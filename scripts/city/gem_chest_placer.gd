## Every gem chest standing in one district, so unloading the tile takes its chests with it.
##
## Chests appear as rooms are furnished, not when the tile bakes: interiors are subdivided and
## dressed lazily by `InteriorDecorator` as the player walks in, and a chest in a room nobody has
## entered would be a chest in an undecided floor plan.
class_name GemChestPlacer
extends Node3D

const GemChestScript := preload("res://scripts/city/gem_chest.gd")

const GameDataScript := preload("res://scripts/city/game_data.gd")

var _chests: Array[GemChest] = []


## Whether the room described by `purpose` gets a chest. Deterministic in `room_seed`, so the
## same room in the same world answers the same way however often it is re-streamed.
static func should_place(purpose: int, room_seed: int) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = room_seed
	return rng.randi_range(1, 100) <= chance_pct(purpose)


static func chance_pct(purpose: int) -> int:
	var chances: Dictionary = GameDataScript.chest_loot().get("place_chance_pct", {}) as Dictionary
	if purpose == RoomDecorator.Purpose.CORRIDOR:
		return int(chances.get("corridor", 0))
	if purpose == RoomDecorator.Purpose.STORAGE:
		return int(chances.get("storage", 34))
	return int(chances.get("ordinary", 7))


## Stand one chest. Null when the model could not be built, which is a content fault rather than
## a reason to carry on without collision.
func place_chest(coord: Vector2i, world_pos: Vector3, yaw: float, chest_seed: int) -> GemChest:
	var chest: GemChest = GemChestScript.new() as GemChest
	chest.name = "GemChest%d" % _chests.size()
	add_child(chest)
	if not chest.build(coord, world_pos, yaw, chest_seed):
		chest.queue_free()
		return null
	_chests.append(chest)
	return chest


func chest_count() -> int:
	return _chests.size()


func chest_at(index: int) -> GemChest:
	if index < 0 or index >= _chests.size():
		push_error("GemChestPlacer.chest_at: %d is not a chest" % index)
		return null
	return _chests[index]


func clear_chests() -> void:
	for chest in _chests:
		if chest != null and is_instance_valid(chest):
			chest.queue_free()
	_chests.clear()
