## Budgeted single-tip infection tendrils. Visual threat only (v1).
## Each tendril has one INFECTION_LEAD; killing the lead reverts the whole lineage.
class_name InfectionDirector
extends Node

signal tendril_killed(tendril_id: int)
signal tendril_spawned(tendril_id: int)
## Any removal path (tip-kill, inert retire, stream unload).
signal tendril_ended(tendril_id: int)
signal player_score_changed(score: int)

@export var tick_interval_sec: float = 0.12
@export var max_tendrils: int = 10
## Soft preference for steps that move farther from the seed.
@export var expand_prefer_chance: float = 0.25
## Mild pull toward the current general heading (kept low so shuffle jiggle wins).
@export var heading_soft: float = 0.28
## Extra random weight on each candidate (higher = more jiggle).
@export var pick_jiggle: float = 2.4
## Max steps before a tendril re-rolls its general heading (actual = rnd * this).
@export var heading_reaim_max_steps: int = 100
const TENDRIL_START_VALUE: int = 1000

const _NEIGHBORS: Array[Vector3i] = [
	Vector3i(1, 0, 0),
	Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0),
	Vector3i(0, -1, 0),
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1),
]
const _NO_VOX := Vector3i(2147483647, 0, 0)

var _terrain: VoxelTerrain
var _tool: VoxelTool
var _voxel_size: float = 0.5
var _next_id: int = 1
var _rng := RandomNumberGenerator.new()
## tendril_id → Dictionary
var _tendrils: Dictionary = {}
## Vector3i → tendril_id (for lead lookup)
var _lead_at: Dictionary = {}
## Spawn order (HUD + stable iteration).
var _rr_ids: Array[int] = []
var player_score: int = 0


func setup(terrain: VoxelTerrain, tool: VoxelTool, voxel_size: float) -> void:
	_terrain = terrain
	_tool = tool
	_voxel_size = voxel_size
	_rng.randomize()


func clear_all() -> void:
	var tids: Array = _tendrils.keys()
	for tid in tids:
		_stop_tendril_sfx(int(tid))
	_tendrils.clear()
	_lead_at.clear()
	_rr_ids.clear()
	var audio := _city_audio()
	if audio != null and audio.has_method("stop_all_tendril_voices"):
		audio.call("stop_all_tendril_voices")


func get_player_score() -> int:
	return player_score


func reset_player_score() -> void:
	player_score = 0
	player_score_changed.emit(player_score)


func active_tendril_count() -> int:
	return _tendrils.size()


## Snapshot for HUD: ordered rows of {id, value} (remaining tip value).
func get_tendril_hud_rows() -> Array:
	var rows: Array = []
	for tid in _rr_ids:
		if not _tendrils.has(tid):
			continue
		var t: Dictionary = _tendrils[tid]
		var value := int(t.get("value", 0))
		rows.append({"id": int(tid), "value": value, "depleted": value <= 0})
	return rows


## Seed a new tendril. prev_mat is restored if the lead is killed.
## heading: general crawl direction (away from impact); empty → random.
## force: skip soft rejection (meteor seeds always plant when capacity allows).
func spawn_tendril_at_vox(
	vox: Vector3i, prev_mat: int = -1, heading: Vector3 = Vector3.ZERO, force: bool = false
) -> int:
	if _tool == null:
		return -1
	if _tendrils.size() >= max_tendrils:
		return -1
	## Don't double-bind the same lead cell to two tendrils.
	if _lead_at.has(vox):
		return -1
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var current := int(_tool.get_voxel(vox))
	var stored_prev := prev_mat
	if stored_prev < 0:
		if current == VoxelMaterial.INFECTION_LEAD or current == VoxelMaterial.INFECTION:
			stored_prev = VoxelMaterial.METEOR_ROCK
		else:
			stored_prev = current
	if not force:
		if (
			current != VoxelMaterial.INFECTION_LEAD
			and current != VoxelMaterial.AIR
			and not VoxelMaterial.is_infectable(current)
			and current != VoxelMaterial.METEOR_ROCK
		):
			if not VoxelMaterial.is_destructible(current):
				return -1
	elif current == VoxelMaterial.BEDROCK or current == VoxelMaterial.WATER:
		return -1

	var tid := _next_id
	_next_id += 1
	var cells: Dictionary = {}
	cells[vox] = {"prev_mat": stored_prev, "parent": _NO_VOX}
	_set_voxel(vox, VoxelMaterial.INFECTION_LEAD)
	_tendrils[tid] = {
		"id": tid,
		"lead": vox,
		"origin": vox,
		"cells": cells,
		"alive": true,
		"heading": _normalize_heading(heading),
		"steps_until_reaim": _roll_reaim_steps(),
		## New tips get several failed advance ticks before inert retire.
		"fail_streak": 0,
		## Per-tendril clock — staggered so tips don't lockstep, but never share budget.
		"tick_accum": _rng.randf() * tick_interval_sec,
		"value": TENDRIL_START_VALUE,
	}
	_lead_at[vox] = tid
	_rr_ids.append(tid)
	_start_tendril_sfx(tid, vox)
	tendril_spawned.emit(tid)
	return tid


