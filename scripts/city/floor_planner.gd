## Cuts one storey plate into purpose-driven rooms.
##
## Pure geometry: no brush, no voxels. FloorMask says which columns exist (courtyard
## voids, punched sky holes, shaft walls), `keep_clear` says which must stay untouched
## (elevator cabins), and `entries` are cells the layout has to stay connected to
## (elevator bay, street door apron). FloorPlanPainter turns the result into voxels.
class_name FloorPlanner
extends RefCounted

## What a building is for. Decided per lot at bake (DistrictGenerator._building_use_for).
enum Use {
	OFFICE,
	RESIDENTIAL,
	## Shop floor at street level, offices above.
	RETAIL_OVER_OFFICE,
	## Shop floor at street level, flats above.
	RETAIL_OVER_FLATS,
}

## Which generator runs for one storey of a use.
enum Layout {
	OFFICE,
	FLATS,
	SHOP,
}

## Below this a storey stays one room — a 7 m plate has no room for corridors.
const MIN_PLAN_SIDE := 16
const MIN_PLAN_AREA := 400
## Circulation width in voxels (2 m).
const CORRIDOR_W := 4
## Door gap along a partition, in voxels (1.5 m).
const DOOR_W := 3
## Smallest sub-room side. RoomDecorator.decorate rejects anything under 3.
const MIN_ROOM_SIDE := 4
## Depth of the cellular office band off the façade, wall line included.
const OFFICE_BAND_MAX := 11
## Target flat frontage along the corridor (9 m), and office cell width (7 m).
const FLAT_TARGET_W := 18
const OFFICE_CELL_W := 14

var rng: RandomNumberGenerator


func plan(
	use: Use,
	storey: int,
	rect: Rect2i,
	air_h: int,
	mask: FloorMask,
	keep_clear: Array[Rect2i],
	entries: Array[Vector2i]
) -> FloorPlan:
	if rng == null:
		push_error("FloorPlanner.plan: rng is null")
		return FloorPlan.new()
	if mask == null:
		push_error("FloorPlanner.plan: mask is null")
		return FloorPlan.new()
	if mask.rect != rect:
		push_error("FloorPlanner.plan: mask %s does not cover plate %s" % [mask.rect, rect])
		return FloorPlan.new()
	var out := FloorPlan.new()
	out.air_h = air_h
	if not _worth_planning(rect, mask):
		return out
	match _layout_for(use, storey):
		Layout.OFFICE:
			_plan_office(out, rect, mask, keep_clear, entries)
		Layout.FLATS:
			_plan_flats(out, rect, mask, keep_clear, entries)
		Layout.SHOP:
			_plan_shop(out, rect, mask, keep_clear, entries)
	if out.rooms.is_empty():
		## Nothing survived the mask / keep_clear filters: leave the storey open rather
		## than painting partitions that fence off an empty floor.
		out.walls.clear()
		out.corridors.clear()
		out.carves.clear()
		return out
	out.verify(rect)
	return out


func _layout_for(use: Use, storey: int) -> Layout:
	match use:
		Use.OFFICE:
			return Layout.OFFICE
		Use.RESIDENTIAL:
			return Layout.FLATS
		Use.RETAIL_OVER_OFFICE:
			return Layout.SHOP if storey == 0 else Layout.OFFICE
		Use.RETAIL_OVER_FLATS:
			return Layout.SHOP if storey == 0 else Layout.FLATS
	push_error("FloorPlanner: unknown use %d" % use)
	return Layout.OFFICE


static func use_name(use: Use) -> String:
	match use:
		Use.OFFICE:
			return "office"
		Use.RESIDENTIAL:
			return "residential"
		Use.RETAIL_OVER_OFFICE:
			return "retail_over_office"
		Use.RETAIL_OVER_FLATS:
			return "retail_over_flats"
	return "unknown"


## Too small, too thin, or too holed to carry corridors and cells.
func _worth_planning(rect: Rect2i, mask: FloorMask) -> bool:
	if mini(rect.size.x, rect.size.y) < MIN_PLAN_SIDE:
		return false
	if rect.size.x * rect.size.y < MIN_PLAN_AREA:
		return false
	return mask.free_count() >= MIN_PLAN_AREA


