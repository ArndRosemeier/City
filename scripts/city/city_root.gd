## City POC on godot_voxel: district stamp, FPS walk, sphere dig, crowd + traffic.
class_name CityRoot
extends Node3D

const VOXEL_SIZE := 0.5
const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
const VoxelBlockLibraryScript := preload("res://scripts/city/voxel_block_library.gd")
const CrowdDirectorScript := preload("res://scripts/city/crowd_director.gd")
const VehicleDirectorScript := preload("res://scripts/vehicles/vehicle_director.gd")
const StreetPropPlacerScript := preload("res://scripts/city/street_prop_placer.gd")
const BuildingImpostorLodScript := preload("res://scripts/city/building_impostor_lod.gd")

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
var _building_lod: BuildingImpostorLod
var _hud: Label
var _status: Label
var _generating: bool = false
var _fps_accum: float = 0.0

## Player voxel mesh radius (2× the previous 220 default).
const PLAYER_VIEW_DISTANCE := 440


func _ready() -> void:
	_generator = DistrictGenerator.new()
	# ~14 m lots/streets; district sized so one center viewer can keep all edits loaded
	# (without a VoxelStream, unloaded blocks are regenerated as air).
	_generator.size_x = 784
	_generator.size_z = 560
	_generator.size_xz = 784
	_generator.cell_size = 28
	_generator.floor_height_vox = 6
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
	light.directional_shadow_max_distance = 420.0
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

	_hud = Label.new()
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 0.9))
	_hud.position = Vector2(16, 12)
	_hud.text = "—"
	layer.add_child(_hud)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 20)
	_status.add_theme_color_override("font_color", Color(1, 0.92, 0.55))
	_status.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_status.offset_top = -72
	_status.offset_bottom = -40
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(_status)


func _process(delta: float) -> void:
	_fps_accum += delta
	if _fps_accum < 0.25:
		return
	_fps_accum = 0.0
	if _hud != null:
		_hud.text = "%d FPS" % Engine.get_frames_per_second()


func _create_terrain() -> void:
	if _preload_viewer != null and is_instance_valid(_preload_viewer):
		_preload_viewer.queue_free()
		_preload_viewer = null
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
	# Must cover district half-diagonal so edits stay resident (no stream → unload = air).
	_terrain.max_view_distance = 512
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


func _ensure_district_anchor_viewer() -> void:
	## Permanent center viewer keeps stamped voxel *data* loaded without meshing the whole city.
	## Player viewer meshes nearby full detail; BuildingImpostorLod draws far massing.
	if _preload_viewer != null and is_instance_valid(_preload_viewer):
		_preload_viewer.queue_free()
	_preload_viewer = VoxelViewer.new()
	_preload_viewer.name = "DistrictAnchorViewer"
	_preload_viewer.view_distance = 512
	_preload_viewer.requires_visuals = false
	_preload_viewer.requires_collisions = true
	add_child(_preload_viewer)
	_preload_viewer.global_position = Vector3(
		float(_generator.size_x) * 0.5 * VOXEL_SIZE,
		float(_generator.max_building_height_vox) * 0.5 * VOXEL_SIZE,
		float(_generator.size_z) * 0.5 * VOXEL_SIZE
	)


func _wait_district_editable() -> bool:
	var size := Vector3(
		float(_generator.size_x),
		float(_generator.max_building_height_vox + 8),
		float(_generator.size_z)
	)
	var box := AABB(Vector3.ZERO, size)
	var max_frames := 3600
	var guard := 0
	while not _tool.is_area_editable(box) and guard < max_frames:
		guard += 1
		if guard % 45 == 0:
			_status.text = "Loading voxels… %d / %d" % [guard, max_frames]
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
		_walker.global_position = Vector3(spawn.x, floor_y + 0.12, spawn.z)
	else:
		push_warning("CityRoot: no floor ray hit at spawn; using raised spawn Y")
		_walker.global_position = spawn
	_walker.velocity = Vector3.ZERO
	_walker.set_physics_process(true)
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
	if _building_lod != null and is_instance_valid(_building_lod):
		_building_lod.clear()
		_building_lod.queue_free()
		_building_lod = null

	_create_terrain()
	_ensure_district_anchor_viewer()
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
	# Keep district anchor at center so distant stamped voxels are not unloaded → air.

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
	player_viewer.view_distance = PLAYER_VIEW_DISTANCE
	player_viewer.requires_collisions = true
	player_viewer.requires_visuals = true
	cam.add_child(player_viewer)

	await _settle_walker_on_floor(spawn)

	var half_x := float(_generator.size_x) * VOXEL_SIZE * 0.5
	var half_z := float(_generator.size_z) * VOXEL_SIZE * 0.5
	var to := Vector3(half_x, _walker.global_position.y, half_z) - _walker.global_position
	if to.length_squared() > 0.01:
		_walker.set_yaw(atan2(-to.x, -to.z))

	_status.text = "Building street navigation…"
	await get_tree().process_frame
	var nav_layers := _generator.build_street_nav(_tool)
	if nav_layers == null or not nav_layers.is_ready():
		push_error("CityRoot: StreetNavLayers failed — crowd/traffic disabled")
		_status.visible = false
		_generating = false
		return

	var ped_map := PedRoadMap.new()
	ped_map.bind_graph(nav_layers.ped, nav_layers)
	var car_map := CarRoadMap.new()
	car_map.bind_graph(nav_layers.road, nav_layers)

	_status.text = "Spawning crowd…"
	await get_tree().process_frame
	_crowd = CrowdDirectorScript.new()
	_crowd.name = "Crowd"
	_crowd.pedestrian_count = crowd_count
	add_child(_crowd)
	_crowd.setup(ped_map, cam, city_seed)

	_status.text = "Spawning traffic…"
	await get_tree().process_frame
	_vehicles = VehicleDirectorScript.new()
	_vehicles.name = "Traffic"
	_vehicles.vehicle_count = vehicle_count
	add_child(_vehicles)
	_vehicles.setup(car_map, cam, city_seed)
	_vehicles.bind_crowd(_crowd)

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

	_status.text = "Building far LOD…"
	await get_tree().process_frame
	_building_lod = BuildingImpostorLodScript.new()
	_building_lod.name = "BuildingImpostors"
	add_child(_building_lod)
	_building_lod.setup(cam, _generator.building_impostors, float(PLAYER_VIEW_DISTANCE) * VOXEL_SIZE)

	_status.visible = false
	_generating = false


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
	# TODO: dig-time StreetNavLayers rebuild — cars/peds still use pre-blast planner graphs.


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
			KEY_F10:
				if _crowd != null and is_instance_valid(_crowd):
					_crowd.adjust_near_distance(1.0)