## Seed a new tendril at world-space tip.
func spawn_tendril_at_world(
	world_pos: Vector3, prev_mat: int = -1, heading: Vector3 = Vector3.ZERO, force: bool = false
) -> int:
	if _tool == null or _terrain == null:
		return -1
	if _tendrils.size() >= max_tendrils:
		return -1
	return spawn_tendril_at_vox(_world_to_vox(world_pos), prev_mat, heading, force)


## Returns true if a tendril was killed.
func try_kill_lead_at_world(world_pos: Vector3) -> bool:
	return try_kill_lead_at_vox(_world_to_vox(world_pos))


func try_kill_lead_at_vox(vox: Vector3i) -> bool:
	if not _lead_at.has(vox):
		## Also accept any infection cell that is somehow the lead key mismatch.
		_tool.channel = VoxelBuffer.CHANNEL_TYPE
		if int(_tool.get_voxel(vox)) != VoxelMaterial.INFECTION_LEAD:
			return false
		## Scan tendrils for this lead.
		for tid in _tendrils.keys():
			var t: Dictionary = _tendrils[tid]
			if t.get("lead") == vox:
				_kill_tendril(int(tid))
				return true
		return false
	var tid2 := int(_lead_at[vox])
	_kill_tendril(tid2)
	return true


## If any lead sits in the carved set, kill those tendrils (full revert).
func notify_voxels_carved(vox_list: Array) -> void:
	var seen: Dictionary = {}
	for item in vox_list:
		var vox: Vector3i
		if item is Dictionary:
			vox = item.get("vox", Vector3i.ZERO)
		elif item is Vector3i:
			vox = item
		else:
			continue
		if not _lead_at.has(vox):
			continue
		var tid := int(_lead_at[vox])
		if seen.has(tid):
			continue
		seen[tid] = true
		_kill_tendril(tid)


func invalidate_outside_aabb(world_aabb: AABB) -> void:
	## Drop tendrils whose lead left the loaded detail bubble.
	var kill: Array[int] = []
	for tid in _tendrils.keys():
		var t: Dictionary = _tendrils[tid]
		var lead: Vector3i = t["lead"]
		var w := _vox_to_world(lead)
		if not world_aabb.has_point(w):
			kill.append(int(tid))
	for tid2 in kill:
		_forget_tendril(tid2)


func _physics_process(delta: float) -> void:
	if _tool == null or _tendrils.is_empty():
		return
	## Each tip advances on its own timer at full speed — no shared round-robin budget.
	var ids := _rr_ids.duplicate()
	for tid in ids:
		if not _tendrils.has(tid):
			_rr_ids.erase(tid)
			continue
		var t: Dictionary = _tendrils[tid]
		var accum := float(t.get("tick_accum", 0.0)) + delta
		if accum < tick_interval_sec:
			t["tick_accum"] = accum
			_tendrils[tid] = t
			continue
		t["tick_accum"] = accum - tick_interval_sec
		_tendrils[tid] = t
		_advance_tendril(tid)


func _advance_tendril(tid: int) -> bool:
	var t: Dictionary = _tendrils[tid]
	if not bool(t.get("alive", true)):
		return false
	var lead: Vector3i = t["lead"]
	var cells: Dictionary = t["cells"]
	var nxt := _pick_infect_neighbor(tid, lead)
	if nxt.x < 2147483646:
		t["fail_streak"] = 0
		_tendrils[tid] = t
		_infect_step(tid, lead, nxt)
		return true
	## Backtrace: walk parent chain for another frontier.
	var cursor := lead
	var guard := 0
	while guard < 4096:
		guard += 1
		var info: Variant = cells.get(cursor)
		if info == null:
			break
		var parent: Vector3i = info["parent"]
		if parent.x >= 2147483646:
			break
		var alt := _pick_infect_neighbor(tid, parent)
		if alt.x < 2147483646:
			t["fail_streak"] = 0
			_tendrils[tid] = t
			## Move lead to parent first (demote current lead), then infect outward.
			_move_lead(tid, lead, parent)
			_infect_step(tid, parent, alt)
			return true
		cursor = parent
	## Grace: don't inert-retire brand-new tips stuck on crater rock for a few ticks.
	var fails := int(t.get("fail_streak", 0)) + 1
	t["fail_streak"] = fails
	_tendrils[tid] = t
	if fails < 16:
		return false
	_retire_tendril_inert(tid)
	return false


