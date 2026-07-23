## One-shot: write BoneMap resources for MPFB game_engine + Quaternius DEF-* rigs.
extends SceneTree


func _initialize() -> void:
	_write_map(
		"res://assets/humans/animations/bonemap_mpfb.tres",
		{
			"Root": &"Root",
			"Hips": &"pelvis",
			"Spine": &"spine_01",
			"Chest": &"spine_02",
			"UpperChest": &"spine_03",
			"Neck": &"neck_01",
			"Head": &"head",
			"LeftShoulder": &"clavicle_l",
			"LeftUpperArm": &"upperarm_l",
			"LeftLowerArm": &"lowerarm_l",
			"LeftHand": &"hand_l",
			"LeftThumbProximal": &"thumb_01_l",
			"LeftThumbDistal": &"thumb_02_l",
			"LeftIndexProximal": &"index_01_l",
			"LeftIndexIntermediate": &"index_02_l",
			"LeftIndexDistal": &"index_03_l",
			"LeftMiddleProximal": &"middle_01_l",
			"LeftMiddleIntermediate": &"middle_02_l",
			"LeftMiddleDistal": &"middle_03_l",
			"LeftRingProximal": &"ring_01_l",
			"LeftRingIntermediate": &"ring_02_l",
			"LeftRingDistal": &"ring_03_l",
			"LeftLittleProximal": &"pinky_01_l",
			"LeftLittleIntermediate": &"pinky_02_l",
			"LeftLittleDistal": &"pinky_03_l",
			"RightShoulder": &"clavicle_r",
			"RightUpperArm": &"upperarm_r",
			"RightLowerArm": &"lowerarm_r",
			"RightHand": &"hand_r",
			"RightThumbProximal": &"thumb_01_r",
			"RightThumbDistal": &"thumb_02_r",
			"RightIndexProximal": &"index_01_r",
			"RightIndexIntermediate": &"index_02_r",
			"RightIndexDistal": &"index_03_r",
			"RightMiddleProximal": &"middle_01_r",
			"RightMiddleIntermediate": &"middle_02_r",
			"RightMiddleDistal": &"middle_03_r",
			"RightRingProximal": &"ring_01_r",
			"RightRingIntermediate": &"ring_02_r",
			"RightRingDistal": &"ring_03_r",
			"RightLittleProximal": &"pinky_01_r",
			"RightLittleIntermediate": &"pinky_02_r",
			"RightLittleDistal": &"pinky_03_r",
			"LeftUpperLeg": &"thigh_l",
			"LeftLowerLeg": &"calf_l",
			"LeftFoot": &"foot_l",
			"LeftToes": &"ball_l",
			"RightUpperLeg": &"thigh_r",
			"RightLowerLeg": &"calf_r",
			"RightFoot": &"foot_r",
			"RightToes": &"ball_r",
		}
	)
	_write_map(
		"res://assets/humans/animations/bonemap_quaternius.tres",
		{
			"Root": &"root",
			"Hips": &"DEF-hips",
			"Spine": &"DEF-spine.001",
			"Chest": &"DEF-spine.002",
			"UpperChest": &"DEF-spine.003",
			"Neck": &"DEF-neck",
			"Head": &"DEF-head",
			"LeftShoulder": &"DEF-shoulder.L",
			"LeftUpperArm": &"DEF-upper_arm.L",
			"LeftLowerArm": &"DEF-forearm.L",
			"LeftHand": &"DEF-hand.L",
			"LeftThumbProximal": &"DEF-thumb.01.L",
			"LeftThumbDistal": &"DEF-thumb.02.L",
			"LeftIndexProximal": &"DEF-f_index.01.L",
			"LeftIndexIntermediate": &"DEF-f_index.02.L",
			"LeftIndexDistal": &"DEF-f_index.03.L",
			"LeftMiddleProximal": &"DEF-f_middle.01.L",
			"LeftMiddleIntermediate": &"DEF-f_middle.02.L",
			"LeftMiddleDistal": &"DEF-f_middle.03.L",
			"LeftRingProximal": &"DEF-f_ring.01.L",
			"LeftRingIntermediate": &"DEF-f_ring.02.L",
			"LeftRingDistal": &"DEF-f_ring.03.L",
			"LeftLittleProximal": &"DEF-f_pinky.01.L",
			"LeftLittleIntermediate": &"DEF-f_pinky.02.L",
			"LeftLittleDistal": &"DEF-f_pinky.03.L",
			"RightShoulder": &"DEF-shoulder.R",
			"RightUpperArm": &"DEF-upper_arm.R",
			"RightLowerArm": &"DEF-forearm.R",
			"RightHand": &"DEF-hand.R",
			"RightThumbProximal": &"DEF-thumb.01.R",
			"RightThumbDistal": &"DEF-thumb.02.R",
			"RightIndexProximal": &"DEF-f_index.01.R",
			"RightIndexIntermediate": &"DEF-f_index.02.R",
			"RightIndexDistal": &"DEF-f_index.03.R",
			"RightMiddleProximal": &"DEF-f_middle.01.R",
			"RightMiddleIntermediate": &"DEF-f_middle.02.R",
			"RightMiddleDistal": &"DEF-f_middle.03.R",
			"RightRingProximal": &"DEF-f_ring.01.R",
			"RightRingIntermediate": &"DEF-f_ring.02.R",
			"RightRingDistal": &"DEF-f_ring.03.R",
			"RightLittleProximal": &"DEF-f_pinky.01.R",
			"RightLittleIntermediate": &"DEF-f_pinky.02.R",
			"RightLittleDistal": &"DEF-f_pinky.03.R",
			"LeftUpperLeg": &"DEF-thigh.L",
			"LeftLowerLeg": &"DEF-shin.L",
			"LeftFoot": &"DEF-foot.L",
			"LeftToes": &"DEF-toe.L",
			"RightUpperLeg": &"DEF-thigh.R",
			"RightLowerLeg": &"DEF-shin.R",
			"RightFoot": &"DEF-foot.R",
			"RightToes": &"DEF-toe.R",
		}
	)
	print("Wrote BoneMap resources.")
	quit(0)


func _write_map(path: String, mapping: Dictionary) -> void:
	var bone_map := BoneMap.new()
	bone_map.profile = SkeletonProfileHumanoid.new()
	for profile_bone in mapping.keys():
		bone_map.set_skeleton_bone_name(StringName(profile_bone), mapping[profile_bone])
	var err := ResourceSaver.save(bone_map, path)
	if err != OK:
		push_error("Failed to save %s err=%s" % [path, err])
	else:
		print("Saved ", path)
