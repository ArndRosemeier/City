## Autoload: reusable runtime profiler for Eccentri City hot paths.
## Toggle overlay with F7 (rebindable). Detects frame hitches and attributes scopes.
## Also registers Performance custom monitors.
extends CanvasLayer

const PlayerControlsScript := preload("res://scripts/city/player_controls.gd")
## By path for the same reason as PlayerControls above: autoloads must not need the global
## class cache to parse.
const UiLayersScript := preload("res://scripts/city/ui_layers.gd")

const MAX_SCOPES := 128
const SMOOTH := 0.18
## Hitch reports are mirrored here when logging is enabled in Settings.
const LOG_PATH := "user://city_hitches.log"
## CitySettingsPanel.CONFIG_PATH — read at boot for the `hitch_log` flag.
const SETTINGS_PATH := "user://city_graphics.cfg"
## Frames longer than this are logged as hitches (ms). 80 ≈ drops below 12 FPS.
const HITCH_MS := 80.0
const HITCH_LOG_MAX := 24
## How many recent hitches the overlay keeps visible.
const HITCH_OVERLAY_SHOW := 8
## VoxelTerrain.get_statistics() timing keys, in pipeline order.
const VOXEL_STAGES: Array[String] = [
	"time_detect_required_blocks",
	"time_request_blocks_to_load",
	"time_process_load_responses",
	"time_request_blocks_to_update",
	"time_process_update_responses",
]
## Streamer/commit backpressure: pause feeding VoxelTools when the remesh queue grows.
## Soft → serialize cooperative workers to 1. Hard → pause new jobs and commit slices.
const REMESH_BACKLOG_SOFT := 8
const REMESH_BACKLOG_HARD := 16
## Mesh-response stage time (µs) from the previous VoxelTerrain stats sample.
const REMESH_MESH_RESP_SOFT_US := 8000
const REMESH_MESH_RESP_HARD_US := 16000

var _enabled: bool = false
var _panel: PanelContainer
var _body: Label
var _scopes: Dictionary = {}  ## name -> {acc_us, last_us, peak_us, count}
var _counters: Dictionary = {}  ## name -> int
## Scopes accumulated since the previous _process (the interval `delta` measures).
var _interval_scope_us: Dictionary = {}
## Calls per scope in that same interval — "350 ms over 3 calls" reads very differently
## from "350 ms in one call".
var _interval_scope_calls: Dictionary = {}
var _open: Array = []  ## stack of {name, t0_us}
var _frame_ms_smooth: float = 0.0
var _physics_ms_smooth: float = 0.0
var _last_physics_usec: int = 0
var _controls: PlayerControls
var _hitch_log: Array = []  ## newest last: {ms, at_msec, scopes: Dictionary, accounted_ms, note}
var _hitch_count: int = 0
var _worst_hitch_ms: float = 0.0
var _hitch_threshold_ms: float = HITCH_MS
## Frame split, all from one clock: this autoload runs first in the process pass, the probe
## below runs last, so we can separate node processing from physics and from everything else.
var _probe: FrameEndProbe
var _t_process_begin_us: int = 0
var _t_process_end_us: int = 0
var _inside_process_ms: float = 0.0
var _outside_ms: float = 0.0
var _t_physics_begin_us: int = 0
var _physics_gap_us: int = 0
var _physics_in_frame_ms: float = 0.0
## Wall time between consecutive process passes — the trustworthy frame measure.
var _wall_frame_ms: float = 0.0
var _worst_frame_ms: float = 0.0
## What `_process(delta)` claimed, kept only to expose the discrepancy.
var _delta_frame_ms: float = 0.0
var _node_count: int = 0
var _object_count: int = 0
var _prev_node_count: int = 0
var _prev_object_count: int = 0
## VoxelTerrain.get_statistics() of the previous frame — main-thread voxel work lives here.
var _terrain: Node = null
var _voxel_stats: Dictionary = {}
## Worst value seen per VoxelTerrain stage this session (µs) — survives quiet frames.
var _voxel_peak_us: Dictionary = {}
## Rare structural events (viewer added/removed, …) -> ticks_msec, for hitch correlation.
var _events: Dictionary = {}
## Open timestamps for bracketed native nodes: label -> ticks_usec.
var _bracket_t0_us: Dictionary = {}
var _log_file: FileAccess = null
var _log_context_written: bool = false
var _scope_overflow_reported: bool = false


