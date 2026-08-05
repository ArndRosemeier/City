## Foundation-pad marker: a lay-flat "+" plate on an empty pad.
##
## The pad itself is the whole affordance. Pressing it asks CityRoot for the build picker, a
## screen-space modal at the mouse — recipe choice does not belong on a world panel a dozen
## pads wide, and a slab standing beside every pad blocked the sightlines the fight is about.
class_name SiegePadPanel
extends "res://scripts/city/ui_3d.gd"

signal pad_pressed(pad_index: int)

const PLATE_M := 1.1
const BTN_PLUS := &"plus"

const IDLE_COLOR := Color(0.78, 0.62, 0.22, 1.0)
## Metres past which a plate stops drawing. There are hundreds of these on a tile, so the cutoff
## is what keeps the field affordable — see `Ui3D.set_view_distance_m`.
const VIEW_DISTANCE_M := 30.0

var _pad_index: int = -1


func setup_pad(origin: Vector3, face_yaw: float, pad_index: int) -> void:
	name = "SiegePadPanel_%d" % pad_index
	_pad_index = pad_index
	size_m = Vector2(PLATE_M, PLATE_M)
	show_debug_marker = false
	## Opaque on purpose. An alpha face would put every plate in the transparent pass, and
	## hundreds of sorted translucent quads lying on the ground is the worst overdraw case there
	## is — the district would pay for the whole field instead of the part in front of the player.
	surface_color = Color(0.07, 0.06, 0.05, 1.0)
	view_distance_m = VIEW_DISTANCE_M
	begin(origin, face_yaw)
	## Ui3D is an upright XY face with normal −Z. +90° lays that face up at the player;
	## −90° buries it in the foundation (same convention as GoTableUi3D).
	rotation.x = deg_to_rad(90.0)
	if not button_pressed.is_connected(_on_button_pressed):
		button_pressed.connect(_on_button_pressed)
	_rebuild_face()


func pad_index() -> int:
	return _pad_index


## Kept for the controller's uniform refresh sweep — the plate has no state to recompute, the
## picker reads the pot when it opens.
func refresh() -> void:
	if button_count() == 0:
		_rebuild_face()


func _rebuild_face() -> void:
	clear_buttons()
	add_button(BTN_PLUS, Rect2(0.16, 0.16, 0.68, 0.68), "+", IDLE_COLOR)


func _on_button_pressed(button_id: StringName, _uv: Vector2) -> void:
	if button_id != BTN_PLUS:
		return
	pad_pressed.emit(_pad_index)
