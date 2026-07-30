## Offline smoke: decorate empty room volumes for every purpose and assert props land.
##
## Run: Godot --headless --path . -s res://tools/test_room_decorator.gd
extends SceneTree

const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const RoomVolumeScript := preload("res://scripts/city/room_volume.gd")
const RoomDecoratorScript := preload("res://scripts/city/room_decorator.gd")
const CastleFloorScript := preload("res://scripts/city/castle_floor.gd")
const CastleVaultScript := preload("res://scripts/city/castle_vault.gd")


func _initialize() -> void:
	var failed := false
	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	failed = _check_factories(failed)
	failed = _check_purpose_names(failed)

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
	]
	for purpose in purposes:
		failed = _check_purpose(purpose, rng, failed)

	failed = _check_keep_clear(rng, failed)
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
			if VoxelMaterial.is_room_prop(id):
				push_error("FAIL keep_clear: prop at door apron (%d,%d)" % [x, z])
				failed = true
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
			if VoxelMaterial.is_room_prop(id):
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
