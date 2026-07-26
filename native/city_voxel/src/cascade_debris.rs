//! Native cascading voxel debris — PhysicsServer3D body pool + MultiMesh visuals.
use crate::materials;
use godot::classes::geometry_instance_3d::ShadowCastingSetting;
use godot::classes::multi_mesh::TransformFormat;
use godot::classes::node::PhysicsInterpolationMode;
use godot::classes::{
    BoxMesh, Engine, Material, MultiMesh, MultiMeshInstance3D, Node3D, Object, Time, INode,
};
use godot::global::godot_error;
use godot::prelude::*;
use std::collections::{HashMap, HashSet};

/// Huge local AABB so MultiMesh is never frustum-culled while instances are far from origin.
/// (Default zero custom_aabb + runtime buffer resize caused all-or-nothing flicker.)
fn debris_cull_aabb() -> Aabb {
    Aabb::new(
        Vector3::new(-4000.0, -500.0, -4000.0),
        Vector3::new(8000.0, 2000.0, 8000.0),
    )
}

const UNSUP_OFFSETS: [Vector3i; 9] = [
    Vector3i::new(1, 0, 0),
    Vector3i::new(-1, 0, 0),
    Vector3i::new(0, 0, 1),
    Vector3i::new(0, 0, -1),
    Vector3i::new(0, 1, 0),
    Vector3i::new(1, 1, 0),
    Vector3i::new(-1, 1, 0),
    Vector3i::new(0, 1, 1),
    Vector3i::new(0, 1, -1),
];

const CANOPY_RADIUS: i32 = 2;
const CANOPY_UP: i32 = 4;
const MAX_PENDING_UNSUPPORTED: usize = 400;

/// PhysicsServer3D::BodyMode
const BODY_MODE_STATIC: i32 = 0;
const BODY_MODE_RIGID: i32 = 2;
// PhysicsServer3D::BodyState (Godot 4.x)
const BODY_STATE_TRANSFORM: i32 = 0;
const BODY_STATE_LINEAR_VELOCITY: i32 = 1;
const BODY_STATE_ANGULAR_VELOCITY: i32 = 2;
const BODY_STATE_SLEEPING: i32 = 3;
const BODY_STATE_CAN_SLEEP: i32 = 4;
// PhysicsServer3D::BodyParameter (Godot 4.x) — NOT the same order as guesswork.
// Wrong values previously set BOUNCE=mass, MASS=0.12, INERTIA=1.0 → never-settle flicker.
const BODY_PARAM_BOUNCE: i32 = 0;
const BODY_PARAM_FRICTION: i32 = 1;
const BODY_PARAM_MASS: i32 = 2;
const BODY_PARAM_GRAVITY_SCALE: i32 = 5;
const BODY_PARAM_LINEAR_DAMP: i32 = 8;
const BODY_PARAM_ANGULAR_DAMP: i32 = 9;
/// Terrain (layer 1) + other debris (layer 4).
const DEBRIS_COLLISION_MASK: i32 = 1 | 4;
const DEBRIS_COLLISION_LAYER: i32 = 4;

/// Full-opacity hold after spawn, then a linear fade to free.
const DESPAWN_HOLD_SEC: f32 = 5.0;
const DESPAWN_FADE_SEC: f32 = 5.0;

/// Temporary cascade diagnostics (console). Turn off after verifying visuals.
const DEBUG_DEBRIS_LOG: bool = false;
const DEBUG_LOG_SPAWNS: u32 = 8;
const DEBUG_LOG_SETTLE_EVERY_N_FRAMES: u32 = 30;

#[derive(Clone)]
struct ColumnEntry {
    vox: Vector3i,
    mat: i32,
    detached: bool,
}

struct LiveBody {
    body: Rid,
    shape: Rid,
    mat_id: i32,
    mm_index: i32,
    /// Last world origin sampled for settle detection.
    last_origin: Vector3,
    /// Seconds spent nearly still — hard-freeze when this exceeds settle_still_sec.
    still_sec: f32,
    /// Seconds since spawn — force-freeze old jittering piles, then despawn fade.
    age_sec: f32,
    /// Frozen as BODY_MODE_STATIC — overlaps cannot wake it.
    settled: bool,
    /// Collision cleared while dropping through stale street collision into a crater.
    phantom_fall: bool,
    /// Collision stripped for the fade-out so invisible cubes cannot trap the walker.
    fading: bool,
    half_extent: f32,
}

struct MmBucket {
    instance: Gd<MultiMeshInstance3D>,
    multimesh: Gd<MultiMesh>,
}

struct PendingVisual {
    vox: Vector3i,
    mat: i32,
}

#[derive(GodotClass)]
#[class(base=Node)]
struct NativeCascadeDebris {
    base: Base<Node>,
    terrain: Option<Gd<Node3D>>,
    tool: Option<Gd<Object>>,
    debris_root: Option<Gd<Node3D>>,
    materials: Vec<Option<Gd<Material>>>,
    voxel_size: f32,
    channel_type: i32,
    mode_set: i32,
    air_value: i32,

    max_cubes_per_collapse: i32,
    cascade_interval_sec: f32,
    max_live_debris: i32,
    tumble_spin: f32,
    pop_impulse: f32,
    spawn_scatter: f32,
    cube_scale: f32,
    max_removals_per_tick: i32,
    spread_chance: f32,
    fizzle_chance: f32,
    unsupported_drop_chance: f32,
    max_active_columns: i32,
    debris_evict_per_frame: i32,
    max_pending_visuals: i32,
    /// World displacement (m) per physics frame below which a cube counts as "still".
    /// Primary settle signal — solver velocity can jitter forever without real motion.
    settle_move: f32,
    /// Hold still this long, then freeze as static.
    settle_still_sec: f32,
    /// Always freeze after this age (stops overlap chatter piles).
    settle_max_age_sec: f32,

    columns: Vec<Vec<ColumnEntry>>,
    pending_unsupported: Vec<Vector3i>,
    pending_visuals: Vec<PendingVisual>,
    canopy_dropped: HashSet<(i32, i32)>,
    live: Vec<LiveBody>,
    buckets: HashMap<i32, MmBucket>,
    box_mesh: Option<Gd<BoxMesh>>,
    space: Rid,
    accum: f32,
    column_rr: usize,
    flushing: bool,
    evict_budget: i32,
    last_tick_us: i64,
    rng_state: u64,
    debug_spawn_logs_left: u32,
    debug_frame: u32,
}

