## Endless city POC: spawn-district boot, then bubble streaming with view priority.
class_name CityRoot
extends Node3D

const VOXEL_SIZE := 0.5
const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
const VoxelBlockLibraryScript := preload("res://scripts/city/voxel_block_library.gd")
const CityWalkerScript := preload("res://scripts/city/city_walker.gd")
const DistrictInstanceScript := preload("res://scripts/city/district_instance.gd")
const CityStreamerScript := preload("res://scripts/city/city_streamer.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")
const PlayerActionBarScript := preload("res://scripts/city/player_action_bar.gd")
const PlayerEnergyHudScript := preload("res://scripts/city/player_energy_hud.gd")
const CityAudioScript := preload("res://scripts/city/city_audio.gd")
const BlastFlashVfxScript := preload("res://scripts/city/blast_flash_vfx.gd")
const DayNightCycleScript := preload("res://scripts/city/day_night_cycle.gd")
const CitySettingsPanelScript := preload("res://scripts/city/city_settings_panel.gd")
const InfectionDirectorScript := preload("res://scripts/city/infection_director.gd")
const InfectionMeteorScript := preload("res://scripts/city/infection_meteor.gd")
const InfectionTendrilHudScript := preload("res://scripts/city/infection_tendril_hud.gd")
const UndeadInvasionDirectorScript := preload("res://scripts/city/undead_invasion_director.gd")
const UndeadInvasionHudScript := preload("res://scripts/city/undead_invasion_hud.gd")
const CityMinimapScript := preload("res://scripts/city/city_minimap.gd")
const TetrisMachineScript := preload("res://scripts/city/tetris_machine.gd")
const TetrisPedNpcScript := preload("res://scripts/city/tetris_ped_npc.gd")
const BuildCatalogScript := preload("res://scripts/city/build_catalog.gd")
const BuildPlacerScript := preload("res://scripts/city/build_placer.gd")
const LoadingSplashScript := preload("res://scripts/city/loading_splash.gd")

## Sentinel for city_seed: draw a fresh world seed when the game starts.
const SEED_RANDOM := 0
## How far from the world origin (in district tiles) the player may spawn.
const SPAWN_DISTRICT_RING := 3
## District layouts hang off this seed plus the district's grid coordinate. Left at
## SEED_RANDOM every launch builds a different world; set a concrete value (in the
## scene, from code, or with --city-seed=N) to replay one exactly.
@export var city_seed: int = SEED_RANDOM
@export var crowd_per_district: int = 96
@export var vehicles_per_district: int = 14
@export var bubble_radius_m: float = 360.0
## Real-time seconds for a full 24h cycle.
@export var day_length_sec: float = 420.0
## District tile the player boots into. Filled at regenerate from the world seed
## (or --spawn-district=x,z / --spawn-theme=…); tools can read it after boot.
var spawn_district_coord: Vector2i = Vector2i.ZERO
## Theme chosen on the start modal (or via --spawn-theme). -1 = unset / random.
var spawn_theme_id: int = -1

var _terrain: VoxelTerrain
var _tool: VoxelTool
var _streamer: Node
## Typed as CharacterBody3D so portable installs work before global class_name cache exists.
var _walker: CharacterBody3D
var _hud: Label
var _hud_layer: CanvasLayer
var _status: Label
var _loading_splash: CanvasLayer
var _action_bar: Node
var _energy_hud: Node
var _debris_root: Node3D
var _cascade: Node
var _infection: Node
var _tendril_hud: Node
var _undead_hud: Node
var _minimap: Node
var _tetris: Node3D
var _tetris_peds: Array[Node3D] = []
var _game_over_layer: CanvasLayer
var _game_over_title: Label
var _game_over_detail: Label
## Per-meteor crater sites: rock stays immune + purple beam until that site's tendrils end.
var _meteor_sites: Dictionary = {}  # site_id → {tendrils, beam, impact_vox}
var _tendril_to_meteor_site: Dictionary = {}  # tendril_id → site_id
var _next_meteor_site_id: int = 1
var _spawn_meteors_enabled: bool = false
var _meteor_spawn_accum: float = 0.0
var _meteor_spawn_interval_sec: float = 120.0
var _undead_invasion_enabled: bool = false
var _undead: Node
var _player_score: int = 0
var _game_over: bool = false
var _radar_cooldown_left: float = 0.0
var _radar_reveal_left: float = 0.0
const RADAR_COOLDOWN_SEC := 30.0
## How long all undead stay painted on the minimap after U.
const RADAR_REVEAL_SEC := 12.0
var _audio: Node
var _day_night: Node
var _settings_panel: Node
var _world_env: WorldEnvironment
var _sun: DirectionalLight3D
var _player_viewer: VoxelViewer
var _collision_viewer: VoxelViewer
var _booting: bool = false
var _district_hopping: bool = false
var _fps_accum: float = 0.0
var _infection_stream_accum: float = 0.0
var _street_night_factor: float = 0.0

## Visual mesh radius (~90 m at default). Collisions use a shorter viewer below.
var _voxel_view_vox: int = 100
var _collision_view_vox: int = 48


func _ready() -> void:
	add_to_group("city_root")
	CityVoxelNativeScript.require_loaded()
	print("CityRoot: city_voxel native ready (volume + cascade debris)")
	_resolve_seed()
	_audio = CityAudioScript.new()
	_audio.name = "CityAudio"
	add_child(_audio)
	_build_env()
	_build_hud()
	call_deferred("_regenerate")


func _resolve_seed() -> void:
	## Runs once per launch, before any district is baked: every generator downstream
	## mixes this with the district coordinate, so the whole world follows from it.
	var cli := _cli_int_flag("--city-seed=")
	if cli != SEED_RANDOM:
		city_seed = cli
	if city_seed == SEED_RANDOM:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		city_seed = maxi(rng.randi() & 0x7fffffff, 1)
	print("CityRoot: world seed %d (replay with --city-seed=%d)" % [city_seed, city_seed])


func _cli_int_flag(flag: String) -> int:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for a: String in args:
		if not a.begins_with(flag):
			continue
		var raw := a.substr(flag.length())
		if not raw.is_valid_int():
			push_error("CityRoot: %s%s is not an integer" % [flag, raw])
			return SEED_RANDOM
		return int(raw)
	return SEED_RANDOM


func _cli_spawn_district() -> Variant:
	## Returns Vector2i when --spawn-district=x,z is present, otherwise null.
	const FLAG := "--spawn-district="
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for a: String in args:
		if not a.begins_with(FLAG):
			continue
		var raw := a.substr(FLAG.length())
		var parts := raw.split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			push_error("CityRoot: %s expects x,z integers (got %s)" % [FLAG, raw])
			return null
		return Vector2i(int(parts[0]), int(parts[1]))
	return null


func _cli_spawn_theme() -> int:
	## Returns a DistrictTheme id when --spawn-theme=… is present, otherwise -1.
	const FLAG := "--spawn-theme="
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for a: String in args:
		if not a.begins_with(FLAG):
			continue
		return DistrictTheme.parse_theme_id(a.substr(FLAG.length()))
	return -1


func _should_show_spawn_picker() -> bool:
	## Tools that `add_child(CityRoot.new())` skip the modal; the main scene shows it.
	## CLI overrides and headless runs also skip.
	if _cli_spawn_district() is Vector2i:
		return false
	if _cli_spawn_theme() >= 0:
		return false
	if DisplayServer.get_name() == "headless":
		return false
	var tree := get_tree()
	if tree == null:
		return false
	return tree.current_scene == self or get_parent() == tree.root


func _pick_spawn_district_random() -> Vector2i:
	## Stable for a given world seed so --city-seed=N also replays the spawn tile.
	var rng := RandomNumberGenerator.new()
	rng.seed = DistrictCoord.feature_seed(city_seed, 0x53504E)  ## "SPN"
	return Vector2i(
		rng.randi_range(-SPAWN_DISTRICT_RING, SPAWN_DISTRICT_RING),
		rng.randi_range(-SPAWN_DISTRICT_RING, SPAWN_DISTRICT_RING)
	)


## Resolves the spawn tile: CLI coord, theme search (modal / --spawn-theme), or RNG.
func _resolve_spawn_district() -> Vector2i:
	var forced: Variant = _cli_spawn_district()
	if forced is Vector2i:
		spawn_theme_id = DistrictTheme.for_district(city_seed, forced as Vector2i).id
		return forced as Vector2i

	var theme_id := _cli_spawn_theme()
	if theme_id < 0 and _should_show_spawn_picker():
		if _loading_splash == null:
			push_error("CityRoot: spawn picker requested but LoadingSplash is missing")
		else:
			_loading_splash.call("show_splash", "Choose a starting district")
			theme_id = int(await _loading_splash.call("prompt_district_choice"))
	if theme_id >= 0:
		spawn_theme_id = theme_id
		var coord := DistrictTheme.find_coord_for_theme(city_seed, theme_id)
		var found := DistrictTheme.for_district(city_seed, coord)
		if found.id != theme_id:
			push_error(
				"CityRoot: theme search returned %s for requested %s"
				% [found.display_name, DistrictTheme.make(theme_id).display_name]
			)
		return coord

	var random_coord := _pick_spawn_district_random()
	spawn_theme_id = DistrictTheme.for_district(city_seed, random_coord).id
	return random_coord


func _build_env() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.rotation_degrees = Vector3(-50, 40, 0)
	_sun.light_energy = 1.3
	_sun.light_color = Color(1.0, 0.96, 0.88)
	_sun.shadow_enabled = true
	_configure_sun_shadows(_sun, 120.0)
	add_child(_sun)

	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.62, 0.72, 1.0)
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	moon.visible = false
	add_child(moon)

	var sky_shader: Shader = load("res://assets/city/shaders/city_sky.gdshader") as Shader
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sky_shader
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	_world_env = WorldEnvironment.new()
	_world_env.name = "WorldEnvironment"
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_color = Color(0.72, 0.76, 0.85)
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.0
	e.fog_enabled = true
	e.fog_light_color = Color(0.65, 0.72, 0.8)
	e.fog_density = 0.0016
	## Keep fog off the sky so clouds/stars stay visible.
	e.fog_sky_affect = 0.0
	e.fog_aerial_perspective = 0.0
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_strength = 0.85
	e.glow_bloom = 0.12
	e.glow_hdr_threshold = 0.85
	## Soft contact shadowing so Blocky walls stop reading flat.
	e.ssao_enabled = true
	e.ssao_radius = 1.4
	e.ssao_intensity = 1.6
	e.ssao_power = 1.5
	_world_env.environment = e
	add_child(_world_env)

	_day_night = DayNightCycleScript.new()
	_day_night.name = "DayNightCycle"
	_day_night.day_length_sec = day_length_sec
	add_child(_day_night)
	_day_night.call("setup", _sun, moon, e, sky_mat)
	if _day_night.has_signal("night_factor_changed"):
		_day_night.connect("night_factor_changed", _on_night_factor_changed)
	if _day_night.has_method("get_night_factor"):
		_on_night_factor_changed(float(_day_night.call("get_night_factor")))


