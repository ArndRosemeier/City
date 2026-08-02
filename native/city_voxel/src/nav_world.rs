//! Multi-district navigation: field registry, cross-border stitching, and search.
//!
//! Districts stream in and out, so navigation lives above them. Fields are held in
//! slots; the high level portal graph spans every loaded field, which is the first time
//! agents can path out of the district they spawned in.
//!
//! Searching is hierarchical. A portal-level A* produces a corridor of sector
//! components, and a voxel-level A* is then confined to that corridor. Confinement is
//! what keeps the cost bounded with a four figure agent population.

use std::cmp::Ordering;
use std::collections::{BinaryHeap, HashMap, HashSet};

use crate::nav::{
    compute_clearance, compute_sector_links, link_reach, rebuild_all_portals, rebuild_node_index,
    rebuild_portals_for, rebuild_sector_components, rebuild_sector_spans, refresh_links_into,
    LinkParams, NavField, Profile, Solidity, Span, SpanId, VoxelSource, LINK_WALK, NO_COMP, SECTOR,
};

/// How much dearer a straight shortcut may be than the stretch of corridor it replaces,
/// as a fraction of that stretch.
///
/// Zero is nearly right: on ground of one cost a straight line is never dearer than the
/// stepped route between its ends, so staircases collapse without any allowance at all.
/// The allowance is for the corner of a costlier cell clipped in passing, which is not
/// worth a waypoint — without it a corridor running along a curb or past a planter keeps
/// a point per cell.
const SMOOTH_COST_SLACK: f32 = 0.06;
/// Flat allowance in cost-voxels on top of [`SMOOTH_COST_SLACK`], so two line samplings of
/// different lengths never decide a short shortcut on rounding alone.
const SMOOTH_COST_EPS: f32 = 0.3;

/// Slot, sector and span index packed into one key so the search can cross districts.
pub type WorldSpan = u64;

#[inline]
pub fn pack_span(slot: u32, id: SpanId) -> WorldSpan {
    ((slot as u64) << 56) | ((id.sector as u64) << 32) | id.index as u64
}

#[inline]
pub fn unpack_span(key: WorldSpan) -> (u32, SpanId) {
    (
        (key >> 56) as u32,
        SpanId {
            sector: ((key >> 32) & 0x00FF_FFFF) as u32,
            index: (key & 0xFFFF_FFFF) as u32,
        },
    )
}

#[inline]
fn world_node(slot: u32, node: u32) -> u32 {
    (slot << 24) | (node & 0x00FF_FFFF)
}

#[inline]
fn world_sector(slot: u32, sector: u32) -> u32 {
    (slot << 24) | (sector & 0x00FF_FFFF)
}

#[inline]
fn column_key(x: i32, z: i32) -> u64 {
    ((x as u32 as u64) << 32) | z as u32 as u64
}

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------

/// Outcome of a path request. Every failure is distinguishable so the agent layer can
/// escalate deliberately instead of silently standing still.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PathStatus {
    Ok,
    /// Reached the closest reachable span to the goal instead of the goal itself.
    Partial,
    /// A route exists only by destroying something, and the profile allows that.
    Breach,
    /// The agent is not standing anywhere the profile considers navigable.
    NoStart,
    /// The goal is not navigable for this profile.
    NoGoal,
    /// Start and goal are navigable but disconnected.
    Unreachable,
}

impl PathStatus {
    pub fn code(self) -> i32 {
        match self {
            PathStatus::Ok => 0,
            PathStatus::Partial => 1,
            PathStatus::Breach => 2,
            PathStatus::NoStart => 3,
            PathStatus::NoGoal => 4,
            PathStatus::Unreachable => 5,
        }
    }
}

#[derive(Clone, Debug)]
pub struct PathResult {
    pub status: PathStatus,
    /// Corridor in world voxel coordinates, starting at the agent.
    pub points: Vec<[f32; 3]>,
    /// Link kind used to enter each point; [`LINK_WALK`] for ordinary walking.
    pub link_kinds: Vec<u8>,
    /// Points the search produced before smoothing, so the cost of keeping a corner is
    /// measurable rather than argued about.
    pub raw_points: usize,
    pub expanded: usize,
}

impl PathResult {
    fn empty(status: PathStatus, expanded: usize) -> Self {
        Self {
            status,
            points: Vec::new(),
            link_kinds: Vec::new(),
            raw_points: 0,
            expanded,
        }
    }
}

// ---------------------------------------------------------------------------
// Priority queue entry
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, PartialEq)]
struct Ranked(f32, u64);

impl Eq for Ranked {}

impl Ord for Ranked {
    fn cmp(&self, other: &Self) -> Ordering {
        // Reversed so BinaryHeap yields the cheapest node first.
        other
            .0
            .partial_cmp(&self.0)
            .unwrap_or(Ordering::Equal)
            .then_with(|| other.1.cmp(&self.1))
    }
}

impl PartialOrd for Ranked {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

// ---------------------------------------------------------------------------
// World
// ---------------------------------------------------------------------------

struct Slot {
    coord: (i32, i32),
    field: NavField,
}

/// Where the last incremental rebuild spent its microseconds.
///
/// A dirty region is drained against a frame budget, and a budget can only be spent well
/// once it is known which phases scale with the dirty columns and which with the whole
/// district. Measured rather than reasoned about, so the split into budget-sized units is
/// sized against the real numbers.
#[derive(Clone, Copy, Debug, Default)]
pub struct RebuildTiming {
    pub sectors: usize,
    pub spans_us: u64,
    pub clearance_us: u64,
    pub links_us: u64,
    /// The inbound pass, which reaches into the neighbouring sectors.
    pub inbound_us: u64,
    pub components_us: u64,
    /// Node index and portals, both of which touch the whole field.
    pub portals_us: u64,
    pub total_us: u64,
}

/// A directed portal in world space. Intra-field portals are copied in; inter-field
/// ones are discovered where two loaded districts share a border.
#[derive(Clone, Copy, Debug)]
struct WorldPortal {
    from_node: u32,
    to_node: u32,
    span_from: WorldSpan,
    span_to: WorldSpan,
    x: f32,
    y: f32,
    z: f32,
}

pub struct NavWorld {
    pub solidity: Solidity,
    pub link_params: LinkParams,
    /// Metres per voxel, for the world/voxel conversions at the API boundary.
    pub voxel_size: f32,
    slots: Vec<Option<Slot>>,
    coord_slot: HashMap<(i32, i32), u32>,
    profiles: HashMap<i32, Profile>,

    graph_dirty: bool,
    portals: Vec<WorldPortal>,
    node_index: HashMap<u32, u32>,
    node_ids: Vec<u32>,
    /// CSR of the portals *leaving* each node; the graph is directed.
    node_portal_start: Vec<u32>,
    node_portal_list: Vec<u32>,

    /// Columns an agent reported impassable, with the time they expire.
    blocked: HashMap<u64, f64>,
    now: f64,

    /// Monotonic version bumped by every field change, so agents can drop stale paths.
    pub version: u64,
    pub last_expanded: usize,
    pub last_rebuild: RebuildTiming,
}

impl Default for NavWorld {
    fn default() -> Self {
        Self::new()
    }
}

impl NavWorld {
    pub fn new() -> Self {
        Self {
            solidity: Solidity::default(),
            link_params: LinkParams::default(),
            voxel_size: 0.5,
            slots: Vec::new(),
            coord_slot: HashMap::new(),
            profiles: HashMap::new(),
            graph_dirty: true,
            portals: Vec::new(),
            node_index: HashMap::new(),
            node_ids: Vec::new(),
            node_portal_start: Vec::new(),
            node_portal_list: Vec::new(),
            blocked: HashMap::new(),
            now: 0.0,
            version: 1,
            last_expanded: 0,
            last_rebuild: RebuildTiming::default(),
        }
    }

    pub fn set_profile(&mut self, id: i32, profile: Profile) {
        self.profiles.insert(id, profile);
    }

    pub fn profile(&self, id: i32) -> Option<&Profile> {
        self.profiles.get(&id)
    }

    pub fn field_count(&self) -> usize {
        self.slots.iter().filter(|s| s.is_some()).count()
    }

    pub fn field_at(&self, coord: (i32, i32)) -> Option<&NavField> {
        let slot = *self.coord_slot.get(&coord)?;
        self.slots[slot as usize].as_ref().map(|s| &s.field)
    }

    pub fn insert_field(&mut self, coord: (i32, i32), field: NavField) -> u32 {
        if let Some(&existing) = self.coord_slot.get(&coord) {
            self.slots[existing as usize] = Some(Slot { coord, field });
            self.graph_dirty = true;
            self.version += 1;
            return existing;
        }
        let slot = match self.slots.iter().position(|s| s.is_none()) {
            Some(i) => i as u32,
            None => {
                self.slots.push(None);
                (self.slots.len() - 1) as u32
            }
        };
        self.slots[slot as usize] = Some(Slot { coord, field });
        self.coord_slot.insert(coord, slot);
        self.graph_dirty = true;
        self.version += 1;
        slot
    }

    pub fn remove_field(&mut self, coord: (i32, i32)) -> bool {
        let Some(slot) = self.coord_slot.remove(&coord) else {
            return false;
        };
        self.slots[slot as usize] = None;
        self.graph_dirty = true;
        self.version += 1;
        true
    }

    pub fn advance_time(&mut self, now: f64) {
        self.now = now;
        if !self.blocked.is_empty() {
            self.blocked.retain(|_, expiry| *expiry > now);
        }
    }

