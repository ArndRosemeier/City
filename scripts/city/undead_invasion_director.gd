## Spawns undead waves, tracks the giant slot, converts pedestrians via mage orbs.
extends Node3D

const UndeadUnitScript := preload("res://scripts/city/undead_unit.gd")

const CONVERT_SCORE_PENALTY := 150
const WAVE_MIN_COUNT := 3
const WAVE_MAX_COUNT := 5
const MAX_ALIVE_UNITS := 40
const MAX_MINIONS := 28
const MAGE_FLEE_TRIGGER_M := 15.0
const MAGE_FLEE_CLEAR_M := 100.0
const MAGE_SCARE_INTERVAL_SEC := 0.25

var _city: Node
var _enabled: bool = false
var _units: Array = []  ## UndeadUnit nodes
var _giant: Node = null
var _giant_candidate: Node = null
var _spawn_accum: float = 0.0
var _spawn_interval_sec: float = 90.0
var _scare_accum: float = 0.0


func setup(city: Node) -> void:
	_city = city


func set_enabled(on: bool) -> void:
	_enabled = on
	if on:
		_spawn_accum = 0.0
		_roll_interval()
		spawn_wave()
		print("UndeadInvasion: ON (next wave in %.0fs)" % _spawn_interval_sec)
	else:
		_spawn_accum = 0.0
		clear_all()
		print("UndeadInvasion: OFF")


## Stop new waves without despawning the army (game over).
func halt_waves() -> void:
	_enabled = false
	_spawn_accum = 0.0


func is_enabled() -> bool:
	return _enabled


func clear_all() -> void:
	for u in _units:
		if u != null and is_instance_valid(u):
			u.queue_free()
	_units.clear()
	_giant = null
	_giant_candidate = null
	for c in get_children():
		if str(c.name).begins_with("UndeadOrb"):
			c.queue_free()


func get_alive_units() -> Array:
	_prune_units()
	var out: Array = []
	for u in _units:
		if u != null and is_instance_valid(u) and bool(u.call("is_alive")):
			out.append(u)
	return out


func get_hud_stats() -> Dictionary:
	_prune_units()
	var mages := 0
	var converted := 0
	var giant_out := false
	for u in _units:
		if u == null or not is_instance_valid(u):
			continue
		if not bool(u.call("is_alive")):
			continue
		if bool(u.call("is_giant")):
			giant_out = true
			continue
		var unit_role: int = int(u.get("role"))
		if unit_role == UndeadUnitScript.Role.MINION:
			converted += 1
		else:
			## Mage (and any non-giant seeker still growing toward the pad).
			mages += 1
	if _giant != null and is_instance_valid(_giant) and bool(_giant.call("is_alive")):
		giant_out = true
	var active := _enabled or mages > 0 or converted > 0 or giant_out
	return {
		"active": active,
		"mages": mages,
		"converted": converted,
		"giant": giant_out,
	}


func _roll_interval() -> void:
	_spawn_interval_sec = randf_range(60.0, 180.0)


func _process(delta: float) -> void:
	if not _enabled:
		return
	_prune_units()
	_spawn_accum += delta
	if _spawn_accum >= _spawn_interval_sec:
		_spawn_accum = 0.0
		_roll_interval()
		spawn_wave()
	_scare_accum += delta
	if _scare_accum >= MAGE_SCARE_INTERVAL_SEC:
		_scare_accum = 0.0
		_scare_crowd_from_mages()


func _scare_crowd_from_mages() -> void:
	if _city == null or not _city.has_method("scare_crowd_from_mages"):
		return
	var threats: Array = []
	for u in _units:
		if u == null or not is_instance_valid(u):
			continue
		if not bool(u.call("is_alive")):
			continue
		if not bool(u.call("is_mage")):
			continue
		threats.append((u as Node3D).global_position)
	if threats.is_empty():
		return
	_city.call("scare_crowd_from_mages", threats, MAGE_FLEE_TRIGGER_M, MAGE_FLEE_CLEAR_M)


func spawn_wave() -> void:
	if _city == null or not _city.has_method("pick_undead_spawn_point"):
		return
	_prune_units()
	var alive := _count_alive()
	if alive >= MAX_ALIVE_UNITS:
		print("UndeadInvasion: wave skipped (at cap %d)" % MAX_ALIVE_UNITS)
		return
	var count := mini(randi_range(WAVE_MIN_COUNT, WAVE_MAX_COUNT), MAX_ALIVE_UNITS - alive)
	var spawned := 0
	for _i in range(count):
		var pos: Vector3 = _city.call("pick_undead_spawn_point") as Vector3
		if pos == Vector3.INF:
			continue
		_spawn_unit(UndeadUnitScript.Role.MAGE, pos)
		spawned += 1
	print("UndeadInvasion: wave spawned=%d (alive=%d)" % [spawned, _count_alive()])