## Tuned for 0.5 m Blocky voxels (facades, eaves, leaf cards). Default Godot
## bias + hard cascade splits shimmer badly as the camera / sun moves.
func _configure_sun_shadows(sun: DirectionalLight3D, max_distance_m: float) -> void:
	if sun == null:
		return
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = max_distance_m
	## Pull the first split out a bit so near streets keep more texels.
	sun.directional_shadow_split_1 = 0.22
	## Prefer normal bias on cubes / thin foliage; plain bias alone peter-pans eaves.
	sun.shadow_bias = 0.14
	sun.shadow_normal_bias = 2.4
	## Blur 0 triggers acne (engine auto-bias floor). Soften slightly.
	sun.shadow_blur = 0.75
	sun.directional_shadow_pancake_size = 8.0


func is_settings_open() -> bool:
	return _settings_panel != null and bool(_settings_panel.call("is_open"))


func _as_district_instance(entry: Variant) -> Variant:
	## Resolve without relying on global class_name cache (portable installs).
	if entry == null or not is_instance_valid(entry):
		return null
	if not (entry is Node):
		return null
	var node := entry as Node
	if node.get_script() != DistrictInstanceScript:
		return null
	return entry


func _on_night_factor_changed(night_factor: float) -> void:
	_street_night_factor = clampf(night_factor, 0.0, 1.0)
	VoxelBlockLibraryScript.set_glass_lit_night_factor(_street_night_factor)
	_push_night_factor_to_street_lights()


func _push_night_factor_to_street_lights() -> void:
	if _streamer == null or not _streamer.has_method("get_loaded_districts"):
		return
	var districts: Array = _streamer.call("get_loaded_districts") as Array
	for entry in districts:
		var inst = _as_district_instance(entry)
		if inst == null:
			continue
		if inst.street_props != null and is_instance_valid(inst.street_props):
			if inst.street_props.has_method("set_night_factor"):
				inst.street_props.call("set_night_factor", _street_night_factor)
		if inst.building_lod != null and is_instance_valid(inst.building_lod):
			if inst.building_lod.has_method("set_night_factor"):
				inst.building_lod.call("set_night_factor", _street_night_factor)


func _build_hud() -> void:
	_loading_splash = LoadingSplashScript.new()
	add_child(_loading_splash)
	_status = _loading_splash.call("status_label") as Label
	_loading_splash.call("show_splash", "Choose a starting district")

	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "HudLayer"
	## Hidden until the spawn district is playable — the title splash owns the screen.
	_hud_layer.visible = false
	add_child(_hud_layer)

	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 22)
	cross.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.offset_left = -8
	cross.offset_top = -14
	cross.offset_right = 8
	cross.offset_bottom = 14
	_hud_layer.add_child(cross)

	_hud = Label.new()
	_hud.add_theme_font_size_override("font_size", 18)
	_hud.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 0.9))
	_hud.position = Vector2(16, 12)
	_hud.text = "—"
	_hud_layer.add_child(_hud)

	_tendril_hud = InfectionTendrilHudScript.new()
	_tendril_hud.name = "InfectionTendrilHud"
	add_child(_tendril_hud)

	_energy_hud = PlayerEnergyHudScript.new()
	_energy_hud.name = "PlayerEnergyHud"
	add_child(_energy_hud)

	_undead_hud = UndeadInvasionHudScript.new()
	_undead_hud.name = "UndeadInvasionHud"
	add_child(_undead_hud)

	_minimap = CityMinimapScript.new()
	_minimap.name = "CityMinimap"
	add_child(_minimap)
	_minimap.call("bind_city", self)

	_build_game_over_overlay()

	_settings_panel = CitySettingsPanelScript.new()
	_settings_panel.name = "CitySettings"
	add_child(_settings_panel)
	_settings_panel.settings_applied.connect(_on_settings_applied)
	_settings_panel.opened.connect(_on_settings_opened)
	_settings_panel.closed.connect(_on_settings_closed)
	if _settings_panel.has_signal("controls_changed"):
		_settings_panel.controls_changed.connect(_on_controls_changed)
	if _settings_panel.has_signal("spawn_meteors_toggled"):
		_settings_panel.spawn_meteors_toggled.connect(_on_spawn_meteors_toggled)
	if _settings_panel.has_signal("undead_invasion_toggled"):
		_settings_panel.undead_invasion_toggled.connect(_on_undead_invasion_toggled)
	## Apply saved / default knobs once the viewport exists.
	call_deferred("_on_settings_applied", _settings_panel.get_settings())
	call_deferred("_apply_saved_controls")


func _build_game_over_overlay() -> void:
	_game_over_layer = CanvasLayer.new()
	_game_over_layer.name = "GameOverOverlay"
	_game_over_layer.layer = 40
	_game_over_layer.visible = false
	add_child(_game_over_layer)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.01, 0.04, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_game_over_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_game_over_layer.add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	_game_over_title = Label.new()
	_game_over_title.text = "GAME OVER"
	_game_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_title.add_theme_font_size_override("font_size", 64)
	_game_over_title.add_theme_color_override("font_color", Color(1.0, 0.35, 0.32))
	_game_over_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_game_over_title.add_theme_constant_override("outline_size", 8)
	box.add_child(_game_over_title)

	_game_over_detail = Label.new()
	_game_over_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_detail.add_theme_font_size_override("font_size", 22)
	_game_over_detail.add_theme_color_override("font_color", Color(0.95, 0.95, 0.92))
	_game_over_detail.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_game_over_detail.add_theme_constant_override("outline_size", 4)
	box.add_child(_game_over_detail)

	var hint := Label.new()
	hint.text = "Press Enter to retry"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color(0.75, 0.95, 0.85))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	hint.add_theme_constant_override("outline_size", 3)
	box.add_child(hint)


func _on_spawn_meteors_toggled(enabled: bool) -> void:
	_spawn_meteors_enabled = enabled
	if enabled:
		_meteor_spawn_accum = 0.0
		_try_auto_spawn_meteor()
		_roll_meteor_spawn_interval()
		print("CityRoot: auto meteor spawns ON (next in %.0fs)" % _meteor_spawn_interval_sec)
	else:
		_meteor_spawn_accum = 0.0
		print("CityRoot: auto meteor spawns OFF")


func _on_undead_invasion_toggled(enabled: bool) -> void:
	_undead_invasion_enabled = enabled
	_ensure_undead_director()
	if _undead != null and _undead.has_method("set_enabled"):
		_undead.call("set_enabled", enabled)
	if _undead_hud != null and is_instance_valid(_undead_hud):
		if enabled:
			_undead_hud.call("bind_director", _undead)
		else:
			_undead_hud.call("clear_display")


func _roll_meteor_spawn_interval() -> void:
	## Random 1–3 minutes between auto impacts.
	_meteor_spawn_interval_sec = randf_range(60.0, 180.0)

func _on_settings_opened() -> void:
	if _walker != null and is_instance_valid(_walker):
		_walker.release_capture()


func _on_settings_closed() -> void:
	if _walker != null and is_instance_valid(_walker):
		_walker._set_capture(true)


func _apply_saved_controls() -> void:
	if _settings_panel != null and _settings_panel.has_method("get_player_controls"):
		_on_controls_changed(_settings_panel.call("get_player_controls"))


func _on_controls_changed(controls: Variant) -> void:
	if controls == null:
		return
	if _walker != null and is_instance_valid(_walker) and _walker.has_method("set_controls"):
		_walker.call("set_controls", controls)
	if _action_bar != null and is_instance_valid(_action_bar) and _action_bar.has_method("set_controls"):
		_action_bar.call("set_controls", controls)
	var profiler := get_tree().root.get_node_or_null("CityProfiler")
	if profiler != null and profiler.has_method("set_controls"):
		profiler.call("set_controls", controls)


func _on_settings_applied(settings: Dictionary) -> void:
	var scale := clampf(float(settings.get("render_scale", 0.75)), 0.45, 1.0)
	get_viewport().scaling_3d_scale = scale

	if _world_env != null and _world_env.environment != null:
		var e := _world_env.environment
		e.ssao_enabled = bool(settings.get("ssao", true))
		e.glow_enabled = bool(settings.get("glow", true))
		e.fog_enabled = bool(settings.get("fog", true))

	if _sun != null:
		_sun.shadow_enabled = bool(settings.get("shadows", true))
		_configure_sun_shadows(
			_sun, clampf(float(settings.get("shadow_distance_m", 120.0)), 40.0, 220.0)
		)

	_voxel_view_vox = clampi(int(settings.get("voxel_view_vox", 100)), 80, 280)
	_collision_view_vox = clampi(int(settings.get("collision_view_vox", 48)), 32, 128)
	if _player_viewer != null and is_instance_valid(_player_viewer):
		_player_viewer.view_distance = _voxel_view_vox
	if _collision_viewer != null and is_instance_valid(_collision_viewer):
		_collision_viewer.view_distance = _collision_view_vox

	bubble_radius_m = clampf(float(settings.get("bubble_radius_m", 360.0)), 180.0, 520.0)
	if _streamer != null and is_instance_valid(_streamer):
		_streamer.bubble_radius_m = bubble_radius_m
		_streamer.unload_radius_m = bubble_radius_m + 140.0
		_streamer.voxel_detail_radius_m = minf(bubble_radius_m * 0.45, 140.0)
		_streamer.player_view_m = float(_voxel_view_vox) * VOXEL_SIZE

	var crowd_m := clampf(float(settings.get("crowd_render_m", 70.0)), 20.0, 160.0)
	var vehicle_m := clampf(float(settings.get("vehicle_render_m", 120.0)), 40.0, 220.0)
	var omni := clampi(int(settings.get("max_omni_lights", 12)), 0, 24)
	_apply_district_runtime_budgets(crowd_m, vehicle_m, omni)