func _infect_step(tid: int, from_lead: Vector3i, target: Vector3i) -> void:
	var t: Dictionary = _tendrils[tid]
	var cells: Dictionary = t["cells"]
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var prev := int(_tool.get_voxel(target))
	if not VoxelMaterial.is_infectable(prev) and prev != VoxelMaterial.AIR:
		return
	## Demote old lead.
	if cells.has(from_lead):
		_set_voxel(from_lead, VoxelMaterial.INFECTION)
	_lead_at.erase(from_lead)
	cells[target] = {"prev_mat": prev, "parent": from_lead}
	_set_voxel(target, VoxelMaterial.INFECTION_LEAD)
	t["lead"] = target
	## Count turns; every rnd*100 steps, pick a new general direction.
	var left := int(t.get("steps_until_reaim", 1)) - 1
	if left <= 0:
		t["heading"] = _normalize_heading(Vector3.ZERO)
		t["steps_until_reaim"] = _roll_reaim_steps()
	else:
		t["steps_until_reaim"] = left
	_lead_at[target] = tid
	_tendrils[tid] = t
	_apply_digest_score(tid)
	_sfx_tendril_transmuted(tid, target)


func _apply_digest_score(tid: int) -> void:
	if not _tendrils.has(tid):
		return
	var t: Dictionary = _tendrils[tid]
	var value := int(t.get("value", 0))
	if value > 0:
		t["value"] = value - 1
		_tendrils[tid] = t
		return
	## Depleted tip: each further conversion taxes the player.
	t["value"] = 0
	_tendrils[tid] = t
	player_score -= 1
	player_score_changed.emit(player_score)


func _move_lead(tid: int, old_lead: Vector3i, new_lead: Vector3i) -> void:
	var t: Dictionary = _tendrils[tid]
	var cells: Dictionary = t["cells"]
	if cells.has(old_lead):
		_set_voxel(old_lead, VoxelMaterial.INFECTION)
	_lead_at.erase(old_lead)
	if cells.has(new_lead):
		_set_voxel(new_lead, VoxelMaterial.INFECTION_LEAD)
		t["lead"] = new_lead
		_lead_at[new_lead] = tid
		_tendrils[tid] = t
		_move_tendril_sfx(tid, new_lead)


func _pick_infect_neighbor(tid: int, vox: Vector3i) -> Vector3i:
	## Shuffle + heavy jiggle, soft general heading, light expand nudge.
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var t: Dictionary = _tendrils.get(tid, {})
	var origin: Vector3i = t.get("origin", vox)
	var heading: Vector3 = t.get("heading", Vector3(1, 0, 0))
	if heading.length_squared() < 0.0001:
		heading = Vector3(1, 0, 0)
	else:
		heading = heading.normalized()
	var cur_d2 := (vox - origin).length_squared()
	var fabric: Array[Vector3i] = []
	var other: Array[Vector3i] = []
	var order := _NEIGHBORS.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Vector3i = order[i]
		order[i] = order[j]
		order[j] = tmp
	for off in order:
		var n: Vector3i = vox + off
		var id := int(_tool.get_voxel(n))
		if not VoxelMaterial.is_infectable(id):
			continue
		if VoxelMaterial.is_building_fabric(id):
			fabric.append(n)
		else:
			other.append(n)
	var pool: Array[Vector3i] = fabric if not fabric.is_empty() else other
	if pool.is_empty():
		return _NO_VOX
	if expand_prefer_chance > 0.0 and _rng.randf() < expand_prefer_chance:
		var expanding: Array[Vector3i] = []
		for n2 in pool:
			if (n2 - origin).length_squared() > cur_d2:
				expanding.append(n2)
		if not expanding.is_empty():
			pool = expanding
	return _pick_jiggled(pool, vox, heading)