func spawn_minion_at(world_pos: Vector3) -> void:
	_prune_units()
	if _count_alive() >= MAX_ALIVE_UNITS:
		return
	if _count_role(UndeadUnitScript.Role.MINION) >= MAX_MINIONS:
		return
	_spawn_unit(UndeadUnitScript.Role.MINION, world_pos)


func _count_alive() -> int:
	var n := 0
	for u in _units:
		if u != null and is_instance_valid(u) and bool(u.call("is_alive")):
			n += 1
	return n


func _count_role(want_role: int) -> int:
	var n := 0
	for u in _units:
		if u == null or not is_instance_valid(u) or not bool(u.call("is_alive")):
			continue
		if bool(u.call("is_giant")):
			continue
		if int(u.get("role")) == want_role:
			n += 1
	return n


func _spawn_unit(role: int, world_pos: Vector3) -> Node:
	var unit: Node = UndeadUnitScript.new()
	unit.name = "Undead_%d" % _units.size()
	add_child(unit)
	unit.call("setup", role, self, _city, world_pos)
	if unit.has_signal("died"):
		unit.connect("died", _on_unit_died)
	_units.append(unit)
	return unit


func wants_giant_candidate(unit: Node) -> bool:
	if not _enabled:
		return false
	if _giant != null and is_instance_valid(_giant) and bool(_giant.call("is_alive")):
		return false
	if _giant_candidate != null and is_instance_valid(_giant_candidate) and _giant_candidate != unit:
		if bool(_giant_candidate.call("is_alive")):
			return false
	_giant_candidate = unit
	return true


func notify_giant_ready(unit: Node) -> void:
	_giant = unit
	_giant_candidate = unit
	print("UndeadInvasion: giant ready")


func try_convert_ped_at(world_pos: Vector3, radius: float) -> bool:
	if _city == null:
		return false
	## Player is a valid mage target — orb contact is game over, not a minion spawn.
	if _city.has_method("try_orb_hit_player") and bool(_city.call("try_orb_hit_player", world_pos, radius)):
		return true
	if not _city.has_method("try_convert_ped_near"):
		return false
	var converted: Variant = _city.call("try_convert_ped_near", world_pos, radius)
	if converted == null or not (converted is Vector3):
		return false
	var pos: Vector3 = converted as Vector3
	if _city.has_method("adjust_player_score"):
		_city.call("adjust_player_score", -CONVERT_SCORE_PENALTY)
	spawn_minion_at(pos)
	return true


func query_segment_hit(from: Vector3, to: Vector3) -> Dictionary:
	var best_dist := INF
	var best: Dictionary = {}
	var seg := to - from
	var seg_len := seg.length()
	if seg_len < 0.05:
		return best
	var dir := seg / seg_len
	for u in _units:
		if u == null or not is_instance_valid(u):
			continue
		if not bool(u.call("is_alive")):
			continue
		var r: float = float(u.call("hit_radius"))
		var hh: float = float(u.call("hit_half_height"))
		var center: Vector3 = (u as Node3D).global_position + Vector3(0.0, hh * 0.85, 0.0)
		var hit := CrowdDirector._segment_hits_capsule(from, dir, seg_len, center, r, hh)
		if hit.is_empty():
			continue
		var dist: float = float(hit["distance"])
		if dist >= best_dist:
			continue
		best_dist = dist
		best = {
			"distance": dist,
			"point": hit["point"],
			"unit": u,
		}
	return best


func kill_unit(unit: Node) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	if not bool(unit.call("is_alive")):
		return false
	var award: int = int(unit.call("kill_from_player"))
	if _city != null and _city.has_method("adjust_player_score") and award != 0:
		_city.call("adjust_player_score", award)
	return true


func _on_unit_died(unit: Node, was_giant: bool) -> void:
	if unit == _giant or was_giant:
		_giant = null
	if unit == _giant_candidate:
		_giant_candidate = null


func _prune_units() -> void:
	var kept: Array = []
	for u in _units:
		if u != null and is_instance_valid(u):
			kept.append(u)
	_units = kept
	if _giant != null and not is_instance_valid(_giant):
		_giant = null
	if _giant_candidate != null and not is_instance_valid(_giant_candidate):
		_giant_candidate = null
