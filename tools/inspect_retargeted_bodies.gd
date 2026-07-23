extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var paths: PackedStringArray = [
		"res://assets/humans/male_base.gltf",
		"res://assets/humans/animations/quaternius/AnimationLibrary_Godot_Standard.gltf",
	]
	for path in paths:
		print("========== ", path, " ==========")
		if not ResourceLoader.exists(path):
			print("MISSING: ", path)
			continue
		var packed: Resource = load(path)
		print("load type=", packed.get_class() if packed != null else "null")
		if packed == null:
			print("LOAD_FAILED")
			continue
		if not (packed is PackedScene):
			print("NOT_PACKED_SCENE")
			continue
		var inst: Node = (packed as PackedScene).instantiate()
		root.add_child(inst)
		print("--- node tree ---")
		_dump_tree(inst, 0)
		print("--- Skeleton3D ---")
		var skels: Array[Skeleton3D] = []
		_collect_skeletons(inst, skels)
		print("Skeleton3D count=", skels.size())
		for skel in skels:
			print("Skeleton path=", skel.get_path())
			print("bone_count=", skel.get_bone_count())
			var limit: int = mini(skel.get_bone_count(), 20)
			for i in range(limit):
				print("  bone[", i, "]=", skel.get_bone_name(i))
		print("--- AnimationPlayer ---")
		var players: Array[AnimationPlayer] = []
		_collect_players(inst, players)
		print("AnimationPlayer exists=", players.size() > 0, " count=", players.size())
		for player in players:
			print("AnimationPlayer path=", player.get_path())
			var anim_names: PackedStringArray = player.get_animation_list()
			print("animation_list size=", anim_names.size())
			var idle_walk: PackedStringArray = []
			for anim_name in anim_names:
				var lower: String = String(anim_name).to_lower()
				if "idle" in lower or "walk" in lower:
					idle_walk.append(anim_name)
			print("Idle/Walk anims:")
			if idle_walk.is_empty():
				print("  (none)")
			else:
				for anim_name in idle_walk:
					print("  ", anim_name)
			for anim_name in idle_walk:
				var lower2: String = String(anim_name).to_lower()
				if "walk" not in lower2:
					continue
				var anim: Animation = player.get_animation(anim_name)
				if anim == null:
					print("Walk anim missing resource: ", anim_name)
					continue
				print("--- Walk tracks: ", anim_name, " track_count=", anim.get_track_count(), " ---")
				var track_limit: int = mini(anim.get_track_count(), 5)
				for ti in range(track_limit):
					print("  track[", ti, "] path=", anim.track_get_path(ti), " type=", anim.track_get_type(ti))
		inst.queue_free()
		print("")
	quit(0)


func _dump_tree(n: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	print(pad, n.name, " [", n.get_class(), "]")
	for c in n.get_children():
		_dump_tree(c, depth + 1)


func _collect_skeletons(node: Node, out: Array[Skeleton3D]) -> void:
	if node is Skeleton3D:
		out.append(node as Skeleton3D)
	for child in node.get_children():
		_collect_skeletons(child, out)


func _collect_players(node: Node, out: Array[AnimationPlayer]) -> void:
	if node is AnimationPlayer:
		out.append(node as AnimationPlayer)
	for child in node.get_children():
		_collect_players(child, out)