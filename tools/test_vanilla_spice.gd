## Vanilla city spice: the apothecary, the killer on the poster, and the crows that watch both.
##
## Everything in this layer is optional content bolted onto tiles that used to be pure flavour,
## so the risks are all about it staying optional and staying findable:
##   - A lab the player cannot spot from the street is a trap. The tells (sick panes, a shingle)
##     and the lot they are painted on have to be the same lot the interior later calls the lab,
##     and both sides derive that from the seed rather than remembering it.
##   - The vat is the one furnishing the player is meant to shoot. If it stops being a whole
##     cluster of catalyst voxels, or stops being carveable, the infestation can never start.
##   - The payout must be tonics. Gems or recipes here would make the infestation the efficient
##     way to farm the district economy, which is the thing this layer is not allowed to do.
##   - Attacking an ordinary pedestrian must still fold them. Only the marked one fights back,
##     and only once — a promotion that fires twice is two killers off one poster.
##   - Crows are the tell for all of it. With nothing registered they must behave like the old
##     flock; with something registered they have to actually sit over it.
##
## Run: powershell -File tools\run_test.ps1 test_vanilla_spice
extends Node3D

const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const AlchemyLabSiteScript := preload("res://scripts/city/alchemy_lab_site.gd")
const WantedPosterScript := preload("res://scripts/city/wanted_poster.gd")
const WantedSuspectScript := preload("res://scripts/city/wanted_suspect.gd")
const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")
const RoomDecoratorScript := preload("res://scripts/city/room_decorator.gd")
const RoomVolumeScript := preload("res://scripts/city/room_volume.gd")
const InteriorRoomScript := preload("res://scripts/city/interior_room.gd")
const BuildingInteriorScript := preload("res://scripts/city/building_interior.gd")
const InteriorDecoratorScript := preload("res://scripts/city/interior_decorator.gd")
const CombatTableScript := preload("res://scripts/city/combat_table.gd")
const CreatureCatalogScript := preload("res://scripts/city/creature_catalog.gd")
const CrowdDirectorScript := preload("res://scripts/city/crowd_director.gd")
const MonsterRosterScript := preload("res://scripts/city/monster_roster.gd")
const BirdDirectorScript := preload("res://scripts/city/bird_director.gd")
const TreeStamperScript := preload("res://scripts/city/tree_stamper.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")

const VOX := 0.5
## The lot fixture: floor at GROUND, six courses of air over it, walls one voxel out.
const GROUND := 8
const AIR_H := 6
const LOT := Rect2i(8, 8, 10, 10)
## Ground-floor courses that carry glass, relative to GROUND.
const GLASS_LO := 2
const GLASS_HI := 3

## Nav fixture for the bodies the street promotes.
const NAV_ORIGIN := Vector3i.ZERO
const NAV_SIZE := 64
const NAV_Y_MAX := 47

## Seeds each roll is sampled over. Enough that a 28–34% chance cannot pass as 0% or 100%.
const ROLL_SAMPLES := 400

## Worlds baked in full for the poster siting check. A full bake is seconds each, so this is a
## handful of ordinary city tiles rather than a sweep.
##
## Always tile (0, 0): a bake brush addresses the district's *own* volume in local voxels while
## `interior_buildings` records world rects, and those two only coincide at the origin tile. In
## the game the live brush is world-space, so the placer reads exactly what it does here.
const WORLD_SEED := 42
const POSTER_SEEDS: Array[int] = [42, 7, 1234, 99, 2026]
const POSTER_COORD := Vector2i.ZERO
## Swings thrown at the promoted killer before the test calls it unkillable.
const KILL_SWINGS := 4000

const SIM_DT := 1.0 / 30.0
## How near a registered site a bird counts as sitting over it, for the crow bias check.
const WATCH_M := 8.0

var _failed := false


## CityRoot with its boot taken out: the lab paths need a terrain to place world points with
## and a brush to carve, and nothing else about a booted city.
class TestCity:
	extends CityRoot

	func _ready() -> void:
		add_to_group("city_root")

	func bind_world(terrain: VoxelTerrain, brush: CityBrush) -> void:
		_terrain = terrain
		_brush = brush

	func bind_roster(roster: MonsterRoster) -> void:
		_monsters = roster

	func infection() -> InfectionDirector:
		return _infection

	func lab_tendril_ids() -> Array:
		return _lab_tendrils.keys()

	func convert_ped(crowd: CrowdDirector, ped: PedAgent) -> void:
		_convert_ped_to_mad(crowd, ped)


## Stand-in for DistrictInstance, exposing only what InteriorDecorator reads off an entry.
class FakeDistrict:
	var is_ready: bool = true
	var bake_quality: String = "full"
	var coord: Vector2i = Vector2i(2, -3)
	var origin_vox: Vector3i = Vector3i.ZERO
	var interior_cell_size: int = 512
	var interior_buildings: Dictionary = {}
	var alchemy_lab_cell: Vector2i = AlchemyLabSite.NO_CELL


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	CombatTableScript.reload()
	_check_materials()
	_check_lab_siting()
	_check_exterior_tells()
	_check_catalyst_stamp()
	_check_interior_claims_the_lab()
	_check_ignition_pays_tonics()
	_check_hostile_rows()
	_check_wanted_poster()
	_check_suspect_identity()
	_check_poster_walls()
	await _check_wanted_ped_fights_back()
	_check_crow_scouts()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------


## The vat has to be shootable and the pane has to be see-through. Both are new ids in a table
## every voxel in the world is looked up in, so this is also the check that they were added
## rather than aliased onto something that already existed.
func _check_materials() -> void:
	if VoxelMaterial.ALCHEMY_CATALYST >= VoxelMaterial.COUNT:
		_fail("FAIL catalyst id %d is past the table's end" % VoxelMaterial.ALCHEMY_CATALYST)
		return
	if VoxelMaterial.LAB_WINDOW >= VoxelMaterial.COUNT:
		_fail("FAIL lab window id %d is past the table's end" % VoxelMaterial.LAB_WINDOW)
		return
	if VoxelMaterial.ALCHEMY_CATALYST == VoxelMaterial.LAB_WINDOW:
		_fail("FAIL the vat and the pane are the same id")
		return
	if not VoxelMaterial.is_alchemy_catalyst(VoxelMaterial.ALCHEMY_CATALYST):
		_fail("FAIL the catalyst does not recognise itself")
		return
	if VoxelMaterial.is_alchemy_catalyst(VoxelMaterial.STONE):
		_fail("FAIL plain stone reads as a catalyst")
		return
	## The whole loop starts with a player shot landing on this material.
	if not VoxelMaterial.is_destructible(VoxelMaterial.ALCHEMY_CATALYST):
		_fail("FAIL the vat cannot be shot, so no lab can ever be lit")
		return
	if VoxelMaterial.is_player_carve_immune(VoxelMaterial.ALCHEMY_CATALYST):
		_fail("FAIL the vat is carve-immune")
		return
	if not VoxelMaterial.is_solid(VoxelMaterial.ALCHEMY_CATALYST):
		_fail("FAIL the vat is not solid, so it cannot stand in a room")
		return
	## Both wear bespoke looks; a missing surface spec draws them as untextured grey.
	if VoxelSurfaceSpec.for_id(VoxelMaterial.ALCHEMY_CATALYST) == null:
		_fail("FAIL the vat has no surface spec")
		return
	if VoxelSurfaceSpec.for_id(VoxelMaterial.LAB_WINDOW) == null:
		_fail("FAIL the lab pane has no surface spec")
		return
	if not VoxelSurfaceSpec.has_bespoke_shader(VoxelMaterial.ALCHEMY_CATALYST):
		_fail("FAIL the vat draws with the ordinary block shader — it must glow")
		return
	print(
		"materials: vat %d is shootable rock with its own shader, pane %d is glass"
		% [VoxelMaterial.ALCHEMY_CATALYST, VoxelMaterial.LAB_WINDOW]
	)


