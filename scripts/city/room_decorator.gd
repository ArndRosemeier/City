## Fills an interior RoomVolume with catalog props for a given purpose.
##
## Callers own the masonry (walls / floor / ceiling). This only stamps into clear
## air above `floor_y`, via CityBrush. Existing solids in the air band (stairs,
## pillars, carved features) reserve their XZ columns — props never replace them.
## Castle bake and JIT city buildings both construct a RoomVolume and call `decorate`.
class_name RoomDecorator
extends RefCounted

enum Purpose {
	LIVING_ROOM,
	BEDROOM,
	OFFICE,
	KITCHEN,
	BATHROOM,
	DINING_ROOM,
	STORAGE,
	LIBRARY,
	TAVERN,
	THRONE_HALL,
	DUNGEON_CHAMBER,
	DUNGEON_CELL,
	ARMORY,
	WORKSHOP,
	GENERIC,
	## Cut by FloorPlanner when a storey is subdivided by purpose.
	RECEPTION,
	MEETING_ROOM,
	BREAK_ROOM,
	CORRIDOR,
	SHOP,
	## Arena sand pit cover: pillars / crates / low walls with walk lanes.
	ARENA_PIT,
}

## Placement role for one plan step.
enum Role {
	CORNER,
	WALL,
	CENTER,
	SCATTER,
	CEILING,
}

## How far into the room an opening reserves (matches castle door swing reach).
## City façades punch AIR doorways; later real doors keep the same clear apron.
const OPENING_APRON_DEPTH := 3
## Clear cells a walker needs over the floor: the capsule is 1.7 m plus its sole, and
## anything hanging into that band is something to bump into, not decoration.
const WALK_CLEAR_VOX := 4

var brush: CityBrush
var rng: RandomNumberGenerator


## Stamp props for `purpose` into `volume`. Returns how many props were written.
func decorate(volume: RoomVolume, purpose: Purpose) -> int:
	if brush == null:
		push_error("RoomDecorator.decorate: brush is null")
		return 0
	if rng == null:
		push_error("RoomDecorator.decorate: rng is null")
		return 0
	if volume == null:
		push_error("RoomDecorator.decorate: volume is null")
		return 0
	if volume.rect.size.x < 3 or volume.rect.size.y < 3 or volume.air_h < 2:
		return 0

	## Columns reserved by the world (stairs, pillars, missing floor, door aprons).
	var blocked: Dictionary = {}
	_mark_clears(volume, blocked)
	_seed_blocked_from_voxels(volume, blocked)
	_seed_opening_aprons(volume, blocked)
	## Columns we filled with floor props this pass (ceiling may still share XZ).
	var occupied: Dictionary = {}

	brush.begin_edit()
	var placed := 0
	for step in _plan_for(purpose, volume):
		placed += _apply_step(volume, step, blocked, occupied)
	brush.end_edit()
	return placed


static func purpose_name(purpose: Purpose) -> String:
	match purpose:
		Purpose.LIVING_ROOM:
			return "living_room"
		Purpose.BEDROOM:
			return "bedroom"
		Purpose.OFFICE:
			return "office"
		Purpose.KITCHEN:
			return "kitchen"
		Purpose.BATHROOM:
			return "bathroom"
		Purpose.DINING_ROOM:
			return "dining_room"
		Purpose.STORAGE:
			return "storage"
		Purpose.LIBRARY:
			return "library"
		Purpose.TAVERN:
			return "tavern"
		Purpose.THRONE_HALL:
			return "throne_hall"
		Purpose.DUNGEON_CHAMBER:
			return "dungeon_chamber"
		Purpose.DUNGEON_CELL:
			return "dungeon_cell"
		Purpose.ARMORY:
			return "armory"
		Purpose.WORKSHOP:
			return "workshop"
		Purpose.GENERIC:
			return "generic"
		Purpose.RECEPTION:
			return "reception"
		Purpose.MEETING_ROOM:
			return "meeting_room"
		Purpose.BREAK_ROOM:
			return "break_room"
		Purpose.CORRIDOR:
			return "corridor"
		Purpose.SHOP:
			return "shop"
		Purpose.ARENA_PIT:
			return "arena_pit"
	return "unknown"


