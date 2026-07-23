## After a chisel, drop the vertical fabric column above as tumbling RigidBody cubes.
## Spawns bottom→top so the breakdown cascades. Cubes stay marked for later cleanup.
## When max_live_debris is reached, oldest cubes are freed to make room.
## Multiple collapses run round-robin so a new punch starts within one interval.
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

var _terrain: VoxelTerrain
var _tool: VoxelTool
var _debris_root: Node3D
var _voxel_size: float = 0.5
## Active collapses; each entry is Array of {vox: Vector3i, mat: int} bottom→top.
var _columns: Array = []
var _rr_index: int = 0
var _accum: float = 0.0
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
	_rr_index = 0
	_accum = 0.0


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
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var column: Array = []
	var y := hit_vox.y + 1
	var cap := hit_vox.y + max_cubes_per_collapse
	while y <= cap:
		var v := Vector3i(hit_vox.x, y, hit_vox.z)
		var id := int(_tool.get_voxel(v))
		if not VoxelMaterial.is_building_fabric(id):
			break
		column.append({"vox": v, "mat": id})
		y += 1
	if column.is_empty():
		return
	## First cube immediately so the punch never waits on older cascades.
	var first: Dictionary = column.pop_front()
	_release_and_spawn(first)
	if column.is_empty():
		return
	_columns.append(column)
	## Prefer the new column on the next tick.
	_rr_index = _columns.size() - 1


func _physics_process(delta: float) -> void:
	if _columns.is_empty():
		return
	if _tool == null or _terrain == null or _debris_root == null:
		_columns.clear()
		return
	_accum += delta
	while _accum >= cascade_interval_sec and not _columns.is_empty():
		_accum -= cascade_interval_sec
		_spawn_next_round_robin()


func _spawn_next_round_robin() -> void:
	## Skip empty slots; try each column at most once per tick.
	var n := _columns.size()
	for _i in n:
		if _columns.is_empty():
			return
		_rr_index = posmod(_rr_index, _columns.size())
		var col: Array = _columns[_rr_index]
		if col.is_empty():
			_columns.remove_at(_rr_index)
			continue
		var entry: Dictionary = col.pop_front()
		if col.is_empty():
			_columns.remove_at(_rr_index)
		else:
			_rr_index += 1
		_release_and_spawn(entry)
		return


func _release_and_spawn(entry: Dictionary) -> void:
	var v: Vector3i = entry["vox"]
	var mat_id: int = int(entry["mat"])
	## Re-check — something else may have cleared it.
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var cur := int(_tool.get_voxel(v))
	if not VoxelMaterial.is_building_fabric(cur):
		return
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = VoxelMaterial.AIR
	_tool.do_point(v)
	_spawn_cube(v, mat_id if mat_id > 0 else cur)


func _ensure_debris_capacity() -> void:
	while _live_bodies.size() >= max_live_debris:
		var old: Variant = _live_bodies.pop_front()
		if old == null or not is_instance_valid(old):
			continue
		var body := old as RigidBody3D
		if body.tree_exited.is_connected(_on_body_exited):
			body.tree_exited.disconnect(_on_body_exited)
		body.queue_free()


func _spawn_cube(vox: Vector3i, mat_id: int) -> void:
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
	body.collision_layer = 1
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
