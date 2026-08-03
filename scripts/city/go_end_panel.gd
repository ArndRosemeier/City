## Giant post-match billboard in front of the voxel Go board.
class_name GoEndPanel
extends Ui3D

signal dismissed()

const BTN_OK := &"ok"
const PANEL_W_M := 20.0
const PANEL_H_M := 10.0

var _result: GoMatchResult = null


func setup(origin: Vector3, face_yaw: float) -> void:
	size_m = Vector2(PANEL_W_M, PANEL_H_M)
	surface_color = Color(0.12, 0.13, 0.16, 0.94)
	show_debug_marker = false
	begin(origin, face_yaw)
	if not button_pressed.is_connected(_on_button):
		button_pressed.connect(_on_button)
	hide_panel()


func show_result(result: GoMatchResult) -> void:
	if result == null:
		push_error("GoEndPanel.show_result: null result")
		return
	_result = result
	_rebuild_chrome()
	visible = true
	set_hit_enabled(true)


func hide_panel() -> void:
	_result = null
	clear_buttons()
	visible = false
	set_hit_enabled(false)


func _rebuild_chrome() -> void:
	clear_buttons()
	if _result == null:
		rebuild_buttons()
		return
	## UV y grows upward. Big type — each strip is metres tall on a 20×10 face.
	add_button(
		&"hdr",
		Rect2(0.06, 0.86, 0.88, 0.1),
		"Game over",
		Color(0.28, 0.32, 0.38),
		true
	)
	var win_col := Color(0.2, 0.45, 0.28)
	if _result.reason == "stopped":
		win_col = Color(0.35, 0.38, 0.42)
	elif _result.winner == GoBoardState.WHITE:
		win_col = Color(0.55, 0.55, 0.58)
	elif _result.winner == 0:
		win_col = Color(0.35, 0.38, 0.42)
	elif _result.reason.begins_with("resign"):
		win_col = Color(0.45, 0.28, 0.2)
	add_button(
		&"winner",
		Rect2(0.06, 0.56, 0.88, 0.26),
		_result.headline(),
		win_col,
		true
	)
	add_button(
		&"score",
		Rect2(0.06, 0.34, 0.88, 0.18),
		_result.score_line(),
		Color(0.18, 0.2, 0.24),
		true
	)
	add_button(
		&"reason",
		Rect2(0.06, 0.2, 0.88, 0.1),
		_result.reason_line(),
		Color(0.22, 0.24, 0.28),
		true
	)
	add_button(
		BTN_OK,
		Rect2(0.28, 0.05, 0.44, 0.12),
		"Continue",
		Color(0.28, 0.5, 0.34),
		true
	)
	rebuild_buttons()


func _on_button(button_id: StringName, _uv: Vector2) -> void:
	if button_id != BTN_OK:
		return
	hide_panel()
	dismissed.emit()
