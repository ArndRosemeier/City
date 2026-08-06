## Do spawn spires actually stand up in a streamed crypt / castle dungeon?
##
## `test_spawn_tower` proves the rules on a fixture. This is the other half: the spire is stamped
## into terrain the district just wrote, and its anchor is found by reading that terrain — so a
## composer that names its pad Y differently, or a room whose blocks are not resident when the
## station streams in, breaks the feature with nothing on the fixture to show for it.
##
## The tile under test is whichever one the boot flags pin, so both rooms are covered by the same
## scene. Run (-Command, not -File: the -File binder flattens a comma list into one argument):
##   powershell -Command "& '.\tools\run_test.ps1' -Scene test_spawn_tower_live
##     -GodotArgs @('--spawn-theme=graveyard','--city-seed=42')"
##   powershell -Command "& '.\tools\run_test.ps1' -Scene test_spawn_tower_live
##     -GodotArgs @('--spawn-theme=castle','--city-seed=42')"
extends Node

const MonsterFactionScript := preload("res://scripts/city/monster_faction.gd")

const BOOT_TIMEOUT_MS := 120_000
const TILE_TIMEOUT_SEC := 120.0

var _city: CityRoot = null
var _failed: bool = false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	var city := CityRoot.new()
	city.city_seed = 42
	## Headless has no renderer to hand a skinned pedestrian, and these are ordinary tiles with a
	## full crowd on them — the dummy mesh server takes the whole process down before the crypt is
	## ever reached. Nothing here is about people on the pavement.
	city.crowd_per_district = 0
	city.vehicles_per_district = 0
	add_child(city)
	_city = city

	var deadline := Time.get_ticks_msec() + BOOT_TIMEOUT_MS
	while city.get_node_or_null("Walker") == null:
		if Time.get_ticks_msec() > deadline:
			_fail("FAIL no walker after %d s" % (BOOT_TIMEOUT_MS / 1000))
			_quit()
			return
		await get_tree().process_frame
	_hide_overlays()

	var theme := DistrictTheme.for_district(city.city_seed, city.spawn_district_coord)
	if theme.id != DistrictTheme.GRAVEYARD and theme.id != DistrictTheme.CASTLE:
		_fail(
			"FAIL spawn district is %s — pin --spawn-theme=graveyard or castle"
			% theme.display_name
		)
		_quit()
		return

	## Judge the tile the frame it is ready rather than after a fixed settle: the headless dummy
	## renderer takes the process down within seconds of the first skinned body being drawn.
	var inst := await _await_station_tile(city, theme.id)
	if inst == null:
		_quit()
		return
	if theme.id == DistrictTheme.GRAVEYARD:
		_check_spire(
			city,
			inst.crypt_spawn_tower,
			inst.crypt_spawner.spawn_world,
			int(MonsterFactionScript.Id.UNDEAD),
			"crypt"
		)
	else:
		_check_dungeon_spires(city, inst)
	_quit()


## The streamed spawn tile, once its stations are up. Null when they never arrive.
func _await_station_tile(city: CityRoot, theme_id: int) -> DistrictInstance:
	var deadline := Time.get_ticks_msec() + int(TILE_TIMEOUT_SEC * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var inst := _spawn_district(city)
		if inst != null and _stations_up(inst, theme_id):
			return inst
		await get_tree().process_frame
	_fail("FAIL no summoning station on the spawn tile after %.0f s" % TILE_TIMEOUT_SEC)
	return null


func _stations_up(inst: DistrictInstance, theme_id: int) -> bool:
	if theme_id == DistrictTheme.GRAVEYARD:
		return inst.crypt_spawner != null and is_instance_valid(inst.crypt_spawner)
	return not inst.dungeon_summoners.is_empty()


## Both castle pads, each on its own rolled faction. Two spires is the plan; one is a placement
## that silently failed on the tighter of the two vaults.
func _check_dungeon_spires(city: CityRoot, inst: DistrictInstance) -> void:
	if inst.dungeon_spawn_towers.size() != inst.dungeon_summoners.size():
		_fail(
			"FAIL %d dungeon pads carry %d spires"
			% [inst.dungeon_summoners.size(), inst.dungeon_spawn_towers.size()]
		)
		return
	var layout: CastleLayout = inst.generator.get_castle_layout()
	if layout == null:
		_fail("FAIL the castle tile has no layout to read pad factions from")
		return
	for i in range(inst.dungeon_spawn_towers.size()):
		var station: Node3D = inst.dungeon_summoners[i]
		var faction := MonsterFactionScript.from_name(
			String(layout.dungeon_summoner_factions[i])
		)
		_check_spire(
			city,
			inst.dungeon_spawn_towers[i],
			station.get("spawn_world") as Vector3,
			int(faction),
			"dungeon pad %d" % i
		)


func _check_spire(
	city: CityRoot,
	tower: Node3D,
	station_world: Vector3,
	want_faction: int,
	label: String
) -> void:
	if tower == null or not is_instance_valid(tower):
		_fail("FAIL the %s station has no spire over it" % label)
		return
	var unit: UndeadUnit = tower.get("unit") as UndeadUnit
	if unit == null or not is_instance_valid(unit) or not unit.is_alive():
		_fail("FAIL the %s spire has no living host" % label)
		return
	if unit.faction() != want_faction:
		_fail(
			"FAIL the %s spire is faction %d, want the station's %d"
			% [label, unit.faction(), want_faction]
		)
		return
	## The stamp has to be in the world and held: a spire the player can dig out from under is a
	## timer again, and one whose cells were never written is invisible.
	var ward := city.voxel_ward()
	var brush := city.voxel_brush()
	if ward == null or brush == null:
		_fail("FAIL the city has no ward / brush to read the stamp back with")
		return
	var held := 0
	var solid := 0
	for cell: Vector3i in tower.get("_cells") as Array[Vector3i]:
		if ward.holds(cell):
			held += 1
		if brush.get_vox(cell) != VoxelMaterial.AIR:
			solid += 1
	if held <= 0 or held != solid:
		_fail("FAIL the %s spire holds %d cells but only %d are solid" % [label, held, solid])
		return
	## The station summons beside the mass, not inside it.
	var gap := Vector2(
		station_world.x - tower.global_position.x,
		station_world.z - tower.global_position.z
	).length()
	if gap <= 0.5:
		_fail("FAIL the %s station summons %.2f m from its spire centre" % [label, gap])
		return
	print(
		"live: %s spire at %v holds %d warded cells, station %.2f m aside"
		% [label, tower.global_position, held, gap]
	)


func _spawn_district(city: CityRoot) -> DistrictInstance:
	var want := city.spawn_district_coord
	var districts: Array = city._streamer.call("get_loaded_districts") as Array
	for entry: Variant in districts:
		var di: DistrictInstance = entry
		if di.coord == want and di.generator != null:
			return di
	return null


func _hide_overlays() -> void:
	for child: Node in _city.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	var errors := get_node_or_null("/root/ErrorOverlay")
	if errors is CanvasLayer:
		(errors as CanvasLayer).visible = false


func _quit() -> void:
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		print("RESULT: OK")
		get_tree().quit(0)
