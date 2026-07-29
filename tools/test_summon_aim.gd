## Combat look-aim uses the viewport crosshair; free-cursor picks stay on aim_ground_at_cursor.
## Regression for N-summon missing ground after RMB look released the OS cursor.
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

	var look: Dictionary = walker.aim_world_at_cursor()
	var ground: Dictionary = walker.aim_ground_at_cursor()
	var look_dir: Vector3 = look["cam_dir"] as Vector3
	var ground_dir: Vector3 = ground["cam_dir"] as Vector3
	if look_dir.distance_to(ground_dir) < 0.02:
		push_error(
			"FAIL look-aim cam_dir matched free-cursor aim (%s) — crosshair/mouse not split"
			% look_dir
		)
		print("RESULT: FAILED")
		get_tree().quit(1)
		return

	var center_ray: Dictionary = walker.call("_aim_ray_at_cursor", cross) as Dictionary
	var center_dir: Vector3 = center_ray["cam_dir"] as Vector3
	if look_dir.distance_to(center_dir) > 0.001:
		push_error(
			"FAIL aim_world_at_cursor cam_dir %s != explicit centre ray %s"
			% [look_dir, center_dir]
		)
		print("RESULT: FAILED")
		get_tree().quit(1)
		return

	## Meteor and summon both go through aim_world_at_cursor — same dictionary shape.
	for key in ["point", "normal", "did_hit", "cam_from", "cam_dir", "voxel", "has_voxel"]:
		if not look.has(key):
			push_error("FAIL aim_world_at_cursor missing key '%s'" % key)
			print("RESULT: FAILED")
			get_tree().quit(1)
			return

	print("PASS summon/meteor shared look-aim uses crosshair, not free cursor")
	print("RESULT: OK")
	get_tree().quit(0)
