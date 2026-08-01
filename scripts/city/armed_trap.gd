## A thrown hold plate: lands, arms, then freezes whoever steps on it for 10 seconds.
##
## Symmetric by design — mobs, pedestrians, and the player all trigger it. Consumed on trigger.
class_name ArmedTrap
extends Area3D

const HOLD_SEC := 10.0
const ARM_DELAY_SEC := 0.35
const TRIGGER_RADIUS := 0.55

signal triggered(victim: Node3D)
signal finished

var _armed: bool = false
var _spent: bool = false
var _mesh: MeshInstance3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 2
	## Deferred: this node may be added from a projectile body_entered callback.
	set_deferred("monitoring", true)
	set_deferred("monitorable", false)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = TRIGGER_RADIUS
	shape.shape = sphere
	add_child(shape)
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 0.08, 0.7)
	_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.2, 0.15, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.25, 0.1)
	mat.emission_energy_multiplier = 0.6
	_mesh.material_override = mat
	add_child(_mesh)
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(ARM_DELAY_SEC).timeout.connect(_arm)


func _arm() -> void:
	if _spent:
		return
	_armed = true
	if _mesh != null and _mesh.material_override is StandardMaterial3D:
		(_mesh.material_override as StandardMaterial3D).emission_energy_multiplier = 1.4


func _on_body_entered(body: Node) -> void:
	if not _armed or _spent:
		return
	var victim := body as Node3D
	if victim == null:
		return
	_spent = true
	set_deferred("monitoring", false)
	triggered.emit(victim)
	_hold_victim(victim)
	queue_free()


func _hold_victim(victim: Node3D) -> void:
	## Freeze whatever motor the actor has for HOLD_SEC, then release.
	if victim.has_method("begin_trap_hold"):
		victim.call("begin_trap_hold", HOLD_SEC)
	elif victim is CharacterBody3D:
		(victim as CharacterBody3D).velocity = Vector3.ZERO
		victim.set_meta("trap_hold_until", Time.get_ticks_msec() + int(HOLD_SEC * 1000.0))
	finished.emit()
