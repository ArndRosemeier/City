## Runtime owner of a Siege Quarter: the pot, the waves, the Lodestone, and the player's
## temporary `SIEGE_DEFENDER` allegiance.
##
## Player-initiated, like the Arena. Streaming the tile in only stands the controller up;
## nothing spawns until `start_run` stakes gems into the pot. Kill hauls during a run feed
## the pot (via `CityRoot.grant_monster_kill_haul`); withdrawing banks it, and losing the
## Lodestone burns it.
class_name SiegeController
extends Node3D

const MonsterFactionScript := preload("res://scripts/city/monster_faction.gd")
const CombatTableScript := preload("res://scripts/city/combat_table.gd")
const InventoryCatalogScript := preload("res://scripts/city/inventory_catalog.gd")
const SiegeLodestonePanelScript := preload("res://scripts/city/siege_lodestone_panel.gd")
const SiegePadPanelScript := preload("res://scripts/city/siege_pad_panel.gd")
const SiegeTowerCatalogScript := preload("res://scripts/city/siege_tower_catalog.gd")
const MonsterRosterScript := preload("res://scripts/city/monster_roster.gd")

## How far above a gate mouth a body is dropped.
const SPAWN_LIFT_M := 0.2
## Floor under the authored vulnerability radius, measured out from the crystal's shell. The
## crystal is solid, so the radius has to clear it by more than UndeadGoalProvider's ring inset
## — otherwise attackers would be sent to stand inside GLASS_LIT and dance around it instead.
const LODESTONE_RADIUS_SLACK_M := 1.6
## Panel centre height above the Lodestone base, and how far out from the crystal it stands.
const PANEL_HEIGHT_M := 1.7
const PANEL_CLEARANCE_M := 1.4
## Clearance between the pad's top face and the lay-flat "+" plate, so its collider and mesh do
## not z-fight the foundation voxels.
const PAD_PLATE_LIFT_M := 0.05

enum Phase {
	IDLE,
	INTERMISSION,
	WAVE,
	LOST,
	WITHDRAWN,
}

var layout: SiegeLayout = null
var origin_vox: Vector3i = Vector3i.ZERO
var voxel_size: float = 0.5
var district_seed: int = 0

## CityRoot in the live game; a duck-typed stand-in is enough for the pot tests.
var _city: Node = null
var _spawn_cb: Callable = Callable()
var _units_cb: Callable = Callable()
var _despawn_cb: Callable = Callable()
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _phase: Phase = Phase.IDLE
var _wave: int = 0
var _intermission_left: float = 0.0
var _spawn_queue: PackedStringArray = PackedStringArray()
var _spawn_cd: float = 0.0
## Living attackers this controller owns this run.
var _alive: Array[UndeadUnit] = []
## Living towers (meshless UndeadUnits) owned by this run.
var _towers: Array[UndeadUnit] = []
## pad_index → tower unit (or null when empty).
var _pad_tower: Dictionary = {}
## pad_index → the lay-flat "+" plate on that pad. Untyped: these are preload instances, and a
## `class_name` element type here has to resolve before the script cache is warm.
var _pad_panels: Array = []

## item_id → count. Session-local; never touches inventory until withdraw or is lost on fail.
var _pot: Dictionary = {}
var _lodestone_hp: float = 0.0
var _lodestone_hp_max: float = 0.0
var _owns_defender_faction: bool = false
var _shutting_down: bool = false
var _panel: SiegeLodestonePanel = null
var _panel_refresh_acc: float = 0.0

## Authored tuning, read once at setup.
var _min_stake_total: int = 5
var _lodestone_base_hp: float = 400.0
var _lodestone_vuln_radius_m: float = 5.0
var _intermission_sec: float = 8.0
var _base_wave_size: int = 6
var _wave_size_growth: int = 2
var _district_cap: int = 34
var _spawn_interval_sec: float = 0.55
var _hp_growth: float = 0.12
var _damage_growth: float = 0.08
var _lodestone_dps_per_attacker: float = 8.0
var _source_factions: PackedStringArray = PackedStringArray()
var _roster: PackedStringArray = PackedStringArray()
var _roster_weights: PackedFloat32Array = PackedFloat32Array()


