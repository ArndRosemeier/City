## Endless city POC: spawn-district boot, then bubble streaming with view priority.
class_name CityRoot
extends Node3D

const VOXEL_SIZE := 0.5
const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
const VoxelBlockLibraryScript := preload("res://scripts/city/voxel_block_library.gd")
const CityStreamerScript := preload("res://scripts/city/city_streamer.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")
const PlayerActionBarScript := preload("res://scripts/city/player_action_bar.gd")
const VoxelCascadeDebrisScript := preload("res://scripts/city/voxel_cascade_debris.gd")
const CityAudioScript := preload("res://scripts/city/city_audio.gd")
const BlastFlashVfxScript := preload("res://scripts/city/blast_flash_vfx.gd")

@export var city_seed: int = 42
@export var crowd_per_district: int = 96
@export var vehicles_per_district: int = 14
@export var bubble_radius_m: float = 360.0

var _terrain: VoxelTerrain
var _tool: VoxelTool
var _streamer: Node
var _walker: CityWalker
var _hud: Label
var _status: Label
var _action_bar: Node
var _debris_root: Node3D
var _cascade: Node
var _audio: Node
var _booting: bool = false
var _fps_accum: float = 0.0

## Visual mesh radius (~90 m). Collisions use a shorter viewer below.
const PLAYER_VIEW_DISTANCE := 180
const PLAYER_COLLISION_DISTANCE := 64


func _ready() -> void:
	if CityVoxelNativeScript.ensure_loaded():
		print("CityRoot: NativeOfflineVoxelVolume ready")
	else:
		print("CityRoot: using GDScript OfflineVoxelVolume fallback")
	_audio = CityAudioScript.new()
	_audio.name = "CityAudio"
	add_child(_audio)
	_build_env()
	_build_hud()
	call_deferred("_regenerate")


func _build_env() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 40, 0)
	light.light_energy = 1.3
	light.shadow_enabled = true
	## 4K + dense Blocky voxels: long cascades destroy fill-rate. Keep near-field only.
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	light.directional_shadow_max_distance = 100.0
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
	e.fog_density = 0.0022
	## Soft bloom so scale-pad emission reads clearly outdoors.
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_strength = 0.85
	e.glow_bloom = 0.12
	e.glow_hdr_threshold = 0.85
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
	## Ceiling only — must fit a district half-diagonal (~482 vox) so data-only
	## anchors can make the full tile editable. Player viewers stay shorter below.
	_terrain.max_view_distance = 512
	_terrain.generate_collisions = true
	_tool = _terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_TYPE


func _ensure_cascade_debris() -> void:
	if _debris_root == null or not is_instance_valid(_debris_root):
		_debris_root = Node3D.new()
		_debris_root.name = "DebrisRoot"
		add_child(_debris_root)
	if _cascade == null or not is_instance_valid(_cascade):
		_cascade = VoxelCascadeDebrisScript.new()
		_cascade.name = "VoxelCascadeDebris"
		add_child(_cascade)
	_cascade.setup(_terrain, _tool, _debris_root, VOXEL_SIZE)


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
	if _action_bar != null and is_instance_valid(_action_bar):
		_action_bar.queue_free()
		_action_bar = null
	if _cascade != null and is_instance_valid(_cascade):
		_cascade.clear_debris()
		_cascade.queue_free()
		_cascade = null
	if _debris_root != null and is_instance_valid(_debris_root):
		_debris_root.queue_free()
		_debris_root = null

	_create_terrain()
	_ensure_cascade_debris()
	await get_tree().process_frame
	await get_tree().process_frame

	_streamer = CityStreamerScript.new()
	_streamer.name = "CityStreamer"
	_streamer.bubble_radius_m = bubble_radius_m
	_streamer.unload_radius_m = bubble_radius_m + 140.0
	_streamer.voxel_detail_radius_m = minf(bubble_radius_m * 0.45, 140.0)
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
	_walker.melee_strike_requested.connect(_on_melee_strike)
	_walker.stomp_requested.connect(_on_stomp)
	var cam := _walker.get_camera()
	## Visuals out to ~90 m; collisions only near the player (big 4K/remesh win).
	var player_viewer := VoxelViewer.new()
	player_viewer.name = "VoxelViewer"
	player_viewer.view_distance = PLAYER_VIEW_DISTANCE
	player_viewer.requires_collisions = false
	player_viewer.requires_visuals = true
	cam.add_child(player_viewer)

	var collision_viewer := VoxelViewer.new()
	collision_viewer.name = "CollisionViewer"
	collision_viewer.view_distance = PLAYER_COLLISION_DISTANCE
	collision_viewer.requires_collisions = true
	collision_viewer.requires_visuals = false
	cam.add_child(collision_viewer)

	## Extra viewer pinned on spawn so neighborhood meshes + collisions exist
	## before the walker drops in (player camera may still be far / unset).
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
	_action_bar = PlayerActionBarScript.new()
	_action_bar.name = "PlayerActionBar"
	add_child(_action_bar)
	_action_bar.setup(_walker)
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
	_notify_destruction(hit_position, maxf(radius_m * 4.0, 28.0))


