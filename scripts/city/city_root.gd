## Endless city POC: spawn-district boot, then bubble streaming with view priority.
class_name CityRoot
extends Node3D

const VOXEL_SIZE := 0.5
const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
const VoxelBlockLibraryScript := preload("res://scripts/city/voxel_block_library.gd")
const CityWalkerScript := preload("res://scripts/city/city_walker.gd")
const DistrictInstanceScript := preload("res://scripts/city/district_instance.gd")
const CityStreamerScript := preload("res://scripts/city/city_streamer.gd")
const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")
const PlayerActionBarScript := preload("res://scripts/city/player_action_bar.gd")
const PlayerEnergyHudScript := preload("res://scripts/city/player_energy_hud.gd")
const PlayerHealthHudScript := preload("res://scripts/city/player_health_hud.gd")
const DamageSourceScript := preload("res://scripts/city/damage_source.gd")
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
const GemLightDirectorScript := preload("res://scripts/city/gem_light_director.gd")
const PlayerInventoryScript := preload("res://scripts/city/player_inventory.gd")
const PlayerInventoryPanelScript := preload("res://scripts/city/player_inventory_panel.gd")
const MonsterSummonPanelScript := preload("res://scripts/city/monster_summon_panel.gd")
const NavDebugOverlayScript := preload("res://scripts/city/nav_debug_overlay.gd")
const CityTargetingScript := preload("res://scripts/city/city_targeting.gd")

## Sentinel for city_seed: draw a fresh world seed when the game starts.
const SEED_RANDOM := 0
## Frames the warm-up visuals stay on screen (behind the splash) so their pipelines compile.
const WARMUP_FRAMES := 8
## Warm-up staging height, far above any generated terrain so nothing intersects the city.
const WARMUP_ALTITUDE_M := 4000.0
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
## Theme of the spawn tile (from RNG / CLI). -1 = unset.
var spawn_theme_id: int = -1

var _terrain: VoxelTerrain
var _tool: VoxelTool
## Single funnel for every live voxel write; publishes voxels_changed(aabb_vox).
var _brush: CityBrush
## Outfit scenes kept referenced for the session so gameplay loads hit the resource cache.
var _warm_scenes: Array[PackedScene] = []
var _streamer: Node
## Typed as CharacterBody3D so portable installs work before global class_name cache exists.
var _walker: CharacterBody3D
var _hud: Label
var _hud_layer: CanvasLayer
## False while the splash owns the screen (boot, district hop). Combined with is_modal_open()
## in _refresh_hud_visibility; nothing sets a HUD layer's visibility outside that.
var _hud_enabled: bool = false
var _status: Label
var _loading_splash: CanvasLayer
var _action_bar: Node
var _energy_hud: Node
var _health_hud: Node
var _debris_root: Node3D
var _cascade: Node
var _gem_lights: Node
var _infection: Node
var _tendril_hud: Node
var _undead_hud: Node
var _minimap: Node
## Span field / portal / corridor / dynamic-block viewer, off until F8.
var _nav_overlay: NavDebugOverlay
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
## Collected gems and crafted items (25 stackable slots).
var _inventory: PlayerInventory = PlayerInventoryScript.new() as PlayerInventory
var _inventory_panel: Node
var _monster_summon_panel: Node
## Free-cursor voxel aim captured when N opens the summon panel, before the cursor moves to UI.
var _summon_aim: CityTargeting.Result = null
var _last_summon_requested_point: Vector3 = Vector3.INF
var _last_summon_actual_point: Vector3 = Vector3.INF
var _last_summoned_unit: UndeadUnit = null
## Cached building-nibble probe — the voxel ring scan is far too heavy to run every goal tick.
var _nibble_cache_from: Vector3 = Vector3.INF
var _nibble_cache_max_m: float = -1.0
var _nibble_cache_at_msec: int = -1000000
var _nibble_cache_result: Vector3 = Vector3.INF
const NIBBLE_CACHE_SEC := 0.4
const NIBBLE_CACHE_MOVE_M := 2.5
var _game_over: bool = false
var _radar_cooldown_left: float = 0.0
var _radar_reveal_left: float = 0.0
var _gem_pickup_accum: float = 0.0
const RADAR_COOLDOWN_SEC := 30.0
## How long all undead stay painted on the minimap after U.
const RADAR_REVEAL_SEC := 12.0
const GEM_PICKUP_INTERVAL_SEC := 0.12
const GEM_PICKUP_REACH_M := 1.35
## How close to a giant's fresh facade strip is close enough to be under it.
const GIANT_DEBRIS_HURT_RADIUS_M := 6.0
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


func _cli_string_flag(flag: String) -> String:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for a: String in args:
		if a.begins_with(flag):
			return a.substr(flag.length())
	return ""


func _cli_float_flag(flag: String, default_value: float) -> float:
	var raw := _cli_string_flag(flag)
	if raw.is_empty():
		return default_value
	if not raw.is_valid_float():
		push_error("CityRoot: %s%s is not a float" % [flag, raw])
		return default_value
	return float(raw)


func _cli_has_flag(flag: String) -> bool:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for a: String in args:
		if a == flag or a.begins_with(flag + "="):
			return true
	return false


## In-game summon + FPS probe: `--auto-summon=big/Orc --auto-summon-offset=28 [--auto-summon-quit]`.
## Verifies shared look/crosshair aim hits ground, then spawns ahead for the FPS sample.
func _cli_auto_summon_probe() -> void:
	var body_id := _cli_string_flag("--auto-summon=")
	if body_id.is_empty():
		return
	if _walker == null or not is_instance_valid(_walker):
		push_error("CityRoot: --auto-summon needs a walker")
		return
	var quit_after := _cli_has_flag("--auto-summon-quit")
	var use_look := _cli_has_flag("--auto-summon-look")
	## Pitch toward the plaza like a player looking at ground; free OS cursor may be anywhere.
	var walker := _walker as CityWalker
	walker._pitch = -0.55
	walker._apply_camera_angles()
	## Let physics/voxel colliders settle under the camera before sampling the shared ray.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var source := (
		CityTargeting.ScreenSource.LOOK_CROSSHAIR
		if use_look
		else CityTargeting.ScreenSource.FREE_CURSOR
	)
	var look_aim := walker.resolve_target(CityTargeting.TargetMode.VOXELS_ONLY, source)
	var look_hit := look_aim.did_hit()
	var look_point := look_aim.point
	print(
		"CityRoot AUTO-SUMMON: look-aim did_hit=%s point=%s (shared meteor/summon ray)"
		% [look_hit, look_point]
	)
	if not look_hit:
		push_error("CityRoot AUTO-SUMMON: look aim missed geometry — shared aim ray broken")
		if quit_after:
			get_tree().quit(1)
		return
	var aim_point := look_point
	_summon_aim = look_aim
	CityProfiler.set_overlay_enabled(true)
	print(
		"CityRoot AUTO-SUMMON: body=%s aim=%s source=%s (player=%s)"
		% [
			body_id,
			aim_point,
			CityTargetingScript.screen_source_name(source),
			_walker.global_position,
		]
	)
	var unit := summon_monster_at_aim(body_id)
	_summon_aim = null
	if unit == null:
		push_error("CityRoot AUTO-SUMMON: spawn failed for '%s'" % body_id)
		if quit_after:
			get_tree().quit(1)
		return
	var flat := Vector2(
		unit.global_position.x - _walker.global_position.x,
		unit.global_position.z - _walker.global_position.z
	).length()
	print(
		"CityRoot AUTO-SUMMON: spawned at %s flat_dist_from_player=%.2fm"
		% [unit.global_position, flat]
	)
	## Baseline a moment after spawn, then sample with the monster ticking.
	CityProfiler.reset_peaks()
	CityProfiler.clear_hitches()
	await get_tree().create_timer(2.5).timeout
	var scopes := PackedStringArray(
		["undead_unit", "undead_nav", "undead_hunt_pick", "building_nibble", "crowd", "nav_queries"]
	)
	CityProfiler.print_scope_report(scopes)
	var frame_ms := CityProfiler.smooth_frame_ms()
	var undead_peak := CityProfiler.scope_peak_ms("undead_unit")
	var nibble_peak := CityProfiler.scope_peak_ms("building_nibble")
	print(
		"CityRoot AUTO-SUMMON: RESULT OK flat_dist=%.2f frame_ms=%.1f undead_unit_peak_ms=%.2f building_nibble_peak_ms=%.2f"
		% [flat, frame_ms, undead_peak, nibble_peak]
	)
	if quit_after:
		get_tree().quit(0)


## Which bound action each `--auto-fire-action=` name presses.
const AUTO_FIRE_BINDS: Dictionary = {
	"beam": "beam",
	"blast": "fire",
	"laser": "laser",
}
## How long the probe waits for the shot to travel and resolve before reading health.
const AUTO_FIRE_SETTLE_SEC := 2.5
## Physics frames the probe gives the streamer to mesh a collider under the spawn point.
const AUTO_FIRE_DECK_TRIES := 240
## Headings tried around the player's facing when looking for level ground in line of sight.
const AUTO_FIRE_YAW_SWEEP_DEG: PackedInt32Array = [
	0, 20, -20, 40, -40, 60, -60, 90, -90, 120, -120, 150, -150, 180
]
## How far the target's deck may sit above or below the player before it counts as a hill.
const AUTO_FIRE_MAX_STEP_M := 1.5
## Physics frames the body gets to land and let navigation stop shoving it around.
const AUTO_FIRE_SETTLE_FRAMES := 30
## Aim passes allowed; the camera's spring arm makes one pass insufficient.
const AUTO_FIRE_AIM_TRIES := 8
## When the crosshair counts as being on the body — a player would call this dead centre.
const AUTO_FIRE_AIM_TOL_DEG := 0.5
## How far the pinned body may drift before the probe puts it back on its mark.
const AUTO_FIRE_PIN_SLACK_M := 0.5
## The shot has to cross real ground to be worth anything; closer than this is not a test.
const AUTO_FIRE_MIN_RANGE_M := 8.0


## Normal-startup probe: no camera changes and no spawned target. Every action enters through its
## real binding, then the exact combat result captured by CityWalker is inspected.
func _cli_startup_fire_probe() -> void:
	if not _cli_has_flag("--startup-fire-probe"):
		return
	var quit_after := _cli_has_flag("--startup-fire-probe-quit")
	if _walker == null or not is_instance_valid(_walker):
		push_error("CityRoot STARTUP-FIRE: no walker")
		if quit_after:
			get_tree().quit(1)
		return
	for _i in range(AUTO_FIRE_DECK_TRIES):
		if not is_splash_open():
			break
		await get_tree().physics_frame
	var walker := _walker as CityWalker
	var camera := walker.get_camera()
	if camera == null:
		push_error("CityRoot STARTUP-FIRE: no camera")
		if quit_after:
			get_tree().quit(1)
		return
	print(
		"CityRoot STARTUP-FIRE: default_pitch=%.4f camera=%s player=%s"
		% [walker._pitch, camera.global_position, walker.global_position]
	)
	var failed := false
	for action: String in ["beam", "blast", "laser"]:
		var previous := walker.last_combat_target()
		_auto_fire_send(action, true, _aim_crosshair(camera))
		if action == "blast":
			await get_tree().create_timer(0.12).timeout
		_auto_fire_send(action, false, _aim_crosshair(camera))
		var wait_sec := 0.45 if action == "blast" else 0.08
		await get_tree().create_timer(wait_sec).timeout
		var result := walker.last_combat_target()
		if result == null or result == previous:
			push_error("CityRoot STARTUP-FIRE: %s produced no combat target" % action)
			failed = true
			continue
		var final_delta := result.point - result.shot_origin
		if final_delta.length_squared() < 0.0001:
			push_error("CityRoot STARTUP-FIRE: %s produced a zero projectile direction" % action)
			failed = true
			continue
		var final_dir := final_delta.normalized()
		var camera_to_muzzle := (
			(result.shot_origin - result.ray_origin).dot(result.ray_direction)
		)
		var camera_hit_from_muzzle := (
			(result.geometry_point - result.shot_origin).dot(result.ray_direction)
			if result.geometry_point.is_finite()
			else INF
		)
		var below_look := final_dir.y - result.ray_direction.y
		print(
			(
				"CityRoot STARTUP-FIRE %s camera_origin=%s muzzle=%s look=%s"
				+ " camera_geometry=%s camera_geom_dist=%.2f camera_to_muzzle_proj=%.2f"
				+ " camera_hit_from_muzzle_proj=%.2f muzzle_geometry=%s muzzle_geom_dist=%.2f"
				+ " muzzle_geom_proj=%.2f muzzle_normal=%s rejected=%s"
				+ " final=%s point=%s dir=%s below_look=%.4f"
			)
			% [
				action,
				result.ray_origin,
				result.shot_origin,
				result.ray_direction,
				result.geometry_point,
				result.geometry_distance,
				camera_to_muzzle,
				camera_hit_from_muzzle,
				result.muzzle_geometry_point,
				result.muzzle_geometry_distance,
				result.muzzle_geometry_projection,
				result.normal,
				result.muzzle_geometry_rejected,
				CityTargetingScript.kind_name(result.kind),
				result.point,
				final_dir,
				below_look,
			]
		)
		if final_dir.dot(result.ray_direction) < 0.95 or below_look < -0.05:
			push_error("CityRoot STARTUP-FIRE: %s redirected below look intent" % action)
			failed = true
		if (
			result.kind == CityTargeting.TargetKind.VOXEL
			and result.muzzle_geometry_distance < AUTO_FIRE_MIN_RANGE_M
			and result.normal.dot(Vector3.UP) > 0.65
		):
			push_error("CityRoot STARTUP-FIRE: %s still targets near deck" % action)
			failed = true
		walker._stop_blaster(true)
		if walker._eye_laser != null:
			walker._eye_laser.call("cancel")
		if walker._charged_blast != null:
			walker._charged_blast.call("cancel")
	print("CityRoot STARTUP-FIRE: RESULT %s" % ("FAILED" if failed else "OK"))
	if quit_after:
		await get_tree().process_frame
		get_tree().quit(1 if failed else 0)


func _aim_crosshair(camera: Camera3D) -> Vector2:
	var rect := camera.get_viewport().get_visible_rect()
	return rect.position + rect.size * 0.5


