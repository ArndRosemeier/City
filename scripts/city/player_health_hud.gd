## Bottom-left wound bar — bound to the CityWalker health pool.
##
## Deliberately unlike the energy bar in all four ways a player reads a bar at a glance: it sits
## in the corner instead of under the crosshair, it is crimson instead of cyan, it is chunky and
## split into four segments instead of one smooth track, and it is captioned with a heart. Two
## coloured rectangles of the same shape in the same place would be a UI bug that only shows up
## when someone dies while their energy was low.
class_name PlayerHealthHud
extends CanvasLayer

const CityMinimapScript := preload("res://scripts/city/city_minimap.gd")

@export var bar_width_px: float = 240.0
@export var bar_height_px: float = 26.0
## Dividers drawn over the track. Four segments means one conversion orb is visibly a quarter.
@export var segment_count: int = 4

var _walker: Node
var _fill: ColorRect
var _pulse: ColorRect
var _label: Label
var _track_w: float = 240.0
## Latest fraction, so the near-death pulse has something to breathe against.
var _fraction: float = 1.0
var _pulse_phase: float = 0.0

## Below this the bar pulses — the point where one more hit of anything ends the run.
const CRITICAL_FRACTION := 0.26
## Stacked on top of the minimap in the same bottom-left column, sharing its left margin. Read
## off `city_minimap.gd` rather than guessed: the two panels overlapping is exactly the kind of
## HUD collision nobody notices until a screenshot.
const MINIMAP_TOP_PX := -CityMinimapScript.MAP_SIZE_PX - 52.0
const PANEL_HEIGHT_PX := 62.0
const COLOR_HEALTHY := Color(0.86, 0.16, 0.24, 0.95)
const COLOR_CRITICAL := Color(1.0, 0.55, 0.16, 0.98)


func _ready() -> void:
	layer = UiLayers.HUD_HEALTH
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel := PanelContainer.new()
	panel.name = "HealthPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 14.0
	## Exactly the track plus its two content margins, so the fill reaches the frame at full
	## rather than leaving a permanent sliver of empty track nobody can spend.
	panel.offset_right = 14.0 + bar_width_px + 20.0
	panel.offset_top = MINIMAP_TOP_PX - PANEL_HEIGHT_PX - 8.0
	panel.offset_bottom = MINIMAP_TOP_PX - 8.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.03, 0.05, 0.84)
	style.border_color = Color(0.55, 0.1, 0.16, 0.9)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.8, 0.97))
	_label.add_theme_color_override("font_outline_color", Color(0.08, 0.0, 0.02, 0.95))
	_label.add_theme_constant_override("outline_size", 3)
	_label.text = "♥ HEALTH  100 / 100"
	col.add_child(_label)

	var track := Control.new()
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.custom_minimum_size = Vector2(bar_width_px, bar_height_px)
	col.add_child(track)

	var back := ColorRect.new()
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.color = Color(0.22, 0.05, 0.07, 0.95)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.add_child(back)

	_fill = ColorRect.new()
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.color = COLOR_HEALTHY
	_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_fill.offset_right = bar_width_px
	track.add_child(_fill)

	_pulse = ColorRect.new()
	_pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pulse.color = Color(1.0, 0.9, 0.6, 0.0)
	_pulse.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.add_child(_pulse)

	if segment_count < 1:
		push_error("PlayerHealthHud: %d segments is not a bar" % segment_count)
		segment_count = 1
	for i in range(1, segment_count):
		var divider := ColorRect.new()
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		divider.color = Color(0.08, 0.02, 0.03, 0.95)
		divider.set_anchors_preset(Control.PRESET_TOP_LEFT)
		divider.offset_left = bar_width_px * (float(i) / float(segment_count)) - 1.0
		divider.offset_right = divider.offset_left + 2.0
		divider.offset_top = 0.0
		divider.offset_bottom = bar_height_px
		track.add_child(divider)

	_track_w = bar_width_px
	visible = false


func bind_walker(walker: Node) -> void:
	if _walker != null and is_instance_valid(_walker) and _walker.has_signal("health_changed"):
		if _walker.is_connected("health_changed", _on_health_changed):
			_walker.disconnect("health_changed", _on_health_changed)
	_walker = walker
	if _walker == null or not is_instance_valid(_walker):
		visible = false
		return
	visible = true
	if not _walker.has_signal("health_changed"):
		push_error("PlayerHealthHud: %s has no health to show" % _walker.name)
		return
	if not _walker.is_connected("health_changed", _on_health_changed):
		_walker.connect("health_changed", _on_health_changed)
	_on_health_changed(
		float(_walker.call("get_health")), float(_walker.call("get_health_max"))
	)


func clear_display() -> void:
	bind_walker(null)


## Shown at a fixed state for screenshots and for the HUD audit tool — no walker involved.
func show_preview(current: float, maximum: float) -> void:
	visible = true
	_on_health_changed(current, maximum)


## How much of the track is filled, as drawn. What a screenshot shows, in a number a test can
## read — a bar bound to the right pool and still painting a full track is a silent HUD.
func fill_fraction() -> float:
	if _fill == null or _track_w <= 0.0:
		push_error("PlayerHealthHud: asked how full a bar that was never built is")
		return 0.0
	return _fill.offset_right / _track_w


func _on_health_changed(current: float, maximum: float) -> void:
	if maximum <= 0.0:
		push_error("PlayerHealthHud: a maximum of %f is not a pool" % maximum)
		return
	_fraction = clampf(current / maximum, 0.0, 1.0)
	if _fill != null:
		_fill.offset_right = _track_w * _fraction
		_fill.color = (
			COLOR_CRITICAL if _fraction <= CRITICAL_FRACTION else COLOR_HEALTHY
		)
	if _label != null:
		_label.text = "♥ HEALTH  %d / %d" % [int(ceil(current)), int(round(maximum))]


func _process(delta: float) -> void:
	if _pulse == null:
		return
	if _fraction > CRITICAL_FRACTION or _fraction <= 0.0:
		_pulse.color.a = 0.0
		_pulse_phase = 0.0
		return
	_pulse_phase = fmod(_pulse_phase + delta * 5.0, TAU)
	_pulse.color.a = 0.06 + 0.1 * (0.5 + 0.5 * sin(_pulse_phase))
