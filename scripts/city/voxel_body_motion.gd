## Character motion against live blocky voxels (VoxelBoxMover).
## Uses voxel data directly — not remeshed Godot colliders — so digs/holes are immediate.
class_name VoxelBodyMotion
extends RefCounted

## Bit 0: solid blocks. Bit 1: water (see VoxelBlockLibrary WATER).
const MASK_SOLID := 1
const MASK_WATER := 2
## Visual water surface height inside a water cell (full-cell mesh top).
const WATER_SURFACE_LOCAL_Y := 1.0

var _mover: VoxelBoxMover = VoxelBoxMover.new()
var _terrain: VoxelTerrain
var _on_floor: bool = false
var _stepped_up: bool = false
var _stepped_down: bool = false
## Last requested step height in world metres (export-facing); converted for the mover.
var _step_height_m: float = 0.55
var _collide_with_water: bool = true


func setup(terrain: VoxelTerrain, max_step_height_m: float = 0.55) -> void:
	_terrain = terrain
	if _terrain == null:
		return
	_mover.set_step_climbing_enabled(true)
	_collide_with_water = true
	_apply_collision_mask()
	set_max_step_height(max_step_height_m)


## Drop the terrain binding. Call before the world tears VoxelTerrain out of the tree —
## `is_instance_valid` stays true across remove_child/queue_free until the frame ends.
func clear() -> void:
	_terrain = null
	_on_floor = false
	_stepped_up = false
	_stepped_down = false


func set_max_step_height(height_m: float) -> void:
	_step_height_m = height_m
	## VoxelBoxMover applies step height in terrain-local space, where one voxel is 1×1×1.
	## CityRoot scales the terrain by VOXEL_SIZE (0.5), so a world-metre value must be
	## converted — passing 0.55 raw only allowed a half-voxel lip.
	var local_units := _world_metres_to_terrain_local(height_m)
	_mover.set_max_step_height(local_units)


func set_collide_with_water(enabled: bool) -> void:
	if _collide_with_water == enabled:
		return
	_collide_with_water = enabled
	_apply_collision_mask()


func _apply_collision_mask() -> void:
	var mask := MASK_SOLID
	if _collide_with_water:
		mask |= MASK_WATER
	_mover.set_collision_mask(mask)


func _world_metres_to_terrain_local(height_m: float) -> float:
	if not has_terrain():
		return height_m
	var sy := absf(_terrain.global_transform.basis.y.length())
	if sy < 0.0001:
		push_error("VoxelBodyMotion: terrain Y scale is degenerate")
		return height_m
	return height_m / sy


func is_on_floor() -> bool:
	return _on_floor


func has_stepped_up() -> bool:
	return _stepped_up


func has_stepped_down() -> bool:
	return _stepped_down


func has_terrain() -> bool:
	## Must be in the tree: to_local/global_transform error once terrain was remove_child'd
	## during regenerate, even though the Object is still instance-valid that frame.
	return (
		_terrain != null
		and is_instance_valid(_terrain)
		and _terrain.is_inside_tree()
	)


## Live VoxelTool for the bound terrain, or null when unbound.
func get_voxel_tool() -> VoxelTool:
	if not has_terrain():
		return null
	return _terrain.get_voxel_tool()


## Voxel material id at a world-space point, or -1 if terrain/tool unavailable.
func get_voxel_at_world(world_pos: Vector3) -> int:
	if not has_terrain():
		return -1
	var tool := get_voxel_tool()
	if tool == null:
		return -1
	var local := _terrain.to_local(world_pos)
	var vox := Vector3i(floori(local.x), floori(local.y), floori(local.z))
	return int(tool.get_voxel(vox))