#[godot_api]
impl INode for NativeCascadeDebris {
    fn init(base: Base<Node>) -> Self {
        Self {
            base,
            terrain: None,
            tool: None,
            debris_root: None,
            materials: Vec::new(),
            voxel_size: 0.5,
            channel_type: 0,
            mode_set: 0,
            air_value: 0,
            max_cubes_per_collapse: 256,
            cascade_interval_sec: 0.04,
            max_live_debris: 1500,
            tumble_spin: 9.0,
            pop_impulse: 2.4,
            spawn_scatter: 0.42,
            cube_scale: 0.9,
            max_removals_per_tick: 10,
            spread_chance: 0.1,
            fizzle_chance: 0.15,
            unsupported_drop_chance: 0.3,
            max_active_columns: 180,
            debris_evict_per_frame: 48,
            max_pending_visuals: 2500,
            settle_move: 0.045,
            settle_still_sec: 0.22,
            settle_max_age_sec: 2.4,
            columns: Vec::new(),
            pending_unsupported: Vec::new(),
            pending_visuals: Vec::new(),
            canopy_dropped: HashSet::new(),
            live: Vec::new(),
            buckets: HashMap::new(),
            box_mesh: None,
            space: Rid::Invalid,
            accum: 0.0,
            column_rr: 0,
            flushing: false,
            evict_budget: 0,
            last_tick_us: 0,
            rng_state: 0xC0FFEE_u64.wrapping_mul(0x9E3779B97F4A7C15),
            debug_spawn_logs_left: DEBUG_LOG_SPAWNS,
            debug_frame: 0,
        }
    }

    fn physics_process(&mut self, delta: f64) {
        let t0 = Time::singleton().get_ticks_usec();
        self.debug_frame = self.debug_frame.wrapping_add(1);
        self.evict_budget = self.debris_evict_per_frame.max(1);
        let dt = delta as f32;
        // Age every cube first — settle cutoff and the despawn fade both read age_sec.
        self.tick_debris_lifetime(dt);
        // Drop through stale street colliders into real voxel support, then freeze piles.
        if self.tool.is_some() && self.terrain.is_some() {
            self.pull_debris_through_phantom_floors(dt);
            self.force_settle_still_debris(dt);
        }
        self.sync_multimesh_transforms();
        self.debug_log_settle_sample();
        self.drain_pending_visuals();
        if self.tool.is_none() || self.terrain.is_none() || self.debris_root.is_none() {
            self.columns.clear();
            self.pending_unsupported.clear();
            self.push_profiler();
            return;
        }
        if self.columns.is_empty()
            && self.pending_unsupported.is_empty()
            && self.pending_visuals.is_empty()
        {
            self.push_profiler();
            self.last_tick_us = (Time::singleton().get_ticks_usec() - t0) as i64;
            return;
        }
        self.accum += dt;
        let interval = self.cascade_interval_sec.max(0.001);
        while self.accum >= interval {
            self.accum -= interval;
            if !self.columns.is_empty() {
                self.advance_cascade_tick();
            } else if !self.pending_unsupported.is_empty() {
                let budget = self.max_removals_per_tick.max(1);
                self.flush_unsupported_drops(budget);
            } else {
                break;
            }
        }
        self.drain_pending_visuals();
        self.last_tick_us = (Time::singleton().get_ticks_usec() - t0) as i64;
        self.push_profiler();
    }
}

#[godot_api]
impl NativeCascadeDebris {
    #[signal]
    fn debris_spawned(world_pos: Vector3);

    #[func]
    fn setup(
        &mut self,
        terrain: Gd<Node3D>,
        tool: Gd<Object>,
        debris_root: Gd<Node3D>,
        voxel_size: f32,
        materials: Array<Variant>,
        channel_type: i32,
        mode_set: i32,
        air_value: i32,
    ) {
        self.terrain = Some(terrain);
        self.tool = Some(tool);
        self.debris_root = Some(debris_root.clone());
        self.voxel_size = voxel_size.max(0.001);
        self.channel_type = channel_type;
        self.mode_set = mode_set;
        self.air_value = air_value;
        // Mirror the old script's _rng.randomize(): vary collapses per run.
        self.rng_state = (Time::singleton().get_ticks_usec() as u64) | 1;
        self.materials.clear();
        for i in 0..materials.len() {
            let v = materials.get(i).unwrap_or_default();
            if v.is_nil() {
                self.materials.push(None);
            } else if let Ok(mat) = v.try_to::<Gd<Material>>() {
                self.materials.push(Some(mat));
            } else {
                self.materials.push(None);
            }
        }
        let mut mesh = BoxMesh::new_gd();
        let size = self.voxel_size * self.cube_scale.clamp(0.7, 1.0);
        mesh.set_size(Vector3::splat(size));
        self.box_mesh = Some(mesh);
        if let Some(world) = debris_root.get_world_3d() {
            self.space = world.get_space();
        } else {
            godot_error!("NativeCascadeDebris.setup: debris_root has no World3D");
        }
        self.clear_queue();
    }

    #[func]
    fn set_max_live_debris(&mut self, v: i32) {
        self.max_live_debris = v.max(1);
    }

    #[func]
    fn live_count(&self) -> i32 {
        self.live.len() as i32
    }

    #[func]
    fn pending_count(&self) -> i32 {
        self.pending_visuals.len() as i32
    }

    #[func]
    fn last_tick_usec(&self) -> i64 {
        self.last_tick_us
    }

    #[func]
    fn clear_queue(&mut self) {
        self.columns.clear();
        self.pending_unsupported.clear();
        self.pending_visuals.clear();
        self.canopy_dropped.clear();
        self.accum = 0.0;
        self.column_rr = 0;
        self.flushing = false;
        self.evict_budget = 0;
    }

    #[func]
    fn clear_debris(&mut self) {
        self.clear_queue();
        while !self.live.is_empty() {
            self.free_body_at(0);
        }
        for (_, mut bucket) in self.buckets.drain() {
            bucket.instance.queue_free();
        }
    }

    #[func]
    fn clear_infection_debris(&mut self) {
        let mut i = 0;
        while i < self.live.len() {
            if materials::is_infection(self.live[i].mat_id) {
                self.free_body_at(i);
            } else {
                i += 1;
            }
        }
        self.pending_visuals
            .retain(|p| !materials::is_infection(p.mat));
    }

    #[func]
    fn collapse_column_above(&mut self, hit_vox: Vector3i) {
        if self.tool.is_none() || self.terrain.is_none() {
            return;
        }
        if !self.enqueue_column_above(hit_vox, true) {
            return;
        }
        if !self.flushing {
            self.flush_unsupported_drops(self.max_removals_per_tick.max(1));
        }
    }

