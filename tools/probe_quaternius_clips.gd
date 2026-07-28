## Lists the animation clips in the shared Quaternius human library. Diagnostic only.
extends Node


func _ready() -> void:
	var packed: Resource = load(QuaterniusLocomotion.LIB_PATH)
	if not (packed is PackedScene):
		push_error("FAIL library is not a PackedScene")
		get_tree().quit(1)
		return
	var root: Node = (packed as PackedScene).instantiate()
	var player := _find_player(root)
	if player == null:
		push_error("FAIL no AnimationPlayer in library")
		root.free()
		get_tree().quit(1)
		return
	var names := player.get_animation_list()
	print("CLIPS(%d):" % names.size())
	for n in names:
		print("  ", n, "  length=", player.get_animation(n).length)
	## Whether the clips touch finger bones decides how an mhclo weapon behaves: MPFB skins one
	## across the hand and thumb, so it only deforms if those bones actually move.
	var finger_bones: Dictionary[String, int] = {}
	for n in ["Walk", "Sprint", "Sword_Attack", "Sword_Idle", "Idle"]:
		if not player.has_animation(n):
			continue
		var anim := player.get_animation(n)
		var hits := 0
		for i in anim.get_track_count():
			var path := String(anim.track_get_path(i))
			var lowered := path.to_lower()
			if (
				lowered.contains("thumb")
				or lowered.contains("index")
				or lowered.contains("middle")
				or lowered.contains("ring")
				or lowered.contains("little")
				or lowered.contains("pinky")
				or lowered.contains("finger")
			):
				hits += 1
				finger_bones[path] = int(finger_bones.get(path, 0)) + 1
		print("  FINGER TRACKS in %s: %d of %d tracks" % [n, hits, anim.get_track_count()])
	if not finger_bones.is_empty():
		print("  finger bone tracks seen: ", finger_bones.keys())
	root.free()
	print("RESULT: OK")
	get_tree().quit(0)


func _find_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null