# ---------------------------------------------------------------- office floors


## Cellular offices in a band along the façade, a ring corridor behind them, meeting
## rooms at the corners, break room and bathroom beside the core. Partitions are glass.
func _plan_office(
	out: FloorPlan,
	rect: Rect2i,
	mask: FloorMask,
	keep_clear: Array[Rect2i],
	entries: Array[Vector2i]
) -> void:
	var band := clampi(mini(rect.size.x, rect.size.y) / 4, MIN_ROOM_SIDE + 1, OFFICE_BAND_MAX)
	var ring := rect.grow(-band)
	var core := ring.grow(-(CORRIDOR_W + 1))
	if core.size.x < MIN_ROOM_SIDE or core.size.y < MIN_ROOM_SIDE:
		_plan_open_with_box(out, rect, mask, keep_clear, entries, VoxelMaterial.GLASS)
		return
	var arms: Array[Rect2i] = [
		Rect2i(ring.position.x, ring.position.y, ring.size.x, CORRIDOR_W),
		Rect2i(ring.position.x, core.end.y + 1, ring.size.x, CORRIDOR_W),
		Rect2i(ring.position.x, core.position.y, CORRIDOR_W, core.size.y),
		Rect2i(core.end.x + 1, core.position.y, CORRIDOR_W, core.size.y),
	]
	for arm in arms:
		out.corridors.append(arm)
	_cut_perimeter_band(out, rect, ring, mask, keep_clear, VoxelMaterial.GLASS)
	_cut_core(out, core, mask, keep_clear, VoxelMaterial.GLASS)
	_connect_entries(out, arms, entries)


## Perimeter cells between the plate edge and the ring corridor, on all four sides.
func _cut_perimeter_band(
	out: FloorPlan,
	rect: Rect2i,
	ring: Rect2i,
	mask: FloorMask,
	keep_clear: Array[Rect2i],
	mat: int
) -> void:
	## North and south run the full width; west and east fill what is left between them.
	var strips: Array[Rect2i] = [
		Rect2i(rect.position.x, rect.position.y, rect.size.x, ring.position.y - rect.position.y - 1),
		Rect2i(rect.position.x, ring.end.y + 1, rect.size.x, rect.end.y - ring.end.y - 1),
		Rect2i(rect.position.x, ring.position.y, ring.position.x - rect.position.x - 1, ring.size.y),
		Rect2i(ring.end.x + 1, ring.position.y, rect.end.x - ring.end.x - 1, ring.size.y),
	]
	for i in range(strips.size()):
		var strip: Rect2i = strips[i]
		if strip.size.x < MIN_ROOM_SIDE or strip.size.y < MIN_ROOM_SIDE:
			continue
		var horizontal := i < 2
		var cells := _slice_strip(strip, horizontal, OFFICE_CELL_W)
		for c in range(cells.size()):
			if c > 0:
				_add_split_wall(out, cells[c - 1], cells[c], mat)
			var at_end := c == 0 or c == cells.size() - 1
			_add_room(
				out,
				cells[c],
				(
					RoomDecorator.Purpose.MEETING_ROOM
					if at_end and cells.size() > 2
					else RoomDecorator.Purpose.OFFICE
				),
				mask,
				keep_clear
			)
		_add_band_wall(out, strip, ring, mat, cells)