func _pick_jiggled(pool: Array[Vector3i], from: Vector3i, heading: Vector3) -> Vector3i:
	## Random weight dominates; heading_soft only nudges the general course.
	var best := pool[0]
	var best_score := -1.0e9
	for n in pool:
		var off := n - from
		var step_f := Vector3(float(off.x), float(off.y) * 0.35, float(off.z))
		var align := 0.0
		if step_f.length_squared() > 0.0001:
			align = step_f.normalized().dot(heading)
		var score := _rng.randf() * pick_jiggle + align * heading_soft
		if score > best_score:
			best_score = score
			best = n
	return best


func _roll_reaim_steps() -> int:
	## rnd * 100 turns (at least 1).
	return maxi(1, int(ceil(_rng.randf() * float(maxi(heading_reaim_max_steps, 1)))))


func _normalize_heading(heading: Vector3) -> Vector3:
	if heading.length_squared() < 0.0001:
		var yaw := _rng.randf() * TAU
		return Vector3(cos(yaw), _rng.randf_range(-0.2, 0.35), sin(yaw)).normalized()
	var h := heading
	h.y = clampf(h.y, -0.55, 0.75)
	if absf(h.x) + absf(h.z) < 0.05:
		var yaw2 := _rng.randf() * TAU
		h.x = cos(yaw2)
		h.z = sin(yaw2)
	return h.normalized()


func _kill_tendril(tid: int) -> void:
	if not _tendrils.has(tid):
		return
	var t: Dictionary = _tendrils[tid]
	var cells: Dictionary = t["cells"]
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_tool.mode = VoxelTool.MODE_SET
	## Restore in arbitrary order — materials only.
	for vox in cells.keys():
		var info: Dictionary = cells[vox]
		var prev: int = int(info.get("prev_mat", VoxelMaterial.AIR))
		_set_voxel(vox, prev)
		_lead_at.erase(vox)
	_forget_tendril(tid)
	tendril_killed.emit(tid)


func _retire_tendril_inert(tid: int) -> void:
	## No more growth; demote lead to body infection.
	if not _tendrils.has(tid):
		return
	var t: Dictionary = _tendrils[tid]
	var lead: Vector3i = t["lead"]
	_set_voxel(lead, VoxelMaterial.INFECTION)
	_lead_at.erase(lead)
	_forget_tendril(tid)


func _forget_tendril(tid: int) -> void:
	if not _tendrils.has(tid) and not _rr_ids.has(tid):
		## Already gone — avoid double-ended for callers that erase first.
		return
	_stop_tendril_sfx(tid)
	_tendrils.erase(tid)
	_rr_ids.erase(tid)
	## Clean any stale lead map entries for this id.
	var stale: Array[Vector3i] = []
	for vox in _lead_at.keys():
		if int(_lead_at[vox]) == tid:
			stale.append(vox)
	for v in stale:
		_lead_at.erase(v)
	tendril_ended.emit(tid)


func _city_audio() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group(&"city_audio")


func _start_tendril_sfx(tid: int, vox: Vector3i) -> void:
	var audio := _city_audio()
	if audio != null and audio.has_method("start_tendril_voice"):
		audio.call("start_tendril_voice", tid, _vox_to_world(vox))


func _move_tendril_sfx(tid: int, vox: Vector3i) -> void:
	var audio := _city_audio()
	if audio != null and audio.has_method("move_tendril_voice"):
		audio.call("move_tendril_voice", tid, _vox_to_world(vox))


func _sfx_tendril_transmuted(tid: int, vox: Vector3i) -> void:
	var world := _vox_to_world(vox)
	var audio := _city_audio()
	if audio == null:
		return
	if audio.has_method("move_tendril_voice"):
		audio.call("move_tendril_voice", tid, world)
	if audio.has_method("play_tendril_transmute"):
		audio.call("play_tendril_transmute", world)


func _stop_tendril_sfx(tid: int) -> void:
	var audio := _city_audio()
	if audio != null and audio.has_method("stop_tendril_voice"):
		audio.call("stop_tendril_voice", tid)


func _set_voxel(vox: Vector3i, mat_id: int) -> void:
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = mat_id
	_tool.do_point(vox)


func _world_to_vox(world: Vector3) -> Vector3i:
	var local := _terrain.to_local(world)
	return Vector3i(int(floor(local.x)), int(floor(local.y)), int(floor(local.z)))


func _vox_to_world(vox: Vector3i) -> Vector3:
	return _terrain.to_global(Vector3(float(vox.x) + 0.5, float(vox.y) + 0.5, float(vox.z) + 0.5))
