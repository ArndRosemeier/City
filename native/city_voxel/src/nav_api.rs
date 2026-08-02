//! Godot bindings for the navigation core.
//!
//! Two classes, split by thread affinity. `NativeNavBake` is created on a district bake
//! worker and owns nothing shared. `NativeNavWorld` lives on the main thread and is the
//! registry every agent queries.
//!
//! Everything crossing this boundary is in world metres; internals stay in voxels.

use godot::prelude::*;

/// Godot dictionaries are generic in gdext; the engine-facing ones stay untyped.
type Dict = Dictionary<Variant, Variant>;

use crate::nav::{
    bake_field, link_reach, link_reach_y, LinkParams, NavField, Profile, Solidity, SpanId,
    VoxelSource, LINK_CLIMB, LINK_DROP, LINK_JUMP, LINK_WALK, SOL_PARTIAL, SOL_PASSABLE,
    SOL_SOLID, SOL_WATER,
};
use crate::nav_world::{NavWorld, PathStatus};
use crate::NativeOfflineVoxelVolume;

/// Reads a baked district volume, which stores district-local coordinates.
struct VolumeSource<'a> {
    volume: &'a NativeOfflineVoxelVolume,
    origin_x: i32,
    origin_z: i32,
}

impl<'a> VoxelSource for VolumeSource<'a> {
    #[inline]
    fn mat(&self, x: i32, y: i32, z: i32) -> u16 {
        self.volume
            .raw(Vector3i::new(x - self.origin_x, y, z - self.origin_z))
    }
}

/// Reads a dense material box copied out of the live terrain.
struct BufferSource<'a> {
    /// Terrain TYPE channel copy: `stride` bytes per voxel. City uses stride 2 (LE u16).
    /// Stride 1 is accepted for older fixtures (material in the single byte).
    data: &'a [u8],
    stride: usize,
    min: (i32, i32, i32),
    size: (i32, i32, i32),
    outside: u16,
}

impl VoxelSource for BufferSource<'_> {
    #[inline]
    fn mat(&self, x: i32, y: i32, z: i32) -> u16 {
        let lx = x - self.min.0;
        let ly = y - self.min.1;
        let lz = z - self.min.2;
        if lx < 0 || ly < 0 || lz < 0 || lx >= self.size.0 || ly >= self.size.1 || lz >= self.size.2
        {
            return self.outside;
        }
        let idx = (ly + lx * self.size.1 + lz * self.size.1 * self.size.0) as usize;
        let base = idx * self.stride;
        if self.stride >= 2 {
            let lo = self.data[base] as u16;
            let hi = self.data[base + 1] as u16;
            lo | (hi << 8)
        } else {
            self.data[base] as u16
        }
    }
}

/// A class byte outside the four known values would fall through every `SOL_*` match and
/// read as thin air, so a typo in the GDScript table would quietly turn a wall into a
/// doorway. Such a material keeps the default of solid and says so instead.
fn solidity_from(
    class: &PackedByteArray,
    top: &PackedFloat32Array,
    destructible: &PackedByteArray,
    climbable: &PackedByteArray,
) -> Solidity {
    let n = class
        .len()
        .max(top.len())
        .max(destructible.len())
        .max(climbable.len())
        .max(crate::materials::COUNT as usize);
    let mut sol = Solidity::with_len(n);
    for i in 0..n {
        if i < class.len() {
            let c = class[i];
            if !(SOL_PASSABLE..=SOL_PARTIAL).contains(&c) {
                godot_error!(
                    "NavSolidity: material {i} has class {c}, and the classes are \
                     {SOL_PASSABLE} passable, {SOL_WATER} water, {SOL_SOLID} solid, \
                     {SOL_PARTIAL} partial"
                );
            } else {
                sol.class[i] = c;
            }
        }
        if i < top.len() {
            sol.top[i] = top[i];
        }
        if i < destructible.len() {
            sol.destructible[i] = destructible[i] != 0;
        }
        if i < climbable.len() {
            sol.climbable[i] = climbable[i] != 0;
        }
    }
    sol
}

