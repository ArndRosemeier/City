//! Hill district native voxel passes: paint, gems, swiss-cheese caves.
//!
//! Heightfield / clearance / portals / trees stay in GDScript. Seed streams are
//! independent of Godot RNG — looks should match quality, not bit-identical layouts.

use crate::hill_paint;
use crate::materials;
use crate::NativeOfflineVoxelVolume;
use godot::prelude::*;
use std::collections::HashMap;
use std::f32::consts::TAU;
use std::time::Instant;

const CAVE_RADIUS: i32 = 2;
const CAVE_CLEARANCE_RY: i32 = 4;
const CAVE_PIT_DEPTH: i32 = 3;
const CAVE_WALK_CLEARANCE: i32 = 6;
const CAVE_MOUTH_HEIGHT: i32 = 12;
const CAVE_LONG_RUN: i32 = 16;
const CAVE_MEANDER_FRAC: f32 = 0.32;
const CAVE_SHELL: i32 = 6;
const CAVE_CELL_XZ: i32 = 22;
const CAVE_CELL_Y: i32 = 15;
const CAVE_MAX_LEVELS: i32 = 6;
const CAVE_ROOM_R_MIN: i32 = 6;
const CAVE_ROOM_R_MAX: i32 = 11;
const CAVE_ROOM_RY_EXTRA: i32 = 4;
const CAVE_LINK_P_HORZ: f32 = 0.55;
const CAVE_LINK_P_VERT: f32 = 0.5;
const CAVE_LINK_R_MIN: i32 = 2;
const CAVE_LINK_R_MAX: i32 = 4;
const CAVE_SHAFT_RADIUS: f32 = 7.0;
const CAVE_SHAFT_RISE: i32 = 12;
const CAVE_STEEP_DROP: i32 = 7;
const CAVE_HOLLOW_TARGET: f32 = 0.30;
const PEAK_MAX: i32 = 72;

#[derive(GodotClass)]
#[class(base=RefCounted)]
struct NativeHillCaves {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for NativeHillCaves {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl NativeHillCaves {
    /// Banded rock + turf for every raised column. `band_mats` / `band_ends` match
    /// HillComposer strata tables (same length; last end is the cycle length).
    #[func]
    fn paint_terrain(
        &mut self,
        mut volume: Gd<NativeOfflineVoxelVolume>,
        origin_x: i32,
        origin_z: i32,
        size_x: i32,
        size_z: i32,
        ground_y: i32,
        height: PackedInt32Array,
        band_mats: PackedInt32Array,
        band_ends: PackedInt32Array,
    ) -> Dictionary<Variant, Variant> {
        let mut out = Dictionary::<Variant, Variant>::new();
        out.set("ok", false);
        let height_vec: Vec<i32> = (0..height.len()).map(|i| height[i]).collect();
        let mats: Vec<i32> = (0..band_mats.len()).map(|i| band_mats[i]).collect();
        let ends: Vec<i32> = (0..band_ends.len()).map(|i| band_ends[i]).collect();
        let mut vol = volume.bind_mut();
        match hill_paint::paint_terrain(
            &mut vol,
            origin_x,
            origin_z,
            size_x,
            size_z,
            ground_y,
            &height_vec,
            &mats,
            &ends,
        ) {
            Ok(stats) => {
                out.set("ok", true);
                out.set("columns", stats.columns as i64);
                out.set("ms", stats.ms);
            }
            Err(msg) => {
                godot_error!("NativeHillCaves.paint_terrain: {msg}");
            }
        }
        out
    }

    /// Embed gem ore before caves open. `road_mask` is `size_x * size_z` bytes (nonzero = skip).
    /// Returns `positions` / `mats` for the gem light registry.
    #[func]
    fn scatter_gems(
        &mut self,
        mut volume: Gd<NativeOfflineVoxelVolume>,
        origin_x: i32,
        origin_z: i32,
        size_x: i32,
        size_z: i32,
        ground_y: i32,
        height: PackedInt32Array,
        road_mask: PackedByteArray,
        seed: i64,
    ) -> Dictionary<Variant, Variant> {
        let mut out = Dictionary::<Variant, Variant>::new();
        out.set("ok", false);
        let height_vec: Vec<i32> = (0..height.len()).map(|i| height[i]).collect();
        let roads: Vec<u8> = (0..road_mask.len()).map(|i| road_mask[i]).collect();
        let mut vol = volume.bind_mut();
        match hill_paint::scatter_gems(
            &mut vol,
            origin_x,
            origin_z,
            size_x,
            size_z,
            ground_y,
            &height_vec,
            &roads,
            seed as u64,
        ) {
            Ok(stats) => {
                out.set("ok", true);
                out.set("clusters", stats.clusters as i64);
                out.set("voxels", stats.voxels as i64);
                out.set("positions", &stats.positions);
                out.set("mats", &stats.mats);
                out.set("ms", stats.ms);
            }
            Err(msg) => {
                godot_error!("NativeHillCaves.scatter_gems: {msg}");
            }
        }
        out
    }

