## Photographs a live crowd walking the navigation stack, and measures what it is standing on.
##
## tools/shot_nav_overlay_city.tscn is the picture of the overlay itself; this one is the
## picture of the pedestrians: the streamed city, a district's CrowdDirector left to walk for
## a few seconds, then three frames — the crowd as a player sees it, the same view with the F8
## corridors drawn over it, and one from above where the street layout is legible.
##
## The walker is moved to the crowd first, and that is not framing. Every LOD decision the
## crowd makes is measured from the player's camera: peds only get skinned visuals, capsules
## and near-tier ticks near it, and CrowdDirector only feeds the overlay corridors of near-tier
## peds. A picture taken from anywhere else is a picture of the far tier, which is invisible.
##
## The surface tally is the eyeball check made countable. Every living ped's footing is read
## straight out of the voxel field, so "peds prefer pavement and cross at crossings" is a
## number in the log next to the image rather than an impression of it.
##
## Needs a renderer, both for the capture and because the district bake waits on
## `is_area_editable`, which never becomes true headless.
##
## Run: Godot --path . res://tools/shot_ped_crowd.tscn --spawn-district=0,0
##
## The spawn tile has to be pinned. Pedestrian routing is only worth photographing where there
## is a carriageway to keep off and crossings to use, and the outer-ring themes — Hill, Graveyard
## and Lake — carry edge road stubs only. (0,0) is always the high-rise core.
extends Node

const WORLD_SEED := 42
## Themes with a street grid through the tile rather than stubs at its edges.
const STREET_THEMES: Array[int] = [
	DistrictTheme.CORE_HIGHRISE,
	DistrictTheme.OLD_TOWN,
	DistrictTheme.WATERFRONT_INDUSTRIAL,
	DistrictTheme.GARDEN_RESIDENTIAL,
	DistrictTheme.CIVIC_QUARTER,
]
const WALKER_TIMEOUT_MS := 120000
const CROWD_TIMEOUT_MS := 60000
## Long enough that errands are under way and corridors exist, short enough to stay a tool.
const WALK_MS := 9000
const SHOT_HOUR := 11.0
## How far back from the crowd the walker stands. The camera sits on an arm behind it, so the
## peds land in the middle distance rather than in the lens.
const STAND_BACK_M := 12.0
## Radius the busiest patch of pavement is measured over. Ninety-six peds spread over a 392 x
## 280 m tile are not a crowd anywhere in particular, so the picture has to find where they are.
const CLUSTER_RADIUS_M := 25.0
## Tight enough that the spans do not bury the corridors drawn over them.
const OVERLAY_RADIUS_M := 26.0
## How near a crossing a ped in the road still counts as using one. A carriageway here is 8 m,
## so this covers stepping off a crossing and cutting its corner, and nothing further.
const CROSSING_REACH_M := 4.0

const CROWD_PNG := "res://tools/ped_crowd_street.png"
const CORRIDOR_PNG := "res://tools/ped_crowd_corridors.png"
const ABOVE_PNG := "res://tools/ped_crowd_above.png"

## Footing a ped may stand on without being in the road.
const PAVEMENT_IDS: Array[int] = [
	VoxelMaterial.SIDEWALK,
	VoxelMaterial.PLAZA,
	VoxelMaterial.PARK,
	VoxelMaterial.TILES,
	VoxelMaterial.GRAVEL,
	VoxelMaterial.DIRT,
	VoxelMaterial.CURB,
]
const ROAD_IDS: Array[int] = [VoxelMaterial.ROAD, VoxelMaterial.ASPHALT, VoxelMaterial.ROAD_LINE]


