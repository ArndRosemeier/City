## Play mode, unlocks, tray binds, and carve hardness for one run.
##
## Owned by CityRoot and written into GameSave v3. Sandbox pretends every gated ability is
## unlocked and never depletes district gem budgets; Adventure starts from
## AbilityRegistry.STARTER_UNLOCKS (authored in gamedata ability_constants.starter_unlocks).
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
## recipe_id → true. Adventure learns these from world pickups; Sandbox knows the lot.
var known_recipes: Dictionary = {}
## site_id → true for every recipe pickup this run has already collected, so a district that
## streams back in cannot pay the same landmark twice.
var looted_recipe_sites: Dictionary = {}


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
	learn_every_recipe()
	looted_recipe_sites.clear()


func reset_adventure() -> void:
	mode = MODE_ADVENTURE
	unlocks.clear()
	hardness_tier = HARDNESS_ROCK
	## Cookbook starts empty, then starters grant their schematics so the Unlock list can show them.
	known_recipes.clear()
	looted_recipe_sites.clear()
	for id in AbilityRegistry.STARTER_UNLOCKS:
		grant_starter(id)
	tray = AbilityRegistry.default_adventure_tray()


## Starter kit entry: unlock + teach the schematic (inventory Unlock list is schematic-gated).
func grant_starter(ability_id: String) -> void:
	mark_unlocked(ability_id)
	var schematic_id := InventoryCatalog.schematic_id_for_ability(ability_id)
	if InventoryCatalog.has_recipe(schematic_id):
		known_recipes[schematic_id] = true


func is_sandbox() -> bool:
	return mode == MODE_SANDBOX


func is_adventure() -> bool:
	return mode == MODE_ADVENTURE


func scores() -> bool:
	return is_adventure()


func uses_gem_budgets() -> bool:
	return is_adventure()


func learn_every_recipe() -> void:
	known_recipes.clear()
	for recipe_id in InventoryCatalog.all_recipe_ids():
		known_recipes[recipe_id] = true


func knows_recipe(recipe_id: String) -> bool:
	if is_sandbox():
		return true
	return bool(known_recipes.get(recipe_id, false))


## True when this call is what taught it — a second pickup of the same recipe reports false so
## the caller can fall back to a gem.
func learn_recipe(recipe_id: String) -> bool:
	if not InventoryCatalog.has_recipe(recipe_id):
		push_error("PlayerLoadout.learn_recipe: unknown recipe '%s'" % recipe_id)
		return false
	if bool(known_recipes.get(recipe_id, false)):
		return false
	known_recipes[recipe_id] = true
	return true


## Sorted, so picking "one of the missing" from a site seed lands on the same recipe every time
## the same run re-rolls it.
func missing_recipe_ids() -> Array[String]:
	var out: Array[String] = []
	if is_sandbox():
		return out
	for recipe_id in InventoryCatalog.all_recipe_ids():
		if not bool(known_recipes.get(recipe_id, false)):
			out.append(recipe_id)
	return out


## Does the player know how to build this power? Craft-gating only bites in Adventure.
func knows_ability_schematic(ability_id: String) -> bool:
	if is_sandbox():
		return true
	return knows_recipe(InventoryCatalog.schematic_id_for_ability(ability_id))


func is_recipe_site_looted(site_id: String) -> bool:
	return bool(looted_recipe_sites.get(site_id, false))


func mark_recipe_site_looted(site_id: String) -> void:
	if site_id.is_empty():
		push_error("PlayerLoadout.mark_recipe_site_looted: empty site id")
		return
	looted_recipe_sites[site_id] = true


func is_unlocked(ability_id: String) -> bool:
	var def := AbilityRegistry.get_def(ability_id)
	if def == null:
		return false
	## Discovery-gated builds stay off the assign menu until a scroll teaches them.
	if def.kind == AbilityRegistry.KIND_BUILD:
		return knows_build_recipe(ability_id)
	if not def.gated:
		return true
	if is_sandbox():
		return true
	return bool(unlocks.get(ability_id, false))


## Free stamps are always known; `requires_recipe` builds need the matching cookbook entry.
func knows_build_recipe(ability_id: String) -> bool:
	if not BuildCatalog.has_id(ability_id):
		return false
	var build := BuildCatalog.by_id(ability_id)
	if build == null:
		return false
	if not build.requires_recipe:
		return true
	return knows_recipe(ability_id)


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
	var recipe_list: Array[String] = []
	for key: Variant in known_recipes.keys():
		if bool(known_recipes[key]):
			recipe_list.append(str(key))
	recipe_list.sort()
	var site_list: Array[String] = []
	for key: Variant in looted_recipe_sites.keys():
		if bool(looted_recipe_sites[key]):
			site_list.append(str(key))
	site_list.sort()
	return {
		"mode": mode,
		"unlocks": unlock_list,
		"tray": tray_copy,
		"hardness_tier": hardness_tier,
		"recipes": recipe_list,
		"recipe_sites": site_list,
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
	known_recipes.clear()
	var raw_recipes: Variant = data.get("recipes", [])
	if typeof(raw_recipes) == TYPE_ARRAY:
		for entry: Variant in raw_recipes as Array:
			known_recipes[str(entry)] = true
	if is_sandbox():
		learn_every_recipe()
	## Starters always keep their schematics visible in the Unlock list.
	for id in AbilityRegistry.STARTER_UNLOCKS:
		var schematic_id := InventoryCatalog.schematic_id_for_ability(id)
		if InventoryCatalog.has_recipe(schematic_id):
			known_recipes[schematic_id] = true
	looted_recipe_sites.clear()
	var raw_sites: Variant = data.get("recipe_sites", [])
	if typeof(raw_sites) == TYPE_ARRAY:
		for entry: Variant in raw_sites as Array:
			looted_recipe_sites[str(entry)] = true
	hardness_tier = clampi(
		int(data.get("hardness_tier", HARDNESS_ROCK)), HARDNESS_ROCK, HARDNESS_EXOTIC
	)
	if is_unlocked(AbilityRegistry.ID_HARDNESS_EXOTIC):
		hardness_tier = maxi(hardness_tier, HARDNESS_EXOTIC)
	elif is_unlocked(AbilityRegistry.ID_HARDNESS_REINFORCED):
		hardness_tier = maxi(hardness_tier, HARDNESS_REINFORCED)
