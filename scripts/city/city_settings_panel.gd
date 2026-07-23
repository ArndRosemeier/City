## Top-right Settings button + performance/quality panel for live tuning.
class_name CitySettingsPanel
extends CanvasLayer

signal closed
signal opened
signal settings_applied(settings: Dictionary)

const CONFIG_PATH := "user://city_graphics.cfg"
## Bump when defaults change so old user configs pick up the new baseline.
const CONFIG_VERSION := 2

var _btn: Button
var _panel: PanelContainer
var _dim: ColorRect
var _open: bool = false
var _suppress: bool = false
var _value_labels: Dictionary = {}  # key -> Label
var _controls: Dictionary = {}  # key -> Control
var _settings: Dictionary = {}


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_settings = default_settings()
	_load_config()
	_build_ui()
	_sync_controls_from_settings()
	set_process_unhandled_input(true)


func is_open() -> bool:
	return _open


func get_settings() -> Dictionary:
	return _settings.duplicate(true)


func open_panel() -> void:
	if _open:
		return
	_open = true
	_dim.visible = true
	_panel.visible = true
	_btn.text = "Close"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	opened.emit()


func close_panel() -> void:
	if not _open:
		return
	_open = false
	_dim.visible = false
	_panel.visible = false
	_btn.text = "Settings"
	_save_config()
	closed.emit()


func toggle_panel() -> void:
	if _open:
		close_panel()
	else:
		open_panel()


static func default_settings() -> Dictionary:
	## Default = Low: weak GPUs get playable FPS out of the box.
	return {
		"render_scale": 0.55,
		"ssao": false,
		"glow": false,
		"fog": true,
		"shadows": true,
		"shadow_distance_m": 60.0,
		"voxel_view_vox": 100,
		"collision_view_vox": 48,
		"bubble_radius_m": 240.0,
		"crowd_render_m": 40.0,
		"vehicle_render_m": 70.0,
		"max_omni_lights": 4,
	}


func apply_preset(name: String) -> void:
	match name:
		"low":
			_settings = default_settings()
		"medium":
			_settings = {
				"render_scale": 0.75,
				"ssao": true,
				"glow": true,
				"fog": true,
				"shadows": true,
				"shadow_distance_m": 120.0,
				"voxel_view_vox": 130,
				"collision_view_vox": 64,
				"bubble_radius_m": 360.0,
				"crowd_render_m": 70.0,
				"vehicle_render_m": 120.0,
				"max_omni_lights": 12,
			}
		"high":
			_settings = {
				"render_scale": 0.9,
				"ssao": true,
				"glow": true,
				"fog": true,
				"shadows": true,
				"shadow_distance_m": 160.0,
				"voxel_view_vox": 220,
				"collision_view_vox": 80,
				"bubble_radius_m": 420.0,
				"crowd_render_m": 100.0,
				"vehicle_render_m": 160.0,
				"max_omni_lights": 16,
			}
		_:
			return
	_sync_controls_from_settings()
	_emit_applied()


