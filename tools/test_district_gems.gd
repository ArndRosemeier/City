## Stage 1 economy: what a district owes in gems, what it pays out, and what the save remembers.
##
## The whole point of a budget is that walking away and coming back is not a way to farm. Nothing
## about a district's voxels is saved, so the tile is re-baked from the seed with all its ore
## painted back in — and the only thing standing between that and infinite gems is this ledger.
## So the cases that matter are the ones about *repeats*: a second visit must not re-roll the
## budget, an emptied type must stay empty, and exploring a tile twice must pay once.
##
## Run: powershell -File tools\run_test.ps1 test_district_gems
extends Node

const DistrictEconomyScript := preload("res://scripts/city/district_economy.gd")
const GameSaveScript := preload("res://scripts/city/game_save.gd")
const GemChestScript := preload("res://scripts/city/gem_chest.gd")
const GemChestPlacerScript := preload("res://scripts/city/gem_chest_placer.gd")
const CityWalkerScript := preload("res://scripts/city/city_walker.gd")
const PlayerInventoryScript := preload("res://scripts/city/player_inventory.gd")
const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const InteriorRoomScript := preload("res://scripts/city/interior_room.gd")
const BuildingInteriorScript := preload("res://scripts/city/building_interior.gd")
const InteriorDecoratorScript := preload("res://scripts/city/interior_decorator.gd")
const RoomVolumeScript := preload("res://scripts/city/room_volume.gd")
const DistrictInstanceScript := preload("res://scripts/city/district_instance.gd")

const SCRATCH_DIR := "user://test_district_gems"
const WORLD_SEED := 9091
const COORD := Vector2i(3, -2)
const OTHER_COORD := Vector2i(-7, 11)

var _failed := false


## CityRoot with its boot removed: the group is what `GemChest` looks itself up by, and the
## economy and inventory it grants through are plain members that exist without a world.
class TestCity:
	extends CityRoot

	func _ready() -> void:
		add_to_group("city_root")

	## An offline volume instead of the streamed world, so the room-to-chest handoff can be
	## driven without booting a city.
	func bind_test_brush(brush: CityBrush) -> void:
		_brush = brush

	func pick_chest_spot(room: Dictionary) -> Vector3i:
		return _chest_spot_in_room(room)


## Stand-in for DistrictInstance, exposing only what InteriorDecorator reads.
class FakeDistrict:
	var is_ready: bool = true
	var bake_quality: String = "full"
	var coord: Vector2i = COORD
	var origin_vox: Vector3i = Vector3i.ZERO
	var interior_cell_size: int = 512
	var interior_buildings: Dictionary = {}


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	GameSaveScript.use_directory(SCRATCH_DIR)
	_wipe_scratch()
	_check_roll_is_deterministic()
	_check_hill_budget_is_its_own_ore()
	_check_take_depletes_and_then_refuses()
	_check_revisit_keeps_the_ledger()
	_check_explore_pays_once()
	_check_chest_chance_is_stable()
	await _check_furnished_room_hands_over_a_spot()
	await _check_chest_pays_until_the_tile_is_empty()
	await _check_save_round_trip()
	_wipe_scratch()
	GameSaveScript.use_default_directory()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


# ---------------------------------------------------------------------------
# Rolling
# ---------------------------------------------------------------------------

