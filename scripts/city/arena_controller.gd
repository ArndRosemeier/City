## Runtime owner for an Arena district: four summon boards, four under-pit lifts,
## pit decorate/wipe (props + arena-tagged monsters).
class_name ArenaController
extends Node3D

const ArenaSummonBoardScript := preload("res://scripts/city/arena_summon_board.gd")
const ArenaSummonLiftScript := preload("res://scripts/city/arena_summon_lift.gd")
const ArenaHologramScript := preload("res://scripts/city/arena_hologram.gd")
const RoomDecoratorScript := preload("res://scripts/city/room_decorator.gd")
const ArenaCombatScript := preload("res://scripts/city/arena_combat.gd")

var layout: ArenaLayout = null
var voxel_size: float = 0.5
var origin_vox: Vector3i = Vector3i.ZERO
var district_seed: int = 0

var _boards: Array[ArenaSummonBoard] = []
var _lifts: Array[ArenaSummonLift] = []
var _hologram: ArenaHologram = null
var _brush_cb: Callable = Callable()
var _spawn_cb: Callable = Callable()
var _units_cb: Callable = Callable()
var _despawn_cb: Callable = Callable()
var _decorate_seed: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func setup(
	p_layout: ArenaLayout,
	p_origin_vox: Vector3i,
	p_voxel_size: float,
	p_district_seed: int,
	live_brush: Callable,
	spawn_monster: Callable,
	alive_units: Callable,
	despawn_unit: Callable = Callable()
) -> void:
	layout = p_layout
	origin_vox = p_origin_vox
	voxel_size = p_voxel_size
	district_seed = p_district_seed
	_brush_cb = live_brush
	## Lifts must not nav-snap out of the undercroft mid-delivery.
	_spawn_cb = func(body_id: String, world_pos: Vector3) -> UndeadUnit:
		if not spawn_monster.is_valid():
			return null
		return spawn_monster.call(body_id, world_pos, false) as UndeadUnit
	_units_cb = alive_units
	_despawn_cb = despawn_unit
	_decorate_seed = district_seed ^ 0xA5E4A
	_rng.seed = district_seed ^ 0x51C0DE
	name = "ArenaController"
	if layout == null:
		push_error("ArenaController.setup: null layout")
		return
	_spawn_lifts()
	_spawn_boards()
	_spawn_hologram()
	redecorate_pit()


func wipe_and_redecorate() -> void:
	_despawn_arena_units()
	_clear_pit_props()
	_decorate_seed = int(Time.get_ticks_msec()) ^ district_seed
	redecorate_pit()


func redecorate_pit() -> void:
	var brush: CityBrush = _brush_cb.call() as CityBrush if _brush_cb.is_valid() else null
	if brush == null:
		push_error("ArenaController.redecorate_pit: no live brush")
		assert(false, "ArenaController: decorate needs live brush")
		return
	if layout == null:
		push_error("ArenaController.redecorate_pit: null layout")
		assert(false, "ArenaController: decorate needs layout")
		return
	## Live CityBrush is world-voxel space (origin 0) — never feed district-local rects.
	var vol := layout.pit_volume_world(origin_vox)
	var dec: RoomDecorator = RoomDecoratorScript.new()
	dec.brush = brush
	dec.rng = RandomNumberGenerator.new()
	dec.rng.seed = _decorate_seed
	var n := dec.decorate(vol, RoomDecorator.Purpose.ARENA)
	if n <= 0:
		push_error(
			"ArenaController.redecorate_pit: labyrinth placed 0 walls (seed=%d vol=%s origin=%s)"
			% [_decorate_seed, vol.describe(), origin_vox]
		)
		assert(false, "ArenaController: arena labyrinth placed nothing")
		return
	print("ArenaController: arena labyrinth walls=%d (seed=%d)" % [n, _decorate_seed])


## Deliver every selected body; pads / lifts are shuffled so a batch does not clump.
func request_summon_batch(monster_ids: PackedStringArray) -> void:
	if monster_ids.is_empty():
		return
	var order := monster_ids.duplicate()
	_shuffle_strings(order)
	for mid: String in order:
		var lift := _random_free_lift()
		if lift != null:
			lift.deliver(mid)
			continue
		## All lifts busy — still drop the body on a random sand pad.
		_spawn_at_random_pad(mid)


