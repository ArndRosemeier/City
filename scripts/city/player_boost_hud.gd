## Top-of-HUD chips for active speed / regen tonics and temporary grow / shrink.
##
## World auras are the primary read for tonics; these chips cover first-person camera
## angles and confirm which timer is still ticking when several are stacked.
extends CanvasLayer

const InventoryItemVisualScript := preload("res://scripts/city/inventory_item_visual.gd")
const AbilityIconVisualScript := preload("res://scripts/city/ability_icon_visual.gd")

const SPEED_COLOR := InventoryItemVisualScript.TONIC_SPEED_COLOR
const REGEN_COLOR := InventoryItemVisualScript.TONIC_REGEN_COLOR
const GROW_COLOR := AbilityIconVisualScript.GROW_GREEN
const SHRINK_COLOR := AbilityIconVisualScript.SHRINK_VIOLET

var _walker: Node
var _root: Control
var _row: HBoxContainer
var _speed_chip: PanelContainer
var _regen_chip: PanelContainer
var _grow_chip: PanelContainer
var _shrink_chip: PanelContainer
var _speed_label: Label
var _regen_label: Label
var _grow_label: Label
var _shrink_label: Label


func _ready() -> void:
	layer = UiLayers.HUD_BOOST
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)

	_row = HBoxContainer.new()
	_row.name = "BoostRow"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 8)
	_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_row.offset_left = -280.0
	_row.offset_right = 280.0
	_row.offset_top = -210.0
	_row.offset_bottom = -178.0
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(_row)

	_speed_chip = _make_chip("SpeedChip", SPEED_COLOR)
	_speed_label = _speed_chip.get_node("Label") as Label
	_row.add_child(_speed_chip)

	_regen_chip = _make_chip("RegenChip", REGEN_COLOR)
	_regen_label = _regen_chip.get_node("Label") as Label
	_row.add_child(_regen_chip)

	_grow_chip = _make_chip("GrowChip", GROW_COLOR)
	_grow_label = _grow_chip.get_node("Label") as Label
	_row.add_child(_grow_chip)

	_shrink_chip = _make_chip("ShrinkChip", SHRINK_COLOR)
	_shrink_label = _shrink_chip.get_node("Label") as Label
	_row.add_child(_shrink_chip)


func bind_walker(walker: Node) -> void:
	_walker = walker
	_refresh()
	set_process(_walker != null and is_instance_valid(_walker))


func clear_display() -> void:
	_walker = null
	set_process(false)
	if _root != null:
		_root.visible = false


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if _root == null:
		return
	if _walker == null or not is_instance_valid(_walker):
		_root.visible = false
		return
	var speed_left := 0.0
	var regen_left := 0.0
	var scale_left := 0.0
	var scale_sign := 0
	if _walker.has_method("speed_boost_left"):
		speed_left = float(_walker.call("speed_boost_left"))
	if _walker.has_method("regen_boost_left"):
		regen_left = float(_walker.call("regen_boost_left"))
	if _walker.has_method("temp_scale_left"):
		scale_left = float(_walker.call("temp_scale_left"))
	if _walker.has_method("temp_scale_sign"):
		scale_sign = int(_walker.call("temp_scale_sign"))

	var show_speed := speed_left > 0.05
	var show_regen := regen_left > 0.05
	var show_grow := scale_left > 0.05 and scale_sign > 0
	var show_shrink := scale_left > 0.05 and scale_sign < 0
	_speed_chip.visible = show_speed
	_regen_chip.visible = show_regen
	_grow_chip.visible = show_grow
	_shrink_chip.visible = show_shrink
	if show_speed and _speed_label != null:
		_speed_label.text = "Speed  %ds" % ceili(speed_left)
	if show_regen and _regen_label != null:
		_regen_label.text = "Regen  %ds" % ceili(regen_left)
	if show_grow and _grow_label != null:
		_grow_label.text = "Grow  %ds" % ceili(scale_left)
	if show_shrink and _shrink_label != null:
		_shrink_label.text = "Shrink  %ds" % ceili(scale_left)
	## Keep CanvasLayer visibility under CityRoot's HUD band; only hide the chips.
	_root.visible = show_speed or show_regen or show_grow or show_shrink


func _make_chip(node_name: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.09, 0.86)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.name = "Label"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.98))
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.06, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	label.text = "—"
	panel.add_child(label)
	return panel
