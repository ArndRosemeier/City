## Player/NPC body proportions. Blend shapes when present; otherwise skeleton scales.
class_name BodyProportions
extends RefCounted

const MORPH_HEIGHT := "height"
const MORPH_WEIGHT := "weight"
const MORPH_TORSO := "torso_length"
const MORPH_LEGS := "leg_length"
const MORPH_SHOULDERS := "shoulder_width"

## Normalized params in roughly [-1, 1]. 0 = authored rest.
var height: float = 0.0
var weight: float = 0.0
var muscle: float = 0.0
var torso_length: float = 0.0
var leg_length: float = 0.0
var arm_length: float = 0.0
var shoulder_width: float = 0.0
var hip_width: float = 0.0
var head_size: float = 0.0
var neck_length: float = 0.0
var hand_size: float = 0.0
var foot_size: float = 0.0


static func identity() -> BodyProportions:
	return BodyProportions.new()


static func random(rng: RandomNumberGenerator) -> BodyProportions:
	var p := BodyProportions.new()
	p.height = rng.randf_range(-0.55, 0.65)
	p.weight = rng.randf_range(-0.55, 0.75)
	p.muscle = rng.randf_range(-0.45, 0.7)
	p.torso_length = rng.randf_range(-0.45, 0.45)
	p.leg_length = rng.randf_range(-0.45, 0.5)
	p.arm_length = rng.randf_range(-0.4, 0.45)
	p.shoulder_width = rng.randf_range(-0.45, 0.55)
	p.hip_width = rng.randf_range(-0.4, 0.5)
	p.head_size = rng.randf_range(-0.35, 0.4)
	p.neck_length = rng.randf_range(-0.35, 0.4)
	p.hand_size = rng.randf_range(-0.35, 0.4)
	p.foot_size = rng.randf_range(-0.35, 0.4)
	return p


func duplicate_props() -> BodyProportions:
	var p := BodyProportions.new()
	p.height = height
	p.weight = weight
	p.muscle = muscle
	p.torso_length = torso_length
	p.leg_length = leg_length
	p.arm_length = arm_length
	p.shoulder_width = shoulder_width
	p.hip_width = hip_width
	p.head_size = head_size
	p.neck_length = neck_length
	p.hand_size = hand_size
	p.foot_size = foot_size
	return p


func reset() -> void:
	height = 0.0
	weight = 0.0
	muscle = 0.0
	torso_length = 0.0
	leg_length = 0.0
	arm_length = 0.0
	shoulder_width = 0.0
	hip_width = 0.0
	head_size = 0.0
	neck_length = 0.0
	hand_size = 0.0
	foot_size = 0.0


## Uniform body scale from height slider (applied on the body root Node3D).
func body_uniform_scale() -> float:
	return _scale_factor(height, 0.18)


func capsule_height(base: float = 1.7) -> float:
	return base * body_uniform_scale() * _scale_factor(leg_length, 0.08) * _scale_factor(torso_length, 0.06)


func capsule_radius(base: float = 0.35) -> float:
	return base * _scale_factor(weight, 0.14) * _scale_factor(hip_width, 0.06)


func apply_to_mesh(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	_set_blend(mesh_instance, MORPH_HEIGHT, height)
	_set_blend(mesh_instance, MORPH_WEIGHT, weight)
	_set_blend(mesh_instance, MORPH_TORSO, torso_length)
	_set_blend(mesh_instance, MORPH_LEGS, leg_length)
	_set_blend(mesh_instance, MORPH_SHOULDERS, shoulder_width)


## Bone name → local pose scale. Applied after animation by ProportionModifier.
func bone_scales() -> Dictionary:
	var w_xz := _scale_factor(weight, 0.12)
	var muscle_xz := _scale_factor(muscle, 0.1)
	var torso_y := _scale_factor(torso_length, 0.14)
	var leg_y := _scale_factor(leg_length, 0.16)
	var arm_y := _scale_factor(arm_length, 0.14)
	var shoulder := _scale_factor(shoulder_width, 0.16)
	var hips := _scale_factor(hip_width, 0.14)
	var head := _scale_factor(head_size, 0.16)
	var neck_y := _scale_factor(neck_length, 0.18)
	var hand := _scale_factor(hand_size, 0.18)
	var foot := _scale_factor(foot_size, 0.18)
	var torso_xz := w_xz * muscle_xz
	return {
		&"Hips": Vector3(hips * w_xz, 1.0, hips * w_xz),
		&"Spine": Vector3(torso_xz, torso_y, torso_xz),
		&"Chest": Vector3(torso_xz * shoulder, torso_y, torso_xz),
		&"UpperChest": Vector3(torso_xz * shoulder, torso_y, torso_xz),
		&"Neck": Vector3(1.0, neck_y, 1.0),
		&"Head": Vector3(head, head, head),
		&"LeftShoulder": Vector3(shoulder, 1.0, shoulder),
		&"RightShoulder": Vector3(shoulder, 1.0, shoulder),
		&"LeftUpperArm": Vector3(muscle_xz, arm_y, muscle_xz),
		&"RightUpperArm": Vector3(muscle_xz, arm_y, muscle_xz),
		&"LeftLowerArm": Vector3(1.0, arm_y, 1.0),
		&"RightLowerArm": Vector3(1.0, arm_y, 1.0),
		&"LeftHand": Vector3(hand, hand, hand),
		&"RightHand": Vector3(hand, hand, hand),
		&"LeftUpperLeg": Vector3(w_xz, leg_y, w_xz),
		&"RightUpperLeg": Vector3(w_xz, leg_y, w_xz),
		&"LeftLowerLeg": Vector3(1.0, leg_y, 1.0),
		&"RightLowerLeg": Vector3(1.0, leg_y, 1.0),
		&"LeftFoot": Vector3(foot, foot, foot),
		&"RightFoot": Vector3(foot, foot, foot),
	}


func _scale_factor(value: float, amount: float) -> float:
	return 1.0 + clampf(value, -1.0, 1.0) * amount


func _set_blend(mesh_instance: MeshInstance3D, morph_name: String, value: float) -> void:
	# Godot blend shapes are typically [0, 1]; map [-1,1] -> [0,1] around 0.5 rest.
	var weight_01 := clampf(0.5 + value * 0.5, 0.0, 1.0)
	var idx := _find_blend_shape_index(mesh_instance, morph_name)
	if idx >= 0:
		mesh_instance.set_blend_shape_value(idx, weight_01)


func _find_blend_shape_index(mesh_instance: MeshInstance3D, morph_name: String) -> int:
	var mesh := mesh_instance.mesh
	if mesh == null:
		return -1
	for i in range(mesh.get_blend_shape_count()):
		if String(mesh.get_blend_shape_name(i)) == morph_name:
			return i
	return -1
