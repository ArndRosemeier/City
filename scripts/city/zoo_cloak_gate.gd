## The one control the visitor gets at a Monster Zoo: a lit post beside the gate that hands
## out the spectator cloak.
##
## It does not start, stop or steer the war — the stations do that on their own timers. All
## this does is take the player out of the target list for two minutes, which is the
## difference between watching the fight and being in it.
class_name ZooCloakGate
extends "res://scripts/city/ui_3d.gd"

signal cloak_requested()

const PANEL_W := 2.2
const PANEL_H := 1.4
const BTN_CLOAK := &"cloak"
const IDLE_COLOR := Color(0.86, 0.20, 0.18, 1.0)
const ACTIVE_COLOR := Color(0.22, 0.78, 0.92, 1.0)

var _label: Label3D = null
var _active: bool = false


func setup_gate(origin: Vector3, face_yaw: float) -> void:
	name = "ZooCloakGate"
	size_m = Vector2(PANEL_W, PANEL_H)
	show_debug_marker = false
	surface_color = Color(0.06, 0.05, 0.06, 1.0)
	add_button(
		BTN_CLOAK,
		Rect2(0.06, 0.06, 0.88, 0.52),
		"Cloak",
		IDLE_COLOR
	)
	begin(origin, face_yaw)
	_build_caption()
	if not button_pressed.is_connected(_on_button_pressed):
		button_pressed.connect(_on_button_pressed)


## Recolour the post while the cloak is up, so the state is readable from the field and not
## only from the HUD strip.
func set_cloak_active(active: bool, seconds_left: float) -> void:
	_active = active
	set_surface_glow(
		Color(0.04, 0.12, 0.15, 1.0) if active else Color(0.14, 0.03, 0.03, 1.0),
		1.6 if active else 0.6
	)
	add_button(
		BTN_CLOAK,
		Rect2(0.06, 0.06, 0.88, 0.52),
		"Refresh" if active else "Cloak",
		ACTIVE_COLOR if active else IDLE_COLOR
	)
	if _label != null and is_instance_valid(_label):
		_label.text = (
			"SPECTATOR  %s" % _clock(seconds_left) if active else "SPECTATOR CLOAK"
		)
		_label.modulate = ACTIVE_COLOR if active else IDLE_COLOR


static func _clock(seconds: float) -> String:
	var whole := maxi(int(ceil(seconds)), 0)
	return "%d:%02d" % [whole / 60, whole % 60]


func _build_caption() -> void:
	_label = Label3D.new()
	_label.name = "Caption"
	_label.text = "SPECTATOR CLOAK"
	_label.font_size = 64
	_label.pixel_size = (PANEL_H * 0.20) / 64.0
	_label.modulate = IDLE_COLOR
	_label.outline_size = 18
	_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.92)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_label.double_sided = true
	_label.position = Vector3(0.0, PANEL_H * 0.30, -0.05)
	_label.rotation.y = PI
	add_child(_label)


func _on_button_pressed(button_id: StringName, _uv: Vector2) -> void:
	if button_id != BTN_CLOAK:
		return
	cloak_requested.emit()
