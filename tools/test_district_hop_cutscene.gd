## The launch-and-land animation that covers a district hop.
##
## What is at risk, and therefore checked:
##   - The hold has no known length. It ends when the destination reports ready, which can be
##     one second or three minutes, so it must never time itself out or finish on its own —
##     a hold that ended early would drop the player onto an unbaked tile.
##   - The camera is the whole point. Looking down on the way up, up during the wait, and down
##     again on the way in is the difference between a cutscene and a teleport with extra steps.
##   - Nothing else in the sky has a fixed scale, so the birds falling past are the only thing
##     selling the climb. They have to keep coming for the whole hold, however long it runs.
##   - The animation hijacks the body and the input. If `finish` ever fails to hand both back
##     the player is left frozen and looking at clouds, which is a soft lock.
##   - The landing has to end exactly on the footing the hop resolved, not near it.
##
## Run: powershell -File tools\run_test.ps1 test_district_hop_cutscene
extends Node3D

const DistrictHopCutsceneScript := preload("res://scripts/city/district_hop_cutscene.gd")

const SIM_DT := 1.0 / 60.0
## Long enough that any timed leg would have finished several times over.
const LONG_HOLD_STEPS := 900
const START := Vector3(40.0, 8.0, -25.0)
const LANDING := Vector3(-310.0, 5.4, 620.0)

var _failed := false
var _walker: CityWalker
var _scene: DistrictHopCutscene


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_walker = CityWalker.new()
	add_child(_walker)
	await get_tree().process_frame
	## Gravity would drag the body out from under the animation.
	_walker.set_physics_process(false)
	_walker.global_position = START

	_scene = DistrictHopCutsceneScript.new() as DistrictHopCutscene
	add_child(_scene)
	## Step the phases by hand instead of by frame, so a 300 fps run and a 30 fps one measure
	## the same animation.
	_scene.set_process(false)

	_check_launch_climbs_and_looks_down()
	_check_hold_waits_forever_and_looks_up()
	_check_hold_keeps_birds_coming()
	_check_descent_lands_on_its_mark()
	_check_finish_hands_the_body_back()
	_check_abandoned_hold_leaves_nothing_behind()

	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------

func _check_launch_climbs_and_looks_down() -> void:
	_scene.begin(_walker)
	if not _walker.is_cutscene_locked():
		_fail("FAIL begin() did not take the body — the player can still walk off mid-launch")
	_scene.start_rise()
	var pitch_before := _walker.get_pitch()
	var steps := _run_phase()
	var climbed := _walker.global_position.y - START.y
	if absf(climbed - DistrictHopCutsceneScript.RISE_M) > 0.5:
		_fail(
			"FAIL launch climbed %.1f m, wanted %.1f"
			% [climbed, DistrictHopCutsceneScript.RISE_M]
		)
	## XZ must not drift: the launch is straight up off the spot the player was standing on.
	if absf(_walker.global_position.x - START.x) > 0.01 or absf(_walker.global_position.z - START.z) > 0.01:
		_fail("FAIL launch drifted off the takeoff spot to %s" % _walker.global_position)
	if _walker.get_pitch() >= pitch_before:
		_fail(
			"FAIL camera did not turn down during the launch (%.2f → %.2f rad)"
			% [pitch_before, _walker.get_pitch()]
		)
	print("launch: +%.1f m over %d steps, camera to %.2f rad" % [
		climbed, steps, _walker.get_pitch()
	])


# ---------------------------------------------------------------------------
# Hold
# ---------------------------------------------------------------------------

func _check_hold_waits_forever_and_looks_up() -> void:
	var hover := Vector3(LANDING.x, LANDING.y + 60.0, LANDING.z)
	_scene.start_hold(hover)
	if _walker.get_pitch() <= 0.0:
		_fail("FAIL the hold is meant to look at sky, camera is at %.2f rad" % _walker.get_pitch())
	for _step in range(LONG_HOLD_STEPS):
		_scene.advance(SIM_DT)
		if _scene.is_phase_done():
			_fail("FAIL the hold ended on its own — the district may not be baked yet")
			return
	if _scene.phase() != DistrictHopCutscene.Phase.HOLD:
		_fail("FAIL the hold left its phase after %d steps" % LONG_HOLD_STEPS)
	if not _walker.global_position.is_equal_approx(hover):
		_fail("FAIL the hold drifted off the destination to %s" % _walker.global_position)
	print("hold: still waiting after %.0f s, camera at %.2f rad" % [
		LONG_HOLD_STEPS * SIM_DT, _walker.get_pitch()
	])


