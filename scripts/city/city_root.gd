## City POC on godot_voxel: district stamp, FPS walk, sphere dig, crowd + traffic.
class_name CityRoot
extends Node3D

const VOXEL_SIZE := 0.5
const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
const VoxelBlockLibraryScript := preload("res://scripts/city/voxel_block_library.gd")
const CrowdDirectorScript := preload("res://scripts/city/crowd_director.gd")
const VehicleDirectorScript := preload("res://scripts/vehicles/vehicle_director.gd")
const StreetPropPlacerScript := preload("res://scripts/city/street_prop_placer.gd")

@export var city_seed: int = 42
@export var crowd_count: int = 1000
@export var vehicle_count: int = 48

var _terrain: VoxelTerrain
var _tool: VoxelTool
var _preload_viewer: VoxelViewer
var _generator: DistrictGenerator
var _walker: CityWalker
var _crowd: CrowdDirector
var _vehicles: VehicleDirector
var _street_props: StreetPropPlacer
var _hud: Label
var _status: Label
var _generating: bool = false
var _hud_lod_accum: float = 0.0


func _ready() -> void:
	_generator = DistrictGenerator.new()
	_generator.size_x = 640
	_generator.size_z = 448
	_generator.size_xz = 640
	_generator.max_building_height_vox = 200
	_generator.voxel_size = VOXEL_SIZE

	_build_env()
	_build_hud()
	call_deferred("_regenerate")


func _build_env() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 40, 0)
	light.light_energy = 1.3
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 280.0
	add_child(light)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.68, 0.82)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.76, 0.85)
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.fog_enabled = true
	e.fog_light_color = Color(0.65, 0.72, 0.8)
	e.fog_density = 0.0015
	env.environment = e
	add_child(env)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 22)
	cross.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.offset_left = -8
	cross.offset_top = -14
	cross.offset_right = 8
	cross.offset_bottom = 14
	layer.add_child(cross)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 12
	panel.offset_top = 12
	panel.offset_right = 520
	panel.offset_bottom = 190
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.82)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	_hud = Label.new()
	_hud.add_theme_font_size_override("font_size", 14)
	panel.add_child(_hud)

	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_CENTER)
	_status.offset_left = -240
	_status.offset_top = -20
	_status.offset_right = 240
	_status.offset_bottom = 20
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 20)
	_status.visible = false
	layer.add_child(_status)
	_refresh_hud()


func _process(delta: float) -> void:
	if _generating:
		return
	if (_crowd == null or not is_instance_valid(_crowd)) and (
		_vehicles == null or not is_instance_valid(_vehicles)
	):
		return
	_hud_lod_accum += delta
	if _hud_lod_accum < 0.5:
		return
	_hud_lod_accum = 0.0
	_refresh_hud()


func _refresh_hud() -> void:
	var meters_x := float(_generator.size_x) * VOXEL_SIZE
	var meters_z := float(_generator.size_z) * VOXEL_SIZE
	var height_m := float(_generator.max_building_height_vox) * VOXEL_SIZE
	var lod_line := "Crowd %d" % crowd_count
	if _crowd != null and is_instance_valid(_crowd):
		var dist := _crowd.get_lod_distances()
		var tiers := _crowd.count_lod_tiers()
		lod_line = (
			"Crowd %d  ·  LOD near %.0fm / mid %.0fm  ·  skinned %d mid %d culled %d  ·  F9/F10"
			% [crowd_count, dist.x, dist.y, tiers.x, tiers.y, tiers.z]
		)
	var traffic_line := "Traffic %d" % vehicle_count
	if _vehicles != null and is_instance_valid(_vehicles):
		var vt: Vector3i = _vehicles.count_lod_tiers()
		traffic_line = "Traffic %d  ·  near %d mid %d culled %d" % [vehicle_count, vt.x, vt.y, vt.z]
	_hud.text = (
		"Street-level city POC (godot_voxel)\n"
		+ "Map ~%.0f×%.0fm  ·  towers up to %.0fm  ·  seed %d\n\n"
		% [meters_x, meters_z, height_m, city_seed]
		+ "Sidewalks + curbs · crosswalks · cars with passengers · street lights\n\n"
		+ "WASD walk  ·  Shift sprint  ·  Mouse look  ·  Wheel zoom\n"
		+ "LMB dig  ·  +/- size  ·  C character  ·  Tab free mouse  ·  R new city  ·  Esc quit\n"
		+ lod_line
		+ "\n"
		+ traffic_line
	)


