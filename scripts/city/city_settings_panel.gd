## Top-right Settings button + Graphics / Controls tabs. Prefs in user://city_graphics.cfg.
class_name CitySettingsPanel
extends CanvasLayer

signal closed
signal opened
signal settings_applied(settings: Dictionary)
signal controls_changed(controls: PlayerControls)
signal spawn_meteors_toggled(enabled: bool)
signal undead_invasion_toggled(enabled: bool)

const PlayerControlsScript := preload("res://scripts/city/player_controls.gd")

const CONFIG_PATH := "user://city_graphics.cfg"
## Bump when graphics defaults change so old user configs pick up the new baseline.
const CONFIG_VERSION := 2
## Bump when default combat binds change so saved layouts pick up the new mapping.
const CONTROLS_VERSION := 2

var _btn: Button
var _spawn_meteors_check: CheckBox
var _undead_invasion_check: CheckBox
var _panel: PanelContainer
var _dim: ColorRect
var _open: bool = false
var _suppress: bool = false
var _value_labels: Dictionary = {}  # key -> Label
var _controls: Dictionary = {}  # graphics key -> Control
var _settings: Dictionary = {}
var _player_controls: PlayerControls
var _bind_buttons: Dictionary = {}  # action_id -> Button
var _listening_action: String = ""
var _listen_hint: Label


func _ready() -> void:
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player_controls = PlayerControlsScript.new() as PlayerControls
	_settings = default_settings()
	_load_config()
	_build_ui()
	_sync_controls_from_settings()
	_sync_bind_buttons()
	set_process_unhandled_input(true)
	set_process_input(true)


func is_open() -> bool:
	return _open


func get_settings() -> Dictionary:
	return _settings.duplicate(true)


func get_player_controls() -> PlayerControls:
	return _player_controls


func is_spawn_meteors_enabled() -> bool:
	return _spawn_meteors_check != null and _spawn_meteors_check.button_pressed


func is_undead_invasion_enabled() -> bool:
	return _undead_invasion_check != null and _undead_invasion_check.button_pressed


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
	_cancel_listen()
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
	var top_bar := HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.focus_mode = Control.FOCUS_NONE
	top_bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top_bar.offset_left = -520.0
	top_bar.offset_top = 12.0
	top_bar.offset_right = -16.0
	top_bar.offset_bottom = 44.0
	top_bar.add_theme_constant_override("separation", 10)
	top_bar.alignment = BoxContainer.ALIGNMENT_END
	add_child(top_bar)

	_spawn_meteors_check = CheckBox.new()
	_spawn_meteors_check.name = "SpawnMeteorsCheck"
	_spawn_meteors_check.text = "Spawn meteors"
	_spawn_meteors_check.focus_mode = Control.FOCUS_NONE
	_spawn_meteors_check.button_pressed = false
	_spawn_meteors_check.toggled.connect(_on_spawn_meteors_toggled)
	top_bar.add_child(_spawn_meteors_check)

	_undead_invasion_check = CheckBox.new()
	_undead_invasion_check.name = "UndeadInvasionCheck"
	_undead_invasion_check.text = "Undead invasion"
	_undead_invasion_check.focus_mode = Control.FOCUS_NONE
	_undead_invasion_check.button_pressed = false
	_undead_invasion_check.toggled.connect(_on_undead_invasion_toggled)
	top_bar.add_child(_undead_invasion_check)

	_btn = Button.new()
	_btn.name = "SettingsButton"
	_btn.text = "Settings"
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.custom_minimum_size = Vector2(112, 0)
	_btn.pressed.connect(toggle_panel)
	top_bar.add_child(_btn)

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
	_panel.offset_left = -460.0
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

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(outer)

	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 20)
	outer.add_child(title)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(tabs)

	var gfx_scroll := ScrollContainer.new()
	gfx_scroll.name = "Graphics"
	gfx_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gfx_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(gfx_scroll)

	var gfx_root := VBoxContainer.new()
	gfx_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gfx_root.add_theme_constant_override("separation", 8)
	gfx_scroll.add_child(gfx_root)
	_build_graphics_tab(gfx_root)

	var ctrl_scroll := ScrollContainer.new()
	ctrl_scroll.name = "Controls"
	ctrl_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ctrl_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(ctrl_scroll)

	var ctrl_root := VBoxContainer.new()
	ctrl_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl_root.add_theme_constant_override("separation", 6)
	ctrl_scroll.add_child(ctrl_root)
	_build_controls_tab(ctrl_root)


func _build_graphics_tab(root: VBoxContainer) -> void:
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


