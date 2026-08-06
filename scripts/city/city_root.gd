## Endless city POC: spawn-district boot, then bubble streaming with view priority.
class_name CityRoot
extends Node3D

const VOXEL_SIZE := 0.5
const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
const VoxelBlockLibraryScript := preload("res://scripts/city/voxel_block_library.gd")
const CityWalkerScript := preload("res://scripts/city/city_walker.gd")
const DistrictInstanceScript := preload("res://scripts/city/district_instance.gd")
const DistrictHopCutsceneScript := preload("res://scripts/city/district_hop_cutscene.gd")
const CityStreamerScript := preload("res://scripts/city/city_streamer.gd")
const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")
const PlayerEnergyHudScript := preload("res://scripts/city/player_energy_hud.gd")
const PlayerHealthHudScript := preload("res://scripts/city/player_health_hud.gd")
const PlayerBoostHudScript := preload("res://scripts/city/player_boost_hud.gd")
const PlayerCompassHudScript := preload("res://scripts/city/player_compass_hud.gd")
const ZooCloakHudScript := preload("res://scripts/city/zoo_cloak_hud.gd")
const SiegeHudScript := preload("res://scripts/city/siege_hud.gd")
const BeaconRegistryScript := preload("res://scripts/city/beacon_registry.gd")
const VoxelWardScript := preload("res://scripts/city/voxel_ward.gd")
const DamageSourceScript := preload("res://scripts/city/damage_source.gd")
const CityAudioScript := preload("res://scripts/city/city_audio.gd")
const BlastFlashVfxScript := preload("res://scripts/city/blast_flash_vfx.gd")
const DayNightCycleScript := preload("res://scripts/city/day_night_cycle.gd")
const CitySettingsPanelScript := preload("res://scripts/city/city_settings_panel.gd")
const InfectionDirectorScript := preload("res://scripts/city/infection_director.gd")
const InfectionMeteorScript := preload("res://scripts/city/infection_meteor.gd")
const InfectionTendrilHudScript := preload("res://scripts/city/infection_tendril_hud.gd")
const MonsterRosterScript := preload("res://scripts/city/monster_roster.gd")
const UndeadInvasionDirectorScript := preload("res://scripts/city/undead_invasion_director.gd")
const UndeadInvasionHudScript := preload("res://scripts/city/undead_invasion_hud.gd")
const CityMinimapScript := preload("res://scripts/city/city_minimap.gd")
const TetrisMachineScript := preload("res://scripts/city/tetris_machine.gd")
const TetrisPedNpcScript := preload("res://scripts/city/tetris_ped_npc.gd")
const AimPanelScript := preload("res://scripts/city/aim_panel.gd")
const ElevatorPanelScript := preload("res://scripts/city/elevator_panel.gd")
const BuildCatalogScript := preload("res://scripts/city/build_catalog.gd")
const BuildPlacerScript := preload("res://scripts/city/build_placer.gd")
const LoadingSplashScript := preload("res://scripts/city/loading_splash.gd")
const GemLightDirectorScript := preload("res://scripts/city/gem_light_director.gd")
const PlayerInventoryScript := preload("res://scripts/city/player_inventory.gd")
const PlayerInventoryPanelScript := preload("res://scripts/city/player_inventory_panel.gd")
const LootToastScript := preload("res://scripts/city/loot_toast.gd")
const AbilityTrayScript := preload("res://scripts/city/ability_tray.gd")
const PlayerLoadoutScript := preload("res://scripts/city/player_loadout.gd")
const TrapProjectileScript := preload("res://scripts/city/trap_projectile.gd")
const ArmedTrapScript := preload("res://scripts/city/armed_trap.gd")
const MonsterSummonPanelScript := preload("res://scripts/city/monster_summon_panel.gd")
const SiegeBuildPickerScript := preload("res://scripts/city/siege_build_picker.gd")
const NavDebugOverlayScript := preload("res://scripts/city/nav_debug_overlay.gd")
const CreatureCatalogScript := preload("res://scripts/city/creature_catalog.gd")
const CombatTableScript := preload("res://scripts/city/combat_table.gd")
const MonsterFactionScript := preload("res://scripts/city/monster_faction.gd")
const MonsterHealthBarScript := preload("res://scripts/city/monster_health_bar.gd")
const InteriorDecoratorScript := preload("res://scripts/city/interior_decorator.gd")
const CastleDoorPlacerScript := preload("res://scripts/city/castle_door_placer.gd")
const GameSaveScript := preload("res://scripts/city/game_save.gd")
const GameMenuPanelScript := preload("res://scripts/city/game_menu_panel.gd")
const CheatPanelScript := preload("res://scripts/city/cheat_panel.gd")
const DistrictEconomyScript := preload("res://scripts/city/district_economy.gd")
const WorldGamesScript := preload("res://scripts/city/world_games.gd")
const FractalCascadeScript := preload("res://scripts/city/fractal_cascade.gd")
const MonsterGemDropScript := preload("res://scripts/city/monster_gem_drop.gd")

## Sentinel for city_seed: draw a fresh world seed when the game starts.
const SEED_RANDOM := 0
## Frames the warm-up visuals stay on screen (behind the splash) so their pipelines compile.
const WARMUP_FRAMES := 8
## Warm-up staging height, far above any generated terrain so nothing intersects the city.
const WARMUP_ALTITUDE_M := 4000.0
## How far from the world origin (in district tiles) the player may spawn.
const SPAWN_DISTRICT_RING := 3
## How far beside a recipe scroll the cheat teleport leaves the walker. Close enough to see and
## click, far enough not to stand inside the prop.
const CHEAT_RECIPE_STAND_OFF_M := 2.4
## Stand-off beside the hill cave boss cage after the cheat hop.
const CHEAT_CAGE_STAND_OFF_M := 3.5
## Birds never draw closer in than this, whatever the crowd slider says.
const BIRD_RENDER_FLOOR_M := 90.0
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
## JIT furniture when the walker steps into an undecorated InteriorRoom, or opens a
## door that leads into one.
var _interior_decorator: InteriorDecorator
## Outfit scenes kept referenced for the session so gameplay loads hit the resource cache.
var _warm_scenes: Array[PackedScene] = []
var _streamer: CityStreamer
var _walker: CityWalker
var _hud: Label
var _hud_layer: CanvasLayer
## Pooled floor selector, rebound to whichever elevator cabin the player is standing in.
var _elevator_panel: ElevatorPanel
## False while the splash owns the screen (boot, district hop). Combined with is_modal_open()
## in _refresh_hud_visibility; nothing sets a HUD layer's visibility outside that.
var _hud_enabled: bool = false
var _status: Label
var _loading_splash: LoadingSplash
var _ability_tray: AbilityTray
var _loadout: PlayerLoadout = PlayerLoadoutScript.new() as PlayerLoadout
## Living ally from the Minion power. At most one; recast dismisses the previous.
var _player_minion: UndeadUnit = null
## Seconds left before the living ally is auto-dismissed.
var _player_minion_life_left: float = 0.0
## Active Siege Quarter run (pot + waves). Null outside a committed defence.
var _siege_run: SiegeController = null
## Objectives every monster of a given faction perceives at any range. Lives here rather than on
## the siege controller because a beacon is a city-wide property of a target, and the goal provider
## has to reach it from any body on the tile.
var _beacons: BeaconRegistry = BeaconRegistryScript.new() as BeaconRegistry
## Voxels a standing structure holds against every kind of damage. Siege towers are the only
## registrars today: a tower is a health pool, and a blast that carved its stamp instead would
## leave the pool alive inside a hole. See `VoxelWard`.
var _ward: VoxelWard = VoxelWardScript.new() as VoxelWard
var _energy_hud: PlayerEnergyHud
var _health_hud: PlayerHealthHud
var _boost_hud: CanvasLayer
var _compass_hud: PlayerCompassHud
## Spectator cloak countdown. Only a Monster Zoo's controller ever puts it on screen.
var _zoo_cloak_hud: CanvasLayer
## Siege Quarter run strip: wave / pot / Lodestone. Bound to `active_siege_run()`.
var _siege_hud: CanvasLayer
var _debris_root: Node3D
var _cascade: NativeCascadeDebris
var _gem_lights: GemLightDirector
var _infection: InfectionDirector
var _tendril_hud: InfectionTendrilHud
var _undead_hud: UndeadInvasionHud
var _minimap: CityMinimap
## Span field / portal / corridor / dynamic-block viewer, off until F8.
var _nav_overlay: NavDebugOverlay
## Every live Tetris cabinet: the T-key summon plus the permanent arcade row a Gaming
## district streams in. Voxel damage is reported to all of them; keys 1–4 are global, so
## only the nearest cabinet within reach listens (see _gate_tetris_input).
var _tetris_machines: Array[Node3D] = []
## The T-key machine — the one a re-summon replaces. District cabinets are permanent and
## are owned by the district instance that spawned them.
var _summoned_tetris: Node3D
var _tetris_peds: Array[Node3D] = []
var _aim_panel: Node3D
var _game_over_layer: CanvasLayer
var _game_over_title: Label
var _game_over_detail: Label
## Built on demand — a boot that worked never pays for these nodes.
var _boot_fail_layer: CanvasLayer
var _boot_fail_detail: Label
## Per-meteor crater sites: rock stays immune + purple beam until that site's tendrils end.
var _meteor_sites: Dictionary = {}  # site_id → {tendrils, beam, impact_vox}
var _tendril_to_meteor_site: Dictionary = {}  # tendril_id → site_id
var _next_meteor_site_id: int = 1
var _spawn_meteors_enabled: bool = false
var _meteor_spawn_accum: float = 0.0
var _meteor_spawn_interval_sec: float = 120.0
var _undead_invasion_enabled: bool = false
## Shared living-monster list (arena, N-key, invasion). Always available once first used.
var _monsters: MonsterRoster
## Optional invasion scenario on top of `_monsters` (waves / giant / convert).
var _undead: UndeadInvasionDirector
## Run score. Explore-once payouts only for now; combat deeds arrive with the scenarios.
var _player_score: int = 0
## Per-district gem budgets + explored flags. The only thing the save knows about the world.
var _economy: DistrictEconomy = DistrictEconomyScript.new() as DistrictEconomy
var _economy_accum: float = 0.0
## Matches the run has going — a Go board in the Gaming plaza today. Outlives the district
## that hosts them, so streaming the plaza out does not forfeit the game.
var _games: WorldGames = WorldGamesScript.new() as WorldGames
## Collected gems and crafted items (25 stackable slots).
var _inventory: PlayerInventory = PlayerInventoryScript.new() as PlayerInventory
var _inventory_panel: PlayerInventoryPanel
## Transient card that shows what just came in — the inventory is closed while you play.
var _loot_toast: LootToast
var _monster_summon_panel: MonsterSummonPanel
## Tower list for one Siege pad, opened by that pad's "+" plate.
var _siege_build_picker: SiegeBuildPicker
var _game_menu: GameMenuPanel
var _cheat_panel: CheatPanel
## Save payload waiting to be poured into the next walker. Set before a regenerate (boot resume,
## quickload, load) and cleared once the character is standing in the rebuilt world.
var _pending_restore: Dictionary = {}
## Theme forced for the next fresh spawn (e.g. Adventure → Old Town). Consumed in
## `_resolve_spawn_district`. -1 = unset. CLI flags still win over this.
var _pending_spawn_theme_id: int = -1
var _autosave_accum: float = 0.0
## World aim captured when N opens the summon panel (before the mouse moves onto UI).
var _summon_aim: Variant = null
var _game_over: bool = false
## True while Enter-after-death is teleporting to the zone spawn.
var _respawning: bool = false
var _radar_cooldown_left: float = 0.0
var _radar_reveal_left: float = 0.0
var _gem_pickup_accum: float = 0.0
const RADAR_COOLDOWN_SEC := 30.0
## How long all undead stay painted on the minimap after U.
const RADAR_REVEAL_SEC := 12.0
const GEM_PICKUP_INTERVAL_SEC := 0.12
const GEM_PICKUP_REACH_M := 1.35
## How far from a cabinet's stand keys 1–4 still reach it. Generous, because a T-key
## machine is summoned at aim range and should be playable from where you summoned it —
## the arcade row stays unambiguous because only the *nearest* cabinet ever listens.
const TETRIS_REACH_M := 20.0
## How far a dropped pedestrian will look for a cabinet to walk up to and play.
const TETRIS_PED_REACH_M := 14.0
## Hill ore is painted as tiny 6-neighbour clumps; one strike / walk-up takes the whole clump.
const GEM_CLUSTER_MAX := 24
## Seconds between district budget / explore sweeps. Only fires when a tile finishes baking or
## the player crosses a tile line, so it can be lazy.
const ECONOMY_TICK_SEC := 0.5
## How close to a giant's fresh facade strip is close enough to be under it.
const GIANT_DEBRIS_HURT_RADIUS_M := 6.0
## Wall-clock seconds between autosaves once the world is playable.
const AUTOSAVE_INTERVAL_SEC := 60.0
## How far up a saved column the footing search looks for somewhere to stand. A character saved
## inside a tunnel he dug comes back on the surface above it, because the tunnel is not saved. Tall
## enough to clear a filled-in shaft from bedrock to street.
const SAVE_FOOTING_UP_VOX := 48
## And how far down, for a save the autosave timer caught mid-jump or mid-fall. Deliberately short:
## a long downward reach would drop a character standing on a rooftop into the street.
const SAVE_FOOTING_DOWN_VOX := 12
## Body height the footing search must clear, in voxels (1.7 m capsule at 0.5 m voxels).
const SAVE_FOOTING_HEIGHT_VOX := 4
## Span the spawn column is searched for a floor before the walker is dropped onto it.
## Up covers a spawn point sunk slightly into its own deck; down covers a rooftop or
## mid-air save whose ground is a storey or two below.
const FLOOR_PROBE_UP_M := 8.0
const FLOOR_PROBE_DOWN_M := 20.0
## How long the preferred column gets before the search widens. Deliberately short: the
## district that owns the column has already reported ready, so ground that is not there
## after this is not coming, and every extra second is a player staring at a splash.
const FOOTING_PREFERRED_MS := 10_000
## And how long each fallback column gets. Shorter still — by now the world is warm.
const FOOTING_FALLBACK_MS := 6_000
## Rings walked outwards when the preferred column has no floor, in metres. Wide enough to
## clear a crypt, a cave mouth or a single unstamped block, tight enough that the player
## still wakes up where they saved.
const FOOTING_RING_RADII_M: Array[float] = [2.0, 4.0, 6.0, 8.0]
## Where the footing the walker was finally given came from. Anything but PREFERRED means
## the world did not have ground where it was asked for it, and said so in the log.
const FOOTING_PREFERRED := "preferred"
const FOOTING_NEARBY := "nearby"
const FOOTING_DISTRICT := "district-spawn"
const FOOTING_SOFT_LAND := "soft-land"
var _audio: CityAudio
var _day_night: DayNightCycle
var _settings_panel: CitySettingsPanel
var _world_env: WorldEnvironment
var _sun: DirectionalLight3D
var _player_viewer: VoxelViewer
var _collision_viewer: VoxelViewer
var _booting: bool = false
var _district_hopping: bool = false
## The launch animation, alive only while a hop is playing.
var _hop_cutscene: DistrictHopCutscene = null
var _fps_accum: float = 0.0
var _infection_stream_accum: float = 0.0
var _street_night_factor: float = 0.0
## True while a material detonation is running — blocks recursive explosive triggers.
var _explosive_detonating: bool = false
## Dissolve cascade: frontier cells die this frame and infect matching neighbours.
var _dissolve_frontier: Array[Vector3i] = []
var _dissolve_seen: Dictionary = {}  # Vector3i → true
var _dissolve_seed_id: int = -1
var _dissolve_removed: int = 0
## Hard cap so a mis-authored dissolve fabric cannot eat the district in one cascade.
const DISSOLVE_MAX_CELLS := 8000
const _DISSOLVE_NEIGHBOURS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
## Fractal display cascades: only a player shot may start one; never spawned by another cascade.
## Cap concurrent chains from separate shots (glow / bands / interior).
const FRACTAL_CASCADE_MAX := 5
var _fractal_cascades: Array = []  # FractalCascade RefCounted instances

## Visual mesh radius (~90 m at default). Collisions use a shorter viewer below.
var _voxel_view_vox: int = 100
var _collision_view_vox: int = 48


func _ready() -> void:
	add_to_group("city_root")
	CityVoxelNativeScript.require_loaded()
	print("CityRoot: city_voxel native ready (volume + cascade debris)")
	var seed_forced := city_seed != SEED_RANDOM or _cli_int_flag("--city-seed=") != SEED_RANDOM
	_resolve_seed()
	_adopt_quicksave_at_boot(seed_forced)
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


## True when this city is the game rather than a fixture inside a test or screenshot scene. Only a
## real session may resume an autosave or write one: a tool that boots a city to photograph a
## district must not inherit somebody's run, and must not leave a save behind that the next launch
## would resume into.
## The main scene hangs directly off the viewport root; a fixture is a child of the tool scene that
## built it. Deliberately not `current_scene`, which is still null while the main scene's _ready runs.
func _is_game_session() -> bool:
	var tree := get_tree()
	return tree != null and get_parent() == tree.root


## Boot resume. The quicksave carries the world seed, so the character wakes up in the city he left
## rather than in a fresh one wearing his old inventory. A seed set in the scene, by a tool or with
## --city-seed wins: those name a specific world, and honouring the save instead would make them
## useless. `seed_forced` is read before _resolve_seed fills in a random one.
func _adopt_quicksave_at_boot(seed_forced: bool) -> void:
	if not _is_game_session():
		return
	if not GameSaveScript.has_quicksave():
		return
	if seed_forced:
		print("CityRoot: a world seed was given, ignoring the autosave")
		return
	var data := GameSaveScript.read_quicksave()
	if data.is_empty():
		## Last build's format, or a file that is not a save at all. Either way there is nobody to
		## wake up, so the autosave goes aside and this run starts a fresh character.
		GameSaveScript.retire_quicksave()
		return
	_pending_restore = data
	city_seed = GameSaveScript.saved_seed(data)
	print("CityRoot: resuming autosave in world seed %d" % city_seed)


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


func _pick_spawn_district_random() -> Vector2i:
	## Stable for a given world seed so --city-seed=N also replays the spawn tile.
	var rng := RandomNumberGenerator.new()
	rng.seed = DistrictCoord.feature_seed(city_seed, 0x53504E)  ## "SPN"
	return Vector2i(
		rng.randi_range(-SPAWN_DISTRICT_RING, SPAWN_DISTRICT_RING),
		rng.randi_range(-SPAWN_DISTRICT_RING, SPAWN_DISTRICT_RING)
	)


## Resolves the spawn tile: a save being restored, CLI coord, --spawn-theme search,
## a pending theme (Adventure Old Town), or seeded RNG. No start modal.
func _resolve_spawn_district() -> Vector2i:
	if not _pending_restore.is_empty():
		var saved := GameSaveScript.saved_position(_pending_restore)
		if saved != Vector3.INF:
			var coord := DistrictCoord.from_world(saved, VOXEL_SIZE)
			spawn_theme_id = DistrictTheme.for_district(city_seed, coord).id
			_pending_spawn_theme_id = -1
			return coord

	var forced: Variant = _cli_spawn_district()
	if forced is Vector2i:
		spawn_theme_id = DistrictTheme.for_district(city_seed, forced as Vector2i).id
		_pending_spawn_theme_id = -1
		return forced as Vector2i

	var theme_id := _cli_spawn_theme()
	if theme_id < 0 and _pending_spawn_theme_id >= 0:
		theme_id = _pending_spawn_theme_id
	_pending_spawn_theme_id = -1
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


func is_siege_build_picker_open() -> bool:
	return _siege_build_picker != null and _siege_build_picker.is_open()


func is_game_menu_open() -> bool:
	return _game_menu != null and _game_menu.is_open()


func is_cheat_open() -> bool:
	return _cheat_panel != null and _cheat_panel.is_open()


## True while a panel of this root's owns the screen. The walker and the build bar read this to
## stop taking hotkeys, and the HUD band is hidden for as long as it holds. The walker's own
## character editor is not in here: nothing would tell us when it closes again.
func is_modal_open() -> bool:
	return (
		is_settings_open()
		or is_inventory_open()
		or is_monster_summon_open()
		or is_siege_build_picker_open()
		or is_game_menu_open()
		or is_cheat_open()
	)


## True while the splash covers the world — boot, a hop in flight, and the J picker. It is a
## screen takeover rather than a modal, but gameplay input has to stop at it just the same:
## parking the walker only stops walking, and the meteor, build and cabinet keys all kept
## firing into the city behind the open picker.
func is_splash_open() -> bool:
	return _loading_splash != null and bool(_loading_splash.call("owns_screen"))


## The character the human is driving. Districts reach for it through the `city_root`
## group when an effect has to start at or aim for the player.
func player_walker() -> CityWalker:
	if _walker == null or not is_instance_valid(_walker):
		return null
	return _walker


func has_player_walker() -> bool:
	return _walker != null and is_instance_valid(_walker)


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
			"set_top_bar_visible",
			not is_inventory_open()
			and not is_monster_summon_open()
			and not is_siege_build_picker_open()
			and not is_game_menu_open()
			and not is_cheat_open()
		)


func get_inventory() -> PlayerInventory:
	return _inventory


func _as_district_instance(entry: Variant) -> DistrictInstance:
	## Script identity rather than `is`, so a node carrying a subclass of the district script
	## is not mistaken for a district the streamer owns.
	if entry == null or not is_instance_valid(entry):
		return null
	if not (entry is Node):
		return null
	var node := entry as Node
	if node.get_script() != DistrictInstanceScript:
		return null
	return node as DistrictInstance


func _on_night_factor_changed(night_factor: float) -> void:
	_street_night_factor = clampf(night_factor, 0.0, 1.0)
	VoxelBlockLibraryScript.set_glass_lit_night_factor(_street_night_factor)
	_push_night_factor_to_street_lights()


func _push_night_factor_to_street_lights() -> void:
	if _streamer == null:
		return
	for entry in _streamer.get_loaded_districts():
		var inst := _as_district_instance(entry)
		if inst == null:
			continue
		if inst.street_props != null and is_instance_valid(inst.street_props):
			inst.street_props.set_night_factor(_street_night_factor)
		if inst.building_lod != null and is_instance_valid(inst.building_lod):
			inst.building_lod.set_night_factor(_street_night_factor)


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

	_boost_hud = PlayerBoostHudScript.new() as CanvasLayer
	_boost_hud.name = "PlayerBuffHud"
	add_child(_boost_hud)

	_compass_hud = PlayerCompassHudScript.new() as PlayerCompassHud
	_compass_hud.name = "PlayerCompassHud"
	add_child(_compass_hud)

	_zoo_cloak_hud = ZooCloakHudScript.new() as CanvasLayer
	_zoo_cloak_hud.name = "ZooCloakHud"
	add_child(_zoo_cloak_hud)

	_siege_hud = SiegeHudScript.new() as CanvasLayer
	_siege_hud.name = "SiegeHud"
	add_child(_siege_hud)
	_siege_hud.call("bind_city", self)

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
	_settings_panel.game_menu_requested.connect(_on_game_menu_requested)

	_game_menu = GameMenuPanelScript.new() as GameMenuPanel
	_game_menu.name = "GameMenu"
	add_child(_game_menu)
	_game_menu.opened.connect(_on_game_menu_opened)
	_game_menu.closed.connect(_on_game_menu_closed)
	_game_menu.quicksave_requested.connect(_on_quicksave_requested)
	_game_menu.quickload_requested.connect(_on_quickload_requested)
	_game_menu.named_save_requested.connect(_on_named_save_requested)
	_game_menu.named_load_requested.connect(_on_named_load_requested)
	_game_menu.new_game_requested.connect(_on_new_game_requested)

	_cheat_panel = CheatPanelScript.new() as CheatPanel
	_cheat_panel.name = "CheatPanel"
	add_child(_cheat_panel)
	_cheat_panel.opened.connect(_on_cheat_opened)
	_cheat_panel.closed.connect(_on_cheat_closed)
	_cheat_panel.fill_gems_requested.connect(_on_cheat_fill_gems)
	_cheat_panel.fill_recipes_requested.connect(_on_cheat_fill_recipes)
	_cheat_panel.teleport_nearest_recipe_requested.connect(_on_cheat_teleport_nearest_recipe)
	_cheat_panel.teleport_cave_cage_requested.connect(_on_cheat_teleport_cave_cage)

	_loot_toast = LootToastScript.new() as LootToast
	_loot_toast.name = "LootToast"
	add_child(_loot_toast)

	_inventory_panel = PlayerInventoryPanelScript.new()
	_inventory_panel.name = "PlayerInventory"
	add_child(_inventory_panel)
	_inventory_panel.call("bind_inventory", _inventory)
	_inventory_panel.opened.connect(_on_inventory_opened)
	_inventory_panel.closed.connect(_on_inventory_closed)
	_inventory_panel.craft_requested.connect(_on_inventory_craft_requested)
	_inventory_panel.unlock_requested.connect(_on_inventory_unlock_requested)

	_monster_summon_panel = MonsterSummonPanelScript.new()
	_monster_summon_panel.name = "MonsterSummon"
	add_child(_monster_summon_panel)
	_monster_summon_panel.opened.connect(_on_monster_summon_opened)
	_monster_summon_panel.closed.connect(_on_monster_summon_closed)
	_monster_summon_panel.summon_requested.connect(_on_monster_summon_requested)

	_siege_build_picker = SiegeBuildPickerScript.new()
	_siege_build_picker.name = "SiegeBuildPicker"
	add_child(_siege_build_picker)
	_siege_build_picker.opened.connect(_on_siege_build_picker_opened)
	_siege_build_picker.closed.connect(_on_siege_build_picker_closed)
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
	hint.text = "Press Enter to respawn at this zone's spawn"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 20)
	hint.add_theme_color_override("font_color", Color(0.75, 0.95, 0.85))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	hint.add_theme_constant_override("outline_size", 3)
	box.add_child(hint)


