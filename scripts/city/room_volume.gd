## District-local interior volume for furniture placement.
##
## `rect` is the clear floor footprint (same convention as CastleFloor.rooms /
## CastleVault.rect). Walls, slab, and ceiling sit outside this box — the decorator
## only stamps into the air above `floor_y`.
class_name RoomVolume
extends RefCounted

var rect: Rect2i = Rect2i()
## Topmost solid floor voxel Y.
var floor_y: int = 0
## Clear voxels above `floor_y`.
var air_h: int = 0
## Keep storey or dungeon level — informational for callers.
var level: int = 0
var is_hall: bool = false
## XZ footprints that must stay empty (door aprons, stair wells).
var keep_clear: Array[Rect2i] = []


func prop_y() -> int:
	return floor_y + 1


## One cell below the exclusive air top when the room is tall enough.
func ceiling_prop_y() -> int:
	return floor_y + maxi(air_h - 1, 1)


func top_y() -> int:
	return floor_y + air_h


## Inclusive min of the clear air box.
func air_min() -> Vector3i:
	return Vector3i(rect.position.x, floor_y + 1, rect.position.y)


## Exclusive max of the clear air box (CityBrush.fill_box convention).
func air_max() -> Vector3i:
	return Vector3i(rect.end.x, floor_y + air_h + 1, rect.end.y)


func area() -> int:
	return rect.size.x * rect.size.y


func contains_xz(p: Vector2i) -> bool:
	return rect.has_point(p)


func is_cleared(p: Vector2i) -> bool:
	for c in keep_clear:
		if c.has_point(p):
			return true
	return false


func describe() -> String:
	return "room %s y=%d air=%d level=%d hall=%s clear=%d" % [
		rect, floor_y, air_h, level, is_hall, keep_clear.size()
	]


static func make(p_rect: Rect2i, p_floor_y: int, p_air_h: int) -> RoomVolume:
	var v := RoomVolume.new()
	v.rect = p_rect
	v.floor_y = p_floor_y
	v.air_h = p_air_h
	return v


static func from_keep_room(f: CastleFloor, room: Rect2i, hall: bool = false) -> RoomVolume:
	var v := RoomVolume.new()
	v.rect = room
	v.floor_y = f.floor_y
	v.air_h = f.air_h
	v.level = f.storey
	v.is_hall = hall
	return v


static func from_vault(vault: CastleVault) -> RoomVolume:
	var v := RoomVolume.new()
	v.rect = vault.rect
	v.floor_y = vault.floor_y
	v.air_h = vault.air_h
	v.level = vault.level
	v.is_hall = vault.is_tall() or vault.is_wide()
	return v
