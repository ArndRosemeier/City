## Headless LOS / solid-ray checks for ProjectileLos (no CityRoot boot).
## Run: powershell -File tools/run_test.ps1 test_projectile_los -KeepLog
extends Node


func _ready() -> void:
	var failed := 0
	failed += _check_clear_air()
	failed += _check_wall_blocks()
	failed += _check_destination_grazing()
	failed += _check_local_to_world_scale()
	failed += _check_far_wall_world_distance()
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


func _check_local_to_world_scale() -> int:
	## Terrain.scale = 0.5 → local span is 2× world metres. Far-half walls used to clamp
	## to the tip and look transparent.
	var local_from := Vector3(0.0, 1.0, 0.0)
	var local_to := Vector3(20.0, 1.0, 0.0)  ## 10 m world
	var world_len := 10.0
	var local_hit := 16.0  ## wall at 8 m world
	var hit_t := ProjectileLos.local_distance_to_world(
		local_hit, local_from, local_to, world_len
	)
	if absf(hit_t - 8.0) > 0.05:
		push_error("local→world distance expected 8 m, got %s" % hit_t)
		return 1
	## Old bug: clamp(local_hit, 0, world_len) → 10, which clears LOS.
	var bogus := clampf(local_hit, 0.0, world_len)
	if absf(bogus - 10.0) > 0.05:
		push_error("sanity: bogus clamp should be 10")
		return 1
	if hit_t + 0.3 >= world_len:
		push_error("scaled wall must deny LOS (hit_t=%s world=%s)" % [hit_t, world_len])
		return 1
	return 0


func _check_far_wall_world_distance() -> int:
	## Simulate CityRoot: march in local voxels, convert to world metres.
	var voxel_size := 0.5
	var wall_x := 16  ## local column → 8 m world
	var get_voxel := func(v: Vector3i) -> int:
		if v.x == wall_x:
			return VoxelMaterial.ARENA_SHELL
		return VoxelMaterial.AIR
	var world_from := Vector3(0.25, 1.25, 0.25)
	var world_to := Vector3(12.25, 1.25, 0.25)
	var local_from := world_from / voxel_size
	var local_to := world_to / voxel_size
	var local_hit := ProjectileLos.probe_solid_ray(local_from, local_to, get_voxel, 1.0)
	if local_hit.is_empty():
		push_error("arena shell column should block local march")
		return 1
	var world_len := world_from.distance_to(world_to)
	var hit_t := ProjectileLos.local_distance_to_world(
		float(local_hit["distance"]), local_from, local_to, world_len
	)
	if hit_t < 7.5 or hit_t > 8.6:
		push_error("far shell wall world hit expected ~8 m, got %s" % hit_t)
		return 1
	if hit_t + voxel_size * 0.6 >= world_len:
		push_error("far shell wall must deny world LOS")
		return 1
	return 0