func _create_terrain() -> void:
	if _terrain != null and is_instance_valid(_terrain):
		_terrain.queue_free()
		_terrain = null
		_tool = null

	_terrain = VoxelTerrain.new()
	_terrain.name = "VoxelTerrain"
	_terrain.scale = Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
	_terrain.generate_collisions = true
	_terrain.collision_layer = 1
	_terrain.collision_mask = 1
	_terrain.max_view_distance = 640
	var sx := float(_generator.size_x)
	var sz := float(_generator.size_z)
	var height := float(_generator.max_building_height_vox + 16)
	_terrain.bounds = AABB(Vector3(0, 0, 0), Vector3(sx, height, sz))

	var mesher := VoxelMesherBlocky.new()
	mesher.library = VoxelBlockLibraryScript.build()
	_terrain.mesher = mesher
	_terrain.generator = AirGeneratorScript.new()

	add_child(_terrain)
	_tool = _terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_TYPE


func _ensure_preload_viewer() -> void:
	if _preload_viewer != null and is_instance_valid(_preload_viewer):
		return
	_preload_viewer = VoxelViewer.new()
	_preload_viewer.name = "PreloadViewer"
	_preload_viewer.view_distance = 640
	_preload_viewer.requires_collisions = true
	_preload_viewer.requires_visuals = true
	add_child(_preload_viewer)
	var cx := float(_generator.size_x) * 0.5
	var cz := float(_generator.size_z) * 0.5
	var cy := float(_generator.max_building_height_vox) * 0.5
	_preload_viewer.global_position = Vector3(cx * VOXEL_SIZE, cy * VOXEL_SIZE, cz * VOXEL_SIZE)


func _wait_district_editable() -> bool:
	var size := Vector3(
		float(_generator.size_x),
		float(_generator.max_building_height_vox + 8),
		float(_generator.size_z)
	)
	var box := AABB(Vector3.ZERO, size)
	var guard := 0
	while not _tool.is_area_editable(box) and guard < 900:
		guard += 1
		if guard % 30 == 0:
			_status.text = "Loading voxels… (%d)" % guard
		await get_tree().process_frame
	return _tool.is_area_editable(box)


func _wait_area_meshed(area_vox: AABB, label: String, max_frames: int = 900) -> bool:
	var guard := 0
	while not _terrain.is_area_meshed(area_vox) and guard < max_frames:
		guard += 1
		if guard % 30 == 0:
			_status.text = "%s (%d)" % [label, guard]
		await get_tree().process_frame
	return _terrain.is_area_meshed(area_vox)


func _spawn_neighborhood_aabb(spawn_world: Vector3, radius_vox: float = 48.0) -> AABB:
	## Voxel-space box around a world spawn so we only wait on nearby collisions.
	var local := _terrain.to_local(spawn_world)
	var r := radius_vox
	var min_v := Vector3(
		maxf(local.x - r, 0.0),
		0.0,
		maxf(local.z - r, 0.0)
	)
	var max_v := Vector3(
		minf(local.x + r, float(_generator.size_x)),
		12.0,
		minf(local.z + r, float(_generator.size_z))
	)
	return AABB(min_v, max_v - min_v)


