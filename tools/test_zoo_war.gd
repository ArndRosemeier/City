## Monster Zoo runtime: the spectator cloak and the forever-war spawn loop.
##
## The bake test covers the geometry; this one covers the two rules that make the district
## behave: a cloaked player is nobody's target and gets their own faction back on a timer,
## and forty stations refill emptied ground faster than held ground without ever running
## the roster dry.
##
## Run: powershell -File tools\run_test.ps1 test_zoo_war
extends Node

const ZooControllerScript := preload("res://scripts/city/zoo_controller.gd")
const ZooLayoutScript := preload("res://scripts/city/zoo_layout.gd")
const CityWalkerScript := preload("res://scripts/city/city_walker.gd")
const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")

const TERRITORIES := 6
const TICK := 0.25

var _failed := false


## CityRoot without a city under it: the controller only ever asks it for the player and
## for the cloak HUD, and both of those are answerable without booting a world.
class TestCity:
	extends CityRoot

	var faction_writes: Array[int] = []
	var cloak_shown: float = -1.0
	var cloak_hidden: int = 0

	func _ready() -> void:
		pass

	func bind_player(walker: CharacterBody3D) -> void:
		_walker = walker

	func set_player_combat_faction(id: int) -> void:
		faction_writes.append(id)
		super.set_player_combat_faction(id)

	func show_zoo_cloak(seconds_left: float) -> void:
		cloak_shown = seconds_left

	func hide_zoo_cloak() -> void:
		cloak_hidden += 1
		cloak_shown = -1.0


## Same director loop, with the roster replaced by a counter. Spawning real bodies would
## drag in nav, the catalogue and a live terrain for a rule that is about arithmetic.
class TestController:
	extends ZooController

	var spawned: PackedInt32Array = PackedInt32Array()
	var living: PackedInt32Array = PackedInt32Array()
	var refuse_spawn: bool = false

	func size_to(n: int) -> void:
		spawned.resize(n)
		spawned.fill(0)
		living.resize(n)
		living.fill(0)

	func _census() -> PackedInt32Array:
		return living.duplicate()

	func _global_alive() -> int:
		var n := 0
		for c in living:
			n += c
		return n

	func _spawn_at_station(index: int) -> bool:
		if refuse_spawn:
			return false
		## The pick still runs for real, so a faction with no spawn_ready body would show up
		## here as a refusal rather than as a silently idle station.
		if _pick_body(layout.seed_faction[index]).is_empty():
			return false
		spawned[index] += 1
		living[index] += 1
		return true

	func station_cooldown(index: int) -> float:
		return _station_cd[index]

	func plate_faction_under(brush: CityBrush, world: Vector3) -> int:
		return _plate_faction_under(brush, world)

	func drive(seconds: float, step: float) -> void:
		var t := 0.0
		while t < seconds:
			_tick_war(step)
			t += step


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_test_spectator_faction()
	if _failed:
		_quit()
		return
	_test_walker_faction_setter()
	if _failed:
		_quit()
		return
	_test_spawn_roster()
	if _failed:
		_quit()
		return
	_test_forever_war()
	if _failed:
		_quit()
		return
	_test_home_turf()
	if _failed:
		_quit()
		return
	_test_cloak()
	print("RESULT: OK" if not _failed else "RESULT: FAILED")
	_quit()