## Runs after every other node in both passes, closing the window this autoload opens.
class FrameEndProbe:
	extends Node

	var profiler: Node

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = 1000
		process_physics_priority = 1000

	func _process(_delta: float) -> void:
		profiler.call("_close_process_pass")

	func _physics_process(_delta: float) -> void:
		profiler.call("_close_physics_step")


## Times a single node's `_process` by sandwiching it between two priorities. Native nodes
## (VoxelTerrain) can't be wrapped with begin/end from script, so we bracket them by order.
class ScopeProbe:
	extends Node

	var profiler: Node
	var label: String
	var opens: bool
	var priority: int

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = priority

	func _process(_delta: float) -> void:
		if opens:
			profiler.call("_bracket_begin", label)
		else:
			profiler.call("_bracket_end", label)


func _ready() -> void:
	layer = UiLayersScript.DEBUG_PROFILER
	process_mode = Node.PROCESS_MODE_ALWAYS
	## Lowest priority = first in the pass, so our timestamp precedes all scene nodes.
	process_priority = -1000
	process_physics_priority = -1000
	_probe = FrameEndProbe.new()
	_probe.name = "FrameEndProbe"
	_probe.profiler = self
	add_child(_probe)
	_build_ui()
	_panel.visible = false
	_register_monitors()
	## Read the setting ourselves instead of waiting for the settings panel: boot hitches
	## happen before the first settings_applied and were missing from the log.
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK and bool(cfg.get_value("graphics", "hitch_log", false)):
		set_file_logging(true)


func _close_process_pass() -> void:
	_t_process_end_us = Time.get_ticks_usec()
	_inside_process_ms = float(_t_process_end_us - _t_process_begin_us) / 1000.0


func _close_physics_step() -> void:
	_physics_gap_us += Time.get_ticks_usec() - _t_physics_begin_us


func _register_monitors() -> void:
	Performance.add_custom_monitor(&"city/frame_ms", Callable(self, "_mon_frame_ms"))
	Performance.add_custom_monitor(&"city/physics_ms", Callable(self, "_mon_physics_ms"))
	Performance.add_custom_monitor(&"city/debris_live", Callable(self, "_mon_debris_live"))
	Performance.add_custom_monitor(&"city/debris_pending", Callable(self, "_mon_debris_pending"))
	Performance.add_custom_monitor(&"city/crowd_agents", Callable(self, "_mon_crowd_agents"))
	Performance.add_custom_monitor(&"city/scope_cascade_us", Callable(self, "_mon_scope_cascade"))
	Performance.add_custom_monitor(&"city/scope_crowd_us", Callable(self, "_mon_scope_crowd"))
	Performance.add_custom_monitor(&"city/hitch_count", Callable(self, "_mon_hitch_count"))
	Performance.add_custom_monitor(&"city/worst_hitch_ms", Callable(self, "_mon_worst_hitch"))
	Performance.add_custom_monitor(&"city/voxel_main_blocks", Callable(self, "_mon_voxel_main_blocks"))


## The terrain reports how much main-thread voxel work is queued each frame.
func set_terrain(terrain: Node) -> void:
	_terrain = terrain
	bracket_node(terrain, "voxel_terrain_process")


## Gives `node` a unique process priority and brackets it, so its own `_process` cost lands
## in the scope table under `label`.
func bracket_node(node: Node, label: String, priority: int = 500) -> void:
	node.process_priority = priority
	_add_scope_probe(label, true, priority - 1)
	_add_scope_probe(label, false, priority + 1)


func _add_scope_probe(label: String, opens: bool, priority: int) -> void:
	var probe := ScopeProbe.new()
	probe.name = "%s_%s" % [label, "open" if opens else "close"]
	probe.profiler = self
	probe.label = label
	probe.opens = opens
	probe.priority = priority
	add_child(probe)


func _bracket_begin(label: String) -> void:
	_bracket_t0_us[label] = Time.get_ticks_usec()