## The last resort when no rung of the footing ladder produced anywhere to stand. A boot that
## dies silently behind the title art looks like a hang and leaves the player with nothing to
## press, so this hands the screen back: retry the same world, start a fresh one, or leave.
func _show_boot_fail_overlay(reason: String) -> void:
	_build_boot_fail_overlay()
	_boot_fail_detail.text = reason
	_boot_fail_layer.visible = true
	if _status != null:
		_status.visible = false
	if _loading_splash != null:
		_loading_splash.call("set_status", "Could not start the world")
	if _walker != null and is_instance_valid(_walker):
		_walker.release_capture()
	push_error("CityRoot: boot failed — %s" % reason)


func _build_boot_fail_overlay() -> void:
	if _boot_fail_layer != null and is_instance_valid(_boot_fail_layer):
		return
	_boot_fail_layer = CanvasLayer.new()
	_boot_fail_layer.name = "BootFailureOverlay"
	_boot_fail_layer.layer = UiLayers.BOOT_FAILURE
	_boot_fail_layer.visible = false
	## The world is not running, so the overlay must not depend on it running.
	_boot_fail_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_boot_fail_layer)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.03, 0.02, 0.02, 0.86)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_boot_fail_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boot_fail_layer.add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)

	var title := Label.new()
	title.text = "COULD NOT START"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", Color(1.0, 0.66, 0.28))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 8)
	box.add_child(title)

	_boot_fail_detail = Label.new()
	_boot_fail_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boot_fail_detail.add_theme_font_size_override("font_size", 21)
	_boot_fail_detail.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	_boot_fail_detail.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_boot_fail_detail.add_theme_constant_override("outline_size", 4)
	box.add_child(_boot_fail_detail)

	var hint := Label.new()
	hint.text = "The log has the spawn column that failed."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 17)
	hint.add_theme_color_override("font_color", Color(0.78, 0.74, 0.68))
	box.add_child(hint)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	row.add_child(_boot_fail_button("Retry this world", _on_boot_fail_retry))
	row.add_child(_boot_fail_button("New game", _on_boot_fail_new_game))
	row.add_child(_boot_fail_button("Quit", _on_boot_fail_quit))


func _boot_fail_button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(190.0, 46.0)
	button.add_theme_font_size_override("font_size", 19)
	button.pressed.connect(pressed)
	return button


func _hide_boot_fail_overlay() -> void:
	if _boot_fail_layer != null and is_instance_valid(_boot_fail_layer):
		_boot_fail_layer.visible = false
	if _status != null:
		_status.visible = true


## Same seed, same save: most boot failures are a streaming race that a second attempt wins.
func _on_boot_fail_retry() -> void:
	_hide_boot_fail_overlay()
	_regenerate()


## The save itself may be the thing that cannot be placed, so this route drops it.
func _on_boot_fail_new_game() -> void:
	_hide_boot_fail_overlay()
	start_new_game(_loadout.mode)


func _on_boot_fail_quit() -> void:
	get_tree().quit()


func _roll_meteor_spawn_interval() -> void:
	## Random 1–3 minutes between auto impacts.
	_meteor_spawn_interval_sec = randf_range(60.0, 180.0)

func _on_settings_opened() -> void:
	_close_other_modals_except("settings")
	_refresh_hud_visibility()
	if _walker != null and is_instance_valid(_walker):
		_walker.release_capture()


func _on_settings_closed() -> void:
	_refresh_hud_visibility()
	if is_modal_open():
		return
	## Free-cursor aim — never restore legacy mouse capture after a modal.
	if _walker != null and is_instance_valid(_walker):
		_walker.release_capture()


func _on_inventory_opened() -> void:
	_close_other_modals_except("inventory")
	_refresh_hud_visibility()
	if _walker != null and is_instance_valid(_walker):
		_walker.release_capture()


func _on_inventory_closed() -> void:
	_refresh_hud_visibility()
	if is_modal_open():
		return
	if _walker != null and is_instance_valid(_walker):
		_walker.release_capture()


func _on_monster_summon_opened() -> void:
	_close_other_modals_except("summon")
	_refresh_hud_visibility()
	if _walker != null and is_instance_valid(_walker):
		_walker.release_capture()


func _on_monster_summon_closed() -> void:
	## Cancel clears a pending look-aim; confirm already consumed it in summon_monster_at_aim.
	_summon_aim = null
	_refresh_hud_visibility()
	if is_modal_open():
		return
	if _walker != null and is_instance_valid(_walker):
		_walker.release_capture()


## Called by SiegeController when a pad's "+" plate is pressed. The list opens at the cursor the
## player just aimed with, so the pad they picked stays in view.
func open_siege_build_picker(pad_index: int, controller: Node) -> void:
	if _siege_build_picker == null or not is_instance_valid(_siege_build_picker):
		push_error("CityRoot.open_siege_build_picker: no picker")
		assert(false, "CityRoot: siege build picker missing")
		return
	var at := get_viewport().get_mouse_position()
	_siege_build_picker.open_for_pad(pad_index, controller, at)


func close_siege_build_picker() -> void:
	if _siege_build_picker != null and is_instance_valid(_siege_build_picker):
		_siege_build_picker.close_panel()


## Pot changed under an open list (a kill credited, another pad bought). Re-list in place.
func refresh_siege_build_picker() -> void:
	if _siege_build_picker != null and is_instance_valid(_siege_build_picker):
		_siege_build_picker.refresh()


func _on_siege_build_picker_opened() -> void:
	_close_other_modals_except("siege_build")
	_refresh_hud_visibility()
	if _walker != null and is_instance_valid(_walker):
		_walker.release_capture()


func _on_siege_build_picker_closed() -> void:
	_refresh_hud_visibility()
	if is_modal_open():
		return
	if _walker != null and is_instance_valid(_walker):
		_walker.release_capture()


func _on_game_menu_requested() -> void:
	if _game_menu == null:
		return
	_game_menu.toggle_panel()


func _on_game_menu_opened() -> void:
	_close_other_modals_except("game")
	_refresh_hud_visibility()
	if _game_over:
		_game_menu.set_status("This run is over — load a save or start a new game.", true)
	elif not can_save_game():
		_game_menu.set_status("The world is still coming up — saving waits for it.", true)
	if _walker != null and is_instance_valid(_walker):
		_walker.release_capture()


func _on_game_menu_closed() -> void:
	_refresh_hud_visibility()
	if is_modal_open():
		return
	if _walker != null and is_instance_valid(_walker):
		_walker.release_capture()


func _on_cheat_opened() -> void:
	_close_other_modals_except("cheat")
	_refresh_hud_visibility()
	if _walker != null and is_instance_valid(_walker):
		_walker.release_capture()
	## Fresh dump every open — the log is for what is true right now, not a history of opens.
	if _cheat_panel != null:
		_cheat_panel.set_log(build_cheat_district_report())


## Snapshot of the player's tile for the cheat modal: gems still owed, living actor tallies, and
## the four neighbouring themes. Themes are looked up by seed rather than by what is loaded, so
## an unloaded neighbour still has a name.
func build_cheat_district_report() -> String:
	var lines: PackedStringArray = PackedStringArray()
	if _walker == null or not is_instance_valid(_walker):
		return "District report\n(no walker)"
	var here := DistrictCoord.from_world(_walker.global_position, VOXEL_SIZE)
	var theme := DistrictTheme.for_district(city_seed, here)
	var place := DistrictName.for_district(city_seed, here)
	lines.append("District report")
	lines.append("%s (%s) at %s" % [place, theme.display_name, str(here)])
	lines.append("")

	var theme_budget := preload("res://scripts/city/game_data.gd").theme_gem_total(theme.id)
	if _loadout != null and _loadout.uses_gem_budgets():
		var left := 0
		if _economy != null:
			left = _economy.remaining_total(here)
		lines.append("Hidden gems: %d (theme budget %d)" % [left, theme_budget])
		if theme.id == DistrictTheme.HILL:
			var hill_inst := _district_at_coord(here)
			if hill_inst != null:
				lines.append(
					"Hill ore voxels: %d"
					% hill_inst.hill_gem_mats.size()
				)
	else:
		lines.append("Hidden gems: n/a (no gem budgets in this mode)")
	lines.append("")

	lines.append("Actors")
	var actor_lines := _cheat_actor_lines()
	if actor_lines.is_empty():
		lines.append("  (none active)")
	else:
		lines.append_array(actor_lines)
	lines.append("")

	lines.append("Neighbors")
	## Same order as signposts: east, south, west, north.
	var card_names: PackedStringArray = PackedStringArray(["east", "south", "west", "north"])
	var card_offs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)
	]
	for i in card_names.size():
		var ncoord := here + card_offs[i]
		var ntheme := DistrictTheme.for_district(city_seed, ncoord)
		lines.append("  %s => %s" % [card_names[i], ntheme.display_name.to_lower()])
	return "\n".join(lines)


## One line per living actor kind across the loaded bubble (and the global monster roster).
## Kinds with a zero count are omitted so an empty invasion does not pad the report.
func _cheat_actor_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var peds := 0
	var vehicles := 0
	if _streamer != null:
		for entry in _streamer.get_loaded_districts():
			var inst := _as_district_instance(entry)
			if inst == null:
				continue
			if inst.crowd != null and is_instance_valid(inst.crowd):
				peds += inst.crowd.agents_for_occupancy().size()
			if inst.vehicles != null and is_instance_valid(inst.vehicles):
				vehicles += inst.vehicles.vehicle_live_count()
	if peds > 0:
		lines.append("  pedestrians: %d" % peds)
	if vehicles > 0:
		lines.append("  vehicles: %d" % vehicles)

	var monster_counts: Dictionary = {}  ## String label → int
	if _monsters != null and is_instance_valid(_monsters):
		for unit in _monsters.get_alive_units():
			if unit == null or not is_instance_valid(unit):
				continue
			var label := _cheat_monster_label(unit)
			monster_counts[label] = int(monster_counts.get(label, 0)) + 1
	var monster_keys: Array = monster_counts.keys()
	monster_keys.sort()
	for key: Variant in monster_keys:
		lines.append("  %s: %d" % [str(key), int(monster_counts[key])])

	if _player_minion != null and is_instance_valid(_player_minion) and _player_minion.is_alive():
		lines.append("  player minion: %s" % _cheat_monster_label(_player_minion))
	return lines


func _cheat_monster_label(unit: UndeadUnit) -> String:
	var entry := unit.creature_entry()
	if entry != null and not entry.id.is_empty():
		return entry.id
	if unit.is_giant():
		return "giant"
	match unit.role:
		UndeadUnit.Role.MAGE:
			return "mage"
		UndeadUnit.Role.MINION:
			return "minion"
		UndeadUnit.Role.GIANT:
			return "giant"
		_:
			return "monster"


func _on_cheat_closed() -> void:
	_refresh_hud_visibility()
	if is_modal_open():
		return
	if _walker != null and is_instance_valid(_walker):
		_walker.release_capture()


## One modal at a time. Each open handler used to list the others by hand, and the cheat panel
## was about to be the fifth place that list had to be kept in sync.
func _close_other_modals_except(keep: String) -> void:
	if keep != "settings" and is_settings_open():
		_settings_panel.call("close_panel")
	if keep != "inventory" and is_inventory_open():
		_inventory_panel.call("close_panel")
	if keep != "summon" and is_monster_summon_open():
		_monster_summon_panel.call("close_panel")
	if keep != "siege_build" and is_siege_build_picker_open():
		_siege_build_picker.close_panel()
	if keep != "game" and is_game_menu_open():
		_game_menu.close_panel()
	if keep != "cheat" and is_cheat_open():
		_cheat_panel.close_panel()


func _on_quicksave_requested() -> void:
	if write_quicksave("Quicksave"):
		_game_menu.set_status("Saved to the autosave slot.")
	else:
		_game_menu.set_status("Quicksave failed — see the log.", true)
	_game_menu.refresh()


func _on_quickload_requested() -> void:
	_game_menu.close_panel()
	if not load_quicksave():
		_game_menu.open_panel()
		_game_menu.set_status("There is no readable autosave.", true)


func _on_named_save_requested(save_name: String) -> void:
	if write_named_save(save_name):
		_game_menu.set_status("Saved as '%s'." % GameSaveScript.sanitize_name(save_name))
	else:
		_game_menu.set_status("Could not save '%s' — see the log." % save_name, true)
	_game_menu.refresh()


func _on_named_load_requested(save_name: String) -> void:
	_game_menu.close_panel()
	if not load_named_save(save_name):
		_game_menu.open_panel()
		_game_menu.set_status("Could not read '%s'." % save_name, true)


func _on_new_game_requested(mode: String) -> void:
	_game_menu.close_panel()
	start_new_game(mode)


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


## Sample meteor-style world aim before the summon panel moves the cursor onto its UI.
func capture_summon_aim() -> void:
	_summon_aim = null
	if _walker == null or not is_instance_valid(_walker):
		push_error("CityRoot.capture_summon_aim: no walker")
		return
	var aim: Dictionary = _walker.call("aim_world_at_cursor") as Dictionary
	_summon_aim = aim
	var point: Vector3 = aim.get("point", Vector3.INF) as Vector3
	var player := get_player_position()
	print(
		"CityRoot: summon aim captured hit=%s point=%s player=%s dist=%.1fm"
		% [
			bool(aim.get("did_hit", false)),
			point,
			player,
			player.distance_to(point) if player != Vector3.INF and point.is_finite() else -1.0,
		]
	)


## Meshless Siege Quarter tower at an explicit world point (pad centre).
func spawn_siege_tower_at(
	combat_id: String, world_pos: Vector3, authored_hp: float, muzzle_height_m: float
) -> UndeadUnit:
	_ensure_monster_roster()
	if _monsters == null:
		push_error("CityRoot.spawn_siege_tower_at: no MonsterRoster")
		assert(false, "CityRoot: no MonsterRoster")
		return null
	return _monsters.spawn_siege_tower(combat_id, world_pos, authored_hp, muzzle_height_m)


## Spawn a catalogue body at an explicit world point (Arena lifts, tests).
## Returns null when nav / caps refuse. When `snap_nav` is false the body stays at
## `world_pos` (lift undercroft delivery). Does not involve the invasion director.
func spawn_monster_at(
	body_id: String, world_pos: Vector3, snap_nav: bool = true
) -> UndeadUnit:
	if body_id.is_empty():
		push_error("CityRoot.spawn_monster_at: empty body id")
		return null
	_ensure_monster_roster()
	if _monsters == null:
		push_error("CityRoot.spawn_monster_at: no MonsterRoster")
		assert(false, "CityRoot: no MonsterRoster")
		return null
	var pos := world_pos
	if snap_nav:
		var entry: CreatureCatalog.Entry = CreatureCatalogScript.by_id(body_id)
		if entry != null and NavService.instance().is_configured():
			var stand := NavService.instance().nearest_surface(entry.nav_profile, pos, 8.0)
			if stand.found:
				pos = stand.position
	return _monsters.spawn_by_id(body_id, pos)


## Living monsters (for Arena wipe). Empty when the roster is not up.
func alive_undead_units() -> Array:
	_ensure_monster_roster()
	if _monsters == null:
		return []
	return _monsters.get_alive_units() as Array


## Drop one living unit without a death clip (Arena Clear / tools).
func despawn_undead_unit(unit: UndeadUnit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	_ensure_monster_roster()
	if _monsters != null:
		_monsters.despawn_unit(unit)
		return
	unit.queue_free()


## Spawn at the world aim captured when N opened. Tiny upward clearance keeps feet out of the
## hit surface; there is no feet/ring/nav fallback on a true miss.
func summon_monster_at_aim(body_id: String) -> UndeadUnit:
	if _game_over or _booting:
		return null
	if _walker == null or not is_instance_valid(_walker):
		push_error("CityRoot.summon_monster_at_aim: no walker")
		return null
	var aim: Dictionary
	if _summon_aim is Dictionary:
		aim = _summon_aim as Dictionary
	else:
		## Direct callers (tests / probes) may skip capture; live sample matches meteor.
		aim = _walker.call("aim_world_at_cursor") as Dictionary
	if not bool(aim.get("did_hit", false)):
		print("CityRoot: summon cancelled — world aim missed")
		return null
	_ensure_monster_roster()
	if _monsters == null:
		push_error("CityRoot.summon_monster_at_aim: no MonsterRoster")
		assert(false, "CityRoot: no MonsterRoster")
		return null
	const BODY_CLEARANCE_M := 0.06
	var requested: Vector3 = aim["point"] as Vector3
	var pos := requested + Vector3.UP * BODY_CLEARANCE_M
	## Snap onto a standable span for this body's nav profile before spawn. Aim hits are voxel
	## surfaces; MONSTER clearance is wider than UNDEAD, and a body a few centimetres off a
	## span starts every goal with NO_START → TRAPPED → re-acquire (including another facade
	## search). Prefer a real footing over a clearance nudge alone.
	var entry: CreatureCatalog.Entry = CreatureCatalogScript.by_id(body_id)
	if entry != null and NavService.instance().is_configured():
		var stand := NavService.instance().nearest_surface(entry.nav_profile, pos, 8.0)
		if stand.found:
			pos = stand.position
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
	CityProfiler.note_event("monster_summon %s" % body_id)
	CityProfiler.begin("monster_summon")
	var unit := _monsters.spawn_by_id(body_id, pos)
	CityProfiler.end("monster_summon")
	if unit != null:
		print("CityRoot: spawn actual=%s requested_voxel_hit=%s" % [unit.global_position, requested])
	return unit


func _on_inventory_unlock_requested(ability_id: String) -> void:
	if not try_unlock_ability(ability_id):
		return
	if _inventory_panel != null and _inventory_panel.has_method("_refresh"):
		_inventory_panel.call("_refresh")


func _on_inventory_craft_requested(recipe_id: String) -> void:
	if _inventory == null:
		return
	if not knows_recipe(recipe_id):
		push_error("CityRoot: craft requested for unknown recipe '%s'" % recipe_id)
		return
	if not _inventory.craft(recipe_id):
		push_error("CityRoot: craft failed for '%s'" % recipe_id)
		return
	print("CityRoot: crafted %s" % recipe_id)


func _apply_saved_controls() -> void:
	if _settings_panel != null:
		_on_controls_changed(_settings_panel.get_player_controls())


func _on_controls_changed(controls: PlayerControls) -> void:
	if controls == null:
		return
	if _walker != null and is_instance_valid(_walker):
		_walker.set_controls(controls)
	if _ability_tray != null and is_instance_valid(_ability_tray):
		_ability_tray.set_controls(controls)
	CityProfiler.set_controls(controls)
	DamageLog.set_controls(controls)


func _on_settings_applied(settings: Dictionary) -> void:
	var scale := clampf(float(settings.get("render_scale", 1.0)), 0.45, 1.0)
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
	if _streamer == null:
		return
	for entry in _streamer.get_loaded_districts():
		var inst := _as_district_instance(entry)
		if inst == null or not is_instance_valid(inst):
			continue
		if inst.crowd != null and is_instance_valid(inst.crowd):
			inst.crowd.render_distance = crowd_m
			inst.crowd._refresh_lod(true)
		if inst.vehicles != null and is_instance_valid(inst.vehicles):
			inst.vehicles.render_distance = vehicle_m
		if inst.street_props != null and is_instance_valid(inst.street_props):
			inst.street_props.max_omni_lights = omni
			inst.street_props._refresh_lights(true)
		if inst.birds != null and is_instance_valid(inst.birds):
			## Birds ride the crowd slider — both are ambient actor draw distance — but a
			## dozen palm-sized meshes cost a fraction of a skinned pedestrian, so they keep
			## a floor rather than disappearing off the bottom of the quality presets.
			inst.birds.render_distance = maxf(crowd_m, BIRD_RENDER_FLOOR_M)


func _process(delta: float) -> void:
	CityProfiler.begin("city_root")
	_fps_accum += delta
	_infection_stream_accum += delta
	_gem_pickup_accum += delta
	_economy_accum += delta
	if not _dissolve_frontier.is_empty():
		CityProfiler.begin("voxel_dissolve")
		_tick_dissolve()
		CityProfiler.end("voxel_dissolve")
	if not _fractal_cascades.is_empty():
		CityProfiler.begin("voxel_fractal_cascade")
		_tick_fractal_cascades()
		CityProfiler.end("voxel_fractal_cascade")
	CityProfiler.begin("underground")
	_sync_underground_lighting()
	CityProfiler.end("underground")
	if (
		not _game_over
		and _interior_decorator != null
		and _walker != null
		and is_instance_valid(_walker)
		and _streamer != null
	):
		CityProfiler.begin("interior_decorate")
		if _interior_decorator.tick(_walker.global_position, _streamer.get_loaded_districts()):
			_try_place_room_chest()
		CityProfiler.end("interior_decorate")
	if (
		not _game_over
		and _walker != null
		and is_instance_valid(_walker)
		and _streamer != null
	):
		_refresh_elevator_panel()
	elif _elevator_panel != null:
		_elevator_panel.unbind()
	_gate_tetris_input()
	if _gem_pickup_accum >= GEM_PICKUP_INTERVAL_SEC:
		_gem_pickup_accum = 0.0
		CityProfiler.begin("gem_pickup")
		_try_collect_nearby_gems()
		CityProfiler.end("gem_pickup")
	if _economy_accum >= ECONOMY_TICK_SEC:
		_economy_accum = 0.0
		CityProfiler.begin("district_economy")
		_tick_district_economy()
		CityProfiler.end("district_economy")
	_tick_autosave(delta)
	_tick_player_minion(delta)
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
		var radar := ""
		if _radar_reveal_left > 0.05:
			radar = "  Radar: LIVE %.0fs" % _radar_reveal_left
		elif _radar_cooldown_left > 0.05:
			radar = "  Radar: %.0fs" % _radar_cooldown_left
		else:
			radar = "  Radar: ready (U)"
		if _loadout != null and _loadout.scores():
			_hud.text = "%d FPS%s  Score: %d%s" % [
				Engine.get_frames_per_second(), clock, _player_score, radar
			]
		else:
			_hud.text = "%d FPS%s  Sandbox%s" % [
				Engine.get_frames_per_second(), clock, radar
			]


func _create_terrain() -> void:
	if _terrain != null and is_instance_valid(_terrain):
		## Detach before queue_free so the name "VoxelTerrain" is free. Leaving the old
		## node in the tree until end-of-frame makes Godot rename the replacement
		## (VoxelTerrain2), and MonsterRoster's child lookup then finds nothing.
		remove_child(_terrain)
		_terrain.queue_free()
		_terrain = null
		_tool = null
		_brush = null
		_interior_decorator = null

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
	## Soft large bounds — streamer loads tiles inside the bubble. Tall enough for the offline
	## bake: block tops land on 16-voxel blocks (e.g. top row 223) and rebuild_y_range adds ~6
	## sky rows above that; a 220-tall ceiling left dirty rebuilds short of the band and
	## NativeNavWorld refused them.
	_terrain.bounds = AABB(Vector3(-20000, 0, -20000), Vector3(40000, 256, 40000))
	## Ceiling only — must fit a district half-diagonal (~482 vox) so data-only
	## anchors can make the full tile editable. Player viewers stay shorter below.
	_terrain.max_view_distance = 512
	_terrain.generate_collisions = true
	_tool = _terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	## Gameplay edits are already in world voxel space, so no origin offset.
	_brush = CityBrushScript.new(_tool) as CityBrush
	_interior_decorator = InteriorDecoratorScript.new() as InteriorDecorator
	_interior_decorator.brush = _brush
	_interior_decorator.voxel_size = VOXEL_SIZE
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
	if _tendril_hud != null and is_instance_valid(_tendril_hud):
		_tendril_hud.call("bind_director", _infection)


func get_economy() -> DistrictEconomy:
	return _economy


## Where a district's game tables park an unfinished match. The Gaming arena reaches for
## this through the `city_root` group whenever it is rebuilt.
func world_games() -> WorldGames:
	return _games


func get_player_score() -> int:
	return _player_score


func get_loadout() -> PlayerLoadout:
	return _loadout


func can_use_ability(ability_id: String) -> bool:
	return _loadout != null and _loadout.is_unlocked(ability_id)


func knows_recipe(recipe_id: String) -> bool:
	return _loadout != null and _loadout.knows_recipe(recipe_id)


func knows_ability_schematic(ability_id: String) -> bool:
	return _loadout != null and _loadout.knows_ability_schematic(ability_id)


func ability_for_mouse_action(action: String) -> String:
	if _loadout == null:
		return ""
	var slot := AbilityRegistry.mouse_slot_for_action(action)
	if slot < 0:
		return ""
	return _loadout.slot_at(slot)


func _on_ability_requested(ability_id: String) -> void:
	activate_ability(ability_id)


func _on_tray_assign_changed() -> void:
	## Tray binds are part of the save; mark the next autosave sooner by zeroing the accumulator.
	_autosave_accum = maxf(_autosave_accum, AUTOSAVE_INTERVAL_SEC - 5.0)


## Fire a tray ability: builds, weapons, powers, consumables.
func activate_ability(ability_id: String) -> void:
	if ability_id.is_empty() or _walker == null or not is_instance_valid(_walker):
		return
	if _game_over or not is_player_alive():
		return
	var def := AbilityRegistry.get_def(ability_id)
	if def == null:
		push_error("CityRoot.activate_ability: unknown '%s'" % ability_id)
		return
	if not can_use_ability(ability_id):
		print("CityRoot: '%s' is locked — unlock it with gems" % def.display_name)
		return
	match ability_id:
		AbilityRegistry.ID_BLASTER:
			_walker.begin_blaster()
		AbilityRegistry.ID_LASER:
			_walker.fire_laser_at_cursor()
		AbilityRegistry.ID_CHARGED_BLAST:
			_walker.begin_charged_blast()
		AbilityRegistry.ID_STOMP:
			_walker.fire_stomp()
		AbilityRegistry.ID_SHIELD:
			_walker.toggle_shield()
		AbilityRegistry.ID_GROW:
			_activate_grow_shrink(true)
		AbilityRegistry.ID_SHRINK:
			_activate_grow_shrink(false)
		AbilityRegistry.ID_MINION:
			_spawn_minion()
		AbilityRegistry.ID_DISTRICT_HOP:
			_walker.request_district_hop()
		AbilityRegistry.ID_TETRIS:
			_walker.request_tetris()
		AbilityRegistry.ID_USE_TRAP:
			_throw_trap()
		AbilityRegistry.ID_USE_BOOST_SPEED:
			_drink_boost(InventoryCatalog.ID_BOOST_SPEED)
		AbilityRegistry.ID_USE_BOOST_REGEN:
			_drink_boost(InventoryCatalog.ID_BOOST_REGEN)
		_:
			if def.kind == AbilityRegistry.KIND_BUILD:
				_on_build_chosen(ability_id)
			else:
				push_error("CityRoot.activate_ability: no verb for '%s'" % ability_id)


func try_unlock_ability(ability_id: String) -> bool:
	var def := AbilityRegistry.get_def(ability_id)
	if def == null:
		push_error("CityRoot.try_unlock_ability: unknown '%s'" % ability_id)
		return false
	if def.unlock_cost.is_empty():
		push_error("CityRoot.try_unlock_ability: '%s' has no unlock cost" % ability_id)
		return false
	if _loadout.is_unlocked(ability_id):
		return false
	## Gems alone no longer buy a power: the run has to have found the schematic for it.
	if not _loadout.knows_ability_schematic(ability_id):
		print("CityRoot: no schematic for '%s' yet" % def.display_name)
		return false
	for item_id: Variant in def.unlock_cost.keys():
		var need := int(def.unlock_cost[item_id])
		if _inventory.count_of(str(item_id)) < need:
			print("CityRoot: cannot afford unlock '%s'" % def.display_name)
			return false
	for item_id: Variant in def.unlock_cost.keys():
		var need := int(def.unlock_cost[item_id])
		if not _inventory.remove(str(item_id), need):
			push_error("CityRoot: unlock spend failed for '%s'" % item_id)
			return false
	_loadout.mark_unlocked(ability_id)
	if _ability_tray != null:
		_ability_tray.refresh()
	print("CityRoot: unlocked %s" % def.display_name)
	return true


func _activate_grow_shrink(grow: bool) -> void:
	if not _walker.try_spend_energy(AbilityRegistry.get_def(
		AbilityRegistry.ID_GROW if grow else AbilityRegistry.ID_SHRINK
	).energy_cost):
		return
	var target := (
		minf(_walker.get_character_scale() * 1.45, _walker.scale_max) if grow
		else maxf(_walker.get_character_scale() / 1.45, _walker.scale_min)
	)
	_walker.begin_temp_scale(target, AbilityRegistry.GROW_SHRINK_DURATION_SEC)


func _spawn_minion() -> void:
	_prune_player_minion()
	var def := AbilityRegistry.get_def(AbilityRegistry.ID_MINION)
	if not _walker.try_spend_energy(def.energy_cost):
		return
	var body_id := _roll_random_summon_id()
	if body_id.is_empty():
		push_error("CityRoot._spawn_minion: empty spawnable roster")
		assert(false, "CityRoot: empty minion roster")
		return
	var stand := _walker.global_position + Vector3(1.2, 0.0, 0.0)
	var unit := spawn_monster_at(body_id, stand)
	if unit == null:
		push_error("CityRoot._spawn_minion: spawn refused for '%s'" % body_id)
		return
	## Replace only after the new body exists so a failed spawn keeps the old ally.
	_dismiss_player_minion()
	unit.become_player_minion()
	_player_minion = unit
	_player_minion_life_left = AbilityRegistry.MINION_DURATION_SEC
	if not unit.died.is_connected(_on_player_minion_died):
		unit.died.connect(_on_player_minion_died)
	_bind_player_minion_hud(unit)
	print(
		"CityRoot: player minion %s (human, half power, %.0fs)"
		% [body_id, AbilityRegistry.MINION_DURATION_SEC]
	)


func _prune_player_minion() -> void:
	if _player_minion == null:
		return
	if not is_instance_valid(_player_minion) or not _player_minion.is_alive():
		_player_minion = null
		_player_minion_life_left = 0.0
		_clear_player_minion_hud()


func _dismiss_player_minion() -> void:
	_prune_player_minion()
	if _player_minion == null:
		return
	var old := _player_minion
	_player_minion = null
	_player_minion_life_left = 0.0
	_clear_player_minion_hud()
	if old.died.is_connected(_on_player_minion_died):
		old.died.disconnect(_on_player_minion_died)
	despawn_undead_unit(old)


func _on_player_minion_died(unit: UndeadUnit, _was_giant: bool) -> void:
	if _player_minion == unit:
		_player_minion = null
		_player_minion_life_left = 0.0
		_clear_player_minion_hud()


func _bind_player_minion_hud(unit: UndeadUnit) -> void:
	if _health_hud == null or not is_instance_valid(_health_hud):
		return
	_health_hud.call("bind_minion", unit)


func _clear_player_minion_hud() -> void:
	if _health_hud == null or not is_instance_valid(_health_hud):
		return
	_health_hud.call("clear_minion")


func _tick_player_minion(delta: float) -> void:
	_prune_player_minion()
	if _player_minion == null:
		return
	_player_minion_life_left -= delta
	if _player_minion_life_left <= 0.0:
		print("CityRoot: player minion expired")
		_dismiss_player_minion()


func _throw_trap() -> void:
	if _inventory.count_of(InventoryCatalog.ID_TRAP) <= 0:
		print("CityRoot: no traps in inventory")
		return
	if _walker == null or not is_instance_valid(_walker):
		push_error("CityRoot._throw_trap: no walker")
		return
	## Same world-voxel aim as meteor / monster summon — cursor ray + destructibles, no agent magnet.
	var aim: Dictionary = _walker.aim_world_at_cursor()
	if not bool(aim.get("did_hit", false)):
		print("CityRoot: trap throw cancelled — world aim missed")
		return
	if not _inventory.remove(InventoryCatalog.ID_TRAP, 1):
		return
	var origin := _walker.global_position + Vector3(0.0, 1.2 * maxf(_walker.character_scale, 0.5), 0.0)
	var target: Vector3 = aim["point"] as Vector3
	var proj: TrapProjectile = TrapProjectileScript.new() as TrapProjectile
	proj.name = "TrapProjectile"
	add_child(proj)
	proj.global_position = origin
	proj.linear_velocity = _trap_throw_velocity(origin, target)
	proj.landed.connect(_on_trap_landed)


## Ballistic lob that lands near `target` under TrapProjectile's gravity_scale.
func _trap_throw_velocity(origin: Vector3, target: Vector3) -> Vector3:
	const GRAVITY_SCALE := 1.35
	var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) * GRAVITY_SCALE
	var to := target - origin
	var flat := Vector3(to.x, 0.0, to.z).length()
	## Longer / higher aims get more airtime so the arc stays readable and the formula stays stable.
	var flight := clampf(flat / 11.0, 0.4, 1.75)
	if to.y > 2.0:
		flight = maxf(flight, 0.55 + to.y * 0.08)
	if to.length_squared() < 0.0001:
		return Vector3.UP * 8.0
	return Vector3(
		to.x / flight,
		(to.y + 0.5 * g * flight * flight) / flight,
		to.z / flight
	)


