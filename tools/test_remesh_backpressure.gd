## Verifies remesh-pressure thresholds and that the streamer/crowd knobs the hitch plan
## landed are wired the way CityProfiler / CityStreamer / CrowdDirector expect.
##
## Run: powershell -File tools\run_test.ps1 test_remesh_backpressure
extends Node

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_check_pressure_levels()
	_check_streamer_slots()
	_check_crowd_defaults()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _check_pressure_levels() -> void:
	var profiler := get_tree().root.get_node_or_null("CityProfiler")
	if profiler == null:
		_fail("FAIL no CityProfiler autoload")
		return
	profiler._voxel_stats = {
		"remaining_main_thread_blocks": 0,
		"time_process_update_responses": 0,
	}
	if int(profiler.remesh_pressure()) != 0:
		_fail("FAIL remesh_pressure expected 0 when clear, got %d" % int(profiler.remesh_pressure()))
	profiler._voxel_stats = {
		"remaining_main_thread_blocks": 8,
		"time_process_update_responses": 0,
	}
	if int(profiler.remesh_pressure()) != 1:
		_fail("FAIL remesh_pressure expected 1 at soft backlog, got %d" % int(profiler.remesh_pressure()))
	profiler._voxel_stats = {
		"remaining_main_thread_blocks": 0,
		"time_process_update_responses": 9000,
	}
	if int(profiler.remesh_pressure()) != 1:
		_fail("FAIL remesh_pressure expected 1 at soft mesh-resp, got %d" % int(profiler.remesh_pressure()))
	profiler._voxel_stats = {
		"remaining_main_thread_blocks": 16,
		"time_process_update_responses": 0,
	}
	if int(profiler.remesh_pressure()) != 2:
		_fail("FAIL remesh_pressure expected 2 at hard backlog, got %d" % int(profiler.remesh_pressure()))
	profiler._voxel_stats = {
		"remaining_main_thread_blocks": 0,
		"time_process_update_responses": 20000,
	}
	if int(profiler.remesh_pressure()) != 2:
		_fail("FAIL remesh_pressure expected 2 at hard mesh-resp, got %d" % int(profiler.remesh_pressure()))
	profiler._voxel_stats = {}


func _check_streamer_slots() -> void:
	var streamer: CityStreamer = CityStreamer.new()
	streamer.name = "TestStreamer"
	add_child(streamer)
	var profiler := get_tree().root.get_node_or_null("CityProfiler")
	profiler._voxel_stats = {
		"remaining_main_thread_blocks": 0,
		"time_process_update_responses": 0,
	}
	streamer.max_workers = 2
	if int(streamer._effective_max_workers()) != 2:
		_fail(
			"FAIL effective workers expected 2 when clear, got %d"
			% int(streamer._effective_max_workers())
		)
	profiler._voxel_stats = {
		"remaining_main_thread_blocks": 10,
		"time_process_update_responses": 0,
	}
	if int(streamer._effective_max_workers()) != 1:
		_fail(
			"FAIL effective workers expected 1 under soft pressure, got %d"
			% int(streamer._effective_max_workers())
		)
	profiler._voxel_stats = {}
	streamer.queue_free()


func _check_crowd_defaults() -> void:
	var crowd: CrowdDirector = CrowdDirector.new()
	if int(crowd.far_tick_stride) < 6:
		_fail("FAIL far_tick_stride expected >= 6, got %d" % int(crowd.far_tick_stride))
	if float(crowd.sim_budget_ms) <= 0.0:
		_fail("FAIL sim_budget_ms must be positive, got %s" % str(crowd.sim_budget_ms))
	crowd.free()
