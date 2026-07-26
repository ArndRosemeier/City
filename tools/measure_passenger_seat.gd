## Headless: measure the seated (Driving) pose of a ped outfit so vehicle cabins can be
## sized from the actual rig instead of guesses. Prints bone-space extents relative to
## the passenger root, at the scale VehicleVisual uses.
extends SceneTree

const PedOutfitScript := preload("res://scripts/humans/ped_outfit.gd")
const QuaterniusLocomotionScript := preload("res://scripts/city/quaternius_locomotion.gd")
## Bone joints are skeleton pivots; the skull surface sits above the head joint.
const SKULL_MARGIN := 0.13
const PASSENGER_SCALE := 0.92


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var worst_head := 0.0
	var worst_id := ""
	for female in [false, true]:
		for i in range(4):
			var outfit: PedOutfit = PedOutfitScript.random(rng, female)
			if outfit == null or outfit.scene_path == "":
				push_error("FAIL outfit without scene_path")
				quit(1)
				return
			var stats := await _measure(outfit.scene_path)
			if stats.is_empty():
				quit(1)
				return
			var head: float = stats["head_top"]
			print(
				(
					"%-46s head_top=%.3f hip=%.3f knee_z=%.3f "
					+ "shoulder_w=%.3f bones_y=[%.3f..%.3f] bones_z=[%.3f..%.3f]"
				)
				% [
					outfit.scene_path.get_file(),
					head,
					stats["hip_y"],
					stats["knee_z"],
					stats["shoulder_w"],
					stats["min_y"],
					stats["max_y"],
					stats["min_z"],
					stats["max_z"],
				]
			)
			if head > worst_head:
				worst_head = head
				worst_id = outfit.scene_path.get_file()

	print("")
	print("tallest seated passenger: %.3f m (%s) at scale %.2f" % [worst_head, worst_id, PASSENGER_SCALE])
	print("cabin roof underside must clear: %.3f m above the seat floor" % worst_head)
	quit(0)


func _measure(scene_path: String) -> Dictionary:
	var packed := load(scene_path)
	if not (packed is PackedScene):
		push_error("FAIL %s is not a PackedScene" % scene_path)
		return {}
	var body := (packed as PackedScene).instantiate() as Node3D
	if body == null:
		push_error("FAIL instantiate failed: %s" % scene_path)
		return {}
	var root := Node3D.new()
	root.add_child(body)
	body.scale = Vector3(PASSENGER_SCALE, PASSENGER_SCALE, PASSENGER_SCALE)
	get_root().add_child(root)

	var anim := AnimationPlayer.new()
	body.add_child(anim)
	QuaterniusLocomotionScript.attach_passenger(anim)
	QuaterniusLocomotionScript.play_driving(anim)
	if anim.current_animation == "":
		push_error("FAIL no driving animation on %s" % scene_path)
		root.queue_free()
		return {}
	## Land mid-clip so the sampled pose is the settled sit, not the blend-in frame.
	anim.advance(0.6)
	await process_frame

	var skel := _find_skeleton(body)
	if skel == null:
		push_error("FAIL no Skeleton3D in %s" % scene_path)
		root.queue_free()
		return {}

	var min_y := INF
	var max_y := -INF
	var min_z := INF
	var max_z := -INF
	var head_y := -INF
	var hip_y := 0.0
	var knee_z := 0.0
	var shoulder_x := 0.0
	for b in range(skel.get_bone_count()):
		var p: Vector3 = root.global_transform.affine_inverse() * (
			skel.global_transform * skel.get_bone_global_pose(b).origin
		)
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
		var bname := skel.get_bone_name(b).to_lower()
		if bname.contains("head"):
			head_y = maxf(head_y, p.y)
		elif bname.contains("hip") or bname.contains("pelvis"):
			hip_y = p.y
		elif bname.contains("shin") or bname.contains("knee"):
			knee_z = minf(knee_z, p.z)
		elif bname.contains("shoulder") or bname.contains("upperarm") or bname.contains("arm"):
			shoulder_x = maxf(shoulder_x, absf(p.x))
	root.queue_free()
	await process_frame
	if head_y == -INF:
		push_error("FAIL no head bone in %s" % scene_path)
		return {}
	return {
		"head_top": head_y + SKULL_MARGIN * PASSENGER_SCALE,
		"hip_y": hip_y,
		"knee_z": knee_z,
		"shoulder_w": shoulder_x * 2.0,
		"min_y": min_y,
		"max_y": max_y,
		"min_z": min_z,
		"max_z": max_z,
	}


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s != null:
			return s
	return null
