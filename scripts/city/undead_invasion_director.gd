## Spawns undead waves, tracks the giant slot, converts pedestrians via mage orbs.
##
## Every unit it spawns navigates through NavService, so a wave is only worth spawning once
## the nav world exists. It also owns the two things the whole army shares: the LOD bands and
## the terrain the near tier collides against.
class_name UndeadInvasionDirector
extends Node3D

const CreatureCatalogScript := preload("res://scripts/city/creature_catalog.gd")

const CONVERT_SCORE_PENALTY := 150
const WAVE_MIN_COUNT := 3
const WAVE_MAX_COUNT := 5
const MAX_ALIVE_UNITS := 40
const MAX_MINIONS := 28
const MAGE_FLEE_TRIGGER_M := 15.0
const MAGE_FLEE_CLEAR_M := 100.0
const MAGE_SCARE_INTERVAL_SEC := 0.25
## CityRoot's terrain child. NavMotor's near tier moves bodies with VoxelBoxMover against
## live voxel data, which needs the terrain node itself; CityRoot exposes no accessor.
const TERRAIN_NODE_NAME := "VoxelTerrain"

var _city: CityRoot
var _terrain: VoxelTerrain
var _lod: NavLod
var _enabled: bool = false
var _units: Array[UndeadUnit] = []
var _giant: UndeadUnit = null
var _giant_candidate: UndeadUnit = null
var _spawn_accum: float = 0.0
var _spawn_interval_sec: float = 90.0
var _scare_accum: float = 0.0


func setup(city: CityRoot) -> void:
	_city = city
	_terrain = city.get_node_or_null(TERRAIN_NODE_NAME) as VoxelTerrain
	if _terrain == null:
		push_error(
			"UndeadInvasion: CityRoot has no %s child, undead cannot collide with voxels"
			% TERRAIN_NODE_NAME
		)
	_lod = NavLod.for_collision_view(NavLod.COLLISION_VIEW_VOX_DEFAULT, CityRoot.VOXEL_SIZE)


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
	## Snapshot: queue_free → tree_exiting must not mutate `_units` while we walk it.
	var doomed: Array[UndeadUnit] = _units.duplicate()
	_units.clear()
	_giant = null
	_giant_candidate = null
	for u in doomed:
		if u != null and is_instance_valid(u):
			u.queue_free()
	for c in get_children():
		if str(c.name).begins_with("UndeadOrb"):
			c.queue_free()


func get_alive_units() -> Array[UndeadUnit]:
	_prune_units()
	var out: Array[UndeadUnit] = []
	for u in _units:
		if not _unit_usable(u):
			continue
		if u.is_alive():
			out.append(u)
	return out


func get_hud_stats() -> Dictionary:
	_prune_units()
	var mages := 0
	var converted := 0
	var giant_out := false
	for u in _units:
		if not _unit_usable(u) or not u.is_alive():
			continue
		if u.is_giant():
			giant_out = true
			continue
		if u.role == UndeadUnit.Role.MINION:
			converted += 1
		else:
			## Mage (and any non-giant seeker still growing toward the pad).
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
	CityProfiler.end("undead")


func _scare_crowd_from_mages() -> void:
	if _city == null:
		return
	_prune_units()
	var threats: Array = []
	for u in _units:
		if not _unit_usable(u) or not u.is_alive() or not u.is_mage():
			continue
		threats.append(u.global_position)
	if threats.is_empty():
		return
	_city.scare_crowd_from_mages(threats, MAGE_FLEE_TRIGGER_M, MAGE_FLEE_CLEAR_M)


func spawn_wave() -> void:
	if _city == null:
		return
	_prune_units()
	var alive := _count_alive()
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
	print("UndeadInvasion: wave spawned=%d (alive=%d)" % [spawned, _count_alive()])


func spawn_minion_at(world_pos: Vector3) -> void:
	_prune_units()
	if _count_alive() >= MAX_ALIVE_UNITS:
		return
	if _count_role(UndeadUnit.Role.MINION) >= MAX_MINIONS:
		return
	_spawn_unit(UndeadUnit.Role.MINION, world_pos)