## In-game blast probe: `--auto-fire=kaykit/Skeleton_Minion [--auto-fire-offset=22]
## [--auto-fire-action=beam|blast|laser] [--auto-fire-hold=0.6] [--auto-fire-quit]`.
##
## Summons one body straight ahead, points the third-person crosshair at its chest, then presses
## the player's own bound button through `Input.parse_input_event` — the shot takes exactly the
## path a hand on the mouse takes, which is the only way to prove the aim in the running game.
## Prints aim origin, direction, resolved target and distances; fails when the body kept its
## health, which is what "the blast always hits the ground" looks like from here.
func _cli_auto_fire_probe() -> void:
	var body_id := _cli_string_flag("--auto-fire=")
	if body_id.is_empty():
		return
	var action := _cli_string_flag("--auto-fire-action=")
	if action.is_empty():
		action = "beam"
	if not AUTO_FIRE_BINDS.has(action):
		push_error("CityRoot AUTO-FIRE: --auto-fire-action=%s is not beam/blast/laser" % action)
		get_tree().quit(1)
		return
	if _walker == null or not is_instance_valid(_walker):
		push_error("CityRoot AUTO-FIRE: needs a walker")
		get_tree().quit(1)
		return
	var walker := _walker as CityWalker
	var offset_m := _cli_float_flag("--auto-fire-offset=", 22.0)
	var hold_sec := _cli_float_flag("--auto-fire-hold=", 0.6)
	var quit_after := _cli_has_flag("--auto-fire-quit")
	## The probe clicks in the same window a player does: as soon as the splash hands back the
	## screen. It must not have to wait out the fade, which is exactly what used to swallow the
	## first shots.
	for _i in range(AUTO_FIRE_DECK_TRIES):
		if not is_splash_open():
			break
		await get_tree().physics_frame
	var locator := await _auto_fire_spawn_target(body_id, offset_m)
	if locator == null:
		if quit_after:
			get_tree().quit(1)
		return
	var requested_spawn := locator.global_position
	_undead.call("unregister_unit", locator)
	locator.queue_free()
	await get_tree().process_frame
	var unit := await _auto_summon_via_panel_at(body_id, requested_spawn)
	if unit == null:
		if quit_after:
			get_tree().quit(1)
		return
	var spawn_error := _last_summon_actual_point.distance_to(
		_last_summon_requested_point + Vector3.UP * 0.06
	)
	var spawn_player_dist := _last_summon_actual_point.distance_to(walker.global_position)
	print(
		"CityRoot AUTO-FIRE: panel spawn requested=%s actual=%s error=%.2fm player_dist=%.2fm"
		% [
			_last_summon_requested_point,
			_last_summon_actual_point,
			spawn_error,
			spawn_player_dist,
		]
	)
	if spawn_error > 1.0 or spawn_player_dist < 20.0:
		push_error("CityRoot AUTO-FIRE: panel summon did not preserve the distant voxel hit")
		if quit_after:
			get_tree().quit(1)
		return
	## This probe measures the player's aim, not monster pathing, so the body stands still where
	## it was placed. Freezing its tick is not enough: navigation teleports a body it decides is
	## trapped, and it lands next to the player, which would turn a 22 m shot into a point-blank
	## one and prove nothing.
	var stand_at := unit.global_position
	unit.set_physics_process(false)
	for _i in range(AUTO_FIRE_SETTLE_FRAMES):
		await get_tree().physics_frame
		if unit.global_position.distance_to(stand_at) > AUTO_FIRE_PIN_SLACK_M:
			unit.global_position = stand_at
	var chest := _auto_fire_chest(unit)
	## The camera rides a colliding spring arm, so one aim pass can leave the crosshair off the
	## body; re-aim at the body's current chest until it is centred.
	for _i in range(AUTO_FIRE_AIM_TRIES):
		chest = _auto_fire_chest(unit)
		await _auto_fire_look_at(walker, chest)
		if _auto_fire_aim_error_deg(walker, _auto_fire_chest(unit)) < AUTO_FIRE_AIM_TOL_DEG:
			break
	chest = _auto_fire_chest(unit)
	var centred := _auto_fire_aim_error_deg(walker, chest)
	if centred > AUTO_FIRE_AIM_TOL_DEG:
		push_error(
			"CityRoot AUTO-FIRE: could not centre the crosshair on the body (%.2f° off)" % centred
		)
		if quit_after:
			get_tree().quit(1)
		return
	print("CityRoot AUTO-FIRE: crosshair centred on the chest to %.2f°" % centred)
	var range_m := walker.global_position.distance_to(chest)
	if range_m < AUTO_FIRE_MIN_RANGE_M:
		push_error(
			"CityRoot AUTO-FIRE: body ended up %.2fm away — too close to prove anything" % range_m
		)
		if quit_after:
			get_tree().quit(1)
		return
	## Nothing draws a reticle, so a player's aim is never exactly on the chest. This tilts the
	## look down by a few degrees to stand in for that, which is when the street deck ends up
	## between the crosshair and the body.
	var aim_low_deg := _cli_float_flag("--auto-fire-aim-low-deg=", 0.0)
	if not is_zero_approx(aim_low_deg):
		walker._pitch = clampf(
			walker._pitch - deg_to_rad(aim_low_deg), walker.pitch_min, walker.pitch_max
		)
		walker._apply_camera_angles()
		await get_tree().physics_frame
		print("CityRoot AUTO-FIRE: crosshair tilted %.1f° below the chest" % aim_low_deg)
	var cam := walker.get_camera()
	if cam == null:
		push_error("CityRoot AUTO-FIRE: walker has no camera")
		get_tree().quit(1)
		return
	var rect := cam.get_viewport().get_visible_rect()
	var crosshair := rect.position + rect.size * 0.5
	var cam_from := cam.project_ray_origin(crosshair)
	var cam_dir := cam.project_ray_normal(crosshair)
	print(
		"CityRoot AUTO-FIRE: action=%s body=%s unit=%s chest=%s dist_from_player=%.2fm"
		% [action, body_id, unit.global_position, chest, walker.global_position.distance_to(chest)]
	)
	var geom := walker.resolve_target(
		CityTargeting.TargetMode.VOXELS_ONLY,
		CityTargeting.ScreenSource.LOOK_CROSSHAIR
	)
	var geom_point := geom.point
	print(
		"CityRoot AUTO-FIRE: cam_from=%s cam_dir=%s geometry_point=%s normal=%s did_hit=%s geom_dist=%.2fm"
		% [
			cam_from,
			cam_dir,
			geom_point,
			geom.normal,
			geom.did_hit(),
			geom.geometry_distance,
		]
	)
	var on_ray := _query_closest_agent_hit(cam_from, cam_from + cam_dir * walker.laser_range_m)
	if on_ray.is_empty():
		print("CityRoot AUTO-FIRE: agent_on_look_ray=no (crosshair misses every body)")
	else:
		print(
			"CityRoot AUTO-FIRE: agent_on_look_ray=%s dist=%.2fm point=%s is_the_target=%s"
			% [
				on_ray["kind"],
				float(on_ray["distance"]),
				on_ray["point"],
				on_ray.get("unit", null) == unit,
			]
		)
	var shot := walker._blaster_shot_endpoints()
	var shot_origin := shot.origin
	var shot_point := shot.target.point
	var target := walker.resolve_target(
		CityTargeting.TargetMode.ACTORS_AND_VOXELS,
		CityTargeting.ScreenSource.LOOK_CROSSHAIR,
		shot_origin
	)
	_print_target_trace("first_fire", target)
	print(
		"CityRoot AUTO-FIRE: resolved target=%s point=%s dist=%.2fm gap_to_chest=%.2fm"
		% [
			CityTargetingScript.kind_name(target.kind),
			target.point,
			target.target_distance(shot_origin),
			target.point.distance_to(chest),
		]
	)
	print(
		"CityRoot AUTO-FIRE: muzzle=%s aim_point=%s dir=%s dist=%.2fm gap_to_chest=%.2fm"
		% [
			shot_origin,
			shot_point,
			(shot_point - shot_origin).normalized(),
			shot_origin.distance_to(shot_point),
			shot_point.distance_to(chest),
		]
	)
	var before := unit.health()
	_auto_fire_send(action, true, crosshair)
	## Projectiles in flight are the receipt that the button reached the walker at all, which is
	## how a swallowed click tells itself apart from a shot that flew wide. Energy cannot do that
	## job: regen refills the few points a burst costs while the probe waits for the hit.
	var shots := 0
	var waited := 0.0
	while waited < maxf(hold_sec, 0.05):
		await get_tree().process_frame
		waited += get_process_delta_time()
		shots = maxi(shots, walker.live_projectile_count())
	_auto_fire_send(action, false, crosshair)
	## The charged blast only leaves the hand on release, so keep counting while it travels.
	waited = 0.0
	while waited < AUTO_FIRE_SETTLE_SEC:
		await get_tree().process_frame
		waited += get_process_delta_time()
		shots = maxi(shots, walker.live_projectile_count())
	var alive := is_instance_valid(unit) and unit.is_alive()
	var after := unit.health() if is_instance_valid(unit) else 0.0
	print(
		"CityRoot AUTO-FIRE: projectiles_in_flight_peak=%d health %.2f → %.2f (delta %.2f) alive=%s"
		% [shots, before, after, before - after, alive]
	)
	if before - after < 0.01:
		if shots == 0:
			push_error(
				"CityRoot AUTO-FIRE: RESULT FAILED — %s never left the player (input or cost path)"
				% action
			)
		else:
			push_error(
				"CityRoot AUTO-FIRE: RESULT FAILED — %s never reached the body %.2fm ahead"
				% [action, walker.global_position.distance_to(chest)]
			)
		if quit_after:
			get_tree().quit(1)
		return
	print(
		"CityRoot AUTO-FIRE: RESULT OK %s took %.2f damage off the %s"
		% [action, before - after, body_id]
	)
	if is_instance_valid(unit) and unit.is_alive():
		## Re-enable the same live body, move the player materially farther away, reacquire it,
		## and repeat the real bound input. This is the user-reported state transition.
		unit.set_physics_process(true)
		var away := walker.global_position - unit.global_position
		away.y = 0.0
		if away.length_squared() < 0.01:
			away = Vector3.BACK
		walker.global_position += away.normalized() * 12.0
		await get_tree().physics_frame
		chest = _auto_fire_chest(unit)
		await _auto_fire_look_at(walker, chest)
		var second_shot := walker._blaster_shot_endpoints()
		var second_origin := second_shot.origin
		var second_target := walker.resolve_target(
			CityTargeting.TargetMode.ACTORS_AND_VOXELS,
			CityTargeting.ScreenSource.LOOK_CROSSHAIR,
			second_origin
		)
		_print_target_trace("farther_fire", second_target)
		print(
			"CityRoot AUTO-FIRE: after_move player=%s mob=%s distance=%.2f final=%s"
			% [
				walker.global_position,
				unit.global_position,
				walker.global_position.distance_to(unit.global_position),
				CityTargetingScript.kind_name(second_target.kind),
			]
		)
		if second_target.kind != CityTargeting.TargetKind.ACTOR:
			push_error("CityRoot AUTO-FIRE: RESULT FAILED — farther reacquire chose geometry")
			if quit_after:
				get_tree().quit(1)
			return
		var before_second := unit.health()
		_auto_fire_send(action, true, crosshair)
		await get_tree().create_timer(maxf(hold_sec, 0.1)).timeout
		_auto_fire_send(action, false, crosshair)
		await get_tree().create_timer(AUTO_FIRE_SETTLE_SEC).timeout
		var after_second := unit.health() if is_instance_valid(unit) else 0.0
		if before_second - after_second < 0.01:
			push_error("CityRoot AUTO-FIRE: RESULT FAILED — farther shot dealt no damage")
			if quit_after:
				get_tree().quit(1)
			return
		print(
			"CityRoot AUTO-FIRE: RESULT OK farther shot actor damage %.2f"
			% (before_second - after_second)
		)
	if quit_after:
		if _undead != null and _undead.has_method("clear_all"):
			_undead.call("clear_all")
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit(0)


func _print_target_trace(label: String, result: CityTargeting.Result) -> void:
	print(
		(
			"CityRoot AUTO-FIRE TARGET %s mode=%s source=%s origin=%s dir=%s"
			+ " geometry=%s geom_dist=%.2f muzzle_geometry=%s muzzle_dist=%.2f"
			+ " muzzle_proj=%.2f rejected=%s actor=%s actor_dist=%.2f final=%s"
		)
		% [
			label,
			CityTargetingScript.mode_name(result.mode),
			CityTargetingScript.screen_source_name(result.screen_source),
			result.ray_origin,
			result.ray_direction,
			result.geometry_point,
			result.geometry_distance,
			result.muzzle_geometry_point,
			result.muzzle_geometry_distance,
			result.muzzle_geometry_projection,
			result.muzzle_geometry_rejected,
			result.actor_point,
			result.actor_distance,
			CityTargetingScript.kind_name(result.kind),
		]
	)


