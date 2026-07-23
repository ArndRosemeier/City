## Maintains an active district bubble around the player with view-priority generation.
## District *stamping* runs on the main thread (VoxelTool is not safe to share across
## OS threads). `max_workers` is cooperative concurrency: up to N districts progress
## in interleaved awaits on that same thread. Voxel Tools still remeshes on its own pool.
class_name CityStreamer
extends Node

const DistrictInstanceScript := preload("res://scripts/city/district_instance.gd")

signal spawn_district_ready(instance: DistrictInstance)
signal status_message(text: String)
signal debug_job_started(kind: String, coord: Vector2i)
signal debug_job_finished(kind: String, coord: Vector2i)

@export var bubble_radius_m: float = 360.0
@export var unload_radius_m: float = 500.0
@export var crowd_per_district: int = 96
@export var vehicles_per_district: int = 14
@export var job_cooldown_sec: float = 0.0
## Cooperative stamp slots. Bake runs on WorkerThreadPool; main thread only commits
## blocks + scene setup. Two slots ⇒ two districts baking in parallel on OS threads.
@export var max_workers: int = 2
## Within this edge distance, bake full voxel buildings. Beyond: ground + impostors only.
@export var voxel_detail_radius_m: float = 140.0

var world_seed: int = 42
var voxel_size: float = 0.5
var player_view_m: float = 90.0

var _terrain: VoxelTerrain
var _tool: VoxelTool
var _camera: Camera3D
var _player: Node3D
var _districts: Dictionary = {}  # Vector2i -> DistrictInstance
var _boot_coord: Vector2i = Vector2i.ZERO
var _booted: bool = false
var _rescore_accum: float = 0.0
var _job_cooldown: float = 0.0

## Active stamp jobs: Vector2i -> {kind: String, started_msec: int}
var _active_jobs: Dictionary = {}

## Debug / throughput accounting.
var _jobs_finished: int = 0
var _cells_stamped_total: int = 0
var _cells_window: PackedInt32Array = PackedInt32Array()
var _cells_window_sec: int = -1
var _jobs_window: PackedInt32Array = PackedInt32Array()
var _jobs_window_sec: int = -1


func setup(
	terrain: VoxelTerrain,
	tool: VoxelTool,
	p_world_seed: int,
	p_voxel_size: float,
	p_player_view_m: float
) -> void:
	_terrain = terrain
	_tool = tool
	world_seed = p_world_seed
	voxel_size = p_voxel_size
	player_view_m = p_player_view_m
	_districts.clear()
	_active_jobs.clear()
	_booted = false


func bind_player(player: Node3D, camera: Camera3D) -> void:
	_player = player
	_camera = camera
	for key: Variant in _districts.keys():
		var inst: DistrictInstance = _districts[key]
		if inst != null and is_instance_valid(inst):
			inst.bind_camera(camera)
	_update_bubble()
	_kick_next_job()


func boot_spawn_district(coord: Vector2i = Vector2i.ZERO) -> void:
	_boot_coord = coord
	status_message.emit("Generating spawn district…")
	_request_district(coord, true)


func district_count() -> int:
	return _districts.size()


func get_district(coord: Vector2i) -> DistrictInstance:
	return _districts.get(coord) as DistrictInstance


func is_worker_busy() -> bool:
	return not _active_jobs.is_empty()


func active_worker_count() -> int:
	return _active_jobs.size()


func note_cells_stamped(count: int) -> void:
	if count <= 0:
		return
	_cells_stamped_total += count
	var sec := int(Time.get_ticks_msec() / 1000)
	if sec != _cells_window_sec:
		_cells_window_sec = sec
		_cells_window.append(0)
		if _cells_window.size() > 8:
			_cells_window = _cells_window.slice(_cells_window.size() - 8)
	if _cells_window.is_empty():
		_cells_window.append(0)
	_cells_window[_cells_window.size() - 1] = int(_cells_window[_cells_window.size() - 1]) + count