    #[func]
    fn detach_voxels(&mut self, entries: Array<Variant>) {
        if entries.is_empty() || self.debris_root.is_none() {
            return;
        }
        let mut column: Vec<ColumnEntry> = Vec::new();
        let mut bark_hits: Vec<Vector3i> = Vec::new();
        for i in 0..entries.len() {
            let Some(raw) = entries.get(i) else {
                continue;
            };
            let Ok(dict) = raw.try_to::<Dictionary<Variant, Variant>>() else {
                continue;
            };
            let vox = dict
                .get("vox")
                .and_then(|v| v.try_to::<Vector3i>().ok());
            let mat = dict
                .get("mat")
                .and_then(|v| v.try_to::<i32>().ok())
                .unwrap_or(0);
            let Some(vox) = vox else {
                continue;
            };
            column.push(ColumnEntry {
                vox,
                mat,
                detached: true,
            });
            if mat == materials::BARK {
                bark_hits.push(vox);
            }
        }
        if column.is_empty() {
            return;
        }
        let first = column.remove(0);
        self.spawn_cube(first.vox, first.mat);
        self.collect_unsupported_neighbors(first.vox);
        if !column.is_empty() {
            self.append_column(column);
        }
        for bark in bark_hits {
            self.drop_canopy_for_bark(bark);
        }
        if !self.flushing {
            self.flush_unsupported_drops(self.max_removals_per_tick.max(1));
        }
    }

    #[func]
    fn detach_blast_voxels(&mut self, entries: Array<Variant>, blast_center_world: Vector3) {
        if entries.is_empty() || self.debris_root.is_none() || self.terrain.is_none() {
            return;
        }
        let terrain = self.terrain.as_ref().unwrap().clone();
        let local_center = terrain.to_local(blast_center_world);
        for i in 0..entries.len() {
            let Some(raw) = entries.get(i) else {
                continue;
            };
            let Ok(dict) = raw.try_to::<Dictionary<Variant, Variant>>() else {
                continue;
            };
            let vox = dict
                .get("vox")
                .and_then(|v| v.try_to::<Vector3i>().ok());
            let mat = dict
                .get("mat")
                .and_then(|v| v.try_to::<i32>().ok())
                .unwrap_or(0);
            let Some(vox) = vox else {
                continue;
            };
            self.spawn_cube_now(vox, mat, Some(local_center));
        }
    }
}

impl NativeCascadeDebris {

    fn rng_u32(&mut self) -> u32 {
        // xorshift64*
        self.rng_state ^= self.rng_state >> 12;
        self.rng_state ^= self.rng_state << 25;
        self.rng_state ^= self.rng_state >> 27;
        (self.rng_state.wrapping_mul(0x2545F4914F6CDD1D) >> 32) as u32
    }

    /// Uniform in [0, 1) — must span the full range, or every probability check
    /// (spread / fizzle / unsupported drop) is silently scaled and cascades go exponential.
    fn rng_f32(&mut self) -> f32 {
        (self.rng_u32() >> 8) as f32 / (1u32 << 24) as f32
    }

    fn rng_range(&mut self, a: f32, b: f32) -> f32 {
        a + (b - a) * self.rng_f32()
    }

    fn rng_i(&mut self, max_exclusive: usize) -> usize {
        if max_exclusive == 0 {
            return 0;
        }
        (self.rng_u32() as usize) % max_exclusive
    }

    fn ps() -> Gd<Object> {
        Engine::singleton()
            .get_singleton(&StringName::from("PhysicsServer3D"))
            .expect("PhysicsServer3D singleton")
    }

    fn tool_set_channel(&mut self) {
        if let Some(tool) = self.tool.as_mut() {
            tool.set("channel", &self.channel_type.to_variant());
        }
    }

    fn get_voxel(&mut self, vox: Vector3i) -> i32 {
        self.tool_set_channel();
        let Some(tool) = self.tool.as_mut() else {
            return 0;
        };
        tool.call("get_voxel", &[vox.to_variant()])
            .try_to::<i32>()
            .unwrap_or(0)
    }

    fn clear_voxel(&mut self, vox: Vector3i) {
        self.tool_set_channel();
        let mode = self.mode_set;
        let air = self.air_value;
        let Some(tool) = self.tool.as_mut() else {
            return;
        };
        tool.set("mode", &mode.to_variant());
        tool.set("value", &air.to_variant());
        tool.call("do_point", &[vox.to_variant()]);
    }

    fn append_column(&mut self, column: Vec<ColumnEntry>) {
        if (self.columns.len() as i32) >= self.max_active_columns {
            return;
        }
        self.columns.push(column);
    }

    fn enqueue_column_above(&mut self, hit_vox: Vector3i, spawn_first: bool) -> bool {
        let mut column: Vec<ColumnEntry> = Vec::new();
        let mut y = hit_vox.y + 1;
        let cap = hit_vox.y + self.max_cubes_per_collapse;
        while y <= cap {
            let v = Vector3i::new(hit_vox.x, y, hit_vox.z);
            let id = self.get_voxel(v);
            if !materials::cascades(id) {
                break;
            }
            column.push(ColumnEntry {
                vox: v,
                mat: id,
                detached: false,
            });
            y += 1;
        }
        if column.is_empty() {
            return false;
        }
        if spawn_first {
            let first = column.remove(0);
            self.release_and_spawn(first);
        }
        if column.is_empty() {
            return true;
        }
        self.append_column(column);
        true
    }

    fn advance_cascade_tick(&mut self) {
        let mut budget = self.max_removals_per_tick.max(1);
        let mut spreads: Vec<Vector3i> = Vec::new();
        let mut visits = 0;
        let visit_limit = self.columns.len();
        while budget > 0 && !self.columns.is_empty() && visits < visit_limit {
            visits += 1;
            if self.column_rr >= self.columns.len() {
                self.column_rr = 0;
            }
            if self.columns[self.column_rr].is_empty() {
                self.columns.remove(self.column_rr);
                continue;
            }
            let entry = self.columns[self.column_rr].remove(0);
            let detached = entry.detached;
            let seed = entry.vox;
            // release_and_spawn already collect_unsupported_neighbors (match old GDScript).
            // Do NOT collect again here — that doubled unsupported spread (~0.3 → ~0.51).
            self.release_and_spawn(entry);
            budget -= 1;
            if !detached {
                if self.rng_f32() < self.fizzle_chance {
                    self.columns[self.column_rr].clear();
                }
                if self.rng_f32() < self.spread_chance {
                    let neighbor = self.pick_spread_neighbor(seed);
                    if neighbor.x != i32::MIN {
                        spreads.push(neighbor);
                    }
                }
            }
            if self.columns[self.column_rr].is_empty() {
                self.columns.remove(self.column_rr);
            } else if !self.columns.is_empty() {
                self.column_rr = (self.column_rr + 1) % self.columns.len();
            }
        }
        for hit in spreads {
            if budget > 0 {
                self.enqueue_column_above(hit, true);
                budget -= 1;
            } else {
                self.enqueue_column_above(hit, false);
            }
        }
        if budget > 0 {
            self.flush_unsupported_drops(budget);
        }
    }