## Break room and bathroom sliced off one end of the core; the rest stays open plan.
func _cut_core(
	out: FloorPlan, core: Rect2i, mask: FloorMask, keep_clear: Array[Rect2i], mat: int
) -> void:
	_add_core_ring_walls(out, core, mat)
	var along_x := core.size.x >= core.size.y
	var service := mini(12, (core.size.x if along_x else core.size.y) / 3)
	if service < MIN_ROOM_SIDE:
		_add_room(out, core, RoomDecorator.Purpose.OFFICE, mask, keep_clear)
		return
	var svc: Rect2i
	var open: Rect2i
	if along_x:
		svc = Rect2i(core.position.x, core.position.y, service, core.size.y)
		open = Rect2i(
			core.position.x + service + 1, core.position.y, core.size.x - service - 1, core.size.y
		)
	else:
		svc = Rect2i(core.position.x, core.position.y, core.size.x, service)
		open = Rect2i(
			core.position.x, core.position.y + service + 1, core.size.x, core.size.y - service - 1
		)
	_add_split_wall(out, svc, open, mat)
	var halves := _split_rect(svc, not along_x)
	if halves.size() == 2:
		_add_split_wall(out, halves[0], halves[1], mat)
		_add_room(out, halves[0], RoomDecorator.Purpose.BREAK_ROOM, mask, keep_clear)
		_add_room(out, halves[1], RoomDecorator.Purpose.BATHROOM, mask, keep_clear)
	else:
		_add_room(out, svc, RoomDecorator.Purpose.BREAK_ROOM, mask, keep_clear)
	_add_room(out, open, RoomDecorator.Purpose.OFFICE, mask, keep_clear)


## Four walls closing the core off from the ring corridor, one door each. The service
## strip sits at one end, so the door on that side serves it and the far one the open plan.
func _add_core_ring_walls(out: FloorPlan, core: Rect2i, mat: int) -> void:
	var ring_walls: Array[Rect2i] = [
		Rect2i(core.position.x - 1, core.position.y - 1, core.size.x + 2, 1),
		Rect2i(core.position.x - 1, core.end.y, core.size.x + 2, 1),
		Rect2i(core.position.x - 1, core.position.y, 1, core.size.y),
		Rect2i(core.end.x, core.position.y, 1, core.size.y),
	]
	for w in ring_walls:
		out.add_wall(w, mat, _centred_gap(w))


## Shallow plate: one open floor with a glazed meeting box in a corner.
func _plan_open_with_box(
	out: FloorPlan,
	rect: Rect2i,
	mask: FloorMask,
	keep_clear: Array[Rect2i],
	entries: Array[Vector2i],
	mat: int
) -> void:
	var box_w := clampi(rect.size.x / 3, MIN_ROOM_SIDE, 12)
	var box_d := clampi(rect.size.y / 3, MIN_ROOM_SIDE, 12)
	var rest := Rect2i(
		rect.position.x, rect.position.y + box_d + 1, rect.size.x, rect.size.y - box_d - 1
	)
	if rest.size.y < MIN_ROOM_SIDE or rect.size.x - box_w - 1 < MIN_ROOM_SIDE:
		_add_room(out, rect, RoomDecorator.Purpose.OFFICE, mask, keep_clear)
		return
	var box := Rect2i(rect.position.x, rect.position.y, box_w, box_d)
	var strip := Rect2i(
		rect.position.x + box_w + 1, rect.position.y, rect.size.x - box_w - 1, box_d
	)
	_add_split_wall(out, box, strip, mat)
	_add_band_wall(
		out,
		Rect2i(rect.position.x, rect.position.y, rect.size.x, box_d),
		rest,
		mat,
		[box, strip] as Array[Rect2i]
	)
	_add_room(out, box, RoomDecorator.Purpose.MEETING_ROOM, mask, keep_clear)
	_add_room(out, strip, RoomDecorator.Purpose.OFFICE, mask, keep_clear)
	_add_room(out, rest, RoomDecorator.Purpose.OFFICE, mask, keep_clear)
	## The open plan doubles as circulation here — it is a room, not a corridor record.
	_connect_entries(out, [rest] as Array[Rect2i], entries)


# ------------------------------------------------------------ residential floors


