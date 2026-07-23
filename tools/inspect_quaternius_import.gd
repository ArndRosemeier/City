extends SceneTree

func _init() -> void:
	var path := "res://assets/humans/animations/quaternius/AnimationLibrary_Godot_Standard.gltf"
	var res: Resource = load(path)
	if res == null:
		print("LOAD_FAILED: resource is null")
		quit(1)
		return

	print("LOADED_TYPE: ", res.get_class())

	if res is PackedScene:
		print("IS_PACKED_SCENE: true")
		var packed: PackedScene = res as PackedScene
		var root: Node = packed.instantiate()
		_print_skeleton_bones(root)
		_print_animation_player(root)
		root.free()
	elif res is AnimationLibrary:
		print("IS_ANIMATION_LIBRARY: true")
		var lib: AnimationLibrary = res as AnimationLibrary
		var names: PackedStringArray = lib.get_animation_list()
		print("ANIMATION_COUNT: ", names.size())
		for anim_name in names:
			print("ANIM: ", anim_name)
	else:
		print("UNEXPECTED_TYPE: ", res.get_class())

	quit()

func _print_skeleton_bones(node: Node) -> void:
	var skeletons: Array[Skeleton3D] = []
	_collect_skeletons(node, skeletons)
	print("SKELETON_COUNT: ", skeletons.size())
	for skel in skeletons:
		print("SKELETON_PATH: ", skel.get_path())
		print("BONE_COUNT: ", skel.get_bone_count())
		for i in range(skel.get_bone_count()):
			print("BONE: ", skel.get_bone_name(i))

func _collect_skeletons(node: Node, out: Array[Skeleton3D]) -> void:
	if node is Skeleton3D:
		out.append(node as Skeleton3D)
	for child in node.get_children():
		_collect_skeletons(child, out)

func _print_animation_player(node: Node) -> void:
	var players: Array[AnimationPlayer] = []
	_collect_animation_players(node, players)
	print("ANIMATION_PLAYER_COUNT: ", players.size())
	for player in players:
		print("ANIMATION_PLAYER_PATH: ", player.get_path())
		var anim_names: PackedStringArray = player.get_animation_list()
		print("ANIMATION_COUNT: ", anim_names.size())
		for anim_name in anim_names:
			print("ANIM: ", anim_name)

func _collect_animation_players(node: Node, out: Array[AnimationPlayer]) -> void:
	if node is AnimationPlayer:
		out.append(node as AnimationPlayer)
	for child in node.get_children():
		_collect_animation_players(child, out)