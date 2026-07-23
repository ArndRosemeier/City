## After a chisel, drop the vertical fabric column above as tumbling RigidBody cubes.
## Spawns bottom→top so the breakdown cascades. Cubes stay marked for later cleanup.
## When max_live_debris is reached, oldest cubes are freed to make room.
## Every active column advances one cube per interval — collapse speed stays constant
## no matter how many columns are falling at once.
## Per tick a column may spread (10%) to a neighbor or fizzle (5%) and stop early.
## Destroying a brick also checks nearby fabric with no support below (30% drop).
class_name VoxelCascadeDebris
extends Node

@export var max_cubes_per_collapse: int = 256
@export var cascade_interval_sec: float = 0.04
@export var max_live_debris: int = 1000
@export var tumble_spin: float = 9.0
@export var pop_impulse: float = 2.4
## Horizontal spawn jitter as a fraction of voxel size (breaks neat columns).
@export var spawn_scatter: float = 0.42
## Collision/mesh scale vs voxel size — slightly under-size so cubes slip apart.
@export var cube_scale: float = 0.9
## Per column-tick: chance to start an adjacent column collapsing.
@export var spread_chance: float = 0.1
## Per column-tick: chance to abort the rest of this column.
@export var fizzle_chance: float = 0.05
## After a brick falls: chance an unsupported neighbor also drops.
@export var unsupported_drop_chance: float = 0.3
## Max unsupported drops resolved in one flush (prevents one-frame wipe / stack blowups).
@export var unsupported_flush_budget: int = 32
## Cap queued columns so chain reactions can't runaway.
@export var max_active_columns: int = 180

## Fabric cells around a cleared brick to check for missing vertical support.
const _UNSUP_OFFSETS: Array[Vector3i] = [
	Vector3i(1, 0, 0),
	Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1),
	Vector3i(0, 1, 0),
	Vector3i(1, 1, 0),
	Vector3i(-1, 1, 0),
	Vector3i(0, 1, 1),
	Vector3i(0, 1, -1),
]

var _terrain: VoxelTerrain
var _tool: VoxelTool
var _debris_root: Node3D
var _voxel_size: float = 0.5
## Active collapses; each entry is Array of {vox: Vector3i, mat: int} bottom→top.
var _columns: Array = []
var _accum: float = 0.0
## Fabric voxels waiting to drop because their support is gone.
var _pending_unsupported: Array[Vector3i] = []
## Re-entrancy guard — nested flush was blowing the stack and killing cascades.
var _flushing: bool = false
## Oldest → newest. Used for FIFO eviction at the live cap.
var _live_bodies: Array = []
var _phys_mat: PhysicsMaterial
var _rng := RandomNumberGenerator.new()


func setup(terrain: VoxelTerrain, tool: VoxelTool, debris_root: Node3D, voxel_size: float) -> void:
	_terrain = terrain
	_tool = tool
	_debris_root = debris_root
	_voxel_size = maxf(voxel_size, 0.001)
	_phys_mat = PhysicsMaterial.new()
	_phys_mat.friction = 0.55
	_phys_mat.bounce = 0.12
	_rng.randomize()
	clear_queue()


func clear_queue() -> void:
	_columns.clear()
	_pending_unsupported.clear()
	_accum = 0.0
	_flushing = false


func clear_debris() -> void:
	clear_queue()
	if _debris_root == null:
		return
	for c in _debris_root.get_children():
		c.queue_free()
	_live_bodies.clear()


func collapse_column_above(hit_vox: Vector3i) -> void:
	if _tool == null or _terrain == null:
		return
	if not _enqueue_column_above(hit_vox, true):
		return
	if not _flushing:
		_flush_unsupported_drops()


## World voxels already cleared (melee sphere). Spawn tumbling cubes without re-carving.
func detach_voxels(entries: Array) -> void:
	if entries.is_empty() or _debris_root == null:
		return
	var column: Array = []
	for raw in entries:
		var e: Dictionary = raw
		column.append({
			"vox": e["vox"],
			"mat": int(e["mat"]),
			"detached": true,
		})
	var first: Dictionary = column.pop_front()
	_spawn_cube(first["vox"] as Vector3i, int(first["mat"]))
	_collect_unsupported_neighbors(first["vox"] as Vector3i)
	if not column.is_empty():
		_append_column(column)
	if not _flushing:
		_flush_unsupported_drops()


func _enqueue_column_above(hit_vox: Vector3i, spawn_first: bool) -> bool:
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var column: Array = []
	var y := hit_vox.y + 1
	var cap := hit_vox.y + max_cubes_per_collapse
	while y <= cap:
		var v := Vector3i(hit_vox.x, y, hit_vox.z)
		var id := int(_tool.get_voxel(v))
		if not VoxelMaterial.is_building_fabric(id):
			break
		column.append({"vox": v, "mat": id, "detached": false})
		y += 1
	if column.is_empty():
		return false
	if spawn_first:
		var first: Dictionary = column.pop_front()
		_release_and_spawn(first)
	if column.is_empty():
		return true
	_append_column(column)
	return true


