## Play mode, unlocks, tray binds, and carve hardness for one run.
##
## Owned by CityRoot and written into GameSave v3. Sandbox pretends every gated ability is
## unlocked and never depletes district gem budgets; Adventure starts with the blaster alone.
class_name PlayerLoadout
extends RefCounted

const MODE_SANDBOX := "sandbox"
const MODE_ADVENTURE := "adventure"

## Soft=0 is unused for tools (Soft is always carveable). Rock=1 is the starter.
const HARDNESS_ROCK := 1
const HARDNESS_REINFORCED := 2
const HARDNESS_EXOTIC := 3

var mode: String = MODE_SANDBOX
var unlocks: Dictionary = {} ## ability_id → true
var tray: Array[String] = []
## Highest hardness tier the player's tools may carve cleanly.
var hardness_tier: int = HARDNESS_ROCK


func _init() -> void:
	reset_sandbox()


func reset_sandbox() -> void:
	mode = MODE_SANDBOX
	unlocks.clear()
	for id in AbilityRegistry.STARTER_UNLOCKS:
		unlocks[id] = true
	## Sandbox: everything gated is unlocked for assign/fire.
	for def in AbilityRegistry.unlockable_defs():
		unlocks[def.id] = true
	tray = AbilityRegistry.default_sandbox_tray()
	hardness_tier = HARDNESS_EXOTIC


func reset_adventure() -> void:
	mode = MODE_ADVENTURE
	unlocks.clear()
	for id in AbilityRegistry.STARTER_UNLOCKS:
		unlocks[id] = true
	tray = AbilityRegistry.default_adventure_tray()
	hardness_tier = HARDNESS_ROCK


func is_sandbox() -> bool:
	return mode == MODE_SANDBOX


func is_adventure() -> bool:
	return mode == MODE_ADVENTURE


func scores() -> bool:
	return is_adventure()


func uses_gem_budgets() -> bool:
	return is_adventure()


func is_unlocked(ability_id: String) -> bool:
	var def := AbilityRegistry.get_def(ability_id)
	if def == null:
		return false
	if not def.gated:
		return true
	if is_sandbox():
		return true
	return bool(unlocks.get(ability_id, false))


func mark_unlocked(ability_id: String) -> void:
	unlocks[ability_id] = true
	if ability_id == AbilityRegistry.ID_HARDNESS_REINFORCED:
		hardness_tier = maxi(hardness_tier, HARDNESS_REINFORCED)
	elif ability_id == AbilityRegistry.ID_HARDNESS_EXOTIC:
		hardness_tier = maxi(hardness_tier, HARDNESS_EXOTIC)


func slot_at(index: int) -> String:
	if index < 0 or index >= tray.size():
		return ""
	return tray[index]


func set_slot(index: int, ability_id: String) -> void:
	if index < 0 or index >= AbilityRegistry.SLOT_COUNT:
		push_error("PlayerLoadout.set_slot: slot %d is out of range" % index)
		return
	if tray.size() < AbilityRegistry.SLOT_COUNT:
		tray.resize(AbilityRegistry.SLOT_COUNT)
	if not ability_id.is_empty():
		var def := AbilityRegistry.get_def(ability_id)
		if def == null:
			push_error("PlayerLoadout.set_slot: unknown ability '%s'" % ability_id)
			return
		if def.kind == AbilityRegistry.KIND_META:
			push_error("PlayerLoadout.set_slot: '%s' is not a tray verb" % ability_id)
			return
		if not is_unlocked(ability_id):
			push_error("PlayerLoadout.set_slot: '%s' is locked" % ability_id)
			return
	tray[index] = ability_id


func to_save_dict() -> Dictionary:
	var unlock_list: Array[String] = []
	for key: Variant in unlocks.keys():
		if bool(unlocks[key]):
			unlock_list.append(str(key))
	unlock_list.sort()
	var tray_copy: Array[String] = []
	for i in range(AbilityRegistry.SLOT_COUNT):
		tray_copy.append(slot_at(i))
	return {
		"mode": mode,
		"unlocks": unlock_list,
		"tray": tray_copy,
		"hardness_tier": hardness_tier,
	}


func load_save_dict(data: Dictionary) -> void:
	var raw_mode := str(data.get("mode", MODE_SANDBOX))
	if raw_mode != MODE_SANDBOX and raw_mode != MODE_ADVENTURE:
		push_error("PlayerLoadout: unknown mode '%s'" % raw_mode)
		raw_mode = MODE_SANDBOX
	mode = raw_mode
	unlocks.clear()
	var raw_unlocks: Variant = data.get("unlocks", [])
	if typeof(raw_unlocks) == TYPE_ARRAY:
		for entry: Variant in raw_unlocks as Array:
			unlocks[str(entry)] = true
	for id in AbilityRegistry.STARTER_UNLOCKS:
		unlocks[id] = true
	if is_sandbox():
		for def in AbilityRegistry.unlockable_defs():
			unlocks[def.id] = true
	tray.clear()
	tray.resize(AbilityRegistry.SLOT_COUNT)
	var raw_tray: Variant = data.get("tray", [])
	if typeof(raw_tray) == TYPE_ARRAY:
		var arr: Array = raw_tray
		for i in range(AbilityRegistry.SLOT_COUNT):
			tray[i] = str(arr[i]) if i < arr.size() else ""
	else:
		tray = (
			AbilityRegistry.default_sandbox_tray() if is_sandbox()
			else AbilityRegistry.default_adventure_tray()
		)
	hardness_tier = clampi(
		int(data.get("hardness_tier", HARDNESS_ROCK)), HARDNESS_ROCK, HARDNESS_EXOTIC
	)
	if is_unlocked(AbilityRegistry.ID_HARDNESS_EXOTIC):
		hardness_tier = maxi(hardness_tier, HARDNESS_EXOTIC)
	elif is_unlocked(AbilityRegistry.ID_HARDNESS_REINFORCED):
		hardness_tier = maxi(hardness_tier, HARDNESS_REINFORCED)
