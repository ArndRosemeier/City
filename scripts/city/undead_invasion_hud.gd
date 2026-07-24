## Compact undead-invasion readout: mages, converted minions, giant flag.
extends CanvasLayer

@export var refresh_sec: float = 0.2

var _director: Node
var _panel: Control
var _title: Label
var _mages: Label
var _converted: Label
var _giant: Label
var _accum: float = 0.0
var _pulse: float = 0.0


func _ready() -> void:
	layer = 13
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = VBoxContainer.new()
	_panel.name = "InvasionPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_constant_override("separation", 2)
	## Top-right under the checkbox strip — keeps left free for tendril HUD.
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -220.0
	_panel.offset_right = -16.0
	_panel.offset_top = 48.0
	_panel.offset_bottom = 140.0
	_panel.visible = false
	root.add_child(_panel)

	_title = _make_line("UNDEAD INVASION", 15, Color(0.75, 0.95, 0.88))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_panel.add_child(_title)
	_mages = _make_line("Mages: 0", 18, Color(0.92, 0.92, 0.95))
	_mages.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_panel.add_child(_mages)
	_converted = _make_line("Converted: 0", 18, Color(0.92, 0.92, 0.95))
	_converted.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_panel.add_child(_converted)
	_giant = _make_line("Giant: —", 18, Color(0.92, 0.92, 0.95))
	_giant.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_panel.add_child(_giant)
	set_process(true)


func bind_director(director: Node) -> void:
	_director = director
	_refresh()


func clear_display() -> void:
	_director = null
	if _panel != null:
		_panel.visible = false


func _make_line(text: String, size_px: int, color: Color) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.add_theme_font_size_override("font_size", size_px)
	lab.add_theme_color_override("font_color", color)
	lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	lab.add_theme_constant_override("outline_size", 4)
	return lab


func _process(delta: float) -> void:
	_pulse += delta
	_accum += delta
	if _accum < refresh_sec:
		_pulse_giant_label()
		return
	_accum = 0.0
	_refresh()
	_pulse_giant_label()


func _refresh() -> void:
	if _director == null or not is_instance_valid(_director) or not _director.has_method("get_hud_stats"):
		if _panel != null:
			_panel.visible = false
		return
	var stats: Dictionary = _director.call("get_hud_stats") as Dictionary
	var show := bool(stats.get("active", false))
	_panel.visible = show
	if not show:
		return
	_mages.text = "Mages: %d" % int(stats.get("mages", 0))
	_converted.text = "Converted: %d" % int(stats.get("converted", 0))
	if bool(stats.get("giant", false)):
		_giant.text = "Giant: ACTIVE"
		_giant.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	else:
		_giant.text = "Giant: —"
		_giant.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
		_giant.modulate = Color.WHITE


func _pulse_giant_label() -> void:
	if _giant == null or not _panel.visible:
		return
	if not _giant.text.begins_with("Giant: ACTIVE"):
		return
	var a := 0.72 + 0.28 * sin(_pulse * 6.0)
	_giant.modulate = Color(1.0, a, a, 1.0)