func _bracket_end(label: String) -> void:
	if not _bracket_t0_us.has(label):
		return
	_record_scope(label, Time.get_ticks_usec() - int(_bracket_t0_us[label]))


func _mon_voxel_main_blocks() -> float:
	return float(voxel_main_thread_blocks())


## Blocks VoxelTools still wants to apply on the main thread (mesh/collision).
func voxel_main_thread_blocks() -> int:
	return int(_voxel_stats.get("remaining_main_thread_blocks", 0))


func voxel_mesh_resp_us() -> int:
	return int(_voxel_stats.get("time_process_update_responses", 0))


## 0 = clear, 1 = soft (serialize stream workers), 2 = hard (pause commits + new jobs).
func remesh_pressure() -> int:
	var blocks := voxel_main_thread_blocks()
	var mesh_us := voxel_mesh_resp_us()
	if blocks >= REMESH_BACKLOG_HARD or mesh_us >= REMESH_MESH_RESP_HARD_US:
		return 2
	if blocks >= REMESH_BACKLOG_SOFT or mesh_us >= REMESH_MESH_RESP_SOFT_US:
		return 1
	return 0


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


func _mon_hitch_count() -> float:
	return float(_hitch_count)


func _mon_worst_hitch() -> float:
	return _worst_hitch_ms


func _scope_last_us(name: String) -> int:
	var s: Variant = _scopes.get(name)
	if s == null:
		return 0
	return int((s as Dictionary).get("last_us", 0))


func set_hitch_threshold_ms(ms: float) -> void:
	_hitch_threshold_ms = maxf(ms, 16.0)


func hitch_threshold_ms() -> float:
	return _hitch_threshold_ms


func set_counter(name: String, value: int) -> void:
	_counters[name] = value


func add_counter(name: String, delta: int = 1) -> void:
	_counters[name] = int(_counters.get(name, 0)) + delta


## Timestamps a structural event so hitch reports can name what happened just before.
func note_event(name: String) -> void:
	_events[name] = Time.get_ticks_msec()


## Mirrors every hitch report into `LOG_PATH`. `context` is written into the header once,
## so a shared log says which quality settings produced it.
func set_file_logging(on: bool, context: Dictionary = {}) -> void:
	if on == (_log_file != null):
		## Boot-time enable has no settings yet; write them when they first arrive.
		if on and not _log_context_written and not context.is_empty():
			_log_context_written = true
			_log_file.store_line("settings %s" % str(context))
			_log_file.flush()
		return
	if not on:
		_emit("CityProfiler logging stopped")
		_log_file.close()
		_log_file = null
		_log_context_written = false
		return
	var file := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file == null:
		push_error(
			"CityProfiler: cannot write %s (%s)"
			% [log_file_path(), error_string(FileAccess.get_open_error())]
		)
		return
	_log_file = file
	_log_file.store_line("EccentriCity hitch log — %s" % Time.get_datetime_string_from_system())
	_log_file.store_line(
		"engine %s · %s · %d cpus · hitch threshold %.0f ms"
		% [
			Engine.get_version_info().get("string", "?"),
			RenderingServer.get_video_adapter_name(),
			OS.get_processor_count(),
			_hitch_threshold_ms,
		]
	)
	if not context.is_empty():
		_log_context_written = true
		_log_file.store_line("settings %s" % str(context))
	_log_file.store_line("")
	_log_file.flush()
	print("CityProfiler logging hitches to %s" % log_file_path())


func is_file_logging() -> bool:
	return _log_file != null


func log_file_path() -> String:
	return ProjectSettings.globalize_path(LOG_PATH)


## Console always, file when enabled. Flushed per line so a crash keeps what we saw.
func _emit(line: String) -> void:
	print(line)
	if _log_file != null:
		_log_file.store_line(line)
		_log_file.flush()


func begin(name: String) -> void:
	## children_us = wall time of nested scopes (so parent records exclusive time only).
	_open.append({"name": name, "t0": Time.get_ticks_usec(), "children_us": 0})


