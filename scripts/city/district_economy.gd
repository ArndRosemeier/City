## What a district tile still owes the player: how many of each gem it has left, and whether it
## has been explored. This is the entire persistent footprint of a district.
##
## Districts are never serialised. `CityStreamer` throws a tile's voxels away when the bubble
## moves off it and bakes it again from the seed on return, so "remember which nuggets were
## dug" is not a thing this game can do. A per-type remaining count is, and it buys the same
## outcome: strip a hill's diamonds and they stay gone, because the *budget* is what the next
## bake paints — not a second ledger fighting the voxels.
##
## The budget is rolled **once**, the first time a coord is created in a run, and only ever
## decremented afterwards. A tile the player has never loaded is not in the save at all.
class_name DistrictEconomy
extends RefCounted

## Every gem type a district can owe, rarest last. Order is the save order too.
const GEM_IDS: Array[int] = [
	VoxelMaterial.GEM_QUARTZ,
	VoxelMaterial.GEM_AMBER,
	VoxelMaterial.GEM_TOPAZ,
	VoxelMaterial.GEM_SAPPHIRE,
	VoxelMaterial.GEM_EMERALD,
	VoxelMaterial.GEM_DIAMOND,
]

## Save key per gem. One letter because a row is written for every tile the player has walked
## into, and a long run touches hundreds of them.
const GEM_KEYS: Array[String] = ["q", "a", "t", "s", "e", "d"]
const EXPLORED_KEY := "explored"

const GameDataScript := preload("res://scripts/city/game_data.gd")

## Score for walking into a tile for the first time. Read from GameData (district_gems).
static var EXPLORE_SCORE: int = 50

## coord key → {q,a,t,s,e,d: int, explored: bool}
var _rows: Dictionary[String, Dictionary] = {}


static func coord_key(coord: Vector2i) -> String:
	return "%d,%d" % [coord.x, coord.y]


static func key_to_coord(key: String) -> Vector2i:
	var parts := key.split(",")
	if parts.size() != 2:
		push_error("DistrictEconomy: '%s' is not a district key" % key)
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


static func gem_slot(gem_mat: int) -> int:
	return GEM_IDS.find(gem_mat)


# ---------------------------------------------------------------------------
# Rolling a first-create budget
# ---------------------------------------------------------------------------

## Theme totals from GameData, split across types by the global rarity curve, seeded by the
## district so the same coord in the same world always owes the same gems.
static func roll_budgets(theme_id: int, district_seed: int) -> Dictionary[int, int]:
	var out := _empty_budget()
	EXPLORE_SCORE = GameDataScript.explore_score()
	var total := GameDataScript.theme_gem_total(theme_id)
	if total <= 0:
		push_error("DistrictEconomy.roll_budgets: theme %d has no gem total" % theme_id)
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = district_seed
	for _i in range(total):
		var gem := VoxelMaterial.pick_gem(rng)
		out[gem] = out[gem] + 1
	return out


## Flat mat-id list matching a budget — one entry per gem voxel the hill bake should paint.
static func flat_gem_list(budgets: Dictionary[int, int]) -> PackedInt32Array:
	var out := PackedInt32Array()
	for gem in GEM_IDS:
		var n := int(budgets.get(gem, 0))
		for _i in range(n):
			out.append(gem)
	return out


static func _empty_budget() -> Dictionary[int, int]:
	var out: Dictionary[int, int] = {}
	for gem in GEM_IDS:
		out[gem] = 0
	return out


# ---------------------------------------------------------------------------
# Rows
# ---------------------------------------------------------------------------

func has_row(coord: Vector2i) -> bool:
	return _rows.has(coord_key(coord))


func row_count() -> int:
	return _rows.size()


## Create the row for a coord the run has just reached for the first time. Does nothing when the
## coord already has one: re-entering a tile must never re-roll what is left in it.
func ensure_row(coord: Vector2i, budgets: Dictionary[int, int]) -> bool:
	var key := coord_key(coord)
	if _rows.has(key):
		return false
	var row: Dictionary = {EXPLORED_KEY: false}
	for i in range(GEM_IDS.size()):
		row[GEM_KEYS[i]] = int(budgets.get(GEM_IDS[i], 0))
	_rows[key] = row
	return true


