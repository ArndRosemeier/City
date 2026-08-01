## Every assignable tray entry: weapons, powers, consumable uses, and free builds.
##
## "Unlocked" means may be assigned. Sandbox treats every non-build combat/power id as unlocked;
## Adventure starts with `blaster` and spends gems for the rest. Builds are never gated.
class_name AbilityRegistry
extends RefCounted

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

## Adventure starts with this alone.
const STARTER_UNLOCKS: Array[String] = [ID_BLASTER]

## Trap-hostile score payout (Adventure only).
const TRAP_HOSTILE_SCORE := 25
const BOOST_DURATION_SEC := 20.0
const GROW_SHRINK_DURATION_SEC := 25.0
const SHIELD_DRAIN_PER_SEC := 8.0
const MINION_MAX := 2


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
	_reg(
		ID_BLASTER, "Blaster", KIND_WEAPON, {}, 1.0, true,
		"Hold primary fire — starter weapon"
	)
	_reg(
		ID_LASER, "Laser", KIND_WEAPON,
		{InventoryCatalog.ID_QUARTZ: 8, InventoryCatalog.ID_TOPAZ: 3}, 1.0, true,
		"Eye beam"
	)
	_reg(
		ID_CHARGED_BLAST, "Charged blast", KIND_WEAPON,
		{
			InventoryCatalog.ID_AMBER: 6,
			InventoryCatalog.ID_TOPAZ: 4,
			InventoryCatalog.ID_SAPPHIRE: 2,
		},
		20.0, true, "Hold Alt fire, release to throw"
	)
	_reg(
		ID_STOMP, "Stomp", KIND_WEAPON,
		{InventoryCatalog.ID_QUARTZ: 10, InventoryCatalog.ID_EMERALD: 2}, 10.0, true,
		"Ground slam"
	)
	_reg(
		ID_SHIELD, "Shield", KIND_POWER,
		{InventoryCatalog.ID_SAPPHIRE: 5, InventoryCatalog.ID_TOPAZ: 4}, 0.0, true,
		"Hold to drain energy and blunt hits"
	)
	_reg(
		ID_GROW, "Grow", KIND_POWER,
		{InventoryCatalog.ID_EMERALD: 3, InventoryCatalog.ID_AMBER: 4}, 12.0, true,
		"Temporary size up"
	)
	_reg(
		ID_SHRINK, "Shrink", KIND_POWER,
		{InventoryCatalog.ID_EMERALD: 2, InventoryCatalog.ID_AMBER: 4}, 12.0, true,
		"Temporary size down"
	)
	_reg(
		ID_MINION, "Minion", KIND_POWER,
		{InventoryCatalog.ID_EMERALD: 4, InventoryCatalog.ID_QUARTZ: 12}, 15.0, true,
		"Summon a follower"
	)
	_reg(
		ID_DISTRICT_HOP, "District hop", KIND_POWER,
		{InventoryCatalog.ID_AMBER: 3, InventoryCatalog.ID_QUARTZ: 6}, 0.0, true,
		"Teleport to a known district"
	)
	_reg(
		ID_TETRIS, "Tetris", KIND_POWER,
		{InventoryCatalog.ID_AMBER: 2, InventoryCatalog.ID_QUARTZ: 8}, 0.0, true,
		"Summon a cabinet"
	)
	_reg(
		ID_USE_TRAP, "Throw trap", KIND_CONSUMABLE, {}, 0.0, false,
		"Lob a hold trap from inventory"
	)
	_reg(
		ID_USE_BOOST_SPEED, "Speed boost", KIND_CONSUMABLE, {}, 0.0, false,
		"Drink a speed tonic"
	)
	_reg(
		ID_USE_BOOST_REGEN, "Regen boost", KIND_CONSUMABLE, {}, 0.0, false,
		"Drink a regen tonic"
	)
	_reg(
		ID_HARDNESS_REINFORCED, "Hardness: Reinforced", KIND_META,
		{InventoryCatalog.ID_DIAMOND: 2, InventoryCatalog.ID_QUARTZ: 20}, 0.0, true,
		"Carve concrete and steel"
	)
	_reg(
		ID_HARDNESS_EXOTIC, "Hardness: Exotic", KIND_META,
		{
			InventoryCatalog.ID_DIAMOND: 4,
			InventoryCatalog.ID_SAPPHIRE: 4,
			InventoryCatalog.ID_QUARTZ: 15,
		},
		0.0, true, "Carve meteor rock and infection"
	)
	for recipe: BuildCatalog.Recipe in BuildCatalog.all():
		_reg(recipe.id, recipe.display_name, KIND_BUILD, {}, 0.0, false, recipe.hint)


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


static func default_sandbox_tray() -> Array[String]:
	var slots: Array[String] = []
	slots.resize(SLOT_COUNT)
	var builds: Array[String] = ["cottage", "pool", "hot_tub", "dog", "cat", "duck"]
	for i in range(SLOT_COUNT):
		slots[i] = ""
	for i in range(mini(6, builds.size())):
		slots[i] = builds[i]
	slots[SLOT_MOUSE_LMB] = ID_BLASTER
	slots[SLOT_MOUSE_CTRL] = ID_LASER
	slots[SLOT_MOUSE_ALT] = ID_CHARGED_BLAST
	return slots


static func default_adventure_tray() -> Array[String]:
	var slots: Array[String] = []
	slots.resize(SLOT_COUNT)
	for i in range(SLOT_COUNT):
		slots[i] = ""
	## Free builds on F-keys so the bar is not blank; combat starts as blaster only.
	var builds: Array[String] = ["cottage", "pool", "hot_tub", "dog", "cat", "duck"]
	for i in range(mini(6, builds.size())):
		slots[i] = builds[i]
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
