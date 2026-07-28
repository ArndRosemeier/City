## Budgeted single-tip infection tendrils. Visual threat only (v1).
## Each tendril has one INFECTION_LEAD; killing the lead reverts the whole lineage.
class_name InfectionDirector
extends Node

const TendrilAuraScript := preload("res://scripts/city/infection_tendril_aura_vfx.gd")

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
## Street-deck surface voxel Y (DistrictGenerator.ground_thickness). Tips never go below this.
@export var min_surface_vox_y: int = 6
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
## Write funnel owned by CityRoot — all tip/body writes go through it.
var _brush: CityBrush
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
## tendril_id → aura Node3D
var _auras: Dictionary = {}


func setup(
	terrain: VoxelTerrain,
	tool: VoxelTool,
	brush: CityBrush,
	voxel_size: float,
	surface_vox_y: int = -1
) -> void:
	_terrain = terrain
	_tool = tool
	_brush = brush
	_voxel_size = voxel_size
	if surface_vox_y >= 0:
		min_surface_vox_y = surface_vox_y
	_rng.randomize()


func clear_all() -> void:
	var tids: Array = _tendrils.keys()
	for tid in tids:
		_stop_tendril_sfx(int(tid))
		_stop_tendril_aura(int(tid))
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
	return _growing_tendril_count()


func _growing_tendril_count() -> int:
	var n := 0
	for tid in _tendrils.keys():
		var t: Dictionary = _tendrils[tid]
		if bool(t.get("dying", false)):
			continue
		n += 1
	return n


## Snapshot for HUD: ordered rows of {id, value} (remaining tip value).
func get_tendril_hud_rows() -> Array:
	var rows: Array = []
	for tid in _rr_ids:
		if not _tendrils.has(tid):
			continue
		var t: Dictionary = _tendrils[tid]
		if bool(t.get("dying", false)):
			continue
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
	if _growing_tendril_count() >= max_tendrils:
		return -1
	## Lift underground seeds onto the street deck — never start below ground level.
	vox = _clamp_to_surface(vox)
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
	if VoxelMaterial.is_diggable_substrate(current):
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
	_start_tendril_aura(tid, vox)
	tendril_spawned.emit(tid)
	return tid


## Seed a new tendril at world-space tip.
func spawn_tendril_at_world(
	world_pos: Vector3, prev_mat: int = -1, heading: Vector3 = Vector3.ZERO, force: bool = false
) -> int:
	if _tool == null or _terrain == null:
		return -1
	if _growing_tendril_count() >= max_tendrils:
		return -1
	return spawn_tendril_at_vox(_world_to_vox(world_pos), prev_mat, heading, force)


## Returns true if a tendril was killed.
func try_kill_lead_at_world(world_pos: Vector3) -> bool:
	return try_kill_lead_at_vox(_world_to_vox(world_pos))


func try_kill_lead_at_vox(vox: Vector3i) -> bool:
	var tid := _tendril_id_for_lead_vox(vox)
	if tid >= 0:
		_kill_tendril(tid)
		return true
	## Orphan glowing tip (planted but never registered / forgotten without restore).
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	if int(_tool.get_voxel(vox)) != VoxelMaterial.INFECTION_LEAD:
		return false
	## No lineage to restore — at least clear the dead tip so it can't fake a killable head.
	_set_voxel(vox, VoxelMaterial.AIR)
	return false


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
		var tid := _tendril_id_for_lead_vox(vox)
		if tid < 0:
			continue
		if seen.has(tid):
			continue
		seen[tid] = true
		_kill_tendril(tid)


func _tendril_id_for_lead_vox(vox: Vector3i) -> int:
	if _lead_at.has(vox):
		return int(_lead_at[vox])
	## Fallback when map desynced — still match by tendril lead cell.
	for tid in _tendrils.keys():
		var t: Dictionary = _tendrils[tid]
		if t.get("lead") == vox:
			return int(tid)
	return -1