## Debug / N-key summon: spawn a named catalogue body at `world_pos` (caller supplies aim).
## Does not require invasion waves. Returns the unit, or null when nav / caps refuse.
func spawn_monster_by_id(body_id: String, world_pos: Vector3, body_seed: int = -1) -> UndeadUnit:
	if body_id.is_empty():
		push_error("UndeadInvasion.spawn_monster_by_id: empty body id")
		assert(false, "UndeadInvasion: empty body id")
		return null
	var entry: CreatureCatalog.Entry = CreatureCatalogScript.by_id(body_id)
	if entry == null:
		return null
	if not entry.is_spawnable():
		push_error(
			"UndeadInvasion.spawn_monster_by_id: '%s' is not spawnable (%s)"
			% [body_id, entry.note]
		)
		assert(false, "UndeadInvasion: body not spawnable")
		return null
	_prune_units()
	if _count_alive() >= MAX_ALIVE_UNITS:
		push_error("UndeadInvasion.spawn_monster_by_id: alive cap %d reached" % MAX_ALIVE_UNITS)
		return null
	var spawn_role := _role_for_entry(entry)
	return _spawn_unit(spawn_role, world_pos, body_seed, body_id)


static func _role_for_entry(entry: CreatureCatalog.Entry) -> UndeadUnit.Role:
	if entry.has_slot(CreatureCatalogScript.Slot.CASTER):
		return UndeadUnit.Role.MAGE
	if entry.has_slot(CreatureCatalogScript.Slot.FODDER):
		return UndeadUnit.Role.MINION
	if entry.has_slot(CreatureCatalogScript.Slot.BRUTE):
		return UndeadUnit.Role.MINION
	push_error("UndeadInvasion: '%s' has no role slot" % entry.id)
	assert(false, "UndeadInvasion: no role for body")
	return UndeadUnit.Role.MINION


func _count_alive() -> int:
	var n := 0
	for u in _units:
		if _unit_usable(u) and u.is_alive():
			n += 1
	return n


func _count_role(want_role: UndeadUnit.Role) -> int:
	var n := 0
	for u in _units:
		if not _unit_usable(u) or not u.is_alive() or u.is_giant():
			continue
		if u.role == want_role:
			n += 1
	return n


## Null when the nav world is not up yet: an undead with no span field to read would spend
## its whole life on the TRAPPED rung, which is noise rather than a signal.
##
## `body_seed` picks the model and every procedural variation on it. A negative one is
## rolled here, so ordinary waves are varied while a test can pin a body down, and
## `body_id` names a catalogue entry outright for a tool that wants one creature.
func _spawn_unit(
	spawn_role: UndeadUnit.Role,
	world_pos: Vector3,
	body_seed: int = -1,
	body_id: String = ""
) -> UndeadUnit:
	if not NavService.instance().is_configured():
		push_warning("UndeadInvasion: no undead spawned, the nav world is not built yet")
		return null
	var unit := UndeadUnit.new()
	unit.name = "Undead_%d" % _units.size()
	add_child(unit)
	unit.setup(
		spawn_role,
		self,
		_city,
		world_pos,
		_terrain,
		_lod,
		body_seed if body_seed >= 0 else randi(),
		body_id
	)
	unit.died.connect(_on_unit_died)
	## Safety net if something frees a body without going through `died`.
	unit.tree_exiting.connect(_on_unit_tree_exiting.bind(unit))
	_units.append(unit)
	return unit


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
	_city.adjust_player_score(-CONVERT_SCORE_PENALTY)
	spawn_minion_at(pos)
	return true


func query_segment_hit(from: Vector3, to: Vector3) -> Dictionary:
	## Aim / blaster can run any frame; never walk freed corpses left by a delayed queue_free.
	_prune_units()
	var best_dist := INF
	var best: Dictionary = {}
	var seg := to - from
	var seg_len := seg.length()
	if seg_len < 0.05:
		return best
	var dir := seg / seg_len
	for u in _units:
		if not _unit_usable(u) or not u.is_alive():
			continue
		var r := u.hit_radius()
		var hh := u.hit_half_height()
		var center := u.global_position + Vector3(0.0, hh * 0.85, 0.0)
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