## Same coord in the same world, same gems — the budget is rolled at first create and a re-stream
## must land on the identical row, or a save written before the re-stream disagrees with the world.
func _check_roll_is_deterministic() -> void:
	var seed_a := DistrictCoord.district_seed(WORLD_SEED, COORD)
	var first := DistrictEconomy.roll_budgets(DistrictTheme.OLD_TOWN, seed_a)
	var again := DistrictEconomy.roll_budgets(DistrictTheme.OLD_TOWN, seed_a)
	if first != again:
		_fail("FAIL the same theme and seed rolled %s then %s" % [str(first), str(again)])
		return
	var total := 0
	for gem: int in first.keys():
		total += int(first[gem])
	var want := int(DistrictEconomy.THEME_TOTALS[DistrictTheme.OLD_TOWN])
	if total != want:
		_fail("FAIL an old town owes %d gems, want %d" % [total, want])
		return

	## The split follows the city-wide rarity curve, so the commonest gem must not be the rarest.
	var quartz := int(first[VoxelMaterial.GEM_QUARTZ])
	var diamond := int(first[VoxelMaterial.GEM_DIAMOND])
	if quartz <= diamond:
		_fail("FAIL a rolled budget holds %d quartz and %d diamond" % [quartz, diamond])
		return

	## A different tile is a different budget — one roll shared by the whole city would make the
	## per-district ledger pointless.
	var other := DistrictEconomy.roll_budgets(
		DistrictTheme.OLD_TOWN, DistrictCoord.district_seed(WORLD_SEED, OTHER_COORD)
	)
	if other == first:
		_fail("FAIL two different tiles rolled the identical budget %s" % str(first))
		return
	print("OK an old town owes %d gems, %d quartz to %d diamond" % [total, quartz, diamond])


## Hills are the mine, and their budget is the ore the bake painted rather than a table figure —
## most of it buried where only digging finds it.
func _check_hill_budget_is_its_own_ore() -> void:
	var mats := PackedInt32Array([
		VoxelMaterial.GEM_QUARTZ,
		VoxelMaterial.GEM_QUARTZ,
		VoxelMaterial.GEM_DIAMOND,
		VoxelMaterial.GEM_SAPPHIRE,
		VoxelMaterial.GEM_QUARTZ,
	])
	var budgets := DistrictEconomy.budgets_from_gem_mats(mats)
	if int(budgets[VoxelMaterial.GEM_QUARTZ]) != 3:
		_fail("FAIL a hill with three quartz nuggets owes %d" % budgets[VoxelMaterial.GEM_QUARTZ])
		return
	if int(budgets[VoxelMaterial.GEM_DIAMOND]) != 1:
		_fail("FAIL a hill with one diamond owes %d" % budgets[VoxelMaterial.GEM_DIAMOND])
		return
	if int(budgets[VoxelMaterial.GEM_EMERALD]) != 0:
		_fail("FAIL a hill with no emerald owes %d" % budgets[VoxelMaterial.GEM_EMERALD])
		return
	if int(budgets[VoxelMaterial.GEM_TOPAZ]) != 0:
		_fail("FAIL a hill with no topaz owes %d" % budgets[VoxelMaterial.GEM_TOPAZ])
		return
	print("OK a hill owes exactly the ore its bake painted")


# ---------------------------------------------------------------------------
# Spending
# ---------------------------------------------------------------------------

func _check_take_depletes_and_then_refuses() -> void:
	var eco: DistrictEconomy = DistrictEconomyScript.new() as DistrictEconomy
	var budgets: Dictionary[int, int] = {
		VoxelMaterial.GEM_QUARTZ: 2,
		VoxelMaterial.GEM_DIAMOND: 0,
	}
	if not eco.ensure_row(COORD, budgets):
		_fail("FAIL a fresh coord refused its first row")
		return
	if eco.remaining(COORD, VoxelMaterial.GEM_QUARTZ) != 2:
		_fail("FAIL the row owes %d quartz" % eco.remaining(COORD, VoxelMaterial.GEM_QUARTZ))
		return
	for i in range(2):
		if not eco.try_take(COORD, VoxelMaterial.GEM_QUARTZ):
			_fail("FAIL quartz %d of 2 was refused" % (i + 1))
			return
	if eco.try_take(COORD, VoxelMaterial.GEM_QUARTZ):
		_fail("FAIL a spent tile paid a third quartz")
		return
	## Running one type dry says nothing about the others.
	if eco.remaining(COORD, VoxelMaterial.GEM_DIAMOND) != 0:
		_fail("FAIL the row invented diamonds")
		return
	## And a tile nobody has created owes nothing at all, rather than paying out of thin air.
	if eco.try_take(OTHER_COORD, VoxelMaterial.GEM_QUARTZ):
		_fail("FAIL a tile with no row paid a quartz")
		return
	print("OK a budget spends down to nothing and then refuses")