fn link_params_from(d: &Dict) -> LinkParams {
    let get_f = |key: &str, fallback: f32| -> f32 {
        d.get(key)
            .and_then(|v| v.try_to::<f32>().ok())
            .unwrap_or(fallback)
    };
    let get_i = |key: &str, fallback: i32| -> i32 {
        d.get(key)
            .and_then(|v| v.try_to::<i32>().ok())
            .unwrap_or(fallback)
    };
    let def = LinkParams::default();
    LinkParams {
        max_climb: get_f("max_climb_vox", def.max_climb),
        climb_chest: get_f("climb_chest_vox", def.climb_chest),
        climb_head: get_f("climb_head_vox", def.climb_head),
        max_jump_gap: get_i("max_jump_gap_cells", def.max_jump_gap),
        max_jump_up: get_f("max_jump_up_vox", def.max_jump_up),
        climb_cost: get_f("climb_cost", def.climb_cost),
        min_drop: get_f("min_drop_vox", def.min_drop),
        max_drop: get_f("max_drop_vox", def.max_drop),
    }
}

// ---------------------------------------------------------------------------
// Bake
// ---------------------------------------------------------------------------

/// One district's navigation data, produced off the main thread.
#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct NativeNavBake {
    base: Base<RefCounted>,
    pub(crate) field: Option<NavField>,
}

#[godot_api]
impl IRefCounted for NativeNavBake {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base, field: None }
    }
}

#[godot_api]
impl NativeNavBake {
    /// Extract spans, clearance, components, portals and traversal links for a district.
    ///
    /// Runs on a bake worker: it touches only the volume it is handed.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn bake_from_volume(
        &mut self,
        volume: Gd<NativeOfflineVoxelVolume>,
        origin_vox: Vector3i,
        size_x: i32,
        size_z: i32,
        y_min: i32,
        y_max: i32,
        solid_class: PackedByteArray,
        solid_top: PackedFloat32Array,
        solid_destructible: PackedByteArray,
        solid_climbable: PackedByteArray,
        link_params: Dict,
    ) -> bool {
        if size_x <= 0 || size_z <= 0 || y_max <= y_min {
            godot_error!(
                "NativeNavBake: refusing degenerate district {size_x}x{size_z} y {y_min}..{y_max}"
            );
            return false;
        }
        let sol = solidity_from(
            &solid_class,
            &solid_top,
            &solid_destructible,
            &solid_climbable,
        );
        let params = link_params_from(&link_params);
        let bound = volume.bind();
        let src = VolumeSource {
            volume: &bound,
            origin_x: origin_vox.x,
            origin_z: origin_vox.z,
        };
        self.field = Some(bake_field(
            &src,
            &sol,
            origin_vox.x,
            origin_vox.z,
            size_x,
            size_z,
            y_min,
            y_max,
            &params,
        ));
        true
    }

    #[func]
    fn is_ready(&self) -> bool {
        self.field.is_some()
    }

    #[func]
    fn stats(&self) -> Dict {
        let mut d = Dict::new();
        let Some(field) = &self.field else {
            d.set("ok", false);
            return d;
        };
        let s = field.stats();
        d.set("ok", true);
        d.set("columns", s.columns as i64);
        d.set("spans", s.spans as i64);
        d.set("max_spans_per_column", s.max_spans_per_column as i64);
        d.set("nodes", s.nodes as i64);
        d.set("portals", s.portals as i64);
        d.set("links", s.links as i64);
        d.set("bytes", s.bytes as i64);
        d.set("sectors", field.sectors.len() as i64);
        d
    }
}

// ---------------------------------------------------------------------------
// World
// ---------------------------------------------------------------------------

/// The navigation registry every agent queries.
#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct NativeNavWorld {
    base: Base<RefCounted>,
    world: NavWorld,
}

#[godot_api]
impl IRefCounted for NativeNavWorld {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            base,
            world: NavWorld::new(),
        }
    }
}

#[godot_api]
impl NativeNavWorld {
    #[func]
    fn configure(
        &mut self,
        voxel_size: f32,
        solid_class: PackedByteArray,
        solid_top: PackedFloat32Array,
        solid_destructible: PackedByteArray,
        solid_climbable: PackedByteArray,
        link_params: Dict,
    ) {
        if voxel_size <= 0.0 {
            godot_error!("NativeNavWorld.configure: voxel_size must be positive");
            return;
        }
        self.world.voxel_size = voxel_size;
        self.world.solidity = solidity_from(
            &solid_class,
            &solid_top,
            &solid_destructible,
            &solid_climbable,
        );
        self.world.link_params = link_params_from(&link_params);
    }

