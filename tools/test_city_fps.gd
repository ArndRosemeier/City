extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var root := CityRoot.new()
	root.city_seed = 3
	get_root().add_child(root)
	for _i in range(1800):
		await process_frame
		if root.get_node_or_null("Walker") != null:
			break
	var walker: CityWalker = root.get_node_or_null("Walker")
	var terrain: VoxelTerrain = root.get_node_or_null("VoxelTerrain")
	print("gen_ms=", Time.get_ticks_msec() - t0)
	print("terrain=", terrain != null)
	print("walker=", walker != null, " pos=", walker.global_position if walker else Vector3.ZERO)
	if walker == null or terrain == null:
		push_error("FAIL no walker or terrain")
		quit(1)
		return

	# Let physics settle and sole-plant against the capsule contact plane.
	for _j in range(180):
		await process_frame
		if walker.is_feet_aligned():
			break
	print("feet_aligned=", walker.is_feet_aligned(), " pos=", walker.global_position)

	var tool: VoxelTool = terrain.get_voxel_tool()
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	var solid := _find_nearby_solid(tool, terrain, walker.global_position)
	if solid == Vector3i(-1, -1, -1):
		push_error("FAIL no solid voxel near walker")
		quit(1)
		return
	var before := tool.get_voxel(solid)
	print("solid_at=", solid, " before=", before)
	tool.mode = VoxelTool.MODE_SET
	tool.value = VoxelMaterial.AIR
	tool.do_sphere(Vector3(solid) + Vector3(0.5, 0.5, 0.5), 3.5)
	var after := tool.get_voxel(solid)
	print("dig after=", after)
	if before == VoxelMaterial.AIR or after != VoxelMaterial.AIR:
		push_error("FAIL dig did not clear solid voxel")
		quit(1)
		return

	# Bedrock floor must survive a sphere that overlaps y=0.
	var floor_v := Vector3i(solid.x, 0, solid.z)
	tool.value = VoxelMaterial.AIR
	tool.do_sphere(Vector3(floor_v) + Vector3(0.5, 0.5, 0.5), 4.0)
	# Mirror CityRoot protection.
	root._restore_bedrock_floor(Vector3(floor_v) + Vector3(0.5, 0.5, 0.5), 4.0)
	var floor_after := tool.get_voxel(floor_v)
	print("bedrock_at=", floor_v, " after=", floor_after)
	if floor_after != VoxelMaterial.BEDROCK:
		push_error("FAIL bedrock floor was destroyed")
		quit(1)
		return

	print("PASS voxel city FPS + dig")
	# Avoid module teardown crash in headless by exiting immediately.
	OS.kill(OS.get_process_id())


func _find_nearby_solid(tool: VoxelTool, terrain: VoxelTerrain, world_pos: Vector3) -> Vector3i:
	var origin := Vector3i(terrain.to_local(world_pos).floor())
	for radius in range(1, 40):
		for y in range(1, 12):
			for dz in range(-radius, radius + 1):
				for dx in range(-radius, radius + 1):
					if maxi(absi(dx), absi(dz)) != radius:
						continue
					var p := origin + Vector3i(dx, y, dz)
					var id := tool.get_voxel(p)
					if (
						id == VoxelMaterial.CONCRETE
						or id == VoxelMaterial.BRICK
						or id == VoxelMaterial.GLASS
						or id == VoxelMaterial.ROOF
					):
						return p
	return Vector3i(-1, -1, -1)