## Live facade probe: `--auto-fire-building [--auto-fire-building-quit]
## [--auto-fire-building-action=beam|blast|laser|all]`.
##
## Finds real building fabric near the player, centres LOOK_CROSSHAIR on the facade, fires the
## shared combat path, and asserts the endpoint is VOXEL on the building — not the street deck
## a few metres under the crosshair.
func _cli_auto_fire_building_probe() -> void:
	if not _cli_has_flag("--auto-fire-building"):
		return
	var quit_after := _cli_has_flag("--auto-fire-building-quit")
	var action_flag := _cli_string_flag("--auto-fire-building-action=")
	if action_flag.is_empty():
		action_flag = "all"
	var actions: PackedStringArray = ["beam", "blast", "laser"]
	if action_flag != "all":
		if not AUTO_FIRE_BINDS.has(action_flag):
			push_error(
				"CityRoot AUTO-FIRE-BUILDING: action must be beam/blast/laser/all, got %s"
				% action_flag
			)
			if quit_after:
				get_tree().quit(1)
			return
		actions = PackedStringArray([action_flag])
	if _walker == null or not is_instance_valid(_walker):
		push_error("CityRoot AUTO-FIRE-BUILDING: no walker")
		if quit_after:
			get_tree().quit(1)
		return
	for _i in range(AUTO_FIRE_DECK_TRIES):
		if not is_splash_open():
			break
		await get_tree().physics_frame
	var walker := _walker as CityWalker
	var facade := await _auto_fire_building_facade_point(walker)
	if not facade.is_finite():
		push_error("CityRoot AUTO-FIRE-BUILDING: no building facade near the player")
		if quit_after:
			get_tree().quit(1)
		return
	print(
		"CityRoot AUTO-FIRE-BUILDING: facade=%s player=%s dist=%.2fm"
		% [facade, walker.global_position, walker.global_position.distance_to(facade)]
	)
	## Soft-aim must not steal the facade for a ped/undead standing in the street.
	if _undead != null and _undead.has_method("clear_all"):
		_undead.call("clear_all")
	await _auto_fire_look_at(walker, facade)
	var cam := walker.get_camera()
	if cam == null:
		push_error("CityRoot AUTO-FIRE-BUILDING: no camera")
		if quit_after:
			get_tree().quit(1)
		return
	var failed := false
	for action: String in actions:
		await _auto_fire_look_at(walker, facade)
		## Lift a few degrees if a living body sits on the look cone between us and the wall.
		var combat := await _auto_fire_building_resolve(walker, facade)
		var crosshair := _aim_crosshair(cam)
		_print_target_trace("building_%s" % action, combat)
		var hand := combat.shot_origin
		if not hand.is_finite():
			hand = (
				walker.global_position
				+ Vector3(0.0, 1.15 * maxf(walker.character_scale, 0.05), 0.0)
			)
		var shot: CityTargeting.ProjectileSolution = walker.call(
			"_combat_projectile_solution", hand, combat, action == "beam"
		) as CityTargeting.ProjectileSolution
		var aim := shot.target.point
		var flat_player := Vector3(walker.global_position.x, 0.0, walker.global_position.z)
		var flat_aim := Vector3(aim.x, 0.0, aim.z)
		var flat_facade := Vector3(facade.x, 0.0, facade.z)
		var along := flat_player.distance_to(flat_aim)
		var facade_gap := aim.distance_to(facade)
		print(
			(
				"CityRoot AUTO-FIRE-BUILDING %s kind=%s aim=%s along_flat=%.2fm"
				+ " facade_gap=%.2fm rejected=%s"
			)
			% [
				action,
				CityTargetingScript.kind_name(combat.kind),
				aim,
				along,
				facade_gap,
				combat.muzzle_geometry_rejected,
			]
		)
		if combat.kind != CityTargeting.TargetKind.VOXEL:
			push_error(
				"CityRoot AUTO-FIRE-BUILDING: RESULT FAILED — %s kind=%s (want VOXEL on facade)"
				% [action, CityTargetingScript.kind_name(combat.kind)]
			)
			failed = true
			continue
		if aim.y < walker.global_position.y - 1.5:
			push_error(
				"CityRoot AUTO-FIRE-BUILDING: RESULT FAILED — %s aim underground %s" % [action, aim]
			)
			failed = true
			continue
		if along < AUTO_FIRE_MIN_RANGE_M:
			push_error(
				(
					"CityRoot AUTO-FIRE-BUILDING: RESULT FAILED — %s dumped into the ground"
					+ " %.2fm ahead (facade hint was %.2fm)"
				)
				% [action, along, flat_player.distance_to(flat_facade)]
			)
			failed = true
			continue
		## Impostor hints can sit past the nearer face the look actually hits. Accept any
		## wall-like VOXEL past min range — the bug is the street dump a few metres ahead.
		if combat.normal.dot(Vector3.UP) > 0.65:
			push_error(
				"CityRoot AUTO-FIRE-BUILDING: RESULT FAILED — %s normal %s is ground-like"
				% [action, combat.normal]
			)
			failed = true
			continue
		if facade_gap > 24.0 and along < 12.0:
			push_error(
				"CityRoot AUTO-FIRE-BUILDING: RESULT FAILED — %s aim %s nowhere near buildings"
				% [action, aim]
			)
			failed = true
			continue
		## Fire through the real binding so VFX / last_combat_target also exercise the path.
		_auto_fire_send(action, true, crosshair)
		var hold := 0.55 if action == "blast" else 0.12
		await get_tree().create_timer(hold).timeout
		_auto_fire_send(action, false, crosshair)
		await get_tree().create_timer(0.35).timeout
		walker._stop_blaster(true)
		if walker._eye_laser != null:
			walker._eye_laser.call("cancel")
		if walker._charged_blast != null:
			walker._charged_blast.call("cancel")
		print("CityRoot AUTO-FIRE-BUILDING: %s OK facade_gap=%.2fm" % [action, facade_gap])
	print("CityRoot AUTO-FIRE-BUILDING: RESULT %s" % ("FAILED" if failed else "OK"))
	if quit_after:
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.15).timeout
		get_tree().quit(1 if failed else 0)


## Resolve combat on the facade; pitch up past any soft-aimed body still in the cone.
func _auto_fire_building_resolve(
	walker: CityWalker, facade: Vector3
) -> CityTargeting.Result:
	var hand := (
		walker.global_position + Vector3(0.0, 1.15 * maxf(walker.character_scale, 0.05), 0.0)
	)
	for attempt in range(5):
		var aim_point := facade + Vector3.UP * (0.6 * float(attempt))
		await _auto_fire_look_at(walker, aim_point)
		var combat := walker.resolve_target(
			CityTargeting.TargetMode.ACTORS_AND_VOXELS,
			CityTargeting.ScreenSource.LOOK_CROSSHAIR,
			hand
		)
		if combat.kind == CityTargeting.TargetKind.VOXEL:
			return combat
	return walker.resolve_target(
		CityTargeting.TargetMode.ACTORS_AND_VOXELS,
		CityTargeting.ScreenSource.LOOK_CROSSHAIR,
		hand
	)


## World point on a nearby building face the player can look at, or INF.
func _auto_fire_building_facade_point(walker: CityWalker) -> Vector3:
	## Remesh lag is real — retry the chest probe while the streamer finishes shells.
	for round_i in range(6):
		for _wait in range(45):
			await get_tree().physics_frame
		var from := walker.global_position
		var hit := _auto_fire_building_chest_probe(from, walker.character_scale)
		if hit.is_finite():
			print(
				"CityRoot AUTO-FIRE-BUILDING: chest probe facade=%s dist=%.2fm (round %d)"
				% [hit, from.distance_to(hit), round_i]
			)
			return hit
		var nibble := find_nearest_building_nibble(from, 56.0)
		if nibble.is_finite():
			var to_player := from - nibble
			to_player.y = 0.0
			if to_player.length_squared() < 0.01:
				to_player = Vector3.BACK
			var face := nibble + to_player.normalized() * 0.4
			face.y = maxf(nibble.y, from.y + 0.8)
			if from.distance_to(face) >= AUTO_FIRE_MIN_RANGE_M:
				print(
					"CityRoot AUTO-FIRE-BUILDING: nibble facade=%s dist=%.2fm (round %d)"
					% [face, from.distance_to(face), round_i]
				)
				return face
	var from := walker.global_position
	var footprints: Array = get_minimap_snapshot(64.0).get("buildings", []) as Array
	footprints.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (
				(a["center"] as Vector3).distance_squared_to(from)
				< (b["center"] as Vector3).distance_squared_to(from)
			)
	)
	for raw in footprints:
		var entry: Dictionary = raw as Dictionary
		var center: Vector3 = entry["center"] as Vector3
		var size: Vector3 = entry.get("size", Vector3(8, 8, 8)) as Vector3
		var to_player := from - center
		to_player.y = 0.0
		if to_player.length_squared() < 0.01:
			continue
		var flat := to_player.normalized()
		var face := center + flat * (maxf(size.x, size.z) * 0.45)
		face.y = from.y + clampf(size.y * 0.35, 1.2, 6.0)
		if from.distance_to(face) < AUTO_FIRE_MIN_RANGE_M:
			continue
		print(
			"CityRoot AUTO-FIRE-BUILDING: impostor facade=%s dist=%.2fm"
			% [face, from.distance_to(face)]
		)
		return face
	print("CityRoot AUTO-FIRE-BUILDING: no facade after retries")
	return Vector3.INF


func _auto_fire_building_chest_probe(from: Vector3, character_scale: float) -> Vector3:
	var chest_y := from.y + 1.35 * maxf(character_scale, 0.05)
	var best := Vector3.INF
	var best_dist := INF
	for deg in range(0, 360, 10):
		var yaw := deg_to_rad(float(deg))
		var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
		var cast_from := Vector3(from.x, chest_y, from.z) + dir * 1.0
		var cast_to := cast_from + dir * 64.0
		var point := Vector3.INF
		var normal := Vector3.UP
		var query := PhysicsRayQueryParameters3D.create(cast_from, cast_to)
		query.collision_mask = 1
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			point = hit["position"] as Vector3
			normal = hit["normal"] as Vector3
		var voxel_hit := probe_destructible_ray(cast_from, cast_to)
		if not voxel_hit.is_empty():
			var vpoint: Vector3 = voxel_hit["point"] as Vector3
			var vdist := from.distance_to(vpoint)
			if not point.is_finite() or vdist + 0.15 < from.distance_to(point):
				if _terrain != null and _tool != null:
					var local := _terrain.to_local(vpoint)
					var vox := Vector3i(floori(local.x), floori(local.y), floori(local.z))
					var id := int(_tool.get_voxel(vox))
					if VoxelMaterial.is_building_fabric(id):
						point = vpoint
						normal = voxel_hit["normal"] as Vector3
		if not point.is_finite():
			continue
		if normal.dot(Vector3.UP) > 0.75:
			continue
		var dist := from.distance_to(point)
		if dist < AUTO_FIRE_MIN_RANGE_M or dist > 56.0:
			continue
		if dist < best_dist:
			best_dist = dist
			best = point
	return best


## Current LOOK_CROSSHAIR hit if it is a wall-like surface past min combat range.
func _auto_fire_building_look_wall(walker: CityWalker) -> Vector3:
	var cam := walker.get_camera()
	if cam == null:
		return Vector3.INF
	var cross := _aim_crosshair(cam)
	var ray_from := cam.project_ray_origin(cross)
	var ray_dir := cam.project_ray_normal(cross)
	var cast_from := ray_from + ray_dir * 1.5
	var cast_to := ray_from + ray_dir * 80.0
	for _i in range(6):
		var query := PhysicsRayQueryParameters3D.create(cast_from, cast_to)
		query.collision_mask = 1
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return Vector3.INF
		var point: Vector3 = hit["position"] as Vector3
		var normal: Vector3 = hit["normal"] as Vector3
		var dist := walker.global_position.distance_to(point)
		var ground_like := (
			normal.dot(Vector3.UP) > 0.65 and point.y < walker.global_position.y - 0.15
		)
		if ground_like:
			cast_from = point + ray_dir * 0.25
			continue
		if dist >= AUTO_FIRE_MIN_RANGE_M and normal.dot(Vector3.UP) <= 0.65:
			return point
		return Vector3.INF
	return Vector3.INF


## Open N through the input map, select the visible panel row, and confirm through the panel's
## real signal path. The free cursor is positioned before N so capture_summon_aim owns the point.
func _auto_summon_via_panel_at(body_id: String, world_point: Vector3) -> UndeadUnit:
	var walker := _walker as CityWalker
	var camera := walker.get_camera()
	if camera == null or camera.is_position_behind(world_point):
		push_error("CityRoot AUTO-FIRE: requested panel spawn is not visible")
		return null
	var before: Array[UndeadUnit] = []
	if _undead != null:
		before = _undead.call("get_alive_units") as Array[UndeadUnit]
	var screen := camera.unproject_position(world_point)
	get_viewport().warp_mouse(screen)
	await get_tree().process_frame
	_auto_send_key_action("monster_summon", true)
	_auto_send_key_action("monster_summon", false)
	await get_tree().process_frame
	if not is_monster_summon_open():
		push_error("CityRoot AUTO-FIRE: real N input did not open summon panel")
		return null
	_monster_summon_panel.call("select_monster_id", body_id)
	_monster_summon_panel.call("confirm_selection")
	await get_tree().process_frame
	var after: Array[UndeadUnit] = _undead.call("get_alive_units") as Array[UndeadUnit]
	for unit: UndeadUnit in after:
		if not before.has(unit):
			return unit
	push_error("CityRoot AUTO-FIRE: panel confirm did not add a monster")
	return null


func _auto_send_key_action(action_id: String, pressed: bool) -> void:
	var ctl := _player_controls()
	if ctl == null:
		push_error("CityRoot AUTO-FIRE: no controls for key action '%s'" % action_id)
		return
	var bind: Dictionary = ctl.call("get_binding", action_id) as Dictionary
	if bind["device"] as String != "key":
		push_error("CityRoot AUTO-FIRE: '%s' is not bound to a key" % action_id)
		return
	var event := InputEventKey.new()
	event.keycode = int(bind["code"]) as Key
	event.physical_keycode = event.keycode
	event.pressed = pressed
	event.shift_pressed = bool(bind["shift"])
	event.ctrl_pressed = bool(bind["ctrl"])
	event.alt_pressed = bool(bind["alt"])
	Input.parse_input_event(event)


## One body standing on the deck `offset_m` away, in a direction the player can actually see it
## from: the probe would otherwise put a monster up a hill or behind a facade and then blame the
## aim for a shot that correctly hit the world. The player is turned to face it.
##
## Terrain colliders around the spawn are still meshing when boot reports playable, so the deck
## ray is retried before the sweep gives up on a heading.
func _auto_fire_spawn_target(body_id: String, offset_m: float) -> UndeadUnit:
	_ensure_undead_director()
	if _undead == null or not _undead.has_method("spawn_monster_by_id"):
		push_error("CityRoot AUTO-FIRE: undead director missing spawn")
		return null
	var reach := maxf(offset_m, 2.0)
	var base_yaw := _walker.rotation.y
	var space := get_world_3d().direct_space_state
	for _i in range(AUTO_FIRE_DECK_TRIES):
		await get_tree().physics_frame
		for step in AUTO_FIRE_YAW_SWEEP_DEG:
			var yaw := base_yaw + deg_to_rad(float(step))
			var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
			var ahead := _walker.global_position + dir * reach
			var down := PhysicsRayQueryParameters3D.create(
				ahead + Vector3.UP * 30.0, ahead - Vector3.UP * 30.0
			)
			down.collision_mask = 1
			var ground := space.intersect_ray(down)
			if ground.is_empty():
				continue
			var at: Vector3 = ground["position"] as Vector3
			## A body more than a storey above or below the player is up a hill or on a roof.
			if absf(at.y - _walker.global_position.y) > AUTO_FIRE_MAX_STEP_M:
				continue
			var eye := _walker.global_position + Vector3.UP * 1.6
			var chest := at + Vector3.UP * 1.2
			var los := PhysicsRayQueryParameters3D.create(eye, chest)
			los.collision_mask = 1
			if not space.intersect_ray(los).is_empty():
				continue
			## A pedestrian in the corridor is a legitimate shield, and a probe that fires
			## through one is measuring the crowd instead of the aim.
			if not _query_closest_agent_hit(eye, chest).is_empty():
				continue
			_walker.set_yaw(yaw)
			var unit := _undead.call("spawn_monster_by_id", body_id, at) as UndeadUnit
			if unit == null:
				push_error(
					"CityRoot AUTO-FIRE: could not summon '%s' %.1fm ahead" % [body_id, offset_m]
				)
			else:
				print(
					"CityRoot AUTO-FIRE: target heading %+.0f° from spawn facing, deck y=%.2f (player y=%.2f)"
					% [rad_to_deg(yaw - base_yaw), at.y, _walker.global_position.y]
				)
			return unit
	push_error(
		"CityRoot AUTO-FIRE: no level deck in line of sight %.1fm away after %d frames"
		% [offset_m, AUTO_FIRE_DECK_TRIES]
	)
	return null