## Double-loaded corridor down the long axis with flats either side.
func _plan_flats(
	out: FloorPlan,
	rect: Rect2i,
	mask: FloorMask,
	keep_clear: Array[Rect2i],
	entries: Array[Vector2i]
) -> void:
	var along_x := rect.size.x >= rect.size.y
	var depth := rect.size.y if along_x else rect.size.x
	var side := (depth - CORRIDOR_W - 2) / 2
	if side < MIN_ROOM_SIDE:
		_plan_single_loaded(out, rect, mask, keep_clear, entries, along_x)
		return
	var corridor: Rect2i
	var near: Rect2i
	var far: Rect2i
	if along_x:
		near = Rect2i(rect.position.x, rect.position.y, rect.size.x, side)
		corridor = Rect2i(rect.position.x, near.end.y + 1, rect.size.x, CORRIDOR_W)
		far = Rect2i(
			rect.position.x, corridor.end.y + 1, rect.size.x, rect.end.y - corridor.end.y - 1
		)
	else:
		near = Rect2i(rect.position.x, rect.position.y, side, rect.size.y)
		corridor = Rect2i(near.end.x + 1, rect.position.y, CORRIDOR_W, rect.size.y)
		far = Rect2i(
			corridor.end.x + 1, rect.position.y, rect.end.x - corridor.end.x - 1, rect.size.y
		)
	out.corridors.append(corridor)
	## `near` sits on the low side, so its corridor edge is the high one, and vice versa.
	_cut_flat_row(out, near, corridor, mask, keep_clear, along_x, false)
	_cut_flat_row(out, far, corridor, mask, keep_clear, along_x, true)
	_connect_entries(out, [corridor] as Array[Rect2i], entries)


## Shallow plate: corridor along one façade, flats on the other side only.
func _plan_single_loaded(
	out: FloorPlan,
	rect: Rect2i,
	mask: FloorMask,
	keep_clear: Array[Rect2i],
	entries: Array[Vector2i],
	along_x: bool
) -> void:
	var corridor: Rect2i
	var row: Rect2i
	if along_x:
		corridor = Rect2i(rect.position.x, rect.position.y, rect.size.x, CORRIDOR_W)
		row = Rect2i(
			rect.position.x, corridor.end.y + 1, rect.size.x, rect.end.y - corridor.end.y - 1
		)
	else:
		corridor = Rect2i(rect.position.x, rect.position.y, CORRIDOR_W, rect.size.y)
		row = Rect2i(
			corridor.end.x + 1, rect.position.y, rect.end.x - corridor.end.x - 1, rect.size.y
		)
	if row.size.x < MIN_ROOM_SIDE or row.size.y < MIN_ROOM_SIDE:
		_add_room(out, rect, RoomDecorator.Purpose.LIVING_ROOM, mask, keep_clear)
		return
	out.corridors.append(corridor)
	_cut_flat_row(out, row, corridor, mask, keep_clear, along_x, true)
	_connect_entries(out, [corridor] as Array[Rect2i], entries)


## One side of the corridor: party walls every 14–22 voxels, each flat sliced inside.
func _cut_flat_row(
	out: FloorPlan,
	row: Rect2i,
	corridor: Rect2i,
	mask: FloorMask,
	keep_clear: Array[Rect2i],
	along_x: bool,
	corridor_at_low: bool
) -> void:
	if row.size.x < MIN_ROOM_SIDE or row.size.y < MIN_ROOM_SIDE:
		return
	var flats := _slice_strip(row, along_x, FLAT_TARGET_W)
	var entrances: Array[Rect2i] = []
	for i in range(flats.size()):
		if i > 0:
			_add_split_wall(out, flats[i - 1], flats[i], VoxelMaterial.BRICK)
		entrances.append(
			_cut_flat(out, flats[i], mask, keep_clear, along_x, corridor_at_low)
		)
	_add_band_wall(out, row, corridor, VoxelMaterial.BRICK, entrances)


