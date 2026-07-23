extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path in ["res://assets/humans/male_base.glb", "res://assets/humans/female_base.glb"]:
		print("=== ", path, " ===")
		var packed = load(path)
		if packed == null:
			print("FAILED load")
			continue
		var inst: Node = packed.instantiate()
		_dump(inst, 0)
		inst.free()
	quit(0)


func _dump(n: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	print(pad, n.name, " [", n.get_class(), "]")
	if n is Skeleton3D:
		var sk: Skeleton3D = n
		print(pad, "  bones=", sk.get_bone_count())
		for i in range(mini(sk.get_bone_count(), 60)):
			print(pad, "   ", i, ": ", sk.get_bone_name(i))
	for c in n.get_children():
		_dump(c, depth + 1)
