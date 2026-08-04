## Scripted pedestrian: walks to a nearby Tetris cabinet, plays Interact, and AI-plays.
class_name TetrisPedNpc
extends Node3D

const PedOutfitScript := preload("res://scripts/humans/ped_outfit.gd")
const PedOutfitApplierScript := preload("res://scripts/humans/ped_outfit_applier.gd")
const TetrisAIScript := preload("res://scripts/city/tetris_ai.gd")

const FALLBACK_MALE: Array[String] = [
	"res://assets/humans/male_base.gltf",
	"res://assets/humans/male_base.glb",
]
const FALLBACK_FEMALE: Array[String] = [
	"res://assets/humans/female_base.gltf",
	"res://assets/humans/female_base.glb",
]

const NEAR_TETRIS_M := 14.0
const WALK_SPEED := 1.7
const ARRIVE_M := 0.55
const AI_TICK_SEC := 0.09
const INTERACT_REPLAY_SEC := 2.4

enum Phase { IDLE, WALK, FACE, PLAY }

var _rng := RandomNumberGenerator.new()
var _body: Node3D
var _anim: AnimationPlayer
var _machine: Node3D
var _phase: int = Phase.IDLE
var _target: Vector3 = Vector3.ZERO
var _walk_speed: float = WALK_SPEED
var _ai_timer: float = 0.0
var _anim_timer: float = 0.0
var _plan: Dictionary = {}
var _plan_piece_id: int = 0
var _claimed: bool = false
var _slot_index: int = 0


func begin(spawn_pos: Vector3, tetris: Node3D, slot_index: int = 0) -> void:
	_rng.randomize()
	_slot_index = slot_index
	_machine = tetris
	_spawn_visual()
	_start_behavior(spawn_pos)


func _start_behavior(spawn_pos: Vector3) -> void:
	if not is_inside_tree():
		push_error("TetrisPedNpc.begin: node must be added to the tree first")
		return
	global_position = spawn_pos
	if _machine == null or not is_instance_valid(_machine):
		_set_phase_idle()
		return
	if not _machine.has_method("is_broken"):
		push_error("TetrisPedNpc: machine missing Tetris API")
		_set_phase_idle()
		return
	if bool(_machine.call("is_broken")):
		_set_phase_idle()
		return
	if _machine.has_method("is_powered") and not bool(_machine.call("is_powered")):
		_set_phase_idle()
		return
	var dist := global_position.distance_to(_machine.global_position)
	if dist > NEAR_TETRIS_M:
		_set_phase_idle()
		return
	## Aiming at the cabinet puts the hit point on its face — stand on the machine's ground plane.
	global_position.y = _machine.global_position.y
	_target = _stand_slot_world()
	_target.y = global_position.y
	_phase = Phase.WALK
	_play_loco_for_speed(WALK_SPEED)


func _ready() -> void:
	set_process(true)


func _exit_tree() -> void:
	_release_claim()


func _process(delta: float) -> void:
	match _phase:
		Phase.WALK:
			_process_walk(delta)
		Phase.FACE:
			_process_face(delta)
		Phase.PLAY:
			_process_play(delta)
		_:
			pass


func _stand_slot_world() -> Vector3:
	var base: Vector3 = _machine.call("get_stand_world_position")
	## Spread multiple peds sideways along the cabinet front.
	var right := _machine.global_transform.basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	else:
		right = right.normalized()
	## Slot 0 centers on the screen; later peds alternate to either side.
	var idx := _slot_index % 5
	var rank := float((idx + 1) / 2)
	var dir := 1.0 if idx % 2 == 1 else -1.0
	return base + right * (rank * dir * 0.6)


func _process_walk(delta: float) -> void:
	if not _machine_ok():
		_set_phase_idle()
		return
	_target = _stand_slot_world()
	_target.y = global_position.y
	var to := Vector3(_target.x - global_position.x, 0.0, _target.z - global_position.z)
	var dist := to.length()
	if dist <= ARRIVE_M:
		global_position = Vector3(_target.x, global_position.y, _target.z)
		_phase = Phase.FACE
		_play_loco_for_speed(0.0)
		return
	var step := minf(_walk_speed * delta, dist)
	var dir := to / dist
	global_position += Vector3(dir.x * step, 0.0, dir.z * step)
	rotation.y = atan2(-dir.x, -dir.z)
	_play_loco_for_speed(_walk_speed)


func _process_face(delta: float) -> void:
	if not _machine_ok():
		_set_phase_idle()
		return
	var to_m := _machine.global_position - global_position
	to_m.y = 0.0
	if to_m.length_squared() < 0.0001:
		_enter_play()
		return
	var want := atan2(-to_m.x, -to_m.z)
	var diff := wrapf(want - rotation.y, -PI, PI)
	rotation.y += clampf(diff, -4.0 * delta, 4.0 * delta)
	_play_loco_for_speed(0.0)
	if absf(wrapf(want - rotation.y, -PI, PI)) < 0.06:
		rotation.y = want
		_enter_play()