## Kitchen and bathroom against the corridor, living room and bedroom on the façade.
## Returns the part of the flat the corridor door opens into.
func _cut_flat(
	out: FloorPlan,
	flat: Rect2i,
	mask: FloorMask,
	keep_clear: Array[Rect2i],
	along_x: bool,
	corridor_at_low: bool
) -> Rect2i:
	var depth := flat.size.y if along_x else flat.size.x
	var service := clampi(depth / 3, MIN_ROOM_SIDE, 10)
	if depth < service + MIN_ROOM_SIDE + 1:
		_add_room(out, flat, RoomDecorator.Purpose.LIVING_ROOM, mask, keep_clear)
		return flat
	var back: Rect2i  ## Corridor side: hall, kitchen, bathroom.
	var front: Rect2i  ## Façade side: living room and bedroom.
	if along_x:
		if corridor_at_low:
			back = Rect2i(flat.position.x, flat.position.y, flat.size.x, service)
			front = Rect2i(
				flat.position.x, back.end.y + 1, flat.size.x, flat.size.y - service - 1
			)
		else:
			front = Rect2i(flat.position.x, flat.position.y, flat.size.x, flat.size.y - service - 1)
			back = Rect2i(flat.position.x, front.end.y + 1, flat.size.x, service)
	else:
		if corridor_at_low:
			back = Rect2i(flat.position.x, flat.position.y, service, flat.size.y)
			front = Rect2i(
				back.end.x + 1, flat.position.y, flat.size.x - service - 1, flat.size.y
			)
		else:
			front = Rect2i(flat.position.x, flat.position.y, flat.size.x - service - 1, flat.size.y)
			back = Rect2i(front.end.x + 1, flat.position.y, service, flat.size.y)
	_add_split_wall(out, back, front, VoxelMaterial.PLASTER)
	var service_parts := _split_rect(back, along_x)
	if service_parts.size() == 2:
		_add_split_wall(out, service_parts[0], service_parts[1], VoxelMaterial.PLASTER)
		_add_room(out, service_parts[0], RoomDecorator.Purpose.KITCHEN, mask, keep_clear)
		_add_room(out, service_parts[1], RoomDecorator.Purpose.BATHROOM, mask, keep_clear)
	else:
		_add_room(out, back, RoomDecorator.Purpose.KITCHEN, mask, keep_clear)
	var living_parts := _split_rect(front, along_x)
	if living_parts.size() == 2:
		_add_split_wall(out, living_parts[0], living_parts[1], VoxelMaterial.PLASTER)
		_add_room(out, living_parts[0], RoomDecorator.Purpose.LIVING_ROOM, mask, keep_clear)
		_add_room(out, living_parts[1], RoomDecorator.Purpose.BEDROOM, mask, keep_clear)
	else:
		_add_room(out, front, RoomDecorator.Purpose.LIVING_ROOM, mask, keep_clear)
	return back


# ------------------------------------------------------------------ shop floors


## Street level: open shop, reception beside it, storage at the back.
func _plan_shop(
	out: FloorPlan,
	rect: Rect2i,
	mask: FloorMask,
	keep_clear: Array[Rect2i],
	entries: Array[Vector2i]
) -> void:
	var along_x := rect.size.x >= rect.size.y
	var depth := rect.size.y if along_x else rect.size.x
	var back := clampi(depth / 4, MIN_ROOM_SIDE, 12)
	var store: Rect2i
	var shop: Rect2i
	if along_x:
		store = Rect2i(rect.position.x, rect.position.y, rect.size.x, back)
		shop = Rect2i(rect.position.x, store.end.y + 1, rect.size.x, rect.size.y - back - 1)
	else:
		store = Rect2i(rect.position.x, rect.position.y, back, rect.size.y)
		shop = Rect2i(store.end.x + 1, rect.position.y, rect.size.x - back - 1, rect.size.y)
	if shop.size.x < MIN_ROOM_SIDE or shop.size.y < MIN_ROOM_SIDE:
		_add_room(out, rect, RoomDecorator.Purpose.SHOP, mask, keep_clear)
		return
	var parts := _split_rect(store, along_x)
	if parts.size() == 2:
		_add_split_wall(out, parts[0], parts[1], VoxelMaterial.PLASTER)
		_add_room(out, parts[0], RoomDecorator.Purpose.STORAGE, mask, keep_clear)
		_add_room(out, parts[1], RoomDecorator.Purpose.RECEPTION, mask, keep_clear)
		_add_band_wall(out, store, shop, VoxelMaterial.PLASTER, parts)
	else:
		_add_room(out, store, RoomDecorator.Purpose.STORAGE, mask, keep_clear)
		_add_band_wall(out, store, shop, VoxelMaterial.PLASTER, [store] as Array[Rect2i])
	_add_room(out, shop, RoomDecorator.Purpose.SHOP, mask, keep_clear)
	## The sales floor is the circulation on a shop storey — a room, not a corridor record.
	_connect_entries(out, [shop] as Array[Rect2i], entries)


# ----------------------------------------------------------------------- pieces


