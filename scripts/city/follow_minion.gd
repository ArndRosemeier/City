## A cheap follower summoned by the minion ability. Walks toward the player; no combat brain.
class_name FollowMinion
extends CharacterBody3D

const SPEED := 3.4
const STOP_M := 1.6

var follow: Node3D
var _mesh: MeshInstance3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.2
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	add_child(shape)
	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	_mesh.mesh = sphere
	_mesh.position = Vector3(0.0, 0.9, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.75, 0.45)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.55, 0.3)
	mat.emission_energy_multiplier = 0.5
	_mesh.material_override = mat
	add_child(_mesh)


func _physics_process(delta: float) -> void:
	if follow == null or not is_instance_valid(follow):
		queue_free()
		return
	if has_meta("trap_hold_until"):
		var until := int(get_meta("trap_hold_until"))
		if Time.get_ticks_msec() < until:
			velocity = Vector3.ZERO
			move_and_slide()
			return
		remove_meta("trap_hold_until")
	var to := follow.global_position - global_position
	to.y = 0.0
	if to.length() > STOP_M:
		velocity = to.normalized() * SPEED
	else:
		velocity = Vector3.ZERO
	velocity.y -= 18.0 * delta
	move_and_slide()
