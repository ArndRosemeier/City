## Stage 2: play modes, tray/unlocks, hardness tiers, traps, and GameSave v3 loadout.
##
## Run: powershell -File tools\run_test.ps1 test_stage2_powers
extends Node

const GameSaveScript := preload("res://scripts/city/game_save.gd")
const CityWalkerScript := preload("res://scripts/city/city_walker.gd")
const PlayerInventoryScript := preload("res://scripts/city/player_inventory.gd")
const PlayerLoadoutScript := preload("res://scripts/city/player_loadout.gd")
const ArmedTrapScript := preload("res://scripts/city/armed_trap.gd")
const PedAgentScript := preload("res://scripts/city/ped_agent.gd")

const SCRATCH_DIR := "user://test_stage2_powers"
const WORLD_SEED := 4242

var _failed := false


class TestCity:
	extends CityRoot

	func _ready() -> void:
		add_to_group("city_root")


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	GameSaveScript.use_directory(SCRATCH_DIR)
	_wipe_scratch()
	_check_modes_and_unlocks()
	_check_tray_defaults()
	_check_hardness_tiers()
	_check_stomp_unbound()
	await _check_save_loadout_round_trip()
	await _check_trap_holds_ped_and_scores()
	_wipe_scratch()
	GameSaveScript.use_default_directory()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _wipe_scratch() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	if dir.dir_exists("test_stage2_powers"):
		_wipe_dir("user://test_stage2_powers")


func _wipe_dir(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name == "." or name == "..":
			name = d.get_next()
			continue
		var child := path.path_join(name)
		if d.current_is_dir():
			_wipe_dir(child)
			DirAccess.remove_absolute(child)
		else:
			DirAccess.remove_absolute(child)
		name = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)


func _check_modes_and_unlocks() -> void:
	var sand: PlayerLoadout = PlayerLoadoutScript.new() as PlayerLoadout
	sand.reset_sandbox()
	if not sand.is_sandbox() or not sand.is_unlocked(AbilityRegistry.ID_LASER):
		_fail("FAIL sandbox must unlock laser")
	if sand.uses_gem_budgets() or sand.scores():
		_fail("FAIL sandbox must skip budgets and score")

	var adv: PlayerLoadout = PlayerLoadoutScript.new() as PlayerLoadout
	adv.reset_adventure()
	if not adv.is_adventure():
		_fail("FAIL adventure mode flag")
	if not adv.is_unlocked(AbilityRegistry.ID_BLASTER):
		_fail("FAIL adventure starter is blaster")
	if adv.is_unlocked(AbilityRegistry.ID_LASER):
		_fail("FAIL adventure laser starts locked")
	if adv.is_unlocked(AbilityRegistry.ID_STOMP):
		_fail("FAIL adventure stomp starts locked")
	if not adv.uses_gem_budgets() or not adv.scores():
		_fail("FAIL adventure must use budgets and score")

	var city := TestCity.new()
	add_child(city)
	city._loadout = adv
	city._inventory = PlayerInventoryScript.new() as PlayerInventory
	## Laser costs quartz+topaz — underfunded must refuse.
	city._inventory.add(InventoryCatalog.ID_QUARTZ, 2)
	if city.try_unlock_ability(AbilityRegistry.ID_LASER):
		_fail("FAIL unlock should refuse when gems are short")
	city._inventory.add(InventoryCatalog.ID_QUARTZ, 20)
	city._inventory.add(InventoryCatalog.ID_TOPAZ, 10)
	if not city.try_unlock_ability(AbilityRegistry.ID_LASER):
		_fail("FAIL unlock laser with enough gems")
	if not adv.is_unlocked(AbilityRegistry.ID_LASER):
		_fail("FAIL laser unlock flag missing after spend")
	if city._inventory.count_of(InventoryCatalog.ID_QUARTZ) >= 22:
		_fail("FAIL unlock did not spend quartz")
	city.queue_free()
	print("OK modes, starter unlocks, and gem spend")