    /// Carve + dress the cheese network into an offline volume.
    ///
    /// `height` is local column relief above `ground_y` (size `size_x * size_z`).
    /// `portals_xz` is flat local `[x0,z0, x1,z1, …]` mouth positions from GDScript.
    /// Returns a stats dictionary (`ok`, chamber/link counts, hollow %, ms).
    #[func]
    fn carve_cheese(
        &mut self,
        mut volume: Gd<NativeOfflineVoxelVolume>,
        origin_x: i32,
        origin_z: i32,
        size_x: i32,
        size_z: i32,
        ground_y: i32,
        height: PackedInt32Array,
        portals_xz: PackedInt32Array,
        seed: i64,
    ) -> Dictionary<Variant, Variant> {
        let mut out = Dictionary::<Variant, Variant>::new();
        out.set("ok", false);
        if size_x <= 0 || size_z <= 0 {
            godot_error!("NativeHillCaves: degenerate size {size_x}x{size_z}");
            return out;
        }
        if height.len() != (size_x * size_z) as usize {
            godot_error!(
                "NativeHillCaves: height len {} != {}x{}",
                height.len(),
                size_x,
                size_z
            );
            return out;
        }
        if portals_xz.len() < 2 || portals_xz.len() % 2 != 0 {
            godot_error!("NativeHillCaves: portals_xz must be non-empty x,z pairs");
            return out;
        }
        let mut portals = Vec::with_capacity(portals_xz.len() / 2);
        for i in (0..portals_xz.len()).step_by(2) {
            portals.push(IVec2 {
                x: portals_xz[i],
                y: portals_xz[i + 1],
            });
        }
        let height_vec: Vec<i32> = (0..height.len()).map(|i| height[i]).collect();
        let started = Instant::now();
        let mut vol = volume.bind_mut();
        let mut ctx = Ctx::new(
            &mut vol,
            origin_x,
            origin_z,
            size_x,
            size_z,
            ground_y,
            height_vec,
            seed as u64,
        );
        let stats = ctx.carve_cheese(&portals);
        let ms = started.elapsed().as_millis() as i64;
        out.set("ok", true);
        out.set("chambers", stats.chambers as i64);
        out.set("links", stats.links as i64);
        out.set("mouths", portals.len() as i64);
        out.set("swells", stats.swells as i64);
        out.set("hollow", stats.hollow as f64);
        out.set("reachable", stats.reachable as f64);
        out.set("ms", ms);
        out
    }
}

#[derive(Clone, Copy)]
struct IVec2 {
    x: i32,
    y: i32,
}

#[derive(Clone, Copy)]
struct IVec3 {
    x: i32,
    y: i32,
    z: i32,
}

#[derive(Clone)]
struct Node {
    x: i32,
    y: i32,
    z: i32,
    rx: i32,
    ry: i32,
    rz: i32,
    kind_crypt: bool,
    gx: i32,
    gy: i32,
    gz: i32,
}

struct Link {
    from: IVec3,
    to: IVec3,
    vertical: bool,
    radius: i32,
}

struct Stats {
    chambers: usize,
    links: usize,
    swells: i32,
    hollow: f32,
    reachable: f32,
}

/// Tiny PCG-ish LCG — fine for procgen look; not Godot-compatible.
struct Rng {
    state: u64,
}

impl Rng {
    fn new(seed: u64) -> Self {
        Self {
            state: seed.wrapping_mul(0x9E37_79B9_7F4A_7C15).wrapping_add(1),
        }
    }

    fn next_u32(&mut self) -> u32 {
        self.state = self
            .state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1);
        (self.state >> 32) as u32
    }

    fn gen_f32(&mut self) -> f32 {
        (self.next_u32() as f32) / (u32::MAX as f32)
    }

    fn gen_bool(&mut self, p: f32) -> bool {
        self.gen_f32() < p
    }

    /// Inclusive range, Godot `randi_range` style.
    fn gen_range_i32(&mut self, lo: i32, hi: i32) -> i32 {
        if hi <= lo {
            return lo;
        }
        let span = (hi as i64 - lo as i64 + 1) as u32;
        lo + (self.next_u32() % span) as i32
    }

    fn gen_mod(&mut self, n: i32) -> i32 {
        if n <= 0 {
            return 0;
        }
        (self.next_u32() % n as u32) as i32
    }
}

struct Ctx<'a> {
    vol: &'a mut NativeOfflineVoxelVolume,
    ox: i32,
    oz: i32,
    w: i32,
    d: i32,
    ground_y: i32,
    height: Vec<i32>,
    cave_lo: Vec<i32>,
    cave_hi: Vec<i32>,
    shell_guard: bool,
    rng: Rng,
}

impl<'a> Ctx<'a> {
    fn new(
        vol: &'a mut NativeOfflineVoxelVolume,
        ox: i32,
        oz: i32,
        w: i32,
        d: i32,
        ground_y: i32,
        height: Vec<i32>,
        seed: u64,
    ) -> Self {
        let n = (w * d) as usize;
        Self {
            vol,
            ox,
            oz,
            w,
            d,
            ground_y,
            height,
            cave_lo: vec![-1; n],
            cave_hi: vec![-1; n],
            shell_guard: true,
            rng: Rng::new(seed),
        }
    }

