## On-screen showcase HUD for the Human POC (no Godot editor needed).
class_name ShowcaseHud
extends CanvasLayer

signal reshuffle_requested
signal orbit_pause_toggled(paused: bool)

var _orbit_paused: bool = false
var _title: Label
var _body: Label
var _hint: Label


func _ready() -> void:
	layer = 100
	_build_ui()


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 24.0
	panel.offset_top = 24.0
	panel.offset_right = 520.0
	panel.offset_bottom = 280.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.82)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	_title = Label.new()
	_title.text = "City — Human POC"
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", Color(0.95, 0.96, 0.98))
	vbox.add_child(_title)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.text = (
		"MakeHuman/MPFB pedestrians (male + female), game_engine rig.\n"
		+ "Knees/elbows included — procedural walk swings thighs, calves, arms.\n"
		+ "Anatomy is an empty pelvis proxy slot — full anatomy can attach later.\n"
		+ "Red box = future cars stub. Ground = future voxel city stub.\n"
		+ "Assets: CC0 MakeHuman/MPFB exports (see LICENSE_ASSETS.md)."
	)
	_body.add_theme_font_size_override("font_size", 15)
	_body.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
	vbox.add_child(_body)

	_hint = Label.new()
	_hint.text = "Esc quit · R reshuffle · Space pause orbit"
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8))
	vbox.add_child(_hint)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		get_tree().quit()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				reshuffle_requested.emit()
			KEY_SPACE:
				_orbit_paused = not _orbit_paused
				orbit_pause_toggled.emit(_orbit_paused)
				_hint.text = (
					"Esc quit · R reshuffle · Space resume orbit"
					if _orbit_paused
					else "Esc quit · R reshuffle · Space pause orbit"
				)