## One hit on one body, which replaced `kill_unit` — a director that can still kill outright is
## a way for a hit to skip the health pool by accident. True when the hit landed, whether or not
## it killed: the caller only wants to know whether the shot was spent on a creature instead of
## on the wall behind it.
##
## The score is credited here and only on the hit that finishes the body, so a monster that now
## takes four punches is still worth fifty points once.
func damage_unit(unit: UndeadUnit, source: DamageSource.Id) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	if not unit.is_alive():
		return false
	_award(unit.apply_damage(source))
	return true


## Every living body standing inside a sphere takes one hit of `source`. The player's stomp is
## the only area attack in the game and this is what makes it one; the count is how many bodies
## it reached.
func damage_units_in_sphere(center: Vector3, radius: float, source: DamageSource.Id) -> int:
	_prune_units()
	var hit := 0
	## Snapshot: a body that dies to this stomp unregisters itself, and shrinking `_units`
	## mid-walk would skip the body standing behind it.
	var caught: Array[UndeadUnit] = _units.duplicate()
	for u in caught:
		if not _unit_usable(u) or not u.is_alive():
			continue
		var chest := u.global_position + Vector3(0.0, u.hit_half_height() * 0.85, 0.0)
		if chest.distance_to(center) > radius + u.hit_radius():
			continue
		_award(u.apply_damage(source))
		hit += 1
	return hit


func _award(score: int) -> void:
	if _city != null and score != 0:
		_city.adjust_player_score(score)


## Drop a registered body from the roster. Loud on double-remove — the list must not keep
## freed refs for aim / damage iterators to trip over.
func unregister_unit(unit: UndeadUnit) -> void:
	if unit == null:
		push_error("UndeadInvasion.unregister_unit: null unit")
		assert(false, "UndeadInvasion: unregister null")
		return
	var idx := _units.find(unit)
	if idx < 0:
		push_error(
			"UndeadInvasion.unregister_unit: '%s' was not registered (double-remove?)"
			% unit.name
		)
		assert(false, "UndeadInvasion: double unregister")
		return
	_units.remove_at(idx)
	if unit == _giant:
		_giant = null
	if unit == _giant_candidate:
		_giant_candidate = null


func _on_unit_died(unit: UndeadUnit, was_giant: bool) -> void:
	if was_giant:
		_giant = null
	## Unregister immediately on death so blaster aim cannot call into a queue_free'd body
	## during the death-clip delay. The corpse stays in the tree until its timer frees it.
	unregister_unit(unit)


func _on_unit_tree_exiting(unit: UndeadUnit) -> void:
	## Expected after `died` already unregistered. If still listed, something freed the node
	## without death — pull it out loudly so iterators stay clean.
	if unit == null or not _units.has(unit):
		return
	push_error(
		"UndeadInvasion: '%s' exited the tree while still registered — forcing unregister"
		% unit.name
	)
	unregister_unit(unit)


## True when `u` is a live Object we may call methods on. Drain-only guard for iterators;
## registration on death is what keeps the list clean.
func _unit_usable(u: UndeadUnit) -> bool:
	return u != null and is_instance_valid(u)


func _prune_units() -> void:
	var kept: Array[UndeadUnit] = []
	var dropped := 0
	for u in _units:
		if _unit_usable(u):
			kept.append(u)
		else:
			dropped += 1
	if dropped > 0:
		push_error(
			"UndeadInvasion._prune_units: dropped %d freed ref(s) — unregister-on-death missed"
			% dropped
		)
	_units = kept
	if _giant != null and not is_instance_valid(_giant):
		_giant = null
	if _giant_candidate != null and not is_instance_valid(_giant_candidate):
		_giant_candidate = null