    /// Mark a column impassable for a while. Used by the agent failure ladder so one
    /// agent's discovery steers the others too.
    pub fn block_column(&mut self, x: i32, z: i32, seconds: f32) {
        self.blocked
            .insert(column_key(x, z), self.now + seconds as f64);
    }

    #[inline]
    fn is_blocked(&self, x: i32, z: i32) -> bool {
        if self.blocked.is_empty() {
            return false;
        }
        self.blocked
            .get(&column_key(x, z))
            .is_some_and(|e| *e > self.now)
    }

    #[inline]
    fn slot_of_column(&self, x: i32, z: i32) -> Option<u32> {
        for (i, slot) in self.slots.iter().enumerate() {
            if let Some(s) = slot {
                if s.field.contains_column(x, z) {
                    return Some(i as u32);
                }
            }
        }
        None
    }

    #[inline]
    fn field_of(&self, slot: u32) -> &NavField {
        &self.slots[slot as usize].as_ref().expect("live slot").field
    }

    #[inline]
    pub fn span_of(&self, key: WorldSpan) -> &Span {
        let (slot, id) = unpack_span(key);
        self.field_of(slot).span(id)
    }

    /// Centre of a span's column at its walking surface, in voxel coordinates.
    #[inline]
    pub fn span_pos(&self, key: WorldSpan) -> [f32; 3] {
        let (slot, id) = unpack_span(key);
        let field = self.field_of(slot);
        let (x, z) = field.span_xz(id);
        let s = field.span(id);
        [x as f32 + 0.5, s.surface_y, z as f32 + 0.5]
    }

    /// Coordinates of every loaded district.
    pub fn district_coords(&self) -> Vec<(i32, i32)> {
        self.slots.iter().flatten().map(|s| s.coord).collect()
    }

    /// Walkable span in a column, searched across whichever field owns it.
    fn step_target(&self, x: i32, z: i32, from_y: f32, profile: &Profile) -> Option<WorldSpan> {
        let slot = self.slot_of_column(x, z)?;
        let field = self.field_of(slot);
        field
            .step_target(x, z, from_y, profile)
            .map(|id| pack_span(slot, id))
    }

    /// Closest span an agent of `profile` could occupy near a world voxel position.
    pub fn nearest_span(
        &self,
        x: f32,
        y: f32,
        z: f32,
        profile: &Profile,
        radius_cells: i32,
    ) -> Option<WorldSpan> {
        let vx = x.floor() as i32;
        let vz = z.floor() as i32;
        let mut best: Option<(WorldSpan, f32)> = None;
        for (i, slot) in self.slots.iter().enumerate() {
            let Some(s) = slot else { continue };
            if let Some((id, d)) = s.field.nearest_span(vx, y, vz, profile, radius_cells) {
                if best.map_or(true, |(_, b)| d < b) {
                    best = Some((pack_span(i as u32, id), d));
                }
            }
        }
        best.map(|(k, _)| k)
    }

    /// Every standable surface in one column within `radius_cells` of `y`.
    ///
    /// Wander picks an XZ probe first, then uses this instead of `nearest_span` so a crypt
    /// floor and the chapel above it are both candidates — nearest_span's vertical weight
    /// would almost always keep the body on its current storey.
    pub fn column_surfaces(
        &self,
        x: f32,
        y: f32,
        z: f32,
        profile: &Profile,
        radius_cells: i32,
    ) -> Vec<[f32; 3]> {
        let wx = x.floor() as i32;
        let wz = z.floor() as i32;
        let Some(slot) = self.slot_of_column(wx, wz) else {
            return Vec::new();
        };
        let field = self.field_of(slot);
        let mut ids: Vec<SpanId> = Vec::new();
        field.column_spans(wx, wz, &mut ids);
        let mut out: Vec<[f32; 3]> = Vec::new();
        let radius = radius_cells as f32;
        for id in ids {
            let s = field.span(id);
            if !profile.accepts(s) {
                continue;
            }
            if (s.surface_y - y).abs() > radius {
                continue;
            }
            out.push([wx as f32 + 0.5, s.surface_y, wz as f32 + 0.5]);
        }
        out
    }

    // -----------------------------------------------------------------------
    // High level graph
    // -----------------------------------------------------------------------

    fn ensure_graph(&mut self) {
        if !self.graph_dirty {
            return;
        }
        self.graph_dirty = false;
        let mut portals: Vec<WorldPortal> = Vec::new();

        for (i, slot) in self.slots.iter().enumerate() {
            let Some(s) = slot else { continue };
            let slot_id = i as u32;
            let field = &s.field;
            for p in &field.portals {
                portals.push(WorldPortal {
                    from_node: world_node(
                        slot_id,
                        field.node_base[p.from_sector as usize] + p.from_comp as u32,
                    ),
                    to_node: world_node(
                        slot_id,
                        field.node_base[p.to_sector as usize] + p.to_comp as u32,
                    ),
                    span_from: pack_span(slot_id, p.span_from),
                    span_to: pack_span(slot_id, p.span_to),
                    x: p.x,
                    y: p.y,
                    z: p.z,
                });
            }
        }

        // Stitch districts that share a border and are both loaded.
        let coords: Vec<((i32, i32), u32)> = self
            .coord_slot
            .iter()
            .map(|(c, s)| (*c, *s))
            .collect();
        for (coord, slot_a) in &coords {
            for (dx, dz) in [(1i32, 0i32), (0, 1)] {
                let other = (coord.0 + dx, coord.1 + dz);
                let Some(&slot_b) = self.coord_slot.get(&other) else {
                    continue;
                };
                // Both ways: the shared edge is only symmetric where the ground is.
                self.stitch_border(*slot_a, slot_b, &mut portals);
                self.stitch_border(slot_b, *slot_a, &mut portals);
            }
        }

        self.portals = portals;
        self.rebuild_node_csr();
    }

    /// Directed portals leading from district `slot_a` into `slot_b` along their shared
    /// edge. Call it once per ordered pair; a crossing that only works one way stays
    /// one way.
    fn stitch_border(&self, slot_a: u32, slot_b: u32, out: &mut Vec<WorldPortal>) {
        let base = Profile::base();
        let fa = self.field_of(slot_a);
        let fb = self.field_of(slot_b);

        // The shared edge is wherever A's last column touches B's first, on either axis.
        let (ax0, ax1) = (fa.origin_x, fa.origin_x + fa.size_x - 1);
        let (az0, az1) = (fa.origin_z, fa.origin_z + fa.size_z - 1);
        let (bx0, bx1) = (fb.origin_x, fb.origin_x + fb.size_x - 1);
        let (bz0, bz1) = (fb.origin_z, fb.origin_z + fb.size_z - 1);

        let mut strip: Vec<(i32, i32, i32, i32)> = Vec::new();
        if ax1 + 1 == bx0 {
            let z_lo = az0.max(bz0);
            let z_hi = az1.min(bz1);
            for z in z_lo..=z_hi {
                strip.push((ax1, z, bx0, z));
            }
        } else if bx1 + 1 == ax0 {
            let z_lo = az0.max(bz0);
            let z_hi = az1.min(bz1);
            for z in z_lo..=z_hi {
                strip.push((ax0, z, bx1, z));
            }
        } else if az1 + 1 == bz0 {
            let x_lo = ax0.max(bx0);
            let x_hi = ax1.min(bx1);
            for x in x_lo..=x_hi {
                strip.push((x, az1, x, bz0));
            }
        } else if bz1 + 1 == az0 {
            let x_lo = ax0.max(bx0);
            let x_hi = ax1.min(bx1);
            for x in x_lo..=x_hi {
                strip.push((x, az0, x, bz1));
            }
        } else {
            return;
        }

        let mut best: HashMap<(u32, u32), (WorldSpan, WorldSpan, f32, f32, f32, f32)> =
            HashMap::new();
        let mut ids: Vec<SpanId> = Vec::new();
        for (ax, az, bx, bz) in strip {
            fa.column_spans(ax, az, &mut ids);
            for &id in &ids {
                let s = *fa.span(id);
                let node_a_local = fa.node_of(id);
                if node_a_local == u32::MAX {
                    continue;
                }
                let Some(nid) = fb.step_target(bx, bz, s.surface_y, &base) else {
                    continue;
                };
                let node_b_local = fb.node_of(nid);
                if node_b_local == u32::MAX {
                    continue;
                }
                let na = world_node(slot_a, node_a_local);
                let nb = world_node(slot_b, node_b_local);
                let score = (fb.span(nid).surface_y - s.surface_y).abs();
                let entry = best.entry((na, nb)).or_insert((
                    pack_span(slot_a, id),
                    pack_span(slot_b, nid),
                    f32::MAX,
                    0.0,
                    0.0,
                    0.0,
                ));
                if score < entry.2 {
                    *entry = (
                        pack_span(slot_a, id),
                        pack_span(slot_b, nid),
                        score,
                        (ax as f32 + bx as f32) * 0.5 + 0.5,
                        (s.surface_y + fb.span(nid).surface_y) * 0.5,
                        (az as f32 + bz as f32) * 0.5 + 0.5,
                    );
                }
            }
        }

        for ((from_node, to_node), (span_from, span_to, _, x, y, z)) in best {
            out.push(WorldPortal {
                from_node,
                to_node,
                span_from,
                span_to,
                x,
                y,
                z,
            });
        }
    }