func _apply_district_runtime_budgets(crowd_m: float, vehicle_m: float, omni: int) -> void:
	if _streamer == null or not _streamer.has_method("get_loaded_districts"):
		return
	var districts: Array = _streamer.call("get_loaded_districts") as Array
	for entry in districts:
		var inst = _as_district_instance(entry)
		if inst == null or not is_instance_valid(inst):
			continue
		if inst.crowd != null and is_instance_valid(inst.crowd):
			inst.crowd.render_distance = crowd_m
			if inst.crowd.has_method("_refresh_lod"):
				inst.crowd.call("_refresh_lod", true)
		if inst.vehicles != null and is_instance_valid(inst.vehicles):
			inst.vehicles.render_distance = vehicle_m
		if inst.street_props != null and is_instance_valid(inst.street_props):
			inst.street_props.max_omni_lights = omni
			if inst.street_props.has_method("_refresh_lights"):
				inst.street_props.call("_refresh_lights", true)


func _process(delta: float) -> void:
	_fps_accum += delta
	_infection_stream_accum += delta
	if _radar_cooldown_left > 0.0:
		_radar_cooldown_left = maxf(0.0, _radar_cooldown_left - delta)
	if _radar_reveal_left > 0.0:
		_radar_reveal_left = maxf(0.0, _radar_reveal_left - delta)
	if _infection_stream_accum >= 0.5:
		_infection_stream_accum = 0.0
		_invalidate_infection_outside_bubble()
	if _spawn_meteors_enabled and _walker != null and is_instance_valid(_walker):
		_meteor_spawn_accum += delta
		if _meteor_spawn_accum >= _meteor_spawn_interval_sec:
			_meteor_spawn_accum = 0.0
			_roll_meteor_spawn_interval()
			_try_auto_spawn_meteor()
	if _fps_accum < 0.25:
		return
	_fps_accum = 0.0
	if _hud != null:
		var clock := ""
		if _day_night != null and _day_night.has_method("get_hour"):
			var h := float(_day_night.call("get_hour"))
			var hh := int(floor(h)) % 24
			var mm := int(floor(fposmod(h, 1.0) * 60.0))
			clock = "  %02d:%02d" % [hh, mm]
		var score := _player_score
		if _infection != null and is_instance_valid(_infection) and _infection.has_method("get_player_score"):
			score = int(_infection.call("get_player_score"))
			_player_score = score
		var radar := ""
		if _radar_reveal_left > 0.05:
			radar = "  Radar: LIVE %.0fs" % _radar_reveal_left
		elif _radar_cooldown_left > 0.05:
			radar = "  Radar: %.0fs" % _radar_cooldown_left
		else:
			radar = "  Radar: ready (U)"
		_hud.text = "%d FPS%s  Score: %d%s" % [Engine.get_frames_per_second(), clock, score, radar]


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
		_cascade = CityVoxelNativeScript.make_cascade_debris()
		_cascade.name = "NativeCascadeDebris"
		add_child(_cascade)
		if _cascade.has_signal("debris_spawned"):
			_cascade.connect("debris_spawned", Callable(self, "_on_native_debris_spawned"))
	var mats: Array = []
	mats.resize(VoxelMaterial.COUNT)
	## Index 0 is AIR — no debris ever spawns for it, the native side skips nulls.
	for i in range(1, VoxelMaterial.COUNT):
		mats[i] = VoxelBlockLibraryScript.debris_material_for(i)
	_cascade.call(
		"setup",
		_terrain,
		_tool,
		_debris_root,
		VOXEL_SIZE,
		mats,
		VoxelBuffer.CHANNEL_TYPE,
		VoxelTool.MODE_SET,
		VoxelMaterial.AIR
	)
	_ensure_infection_director()


func _on_native_debris_spawned(world_pos: Vector3) -> void:
	if _audio != null and _audio.has_method("play_debris"):
		_audio.call("play_debris", world_pos)


func _ensure_infection_director() -> void:
	if _infection == null or not is_instance_valid(_infection):
		_infection = InfectionDirectorScript.new()
		_infection.name = "InfectionDirector"
		add_child(_infection)
	## Street deck voxel Y matches DistrictGenerator.ground_thickness (bedrock+stone).
	_infection.call("setup", _terrain, _tool, VOXEL_SIZE, 6)
	if _infection.has_signal("tendril_killed"):
		var cb_kill := Callable(self, "_on_tendril_killed")
		if not _infection.is_connected("tendril_killed", cb_kill):
			_infection.connect("tendril_killed", cb_kill)
	if _infection.has_signal("tendril_ended"):
		var cb_end := Callable(self, "_on_tendril_ended")
		if not _infection.is_connected("tendril_ended", cb_end):
			_infection.connect("tendril_ended", cb_end)
	if _infection.has_signal("player_score_changed"):
		var cb_score := Callable(self, "_on_player_score_changed")
		if not _infection.is_connected("player_score_changed", cb_score):
			_infection.connect("player_score_changed", cb_score)
	if _tendril_hud != null and is_instance_valid(_tendril_hud):
		_tendril_hud.call("bind_director", _infection)


func _on_player_score_changed(score: int) -> void:
	_player_score = score


func adjust_player_score(delta: int) -> void:
	var score := _player_score
	if _infection != null and is_instance_valid(_infection) and _infection.has_method("get_player_score"):
		score = int(_infection.call("get_player_score"))
	score += delta
	_player_score = score
	if _infection != null and is_instance_valid(_infection):
		_infection.player_score = score
		if _infection.has_signal("player_score_changed"):
			_infection.player_score_changed.emit(score)


func get_player_position() -> Vector3:
	if _walker != null and is_instance_valid(_walker) and not _game_over:
		return _walker.global_position
	return Vector3.INF


func is_player_alive() -> bool:
	return not _game_over and _walker != null and is_instance_valid(_walker)


func get_minimap_snapshot(range_m: float = 100.0) -> Dictionary:
	var origin := Vector3.ZERO
	var yaw := 0.0
	if _walker != null and is_instance_valid(_walker):
		origin = _walker.global_position
		yaw = _walker.rotation.y
	var buildings: Array = []
	if _streamer != null and _streamer.has_method("get_loaded_districts"):
		var districts: Array = _streamer.call("get_loaded_districts") as Array
		for entry in districts:
			var inst = _as_district_instance(entry)
			if inst == null or not is_instance_valid(inst) or inst.building_lod == null:
				continue
			if not inst.building_lod.has_method("get_footprints_near"):
				continue
			var more: Array = inst.building_lod.call("get_footprints_near", origin, range_m) as Array
			for b in more:
				buildings.append(b)
	var undead: Array = []
	var radar_on := _radar_reveal_left > 0.0
	var range_r2 := range_m * range_m
	if _undead != null and is_instance_valid(_undead) and _undead.has_method("get_alive_units"):
		var units: Array = _undead.call("get_alive_units") as Array
		for u in units:
			if u == null or not is_instance_valid(u):
				continue
			var pos: Vector3 = (u as Node3D).global_position
			var dx := pos.x - origin.x
			var dz := pos.z - origin.z
			var d2 := dx * dx + dz * dz
			var outside := d2 > range_r2
			## Nearby undead always paint; beyond-range only while radar is live.
			if outside and not radar_on:
				continue
			var kind := "mage"
			if bool(u.call("is_giant")):
				kind = "giant"
			elif int(u.get("role")) == 1:  ## UndeadUnit.Role.MINION
				kind = "minion"
			undead.append({"pos": pos, "kind": kind, "edge": outside})
	var meteors: Array = []
	for c in get_children():
		if c == null or not is_instance_valid(c):
			continue
		if not str(c.name).begins_with("InfectionMeteor"):
			continue
		var mp: Vector3 = (c as Node3D).global_position
		var mdx := mp.x - origin.x
		var mdz := mp.z - origin.z
		if mdx * mdx + mdz * mdz > range_m * range_m:
			continue
		meteors.append(mp)
	if _terrain != null:
		for site_id in _meteor_sites.keys():
			var site: Dictionary = _meteor_sites[site_id]
			var iv: Variant = site.get("impact_vox", null)
			if iv == null:
				continue
			var vox: Vector3i = iv as Vector3i
			var wp := _terrain.to_global(
				Vector3(float(vox.x) + 0.5, float(vox.y) + 0.5, float(vox.z) + 0.5)
			)
			var sdx := wp.x - origin.x
			var sdz := wp.z - origin.z
			if sdx * sdx + sdz * sdz > range_m * range_m:
				continue
			meteors.append(wp)
	return {
		"origin": origin,
		"yaw": yaw,
		"range_m": range_m,
		"buildings": buildings,
		"undead": undead,
		"meteors": meteors,
		"radar_active": radar_on,
	}


func get_player_target_position() -> Vector3:
	## Chest-ish aim point so orbs track like a standing pedestrian.
	if not is_player_alive():
		return Vector3.INF
	var s := float(_walker.get_character_scale())
	return _walker.global_position + Vector3(0.0, 1.05 * s, 0.0)


func trigger_game_over(reason: String = "Converted by undead") -> void:
	if _game_over:
		return
	_game_over = true
	_spawn_meteors_enabled = false
	if _undead != null and is_instance_valid(_undead) and _undead.has_method("halt_waves"):
		_undead.call("halt_waves")
	if _walker != null and is_instance_valid(_walker):
		if _walker.has_method("set_game_over_locked"):
			_walker.call("set_game_over_locked", true)
		_walker.velocity = Vector3.ZERO
		_walker.release_capture()
	if _game_over_detail != null:
		_game_over_detail.text = reason
	if _game_over_layer != null:
		_game_over_layer.visible = true
	_status.visible = false
	print("CityRoot: GAME OVER — %s" % reason)


func _hide_game_over_overlay() -> void:
	if _game_over_layer != null:
		_game_over_layer.visible = false


func _retry_after_game_over() -> void:
	if not _game_over or _booting:
		return
	## Clear immediately so double-Enter / _input+_unhandled can't double-regen.
	_game_over = false
	var want_undead := _undead_invasion_enabled
	if _settings_panel != null and _settings_panel.has_method("is_undead_invasion_enabled"):
		want_undead = bool(_settings_panel.call("is_undead_invasion_enabled"))
	_undead_invasion_enabled = want_undead
	if _settings_panel != null and _settings_panel.has_method("is_spawn_meteors_enabled"):
		_spawn_meteors_enabled = bool(_settings_panel.call("is_spawn_meteors_enabled"))
	_hide_game_over_overlay()
	call_deferred("_regenerate")