func setup(
	p_layout: SiegeLayout,
	p_origin_vox: Vector3i,
	p_voxel_size: float,
	p_district_seed: int,
	city: Node,
	spawn_monster: Callable,
	alive_units: Callable,
	despawn_unit: Callable
) -> void:
	layout = p_layout
	origin_vox = p_origin_vox
	voxel_size = p_voxel_size
	district_seed = p_district_seed
	_city = city
	_spawn_cb = spawn_monster
	_units_cb = alive_units
	_despawn_cb = despawn_unit
	_rng.seed = district_seed ^ 0x51E6E
	name = "SiegeController"
	if layout == null or not layout.is_valid():
		push_error("SiegeController.setup: layout is missing or unusable")
		assert(false, "SiegeController: bad layout")
		return
	if _city == null or not is_instance_valid(_city):
		push_error("SiegeController.setup: needs CityRoot")
		assert(false, "SiegeController: no CityRoot")
		return
	_read_constants()
	_build_roster()
	_phase = Phase.IDLE
	_spawn_lodestone_panel()
	set_process(true)
	print(
		"SiegeController: ready — %s, roster=%d bodies, min_stake=%d"
		% [layout.describe(), _roster.size(), _min_stake_total]
	)


func shutdown() -> void:
	if _shutting_down:
		return
	_shutting_down = true
	## Streaming a tile out must never leave the player stuck as SIEGE_DEFENDER, and a pot
	## that was never withdrawn is gone with the district — that is the risk of the mode.
	if is_running():
		_pot.clear()
		_phase = Phase.LOST
	_end_run(true)
	set_process(false)


func _exit_tree() -> void:
	shutdown()


func is_running() -> bool:
	return _phase == Phase.INTERMISSION or _phase == Phase.WAVE


func phase() -> Phase:
	return _phase


func wave_number() -> int:
	return _wave


func pot_snapshot() -> Dictionary:
	return _pot.duplicate()


func pot_total() -> int:
	var n := 0
	for k: Variant in _pot.keys():
		n += int(_pot[k])
	return n


func lodestone_hp() -> float:
	return _lodestone_hp


func lodestone_hp_max() -> float:
	return _lodestone_hp_max


func min_stake_total() -> int:
	return _min_stake_total


func intermission_left() -> float:
	return _intermission_left


func alive_count() -> int:
	return _alive.size()


func inventory() -> PlayerInventory:
	if _city == null or not is_instance_valid(_city) or not _city.has_method("get_inventory"):
		return null
	return _city.call("get_inventory") as PlayerInventory


func lodestone_world_pos() -> Vector3:
	var w := layout.lodestone_world(origin_vox)
	return Vector3(
		(float(w.x) + 0.5) * voxel_size,
		float(w.y) * voxel_size,
		(float(w.z) + 0.5) * voxel_size
	)


## Compact stats for SiegeHud. `active` is false outside INTERMISSION/WAVE.
func get_hud_stats() -> Dictionary:
	return {
		"active": is_running(),
		"phase": int(_phase),
		"wave": _wave,
		"pot_total": pot_total(),
		"pot": pot_snapshot(),
		"lodestone_hp": _lodestone_hp,
		"lodestone_hp_max": _lodestone_hp_max,
		"intermission_left": _intermission_left,
		"alive": _alive.size(),
		"queued": _spawn_queue.size(),
	}


