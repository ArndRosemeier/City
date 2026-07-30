## Floor selector inside an elevator cabin: a paper-thin Ui3D on the wall opposite the
## bay, one button per landing plus a readout of the floor you are standing on.
##
## Ui3D quads face +Z while the readable side is −Z, which mirrors X for the viewer —
## so column 0 is authored on the high-UV (+X) side to appear on the viewer's left.
##
## Fire the blaster at a button to ride there (see CityWalker._try_press_ui_3d). One
## instance is pooled by CityRoot and rebound as the player moves between cabins.
class_name ElevatorPanel
extends "res://scripts/city/ui_3d.gd"

## The player picked landing `landing_index` on the bound shaft.
signal floor_selected(landing_index: int)

## The plate is sized to its keypad — a fixed width leaves dead surface on short shafts.
const MAX_PANEL_W := 1.2
const MIN_PANEL_W := 0.42
const EDGE_M := 0.06
const MIN_PANEL_H := 0.55
const MAX_PANEL_H := 1.45
## Panel centre above the landing surface — hand height, and clears the 2 m storey band.
const CENTER_H_M := 1.05
## Keeps the quad and its collider out of the wall voxels behind it.
const WALL_INSET_M := 0.07
const MAX_ROWS := 7
## Target button size; columns shrink below this only when a shaft is very tall.
const BTN_W_M := 0.34
const ROW_H_M := 0.17
## Grid band in UV; above it sits the floor readout.
const GRID_BOTTOM := 0.05
const GRID_TOP := 0.8
const SIDE_PAD := 0.04
const GAP_UV := Vector2(0.012, 0.014)
const BTN_PREFIX := "floor_"
const SURFACE_COLOR := Color(0.07, 0.08, 0.11, 1.0)
const BTN_COLOR := Color(0.16, 0.22, 0.34, 1.0)
const BTN_CURRENT_COLOR := Color(0.86, 0.62, 0.12, 1.0)

var _shaft: ElevatorShaft = null
var _index: int = -1
var _readout: Label3D = null
var _floor_by_button: Dictionary[StringName, int] = {}
## UV rect per landing index, so recolouring does not have to re-derive the layout.
var _rects: Array[Rect2] = []


## Mount on `shaft`'s cabin wall at landing `index` and light that floor's button.
## Cheap to call every frame: rebuilds only when the shaft or landing changes.
func bind_to(shaft: ElevatorShaft, index: int, voxel_size: float) -> void:
	if shaft == null:
		push_error("ElevatorPanel.bind_to: null shaft")
		return
	if index < 0 or index >= shaft.landing_count():
		push_error("ElevatorPanel.bind_to: index %d of %d" % [index, shaft.landing_count()])
		return
	if shaft == _shaft and index == _index:
		set_hit_enabled(true)
		return
	var same_shaft := shaft == _shaft
	_shaft = shaft
	_index = index
	if same_shaft:
		## Same keypad, different current floor — only the highlight and readout move.
		_recolor_buttons()
		_update_readout()
	else:
		_build_keypad()
	_mount(voxel_size)
	set_hit_enabled(true)


func unbind() -> void:
	_shaft = null
	_index = -1
	set_hit_enabled(false)


func bound_shaft() -> ElevatorShaft:
	return _shaft


func bound_index() -> int:
	return _index


## Landing index behind `button_id`, or -1 when it is not a floor button.
func landing_for_button(button_id: StringName) -> int:
	return int(_floor_by_button.get(button_id, -1))


## Centre UV of floor `index`'s button, or Vector2.INF when there is none.
func button_uv(index: int) -> Vector2:
	if index < 0 or index >= _rects.size():
		return Vector2.INF
	var rect := _rects[index]
	return rect.position + rect.size * 0.5


## Floor label as shown on the keypad: the lowest landing is the ground floor.
static func floor_label(index: int) -> String:
	return "G" if index == 0 else str(index)


func _build_keypad() -> void:
	var n := _shaft.landing_count()
	var cols := maxi(ceili(float(n) / float(MAX_ROWS)), 1)
	var rows := maxi(ceili(float(n) / float(cols)), 1)
	name = "ElevatorPanel"
	show_debug_marker = false
	surface_color = SURFACE_COLOR
	var panel_w := clampf(
		float(cols) * BTN_W_M + 2.0 * EDGE_M, MIN_PANEL_W, MAX_PANEL_W
	)
	size_m = Vector2(
		panel_w,
		clampf(float(rows) * ROW_H_M / (GRID_TOP - GRID_BOTTOM), MIN_PANEL_H, MAX_PANEL_H)
	)
	clear_buttons()
	_floor_by_button.clear()
	_rects.clear()
	var grid_w := minf(1.0 - 2.0 * SIDE_PAD, float(cols) * BTN_W_M / panel_w)
	var cell := Vector2(grid_w / float(cols), (GRID_TOP - GRID_BOTTOM) / float(rows))
	var x0 := 0.5 - grid_w * 0.5
	for i in range(n):
		var col := i / rows
		var row := i % rows
		## Mirror the column so the lowest floors land on the viewer's left.
		var rect := Rect2(
			x0 + float(cols - 1 - col) * cell.x + GAP_UV.x * 0.5,
			GRID_BOTTOM + float(row) * cell.y + GAP_UV.y * 0.5,
			cell.x - GAP_UV.x,
			cell.y - GAP_UV.y
		)
		var id := StringName(BTN_PREFIX + str(i))
		_floor_by_button[id] = i
		_rects.append(rect)
		add_button(id, rect, floor_label(i), _button_color(i), true)
	rebuild_buttons()


func _button_color(index: int) -> Color:
	return BTN_CURRENT_COLOR if index == _index else BTN_COLOR


func _recolor_buttons() -> void:
	for i in range(_rects.size()):
		var id := StringName(BTN_PREFIX + str(i))
		add_button(id, _rects[i], floor_label(i), _button_color(i), true)
	rebuild_buttons()


func _mount(voxel_size: float) -> void:
	var origin := _shaft.back_wall_center(_index, voxel_size, WALL_INSET_M)
	if not is_finite(origin.x):
		push_error("ElevatorPanel._mount: shaft gave no wall anchor")
		return
	origin.y += CENTER_H_M
	begin(origin, _shaft.bay_yaw())
	if not button_pressed.is_connected(_on_button_pressed):
		button_pressed.connect(_on_button_pressed)
	_update_readout()


func _update_readout() -> void:
	_ensure_readout()
	_readout.text = "FLOOR %s" % floor_label(_index)
	var band_center := GRID_TOP + (1.0 - GRID_TOP) * 0.5
	var local := _uv_to_local(Vector2(0.5, band_center))
	_readout.position = Vector3(local.x, local.y, -0.02)
	_readout.pixel_size = ((1.0 - GRID_TOP) * size_m.y * 0.42) / 64.0


func _ensure_readout() -> void:
	if _readout != null and is_instance_valid(_readout):
		return
	_readout = Label3D.new()
	_readout.name = "Readout"
	_readout.font_size = 64
	_readout.modulate = Color(0.98, 0.9, 0.66, 1.0)
	_readout.outline_size = 14
	_readout.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_readout.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_readout.double_sided = true
	## QuadMesh faces −Z; Label3D faces +Z by default — flip to match the panel face.
	_readout.rotation.y = PI
	add_child(_readout)


func _on_button_pressed(button_id: StringName, _uv: Vector2) -> void:
	var i := landing_for_button(button_id)
	if i < 0:
		return
	if i == _index:
		return
	floor_selected.emit(i)