## Charged Shift bomb: carve + tumble debris, no column cascades above the hole.
func apply_charged_blast(hit_world: Vector3, radius_m: float) -> void:
	if _tool == null or _terrain == null:
		return
	var radius := maxf(radius_m, 0.35)
	var local := _terrain.to_local(hit_world)
	## Cap voxel radius so giant characters don't freeze a frame scanning hundreds of thousands of cells.
	var radius_vox := minf(radius / VOXEL_SIZE, 14.0)
	var r_i := int(ceil(radius_vox)) + 1
	var r2 := radius_vox * radius_vox
	var cx := int(floor(local.x))
	var cy := int(floor(local.y))
	var cz := int(floor(local.z))
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = VoxelMaterial.AIR
	var detached: Array = []
	const MAX_DEBRIS := 900
	for z in range(cz - r_i, cz + r_i + 1):
		for y in range(cy - r_i, cy + r_i + 1):
			for x in range(cx - r_i, cx + r_i + 1):
				var center := Vector3(float(x) + 0.5, float(y) + 0.5, float(z) + 0.5)
				if center.distance_squared_to(local) > r2 + 0.0001:
					continue
				var vox := Vector3i(x, y, z)
				var mat_id := int(_tool.get_voxel(vox))
				if not VoxelMaterial.is_destructible(mat_id):
					continue
				if detached.size() < MAX_DEBRIS:
					detached.append({"vox": vox, "mat": mat_id})
	_tool.do_sphere(local, radius_vox)
	_restore_bedrock_floor(local, radius_vox)
	if _cascade != null and _cascade.has_method("detach_blast_voxels"):
		_cascade.call("detach_blast_voxels", detached, hit_world)
	BlastFlashVfxScript.spawn(self, hit_world, radius)
	_notify_destruction(hit_world, maxf(radius * 5.0, 32.0))


## Shift+LMB stomp: clear a bowl around the feet and cascade columns above.
func _on_stomp(feet_position: Vector3, radius_m: float) -> void:
	if _tool == null or _terrain == null:
		return
	var radius := maxf(radius_m, 0.5)
	var local := _terrain.to_local(feet_position)
	var radius_vox := minf(radius / VOXEL_SIZE, 16.0)
	## Flattened bowl: full radius in XZ, shorter in Y so sidewalks crack without a deep shaft.
	var ry := maxf(radius_vox * 0.55, 1.2)
	var r_i := int(ceil(radius_vox)) + 1
	var ry_i := int(ceil(ry)) + 1
	var cx := int(floor(local.x))
	var cy := int(floor(local.y))
	var cz := int(floor(local.z))
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = VoxelMaterial.AIR
	var detached: Array = []
	var column_max_y: Dictionary = {}
	const MAX_DEBRIS := 1100
	for z in range(cz - r_i, cz + r_i + 1):
		for y in range(cy - ry_i, cy + ry_i + 1):
			for x in range(cx - r_i, cx + r_i + 1):
				var dx := (float(x) + 0.5 - local.x) / radius_vox
				var dy := (float(y) + 0.5 - local.y) / ry
				var dz := (float(z) + 0.5 - local.z) / radius_vox
				if dx * dx + dy * dy + dz * dz > 1.0001:
					continue
				var vox := Vector3i(x, y, z)
				var mat_id := int(_tool.get_voxel(vox))
				if not VoxelMaterial.is_destructible(mat_id):
					continue
				if detached.size() < MAX_DEBRIS:
					detached.append({"vox": vox, "mat": mat_id})
				_tool.do_point(vox)
				var col := Vector2i(x, z)
				if column_max_y.has(col):
					column_max_y[col] = maxi(int(column_max_y[col]), y)
				else:
					column_max_y[col] = y
	_restore_bedrock_floor(local, radius_vox)
	if _cascade != null:
		if _cascade.has_method("detach_voxels"):
			_cascade.detach_voxels(detached)
		for col_key in column_max_y.keys():
			var xz: Vector2i = col_key
			var max_y: int = int(column_max_y[col_key])
			_cascade.collapse_column_above(Vector3i(xz.x, max_y, xz.y))
	BlastFlashVfxScript.spawn(self, feet_position, radius * 0.85)
	_notify_destruction(feet_position, maxf(radius * 5.0, 36.0))


