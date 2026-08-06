## Monster kill gem haul: score from max HP, random tier partition, player-kill only.
##
## Run: powershell -File tools\run_test.ps1 test_monster_gem_drop
extends Node

const MonsterGemDropScript := preload("res://scripts/city/monster_gem_drop.gd")
const VoxelMaterialScript := preload("res://scripts/city/voxel_material.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")
const MonsterRosterScript := preload("res://scripts/city/monster_roster.gd")

const VOXEL_SIZE := 0.5
const FIELD_Y_MAX := 47
const TILE := Vector2i(-431, -431)
const ORIGIN := Vector3i(71000, 0, 71000)
const SX := 64
const SZ := 64
const BODY_SEED := 20260805

var _failed := false
var _nav: NavService
var _city: TestCity
var _director: TestDirector
var _terrain: VoxelTerrain


class TestCity:
	extends CityRoot
	var haul_calls: int = 0
	var haul_max_hp: float = -1.0

	func grant_monster_kill_haul(_world_pos: Vector3, max_hp: float) -> void:
		haul_calls += 1
		haul_max_hp = max_hp


class TestDirector:
	extends UndeadInvasionDirector

	func bind(city: CityRoot, terrain: VoxelTerrain, lod: NavLod) -> void:
		_city = city
		var monsters = MonsterRosterScript.new()
		monsters.name = "MonsterRoster"
		add_child(monsters)
		monsters.setup(city, terrain, lod)
		_roster = monsters


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_city = TestCity.new()
	_check_score()
	_check_recipe_drop_chance()
	_check_partition()
	_check_roll_values()
	_check_tier_mats()
	if _failed:
		_quit()
		return
	if not _boot_nav():
		_quit()
		return
	await _check_player_kill_grants()
	if _failed:
		_quit()
		return
	await _check_mob_kill_skips()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	_quit()


func _check_score() -> void:
	var cases: Array = [
		[0.0, 0],
		[39.9, 0],
		[40.0, 1],
		[79.9, 1],
		[80.0, 2],
		[110.0, 2],
		[205.0, 5],
	]
	for entry: Variant in cases:
		var pair: Array = entry
		var hp := float(pair[0])
		var want := int(pair[1])
		var got: int = MonsterGemDropScript.score_for_max_hp(hp)
		if got != want:
			_fail("FAIL score_for_max_hp(%s) = %d, expected %d" % [hp, got, want])
			return
	print("OK score_for_max_hp")
	_check_siege_floor()


func _check_recipe_drop_chance() -> void:
	var cases: Array = [
		[0.0, 0.0],
		[30.0, 1.0],
		[60.0, 2.0],
		[300.0, 10.0],
		[3000.0, 100.0],
		[9000.0, 100.0],
	]
	for entry: Variant in cases:
		var pair: Array = entry
		var hp := float(pair[0])
		var want := float(pair[1])
		var got := MonsterGemDropScript.recipe_drop_chance_pct(hp)
		if not is_equal_approx(got, want):
			_fail("FAIL recipe_drop_chance_pct(%s) = %s, want %s" % [hp, got, want])
			return
	## Deterministic: chance 0 never fires; chance 100 always fires.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	if MonsterGemDropScript.rolls_recipe_drop(0.0, rng):
		_fail("FAIL rolls_recipe_drop(0) must be false")
		return
	var hits := 0
	const TRIALS := 400
	rng.seed = 2
	for _i in range(TRIALS):
		if MonsterGemDropScript.rolls_recipe_drop(30.0, rng):
			hits += 1
	## 1% of 400 ≈ 4; allow a wide band so the harness is not flaky.
	if hits < 1 or hits > 20:
		_fail("FAIL rolls_recipe_drop(30) hit %d / %d (want ~4)" % [hits, TRIALS])
		return
	rng.seed = 3
	for _i in range(20):
		if not MonsterGemDropScript.rolls_recipe_drop(3000.0, rng):
			_fail("FAIL rolls_recipe_drop at 100%% missed")
			return
	print("OK recipe drop chance (max_hp/30)%%")


