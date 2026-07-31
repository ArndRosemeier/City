## The one thing the save feature is for: a run that comes back.
##
## The file layer is covered headless by test_game_save. What that cannot reach is the part where a
## load throws the world away and builds it again — the seed has to travel with the save, the
## spawn district has to be the one the character stood in rather than the one the seed would have
## picked, and the character has to be poured into a walker that did not exist when the save was
## written. Each of those is a separate place for a load to come back as a stranger in the wrong
## city, and all three are silent failures: the game keeps running, just not as the run that was
## saved.
##
## New Game is checked in the same session because it is the opposite promise: it must take the
## autosave with it, so the next launch does not resume the run the player walked away from.
##
## Needs a renderer: the district bake waits on voxel areas becoming editable.
##
## Run: powershell -File tools\run_test.ps1 test_save_load_cycle -Rendered -TimeoutSec 300
extends Node

const SCRATCH_DIR := "user://test_cycle_saves"
const WORLD_SEED := 42
const BOOT_TIMEOUT_MS := 150_000
## How far the saved position may drift after the load. The footing search may lift the character
## onto whatever the rebuilt world put in his column, so only the ground plane is pinned.
const XZ_TOLERANCE_M := 0.75
const GEM_COUNT := 9
const SAVED_SCALE := 1.35


var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	GameSave.use_directory(SCRATCH_DIR)
	_wipe_scratch()

	var city := CityRoot.new()
	city.city_seed = WORLD_SEED
	add_child(city)
	var walker := await _await_boot(city)
	if walker == null:
		_finish()
		return

	var saved_pos := walker.global_position
	walker.set_character_scale(SAVED_SCALE, true)
	var inv := city.get_inventory()
	inv.clear()
	if inv.add(InventoryCatalog.ID_TOPAZ, GEM_COUNT) != 0:
		_fail("FAIL could not stock the inventory before saving")
	if not city.write_quicksave("Cycle test"):
		_fail("FAIL the live city wrote no quicksave")
		_finish()
		return
	print("OK saved at %s with %d topaz at scale %.2f" % [saved_pos, GEM_COUNT, SAVED_SCALE])

	## Walk away from everything the save recorded, so a load that restores nothing fails here.
	walker.global_position = saved_pos + Vector3(400.0, 0.0, 400.0)
	walker.set_character_scale(1.0, true)
	inv.clear()

	if not city.load_quicksave():
		_fail("FAIL the load was refused")
		_finish()
		return
	var reloaded := await _await_boot(city)
	if reloaded == null:
		_finish()
		return
	if reloaded == walker:
		_fail("FAIL the load reused the old walker instead of rebuilding the world")

	if city.city_seed != WORLD_SEED:
		_fail("FAIL the loaded world seed is %d, not the saved %d" % [city.city_seed, WORLD_SEED])
	var landed := reloaded.global_position
	var drift := Vector2(landed.x - saved_pos.x, landed.z - saved_pos.z).length()
	if drift > XZ_TOLERANCE_M:
		_fail("FAIL landed %.2f m from the saved column (%s vs %s)" % [drift, landed, saved_pos])
	else:
		print("OK landed %.2f m from the saved column at y %.2f (saved y %.2f)"
			% [drift, landed.y, saved_pos.y])
	if not is_equal_approx(reloaded.get_character_scale(), SAVED_SCALE):
		_fail("FAIL character scale came back as %.3f" % reloaded.get_character_scale())
	var got_gems := city.get_inventory().count_of(InventoryCatalog.ID_TOPAZ)
	if got_gems != GEM_COUNT:
		_fail("FAIL topaz came back as %d, saved %d" % [got_gems, GEM_COUNT])
	if not _failed:
		print("OK the load rebuilt the saved world and put the character back in it")

	_check_teardown_cannot_clobber(city, reloaded)
	_check_new_game_drops_the_autosave(city)

	_wipe_scratch()
	GameSave.use_default_directory()
	_finish()


## Shutting the game down used to write one last autosave from a walker that had already left the
## tree. Such a walker answers every question about itself correctly except where it is standing,
## which comes back as the world origin — so the good save written moments earlier was replaced by a
## character stranded at (0, 0, 0), and closing the window looked like it had not saved at all.
func _check_teardown_cannot_clobber(city: CityRoot, walker: CityWalker) -> void:
	if not city.write_quicksave("Before teardown"):
		_fail("FAIL the city refused to save a walker standing in the world")
		return
	var good_pos := GameSave.saved_position(GameSave.read_quicksave())
	if good_pos.length() < 1.0:
		_fail("FAIL the save taken before teardown already reads as the world origin")
		return

	var parent := walker.get_parent()
	parent.remove_child(walker)
	if city.can_save_game():
		_fail("FAIL the city still offers to save a walker that has left the tree")
	if city.write_quicksave("After teardown"):
		_fail("FAIL a detached walker was written into the autosave slot")
	if not GameSave.capture(city.city_seed, walker, city.get_inventory(), "direct").is_empty():
		_fail("FAIL GameSave.capture accepted a walker that has no world position")
	var now := GameSave.saved_position(GameSave.read_quicksave())
	if not now.is_equal_approx(good_pos):
		_fail("FAIL the autosave moved during teardown: %s became %s" % [good_pos, now])
	else:
		print("OK teardown cannot overwrite the save — still at %s" % good_pos)

	## Put him back, so the New Game check still has a live character to work with.
	parent.add_child(walker)
	if not city.can_save_game():
		_fail("FAIL the walker did not rejoin the world after the teardown check")


## New Game keeps the named library and drops the autosave. The world it then builds is not waited
## on: what matters is that the file the next launch would resume from is gone.
func _check_new_game_drops_the_autosave(city: CityRoot) -> void:
	if not city.write_named_save("keep_me"):
		_fail("FAIL could not write the named save New Game must spare")
		return
	if not city.has_quicksave():
		_fail("FAIL there is no autosave for New Game to drop")
		return
	city.start_new_game()
	if city.has_quicksave():
		_fail("FAIL New Game left the autosave in place — the next launch would resume it")
	if city.city_seed == WORLD_SEED:
		_fail("FAIL New Game kept the old world seed")
	var names := PackedStringArray()
	for entry: Dictionary in city.list_named_saves():
		names.append(String(entry["name"]))
	if not names.has("keep_me"):
		_fail("FAIL New Game took the named library with it: %s" % str(names))
	else:
		print("OK New Game dropped the autosave, kept the library, and drew a new seed")


func _await_boot(city: CityRoot) -> CityWalker:
	var deadline := Time.get_ticks_msec() + BOOT_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var walker := city.get_node_or_null("Walker") as CityWalker
		if walker != null and walker.is_physics_processing() and not city.is_splash_open():
			## A few frames of settling: the restore runs right after physics comes on.
			for _i in range(6):
				await get_tree().process_frame
			return city.get_node_or_null("Walker") as CityWalker
	_fail("FAIL the city never became playable within %d ms" % BOOT_TIMEOUT_MS)
	return null


func _wipe_scratch() -> void:
	var dir := DirAccess.open(SCRATCH_DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		DirAccess.remove_absolute("%s/%s" % [SCRATCH_DIR, file])


func _finish() -> void:
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)
