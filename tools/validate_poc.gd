## Headless smoke test: load bases, spawn one pedestrian, check anatomy slot.
extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var errors := 0
	for path in ["res://assets/humans/male_base.gltf", "res://assets/humans/female_base.gltf"]:
		if not ResourceLoader.exists(path):
			push_error("Missing %s" % path)
			errors += 1
			continue
		var packed := load(path)
		if packed == null:
			push_error("Failed to load %s" % path)
			errors += 1
		elif packed is PackedScene:
			var inst: Node = packed.instantiate()
			var mesh := _find_mesh(inst)
			if mesh == null:
				push_error("%s has no MeshInstance3D" % path)
				errors += 1
			elif mesh.mesh != null and mesh.mesh.get_blend_shape_count() < 1:
				push_warning("%s has no blend shapes (proportions will use fallback only)" % path)
			inst.free()

	var ped_scene: PackedScene = load("res://scenes/human/pedestrian.tscn")
	var ped := ped_scene.instantiate() as Pedestrian
	var root := Node3D.new()
	root.add_child(ped)
	root.add_child(Node3D.new())  # keep tree alive briefly
	get_root().add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	ped.setup(Pedestrian.Sex.MALE, BodyProportions.random(rng), rng)
	if ped.get_node_or_null("AnatomySlot") == null:
		push_error("Pedestrian missing AnatomySlot")
		errors += 1
	await create_timer(0.1).timeout
	print("POC validate finished with %d errors" % errors)
	quit(1 if errors > 0 else 0)


func _find_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root as MeshInstance3D
	for child in root.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null
