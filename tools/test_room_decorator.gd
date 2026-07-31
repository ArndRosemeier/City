## Offline smoke: decorate empty room volumes for every purpose and assert props land.
##
## Run: Godot --headless --path . -s res://tools/test_room_decorator.gd
extends SceneTree

const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const RoomVolumeScript := preload("res://scripts/city/room_volume.gd")
const RoomDecoratorScript := preload("res://scripts/city/room_decorator.gd")
const RoomPropKitScript := preload("res://scripts/city/room_prop_kit.gd")
const RoomPropCatalogScript := preload("res://scripts/city/room_prop_catalog.gd")
const CastleFloorScript := preload("res://scripts/city/castle_floor.gd")
const CastleVaultScript := preload("res://scripts/city/castle_vault.gd")


func _initialize() -> void:
	var failed := false
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	failed = _check_factories(failed)
	failed = _check_purpose_names(failed)
	failed = _check_arena_labyrinth(rng, failed)
	failed = _check_bed_footprint(failed)

	var purposes: Array[int] = [
		RoomDecoratorScript.Purpose.LIVING_ROOM,
		RoomDecoratorScript.Purpose.BEDROOM,
		RoomDecoratorScript.Purpose.OFFICE,
		RoomDecoratorScript.Purpose.KITCHEN,
		RoomDecoratorScript.Purpose.BATHROOM,
		RoomDecoratorScript.Purpose.DINING_ROOM,
		RoomDecoratorScript.Purpose.STORAGE,
		RoomDecoratorScript.Purpose.LIBRARY,
		RoomDecoratorScript.Purpose.TAVERN,
		RoomDecoratorScript.Purpose.THRONE_HALL,
		RoomDecoratorScript.Purpose.DUNGEON_CHAMBER,
		RoomDecoratorScript.Purpose.DUNGEON_CELL,
		RoomDecoratorScript.Purpose.ARMORY,
		RoomDecoratorScript.Purpose.WORKSHOP,
		RoomDecoratorScript.Purpose.GENERIC,
		RoomDecoratorScript.Purpose.RECEPTION,
		RoomDecoratorScript.Purpose.MEETING_ROOM,
		RoomDecoratorScript.Purpose.BREAK_ROOM,
		RoomDecoratorScript.Purpose.CORRIDOR,
		RoomDecoratorScript.Purpose.SHOP,
	]
	for purpose in purposes:
		failed = _check_purpose(purpose, rng, failed)

	failed = _check_ceiling_clearance(failed)
	failed = _check_keep_clear(rng, failed)
	failed = _check_opening_apron(rng, failed)
	failed = _check_preserves_stairs(rng, failed)
	failed = _check_tiny_room(rng, failed)

	print("RESULT: %s" % ("OK" if not failed else "FAILED"))
	quit(1 if failed else 0)


func _make_decorator(rng: RandomNumberGenerator) -> RefCounted:
	var brush: CityBrush = CityBrushScript.new()
	brush.use_offline_volume()
	var dec: RoomDecorator = RoomDecoratorScript.new()
	dec.brush = brush
	dec.rng = rng
	return dec


func _shell_room(brush: CityBrush, volume: RoomVolume) -> void:
	## Slab + walls around the interior rect (outside rect), air inside.
	var r := volume.rect
	brush.fill_box(
		Vector3i(r.position.x - 1, volume.floor_y, r.position.y - 1),
		Vector3i(r.end.x + 1, volume.floor_y + 1, r.end.y + 1),
		VoxelMaterial.STONE
	)
	brush.fill_box(
		Vector3i(r.position.x - 1, volume.floor_y + 1, r.position.y - 1),
		Vector3i(r.end.x + 1, volume.floor_y + volume.air_h + 1, r.end.y + 1),
		VoxelMaterial.STONE
	)
	brush.fill_box(volume.air_min(), volume.air_max(), VoxelMaterial.AIR)


## Count origin mesh voxels only (not PROP_FOOTPRINT fillers).
func _count_props(brush: CityBrush, volume: RoomVolume) -> int:
	var n := 0
	var a := volume.air_min()
	var b := volume.air_max()
	for y in range(a.y, b.y):
		for z in range(a.z, b.z):
			for x in range(a.x, b.x):
				if VoxelMaterial.is_room_prop(brush.get_vox(Vector3i(x, y, z))):
					n += 1
	return n


