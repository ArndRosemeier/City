//! Universal voxel navigation core.
//!
//! The world is described as a *span field*: for every voxel column we store every
//! surface an agent could stand on, together with the free height above it. That makes
//! navigation natively 3D — street level, catacombs below, building floors and roofs
//! above all coexist in one column — without any of the flat-ground assumptions the old
//! street graphs made.
//!
//! Passability is never derived from material semantics here. The caller supplies a
//! [`Solidity`] table built from the real collision data of the voxel block library, so
//! a voxel type whose collision is switched off is passable to navigation by definition.
//!
//! Storage is partitioned into sectors. A sector owns its columns, spans, component
//! labels and links, so destroying a wall rebuilds one sector instead of renumbering
//! the whole district.
//!
//! This module holds no Godot types so the algorithms stay unit testable.

use std::collections::{HashMap, HashSet};

/// No collision at all — agents pass straight through (air, foliage, flowers).
pub const SOL_PASSABLE: u8 = 0;
/// Collision on the water mask only — swimmable, blocks nothing solid.
pub const SOL_WATER: u8 = 1;
/// Collision fills the cell.
pub const SOL_SOLID: u8 = 2;
/// Collision occupies part of the cell height (curbs, roof wedges) — a step, not a wall.
pub const SOL_PARTIAL: u8 = 3;

/// Sector edge in voxels. Matches `DistrictCoord.CELL_SIZE` so sector borders line up
/// with the street grid instead of cutting arbitrarily across it.
pub const SECTOR: i32 = 28;

/// Free cells above a surface are counted up to this; taller shafts are equivalent.
pub const MAX_HEADROOM: u8 = 40;
/// Geodesic clearance saturates here (7.5 m at 0.5 m voxels covers the largest agent).
pub const MAX_CLEARANCE: u8 = 15;

pub const NO_COMP: u16 = u16::MAX;

/// The supporting voxel can be destroyed, so this span may vanish.
pub const FLAG_DESTRUCTIBLE: u8 = 1 << 0;

pub const LINK_WALK: u8 = 255;
pub const LINK_CLIMB: u8 = 0;
pub const LINK_DROP: u8 = 1;
pub const LINK_JUMP: u8 = 2;

// ---------------------------------------------------------------------------
// Collision facts
// ---------------------------------------------------------------------------

/// Per-material collision facts, mirrored from the voxel block library.
#[derive(Clone)]
pub struct Solidity {
    /// `SOL_*` class per material id. Length tracks the GDScript table (`VoxelMaterial.COUNT`).
    pub class: Vec<u8>,
    /// Top of the collision volume inside the cell, 0..1, meaningful for `SOL_PARTIAL`.
    pub top: Vec<f32>,
    /// Material can be carved away, so spans resting on it are fragile.
    pub destructible: Vec<bool>,
    /// Material offers a grip for climbing agents.
    pub climbable: Vec<bool>,
}

impl Default for Solidity {
    fn default() -> Self {
        Self::with_len(crate::materials::COUNT as usize)
    }
}

impl Solidity {
    pub fn with_len(n: usize) -> Self {
        // Unknown materials read as solid: an agent refusing to walk is a visible bug,
        // an agent walking through a wall is a silent one.
        let n = n.max(1);
        Self {
            class: vec![SOL_SOLID; n],
            top: vec![1.0; n],
            destructible: vec![false; n],
            climbable: vec![false; n],
        }
    }

    #[inline]
    pub fn class_of(&self, mat: u16) -> u8 {
        self.class
            .get(mat as usize)
            .copied()
            .unwrap_or(SOL_SOLID)
    }

    /// Height of the collision top inside a cell; 0 when nothing supports weight.
    #[inline]
    pub fn support(&self, mat: u16) -> f32 {
        match self.class_of(mat) {
            SOL_SOLID => 1.0,
            SOL_PARTIAL => self.top.get(mat as usize).copied().unwrap_or(1.0),
            _ => 0.0,
        }
    }

    /// True when the cell stops an agent occupying the space above a lower surface.
    #[inline]
    pub fn occupies_cell(&self, mat: u16) -> bool {
        matches!(self.class_of(mat), SOL_SOLID | SOL_PARTIAL)
    }

    #[inline]
    pub fn is_destructible(&self, mat: u16) -> bool {
        self.destructible.get(mat as usize).copied().unwrap_or(false)
    }
}

// ---------------------------------------------------------------------------
// Spans
// ---------------------------------------------------------------------------

/// One standing surface in one voxel column.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Span {
    /// World voxel Y of the walkable surface (fractional for curbs and roof pitches).
    pub surface_y: f32,
    /// Free cells above the surface, saturating at [`MAX_HEADROOM`].
    pub headroom: u8,
    /// Water cells stacked directly on the surface. Zero is dry ground, and anything
    /// above it is how deep an agent has to wade to stand here.
    pub water_depth: u8,
    /// Geodesic distance in cells to the edge of walkable space, saturating.
    pub clearance: u8,
    /// Material of the supporting voxel, used for surface cost.
    pub mat: u16,
    pub flags: u8,
}

/// Identifies a span inside one field.
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug)]
pub struct SpanId {
    pub sector: u32,
    pub index: u32,
}

/// An explicit traversal that ordinary walking cannot express.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct NavLink {
    pub kind: u8,
    /// Destination column in world voxel coordinates.
    pub to_x: i32,
    pub to_z: i32,
    pub to: SpanId,
    /// Traversal cost in the same units as walking distance (voxels).
    pub cost: f32,
}

// ---------------------------------------------------------------------------
// Profiles
// ---------------------------------------------------------------------------

/// What an agent's body can do. Baked data is body-agnostic; this filters it per query.
#[derive(Clone)]
pub struct Profile {
    /// Required geodesic clearance in cells (roughly the body radius).
    pub radius_cells: u8,
    /// Required free cells above the surface (roughly the body height).
    pub height_cells: u8,
    /// Largest upward surface difference walkable without a link, in voxels.
    pub max_step: f32,
    /// Largest downward surface difference walkable without a link, in voxels.
    pub max_drop: f32,
    /// Deepest water the agent can walk through, in cells.
    pub max_wade: u8,
    /// Agent can enter water deeper than `max_wade`.
    pub can_swim: bool,
    pub can_climb: bool,
    pub can_jump: bool,
    /// Agent smashes through obstacles, so an unreachable goal becomes a breach route.
    pub can_break: bool,
    /// Multiplier per supporting material, letting cars prefer asphalt and peds pavement.
    pub surface_cost: Vec<f32>,
}

impl Default for Profile {
    fn default() -> Self {
        Self {
            radius_cells: 1,
            height_cells: 4,
            max_step: 1.2,
            max_drop: 3.0,
            max_wade: 1,
            can_swim: false,
            can_climb: false,
            can_jump: false,
            can_break: false,
            surface_cost: vec![1.0; crate::materials::COUNT as usize],
        }
    }
}

impl Profile {
    /// The permissive profile used to bake components, clearance and links. Everything a
    /// real agent can reach is reachable here, so per-profile queries only narrow it.
    pub fn base() -> Self {
        Self {
            radius_cells: 0,
            height_cells: 2,
            max_step: 1.2,
            max_drop: 4.0,
            max_wade: 255,
            can_swim: true,
            can_climb: false,
            can_jump: false,
            can_break: false,
            surface_cost: vec![1.0; crate::materials::COUNT as usize],
        }
    }

    #[inline]
    pub fn accepts(&self, s: &Span) -> bool {
        if s.clearance < self.radius_cells || s.headroom < self.height_cells {
            return false;
        }
        if s.water_depth > self.max_wade && !self.can_swim {
            return false;
        }
        true
    }

    #[inline]
    pub fn accepts_link(&self, kind: u8) -> bool {
        match kind {
            LINK_CLIMB => self.can_climb,
            LINK_JUMP => self.can_jump,
            LINK_DROP => true,
            _ => true,
        }
    }

    #[inline]
    pub fn cost_of(&self, s: &Span) -> f32 {
        self.surface_cost
            .get(s.mat as usize)
            .copied()
            .unwrap_or(1.0)
    }
}

// ---------------------------------------------------------------------------
// Voxel access
// ---------------------------------------------------------------------------

/// Read access to a voxel volume in world voxel coordinates.
pub trait VoxelSource {
    fn mat(&self, x: i32, y: i32, z: i32) -> u16;
}

// ---------------------------------------------------------------------------
// Span extraction
// ---------------------------------------------------------------------------

/// Walkable surfaces in one column, bottom to top.
///
/// A surface exists wherever a supporting voxel is topped by free space. A partially
/// filled cell (curb, roof wedge) supports at its own collision top, so agents stand on
/// the lip rather than snapping to a whole voxel.
pub fn extract_column<S: VoxelSource>(
    src: &S,
    sol: &Solidity,
    x: i32,
    z: i32,
    y_min: i32,
    y_max: i32,
    out: &mut Vec<Span>,
) {
    let mut y = y_min;
    while y <= y_max {
        let mat = src.mat(x, y, z);
        let support = sol.support(mat);
        if support <= 0.0 {
            y += 1;
            continue;
        }

        // A full cell puts the surface on its ceiling; a partial one inside itself. Free
        // height is counted from the next whole cell either way, so the sliver left above
        // a curb lip is ignored rather than over-promised.
        let full = support >= 1.0;
        let surface_y = y as f32 + support;
        let scan_from = y + 1;

        if scan_from > y_max {
            break;
        }
        // Anything occupying the cell above a full one is the real standing surface, and
        // it will be emitted when the scan reaches it.
        if full && sol.occupies_cell(src.mat(x, scan_from, z)) {
            y += 1;
            continue;
        }

        let mut headroom: u8 = 0;
        let mut water_depth: u8 = 0;
        let mut still_water = true;
        let mut yy = scan_from;
        while yy <= y_max && headroom < MAX_HEADROOM {
            let m = src.mat(x, yy, z);
            if sol.occupies_cell(m) {
                break;
            }
            if sol.class_of(m) == SOL_WATER {
                if still_water {
                    water_depth += 1;
                }
            } else {
                still_water = false;
            }
            headroom += 1;
            yy += 1;
        }

        if headroom > 0 {
            let mut flags = 0u8;
            if sol.is_destructible(mat) {
                flags |= FLAG_DESTRUCTIBLE;
            }
            out.push(Span {
                surface_y,
                headroom,
                water_depth,
                clearance: MAX_CLEARANCE,
                mat,
                flags,
            });
        }
        y += 1;
    }
}