## The farming case: leave a stripped tile, come back, and the streamer re-bakes every nugget.
## `ensure_row` has to leave the ledger alone or the ore pays twice.
func _check_revisit_keeps_the_ledger() -> void:
	var eco: DistrictEconomy = DistrictEconomyScript.new() as DistrictEconomy
	var seed_v := DistrictCoord.district_seed(WORLD_SEED, COORD)
	eco.ensure_row(COORD, DistrictEconomy.roll_budgets(DistrictTheme.LAKE, seed_v))
	var owed := eco.remaining_total(COORD)
	while eco.try_take(COORD, VoxelMaterial.GEM_QUARTZ):
		pass
	var left := eco.remaining_total(COORD)
	if left >= owed:
		_fail("FAIL stripping the quartz left %d of %d gems" % [left, owed])
		return
	## Second create of the same coord: same call the streamer makes, same arguments.
	if eco.ensure_row(COORD, DistrictEconomy.roll_budgets(DistrictTheme.LAKE, seed_v)):
		_fail("FAIL a re-streamed tile was given a second row")
		return
	if eco.remaining_total(COORD) != left:
		_fail(
			"FAIL a re-streamed tile came back with %d gems instead of %d"
			% [eco.remaining_total(COORD), left]
		)
		return
	if eco.remaining(COORD, VoxelMaterial.GEM_QUARTZ) != 0:
		_fail("FAIL the re-bake refilled the quartz")
		return
	print("OK re-streaming a stripped tile does not refill it")


# ---------------------------------------------------------------------------
# Exploring
# ---------------------------------------------------------------------------

func _check_explore_pays_once() -> void:
	var eco: DistrictEconomy = DistrictEconomyScript.new() as DistrictEconomy
	if eco.mark_explored(COORD):
		_fail("FAIL a tile with no row could be explored")
		return
	eco.ensure_row(COORD, DistrictEconomy.roll_budgets(DistrictTheme.CIVIC_QUARTER, 7))
	if eco.is_explored(COORD):
		_fail("FAIL a fresh row starts out explored")
		return
	if not eco.mark_explored(COORD):
		_fail("FAIL walking into a new tile paid nothing")
		return
	if not eco.is_explored(COORD):
		_fail("FAIL the tile did not stay explored")
		return
	if eco.mark_explored(COORD):
		_fail("FAIL walking back into the same tile paid a second time")
		return
	## Unload and re-create: the flag lives in the ledger, not on the district node.
	eco.ensure_row(COORD, DistrictEconomy.roll_budgets(DistrictTheme.CIVIC_QUARTER, 7))
	if eco.mark_explored(COORD):
		_fail("FAIL a re-streamed tile paid its explore score again")
		return
	if eco.explored_count() != 1:
		_fail("FAIL %d tiles read as explored" % eco.explored_count())
		return
	print("OK exploring a tile pays once, re-streaming included")


# ---------------------------------------------------------------------------
# Chests
# ---------------------------------------------------------------------------

## A chest is a find, so most rooms have none — and the same room must answer the same way every
## time it is furnished, or a re-streamed building sprouts chests it did not have.
func _check_chest_chance_is_stable() -> void:
	var room_seed := 12345
	var first := GemChestPlacer.should_place(RoomDecorator.Purpose.STORAGE, room_seed)
	if first != GemChestPlacer.should_place(RoomDecorator.Purpose.STORAGE, room_seed):
		_fail("FAIL the same room seed gave two different answers")
		return
	if GemChestPlacer.chance_pct(RoomDecorator.Purpose.CORRIDOR) != 0:
		_fail("FAIL corridors can hold chests")
		return
	if (
		GemChestPlacer.chance_pct(RoomDecorator.Purpose.STORAGE)
		<= GemChestPlacer.chance_pct(RoomDecorator.Purpose.BEDROOM)
	):
		_fail("FAIL a storage room is no likelier than a bedroom")
		return
	var hits := 0
	for i in range(400):
		if GemChestPlacer.should_place(RoomDecorator.Purpose.BEDROOM, i * 977 + 13):
			hits += 1
	if hits == 0 or hits > 80:
		_fail("FAIL %d of 400 ordinary rooms held a chest" % hits)
		return
	print("OK %d of 400 ordinary rooms hold a chest, corridors never do" % hits)


