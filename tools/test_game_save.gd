## Save/load feature test: the two slot kinds, the payload that survives a round trip, and the
## footing search that makes a save taken inside a dug hole loadable again.
##
## The whole run is redirected into a scratch folder first. A headless test that wrote
## `user://saves/quicksave.json` would overwrite the autosave of whoever plays on this machine,
## which is exactly the file the next launch resumes from.
##
## What is actually at risk here, and therefore checked:
##   - A save is only worth writing if it comes back. Every field is compared on a *second*
##     walker, not on the one it was captured from, because applying to the original would pass
##     even if apply_character did nothing at all.
##   - Named slots and the autosave slot must not see each other: the Load list is a library the
##     player built, and the autosave rewrites its file on a timer.
##   - The world is rebuilt from the seed, so anything the character excavated is filled back in.
##     A save taken in a tunnel must resolve to the surface above it rather than inside rock.
##
## Run: powershell -File tools\run_test.ps1 test_game_save
extends Node

const GameSaveScript := preload("res://scripts/city/game_save.gd")
const CityWalkerScript := preload("res://scripts/city/city_walker.gd")
const PlayerInventoryScript := preload("res://scripts/city/player_inventory.gd")
const WorldGamesScript := preload("res://scripts/city/world_games.gd")

const SCRATCH_DIR := "user://test_saves"
const SLOT_NAME := "round_trip"
const GAMES_SLOT := "unfinished_match"
const WORLD_SEED := 4242
const VOX := 0.5
## Body height the footing search must clear, in voxels — the same 1.7 m capsule CityRoot passes.
const BODY_VOX := 4
const UP_VOX := 48
const DOWN_VOX := 12
## Buffer for the footing checks: one column is enough, but a few voxels of margin keeps every
## sampled cell — including the ones a downward scan reaches — inside the buffer.
const BUF := Vector3i(8, 48, 8)
## Where the fake character stood, deliberately buried inside the solid deck around him.
const BURIED_POS := Vector3(2.25, 7.0, 2.25)
## Top solid voxel of that deck, so the footing must land on voxel DECK_TOP_Y + 1.
const DECK_TOP_Y := 19

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	GameSaveScript.use_directory(SCRATCH_DIR)
	_wipe_scratch()
	_check_names()
	_check_footing()
	await _check_round_trip()
	await _check_games_section()
	_check_slots_are_separate()
	_check_old_format_is_retired()
	_wipe_scratch()
	GameSaveScript.use_default_directory()
	if GameSaveScript.saves_dir() != GameSaveScript.SAVES_DIR:
		_fail("FAIL the scratch redirect leaked out of the test")
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


# ---------------------------------------------------------------------------
# Names
# ---------------------------------------------------------------------------

## A save name becomes a filename, so the folding has to be total: anything left over is a path
## the player typed into the game reaching a file the game did not mean to touch.
func _check_names() -> void:
	var cases: Dictionary[String, String] = {
		"My Save": "My_Save",
		"  spaced  out  ": "spaced_out",
		"../../etc/passwd": "etcpasswd",
		"tunnel-run_2": "tunnel-run_2",
		"!!!": "",
		"   ": "",
	}
	for raw: String in cases.keys():
		var got := GameSaveScript.sanitize_name(raw)
		if got != cases[raw]:
			_fail("FAIL sanitize '%s' want '%s' got '%s'" % [raw, cases[raw], got])
	if not GameSaveScript.is_reserved_name("quicksave"):
		_fail("FAIL 'quicksave' must be reserved for the autosave slot")
	if not GameSaveScript.is_reserved_name(" QuickSave "):
		_fail("FAIL the reserved name must not be dodgeable by case or spacing")
	if GameSaveScript.is_reserved_name("quicksave2"):
		_fail("FAIL 'quicksave2' is a perfectly good save name")
	if not GameSaveScript.named_path("!!!").is_empty():
		_fail("FAIL a name with nothing usable in it must not resolve to a path")
	if GameSaveScript.write_named("quicksave", {"version": GameSaveScript.VERSION}):
		_fail("FAIL a named save was allowed onto the autosave slot")
	print("OK save names fold to filenames and the autosave slot is reserved")


# ---------------------------------------------------------------------------
# Footing
# ---------------------------------------------------------------------------

