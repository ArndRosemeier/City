extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load("res://assets/humans/male_base.gltf")
	var inst: Node = packed.instantiate()
	get_root().add_child(inst)
	var skel := _find_skel(inst)
	if skel == null:
		push_error("No Skeleton3D found")
		quit(1)
		return
	var n := skel.get_bone_count()
	print("bone count=", n)
	for i in range(n):
		print(i, "\t", skel.get_bone_name(i))
	quit(0)

func _find_skel(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root
	for c in root.get_children():
		var f := _find_skel(c)
		if f:
			return f
	return null