func _check_bed_footprint(failed: bool) -> bool:
	var bed: Vector3i = RoomPropCatalogScript.size_of_stem("bedSingle")
	if bed.x < 2 or bed.z < 3:
		push_error("FAIL bedSingle footprint too small: %s (expected multi-cell)" % bed)
		failed = true
	var brush: CityBrush = CityBrushScript.new()
	brush.use_offline_volume()
	var volume: RoomVolume = RoomVolumeScript.make(Rect2i(0, 0, 16, 16), 0, 6)
	_shell_room(brush, volume)
	var origin := Vector3i(2, volume.prop_y(), 2)
	if not RoomPropKitScript.stamp_brush(brush, origin, "bedSingle", false):
		push_error("FAIL bedSingle stamp failed")
		return true
	if brush.get_vox(origin) != RoomPropCatalogScript.id_for_stem("bedSingle"):
		push_error("FAIL bedSingle origin is not the mesh id")
		failed = true
	var cells := 0
	for off in RoomPropKitScript.recipe_cells("bedSingle"):
		var id := brush.get_vox(origin + off)
		if not VoxelMaterial.is_prop_furniture(id):
			push_error("FAIL bed footprint cell empty at %s" % (origin + off))
			failed = true
		cells += 1
	if cells != bed.x * bed.y * bed.z:
		push_error("FAIL bed cell count %d != %d" % [cells, bed.x * bed.y * bed.z])
		failed = true
	print("  bedSingle footprint: %s (%d cells)" % [bed, cells])
	return failed


func _check_factories(failed: bool) -> bool:
	var floor: CastleFloor = CastleFloorScript.new()
	floor.storey = 1
	floor.floor_y = 10
	floor.air_h = 7
	var room := Rect2i(4, 4, 12, 10)
	var from_keep: RoomVolume = RoomVolumeScript.from_keep_room(floor, room, true)
	if from_keep.floor_y != 10 or from_keep.air_h != 7 or from_keep.rect != room or not from_keep.is_hall:
		push_error("FAIL from_keep_room fields mismatch")
		failed = true

	var vault: CastleVault = CastleVaultScript.new()
	vault.rect = Rect2i(0, 0, 20, 16)
	vault.floor_y = 2
	vault.air_h = 9
	vault.level = 0
	vault.span_levels = 2
	var from_vault: RoomVolume = RoomVolumeScript.from_vault(vault)
	if from_vault.air_h != 9 or from_vault.prop_y() != 3 or not from_vault.is_hall:
		push_error("FAIL from_vault fields mismatch")
		failed = true
	return failed


func _check_purpose_names(failed: bool) -> bool:
	if RoomDecoratorScript.purpose_from_name("living_room") != RoomDecoratorScript.Purpose.LIVING_ROOM:
		push_error("FAIL purpose_from_name living_room")
		failed = true
	if RoomDecoratorScript.purpose_from_name("dungeon_cell") != RoomDecoratorScript.Purpose.DUNGEON_CELL:
		push_error("FAIL purpose_from_name dungeon_cell")
		failed = true
	if RoomDecoratorScript.purpose_name(RoomDecoratorScript.Purpose.ARMORY) != "armory":
		push_error("FAIL purpose_name armory")
		failed = true
	if RoomDecoratorScript.purpose_from_name("arena") != RoomDecoratorScript.Purpose.ARENA:
		push_error("FAIL purpose_from_name arena")
		failed = true
	if RoomDecoratorScript.purpose_from_name("arena_pit") != RoomDecoratorScript.Purpose.ARENA_PIT:
		push_error("FAIL purpose_from_name arena_pit still maps to pit")
		failed = true
	return failed


func _check_arena_labyrinth(rng: RandomNumberGenerator, failed: bool) -> bool:
	var dec: RoomDecorator = _make_decorator(rng) as RoomDecorator
	var volume: RoomVolume = RoomVolumeScript.make(Rect2i(2, 2, 40, 36), 0, 6)
	_shell_room(dec.brush, volume)
	## Lift pad clear in the middle — must stay open.
	volume.keep_clear.append(Rect2i(18, 16, 6, 6))
	var walls := dec.decorate(volume, RoomDecoratorScript.Purpose.ARENA)
	if walls < 20:
		push_error("FAIL ARENA labyrinth walls=%d (want some fractal columns)" % walls)
		failed = true
	var y := volume.prop_y()
	var r := volume.rect
	var mid_x := r.position.x + r.size.x / 2
	var mid_z := r.position.y + r.size.y / 2
	var fractal := 0
	var usable := 0
	var clear_ok := true
	## Each quarter should use only one band id among its remaining walls.
	var quarter_band: Array[int] = [-1, -1, -1, -1]
	for z in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var id := dec.brush.get_vox(Vector3i(x, y, z))
			if volume.is_cleared(Vector2i(x, z)):
				if id != VoxelMaterial.AIR:
					clear_ok = false
				continue
			usable += 1
			if id == VoxelMaterial.AIR:
				continue
			if not VoxelMaterial.is_fractal_band(id):
				push_error("FAIL ARENA non-fractal wall mat %d at %d,%d" % [id, x, z])
				failed = true
				continue
			fractal += 1
			if not VoxelMaterial.is_destructible(id):
				push_error("FAIL ARENA wall mat %d is not destructible" % id)
				failed = true
			var qi := (1 if x >= mid_x else 0) + (2 if z >= mid_z else 0)
			if quarter_band[qi] < 0:
				quarter_band[qi] = id
			elif quarter_band[qi] != id:
				push_error(
					"FAIL ARENA quarter %d mixed mats %d and %d" % [qi, quarter_band[qi], id]
				)
				failed = true
	if not clear_ok:
		push_error("FAIL ARENA keep_clear still has walls")
		failed = true
	if fractal != walls:
		push_error("FAIL ARENA counted fractal=%d walls=%d" % [fractal, walls])
		failed = true
	var wall_frac := float(fractal) / float(maxi(usable, 1))
	if wall_frac > 0.20:
		push_error("FAIL ARENA wall coverage %.2f (want ~0.15)" % wall_frac)
		failed = true
	print(
		"arena labyrinth: walls=%d coverage=%.0f%% keep_clear open"
		% [walls, wall_frac * 100.0]
	)
	return failed


