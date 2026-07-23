## Endless city POC: spawn-district boot, then bubble streaming with view priority.
class_name CityRoot
extends Node3D

const VOXEL_SIZE := 0.5
const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
const VoxelBlockLibraryScript := preload("res://scripts/city/voxel_block_library.gd")
const CityStreamerScript := preload("res://scripts/city/city_streamer.gd")
const CityDebugHudScript := preload("res://scripts/city/city_debug_hud.gd")

@export var city_seed: int = 42
@export var crowd_per_district: int = 48
@export var vehicles_per_district: int = 6
@export var bubble_radius_m: float = 460.0

var _terrain: VoxelTerrain
var _tool: VoxelTool
var _streamer: Node
var _walker: CityWalker
var _hud: Label
var _status: Label
var _debug_hud: Node
var _booting: bool = false
var _fps_accum: float = 0.0

const PLAYER_VIEW_DISTANCE := 280


func _ready() -> void:
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
		var extra := ""
		if _streamer != null:
			extra = "  ·  districts %d" % int(_streamer.call("district_count"))
		_hud.text = "%d FPS%s" % [Engine.get_frames_per_second(), extra]


func _create_terrain() -> void:
	if _terrain != null and is_instance_valid(_terrain):
		_terrain.queue_free()
		_terrain = null
		_tool = null

	_terrain = VoxelTerrain.new()
	_terrain.name = "VoxelTerrain"
	add_child(_terrain)
	_terrain.scale = Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)

	var mesher := VoxelMesherBlocky.new()
	mesher.library = VoxelBlockLibraryScript.build()
	_terrain.mesher = mesher
	_terrain.generator = AirGeneratorScript.new()
	## No VoxelStreamMemory — modified blocks exist only while a VoxelViewer holds them.
	## Leaving the bubble drops the district anchor → data is discarded (and regenerated
	## from the deterministic district seed if you return). Storing every visited tile
	## forever was the multi‑GB leak.
	## Soft large bounds — streamer loads tiles inside the bubble.
	_terrain.bounds = AABB(Vector3(-20000, 0, -20000), Vector3(40000, 220, 40000))
	## VoxelTerrain clamps viewers to this (internal practical cap ~512).
	_terrain.max_view_distance = 512
	_terrain.generate_collisions = true
	_tool = _terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_TYPE


func _regenerate() -> void:
	if _booting:
		return
	_booting = true
	_status.visible = true
	_status.text = "Setting up VoxelTerrain…"
	await get_tree().process_frame

	if _walker != null and is_instance_valid(_walker):
		_walker.queue_free()
		_walker = null
	if _streamer != null and is_instance_valid(_streamer):
		_streamer.call("clear_all")
		_streamer.queue_free()
		_streamer = null
	if _debug_hud != null and is_instance_valid(_debug_hud):
		_debug_hud.queue_free()
		_debug_hud = null

	_create_terrain()
	await get_tree().process_frame
	await get_tree().process_frame

	_streamer = CityStreamerScript.new()
	_streamer.name = "CityStreamer"
	_streamer.bubble_radius_m = bubble_radius_m
	_streamer.unload_radius_m = bubble_radius_m + 180.0
	_streamer.crowd_per_district = crowd_per_district
	_streamer.vehicles_per_district = vehicles_per_district
	add_child(_streamer)
	_streamer.setup(
		_terrain,
		_tool,
		city_seed,
		VOXEL_SIZE,
		float(PLAYER_VIEW_DISTANCE) * VOXEL_SIZE
	)
	_streamer.status_message.connect(_on_streamer_status)
	_streamer.spawn_district_ready.connect(_on_spawn_district_ready)

	_debug_hud = CityDebugHudScript.new()
	_debug_hud.name = "CityDebugHud"
	add_child(_debug_hud)
	_debug_hud.setup(_streamer, _terrain)

	_status.text = "Generating spawn district…"
	_streamer.boot_spawn_district(Vector2i.ZERO)


func _on_streamer_status(text: String) -> void:
	if _status != null and _status.visible:
		_status.text = text


