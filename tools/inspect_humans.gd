extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path in [
		"res://assets/humans/male_base.gltf",
		"res://assets/humans/male_base.glb",
		"res://assets/humans/female_base.gltf",
	]:
		print("exists(", path, ")=", ResourceLoader.exists(path))
		var packed = load(path)
		print("load type=", packed)
		if packed is PackedScene:
			var inst: Node = packed.instantiate()
			_dump(inst, 0)
			var mesh := _find_mesh(inst)
			var skel := _find_skel(inst)
			print("FOUND mesh=", mesh, " skel=", skel)
			if mesh != null:
				print("  mesh resource=", mesh.mesh)
				print("  blend shapes=", mesh.mesh.get_blend_shape_count() if mesh.mesh else -1)
			inst.free()
	quit(0)


func _dump(n: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var extra := ""
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		extra = " mesh=%s" % mi.mesh
	print(pad, n.name, " [", n.get_class(), "]", extra)
	for c in n.get_children():
		_dump(c, depth + 1)


func _find_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root
	for c in root.get_children():
		var f := _find_mesh(c)
		if f:
			return f
	return null


func _find_skel(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root
	for c in root.get_children():
		var f := _find_skel(c)
		if f:
			return f
	return null