func end(name: String) -> void:
	if _open.is_empty():
		push_error("CityProfiler: end('%s') with empty scope stack" % name)
		return
	var top: Dictionary = _open[_open.size() - 1]
	if str(top.get("name", "")) != name:
		push_error("CityProfiler: end('%s') but top is '%s'" % [name, top.get("name", "")])
	_open.pop_back()
	var wall_us := Time.get_ticks_usec() - int(top.get("t0", 0))
	var exclusive_us := maxi(wall_us - int(top.get("children_us", 0)), 0)
	_record_scope(str(top.get("name", name)), exclusive_us)
	## Attribute full child wall time to the parent so parent's exclusive excludes us.
	if not _open.is_empty():
		var parent: Dictionary = _open[_open.size() - 1]
		parent["children_us"] = int(parent.get("children_us", 0)) + wall_us
		_open[_open.size() - 1] = parent


func scope_us(name: String, elapsed_us: int) -> void:
	_record_scope(name, elapsed_us)


func _record_scope(name: String, dt_us: int) -> void:
	var s: Dictionary
	if _scopes.has(name):
		s = _scopes[name]
	else:
		if _scopes.size() >= MAX_SCOPES:
			## Dropping a scope silently would hide the very cost we are hunting.
			if not _scope_overflow_reported:
				_scope_overflow_reported = true
				push_error(
					"CityProfiler: scope table full (%d), '%s' and later scopes are not measured"
					% [MAX_SCOPES, name]
				)
			return
		s = {"acc_us": 0, "last_us": 0, "peak_us": 0, "count": 0}
	s["acc_us"] = int(s["acc_us"]) + dt_us
	s["last_us"] = dt_us
	s["peak_us"] = maxi(int(s["peak_us"]), dt_us)
	s["count"] = int(s["count"]) + 1
	_scopes[name] = s
	_interval_scope_us[name] = int(_interval_scope_us.get(name, 0)) + dt_us
	_interval_scope_calls[name] = int(_interval_scope_calls.get(name, 0)) + 1


func _process(delta: float) -> void:
	_delta_frame_ms = delta * 1000.0
	## Measure frames with the monotonic clock, not `delta`: headless runs report a `delta`
	## several times larger than the real gap between process passes.
	var t_now := Time.get_ticks_usec()
	var first_frame := _t_process_begin_us == 0
	if not first_frame:
		_wall_frame_ms = float(t_now - _t_process_begin_us) / 1000.0
	if _t_process_end_us > 0:
		_outside_ms = float(t_now - _t_process_end_us) / 1000.0
	_physics_in_frame_ms = float(_physics_gap_us) / 1000.0
	_physics_gap_us = 0
	_t_process_begin_us = t_now
	_frame_ms_smooth = lerpf(_frame_ms_smooth, _wall_frame_ms, SMOOTH)
	_worst_frame_ms = maxf(_worst_frame_ms, _wall_frame_ms)
	_sample_engine_state()
	if not first_frame and _wall_frame_ms >= _hitch_threshold_ms:
		_record_hitch(_wall_frame_ms)
	## Start a fresh attribution window for the upcoming interval.
	_interval_scope_us.clear()
	_interval_scope_calls.clear()
	_prev_node_count = _node_count
	_prev_object_count = _object_count
	if _enabled:
		_refresh_label()


func _sample_engine_state() -> void:
	_node_count = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_object_count = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	if _terrain != null and is_instance_valid(_terrain):
		_voxel_stats = _terrain.call("get_statistics") as Dictionary
		for stage: String in VOXEL_STAGES:
			var v := int(_voxel_stats.get(stage, 0))
			if v > int(_voxel_peak_us.get(stage, 0)):
				_voxel_peak_us[stage] = v


func _physics_process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	_t_physics_begin_us = now
	if _last_physics_usec > 0:
		var dt_ms := float(now - _last_physics_usec) / 1000.0
		_physics_ms_smooth = lerpf(_physics_ms_smooth, dt_ms, SMOOTH)
	_last_physics_usec = now


