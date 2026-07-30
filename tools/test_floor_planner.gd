## Floor plans must be walkable: no orphan rooms, no rooms inside the elevator, and no
## partition voxels where the shell already stands. Covers FloorPlanner and the painter.
##
## Run: powershell -File tools\run_test.ps1 test_floor_planner
extends Node

const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const FloorMaskScript := preload("res://scripts/city/floor_mask.gd")
const FloorPlannerScript := preload("res://scripts/city/floor_planner.gd")
const FloorPlanPainterScript := preload("res://scripts/city/floor_plan_painter.gd")

## Plates the planner has to cope with: a downtown parcel, oblongs both ways, the
## smallest plate worth planning, and one under the threshold.
const PLATES: Array[Rect2i] = [
	Rect2i(-140, 96, 106, 106),
	Rect2i(0, 0, 44, 26),
	Rect2i(-30, 8, 22, 62),
	## Just over MIN_PLAN_AREA — the smallest plate that still gets partitioned.
	Rect2i(5, 5, 22, 20),
]
const TINY := Rect2i(3, 3, 12, 12)
const AIR_H := 5
const USES: Array[int] = [
	FloorPlanner.Use.OFFICE,
	FloorPlanner.Use.RESIDENTIAL,
	FloorPlanner.Use.RETAIL_OVER_OFFICE,
	FloorPlanner.Use.RETAIL_OVER_FLATS,
]


func _ready() -> void:
	var failed := false
	failed = _check_layouts(failed)
	failed = _check_tiny_plate(failed)
	failed = _check_purpose_mix(failed)
	failed = _check_determinism(failed)
	failed = _check_keep_clear(failed)
	failed = _check_mask_holes(failed)
	failed = _check_painter(failed)
	print("RESULT: %s" % ("OK" if not failed else "FAILED"))
	get_tree().quit(1 if failed else 0)


func _planner(seed_value: int) -> FloorPlanner:
	var p: FloorPlanner = FloorPlannerScript.new() as FloorPlanner
	p.rng = RandomNumberGenerator.new()
	p.rng.seed = seed_value
	return p


## Every column standable.
func _full_mask(rect: Rect2i) -> FloorMask:
	var m: FloorMask = FloorMaskScript.make(rect) as FloorMask
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			m.set_free(Vector2i(x, z), true)
	return m


func _entry_of(rect: Rect2i) -> Array[Vector2i]:
	return [rect.position + Vector2i(1, 1)] as Array[Vector2i]


func _check_layouts(failed: bool) -> bool:
	for use in USES:
		for storey in [0, 3]:
			for plate in PLATES:
				var mask := _full_mask(plate)
				var plan := _planner(7 + storey).plan(
					use as FloorPlanner.Use,
					storey,
					plate,
					AIR_H,
					mask,
					[] as Array[Rect2i],
					_entry_of(plate)
				)
				var label := "%s s%d %s" % [
					FloorPlannerScript.use_name(use as FloorPlanner.Use), storey, plate
				]
				if not plan.verify(plate):
					push_error("FAIL %s did not verify" % label)
					failed = true
					continue
				if plan.rooms.is_empty():
					push_error("FAIL %s produced no rooms" % label)
					failed = true
					continue
				for r in plan.rooms:
					if r.rect.size.x < FloorPlannerScript.MIN_ROOM_SIDE or r.rect.size.y < FloorPlannerScript.MIN_ROOM_SIDE:
						push_error("FAIL %s room %s under minimum side" % [label, r.rect])
						failed = true
				failed = _check_reachable(plan, plate, mask, label, failed)
	print("  layouts: %d uses x 2 storeys x %d plates" % [USES.size(), PLATES.size()])
	return failed


