## Headless: multi-storey bake carves elevator cabins (pad, clear cabin, three-sided
## metal enclosure with one bay), reserves them from prop stamping, and the ride
## advances to the next landing.
##
## Run: powershell -File tools\run_test.ps1 test_elevator_shaft
extends Node

const ElevatorShaftScript := preload("res://scripts/city/elevator_shaft.gd")
const ElevatorPanelScript := preload("res://scripts/city/elevator_panel.gd")
const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")

const VOXEL_SIZE := 0.5

var _failed := false


## Stand-in for CityWalker.begin_elevator_ride (avoids Walker._ready side effects).
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


func _ready() -> void:
	_check_shaft_math()
	_check_bay_geometry()
	_check_panel()
	_check_bake()
	_check_ride()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _check_shaft_math() -> void:
	var ys := PackedInt32Array([7, 15, 21])
	var shaft: ElevatorShaft = ElevatorShaftScript.make(
		Rect2i(10, 20, 3, 3), ys, Vector2i(0, 1)
	)
	if shaft.landing_count() != 3:
		_fail("FAIL landing_count")
		return
	if shaft.nearest_landing_index(14) != 1:
		_fail("FAIL nearest_landing_index")
		return
	if shaft.next_landing_index(2) != 0:
		_fail("FAIL next_landing wrap")
		return
	if not shaft.contains_foot_voxel(Vector3i(11, 15, 21)):
		_fail("FAIL contains_foot in cabin")
		return
	if shaft.contains_foot_voxel(Vector3i(11, 40, 21)):
		_fail("FAIL contains_foot far Y")
		return
	var at := shaft.world_anchor(1, VOXEL_SIZE)
	var expect_y := (15.0 + 0.05) * VOXEL_SIZE
	if not is_equal_approx(at.y, expect_y):
		_fail("FAIL world_anchor y=%.4f want %.4f" % [at.y, expect_y])
		return
	## Standing in the cabin, in the bay doorway, and one voxel off a landing all count;
	## the same cell mid-storey, or two cells out in XZ, does not.
	var cases: Array[Array] = [
		[Vector3i(11, 15, 21), 1],
		[Vector3i(11, 16, 21), 1],
		[Vector3i(11, 15, 23), 1],
		[Vector3i(11, 21, 22), 2],
		[Vector3i(11, 11, 21), -1],
		[Vector3i(11, 15, 24), -1],
		[Vector3i(8, 15, 21), -1],
	]
	for case in cases:
		var vox: Vector3i = case[0]
		var want: int = case[1]
		var got := shaft.foot_landing_index(vox)
		if got != want:
			_fail("FAIL foot_landing_index%s = %d, want %d" % [str(vox), got, want])
			return
	print("  shaft math: ok")


## The panel mounts on the wall opposite the bay and looks back at the doorway, for
## every bay direction — a mirrored yaw would bury it inside the wall voxels.
func _check_bay_geometry() -> void:
	var ys := PackedInt32Array([7, 15, 21])
	for dir: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var shaft: ElevatorShaft = ElevatorShaftScript.make(Rect2i(10, 20, 3, 3), ys, dir)
		var yaw := shaft.bay_yaw()
		## Ui3D's readable face is local −Z; rotating it by the yaw must point at the bay.
		var face := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var want := Vector3(float(dir.x), 0.0, float(dir.y))
		if face.distance_to(want) > 0.001:
			_fail("FAIL bay %s faces %s, want %s" % [str(dir), str(face), str(want)])
			return
		var center := shaft.back_wall_center(0, VOXEL_SIZE)
		var cabin_center := Vector3(
			(float(shaft.rect.position.x) + 1.5) * VOXEL_SIZE,
			center.y,
			(float(shaft.rect.position.y) + 1.5) * VOXEL_SIZE
		)
		var out := center - cabin_center
		if Vector2(out.x, out.z).dot(Vector2(dir)) >= 0.0:
			_fail("FAIL bay %s wall anchor %s is not opposite the bay" % [str(dir), str(out)])
			return
		var want_y := float(int(ys[0]) + 1) * VOXEL_SIZE
		if not is_equal_approx(center.y, want_y):
			_fail("FAIL wall anchor y=%.3f want %.3f (pad top)" % [center.y, want_y])
			return
	print("  bay geometry: ok")


