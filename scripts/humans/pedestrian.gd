## One pedestrian: skinned body, proportion morphs, locomotion, anatomy proxy slot.
class_name Pedestrian
extends CharacterBody3D

enum Sex { MALE, FEMALE }

const MALE_SCENE := "res://assets/humans/male_base.gltf"
const FEMALE_SCENE := "res://assets/humans/female_base.gltf"

@export var sex: Sex = Sex.MALE
@export var walk_speed: float = 1.35
@export var turn_speed: float = 2.2

var proportions: BodyProportions
var _mesh: MeshInstance3D
var _skeleton: Skeleton3D
var _bind_pose_rot: Dictionary = {}  # bone index -> Quaternion (glTF bind left in pose)
var _anatomy: AnatomyProxy
var _phase: float = 0.0
var _heading: float = 0.0
var _rng: RandomNumberGenerator


func setup(sex_value: Sex, props: BodyProportions, rng: RandomNumberGenerator) -> void:
	sex = sex_value
	proportions = props
	_rng = rng
	_heading = rng.randf_range(0.0, TAU)
	_phase = rng.randf_range(0.0, TAU)
	rotation.y = _heading
	_load_body()
	_ensure_anatomy_slot()
	if proportions != null and _mesh != null:
		proportions.apply_to_mesh(_mesh)


func _load_body() -> void:
	var candidates: Array[String] = []
	if sex == Sex.MALE:
		candidates = [
			"res://assets/humans/male_base.gltf",
			"res://assets/humans/male_base.glb",
		]
	else:
		candidates = [
			"res://assets/humans/female_base.gltf",
			"res://assets/humans/female_base.glb",
		]
	var path := ""
	for candidate in candidates:
		if ResourceLoader.exists(candidate):
			path = candidate
			break
	if path == "":
		push_error("Pedestrian: missing body asset for sex=%s" % sex)
		_create_fallback_body()
		return
	var packed := load(path)
	var instance: Node = null
	if packed is PackedScene:
		instance = packed.instantiate()
	else:
		push_error("Pedestrian: %s did not load as PackedScene" % path)
		_create_fallback_body()
		return
	instance.name = "Body"
	# MakeHuman/glTF faces +Z; CharacterBody3D forward is -Z.
	instance.rotation.y = PI
	add_child(instance)
	_mesh = _find_mesh(instance)
	_skeleton = _find_skeleton(instance)
	_cache_bind_pose_rotations()
	if _mesh == null:
		push_warning("Pedestrian: no MeshInstance3D in %s; using fallback" % path)
		instance.queue_free()
		_create_fallback_body()
		return
	print("Pedestrian loaded MH body: ", path, " mesh=", _mesh.name, " bones=", _skeleton.get_bone_count() if _skeleton else 0)


func _create_fallback_body() -> void:
	var body := Node3D.new()
	body.name = "Body"
	add_child(body)
	var skel := Skeleton3D.new()
	skel.name = "Skeleton"
	skel.add_bone("Root")
	skel.set_bone_rest(0, Transform3D.IDENTITY)
	skel.add_bone("Pelvis")
	skel.set_bone_parent(1, 0)
	skel.set_bone_rest(1, Transform3D(Basis.IDENTITY, Vector3(0, 0.95, 0)))
	body.add_child(skel)
	_skeleton = skel
	var mi := MeshInstance3D.new()
	mi.name = "BodyMesh"
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.18 if sex == Sex.FEMALE else 0.2
	capsule.height = 1.7 if sex == Sex.FEMALE else 1.8
	mi.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.68, 0.54) if sex == Sex.FEMALE else Color(0.78, 0.58, 0.44)
	mi.material_override = mat
	mi.position.y = capsule.height * 0.5
	body.add_child(mi)
	_mesh = mi


func _ensure_anatomy_slot() -> void:
	_anatomy = get_node_or_null("AnatomySlot") as AnatomyProxy
	if _anatomy == null:
		_anatomy = AnatomyProxy.new()
		_anatomy.name = "AnatomySlot"
		_anatomy.slot_kind = AnatomyProxy.SlotKind.ANATOMY
		_anatomy.slot_id = &"crotch"
		_anatomy.bone_name = &"pelvis"
		_anatomy.proxy_visible = false
		add_child(_anatomy)
	if _skeleton != null:
		_anatomy.setup(_skeleton)
	AnatomySlotContract.assert_ready(self)


func _physics_process(delta: float) -> void:
	_heading += _rng.randf_range(-1.0, 1.0) * 0.35 * delta
	rotation.y = lerp_angle(rotation.y, _heading, turn_speed * delta)
	var dir := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	velocity = dir * walk_speed
	move_and_slide()
	position.y = 0.0
	_phase += delta * walk_speed * 4.0
	_apply_walk_pose(delta)


func _cache_bind_pose_rotations() -> void:
	_bind_pose_rot.clear()
	if _skeleton == null:
		return
	for bone_i in range(_skeleton.get_bone_count()):
		_bind_pose_rot[bone_i] = _skeleton.get_bone_pose_rotation(bone_i)


func _set_bone_delta_rotation(bone_idx: int, delta: Quaternion) -> void:
	if bone_idx < 0 or not _bind_pose_rot.has(bone_idx):
		return
	_skeleton.set_bone_pose_rotation(bone_idx, _bind_pose_rot[bone_idx] * delta)


func _apply_walk_pose(_delta: float) -> void:
	if _skeleton == null:
		return
	# Mild procedural walk on game_engine bones. Delta multiplies onto bind pose.
	var left := _skeleton.find_bone("thigh_l")
	var right := _skeleton.find_bone("thigh_r")
	var left_calf := _skeleton.find_bone("calf_l")
	var right_calf := _skeleton.find_bone("calf_r")
	var left_arm := _skeleton.find_bone("upperarm_l")
	var right_arm := _skeleton.find_bone("upperarm_r")
	if left < 0:
		left = _skeleton.find_bone("LeftUpLeg")
	if right < 0:
		right = _skeleton.find_bone("RightUpLeg")
	var swing := sin(_phase) * 0.28
	var knee := absf(sin(_phase)) * 0.35
	var arm_swing := sin(_phase) * 0.22
	_set_bone_delta_rotation(left, Quaternion(Vector3.RIGHT, swing))
	_set_bone_delta_rotation(right, Quaternion(Vector3.RIGHT, -swing))
	_set_bone_delta_rotation(left_calf, Quaternion(Vector3.RIGHT, knee if swing > 0.0 else 0.05))
	_set_bone_delta_rotation(right_calf, Quaternion(Vector3.RIGHT, knee if swing < 0.0 else 0.05))
	_set_bone_delta_rotation(left_arm, Quaternion(Vector3.RIGHT, -arm_swing))
	_set_bone_delta_rotation(right_arm, Quaternion(Vector3.RIGHT, arm_swing))


func _find_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root as MeshInstance3D
	for child in root.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
