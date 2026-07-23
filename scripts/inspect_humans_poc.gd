## Close-up inspection POC: male + female, stationary, keyboard limb posing.
extends Node3D

const MALE_PATH := "res://assets/humans/male_base.gltf"
const FEMALE_PATH := "res://assets/humans/female_base.gltf"

## Bone names on MPFB game_engine rig
const LIMBS: Array[Dictionary] = [
	{"id": "1", "label": "L thigh", "bone": "thigh_l"},
	{"id": "2", "label": "L knee/calf", "bone": "calf_l"},
	{"id": "3", "label": "R thigh", "bone": "thigh_r"},
	{"id": "4", "label": "R knee/calf", "bone": "calf_r"},
	{"id": "5", "label": "L upper arm", "bone": "upperarm_l"},
	{"id": "6", "label": "L forearm", "bone": "lowerarm_l"},
	{"id": "7", "label": "R upper arm", "bone": "upperarm_r"},
	{"id": "8", "label": "R forearm", "bone": "lowerarm_r"},
	{"id": "9", "label": "Head", "bone": "head"},
	{"id": "0", "label": "Spine", "bone": "spine_02"},
]

var _male: Node3D
var _female: Node3D
var _male_skel: Skeleton3D
var _female_skel: Skeleton3D
var _active_is_male: bool = true
var _limb_index: int = 1  # calf by default so knees are obvious
var _pose_euler: Dictionary = {}  # skeleton_id -> bone_name -> Vector3 radians
var _dirty_bones: Dictionary = {}  # skeleton_id -> Dictionary bone_name -> true
## glTF import stores bind orientation in pose (not identity). Deltas must multiply onto this.
var _bind_pose_rot: Dictionary = {}  # skeleton_id -> bone_name -> Quaternion
var _body_yaw: float = PI  # MH/Blender often needs 180° so feet/face point at camera
var _camera: Camera3D
var _hud: Label
var _cam_dist: float = 2.4
var _cam_height: float = 1.2
var _cam_yaw: float = 0.0


func _ready() -> void:
	_build_world()
	_male = _spawn_human(MALE_PATH, Vector3(-0.7, 0.0, 0.0), "Male")
	_female = _spawn_human(FEMALE_PATH, Vector3(0.7, 0.0, 0.0), "Female")
	_male_skel = _find_skeleton(_male)
	_female_skel = _find_skeleton(_female)
	_cache_bind_pose_rotations(_male_skel)
	_cache_bind_pose_rotations(_female_skel)
	_apply_body_yaw()
	_build_hud()
	_update_camera()
	_update_hud()
	if _male_skel == null or _female_skel == null:
		push_error("Inspection POC: skeleton missing — check human glTF imports")


func _build_world() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, 40.0, 0.0)
	light.light_energy = 1.35
	light.shadow_enabled = true
	add_child(light)

	var fill := OmniLight3D.new()
	fill.position = Vector3(0.0, 2.0, 2.5)
	fill.light_energy = 0.55
	fill.omni_range = 8.0
	add_child(fill)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.42, 0.48, 0.55)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	add_child(env)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.2, 0.22, 0.25)
	ground.material_override = gmat
	add_child(ground)

	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 40.0
	add_child(_camera)


func _spawn_human(path: String, pos: Vector3, label_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = label_name
	root.position = pos
	add_child(root)
	if not ResourceLoader.exists(path):
		push_error("Missing %s" % path)
		return root
	var packed := load(path) as PackedScene
	var body: Node = packed.instantiate()
	body.name = "Body"
	root.add_child(body)
	# Smooth shading help if importer left flat look
	var mesh := _find_mesh(body)
	if mesh != null and mesh.mesh != null:
		for s in range(mesh.mesh.get_surface_count()):
			var mat := mesh.get_active_material(s)
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				sm.roughness = 0.7
	return root


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 16.0
	panel.offset_top = 16.0
	panel.offset_right = 560.0
	panel.offset_bottom = 320.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.09, 0.88)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	_hud = Label.new()
	_hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud.add_theme_font_size_override("font_size", 14)
	_hud.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
	panel.add_child(_hud)


func _process(delta: float) -> void:
	_handle_held_keys(delta)
	_update_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				get_tree().quit()
			KEY_TAB:
				_active_is_male = not _active_is_male
				_update_hud()
			KEY_F:
				_body_yaw += PI
				_apply_body_yaw()
				_update_hud()
			KEY_R:
				_reset_poses()
				_update_hud()
			KEY_COMMA:
				_limb_index = (_limb_index - 1 + LIMBS.size()) % LIMBS.size()
				_update_hud()
			KEY_PERIOD:
				_limb_index = (_limb_index + 1) % LIMBS.size()
				_update_hud()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0:
				_select_limb_by_key(event.keycode)
				_update_hud()


func _select_limb_by_key(keycode: Key) -> void:
	var id := ""
	match keycode:
		KEY_1: id = "1"
		KEY_2: id = "2"
		KEY_3: id = "3"
		KEY_4: id = "4"
		KEY_5: id = "5"
		KEY_6: id = "6"
		KEY_7: id = "7"
		KEY_8: id = "8"
		KEY_9: id = "9"
		KEY_0: id = "0"
	for i in range(LIMBS.size()):
		if String(LIMBS[i]["id"]) == id:
			_limb_index = i
			return