## Chop a band into cells of roughly `want_w` along its long axis, leaving a 1-cell wall
## line between neighbours.
func _slice_strip(strip: Rect2i, horizontal: bool, want_w: int) -> Array[Rect2i]:
	var span := strip.size.x if horizontal else strip.size.y
	var parts := clampi(
		int(round(float(span) / float(maxi(want_w, MIN_ROOM_SIDE)))), 1, 12
	)
	var out: Array[Rect2i] = []
	if parts <= 1:
		out.append(strip)
		return out
	var step := span / parts
	var at := 0
	for i in range(parts):
		var len_i := step - 1 if i < parts - 1 else span - at
		if len_i < MIN_ROOM_SIDE:
			break
		if horizontal:
			out.append(Rect2i(strip.position.x + at, strip.position.y, len_i, strip.size.y))
		else:
			out.append(Rect2i(strip.position.x, strip.position.y + at, strip.size.x, len_i))
		at += len_i + 1
	if out.is_empty():
		out.append(strip)
	return out


## Halve a rect, leaving a 1-cell wall line. Empty when the halves would be too small.
func _split_rect(r: Rect2i, across_x: bool) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	var horizontal := across_x if absi(r.size.x - r.size.y) < 4 else r.size.x > r.size.y
	if horizontal:
		var w := (r.size.x - 1) / 2
		if w < MIN_ROOM_SIDE or r.size.x - w - 1 < MIN_ROOM_SIDE:
			return out
		out.append(Rect2i(r.position.x, r.position.y, w, r.size.y))
		out.append(Rect2i(r.position.x + w + 1, r.position.y, r.size.x - w - 1, r.size.y))
	else:
		var d := (r.size.y - 1) / 2
		if d < MIN_ROOM_SIDE or r.size.y - d - 1 < MIN_ROOM_SIDE:
			return out
		out.append(Rect2i(r.position.x, r.position.y, r.size.x, d))
		out.append(Rect2i(r.position.x, r.position.y + d + 1, r.size.x, r.size.y - d - 1))
	return out


## The 1-cell line two split rects left between them, with one centred door.
func _add_split_wall(out: FloorPlan, a: Rect2i, b: Rect2i, mat: int) -> void:
	var wall := _line_between(a, b)
	if wall.size.x <= 0 or wall.size.y <= 0:
		push_error("FloorPlanner._add_split_wall: %s and %s are not split apart" % [a, b])
		return
	out.add_wall(wall, mat, _centred_gap(wall))


## The line between a band and the circulation behind it, with one door per `cells` entry.
func _add_band_wall(
	out: FloorPlan, band: Rect2i, corridor: Rect2i, mat: int, cells: Array[Rect2i]
) -> void:
	var wall := _band_wall_rect(band, corridor)
	if wall.size.x <= 0 or wall.size.y <= 0:
		push_error(
			"FloorPlanner._add_band_wall: band %s does not face corridor %s" % [band, corridor]
		)
		return
	var gaps: Array[Rect2i] = []
	for cell in cells:
		var g := _gap_facing(wall, cell)
		if g.size.x > 0 and g.size.y > 0:
			gaps.append(g)
	if gaps.is_empty():
		gaps = _centred_gap(wall)
	out.add_wall(wall, mat, gaps)


## Wall closing a band off from the circulation it faces. Spans the whole band, so the
## corners of a perimeter ring are sealed too, not just the part facing the corridor.
func _band_wall_rect(band: Rect2i, corridor: Rect2i) -> Rect2i:
	if band.end.y + 1 == corridor.position.y:
		return Rect2i(band.position.x, band.end.y, band.size.x, 1)
	if corridor.end.y + 1 == band.position.y:
		return Rect2i(band.position.x, corridor.end.y, band.size.x, 1)
	if band.end.x + 1 == corridor.position.x:
		return Rect2i(band.end.x, band.position.y, 1, band.size.y)
	if corridor.end.x + 1 == band.position.x:
		return Rect2i(corridor.end.x, band.position.y, 1, band.size.y)
	return Rect2i()


