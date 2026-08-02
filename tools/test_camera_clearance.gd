## The camera keeps its near plane out of the ceiling in a room with no headroom.
##
## A SpringArm3D left without a shape casts its child camera's near-plane pyramid, which stops
## the lens two millimetres off whatever it hit. Two millimetres survives nothing: a stomp shake
## lifts the camera up to 0.18 m, and the pivot swings a good deal further than that between two
## physics ticks, so under a castle dungeon's 2.5 m ceiling the near plane crossed the roof and
## the room flickered away for a frame at a time. The arm's own `margin` cannot buy the clearance
## back — godotengine/godot#76220 — so CityWalker sweeps an explicit sphere instead.
##
## Both halves are worth pinning. Too small a probe and the flicker returns; a probe that catches
## on the walker's own capsule would glue the camera to the player's head instead.
##
## Run: powershell -File tools\run_test.ps1 test_camera_clearance
extends Node

## A castle dungeon storey: seven voxels of pitch less a two-voxel slab.
const CEILING_Y := 2.5
const EPS := 0.001

var _failed := false
var _walker: CityWalker
var _ceiling: StaticBody3D


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_walker = CityWalker.new()
	add_child(_walker)
	await get_tree().process_frame
	## The camera is the whole subject here; gravity would only drop the body out of the room.
	_walker.set_physics_process(false)
	_walker.global_position = Vector3.ZERO

	await _test_our_own_body_does_not_stop_the_arm()
	if _failed:
		_quit()
		return
	await _test_a_low_ceiling_keeps_the_near_plane_out()
	_quit()


# ---------------------------------------------------------------------------
# Open sky: the arm reaches its full length
# ---------------------------------------------------------------------------

func _test_our_own_body_does_not_stop_the_arm() -> void:
	await _settle()
	var spring := _spring()
	if spring == null:
		return
	if absf(spring.get_hit_length() - spring.spring_length) > EPS:
		_fail(
			"FAIL the arm stopped at %.3f m of %.3f m with nothing in the way — the sweep is"
			% [spring.get_hit_length(), spring.spring_length]
			+ " catching on the walker's own capsule"
		)
		return
	print("open sky: the arm runs its full %.2f m" % spring.spring_length)


# ---------------------------------------------------------------------------
# Under a dungeon ceiling: the near plane stays clear by more than a shake
# ---------------------------------------------------------------------------

func _test_a_low_ceiling_keeps_the_near_plane_out() -> void:
	_ceiling = StaticBody3D.new()
	_ceiling.name = "Ceiling"
	_ceiling.collision_layer = 1
	var col := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(40.0, 1.0, 40.0)
	col.shape = slab
	col.position = Vector3(0.0, CEILING_Y + 0.5, 0.0)
	_ceiling.add_child(col)
	add_child(_ceiling)
	await _settle()

	var spring := _spring()
	if spring == null:
		return
	if spring.get_hit_length() >= spring.spring_length - EPS:
		_fail("FAIL the ceiling did not shorten the arm at all (%.3f m)" % spring.get_hit_length())
		return
	if spring.get_hit_length() <= EPS:
		_fail("FAIL the arm collapsed onto the pivot — the camera is inside the player's head")
		return

	var clearance := CEILING_Y - _near_plane_top_y()
	## What the clearance has to survive: a full-trauma stomp lifts the lens by this much, and
	## the arm only recomputes on a physics tick, so the slack is all that stands between the
	## shake and the roof.
	var shake_lift := _walker.camera_shake_max_offset_m * 0.65
	if clearance < shake_lift:
		_fail(
			"FAIL the near plane sits %.3f m under the ceiling, less than the %.3f m a shake"
			% [clearance, shake_lift]
			+ " lifts it — the roof will flicker"
		)
		return
	print(
		"low ceiling: arm %.2f m, near plane %.3f m clear, shake lifts %.3f m"
		% [spring.get_hit_length(), clearance, shake_lift]
	)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

## Highest point of the camera's near plane in world space — the first thing to cross a roof.
func _near_plane_top_y() -> float:
	var cam := _walker.get_camera()
	if cam == null:
		_fail("FAIL the walker has no camera")
		return 0.0
	var vp := get_viewport().get_visible_rect().size
	var top := -INF
	for corner: Vector2 in [Vector2.ZERO, Vector2(vp.x, 0.0), Vector2(0.0, vp.y), vp]:
		top = maxf(top, cam.project_position(corner, cam.near).y)
	return top


func _spring() -> SpringArm3D:
	var arm := _walker.get_node_or_null("CameraPivot/SpringArm") as SpringArm3D
	if arm == null:
		_fail("FAIL the walker has no CameraPivot/SpringArm")
	return arm


## The arm only moves on an internal physics tick, so nothing is true until a few have passed.
func _settle() -> void:
	for _i in range(8):
		await get_tree().physics_frame


func _quit() -> void:
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)