func _on_melee_strike(origin: Vector3, direction: Vector3, max_range_m: float) -> void:
	## March to the first destructible voxel, then carve a sphere whose diameter (in voxels)
	## equals character_scale. Below 0.5× the fist/foot is too small to break anything.
	if _tool == null or _terrain == null or _walker == null:
		return
	var dir := direction
	if dir.length_squared() < 0.0001:
		return
	dir = dir.normalized()
	var max_range := maxf(max_range_m, 0.05)
	var end := origin + dir * max_range
	## Pedestrians / cars take priority over voxel fabric along the same strike.
	if _apply_agent_hit(origin, end, dir):
		return
	var scale := float(_walker.get_character_scale())
	if scale < 0.5:
		return
	var local_origin := _terrain.to_local(origin)
	var max_range_vox := max_range / VOXEL_SIZE
	var step := 0.2  ## fraction of a voxel — precision over speed
	var steps := int(ceil(max_range_vox / step)) + 1
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var hit_vox := Vector3i(2147483647, 2147483647, 2147483647)
	var found := false
	for i in range(1, steps + 1):
		var p := local_origin + dir * (float(i) * step)
		var v := Vector3i(int(floor(p.x)), int(floor(p.y)), int(floor(p.z)))
		if found and v == hit_vox:
			continue
		var id := int(_tool.get_voxel(v))
		if not VoxelMaterial.is_destructible(id):
			continue
		hit_vox = v
		found = true
		break
	if not found:
		return

	## Diameter = 1 voxel per human scale → radius = scale/2.
	var radius_vox := scale * 0.5
	var hit_center := Vector3(float(hit_vox.x) + 0.5, float(hit_vox.y) + 0.5, float(hit_vox.z) + 0.5)
	var r_i := int(ceil(radius_vox))
	var r2 := radius_vox * radius_vox
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = VoxelMaterial.AIR
	## Collect destructibles in the punch sphere, then clear. Cascade must use the TOP of the
	## hole — starting from the bottom found only AIR (sphere already wiped the column).
	var detached: Array = []
	var column_max_y: Dictionary = {}  # Vector2i → int
	for z in range(hit_vox.z - r_i, hit_vox.z + r_i + 1):
		for y in range(hit_vox.y - r_i, hit_vox.y + r_i + 1):
			for x in range(hit_vox.x - r_i, hit_vox.x + r_i + 1):
				var center := Vector3(float(x) + 0.5, float(y) + 0.5, float(z) + 0.5)
				if center.distance_squared_to(hit_center) > r2 + 0.0001:
					continue
				var vox := Vector3i(x, y, z)
				var mat_id := int(_tool.get_voxel(vox))
				if not VoxelMaterial.is_destructible(mat_id):
					continue
				detached.append({"vox": vox, "mat": mat_id})
				_tool.do_point(vox)
				var col := Vector2i(x, z)
				if column_max_y.has(col):
					column_max_y[col] = maxi(int(column_max_y[col]), y)
				else:
					column_max_y[col] = y

	if _cascade == null:
		return
	## Cleared voxels become debris (already AIR in the world).
	_cascade.detach_voxels(detached)
	## Remaining destructibles above the hole tumble down per column.
	for col_key in column_max_y.keys():
		var xz: Vector2i = col_key
		var max_y: int = int(column_max_y[col_key])
		_cascade.collapse_column_above(Vector3i(xz.x, max_y, xz.y))

	var hit_world := _terrain.to_global(
		Vector3(float(hit_vox.x) + 0.5, float(hit_vox.y) + 0.5, float(hit_vox.z) + 0.5)
	)
	_notify_destruction(hit_world, 30.0 + 8.0 * scale)