// ---------------------------------------------------------------------------
// Sectors
// ---------------------------------------------------------------------------

/// One sector's worth of columns. Rebuilt as a unit when voxels change.
#[derive(Clone)]
pub struct Sector {
    /// World voxel origin of the sector's first column.
    pub x0: i32,
    pub z0: i32,
    /// Column counts, clipped at the field edge.
    pub sx: i32,
    pub sz: i32,
    /// CSR index into `spans`, length `sx * sz + 1`.
    pub col_start: Vec<u32>,
    pub spans: Vec<Span>,
    /// Connected component label per span, local to this sector.
    pub span_comp: Vec<u16>,
    pub comp_count: u16,
    /// Sparse traversal links keyed by local span index.
    pub links: HashMap<u32, Vec<NavLink>>,
}

impl Sector {
    fn new(x0: i32, z0: i32, sx: i32, sz: i32) -> Self {
        Self {
            x0,
            z0,
            sx,
            sz,
            col_start: vec![0; (sx * sz) as usize + 1],
            spans: Vec::new(),
            span_comp: Vec::new(),
            comp_count: 0,
            links: HashMap::new(),
        }
    }

    #[inline]
    pub fn contains(&self, wx: i32, wz: i32) -> bool {
        wx >= self.x0 && wz >= self.z0 && wx < self.x0 + self.sx && wz < self.z0 + self.sz
    }

    #[inline]
    pub fn local_col(&self, wx: i32, wz: i32) -> Option<usize> {
        if !self.contains(wx, wz) {
            return None;
        }
        Some(((wx - self.x0) + (wz - self.z0) * self.sx) as usize)
    }

    #[inline]
    pub fn col_range(&self, col: usize) -> std::ops::Range<usize> {
        self.col_start[col] as usize..self.col_start[col + 1] as usize
    }

    #[inline]
    pub fn col_of_span(&self, index: u32) -> usize {
        match self.col_start.binary_search(&index) {
            Ok(mut i) => {
                // Empty columns share an offset; walk to the one that owns the span.
                while i + 1 < self.col_start.len() && self.col_start[i + 1] == index {
                    i += 1;
                }
                i
            }
            Err(i) => i - 1,
        }
    }

    #[inline]
    pub fn col_xz(&self, col: usize) -> (i32, i32) {
        let lx = (col as i32) % self.sx;
        let lz = (col as i32) / self.sx;
        (self.x0 + lx, self.z0 + lz)
    }
}

/// A *directed* crossing from one sector component into another.
///
/// Direction is the whole point. Movement is not symmetric — a ledge can be left by
/// falling off it and not by climbing back up — so an undirected coarse graph would
/// happily route an agent up a one-way drop into a sealed courtyard. Two components
/// that are mutually reachable carry two portals, one each way; a one-way descent
/// carries only the downward one.
///
/// Both ends are stored as (sector, component) rather than global node ids, so
/// relabelling a rebuilt sector does not invalidate every portal in the district.
/// `from_sector == to_sector` is an ordinary intra-sector crossing.
#[derive(Clone, Copy, Debug)]
pub struct Portal {
    pub from_sector: u32,
    pub from_comp: u16,
    pub to_sector: u32,
    pub to_comp: u16,
    pub span_from: SpanId,
    pub span_to: SpanId,
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

// ---------------------------------------------------------------------------
// Field
// ---------------------------------------------------------------------------

/// Navigation data for one district.
#[derive(Clone)]
pub struct NavField {
    pub origin_x: i32,
    pub origin_z: i32,
    pub size_x: i32,
    pub size_z: i32,
    pub y_min: i32,
    pub y_max: i32,
    pub sectors_x: i32,
    pub sectors_z: i32,
    pub sectors: Vec<Sector>,
    pub portals: Vec<Portal>,
    /// First high level node id of each sector; prefix sum over component counts.
    pub node_base: Vec<u32>,
    pub node_count: u32,
    /// Portal indices *leaving* each node, CSR into `node_portals`. Portals are
    /// directed, so a node lists only the crossings an agent standing there can take.
    pub node_portal_start: Vec<u32>,
    pub node_portals: Vec<u32>,
    /// Bumped whenever spans change, so cached agent corridors can be invalidated.
    pub version: u64,
}

impl NavField {
    pub fn new(
        origin_x: i32,
        origin_z: i32,
        size_x: i32,
        size_z: i32,
        y_min: i32,
        y_max: i32,
    ) -> Self {
        let sectors_x = (size_x + SECTOR - 1) / SECTOR;
        let sectors_z = (size_z + SECTOR - 1) / SECTOR;
        let mut sectors = Vec::with_capacity((sectors_x * sectors_z) as usize);
        for sz in 0..sectors_z {
            for sx in 0..sectors_x {
                let x0 = sx * SECTOR;
                let z0 = sz * SECTOR;
                let w = (x0 + SECTOR).min(size_x) - x0;
                let d = (z0 + SECTOR).min(size_z) - z0;
                sectors.push(Sector::new(origin_x + x0, origin_z + z0, w, d));
            }
        }
        Self {
            origin_x,
            origin_z,
            size_x,
            size_z,
            y_min,
            y_max,
            sectors_x,
            sectors_z,
            sectors,
            portals: Vec::new(),
            node_base: Vec::new(),
            node_count: 0,
            node_portal_start: Vec::new(),
            node_portals: Vec::new(),
            version: 1,
        }
    }

    #[inline]
    pub fn contains_column(&self, wx: i32, wz: i32) -> bool {
        let lx = wx - self.origin_x;
        let lz = wz - self.origin_z;
        lx >= 0 && lz >= 0 && lx < self.size_x && lz < self.size_z
    }

    #[inline]
    pub fn sector_index(&self, wx: i32, wz: i32) -> Option<usize> {
        if !self.contains_column(wx, wz) {
            return None;
        }
        let sx = (wx - self.origin_x) / SECTOR;
        let sz = (wz - self.origin_z) / SECTOR;
        Some((sx + sz * self.sectors_x) as usize)
    }

    #[inline]
    pub fn span(&self, id: SpanId) -> &Span {
        &self.sectors[id.sector as usize].spans[id.index as usize]
    }

    #[inline]
    pub fn span_xz(&self, id: SpanId) -> (i32, i32) {
        let s = &self.sectors[id.sector as usize];
        s.col_xz(s.col_of_span(id.index))
    }

    #[inline]
    pub fn node_of(&self, id: SpanId) -> u32 {
        let comp = self.sectors[id.sector as usize].span_comp[id.index as usize];
        if comp == NO_COMP {
            return u32::MAX;
        }
        self.node_base[id.sector as usize] + comp as u32
    }

    /// Every span in a column, as ids.
    pub fn column_spans(&self, wx: i32, wz: i32, out: &mut Vec<SpanId>) {
        out.clear();
        let Some(si) = self.sector_index(wx, wz) else {
            return;
        };
        let sector = &self.sectors[si];
        let Some(col) = sector.local_col(wx, wz) else {
            return;
        };
        for i in sector.col_range(col) {
            out.push(SpanId {
                sector: si as u32,
                index: i as u32,
            });
        }
    }

    /// Best span in a column for `profile` reachable by walking from `from_y`.
    pub fn step_target(&self, wx: i32, wz: i32, from_y: f32, profile: &Profile) -> Option<SpanId> {
        let si = self.sector_index(wx, wz)?;
        let sector = &self.sectors[si];
        let col = sector.local_col(wx, wz)?;
        let mut best: Option<(SpanId, f32)> = None;
        for i in sector.col_range(col) {
            let s = &sector.spans[i];
            if !profile.accepts(s) {
                continue;
            }
            let dy = s.surface_y - from_y;
            if dy > profile.max_step || -dy > profile.max_drop {
                continue;
            }
            let score = dy.abs();
            if best.map_or(true, |(_, b)| score < b) {
                best = Some((
                    SpanId {
                        sector: si as u32,
                        index: i as u32,
                    },
                    score,
                ));
            }
        }
        best.map(|(id, _)| id)
    }

    /// Span closest to a world voxel position that `profile` can occupy.
    pub fn nearest_span(
        &self,
        wx: i32,
        wy: f32,
        wz: i32,
        profile: &Profile,
        radius_cells: i32,
    ) -> Option<(SpanId, f32)> {
        let mut best: Option<(SpanId, f32)> = None;
        for r in 0..=radius_cells {
            // Expanding ring search: the first ring with a hit is the closest one.
            let mut found_in_ring = false;
            for dz in -r..=r {
                for dx in -r..=r {
                    if r > 0 && dx.abs() != r && dz.abs() != r {
                        continue;
                    }
                    let x = wx + dx;
                    let z = wz + dz;
                    let Some(si) = self.sector_index(x, z) else {
                        continue;
                    };
                    let sector = &self.sectors[si];
                    let Some(col) = sector.local_col(x, z) else {
                        continue;
                    };
                    for i in sector.col_range(col) {
                        let s = &sector.spans[i];
                        if !profile.accepts(s) {
                            continue;
                        }
                        let ddx = (x - wx) as f32;
                        let ddz = (z - wz) as f32;
                        let ddy = s.surface_y - wy;
                        // Vertical error dominates: standing on the right floor of a
                        // building matters more than a metre of horizontal drift.
                        let d = ddx * ddx + ddz * ddz + ddy * ddy * 4.0;
                        if best.map_or(true, |(_, b)| d < b) {
                            best = Some((
                                SpanId {
                                    sector: si as u32,
                                    index: i as u32,
                                },
                                d,
                            ));
                            found_in_ring = true;
                        }
                    }
                }
            }
            if found_in_ring && r > 0 {
                break;
            }
        }
        best.map(|(id, d)| (id, d.sqrt()))
    }