func _check_tray_defaults() -> void:
	var sand_tray := AbilityRegistry.default_sandbox_tray()
	if sand_tray[AbilityRegistry.SLOT_MOUSE_LMB] != AbilityRegistry.ID_BLASTER:
		_fail("FAIL sandbox LMB is not blaster")
	if sand_tray[AbilityRegistry.SLOT_MOUSE_CTRL] != AbilityRegistry.ID_LASER:
		_fail("FAIL sandbox Ctrl slot is not laser")
	var adv_tray := AbilityRegistry.default_adventure_tray()
	if adv_tray[AbilityRegistry.SLOT_MOUSE_LMB] != AbilityRegistry.ID_BLASTER:
		_fail("FAIL adventure LMB is not blaster")
	if not str(adv_tray[AbilityRegistry.SLOT_MOUSE_CTRL]).is_empty():
		_fail("FAIL adventure Ctrl combat slot should start empty")
	var loadout: PlayerLoadout = PlayerLoadoutScript.new() as PlayerLoadout
	loadout.reset_adventure()
	loadout.mark_unlocked(AbilityRegistry.ID_STOMP)
	loadout.set_slot(AbilityRegistry.SLOT_MOUSE_ALT, AbilityRegistry.ID_STOMP)
	if loadout.slot_at(AbilityRegistry.SLOT_MOUSE_ALT) != AbilityRegistry.ID_STOMP:
		_fail("FAIL could not assign stomp to Alt after unlock")
	loadout.set_slot(0, AbilityRegistry.ID_LASER)
	if loadout.slot_at(0) == AbilityRegistry.ID_LASER:
		_fail("FAIL locked laser must not assign to tray")
	print("OK tray defaults and assign gates")


func _check_hardness_tiers() -> void:
	if int(VoxelMaterial.hardness(VoxelMaterial.STONE)) != int(VoxelMaterial.Hardness.ROCK):
		_fail("FAIL stone should be Rock")
	if int(VoxelMaterial.hardness(VoxelMaterial.CONCRETE)) != int(VoxelMaterial.Hardness.REINFORCED):
		_fail("FAIL concrete should be Reinforced")
	if int(VoxelMaterial.hardness(VoxelMaterial.METEOR_ROCK)) != int(VoxelMaterial.Hardness.EXOTIC):
		_fail("FAIL meteor rock should be Exotic")
	if int(VoxelMaterial.hardness(VoxelMaterial.BEDROCK)) != int(VoxelMaterial.Hardness.NEVER):
		_fail("FAIL bedrock should be Never")
	var loadout: PlayerLoadout = PlayerLoadoutScript.new() as PlayerLoadout
	loadout.reset_adventure()
	if loadout.hardness_tier != PlayerLoadout.HARDNESS_ROCK:
		_fail("FAIL adventure starts at Rock hardness")
	loadout.mark_unlocked(AbilityRegistry.ID_HARDNESS_REINFORCED)
	if loadout.hardness_tier < PlayerLoadout.HARDNESS_REINFORCED:
		_fail("FAIL reinforced unlock did not raise tier")
	loadout.mark_unlocked(AbilityRegistry.ID_HARDNESS_EXOTIC)
	if loadout.hardness_tier < PlayerLoadout.HARDNESS_EXOTIC:
		_fail("FAIL exotic unlock did not raise tier")
	print("OK hardness material map and unlock tiers")


func _check_stomp_unbound() -> void:
	var ctl := PlayerControls.new()
	var bind := ctl.get_binding("stomp")
	if int(bind.get("code", -1)) != int(KEY_NONE):
		_fail("FAIL stomp default bind should be KEY_NONE")
	var ek := InputEventKey.new()
	ek.pressed = true
	ek.keycode = KEY_Q
	ek.physical_keycode = KEY_Q
	if ctl.matches_key_pressed(ek, "stomp"):
		_fail("FAIL Q must not fire stomp after tray migration")
	print("OK stomp is tray-only (Q unbound)")


