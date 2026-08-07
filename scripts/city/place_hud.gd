## Top-left place chrome: district name, analog day clock, and a fold for non-vital stats.
##
## Lives on CityRoot's HudLayer (not its own CanvasLayer) so it shares the stats band with the
## crosshair. The always-on row is the place name plus the clock; FPS and friends hide behind the
## arrow until someone asks for them.
class_name PlaceHud
extends Control

signal fold_changed(open: bool)
## Fires whenever the bottom edge of the chrome (including an open fold) moves, so buff chips
## can sit clear of it.
signal bottom_changed(bottom_y: float)

const POS := Vector2(16.0, 12.0)
const ROW_H := 30.0
const CLOCK_SIZE := 28.0
const FOLD_BTN_W := 26.0
const GAP := 8.0
const FOLD_PAD_TOP := 4.0

const CHIP_BG := Color(0.32, 0.2, 0.1, 0.42)
const CHIP_TEXT := Color(0.93, 0.86, 0.72, 0.95)
const FOLD_TEXT := Color(0.88, 0.88, 0.84, 0.9)
const FACE_FILL := Color(0.9, 0.82, 0.68, 0.92)
const FACE_RIM := Color(0.42, 0.26, 0.12, 0.95)
const HAND_COLOR := Color(0.22, 0.12, 0.06, 0.95)
const HUB_COLOR := Color(0.35, 0.18, 0.08, 0.95)

var _row: HBoxContainer
var _name_panel: PanelContainer
var _name_label: Label
var _clock: _AnalogClock
var _fold_btn: Button
var _fold_panel: PanelContainer
var _fold_label: Label
var _fold_open: bool = false
var _hour: float = 12.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = POS
	_build()
	_apply_fold()
	call_deferred("_emit_bottom")


func set_district_name(place: String) -> void:
	if _name_label == null:
		return
	_name_label.text = place if not place.is_empty() else "—"


func set_hour(hour: float) -> void:
	_hour = hour
	if _clock != null:
		_clock.set_hour(hour)


func set_fold_line(text: String) -> void:
	if _fold_label == null:
		return
	_fold_label.text = text


func is_fold_open() -> bool:
	return _fold_open


## Bottom edge of this chrome in parent space (POS.y + height), for stacking buffs under it.
func bottom_y() -> float:
	var h := ROW_H
	if _fold_open and _fold_panel != null:
		h += FOLD_PAD_TOP + _fold_panel.get_combined_minimum_size().y
	return POS.y + h


func _build() -> void:
	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", int(GAP))
	_row.custom_minimum_size = Vector2(0.0, ROW_H)
	add_child(_row)

	_name_panel = PanelContainer.new()
	_name_panel.name = "DistrictName"
	_name_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_sb := StyleBoxFlat.new()
	name_sb.bg_color = CHIP_BG
	name_sb.set_corner_radius_all(4)
	name_sb.content_margin_left = 8
	name_sb.content_margin_right = 8
	name_sb.content_margin_top = 3
	name_sb.content_margin_bottom = 3
	_name_panel.add_theme_stylebox_override("panel", name_sb)
	_name_label = Label.new()
	_name_label.name = "Name"
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.add_theme_font_size_override("font_size", 15)
	_name_label.add_theme_color_override("font_color", CHIP_TEXT)
	_name_label.text = "—"
	_name_panel.add_child(_name_label)
	_row.add_child(_name_panel)

	_clock = _AnalogClock.new()
	_clock.name = "Clock"
	_clock.custom_minimum_size = Vector2(CLOCK_SIZE, CLOCK_SIZE)
	_clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_clock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_child(_clock)

	_fold_btn = Button.new()
	_fold_btn.name = "FoldButton"
	_fold_btn.focus_mode = Control.FOCUS_NONE
	_fold_btn.custom_minimum_size = Vector2(FOLD_BTN_W, ROW_H - 4.0)
	_fold_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_fold_btn.tooltip_text = "Show FPS and other stats"
	_style_fold_button(_fold_btn)
	_fold_btn.pressed.connect(_toggle_fold)
	_row.add_child(_fold_btn)

	_fold_panel = PanelContainer.new()
	_fold_panel.name = "Fold"
	_fold_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fold_panel.position = Vector2(0.0, ROW_H + FOLD_PAD_TOP)
	var fold_sb := StyleBoxFlat.new()
	fold_sb.bg_color = Color(0.28, 0.18, 0.1, 0.5)
	fold_sb.set_corner_radius_all(4)
	fold_sb.content_margin_left = 8
	fold_sb.content_margin_right = 8
	fold_sb.content_margin_top = 3
	fold_sb.content_margin_bottom = 3
	_fold_panel.add_theme_stylebox_override("panel", fold_sb)
	_fold_label = Label.new()
	_fold_label.name = "Stats"
	_fold_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fold_label.add_theme_font_size_override("font_size", 14)
	_fold_label.add_theme_color_override("font_color", FOLD_TEXT)
	_fold_label.text = "—"
	_fold_panel.add_child(_fold_label)
	add_child(_fold_panel)