func debug_snapshot() -> Dictionary:
	var pending_ground := 0
	var pending_detail := 0
	var busy_count := 0
	var ready_count := 0
	var tiles: Array = []
	var player_pos := _player_pos()
	var player_coord := DistrictCoord.from_world(player_pos, voxel_size)
	for key: Variant in _districts.keys():
		var inst: DistrictInstance = _districts[key]
		if inst == null or not is_instance_valid(inst):
			continue
		var state := "queued"
		if inst.is_busy:
			busy_count += 1
			state = "busy"
		elif inst.is_ready:
			ready_count += 1
			state = "ready"
		elif inst.is_ground_ready:
			pending_detail += 1
			state = "ground"
		else:
			pending_ground += 1
			state = "pending"
		tiles.append(
			{
				"coord": inst.coord,
				"state": state,
				"edge_m": inst.distance_to_point(player_pos),
			}
		)
	var pending_total := pending_ground + pending_detail
	var active_n := _active_jobs.size()
	var worker := "idle"
	if active_n > 0 and pending_total > 0 and active_n < max_workers:
		worker = "underfilled"  ## slots free while queue still has work
	elif active_n > 0:
		worker = "working"
	elif pending_total > 0:
		worker = "stalled"  ## idle with queued work
	var cells_per_sec := 0.0
	if _cells_window.size() > 0:
		var sum := 0
		for v in _cells_window:
			sum += int(v)
		cells_per_sec = float(sum) / float(_cells_window.size())
	var jobs_per_min := 0.0
	if _jobs_window.size() > 0:
		var jsum := 0
		for jv in _jobs_window:
			jsum += int(jv)
		jobs_per_min = float(jsum) * (60.0 / float(_jobs_window.size()))
	var active_list: Array = []
	var now := Time.get_ticks_msec()
	for ckey: Variant in _active_jobs.keys():
		var info: Dictionary = _active_jobs[ckey]
		active_list.append(
			{
				"coord": ckey as Vector2i,
				"kind": str(info.get("kind", "")),
				"age_sec": float(now - int(info.get("started_msec", now))) * 0.001,
			}
		)
	var primary_kind := ""
	var primary_coord := Vector2i(9999, 9999)
	var primary_age := 0.0
	if not active_list.is_empty():
		primary_kind = str(active_list[0]["kind"])
		primary_coord = active_list[0]["coord"] as Vector2i
		primary_age = float(active_list[0]["age_sec"])
	return {
		"loaded": _districts.size(),
		"ready": ready_count,
		"busy": busy_count,
		"pending_ground": pending_ground,
		"pending_detail": pending_detail,
		"in_works": busy_count + pending_total,
		"worker": worker,
		"workers_max": max_workers,
		"workers_active": active_n,
		"active_jobs": active_list,
		"worker_busy_flag": active_n > 0,
		"current_kind": primary_kind,
		"current_coord": primary_coord,
		"job_age_sec": primary_age,
		"cells_per_sec": cells_per_sec,
		"jobs_per_min": jobs_per_min,
		"cells_total": _cells_stamped_total,
		"jobs_finished": _jobs_finished,
		"player_coord": player_coord,
		"player_pos": player_pos,
		"tiles": tiles,
		"voxel_size": voxel_size,
	}


func _note_job_finished(coord: Vector2i, kind: String) -> void:
	_active_jobs.erase(coord)
	_jobs_finished += 1
	var sec := int(Time.get_ticks_msec() / 1000)
	if sec != _jobs_window_sec:
		_jobs_window_sec = sec
		_jobs_window.append(0)
		if _jobs_window.size() > 8:
			_jobs_window = _jobs_window.slice(_jobs_window.size() - 8)
	if _jobs_window.is_empty():
		_jobs_window.append(0)
	_jobs_window[_jobs_window.size() - 1] = int(_jobs_window[_jobs_window.size() - 1]) + 1
	debug_job_finished.emit(kind, coord)


