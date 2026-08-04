## One monster standing on one square of the chess court: a visual puppet, nothing more.
##
## Deliberately not an `UndeadUnit`. That would bring aggro that hunts the player, two armies
## that auto-fight, a `tick()` that stops when the player dies, terrain-chewing auras, and
## thirty-two of the forty-slot `MonsterRoster` budget — none of which a chess piece wants.
## A piece moves in straight lines between squares, so it needs no navigation at all: the
## same tweened-path trick `go_ped_actor.gd` already walks its opponents with.
##
## What is borrowed from the monster stack is the part worth borrowing: `CreatureCatalog`
## rows for the bodies (and the loader contract they promise — Node3D root, one
## AnimationPlayer, feet on y=0, facing +Z), `CreatureClips` for the four clips a piece needs,
## and `CreatureVariation`'s recolour to put a piece in its army's colours. Height is normalised
## on the way in, because the catalogue runs 1.8 m to 4.4 m and a board wants a king that reads
## as a king rather than as whichever body was tallest.
##
## Height and colour both arrive as arguments rather than being looked up here: which monster
## plays which piece, how tall it stands and what colour it wears are all one decision, and it
## belongs in `ChessCast` next to each other rather than split across the puppet.
class_name ChessPieceActor
extends Node3D

const CreatureCatalogScript := preload("res://scripts/city/creature_catalog.gd")
const CreatureClipsScript := preload("res://scripts/city/creature_clips.gd")
const CreatureVariationScript := preload("res://scripts/city/creature_variation.gd")

## Metres per second across the board. Fast enough that a full game does not become a
## waiting simulator, slow enough that the walk cycle reads.
const WALK_SPEED := 3.4
## Ground speed the Quaternius walk cycles are authored at, at reference height. The cycle
## is scaled by the body's own height so a stretched giant does not scurry.
const WALK_ANIM_REF_MPS := 1.55
## Seconds to swing round on the spot before a walk or a strike.
const TURN_TIME := 0.22
## Where in the melee clip the blow is considered to land, as a fraction of its length.
const STRIKE_AT := 0.45
## A knight hops rather than walking round the corner, and this is the apex of that hop.
const HOP_HEIGHT := 1.6

## The move animation is finished and the piece stands on `square`.
signal arrived()
## The melee clip has reached its blow — the moment the defender should start dying.
signal struck()
## The melee clip is over and the attacker is back to idle.
signal melee_done()
## The death clip is over. The piece is still in the tree; the arena frees it.
signal death_done()

## Cached PackedScenes, shared across every actor: thirty-two pieces are twelve distinct
## bodies, and loading each GLB once is the difference between a hitch and a stutter.
static var _scene_cache: Dictionary = {}

## Board square this piece occupies, in ChessBoardState coordinates (file, rank).
var square: Vector2i = Vector2i(-1, -1)
## ChessBoardState piece type and colour. Kept here so the arena can read a piece off its
## puppet rather than cross-referencing the board for what it is looking at.
var piece_type: int = 0
var colour: int = 0

var _entry: CreatureCatalog.Entry = null
var _model: Node3D = null
var _anim: AnimationPlayer = null
var _clip_idle: String = ""
var _clip_walk: String = ""
var _clip_melee: String = ""
var _clip_death: String = ""
## measured_height → target height, so the pivot correction scales with the body.
var _build: float = 1.0
var _tween: Tween = null
## Facing at the start of the turn in progress, so a turn takes the short way round.
var _turn_from: float = 0.0
var _dying: bool = false


## Load `body_id` from the catalogue, normalise it to `target_height` metres and stand it at
## `world_pos` facing `yaw`. False when the row or the asset does not hold up its end of the
## loader contract — the caller has a hole on the board and should say so.
func begin(
	body_id: String,
	p_colour: int,
	p_type: int,
	p_square: Vector2i,
	target_height: float,
	band: CreatureVariation.Band,
	world_pos: Vector3,
	yaw: float
) -> bool:
	colour = p_colour
	piece_type = p_type
	square = p_square
	_entry = CreatureCatalogScript.by_id(body_id)
	if _entry == null:
		return false
	if _entry.measured_height <= 0.0:
		push_error("ChessPieceActor: %s has no measured height" % body_id)
		return false
	if not _load_model(target_height, band):
		return false
	global_position = world_pos
	rotation.y = yaw
	play_idle()
	return true