func _on_trap_landed(trap: ArmedTrap) -> void:
	if trap == null:
		return
	trap.triggered.connect(_on_trap_triggered)


func _on_trap_triggered(victim: Node3D) -> void:
	if victim == null or not _loadout.scores():
		return
	## Hostile = undead unit. Peds and the player do not pay.
	var is_hostile := victim.is_in_group("undead")
	if not is_hostile and victim.get_script() != null:
		is_hostile = String(victim.get_script().resource_path).ends_with("undead_unit.gd")
	if is_hostile:
		_player_score += AbilityRegistry.TRAP_HOSTILE_SCORE
		print(
			"CityRoot: trapped a hostile (+%d, score %d)"
			% [AbilityRegistry.TRAP_HOSTILE_SCORE, _player_score]
		)


func _drink_boost(item_id: String) -> void:
	if _inventory.count_of(item_id) <= 0:
		print("CityRoot: no %s in inventory" % item_id)
		return
	if not _inventory.remove(item_id, 1):
		return
	if item_id == InventoryCatalog.ID_BOOST_SPEED:
		_walker.begin_speed_boost(AbilityRegistry.BOOST_DURATION_SEC)
	elif item_id == InventoryCatalog.ID_BOOST_REGEN:
		_walker.begin_regen_boost(AbilityRegistry.BOOST_DURATION_SEC)


## Roll a budget for every tile the run has just reached, and pay exploration for the tile the
## player is standing in. Both happen once per coord, ever, and both are cheap enough to sweep.
func _tick_district_economy() -> void:
	if _streamer == null or _booting:
		return
	for entry in _streamer.get_loaded_districts():
		var inst := _as_district_instance(entry)
		if inst == null or not inst.is_ready or inst.generator == null:
			continue
		if _loadout.uses_gem_budgets():
			_ensure_district_row(inst)
	## After the sweep so we never unload a district mid-iteration.
	if not _hill_budget_reloads.is_empty() and _streamer != null:
		var pending := _hill_budget_reloads.duplicate()
		_hill_budget_reloads.clear()
		for coord: Vector2i in pending:
			print("CityRoot: reloading hill %s to stamp repaired gem budget" % str(coord))
			_streamer.reload_district(coord)
	if _game_over or _walker == null or not is_instance_valid(_walker):
		return
	if not _loadout.scores():
		return
	var here := DistrictCoord.from_world(_walker.global_position, VOXEL_SIZE)
	if not _economy.has_row(here):
		## Sandbox skipped rows; Adventure always ensures above. Still explore-mark if a row exists.
		if _loadout.uses_gem_budgets():
			return
		## Adventure-less path shouldn't score; already returned.
		return
	if _economy.mark_explored(here):
		var explore := preload("res://scripts/city/game_data.gd").explore_score()
		DistrictEconomy.EXPLORE_SCORE = explore
		_player_score += explore
		var place := DistrictName.for_district(city_seed, here)
		## Same beat as a chest: say what happened and play the haul flourish so the score
		## bump is not only a number ticking in the status line.
		if _loot_toast != null:
			_loot_toast.show_message("%s — +%d explore" % [place, explore])
		if _audio != null:
			_audio.play_treasure_bling()
		print(
			"CityRoot: explored %s (+%d, score %d)"
			% [str(here), explore, _player_score]
		)


## Hill tiles whose ledger was repaired while already stamped — re-bake so ore matches.
var _hill_budget_reloads: Array[Vector2i] = []


## First create of a coord in this run: fix what it will ever pay out from the theme constant.
## Hills use the same table; the bake paints exactly whatever is still remaining.
func _ensure_district_row(inst: DistrictInstance) -> void:
	if inst == null or inst.generator == null or inst.generator.theme == null:
		return
	## Seed + coord decide the theme — never trust a stale generator field for the budget.
	var theme := DistrictTheme.for_district(city_seed, inst.coord)
	var dseed := DistrictCoord.district_seed(city_seed, inst.coord)
	if theme.id == DistrictTheme.HILL:
		## May repair a stale wrong-theme row left by an earlier bug / save.
		if _economy.ensure_hill_row(inst.coord, dseed):
			var want := preload("res://scripts/city/game_data.gd").theme_gem_total(
				DistrictTheme.HILL
			)
			print(
				"CityRoot: district %s (%s) owes %d gems"
				% [str(inst.coord), theme.display_name, _economy.remaining_total(inst.coord)]
			)
			## Ledger alone is not enough — a ready hill still has the short ore stamp.
			if (
				inst.is_ready
				and not inst.is_busy
				and inst.hill_gem_mats.size() < want
				and not _hill_budget_reloads.has(inst.coord)
			):
				_hill_budget_reloads.append(inst.coord)
		return
	if _economy.has_row(inst.coord):
		return
	var budgets := DistrictEconomy.roll_budgets(theme.id, dseed)
	_economy.ensure_row(inst.coord, budgets, theme.id)
	print(
		"CityRoot: district %s (%s) owes %d gems"
		% [str(inst.coord), theme.display_name, _economy.remaining_total(inst.coord)]
	)


## Gems a hill bake should paint: the district constant, or that minus already harvested.
## Called on the main thread before the worker starts so the ledger and voxels stay one thing.
func hill_gem_paint_list(coord: Vector2i) -> PackedInt32Array:
	var dseed := DistrictCoord.district_seed(city_seed, coord)
	var theme := DistrictTheme.for_district(city_seed, coord)
	assert(
		theme.id == DistrictTheme.HILL,
		"hill_gem_paint_list called for non-hill %s (%s)" % [str(coord), theme.display_name]
	)
	if _loadout == null or not _loadout.uses_gem_budgets():
		## Sandbox: always the full mine.
		return DistrictEconomy.flat_gem_list(
			DistrictEconomy.roll_budgets(DistrictTheme.HILL, dseed)
		)
	if _economy.ensure_hill_row(coord, dseed):
		print(
			"CityRoot: district %s (Hill) owes %d gems"
			% [str(coord), _economy.remaining_total(coord)]
		)
	var paint := _economy.remaining_flat_list(coord)
	var want := preload("res://scripts/city/game_data.gd").theme_gem_total(DistrictTheme.HILL)
	## A mined hill paints what is left of it, so a short list is only a defect when the gems
	## are not accounted for by the harvest: that is a ledger rolled against another theme's
	## total, which `ensure_hill_row` cannot repair once the tile has been dug.
	var harvested := _economy.harvested_total(coord)
	if paint.size() + harvested < want:
		push_error(
			"CityRoot: hill %s paint list is %d with %d harvested, theme budget %d"
			% [str(coord), paint.size(), harvested, want]
		)
	return paint


## Spend one gem of `mat_id` from the district that holds `world_vox`.
func try_take_district_gem(world_vox: Vector3i, mat_id: int) -> bool:
	var coord := _district_coord_for_vox(world_vox)
	_ensure_economy_at_coord(coord)
	return _economy.try_take(coord, mat_id)


func _district_coord_for_vox(world_vox: Vector3i) -> Vector2i:
	var world := Vector3(
		(float(world_vox.x) + 0.5) * VOXEL_SIZE,
		(float(world_vox.y) + 0.5) * VOXEL_SIZE,
		(float(world_vox.z) + 0.5) * VOXEL_SIZE
	)
	return DistrictCoord.from_world(world, VOXEL_SIZE)


func _ensure_economy_at_coord(coord: Vector2i) -> void:
	if not _loadout.uses_gem_budgets():
		return
	var inst := _district_at_coord(coord)
	if inst != null and inst.is_ready:
		_ensure_district_row(inst)


## A room was just furnished, so it may get a chest. The decorator paints voxels and nothing else,
## and a chest is a node with an animated lid — so this is where it is stood up.
func _try_place_room_chest() -> void:
	var room := _interior_decorator.take_furnished_room()
	if room.is_empty():
		return
	var purpose := int(room["purpose"])
	var room_seed := int(room["seed"])
	if not GemChestPlacer.should_place(purpose, room_seed):
		return
	var coord: Vector2i = room["coord"] as Vector2i
	var inst := _district_at_coord(coord)
	if inst == null:
		## The tile unloaded between the paint and this frame. Nothing to hang the chest on.
		return
	var spot := _chest_spot_in_room(room)
	if spot == Vector3i(2147483647, 2147483647, 2147483647):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = room_seed ^ 0x43455354
	## X and Z centred in the cell, Y at its floor — the model's own origin is its base.
	var world := Vector3(
		(float(spot.x) + 0.5) * VOXEL_SIZE,
		float(spot.y) * VOXEL_SIZE,
		(float(spot.z) + 0.5) * VOXEL_SIZE
	)
	## Quarter turns only: a chest shoved against a wall is not sitting at 37 degrees to it.
	var yaw := float(rng.randi_range(0, 3)) * (PI * 0.5)
	var chest := inst.ensure_gem_chests().place_chest(coord, world, yaw, room_seed)
	if chest == null:
		return
	print(
		"CityRoot: chest in %s room of district %s at %s"
		% [RoomDecorator.purpose_name(purpose as RoomDecorator.Purpose), str(coord), str(spot)]
	)


## A free floor cell in the furnished room. The wall ring is tried first — a chest belongs against
## the masonry rather than in the middle of the carpet — and then the rest of the floor, because
## the rooms likeliest to hold a chest are the ones the decorator has already lined with crates.
## The sentinel means the room has no clear floor left at all.
##
## `floor_y` is the topmost *solid* slab cell (see `RoomVolume`), so a chest stands one above it.
func _chest_spot_in_room(room: Dictionary) -> Vector3i:
	var sentinel := Vector3i(2147483647, 2147483647, 2147483647)
	if _brush == null:
		return sentinel
	var rect: Rect2i = room["rect"] as Rect2i
	var stand_y := int(room["floor_y"]) + 1
	if rect.size.x < 3 or rect.size.y < 3:
		return sentinel
	var rng := RandomNumberGenerator.new()
	rng.seed = int(room["seed"]) ^ 0x53504f54
	## Inset by one so a chest never lands inside a partition the painter just drew.
	var inner := Rect2i(rect.position + Vector2i.ONE, rect.size - Vector2i(2, 2))
	if inner.size.x < 1 or inner.size.y < 1:
		return sentinel
	var ring: Array[Vector2i] = []
	var middle: Array[Vector2i] = []
	for z in range(inner.position.y, inner.end.y):
		for x in range(inner.position.x, inner.end.x):
			var cell := Vector2i(x, z)
			var on_edge := (
				x == inner.position.x or x == inner.end.x - 1
				or z == inner.position.y or z == inner.end.y - 1
			)
			if on_edge:
				ring.append(cell)
			else:
				middle.append(cell)
	var spot := _first_standable(ring, stand_y, rng)
	if spot != sentinel:
		return spot
	return _first_standable(middle, stand_y, rng)


## The first cell of `cells` a chest fits on, scanned from a seeded offset so two rooms with the
## same shape do not both put their chest in the same corner.
func _first_standable(
	cells: Array[Vector2i], stand_y: int, rng: RandomNumberGenerator
) -> Vector3i:
	var sentinel := Vector3i(2147483647, 2147483647, 2147483647)
	if cells.is_empty():
		return sentinel
	var start := rng.randi_range(0, cells.size() - 1)
	for i in range(cells.size()):
		var cell: Vector2i = cells[(start + i) % cells.size()]
		var stand := Vector3i(cell.x, stand_y, cell.y)
		if not VoxelMaterial.is_solid(_brush.get_vox(stand + Vector3i(0, -1, 0))):
			continue
		if _brush.get_vox(stand) != VoxelMaterial.AIR:
			continue
		if _brush.get_vox(stand + Vector3i(0, 1, 0)) != VoxelMaterial.AIR:
			continue
		return stand
	return sentinel


func _district_at_coord(coord: Vector2i) -> DistrictInstance:
	if _streamer == null:
		return null
	for entry in _streamer.get_loaded_districts():
		var inst := _as_district_instance(entry)
		if inst != null and inst.coord == coord:
			return inst
	return null


## Theme id for a currently loaded district, or -1 when that tile is not in memory.
func get_loaded_district_theme_id(coord: Vector2i) -> int:
	var inst := _district_at_coord(coord)
	if inst == null or inst.generator == null or inst.generator.theme == null:
		return -1
	return inst.generator.theme.id


## Hand the player one gem. When `from_budget` is true, spends the district ledger (town chests /
## canopy). Hill cave ore uses the ledger only when voxels are collected — chests pass false.
func grant_district_gem(coord: Vector2i, mat_id: int, from_budget: bool = true) -> bool:
	var item_id := InventoryCatalog.item_id_for_gem(mat_id)
	if item_id == "":
		push_error("CityRoot.grant_district_gem: %d is not a gem" % mat_id)
		return false
	if from_budget and _loadout.uses_gem_budgets():
		_ensure_economy_at_coord(coord)
		if not _economy.try_take(coord, mat_id):
			return false
	var leftover := _inventory.add(item_id, 1)
	if leftover != 0:
		push_error("CityRoot: inventory full — gem %s could not be stored" % item_id)
	## No chime here: a chest pays several stones in one frame, and the caller plays one sound for
	## the whole find. The card is what shows each stone.
	if _loot_toast != null:
		_loot_toast.add_item(item_id, 1)
	return true


## A chest was opened: the lid at the chest, and — if it actually paid — the haul flourish over the
## card the grants have already filled in. The chest knows what happened; the audio and the HUD live
## here, so this is where the two are put together.
##
## Called after the grants, so `gems_paid` is settled and the card can be named for what it was.
func report_chest_opened(world_pos: Vector3, gems_paid: int) -> void:
	if _audio != null:
		_audio.play_chest_open(world_pos)
	if _loot_toast == null:
		return
	if gems_paid <= 0:
		## Worth saying: an open chest with nothing in it otherwise looks like a bug rather than
		## like a district that has already been picked clean.
		_loot_toast.show_message("The chest is empty")
		return
	_loot_toast.set_headline("Chest opened")
	if _audio != null:
		_audio.play_treasure_bling()


## Gems handed out when the cookbook is already complete. Nothing cheap: the spot was worth a
## scroll, so it stays worth the climb after the last recipe is known.
## Resolved from gamedata `recipe_sites.fallback_gems` on first use.
var _recipe_fallback_gems: Array[int] = []


func is_recipe_site_looted(site_id: String) -> bool:
	return _loadout != null and _loadout.is_recipe_site_looted(site_id)


## A scroll was opened. This is the only place a recipe pickup decides what it was: one recipe
## the run is still missing, or — once there are none left — a rare gem instead. Returns true
## when the find paid anything at all.
func collect_recipe_pickup(site_id: String, world_pos: Vector3) -> bool:
	if _loadout == null:
		push_error("CityRoot.collect_recipe_pickup: no loadout to learn into")
		return false
	if _loadout.is_recipe_site_looted(site_id):
		return false
	_loadout.mark_recipe_site_looted(site_id)
	var missing := _loadout.missing_recipe_ids()
	if missing.is_empty():
		return _pay_recipe_fallback_gem(site_id, world_pos)
	## Seeded by the site, so the same scroll always turns out to be the same recipe for a given
	## run — reloading an autosave taken a step earlier cannot re-roll it into a better one.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(site_id) ^ int(city_seed)
	var recipe_id := missing[rng.randi_range(0, missing.size() - 1)]
	if not _loadout.learn_recipe(recipe_id):
		push_error("CityRoot: recipe '%s' was already known" % recipe_id)
		return false
	var recipe := InventoryCatalog.recipe(recipe_id)
	var label := recipe_id if recipe == null else recipe.display_name
	if _audio != null:
		_audio.play_chest_open(world_pos)
		_audio.play_treasure_bling()
	if _loot_toast != null:
		## A chest can pay stones and a scroll in the same click. Resetting the card there would
		## throw away the gems that were just put on it, so an open card is only renamed.
		if _loot_toast.is_showing():
			_loot_toast.set_headline("Recipe learned — %s" % label)
		else:
			_loot_toast.show_message("Recipe learned — %s" % label)
	if _inventory_panel != null and _inventory_panel.has_method("rebuild_recipe_lists"):
		_inventory_panel.call("rebuild_recipe_lists")
	if _ability_tray != null:
		_ability_tray.refresh()
	print("CityRoot: learned recipe '%s' at %s" % [recipe_id, site_id])
	return true


## The cookbook is full, so the scroll pays a stone instead. Off-budget like a hill chest: the
## district ledger is for what is buried in the tile, and this is a reward for standing here.
func _recipe_fallback_gem_mats() -> Array[int]:
	if not _recipe_fallback_gems.is_empty():
		return _recipe_fallback_gems
	const GameDataScript := preload("res://scripts/city/game_data.gd")
	var raw: Variant = GameDataScript.recipe_sites().get("fallback_gems", [])
	if typeof(raw) == TYPE_ARRAY:
		for item_id_v: Variant in raw:
			var item_id := str(item_id_v)
			var def := InventoryCatalog.item(item_id)
			if def == null or def.gem_mat_id < 0:
				push_error("CityRoot: fallback gem '%s' is not a gem item" % item_id)
				continue
			_recipe_fallback_gems.append(def.gem_mat_id)
	if _recipe_fallback_gems.is_empty():
		_recipe_fallback_gems = [VoxelMaterial.GEM_EMERALD, VoxelMaterial.GEM_DIAMOND]
	return _recipe_fallback_gems


func _pay_recipe_fallback_gem(site_id: String, world_pos: Vector3) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(site_id) ^ int(city_seed)
	var gems := _recipe_fallback_gem_mats()
	var gem: int = gems[rng.randi_range(0, gems.size() - 1)]
	var coord := DistrictCoord.from_world(world_pos, VOXEL_SIZE)
	if not grant_district_gem(coord, gem, false):
		push_error("CityRoot: recipe cache could not pay a gem at %s" % site_id)
		return false
	if _audio != null:
		_audio.play_chest_open(world_pos)
		_audio.play_treasure_bling()
	if _loot_toast != null:
		_loot_toast.set_headline("Recipe cache — nothing new to learn")
	print("CityRoot: recipe cache at %s paid a gem instead" % site_id)
	return true


func get_loot_toast() -> LootToast:
	return _loot_toast


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


## Pull a gem vein: the struck/touched cell plus every same-type neighbour in the local cluster.
## Feedback matches chests — one loot card + treasure bling for the whole haul.
##
## A visible gem always pays. Anti-farm is "the next bake only paints what is still remaining",
## not "refuse a voxel that is sitting in front of you".
func try_collect_gem_at(vox: Vector3i) -> bool:
	var cluster := _gem_cluster_at(vox)
	if cluster.is_empty():
		return false
	var paid := 0
	var pitch_mat := -1
	for cell: Vector3i in cluster:
		var credited_mat := _collect_gem_voxel(cell)
		if credited_mat >= 0:
			paid += 1
			if pitch_mat < 0:
				pitch_mat = credited_mat
	var local := Vector3(float(vox.x) + 0.5, float(vox.y) + 0.5, float(vox.z) + 0.5)
	var world := _terrain.to_global(local) if _terrain != null else local * VOXEL_SIZE
	report_gem_haul(world, paid, pitch_mat)
	return true


