extends SceneTree


const MALE_PATH := "res://assets/humans/male_base.gltf"
const QUAT_PATH := "res://assets/humans/animations/quaternius/AnimationLibrary_Godot_Standard.gltf"
const ANIM_IDLE := &"Idle"
const ANIM_WALK := &"Walk"
const LIB_NAME := &"quat"

const PROFILE_ARM_BONES: Array[String] = [
	"LeftUpperArm", "RightUpperArm",
	"LeftLowerArm", "RightLowerArm",
	"LeftHand", "RightHand",
]
const FALLBACK_ARM_BONES: Dictionary = {
	"LeftUpperArm": ["upperarm_l", "upper_arm_l", "arm_l"],
	"RightUpperArm": ["upperarm_r", "upper_arm_r", "arm_r"],
	"LeftLowerArm": ["lowerarm_l", "forearm_l", "lower_arm_l"],
	"RightLowerArm": ["lowerarm_r", "forearm_r", "lower_arm_r"],
	"LeftHand": ["hand_l", "wrist_l"],
	"RightHand": ["hand_r", "wrist_r"],
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== diagnose_arm_rests ===")
	_dump_scene("MALE", MALE_PATH)
	_dump_scene("QUATERNIUS", QUAT_PATH)
	_dump_male_walk_pose()
	print("=== diagnose_arm_rests DONE ===")
	quit(0)


func _dump_scene(label: String, path: String) -> void:
	print("\n######## SCENE: %s (%s) ########" % [label, path])
	if not ResourceLoader.exists(path):
		print("MISSING: ", path)
		return
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		print("NOT_PACKED_SCENE: ", path)
		return
	var root: Node = packed.instantiate()
	get_root().add_child(root)
	var skels: Array[Skeleton3D] = []
	_collect_skeletons(root, skels)
	print("SKELETON_COUNT: ", skels.size())
	for skel in skels:
		_dump_skeleton(skel)
	root.queue_free()


func _dump_skeleton(skel: Skeleton3D) -> void:
	print("\n--- Skeleton path=", skel.get_path(), " bones=", skel.get_bone_count(), " ---")
	print("MATCHING BONE NAMES:")
	for i in range(skel.get_bone_count()):
		var n := skel.get_bone_name(i)
		var nl := n.to_lower()
		if (
			"UpperArm" in n or "LowerArm" in n or "Hand" in n or "Shoulder" in n
			or "upperarm" in nl or "hand" in nl or "clavicle" in nl
			or "shoulder" in nl or "lowerarm" in nl or "forearm" in nl
		):
			print("  [%d] %s  parent=%s" % [
				i, n,
				skel.get_bone_name(skel.get_bone_parent(i)) if skel.get_bone_parent(i) >= 0 else "<none>"
			])

	print("ARM REST DETAIL:")
	for profile_name in PROFILE_ARM_BONES:
		var bi := _resolve_bone(skel, profile_name)
		if bi < 0:
			print("  %s: MISSING (tried fallbacks)" % profile_name)
			continue
		var actual := skel.get_bone_name(bi)
		var rest := skel.get_bone_rest(bi)
		var euler_deg: Vector3 = rest.basis.get_euler() * 180.0 / PI
		var tip_global: Vector3 = _bone_tip_global_rest(skel, bi)
		var bone_global := skel.get_bone_global_rest(bi)
		print(
			"  %s (as %s): rest.origin=%s rest.euler_deg=%s global_rest.origin=%s tip_global_rest=%s"
			% [profile_name, actual, rest.origin, euler_deg, bone_global.origin, tip_global]
		)


func _resolve_bone(skel: Skeleton3D, profile_name: String) -> int:
	var i := skel.find_bone(profile_name)
	if i >= 0:
		return i
	if not FALLBACK_ARM_BONES.has(profile_name):
		return -1
	var fallbacks: Array = FALLBACK_ARM_BONES[profile_name]
	for fb in fallbacks:
		i = skel.find_bone(String(fb))
		if i >= 0:
			return i
	return -1


func _bone_tip_global_rest(skel: Skeleton3D, bone_i: int) -> Vector3:
	for ci in range(skel.get_bone_count()):
		if skel.get_bone_parent(ci) == bone_i:
			return skel.get_bone_global_rest(ci).origin
	return skel.get_bone_global_rest(bone_i).origin


func _dump_male_walk_pose() -> void:
	print("\n######## MALE + QUATERNIUS Walk @ t=0.3 ########")
	if not ResourceLoader.exists(MALE_PATH) or not ResourceLoader.exists(QUAT_PATH):
		print("MISSING assets for walk pose dump")
		return

	var male_packed: PackedScene = load(MALE_PATH) as PackedScene
	var body: Node3D = male_packed.instantiate() as Node3D
	body.name = "Body"
	body.rotation.y = PI
	get_root().add_child(body)

	var skel := _find_skeleton(body)
	if skel == null:
		print("NO_SKELETON on male body")
		return

	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	body.add_child(anim_player)

	var lib_root: Node = (load(QUAT_PATH) as PackedScene).instantiate()
	var src_player := _find_animation_player(lib_root)
	if src_player == null:
		print("NO AnimationPlayer in Quaternius")
		lib_root.free()
		return

	var library := AnimationLibrary.new()
	for anim_name in [String(ANIM_IDLE), String(ANIM_WALK)]:
		if not src_player.has_animation(anim_name):
			print("MISSING anim: ", anim_name)
			continue
		var src: Animation = src_player.get_animation(anim_name)
		var copy: Animation = src.duplicate(true) as Animation
		_prepare_locomotion_clip(copy)
		library.add_animation(anim_name, copy)
	anim_player.add_animation_library(String(LIB_NAME), library)
	lib_root.free()

	var walk_path := "%s/%s" % [LIB_NAME, ANIM_WALK]
	if not anim_player.has_animation(walk_path):
		print("FAIL: no ", walk_path)
		return

	anim_player.play(walk_path)
	anim_player.seek(0.3, true)
	anim_player.advance(0.0)
	skel.force_update_all_bone_transforms()

	var hips_i := _find_first_bone(skel, ["Hips", "hips", "pelvis", "Root"])
	var chest_i := _find_first_bone(skel, ["UpperChest", "Chest", "chest", "spine_02", "spine_01"])
	var lhand_i := _resolve_bone(skel, "LeftHand")
	var rhand_i := _resolve_bone(skel, "RightHand")

	print("Walk playing=", anim_player.current_animation, " t=", anim_player.current_animation_position)
	print(
		"bones: Hips=%s Chest/UpperChest=%s LeftHand=%s RightHand=%s"
		% [
			skel.get_bone_name(hips_i) if hips_i >= 0 else "MISSING",
			skel.get_bone_name(chest_i) if chest_i >= 0 else "MISSING",
			skel.get_bone_name(lhand_i) if lhand_i >= 0 else "MISSING",
			skel.get_bone_name(rhand_i) if rhand_i >= 0 else "MISSING",
		]
	)

	if hips_i < 0:
		print("NO HIPS - cannot compute relative positions")
		return

	var hips_g := skel.get_bone_global_pose(hips_i)
	_print_rel("Hips", hips_g, hips_g)
	if chest_i >= 0:
		_print_rel(skel.get_bone_name(chest_i), skel.get_bone_global_pose(chest_i), hips_g)
	if lhand_i >= 0:
		_print_rel(skel.get_bone_name(lhand_i), skel.get_bone_global_pose(lhand_i), hips_g)
	if rhand_i >= 0:
		_print_rel(skel.get_bone_name(rhand_i), skel.get_bone_global_pose(rhand_i), hips_g)

	if lhand_i >= 0 and rhand_i >= 0:
		var l_rel := hips_g.affine_inverse() * skel.get_bone_global_pose(lhand_i).origin
		var r_rel := hips_g.affine_inverse() * skel.get_bone_global_pose(rhand_i).origin
		print("SIDE_CHECK hips-local: LeftHand.x=%.4f RightHand.x=%.4f (expect Left +X / Right -X or vice versa)" % [l_rel.x, r_rel.x])
		if chest_i >= 0:
			var c_rel := hips_g.affine_inverse() * skel.get_bone_global_pose(chest_i).origin
			print("TORSO_CHECK hips-local Chest=%s Hands z: L=%.4f R=%.4f Chest.z=%.4f" % [c_rel, l_rel.z, r_rel.z, c_rel.z])


func _print_rel(label: String, bone_g: Transform3D, hips_g: Transform3D) -> void:
	var rel := hips_g.affine_inverse() * bone_g.origin
	print(
		"  %s global=%s  rel_to_Hips=%s"
		% [label, bone_g.origin, rel]
	)


func _prepare_locomotion_clip(anim: Animation) -> void:
	anim.loop_mode = Animation.LOOP_LINEAR
	for i in range(anim.get_track_count() - 1, -1, -1):
		var path := str(anim.track_get_path(i))
		var typ := anim.track_get_type(i)
		if typ == Animation.TYPE_POSITION_3D and path.ends_with(":Root"):
			anim.remove_track(i)


func _find_first_bone(skel: Skeleton3D, names: Array) -> int:
	for n in names:
		var i := skel.find_bone(String(n))
		if i >= 0:
			return i
	return -1


func _collect_skeletons(node: Node, out: Array[Skeleton3D]) -> void:
	if node is Skeleton3D:
		out.append(node as Skeleton3D)
	for child in node.get_children():
		_collect_skeletons(child, out)


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null