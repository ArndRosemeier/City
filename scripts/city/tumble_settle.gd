## Snaps laser-tumbled pedestrians / cars onto a sensible resting pose
## (never freeze upright on feet / wheels).
class_name TumbleSettle
extends RefCounted

const QuaterniusLocomotionScript := preload("res://scripts/city/quaternius_locomotion.gd")

enum Kind { PEDESTRIAN, VEHICLE }


static func freeze_lying_down(body: RigidBody3D, kind: Kind, ground_clearance: float = 0.35) -> void:
	if body == null or not is_instance_valid(body):
		return
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO

	var xf := body.global_transform
	var basis := xf.basis.orthonormalized()
	if kind == Kind.PEDESTRIAN:
		## Death01 is authored for an upright root — straighten, then hold the fallen end pose.
		basis = _basis_upright_yaw(basis)
		xf.basis = basis
		xf.origin = _drop_to_ground(body, xf.origin, ground_clearance)
		body.global_transform = xf
		_hold_death_end_pose(body)
	else:
		## Cars: roof or long side down — never settle back onto the wheels.
		basis = _basis_resting_on_side(basis)
		xf.basis = basis
		xf.origin = _drop_to_ground(body, xf.origin, ground_clearance)
		body.global_transform = xf

	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC


## Keep facing (yaw) but force local +Y to world up.
static func _basis_upright_yaw(basis: Basis) -> Basis:
	var forward := -basis.z
	forward.y = 0.0
	if forward.length_squared() < 1e-6:
		forward = -basis.x
		forward.y = 0.0
	if forward.length_squared() < 1e-6:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	return Basis.looking_at(forward, Vector3.UP)


## Rotate so roof or a long side points skyward (wheels never end up down).
static func _basis_resting_on_side(basis: Basis) -> Basis:
	var local_ups: Array[Vector3] = [Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT]
	var best_local := local_ups[0]
	var best_dot := -INF
	for local_up in local_ups:
		var world_up_guess: Vector3 = (basis * local_up).normalized()
		var d := world_up_guess.dot(Vector3.UP)
		if local_up == Vector3.DOWN:
			d += 0.25
		if d > best_dot:
			best_dot = d
			best_local = local_up

	var current: Vector3 = (basis * best_local).normalized()
	if current.length_squared() < 1e-8:
		return basis
	if current.dot(Vector3.UP) > 0.92:
		return basis
	var rot := Quaternion(current, Vector3.UP)
	return Basis(rot) * basis


static func _drop_to_ground(body: RigidBody3D, origin: Vector3, clearance: float) -> Vector3:
	var world := body.get_world_3d()
	if world == null:
		return origin
	var space := world.direct_space_state
	if space == null:
		return origin
	var from := origin + Vector3.UP * 4.0
	var to := origin + Vector3.DOWN * 20.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [body.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return origin
	var ground: Vector3 = hit["position"] as Vector3
	return Vector3(origin.x, ground.y + clearance, origin.z)


static func _hold_death_end_pose(body: RigidBody3D) -> void:
	var anim := _find_anim(body)
	if anim == null:
		return
	var path := "%s/%s" % [QuaterniusLocomotionScript.LIB_NAME, QuaterniusLocomotionScript.ANIM_DEATH]
	if not anim.has_animation(path):
		return
	var clip: Animation = anim.get_animation(path)
	if clip == null:
		return
	anim.play(path, 0.0)
	anim.seek(maxf(clip.length - 0.02, 0.0), true)
	anim.speed_scale = 0.0


static func _find_anim(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null
