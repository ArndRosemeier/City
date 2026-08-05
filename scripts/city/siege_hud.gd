## Run readout for the Siege Quarter: wave, pot, Lodestone HP, intermission clock.
##
## Shown while a run is live. CityRoot owns CanvasLayer visibility for the HUD band; this
## toggles an inner root the same way ZooCloakHud and LootToast do.
extends CanvasLayer

const ACCENT := Color(0.92, 0.72, 0.28, 1.0)
const DANGER := Color(1.0, 0.42, 0.32, 1.0)
const OK := Color(0.45, 0.88, 0.55, 1.0)

@export var refresh_sec: float = 0.15

var _city: Node = null
var _root: Control
var _panel: PanelContainer
var _title: Label
var _wave: Label
var _pot: Label
var _lode: Label
var _clock: Label
var _style: StyleBoxFlat
var _accum: float = 0.0


func _ready() -> void:
	layer = UiLayers.HUD_SIEGE
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.name = "SiegeStrip"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.offset_left = -200.0
	_panel.offset_right = 200.0
	_panel.offset_top = 18.0
	_panel.offset_bottom = 110.0
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.05, 0.04, 0.03, 0.90)
	_style.border_color = ACCENT
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(6)
	_style.content_margin_left = 14
	_style.content_margin_right = 14
	_style.content_margin_top = 6
	_style.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", _style)
	_root.add_child(_panel)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 1)
	_panel.add_child(col)

	_title = _line("SIEGE", 14, ACCENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_wave = _line("Wave 0", 18, Color(0.95, 0.95, 0.92))
	_wave.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_wave)
	_pot = _line("Pot 0", 16, Color(0.92, 0.92, 0.88))
	_pot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_pot)
	_lode = _line("Lodestone —", 16, Color(0.92, 0.92, 0.88))
	_lode.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_lode)
	_clock = _line("", 15, OK)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_clock)
	set_process(true)


func bind_city(city: Node) -> void:
	_city = city
	_refresh()


func clear_display() -> void:
	_city = null
	if _root != null:
		_root.visible = false


func _line(text: String, size_px: int, color: Color) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.add_theme_font_size_override("font_size", size_px)
	lab.add_theme_color_override("font_color", color)
	lab.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	lab.add_theme_constant_override("outline_size", 3)
	return lab


func _process(delta: float) -> void:
	_accum += delta
	if _accum < refresh_sec:
		return
	_accum = 0.0
	_refresh()


func _refresh() -> void:
	if _root == null:
		return
	var ctrl: SiegeController = null
	if _city != null and is_instance_valid(_city) and _city.has_method("active_siege_run"):
		ctrl = _city.call("active_siege_run") as SiegeController
	if ctrl == null or not is_instance_valid(ctrl) or not ctrl.is_running():
		_root.visible = false
		return
	var stats: Dictionary = ctrl.get_hud_stats()
	_root.visible = true
	var phase := int(stats.get("phase", 0))
	var wave := int(stats.get("wave", 0))
	var pot := int(stats.get("pot_total", 0))
	var hp := float(stats.get("lodestone_hp", 0.0))
	var hp_max := float(stats.get("lodestone_hp_max", 1.0))
	var frac := 0.0 if hp_max <= 0.0 else hp / hp_max
	_wave.text = "Wave %d" % wave
	_pot.text = "Pot  %d gems" % pot
	_lode.text = "Lodestone  %d%%" % int(round(frac * 100.0))
	_lode.add_theme_color_override("font_color", DANGER if frac < 0.35 else Color(0.92, 0.92, 0.88))
	_style.border_color = DANGER if frac < 0.35 else ACCENT
	if phase == int(SiegeController.Phase.INTERMISSION):
		var left := float(stats.get("intermission_left", 0.0))
		_clock.text = "Withdraw or hold — next in %s" % _clock_text(left)
		_clock.add_theme_color_override("font_color", OK)
		_title.text = "SIEGE · CLEAR"
	else:
		var alive := int(stats.get("alive", 0))
		var queued := int(stats.get("queued", 0))
		_clock.text = "Alive %d · inbound %d" % [alive, queued]
		_clock.add_theme_color_override("font_color", DANGER)
		_title.text = "SIEGE · HOLD"


static func _clock_text(seconds: float) -> String:
	var whole := maxi(int(ceil(seconds)), 0)
	return "%d:%02d" % [whole / 60, whole % 60]