    /// Register an agent body. Surface costs below 1.0 would break the search heuristic,
    /// so preference is expressed by making other surfaces dearer.
    #[func]
    fn register_profile(&mut self, id: i32, spec: Dict) {
        let get_f = |key: &str, fallback: f32| -> f32 {
            spec.get(key)
                .and_then(|v| v.try_to::<f32>().ok())
                .unwrap_or(fallback)
        };
        let get_i = |key: &str, fallback: i32| -> i32 {
            spec.get(key)
                .and_then(|v| v.try_to::<i32>().ok())
                .unwrap_or(fallback)
        };
        let get_b = |key: &str, fallback: bool| -> bool {
            spec.get(key)
                .and_then(|v| v.try_to::<bool>().ok())
                .unwrap_or(fallback)
        };
        let def = Profile::default();
        let mut surface_cost = vec![1.0f32; crate::materials::COUNT as usize];
        if let Some(v) = spec.get("surface_cost") {
            if let Ok(arr) = v.try_to::<PackedFloat32Array>() {
                if arr.len() > surface_cost.len() {
                    surface_cost.resize(arr.len(), 1.0);
                }
                for i in 0..surface_cost.len().min(arr.len()) {
                    let c = arr[i];
                    if c < 1.0 {
                        godot_error!(
                            "NativeNavWorld.register_profile: surface_cost[{i}] = {c} is below 1.0"
                        );
                    }
                    surface_cost[i] = c.max(1.0);
                }
            }
        }
        let profile = Profile {
            radius_cells: get_i("radius_cells", def.radius_cells as i32).clamp(0, 255) as u8,
            height_cells: get_i("height_cells", def.height_cells as i32).clamp(1, 255) as u8,
            max_step: get_f("max_step_vox", def.max_step),
            max_drop: get_f("max_drop_vox", def.max_drop),
            max_wade: get_i("max_wade_cells", def.max_wade as i32).clamp(0, 255) as u8,
            can_swim: get_b("can_swim", def.can_swim),
            can_climb: get_b("can_climb", def.can_climb),
            can_jump: get_b("can_jump", def.can_jump),
            can_break: get_b("can_break", def.can_break),
            surface_cost,
        };
        // Walking covers descents down to `max_drop` and drop links start just past
        // `min_drop`. A body between the two would meet descents it can neither walk
        // nor take a link for, and would simply be stranded on the ledge.
        let min_drop = self.world.link_params.min_drop;
        if profile.max_drop < min_drop {
            godot_error!(
                "NativeNavWorld.register_profile: profile {id} drops {} voxels but links only \
                 start past {min_drop}, leaving descents it cannot make at all",
                profile.max_drop
            );
        }
        self.world.set_profile(id, profile);
    }

    #[func]
    fn has_profile(&self, id: i32) -> bool {
        self.world.profile(id).is_some()
    }

    /// Hand a finished bake to the world. The bake is emptied so the data is not copied.
    #[func]
    fn insert_bake(&mut self, coord: Vector2i, mut bake: Gd<NativeNavBake>) -> bool {
        let field = bake.bind_mut().field.take();
        let Some(field) = field else {
            godot_error!("NativeNavWorld.insert_bake: bake for {coord} holds no field");
            return false;
        };
        self.world.insert_field((coord.x, coord.y), field);
        true
    }

    #[func]
    fn remove_district(&mut self, coord: Vector2i) -> bool {
        self.world.remove_field((coord.x, coord.y))
    }

    #[func]
    fn has_district(&self, coord: Vector2i) -> bool {
        self.world.field_at((coord.x, coord.y)).is_some()
    }

    #[func]
    fn district_count(&self) -> i32 {
        self.world.field_count() as i32
    }

    #[func]
    fn district_stats(&self, coord: Vector2i) -> Dict {
        let mut d = Dict::new();
        let Some(field) = self.world.field_at((coord.x, coord.y)) else {
            d.set("ok", false);
            return d;
        };
        let s = field.stats();
        d.set("ok", true);
        d.set("columns", s.columns as i64);
        d.set("spans", s.spans as i64);
        d.set("max_spans_per_column", s.max_spans_per_column as i64);
        d.set("nodes", s.nodes as i64);
        d.set("portals", s.portals as i64);
        d.set("links", s.links as i64);
        d.set("bytes", s.bytes as i64);
        d.set("version", field.version as i64);
        d
    }