## Siege waves are KayKit fodder (~34 HP). The global score floor pays those nothing, so a live
## run must raise a one-stone floor or the pot never refills after the stake is spent.
func _check_siege_floor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var empty: Array[int] = MonsterGemDropScript.roll_mats(34.0, rng, 0)
	if not empty.is_empty():
		_fail("FAIL roll_mats(34) without a floor still paid %d stones" % empty.size())
		return
	var floored: Array[int] = MonsterGemDropScript.roll_mats(34.0, rng, 1)
	if floored.size() != 1:
		_fail("FAIL roll_mats(34, min_score=1) paid %d stones, want 1" % floored.size())
		return
	if MonsterGemDropScript.value_for_mat(floored[0]) != 1:
		_fail("FAIL siege floor stone is not a tier-1 gem")
		return
	## A body that already scores must not be capped down to the floor.
	var big: Array[int] = MonsterGemDropScript.roll_mats(110.0, rng, 1)
	var score := 0
	for mat in big:
		score += MonsterGemDropScript.value_for_mat(mat)
	if score != 2:
		_fail("FAIL roll_mats(110, min_score=1) scored %d, want 2" % score)
		return
	print("OK siege min_score floor")


func _check_partition() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	if not MonsterGemDropScript.partition_score(0, rng).is_empty():
		_fail("FAIL partition_score(0) should be empty")
		return
	for score in [1, 2, 3, 4, 5, 7, 12]:
		for _trial in range(40):
			var parts: Array[int] = MonsterGemDropScript.partition_score(score, rng)
			var total := 0
			for v in parts:
				if v < 1 or v > 3:
					_fail("FAIL partition value %d out of 1..3 for score %d" % [v, score])
					return
				total += v
			if total != score:
				_fail(
					"FAIL partition of %d summed to %d: %s" % [score, total, str(parts)]
				)
				return
	print("OK partition_score")


func _check_roll_values() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	if not MonsterGemDropScript.roll_mats(39.0, rng).is_empty():
		_fail("FAIL roll_mats under score 1 should be empty")
		return
	for _trial in range(30):
		var mats: Array[int] = MonsterGemDropScript.roll_mats(120.0, rng)
		var total := 0
		for mat_id in mats:
			var v: int = MonsterGemDropScript.value_for_mat(mat_id)
			if v < 1:
				_fail("FAIL roll_mats produced non-tier gem %d" % mat_id)
				return
			total += v
		if total != 3:
			_fail("FAIL roll_mats(120) value sum %d, expected 3" % total)
			return
	print("OK roll_mats")


func _check_tier_mats() -> void:
	var want := {
		1: [VoxelMaterialScript.GEM_QUARTZ, VoxelMaterialScript.GEM_AMBER],
		2: [VoxelMaterialScript.GEM_TOPAZ, VoxelMaterialScript.GEM_SAPPHIRE],
		3: [VoxelMaterialScript.GEM_EMERALD, VoxelMaterialScript.GEM_DIAMOND],
	}
	for value: Variant in want.keys():
		var mats: Array = want[value]
		for mat_id: Variant in mats:
			if MonsterGemDropScript.value_for_mat(int(mat_id)) != int(value):
				_fail("FAIL value_for_mat(%d) != %d" % [int(mat_id), int(value)])
				return
	print("OK tier mats")


func _boot_nav() -> bool:
	_nav = NavService.instance()
	_nav.ensure_configured(VOXEL_SIZE)
	if not _nav.is_configured():
		_fail("FAIL NavService did not configure")
		return false
	var bake := _bake_tile()
	if bake == null:
		return false
	if not _nav.register_district(TILE, bake):
		_fail("FAIL NavService refused the test tile")
		return false
	_terrain = VoxelTerrain.new()
	_terrain.name = "VoxelTerrain"
	add_child(_terrain)
	_terrain.scale = Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
	_director = TestDirector.new()
	_director.name = "UndeadInvasion"
	add_child(_director)
	_director.bind(_city, _terrain, NavLod.for_collision_view(48, VOXEL_SIZE))
	return true