    pub fn stats(&self) -> FieldStats {
        let mut spans = 0usize;
        let mut max_per_col = 0usize;
        let mut links = 0usize;
        let mut bytes = 0usize;
        for sector in &self.sectors {
            spans += sector.spans.len();
            links += sector.links.values().map(|v| v.len()).sum::<usize>();
            bytes += sector.spans.len() * std::mem::size_of::<Span>()
                + sector.col_start.len() * 4
                + sector.span_comp.len() * 2;
            for c in 0..(sector.sx * sector.sz) as usize {
                max_per_col = max_per_col.max(sector.col_range(c).len());
            }
        }
        bytes += self.portals.len() * std::mem::size_of::<Portal>() + self.node_portals.len() * 4;
        FieldStats {
            columns: (self.size_x * self.size_z) as usize,
            spans,
            max_spans_per_column: max_per_col,
            nodes: self.node_count as usize,
            portals: self.portals.len(),
            links,
            bytes,
        }
    }
}

#[derive(Clone, Copy, Debug, Default)]
pub struct FieldStats {
    pub columns: usize,
    pub spans: usize,
    pub max_spans_per_column: usize,
    pub nodes: usize,
    pub portals: usize,
    pub links: usize,
    pub bytes: usize,
}

// ---------------------------------------------------------------------------
// Baking
// ---------------------------------------------------------------------------

/// Rebuild the spans of one sector from voxels. Component labels and links are left for
/// [`rebuild_sector_components`] and [`compute_links`].
pub fn rebuild_sector_spans<S: VoxelSource>(
    field: &mut NavField,
    sector_index: usize,
    src: &S,
    sol: &Solidity,
) {
    let y_min = field.y_min;
    let y_max = field.y_max;
    let sector = &mut field.sectors[sector_index];
    sector.spans.clear();
    let mut scratch: Vec<Span> = Vec::with_capacity(8);
    let cols = (sector.sx * sector.sz) as usize;
    for col in 0..cols {
        sector.col_start[col] = sector.spans.len() as u32;
        let (wx, wz) = sector.col_xz(col);
        scratch.clear();
        extract_column(src, sol, wx, wz, y_min, y_max, &mut scratch);
        sector.spans.extend_from_slice(&scratch);
    }
    sector.col_start[cols] = sector.spans.len() as u32;
    sector.span_comp = vec![NO_COMP; sector.spans.len()];
    sector.comp_count = 0;
    sector.links.clear();
}

/// Build the whole field from a voxel source.
///
/// Order matters: links must exist before components, because base connectivity is the
/// union of everything *any* body can do. A route only a climber can take still has to
/// join the graph, or the search would report it impossible for everyone.
pub fn bake_field<S: VoxelSource>(
    src: &S,
    sol: &Solidity,
    origin_x: i32,
    origin_z: i32,
    size_x: i32,
    size_z: i32,
    y_min: i32,
    y_max: i32,
    params: &LinkParams,
) -> NavField {
    let mut field = NavField::new(origin_x, origin_z, size_x, size_z, y_min, y_max);
    for si in 0..field.sectors.len() {
        rebuild_sector_spans(&mut field, si, src, sol);
    }
    compute_clearance(&mut field, None);
    for si in 0..field.sectors.len() {
        compute_sector_links(&mut field, si, src, sol, params);
    }
    for si in 0..field.sectors.len() {
        rebuild_sector_components(&mut field, si);
    }
    rebuild_node_index(&mut field);
    rebuild_all_portals(&mut field);
    field
}

/// Geodesic distance from every span to the edge of walkable space.
///
/// Sources are spans bordering a column that offers no reachable continuation, which is
/// exactly a wall, a ledge or the field boundary. One BFS then gives every span the
/// radius of the largest body that fits there.
///
/// Passing `region` limits the work to a rectangle of *columns* during incremental
/// rebuilds; spans just outside it seed the BFS with the values they already hold. That
/// is exact as long as the rectangle reaches [`MAX_CLEARANCE`] columns past every column
/// whose geometry changed: a source further away than the distance the transform
/// saturates at can only offer a value the span already reads.
pub fn compute_clearance(field: &mut NavField, region: Option<(i32, i32, i32, i32)>) {
    let base = Profile::base();
    let x_last = field.origin_x + field.size_x - 1;
    let z_last = field.origin_z + field.size_z - 1;
    let (cx0, cz0, cx1, cz1) = match region {
        Some((x0, z0, x1, z1)) => (
            x0.max(field.origin_x),
            z0.max(field.origin_z),
            x1.min(x_last),
            z1.min(z_last),
        ),
        None => (field.origin_x, field.origin_z, x_last, z_last),
    };
    if cx0 > cx1 || cz0 > cz1 {
        return;
    }
    // Sectors the column rectangle reaches into. Whole sectors, so the BFS can find a
    // span's slot by arithmetic; the columns of theirs that fall outside the rectangle
    // are simply left out of the numbering.
    let sx0 = (cx0 - field.origin_x) / SECTOR;
    let sx1 = ((cx1 - field.origin_x) / SECTOR).min(field.sectors_x - 1);
    let sz0 = (cz0 - field.origin_z) / SECTOR;
    let sz1 = ((cz1 - field.origin_z) / SECTOR).min(field.sectors_z - 1);

    // Spans of the region, numbered densely so the BFS can index a flat array instead of
    // hashing a SpanId per edge — a rebuild visits tens of thousands of them per frame.
    let rw = (sx1 - sx0 + 1) as usize;
    let slots = rw * (sz1 - sz0 + 1) as usize;
    let mut slot_base: Vec<u32> = vec![0; slots + 1];
    for sz in sz0..=sz1 {
        for sx in sx0..=sx1 {
            let si = (sx + sz * field.sectors_x) as usize;
            let slot = (sx - sx0) as usize + (sz - sz0) as usize * rw;
            slot_base[slot + 1] = slot_base[slot] + field.sectors[si].spans.len() as u32;
        }
    }
    // Dense number per span of every sector touched, NOT_IN_REGION for the spans of the
    // columns the rectangle cuts away.
    const NOT_IN_REGION: u32 = u32::MAX;
    let mut slot_of: Vec<u32> = vec![NOT_IN_REGION; slot_base[slots] as usize];
    let mut ids: Vec<SpanId> = Vec::new();
    for sz in sz0..=sz1 {
        for sx in sx0..=sx1 {
            let si = (sx + sz * field.sectors_x) as usize;
            let slot = (sx - sx0) as usize + (sz - sz0) as usize * rw;
            let base_of = slot_base[slot] as usize;
            let sector = &field.sectors[si];
            for col in 0..(sector.sx * sector.sz) as usize {
                let (wx, wz) = sector.col_xz(col);
                if wx < cx0 || wx > cx1 || wz < cz0 || wz > cz1 {
                    continue;
                }
                for index in sector.col_range(col) {
                    slot_of[base_of + index] = ids.len() as u32;
                    ids.push(SpanId {
                        sector: si as u32,
                        index: index as u32,
                    });
                }
            }
        }
    }
    let flat = |field: &NavField, id: SpanId| -> Option<usize> {
        let sx = (id.sector as i32) % field.sectors_x;
        let sz = (id.sector as i32) / field.sectors_x;
        if sx < sx0 || sx > sx1 || sz < sz0 || sz > sz1 {
            return None;
        }
        let slot = (sx - sx0) as usize + (sz - sz0) as usize * rw;
        match slot_of[slot_base[slot] as usize + id.index as usize] {
            NOT_IN_REGION => None,
            k => Some(k as usize),
        }
    };

    let mut dist: Vec<u8> = vec![u8::MAX; ids.len()];
    let mut queue: Vec<u32> = Vec::new();

    for (k, &id) in ids.iter().enumerate() {
        let s = *field.span(id);
        let (wx, wz) = field.span_xz(id);
        let mut open = true;
        for (dx, dz) in STEP_DIRS {
            let nx = wx + dx;
            let nz = wz + dz;
            if !field.contains_column(nx, nz) {
                // Field edge: left open so district borders do not pinch. Cross-district
                // clearance is refined once the neighbouring district loads.
                continue;
            }
            if field.step_target(nx, nz, s.surface_y, &base).is_none() {
                open = false;
                break;
            }
        }
        if !open {
            dist[k] = 0;
            queue.push(k as u32);
        }
    }

    // Seed from spans just outside the region so a local rebuild blends with the rest.
    if region.is_some() {
        for (k, &id) in ids.iter().enumerate() {
            let s = *field.span(id);
            let (wx, wz) = field.span_xz(id);
            for (dx, dz) in STEP_DIRS {
                let Some(nid) = field.step_target(wx + dx, wz + dz, s.surface_y, &base) else {
                    continue;
                };
                if flat(field, nid).is_some() {
                    continue;
                }
                let d = field.span(nid).clearance.saturating_add(1).min(MAX_CLEARANCE);
                if d < dist[k] {
                    dist[k] = d;
                    queue.push(k as u32);
                }
            }
        }
    }

    let mut head = 0usize;
    while head < queue.len() {
        let k = queue[head] as usize;
        head += 1;
        let d = dist[k];
        if d >= MAX_CLEARANCE {
            continue;
        }
        let id = ids[k];
        let s = *field.span(id);
        let (wx, wz) = field.span_xz(id);
        for (dx, dz) in STEP_DIRS {
            let Some(nid) = field.step_target(wx + dx, wz + dz, s.surface_y, &base) else {
                continue;
            };
            let Some(nk) = flat(field, nid) else {
                continue;
            };
            if dist[nk] > d + 1 {
                dist[nk] = d + 1;
                queue.push(nk as u32);
            }
        }
    }

    for (k, id) in ids.into_iter().enumerate() {
        let d = dist[k];
        let v = if d == u8::MAX { MAX_CLEARANCE } else { d };
        field.sectors[id.sector as usize].spans[id.index as usize].clearance = v;
    }
}

/// The four axis moves, in the order [`sector_edges`] and the link bake both use.
const STEP_DIRS: [(i32, i32); 4] = [(-1, 0), (1, 0), (0, -1), (0, 1)];

/// Every move an agent could make inside one sector, as a CSR over local span indices.
///
/// Moves are one-way by nature: the base profile walks down four voxels and up barely
/// one, and a baked drop or climb link is a single direction by definition. Recording
/// them directed is what lets the component pass tell "the same place" apart from
/// "somewhere you can fall to".
fn sector_edges(field: &NavField, sector_index: usize) -> (Vec<u32>, Vec<u32>) {
    let base = Profile::base();
    let (sx, sz, count) = {
        let s = &field.sectors[sector_index];
        (s.sx, s.sz, s.spans.len())
    };
    let mut pairs: Vec<(u32, u32)> = Vec::with_capacity(count * 2);
    for col in 0..(sx * sz) as usize {
        let (wx, wz) = field.sectors[sector_index].col_xz(col);
        let range = field.sectors[sector_index].col_range(col);
        for index in range {
            let surface_y = field.sectors[sector_index].spans[index].surface_y;
            for (dx, dz) in STEP_DIRS {
                let Some(nid) = field.step_target(wx + dx, wz + dz, surface_y, &base) else {
                    continue;
                };
                if nid.sector as usize == sector_index {
                    pairs.push((index as u32, nid.index));
                }
            }
            // Links carry connectivity too, otherwise a roof only a climber can reach
            // would look unreachable to every profile.
            if let Some(links) = field.sectors[sector_index].links.get(&(index as u32)) {
                for link in links {
                    if link.to.sector as usize == sector_index {
                        pairs.push((index as u32, link.to.index));
                    }
                }
            }
        }
    }

    let mut start = vec![0u32; count + 1];
    for (u, _) in &pairs {
        start[*u as usize + 1] += 1;
    }
    for i in 0..count {
        start[i + 1] += start[i];
    }
    let mut cursor = start.clone();
    let mut edge = vec![0u32; pairs.len()];
    for (u, v) in pairs {
        edge[cursor[u as usize] as usize] = v;
        cursor[u as usize] += 1;
    }
    (start, edge)
}

/// Tarjan's strongly connected components over a CSR digraph, iteratively so a long
/// corridor of spans cannot blow the stack.
///
/// Strong connectivity is exactly the right equivalence here: two spans share a
/// component when an agent can get from either to the other and back. Anything weaker
/// would merge a ledge with the ground it drops onto and hand the coarse search a route
/// back up that does not exist.
fn strongly_connected(start: &[u32], edge: &[u32]) -> (Vec<u16>, u16) {
    const UNVISITED: u32 = u32::MAX;
    let n = start.len() - 1;
    let mut index = vec![UNVISITED; n];
    let mut low = vec![0u32; n];
    let mut on_stack = vec![false; n];
    let mut comp = vec![NO_COMP; n];
    let mut ring: Vec<u32> = Vec::new();
    let mut call: Vec<(u32, u32)> = Vec::new();
    let mut next_index = 0u32;
    let mut next_comp: u16 = 0;

    for root in 0..n {
        if index[root] != UNVISITED {
            continue;
        }
        if next_comp == NO_COMP {
            // 65535 components in one sector is not a sector any more. Leaving the rest
            // unlabelled makes them visibly unreachable rather than silently wrong.
            break;
        }
        index[root] = next_index;
        low[root] = next_index;
        next_index += 1;
        ring.push(root as u32);
        on_stack[root] = true;
        call.push((root as u32, start[root]));

        while let Some(&(v, cursor)) = call.last() {
            let vu = v as usize;
            if cursor < start[vu + 1] {
                call.last_mut().expect("frame just read").1 = cursor + 1;
                let w = edge[cursor as usize] as usize;
                if index[w] == UNVISITED {
                    index[w] = next_index;
                    low[w] = next_index;
                    next_index += 1;
                    ring.push(w as u32);
                    on_stack[w] = true;
                    call.push((w as u32, start[w]));
                } else if on_stack[w] {
                    low[vu] = low[vu].min(index[w]);
                }
                continue;
            }
            call.pop();
            if let Some(&(parent, _)) = call.last() {
                let pu = parent as usize;
                low[pu] = low[pu].min(low[vu]);
            }
            if low[vu] == index[vu] {
                loop {
                    let w = ring.pop().expect("component root is on the ring") as usize;
                    on_stack[w] = false;
                    comp[w] = next_comp;
                    if w == vu {
                        break;
                    }
                }
                next_comp += 1;
                if next_comp == NO_COMP {
                    break;
                }
            }
        }
    }
    (comp, next_comp)
}

/// Label a sector's spans with strongly connected components of the moves confined to
/// that sector. Crossings, in or out, become directed portals instead.
pub fn rebuild_sector_components(field: &mut NavField, sector_index: usize) {
    let (start, edge) = sector_edges(field, sector_index);
    let (comp_of, count) = strongly_connected(&start, &edge);
    let sector = &mut field.sectors[sector_index];
    sector.span_comp = comp_of;
    sector.comp_count = count;
}

/// Recompute the sector to node-id prefix sum. Cheap, so it runs after any relabelling.
pub fn rebuild_node_index(field: &mut NavField) {
    let n = field.sectors.len();
    field.node_base = vec![0; n];
    let mut acc = 0u32;
    for i in 0..n {
        field.node_base[i] = acc;
        acc += field.sectors[i].comp_count as u32;
    }
    field.node_count = acc;
}

/// Turn the best representative crossing per component pair into portals.
fn push_portals(
    field: &NavField,
    from_sector: u32,
    to_sector: u32,
    best: HashMap<(u16, u16), (SpanId, SpanId, f32)>,
    out: &mut Vec<Portal>,
) {
    for ((from_comp, to_comp), (span_from, span_to, _)) in best {
        let (fx, fz) = field.span_xz(span_from);
        let (tx, tz) = field.span_xz(span_to);
        out.push(Portal {
            from_sector,
            from_comp,
            to_sector,
            to_comp,
            span_from,
            span_to,
            x: (fx as f32 + tx as f32) * 0.5 + 0.5,
            y: (field.span(span_from).surface_y + field.span(span_to).surface_y) * 0.5,
            z: (fz as f32 + tz as f32) * 0.5 + 0.5,
        });
    }
}

/// Directed crossings from sector `a` into the adjacent sector `b`.
///
/// Only the moves that genuinely leave `a` for `b` are recorded, so scanning the pair
/// the other way round is a separate call producing separate portals.
fn portals_across(field: &NavField, a: usize, b: usize, out: &mut Vec<Portal>) {
    let base = Profile::base();
    let (ax0, az0, asx, asz) = {
        let s = &field.sectors[a];
        (s.x0, s.z0, s.sx, s.sz)
    };
    // Only the strip of A that faces B needs scanning.
    let bs = &field.sectors[b];
    let dx = (bs.x0 - ax0).signum();
    let dz = (bs.z0 - az0).signum();
    let mut best: HashMap<(u16, u16), (SpanId, SpanId, f32)> = HashMap::new();

    let (sx0, sx1, sz0, sz1) = if dx > 0 {
        (ax0 + asx - 1, ax0 + asx - 1, az0, az0 + asz - 1)
    } else if dx < 0 {
        (ax0, ax0, az0, az0 + asz - 1)
    } else if dz > 0 {
        (ax0, ax0 + asx - 1, az0 + asz - 1, az0 + asz - 1)
    } else {
        (ax0, ax0 + asx - 1, az0, az0)
    };

    let mut ids: Vec<SpanId> = Vec::new();
    for wz in sz0..=sz1 {
        for wx in sx0..=sx1 {
            field.column_spans(wx, wz, &mut ids);
            for &id in &ids {
                if id.sector as usize != a {
                    continue;
                }
                let comp_a = field.sectors[a].span_comp[id.index as usize];
                if comp_a == NO_COMP {
                    continue;
                }
                let s = *field.span(id);
                let Some(nid) = field.step_target(wx + dx, wz + dz, s.surface_y, &base) else {
                    continue;
                };
                if nid.sector as usize != b {
                    continue;
                }
                let comp_b = field.sectors[b].span_comp[nid.index as usize];
                if comp_b == NO_COMP {
                    continue;
                }
                let score = (field.span(nid).surface_y - s.surface_y).abs();
                let entry = best.entry((comp_a, comp_b)).or_insert((id, nid, f32::MAX));
                if score < entry.2 {
                    *entry = (id, nid, score);
                }
            }
        }
    }

    // Links landing in B are crossings too, and they are already one-way: a drop into
    // the next sector is recorded here without any matching edge back up.
    let crossing: Vec<(u32, SpanId)> = field.sectors[a]
        .links
        .iter()
        .flat_map(|(index, links)| {
            links
                .iter()
                .filter(|l| l.to.sector as usize == b)
                .map(move |l| (*index, l.to))
        })
        .collect();
    for (index, target) in crossing {
        let from = SpanId {
            sector: a as u32,
            index,
        };
        let comp_a = field.sectors[a].span_comp[index as usize];
        let comp_b = field.sectors[b].span_comp[target.index as usize];
        if comp_a == NO_COMP || comp_b == NO_COMP {
            continue;
        }
        let score = (field.span(target).surface_y - field.span(from).surface_y).abs();
        let entry = best
            .entry((comp_a, comp_b))
            .or_insert((from, target, f32::MAX));
        if score < entry.2 {
            *entry = (from, target, score);
        }
    }

    push_portals(field, a as u32, b as u32, best, out);
}

/// Directed crossings between two components of the *same* sector.
///
/// Without these a ledge whose only exit is a drop is a coarse island: nothing points
/// at it and nothing leaves it, so the corridor search calls a place an agent can
/// plainly fall out of unreachable. Because they are directed, adding them cannot
/// invent a route back up the drop.
fn portals_inside(field: &NavField, sector_index: usize, out: &mut Vec<Portal>) {
    if field.sectors[sector_index].comp_count < 2 {
        return;
    }
    let (start, edge) = sector_edges(field, sector_index);
    let mut best: HashMap<(u16, u16), (SpanId, SpanId, f32)> = HashMap::new();
    for u in 0..(start.len() - 1) {
        let comp_u = field.sectors[sector_index].span_comp[u];
        if comp_u == NO_COMP {
            continue;
        }
        for &v in &edge[start[u] as usize..start[u + 1] as usize] {
            let comp_v = field.sectors[sector_index].span_comp[v as usize];
            if comp_v == NO_COMP || comp_v == comp_u {
                continue;
            }
            let from = SpanId {
                sector: sector_index as u32,
                index: u as u32,
            };
            let to = SpanId {
                sector: sector_index as u32,
                index: v,
            };
            let score = (field.span(to).surface_y - field.span(from).surface_y).abs();
            let entry = best
                .entry((comp_u, comp_v))
                .or_insert((from, to, f32::MAX));
            if score < entry.2 {
                *entry = (from, to, score);
            }
        }
    }
    push_portals(
        field,
        sector_index as u32,
        sector_index as u32,
        best,
        out,
    );
}

/// Every sector index adjacent to `s`, in the four axis directions.
fn sector_neighbours(field: &NavField, s: usize) -> Vec<usize> {
    let sx = (s as i32) % field.sectors_x;
    let sz = (s as i32) / field.sectors_x;
    let mut out = Vec::with_capacity(4);
    for (dx, dz) in STEP_DIRS {
        let nx = sx + dx;
        let nz = sz + dz;
        if nx < 0 || nz < 0 || nx >= field.sectors_x || nz >= field.sectors_z {
            continue;
        }
        out.push((nx + nz * field.sectors_x) as usize);
    }
    out
}

/// Recompute every portal in the field, then the node CSR index.
pub fn rebuild_all_portals(field: &mut NavField) {
    let mut portals: Vec<Portal> = Vec::new();
    for s in 0..field.sectors.len() {
        portals_inside(field, s, &mut portals);
        for n in sector_neighbours(field, s) {
            portals_across(field, s, n, &mut portals);
        }
    }
    field.portals = portals;
    rebuild_portal_index(field);
}

/// Rebuild only the portals touching the listed sectors, keeping the rest.
pub fn rebuild_portals_for(field: &mut NavField, sectors: &[usize]) {
    let touched: HashSet<usize> = sectors.iter().copied().collect();
    let mut kept: Vec<Portal> = std::mem::take(&mut field.portals)
        .into_iter()
        .filter(|p| {
            !touched.contains(&(p.from_sector as usize))
                && !touched.contains(&(p.to_sector as usize))
        })
        .collect();

    let mut done: HashSet<(usize, usize)> = HashSet::new();
    for &s in sectors {
        if done.insert((s, s)) {
            portals_inside(field, s, &mut kept);
        }
        for n in sector_neighbours(field, s) {
            // Both directions: a rebuilt sector changes what leaves it *and* what its
            // neighbours can still reach into it.
            if done.insert((s, n)) {
                portals_across(field, s, n, &mut kept);
            }
            if done.insert((n, s)) {
                portals_across(field, n, s, &mut kept);
            }
        }
    }
    field.portals = kept;
    rebuild_portal_index(field);
}

fn rebuild_portal_index(field: &mut NavField) {
    let nodes = field.node_count as usize;
    let node_of = |field: &NavField, sector: u32, comp: u16| -> usize {
        (field.node_base[sector as usize] + comp as u32) as usize
    };
    let mut counts = vec![0u32; nodes + 1];
    for p in &field.portals {
        let a = node_of(field, p.from_sector, p.from_comp);
        if a < nodes {
            counts[a] += 1;
        }
    }
    field.node_portal_start = vec![0; nodes + 1];
    let mut acc = 0u32;
    for i in 0..nodes {
        field.node_portal_start[i] = acc;
        acc += counts[i];
    }
    field.node_portal_start[nodes] = acc;
    let mut cursor = field.node_portal_start.clone();
    field.node_portals = vec![0; acc as usize];
    for pi in 0..field.portals.len() {
        let p = field.portals[pi];
        let a = node_of(field, p.from_sector, p.from_comp);
        if a < nodes {
            field.node_portals[cursor[a] as usize] = pi as u32;
            cursor[a] += 1;
        }
    }
}

// ---------------------------------------------------------------------------
// Traversal links
// ---------------------------------------------------------------------------

/// Cells above the take-off surface that a jump arc must keep clear.
const JUMP_ARC_CELLS: i32 = 3;

/// Tuning for the link bake, mirrored from the player's climb constants so mobs climb
/// where the player can.
///
/// The climb heights are `city_walker.gd` in voxels at `character_scale` 1.0 and 0.5 m
/// cells: `_find_climb_wall()` probes the facade at chest height and again at
/// `chest + max(climb_min_wall_m, max_step_height * 2.8)`, and refuses the climb unless
/// both probes hit. `min_drop` is `climb_drop_depth_m`, the drop the player treats as a
/// climb-down rather than a step off a lip.
#[derive(Clone, Copy)]
pub struct LinkParams {
    /// Tallest climb in voxels.
    pub max_climb: f32,
    /// Chest probe height above the take-off surface, in voxels.
    pub climb_chest: f32,
    /// Head probe height above the take-off surface, in voxels.
    pub climb_head: f32,
    /// Widest jumpable gap in columns.
    pub max_jump_gap: i32,
    /// Highest landing a jump may reach, in voxels.
    pub max_jump_up: f32,
    /// Cost per voxel of climbing, relative to walking one voxel.
    pub climb_cost: f32,
    /// Shallowest drop that may be baked as a link at all, in voxels — the depth at
    /// which the player stops stepping off a lip and climbs down instead.
    ///
    /// Every descent deeper than this is a link, walkable or not. Walking with the
    /// permissive [`Profile::base`] covers four voxels, but a real body declares its own
    /// `max_drop` and a pedestrian's is three, so anything keyed to the base envelope
    /// would leave descents that are neither a walk edge nor a link for that body. The
    /// overlap costs a parallel edge on shallow ledges and closes the hole.
    pub min_drop: f32,
    /// Deepest survivable drop in voxels.
    pub max_drop: f32,
}

impl Default for LinkParams {
    fn default() -> Self {
        Self {
            max_climb: 24.0,
            climb_chest: 1.9,
            climb_head: 4.98,
            max_jump_gap: 3,
            max_jump_up: 2.0,
            climb_cost: 3.0,
            min_drop: 1.7,
            max_drop: 24.0,
        }
    }
}

/// How far, in columns, a link can reach out of the column it takes off from.
///
/// A rebuild has to see this much world around every sector it rebuilds: that is the
/// span of voxels the climb probes and the jump arc read.
pub fn link_reach(params: &LinkParams) -> i32 {
    params.max_jump_gap.max(1)
}

/// How far, in voxels, a rebuild reads *above* the field's own Y range.
///
/// Span extraction stops at `y_max`, but a surface resting on that last cell stands a
/// voxel above it and the climb probes and the jump arc reach further up again. A material
/// box shorter than this hands the rebuild rock where the bake saw sky, so it is what lets
/// the copy be the band the field occupies rather than the whole height of the terrain.
pub fn link_reach_y(params: &LinkParams) -> i32 {
    1 + (params.climb_head.ceil() as i32).max(JUMP_ARC_CELLS)
}

/// The links leaving one span in one of the four axis directions.
///
/// Split out of the sector bake so an incremental rebuild can refresh exactly the
/// directions that point at geometry which changed, and leave the rest alone.
#[allow(clippy::too_many_arguments)]
fn links_in_direction<S: VoxelSource>(
    field: &NavField,
    src: &S,
    sol: &Solidity,
    params: &LinkParams,
    wx: i32,
    wz: i32,
    s: &Span,
    dx: i32,
    dz: i32,
    ids: &mut Vec<SpanId>,
    out: &mut Vec<NavLink>,
) {
    let base = Profile::base();
    let nx = wx + dx;
    let nz = wz + dz;
    if !field.contains_column(nx, nz) {
        return;
    }
    let walkable = field.step_target(nx, nz, s.surface_y, &base).is_some();

    // Climb: a grippable face next door with a landing above it. Both of the player's
    // wall probes must find that grip, otherwise a mob would scale a garden wall the
    // player can only step over.
    let chest_y = (s.surface_y + params.climb_chest).floor() as i32;
    let head_y = (s.surface_y + params.climb_head).floor() as i32;
    if sol.climbable[src.mat(nx, chest_y, nz) as usize]
        && sol.climbable[src.mat(nx, head_y, nz) as usize]
    {
        field.column_spans(nx, nz, ids);
        let mut best: Option<(SpanId, f32)> = None;
        for &t in ids.iter() {
            let ts = *field.span(t);
            let dy = ts.surface_y - s.surface_y;
            if dy <= base.max_step || dy > params.max_climb || ts.headroom < 2 {
                continue;
            }
            // The climber's body hangs in this column, so a ceiling over the take-off
            // ends the ascent exactly as it does for the player.
            if dy > s.headroom as f32 {
                continue;
            }
            if best.map_or(true, |(_, b)| dy < b) {
                best = Some((t, dy));
            }
        }
        if let Some((t, dy)) = best {
            out.push(NavLink {
                kind: LINK_CLIMB,
                to_x: nx,
                to_z: nz,
                to: t,
                cost: dy * params.climb_cost,
            });
        }
    }

    // Drop: a landing deeper than the lip the player would just step off. Baked whether
    // or not the permissive base profile could also walk it, because the body doing the
    // query may declare a shallower `max_drop` than the base envelope.
    field.column_spans(nx, nz, ids);
    let mut lowest: Option<(SpanId, f32)> = None;
    for &t in ids.iter() {
        let ts = *field.span(t);
        let dy = s.surface_y - ts.surface_y;
        if dy <= params.min_drop || dy > params.max_drop || ts.headroom < 2 {
            continue;
        }
        // The fall has to be clear: a landing whose own free height stops below the
        // take-off sits under a floor, not under a ledge.
        if ts.surface_y + (ts.headroom as f32) < s.surface_y {
            continue;
        }
        if lowest.map_or(true, |(_, b)| dy < b) {
            lowest = Some((t, dy));
        }
    }
    if let Some((t, dy)) = lowest {
        out.push(NavLink {
            kind: LINK_DROP,
            to_x: nx,
            to_z: nz,
            to: t,
            cost: 1.0 + dy * 0.25,
        });
    }

    if walkable {
        return;
    }

    // Jump: clear a narrow gap in a straight line. The arc has to be empty, or agents
    // would vault straight over walls.
    let arc_base = s.surface_y.floor() as i32;
    let arc_top = arc_base + JUMP_ARC_CELLS;
    for gap in 2..=params.max_jump_gap {
        let jx = wx + dx * gap;
        let jz = wz + dz * gap;
        if !field.contains_column(jx, jz) {
            break;
        }
        let over_x = wx + dx * (gap - 1);
        let over_z = wz + dz * (gap - 1);
        let blocked =
            (arc_base..=arc_top).any(|y| sol.occupies_cell(src.mat(over_x, y, over_z)));
        if blocked {
            break;
        }
        field.column_spans(jx, jz, ids);
        for &t in ids.iter() {
            let ts = *field.span(t);
            let dy = ts.surface_y - s.surface_y;
            if dy > params.max_jump_up || -dy > params.max_drop || ts.headroom < 2 {
                continue;
            }
            out.push(NavLink {
                kind: LINK_JUMP,
                to_x: jx,
                to_z: jz,
                to: t,
                cost: gap as f32 * 1.5 + dy.abs(),
            });
            return;
        }
    }
}

/// Emit climb, drop and jump links for one sector.
///
/// Mobs cannot probe for walls the way the player does, because remeshed colliders only
/// exist near the camera. Links are resolved once here and become ordinary, priced edges
/// in the search, so an agent climbs a facade only when that genuinely beats walking
/// around it.
pub fn compute_sector_links<S: VoxelSource>(
    field: &mut NavField,
    sector_index: usize,
    src: &S,
    sol: &Solidity,
    params: &LinkParams,
) {
    let cols = {
        let s = &field.sectors[sector_index];
        (s.sx * s.sz) as usize
    };
    let mut new_links: HashMap<u32, Vec<NavLink>> = HashMap::new();
    let mut ids: Vec<SpanId> = Vec::new();

    for col in 0..cols {
        let (wx, wz) = {
            let s = &field.sectors[sector_index];
            s.col_xz(col)
        };
        let range = {
            let s = &field.sectors[sector_index];
            s.col_range(col)
        };
        for index in range {
            let s = field.sectors[sector_index].spans[index];
            let mut out: Vec<NavLink> = Vec::new();
            for (dx, dz) in STEP_DIRS {
                links_in_direction(
                    field, src, sol, params, wx, wz, &s, dx, dz, &mut ids, &mut out,
                );
            }
            if !out.is_empty() {
                new_links.insert(index as u32, out);
            }
        }
    }

    field.sectors[sector_index].links = new_links;
}

/// Which of [`STEP_DIRS`] a link leaves its take-off column by.
fn direction_of(wx: i32, wz: i32, to_x: i32, to_z: i32) -> Option<usize> {
    let d = ((to_x - wx).signum(), (to_z - wz).signum());
    STEP_DIRS.iter().position(|dir| *dir == d)
}

/// Rebuild the links that reach *into* a set of freshly rebuilt sectors from outside.
///
/// A link names its landing as a raw index into the target sector's span list, so a
/// rebuild that shrinks that list leaves every neighbour reaching into it pointing at
/// spans which no longer exist — the dangling reference that used to take the whole
/// extension down with an out-of-bounds panic while terrain was being destroyed.
///
/// Recomputing them is the honest repair: for every column close enough to reach a
/// rebuilt sector, the directions that can land in one are baked again from the fresh
/// voxels, and the directions pointing anywhere else keep the links they already had.
/// `src` must therefore cover the rebuilt sectors plus [`link_reach`] columns around
/// them, which is what `NavWorld::rebuild_box` checks before it starts.
pub fn refresh_links_into<S: VoxelSource>(
    field: &mut NavField,
    touched: &[usize],
    src: &S,
    sol: &Solidity,
    params: &LinkParams,
) {
    let reach = link_reach(params);
    let inside: HashSet<usize> = touched.iter().copied().collect();

    let mut columns: HashSet<(i32, i32)> = HashSet::new();
    for &si in touched {
        let (x0, z0, sx, sz) = {
            let s = &field.sectors[si];
            (s.x0, s.z0, s.sx, s.sz)
        };
        for z in (z0 - reach)..(z0 + sz + reach) {
            for x in (x0 - reach)..(x0 + sx + reach) {
                let Some(nsi) = field.sector_index(x, z) else {
                    continue;
                };
                if inside.contains(&nsi) {
                    continue;
                }
                columns.insert((x, z));
            }
        }
    }

    let mut ids: Vec<SpanId> = Vec::new();
    let mut fresh: Vec<NavLink> = Vec::new();
    for (wx, wz) in columns {
        let si = field
            .sector_index(wx, wz)
            .expect("column was found through the field");
        let mut refresh = [false; 4];
        for (i, (dx, dz)) in STEP_DIRS.iter().enumerate() {
            for gap in 1..=reach {
                let tx = wx + dx * gap;
                let tz = wz + dz * gap;
                if field
                    .sector_index(tx, tz)
                    .is_some_and(|t| inside.contains(&t))
                {
                    refresh[i] = true;
                    break;
                }
            }
        }
        if !refresh.iter().any(|r| *r) {
            continue;
        }
        let col = field.sectors[si]
            .local_col(wx, wz)
            .expect("column belongs to the sector that reported it");
        let range = field.sectors[si].col_range(col);
        for index in range {
            let s = field.sectors[si].spans[index];
            fresh.clear();
            if let Some(old) = field.sectors[si].links.get(&(index as u32)) {
                for link in old {
                    match direction_of(wx, wz, link.to_x, link.to_z) {
                        Some(i) if refresh[i] => continue,
                        _ => fresh.push(*link),
                    }
                }
            }
            for (i, (dx, dz)) in STEP_DIRS.iter().enumerate() {
                if !refresh[i] {
                    continue;
                }
                links_in_direction(
                    field, src, sol, params, wx, wz, &s, *dx, *dz, &mut ids, &mut fresh,
                );
            }
            let sector = &mut field.sectors[si];
            if fresh.is_empty() {
                sector.links.remove(&(index as u32));
            } else {
                sector.links.insert(index as u32, fresh.clone());
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_solidity() -> Solidity {
        let mut sol = Solidity::default();
        // 0 = air, 1 = foliage (collision off), 2 = water, 3 = stone, 4 = curb
        sol.class[0] = SOL_PASSABLE;
        sol.class[1] = SOL_PASSABLE;
        sol.class[2] = SOL_WATER;
        sol.class[3] = SOL_SOLID;
        sol.class[4] = SOL_PARTIAL;
        sol.top[4] = 0.4;
        sol.climbable[3] = true;
        sol.destructible[3] = true;
        sol
    }

    struct Ground(i32);
    impl VoxelSource for Ground {
        fn mat(&self, _x: i32, y: i32, _z: i32) -> u16 {
            if y <= self.0 {
                3
            } else {
                0
            }
        }
    }

    #[test]
    fn column_yields_surface_above_solid() {
        let sol = test_solidity();
        let mut out = Vec::new();
        extract_column(&Ground(5), &sol, 0, 0, 0, 20, &mut out);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].surface_y, 6.0);
        assert_eq!(out[0].headroom, 15);
        assert_eq!(out[0].water_depth, 0);
    }

    /// Material ids past 255 must index solidity and stamp onto spans — no byte truncation.
    #[test]
    fn high_material_id_past_byte_range() {
        let mut sol = Solidity::with_len(300);
        sol.class[0] = SOL_PASSABLE;
        sol.class[280] = SOL_SOLID;
        struct HiMat;
        impl VoxelSource for HiMat {
            fn mat(&self, _x: i32, y: i32, _z: i32) -> u16 {
                if y <= 2 {
                    280
                } else {
                    0
                }
            }
        }
        let mut out = Vec::new();
        extract_column(&HiMat, &sol, 0, 0, 0, 20, &mut out);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].surface_y, 3.0);
        assert_eq!(out[0].mat, 280);
        assert_eq!(sol.class_of(280), SOL_SOLID);
        assert_eq!(sol.class_of(400), SOL_SOLID);
    }