func _check_purpose(purpose: int, rng: RandomNumberGenerator, failed: bool) -> bool:
	var dec: RoomDecorator = _make_decorator(rng) as RoomDecorator
	var volume: RoomVolume = RoomVolumeScript.make(Rect2i(2, 2, 14, 12), 0, 6)
	_shell_room(dec.brush, volume)
	var placed := dec.decorate(volume, purpose as RoomDecorator.Purpose)
	var counted := _count_props(dec.brush, volume)
	var name := RoomDecoratorScript.purpose_name(purpose as RoomDecorator.Purpose)
	if placed < 1:
		push_error("FAIL %s: decorate returned %d" % [name, placed])
		failed = true
	if counted != placed:
		push_error("FAIL %s: placed=%d counted=%d" % [name, placed, counted])
		failed = true
	if counted < 1:
		push_error("FAIL %s: no prop voxels in volume" % name)
		failed = true
	print("  %s: placed=%d" % [name, placed])
	return failed


## Lamps and fans belong against the ceiling course. Anything hanging lower is something
## the walker walks into — and a 2 m storey has no room for one at all.
func _check_ceiling_clearance(failed: bool) -> bool:
	var clear: int = RoomDecoratorScript.WALK_CLEAR_VOX
	for air_h in [4, 5, 7]:
		## Own seed: this check asserts a prop count, so it must not drift when another
		## check above it draws a different number of randoms.
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + air_h
		var dec: RoomDecorator = _make_decorator(rng) as RoomDecorator
		var volume: RoomVolume = RoomVolumeScript.make(Rect2i(0, 0, 16, 14), 0, air_h)
		_shell_room(dec.brush, volume)
		dec.decorate(volume, RoomDecoratorScript.Purpose.LIVING_ROOM)
		var hung := 0
		for z in range(volume.rect.position.y, volume.rect.end.y):
			for x in range(volume.rect.position.x, volume.rect.end.x):
				var bottom := _hanging_bottom(dec.brush, volume, x, z)
				if bottom < 0:
					continue
				hung += 1
				if bottom - volume.prop_y() < clear:
					push_error(
						"FAIL air_h=%d: prop hangs to y=%d, only %d clear cells over the floor"
						% [air_h, bottom, bottom - volume.prop_y()]
					)
					failed = true
				if not _solid_to_ceiling(dec.brush, volume, x, z, bottom):
					push_error(
						"FAIL air_h=%d: prop at (%d,%d) floats below the ceiling" % [air_h, x, z]
					)
					failed = true
		if air_h < clear + 1 and hung > 0:
			push_error("FAIL air_h=%d is too low for ceiling props, got %d" % [air_h, hung])
			failed = true
		if air_h >= clear + 1 and hung == 0:
			push_error("FAIL air_h=%d has headroom to spare but hung nothing" % air_h)
			failed = true
		print("  ceiling clearance air_h=%d: %d hanging columns" % [air_h, hung])
	return failed


## Y of the lowest prop cell in a column that has open air under it, or -1 when nothing
## in the column hangs (a lamp may share a column with the table it lights).
func _hanging_bottom(brush: CityBrush, volume: RoomVolume, x: int, z: int) -> int:
	for y in range(volume.prop_y() + 1, volume.floor_y + volume.air_h + 1):
		if not VoxelMaterial.is_prop_furniture(brush.get_vox(Vector3i(x, y, z))):
			continue
		if brush.get_vox(Vector3i(x, y - 1, z)) == VoxelMaterial.AIR:
			return y
		return -1
	return -1