    fn collect_unsupported_neighbors(&mut self, cleared: Vector3i) {
        if self.tool.is_none() {
            return;
        }
        if self.pending_unsupported.len() >= MAX_PENDING_UNSUPPORTED {
            return;
        }
        for offset in UNSUP_OFFSETS {
            let n = Vector3i::new(
                cleared.x + offset.x,
                cleared.y + offset.y,
                cleared.z + offset.z,
            );
            if !materials::cascades(self.get_voxel(n)) {
                continue;
            }
            if self.has_support_below(n) {
                continue;
            }
            if self.column_xz_queued(n.x, n.z) {
                continue;
            }
            if self.rng_f32() >= self.unsupported_drop_chance {
                continue;
            }
            if self.pending_unsupported.iter().any(|p| *p == n) {
                continue;
            }
            self.pending_unsupported.push(n);
            if self.pending_unsupported.len() >= MAX_PENDING_UNSUPPORTED {
                return;
            }
        }
    }

    fn has_support_below(&mut self, vox: Vector3i) -> bool {
        let below = Vector3i::new(vox.x, vox.y - 1, vox.z);
        materials::is_solid(self.get_voxel(below))
    }

    fn flush_unsupported_drops(&mut self, budget: i32) {
        if self.flushing {
            return;
        }
        self.flushing = true;
        let mut left = budget.max(0);
        while !self.pending_unsupported.is_empty() && left > 0 {
            left -= 1;
            let n = self.pending_unsupported.remove(0);
            self.try_drop_unsupported(n);
        }
        self.flushing = false;
    }

    fn try_drop_unsupported(&mut self, n: Vector3i) {
        if self.tool.is_none() || self.debris_root.is_none() {
            return;
        }
        let id = self.get_voxel(n);
        if !materials::cascades(id) {
            return;
        }
        if self.has_support_below(n) {
            return;
        }
        if self.column_xz_queued(n.x, n.z) {
            return;
        }
        self.clear_voxel(n);
        self.spawn_cube(n, id);
        self.enqueue_column_above(n, false);
        self.collect_unsupported_neighbors(n);
    }

    fn pick_spread_neighbor(&mut self, from_vox: Vector3i) -> Vector3i {
        let dirs = [
            Vector3i::new(1, 0, 0),
            Vector3i::new(-1, 0, 0),
            Vector3i::new(0, 0, 1),
            Vector3i::new(0, 0, -1),
        ];
        let mut candidates: Vec<Vector3i> = Vec::new();
        for d in dirs {
            let nx = from_vox.x + d.x;
            let nz = from_vox.z + d.z;
            if self.column_xz_queued(nx, nz) {
                continue;
            }
            let mut found_y = i32::MIN;
            for dy in [0, 1, -1, 2, -2] {
                let fy = from_vox.y + dy;
                let probe = Vector3i::new(nx, fy, nz);
                if materials::cascades(self.get_voxel(probe)) {
                    found_y = fy;
                    break;
                }
            }
            if found_y == i32::MIN {
                continue;
            }
            candidates.push(Vector3i::new(nx, found_y - 1, nz));
        }
        if candidates.is_empty() {
            return Vector3i::new(i32::MIN, 0, 0);
        }
        let i = self.rng_i(candidates.len());
        candidates[i]
    }

    fn column_xz_queued(&self, x: i32, z: i32) -> bool {
        for col in &self.columns {
            if col.is_empty() {
                continue;
            }
            let v = col[0].vox;
            if v.x == x && v.z == z {
                return true;
            }
        }
        false
    }

    fn release_and_spawn(&mut self, entry: ColumnEntry) {
        let v = entry.vox;
        let mat_id = entry.mat;
        if entry.detached {
            self.spawn_cube(v, mat_id);
            self.collect_unsupported_neighbors(v);
            if mat_id == materials::BARK {
                self.drop_canopy_for_bark(v);
            }
            return;
        }
        let cur = self.get_voxel(v);
        if !materials::is_destructible(cur) {
            return;
        }
        self.clear_voxel(v);
        let spawn_mat = if mat_id > 0 { mat_id } else { cur };
        self.spawn_cube(v, spawn_mat);
        self.collect_unsupported_neighbors(v);
        if spawn_mat == materials::BARK || cur == materials::BARK {
            self.drop_canopy_for_bark(v);
        }
    }

    fn drop_canopy_for_bark(&mut self, bark: Vector3i) {
        if self.tool.is_none() || self.debris_root.is_none() {
            return;
        }
        let stem = (bark.x, bark.z);
        if self.canopy_dropped.contains(&stem) {
            return;
        }
        let mut top_y = bark.y;
        for y in bark.y..(bark.y + 14) {
            let id = self.get_voxel(Vector3i::new(bark.x, y, bark.z));
            if id == materials::BARK {
                top_y = y;
            } else if y > bark.y {
                break;
            }
        }
        let mut by_col: HashMap<(i32, i32), Vec<ColumnEntry>> = HashMap::new();
        let mut found_any = false;
        for dz in -CANOPY_RADIUS..=CANOPY_RADIUS {
            for dx in -CANOPY_RADIUS..=CANOPY_RADIUS {
                if dx.abs() == CANOPY_RADIUS && dz.abs() == CANOPY_RADIUS {
                    continue;
                }
                for y in (top_y - 1)..=(top_y + CANOPY_UP) {
                    let v = Vector3i::new(bark.x + dx, y, bark.z + dz);
                    if self.get_voxel(v) != materials::LEAVES {
                        continue;
                    }
                    self.clear_voxel(v);
                    by_col.entry((v.x, v.z)).or_default().push(ColumnEntry {
                        vox: v,
                        mat: materials::LEAVES,
                        detached: true,
                    });
                    found_any = true;
                }
            }
        }
        if !found_any {
            return;
        }
        self.canopy_dropped.insert(stem);
        for (_key, mut col) in by_col {
            col.sort_by_key(|e| e.vox.y);
            let first = col.remove(0);
            self.spawn_cube(first.vox, materials::LEAVES);
            self.collect_unsupported_neighbors(first.vox);
            if !col.is_empty() {
                self.append_column(col);
            }
        }
    }

    fn make_room_for_spawn(&mut self) -> bool {
        if (self.live.len() as i32) < self.max_live_debris {
            return true;
        }
        if self.evict_budget <= 0 {
            return false;
        }
        if self.free_oldest_sleeping() || self.free_oldest() {
            self.evict_budget -= 1;
        }
        (self.live.len() as i32) < self.max_live_debris
    }

    fn body_sleeping(&self, body: Rid) -> bool {
        let mut ps = Self::ps();
        ps.call(
            "body_get_state",
            &[body.to_variant(), BODY_STATE_SLEEPING.to_variant()],
        )
        .try_to::<bool>()
        .unwrap_or(false)
    }

    fn free_oldest_sleeping(&mut self) -> bool {
        for i in 0..self.live.len() {
            if self.live[i].settled || self.body_sleeping(self.live[i].body) {
                return self.free_body_at(i);
            }
        }
        false
    }

    fn free_oldest(&mut self) -> bool {
        if self.live.is_empty() {
            return false;
        }
        self.free_body_at(0)
    }