    fn rebuild_node_csr(&mut self) {
        self.node_index.clear();
        self.node_ids.clear();
        // Sink nodes are registered too, with an empty out-list, so a lookup on them is
        // an ordinary dead end rather than a missing entry.
        for p in &self.portals {
            for n in [p.from_node, p.to_node] {
                if !self.node_index.contains_key(&n) {
                    self.node_index.insert(n, self.node_ids.len() as u32);
                    self.node_ids.push(n);
                }
            }
        }
        let count = self.node_ids.len();
        let mut counts = vec![0u32; count + 1];
        for p in &self.portals {
            counts[self.node_index[&p.from_node] as usize] += 1;
        }
        self.node_portal_start = vec![0; count + 1];
        let mut acc = 0u32;
        for i in 0..count {
            self.node_portal_start[i] = acc;
            acc += counts[i];
        }
        self.node_portal_start[count] = acc;
        let mut cursor = self.node_portal_start.clone();
        self.node_portal_list = vec![0; acc as usize];
        for (pi, p) in self.portals.iter().enumerate() {
            let a = self.node_index[&p.from_node] as usize;
            self.node_portal_list[cursor[a] as usize] = pi as u32;
            cursor[a] += 1;
        }
    }

    /// Portal indices leaving a node.
    #[inline]
    fn out_portals(&self, node: u32) -> &[u32] {
        let Some(&dense) = self.node_index.get(&node) else {
            return &[];
        };
        let lo = self.node_portal_start[dense as usize] as usize;
        let hi = self.node_portal_start[dense as usize + 1] as usize;
        &self.node_portal_list[lo..hi]
    }

    #[inline]
    fn node_of_span(&self, key: WorldSpan) -> u32 {
        let (slot, id) = unpack_span(key);
        let field = self.field_of(slot);
        let local = field.node_of(id);
        if local == u32::MAX {
            return u32::MAX;
        }
        world_node(slot, local)
    }

    #[inline]
    fn sector_of_span(&self, key: WorldSpan) -> u32 {
        let (slot, id) = unpack_span(key);
        world_sector(slot, id.sector)
    }

    /// Portal-level A* returning the sectors the corridor passes through.
    ///
    /// The graph is directed: a portal is entered at its `from_node` and left at its
    /// `to_node`, and the only successors of a portal are the ones leaving where it
    /// lands. That is what stops the coarse search riding a one-way drop backwards.
    fn corridor(&self, start: WorldSpan, goal: WorldSpan, limit: usize) -> Option<HashSet<u32>> {
        let start_node = self.node_of_span(start);
        let goal_node = self.node_of_span(goal);
        if start_node == u32::MAX || goal_node == u32::MAX {
            return None;
        }
        if start_node == goal_node {
            let mut set = HashSet::new();
            set.insert(self.sector_of_span(start));
            set.insert(self.sector_of_span(goal));
            return Some(set);
        }
        if !self.node_index.contains_key(&start_node) || !self.node_index.contains_key(&goal_node)
        {
            // A node no portal touches cannot be reached hierarchically.
            return None;
        }

        let goal_pos = self.span_pos(goal);
        let start_pos = self.span_pos(start);
        let h = |p: &WorldPortal| -> f32 {
            let dx = p.x - goal_pos[0];
            let dy = p.y - goal_pos[1];
            let dz = p.z - goal_pos[2];
            (dx * dx + dz * dz).sqrt() + dy.abs() * 0.5
        };

        let mut open: BinaryHeap<Ranked> = BinaryHeap::new();
        let mut g: HashMap<u32, f32> = HashMap::new();
        let mut came: HashMap<u32, u32> = HashMap::new();
        let mut goal_portal: Option<u32> = None;

        // Seed with every portal leaving the start node.
        for &pi in self.out_portals(start_node) {
            let p = &self.portals[pi as usize];
            let dx = p.x - start_pos[0];
            let dz = p.z - start_pos[2];
            let cost = (dx * dx + dz * dz).sqrt();
            if g.get(&pi).is_none_or(|&old| cost < old) {
                g.insert(pi, cost);
                open.push(Ranked(cost + h(p), pi as u64));
            }
        }

        let mut expanded = 0usize;
        while let Some(Ranked(_, raw)) = open.pop() {
            let pi = raw as u32;
            expanded += 1;
            if expanded > limit {
                break;
            }
            let p = self.portals[pi as usize];
            let cur_g = g[&pi];
            if p.to_node == goal_node {
                goal_portal = Some(pi);
                break;
            }
            for &qi in self.out_portals(p.to_node) {
                if qi == pi {
                    continue;
                }
                let q = &self.portals[qi as usize];
                let dx = q.x - p.x;
                let dy = q.y - p.y;
                let dz = q.z - p.z;
                let step = (dx * dx + dz * dz).sqrt() + dy.abs() * 0.5;
                let ng = cur_g + step;
                if g.get(&qi).is_none_or(|&old| ng < old - 1e-4) {
                    g.insert(qi, ng);
                    came.insert(qi, pi);
                    open.push(Ranked(ng + h(q), qi as u64));
                }
            }
        }

        let mut set: HashSet<u32> = HashSet::new();
        set.insert(self.sector_of_span(start));
        set.insert(self.sector_of_span(goal));
        let mut cur = goal_portal?;
        loop {
            let p = &self.portals[cur as usize];
            set.insert(self.sector_of_span(p.span_from));
            set.insert(self.sector_of_span(p.span_to));
            match came.get(&cur) {
                Some(&prev) => cur = prev,
                None => break,
            }
        }
        Some(set)
    }

    // -----------------------------------------------------------------------
    // Fine search
    // -----------------------------------------------------------------------

    fn neighbours(
        &self,
        key: WorldSpan,
        profile: &Profile,
        out: &mut Vec<(WorldSpan, f32, u8)>,
    ) {
        out.clear();
        let (slot, id) = unpack_span(key);
        let field = self.field_of(slot);
        let s = *field.span(id);
        let (wx, wz) = field.span_xz(id);

        // Straight moves first; diagonals only when both flanks are open, so agents do
        // not clip corners of buildings.
        let mut open_dir = [false; 4];
        const DIRS: [(i32, i32); 4] = [(-1, 0), (1, 0), (0, -1), (0, 1)];
        for (i, (dx, dz)) in DIRS.iter().enumerate() {
            let nx = wx + dx;
            let nz = wz + dz;
            if self.is_blocked(nx, nz) {
                continue;
            }
            let Some(nkey) = self.step_target(nx, nz, s.surface_y, profile) else {
                continue;
            };
            open_dir[i] = true;
            let ns = self.span_of(nkey);
            let climb = (ns.surface_y - s.surface_y).abs();
            let cost = profile.cost_of(ns) + climb * 0.5;
            out.push((nkey, cost, LINK_WALK));
        }

        const DIAG: [(i32, i32, usize, usize); 4] = [
            (-1, -1, 0, 2),
            (1, -1, 1, 2),
            (-1, 1, 0, 3),
            (1, 1, 1, 3),
        ];
        for (dx, dz, a, b) in DIAG {
            if !open_dir[a] || !open_dir[b] {
                continue;
            }
            let nx = wx + dx;
            let nz = wz + dz;
            if self.is_blocked(nx, nz) {
                continue;
            }
            let Some(nkey) = self.step_target(nx, nz, s.surface_y, profile) else {
                continue;
            };
            let ns = self.span_of(nkey);
            let climb = (ns.surface_y - s.surface_y).abs();
            let cost = profile.cost_of(ns) * std::f32::consts::SQRT_2 + climb * 0.5;
            out.push((nkey, cost, LINK_WALK));
        }

        // Baked traversals: climbing a facade, dropping off a roof, clearing a gap.
        if let Some(links) = field.sectors[id.sector as usize].links.get(&id.index) {
            for link in links {
                if !profile.accepts_link(link.kind) {
                    continue;
                }
                if self.is_blocked(link.to_x, link.to_z) {
                    continue;
                }
                let target = field.span(link.to);
                if !profile.accepts(target) {
                    continue;
                }
                out.push((pack_span(slot, link.to), link.cost, link.kind));
            }
        }
    }

    #[inline]
    fn heuristic(&self, key: WorldSpan, goal_pos: [f32; 3]) -> f32 {
        let p = self.span_pos(key);
        let dx = (p[0] - goal_pos[0]).abs();
        let dz = (p[2] - goal_pos[2]).abs();
        let dy = (p[1] - goal_pos[1]).abs();
        // Octile distance keeps the estimate admissible against diagonal moves.
        let (lo, hi) = if dx < dz { (dx, dz) } else { (dz, dx) };
        hi + (std::f32::consts::SQRT_2 - 1.0) * lo + dy * 0.5
    }

    fn fine_search(
        &self,
        start: WorldSpan,
        goal: WorldSpan,
        profile: &Profile,
        corridor: Option<&HashSet<u32>>,
        budget: usize,
    ) -> (Option<Vec<(WorldSpan, u8)>>, WorldSpan, usize) {
        let goal_pos = self.span_pos(goal);
        let mut open: BinaryHeap<Ranked> = BinaryHeap::new();
        let mut g: HashMap<WorldSpan, f32> = HashMap::new();
        let mut came: HashMap<WorldSpan, (WorldSpan, u8)> = HashMap::new();
        let mut nbrs: Vec<(WorldSpan, f32, u8)> = Vec::with_capacity(12);

        g.insert(start, 0.0);
        open.push(Ranked(self.heuristic(start, goal_pos), start));

        let mut best_key = start;
        let mut best_h = self.heuristic(start, goal_pos);
        let mut expanded = 0usize;
        let mut found = false;

        while let Some(Ranked(_, key)) = open.pop() {
            if key == goal {
                found = true;
                best_key = goal;
                break;
            }
            expanded += 1;
            if expanded > budget {
                break;
            }
            let cur_g = g[&key];
            self.neighbours(key, profile, &mut nbrs);
            for &(nkey, step, kind) in &nbrs {
                if let Some(set) = corridor {
                    if nkey != goal && !set.contains(&self.sector_of_span(nkey)) {
                        continue;
                    }
                }
                let ng = cur_g + step;
                if g.get(&nkey).is_none_or(|&old| ng < old - 1e-4) {
                    g.insert(nkey, ng);
                    came.insert(nkey, (key, kind));
                    let h = self.heuristic(nkey, goal_pos);
                    if h < best_h {
                        best_h = h;
                        best_key = nkey;
                    }
                    open.push(Ranked(ng + h, nkey));
                }
            }
        }

        let target = if found { goal } else { best_key };
        if target == start && !found {
            return (None, start, expanded);
        }
        let mut chain: Vec<(WorldSpan, u8)> = Vec::new();
        let mut cur = target;
        let mut guard = 0usize;
        loop {
            guard += 1;
            if guard > 1_000_000 {
                // A cycle here would mean corrupt parent links; refuse rather than hang.
                return (None, start, expanded);
            }
            match came.get(&cur) {
                Some(&(prev, kind)) => {
                    chain.push((cur, kind));
                    cur = prev;
                }
                None => {
                    chain.push((cur, LINK_WALK));
                    break;
                }
            }
        }
        chain.reverse();
        (Some(chain), target, expanded)
    }

