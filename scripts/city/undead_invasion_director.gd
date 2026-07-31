## Undead invasion scenario: waves, giant slot, mage scare, orb conversion.
## Living bodies live on MonsterRoster — this director only drives the invasion rules.
class_name UndeadInvasionDirector
extends Node3D

const WAVE_MIN_COUNT := 3
const WAVE_MAX_COUNT := 5
const MAX_ALIVE_UNITS := 40
const MAX_MINIONS := 28
const MAGE_FLEE_TRIGGER_M := 15.0
const MAGE_FLEE_CLEAR_M := 100.0
const MAGE_SCARE_INTERVAL_SEC := 0.25

var _city: CityRoot
var _roster: MonsterRoster
var _enabled: bool = false
var _giant: UndeadUnit = null
var _giant_candidate: UndeadUnit = null
var _spawn_accum: float = 0.0
var _spawn_interval_sec: float = 90.0
var _scare_accum: float = 0.0


func setup(city: CityRoot, roster: MonsterRoster) -> void:
	_city = city
	_roster = roster
	if _roster == null:
		push_error("UndeadInvasion.setup: null MonsterRoster")
		assert(false, "UndeadInvasion: roster required")


func roster() -> MonsterRoster:
	return _roster


func set_enabled(on: bool) -> void:
	_enabled = on
	if on:
		_spawn_accum = 0.0
		_roll_interval()
		spawn_wave()
		print("UndeadInvasion: ON (next wave in %.0fs)" % _spawn_interval_sec)
	else:
		_spawn_accum = 0.0
		clear_invasion()
		print("UndeadInvasion: OFF")


## Stop new waves without despawning the army (game over).
func halt_waves() -> void:
	_enabled = false
	_spawn_accum = 0.0


func is_enabled() -> bool:
	return _enabled


## Wipe invasion-owned bodies only — arena / free summons stay on the roster.
func clear_invasion() -> void:
	_giant = null
	_giant_candidate = null
	if _roster != null:
		_roster.clear_invasion_units()


## @deprecated Prefer clear_invasion — kept for callers / tests that still say clear_all.
func clear_all() -> void:
	clear_invasion()


func get_alive_units() -> Array[UndeadUnit]:
	if _roster == null:
		return []
	var out: Array[UndeadUnit] = []
	for u in _roster.get_alive_units():
		if MonsterRoster.is_invasion_owned(u):
			out.append(u)
	return out


func get_hud_stats() -> Dictionary:
	var mages := 0
	var converted := 0
	var giant_out := false
	if _roster != null:
		for u in _roster.get_alive_units():
			if not MonsterRoster.is_invasion_owned(u):
				continue
			if u.is_giant():
				giant_out = true
				continue
			if u.role == UndeadUnit.Role.MINION:
				converted += 1
			else:
				mages += 1
	if _giant != null and is_instance_valid(_giant) and _giant.is_alive():
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
	CityProfiler.begin("undead")
	_spawn_accum += delta
	if _spawn_accum >= _spawn_interval_sec:
		_spawn_accum = 0.0
		_roll_interval()
		spawn_wave()
	_scare_accum += delta
	if _scare_accum >= MAGE_SCARE_INTERVAL_SEC:
		_scare_accum = 0.0
		_scare_crowd_from_mages()
	CityProfiler.end("undead")


func _scare_crowd_from_mages() -> void:
	if _city == null or _roster == null:
		return
	var threats: Array = []
	for u in _roster.get_alive_units():
		if not MonsterRoster.is_invasion_owned(u) or not u.is_mage():
			continue
		threats.append(u.global_position)
	if threats.is_empty():
		return
	_city.scare_crowd_from_mages(threats, MAGE_FLEE_TRIGGER_M, MAGE_FLEE_CLEAR_M)


