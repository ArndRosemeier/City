## Runtime owner of a Siege Quarter: the pot, the waves, the five stones, the eight hell gates, and
## the player's temporary `SIEGE_DEFENDER` allegiance.
##
## Player-initiated, like the Arena. Streaming the tile in only stands the controller up;
## nothing spawns until `start_run`. Towers are paid from the player's bag; kill hauls during a
## run feed the pot (via `CityRoot.grant_monster_kill_haul`); withdrawing banks it, and losing the
## Lodestone burns it. The pot is loot, not a stake — the player never pays into it.
##
## The five stones are why a run is a map rather than a plaza. Four outer stones stand ~100 m out and
## the centre cannot be hurt while any of them lives, so pressure has to be answered where it lands.
## The horde finds them through `BeaconRegistry` rather than through aggro — a stone 100 m away
## across a district is invisible to every ordinary acquisition rule.
class_name SiegeController
extends Node3D

const MonsterFactionScript := preload("res://scripts/city/monster_faction.gd")
const CombatTableScript := preload("res://scripts/city/combat_table.gd")
const InventoryCatalogScript := preload("res://scripts/city/inventory_catalog.gd")
const SiegeLodestonePanelScript := preload("res://scripts/city/siege_lodestone_panel.gd")
const SiegePadPanelScript := preload("res://scripts/city/siege_pad_panel.gd")
const SiegeTowerCatalogScript := preload("res://scripts/city/siege_tower_catalog.gd")
const MonsterRosterScript := preload("res://scripts/city/monster_roster.gd")
const SiegeShieldArcVfxScript := preload("res://scripts/city/siege_shield_arc_vfx.gd")

## One objective's whole runtime state. A stone is not a combat entity — it has no body, no collider
## and no hitbox — which is why five of them cost no more than the contact tick one of them did.
class StoneState:
	extends RefCounted

	var label: String = ""
	var pos: Vector3 = Vector3.ZERO
	var hp: float = 0.0
	var hp_max: float = 0.0
	## Flat metres in which an attacker both stops walking and deals contact damage.
	var vuln_radius_m: float = 5.0
	## Height of the crystal's apex above `pos`, for the shield arc's anchor.
	var apex_m: float = 0.0
	## Beacon this stone is currently registered as, or 0 when the horde cannot perceive it. The
	## centre stays at 0 until the last outer stone falls — that is the shield, mechanically.
	var beacon_id: int = 0
	var is_centre: bool = false
	var alive: bool = true
	## The light bridge to the centre. Outer stones only.
	var arc: Node3D = null


## How far above a hell gate's mouth a body is dropped.
const SPAWN_LIFT_M := 0.2
## How far in front of a mouth a body appears, in voxels. In front rather than behind: the mouth
## plane is `LOS_VEIL`, which bodies walk through but the navigator reads as solid, so a body born
## on the far side would have to path out of a wall.
const SPAWN_STEP_VOX := 3.0
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
## Where a tower's combat host stands above the pad surface cell. The host is a point rather than
## a mesh, so this only has to sit inside the stamp — the muzzle is lifted separately.
const TOWER_HOST_LIFT_M := 0.6
## Plates built per frame. A quarter carries hundreds of build sites and each plate is eight
## nodes, so standing them all up in the frame the run starts is a visible hitch.
const PLATES_PER_FRAME := 8
## How close the player must be to *operate* a pad (open the build picker). Colliders go live
## farther out — out to the plate's view distance — so aiming a distant "+" swallows the shot
## and toasts "too far" instead of carving the street. A field of always-on colliders would still
## eat every low aim across the quarter, so detection is still proximity-gated.
const PLATE_TOUCH_M := 10.0
const PLATE_PROXIMITY_INTERVAL_SEC := 0.2
## A wave always shows up, even when the soft target is already met by bodies chewing a stone
## somewhere the player abandoned. Zero-body waves would switch the siege off by inaction.
const MIN_WAVE_BATCH := 2
## Hell-gate mouth light: range and the energy a full-weight gate burns at. The tell is a forecast —
## it shows where the *next* wave is coming from, so a player who reads it can pre-build a flank.
const GATE_LIGHT_RANGE_M := 26.0
const GATE_LIGHT_ENERGY := 7.0
## Emissive pip in the mouth, so the tell survives being read from outside the light's range.
const GATE_PIP_RADIUS_M := 0.7

