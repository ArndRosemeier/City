## Target mode and screen source are independent: summon/placement uses voxel-only free cursor,
## while combat uses the look crosshair.
##
## Run: powershell -File tools\run_test.ps1 test_summon_aim
extends Node


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var walker := CityWalker.new()
	add_child(walker)
	await get_tree().process_frame
	await get_tree().process_frame

	var rect := get_viewport().get_visible_rect()
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		push_error("FAIL viewport too small for aim test: %s" % rect.size)
		print("RESULT: FAILED")
		get_tree().quit(1)
		return

	var cross: Vector2 = walker.call("_aim_crosshair_screen_pos") as Vector2
	var expected := rect.position + rect.size * 0.5
	if cross.distance_to(expected) > 0.5:
		push_error("FAIL crosshair screen pos %s expected %s" % [cross, expected])
		print("RESULT: FAILED")
		get_tree().quit(1)
		return

	## Park the free cursor in a top corner (sky in third-person) — look-aim must ignore it.
	get_viewport().warp_mouse(rect.position + Vector2(4.0, 4.0))
	await get_tree().process_frame

	var look := walker.resolve_target(
		CityTargeting.TargetMode.VOXELS_ONLY,
		CityTargeting.ScreenSource.LOOK_CROSSHAIR
	)
	var ground := walker.resolve_target(
		CityTargeting.TargetMode.VOXELS_ONLY,
		CityTargeting.ScreenSource.FREE_CURSOR
	)
	var look_dir := look.ray_direction
	var ground_dir := ground.ray_direction
	if look_dir.distance_to(ground_dir) < 0.02:
		push_error(
			"FAIL look-aim cam_dir matched free-cursor aim (%s) — crosshair/mouse not split"
			% look_dir
		)
		print("RESULT: FAILED")
		get_tree().quit(1)
		return

	var center_ray := walker.call(
		"_geometry_target",
		CityTargeting.TargetMode.VOXELS_ONLY,
		CityTargeting.ScreenSource.LOOK_CROSSHAIR,
		walker.laser_range_m
	) as CityTargeting.Result
	var center_dir := center_ray.ray_direction
	if look_dir.distance_to(center_dir) > 0.001:
		push_error(
			"FAIL LOOK_CROSSHAIR direction %s != centralized base ray %s"
			% [look_dir, center_dir]
		)
		print("RESULT: FAILED")
		get_tree().quit(1)
		return

	if look.mode != CityTargeting.TargetMode.VOXELS_ONLY:
		push_error("FAIL look result lost VOXELS_ONLY mode")
		print("RESULT: FAILED")
		get_tree().quit(1)
		return
	if look.screen_source != CityTargeting.ScreenSource.LOOK_CROSSHAIR:
		push_error("FAIL look result lost LOOK_CROSSHAIR source")
		print("RESULT: FAILED")
		get_tree().quit(1)
		return
	if ground.screen_source != CityTargeting.ScreenSource.FREE_CURSOR:
		push_error("FAIL placement result lost FREE_CURSOR source")
		print("RESULT: FAILED")
		get_tree().quit(1)
		return

	print("PASS target mode/source are explicit and crosshair/free-cursor rays stay separate")
	print("RESULT: OK")
	get_tree().quit(0)