func _check_footing() -> void:
	var buffer := VoxelBuffer.new()
	buffer.create(BUF.x, BUF.y, BUF.z)
	buffer.fill(VoxelMaterial.AIR, VoxelBuffer.CHANNEL_TYPE)
	for y in range(0, DECK_TOP_Y + 1):
		for x in BUF.x:
			for z in BUF.z:
				buffer.set_voxel(VoxelMaterial.STONE, x, y, z, VoxelBuffer.CHANNEL_TYPE)
	var tool := buffer.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_TYPE

	var footing := _footing(tool, BURIED_POS)
	var want_y := float(DECK_TOP_Y + 1) * VOX
	if footing == Vector3.INF:
		_fail("FAIL a buried save found no footing above a solid deck")
	elif not is_equal_approx(footing.y, want_y):
		_fail("FAIL footing y want %.2f got %.2f" % [want_y, footing.y])
	elif floori(footing.x / VOX) != floori(BURIED_POS.x / VOX):
		_fail("FAIL the footing left the saved column: %s" % footing)

	## Standing in the open already: the search must not lift him a voxel for no reason.
	var open_pos := Vector3(BURIED_POS.x, want_y + 0.1, BURIED_POS.z)
	var same := _footing(tool, open_pos)
	if not is_equal_approx(same.y, want_y):
		_fail("FAIL a character already standing free was moved to %s" % same)

	## Caught mid-jump by the autosave timer: the deck is below him, and dropping onto it is the
	## only sane reading of that save.
	var airborne := Vector3(BURIED_POS.x, want_y + 3.0, BURIED_POS.z)
	var landed := _footing(tool, airborne)
	if not is_equal_approx(landed.y, want_y):
		_fail("FAIL an airborne save resolved to %s instead of the deck at %.2f" % [landed, want_y])

	## Water is neither floor nor wall. A save under a lake surface has no footing there.
	buffer.fill(VoxelMaterial.WATER, VoxelBuffer.CHANNEL_TYPE)
	var flooded := GameSaveScript.first_free_footing(tool, BURIED_POS, VOX, BODY_VOX, 4, 4)
	if flooded != Vector3.INF:
		_fail("FAIL water counted as a floor at %s" % flooded)
	print("OK footing lifts a buried save, drops an airborne one, and leaves a free one alone")


func _footing(tool: VoxelTool, world: Vector3) -> Vector3:
	return GameSaveScript.first_free_footing(tool, world, VOX, BODY_VOX, UP_VOX, DOWN_VOX)


# ---------------------------------------------------------------------------
# Round trip
# ---------------------------------------------------------------------------

func _check_round_trip() -> void:
	var source := await _make_walker("Source")
	if source == null:
		return
	source.set_character_scale(1.4, true)
	source.set_health_points(63.5)
	source.set_energy_points(41.25)
	source.set_yaw(1.25)
	source.global_position = BURIED_POS
	var props := source.get_proportions().duplicate_props()
	props.height = 0.42
	props.shoulder_width = -0.31
	source.apply_proportions(props)

	var inventory := PlayerInventoryScript.new() as PlayerInventory
	if inventory.add(InventoryCatalog.ID_QUARTZ, 7) != 0:
		_fail("FAIL could not stock the test inventory with quartz")
	if inventory.add(InventoryCatalog.ID_AMBER, 3) != 0:
		_fail("FAIL could not stock the test inventory with amber")

	var data := GameSaveScript.capture(WORLD_SEED, source, inventory, "Round trip")
	if data.is_empty():
		_fail("FAIL capture produced nothing")
		source.queue_free()
		return
	if not GameSaveScript.write_quicksave(data):
		_fail("FAIL could not write the quicksave")
	if not GameSaveScript.write_named(SLOT_NAME, data):
		_fail("FAIL could not write the named save")

	for slot: String in ["quick", "named"]:
		var read := (
			GameSaveScript.read_quicksave() if slot == "quick"
			else GameSaveScript.read_named(SLOT_NAME)
		)
		if read.is_empty():
			_fail("FAIL the %s slot read back empty" % slot)
			continue
		if GameSaveScript.saved_seed(read) != WORLD_SEED:
			_fail("FAIL %s slot seed want %d got %d"
				% [slot, WORLD_SEED, GameSaveScript.saved_seed(read)])
		if not GameSaveScript.saved_position(read).is_equal_approx(BURIED_POS):
			_fail("FAIL %s slot position got %s" % [slot, GameSaveScript.saved_position(read)])
		await _check_applies_to_fresh_walker(slot, read, source)

	source.queue_free()
	print("OK both slots round-trip the character, the pools and the inventory")