func _record_hitch(frame_ms: float) -> void:
	_hitch_count += 1
	_worst_hitch_ms = maxf(_worst_hitch_ms, frame_ms)
	var snap: Dictionary = _interval_scope_us.duplicate()
	var calls: Dictionary = _interval_scope_calls.duplicate()
	## Still-open scopes: exclusive wall so far (exclude nested children already in snap).
	for entry: Variant in _open:
		var e: Dictionary = entry
		var n := str(e.get("name", "?"))
		var live := Time.get_ticks_usec() - int(e.get("t0", 0))
		var exclusive_live := maxi(live - int(e.get("children_us", 0)), 0)
		snap[n] = int(snap.get(n, 0)) + exclusive_live
		calls[n] = int(calls.get(n, 0)) + 1
	var accounted_us := 0
	for k: Variant in snap.keys():
		accounted_us += int(snap[k])
	var accounted_ms := float(accounted_us) / 1000.0
	var unaccounted_ms := maxf(frame_ms - accounted_ms, 0.0)
	var note := ""
	if unaccounted_ms >= frame_ms * 0.5 and unaccounted_ms >= 40.0:
		note = "mostly outside profiled GDScript (VoxelTools remesh/collision, GPU sync, or unwrapped native)"
	elif not _open.is_empty():
		var open_names: PackedStringArray = PackedStringArray()
		for entry2: Variant in _open:
			open_names.append(str((entry2 as Dictionary).get("name", "?")))
		note = "open scopes: " + ", ".join(open_names)

	var ranked: Array = snap.keys()
	ranked.sort_custom(func(a: Variant, b: Variant) -> bool: return int(snap[a]) > int(snap[b]))
	var top_parts: PackedStringArray = PackedStringArray()
	for i in mini(ranked.size(), 6):
		var nm: String = str(ranked[i])
		top_parts.append(
			"%s=%.1fms x%d" % [nm, float(int(snap[nm])) / 1000.0, int(calls.get(nm, 0))]
		)

	var line := (
		"CityProfiler HITCH #%d  %.0f ms  accounted %.0f ms  unaccounted %.0f ms"
		% [_hitch_count, frame_ms, accounted_ms, unaccounted_ms]
	)
	if top_parts.size() > 0:
		line += "  |  " + ", ".join(top_parts)
	if note != "":
		line += "  |  " + note
	_emit(line)
	_print_hitch_detail(frame_ms)

	_hitch_log.append({
		"ms": frame_ms,
		"at_msec": Time.get_ticks_msec(),
		"scopes": snap,
		"accounted_ms": accounted_ms,
		"unaccounted_ms": unaccounted_ms,
		"note": note,
		"counters": _counters.duplicate(),
	})
	while _hitch_log.size() > HITCH_LOG_MAX:
		_hitch_log.pop_front()
	## Include streamer job context when commits/remeshes are the likely culprit.
	var jobs := int(_counters.get("streamer_jobs", 0))
	var phase := int(_counters.get("stream_phase", 0))
	var blocks_left := int(_counters.get("stream_blocks_left", 0))
	var backpressure := int(_counters.get("remesh_backpressure", 0))
	if (jobs > 0 or phase > 0 or backpressure > 0) and unaccounted_ms >= 40.0:
		var phase_names: Dictionary = {
			0: "idle",
			1: "ground_bake",
			2: "ground_commit",
			3: "detail_commit",
			4: "detail_populate",
		}
		var phase_name: String = str(phase_names.get(phase, str(phase)))
		_emit(
			(
				"  CityProfiler HITCH context: streamer_jobs=%d phase=%s blocks_left=%d"
				+ " remesh_backpressure=%d voxel_main_blocks=%d (commit/remesh likely)"
			)
			% [jobs, phase_name, blocks_left, backpressure, voxel_main_thread_blocks()]
		)