func _check_save_loadout_round_trip() -> void:
	var walker: CityWalker = CityWalkerScript.new() as CityWalker
	walker.name = "SaveWalker"
	add_child(walker)
	walker.set_physics_process(false)
	walker.set_process(false)
	await get_tree().process_frame
	if walker.get_proportions() == null:
		_fail("FAIL walker came up without proportions")
		walker.queue_free()
		return
	walker.global_position = Vector3(12.0, 4.0, -8.0)
	var inventory: PlayerInventory = PlayerInventoryScript.new() as PlayerInventory
	if inventory.add(InventoryCatalog.ID_DIAMOND, 2) != 0:
		_fail("FAIL could not stock diamond")
	var loadout: PlayerLoadout = PlayerLoadoutScript.new() as PlayerLoadout
	loadout.reset_adventure()
	loadout.mark_unlocked(AbilityRegistry.ID_LASER)
	loadout.mark_unlocked(AbilityRegistry.ID_HARDNESS_REINFORCED)
	loadout.set_slot(AbilityRegistry.SLOT_MOUSE_CTRL, AbilityRegistry.ID_LASER)
	var data := GameSaveScript.capture(
		WORLD_SEED, walker, inventory, "Stage2", null, 75, loadout
	)
	if data.is_empty():
		_fail("FAIL capture empty")
		walker.queue_free()
		return
	if int(data.get("version", 0)) != GameSaveScript.VERSION:
		_fail("FAIL save version want %d" % GameSaveScript.VERSION)
	if str(data.get("mode", "")) != PlayerLoadout.MODE_ADVENTURE:
		_fail("FAIL save mode missing")
	if GameSaveScript.saved_score(data) != 75:
		_fail("FAIL save score")
	var restored: PlayerLoadout = PlayerLoadoutScript.new() as PlayerLoadout
	GameSaveScript.apply_loadout(restored, data)
	if not restored.is_adventure():
		_fail("FAIL restored mode")
	if not restored.is_unlocked(AbilityRegistry.ID_LASER):
		_fail("FAIL restored laser unlock")
	if restored.slot_at(AbilityRegistry.SLOT_MOUSE_CTRL) != AbilityRegistry.ID_LASER:
		_fail("FAIL restored tray slot")
	if restored.hardness_tier < PlayerLoadout.HARDNESS_REINFORCED:
		_fail("FAIL restored hardness tier")
	walker.queue_free()
	print("OK GameSave v3 loadout round-trip")


func _check_trap_holds_ped_and_scores() -> void:
	var city := TestCity.new()
	add_child(city)
	city._loadout = PlayerLoadoutScript.new() as PlayerLoadout
	city._loadout.reset_adventure()
	city._player_score = 0

	var ped: PedAgent = PedAgentScript.new() as PedAgent
	ped.name = "TrapPed"
	add_child(ped)
	ped.global_position = Vector3(1.0, 0.0, 0.0)
	ped.begin_trap_hold(ArmedTrap.HOLD_SEC)
	if not ped.is_trap_held():
		_fail("FAIL ped should be trap-held")

	var undead := CharacterBody3D.new()
	undead.name = "FakeUndead"
	undead.add_to_group("undead")
	add_child(undead)
	city._on_trap_triggered(undead)
	if city.get_player_score() != AbilityRegistry.TRAP_HOSTILE_SCORE:
		_fail(
			"FAIL adventure hostile trap score want %d got %d"
			% [AbilityRegistry.TRAP_HOSTILE_SCORE, city.get_player_score()]
		)
	city._on_trap_triggered(ped)
	if city.get_player_score() != AbilityRegistry.TRAP_HOSTILE_SCORE:
		_fail("FAIL trapping a ped must not add score")

	city._loadout.reset_sandbox()
	city._player_score = 10
	city._on_trap_triggered(undead)
	if city.get_player_score() != 10:
		_fail("FAIL sandbox must not write trap score")

	ped.queue_free()
	undead.queue_free()
	city.queue_free()
	print("OK trap hold + hostile score gating")
