## Every assignable tray entry: weapons, powers, consumable uses, and free builds.
##
## "Unlocked" means may be assigned. Sandbox treats every gated combat/power id as unlocked;
## Adventure starts with `blaster` and spends gems for the rest. Builds and consumables wait on
## cookbook recipes (see PlayerLoadout.knows_build_recipe / knows_consumable_recipe).
##
## Authored ability rows + balance constants live in `assets/gamedata.json` via GameData.
## Build tray entries are still registered from BuildCatalog (also GameData-backed).
class_name AbilityRegistry
extends RefCounted

const GameDataScript := preload("res://scripts/city/game_data.gd")

const SLOT_COUNT := 9
## F1–F6 then LMB, Ctrl+LMB, Alt+LMB.
const SLOT_MOUSE_LMB := 6
const SLOT_MOUSE_CTRL := 7
const SLOT_MOUSE_ALT := 8

const ID_BLASTER := "blaster"
const ID_LASER := "laser"
const ID_CHARGED_BLAST := "charged_blast"
const ID_STOMP := "stomp"
const ID_SHIELD := "shield"
const ID_GROW := "grow"
const ID_SHRINK := "shrink"
const ID_MINION := "minion"
const ID_DISTRICT_HOP := "district_hop"
const ID_TETRIS := "tetris"
const ID_USE_TRAP := "use_trap"
const ID_USE_BOOST_SPEED := "use_boost_speed"
const ID_USE_BOOST_REGEN := "use_boost_regen"
const ID_HARDNESS_REINFORCED := "hardness_reinforced"
const ID_HARDNESS_EXOTIC := "hardness_exotic"

const KIND_WEAPON := "weapon"
const KIND_POWER := "power"
const KIND_BUILD := "build"
const KIND_CONSUMABLE := "consumable"
const KIND_META := "meta"

## Filled from GameData.ability_constants on ensure_loaded.
static var STARTER_UNLOCKS: Array[String] = [ID_BLASTER]
static var TRAP_HOSTILE_SCORE: int = 25
static var BOOST_DURATION_SEC: float = 20.0
static var GROW_SHRINK_DURATION_SEC: float = 25.0
static var SHIELD_DRAIN_PER_SEC: float = 8.0
static var MINION_MAX: int = 1
static var MINION_DURATION_SEC: float = 60.0
static var _default_sandbox_builds: Array[String] = []


class AbilityDef:
	extends RefCounted
	var id: String = ""
	var display_name: String = ""
	var kind: String = KIND_POWER
	## Inventory gem ids → count. Empty = free (builds, starter).
	var unlock_cost: Dictionary = {}
	var energy_cost: float = 0.0
	## When true, Adventure must unlock before assign/fire. Builds are false.
	var gated: bool = true
	var hint: String = ""


static var _by_id: Dictionary = {}
static var _order: Array[String] = []
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_by_id.clear()
	_order.clear()
	var constants: Dictionary = GameDataScript.ability_constants()
	STARTER_UNLOCKS.clear()
	var starters: Variant = constants.get("starter_unlocks", [ID_BLASTER])
	if typeof(starters) == TYPE_ARRAY:
		for s: Variant in starters:
			STARTER_UNLOCKS.append(str(s))
	TRAP_HOSTILE_SCORE = int(constants.get("trap_hostile_score", 25))
	BOOST_DURATION_SEC = float(constants.get("boost_duration_sec", 20.0))
	GROW_SHRINK_DURATION_SEC = float(constants.get("grow_shrink_duration_sec", 25.0))
	SHIELD_DRAIN_PER_SEC = float(constants.get("shield_drain_per_sec", 8.0))
	MINION_MAX = int(constants.get("minion_max", 1))
	MINION_DURATION_SEC = float(constants.get("minion_duration_sec", 60.0))
	_default_sandbox_builds.clear()
	var builds_raw: Variant = constants.get("default_sandbox_builds", [])
	if typeof(builds_raw) == TYPE_ARRAY:
		for b: Variant in builds_raw:
			_default_sandbox_builds.append(str(b))

	var abilities: Dictionary = GameDataScript.abilities()
	var ids: Array = abilities.keys()
	ids.sort()
	## Keep a stable authoring order: weapons/powers first as listed in gamedata insertion
	## order is lost after JSON parse — use the key order from the file via unsorted keys
	## then append builds. Prefer the order keys appear in the raw document.
	ids = _ability_ids_in_doc_order(abilities)
	for id_v: Variant in ids:
		var id := str(id_v)
		var row: Dictionary = abilities[id] as Dictionary
		var cost: Dictionary = {}
		var cost_raw: Variant = row.get("unlock_cost", {})
		if typeof(cost_raw) == TYPE_DICTIONARY:
			cost = (cost_raw as Dictionary).duplicate()
		_reg(
			id,
			str(row.get("display_name", id)),
			str(row.get("kind", KIND_POWER)),
			cost,
			float(row.get("energy_cost", 0.0)),
			bool(row.get("gated", true)),
			str(row.get("hint", ""))
		)
	for recipe: BuildCatalog.Recipe in BuildCatalog.all():
		_reg(recipe.id, recipe.display_name, KIND_BUILD, {}, 0.0, false, recipe.hint)