## There is no "wave cleared" state: waves land on a timer and leftovers keep chewing, so the only
## phases are before the first wave and after it. See §10 of the design doc.
enum Phase {
	IDLE,
	DEPLOY,
	RUNNING,
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
## Countdown of the pre-run deployment window, then of the gap to the next wave.
var _deploy_left: float = 0.0
var _wave_left: float = 0.0
var _spawn_queue: PackedStringArray = PackedStringArray()
var _spawn_cd: float = 0.0
## Drip between bodies of the current batch, sized so the batch spans part of the wave period.
var _drip_interval: float = 0.55
## Living attackers this controller owns this run.
var _alive: Array[UndeadUnit] = []
## Living towers (meshless UndeadUnits) owned by this run.
var _towers: Array[UndeadUnit] = []
## pad_index → tower unit (or null when empty).
var _pad_tower: Dictionary = {}
## pad_index → the lay-flat "+" plate on that pad. A Dictionary rather than an array because
## plates are built a few per frame, so the collection is sparse until the queue drains. Values are
## untyped: these are preload instances, and a `class_name` element type here has to resolve
## before the script cache is warm.
var _pad_panels: Dictionary = {}
## Pad indices still waiting for a plate.
var _plate_queue: PackedInt32Array = PackedInt32Array()
var _plate_prox_acc: float = 0.0

## item_id → count. Session-local; never touches inventory until withdraw or is lost on fail.
var _pot: Dictionary = {}
## The centre plus the four outer stones, built at `start_run`. Empty outside a run.
var _stones: Array[StoneState] = []
var _centre: StoneState = null
## Per-hell-gate spawn weight for this wave and for the next one. The next-wave table is the
## forecast the mouth lights show; the current one is what `_pick_gate` draws from.
var _gate_weights: PackedFloat32Array = PackedFloat32Array()
var _next_gate_weights: PackedFloat32Array = PackedFloat32Array()
## Gate that carried this wave and the one that will carry the next, so a bearing never repeats
## twice running and the HUD can name where the pressure is about to come from.
var _primary_gate: int = -1
var _next_primary_gate: int = -1
## Mouth lights and pips, parallel to `layout.hell_gates`.
var _gate_lights: Array[OmniLight3D] = []
var _gate_pips: Array[MeshInstance3D] = []
var _gate_pip_mats: Array[StandardMaterial3D] = []
var _owns_defender_faction: bool = false
var _shutting_down: bool = false
var _panel: SiegeLodestonePanel = null
var _panel_refresh_acc: float = 0.0

## Authored tuning, read once at setup.
var _lodestone_base_hp: float = 400.0
var _outer_stone_hp: float = 250.0
var _lodestone_vuln_radius_m: float = 5.0
## Weight of the gate a wave picks as its primary, the floor every other gate keeps, and how fast
## weight falls away with angular distance from the primary bearing.
var _gate_primary_share: float = 1.0
var _gate_weight_floor: float = 0.08
var _gate_falloff: float = 1.6
## Ground around the crystal that has to be empty of attackers before the pot can be banked.
var _withdraw_clear_radius_m: float = 20.0
var _deploy_sec: float = 45.0
var _wave_period_sec: float = 120.0
## Share of the wave period the batch's drip is spread across, so pressure is continuous rather
## than a five-second dump followed by silence.
var _wave_drip_fraction: float = 0.5
var _alive_target_base: int = 10
var _alive_target_growth: int = 2
## Ceiling on the soft alive target, not a wall the spawner slams into.
var _district_cap: int = 34
## Floor under the computed drip — the batch never spawns faster than this.
var _spawn_interval_sec: float = 0.55
var _hp_growth: float = 0.12
var _damage_growth: float = 0.08
var _lodestone_dps_per_attacker: float = 8.0
var _repair_energy_per_sec: float = 2.0
var _repair_hp_per_sec: float = 5.0
var _repair_range_m: float = 18.0
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
	## Stones and their arcs belong to the *tile*, not to a run. A player who walks into a Siege
	## quarter should be able to read what the place is before staking anything: four bridges of light
	## converging on one crystal say "these four protect that one" without a word of UI.
	_build_stones()
	_ensure_shield_arcs()
	_spawn_lodestone_panel()
	set_process(true)
	print(
		"SiegeController: ready — %s, roster=%d bodies"
		% [layout.describe(), _roster.size()]
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
	## The arcs are the only thing that outlives a run, so tearing the tile down is the one place
	## they have to be taken away explicitly.
	_clear_shield_arcs()
	set_process(false)


func _exit_tree() -> void:
	shutdown()


func is_running() -> bool:
	return _phase == Phase.DEPLOY or _phase == Phase.RUNNING


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
	return _centre.hp if _centre != null else 0.0


func lodestone_hp_max() -> float:
	return _centre.hp_max if _centre != null else 0.0


## The five pools, centre first. Read-only for the HUD and the tests.
func stones() -> Array[StoneState]:
	return _stones


func outer_stones_alive() -> int:
	var n := 0
	for stone: StoneState in _stones:
		if not stone.is_centre and stone.alive:
			n += 1
	return n


## True while an outer stone still stands, meaning contact on the Lodestone does nothing.
func centre_shielded() -> bool:
	return outer_stones_alive() > 0


## Seconds left of the pre-run deployment window. Zero once the first wave has landed.
func deploy_left() -> float:
	return _deploy_left


## Seconds until the next wave lands.
func wave_left() -> float:
	return _wave_left


## How many attackers the district aims to keep alive at the current wave. A target, not a wall:
## bodies already alive count against it, so an ignored flank thins the next wave instead of the
## spawner slamming into a cap.
func alive_target() -> int:
	return mini(_alive_target_base + maxi(_wave - 1, 0) * _alive_target_growth, _district_cap)


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


func repair_energy_per_sec() -> float:
	return _repair_energy_per_sec


func repair_hp_per_sec() -> float:
	return _repair_hp_per_sec


func repair_range_m() -> float:
	return _repair_range_m


## Compact stats for SiegeHud. `active` is false outside DEPLOY/RUNNING.
func get_hud_stats() -> Dictionary:
	return {
		"active": is_running(),
		"phase": int(_phase),
		"wave": _wave,
		"pot_total": pot_total(),
		"pot": pot_snapshot(),
		"lodestone_hp": lodestone_hp(),
		"lodestone_hp_max": lodestone_hp_max(),
		"deploy_left": _deploy_left,
		"wave_left": _wave_left,
		"alive": _alive.size(),
		"alive_target": alive_target(),
		"queued": _spawn_queue.size(),
		"withdraw_reason": withdraw_block_reason(),
		"outer_alive": outer_stones_alive(),
		"outer_total": layout.outer_stone_count() if layout != null else 0,
		"centre_shielded": centre_shielded(),
		"next_pressure": next_pressure_label(),
	}


## Open the run with an empty pot. False when a run is already live.
##
## Towers are paid from the bag as they are built; kill loot fills the pot. There is no stake —
## starting used to drain gems the player had not yet chosen to spend, and the pot is loot now.
func start_run() -> bool:
	if is_running():
		push_error("SiegeController.start_run: a run is already live")
		return false
	if _phase == Phase.LOST or _phase == Phase.WITHDRAWN:
		## A finished controller can be restarted after a withdraw; a loss leaves the tile
		## idle until the player starts again.
		_phase = Phase.IDLE
	_pot.clear()

	_reset_stones()
	_wave = 0
	_alive.clear()
	_spawn_queue.clear()
	_city.call("begin_siege_run", self)
	_city.call(
		"set_player_combat_faction", int(MonsterFactionScript.Id.SIEGE_DEFENDER)
	)
	_owns_defender_faction = true
	_clear_towers()
	_register_outer_beacons()
	_ensure_shield_arcs()
	_spawn_gate_lights()
	## First forecast before the deployment window ends, so the mouths are already telling the
	## player where wave one lands while there is still time to build for it.
	_roll_next_gate_weights()
	_apply_gate_lights()
	## Phase first: a pad plate builds its face from `is_running()`, so queueing the plates
	## before the run opens leaves every one of them empty.
	_begin_deploy()
	_spawn_pad_panels()
	_refresh_panel()
	print(
		"SiegeController: run started — centre=%.0f hp behind %d outer stones, %d build sites"
		% [lodestone_hp_max(), outer_stones_alive(), layout.pad_count()]
	)
	return true


## Flat metres around the Lodestone that must be clear of attackers before the pot can be banked.
func withdraw_clear_radius_m() -> float:
	return _withdraw_clear_radius_m


## Live attackers inside the withdrawal ring. Zero means the console will bank.
func withdraw_blockers() -> int:
	if not is_running():
		return 0
	var aim := lodestone_world_pos()
	var r2 := _withdraw_clear_radius_m * _withdraw_clear_radius_m
	var n := 0
	for unit: UndeadUnit in _alive:
		if unit == null or not is_instance_valid(unit) or not unit.is_alive():
			continue
		var d2 := Vector2(
			unit.global_position.x - aim.x, unit.global_position.z - aim.z
		).length_squared()
		if d2 <= r2:
			n += 1
	return n


## Why the pot cannot be banked right now, or "" when it can.
##
## Two halves, one radius: the player has to be standing on the crystal's ground, and that ground
## has to be clear of attackers. The button lives on the HUD rather than out in the quarter, so the
## rule is what keeps cashing out physical — otherwise the player could bank from the rim without
## ever walking back, and a pot that costs nothing to keep is not a gamble. Waves land on a clock
## and never stop, so every minute the pot grows is a minute this ring is harder to own.
func withdraw_block_reason() -> String:
	if not is_running():
		return "No siege is running"
	var lode := lodestone_world_pos()
	var here := _player_position()
	var gap := Vector2(here.x - lode.x, here.z - lode.z).length()
	if gap > _withdraw_clear_radius_m:
		return "Too far from the Lodestone — %dm out" % int(round(gap))
	var blockers := withdraw_blockers()
	if blockers > 0:
		return (
			"%d attacker%s within %dm of the Lodestone"
			% [blockers, "" if blockers == 1 else "s", int(round(_withdraw_clear_radius_m))]
		)
	return ""


## Bank the pot into inventory and end the run. False when `withdraw_block_reason` has something
## to say — a legal player miss, not a fault, so the HUD prints the reason and the run carries on.
func withdraw() -> bool:
	if not is_running():
		push_error("SiegeController.withdraw: no live run (phase=%d)" % int(_phase))
		return false
	if not withdraw_block_reason().is_empty():
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
		_refresh_panel()
		_refresh_pad_panels()
		if _city != null and is_instance_valid(_city) and _city.has_method("refresh_siege_build_picker"):
			_city.call("refresh_siege_build_picker")
	return paid


## Spend tower gems from the player's bag. False when the bag cannot cover the cost.
func spend_tower_cost(cost: Dictionary) -> bool:
	if not is_running():
		push_error("SiegeController.spend_tower_cost: no run")
		return false
	if not can_afford(cost):
		return false
	var inv := inventory()
	if inv == null:
		push_error("SiegeController.spend_tower_cost: no inventory")
		return false
	for k: Variant in cost.keys():
		var item_id := String(k)
		var n := int(cost[k])
		if n <= 0:
			continue
		if not inv.remove(item_id, n):
			push_error(
				"SiegeController.spend_tower_cost: remove failed for %s after afford check"
				% item_id
			)
			assert(false, "SiegeController: inventory remove failed after count check")
			return false
	return true


func can_afford(cost: Dictionary) -> bool:
	if not is_running():
		return false
	var inv := inventory()
	if inv == null:
		return false
	for k: Variant in cost.keys():
		var item_id := String(k)
		var n := int(cost[k])
		if n <= 0:
			continue
		if inv.count_of(item_id) < n:
			return false
	return true


func _refund_tower_cost(cost: Dictionary) -> void:
	var inv := inventory()
	if inv == null:
		push_error("SiegeController._refund_tower_cost: no inventory to restore")
		return
	for k: Variant in cost.keys():
		var item_id := String(k)
		var n := int(cost[k])
		if n > 0:
			inv.add(item_id, n)


## Buy `tower_id` onto an empty pad. Stamps voxels, spawns the combat host, spends the bag.
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
	## A short bag is a legal player miss, not a fault — the picker only lists what they can pay.
	## Everything below this line is a genuine error if it fails.
	if not spend_tower_cost(cost):
		return false
	var pad_world := _pad_world_pos(pad_index)
	var brush: CityBrush = _city.call("voxel_brush") as CityBrush
	var terrain: VoxelTerrain = _city.call("voxel_terrain") as VoxelTerrain
	if brush == null or terrain == null:
		push_error("SiegeController.build_tower: city has no brush/terrain")
		_refund_tower_cost(cost)
		return false
	var stamped: Array[Vector3i] = SiegeTowerCatalogScript.stamp_at(
		terrain, brush, def, pad_world
	)
	if stamped.is_empty():
		push_error("SiegeController.build_tower: stamp wrote nothing for '%s'" % tower_id)
		_refund_tower_cost(cost)
		return false
	var combat_id := str(def.get("combat_id"))
	var hp := float(def.get("hp"))
	var unit: UndeadUnit = null
	if _city.has_method("spawn_siege_tower_at"):
		## The host sits inside the stamp; its muzzle has to clear the top of it, or every LOS
		## probe the turret makes starts in its own stone and it silently never fires.
		var muzzle_h := (
			SiegeTowerCatalogScript.muzzle_height_m(def, voxel_size) - TOWER_HOST_LIFT_M
		)
		## Stamp footprint as a living hit volume — mobs stand at the wall, not at pad centre.
		var hit_r := SiegeTowerCatalogScript.structure_hit_radius_m(def, voxel_size)
		unit = _city.call(
			"spawn_siege_tower_at",
			combat_id,
			pad_world + Vector3(0.0, TOWER_HOST_LIFT_M, 0.0),
			hp,
			muzzle_h,
			hit_r
		) as UndeadUnit
	if unit == null or not is_instance_valid(unit):
		push_error("SiegeController.build_tower: spawn failed for '%s'" % combat_id)
		_refund_tower_cost(cost)
		return false
	_towers.append(unit)
	_pad_tower[pad_index] = unit
	_ward_claim(unit, stamped)
	unit.died.connect(_on_tower_died.bind(pad_index))
	_hide_pad_panel(pad_index)
	_refresh_panel()
	_refresh_pad_panels()
	if _city != null and is_instance_valid(_city) and _city.has_method("refresh_siege_build_picker"):
		_city.call("refresh_siege_build_picker")
	print(
		"SiegeController: built %s on pad %d"
		% [str(def.get("display_name")), pad_index]
	)
	return true


func _process(delta: float) -> void:
	if layout == null or _city == null or not is_instance_valid(_city):
		return
	if is_running():
		_prune_alive()
		_tick_plate_build()
		_tick_plate_proximity(delta)
		match _phase:
			Phase.DEPLOY:
				_deploy_left -= delta
				if _deploy_left <= 0.0:
					_deploy_left = 0.0
					_begin_wave()
			Phase.RUNNING:
				## No end condition. A wave is a scheduled batch, not a room to clear — bodies
				## the player never reaches keep chewing, and waiting on `_alive` to empty would
				## hang the run forever the moment anything survives out of reach.
				_wave_left -= delta
				if _wave_left <= 0.0:
					_begin_wave()
				_tick_spawns(delta)
				_tick_stones(delta)
	## Console clock — labels only; full face rebuilds happen on phase changes. Skipped during a
	## run: the console is hidden then and `SiegeHud` carries the live readout.
	if is_running():
		return
	_panel_refresh_acc += delta
	if _panel_refresh_acc >= 0.25:
		_panel_refresh_acc = 0.0
		if _panel != null and is_instance_valid(_panel):
			_panel.tick_display()


## The deployment window: started, plates going up, gates still dark. This is the run's only pause
## and the player's whole setup time — after the first wave the clock never stops.
func _begin_deploy() -> void:
	_phase = Phase.DEPLOY
	_deploy_left = _deploy_sec
	_wave_left = 0.0
	_refresh_panel()
	print("SiegeController: deploying — first wave in %.0fs" % _deploy_sec)


func _begin_wave() -> void:
	_wave += 1
	_phase = Phase.RUNNING
	_wave_left = _wave_period_sec
	## The forecast the mouths have been showing becomes this wave's table, then a fresh forecast
	## goes up for the wave after it. That ordering is the whole point of the tell: what the player
	## read while building is what actually arrives.
	_adopt_next_gate_weights()
	_roll_next_gate_weights()
	_apply_gate_lights()
	## Soft target: the batch is the shortfall against where the horde should be, so leftovers
	## chewing a stone the player walked away from buy quiet and cost stone HP instead of piling
	## into an ever-growing field.
	var batch := clampi(alive_target() - _alive.size(), MIN_WAVE_BATCH, _district_cap)
	_spawn_queue.clear()
	for _i in range(batch):
		_spawn_queue.append(_pick_body())
	_drip_interval = maxf(
		_spawn_interval_sec, (_wave_period_sec * _wave_drip_fraction) / float(batch)
	)
	_spawn_cd = 0.0
	_refresh_panel()
	print(
		"SiegeController: wave %d — %d bodies from %s (alive %d, target %d), drip %.1fs, hp×%.2f dmg×%.2f"
		% [
			_wave,
			batch,
			gate_bearing_label(_primary_gate),
			_alive.size(),
			alive_target(),
			_drip_interval,
			_wave_hp_mult(),
			_wave_damage_mult(),
		]
	)


func _tick_spawns(delta: float) -> void:
	if _spawn_queue.is_empty():
		return
	_spawn_cd -= delta
	if _spawn_cd > 0.0:
		return
	## The global roster ceiling is a frame-rate safety net, not a balance number. Hold the body on
	## the queue and retry — dequeuing on a null spawn used to erase wave members and flood the
	## ErrorOverlay with "alive cap reached".
	if _global_walkers() >= MonsterRosterScript.MAX_ALIVE_UNITS:
		_spawn_cd = _drip_interval
		return
	var body_id := _spawn_queue[0]
	if not _spawn_attacker(body_id):
		_spawn_cd = _drip_interval
		return
	_spawn_queue.remove_at(0)
	_spawn_cd = _drip_interval


## Walking bodies across the whole city. Towers are skipped: the roster ceiling bounds walkers, and
## a quarter plated with 200 immobile towers must not switch the horde attacking them off.
func _global_walkers() -> int:
	if not _units_cb.is_valid():
		return _alive.size()
	var n := 0
	for u: Variant in _units_cb.call() as Array:
		var unit := u as UndeadUnit
		if unit == null or not is_instance_valid(unit) or unit.is_siege_tower():
			continue
		n += 1
	return n


## False when the roster refused (cap / nav). The body stays queued for a later tick.
##
## Nothing here tells the body what to attack. Beacons do that, and they do it live — a stone that
## falls while this body is walking to it retargets it on its next query, which a spawn-time aim
## could never do.
func _spawn_attacker(body_id: String) -> bool:
	if not _spawn_cb.is_valid() or layout.hell_gate_count() <= 0:
		return false
	var gate_i := _pick_gate()
	var gate := layout.hell_gates[gate_i]
	var gw := gate.world(origin_vox)
	var pos := Vector3(
		(float(gw.x) + 0.5) * voxel_size,
		float(gw.y) * voxel_size + SPAWN_LIFT_M,
		(float(gw.z) + 0.5) * voxel_size
	)
	pos -= Vector3(float(gate.outward.x), 0.0, float(gate.outward.y)) * voxel_size * SPAWN_STEP_VOX
	var unit: UndeadUnit = _spawn_cb.call(body_id, pos, true) as UndeadUnit
	if unit == null or not is_instance_valid(unit):
		return false
	unit.set_faction(int(MonsterFactionScript.Id.SIEGE_ATTACKER))
	unit.scale_for_wave(_wave_hp_mult(), _wave_damage_mult())
	_alive.append(unit)
	return true


# --- Hell gates -------------------------------------------------------------

## Weight table for a wave: one gate is the primary and every other falls away with angular distance
## from it, never below the floor. A single hot gate would let the player fortify one lane and stop
## playing; a flat table would make every wave feel the same. Rolled from the district seed and the
## wave number, so the same tile plays the same order of attacks on a reload.
func _roll_gate_weights(wave: int, avoid_gate: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := layout.hell_gate_count()
	if n <= 0:
		return out
	var pick := RandomNumberGenerator.new()
	pick.seed = district_seed ^ (wave * 0x9E3779B9)
	var primary := int(pick.randi() % n)
	if n > 1 and primary == avoid_gate:
		## Two waves from the same mouth read as a bug rather than as pressure.
		primary = (primary + 1 + int(pick.randi() % (n - 1))) % n
	var primary_bearing := layout.hell_gates[primary].bearing_rad
	for i in range(n):
		var gap := absf(angle_difference(layout.hell_gates[i].bearing_rad, primary_bearing))
		out.append(
			maxf(_gate_primary_share * exp(-_gate_falloff * gap), _gate_weight_floor)
		)
	return out


func _roll_next_gate_weights() -> void:
	_next_gate_weights = _roll_gate_weights(_wave + 1, _primary_gate)
	_next_primary_gate = _heaviest_gate(_next_gate_weights)


func _adopt_next_gate_weights() -> void:
	if _next_gate_weights.size() != layout.hell_gate_count():
		_next_gate_weights = _roll_gate_weights(_wave, _primary_gate)
	_gate_weights = _next_gate_weights
	_primary_gate = _heaviest_gate(_gate_weights)


func _heaviest_gate(weights: PackedFloat32Array) -> int:
	var best := -1
	var best_w := -1.0
	for i in range(weights.size()):
		if weights[i] > best_w:
			best_w = weights[i]
			best = i
	return best


func _pick_gate() -> int:
	var n := layout.hell_gate_count()
	if _gate_weights.size() != n:
		push_error("SiegeController._pick_gate: no weight table for %d gates" % n)
		assert(false, "SiegeController: gate weights out of sync")
		return int(_rng.randi() % n)
	var total := 0.0
	for w in _gate_weights:
		total += w
	var roll := _rng.randf() * total
	var acc := 0.0
	for i in range(n):
		acc += _gate_weights[i]
		if roll <= acc:
			return i
	return n - 1


## Compass name of a gate's bearing, for logs and the HUD. Bearing is measured in district-local
## voxel space, where +X is east and +Z is south.
func gate_bearing_label(gate_i: int) -> String:
	if gate_i < 0 or gate_i >= layout.hell_gate_count():
		return "nowhere"
	var deg := rad_to_deg(layout.hell_gates[gate_i].bearing_rad)
	var octant := int(round(fposmod(deg, 360.0) / 45.0)) % 8
	return [
		"the east",
		"the south-east",
		"the south",
		"the south-west",
		"the west",
		"the north-west",
		"the north",
		"the north-east",
	][octant]


## One line of forecast for the HUD, or "" before the first table exists.
func next_pressure_label() -> String:
	if not is_running() or _next_primary_gate < 0:
		return ""
	return "Next wave from %s" % gate_bearing_label(_next_primary_gate)


## Per-gate weight for the *next* wave. The mouth lights read from this.
func next_gate_weights() -> PackedFloat32Array:
	return _next_gate_weights


## A light and a glowing pip in every mouth. Voxel materials cannot change emission per instance
## without a remesh, so the "this one burns brighter" tell has to be nodes rather than paint.
func _spawn_gate_lights() -> void:
	_clear_gate_lights()
	for i in range(layout.hell_gate_count()):
		var gate := layout.hell_gates[i]
		var gw := gate.world(origin_vox)
		var at := Vector3(
			(float(gw.x) + 0.5) * voxel_size,
			(float(gw.y) + 4.0) * voxel_size,
			(float(gw.z) + 0.5) * voxel_size
		)
		var light := OmniLight3D.new()
		light.name = "GateLight%d" % i
		light.omni_range = GATE_LIGHT_RANGE_M
		light.light_color = Color(1.0, 0.42, 0.2)
		light.light_energy = 0.0
		light.shadow_enabled = false
		add_child(light)
		light.global_position = at
		_gate_lights.append(light)

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.45, 0.22)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.4, 0.16)
		mat.emission_energy_multiplier = 0.5
		var sphere := SphereMesh.new()
		sphere.radius = GATE_PIP_RADIUS_M
		sphere.height = GATE_PIP_RADIUS_M * 2.0
		sphere.radial_segments = 8
		sphere.rings = 4
		var pip := MeshInstance3D.new()
		pip.name = "GatePip%d" % i
		pip.mesh = sphere
		pip.material_override = mat
		pip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pip)
		pip.global_position = at
		_gate_pips.append(pip)
		_gate_pip_mats.append(mat)