## Stake gems from inventory and open the run. `stake` is item_id → count. False when the
## stake is short, the inventory cannot cover it, or a run is already live.
func start_run(stake: Dictionary) -> bool:
	if is_running():
		push_error("SiegeController.start_run: a run is already live")
		return false
	if _phase == Phase.LOST or _phase == Phase.WITHDRAWN:
		## A finished controller can be restarted after a withdraw; a loss leaves the tile
		## idle until the player stakes again.
		_phase = Phase.IDLE
	var total := 0
	for k: Variant in stake.keys():
		var item_id := String(k)
		var n := int(stake[k])
		if n <= 0:
			continue
		if not InventoryCatalogScript.has_item(item_id):
			push_error("SiegeController.start_run: unknown item '%s'" % item_id)
			return false
		total += n
	if total < _min_stake_total:
		push_error(
			"SiegeController.start_run: stake %d is below the minimum %d"
			% [total, _min_stake_total]
		)
		return false
	var inv: PlayerInventory = _city.call("get_inventory") as PlayerInventory
	if inv == null:
		push_error("SiegeController.start_run: no inventory")
		return false
	for k: Variant in stake.keys():
		var item_id := String(k)
		var n := int(stake[k])
		if n <= 0:
			continue
		if inv.count_of(item_id) < n:
			push_error(
				"SiegeController.start_run: need %d × %s, have %d"
				% [n, item_id, inv.count_of(item_id)]
			)
			return false
	## Pull only after every check passes — a short stake must not drain part of a bag.
	_pot.clear()
	for k: Variant in stake.keys():
		var item_id := String(k)
		var n := int(stake[k])
		if n <= 0:
			continue
		if not inv.remove(item_id, n):
			push_error("SiegeController.start_run: remove failed for %s" % item_id)
			assert(false, "SiegeController: inventory remove failed after count check")
			return false
		_pot[item_id] = int(_pot.get(item_id, 0)) + n

	_lodestone_hp_max = _lodestone_base_hp
	_lodestone_hp = _lodestone_hp_max
	_wave = 0
	_alive.clear()
	_spawn_queue.clear()
	_city.call("begin_siege_run", self)
	_city.call(
		"set_player_combat_faction", int(MonsterFactionScript.Id.SIEGE_DEFENDER)
	)
	_owns_defender_faction = true
	_clear_towers()
	## Phase first: a pad console builds its face from `is_running()`, so spawning the
	## consoles before the intermission opens leaves every one of them empty.
	_begin_intermission()
	_spawn_pad_panels()
	_refresh_panel()
	print(
		"SiegeController: run started — pot=%d gems, lodestone=%.0f hp"
		% [pot_total(), _lodestone_hp_max]
	)
	return true


## Bank the pot into inventory and end the run. Only legal between waves.
func withdraw() -> bool:
	if _phase != Phase.INTERMISSION:
		push_error("SiegeController.withdraw: only between waves (phase=%d)" % int(_phase))
		return false
	var inv: PlayerInventory = _city.call("get_inventory") as PlayerInventory
	if inv == null:
		push_error("SiegeController.withdraw: no inventory")
		return false
	for k: Variant in _pot.keys():
		var item_id := String(k)
		var n := int(_pot[k])
		if n <= 0:
			continue
		var leftover := inv.add(item_id, n)
		if leftover != 0:
			push_error(
				"SiegeController.withdraw: inventory full — %d × %s left unbanked"
				% [leftover, item_id]
			)
	_pot.clear()
	_phase = Phase.WITHDRAWN
	_end_run(true)
	_refresh_panel()
	print("SiegeController: withdrew — banked and cleared the field")
	return true


## Credit VoxelMaterial gem ids into the pot. Returns how many stones were accepted.
func credit_kill_mats(mats: Array[int]) -> int:
	if not is_running():
		return 0
	var paid := 0
	for mat in mats:
		var item_id := InventoryCatalogScript.item_id_for_gem(mat)
		if item_id.is_empty():
			continue
		_pot[item_id] = int(_pot.get(item_id, 0)) + 1
		paid += 1
	if paid > 0:
		_refresh_pad_panels()
	return paid


## Spend from the pot (tower purchase). False when the pot cannot cover the cost.
func spend_from_pot(cost: Dictionary) -> bool:
	if not is_running():
		push_error("SiegeController.spend_from_pot: no run")
		return false
	if not can_afford(cost):
		return false
	for k: Variant in cost.keys():
		var item_id := String(k)
		var n := int(cost[k])
		if n <= 0:
			continue
		_pot[item_id] = int(_pot[item_id]) - n
		if int(_pot[item_id]) <= 0:
			_pot.erase(item_id)
	return true


func can_afford(cost: Dictionary) -> bool:
	if not is_running():
		return false
	for k: Variant in cost.keys():
		var item_id := String(k)
		var n := int(cost[k])
		if n <= 0:
			continue
		if int(_pot.get(item_id, 0)) < n:
			return false
	return true