func _ready() -> void:
	var city := CityRoot.new()
	city.city_seed = WORLD_SEED
	add_child(city)

	var walker := await _await_walker(city)
	if walker == null:
		return
	if not await _await_boot(walker):
		return
	if not STREET_THEMES.has(city.spawn_theme_id):
		push_error(
			"FAIL spawned in %s, which has no street grid to route on — run with"
			% DistrictTheme.make(city.spawn_theme_id).display_name
			+ " --spawn-district=0,0"
		)
		get_tree().quit(1)
		return
	var crowd := await _await_crowd(city, walker)
	if crowd == null:
		return

	var overlay := city.get_node_or_null("NavDebugOverlay") as NavDebugOverlay
	if overlay == null:
		push_error("FAIL CityRoot built no NavDebugOverlay")
		get_tree().quit(1)
		return
	_hide_city_hud(city)
	_hide_error_panel()
	_pin_hour(city)
	_stand_in_the_crowd(city, walker, crowd)

	## Let the crowd get on with its errands before anyone photographs it.
	await _wait_ms(WALK_MS)

	var provider := crowd.goal_provider()
	var tiers := crowd.count_lod_tiers()
	print(
		"crowd: agents=%d skinned=%d near=%d mid=%d far=%d colliders=%d %s"
		% [
			crowd.agent_count(),
			crowd.get_skinned_count(),
			tiers.x,
			tiers.y,
			tiers.z,
			crowd.collider_count(),
			provider.describe_load(),
		]
	)
	if provider.goals_reached() <= 0:
		push_error("FAIL the live crowd reached no goal in %d ms" % WALK_MS)
		get_tree().quit(1)
		return
	if tiers.x <= 0:
		var eye := walker.get_camera().global_position
		var closest := crowd.find_nearest_agent(eye, 4000.0)
		push_error(
			"FAIL no ped reached the near tier: camera at %s, nearest ped %s"
			% [
				str(eye),
				(
					"none within 4 km"
					if closest.is_empty()
					else "%.1f m away" % eye.distance_to(closest["position"] as Vector3)
				),
			]
		)
		get_tree().quit(1)
		return
	_report_footing(city, crowd)

	await _shoot(CROWD_PNG)

	overlay.radius_m = OVERLAY_RADIUS_M
	overlay.set_enabled(true)
	## The corridor layer is fed on CrowdDirector's LOD cadence, not per repath.
	await _wait_ms(1200)
	if overlay.corridor_count() == 0:
		push_error("FAIL the overlay drew no ped corridors")
		get_tree().quit(1)
		return
	print("overlay: %s" % overlay.counter_line())
	await _shoot(CORRIDOR_PNG)

	var eye := walker.global_position + Vector3(-14.0, 22.0, 16.0)
	await _shoot_from(eye, walker.global_position, 60.0, ABOVE_PNG)

	print("RESULT: OK")
	get_tree().quit(0)


func _await_walker(city: CityRoot) -> CityWalker:
	var deadline := Time.get_ticks_msec() + WALKER_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var walker := city.get_node_or_null("Walker") as CityWalker
		if walker != null:
			return walker
	push_error("FAIL no walker after %d ms" % WALKER_TIMEOUT_MS)
	get_tree().quit(1)
	return null


## Boot is over when the walker has physics: CityRoot holds it off until ground collision
## exists, and the same await ends by placing the walker at the spawn, aiming it and showing the
## HUD again. Anything this tool does before that is undone.
func _await_boot(walker: CityWalker) -> bool:
	var deadline := Time.get_ticks_msec() + WALKER_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if walker.is_physics_processing():
			## The last of the placement runs a physics frame after that flag goes up.
			await _frames(4)
			return true
	push_error("FAIL the walker never got physics in %d ms" % WALKER_TIMEOUT_MS)
	get_tree().quit(1)
	return false


## The crowd of the district the walker stands in, once it has spawned its peds. Nearest rather
## than first: only the tile the player is on bakes at full quality, so that is the only one
## with a crowd worth photographing.
func _await_crowd(city: CityRoot, walker: CityWalker) -> CrowdDirector:
	var deadline := Time.get_ticks_msec() + CROWD_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var best: CrowdDirector = null
		var best_d2 := INF
		for inst: Variant in _loaded_districts(city):
			var district: DistrictInstance = inst
			if district.crowd == null or not is_instance_valid(district.crowd):
				continue
			if district.crowd.agent_count() == 0:
				continue
			var d2 := district.world_aabb_center().distance_squared_to(walker.global_position)
			if d2 >= best_d2:
				continue
			best_d2 = d2
			best = district.crowd
		if best != null:
			return best
	push_error("FAIL no district crowd spawned a ped in %d ms" % CROWD_TIMEOUT_MS)
	get_tree().quit(1)
	return null