    fn idx(&self, x: i32, z: i32) -> usize {
        (z * self.w + x) as usize
    }

    fn height_at(&self, x: i32, z: i32) -> i32 {
        if x < 0 || z < 0 || x >= self.w || z >= self.d {
            return 0;
        }
        self.height[self.idx(x, z)]
    }

    fn get(&self, wx: i32, y: i32, wz: i32) -> i32 {
        self.vol.raw(Vector3i::new(wx, y, wz)) as i32
    }

    fn set(&mut self, wx: i32, y: i32, wz: i32, mat: i32) {
        self.vol
            .set_raw(Vector3i::new(wx, y, wz), mat.clamp(0, 65535) as u16);
    }

    fn carve_cheese(&mut self, portals: &[IVec2]) -> Stats {
        let mut nodes = self.build_cavern_nodes();
        if nodes.len() < 2 {
            return Stats {
                chambers: nodes.len(),
                links: 0,
                swells: 0,
                hollow: 0.0,
                reachable: 0.0,
            };
        }
        let mut by_key: HashMap<(i32, i32, i32), usize> = HashMap::new();
        for (i, n) in nodes.iter().enumerate() {
            by_key.insert((n.gx, n.gy, n.gz), i);
        }
        for i in 0..nodes.len() {
            self.carve_room(&nodes[i]);
        }
        self.bulge_caverns(&nodes);
        let links = self.link_caverns(&nodes, &by_key);
        for link in &links {
            if link.vertical {
                self.carve_shaft(link.from, link.to);
            } else {
                self.carve_passage(link.from, link.to, link.radius, true);
            }
        }
        self.carve_mouths(portals, &nodes);
        let mut hollow = self.measure_core_hollow();
        let mut swells = 0;
        while hollow < CAVE_HOLLOW_TARGET && swells < 4 {
            hollow = self.widen_caverns(&mut nodes);
            swells += 1;
        }
        let reachable = self.audit_reachable(portals);
        self.dress_cave_system(&nodes);
        Stats {
            chambers: nodes.len(),
            links: links.len(),
            swells,
            hollow,
            reachable,
        }
    }

    fn build_cavern_nodes(&mut self) -> Vec<Node> {
        let mut out = Vec::new();
        let margin = CAVE_ROOM_R_MAX + 4;
        if self.w < margin * 3 || self.d < margin * 3 {
            return out;
        }
        let jit = CAVE_CELL_XZ / 4;
        let mut gz = 0;
        let mut bz = margin;
        while bz < self.d - margin {
            let mut gx = 0;
            let mut bx = margin;
            while bx < self.w - margin {
                let mut gy = 0;
                let mut level_y = self.ground_y + CAVE_CLEARANCE_RY + 3;
                while gy < CAVE_MAX_LEVELS {
                    let x = (bx + self.rng.gen_range_i32(-jit, jit)).clamp(margin, self.w - margin - 1);
                    let z = (bz + self.rng.gen_range_i32(-jit, jit)).clamp(margin, self.d - margin - 1);
                    let rx = self.rng.gen_range_i32(CAVE_ROOM_R_MIN, CAVE_ROOM_R_MAX);
                    let rz = self.rng.gen_range_i32(CAVE_ROOM_R_MIN, CAVE_ROOM_R_MAX);
                    let ry = CAVE_CLEARANCE_RY + self.rng.gen_mod(CAVE_ROOM_RY_EXTRA + 1);
                    let cy = level_y + self.rng.gen_range_i32(-1, 2);
                    let ceiling = self.ground_y + self.min_height_in_rect(x, z, rx, rz) - CAVE_SHELL;
                    if cy + ry > ceiling {
                        break;
                    }
                    let kind_crypt = gy == 0 && self.rng.gen_bool(0.18);
                    out.push(Node {
                        x,
                        y: cy,
                        z,
                        rx,
                        ry,
                        rz,
                        kind_crypt,
                        gx,
                        gy,
                        gz,
                    });
                    gy += 1;
                    level_y += CAVE_CELL_Y;
                }
                gx += 1;
                bx += CAVE_CELL_XZ;
            }
            gz += 1;
            bz += CAVE_CELL_XZ;
        }
        out
    }

    fn min_height_in_rect(&self, cx: i32, cz: i32, rx: i32, rz: i32) -> i32 {
        let mut lo = PEAK_MAX * 2;
        let mut z = (cz - rz).max(0);
        let z_end = (cz + rz).min(self.d - 1);
        let x_end = (cx + rx).min(self.w - 1);
        while z <= z_end {
            let row = z * self.w;
            let mut x = (cx - rx).max(0);
            while x <= x_end {
                lo = lo.min(self.height[(row + x) as usize]);
                x += 3;
            }
            z += 3;
        }
        lo
    }

