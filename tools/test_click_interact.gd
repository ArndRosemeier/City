## Blaster LMB swallows world interact (doors) before spending energy; misses still fire.
##
## Run: powershell -File tools\run_test.ps1 test_click_interact
extends Node

const CastleDoorPlacerScript := preload("res://scripts/city/castle_door_placer.gd")
const VOXEL_SIZE := 0.5

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	await _check_swallow_skips_energy()
	await _check_miss_spends_energy()
	_check_door_plane_pick()
	_check_door_aim_toggle()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


## Fake CityRoot: walker finds it via resolve_laser_aim + apply_laser_agent_hit.
class FakeRoot extends Node:
	var swallow: bool = false
	var aim_calls: int = 0

	func resolve_laser_aim(_cam_from: Vector3, wall_aim: Vector3, _eye_from: Vector3) -> Vector3:
		return wall_aim

	func apply_laser_agent_hit(
		_from: Vector3,
		_to: Vector3,
		_direction: Vector3,
		_source: Variant,
		_creatures: bool = true
	) -> bool:
		return false

	func try_interact_aim(_origin: Vector3, _aim_point: Vector3) -> bool:
		aim_calls += 1
		return swallow


func _check_swallow_skips_energy() -> void:
	var root := FakeRoot.new()
	root.name = "FakeRoot"
	root.swallow = true
	add_child(root)
	var walker := CityWalker.new()
	walker.name = "Walker"
	root.add_child(walker)
	walker.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var before := walker.get_energy()
	walker.call("_fire_blaster_bolt")
	if root.aim_calls < 1:
		_fail("FAIL swallow path never called try_interact_aim")
	elif not is_equal_approx(walker.get_energy(), before):
		_fail(
			"FAIL energy spent on interact swallow (%.1f -> %.1f)"
			% [before, walker.get_energy()]
		)
	else:
		print("OK interact swallow spends no energy (aim_calls=%d)" % root.aim_calls)
	walker.queue_free()
	root.queue_free()
	await get_tree().process_frame


func _check_miss_spends_energy() -> void:
	var root := FakeRoot.new()
	root.name = "FakeRootMiss"
	root.swallow = false
	add_child(root)
	var walker := CityWalker.new()
	walker.name = "WalkerMiss"
	root.add_child(walker)
	walker.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	var before := walker.get_energy()
	walker.call("_fire_blaster_bolt")
	var after := walker.get_energy()
	var cost := walker.energy_cost_blaster
	if root.aim_calls < 1:
		_fail("FAIL miss path never called try_interact_aim")
	elif after > before - cost + 0.001:
		_fail("FAIL miss did not spend blaster energy (%.1f -> %.1f)" % [before, after])
	else:
		print("OK miss spends blaster energy (%.1f -> %.1f)" % [before, after])
	walker.queue_free()
	root.queue_free()
	await get_tree().process_frame


func _make_doorway(center: Vector2i) -> CastleDoorway:
	var d := CastleDoorway.new()
	d.center = center
	d.axis = Vector2i(0, 1)
	d.width = 3
	d.depth = 1
	d.floor_y = 4
	d.height = 4
	d.arch_courses = 0
	d.leaf = CastleDoorway.LEAF_DOOR
	d.link = CastleDoorway.LINK_LOOP
	return d


func _check_door_plane_pick() -> void:
	var placer: CastleDoorPlacer = CastleDoorPlacerScript.new() as CastleDoorPlacer
	add_child(placer)
	var d := _make_doorway(Vector2i(10, 10))
	## Mesh-only hang (no brush) — plane pick does not need DOOR voxels.
	placer.hang_lot_doorways([d], VOXEL_SIZE, null, null)
	if placer.door_count() != 1:
		_fail("FAIL plane pick hung %d doors" % placer.door_count())
		placer.queue_free()
		return
	var hung: CastleDoorPlacer.Hung = placer.hung_doors()[0]
	var n := Vector3(0.0, 0.0, 1.0)
	var mid_y := float(d.height) * 0.5 * VOXEL_SIZE
	var origin := hung.at - n * 2.0 + Vector3(0.0, mid_y, 0.0)
	var hit: Dictionary = placer.door_hit_along_ray(origin, n, 3.2)
	if hit.is_empty():
		_fail("FAIL door_hit_along_ray missed closed doorway plane")
	elif float(hit["t"]) > 2.1:
		_fail("FAIL door hit t=%.2f, expected ~2.0" % float(hit["t"]))
	else:
		print("OK doorway plane pick t=%.2f" % float(hit["t"]))
	## Aim past the jamb — must miss.
	var miss_origin := hung.at + Vector3(float(d.width) * VOXEL_SIZE + 1.5, 1.0, 0.0)
	var miss: Dictionary = placer.door_hit_along_ray(miss_origin, n, 3.2)
	if not miss.is_empty():
		_fail("FAIL door_hit_along_ray hit when aiming past the jamb")
	placer.queue_free()


func _check_door_aim_toggle() -> void:
	## Offline brush: seal + toggle without a live VoxelTerrain.
	var brush: CityBrush = (load("res://scripts/city/city_brush.gd") as GDScript).new() as CityBrush
	brush.use_offline_volume()
	var d := _make_doorway(Vector2i(20, 20))
	var s := d.side()
	var half := d.width / 2
	var y_lo := d.floor_y + mini(2, d.height)
	var y_hi := d.floor_y + maxi(d.height / 2, y_lo)
	brush.begin_edit()
	for y in [y_lo, y_hi]:
		for sign_i in [-1, 1]:
			var col: Vector2i = d.center + s * ((half + 1) * sign_i)
			brush.set_vox(Vector3i(col.x, y, col.y), VoxelMaterial.STONE)
	brush.end_edit()
	var placer: CastleDoorPlacer = CastleDoorPlacerScript.new() as CastleDoorPlacer
	add_child(placer)
	placer.hang_lot_doorways([d], VOXEL_SIZE, null, brush)
	if placer.door_count() != 1:
		_fail("FAIL aim toggle hung %d doors, expected 1" % placer.door_count())
		placer.queue_free()
		return
	var hung: CastleDoorPlacer.Hung = placer.hung_doors()[0]
	var n := Vector3(float(d.axis.x), 0.0, float(d.axis.y)).normalized()
	var origin: Vector3 = (
		hung.at - n * 1.5 + Vector3(0.0, float(d.height) * 0.5 * VOXEL_SIZE, 0.0)
	)
	var hit: Dictionary = placer.door_hit_along_ray(origin, n, CastleDoorPlacer.INTERACT_DISTANCE)
	if hit.is_empty():
		_fail("FAIL aim toggle: door_hit_along_ray missed")
		placer.queue_free()
		return
	var picked: CastleDoorPlacer.Hung = hit["door"] as CastleDoorPlacer.Hung
	if not placer.toggle_door(picked):
		_fail("FAIL aim toggle: toggle_door failed")
		placer.queue_free()
		return
	if picked.closed:
		_fail("FAIL aim toggle left the door closed")
		placer.queue_free()
		return
	print("OK aim ray toggles door (t=%.2f)" % float(hit["t"]))
	placer.queue_free()