## Buy `tower_id` onto an empty pad. Stamps voxels, spawns the combat host, spends the pot.
func build_tower(pad_index: int, tower_id: String) -> bool:
	if not is_running():
		push_error("SiegeController.build_tower: no run")
		return false
	if layout == null or pad_index < 0 or pad_index >= layout.pad_count():
		push_error("SiegeController.build_tower: bad pad %d" % pad_index)
		return false
	if _pad_tower.get(pad_index, null) != null:
		push_error("SiegeController.build_tower: pad %d is occupied" % pad_index)
		return false
	var def: RefCounted = SiegeTowerCatalogScript.by_id(tower_id) as RefCounted
	if def == null:
		return false
	var cost: Dictionary = def.get("cost") as Dictionary
	## A short pot is a legal player miss, not a fault — the pad console shows the price and
	## mutes its BUILD. Everything below this line is a genuine error if it fails.
	if not spend_from_pot(cost):
		return false
	var pad_world := _pad_world_pos(pad_index)
	var brush: CityBrush = _city.call("voxel_brush") as CityBrush
	var terrain: VoxelTerrain = _city.call("voxel_terrain") as VoxelTerrain
	if brush == null or terrain == null:
		push_error("SiegeController.build_tower: city has no brush/terrain")
		## Refund — we already deducted.
		for k: Variant in cost.keys():
			_pot[String(k)] = int(_pot.get(String(k), 0)) + int(cost[k])
		return false
	var written: int = int(
		SiegeTowerCatalogScript.stamp_at(terrain, brush, def, pad_world)
	)
	if written <= 0:
		push_error("SiegeController.build_tower: stamp wrote nothing for '%s'" % tower_id)
		for k: Variant in cost.keys():
			_pot[String(k)] = int(_pot.get(String(k), 0)) + int(cost[k])
		return false
	var combat_id := str(def.get("combat_id"))
	var hp := float(def.get("hp"))
	var unit: UndeadUnit = null
	if _city.has_method("spawn_siege_tower_at"):
		unit = _city.call(
			"spawn_siege_tower_at", combat_id, pad_world + Vector3(0.0, 0.6, 0.0), hp
		) as UndeadUnit
	if unit == null or not is_instance_valid(unit):
		push_error("SiegeController.build_tower: spawn failed for '%s'" % combat_id)
		for k: Variant in cost.keys():
			_pot[String(k)] = int(_pot.get(String(k), 0)) + int(cost[k])
		return false
	_towers.append(unit)
	_pad_tower[pad_index] = unit
	unit.died.connect(_on_tower_died.bind(pad_index))
	_hide_pad_panel(pad_index)
	_refresh_panel()
	_refresh_pad_panels()
	print(
		"SiegeController: built %s on pad %d — pot now %d"
		% [str(def.get("display_name")), pad_index, pot_total()]
	)
	return true


func _process(delta: float) -> void:
	if layout == null or _city == null or not is_instance_valid(_city):
		return
	if is_running():
		_prune_alive()
		match _phase:
			Phase.INTERMISSION:
				_intermission_left -= delta
				if _intermission_left <= 0.0:
					_begin_wave()
			Phase.WAVE:
				_tick_spawns(delta)
				_tick_lodestone(delta)
				if _spawn_queue.is_empty() and _alive.is_empty() and _lodestone_hp > 0.0:
					_begin_intermission()
	## Panel clock / HP readout — labels only; full face rebuilds happen on phase changes.
	_panel_refresh_acc += delta
	if _panel_refresh_acc >= 0.25:
		_panel_refresh_acc = 0.0
		if _panel != null and is_instance_valid(_panel):
			_panel.tick_display()


func _begin_intermission() -> void:
	_phase = Phase.INTERMISSION
	_intermission_left = _intermission_sec
	_refresh_panel()
	print(
		"SiegeController: intermission %.1fs after wave %d — pot=%d"
		% [_intermission_sec, _wave, pot_total()]
	)


func _begin_wave() -> void:
	_wave += 1
	_phase = Phase.WAVE
	var size := mini(_base_wave_size + (_wave - 1) * _wave_size_growth, _district_cap)
	_spawn_queue.clear()
	for _i in range(size):
		_spawn_queue.append(_pick_body())
	_spawn_cd = 0.0
	_refresh_panel()
	print(
		"SiegeController: wave %d — %d bodies, hp×%.2f dmg×%.2f"
		% [_wave, size, _wave_hp_mult(), _wave_damage_mult()]
	)