## The payload is poured into a walker that never saw the original. Applying it to the captured
## body would pass even if apply_character were empty.
func _check_applies_to_fresh_walker(slot: String, data: Dictionary, source: CityWalker) -> void:
	var target := await _make_walker("Target_%s" % slot)
	if target == null:
		return
	GameSaveScript.apply_character(target, data)
	var inventory := PlayerInventoryScript.new() as PlayerInventory
	GameSaveScript.apply_inventory(inventory, data)

	if not is_equal_approx(target.get_character_scale(), source.get_character_scale()):
		_fail("FAIL %s scale want %.3f got %.3f"
			% [slot, source.get_character_scale(), target.get_character_scale()])
	if not is_equal_approx(target.get_health(), source.get_health()):
		_fail("FAIL %s health want %.2f got %.2f"
			% [slot, source.get_health(), target.get_health()])
	if not is_equal_approx(target.get_energy(), source.get_energy()):
		_fail("FAIL %s energy want %.2f got %.2f"
			% [slot, source.get_energy(), target.get_energy()])
	if not is_equal_approx(target.get_yaw(), source.get_yaw()):
		_fail("FAIL %s yaw want %.3f got %.3f" % [slot, source.get_yaw(), target.get_yaw()])
	if target.is_female() != source.is_female():
		_fail("FAIL %s sex did not survive the round trip" % slot)
	var want_props := source.get_proportions()
	var got_props := target.get_proportions()
	if not is_equal_approx(got_props.height, want_props.height):
		_fail("FAIL %s proportion height want %.3f got %.3f"
			% [slot, want_props.height, got_props.height])
	if not is_equal_approx(got_props.shoulder_width, want_props.shoulder_width):
		_fail("FAIL %s proportion shoulder_width want %.3f got %.3f"
			% [slot, want_props.shoulder_width, got_props.shoulder_width])
	if target.outfit_save_dict() != source.outfit_save_dict():
		_fail("FAIL %s outfit want %s got %s"
			% [slot, source.outfit_save_dict(), target.outfit_save_dict()])
	if inventory.count_of(InventoryCatalog.ID_QUARTZ) != 7:
		_fail("FAIL %s quartz want 7 got %d"
			% [slot, inventory.count_of(InventoryCatalog.ID_QUARTZ)])
	if inventory.count_of(InventoryCatalog.ID_AMBER) != 3:
		_fail("FAIL %s amber want 3 got %d"
			% [slot, inventory.count_of(InventoryCatalog.ID_AMBER)])
	target.queue_free()


func _make_walker(node_name: String) -> CityWalker:
	var walker := CityWalkerScript.new() as CityWalker
	walker.name = node_name
	add_child(walker)
	## No frame may drive it: there is no terrain here for voxel motion to walk on.
	walker.set_physics_process(false)
	walker.set_process(false)
	await get_tree().process_frame
	if walker.get_proportions() == null:
		_fail("FAIL %s came up without proportions" % node_name)
		walker.queue_free()
		return null
	return walker


# ---------------------------------------------------------------------------
# Games
# ---------------------------------------------------------------------------

## A half-played Go game is hours the seed cannot regenerate, so it travels in the file the
## way the inventory does. Checked at the save layer only: that the row goes out whole and
## comes back into a registry that never saw the original.
func _check_games_section() -> void:
	var walker := await _make_walker("Games")
	if walker == null:
		return
	walker.global_position = BURIED_POS
	var inventory := PlayerInventoryScript.new() as PlayerInventory
	var board := GoBoardState.new()
	board.setup(9)
	for vertex: String in ["D4", "F6", "E5"]:
		if not board.try_play(board.next_color, vertex):
			_fail("FAIL the mock match would not play %s" % vertex)
	var games := WorldGamesScript.new() as WorldGames
	games.set_go({
		"board_n": 9,
		"black_human": true,
		"white_human": false,
		"black_rank": "5k",
		"white_rank": "3k",
		"board": board.to_save_dict(),
	})

	var data := GameSaveScript.capture(
		WORLD_SEED, walker, inventory, "Match", null, 0, null, games
	)
	if data.is_empty():
		_fail("FAIL capture produced nothing with a match in progress")
		walker.queue_free()
		return
	if not GameSaveScript.write_named(GAMES_SLOT, data):
		_fail("FAIL could not write the save holding the match")
	var read := GameSaveScript.read_named(GAMES_SLOT)
	if read.is_empty():
		_fail("FAIL the save holding the match read back empty")
		walker.queue_free()
		return

	var restored := WorldGamesScript.new() as WorldGames
	GameSaveScript.apply_games(restored, read)
	if not restored.has_go():
		_fail("FAIL the match did not survive the file")
	else:
		var back := GoBoardState.from_save_dict(restored.go_snapshot().get("board", {}))
		if back == null:
			_fail("FAIL the restored row does not hold a readable board")
		elif Array(back.stones) != Array(board.stones):
			_fail("FAIL the restored board is a different position")
		elif back.next_color != board.next_color:
			_fail("FAIL the restored board hands the move to the wrong colour")
		elif back.move_list.size() != board.move_list.size():
			_fail("FAIL the move list is gone, so KataGo cannot be replayed into the game")

	## A run with nothing going still writes the section, empty. A missing one would have
	## `apply_games` shouting on every load of a save from a player who never sat down.
	var idle := GameSaveScript.capture(WORLD_SEED, walker, inventory, "Idle")
	var idle_games: Variant = idle.get("games", null)
	if typeof(idle_games) != TYPE_DICTIONARY:
		_fail("FAIL a save with no match going has no games section at all")
	elif not (idle_games as Dictionary).is_empty():
		_fail("FAIL a save with no match going carries one anyway: %s" % str(idle_games))
	walker.queue_free()
	print("OK an unfinished match survives capture, the file and apply_games")


