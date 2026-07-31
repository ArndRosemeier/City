## Street furniture culling: lamp poles and sidewalk props must not pop, and the OmniLight budget
## must stay honest.
##
## What is at risk, and therefore checked:
##   - The cull used to hide a whole lamp when one point three metres up it left the camera
##     frustum, so standing under a lamp or panning it toward the screen edge blinked it out.
##     Frustum culling is the renderer's job; the script only owns draw distance.
##   - Draw distance needs hysteresis, or a player standing on the boundary sees the street
##     furniture strobe.
##   - Lights are the expensive part, so they keep their frustum test and their budget: only the
##     nearest few lamps that can actually be seen may burn, and only after dark.
##
## Run: powershell -File tools\run_test.ps1 test_street_props
extends Node3D

const StreetPropPlacerScript := preload("res://scripts/city/street_prop_placer.gd")

const VOX := 0.5
const CELL_SIZE := 28
const GROUND_THICKNESS := 6
const EYE_M := 1.7

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	var cam := Camera3D.new()
	cam.fov = 70.0
	add_child(cam)
	var placer := _build_placer(cam)
	if placer._poles.is_empty() or placer._props.is_empty():
		_fail("FAIL placer produced %d poles / %d props" % [placer._poles.size(), placer._props.size()])
		_finish(placer)
		return

	_check_close_up(placer, cam)
	_check_turning_away(placer, cam)
	_check_draw_distance(placer, cam)
	_check_edge_is_steady(placer, cam)
	_check_lamps_follow_night(placer, cam)
	_check_light_budget(placer, cam)
	_finish(placer)


func _finish(placer: StreetPropPlacer) -> void:
	placer.queue_free()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


## Right up against a lamp and a trash can, at eye height, looking level: both are unmissably on
## screen, so neither may be culled.
func _check_close_up(placer: StreetPropPlacer, cam: Camera3D) -> void:
	var pole: Node3D = placer._poles[0]
	var prop: Node3D = placer._props[0]
	for metres in [8.0, 3.0, 1.0, 0.5]:
		_look_from(cam, pole.global_position, float(metres), 0.0)
		placer._refresh_lights(true)
		if not pole.visible:
			_fail("FAIL lamp culled from %.1f m away" % metres)
		_look_from(cam, prop.global_position, float(metres), 0.0)
		placer._refresh_lights(true)
		if not prop.visible:
			_fail("FAIL sidewalk prop culled from %.1f m away" % metres)
	print("close up: lamp and prop survive down to half a metre")


func _check_turning_away(placer: StreetPropPlacer, cam: Camera3D) -> void:
	var pole: Node3D = placer._poles[0]
	for turn in [0.0, 90.0, 180.0, 270.0]:
		_look_from(cam, pole.global_position, 6.0, float(turn))
		placer._refresh_lights(true)
		if not pole.visible:
			_fail("FAIL lamp culled at 6 m with the camera turned %.0f°" % turn)
	print("turning: lamp stays loaded through a full turn at 6 m")


func _check_draw_distance(placer: StreetPropPlacer, cam: Camera3D) -> void:
	var pole: Node3D = placer._poles[0]
	var prop: Node3D = placer._props[0]
	_look_from(cam, pole.global_position, placer.pole_draw_distance + 60.0, 0.0)
	placer._refresh_lights(true)
	if pole.visible:
		_fail("FAIL lamp still drawn %.0f m past its draw distance" % 60.0)
	_look_from(cam, prop.global_position, placer.prop_draw_distance + 60.0, 0.0)
	placer._refresh_lights(true)
	if prop.visible:
		_fail("FAIL sidewalk prop still drawn well past its draw distance")
	print("draw distance: both drop out beyond their range")


## Step back and forth across the draw distance itself. Once shown, hysteresis has to hold the
## lamp on until well past the line, so the whole walk costs exactly one transition — without it
## every single step would toggle.
func _check_edge_is_steady(placer: StreetPropPlacer, cam: Camera3D) -> void:
	var pole: Node3D = placer._poles[0]
	_look_from(cam, pole.global_position, placer.pole_draw_distance + 60.0, 0.0)
	placer._refresh_lights(true)
	if pole.visible:
		_fail("FAIL lamp did not start the edge walk hidden")
	var flips := 0
	var was := pole.visible
	for step in range(24):
		var side := -1.0 if (step % 2) == 0 else 1.0
		_look_from(cam, pole.global_position, placer.pole_draw_distance + side, 0.0)
		placer._refresh_lights(true)
		if pole.visible != was:
			flips += 1
			was = pole.visible
	if flips != 1:
		_fail("FAIL lamp flipped visibility %d times straddling the draw distance, wanted 1" % flips)
	if not pole.visible:
		_fail("FAIL lamp never came on during the edge walk — the boundary was not crossed")
	print("edge: %d transition over 24 steps straddling the boundary" % flips)


