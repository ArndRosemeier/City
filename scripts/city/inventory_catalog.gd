## Catalog of inventory items and craft recipes. Gems map 1:1 from VoxelMaterial.GEM_*.
##
## Authored rows live in `assets/gamedata.json` via GameData. Schematics stay derived from
## AbilityRegistry so a new gated power always has a discovery recipe.
class_name InventoryCatalog
extends RefCounted

const GameDataScript := preload("res://scripts/city/game_data.gd")

const STACK_DEFAULT := 99
const SLOT_COUNT := 25

const ID_QUARTZ := "gem_quartz"
const ID_AMBER := "gem_amber"
const ID_TOPAZ := "gem_topaz"
const ID_SAPPHIRE := "gem_sapphire"
const ID_EMERALD := "gem_emerald"
const ID_DIAMOND := "gem_diamond"
const ID_TRAP := "trap"
const ID_BOOST_SPEED := "boost_speed"
const ID_BOOST_REGEN := "boost_regen"

const RECIPE_TRAP := "trap_from_quartz"
const RECIPE_BOOST_SPEED := "boost_speed_craft"
const RECIPE_BOOST_REGEN := "boost_regen_craft"

const RECIPE_KIND_CRAFT := "craft"
const RECIPE_KIND_SCHEMATIC := "schematic"
const SCHEMATIC_PREFIX := "schematic_"


class ItemDef:
	extends RefCounted
	var id: String = ""
	var display_name: String = ""
	var stack_max: int = STACK_DEFAULT
	## VoxelMaterial.GEM_* when this row is a collected gem; -1 otherwise.
	var gem_mat_id: int = -1
	## True for craft outputs that use the inward-pulse trap look.
	var is_trap: bool = false
	## Drinkable temporary boost.
	var is_boost: bool = false


class Recipe:
	extends RefCounted
	var id: String = ""
	var display_name: String = ""
	## item_id → count consumed. Empty on schematics.
	var inputs: Dictionary = {}
	var output_id: String = ""
	var output_count: int = 1
	var kind: String = RECIPE_KIND_CRAFT
	## AbilityRegistry id this schematic makes purchasable. Empty on craft recipes.
	var unlocks_ability: String = ""


static var _items: Dictionary = {}
static var _recipes: Dictionary = {}
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_items.clear()
	_recipes.clear()
	var items_doc: Dictionary = GameDataScript.items()
	for id_v: Variant in items_doc.keys():
		var id := str(id_v)
		var row: Dictionary = items_doc[id] as Dictionary
		var item := ItemDef.new()
		item.id = id
		item.display_name = str(row.get("display_name", id))
		item.stack_max = int(row.get("stack_max", STACK_DEFAULT))
		item.gem_mat_id = int(row.get("gem_mat_id", -1))
		var flags: Variant = row.get("flags", [])
		if typeof(flags) == TYPE_ARRAY:
			for flag_v: Variant in flags:
				match str(flag_v):
					"trap":
						item.is_trap = true
					"boost":
						item.is_boost = true
					"gem":
						pass
					_:
						push_error("InventoryCatalog: unknown item flag '%s' on %s" % [flag_v, id])
		_items[id] = item

	var crafts: Dictionary = GameDataScript.craft_recipes()
	for id_v: Variant in crafts.keys():
		var id := str(id_v)
		var row: Dictionary = crafts[id] as Dictionary
		var recipe := Recipe.new()
		recipe.id = id
		recipe.display_name = str(row.get("display_name", id))
		recipe.kind = RECIPE_KIND_CRAFT
		recipe.output_id = str(row.get("output_id", ""))
		recipe.output_count = int(row.get("output_count", 1))
		var inputs_raw: Variant = row.get("inputs", {})
		if typeof(inputs_raw) == TYPE_DICTIONARY:
			recipe.inputs = (inputs_raw as Dictionary).duplicate()
		_recipes[id] = recipe
	_register_schematics()


## One schematic per gem-priced ability, derived from the registry so a new power cannot ship
## without the recipe that gates it.
static func _register_schematics() -> void:
	for def in AbilityRegistry.unlockable_defs():
		var recipe := Recipe.new()
		recipe.id = schematic_id_for_ability(def.id)
		recipe.display_name = def.display_name
		recipe.kind = RECIPE_KIND_SCHEMATIC
		recipe.unlocks_ability = def.id
		_recipes[recipe.id] = recipe


static func item(item_id: String) -> ItemDef:
	ensure_loaded()
	if not _items.has(item_id):
		push_error("InventoryCatalog: unknown item '%s'" % item_id)
		return null
	return _items[item_id] as ItemDef


static func has_item(item_id: String) -> bool:
	ensure_loaded()
	return _items.has(item_id)


## Everything the game can put in a slot. Sorted, so a coverage sweep over the catalog reports
## the same order every run.
static func all_item_ids() -> Array[String]:
	ensure_loaded()
	var out: Array[String] = []
	for key: Variant in _items.keys():
		out.append(str(key))
	out.sort()
	return out


static func recipe(recipe_id: String) -> Recipe:
	ensure_loaded()
	if not _recipes.has(recipe_id):
		push_error("InventoryCatalog: unknown recipe '%s'" % recipe_id)
		return null
	return _recipes[recipe_id] as Recipe


static func has_recipe(recipe_id: String) -> bool:
	ensure_loaded()
	return _recipes.has(recipe_id)


static func all_recipes() -> Array[Recipe]:
	ensure_loaded()
	var out: Array[Recipe] = []
	for key in _recipes.keys():
		out.append(_recipes[key] as Recipe)
	return out


## Recipes that spend items and hand one back — the Construct list.
static func craft_recipes() -> Array[Recipe]:
	var out: Array[Recipe] = []
	for r in all_recipes():
		if r.kind == RECIPE_KIND_CRAFT:
			out.append(r)
	return out


## Recipes that only make a power purchasable — the Unlock list.
static func schematic_recipes() -> Array[Recipe]:
	var out: Array[Recipe] = []
	for r in all_recipes():
		if r.kind == RECIPE_KIND_SCHEMATIC:
			out.append(r)
	return out


## Stable ordering, so a seeded pick of "one recipe the player is missing" replays.
static func all_recipe_ids() -> Array[String]:
	var out: Array[String] = []
	for r in all_recipes():
		out.append(r.id)
	out.sort()
	return out


static func schematic_id_for_ability(ability_id: String) -> String:
	return SCHEMATIC_PREFIX + ability_id


static func display_name(item_id: String) -> String:
	var def := item(item_id)
	if def == null:
		return item_id
	return def.display_name


static func item_id_for_gem(mat_id: int) -> String:
	ensure_loaded()
	for key: Variant in _items.keys():
		var def: ItemDef = _items[key] as ItemDef
		if def.gem_mat_id == mat_id:
			return def.id
	push_error("InventoryCatalog.item_id_for_gem: no item for mat %d" % mat_id)
	return ""