func invalidate_outside_aabb(world_aabb: AABB) -> void:
	## Pause tips that left the loaded detail bubble — do NOT forget them.
	## Forgetting dropped lineage + _lead_at while leaving glowing LEAD voxels in the world,
	## so growth stopped and tip-kill could no longer revert (common when meteors land near
	## the detail edge or the player walks toward a far undead wave).
	for tid in _tendrils.keys():
		var t: Dictionary = _tendrils[tid]
		var lead: Vector3i = t["lead"]
		var w := _vox_to_world(lead)
		var inside := world_aabb.has_point(w)
		var was_suspended := bool(t.get("suspended", false))
		if inside and was_suspended:
			## Resuming — clear fail streak so a brief unload doesn't inert-retire.
			t["fail_streak"] = 0
		t["suspended"] = not inside
		_tendrils[tid] = t


func _physics_process(delta: float) -> void:
	if _tool == null or _tendrils.is_empty():
		return
	CityProfiler.begin("infection")
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
		## Dying tips keep reverting even outside the detail bubble.
		if bool(t.get("dying", false)):
			_revert_tendril_tick(tid)
			continue
		if bool(t.get("suspended", false)):
			continue
		_advance_tendril(tid)
	CityProfiler.end("infection")


func _advance_tendril(tid: int) -> bool:
	var t: Dictionary = _tendrils[tid]
	if not bool(t.get("alive", true)):
		return false
	## If something carved the tip without tip-kill (e.g. old undead stomps), replant it
	## so growth continues and the player can still kill-to-revert.
	_repair_lead_voxel(tid)
	if not _tendrils.has(tid):
		return false
	t = _tendrils[tid]
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


func _repair_lead_voxel(tid: int) -> void:
	if not _tendrils.has(tid) or _tool == null:
		return
	var t: Dictionary = _tendrils[tid]
	var lead: Vector3i = t["lead"]
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var id := int(_tool.get_voxel(lead))
	if id == VoxelMaterial.INFECTION_LEAD:
		_lead_at[lead] = tid
		return
	## Tip voxel missing or demoted — restore a killable glowing head on the lineage tip.
	_set_voxel(lead, VoxelMaterial.INFECTION_LEAD)
	_lead_at[lead] = tid


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
	if value <= 0:
		## Depleted tips keep converting; score is never taxed.
		return
	t["value"] = value - 1
	_tendrils[tid] = t


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
		## Street deck is the floor — never crawl into diggable stone under pavement.
		if n.y < min_surface_vox_y:
			continue
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
		return Vector3(cos(yaw), _rng.randf_range(0.0, 0.35), sin(yaw)).normalized()
	var h := heading
	## Prefer level / upward crawl — never aim into the ground.
	h.y = clampf(h.y, 0.0, 0.75)
	if absf(h.x) + absf(h.z) < 0.05:
		var yaw2 := _rng.randf() * TAU
		h.x = cos(yaw2)
		h.z = sin(yaw2)
	return h.normalized()


## Raise a voxel onto the street-deck surface Y when it would start underground.
func _clamp_to_surface(vox: Vector3i) -> Vector3i:
	if vox.y >= min_surface_vox_y:
		return vox
	return Vector3i(vox.x, min_surface_vox_y, vox.z)


func _kill_tendril(tid: int) -> void:
	if not _tendrils.has(tid):
		return
	var t: Dictionary = _tendrils[tid]
	if bool(t.get("dying", false)):
		return
	## Bank whatever value is left — kill early for the full 1000.
	var remaining := maxi(int(t.get("value", 0)), 0)
	if remaining > 0:
		player_score += remaining
		player_score_changed.emit(player_score)
	var lead: Vector3i = t["lead"]
	var cells: Dictionary = t["cells"]
	var order := _build_revert_order(lead, cells)
	## Stop growth / tip targeting immediately; voxels peel back head → root.
	_lead_at.erase(lead)
	_stop_tendril_sfx(tid)
	_stop_tendril_aura(tid)
	t["dying"] = true
	t["alive"] = false
	t["value"] = 0
	t["revert_queue"] = order
	t["tick_accum"] = 0.0
	_tendrils[tid] = t
	tendril_killed.emit(tid)
	## First voxel (the destroyed head) reverts on this kill tick.
	_revert_tendril_tick(tid)