# ---------------------------------------------------------------------------
# Where the lab is
# ---------------------------------------------------------------------------


## Stream time paints the outside and the JIT decorator dresses the inside, minutes apart and
## with nothing shared between them but the seed. If this roll is not a pure function, a tile
## gets a shopfront with an ordinary back room behind it.
func _check_lab_siting() -> void:
	var buildings := _fake_building_set(12)
	var theme := int(DistrictTheme.OLD_TOWN)
	var first := AlchemyLabSiteScript.lab_cell_for(4242, theme, buildings)
	if first != AlchemyLabSiteScript.lab_cell_for(4242, theme, buildings):
		_fail("FAIL the same tile answered its lab lot two different ways")
		return
	if AlchemyLabSiteScript.lab_cell_for(4242, theme, {}) != AlchemyLabSite.NO_CELL:
		_fail("FAIL a tile with no buildings still found a lab")
		return
	if AlchemyLabSiteScript.is_vanilla_theme(int(DistrictTheme.SIEGE)):
		_fail("FAIL a siege tile counts as vanilla")
		return
	var hits := 0
	for i in range(ROLL_SAMPLES):
		var cell: Vector2i = AlchemyLabSiteScript.lab_cell_for(i * 7919 + 3, theme, buildings)
		if cell == AlchemyLabSite.NO_CELL:
			continue
		hits += 1
		if not buildings.has(cell):
			_fail("FAIL the lab landed on cell %s, which has no building" % str(cell))
			return
	var rate := float(hits) / float(ROLL_SAMPLES)
	if absf(rate - AlchemyLabSite.LAB_CHANCE) > 0.08:
		_fail(
			"FAIL %.0f%% of vanilla tiles rolled a lab, wanted about %.0f%%"
			% [rate * 100.0, AlchemyLabSite.LAB_CHANCE * 100.0]
		)
		return
	## Special and siege tiles have their own content and must not grow apothecaries.
	for special_theme: int in [
		int(DistrictTheme.SIEGE), int(DistrictTheme.GRAVEYARD), int(DistrictTheme.CASTLE)
	]:
		for i in range(64):
			if (
				AlchemyLabSiteScript.lab_cell_for(i * 131 + 5, special_theme, buildings)
				!= AlchemyLabSite.NO_CELL
			):
				_fail("FAIL theme %d rolled a lab" % special_theme)
				return
	print(
		"siting: %d of %d vanilla tiles hide a lab, always on a real lot, never on special tiles"
		% [hits, ROLL_SAMPLES]
	)


## Lots the roll may pick from. Only the keys and the fact that each has a storey matter.
func _fake_building_set(n: int) -> Dictionary:
	var out: Dictionary = {}
	for i in range(n):
		var cell := Vector2i(i % 4, i / 4)
		var building: BuildingInterior = BuildingInteriorScript.make(
			Rect2i(cell.x * 20, cell.y * 20, 10, 10), FloorPlanner.Use.RESIDENTIAL
		) as BuildingInterior
		building.storeys.append(
			InteriorRoomScript.make(
				Rect2i(cell.x * 20, cell.y * 20, 10, 10),
				GROUND,
				AIR_H,
				RoomDecorator.Purpose.GENERIC
			) as InteriorRoom
		)
		out[cell] = building
	return out


# ---------------------------------------------------------------------------
# Street tells
# ---------------------------------------------------------------------------


## The player has to be able to walk past and think "something is wrong in there". Two tells:
## the ground-floor glass turns sick, and a shingle goes up over the door.
func _check_exterior_tells() -> void:
	var brush := _build_lot()
	var building := _lot_building()
	var door := _lot_door()
	var glass_before := _count_mat(brush, VoxelMaterial.GLASS)
	if glass_before == 0:
		_fail("FAIL the lot fixture has no window glass to sicken")
		return
	var site: AlchemyLabSite = AlchemyLabSiteScript.new() as AlchemyLabSite
	if not site.setup(brush, Vector2i.ZERO, building, [door]):
		_fail("FAIL a lot with glass and a door refused to become a lab")
		site.free()
		return
	if site.panes_painted <= 0:
		_fail("FAIL no pane turned sick")
		site.free()
		return
	if not site.has_sign():
		_fail("FAIL no shingle went up over the door")
		site.free()
		return
	if _count_mat(brush, VoxelMaterial.LAB_WINDOW) < site.panes_painted:
		_fail("FAIL the sick panes were reported but not painted")
		site.free()
		return
	## Only glass is swapped. A tell that punches new holes in a facade reads as damage.
	if _count_mat(brush, VoxelMaterial.GLASS) + site.panes_painted != glass_before:
		_fail("FAIL the pane swap changed the amount of glass on the building")
		site.free()
		return
	## The shingle stands on the wall over the opening, not in the opening.
	var sign_vox := site.sign_vox
	if sign_vox.y <= door.floor_y + door.height:
		_fail("FAIL the shingle at y=%d hangs inside the doorway" % sign_vox.y)
		site.free()
		return
	var sign_world := site.sign_world(VOX)
	if sign_world == Vector3.INF or not is_equal_approx(sign_world.y, (float(sign_vox.y) + 0.5) * VOX):
		_fail("FAIL the shingle has no world point for the crows to gather on")
		site.free()
		return
	## A blank lot has neither tell, so it must refuse rather than claim a lab nobody can find.
	var bare := _build_bare_lot()
	var bare_site: AlchemyLabSite = AlchemyLabSiteScript.new() as AlchemyLabSite
	if bare_site.setup(bare, Vector2i.ZERO, _lot_building(), []):
		_fail("FAIL a windowless lot with no door still claimed a lab")
	if bare_site.lab_cell != AlchemyLabSite.NO_CELL:
		_fail("FAIL a refused lot kept its lab cell")
	bare_site.free()
	site.free()
	print(
		"tells: %d sick panes and a shingle at %s, and nothing else about the facade moved"
		% [site.panes_painted, str(sign_vox)]
	)


# ---------------------------------------------------------------------------
# The vat
# ---------------------------------------------------------------------------


