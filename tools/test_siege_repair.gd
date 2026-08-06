## Siege repair channel: pick damaged stones/towers along an aim ray, heal HP, gamedata rates.
##
## Run: powershell -File tools\run_test.ps1 test_siege_repair
extends Node

const SiegeControllerScript := preload("res://scripts/city/siege_controller.gd")
const SiegeLayoutScript := preload("res://scripts/city/siege_layout.gd")
const PlayerInventoryScript := preload("res://scripts/city/player_inventory.gd")
const BeaconRegistryScript := preload("res://scripts/city/beacon_registry.gd")
const MonsterFactionScript := preload("res://scripts/city/monster_faction.gd")

const FIX_CENTRE := 112
const FIX_OUTER_OFFSET := 100
const FIX_GATE_RADIUS := 108

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_check_gamedata()
	_check_stone_heal_and_pick()
	_check_tower_heal_and_pick()
	_check_full_hp_ignored()
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		print("RESULT: OK")
		get_tree().quit(0)


func _check_gamedata() -> void:
	var energy := GameData.siege_float("repair_energy_per_sec")
	var hp := GameData.siege_float("repair_hp_per_sec")
	var range_m := GameData.siege_float("repair_range_m")
	if not is_equal_approx(energy, 2.0):
		_fail("FAIL repair_energy_per_sec is %f, want 2" % energy)
	if not is_equal_approx(hp, 5.0):
		_fail("FAIL repair_hp_per_sec is %f, want 5" % hp)
	if range_m < 15.0 or range_m > 20.0:
		_fail("FAIL repair_range_m is %f, want 15–20" % range_m)
	print("gamedata: repair %.0f energy/s, %.0f hp/s, %.0f m" % [energy, hp, range_m])


func _make_layout() -> SiegeLayout:
	var layout: SiegeLayout = SiegeLayoutScript.new() as SiegeLayout
	layout.quarter_cells = Rect2i(0, 0, 8, 8)
	layout.quarter_vox = Rect2i(0, 0, 224, 224)
	layout.deck_y = 6
	layout.lodestone_xz = Vector2i(FIX_CENTRE, FIX_CENTRE)
	layout.lodestone_base_y = 6
	layout.lodestone_radius_vox = 5
	layout.lodestone_height_vox = 16
	layout.add_breach(Vector3i(0, 6, FIX_CENTRE), Vector2i(1, 0))
	layout.add_pad(Vector3i(40, 6, 40), SiegeLayout.PadKind.STREET)
	for i in range(4):
		var sx := 1 if (i % 2) == 0 else -1
		var sz := 1 if i < 2 else -1
		layout.add_outer_stone(
			Vector2i(
				FIX_CENTRE + sx * FIX_OUTER_OFFSET, FIX_CENTRE + sz * FIX_OUTER_OFFSET
			),
			6,
			4,
			12
		)
	for g in range(8):
		var bearing := TAU * float(g) / 8.0
		var mouth := Vector3i(
			FIX_CENTRE + int(round(cos(bearing) * float(FIX_GATE_RADIUS))),
			6,
			FIX_CENTRE + int(round(sin(bearing) * float(FIX_GATE_RADIUS)))
		)
		var outward := Vector2i(1, 0)
		if absf(cos(bearing)) < absf(sin(bearing)):
			outward = Vector2i(0, 1 if sin(bearing) >= 0.0 else -1)
		elif cos(bearing) < 0.0:
			outward = Vector2i(-1, 0)
		layout.add_hell_gate(mouth, outward, bearing)
	return layout


func _boot_ctrl() -> Dictionary:
	var city := _FakeCity.new()
	city.name = "FakeCity"
	add_child(city)
	var layout := _make_layout()
	if not layout.is_valid():
		_fail("FAIL fixture layout invalid")
		return {}
	var ctrl: SiegeController = SiegeControllerScript.new() as SiegeController
	add_child(ctrl)
	ctrl.setup(
		layout,
		Vector3i.ZERO,
		0.5,
		42,
		city,
		Callable(),
		Callable(),
		Callable()
	)
	if not ctrl.start_run():
		_fail("FAIL start_run rejected")
		return {}
	return {"city": city, "ctrl": ctrl}


func _check_stone_heal_and_pick() -> void:
	var boot := _boot_ctrl()
	if boot.is_empty():
		return
	var ctrl: SiegeController = boot["ctrl"] as SiegeController
	var stones := ctrl.stones()
	if stones.size() < 2:
		_fail("FAIL expected centre + outers")
		return
	var outer: SiegeController.StoneState = null
	for s: SiegeController.StoneState in stones:
		if not s.is_centre:
			outer = s
			break
	if outer == null:
		_fail("FAIL no outer stone")
		return
	outer.hp = outer.hp_max * 0.4
	var before := outer.hp
	var healed := ctrl.heal_stone(outer, 5.0)
	if not is_equal_approx(healed, 5.0) or not is_equal_approx(outer.hp, before + 5.0):
		_fail("FAIL heal_stone applied %f (hp now %f)" % [healed, outer.hp])
	## Cap at max.
	outer.hp = outer.hp_max - 2.0
	healed = ctrl.heal_stone(outer, 10.0)
	if not is_equal_approx(healed, 2.0) or not is_equal_approx(outer.hp, outer.hp_max):
		_fail("FAIL heal_stone overheal leaked (%f / hp %f)" % [healed, outer.hp])

	outer.hp = outer.hp_max * 0.5
	var aim_point := outer.pos + Vector3(0.0, outer.apex_m * 0.45, 0.0)
	var from := aim_point + Vector3(8.0, 1.0, 0.0)
	var dir := (aim_point - from).normalized()
	var pick: Dictionary = ctrl.pick_repair_target(from, dir)
	if pick.is_empty() or str(pick.get("kind", "")) != "stone":
		_fail("FAIL pick_repair_target missed damaged outer stone")
	elif pick.get("stone") != outer:
		_fail("FAIL pick_repair_target chose the wrong stone")
	else:
		var applied := ctrl.apply_repair(pick, ctrl.repair_hp_per_sec())
		if applied <= 0.0:
			_fail("FAIL apply_repair healed nothing on a damaged stone")
	## Dead stones are not repairable.
	outer.hp = 0.0
	outer.alive = false
	pick = ctrl.pick_repair_target(from, dir)
	if not pick.is_empty() and pick.get("stone") == outer:
		_fail("FAIL pick_repair_target offered a dead stone")
	print("stones: heal + ray pick + dead rejected")
	ctrl.shutdown()
	ctrl.queue_free()
	(boot["city"] as Node).queue_free()


