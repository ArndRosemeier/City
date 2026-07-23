extends SceneTree

const MALE := "res://assets/humans/male_base.gltf"
const QUAT := "res://assets/humans/animations/quaternius/AnimationLibrary_Godot_Standard.gltf"
const ANIM_WALK := &"Walk"
const LIB := &"quat"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_print_lua("MALE", MALE)
	_print_lua("QUATERNIUS", QUAT)
	_walk_hands()
	quit(0)

func _print_lua(label: String, path: String) -> void:
	var packed := load(path) as PackedScene
	var root := packed.instantiate()
	get_root().add_child(root)
	var skel := _find_skel(root)
	var bi := skel.find_bone("LeftUpperArm")
	var rest := skel.get_bone_rest(bi)
	var euler := rest.basis.get_euler() * 180.0 / PI
	var tip := _tip(skel, bi)
	var sh_i := skel.find_bone("LeftShoulder")
	var sh_y := skel.get_bone_global_rest(sh_i).origin.y if sh_i >= 0 else tip.y
	# For T-pose check use shoulder global y vs arm tip; also compare tip y to upper arm global origin y
	var arm_y := skel.get_bone_global_rest(bi).origin.y
	print("%s LeftUpperArm rest.origin=%s rest.euler_deg=%s tip=%s" % [label, rest.origin, euler, tip])
	if label == "MALE":
		var dy := absf(tip.y - arm_y)
		var tpose := dy <= 0.05
		print("T-POSE CHECK: tip.y=%.6f shoulder/arm_origin.y=%.6f |dy|=%.6f -> %s" % [tip.y, arm_y, dy, "PASS" if tpose else "FAIL"])
	root.queue_free()

func _tip(skel: Skeleton3D, bone_i: int) -> Vector3:
	for ci in range(skel.get_bone_count()):
		if skel.get_bone_parent(ci) == bone_i:
			return skel.get_bone_global_rest(ci).origin
	return skel.get_bone_global_rest(bone_i).origin

func _walk_hands() -> void:
	var body := (load(MALE) as PackedScene).instantiate() as Node3D
	body.rotation.y = PI
	get_root().add_child(body)
	var skel := _find_skel(body)
	var ap := AnimationPlayer.new()
	body.add_child(ap)
	var lib_root := (load(QUAT) as PackedScene).instantiate()
	var src := _find_ap(lib_root)
	var library := AnimationLibrary.new()
	var src_anim: Animation = src.get_animation(String(ANIM_WALK)).duplicate(true) as Animation
	src_anim.loop_mode = Animation.LOOP_LINEAR
	for i in range(src_anim.get_track_count() - 1, -1, -1):
		var p := str(src_anim.track_get_path(i))
		if src_anim.track_get_type(i) == Animation.TYPE_POSITION_3D and p.ends_with(":Root"):
			src_anim.remove_track(i)
	library.add_animation(String(ANIM_WALK), src_anim)
	ap.add_animation_library(String(LIB), library)
	lib_root.free()
	ap.play("%s/%s" % [LIB, ANIM_WALK])
	ap.seek(0.3, true)
	ap.advance(0.0)
	skel.force_update_all_bone_transforms()
	var hips_i := skel.find_bone("Hips")
	var lh := skel.find_bone("LeftHand")
	var rh := skel.find_bone("RightHand")
	var hips_g := skel.get_bone_global_pose(hips_i)
	var lx := (hips_g.affine_inverse() * skel.get_bone_global_pose(lh).origin).x
	var rx := (hips_g.affine_inverse() * skel.get_bone_global_pose(rh).origin).x
	var arms_out := absf(lx) > 0.15 and absf(rx) > 0.15
	print("WALK hands hips-local x: L=%.4f R=%.4f |L|=%.4f |R|=%.4f -> %s" % [
		lx, rx, absf(lx), absf(rx), "PASS arms out" if arms_out else "FAIL hands crossed/midline"
	])

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var f := _find_skel(c)
		if f:
			return f
	return null

func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var f := _find_ap(c)
		if f:
			return f
	return null
