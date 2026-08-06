## Single undead station under a Graveyard chapel crypt.
##
## Same forever-war idea as a Monster Zoo pad: refill until a small alive cap, then slow
## down. No gazebo, turf plates, or cloak — the crypt floor is already the pad.
## Tuning lives in gamedata.json under `crypt`.
class_name CryptSpawner
extends Node3D

const META_OWNED := &"crypt_owned"

var spawn_world: Vector3 = Vector3.ZERO
var district_seed: int = 0

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
var _faction: String = "undead"


func setup(
	p_spawn_world: Vector3,
	p_district_seed: int,
	spawn_monster: Callable,
	alive_units: Callable,
	despawn_unit: Callable
) -> void:
	spawn_world = p_spawn_world
	district_seed = p_district_seed
	_spawn_cb = spawn_monster
	_units_cb = alive_units
	_despawn_cb = despawn_unit
	_rng.seed = district_seed ^ 0x0C297A
	name = "CryptSpawner"
	_read_constants()
	_build_roster()
	## First body soon after the tile streams in — not a full interval of empty crypt.
	_cd = _base_interval_sec * GameData.crypt_float("first_spawn_fraction")
	set_process(true)
	print("CryptSpawner: undead station at %s" % spawn_world)


func shutdown() -> void:
	set_process(false)
	_despawn_owned()


## The spire above this station came down. New bodies stop; the ones already walking the crypt
## keep walking it — breaking the tower is a lasting win, not an undo of the fight so far.
func stop_spawning() -> void:
	set_process(false)
	print("CryptSpawner: spire down, station closed at %s" % spawn_world)


func _exit_tree() -> void:
	_despawn_owned()


func _read_constants() -> void:
	_spawn_lift_m = GameData.crypt_float("spawn_lift_m")
	_base_interval_sec = GameData.crypt_float("base_spawn_interval_sec")
	_pressure_k = GameData.crypt_float("spawn_pressure_k")
	_alive_cap = GameData.crypt_int("alive_cap")
	_faction = GameData.crypt_string("faction")


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
	_bodies = CombatTable.spawnable_ids_for_faction(_faction)
	_weights.resize(_bodies.size())
	for i in range(_bodies.size()):
		_weights[i] = maxf(CombatTable.spawn_weight_for(_bodies[i]), 0.0)
	if _bodies.is_empty():
		push_error("CryptSpawner: no spawn_ready '%s' bodies in CombatTable" % _faction)


func _census() -> int:
	if not _units_cb.is_valid():
		return 0
	var n := 0
	for u: Variant in _units_cb.call() as Array:
		var unit := u as UndeadUnit
		if unit == null or not is_instance_valid(unit) or not unit.is_alive():
			continue
		if is_crypt_owned(unit):
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
	## No nav snap — pad is underground; snapping can yank the body through the mound.
	var unit: UndeadUnit = _spawn_cb.call(body, at, false) as UndeadUnit
	if unit == null or not is_instance_valid(unit):
		return false
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
	var doomed: Array[UndeadUnit] = []
	for u: Variant in _units_cb.call() as Array:
		var unit := u as UndeadUnit
		if unit == null or not is_instance_valid(unit):
			continue
		if is_crypt_owned(unit):
			doomed.append(unit)
	for unit in doomed:
		_despawn_cb.call(unit)


static func tag_unit(unit: Node) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	unit.set_meta(META_OWNED, true)


static func is_crypt_owned(unit: Node) -> bool:
	return (
		unit != null
		and is_instance_valid(unit)
		and unit.has_meta(META_OWNED)
		and bool(unit.get_meta(META_OWNED))
	)