func _handle_held_keys(delta: float) -> void:
	var step := 1.2 * delta
	var moved := false
	var e := _get_active_euler()
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_I):
		e.x -= step
		moved = true
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_K):
		e.x += step
		moved = true
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_J):
		e.y -= step
		moved = true
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_L):
		e.y += step
		moved = true
	if Input.is_key_pressed(KEY_U):
		e.z -= step
		moved = true
	if Input.is_key_pressed(KEY_O):
		e.z += step
		moved = true
	# Camera orbit / zoom
	if Input.is_key_pressed(KEY_A):
		_cam_yaw -= delta * 1.1
	if Input.is_key_pressed(KEY_D):
		_cam_yaw += delta * 1.1
	if Input.is_key_pressed(KEY_W):
		_cam_dist = maxf(0.8, _cam_dist - delta * 1.5)
	if Input.is_key_pressed(KEY_S):
		_cam_dist = minf(6.0, _cam_dist + delta * 1.5)
	if Input.is_key_pressed(KEY_Q):
		_cam_height = maxf(0.2, _cam_height - delta * 1.2)
	if Input.is_key_pressed(KEY_E):
		_cam_height = minf(2.4, _cam_height + delta * 1.2)
	if moved:
		_set_active_euler(e)
		_mark_active_dirty()
		_apply_active_pose()
		_update_hud()


func _mark_active_dirty() -> void:
	var skel := _active_skeleton()
	var bone := String(LIMBS[_limb_index]["bone"])
	var key := _skel_key(skel)
	if not _dirty_bones.has(key):
		_dirty_bones[key] = {}
	_dirty_bones[key][bone] = true


func _get_active_euler() -> Vector3:
	var skel := _active_skeleton()
	var bone := String(LIMBS[_limb_index]["bone"])
	var key := _skel_key(skel)
	if not _pose_euler.has(key):
		_pose_euler[key] = {}
	var map: Dictionary = _pose_euler[key]
	if not map.has(bone):
		map[bone] = Vector3.ZERO
	return map[bone]


func _set_active_euler(e: Vector3) -> void:
	var skel := _active_skeleton()
	var bone := String(LIMBS[_limb_index]["bone"])
	var key := _skel_key(skel)
	if not _pose_euler.has(key):
		_pose_euler[key] = {}
	_pose_euler[key][bone] = e


func _cache_bind_pose_rotations(skel: Skeleton3D) -> void:
	if skel == null:
		return
	var key := _skel_key(skel)
	var map: Dictionary = {}
	for bone_i in range(skel.get_bone_count()):
		map[skel.get_bone_name(bone_i)] = skel.get_bone_pose_rotation(bone_i)
	_bind_pose_rot[key] = map


func _bind_rotation(skel: Skeleton3D, bone_name: String) -> Quaternion:
	var key := _skel_key(skel)
	if not _bind_pose_rot.has(key):
		_cache_bind_pose_rotations(skel)
	var map: Dictionary = _bind_pose_rot[key]
	if not map.has(bone_name):
		push_error("No bind pose rotation cached for bone '%s'" % bone_name)
	return map[bone_name]


func _apply_active_pose() -> void:
	var skel := _active_skeleton()
	if skel == null:
		return
	var bone_name := String(LIMBS[_limb_index]["bone"])
	var idx := skel.find_bone(bone_name)
	if idx < 0:
		push_warning("Bone not found: %s" % bone_name)
		return
	var e: Vector3 = _get_active_euler()
	# Delta in bone-local axes; must multiply onto bind pose (glTF leaves bind in pose).
	var delta := (
		Quaternion(Vector3.RIGHT, e.x)
		* Quaternion(Vector3.UP, e.y)
		* Quaternion(Vector3.FORWARD, e.z)
	)
	skel.set_bone_pose_rotation(idx, _bind_rotation(skel, bone_name) * delta)


func _reset_poses() -> void:
	for skel in [_male_skel, _female_skel]:
		if skel == null:
			continue
		skel.reset_bone_poses()
		_cache_bind_pose_rotations(skel)
	_pose_euler.clear()
	_dirty_bones.clear()


func _apply_body_yaw() -> void:
	if _male:
		_male.rotation.y = _body_yaw
	if _female:
		_female.rotation.y = _body_yaw


func _update_camera() -> void:
	var target := Vector3(0.0, 1.0, 0.0)
	var offset := Vector3(sin(_cam_yaw) * _cam_dist, _cam_height, cos(_cam_yaw) * _cam_dist)
	_camera.position = target + offset
	_camera.look_at(target)


func _update_hud() -> void:
	var who := "MALE" if _active_is_male else "FEMALE"
	var limb: Dictionary = LIMBS[_limb_index]
	var skel := _active_skeleton()
	var bone := String(limb["bone"])
	var idx := skel.find_bone(bone) if skel else -1
	var e := _get_active_euler()
	_hud.text = (
		"Human inspection POC (2 people, no auto-walk)\n\n"
		+ "Active: %s\n" % who
		+ "Limb: [%s] %s   bone '%s'  idx=%d\n" % [limb["id"], limb["label"], bone, idx]
		+ "Pose euler deg: x=%.1f  y=%.1f  z=%.1f\n" % [rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)]
		+ "Body yaw: %.0f deg   (press F to flip facing)\n\n" % rad_to_deg(fposmod(_body_yaw, TAU))
		+ "Tab = switch male/female\n"
		+ "1-0 or , . = SELECT limb only (does not bend yet)\n"
		+ "I/K or Up/Down = pitch / bend (bone-local; try both dirs)\n"
		+ "J/L or Left/Right = yaw\n"
		+ "U/O = roll\n"
		+ "WASD = camera zoom/orbit   Q/E = camera height\n"
		+ "R = reset poses   Esc = quit"
	)


func _active_skeleton() -> Skeleton3D:
	return _male_skel if _active_is_male else _female_skel


func _skel_key(skel: Skeleton3D) -> String:
	return str(skel.get_instance_id()) if skel else "none"


func _find_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root
	for c in root.get_children():
		var f := _find_mesh(c)
		if f:
			return f
	return null


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root
	for c in root.get_children():
		var f := _find_skeleton(c)
		if f:
			return f
	return null