    fn free_body_at(&mut self, index: usize) -> bool {
        if index >= self.live.len() {
            return false;
        }
        let mat_id = self.live[index].mat_id;
        let mm_index = self.live[index].mm_index;
        let body = self.live[index].body;
        let shape = self.live[index].shape;
        self.remove_from_multimesh(mat_id, mm_index);
        self.live.remove(index);
        let mut ps = Self::ps();
        ps.call(
            "body_set_space",
            &[body.to_variant(), Rid::Invalid.to_variant()],
        );
        ps.call("free_rid", &[body.to_variant()]);
        ps.call("free_rid", &[shape.to_variant()]);
        true
    }

    fn drain_pending_visuals(&mut self) {
        while !self.pending_visuals.is_empty() {
            if !self.make_room_for_spawn() {
                return;
            }
            let entry = self.pending_visuals.remove(0);
            self.spawn_cube_now(entry.vox, entry.mat, None);
        }
    }

    fn spawn_cube(&mut self, vox: Vector3i, mat_id: i32) {
        if self.debris_root.is_none() || self.terrain.is_none() {
            return;
        }
        if !self.make_room_for_spawn() {
            if (self.pending_visuals.len() as i32) < self.max_pending_visuals {
                self.pending_visuals.push(PendingVisual { vox, mat: mat_id });
            }
            return;
        }
        self.spawn_cube_now(vox, mat_id, None);
    }

    fn spawn_cube_now(
        &mut self,
        vox: Vector3i,
        mat_id: i32,
        blast: Option<Vector3>,
    ) {
        if self.terrain.is_none() {
            return;
        }
        if self.space == Rid::Invalid {
            godot_error!("NativeCascadeDebris: physics space invalid");
            return;
        }
        let local_center = Vector3::new(
            vox.x as f32 + 0.5,
            vox.y as f32 + 0.5,
            vox.z as f32 + 0.5,
        );
        let mut world_center = {
            let terrain = self.terrain.as_ref().unwrap();
            terrain.to_global(local_center)
        };
        let scatter_m = self.voxel_size * self.spawn_scatter;
        let yaw = self.rng_range(0.0, std::f32::consts::TAU);
        let radial = self.rng_range(scatter_m * 0.35, scatter_m);
        world_center += Vector3::new(
            yaw.cos() * radial,
            self.rng_range(0.0, self.voxel_size * 0.08),
            yaw.sin() * radial,
        );
        // Full edge length — matches old BoxMesh / BoxShape3D.size.
        let size = self.voxel_size * self.cube_scale.clamp(0.7, 1.0);
        let mass = (size * size * size * 900.0).clamp(0.35, 12.0);
        // PhysicsServer3D box shape_set_data wants half-extents, not full size.
        // Passing full size made colliders 2× too large → perpetual overlap / flicker.
        let half_extents = Vector3::splat(size * 0.5);

        let mut ps = Self::ps();
        let body = ps
            .call("body_create", &[])
            .try_to::<Rid>()
            .unwrap_or(Rid::Invalid);
        let shape = ps
            .call("box_shape_create", &[])
            .try_to::<Rid>()
            .unwrap_or(Rid::Invalid);
        if body == Rid::Invalid || shape == Rid::Invalid {
            godot_error!("NativeCascadeDebris: failed to create body/shape");
            return;
        }
        ps.call(
            "shape_set_data",
            &[shape.to_variant(), half_extents.to_variant()],
        );
        ps.call(
            "body_set_mode",
            &[body.to_variant(), BODY_MODE_RIGID.to_variant()],
        );
        ps.call(
            "body_add_shape",
            &[
                body.to_variant(),
                shape.to_variant(),
                Transform3D::IDENTITY.to_variant(),
                false.to_variant(),
            ],
        );
        ps.call(
            "body_set_collision_layer",
            &[body.to_variant(), DEBRIS_COLLISION_LAYER.to_variant()],
        );
        ps.call(
            "body_set_collision_mask",
            &[body.to_variant(), DEBRIS_COLLISION_MASK.to_variant()],
        );
        ps.call(
            "body_set_enable_continuous_collision_detection",
            &[body.to_variant(), true.to_variant()],
        );
        // Match old RigidBody3D: mass from volume, then rebuild inertia from shapes.
        ps.call(
            "body_set_param",
            &[
                body.to_variant(),
                BODY_PARAM_BOUNCE.to_variant(),
                0.04f32.to_variant(),
            ],
        );
        ps.call(
            "body_set_param",
            &[
                body.to_variant(),
                BODY_PARAM_FRICTION.to_variant(),
                0.85f32.to_variant(),
            ],
        );
        ps.call(
            "body_set_param",
            &[
                body.to_variant(),
                BODY_PARAM_MASS.to_variant(),
                mass.to_variant(),
            ],
        );
        ps.call(
            "body_set_param",
            &[
                body.to_variant(),
                BODY_PARAM_GRAVITY_SCALE.to_variant(),
                1.0f32.to_variant(),
            ],
        );
        // Keep flight lively — high damp stalls cubes mid-air.
        ps.call(
            "body_set_param",
            &[
                body.to_variant(),
                BODY_PARAM_LINEAR_DAMP.to_variant(),
                0.25f32.to_variant(),
            ],
        );
        ps.call(
            "body_set_param",
            &[
                body.to_variant(),
                BODY_PARAM_ANGULAR_DAMP.to_variant(),
                1.2f32.to_variant(),
            ],
        );
        ps.call("body_reset_mass_properties", &[body.to_variant()]);
        ps.call(
            "body_set_state",
            &[
                body.to_variant(),
                BODY_STATE_CAN_SLEEP.to_variant(),
                true.to_variant(),
            ],
        );
        ps.call(
            "body_set_space",
            &[body.to_variant(), self.space.to_variant()],
        );

        if DEBUG_DEBRIS_LOG && self.debug_spawn_logs_left > 0 {
            self.debug_spawn_logs_left -= 1;
            let rbounce = ps
                .call(
                    "body_get_param",
                    &[body.to_variant(), BODY_PARAM_BOUNCE.to_variant()],
                )
                .try_to::<f32>()
                .unwrap_or(-1.0);
            let rfriction = ps
                .call(
                    "body_get_param",
                    &[body.to_variant(), BODY_PARAM_FRICTION.to_variant()],
                )
                .try_to::<f32>()
                .unwrap_or(-1.0);
            let rmass = ps
                .call(
                    "body_get_param",
                    &[body.to_variant(), BODY_PARAM_MASS.to_variant()],
                )
                .try_to::<f32>()
                .unwrap_or(-1.0);
            let rgrav = ps
                .call(
                    "body_get_param",
                    &[body.to_variant(), BODY_PARAM_GRAVITY_SCALE.to_variant()],
                )
                .try_to::<f32>()
                .unwrap_or(-1.0);
            let shape_data = ps
                .call("shape_get_data", &[shape.to_variant()])
                .try_to::<Vector3>()
                .unwrap_or(Vector3::ZERO);
            godot::global::godot_print!(
                "CascadeDebris spawn: full={:.3} half=({:.3},{:.3},{:.3}) mass={:.3} bounce={:.3} friction={:.3} grav={:.3} shape_half=({:.3},{:.3},{:.3})",
                size,
                half_extents.x,
                half_extents.y,
                half_extents.z,
                rmass,
                rbounce,
                rfriction,
                rgrav,
                shape_data.x,
                shape_data.y,
                shape_data.z
            );
        }

        let basis_euler = Vector3::new(
            self.rng_range(-0.85, 0.85),
            self.rng_range(0.0, std::f32::consts::TAU),
            self.rng_range(-0.85, 0.85),
        );
        let xf = Transform3D {
            basis: Basis::from_euler(EulerOrder::YXZ, basis_euler),
            origin: world_center,
        };
        ps.call(
            "body_set_state",
            &[
                body.to_variant(),
                BODY_STATE_TRANSFORM.to_variant(),
                xf.to_variant(),
            ],
        );

        let (lin, ang) = if let Some(blast) = blast {
            let mut away = local_center - blast;
            if away.length_squared() < 0.0001 {
                away = Vector3::new(
                    self.rng_range(-1.0, 1.0),
                    0.55,
                    self.rng_range(-1.0, 1.0),
                );
            }
            let dir = away.normalized();
            let burst = self.pop_impulse * self.rng_range(1.1, 2.0);
            let lin = dir * burst
                + Vector3::UP * (self.pop_impulse * self.rng_range(0.45, 1.1));
            let ang = Vector3::new(
                self.rng_range(-self.tumble_spin, self.tumble_spin),
                self.rng_range(-self.tumble_spin, self.tumble_spin),
                self.rng_range(-self.tumble_spin, self.tumble_spin),
            );
            (lin, ang)
        } else {
            let outward = Vector3::new(yaw.cos(), 0.0, yaw.sin());
            let burst = self.pop_impulse * self.rng_range(0.65, 1.25);
            let lin = outward * burst
                + Vector3::new(
                    self.rng_range(-self.pop_impulse * 0.35, self.pop_impulse * 0.35),
                    self.rng_range(0.35, self.pop_impulse * 0.85),
                    self.rng_range(-self.pop_impulse * 0.35, self.pop_impulse * 0.35),
                );
            let ang = Vector3::new(
                self.rng_range(-self.tumble_spin, self.tumble_spin),
                self.rng_range(-self.tumble_spin, self.tumble_spin),
                self.rng_range(-self.tumble_spin, self.tumble_spin),
            );
            (lin, ang)
        };
        ps.call(
            "body_set_state",
            &[
                body.to_variant(),
                BODY_STATE_LINEAR_VELOCITY.to_variant(),
                lin.to_variant(),
            ],
        );
        ps.call(
            "body_set_state",
            &[
                body.to_variant(),
                BODY_STATE_ANGULAR_VELOCITY.to_variant(),
                ang.to_variant(),
            ],
        );

        let local_xf = self.world_to_debris_local(xf);
        let mm_index = self.add_to_multimesh(mat_id, local_xf);
        self.live.push(LiveBody {
            body,
            shape,
            mat_id,
            mm_index,
            last_origin: world_center,
            still_sec: 0.0,
            age_sec: 0.0,
            settled: false,
            phantom_fall: false,
            fading: false,
            half_extent: half_extents.x,
        });
        self.base_mut()
            .emit_signal("debris_spawned", &[world_center.to_variant()]);
    }

