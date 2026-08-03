## Scripted Go opponent / ambient player with tier-visible outfit.
class_name GoPedActor
extends Node3D

const PedOutfitScript := preload("res://scripts/humans/ped_outfit.gd")
const PedOutfitApplierScript := preload("res://scripts/humans/ped_outfit_applier.gd")

const FALLBACK_MALE: Array[String] = [
	"res://assets/humans/male_base.gltf",
	"res://assets/humans/male_base.glb",
]
const FALLBACK_FEMALE: Array[String] = [
	"res://assets/humans/female_base.gltf",
	"res://assets/humans/female_base.glb",
]

## Quaternius rigs, then the glTF exporter variants, then the arm as a last resort.
const HAND_BONES: Array[StringName] = [
	&"RightHand",
	&"hand_r",
	&"hand.R",
	&"RightLowerArm",
	&"lowerarm_r",
	&"LeftHand",
	&"hand_l",
]

signal seat_reached()

enum Phase { IDLE, WALK, SEATED, THINK }

var tier: StringName = &"novice"
var _rng := RandomNumberGenerator.new()
var _body: Node3D = null
var _anim: AnimationPlayer = null
var _phase: int = Phase.IDLE
var _face_yaw: float = 0.0
var _walk_tween: Tween = null
const WALK_SPEED := 1.7


func begin_as_invite(spawn_pos: Vector3, p_tier: StringName, face_yaw: float = 0.0) -> void:
	tier = p_tier
	_face_yaw = face_yaw
	_rng.seed = hash(String(tier)) ^ 0x60A11
	_spawn_visual()
	global_position = spawn_pos
	rotation.y = face_yaw
	_phase = Phase.IDLE
	if _anim != null:
		QuaterniusLocomotion.play_idle(_anim)


func walk_to_seat(seat: Vector3, face_yaw: float) -> bool:
	return walk_path([seat], face_yaw)


## Drop straight into the seat, already facing the table. Resuming a saved match: the
## opponent walked over during the session that saved it, and watching them arrive again
## every time the district streams in would replay an entrance that already happened.
func seat_immediately(seat: Vector3, face_yaw: float) -> void:
	if _walk_tween != null and is_instance_valid(_walk_tween):
		_walk_tween.kill()
		_walk_tween = null
	_face_yaw = face_yaw
	global_position = seat
	_arrive_at_seat()


## Walk a polyline in XZ (around obstacles), then face `face_yaw` at the seat.
## Returns true when a walk tween is running (await `seat_reached`); false if already seated.
func walk_path(waypoints: Array[Vector3], face_yaw: float) -> bool:
	_face_yaw = face_yaw
	_phase = Phase.WALK
	if _walk_tween != null and is_instance_valid(_walk_tween):
		_walk_tween.kill()
		_walk_tween = null
	if waypoints.is_empty():
		_arrive_at_seat()
		return false
	if _anim != null:
		QuaterniusLocomotion.play_walk(_anim, WALK_SPEED)
	_walk_tween = create_tween()
	_walk_tween.set_trans(Tween.TRANS_LINEAR)
	var y := global_position.y
	var from := global_position
	var segments := 0
	for wp in waypoints:
		var dest := Vector3(wp.x, y, wp.z)
		var dist := Vector2(dest.x - from.x, dest.z - from.z).length()
		if dist < 0.12:
			from = dest
			continue
		var look := dest - from
		look.y = 0.0
		var yaw := atan2(-look.x, -look.z)
		var dur := clampf(dist / WALK_SPEED, 0.2, 8.0)
		_walk_tween.tween_callback(func() -> void: rotation.y = yaw)
		_walk_tween.tween_property(self, "global_position", dest, dur)
		from = dest
		segments += 1
	if segments == 0:
		_walk_tween.kill()
		_walk_tween = null
		_arrive_at_seat()
		return false
	_walk_tween.tween_callback(_arrive_at_seat)
	return true


## World point of the hand that reaches out to the board — where move VFX start. The
## proxy capsule has no skeleton, so fall back to a point in front of the chest.
func hand_world_pos() -> Vector3:
	var skel: Skeleton3D = _find_skeleton(_body) if _body != null else null
	if skel != null:
		skel.force_update_all_bone_transforms()
		for bone_name in HAND_BONES:
			var idx := skel.find_bone(String(bone_name))
			if idx >= 0:
				return skel.to_global(skel.get_bone_global_pose(idx).origin)
	return global_position + global_transform.basis * Vector3(0.0, 1.05, -0.35)


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func set_thinking(on: bool) -> void:
	if _phase == Phase.WALK:
		return
	if on:
		_phase = Phase.THINK
		if _anim != null:
			QuaterniusLocomotion.play_interact(_anim)
	else:
		_phase = Phase.SEATED
		if _anim != null:
			QuaterniusLocomotion.play_idle_talking(_anim)


func _arrive_at_seat() -> void:
	_phase = Phase.SEATED
	rotation.y = _face_yaw
	## Mesh is authored facing +Z; keep the −Z root convention after locomotion clips.
	if _body != null and is_instance_valid(_body):
		_body.rotation.y = PI
	if _anim != null:
		QuaterniusLocomotion.play_idle_talking(_anim)
	seat_reached.emit()


func _spawn_visual() -> void:
	## Keep InviteHit (and other non-body) children; only replace the mesh body.
	if _body != null and is_instance_valid(_body):
		_body.queue_free()
		_body = null
	var female := String(tier) == "novice"
	var outfit: PedOutfit = PedOutfitScript.random(_rng, female, PedOutfit.Faction.CIVILIAN)
	match String(tier):
		"dan":
			outfit.proxy_color = Color(0.12, 0.1, 0.1)
			outfit.shirt = Color(0.12, 0.1, 0.1)
			outfit.pants = Color(0.72, 0.55, 0.18)
		"club":
			outfit.proxy_color = Color(0.18, 0.28, 0.48)
			outfit.shirt = Color(0.18, 0.28, 0.48)
			outfit.pants = Color(0.85, 0.85, 0.88)
		_:
			outfit.proxy_color = Color(0.35, 0.55, 0.38)
			outfit.shirt = Color(0.35, 0.55, 0.38)
			outfit.pants = Color(0.7, 0.65, 0.5)
	var path := outfit.scene_path if outfit != null else ""
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
	match String(tier):
		"dan":
			mat.albedo_color = Color(0.12, 0.1, 0.1)
		"club":
			mat.albedo_color = Color(0.18, 0.28, 0.48)
		_:
			mat.albedo_color = Color(0.35, 0.55, 0.38)
	mi.material_override = mat
	mi.position.y = capsule.height * 0.5
	_body.add_child(mi)
	_anim = AnimationPlayer.new()
	_body.add_child(_anim)
	QuaterniusLocomotion.attach_npc(_anim)