## Splits a hitch into "main thread was busy" vs "main thread was stalled/starved", then
## names the voxel stage if the terrain was the busy one.
func _print_hitch_detail(frame_ms: float) -> void:
	var other_ms := maxf(_outside_ms - _physics_in_frame_ms, 0.0)
	_emit(
		(
			"  frame split: node _process %.1f ms + physics %.1f ms + other %.1f ms"
			+ "  (frame %.1f ms, delta claimed %.1f ms)  |  nodes %+d · objects %+d · cpus %d"
		)
		% [
			_inside_process_ms,
			_physics_in_frame_ms,
			other_ms,
			frame_ms,
			_delta_frame_ms,
			_node_count - _prev_node_count,
			_object_count - _prev_object_count,
			OS.get_processor_count(),
		]
	)
	_emit(
		"  jobs: district bakes %d · streamer jobs %d · stream phase %d · blocks left %d"
		% [
			int(_counters.get("bake_tasks", 0)),
			int(_counters.get("streamer_jobs", 0)),
			int(_counters.get("stream_phase", 0)),
			int(_counters.get("stream_blocks_left", 0)),
		]
	)
	if not _voxel_stats.is_empty():
		_emit(
			(
				"  voxel: main-thread blocks left %d · detect %d µs · load req %d µs"
				+ " · load resp %d µs · mesh req %d µs · mesh resp %d µs"
				+ " · updated %d · dropped loads %d · dropped meshes %d"
			)
			% [
				int(_voxel_stats.get("remaining_main_thread_blocks", 0)),
				int(_voxel_stats.get("time_detect_required_blocks", 0)),
				int(_voxel_stats.get("time_request_blocks_to_load", 0)),
				int(_voxel_stats.get("time_process_load_responses", 0)),
				int(_voxel_stats.get("time_request_blocks_to_update", 0)),
				int(_voxel_stats.get("time_process_update_responses", 0)),
				int(_voxel_stats.get("updated_blocks", 0)),
				int(_voxel_stats.get("dropped_block_loads", 0)),
				int(_voxel_stats.get("dropped_block_meshs", 0)),
			]
		)
	var recent: PackedStringArray = PackedStringArray()
	var now := Time.get_ticks_msec()
	for key: Variant in _events.keys():
		var age := now - int(_events[key])
		if age <= 2000:
			recent.append("%s %d ms ago" % [str(key), age])
	if recent.size() > 0:
		_emit("  recent events: " + ", ".join(recent))
	var verdict := ""
	if _inside_process_ms >= frame_ms * 0.5:
		verdict = "inside node _process — see scopes and voxel stage times above"
	elif _physics_in_frame_ms >= frame_ms * 0.3:
		verdict = "inside physics steps — bodies, movers or physics queries"
	elif other_ms >= frame_ms * 0.5:
		verdict = (
			"outside every node callback — renderer submit / GPU wait, synchronous resource"
			+ " loading, or main-thread starvation while worker threads saturate the CPU"
		)
	else:
		verdict = "spread across node processing, physics and engine work"
	_emit("  verdict: " + verdict)


## One comparable line per run — peaks survive frames that never crossed the hitch threshold.
func _exit_tree() -> void:
	var parts: PackedStringArray = PackedStringArray()
	for stage: String in VOXEL_STAGES:
		parts.append(
			"%s %.1f ms" % [stage.trim_prefix("time_"), float(int(_voxel_peak_us.get(stage, 0))) / 1000.0]
		)
	_emit(
		"CityProfiler SUMMARY  hitches %d · worst hitch %.0f ms · worst frame %.0f ms  |  voxel peaks: %s"
		% [_hitch_count, _worst_hitch_ms, _worst_frame_ms, ", ".join(parts)]
	)
	if _log_file != null:
		_log_file.close()
		_log_file = null


func recent_hitches() -> Array:
	return _hitch_log.duplicate()


func set_controls(controls: PlayerControls) -> void:
	_controls = controls


func _ctl() -> PlayerControls:
	if _controls == null:
		_controls = PlayerControlsScript.new() as PlayerControls
	return _controls


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if _ctl().matches_key_pressed(key, "profiler"):
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
	_worst_hitch_ms = 0.0


## Smooth wall-clock frame time in ms (same value the F7 overlay shows).
func smooth_frame_ms() -> float:
	return _frame_ms_smooth


func worst_frame_ms() -> float:
	return _worst_frame_ms


func hitch_count() -> int:
	return _hitch_count


## Peak exclusive time for a begin/end scope, in milliseconds.
func scope_peak_ms(scope_name: String) -> float:
	if not _scopes.has(scope_name):
		return 0.0
	var s: Dictionary = _scopes[scope_name]
	return float(int(s.get("peak_us", 0))) / 1000.0


## Last exclusive sample for a scope, in milliseconds.
func scope_last_ms(scope_name: String) -> float:
	if not _scopes.has(scope_name):
		return 0.0
	var s: Dictionary = _scopes[scope_name]
	return float(int(s.get("last_us", 0))) / 1000.0