## The lab room stamps a vat; every other room stamps none. The vat is raw voxels rather than a
## prop because the carve path recognises the thing the player shoots by material id.
func _check_catalyst_stamp() -> void:
	var lab := _decorate_room(RoomDecorator.Purpose.ALCHEMY_LAB)
	var vox: Vector3i = lab["catalyst"]
	if vox == RoomDecorator.NO_CATALYST:
		_fail("FAIL an alchemy lab was furnished without a vat in it")
		return
	var brush: CityBrush = lab["brush"]
	if brush.get_vox(vox) != VoxelMaterial.ALCHEMY_CATALYST:
		_fail("FAIL the reported vat cell holds mat %d" % brush.get_vox(vox))
		return
	## One shot has to take the whole vat, so it has to be more than one cell.
	if brush.get_vox(vox + Vector3i.UP) != VoxelMaterial.ALCHEMY_CATALYST:
		_fail("FAIL the vat is a single voxel — a shot would leave a lit stump")
		return
	var stamped := _count_mat(brush, VoxelMaterial.ALCHEMY_CATALYST)
	if stamped != RoomDecorator.CATALYST_H:
		_fail("FAIL the room holds %d catalyst cells, wanted %d" % [stamped, RoomDecorator.CATALYST_H])
		return
	var plain := _decorate_room(RoomDecorator.Purpose.LIVING_ROOM)
	if plain["catalyst"] as Vector3i != RoomDecorator.NO_CATALYST:
		_fail("FAIL an ordinary living room stamped a vat")
		return
	if _count_mat(plain["brush"] as CityBrush, VoxelMaterial.ALCHEMY_CATALYST) != 0:
		_fail("FAIL an ordinary living room has catalyst in it")
		return
	print("vat: %d cells in the lab, none in an ordinary room" % stamped)


## Furnish one room of `purpose` in its own scratch volume.
func _decorate_room(purpose: RoomDecorator.Purpose) -> Dictionary:
	var brush: CityBrush = CityBrushScript.new() as CityBrush
	brush.use_offline_volume()
	var volume: RoomVolume = RoomVolumeScript.make(LOT, GROUND, AIR_H) as RoomVolume
	brush.fill_box(
		Vector3i(volume.rect.position.x - 1, volume.floor_y, volume.rect.position.y - 1),
		Vector3i(volume.rect.end.x + 1, volume.floor_y + volume.air_h + 2, volume.rect.end.y + 1),
		VoxelMaterial.STONE
	)
	brush.fill_box(volume.air_min(), volume.air_max(), VoxelMaterial.AIR)
	var dec: RoomDecorator = RoomDecoratorScript.new() as RoomDecorator
	dec.brush = brush
	dec.rng = RandomNumberGenerator.new()
	dec.rng.seed = 20260806
	dec.decorate(volume, purpose)
	return {"brush": brush, "catalyst": dec.last_catalyst_vox}


## The seam the whole slice hangs on: the district names a lot, and the decorator that walks in
## later turns a room of that lot — and of no other lot — into the lab.
func _check_interior_claims_the_lab() -> void:
	var with_lab := _furnish_storey(true)
	if not bool(with_lab["lab"]):
		_fail("FAIL the apothecary lot was furnished without a lab room")
		return
	if with_lab["catalyst"] as Vector3i == RoomDecorator.NO_CATALYST:
		_fail("FAIL the lab room was claimed but no vat was stamped in it")
		return
	if int(with_lab["labs"]) != 1:
		_fail("FAIL the lot claimed %d lab rooms, wanted exactly 1" % int(with_lab["labs"]))
		return
	var without := _furnish_storey(false)
	if bool(without["lab"]):
		_fail("FAIL an ordinary lot grew a lab room out of nothing")
		return
	if without["catalyst"] as Vector3i != RoomDecorator.NO_CATALYST:
		_fail("FAIL an ordinary lot stamped a vat")
		return
	print(
		"interior: the named lot claims 1 lab room and stamps its vat; an unnamed lot claims none"
	)


## Drive the JIT decorator over one storey until it stops furnishing rooms.
func _furnish_storey(is_lab: bool) -> Dictionary:
	var brush: CityBrush = CityBrushScript.new() as CityBrush
	brush.use_offline_volume()
	brush.fill_box(
		Vector3i(LOT.position.x - 1, GROUND, LOT.position.y - 1),
		Vector3i(LOT.end.x + 1, GROUND + AIR_H + 2, LOT.end.y + 1),
		VoxelMaterial.STONE
	)
	brush.fill_box(
		Vector3i(LOT.position.x, GROUND + 1, LOT.position.y),
		Vector3i(LOT.end.x, GROUND + AIR_H + 1, LOT.end.y),
		VoxelMaterial.AIR
	)
	var storey: InteriorRoom = InteriorRoomScript.make(
		LOT, GROUND, AIR_H, RoomDecorator.Purpose.GENERIC
	) as InteriorRoom
	storey.use = FloorPlanner.Use.RETAIL_OVER_FLATS
	var building: BuildingInterior = BuildingInteriorScript.make(
		LOT.grow(1), FloorPlanner.Use.RETAIL_OVER_FLATS
	) as BuildingInterior
	building.storeys.append(storey)
	var district := FakeDistrict.new()
	district.interior_buildings = {Vector2i.ZERO: building}
	if is_lab:
		district.alchemy_lab_cell = Vector2i.ZERO

	var dec: InteriorDecorator = InteriorDecoratorScript.new() as InteriorDecorator
	dec.brush = brush
	dec.voxel_size = VOX
	var foot := Vector3(
		float(LOT.position.x + 2) * VOX + 0.25,
		float(GROUND + 1) * VOX + 0.1,
		float(LOT.position.y + 2) * VOX + 0.25
	)
	var labs := 0
	var catalyst := RoomDecorator.NO_CATALYST
	for _step in range(200):
		if not dec.tick(foot, [district]):
			break
		var room := dec.take_furnished_room()
		if room.is_empty():
			continue
		if int(room["purpose"]) != int(RoomDecorator.Purpose.ALCHEMY_LAB):
			continue
		labs += 1
		catalyst = room["catalyst_vox"] as Vector3i
	return {"lab": labs > 0, "labs": labs, "catalyst": catalyst}


# ---------------------------------------------------------------------------
# Ignition and payout
# ---------------------------------------------------------------------------


