## The launch-and-land animation that covers a district hop.
##
## A hop used to be an instant teleport hidden behind the title splash: the player stared at
## art for however long the destination took to bake. This plays the wait instead. The body is
## thrown about fifty metres up while the camera looks back down at the district being left,
## then the camera turns to the sky and holds there for as long as the bake needs, then it turns
## back down and rides the descent onto the new district's spawn.
##
## The hold is the trick. The player is not actually climbing during it — they are parked over
## the destination so the streaming bubble bakes that tile — so the only thing selling continued
## ascent is a handful of birds falling past the camera. Nothing else in the frame has a fixed
## scale up there; clouds are a shader on the sky dome and do not move relative to the viewer.
##
## Phases are stepped by `advance`, not by a Tween, because the hold has no known length: it
## ends when the district reports ready, which can be one second or three minutes.
class_name DistrictHopCutscene
extends Node3D

const BirdActorScript := preload("res://scripts/city/bird_actor.gd")

enum Phase {
	## Nothing running. Also where `finish` leaves it.
	IDLE,
	## Climbing away from the origin district, camera swinging down to watch it shrink.
	RISE,
	## Parked over the destination, looking up, birds streaming past. Ends on `start_descent`.
	HOLD,
	## Riding down onto the new district's spawn, camera swinging back to level.
	DESCEND,
}

## How far above their own feet the launch throws the player, in metres.
const RISE_M := 50.0
## Seconds the scripted legs take. The hold in between runs as long as the bake does.
const RISE_SEC := 1.7
const DESCENT_SEC := 2.2
## Camera pitch targets, radians. Down is far enough to watch the ground fall away without
## clipping the walker's own back; up clears the horizon so the frame is sky.
const PITCH_DOWN := -1.15
const PITCH_UP := 0.72
## Where the camera settles once the player has their feet back.
const PITCH_LEVEL := -0.35
## Fraction of the descent spent looking down at the arriving district before the camera
## starts easing back to a playable angle.
const DESCENT_LOOK_DOWN_U := 0.55

## Birds streaming past during the hold.
const HOLD_BIRDS := 14
## Their descent rate past the camera, in metres per second.
const BIRD_FALL_MIN := 6.0
const BIRD_FALL_MAX := 11.0
## Box they are recycled through, relative to the camera: how far out to the sides they can
## pass, how far above they appear, and how far below they get retired. Kept tight around the
## camera because the hold looks up — a box the size of the sky puts most of the flock behind
## the viewer, where it sells nothing, and empties out the one part of the frame that matters.
const BIRD_SPREAD_M := 16.0
const BIRD_ABOVE_M := 26.0
const BIRD_BELOW_M := 16.0
## They read as distant birds passing, not as gulls buzzing the camera.
const BIRD_SIZE_MIN := 0.9
const BIRD_SIZE_MAX := 1.6

var _walker: CityWalker = null
var _phase: Phase = Phase.IDLE
## Seconds into the current timed phase, and how long that phase runs for.
var _elapsed: float = 0.0
var _duration: float = 0.0
var _from_pos: Vector3 = Vector3.ZERO
var _to_pos: Vector3 = Vector3.ZERO
var _from_pitch: float = 0.0
var _birds: Array[BirdActor] = []
var _coats: Array[BirdActor.Coat] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _process(delta: float) -> void:
	advance(delta)


# ---------------------------------------------------------------------------
# Phases
# ---------------------------------------------------------------------------

## Take the body. The walker keeps its own physics off (the hop already did that) — this is the
## input and look lock, so a mouse drag cannot fight the scripted camera.
func begin(walker: CityWalker) -> void:
	if walker == null or not is_instance_valid(walker):
		push_error("DistrictHopCutscene.begin: no walker")
		return
	_walker = walker
	_walker.set_cutscene_locked(true)


## Launch. Climbs `RISE_M` from wherever the feet are while the camera swings down.
func start_rise() -> void:
	if _walker == null:
		push_error("DistrictHopCutscene.start_rise: begin() first")
		return
	_from_pos = _walker.global_position
	_to_pos = _from_pos + Vector3(0.0, RISE_M, 0.0)
	_from_pitch = _walker.get_pitch()
	_elapsed = 0.0
	_duration = RISE_SEC
	_phase = Phase.RISE


## Park over the destination and look up. `hold_pos` is where the streaming bubble needs the
## player to sit, which is a different tile entirely — the camera is pointed at empty sky for
## the swap so the jump across the map is never in frame.
func start_hold(hold_pos: Vector3) -> void:
	if _walker == null:
		push_error("DistrictHopCutscene.start_hold: begin() first")
		return
	_walker.global_position = hold_pos
	_walker.velocity = Vector3.ZERO
	_walker.set_pitch(PITCH_UP)
	_elapsed = 0.0
	_duration = 0.0
	_phase = Phase.HOLD
	_spawn_hold_birds()


## Ride down onto the new district. `feet` is the final standing position.
func start_descent(feet: Vector3) -> void:
	if _walker == null:
		push_error("DistrictHopCutscene.start_descent: begin() first")
		return
	_clear_birds()
	_from_pos = _walker.global_position
	_to_pos = feet
	_from_pitch = _walker.get_pitch()
	_elapsed = 0.0
	_duration = DESCENT_SEC
	_phase = Phase.DESCEND