## World Y of the visual water surface above/near `world_pos`, or NAN if none.
func get_water_surface_world_y(world_pos: Vector3) -> float:
	if not has_terrain():
		return NAN
	var tool := _terrain.get_voxel_tool()
	if tool == null:
		return NAN
	var local := _terrain.to_local(world_pos)
	var vx := floori(local.x)
	var vz := floori(local.z)
	var y_start := floori(local.y)
	var found := -2147483648
	for y in range(y_start + 8, y_start - 24, -1):
		if int(tool.get_voxel(Vector3i(vx, y, vz))) == VoxelMaterial.WATER:
			found = y
			break
	if found == -2147483648:
		return NAN
	var top := found
	while int(tool.get_voxel(Vector3i(vx, top + 1, vz))) == VoxelMaterial.WATER:
		top += 1
	var surface_local := Vector3(local.x, float(top) + WATER_SURFACE_LOCAL_Y, local.z)
	return _terrain.to_global(surface_local).y


## Move `body` by `velocity * delta` against voxel AABBs. Returns the applied motion.
func move(
	body: CharacterBody3D,
	capsule: CollisionShape3D,
	velocity: Vector3,
	delta: float
) -> Vector3:
	_on_floor = false
	_stepped_up = false
	_stepped_down = false
	if not has_terrain() or capsule == null or capsule.shape == null:
		var fallback := velocity * delta
		body.global_position += fallback
		return fallback
	var shape := capsule.shape as CapsuleShape3D
	if shape == null:
		var fallback2 := velocity * delta
		body.global_position += fallback2
		return fallback2

	## Slight shrink avoids false positives on touching voxel faces (VoxelBoxMover docs).
	var aabb := _capsule_aabb(shape, capsule.position).grow(-0.01)
	var motion := velocity * delta
	var pos := body.global_position
	var allowed: Vector3 = _mover.get_motion(pos, motion, aabb, _terrain)
	body.global_position = pos + allowed
	_stepped_up = _mover.has_stepped_up()
	## Floor: we tried to move down (or rest) and vertical motion was blocked/reduced.
	if velocity.y <= 0.0 and allowed.y > motion.y + 0.0001:
		_on_floor = true
	elif velocity.y <= 0.0 and _probe_floor(body.global_position, aabb):
		_on_floor = true
	## VoxelBoxMover only climbs up. A one-voxel stair down would otherwise be a free-fall
	## for a few frames (jump anim, gravity build-up). Snap down by the same height we can
	## step up so a curb is a curb from either direction.
	if not _on_floor and velocity.y <= 0.0:
		var drop := _step_down_delta(body.global_position, aabb)
		if drop < 0.0:
			body.global_position.y += drop
			allowed.y += drop
			_on_floor = true
			_stepped_down = true
	return allowed


func intersects_at(body: CharacterBody3D, capsule: CollisionShape3D, offset: Vector3) -> bool:
	if not has_terrain() or capsule == null or capsule.shape == null:
		return false
	var shape := capsule.shape as CapsuleShape3D
	if shape == null:
		return false
	var aabb := _capsule_aabb(shape, capsule.position)
	aabb.position += body.global_position + offset
	return _mover.intersects(aabb, _terrain)


func _probe_floor(pos: Vector3, local_aabb: AABB) -> bool:
	## Tiny downward query — catches resting on a surface with zero wish velocity.
	var probe := Vector3(0.0, -0.06, 0.0)
	var allowed: Vector3 = _mover.get_motion(pos, probe, local_aabb, _terrain)
	return allowed.y > probe.y + 0.0001


## Negative Y to the nearest stand within `max_step_height`, or 0 if none (cliff / open air).
func _step_down_delta(pos: Vector3, local_aabb: AABB) -> float:
	if _step_height_m <= 0.0001:
		return 0.0
	var probe := Vector3(0.0, -_step_height_m, 0.0)
	var allowed: Vector3 = _mover.get_motion(pos, probe, local_aabb, _terrain)
	## A hit shortens the probe. A free fall through the whole step means keep falling.
	if allowed.y > probe.y + 0.0001 and allowed.y < -0.0001:
		return allowed.y
	return 0.0


func _capsule_aabb(shape: CapsuleShape3D, capsule_local_pos: Vector3) -> AABB:
	## CapsuleShape3D.height is the full height including hemispheres (Godot 4).
	var r := shape.radius
	var h := shape.height
	var center := capsule_local_pos
	return AABB(
		Vector3(center.x - r, center.y - h * 0.5, center.z - r),
		Vector3(r * 2.0, h, r * 2.0)
	)