## Put the player among the peds, facing them. Peds spawn wherever the district's pavement is,
## which is not where the walker happened to drop in.
func _stand_in_the_crowd(city: CityRoot, walker: CityWalker, crowd: CrowdDirector) -> void:
	var at := _busiest_pavement(city, crowd)
	if at == Vector3.INF:
		push_error("FAIL the crowd has no living ped to stand with")
		return
	var back := Vector3(0.62, 0.0, 0.78).normalized() * STAND_BACK_M
	## Parked, not dropped: the collision viewer rides the camera, so a walker teleported onto
	## a street whose collision blocks have not streamed yet falls through it, and nine seconds
	## of that puts the LOD observer four hundred metres under the crowd.
	walker.set_physics_process(false)
	walker.velocity = Vector3.ZERO
	walker.global_position = at + back + Vector3(0.0, 0.9, 0.0)
	walker.set_yaw(atan2(back.x, back.z))
	print("walker stands %.0f m off %s" % [STAND_BACK_M, str(at)])


## The centre of the busiest patch of the district: whichever ped has the most company inside
## `CLUSTER_RADIUS_M`, averaged with that company. Peds off the carriageway are preferred, so the
## frame is pavement and crossings rather than the middle of a road.
func _busiest_pavement(city: CityRoot, crowd: CrowdDirector) -> Vector3:
	var tool := _footing_tool(city)
	if tool == null:
		return Vector3.INF
	var terrain := city.voxel_terrain()
	var live: Array[Vector3] = []
	var off_road: Array[bool] = []
	for i in range(crowd.agent_count()):
		var ped := crowd.agent_at(i)
		if ped == null or ped.dead:
			continue
		live.append(ped.global_position)
		var id := _footing_id(terrain, tool, ped.global_position)
		off_road.append(id == VoxelMaterial.CROSSWALK or PAVEMENT_IDS.has(id))
	if live.is_empty():
		return Vector3.INF
	var r2 := CLUSTER_RADIUS_M * CLUSTER_RADIUS_M
	var best := Vector3.INF
	var best_score := -1.0
	for i in range(live.size()):
		var sum := Vector3.ZERO
		var near := 0
		for j in range(live.size()):
			if Vector2(live[i].x - live[j].x, live[i].z - live[j].z).length_squared() > r2:
				continue
			sum += live[j]
			near += 1
		var score := float(near) + (1.5 if off_road[i] else 0.0)
		if score <= best_score:
			continue
		best_score = score
		best = sum / float(near)
	return best


func _loaded_districts(city: CityRoot) -> Array:
	var streamer := city.get_node_or_null("CityStreamer") as CityStreamer
	if streamer == null:
		push_error("FAIL CityRoot has no CityStreamer to list districts from")
		return []
	return streamer.get_loaded_districts()


