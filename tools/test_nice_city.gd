extends SceneTree
## Headless smoke: generate district and assert plaza / park / building variety.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var root := CityRoot.new()
	root.city_seed = 42
	root.crowd_count = 0
	get_root().add_child(root)

	for _i in range(2400):
		await process_frame
		if root.get_node_or_null("Walker") != null:
			break

	var terrain: VoxelTerrain = root.get_node_or_null("VoxelTerrain")
	var walker: CityWalker = root.get_node_or_null("Walker")
	print("gen_ms=", Time.get_ticks_msec() - t0)
	if terrain == null or walker == null:
		push_error("FAIL missing terrain/walker")
		quit(1)
		return

	var tool: VoxelTool = terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_TYPE

	var counts: Dictionary = {}
	var size := 384
	var y := 1
	for z in range(0, size, 4):
		for x in range(0, size, 4):
			var id := tool.get_voxel(Vector3i(x, y, z))
			counts[id] = int(counts.get(id, 0)) + 1

	print("sample_counts=", counts)
	var need := [
		VoxelMaterial.ASPHALT,
		VoxelMaterial.PLAZA,
		VoxelMaterial.PARK,
		VoxelMaterial.SIDEWALK,
		VoxelMaterial.PLASTER,
	]
	for id in need:
		if int(counts.get(id, 0)) <= 0:
			push_error("FAIL missing material id=%d in ground sample" % id)
			quit(1)
			return

	# Look for architectural signals a bit above ground.
	var found_metal := false
	var found_clay := false
	var found_water := false
	var found_leaves := false
	var found_glass := false
	for z in range(0, size, 3):
		for x in range(0, size, 3):
			for yy in range(1, 45):
				var id2 := tool.get_voxel(Vector3i(x, yy, z))
				if id2 == VoxelMaterial.METAL:
					found_metal = true
				elif id2 == VoxelMaterial.ROOF_CLAY:
					found_clay = true
				elif id2 == VoxelMaterial.WATER:
					found_water = true
				elif id2 == VoxelMaterial.LEAVES:
					found_leaves = true
				elif id2 == VoxelMaterial.GLASS:
					found_glass = true
	print(
		"metal=", found_metal,
		" roof_clay=", found_clay,
		" water=", found_water,
		" leaves=", found_leaves,
		" glass=", found_glass,
		" walker=", walker.global_position
	)
	if not found_water:
		push_error("FAIL no water (plaza fountain / park pond)")
		quit(1)
		return
	if not found_leaves:
		push_error("FAIL no tree leaves")
		quit(1)
		return
	if not found_glass:
		push_error("FAIL no glass windows")
		quit(1)
		return

	print("OK nice_city_smoke")
	quit(0)