static func purpose_from_name(name: String) -> Purpose:
	match name.to_lower().strip_edges():
		"living_room", "living":
			return Purpose.LIVING_ROOM
		"bedroom", "bed":
			return Purpose.BEDROOM
		"office", "study":
			return Purpose.OFFICE
		"kitchen":
			return Purpose.KITCHEN
		"bathroom", "bath":
			return Purpose.BATHROOM
		"dining_room", "dining":
			return Purpose.DINING_ROOM
		"storage", "store", "pantry":
			return Purpose.STORAGE
		"library":
			return Purpose.LIBRARY
		"tavern", "inn", "pub":
			return Purpose.TAVERN
		"throne_hall", "throne", "great_hall", "hall":
			return Purpose.THRONE_HALL
		"dungeon_chamber", "chamber":
			return Purpose.DUNGEON_CHAMBER
		"dungeon_cell", "cell":
			return Purpose.DUNGEON_CELL
		"armory", "armoury":
			return Purpose.ARMORY
		"workshop", "smithy":
			return Purpose.WORKSHOP
		"reception", "lobby":
			return Purpose.RECEPTION
		"meeting_room", "meeting", "conference":
			return Purpose.MEETING_ROOM
		"break_room", "break", "pantry_room":
			return Purpose.BREAK_ROOM
		"corridor", "hallway", "landing":
			return Purpose.CORRIDOR
		"shop", "retail", "store_front":
			return Purpose.SHOP
		"arena_pit", "arena":
			return Purpose.ARENA_PIT
		_:
			return Purpose.GENERIC


func _mark_clears(volume: RoomVolume, blocked: Dictionary) -> void:
	for c in volume.keep_clear:
		for z in range(c.position.y, c.end.y):
			for x in range(c.position.x, c.end.x):
				blocked[Vector2i(x, z)] = true


## Reserve every XZ column that is not a free furniture cell: missing slab, or any
## non-air already in the clear band (stair flights, supports, prior props).
func _seed_blocked_from_voxels(volume: RoomVolume, blocked: Dictionary) -> void:
	var y_lo := volume.prop_y()
	var y_hi := volume.floor_y + volume.air_h
	for z in range(volume.rect.position.y, volume.rect.end.y):
		for x in range(volume.rect.position.x, volume.rect.end.x):
			var p := Vector2i(x, z)
			if blocked.has(p):
				continue
			if brush.get_vox(Vector3i(x, volume.floor_y, z)) == VoxelMaterial.AIR:
				blocked[p] = true
				continue
			for y in range(y_lo, y_hi + 1):
				if brush.get_vox(Vector3i(x, y, z)) != VoxelMaterial.AIR:
					blocked[p] = true
					break


## Walk the room perimeter: AIR in the wall cell outside = doorway / open passage.
## Glass windows stay solid ids and do not clear. Reserves an inward apron so WALL
## props cannot smother the opening (same clearance future hinged doors need).
func _seed_opening_aprons(volume: RoomVolume, blocked: Dictionary) -> void:
	var r := volume.rect
	var depth := mini(
		OPENING_APRON_DEPTH,
		maxi(1, mini(r.size.x, r.size.y) / 3)
	)
	## -Z wall (outside z = r.position.y - 1), apron grows +Z into the room.
	for x in range(r.position.x, r.end.x):
		if _is_opening_wall_cell(Vector3i(x, volume.floor_y + 1, r.position.y - 1)):
			_block_opening_apron(volume, blocked, Vector2i(x, r.position.y), Vector2i(0, 1), depth)
	## +Z wall (outside z = r.end.y).
	for x in range(r.position.x, r.end.x):
		if _is_opening_wall_cell(Vector3i(x, volume.floor_y + 1, r.end.y)):
			_block_opening_apron(volume, blocked, Vector2i(x, r.end.y - 1), Vector2i(0, -1), depth)
	## -X wall.
	for z in range(r.position.y, r.end.y):
		if _is_opening_wall_cell(Vector3i(r.position.x - 1, volume.floor_y + 1, z)):
			_block_opening_apron(volume, blocked, Vector2i(r.position.x, z), Vector2i(1, 0), depth)
	## +X wall.
	for z in range(r.position.y, r.end.y):
		if _is_opening_wall_cell(Vector3i(r.end.x, volume.floor_y + 1, z)):
			_block_opening_apron(volume, blocked, Vector2i(r.end.x - 1, z), Vector2i(-1, 0), depth)


