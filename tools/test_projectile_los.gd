## Headless LOS / solid-ray checks for ProjectileLos (no CityRoot boot).
## Run: powershell -File tools/run_test.ps1 test_projectile_los -KeepLog
extends Node


func _ready() -> void:
	var failed := 0
	failed += _check_clear_air()
	failed += _check_wall_blocks()
	failed += _check_destination_grazing()
	if failed > 0:
		print("RESULT: FAIL (%d)" % failed)
		get_tree().quit(1)
		return
	print("RESULT: OK")
	get_tree().quit(0)


func _check_clear_air() -> int:
	var get_voxel := func(_v: Vector3i) -> int: return VoxelMaterial.AIR
	var hit := ProjectileLos.probe_solid_ray(
		Vector3(0, 1, 0), Vector3(5, 1, 0), get_voxel, 0.5
	)
	if not hit.is_empty():
		push_error("clear air should not hit")
		return 1
	if not ProjectileLos.has_line_of_sight(Vector3(0, 1, 0), Vector3(5, 1, 0), get_voxel, 0.5):
		push_error("clear air should have LOS")
		return 1
	return 0


func _check_wall_blocks() -> int:
	## Solid wall at x=2 (local voxel column).
	var get_voxel := func(v: Vector3i) -> int:
		if v.x == 2:
			return VoxelMaterial.STONE
		return VoxelMaterial.AIR
	var from := Vector3(0.25, 1.25, 0.25)
	var to := Vector3(4.25, 1.25, 0.25)
	var hit := ProjectileLos.probe_solid_ray(from, to, get_voxel, 0.5)
	if hit.is_empty():
		push_error("wall should block ray")
		return 1
	if float(hit["distance"]) >= from.distance_to(to) - 0.1:
		push_error("wall hit distance too far: %s" % hit)
		return 1
	if ProjectileLos.has_line_of_sight(from, to, get_voxel, 0.5):
		push_error("wall should deny LOS")
		return 1
	return 0


func _check_destination_grazing() -> int:
	## Target standing inside a solid cell still counts as visible (grazing slack).
	var get_voxel := func(v: Vector3i) -> int:
		if v.x == 4 and v.y == 1 and v.z == 0:
			return VoxelMaterial.STONE
		return VoxelMaterial.AIR
	var from := Vector3(0.25, 1.25, 0.25)
	var to := Vector3(4.25, 1.25, 0.25)
	if not ProjectileLos.has_line_of_sight(from, to, get_voxel, 0.5):
		push_error("destination cell should not deny LOS")
		return 1
	return 0
