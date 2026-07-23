extends SceneTree

## Diagnose neutral_bone rest/pose after Keep Global Rest On Leftovers reimport.

const MALE := "res://assets/humans/male_base.gltf"
const QUAT := "res://assets/humans/animations/quaternius/AnimationLibrary_Godot_Standard.gltf"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== diagnose_neutral_bone ===")
	if not ResourceLoader.exists(MALE):
		push_error("missing %s" % MALE)
		quit(1)
		return

	var packed: PackedScene = load(MALE) as PackedScene
	var root: Node = packed.instantiate()
	get_root().add_child(root)

	var skel := _find_skel(root)
	if skel == null:
		push_error("No Skeleton3D")
		quit(1)
		return

	var bone_i := _find_neutral(skel)
	if bone_i < 0:
		print("FAIL: no bone named neutral_bone / containing 'neutral'")
		_list_bones_hint(skel)
		quit(1)
		return

	var bname := skel.get_bone_name(bone_i)
	var parent_i := skel.get_bone_parent(bone_i)
	var parent_name := "<none>" if parent_i < 0 else skel.get_bone_name(parent_i)
	var rest := skel.get_bone_rest(bone_i)
	var global_rest := skel.get_bone_global_rest(bone_i)

	print("bone=", bname, " index=", bone_i, " parent=", parent_name)
	print("rest.origin=", rest.origin)
	print("rest.basis=", rest.basis)
	print("global_rest.origin=", global_rest.origin)
	print("global_rest.basis=", global_rest.basis)

	for ref_name in ["Hips", "Spine", "Chest", "UpperChest"]:
		var ri := skel.find_bone(ref_name)
		if ri >= 0:
			var gro := skel.get_bone_global_rest(ri).origin
			print("ref ", ref_name, " global_rest.origin=", gro, " dist_to_neutral=", gro.distance_to(global_rest.origin))

	var rest_ok := _is_chest_like(global_rest.origin)
	print("global_rest chest-like? ", rest_ok, " (|xz|=", _xz_len(global_rest.origin), " y=", global_rest.origin.y, ")")

	_play_idle(root, skel)
	await process_frame
	await process_frame
	skel.force_update_all_bone_transforms()

	var global_pose := skel.get_bone_global_pose(bone_i)
	print("after Idle: global_pose.origin=", global_pose.origin)
	print("after Idle: global_pose.basis=", global_pose.basis)

	var pose_ok := _is_chest_like(global_pose.origin)
	print("global_pose chest-like? ", pose_ok, " (|xz|=", _xz_len(global_pose.origin), " y=", global_pose.origin.y, ")")

	var near_world_origin := global_rest.origin.length() < 0.15 or absf(global_rest.origin.y) < 0.05
	var pose_near_origin := global_pose.origin.length() < 0.15 or absf(global_pose.origin.y) < 0.05

	var passed := rest_ok and pose_ok and not near_world_origin and not pose_near_origin
	if passed:
		print("PASS: neutral_bone global rest/pose near nipple/chest height (y>1.0, |xz| small)")
		quit(0)
	else:
		print("FAIL: neutral_bone near world origin or not at chest height")
		print("  rest_ok=", rest_ok, " pose_ok=", pose_ok, " near_origin_rest=", near_world_origin, " near_origin_pose=", pose_near_origin)
		quit(1)


func _is_chest_like(o: Vector3) -> bool:
	return o.y > 1.0 and _xz_len(o) < 0.45


func _xz_len(o: Vector3) -> float:
	return Vector2(o.x, o.z).length()


func _find_neutral(skel: Skeleton3D) -> int:
	var exact := skel.find_bone("neutral_bone")
	if exact >= 0:
		return exact
	for i in range(skel.get_bone_count()):
		var n := skel.get_bone_name(i).to_lower()
		if n.contains("neutral"):
			return i
	return -1


func _list_bones_hint(skel: Skeleton3D) -> void:
	print("bones containing 'neutral'/'nip'/'chest'/'spine':")
	for i in range(skel.get_bone_count()):
		var n := skel.get_bone_name(i).to_lower()
		if n.contains("neutral") or n.contains("nip") or n.contains("chest") or n.contains("spine"):
			print("  ", i, " ", skel.get_bone_name(i))


func _play_idle(body: Node, skel: Skeleton3D) -> void:
	if not ResourceLoader.exists(QUAT):
		push_warning("Quaternius missing; skipping Idle pose")
		skel.reset_bone_poses()
		skel.force_update_all_bone_transforms()
		return

	var lib_packed := load(QUAT) as PackedScene
	var lib_root: Node = lib_packed.instantiate()
	var src_player := _find_anim(lib_root)
	if src_player == null or not src_player.has_animation("Idle"):
		push_warning("Idle not found; using rest poses")
		lib_root.free()
		skel.reset_bone_poses()
		skel.force_update_all_bone_transforms()
		return

	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	body.add_child(player)
	var library := AnimationLibrary.new()
	var src: Animation = src_player.get_animation("Idle")
	var copy: Animation = src.duplicate(true) as Animation
	copy.loop_mode = Animation.LOOP_LINEAR
	library.add_animation("Idle", copy)
	player.add_animation_library("quat", library)
	lib_root.free()

	player.play("quat/Idle")
	player.advance(0.1)
	skel.force_update_all_bone_transforms()
	print("played quat/Idle; current=", player.current_animation, " pos=", player.current_animation_position)


func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var f := _find_skel(c)
		if f != null:
			return f
	return null


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var f := _find_anim(c)
		if f != null:
			return f
	return null