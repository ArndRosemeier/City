@tool
extends EditorScenePostImportPlugin

## Auto-assigns humanoid BoneMaps + Rest Fixer so Quaternius clips share onto MPFB bodies.
## Godot 4.6 uses retarget_method (not overwrite_axis) and fix_silhouette/enable.


func _pre_process(scene: Node) -> void:
	var skel := _find_skeleton(scene)
	if skel == null:
		return
	var map_path := ""
	var is_quaternius := false
	if skel.find_bone("DEF-hips") >= 0:
		map_path = "res://assets/humans/animations/bonemap_quaternius.tres"
		is_quaternius = true
	elif skel.find_bone("pelvis") >= 0:
		map_path = "res://assets/humans/animations/bonemap_mpfb.tres"
	else:
		return
	if not ResourceLoader.exists(map_path):
		push_warning("humanoid_retarget: missing %s" % map_path)
		return
	var bone_map: BoneMap = load(map_path) as BoneMap
	if bone_map == null:
		push_warning("humanoid_retarget: failed to load %s" % map_path)
		return

	var subresources: Variant = get_option_value("_subresources")
	if typeof(subresources) != TYPE_DICTIONARY:
		subresources = {}
	var sub: Dictionary = subresources
	if not sub.has("nodes"):
		sub["nodes"] = {}
	var nodes: Dictionary = sub["nodes"]
	var key := "PATH:%s" % str(scene.get_path_to(skel))
	var node_opts: Dictionary = nodes.get(key, {})
	node_opts["retarget/bone_map"] = bone_map
	# Unify rests to SkeletonProfileHumanoid so absolute Godot 4 poses are shareable.
	node_opts["retarget/bone_renamer/rename_bones"] = true
	node_opts["retarget/bone_renamer/unique_node"] = true
	node_opts["retarget/rest_fixer/apply_node_transforms"] = true
	node_opts["retarget/rest_fixer/normalize_position_tracks"] = true
	node_opts["retarget/rest_fixer/reset_all_bone_poses_after_import"] = true
	# Godot 4.6+: 0=None, 1=Overwrite Axis, 2=Use Retarget Modifier
	node_opts["retarget/rest_fixer/retarget_method"] = 1
	# Preserve rests on unmapped leftovers (MPFB nipples → Blender neutral_bone, thumb_03_*).
	node_opts["retarget/rest_fixer/keep_global_rest_on_leftovers"] = true
	node_opts["retarget/rest_fixer/fix_silhouette/enable"] = not is_quaternius
	if not is_quaternius:
		node_opts["retarget/rest_fixer/fix_silhouette/threshold"] = 0.1
		# Keep authored foot rests so sole planting stays sane after silhouette fix.
		node_opts["retarget/rest_fixer/fix_silhouette/filter"] = PackedStringArray(
			["LeftFoot", "RightFoot", "LeftToes", "RightToes"]
		)
	if is_quaternius:
		node_opts["retarget/remove_tracks/unimportant_positions"] = true
		node_opts["retarget/remove_tracks/unmapped_bones"] = true
	nodes[key] = node_opts
	sub["nodes"] = nodes
	print(
		"humanoid_retarget: assigned ",
		map_path,
		" retarget_method=1 fix_silhouette/enable=",
		not is_quaternius,
		" -> ",
		key
	)


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null