func _ensure_undead_director() -> void:
	if _undead == null or not is_instance_valid(_undead):
		_undead = UndeadInvasionDirectorScript.new()
		_undead.name = "UndeadInvasion"
		add_child(_undead)
	_undead.call("setup", self)
	if _undead_hud != null and is_instance_valid(_undead_hud) and _undead_invasion_enabled:
		_undead_hud.call("bind_director", _undead)


func request_undead_radar() -> bool:
	if _game_over or _booting:
		return false
	if _radar_cooldown_left > 0.0:
		return false
	if _walker == null or not is_instance_valid(_walker):
		return false
	## Paint every living undead on the minimap (edge dots past 100 m). No world light pulse.
	_radar_reveal_left = RADAR_REVEAL_SEC
	_radar_cooldown_left = RADAR_COOLDOWN_SEC
	return true


## Hop one district tile in the direction the walker is facing (J by default).
func request_district_hop() -> bool:
	if _game_over or _booting or _district_hopping:
		return false
	if _walker == null or not is_instance_valid(_walker):
		return false
	if _streamer == null or not is_instance_valid(_streamer):
		return false
	_district_hopping = true
	_district_hop_async()
	return true


func _facing_district_delta(forward: Vector3) -> Vector2i:
	var f := Vector3(forward.x, 0.0, forward.z)
	if f.length_squared() < 0.0001:
		return Vector2i(0, -1)
	f = f.normalized()
	## Snap to the dominant axis so diagonal facing still lands on a neighbour tile.
	if absf(f.x) >= absf(f.z):
		return Vector2i(1 if f.x >= 0.0 else -1, 0)
	return Vector2i(0, 1 if f.z >= 0.0 else -1)


func _district_hop_async() -> void:
	var walker := _walker
	if walker == null or not is_instance_valid(walker):
		_district_hopping = false
		return
	var origin_pos := walker.global_position
	var here := DistrictCoord.from_world(origin_pos, VOXEL_SIZE)
	var delta := _facing_district_delta(-walker.global_transform.basis.z)
	var dest := here + delta
	var theme := DistrictTheme.for_district(city_seed, dest)
	print(
		"CityRoot: district hop %s → %s (%s) facing=%s"
		% [here, dest, theme.display_name, delta]
	)
	if _hud_layer != null:
		_hud_layer.visible = false
	if _loading_splash != null:
		_loading_splash.call(
			"show_splash",
			"Hopping to %s %s…" % [theme.display_name, dest]
		)
	walker.set_physics_process(false)
	walker.velocity = Vector3.ZERO
	## Park above the destination centre so the bubble scores that tile first.
	var hover := DistrictCoord.center_world(dest, VOXEL_SIZE) + Vector3(0.0, 40.0, 0.0)
	walker.global_position = hover
	var inst: DistrictInstance = _streamer.call("prioritize_district", dest) as DistrictInstance
	if inst == null:
		await _finish_district_hop_fail("missing district instance", origin_pos)
		return
	## Wall-clock, not frames: headed runs sit at hundreds of FPS, so a 3600-frame
	## budget was only a few seconds — too short for Hill / Graveyard bakes.
	const HOP_WAIT_MS := 180_000
	const HOP_EARLY_GROUND_MS := 4_000
	const HOP_STATUS_EVERY_MS := 500
	var hop_started := Time.get_ticks_msec()
	var hop_deadline := hop_started + HOP_WAIT_MS
	var last_status_ms := 0
	while not inst.is_ready and Time.get_ticks_msec() < hop_deadline:
		if not is_instance_valid(inst):
			await _finish_district_hop_fail("district unloaded while hopping", origin_pos)
			return
		var elapsed_ms := Time.get_ticks_msec() - hop_started
		if _loading_splash != null and elapsed_ms - last_status_ms >= HOP_STATUS_EVERY_MS:
			last_status_ms = elapsed_ms
			var phase := "ground" if not inst.is_ground_ready else "detail"
			if inst.is_busy:
				phase += ", baking"
			_loading_splash.call(
				"set_status",
				"Loading %s %s (%s, %ds)…"
				% [theme.display_name, dest, phase, elapsed_ms / 1000]
			)
		## Ground is enough to find a street spawn once the stamp job has paused.
		## Hill / Graveyard usually stay busy until full ready — that path waits below.
		if (
			inst.is_ground_ready
			and inst.generator != null
			and not inst.is_busy
			and elapsed_ms >= HOP_EARLY_GROUND_MS
		):
			break
		await get_tree().process_frame
	if not is_instance_valid(inst) or inst.generator == null:
		await _finish_district_hop_fail(
			"district never became ready after %ds"
			% [(Time.get_ticks_msec() - hop_started) / 1000],
			origin_pos
		)
		return
	if not inst.is_ready and not inst.is_ground_ready:
		await _finish_district_hop_fail(
			"district still empty after %ds"
			% [(Time.get_ticks_msec() - hop_started) / 1000],
			origin_pos
		)
		return
	if _loading_splash != null:
		_loading_splash.call("set_status", "Finding spawn in %s…" % theme.display_name)
	var spawn: Vector3 = inst.generator.find_spawn_world(_tool)
	if not _has_solid_ground_at(spawn):
		var ground_deadline := Time.get_ticks_msec() + 45_000
		while not _has_solid_ground_at(spawn) and Time.get_ticks_msec() < ground_deadline:
			await get_tree().process_frame
		spawn = inst.generator.find_spawn_world(_tool)
	walker.global_position = spawn + Vector3(0.0, 6.0, 0.0)
	walker.velocity = Vector3.ZERO
	if _loading_splash != null:
		_loading_splash.call("set_status", "Waiting for ground collisions…")
	var floor_y := await _wait_floor_collision_ms(spawn, 60_000)
	if is_nan(floor_y):
		await _finish_district_hop_fail("no ground collision at hop spawn", origin_pos)
		return
	walker.global_position = Vector3(spawn.x, floor_y + 0.15, spawn.z)
	walker.velocity = Vector3.ZERO
	walker.set_physics_process(true)
	if _streamer != null and _streamer.has_method("clear_priority_district"):
		_streamer.call("clear_priority_district")
	_district_hopping = false
	if _hud_layer != null:
		_hud_layer.visible = true
	if _loading_splash != null:
		_loading_splash.call("hide_splash")
	print("CityRoot: district hop landed in %s at y=%.2f" % [dest, floor_y])


func _finish_district_hop_fail(reason: String, restore_pos: Vector3) -> void:
	push_error("CityRoot: district hop failed — %s" % reason)
	if _streamer != null and _streamer.has_method("clear_priority_district"):
		_streamer.call("clear_priority_district")
	if _walker != null and is_instance_valid(_walker):
		_walker.global_position = restore_pos
		_walker.velocity = Vector3.ZERO
		_walker.set_physics_process(true)
	_district_hopping = false
	if _hud_layer != null and not _booting:
		_hud_layer.visible = true
	if _loading_splash != null:
		_loading_splash.call("set_status", "Hop failed — %s" % reason)
		## Brief beat so the error is readable, then fade.
		await get_tree().create_timer(1.2).timeout
		if not _booting and _loading_splash != null:
			_loading_splash.call("hide_splash")


func _on_tendril_killed(_tendril_id: int) -> void:
	## Tip-kill restores terrain; vanish any loose infection-textured debris too.
	if _cascade != null and is_instance_valid(_cascade) and _cascade.has_method("clear_infection_debris"):
		_cascade.call("clear_infection_debris")


func _on_tendril_ended(tendril_id: int) -> void:
	_release_tendril_from_meteor_site(tendril_id)


func _regenerate() -> void:
	if _booting:
		return
	_booting = true
	_game_over = false
	_hide_game_over_overlay()
	if _hud_layer != null:
		_hud_layer.visible = false
	## Pick the spawn tile before any district bake so the title modal is first.
	if _loading_splash != null:
		_loading_splash.call("show_splash", "Choose a starting district")
	spawn_district_coord = await _resolve_spawn_district()
	var theme := DistrictTheme.for_district(city_seed, spawn_district_coord)
	print(
		"CityRoot: spawn district %s (%s) — pin with --spawn-district=%d,%d or --spawn-theme=%s"
		% [
			spawn_district_coord, theme.display_name,
			spawn_district_coord.x, spawn_district_coord.y,
			theme.display_name.to_lower().replace(" ", "-"),
		]
	)
	if _loading_splash != null:
		_loading_splash.call(
			"show_splash", "Generating %s at %s…" % [theme.display_name, spawn_district_coord]
		)
	elif _status != null:
		_status.visible = true
		_status.text = "Setting up VoxelTerrain…"
	await get_tree().process_frame

	if _walker != null and is_instance_valid(_walker):
		_walker.queue_free()
		_walker = null
	if _tetris != null and is_instance_valid(_tetris):
		if _tetris.has_method("clear_shell"):
			_tetris.call("clear_shell")
		_tetris.queue_free()
		_tetris = null
	_clear_tetris_peds()
	if _streamer != null and is_instance_valid(_streamer):
		_streamer.call("clear_all")
		_streamer.queue_free()
		_streamer = null
	if _action_bar != null and is_instance_valid(_action_bar):
		_action_bar.queue_free()
		_action_bar = null
	if _infection != null and is_instance_valid(_infection):
		_infection.call("clear_all")
		_infection.queue_free()
		_infection = null
	if _undead != null and is_instance_valid(_undead):
		_undead.call("clear_all")
		_undead.queue_free()
		_undead = null
	_player_score = 0
	_radar_cooldown_left = 0.0
	_radar_reveal_left = 0.0
	_clear_all_meteor_sites()
	_meteor_spawn_accum = 0.0
	if _spawn_meteors_enabled:
		_roll_meteor_spawn_interval()
	if _tendril_hud != null and is_instance_valid(_tendril_hud):
		_tendril_hud.call("clear_display")
	if _energy_hud != null and is_instance_valid(_energy_hud):
		_energy_hud.call("clear_display")
	if _undead_hud != null and is_instance_valid(_undead_hud):
		_undead_hud.call("clear_display")
	if _minimap != null and is_instance_valid(_minimap):
		_minimap.call("bind_city", self)
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
		float(_voxel_view_vox) * VOXEL_SIZE
	)
	_streamer.status_message.connect(_on_streamer_status)
	_streamer.spawn_district_ready.connect(_on_spawn_district_ready)

	_status.text = "Generating %s…" % theme.display_name
	_streamer.boot_spawn_district(spawn_district_coord)


