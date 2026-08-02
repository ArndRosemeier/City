## A pad that owns a low room shrinks the bodies it drops into it.
##
## Castle dungeon storeys are seven voxels of pitch minus a two-voxel slab, so a corridor has
## 2.5 m of headroom. A Quaternius body is drawn up to four metres tall and paths on the monster
## profile, which demands 3.5 m of clearance — dropped into a corridor it stands wedged between
## slab and ceiling with no walkable span to leave on, which reads in game as a mob stuck in the
## ground. `FactionPadSpawner` clamps every body it spawns to `dungeon_summoner.max_height_m`.
##
## What is pinned here is that the clamp moves the three things that matter and not just the
## drawing: the mesh, the collision capsule, and the navigation profile. A clamp that only
## rescaled the model would leave the body colliding at full size and still stuck.
##
## Run: powershell -File tools\run_test.ps1 test_mob_height_clamp
extends Node

const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")

const VOXEL_SIZE := 0.5
const FIELD_Y_MAX := 47
## Parked away from every district and from the other tests' tiles.
const TILE := Vector2i(-424, -424)
const ORIGIN := Vector3i(74000, 0, 74000)
const SX := 96
const SZ := 96

const BODY_SEED := 20260802
const EPS := 0.001
## The dungeon's own limit, and what a castle pad is tuned to.
const DUNGEON_MAX_M := 1.5
## Tall enough that no body in the catalogue reaches it, so the clamp must decline to act.
const NO_LIMIT_M := 20.0
## A Quaternius Big body: drawn well over the dungeon limit and born on the monster profile.
const TALL_BODY := "big/Cactoro"

var _failed := false
var _nav: NavService
var _city: TestCity
var _director: TestDirector
var _terrain: VoxelTerrain


class TestCity:
	extends CityRoot

	func trigger_game_over(reason: String = "Converted by undead") -> void:
		pass


class TestDirector:
	extends UndeadInvasionDirector

	func bind(city: CityRoot, terrain: VoxelTerrain, lod: NavLod) -> void:
		_city = city
		var monsters := MonsterRoster.new()
		monsters.name = "MonsterRoster"
		add_child(monsters)
		monsters.setup(city, terrain, lod)
		_roster = monsters


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_city = TestCity.new()
	if not _boot_nav():
		_quit()
		return
	_test_the_dungeon_limit_is_authored()
	if _failed:
		_quit()
		return
	await _test_a_tall_body_is_shrunk_to_fit()
	if _failed:
		_quit()
		return
	await _test_a_body_that_already_fits_is_left_alone()
	if _failed:
		_quit()
		return
	await _test_the_clamp_will_not_collapse_a_body()
	_quit()


# ---------------------------------------------------------------------------
# The tuning the castle pads read
# ---------------------------------------------------------------------------

func _test_the_dungeon_limit_is_authored() -> void:
	var limit := GameData.section_float("dungeon_summoner", "max_height_m")
	if limit <= 0.0:
		_fail("FAIL dungeon_summoner.max_height_m is %.2f, must be positive" % limit)
		return
	if absf(limit - DUNGEON_MAX_M) > EPS:
		_fail(
			"FAIL dungeon_summoner.max_height_m is %.2f, expected the %.2f m the dungeon was cut for"
			% [limit, DUNGEON_MAX_M]
		)
		return
	print("tuning: castle pads clamp their bodies to %.2f m" % limit)


# ---------------------------------------------------------------------------
# Mesh, collider and navigation profile all follow the clamp
# ---------------------------------------------------------------------------