static func _ability_ids_in_doc_order(abilities: Dictionary) -> Array:
	## JSON objects do not guarantee order in Godot; sort for determinism.
	var ids: Array = abilities.keys()
	ids.sort()
	return ids


static func _reg(
	id: String,
	display_name: String,
	kind: String,
	cost: Dictionary,
	energy: float,
	gated: bool,
	hint: String
) -> void:
	var def := AbilityDef.new()
	def.id = id
	def.display_name = display_name
	def.kind = kind
	def.unlock_cost = cost
	def.energy_cost = energy
	def.gated = gated
	def.hint = hint
	_by_id[id] = def
	_order.append(id)


static func get_def(ability_id: String) -> AbilityDef:
	ensure_loaded()
	if not _by_id.has(ability_id):
		return null
	return _by_id[ability_id] as AbilityDef


static func all_defs() -> Array[AbilityDef]:
	ensure_loaded()
	var out: Array[AbilityDef] = []
	for id in _order:
		out.append(_by_id[id] as AbilityDef)
	return out


static func assignable_defs() -> Array[AbilityDef]:
	## Meta hardness unlocks are not tray verbs — they only appear in the unlock list.
	var out: Array[AbilityDef] = []
	for def in all_defs():
		if def.kind == KIND_META:
			continue
		out.append(def)
	return out


static func unlockable_defs() -> Array[AbilityDef]:
	var out: Array[AbilityDef] = []
	for def in all_defs():
		if def.gated and not def.unlock_cost.is_empty():
			out.append(def)
	return out


## Craft recipe that teaches a consumable tray verb. Empty when `ability_id` is not a consumable.
static func craft_recipe_for_consumable(ability_id: String) -> String:
	match ability_id:
		ID_USE_TRAP:
			return InventoryCatalog.RECIPE_TRAP
		ID_USE_BOOST_SPEED:
			return InventoryCatalog.RECIPE_BOOST_SPEED
		ID_USE_BOOST_REGEN:
			return InventoryCatalog.RECIPE_BOOST_REGEN
		_:
			return ""


static func default_sandbox_tray() -> Array[String]:
	ensure_loaded()
	var slots: Array[String] = []
	slots.resize(SLOT_COUNT)
	for i in range(SLOT_COUNT):
		slots[i] = ""
	for i in range(mini(6, _default_sandbox_builds.size())):
		slots[i] = _default_sandbox_builds[i]
	slots[SLOT_MOUSE_LMB] = ID_BLASTER
	slots[SLOT_MOUSE_CTRL] = ID_LASER
	slots[SLOT_MOUSE_ALT] = ID_CHARGED_BLAST
	return slots


static func default_adventure_tray() -> Array[String]:
	ensure_loaded()
	var slots: Array[String] = []
	slots.resize(SLOT_COUNT)
	for i in range(SLOT_COUNT):
		slots[i] = ""
	## Optional free starter stamps on F-keys; discovery builds stay off until learned.
	for i in range(mini(6, _default_sandbox_builds.size())):
		slots[i] = _default_sandbox_builds[i]
	slots[SLOT_MOUSE_LMB] = ID_BLASTER
	return slots


static func mouse_slot_for_action(action: String) -> int:
	match action:
		"beam":
			return SLOT_MOUSE_LMB
		"laser":
			return SLOT_MOUSE_CTRL
		"fire":
			return SLOT_MOUSE_ALT
		_:
			return -1


static func slot_label(index: int) -> String:
	match index:
		SLOT_MOUSE_LMB:
			return "LMB"
		SLOT_MOUSE_CTRL:
			return "Ctrl"
		SLOT_MOUSE_ALT:
			return "Alt"
		_:
			if index >= 0 and index < 6:
				return "F%d" % (index + 1)
			return "?"
