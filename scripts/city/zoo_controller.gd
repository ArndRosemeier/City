## Runtime owner of a Monster Zoo district: the forever war, the home-turf plates, and the
## spectator cloak at the gate.
##
## Unlike the Arena, nothing here waits on the player. The stations start ticking the moment
## the district streams in and keep going until it streams out, so arriving means walking
## into a fight already in progress. The only control the visitor has is the cloak, which
## buys them out of the target list — not out of the ground they are standing on.
class_name ZooController
extends Node3D

const ZooCloakGateScript := preload("res://scripts/city/zoo_cloak_gate.gd")
const ZooCombatScript := preload("res://scripts/city/zoo_combat.gd")
const MonsterFactionScript := preload("res://scripts/city/monster_faction.gd")
const DamageSourceScript := preload("res://scripts/city/damage_source.gd")

## How far above the pad a body is dropped, so it does not spawn inside the gravel.
const SPAWN_LIFT_M := 0.2
## Feet-to-floor probe depth in voxels when resolving which plate somebody stands on.
const FOOT_PROBE_VOX := 3

var layout: ZooLayout = null
var origin_vox: Vector3i = Vector3i.ZERO
var voxel_size: float = 0.5
var district_seed: int = 0

var _city: CityRoot = null
var _brush_cb: Callable = Callable()
var _spawn_cb: Callable = Callable()
var _units_cb: Callable = Callable()
var _despawn_cb: Callable = Callable()
var _gate: ZooCloakGate = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Authored forever-war tuning, read once at setup.
var _cloak_duration: float = 120.0
var _plate_interval: float = 1.0
var _base_interval: float = 14.0
var _pressure_k: float = 0.9
var _per_territory_cap: int = 2
var _district_cap: int = 34

## Seconds until each station may deliver its next body.
var _station_cd: PackedFloat32Array = PackedFloat32Array()
## `spawn_ready` body ids per monster faction index, and their matching pick weights.
var _faction_bodies: Array[PackedStringArray] = []
var _faction_weights: Array[PackedFloat32Array] = []
var _plate_acc: float = 0.0
var _cloak_left: float = 0.0
## True while this controller is the one holding the player out of the war.
var _owns_cloak: bool = false


func setup(
	p_layout: ZooLayout,
	p_origin_vox: Vector3i,
	p_voxel_size: float,
	p_district_seed: int,
	city: CityRoot,
	live_brush: Callable,
	spawn_monster: Callable,
	alive_units: Callable,
	despawn_unit: Callable
) -> void:
	layout = p_layout
	origin_vox = p_origin_vox
	voxel_size = p_voxel_size
	district_seed = p_district_seed
	_city = city
	_brush_cb = live_brush
	_spawn_cb = spawn_monster
	_units_cb = alive_units
	_despawn_cb = despawn_unit
	_rng.seed = district_seed ^ 0x200BEE
	name = "ZooController"
	if layout == null:
		push_error("ZooController.setup: null layout")
		assert(false, "ZooController: no layout")
		return
	if _city == null or not is_instance_valid(_city):
		push_error("ZooController.setup: the forever war needs CityRoot to spawn and damage")
		assert(false, "ZooController: no CityRoot")
		return
	_read_constants()
	_build_faction_rosters()
	_stagger_stations()
	_spawn_cloak_gate()
	set_process(true)
	print(
		"ZooController: forever war up — %d stations, base %.1fs, caps %d/territory %d/district"
		% [layout.territory_count(), _base_interval, _per_territory_cap, _district_cap]
	)


## Drop this district's war and hand the player back their own faction.
func shutdown() -> void:
	set_process(false)
	_end_cloak()
	_despawn_zoo_units()


func _exit_tree() -> void:
	## Streaming a tile out must never leave the player permanently un-huntable.
	_end_cloak()


func _process(delta: float) -> void:
	if layout == null or _city == null or not is_instance_valid(_city):
		return
	_tick_cloak(delta)
	_tick_war(delta)
	_tick_plates(delta)


# --- constants and rosters --------------------------------------------------

func _read_constants() -> void:
	_cloak_duration = GameData.zoo_float("cloak_duration_sec")
	_plate_interval = GameData.zoo_float("plate_damage_interval_sec")
	_base_interval = GameData.zoo_float("base_spawn_interval_sec")
	_pressure_k = GameData.zoo_float("spawn_pressure_k")
	_per_territory_cap = GameData.zoo_int("per_territory_cap")
	_district_cap = GameData.zoo_int("district_alive_cap")


