## Spawn spires: the world-placed convert tower that owns a crypt / dungeon summoning station.
##
## Covers the four rules the feature stands on — the player may shoot it (a siege pad may not be
## shot), the kill always teaches a recipe, its summons outlive it, and the mass fits under the
## ceiling of the rooms it is stamped in.
##
## Run: powershell -File tools\run_test.ps1 test_spawn_tower
extends Node

const SpawnTowerScript := preload("res://scripts/city/spawn_tower.gd")
const SiegeTowerCatalogScript := preload("res://scripts/city/siege_tower_catalog.gd")
const SiegeControllerScript := preload("res://scripts/city/siege_controller.gd")
const CombatTableScript := preload("res://scripts/city/combat_table.gd")
const MonsterFactionScript := preload("res://scripts/city/monster_faction.gd")
const MonsterRosterScript := preload("res://scripts/city/monster_roster.gd")
const FactionPadSpawnerScript := preload("res://scripts/city/faction_pad_spawner.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")
const CastleComposerScript := preload("res://scripts/city/castle_composer.gd")
const GraveyardComposerScript := preload("res://scripts/city/graveyard_composer.gd")

const VOXEL_SIZE := 0.5
const FIELD_Y_MAX := 47
const TILE := Vector2i(-431, -431)
const ORIGIN := Vector3i(71000, 0, 71000)
const SX := 64
const SZ := 64
## Player swings thrown at the spire before the test calls it unkillable.
const KILL_SWINGS := 200

var _failed := false
## Bodies the station handed back through its despawn callback.
var _despawned := 0


class TestCity:
	extends CityRoot
	var spire_kills: int = 0

	## Count the grant and still run the real one, so the recipe path is the tested path.
	func grant_spawn_tower_kill(world_pos: Vector3) -> void:
		spire_kills += 1
		super.grant_spawn_tower_kill(world_pos)


## Stands in for a summoned body: the station only asks whether it is alive and whether it
## carries the pad's ownership meta.
class OwnedBody:
	extends Node

	func is_alive() -> bool:
		return true


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	CombatTableScript.reload()
	SiegeTowerCatalogScript.reload()
	_check_catalog_row()
	_check_combat_row()
	_check_summon_offset()
	_check_tower_body()
	_check_station_keeps_its_summons()
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		print("RESULT: OK")
		get_tree().quit(0)


## The spire is a siege tower row that is never for sale, wears the dark set interior rather than
## a glowing band, and is short enough to stand in a dungeon vault.
func _check_catalog_row() -> void:
	var def: RefCounted = SiegeTowerCatalogScript.by_id(SpawnTowerScript.TOWER_ID) as RefCounted
	if def == null:
		_fail("FAIL no '%s' row in the tower catalogue" % SpawnTowerScript.TOWER_ID)
		return
	if bool(def.get("buildable")):
		_fail("FAIL the spawn spire is listed as buildable — pads would sell it")
	var hp := float(def.get("hp"))
	var lo := INF
	var hi := 0.0
	for other_v: Variant in SiegeTowerCatalogScript.buildable():
		var other_hp := float((other_v as RefCounted).get("hp"))
		lo = minf(lo, other_hp)
		hi = maxf(hi, other_hp)
	if hp < lo or hp > hi:
		_fail("FAIL spire hp %.0f is outside the siege tower band %.0f–%.0f" % [hp, lo, hi])
	var voxels: PackedInt32Array = def.get("voxels") as PackedInt32Array
	var n := voxels.size() / 4
	if n <= 0:
		_fail("FAIL the spire stamp is empty")
		return
	for i in range(n):
		var mat: int = voxels[i * 4 + 3]
		if mat == VoxelMaterial.ORB:
			continue
		if mat != VoxelMaterial.FRACTAL_INTERIOR:
			_fail("FAIL spire body mat %d is not the dark set interior" % mat)
	_check_fits_underground(def)
	print("catalog: %.0f hp dark fractal spire, %d cells, never for sale" % [hp, n])