func _append_column(column: Array) -> void:
	if _columns.size() >= max_active_columns:
		return
	_columns.append(column)


func _physics_process(delta: float) -> void:
	if _tool == null or _terrain == null or _debris_root == null:
		_columns.clear()
		_pending_unsupported.clear()
		return
	if _columns.is_empty() and _pending_unsupported.is_empty():
		return
	_accum += delta
	while _accum >= cascade_interval_sec and not _columns.is_empty():
		_accum -= cascade_interval_sec
		_spawn_one_from_each_column()
	## Keep draining unsupported chains even when no columns remain.
	if not _pending_unsupported.is_empty() and not _flushing:
		_flush_unsupported_drops()


func _spawn_one_from_each_column() -> void:
	## Parallel advance: every column drops one brick this tick so N columns
	## don't make each column N× slower.
	var spreads: Array[Vector3i] = []
	var i := 0
	while i < _columns.size():
		var col: Array = _columns[i]
		if col.is_empty():
			_columns.remove_at(i)
			continue
		var entry: Dictionary = col.pop_front()
		var detached := bool(entry.get("detached", false))
		_release_and_spawn(entry)
		## Structural columns only — punch-spray debris doesn't fizzle/spread.
		if not detached:
			if _rng.randf() < fizzle_chance:
				col.clear()
			if _rng.randf() < spread_chance:
				var seed_vox: Vector3i = entry["vox"]
				var neighbor := _pick_spread_neighbor(seed_vox)
				if neighbor.x != -2147483648:
					spreads.append(neighbor)
		if col.is_empty():
			_columns.remove_at(i)
		else:
			i += 1
	## Apply spreads after the tick so new columns don't steal this frame's slots.
	for hit in spreads:
		## Enqueue only — flush once below (avoids nested flush recursion).
		_enqueue_column_above(hit, true)
	_flush_unsupported_drops()


func _collect_unsupported_neighbors(cleared: Vector3i) -> void:
	## Any fabric around the hole that has nothing solid under it may fall.
	if _tool == null:
		return
	if _pending_unsupported.size() >= 400:
		return
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	for offset in _UNSUP_OFFSETS:
		var n: Vector3i = cleared + offset
		if not VoxelMaterial.is_building_fabric(int(_tool.get_voxel(n))):
			continue
		if _has_support_below(n):
			continue
		if _column_xz_queued(n.x, n.z):
			continue
		if _rng.randf() >= unsupported_drop_chance:
			continue
		## De-dupe pending list.
		var already := false
		for p in _pending_unsupported:
			if p == n:
				already = true
				break
		if already:
			continue
		_pending_unsupported.append(n)
		if _pending_unsupported.size() >= 400:
			return


func _has_support_below(vox: Vector3i) -> bool:
	var below := Vector3i(vox.x, vox.y - 1, vox.z)
	return VoxelMaterial.is_solid(int(_tool.get_voxel(below)))


func _flush_unsupported_drops() -> void:
	## Budgeted, non-reentrant drain — nested flush used to stack-overflow and kill debris.
	if _flushing:
		return
	_flushing = true
	var budget := maxi(unsupported_flush_budget, 1)
	while not _pending_unsupported.is_empty() and budget > 0:
		budget -= 1
		var n: Vector3i = _pending_unsupported.pop_front()
		_try_drop_unsupported(n)
	_flushing = false


func _try_drop_unsupported(n: Vector3i) -> void:
	if _tool == null or _debris_root == null:
		return
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var id := int(_tool.get_voxel(n))
	if not VoxelMaterial.is_building_fabric(id):
		return
	## Support may have returned (unlikely) or column already claimed.
	if _has_support_below(n):
		return
	if _column_xz_queued(n.x, n.z):
		return
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = VoxelMaterial.AIR
	_tool.do_point(n)
	_spawn_cube(n, id)
	## Queue the stack above for the normal parallel cascade — do NOT recurse flush.
	_enqueue_column_above(n, false)
	_collect_unsupported_neighbors(n)


func _pick_spread_neighbor(from_vox: Vector3i) -> Vector3i:
	## Only real fabric neighbors count. Air is skipped; fail only if nothing solid is around.
	var dirs: Array[Vector3i] = [
		Vector3i(1, 0, 0),
		Vector3i(-1, 0, 0),
		Vector3i(0, 0, 1),
		Vector3i(0, 0, -1),
	]
	var candidates: Array[Vector3i] = []  ## hit_vox for collapse_column_above
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	for d in dirs:
		var nx := from_vox.x + d.x
		var nz := from_vox.z + d.z
		if _column_xz_queued(nx, nz):
			continue
		## Search a short vertical band so stepped facades still count as neighbors.
		var found_y := -2147483648
		for dy in [0, 1, -1, 2, -2]:
			var fy: int = from_vox.y + int(dy)
			var probe := Vector3i(nx, fy, nz)
			if VoxelMaterial.is_building_fabric(int(_tool.get_voxel(probe))):
				found_y = fy
				break
		if found_y == -2147483648:
			continue
		## collapse_column_above starts at hit.y+1 → first brick is the fabric we found.
		candidates.append(Vector3i(nx, found_y - 1, nz))
	if candidates.is_empty():
		return Vector3i(-2147483648, 0, 0)
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _column_xz_queued(x: int, z: int) -> bool:
	for col in _columns:
		if (col as Array).is_empty():
			continue
		var v: Vector3i = (col as Array)[0]["vox"]
		if v.x == x and v.z == z:
			return true
	return false