## Resolve the spawn roster once. Doing this per station tick would re-walk the whole
## monster table forty times a minute for an answer that never changes.
func _build_faction_rosters() -> void:
	_faction_bodies.clear()
	_faction_weights.clear()
	for f in range(MonsterFactionScript.MONSTER_COUNT):
		var fname := MonsterFactionScript.faction_name(
			MonsterFactionScript.monster_faction_at(f)
		)
		var ids := CombatTable.spawnable_ids_for_faction(fname)
		var weights := PackedFloat32Array()
		weights.resize(ids.size())
		for i in range(ids.size()):
			weights[i] = maxf(CombatTable.spawn_weight_for(ids[i]), 0.0)
		_faction_bodies.append(ids)
		_faction_weights.append(weights)


## Spread the first delivery of forty stations over one base interval, or the district pops
## its whole population into existence on the frame it streams in.
func _stagger_stations() -> void:
	var n := layout.territory_count()
	_station_cd = PackedFloat32Array()
	_station_cd.resize(n)
	if n <= 0:
		return
	for i in range(n):
		_station_cd[i] = _base_interval * float(i) / float(n)


# --- forever war ------------------------------------------------------------

func _tick_war(delta: float) -> void:
	var n := _station_cd.size()
	if n <= 0:
		return
	var any_ready := false
	for i in range(n):
		_station_cd[i] -= delta
		if _station_cd[i] <= 0.0:
			any_ready = true
	if not any_ready:
		return
	var census := _census()
	var zoo_alive := 0
	for c in census:
		zoo_alive += c
	var global_alive := _global_alive()
	for i in range(n):
		if _station_cd[i] > 0.0:
			continue
		var living := census[i]
		## Emptied ground refills fast, held ground refills slowly. The winner of a cell
		## does not get to keep pouring bodies into it.
		_station_cd[i] = _base_interval * (1.0 + _pressure_k * float(living))
		if living >= _per_territory_cap:
			continue
		if zoo_alive >= _district_cap:
			continue
		if global_alive >= MonsterRoster.MAX_ALIVE_UNITS:
			continue
		if _spawn_at_station(i):
			census[i] += 1
			zoo_alive += 1
			global_alive += 1


## Living zoo bodies per territory index.
func _census() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(layout.territory_count())
	out.fill(0)
	if not _units_cb.is_valid():
		return out
	for u: Variant in _units_cb.call() as Array:
		var unit := u as UndeadUnit
		if unit == null or not is_instance_valid(unit) or not unit.is_alive():
			continue
		var t := ZooCombatScript.territory_of(unit)
		if t < 0 or t >= out.size():
			continue
		out[t] += 1
	return out


func _global_alive() -> int:
	if not _units_cb.is_valid():
		return 0
	return (_units_cb.call() as Array).size()


func _spawn_at_station(index: int) -> bool:
	var body := _pick_body(layout.seed_faction[index])
	if body.is_empty():
		return false
	var at := layout.spawner_world(index, origin_vox, voxel_size)
	at.y += SPAWN_LIFT_M
	var unit: UndeadUnit = _spawn_cb.call(body, at) as UndeadUnit
	if unit == null or not is_instance_valid(unit):
		return false
	ZooCombatScript.tag_unit(unit, index)
	return true


## Weighted pick among the faction's `spawn_ready` bodies.
func _pick_body(faction_index: int) -> String:
	if faction_index < 0 or faction_index >= _faction_bodies.size():
		push_error("ZooController._pick_body: territory rolled faction %d" % faction_index)
		return ""
	var ids := _faction_bodies[faction_index]
	if ids.is_empty():
		return ""
	var weights := _faction_weights[faction_index]
	var total := 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return ids[_rng.randi() % ids.size()]
	var roll := _rng.randf() * total
	for i in range(ids.size()):
		roll -= weights[i]
		if roll <= 0.0:
			return ids[i]
	return ids[ids.size() - 1]


# --- home turf --------------------------------------------------------------