## Brightness ∝ the gate's share of the next wave. A mouth at the floor is nearly dark, so scanning
## the skyline answers "where do I build next" without opening anything.
func _apply_gate_lights() -> void:
	if _gate_lights.size() != _next_gate_weights.size():
		return
	var top := 0.0
	for w in _next_gate_weights:
		top = maxf(top, w)
	if top <= 0.0:
		return
	for i in range(_gate_lights.size()):
		var share := clampf(_next_gate_weights[i] / top, 0.0, 1.0)
		_gate_lights[i].light_energy = GATE_LIGHT_ENERGY * share * share
		_gate_pip_mats[i].emission_energy_multiplier = 0.4 + 5.0 * share * share


func _clear_gate_lights() -> void:
	for light: OmniLight3D in _gate_lights:
		if light != null and is_instance_valid(light):
			light.queue_free()
	for pip: MeshInstance3D in _gate_pips:
		if pip != null and is_instance_valid(pip):
			pip.queue_free()
	_gate_lights.clear()
	_gate_pips.clear()
	_gate_pip_mats.clear()


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


## Build the run's five pools. Positions come from the layout the composer baked, so the stones the
## controller ticks are the crystals actually standing on the tile.
func _build_stones() -> void:
	_stones.clear()
	_centre = null
	var centre := StoneState.new()
	centre.label = "Lodestone"
	centre.pos = lodestone_world_pos()
	centre.hp_max = _lodestone_base_hp
	centre.hp = centre.hp_max
	centre.vuln_radius_m = lodestone_vulnerable_radius_m()
	centre.apex_m = float(layout.lodestone_height_vox + 2) * voxel_size
	centre.is_centre = true
	_centre = centre
	_stones.append(centre)
	for i in range(layout.outer_stone_count()):
		var planned := layout.outer_stones[i]
		var stone := StoneState.new()
		stone.label = "Outer stone %d" % (i + 1)
		stone.pos = _stone_world_pos(planned)
		stone.hp_max = _outer_stone_hp
		stone.hp = stone.hp_max
		stone.vuln_radius_m = _stone_vulnerable_radius_m(planned.radius_vox)
		stone.apex_m = float(planned.height_vox + 2) * voxel_size
		_stones.append(stone)