func _check_lamps_follow_night(placer: StreetPropPlacer, cam: Camera3D) -> void:
	var pole: Node3D = placer._poles[0]
	var omni: OmniLight3D = placer._omnis[0]
	_look_from(cam, pole.global_position, 10.0, 0.0)
	placer.set_night_factor(0.0)
	if omni.visible:
		_fail("FAIL lamp burning in broad daylight")
	placer.set_night_factor(1.0)
	if not omni.visible:
		_fail("FAIL lamp dark at night with the camera 10 m in front of it")
	## A lamp behind the camera lights nothing you can see, so the budget skips it — but the mesh
	## must stay loaded, which is the part that used to blink.
	_look_from(cam, pole.global_position, 10.0, 180.0)
	placer._refresh_lights(true)
	if omni.visible:
		_fail("FAIL lamp behind the camera still burning a light")
	if not pole.visible:
		_fail("FAIL lamp mesh culled just because its light was skipped")
	print("night: lights follow dusk and the frustum, meshes do not")


## Stand mid-district after dark, looking down a street with a cluster of lamps in range, and the
## cap is what decides how many burn.
func _check_light_budget(placer: StreetPropPlacer, cam: Camera3D) -> void:
	placer.set_night_factor(1.0)
	## Stand at the middle of the lamps the placer actually produced, not the middle of the tile:
	## it stops at max_poles, so the far end of a full-grid planner never gets any.
	var centre := Vector3.ZERO
	for p: Node3D in placer._poles:
		centre += p.global_position
	centre /= float(placer._poles.size())
	cam.global_position = Vector3(centre.x, EYE_M, centre.z)
	cam.look_at(Vector3(centre.x, EYE_M, centre.z - 30.0))

	placer.max_omni_lights = 64
	placer._refresh_lights(true)
	var uncapped := _lights_on(placer)
	## Guard the setup itself: with nothing in view the cap below would pass on an empty street.
	if uncapped < 3:
		_fail("FAIL only %d lamps lit mid-district — the budget check has nothing to cap" % uncapped)
		return
	placer.max_omni_lights = 2
	placer._refresh_lights(true)
	var capped := _lights_on(placer)
	if capped != placer.max_omni_lights:
		_fail("FAIL %d lights on with a budget of %d" % [capped, placer.max_omni_lights])
	print("budget: %d lamps in range, %d burning under a cap of 2" % [uncapped, capped])


func _lights_on(placer: StreetPropPlacer) -> int:
	var on := 0
	for omni: OmniLight3D in placer._omnis:
		if omni.visible:
			on += 1
	return on


## Park the camera `metres` away from `target` at eye height, yawed `turn` degrees off looking
## straight at it. A level gaze is the worst case for a point-based cull: everything tall is
## above the view centre and everything low is below it.
func _look_from(cam: Camera3D, target: Vector3, metres: float, turn: float) -> void:
	cam.global_position = Vector3(target.x, EYE_M, target.z + metres)
	cam.rotation = Vector3(0.0, deg_to_rad(turn), 0.0)


func _build_placer(cam: Camera3D) -> StreetPropPlacer:
	var planner := DistrictPlanner.new()
	planner.theme = DistrictTheme.make(DistrictTheme.OLD_TOWN)
	planner.cell_size = CELL_SIZE
	planner.avenue_light_cells = _fake_avenue_cells()
	var placer: StreetPropPlacer = StreetPropPlacerScript.new() as StreetPropPlacer
	add_child(placer)
	placer.place_from_planner(planner, CELL_SIZE, VOX, GROUND_THICKNESS, cam, Vector3i.ZERO)
	return placer


## Every cell in the tile. The real planner hands over a subset of these, and the placer strides
## through whatever it is given, so a full grid just means more furniture to cull.
func _fake_avenue_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for z in range(DistrictCoord.SIZE_Z_VOX / CELL_SIZE):
		for x in range(DistrictCoord.SIZE_X_VOX / CELL_SIZE):
			cells.append(Vector2i(x, z))
	return cells