## Shooting the vat is the opt-in. It takes the whole cluster, plants tips in the room's own
## fabric, and every tip killed afterwards pays tonics — not gems, and never a recipe.
func _check_ignition_pays_tonics() -> void:
	var brush: CityBrush = CityBrushScript.new() as CityBrush
	brush.use_offline_volume()
	## A stone room well above the street deck floor, so seeds are not clamped up out of it.
	brush.fill_box(
		Vector3i(LOT.position.x - 1, GROUND, LOT.position.y - 1),
		Vector3i(LOT.end.x + 1, GROUND + AIR_H + 2, LOT.end.y + 1),
		VoxelMaterial.BRICK
	)
	brush.fill_box(
		Vector3i(LOT.position.x, GROUND + 1, LOT.position.y),
		Vector3i(LOT.end.x, GROUND + AIR_H + 1, LOT.end.y),
		VoxelMaterial.AIR
	)
	var base := Vector3i(LOT.position.x + 4, GROUND + 1, LOT.position.y + 4)
	for i in range(RoomDecorator.CATALYST_H):
		brush.set_vox(base + Vector3i(0, i, 0), VoxelMaterial.ALCHEMY_CATALYST)

	var terrain := VoxelTerrain.new()
	terrain.name = "IgnitionField"
	add_child(terrain)
	terrain.scale = Vector3(VOX, VOX, VOX)
	var city: TestCity = TestCity.new()
	city.name = "IgnitionCity"
	add_child(city)
	city.set_process(false)
	city.set_physics_process(false)
	city.bind_world(terrain, brush)

	var planted := city.ignite_alchemy_catalyst(base)
	if planted <= 0:
		_fail("FAIL shooting the vat planted nothing")
		_drop(city, terrain)
		return
	if _count_mat(brush, VoxelMaterial.ALCHEMY_CATALYST) != 0:
		_fail("FAIL the shot left catalyst standing — a lit stump the player cannot finish")
		_drop(city, terrain)
		return
	var infection := city.infection()
	if infection == null:
		_fail("FAIL no infection director came up with the lab")
		_drop(city, terrain)
		return
	infection.set_physics_process(false)
	if city.lab_tendril_ids().size() != planted:
		_fail(
			"FAIL %d tips planted but %d are booked as the lab's"
			% [planted, city.lab_tendril_ids().size()]
		)
		_drop(city, terrain)
		return

	## A body standing in what grew is caught; one across the room is not.
	var lead_vox := _find_mat(brush, VoxelMaterial.INFECTION_LEAD)
	if lead_vox == Vector3i.MAX:
		_fail("FAIL the tips left no glowing head in the room")
		_drop(city, terrain)
		return
	var on_it := terrain.to_global(Vector3(lead_vox) + Vector3(0.5, 0.5, 0.5))
	if not infection.infection_touches_world(on_it):
		_fail("FAIL a body standing on a tip does not read as touching it")
		_drop(city, terrain)
		return
	if infection.infection_touches_world(on_it + Vector3(40.0, 0.0, 40.0)):
		_fail("FAIL a body 40 m away reads as touching the infection")
		_drop(city, terrain)
		return

	var inv := city.get_inventory()
	var before := (
		inv.count_of(InventoryCatalog.ID_BOOST_REGEN)
		+ inv.count_of(InventoryCatalog.ID_BOOST_SPEED)
	)
	var gems_before := _gem_count(inv)
	if not infection.try_kill_lead_at_vox(lead_vox):
		_fail("FAIL the glowing head at %s could not be killed" % str(lead_vox))
		_drop(city, terrain)
		return
	var after := (
		inv.count_of(InventoryCatalog.ID_BOOST_REGEN)
		+ inv.count_of(InventoryCatalog.ID_BOOST_SPEED)
	)
	var paid := after - before
	if paid < CityRoot.LAB_TONIC_MIN or paid > CityRoot.LAB_TONIC_MAX:
		_fail("FAIL killing a tip paid %d tonics, wanted %d–%d" % [
			paid, CityRoot.LAB_TONIC_MIN, CityRoot.LAB_TONIC_MAX
		])
		_drop(city, terrain)
		return
	if _gem_count(inv) != gems_before:
		_fail("FAIL the infestation paid gems, which is the district economy's job")
		_drop(city, terrain)
		return
	## Only lab tips pay. A meteor tip killed later must not draw on the same purse.
	var stray := infection.spawn_tendril_at_vox(base + Vector3i(2, 0, 2), -1, Vector3.ZERO, true)
	if stray >= 0:
		var before_stray := (
			inv.count_of(InventoryCatalog.ID_BOOST_REGEN)
			+ inv.count_of(InventoryCatalog.ID_BOOST_SPEED)
		)
		infection.try_kill_lead_at_vox(_find_tendril_lead(infection, stray))
		var after_stray := (
			inv.count_of(InventoryCatalog.ID_BOOST_REGEN)
			+ inv.count_of(InventoryCatalog.ID_BOOST_SPEED)
		)
		if after_stray != before_stray:
			_fail("FAIL a tip the lab did not plant paid %d tonics" % (after_stray - before_stray))
			_drop(city, terrain)
			return
	print("ignition: the vat spilled %d tips and one killed tip paid %d tonics, no gems" % [
		planted, paid
	])
	_drop(city, terrain)


func _find_tendril_lead(infection: InfectionDirector, tid: int) -> Vector3i:
	var world: Vector3 = infection.tendril_lead_world(tid)
	if world == Vector3.INF:
		return Vector3i.MAX
	return Vector3i(
		int(floor(world.x / VOX)), int(floor(world.y / VOX)), int(floor(world.z / VOX))
	)


func _gem_count(inv: PlayerInventory) -> int:
	var n := 0
	for id: String in [
		InventoryCatalog.ID_QUARTZ,
		InventoryCatalog.ID_AMBER,
		InventoryCatalog.ID_TOPAZ,
		InventoryCatalog.ID_SAPPHIRE,
		InventoryCatalog.ID_EMERALD,
		InventoryCatalog.ID_DIAMOND,
	]:
		n += inv.count_of(id)
	return n


# ---------------------------------------------------------------------------
# The bodies the street promotes
# ---------------------------------------------------------------------------


## Both hostiles exist as authored rows and neither may ever be rolled by an ordinary spawner:
## a mad citizen in a graveyard, or a wanted killer summoned by a spire, would be a body with
## no story attached to it.
func _check_hostile_rows() -> void:
	for id: String in [CityRoot.MAD_CITIZEN_BODY_ID, CityRoot.WANTED_KILLER_BODY_ID]:
		if CreatureCatalogScript.by_id(id) == null:
			_fail("FAIL no creature '%s'" % id)
			return
		if not CombatTableScript.has_monster(id):
			_fail("FAIL no combat row '%s'" % id)
			return
		if CombatTableScript.spawnable_ids().has(id):
			_fail("FAIL '%s' is spawn_ready, so random spawners can roll it" % id)
			return
	var mad := CombatTableScript.resolve(CityRoot.MAD_CITIZEN_BODY_ID)
	var killer := CombatTableScript.resolve(CityRoot.WANTED_KILLER_BODY_ID)
	if mad == null or killer == null:
		_fail("FAIL a city hostile does not resolve")
		return
	## The mad citizen is pressure, not a fight: melee only and weaker than the poster's face.
	if mad.attacks.size() != 1 or mad.attacks[0] != "melee":
		_fail("FAIL the mad citizen's kit is %s, wanted melee only" % str(mad.attacks))
		return
	if killer.attacks.size() < 2 or not killer.attacks.has("melee"):
		_fail("FAIL the wanted killer's kit is %s, wanted melee plus something nasty" % str(killer.attacks))
		return
	if killer.hp_mult <= mad.hp_mult or killer.damage_mult <= mad.damage_mult:
		_fail("FAIL the wanted killer is not tougher than a mad citizen")
		return
	## A pedestrian who folds to one shot is the baseline; the killer has to outlast that.
	if killer.hp_mult <= 1.0:
		_fail("FAIL the wanted killer is at or under baseline hp (%.2f)" % killer.hp_mult)
		return
	for id: String in [CityRoot.MAD_CITIZEN_BODY_ID, CityRoot.WANTED_KILLER_BODY_ID]:
		if CombatTableScript.faction_for(id) != "horde":
			_fail("FAIL '%s' is faction '%s', so it may not fight the player" % [
				id, CombatTableScript.faction_for(id)
			])
			return
	print("hostiles: mad citizen %s vs wanted killer %s, neither spawn_ready" % [
		str(mad.attacks), str(killer.attacks)
	])