    // -----------------------------------------------------------------------
    // Smoothing
    // -----------------------------------------------------------------------

    /// Surface cost of walking the straight line between two spans, in the units the fine
    /// search charges: the profile's multiplier per voxel of ground covered. `None` when an
    /// agent cannot walk that line at all.
    fn line_cost(&self, a: WorldSpan, b: WorldSpan, profile: &Profile) -> Option<f32> {
        let pa = self.span_pos(a);
        let pb = self.span_pos(b);
        let dx = pb[0] - pa[0];
        let dz = pb[2] - pa[2];
        let dist = (dx * dx + dz * dz).sqrt();
        if dist < 0.001 {
            return Some(0.0);
        }
        let steps = (dist * 2.0).ceil() as i32;
        let seg = dist / steps as f32;
        let mut prev_y = pa[1];
        let mut cost = 0.0f32;
        for i in 1..=steps {
            let t = i as f32 / steps as f32;
            let x = pa[0] + dx * t;
            let z = pa[2] + dz * t;
            let vx = x.floor() as i32;
            let vz = z.floor() as i32;
            if self.is_blocked(vx, vz) {
                return None;
            }
            let key = self.step_target(vx, vz, prev_y, profile)?;
            let s = self.span_of(key);
            prev_y = s.surface_y;
            cost += profile.cost_of(s) * seg;
        }
        // Reject shortcuts that end on a different level than the node they replace.
        if (prev_y - pb[1]).abs() > profile.max_step.max(profile.max_drop) {
            return None;
        }
        Some(cost)
    }

    /// Drop intermediate corridor points a straight walk already covers *at the price the
    /// corridor paid for them*. Links are never smoothed away: a climb or a jump is a
    /// discrete action for the motor.
    ///
    /// Cost is the whole difficulty here. String-pulling on walkability alone throws away
    /// exactly what the surface costs bought: A* sends a pedestrian round to a painted
    /// crossing, every intermediate point of that detour is individually skippable across
    /// bare tarmac, and the corridor collapses onto the straight line the cost table exists
    /// to prevent. Measuring a shortcut with the same sampler as the stretch it replaces
    /// keeps the trade instead of choosing a side of it: on ground of one cost the straight
    /// line is never the dearer of the two, so a staircase of per-cell waypoints still
    /// collapses to its two ends.
    fn smooth(&self, chain: &[(WorldSpan, u8)], profile: &Profile) -> Vec<(WorldSpan, u8)> {
        if chain.len() <= 2 {
            return chain.to_vec();
        }
        let mut out: Vec<(WorldSpan, u8)> = Vec::with_capacity(chain.len());
        out.push(chain[0]);
        let mut anchor = 0usize;
        // Cost of the corridor from `anchor` to the last point the shortcut swallowed, so
        // the next candidate has something comparable to be measured against.
        let mut walked = 0.0f32;
        let mut i = 1usize;
        while i < chain.len() {
            if chain[i].1 != LINK_WALK {
                // Keep both ends of the link exactly.
                if anchor != i - 1 {
                    out.push(chain[i - 1]);
                }
                out.push(chain[i]);
                anchor = i;
                walked = 0.0;
                i += 1;
                continue;
            }
            let step = self.line_cost(chain[i - 1].0, chain[i].0, profile);
            let shortcut = self.line_cost(chain[anchor].0, chain[i].0, profile);
            let skip = match (step, shortcut) {
                (Some(step), Some(shortcut)) => {
                    let corridor = walked + step;
                    let cheap = shortcut <= corridor * (1.0 + SMOOTH_COST_SLACK) + SMOOTH_COST_EPS;
                    if cheap {
                        walked = corridor;
                    }
                    cheap
                }
                // A straight line that is not walkable at all is not a shortcut either.
                _ => false,
            };
            if !skip {
                if anchor == i - 1 {
                    // Not even the raw step is a straight walk. `neighbours` only tests the
                    // cell it steps into, while the line sampler covers the take-off cell as
                    // well, so a search that started on a blocked column produces exactly
                    // this. Keep the step verbatim; retrying the same pair never terminates.
                    out.push(chain[i]);
                    anchor = i;
                    walked = 0.0;
                    i += 1;
                    continue;
                }
                out.push(chain[i - 1]);
                anchor = i - 1;
                walked = 0.0;
                continue;
            }
            if i == chain.len() - 1 {
                out.push(chain[i]);
            }
            i += 1;
        }
        if out.last().map(|p| p.0) != Some(chain[chain.len() - 1].0) {
            out.push(chain[chain.len() - 1]);
        }
        out
    }

    // -----------------------------------------------------------------------
    // Public query
    // -----------------------------------------------------------------------

    /// Path in world voxel coordinates. `from` and `to` are voxel-space positions.
    pub fn find_path(
        &mut self,
        profile_id: i32,
        from: [f32; 3],
        to: [f32; 3],
        budget: usize,
    ) -> PathResult {
        self.ensure_graph();
        let Some(profile) = self.profiles.get(&profile_id).cloned() else {
            return PathResult::empty(PathStatus::NoStart, 0);
        };

        let Some(start) = self.nearest_span(from[0], from[1], from[2], &profile, 6) else {
            return PathResult::empty(PathStatus::NoStart, 0);
        };
        let goal = match self.nearest_span(to[0], to[1], to[2], &profile, 8) {
            Some(g) => g,
            None => {
                if profile.can_break {
                    return self.breach_path(from, to);
                }
                return PathResult::empty(PathStatus::NoGoal, 0);
            }
        };

        if start == goal {
            let p = self.span_pos(start);
            return PathResult {
                status: PathStatus::Ok,
                points: vec![[from[0], from[1], from[2]], p],
                link_kinds: vec![LINK_WALK, LINK_WALK],
                raw_points: 2,
                expanded: 0,
            };
        }

        let sp = self.span_pos(start);
        let gp = self.span_pos(goal);
        let straight = ((sp[0] - gp[0]).powi(2) + (sp[2] - gp[2]).powi(2)).sqrt();

        // The hierarchy is built from the permissive base profile, so when it finds no
        // route at all no body can have one. That is a definite answer, and much cheaper
        // than letting the fine search flood a sealed pocket first.
        let corridor = if self.node_of_span(start) == self.node_of_span(goal) {
            None
        } else {
            match self.corridor(start, goal, 20_000) {
                None => {
                    if profile.can_break {
                        return self.breach_path(from, to);
                    }
                    return PathResult::empty(PathStatus::Unreachable, 0);
                }
                // Short hops skip the corridor filter: confining the search costs more
                // than it saves once the goal is a sector or two away.
                Some(set) if straight > (SECTOR as f32) * 1.5 => Some(set),
                Some(_) => None,
            }
        };

        let (mut chain, mut reached, mut expanded) =
            self.fine_search(start, goal, &profile, corridor.as_ref(), budget);

        // A corridor built from the permissive base profile can be too tight for a real
        // body. Retry once without it rather than reporting a false dead end.
        if corridor.is_some() && reached != goal {
            let (c2, r2, e2) = self.fine_search(start, goal, &profile, None, budget * 2);
            expanded += e2;
            if r2 == goal || chain.is_none() {
                chain = c2;
                reached = r2;
            }
        }

        self.last_expanded = expanded;
        let Some(chain) = chain else {
            if profile.can_break {
                return self.breach_path(from, to);
            }
            return PathResult::empty(PathStatus::Unreachable, expanded);
        };

        let raw_points = chain.len() + 1;
        let smoothed = self.smooth(&chain, &profile);
        let mut points: Vec<[f32; 3]> = Vec::with_capacity(smoothed.len() + 1);
        let mut kinds: Vec<u8> = Vec::with_capacity(smoothed.len() + 1);
        points.push([from[0], from[1], from[2]]);
        kinds.push(LINK_WALK);
        for (key, kind) in &smoothed {
            points.push(self.span_pos(*key));
            kinds.push(*kind);
        }

        let status = if reached == goal {
            PathStatus::Ok
        } else if profile.can_break {
            // Walk as far as the route allows, then smash the rest.
            points.push([to[0], to[1], to[2]]);
            kinds.push(LINK_WALK);
            PathStatus::Breach
        } else {
            PathStatus::Partial
        };
        PathResult {
            status,
            points,
            link_kinds: kinds,
            raw_points,
            expanded,
        }
    }

