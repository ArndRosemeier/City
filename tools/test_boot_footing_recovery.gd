## Boot must not be one bad voxel column away from an unusable game.
##
## A spawn used to be a single gate: one column, one wait, and a hard refusal to enable walker
## physics if that column came up empty — which is exactly what a streaming race or a carved-out
## save position produces. The player got a splash that never went away.
##
## So the footing search is a ladder, and this pins every rung of it: the preferred column, the
## rings around it, the district's own spawn, and finally a soft landing that still reaches play.
## The only empty answer allowed is the one the caller can act on — no finite place to stand at
## all, which is what puts the Retry / New Game / Quit overlay on screen.
##
## Needs a renderer: the district bake waits on voxel areas becoming editable.
##
## Run: powershell -File tools\run_test.ps1 test_boot_footing_recovery -Rendered -TimeoutSec 300
extends Node

const WORLD_SEED := 42
const BOOT_TIMEOUT_MS := 150_000
## Rungs below the first are meant to be quick, and the test should not sit through the real
## ten-second grace on columns it deliberately emptied.
const PROBE_MS := 400
## Deep enough to clear FLOOR_PROBE_DOWN_M / UP_M so the carved column reads as pure void.
const CARVE_TOP_VOX := 26

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	var city := CityRoot.new()
	city.city_seed = WORLD_SEED
	add_child(city)
	var walker := await _await_boot(city)
	if walker == null:
		_finish()
		return

	var spawn := walker.global_position
	var gen := _spawn_generator(city, spawn)
	if gen == null:
		_fail("FAIL no district generator under the spawn — cannot exercise the ladder")
		_finish()
		return

	await _check_preferred_column_wins(city, gen, spawn)
	await _check_carved_column_falls_back_to_a_neighbour(city, gen, spawn)
	await _check_void_column_soft_lands(city, spawn)
	await _check_nothing_finite_reports_failure(city)

	_finish()


## The happy path still has to be the cheap one: ground under the asked-for column is used as is.
func _check_preferred_column_wins(city: CityRoot, gen: DistrictGenerator, spawn: Vector3) -> void:
	var got: Dictionary = await city._resolve_playable_footing(spawn, gen, "test preferred", PROBE_MS)
	if got.is_empty():
		_fail("FAIL the resolver found nothing in the column the walker is standing in")
		return
	if String(got["source"]) != CityRoot.FOOTING_PREFERRED:
		_fail(
			"FAIL good ground resolved as '%s', want '%s'"
			% [got["source"], CityRoot.FOOTING_PREFERRED]
		)
		return
	var floor_y := float(got["floor_y"])
	if absf(floor_y - spawn.y) > 1.0:
		_fail("FAIL preferred floor came back at y %.2f, walker stands at %.2f" % [floor_y, spawn.y])
		return
	print("OK a column with ground under it is used as-is")


## The failure that started all this: the one column the player is owed has no floor. The rings
## around it do, and waking up a couple of metres away beats not waking up.
func _check_carved_column_falls_back_to_a_neighbour(
	city: CityRoot, gen: DistrictGenerator, spawn: Vector3
) -> void:
	var hole := spawn + Vector3(12.0, 0.0, 0.0)
	if not await _carve_column(city, hole):
		_fail("FAIL could not empty a column to test the fallback rings")
		return
	var got: Dictionary = await city._resolve_playable_footing(hole, gen, "test carved", PROBE_MS)
	if got.is_empty():
		_fail("FAIL an emptied column left the resolver with no answer at all")
		return
	var source := String(got["source"])
	if source != CityRoot.FOOTING_NEARBY:
		_fail("FAIL an emptied column resolved as '%s', want '%s'"
			% [source, CityRoot.FOOTING_NEARBY])
		return
	var landed: Vector3 = got["spawn"] as Vector3
	var drift := Vector2(landed.x - hole.x, landed.z - hole.z).length()
	if drift > CityRoot.FOOTING_RING_RADII_M[CityRoot.FOOTING_RING_RADII_M.size() - 1] + 0.75:
		_fail("FAIL the fallback stand is %.1f m away — further than the outermost ring" % drift)
		return
	if not is_finite(float(got["floor_y"])):
		_fail("FAIL the fallback stand came back with a non-finite floor")
		return
	print("OK an emptied column falls back to solid ground %.1f m away" % drift)


## Far outside anything the world has stamped, with no generator to ask. There is nothing to
## stand on and nothing to fall back to, but the answer still has to be somewhere finite: the
## walker's void floor and safety deck can carry a bad landing, they cannot carry never landing.
func _check_void_column_soft_lands(city: CityRoot, spawn: Vector3) -> void:
	var nowhere := Vector3(spawn.x + 40_000.0, 600.0, spawn.z + 40_000.0)
	var got: Dictionary = await city._resolve_playable_footing(nowhere, null, "test void", PROBE_MS)
	if got.is_empty():
		_fail("FAIL a finite spawn over empty space produced no landing at all")
		return
	if String(got["source"]) != CityRoot.FOOTING_SOFT_LAND:
		_fail(
			"FAIL empty space resolved as '%s', want '%s'"
			% [got["source"], CityRoot.FOOTING_SOFT_LAND]
		)
		return
	if not is_finite(float(got["floor_y"])):
		_fail("FAIL the soft landing came back with a non-finite floor")
		return
	print("OK empty space soft-lands rather than refusing to place the player")


## The one case the caller must handle itself, because there is genuinely nowhere to put a body.
func _check_nothing_finite_reports_failure(city: CityRoot) -> void:
	var got: Dictionary = await city._resolve_playable_footing(
		Vector3(INF, INF, INF), null, "test nowhere", PROBE_MS
	)
	if not got.is_empty():
		_fail("FAIL a non-finite spawn with no generator still returned %s" % got)
		return
	print("OK a spawn with no finite coordinates reports failure so the caller can offer a way out")


## Empties every voxel from bedrock past the top of the floor probe, so the column reads as void
## however far the resolver looks up or down.
func _carve_column(city: CityRoot, world: Vector3) -> bool:
	var tool: VoxelTool = city._tool
	if tool == null:
		return false
	var vx := floori(world.x / CityRoot.VOXEL_SIZE)
	var vz := floori(world.z / CityRoot.VOXEL_SIZE)
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	for y in range(0, CARVE_TOP_VOX + 1):
		tool.set_voxel(Vector3i(vx, y, vz), VoxelMaterial.AIR)
	await get_tree().physics_frame
	return is_nan(city._voxel_floor_y(world))


func _spawn_generator(city: CityRoot, spawn: Vector3) -> DistrictGenerator:
	var coord := DistrictCoord.from_world(spawn, CityRoot.VOXEL_SIZE)
	var inst: DistrictInstance = city._streamer.get_district(coord)
	if inst == null or not is_instance_valid(inst):
		return null
	return inst.generator


func _await_boot(city: CityRoot) -> CityWalker:
	var deadline := Time.get_ticks_msec() + BOOT_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var walker := city.get_node_or_null("Walker") as CityWalker
		if walker != null and walker.is_physics_processing() and not city.is_splash_open():
			for _i in range(6):
				await get_tree().process_frame
			return city.get_node_or_null("Walker") as CityWalker
	_fail("FAIL the city never became playable within %d ms" % BOOT_TIMEOUT_MS)
	return null


func _finish() -> void:
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)