func _on_streamer_status(text: String) -> void:
	if _loading_splash != null and _loading_splash.visible:
		_loading_splash.call("set_status", text)
	elif _status != null and _status.visible:
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
		var ground_deadline := Time.get_ticks_msec() + 45_000
		while not _has_solid_ground_at(spawn) and Time.get_ticks_msec() < ground_deadline:
			await get_tree().process_frame
		spawn = gen.find_spawn_world(_tool)

	_status.text = "Spawning player…"
	_walker = CityWalkerScript.new() as CharacterBody3D
	_walker.name = "Walker"
	add_child(_walker)
	_walker.set_physics_process(false)
	## Live voxel motion — digs/holes match data immediately (not remeshed colliders).
	if _walker.has_method("bind_terrain"):
		_walker.call("bind_terrain", _terrain)
	## Hold above until collision exists — never enable physics in the void.
	_walker.global_position = spawn + Vector3(0.0, 6.0, 0.0)
	_walker.blast_requested.connect(_on_blast)
	_walker.melee_strike_requested.connect(_on_melee_strike)
	_walker.stomp_requested.connect(_on_stomp)
	_walker.meteor_requested.connect(_on_meteor_requested)
	_walker.tetris_requested.connect(_on_tetris_requested)
	_walker.pedestrian_requested.connect(_on_pedestrian_requested)
	var cam: Camera3D = _walker.call("get_camera") as Camera3D
	## Visuals out to settings radius; collisions only near the player (big remesh win).
	_player_viewer = VoxelViewer.new()
	_player_viewer.name = "VoxelViewer"
	_player_viewer.view_distance = _voxel_view_vox
	_player_viewer.requires_collisions = false
	_player_viewer.requires_visuals = true
	cam.add_child(_player_viewer)

	_collision_viewer = VoxelViewer.new()
	_collision_viewer.name = "CollisionViewer"
	_collision_viewer.view_distance = _collision_view_vox
	_collision_viewer.requires_collisions = true
	_collision_viewer.requires_visuals = false
	cam.add_child(_collision_viewer)

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

	_booting = false
	if _hud_layer != null:
		_hud_layer.visible = true
	if _loading_splash != null:
		_loading_splash.call("hide_splash")
	elif _status != null:
		_status.visible = false
	_action_bar = PlayerActionBarScript.new()
	_action_bar.name = "PlayerActionBar"
	add_child(_action_bar)
	_action_bar.setup(_walker)
	_action_bar.build_requested.connect(_on_build_chosen)
	if _energy_hud != null and is_instance_valid(_energy_hud):
		_energy_hud.call("bind_walker", _walker)
	if _settings_panel != null:
		_on_settings_applied(_settings_panel.get_settings())
		_apply_saved_controls()
	if _undead_invasion_enabled:
		_ensure_undead_director()
		_undead.call("set_enabled", true)
		if _undead_hud != null and is_instance_valid(_undead_hud):
			_undead_hud.call("bind_director", _undead)
	print(
		"CityRoot: playable — endless stream active at y=%.2f (F1–F6 = build · M = meteor · T = tetris)"
		% floor_y
	)


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
	## Boot path still passes a frame budget; map it to wall-clock at 60 Hz so a
	## unlocked render loop cannot burn the whole wait in a few seconds.
	return await _wait_floor_collision_ms(spawn, maxi(1, max_frames) * 1000 / 60)


func _wait_floor_collision_ms(spawn: Vector3, max_ms: int = 60_000) -> float:
	## Returns floor Y, or NAN if never found. Physics stays disabled until this succeeds.
	var deadline := Time.get_ticks_msec() + max_ms
	var started := Time.get_ticks_msec()
	var last_status := 0
	while Time.get_ticks_msec() < deadline:
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
		var elapsed := Time.get_ticks_msec() - started
		if elapsed - last_status >= 500:
			last_status = elapsed
			if _status != null:
				_status.text = "Waiting for ground collisions… (%ds)" % (elapsed / 1000)
			if _loading_splash != null and _district_hopping:
				_loading_splash.call(
					"set_status", "Waiting for ground collisions… (%ds)" % (elapsed / 1000)
				)
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
	## Revert any tip in the blast first; restored fabric then takes the carve normally.
	_tip_kill_leads_in_sphere(local, radius_vox)
	_carve_destructible_sphere(local, radius_vox)
	_restore_bedrock_floor(local, radius_vox)
	_notify_tetris_damage()
	_notify_destruction(hit_position, maxf(radius_m * 4.0, 28.0))


## Charged LMB bomb (and stomp): carve + outward tumble debris, then cascade columns above.
func apply_charged_blast(hit_world: Vector3, radius_m: float) -> void:
	if _tool == null or _terrain == null:
		return
	var radius := maxf(radius_m, 0.35)
	var local := _terrain.to_local(hit_world)
	## Cap voxel radius so giant characters don't freeze a frame scanning hundreds of thousands of cells.
	var radius_vox := minf(radius / VOXEL_SIZE, 14.0)
	## Tip-kill first so restored bricks/concrete in the sphere can explode with the blast.
	_tip_kill_leads_in_sphere(local, radius_vox)
	var r_i := int(ceil(radius_vox)) + 1
	var r2 := radius_vox * radius_vox
	var cx := int(floor(local.x))
	var cy := int(floor(local.y))
	var cz := int(floor(local.z))
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = VoxelMaterial.AIR
	var detached: Array = []
	var column_max_y: Dictionary = {}  # Vector2i → int
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
				var col := Vector2i(x, z)
				if column_max_y.has(col):
					column_max_y[col] = maxi(int(column_max_y[col]), y)
				else:
					column_max_y[col] = y
				_tool.do_point(vox)
	_restore_bedrock_floor(local, radius_vox)
	if _cascade != null:
		## Primary blast voxels fly outward from the impact.
		if _cascade.has_method("detach_blast_voxels"):
			_cascade.call("detach_blast_voxels", detached, hit_world)
		## Fabric still standing above the hole cascades like melee.
		for col_key in column_max_y.keys():
			var xz: Vector2i = col_key
			var max_y: int = int(column_max_y[col_key])
			_cascade_column_above(Vector3i(xz.x, max_y, xz.y))
	BlastFlashVfxScript.spawn(self, hit_world, radius)
	_notify_tetris_damage(detached)
	_notify_destruction(hit_world, maxf(radius * 5.0, 32.0))


## Drop whatever still stands above a fresh hole — unless it is hillside. Rock is
## self-supporting, and a hill is one connected massif: cascading it turns a single
## charged shot inside a cave into a mountain that hollows itself out column by column.
func _cascade_column_above(top_vox: Vector3i) -> void:
	if _cascade == null or not is_instance_valid(_cascade):
		return
	if not _cascade.has_method("collapse_column_above"):
		return
	var above := int(_tool.get_voxel(Vector3i(top_vox.x, top_vox.y + 1, top_vox.z)))
	if VoxelMaterial.is_self_supporting_terrain(above):
		return
	_cascade.collapse_column_above(top_vox)


## Q stomp: same destruction as a max-charge blast at the feet (anim/FX differ on the walker).
func _on_stomp(feet_position: Vector3, radius_m: float) -> void:
	apply_charged_blast(feet_position, radius_m)


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
	## Revert tips in the punch sphere first; then the strike carves restored fabric as usual.
	_tip_kill_leads_in_sphere(hit_center, radius_vox)
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
				var col := Vector2i(x, z)
				if column_max_y.has(col):
					column_max_y[col] = maxi(int(column_max_y[col]), y)
				else:
					column_max_y[col] = y

	for entry in detached:
		_tool.do_point(entry["vox"] as Vector3i)

	if _cascade == null:
		return
	var hit_world := _terrain.to_global(
		Vector3(float(hit_vox.x) + 0.5, float(hit_vox.y) + 0.5, float(hit_vox.z) + 0.5)
	)
	## Punch sphere is already AIR — spawn debris immediately (same as blast).
	if _cascade.has_method("detach_blast_voxels"):
		_cascade.call("detach_blast_voxels", detached, hit_world)
	elif _cascade.has_method("detach_voxels"):
		_cascade.detach_voxels(detached)
	## Remaining destructibles above the hole tumble down per column.
	for col_key in column_max_y.keys():
		var xz: Vector2i = col_key
		var max_y: int = int(column_max_y[col_key])
		_cascade_column_above(Vector3i(xz.x, max_y, xz.y))

	_notify_tetris_damage(detached)
	_notify_destruction(hit_world, 30.0 + 8.0 * scale)


func _on_meteor_requested(hit_point: Vector3, _hit_normal: Vector3) -> void:
	_spawn_meteor_at(hit_point)


func _on_build_chosen(recipe_id: String) -> void:
	if _tool == null or _terrain == null or _walker == null:
		push_error("CityRoot: cannot build without terrain / walker")
		return
	var recipe: BuildCatalog.Recipe = BuildCatalogScript.by_id(recipe_id)
	if recipe == null:
		return
	var aim: Dictionary = _walker.call("aim_ground_at_cursor") as Dictionary
	var hit: Vector3
	if bool(aim.get("did_hit", false)):
		hit = aim["point"] as Vector3
	else:
		## No ground under the cursor — drop it a few metres in front of the player.
		hit = _walker.global_position - _walker.global_transform.basis.z * 4.0
	var written: int = BuildPlacerScript.place(
		_terrain, _tool, recipe, hit, _walker.global_position
	)
	print("CityRoot: built %s (%d voxels) at %s" % [recipe.display_name, written, hit])


func _on_tetris_requested(hit_point: Vector3, _hit_normal: Vector3) -> void:
	_spawn_tetris_at(hit_point)


func _on_pedestrian_requested(hit_point: Vector3, _hit_normal: Vector3) -> void:
	_spawn_tetris_ped_at(hit_point)