    #[test]
    fn foliage_is_passable_and_creates_no_surface() {
        let sol = test_solidity();
        struct Grove;
        impl VoxelSource for Grove {
            fn mat(&self, _x: i32, y: i32, _z: i32) -> u16 {
                if y <= 2 {
                    3
                } else if y <= 6 {
                    1
                } else {
                    0
                }
            }
        }
        let mut out = Vec::new();
        extract_column(&Grove, &sol, 0, 0, 0, 20, &mut out);
        assert_eq!(out.len(), 1, "foliage must not become a floor");
        assert_eq!(out[0].surface_y, 3.0);
        assert_eq!(out[0].headroom, 18, "foliage must not eat headroom");
    }

    #[test]
    fn partial_cell_supports_at_its_collision_top() {
        let sol = test_solidity();
        struct Curb;
        impl VoxelSource for Curb {
            fn mat(&self, _x: i32, y: i32, _z: i32) -> u16 {
                match y {
                    y if y <= 2 => 3,
                    3 => 4,
                    _ => 0,
                }
            }
        }
        let mut out = Vec::new();
        extract_column(&Curb, &sol, 0, 0, 0, 10, &mut out);
        assert_eq!(out.len(), 1, "the covered stone top is not standable");
        assert!((out[0].surface_y - 3.4).abs() < 1e-5);
    }

