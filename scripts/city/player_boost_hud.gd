## HUD buff area — active status effects just below the FPS line.
##
## No panel chrome: icons sit on the world. Same-buff stacks (cloudstone) half-overlap;
## different buff types sit in a loose row beside each other. Visible icons run a small
## idle loop (cloud bob / chip pulse) so active buffs read as live.
## CityRoot owns the CanvasLayer lifecycle; this only binds a walker and polls it.
extends CanvasLayer

const InventoryItemVisualScript := preload("res://scripts/city/inventory_item_visual.gd")
const AbilityIconVisualScript := preload("res://scripts/city/ability_icon_visual.gd")

const SPEED_COLOR := InventoryItemVisualScript.TONIC_SPEED_COLOR
const REGEN_COLOR := InventoryItemVisualScript.TONIC_REGEN_COLOR
const GROW_COLOR := AbilityIconVisualScript.GROW_GREEN
const SHRINK_COLOR := AbilityIconVisualScript.SHRINK_VIOLET
const CLOUD_ICON_MAX := 10
## Default under the place chrome (district + clock). CityRoot may push this down when the
## stats fold opens via `set_buff_area_top`.
const BUFF_AREA_POS := Vector2(16.0, 48.0)
const CHIP_PULSE_HZ := 0.55
const CHIP_PULSE_SCALE := 0.045
const CHIP_PULSE_ALPHA := 0.12

## One soft cloud silhouette for a single cloudstone stack.
class BuffCloudIcon:
	extends Control

	const SIZE := Vector2(22.0, 16.0)
	const BOB_PX := 1.8
	const BOB_HZ := 0.85
	const PUFF_HZ := 1.1
	const PUFF_AMT := 0.07

	var phase: float = 0.0
	var _t: float = 0.0

	func setup(index: int) -> void:
		phase = float(index) * 0.55
		_t = phase

	func _ready() -> void:
		custom_minimum_size = SIZE
		size = SIZE
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(delta: float) -> void:
		if not visible:
			return
		_t += delta
		queue_redraw()

	func _draw() -> void:
		## Draw-space bob/puff — HBox owns Control.position, so motion stays in the mesh.
		var bob := sin(_t * TAU * BOB_HZ + phase) * BOB_PX
		var puff := 1.0 + PUFF_AMT * sin(_t * TAU * PUFF_HZ + phase * 1.3)
		var origin := Vector2(SIZE.x * 0.5, SIZE.y * 0.5 + bob)
		var fill := Color(0.9, 0.94, 1.0, 0.92 + 0.06 * sin(_t * TAU * PUFF_HZ + phase))
		var rim := Color(0.55, 0.7, 0.95, 0.5 + 0.12 * sin(_t * TAU * BOB_HZ + phase + 0.4))
		_draw_disc(origin, Vector2(0.0, 0.5) * puff, 6.8 * puff, rim)
		_draw_disc(origin, Vector2(0.0, 0.5) * puff, 5.6 * puff, fill)
		_draw_disc(origin, Vector2(-4.5, -0.5) * puff, 4.8 * puff, fill)
		_draw_disc(origin, Vector2(4.5, -0.2) * puff, 4.6 * puff, fill)
		_draw_disc(origin, Vector2(0.0, -3.0) * puff, 4.2 * puff, fill)

	func _draw_disc(origin: Vector2, offset: Vector2, radius: float, colour: Color) -> void:
		draw_circle(origin + offset, radius, colour)


var _walker: Node
var _root: Control
var _buff_area: Control
var _row: HBoxContainer
var _cloud_row: HBoxContainer
var _cloud_icons: Array[Control] = []
var _speed_chip: PanelContainer
var _regen_chip: PanelContainer
var _grow_chip: PanelContainer
var _shrink_chip: PanelContainer
var _speed_label: Label
var _regen_label: Label
var _grow_label: Label
var _shrink_label: Label
var _anim_t: float = 0.0


func _ready() -> void:
	layer = UiLayers.HUD_BUFF
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)

	_buff_area = Control.new()
	_buff_area.name = "BuffArea"
	_buff_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buff_area.position = BUFF_AREA_POS
	_root.add_child(_buff_area)

	_row = HBoxContainer.new()
	_row.name = "BuffRow"
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 8)
	_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_buff_area.add_child(_row)

	_cloud_row = HBoxContainer.new()
	_cloud_row.name = "CloudRow"
	_cloud_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Half-icon step: each cloud covers half of the previous one.
	_cloud_row.add_theme_constant_override("separation", -int(BuffCloudIcon.SIZE.x * 0.5))
	_cloud_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_cloud_row.visible = false
	_row.add_child(_cloud_row)
	for i in CLOUD_ICON_MAX:
		var icon := BuffCloudIcon.new()
		icon.name = "Cloud_%d" % (i + 1)
		icon.visible = false
		## Later stacks draw on top of earlier ones in the overlap.
		icon.z_index = i
		icon.setup(i)
		_cloud_row.add_child(icon)
		_cloud_icons.append(icon)

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


## Keep the chip row clear of the place chrome / open stats fold above it.
func set_buff_area_top(top_y: float) -> void:
	if _buff_area == null:
		return
	_buff_area.position = Vector2(BUFF_AREA_POS.x, top_y)


func bind_walker(walker: Node) -> void:
	_walker = walker
	_refresh()
	set_process(_walker != null and is_instance_valid(_walker))


func clear_display() -> void:
	_walker = null
	set_process(false)
	if _root != null:
		_root.visible = false


func _process(delta: float) -> void:
	_anim_t += delta
	_refresh()
	_animate_chips()


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
	var clouds := 0
	if _walker.has_method("speed_boost_left"):
		speed_left = float(_walker.call("speed_boost_left"))
	if _walker.has_method("regen_boost_left"):
		regen_left = float(_walker.call("regen_boost_left"))
	if _walker.has_method("temp_scale_left"):
		scale_left = float(_walker.call("temp_scale_left"))
	if _walker.has_method("temp_scale_sign"):
		scale_sign = int(_walker.call("temp_scale_sign"))
	if _walker.has_method("cloud_stacks"):
		clouds = clampi(int(_walker.call("cloud_stacks")), 0, CLOUD_ICON_MAX)

	var show_speed := speed_left > 0.05
	var show_regen := regen_left > 0.05
	var show_grow := scale_left > 0.05 and scale_sign > 0
	var show_shrink := scale_left > 0.05 and scale_sign < 0
	var show_clouds := clouds > 0
	_speed_chip.visible = show_speed
	_regen_chip.visible = show_regen
	_grow_chip.visible = show_grow
	_shrink_chip.visible = show_shrink
	_cloud_row.visible = show_clouds
	for i in _cloud_icons.size():
		_cloud_icons[i].visible = i < clouds
	if show_speed and _speed_label != null:
		_speed_label.text = "Speed  %ds" % ceili(speed_left)
	if show_regen and _regen_label != null:
		_regen_label.text = "Regen  %ds" % ceili(regen_left)
	if show_grow and _grow_label != null:
		_grow_label.text = "Grow  %ds" % ceili(scale_left)
	if show_shrink and _shrink_label != null:
		_shrink_label.text = "Shrink  %ds" % ceili(scale_left)
	## Keep CanvasLayer visibility under CityRoot's HUD band; only hide the area.
	_root.visible = show_speed or show_regen or show_grow or show_shrink or show_clouds


func _animate_chips() -> void:
	_pulse_chip(_speed_chip, 0.0)
	_pulse_chip(_regen_chip, 1.1)
	_pulse_chip(_grow_chip, 2.0)
	_pulse_chip(_shrink_chip, 2.8)


func _pulse_chip(chip: Control, phase: float) -> void:
	if chip == null or not chip.visible:
		return
	## Containers own position; scale/modulate keep the idle loop without fighting layout.
	var wave := sin(_anim_t * TAU * CHIP_PULSE_HZ + phase)
	chip.pivot_offset = chip.size * 0.5
	var s := 1.0 + CHIP_PULSE_SCALE * wave
	chip.scale = Vector2(s, s)
	chip.modulate = Color(1.0, 1.0, 1.0, 1.0 - CHIP_PULSE_ALPHA * 0.5 + CHIP_PULSE_ALPHA * 0.5 * wave)


func _make_chip(node_name: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	## Transparent fill — only the accent rim + label, matching the open buff area.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
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
