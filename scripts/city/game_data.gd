## Sole runtime reader of `assets/gamedata.json`.
##
## Every catalog / table (combat, items, recipes, districts, abilities, Mandelbrot spots,
## discovery chances) goes through this type so the on-disk shape can change in one place.
## Call sites use the typed facades (`CombatTable`, `InventoryCatalog`, …); those facades
## must not open JSON themselves.
class_name GameData
extends RefCounted

const PATH := "res://assets/gamedata.json"

## DistrictTheme display keys in `district_gems.theme_totals` → theme id.
const THEME_NAME_TO_ID: Dictionary = {
	"core_highrise": 0,
	"old_town": 1,
	"waterfront_industrial": 2,
	"garden_residential": 3,
	"civic_quarter": 4,
	"hill": 5,
	"graveyard": 6,
	"lake": 7,
	"castle": 8,
	"fractal": 9,
	"arena": 10,
	"zoo": 11,
	"gaming": 12,
	"siege": 13,
}

static var _loaded: bool = false
static var _doc: Dictionary = {}


static func reload() -> void:
	_loaded = false
	_doc.clear()
	ensure_loaded()


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(PATH):
		push_error("GameData: missing %s" % PATH)
		assert(false, "GameData: missing gamedata.json")
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("GameData: cannot open %s" % PATH)
		assert(false, "GameData: open failed")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("GameData: %s root must be an object" % PATH)
		assert(false, "GameData: bad root")
		return
	_doc = parsed


static func raw() -> Dictionary:
	ensure_loaded()
	return _doc


static func _section(key: String) -> Dictionary:
	ensure_loaded()
	var raw: Variant = _doc.get(key, null)
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("GameData: '%s' must be an object" % key)
		assert(false, "GameData: missing section")
		return {}
	return raw


static func _section_array(key: String) -> Array:
	ensure_loaded()
	var raw: Variant = _doc.get(key, null)
	if typeof(raw) != TYPE_ARRAY:
		push_error("GameData: '%s' must be an array" % key)
		assert(false, "GameData: missing array section")
		return []
	return raw


# --- Combat -----------------------------------------------------------------

static func attacks() -> Dictionary:
	return _section("attacks")


static func auras() -> Dictionary:
	return _section("auras")


static func behaviours() -> Dictionary:
	return _section("behaviours")


static func templates() -> Dictionary:
	return _section("templates")


static func monsters_array() -> Array:
	return _section_array("monsters")


static func attack(id: String) -> Dictionary:
	var m := attacks()
	if not m.has(id):
		push_error("GameData.attack: unknown '%s'" % id)
		assert(false, "GameData: unknown attack")
		return {}
	return m[id] as Dictionary


static func behaviour(id: String) -> Dictionary:
	var m := behaviours()
	if not m.has(id):
		push_error("GameData.behaviour: unknown '%s'" % id)
		assert(false, "GameData: unknown behaviour")
		return {}
	return m[id] as Dictionary


static func template(id: String) -> Dictionary:
	var m := templates()
	if not m.has(id):
		push_error("GameData.template: unknown '%s'" % id)
		assert(false, "GameData: unknown template")
		return {}
	return m[id] as Dictionary


# --- Items / craft / build --------------------------------------------------

static func items() -> Dictionary:
	return _section("items")


static func craft_recipes() -> Dictionary:
	return _section("craft_recipes")


static func build_recipes() -> Dictionary:
	return _section("build_recipes")


static func item(id: String) -> Dictionary:
	var m := items()
	if not m.has(id):
		push_error("GameData.item: unknown '%s'" % id)
		assert(false, "GameData: unknown item")
		return {}
	return m[id] as Dictionary


static func craft_recipe(id: String) -> Dictionary:
	var m := craft_recipes()
	if not m.has(id):
		push_error("GameData.craft_recipe: unknown '%s'" % id)
		assert(false, "GameData: unknown craft recipe")
		return {}
	return m[id] as Dictionary


static func build_recipe(id: String) -> Dictionary:
	var m := build_recipes()
	if not m.has(id):
		push_error("GameData.build_recipe: unknown '%s'" % id)
		assert(false, "GameData: unknown build recipe")
		return {}
	return m[id] as Dictionary


# --- District gems ----------------------------------------------------------

static func district_gems() -> Dictionary:
	return _section("district_gems")


static func theme_gem_total(theme_id: int) -> int:
	var totals: Dictionary = district_gems().get("theme_totals", {}) as Dictionary
	for name: Variant in THEME_NAME_TO_ID.keys():
		if int(THEME_NAME_TO_ID[name]) == theme_id:
			return int(totals.get(str(name), 0))
	push_error("GameData.theme_gem_total: unknown theme id %d" % theme_id)
	return 0