func _bake_tile() -> NativeNavBake:
	var volume := CityVoxelNativeScript.make_volume() as NativeOfflineVoxelVolume
	volume.fill_box(Vector3i.ZERO, Vector3i(SX, 1, SZ), VoxelMaterial.CONCRETE)
	var tables := _nav.solidity_tables()
	var bake := CityVoxelNativeScript.make_nav_bake() as NativeNavBake
	var ok: bool = bake.bake_from_volume(
		volume,
		ORIGIN,
		SX,
		SZ,
		0,
		FIELD_Y_MAX,
		tables["class"],
		tables["top"],
		tables["destructible"],
		tables["climbable"],
		_nav.link_params()
	)
	if not ok:
		_fail("FAIL bake_from_volume rejected the test tile")
		return null
	return bake


func _w(vox: Vector3i) -> Vector3:
	return Vector3(
		float(ORIGIN.x + vox.x), float(ORIGIN.y + vox.y), float(ORIGIN.z + vox.z)
	) * VOXEL_SIZE


func _spawn_big() -> UndeadUnit:
	var unit := _director._spawn_unit(
		UndeadUnit.Role.MINION, _w(Vector3i(8, 1, 8)), BODY_SEED, "big/Dino"
	)
	if unit == null:
		_fail("FAIL director refused to spawn big/Dino")
		return null
	unit.set_physics_process(false)
	return unit


func _settle(unit: UndeadUnit) -> void:
	await get_tree().process_frame
	if is_instance_valid(unit):
		_director.despawn_unit(unit)
	await get_tree().process_frame


func _check_player_kill_grants() -> void:
	_city.haul_calls = 0
	_city.haul_max_hp = -1.0
	var unit := _spawn_big()
	if unit == null:
		return
	var want_hp := unit.health_max()
	var died := unit.apply_damage_scaled(
		DamageSource.Id.PLAYER_MELEE, 1000.0, "player", null
	)
	if not died:
		_fail("FAIL player melee did not kill big/Dino")
		await _settle(unit)
		return
	if _city.haul_calls != 1:
		_fail("FAIL player kill haul_calls=%d, expected 1" % _city.haul_calls)
		await _settle(unit)
		return
	if not is_equal_approx(_city.haul_max_hp, want_hp):
		_fail("FAIL haul max_hp=%s, expected %s" % [_city.haul_max_hp, want_hp])
		await _settle(unit)
		return
	if MonsterGemDropScript.score_for_max_hp(_city.haul_max_hp) < 1:
		_fail("FAIL player kill max_hp %s scored under 1" % _city.haul_max_hp)
		await _settle(unit)
		return
	print("OK player kill grants haul (max_hp=%s)" % _city.haul_max_hp)
	await _settle(unit)


func _check_mob_kill_skips() -> void:
	_city.haul_calls = 0
	var unit := _spawn_big()
	if unit == null:
		return
	var died := unit.apply_damage_scaled(
		DamageSource.Id.MONSTER_MELEE_MOB, 1000.0, "mob", null
	)
	if not died:
		_fail("FAIL mob melee did not kill big/Dino")
		await _settle(unit)
		return
	if _city.haul_calls != 0:
		_fail("FAIL mob kill still granted haul (%d calls)" % _city.haul_calls)
		await _settle(unit)
		return
	print("OK mob kill skips haul")
	await _settle(unit)


func _quit() -> void:
	if _director != null and is_instance_valid(_director):
		_director.clear_all()
	NavService.reset()
	if _city != null:
		_city.free()
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		get_tree().quit(0)