func _style_fold_button(btn: Button) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CHIP_BG
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	btn.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.4, 0.26, 0.14, 0.55)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_color_override("font_color", CHIP_TEXT)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.78, 1.0))
	btn.add_theme_font_size_override("font_size", 14)


func _toggle_fold() -> void:
	_fold_open = not _fold_open
	_apply_fold()
	fold_changed.emit(_fold_open)
	call_deferred("_emit_bottom")


func _apply_fold() -> void:
	if _fold_panel != null:
		_fold_panel.visible = _fold_open
	if _fold_btn != null:
		_fold_btn.text = "▾" if _fold_open else "▸"
		_fold_btn.tooltip_text = (
			"Hide stats" if _fold_open else "Show FPS and other stats"
		)


func _emit_bottom() -> void:
	bottom_changed.emit(bottom_y())


## Classic 12-hour face driven by the game's day/night hour (0–24, fractional minutes).
class _AnalogClock:
	extends Control

	var _hour: float = 12.0

	func set_hour(hour: float) -> void:
		if is_equal_approx(_hour, hour):
			return
		_hour = hour
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := mini(size.x, size.y) * 0.5 - 1.0
		draw_circle(c, r, PlaceHud.FACE_RIM)
		draw_circle(c, r - 1.6, PlaceHud.FACE_FILL)
		## Twelve hour ticks — short marks, heavier at the cardinals.
		for i in range(12):
			var a := deg_to_rad(float(i) * 30.0 - 90.0)
			var outer := c + Vector2(cos(a), sin(a)) * (r - 2.2)
			var inner := c + Vector2(cos(a), sin(a)) * (r - (5.5 if i % 3 == 0 else 4.0))
			var tick_col := (
				PlaceHud.FACE_RIM if i % 3 == 0
				else Color(PlaceHud.FACE_RIM.r, PlaceHud.FACE_RIM.g, PlaceHud.FACE_RIM.b, 0.7)
			)
			draw_line(inner, outer, tick_col, 1.4 if i % 3 == 0 else 1.0, true)
		var minutes := fposmod(_hour, 1.0) * 60.0
		var hour_12 := fposmod(_hour, 12.0)
		var hour_angle := deg_to_rad((hour_12 * 30.0 + minutes * 0.5) - 90.0)
		var minute_angle := deg_to_rad(minutes * 6.0 - 90.0)
		draw_line(
			c,
			c + Vector2(cos(hour_angle), sin(hour_angle)) * (r * 0.52),
			PlaceHud.HAND_COLOR,
			2.2,
			true
		)
		draw_line(
			c,
			c + Vector2(cos(minute_angle), sin(minute_angle)) * (r * 0.78),
			PlaceHud.HAND_COLOR,
			1.5,
			true
		)
		draw_circle(c, 1.8, PlaceHud.HUB_COLOR)