## Put the five stones back to full for a fresh run, in place rather than rebuilt. Rebuilding would
## drop the `StoneState` objects that hold the idle arcs, orphaning four sets of geometry under the
## controller every time a run started.
func _reset_stones() -> void:
	if _stones.is_empty():
		_build_stones()
		return
	for stone: StoneState in _stones:
		stone.hp = stone.hp_max
		stone.alive = true
		stone.beacon_id = 0


func _stone_world_pos(planned: SiegeLayout.Stone) -> Vector3:
	var w := planned.world(origin_vox)
	return Vector3(
		(float(w.x) + 0.5) * voxel_size,
		float(w.y) * voxel_size,
		(float(w.z) + 0.5) * voxel_size
	)


## Same rule as the Lodestone's: the radius has to clear the solid crystal by more than the goal
## provider's ring inset, or attackers are sent to stand inside `GLASS_LIT` and dance around it.
func _stone_vulnerable_radius_m(radius_vox: int) -> float:
	return maxf(
		_lodestone_vuln_radius_m, float(radius_vox) * voxel_size + LODESTONE_RADIUS_SLACK_M
	)


# --- Beacons ----------------------------------------------------------------

## Null only while the city is being torn down, which is a legitimate state on `shutdown`. A live
## city that cannot hold beacons is a wiring bug and says so.
func _beacon_registry() -> BeaconRegistry:
	if _city == null or not is_instance_valid(_city):
		return null
	if not _city.has_method("beacon_registry"):
		push_error("SiegeController: the city has no beacon registry")
		assert(false, "SiegeController: city cannot hold beacons")
		return null
	return _city.call("beacon_registry") as BeaconRegistry