func _build_controls_tab(root: VBoxContainer) -> void:
	_listen_hint = Label.new()
	_listen_hint.text = "Click a binding, then press a key or mouse button (+ modifiers)."
	_listen_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_listen_hint.add_theme_font_size_override("font_size", 13)
	_listen_hint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	root.add_child(_listen_hint)

	var reset := Button.new()
	reset.text = "Reset controls to defaults"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(_on_reset_controls)
	root.add_child(reset)

	var last_group := ""
	for row in PlayerControls.ACTION_META:
		var group := str(row.get("group", ""))
		if group != last_group:
			last_group = group
			var g := Label.new()
			g.text = group
			g.add_theme_font_size_override("font_size", 15)
			g.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
			root.add_child(g)
		var action_id := str(row["id"])
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		root.add_child(line)
		var name_l := Label.new()
		name_l.text = str(row["label"])
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.clip_text = true
		line.add_child(name_l)
		var bind_btn := Button.new()
		bind_btn.focus_mode = Control.FOCUS_NONE
		bind_btn.custom_minimum_size = Vector2(148, 0)
		bind_btn.pressed.connect(_on_bind_button_pressed.bind(action_id))
		line.add_child(bind_btn)
		_bind_buttons[action_id] = bind_btn


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


func _sync_bind_buttons() -> void:
	for action_id in _bind_buttons.keys():
		var btn: Button = _bind_buttons[action_id]
		if action_id == _listening_action:
			btn.text = "Press key..."
		else:
			btn.text = _player_controls.binding_label(action_id)


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


func _on_spawn_meteors_toggled(on: bool) -> void:
	spawn_meteors_toggled.emit(on)


func _on_undead_invasion_toggled(on: bool) -> void:
	undead_invasion_toggled.emit(on)


func _on_reset_controls() -> void:
	_cancel_listen()
	_player_controls.reset_to_defaults()
	_sync_bind_buttons()
	_emit_controls()


func _on_bind_button_pressed(action_id: String) -> void:
	if _listening_action == action_id:
		_cancel_listen()
		return
	_listening_action = action_id
	if _listen_hint != null:
		_listen_hint.text = "Listening for '%s' — Esc cancels." % action_id
	_sync_bind_buttons()


func _cancel_listen() -> void:
	if _listening_action.is_empty():
		return
	_listening_action = ""
	if _listen_hint != null:
		_listen_hint.text = "Click a binding, then press a key or mouse button (+ modifiers)."
	_sync_bind_buttons()


func _commit_binding(binding: Dictionary) -> void:
	if _listening_action.is_empty():
		return
	var action := _listening_action
	_player_controls.set_binding(action, binding)
	_listening_action = ""
	if _listen_hint != null:
		_listen_hint.text = "Bound %s → %s" % [action, PlayerControls.format_binding(binding)]
	_sync_bind_buttons()
	_emit_controls()


func _emit_applied() -> void:
	settings_applied.emit(_settings.duplicate(true))
	_save_config()


func _emit_controls() -> void:
	controls_changed.emit(_player_controls)
	_save_config()


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _listening_action.is_empty():
			return
		close_panel()


func _input(event: InputEvent) -> void:
	if _listening_action.is_empty() or not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ek := event as InputEventKey
		if ek.keycode == KEY_ESCAPE:
			_cancel_listen()
			get_viewport().set_input_as_handled()
			return
		## Don't bind bare modifier keys as the main code when they are only modifiers —
		## except for actions like sprint / build_assign that intentionally use them.
		var code := ek.keycode
		if code == KEY_SHIFT or code == KEY_CTRL or code == KEY_ALT or code == KEY_META:
			_commit_binding({
				"device": "key",
				"code": int(code),
				"shift": false,
				"ctrl": false,
				"alt": false,
			})
		else:
			_commit_binding({
				"device": "key",
				"code": int(code),
				"shift": ek.shift_pressed,
				"ctrl": ek.ctrl_pressed,
				"alt": ek.alt_pressed,
			})
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		_commit_binding({
			"device": "mouse",
			"code": int(mb.button_index),
			"shift": mb.shift_pressed,
			"ctrl": mb.ctrl_pressed,
			"alt": mb.alt_pressed,
		})
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if not _listening_action.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	var ver := int(cfg.get_value("graphics", "config_version", 1))
	if ver >= CONFIG_VERSION:
		for key in default_settings().keys():
			if cfg.has_section_key("graphics", key):
				_settings[key] = cfg.get_value("graphics", key)
	var cver := int(cfg.get_value("controls", "config_version", 0))
	if cver >= CONTROLS_VERSION and cfg.has_section_key("controls", "bindings"):
		var raw: Variant = cfg.get_value("controls", "bindings")
		if raw is Dictionary:
			_player_controls.load_save_dict(raw as Dictionary)


func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)
	cfg.set_value("graphics", "config_version", CONFIG_VERSION)
	for key in _settings.keys():
		cfg.set_value("graphics", key, _settings[key])
	cfg.set_value("controls", "config_version", CONTROLS_VERSION)
	cfg.set_value("controls", "bindings", _player_controls.to_save_dict())
	cfg.save(CONFIG_PATH)