func remaining(coord: Vector2i, gem_mat: int) -> int:
	var row: Dictionary = _rows.get(coord_key(coord), {})
	if row.is_empty():
		return 0
	var slot := gem_slot(gem_mat)
	if slot < 0:
		push_error("DistrictEconomy.remaining: %d is not a gem" % gem_mat)
		return 0
	return int(row.get(GEM_KEYS[slot], 0))


## Total gems of every type this tile still owes.
func remaining_total(coord: Vector2i) -> int:
	var n := 0
	for gem in GEM_IDS:
		n += remaining(coord, gem)
	return n


## One mat id per gem still owed — the exact list a hill bake should paint.
func remaining_flat_list(coord: Vector2i) -> PackedInt32Array:
	var budgets := _empty_budget()
	for gem in GEM_IDS:
		budgets[gem] = remaining(coord, gem)
	return flat_gem_list(budgets)


## Spend one gem of `gem_mat` from `coord`. False when that type is spent (or the tile has no
## row yet, which means nothing has been rolled for it and it owes nothing).
func try_take(coord: Vector2i, gem_mat: int) -> bool:
	var key := coord_key(coord)
	if not _rows.has(key):
		return false
	var slot := gem_slot(gem_mat)
	if slot < 0:
		push_error("DistrictEconomy.try_take: %d is not a gem" % gem_mat)
		return false
	var row: Dictionary = _rows[key]
	var left := int(row.get(GEM_KEYS[slot], 0))
	if left <= 0:
		return false
	row[GEM_KEYS[slot]] = left - 1
	return true


## Spend one gem of any remaining type. Used when a visible voxel's type was already drained
## (e.g. a chest spent that slot) so the next bake still shrinks by one.
func try_take_any(coord: Vector2i) -> bool:
	for gem in GEM_IDS:
		if try_take(coord, gem):
			return true
	return false


## A gem type this tile can still pay, drawn off the rarity curve across only what is left.
## `VoxelMaterial.AIR` when the tile owes nothing at all.
##
## Rolling a type first and then asking whether it is in stock would make a chest in a
## quartz-only district mostly pay nothing, which reads as a bug rather than as scarcity.
func pick_available(coord: Vector2i, rng: RandomNumberGenerator) -> int:
	var total := 0
	for gem in GEM_IDS:
		if remaining(coord, gem) > 0:
			total += VoxelMaterial.gem_rarity_weight(gem)
	if total <= 0:
		return VoxelMaterial.AIR
	var roll := rng.randi_range(1, total)
	for gem in GEM_IDS:
		if remaining(coord, gem) <= 0:
			continue
		roll -= VoxelMaterial.gem_rarity_weight(gem)
		if roll <= 0:
			return gem
	push_error("DistrictEconomy.pick_available: the weights did not add up for %s" % str(coord))
	return VoxelMaterial.AIR


func is_explored(coord: Vector2i) -> bool:
	var row: Dictionary = _rows.get(coord_key(coord), {})
	return bool(row.get(EXPLORED_KEY, false))


## Flag a tile explored. True only the first time, which is what the score pays on.
func mark_explored(coord: Vector2i) -> bool:
	var key := coord_key(coord)
	if not _rows.has(key):
		return false
	var row: Dictionary = _rows[key]
	if bool(row.get(EXPLORED_KEY, false)):
		return false
	row[EXPLORED_KEY] = true
	return true


func explored_count() -> int:
	var n := 0
	for key: String in _rows.keys():
		if bool((_rows[key] as Dictionary).get(EXPLORED_KEY, false)):
			n += 1
	return n


func clear() -> void:
	_rows.clear()


# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------

func to_save_dict() -> Dictionary:
	var out := {}
	for key: String in _rows.keys():
		out[key] = (_rows[key] as Dictionary).duplicate()
	return out


func load_save_dict(data: Dictionary) -> void:
	_rows.clear()
	for raw_key: Variant in data.keys():
		var key := str(raw_key)
		var raw: Variant = data[raw_key]
		if typeof(raw) != TYPE_DICTIONARY:
			push_error("DistrictEconomy: district row '%s' is not an object" % key)
			continue
		var src: Dictionary = raw
		var row: Dictionary = {EXPLORED_KEY: bool(src.get(EXPLORED_KEY, false))}
		for gem_key in GEM_KEYS:
			row[gem_key] = maxi(int(src.get(gem_key, 0)), 0)
		_rows[key] = row