    /// A straight run for agents that solve obstacles by destroying them.
    fn breach_path(&self, from: [f32; 3], to: [f32; 3]) -> PathResult {
        let dx = to[0] - from[0];
        let dz = to[2] - from[2];
        let dist = (dx * dx + dz * dz).sqrt();
        let steps = ((dist / 8.0).ceil() as i32).max(1);
        let mut points = Vec::with_capacity(steps as usize + 1);
        let mut kinds = Vec::with_capacity(steps as usize + 1);
        for i in 0..=steps {
            let t = i as f32 / steps as f32;
            points.push([
                from[0] + dx * t,
                from[1] + (to[1] - from[1]) * t,
                from[2] + dz * t,
            ]);
            kinds.push(LINK_WALK);
        }
        let raw_points = points.len();
        PathResult {
            status: PathStatus::Breach,
            points,
            link_kinds: kinds,
            raw_points,
            expanded: 0,
        }
    }

    /// Is there any route at all, ignoring path detail? Used by goal selection so agents
    /// never commit to a destination they cannot reach.
    pub fn reachable(&mut self, profile_id: i32, from: [f32; 3], to: [f32; 3]) -> bool {
        self.ensure_graph();
        let Some(profile) = self.profiles.get(&profile_id).cloned() else {
            return false;
        };
        let (Some(start), Some(goal)) = (
            self.nearest_span(from[0], from[1], from[2], &profile, 6),
            self.nearest_span(to[0], to[1], to[2], &profile, 8),
        ) else {
            return false;
        };
        if self.node_of_span(start) == self.node_of_span(goal) {
            return true;
        }
        self.corridor(start, goal, 20_000).is_some()
    }

    // -----------------------------------------------------------------------
    // Incremental rebuild
    // -----------------------------------------------------------------------

    /// Rebuild the sectors a voxel box fully covers, from fresh material data.
    ///
    /// A sector is rebuilt only when the box carries *every* one of its columns —
    /// rescanning half a sector against the outside-the-box fallback would carve holes
    /// into the field. Everything the box carries beyond those sectors is context: the
    /// climb probes and jump arcs read it, and the links neighbouring sectors point back
    /// into the rebuilt ones are recomputed from it. `link_reach` columns of that
    /// context are required on every side that is not a district edge, and the caller is
    /// told loudly when it did not supply them.
    pub fn rebuild_box<S: VoxelSource>(
        &mut self,
        coord: (i32, i32),
        min_x: i32,
        min_z: i32,
        max_x: i32,
        max_z: i32,
        src: &S,
    ) -> Result<usize, String> {
        let Some(&slot) = self.coord_slot.get(&coord) else {
            return Err(format!("no district registered at {coord:?}"));
        };
        let solidity = self.solidity.clone();
        let params = self.link_params;
        let reach = link_reach(&params);
        let Some(slot_ref) = self.slots[slot as usize].as_mut() else {
            return Err(format!("district {coord:?} has no field in its slot"));
        };
        let field = &mut slot_ref.field;

        let x_last = field.origin_x + field.size_x - 1;
        let z_last = field.origin_z + field.size_z - 1;
        let mut touched: Vec<usize> = Vec::new();
        let mut short: Option<String> = None;
        for si in 0..field.sectors.len() {
            let (x0, z0, sx, sz) = {
                let s = &field.sectors[si];
                (s.x0, s.z0, s.sx, s.sz)
            };
            let (x1, z1) = (x0 + sx - 1, z0 + sz - 1);
            if x0 < min_x || z0 < min_z || x1 > max_x || z1 > max_z {
                continue;
            }
            touched.push(si);
            if min_x > (x0 - reach).max(field.origin_x)
                || max_x < (x1 + reach).min(x_last)
                || min_z > (z0 - reach).max(field.origin_z)
                || max_z < (z1 + reach).min(z_last)
            {
                short = Some(format!(
                    "sector x {x0}..{x1} z {z0}..{z1} needs {reach} columns of context, \
                     the box only spans x {min_x}..{max_x} z {min_z}..{max_z}"
                ));
            }
        }
        if let Some(why) = short {
            return Err(why);
        }
        if touched.is_empty() {
            return Err(format!(
                "the box x {min_x}..{max_x} z {min_z}..{max_z} covers no whole sector of {coord:?}"
            ));
        }

        let mut timing = RebuildTiming {
            sectors: touched.len(),
            ..RebuildTiming::default()
        };
        let started = std::time::Instant::now();
        let mut phase = started;
        let lap = |phase: &mut std::time::Instant| -> u64 {
            let now = std::time::Instant::now();
            let us = now.duration_since(*phase).as_micros() as u64;
            *phase = now;
            us
        };

        for &si in &touched {
            rebuild_sector_spans(field, si, src, &solidity);
        }
        timing.spans_us = lap(&mut phase);
        // Clearance is geodesic, so the columns around the change have to be refreshed
        // too — but only as far as the distance transform saturates at, because a source
        // further away than that cannot lower a value below the cap it already reads.
        let halo = 0;
        let (mut cx0, mut cz0, mut cx1, mut cz1) = (i32::MAX, i32::MAX, i32::MIN, i32::MIN);
        for &si in &touched {
            let s = &field.sectors[si];
            cx0 = cx0.min(s.x0);
            cz0 = cz0.min(s.z0);
            cx1 = cx1.max(s.x0 + s.sx - 1);
            cz1 = cz1.max(s.z0 + s.sz - 1);
        }
        compute_clearance(
            field,
            Some((cx0 - halo, cz0 - halo, cx1 + halo, cz1 + halo)),
        );
        timing.clearance_us = lap(&mut phase);
        // Links first: components treat them as connectivity, so stale links would
        // relabel the sector against a world that no longer exists. The inbound pass is
        // what keeps the neighbours' links from naming spans this rebuild just deleted.
        for &si in &touched {
            compute_sector_links(field, si, src, &solidity, &params);
        }
        timing.links_us = lap(&mut phase);
        refresh_links_into(field, &touched, src, &solidity, &params);
        timing.inbound_us = lap(&mut phase);
        for &si in &touched {
            rebuild_sector_components(field, si);
        }
        timing.components_us = lap(&mut phase);
        rebuild_node_index(field);
        rebuild_portals_for(field, &touched);
        timing.portals_us = lap(&mut phase);
        field.version += 1;

        timing.total_us = started.elapsed().as_micros() as u64;
        self.last_rebuild = timing;
        self.graph_dirty = true;
        self.version += 1;
        Ok(touched.len())
    }

    /// Full portal rebuild, used after wholesale changes.
    pub fn refresh_field(&mut self, coord: (i32, i32)) {
        let Some(&slot) = self.coord_slot.get(&coord) else {
            return;
        };
        let Some(slot_ref) = self.slots[slot as usize].as_mut() else {
            return;
        };
        rebuild_node_index(&mut slot_ref.field);
        rebuild_all_portals(&mut slot_ref.field);
        self.graph_dirty = true;
        self.version += 1;
    }