func _spawn_tetris_at(hit_point: Vector3) -> void:
	if _tool == null or _terrain == null:
		push_error("CityRoot: cannot spawn Tetris without VoxelTerrain tool")
		return
	if _tetris != null and is_instance_valid(_tetris):
		if _tetris.has_method("clear_shell"):
			_tetris.call("clear_shell")
		_tetris.queue_free()
		_tetris = null
	## Old cabinet players lose their machine.
	_clear_tetris_peds()
	var face_yaw := 0.0
	if _walker != null and is_instance_valid(_walker):
		var to_player := get_player_position() - hit_point
		to_player.y = 0.0
		if to_player.length_squared() > 0.01:
			face_yaw = atan2(-to_player.x, -to_player.z)
		else:
			face_yaw = _walker.rotation.y + PI
	## Cardinal facing only — voxel shell must stay axis-aligned (no diagonal cabinets).
	face_yaw = roundf(face_yaw / (PI * 0.5)) * (PI * 0.5)
	_tetris = TetrisMachineScript.new() as Node3D
	_tetris.name = "TetrisMachine"
	var spawned: Node3D = _tetris
	add_child(_tetris)
	spawned.tree_exited.connect(func() -> void:
		if _tetris == spawned:
			_tetris = null
	)
	_tetris.call("begin", _terrain, _tool, hit_point, face_yaw, VOXEL_SIZE)


func _spawn_tetris_ped_at(hit_point: Vector3) -> void:
	var slot := _tetris_peds.size()
	var ped: Node3D = TetrisPedNpcScript.new() as Node3D
	ped.name = "TetrisPedNpc_%d" % slot
	add_child(ped)
	_tetris_peds.append(ped)
	ped.tree_exited.connect(func() -> void:
		_tetris_peds.erase(ped)
	)
	var machine: Node3D = _tetris if _tetris != null and is_instance_valid(_tetris) else null
	ped.call("begin", hit_point, machine, slot)


func _clear_tetris_peds() -> void:
	for ped in _tetris_peds:
		if ped != null and is_instance_valid(ped):
			ped.queue_free()
	_tetris_peds.clear()


func _notify_tetris_damage(detached: Array = []) -> void:
	if _tetris == null or not is_instance_valid(_tetris):
		return
	if detached.is_empty():
		if _tetris.has_method("check_integrity"):
			_tetris.call("check_integrity")
	elif _tetris.has_method("notify_voxels_carved"):
		_tetris.call("notify_voxels_carved", detached)


func _try_auto_spawn_meteor() -> void:
	var aim := _pick_ground_meteor_target()
	if aim == Vector3.INF:
		## No clear ground this beat — try again soon instead of waiting another full interval.
		_meteor_spawn_interval_sec = minf(_meteor_spawn_interval_sec, 20.0)
		return
	_spawn_meteor_at(aim)


func _spawn_meteor_at(hit_point: Vector3) -> void:
	if _terrain == null or _tool == null:
		return
	_ensure_infection_director()
	## Connect before begin so a same-frame impact cannot miss the handler.
	var meteor: Node = InfectionMeteorScript.new()
	meteor.name = "InfectionMeteor"
	add_child(meteor)
	meteor.connect("impacted", _on_meteor_impacted)
	meteor.call("begin", _terrain, _tool, hit_point, 55.0)


## Random outdoor ground deck near the player — never building fabric.
func _pick_ground_meteor_target() -> Vector3:
	return _pick_ground_ring_target(50.0, 150.0)


func pick_undead_spawn_point() -> Vector3:
	return _pick_ground_ring_target(50.0, 150.0)


func _pick_ground_ring_target(min_m: float, max_m: float) -> Vector3:
	if _terrain == null or _tool == null or _walker == null or not is_instance_valid(_walker):
		return Vector3.INF
	## Keep impacts/spawns inside the infection detail bubble so tips aren't suspended on arrival.
	var detail_m := 140.0
	if _streamer != null:
		detail_m = float(_streamer.get("voxel_detail_radius_m"))
		if detail_m < 40.0:
			detail_m = 40.0
	var capped_max := minf(max_m, detail_m * 0.9)
	var capped_min := minf(min_m, capped_max - 15.0)
	if capped_min < 20.0:
		capped_min = minf(20.0, capped_max * 0.35)
	var origin := _walker.global_position
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	for _attempt in range(28):
		var ang := randf() * TAU
		var dist := randf_range(capped_min, capped_max)
		var wx := origin.x + cos(ang) * dist
		var wz := origin.z + sin(ang) * dist
		var local := _terrain.to_local(Vector3(wx, origin.y, wz))
		var lx := int(floor(local.x))
		var lz := int(floor(local.z))
		var found_y := -1
		for y in range(56, 0, -1):
			var vox := Vector3i(lx, y, lz)
			var id := int(_tool.get_voxel(vox))
			if id == VoxelMaterial.AIR:
				continue
			if VoxelMaterial.is_building_fabric(id):
				found_y = -1
				break
			if VoxelMaterial.is_ground_surface(id):
				found_y = y
				break
			## Non-ground solid (water / bedrock / odd) — skip this column.
			found_y = -1
			break
		if found_y < 1:
			continue
		return _terrain.to_global(Vector3(float(lx) + 0.5, float(found_y) + 0.95, float(lz) + 0.5))
	return Vector3.INF


func find_nearest_grow_pad(from: Vector3, max_dist: float) -> Node3D:
	if _streamer == null or not _streamer.has_method("get_loaded_districts"):
		return null
	var best: Node3D = null
	var best_d2 := max_dist * max_dist
	var districts: Array = _streamer.call("get_loaded_districts") as Array
	for entry in districts:
		var inst = _as_district_instance(entry)
		if inst == null or not is_instance_valid(inst) or inst.scale_pads == null:
			continue
		for pad in inst.scale_pads.get_children():
			if pad == null or not is_instance_valid(pad):
				continue
			if not (pad is ScalePad):
				continue
			var sp := pad as ScalePad
			if sp.kind != ScalePad.Kind.GROW:
				continue
			var d2 := Vector2(sp.global_position.x - from.x, sp.global_position.z - from.z).length_squared()
			if d2 > best_d2:
				continue
			best_d2 = d2
			best = sp
	return best


func find_nearest_ped_position(from: Vector3, max_dist: float) -> Vector3:
	var best := Vector3.INF
	var best_d2 := max_dist * max_dist
	## Player counts as a pedestrian target for mage aim.
	if is_player_alive():
		var ppos := get_player_target_position()
		var pd2 := Vector2(ppos.x - from.x, ppos.z - from.z).length_squared()
		if pd2 <= best_d2:
			best_d2 = pd2
			best = ppos
	if _streamer == null or not _streamer.has_method("get_loaded_districts"):
		return best
	var districts: Array = _streamer.call("get_loaded_districts") as Array
	for entry in districts:
		var inst = _as_district_instance(entry)
		if inst == null or not is_instance_valid(inst) or inst.crowd == null:
			continue
		var hit: Dictionary = inst.crowd.find_nearest_agent(from, max_dist)
		if hit.is_empty():
			continue
		var pos: Vector3 = hit["position"] as Vector3
		var d2 := Vector2(pos.x - from.x, pos.z - from.z).length_squared()
		if d2 > best_d2:
			continue
		best_d2 = d2
		best = pos
	return best


## Panic pedestrians near undead mages (trigger / clear distances in meters).
func scare_crowd_from_mages(threats: Array, trigger_m: float, clear_m: float) -> void:
	if threats.is_empty():
		return
	if _streamer == null or not _streamer.has_method("get_loaded_districts"):
		return
	var districts: Array = _streamer.call("get_loaded_districts") as Array
	for entry in districts:
		var inst = _as_district_instance(entry)
		if inst == null or not is_instance_valid(inst) or inst.crowd == null:
			continue
		inst.crowd.scare_from_threats(threats, trigger_m, clear_m)


## Hit player or convert nearest ped near world_pos. Returns former position or null.
func try_orb_hit_player(world_pos: Vector3, radius: float) -> bool:
	if not is_player_alive():
		return false
	var ppos := get_player_target_position()
	var hit_r := radius + 0.45 * float(_walker.get_character_scale())
	if world_pos.distance_squared_to(ppos) > hit_r * hit_r:
		return false
	trigger_game_over("Undead conversion orb")
	return true


func try_convert_ped_near(world_pos: Vector3, radius: float) -> Variant:
	if _streamer == null or not _streamer.has_method("get_loaded_districts"):
		return null
	var best_crowd: CrowdDirector = null
	var best_agent: PedAgent = null
	var best_d2 := radius * radius
	var districts: Array = _streamer.call("get_loaded_districts") as Array
	for entry in districts:
		var inst = _as_district_instance(entry)
		if inst == null or not is_instance_valid(inst) or inst.crowd == null:
			continue
		var hit: Dictionary = inst.crowd.find_nearest_agent(world_pos, radius)
		if hit.is_empty():
			continue
		var pos: Vector3 = hit["position"] as Vector3
		var d2 := pos.distance_squared_to(world_pos)
		if d2 > best_d2:
			continue
		best_d2 = d2
		best_crowd = inst.crowd
		best_agent = hit["agent"] as PedAgent
	if best_crowd == null or best_agent == null:
		return null
	var former: Vector3 = best_crowd.convert_agent_silent(best_agent)
	if former == Vector3.INF:
		return null
	return former


func undead_stomp_at(world_pos: Vector3, radius_m: float) -> void:
	if _terrain == null or _tool == null:
		return
	## Cap carve size — giant scale used to push huge radii and melt remeshing.
	var radius_vox := clampf(radius_m / VOXEL_SIZE, 1.5, 8.0)
	var local := _terrain.to_local(world_pos)
	var removed := _carve_building_sphere_counted(local, radius_vox)
	if removed <= 0:
		return
	adjust_player_score(-removed)
	_notify_destruction(world_pos, 28.0 + radius_vox)