func _begin_tracked_job(kind: String, inst: DistrictInstance) -> void:
	_active_jobs[inst.coord] = {"kind": kind, "started_msec": Time.get_ticks_msec()}
	debug_job_started.emit(kind, inst.coord)


func _process(delta: float) -> void:
	if _terrain == null or _tool == null:
		return
	_job_cooldown = maxf(_job_cooldown - delta, 0.0)
	_rescore_accum += delta
	if _player != null and is_instance_valid(_player) and _rescore_accum >= 0.2:
		_rescore_accum = 0.0
		_update_bubble()
	if _job_cooldown <= 0.0:
		_kick_next_job()


func _update_bubble() -> void:
	var pos := _player.global_position
	var here := DistrictCoord.from_world(pos, voxel_size)
	var reach := 1
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var c := Vector2i(here.x + dx, here.y + dz)
			var edge := _edge_distance_m(c, pos)
			if edge <= bubble_radius_m:
				_request_district(c, false)

	var to_drop: Array[Vector2i] = []
	for key: Variant in _districts.keys():
		var c2: Vector2i = key
		var inst: DistrictInstance = _districts[c2]
		if inst == null or not is_instance_valid(inst):
			to_drop.append(c2)
			continue
		if inst.is_busy:
			continue
		var d2 := _edge_distance_m(c2, pos)
		if d2 > unload_radius_m:
			to_drop.append(c2)
	for c3 in to_drop:
		_unload_district(c3)


func _edge_distance_m(coord: Vector2i, pos: Vector3) -> float:
	var o := DistrictCoord.origin_world(coord, voxel_size)
	var sx := float(DistrictCoord.SIZE_X_VOX) * voxel_size
	var sz := float(DistrictCoord.SIZE_Z_VOX) * voxel_size
	var nx := clampf(pos.x, o.x, o.x + sx)
	var nz := clampf(pos.z, o.z, o.z + sz)
	return Vector2(nx - pos.x, nz - pos.z).length()


func _request_district(coord: Vector2i, is_boot: bool) -> void:
	if _districts.has(coord):
		return
	var inst: DistrictInstance = DistrictInstanceScript.new()
	inst.configure(coord, voxel_size, world_seed, crowd_per_district, vehicles_per_district, player_view_m)
	add_child(inst)
	_districts[coord] = inst
	inst.ensure_prefetch()
	inst.ground_ready.connect(_on_district_ground_ready)
	inst.ready_to_play.connect(_on_district_ready)
	inst.failed.connect(_on_district_failed)
	inst.stamp_progress.connect(_on_stamp_progress)
	if is_boot:
		_begin_tracked_job("ground", inst)
		inst.begin_ground(_terrain, _tool, _camera, "full")
		_kick_next_job()


func _player_pos() -> Vector3:
	if _player != null and is_instance_valid(_player):
		return _player.global_position
	if _camera != null and is_instance_valid(_camera):
		return _camera.global_position
	return Vector3.ZERO


func _pick_nearest(predicate: Callable) -> DistrictInstance:
	var best: DistrictInstance = null
	var best_edge := INF
	var best_center := INF
	var player_pos := _player_pos()
	for key: Variant in _districts.keys():
		var inst: DistrictInstance = _districts[key]
		if inst == null or not is_instance_valid(inst):
			continue
		if inst.is_busy:
			continue
		if not bool(predicate.call(inst)):
			continue
		var edge_dist := inst.distance_to_point(player_pos)
		var center := inst.world_aabb_center()
		var center_dist := Vector2(center.x - player_pos.x, center.z - player_pos.z).length()
		if edge_dist < best_edge - 0.01 or (absf(edge_dist - best_edge) <= 0.01 and center_dist < best_center):
			best_edge = edge_dist
			best_center = center_dist
			best = inst
	return best


func _on_stamp_progress(cells: int) -> void:
	note_cells_stamped(cells)