## Make the four outer stones perceivable. The centre is deliberately left out: while it is not a
## beacon the horde has no reason to walk to it, which is the shield expressed as behaviour rather
## than as a damage-immunity rule bolted on top of one.
func _register_outer_beacons() -> void:
	var registry := _beacon_registry()
	if registry == null:
		return
	for stone: StoneState in _stones:
		if stone.is_centre or not stone.alive:
			continue
		stone.beacon_id = registry.register(
			stone.pos,
			stone.vuln_radius_m,
			int(MonsterFactionScript.Id.SIEGE_ATTACKER)
		)


func _register_centre_beacon() -> void:
	if _centre == null or _centre.beacon_id != 0:
		return
	var registry := _beacon_registry()
	if registry == null:
		return
	_centre.beacon_id = registry.register(
		_centre.pos,
		_centre.vuln_radius_m,
		int(MonsterFactionScript.Id.SIEGE_ATTACKER)
	)


func _unregister_beacon(stone: StoneState) -> void:
	if stone.beacon_id == 0:
		return
	var registry := _beacon_registry()
	if registry != null and registry.has(stone.beacon_id):
		registry.unregister(stone.beacon_id)
	stone.beacon_id = 0


func _clear_beacons() -> void:
	for stone: StoneState in _stones:
		stone.beacon_id = 0
	var registry := _beacon_registry()
	if registry != null:
		registry.clear_audience(int(MonsterFactionScript.Id.SIEGE_ATTACKER))


# --- Shield arcs ------------------------------------------------------------