## Giant facade brush: peel full-height structure strips and tumble the debris.
## inward = toward the wall, along = walk direction parallel to the facade.
func undead_giant_scrape_at(contact_world: Vector3, inward: Vector3, along: Vector3) -> int:
	if _terrain == null or _tool == null:
		return 0
	var into := inward
	into.y = 0.0
	if into.length_squared() < 0.0001:
		return 0
	into = into.normalized()
	var side := along
	side.y = 0.0
	if side.length_squared() < 0.0001:
		side = Vector3(-into.z, 0.0, into.x)
	else:
		side = side.normalized()
	var local := _terrain.to_local(contact_world)
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	## March into the wall; scan tall so floor-slab edges still register after the shell is gone.
	var hit := Vector3i(2147483647, 2147483647, 2147483647)
	var found := false
	for step in range(0, 18):
		var p := local + into * (float(step) * 0.55)
		var v := Vector3i(int(floor(p.x)), int(floor(p.y)), int(floor(p.z)))
		for dy in range(-4, 56):
			var probe := Vector3i(v.x, v.y + dy, v.z)
			if probe.y < 1:
				continue
			var id := int(_tool.get_voxel(probe))
			if not VoxelMaterial.is_undead_structure_target(id):
				continue
			hit = probe
			found = true
			break
		if found:
			break
	if not found:
		return 0
	## Strip width along the walk + a couple voxels deep into the building.
	var along_half := 2
	var depth_vox := 2
	var ix := Vector3i(int(round(into.x)), 0, int(round(into.z)))
	if ix == Vector3i.ZERO:
		if absf(into.x) >= absf(into.z):
			ix = Vector3i(1 if into.x >= 0.0 else -1, 0, 0)
		else:
			ix = Vector3i(0, 0, 1 if into.z >= 0.0 else -1)
	var sx := Vector3i(int(round(side.x)), 0, int(round(side.z)))
	if sx == Vector3i.ZERO:
		sx = Vector3i(-ix.z, 0, ix.x)
	var detached: Array = []
	const MAX_DEBRIS := 160
	## Peel every structure voxel in the column band — floor slabs have air gaps between them.
	var y_lo := maxi(1, hit.y - 8)
	var y_hi := hit.y + 72
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = VoxelMaterial.AIR
	var removed := 0
	var scrape_center := Vector3(float(hit.x) + 0.5, float(hit.y) + 0.5, float(hit.z) + 0.5)
	_tip_kill_leads_in_sphere(scrape_center, 8.0)
	for a in range(-along_half, along_half + 1):
		for d in range(0, depth_vox):
			var col_x := hit.x + sx.x * a + ix.x * d
			var col_z := hit.z + sx.z * a + ix.z * d
			for y3 in range(y_lo, y_hi + 1):
				var vox := Vector3i(col_x, y3, col_z)
				var mat_id := int(_tool.get_voxel(vox))
				if not VoxelMaterial.is_undead_structure_target(mat_id):
					continue
				if detached.size() < MAX_DEBRIS:
					detached.append({"vox": vox, "mat": mat_id})
				_tool.do_point(vox)
				removed += 1
	if removed <= 0:
		return 0
	adjust_player_score(-removed)
	var world_hit := _terrain.to_global(
		Vector3(float(hit.x) + 0.5, float(hit.y) + 0.5, float(hit.z) + 0.5)
	)
	if _cascade != null and is_instance_valid(_cascade):
		if _cascade.has_method("detach_blast_voxels") and not detached.is_empty():
			_cascade.call("detach_blast_voxels", detached, world_hit)
	_notify_tetris_damage(detached)
	_notify_destruction(world_hit, 36.0)
	return removed


## Minion bite: remove one nearby building voxel (−1 score). No cascade.
func undead_nibble_building_near(world_pos: Vector3, reach_m: float) -> bool:
	if _terrain == null or _tool == null:
		return false
	var vox := _find_building_vox_near(world_pos, reach_m)
	if vox == Vector3i(2147483647, 2147483647, 2147483647):
		return false
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var mat_id := int(_tool.get_voxel(vox))
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = VoxelMaterial.AIR
	_tool.do_point(vox)
	adjust_player_score(-1)
	var world := _terrain.to_global(Vector3(float(vox.x) + 0.5, float(vox.y) + 0.5, float(vox.z) + 0.5))
	_notify_tetris_damage([{"vox": vox, "mat": mat_id}])
	_notify_destruction(world, 10.0)
	return true


## World position of a nearby building fabric voxel, or Vector3.INF.
func find_nearest_building_nibble(from: Vector3, max_dist: float) -> Vector3:
	var vox := _find_building_vox_near(from, max_dist)
	if vox == Vector3i(2147483647, 2147483647, 2147483647):
		return Vector3.INF
	return _terrain.to_global(Vector3(float(vox.x) + 0.5, float(vox.y) + 0.5, float(vox.z) + 0.5))


func _find_building_vox_near(from: Vector3, max_dist: float) -> Vector3i:
	const SENTINEL := Vector3i(2147483647, 2147483647, 2147483647)
	if _terrain == null or _tool == null:
		return SENTINEL
	var local := _terrain.to_local(from)
	var max_vox := maxi(int(ceil(max_dist / VOXEL_SIZE)), 2)
	var ox := int(floor(local.x))
	var oy := int(floor(local.y))
	var oz := int(floor(local.z))
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var best := SENTINEL
	var best_score := -1.0e30
	## Prefer exposed edges (air beside them) so peeled shells still yield floor-slab lips.
	for r in range(0, max_vox + 1):
		var found_this_ring := false
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if r > 0 and absi(dx) != r and absi(dz) != r:
					continue
				## Tall scan — floors sit well above street after the outer wall is gone.
				for dy in range(0, 48):
					var v := Vector3i(ox + dx, oy + dy, oz + dz)
					var id := int(_tool.get_voxel(v))
					if not VoxelMaterial.is_undead_structure_target(id):
						continue
					var center := _terrain.to_global(
						Vector3(float(v.x) + 0.5, float(v.y) + 0.5, float(v.z) + 0.5)
					)
					var world_d := center.distance_to(from)
					if world_d > max_dist:
						continue
					## Exposed if any horizontal neighbor is air / non-structure.
					var exposed := 0
					var nbrs: Array[Vector3i] = [
						Vector3i(1, 0, 0),
						Vector3i(-1, 0, 0),
						Vector3i(0, 0, 1),
						Vector3i(0, 0, -1),
					]
					for off in nbrs:
						var nid := int(_tool.get_voxel(v + off))
						if not VoxelMaterial.is_undead_structure_target(nid):
							exposed += 1
					## Buried interior cores score poorly; open floor edges / walls win.
					var score := float(exposed) * 40.0 - world_d
					if score <= best_score:
						continue
					best_score = score
					best = v
					found_this_ring = true
		if found_this_ring and r >= 2:
			break
	return best


func _carve_building_sphere_counted(local_center: Vector3, radius_vox: float) -> int:
	## Giant stomps only hit building fabric — not roads / plazas / parks.
	var removed := 0
	var r_i := int(ceil(radius_vox)) + 1
	var r2 := radius_vox * radius_vox
	var cx := int(floor(local_center.x))
	var cy := int(floor(local_center.y))
	var cz := int(floor(local_center.z))
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = VoxelMaterial.AIR
	for z in range(cz - r_i, cz + r_i + 1):
		for y in range(cy - r_i, cy + r_i + 1):
			for x in range(cx - r_i, cx + r_i + 1):
				var center := Vector3(float(x) + 0.5, float(y) + 0.5, float(z) + 0.5)
				if center.distance_squared_to(local_center) > r2 + 0.0001:
					continue
				var vox := Vector3i(x, y, z)
				var id := int(_tool.get_voxel(vox))
				if not VoxelMaterial.is_undead_structure_target(id):
					continue
				_tool.do_point(vox)
				removed += 1
	return removed


func _on_meteor_impacted(world_pos: Vector3, seeds: Array, sky_beam: Node = null) -> void:
	BlastFlashVfxScript.spawn(self, world_pos, 7.5)
	if _infection == null or _terrain == null:
		return
	var local := _terrain.to_local(world_pos)
	var impact_vox := Vector3i(int(floor(local.x)), int(floor(local.y)), int(floor(local.z)))
	var site_id := _next_meteor_site_id
	_next_meteor_site_id += 1
	var site_tendrils: Dictionary = {}
	var seen: Dictionary = {}
	var spawned := 0
	for entry in seeds:
		if not (entry is Dictionary):
			continue
		var vox: Vector3i = entry.get("vox", Vector3i.ZERO)
		var prev_mat := int(entry.get("prev_mat", -1))
		var key := "%d,%d,%d" % [vox.x, vox.y, vox.z]
		if seen.has(key):
			continue
		seen[key] = true
		## General direction: away from impact crater.
		var away := Vector3(
			float(vox.x - impact_vox.x),
			float(vox.y - impact_vox.y) * 0.35,
			float(vox.z - impact_vox.z)
		)
		if away.length_squared() < 0.25:
			away = Vector3(randf_range(-1.0, 1.0), 0.1, randf_range(-1.0, 1.0))
		var tid := int(_infection.call("spawn_tendril_at_vox", vox, prev_mat, away, true))
		if tid >= 0:
			spawned += 1
			site_tendrils[tid] = true
			_tendril_to_meteor_site[tid] = site_id
		else:
			## Meteor pre-planted a LEAD; registration failed (cap) — don't leave an orphan tip.
			_tool.channel = VoxelBuffer.CHANNEL_TYPE
			_tool.mode = VoxelTool.MODE_SET
			_tool.value = prev_mat if prev_mat >= 0 else VoxelMaterial.METEOR_ROCK
			_tool.do_point(vox)
	## If capacity/plant glitches left us short, force more tips on nearby fabric.
	var want_min := 2
	if spawned < want_min and _infection.has_method("spawn_tendril_at_vox"):
		for ring in range(4, 14):
			if spawned >= want_min:
				break
			for z in range(-ring, ring + 1):
				for x in range(-ring, ring + 1):
					if spawned >= want_min:
						break
					if maxi(absi(x), absi(z)) != ring:
						continue
					var v2 := impact_vox + Vector3i(x, 0, z)
					if v2.y < 6:
						v2.y = 6
					_tool.channel = VoxelBuffer.CHANNEL_TYPE
					var id := int(_tool.get_voxel(v2))
					if not VoxelMaterial.is_infectable(id):
						## Prefer surface fabric above, never diggable stone under the deck.
						var above := v2 + Vector3i(0, 1, 0)
						if VoxelMaterial.is_infectable(int(_tool.get_voxel(above))):
							v2 = above
							id = int(_tool.get_voxel(v2))
						else:
							continue
					var key2 := "%d,%d,%d" % [v2.x, v2.y, v2.z]
					if seen.has(key2):
						continue
					seen[key2] = true
					var away2 := Vector3(float(x), 0.1, float(z))
					var tid2 := int(_infection.call("spawn_tendril_at_vox", v2, id, away2, true))
					if tid2 >= 0:
						spawned += 1
						site_tendrils[tid2] = true
						_tendril_to_meteor_site[tid2] = site_id

	_meteor_sites[site_id] = {
		"tendrils": site_tendrils,
		"beam": sky_beam,
		"impact_vox": impact_vox,
	}
	## No tips planted → rock is immediately fair game and the beam collapses.
	if site_tendrils.is_empty():
		_clear_meteor_site(site_id)