func _notify_destruction(world_pos: Vector3, radius_m: float = 32.0) -> void:
	## Peds sprint and cars floor it away from the blast along their graphs.
	if _streamer == null or not _streamer.has_method("get_loaded_districts"):
		return
	var districts: Array = _streamer.call("get_loaded_districts") as Array
	for entry in districts:
		var inst: DistrictInstance = entry as DistrictInstance
		if inst == null or not is_instance_valid(inst):
			continue
		if inst.crowd != null and is_instance_valid(inst.crowd):
			inst.crowd.react_to_destruction(world_pos, radius_m)
		if inst.vehicles != null and is_instance_valid(inst.vehicles):
			inst.vehicles.react_to_destruction(world_pos, radius_m)


## Shorten a laser aim so the dart stops on the nearest ped/car before the wall.
## Prefer the camera click ray (what the player aimed at); also try eye→wall.
func resolve_laser_aim(cam_from: Vector3, wall_aim: Vector3, eye_from: Vector3) -> Vector3:
	var hit := _query_closest_agent_hit(cam_from, wall_aim)
	if hit.is_empty() and eye_from.distance_squared_to(cam_from) > 0.01:
		hit = _query_closest_agent_hit(eye_from, wall_aim)
	if hit.is_empty():
		return wall_aim
	return hit["point"] as Vector3


## True when a ped died or a car flipped along the segment (no voxel carve).
func apply_laser_agent_hit(from: Vector3, to: Vector3, direction: Vector3) -> bool:
	var dir := direction
	if dir.length_squared() < 0.0001:
		dir = (to - from)
	if dir.length_squared() < 0.0001:
		return false
	return _apply_agent_hit(from, to, dir.normalized())


## Mid-flight probe: distance along from→tip to the nearest agent, or -1.
func laser_probe_agent_distance(from: Vector3, tip: Vector3) -> float:
	var hit := _query_closest_agent_hit(from, tip)
	if hit.is_empty():
		return -1.0
	return float(hit["distance"])


func _apply_agent_hit(from: Vector3, to: Vector3, direction: Vector3) -> bool:
	var hit := _query_closest_agent_hit(from, to)
	if hit.is_empty():
		return false
	var kind: String = str(hit.get("kind", ""))
	var point: Vector3 = hit["point"] as Vector3
	var ok := false
	if kind == "ped":
		var crowd: CrowdDirector = hit["crowd"]
		var agent: PedAgent = hit["agent"]
		ok = crowd.kill_agent(agent, point, direction)
	elif kind == "vehicle":
		var vehicles: VehicleDirector = hit["vehicles"]
		var v_agent: VehicleAgent = hit["agent"]
		ok = vehicles.wreck_agent(v_agent, point, direction)
	if ok:
		_notify_destruction(point, 34.0)
	return ok


func _query_closest_agent_hit(from: Vector3, to: Vector3) -> Dictionary:
	if _streamer == null or not _streamer.has_method("get_loaded_districts"):
		return {}
	var best: Dictionary = {}
	var best_dist := INF
	var districts: Array = _streamer.call("get_loaded_districts") as Array
	for entry in districts:
		var inst: DistrictInstance = entry as DistrictInstance
		if inst == null or not is_instance_valid(inst):
			continue
		## Crowd/traffic exist only after full bake (far tiles skip them).
		if inst.crowd != null and is_instance_valid(inst.crowd):
			var ped_hit: Dictionary = inst.crowd.query_segment_hit(from, to)
			if not ped_hit.is_empty():
				var d: float = float(ped_hit["distance"])
				if d < best_dist:
					best_dist = d
					best = ped_hit.duplicate()
					best["kind"] = "ped"
					best["crowd"] = inst.crowd
		if inst.vehicles != null and is_instance_valid(inst.vehicles):
			var car_hit: Dictionary = inst.vehicles.query_segment_hit(from, to)
			if not car_hit.is_empty():
				var d2: float = float(car_hit["distance"])
				if d2 < best_dist:
					best_dist = d2
					best = car_hit.duplicate()
					best["kind"] = "vehicle"
					best["vehicles"] = inst.vehicles
	return best


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
				get_tree().quit()
