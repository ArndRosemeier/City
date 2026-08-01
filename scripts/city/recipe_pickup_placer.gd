## Every recipe scroll standing in one district, so unloading the tile takes its scrolls with it.
##
## The chance table is the whole difficulty curve of discovery. Landmarks that cost a real climb
## (a hill summit, a castle crown, an arena spire) always pay, because a player who got up there
## and found nothing learns the wrong lesson. Everything cheap — a roof among hundreds of roofs,
## a chest in a room — pays rarely, and the per-district cap stops a lucky seed from carpeting
## one tile in scrolls.
class_name RecipePickupPlacer
extends Node3D

const RecipePickupScript := preload("res://scripts/city/recipe_pickup.gd")

const SITE_HILL_SUMMIT := 0
const SITE_CASTLE_TOWER := 1
const SITE_ARENA_TOWER := 2
const SITE_GAZEBO := 3
const SITE_LAKE_ISLAND := 4
const SITE_FRACTAL_NICHE := 5
const SITE_CRYPT := 6
const SITE_ROOFTOP := 7
const SITE_CHEST := 8

## Scrolls one district may hold. Landmark sites are placed first, so the cap trims the cheap
## sites rather than the ones worth climbing to.
const PER_DISTRICT_MAX := 2

var _pickups: Array[RecipePickup] = []


static func site_kind_name(kind: int) -> String:
	match kind:
		SITE_HILL_SUMMIT:
			return "summit"
		SITE_CASTLE_TOWER:
			return "castle-tower"
		SITE_ARENA_TOWER:
			return "arena-tower"
		SITE_GAZEBO:
			return "gazebo"
		SITE_LAKE_ISLAND:
			return "island"
		SITE_FRACTAL_NICHE:
			return "fractal-niche"
		SITE_CRYPT:
			return "crypt"
		SITE_ROOFTOP:
			return "roof"
		SITE_CHEST:
			return "chest"
		_:
			push_error("RecipePickupPlacer.site_kind_name: unknown kind %d" % kind)
			return "unknown"


## Out of a hundred. The four landmark sites are certain: they are already rare because the
## landmark itself is rare, and rolling dice on top of that only makes the climb feel cheated.
static func chance_pct(kind: int) -> int:
	match kind:
		SITE_HILL_SUMMIT:
			return 100
		SITE_CASTLE_TOWER:
			return 100
		SITE_ARENA_TOWER:
			return 100
		SITE_GAZEBO:
			return 100
		SITE_LAKE_ISLAND:
			return 45
		SITE_FRACTAL_NICHE:
			return 60
		SITE_CRYPT:
			return 25
		SITE_ROOFTOP:
			return 8
		SITE_CHEST:
			return 6
		_:
			push_error("RecipePickupPlacer.chance_pct: unknown kind %d" % kind)
			return 0


## Deterministic in `site_seed`, so the same spot in the same world answers the same way however
## often the tile is re-streamed.
static func should_place(kind: int, site_seed: int) -> bool:
	var pct := chance_pct(kind)
	if pct >= 100:
		return true
	if pct <= 0:
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = site_seed
	return rng.randi_range(1, 100) <= pct


## Stable name for one spot. `index` separates several sites of the same kind on one tile — the
## four arena spires, or one roof among many.
static func site_id(kind: int, coord: Vector2i, index: int) -> String:
	return "%s:%d,%d:%d" % [site_kind_name(kind), coord.x, coord.y, index]


func pickup_count() -> int:
	return _pickups.size()


## Live scrolls still standing in this district. Dead/freed entries are dropped so callers can
## walk the list without re-checking validity.
func live_pickups() -> Array[RecipePickup]:
	var out: Array[RecipePickup] = []
	var kept: Array[RecipePickup] = []
	for pickup in _pickups:
		if pickup == null or not is_instance_valid(pickup) or pickup.is_taken():
			continue
		kept.append(pickup)
		out.append(pickup)
	_pickups = kept
	return out


## Landmark scrolls only — chest bonuses are left out so a debug teleport cannot dump the player
## on a chest that happens to be closer than the climb they were trying to find.
func live_landmark_pickups() -> Array[RecipePickup]:
	var out: Array[RecipePickup] = []
	for pickup in live_pickups():
		if not is_landmark_site_id(pickup.site_id):
			continue
		out.append(pickup)
	return out


static func is_landmark_site_id(site_id: String) -> bool:
	return not site_id.begins_with("%s:" % site_kind_name(SITE_CHEST))


func at_capacity() -> bool:
	return _pickups.size() >= PER_DISTRICT_MAX


## Roll for a spot and, if it wins, stand a scroll there. Returns null whenever nothing should
## appear — the tile is full, the dice said no, or this run already took that one.
func try_place(
	kind: int, coord: Vector2i, index: int, world_pos: Vector3, site_seed: int
) -> RecipePickup:
	if at_capacity():
		return null
	var id := site_id(kind, coord, index)
	var city := _city_root()
	if city != null and city.is_recipe_site_looted(id):
		return null
	if not should_place(kind, site_seed):
		return null
	var pickup: RecipePickup = RecipePickupScript.new() as RecipePickup
	pickup.name = "RecipePickup%d" % _pickups.size()
	add_child(pickup)
	if not pickup.build(id, world_pos, site_seed):
		pickup.queue_free()
		return null
	_pickups.append(pickup)
	print("RecipePickupPlacer: %s at %s" % [id, str(world_pos)])
	return pickup


func clear_pickups() -> void:
	for pickup in _pickups:
		if pickup != null and is_instance_valid(pickup):
			pickup.queue_free()
	_pickups.clear()


func _city_root() -> CityRoot:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group("city_root")
	if nodes.is_empty():
		return null
	return nodes[0] as CityRoot