    /// Debug view of every span near a point, for the navigation overlay.
    pub fn debug_spans(
        &self,
        centre: [f32; 3],
        radius_cells: i32,
        out: &mut Vec<(f32, f32, f32, u8, u8, u8)>,
    ) {
        out.clear();
        let cx = centre[0].floor() as i32;
        let cz = centre[2].floor() as i32;
        let mut ids: Vec<SpanId> = Vec::new();
        for z in (cz - radius_cells)..=(cz + radius_cells) {
            for x in (cx - radius_cells)..=(cx + radius_cells) {
                let Some(slot) = self.slot_of_column(x, z) else {
                    continue;
                };
                let field = self.field_of(slot);
                field.column_spans(x, z, &mut ids);
                for &id in &ids {
                    let s = field.span(id);
                    let comp = field.sectors[id.sector as usize].span_comp[id.index as usize];
                    out.push((
                        x as f32 + 0.5,
                        s.surface_y,
                        z as f32 + 0.5,
                        s.clearance,
                        s.headroom,
                        if comp == NO_COMP { 255 } else { (comp % 255) as u8 },
                    ));
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::nav::{bake_field, SOL_PASSABLE, SOL_SOLID};

    fn solidity() -> Solidity {
        let mut sol = Solidity::default();
        sol.class[0] = SOL_PASSABLE;
        sol.class[3] = SOL_SOLID;
        sol.climbable[3] = true;
        sol.destructible[3] = true;
        sol
    }

    struct Ground;
    impl VoxelSource for Ground {
        fn mat(&self, _x: i32, y: i32, _z: i32) -> u16 {
            if y <= 0 {
                3
            } else {
                0
            }
        }
    }

    /// Flat ground with a full-height wall that has one doorway in it.
    struct Walled {
        wall_x: i32,
        door_z: i32,
    }
    impl VoxelSource for Walled {
        fn mat(&self, x: i32, y: i32, z: i32) -> u16 {
            if y <= 0 {
                return 3;
            }
            if x == self.wall_x && y <= 8 && z != self.door_z {
                return 3;
            }
            0
        }
    }

    fn world_with(field: NavField) -> NavWorld {
        let mut w = NavWorld::new();
        w.solidity = solidity();
        w.set_profile(
            0,
            Profile {
                radius_cells: 0,
                height_cells: 3,
                ..Profile::default()
            },
        );
        w.insert_field((0, 0), field);
        w
    }

    #[test]
    fn path_across_open_ground() {
        let sol = solidity();
        let field = bake_field(&Ground, &sol, 0, 0, 60, 60, 0, 12, &LinkParams::default());
        let mut w = world_with(field);
        let r = w.find_path(0, [2.0, 1.0, 2.0], [55.0, 1.0, 55.0], 20_000);
        assert_eq!(r.status, PathStatus::Ok);
        assert!(r.points.len() >= 2);
        // Smoothing has to keep smoothing: a diagonal run over ground of one cost is a
        // straight line, and paying attention to cost must not turn it into a staircase.
        assert!(
            r.points.len() <= 6,
            "a straight run over uniform ground came back as {} points",
            r.points.len()
        );
        let last = *r.points.last().unwrap();
        assert!((last[0] - 55.5).abs() < 2.0 && (last[2] - 55.5).abs() < 2.0);
    }

    /// A street: pavement, a carriageway with one painted crossing in it, pavement. Costs
    /// are the shipping pedestrian ones, so what this pins is the shipped behaviour.
    struct Street;
    impl Street {
        const ROAD_Z0: i32 = 14;
        const ROAD_Z1: i32 = 30;
        const WALK_X0: i32 = 30;
        const WALK_X1: i32 = 36;
        /// Far enough off the crossing that a corridor ignoring cost crosses bare asphalt.
        const PAIR_X: f32 = 38.5;
        const PAVEMENT: u16 = 3;
        const ASPHALT: u16 = 6;
        const CROSSWALK: u16 = 7;
    }
    impl VoxelSource for Street {
        fn mat(&self, x: i32, y: i32, z: i32) -> u16 {
            if y > 0 {
                return 0;
            }
            if !(Street::ROAD_Z0..Street::ROAD_Z1).contains(&z) {
                return Street::PAVEMENT;
            }
            if (Street::WALK_X0..Street::WALK_X1).contains(&x) {
                return Street::CROSSWALK;
            }
            Street::ASPHALT
        }
    }

    /// Where a corridor passes the middle of the carriageway, in voxels.
    fn crossed_road_at(points: &[[f32; 3]]) -> Option<f32> {
        let mid = (Street::ROAD_Z0 + Street::ROAD_Z1) as f32 * 0.5;
        for pair in points.windows(2) {
            let (a, b) = (pair[0], pair[1]);
            if (a[2] - mid) * (b[2] - mid) > 0.0 {
                continue;
            }
            if (a[2] - b[2]).abs() < 1e-4 {
                return Some(a[0]);
            }
            return Some(a[0] + (b[0] - a[0]) * (mid - a[2]) / (b[2] - a[2]));
        }
        None
    }

    /// The corridor a cost table pays for has to survive smoothing.
    ///
    /// `neighbours` charges a pedestrian 2.5x for asphalt against 1.25x for a crossing, so
    /// the fine search does detour to the paint — and string-pulling on walkability alone
    /// then dropped every point of that detour, because on flat tarmac each one is
    /// individually skippable. `ped_goal_provider.gd` walked errands through a crossing's
    /// three nodes to work around exactly this.
    #[test]
    fn a_priced_detour_across_a_road_survives_smoothing() {
        let sol = solidity();
        let field = bake_field(&Street, &sol, 0, 0, 84, 44, 0, 10, &LinkParams::default());
        let mut w = NavWorld::new();
        w.solidity = sol;
        let mut costs = vec![1.0f32; crate::materials::COUNT as usize];
        costs[Street::ASPHALT as usize] = 2.5;
        costs[Street::CROSSWALK as usize] = 1.25;
        w.set_profile(
            0,
            Profile {
                radius_cells: 0,
                height_cells: 3,
                surface_cost: costs,
                ..Profile::default()
            },
        );
        // The same body with no opinion about surfaces, so the detour is attributable to
        // the cost table and not to the geometry.
        w.set_profile(
            1,
            Profile {
                radius_cells: 0,
                height_cells: 3,
                ..Profile::default()
            },
        );
        w.insert_field((0, 0), field);

        let from = [Street::PAIR_X, 1.0, 8.5];
        let to = [Street::PAIR_X, 1.0, 36.5];
        let ped = w.find_path(0, from, to, 120_000);
        assert_eq!(ped.status, PathStatus::Ok, "crossing the street is walkable");
        let flat = w.find_path(1, from, to, 120_000);
        assert_eq!(flat.status, PathStatus::Ok);

        let ped_x = crossed_road_at(&ped.points).expect("the corridor has to cross the road");
        let flat_x = crossed_road_at(&flat.points).expect("the corridor has to cross the road");
        assert!(
            ped_x >= Street::WALK_X0 as f32 && ped_x <= Street::WALK_X1 as f32,
            "a pedestrian crossed the carriageway at x={ped_x}, off the {}..{} crossing: {:?}",
            Street::WALK_X0,
            Street::WALK_X1,
            ped.points
        );
        assert!(
            (flat_x - Street::PAIR_X).abs() < 2.0,
            "a body with flat costs should walk straight across at x={}, not x={flat_x}",
            Street::PAIR_X
        );
        // The detour is kept, the run along each pavement is not: a corridor of one point
        // per cell would be forty of them.
        assert!(
            ped.points.len() <= 10,
            "the priced detour came back as {} points: {:?}",
            ped.points.len(),
            ped.points
        );
        assert!(
            ped.raw_points >= 3 * ped.points.len(),
            "smoothing pulled {} search points down to only {}",
            ped.raw_points,
            ped.points.len()
        );
    }

    #[test]
    fn path_routes_through_the_only_doorway() {
        let sol = solidity();
        let field = bake_field(
            &Walled {
                wall_x: 30,
                door_z: 10,
            },
            &sol,
            0,
            0,
            60,
            60,
            0,
            12,
            &LinkParams::default(),
        );
        let mut w = world_with(field);
        let r = w.find_path(0, [5.0, 1.0, 40.0], [55.0, 1.0, 40.0], 60_000);
        assert_eq!(r.status, PathStatus::Ok, "the doorway makes this reachable");
        let passes_door = r
            .points
            .iter()
            .any(|p| (p[0] - 30.5).abs() < 2.0 && (p[2] - 10.5).abs() < 3.0);
        assert!(passes_door, "path must funnel through the doorway: {:?}", r.points);
    }

    #[test]
    fn sealed_goal_is_unreachable_but_breachable() {
        let sol = solidity();
        // A closed box of sheer wall (material 5 offers no grip) around the target column.
        struct Sealed;
        impl VoxelSource for Sealed {
            fn mat(&self, x: i32, y: i32, z: i32) -> u16 {
                if y <= 0 {
                    return 3;
                }
                let on_ring = (x == 40 || x == 46) && (44..=50).contains(&z)
                    || (z == 44 || z == 50) && (40..=46).contains(&x);
                if on_ring && y <= 8 {
                    return 5;
                }
                0
            }
        }
        let field = bake_field(&Sealed, &sol, 0, 0, 60, 60, 0, 12, &LinkParams::default());
        let mut w = world_with(field);
        w.set_profile(
            1,
            Profile {
                radius_cells: 0,
                height_cells: 3,
                can_break: true,
                ..Profile::default()
            },
        );
        let goal = [43.0, 1.0, 47.0];
        let walker = w.find_path(0, [5.0, 1.0, 5.0], goal, 60_000);
        assert_eq!(
            walker.status,
            PathStatus::Unreachable,
            "a walled courtyard is closed to a normal agent"
        );
        let breaker = w.find_path(1, [5.0, 1.0, 5.0], goal, 60_000);
        assert_eq!(
            breaker.status,
            PathStatus::Breach,
            "an agent that breaks walls still gets a route"
        );
        assert!(breaker.points.len() >= 2);
    }

    #[test]
    fn agents_cross_a_district_border_once_both_are_loaded() {
        let sol = solidity();
        let a = bake_field(&Ground, &sol, 0, 0, 56, 56, 0, 12, &LinkParams::default());
        let b = bake_field(&Ground, &sol, 56, 0, 56, 56, 0, 12, &LinkParams::default());
        let mut w = NavWorld::new();
        w.solidity = solidity();
        w.set_profile(
            0,
            Profile {
                radius_cells: 0,
                height_cells: 3,
                ..Profile::default()
            },
        );
        w.insert_field((0, 0), a);
        let only_a = w.find_path(0, [5.0, 1.0, 5.0], [100.0, 1.0, 30.0], 60_000);
        assert_ne!(
            only_a.status,
            PathStatus::Ok,
            "the second district is not loaded yet"
        );

        w.insert_field((1, 0), b);
        let both = w.find_path(0, [5.0, 1.0, 5.0], [100.0, 1.0, 30.0], 60_000);
        assert_eq!(both.status, PathStatus::Ok, "border must stitch when both load");
        let crossed = both.points.iter().any(|p| p[0] > 60.0);
        assert!(crossed, "path should actually enter the neighbour district");
    }

    #[test]
    fn blocking_a_column_forces_a_detour() {
        let sol = solidity();
        // A corridor one column wide: blocking it must break the route.
        struct Corridor;
        impl VoxelSource for Corridor {
            fn mat(&self, x: i32, y: i32, z: i32) -> u16 {
                if y <= 0 {
                    return 3;
                }
                if x == 20 && y <= 6 && z != 10 {
                    return 3;
                }
                0
            }
        }
        let field = bake_field(&Corridor, &sol, 0, 0, 40, 40, 0, 10, &LinkParams::default());
        let mut w = world_with(field);
        let before = w.find_path(0, [5.0, 1.0, 10.0], [35.0, 1.0, 10.0], 60_000);
        assert_eq!(before.status, PathStatus::Ok);
        w.advance_time(0.0);
        w.block_column(20, 10, 5.0);
        let after = w.find_path(0, [5.0, 1.0, 10.0], [35.0, 1.0, 10.0], 60_000);
        assert_ne!(
            after.status,
            PathStatus::Ok,
            "the only gap is blocked, so the goal is not reachable"
        );
        w.advance_time(10.0);
        let expired = w.find_path(0, [5.0, 1.0, 10.0], [35.0, 1.0, 10.0], 60_000);
        assert_eq!(expired.status, PathStatus::Ok, "blocks must expire");
    }

    #[test]
    fn a_path_off_a_blocked_column_still_returns() {
        // The failure ladder blames the column an agent cannot get past, and the agent it
        // blamed it for is often standing in it. Walking out of a blocked column towards -X
        // samples that column again in `line_walkable`, which `neighbours` never did, so the
        // smoother meets a raw step it cannot straighten.
        let sol = solidity();
        struct Flat;
        impl VoxelSource for Flat {
            fn mat(&self, _x: i32, y: i32, _z: i32) -> u16 {
                if y <= 0 {
                    3
                } else {
                    0
                }
            }
        }
        let field = bake_field(&Flat, &sol, 0, 0, 60, 40, 0, 10, &LinkParams::default());
        let mut w = world_with(field);
        w.advance_time(0.0);
        w.block_column(40, 20, 30.0);
        for goal_x in [10.0f32, 55.0f32] {
            let out = w.find_path(0, [40.5, 1.0, 20.5], [goal_x, 1.0, 20.5], 60_000);
            assert_eq!(
                out.status,
                PathStatus::Ok,
                "leaving a blocked column towards x={goal_x} must terminate with a corridor"
            );
        }
    }

    #[test]
    fn rebuilding_a_box_opens_a_new_route() {
        let sol = solidity();
        struct Sealed;
        impl VoxelSource for Sealed {
            fn mat(&self, x: i32, y: i32, _z: i32) -> u16 {
                if y <= 0 {
                    return 3;
                }
                if x == 20 && y <= 8 {
                    return 3;
                }
                0
            }
        }
        struct Breached;
        impl VoxelSource for Breached {
            fn mat(&self, x: i32, y: i32, z: i32) -> u16 {
                if y <= 0 {
                    return 3;
                }
                // Same wall, with a hole blasted at z == 15.
                if x == 20 && y <= 8 && z != 15 {
                    return 3;
                }
                0
            }
        }
        let field = bake_field(&Sealed, &sol, 0, 0, 56, 56, 0, 12, &LinkParams::default());
        let mut w = world_with(field);
        let before = w.find_path(0, [5.0, 1.0, 15.0], [50.0, 1.0, 15.0], 60_000);
        assert_ne!(before.status, PathStatus::Ok, "solid wall blocks the route");

        // Sector (0, 0) plus the context columns the link bake reads past its edge. The
        // wall and the hole both sit inside it; the neighbouring sectors are only
        // partly covered, so they are read and not rebuilt.
        let touched = w
            .rebuild_box((0, 0), 0, 0, SECTOR + 3, SECTOR + 3, &Breached)
            .expect("the box covers sector (0, 0) whole");
        assert_eq!(touched, 1, "only the sector the box carries entirely");
        let after = w.find_path(0, [5.0, 1.0, 15.0], [50.0, 1.0, 15.0], 60_000);
        assert_eq!(
            after.status,
            PathStatus::Ok,
            "navigation must notice the hole immediately"
        );
    }

    /// Everything a rebuild may change, in a form that can be compared. Portals and
    /// links come out of hash maps, so only the *set* of them is defined; sorting is what
    /// makes the comparison about content rather than iteration order.
    #[derive(PartialEq, Debug)]
    struct FieldShape {
        spans: Vec<Vec<Span>>,
        comps: Vec<Vec<u16>>,
        comp_counts: Vec<u16>,
        node_base: Vec<u32>,
        node_count: u32,
        /// (sector, take-off span, kind, target column, target span, cost in millivoxels)
        links: Vec<(u32, u32, u8, i32, i32, u32, u32, i32)>,
        /// (from node, to node, representative crossing)
        portals: Vec<(u32, u16, u32, u16, u32, u32)>,
    }

    fn field_shape(field: &NavField) -> FieldShape {
        let mut links: Vec<(u32, u32, u8, i32, i32, u32, u32, i32)> = Vec::new();
        for (si, sector) in field.sectors.iter().enumerate() {
            for (index, list) in &sector.links {
                for l in list {
                    links.push((
                        si as u32,
                        *index,
                        l.kind,
                        l.to_x,
                        l.to_z,
                        l.to.sector,
                        l.to.index,
                        (l.cost * 1000.0).round() as i32,
                    ));
                }
            }
        }
        links.sort_unstable();
        let mut portals: Vec<(u32, u16, u32, u16, u32, u32)> = field
            .portals
            .iter()
            .map(|p| {
                (
                    p.from_sector,
                    p.from_comp,
                    p.to_sector,
                    p.to_comp,
                    p.span_from.index,
                    p.span_to.index,
                )
            })
            .collect();
        portals.sort_unstable();
        FieldShape {
            spans: field.sectors.iter().map(|s| s.spans.clone()).collect(),
            comps: field.sectors.iter().map(|s| s.span_comp.clone()).collect(),
            comp_counts: field.sectors.iter().map(|s| s.comp_count).collect(),
            node_base: field.node_base.clone(),
            node_count: field.node_count,
            links,
            portals,
        }
    }

    /// Every span index a link, a portal or the node index names has to exist. A rebuild
    /// that renumbered one sector's spans without refreshing what points at them leaves
    /// precisely this wrong, and the symptom was an out-of-bounds panic inside a query
    /// rather than a wrong route, so it is worth checking directly instead of hoping a
    /// path happens to walk over it.
    fn assert_indices_live(field: &NavField, when: &str) {
        let spans_in = |sector: u32| -> usize {
            assert!(
                (sector as usize) < field.sectors.len(),
                "{when}: sector {sector} of {}",
                field.sectors.len()
            );
            field.sectors[sector as usize].spans.len()
        };
        for (si, sector) in field.sectors.iter().enumerate() {
            assert_eq!(
                sector.span_comp.len(),
                sector.spans.len(),
                "{when}: sector {si} labels {} of {} spans",
                sector.span_comp.len(),
                sector.spans.len()
            );
            for comp in &sector.span_comp {
                assert!(
                    *comp < sector.comp_count,
                    "{when}: sector {si} labels a span {comp} of {} components",
                    sector.comp_count
                );
            }
            for (index, list) in &sector.links {
                assert!(
                    (*index as usize) < sector.spans.len(),
                    "{when}: sector {si} hangs links off span {index} of {}",
                    sector.spans.len()
                );
                for l in list {
                    assert!(
                        (l.to.index as usize) < spans_in(l.to.sector),
                        "{when}: a link out of sector {si} names span {} of sector {}",
                        l.to.index,
                        l.to.sector
                    );
                }
            }
        }
        for p in &field.portals {
            assert!((p.span_from.index as usize) < spans_in(p.span_from.sector), "{when}: portal");
            assert!((p.span_to.index as usize) < spans_in(p.span_to.sector), "{when}: portal");
            assert!(
                p.from_comp < field.sectors[p.from_sector as usize].comp_count
                    && p.to_comp < field.sectors[p.to_sector as usize].comp_count,
                "{when}: a portal names a component that no longer exists"
            );
        }
        for portal in &field.node_portals {
            assert!(
                (*portal as usize) < field.portals.len(),
                "{when}: the node index names portal {portal} of {}",
                field.portals.len()
            );
        }
    }

    /// A deck with a climbable wall down the middle of the four sectors under test and a
    /// low platform beside it, so those sectors hold several components, links in every
    /// category, and portals in both directions. `hole` punches the deck and the wall out
    /// around the corner all four sectors meet at.
    struct Yard {
        hole: bool,
    }
    impl VoxelSource for Yard {
        fn mat(&self, x: i32, y: i32, z: i32) -> u16 {
            let gone = self.hole && (x - 56).pow(2) + (z - 56).pow(2) <= 36;
            if y <= 0 {
                return if gone { 0 } else { 3 };
            }
            if x == 56 && y <= 8 && !gone {
                return 3;
            }
            if (40..48).contains(&x) && (40..48).contains(&z) && y <= 4 {
                return 3;
            }
            0
        }
    }

    /// Spreading one edit over several frames must land in exactly the state rebuilding
    /// it in one go would have produced, or the field an agent queries between the frames
    /// is not merely stale but wrong. This is the dangling-link failure again, only
    /// stretched over time, so it is pinned rather than argued about.
    #[test]
    fn splitting_a_rebuild_per_sector_matches_one_shot() {
        let sol = solidity();
        let params = LinkParams::default();
        let baked = bake_field(&Yard { hole: false }, &sol, 0, 0, 112, 112, 0, 14, &params);
        let before = field_shape(&baked);
        let after = Yard { hole: true };
        let reach = link_reach(&params) as i32;

        // The four sectors around the hole, covered whole with their context and nothing
        // else covered whole, so exactly those four rebuild.
        let mut one_shot = world_with(baked.clone());
        let touched = one_shot
            .rebuild_box(
                (0, 0),
                SECTOR - reach,
                SECTOR - reach,
                3 * SECTOR - 1 + reach,
                3 * SECTOR - 1 + reach,
                &after,
            )
            .expect("the box carries the four sectors whole");
        assert_eq!(touched, 4, "the hole straddles four sectors");

        // One sector at a time, deliberately not in reading order: a split that only works
        // when neighbours arrive left to right is not a split.
        let per_sector: Vec<(i32, i32, i32, i32)> = [(1, 1), (2, 2), (1, 2), (2, 1)]
            .iter()
            .map(|&(sx, sz): &(i32, i32)| (sx, sz, 1, 1))
            .collect();
        // And in the shape `nav_dirty_tracker.gd` drains: a run of sectors along X inside
        // one sector row, rows in order.
        let per_row: Vec<(i32, i32, i32, i32)> = vec![(1, 1, 2, 1), (1, 2, 2, 1)];

        for units in [per_sector, per_row] {
            let mut split = world_with(baked.clone());
            let mut rebuilt = 0usize;
            for (sx, sz, wide, deep) in &units {
                let x0 = sx * SECTOR;
                let z0 = sz * SECTOR;
                rebuilt += split
                    .rebuild_box(
                        (0, 0),
                        x0 - reach,
                        z0 - reach,
                        x0 + wide * SECTOR - 1 + reach,
                        z0 + deep * SECTOR - 1 + reach,
                        &after,
                    )
                    .expect("a unit plus its context");
                // Half-applied is allowed to be stale, never to panic or to name a span
                // that no longer exists. The edit only removes material, so the route over
                // the wall it punches a gap in stays walkable at every intermediate state.
                assert_indices_live(split.field_at((0, 0)).expect("field stayed put"), "mid split");
                // The deck west of the wall crosses two of the rebuilt sectors and the edit
                // only removes material well clear of it, so this route is walkable in the
                // baked field and in every intermediate state on the way to the final one.
                let mid = split.find_path(0, [10.0, 1.0, 20.0], [50.0, 1.0, 90.0], 60_000);
                assert_eq!(
                    mid.status,
                    PathStatus::Ok,
                    "a query between two units of the same edit has to answer"
                );
                assert!(
                    mid.points.iter().all(|p| p.iter().all(|c| c.is_finite())),
                    "a mid split corridor contains a non-finite point"
                );
                assert!(
                    mid.points.last().is_some_and(|p| p[2] > 85.0),
                    "a mid split corridor stops at {:?} short of its goal",
                    mid.points.last()
                );
                // And the route the edit does change answers without panicking, however
                // stale the half-applied field is.
                let over = split.find_path(0, [10.0, 1.0, 56.0], [100.0, 1.0, 56.0], 60_000);
                assert!(
                    over.points.iter().all(|p| p.iter().all(|c| c.is_finite())),
                    "a query across the edit returned a non-finite point at {:?}",
                    over.status
                );
            }
            assert_eq!(rebuilt, 4, "the units together carry the four sectors");

            assert_indices_live(
                one_shot.field_at((0, 0)).expect("field stayed put"),
                "after one shot",
            );
            assert_indices_live(split.field_at((0, 0)).expect("field stayed put"), "after split");
            let one_shot_shape = field_shape(one_shot.field_at((0, 0)).expect("field stayed put"));
            let split_shape = field_shape(split.field_at((0, 0)).expect("field stayed put"));
            assert_ne!(before, one_shot_shape, "the edit has to change the field");
            assert_eq!(
                split_shape.spans, one_shot_shape.spans,
                "spans differ between the {} unit split and the single rebuild",
                units.len()
            );
            assert_eq!(
                split_shape.comps, one_shot_shape.comps,
                "component labels differ between the {} unit split and the single rebuild",
                units.len()
            );
            assert_eq!(
                split_shape.links, one_shot_shape.links,
                "links differ between the {} unit split and the single rebuild",
                units.len()
            );
            assert_eq!(
                split_shape.portals, one_shot_shape.portals,
                "portals differ between the {} unit split and the single rebuild",
                units.len()
            );
            assert_eq!(split_shape, one_shot_shape);
        }
    }

    #[test]
    fn a_giant_body_cannot_use_a_gap_a_person_fits_through() {
        let sol = solidity();
        // Two open halves joined only by a five column gap in a long wall.
        struct Gap;
        impl VoxelSource for Gap {
            fn mat(&self, x: i32, y: i32, z: i32) -> u16 {
                if y <= 0 {
                    return 3;
                }
                if x == 30 && y <= 20 && !(18..=22).contains(&z) {
                    return 3;
                }
                0
            }
        }
        let field = bake_field(&Gap, &sol, 0, 0, 60, 42, 0, 24, &LinkParams::default());
        let mut w = world_with(field);
        w.set_profile(
            2,
            Profile {
                radius_cells: 4,
                height_cells: 12,
                ..Profile::default()
            },
        );
        let start = [10.0, 1.0, 20.0];
        let goal = [50.0, 1.0, 20.0];

        let person = w.find_path(0, start, goal, 120_000);
        assert_eq!(person.status, PathStatus::Ok, "a person fits the gap");
        assert!(
            person.points.iter().any(|p| p[0] > 45.0),
            "the person should actually get across"
        );

        let giant = w.find_path(2, start, goal, 120_000);
        assert_ne!(
            giant.status,
            PathStatus::Ok,
            "a giant body must not squeeze through a five column gap"
        );
        assert!(
            giant.points.iter().all(|p| p[0] < 31.0),
            "the giant must stay on its own side: {:?}",
            giant.points.last()
        );
    }

    #[test]
    fn climb_links_let_a_climber_reach_a_roof() {
        let sol = solidity();
        struct Building;
        impl VoxelSource for Building {
            fn mat(&self, x: i32, y: i32, z: i32) -> u16 {
                if y <= 0 {
                    return 3;
                }
                // A solid 10 x 10 block, 8 voxels tall, with a walkable top.
                if (20..30).contains(&x) && (20..30).contains(&z) && y <= 8 {
                    return 3;
                }
                0
            }
        }
        let field = bake_field(&Building, &sol, 0, 0, 56, 56, 0, 24, &LinkParams::default());
        let mut w = NavWorld::new();
        w.solidity = solidity();
        w.set_profile(
            0,
            Profile {
                radius_cells: 0,
                height_cells: 3,
                ..Profile::default()
            },
        );
        w.set_profile(
            3,
            Profile {
                radius_cells: 0,
                height_cells: 3,
                can_climb: true,
                ..Profile::default()
            },
        );
        w.insert_field((0, 0), field);

        let roof = [25.0, 9.0, 25.0];
        let walker = w.find_path(0, [10.0, 1.0, 25.0], roof, 60_000);
        assert_ne!(
            walker.status,
            PathStatus::Ok,
            "a non-climber cannot reach the roof"
        );
        let climber = w.find_path(3, [10.0, 1.0, 25.0], roof, 60_000);
        assert_eq!(
            climber.status,
            PathStatus::Ok,
            "a climber should scale the facade"
        );
        assert!(
            climber.link_kinds.iter().any(|k| *k == crate::nav::LINK_CLIMB),
            "the route must actually use a climb link"
        );
    }

    #[test]
    fn a_one_way_descent_is_walkable_downward_and_not_back_up() {
        let sol = solidity();
        // A raised terrace filling one half of the world, sheer on the dividing edge
        // (material 5 offers no grip) and eight voxels above the ground below it. An
        // agent standing on it can step off; nothing gets it back up.
        struct Terrace;
        impl VoxelSource for Terrace {
            fn mat(&self, x: i32, y: i32, _z: i32) -> u16 {
                if y <= 0 {
                    return 3;
                }
                if x < 24 && y <= 8 {
                    return 5;
                }
                0
            }
        }
        let field = bake_field(&Terrace, &sol, 0, 0, 56, 56, 0, 24, &LinkParams::default());
        let mut w = world_with(field);
        let high = [10.0, 9.0, 28.0];
        let low = [45.0, 1.0, 28.0];

        let down = w.find_path(0, high, low, 60_000);
        assert_eq!(
            down.status,
            PathStatus::Ok,
            "a place you can plainly fall out of is not unreachable"
        );
        assert!(
            down.link_kinds.iter().any(|k| *k == crate::nav::LINK_DROP),
            "the descent has to be the baked drop: {:?}",
            down.link_kinds
        );

        let up = w.find_path(0, low, high, 60_000);
        assert_ne!(
            up.status,
            PathStatus::Ok,
            "the coarse graph must not run a one-way drop backwards"
        );
        assert!(
            up.points.iter().all(|p| p[1] < 8.0),
            "the walker must stay off the terrace: {:?}",
            up.points.last()
        );
    }

    #[test]
    fn stacked_levels_are_addressed_independently() {
        let sol = solidity();
        struct TwoFloors;
        impl VoxelSource for TwoFloors {
            fn mat(&self, x: i32, y: i32, z: i32) -> u16 {
                if y <= 0 {
                    return 3;
                }
                // An upper slab over the whole area, held up outside the test corridor.
                if y == 8 && (5..50).contains(&x) && (5..50).contains(&z) {
                    return 3;
                }
                0
            }
        }
        let field = bake_field(&TwoFloors, &sol, 0, 0, 56, 56, 0, 20, &LinkParams::default());
        let w = world_with(field);
        let f = w.field_at((0, 0)).unwrap();
        let mut ids = Vec::new();
        f.column_spans(20, 20, &mut ids);
        assert_eq!(ids.len(), 2, "ground and slab top are separate spans");
        let ys: Vec<f32> = ids.iter().map(|i| f.span(*i).surface_y).collect();
        assert!(ys.contains(&1.0) && ys.contains(&9.0), "got {ys:?}");

        let profile = w.profile(0).unwrap();
        let both = w.column_surfaces(20.2, 1.0, 20.2, profile, 12);
        let both_ys: Vec<f32> = both.iter().map(|p| p[1]).collect();
        assert_eq!(both.len(), 2, "vertical band must list both floors: {both_ys:?}");
        let ground_only = w.column_surfaces(20.2, 1.0, 20.2, profile, 2);
        assert_eq!(
            ground_only.len(),
            1,
            "tight vertical band must not reach the slab"
        );
        assert!((ground_only[0][1] - 1.0).abs() < 0.01);
    }
}