func request_summon(monster_id: String) -> void:
	var one := PackedStringArray()
	one.append(monster_id)
	request_summon_batch(one)


func _spawn_hologram() -> void:
	if _hologram != null and is_instance_valid(_hologram):
		_hologram.queue_free()
	_hologram = ArenaHologramScript.new() as ArenaHologram
	add_child(_hologram)
	_hologram.setup(layout, origin_vox, voxel_size, district_seed)


func _spawn_lifts() -> void:
	for pad: Vector2i in layout.lift_pads:
		var lift: ArenaSummonLift = ArenaSummonLiftScript.new() as ArenaSummonLift
		add_child(lift)
		lift.setup(
			pad,
			layout.pit_floor_y,
			10,
			origin_vox,
			voxel_size,
			_spawn_cb
		)
		_lifts.append(lift)


func _spawn_boards() -> void:
	for mount: Dictionary in layout.board_mounts:
		var origin_xz: Vector2i = mount["origin"] as Vector2i
		var outward: Vector2i = mount["dir"] as Vector2i
		var yaw: float = float(mount["yaw"])
		## Sit on the seating-facing face of the low parapet (readable side faces outward).
		var wall_face := (
			Vector3(float(outward.x), 0.0, float(outward.y)).normalized()
			* (voxel_size * 0.5 + 0.05)
		)
		var deck_y := float(layout.seating_y + 1) * voxel_size
		var origin := Vector3(
			(float(origin_vox.x + origin_xz.x) + 0.5) * voxel_size,
			deck_y + 0.92,
			(float(origin_vox.z + origin_xz.y) + 0.5) * voxel_size
		) + wall_face
		var board: ArenaSummonBoard = ArenaSummonBoardScript.new() as ArenaSummonBoard
		add_child(board)
		board.setup_board(origin, yaw)
		board.summon_batch_requested.connect(request_summon_batch)
		board.clear_requested.connect(wipe_and_redecorate)
		_boards.append(board)


func _random_free_lift() -> ArenaSummonLift:
	if _lifts.is_empty():
		return null
	var free: Array[ArenaSummonLift] = []
	for lift: ArenaSummonLift in _lifts:
		if not lift.is_busy():
			free.append(lift)
	if free.is_empty():
		return null
	return free[_rng.randi_range(0, free.size() - 1)]


func _spawn_at_random_pad(monster_id: String) -> void:
	if layout == null or layout.lift_pads.is_empty() or not _spawn_cb.is_valid():
		return
	var pad: Vector2i = layout.lift_pads[_rng.randi_range(0, layout.lift_pads.size() - 1)]
	var top := Vector3(
		(float(origin_vox.x + pad.x) + 0.5) * voxel_size,
		float(layout.pit_floor_y + 1) * voxel_size,
		(float(origin_vox.z + pad.y) + 0.5) * voxel_size
	)
	var unit: UndeadUnit = _spawn_cb.call(monster_id, top) as UndeadUnit
	if unit == null or not is_instance_valid(unit):
		return
	ArenaCombatScript.tag_unit(unit)


func _shuffle_strings(arr: PackedStringArray) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _despawn_arena_units() -> void:
	if not _units_cb.is_valid():
		return
	## Snapshot — despawn unregisters and may mutate the director list.
	var units: Array = (_units_cb.call() as Array).duplicate()
	for u in units:
		var unit := u as UndeadUnit
		if unit == null or not is_instance_valid(unit):
			continue
		if not ArenaCombatScript.is_arena_owned(unit):
			continue
		if _despawn_cb.is_valid():
			_despawn_cb.call(unit)
		else:
			push_error("ArenaController._despawn_arena_units: no despawn callback")
			unit.queue_free()


func _clear_pit_props() -> void:
	var brush: CityBrush = _brush_cb.call() as CityBrush if _brush_cb.is_valid() else null
	if brush == null:
		push_error("ArenaController._clear_pit_props: no live brush")
		assert(false, "ArenaController: clear needs live brush")
		return
	if layout == null:
		push_error("ArenaController._clear_pit_props: null layout")
		assert(false, "ArenaController: clear needs layout")
		return
	var vol := layout.pit_volume_world(origin_vox)
	## Clear the air band only — sand slab and ARENA_SHELL undercroft stay.
	brush.fill_box(vol.air_min(), vol.air_max(), VoxelMaterial.AIR)