    fn bulge_caverns(&mut self, nodes: &[Node]) {
        for node in nodes {
            let lobes = 2 + self.rng.gen_mod(3);
            for _ in 0..lobes {
                let ang = self.rng.gen_f32() * TAU;
                let ox = node.x + (ang.cos() * node.rx as f32 * 0.8).round() as i32;
                let oz = node.z + (ang.sin() * node.rz as f32 * 0.8).round() as i32;
                let oy = node.y + self.rng.gen_range_i32(-node.ry / 2, node.ry / 2);
                let rx = 3 + self.rng.gen_mod(4);
                let rz = 3 + self.rng.gen_mod(4);
                let floor_min = self.ground_y - CAVE_PIT_DEPTH;
                self.carve_ellipsoid(
                    IVec3 {
                        x: self.ox + ox,
                        y: oy,
                        z: self.oz + oz,
                    },
                    IVec3 {
                        x: rx,
                        y: CAVE_CLEARANCE_RY,
                        z: rz,
                    },
                    floor_min,
                );
            }
        }
    }

    fn link_caverns(
        &mut self,
        nodes: &[Node],
        by_key: &HashMap<(i32, i32, i32), usize>,
    ) -> Vec<Link> {
        let n = nodes.len();
        let mut parent: Vec<usize> = (0..n).collect();
        let dirs = [(1, 0, 0), (0, 0, 1), (0, 1, 0)];
        let mut cands: Vec<(usize, usize, bool)> = Vec::new();
        for (i, node) in nodes.iter().enumerate() {
            for (dx, dy, dz) in dirs {
                let key = (node.gx + dx, node.gy + dy, node.gz + dz);
                if let Some(&j) = by_key.get(&key) {
                    cands.push((i, j, dy != 0));
                }
            }
        }
        for i in (1..cands.len()).rev() {
            let j = self.rng.gen_mod((i + 1) as i32) as usize;
            cands.swap(i, j);
        }
        let mut links = Vec::new();
        for (a, b, vertical_edge) in cands {
            let ra = uf_find(&mut parent, a);
            let rb = uf_find(&mut parent, b);
            let needed = ra != rb;
            if !needed {
                let keep = if vertical_edge {
                    CAVE_LINK_P_VERT
                } else {
                    CAVE_LINK_P_HORZ
                };
                if !self.rng.gen_bool(keep) {
                    continue;
                }
            } else {
                parent[ra] = rb;
            }
            links.push(self.link_between(&nodes[a], &nodes[b]));
        }
        self.join_islands(nodes, &mut parent, &mut links);
        links
    }

    fn join_islands(&mut self, nodes: &[Node], parent: &mut [usize], links: &mut Vec<Link>) {
        let mut groups: HashMap<usize, Vec<usize>> = HashMap::new();
        for i in 0..nodes.len() {
            let root = uf_find(parent, i);
            groups.entry(root).or_default().push(i);
        }
        if groups.len() <= 1 {
            return;
        }
        let mut main_root = 0usize;
        let mut main_size = 0usize;
        for (&root, group) in &groups {
            if group.len() > main_size {
                main_size = group.len();
                main_root = root;
            }
        }
        let main = groups.get(&main_root).cloned().unwrap_or_default();
        let roots: Vec<usize> = groups.keys().copied().collect();
        for root in roots {
            if root == main_root {
                continue;
            }
            let island = match groups.get(&root) {
                Some(g) => g.clone(),
                None => continue,
            };
            let pick = island[0];
            let here = &nodes[pick];
            let mut best = None;
            let mut best_d = f32::MAX;
            for &cand_i in &main {
                let other = &nodes[cand_i];
                let dx = (other.x - here.x) as f32;
                let dy = (other.y - here.y) as f32;
                let dz = (other.z - here.z) as f32;
                let d = dx * dx + dy * dy + dz * dz;
                if d < best_d {
                    best_d = d;
                    best = Some(cand_i);
                }
            }
            let Some(best) = best else { continue };
            let link = self.link_between(here, &nodes[best]);
            links.push(link);
            let ra = uf_find(parent, pick);
            let rb = uf_find(parent, best);
            parent[ra] = rb;
        }
    }

    fn link_between(&mut self, a: &Node, b: &Node) -> Link {
        let from = IVec3 {
            x: a.x,
            y: a.y,
            z: a.z,
        };
        let to = IVec3 {
            x: b.x,
            y: b.y,
            z: b.z,
        };
        Link {
            from,
            to,
            vertical: (to.y - from.y).abs() >= CAVE_STEEP_DROP,
            radius: self.rng.gen_range_i32(CAVE_LINK_R_MIN, CAVE_LINK_R_MAX),
        }
    }