## Where the probe considers the body's centre of mass — the same chest the targeting picks.
func _auto_fire_chest(unit: UndeadUnit) -> Vector3:
	return unit.global_position + Vector3(0.0, unit.hit_half_height() * 0.85, 0.0)


## Angle between the crosshair ray and `target`, in degrees: how far off the body the player's
## look currently is.
func _auto_fire_aim_error_deg(walker: CityWalker, target: Vector3) -> float:
	var cam := walker.get_camera()
	if cam == null:
		push_error("CityRoot AUTO-FIRE: walker has no camera while measuring aim")
		return 180.0
	var rect := cam.get_viewport().get_visible_rect()
	var crosshair := rect.position + rect.size * 0.5
	var from := cam.project_ray_origin(crosshair)
	var dir := cam.project_ray_normal(crosshair)
	var want := target - from
	if want.length_squared() < 0.0001:
		return 0.0
	return rad_to_deg(acos(clampf(want.normalized().dot(dir.normalized()), -1.0, 1.0)))


## Point the crosshair at `target`. The camera rides a spring arm that collides with the world,
## so the pitch that centres a point has no closed form — iterate on the camera's own centre ray.
func _auto_fire_look_at(walker: CityWalker, target: Vector3) -> void:
	var look := target - walker.global_position
	look.y = 0.0
	if look.length_squared() > 0.01:
		walker.set_yaw(atan2(-look.x, -look.z))
	for _i in range(10):
		await get_tree().physics_frame
		var cam := walker.get_camera()
		if cam == null:
			push_error("CityRoot AUTO-FIRE: walker has no camera while aiming")
			return
		var rect := cam.get_viewport().get_visible_rect()
		var crosshair := rect.position + rect.size * 0.5
		var from := cam.project_ray_origin(crosshair)
		var dir := cam.project_ray_normal(crosshair)
		var want := target - from
		if want.length_squared() < 0.01:
			return
		want = want.normalized()
		var err := asin(clampf(want.y, -1.0, 1.0)) - asin(clampf(dir.y, -1.0, 1.0))
		walker._pitch = clampf(walker._pitch + err, walker.pitch_min, walker.pitch_max)
		walker._apply_camera_angles()
		if absf(err) < 0.0005:
			return


## Press or release the real bound button for `action` through the input pipeline.
func _auto_fire_send(action: String, pressed: bool, at: Vector2) -> void:
	var ctl := _player_controls()
	if ctl == null:
		push_error("CityRoot AUTO-FIRE: no player controls to read the binding from")
		return
	var bind_id := str(AUTO_FIRE_BINDS[action])
	var bind: Dictionary = ctl.call("get_binding", bind_id) as Dictionary
	var device := str(bind.get("device", ""))
	if device == "mouse":
		var mb := InputEventMouseButton.new()
		mb.button_index = int(bind["code"]) as MouseButton
		mb.pressed = pressed
		mb.position = at
		mb.global_position = at
		mb.shift_pressed = bool(bind["shift"])
		mb.ctrl_pressed = bool(bind["ctrl"])
		mb.alt_pressed = bool(bind["alt"])
		Input.parse_input_event(mb)
		print(
			"CityRoot AUTO-FIRE: %s %s (%s)"
			% [bind_id, "press" if pressed else "release", PlayerControls.format_binding(bind)]
		)
		return
	if device != "key":
		push_error("CityRoot AUTO-FIRE: '%s' is bound to device '%s'" % [bind_id, device])
		return
	var ke := InputEventKey.new()
	ke.keycode = int(bind["code"]) as Key
	ke.physical_keycode = ke.keycode
	ke.pressed = pressed
	ke.shift_pressed = bool(bind["shift"])
	ke.ctrl_pressed = bool(bind["ctrl"])
	ke.alt_pressed = bool(bind["alt"])
	Input.parse_input_event(ke)
	print(
		"CityRoot AUTO-FIRE: %s %s (%s)"
		% [bind_id, "press" if pressed else "release", PlayerControls.format_binding(bind)]
	)


## Physics frames the walk probe gives the splash before it starts pressing keys.
const AUTO_WALK_BOOT_FRAMES := 1200
## Metres the failsafe deck rides below the feet (CityWalker._update_safety_deck).
const AUTO_WALK_DECK_DROP_M := 8.0
## How far the deck may sit from the feet on a frame the walker wrote it.
const AUTO_WALK_DECK_TOL_M := 0.01
## Worst axis drift the deck basis may show: turning must not rotate or stretch the box.
const AUTO_WALK_BASIS_TOL := 0.0001
## Longest unsupported stretch that still reads as walking over a lip rather than falling.
const AUTO_WALK_MAX_AIR_SEC := 2.0
## How far below its starting ground the player may get before it has fallen out of the world.
const AUTO_WALK_MAX_DROP_M := 30.0
## Seconds the probe lets the body settle before it reads the standing state it spawned in.
const AUTO_WALK_SETTLE_SEC := 1.5


## In-game walk probe: `--auto-walk [--auto-walk-leg-sec=3] [--auto-walk-shot=res://tools/w.png]
## [--auto-walk-quit]`.
##
## Holds the player's own bound movement keys through `Input.parse_input_event` and watches what
## holds the body up while it walks, turns, sprints, jumps and resizes: floor contact, water,
## step-ups, how far it sinks, and where the failsafe deck under it ends up. The deck is a child
## of the walker with `top_level` on, so the two failures worth catching are a deck that stopped
## tracking the feet and a deck that turns or stretches with the body — neither of which a
## headless RID count can see, which is why this has to run rendered.
func _cli_auto_walk_probe() -> void:
	if not _cli_has_flag("--auto-walk"):
		return
	if _walker == null or not is_instance_valid(_walker):
		push_error("CityRoot AUTO-WALK: needs a walker")
		get_tree().quit(1)
		return
	var walker := _walker as CityWalker
	var leg_sec := _cli_float_flag("--auto-walk-leg-sec=", 3.0)
	var shot_path := _cli_string_flag("--auto-walk-shot=")
	var quit_after := _cli_has_flag("--auto-walk-quit")
	for _i in range(AUTO_WALK_BOOT_FRAMES):
		if not is_splash_open():
			break
		await get_tree().physics_frame
	var deck := walker.get_node_or_null("SafetyDeck") as StaticBody3D
	if deck == null:
		push_error(
			"CityRoot AUTO-WALK: the walker owns no SafetyDeck child — it would outlive the body"
		)
		if quit_after:
			get_tree().quit(1)
		return
	print(
		"CityRoot AUTO-WALK: deck owner=%s top_level=%s layer=%d walker_mask=%d"
		% [deck.get_parent().name, deck.top_level, deck.collision_layer, walker.collision_mask]
	)

	var start := walker.global_position
	var settled := 0.0
	while settled < AUTO_WALK_SETTLE_SEC:
		await get_tree().physics_frame
		settled += get_physics_process_delta_time()
	print(
		"CityRoot AUTO-WALK: spawn on_ground=%s swimming=%s y %.3f → %.3f (sank %.3fm in %.1fs) deck=%s"
		% [
			walker.is_supported(),
			walker.is_swimming(),
			start.y,
			walker.global_position.y,
			start.y - walker.global_position.y,
			AUTO_WALK_SETTLE_SEC,
			deck.global_position,
		]
	)
	if not walker.is_supported():
		push_error(
			"CityRoot AUTO-WALK: RESULT FAILED — nothing holds the player up at spawn (y=%.3f)"
			% walker.global_position.y
		)
		if quit_after:
			get_tree().quit(1)
		return

	## `airborne_ok` marks the one leg that is meant to leave the ground: holding the jump key
	## keeps rising for as long as it is held, so its air time is the feature, not a fall.
	## Only the resizing legs carry a `scale`; the rest walk at whatever size the last one left.
	var legs: Array[Dictionary] = [
		{"what": "stand still", "keys": PackedStringArray(), "airborne_ok": false},
		{"what": "walk forward", "keys": PackedStringArray(["move_forward"]), "airborne_ok": false},
		{
			"what": "sprint forward",
			"keys": PackedStringArray(["move_forward", "sprint"]),
			"airborne_ok": false,
		},
		{
			"what": "forward + turn left",
			"keys": PackedStringArray(["move_forward", "turn_left"]),
			"airborne_ok": false,
		},
		{
			"what": "forward + turn right",
			"keys": PackedStringArray(["move_forward", "turn_right"]),
			"airborne_ok": false,
		},
		{"what": "turn in place", "keys": PackedStringArray(["turn_left"]), "airborne_ok": false},
		{"what": "walk back", "keys": PackedStringArray(["move_back"]), "airborne_ok": false},
		{
			"what": "jump while walking",
			"keys": PackedStringArray(["move_forward", "jump"]),
			"airborne_ok": true,
		},
		{"what": "land after the jump", "keys": PackedStringArray(), "airborne_ok": false},
		## A giant and a mouse walk on the same deck; resizing must not scale the box with them.
		{
			"what": "walk forward as a giant",
			"keys": PackedStringArray(["move_forward"]),
			"airborne_ok": false,
			"scale": 2.5,
		},
		{
			"what": "walk forward shrunk",
			"keys": PackedStringArray(["move_forward"]),
			"airborne_ok": false,
			"scale": 0.4,
		},
		{
			"what": "walk forward back at full size",
			"keys": PackedStringArray(["move_forward"]),
			"airborne_ok": false,
			"scale": 1.0,
		},
	]
	var worst_air := 0.0
	var worst_deck_off := 0.0
	var worst_basis := 0.0
	var lowest_y := walker.global_position.y
	var supported_frames := 0
	var swim_frames := 0
	var step_frames := 0
	var total_frames := 0
	var stale_frames := 0
	for leg: Dictionary in legs:
		if leg.has("scale"):
			walker.set_character_scale(float(leg["scale"]), true)
		var stat := await _auto_walk_leg(
			walker, deck, str(leg["what"]), leg["keys"] as PackedStringArray, leg_sec
		)
		if not bool(leg["airborne_ok"]):
			worst_air = maxf(worst_air, float(stat["worst_air_sec"]))
		worst_deck_off = maxf(worst_deck_off, float(stat["worst_deck_off_m"]))
		worst_basis = maxf(worst_basis, float(stat["worst_basis_err"]))
		lowest_y = minf(lowest_y, float(stat["lowest_y"]))
		supported_frames += int(stat["supported_frames"])
		swim_frames += int(stat["swim_frames"])
		step_frames += int(stat["step_frames"])
		total_frames += int(stat["frames"])
		stale_frames += int(stat["stale_frames"])

	var deck_box := (deck.get_child(0) as CollisionShape3D).shape as BoxShape3D
	var errors_shown := _auto_walk_errors_on_screen()
	print(
		"CityRoot AUTO-WALK: on ground %d/%d frames · in water %d · stepped up %d · worst unintended airborne %.2fs · fell to y=%.2f (spawn %.2f) · deck off by ≤%.4fm (%d frames one tick behind) · deck basis drift ≤%.6f · box %s · errors on screen %d"
		% [
			supported_frames,
			total_frames,
			swim_frames,
			step_frames,
			worst_air,
			lowest_y,
			start.y,
			worst_deck_off,
			stale_frames,
			worst_basis,
			deck_box.size,
			errors_shown,
		]
	)
	if not shot_path.is_empty():
		await _auto_walk_screenshot(shot_path)

	var verdict := ""
	if worst_air > AUTO_WALK_MAX_AIR_SEC:
		verdict = "the player was in free fall for %.2fs — the ground stopped holding it" % worst_air
	elif start.y - lowest_y > AUTO_WALK_MAX_DROP_M:
		verdict = (
			"the player sank %.2fm below its spawn ground — it fell through the world"
			% (start.y - lowest_y)
		)
	elif worst_basis > AUTO_WALK_BASIS_TOL:
		verdict = (
			"the failsafe deck turned or stretched with the body (axis drift %.6f)" % worst_basis
		)
	elif worst_deck_off > AUTO_WALK_DECK_TOL_M:
		verdict = "the failsafe deck drifted %.4fm off the feet" % worst_deck_off
	elif not (walker.is_supported() or walker.is_swimming()):
		verdict = "the player ended the run unsupported at y=%.3f" % walker.global_position.y
	if not verdict.is_empty():
		push_error("CityRoot AUTO-WALK: RESULT FAILED — %s" % verdict)
		if quit_after:
			get_tree().quit(1)
		return
	print(
		"CityRoot AUTO-WALK: RESULT OK the player stood and walked supported over %d frames"
		% total_frames
	)
	if quit_after:
		get_tree().quit(0)