    #[test]
    fn water_column_reports_depth() {
        let sol = test_solidity();
        struct Lake;
        impl VoxelSource for Lake {
            fn mat(&self, _x: i32, y: i32, _z: i32) -> u16 {
                if y <= 2 {
                    3
                } else if y <= 5 {
                    2
                } else {
                    0
                }
            }
        }
        let mut out = Vec::new();
        extract_column(&Lake, &sol, 0, 0, 0, 12, &mut out);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].water_depth, 3);
    }

    #[test]
    fn stacked_floors_produce_multiple_spans() {
        let sol = test_solidity();
        struct Tower;
        impl VoxelSource for Tower {
            fn mat(&self, _x: i32, y: i32, _z: i32) -> u16 {
                if y <= 0 || y == 6 || y == 12 {
                    3
                } else {
                    0
                }
            }
        }
        let mut out = Vec::new();
        extract_column(&Tower, &sol, 0, 0, 0, 20, &mut out);
        assert_eq!(out.len(), 3, "each slab top is its own navigable level");
        assert_eq!(out[0].surface_y, 1.0);
        assert_eq!(out[1].surface_y, 7.0);
        assert_eq!(out[2].surface_y, 13.0);
        assert_eq!(out[0].headroom, 5, "headroom stops at the slab above");
    }

    #[test]
    fn clearance_grows_away_from_walls() {
        let sol = test_solidity();
        struct Room;
        impl VoxelSource for Room {
            fn mat(&self, x: i32, y: i32, z: i32) -> u16 {
                if y <= 0 {
                    return 3;
                }
                if y <= 4 && (x == 0 || z == 0 || x == 20 || z == 20) {
                    return 3;
                }
                0
            }
        }
        let field = bake_field(&Room, &sol, 0, 0, 21, 21, 0, 10, &LinkParams::default());
        let mut ids = Vec::new();
        field.column_spans(10, 10, &mut ids);
        let centre = field.span(ids[0]).clearance;
        field.column_spans(1, 10, &mut ids);
        let edge = field.span(ids[0]).clearance;
        assert_eq!(edge, 0, "a span against a wall has no clearance");
        assert!(centre >= 8, "room centre should be wide open, got {centre}");
    }

    #[test]
    fn profile_rejects_bodies_that_do_not_fit() {
        let span = Span {
            surface_y: 1.0,
            headroom: 3,
            water_depth: 0,
            clearance: 2,
            mat: 3,
            flags: 0,
        };
        let small = Profile {
            radius_cells: 1,
            height_cells: 3,
            ..Profile::default()
        };
        let giant = Profile {
            radius_cells: 6,
            height_cells: 12,
            ..Profile::default()
        };
        assert!(small.accepts(&span));
        assert!(!giant.accepts(&span), "a giant must not fit a narrow low span");
    }

    #[test]
    fn non_swimmer_refuses_deep_water() {
        let span = Span {
            surface_y: 1.0,
            headroom: 8,
            water_depth: 4,
            clearance: 8,
            mat: 3,
            flags: 0,
        };
        let walker = Profile {
            max_wade: 1,
            can_swim: false,
            ..Profile::default()
        };
        let swimmer = Profile {
            max_wade: 1,
            can_swim: true,
            ..Profile::default()
        };
        assert!(!walker.accepts(&span));
        assert!(swimmer.accepts(&span));
    }

    #[test]
    fn col_of_span_survives_empty_columns() {
        let sol = test_solidity();
        struct Pillars;
        impl VoxelSource for Pillars {
            fn mat(&self, x: i32, y: i32, _z: i32) -> u16 {
                if x % 2 == 0 && y <= 0 {
                    3
                } else {
                    0
                }
            }
        }
        let field = bake_field(&Pillars, &sol, 0, 0, 8, 2, 0, 4, &LinkParams::default());
        for (si, sector) in field.sectors.iter().enumerate() {
            for index in 0..sector.spans.len() {
                let col = sector.col_of_span(index as u32);
                assert!(
                    sector.col_range(col).contains(&index),
                    "sector {si} span {index} must belong to the column it reports"
                );
            }
        }
    }

    #[test]
    fn open_ground_is_one_component_with_portals_between_sectors() {
        let sol = test_solidity();
        // Three sectors wide so there is a genuine interior border.
        let field = bake_field(&Ground(0), &sol, 0, 0, SECTOR * 3, SECTOR, 0, 6, &LinkParams::default());
        assert_eq!(field.sectors.len(), 3);
        for s in &field.sectors {
            assert_eq!(s.comp_count, 1, "flat ground is one component per sector");
        }
        // Portals are directed, so open ground carries a crossing each way.
        assert_eq!(field.portals.len(), 4, "two interior borders, two portals each");
        for p in &field.portals {
            assert_ne!(p.from_sector, p.to_sector, "flat ground needs no inner edge");
        }
    }

    #[test]
    fn portals_are_symmetric_across_a_sector_border() {
        let sol = test_solidity();
        // Sheer partition (material 5 offers no grip) along the last column of sector 0,
        // with one doorway, so the border carries a real crossing instead of open ground.
        struct Doorway;
        impl VoxelSource for Doorway {
            fn mat(&self, x: i32, y: i32, z: i32) -> u16 {
                if y <= 0 {
                    return 3;
                }
                if x == SECTOR - 1 && y <= 6 && z != 10 {
                    return 5;
                }
                0
            }
        }
        let field = bake_field(
            &Doorway,
            &sol,
            0,
            0,
            SECTOR * 2,
            SECTOR,
            0,
            12,
            &LinkParams::default(),
        );
        assert!(!field.portals.is_empty(), "the doorway must yield a portal");

        for (pi, p) in field.portals.iter().enumerate() {
            assert_eq!(p.span_from.sector, p.from_sector, "portal {pi} start is misfiled");
            assert_eq!(p.span_to.sector, p.to_sector, "portal {pi} end is misfiled");
            assert_eq!(
                field.sectors[p.from_sector as usize].span_comp[p.span_from.index as usize],
                p.from_comp
            );
            assert_eq!(
                field.sectors[p.to_sector as usize].span_comp[p.span_to.index as usize],
                p.to_comp
            );
            // A portal is filed under the node it leaves, and only that one: the search
            // reaches it by standing where it starts.
            let from_node = field.node_of(p.span_from);
            let lo = field.node_portal_start[from_node as usize] as usize;
            let hi = field.node_portal_start[from_node as usize + 1] as usize;
            assert!(
                field.node_portals[lo..hi].contains(&(pi as u32)),
                "portal {pi} is missing from node {from_node}"
            );
        }

        let comp_at = |x: i32, z: i32| -> (u32, u16) {
            let mut ids = Vec::new();
            field.column_spans(x, z, &mut ids);
            let id = ids[0];
            (id.sector, field.sectors[id.sector as usize].span_comp[id.index as usize])
        };
        let crossings: Vec<(u32, u16, u32, u16)> = field
            .portals
            .iter()
            .filter(|p| p.from_sector != p.to_sector)
            .map(|p| (p.from_sector, p.from_comp, p.to_sector, p.to_comp))
            .collect();

        // Level ground either side of the doorway is walkable both ways, so that
        // crossing has to appear in both directions.
        let (left_sector, left) = comp_at(5, 10);
        let (right_sector, right) = comp_at(SECTOR + 5, 10);
        assert!(
            crossings.contains(&(left_sector, left, right_sector, right))
                && crossings.contains(&(right_sector, right, left_sector, left)),
            "the doorway must be crossable both ways: {crossings:?}"
        );

        // The partition's own top also touches the border, and dropping off it is the
        // only way to use it, so that crossing must exist in one direction only.
        let (wall_sector, wall) = comp_at(SECTOR - 1, 5);
        assert_ne!(wall, left, "the sheer partition top is not the ground");
        assert!(
            crossings.contains(&(wall_sector, wall, right_sector, right))
                && !crossings.contains(&(right_sector, right, wall_sector, wall)),
            "the wall top drops into the next sector and cannot be climbed: {crossings:?}"
        );
    }

    /// Links leaving the `nth` span of a column, counted from the bottom.
    fn links_from(field: &NavField, x: i32, z: i32, nth: usize) -> Vec<NavLink> {
        let mut ids = Vec::new();
        field.column_spans(x, z, &mut ids);
        assert!(ids.len() > nth, "column {x},{z} has no span {nth}");
        let id = ids[nth];
        field.sectors[id.sector as usize]
            .links
            .get(&id.index)
            .cloned()
            .unwrap_or_default()
    }

    fn links_of_kind(field: &NavField, x: i32, z: i32, nth: usize, kind: u8) -> Vec<NavLink> {
        links_from(field, x, z, nth)
            .into_iter()
            .filter(|l| l.kind == kind)
            .collect()
    }

    #[test]
    fn climb_needs_a_grip_at_head_height() {
        let sol = test_solidity();
        // A three cell garden wall and a six cell facade on the same flat ground.
        struct Walls;
        impl VoxelSource for Walls {
            fn mat(&self, x: i32, y: i32, _z: i32) -> u16 {
                if y <= 0 {
                    return 3;
                }
                if x == 10 && y <= 3 {
                    return 3;
                }
                if x == 20 && y <= 6 {
                    return 3;
                }
                0
            }
        }
        let field = bake_field(&Walls, &sol, 0, 0, SECTOR, SECTOR, 0, 20, &LinkParams::default());
        assert!(
            links_of_kind(&field, 9, 5, 0, LINK_CLIMB).is_empty(),
            "the player's head probe misses a three cell wall, so no mob may climb it"
        );
        let facade = links_of_kind(&field, 19, 5, 0, LINK_CLIMB);
        assert_eq!(facade.len(), 1, "a six cell facade is climbable: {facade:?}");
        assert!((field.span(facade[0].to).surface_y - 7.0).abs() < 1e-5);
    }

    #[test]
    fn climb_stops_at_a_ceiling_over_the_take_off() {
        let sol = test_solidity();
        // The same climbable facade, with a canopy over both the facade and the ground
        // beside it: the roof below the canopy is too tight to stand on and the canopy top
        // is out of reach, exactly as it is for the player.
        struct Canopy;
        impl VoxelSource for Canopy {
            fn mat(&self, x: i32, y: i32, _z: i32) -> u16 {
                if y <= 0 || y == 8 {
                    return 3;
                }
                if x >= 20 && y <= 6 {
                    return 3;
                }
                0
            }
        }
        let field = bake_field(&Canopy, &sol, 0, 0, SECTOR, SECTOR, 0, 20, &LinkParams::default());
        let mut ids = Vec::new();
        field.column_spans(19, 5, &mut ids);
        assert_eq!(field.span(ids[0]).headroom, 7, "canopy must cap the take-off");
        assert!(
            links_of_kind(&field, 19, 5, 0, LINK_CLIMB).is_empty(),
            "a mob must not climb through the canopy roofing its own column"
        );
    }

    #[test]
    fn drops_do_not_fall_through_a_floor() {
        let sol = test_solidity();
        // An upper deck over open ground. A span on the deck must not drop into the ground
        // span next door, because the deck itself is in the way.
        struct Deck;
        impl VoxelSource for Deck {
            fn mat(&self, _x: i32, y: i32, _z: i32) -> u16 {
                if y <= 0 || y == 10 {
                    3
                } else {
                    0
                }
            }
        }
        let field = bake_field(&Deck, &sol, 0, 0, SECTOR, SECTOR, 0, 20, &LinkParams::default());
        let mut ids = Vec::new();
        field.column_spans(14, 14, &mut ids);
        assert_eq!(ids.len(), 2, "ground and deck are separate spans");
        let drops = links_of_kind(&field, 14, 14, 1, LINK_DROP);
        assert!(drops.is_empty(), "a drop must not pass through the deck: {drops:?}");
    }

    #[test]
    fn drops_are_links_wherever_the_descent_beats_a_step() {
        let sol = test_solidity();
        // A one cell step, a two cell block and a six cell platform on flat ground.
        struct Terraces;
        impl VoxelSource for Terraces {
            fn mat(&self, x: i32, y: i32, _z: i32) -> u16 {
                if y <= 0 {
                    return 3;
                }
                if (5..9).contains(&x) && y <= 1 {
                    return 3;
                }
                if (12..16).contains(&x) && y <= 2 {
                    return 3;
                }
                if (19..23).contains(&x) && y <= 6 {
                    return 3;
                }
                0
            }
        }
        let params = LinkParams::default();
        let field = bake_field(&Terraces, &sol, 0, 0, SECTOR, SECTOR, 0, 20, &params);
        assert!(
            links_of_kind(&field, 5, 5, 0, LINK_DROP).is_empty(),
            "half a metre is a step off a lip, not a climb-down"
        );
        // A metre is walkable for the permissive base profile but not for every body —
        // a pedestrian declares 1.5 m of drop, so the descent needs an explicit link or
        // it would exist for the bake and not for the agent.
        let metre = links_of_kind(&field, 12, 5, 0, LINK_DROP);
        assert_eq!(metre.len(), 1, "a metre down needs a link too: {metre:?}");
        assert!((field.span(metre[0].to).surface_y - 1.0).abs() < 1e-5);
        let drops = links_of_kind(&field, 19, 5, 0, LINK_DROP);
        assert_eq!(drops.len(), 1, "one edge faces the lower ground: {drops:?}");
        assert!((field.span(drops[0].to).surface_y - 1.0).abs() < 1e-5);

        // Whatever walking covers, no drop may ever be shallower than the depth the player
        // treats as a climb-down instead of a step.
        for sector in &field.sectors {
            for (index, links) in &sector.links {
                let from = sector.spans[*index as usize].surface_y;
                for link in links.iter().filter(|l| l.kind == LINK_DROP) {
                    let dy = from - field.span(link.to).surface_y;
                    assert!(dy > params.min_drop, "drop of {dy} voxels is a step, not a link");
                }
            }
        }
    }

    #[test]
    fn a_wall_disconnects_the_ground_either_side_of_it() {
        let sol = test_solidity();
        struct Split;
        impl VoxelSource for Split {
            fn mat(&self, x: i32, y: i32, _z: i32) -> u16 {
                if y <= 0 {
                    return 3;
                }
                // Sheer material 5: solid and offering no grip, so no climb link bridges it.
                if x == 14 && y <= 6 {
                    return 5;
                }
                0
            }
        }
        let field = bake_field(&Split, &sol, 0, 0, SECTOR, SECTOR, 0, 10, &LinkParams::default());
        let mut ids = Vec::new();
        field.column_spans(5, 5, &mut ids);
        let left = field.sectors[0].span_comp[ids[0].index as usize];
        field.column_spans(20, 5, &mut ids);
        let right = field.sectors[0].span_comp[ids[0].index as usize];
        assert_ne!(left, right, "the wall must split the ground into two components");
        // The wall top drops onto both sides and can be climbed from neither, so it is a
        // component of its own: three in all, joined by one-way edges pointing down.
        assert_eq!(field.sectors[0].comp_count, 3);
        field.column_spans(14, 5, &mut ids);
        let top = field.sectors[0].span_comp[ids[0].index as usize];
        let leaving: Vec<(u16, u16)> = field
            .portals
            .iter()
            .map(|p| (p.from_comp, p.to_comp))
            .collect();
        assert!(leaving.contains(&(top, left)) && leaving.contains(&(top, right)));
        assert!(
            !leaving.contains(&(left, top)) && !leaving.contains(&(right, top)),
            "nothing may lead back up a sheer wall: {leaving:?}"
        );
    }

    #[test]
    fn a_one_way_ledge_is_its_own_component_with_only_a_way_down() {
        let sol = test_solidity();
        // A sheer plinth in the middle of one sector: eight cells of material 5, which
        // offers no grip, so the only way off its top is to fall.
        struct Plinth;
        impl VoxelSource for Plinth {
            fn mat(&self, x: i32, y: i32, z: i32) -> u16 {
                if y <= 0 {
                    return 3;
                }
                if (10..16).contains(&x) && (10..16).contains(&z) && y <= 8 {
                    return 5;
                }
                0
            }
        }
        let field = bake_field(&Plinth, &sol, 0, 0, SECTOR, SECTOR, 0, 20, &LinkParams::default());
        let mut ids = Vec::new();
        field.column_spans(12, 12, &mut ids);
        let ledge = field.sectors[0].span_comp[ids[0].index as usize];
        field.column_spans(2, 2, &mut ids);
        let ground = field.sectors[0].span_comp[ids[0].index as usize];
        assert_ne!(ledge, ground, "you cannot climb back onto the plinth");

        let edges: Vec<(u16, u16)> = field
            .portals
            .iter()
            .filter(|p| p.from_sector == 0 && p.to_sector == 0)
            .map(|p| (p.from_comp, p.to_comp))
            .collect();
        assert!(
            edges.contains(&(ledge, ground)),
            "the drop off the plinth must be a coarse edge: {edges:?}"
        );
        assert!(
            !edges.contains(&(ground, ledge)),
            "nothing may lead back up: {edges:?}"
        );
    }

    /// Every link in the field must name a span that exists, at the height it was baked
    /// against. A dangling index is the bug this guards; a silently re-pointed one would
    /// send agents somewhere else entirely.
    fn assert_links_resolve(field: &NavField, when: &str) {
        for (si, sector) in field.sectors.iter().enumerate() {
            for (index, links) in &sector.links {
                assert!(
                    (*index as usize) < sector.spans.len(),
                    "{when}: sector {si} keys a link on span {index} of {}",
                    sector.spans.len()
                );
                for link in links {
                    let target = &field.sectors[link.to.sector as usize];
                    assert!(
                        (link.to.index as usize) < target.spans.len(),
                        "{when}: sector {si} link {link:?} names span {} of {} in sector {}",
                        link.to.index,
                        target.spans.len(),
                        link.to.sector
                    );
                    let (tx, tz) = field.span_xz(link.to);
                    assert_eq!(
                        (tx, tz),
                        (link.to_x, link.to_z),
                        "{when}: sector {si} link {link:?} lands in the wrong column"
                    );
                }
            }
        }
    }

    #[test]
    fn shrinking_a_sector_does_not_leave_neighbours_pointing_at_dead_spans() {
        let sol = test_solidity();
        // Two sectors. A tall shelf fills the right half of sector 0 and drops into the
        // open ground of sector 1, so sector 0 holds links whose landings live next door.
        struct Shelf;
        impl VoxelSource for Shelf {
            fn mat(&self, x: i32, y: i32, _z: i32) -> u16 {
                if y <= 0 {
                    return 3;
                }
                if (20..SECTOR).contains(&x) && y <= 8 {
                    return 3;
                }
                0
            }
        }
        // The same world with sector 1 blown out entirely: every column there loses its
        // only span, so the neighbour's landings are gone rather than merely moved.
        struct Blasted;
        impl VoxelSource for Blasted {
            fn mat(&self, x: i32, y: i32, _z: i32) -> u16 {
                if x >= SECTOR {
                    return 0;
                }
                Shelf.mat(x, y, 0)
            }
        }

        let mut field = bake_field(
            &Shelf,
            &sol,
            0,
            0,
            SECTOR * 2,
            SECTOR,
            0,
            20,
            &LinkParams::default(),
        );
        assert_links_resolve(&field, "after the bake");
        let inbound = field.sectors[0]
            .links
            .values()
            .flatten()
            .filter(|l| l.to.sector == 1)
            .count();
        assert!(inbound > 0, "the shelf must drop into the neighbouring sector");
        let spans_before = field.sectors[1].spans.len();

        // Exactly what an incremental rebuild does to sector 1, in the same order.
        let params = LinkParams::default();
        rebuild_sector_spans(&mut field, 1, &Blasted, &sol);
        assert!(
            field.sectors[1].spans.len() < spans_before,
            "the blast has to shrink the span list, or the test proves nothing"
        );
        compute_clearance(&mut field, Some((0, 0, 1, 0)));
        compute_sector_links(&mut field, 1, &Blasted, &sol, &params);
        refresh_links_into(&mut field, &[1], &Blasted, &sol, &params);
        rebuild_sector_components(&mut field, 1);
        rebuild_node_index(&mut field);
        // This is where a dangling index used to take the whole extension down.
        rebuild_portals_for(&mut field, &[1]);

        assert_links_resolve(&field, "after the shrinking rebuild");
        let survivors = field.sectors[0]
            .links
            .values()
            .flatten()
            .filter(|l| l.to.sector == 1)
            .count();
        assert_eq!(survivors, 0, "there is nothing left next door to land on");
    }
}