    fn carve_shaft(&mut self, a: IVec3, b: IVec3) {
        let (lo, hi) = if a.y <= b.y { (a, b) } else { (b, a) };
        let rise = hi.y - lo.y;
        if rise < CAVE_STEEP_DROP {
            self.carve_passage(lo, hi, CAVE_RADIUS + 1, true);
            return;
        }
        let cx = (lo.x + hi.x) as f32 * 0.5;
        let cz = (lo.z + hi.z) as f32 * 0.5;
        let rad = CAVE_SHAFT_RADIUS + self.rng.gen_f32() * 2.0;
        let turns = ((rise as f32) / (CAVE_SHAFT_RISE as f32)).max(1.0);
        let steps = ((turns * 44.0) as i32).max(32);
        let ang0 = self.rng.gen_f32() * TAU;
        let spin = if self.rng.gen_bool(0.5) { 1.0 } else { -1.0 };
        let mut first = lo;
        let mut last = lo;
        for i in 0..=steps {
            let t = i as f32 / steps as f32;
            let ang = ang0 + spin * t * turns * TAU;
            let x = ((cx + ang.cos() * rad).round() as i32).clamp(4, self.w - 5);
            let z = ((cz + ang.sin() * rad).round() as i32).clamp(4, self.d - 5);
            let y = lerp_i(lo.y, hi.y, t);
            let p = IVec3 {
                x,
                y: self.clamp_cave_y(x, z, y, CAVE_RADIUS),
                z,
            };
            self.carve_passage_slice(self.ox + p.x, p.y, self.oz + p.z, CAVE_RADIUS);
            if i == 0 {
                first = p;
            }
            last = p;
        }
        self.carve_passage_segment(lo, first, CAVE_RADIUS, 1);
        self.carve_passage_segment(last, hi, CAVE_RADIUS, 2);
        if self.rng.gen_bool(0.4) {
            let mx = (cx.round() as i32).clamp(4, self.w - 5);
            let mz = (cz.round() as i32).clamp(4, self.d - 5);
            self.carve_passage_segment(
                IVec3 {
                    x: mx,
                    y: lo.y,
                    z: mz,
                },
                IVec3 {
                    x: mx,
                    y: hi.y,
                    z: mz,
                },
                CAVE_RADIUS,
                3,
            );
        }
    }

    fn carve_mouths(&mut self, portals: &[IVec2], nodes: &[Node]) {
        for portal in portals {
            let target = self.nearest_node(*portal, nodes);
            let inner = IVec3 {
                x: target.x,
                y: target.y,
                z: target.z,
            };
            let mouth = IVec3 {
                x: portal.x,
                y: self.ground_y + CAVE_CLEARANCE_RY + 1,
                z: portal.y,
            };
            let throat = self.step_toward(mouth, inner, 14);
            // Meadow-side start so the opening cuts the hillside face.
            let outer = self.mouth_outer(*portal, throat, 8);
            self.shell_guard = false;
            self.carve_passage_segment(outer, throat, CAVE_RADIUS + 1, 0);
            self.shell_guard = true;
            self.carve_passage(throat, inner, CAVE_RADIUS + 1, true);
        }
    }

    fn mouth_outer(&self, portal: IVec2, throat: IVec3, dist: i32) -> IVec3 {
        let dx = (portal.x - throat.x) as f32;
        let dz = (portal.y - throat.z) as f32;
        let run = (dx * dx + dz * dz).sqrt().max(1.0);
        let x = (portal.x + (dx / run * dist as f32).round() as i32).clamp(4, self.w - 5);
        let z = (portal.y + (dz / run * dist as f32).round() as i32).clamp(4, self.d - 5);
        IVec3 {
            x,
            y: self.ground_y + CAVE_CLEARANCE_RY + 1,
            z,
        }
    }