func _tick_spawns(delta: float) -> void:
	if _spawn_queue.is_empty():
		return
	_spawn_cd -= delta
	if _spawn_cd > 0.0:
		return
	if _alive.size() >= _district_cap:
		_spawn_cd = _spawn_interval_sec
		return
	## Same soft hold Zoo uses: a full city roster is temporary pressure. Keep the body on the
	## queue and try again next tick — dequeuing on a null spawn used to erase wave members
	## and flood the ErrorOverlay with "alive cap reached".
	if _global_alive() >= MonsterRosterScript.MAX_ALIVE_UNITS:
		_spawn_cd = _spawn_interval_sec
		return
	var body_id := _spawn_queue[0]
	if not _spawn_attacker(body_id):
		_spawn_cd = _spawn_interval_sec
		return
	_spawn_queue.remove_at(0)
	_spawn_cd = _spawn_interval_sec


func _global_alive() -> int:
	if not _units_cb.is_valid():
		return _alive.size()
	return (_units_cb.call() as Array).size()


## False when the roster refused (cap / nav). The body stays queued for a later tick.
func _spawn_attacker(body_id: String) -> bool:
	if not _spawn_cb.is_valid() or layout.gate_count() <= 0:
		return false
	var gate_i := int(_rng.randi() % layout.gate_count())
	var gw := layout.gate_world(gate_i, origin_vox)
	var pos := Vector3(
		(float(gw.x) + 0.5) * voxel_size,
		float(gw.y) * voxel_size + SPAWN_LIFT_M,
		(float(gw.z) + 0.5) * voxel_size
	)
	## Outside the mouth by one cell so the body is not born inside the barricade ring.
	var outward := layout.gate_dirs[gate_i] * -1
	pos += Vector3(float(outward.x), 0.0, float(outward.y)) * voxel_size * 3.0
	var unit: UndeadUnit = _spawn_cb.call(body_id, pos, true) as UndeadUnit
	if unit == null or not is_instance_valid(unit):
		return false
	unit.set_faction(int(MonsterFactionScript.Id.SIEGE_ATTACKER))
	## Hold radius *is* the vulnerability radius — see `lodestone_vulnerable_radius_m`.
	unit.set_push_aim(lodestone_world_pos(), lodestone_vulnerable_radius_m())
	unit.scale_for_wave(_wave_hp_mult(), _wave_damage_mult())
	_alive.append(unit)
	return true


## Flat metres from the Lodestone centre in which an attacker both **stops walking** and
## **deals contact damage**.
##
## The Lodestone has no collider and attackers have no weapon hitbox, so "did the swing
## connect" is answered by this one authored number instead. Holding and hurting have to
## share it: when the stop radius was tighter than the damage radius, bodies parked in the
## gap between them, kept being handed a fresh corridor, and circled the crystal forever.
func lodestone_vulnerable_radius_m() -> float:
	var crystal := float(layout.lodestone_radius_vox) * voxel_size
	return maxf(_lodestone_vuln_radius_m, crystal + LODESTONE_RADIUS_SLACK_M)


func _tick_lodestone(delta: float) -> void:
	if _lodestone_hp <= 0.0:
		return
	var aim := lodestone_world_pos()
	var hit_m := lodestone_vulnerable_radius_m()
	var hit_r2 := hit_m * hit_m
	var chewers := 0
	for unit: UndeadUnit in _alive:
		if unit == null or not is_instance_valid(unit) or not unit.is_alive():
			continue
		var d2 := Vector2(
			unit.global_position.x - aim.x, unit.global_position.z - aim.z
		).length_squared()
		if d2 <= hit_r2:
			chewers += 1
	if chewers <= 0:
		return
	_lodestone_hp -= float(chewers) * _lodestone_dps_per_attacker * delta
	if _lodestone_hp <= 0.0:
		_lodestone_hp = 0.0
		_on_lodestone_destroyed()


func _on_lodestone_destroyed() -> void:
	print(
		"SiegeController: Lodestone fell on wave %d — pot of %d gems is lost"
		% [_wave, pot_total()]
	)
	_pot.clear()
	_phase = Phase.LOST
	_end_run(true)
	_refresh_panel()


func _end_run(despawn_field: bool) -> void:
	if _owns_defender_faction and _city != null and is_instance_valid(_city):
		_city.call("set_player_combat_faction", int(MonsterFactionScript.Id.HUMAN))
		_city.call("end_siege_run", self)
	_owns_defender_faction = false
	_spawn_queue.clear()
	if despawn_field:
		_despawn_alive()
		_clear_towers()
	_alive.clear()
	_clear_pad_panels()