## The spire is stamped into rooms with a low ceiling. Its muzzle is where every line-of-sight
## probe starts: buried in the slab above, the tower acquires nothing and holds fire in silence.
func _check_fits_underground(def: RefCounted) -> void:
	var muzzle := SiegeTowerCatalogScript.muzzle_height_m(def, VOXEL_SIZE)
	var mass_top := (
		float(SiegeTowerCatalogScript.STAMP_BASE_CELLS + int(def.get("stamp_top_oy")) + 1)
		* VOXEL_SIZE
	)
	if muzzle <= mass_top:
		_fail("FAIL spire muzzle %.2f m sits in its own ORB cell (top %.2f m)" % [muzzle, mass_top])
		return
	## Both anchors are the plate's bottom face, so the ceiling is one plate cell plus the room's
	## air. The castle vault is the tighter of the two rooms the spire stands in.
	var vault_ceiling := float(1 + CastleComposerScript.DUNGEON_HEAD) * VOXEL_SIZE
	var crypt_ceiling := float(1 + GraveyardComposerScript.CRYPT_H) * VOXEL_SIZE
	if muzzle >= vault_ceiling:
		_fail(
			"FAIL spire muzzle %.2f m is inside a dungeon vault's slab (ceiling %.2f m)"
			% [muzzle, vault_ceiling]
		)
		return
	if muzzle >= crypt_ceiling:
		_fail(
			"FAIL spire muzzle %.2f m is inside the crypt's roof (ceiling %.2f m)"
			% [muzzle, crypt_ceiling]
		)
		return
	print(
		"fit: eye at %.2f m clears the mass at %.2f m and the vault roof at %.2f m"
		% [muzzle, mass_top, vault_ceiling]
	)


## Convert is the whole kit: a spire pulls bodies over and lets its summons do the killing.
func _check_combat_row() -> void:
	var def: RefCounted = SiegeTowerCatalogScript.by_id(SpawnTowerScript.TOWER_ID) as RefCounted
	if def == null:
		return
	var combat_id := str(def.get("combat_id"))
	if not CombatTableScript.has_monster(combat_id):
		_fail("FAIL no combat row '%s'" % combat_id)
		return
	if CombatTableScript.spawnable_ids().has(combat_id):
		_fail("FAIL '%s' is spawn-ready — a station could summon spires" % combat_id)
	var stats := CombatTableScript.resolve(combat_id)
	if stats == null:
		_fail("FAIL '%s' does not resolve" % combat_id)
		return
	if float(stats.get("speed_mult")) > 0.0:
		_fail("FAIL '%s' can move" % combat_id)
	var attacks: PackedStringArray = stats.get("attacks") as PackedStringArray
	if attacks.size() != 1 or attacks[0] != "orb_convert":
		_fail("FAIL '%s' kit is %s, want only orb_convert" % [combat_id, str(attacks)])
		return
	print("combat: %s is an immobile convert-only turret" % combat_id)


## Fresh bodies must not arrive inside the mass the station is standing under.
func _check_summon_offset() -> void:
	var def: RefCounted = SiegeTowerCatalogScript.by_id(SpawnTowerScript.TOWER_ID) as RefCounted
	if def == null:
		return
	var pad := Vector3(10.0, 4.0, 10.0)
	var summon: Vector3 = SpawnTowerScript.summon_world(pad, VOXEL_SIZE)
	if not is_equal_approx(summon.y, pad.y):
		_fail("FAIL the summon point left the floor (%.2f vs %.2f)" % [summon.y, pad.y])
	var gap := Vector2(summon.x - pad.x, summon.z - pad.z).length()
	var face := (float(int(def.get("stamp_radius_vox"))) + 0.5) * VOXEL_SIZE
	if gap <= face:
		_fail("FAIL summons arrive %.2f m out, inside the %.2f m stamp face" % [gap, face])
		return
	print("summons: station stands %.2f m clear of the %.2f m stamp face" % [gap, face])


## The body itself: owned by the faction it summons for, shootable by the player (a siege pad is
## not), and worth exactly one recipe when it goes down.
func _check_tower_body() -> void:
	var nav := NavService.instance()
	nav.ensure_configured(VOXEL_SIZE)
	if not nav.is_configured():
		_fail("FAIL NavService did not configure")
		return
	var bake := _bake_tile(nav)
	if bake == null:
		return
	if not nav.register_district(TILE, bake):
		_fail("FAIL NavService refused the test tile")
		return
	var terrain := VoxelTerrain.new()
	terrain.name = "VoxelTerrain"
	add_child(terrain)
	terrain.scale = Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
	var city: TestCity = TestCity.new()
	var roster: MonsterRoster = MonsterRosterScript.new() as MonsterRoster
	roster.name = "MonsterRoster"
	add_child(roster)
	roster.setup(city, terrain, NavLod.for_collision_view(48, VOXEL_SIZE))

	var def: RefCounted = SiegeTowerCatalogScript.by_id(SpawnTowerScript.TOWER_ID) as RefCounted
	var hp := float(def.get("hp"))
	var at := Vector3(
		float(ORIGIN.x + 8), float(ORIGIN.y + 1), float(ORIGIN.z + 8)
	) * VOXEL_SIZE
	var muzzle_h := (
		SiegeTowerCatalogScript.muzzle_height_m(def, VOXEL_SIZE)
		- SpawnTowerScript.HOST_LIFT_M
	)
	var hit_r := SiegeTowerCatalogScript.structure_hit_radius_m(def, VOXEL_SIZE)
	var tower := roster.spawn_faction_tower(
		str(def.get("combat_id")),
		at,
		hp,
		muzzle_h,
		hit_r,
		int(MonsterFactionScript.Id.UNDEAD)
	)
	if tower == null:
		_fail("FAIL the roster refused to spawn a spawn tower")
		_teardown(roster, terrain, city)
		return
	tower.set_physics_process(false)
	if not tower.is_siege_tower() or not tower.is_spawn_tower():
		_fail("FAIL the spire does not report as a spawn tower structure")
	if tower.faction() != int(MonsterFactionScript.Id.UNDEAD):
		_fail("FAIL spire faction is %d, want UNDEAD" % tower.faction())
	if not is_equal_approx(tower.health_max(), hp):
		_fail("FAIL spire max hp is %.1f, want %.1f" % [tower.health_max(), hp])
	_check_player_can_break_it(city, tower, hp)
	_teardown(roster, terrain, city)