## What the crowd is standing on, read out of the voxel field one ped at a time.
func _report_footing(city: CityRoot, crowd: CrowdDirector) -> void:
	var tool := _footing_tool(city)
	if tool == null:
		return
	var terrain := city.voxel_terrain()
	var pavement := 0
	var crossing := 0
	var road := 0
	var other := 0
	var road_near_crossing := 0
	for i in range(crowd.agent_count()):
		var ped := crowd.agent_at(i)
		if ped == null or ped.dead:
			continue
		var id := _footing_id(terrain, tool, ped.global_position)
		if id == VoxelMaterial.CROSSWALK:
			crossing += 1
		elif PAVEMENT_IDS.has(id):
			pavement += 1
		elif ROAD_IDS.has(id):
			road += 1
			if _crossing_within(terrain, tool, ped.global_position, CROSSING_REACH_M):
				road_near_crossing += 1
		else:
			other += 1
	var on_street := pavement + crossing + road
	if on_street == 0:
		push_error("FAIL not one of %d peds stands on a street surface" % crowd.agent_count())
		return
	print(
		"footing: pavement=%d crossing=%d road=%d other=%d — %.0f%% off the carriageway"
		% [
			pavement,
			crossing,
			road,
			other,
			float(pavement + crossing) / float(on_street) * 100.0,
		]
	)
	## Corner-cutting or a stroll down the centre line are very different regressions, and only
	## the second one is unrecognisable as pedestrian behaviour.
	print(
		"of the %d in the road, %d are within %.0f m of a crossing and %d are not"
		% [road, road_near_crossing, CROSSING_REACH_M, road - road_near_crossing]
	)


## Whether any painted crossing voxel lies within `reach_m` of `at`, on the surface the ped is
## standing on.
func _crossing_within(
	terrain: VoxelTerrain, tool: VoxelTool, at: Vector3, reach_m: float
) -> bool:
	var local := terrain.to_local(at)
	var reach := ceili(reach_m / CityRoot.VOXEL_SIZE)
	var cx := floori(local.x)
	var cz := floori(local.z)
	var top := floori(local.y)
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if dx * dx + dz * dz > reach * reach:
				continue
			for y in range(top, top - 3, -1):
				var id := int(tool.get_voxel(Vector3i(cx + dx, y, cz + dz)))
				if id == VoxelMaterial.AIR:
					continue
				if id == VoxelMaterial.CROSSWALK:
					return true
				break
	return false


func _footing_tool(city: CityRoot) -> VoxelTool:
	var terrain := city.voxel_terrain()
	if terrain == null:
		push_error("FAIL the booted city has no VoxelTerrain to read footing from")
		return null
	var tool := terrain.get_voxel_tool()
	if tool == null:
		push_error("FAIL the terrain handed out no VoxelTool")
	return tool


## The solid voxel a ped's feet rest on. Their Y is the top of it, so the sample is one voxel
## down, with a little slack for a body mid-step.
func _footing_id(terrain: VoxelTerrain, tool: VoxelTool, at: Vector3) -> int:
	var local := terrain.to_local(at)
	var vx := floori(local.x)
	var vz := floori(local.z)
	var top := floori(local.y)
	for y in range(top, top - 3, -1):
		var id := int(tool.get_voxel(Vector3i(vx, y, vz)))
		if id != VoxelMaterial.AIR:
			return id
	return VoxelMaterial.AIR


func _hide_city_hud(city: CityRoot) -> void:
	for child in city.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false


## The autoloaded error panel sits over the middle of the frame. Everything it lists is also on
## stdout, so hiding it for the capture hides nothing from the reviewer.
func _hide_error_panel() -> void:
	var panel := get_tree().root.get_node_or_null("ErrorOverlay") as CanvasLayer
	if panel == null:
		push_error("FAIL no ErrorOverlay autoload to hide")
		return
	panel.visible = false


func _pin_hour(city: CityRoot) -> void:
	var cycle := city.get_node_or_null("DayNightCycle")
	if cycle == null:
		push_error("FAIL no DayNightCycle to pin")
		return
	cycle.call("set_hour", SHOT_HOUR)


## Capture whatever camera is current — for the first two shots that is the player's own.
func _shoot(path: String) -> void:
	for i in range(20):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
		return
	img.save_png(path)
	print("SAVED %s" % path)


func _shoot_from(eye: Vector3, target: Vector3, fov: float, path: String) -> void:
	var cam := Camera3D.new()
	cam.fov = fov
	cam.far = 4000.0
	add_child(cam)
	cam.global_position = eye
	cam.look_at(target, Vector3.UP)
	cam.make_current()
	await _shoot(path)
	cam.queue_free()


func _frames(count: int) -> void:
	for i in range(count):
		await get_tree().process_frame


func _wait_ms(ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