## Passable punched opening (city door / castle carve). Closed DOOR plugs still mark the
## doorway for furniture aprons — the leaf/barrier occupies the opening, not the apron.
func _is_opening_wall_cell(wall_vox: Vector3i) -> bool:
	var id := brush.get_vox(wall_vox)
	return id == VoxelMaterial.AIR or VoxelMaterial.is_door(id)


func _block_opening_apron(
	volume: RoomVolume,
	blocked: Dictionary,
	edge: Vector2i,
	inward: Vector2i,
	depth: int
) -> void:
	for d in range(depth):
		var p := edge + inward * d
		if volume.contains_xz(p):
			blocked[p] = true


func _plan_for(purpose: Purpose, volume: RoomVolume) -> Array[Dictionary]:
	var area := volume.area()
	var wall_n := _scaled(2, area, 70, 8)
	var scatter_n := _scaled(1, area, 90, 10)
	var corner_n := mini(4, _scaled(1, area, 120, 4))

	match purpose:
		Purpose.LIVING_ROOM:
			return _steps([
				_step(Role.CENTER, ["rugRectangle", "rugRound", "rugSquare"], 1),
				_step(Role.WALL, ["loungeSofa", "loungeSofaLong", "loungeSofaCorner"], 1),
				_step(Role.CENTER, ["tableCoffee", "tableCoffeeGlass"], 1),
				_step(Role.WALL, ["loungeChair", "loungeChairRelax", "benchCushion"], wall_n),
				_step(Role.CORNER, ["lampRoundFloor", "lampSquareFloor", "pottedPlant"], corner_n),
				_step(Role.CEILING, ["lampSquareCeiling", "ceilingFan"], 1),
			])
		Purpose.BEDROOM:
			return _steps([
				_step(Role.WALL, ["bedDouble", "bedSingle", "bedBunk"], 1),
				_step(Role.WALL, ["cabinetBed", "cabinetBedDrawer", "sideTable"], 1),
				_step(Role.CORNER, ["coatRackStanding", "plantSmall1", "lampRoundFloor"], corner_n),
				_step(Role.CEILING, ["lampSquareCeiling"], 1),
			])
		Purpose.OFFICE:
			return _steps([
				_step(Role.WALL, ["desk", "deskCorner"], 1),
				_step(Role.WALL, ["chairDesk", "chair"], 1),
				_step(Role.WALL, ["bookcaseOpen", "bookcaseClosed", "bookcaseClosedWide"], wall_n),
				_step(Role.CORNER, ["plantSmall2", "pottedPlant", "lampSquareFloor"], corner_n),
				_step(Role.CEILING, ["lampSquareCeiling"], 1),
			])
		Purpose.KITCHEN:
			return _steps([
				_step(Role.WALL, ["kitchenCabinet", "kitchenCabinetDrawer", "kitchenCabinetDrawer1"], wall_n),
				_step(Role.WALL, ["kitchenStove", "kitchenStoveElectric", "kitchenSink"], 1),
				_step(Role.WALL, ["kitchenFridge", "kitchenFridgeSmall", "kitchenFridgeBuiltIn"], 1),
				_step(Role.CORNER, ["kitchenCoffeeMachine", "kitchenMicrowave", "kitchenBlender"], 1),
				_step(Role.CEILING, ["ceilingFan", "lampSquareCeiling"], 1),
			])
		Purpose.BATHROOM:
			return _steps([
				_step(Role.WALL, ["bathtub", "shower"], 1),
				_step(Role.WALL, ["toilet"], 1),
				_step(Role.WALL, ["bathroomSink", "bathroomCabinet"], 1),
				_step(Role.WALL, ["bathroomMirror"], 1),
				_step(Role.CORNER, ["plantSmall3"], mini(1, corner_n)),
			])
		Purpose.DINING_ROOM:
			return _steps([
				_step(Role.CENTER, ["table", "tableCloth"], 1),
				_step(Role.WALL, ["chair", "chairRounded", "chairCushion"], maxi(2, wall_n)),
				_step(Role.CORNER, ["plantSmall1", "pottedPlant", "sideTable"], corner_n),
				_step(Role.CEILING, ["lampSquareCeiling"], 1),
			])
		Purpose.STORAGE:
			return _steps([
				_step(Role.WALL, ["crate", "barrel", "cardboardBoxOpen"], wall_n + scatter_n),
				_step(Role.SCATTER, ["crate", "barrel"], scatter_n),
				_step(Role.CORNER, ["cardboardBoxOpen", "crate"], corner_n),
			])
		Purpose.LIBRARY:
			return _steps([
				_step(Role.WALL, [
					"bookcaseOpen", "bookcaseClosed", "bookcaseClosedDoors",
					"bookcaseClosedWide", "bookcaseOpenLow"
				], maxi(3, wall_n)),
				_step(Role.CENTER, ["table", "desk"], 1),
				_step(Role.WALL, ["chair", "chairDesk", "bench"], 2),
				_step(Role.CORNER, ["lampRoundFloor", "plantSmall2"], corner_n),
				_step(Role.CEILING, ["lampSquareCeiling"], 1),
			])
		Purpose.TAVERN:
			return _steps([
				_step(Role.CENTER, ["table", "tableCloth"], maxi(1, area / 100)),
				_step(Role.WALL, ["kitchenBar", "kitchenBarEnd"], 1),
				_step(Role.WALL, ["stoolBar", "stoolBarSquare", "bench"], wall_n),
				_step(Role.SCATTER, ["barrel", "crate"], scatter_n),
				_step(Role.CORNER, ["speaker", "radio", "plantSmall1"], corner_n),
				_step(Role.CEILING, ["lampSquareCeiling", "ceilingFan"], 1),
			])
		Purpose.THRONE_HALL:
			return _steps([
				_step(Role.CENTER, ["rugRectangle", "rugRounded"], 1),
				_step(Role.WALL, ["bench", "benchCushion", "loungeSofaLong"], wall_n),
				_step(Role.CORNER, ["pottedPlant", "plantSmall1", "bear"], corner_n),
				_step(Role.WALL, ["bookcaseClosedWide", "sideTable"], mini(2, wall_n)),
				_step(Role.CEILING, ["lampSquareCeiling"], maxi(1, area / 200)),
			])
		Purpose.DUNGEON_CHAMBER:
			return _steps([
				_step(Role.WALL, ["barrel", "crate", "bench"], wall_n),
				_step(Role.SCATTER, ["barrel", "crate", "cardboardBoxOpen"], scatter_n),
				_step(Role.CORNER, ["lampSquareFloor", "crate"], corner_n),
				_step(Role.CENTER, ["table"], 1 if area >= 80 else 0),
			])
		Purpose.DUNGEON_CELL:
			return _steps([
				_step(Role.WALL, ["bedSingle", "bedBunk"], 1),
				_step(Role.CORNER, ["barrel", "crate"], 1),
				_step(Role.WALL, ["stoolBarSquare", "chair"], 1),
			])
		Purpose.ARMORY:
			return _steps([
				_step(Role.WALL, ["crate", "barrel", "bookcaseClosed"], wall_n),
				_step(Role.SCATTER, ["crate", "barrel"], scatter_n),
				_step(Role.CORNER, ["coatRackStanding", "crate"], corner_n),
				_step(Role.CENTER, ["table"], 1),
			])
		Purpose.WORKSHOP:
			return _steps([
				_step(Role.WALL, ["desk", "table", "sideTable"], 1),
				_step(Role.WALL, ["chairDesk", "stoolBar"], 1),
				_step(Role.SCATTER, ["crate", "barrel", "cardboardBoxOpen"], scatter_n),
				_step(Role.CORNER, ["lampSquareFloor", "coatRackStanding"], corner_n),
				_step(Role.CEILING, ["ceilingFan", "lampSquareCeiling"], 1),
			])
		Purpose.GENERIC:
			return _steps([
				_step(Role.WALL, ["chair", "bench", "table"], mini(2, wall_n)),
				_step(Role.CORNER, ["crate", "plantSmall1", "lampRoundFloor"], corner_n),
				_step(Role.SCATTER, ["crate", "barrel"], scatter_n),
			])
		Purpose.RECEPTION:
			return _steps([
				_step(Role.WALL, ["kitchenBar", "kitchenBarEnd", "desk"], 1),
				_step(Role.WALL, ["chairDesk", "loungeSofa", "benchCushion"], maxi(2, wall_n)),
				_step(Role.CENTER, ["rugRectangle", "tableCoffeeGlass"], 1),
				_step(Role.CORNER, ["pottedPlant", "plantSmall2", "coatRackStanding"], corner_n),
				_step(Role.CEILING, ["lampSquareCeiling"], maxi(1, area / 200)),
			])
		Purpose.MEETING_ROOM:
			return _steps([
				_step(Role.CENTER, ["tableGlass", "table", "tableCross"], 1),
				_step(Role.WALL, ["chairDesk", "chairRounded", "chair"], maxi(4, wall_n)),
				_step(Role.WALL, ["cabinetTelevision", "televisionModern"], 1),
				_step(Role.CORNER, ["plantSmall2", "pottedPlant"], corner_n),
				_step(Role.CEILING, ["lampSquareCeiling"], 1),
			])
		Purpose.BREAK_ROOM:
			return _steps([
				_step(Role.WALL, ["kitchenCabinet", "kitchenSink", "kitchenCabinetDrawer"], wall_n),
				_step(Role.WALL, ["kitchenCoffeeMachine", "kitchenMicrowave"], 1),
				_step(Role.WALL, ["kitchenFridgeSmall", "kitchenFridge"], 1),
				_step(Role.CENTER, ["table", "tableRound"], 1),
				_step(Role.WALL, ["chair", "stoolBar"], maxi(2, wall_n)),
				_step(Role.CEILING, ["lampSquareCeiling"], 1),
			])
		Purpose.CORRIDOR:
			## Circulation stays walkable: only the wall line and the ceiling get dressed.
			return _steps([
				_step(Role.WALL, ["bench", "benchCushionLow", "coatRack"], mini(2, wall_n), 6),
				_step(Role.WALL, ["pottedPlant", "plantSmall3"], mini(2, wall_n), 8),
				_step(Role.CEILING, ["lampSquareCeiling"], maxi(1, area / 120)),
			])
		Purpose.SHOP:
			return _steps([
				_step(Role.WALL, ["bookcaseOpen", "bookcaseOpenLow", "kitchenCabinetUpper"], maxi(3, wall_n)),
				_step(Role.WALL, ["kitchenBar", "kitchenBarEnd"], 1),
				_step(Role.CENTER, ["table", "tableCloth"], maxi(1, area / 150)),
				_step(Role.SCATTER, ["crate", "cardboardBoxOpen"], scatter_n),
				_step(Role.CORNER, ["pottedPlant", "trashcan", "plantSmall1"], corner_n),
				_step(Role.CEILING, ["lampSquareCeiling"], maxi(1, area / 150)),
			])
		Purpose.ARENA_PIT:
			## Cover props with walk lanes — no ceiling hangings over the open pit.
			var pit_scatter := _scaled(4, area, 180, 36)
			var pit_wall := _scaled(2, area, 220, 16)
			return _steps([
				_step(Role.SCATTER, ["crate", "barrel", "cardboardBoxOpen"], pit_scatter, 5),
				_step(Role.WALL, ["pillarSmall", "statue_column", "statue_obelisk"], pit_wall, 8),
				_step(Role.CORNER, ["urnRound", "crate", "barrel"], corner_n),
				_step(Role.CENTER, ["table", "benchStone"], 1 if area >= 200 else 0),
			])
	return [] as Array[Dictionary]