func _despawn_alive() -> void:
	for unit: UndeadUnit in _alive:
		if unit == null or not is_instance_valid(unit):
			continue
		if _despawn_cb.is_valid():
			_despawn_cb.call(unit)
		elif unit.is_alive():
			unit.queue_free()


func _prune_alive() -> void:
	var kept: Array[UndeadUnit] = []
	for unit: UndeadUnit in _alive:
		if unit != null and is_instance_valid(unit) and unit.is_alive():
			kept.append(unit)
	_alive = kept


func _wave_hp_mult() -> float:
	return 1.0 + _hp_growth * float(_wave - 1)


func _wave_damage_mult() -> float:
	return 1.0 + _damage_growth * float(_wave - 1)


func _read_constants() -> void:
	_min_stake_total = GameData.siege_int("min_stake_total")
	_lodestone_base_hp = GameData.siege_float("lodestone_hp")
	_lodestone_vuln_radius_m = GameData.siege_float("lodestone_vulnerable_radius_m")
	_intermission_sec = GameData.siege_float("intermission_sec")
	_base_wave_size = GameData.siege_int("base_wave_size")
	_wave_size_growth = GameData.siege_int("wave_size_growth")
	_district_cap = GameData.siege_int("district_alive_cap")
	_spawn_interval_sec = GameData.siege_float("spawn_interval_sec")
	_hp_growth = GameData.siege_float("hp_growth_per_wave")
	_damage_growth = GameData.siege_float("damage_growth_per_wave")
	_lodestone_dps_per_attacker = GameData.siege_float("lodestone_dps_per_attacker")
	var raw: Variant = GameData.siege().get("source_factions", [])
	_source_factions = PackedStringArray()
	if typeof(raw) == TYPE_ARRAY:
		for entry: Variant in raw as Array:
			_source_factions.append(String(entry))
	if _source_factions.is_empty():
		_source_factions = PackedStringArray(["undead", "horde", "beast", "infernal"])


func _build_roster() -> void:
	_roster = PackedStringArray()
	_roster_weights = PackedFloat32Array()
	for fname: String in _source_factions:
		var ids := CombatTableScript.spawnable_ids_for_faction(fname)
		for id: String in ids:
			_roster.append(id)
			_roster_weights.append(maxf(CombatTableScript.spawn_weight_for(id), 0.01))
	if _roster.is_empty():
		push_error("SiegeController: no spawn_ready bodies in source_factions")
		assert(false, "SiegeController: empty roster")


func _pick_body() -> String:
	if _roster.is_empty():
		return ""
	var total := 0.0
	for w in _roster_weights:
		total += w
	var roll := _rng.randf() * total
	var acc := 0.0
	for i in range(_roster.size()):
		acc += _roster_weights[i]
		if roll <= acc:
			return _roster[i]
	return _roster[_roster.size() - 1]


# --- Pads / towers ----------------------------------------------------------

func _pad_world_pos(pad_index: int) -> Vector3:
	var w := layout.pad_world(pad_index, origin_vox)
	return Vector3(
		(float(w.x) + 0.5) * voxel_size,
		float(w.y) * voxel_size,
		(float(w.z) + 0.5) * voxel_size
	)


func _spawn_pad_panels() -> void:
	_clear_pad_panels()
	if layout == null:
		return
	var lode := lodestone_world_pos()
	for i in range(layout.pad_count()):
		var pad := _pad_world_pos(i)
		var outward := Vector2(pad.x - lode.x, pad.z - lode.z)
		if outward.length_squared() < 0.01:
			outward = Vector2(0.0, 1.0)
		outward = outward.normalized()
		## Yaw only spins the square plate around its own centre, but keep it approach-relative
		## so the "+" glyph reads upright from where the player stands (see Ui3D class doc).
		var yaw := atan2(-outward.x, -outward.y)
		## `_pad_world_pos` returns the solid plate cell, so the marker goes a hair above its
		## top face — inside the cell it would be buried in the foundation.
		var origin := pad + Vector3.UP * (voxel_size + PAD_PLATE_LIFT_M)
		var panel: Node = SiegePadPanelScript.new() as Node
		add_child(panel)
		panel.call("setup_pad", origin, yaw, i)
		panel.connect("pad_pressed", _on_pad_pressed)
		_pad_panels.append(panel)


