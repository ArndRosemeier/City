## Character motion against live blocky voxels (VoxelBoxMover).
## Uses voxel data directly — not remeshed Godot colliders — so digs/holes are immediate.
class_name VoxelBodyMotion
extends RefCounted

var _mover: VoxelBoxMover = VoxelBoxMover.new()
var _terrain: VoxelTerrain
var _on_floor: bool = false
var _stepped_up: bool = false


func setup(terrain: VoxelTerrain, max_step_height_m: float = 0.38) -> void:
	_terrain = terrain
	_mover.set_step_climbing_enabled(true)
	_mover.set_max_step_height(max_step_height_m)
	## Match VoxelBlockyModel.collision_mask defaults (all solid models use bit 0).
	_mover.set_collision_mask(1)


func set_max_step_height(height_m: float) -> void:
	_mover.set_max_step_height(height_m)


func is_on_floor() -> bool:
	return _on_floor


func has_stepped_up() -> bool:
	return _stepped_up


func has_terrain() -> bool:
	return _terrain != null and is_instance_valid(_terrain)


## Move `body` by `velocity * delta` against voxel AABBs. Returns the applied motion.
func move(
	body: CharacterBody3D,
	capsule: CollisionShape3D,
	velocity: Vector3,
	delta: float
) -> Vector3:
	_on_floor = false
	_stepped_up = false
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


func _capsule_aabb(shape: CapsuleShape3D, capsule_local_pos: Vector3) -> AABB:
	## CapsuleShape3D.height is the full height including hemispheres (Godot 4).
	var r := shape.radius
	var h := shape.height
	var center := capsule_local_pos
	return AABB(
		Vector3(center.x - r, center.y - h * 0.5, center.z - r),
		Vector3(r * 2.0, h, r * 2.0)
	)