func body_id() -> String:
	return "" if _entry == null else _entry.id


## Standing height in metres after normalisation — what the arena lifts labels and
## highlights over.
func stand_height() -> float:
	return 0.0 if _entry == null else _entry.measured_height * _build


## Drop onto a square with no animation. Used when a saved game is resumed: the pieces
## walked to these squares in the session that saved it, and replaying that march every
## time the district streams in would be an entrance that already happened.
func place_at(p_square: Vector2i, world_pos: Vector3, yaw: float) -> void:
	_kill_tween()
	square = p_square
	global_position = world_pos
	rotation.y = yaw
	play_idle()


## Walk the polyline `waypoints` (world points, XZ only — y comes from the current stand),
## then face `arrive_yaw` and emit `arrived`. `hop` sends the piece over the path in an arc
## instead, which is how a knight gets to jump rather than sliding through its own rank.
func walk_to(
	p_square: Vector2i, waypoints: Array[Vector3], arrive_yaw: float, hop: bool = false
) -> void:
	_kill_tween()
	square = p_square
	if waypoints.is_empty():
		rotation.y = arrive_yaw
		_arrive()
		return
	var stand_y := global_position.y
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_LINEAR)
	var from := global_position
	var legs := 0
	for wp in waypoints:
		var dest := Vector3(wp.x, stand_y, wp.z)
		var span := Vector2(dest.x - from.x, dest.z - from.z).length()
		if span < 0.05:
			continue
		_queue_turn(atan2(dest.x - from.x, dest.z - from.z))
		var dur := span / WALK_SPEED
		if hop:
			_tween.tween_callback(_play_hop)
			_tween.tween_method(_hop_step.bind(from, dest), 0.0, 1.0, maxf(dur, 0.45))
		else:
			_tween.tween_callback(_play_walk)
			_tween.tween_property(self, "global_position", dest, dur)
		from = dest
		legs += 1
	if legs == 0:
		_kill_tween()
		rotation.y = arrive_yaw
		_arrive()
		return
	_queue_turn(arrive_yaw)
	_tween.tween_callback(_arrive)


## Turn on the spot to look at a world point, without moving. The attacker does this before
## it swings.
func face_towards(world_pos: Vector3) -> void:
	var flat := Vector3(world_pos.x - global_position.x, 0.0, world_pos.z - global_position.z)
	if flat.length() < 0.01:
		return
	_kill_tween()
	_tween = create_tween()
	_queue_turn(atan2(flat.x, flat.z))


func play_idle() -> void:
	if _anim == null or _clip_idle.is_empty():
		return
	_anim.speed_scale = 1.0
	_anim.play(_clip_idle)


## Swing once, then fall back to idle. `struck` fires when the blow lands and `melee_done`
## when the clip is over, so the arena can start the defender's death on the hit rather than
## on the wind-up.
func play_melee() -> void:
	if _anim == null or _clip_melee.is_empty():
		melee_done.emit()
		return
	_anim.speed_scale = 1.0
	_anim.play(_clip_melee)
	var clip := _anim.get_animation(_clip_melee)
	var delay := 0.2 if clip == null else clip.length * STRIKE_AT
	## Connecting a method rather than a lambda so the connection dies with the actor: a
	## piece freed mid-swing must not fire into a freed object.
	get_tree().create_timer(delay).timeout.connect(_emit_struck, CONNECT_ONE_SHOT)


## Fall over and stay down. `death_done` fires when the clip is finished; the actor holds
## the last pose until the arena frees it.
func play_death() -> void:
	_kill_tween()
	_dying = true
	if _anim == null or _clip_death.is_empty():
		death_done.emit()
		return
	_anim.speed_scale = 1.0
	_anim.play(_clip_death)


func is_dying() -> bool:
	return _dying


func _emit_struck() -> void:
	struck.emit()


## Append a spin-on-the-spot to the running tween. `lerp_angle` rather than a property tween
## because 3.0 → -3.0 radians is a sixth of a turn one way and five sixths the other, and a
## property tween always takes the long way.
func _queue_turn(target: float) -> void:
	_tween.tween_callback(_begin_turn)
	_tween.tween_method(_turn_step.bind(target), 0.0, 1.0, TURN_TIME)