## The whole point of the panel: reaching a landing below the current one.
func _check_panel() -> void:
	var ys := PackedInt32Array([7, 15, 21])
	var shaft: ElevatorShaft = ElevatorShaftScript.make(
		Rect2i(10, 20, 3, 3), ys, Vector2i(0, 1)
	)
	var panel := ElevatorPanelScript.new() as ElevatorPanel
	add_child(panel)
	panel.bind_to(shaft, 2, VOXEL_SIZE)
	if panel.button_count() != ys.size():
		_fail("FAIL panel has %d buttons for %d floors" % [panel.button_count(), ys.size()])
		panel.queue_free()
		return
	var face := -panel.global_transform.basis.z
	if face.distance_to(Vector3(0.0, 0.0, 1.0)) > 0.001:
		_fail("FAIL panel faces %s, want +Z (the bay)" % str(face))
		panel.queue_free()
		return
	var want_y := float(int(ys[2]) + 1) * VOXEL_SIZE + ElevatorPanelScript.CENTER_H_M
	if not is_equal_approx(panel.global_position.y, want_y):
		_fail("FAIL panel y=%.3f want %.3f" % [panel.global_position.y, want_y])
		panel.queue_free()
		return
	var picked: Array[int] = []
	panel.floor_selected.connect(
		func(index: int) -> void:
			picked.append(index)
	)
	## Pressing the floor you are already on must not start a ride.
	if not _press_floor(panel, 2):
		_fail("FAIL panel rejected a press on the current floor button")
		panel.queue_free()
		return
	if not picked.is_empty():
		_fail("FAIL current floor emitted floor_selected %s" % str(picked))
		panel.queue_free()
		return
	if not _press_floor(panel, 0):
		_fail("FAIL panel rejected a press on the ground floor button")
		panel.queue_free()
		return
	if picked != ([0] as Array[int]):
		_fail("FAIL ground floor press emitted %s, want [0]" % str(picked))
		panel.queue_free()
		return
	var dest := shaft.world_anchor(0, VOXEL_SIZE)
	var here := shaft.world_anchor(2, VOXEL_SIZE)
	if dest.y >= here.y:
		_fail("FAIL selected floor is not below the current one")
		panel.queue_free()
		return
	## Rebinding to a lower landing follows the player down without rebuilding the keypad.
	panel.bind_to(shaft, 0, VOXEL_SIZE)
	if panel.bound_index() != 0 or panel.button_count() != ys.size():
		_fail("FAIL rebind left index=%d buttons=%d" % [panel.bound_index(), panel.button_count()])
		panel.queue_free()
		return
	print("  panel: %d floors, ground reachable from the top" % panel.button_count())
	panel.queue_free()


## Fire at the centre of floor `index`'s button. False when the panel rejected the hit.
func _press_floor(panel: ElevatorPanel, index: int) -> bool:
	var uv := panel.button_uv(index)
	if not is_finite(uv.x):
		_fail("FAIL panel has no button for floor %d" % index)
		return false
	var local: Vector3 = panel.call("_uv_to_local", uv) as Vector3
	return panel.press_at_world(panel.to_global(local))