## Stand an arc over every living outer stone that has none. Idempotent, because it runs at setup, at
## the start of a run and again when one ends — a stone that fell mid-run gets its bridge back once
## the run is over, since between runs all four stand again.
func _ensure_shield_arcs() -> void:
	if _centre == null or _shutting_down:
		return
	var centre_apex := _centre.pos + Vector3.UP * _centre.apex_m
	for i in range(_stones.size()):
		var stone := _stones[i]
		if stone.is_centre or not stone.alive:
			continue
		if stone.arc != null and is_instance_valid(stone.arc):
			continue
		var arc: Node3D = SiegeShieldArcVfxScript.new() as Node3D
		arc.name = "ShieldArc%d" % i
		add_child(arc)
		arc.call("setup_arc", stone.pos + Vector3.UP * stone.apex_m, centre_apex)
		stone.arc = arc


func _drop_shield_arc(stone: StoneState) -> void:
	if stone.arc == null or not is_instance_valid(stone.arc):
		stone.arc = null
		return
	stone.arc.call("begin_fade_out")
	stone.arc = null


func _clear_shield_arcs() -> void:
	for stone: StoneState in _stones:
		if stone.arc != null and is_instance_valid(stone.arc):
			stone.arc.queue_free()
		stone.arc = null


# --- Repair channel ---------------------------------------------------------

## Best damaged tower / stone along the aim ray within repair range. Empty when nothing
## needs mending or the aim misses. `point` is the beam attach (mid-mass), not the pad foot.
##
## Keys: `kind` ("tower"|"stone"), `unit` / `stone`, `point`, `t` (metres along the ray).
##
## LOS is tested to the near-side contact on the aim volume — never to the mass centre. Centres
## sit inside solid stamp / crystal voxels, and `has_voxel_line_of_sight` treats that as blocked,
## which used to make every tower aim fall through to the blaster.
func pick_repair_target(
	from: Vector3, dir: Vector3, max_range_m: float = -1.0
) -> Dictionary:
	if not is_running():
		return {}
	var aim := dir.normalized()
	if aim.length_squared() < 0.0001:
		return {}
	var max_m := max_range_m if max_range_m > 0.0 else _repair_range_m
	var best_t := INF
	var best: Dictionary = {}
	for stone: StoneState in _stones:
		if not stone.alive or stone.hp >= stone.hp_max - 0.01:
			continue
		var centre := _stone_repair_point(stone)
		var hit_r := _stone_repair_aim_radius_m(stone)
		var t := _ray_sphere_t(from, aim, centre, hit_r, max_m)
		if t >= best_t:
			continue
		if not _repair_has_los(from, from + aim * t):
			continue
		best_t = t
		best = {
			"kind": "stone",
			"stone": stone,
			"unit": null,
			"point": centre,
			"t": t,
		}
	for unit: UndeadUnit in _towers:
		if unit == null or not is_instance_valid(unit) or not unit.is_alive():
			continue
		if unit.health() >= unit.health_max() - 0.01:
			continue
		var attach := _tower_repair_point(unit)
		var hit_r := maxf(unit.hit_radius(), 0.6)
		## Towers are tall thin stamps; a single sphere at host height misses any aim at the shaft
		## or ORB tip. March spheres from foot to muzzle so the whole spire is aimable.
		var t := _ray_tower_shaft_t(from, aim, unit, hit_r, max_m)
		if t >= best_t:
			continue
		if not _repair_has_los(from, from + aim * t):
			continue
		best_t = t
		best = {
			"kind": "tower",
			"stone": null,
			"unit": unit,
			"point": attach,
			"t": t,
		}
	return best


## True when the aim ray hits a living tower that is already at full HP (same range / LOS as
## repair). Used so LMB on an undamaged tower toasts and does not fall through to the blaster.
func aim_hits_undamaged_tower(
	from: Vector3, dir: Vector3, max_range_m: float = -1.0
) -> bool:
	if not is_running():
		return false
	var aim := dir.normalized()
	if aim.length_squared() < 0.0001:
		return false
	var max_m := max_range_m if max_range_m > 0.0 else _repair_range_m
	var best_t := INF
	var hit := false
	for unit: UndeadUnit in _towers:
		if unit == null or not is_instance_valid(unit) or not unit.is_alive():
			continue
		if unit.health() < unit.health_max() - 0.01:
			continue
		var hit_r := maxf(unit.hit_radius(), 0.6)
		var t := _ray_tower_shaft_t(from, aim, unit, hit_r, max_m)
		if t >= best_t:
			continue
		if not _repair_has_los(from, from + aim * t):
			continue
		best_t = t
		hit = true
	return hit


func toast_undamaged() -> void:
	_toast_message("undamaged.")


## Apply `amount` HP to a pick_repair_target result. Returns healed points.
func apply_repair(target: Dictionary, amount: float) -> float:
	if target.is_empty() or amount <= 0.0:
		return 0.0
	var kind := str(target.get("kind", ""))
	if kind == "stone":
		return heal_stone(target.get("stone") as StoneState, amount)
	if kind == "tower":
		var unit := target.get("unit") as UndeadUnit
		if unit == null or not is_instance_valid(unit):
			return 0.0
		return unit.apply_heal(amount)
	push_error("SiegeController.apply_repair: unknown kind '%s'" % kind)
	return 0.0


func heal_stone(stone: StoneState, amount: float) -> float:
	if stone == null or not stone.alive:
		return 0.0
	if amount <= 0.0:
		push_error("SiegeController.heal_stone: non-positive amount %f" % amount)
		assert(false, "SiegeController: bad heal amount")
		return 0.0
	var room := stone.hp_max - stone.hp
	if room <= 0.0:
		return 0.0
	var add := minf(amount, room)
	stone.hp += add
	return add


func _stone_repair_point(stone: StoneState) -> Vector3:
	return stone.pos + Vector3(0.0, stone.apex_m * 0.45, 0.0)


func _tower_repair_point(unit: UndeadUnit) -> Vector3:
	## Mid-shaft attach so the green beam meets the stamp, not the buried host capsule.
	var tip := unit.muzzle_world()
	return (unit.global_position + tip) * 0.5


## Crystal shell, not the full chewer ring — aiming the vuln radius would soft-lock repair
## from half a street away.
func _stone_repair_aim_radius_m(stone: StoneState) -> float:
	return maxf(stone.vuln_radius_m - LODESTONE_RADIUS_SLACK_M, 1.2)


## LOS to the near face of the aim volume. Pull back a half-voxel so the probe ends in air
## just outside the stamp / crystal rather than in the first solid cell of the shell.
func _repair_has_los(from: Vector3, contact: Vector3) -> bool:
	if _city == null or not is_instance_valid(_city):
		return true
	if not _city.has_method("has_voxel_line_of_sight"):
		return true
	var delta := contact - from
	var dist := delta.length()
	if dist < 0.05:
		return true
	var pull := minf(voxel_size * 0.55, dist * 0.5)
	var to := from + delta * ((dist - pull) / dist)
	return bool(_city.call("has_voxel_line_of_sight", from, to))


