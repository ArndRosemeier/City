## City POC on godot_voxel: district stamp, FPS walk, sphere dig, crowd.
class_name CityRoot
extends Node3D

const VOXEL_SIZE := 0.5
const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
const VoxelBlockLibraryScript := preload("res://scripts/city/voxel_block_library.gd")
const CrowdDirectorScript := preload("res://scripts/city/crowd_director.gd")
const PedRoadMapScript := preload("res://scripts/city/ped_roadmap.gd")

@export var city_seed: int = 42
@export var crowd_count: int = 1000

var _terrain: VoxelTerrain
var _tool: VoxelTool
var _preload_viewer: VoxelViewer
var _generator: DistrictGenerator
var _walker: CityWalker
var _crowd: CrowdDirector
var _hud: Label
var _status: Label
var _generating: bool = false
var _hud_lod_accum: float = 0.0


func _ready() -> void:
	_generator = DistrictGenerator.new()
	_generator.size_xz = 384
	_generator.max_building_height_vox = 60
	_generator.voxel_size = VOXEL_SIZE

	_build_env()
	_build_hud()
	call_deferred("_regenerate")


func _build_env() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 40, 0)
	light.light_energy = 1.3
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 220.0
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
	e.fog_density = 0.0018
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
	panel.offset_right = 480
	panel.offset_bottom = 170
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
	if _crowd == null or not is_instance_valid(_crowd) or _generating:
		return
	_hud_lod_accum += delta
	if _hud_lod_accum < 0.5:
		return
	_hud_lod_accum = 0.0
	_refresh_hud()


func _refresh_hud() -> void:
	var meters := float(_generator.size_xz) * VOXEL_SIZE
	var lod_line := "Crowd %d" % crowd_count
	if _crowd != null and is_instance_valid(_crowd):
		var dist := _crowd.get_lod_distances()
		var tiers := _crowd.count_lod_tiers()
		lod_line = (
			"Crowd %d  ·  LOD near %.0fm / mid %.0fm  ·  skinned %d mid %d culled %d  ·  F9/F10"
			% [crowd_count, dist.x, dist.y, tiers.x, tiers.y, tiers.z]
		)
	_hud.text = (
		"Street-level city POC (godot_voxel)\n"
		+ "Map ~%.0fm  ·  towers up to 30m  ·  seed %d\n\n" % [meters, city_seed]
		+ "Plazas, parks, avenues · architectural building styles\n\n"
		+ "WASD walk  ·  Shift sprint  ·  Mouse look  ·  Wheel zoom\n"
		+ "LMB dig  ·  +/- size  ·  C character  ·  Tab free mouse  ·  R new city  ·  Esc quit\n"
		+ lod_line
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
	_terrain.max_view_distance = 512
	var half := float(_generator.size_xz)
	var height := float(_generator.max_building_height_vox + 16)
	_terrain.bounds = AABB(Vector3(0, 0, 0), Vector3(half, height, half))

	var mesher := VoxelMesherBlocky.new()
	mesher.library = VoxelBlockLibraryScript.build()
	_terrain.mesher = mesher
	# Do not set material_override — it would wipe per-block textures from the library.
	_terrain.generator = AirGeneratorScript.new()

	add_child(_terrain)
	_tool = _terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_TYPE


func _ensure_preload_viewer() -> void:
	if _preload_viewer != null and is_instance_valid(_preload_viewer):
		return
	_preload_viewer = VoxelViewer.new()
	_preload_viewer.name = "PreloadViewer"
	_preload_viewer.view_distance = 512
	_preload_viewer.requires_collisions = true
	_preload_viewer.requires_visuals = true
	add_child(_preload_viewer)
	var cx := float(_generator.size_xz) * 0.5
	var cy := float(_generator.max_building_height_vox) * 0.5
	# Viewer lives in world space; terrain is scaled by VOXEL_SIZE.
	_preload_viewer.global_position = Vector3(cx * VOXEL_SIZE, cy * VOXEL_SIZE, cx * VOXEL_SIZE)


func _wait_district_editable() -> bool:
	var size := Vector3(
		float(_generator.size_xz),
		float(_generator.max_building_height_vox + 8),
		float(_generator.size_xz)
	)
	var box := AABB(Vector3.ZERO, size)
	var guard := 0
	while not _tool.is_area_editable(box) and guard < 600:
		guard += 1
		if guard % 30 == 0:
			_status.text = "Loading voxels… (%d)" % guard
		await get_tree().process_frame
	return _tool.is_area_editable(box)


func _wait_district_meshed() -> void:
	var area := AABB(
		Vector3.ZERO,
		Vector3(float(_generator.size_xz), 8.0, float(_generator.size_xz))
	)
	var guard := 0
	while not _terrain.is_area_meshed(area) and guard < 900:
		guard += 1
		if guard % 30 == 0:
			_status.text = "Meshing… (%d)" % guard
		await get_tree().process_frame


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

	_status.text = "Waiting for meshes…"
	await _wait_district_meshed()

	_walker = CityWalker.new()
	_walker.name = "Walker"
	add_child(_walker)
	_walker.global_position = _generator.find_spawn_world(_tool)
	_walker.blast_requested.connect(_on_blast)
	# Keep a VoxelViewer on the camera so chunks stay loaded while walking.
	var cam := _walker.get_camera()
	var player_viewer := VoxelViewer.new()
	player_viewer.name = "VoxelViewer"
	player_viewer.view_distance = 192
	player_viewer.requires_collisions = true
	cam.add_child(player_viewer)

	var half := float(_generator.size_xz) * VOXEL_SIZE * 0.5
	var to := Vector3(half, _walker.global_position.y, half) - _walker.global_position
	if to.length_squared() > 0.01:
		_walker.set_yaw(atan2(-to.x, -to.z))

	_status.text = "Building pedestrian roadmap…"
	await get_tree().process_frame
	var roadmap := _generator.build_ped_roadmap(_tool, 2)
	_status.text = "Spawning crowd…"
	await get_tree().process_frame
	_crowd = CrowdDirectorScript.new()
	_crowd.name = "Crowd"
	_crowd.pedestrian_count = crowd_count
	add_child(_crowd)
	_crowd.setup(roadmap, cam, city_seed)

	_status.visible = false
	_generating = false
	_refresh_hud()


func _on_blast(hit_position: Vector3, _collider: Object, radius_m: float) -> void:
	if _tool == null or _terrain == null or _generator == null:
		return
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = VoxelMaterial.AIR
	# do_sphere uses volume/voxel space (terrain local), not world meters.
	var local := _terrain.to_local(hit_position)
	var radius_vox := maxf(radius_m, 0.25) / VOXEL_SIZE
	_tool.do_sphere(local, radius_vox)
	_restore_bedrock_floor(local, radius_vox)


func _restore_bedrock_floor(center_vox: Vector3, radius_vox: float) -> void:
	## Bottom slab stays solid so digs cannot open into the void.
	var thickness := maxi(_generator.ground_thickness, 1)
	var r := int(ceil(radius_vox)) + 1
	var min_x := clampi(int(floor(center_vox.x)) - r, 0, _generator.size_xz - 1)
	var max_x := clampi(int(ceil(center_vox.x)) + r, 0, _generator.size_xz - 1)
	var min_z := clampi(int(floor(center_vox.z)) - r, 0, _generator.size_xz - 1)
	var max_z := clampi(int(ceil(center_vox.z)) + r, 0, _generator.size_xz - 1)
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
