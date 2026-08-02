## Cave through-floor falls used to park on the bedrock clamp under the hill (beige void view).
## Rescue must snap back to the last solid stand instead of leaving the body under the massif.
##
## Run: powershell -File tools\run_test.ps1 test_walker_void_rescue
extends Node


func _ready() -> void:
	await get_tree().physics_frame

	var walker := CityWalker.new()
	walker.set_physics_process(false)
	add_child(walker)
	await get_tree().physics_frame

	var cave_stand := Vector3(40.0, 18.5, -12.0)
	walker.global_position = cave_stand
	walker._last_solid_footing = cave_stand
	walker._has_solid_footing = true
	walker._last_grounded_y = cave_stand.y

	## Drop under the bedrock band — the old clamp parked here and showed cave undersides.
	walker.global_position = Vector3(cave_stand.x, CityWalker.VOID_FLOOR_TOP_Y - 1.0, cave_stand.z)
	walker.velocity = Vector3(0.0, -20.0, 0.0)
	walker._enforce_void_floor()

	if walker.global_position.distance_to(cave_stand) > 0.05:
		push_error(
			"FAIL void rescue left body at %s instead of last stand %s"
			% [walker.global_position, cave_stand]
		)
		return _fail()
	if walker.velocity.length_squared() > 0.0001:
		push_error("FAIL void rescue left residual velocity %s" % walker.velocity)
		return _fail()
	print("PASS last solid footing restores a cave through-floor fall")

	## No remembered stand and no terrain: still clamp so the body never sinks forever.
	walker._has_solid_footing = false
	walker.global_position = Vector3(0.0, CityWalker.VOID_FLOOR_TOP_Y - 2.0, 0.0)
	walker._enforce_void_floor()
	if not is_equal_approx(walker.global_position.y, CityWalker.VOID_FLOOR_TOP_Y):
		push_error(
			"FAIL empty rescue clamped to y=%.3f want %.3f"
			% [walker.global_position.y, CityWalker.VOID_FLOOR_TOP_Y]
		)
		return _fail()
	print("PASS bedrock clamp remains when no stand can be resolved")

	print("RESULT: OK")
	get_tree().quit(0)


func _fail() -> void:
	print("RESULT: FAILED")
	get_tree().quit(1)