## The seam between the decorator and the chest: furnishing a room offers it up exactly once, and
## the spot picked out of it is a cell a chest can actually stand in.
func _check_furnished_room_hands_over_a_spot() -> void:
	var brush: CityBrush = CityBrushScript.new()
	brush.use_offline_volume()
	var volume: RoomVolume = RoomVolumeScript.make(Rect2i(4, 4, 12, 12), 10, 5) as RoomVolume
	brush.fill_box(
		Vector3i(volume.rect.position.x - 1, volume.floor_y, volume.rect.position.y - 1),
		Vector3i(volume.rect.end.x + 1, volume.floor_y + volume.air_h + 2, volume.rect.end.y + 1),
		VoxelMaterial.STONE
	)
	brush.fill_box(volume.air_min(), volume.air_max(), VoxelMaterial.AIR)

	var room: InteriorRoom = InteriorRoomScript.make(
		volume.rect, volume.floor_y, volume.air_h, RoomDecorator.Purpose.STORAGE
	) as InteriorRoom
	var building: BuildingInterior = BuildingInteriorScript.make(
		room.rect.grow(1), room.use
	) as BuildingInterior
	building.storeys.append(room)
	var district := FakeDistrict.new()
	district.interior_buildings = {Vector2i.ZERO: building}

	var dec: InteriorDecorator = InteriorDecoratorScript.new() as InteriorDecorator
	dec.brush = brush
	dec.voxel_size = 0.5
	if not dec.take_furnished_room().is_empty():
		_fail("FAIL a decorator that has done nothing offered a furnished room")
		return
	var foot := Vector3(
		float(volume.rect.position.x + 2) * 0.5 + 0.25,
		float(volume.floor_y + 1) * 0.5 + 0.1,
		float(volume.rect.position.y + 2) * 0.5 + 0.25
	)
	## First tick plans the storey, second furnishes the room.
	dec.tick(foot, [district])
	dec.tick(foot, [district])
	var furnished := dec.take_furnished_room()
	if furnished.is_empty():
		_fail("FAIL furnishing a room offered nothing to put a chest in")
		return
	if furnished["coord"] as Vector2i != COORD:
		_fail("FAIL the furnished room named district %s" % str(furnished["coord"]))
		return
	if furnished["rect"] as Rect2i != room.rect:
		_fail("FAIL the furnished room named rect %s" % str(furnished["rect"]))
		return
	if not dec.take_furnished_room().is_empty():
		_fail("FAIL the same furnished room was offered twice, so it can hold two chests")
		return

	var city := TestCity.new()
	city.name = "SpotCity"
	add_child(city)
	city.set_process(false)
	city.set_physics_process(false)
	await get_tree().process_frame
	city.bind_test_brush(brush)
	var spot := city.pick_chest_spot(furnished)
	if spot == Vector3i(2147483647, 2147483647, 2147483647):
		_fail("FAIL a furnished storage room had nowhere to stand a chest")
		city.queue_free()
		return
	if not room.rect.has_point(Vector2i(spot.x, spot.z)):
		_fail("FAIL the chest spot %s is outside the room" % str(spot))
		city.queue_free()
		return
	if not VoxelMaterial.is_solid(brush.get_vox(spot + Vector3i(0, -1, 0))):
		_fail("FAIL the chest spot %s has no floor under it" % str(spot))
		city.queue_free()
		return
	if brush.get_vox(spot) != VoxelMaterial.AIR:
		_fail("FAIL the chest spot %s is inside something" % str(spot))
		city.queue_free()
		return
	print("OK a furnished room is offered once and yields a standable spot at %s" % str(spot))
	city.queue_free()