func _test_a_tall_body_is_shrunk_to_fit() -> void:
	var unit := _spawn(_w(Vector3i(20, 1, 20)), TALL_BODY)
	if unit == null:
		return
	var was_tall := unit.standing_height_m()
	if was_tall <= DUNGEON_MAX_M:
		_fail(
			"FAIL %s is only %.2f m tall, so it cannot show what the clamp does"
			% [TALL_BODY, was_tall]
		)
		await _settle(unit)
		return
	if unit.nav_profile_id() != NavProfile.Id.MONSTER:
		_fail(
			"FAIL %s paths as profile %d, expected MONSTER before the clamp"
			% [TALL_BODY, unit.nav_profile_id()]
		)
		await _settle(unit)
		return
	var was_capsule := _capsule_height(unit)
	var was_hit := unit.hit_half_height()

	unit.clamp_standing_height(DUNGEON_MAX_M)

	var now_tall := unit.standing_height_m()
	if now_tall > DUNGEON_MAX_M + EPS:
		_fail("FAIL the clamp left %s %.2f m tall, over the %.2f m limit" % [TALL_BODY, now_tall, DUNGEON_MAX_M])
		await _settle(unit)
		return
	var now_capsule := _capsule_height(unit)
	if now_capsule >= was_capsule - EPS:
		_fail(
			(
				"FAIL the collision capsule did not shrink: was %.2f m, now %.2f m — the body is"
				+ " drawn small but still collides full size"
			)
			% [was_capsule, now_capsule]
		)
		await _settle(unit)
		return
	if unit.hit_half_height() >= was_hit - EPS:
		_fail(
			"FAIL the hit volume did not shrink: was %.2f m, now %.2f m"
			% [was_hit, unit.hit_half_height()]
		)
		await _settle(unit)
		return
	## A dungeon corridor has 2.5 m of headroom and the monster profile wants 3.5 m, so a body
	## left on it has nowhere to walk however small it is drawn.
	if unit.nav_profile_id() != NavProfile.Id.UNDEAD:
		_fail(
			"FAIL a shrunk body still paths as profile %d, expected UNDEAD"
			% unit.nav_profile_id()
		)
		await _settle(unit)
		return
	print(
		"clamp: %s %.2f m -> %.2f m, capsule %.2f m -> %.2f m, now on the undead profile"
		% [TALL_BODY, was_tall, now_tall, was_capsule, now_capsule]
	)
	await _settle(unit)


func _test_a_body_that_already_fits_is_left_alone() -> void:
	var unit := _spawn(_w(Vector3i(30, 1, 20)), TALL_BODY)
	if unit == null:
		return
	var was_tall := unit.standing_height_m()
	var was_profile := unit.nav_profile_id()
	var was_capsule := _capsule_height(unit)

	unit.clamp_standing_height(NO_LIMIT_M)

	if absf(unit.character_scale - 1.0) > EPS:
		_fail("FAIL a body under the limit was rescaled to %.3f" % unit.character_scale)
		await _settle(unit)
		return
	if absf(unit.standing_height_m() - was_tall) > EPS:
		_fail("FAIL a body under the limit changed height to %.2f m" % unit.standing_height_m())
		await _settle(unit)
		return
	if absf(_capsule_height(unit) - was_capsule) > EPS:
		_fail("FAIL a body under the limit changed capsule to %.2f m" % _capsule_height(unit))
		await _settle(unit)
		return
	if unit.nav_profile_id() != was_profile:
		_fail("FAIL a body under the limit was moved off profile %d" % was_profile)
		await _settle(unit)
		return
	print("clamp: a body already under the limit keeps its size and its profile")
	await _settle(unit)


func _test_the_clamp_will_not_collapse_a_body() -> void:
	var unit := _spawn(_w(Vector3i(40, 1, 20)), TALL_BODY)
	if unit == null:
		return
	unit.clamp_standing_height(0.0001)
	if unit.character_scale < UndeadUnit.MIN_CHARACTER_SCALE - EPS:
		_fail(
			"FAIL an absurd limit shrank the body to %.4f, under the %.2f floor"
			% [unit.character_scale, UndeadUnit.MIN_CHARACTER_SCALE]
		)
		await _settle(unit)
		return
	print("clamp: an absurd limit stops at the %.2f scale floor" % UndeadUnit.MIN_CHARACTER_SCALE)
	await _settle(unit)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## The body's own collision capsule — the shape that decides whether it is wedged in the slab.
func _capsule_height(unit: UndeadUnit) -> float:
	for child in unit.get_children():
		var shape := child as CollisionShape3D
		if shape == null:
			continue
		var capsule := shape.shape as CapsuleShape3D
		if capsule != null:
			return capsule.height
	_fail("FAIL %s has no capsule to measure" % unit.name)
	return 0.0


func _spawn(at: Vector3, body_id: String) -> UndeadUnit:
	var unit := _director._spawn_unit(UndeadUnit.Role.MINION, at, BODY_SEED, body_id)
	if unit == null:
		_fail("FAIL the director refused to spawn %s" % body_id)
		return null
	## Nothing here is a navigation test; the bodies stand where they are put.
	unit.set_physics_process(false)
	return unit


func _settle(unit: UndeadUnit) -> void:
	await get_tree().process_frame
	if is_instance_valid(unit):
		_director.despawn_unit(unit)
	await get_tree().process_frame


func _boot_nav() -> bool:
	_nav = NavService.instance()
	_nav.ensure_configured(VOXEL_SIZE)
	if not _nav.is_configured():
		_fail("FAIL NavService did not configure")
		return false
	if not _nav.register_district(TILE, _bake_tile()):
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


func _quit() -> void:
	if _director != null and is_instance_valid(_director):
		_director.clear_all()
	NavService.reset()
	if _city != null:
		## Never entered the tree, so nothing else will free it.
		_city.free()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)