## Head-first parent walk, then any leftover side-branch tips (also tip→root).
func _build_revert_order(lead: Vector3i, cells: Dictionary) -> Array[Vector3i]:
	var order: Array[Vector3i] = []
	var seen: Dictionary = {}
	_append_parent_chain(order, seen, lead, cells)
	for vox in cells.keys():
		if seen.has(vox):
			continue
		_append_parent_chain(order, seen, vox as Vector3i, cells)
	return order


func _append_parent_chain(
	order: Array[Vector3i], seen: Dictionary, start: Vector3i, cells: Dictionary
) -> void:
	var cursor := start
	var guard := 0
	while guard < 4096:
		guard += 1
		if not cells.has(cursor) or seen.has(cursor):
			break
		seen[cursor] = true
		order.append(cursor)
		var info: Dictionary = cells[cursor]
		var parent: Vector3i = info.get("parent", _NO_VOX)
		if parent.x >= 2147483646:
			break
		cursor = parent


func _revert_tendril_tick(tid: int) -> void:
	if not _tendrils.has(tid):
		return
	var t: Dictionary = _tendrils[tid]
	var queue: Array = t.get("revert_queue", []) as Array
	var cells: Dictionary = t.get("cells", {}) as Dictionary
	if queue.is_empty():
		_forget_tendril(tid)
		return
	var vox: Vector3i = queue.pop_front() as Vector3i
	t["revert_queue"] = queue
	if cells.has(vox):
		var info: Dictionary = cells[vox]
		var prev: int = int(info.get("prev_mat", VoxelMaterial.AIR))
		_set_voxel(vox, prev)
		cells.erase(vox)
		t["cells"] = cells
	_lead_at.erase(vox)
	_tendrils[tid] = t
	if queue.is_empty():
		_forget_tendril(tid)


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
	_stop_tendril_aura(tid)
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
	_move_tendril_aura(tid, vox)


func _sfx_tendril_transmuted(tid: int, vox: Vector3i) -> void:
	var world := _vox_to_world(vox)
	var audio := _city_audio()
	if audio != null:
		if audio.has_method("move_tendril_voice"):
			audio.call("move_tendril_voice", tid, world)
		if audio.has_method("play_tendril_transmute"):
			audio.call("play_tendril_transmute", world)
	_move_tendril_aura(tid, vox)


func _stop_tendril_sfx(tid: int) -> void:
	var audio := _city_audio()
	if audio != null and audio.has_method("stop_tendril_voice"):
		audio.call("stop_tendril_voice", tid)


func _aura_parent() -> Node:
	if _terrain != null and is_instance_valid(_terrain):
		return _terrain
	return get_parent()


func _start_tendril_aura(tid: int, vox: Vector3i) -> void:
	_stop_tendril_aura(tid)
	var host := _aura_parent()
	if host == null:
		return
	var aura: Node3D = TendrilAuraScript.new() as Node3D
	aura.name = "TendrilAura_%d" % tid
	host.add_child(aura)
	aura.call("setup", _vox_to_world(vox), _rng.randf() * TAU)
	_auras[tid] = aura


func _move_tendril_aura(tid: int, vox: Vector3i) -> void:
	var aura: Variant = _auras.get(tid, null)
	if aura == null or not is_instance_valid(aura):
		return
	if aura.has_method("move_to"):
		aura.call("move_to", _vox_to_world(vox))


func _stop_tendril_aura(tid: int) -> void:
	var aura: Variant = _auras.get(tid, null)
	_auras.erase(tid)
	if aura != null and is_instance_valid(aura):
		(aura as Node).queue_free()


func _set_voxel(vox: Vector3i, mat_id: int) -> void:
	_brush.set_vox(vox, mat_id)


func _world_to_vox(world: Vector3) -> Vector3i:
	var local := _terrain.to_local(world)
	return Vector3i(int(floor(local.x)), int(floor(local.y)), int(floor(local.z)))


func _vox_to_world(vox: Vector3i) -> Vector3:
	return _terrain.to_global(Vector3(float(vox.x) + 0.5, float(vox.y) + 0.5, float(vox.z) + 0.5))
