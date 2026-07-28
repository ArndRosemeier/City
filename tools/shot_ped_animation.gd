## Plays library clips on outfit bodies, screenshots them, and asserts the skeleton actually
## moves.
##
## The second part is the point: an outfit GLB whose .import lost its retarget bone map imports
## without any error and simply stands in its rest pose forever, so "it still looks fine in a
## still frame" is not evidence. This measures bone travel over the clip and fails when a body
## is frozen.
##
## Run: powershell -File tools\run_test.ps1 shot_ped_animation -Rendered
##      ... -GodotArgs "--outfit=male_work_01","--clips=Walk,Sword_Attack"
extends Node

const OUT_DIR := "res://tools/pedshots_anim"
const DEFAULT_CLIPS: Array[String] = ["Walk", "Sprint", "Sword_Attack"]
## Phases of the clip to capture, as fractions of its length. Override with --phases=0.1,0.5.
const DEFAULT_PHASES: Array[float] = [0.35, 0.7]
## A driven skeleton moves whole limbs; anything under this is rest-pose jitter.
const MIN_BONE_TRAVEL_M := 0.02

var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_build_stage()
	PedOutfitCatalog.reload()
	var outfits := _selected_outfits()
	if outfits.is_empty():
		_fail("no outfit selected — catalog empty or --outfit id unknown")
		_finish()
		return
	var clips := _selected_clips()
	var library := QuaterniusLocomotion.build_library(clips)
	if library == null:
		_fail("could not build animation library")
		_finish()
		return
	for clip in clips:
		if not library.has_animation(clip):
			_fail("library has no clip '%s'" % clip)
	for outfit in outfits:
		for clip in clips:
			if library.has_animation(clip):
				await _shoot_clip(outfit, clip, library)
	_finish()


func _selected_outfits() -> Array[PedOutfit]:
	var wanted := _arg_value("--outfit")
	var all := PedOutfitCatalog.all_outfits()
	if wanted == "":
		return all
	var out: Array[PedOutfit] = []
	for outfit in all:
		if outfit.variant_id == wanted:
			out.append(outfit)
	return out


func _selected_phases() -> Array[float]:
	var raw := _arg_value("--phases")
	if raw == "":
		return DEFAULT_PHASES
	var out: Array[float] = []
	for part in raw.split(","):
		var trimmed := part.strip_edges()
		if trimmed != "":
			out.append(float(trimmed))
	if out.size() < 2:
		_fail("--phases needs at least two phases to measure bone travel")
	return out


func _selected_clips() -> Array[String]:
	var raw := _arg_value("--clips")
	if raw == "":
		return DEFAULT_CLIPS
	var out: Array[String] = []
	for part in raw.split(","):
		var trimmed := part.strip_edges()
		if trimmed != "":
			out.append(trimmed)
	return out


func _arg_value(flag: String) -> String:
	for arg in OS.get_cmdline_args():
		if arg.begins_with(flag + "="):
			return arg.substr(flag.length() + 1)
	return ""