func _solid_to_ceiling(brush: CityBrush, volume: RoomVolume, x: int, z: int, from: int) -> bool:
	for y in range(from, volume.floor_y + volume.air_h + 1):
		if not VoxelMaterial.is_prop_furniture(brush.get_vox(Vector3i(x, y, z))):
			return false
	return true


func _check_keep_clear(rng: RandomNumberGenerator, failed: bool) -> bool:
	var dec: RoomDecorator = _make_decorator(rng) as RoomDecorator
	var volume: RoomVolume = RoomVolumeScript.make(Rect2i(0, 0, 10, 10), 0, 5)
	## Door apron through the south wall center — must stay empty.
	volume.keep_clear = [Rect2i(4, 0, 2, 3)] as Array[Rect2i]
	_shell_room(dec.brush, volume)
	dec.decorate(volume, RoomDecoratorScript.Purpose.STORAGE)
	for z in range(0, 3):
		for x in range(4, 6):
			var id := dec.brush.get_vox(Vector3i(x, volume.prop_y(), z))
			if VoxelMaterial.is_prop_furniture(id):
				push_error("FAIL keep_clear: prop at door apron (%d,%d)" % [x, z])
				failed = true
	return failed


## City façades punch AIR doorways in the wall ring outside the room rect — the
## decorator must reserve an inward apron without an explicit keep_clear list.
func _check_opening_apron(rng: RandomNumberGenerator, failed: bool) -> bool:
	var dec: RoomDecorator = _make_decorator(rng) as RoomDecorator
	var volume: RoomVolume = RoomVolumeScript.make(Rect2i(0, 0, 14, 14), 0, 5)
	_shell_room(dec.brush, volume)
	## Punch a 3-wide door in the -Z wall (outside z = -1), centered.
	for x in range(6, 9):
		for y in range(volume.floor_y + 1, volume.floor_y + volume.air_h):
			dec.brush.set_vox(Vector3i(x, y, -1), VoxelMaterial.AIR)
	dec.decorate(volume, RoomDecoratorScript.Purpose.LIVING_ROOM)
	var depth: int = RoomDecoratorScript.OPENING_APRON_DEPTH
	for z in range(0, depth):
		for x in range(6, 9):
			for y in range(volume.prop_y(), volume.floor_y + volume.air_h + 1):
				var id := dec.brush.get_vox(Vector3i(x, y, z))
				if VoxelMaterial.is_prop_furniture(id):
					push_error(
						"FAIL opening_apron: prop in doorway lane (%d,%d,%d)" % [x, y, z]
					)
					failed = true
	print("  opening_apron: ok")
	return failed


func _check_preserves_stairs(rng: RandomNumberGenerator, failed: bool) -> bool:
	var dec: RoomDecorator = _make_decorator(rng) as RoomDecorator
	var volume: RoomVolume = RoomVolumeScript.make(Rect2i(0, 0, 12, 12), 0, 6)
	_shell_room(dec.brush, volume)
	## Fake stair flight: solid steps climbing through a corner of the room.
	var stair: Array[Vector3i] = []
	for i in range(5):
		var at := Vector3i(1 + i, volume.prop_y() + i, 1)
		dec.brush.set_vox(at, VoxelMaterial.STONE)
		stair.append(at)
	var placed := dec.decorate(volume, RoomDecoratorScript.Purpose.STORAGE)
	if placed < 1:
		push_error("FAIL preserves_stairs: expected props beside the flight")
		failed = true
	for at in stair:
		if dec.brush.get_vox(at) != VoxelMaterial.STONE:
			push_error("FAIL preserves_stairs: stair voxel replaced at %s" % at)
			failed = true
	## Entire stair columns must stay free of props (not only the step cells).
	for i in range(5):
		var col := Vector2i(1 + i, 1)
		for y in range(volume.prop_y(), volume.floor_y + volume.air_h + 1):
			var id := dec.brush.get_vox(Vector3i(col.x, y, col.y))
			if VoxelMaterial.is_prop_furniture(id):
				push_error("FAIL preserves_stairs: prop in stair column %s y=%d" % [col, y])
				failed = true
	return failed


func _check_tiny_room(rng: RandomNumberGenerator, failed: bool) -> bool:
	var dec: RoomDecorator = _make_decorator(rng) as RoomDecorator
	var volume: RoomVolume = RoomVolumeScript.make(Rect2i(0, 0, 2, 2), 0, 4)
	_shell_room(dec.brush, volume)
	var placed := dec.decorate(volume, RoomDecoratorScript.Purpose.GENERIC)
	if placed != 0:
		push_error("FAIL tiny room should place nothing, got %d" % placed)
		failed = true
	return failed