func _enter_play() -> void:
	if not _machine_ok():
		_set_phase_idle()
		return
	## Claim only once at the cabinet — avoids locking input while a ped is stuck approaching.
	if not _claimed:
		if not bool(_machine.call("claim_ai_controller", self)):
			## Someone else is already playing — hang out and watch.
			_set_phase_idle()
			return
		_claimed = true
	_phase = Phase.PLAY
	_plan.clear()
	_plan_piece_id = 0
	_ai_timer = 0.0
	_anim_timer = 0.0
	if _anim != null:
		QuaterniusLocomotion.play_interact(_anim)


func _process_play(delta: float) -> void:
	if not _machine_ok():
		_abort_play()
		return
	if bool(_machine.call("is_broken")) or bool(_machine.call("is_game_over")):
		_abort_play()
		return

	_anim_timer += delta
	if _anim != null:
		if _anim_timer >= INTERACT_REPLAY_SEC:
			_anim_timer = 0.0
			QuaterniusLocomotion.play_interact(_anim)
		elif not QuaterniusLocomotion.is_interact_playing(_anim):
			QuaterniusLocomotion.play_idle_talking(_anim)

	if not bool(_machine.call("is_playable")):
		_plan.clear()
		_plan_piece_id = 0
		return

	_ai_timer += delta
	if _ai_timer < AI_TICK_SEC:
		return
	_ai_timer = 0.0
	_ai_step()


func _ai_step() -> void:
	var piece_v: Variant = _machine.call("get_active_piece")
	if typeof(piece_v) != TYPE_DICTIONARY:
		push_error("TetrisPedNpc: get_active_piece did not return Dictionary")
		return
	var piece: Dictionary = piece_v
	if piece.is_empty():
		_plan.clear()
		return
	var pid := int(piece.get("id", 0))
	if _plan.is_empty() or _plan_piece_id != pid:
		_plan = TetrisAIScript.choose_placement(_machine)
		_plan_piece_id = pid
		if _plan.is_empty():
			## Still act — soft-drop rather than freeze the cabinet.
			_machine.call("try_ai_soft_drop")
			return

	var want_rot := int(_plan.get("rot", 0))
	var want_x := int(_plan.get("x", 0))
	var cur_rot := int(piece.get("rot", 0))
	var cur_x := int(piece.get("x", 0))

	if cur_rot != want_rot:
		if not bool(_machine.call("try_ai_rotate", 1)):
			## Rotation blocked — drop what we have.
			_machine.call("try_ai_soft_drop")
		return
	if cur_x < want_x:
		if not bool(_machine.call("try_ai_left")):
			_machine.call("try_ai_soft_drop")
		return
	if cur_x > want_x:
		if not bool(_machine.call("try_ai_right")):
			_machine.call("try_ai_soft_drop")
		return
	_machine.call("try_ai_soft_drop")


func _machine_ok() -> bool:
	return _machine != null and is_instance_valid(_machine)


func _set_phase_idle() -> void:
	_phase = Phase.IDLE
	_play_loco_for_speed(0.0)


func _abort_play() -> void:
	_release_claim()
	_machine = null
	_plan.clear()
	_set_phase_idle()


func _release_claim() -> void:
	if _claimed and _machine_ok() and _machine.has_method("release_ai_controller"):
		_machine.call("release_ai_controller", self)
	_claimed = false


func _play_loco_for_speed(speed: float) -> void:
	if _anim == null:
		return
	if speed < 0.05:
		QuaterniusLocomotion.play_idle(_anim)
	else:
		QuaterniusLocomotion.play_walk(_anim, speed)


func _spawn_visual() -> void:
	var female := _rng.randf() < 0.5
	var outfit: PedOutfit = PedOutfitScript.random(_rng, female, PedOutfit.Faction.CIVILIAN)
	var path := ""
	if outfit != null:
		path = outfit.scene_path
	if path == "" or not ResourceLoader.exists(path):
		path = _fallback_path(female)
	if path == "" or not ResourceLoader.exists(path):
		_spawn_capsule(female)
		return
	var packed := load(path)
	if not (packed is PackedScene):
		_spawn_capsule(female)
		return
	_body = (packed as PackedScene).instantiate() as Node3D
	_body.name = "Body"
	_body.rotation.y = PI
	add_child(_body)
	var scale_f := _rng.randf_range(0.94, 1.06)
	scale = Vector3(scale_f, scale_f, scale_f)
	if outfit != null:
		PedOutfitApplierScript.apply_to_body_root(_body, outfit, female)
	_anim = AnimationPlayer.new()
	_anim.name = "AnimationPlayer"
	_body.add_child(_anim)
	QuaterniusLocomotion.attach_npc(_anim)


func _fallback_path(female: bool) -> String:
	var paths := FALLBACK_FEMALE if female else FALLBACK_MALE
	for candidate in paths:
		if ResourceLoader.exists(candidate):
			return candidate
	return ""


func _spawn_capsule(female: bool) -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var mi := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.18 if female else 0.2
	capsule.height = 1.65 if female else 1.75
	mi.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.68, 0.54) if female else Color(0.78, 0.58, 0.44)
	mi.material_override = mat
	mi.position.y = capsule.height * 0.5
	_body.add_child(mi)
	_anim = AnimationPlayer.new()
	_body.add_child(_anim)
	QuaterniusLocomotion.attach_npc(_anim)
