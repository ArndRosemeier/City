## In-game player body editor (toggle with C).
class_name CharacterEditor
extends CanvasLayer

signal proportions_changed(props: BodyProportions)
signal sex_change_requested(female: bool)
signal closed

const SLIDERS: Array[Dictionary] = [
	{"key": "height", "label": "Height"},
	{"key": "weight", "label": "Weight"},
	{"key": "muscle", "label": "Muscle"},
	{"key": "torso_length", "label": "Torso length"},
	{"key": "leg_length", "label": "Leg length"},
	{"key": "arm_length", "label": "Arm length"},
	{"key": "shoulder_width", "label": "Shoulder width"},
	{"key": "hip_width", "label": "Hip width"},
	{"key": "head_size", "label": "Head size"},
	{"key": "neck_length", "label": "Neck length"},
	{"key": "hand_size", "label": "Hand size"},
	{"key": "foot_size", "label": "Foot size"},
]

var _props: BodyProportions = BodyProportions.identity()
var _female: bool = false
var _panel: PanelContainer
var _sex_label: Label
var _slider_by_key: Dictionary = {}
var _suppress: bool = false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false
	set_process_unhandled_input(true)


func is_open() -> bool:
	return visible


func open_editor(props: BodyProportions, female: bool) -> void:
	_props = props.duplicate_props() if props != null else BodyProportions.identity()
	_female = female
	_sync_sliders_from_props()
	_refresh_sex_label()
	visible = true


func close_editor() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func get_proportions() -> BodyProportions:
	return _props


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.03, 0.05, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_panel.offset_left = 24.0
	_panel.offset_top = -280.0
	_panel.offset_right = 420.0
	_panel.offset_bottom = 280.0
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Character"
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	var hint := Label.new()
	hint.text = "C close  ·  live preview"
	hint.modulate = Color(0.75, 0.78, 0.85)
	root.add_child(hint)

	var sex_row := HBoxContainer.new()
	sex_row.add_theme_constant_override("separation", 8)
	root.add_child(sex_row)
	_sex_label = Label.new()
	_sex_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sex_row.add_child(_sex_label)
	var male_btn := Button.new()
	male_btn.text = "Male"
	male_btn.pressed.connect(func() -> void: _request_sex(false))
	sex_row.add_child(male_btn)
	var female_btn := Button.new()
	female_btn.text = "Female"
	female_btn.pressed.connect(func() -> void: _request_sex(true))
	sex_row.add_child(female_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 380)
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	for spec in SLIDERS:
		list.add_child(_make_slider_row(String(spec["key"]), String(spec["label"])))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	root.add_child(actions)
	var random_btn := Button.new()
	random_btn.text = "Randomize"
	random_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	random_btn.pressed.connect(_on_randomize)
	actions.add_child(random_btn)
	var reset_btn := Button.new()
	reset_btn.text = "Reset"
	reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_btn.pressed.connect(_on_reset)
	actions.add_child(reset_btn)
	var close_btn := Button.new()
	close_btn.text = "Done"
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn.pressed.connect(close_editor)
	actions.add_child(close_btn)


func _make_slider_row(key: String, label_text: String) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	row.add_child(top)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(label)
	var value_label := Label.new()
	value_label.name = "Value"
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.custom_minimum_size = Vector2(48, 0)
	top.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = -1.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v: float) -> void: _on_slider(key, v, value_label))
	row.add_child(slider)
	_slider_by_key[key] = {"slider": slider, "value_label": value_label}
	return row


func _sync_sliders_from_props() -> void:
	_suppress = true
	for key: Variant in _slider_by_key.keys():
		var entry: Dictionary = _slider_by_key[key]
		var slider: HSlider = entry["slider"]
		var value_label: Label = entry["value_label"]
		var v: float = float(_props.get(String(key)))
		slider.value = v
		value_label.text = "%+.2f" % v
	_suppress = false


func _refresh_sex_label() -> void:
	_sex_label.text = "Body: Female" if _female else "Body: Male"


func _on_slider(key: String, value: float, value_label: Label) -> void:
	value_label.text = "%+.2f" % value
	if _suppress:
		return
	_props.set(key, value)
	proportions_changed.emit(_props)


func _on_randomize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_props = BodyProportions.random(rng)
	_sync_sliders_from_props()
	proportions_changed.emit(_props)


func _on_reset() -> void:
	_props.reset()
	_sync_sliders_from_props()
	proportions_changed.emit(_props)


func _request_sex(female: bool) -> void:
	if female == _female:
		return
	_female = female
	_refresh_sex_label()
	sex_change_requested.emit(_female)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_C or event.keycode == KEY_ESCAPE:
			close_editor()
			get_viewport().set_input_as_handled()
