## Countdown strip for the Monster Zoo spectator cloak.
##
## The cloak is invisible from the inside — nothing about the player changes except that
## forty territories' worth of monsters stop acquiring them. That is exactly the kind of
## state that has to be on screen with a clock on it, because the moment it lapses the
## nearest fight turns around.
extends CanvasLayer

const CLOAK_COLOR := Color(0.35, 0.85, 1.0, 1.0)
## Under this many seconds the strip pulses red — time to walk back to the gate.
const WARN_SEC := 15.0
const WARN_COLOR := Color(1.0, 0.42, 0.32, 1.0)

var _root: Control
var _panel: PanelContainer
var _label: Label
var _style: StyleBoxFlat


func _ready() -> void:
	layer = UiLayers.HUD_ZOO_CLOAK
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.name = "CloakStrip"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.offset_left = -140.0
	_panel.offset_right = 140.0
	## Under the compass, which owns top-centre. Overlapping it hid the rose behind a cloak state
	## the player can already see on their own body.
	_panel.offset_top = PlayerCompassHud.BAND_BOTTOM + 10.0
	_panel.offset_bottom = _panel.offset_top + 36.0
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.03, 0.06, 0.09, 0.88)
	_style.border_color = CLOAK_COLOR
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(6)
	_style.content_margin_left = 14
	_style.content_margin_right = 14
	_style.content_margin_top = 5
	_style.content_margin_bottom = 5
	_panel.add_theme_stylebox_override("panel", _style)
	_root.add_child(_panel)

	_label = Label.new()
	_label.name = "Label"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", CLOAK_COLOR)
	_label.add_theme_color_override("font_outline_color", Color(0.01, 0.03, 0.05, 0.95))
	_label.add_theme_constant_override("outline_size", 3)
	_label.text = "SPECTATOR"
	_panel.add_child(_label)


## Show `seconds_left` as M:SS, or hide the strip once the cloak has lapsed.
func show_countdown(seconds_left: float) -> void:
	if _root == null:
		return
	if seconds_left <= 0.0:
		_root.visible = false
		return
	var whole := maxi(int(ceil(seconds_left)), 0)
	_label.text = "SPECTATOR  %d:%02d" % [whole / 60, whole % 60]
	var tint := WARN_COLOR if seconds_left <= WARN_SEC else CLOAK_COLOR
	_label.add_theme_color_override("font_color", tint)
	_style.border_color = tint
	_root.visible = true


func hide_countdown() -> void:
	if _root != null:
		_root.visible = false