# ---------------------------------------------------------------------------
# The poster
# ---------------------------------------------------------------------------


## The roll only. Geometry is checked against real districts in `_check_poster_walls`.
func _check_wanted_poster() -> void:
	var pasted := 0
	for i in range(ROLL_SAMPLES):
		if WantedPosterScript.posts_bills(i * 7919 + 3, int(DistrictTheme.OLD_TOWN)):
			pasted += 1
	var rate := float(pasted) / float(ROLL_SAMPLES)
	if absf(rate - WantedPoster.WANTED_CHANCE) > 0.08:
		_fail("FAIL %.0f%% of tiles post a bill, wanted about %.0f%%" % [
			rate * 100.0, WantedPoster.WANTED_CHANCE * 100.0
		])
		return
	## Special tiles keep their own content.
	for i in range(ROLL_SAMPLES):
		if WantedPosterScript.posts_bills(i, int(DistrictTheme.GRAVEYARD)):
			_fail("FAIL a special district posted a wanted bill")
			return
	print("poster: %d of %d vanilla tiles post bills, no special tile does" % [
		pasted, ROLL_SAMPLES
	])


## Siting, against districts baked exactly the way the game bakes them.
##
## Every rule here is one the fixtures cannot check, because they are all about what real
## facades look like: the bill has to land on a wall that is actually there (the storey rect
## grown by one, which is where the shell stands), it has to face an avenue, it must not hang
## over a doorway or a setback, and two bills must not end up on the same corner. A tile that
## offers no such wall simply posts nothing, so the check that matters most is that the city
## as a whole still finds walls — a silent zero here is the failure mode this catches.
func _check_poster_walls() -> void:
	var tiles := 0
	var with_walls := 0
	var total_sites := 0
	var sample_brush: CityBrush = null
	var sample_site: WantedPoster.Site = null
	for world_seed: int in POSTER_SEEDS:
		var coord := POSTER_COORD
		var theme := DistrictTheme.for_district(world_seed, coord)
		if not AlchemyLabSite.is_vanilla_theme(theme.id):
			continue
		var payload: Dictionary = DistrictBakeJobScript.bake({
			"coord": coord,
			"world_seed": world_seed,
			"quality": DistrictBakeJobScript.QUALITY_FULL,
			"bake_nav": false,
		})
		if not bool(payload.get("ok", false)):
			_fail("FAIL bake seed %d: %s" % [world_seed, payload.get("error", "?")])
			return
		tiles += 1
		var gen: DistrictGenerator = payload["generator"]
		var planner: DistrictPlanner = payload["planner"]
		var brush: CityBrush = gen._brush
		var buildings: Dictionary = payload["interior_buildings"]
		var sites: Array = WantedPosterScript.sites_on_tile(
			int(payload["seed"]), buildings, planner, brush, VOX
		)
		var label := "world %d (%s)" % [world_seed, theme.display_name]
		if sites.size() > WantedPoster.MAX_PER_TILE:
			_fail("FAIL %s offered %d bills, capped at %d" % [
				label, sites.size(), WantedPoster.MAX_PER_TILE
			])
			return
		if not sites.is_empty():
			with_walls += 1
		total_sites += sites.size()
		for item: Variant in sites:
			var site: WantedPoster.Site = item as WantedPoster.Site
			if not _site_is_sound(label, site, planner, brush, payload["origin_vox"]):
				return
			if sample_site == null:
				sample_site = site
				sample_brush = brush
		if not _sites_are_spread(label, sites):
			return
	if tiles == 0:
		_fail("FAIL none of the sampled worlds is a vanilla theme — this check went stale")
		return
	## Ordinary city tiles are what this layer lives on. One that cannot carry a single bill
	## means the siting rules have drifted away from the buildings the generator makes.
	if with_walls < tiles:
		_fail(
			"FAIL only %d of %d ordinary tiles offered a wall to paste a bill on" % [
				with_walls, tiles
			]
		)
		return
	if sample_site == null:
		return
	_check_boarding(sample_brush, sample_site)
	print("poster walls: %d of %d ordinary tiles carry bills, %d sites in all" % [
		with_walls, tiles, total_sites
	])


## Solid all the way across, facing an avenue, and standing on the lot it says it does.
func _site_is_sound(
	label: String,
	site: WantedPoster.Site,
	planner: DistrictPlanner,
	brush: CityBrush,
	origin_vox: Vector3i
) -> bool:
	var want := Vector2i(
		int(ceil(WantedPoster.SHEET_M.x / VOX)), int(ceil(WantedPoster.SHEET_M.y / VOX))
	)
	if site.span != want:
		_fail("FAIL %s sited a %s bill, wanted %s" % [label, str(site.span), str(want)])
		return false
	var panes := 0
	for t in range(site.span.x):
		for row in range(site.span.y):
			var v: Vector3i = site.origin_vox + site.run * t + Vector3i(0, row, 0)
			var id := brush.get_vox(v)
			if id == VoxelMaterial.AIR:
				_fail("FAIL %s pasted a bill over open air at %s" % [label, str(v)])
				return false
			if id == VoxelMaterial.GLASS or id == VoxelMaterial.GLASS_LIT:
				panes += 1
	if float(panes) > float(site.span.x * site.span.y) * (1.0 - WantedPoster.MIN_OPAQUE_SHARE):
		_fail("FAIL %s pasted a bill over a shopfront (%d panes)" % [label, panes])
		return false
	## The cell the paper looks at has to be one of the world's wide streets.
	var mid := site.middle_vox()
	var outside := Vector2i(
		mid.x + site.out_dir.x * 2 - origin_vox.x, mid.z + site.out_dir.z * 2 - origin_vox.z
	)
	var cell := Vector2i(
		int(floor(float(outside.x) / float(DistrictCoord.CELL_SIZE))),
		int(floor(float(outside.y) / float(DistrictCoord.CELL_SIZE)))
	)
	if not _avenue_within(planner, cell, 2):
		_fail("FAIL %s hung a bill on a back wall (cell %s)" % [label, str(cell)])
		return false
	return true


static func _avenue_within(planner: DistrictPlanner, cell: Vector2i, reach: int) -> bool:
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if planner.tag_at(cell.x + dx, cell.y + dz) == LandUse.AVENUE:
				return true
	return false