## Pad caption for the build picker: elevation is the pad's whole identity, so say it before
## the player spends a gem.
func pad_kind_label(pad_index: int) -> String:
	match layout.pad_kind_at(pad_index):
		SiegeLayout.PadKind.STREET:
			return "STREET PAD"
		SiegeLayout.PadKind.ROOF_JUMP:
			return "ROOF PAD"
		SiegeLayout.PadKind.ROOF_HIGH:
			return "HIGH ROOF PAD"
	push_error("SiegeController: pad %d has an unknown kind" % pad_index)
	return "PAD"


func _clear_pad_panels() -> void:
	for panel_v: Variant in _pad_panels:
		var panel := panel_v as Node
		if panel != null and is_instance_valid(panel):
			panel.queue_free()
	_pad_panels.clear()
	_close_build_picker()


func _hide_pad_panel(pad_index: int) -> void:
	if pad_index < 0 or pad_index >= _pad_panels.size():
		return
	var panel := _pad_panels[pad_index] as Node
	if panel != null and is_instance_valid(panel):
		panel.call("set_hit_enabled", false)


## The plates themselves carry no pot state; the affordable list lives in the picker, so a pot
## change only has to re-list whatever picker is currently up.
func _refresh_pad_panels() -> void:
	for panel_v: Variant in _pad_panels:
		var panel := panel_v as Node3D
		if panel != null and is_instance_valid(panel) and panel.visible:
			panel.call("refresh")
	if _city != null and is_instance_valid(_city):
		_city.call("refresh_siege_build_picker")


## The "+" plate was pressed: hand the pad to the screen-space picker at the mouse.
func _on_pad_pressed(pad_index: int) -> void:
	if not is_running():
		return
	if _pad_tower.get(pad_index, null) != null:
		return
	if _city == null or not is_instance_valid(_city):
		push_error("SiegeController._on_pad_pressed: no city")
		assert(false, "SiegeController: pad press without a city")
		return
	_city.call("open_siege_build_picker", pad_index, self)


func _close_build_picker() -> void:
	if _city != null and is_instance_valid(_city):
		_city.call("close_siege_build_picker")


func _on_tower_died(_unit: UndeadUnit, _was_giant: bool, pad_index: int) -> void:
	_pad_tower.erase(pad_index)
	## Show the pad's "+" again so the player can rebuy at full pot price.
	if is_running() and pad_index >= 0 and pad_index < _pad_panels.size():
		var panel := _pad_panels[pad_index] as Node
		if panel != null and is_instance_valid(panel):
			panel.call("set_hit_enabled", true)
			panel.call("refresh")
	var kept: Array[UndeadUnit] = []
	for t: UndeadUnit in _towers:
		if t != null and is_instance_valid(t) and t.is_alive():
			kept.append(t)
	_towers = kept


func _clear_towers() -> void:
	for unit: UndeadUnit in _towers:
		if unit == null or not is_instance_valid(unit):
			continue
		if _despawn_cb.is_valid():
			_despawn_cb.call(unit)
		else:
			unit.queue_free()
	_towers.clear()
	_pad_tower.clear()


# --- Lodestone console ------------------------------------------------------

func _spawn_lodestone_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
	## Gate-side of the Lodestone, face toward the approach (see Ui3D class doc —
	## `atan2(outward…)` would aim into the crystal).
	var outward := Vector2.ZERO
	for d: Vector2i in layout.gate_dirs:
		outward += Vector2(float(-d.x), float(-d.y))
	if outward.length_squared() < 0.01:
		outward = Vector2(0.0, 1.0)
	outward = outward.normalized()
	var yaw := atan2(-outward.x, -outward.y)
	var origin := lodestone_world_pos()
	var radius_m := float(layout.lodestone_radius_vox) * voxel_size
	origin += Vector3(outward.x, 0.0, outward.y) * (radius_m + PANEL_CLEARANCE_M)
	origin.y += PANEL_HEIGHT_M
	_panel = SiegeLodestonePanelScript.new() as SiegeLodestonePanel
	add_child(_panel)
	_panel.setup_panel(origin, yaw, self)
	_panel.start_requested.connect(_on_panel_start)
	_panel.withdraw_requested.connect(_on_panel_withdraw)


func _on_panel_start(stake: Dictionary) -> void:
	if not start_run(stake):
		_refresh_panel()


func _on_panel_withdraw() -> void:
	if not withdraw():
		_refresh_panel()


func _refresh_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		_panel.refresh()