## Hold `keys` for `seconds` and report what held the body up. Keys: frames, supported_frames,
## swim_frames, step_frames, stale_frames, worst_air_sec, lowest_y, worst_deck_off_m,
## worst_basis_err.
func _auto_walk_leg(
	walker: CityWalker,
	deck: StaticBody3D,
	what: String,
	keys: PackedStringArray,
	seconds: float
) -> Dictionary:
	var drop := Vector3(0.0, AUTO_WALK_DECK_DROP_M, 0.0)
	var from := walker.global_position
	var prev_feet := from
	var frames := 0
	var supported_frames := 0
	var swim_frames := 0
	var step_frames := 0
	var stale_frames := 0
	var air_sec := 0.0
	var worst_air := 0.0
	var lowest_y := from.y
	var worst_deck_off := 0.0
	var worst_basis := 0.0
	for key in keys:
		_auto_walk_hold(key, true)
	var waited := 0.0
	while waited < maxf(seconds, 0.05):
		await get_tree().physics_frame
		var step := get_physics_process_delta_time()
		waited += step
		frames += 1
		var feet := walker.global_position
		lowest_y = minf(lowest_y, feet.y)
		## Water holds the body up as legitimately as ground does — the walker's own locomotion
		## counts a swim as not airborne, so a probe that called it a fall would fail on a pond.
		if walker.is_supported():
			supported_frames += 1
			air_sec = 0.0
		elif walker.is_swimming():
			swim_frames += 1
			air_sec = 0.0
		else:
			air_sec += step
			worst_air = maxf(worst_air, air_sec)
		if walker.has_stepped_up():
			step_frames += 1
		worst_basis = maxf(worst_basis, _auto_walk_basis_error(deck.global_transform.basis))
		## The deck has to be where the walker last wrote it. Leaving a climb returns out of
		## `_physics_climb` before `_update_safety_deck`, so on those frames the deck is still
		## on the previous tick's feet — counted, but not drift. Anything further off is a deck
		## that stopped tracking the body at all.
		var off_now := deck.global_position.distance_to(feet - drop)
		var off_prev := deck.global_position.distance_to(prev_feet - drop)
		if off_now > AUTO_WALK_DECK_TOL_M and off_prev <= AUTO_WALK_DECK_TOL_M:
			stale_frames += 1
		worst_deck_off = maxf(worst_deck_off, minf(off_now, off_prev))
		prev_feet = feet
	for key in keys:
		_auto_walk_hold(key, false)
	print(
		"CityRoot AUTO-WALK: %-32s ground %3d/%3d · swim %3d · stepped up %3d · moved %5.2fm · y %.2f→%.2f (low %.2f) · air ≤%.2fs · deck ≤%.4fm (%d behind) basis ≤%.6f"
		% [
			what,
			supported_frames,
			frames,
			swim_frames,
			step_frames,
			from.distance_to(walker.global_position),
			from.y,
			walker.global_position.y,
			lowest_y,
			worst_air,
			worst_deck_off,
			stale_frames,
			worst_basis,
		]
	)
	return {
		"frames": frames,
		"supported_frames": supported_frames,
		"swim_frames": swim_frames,
		"step_frames": step_frames,
		"stale_frames": stale_frames,
		"worst_air_sec": worst_air,
		"lowest_y": lowest_y,
		"worst_deck_off_m": worst_deck_off,
		"worst_basis_err": worst_basis,
	}


## Press or release the real bound key for a movement action, the way a hand on the keyboard does.
func _auto_walk_hold(action_id: String, pressed: bool) -> void:
	var ctl := _player_controls()
	if ctl == null:
		push_error("CityRoot AUTO-WALK: no player controls to read the binding from")
		return
	var bind: Dictionary = ctl.call("get_binding", action_id) as Dictionary
	var device := str(bind.get("device", ""))
	if device != "key":
		push_error("CityRoot AUTO-WALK: '%s' is bound to device '%s'" % [action_id, device])
		return
	var ke := InputEventKey.new()
	ke.keycode = int(bind["code"]) as Key
	ke.physical_keycode = ke.keycode
	ke.pressed = pressed
	Input.parse_input_event(ke)


## Worst axis drift between `b` and the world axes: 0 means unrotated and unscaled.
func _auto_walk_basis_error(b: Basis) -> float:
	return maxf(
		maxf(b.x.distance_to(Vector3.RIGHT), b.y.distance_to(Vector3.UP)),
		b.z.distance_to(Vector3.BACK)
	)


## How many errors the in-game overlay is showing — a rendered run's own error report.
func _auto_walk_errors_on_screen() -> int:
	var overlay := get_node_or_null("/root/ErrorOverlay")
	if overlay == null:
		push_error("CityRoot AUTO-WALK: the ErrorOverlay autoload is missing")
		return -1
	return int(overlay.get("_visible_count"))


func _auto_walk_screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("CityRoot AUTO-WALK: no viewport image for %s" % path)
		return
	var saved := img.save_png(path)
	if saved != OK:
		push_error("CityRoot AUTO-WALK: could not save %s (error %d)" % [path, saved])
		return
	print("CityRoot AUTO-WALK: SAVED %s" % path)


func _pick_spawn_district_random() -> Vector2i:
	## Stable for a given world seed so --city-seed=N also replays the spawn tile.
	var rng := RandomNumberGenerator.new()
	rng.seed = DistrictCoord.feature_seed(city_seed, 0x53504E)  ## "SPN"
	return Vector2i(
		rng.randi_range(-SPAWN_DISTRICT_RING, SPAWN_DISTRICT_RING),
		rng.randi_range(-SPAWN_DISTRICT_RING, SPAWN_DISTRICT_RING)
	)


## Resolves the spawn tile: CLI coord, --spawn-theme search, or seeded RNG. No start modal.
func _resolve_spawn_district() -> Vector2i:
	var forced: Variant = _cli_spawn_district()
	if forced is Vector2i:
		spawn_theme_id = DistrictTheme.for_district(city_seed, forced as Vector2i).id
		return forced as Vector2i

	var theme_id := _cli_spawn_theme()
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


func is_inventory_open() -> bool:
	return _inventory_panel != null and bool(_inventory_panel.call("is_open"))


func is_monster_summon_open() -> bool:
	return _monster_summon_panel != null and bool(_monster_summon_panel.call("is_open"))


## True while a panel of this root's owns the screen. The walker and the build bar read this to
## stop taking hotkeys, and the HUD band is hidden for as long as it holds. The walker's own
## character editor is not in here: nothing would tell us when it closes again.
func is_modal_open() -> bool:
	return is_settings_open() or is_inventory_open() or is_monster_summon_open()


## True while the splash covers the world — boot, a hop in flight, and the J picker. It is a
## screen takeover rather than a modal, but gameplay input has to stop at it just the same:
## parking the walker only stops walking, and the meteor, build and cabinet keys all kept
## firing into the city behind the open picker.
func is_splash_open() -> bool:
	return _loading_splash != null and bool(_loading_splash.call("owns_screen"))


func _is_character_editor_open() -> bool:
	if _walker == null or not is_instance_valid(_walker):
		return false
	return bool(_walker.call("is_character_editor_open"))


## The HUD is on screen only while play is running and nothing owns the screen. Covering it is
## not enough: every modal dim is translucent, so a HUD left up bleeds through the panel.
func _set_hud_enabled(enabled: bool) -> void:
	_hud_enabled = enabled
	_refresh_hud_visibility()


func _refresh_hud_visibility() -> void:
	var show_hud := _hud_enabled and not is_modal_open()
	for child in get_children():
		var canvas := child as CanvasLayer
		if canvas == null:
			continue
		if canvas.layer >= UiLayers.HUD_MIN and canvas.layer <= UiLayers.HUD_MAX:
			canvas.visible = show_hud
	if _settings_panel != null:
		_settings_panel.call(
			"set_top_bar_visible", not is_inventory_open() and not is_monster_summon_open()
		)


func get_inventory() -> PlayerInventory:
	return _inventory


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
	_loading_splash.call("show_splash", "Loading EccentriCity…")

	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "HudLayer"
	_hud_layer.layer = UiLayers.HUD_STATS
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

	_health_hud = PlayerHealthHudScript.new()
	_health_hud.name = "PlayerHealthHud"
	add_child(_health_hud)

	_undead_hud = UndeadInvasionHudScript.new()
	_undead_hud.name = "UndeadInvasionHud"
	add_child(_undead_hud)

	_minimap = CityMinimapScript.new()
	_minimap.name = "CityMinimap"
	add_child(_minimap)
	_minimap.call("bind_city", self)

	_nav_overlay = NavDebugOverlayScript.new() as NavDebugOverlay
	_nav_overlay.name = "NavDebugOverlay"
	add_child(_nav_overlay)

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

	_inventory_panel = PlayerInventoryPanelScript.new()
	_inventory_panel.name = "PlayerInventory"
	add_child(_inventory_panel)
	_inventory_panel.call("bind_inventory", _inventory)
	_inventory_panel.opened.connect(_on_inventory_opened)
	_inventory_panel.closed.connect(_on_inventory_closed)
	_inventory_panel.craft_requested.connect(_on_inventory_craft_requested)

	_monster_summon_panel = MonsterSummonPanelScript.new()
	_monster_summon_panel.name = "MonsterSummon"
	add_child(_monster_summon_panel)
	_monster_summon_panel.opened.connect(_on_monster_summon_opened)
	_monster_summon_panel.closed.connect(_on_monster_summon_closed)
	_monster_summon_panel.summon_requested.connect(_on_monster_summon_requested)
	## Apply saved / default knobs once the viewport exists.
	call_deferred("_on_settings_applied", _settings_panel.get_settings())
	call_deferred("_apply_saved_controls")


func _build_game_over_overlay() -> void:
	_game_over_layer = CanvasLayer.new()
	_game_over_layer.name = "GameOverOverlay"
	_game_over_layer.layer = UiLayers.GAME_OVER
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
	if is_inventory_open():
		_inventory_panel.call("close_panel")
	if is_monster_summon_open():
		_monster_summon_panel.call("close_panel")
	_refresh_hud_visibility()
	if _walker != null and is_instance_valid(_walker):
		_walker.release_capture()


func _on_settings_closed() -> void:
	_refresh_hud_visibility()
	if is_inventory_open() or is_monster_summon_open():
		return
	if _walker != null and is_instance_valid(_walker):
		_walker._set_capture(true)


func _on_inventory_opened() -> void:
	if is_settings_open():
		_settings_panel.call("close_panel")
	if is_monster_summon_open():
		_monster_summon_panel.call("close_panel")
	_refresh_hud_visibility()
	if _walker != null and is_instance_valid(_walker):
		_walker.release_capture()


func _on_inventory_closed() -> void:
	_refresh_hud_visibility()
	if is_settings_open() or is_monster_summon_open():
		return
	if _walker != null and is_instance_valid(_walker):
		_walker._set_capture(true)


func _on_monster_summon_opened() -> void:
	if is_settings_open():
		_settings_panel.call("close_panel")
	if is_inventory_open():
		_inventory_panel.call("close_panel")
	_refresh_hud_visibility()
	if _walker != null and is_instance_valid(_walker):
		_walker.release_capture()


func _on_monster_summon_closed() -> void:
	## Cancel clears a pending look-aim; confirm already consumed it in summon_monster_at_aim.
	_summon_aim = null
	_refresh_hud_visibility()
	if is_settings_open() or is_inventory_open():
		return
	if _walker != null and is_instance_valid(_walker):
		_walker._set_capture(true)


func _on_monster_summon_requested(monster_id: String) -> void:
	var body_id := monster_id
	if body_id.is_empty():
		body_id = _roll_random_summon_id()
		if body_id.is_empty():
			push_error("CityRoot: Random summon has an empty spawnable roster")
			assert(false, "CityRoot: empty summon roster")
			return
	var unit := summon_monster_at_aim(body_id)
	_summon_aim = null
	if unit == null:
		## Miss is a quiet cancel inside summon_monster_at_aim; hard failures already push_error.
		return
	print("CityRoot: summoned %s at %s" % [body_id, unit.global_position])


func _roll_random_summon_id() -> String:
	var ids: PackedStringArray = MonsterSummonPanelScript.summonable_ids()
	if ids.is_empty():
		return ""
	return ids[randi_range(0, ids.size() - 1)]


## Sample the free cursor's voxel-only aim before the summon panel moves that cursor onto its UI.
func capture_summon_aim() -> void:
	_summon_aim = null
	if _walker == null or not is_instance_valid(_walker):
		push_error("CityRoot.capture_summon_aim: no walker")
		return
	var walker := _walker as CityWalker
	var aim: CityTargeting.Result = walker.resolve_target(
		CityTargeting.TargetMode.VOXELS_ONLY, CityTargeting.ScreenSource.FREE_CURSOR
	)
	_summon_aim = aim
	var point: Vector3 = aim.point
	var player := get_player_position()
	print(
		(
			"CityRoot TARGET mode=%s source=%s origin=%s dir=%s geometry=%s geom_dist=%.2f"
			+ " actor=%s actor_dist=%.2f final=%s voxel=%s"
		)
		% [
			CityTargetingScript.mode_name(aim.mode),
			CityTargetingScript.screen_source_name(aim.screen_source),
			aim.ray_origin,
			aim.ray_direction,
			point,
			aim.geometry_distance,
			aim.actor_point,
			aim.actor_distance,
			CityTargetingScript.kind_name(aim.kind),
			aim.voxel,
		]
	)
	if player != Vector3.INF and point.is_finite():
		print("CityRoot: summon captured distance_from_player=%.1fm" % player.distance_to(point))


## Spawn at the free-cursor voxel hit captured when N opened. A tiny upward clearance keeps the
## body's feet out of the hit surface; there is no feet/ring/nav fallback on a true miss.
func summon_monster_at_aim(body_id: String) -> UndeadUnit:
	if _game_over or _booting:
		return null
	if _walker == null or not is_instance_valid(_walker):
		push_error("CityRoot.summon_monster_at_aim: no walker")
		return null
	var aim := _summon_aim
	if aim == null:
		var walker := _walker as CityWalker
		aim = walker.resolve_target(
			CityTargeting.TargetMode.VOXELS_ONLY, CityTargeting.ScreenSource.FREE_CURSOR
		)
	if not aim.did_hit():
		print("CityRoot: summon cancelled — free-cursor voxel aim missed")
		return null
	if aim.mode != CityTargeting.TargetMode.VOXELS_ONLY:
		push_error("CityRoot.summon_monster_at_aim: cached aim is not VOXELS_ONLY")
		assert(false, "CityRoot: contaminated summon aim")
	_ensure_undead_director()
	if _undead == null or not _undead.has_method("spawn_monster_by_id"):
		push_error("CityRoot.summon_monster_at_aim: undead director missing spawn")
		assert(false, "CityRoot: no spawn_monster_by_id")
		return null
	const BODY_CLEARANCE_M := 0.06
	var requested := aim.point
	var pos := requested + Vector3.UP * BODY_CLEARANCE_M
	_last_summon_requested_point = requested
	_last_summon_actual_point = Vector3.INF
	_last_summoned_unit = null
	var player := get_player_position()
	print(
		"CityRoot: spawn requested=%s actual_request=%s player=%s flat_dist=%.1fm body=%s"
		% [
			requested,
			pos,
			player,
			Vector2(pos.x - player.x, pos.z - player.z).length() if player != Vector3.INF else -1.0,
			body_id,
		]
	)
	var unit := _undead.call("spawn_monster_by_id", body_id, pos) as UndeadUnit
	if unit != null:
		_last_summoned_unit = unit
		_last_summon_actual_point = unit.global_position
		print("CityRoot: spawn actual=%s requested_voxel_hit=%s" % [unit.global_position, requested])
	return unit