## Closest intersection of ray `from + t*dir` with a sphere. INF when none in [0, max_m].
func _ray_sphere_t(
	from: Vector3, dir: Vector3, centre: Vector3, radius: float, max_m: float
) -> float:
	var to_c := from - centre
	var b := to_c.dot(dir)
	var c := to_c.dot(to_c) - radius * radius
	var disc := b * b - c
	if disc < 0.0:
		return INF
	var s := sqrt(disc)
	var t0 := -b - s
	var t1 := -b + s
	var t := t0 if t0 >= 0.0 else t1
	if t < 0.0 or t > max_m:
		return INF
	return t


## Foot→muzzle shaft as stacked spheres (same radius as the stamp hit volume).
func _ray_tower_shaft_t(
	from: Vector3, dir: Vector3, unit: UndeadUnit, radius: float, max_m: float
) -> float:
	var foot := unit.global_position
	var tip := unit.muzzle_world()
	var best := INF
	const SAMPLES := 5
	for i in range(SAMPLES):
		var p := foot.lerp(tip, float(i) / float(SAMPLES - 1))
		var t := _ray_sphere_t(from, dir, p, radius, max_m)
		if t < best:
			best = t
	return best


# --- Stone damage -----------------------------------------------------------

## Contact damage on every living stone. The centre is skipped while any outer stone stands: bodies
## may pile onto it and achieve nothing, which turns a lost centre plaza into a problem the player
## can still solve by going out and holding a flank.
func _tick_stones(delta: float) -> void:
	var shielded := centre_shielded()
	for stone: StoneState in _stones:
		if not stone.alive:
			continue
		if stone.is_centre and shielded:
			continue
		var chewers := _chewers_within(stone.pos, stone.vuln_radius_m)
		if chewers <= 0:
			continue
		stone.hp -= float(chewers) * _lodestone_dps_per_attacker * delta
		if stone.hp > 0.0:
			continue
		stone.hp = 0.0
		stone.alive = false
		_on_stone_destroyed(stone)
		if _phase != Phase.RUNNING:
			## The centre went down and the run is over — nothing left to tick.
			return


func _chewers_within(aim: Vector3, radius_m: float) -> int:
	var r2 := radius_m * radius_m
	var n := 0
	for unit: UndeadUnit in _alive:
		if unit == null or not is_instance_valid(unit) or not unit.is_alive():
			continue
		var d2 := Vector2(
			unit.global_position.x - aim.x, unit.global_position.z - aim.z
		).length_squared()
		if d2 <= r2:
			n += 1
	return n


## An outer stone is gone for the rest of the run. Repair only works while it still stands —
## once it falls there is no rebuild. The four are the run's clock; the last one falling is what
## puts the Lodestone in reach.
func _on_stone_destroyed(stone: StoneState) -> void:
	if stone.is_centre:
		_on_lodestone_destroyed()
		return
	_unregister_beacon(stone)
	_drop_shield_arc(stone)
	var left := outer_stones_alive()
	print(
		"SiegeController: %s fell on wave %d — %d outer stone%s left"
		% [stone.label, _wave, left, "" if left == 1 else "s"]
	)
	if left > 0:
		return
	_register_centre_beacon()
	print("SiegeController: last stand — the Lodestone is exposed")


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
	## Beacons first: a banked pot must not leave the horde walking to stones nobody is defending.
	_clear_beacons()
	## The arcs outlive the run: they are the tile's own signage. Stones that fell during it stand
	## again for the next one, so their bridges come back with them — on teardown they go with the
	## controller instead, and `_ensure_shield_arcs` refuses to build during shutdown.
	_reset_stones()
	_ensure_shield_arcs()
	_clear_gate_lights()
	_gate_weights = PackedFloat32Array()
	_next_gate_weights = PackedFloat32Array()
	_primary_gate = -1
	_next_primary_gate = -1
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
	_lodestone_base_hp = GameData.siege_float("lodestone_hp")
	_outer_stone_hp = GameData.siege_float("outer_stone_hp")
	_lodestone_vuln_radius_m = GameData.siege_float("lodestone_vulnerable_radius_m")
	_gate_primary_share = GameData.siege_float("gate_primary_share")
	_gate_weight_floor = GameData.siege_float("gate_weight_floor")
	_gate_falloff = GameData.siege_float("gate_falloff")
	_withdraw_clear_radius_m = GameData.siege_float("withdraw_clear_radius_m")
	_deploy_sec = GameData.siege_float("deploy_sec")
	_wave_period_sec = GameData.siege_float("wave_period_sec")
	_wave_drip_fraction = GameData.siege_float("wave_drip_fraction")
	_alive_target_base = GameData.siege_int("alive_target_base")
	_alive_target_growth = GameData.siege_int("alive_target_growth")
	_district_cap = GameData.siege_int("district_alive_cap")
	_spawn_interval_sec = GameData.siege_float("spawn_interval_sec")
	_hp_growth = GameData.siege_float("hp_growth_per_wave")
	_damage_growth = GameData.siege_float("damage_growth_per_wave")
	_lodestone_dps_per_attacker = GameData.siege_float("lodestone_dps_per_attacker")
	_repair_energy_per_sec = GameData.siege_float("repair_energy_per_sec")
	_repair_hp_per_sec = GameData.siege_float("repair_hp_per_sec")
	_repair_range_m = GameData.siege_float("repair_range_m")
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


## Queue a plate for every build site, then stand the first batch up immediately. The rest arrive
## a few per frame: hundreds of sites at eight nodes each is a hitch if built in one go, and the
## player cannot press a plate across the quarter in the first second anyway.
func _spawn_pad_panels() -> void:
	_clear_pad_panels()
	if layout == null:
		return
	_plate_queue = PackedInt32Array()
	for i in range(layout.pad_count()):
		_plate_queue.append(i)
	_tick_plate_build()


func _tick_plate_build() -> void:
	if _plate_queue.is_empty():
		return
	var made := 0
	while made < PLATES_PER_FRAME and not _plate_queue.is_empty():
		var pad_index := _plate_queue[0]
		_plate_queue.remove_at(0)
		made += 1
		if _pad_tower.get(pad_index, null) != null:
			continue
		_build_pad_panel(pad_index)


func _build_pad_panel(pad_index: int) -> void:
	var lode := lodestone_world_pos()
	var pad := _pad_world_pos(pad_index)
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
	panel.call("setup_pad", origin, yaw, pad_index)
	## Born deaf. `_tick_plate_proximity` hands a collider to the plates the player can actually
	## reach; a fresh plate with a live body would swallow shots from across the quarter.
	panel.call("set_collision_enabled", false)
	panel.connect("pad_pressed", _on_pad_pressed)
	_pad_panels[pad_index] = panel


## Colliders follow the player out to draw range; operating still needs PLATE_TOUCH_M.
func _tick_plate_proximity(delta: float) -> void:
	_plate_prox_acc += delta
	if _plate_prox_acc < PLATE_PROXIMITY_INTERVAL_SEC:
		return
	_plate_prox_acc = 0.0
	if _pad_panels.is_empty():
		return
	var player := _player_position()
	var detect_m: float = float(SiegePadPanelScript.VIEW_DISTANCE_M)
	var detect2 := detect_m * detect_m
	for key: Variant in _pad_panels.keys():
		var panel := _pad_panels[key] as Node3D
		if panel == null or not is_instance_valid(panel) or not panel.visible:
			continue
		var near := panel.global_position.distance_squared_to(player) <= detect2
		if bool(panel.call("is_collision_enabled")) != near:
			panel.call("set_collision_enabled", near)


