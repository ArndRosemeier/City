## Bottom-center energy bar — bound to CityWalker energy pool.
extends CanvasLayer

@export var bar_width_px: float = 280.0
@export var bar_height_px: float = 18.0

var _walker: Node
var _fill: ColorRect
var _glow: ColorRect
var _label: Label
var _track_w: float = 280.0


func _ready() -> void:
	layer = UiLayers.HUD_ENERGY
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var panel := PanelContainer.new()
	panel.name = "EnergyPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -bar_width_px * 0.5 - 10.0
	panel.offset_right = bar_width_px * 0.5 + 10.0
	panel.offset_top = -168.0
	panel.offset_bottom = -138.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.82)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 3)
	panel.add_child(col)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.7, 0.92, 1.0, 0.95))
	_label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.06, 0.9))
	_label.add_theme_constant_override("outline_size", 3)
	_label.text = "Energy 100 / 100"
	col.add_child(_label)

	var track := Control.new()
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.custom_minimum_size = Vector2(bar_width_px, bar_height_px)
	col.add_child(track)

	var back := ColorRect.new()
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.color = Color(0.12, 0.16, 0.2, 0.95)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.add_child(back)

	_glow = ColorRect.new()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.color = Color(0.25, 0.75, 1.0, 0.22)
	_glow.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_glow.offset_right = bar_width_px
	track.add_child(_glow)

	_fill = ColorRect.new()
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.color = Color(0.35, 0.85, 1.0, 0.92)
	_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_fill.offset_right = bar_width_px
	track.add_child(_fill)

	_track_w = bar_width_px
	visible = false


func bind_walker(walker: Node) -> void:
	if _walker != null and is_instance_valid(_walker) and _walker.has_signal("energy_changed"):
		if _walker.is_connected("energy_changed", _on_energy_changed):
			_walker.disconnect("energy_changed", _on_energy_changed)
	_walker = walker
	if _walker == null or not is_instance_valid(_walker):
		visible = false
		return
	visible = true
	if _walker.has_signal("energy_changed") and not _walker.is_connected(
		"energy_changed", _on_energy_changed
	):
		_walker.connect("energy_changed", _on_energy_changed)
	var cur := 100.0
	var mx := 100.0
	if _walker.has_method("get_energy"):
		cur = float(_walker.call("get_energy"))
	if _walker.has_method("get_energy_max"):
		mx = float(_walker.call("get_energy_max"))
	_on_energy_changed(cur, mx)


func clear_display() -> void:
	bind_walker(null)


func _on_energy_changed(current: float, maximum: float) -> void:
	var mx := maxf(maximum, 0.001)
	var frac := clampf(current / mx, 0.0, 1.0)
	var w := _track_w * frac
	if _fill != null:
		_fill.offset_right = w
		## Cool cyan when full, warmer when low.
		_fill.color = Color(0.35, 0.85, 1.0, 0.92).lerp(Color(1.0, 0.45, 0.3, 0.95), 1.0 - frac)
	if _glow != null:
		_glow.offset_right = w
		_glow.color = Color(0.25, 0.75, 1.0, 0.18 + 0.12 * frac)
	if _label != null:
		_label.text = "Energy %d / %d" % [int(round(current)), int(round(maximum))]