## The chest end to end: a click hands over gems from the tile's budget, and once that tile is
## empty the same click opens an empty chest instead of paying again.
func _check_chest_pays_until_the_tile_is_empty() -> void:
	var city := TestCity.new()
	city.name = "TestCity"
	add_child(city)
	city.set_process(false)
	city.set_physics_process(false)
	await get_tree().process_frame

	var eco := city.get_economy()
	var stocked: Dictionary[int, int] = {VoxelMaterial.GEM_QUARTZ: 40}
	eco.ensure_row(COORD, stocked)
	var inv := city.get_inventory()
	inv.clear()

	## Through a real district node, because that is what owns the chests in a live world and what
	## takes them away again when the tile unloads.
	var district: DistrictInstance = DistrictInstanceScript.new() as DistrictInstance
	district.name = "District"
	district.coord = COORD
	add_child(district)
	var placer := district.ensure_gem_chests()
	if district.ensure_gem_chests() != placer:
		_fail("FAIL a district made a second chest holder")
		_free_chest_case(city, district)
		return
	var chest := placer.place_chest(COORD, Vector3(4.0, 1.0, 4.0), 0.0, 4242)
	if chest == null:
		_fail("FAIL the chest could not be built")
		_free_chest_case(city, district)
		return
	if not chest.is_in_group("world_interact"):
		_fail("FAIL a chest is not a world_interact node, so a click cannot find it")
		_free_chest_case(city, district)
		return
	if chest.get_node_or_null("ClickBody") == null:
		_fail("FAIL the chest has no collision body for the aim ray to hit")
		_free_chest_case(city, district)
		return

	var before := eco.remaining(COORD, VoxelMaterial.GEM_QUARTZ)
	if not chest.interact_at_world(chest.global_position):
		_fail("FAIL the chest did not swallow the click")
		_free_chest_case(city, district)
		return
	var paid := before - eco.remaining(COORD, VoxelMaterial.GEM_QUARTZ)
	## Quartz is all this tile owes, so a chest that draws from what is left must pay in quartz.
	if paid < GemChest.GEMS_MIN or paid > GemChest.GEMS_MAX:
		_fail("FAIL an opened chest took %d gems out of the budget" % paid)
		_free_chest_case(city, district)
		return
	if inv.count_of(InventoryCatalog.ID_QUARTZ) != paid:
		_fail(
			"FAIL the chest paid %d gems but the inventory holds %d"
			% [paid, inv.count_of(InventoryCatalog.ID_QUARTZ)]
		)
		_free_chest_case(city, district)
		return
	if not chest.is_opened():
		_fail("FAIL an opened chest does not read as opened")
		_free_chest_case(city, district)
		return

	## Clicking it again is still a click on a chest — swallowed, but worth nothing.
	var held := inv.count_of(InventoryCatalog.ID_QUARTZ)
	if not chest.interact_at_world(chest.global_position):
		_fail("FAIL an open chest stopped swallowing clicks, so it can be shot")
		_free_chest_case(city, district)
		return
	if inv.count_of(InventoryCatalog.ID_QUARTZ) != held:
		_fail("FAIL re-opening the chest paid again")
		_free_chest_case(city, district)
		return

	## A chest in a tile that has already been picked clean opens empty.
	while eco.try_take(COORD, VoxelMaterial.GEM_QUARTZ):
		pass
	var empty_chest := placer.place_chest(COORD, Vector3(6.0, 1.0, 4.0), 0.0, 99)
	if empty_chest == null:
		_fail("FAIL the second chest could not be built")
		_free_chest_case(city, district)
		return
	var held_before := inv.count_of(InventoryCatalog.ID_QUARTZ)
	empty_chest.interact_at_world(empty_chest.global_position)
	if inv.count_of(InventoryCatalog.ID_QUARTZ) != held_before:
		_fail("FAIL a chest in a stripped district still paid out")
		_free_chest_case(city, district)
		return
	print("OK a chest pays %d gems from the tile's budget, then nothing" % paid)
	_free_chest_case(city, district)