    /// World Y of the top face of the highest solid voxel under `world` (terrain-local scan).
    fn voxel_support_top_y(&mut self, world: Vector3) -> Option<f32> {
        let local = {
            let terrain = self.terrain.as_ref()?;
            terrain.to_local(world)
        };
        let vx = local.x.floor() as i32;
        let vz = local.z.floor() as i32;
        let mut top_local_y: Option<f32> = None;
        for y in (0..=64).rev() {
            let id = self.get_voxel(Vector3i::new(vx, y, vz));
            if materials::is_solid(id) {
                // Terrain is scaled by voxel_size; local units are voxel indices.
                top_local_y = Some((y + 1) as f32);
                break;
            }
        }
        let top = top_local_y?;
        let top_local = Vector3::new(local.x, top, local.z);
        let terrain = self.terrain.as_ref()?;
        Some(terrain.to_global(top_local).y)
    }

    /// Street collision remesh lags carve — cubes rest on the old deck above air.
    /// Temporarily clear collisions and drop them onto real voxel support.
    fn pull_debris_through_phantom_floors(&mut self, delta: f32) {
        if self.live.is_empty() || self.space == Rid::Invalid {
            return;
        }
        let _dt = delta.max(0.0);
        let mut ps = Self::ps();
        struct Snap {
            index: usize,
            body: Rid,
            origin: Vector3,
            basis: Basis,
            vel: Vector3,
            half: f32,
            phantom_fall: bool,
        }
        let mut snaps: Vec<Snap> = Vec::with_capacity(self.live.len());
        for (index, live) in self.live.iter_mut().enumerate() {
            if live.settled {
                continue;
            }
            let Ok(xf) = ps
                .call(
                    "body_get_state",
                    &[
                        live.body.to_variant(),
                        BODY_STATE_TRANSFORM.to_variant(),
                    ],
                )
                .try_to::<Transform3D>()
            else {
                continue;
            };
            let vel = ps
                .call(
                    "body_get_state",
                    &[
                        live.body.to_variant(),
                        BODY_STATE_LINEAR_VELOCITY.to_variant(),
                    ],
                )
                .try_to::<Vector3>()
                .unwrap_or(Vector3::ZERO);
            snaps.push(Snap {
                index,
                body: live.body,
                origin: xf.origin,
                basis: xf.basis,
                vel,
                half: live.half_extent,
                phantom_fall: live.phantom_fall,
            });
        }

        let mut supports: Vec<(usize, f32)> = Vec::with_capacity(snaps.len());
        for snap in &snaps {
            if let Some(y) = self.voxel_support_top_y(snap.origin) {
                supports.push((snap.index, y));
            }
        }
        let support_by_index: HashMap<usize, f32> = supports.into_iter().collect();

        for snap in snaps {
            let Some(&support_y) = support_by_index.get(&snap.index) else {
                continue;
            };
            let rest_y = support_y + snap.half;
            let gap = snap.origin.y - rest_y;
            let live = &mut self.live[snap.index];

            if snap.phantom_fall {
                if gap <= 0.08 {
                    let xf = Transform3D {
                        basis: snap.basis,
                        origin: Vector3::new(snap.origin.x, rest_y, snap.origin.z),
                    };
                    ps.call(
                        "body_set_state",
                        &[
                            snap.body.to_variant(),
                            BODY_STATE_TRANSFORM.to_variant(),
                            xf.to_variant(),
                        ],
                    );
                    ps.call(
                        "body_set_state",
                        &[
                            snap.body.to_variant(),
                            BODY_STATE_LINEAR_VELOCITY.to_variant(),
                            Vector3::ZERO.to_variant(),
                        ],
                    );
                    ps.call(
                        "body_set_state",
                        &[
                            snap.body.to_variant(),
                            BODY_STATE_ANGULAR_VELOCITY.to_variant(),
                            Vector3::ZERO.to_variant(),
                        ],
                    );
                    if !live.fading {
                        ps.call(
                            "body_set_collision_mask",
                            &[
                                snap.body.to_variant(),
                                DEBRIS_COLLISION_MASK.to_variant(),
                            ],
                        );
                    }
                    live.phantom_fall = false;
                    live.last_origin = xf.origin;
                } else {
                    let mut dive = snap.vel;
                    dive.y = dive.y.min(-10.0);
                    ps.call(
                        "body_set_state",
                        &[
                            snap.body.to_variant(),
                            BODY_STATE_LINEAR_VELOCITY.to_variant(),
                            dive.to_variant(),
                        ],
                    );
                }
                continue;
            }

            // Stuck on phantom floor: large voxel gap, barely moving vertically.
            if gap > 0.28 && snap.vel.y > -1.25 && snap.vel.y < 1.0 {
                live.phantom_fall = true;
                ps.call(
                    "body_set_collision_mask",
                    &[snap.body.to_variant(), 0i32.to_variant()],
                );
                let mut dive = snap.vel;
                dive.y = -12.0;
                ps.call(
                    "body_set_state",
                    &[
                        snap.body.to_variant(),
                        BODY_STATE_LINEAR_VELOCITY.to_variant(),
                        dive.to_variant(),
                    ],
                );
            }
        }
    }