func _on_spawn_district_ready(inst: Node) -> void:
	if inst == null or not inst.get("generator"):
		_status.text = "ERROR: spawn district missing generator"
		_booting = false
		return
	_status.text = "Finding spawn…"
	var gen: DistrictGenerator = inst.generator
	var spawn: Vector3 = gen.find_spawn_world(_tool)
	## Verify stamped ground exists under spawn (voxel data, not just mesh flag).
	if not _has_solid_ground_at(spawn):
		_status.text = "Waiting for stamped ground…"
		var gguard := 0
		while not _has_solid_ground_at(spawn) and gguard < 600:
			gguard += 1
			await get_tree().process_frame
		spawn = gen.find_spawn_world(_tool)

	_status.text = "Spawning player…"
	_walker = CityWalker.new()
	_walker.name = "Walker"
	add_child(_walker)
	_walker.set_physics_process(false)
	## Hold above until collision exists — never enable physics in the void.
	_walker.global_position = spawn + Vector3(0.0, 6.0, 0.0)
	_walker.blast_requested.connect(_on_blast)
	var cam := _walker.get_camera()
	var player_viewer := VoxelViewer.new()
	player_viewer.name = "VoxelViewer"
	player_viewer.view_distance = PLAYER_VIEW_DISTANCE
	player_viewer.requires_collisions = true
	player_viewer.requires_visuals = true
	cam.add_child(player_viewer)

	## Extra collision viewer pinned on spawn so the neighborhood is forced resident.
	var spawn_viewer := VoxelViewer.new()
	spawn_viewer.name = "SpawnCollisionViewer"
	spawn_viewer.view_distance = 96
	spawn_viewer.requires_collisions = true
	spawn_viewer.requires_visuals = true
	add_child(spawn_viewer)
	spawn_viewer.global_position = spawn + Vector3(0.0, 2.0, 0.0)

	_streamer.call("bind_player", _walker, cam)

	_status.text = "Waiting for ground collisions…"
	var floor_y := await _wait_floor_collision(spawn, 2400)
	if is_nan(floor_y):
		_status.text = "ERROR: no ground collision at spawn"
		push_error("CityRoot: floor ray never hit — refusing to enable walker physics")
		_booting = false
		return

	_walker.global_position = Vector3(spawn.x, floor_y + 0.15, spawn.z)
	_walker.velocity = Vector3.ZERO
	_walker.set_physics_process(true)
	await get_tree().physics_frame
	if is_instance_valid(_walker) and not _walker.is_on_floor():
		_walker.global_position.y += 0.4
		_walker.velocity = Vector3.ZERO

	if is_instance_valid(spawn_viewer):
		spawn_viewer.queue_free()

	var look: Vector3 = inst.call("world_aabb_center") - _walker.global_position
	look.y = 0.0
	if look.length_squared() > 0.01:
		_walker.set_yaw(atan2(-look.x, -look.z))

	_status.visible = false
	_booting = false
	print("CityRoot: playable — endless stream active at y=%.2f" % floor_y)


func _has_solid_ground_at(world: Vector3) -> bool:
	if _tool == null:
		return false
	var vx := int(floor(world.x / VOXEL_SIZE))
	var vz := int(floor(world.z / VOXEL_SIZE))
	for y in range(0, 8):
		var mat := int(_tool.get_voxel(Vector3i(vx, y, vz)))
		if mat != VoxelMaterial.AIR and VoxelMaterial.is_solid(mat):
			return true
	return false


func _wait_floor_collision(spawn: Vector3, max_frames: int = 1800) -> float:
	## Returns floor Y, or NAN if never found. Physics stays disabled until this succeeds.
	var guard := 0
	while guard < max_frames:
		guard += 1
		if _walker == null or not is_instance_valid(_walker):
			return NAN
		var space := _walker.get_world_3d().direct_space_state
		var from := spawn + Vector3(0.0, 8.0, 0.0)
		var to := spawn + Vector3(0.0, -20.0, 0.0)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1
		q.exclude = [_walker.get_rid()]
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			return float(hit.position.y)
		if guard % 45 == 0 and _status != null:
			_status.text = "Waiting for ground collisions… (%d)" % guard
		await get_tree().physics_frame
	return NAN


func _wait_area_meshed(area_vox: AABB, label: String, max_frames: int = 900) -> bool:
	var guard := 0
	while not _terrain.is_area_meshed(area_vox) and guard < max_frames:
		guard += 1
		if guard % 30 == 0 and _status != null:
			_status.text = "%s (%d)" % [label, guard]
		await get_tree().process_frame
	return _terrain.is_area_meshed(area_vox)


func _spawn_neighborhood_aabb(spawn_world: Vector3, radius_vox: float = 48.0) -> AABB:
	var local := _terrain.to_local(spawn_world)
	var r := radius_vox
	return AABB(
		Vector3(local.x - r, 0.0, local.z - r),
		Vector3(r * 2.0, 12.0, r * 2.0)
	)


func _on_blast(hit_position: Vector3, _collider: Object, radius_m: float) -> void:
	if _tool == null or _terrain == null:
		return
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = VoxelMaterial.AIR
	var local := _terrain.to_local(hit_position)
	var radius_vox := maxf(radius_m, 0.25) / VOXEL_SIZE
	_tool.do_sphere(local, radius_vox)
	_restore_bedrock_floor(local, radius_vox)


func _restore_bedrock_floor(center_vox: Vector3, radius_vox: float) -> void:
	var thickness := 1
	var r := int(ceil(radius_vox)) + 1
	var cx := int(floor(center_vox.x))
	var cz := int(floor(center_vox.z))
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = VoxelMaterial.BEDROCK
	for z in range(cz - r, cz + r + 1):
		for x in range(cx - r, cx + r + 1):
			var dx := float(x) + 0.5 - center_vox.x
			var dz := float(z) + 0.5 - center_vox.z
			if dx * dx + dz * dz > radius_vox * radius_vox:
				continue
			for y in range(0, thickness):
				_tool.do_point(Vector3i(x, y, z))


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
