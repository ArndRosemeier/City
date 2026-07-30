## Headless: multi-storey bake emits ElevatorShaft; keep_clear; ride advances landing.
##
## Run: Godot --headless --path . -s res://tools/test_elevator_shaft.gd
extends SceneTree

const ElevatorShaftScript := preload("res://scripts/city/elevator_shaft.gd")
const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")

const VOXEL_SIZE := 0.5


## Stand-in for CityWalker.begin_elevator_ride (avoids Walker._ready in -s).
class RideBody extends Node3D:
	var _elevator_ride_t: float = -1.0
	var _elevator_ride_duration: float = 0.85
	var _elevator_ride_from: Vector3 = Vector3.ZERO
	var _elevator_ride_to: Vector3 = Vector3.ZERO

	func is_elevator_riding() -> bool:
		return _elevator_ride_t >= 0.0

	func begin_elevator_ride(to_world: Vector3, duration_sec: float = 0.85) -> void:
		if is_elevator_riding():
			return
		_elevator_ride_from = position
		_elevator_ride_to = to_world
		_elevator_ride_duration = maxf(duration_sec, 0.05)
		_elevator_ride_t = 0.0

	func tick_ride(delta: float) -> void:
		if not is_elevator_riding():
			return
		_elevator_ride_t += delta
		var u := clampf(_elevator_ride_t / _elevator_ride_duration, 0.0, 1.0)
		u = u * u * (3.0 - 2.0 * u)
		position = _elevator_ride_from.lerp(_elevator_ride_to, u)
		if u >= 1.0:
			position = _elevator_ride_to
			_elevator_ride_t = -1.0


func _initialize() -> void:
	var failed := false
	failed = _check_shaft_math(failed)
	failed = _check_bake_emit(failed)
	failed = _check_ride(failed)
	if failed:
		push_error("test_elevator_shaft: FAILED")
		quit(1)
	else:
		print("test_elevator_shaft: OK")
		quit(0)


func _fail(msg: String, _failed: bool) -> bool:
	push_error(msg)
	return true


func _check_shaft_math(failed: bool) -> bool:
	var ys := PackedInt32Array([7, 15, 21])
	## Typed loosely — headless -s often lacks a fresh global class_name cache.
	var shaft: RefCounted = ElevatorShaftScript.make(Rect2i(10, 20, 3, 3), ys) as RefCounted
	if int(shaft.call("landing_count")) != 3:
		return _fail("FAIL landing_count", failed)
	if int(shaft.call("nearest_landing_index", 14)) != 1:
		return _fail("FAIL nearest_landing_index", failed)
	if int(shaft.call("next_landing_index", 2)) != 0:
		return _fail("FAIL next_landing wrap", failed)
	if not bool(shaft.call("contains_foot_voxel", Vector3i(11, 15, 21))):
		return _fail("FAIL contains_foot in cabin", failed)
	if bool(shaft.call("contains_foot_voxel", Vector3i(11, 40, 21))):
		return _fail("FAIL contains_foot far Y", failed)
	var at: Vector3 = shaft.call("world_anchor", 1, VOXEL_SIZE) as Vector3
	var expect_y := (15.0 + 0.05) * VOXEL_SIZE
	if not is_equal_approx(at.y, expect_y):
		return _fail("FAIL world_anchor y=%.4f want %.4f" % [at.y, expect_y], failed)
	print("  shaft math: ok")
	return failed


func _check_bake_emit(failed: bool) -> bool:
	var payload: Dictionary = DistrictBakeJobScript.bake({
		"coord": Vector2i(0, 0),
		"world_seed": 42,
		"quality": DistrictBakeJobScript.QUALITY_FULL,
		"bake_nav": false,
	})
	if not bool(payload.get("ok", false)):
		return _fail("FAIL bake: %s" % payload.get("error", "?"), failed)
	var shafts: Array = payload.get("elevator_shafts", [])
	if shafts.is_empty():
		return _fail("FAIL full bake emitted zero elevator_shafts", failed)
	var rooms: Array = payload.get("interior_rooms", [])
	var cleared := 0
	for shaft_v in shafts:
		var shaft: RefCounted = shaft_v as RefCounted
		if shaft == null or not shaft.has_method("landing_count"):
			return _fail("FAIL elevator_shafts entry missing ElevatorShaft API", failed)
		if int(shaft.call("landing_count")) < 2:
			return _fail("FAIL shaft has <2 landings: %s" % shaft.get("floor_ys"), failed)
		var rect: Rect2i = shaft.get("rect") as Rect2i
		if rect.size.x < 3 or rect.size.y < 3:
			return _fail("FAIL shaft rect too small: %s" % rect, failed)
		var floor_ys: PackedInt32Array = shaft.get("floor_ys") as PackedInt32Array
		for i in range(1, floor_ys.size()):
			if int(floor_ys[i]) <= int(floor_ys[i - 1]):
				return _fail("FAIL floor_ys not ascending", failed)
		for room_v in rooms:
			var room: RefCounted = room_v as RefCounted
			if room == null:
				continue
			var clears: Array = room.get("keep_clear") as Array
			for c in clears:
				if c == rect:
					cleared += 1
	if cleared <= 0:
		return _fail("FAIL no InteriorRoom keep_clear matched a shaft", failed)

	var far: Dictionary = DistrictBakeJobScript.bake({
		"coord": Vector2i(1, 0),
		"world_seed": 42,
		"quality": DistrictBakeJobScript.QUALITY_FAR,
		"bake_nav": false,
	})
	if not bool(far.get("ok", false)):
		return _fail("FAIL far bake: %s" % far.get("error", "?"), failed)
	var far_shafts: Array = far.get("elevator_shafts", [])
	if not far_shafts.is_empty():
		return _fail(
			"FAIL far bake should not emit elevator_shafts (got %d)" % far_shafts.size(), failed
		)
	print("  bake shafts=%d keep_clear_hits=%d" % [shafts.size(), cleared])
	return failed


func _check_ride(failed: bool) -> bool:
	var ys := PackedInt32Array([7, 15, 21])
	var shaft: RefCounted = ElevatorShaftScript.make(Rect2i(10, 20, 3, 3), ys) as RefCounted
	var from_i: int = int(shaft.call("nearest_landing_index", 7))
	var to_i: int = int(shaft.call("next_landing_index", from_i))
	if from_i != 0 or to_i != 1:
		return _fail("FAIL ride landing indices from=%d to=%d" % [from_i, to_i], failed)
	var start: Vector3 = shaft.call("world_anchor", from_i, VOXEL_SIZE) as Vector3
	var dest: Vector3 = shaft.call("world_anchor", to_i, VOXEL_SIZE) as Vector3
	if dest.y <= start.y:
		return _fail("FAIL next landing not above", failed)

	## No add_child — Walker/Node3D _ready side-effects can quit the -s tree.
	var body := RideBody.new()
	body.position = start
	body.begin_elevator_ride(dest, 0.2)
	if not body.is_elevator_riding():
		return _fail("FAIL is_elevator_riding after begin", failed)
	var guard := 0
	while body.is_elevator_riding() and guard < 60:
		body.tick_ride(1.0 / 30.0)
		guard += 1
	if body.is_elevator_riding():
		return _fail("FAIL ride did not finish", failed)
	if not is_equal_approx(body.position.y, dest.y):
		return _fail("FAIL ride end y=%.3f want %.3f" % [body.position.y, dest.y], failed)
	print("  ride: ok")
	return failed