## Step the running phase. Called every frame by `_process`; tests drive it directly with a
## fixed delta so a scene that runs at 300 fps and one that runs at 30 measure the same thing.
func advance(delta: float) -> void:
	if _walker == null or not is_instance_valid(_walker):
		return
	match _phase:
		Phase.RISE:
			_advance_leg(delta, PITCH_DOWN)
		Phase.HOLD:
			_elapsed += delta
			_advance_birds(delta)
		Phase.DESCEND:
			_advance_descent(delta)
		Phase.IDLE:
			pass


## True once the current timed leg has played out. The hold is never done on its own — it ends
## when the caller decides the district is ready.
func is_phase_done() -> bool:
	if _phase == Phase.IDLE:
		return true
	if _phase == Phase.HOLD:
		return false
	return _elapsed >= _duration


## Block until the running leg finishes. The hold is excluded on purpose: awaiting it would
## never return.
func await_phase() -> void:
	while not is_phase_done():
		await get_tree().process_frame


## Hand the body back. Leaves the walker wherever the last phase put it.
func finish() -> void:
	_clear_birds()
	_phase = Phase.IDLE
	if _walker != null and is_instance_valid(_walker):
		_walker.set_cutscene_locked(false)
	_walker = null


func phase() -> Phase:
	return _phase


func bird_count() -> int:
	return _birds.size()


# ---------------------------------------------------------------------------
# Motion
# ---------------------------------------------------------------------------

func _advance_leg(delta: float, pitch_target: float) -> void:
	_elapsed = minf(_elapsed + delta, _duration)
	var u := _eased()
	_walker.global_position = _from_pos.lerp(_to_pos, u)
	_walker.velocity = Vector3.ZERO
	_walker.set_pitch(lerpf(_from_pitch, pitch_target, u))


## The descent looks down at the district it is falling toward, then eases back to a playable
## angle over the last stretch so the player is not staring at their own feet on touchdown.
func _advance_descent(delta: float) -> void:
	_elapsed = minf(_elapsed + delta, _duration)
	var u := _eased()
	_walker.global_position = _from_pos.lerp(_to_pos, u)
	_walker.velocity = Vector3.ZERO
	if u <= DESCENT_LOOK_DOWN_U:
		_walker.set_pitch(lerpf(_from_pitch, PITCH_DOWN, u / DESCENT_LOOK_DOWN_U))
	else:
		var back := (u - DESCENT_LOOK_DOWN_U) / (1.0 - DESCENT_LOOK_DOWN_U)
		_walker.set_pitch(lerpf(PITCH_DOWN, PITCH_LEVEL, back))


## Smoothstep, so a leg leaves and arrives without a jolt.
func _eased() -> float:
	if _duration <= 0.0:
		return 1.0
	var u := clampf(_elapsed / _duration, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


# ---------------------------------------------------------------------------
# Hold birds
# ---------------------------------------------------------------------------

func _spawn_hold_birds() -> void:
	if not _birds.is_empty():
		return
	if _coats.is_empty():
		_coats = BirdActorScript.build_species_coats()
	var eye := _walker.global_position
	for i in range(HOLD_BIRDS):
		var bird: BirdActor = BirdActorScript.new()
		bird.name = "HopBird_%d" % i
		add_child(bird)
		var coat := _coats[_rng.randi_range(0, _coats.size() - 1)]
		bird.build(
			coat.body, coat.accent, coat.beak, _rng.randf_range(BIRD_SIZE_MIN, BIRD_SIZE_MAX)
		)
		_birds.append(bird)
		## Stagger the first pass over the whole box, otherwise the flock arrives as one wave.
		_recycle_bird(bird, eye, _rng.randf_range(-BIRD_BELOW_M, BIRD_ABOVE_M))
	_advance_birds(0.0)


## Send one bird back to the top of the box on a fresh diagonal. `start_y_offset` is where it
## enters relative to the camera.
func _recycle_bird(bird: BirdActor, eye: Vector3, start_y_offset: float) -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var out := _rng.randf_range(BIRD_SPREAD_M * 0.35, BIRD_SPREAD_M)
	var side := Vector3(cos(angle), 0.0, sin(angle))
	var from := eye + side * out + Vector3(0.0, start_y_offset, 0.0)
	bird.global_position = from
	## Aimed down and further out, so it glides past on a diagonal instead of dropping like a
	## stone. The player is standing still: this slant is the whole sense of movement.
	var fall := _rng.randf_range(BIRD_FALL_MIN, BIRD_FALL_MAX)
	bird.cruise_speed = fall
	bird.flee_speed = fall
	bird.velocity = Vector3(0.0, -fall, 0.0)
	bird.fly_to(from + side * out * 0.6 + Vector3(0.0, -(BIRD_ABOVE_M + BIRD_BELOW_M), 0.0),
		Vector3.INF)


func _advance_birds(delta: float) -> void:
	var eye := _walker.global_position
	for bird in _birds:
		if not is_instance_valid(bird):
			continue
		if delta > 0.0:
			bird.tick(delta)
		if bird.global_position.y < eye.y - BIRD_BELOW_M:
			_recycle_bird(bird, eye, BIRD_ABOVE_M)


func _clear_birds() -> void:
	for bird in _birds:
		if is_instance_valid(bird):
			bird.queue_free()
	_birds.clear()