func _test_spectator_faction() -> void:
	var spec := MonsterFaction.Id.SPECTATOR
	if MonsterFaction.from_name(MonsterFaction.faction_name(spec)) != spec:
		_fail("FAIL SPECTATOR does not round-trip through its name")
		return
	for other: MonsterFaction.Id in MonsterFaction.all():
		if MonsterFaction.is_hostile(spec, other):
			_fail("FAIL a spectator may hunt %s" % MonsterFaction.faction_name(other))
			return
		if MonsterFaction.is_hostile(other, spec):
			_fail("FAIL %s may hunt a spectator" % MonsterFaction.faction_name(other))
			return
	## The cloak must not have made everyone friends.
	if not MonsterFaction.is_hostile(MonsterFaction.Id.UNDEAD, MonsterFaction.Id.HUMAN):
		_fail("FAIL the undead stopped hunting humans")
		return
	if MonsterFaction.monster_faction_at(0) != MonsterFaction.Id.UNDEAD:
		_fail("FAIL monster faction index 0 is not undead")
		return
	if MonsterFaction.monster_faction_at(5) != MonsterFaction.Id.ARCANE:
		_fail("FAIL monster faction index 5 is not arcane")
		return
	print("spectator: cloaked in both directions, six monster factions still indexed")


func _test_walker_faction_setter() -> void:
	var walker: CityWalker = CityWalkerScript.new() as CityWalker
	if walker.combat_faction() != int(MonsterFaction.Id.HUMAN):
		_fail("FAIL a fresh walker is faction %d, not human" % walker.combat_faction())
		walker.free()
		return
	walker.set_combat_faction(int(MonsterFaction.Id.SPECTATOR))
	if walker.combat_faction() != int(MonsterFaction.Id.SPECTATOR):
		_fail("FAIL set_combat_faction did not take")
		walker.free()
		return
	walker.set_combat_faction(int(MonsterFaction.Id.HUMAN))
	if walker.combat_faction() != int(MonsterFaction.Id.HUMAN):
		_fail("FAIL the walker did not get its own faction back")
		walker.free()
		return
	walker.free()
	print("walker faction: human → spectator → human")


func _test_spawn_roster() -> void:
	for f in range(MonsterFaction.MONSTER_COUNT):
		var fname := MonsterFaction.faction_name(MonsterFaction.monster_faction_at(f))
		var ids := CombatTable.spawnable_ids_for_faction(fname)
		if ids.is_empty():
			_fail("FAIL faction '%s' has no spawn_ready body to hold its ground" % fname)
			return
		for mid: String in ids:
			if CombatTable.faction_for(mid) != fname:
				_fail("FAIL '%s' is in the %s roster but fights for %s"
					% [mid, fname, CombatTable.faction_for(mid)])
				return
			if CombatTable.spawn_weight_for(mid) <= 0.0:
				_fail("FAIL '%s' has a non-positive spawn weight" % mid)
				return
	print("spawn roster: every monster faction can field a body")


func _test_forever_war() -> void:
	var city := TestCity.new()
	city.name = "TestCity"
	add_child(city)
	var ctrl := _make_controller(city, _make_layout())
	var base := GameData.zoo_float("base_spawn_interval_sec")
	var cap := GameData.zoo_int("per_territory_cap")

	## Forty stations must not all fire on the frame the district streams in.
	var max_cd := 0.0
	for i in range(TERRITORIES):
		max_cd = maxf(max_cd, ctrl.station_cooldown(i))
	if max_cd <= 0.0 or max_cd >= base:
		_fail("FAIL stations are not staggered across one interval (max cd %.2f)" % max_cd)
		city.queue_free()
		return

	## Left alone, the war fills every territory to the soft cap and stops there.
	ctrl.drive(base * 12.0, TICK)
	for i in range(TERRITORIES):
		if ctrl.living[i] != cap:
			_fail(
				"FAIL territory %d settled at %d living, soft cap is %d"
				% [i, ctrl.living[i], cap]
			)
			city.queue_free()
			return
	print("forever war: %d territories at the %d-body cap without a player" % [TERRITORIES, cap])

	## Wipe one cell. Inverse pressure means it refills before the full ones top up again.
	var wiped := 2
	ctrl.living[wiped] = 0
	var before := ctrl.spawned.duplicate()
	ctrl.drive(base * 3.0, TICK)
	var refilled := ctrl.spawned[wiped] - before[wiped]
	if refilled <= 0:
		_fail("FAIL an emptied territory got no reinforcements")
		city.queue_free()
		return
	for i in range(TERRITORIES):
		if i == wiped:
			continue
		if ctrl.spawned[i] - before[i] >= refilled:
			_fail(
				"FAIL held territory %d spawned as fast as the emptied one (%d vs %d)"
				% [i, ctrl.spawned[i] - before[i], refilled]
			)
			city.queue_free()
			return
	print("inverse pressure: emptied cell took %d bodies while full cells idled" % refilled)
	city.queue_free()