## The 1-cell gap between two rects that were split apart along one axis.
func _line_between(a: Rect2i, b: Rect2i) -> Rect2i:
	if a.end.x + 1 == b.position.x:
		return Rect2i(a.end.x, maxi(a.position.y, b.position.y), 1, _overlap_z(a, b))
	if b.end.x + 1 == a.position.x:
		return Rect2i(b.end.x, maxi(a.position.y, b.position.y), 1, _overlap_z(a, b))
	if a.end.y + 1 == b.position.y:
		return Rect2i(maxi(a.position.x, b.position.x), a.end.y, _overlap_x(a, b), 1)
	if b.end.y + 1 == a.position.y:
		return Rect2i(maxi(a.position.x, b.position.x), b.end.y, _overlap_x(a, b), 1)
	return Rect2i()


func _overlap_x(a: Rect2i, b: Rect2i) -> int:
	return maxi(mini(a.end.x, b.end.x) - maxi(a.position.x, b.position.x), 0)


func _overlap_z(a: Rect2i, b: Rect2i) -> int:
	return maxi(mini(a.end.y, b.end.y) - maxi(a.position.y, b.position.y), 0)


func _centred_gap(wall: Rect2i) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	if wall.size.x == 1:
		var h := mini(DOOR_W, wall.size.y)
		out.append(Rect2i(wall.position.x, wall.position.y + (wall.size.y - h) / 2, 1, h))
	else:
		var w := mini(DOOR_W, wall.size.x)
		out.append(Rect2i(wall.position.x + (wall.size.x - w) / 2, wall.position.y, w, 1))
	return out


## A door in `wall` centred on the part of `cell` that faces it.
func _gap_facing(wall: Rect2i, cell: Rect2i) -> Rect2i:
	if wall.size.x == 1:
		var lo := maxi(wall.position.y, cell.position.y)
		var hi := mini(wall.end.y, cell.end.y)
		var h := mini(DOOR_W, hi - lo)
		if h < 1:
			return Rect2i()
		return Rect2i(wall.position.x, lo + (hi - lo - h) / 2, 1, h)
	var x_lo := maxi(wall.position.x, cell.position.x)
	var x_hi := mini(wall.end.x, cell.end.x)
	var w := mini(DOOR_W, x_hi - x_lo)
	if w < 1:
		return Rect2i()
	return Rect2i(x_lo + (x_hi - x_lo - w) / 2, wall.position.y, w, 1)


## Clear a path from every entry cell to the nearest circulation rect, so the elevator
## bay and the street door always reach the plan.
func _connect_entries(out: FloorPlan, corridors: Array[Rect2i], entries: Array[Vector2i]) -> void:
	for e in entries:
		var best := Rect2i()
		var best_d := 1 << 30
		for c in corridors:
			if c.has_point(e):
				best_d = -1
				break
			var p := _closest_point(c, e)
			var d := absi(p.x - e.x) + absi(p.y - e.y)
			if d < best_d:
				best_d = d
				best = c
		if best_d < 0 or best.size.x <= 0:
			continue
		out.add_link(e, _closest_point(best, e))


func _closest_point(r: Rect2i, p: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(p.x, r.position.x, r.end.x - 1), clampi(p.y, r.position.y, r.end.y - 1)
	)


func _add_room(
	out: FloorPlan, r: Rect2i, purpose: int, mask: FloorMask, keep_clear: Array[Rect2i]
) -> void:
	if r.size.x < MIN_ROOM_SIDE or r.size.y < MIN_ROOM_SIDE:
		return
	if _blocked_by(r, keep_clear):
		return
	if not _mask_ok(r, mask):
		return
	out.add_room(r, purpose)


## A shaft clipping a corner is fine — the decorator skips those columns anyway. A shaft
## eating half the room is not: what is left is a slot, not a room.
func _blocked_by(r: Rect2i, keep_clear: Array[Rect2i]) -> bool:
	var taken := 0
	for c in keep_clear:
		var hit := c.intersection(r)
		taken += hit.size.x * hit.size.y
	return taken * 2 >= r.size.x * r.size.y


## At least two thirds of the columns must be standable, else the "room" is mostly a
## courtyard void, a punched sky hole, or a stair well.
func _mask_ok(r: Rect2i, mask: FloorMask) -> bool:
	return mask.free_count_in(r) * 3 >= r.size.x * r.size.y * 2