## Flood the plate through everything the plan leaves open; every room must be entered.
func _check_reachable(
	plan: FloorPlan, plate: Rect2i, mask: FloorMask, label: String, failed: bool
) -> bool:
	var blocked := _blocked_cells(plan)
	var entry := plate.position + Vector2i(1, 1)
	if blocked.has(entry):
		push_error("FAIL %s walled its own entry cell %s" % [label, entry])
		return true
	var seen: Dictionary = {entry: true}
	var queue: Array[Vector2i] = [entry]
	while not queue.is_empty():
		var p: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if seen.has(q) or not plate.has_point(q):
				continue
			if blocked.has(q) or not mask.is_free(q):
				continue
			seen[q] = true
			queue.append(q)
	for r in plan.rooms:
		if not _any_seen(r.rect, seen):
			push_error(
				"FAIL %s room %s (%s) is sealed off"
				% [label, r.rect, RoomDecorator.purpose_name(r.purpose as RoomDecorator.Purpose)]
			)
			failed = true
	for c in plan.corridors:
		if not _any_seen(c, seen):
			push_error("FAIL %s corridor %s is sealed off" % [label, c])
			failed = true
	return failed


## Wall columns the painter would actually fill: gaps stay open, and a carve reopens
## whatever the painter itself wrote.
func _blocked_cells(plan: FloorPlan) -> Dictionary:
	var blocked: Dictionary = {}
	for w in plan.walls:
		for z in range(w.rect.position.y, w.rect.end.y):
			for x in range(w.rect.position.x, w.rect.end.x):
				var p := Vector2i(x, z)
				if not w.is_gap(p):
					blocked[p] = true
	for c in plan.carves:
		for z in range(c.position.y, c.end.y):
			for x in range(c.position.x, c.end.x):
				blocked.erase(Vector2i(x, z))
	return blocked


## Link paths are cleared again after the partitions land, by design.
func _is_carved(plan: FloorPlan, p: Vector2i) -> bool:
	for c in plan.carves:
		if c.has_point(p):
			return true
	return false


func _any_seen(r: Rect2i, seen: Dictionary) -> bool:
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if seen.has(Vector2i(x, z)):
				return true
	return false


func _check_tiny_plate(failed: bool) -> bool:
	var plan := _planner(1).plan(
		FloorPlanner.Use.RESIDENTIAL,
		2,
		TINY,
		AIR_H,
		_full_mask(TINY),
		[] as Array[Rect2i],
		_entry_of(TINY)
	)
	if not plan.rooms.is_empty() or not plan.walls.is_empty():
		push_error("FAIL a %s plate must stay one open room" % TINY.size)
		failed = true
	print("  tiny plate stays open")
	return failed


## Business towers get glazed cells, flats get a kitchen and a bathroom, and the street
## storey of a retail building is a shop.
func _check_purpose_mix(failed: bool) -> bool:
	var plate := PLATES[0]
	var mask := _full_mask(plate)
	var office := _planner(3).plan(
		FloorPlanner.Use.RETAIL_OVER_OFFICE, 4, plate, AIR_H, mask, [] as Array[Rect2i],
		_entry_of(plate)
	)
	for w in office.walls:
		if w.mat != VoxelMaterial.GLASS:
			push_error("FAIL office partition is material %d, not glass" % w.mat)
			failed = true
			break
	failed = _need_purpose(office, RoomDecorator.Purpose.OFFICE, "office floor", failed)
	failed = _need_purpose(office, RoomDecorator.Purpose.MEETING_ROOM, "office floor", failed)
	failed = _need_purpose(office, RoomDecorator.Purpose.BREAK_ROOM, "office floor", failed)

	var flats := _planner(4).plan(
		FloorPlanner.Use.RESIDENTIAL, 2, plate, AIR_H, mask, [] as Array[Rect2i],
		_entry_of(plate)
	)
	failed = _need_purpose(flats, RoomDecorator.Purpose.LIVING_ROOM, "flats floor", failed)
	failed = _need_purpose(flats, RoomDecorator.Purpose.BEDROOM, "flats floor", failed)
	failed = _need_purpose(flats, RoomDecorator.Purpose.KITCHEN, "flats floor", failed)
	failed = _need_purpose(flats, RoomDecorator.Purpose.BATHROOM, "flats floor", failed)

	var shop := _planner(5).plan(
		FloorPlanner.Use.RETAIL_OVER_FLATS, 0, plate, AIR_H, mask, [] as Array[Rect2i],
		_entry_of(plate)
	)
	failed = _need_purpose(shop, RoomDecorator.Purpose.SHOP, "shop floor", failed)
	failed = _need_purpose(shop, RoomDecorator.Purpose.STORAGE, "shop floor", failed)
	print(
		"  purpose mix: office=%d flats=%d shop=%d rooms"
		% [office.rooms.size(), flats.rooms.size(), shop.rooms.size()]
	)
	return failed


