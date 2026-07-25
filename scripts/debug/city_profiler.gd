## Autoload: reusable runtime profiler for Eccentri City hot paths.
## Toggle overlay with F7 (rebindable). Also registers Performance custom monitors.
extends CanvasLayer

const PlayerControlsScript := preload("res://scripts/city/player_controls.gd")

const MAX_SCOPES := 48
const SMOOTH := 0.18

var _enabled: bool = false
var _panel: PanelContainer
var _body: Label
var _scopes: Dictionary = {}  ## name -> {acc_us, last_us, peak_us, count}
var _counters: Dictionary = {}  ## name -> int
var _frame_scope_us: Dictionary = {}  ## name -> us this frame (open nesting stack)
var _open: Array = []  ## stack of {name, t0_us}
var _frame_ms_smooth: float = 0.0
var _physics_ms_smooth: float = 0.0
var _last_physics_usec: int = 0
var _controls: RefCounted


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_panel.visible = false
	_register_monitors()


func _register_monitors() -> void:
	Performance.add_custom_monitor(&"city/frame_ms", Callable(self, "_mon_frame_ms"))
	Performance.add_custom_monitor(&"city/physics_ms", Callable(self, "_mon_physics_ms"))
	Performance.add_custom_monitor(&"city/debris_live", Callable(self, "_mon_debris_live"))
	Performance.add_custom_monitor(&"city/debris_pending", Callable(self, "_mon_debris_pending"))
	Performance.add_custom_monitor(&"city/crowd_agents", Callable(self, "_mon_crowd_agents"))
	Performance.add_custom_monitor(&"city/scope_cascade_us", Callable(self, "_mon_scope_cascade"))
	Performance.add_custom_monitor(&"city/scope_crowd_us", Callable(self, "_mon_scope_crowd"))


func _mon_frame_ms() -> float:
	return _frame_ms_smooth


func _mon_physics_ms() -> float:
	return _physics_ms_smooth


func _mon_debris_live() -> float:
	return float(int(_counters.get("debris_live", 0)))


func _mon_debris_pending() -> float:
	return float(int(_counters.get("debris_pending", 0)))


func _mon_crowd_agents() -> float:
	return float(int(_counters.get("crowd_agents", 0)))


func _mon_scope_cascade() -> float:
	return float(_scope_last_us("cascade"))


func _mon_scope_crowd() -> float:
	return float(_scope_last_us("crowd"))


func _scope_last_us(name: String) -> int:
	var s: Variant = _scopes.get(name)
	if s == null:
		return 0
	return int((s as Dictionary).get("last_us", 0))


func set_counter(name: String, value: int) -> void:
	_counters[name] = value


func add_counter(name: String, delta: int = 1) -> void:
	_counters[name] = int(_counters.get(name, 0)) + delta


func begin(name: String) -> void:
	_open.append({"name": name, "t0": Time.get_ticks_usec()})


func end(name: String) -> void:
	if _open.is_empty():
		push_error("CityProfiler: end('%s') with empty scope stack" % name)
		return
	var top: Dictionary = _open[_open.size() - 1]
	if str(top.get("name", "")) != name:
		push_error("CityProfiler: end('%s') but top is '%s'" % [name, top.get("name", "")])
	_open.pop_back()
	var dt := Time.get_ticks_usec() - int(top.get("t0", 0))
	_record_scope(str(top.get("name", name)), dt)


func scope_us(name: String, elapsed_us: int) -> void:
	_record_scope(name, elapsed_us)


func _record_scope(name: String, dt_us: int) -> void:
	var s: Dictionary
	if _scopes.has(name):
		s = _scopes[name]
	else:
		if _scopes.size() >= MAX_SCOPES:
			return
		s = {"acc_us": 0, "last_us": 0, "peak_us": 0, "count": 0}
	s["acc_us"] = int(s["acc_us"]) + dt_us
	s["last_us"] = dt_us
	s["peak_us"] = maxi(int(s["peak_us"]), dt_us)
	s["count"] = int(s["count"]) + 1
	_scopes[name] = s
	_frame_scope_us[name] = int(_frame_scope_us.get(name, 0)) + dt_us


func _process(delta: float) -> void:
	var frame_ms := delta * 1000.0
	_frame_ms_smooth = lerpf(_frame_ms_smooth, frame_ms, SMOOTH)
	if _enabled:
		_refresh_label()


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_physics_usec > 0:
		var dt_ms := float(now - _last_physics_usec) / 1000.0
		_physics_ms_smooth = lerpf(_physics_ms_smooth, dt_ms, SMOOTH)
	_last_physics_usec = now
	## Reset per-physics-frame accumulators used for overlay "this tick" column.
	_frame_scope_us.clear()


func set_controls(controls: RefCounted) -> void:
	_controls = controls


func _ctl() -> RefCounted:
	if _controls == null:
		_controls = PlayerControlsScript.new() as RefCounted
	return _controls


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if bool(_ctl().call("matches_key_pressed", event, "profiler")):
			set_overlay_enabled(not _enabled)
			get_viewport().set_input_as_handled()


func set_overlay_enabled(on: bool) -> void:
	_enabled = on
	_panel.visible = on
	if on:
		_refresh_label()


func is_overlay_enabled() -> bool:
	return _enabled


func reset_peaks() -> void:
	for k in _scopes.keys():
		var s: Dictionary = _scopes[k]
		s["peak_us"] = int(s.get("last_us", 0))
		_scopes[k] = s


func _refresh_label() -> void:
	if _body == null:
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("CityProfiler  (F7 toggle)")
	lines.append(
		"frame %.1f ms · physics interval %.1f ms"
		% [_frame_ms_smooth, _physics_ms_smooth]
	)
	lines.append(
		"debris live %d · pending %d · crowd %d · vehicles %d"
		% [
			int(_counters.get("debris_live", 0)),
			int(_counters.get("debris_pending", 0)),
			int(_counters.get("crowd_agents", 0)),
			int(_counters.get("vehicle_agents", 0)),
		]
	)
	lines.append("--- scopes (last / peak µs) ---")
	var names: Array = _scopes.keys()
	names.sort()
	for name in names:
		var s: Dictionary = _scopes[name]
		var tick_us := int(_frame_scope_us.get(name, 0))
		lines.append(
			"%s  last %d  peak %d  tick %d  n=%d"
			% [name, int(s["last_us"]), int(s["peak_us"]), tick_us, int(s["count"])]
		)
	_body.text = "\n".join(lines)


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.offset_left = 12.0
	_panel.offset_top = 12.0
	_panel.offset_right = 420.0
	_panel.offset_bottom = 320.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.1, 0.82)
	sb.border_color = Color(0.35, 0.75, 0.95, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", sb)
	root.add_child(_panel)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_OFF
	_body.add_theme_font_size_override("font_size", 13)
	_body.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_panel.add_child(_body)
