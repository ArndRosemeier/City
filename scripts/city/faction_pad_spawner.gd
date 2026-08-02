## One forever-war pad for a single combat faction.
##
## Castle dungeon summoners use this with a rolled faction and `dungeon_summoner` tuning.
## Each pad owns its bodies via a unique meta key so two pads do not share one alive-cap.
class_name FactionPadSpawner
extends Node3D

var spawn_world: Vector3 = Vector3.ZERO
var district_seed: int = 0
var faction: String = ""

var _spawn_cb: Callable = Callable()
var _units_cb: Callable = Callable()
var _despawn_cb: Callable = Callable()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _bodies: PackedStringArray = PackedStringArray()
var _weights: PackedFloat32Array = PackedFloat32Array()
var _cd: float = 0.0
var _spawn_lift_m: float = 0.2
var _base_interval_sec: float = 30.0
var _pressure_k: float = 0.9
var _alive_cap: int = 20
## Tallest body this pad's room can take, in metres. Anything drawn taller is shrunk to fit
## on spawn instead of standing wedged in the slab.
var _max_height_m: float = 0.0
var _tuning_section: String = "dungeon_summoner"
var _owner_meta: StringName = &"faction_pad_owned"


func setup(
	p_spawn_world: Vector3,
	p_district_seed: int,
	spawn_monster: Callable,
	alive_units: Callable,
	despawn_unit: Callable,
	p_faction: String,
	p_tuning_section: String,
	p_owner_meta: StringName,
	p_node_name: String = "FactionPadSpawner"
) -> void:
	if p_faction.strip_edges().is_empty():
		push_error("FactionPadSpawner.setup: faction is required")
		assert(false, "FactionPadSpawner: empty faction")
		return
	if p_tuning_section.strip_edges().is_empty():
		push_error("FactionPadSpawner.setup: tuning section is required")
		assert(false, "FactionPadSpawner: empty tuning section")
		return
	if String(p_owner_meta).is_empty():
		push_error("FactionPadSpawner.setup: owner meta is required")
		assert(false, "FactionPadSpawner: empty owner meta")
		return
	spawn_world = p_spawn_world
	district_seed = p_district_seed
	faction = p_faction
	_tuning_section = p_tuning_section
	_owner_meta = p_owner_meta
	_spawn_cb = spawn_monster
	_units_cb = alive_units
	_despawn_cb = despawn_unit
	_rng.seed = district_seed ^ int(hash(String(p_owner_meta)))
	name = p_node_name
	_read_constants()
	_build_roster()
	## First body soon after the tile streams in — not a full interval of empty pad.
	_cd = _base_interval_sec * GameData.section_float(_tuning_section, "first_spawn_fraction")
	set_process(true)
	print(
		"FactionPadSpawner: %s station (%s) at %s"
		% [faction, _tuning_section, spawn_world]
	)


func shutdown() -> void:
	set_process(false)
	_despawn_owned()


func _exit_tree() -> void:
	_despawn_owned()


func _read_constants() -> void:
	_spawn_lift_m = GameData.section_float(_tuning_section, "spawn_lift_m")
	_base_interval_sec = GameData.section_float(_tuning_section, "base_spawn_interval_sec")
	_pressure_k = GameData.section_float(_tuning_section, "spawn_pressure_k")
	_alive_cap = GameData.section_int(_tuning_section, "alive_cap")
	_max_height_m = GameData.section_float(_tuning_section, "max_height_m")
	if _max_height_m <= 0.0:
		push_error(
			"FactionPadSpawner: %s.max_height_m must be positive, got %.2f"
			% [_tuning_section, _max_height_m]
		)
		assert(false, "FactionPadSpawner: bad max_height_m")


func _process(delta: float) -> void:
	_cd -= delta
	if _cd > 0.0:
		return
	var living := _census()
	_cd = _base_interval_sec * (1.0 + _pressure_k * float(living))
	if living >= _alive_cap:
		return
	if _global_alive() >= MonsterRoster.MAX_ALIVE_UNITS:
		return
	_spawn_one()


func _build_roster() -> void:
	_bodies = CombatTable.spawnable_ids_for_faction(faction)
	_weights.resize(_bodies.size())
	for i in range(_bodies.size()):
		_weights[i] = maxf(CombatTable.spawn_weight_for(_bodies[i]), 0.0)
	if _bodies.is_empty():
		push_error(
			"FactionPadSpawner: no spawn_ready '%s' bodies in CombatTable" % faction
		)


func _census() -> int:
	if not _units_cb.is_valid():
		return 0
	var n := 0
	for u: Variant in _units_cb.call() as Array:
		var unit: Node = u as Node
		if unit == null or not is_instance_valid(unit):
			continue
		if not bool(unit.call("is_alive")):
			continue
		if is_owned(unit):
			n += 1
	return n


func _global_alive() -> int:
	if not _units_cb.is_valid():
		return 0
	return (_units_cb.call() as Array).size()


func _spawn_one() -> bool:
	var body := _pick_body()
	if body.is_empty():
		return false
	var at := spawn_world + Vector3(0.0, _spawn_lift_m, 0.0)
	## No nav snap — pads are underground; snapping can yank the body through the ceiling.
	var unit: UndeadUnit = _spawn_cb.call(body, at, false) as UndeadUnit
	if unit == null or not is_instance_valid(unit):
		return false
	unit.clamp_standing_height(_max_height_m)
	tag_unit(unit)
	return true


func _pick_body() -> String:
	if _bodies.is_empty():
		return ""
	var total := 0.0
	for w in _weights:
		total += w
	if total <= 0.0:
		return _bodies[_rng.randi() % _bodies.size()]
	var roll := _rng.randf() * total
	for i in range(_bodies.size()):
		roll -= _weights[i]
		if roll <= 0.0:
			return _bodies[i]
	return _bodies[_bodies.size() - 1]


func _despawn_owned() -> void:
	if not _units_cb.is_valid() or not _despawn_cb.is_valid():
		return
	var doomed: Array[Node] = []
	for u: Variant in _units_cb.call() as Array:
		var unit: Node = u as Node
		if unit == null or not is_instance_valid(unit):
			continue
		if is_owned(unit):
			doomed.append(unit)
	for unit in doomed:
		_despawn_cb.call(unit)


func tag_unit(unit: Node) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	unit.set_meta(_owner_meta, true)


func is_owned(unit: Node) -> bool:
	return (
		unit != null
		and is_instance_valid(unit)
		and unit.has_meta(_owner_meta)
		and bool(unit.get_meta(_owner_meta))
	)