func _need_purpose(plan: FloorPlan, purpose: int, label: String, failed: bool) -> bool:
	for r in plan.rooms:
		if r.purpose == purpose:
			return failed
	push_error(
		"FAIL %s has no %s"
		% [label, RoomDecorator.purpose_name(purpose as RoomDecorator.Purpose)]
	)
	return true


func _check_determinism(failed: bool) -> bool:
	var plate := PLATES[1]
	var a := _planner(11).plan(
		FloorPlanner.Use.RESIDENTIAL, 1, plate, AIR_H, _full_mask(plate),
		[] as Array[Rect2i], _entry_of(plate)
	)
	var b := _planner(11).plan(
		FloorPlanner.Use.RESIDENTIAL, 1, plate, AIR_H, _full_mask(plate),
		[] as Array[Rect2i], _entry_of(plate)
	)
	if a.rooms.size() != b.rooms.size() or a.walls.size() != b.walls.size():
		push_error("FAIL same seed gave different plans (%s vs %s)" % [a.describe(), b.describe()])
		return true
	for i in range(a.rooms.size()):
		if a.rooms[i].rect != b.rooms[i].rect or a.rooms[i].purpose != b.rooms[i].purpose:
			push_error("FAIL room %d differs between identical plans" % i)
			failed = true
	print("  determinism: %s" % a.describe())
	return failed


## The elevator enclosure owns its cells: no room may claim them.
func _check_keep_clear(failed: bool) -> bool:
	var plate := PLATES[0]
	var cabin := Rect2i(plate.position.x + 40, plate.position.y + 40, 5, 5)
	var keep: Array[Rect2i] = [cabin]
	for use in USES:
		var plan := _planner(9).plan(
			use as FloorPlanner.Use, 2, plate, AIR_H, _full_mask(plate), keep,
			[Vector2i(cabin.end.x, cabin.position.y + 2)] as Array[Vector2i]
		)
		for r in plan.rooms:
			var hit := cabin.intersection(r.rect)
			if hit.size.x * hit.size.y * 2 >= r.rect.size.x * r.rect.size.y:
				push_error(
					"FAIL %s put room %s inside the elevator %s"
					% [FloorPlannerScript.use_name(use as FloorPlanner.Use), r.rect, cabin]
				)
				failed = true
	print("  keep_clear leaves no room swallowed by the shaft")
	return failed


## A courtyard void must not become rooms, and it must not sink the whole plan either.
func _check_mask_holes(failed: bool) -> bool:
	var plate := PLATES[0]
	var mask := _full_mask(plate)
	var hole := Rect2i(plate.position.x + 30, plate.position.y + 30, 40, 40)
	for z in range(hole.position.y, hole.end.y):
		for x in range(hole.position.x, hole.end.x):
			mask.set_free(Vector2i(x, z), false)
	var plan := _planner(13).plan(
		FloorPlanner.Use.RESIDENTIAL, 1, plate, AIR_H, mask, [] as Array[Rect2i],
		_entry_of(plate)
	)
	if plan.rooms.is_empty():
		push_error("FAIL a holed plate produced no rooms at all")
		return true
	for r in plan.rooms:
		if hole.encloses(r.rect):
			push_error("FAIL room %s sits entirely in the void %s" % [r.rect, hole])
			failed = true
	print("  mask holes: %d rooms around a %s void" % [plan.rooms.size(), hole.size])
	return failed