func _on_inventory_craft_requested(recipe_id: String) -> void:
	if _inventory == null:
		return
	if not _inventory.craft(recipe_id):
		push_error("CityRoot: craft failed for '%s'" % recipe_id)
		return
	print("CityRoot: crafted %s" % recipe_id)


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

	CityProfiler.set_file_logging(bool(settings.get("hitch_log", false)), settings)


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
	CityProfiler.begin("city_root")
	_fps_accum += delta
	_infection_stream_accum += delta
	_gem_pickup_accum += delta
	CityProfiler.begin("underground")
	_sync_underground_lighting()
	CityProfiler.end("underground")
	if _gem_pickup_accum >= GEM_PICKUP_INTERVAL_SEC:
		_gem_pickup_accum = 0.0
		CityProfiler.begin("gem_pickup")
		_try_collect_nearby_gems()
		CityProfiler.end("gem_pickup")
	if _radar_cooldown_left > 0.0:
		_radar_cooldown_left = maxf(0.0, _radar_cooldown_left - delta)
	if _radar_reveal_left > 0.0:
		_radar_reveal_left = maxf(0.0, _radar_reveal_left - delta)
	if _infection_stream_accum >= 0.5:
		_infection_stream_accum = 0.0
		CityProfiler.begin("infection_stream")
		_invalidate_infection_outside_bubble()
		CityProfiler.end("infection_stream")
	if _spawn_meteors_enabled and _walker != null and is_instance_valid(_walker):
		_meteor_spawn_accum += delta
		if _meteor_spawn_accum >= _meteor_spawn_interval_sec:
			_meteor_spawn_accum = 0.0
			_roll_meteor_spawn_interval()
			CityProfiler.begin("meteor_spawn")
			_try_auto_spawn_meteor()
			CityProfiler.end("meteor_spawn")
	CityProfiler.end("city_root")
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
		_brush = null

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
	## Y must cover offline nav bake height + link_reach_y headroom. Painted volumes use
	## 16-voxel blocks (e.g. top row 223) and rebuild_y_range adds ~6 sky rows above that;
	## a 220-tall ceiling left dirty rebuilds short of the band and NativeNavWorld refused.
	_terrain.bounds = AABB(Vector3(-20000, 0, -20000), Vector3(40000, 256, 40000))
	## Ceiling only — must fit a district half-diagonal (~482 vox) so data-only
	## anchors can make the full tile editable. Player viewers stay shorter below.
	_terrain.max_view_distance = 512
	_terrain.generate_collisions = true
	_tool = _terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	## Gameplay edits are already in world voxel space, so no origin offset.
	_brush = CityBrushScript.new(_tool) as CityBrush
	CityProfiler.set_terrain(_terrain)


## The one brush every live voxel write goes through. Connect to its
## `voxels_changed(aabb_vox)` to react to world mutation — that is the seam the
## nav span/portal rebuild (and nav_version invalidation) hangs off. Valid only
## after boot; regenerating the world replaces it, so re-connect on each terrain.
func voxel_brush() -> CityBrush:
	return _brush


## The live terrain, for consumers that move bodies against voxel data rather than edit it —
## VoxelBoxMover needs the node itself, not the tool. Valid only after boot; regenerating the
## world replaces it, so re-read it on each terrain.
func voxel_terrain() -> VoxelTerrain:
	return _terrain


func _ensure_gem_lights(camera: Camera3D) -> void:
	if _gem_lights != null and is_instance_valid(_gem_lights):
		_gem_lights.queue_free()
		_gem_lights = null
	_gem_lights = GemLightDirectorScript.new()
	_gem_lights.name = "GemLightDirector"
	add_child(_gem_lights)
	_gem_lights.call("setup", _tool, camera, _streamer)


func _sync_underground_lighting() -> void:
	var under := 0.0
	if _walker != null and is_instance_valid(_walker) and _walker.has_method("get_underground_factor"):
		under = float(_walker.call("get_underground_factor"))
	if _day_night != null and is_instance_valid(_day_night) and _day_night.has_method("set_underground_factor"):
		_day_night.call("set_underground_factor", under)
	if _gem_lights != null and is_instance_valid(_gem_lights) and _gem_lights.has_method("set_underground"):
		_gem_lights.call("set_underground", under > 0.5)


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
	_infection.call("setup", _terrain, _tool, _brush, VOXEL_SIZE, 6)
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


func get_gem_count(mat_id: int) -> int:
	var item_id := InventoryCatalog.item_id_for_gem(mat_id)
	if item_id == "":
		return 0
	return _inventory.count_of(item_id)


## All gem tallies keyed by VoxelMaterial.GEM_* — empty entries omitted.
func get_gem_counts() -> Dictionary:
	var out: Dictionary = {}
	for mat_id in range(VoxelMaterial.GEM_QUARTZ, VoxelMaterial.GEM_DIAMOND + 1):
		var n := get_gem_count(mat_id)
		if n > 0:
			out[mat_id] = n
	return out


## Remove one gem voxel and credit the inventory. Returns false if it is gone already.
func try_collect_gem_at(vox: Vector3i) -> bool:
	if _tool == null:
		return false
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var mat_id := int(_tool.get_voxel(vox))
	if not VoxelMaterial.is_gem(mat_id):
		return false
	var item_id := InventoryCatalog.item_id_for_gem(mat_id)
	if item_id == "":
		return false
	_brush.set_vox(vox, VoxelMaterial.AIR)
	var leftover := _inventory.add(item_id, 1)
	if leftover != 0:
		push_error("CityRoot: inventory full — gem %s could not be stored" % item_id)
	if _audio != null and _audio.has_method("play_gem_pickup"):
		var local := Vector3(float(vox.x) + 0.5, float(vox.y) + 0.5, float(vox.z) + 0.5)
		var world := _terrain.to_global(local) if _terrain != null else local * VOXEL_SIZE
		_audio.call("play_gem_pickup", world, mat_id)
	return true


## Walk-up pickup: any gem within arm's reach of the chest is taken.
func _try_collect_nearby_gems() -> void:
	if _tool == null or _terrain == null or not is_player_alive():
		return
	var scale := 1.0
	if _walker.has_method("get_character_scale"):
		scale = maxf(float(_walker.call("get_character_scale")), 0.5)
	var reach_m := GEM_PICKUP_REACH_M * scale
	var chest := get_player_target_position()
	var local := _terrain.to_local(chest)
	var r_vox := int(ceil(reach_m / VOXEL_SIZE))
	var r2 := (reach_m / VOXEL_SIZE) * (reach_m / VOXEL_SIZE)
	var cx := int(floor(local.x))
	var cy := int(floor(local.y))
	var cz := int(floor(local.z))
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	for z in range(cz - r_vox, cz + r_vox + 1):
		for y in range(cy - r_vox, cy + r_vox + 1):
			for x in range(cx - r_vox, cx + r_vox + 1):
				var center := Vector3(float(x) + 0.5, float(y) + 0.5, float(z) + 0.5)
				if center.distance_squared_to(local) > r2 + 0.0001:
					continue
				var id := int(_tool.get_voxel(Vector3i(x, y, z)))
				if VoxelMaterial.is_gem(id):
					try_collect_gem_at(Vector3i(x, y, z))


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


## Hurt the player. Returns the points actually taken, which is zero when the run is already
## over or the hit found nobody to hurt.
##
## The only route from an enemy to the player's health, so the game-over screen has exactly one
## place it can come from: this drains the pool, the pool tells the walker it is empty, and the
## walker's signal brings us back here to `_on_player_health_depleted`. Nothing else calls
## `trigger_game_over` for damage any more.
func damage_player(source: DamageSource.Id) -> float:
	return damage_player_scaled(source, 1.0)


## Same as `damage_player`, with a body's resolved `damage_mult` applied to the table amount.
func damage_player_scaled(source: DamageSource.Id, scale: float) -> float:
	if not is_player_alive():
		return 0.0
	if DamageSourceScript.target(source) != DamageSourceScript.Target.PLAYER:
		push_error(
			"CityRoot: %s hurts creatures, not the player"
			% DamageSourceScript.source_name(source)
		)
		return 0.0
	return float(_walker.call("take_damage_scaled", source, scale))


func _on_player_health_depleted(source: DamageSource.Id) -> void:
	trigger_game_over(DamageSourceScript.death_reason(source))


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


## Open the district-type picker, then hop to the nearest matching tile (J by default).
func request_district_hop() -> bool:
	if _game_over or _booting or _district_hopping:
		return false
	if _walker == null or not is_instance_valid(_walker):
		return false
	if _streamer == null or not is_instance_valid(_streamer):
		return false
	if _loading_splash == null:
		push_error("CityRoot: district hop needs LoadingSplash for the type picker")
		return false
	_district_hopping = true
	_district_hop_pick_async()
	return true


func _district_hop_pick_async() -> void:
	var walker := _walker
	if walker == null or not is_instance_valid(walker):
		_district_hopping = false
		return
	var origin_pos := walker.global_position
	_set_hud_enabled(false)
	walker.set_physics_process(false)
	walker.velocity = Vector3.ZERO
	var theme_id: int = int(
		await _loading_splash.call(
			"prompt_district_choice",
			"Jump to District",
			"Pick a type — we'll teleport you to the nearest matching tile.",
			"Choose a district type"
		)
	)
	if theme_id < 0 or theme_id >= DistrictTheme.COUNT:
		await _finish_district_hop_fail("no district type chosen", origin_pos)
		return
	var dest := DistrictTheme.find_coord_for_theme(city_seed, theme_id)
	var theme := DistrictTheme.for_district(city_seed, dest)
	if theme.id != theme_id:
		await _finish_district_hop_fail(
			"no %s tile found nearby" % DistrictTheme.make(theme_id).display_name,
			origin_pos
		)
		return
	await _district_hop_to(dest, origin_pos)


func _district_hop_to(dest: Vector2i, origin_pos: Vector3) -> void:
	var walker := _walker
	if walker == null or not is_instance_valid(walker):
		_district_hopping = false
		return
	var here := DistrictCoord.from_world(origin_pos, VOXEL_SIZE)
	var theme := DistrictTheme.for_district(city_seed, dest)
	print(
		"CityRoot: district hop %s → %s (%s)"
		% [here, dest, theme.display_name]
	)
	_set_hud_enabled(false)
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
	_set_hud_enabled(true)
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
	if not _booting:
		_set_hud_enabled(true)
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
	_set_hud_enabled(false)
	## Splash while the spawn district bakes — no type picker at boot.
	if _loading_splash != null:
		_loading_splash.call("show_splash", "Loading EccentriCity…")
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
	_inventory.clear()
	_gem_pickup_accum = 0.0
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
	if _health_hud != null and is_instance_valid(_health_hud):
		_health_hud.call("clear_display")
	if _undead_hud != null and is_instance_valid(_undead_hud):
		_undead_hud.call("clear_display")
	if _minimap != null and is_instance_valid(_minimap):
		_minimap.call("bind_city", self)
	## The overlay's follow target and every corridor it drew belong to the old world.
	if _nav_overlay != null and is_instance_valid(_nav_overlay):
		_nav_overlay.set_enabled(false)
		_nav_overlay.bind_follow(null)
		_nav_overlay.bind_aim_provider(Callable())
	if _cascade != null and is_instance_valid(_cascade):
		_cascade.clear_debris()
		_cascade.queue_free()
		_cascade = null
	if _gem_lights != null and is_instance_valid(_gem_lights):
		_gem_lights.queue_free()
		_gem_lights = null
	if _debris_root != null and is_instance_valid(_debris_root):
		_debris_root.queue_free()
		_debris_root = null

	_create_terrain()
	_ensure_cascade_debris()
	await get_tree().process_frame
	await get_tree().process_frame

	## Before the streamer exists: the spawn district promotes its first pedestrians and cars
	## while the splash is still up, and those must already be warm.
	await _warm_visual_pipelines()

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
	_walker.health_depleted.connect(_on_player_health_depleted)
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
	_ensure_gem_lights(cam)
	_nav_overlay.bind_follow(_walker)
	_nav_overlay.bind_aim_provider(_nav_overlay_aim)

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
	_set_hud_enabled(true)
	if _loading_splash != null:
		_loading_splash.call("hide_splash")
	elif _status != null:
		_status.visible = false
	_action_bar = PlayerActionBarScript.new()
	_action_bar.name = "PlayerActionBar"
	add_child(_action_bar)
	_action_bar.setup(_walker)
	_action_bar.build_requested.connect(_on_build_chosen)
	## It joins the HUD band after the band was last refreshed, so it would otherwise stay up
	## over a panel opened while the spawn district was still baking.
	_refresh_hud_visibility()
	if _energy_hud != null and is_instance_valid(_energy_hud):
		_energy_hud.call("bind_walker", _walker)
	if _health_hud != null and is_instance_valid(_health_hud):
		_health_hud.call("bind_walker", _walker)
	if _settings_panel != null:
		_on_settings_applied(_settings_panel.get_settings())
		_apply_saved_controls()
	if _undead_invasion_enabled:
		_ensure_undead_director()
		_undead.call("set_enabled", true)
		if _undead_hud != null and is_instance_valid(_undead_hud):
			_undead_hud.call("bind_director", _undead)
	print(
		"CityRoot: playable — endless stream active at y=%.2f (F1–F6 = build · M = meteor · N = summon · Y = day/night · T = tetris)"
		% floor_y
	)
	call_deferred("_cli_auto_summon_probe")
	call_deferred("_cli_startup_fire_probe")
	call_deferred("_cli_auto_fire_probe")
	call_deferred("_cli_auto_fire_building_probe")
	call_deferred("_cli_auto_walk_probe")