## Unloading a tile is `destroy_and_clear`, and it has to take the chests with it — a chest left
## behind would be a clickable payout floating in a district that no longer exists.
func _free_chest_case(city: TestCity, district: DistrictInstance) -> void:
	var placer := district.gem_chests
	## No VoxelTool: this district was never baked, and unload does not touch voxels through it.
	district.destroy_and_clear(null)
	if district.gem_chests != null:
		_fail("FAIL an unloaded district still holds a chest placer")
	if placer != null and is_instance_valid(placer) and not placer.is_queued_for_deletion():
		_fail("FAIL the chest placer survived its district being unloaded")
	city.queue_free()


# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------

## The ledger is only worth keeping if it comes back. Rows are compared on a *second* economy,
## because loading into the one that wrote them would pass with an empty apply.
func _check_save_round_trip() -> void:
	var walker := CityWalkerScript.new() as CityWalker
	walker.name = "SaveWalker"
	add_child(walker)
	walker.set_physics_process(false)
	walker.set_process(false)
	await get_tree().process_frame
	if walker.get_proportions() == null:
		_fail("FAIL the save walker came up without proportions")
		walker.queue_free()
		return
	walker.global_position = Vector3(12.0, 8.0, -3.0)

	var eco: DistrictEconomy = DistrictEconomyScript.new() as DistrictEconomy
	eco.ensure_row(
		COORD, DistrictEconomy.roll_budgets(DistrictTheme.CASTLE, WORLD_SEED)
	)
	eco.ensure_row(
		OTHER_COORD, DistrictEconomy.budgets_from_gem_mats(
			PackedInt32Array([VoxelMaterial.GEM_EMERALD, VoxelMaterial.GEM_EMERALD])
		)
	)
	eco.try_take(COORD, VoxelMaterial.GEM_QUARTZ)
	eco.mark_explored(COORD)
	var want_castle := eco.remaining(COORD, VoxelMaterial.GEM_QUARTZ)
	var score := DistrictEconomy.EXPLORE_SCORE * 3

	var inventory := PlayerInventoryScript.new() as PlayerInventory
	var data := GameSaveScript.capture(
		WORLD_SEED, walker, inventory, "Gems", eco, score
	)
	walker.queue_free()
	if data.is_empty():
		_fail("FAIL capture produced nothing")
		return
	if not GameSaveScript.write_quicksave(data):
		_fail("FAIL could not write the quicksave")
		return
	var read := GameSaveScript.read_quicksave()
	if read.is_empty():
		_fail("FAIL the v%d quicksave read back empty" % GameSaveScript.VERSION)
		return
	if GameSaveScript.saved_score(read) != score:
		_fail("FAIL the score came back as %d, not %d" % [GameSaveScript.saved_score(read), score])
		return

	var loaded: DistrictEconomy = DistrictEconomyScript.new() as DistrictEconomy
	GameSaveScript.apply_districts(loaded, read)
	if loaded.row_count() != 2:
		_fail("FAIL %d district rows came back, want 2" % loaded.row_count())
		return
	if loaded.remaining(COORD, VoxelMaterial.GEM_QUARTZ) != want_castle:
		_fail(
			"FAIL the castle came back owing %d quartz, not %d"
			% [loaded.remaining(COORD, VoxelMaterial.GEM_QUARTZ), want_castle]
		)
		return
	if loaded.remaining(OTHER_COORD, VoxelMaterial.GEM_EMERALD) != 2:
		_fail(
			"FAIL the hill came back owing %d emerald, not 2"
			% loaded.remaining(OTHER_COORD, VoxelMaterial.GEM_EMERALD)
		)
		return
	if not loaded.is_explored(COORD):
		_fail("FAIL the explored flag did not survive the save")
		return
	if loaded.is_explored(OTHER_COORD):
		_fail("FAIL an unexplored tile came back explored")
		return
	print("OK the save carries %d district rows and a score of %d" % [loaded.row_count(), score])


func _wipe_scratch() -> void:
	if not DirAccess.dir_exists_absolute(SCRATCH_DIR):
		return
	var dir := DirAccess.open(SCRATCH_DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		DirAccess.remove_absolute("%s/%s" % [SCRATCH_DIR, file])