## A siege pad rejects player fire — the player paid for it. A spire is the opposite structure on
## the opposite side, and the whole reward loop dies if the shots do nothing.
func _check_player_can_break_it(city: TestCity, tower: UndeadUnit, hp: float) -> void:
	tower.apply_damage_scaled(DamageSource.Id.PLAYER_MELEE, 1.0, "player", null)
	if tower.health() >= hp:
		_fail("FAIL player melee bounced off a hostile spire")
		return
	## Recipes only gate in Adventure — Sandbox knows the whole cookbook, so a drop there is a
	## no-op by design and proves nothing.
	city.get_loadout().reset_adventure()
	var missing := city.get_loadout().missing_recipe_ids().size()
	if missing <= 0:
		_fail("FAIL the fixture cookbook is already full, so no drop can be proven")
		return
	var swings := 1
	while tower.is_alive() and swings < KILL_SWINGS:
		tower.apply_damage_scaled(DamageSource.Id.PLAYER_MELEE, 1.0, "player", null)
		swings += 1
	if tower.is_alive():
		_fail("FAIL %d player swings did not bring a %.0f hp spire down" % [swings, hp])
		return
	if city.spire_kills != 1:
		_fail("FAIL the kill reported %d spire payouts, want exactly 1" % city.spire_kills)
		return
	var left := city.get_loadout().missing_recipe_ids().size()
	if left != missing - 1:
		_fail("FAIL the kill taught %d recipes, want exactly 1" % (missing - left))
		return
	print("kill: %d player swings broke the spire and always paid a recipe" % swings)


## Killing the tower closes the tap. It does not reach into the room and take back everything
## that already walked out of it — that is the difference between the spire and district unload.
func _check_station_keeps_its_summons() -> void:
	var station: Node3D = FactionPadSpawnerScript.new() as Node3D
	station.name = "TestStation"
	add_child(station)
	var owned := OwnedBody.new()
	owned.name = "OwnedBody"
	add_child(owned)
	_despawned = 0
	station.call(
		"setup",
		Vector3.ZERO,
		1234,
		Callable(),
		Callable(self, "_alive_units").bind(owned),
		Callable(self, "_despawn_unit"),
		"undead",
		"dungeon_summoner",
		&"test_station_owned",
		"TestStation"
	)
	station.call("tag_unit", owned)
	station.call("stop_spawning")
	if station.is_processing():
		_fail("FAIL the station kept summoning after its spire fell")
	if _despawned != 0:
		_fail("FAIL a dead spire despawned %d of its summons" % _despawned)
		return
	## Unload is the other path and still clears the room.
	station.call("shutdown")
	if _despawned != 1:
		_fail("FAIL district teardown left %d summons behind" % (1 - _despawned))
		return
	print("summons: %d body survives the spire and is only cleared on unload" % 1)


func _alive_units(owned: Node) -> Array:
	return [owned]


func _despawn_unit(_unit: Node) -> void:
	_despawned += 1


func _teardown(roster: MonsterRoster, terrain: VoxelTerrain, city: CityRoot) -> void:
	if roster != null and is_instance_valid(roster):
		roster.clear_all()
		roster.queue_free()
	if terrain != null and is_instance_valid(terrain):
		terrain.queue_free()
	NavService.reset()
	if city != null and is_instance_valid(city):
		city.free()


func _bake_tile(nav: NavService) -> NativeNavBake:
	var volume := CityVoxelNativeScript.make_volume() as NativeOfflineVoxelVolume
	volume.fill_box(Vector3i.ZERO, Vector3i(SX, 1, SZ), VoxelMaterial.CONCRETE)
	var tables := nav.solidity_tables()
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
		nav.link_params()
	)
	if not ok:
		_fail("FAIL bake_from_volume rejected the test tile")
		return null
	return bake