## A pedestrian or car visual pays two one-off costs the first time it appears: reading its
## scene, and compiling the material pipeline when the mesh is first drawn (measured at
## 113 ms mid-game). Both are paid here instead, behind the opaque splash: every outfit is
## drawn for a few frames, and the scenes stay referenced for the session so later loads are
## resource-cache hits.
func _warm_visual_pipelines() -> void:
	## The dummy renderer compiles nothing, and its mesh storage is a stub.
	if DisplayServer.get_name() == "headless":
		return
	CityProfiler.note_event("visual_warmup")
	if _status != null:
		_status.text = "Warming pedestrian and traffic visuals…"
	var holder := Node3D.new()
	holder.name = "VisualWarmup"
	add_child(holder)
	## The player camera does not exist yet, and a frustum-culled mesh is never drawn — so it
	## would compile nothing and the warm-up would be silently useless. Stage the whole set
	## high above the city in front of a throwaway wide-angle camera instead.
	var base := Vector3(0.0, WARMUP_ALTITUDE_M, 0.0)
	var cam := Camera3D.new()
	cam.name = "WarmupCamera"
	cam.fov = 75.0
	holder.add_child(cam)
	cam.global_position = base + Vector3(0.0, 6.0, 30.0)
	cam.look_at(base + Vector3(0.0, 1.0, -7.0), Vector3.UP)
	cam.make_current()

	var outfits := PedOutfitCatalog.all_outfits()
	for i in outfits.size():
		var outfit := outfits[i]
		var packed := load(outfit.scene_path) as PackedScene
		if packed == null:
			push_error("CityRoot: outfit scene failed to load: %s" % outfit.scene_path)
			continue
		_warm_scenes.append(packed)
		var visual := CrowdPedVisual.new()
		visual.name = "WarmPed_%d" % i
		holder.add_child(visual)
		visual.bind_agent(i, outfit.female, 1.0, outfit)
		visual.global_position = base + Vector3(
			float(i) - float(outfits.size() - 1) * 0.5, 0.0, 0.0
		)

	## Traffic is procedural per profile, so each catalog entry builds its own materials.
	VehicleCatalog.ensure_loaded()
	if not VehicleCatalog.is_ready() or VehicleCatalog.count() <= 0:
		push_error("CityRoot: vehicle catalog unavailable — car pipelines stay cold")
	var cars := VehicleCatalog.count()
	for i in cars:
		var car := VehicleVisual.new()
		car.name = "WarmCar_%d" % i
		holder.add_child(car)
		## Passengers only on the first: they are outfit scenes, already warm by now.
		car.setup(VehicleCatalog.entry_at(i), 2 if i == 0 else 0, 11 + i)
		if not car.ready_visual:
			push_error("CityRoot: warm-up car visual failed to build for entry %d" % i)
		var col := i % 5
		var row := i / 5
		car.sync_pose(
			base + Vector3((float(col) - 2.0) * 3.2, 0.0, -8.0 - float(row) * 6.0), 0.0
		)

	## Pipelines compile on the render thread, so give it real frames to draw in.
	for _frame in WARMUP_FRAMES:
		await get_tree().process_frame
	holder.queue_free()
	print("CityRoot: warmed %d outfit scenes + %d cars" % [_warm_scenes.size(), cars])


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
	var local := _terrain.to_local(hit_position)
	var radius_vox := maxf(radius_m, 0.25) / VOXEL_SIZE
	## Revert any tip in the blast first; restored fabric then takes the carve normally.
	_tip_kill_leads_in_sphere(local, radius_vox)
	_brush.begin_edit()
	_carve_destructible_sphere(local, radius_vox)
	_restore_bedrock_floor(local, radius_vox)
	_brush.end_edit()
	_notify_tetris_damage()
	_notify_destruction(hit_position, maxf(radius_m * 4.0, 28.0))


## Charged LMB bomb (and stomp): carve + outward tumble debris, then cascade columns above.
func apply_charged_blast(hit_world: Vector3, radius_m: float) -> void:
	if _tool == null or _terrain == null:
		return
	CityProfiler.begin("voxel_blast")
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
	var detached: Array = []
	var column_max_y: Dictionary = {}  # Vector2i → int
	const MAX_DEBRIS := 900
	_brush.begin_edit()
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
				_brush.set_vox(vox, VoxelMaterial.AIR)
	_restore_bedrock_floor(local, radius_vox)
	_brush.end_edit()
	CityProfiler.end("voxel_blast")
	if _cascade != null:
		## Primary blast voxels fly outward from the impact.
		if _cascade.has_method("detach_blast_voxels"):
			CityProfiler.begin("cascade_detach")
			_cascade.call("detach_blast_voxels", detached, hit_world)
			CityProfiler.end("cascade_detach")
		## Fabric still standing above the hole cascades like melee.
		for col_key in column_max_y.keys():
			var xz: Vector2i = col_key
			var max_y: int = int(column_max_y[col_key])
			_cascade_column_above(Vector3i(xz.x, max_y, xz.y))
	BlastFlashVfxScript.spawn(self, hit_world, radius)
	_notify_tetris_damage(detached)
	_notify_destruction(hit_world, maxf(radius * 5.0, 32.0))


## Drop whatever still stands above a fresh hole — unless it is soft soil/turf.
## Stone and cave fabric cascade; dirt / gravel / park / grave soil do not.
func _cascade_column_above(top_vox: Vector3i) -> void:
	if _cascade == null or not is_instance_valid(_cascade):
		return
	if not _cascade.has_method("collapse_column_above"):
		return
	var above := int(_tool.get_voxel(Vector3i(top_vox.x, top_vox.y + 1, top_vox.z)))
	if VoxelMaterial.is_self_supporting_terrain(above):
		return
	CityProfiler.begin("cascade")
	_cascade.collapse_column_above(top_vox)
	CityProfiler.end("cascade")


## Q stomp: same destruction as a max-charge blast at the feet (anim/FX differ on the walker).
##
## The stomp used to hurt nothing living at all — it carved a crater and the skeleton standing in
## it walked out. It is an area attack, so it hits everything in the crater and always did look
## like it should.
func _on_stomp(feet_position: Vector3, radius_m: float) -> void:
	apply_area_damage(feet_position, radius_m, DamageSourceScript.Id.PLAYER_STOMP)
	apply_charged_blast(feet_position, radius_m)


## Every creature inside the sphere takes one hit. Returns how many were reached.
##
## Area attacks cannot go through `_apply_agent_hit`: that answers "the nearest body along a
## line", which for a two-metre blast sphere in a wave of skeletons is one skeleton.
func apply_area_damage(center: Vector3, radius: float, source: DamageSource.Id) -> int:
	if radius <= 0.0:
		push_error("CityRoot: an area attack of radius %f reaches nothing" % radius)
		return 0
	if _undead == null or not is_instance_valid(_undead):
		return 0
	return int(_undead.call("damage_units_in_sphere", center, radius, source))


func _on_melee_strike(
	origin: Vector3, direction: Vector3, max_range_m: float, source: DamageSource.Id
) -> void:
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
	## Bodies take priority over voxel fabric along the same strike: a punch that lands on a
	## skeleton is not also a punch into the wall behind it, which is the whole of how damage
	## stays out of the carving path — one strike is one or the other, never both.
	if _apply_agent_hit(origin, end, dir, source):
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
	var hit_gem := false
	for i in range(1, steps + 1):
		var p := local_origin + dir * (float(i) * step)
		var v := Vector3i(int(floor(p.x)), int(floor(p.y)), int(floor(p.z)))
		if found and v == hit_vox:
			continue
		var id := int(_tool.get_voxel(v))
		if VoxelMaterial.is_gem(id):
			hit_vox = v
			found = true
			hit_gem = true
			break
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
	## Punching a gem (or a gem in the fist sphere) collects it — gems never carve.
	if hit_gem:
		try_collect_gem_at(hit_vox)
	## Revert tips in the punch sphere first; then the strike carves restored fabric as usual.
	_tip_kill_leads_in_sphere(hit_center, radius_vox)
	var r_i := int(ceil(radius_vox))
	var r2 := radius_vox * radius_vox
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
				if VoxelMaterial.is_gem(mat_id):
					try_collect_gem_at(vox)
					continue
				if not VoxelMaterial.is_destructible(mat_id):
					continue
				detached.append({"vox": vox, "mat": mat_id})
				var col := Vector2i(x, z)
				if column_max_y.has(col):
					column_max_y[col] = maxi(int(column_max_y[col]), y)
				else:
					column_max_y[col] = y

	if hit_gem and detached.is_empty():
		return

	_brush.begin_edit()
	for entry in detached:
		_brush.set_vox(entry["vox"] as Vector3i, VoxelMaterial.AIR)
	_brush.end_edit()

	if _cascade == null:
		return
	var hit_world := _terrain.to_global(
		Vector3(float(hit_vox.x) + 0.5, float(hit_vox.y) + 0.5, float(hit_vox.z) + 0.5)
	)
	## Punch sphere is already AIR — spawn debris immediately (same as blast).
	if _cascade.has_method("detach_blast_voxels"):
		CityProfiler.begin("cascade_detach")
		_cascade.call("detach_blast_voxels", detached, hit_world)
		CityProfiler.end("cascade_detach")
	elif _cascade.has_method("detach_voxels"):
		CityProfiler.begin("cascade_detach")
		_cascade.detach_voxels(detached)
		CityProfiler.end("cascade_detach")
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
	var walker := _walker as CityWalker
	var aim: CityTargeting.Result = walker.resolve_target(
		CityTargeting.TargetMode.VOXELS_ONLY, CityTargeting.ScreenSource.FREE_CURSOR
	)
	if not aim.did_hit():
		return
	var hit: Vector3 = aim.point
	var written: int = BuildPlacerScript.place(
		_terrain, _tool, _brush, recipe, hit, _walker.global_position
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
	if _walker == null or not is_instance_valid(_walker):
		push_error("CityRoot: cannot spawn Tetris without the walker that gates its keys")
		return
	var walker := _walker as CityWalker
	if _tetris != null and is_instance_valid(_tetris):
		if _tetris.has_method("clear_shell"):
			_tetris.call("clear_shell")
		_tetris.queue_free()
		_tetris = null
	## Old cabinet players lose their machine.
	_clear_tetris_peds()
	var face_yaw := 0.0
	var to_player := get_player_position() - hit_point
	to_player.y = 0.0
	if to_player.length_squared() > 0.01:
		face_yaw = atan2(-to_player.x, -to_player.z)
	else:
		face_yaw = walker.rotation.y + PI
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
	_tetris.call("begin", _terrain, _tool, _brush, walker, hit_point, face_yaw, VOXEL_SIZE)


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
	meteor.call("begin", _terrain, _tool, _brush, hit_point, 55.0)


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
	var ped := find_nearest_ped_only(from, max_dist)
	if ped != Vector3.INF:
		var d2 := Vector2(ped.x - from.x, ped.z - from.z).length_squared()
		if d2 <= best_d2:
			best = ped
	return best


## Nearest crowd pedestrian only — never the player. Used when prey_weights separate the two.
func find_nearest_ped_only(from: Vector3, max_dist: float) -> Vector3:
	var best := Vector3.INF
	var best_d2 := max_dist * max_dist
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


## Nearest living undead/monster other than `except_unit`. Vector3.INF when none in range.
func find_nearest_monster_position(
	from: Vector3, max_dist: float, except_unit: UndeadUnit = null
) -> Vector3:
	if _undead == null or not is_instance_valid(_undead) or not _undead.has_method("get_alive_units"):
		return Vector3.INF
	var best := Vector3.INF
	var best_d2 := max_dist * max_dist
	var units: Array = _undead.call("get_alive_units") as Array
	for entry in units:
		var unit := entry as UndeadUnit
		if unit == null or not is_instance_valid(unit) or not unit.is_alive():
			continue
		if except_unit != null and unit == except_unit:
			continue
		var d2 := Vector2(
			unit.global_position.x - from.x, unit.global_position.z - from.z
		).length_squared()
		if d2 > best_d2:
			continue
		best_d2 = d2
		best = unit.global_position
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
##
## An orb used to end the run outright. It now takes a quarter of the pool, so the fourth one
## converts you and the first three are a reason to leave the street.
func try_orb_hit_player(world_pos: Vector3, radius: float) -> bool:
	if not is_player_alive():
		return false
	var ppos := get_player_target_position()
	var hit_r := radius + 0.45 * float(_walker.get_character_scale())
	if world_pos.distance_squared_to(ppos) > hit_r * hit_r:
		return false
	damage_player(DamageSourceScript.Id.UNDEAD_ORB)
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


## One-shot remove a pedestrian in reach (monster melee vs ped prey). No health pool — peds
## stay instantly removable. Returns the former world position, or null when nobody was there.
func try_kill_ped_near(world_pos: Vector3, radius: float) -> Variant:
	if _streamer == null or not _streamer.has_method("get_loaded_districts"):
		return null
	var best_crowd: CrowdDirector = null
	var best_agent: PedAgent = null
	var best_pos := Vector3.INF
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
		best_pos = pos
	if best_crowd == null or best_agent == null:
		return null
	var away := best_pos - world_pos
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = Vector3.FORWARD
	if not best_crowd.kill_agent(best_agent, best_pos, away.normalized()):
		return null
	return best_pos


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
	var removed := 0
	var scrape_center := Vector3(float(hit.x) + 0.5, float(hit.y) + 0.5, float(hit.z) + 0.5)
	_tip_kill_leads_in_sphere(scrape_center, 8.0)
	_brush.begin_edit()
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
				_brush.set_vox(vox, VoxelMaterial.AIR)
				removed += 1
	_brush.end_edit()
	if removed <= 0:
		return 0
	adjust_player_score(-removed)
	var world_hit := _terrain.to_global(
		Vector3(float(hit.x) + 0.5, float(hit.y) + 0.5, float(hit.z) + 0.5)
	)
	if _cascade != null and is_instance_valid(_cascade):
		if _cascade.has_method("detach_blast_voxels") and not detached.is_empty():
			CityProfiler.begin("cascade_detach")
			_cascade.call("detach_blast_voxels", detached, world_hit)
			CityProfiler.end("cascade_detach")
	_notify_tetris_damage(detached)
	_notify_destruction(world_hit, 36.0)
	_damage_player_in_debris(world_hit)
	return removed


## Standing under a facade a giant is peeling. Giants take many hits now, which only makes them
## a threat if they can answer — this is the answer, and it is positional rather than aimed: a
## tenth of the pool per strip, and the counter is to not be there.
func _damage_player_in_debris(world_hit: Vector3) -> void:
	if not is_player_alive():
		return
	if _walker.global_position.distance_to(world_hit) > GIANT_DEBRIS_HURT_RADIUS_M:
		return
	damage_player(DamageSourceScript.Id.GIANT_DEBRIS)


## Minion bite: remove one nearby building voxel (−1 score). No cascade.
func undead_nibble_building_near(world_pos: Vector3, reach_m: float) -> bool:
	if _terrain == null or _tool == null:
		return false
	var vox := _find_building_vox_near(world_pos, reach_m)
	if vox == Vector3i(2147483647, 2147483647, 2147483647):
		return false
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var mat_id := int(_tool.get_voxel(vox))
	_brush.set_vox(vox, VoxelMaterial.AIR)
	adjust_player_score(-1)
	var world := _terrain.to_global(Vector3(float(vox.x) + 0.5, float(vox.y) + 0.5, float(vox.z) + 0.5))
	_notify_tetris_damage([{"vox": vox, "mat": mat_id}])
	_notify_destruction(world, 10.0)
	return true


## World position of a nearby building fabric voxel, or Vector3.INF.
## Results are short-TTL cached — the ring scan can exceed a frame at aggro ranges.
func find_nearest_building_nibble(from: Vector3, max_dist: float) -> Vector3:
	CityProfiler.begin("building_nibble")
	var now := Time.get_ticks_msec()
	if (
		now - _nibble_cache_at_msec < int(NIBBLE_CACHE_SEC * 1000.0)
		and is_equal_approx(_nibble_cache_max_m, max_dist)
		and _nibble_cache_from != Vector3.INF
		and from.distance_to(_nibble_cache_from) <= NIBBLE_CACHE_MOVE_M
	):
		CityProfiler.add_counter("building_nibble_cache_hit")
		CityProfiler.end("building_nibble")
		return _nibble_cache_result
	var vox := _find_building_vox_near(from, max_dist)
	var result := Vector3.INF
	if vox != Vector3i(2147483647, 2147483647, 2147483647):
		result = _terrain.to_global(
			Vector3(float(vox.x) + 0.5, float(vox.y) + 0.5, float(vox.z) + 0.5)
		)
	_nibble_cache_from = from
	_nibble_cache_max_m = max_dist
	_nibble_cache_at_msec = now
	_nibble_cache_result = result
	CityProfiler.end("building_nibble")
	return result


func _find_building_vox_near(from: Vector3, max_dist: float) -> Vector3i:
	const SENTINEL := Vector3i(2147483647, 2147483647, 2147483647)
	if _terrain == null or _tool == null:
		return SENTINEL
	var local := _terrain.to_local(from)
	var max_vox := maxi(int(ceil(max_dist / VOXEL_SIZE)), 2)
	## Hard cap — aggro/leash values (80–110 m) at 0.5 m voxels are hundreds of rings and
	## millions of reads; undead only need a nearby facade, not a city-wide flood.
	## 32 rings × 0.5 m ≈ 16 m; taller floors still covered by DY_SCAN.
	const MAX_RINGS := 32
	const DY_SCAN := 28
	max_vox = mini(max_vox, MAX_RINGS)
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
				for dy in range(0, DY_SCAN):
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
	_brush.begin_edit()
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
				_brush.set_vox(vox, VoxelMaterial.AIR)
				removed += 1
	_brush.end_edit()
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
			_brush.set_vox(vox, prev_mat if prev_mat >= 0 else VoxelMaterial.METEOR_ROCK)
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
	_brush.begin_edit()
	for z in range(-r, r + 1):
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if x * x + y * y + z * z > r * r + 1:
					continue
				var vox := impact_vox + Vector3i(x, y, z)
				if int(_tool.get_voxel(vox)) == VoxelMaterial.METEOR_ROCK:
					_brush.set_vox(vox, VoxelMaterial.STONE)
	_brush.end_edit()


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


## How far off the look direction a creature may stand and still be what the player is aiming
## at. Nothing draws a reticle, so the aim is a guess about the middle of the screen; a hard ray
## through that guess misses a body by metres at combat range, which is why the blast used to
## land in the street. Roughly an eighth of the 70° field of view.
const COMBAT_AIM_CONE_DEG := 9.0
## Slack on the muzzle line-of-sight ray. The deck the body stands on is allowed to clip the
## last stretch of it; a wall further back is not.
const COMBAT_LOS_SLACK_M := 1.0


## Actor phase of CityWalker.resolve_target(ACTORS_AND_VOXELS). Geometry remains in `result`
## as the fallback and for diagnostics; it never vetoes a visible actor merely because the
## third-person camera ray grazed the street first.
func resolve_actor_target(
	result: CityTargeting.Result, shot_origin: Vector3, reach_m: float
) -> void:
	if result == null:
		push_error("CityRoot.resolve_actor_target: null result")
		assert(false, "CityRoot: null targeting result")
		return
	if result.mode != CityTargeting.TargetMode.ACTORS_AND_VOXELS:
		push_error("CityRoot.resolve_actor_target: result mode is not ACTORS_AND_VOXELS")
		assert(false, "CityRoot: actor resolution in voxel-only mode")
	if result.ray_direction.length_squared() < 0.0001:
		push_error("CityRoot.resolve_actor_target: look direction is zero")
		return
	var look := result.ray_direction.normalized()
	var range_m := maxf(reach_m, 1.0)
	## Straight on-ray hit first: whatever the player is actually pointing through wins, ped or
	## car included, and it is the only way those two stay targetable at all.
	var on_ray := _query_closest_agent_hit(
		result.ray_origin, result.ray_origin + look * range_m
	)
	if not on_ray.is_empty():
		var on_ray_point: Vector3 = on_ray["point"] as Vector3
		if _muzzle_sees(shot_origin, on_ray_point):
			_set_actor_target(result, on_ray_point, shot_origin, _actor_from_hit(on_ray))
			return
	var soft := _closest_creature_in_cone(
		result.ray_origin, look, range_m, shot_origin
	)
	if not soft.is_empty():
		_set_actor_target(
			result,
			soft["point"] as Vector3,
			shot_origin,
			soft["unit"] as Node3D
		)


## Chest of the living creature nearest the centre of the look cone with a clear muzzle line,
## or INF. Candidates are walked centre-out, so a wall in front of the best one hands the shot
## to the next instead of dropping straight to geometry.
func _closest_creature_in_cone(
	cam_from: Vector3,
	look: Vector3,
	range_m: float,
	shot_origin: Vector3
) -> Dictionary:
	if _undead == null or not is_instance_valid(_undead):
		return {}
	if not _undead.has_method("get_alive_units"):
		push_error("CityRoot.resolve_actor_target: undead director cannot list its units")
		return {}
	var units: Array[UndeadUnit] = _undead.call("get_alive_units") as Array[UndeadUnit]
	var cone := deg_to_rad(COMBAT_AIM_CONE_DEG)
	var ranked: Array[Dictionary] = []
	for unit: UndeadUnit in units:
		if unit == null or not is_instance_valid(unit):
			continue
		## Aim above capsule centre. At long range a centre-to-centre line can graze the street
		## even though the body is fully visible; upper torso remains inside the hit capsule.
		var chest := unit.global_position + Vector3.UP * unit.hit_half_height() * 1.2
		var to_body := chest - cam_from
		var dist := to_body.length()
		if dist < 0.05 or dist > range_m:
			continue
		var angle := acos(clampf(to_body.dot(look) / dist, -1.0, 1.0))
		## The body is not a point: its own width earns tolerance, which matters up close where
		## a fixed cone is only centimetres wide.
		var margin := angle - atan(unit.hit_radius() / dist)
		if margin > cone:
			continue
		ranked.append({"margin": margin, "point": chest, "unit": unit})
	ranked.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["margin"]) < float(b["margin"])
	)
	for row in ranked:
		var chest: Vector3 = row["point"] as Vector3
		if _muzzle_sees(shot_origin, chest):
			return row
	return {}


