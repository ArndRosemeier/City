## Gem haul for a monster the player killed: score from max HP, paid as tiered stones.
##
## Score is `floor(max_hp / 40)`. Below 1 means nothing drops — KayKit fodder (~34 HP) pays
## zero; a Quaternius Big (~110) pays 2; grown giants and Unique bosses scale up with HP.
##
## The score is spent as a random partition into values 1 / 2 / 3. Each value maps to a gem
## tier with two stones; which of the two is rolled independently. Inventory + loot toast get
## the haul — there is no world pickup.
class_name MonsterGemDrop
extends RefCounted

const VoxelMaterialScript := preload("res://scripts/city/voxel_material.gd")

const HP_PER_SCORE := 40.0
const TIER_MAX_VALUE := 3

## Tier value → the two VoxelMaterial gem ids that pay that value.
const TIER_MATS: Dictionary = {
	1: [VoxelMaterialScript.GEM_QUARTZ, VoxelMaterialScript.GEM_AMBER],
	2: [VoxelMaterialScript.GEM_TOPAZ, VoxelMaterialScript.GEM_SAPPHIRE],
	3: [VoxelMaterialScript.GEM_EMERALD, VoxelMaterialScript.GEM_DIAMOND],
}


static func score_for_max_hp(max_hp: float) -> int:
	if max_hp < 0.0:
		push_error("MonsterGemDrop.score_for_max_hp: negative max_hp %f" % max_hp)
		assert(false, "MonsterGemDrop: bad max_hp")
		return 0
	return int(floor(max_hp / HP_PER_SCORE))


## Value (1..3) of one gem material, or 0 if it is not a kill-drop stone.
static func value_for_mat(mat_id: int) -> int:
	for value: Variant in TIER_MATS.keys():
		var mats: Array = TIER_MATS[value]
		if mats.has(mat_id):
			return int(value)
	return 0


## Random partition of `score` into values in 1..min(3, remaining). Empty when score < 1.
static func partition_score(score: int, rng: RandomNumberGenerator) -> Array[int]:
	var parts: Array[int] = []
	if score < 1:
		return parts
	if rng == null:
		push_error("MonsterGemDrop.partition_score: rng is null")
		assert(false, "MonsterGemDrop: null rng")
		return parts
	var remaining := score
	while remaining > 0:
		var max_v := mini(TIER_MAX_VALUE, remaining)
		var v := rng.randi_range(1, max_v)
		parts.append(v)
		remaining -= v
	return parts


static func pick_mat_for_value(value: int, rng: RandomNumberGenerator) -> int:
	if not TIER_MATS.has(value):
		push_error("MonsterGemDrop.pick_mat_for_value: bad tier value %d" % value)
		assert(false, "MonsterGemDrop: bad tier")
		return VoxelMaterialScript.GEM_QUARTZ
	if rng == null:
		push_error("MonsterGemDrop.pick_mat_for_value: rng is null")
		assert(false, "MonsterGemDrop: null rng")
		return VoxelMaterialScript.GEM_QUARTZ
	var mats: Array = TIER_MATS[value]
	return int(mats[rng.randi_range(0, mats.size() - 1)])


## Full haul as VoxelMaterial gem ids. Empty when the effective score is under 1.
##
## `min_score` raises a floor under the HP-derived score. Siege uses 1: wave fodder is KayKit
## (~34 HP), which scores zero under the global table, and an empty pot after the stake is spent
## is a dead run. Outside a siege leave it at 0 so zoo / street kills keep the authored floor.
static func roll_mats(
	max_hp: float, rng: RandomNumberGenerator, min_score: int = 0
) -> Array[int]:
	var out: Array[int] = []
	if min_score < 0:
		push_error("MonsterGemDrop.roll_mats: negative min_score %d" % min_score)
		assert(false, "MonsterGemDrop: bad min_score")
		min_score = 0
	var score := maxi(score_for_max_hp(max_hp), min_score)
	if score < 1:
		return out
	var parts := partition_score(score, rng)
	var total := 0
	for v in parts:
		total += v
		out.append(pick_mat_for_value(v, rng))
	if total != score:
		push_error(
			"MonsterGemDrop.roll_mats: partition summed to %d, wanted %d" % [total, score]
		)
		assert(false, "MonsterGemDrop: bad partition")
	return out