    #[func]
    fn version(&self) -> i64 {
        self.world.version as i64
    }

    #[func]
    fn advance_time(&mut self, now: f64) {
        self.world.advance_time(now);
    }

    /// Temporarily mark the column under a world position impassable.
    #[func]
    fn block_world_column(&mut self, world_pos: Vector3, seconds: f32) {
        let vs = self.world.voxel_size;
        let x = (world_pos.x / vs).floor() as i32;
        let z = (world_pos.z / vs).floor() as i32;
        self.world.block_column(x, z, seconds);
    }

    #[func]
    fn find_path(
        &mut self,
        profile_id: i32,
        from_world: Vector3,
        to_world: Vector3,
        budget: i32,
    ) -> Dict {
        let vs = self.world.voxel_size;
        let from = [from_world.x / vs, from_world.y / vs, from_world.z / vs];
        let to = [to_world.x / vs, to_world.y / vs, to_world.z / vs];
        let budget = budget.clamp(64, 1_000_000) as usize;
        let r = self.world.find_path(profile_id, from, to, budget);

        let mut points = PackedVector3Array::new();
        for p in &r.points {
            points.push(Vector3::new(p[0] * vs, p[1] * vs, p[2] * vs));
        }
        let mut links = PackedByteArray::new();
        for k in &r.link_kinds {
            links.push(*k);
        }
        let mut d = Dict::new();
        d.set("status", r.status.code());
        d.set("points", &points);
        d.set("links", &links);
        d.set("raw_points", r.raw_points as i64);
        d.set("expanded", r.expanded as i64);
        d.set("usable", matches!(r.status, PathStatus::Ok | PathStatus::Partial | PathStatus::Breach));
        d
    }

    #[func]
    fn reachable(&mut self, profile_id: i32, from_world: Vector3, to_world: Vector3) -> bool {
        let vs = self.world.voxel_size;
        self.world.reachable(
            profile_id,
            [from_world.x / vs, from_world.y / vs, from_world.z / vs],
            [to_world.x / vs, to_world.y / vs, to_world.z / vs],
        )
    }

    /// Snap a world position onto the nearest surface this body can occupy.
    #[func]
    fn nearest_surface(&self, profile_id: i32, world_pos: Vector3, radius_m: f32) -> Dict {
        let vs = self.world.voxel_size;
        let mut d = Dict::new();
        let Some(profile) = self.world.profile(profile_id) else {
            godot_error!("NativeNavWorld.nearest_surface: unknown profile {profile_id}");
            d.set("found", false);
            d.set("position", world_pos);
            return d;
        };
        let radius_cells = ((radius_m / vs).ceil() as i32).clamp(0, 64);
        match self.world.nearest_span(
            world_pos.x / vs,
            world_pos.y / vs,
            world_pos.z / vs,
            profile,
            radius_cells,
        ) {
            Some(key) => {
                let s = *self.world.span_of(key);
                let p = self.world.span_pos(key);
                d.set("found", true);
                d.set("position", Vector3::new(p[0] * vs, p[1] * vs, p[2] * vs));
                d.set("clearance", s.clearance as i64);
                d.set("headroom", s.headroom as i64);
                d.set("water_depth", s.water_depth as i64);
            }
            None => {
                d.set("found", false);
                d.set("position", world_pos);
            }
        }
        d
    }

    /// Standable surfaces in the column under `world_pos`, within `radius_m` vertically.
    ///
    /// One column only — no ring search. Wander uses this after picking an XZ probe so
    /// multi-level destinations stay cheap.
    #[func]
    fn column_surfaces(
        &self,
        profile_id: i32,
        world_pos: Vector3,
        radius_m: f32,
    ) -> PackedVector3Array {
        let mut out = PackedVector3Array::new();
        let vs = self.world.voxel_size;
        let Some(profile) = self.world.profile(profile_id) else {
            godot_error!("NativeNavWorld.column_surfaces: unknown profile {profile_id}");
            return out;
        };
        let radius_cells = ((radius_m / vs).ceil() as i32).clamp(0, 64);
        for p in self.world.column_surfaces(
            world_pos.x / vs,
            world_pos.y / vs,
            world_pos.z / vs,
            profile,
            radius_cells,
        ) {
            out.push(Vector3::new(p[0] * vs, p[1] * vs, p[2] * vs));
        }
        out
    }