## True when nothing solid stands between the muzzle and `point`.
func _muzzle_sees(from: Vector3, point: Vector3) -> bool:
	if not from.is_finite():
		push_error("CityRoot.resolve_actor_target: muzzle origin is not finite")
		return false
	var dist := from.distance_to(point)
	if dist < 0.05:
		return true
	## Lift the visibility probe by a palm-width. The projectile still starts at the real muzzle,
	## but a deck touching the hand must not masquerade as a wall across a 30 m torso shot.
	var probe_lift := Vector3.UP * 0.12
	var query := PhysicsRayQueryParameters3D.create(from + probe_lift, point + probe_lift)
	## Terrain and buildings only. Bodies live on layer 2 and must never shadow each other here.
	query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	return (from + probe_lift).distance_to(hit["position"] as Vector3) >= (
		dist - COMBAT_LOS_SLACK_M
	)


func _set_actor_target(
	result: CityTargeting.Result,
	point: Vector3,
	shot_origin: Vector3,
	actor: Node3D
) -> void:
	result.kind = CityTargeting.TargetKind.ACTOR
	result.point = point
	result.actor_point = point
	result.actor_distance = shot_origin.distance_to(point)
	result.actor = actor


func _actor_from_hit(hit: Dictionary) -> Node3D:
	var kind: String = hit["kind"] as String
	match kind:
		"undead":
			return hit["unit"] as Node3D
		"ped", "vehicle":
			## Their query agents are data objects rather than scene nodes.
			return null
	push_error("CityRoot._actor_from_hit: unknown actor kind '%s'" % kind)
	assert(false, "CityRoot: unknown actor kind")
	return null


## True when the shot landed on a body along the segment (no voxel carve).
##
## `source` is which of the player's attacks arrived, because a creature now cares: the eye laser
## chips a monster the fist would have to hit twice.
func apply_laser_agent_hit(
	from: Vector3,
	to: Vector3,
	direction: Vector3,
	source: DamageSource.Id,
	creatures: bool = true
) -> bool:
	var dir := direction
	if dir.length_squared() < 0.0001:
		dir = (to - from)
	if dir.length_squared() < 0.0001:
		return false
	return _apply_agent_hit(from, to, dir.normalized(), source, creatures)


## Mid-flight probe: distance along from→tip to the nearest agent, or -1.
func laser_probe_agent_distance(from: Vector3, tip: Vector3) -> float:
	var hit := _query_closest_agent_hit(from, tip)
	if hit.is_empty():
		return -1.0
	return float(hit["distance"])


## Pedestrians and cars stay one-hit: they are scenery that screams, not opponents, and giving a
## commuter a health bar would mean a laser dart that only annoys them. Creatures take `source`
## through the director and decide for themselves whether that was fatal.
##
## `creatures` is false for the area attacks, whose sphere pass has already hit every body with
## health in the blast — this pass is then only there to still flatten the ped and flip the car.
func _apply_agent_hit(
	from: Vector3,
	to: Vector3,
	direction: Vector3,
	source: DamageSource.Id,
	creatures: bool = true
) -> bool:
	if DamageSourceScript.target(source) != DamageSourceScript.Target.CREATURE:
		push_error(
			"CityRoot: %s hurts the player, not agents" % DamageSourceScript.source_name(source)
		)
		return false
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
		if not creatures:
			return false
		var undead: Node = hit["undead"]
		var unit: Node = hit["unit"]
		ok = bool(undead.call("damage_unit", unit, source))
	if ok:
		_notify_destruction(point, 34.0)
	return ok


func _query_closest_agent_hit(from: Vector3, to: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := INF
	## Peds/cars need loaded districts; undead live on CityRoot and must still aim without them.
	if _streamer != null and _streamer.has_method("get_loaded_districts"):
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
	_brush.begin_edit()
	for z in range(cz - r_i, cz + r_i + 1):
		for y in range(cy - r_i, cy + r_i + 1):
			for x in range(cx - r_i, cx + r_i + 1):
				var center := Vector3(float(x) + 0.5, float(y) + 0.5, float(z) + 0.5)
				if center.distance_squared_to(local_center) > r2 + 0.0001:
					continue
				var vox := Vector3i(x, y, z)
				if not VoxelMaterial.is_destructible(int(_tool.get_voxel(vox))):
					continue
				_brush.set_vox(vox, VoxelMaterial.AIR)
				removed += 1
	_brush.end_edit()
	return removed


## Ensure the indestructible bedrock band (y=0) remains under a crater.
## Diggable STONE / pavement above are left as carved air so holes match debris.
func _restore_bedrock_floor(center_vox: Vector3, radius_vox: float) -> void:
	const BEDROCK_BAND := 1
	var r := int(ceil(radius_vox)) + 1
	var cx := int(floor(center_vox.x))
	var cz := int(floor(center_vox.z))
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_brush.begin_edit()
	for z in range(cz - r, cz + r + 1):
		for x in range(cx - r, cx + r + 1):
			var dx := float(x) + 0.5 - center_vox.x
			var dz := float(z) + 0.5 - center_vox.z
			if dx * dx + dz * dz > radius_vox * radius_vox:
				continue
			for y in range(0, BEDROCK_BAND):
				_brush.set_vox(Vector3i(x, y, z), VoxelMaterial.BEDROCK)
	_brush.end_edit()


## Where the navigation overlay probes a corridor to: whatever the player's cursor points
## at. Vector3.INF means "no aim this frame", which the overlay skips.
func _nav_overlay_aim() -> Vector3:
	if _walker == null or not is_instance_valid(_walker):
		return Vector3.INF
	var walker := _walker as CityWalker
	var aim: CityTargeting.Result = walker.resolve_target(
		CityTargeting.TargetMode.VOXELS_ONLY, CityTargeting.ScreenSource.FREE_CURSOR
	)
	return aim.point if aim.did_hit() else Vector3.INF


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
		if is_inventory_open():
			_inventory_panel.call("close_panel")
			get_viewport().set_input_as_handled()
			return
		if is_monster_summon_open():
			_monster_summon_panel.call("close_panel")
			get_viewport().set_input_as_handled()
			return
		get_tree().quit()
		return
	if bool(ctl.call("matches_key_pressed", ek, "inventory")):
		## The character editor is a modal of the walker's own, and two open panels would
		## stack in whatever order UiLayers happens to give them. The splash outranks the whole
		## modal band, so a panel opened under it is invisible and still takes the keys.
		if _game_over or _booting or _is_character_editor_open() or is_splash_open():
			return
		if _inventory_panel != null:
			_inventory_panel.call("toggle_panel")
		get_viewport().set_input_as_handled()
		return
	if bool(ctl.call("matches_key_pressed", ek, "monster_summon")):
		if _game_over or _booting or _is_character_editor_open() or is_splash_open():
			return
		if _monster_summon_panel != null:
			## Capture look-aim while the mouse is still captured — opening the panel releases
			## it onto the UI and a live sample at confirm would hit near the player's feet.
			if not is_monster_summon_open():
				capture_summon_aim()
			_monster_summon_panel.call("toggle_panel")
		get_viewport().set_input_as_handled()
		return
	if bool(ctl.call("matches_key_pressed", ek, "retry")):
		if _game_over:
			_retry_after_game_over()
			get_viewport().set_input_as_handled()
		return
	if bool(ctl.call("matches_key_pressed", ek, "day_night")):
		## World keys stop at an open panel or the splash; the debug toggles below deliberately
		## do not.
		if _game_over or is_modal_open() or is_splash_open():
			return
		if _day_night != null and _day_night.has_method("toggle_day_night"):
			_day_night.call("toggle_day_night")
		get_viewport().set_input_as_handled()
		return
	## Shift+F8 recolours, bare F8 toggles — the modifier-carrying bind is tested first,
	## because a bare bind matches with extra modifiers held.
	if bool(ctl.call("matches_key_pressed", ek, "nav_overlay_colour")):
		if _nav_overlay.is_enabled():
			print("CityRoot: nav overlay colouring by %s" % _nav_overlay.cycle_span_colour())
		get_viewport().set_input_as_handled()
		return
	if bool(ctl.call("matches_key_pressed", ek, "nav_overlay")):
		print("CityRoot: nav overlay %s" % ("on" if _nav_overlay.toggle() else "off"))
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