## Standing on somebody else's plate has to resolve to *their* faction, through whatever
## thin layer of rubble the scar pass left on top of the deck.
func _test_home_turf() -> void:
	CityVoxelNativeScript.require_loaded()
	var city := TestCity.new()
	city.name = "TestCityTurf"
	add_child(city)
	var ctrl := _make_controller(city, _make_layout())
	var brush: CityBrush = CityBrushScript.new() as CityBrush
	brush.use_offline_volume()
	var vs := 0.5
	var deck := 6
	## One column of plain ground, one of infernal turf, one of grove turf.
	brush.set_vox(Vector3i(10, deck, 10), VoxelMaterial.DIRT)
	brush.set_vox(Vector3i(12, deck, 10), VoxelMaterial.ZOO_TURF_INFERNAL)
	brush.set_vox(Vector3i(14, deck, 10), VoxelMaterial.ZOO_TURF_GROVE)

	var plain := ctrl.plate_faction_under(brush, _foot(10, deck, 10, vs))
	if plain != -1:
		_fail("FAIL ordinary dirt reported turf faction %d" % plain)
		city.queue_free()
		return
	var infernal := ctrl.plate_faction_under(brush, _foot(12, deck, 10, vs))
	if infernal != int(MonsterFaction.Id.INFERNAL):
		_fail("FAIL infernal turf resolved to faction %d" % infernal)
		city.queue_free()
		return
	var grove := ctrl.plate_faction_under(brush, _foot(14, deck, 10, vs))
	if grove != int(MonsterFaction.Id.GROVE):
		_fail("FAIL grove turf resolved to faction %d" % grove)
		city.queue_free()
		return
	## A body standing well clear of the ground is not on anybody's turf.
	var airborne := ctrl.plate_faction_under(
		brush, Vector3(12.25, float(deck + 6) * vs, 10.25)
	)
	if airborne != -1:
		_fail("FAIL a body six voxels up still read as standing on turf")
		city.queue_free()
		return
	## Plate damage carries no attacker, so nothing can retaliate against the floor.
	if DamageSource.target(DamageSource.Id.ZOO_PLATE) != DamageSource.Target.PLAYER:
		_fail("FAIL ZOO_PLATE does not hurt the player")
		city.queue_free()
		return
	if DamageSource.target(DamageSource.Id.ZOO_PLATE_MOB) != DamageSource.Target.CREATURE:
		_fail("FAIL ZOO_PLATE_MOB does not hurt creatures")
		city.queue_free()
		return
	if DamageSource.amount(DamageSource.Id.ZOO_PLATE) <= 0.0:
		_fail("FAIL zoo turf deals no damage")
		city.queue_free()
		return
	print("home turf: plates resolve to their owner and nobody else's")
	city.queue_free()


## Feet-height world point standing on the voxel at (x, y, z).
func _foot(x: int, y: int, z: int, vs: float) -> Vector3:
	return Vector3((float(x) + 0.5) * vs, float(y + 1) * vs + 0.05, (float(z) + 0.5) * vs)


