## Lobbed trap. Arms as an ArmedTrap when it hits the ground (or times out in air).
class_name TrapProjectile
extends RigidBody3D

const ArmedTrapScript := preload("res://scripts/city/armed_trap.gd")

signal landed(trap: ArmedTrap)

const LIFE_SEC := 4.0

var _spent: bool = false


func _ready() -> void:
	gravity_scale = 1.35
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	collision_layer = 0
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.18
	shape.shape = sphere
	add_child(shape)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.35, 0.12, 0.35)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.18, 0.12)
	mesh.material_override = mat
	add_child(mesh)
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(LIFE_SEC).timeout.connect(_timeout_land)


func _on_body_entered(_body: Node) -> void:
	## Area/body signals cannot spawn another Area3D that toggles monitoring inline.
	call_deferred("_land")


func _timeout_land() -> void:
	_land()


func _land() -> void:
	if _spent:
		return
	_spent = true
	var trap: ArmedTrap = ArmedTrapScript.new() as ArmedTrap
	trap.name = "ArmedTrap"
	var parent := get_parent()
	if parent == null:
		queue_free()
		return
	var pos := global_position
	parent.add_child(trap)
	trap.global_position = pos
	landed.emit(trap)
	queue_free()