func _shoot_clip(outfit: PedOutfit, clip: String, library: AnimationLibrary) -> void:
	var packed: Resource = load(outfit.scene_path)
	if not (packed is PackedScene):
		_fail("%s: %s is not a PackedScene" % [outfit.variant_id, outfit.scene_path])
		return
	var body: Node3D = (packed as PackedScene).instantiate() as Node3D
	body.name = "Body"
	## Bodies face +Z out of glTF; turn them to face the camera at -Z as the game does.
	body.rotation.y = PI
	add_child(body)
	PedOutfitApplier.apply_to_body_root(body, outfit, outfit.female)
	var skeleton := _find_skeleton(body)
	if skeleton == null:
		_fail("%s: no Skeleton3D" % outfit.variant_id)
		body.queue_free()
		return
	var anim := AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	body.add_child(anim)
	anim.add_animation_library("quat", library)
	var path := "quat/%s" % clip
	anim.play(path)
	var length := library.get_animation(clip).length

	var samples: Array[PackedVector3Array] = []
	for phase in _selected_phases():
		anim.seek(length * phase, true)
		await get_tree().process_frame
		await get_tree().process_frame
		samples.append(_bone_origins(skeleton))
		await _shoot(
			Vector3(0.9, 1.1, -2.6),
			Vector3(0.0, 0.95, 0.0),
			"%s/%s_%s_p%02d.png" % [OUT_DIR, outfit.variant_id, clip, int(phase * 100.0)]
		)
		## The right hand is where an mhclo weapon would drift or shear away from the grip, so
		## it gets a frame at every phase, not just one.
		var hand := _hand_position(skeleton)
		if hand == Vector3.INF:
			_fail("%s: no right-hand bone — cannot inspect a weapon grip" % outfit.variant_id)
		else:
			## Telephoto from well back, so framing is the same wherever the arm happens to be.
			await _shoot(
				hand + Vector3(1.5, 0.95, -2.0),
				hand,
				"%s/%s_%s_hand_p%02d.png" % [OUT_DIR, outfit.variant_id, clip, int(phase * 100.0)],
				18.0
			)

	## Shoulders and hips are where interpolated mhclo weights break first.
	anim.seek(length * 0.5, true)
	await get_tree().process_frame
	await _shoot(
		Vector3(0.55, 1.42, -1.15),
		Vector3(0.0, 1.32, 0.0),
		"%s/%s_%s_shoulders.png" % [OUT_DIR, outfit.variant_id, clip]
	)
	await _shoot(
		Vector3(0.5, 0.98, -1.25),
		Vector3(0.0, 0.9, 0.0),
		"%s/%s_%s_hips.png" % [OUT_DIR, outfit.variant_id, clip]
	)

	var travel := _max_travel(samples[0], samples[samples.size() - 1])
	print(
		"%s / %s: bones=%d max_bone_travel=%.3f m"
		% [outfit.variant_id, clip, skeleton.get_bone_count(), travel]
	)
	if travel < MIN_BONE_TRAVEL_M:
		_fail(
			(
				"%s / %s: skeleton barely moved (%.4f m) — the clip is not driving the body, "
				+ "check retarget/bone_map in %s.import"
			)
			% [outfit.variant_id, clip, travel, outfit.scene_path.get_file()]
		)
	body.queue_free()
	await _settle(0.15)


func _bone_origins(skeleton: Skeleton3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in skeleton.get_bone_count():
		out.append(skeleton.get_bone_global_pose(i).origin)
	return out


func _max_travel(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var worst := 0.0
	for i in mini(a.size(), b.size()):
		worst = maxf(worst, a[i].distance_to(b[i]))
	return worst


## Right hand in world space, for the weapon-grip close-up. Vector3.INF when the rig has no
## recognisable hand bone.
func _hand_position(skeleton: Skeleton3D) -> Vector3:
	for candidate: String in ["hand.R", "RightHand", "hand_r", "Right_Hand"]:
		var index := skeleton.find_bone(candidate)
		if index >= 0:
			return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin
	return Vector3.INF


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.55, 0.72)
	sky_mat.sky_horizon_color = Color(0.72, 0.76, 0.80)
	sky_mat.ground_bottom_color = Color(0.24, 0.24, 0.26)
	sky_mat.ground_horizon_color = Color(0.45, 0.45, 0.47)
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-38.0, 25.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

	var pad := MeshInstance3D.new()
	pad.name = "Pad"
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	pad.mesh = plane
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.32, 0.33, 0.35)
	pad_mat.roughness = 0.9
	pad.material_override = pad_mat
	add_child(pad)


func _settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _shoot(eye: Vector3, target: Vector3, path: String, fov: float = 45.0) -> void:
	var cam := Camera3D.new()
	cam.position = eye
	cam.fov = fov
	cam.far = 500.0
	add_child(cam)
	cam.look_at(target, Vector3.UP)
	cam.make_current()
	await _settle(0.25)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		_fail("no viewport image for %s" % path)
	else:
		img.save_png(path)
	cam.queue_free()


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("FAIL ", msg)


func _finish() -> void:
	if _failures.is_empty():
		print("RESULT: OK")
		get_tree().quit(0)
		return
	print("RESULT: FAIL (%d)" % _failures.size())
	get_tree().quit(1)