    fn nearest_node<'b>(&self, portal: IVec2, nodes: &'b [Node]) -> &'b Node {
        let mut best = &nodes[0];
        let mut best_d = f32::MAX;
        for node in nodes {
            let dx = (node.x - portal.x) as f32;
            let dz = (node.z - portal.y) as f32;
            let dy = (node.y - self.ground_y) as f32 * 2.0;
            let d = dx * dx + dz * dz + dy * dy;
            if d < best_d {
                best_d = d;
                best = node;
            }
        }
        best
    }

    fn step_toward(&self, from: IVec3, to: IVec3, dist: i32) -> IVec3 {
        let dx = (to.x - from.x) as f32;
        let dz = (to.z - from.z) as f32;
        let run = (dx * dx + dz * dz).sqrt().max(1.0);
        if run <= dist as f32 {
            return to;
        }
        let t = dist as f32 / run;
        let x = (from.x + (dx * t).round() as i32).clamp(4, self.w - 5);
        let z = (from.z + (dz * t).round() as i32).clamp(4, self.d - 5);
        IVec3 {
            x,
            y: self.clamp_cave_y(x, z, from.y, CAVE_RADIUS),
            z,
        }
    }

    fn clamp_cave_y(&self, x: i32, z: i32, y: i32, ry: i32) -> i32 {
        let low = self.ground_y + ry;
        let high = self.ground_y + self.height_at(x, z) - CAVE_SHELL - ry;
        if high <= low {
            return low;
        }
        y.clamp(low, high)
    }

    fn measure_core_hollow(&self) -> f32 {
        let mut open = 0i32;
        let mut total = 0i32;
        let mut z = 4;
        while z < self.d - 4 {
            let row = z * self.w;
            let mut x = 4;
            while x < self.w - 4 {
                let top = self.ground_y + self.height[(row + x) as usize] - CAVE_SHELL;
                let mut y = self.ground_y + 1;
                while y <= top {
                    total += 1;
                    if self.get(self.ox + x, y, self.oz + z) == materials::AIR {
                        open += 1;
                    }
                    y += 2;
                }
                x += 4;
            }
            z += 4;
        }
        if total == 0 {
            return 0.0;
        }
        open as f32 / total as f32
    }

    fn widen_caverns(&mut self, nodes: &mut [Node]) -> f32 {
        for node in nodes.iter_mut() {
            node.rx += 1;
            node.rz += 1;
            if self.rng.gen_bool(0.5) {
                node.ry += 1;
            }
        }
        // Re-borrow: carve after mutating sizes.
        for i in 0..nodes.len() {
            let room = nodes[i].clone();
            self.carve_room(&room);
        }
        self.measure_core_hollow()
    }

    fn audit_reachable(&self, portals: &[IVec2]) -> f32 {
        let n = (self.w * self.d) as usize;
        let mut seen = vec![0u8; n];
        let mut open = 0;
        for i in 0..n {
            if self.cave_hi[i] >= 0 {
                open += 1;
            }
        }
        if open == 0 {
            return 0.0;
        }
        let mut queue = Vec::new();
        for portal in portals {
            let start = (portal.y * self.w + portal.x) as usize;
            if start >= n || self.cave_hi[start] < 0 || seen[start] == 1 {
                continue;
            }
            seen[start] = 1;
            queue.push(start);
        }
        let mut reached = queue.len();
        let mut head = 0;
        let steps = [(1, 0), (-1, 0), (0, 1), (0, -1)];
        while head < queue.len() {
            let idx = queue[head];
            head += 1;
            let x = (idx as i32) % self.w;
            let z = (idx as i32) / self.w;
            for (sx, sz) in steps {
                let nx = x + sx;
                let nz = z + sz;
                if nx < 0 || nz < 0 || nx >= self.w || nz >= self.d {
                    continue;
                }
                let ni = (nz * self.w + nx) as usize;
                if seen[ni] == 1 || self.cave_hi[ni] < 0 {
                    continue;
                }
                seen[ni] = 1;
                reached += 1;
                queue.push(ni);
            }
        }
        reached as f32 / open as f32
    }

    fn carve_room(&mut self, room: &Node) {
        self.carve_ellipsoid(
            IVec3 {
                x: self.ox + room.x,
                y: room.y,
                z: self.oz + room.z,
            },
            IVec3 {
                x: room.rx,
                y: room.ry,
                z: room.rz,
            },
            self.ground_y - CAVE_PIT_DEPTH,
        );
    }

    fn carve_passage(&mut self, from: IVec3, to: IVec3, radius: i32, force_meander: bool) {
        let points = self.meander_waypoints(from, to, force_meander);
        for i in 0..points.len().saturating_sub(1) {
            self.carve_passage_segment(points[i], points[i + 1], radius, i as i32);
        }
    }

    fn meander_waypoints(&mut self, from: IVec3, to: IVec3, force_meander: bool) -> Vec<IVec3> {
        let mut out = vec![from];
        let run = corridor_run_xz(from, to);
        if run < 8 && !force_meander {
            out.push(to);
            return out;
        }
        let dx = (to.x - from.x) as f32;
        let dz = (to.z - from.z) as f32;
        let plen = (dx * dx + dz * dz).sqrt().max(1.0);
        let px = -dz / plen;
        let pz = dx / plen;
        let mut bends = 1;
        if run >= CAVE_LONG_RUN || force_meander {
            bends = 2;
        }
        if run >= CAVE_LONG_RUN + 14 {
            bends = 3;
        }
        let mut amp = (run as f32 * CAVE_MEANDER_FRAC).max(5.0);
        if force_meander {
            amp = amp.max(8.0);
        }
        let sign = if self.rng.gen_bool(0.5) { 1.0 } else { -1.0 };
        for bi in 0..bends {
            let t = (bi as f32 + 1.0) / (bends as f32 + 1.0);
            let side = sign * if bi % 2 == 0 { 1.0 } else { -1.0 };
            let swing = amp * (0.55 + self.rng.gen_f32() * 0.55) * side;
            let y_wob = self.rng.gen_range_i32(-1, 1);
            let mut x = (lerp_f(from.x as f32, to.x as f32, t) + px * swing)
                .round() as i32;
            x = x.clamp(4, self.w - 5);
            let mut z = (lerp_f(from.z as f32, to.z as f32, t) + pz * swing)
                .round() as i32;
            z = z.clamp(4, self.d - 5);
            let mut y = self.clamp_cave_y(
                x,
                z,
                lerp_i(from.y, to.y, t) + y_wob,
                CAVE_CLEARANCE_RY,
            );
            if self.height_at(x, z) < CAVE_MOUTH_HEIGHT + 4 {
                x = (lerp_f(from.x as f32, to.x as f32, t) + px * swing * 0.35)
                    .round() as i32;
                x = x.clamp(4, self.w - 5);
                z = (lerp_f(from.z as f32, to.z as f32, t) + pz * swing * 0.35)
                    .round() as i32;
                z = z.clamp(4, self.d - 5);
                y = self.clamp_cave_y(x, z, y, CAVE_CLEARANCE_RY);
            }
            out.push(IVec3 { x, y, z });
        }
        out.push(to);
        out
    }

    fn carve_passage_segment(&mut self, from: IVec3, to: IVec3, radius: i32, seed_i: i32) {
        let dx = to.x - from.x;
        let dy = to.y - from.y;
        let dz = to.z - from.z;
        let steps = dx.abs().max(dz.abs()).max(dy.abs());
        if steps <= 0 {
            self.carve_passage_slice(self.ox + from.x, from.y, self.oz + from.z, radius);
            return;
        }
        let phase = from.x as f32 * 0.11 + from.z as f32 * 0.07 + seed_i as f32 * 1.7;
        for i in 0..=steps {
            let t = i as f32 / steps as f32;
            let mut x = lerp_i(from.x, to.x, t);
            let mut y = lerp_i(from.y, to.y, t);
            let mut z = lerp_i(from.z, to.z, t);
            let at_end = i == 0 || i == steps;
            let mut r = radius;
            if !at_end {
                let wob = (2.2 * (t * TAU * 1.1 + phase).sin()
                    + 1.1 * (t * TAU * 2.7 + phase * 1.3).sin())
                .round() as i32;
                if dx.abs() >= dz.abs() {
                    z += wob;
                } else {
                    x += wob;
                }
                let pulse = (t * TAU * 1.6 + phase * 0.5).sin();
                if (t * 9.0 + phase).sin().round() as i32 != 0 {
                    y = self.clamp_cave_y(
                        x,
                        z,
                        y + if pulse > 0.0 { 1 } else { -1 },
                        CAVE_CLEARANCE_RY,
                    );
                }
                let pulse_r = (t * TAU * 1.6 + phase * 0.5).sin();
                if pulse_r > 0.55 {
                    r = radius + 1;
                } else if pulse_r < -0.7 && radius > 2 {
                    r = radius - 1;
                }
            }
            self.carve_passage_slice(self.ox + x, y, self.oz + z, r);
        }
    }

    fn carve_passage_slice(&mut self, cx: i32, cy: i32, cz: i32, rxz: i32) {
        let lx = cx - self.ox;
        let lz = cz - self.oz;
        let (y, ry) = if self.shell_guard {
            (
                self.clamp_cave_y(lx, lz, cy, CAVE_CLEARANCE_RY),
                CAVE_CLEARANCE_RY,
            )
        } else {
            // Daylight mouth: must clear turf. Shell clamp used to leave portals
            // at CAVE_MOUTH_HEIGHT sealed under ~3 voxels of rock.
            let surface = self.ground_y + self.height_at(lx, lz);
            let floor_y = self.ground_y + 1;
            let top = surface + 1;
            let span = (top - floor_y).max(1) as f32;
            let ry = CAVE_CLEARANCE_RY.max((span * 0.5).ceil() as i32 + 1);
            (floor_y + ry, ry)
        };
        self.carve_ellipsoid(
            IVec3 { x: cx, y, z: cz },
            IVec3 {
                x: rxz,
                y: ry,
                z: rxz,
            },
            self.ground_y - CAVE_PIT_DEPTH,
        );
    }


    fn carve_ellipsoid(&mut self, center: IVec3, radii: IVec3, floor_min_y: i32) {
        if radii.x <= 0 || radii.y <= 0 || radii.z <= 0 {
            return;
        }
        let fx = radii.x as f32;
        let fy = radii.y as f32;
        let fz = radii.z as f32;
        let y0 = (center.y - radii.y).max(floor_min_y);
        for z in (center.z - radii.z)..=(center.z + radii.z) {
            let lz = z - self.oz;
            if lz < 0 || lz >= self.d {
                continue;
            }
            let row = lz * self.w;
            let nz = (z - center.z) as f32 / fz;
            for x in (center.x - radii.x)..=(center.x + radii.x) {
                let lx = x - self.ox;
                if lx < 0 || lx >= self.w {
                    continue;
                }
                let nx = (x - center.x) as f32 / fx;
                let mut y1 = center.y + radii.y;
                if self.shell_guard {
                    y1 = y1.min(self.ground_y + self.height[(row + lx) as usize] - CAVE_SHELL);
                }
                for y in y0..=y1 {
                    let ny = (y - center.y) as f32 / fy;
                    if nx * nx + ny * ny + nz * nz > 1.0 {
                        continue;
                    }
                    let id = self.get(x, y, z);
                    if materials::is_gem(id) {
                        continue;
                    }
                    self.set(x, y, z, materials::AIR);
                    let col = (row + lx) as usize;
                    if self.cave_hi[col] < 0 {
                        self.cave_lo[col] = y;
                        self.cave_hi[col] = y;
                    } else {
                        self.cave_lo[col] = self.cave_lo[col].min(y);
                        self.cave_hi[col] = self.cave_hi[col].max(y);
                    }
                }
            }
        }
    }

    fn dress_cave_system(&mut self, rooms: &[Node]) {
        let deck_floor = self.ground_y - CAVE_PIT_DEPTH;
        for z in 0..self.d {
            let row = z * self.w;
            for x in 0..self.w {
                let hi = self.cave_hi[(row + x) as usize];
                if hi < 0 {
                    continue;
                }
                let wx = self.ox + x;
                let wz = self.oz + z;
                let lo = self.cave_lo[(row + x) as usize];
                let y_start = (lo - 1).max(deck_floor);
                for y in y_start..=(hi + 1) {
                    let here = self.get(wx, y, wz);
                    if materials::is_gem(here) {
                        continue;
                    }
                    if here == materials::AIR {
                        let below = self.get(wx, y - 1, wz);
                        if materials::is_gem(below) {
                            continue;
                        }
                        if materials::is_cave_shellable(below) {
                            self.set(wx, y - 1, wz, materials::CAVE_FLOOR);
                        }
                        continue;
                    }
                    if !materials::is_cave_shellable(here) {
                        continue;
                    }
                    if self.air_neighbour(wx, y, wz) {
                        self.set(wx, y, wz, materials::CAVE_WALL);
                    }
                }
            }
        }
        for room in rooms {
            self.dress_cave_room(room);
        }
    }

    fn air_neighbour(&self, wx: i32, y: i32, wz: i32) -> bool {
        self.get(wx, y - 1, wz) == materials::AIR
            || self.get(wx, y + 1, wz) == materials::AIR
            || self.get(wx + 1, y, wz) == materials::AIR
            || self.get(wx - 1, y, wz) == materials::AIR
            || self.get(wx, y, wz + 1) == materials::AIR
            || self.get(wx, y, wz - 1) == materials::AIR
    }

    fn dress_cave_room(&mut self, room: &Node) {
        let sx = room.x;
        let sz = room.z;
        let cy = room.y;
        let rx = room.rx;
        let ry = room.ry;
        let rz = room.rz;
        if room.kind_crypt {
            let pool_r = rx.min(rz) - 1;
            if pool_r >= 2 {
                for z in (sz - pool_r)..=(sz + pool_r) {
                    for x in (sx - pool_r)..=(sx + pool_r) {
                        if (x - sx) * (x - sx) + (z - sz) * (z - sz) > pool_r * pool_r {
                            continue;
                        }
                        let wx = self.ox + x;
                        let wz = self.oz + z;
                        let fy = cy - ry;
                        if self.get(wx, fy + 1, wz) == materials::AIR {
                            self.set(wx, fy, wz, materials::WATER);
                        }
                    }
                }
            }
        }
        let features = 3 + self.rng.gen_mod(5);
        for _ in 0..features {
            let px = sx + self.rng.gen_range_i32(-rx + 1, rx - 1);
            let pz = sz + self.rng.gen_range_i32(-rz + 1, rz - 1);
            let wx2 = self.ox + px;
            let wz2 = self.oz + pz;
            if self.rng.gen_bool(0.55) {
                let mut base_y = cy - ry;
                while base_y < cy + ry && self.get(wx2, base_y, wz2) != materials::AIR {
                    base_y += 1;
                }
                if self.get(wx2, base_y, wz2) == materials::AIR {
                    let h = 1 + self.rng.gen_mod(2);
                    for dy in 0..h {
                        let y = base_y + dy;
                        if self.get(wx2, y, wz2) != materials::AIR {
                            break;
                        }
                        self.set(wx2, y, wz2, materials::CAVE_WALL);
                    }
                }
            } else {
                let mut top_y = cy + ry;
                while top_y > cy - ry && self.get(wx2, top_y, wz2) != materials::AIR {
                    top_y -= 1;
                }
                let clear_floor = cy - ry + CAVE_WALK_CLEARANCE;
                if self.get(wx2, top_y, wz2) == materials::AIR {
                    let h2 = 2 + self.rng.gen_mod(4);
                    for dy2 in 0..h2 {
                        let y = top_y - dy2;
                        if y <= clear_floor {
                            break;
                        }
                        if self.get(wx2, y, wz2) != materials::AIR {
                            break;
                        }
                        self.set(wx2, y, wz2, materials::CAVE_WALL);
                    }
                }
            }
        }
        if rx >= 6 {
            let pillars = 1 + self.rng.gen_mod(3);
            for _ in 0..pillars {
                if !self.rng.gen_bool(0.55) {
                    continue;
                }
                let qx = self.ox + sx + self.rng.gen_range_i32(-rx / 2, rx / 2);
                let qz = self.oz + sz + self.rng.gen_range_i32(-rz / 2, rz / 2);
                let y0 = cy - ry + 1;
                let y1 = cy + ry - 1;
                if y0 < y1 {
                    for y in y0..y1 {
                        // Ore is budgeted: the tile owes exactly the gems that were embedded
                        // before the carve, so a pillar grows around a nugget, not through it.
                        if materials::is_gem(self.get(qx, y, qz)) {
                            continue;
                        }
                        self.set(qx, y, qz, materials::CAVE_WALL);
                    }
                }
            }
        }
    }
}

fn uf_find(parent: &mut [usize], i: usize) -> usize {
    let mut root = i;
    while parent[root] != root {
        root = parent[root];
    }
    let mut walk = i;
    while parent[walk] != walk {
        let next = parent[walk];
        parent[walk] = root;
        walk = next;
    }
    root
}

fn corridor_run_xz(from: IVec3, to: IVec3) -> i32 {
    let dx = to.x - from.x;
    let dz = to.z - from.z;
    ((dx * dx + dz * dz) as f32).sqrt().round() as i32
}

fn lerp_f(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

fn lerp_i(a: i32, b: i32, t: f32) -> i32 {
    lerp_f(a as f32, b as f32, t).round() as i32
}
