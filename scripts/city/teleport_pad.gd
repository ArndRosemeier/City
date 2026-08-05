## The launch disc in the middle of a teleport chamber. Stand on it, click it, go.
##
## Clicked rather than walked into, like GemChest: the blaster's pre-fire swallow resolves it
## (`CityWalker._try_world_interact`), so the body sits on collision layer 1 and the node
## carries the `world_interact` group.
class_name TeleportPad
extends Node3D

## The pad was clicked. The chamber decides whether that means anything.
signal pad_pressed

const RADIUS_M := 1.35
const DISC_H_M := 0.06
const RING_H_M := 0.10
const IDLE_COLOR := Color(0.06, 0.30, 0.42, 1.0)
const ARMED_COLOR := Color(0.20, 0.95, 1.0, 1.0)

var _disc: MeshInstance3D = null
var _ring: MeshInstance3D = null
var _armed: bool = false


func build(world_pos: Vector3) -> void:
	global_position = world_pos
	_disc = _make_cylinder("Disc", RADIUS_M, DISC_H_M, DISC_H_M * 0.5, 0.6)
	_ring = _make_cylinder("Ring", RADIUS_M * 0.42, RING_H_M, RING_H_M * 0.5 + 0.02, 2.2)
	var body := StaticBody3D.new()
	body.name = "ClickBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS_M
	cyl.height = RING_H_M * 2.0
	shape.shape = cyl
	shape.position = Vector3(0.0, RING_H_M * 0.5, 0.0)
	body.add_child(shape)
	add_child(body)
	add_to_group("world_interact")
	set_meta("world_interact", true)
	_apply_colors()


## Lit when a destination is armed, so the pad tells you whether clicking will do anything.
func set_armed(armed: bool) -> void:
	if _armed == armed:
		return
	_armed = armed
	_apply_colors()


func is_armed() -> bool:
	return _armed


## Returns true in every case where the click belonged to the pad, armed or not, so an unarmed
## pad swallows the shot instead of turning it into a bolt fired at the chamber floor.
func interact_at_world(_world_pos: Vector3) -> bool:
	pad_pressed.emit()
	return true


func _apply_colors() -> void:
	_tint(_disc, IDLE_COLOR if not _armed else ARMED_COLOR.darkened(0.45), 0.6 if not _armed else 1.4)
	_tint(_ring, IDLE_COLOR.lightened(0.15) if not _armed else ARMED_COLOR, 1.4 if not _armed else 4.0)


func _tint(mi: MeshInstance3D, color: Color, energy: float) -> void:
	if mi == null or not is_instance_valid(mi):
		return
	var mat := mi.material_override as StandardMaterial3D
	if mat == null:
		push_error("TeleportPad: %s has no material" % mi.name)
		return
	mat.albedo_color = color
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = energy


func _make_cylinder(
	node_name: String, radius: float, height: float, y: float, energy: float
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	mesh.rings = 1
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = IDLE_COLOR
	mat.metallic = 0.6
	mat.roughness = 0.25
	mat.emission_enabled = true
	mat.emission = IDLE_COLOR
	mat.emission_energy_multiplier = energy
	mi.material_override = mat
	mi.position = Vector3(0.0, y, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi
