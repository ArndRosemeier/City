## Stacked HUD: one sickly glowing line per active tendril, remaining value centered.
class_name InfectionTendrilHud
extends CanvasLayer

@export var refresh_sec: float = 0.12
@export var line_width_px: float = 220.0
@export var row_height_px: float = 26.0
@export var stack_gap_px: float = 6.0

var _director: Node
var _stack: VBoxContainer
var _rows: Dictionary = {}  # tendril_id → Control
var _accum: float = 0.0
var _pulse_age: float = 0.0


func _ready() -> void:
	layer = UiLayers.HUD_TENDRILS
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_stack = VBoxContainer.new()
	_stack.name = "TendrilStack"
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.add_theme_constant_override("separation", int(stack_gap_px))
	_stack.position = Vector2(18, 48)
	root.add_child(_stack)
	set_process(true)


func bind_director(director: Node) -> void:
	_director = director
	_rebuild_from_director()


func clear_display() -> void:
	_director = null
	for id in _rows.keys():
		var row: Control = _rows[id]
		if is_instance_valid(row):
			row.queue_free()
	_rows.clear()


func _process(delta: float) -> void:
	_pulse_age += delta
	_accum += delta
	if _accum < refresh_sec:
		_pulse_rows()
		return
	_accum = 0.0
	_rebuild_from_director()
	_pulse_rows()


func _rebuild_from_director() -> void:
	if _director == null or not is_instance_valid(_director):
		if not _rows.is_empty():
			clear_display()
		return
	if not _director.has_method("get_tendril_hud_rows"):
		return
	var snapshot: Array = _director.call("get_tendril_hud_rows") as Array
	var alive: Dictionary = {}
	for entry in snapshot:
		if not (entry is Dictionary):
			continue
		var row_data := entry as Dictionary
		var tid := int(row_data.get("id", -1))
		var value := int(row_data.get("value", row_data.get("mass", 0)))
		var depleted := bool(row_data.get("depleted", value <= 0))
		if tid < 0:
			continue
		alive[tid] = true
		var row: Control = _rows.get(tid) as Control
		if row == null or not is_instance_valid(row):
			row = _make_row(tid)
			_rows[tid] = row
			_stack.add_child(row)
		_set_row_value(row, value, depleted)
	## Drop rows for dead tendrils (preserve stack order of survivors).
	var dead: Array[int] = []
	for tid2 in _rows.keys():
		if not alive.has(tid2):
			dead.append(int(tid2))
	for tid3 in dead:
		var doomed: Control = _rows[tid3]
		_rows.erase(tid3)
		if is_instance_valid(doomed):
			doomed.queue_free()
	## Keep visual order matching director snapshot.
	for i in range(snapshot.size()):
		var e: Dictionary = snapshot[i]
		var tid4 := int(e.get("id", -1))
		if not _rows.has(tid4):
			continue
		var r: Control = _rows[tid4]
		_stack.move_child(r, i)


func _make_row(tendril_id: int) -> Control:
	var row := Control.new()
	row.name = "Tendril_%d" % tendril_id
	row.custom_minimum_size = Vector2(line_width_px, row_height_px)
	row.size = Vector2(line_width_px, row_height_px)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_meta("tendril_id", tendril_id)
	row.set_meta("value", 1000)
	row.set_meta("depleted", false)
	row.set_meta("pulse", 0.0)

	var glow := ColorRect.new()
	glow.name = "Glow"
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.color = Color(0.35, 0.95, 0.25, 0.22)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.offset_top = row_height_px * 0.28
	glow.offset_bottom = -row_height_px * 0.28
	row.add_child(glow)

	var core := ColorRect.new()
	core.name = "Core"
	core.mouse_filter = Control.MOUSE_FILTER_IGNORE
	core.color = Color(0.55, 1.0, 0.35, 0.85)
	core.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	core.offset_top = row_height_px * 0.42
	core.offset_bottom = -row_height_px * 0.42
	row.add_child(core)

	var label := Label.new()
	label.name = "Value"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.55, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.08, 0.22, 0.05, 0.95))
	label.add_theme_constant_override("outline_size", 6)
	label.text = "1000"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return row


func _set_row_value(row: Control, value: int, depleted: bool) -> void:
	row.set_meta("value", value)
	row.set_meta("depleted", depleted)
	var label := row.get_node_or_null("Value") as Label
	if label == null:
		label = row.get_node_or_null("Mass") as Label
	if label != null:
		label.text = str(maxi(value, 0))
		if depleted:
			label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.38, 1.0))
			label.add_theme_color_override("font_outline_color", Color(0.35, 0.05, 0.05, 0.95))
		else:
			label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.55, 1.0))
			label.add_theme_color_override("font_outline_color", Color(0.08, 0.22, 0.05, 0.95))


func _pulse_rows() -> void:
	## Soft throb — sickly green while valued, warning red when depleted.
	var i := 0
	for tid in _rows.keys():
		var row: Control = _rows[tid]
		if row == null or not is_instance_valid(row):
			continue
		var glow := row.get_node_or_null("Glow") as ColorRect
		var core := row.get_node_or_null("Core") as ColorRect
		var depleted := bool(row.get_meta("depleted", false))
		var phase := _pulse_age * 2.4 + float(i) * 0.7
		var pulse := 0.55 + 0.45 * sin(phase)
		if depleted:
			if glow != null:
				glow.color = Color(0.95, 0.18, 0.12, lerpf(0.16, 0.42, pulse))
			if core != null:
				core.color = Color(1.0, 0.28, 0.2, lerpf(0.6, 1.0, pulse))
		else:
			if glow != null:
				glow.color = Color(0.3, 0.9, 0.22, lerpf(0.12, 0.34, pulse))
			if core != null:
				core.color = Color(0.5, 1.0, 0.32, lerpf(0.55, 0.95, pulse))
		i += 1