func spawn_wave() -> void:
	if _city == null or _roster == null:
		return
	var alive := _count_invasion_alive()
	if alive >= MAX_ALIVE_UNITS:
		print("UndeadInvasion: wave skipped (at cap %d)" % MAX_ALIVE_UNITS)
		return
	var count := mini(randi_range(WAVE_MIN_COUNT, WAVE_MAX_COUNT), MAX_ALIVE_UNITS - alive)
	var spawned := 0
	for _i in range(count):
		var pos := _city.pick_undead_spawn_point()
		if pos == Vector3.INF:
			continue
		if _spawn_unit(UndeadUnit.Role.MAGE, pos) != null:
			spawned += 1
	print("UndeadInvasion: wave spawned=%d (alive=%d)" % [spawned, _count_invasion_alive()])


func spawn_minion_at(world_pos: Vector3) -> void:
	if _roster == null:
		return
	if _count_invasion_alive() >= MAX_ALIVE_UNITS:
		return
	if _count_invasion_role(UndeadUnit.Role.MINION) >= MAX_MINIONS:
		return
	_spawn_unit(UndeadUnit.Role.MINION, world_pos)


## Test / legacy path — production summons go through MonsterRoster.spawn_by_id.
func spawn_monster_by_id(body_id: String, world_pos: Vector3, body_seed: int = -1) -> UndeadUnit:
	if _roster == null:
		push_error("UndeadInvasion.spawn_monster_by_id: no roster")
		return null
	return _roster.spawn_by_id(body_id, world_pos, body_seed, true, self)


func _count_invasion_alive() -> int:
	var n := 0
	if _roster == null:
		return 0
	for u in _roster.get_alive_units():
		if MonsterRoster.is_invasion_owned(u):
			n += 1
	return n


func _count_invasion_role(want_role: UndeadUnit.Role) -> int:
	var n := 0
	if _roster == null:
		return 0
	for u in _roster.get_alive_units():
		if not MonsterRoster.is_invasion_owned(u) or u.is_giant():
			continue
		if u.role == want_role:
			n += 1
	return n


## Spawns an invasion-owned body on the shared roster.
func _spawn_unit(
	spawn_role: UndeadUnit.Role,
	world_pos: Vector3,
	body_seed: int = -1,
	body_id: String = ""
) -> UndeadUnit:
	if _roster == null:
		return null
	return _roster.spawn_role(spawn_role, world_pos, body_seed, body_id, true, self)


func wants_giant_candidate(unit: UndeadUnit) -> bool:
	if not _enabled:
		return false
	if _giant != null and is_instance_valid(_giant) and _giant.is_alive():
		return false
	if _giant_candidate != null and is_instance_valid(_giant_candidate) and _giant_candidate != unit:
		if _giant_candidate.is_alive():
			return false
	_giant_candidate = unit
	return true


func notify_giant_ready(unit: UndeadUnit) -> void:
	_giant = unit
	_giant_candidate = unit
	print("UndeadInvasion: giant ready")


func try_convert_ped_at(world_pos: Vector3, radius: float) -> bool:
	if _city == null:
		return false
	## Player is a valid mage target — orb contact is game over, not a minion spawn.
	if _city.try_orb_hit_player(world_pos, radius):
		return true
	var converted: Variant = _city.try_convert_ped_near(world_pos, radius)
	if converted == null or not (converted is Vector3):
		return false
	var pos: Vector3 = converted as Vector3
	spawn_minion_at(pos)
	return true


## Forwarders so older tests that still aim the director keep working.
func query_segment_hit(from: Vector3, to: Vector3) -> Dictionary:
	if _roster == null:
		return {}
	return _roster.query_segment_hit(from, to)


func damage_unit(unit: UndeadUnit, source: DamageSource.Id) -> bool:
	if _roster == null:
		return false
	return _roster.damage_unit(unit, source)


func damage_units_in_sphere(center: Vector3, radius: float, source: DamageSource.Id) -> int:
	if _roster == null:
		return 0
	return _roster.damage_units_in_sphere(center, radius, source)


func unregister_unit(unit: UndeadUnit) -> void:
	if unit == _giant:
		_giant = null
	if unit == _giant_candidate:
		_giant_candidate = null
	if _roster != null:
		_roster.unregister_unit(unit)


func despawn_unit(unit: UndeadUnit) -> void:
	if unit == _giant:
		_giant = null
	if unit == _giant_candidate:
		_giant_candidate = null
	if _roster != null:
		_roster.despawn_unit(unit)