func _check_tower_heal_and_pick() -> void:
	var boot := _boot_ctrl()
	if boot.is_empty():
		return
	var ctrl: SiegeController = boot["ctrl"] as SiegeController
	var tower := UndeadUnit.new()
	tower.name = "TestTower"
	add_child(tower)
	tower.global_position = Vector3(20.0, 1.0, 0.0)
	tower.set("_alive", true)
	tower.set("_health", 40.0)
	tower.set("_health_max", 100.0)
	tower.set("_siege_tower", true)
	tower.set("_structure_hit_radius_m", 2.0)
	tower.set("_muzzle_height_m", 3.0)
	ctrl._towers.append(tower)

	var healed := tower.apply_heal(5.0)
	if not is_equal_approx(healed, 5.0) or not is_equal_approx(tower.health(), 45.0):
		_fail("FAIL apply_heal on tower: healed %f hp now %f" % [healed, tower.health()])

	## Aim at the ORB tip height — a host-height sphere alone used to miss this and leave the blaster.
	var tip := tower.muzzle_world()
	var from := tip + Vector3(0.0, 0.0, 10.0)
	var dir := (tip - from).normalized()
	var pick: Dictionary = ctrl.pick_repair_target(from, dir)
	if pick.is_empty() or str(pick.get("kind", "")) != "tower":
		_fail("FAIL pick_repair_target missed damaged tower (tip aim)")
	elif pick.get("unit") != tower:
		_fail("FAIL pick_repair_target chose the wrong tower")
	else:
		var applied := ctrl.apply_repair(pick, 3.0)
		if not is_equal_approx(applied, 3.0):
			_fail("FAIL apply_repair on tower healed %f, want 3" % applied)
	print("towers: apply_heal + tip-height ray pick")
	ctrl.shutdown()
	ctrl.queue_free()
	tower.queue_free()
	(boot["city"] as Node).queue_free()


func _check_full_hp_ignored() -> void:
	var boot := _boot_ctrl()
	if boot.is_empty():
		return
	var ctrl: SiegeController = boot["ctrl"] as SiegeController
	## Fresh stones are full — LMB must keep the blaster, so pick returns empty.
	var centre := ctrl.lodestone_world_pos() + Vector3(0.0, 2.0, 0.0)
	var from := centre + Vector3(6.0, 0.0, 0.0)
	var dir := (centre - from).normalized()
	var pick: Dictionary = ctrl.pick_repair_target(from, dir)
	if not pick.is_empty():
		_fail("FAIL pick_repair_target offered a full-HP Lodestone")
	## Out of range.
	var stones := ctrl.stones()
	var outer: SiegeController.StoneState = null
	for s: SiegeController.StoneState in stones:
		if not s.is_centre:
			outer = s
			break
	outer.hp = outer.hp_max * 0.5
	var aim := outer.pos + Vector3(0.0, outer.apex_m * 0.45, 0.0)
	from = aim + Vector3(ctrl.repair_range_m() + 5.0, 0.0, 0.0)
	dir = (aim - from).normalized()
	pick = ctrl.pick_repair_target(from, dir)
	if not pick.is_empty():
		_fail("FAIL pick_repair_target reached past repair_range_m")
	print("gates: full HP and out-of-range both empty")
	ctrl.shutdown()
	ctrl.queue_free()
	(boot["city"] as Node).queue_free()


class _FakeCity:
	extends Node

	var inventory: PlayerInventory = PlayerInventoryScript.new() as PlayerInventory
	var _faction: int = int(MonsterFactionScript.Id.HUMAN)
	var active_siege: SiegeController = null
	var player_pos: Vector3 = Vector3.ZERO
	var beacons: BeaconRegistry = BeaconRegistryScript.new() as BeaconRegistry

	func get_inventory() -> PlayerInventory:
		return inventory

	func beacon_registry() -> BeaconRegistry:
		return beacons

	func get_player_position() -> Vector3:
		return player_pos

	func set_player_combat_faction(id: int) -> void:
		_faction = id

	func player_faction() -> int:
		return _faction

	func begin_siege_run(ctrl: SiegeController) -> void:
		active_siege = ctrl

	func end_siege_run(ctrl: SiegeController) -> void:
		if active_siege == ctrl:
			active_siege = null

	func has_voxel_line_of_sight(_from: Vector3, _to: Vector3) -> bool:
		return true