static func gem_rarity_weight(item_id: String) -> int:
	var weights: Dictionary = district_gems().get("rarity_weights", {}) as Dictionary
	if not weights.has(item_id):
		push_error("GameData.gem_rarity_weight: unknown '%s'" % item_id)
		return 0
	return int(weights[item_id])


# --- Abilities --------------------------------------------------------------

static func abilities() -> Dictionary:
	return _section("abilities")


static func ability_constants() -> Dictionary:
	return _section("ability_constants")


# --- Monster Zoo ------------------------------------------------------------

## Forever-war tuning: cloak length, plate damage cadence, spawn pressure and caps.
static func zoo() -> Dictionary:
	return _section("zoo")


static func zoo_float(key: String) -> float:
	var sec := zoo()
	if not sec.has(key):
		push_error("GameData.zoo_float: missing 'zoo.%s'" % key)
		assert(false, "GameData: missing zoo constant")
		return 0.0
	return float(sec[key])


static func zoo_int(key: String) -> int:
	var sec := zoo()
	if not sec.has(key):
		push_error("GameData.zoo_int: missing 'zoo.%s'" % key)
		assert(false, "GameData: missing zoo constant")
		return 0
	return int(sec[key])


# --- Siege Quarter ----------------------------------------------------------

## Pot stake, Lodestone HP, wave growth, spawn cadence and source factions.
static func siege() -> Dictionary:
	return _section("siege")


static func siege_float(key: String) -> float:
	var sec := siege()
	if not sec.has(key):
		push_error("GameData.siege_float: missing 'siege.%s'" % key)
		assert(false, "GameData: missing siege constant")
		return 0.0
	return float(sec[key])


static func siege_int(key: String) -> int:
	var sec := siege()
	if not sec.has(key):
		push_error("GameData.siege_int: missing 'siege.%s'" % key)
		assert(false, "GameData: missing siege constant")
		return 0
	return int(sec[key])


## Tower catalogue for the Siege Quarter (`siege_towers` section).
static func siege_towers() -> Dictionary:
	return _section("siege_towers")


# --- Graveyard crypt undead station ----------------------------------------

## Chapel-crypt forever-war pad: interval, pressure, alive cap, faction roster.
static func crypt() -> Dictionary:
	return _section("crypt")


static func crypt_float(key: String) -> float:
	var sec := crypt()
	if not sec.has(key):
		push_error("GameData.crypt_float: missing 'crypt.%s'" % key)
		assert(false, "GameData: missing crypt constant")
		return 0.0
	return float(sec[key])


static func crypt_int(key: String) -> int:
	var sec := crypt()
	if not sec.has(key):
		push_error("GameData.crypt_int: missing 'crypt.%s'" % key)
		assert(false, "GameData: missing crypt constant")
		return 0
	return int(sec[key])


static func crypt_string(key: String) -> String:
	var sec := crypt()
	if not sec.has(key):
		push_error("GameData.crypt_string: missing 'crypt.%s'" % key)
		assert(false, "GameData: missing crypt constant")
		return ""
	return str(sec[key])


# --- Castle dungeon summoner pads ------------------------------------------

## Forever-war pads inside a castle dungeon — faction is rolled per pad, not authored here.
static func dungeon_summoner() -> Dictionary:
	return _section("dungeon_summoner")


## Typed read from any authored top-level gamedata object section.
static func section_float(section: String, key: String) -> float:
	var sec := _section(section)
	if not sec.has(key):
		push_error("GameData.section_float: missing '%s.%s'" % [section, key])
		assert(false, "GameData: missing section constant")
		return 0.0
	return float(sec[key])


static func section_int(section: String, key: String) -> int:
	var sec := _section(section)
	if not sec.has(key):
		push_error("GameData.section_int: missing '%s.%s'" % [section, key])
		assert(false, "GameData: missing section constant")
		return 0
	return int(sec[key])


static func ability(id: String) -> Dictionary:
	var m := abilities()
	if not m.has(id):
		push_error("GameData.ability: unknown '%s'" % id)
		assert(false, "GameData: unknown ability")
		return {}
	return m[id] as Dictionary


# --- Discovery --------------------------------------------------------------

static func chest_loot() -> Dictionary:
	return _section("chest_loot")


static func recipe_sites() -> Dictionary:
	return _section("recipe_sites")


# --- Mandelbrot -------------------------------------------------------------

static func mandelbrot_spots() -> Dictionary:
	return _section("mandelbrot_spots")


static func mandelbrot_spot_list() -> Array:
	var sec := mandelbrot_spots()
	var spots: Variant = sec.get("spots", null)
	if typeof(spots) != TYPE_ARRAY:
		push_error("GameData: mandelbrot_spots.spots must be an array")
		assert(false, "GameData: bad spots")
		return []
	return spots