func _player_position() -> Vector3:
	if (
		_city == null
		or not is_instance_valid(_city)
		or not _city.has_method("get_player_position")
	):
		push_error("SiegeController: the city cannot report a player position")
		assert(false, "SiegeController: no player position")
		return Vector3.ZERO
	return _city.call("get_player_position") as Vector3


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
	for key: Variant in _pad_panels.keys():
		var panel := _pad_panels[key] as Node
		if panel != null and is_instance_valid(panel):
			panel.queue_free()
	_pad_panels.clear()
	_plate_queue = PackedInt32Array()
	_close_build_picker()


func _hide_pad_panel(pad_index: int) -> void:
	var panel := _pad_panels.get(pad_index, null) as Node
	if panel != null and is_instance_valid(panel):
		panel.call("set_hit_enabled", false)


## The plates themselves carry no pot state; the affordable list lives in the picker, so a pot
## change only has to re-list whatever picker is currently up.
func _refresh_pad_panels() -> void:
	for key: Variant in _pad_panels.keys():
		var panel := _pad_panels[key] as Node3D
		if panel != null and is_instance_valid(panel) and panel.visible:
			panel.call("refresh")
	if _city != null and is_instance_valid(_city):
		_city.call("refresh_siege_build_picker")


## The "+" plate was pressed: hand the pad to the screen-space picker at the mouse.
## Hits beyond operate range still swallow the shot (collider is live) but only toast.
func _on_pad_pressed(pad_index: int) -> void:
	if not is_running():
		return
	if _pad_tower.get(pad_index, null) != null:
		return
	if _city == null or not is_instance_valid(_city):
		push_error("SiegeController._on_pad_pressed: no city")
		assert(false, "SiegeController: pad press without a city")
		return
	var panel := _pad_panels.get(pad_index, null) as Node3D
	if panel != null and is_instance_valid(panel):
		var dist := panel.global_position.distance_to(_player_position())
		if dist > PLATE_TOUCH_M:
			_toast_too_far_to_operate()
			return
	_city.call("open_siege_build_picker", pad_index, self)


func _toast_too_far_to_operate() -> void:
	_toast_message("too far to operate")


func _toast_message(text: String) -> void:
	if _city == null or not is_instance_valid(_city) or not _city.has_method("get_loot_toast"):
		return
	var toast := _city.call("get_loot_toast") as Object
	if toast == null or not is_instance_valid(toast):
		return
	if toast.has_method("show_message"):
		toast.call("show_message", text)


func _close_build_picker() -> void:
	if _city != null and is_instance_valid(_city):
		_city.call("close_siege_build_picker")


# --- Tower voxel ward -------------------------------------------------------

## Null only while the city is being torn down (see `_beacon_registry`).
func _voxel_ward() -> VoxelWard:
	if _city == null or not is_instance_valid(_city):
		return null
	if not _city.has_method("voxel_ward"):
		push_error("SiegeController: the city has no voxel ward")
		assert(false, "SiegeController: city cannot ward voxels")
		return null
	return _city.call("voxel_ward") as VoxelWard


## Hold a fresh tower's stamp against damage for as long as the tower stands. Its hit points are how
## it is meant to come down; a blast or a monster's bolt that instead carved the stone out from under
## it would leave a live turret firing from inside a hole.
func _ward_claim(unit: UndeadUnit, cells: Array[Vector3i]) -> void:
	var ward := _voxel_ward()
	if ward == null:
		return
	ward.claim(unit.get_instance_id(), cells)


## Give a dead tower's cells back. Returns the cells it held so the stamp can be demolished.
func _ward_release(unit: UndeadUnit) -> Array[Vector3i]:
	var empty: Array[Vector3i] = []
	var ward := _voxel_ward()
	if ward == null or unit == null:
		return empty
	return ward.release(unit.get_instance_id())


## Tear the stamp out of the world. Death scatters debris like a player carve; run teardown just
## clears, so withdrawing a dozen towers does not dump a debris storm on the plaza.
func _demolish_stamp(unit: UndeadUnit, cells: Array[Vector3i], scatter: bool) -> void:
	if cells.is_empty() or _city == null or not is_instance_valid(_city):
		return
	if not _city.has_method("destroy_voxels_with_debris"):
		push_error("SiegeController: city cannot demolish tower stamps")
		assert(false, "SiegeController: city missing destroy_voxels_with_debris")
		return
	var centre := Vector3.ZERO
	if unit != null and is_instance_valid(unit):
		centre = unit.global_position
	else:
		## Fall back to the first cell's world centre when the host is already gone.
		var vox: Vector3i = cells[0]
		var terrain: VoxelTerrain = _city.call("voxel_terrain") as VoxelTerrain
		if terrain != null:
			centre = terrain.to_global(
				Vector3(float(vox.x) + 0.5, float(vox.y) + 0.5, float(vox.z) + 0.5)
			)
		else:
			centre = Vector3(float(vox.x) + 0.5, float(vox.y) + 0.5, float(vox.z) + 0.5) * voxel_size
	_city.call("destroy_voxels_with_debris", cells, centre, scatter)


func _on_tower_died(unit: UndeadUnit, _was_giant: bool, pad_index: int) -> void:
	_pad_tower.erase(pad_index)
	if unit != null:
		var cells := _ward_release(unit)
		_demolish_stamp(unit, cells, true)
	## Show the pad's "+" again so the player can rebuild. The collider stays for
	## `_tick_plate_proximity` to hand back, which is why this re-shows rather than re-enabling hits.
	if is_running():
		var panel := _pad_panels.get(pad_index, null) as Node
		if panel != null and is_instance_valid(panel):
			panel.call("set_hit_enabled", true)
			panel.call("set_collision_enabled", false)
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
		var cells := _ward_release(unit)
		_demolish_stamp(unit, cells, false)
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
	## Breach-side of the Lodestone, face toward the approach (see Ui3D class doc —
	## `atan2(outward…)` would aim into the crystal).
	var outward := Vector2.ZERO
	for d: Vector2i in layout.breach_dirs:
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
	_panel.details_requested.connect(_on_panel_details)


func _on_panel_start() -> void:
	if not start_run():
		_refresh_panel()


func _on_panel_details() -> void:
	if _city != null and is_instance_valid(_city) and _city.has_method("open_siege_details"):
		_city.call("open_siege_details")


## The console is a between-runs object, and during a run it is not merely useless but harmful: it
## stands a metre and a half from the crystal, and `CityWalker._try_world_interact` turns any shot
## that crosses a `Ui3D` collider into a button press instead of a bolt. A shot aimed at a body by
## the stone banked a whole run that way. Everything the player needs mid-run is on `SiegeHud`.
func _refresh_panel() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var live := is_running()
	_panel.set_hit_enabled(not live)
	if not live:
		_panel.refresh()