func _test_cloak() -> void:
	var city := TestCity.new()
	city.name = "TestCityCloak"
	add_child(city)
	var walker: CityWalker = CityWalkerScript.new() as CityWalker
	walker.name = "TestWalker"
	city.add_child(walker)
	city.bind_player(walker)
	var ctrl := _make_controller(city, _make_layout())
	var duration := GameData.zoo_float("cloak_duration_sec")

	ctrl.request_cloak()
	if walker.combat_faction() != int(MonsterFaction.Id.SPECTATOR):
		_fail("FAIL the gate did not cloak the player")
		city.queue_free()
		return
	if not is_equal_approx(ctrl.cloak_seconds_left(), duration):
		_fail("FAIL cloak started at %.1fs, authored %.1fs" % [ctrl.cloak_seconds_left(), duration])
		city.queue_free()
		return

	## Burn most of it, then press again: the rule is refresh to full, not stack.
	_drive_cloak(ctrl, duration - 5.0)
	ctrl.request_cloak()
	if not is_equal_approx(ctrl.cloak_seconds_left(), duration):
		_fail("FAIL re-pressing the gate left %.1fs instead of a full refresh"
			% ctrl.cloak_seconds_left())
		city.queue_free()
		return
	if city.cloak_shown <= 0.0:
		_fail("FAIL the countdown is not on screen while cloaked")
		city.queue_free()
		return

	## And it does expire — a permanent cloak would make the whole district scenery.
	_drive_cloak(ctrl, duration + 1.0)
	if walker.combat_faction() != int(MonsterFaction.Id.HUMAN):
		_fail("FAIL the cloak lapsed without handing the player back to the war")
		city.queue_free()
		return
	if ctrl.cloak_seconds_left() != 0.0:
		_fail("FAIL a lapsed cloak still reports %.1fs" % ctrl.cloak_seconds_left())
		city.queue_free()
		return
	if city.cloak_hidden <= 0:
		_fail("FAIL the countdown stayed on screen after the cloak lapsed")
		city.queue_free()
		return
	print("cloak: 2:00 grant, refresh on re-press, human again on expiry")
	city.queue_free()


func _drive_cloak(ctrl: TestController, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		ctrl._tick_cloak(TICK)
		t += TICK


func _make_controller(city: TestCity, layout: ZooLayout) -> TestController:
	var ctrl := TestController.new()
	ctrl.name = "TestZooController"
	add_child(ctrl)
	ctrl.size_to(layout.territory_count())
	ctrl.setup(
		layout,
		Vector3i.ZERO,
		0.5,
		1234,
		city,
		Callable(),
		Callable(),
		Callable(),
		Callable()
	)
	## The harness drives the loop itself, one known step at a time.
	ctrl.set_process(false)
	return ctrl


## A minimal zoo: one territory per monster faction, laid out along a line.
func _make_layout() -> ZooLayout:
	var out: ZooLayout = ZooLayoutScript.new() as ZooLayout
	out.fence_rect = Rect2i(0, 0, 200, 60)
	out.field_rect = Rect2i(2, 2, 196, 56)
	out.deck_y = 6
	out.fence_top_y = 22
	out.gate_rect = Rect2i(90, 0, 11, 2)
	out.gate_dir = Vector2i(0, 1)
	out.plaza_rect = Rect2i(84, 2, 24, 22)
	out.cloak_gate_vox = Vector3i(108, 6, 6)
	out.seed_radius_vox = 16
	out.owner_cell_vox = 4
	out.owner_origin = out.field_rect.position
	out.owner_size = Vector2i(49, 14)
	out.ownership = PackedInt32Array()
	out.ownership.resize(out.owner_size.x * out.owner_size.y)
	out.seed_faction = PackedInt32Array()
	out.seed_faction.resize(TERRITORIES)
	for i in range(TERRITORIES):
		out.seed_xz.append(Vector2i(20 + i * 30, 30))
		out.spawner_vox.append(Vector3i(20 + i * 30, out.deck_y, 30))
		out.seed_faction[i] = i
	for cell in range(out.ownership.size()):
		out.ownership[cell] = cell % TERRITORIES
	return out


func _quit() -> void:
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		get_tree().quit(0)