func _release_and_spawn(entry: Dictionary) -> void:
	var v: Vector3i = entry["vox"]
	var mat_id: int = int(entry["mat"])
	## Melee sphere already cleared these — just spawn the cube.
	if bool(entry.get("detached", false)):
		_spawn_cube(v, mat_id)
		_collect_unsupported_neighbors(v)
		return
	## Re-check — something else may have cleared it.
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var cur := int(_tool.get_voxel(v))
	if not VoxelMaterial.is_building_fabric(cur):
		return
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = VoxelMaterial.AIR
	_tool.do_point(v)
	_spawn_cube(v, mat_id if mat_id > 0 else cur)
	_collect_unsupported_neighbors(v)


func _ensure_debris_capacity() -> void:
	## Drop stale refs first so a full list of freed bodies can't block new spawns.
	var write := 0
	for i in _live_bodies.size():
		var b: Variant = _live_bodies[i]
		if b != null and is_instance_valid(b):
			_live_bodies[write] = b
			write += 1
	_live_bodies.resize(write)
	## Evict oldest — but never more than needed for one new cube.
	while _live_bodies.size() >= max_live_debris:
		var old: Variant = _live_bodies.pop_front()
		if old == null or not is_instance_valid(old):
			continue
		var body := old as RigidBody3D
		if body.tree_exited.is_connected(_on_body_exited):
			body.tree_exited.disconnect(_on_body_exited)
		body.queue_free()


func _spawn_cube(vox: Vector3i, mat_id: int) -> void:
	if _debris_root == null or _terrain == null:
		return
	_ensure_debris_capacity()
	var local_center := Vector3(float(vox.x) + 0.5, float(vox.y) + 0.5, float(vox.z) + 0.5)
	var world_center := _terrain.to_global(local_center)
	## Nudge off the column axis so neighbors don't rest in a perfect stack.
	var scatter_m := _voxel_size * spawn_scatter
	var yaw := _rng.randf_range(0.0, TAU)
	var radial := _rng.randf_range(scatter_m * 0.35, scatter_m)
	world_center += Vector3(cos(yaw) * radial, _rng.randf_range(0.0, _voxel_size * 0.08), sin(yaw) * radial)
	var size := Vector3.ONE * (_voxel_size * clampf(cube_scale, 0.7, 1.0))

	var body := RigidBody3D.new()
	body.name = "CascadeCube"
	body.collision_layer = 4
	body.collision_mask = 1
	body.continuous_cd = true
	body.can_sleep = true
	body.gravity_scale = 1.0
	body.mass = clampf(size.x * size.y * size.z * 900.0, 0.35, 12.0)
	body.physics_material_override = _phys_mat
	body.set_meta("debris", "cascade_cube")
	body.set_meta("mat_id", mat_id)
	body.set_meta("origin_vox", vox)

	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = VoxelBlockLibrary.material_for(mat_id)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)

	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)

	_debris_root.add_child(body)
	body.global_position = world_center
	## Strong random orientation so faces don't stack flush.
	body.rotation = Vector3(
		_rng.randf_range(-0.85, 0.85),
		_rng.randf_range(0.0, TAU),
		_rng.randf_range(-0.85, 0.85)
	)
	## Outward burst in the scatter direction + a bit of upward kick.
	var outward := Vector3(cos(yaw), 0.0, sin(yaw))
	var burst := pop_impulse * _rng.randf_range(0.65, 1.25)
	body.linear_velocity = (
		outward * burst
		+ Vector3(
			_rng.randf_range(-pop_impulse * 0.35, pop_impulse * 0.35),
			_rng.randf_range(0.35, pop_impulse * 0.85),
			_rng.randf_range(-pop_impulse * 0.35, pop_impulse * 0.35)
		)
	)
	body.angular_velocity = Vector3(
		_rng.randf_range(-tumble_spin, tumble_spin),
		_rng.randf_range(-tumble_spin, tumble_spin),
		_rng.randf_range(-tumble_spin, tumble_spin)
	)
	_live_bodies.append(body)
	body.tree_exited.connect(_on_body_exited.bind(body))


func _on_body_exited(body: RigidBody3D) -> void:
	_live_bodies.erase(body)