    /// Rebuild navigation for a voxel box after the world changed there.
    ///
    /// `materials` is a dense Y-major box copied from the terrain. `stride` is 1 for an
    /// 8 bit channel and 2 for the 16 bit channel the city uses.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn rebuild_region(
        &mut self,
        coord: Vector2i,
        min_vox: Vector3i,
        size_vox: Vector3i,
        materials: PackedByteArray,
        stride: i32,
    ) -> i32 {
        if size_vox.x <= 0 || size_vox.y <= 0 || size_vox.z <= 0 {
            godot_error!("NativeNavWorld.rebuild_region: empty box {size_vox}");
            return 0;
        }
        let stride = stride.max(1) as usize;
        let count = (size_vox.x * size_vox.y * size_vox.z) as usize;
        if materials.len() < count * stride {
            godot_error!(
                "NativeNavWorld.rebuild_region: got {} bytes, need {} for {size_vox} at stride {stride}",
                materials.len(),
                count * stride
            );
            return 0;
        }
        // Outside the box the world reads solid, so a box that stops short of the field's
        // own Y range would not fail — it would quietly bake rock into the gap. GDScript
        // sizes the copy from `rebuild_y_range`; this is what happens when it does not.
        let want = self.rebuild_y_range(coord);
        if want.y < want.x {
            return 0;
        }
        if min_vox.y > want.x || min_vox.y + size_vox.y - 1 < want.y {
            godot_error!(
                "NativeNavWorld.rebuild_region: district {coord} needs voxel rows {}..{}, the box carries {}..{}",
                want.x,
                want.y,
                min_vox.y,
                min_vox.y + size_vox.y - 1
            );
            return 0;
        }
        let src = BufferSource {
            data: materials.as_slice(),
            stride,
            min: (min_vox.x, min_vox.y, min_vox.z),
            size: (size_vox.x, size_vox.y, size_vox.z),
            // Outside the copied box the world is unknown; solid keeps the rebuild from
            // inventing openings at the box edge.
            outside: 1,
        };
        match self.world.rebuild_box(
            (coord.x, coord.y),
            min_vox.x,
            min_vox.z,
            min_vox.x + size_vox.x - 1,
            min_vox.z + size_vox.z - 1,
            &src,
        ) {
            Ok(sectors) => sectors as i32,
            Err(why) => {
                godot_error!("NativeNavWorld.rebuild_region: {why}");
                0
            }
        }
    }

    /// Columns of world a rebuild needs around every sector it rebuilds, so GDScript
    /// sizes the material copy from the bake rules instead of a hard-coded guess.
    #[func]
    fn link_reach_vox(&self) -> i64 {
        link_reach(&self.world.link_params) as i64
    }

    /// Inclusive voxel Y band a rebuild of this district has to be handed: the range the
    /// field occupies, plus the voxels the link probes read above it.
    ///
    /// The terrain is hundreds of voxels tall and a nav field is a fraction of that, so a
    /// material copy sized from the terrain spends most of itself on rock and sky the
    /// rescan never looks at. `x` above `y` means there is no such district.
    #[func]
    fn rebuild_y_range(&self, coord: Vector2i) -> Vector2i {
        let Some(field) = self.world.field_at((coord.x, coord.y)) else {
            godot_error!("NativeNavWorld.rebuild_y_range: no district at {coord}");
            return Vector2i::new(0, -1);
        };
        Vector2i::new(
            field.y_min,
            field.y_max + link_reach_y(&self.world.link_params),
        )
    }

    /// Microseconds the last `rebuild_region` spent per phase, so a frame budget can be
    /// spent where the time goes rather than where it is assumed to go.
    #[func]
    fn last_rebuild_timing(&self) -> Dict {
        let t = self.world.last_rebuild;
        let mut d = Dict::new();
        d.set("sectors", t.sectors as i64);
        d.set("spans_us", t.spans_us as i64);
        d.set("clearance_us", t.clearance_us as i64);
        d.set("links_us", t.links_us as i64);
        d.set("inbound_us", t.inbound_us as i64);
        d.set("components_us", t.components_us as i64);
        d.set("portals_us", t.portals_us as i64);
        d.set("total_us", t.total_us as i64);
        d
    }

    #[func]
    fn refresh_district(&mut self, coord: Vector2i) {
        self.world.refresh_field((coord.x, coord.y));
    }

    /// Spans near a point, for the navigation debug overlay.
    #[func]
    fn debug_spans(&self, centre_world: Vector3, radius_m: f32) -> Dict {
        let vs = self.world.voxel_size;
        let radius_cells = ((radius_m / vs).ceil() as i32).clamp(1, 96);
        let mut raw: Vec<(f32, f32, f32, u8, u8, u8)> = Vec::new();
        self.world.debug_spans(
            [centre_world.x / vs, centre_world.y / vs, centre_world.z / vs],
            radius_cells,
            &mut raw,
        );
        let mut positions = PackedVector3Array::new();
        let mut clearance = PackedByteArray::new();
        let mut headroom = PackedByteArray::new();
        let mut component = PackedByteArray::new();
        for (x, y, z, c, h, comp) in raw {
            positions.push(Vector3::new(x * vs, y * vs, z * vs));
            clearance.push(c);
            headroom.push(h);
            component.push(comp);
        }
        let mut d = Dict::new();
        d.set("positions", &positions);
        d.set("clearance", &clearance);
        d.set("headroom", &headroom);
        d.set("component", &component);
        d
    }

    /// Portal midpoints near a point, so the overlay can show the corridor graph.
    #[func]
    fn debug_portals(&self, centre_world: Vector3, radius_m: f32) -> PackedVector3Array {
        let vs = self.world.voxel_size;
        let mut out = PackedVector3Array::new();
        let r2 = radius_m * radius_m;
        for coord in self.world.district_coords() {
            let Some(field) = self.world.field_at(coord) else {
                continue;
            };
            for p in &field.portals {
                let w = Vector3::new(p.x * vs, p.y * vs, p.z * vs);
                let dx = w.x - centre_world.x;
                let dz = w.z - centre_world.z;
                if dx * dx + dz * dz <= r2 {
                    out.push(w);
                }
            }
        }
        out
    }

    /// Traversal links taking off near a point, for the debug overlay and for the headless
    /// test that pins the climb bake to the player's climb rules.
    #[func]
    fn debug_links(&self, centre_world: Vector3, radius_m: f32) -> Dict {
        let vs = self.world.voxel_size;
        let radius = radius_m / vs;
        let cx = centre_world.x / vs;
        let cz = centre_world.z / vs;
        let mut from = PackedVector3Array::new();
        let mut to = PackedVector3Array::new();
        let mut kind = PackedByteArray::new();
        let mut cost = PackedFloat32Array::new();
        for coord in self.world.district_coords() {
            let Some(field) = self.world.field_at(coord) else {
                continue;
            };
            for (si, sector) in field.sectors.iter().enumerate() {
                for (index, links) in &sector.links {
                    let id = SpanId {
                        sector: si as u32,
                        index: *index,
                    };
                    let (x, z) = field.span_xz(id);
                    let fx = x as f32 + 0.5;
                    let fz = z as f32 + 0.5;
                    if (fx - cx).abs() > radius || (fz - cz).abs() > radius {
                        continue;
                    }
                    let fy = field.span(id).surface_y;
                    for link in links {
                        from.push(Vector3::new(fx * vs, fy * vs, fz * vs));
                        to.push(Vector3::new(
                            (link.to_x as f32 + 0.5) * vs,
                            field.span(link.to).surface_y * vs,
                            (link.to_z as f32 + 0.5) * vs,
                        ));
                        kind.push(link.kind);
                        cost.push(link.cost);
                    }
                }
            }
        }
        let mut d = Dict::new();
        d.set("from", &from);
        d.set("to", &to);
        d.set("kind", &kind);
        d.set("cost", &cost);
        d
    }

    /// Constant mirrors so GDScript never hard-codes the link ids.
    #[func]
    fn link_walk_id() -> i64 {
        LINK_WALK as i64
    }

    #[func]
    fn link_climb_id() -> i64 {
        LINK_CLIMB as i64
    }

    #[func]
    fn link_drop_id() -> i64 {
        LINK_DROP as i64
    }

    #[func]
    fn link_jump_id() -> i64 {
        LINK_JUMP as i64
    }
}