func _sites_are_spread(label: String, sites: Array) -> bool:
	for i in range(sites.size()):
		for j in range(i + 1, sites.size()):
			var a: WantedPoster.Site = sites[i] as WantedPoster.Site
			var b: WantedPoster.Site = sites[j] as WantedPoster.Site
			var am := a.middle_vox()
			var bm := b.middle_vox()
			var metres := Vector2(am.x - bm.x, am.z - bm.z).length() * VOX
			if metres < WantedPoster.MIN_SPACING_M - 0.01:
				_fail("FAIL %s hung two bills %.1f m apart" % [label, metres])
				return false
	return true


## Pasting boards the glass behind the paper with the wall's own masonry, and puts a sheet of
## the right size on the outer face of that wall, facing the street.
func _check_boarding(brush: CityBrush, site: WantedPoster.Site) -> void:
	var poster: WantedPoster = WantedPosterScript.new() as WantedPoster
	add_child(poster)
	if not poster.setup(brush, site, VOX, null):
		_fail("FAIL pasting a sound site failed")
		poster.queue_free()
		return
	for t in range(site.span.x):
		for row in range(site.span.y):
			var v: Vector3i = site.origin_vox + site.run * t + Vector3i(0, row, 0)
			var id := brush.get_vox(v)
			if id == VoxelMaterial.GLASS or id == VoxelMaterial.GLASS_LIT:
				_fail("FAIL a pane survived behind the paper at %s" % str(v))
				poster.queue_free()
				return
			if id == VoxelMaterial.AIR:
				_fail("FAIL boarding punched a hole in the wall at %s" % str(v))
				poster.queue_free()
				return
	var sheet := poster.get_node_or_null("Sheet") as MeshInstance3D
	if sheet == null:
		_fail("FAIL the bill has no paper on it")
		poster.queue_free()
		return
	var quad := sheet.mesh as QuadMesh
	if quad == null or absf(quad.size.x - WantedPoster.SHEET_M.x) > 0.01 or absf(
		quad.size.y - WantedPoster.SHEET_M.y
	) > 0.01:
		_fail("FAIL the sheet is %s metres, wanted %s" % [
			str(quad.size if quad != null else Vector2.ZERO), str(WantedPoster.SHEET_M)
		])
		poster.queue_free()
		return
	## Local +Z is the readable face; it has to point away from the wall.
	var face := poster.global_transform.basis.z
	var want_face := Vector3(site.out_dir)
	if face.dot(want_face) < 0.99:
		_fail("FAIL the bill reads into the building (%s vs %s)" % [str(face), str(want_face)])
		poster.queue_free()
		return
	## And it has to stand proud of the masonry rather than inside it.
	var wall_face := (
		float(site.origin_vox.x if site.out_dir.x != 0 else site.origin_vox.z)
		+ (1.0 if (site.out_dir.x + site.out_dir.z) > 0 else 0.0)
	) * VOX
	var sheet_at := (
		poster.global_position.x if site.out_dir.x != 0 else poster.global_position.z
	)
	var proud := (sheet_at - wall_face) * float(site.out_dir.x + site.out_dir.z)
	if absf(proud - WantedPoster.STANDOFF_M) > 0.001:
		_fail("FAIL the sheet sits %.3f m off the wall, wanted %.3f" % [
			proud, WantedPoster.STANDOFF_M
		])
		poster.queue_free()
		return
	if poster.get_node_or_null("Line_WANTED") == null:
		_fail("FAIL the bill carries no headline")
	poster.queue_free()


## The mugshot pipeline, as far as a machine with no renderer can take it: the world has one
## suspect, it is the same one on every tile, and the body it names can actually be framed.
func _check_suspect_identity() -> void:
	WantedSuspectScript.forget()
	var first := WantedSuspectScript.identity(WORLD_SEED)
	if first == null:
		_fail("FAIL the world has no wanted suspect to print on its bills")
		return
	if first.faction != PedOutfit.Faction.HOSTILE:
		_fail("FAIL the suspect is dressed like a commuter (faction %d)" % int(first.faction))
		return
	if WantedSuspectScript.identity(WORLD_SEED) != first:
		_fail("FAIL two tiles of one world would print two different faces")
		return
	if not ResourceLoader.exists(first.scene_path):
		_fail("FAIL the suspect's body %s is not on disk" % first.scene_path)
		return
	## The mugshot is framed off the rig's head bone, so a body without one bakes nothing.
	var packed := load(first.scene_path) as PackedScene
	if packed == null:
		_fail("FAIL the suspect's body %s will not load" % first.scene_path)
		return
	var root := packed.instantiate() as Node3D
	add_child(root)
	var skel := _find_skeleton(root)
	if skel == null:
		_fail("FAIL the suspect's body has no skeleton to frame a mugshot from")
		root.queue_free()
		return
	if skel.find_bone(WantedSuspect.HEAD_BONE) < 0:
		_fail("FAIL the suspect's rig has no '%s' bone" % WantedSuspect.HEAD_BONE)
		root.queue_free()
		return
	root.queue_free()
	if WantedSuspectScript.portrait() != null:
		_fail("FAIL a headless session baked a mugshot it cannot have rendered")
		return
	print("suspect: one killer per world (%s), rig framed on '%s'" % [
		first.variant_id, WantedSuspect.HEAD_BONE
	])


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