    /// Freeze barely-moving / aged cubes as STATIC so overlap chatter cannot wake them.
    fn force_settle_still_debris(&mut self, delta: f32) {
        if self.live.is_empty() || self.space == Rid::Invalid {
            return;
        }
        let move_lim = self.settle_move.max(0.001);
        let need = self.settle_still_sec.max(0.05);
        let max_age = self.settle_max_age_sec.max(0.5);
        let dt = delta.max(0.0);
        let mut ps = Self::ps();
        for live in self.live.iter_mut() {
            if live.settled || live.phantom_fall {
                continue;
            }
            let xf = ps
                .call(
                    "body_get_state",
                    &[
                        live.body.to_variant(),
                        BODY_STATE_TRANSFORM.to_variant(),
                    ],
                )
                .try_to::<Transform3D>();
            let Ok(xf) = xf else {
                continue;
            };
            let origin = xf.origin;
            let moved = (origin - live.last_origin).length();
            live.last_origin = origin;
            if moved < move_lim {
                live.still_sec += dt;
            } else {
                live.still_sec = 0.0;
            }
            // Age cutoff always wins — overlapping piles can chatter forever otherwise.
            let age_force = live.age_sec >= max_age;
            let still_force = live.still_sec >= need;
            if !still_force && !age_force {
                continue;
            }
            Self::freeze_body_static(&mut ps, live, xf);
        }
    }

    fn freeze_body_static(ps: &mut Gd<Object>, live: &mut LiveBody, xf: Transform3D) {
        live.still_sec = 0.0;
        live.settled = true;
        live.phantom_fall = false;
        live.last_origin = xf.origin;
        ps.call(
            "body_set_state",
            &[
                live.body.to_variant(),
                BODY_STATE_LINEAR_VELOCITY.to_variant(),
                Vector3::ZERO.to_variant(),
            ],
        );
        ps.call(
            "body_set_state",
            &[
                live.body.to_variant(),
                BODY_STATE_ANGULAR_VELOCITY.to_variant(),
                Vector3::ZERO.to_variant(),
            ],
        );
        ps.call(
            "body_set_state",
            &[
                live.body.to_variant(),
                BODY_STATE_TRANSFORM.to_variant(),
                xf.to_variant(),
            ],
        );
        ps.call(
            "body_set_mode",
            &[live.body.to_variant(), BODY_MODE_STATIC.to_variant()],
        );
        // Fading cubes stay non-colliding so a late freeze cannot re-solidify a ghost.
        let mask = if live.fading {
            0
        } else {
            DEBRIS_COLLISION_MASK
        };
        let layer = if live.fading { 0 } else { DEBRIS_COLLISION_LAYER };
        ps.call(
            "body_set_collision_layer",
            &[live.body.to_variant(), layer.to_variant()],
        );
        ps.call(
            "body_set_collision_mask",
            &[live.body.to_variant(), mask.to_variant()],
        );
    }

    fn ensure_bucket(&mut self, mat_id: i32) -> &mut MmBucket {
        if !self.buckets.contains_key(&mat_id) {
            let pool = self.max_live_debris.max(1);
            let mut mm = MultiMesh::new_gd();
            mm.set_transform_format(TransformFormat::TRANSFORM_3D);
            mm.set_use_colors(true);
            // Preallocate once — resizing instance_count every spawn/despawn flickers the buffer.
            mm.set_instance_count(pool);
            mm.set_visible_instance_count(0);
            mm.set_custom_aabb(debris_cull_aabb());
            if let Some(mesh) = &self.box_mesh {
                mm.set_mesh(mesh);
            }
            let mut inst = MultiMeshInstance3D::new_alloc();
            inst.set_multimesh(&mm);
            inst.set_cast_shadows_setting(ShadowCastingSetting::OFF);
            inst.set_physics_interpolation_mode(PhysicsInterpolationMode::OFF);
            if let Some(Some(mat)) = self.materials.get(mat_id as usize) {
                inst.set_material_override(mat);
            }
            if let Some(root) = self.debris_root.as_mut() {
                root.add_child(&inst);
            }
            self.buckets.insert(
                mat_id,
                MmBucket {
                    instance: inst,
                    multimesh: mm,
                },
            );
        }
        self.buckets.get_mut(&mat_id).unwrap()
    }

    fn add_to_multimesh(&mut self, mat_id: i32, xf: Transform3D) -> i32 {
        let bucket = self.ensure_bucket(mat_id);
        let vis = bucket.multimesh.get_visible_instance_count();
        let cap = bucket.multimesh.get_instance_count();
        if vis >= cap {
            // Should be rare (live cap enforced); grow without shrinking later.
            bucket.multimesh.set_instance_count(vis + 64);
            bucket.multimesh.set_custom_aabb(debris_cull_aabb());
        }
        bucket.multimesh.set_instance_transform(vis, xf);
        bucket
            .multimesh
            .set_instance_color(vis, Color::from_rgba(1.0, 1.0, 1.0, 1.0));
        bucket.multimesh.reset_instance_physics_interpolation(vis);
        bucket.multimesh.set_visible_instance_count(vis + 1);
        vis
    }