## Base count, plus one per `per_cells` of floor area, capped.
func _scaled(base: int, area: int, per_cells: int, cap: int) -> int:
	var extra := 0 if per_cells <= 0 else area / per_cells
	return clampi(base + extra, 0, cap)


func _step(role: Role, stems: Array, count: int, spacing: int = 2) -> Dictionary:
	var packed := PackedStringArray()
	for s in stems:
		var stem := String(s)
		## Skip unknown stems loudly at plan time so typos fail in tests, not silently.
		if RoomPropCatalog.find_stem(stem) < RoomPropCatalog.PROP_FIRST:
			push_error("RoomDecorator: unknown stem '%s'" % stem)
			continue
		packed.append(stem)
	return {
		"role": role,
		"stems": packed,
		"count": count,
		"spacing": spacing,
	}


func _steps(items: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item in items:
		var d: Dictionary = item
		if int(d.get("count", 0)) <= 0:
			continue
		var stems: PackedStringArray = d.get("stems", PackedStringArray())
		if stems.is_empty():
			continue
		out.append(d)
	return out


func _apply_step(
	volume: RoomVolume, step: Dictionary, blocked: Dictionary, occupied: Dictionary
) -> int:
	var role: Role = step["role"] as Role
	var stems: PackedStringArray = step["stems"]
	var count: int = int(step["count"])
	var spacing: int = int(step.get("spacing", 2))
	if stems.is_empty() or count <= 0:
		return 0

	## Floor props avoid blocked + already-placed; ceiling only avoids world geometry
	## so a lamp may hang above a table.
	var reserved: Dictionary = blocked if role == Role.CEILING else _merged(blocked, occupied)

	var slots: Array[Vector2i] = []
	match role:
		Role.CORNER:
			slots = _corner_slots(volume, reserved)
		Role.WALL:
			slots = _wall_slots(volume, reserved, spacing)
		Role.CENTER:
			slots = _center_slots(volume, reserved)
		Role.SCATTER:
			slots = _scatter_slots(volume, reserved, count * 3)
		Role.CEILING:
			## A 2 m city storey has no room for anything under its ceiling: the walker
			## would wear it. Leave those floors bare rather than hang a hazard.
			if volume.air_h < WALK_CLEAR_VOX + 1:
				return 0
			slots = _center_slots(volume, reserved)
		_:
			push_error("RoomDecorator: unknown role %s" % role)
			return 0

	if slots.is_empty():
		return 0

	_shuffle(slots)
	var placed := 0
	var guard := maxi(count * 12, slots.size())
	while placed < count and guard > 0 and not slots.is_empty():
		guard -= 1
		var stem := stems[rng.randi() % stems.size()]
		var size := RoomPropKit.size_of(stem)
		var y := volume.prop_y()
		if role == Role.CEILING:
			## Hang multi-cell-tall lamps down from the ceiling course, and only when
			## what is left below is still a corridor the walker fits through.
			y = volume.ceiling_prop_y() - size.y + 1
			if y - volume.prop_y() < WALK_CLEAR_VOX:
				continue
		var slot_i := _find_fitting_slot(volume, slots, size, y, stem, reserved)
		if slot_i < 0:
			continue
		var slot: Vector2i = slots[slot_i]
		var at := Vector3i(slot.x, y, slot.y)
		if not RoomPropKit.stamp_brush(brush, at, stem, false):
			continue
		if role != Role.CEILING:
			_mark_footprint(occupied, slot, size)
		placed += 1
	return placed


func _find_fitting_slot(
	volume: RoomVolume,
	slots: Array[Vector2i],
	size: Vector3i,
	y: int,
	stem: String,
	reserved: Dictionary
) -> int:
	for i in range(slots.size()):
		var slot: Vector2i = slots[i]
		if not _footprint_xz_free(volume, slot, size, reserved):
			continue
		var at := Vector3i(slot.x, y, slot.y)
		if RoomPropKit.can_stamp_brush(brush, volume, at, stem, false):
			return i
	return -1


func _footprint_xz_free(
	volume: RoomVolume, origin: Vector2i, size: Vector3i, reserved: Dictionary
) -> bool:
	for z in range(size.z):
		for x in range(size.x):
			var p := origin + Vector2i(x, z)
			if reserved.has(p) or volume.is_cleared(p) or not volume.contains_xz(p):
				return false
	return true


func _mark_footprint(occupied: Dictionary, origin: Vector2i, size: Vector3i) -> void:
	for z in range(size.z):
		for x in range(size.x):
			occupied[origin + Vector2i(x, z)] = true


func _merged(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = a.duplicate()
	for k in b:
		out[k] = true
	return out


func _corner_slots(volume: RoomVolume, reserved: Dictionary) -> Array[Vector2i]:
	var r := volume.rect
	var candidates: Array[Vector2i] = [
		Vector2i(r.position.x, r.position.y),
		Vector2i(r.end.x - 1, r.position.y),
		Vector2i(r.position.x, r.end.y - 1),
		Vector2i(r.end.x - 1, r.end.y - 1),
	]
	var out: Array[Vector2i] = []
	for c in candidates:
		_try_slot(c, volume, reserved, out)
	return out


func _wall_slots(volume: RoomVolume, reserved: Dictionary, spacing: int) -> Array[Vector2i]:
	var r := volume.rect
	var step := maxi(spacing, 1)
	var out: Array[Vector2i] = []
	## North / south edges (vary x).
	for x in range(r.position.x + 1, r.end.x - 1, step):
		_try_slot(Vector2i(x, r.position.y), volume, reserved, out)
		_try_slot(Vector2i(x, r.end.y - 1), volume, reserved, out)
	## West / east edges (vary z).
	for z in range(r.position.y + 1, r.end.y - 1, step):
		_try_slot(Vector2i(r.position.x, z), volume, reserved, out)
		_try_slot(Vector2i(r.end.x - 1, z), volume, reserved, out)
	return out


func _center_slots(volume: RoomVolume, reserved: Dictionary) -> Array[Vector2i]:
	var r := volume.rect
	var cx := r.position.x + r.size.x / 2
	var cz := r.position.y + r.size.y / 2
	var out: Array[Vector2i] = []
	## Prefer true center, then a small ring so a blocked center still places.
	var ring: Array[Vector2i] = [
		Vector2i(cx, cz),
		Vector2i(cx - 1, cz), Vector2i(cx + 1, cz),
		Vector2i(cx, cz - 1), Vector2i(cx, cz + 1),
	]
	for p in ring:
		_try_slot(p, volume, reserved, out)
	return out


func _scatter_slots(volume: RoomVolume, reserved: Dictionary, want: int) -> Array[Vector2i]:
	var r := volume.rect
	## Keep a one-cell apron from walls when the room is large enough.
	var inset := 1 if r.size.x >= 6 and r.size.y >= 6 else 0
	var x0 := r.position.x + inset
	var z0 := r.position.y + inset
	var x1 := r.end.x - inset
	var z1 := r.end.y - inset
	if x1 <= x0 or z1 <= z0:
		return [] as Array[Vector2i]
	var out: Array[Vector2i] = []
	var guard := want * 8
	while out.size() < want and guard > 0:
		guard -= 1
		var p := Vector2i(rng.randi_range(x0, x1 - 1), rng.randi_range(z0, z1 - 1))
		_try_slot(p, volume, reserved, out)
	return out


func _try_slot(
	p: Vector2i, volume: RoomVolume, reserved: Dictionary, out: Array[Vector2i]
) -> void:
	if reserved.has(p) or volume.is_cleared(p) or not volume.contains_xz(p):
		return
	if out.has(p):
		return
	out.append(p)


func _shuffle(items: Array[Vector2i]) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := items[i]
		items[i] = items[j]
		items[j] = tmp