## Off-budget gem haul when the player kills a monster. Score is floor(max_hp / 40), paid as
## tiered stones (see MonsterGemDrop). District ledger is not charged.
##
## During a Siege run the haul feeds the pot instead of the inventory — skin in the game, and
## the unbounded wave faucet never touches the progression economy until the player withdraws.
func grant_monster_kill_haul(world_pos: Vector3, max_hp: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var siege := active_siege_run()
	## Siege waves are mostly KayKit fodder under the global score floor (floor(hp/40) = 0).
	## Without a one-stone floor the pot never refills after the stake and the run starves.
	var haul: Array[int] = MonsterGemDropScript.roll_mats(
		max_hp, rng, 1 if siege != null else 0
	)
	if haul.is_empty():
		return
	if siege != null:
		var pot_paid := siege.credit_kill_mats(haul)
		if pot_paid <= 0:
			return
		## The pot is the inventory during a run — still put every stone on the loot card.
		## `report_gem_haul` alone only sets a headline; without `add_gem` the card never
		## becomes visible, so a kill looked like it paid nothing even when the pot moved.
		if _loot_toast != null:
			for gem in haul:
				_loot_toast.add_gem(gem, 1)
		report_gem_haul(world_pos, pot_paid, haul[0])
		if _loot_toast != null:
			_loot_toast.set_headline("Siege pot")
		return
	var vox := Vector3i.ZERO
	if _terrain != null:
		var local := _terrain.to_local(world_pos)
		vox = Vector3i(int(floor(local.x)), int(floor(local.y)), int(floor(local.z)))
	var coord := _district_coord_for_vox(vox)
	var paid := 0
	var pitch_mat := -1
	for gem in haul:
		if grant_district_gem(coord, gem, false):
			paid += 1
			if pitch_mat < 0:
				pitch_mat = gem
	if paid <= 0:
		return
	report_gem_haul(world_pos, paid, pitch_mat)
	## report_gem_haul names a generic find — kill hauls get their own card title after.
	if _loot_toast != null:
		_loot_toast.set_headline("Monster slain")


## Same flourish as a chest haul: one card headline and one bling for every stone already stacked
## on the toast. Cave ore also plays the gem chime once so a dug vein still sings.
func report_gem_haul(world_pos: Vector3, gems_paid: int, mat_id: int = -1) -> void:
	if gems_paid <= 0:
		return
	if _loot_toast != null:
		_loot_toast.set_headline("Gems found")
	if _audio == null:
		return
	_audio.play_gem_pickup(world_pos, mat_id)
	_audio.play_treasure_bling()


## Clear one visible gem cell and credit inventory. Always pays; the ledger tracks harvest so the
## next hill bake paints fewer. Returns the gem material id, or -1 if the cell was not a gem.
func _collect_gem_voxel(vox: Vector3i) -> int:
	var mat_id := _gem_id_at(vox)
	if not VoxelMaterial.is_gem(mat_id):
		return -1
	var item_id := InventoryCatalog.item_id_for_gem(mat_id)
	if item_id == "":
		return -1
	if _brush == null and _tool == null:
		return -1
	_clear_gem_voxel(vox)
	if _loadout != null and _loadout.uses_gem_budgets():
		var coord := _district_coord_for_vox(vox)
		_ensure_economy_at_coord(coord)
		## Visible always pays. Prefer the matching type; if a chest already spent that slot,
		## burn any remaining so the next hill bake still shrinks.
		if not _economy.try_take(coord, mat_id):
			_economy.try_take_any(coord)
	var leftover := _inventory.add(item_id, 1)
	if leftover != 0:
		push_error("CityRoot: inventory full — gem %s could not be stored" % item_id)
	if _loot_toast != null:
		_loot_toast.add_item(item_id, 1)
	return mat_id


func _clear_gem_voxel(vox: Vector3i) -> void:
	if _brush != null:
		_brush.set_vox(vox, VoxelMaterial.AIR)
	elif _tool != null:
		_tool.channel = VoxelBuffer.CHANNEL_TYPE
		_tool.set_voxel(vox, VoxelMaterial.AIR)


func _gem_id_at(vox: Vector3i) -> int:
	if _brush != null:
		return _brush.get_vox(vox)
	if _tool == null:
		return VoxelMaterial.AIR
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	return int(_tool.get_voxel(vox))


## 6-connected same-type gem cells around `origin`, capped so a pathologically huge paint cannot
## wipe a whole hillside in one click.
func _gem_cluster_at(origin: Vector3i) -> Array[Vector3i]:
	var start_id := _gem_id_at(origin)
	if not VoxelMaterial.is_gem(start_id):
		return []
	var out: Array[Vector3i] = []
	var seen: Dictionary = {}
	var queue: Array[Vector3i] = [origin]
	seen[origin] = true
	var dirs: Array[Vector3i] = [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	]
	while not queue.is_empty() and out.size() < GEM_CLUSTER_MAX:
		var p: Vector3i = queue.pop_front()
		out.append(p)
		for d: Vector3i in dirs:
			var n: Vector3i = p + d
			if seen.has(n):
				continue
			if _gem_id_at(n) != start_id:
				continue
			seen[n] = true
			queue.append(n)
	return out


## Walk-up pickup: any gem within arm's reach of the chest is taken (whole local cluster).
func _try_collect_nearby_gems() -> void:
	if _terrain == null or not is_player_alive():
		return
	if _brush == null and _tool == null:
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
	for z in range(cz - r_vox, cz + r_vox + 1):
		for y in range(cy - r_vox, cy + r_vox + 1):
			for x in range(cx - r_vox, cx + r_vox + 1):
				var center := Vector3(float(x) + 0.5, float(y) + 0.5, float(z) + 0.5)
				if center.distance_squared_to(local) > r2 + 0.0001:
					continue
				var cell := Vector3i(x, y, z)
				if VoxelMaterial.is_gem(_gem_id_at(cell)):
					try_collect_gem_at(cell)


func get_player_position() -> Vector3:
	if _walker != null and is_instance_valid(_walker) and not _game_over:
		return _walker.global_position
	return Vector3.INF


## Living player body, or null. Used when a hit promotes the attacker as pursuit prey.
func get_player_node() -> Node:
	if not is_player_alive():
		return null
	return _walker


## MonsterFaction.Id the player fights as — human until a faction-change power exists.
func player_faction() -> int:
	if _walker != null and is_instance_valid(_walker):
		return _walker.combat_faction()
	return MonsterFactionScript.Id.HUMAN


## Put the player on another side. The Monster Zoo's spectator cloak is the only caller,
## and it always hands HUMAN back when the cloak lapses.
func set_player_combat_faction(id: int) -> void:
	if _walker == null or not is_instance_valid(_walker):
		return
	_walker.set_combat_faction(id)


## Objectives that bypass aggro range and line of sight. `UndeadGoalProvider` reads this when a
## body has nothing living to hunt; the Siege Quarter's stones are the only registrars today.
func beacon_registry() -> BeaconRegistry:
	return _beacons


## Cells no damage may take, claimed by whatever structure is standing on them. Siege towers claim
## their stamp while they live and drop it when they die.
func voxel_ward() -> VoxelWard:
	return _ward


## Active Siege Quarter run, or null. Kill hauls and streaming pin consult this.
func active_siege_run() -> SiegeController:
	if _siege_run != null and is_instance_valid(_siege_run) and _siege_run.is_running():
		return _siege_run
	return null


## Called by SiegeController when a run starts. One run at a time — a second start is a bug.
func begin_siege_run(ctrl: SiegeController) -> void:
	if ctrl == null or not is_instance_valid(ctrl):
		push_error("CityRoot.begin_siege_run: null controller")
		assert(false, "CityRoot: null siege controller")
		return
	if _siege_run != null and is_instance_valid(_siege_run) and _siege_run != ctrl:
		push_error("CityRoot.begin_siege_run: a siege is already running")
		assert(false, "CityRoot: overlapping siege runs")
		return
	_siege_run = ctrl


func end_siege_run(ctrl: SiegeController) -> void:
	if _siege_run == ctrl:
		_siege_run = null


## Spectator cloak countdown, driven by whichever Monster Zoo granted the cloak.
func show_zoo_cloak(seconds_left: float) -> void:
	if _zoo_cloak_hud != null and is_instance_valid(_zoo_cloak_hud):
		_zoo_cloak_hud.call("show_countdown", seconds_left)


func hide_zoo_cloak() -> void:
	if _zoo_cloak_hud != null and is_instance_valid(_zoo_cloak_hud):
		_zoo_cloak_hud.call("hide_countdown")


## Pedestrians are civilians, not authored bodies: they are human, all of them.
func ped_faction() -> int:
	return MonsterFactionScript.Id.HUMAN


func is_player_alive() -> bool:
	return not _game_over and _walker != null and is_instance_valid(_walker)


func get_minimap_snapshot(range_m: float = 100.0) -> Dictionary:
	var origin := Vector3.ZERO
	var yaw := 0.0
	if _walker != null and is_instance_valid(_walker):
		origin = _walker.global_position
		yaw = _walker.rotation.y
	var buildings: Array = []
	if _streamer != null:
		for entry in _streamer.get_loaded_districts():
			var inst := _as_district_instance(entry)
			if inst == null or not is_instance_valid(inst) or inst.building_lod == null:
				continue
			for b in inst.building_lod.get_footprints_near(origin, range_m):
				buildings.append(b)
	var undead: Array = []
	var radar_on := _radar_reveal_left > 0.0
	var range_r2 := range_m * range_m
	if _monsters != null and is_instance_valid(_monsters):
		for u: UndeadUnit in _monsters.get_alive_units():
			if u == null or not is_instance_valid(u):
				continue
			var pos := u.global_position
			var dx := pos.x - origin.x
			var dz := pos.z - origin.z
			var d2 := dx * dx + dz * dz
			var outside := d2 > range_r2
			## Nearby monsters always paint; beyond-range only while radar is live.
			if outside and not radar_on:
				continue
			var kind := "mage"
			if u.is_giant():
				kind = "giant"
			elif u.role == UndeadUnit.Role.MINION:
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
	if not _game_over or _booting or _respawning:
		return
	## Clear immediately so double-Enter / _input+_unhandled can't double-fire.
	_game_over = false
	_respawning = true
	_hide_game_over_overlay()
	## Stay in the current world — teleport to this district's spawn point.
	_respawn_at_zone_spawn()


## Put the player back on their feet at the loaded district's spawn (Enter after death).
func _respawn_at_zone_spawn() -> void:
	if _booting:
		_respawning = false
		return
	if _walker == null or not is_instance_valid(_walker) or _streamer == null or _tool == null:
		_respawning = false
		push_error("CityRoot: respawn unavailable — regenerating world")
		call_deferred("_regenerate")
		return
	var death_pos := _walker.global_position
	var coord := DistrictCoord.from_world(death_pos, VOXEL_SIZE)
	var inst: DistrictInstance = _streamer.get_district(coord)
	if inst == null or not is_instance_valid(inst) or inst.generator == null:
		_respawning = false
		push_error("CityRoot: respawn — district %s not ready, regenerating" % coord)
		call_deferred("_regenerate")
		return
	_walker.set_physics_process(false)
	_walker.velocity = Vector3.ZERO
	var spawn: Vector3 = inst.generator.find_spawn_world(_tool)
	if not is_finite(spawn.x):
		_respawning = false
		push_error("CityRoot: respawn — no spawn in %s, regenerating" % coord)
		_walker.set_physics_process(true)
		call_deferred("_regenerate")
		return
	_walker.global_position = spawn + Vector3(0.0, 6.0, 0.0)
	_walker.velocity = Vector3.ZERO
	_apply_spawn_yaw(_walker, inst.generator)
	var footing := await _resolve_playable_footing(
		spawn, inst.generator, "respawn in %s" % coord, FOOTING_FALLBACK_MS
	)
	if not is_instance_valid(_walker):
		_respawning = false
		return
	if footing.is_empty():
		_respawning = false
		push_error("CityRoot: respawn — nowhere to stand in %s, regenerating" % coord)
		call_deferred("_regenerate")
		return
	spawn = footing["spawn"] as Vector3
	var floor_y := float(footing["floor_y"])
	_walker.global_position = Vector3(spawn.x, floor_y + 0.15, spawn.z)
	_walker.velocity = Vector3.ZERO
	_apply_spawn_yaw(_walker, inst.generator)
	if _walker.has_method("restore_full_health"):
		_walker.call("restore_full_health")
	if _walker.has_method("set_game_over_locked"):
		_walker.call("set_game_over_locked", false)
	_walker.set_physics_process(true)
	if _status != null:
		_status.visible = true
	_set_hud_enabled(true)
	## Resume systems halted on death (settings may still leave them off).
	if _undead_invasion_enabled:
		_ensure_undead_director()
		if _undead != null and _undead.has_method("set_enabled"):
			_undead.call("set_enabled", true)
	if _spawn_meteors_enabled:
		_meteor_spawn_accum = 0.0
		_roll_meteor_spawn_interval()
	_respawning = false
	print(
		"CityRoot: respawned at zone spawn %s (%s) y=%.2f"
		% [coord, DistrictTheme.for_district(city_seed, coord).display_name, floor_y]
	)


func _ensure_monster_roster() -> void:
	if _monsters == null or not is_instance_valid(_monsters):
		_monsters = MonsterRosterScript.new() as MonsterRoster
		_monsters.name = "MonsterRoster"
		add_child(_monsters)
	## Pass the live field — never rely on child-name lookup after a regenerate.
	_monsters.setup(self, _terrain)


func _ensure_undead_director() -> void:
	_ensure_monster_roster()
	if _undead == null or not is_instance_valid(_undead):
		_undead = UndeadInvasionDirectorScript.new()
		_undead.name = "UndeadInvasion"
		add_child(_undead)
	_undead.call("setup", self, _monsters)
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


## Hop to a named tile, for the teleport chambers. Same guards as the J picker, which stays
## exactly as it was — this route skips the type picker because the console already chose.
func request_district_hop_to(dest: Vector2i) -> bool:
	if _game_over or _booting or _district_hopping:
		return false
	if _walker == null or not is_instance_valid(_walker):
		return false
	if _streamer == null or not is_instance_valid(_streamer):
		return false
	if _loading_splash == null:
		push_error("CityRoot: district hop needs LoadingSplash for the bake status line")
		return false
	if dest == DistrictCoord.from_world(_walker.global_position, VOXEL_SIZE):
		return false
	_district_hopping = true
	_district_hop_to(dest, _walker.global_position)
	return true


## Run Instant Mandelbrot Create under a wait splash showing the selected fractal.
## `work` must be an async Callable (awaited). Returns false if a splash already owns the screen.
func request_fractal_create_wait(art: Texture2D, work: Callable) -> bool:
	if _game_over or _booting or _district_hopping:
		return false
	if _loading_splash == null:
		push_error("CityRoot: fractal create wait needs LoadingSplash")
		return false
	if not work.is_valid():
		push_error("CityRoot: fractal create wait needs a work Callable")
		return false
	_district_hopping = true
	_fractal_create_wait_async(art, work)
	return true


func _fractal_create_wait_async(art: Texture2D, work: Callable) -> void:
	_set_hud_enabled(false)
	var walker := _walker
	if walker != null and is_instance_valid(walker):
		walker.set_physics_process(false)
		walker.velocity = Vector3.ZERO
	_loading_splash.call("show_splash", "Creating fractal…", art)
	await work.call()
	if walker != null and is_instance_valid(walker):
		walker.set_physics_process(true)
	_district_hopping = false
	if not _booting:
		_set_hud_enabled(true)
	if _loading_splash != null:
		_loading_splash.call("hide_splash")
	print("CityRoot: fractal create wait finished")


## Unload + rebake one tile under a wait splash (Mandelbrot Clear). Player stays put.
func request_district_reload(coord: Vector2i) -> bool:
	if _game_over or _booting or _district_hopping:
		return false
	if _walker == null or not is_instance_valid(_walker):
		return false
	if _streamer == null or not is_instance_valid(_streamer):
		return false
	if _loading_splash == null:
		push_error("CityRoot: district reload needs LoadingSplash")
		return false
	_district_hopping = true
	_district_reload_async(coord)
	return true


func _district_reload_async(coord: Vector2i) -> void:
	var walker := _walker
	if walker == null or not is_instance_valid(walker):
		_district_hopping = false
		return
	var origin_pos := walker.global_position
	var stay_xz := Vector3(origin_pos.x, 0.0, origin_pos.z)
	var theme := DistrictTheme.for_district(city_seed, coord)
	print("CityRoot: district reload %s (%s)" % [coord, theme.display_name])
	_set_hud_enabled(false)
	_loading_splash.call(
		"show_splash",
		"Clearing %s %s…" % [theme.display_name, coord]
	)
	walker.set_physics_process(false)
	walker.velocity = Vector3.ZERO
	## Hover so unload does not drop the body through empty space.
	walker.global_position = stay_xz + Vector3(0.0, 40.0, 0.0)
	var inst: DistrictInstance = _streamer.call("reload_district", coord) as DistrictInstance
	if inst == null:
		await _finish_district_hop_fail("missing district instance after reload", origin_pos)
		return
	const RELOAD_WAIT_MS := 180_000
	const RELOAD_EARLY_GROUND_MS := 4_000
	const RELOAD_STATUS_EVERY_MS := 500
	var started := Time.get_ticks_msec()
	var deadline := started + RELOAD_WAIT_MS
	var last_status_ms := 0
	while not inst.is_ready and Time.get_ticks_msec() < deadline:
		if not is_instance_valid(inst):
			await _finish_district_hop_fail("district unloaded while reloading", origin_pos)
			return
		var elapsed_ms := Time.get_ticks_msec() - started
		if elapsed_ms - last_status_ms >= RELOAD_STATUS_EVERY_MS:
			last_status_ms = elapsed_ms
			var phase := "ground" if not inst.is_ground_ready else "detail"
			if inst.is_busy:
				phase += ", baking"
			_loading_splash.call(
				"set_status",
				"Rebuilding %s %s (%s, %ds)…"
				% [theme.display_name, coord, phase, elapsed_ms / 1000]
			)
		if (
			inst.is_ground_ready
			and inst.generator != null
			and not inst.is_busy
			and elapsed_ms >= RELOAD_EARLY_GROUND_MS
		):
			break
		await get_tree().process_frame
	if not is_instance_valid(inst) or inst.generator == null:
		await _finish_district_hop_fail(
			"district never became ready after %ds"
			% [(Time.get_ticks_msec() - started) / 1000],
			origin_pos
		)
		return
	if not inst.is_ready and not inst.is_ground_ready:
		await _finish_district_hop_fail(
			"district still empty after %ds"
			% [(Time.get_ticks_msec() - started) / 1000],
			origin_pos
		)
		return
	_loading_splash.call("set_status", "Finding ground…")
	var spawn := stay_xz
	if inst.generator != null and inst.generator.has_method("find_spawn_world"):
		## Prefer a street spawn near the plaza if the old feet are over void.
		var candidate: Vector3 = inst.generator.find_spawn_world(_tool)
		spawn = Vector3(stay_xz.x, candidate.y, stay_xz.z)
	walker.global_position = spawn + Vector3(0.0, 6.0, 0.0)
	walker.velocity = Vector3.ZERO
	_loading_splash.call("set_status", "Finding footing…")
	var footing := await _resolve_playable_footing(spawn, inst.generator, "reload of %s" % coord)
	if footing.is_empty():
		await _finish_district_hop_fail("no ground under spawn after reload", origin_pos)
		return
	spawn = footing["spawn"] as Vector3
	var floor_y := float(footing["floor_y"])
	walker.global_position = Vector3(spawn.x, floor_y + 0.15, spawn.z)
	walker.velocity = Vector3.ZERO
	walker.set_physics_process(true)
	if _streamer != null and _streamer.has_method("clear_priority_district"):
		_streamer.call("clear_priority_district")
	_district_hopping = false
	_set_hud_enabled(true)
	_loading_splash.call("hide_splash")
	print("CityRoot: district reload landed at y=%.2f" % floor_y)


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
	walker.set_physics_process(false)
	walker.velocity = Vector3.ZERO
	## The title splash would hide the whole point of the hop. Drop to a status line over the
	## live world so the launch, the sky and the landing are all on screen, and the bake still
	## says how far along it is.
	if _loading_splash != null:
		_loading_splash.call(
			"show_status_only",
			"Hopping to %s %s…" % [theme.display_name, dest]
		)
	_begin_hop_cutscene(walker)
	_hop_cutscene.start_rise()
	await _hop_cutscene.await_phase()
	## Park above the destination centre so the bubble scores that tile first. The camera is
	## looking at sky for this, so crossing the map is never in frame. Held a touch above where
	## the launch topped out, so the swap cannot read as a drop.
	var hover := (
		DistrictCoord.center_world(dest, VOXEL_SIZE)
		+ Vector3(0.0, DistrictHopCutsceneScript.RISE_M + 5.0, 0.0)
	)
	_hop_cutscene.start_hold(hover)
	var inst: DistrictInstance = _streamer.call("prioritize_district", dest) as DistrictInstance
	if inst == null:
		await _finish_district_hop_fail("missing district instance", origin_pos)
		return
	## Wall-clock, not frames: headed runs sit at hundreds of FPS, so a 3600-frame
	## budget was only a few seconds — too short for Hill / Graveyard bakes.
	const HOP_WAIT_MS := 180_000
	const HOP_STATUS_EVERY_MS := 500
	var hop_started := Time.get_ticks_msec()
	var hop_deadline := hop_started + HOP_WAIT_MS
	var last_status_ms := 0
	## Wait for full ready — landing on ground-only left upper block rows as AIR holes
	## (hills, castle plinths, etc.) until detail caught up under remesh pressure.
	while Time.get_ticks_msec() < hop_deadline:
		if not is_instance_valid(inst):
			await _finish_district_hop_fail("district unloaded while hopping", origin_pos)
			return
		if inst.is_ready:
			break
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
		await get_tree().process_frame
	if not is_instance_valid(inst) or inst.generator == null or not inst.is_ready:
		await _finish_district_hop_fail(
			"district never became ready after %ds"
			% [(Time.get_ticks_msec() - hop_started) / 1000],
			origin_pos
		)
		return
	if _loading_splash != null:
		_loading_splash.call("set_status", "Finding spawn in %s…" % theme.display_name)
	var spawn: Vector3 = inst.generator.find_spawn_world(_tool)
	if not _has_solid_ground_at(spawn):
		var ground_deadline := Time.get_ticks_msec() + FOOTING_PREFERRED_MS
		while not _has_solid_ground_at(spawn) and Time.get_ticks_msec() < ground_deadline:
			await get_tree().process_frame
		spawn = inst.generator.find_spawn_world(_tool)
	## Slide across to sit over the landing spot rather than the tile centre, so the blocks
	## being probed for footing are the ones the bubble is keeping loaded — and so the descent
	## comes straight down on the district instead of sliding across it. Still invisible: the
	## camera is on the sky until the descent starts.
	walker.global_position = Vector3(spawn.x, walker.global_position.y, spawn.z)
	## Footing is resolved from up here, before the descent starts, so the ride down ends on
	## the spot the player actually stands on rather than dropping and then snapping.
	if _loading_splash != null:
		_loading_splash.call("set_status", "Finding footing…")
	var footing := await _resolve_playable_footing(spawn, inst.generator, "hop into %s" % dest)
	if footing.is_empty():
		await _finish_district_hop_fail("no ground under hop spawn", origin_pos)
		return
	spawn = footing["spawn"] as Vector3
	var floor_y := float(footing["floor_y"])
	var feet := Vector3(spawn.x, floor_y + 0.15, spawn.z)
	_apply_spawn_yaw(walker, inst.generator)
	if _loading_splash != null:
		_loading_splash.call("hide_splash")
	_hop_cutscene.start_descent(feet)
	await _hop_cutscene.await_phase()
	_end_hop_cutscene()
	walker.global_position = feet
	walker.velocity = Vector3.ZERO
	_apply_spawn_yaw(walker, inst.generator)
	walker.set_physics_process(true)
	if _streamer != null and _streamer.has_method("clear_priority_district"):
		_streamer.call("clear_priority_district")
	_district_hopping = false
	_set_hud_enabled(true)
	print("CityRoot: district hop landed in %s at y=%.2f" % [dest, floor_y])


## Stand up the launch animation. One node, alive only for the hop, so a failed hop cannot
## leave birds or a hijacked camera behind.
func _begin_hop_cutscene(walker: CityWalker) -> void:
	_end_hop_cutscene()
	_hop_cutscene = DistrictHopCutsceneScript.new()
	_hop_cutscene.name = "DistrictHopCutscene"
	add_child(_hop_cutscene)
	_hop_cutscene.begin(walker)


func _end_hop_cutscene() -> void:
	if _hop_cutscene == null or not is_instance_valid(_hop_cutscene):
		_hop_cutscene = null
		return
	_hop_cutscene.finish()
	_hop_cutscene.queue_free()
	_hop_cutscene = null


func _finish_district_hop_fail(reason: String, restore_pos: Vector3) -> void:
	push_error("CityRoot: district hop failed — %s" % reason)
	_end_hop_cutscene()
	if _streamer != null and _streamer.has_method("clear_priority_district"):
		_streamer.call("clear_priority_district")
	if _walker != null and is_instance_valid(_walker):
		_walker.global_position = restore_pos
		_walker.velocity = Vector3.ZERO
		_walker.set_pitch(DistrictHopCutsceneScript.PITCH_LEVEL)
		_walker.set_physics_process(true)
	_district_hopping = false
	if not _booting:
		_set_hud_enabled(true)
	if _loading_splash != null:
		## A failed hop drops the player back where they were, so the message needs the full
		## splash behind it — a status line over the world is too easy to miss.
		_loading_splash.call("show_splash", "Hop failed — %s" % reason)
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
		## Stop probes before terrain leaves the tree — queue_free is deferred, and
		## `_process` would still call to_local on the detached VoxelTerrain.
		_walker.set_process(false)
		_walker.set_physics_process(false)
		if _walker.has_method("bind_terrain"):
			_walker.call("bind_terrain", null)
		_walker.queue_free()
		_walker = null
	_clear_summoned_tetris()
	_clear_tetris_peds()
	if _aim_panel != null and is_instance_valid(_aim_panel):
		_aim_panel.queue_free()
		_aim_panel = null
	if _streamer != null and is_instance_valid(_streamer):
		_streamer.call("clear_all")
		_streamer.queue_free()
		_streamer = null
	if _ability_tray != null and is_instance_valid(_ability_tray):
		_ability_tray.queue_free()
		_ability_tray = null
	_dismiss_player_minion()
	if _infection != null and is_instance_valid(_infection):
		_infection.call("clear_all")
		_infection.queue_free()
		_infection = null
	if _monsters != null and is_instance_valid(_monsters):
		_monsters.clear_all()
	if _undead != null and is_instance_valid(_undead):
		_undead.queue_free()
		_undead = null
	_player_score = 0
	_inventory.clear()
	## Every district row and every open match belongs to the world being torn down. District
	## rows refill once the walker stands (`_restore_pending_character`). Match paperwork is
	## poured back immediately below when a load is pending, so a Gaming plaza that streams
	## during spawn can already resume Go / chess instead of standing up empty.
	_economy.clear()
	_games.clear()
	if not _pending_restore.is_empty():
		GameSaveScript.apply_games(_games, _pending_restore)
	_gem_pickup_accum = 0.0
	_economy_accum = 0.0
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
	if _boost_hud != null and is_instance_valid(_boost_hud):
		_boost_hud.call("clear_display")
	if _zoo_cloak_hud != null and is_instance_valid(_zoo_cloak_hud):
		_zoo_cloak_hud.call("hide_countdown")
	if _siege_hud != null and is_instance_valid(_siege_hud):
		_siege_hud.call("clear_display")
		_siege_hud.call("bind_city", self)
	if _compass_hud != null and is_instance_valid(_compass_hud):
		_compass_hud.clear_display()
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
		float(_voxel_view_vox) * VOXEL_SIZE,
		_brush
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


func _on_spawn_district_ready(inst: DistrictInstance) -> void:
	if inst == null or inst.generator == null:
		_status.text = "ERROR: spawn district missing generator"
		_booting = false
		return
	_status.text = "Finding spawn…"
	var gen := inst.generator
	var spawn: Vector3 = gen.find_spawn_world(_tool)
	## Verify stamped ground exists under spawn (voxel data, not just mesh flag).
	if not _has_solid_ground_at(spawn):
		_status.text = "Waiting for stamped ground…"
		var ground_deadline := Time.get_ticks_msec() + FOOTING_PREFERRED_MS
		while not _has_solid_ground_at(spawn) and Time.get_ticks_msec() < ground_deadline:
			await get_tree().process_frame
		spawn = gen.find_spawn_world(_tool)
	var restoring := not _pending_restore.is_empty()
	if restoring:
		var resumed := _footing_for_saved_position(_pending_restore)
		if resumed == Vector3.INF:
			push_warning(
				"CityRoot: the saved position has no footing in the rebuilt world — "
				+ "using the district spawn"
			)
		else:
			spawn = resumed

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
	_walker.aim_panel_requested.connect(_on_aim_panel_requested)
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

	_status.text = "Finding footing…"
	var footing := await _resolve_playable_footing(spawn, gen, "boot spawn")
	if footing.is_empty():
		## Out of rungs. Never leave a walker standing in the world with physics off and no
		## way out — hand the screen back to the player.
		_status.text = "ERROR: no ground at spawn"
		_booting = false
		if is_instance_valid(spawn_viewer):
			spawn_viewer.queue_free()
		if is_instance_valid(_walker):
			_show_boot_fail_overlay(
				"The spawn district came up without ground to stand on."
			)
		return
	spawn = footing["spawn"] as Vector3
	var floor_y := float(footing["floor_y"])

	_walker.global_position = Vector3(spawn.x, floor_y + 0.15, spawn.z)
	_walker.velocity = Vector3.ZERO
	_apply_spawn_yaw(_walker, gen)
	_walker.set_physics_process(true)
	await get_tree().physics_frame
	if is_instance_valid(_walker) and not _walker.is_on_floor():
		_walker.global_position.y += 0.4
		_walker.velocity = Vector3.ZERO

	if is_instance_valid(spawn_viewer):
		spawn_viewer.queue_free()

	if restoring:
		## After the body is standing: growing back to a saved size tests the space around it, and
		## a walker still hanging above the ground would test the wrong space.
		_restore_pending_character()
	elif not is_finite(float(gen.last_spawn_yaw)):
		var look: Vector3 = inst.call("world_aabb_center") - _walker.global_position
		look.y = 0.0
		if look.length_squared() > 0.01:
			_walker.set_yaw(atan2(-look.x, -look.z))

	_booting = false
	## Roll the spawn tile's gem budget and pay for standing in it now, rather than up to half a
	## second later — the HUD is about to be shown and a run always starts on an explored tile.
	_economy_accum = 0.0
	_tick_district_economy()
	_set_hud_enabled(true)
	if _loading_splash != null:
		_loading_splash.call("hide_splash")
	elif _status != null:
		_status.visible = false
	_ability_tray = AbilityTrayScript.new() as AbilityTray
	_ability_tray.name = "AbilityTray"
	add_child(_ability_tray)
	_ability_tray.setup(_walker, _loadout)
	_ability_tray.ability_requested.connect(_on_ability_requested)
	_ability_tray.assign_changed.connect(_on_tray_assign_changed)
	## It joins the HUD band after the band was last refreshed, so it would otherwise stay up
	## over a panel opened while the spawn district was still baking.
	_refresh_hud_visibility()
	if _energy_hud != null and is_instance_valid(_energy_hud):
		_energy_hud.call("bind_walker", _walker)
	if _health_hud != null and is_instance_valid(_health_hud):
		_health_hud.call("bind_walker", _walker)
	if _boost_hud != null and is_instance_valid(_boost_hud):
		_boost_hud.call("bind_walker", _walker)
	if _compass_hud != null and is_instance_valid(_compass_hud):
		_compass_hud.bind_walker(_walker)
	if _settings_panel != null:
		_on_settings_applied(_settings_panel.get_settings())
		_apply_saved_controls()
	if _undead_invasion_enabled:
		_ensure_undead_director()
		_undead.call("set_enabled", true)
		if _undead_hud != null and is_instance_valid(_undead_hud):
			_undead_hud.call("bind_director", _undead)
	## Tiles that came up during boot could not stand their Tetris cabinets up, because a
	## cabinet is gated on the walker that only exists now.
	_stand_up_district_arcades()
	print(
		"CityRoot: playable — endless stream active at y=%.2f (F1–F6 = build · M = meteor · T = tetris)"
		% floor_y
	)
	_maybe_run_summon_probe()


func _stand_up_district_arcades() -> void:
	if _streamer == null or not is_instance_valid(_streamer):
		return
	var districts: Array = _streamer.call("get_loaded_districts") as Array
	for entry: Variant in districts:
		var di: DistrictInstance = entry
		if di != null and is_instance_valid(di):
			di.stand_up_gaming_arcade()


## `--summon-probe=big/BlueDemon` (optional `--summon-probe-quit`): summon once playable so
## hitch logs attribute the thin spawn path without needing the N-key panel.
func _maybe_run_summon_probe() -> void:
	var body_id := _cli_string_flag("--summon-probe=")
	if body_id.is_empty():
		return
	call_deferred("_run_summon_probe", body_id)


func _run_summon_probe(body_id: String) -> void:
	## Let a few streamed frames settle so nav / crowd are alive before the first goal.
	for _i in 45:
		await get_tree().process_frame
	var player := get_player_position()
	if player == Vector3.INF:
		push_error("CityRoot summon-probe: no player position")
		return
	var ahead := player + Vector3(8.0, 0.0, 0.0)
	_summon_aim = {"point": ahead, "normal": Vector3.UP, "did_hit": true}
	var before := int(Performance.get_custom_monitor(&"city/hitch_count"))
	var t0 := Time.get_ticks_usec()
	var unit := summon_monster_at_aim(body_id)
	var summon_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	if unit == null:
		push_error("CityRoot summon-probe: spawn failed for %s" % body_id)
		return
	print(
		"CityRoot SUMMON-PROBE: spawned %s in %.1f ms at %s"
		% [body_id, summon_ms, unit.global_position]
	)
	for _j in 90:
		await get_tree().process_frame
	var after := int(Performance.get_custom_monitor(&"city/hitch_count"))
	print(
		"CityRoot SUMMON-PROBE: RESULT hitches_after=%d summon_ms=%.1f"
		% [after - before, summon_ms]
	)
	if _cli_has_flag("--summon-probe-quit"):
		get_tree().quit()


func _cli_string_flag(flag: String) -> String:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for a: String in args:
		if a.begins_with(flag):
			return a.substr(flag.length())
	return ""


func _cli_has_flag(flag: String) -> bool:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	return args.has(flag)


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

	## Shared monster health-bar shader: first summon used to compile it on the live camera.
	var bar := MonsterHealthBarScript.new()
	bar.name = "WarmHealthBar"
	holder.add_child(bar)
	bar.fit_to_body(0.55, 0.8)
	bar.global_position = base + Vector3(0.0, 0.2, -4.0)

	## Pipelines compile on the render thread, so give it real frames to draw in.
	for _frame in WARMUP_FRAMES:
		await get_tree().process_frame
	holder.queue_free()
	print("CityRoot: warmed %d outfit scenes + %d cars" % [_warm_scenes.size(), cars])


func _apply_spawn_yaw(walker: Node3D, gen: Object) -> void:
	if walker == null or gen == null:
		return
	var yaw := float(gen.get("last_spawn_yaw"))
	if not is_finite(yaw):
		return
	if walker.has_method("set_yaw"):
		walker.call("set_yaw", yaw)
	else:
		walker.rotation.y = yaw


# ---------------------------------------------------------------------------
# Save / load
# ---------------------------------------------------------------------------

## Where a saved character can stand now. The world is rebuilt from the seed, so anything he had
## dug out is filled in again: the search walks up his old column until the body fits.
func _footing_for_saved_position(data: Dictionary) -> Vector3:
	var saved := GameSaveScript.saved_position(data)
	if saved == Vector3.INF:
		return Vector3.INF
	return GameSaveScript.first_free_footing(
		_tool,
		saved,
		VOXEL_SIZE,
		SAVE_FOOTING_HEIGHT_VOX,
		SAVE_FOOTING_UP_VOX,
		SAVE_FOOTING_DOWN_VOX
	)


## Pour the pending payload into the walker that just spawned, then forget it — a later regenerate
## must build a fresh character rather than resurrect this one.
func _restore_pending_character() -> void:
	if _pending_restore.is_empty():
		return
	if _walker == null or not is_instance_valid(_walker):
		push_error("CityRoot: the world came up without a walker to restore into")
		_pending_restore = {}
		return
	GameSaveScript.apply_character(_walker, _pending_restore)
	GameSaveScript.apply_inventory(_inventory, _pending_restore)
	GameSaveScript.apply_districts(_economy, _pending_restore)
	GameSaveScript.apply_loadout(_loadout, _pending_restore)
	## Idempotent with the early fill in `_regenerate`: keeps the registry correct if nothing
	## streamed yet, then asks any already-built tables to sit down at the saved matches.
	GameSaveScript.apply_games(_games, _pending_restore)
	_resume_loaded_game_tables()
	_player_score = GameSaveScript.saved_score(_pending_restore)
	if not _loadout.scores():
		_player_score = 0
	if _ability_tray != null:
		_ability_tray.bind_loadout(_loadout)
		_ability_tray.refresh()
	print(
		"CityRoot: restored save at %s (seed %d, mode %s)"
		% [_walker.global_position, city_seed, _loadout.mode]
	)
	_pending_restore = {}
	_autosave_accum = 0.0


## Spawn-tile Gaming plazas may have called setup while `_games` was still empty. After the
## save paperwork is in, tell those arenas to resume (no-op when they already did, or when
## no match is stored).
func _resume_loaded_game_tables() -> void:
	if _streamer == null or not is_instance_valid(_streamer):
		return
	if not _streamer.has_method("get_loaded_districts"):
		return
	for entry in _streamer.get_loaded_districts():
		var inst := _as_district_instance(entry)
		if inst == null:
			continue
		if inst.gaming_arena != null and is_instance_valid(inst.gaming_arena):
			if inst.gaming_arena.has_method("try_resume_from_world_games"):
				inst.gaming_arena.call("try_resume_from_world_games")
		if inst.chess_arena != null and is_instance_valid(inst.chess_arena):
			if inst.chess_arena.has_method("try_resume_from_world_games"):
				inst.chess_arena.call("try_resume_from_world_games")


## True while there is a live character worth writing to disk. A finished run is not one: a save
## holding a dead character would resume into a body with nothing left in the pool. Neither is a
## walker that has left the tree: it still answers every question about itself except where it is
## standing, which comes back as the world origin.
func can_save_game() -> bool:
	return (
		not _booting
		and not _game_over
		and _walker != null
		and is_instance_valid(_walker)
		and _walker.is_inside_tree()
	)


## Last-moment autosave for an exit we chose, taken while the character is still in the world.
func _autosave_on_exit() -> void:
	if _is_game_session() and can_save_game():
		write_quicksave("Autosave")


func has_quicksave() -> bool:
	return GameSaveScript.has_quicksave()


func list_named_saves() -> Array[Dictionary]:
	return GameSaveScript.list_named()


## Autosave slot. `label` is only what the file reports about itself; the path is fixed.
func write_quicksave(label: String = "Autosave") -> bool:
	if not can_save_game():
		return false
	var data := GameSaveScript.capture(
		city_seed, _walker, _inventory, label, _economy, _player_score, _loadout, _games
	)
	if data.is_empty():
		return false
	if not GameSaveScript.write_quicksave(data):
		return false
	_autosave_accum = 0.0
	return true


func write_named_save(raw_name: String) -> bool:
	if not can_save_game():
		return false
	var label := raw_name.strip_edges()
	var data := GameSaveScript.capture(
		city_seed, _walker, _inventory, label, _economy, _player_score, _loadout, _games
	)
	if data.is_empty():
		return false
	return GameSaveScript.write_named(raw_name, data)


func load_quicksave() -> bool:
	return _start_load(GameSaveScript.read_quicksave(), "autosave")


func load_named_save(raw_name: String) -> bool:
	return _start_load(GameSaveScript.read_named(raw_name), raw_name)


## Loading is a regenerate: the world follows from the saved seed, and the character is poured into
## the walker the rebuild spawns. Nothing tries to edit the live world into shape.
func _start_load(data: Dictionary, what: String) -> bool:
	if data.is_empty():
		## `GameSave` has already said in the log why — an older format is a warning, a broken file
		## is an error. Either way the menu reports it to the player, so this is not the place to
		## decide which of the two happened.
		push_warning("CityRoot: there is no readable save in '%s'" % what)
		return false
	if _booting:
		push_warning("CityRoot: still booting — ignoring the load of '%s'" % what)
		return false
	_pending_restore = data
	city_seed = GameSaveScript.saved_seed(data)
	print("CityRoot: loading '%s' (world seed %d)" % [what, city_seed])
	_regenerate()
	return true


## A new game keeps the named library and drops only the autosave: the next boot must not resume
## the run the player just walked away from. `mode` is sandbox or adventure.
func start_new_game(mode: String = PlayerLoadout.MODE_SANDBOX) -> void:
	if _booting:
		push_warning("CityRoot: still booting — ignoring New Game")
		return
	GameSaveScript.delete_quicksave()
	_pending_restore = {}
	if mode == PlayerLoadout.MODE_ADVENTURE:
		_loadout.reset_adventure()
		## Adventure always boots in Old Town so the first district matches the mode pitch.
		_pending_spawn_theme_id = DistrictTheme.OLD_TOWN
	else:
		_loadout.reset_sandbox()
		_pending_spawn_theme_id = -1
	_player_score = 0
	_inventory.clear()
	_economy.clear()
	_games.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	city_seed = maxi(rng.randi() & 0x7fffffff, 1)
	spawn_theme_id = -1
	print("CityRoot: new %s game in world seed %d" % [_loadout.mode, city_seed])
	_regenerate()


func _tick_autosave(delta: float) -> void:
	if not _is_game_session() or not can_save_game() or _district_hopping:
		return
	_autosave_accum += delta
	if _autosave_accum < AUTOSAVE_INTERVAL_SEC:
		return
	_autosave_accum = 0.0
	write_quicksave("Autosave")


## Closing the window is the most common way this game ends, so it saves there.
##
## NOTIFICATION_EXIT_TREE deliberately does not save. Teardown is depth-first, so by the time this
## node hears about it the walker has already left the tree, and a detached Node3D reports its
## global position as the world origin — that pass used to overwrite the good save written a moment
## earlier with a character standing at (0, 0, 0). Deliberate quits save on their way out instead
## (see the Esc handler), and the periodic autosave is the backstop for a hard kill.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave_on_exit()


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


## What the spawn column actually holds when no floor turns up. Voxel data and mesh state
## are separate stages: no data means the district never stamped here, data without a mesh
## means the streamer is still behind.
func _describe_missing_floor(spawn: Vector3) -> String:
	var vx := floori(spawn.x / VOXEL_SIZE)
	var vz := floori(spawn.z / VOXEL_SIZE)
	var vy := floori(spawn.y / VOXEL_SIZE)
	var column := PackedStringArray()
	for dy in range(-6, 5):
		var y := vy + dy
		var mat := int(_tool.get_voxel(Vector3i(vx, y, vz))) if _tool != null else -1
		column.append("%d:%d" % [y, mat])
	var meshed := "n/a"
	if _terrain != null and is_instance_valid(_terrain):
		meshed = str(_terrain.is_area_meshed(_spawn_neighborhood_aabb(spawn, 8.0)))
	return (
		"spawn %s (voxel %d,%d,%d) column[y:mat] %s · area meshed %s"
		% [spawn, vx, vy, vz, " ".join(column), meshed]
	)


## Surface Y of the highest solid voxel in the spawn column, or NAN when it is all air.
## Searches the same span the walker could plausibly be dropped through.
func _voxel_floor_y(spawn: Vector3) -> float:
	if _tool == null:
		return NAN
	var vx := floori(spawn.x / VOXEL_SIZE)
	var vz := floori(spawn.z / VOXEL_SIZE)
	var top := floori((spawn.y + FLOOR_PROBE_UP_M) / VOXEL_SIZE)
	var bottom := floori((spawn.y - FLOOR_PROBE_DOWN_M) / VOXEL_SIZE)
	for y in range(top, bottom - 1, -1):
		var mat := int(_tool.get_voxel(Vector3i(vx, y, vz)))
		if mat != VoxelMaterial.AIR and VoxelMaterial.is_solid(mat):
			return float(y + 1) * VOXEL_SIZE
	return NAN


## Waits for a district to stamp ground under `spawn`, then reports its surface Y, or NAN
## if none ever appears.
##
## Reads voxel data, not remeshed colliders. The walker moves with VoxelBoxMover against
## that same data and its collision_mask deliberately excludes terrain bodies, so a block
## the remesher left without a collider is still solid ground to it. Gating on colliders
## used to strand a boot for the full budget on ground the player could have stood on.
func _wait_voxel_floor_ms(spawn: Vector3, max_ms: int = 60_000, stage: String = "") -> float:
	var deadline := Time.get_ticks_msec() + max_ms
	var started := Time.get_ticks_msec()
	var last_status := 0
	while Time.get_ticks_msec() < deadline:
		if _walker == null or not is_instance_valid(_walker):
			return NAN
		var floor_y := _voxel_floor_y(spawn)
		if not is_nan(floor_y):
			return floor_y
		var elapsed := Time.get_ticks_msec() - started
		if elapsed - last_status >= 500:
			last_status = elapsed
			var text := "Finding footing… %s (%ds)" % [stage, elapsed / 1000] if stage != "" \
				else "Waiting for ground… (%ds)" % (elapsed / 1000)
			if _status != null:
				_status.text = text
			if _loading_splash != null and (_booting or _district_hopping):
				_loading_splash.call("set_status", text)
		await get_tree().process_frame
	return NAN


## First column around `centre` a body actually fits in, or Vector3.INF. Walks outwards in
## rings so a spawn that lost its own block still wakes the player within sight of it.
func _nearby_footing(centre: Vector3) -> Vector3:
	if _tool == null or not is_finite(centre.x) or not is_finite(centre.z):
		return Vector3.INF
	const DIRECTIONS: Array[Vector2] = [
		Vector2(1.0, 0.0), Vector2(-1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.0, -1.0),
		Vector2(0.7, 0.7), Vector2(-0.7, 0.7), Vector2(0.7, -0.7), Vector2(-0.7, -0.7),
	]
	for radius: float in FOOTING_RING_RADII_M:
		for dir: Vector2 in DIRECTIONS:
			var hint := centre + Vector3(dir.x * radius, 0.0, dir.y * radius)
			## `first_free_footing` checks the body fits, not just that something is solid —
			## a spawn wedged under a crypt lid is no better than no spawn at all.
			var footing := GameSaveScript.first_free_footing(
				_tool,
				hint,
				VOXEL_SIZE,
				SAVE_FOOTING_HEIGHT_VOX,
				SAVE_FOOTING_UP_VOX,
				SAVE_FOOTING_DOWN_VOX
			)
			if footing != Vector3.INF:
				return footing
	return Vector3.INF


## The one way any entry point asks the world where the player may stand.
##
## Returns `{ spawn: Vector3, floor_y: float, source: String }`, or an empty Dictionary only
## when there is nothing finite left to stand on at all — the caller must then hand the
## player an escape hatch rather than leave a walker with physics switched off.
##
## Every rung below the first is a defect in the world, not a normal outcome, so each one
## says so in the log. It still lands the player: a run that continues on the wrong paving
## slab beats a run that never starts.
func _resolve_playable_footing(
	preferred: Vector3, gen: DistrictGenerator, label: String, max_ms: int = FOOTING_PREFERRED_MS
) -> Dictionary:
	if is_finite(preferred.x) and is_finite(preferred.z):
		var direct := await _wait_voxel_floor_ms(preferred, max_ms, "preferred")
		if not is_nan(direct):
			return {"spawn": preferred, "floor_y": direct, "source": FOOTING_PREFERRED}
		if _walker == null or not is_instance_valid(_walker):
			return {}
		push_warning(
			"CityRoot: %s — no floor in the preferred column after %.1fs, widening the search. %s"
			% [label, max_ms / 1000.0, _describe_missing_floor(preferred)]
		)
		_set_footing_status("Finding footing… nearby")
		var near := _nearby_footing(preferred)
		if near != Vector3.INF:
			push_warning(
				"CityRoot: %s — standing %.1f m from the preferred column instead (%s)"
				% [label, preferred.distance_to(near), near]
			)
			return {"spawn": near, "floor_y": near.y, "source": FOOTING_NEARBY}

	var district_spawn := Vector3.INF
	if gen != null and gen.has_method("find_spawn_world"):
		district_spawn = gen.find_spawn_world(_tool)
	if is_finite(district_spawn.x) and not district_spawn.is_equal_approx(preferred):
		_set_footing_status("Finding footing… district spawn")
		var at_district := await _wait_voxel_floor_ms(
			district_spawn, FOOTING_FALLBACK_MS, "district spawn"
		)
		if _walker == null or not is_instance_valid(_walker):
			return {}
		if not is_nan(at_district):
			push_warning(
				"CityRoot: %s — fell back to the district spawn %s" % [label, district_spawn]
			)
			return {
				"spawn": district_spawn, "floor_y": at_district, "source": FOOTING_DISTRICT
			}
		var near_district := _nearby_footing(district_spawn)
		if near_district != Vector3.INF:
			push_warning(
				"CityRoot: %s — fell back to %s, near the district spawn"
				% [label, near_district]
			)
			return {
				"spawn": near_district, "floor_y": near_district.y, "source": FOOTING_NEARBY
			}

	## Nothing in this world is solid where it should be. Soft-land on the best finite guess
	## and let the walker's void floor and safety deck carry it — but say loudly that the
	## district failed to produce ground, because that is a world-generation bug.
	var landing := preferred if is_finite(preferred.x) else district_spawn
	if not is_finite(landing.x) or not is_finite(landing.y) or not is_finite(landing.z):
		push_error(
			"CityRoot: %s — no finite spawn anywhere in this district; cannot place the player"
			% label
		)
		return {}
	push_error(
		"CityRoot: %s — no solid ground at the spawn or anywhere around it; soft-landing. %s"
		% [label, _describe_missing_floor(landing)]
	)
	return {"spawn": landing, "floor_y": landing.y, "source": FOOTING_SOFT_LAND}


func _set_footing_status(text: String) -> void:
	if _status != null:
		_status.text = text
	if _loading_splash != null and (_booting or _district_hopping):
		_loading_splash.call("set_status", text)


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
	## Legacy dig signal — same per-cell player destroy as charged blast (no VFX flash).
	if _tool == null or _terrain == null or _brush == null:
		return
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var local := _terrain.to_local(hit_position)
	var hit_vox := Vector3i(int(floor(local.x)), int(floor(local.y)), int(floor(local.z)))
	var hit_mat := int(_tool.get_voxel(hit_vox))
	## Dissolve under the impact stays exclusive (cage / boss).
	if VoxelMaterial.is_dissolve(hit_mat):
		_try_start_dissolve(hit_position, hit_mat)
		return
	if VoxelMaterial.is_explosive(hit_mat):
		_try_detonate_explosive(hit_position, hit_mat)
		return
	var radius_vox := maxf(radius_m, 0.25) / VOXEL_SIZE
	_tip_kill_leads_in_sphere(local, radius_vox)
	var r_i := int(ceil(radius_vox)) + 1
	var r2 := radius_vox * radius_vox
	var cx := hit_vox.x
	var cy := hit_vox.y
	var cz := hit_vox.z
	var allow_chip := _roll_carve_chip()
	var ctx := _make_player_carve_ctx(allow_chip, 900)
	_player_note_cell(hit_vox, ctx)
	for z in range(cz - r_i, cz + r_i + 1):
		for y in range(cy - r_i, cy + r_i + 1):
			for x in range(cx - r_i, cx + r_i + 1):
				var center := Vector3(float(x) + 0.5, float(y) + 0.5, float(z) + 0.5)
				if center.distance_squared_to(local) > r2 + 0.0001:
					continue
				var vox := Vector3i(x, y, z)
				if vox == hit_vox:
					continue
				_player_note_cell(vox, ctx)
	_player_commit_carve(ctx, hit_position)
	_restore_bedrock_floor(local, radius_vox)
	_notify_destruction(hit_position, maxf(radius_m * 4.0, 28.0))


## Start one column-hop cascade at an exact seed voxel. Only shots call this.
## Up to FRACTAL_CASCADE_MAX concurrent from separate shots; at the cap the hit is absorbed.
func _try_start_fractal_cascade_at(seed_vox: Vector3i) -> bool:
	if _tool == null or _terrain == null or _brush == null:
		return false
	var mat_id := _brush.get_vox(seed_vox)
	if not VoxelMaterial.is_fractal_display(mat_id):
		return false
	_prune_fractal_cascades()
	if _fractal_cascades.size() >= FRACTAL_CASCADE_MAX:
		return true
	var cascade: RefCounted = FractalCascadeScript.new()
	var detached: Array = cascade.call("start", _brush, seed_vox) as Array
	var hit_world := _terrain.to_global(
		Vector3(float(seed_vox.x) + 0.5, float(seed_vox.y) + 0.5, float(seed_vox.z) + 0.5)
	)
	_emit_fractal_cascade_debris(detached, hit_world)
	if bool(cascade.call("is_active")):
		_fractal_cascades.append(cascade)
	return true


func _prune_fractal_cascades() -> void:
	var i := 0
	while i < _fractal_cascades.size():
		var cascade: RefCounted = _fractal_cascades[i] as RefCounted
		if cascade == null or not bool(cascade.call("is_active")):
			_fractal_cascades.remove_at(i)
			continue
		i += 1


func _tick_fractal_cascades() -> void:
	var i := 0
	while i < _fractal_cascades.size():
		var cascade: RefCounted = _fractal_cascades[i] as RefCounted
		if cascade == null:
			_fractal_cascades.remove_at(i)
			continue
		var detached: Array = cascade.call("tick") as Array
		if not detached.is_empty():
			_emit_fractal_cascade_debris(detached, _hit_world_from_detached(detached))
		if not bool(cascade.call("is_active")):
			_fractal_cascades.remove_at(i)
			continue
		i += 1


## World-space centre of the first detached entry — debris blast origin for one column peel.
func _hit_world_from_detached(detached: Array) -> Vector3:
	if _terrain == null or detached.is_empty():
		return Vector3.ZERO
	var entry: Variant = detached[0]
	if typeof(entry) != TYPE_DICTIONARY:
		return Vector3.ZERO
	var vox: Vector3i = (entry as Dictionary).get("vox", Vector3i.ZERO) as Vector3i
	return _terrain.to_global(
		Vector3(float(vox.x) + 0.5, float(vox.y) + 0.5, float(vox.z) + 0.5)
	)


func _emit_fractal_cascade_debris(detached: Array, hit_world: Vector3) -> void:
	if detached.is_empty():
		return
	if _cascade != null and _cascade.has_method("detach_blast_voxels"):
		CityProfiler.begin("cascade_detach")
		_cascade.call("detach_blast_voxels", detached, hit_world)
		CityProfiler.end("cascade_detach")
	_notify_tetris_damage(detached)
	_notify_destruction(hit_world, 28.0)


## Player damage touched dissolve fabric — start (or extend) a neighbour-infection cascade.
## Returns true when the hit was dissolve fabric (caller should skip the normal carve).
## No area damage: the point is that the cage opens without cratering the boss.
func _try_start_dissolve(hit_world: Vector3, mat_id: int) -> bool:
	if not VoxelMaterial.is_dissolve(mat_id):
		return false
	if _tool == null or _terrain == null or _brush == null:
		return false
	var local := _terrain.to_local(hit_world)
	var seed_vox := Vector3i(int(floor(local.x)), int(floor(local.y)), int(floor(local.z)))
	## A second hit on the same assembly just feeds the frontier; a different cluster waits.
	if not _dissolve_frontier.is_empty():
		if VoxelMaterial.dissolve_cluster(mat_id) != VoxelMaterial.dissolve_cluster(_dissolve_seed_id):
			return true
		_dissolve_enqueue(seed_vox, mat_id)
		return true
	_dissolve_seen.clear()
	_dissolve_seed_id = mat_id
	_dissolve_removed = 0
	_dissolve_frontier.clear()
	_dissolve_enqueue(seed_vox, mat_id)
	if _dissolve_frontier.is_empty():
		_dissolve_seed_id = -1
		return true
	if _audio != null and _audio.has_method("play_dissolve_hiss"):
		_audio.call("play_dissolve_hiss", hit_world)
	## First wave this frame so the struck cell is gone before the next shot lands.
	_tick_dissolve()
	return true


func _dissolve_enqueue(vox: Vector3i, seed_id: int) -> void:
	if _dissolve_seen.has(vox):
		return
	var mat := _brush.get_vox(vox) if _brush != null else VoxelMaterial.AIR
	if not VoxelMaterial.dissolves_with(seed_id, mat):
		return
	_dissolve_seen[vox] = true
	_dissolve_frontier.append(vox)


## One infection wave: every frontier cell vanishes and infects matching 6-neighbours.
func _tick_dissolve() -> void:
	if _dissolve_frontier.is_empty() or _brush == null or _terrain == null:
		return
	var seed_id := _dissolve_seed_id
	var wave: Array[Vector3i] = _dissolve_frontier
	_dissolve_frontier = []
	var next: Array[Vector3i] = []
	var world_hint := Vector3.ZERO
	var hinted := false
	_brush.begin_edit()
	for vox: Vector3i in wave:
		if _dissolve_removed >= DISSOLVE_MAX_CELLS:
			push_error(
				"CityRoot: dissolve cascade hit DISSOLVE_MAX_CELLS (%d) — stopping"
				% DISSOLVE_MAX_CELLS
			)
			assert(false, "CityRoot: dissolve cascade overflow")
			break
		var mat := _brush.get_vox(vox)
		if not VoxelMaterial.dissolves_with(seed_id, mat):
			continue
		_brush.destroy_vox(vox)
		_dissolve_removed += 1
		if not hinted:
			world_hint = _terrain.to_global(
				Vector3(float(vox.x) + 0.5, float(vox.y) + 0.5, float(vox.z) + 0.5)
			)
			hinted = true
		for d: Vector3i in _DISSOLVE_NEIGHBOURS:
			var n := vox + d
			if _dissolve_seen.has(n):
				continue
			var nmat := _brush.get_vox(n)
			if not VoxelMaterial.dissolves_with(seed_id, nmat):
				continue
			_dissolve_seen[n] = true
			next.append(n)
	_brush.end_edit()
	_dissolve_frontier = next
	if hinted:
		_notify_destruction(world_hint, 18.0)
		if _audio != null and _audio.has_method("move_dissolve_hiss"):
			_audio.call("move_dissolve_hiss", world_hint)
	if _dissolve_frontier.is_empty():
		_dissolve_seen.clear()
		_dissolve_seed_id = -1
		_dissolve_removed = 0


## Player damage touched explosive fabric — charged blast + boom + area damage once.
## Returns true when a detonation ran (caller should skip the normal carve).
func _try_detonate_explosive(hit_world: Vector3, mat_id: int) -> bool:
	if _explosive_detonating:
		return false
	if not VoxelMaterial.is_explosive(mat_id):
		return false
	var radius := VoxelMaterial.explosive_radius_m(mat_id)
	if radius <= 0.0:
		push_error("CityRoot: explosive mat %d has non-positive blast radius" % mat_id)
		assert(false, "CityRoot: explosive_radius_m")
		return false
	_explosive_detonating = true
	if _audio != null:
		if _audio.has_method("play_explosive_boom"):
			_audio.call("play_explosive_boom", hit_world)
		if _audio.has_method("play_charged_blast_impact"):
			## Large scale → deeper pitch; layered under the dedicated boom.
			_audio.call("play_charged_blast_impact", hit_world, 2.8)
	apply_area_damage(hit_world, radius, DamageSourceScript.Id.PLAYER_BLAST)
	apply_charged_blast(hit_world, radius)
	_explosive_detonating = false
	return true


## Charged LMB bomb (and stomp): per-cell player destroy, then normal debris/column for NORMAL cells.
func apply_charged_blast(hit_world: Vector3, radius_m: float) -> void:
	if _tool == null or _terrain == null or _brush == null:
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
	var center_vox := Vector3i(cx, cy, cz)
	var probe_mat := _brush.get_vox(center_vox)
	## Dissolve under the impact: exclusive cascade (no cratering the boss / cage floor).
	if VoxelMaterial.is_dissolve(probe_mat):
		CityProfiler.end("voxel_blast")
		_try_start_dissolve(hit_world, probe_mat)
		return
	## Explosive fabric under the impact: enlarge to material radius + acoustic boom.
	## Area damage is the caller's job (walker / stomp / `_try_detonate_explosive`).
	if not _explosive_detonating and VoxelMaterial.is_explosive(probe_mat):
		var er := VoxelMaterial.explosive_radius_m(probe_mat)
		if er > radius:
			radius = er
			radius_vox = minf(radius / VOXEL_SIZE, 14.0)
			r_i = int(ceil(radius_vox)) + 1
			r2 = radius_vox * radius_vox
		if _audio != null:
			if _audio.has_method("play_explosive_boom"):
				_audio.call("play_explosive_boom", hit_world)
			if _audio.has_method("play_charged_blast_impact"):
				_audio.call("play_charged_blast_impact", hit_world, 2.8)
	const MAX_DEBRIS := 900
	## One chip roll for the whole blast — same gate as blaster / laser / melee.
	var allow_chip := _roll_carve_chip()
	var center_verdict := _carve_verdict(probe_mat, center_vox)
	if (
		center_verdict == CarveVerdict.REFUSE
		or (center_verdict == CarveVerdict.CHIP and not allow_chip)
	):
		_flash_hardness_refuse(probe_mat)
	var ctx := _make_player_carve_ctx(allow_chip, MAX_DEBRIS)
	## Pass 1 — classify every cell. Centre is noted first so it wins the one fractal seed.
	_player_note_cell(center_vox, ctx)
	for z in range(cz - r_i, cz + r_i + 1):
		for y in range(cy - r_i, cy + r_i + 1):
			for x in range(cx - r_i, cx + r_i + 1):
				var center := Vector3(float(x) + 0.5, float(y) + 0.5, float(z) + 0.5)
				if center.distance_squared_to(local) > r2 + 0.0001:
					continue
				var vox := Vector3i(x, y, z)
				if vox == center_vox:
					continue
				_player_note_cell(vox, ctx)
	## Pass 2 — one fractal cascade (if any) then normal carves. Seed runs outside the edit.
	_player_commit_carve(ctx, hit_world)
	_restore_bedrock_floor(local, radius_vox)
	CityProfiler.end("voxel_blast")
	BlastFlashVfxScript.spawn(self, hit_world, radius)
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
	if _ward.holds_above(top_vox.x, top_vox.z, top_vox.y):
		## A structure stands over the break. Collapsing the column would drop the exact cells the
		## carve was just refused on — a tower cut off at the ankles instead of shot down.
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
	if _monsters == null or not is_instance_valid(_monsters):
		return 0
	return _monsters.damage_units_in_sphere(center, radius, source)


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
	apply_voxel_strike(origin, dir, max_range, float(_walker.get_character_scale()))


## Shared hardness gate for every player carve (blaster / laser / melee / charged blast / dig).
## One path — duplicated checks used to flash "Too hard" for Exotic while silently swallowing
## Reinforced chip misses, and the punch sphere re-rolled the chip chance after the ray won.
enum CarveVerdict {
	OK,
	## One tier above the tool: slow chip when `allow_chip` is true for this strike.
	CHIP,
	## Two+ tiers above — unlock hardness; always toast.
	REFUSE,
	## Bedrock / arena shell / infection body, or a cell a standing structure holds (`VoxelWard`) —
	## never yields, no toast.
	IMMUNE,
}

## Per-cell fate for player weapons. All four tray weapons route sphere cells through
## `_player_note_cell` + `_player_commit_carve` so fractal / dissolve never use the normal path.
enum PlayerVoxelKind {
	NONE,
	GEM,
	DISSOLVE,
	FRACTAL,
	EXPLOSIVE,
	NORMAL,
}

## Chance a CHIP-tier cell yields when the strike has already committed to chipping.
const CARVE_CHIP_CHANCE := 0.28


## Material policy for one player-destroyed cell (before hardness).
func _player_voxel_kind(mat_id: int) -> PlayerVoxelKind:
	if mat_id == VoxelMaterial.AIR or mat_id == VoxelMaterial.WATER:
		return PlayerVoxelKind.NONE
	if VoxelMaterial.is_gem(mat_id):
		return PlayerVoxelKind.GEM
	if VoxelMaterial.is_dissolve(mat_id):
		return PlayerVoxelKind.DISSOLVE
	if VoxelMaterial.is_fractal_display(mat_id):
		return PlayerVoxelKind.FRACTAL
	if VoxelMaterial.is_explosive(mat_id):
		return PlayerVoxelKind.EXPLOSIVE
	if VoxelMaterial.is_destructible(mat_id):
		return PlayerVoxelKind.NORMAL
	return PlayerVoxelKind.NONE


## Sentinel: no fractal seed chosen yet for this hit.
const _PLAYER_NO_SEED := Vector3i(2147483647, 2147483647, 2147483647)


func _make_player_carve_ctx(allow_chip: bool, max_debris: int) -> Dictionary:
	return {
		"allow_chip": allow_chip,
		"detached": [],
		"column_max_y": {},  # Vector2i → int
		"max_debris": max_debris,
		"normal_cells": [],  # Array[Vector3i] — carved in commit
		## One shot → one fractal seed (first noted cell; callers note the impact first).
		"fractal_seed": _PLAYER_NO_SEED,
		"handled": false,
	}


## Pass 1: classify one cell. Does not carve normals or start the fractal cascade yet.
func _player_note_cell(vox: Vector3i, ctx: Dictionary) -> void:
	if _brush == null or _terrain == null:
		return
	var mat_id := _brush.get_vox(vox)
	var kind := _player_voxel_kind(mat_id)
	if kind == PlayerVoxelKind.NONE:
		return
	var allow_chip: bool = bool(ctx["allow_chip"])
	match kind:
		PlayerVoxelKind.GEM:
			try_collect_gem_at(vox)
			ctx["handled"] = true
		PlayerVoxelKind.DISSOLVE:
			var hit_world := _terrain.to_global(
				Vector3(float(vox.x) + 0.5, float(vox.y) + 0.5, float(vox.z) + 0.5)
			)
			_try_start_dissolve(hit_world, mat_id)
			ctx["handled"] = true
		PlayerVoxelKind.FRACTAL:
			if not _carve_allowed(mat_id, vox, allow_chip):
				return
			var seed: Vector3i = ctx["fractal_seed"] as Vector3i
			if seed == _PLAYER_NO_SEED:
				ctx["fractal_seed"] = vox
			ctx["handled"] = true
		PlayerVoxelKind.EXPLOSIVE, PlayerVoxelKind.NORMAL:
			if not _carve_allowed(mat_id, vox, allow_chip):
				return
			(ctx["normal_cells"] as Array).append(vox)
			ctx["handled"] = true


## Pass 2: start at most one fractal cascade, then carve queued normal cells + debris.
func _player_commit_carve(ctx: Dictionary, hit_world: Vector3) -> void:
	var seed: Vector3i = ctx["fractal_seed"] as Vector3i
	if seed != _PLAYER_NO_SEED:
		_try_start_fractal_cascade_at(seed)
	var normals: Array = ctx["normal_cells"] as Array
	if not normals.is_empty() and _brush != null:
		var detached: Array = ctx["detached"] as Array
		var column_max_y: Dictionary = ctx["column_max_y"] as Dictionary
		var max_debris: int = int(ctx["max_debris"])
		_brush.begin_edit()
		for item in normals:
			var vox: Vector3i = item as Vector3i
			var carved := _brush.destroy_vox(vox)
			for entry in carved:
				var ev: Vector3i = entry["vox"] as Vector3i
				if detached.size() < max_debris:
					detached.append(entry)
				var col := Vector2i(ev.x, ev.z)
				if column_max_y.has(col):
					column_max_y[col] = maxi(int(column_max_y[col]), ev.y)
				else:
					column_max_y[col] = ev.y
		_brush.end_edit()
	_player_emit_normal_cascade(ctx, hit_world)


## Spawn tumble debris + column collapse for cells that took the NORMAL path this hit.
func _player_emit_normal_cascade(ctx: Dictionary, hit_world: Vector3) -> void:
	var detached: Array = ctx["detached"] as Array
	var column_max_y: Dictionary = ctx["column_max_y"] as Dictionary
	if _cascade != null and is_instance_valid(_cascade):
		if not detached.is_empty() and _cascade.has_method("detach_blast_voxels"):
			CityProfiler.begin("cascade_detach")
			_cascade.call("detach_blast_voxels", detached, hit_world)
			CityProfiler.end("cascade_detach")
		elif not detached.is_empty() and _cascade.has_method("detach_voxels"):
			CityProfiler.begin("cascade_detach")
			_cascade.detach_voxels(detached)
			CityProfiler.end("cascade_detach")
		for col_key in column_max_y.keys():
			var xz: Vector2i = col_key
			var max_y: int = int(column_max_y[col_key])
			_cascade_column_above(Vector3i(xz.x, max_y, xz.y))
	if not detached.is_empty():
		_notify_tetris_damage(detached)


## Classify the cell at `vox` (material `mat_id`) against the player's hardness tier. No RNG —
## callers roll chip once.
##
## `vox` decides as much as the material does: a structure standing there may hold its own cells
## against damage regardless of what it is built out of (see `VoxelWard`).
func _carve_verdict(mat_id: int, vox: Vector3i) -> CarveVerdict:
	if (
		mat_id == VoxelMaterial.AIR
		or mat_id == VoxelMaterial.WATER
		or not VoxelMaterial.is_destructible(mat_id)
	):
		return CarveVerdict.IMMUNE
	if _ward.holds(vox):
		return CarveVerdict.IMMUNE
	var need := int(VoxelMaterial.hardness(mat_id))
	if need == int(VoxelMaterial.Hardness.NEVER):
		return CarveVerdict.IMMUNE
	var have := _hardness_tier()
	if need <= have:
		return CarveVerdict.OK
	if need == have + 1:
		return CarveVerdict.CHIP
	return CarveVerdict.REFUSE


## True when this strike may destroy the cell at `vox`. `allow_chip` is the single per-strike roll.
func _carve_allowed(mat_id: int, vox: Vector3i, allow_chip: bool = false) -> bool:
	match _carve_verdict(mat_id, vox):
		CarveVerdict.OK:
			return true
		CarveVerdict.CHIP:
			return allow_chip
		_:
			return false


func _hardness_tier() -> int:
	return _loadout.hardness_tier if _loadout != null else PlayerLoadout.HARDNESS_ROCK


## Toast when the tool cannot break this cell (chip miss or two+ tiers short).
func _flash_hardness_refuse(mat_id: int) -> void:
	var need := int(VoxelMaterial.hardness(mat_id))
	print(
		"CityRoot: too hard (need tier %d, have %d) — unlock hardness"
		% [need, _hardness_tier()]
	)
	if _loot_toast != null:
		_loot_toast.show_message("Too hard")


## One roll for the whole strike/blast — never re-roll per voxel.
func _roll_carve_chip() -> bool:
	return randf() < CARVE_CHIP_CHANCE


func apply_voxel_strike(
	origin: Vector3, direction: Vector3, max_range_m: float, character_scale: float
) -> bool:
	if _tool == null or _terrain == null or _brush == null:
		return false
	var dir := direction
	if dir.length_squared() < 0.0001:
		return false
	dir = dir.normalized()
	var scale := character_scale
	if scale < 0.5:
		return false
	var max_range := maxf(max_range_m, 0.05)
	var local_origin := _terrain.to_local(origin)
	var max_range_vox := max_range / VOXEL_SIZE
	var step := 0.2  ## fraction of a voxel — precision over speed
	var steps := int(ceil(max_range_vox / step)) + 1
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var hit_vox := Vector3i(2147483647, 2147483647, 2147483647)
	var found := false
	var hit_gem := false
	## Rolled at most once when the ray first meets a CHIP-tier cell.
	var allow_chip := false
	var chip_rolled := false
	for i in range(1, steps + 1):
		var p := local_origin + dir * (float(i) * step)
		var v := Vector3i(int(floor(p.x)), int(floor(p.y)), int(floor(p.z)))
		if found and v == hit_vox:
			continue
		var id := int(_tool.get_voxel(v))
		if id == VoxelMaterial.AIR or id == VoxelMaterial.WATER:
			continue
		if VoxelMaterial.is_gem(id):
			hit_vox = v
			found = true
			hit_gem = true
			break
		var verdict := _carve_verdict(id, v)
		match verdict:
			CarveVerdict.IMMUNE:
				## Solid that never yields — stop the ray.
				break
			CarveVerdict.REFUSE:
				_flash_hardness_refuse(id)
				break
			CarveVerdict.CHIP:
				if not chip_rolled:
					allow_chip = _roll_carve_chip()
					chip_rolled = true
				if not allow_chip:
					## Same toast as a full refuse — silent swallows looked like a dead blaster.
					_flash_hardness_refuse(id)
					break
				hit_vox = v
				found = true
				break
			CarveVerdict.OK:
				hit_vox = v
				found = true
				break
	if not found:
		return false

	## Diameter = 1 voxel per human scale → radius = scale/2.
	var radius_vox := scale * 0.5
	var hit_center := Vector3(float(hit_vox.x) + 0.5, float(hit_vox.y) + 0.5, float(hit_vox.z) + 0.5)
	var hit_world := _terrain.to_global(hit_center)
	var hit_mat := int(_tool.get_voxel(hit_vox))
	## Punching a gem (or a gem in the fist sphere) collects it — gems never carve.
	if hit_gem:
		try_collect_gem_at(hit_vox)
	## Dissolve on the primary cell: exclusive (cage opens without a punch crater).
	elif VoxelMaterial.is_dissolve(hit_mat):
		return _try_start_dissolve(hit_world, hit_mat)
	elif VoxelMaterial.is_explosive(hit_mat):
		return _try_detonate_explosive(hit_world, hit_mat)
	## Revert tips in the punch sphere first; then every cell uses the shared player carve path.
	_tip_kill_leads_in_sphere(hit_center, radius_vox)
	var r_i := int(ceil(radius_vox))
	var r2 := radius_vox * radius_vox
	## Reuse the ray's chip roll — never roll again per neighbour.
	var ctx := _make_player_carve_ctx(allow_chip, 900)
	## Pass 1 — hit cell first so it wins the one fractal seed when it is fractal.
	_player_note_cell(hit_vox, ctx)
	for z in range(hit_vox.z - r_i, hit_vox.z + r_i + 1):
		for y in range(hit_vox.y - r_i, hit_vox.y + r_i + 1):
			for x in range(hit_vox.x - r_i, hit_vox.x + r_i + 1):
				var center := Vector3(float(x) + 0.5, float(y) + 0.5, float(z) + 0.5)
				if center.distance_squared_to(hit_center) > r2 + 0.0001:
					continue
				var vox := Vector3i(x, y, z)
				if vox == hit_vox:
					continue
				_player_note_cell(vox, ctx)
	_player_commit_carve(ctx, hit_world)

	var detached: Array = ctx["detached"] as Array
	if hit_gem and detached.is_empty() and not bool(ctx["handled"]):
		return true
	if bool(ctx["handled"]) or not detached.is_empty() or hit_gem:
		_notify_destruction(hit_world, 30.0 + 8.0 * scale)
		return true
	return false


func _on_meteor_requested(hit_point: Vector3, _hit_normal: Vector3) -> void:
	_spawn_meteor_at(hit_point)


func _on_build_chosen(recipe_id: String) -> void:
	if _tool == null or _terrain == null or _walker == null:
		push_error("CityRoot: cannot build without terrain / walker")
		return
	var recipe: BuildCatalog.Recipe = BuildCatalogScript.by_id(recipe_id)
	if recipe == null:
		return
	if not recipe.consume_item.is_empty():
		if _inventory == null:
			push_error("CityRoot: build '%s' needs inventory to spend %s" % [recipe_id, recipe.consume_item])
			return
		if _inventory.count_of(recipe.consume_item) < recipe.consume_count:
			print(
				"CityRoot: need %d %s to place %s"
				% [recipe.consume_count, InventoryCatalog.display_name(recipe.consume_item), recipe.display_name]
			)
			return
	var aim: Dictionary = _walker.call("aim_ground_at_cursor") as Dictionary
	var hit: Vector3
	if bool(aim.get("did_hit", false)):
		hit = aim["point"] as Vector3
	else:
		## No ground under the cursor — drop it a few metres in front of the player.
		hit = _walker.global_position - _walker.global_transform.basis.z * 4.0
	var written: int = BuildPlacerScript.place(
		_terrain, _tool, _brush, recipe, hit, _walker.global_position
	)
	if written <= 0:
		print("CityRoot: build %s wrote no voxels at %s" % [recipe.display_name, hit])
		return
	if not recipe.consume_item.is_empty():
		if not _inventory.remove(recipe.consume_item, recipe.consume_count):
			push_error(
				"CityRoot: spent check passed but remove failed for %s x%d"
				% [recipe.consume_item, recipe.consume_count]
			)
			return
		if _inventory_panel != null and _inventory_panel.has_method("_refresh"):
			_inventory_panel.call("_refresh")
	print("CityRoot: built %s (%d voxels) at %s" % [recipe.display_name, written, hit])


func _on_tetris_requested(hit_point: Vector3, _hit_normal: Vector3) -> void:
	_spawn_tetris_at(hit_point)


func _on_aim_panel_requested(hit_point: Vector3, _hit_normal: Vector3) -> void:
	_spawn_aim_panel_at(hit_point)


func _on_pedestrian_requested(hit_point: Vector3, _hit_normal: Vector3) -> void:
	_spawn_tetris_ped_at(hit_point)


func _spawn_aim_panel_at(hit_point: Vector3) -> void:
	if _aim_panel != null and is_instance_valid(_aim_panel):
		_aim_panel.queue_free()
		_aim_panel = null
	var face_yaw := 0.0
	var to_player := get_player_position() - hit_point
	to_player.y = 0.0
	if to_player.length_squared() > 0.01:
		face_yaw = atan2(-to_player.x, -to_player.z)
	elif _walker != null and is_instance_valid(_walker):
		face_yaw = _walker.rotation.y + PI
	## Cardinal facing only — keeps the click surface axis-aligned like Tetris.
	face_yaw = roundf(face_yaw / (PI * 0.5)) * (PI * 0.5)
	var panel: Node3D = AimPanelScript.new() as Node3D
	panel.name = "AimPanel"
	_aim_panel = panel
	add_child(panel)
	panel.tree_exited.connect(func() -> void:
		if _aim_panel == panel:
			_aim_panel = null
	)
	panel.call("begin", hit_point, face_yaw)


func _spawn_tetris_at(hit_point: Vector3) -> void:
	if _walker == null or not is_instance_valid(_walker):
		push_error("CityRoot: cannot spawn Tetris without the walker that gates its keys")
		return
	var walker := _walker as CityWalker
	_clear_summoned_tetris()
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
	_summoned_tetris = spawn_tetris_cabinet(self, hit_point, face_yaw, "TetrisMachine")


## Stand a cabinet up under `parent` and register it. Districts call this for their arcade
## row and keep ownership, so the cabinets die with the tile that streamed them in.
func spawn_tetris_cabinet(
	parent: Node, ground_hit: Vector3, face_yaw: float, node_name: String
) -> Node3D:
	if parent == null or not parent.is_inside_tree():
		push_error("CityRoot.spawn_tetris_cabinet: parent must already be in the tree")
		return null
	if _tool == null or _terrain == null or _brush == null:
		push_error("CityRoot.spawn_tetris_cabinet: no VoxelTerrain tool to stamp the shell")
		return null
	if _walker == null or not is_instance_valid(_walker):
		push_error("CityRoot.spawn_tetris_cabinet: no walker to gate the cabinet keys")
		return null
	var machine: Node3D = TetrisMachineScript.new() as Node3D
	machine.name = node_name
	parent.add_child(machine)
	_tetris_machines.append(machine)
	machine.tree_exited.connect(func() -> void:
		_tetris_machines.erase(machine)
		if _summoned_tetris == machine:
			_summoned_tetris = null
	)
	machine.call(
		"begin", _terrain, _tool, _brush, _walker as CityWalker, ground_hit, face_yaw, VOXEL_SIZE
	)
	return machine


func _clear_summoned_tetris() -> void:
	if _summoned_tetris == null or not is_instance_valid(_summoned_tetris):
		_summoned_tetris = null
		return
	if _summoned_tetris.has_method("clear_shell"):
		_summoned_tetris.call("clear_shell")
	_summoned_tetris.queue_free()
	_tetris_machines.erase(_summoned_tetris)
	_summoned_tetris = null


## Closest cabinet to `at` whose stand is within `max_m`, or null. Distance is measured to
## the stand rather than the cabinet centre, because that is where a player or NPC has to
## be for the screen to be readable.
func nearest_tetris_machine(at: Vector3, max_m: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_m * max_m
	for machine in _tetris_machines:
		if machine == null or not is_instance_valid(machine):
			continue
		var stand: Vector3 = machine.call("get_stand_world_position")
		var d := at.distance_squared_to(stand)
		if d < best_d:
			best_d = d
			best = machine
	return best


## Keys 1–4 are one global set, so exactly one cabinet may be listening. The nearest one in
## reach wins; every other board goes deaf. AI-owned boards are left alone because their
## controller already holds their input, and off boards are never listeners — power is the
## stronger rule than proximity.
func _gate_tetris_input() -> void:
	if _tetris_machines.is_empty():
		return
	var listener: Node3D = null
	if _walker != null and is_instance_valid(_walker) and not _game_over:
		listener = nearest_tetris_machine(_walker.global_position, TETRIS_REACH_M)
		if listener != null:
			if bool(listener.call("has_ai_controller")):
				listener = null
			elif listener.has_method("is_powered") and not bool(listener.call("is_powered")):
				listener = null
	for machine in _tetris_machines:
		if machine == null or not is_instance_valid(machine):
			continue
		if bool(machine.call("has_ai_controller")):
			continue
		machine.call("set_input_enabled", machine == listener)


func _spawn_tetris_ped_at(hit_point: Vector3) -> void:
	var slot := _tetris_peds.size()
	var ped: Node3D = TetrisPedNpcScript.new() as Node3D
	ped.name = "TetrisPedNpc_%d" % slot
	add_child(ped)
	_tetris_peds.append(ped)
	ped.tree_exited.connect(func() -> void:
		_tetris_peds.erase(ped)
	)
	## A ped walks to whichever cabinet it was dropped beside; the ped itself re-checks the
	## distance and just stands around if there is nothing playable nearby.
	ped.call("begin", hit_point, nearest_tetris_machine(hit_point, TETRIS_PED_REACH_M), slot)


func _clear_tetris_peds() -> void:
	for ped in _tetris_peds:
		if ped != null and is_instance_valid(ped):
			ped.queue_free()
	_tetris_peds.clear()


func _notify_tetris_damage(detached: Array = []) -> void:
	for machine in _tetris_machines:
		if machine == null or not is_instance_valid(machine):
			continue
		if detached.is_empty():
			if machine.has_method("check_integrity"):
				machine.call("check_integrity")
		elif machine.has_method("notify_voxels_carved"):
			machine.call("notify_voxels_carved", detached)


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


## Nearest crowd pedestrian only (no player). Vector3.INF when none in range.
func find_nearest_ped_only(from: Vector3, max_dist: float) -> Vector3:
	var best := Vector3.INF
	var best_d2 := max_dist * max_dist
	if _streamer == null:
		return best
	var districts := _streamer.get_loaded_districts()
	for entry in districts:
		var inst := _as_district_instance(entry)
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


## All crowd pedestrians within max_dist (XZ). Empty when none / no streamer.
func collect_ped_positions(from: Vector3, max_dist: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _streamer == null:
		return out
	var districts := _streamer.get_loaded_districts()
	for entry in districts:
		var inst := _as_district_instance(entry)
		if inst == null or not is_instance_valid(inst) or inst.crowd == null:
			continue
		if not inst.crowd.has_method("collect_positions_in_range"):
			continue
		var chunk: PackedVector3Array = inst.crowd.call(
			"collect_positions_in_range", from, max_dist
		) as PackedVector3Array
		out.append_array(chunk)
	return out


## Every actor that is not a bird, within max_dist (XZ) of `from`: the player, pedestrians,
## traffic and living monsters. Bird flocks ask this to decide when to take off, which is the
## only thing in the world that cares about "an actor, any actor" rather than a specific kind.
func collect_actor_positions(from: Vector3, max_dist: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var max_d2 := max_dist * max_dist
	if is_player_alive():
		out.append(_walker.global_position)
	out.append_array(collect_ped_positions(from, max_dist))
	if _monsters != null and is_instance_valid(_monsters):
		for entry in _monsters.get_alive_units():
			var unit := entry as UndeadUnit
			if unit == null or not is_instance_valid(unit) or not unit.is_alive():
				continue
			if Vector2(
				unit.global_position.x - from.x, unit.global_position.z - from.z
			).length_squared() <= max_d2:
				out.append(unit.global_position)
	if _streamer == null:
		return out
	for entry in _streamer.get_loaded_districts():
		var inst := _as_district_instance(entry)
		if inst == null or not is_instance_valid(inst) or inst.vehicles == null:
			continue
		if not is_instance_valid(inst.vehicles):
			continue
		for i in range(inst.vehicles.vehicle_live_count()):
			var car := inst.vehicles.agent_at(i)
			if car == null or not is_instance_valid(car):
				continue
			if Vector2(
				car.global_position.x - from.x, car.global_position.z - from.z
			).length_squared() <= max_d2:
				out.append(car.global_position)
	return out


## Living hostile monsters within max_dist (XZ) for `hunter`. Bodies rather than points,
## because a hunter commits to one target and has to recognise it again next tick.
## Bodies `hunter` may hurt (damage / splash). Fresh prey search uses
## `collect_acquirable_monsters` — siege defenders are hostile for damage but not for acquire.
func collect_hostile_monsters(
	from: Vector3, max_dist: float, hunter: UndeadUnit = null
) -> Array[UndeadUnit]:
	return _collect_monsters(from, max_dist, hunter, false)


## Bodies `hunter` may pick as a fresh hunt target. Siege defenders are excluded here so the
## horde walks past silent towers; forced retaliation still finds them via promote_attacker.
func collect_acquirable_monsters(
	from: Vector3, max_dist: float, hunter: UndeadUnit = null
) -> Array[UndeadUnit]:
	return _collect_monsters(from, max_dist, hunter, true)


func _collect_monsters(
	from: Vector3, max_dist: float, hunter: UndeadUnit, acquirable_only: bool
) -> Array[UndeadUnit]:
	var out: Array[UndeadUnit] = []
	if _monsters == null or not is_instance_valid(_monsters):
		return out
	var max_d2 := max_dist * max_dist
	var units: Array = _monsters.get_alive_units() as Array
	for entry in units:
		var unit := entry as UndeadUnit
		if unit == null or not is_instance_valid(unit) or not unit.is_alive():
			continue
		if hunter != null:
			if unit == hunter:
				continue
			if acquirable_only:
				if not hunter.can_acquire_prey(unit):
					continue
			elif not hunter.is_hostile_to(unit):
				continue
		var d2 := Vector2(
			unit.global_position.x - from.x, unit.global_position.z - from.z
		).length_squared()
		if d2 > max_d2:
			continue
		out.append(unit)
	return out


## Nearest living undead/monster other than `except_unit`. When `except_unit` is set, only
## other-faction bodies count as prey (same-faction packs do not hunt each other).
## Vector3.INF when none in range.
func find_nearest_monster_position(
	from: Vector3, max_dist: float, except_unit: UndeadUnit = null
) -> Vector3:
	var unit := find_nearest_hostile_monster(from, max_dist, except_unit)
	if unit == null:
		return Vector3.INF
	return unit.global_position


## Nearest living hostile monster for `hunter` (or any other unit when `hunter` is null).
## Null when none in range. Uses damage-hostility, not acquire — combat splash must still
## find a siege defender the attacker was forced onto.
func find_nearest_hostile_monster(
	from: Vector3, max_dist: float, hunter: UndeadUnit = null
) -> UndeadUnit:
	if _monsters == null or not is_instance_valid(_monsters):
		return null
	var best: UndeadUnit = null
	var best_d2 := max_dist * max_dist
	var units: Array = _monsters.get_alive_units() as Array
	for entry in units:
		var unit := entry as UndeadUnit
		if unit == null or not is_instance_valid(unit) or not unit.is_alive():
			continue
		if hunter != null:
			if unit == hunter:
				continue
			if not hunter.is_hostile_to(unit):
				continue
		var d2 := Vector2(
			unit.global_position.x - from.x, unit.global_position.z - from.z
		).length_squared()
		if d2 > best_d2:
			continue
		best_d2 = d2
		best = unit
	return best


## Panic pedestrians near undead mages (trigger / clear distances in meters).
func scare_crowd_from_mages(threats: Array, trigger_m: float, clear_m: float) -> void:
	if threats.is_empty():
		return
	if _streamer == null:
		return
	var districts := _streamer.get_loaded_districts()
	for entry in districts:
		var inst := _as_district_instance(entry)
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
	## Capture sphere must not reach through solid walls / arena shell / LOS veil.
	if not has_voxel_line_of_sight(world_pos, ppos):
		return false
	damage_player(DamageSourceScript.Id.UNDEAD_ORB)
	return true


func try_convert_ped_near(world_pos: Vector3, radius: float) -> Variant:
	if _streamer == null:
		return null
	var best_crowd: CrowdDirector = null
	var best_agent: PedAgent = null
	var best_d2 := radius * radius
	var districts := _streamer.get_loaded_districts()
	for entry in districts:
		var inst := _as_district_instance(entry)
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
	var ped_pos: Vector3 = best_agent.global_position
	if not has_voxel_line_of_sight(world_pos, ped_pos):
		return null
	var former: Vector3 = best_crowd.convert_agent_silent(best_agent)
	if former == Vector3.INF:
		return null
	return former


## One-shot remove a pedestrian near `world_pos` (melee / living prey). Returns former position.
func try_kill_ped_near(world_pos: Vector3, radius: float) -> Variant:
	if _streamer == null:
		return null
	var best_crowd: CrowdDirector = null
	var best_agent: PedAgent = null
	var best_pos := Vector3.INF
	var best_d2 := radius * radius
	var districts := _streamer.get_loaded_districts()
	for entry in districts:
		var inst := _as_district_instance(entry)
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
	_notify_destruction(world_pos, 28.0 + radius_vox)


## Crumble-stride aura: peel destructible voxels ahead of a walking monster and cascade.
## Skips cave-cage materials (player must blast those). Soft self-supporting terrain still
## craters without column collapse via the usual cascade gate.
func undead_crumble_stride_at(
	contact_world: Vector3, along: Vector3, along_half: int = 1, depth_vox: int = 2
) -> int:
	if _terrain == null or _tool == null or _brush == null:
		return 0
	var forward := along
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return 0
	forward = forward.normalized()
	var side := Vector3(-forward.z, 0.0, forward.x)
	var local := _terrain.to_local(contact_world)
	var origin := Vector3i(int(floor(local.x)), int(floor(local.y)), int(floor(local.z)))
	var ix := Vector3i(int(round(forward.x)), 0, int(round(forward.z)))
	if ix == Vector3i.ZERO:
		if absf(forward.x) >= absf(forward.z):
			ix = Vector3i(1 if forward.x >= 0.0 else -1, 0, 0)
		else:
			ix = Vector3i(0, 0, 1 if forward.z >= 0.0 else -1)
	var sx := Vector3i(int(round(side.x)), 0, int(round(side.z)))
	if sx == Vector3i.ZERO:
		sx = Vector3i(-ix.z, 0, ix.x)
	var detached: Array = []
	var column_max_y: Dictionary = {}
	const MAX_DEBRIS := 80
	var removed := 0
	var y_lo := maxi(1, origin.y - 1)
	var y_hi := origin.y + 5
	_brush.begin_edit()
	for a in range(-along_half, along_half + 1):
		for d in range(0, maxi(depth_vox, 1)):
			var col_x := origin.x + sx.x * a + ix.x * d
			var col_z := origin.z + sx.z * a + ix.z * d
			for y3 in range(y_lo, y_hi + 1):
				var vox := Vector3i(col_x, y3, col_z)
				var mat_id := _brush.get_vox(vox)
				if not VoxelMaterial.is_destructible(mat_id):
					continue
				if VoxelMaterial.is_cave_cage(mat_id):
					continue
				var carved := _brush.destroy_vox(vox)
				for entry in carved:
					if detached.size() < MAX_DEBRIS:
						detached.append(entry)
					removed += 1
				var key := Vector2i(vox.x, vox.z)
				var prev_y: int = int(column_max_y.get(key, -1))
				if vox.y > prev_y:
					column_max_y[key] = vox.y
	_brush.end_edit()
	if removed <= 0:
		return 0
	var world_hit := _terrain.to_global(
		Vector3(float(origin.x) + 0.5, float(origin.y) + 0.5, float(origin.z) + 0.5)
	)
	_ensure_cascade_debris()
	if _cascade != null and is_instance_valid(_cascade):
		if _cascade.has_method("detach_blast_voxels") and not detached.is_empty():
			CityProfiler.begin("cascade_detach")
			_cascade.call("detach_blast_voxels", detached, world_hit)
			CityProfiler.end("cascade_detach")
		for key_v: Variant in column_max_y.keys():
			var xz: Vector2i = key_v as Vector2i
			var max_y: int = int(column_max_y[key_v])
			_cascade_column_above(Vector3i(xz.x, max_y, xz.y))
	_notify_destruction(world_hit, 20.0)
	return removed


## Giant facade brush: peel full-height structure strips and tumble the debris.
## inward = toward the wall, along = walk direction parallel to the facade.
##
## No AI drives this any more — mobs hunt bodies, never fabric. Kept as a voxel operation a
## future scripted set-piece can call; the only damage buildings take now is collateral.
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
				if not _monster_may_chew(vox, _brush.get_vox(vox)):
					continue
				var carved := _brush.destroy_vox(vox)
				for entry in carved:
					if detached.size() < MAX_DEBRIS:
						detached.append(entry)
					removed += 1
	_brush.end_edit()
	if removed <= 0:
		return 0
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


## Remove one nearby building voxel. No cascade. Like `undead_giant_scrape_at`, nothing in
## the AI calls this since mobs stopped targeting buildings.
func undead_nibble_building_near(world_pos: Vector3, reach_m: float) -> bool:
	if _terrain == null or _tool == null:
		return false
	var vox := _find_building_vox_near(world_pos, reach_m)
	if vox == Vector3i(2147483647, 2147483647, 2147483647):
		return false
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var carved := _brush.destroy_vox(vox)
	if carved.is_empty():
		return false
	var world := _terrain.to_global(Vector3(float(vox.x) + 0.5, float(vox.y) + 0.5, float(vox.z) + 0.5))
	_notify_tetris_damage(carved)
	_notify_destruction(world, 10.0)
	return true


## World position of a nearby building fabric voxel, or Vector3.INF.
func find_nearest_building_nibble(from: Vector3, max_dist: float) -> Vector3:
	var vox := _find_building_vox_near(from, max_dist)
	if vox == Vector3i(2147483647, 2147483647, 2147483647):
		return Vector3.INF
	return _terrain.to_global(Vector3(float(vox.x) + 0.5, float(vox.y) + 0.5, float(vox.z) + 0.5))


## Hard cap on XZ columns probed. A naïve 45 m ring × 48-tall scan is ~1.5M get_voxel
## calls (~1.5 s) when nothing is in range — paid on the physics thread the first time a
## minion/monster acquires a facade goal, and again whenever that goal fails and restarts.
const BUILDING_PROBE_COLUMN_BUDGET := 384
## Street-level pass first; tall floors only when the short pass found nothing in-budget.
const BUILDING_PROBE_DY_STREET := 16
const BUILDING_PROBE_DY_TALL := 48


func _find_building_vox_near(from: Vector3, max_dist: float) -> Vector3i:
	const SENTINEL := Vector3i(2147483647, 2147483647, 2147483647)
	if _terrain == null or _tool == null:
		return SENTINEL
	CityProfiler.begin("building_nibble_query")
	var best := _find_building_vox_near_budgeted(from, max_dist, SENTINEL)
	CityProfiler.end("building_nibble_query")
	return best


func _find_building_vox_near_budgeted(
	from: Vector3, max_dist: float, sentinel: Vector3i
) -> Vector3i:
	var local := _terrain.to_local(from)
	var max_vox := maxi(int(ceil(max_dist / VOXEL_SIZE)), 2)
	var ox := int(floor(local.x))
	var oy := int(floor(local.y))
	var oz := int(floor(local.z))
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var best := sentinel
	var best_score := -1.0e30
	var columns_left := BUILDING_PROBE_COLUMN_BUDGET
	## Footprint edges first: when impostor LOD has buildings, this finds fabric in a handful
	## of columns instead of walking an empty plaza out to max_dist.
	var seeds := _building_probe_seed_columns(from, max_dist)
	for seed: Vector2i in seeds:
		if columns_left <= 0:
			break
		columns_left -= 1
		var scored := _score_building_column(
			Vector3i(seed.x, oy, seed.y), from, max_dist, BUILDING_PROBE_DY_STREET, best_score
		)
		if scored["score"] > best_score:
			best_score = float(scored["score"])
			best = scored["vox"] as Vector3i
	if best != sentinel:
		return best
	## Expanding ring, same scoring as before, but stop when the column budget is spent so a
	## park / plaza / far-empty tile cannot freeze the frame.
	for r in range(0, max_vox + 1):
		if columns_left <= 0:
			break
		var found_this_ring := false
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if r > 0 and absi(dx) != r and absi(dz) != r:
					continue
				if columns_left <= 0:
					break
				columns_left -= 1
				var scored_ring := _score_building_column(
					Vector3i(ox + dx, oy, oz + dz),
					from,
					max_dist,
					BUILDING_PROBE_DY_STREET,
					best_score
				)
				if scored_ring["score"] > best_score:
					best_score = float(scored_ring["score"])
					best = scored_ring["vox"] as Vector3i
					found_this_ring = true
		if found_this_ring and r >= 2:
			return best
	if best != sentinel or columns_left <= 0:
		return best
	## Second pass: spend any leftover budget on tall floors near the origin (peeled shells).
	var tall_r := mini(max_vox, 12)
	for r2 in range(0, tall_r + 1):
		if columns_left <= 0:
			break
		for dz2 in range(-r2, r2 + 1):
			for dx2 in range(-r2, r2 + 1):
				if r2 > 0 and absi(dx2) != r2 and absi(dz2) != r2:
					continue
				if columns_left <= 0:
					break
				columns_left -= 1
				var scored_tall := _score_building_column(
					Vector3i(ox + dx2, oy, oz + dz2),
					from,
					max_dist,
					BUILDING_PROBE_DY_TALL,
					best_score
				)
				if scored_tall["score"] > best_score:
					best_score = float(scored_tall["score"])
					best = scored_tall["vox"] as Vector3i
	return best


## Nearest footprint-edge columns from loaded districts, closest first.
func _building_probe_seed_columns(from: Vector3, max_dist: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if _streamer == null:
		return out
	if _terrain == null:
		return out
	var ranked: Array = []
	var districts := _streamer.get_loaded_districts()
	for entry in districts:
		var inst := _as_district_instance(entry)
		if inst == null or not is_instance_valid(inst) or inst.building_lod == null:
			continue
		for b in inst.building_lod.get_footprints_near(from, max_dist):
			var center: Vector3 = b["center"] as Vector3
			var size: Vector3 = b["size"] as Vector3
			var hx := size.x * 0.5
			var hz := size.z * 0.5
			var edge := Vector3(
				clampf(from.x, center.x - hx, center.x + hx),
				center.y,
				clampf(from.z, center.z - hz, center.z + hz)
			)
			var d2 := Vector2(edge.x - from.x, edge.z - from.z).length_squared()
			if d2 > max_dist * max_dist:
				continue
			var local := _terrain.to_local(edge)
			ranked.append({
				"d2": d2,
				"col": Vector2i(int(floor(local.x)), int(floor(local.z))),
			})
	ranked.sort_custom(func(a: Variant, b: Variant) -> bool: return float(a["d2"]) < float(b["d2"]))
	var seen: Dictionary = {}
	for item: Variant in ranked:
		var col: Vector2i = item["col"] as Vector2i
		if seen.has(col):
			continue
		seen[col] = true
		out.append(col)
		if out.size() >= 24:
			break
	return out


## True when a monster peeling structures may take this cell: the fabric test it always used, plus the
## rule that a standing structure holds its own voxels. A giant scraping a siege tower down cell by
## cell is the same desync as a player blasting one — the pool would still be standing.
func _monster_may_chew(vox: Vector3i, mat_id: int) -> bool:
	if not VoxelMaterial.is_undead_structure_target(mat_id):
		return false
	return not _ward.holds(vox)


## Score one XZ column for undead facade work. Returns {score, vox}; score stays below
## `beat_score` rejection path as -INF when nothing better was found.
func _score_building_column(
	base: Vector3i,
	from: Vector3,
	max_dist: float,
	dy_max: int,
	beat_score: float
) -> Dictionary:
	var best_score := beat_score
	var best := Vector3i(2147483647, 2147483647, 2147483647)
	var nbrs: Array[Vector3i] = [
		Vector3i(1, 0, 0),
		Vector3i(-1, 0, 0),
		Vector3i(0, 0, 1),
		Vector3i(0, 0, -1),
	]
	for dy in range(0, dy_max):
		var v := Vector3i(base.x, base.y + dy, base.z)
		if not _monster_may_chew(v, int(_tool.get_voxel(v))):
			continue
		var center := _terrain.to_global(
			Vector3(float(v.x) + 0.5, float(v.y) + 0.5, float(v.z) + 0.5)
		)
		var world_d := center.distance_to(from)
		if world_d > max_dist:
			continue
		var exposed := 0
		for off in nbrs:
			var nid := int(_tool.get_voxel(v + off))
			if not VoxelMaterial.is_undead_structure_target(nid):
				exposed += 1
		var score := float(exposed) * 40.0 - world_d
		if score <= best_score:
			continue
		best_score = score
		best = v
	return {"score": best_score, "vox": best}


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
				if not _monster_may_chew(vox, _brush.get_vox(vox)):
					continue
				removed += _brush.destroy_vox(vox).size()
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
		var seed_entry := entry as Dictionary
		var vox: Vector3i = seed_entry.get("vox", Vector3i.ZERO)
		var prev_mat := int(seed_entry.get("prev_mat", -1))
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
	var beam := site.get("beam", null) as InfectionSkyBeamVfx
	if beam != null and is_instance_valid(beam):
		beam.begin_fade_out(1.2)
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
			var entry := item as Dictionary
			vox = entry.get("vox", Vector3i.ZERO)
			## Fast path from collect mat id.
			if int(entry.get("mat", -1)) == VoxelMaterial.INFECTION_LEAD:
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
	if _streamer == null:
		return
	var districts := _streamer.get_loaded_districts()
	for entry in districts:
		var inst := _as_district_instance(entry)
		if inst == null or not is_instance_valid(inst):
			continue
		if inst.crowd != null and is_instance_valid(inst.crowd):
			inst.crowd.react_to_destruction(world_pos, radius_m)
		if inst.vehicles != null and is_instance_valid(inst.vehicles):
			inst.vehicles.react_to_destruction(world_pos, radius_m)
		if inst.birds != null and is_instance_valid(inst.birds):
			inst.birds.react_to_destruction(world_pos, radius_m)


## First destructible voxel along a world ray (includes walk-through park mats:
## bark / leaves / planters). Physics rays miss those because they have no collision.
## Returns {} or {point, normal, distance} in world space.
func probe_destructible_ray(from_world: Vector3, to_world: Vector3) -> Dictionary:
	return _probe_voxel_ray(from_world, to_world, true)


## First *solid* voxel along a world ray (walls, glass, bedrock, arena shell, …).
## Used for mob/player projectile occlusion and combat line of sight. Agents are ignored.
## Returns {} or {point, normal, distance, voxel_id} in world space.
func probe_solid_ray(from_world: Vector3, to_world: Vector3) -> Dictionary:
	return _probe_voxel_ray(from_world, to_world, false)


## True when no solid voxel blocks the segment. Missing terrain fails open (tools / boot).
func has_voxel_line_of_sight(from_world: Vector3, to_world: Vector3) -> bool:
	if _tool == null or _terrain == null:
		return true
	var hit := probe_solid_ray(from_world, to_world)
	if hit.is_empty():
		return true
	var dist := from_world.distance_to(to_world)
	return float(hit["distance"]) + VOXEL_SIZE * 0.6 >= dist


## Mid-flight probe for blaster / laser / charged blast. Distance to the nearest blocker
## along from→tip, or -1. Solids always count; agents (peds/cars/undead) when requested.
func projectile_obstacle_distance(
	from_world: Vector3, tip_world: Vector3, include_agents: bool = true
) -> float:
	var best := -1.0
	var solid := probe_solid_ray(from_world, tip_world)
	if not solid.is_empty():
		best = float(solid["distance"])
	if include_agents:
		var agent_d := laser_probe_agent_distance(from_world, tip_world)
		if agent_d >= 0.0 and (best < 0.0 or agent_d < best):
			best = agent_d
	return best


func _probe_voxel_ray(
	from_world: Vector3, to_world: Vector3, destructible_only: bool
) -> Dictionary:
	if _tool == null or _terrain == null:
		return {}
	var local_from := _terrain.to_local(from_world)
	var local_to := _terrain.to_local(to_world)
	var get_voxel := func(v: Vector3i) -> int: return int(_tool.get_voxel(v))
	var local_hit: Dictionary
	if destructible_only:
		local_hit = _probe_destructible_local(local_from, local_to, get_voxel)
	else:
		## Endpoints are terrain-local voxels — step pull-back is in voxel units (~1).
		local_hit = ProjectileLos.probe_solid_ray(
			local_from, local_to, get_voxel, 1.0
		)
	if local_hit.is_empty():
		return {}
	var world_dir := to_world - from_world
	var world_len := world_dir.length()
	if world_len < 0.05:
		return {}
	world_dir /= world_len
	## March ran in terrain-local voxel units (terrain.scale = VOXEL_SIZE). Convert.
	var hit_t := ProjectileLos.local_distance_to_world(
		float(local_hit["distance"]), local_from, local_to, world_len
	)
	var out := {
		"point": from_world + world_dir * hit_t,
		"normal": -world_dir,
		"distance": hit_t,
	}
	if local_hit.has("voxel_id"):
		out["voxel_id"] = local_hit["voxel_id"]
	return out


func _probe_destructible_local(
	local_from: Vector3, local_to: Vector3, get_voxel: Callable
) -> Dictionary:
	var delta := local_to - local_from
	var dist := delta.length()
	if dist < 0.05:
		return {}
	var dir := delta / dist
	var step := ProjectileLos.STEP_M
	var steps := int(ceil(dist / step)) + 1
	var prev := Vector3i(2147483647, 2147483647, 2147483647)
	for i in range(1, steps + 1):
		var p := local_from + dir * (float(i) * step)
		var v := Vector3i(int(floor(p.x)), int(floor(p.y)), int(floor(p.z)))
		if v == prev:
			continue
		prev = v
		var id := int(get_voxel.call(v))
		if not VoxelMaterial.is_destructible(id):
			continue
		## Local march: pull back ~0.2 voxel (not VOXEL_SIZE metres).
		var hit_t := clampf(float(i) * step - 0.2, 0.0, dist)
		return {
			"point": local_from + dir * hit_t,
			"normal": -dir,
			"distance": hit_t,
			"voxel_id": id,
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
	var agent_d := float(hit.get("distance", from.distance_to(point)))
	## Blaster / laser impacts march a short carve segment past the solid they stopped on.
	## Without this gate, a CageDemon (or any mob) behind glass steals the strike and the
	## wall never yields — solids must win so fabric can carve.
	var solid := probe_solid_ray(from, point)
	if not solid.is_empty() and float(solid["distance"]) + 0.2 < agent_d:
		return false
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
	if _streamer == null:
		return {}
	var best: Dictionary = {}
	var best_dist := INF
	var districts := _streamer.get_loaded_districts()
	for entry in districts:
		var inst := _as_district_instance(entry)
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
	if _monsters != null and is_instance_valid(_monsters):
		var u_hit: Dictionary = _monsters.query_segment_hit(from, to)
		if not u_hit.is_empty():
			var d3: float = float(u_hit["distance"])
			if d3 < best_dist:
				best_dist = d3
				best = u_hit.duplicate()
				best["kind"] = "undead"
				best["undead"] = _monsters
	return best


func _carve_destructible_sphere(local_center: Vector3, radius_vox: float) -> void:
	_carve_destructible_sphere_counted(local_center, radius_vox)


func _carve_destructible_sphere_counted(local_center: Vector3, radius_vox: float) -> int:
	## Point carve — same hardness gate as blaster / charged blast (used to ignore tier).
	var removed := 0
	var r_i := int(ceil(radius_vox)) + 1
	var r2 := radius_vox * radius_vox
	var cx := int(floor(local_center.x))
	var cy := int(floor(local_center.y))
	var cz := int(floor(local_center.z))
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var allow_chip := _roll_carve_chip()
	var center_vox := Vector3i(cx, cy, cz)
	var center_mat := _brush.get_vox(center_vox) if _brush != null else VoxelMaterial.AIR
	var center_verdict := _carve_verdict(center_mat, center_vox)
	if (
		center_verdict == CarveVerdict.REFUSE
		or (center_verdict == CarveVerdict.CHIP and not allow_chip)
	):
		_flash_hardness_refuse(center_mat)
	_brush.begin_edit()
	for z in range(cz - r_i, cz + r_i + 1):
		for y in range(cy - r_i, cy + r_i + 1):
			for x in range(cx - r_i, cx + r_i + 1):
				var center := Vector3(float(x) + 0.5, float(y) + 0.5, float(z) + 0.5)
				if center.distance_squared_to(local_center) > r2 + 0.0001:
					continue
				var vox := Vector3i(x, y, z)
				var mat_id := _brush.get_vox(vox)
				if not _carve_allowed(mat_id, vox, allow_chip):
					continue
				removed += _brush.destroy_vox(vox).size()
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
	var aim: Dictionary = _walker.call("aim_ground_at_cursor")
	return aim["point"]


func _player_controls() -> PlayerControls:
	if _settings_panel == null:
		return null
	return _settings_panel.get_player_controls()


## Closest cabin in `inst` whose footprint (plus a 1-cell apron) holds the feet at a
## landing. Keys: shaft, from_i (landing the player is on), d2. Empty when none.
func _elevator_at_feet(inst: DistrictInstance, feet: Vector3) -> Dictionary:
	var shafts: Array = inst.elevator_shafts
	if shafts.is_empty():
		return {}
	var foot_vox := Vector3i(
		int(floor(feet.x / VOXEL_SIZE)),
		int(floor(feet.y / VOXEL_SIZE)),
		int(floor(feet.z / VOXEL_SIZE))
	)
	var best := {}
	var best_d2 := INF
	for shaft_v in shafts:
		var shaft: ElevatorShaft = shaft_v as ElevatorShaft
		if shaft == null:
			continue
		if shaft.landing_count() < 2:
			continue
		var from_i := shaft.foot_landing_index(foot_vox)
		if from_i < 0:
			continue
		var d2: float = shaft.world_anchor(from_i, VOXEL_SIZE).distance_squared_to(feet)
		if d2 >= best_d2:
			continue
		best_d2 = d2
		best = {"shaft": shaft, "from_i": from_i, "d2": d2}
	return best


## Mount the floor selector on the cabin the player is standing in, or park it.
func _refresh_elevator_panel() -> void:
	if _game_over or _walker.is_elevator_riding():
		if _elevator_panel != null:
			_elevator_panel.unbind()
		return
	var feet: Vector3 = _walker.global_position
	var best := {}
	var best_d2 := INF
	for entry in _streamer.get_loaded_districts():
		var inst: DistrictInstance = _as_district_instance(entry)
		if inst == null:
			continue
		var at := _elevator_at_feet(inst, feet)
		if at.is_empty() or float(at["d2"]) >= best_d2:
			continue
		best_d2 = float(at["d2"])
		best = at
	if best.is_empty():
		if _elevator_panel != null:
			_elevator_panel.unbind()
		return
	_ensure_elevator_panel()
	_elevator_panel.bind_to(best["shaft"] as ElevatorShaft, int(best["from_i"]), VOXEL_SIZE)


func _ensure_elevator_panel() -> void:
	if _elevator_panel != null and is_instance_valid(_elevator_panel):
		return
	_elevator_panel = ElevatorPanelScript.new() as ElevatorPanel
	_elevator_panel.name = "ElevatorPanel"
	add_child(_elevator_panel)
	_elevator_panel.floor_selected.connect(_on_elevator_floor_selected)


func _on_elevator_floor_selected(landing_index: int) -> void:
	if _walker == null or not is_instance_valid(_walker) or _elevator_panel == null:
		return
	var shaft := _elevator_panel.bound_shaft()
	if shaft == null:
		return
	if landing_index < 0 or landing_index >= shaft.landing_count():
		push_error("CityRoot: elevator floor %d of %d" % [landing_index, shaft.landing_count()])
		return
	_walker.begin_elevator_ride(shaft.world_anchor(landing_index, VOXEL_SIZE))


## Blaster-aim world interact: toggle the hung door under the aim ray, if any.
## Elevator rides are Ui3D panel clicks only — not handled here.
func try_interact_aim(origin: Vector3, aim_point: Vector3) -> bool:
	if _streamer == null:
		return false
	var dir := aim_point - origin
	if dir.length_squared() < 0.000001:
		return false
	dir = dir.normalized()
	var max_dist: float = float(CastleDoorPlacer.INTERACT_DISTANCE)
	var best_t := max_dist + 1.0
	var best_door: CastleDoorPlacer.Hung = null
	var best_placer: CastleDoorPlacer = null
	for entry in _streamer.get_loaded_districts():
		var inst: DistrictInstance = _as_district_instance(entry)
		if inst == null or inst.castle_doors == null or not is_instance_valid(inst.castle_doors):
			continue
		var hit: Dictionary = inst.castle_doors.door_hit_along_ray(origin, dir, max_dist)
		if hit.is_empty():
			continue
		var t: float = float(hit["t"])
		if t >= best_t:
			continue
		best_t = t
		best_door = hit["door"] as CastleDoorPlacer.Hung
		best_placer = inst.castle_doors
	## Closed doors are DOOR voxels — a plane miss that still lands on a plug counts.
	if best_door == null:
		var voxel_hit := _door_from_voxel_ray(origin, dir, max_dist)
		if not voxel_hit.is_empty():
			best_door = voxel_hit["door"] as CastleDoorPlacer.Hung
			best_placer = voxel_hit["placer"] as CastleDoorPlacer
	if best_door == null or best_placer == null:
		return false
	var opening := best_door.closed
	if not best_placer.toggle_door(best_door):
		return false
	## Opening onto an undecorated interior starts the JIT pipeline while the
	## walker is still on the street — partitions (and the room beyond) finish
	## before the first step inside.
	if opening and not best_door.closed:
		_prime_interior_beyond_door(best_door)
	return true


## First DOOR voxel along the aim segment mapped back to its hung door.
func _door_from_voxel_ray(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var tip := origin + dir * max_dist
	var solid := probe_solid_ray(origin, tip)
	if solid.is_empty():
		return {}
	if int(solid.get("voxel_id", -1)) != VoxelMaterial.DOOR:
		return {}
	var dist: float = float(solid.get("distance", INF))
	if dist > max_dist:
		return {}
	var point: Vector3 = solid["point"] as Vector3
	## Step slightly into the hit so floor() lands inside the DOOR cell, not the face.
	var inward := point + dir * (VOXEL_SIZE * 0.25)
	var world_vox := Vector3i(
		int(floor(inward.x / VOXEL_SIZE)),
		int(floor(inward.y / VOXEL_SIZE)),
		int(floor(inward.z / VOXEL_SIZE))
	)
	for entry in _streamer.get_loaded_districts():
		var inst: DistrictInstance = _as_district_instance(entry)
		if inst == null or inst.castle_doors == null or not is_instance_valid(inst.castle_doors):
			continue
		var door: CastleDoorPlacer.Hung = inst.castle_doors.door_at_voxel(world_vox)
		if door != null:
			return {"door": door, "placer": inst.castle_doors, "t": dist}
	return {}


## Probe one cell past the inner face of the opening and ask InteriorDecorator to work
## that storey. Castle doors and doors with no city interior simply miss and clear.
func _prime_interior_beyond_door(door: CastleDoorPlacer.Hung) -> void:
	if _interior_decorator == null or door == null or door.doorway == null:
		return
	var d: CastleDoorway = door.doorway
	var step := maxi(d.depth, 1)
	var col: Vector2i = d.center + d.axis * step
	var world_vox := Vector3i(col.x, d.floor_y + 1, col.y) + door.origin_vox
	var world := Vector3(
		(float(world_vox.x) + 0.5) * VOXEL_SIZE,
		(float(world_vox.y) + 0.5) * VOXEL_SIZE,
		(float(world_vox.z) + 0.5) * VOXEL_SIZE
	)
	_interior_decorator.prime_at(world)


func _unhandled_input(event: InputEvent) -> void:
	var ek := event as InputEventKey
	if ek == null or not ek.pressed or ek.echo:
		return
	## Debug: Ctrl+Shift+F12 toggles the cheat modal. Not remappable on purpose.
	## Checked before bare F12 (screenshot) so the modifier chord is not eaten as a shot.
	if (
		ek.keycode == KEY_F12
		and ek.ctrl_pressed
		and ek.shift_pressed
		and not ek.alt_pressed
	):
		if _cheat_panel != null and not _booting and not is_splash_open():
			_cheat_panel.toggle_panel()
		get_viewport().set_input_as_handled()
		return
	## F12 → PNG under <install>/screenshots/. Steam-style; OBS covers video.
	if ek.keycode == KEY_F12 and not ek.ctrl_pressed and not ek.alt_pressed:
		_take_screenshot()
		get_viewport().set_input_as_handled()
		return
	var ctl := _player_controls()
	if ctl == null:
		return
	if ctl.matches_key_pressed(ek, "quit"):
		if is_inventory_open():
			_inventory_panel.close_panel()
			get_viewport().set_input_as_handled()
			return
		if is_monster_summon_open():
			_monster_summon_panel.close_panel()
			get_viewport().set_input_as_handled()
			return
		if is_siege_build_picker_open():
			_siege_build_picker.close_panel()
			get_viewport().set_input_as_handled()
			return
		if is_game_menu_open():
			_game_menu.close_panel()
			get_viewport().set_input_as_handled()
			return
		if is_cheat_open():
			_cheat_panel.close_panel()
			get_viewport().set_input_as_handled()
			return
		## Quitting from the keyboard never reaches the window manager, so this is the only chance
		## to save while the walker is still standing in the world.
		_autosave_on_exit()
		get_tree().quit()
		return
	if ctl.matches_key_pressed(ek, "inventory"):
		## The character editor is a modal of the walker's own, and two open panels would
		## stack in whatever order UiLayers happens to give them. The splash outranks the whole
		## modal band, so a panel opened under it is invisible and still takes the keys.
		if _game_over or _booting or _is_character_editor_open() or is_splash_open():
			return
		if _inventory_panel != null:
			_inventory_panel.toggle_panel()
		get_viewport().set_input_as_handled()
		return
	if ctl.matches_key_pressed(ek, "monster_summon"):
		if _game_over or _booting or _is_character_editor_open() or is_splash_open():
			return
		if _monster_summon_panel != null:
			## Sample world aim before the panel moves the free cursor onto its UI; a live
			## sample at confirm would hit near the player's feet.
			if not is_monster_summon_open():
				capture_summon_aim()
			_monster_summon_panel.toggle_panel()
		get_viewport().set_input_as_handled()
		return
	if ctl.matches_key_pressed(ek, "retry"):
		if _game_over:
			_retry_after_game_over()
			get_viewport().set_input_as_handled()
		return
	if ctl.matches_key_pressed(ek, "day_night"):
		## World keys stop at an open panel or the splash; the debug toggles below deliberately
		## do not.
		if _game_over or is_modal_open() or is_splash_open():
			return
		if _day_night != null:
			_day_night.toggle_day_night()
		get_viewport().set_input_as_handled()
		return
	## Shift+F8 recolours, bare F8 toggles — the modifier-carrying bind is tested first,
	## because a bare bind matches with extra modifiers held.
	if ctl.matches_key_pressed(ek, "nav_overlay_colour"):
		if _nav_overlay.is_enabled():
			print("CityRoot: nav overlay colouring by %s" % _nav_overlay.cycle_span_colour())
		get_viewport().set_input_as_handled()
		return
	if ctl.matches_key_pressed(ek, "nav_overlay"):
		print("CityRoot: nav overlay %s" % ("on" if _nav_overlay.toggle() else "off"))
		get_viewport().set_input_as_handled()


## Grab the game viewport into `<install>/screenshots/` and toast the filename.
## Names are `{DistrictName}_{n}.png` — n counts up from 1 for that district name.
func _take_screenshot() -> void:
	var viewport := get_viewport()
	if viewport == null:
		push_error("CityRoot._take_screenshot: no viewport")
		return
	var tex := viewport.get_texture()
	if tex == null:
		push_error("CityRoot._take_screenshot: viewport has no texture")
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		push_error("CityRoot._take_screenshot: empty image")
		return
	var dir_abs := _screenshot_dir_abs()
	if not DirAccess.dir_exists_absolute(dir_abs):
		var mk := DirAccess.make_dir_recursive_absolute(dir_abs)
		if mk != OK:
			push_error(
				"CityRoot._take_screenshot: could not create %s (%s)"
				% [dir_abs, error_string(mk)]
			)
			return
	var base := _screenshot_district_base()
	var file_name := _next_screenshot_file_name(dir_abs, base)
	var abs_path := "%s/%s" % [dir_abs, file_name]
	var err := img.save_png(abs_path)
	if err != OK:
		push_error("CityRoot._take_screenshot: save failed %s (%s)" % [abs_path, error_string(err)])
		if _loot_toast != null:
			_loot_toast.show_message("Screenshot failed")
		return
	print("CityRoot: screenshot → %s" % abs_path)
	if _loot_toast != null:
		_loot_toast.show_message("Screenshot · %s" % file_name)


## Exported build: next to the .exe. Editor / project runs: project root.
func _screenshot_dir_abs() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://screenshots")
	return OS.get_executable_path().get_base_dir().path_join("screenshots")


## Place-name slug for the tile the walker is standing in (filesystem-safe).
func _screenshot_district_base() -> String:
	if _walker == null or not is_instance_valid(_walker):
		return "district"
	var here := DistrictCoord.from_world(_walker.global_position, VOXEL_SIZE)
	return _sanitize_screenshot_base(DistrictName.for_district(city_seed, here))


func _sanitize_screenshot_base(raw: String) -> String:
	var out := ""
	for i in raw.length():
		var ch := raw[i]
		var code := ch.unicode_at(0)
		var letter := (
			(code >= 48 and code <= 57)
			or (code >= 65 and code <= 90)
			or (code >= 97 and code <= 122)
		)
		if letter:
			out += ch
		elif ch == " " or ch == "-" or ch == "_":
			if out.is_empty() or out[out.length() - 1] != "_":
				out += "_"
	while out.ends_with("_"):
		out = out.substr(0, out.length() - 1)
	if out.is_empty():
		return "district"
	return out


## Smallest unused `{base}_{n}.png` in the screenshots folder (n starts at 1).
func _next_screenshot_file_name(dir_abs: String, base: String) -> String:
	var n := 1
	while FileAccess.file_exists("%s/%s_%d.png" % [dir_abs, base, n]):
		n += 1
		if n > 9999:
			push_error("CityRoot._next_screenshot_file_name: ran out of numbers for %s" % base)
			return "%s_%d.png" % [base, Time.get_ticks_msec()]
	return "%s_%d.png" % [base, n]


func _on_cheat_fill_gems() -> void:
	if _inventory == null:
		_cheat_log("Fill gems failed: no inventory.")
		push_error("CityRoot: cheat fill gems needs an inventory")
		return
	const TARGET := 99
	var filled := 0
	for mat_id in range(VoxelMaterial.GEM_QUARTZ, VoxelMaterial.GEM_DIAMOND + 1):
		var item_id := InventoryCatalog.item_id_for_gem(mat_id)
		if item_id.is_empty():
			continue
		var have := _inventory.count_of(item_id)
		var need := TARGET - have
		if need <= 0:
			continue
		var left := _inventory.add(item_id, need)
		if left != 0:
			push_error("CityRoot: cheat could not fit %d × %s" % [left, item_id])
		else:
			filled += 1
	var msg := "Filled %d gem type(s) to %d." % [filled, TARGET]
	_cheat_log(msg)
	print("CityRoot: cheat — %s" % msg)


func _on_cheat_fill_recipes() -> void:
	if _loadout == null:
		_cheat_log("Fill recipes failed: no loadout.")
		push_error("CityRoot: cheat fill recipes needs a loadout")
		return
	var before := _loadout.missing_recipe_ids().size()
	_loadout.learn_every_recipe()
	if _inventory_panel != null and _inventory_panel.has_method("rebuild_recipe_lists"):
		_inventory_panel.call("rebuild_recipe_lists")
	var after := _loadout.missing_recipe_ids().size()
	var learned := before - after
	var msg := (
		"Cookbook already full." if learned <= 0
		else "Learned %d recipe(s); %d still missing (should be 0)." % [learned, after]
	)
	_cheat_log(msg)
	print("CityRoot: cheat — %s" % msg)


func _on_cheat_teleport_nearest_recipe() -> void:
	if _walker == null or not is_instance_valid(_walker):
		_cheat_log("Teleport failed: no walker.")
		return
	if _streamer == null:
		_cheat_log("Teleport failed: world not streaming yet.")
		return
	var best: RecipePickup = null
	var best_dist := INF
	var from := _walker.global_position
	var scanned := 0
	for entry in _streamer.get_loaded_districts():
		var inst := _as_district_instance(entry)
		if inst == null or inst.recipe_pickups == null:
			continue
		if not is_instance_valid(inst.recipe_pickups):
			continue
		for pickup in inst.recipe_pickups.live_landmark_pickups():
			scanned += 1
			var d := from.distance_to(pickup.global_position)
			if d < best_dist:
				best_dist = d
				best = pickup
	if best == null:
		_cheat_log(
			"No landmark recipe scrolls in loaded districts (scanned %d; chests ignored)."
			% scanned
		)
		return
	var target := best.global_position
	var flat := Vector3(target.x - from.x, 0.0, target.z - from.z)
	if flat.length_squared() < 0.01:
		flat = Vector3(CHEAT_RECIPE_STAND_OFF_M, 0.0, 0.0)
	else:
		flat = flat.normalized() * CHEAT_RECIPE_STAND_OFF_M
	var stand := Vector3(target.x - flat.x, target.y + 0.35, target.z - flat.z)
	_walker.velocity = Vector3.ZERO
	_walker.global_position = stand
	_walker.velocity = Vector3.ZERO
	## Face the scroll so the first click after closing the panel lands on it.
	var toward := target - stand
	if _walker.has_method("set_yaw"):
		_walker.call("set_yaw", atan2(-toward.x, -toward.z))
	var msg := "Teleported to %s (%.1f m away)." % [best.site_id, best_dist]
	_cheat_log(msg)
	print("CityRoot: cheat — %s" % msg)
	if _cheat_panel != null:
		_cheat_panel.close_panel()


## Hop to a Hill tile, then stand beside the Unique cave-cage boss enclosure.
func _on_cheat_teleport_cave_cage() -> void:
	if _walker == null or not is_instance_valid(_walker):
		_cheat_log("Cave cage teleport failed: no walker.")
		return
	if _streamer == null:
		_cheat_log("Cave cage teleport failed: world not streaming yet.")
		return
	if _district_hopping:
		_cheat_log("Cave cage teleport failed: already hopping.")
		return
	var dest := DistrictTheme.find_coord_for_theme(city_seed, DistrictTheme.HILL)
	var theme := DistrictTheme.for_district(city_seed, dest)
	if theme.id != DistrictTheme.HILL:
		_cheat_log("Cave cage teleport failed: no Hill district found.")
		push_error("CityRoot: cheat cave cage — no Hill for seed %d" % city_seed)
		return
	_cheat_log("Hopping to Hill %s for the cave cage…" % str(dest))
	if _cheat_panel != null:
		_cheat_panel.close_panel()
	_district_hopping = true
	await _district_hop_to(dest, _walker.global_position)
	if _walker == null or not is_instance_valid(_walker):
		return
	var cage_inst: DistrictInstance = null
	for entry in _streamer.get_loaded_districts():
		var inst := _as_district_instance(entry)
		if inst == null or inst.coord != dest:
			continue
		cage_inst = inst
		break
	if cage_inst == null:
		_cheat_log("Cave cage teleport: Hill loaded but district instance missing.")
		push_error("CityRoot: cheat cave cage — no DistrictInstance at %s" % str(dest))
		return
	if not cage_inst.cave_cage_stand_world.is_finite():
		_cheat_log("Cave cage teleport: Hill has no cage stand (no chamber?).")
		push_error("CityRoot: cheat cave cage — INF stand at %s" % str(dest))
		return
	var target: Vector3 = cage_inst.cave_cage_stand_world
	var from := _walker.global_position
	var flat := Vector3(target.x - from.x, 0.0, target.z - from.z)
	if flat.length_squared() < 0.01:
		flat = Vector3(CHEAT_CAGE_STAND_OFF_M, 0.0, 0.0)
	else:
		flat = flat.normalized() * CHEAT_CAGE_STAND_OFF_M
	var stand := Vector3(target.x - flat.x, target.y + 0.35, target.z - flat.z)
	_walker.velocity = Vector3.ZERO
	_walker.global_position = stand
	_walker.velocity = Vector3.ZERO
	var toward := target - stand
	if _walker.has_method("set_yaw"):
		_walker.call("set_yaw", atan2(-toward.x, -toward.z))
	var msg := "Stood beside cave cage at %s." % str(dest)
	_cheat_log(msg)
	print("CityRoot: cheat — %s" % msg)


func _cheat_log(line: String) -> void:
	if _cheat_panel != null:
		_cheat_panel.append_log(line)


func _input(event: InputEvent) -> void:
	## Game-over respawn must work even if another control ate unhandled input.
	if not _game_over or _booting or _respawning:
		return
	var ek := event as InputEventKey
	if ek == null or not ek.pressed or ek.echo:
		return
	var ctl := _player_controls()
	if ctl != null and ctl.matches_key_pressed(ek, "retry"):
		_retry_after_game_over()
		get_viewport().set_input_as_handled()