func _tick_plates(delta: float) -> void:
	_plate_acc += delta
	if _plate_acc < _plate_interval:
		return
	_plate_acc = 0.0
	var brush: CityBrush = _brush_cb.call() as CityBrush if _brush_cb.is_valid() else null
	if brush == null:
		return
	if _units_cb.is_valid():
		for u: Variant in _units_cb.call() as Array:
			var unit := u as UndeadUnit
			if unit == null or not is_instance_valid(unit) or not unit.is_alive():
				continue
			var owner_f := _plate_faction_under(brush, unit.global_position)
			if owner_f < 0 or owner_f == unit.faction():
				continue
			## No attacker: the ground is not something a body can turn around and hit.
			unit.apply_damage_scaled(
				DamageSourceScript.Id.ZOO_PLATE_MOB, 1.0, "zoo turf", null
			)
	if not _city.is_player_alive():
		return
	var player := _city.get_player_node()
	if player == null or not is_instance_valid(player):
		return
	var here := _plate_faction_under(brush, (player as Node3D).global_position)
	if here < 0:
		return
	## The cloak hides the player from hunters, not from the floor.
	_city.damage_player(DamageSourceScript.Id.ZOO_PLATE)


## MonsterFaction.Id of the turf plate under `world`, or -1 when the floor is ordinary
## ground, another district, or the plate belongs to whoever is asking.
func _plate_faction_under(brush: CityBrush, world: Vector3) -> int:
	var vx := int(floor(world.x / voxel_size))
	var vy := int(floor(world.y / voxel_size))
	var vz := int(floor(world.z / voxel_size))
	for dy in range(0, FOOT_PROBE_VOX + 1):
		var id := brush.get_vox(Vector3i(vx, vy - dy, vz))
		if id == VoxelMaterial.AIR:
			continue
		if not VoxelMaterial.is_zoo_turf(id):
			return -1
		return int(
			MonsterFactionScript.monster_faction_at(VoxelMaterial.zoo_turf_faction_index(id))
		)
	return -1


# --- spectator cloak --------------------------------------------------------

func _spawn_cloak_gate() -> void:
	if layout.cloak_gate_vox.x < 0:
		push_error("ZooController: the zoo was built without a cloak gate mount")
		return
	var mount := layout.cloak_gate_vox
	var origin := Vector3(
		(float(origin_vox.x + mount.x) + 0.5) * voxel_size,
		float(origin_vox.y + mount.y + 1) * voxel_size + 1.1,
		(float(origin_vox.z + mount.z) + 0.5) * voxel_size
	)
	## Face back out of the gate, so the post is readable on the way in.
	var yaw := atan2(float(layout.gate_dir.x), float(layout.gate_dir.y))
	_gate = ZooCloakGateScript.new() as ZooCloakGate
	add_child(_gate)
	_gate.setup_gate(origin, yaw)
	_gate.cloak_requested.connect(request_cloak)
	_gate.set_cloak_active(false, 0.0)


## Grant, or refresh, the spectator cloak. Re-pressing the gate resets the full duration
## rather than stacking — one rule, and it is the one the countdown shows.
func request_cloak() -> void:
	if _city == null or not is_instance_valid(_city) or not _city.is_player_alive():
		return
	_city.set_player_combat_faction(int(MonsterFactionScript.Id.SPECTATOR))
	_cloak_left = _cloak_duration
	_owns_cloak = true
	_city.show_zoo_cloak(_cloak_left)
	if _gate != null and is_instance_valid(_gate):
		_gate.set_cloak_active(true, _cloak_left)


func cloak_seconds_left() -> float:
	return _cloak_left


func _tick_cloak(delta: float) -> void:
	if not _owns_cloak:
		return
	_cloak_left -= delta
	if _cloak_left <= 0.0:
		_end_cloak()
		return
	_city.show_zoo_cloak(_cloak_left)
	if _gate != null and is_instance_valid(_gate):
		_gate.set_cloak_active(true, _cloak_left)


func _end_cloak() -> void:
	if not _owns_cloak:
		return
	_owns_cloak = false
	_cloak_left = 0.0
	if _city != null and is_instance_valid(_city):
		_city.set_player_combat_faction(int(MonsterFactionScript.Id.HUMAN))
		_city.hide_zoo_cloak()
	if _gate != null and is_instance_valid(_gate):
		_gate.set_cloak_active(false, 0.0)


func _despawn_zoo_units() -> void:
	if not _units_cb.is_valid():
		return
	## Snapshot — despawning unregisters and mutates the roster's list.
	var units: Array = (_units_cb.call() as Array).duplicate()
	for u in units:
		var unit := u as UndeadUnit
		if unit == null or not is_instance_valid(unit):
			continue
		if not ZooCombatScript.is_zoo_owned(unit):
			continue
		if _despawn_cb.is_valid():
			_despawn_cb.call(unit)
		else:
			push_error("ZooController._despawn_zoo_units: no despawn callback")
			unit.queue_free()