## The hunt end to end: the crowd marks the ped nearest the bill, an ordinary ped still folds
## to one hit, and the marked one turns into the body the poster warned about — once.
func _check_wanted_ped_fights_back() -> void:
	var nav := NavService.instance()
	nav.ensure_configured(VOX)
	var bake := _bake_ground(nav)
	if bake == null:
		return
	if not nav.register_district(Vector2i(-407, -407), bake):
		_fail("FAIL NavService refused the test tile")
		return
	var terrain := VoxelTerrain.new()
	terrain.name = "HuntField"
	add_child(terrain)
	terrain.scale = Vector3(VOX, VOX, VOX)
	var city: TestCity = TestCity.new()
	city.name = "HuntCity"
	add_child(city)
	city.set_process(false)
	city.set_physics_process(false)
	city.bind_world(terrain, null)
	var roster: MonsterRoster = MonsterRosterScript.new() as MonsterRoster
	roster.name = "MonsterRoster"
	add_child(roster)
	roster.setup(city, terrain, NavLod.for_collision_view(48, VOX))
	city.bind_roster(roster)

	var crowd: CrowdDirector = CrowdDirectorScript.new() as CrowdDirector
	crowd.name = "TestCrowd"
	add_child(crowd)
	## The hunt is about who the crowd marks, not about walking anyone anywhere.
	crowd.set_physics_process(false)
	var peds := _seed_crowd(crowd)
	await get_tree().process_frame

	if crowd.wanted_agent() != null:
		_fail("FAIL a crowd with no bill on the wall already has a killer in it")
		_drop_hunt(crowd, roster, terrain, city)
		return
	var bill := peds[0].global_position + Vector3(1.0, 0.0, 1.0)
	var suspect := WantedSuspectScript.identity(WORLD_SEED)
	var marked := crowd.mark_wanted(bill, suspect)
	if marked == null:
		_fail("FAIL the bill marked nobody")
		_drop_hunt(crowd, roster, terrain, city)
		return
	if marked != peds[0]:
		_fail("FAIL the bill marked a ped further from it than the nearest one")
		_drop_hunt(crowd, roster, terrain, city)
		return
	if marked.outfit == null or marked.outfit.faction != PedOutfit.Faction.HOSTILE:
		_fail("FAIL the killer is dressed like a commuter, so the hunt needs the poster")
		_drop_hunt(crowd, roster, terrain, city)
		return
	## The face on the wall is the face in the street: same outfit, same sex, or the poster
	## is describing somebody else.
	if marked.outfit != suspect or marked.female != suspect.female:
		_fail("FAIL the marked ped is not the suspect the bills were printed from")
		_drop_hunt(crowd, roster, terrain, city)
		return
	## Everyone else on the street is still a commuter. The hit path reads this flag to decide
	## between folding a ped and starting a fight, so a crowd where more than one ped answers
	## yes is a crowd that spawns killers out of bystanders.
	for other: PedAgent in peds.slice(1):
		if crowd.is_wanted(other):
			_fail("FAIL a second ped reads as wanted")
			_drop_hunt(crowd, roster, terrain, city)
			return
	if roster.count_alive_walkers() != 0:
		_fail("FAIL marking a ped already put a monster on the street")
		_drop_hunt(crowd, roster, terrain, city)
		return

	if not city.promote_wanted_ped(crowd, marked):
		_fail("FAIL the marked ped folded instead of fighting back")
		_drop_hunt(crowd, roster, terrain, city)
		return
	if roster.count_alive_walkers() != 1:
		_fail("FAIL promotion left %d bodies on the street" % roster.count_alive_walkers())
		_drop_hunt(crowd, roster, terrain, city)
		return
	## One poster, one killer: the promoted ped is gone from the crowd and cannot be promoted
	## a second time by the next shot that lands on the same body.
	if crowd.is_wanted(marked) or crowd.wanted_agent() != null:
		_fail("FAIL the crowd still holds a killer after promoting them")
		_drop_hunt(crowd, roster, terrain, city)
		return
	if city.promote_wanted_ped(crowd, marked):
		_fail("FAIL the same ped was promoted twice")
		_drop_hunt(crowd, roster, terrain, city)
		return

	var killer := _first_alive(roster)
	if killer == null:
		_fail("FAIL the promoted killer is not alive")
		_drop_hunt(crowd, roster, terrain, city)
		return
	killer.set_physics_process(false)
	var inv := city.get_inventory()
	var before := (
		inv.count_of(InventoryCatalog.ID_BOOST_REGEN)
		+ inv.count_of(InventoryCatalog.ID_BOOST_SPEED)
	)
	var swings := 0
	while killer.is_alive() and swings < KILL_SWINGS:
		killer.apply_damage_scaled(DamageSource.Id.PLAYER_MELEE, 1.0, "player", null)
		swings += 1
	if killer.is_alive():
		_fail("FAIL %d swings did not bring the killer down" % swings)
		_drop_hunt(crowd, roster, terrain, city)
		return
	var paid := (
		inv.count_of(InventoryCatalog.ID_BOOST_REGEN)
		+ inv.count_of(InventoryCatalog.ID_BOOST_SPEED)
	) - before
	if paid != 1:
		_fail("FAIL winning the hunt paid %d tonics, wanted 1" % paid)
		_drop_hunt(crowd, roster, terrain, city)
		return
	print("hunt: the bill marks one ped, promotes them once, and the killer pays 1 tonic")
	_drop_hunt(crowd, roster, terrain, city)


## A handful of peds standing on the baked deck. Enough to tell "nearest" from "any".
func _seed_crowd(crowd: CrowdDirector) -> Array[PedAgent]:
	var out: Array[PedAgent] = []
	for i in range(5):
		var ped := PedAgent.new()
		ped.name = "Ped_%d" % i
		crowd.add_child(ped)
		ped.global_position = Vector3(8.0 + float(i) * 4.0, 1.0, 8.0)
		ped.last_pos = ped.global_position
		## Straight into the roll the director keeps. Spawning peds for real needs a streamed
		## tile and a goal provider, and none of that is what the hunt is about.
		crowd._agents.append(ped)
		out.append(ped)
	return out


func _first_alive(roster: MonsterRoster) -> UndeadUnit:
	for unit: UndeadUnit in roster.get_alive_units():
		if is_instance_valid(unit) and unit.is_alive():
			return unit
	return null


func _bake_ground(nav: NavService) -> NativeNavBake:
	var volume := CityVoxelNativeScript.make_volume() as NativeOfflineVoxelVolume
	volume.fill_box(Vector3i.ZERO, Vector3i(NAV_SIZE, 1, NAV_SIZE), VoxelMaterial.CONCRETE)
	var tables := nav.solidity_tables()
	var bake := CityVoxelNativeScript.make_nav_bake() as NativeNavBake
	var ok: bool = bake.bake_from_volume(
		volume,
		NAV_ORIGIN,
		NAV_SIZE,
		NAV_SIZE,
		0,
		NAV_Y_MAX,
		tables["class"],
		tables["top"],
		tables["destructible"],
		tables["climbable"],
		nav.link_params()
	)
	if not ok:
		_fail("FAIL bake_from_volume rejected the hunt fixture")
		return null
	return bake


# ---------------------------------------------------------------------------
# Crows
# ---------------------------------------------------------------------------


## Crows are the layer's only free advertising: a knot of black birds over a roof is how a
## player who never enters a building learns the street has something on it. With nothing
## registered they must be the old ambient flock.
func _check_crow_scouts() -> void:
	var brush := _build_grove()
	var cam := Camera3D.new()
	add_child(cam)
	var flock: BirdDirector = BirdDirectorScript.new() as BirdDirector
	flock.name = "SpiceBirds"
	add_child(flock)
	flock.render_distance = 1000.0
	flock.setup(brush, null, Vector3i.ZERO, Vector2i(96, 96), 6, 28, VOX, cam, 4242)
	if flock.bird_live_count() == 0:
		_fail("FAIL the crow fixture has no birds in it")
		return
	if flock.crow_count() != 0 or flock.attractor_count() != 0:
		_fail("FAIL a tile with nothing to watch already has crows on it")
		return
	for _step in range(300):
		flock.simulate(SIM_DT)
	if flock.birds_watching_attractors() != 0:
		_fail("FAIL birds are watching attractors that do not exist")
		return

	## Something worth watching, in one corner of the tile.
	var mark := Vector3(12.0, float(7) * VOX, 12.0)
	flock.add_attractor(mark)
	if flock.attractor_count() != 1:
		_fail("FAIL the attractor was not registered")
		return
	if flock.crow_count() == 0:
		_fail("FAIL nothing in the flock turned black over a registered site")
		return
	if flock.crow_count() >= flock.bird_live_count():
		_fail("FAIL the whole flock turned into crows")
		return
	## Ignoring a second registration would leave the lab watched and the poster bare.
	var second := mark + Vector3(24.0, 0.0, 24.0)
	flock.add_attractor(second)
	if flock.attractor_count() != 2:
		_fail("FAIL a second site was not registered")
		return
	var marks: Array[Vector3] = [mark, second]
	var want := int(ceil(float(flock.crow_count()) * 0.5))
	var watched := 0
	for _step in range(120 * 30):
		flock.simulate(SIM_DT)
		watched = _watching(flock, marks, true)
		if watched >= want:
			break
	if watched < want:
		_fail(
			"FAIL only %d of %d crows sat over a registered site within 120 s"
			% [watched, flock.crow_count()]
		)
		return
	var others := flock.bird_live_count() - flock.crow_count()
	var crow_share := float(watched) / float(maxi(flock.crow_count(), 1))
	var other_share := float(_watching(flock, marks, false)) / float(maxi(others, 1))
	if crow_share <= other_share:
		_fail(
			"FAIL %.0f%% of crows and %.0f%% of ordinary birds sit over the sites — no bias"
			% [crow_share * 100.0, other_share * 100.0]
		)
		return
	print("crows: %d of %d birds turned black, %.0f%% of them over a site vs %.0f%% of the rest" % [
		flock.crow_count(), flock.bird_live_count(), crow_share * 100.0, other_share * 100.0
	])
	flock.clear_birds()
	if flock.attractor_count() != 0 or flock.crow_count() != 0:
		_fail("FAIL teardown left crows and attractors behind")