func _check_bake() -> void:
	var payload: Dictionary = DistrictBakeJobScript.bake({
		"coord": Vector2i(0, 0),
		"world_seed": 42,
		"quality": DistrictBakeJobScript.QUALITY_FULL,
		"bake_nav": false,
	})
	if not bool(payload.get("ok", false)):
		_fail("FAIL bake: %s" % payload.get("error", "?"))
		return
	var shafts: Array = payload.get("elevator_shafts", [])
	if shafts.is_empty():
		_fail("FAIL full bake emitted zero elevator_shafts")
		return
	var index: Dictionary = payload.get("interior_buildings", {})
	var reserved := 0
	for shaft_v in shafts:
		var shaft: ElevatorShaft = shaft_v as ElevatorShaft
		if shaft == null:
			_fail("FAIL elevator_shafts entry is not an ElevatorShaft")
			return
		if shaft.landing_count() < 2:
			_fail("FAIL shaft has <2 landings: %s" % str(shaft.floor_ys))
			return
		if shaft.rect.size.x < 3 or shaft.rect.size.y < 3:
			_fail("FAIL shaft rect too small: %s" % str(shaft.rect))
			return
		for i in range(1, shaft.floor_ys.size()):
			if int(shaft.floor_ys[i]) <= int(shaft.floor_ys[i - 1]):
				_fail("FAIL floor_ys not ascending: %s" % str(shaft.floor_ys))
				return
		## The enclosure walls and bay must be off limits to the prop decorator, not
		## just the cabin pad — on every storey the cabin serves.
		for building_v in index.values():
			var building: BuildingInterior = building_v as BuildingInterior
			if building == null:
				continue
			for room in building.storeys:
				for c: Rect2i in room.keep_clear:
					if c.encloses(shaft.rect):
						reserved += 1
	if reserved <= 0:
		_fail("FAIL no InteriorRoom keep_clear covers a shaft cabin")
		return
	print("  bake shafts=%d reserved=%d" % [shafts.size(), reserved])
	_check_cabin_voxels(payload, shafts)

	var far: Dictionary = DistrictBakeJobScript.bake({
		"coord": Vector2i(1, 0),
		"world_seed": 42,
		"quality": DistrictBakeJobScript.QUALITY_FAR,
		"bake_nav": false,
	})
	if not bool(far.get("ok", false)):
		_fail("FAIL far bake: %s" % far.get("error", "?"))
		return
	var far_shafts: Array = far.get("elevator_shafts", [])
	if not far_shafts.is_empty():
		_fail("FAIL far bake should not emit elevator_shafts (got %d)" % far_shafts.size())


## Every landing must be a standable metal pad inside a three-sided enclosure with
## exactly one open bay, read straight out of the baked voxels.
func _check_cabin_voxels(payload: Dictionary, shafts: Array) -> void:
	var gen: DistrictGenerator = payload.get("generator") as DistrictGenerator
	if gen == null:
		_fail("FAIL bake payload has no generator")
		return
	var volume: NativeOfflineVoxelVolume = gen.get_offline_volume()
	if volume == null:
		_fail("FAIL bake generator has no offline volume")
		return
	var origin: Vector3i = payload.get("origin_vox", Vector3i.ZERO) as Vector3i
	var landings := 0
	for shaft_v in shafts:
		var shaft: ElevatorShaft = shaft_v as ElevatorShaft
		var cabin := Rect2i(
			shaft.rect.position.x - origin.x,
			shaft.rect.position.y - origin.z,
			shaft.rect.size.x,
			shaft.rect.size.y
		)
		var cx := cabin.position.x + cabin.size.x / 2
		var cz := cabin.position.y + cabin.size.y / 2
		for li in range(shaft.floor_ys.size()):
			var pad_y := int(shaft.floor_ys[li]) - origin.y
			for z in range(cabin.position.y, cabin.end.y):
				for x in range(cabin.position.x, cabin.end.x):
					if int(volume.get_vox(Vector3i(x, pad_y, z))) == VoxelMaterial.AIR:
						_fail("FAIL cabin pad hole at %s" % Vector3i(x, pad_y, z))
						return
			for dy in [1, 2]:
				var head := Vector3i(cx, pad_y + dy, cz)
				if int(volume.get_vox(head)) != VoxelMaterial.AIR:
					_fail("FAIL cabin not clear at %s (id %d)" % [head, volume.get_vox(head)])
					return
			var open_sides := 0
			var solid_sides := 0
			for side in _cabin_side_strips(cabin):
				var air := 0
				var solid := 0
				for xz: Vector2i in side:
					if int(volume.get_vox(Vector3i(xz.x, pad_y + 1, xz.y))) == VoxelMaterial.AIR:
						air += 1
					else:
						solid += 1
				if air == side.size():
					open_sides += 1
				elif solid == side.size():
					solid_sides += 1
			if open_sides != 1 or solid_sides != 3:
				_fail(
					"FAIL cabin at y=%d has %d open / %d solid sides (want 1 / 3)"
					% [pad_y, open_sides, solid_sides]
				)
				return
			if not _check_panel_fits(shaft, volume, origin, li):
				return
			landings += 1
	print("  cabin voxels: %d landings enclosed" % landings)