## The painter may only add partitions where the storey is empty, and only in slices.
func _check_painter(failed: bool) -> bool:
	var plate := Rect2i(8, 8, 60, 44)
	var floor_y := 12
	var brush: CityBrush = CityBrushScript.new()
	brush.use_offline_volume()
	_build_storey(brush, plate, floor_y)
	var cabin := Rect2i(plate.position.x + 20, plate.position.y + 16, 5, 5)
	_build_elevator(brush, cabin, floor_y)

	var mask: FloorMask = FloorMaskScript.from_brush(brush, plate, floor_y, AIR_H) as FloorMask
	for z in range(cabin.position.y, cabin.end.y):
		for x in range(cabin.position.x, cabin.end.x):
			if mask.is_free(Vector2i(x, z)):
				push_error("FAIL mask thinks the elevator column %d,%d is free" % [x, z])
				failed = true
	var plan := _planner(17).plan(
		FloorPlanner.Use.OFFICE,
		3,
		plate,
		AIR_H,
		mask,
		[cabin] as Array[Rect2i],
		[Vector2i(cabin.end.x, cabin.position.y + 2)] as Array[Vector2i]
	)
	var painter: FloorPlanPainter = FloorPlanPainterScript.new() as FloorPlanPainter
	painter.brush = brush
	painter.budget = 400
	painter.begin(plan, mask, floor_y)
	var steps := 0
	var written := 0
	while not painter.is_done() and steps < 200:
		written += painter.paint_step()
		steps += 1
	if steps < 2:
		push_error("FAIL painter finished a %s plate in one budgeted step" % plate.size)
		failed = true
	if written <= 0:
		push_error("FAIL painter wrote nothing")
		return true

	## The shaft is untouched and its bay is still open.
	for z in range(cabin.position.y, cabin.end.y):
		for x in range(cabin.position.x, cabin.end.x):
			if brush.get_vox(Vector3i(x, floor_y + 1, z)) != VoxelMaterial.METAL_PLATE:
				push_error("FAIL painter breached the elevator at %d,%d" % [x, z])
				failed = true
	var glass := 0
	var gaps_open := true
	for w in plan.walls:
		for z in range(w.rect.position.y, w.rect.end.y):
			for x in range(w.rect.position.x, w.rect.end.x):
				var p := Vector2i(x, z)
				var id := brush.get_vox(Vector3i(x, floor_y + 1, z))
				if w.is_gap(p):
					if id != VoxelMaterial.AIR:
						gaps_open = false
					continue
				if not mask.is_free(p) or _is_carved(plan, p):
					continue
				if id == VoxelMaterial.GLASS:
					glass += 1
				else:
					push_error("FAIL wall cell %s is %d, not glass" % [p, id])
					failed = true
	if not gaps_open:
		push_error("FAIL a door gap was painted shut")
		failed = true
	if glass <= 0:
		push_error("FAIL no glass partition landed")
		failed = true
	print("  painter: %d steps, %d voxels, %d glass cells" % [steps, written, glass])
	return failed


## Floor slab, clear band, ceiling — the shape BuildingGrammar._fill_shell leaves behind.
func _build_storey(brush: CityBrush, plate: Rect2i, floor_y: int) -> void:
	var outer := plate.grow(1)
	brush.fill_box(
		Vector3i(outer.position.x, floor_y - 1, outer.position.y),
		Vector3i(outer.end.x, floor_y + AIR_H + 2, outer.end.y),
		VoxelMaterial.CONCRETE
	)
	brush.fill_box(
		Vector3i(plate.position.x, floor_y + 1, plate.position.y),
		Vector3i(plate.end.x, floor_y + AIR_H + 1, plate.end.y),
		VoxelMaterial.AIR
	)


func _build_elevator(brush: CityBrush, cabin: Rect2i, floor_y: int) -> void:
	brush.fill_box(
		Vector3i(cabin.position.x, floor_y + 1, cabin.position.y),
		Vector3i(cabin.end.x, floor_y + AIR_H + 1, cabin.end.y),
		VoxelMaterial.METAL_PLATE
	)
