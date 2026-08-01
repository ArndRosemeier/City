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
## Peak of a lock-on Create morph. Replaces the old spiral-niche hide.
const SITE_FRACTAL_PEAK := 5
const SITE_CRYPT := 6
const SITE_ROOFTOP := 7
const SITE_CHEST := 8
## One of the Monster Zoo gazebo roofs (summon stations + battlefield bandstands).
const SITE_ZOO_GAZEBO := 9

const GameDataScript := preload("res://scripts/city/game_data.gd")

## Scrolls one district may hold from the stream-time placer (gamedata). Fractal peak recipes
## sit outside this cap — each of the four panels can pay once when the player follows its lock-on.
static var PER_DISTRICT_MAX: int = 2

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
		SITE_FRACTAL_PEAK:
			return "fractal-peak"
		SITE_CRYPT:
			return "crypt"
		SITE_ROOFTOP:
			return "roof"
		SITE_CHEST:
			return "chest"
		SITE_ZOO_GAZEBO:
			return "zoo-gazebo"
		_:
			push_error("RecipePickupPlacer.site_kind_name: unknown kind %d" % kind)
			return "unknown"


## Out of a hundred. Authored in gamedata.json `recipe_sites.chance_pct`.
static func chance_pct(kind: int) -> int:
	PER_DISTRICT_MAX = int(GameDataScript.recipe_sites().get("per_district_max", 2))
	var chances: Dictionary = GameDataScript.recipe_sites().get("chance_pct", {}) as Dictionary
	var key := site_kind_name(kind)
	if key == "unknown":
		return 0
	if not chances.has(key):
		push_error("RecipePickupPlacer.chance_pct: no gamedata chance for '%s'" % key)
		return 0
	return int(chances[key])


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
	return _spawn_pickup(kind, coord, index, world_pos, site_seed)


## Fractal peak after a lock-on Create. Bypasses the stream-time district cap so all four panels
## can pay; still refuses a site this run already looted.
func try_place_fractal_peak(
	coord: Vector2i, edge_index: int, world_pos: Vector3, site_seed: int
) -> RecipePickup:
	return _spawn_pickup(SITE_FRACTAL_PEAK, coord, edge_index, world_pos, site_seed)


func _spawn_pickup(
	kind: int, coord: Vector2i, index: int, world_pos: Vector3, site_seed: int
) -> RecipePickup:
	var id := site_id(kind, coord, index)
	var city := _city_root()
	if city != null and city.is_recipe_site_looted(id):
		return null
	if not should_place(kind, site_seed):
		return null
	## Already standing — do not double-spawn the same peak after a second Create.
	for existing in _pickups:
		if existing != null and is_instance_valid(existing) and existing.site_id == id:
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