func _kick_next_job() -> void:
	## Fill free cooperative slots (OS bake threads + main-thread commits).
	while _active_jobs.size() < maxi(max_workers, 1):
		if not _try_start_one_job():
			break


func _try_start_one_job() -> bool:
	if _camera == null or not is_instance_valid(_camera):
		## Boot may run before camera exists — allow ground-only boot job already started.
		return false
	var player_pos := _player_pos()
	## Prefer upgrading far tiles that entered the detail radius.
	var upgrade_job := _pick_nearest(func(inst: DistrictInstance) -> bool: return inst.needs_upgrade() and inst.distance_to_point(player_pos) <= voxel_detail_radius_m)
	if upgrade_job != null:
		_begin_tracked_job("upgrade", upgrade_job)
		print(
			"CityStreamer upgrade %s edge=%.0fm workers=%d/%d"
			% [str(upgrade_job.coord), upgrade_job.distance_to_point(player_pos), _active_jobs.size(), max_workers]
		)
		upgrade_job.begin_upgrade(_terrain, _tool, _camera)
		return true
	var ground_job := _pick_nearest(func(inst: DistrictInstance) -> bool: return inst.needs_ground())
	if ground_job != null:
		var quality := "full"
		if ground_job.distance_to_point(player_pos) > voxel_detail_radius_m:
			quality = "far"
		_begin_tracked_job("ground", ground_job)
		print(
			"CityStreamer ground %s quality=%s edge=%.0fm workers=%d/%d"
			% [str(ground_job.coord), quality, ground_job.distance_to_point(player_pos), _active_jobs.size(), max_workers]
		)
		ground_job.begin_ground(_terrain, _tool, _camera, quality)
		return true
	var detail_job := _pick_nearest(func(inst: DistrictInstance) -> bool: return inst.needs_detail())
	if detail_job == null:
		return false
	_begin_tracked_job("detail", detail_job)
	print(
		"CityStreamer detail %s edge=%.0fm workers=%d/%d"
		% [str(detail_job.coord), detail_job.distance_to_point(player_pos), _active_jobs.size(), max_workers]
	)
	detail_job.begin_detail(_terrain, _tool, _camera)
	return true


func _on_district_ground_ready(inst: DistrictInstance) -> void:
	_job_cooldown = 0.0
	_note_job_finished(inst.coord, "ground")
	## Spawn district must finish detail before play.
	if not _booted and inst.coord == _boot_coord:
		_begin_tracked_job("detail", inst)
		inst.begin_detail(_terrain, _tool, _camera)
	_kick_next_job()


func _on_district_ready(inst: DistrictInstance) -> void:
	if not inst.from_stream_cache:
		_job_cooldown = job_cooldown_sec
		var kind := "detail"
		if str(inst.bake_quality) == "far":
			kind = "far"
		_note_job_finished(inst.coord, kind)
	if not _booted and inst.coord == _boot_coord:
		_booted = true
		spawn_district_ready.emit(inst)
	_kick_next_job()


func _on_district_failed(inst: DistrictInstance, reason: String) -> void:
	_job_cooldown = job_cooldown_sec
	_active_jobs.erase(inst.coord)
	push_error("CityStreamer: district %s failed: %s" % [str(inst.coord), reason])
	_districts.erase(inst.coord)
	if is_instance_valid(inst):
		inst.queue_free()
	_kick_next_job()


func _unload_district(coord: Vector2i) -> void:
	if not _districts.has(coord):
		return
	var inst: DistrictInstance = _districts[coord]
	_districts.erase(coord)
	_active_jobs.erase(coord)
	print("CityStreamer unload %s" % str(coord))
	if inst != null and is_instance_valid(inst):
		inst.destroy_and_clear(_tool)


func clear_all() -> void:
	var keys: Array = _districts.keys()
	for key: Variant in keys:
		_unload_district(key as Vector2i)
	_active_jobs.clear()
	_booted = false