## Print peaks for the named scopes (used by the --auto-summon probe).
func print_scope_report(scope_names: PackedStringArray) -> void:
	_emit(
		"CityProfiler REPORT  frame_smooth=%.1fms worst_frame=%.1fms hitches=%d"
		% [_frame_ms_smooth, _worst_frame_ms, _hitch_count]
	)
	for scope_name: String in scope_names:
		if not _scopes.has(scope_name):
			_emit("  %s  (no samples)" % scope_name)
			continue
		var s: Dictionary = _scopes[scope_name]
		_emit(
			"  %s  last=%.2fms peak=%.2fms n=%d"
			% [
				scope_name,
				float(int(s.get("last_us", 0))) / 1000.0,
				float(int(s.get("peak_us", 0))) / 1000.0,
				int(s.get("count", 0)),
			]
		)


func clear_hitches() -> void:
	_hitch_log.clear()
	_hitch_count = 0
	_worst_hitch_ms = 0.0


func _refresh_label() -> void:
	if _body == null:
		return
	var lines: PackedStringArray = PackedStringArray()
	lines.append("CityProfiler  (F7 toggle)  hitch≥%.0fms" % _hitch_threshold_ms)
	lines.append(
		"frame %.1f ms · physics interval %.1f ms · hitches %d · worst %.0f ms"
		% [_frame_ms_smooth, _physics_ms_smooth, _hitch_count, _worst_hitch_ms]
	)
	lines.append(
		(
			"debris live %d · pending %d · crowd %d · vehicles %d · streamer jobs %d"
			+ " · stream phase %d · blocks left %d · remesh bp %d · voxel main %d"
		)
		% [
			int(_counters.get("debris_live", 0)),
			int(_counters.get("debris_pending", 0)),
			int(_counters.get("crowd_agents", 0)),
			int(_counters.get("vehicle_agents", 0)),
			int(_counters.get("streamer_jobs", 0)),
			int(_counters.get("stream_phase", 0)),
			int(_counters.get("stream_blocks_left", 0)),
			int(_counters.get("remesh_backpressure", 0)),
			voxel_main_thread_blocks(),
		]
	)
	if _hitch_log.size() > 0:
		lines.append("--- recent hitches (newest last) ---")
		var start := maxi(_hitch_log.size() - HITCH_OVERLAY_SHOW, 0)
		for i in range(start, _hitch_log.size()):
			var h: Dictionary = _hitch_log[i]
			var scopes: Dictionary = h.get("scopes", {})
			var ranked2: Array = scopes.keys()
			ranked2.sort_custom(
				func(a: Variant, b: Variant) -> bool: return int(scopes[a]) > int(scopes[b])
			)
			var bits: PackedStringArray = PackedStringArray()
			for j in mini(ranked2.size(), 3):
				bits.append(
					"%s %.0f"
					% [str(ranked2[j]), float(int(scopes[ranked2[j]])) / 1000.0]
				)
			var top := ", ".join(bits) if bits.size() > 0 else "(no scopes)"
			lines.append(
				"#%d  %.0fms  acct %.0f  gap %.0f  %s"
				% [
					i + 1,
					float(h.get("ms", 0.0)),
					float(h.get("accounted_ms", 0.0)),
					float(h.get("unaccounted_ms", 0.0)),
					top,
				]
			)
			var nnote := str(h.get("note", ""))
			if nnote != "":
				lines.append("    %s" % nnote)
	lines.append("--- scopes (last / peak µs) ---")
	var names: Array = _scopes.keys()
	names.sort()
	for name in names:
		var s: Dictionary = _scopes[name]
		var tick_us := int(_interval_scope_us.get(name, 0))
		lines.append(
			"%s  last %d  peak %d  tick %d  n=%d"
			% [name, int(s["last_us"]), int(s["peak_us"]), tick_us, int(s["count"])]
		)
	_body.text = "\n".join(lines)
	## Grow panel with hitch log.
	_panel.offset_right = 520.0
	_panel.offset_bottom = 12.0 + float(_body.get_minimum_size().y) + 24.0


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.offset_left = 12.0
	_panel.offset_top = 12.0
	_panel.offset_right = 520.0
	_panel.offset_bottom = 360.0
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