# ---------------------------------------------------------------------------
# Slot separation
# ---------------------------------------------------------------------------

func _check_slots_are_separate() -> void:
	var listed := GameSaveScript.list_named()
	var names := PackedStringArray()
	for entry: Dictionary in listed:
		names.append(String(entry["name"]))
	if not names.has(SLOT_NAME):
		_fail("FAIL the named save is missing from the library: %s" % str(names))
	if names.has(GameSaveScript.QUICKSAVE_NAME):
		_fail("FAIL the autosave slot showed up in the named library")

	if not GameSaveScript.has_quicksave():
		_fail("FAIL the quicksave went missing")
	if not GameSaveScript.delete_quicksave():
		_fail("FAIL could not delete the quicksave")
	if GameSaveScript.has_quicksave():
		_fail("FAIL the quicksave survived its own deletion")
	## New Game drops only the autosave; the library the player built is not its business.
	if GameSaveScript.read_named(SLOT_NAME).is_empty():
		_fail("FAIL deleting the quicksave took the named save with it")
	print("OK the autosave slot and the named library are independent")


# ---------------------------------------------------------------------------
# An autosave from an older build
# ---------------------------------------------------------------------------

## Bumping `VERSION` strands the autosave of everyone already playing, and that is the *expected*
## first launch after an update — not a fault to shout about. So the read refuses it, boot moves it
## aside, and the next launch is quiet: no error, no slot in the Load list that cannot be loaded.
func _check_old_format_is_retired() -> void:
	var path := GameSaveScript.quicksave_path()
	var stale := {"version": GameSaveScript.VERSION - 1, "city_seed": WORLD_SEED}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("FAIL could not plant an old-format autosave")
		return
	file.store_string(JSON.stringify(stale, "\t"))
	file.close()

	if not GameSaveScript.has_quicksave():
		_fail("FAIL the planted autosave is not there")
		return
	if not GameSaveScript.read_quicksave().is_empty():
		_fail("FAIL a save from another build was read as if this build wrote it")
		return
	if not GameSaveScript.retire_quicksave():
		_fail("FAIL the old autosave could not be moved aside")
		return
	if GameSaveScript.has_quicksave():
		_fail("FAIL the old autosave is still in the slot, so the next boot trips over it again")
		return
	if not FileAccess.file_exists("%s.bak" % path):
		_fail("FAIL the old autosave was thrown away rather than kept")
		return
	## The retired file must be invisible to the library, or the player gets a slot that refuses.
	for entry: Dictionary in GameSaveScript.list_named():
		if String(entry["name"]).contains(GameSaveScript.QUICKSAVE_NAME):
			_fail("FAIL the retired autosave showed up in the Load list as '%s'" % entry["name"])
			return
	## Nothing to retire is not a failure — most boots have a save they can actually read.
	if GameSaveScript.retire_quicksave():
		_fail("FAIL retiring an empty slot reported that it moved something")
		return
	print("OK an autosave from an older build is refused, kept aside and out of the Load list")


func _wipe_scratch() -> void:
	if not DirAccess.dir_exists_absolute(SCRATCH_DIR):
		return
	var dir := DirAccess.open(SCRATCH_DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		DirAccess.remove_absolute("%s/%s" % [SCRATCH_DIR, file])