## The birds are the only fixed-scale thing up there, so they are the only thing selling the
## climb. A flock that falls out of the box once and is never sent back leaves the second half
## of a long bake as a static sky — so what matters is that they keep being recycled, and that
## none of them wander off somewhere the camera will never see them again.
func _check_hold_keeps_birds_coming() -> void:
	var flock := _scene.bird_count()
	if flock <= 0:
		_fail("FAIL the hold has no birds — nothing sells the climb")
		return
	var eye := _walker.global_position
	var birds := _hold_birds()
	var was: Array[float] = []
	for bird in birds:
		was.append(bird.global_position.y)
	var recycles := 0
	var lowest := 0.0
	var widest := 0.0
	for _step in range(LONG_HOLD_STEPS):
		_scene.advance(SIM_DT)
		for i in range(birds.size()):
			var y := birds[i].global_position.y
			## Only a recycle sends a bird upward; the flight itself is all downward.
			if y > was[i] + 1.0:
				recycles += 1
			was[i] = y
			lowest = minf(lowest, y - eye.y)
			widest = maxf(widest, Vector2(
				birds[i].global_position.x - eye.x, birds[i].global_position.z - eye.z
			).length())
	if recycles < flock:
		_fail(
			"FAIL only %d recycles in %.0f s of holding with %d birds — the sky runs empty on a"
			% [recycles, LONG_HOLD_STEPS * SIM_DT, flock]
			+ " long bake"
		)
	if lowest < -DistrictHopCutsceneScript.BIRD_BELOW_M * 1.5:
		_fail("FAIL a bird fell %.0f m below the camera before being recycled" % -lowest)
	if widest > DistrictHopCutsceneScript.BIRD_SPREAD_M * 2.0:
		_fail("FAIL a bird drifted %.0f m sideways, out of anything the camera frames" % widest)
	if _scene.bird_count() != flock:
		_fail("FAIL the flock changed size during the hold")
	print("hold birds: %d flying, %d recycles over %.0f s, box %.0f m down / %.0f m wide" % [
		flock, recycles, LONG_HOLD_STEPS * SIM_DT, -lowest, widest
	])


func _hold_birds() -> Array[BirdActor]:
	var out: Array[BirdActor] = []
	for child in _scene.get_children():
		var bird := child as BirdActor
		if bird != null:
			out.append(bird)
	return out


# ---------------------------------------------------------------------------
# Descent
# ---------------------------------------------------------------------------

func _check_descent_lands_on_its_mark() -> void:
	var pitch_up := _walker.get_pitch()
	_scene.start_descent(LANDING)
	if _scene.bird_count() != 0:
		_fail("FAIL the hold birds followed the player down")
	var looked_down := pitch_up
	var steps := 0
	while not _scene.is_phase_done() and steps < 2000:
		_scene.advance(SIM_DT)
		looked_down = minf(looked_down, _walker.get_pitch())
		steps += 1
	if not _walker.global_position.is_equal_approx(LANDING):
		_fail(
			"FAIL landed at %s, footing was %s"
			% [_walker.global_position, LANDING]
		)
	if looked_down >= 0.0:
		_fail("FAIL camera never turned down at the arriving district (lowest %.2f rad)" % looked_down)
	## Ending nose-down would leave the player staring at the pavement they just landed on.
	if absf(_walker.get_pitch() - DistrictHopCutsceneScript.PITCH_LEVEL) > 0.05:
		_fail(
			"FAIL camera finished at %.2f rad instead of level %.2f"
			% [_walker.get_pitch(), DistrictHopCutsceneScript.PITCH_LEVEL]
		)
	print("descent: %d steps, dipped to %.2f rad, settled at %.2f rad" % [
		steps, looked_down, _walker.get_pitch()
	])


# ---------------------------------------------------------------------------
# Teardown
# ---------------------------------------------------------------------------

func _check_finish_hands_the_body_back() -> void:
	_scene.finish()
	if _walker.is_cutscene_locked():
		_fail("FAIL finish() left the body locked — the player cannot move")
	if _scene.bird_count() != 0:
		_fail("FAIL finish() left birds behind")
	if _scene.phase() != DistrictHopCutscene.Phase.IDLE:
		_fail("FAIL finish() left the animation running")
	## Advancing a finished scene must be harmless: a failed hop calls finish mid-phase.
	_scene.advance(SIM_DT)
	print("teardown: body returned, %d birds left" % _scene.bird_count())


## A hop that fails during the bake aborts from inside the hold. That path must also clean up.
func _check_abandoned_hold_leaves_nothing_behind() -> void:
	_scene.begin(_walker)
	_scene.start_hold(Vector3(0.0, 120.0, 0.0))
	for _step in range(30):
		_scene.advance(SIM_DT)
	if _scene.bird_count() <= 0:
		_fail("FAIL the second hold spawned no birds — the flock does not come back")
	_scene.finish()
	if _scene.bird_count() != 0 or _walker.is_cutscene_locked():
		_fail("FAIL aborting from the hold left the animation half up")
	print("abort: hold torn down cleanly")


# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------

## Step the running leg to its end and report how many steps it took. Guarded so a leg that
## never finishes fails the test instead of hanging the run.
func _run_phase() -> int:
	var steps := 0
	while not _scene.is_phase_done() and steps < 2000:
		_scene.advance(SIM_DT)
		steps += 1
	if steps >= 2000:
		_fail("FAIL a timed leg never finished")
	return steps