func _build_ui() -> void:
	_btn = Button.new()
	_btn.name = "SettingsButton"
	_btn.text = "Settings"
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_btn.offset_left = -128.0
	_btn.offset_top = 12.0
	_btn.offset_right = -16.0
	_btn.offset_bottom = 44.0
	_btn.pressed.connect(toggle_panel)
	add_child(_btn)

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0.02, 0.03, 0.05, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	_dim.gui_input.connect(_on_dim_input)
	add_child(_dim)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.visible = false
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -420.0
	_panel.offset_top = 56.0
	_panel.offset_right = -16.0
	_panel.offset_bottom = -24.0
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	scroll.add_child(root)

	var title := Label.new()
	title.text = "Graphics / Performance"
	title.add_theme_font_size_override("font_size", 20)
	root.add_child(title)

	var hint := Label.new()
	hint.text = "Changes apply live. Esc closes."
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	root.add_child(hint)

	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 8)
	root.add_child(presets)
	for p in [
		{"id": "low", "label": "Low"},
		{"id": "medium", "label": "Medium"},
		{"id": "high", "label": "High"},
	]:
		var b := Button.new()
		b.text = str(p["label"])
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pid: String = str(p["id"])
		b.pressed.connect(func() -> void: apply_preset(pid))
		presets.add_child(b)

	_add_slider(root, "render_scale", "Render scale", 0.45, 1.0, 0.05)
	_add_check(root, "ssao", "SSAO")
	_add_check(root, "glow", "Glow / bloom")
	_add_check(root, "fog", "Fog")
	_add_check(root, "shadows", "Sun shadows")
	_add_slider(root, "shadow_distance_m", "Shadow distance (m)", 40.0, 220.0, 5.0)
	_add_slider(root, "voxel_view_vox", "Voxel mesh radius (vox)", 80.0, 280.0, 10.0)
	_add_slider(root, "collision_view_vox", "Collision radius (vox)", 32.0, 128.0, 8.0)
	_add_slider(root, "bubble_radius_m", "District bubble (m)", 180.0, 520.0, 20.0)
	_add_slider(root, "crowd_render_m", "Ped render (m)", 20.0, 160.0, 5.0)
	_add_slider(root, "vehicle_render_m", "Vehicle render (m)", 40.0, 220.0, 10.0)
	_add_slider(root, "max_omni_lights", "Street lamp lights", 0.0, 24.0, 1.0)


func _add_slider(parent: VBoxContainer, key: String, label: String, min_v: float, max_v: float, step: float) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	parent.add_child(row)
	var head := HBoxContainer.new()
	row.add_child(head)
	var name_l := Label.new()
	name_l.text = label
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_l)
	var val_l := Label.new()
	val_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_l.custom_minimum_size = Vector2(56, 0)
	head.add_child(val_l)
	_value_labels[key] = val_l
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v: float) -> void: _on_slider(key, v))
	row.add_child(slider)
	_controls[key] = slider


func _add_check(parent: VBoxContainer, key: String, label: String) -> void:
	var box := CheckButton.new()
	box.text = label
	box.focus_mode = Control.FOCUS_NONE
	box.toggled.connect(func(on: bool) -> void: _on_check(key, on))
	parent.add_child(box)
	_controls[key] = box


func _sync_controls_from_settings() -> void:
	_suppress = true
	for key in _controls.keys():
		var c: Control = _controls[key]
		var v: Variant = _settings.get(key)
		if c is HSlider:
			(c as HSlider).value = float(v)
			_update_value_label(key, float(v))
		elif c is CheckButton:
			(c as CheckButton).button_pressed = bool(v)
	_suppress = false


func _update_value_label(key: String, value: float) -> void:
	var lab: Label = _value_labels.get(key) as Label
	if lab == null:
		return
	if key == "render_scale":
		lab.text = "%.2f" % value
	elif key.ends_with("_m") or key == "render_scale":
		lab.text = "%.0f" % value
	else:
		lab.text = "%d" % int(round(value))


func _on_slider(key: String, value: float) -> void:
	if _suppress:
		return
	if key in ["voxel_view_vox", "collision_view_vox", "max_omni_lights"]:
		_settings[key] = int(round(value))
	else:
		_settings[key] = value
	_update_value_label(key, value)
	_emit_applied()


func _on_check(key: String, on: bool) -> void:
	if _suppress:
		return
	_settings[key] = on
	_emit_applied()


func _emit_applied() -> void:
	settings_applied.emit(_settings.duplicate(true))
	_save_config()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_panel()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	var ver := int(cfg.get_value("graphics", "config_version", 1))
	if ver < CONFIG_VERSION:
		## Drop stale prefs so Low becomes the new default for existing installs.
		return
	for key in default_settings().keys():
		if cfg.has_section_key("graphics", key):
			_settings[key] = cfg.get_value("graphics", key)


func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("graphics", "config_version", CONFIG_VERSION)
	for key in _settings.keys():
		cfg.set_value("graphics", key, _settings[key])
	cfg.save(CONFIG_PATH)