func _settle_walker_on_floor(spawn: Vector3) -> void:
	if _walker == null or not is_instance_valid(_walker):
		return
	_status.text = "Settling player…"
	var space := _walker.get_world_3d().direct_space_state
	var floor_y := spawn.y
	var found := false
	var guard := 0
	while guard < 180:
		guard += 1
		var from := spawn + Vector3(0.0, 2.0, 0.0)
		var to := spawn + Vector3(0.0, -8.0, 0.0)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1
		q.exclude = [_walker.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			floor_y = float(hit.position.y)
			found = true
			break
		await get_tree().physics_frame
	if found:
		# Capsule bottom sits ~0.1 above CharacterBody origin.
		_walker.global_position = Vector3(spawn.x, floor_y + 0.12, spawn.z)
	else:
		push_warning("CityRoot: no floor ray hit at spawn; using raised spawn Y")
		_walker.global_position = spawn
	_walker.velocity = Vector3.ZERO
	_walker.set_physics_process(true)
	# One slide frame to snap without building fall speed.
	await get_tree().physics_frame
	if is_instance_valid(_walker) and not _walker.is_on_floor():
		_walker.global_position.y += 0.5
		_walker.velocity = Vector3.ZERO


func _regenerate() -> void:
	if _generating:
		return
	_generating = true
	_status.visible = true
	_status.text = "Setting up VoxelTerrain…"
	await get_tree().process_frame

	if _walker != null and is_instance_valid(_walker):
		_walker.queue_free()
		_walker = null
	if _crowd != null and is_instance_valid(_crowd):
		_crowd.clear_crowd()
		_crowd.queue_free()
		_crowd = null
	if _vehicles != null and is_instance_valid(_vehicles):
		_vehicles.clear_vehicles()
		_vehicles.queue_free()
		_vehicles = null
	if _street_props != null and is_instance_valid(_street_props):
		_street_props.clear_props()
		_street_props.queue_free()
		_street_props = null

	_create_terrain()
	_ensure_preload_viewer()
	await get_tree().process_frame
	await get_tree().process_frame

	_status.text = "Loading voxel blocks…"
	var editable := await _wait_district_editable()
	if not editable:
		_status.text = "ERROR: district area never became editable"
		push_error("CityRoot: VoxelTool.is_area_editable failed for district bounds")
		_generating = false
		return

	_status.text = "Generating city…"
	await get_tree().process_frame
	_generator.generate(_tool, city_seed)

	var spawn := _generator.find_spawn_world(_tool)
	# Park preload viewer on the spawn so collisions stream in under the player.
	if _preload_viewer != null and is_instance_valid(_preload_viewer):
		_preload_viewer.global_position = spawn + Vector3(0.0, 8.0, 0.0)

	_status.text = "Waiting for ground collisions…"
	var spawn_area := _spawn_neighborhood_aabb(spawn, 56.0)
	var meshed := await _wait_area_meshed(spawn_area, "Meshing spawn…", 1200)
	if not meshed:
		push_warning("CityRoot: spawn neighborhood still not fully meshed; spawning anyway")

	_walker = CityWalker.new()
	_walker.name = "Walker"
	add_child(_walker)
	_walker.set_physics_process(false)
	_walker.global_position = spawn
	_walker.blast_requested.connect(_on_blast)
	var cam := _walker.get_camera()
	var player_viewer := VoxelViewer.new()
	player_viewer.name = "VoxelViewer"
	player_viewer.view_distance = 220
	player_viewer.requires_collisions = true
	cam.add_child(player_viewer)

	# Settle onto the floor once collisions exist (avoids tunneling on first frames).
	await _settle_walker_on_floor(spawn)

	var half_x := float(_generator.size_x) * VOXEL_SIZE * 0.5
	var half_z := float(_generator.size_z) * VOXEL_SIZE * 0.5
	var to := Vector3(half_x, _walker.global_position.y, half_z) - _walker.global_position
	if to.length_squared() > 0.01:
		_walker.set_yaw(atan2(-to.x, -to.z))

	_status.text = "Building pedestrian roadmap…"
	await get_tree().process_frame
	var ped_map := _generator.build_ped_roadmap(_tool, 2)
	_status.text = "Spawning crowd…"
	await get_tree().process_frame
	_crowd = CrowdDirectorScript.new()
	_crowd.name = "Crowd"
	_crowd.pedestrian_count = crowd_count
	add_child(_crowd)
	_crowd.setup(ped_map, cam, city_seed)

	_status.text = "Building car roadmap…"
	await get_tree().process_frame
	var car_map := _generator.build_car_roadmap(_tool, 2)
	_status.text = "Spawning traffic…"
	await get_tree().process_frame
	_vehicles = VehicleDirectorScript.new()
	_vehicles.name = "Traffic"
	_vehicles.vehicle_count = vehicle_count
	add_child(_vehicles)
	_vehicles.setup(car_map, cam, city_seed)

	_status.text = "Placing street lights…"
	await get_tree().process_frame
	_street_props = StreetPropPlacerScript.new()
	_street_props.name = "StreetProps"
	add_child(_street_props)
	var planner := _generator.get_planner()
	_street_props.place_from_planner(
		planner,
		_generator.cell_size,
		VOXEL_SIZE,
		_generator.ground_thickness,
		cam
	)

	_status.visible = false
	_generating = false
	_refresh_hud()


func _on_blast(hit_position: Vector3, _collider: Object, radius_m: float) -> void:
	if _tool == null or _terrain == null or _generator == null:
		return
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = VoxelMaterial.AIR
	var local := _terrain.to_local(hit_position)
	var radius_vox := maxf(radius_m, 0.25) / VOXEL_SIZE
	_tool.do_sphere(local, radius_vox)
	_restore_bedrock_floor(local, radius_vox)


func _restore_bedrock_floor(center_vox: Vector3, radius_vox: float) -> void:
	var thickness := maxi(_generator.ground_thickness, 1)
	var r := int(ceil(radius_vox)) + 1
	var min_x := clampi(int(floor(center_vox.x)) - r, 0, _generator.size_x - 1)
	var max_x := clampi(int(ceil(center_vox.x)) + r, 0, _generator.size_x - 1)
	var min_z := clampi(int(floor(center_vox.z)) - r, 0, _generator.size_z - 1)
	var max_z := clampi(int(ceil(center_vox.z)) + r, 0, _generator.size_z - 1)
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = VoxelMaterial.BEDROCK
	_tool.do_box(
		Vector3i(min_x, 0, min_z),
		Vector3i(max_x, thickness - 1, max_z)
	)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if _walker != null and _walker.is_captured():
					_walker.release_capture()
				else:
					get_tree().quit()
			KEY_TAB:
				if _walker != null:
					_walker.toggle_capture()
			KEY_R:
				city_seed = randi()
				_regenerate()
			KEY_F9:
				if _crowd != null and is_instance_valid(_crowd):
					_crowd.adjust_near_distance(-1.0)
					_refresh_hud()
			KEY_F10:
				if _crowd != null and is_instance_valid(_crowd):
					_crowd.adjust_near_distance(1.0)
					_refresh_hud()