## The floor selector hangs in the cabin's back row with the enclosure wall behind it.
## Catches a mirrored bay yaw or a mount height that would bury the panel in masonry.
func _check_panel_fits(
	shaft: ElevatorShaft, volume: NativeOfflineVoxelVolume, origin: Vector3i, index: int
) -> bool:
	var at := shaft.back_wall_center(index, VOXEL_SIZE, ElevatorPanelScript.WALL_INSET_M)
	at.y += ElevatorPanelScript.CENTER_H_M
	var vox := Vector3i(
		int(floor(at.x / VOXEL_SIZE)) - origin.x,
		int(floor(at.y / VOXEL_SIZE)) - origin.y,
		int(floor(at.z / VOXEL_SIZE)) - origin.z
	)
	if int(volume.get_vox(vox)) != VoxelMaterial.AIR:
		_fail("FAIL panel mount %s is inside solid (id %d)" % [vox, volume.get_vox(vox)])
		return false
	var behind := vox - Vector3i(shaft.bay_dir.x, 0, shaft.bay_dir.y)
	if int(volume.get_vox(behind)) == VoxelMaterial.AIR:
		_fail("FAIL no cabin wall behind the panel at %s" % behind)
		return false
	return true


## The four one-cell strips hugging the cabin faces, corners excluded.
func _cabin_side_strips(cabin: Rect2i) -> Array[Array]:
	var neg_z: Array[Vector2i] = []
	var pos_z: Array[Vector2i] = []
	for x in range(cabin.position.x, cabin.end.x):
		neg_z.append(Vector2i(x, cabin.position.y - 1))
		pos_z.append(Vector2i(x, cabin.end.y))
	var neg_x: Array[Vector2i] = []
	var pos_x: Array[Vector2i] = []
	for z in range(cabin.position.y, cabin.end.y):
		neg_x.append(Vector2i(cabin.position.x - 1, z))
		pos_x.append(Vector2i(cabin.end.x, z))
	return [neg_z, pos_z, neg_x, pos_x] as Array[Array]


func _check_ride() -> void:
	var ys := PackedInt32Array([7, 15, 21])
	var shaft: ElevatorShaft = ElevatorShaftScript.make(
		Rect2i(10, 20, 3, 3), ys, Vector2i(0, 1)
	)
	var from_i := shaft.nearest_landing_index(7)
	var to_i := shaft.next_landing_index(from_i)
	if from_i != 0 or to_i != 1:
		_fail("FAIL ride landing indices from=%d to=%d" % [from_i, to_i])
		return
	var start := shaft.world_anchor(from_i, VOXEL_SIZE)
	var dest := shaft.world_anchor(to_i, VOXEL_SIZE)
	if dest.y <= start.y:
		_fail("FAIL next landing not above")
		return
	var body := RideBody.new()
	body.position = start
	body.begin_elevator_ride(dest, 0.2)
	if not body.is_elevator_riding():
		_fail("FAIL is_elevator_riding after begin")
		return
	var guard := 0
	while body.is_elevator_riding() and guard < 60:
		body.tick_ride(1.0 / 30.0)
		guard += 1
	if body.is_elevator_riding():
		_fail("FAIL ride did not finish")
		return
	if not is_equal_approx(body.position.y, dest.y):
		_fail("FAIL ride end y=%.3f want %.3f" % [body.position.y, dest.y])
		return
	print("  ride: ok")