func _begin_turn() -> void:
	_turn_from = rotation.y


func _turn_step(t: float, target: float) -> void:
	rotation.y = lerp_angle(_turn_from, target, t)


func _play_walk() -> void:
	if _anim == null or _clip_walk.is_empty():
		return
	var ref := WALK_ANIM_REF_MPS * maxf(stand_height() / CreatureCatalog.REFERENCE_HEIGHT, 0.2)
	_anim.speed_scale = clampf(WALK_SPEED / ref, 0.4, 1.6)
	_anim.play(_clip_walk)


## A hop has no authored clip in either Quaternius set, so it is the walk cycle over an arc.
func _play_hop() -> void:
	_play_walk()


func _hop_step(t: float, from: Vector3, dest: Vector3) -> void:
	var flat := from.lerp(dest, t)
	## sin gives zero at both ends, so the piece lands exactly on the square.
	global_position = Vector3(flat.x, from.y + sin(t * PI) * HOP_HEIGHT, flat.z)


func _arrive() -> void:
	_tween = null
	play_idle()
	arrived.emit()


func _kill_tween() -> void:
	if _tween != null and is_instance_valid(_tween):
		_tween.kill()
	_tween = null


func _load_model(target_height: float, band: CreatureVariation.Band) -> bool:
	var packed := _cached_scene(_entry.path)
	if packed == null:
		push_error("ChessPieceActor: %s did not load a scene from %s" % [_entry.id, _entry.path])
		return false
	var inst := packed.instantiate()
	_model = inst as Node3D
	if _model == null:
		push_error("ChessPieceActor: %s root is not Node3D (got %s)" % [_entry.id, inst.get_class()])
		inst.queue_free()
		return false
	_model.name = "CreatureModel"
	add_child(_model)
	if band == null:
		push_error("ChessPieceActor: %s was given no band to paint into" % _entry.id)
		return false
	CreatureVariationScript.paint_flat(_model, band)
	_build = target_height / _entry.measured_height
	_model.scale = Vector3.ONE * _build
	_model.rotation = Vector3(0.0, _entry.model_yaw, 0.0)
	## The pivot correction is authored in the body's own units, so it scales with it.
	_model.position = _entry.model_offset * _build
	_anim = _find_anim(_model)
	if _anim == null:
		push_error("ChessPieceActor: no AnimationPlayer in %s" % _entry.id)
		return false
	_anim.active = true
	var clips := _anim.get_animation_list()
	_clip_idle = CreatureClipsScript.resolve(clips, CreatureClips.Action.IDLE, _entry.id)
	_clip_walk = CreatureClipsScript.resolve(clips, CreatureClips.Action.LOCOMOTION, _entry.id)
	_clip_melee = CreatureClipsScript.resolve(clips, CreatureClips.Action.MELEE, _entry.id)
	_clip_death = CreatureClipsScript.resolve(clips, CreatureClips.Action.DEATH, _entry.id)
	_set_loop(_clip_idle, Animation.LOOP_LINEAR)
	_set_loop(_clip_walk, Animation.LOOP_LINEAR)
	## One swing, one death — a looping death clip is a monster that will not stay down.
	_set_loop(_clip_melee, Animation.LOOP_NONE)
	_set_loop(_clip_death, Animation.LOOP_NONE)
	_anim.animation_finished.connect(_on_clip_finished)
	return true


func _set_loop(clip: String, mode: Animation.LoopMode) -> void:
	if clip.is_empty():
		return
	var anim := _anim.get_animation(clip)
	if anim == null:
		push_error("ChessPieceActor: %s resolved %s to a clip it does not have" % [_entry.id, clip])
		return
	anim.loop_mode = mode


func _on_clip_finished(clip: StringName) -> void:
	var name_str := String(clip)
	if name_str == _clip_melee:
		play_idle()
		melee_done.emit()
	elif name_str == _clip_death:
		death_done.emit()


static func _cached_scene(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if _scene_cache.has(path):
		return _scene_cache[path] as PackedScene
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	_scene_cache[path] = packed
	return packed


static func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var found := _find_anim(c)
		if found != null:
			return found
	return null
