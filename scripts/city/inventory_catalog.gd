## Catalog of inventory items and craft recipes. Gems map 1:1 from VoxelMaterial.GEM_*.
class_name InventoryCatalog
extends RefCounted

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

## A craft recipe spends inputs and yields an item. A schematic yields nothing on its own — it
## is the knowledge an Adventure run needs before the matching power may be bought at all, and
## the gem price stays on `AbilityRegistry`.
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
	_register_gem(ID_QUARTZ, "Quartz", VoxelMaterial.GEM_QUARTZ)
	_register_gem(ID_AMBER, "Amber", VoxelMaterial.GEM_AMBER)
	_register_gem(ID_TOPAZ, "Topaz", VoxelMaterial.GEM_TOPAZ)
	_register_gem(ID_SAPPHIRE, "Sapphire", VoxelMaterial.GEM_SAPPHIRE)
	_register_gem(ID_EMERALD, "Emerald", VoxelMaterial.GEM_EMERALD)
	_register_gem(ID_DIAMOND, "Diamond", VoxelMaterial.GEM_DIAMOND)
	var trap := ItemDef.new()
	trap.id = ID_TRAP
	trap.display_name = "Trap"
	trap.stack_max = STACK_DEFAULT
	trap.is_trap = true
	_items[ID_TRAP] = trap
	_register_boost(ID_BOOST_SPEED, "Speed tonic")
	_register_boost(ID_BOOST_REGEN, "Regen tonic")

	_register_recipe(RECIPE_TRAP, "Trap", {ID_QUARTZ: 5}, ID_TRAP, 1)
	_register_recipe(
		RECIPE_BOOST_SPEED, "Speed tonic",
		{ID_AMBER: 3, ID_QUARTZ: 4}, ID_BOOST_SPEED, 1
	)
	_register_recipe(
		RECIPE_BOOST_REGEN, "Regen tonic",
		{ID_TOPAZ: 3, ID_AMBER: 2}, ID_BOOST_REGEN, 1
	)
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


static func _register_gem(item_id: String, display_name: String, mat_id: int) -> void:
	var item := ItemDef.new()
	item.id = item_id
	item.display_name = display_name
	item.gem_mat_id = mat_id
	_items[item_id] = item


static func _register_boost(item_id: String, display_name: String) -> void:
	var item := ItemDef.new()
	item.id = item_id
	item.display_name = display_name
	item.is_boost = true
	_items[item_id] = item


static func _register_recipe(
	recipe_id: String,
	display_name: String,
	inputs: Dictionary,
	output_id: String,
	output_count: int
) -> void:
	var recipe := Recipe.new()
	recipe.id = recipe_id
	recipe.display_name = display_name
	recipe.inputs = inputs
	recipe.output_id = output_id
	recipe.output_count = output_count
	_recipes[recipe_id] = recipe


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


static func has_recipe(recipe_id: String) -> bool:
	ensure_loaded()
	return _recipes.has(recipe_id)


static func item_id_for_gem(mat_id: int) -> String:
	ensure_loaded()
	if not VoxelMaterial.is_gem(mat_id):
		push_error("InventoryCatalog.item_id_for_gem: not a gem id %d" % mat_id)
		return ""
	match mat_id:
		VoxelMaterial.GEM_QUARTZ:
			return ID_QUARTZ
		VoxelMaterial.GEM_AMBER:
			return ID_AMBER
		VoxelMaterial.GEM_TOPAZ:
			return ID_TOPAZ
		VoxelMaterial.GEM_SAPPHIRE:
			return ID_SAPPHIRE
		VoxelMaterial.GEM_EMERALD:
			return ID_EMERALD
		VoxelMaterial.GEM_DIAMOND:
			return ID_DIAMOND
		_:
			push_error("InventoryCatalog.item_id_for_gem: unmapped gem id %d" % mat_id)
			return ""


static func display_name(item_id: String) -> String:
	var def := item(item_id)
	if def == null:
		return item_id
	return def.display_name