    fn remove_from_multimesh(&mut self, mat_id: i32, mm_index: i32) {
        let Some(bucket) = self.buckets.get_mut(&mat_id) else {
            return;
        };
        let vis = bucket.multimesh.get_visible_instance_count();
        if vis <= 0 || mm_index < 0 || mm_index >= vis {
            return;
        }
        let last = vis - 1;
        if mm_index != last {
            let xf = bucket.multimesh.get_instance_transform(last);
            let col = bucket.multimesh.get_instance_color(last);
            bucket.multimesh.set_instance_transform(mm_index, xf);
            bucket.multimesh.set_instance_color(mm_index, col);
            bucket.multimesh.reset_instance_physics_interpolation(mm_index);
            // Update the live body that held `last`.
            for live in self.live.iter_mut() {
                if live.mat_id == mat_id && live.mm_index == last {
                    live.mm_index = mm_index;
                    break;
                }
            }
        }
        // Hide trailing slot — do not reallocate the buffer.
        bucket.multimesh.set_visible_instance_count(last);
    }

    fn world_to_debris_local(&self, world_xf: Transform3D) -> Transform3D {
        let Some(root) = self.debris_root.as_ref() else {
            return world_xf;
        };
        let inv = root.get_global_transform().affine_inverse();
        inv * world_xf
    }

    fn despawn_alpha(age_sec: f32) -> f32 {
        if age_sec <= DESPAWN_HOLD_SEC {
            return 1.0;
        }
        let fade_t = (age_sec - DESPAWN_HOLD_SEC) / DESPAWN_FADE_SEC.max(0.001);
        (1.0 - fade_t).clamp(0.0, 1.0)
    }

    /// Infection / meteor / Game Boy share opaque terrain shaders, so they cannot
    /// read MultiMesh COLOR.a. Shrink those visuals during the fade instead.
    fn fades_by_scale(mat_id: i32) -> bool {
        materials::is_infection(mat_id)
            || mat_id == materials::METEOR_ROCK
            || mat_id == materials::GAMEBOY
    }

    fn tick_debris_lifetime(&mut self, dt: f32) {
        if self.live.is_empty() {
            return;
        }
        let dt = dt.max(0.0);
        let mut kill: Vec<usize> = Vec::new();
        let mut strip: Vec<usize> = Vec::new();
        for (i, live) in self.live.iter_mut().enumerate() {
            live.age_sec += dt;
            let alpha = Self::despawn_alpha(live.age_sec);
            if alpha <= 0.0 {
                kill.push(i);
                continue;
            }
            if alpha < 1.0 && !live.fading {
                live.fading = true;
                strip.push(i);
            }
        }
        // Strip collision before the cube goes translucent so the walker cannot stick.
        if !strip.is_empty() {
            let mut ps = Self::ps();
            for i in strip {
                let body = self.live[i].body;
                ps.call(
                    "body_set_collision_layer",
                    &[body.to_variant(), 0i32.to_variant()],
                );
                ps.call(
                    "body_set_collision_mask",
                    &[body.to_variant(), 0i32.to_variant()],
                );
            }
        }
        // Free highest indices first so removals do not invalidate earlier ones.
        kill.sort_unstable_by(|a, b| b.cmp(a));
        for i in kill {
            self.free_body_at(i);
        }
    }

    fn sync_multimesh_transforms(&mut self) {
        let mut ps = Self::ps();
        // Collect transforms then apply — avoid borrow issues across buckets.
        let mut updates: Vec<(i32, i32, Transform3D, Color)> =
            Vec::with_capacity(self.live.len());
        for live in &self.live {
            let Ok(world_xf) = ps
                .call(
                    "body_get_state",
                    &[
                        live.body.to_variant(),
                        BODY_STATE_TRANSFORM.to_variant(),
                    ],
                )
                .try_to::<Transform3D>()
            else {
                // Never write IDENTITY — that teleports every cube to the origin (looks like
                // the whole debris field flickering in/out).
                continue;
            };
            let alpha = Self::despawn_alpha(live.age_sec);
            let mut local_xf = self.world_to_debris_local(world_xf);
            if Self::fades_by_scale(live.mat_id) {
                let s = alpha.max(0.001);
                local_xf.basis = local_xf.basis * Basis::from_scale(Vector3::splat(s));
            }
            let color = Color::from_rgba(1.0, 1.0, 1.0, alpha);
            updates.push((live.mat_id, live.mm_index, local_xf, color));
        }
        for (mat_id, mm_index, xf, color) in updates {
            if let Some(bucket) = self.buckets.get_mut(&mat_id) {
                let vis = bucket.multimesh.get_visible_instance_count();
                if mm_index >= 0 && mm_index < vis {
                    bucket.multimesh.set_instance_transform(mm_index, xf);
                    bucket.multimesh.set_instance_color(mm_index, color);
                }
            }
        }
    }

    fn debug_log_settle_sample(&self) {
        if !DEBUG_DEBRIS_LOG || self.live.is_empty() {
            return;
        }
        if self.debug_frame % DEBUG_LOG_SETTLE_EVERY_N_FRAMES != 0 {
            return;
        }
        let mut ps = Self::ps();
        let mut sleeping = 0u32;
        let mut awake = 0u32;
        let mut max_speed = 0.0f32;
        let sample_n = self.live.len().min(6);
        let mut sample = String::new();
        for (i, live) in self.live.iter().enumerate() {
            let asleep = ps
                .call(
                    "body_get_state",
                    &[
                        live.body.to_variant(),
                        BODY_STATE_SLEEPING.to_variant(),
                    ],
                )
                .try_to::<bool>()
                .unwrap_or(false);
            let vel = ps
                .call(
                    "body_get_state",
                    &[
                        live.body.to_variant(),
                        BODY_STATE_LINEAR_VELOCITY.to_variant(),
                    ],
                )
                .try_to::<Vector3>()
                .unwrap_or(Vector3::ZERO);
            let speed = vel.length();
            if asleep {
                sleeping += 1;
            } else {
                awake += 1;
            }
            if speed > max_speed {
                max_speed = speed;
            }
            if i < sample_n {
                sample.push_str(&format!(
                    " [{}] sleep={} v={:.2}",
                    i, asleep, speed
                ));
            }
        }
        godot::global::godot_print!(
            "CascadeDebris settle: live={} sleep={} awake={} max_v={:.2}{}",
            self.live.len(),
            sleeping,
            awake,
            max_speed,
            sample
        );
    }

    fn push_profiler(&self) {
        let tree = self.base().get_tree();
        let Some(root) = tree.get_root() else {
            return;
        };
        let Some(mut profiler) = root.get_node_or_null("CityProfiler") else {
            return;
        };
        profiler.call(
            "set_counter",
            &[
                "debris_live".to_variant(),
                (self.live.len() as i32).to_variant(),
            ],
        );
        profiler.call(
            "set_counter",
            &[
                "debris_pending".to_variant(),
                (self.pending_visuals.len() as i32).to_variant(),
            ],
        );
        profiler.call(
            "scope_us",
            &["cascade".to_variant(), self.last_tick_us.to_variant()],
        );
    }
}