func _release_tendril_from_meteor_site(tendril_id: int) -> void:
	if not _tendril_to_meteor_site.has(tendril_id):
		return
	var site_id := int(_tendril_to_meteor_site[tendril_id])
	_tendril_to_meteor_site.erase(tendril_id)
	if not _meteor_sites.has(site_id):
		return
	var site: Dictionary = _meteor_sites[site_id]
	var tids: Dictionary = site.get("tendrils", {})
	tids.erase(tendril_id)
	site["tendrils"] = tids
	_meteor_sites[site_id] = site
	if tids.is_empty():
		_clear_meteor_site(site_id)


func _clear_meteor_site(site_id: int) -> void:
	if not _meteor_sites.has(site_id):
		return
	var site: Dictionary = _meteor_sites[site_id]
	_meteor_sites.erase(site_id)
	var tids: Dictionary = site.get("tendrils", {})
	for tid in tids.keys():
		_tendril_to_meteor_site.erase(int(tid))
	var beam: Variant = site.get("beam", null)
	if beam is Node and is_instance_valid(beam):
		if beam.has_method("begin_fade_out"):
			beam.call("begin_fade_out", 1.2)
		else:
			beam.queue_free()
	var impact_vox: Vector3i = site.get("impact_vox", Vector3i.ZERO)
	_unlock_meteor_rock_at(impact_vox)


func _clear_all_meteor_sites() -> void:
	var ids: Array = _meteor_sites.keys()
	for site_id in ids:
		_clear_meteor_site(int(site_id))
	_meteor_sites.clear()
	_tendril_to_meteor_site.clear()


## Crater rock becomes normal destructible stone once its tendrils are gone.
func _unlock_meteor_rock_at(impact_vox: Vector3i) -> void:
	if _tool == null:
		return
	var r: int = 4
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = VoxelMaterial.STONE
	for z in range(-r, r + 1):
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if x * x + y * y + z * z > r * r + 1:
					continue
				var vox := impact_vox + Vector3i(x, y, z)
				if int(_tool.get_voxel(vox)) == VoxelMaterial.METEOR_ROCK:
					_tool.do_point(vox)


func _notify_infection_leads_in(vox_entries: Array) -> void:
	## Full tip-kill + lineage restore for any lead in the carve set (before AIR write).
	if _infection == null or not is_instance_valid(_infection):
		return
	_infection.call("notify_voxels_carved", vox_entries)


## Returns true if at least one lead was killed (tendril fully reverted).
func _tip_kill_leads_in_entries(vox_entries: Array) -> bool:
	if _infection == null or not is_instance_valid(_infection) or _tool == null:
		return false
	var leads: Array = []
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	for item in vox_entries:
		var vox: Vector3i
		if item is Dictionary:
			vox = item.get("vox", Vector3i.ZERO)
			## Fast path from collect mat id.
			if int(item.get("mat", -1)) == VoxelMaterial.INFECTION_LEAD:
				leads.append(vox)
				continue
		elif item is Vector3i:
			vox = item
		else:
			continue
		if int(_tool.get_voxel(vox)) == VoxelMaterial.INFECTION_LEAD:
			leads.append(vox)
	if leads.is_empty():
		return false
	_infection.call("notify_voxels_carved", leads)
	return true


func _tip_kill_leads_in_sphere(local_center: Vector3, radius_vox: float) -> bool:
	if _infection == null or not is_instance_valid(_infection) or _tool == null:
		return false
	var r_i := int(ceil(radius_vox)) + 1
	var r2 := radius_vox * radius_vox
	var cx := int(floor(local_center.x))
	var cy := int(floor(local_center.y))
	var cz := int(floor(local_center.z))
	var leads: Array = []
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	for z in range(cz - r_i, cz + r_i + 1):
		for y in range(cy - r_i, cy + r_i + 1):
			for x in range(cx - r_i, cx + r_i + 1):
				var center := Vector3(float(x) + 0.5, float(y) + 0.5, float(z) + 0.5)
				if center.distance_squared_to(local_center) > r2 + 0.0001:
					continue
				var vox := Vector3i(x, y, z)
				if int(_tool.get_voxel(vox)) == VoxelMaterial.INFECTION_LEAD:
					leads.append(vox)
	if leads.is_empty():
		return false
	_infection.call("notify_voxels_carved", leads)
	return true


func _notify_infection_sphere_carved(local_center: Vector3, radius_vox: float) -> void:
	_tip_kill_leads_in_sphere(local_center, radius_vox)


func _invalidate_infection_outside_bubble() -> void:
	if _infection == null or not is_instance_valid(_infection):
		return
	if _walker == null or not is_instance_valid(_walker):
		return
	var center := _walker.global_position
	var detail_m := 140.0
	if _streamer != null:
		detail_m = float(_streamer.get("voxel_detail_radius_m"))
		if detail_m < 40.0:
			detail_m = 40.0
	var half := Vector3(detail_m, 80.0, detail_m)
	var aabb := AABB(center - half, half * 2.0)
	_infection.call("invalidate_outside_aabb", aabb)


func _notify_destruction(world_pos: Vector3, radius_m: float = 32.0) -> void:
	## Peds sprint and cars floor it away from the blast along their graphs.
	if _streamer == null or not _streamer.has_method("get_loaded_districts"):
		return
	var districts: Array = _streamer.call("get_loaded_districts") as Array
	for entry in districts:
		var inst = _as_district_instance(entry)
		if inst == null or not is_instance_valid(inst):
			continue
		if inst.crowd != null and is_instance_valid(inst.crowd):
			inst.crowd.react_to_destruction(world_pos, radius_m)
		if inst.vehicles != null and is_instance_valid(inst.vehicles):
			inst.vehicles.react_to_destruction(world_pos, radius_m)


## First destructible voxel along a world ray (includes walk-through park mats:
## bark / leaves / planters). Physics rays miss those because they have no collision.
## Returns {} or {point, normal, distance} in world space.
func probe_destructible_ray(from_world: Vector3, to_world: Vector3) -> Dictionary:
	if _tool == null or _terrain == null:
		return {}
	var local_from := _terrain.to_local(from_world)
	var local_to := _terrain.to_local(to_world)
	var delta := local_to - local_from
	var dist := delta.length()
	if dist < 0.05:
		return {}
	var dir := delta / dist
	## ~0.2 voxel steps — same density as melee march.
	var step := 0.2
	var steps := int(ceil(dist / step)) + 1
	var world_dir := to_world - from_world
	var world_len := world_dir.length()
	if world_len < 0.05:
		return {}
	world_dir /= world_len
	var prev := Vector3i(2147483647, 2147483647, 2147483647)
	for i in range(1, steps + 1):
		var p := local_from + dir * (float(i) * step)
		var v := Vector3i(int(floor(p.x)), int(floor(p.y)), int(floor(p.z)))
		if v == prev:
			continue
		prev = v
		var id := int(_tool.get_voxel(v))
		if not VoxelMaterial.is_destructible(id):
			continue
		var hit_t := clampf((float(i) * step / dist) * world_len - VOXEL_SIZE * 0.2, 0.0, world_len)
		return {
			"point": from_world + world_dir * hit_t,
			"normal": -world_dir,
			"distance": hit_t,
		}
	return {}


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
	elif kind == "undead":
		var undead: Node = hit["undead"]
		var unit: Node = hit["unit"]
		ok = bool(undead.call("kill_unit", unit))
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
		var inst = _as_district_instance(entry)
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
	if _undead != null and is_instance_valid(_undead) and _undead.has_method("query_segment_hit"):
		var u_hit: Dictionary = _undead.call("query_segment_hit", from, to)
		if not u_hit.is_empty():
			var d3: float = float(u_hit["distance"])
			if d3 < best_dist:
				best_dist = d3
				best = u_hit.duplicate()
				best["kind"] = "undead"
				best["undead"] = _undead
	return best


func _carve_destructible_sphere(local_center: Vector3, radius_vox: float) -> void:
	_carve_destructible_sphere_counted(local_center, radius_vox)


func _carve_destructible_sphere_counted(local_center: Vector3, radius_vox: float) -> int:
	## Point carve only — skips infection body / meteor rock / bedrock / water.
	var removed := 0
	var r_i := int(ceil(radius_vox)) + 1
	var r2 := radius_vox * radius_vox
	var cx := int(floor(local_center.x))
	var cy := int(floor(local_center.y))
	var cz := int(floor(local_center.z))
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = VoxelMaterial.AIR
	for z in range(cz - r_i, cz + r_i + 1):
		for y in range(cy - r_i, cy + r_i + 1):
			for x in range(cx - r_i, cx + r_i + 1):
				var center := Vector3(float(x) + 0.5, float(y) + 0.5, float(z) + 0.5)
				if center.distance_squared_to(local_center) > r2 + 0.0001:
					continue
				var vox := Vector3i(x, y, z)
				if not VoxelMaterial.is_destructible(int(_tool.get_voxel(vox))):
					continue
				_tool.do_point(vox)
				removed += 1
	return removed


## Ensure the indestructible bedrock band (y=0) remains under a crater.
## Diggable STONE / pavement above are left as carved air so holes match debris.
func _restore_bedrock_floor(center_vox: Vector3, radius_vox: float) -> void:
	const BEDROCK_BAND := 1
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
			for y in range(0, BEDROCK_BAND):
				_tool.do_point(Vector3i(x, y, z))


func _player_controls() -> RefCounted:
	if _settings_panel != null and _settings_panel.has_method("get_player_controls"):
		return _settings_panel.call("get_player_controls") as RefCounted
	return null


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var ek := event as InputEventKey
	var ctl := _player_controls()
	if ctl == null or not ctl.has_method("matches_key_pressed"):
		return
	if bool(ctl.call("matches_key_pressed", ek, "quit")):
		get_tree().quit()
		return
	if bool(ctl.call("matches_key_pressed", ek, "retry")):
		if _game_over:
			_retry_after_game_over()
			get_viewport().set_input_as_handled()
		return
	if bool(ctl.call("matches_key_pressed", ek, "day_night")):
		if _game_over:
			return
		if _day_night != null and _day_night.has_method("toggle_day_night"):
			_day_night.call("toggle_day_night")
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	## Game-over retry must work even if another control ate unhandled input.
	if not _game_over or _booting:
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var ctl := _player_controls()
	if ctl != null and ctl.has_method("matches_key_pressed"):
		if bool(ctl.call("matches_key_pressed", event, "retry")):
			_retry_after_game_over()
			get_viewport().set_input_as_handled()