## Birds of one kind sitting on top of a registered site. Tighter than the director's own
## watch radius, which is wide enough that a bird anywhere on a small tile would qualify.
func _watching(flock: BirdDirector, marks: Array[Vector3], crows: bool) -> int:
	var n := 0
	for bird: BirdActor in flock._birds:
		if flock.is_crow(bird) != crows:
			continue
		for at: Vector3 in marks:
			if bird.global_position.distance_to(at) <= WATCH_M:
				n += 1
				break
	return n


func _build_grove() -> CityBrush:
	var brush: CityBrush = CityBrushScript.new() as CityBrush
	brush.use_offline_volume()
	brush.fill_box(Vector3i(0, 6, 0), Vector3i(96, 7, 96), VoxelMaterial.SIDEWALK)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260806
	var stamper: TreeStamper = TreeStamperScript.new() as TreeStamper
	stamper.brush = brush
	stamper.rng = rng
	stamper.allow_canopy_gems = false
	for z in range(8, 88, 14):
		for x in range(8, 88, 14):
			stamper.round_tree(x, 6, z)
	return brush


# ---------------------------------------------------------------------------
# Fixtures and helpers
# ---------------------------------------------------------------------------


## A single lot with a glazed ground floor and one street door punched through its +Z wall.
func _build_lot() -> CityBrush:
	var brush: CityBrush = CityBrushScript.new() as CityBrush
	brush.use_offline_volume()
	var ring := LOT.grow(1)
	brush.fill_box(
		Vector3i(ring.position.x, GROUND, ring.position.y),
		Vector3i(ring.end.x, GROUND + AIR_H + 2, ring.end.y),
		VoxelMaterial.BRICK
	)
	brush.fill_box(
		Vector3i(LOT.position.x, GROUND + 1, LOT.position.y),
		Vector3i(LOT.end.x, GROUND + AIR_H + 1, LOT.end.y),
		VoxelMaterial.AIR
	)
	for y in [GROUND + GLASS_LO, GROUND + GLASS_HI]:
		for x in range(ring.position.x, ring.end.x):
			for z in range(ring.position.y, ring.end.y):
				if not _on_ring(ring, x, z):
					continue
				brush.set_vox(Vector3i(x, y, z), VoxelMaterial.GLASS)
	var door := _lot_door()
	for column: Vector2i in door.columns():
		for row in range(door.height):
			brush.set_vox(Vector3i(column.x, door.floor_y + row, column.y), VoxelMaterial.AIR)
	return brush


## The same lot with blank walls and no door: nothing to hang a tell on.
func _build_bare_lot() -> CityBrush:
	var brush: CityBrush = CityBrushScript.new() as CityBrush
	brush.use_offline_volume()
	var ring := LOT.grow(1)
	brush.fill_box(
		Vector3i(ring.position.x, GROUND, ring.position.y),
		Vector3i(ring.end.x, GROUND + AIR_H + 2, ring.end.y),
		VoxelMaterial.BRICK
	)
	brush.fill_box(
		Vector3i(LOT.position.x, GROUND + 1, LOT.position.y),
		Vector3i(LOT.end.x, GROUND + AIR_H + 1, LOT.end.y),
		VoxelMaterial.AIR
	)
	return brush


func _on_ring(ring: Rect2i, x: int, z: int) -> bool:
	return (
		x == ring.position.x or x == ring.end.x - 1
		or z == ring.position.y or z == ring.end.y - 1
	)


func _lot_building() -> BuildingInterior:
	var building: BuildingInterior = BuildingInteriorScript.make(
		LOT, FloorPlanner.Use.RETAIL_OVER_FLATS
	) as BuildingInterior
	building.storeys.append(
		InteriorRoomScript.make(
			LOT, GROUND, AIR_H, RoomDecorator.Purpose.GENERIC
		) as InteriorRoom
	)
	return building


func _lot_door() -> CastleDoorway:
	var door := CastleDoorway.new()
	door.center = Vector2i(LOT.position.x + LOT.size.x / 2, LOT.end.y)
	door.axis = Vector2i(0, 1)
	door.width = 3
	door.depth = 1
	door.storey = 0
	door.floor_y = GROUND + 1
	door.height = 4
	door.arch_courses = 0
	return door


func _count_mat(brush: CityBrush, mat: int) -> int:
	var n := 0
	var ring := LOT.grow(2)
	for y in range(GROUND - 1, GROUND + AIR_H + 4):
		for x in range(ring.position.x, ring.end.x):
			for z in range(ring.position.y, ring.end.y):
				if brush.get_vox(Vector3i(x, y, z)) == mat:
					n += 1
	return n


func _find_mat(brush: CityBrush, mat: int) -> Vector3i:
	var ring := LOT.grow(2)
	for y in range(GROUND - 1, GROUND + AIR_H + 4):
		for x in range(ring.position.x, ring.end.x):
			for z in range(ring.position.y, ring.end.y):
				var v := Vector3i(x, y, z)
				if brush.get_vox(v) == mat:
					return v
	return Vector3i.MAX


func _drop(city: TestCity, terrain: VoxelTerrain) -> void:
	if is_instance_valid(city):
		city.queue_free()
	if is_instance_valid(terrain):
		terrain.queue_free()


func _drop_hunt(
	crowd: CrowdDirector, roster: MonsterRoster, terrain: VoxelTerrain, city: TestCity
) -> void:
	if is_instance_valid(roster):
		roster.clear_all()
		roster.queue_free()
	if is_instance_valid(crowd):
		crowd.queue_free()
	NavService.reset()
	_drop(city, terrain)
