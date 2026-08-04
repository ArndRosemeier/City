## Eccentri City SFX. On by default; toggle with O.
## Prefers Kenney CC0 clips under res://assets/audio/; procedural fallback if missing.
class_name CityAudio
extends Node

const GROUP_NAME := &"city_audio"
const POOL_SIZE := 12
const GEM_VOICE_COUNT := 4
const MAX_DEBRIS_PER_SEC := 14.0
const MAX_PLATE_BURN_PER_SEC := 10.0
const MAX_MONSTER_FOOT_PER_SEC := 20.0
const MAX_TENDRIL_VOICES := 10
## Combat / zoo SFX need to read across a district, not just at arm's length.
const MONSTER_SFX_MAX_DISTANCE := 220.0
const MONSTER_SFX_UNIT_SIZE := 32.0
const LOCAL_SFX_MAX_DISTANCE := 80.0
const LOCAL_SFX_UNIT_SIZE := 4.0

const FOOTSTEP_DIR := "res://assets/audio/footstep"
const DEBRIS_DIR := "res://assets/audio/debris"
const LASER_FIRE_DIR := "res://assets/audio/laser"
const BLAST_DIR := "res://assets/audio/blast"
const UI_DIR := "res://assets/audio/ui"

var enabled: bool = true

var _foot_streams: Array[AudioStream] = []
var _debris_streams: Array[AudioStream] = []
var _laser_fire_streams: Array[AudioStream] = []
var _laser_impact_streams: Array[AudioStream] = []
var _blast_charge_streams: Array[AudioStream] = []
var _blast_throw_streams: Array[AudioStream] = []
var _blast_impact_streams: Array[AudioStream] = []
var _ui_on: AudioStream
var _ui_off: AudioStream
var _meteor_whine_stream: AudioStream
var _meteor_crash_stream: AudioStream
var _tendril_drone_stream: AudioStream
var _tendril_tick_stream: AudioStream
var _gem_pickup_stream: AudioStream
## Chest lid and the flourish for a whole haul. No pack has either mood, so both are synthesized.
var _chest_open_stream: AudioStream
var _bling_stream: AudioStream
## Yunzi-style glass stone on wood — sharp clack + short crystalline ring.
var _go_stone_bling_stream: AudioStream
## Fractal panel lock-on — a short locking chirp when the postcard autozoom lands.
var _lock_on_stream: AudioStream

## Monster / fist melee — no Kenney pack for this mood, so always procedural.
var _melee_swing_streams: Array[AudioStream] = []
var _melee_hit_streams: Array[AudioStream] = []
## Purple conversion orb cast + impact.
var _orb_cast_streams: Array[AudioStream] = []
var _orb_impact_streams: Array[AudioStream] = []
## Monster Zoo: hostile turf sizzle, summon shimmer, summon solidify.
var _zoo_plate_streams: Array[AudioStream] = []
var _zoo_summon_start_streams: Array[AudioStream] = []
var _zoo_summon_ready_streams: Array[AudioStream] = []

var _pool: Array[AudioStreamPlayer3D] = []
var _pool_i: int = 0
var _rng := RandomNumberGenerator.new()
var _debris_budget: float = 0.0
var _plate_burn_budget: float = 0.0
var _monster_foot_budget: float = 0.0
var _ui_player: AudioStreamPlayer
var _gem_players: Array[AudioStreamPlayer] = []
var _gem_player_i: int = 0
var _bling_player: AudioStreamPlayer
var _whine_player: AudioStreamPlayer3D
var _whine_follow: Node3D
var _crash_player: AudioStreamPlayer3D
var _blast_charge_player: AudioStreamPlayer3D
var _blast_impact_player: AudioStreamPlayer3D
var _explosive_boom_player: AudioStreamPlayer3D
var _explosive_boom_stream: AudioStream
var _dissolve_hiss_player: AudioStreamPlayer3D
var _dissolve_hiss_stream: AudioStream
var _tendril_voices: Dictionary = {}  # tendril_id → AudioStreamPlayer3D


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_rng.randomize()
	_load_banks()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.name = "Sfx_%d" % i
		p.max_distance = LOCAL_SFX_MAX_DISTANCE
		p.unit_size = LOCAL_SFX_UNIT_SIZE
		p.max_db = 6.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.bus = &"Master"
		add_child(p)
		_pool.append(p)
	_ui_player = AudioStreamPlayer.new()
	_ui_player.name = "UiSfx"
	_ui_player.bus = &"Master"
	add_child(_ui_player)
	for i in GEM_VOICE_COUNT:
		var gp := AudioStreamPlayer.new()
		gp.name = "GemPickup_%d" % i
		gp.bus = &"Master"
		add_child(gp)
		_gem_players.append(gp)
	_bling_player = AudioStreamPlayer.new()
	_bling_player.name = "TreasureBling"
	_bling_player.bus = &"Master"
	add_child(_bling_player)
	_whine_player = _make_dedicated_player("MeteorWhine", 420.0, 18.0)
	_crash_player = _make_dedicated_player("MeteorCrash", 720.0, 42.0)
	_crash_player.attenuation_filter_cutoff_hz = 5000.0
	_blast_charge_player = _make_dedicated_player(
		"BlastCharge", MONSTER_SFX_MAX_DISTANCE, MONSTER_SFX_UNIT_SIZE
	)
	_blast_charge_player.attenuation_filter_cutoff_hz = 14000.0
	## Inverse distance (not square) so charged impacts still read across the zoo.
	_blast_impact_player = _make_dedicated_player(
		"BlastImpact3D", MONSTER_SFX_MAX_DISTANCE, MONSTER_SFX_UNIT_SIZE
	)
	_blast_impact_player.max_db = 12.0
	_blast_impact_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_blast_impact_player.attenuation_filter_cutoff_hz = 14000.0
	## Material detonations — carries farther than a normal charged impact.
	_explosive_boom_player = _make_dedicated_player("ExplosiveBoom", 420.0, 28.0)
	_explosive_boom_player.max_db = 14.0
	_explosive_boom_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_explosive_boom_player.attenuation_filter_cutoff_hz = 6000.0
	## Dissolve cascade — crystalline unravel, not a crater boom. Long enough to cover a
	## whole cage's infection waves; position follows the frontier while it plays.
	_dissolve_hiss_player = _make_dedicated_player("DissolveHiss", 140.0, 18.0)
	_dissolve_hiss_player.max_db = 10.0
	_dissolve_hiss_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	_dissolve_hiss_player.attenuation_filter_cutoff_hz = 12000.0


func _process(delta: float) -> void:
	_debris_budget = minf(_debris_budget + MAX_DEBRIS_PER_SEC * delta, MAX_DEBRIS_PER_SEC)
	_plate_burn_budget = minf(
		_plate_burn_budget + MAX_PLATE_BURN_PER_SEC * delta, MAX_PLATE_BURN_PER_SEC
	)
	_monster_foot_budget = minf(
		_monster_foot_budget + MAX_MONSTER_FOOT_PER_SEC * delta, MAX_MONSTER_FOOT_PER_SEC
	)
	if _whine_follow != null and is_instance_valid(_whine_follow) and _whine_player.playing:
		_whine_player.global_position = _whine_follow.global_position
		## Pitch climbs as it drops — incoming scream.
		var height := maxf(_whine_follow.global_position.y, 0.0)
		_whine_player.pitch_scale = clampf(lerpf(1.55, 0.82, height / 60.0), 0.75, 1.7)
	elif _whine_player.playing and (_whine_follow == null or not is_instance_valid(_whine_follow)):
		_whine_player.stop()
		_whine_follow = null


func toggle() -> bool:
	enabled = not enabled
	if enabled:
		_play_ui(_ui_on)
	else:
		_play_ui(_ui_off)
		_stop_infection_sfx()
	return enabled


func is_enabled() -> bool:
	return enabled


func play_footstep(world_pos: Vector3, character_scale: float = 1.0) -> void:
	if not enabled:
		return
	var stream := _pick(_foot_streams)
	if stream == null:
		return
	var p := _next_player()
	p.stream = stream
	p.global_position = world_pos
	p.pitch_scale = clampf(1.1 / sqrt(maxf(character_scale, 0.2)), 0.55, 1.55)
	p.pitch_scale *= _rng.randf_range(0.94, 1.06)
	p.volume_db = -10.0 + clampf((character_scale - 1.0) * 2.0, -4.0, 5.0)
	p.play()


## Monster stride — same bank as the player, rate-limited so a packed Zoo does not
## drown every other SFX in stomps.
func play_monster_footstep(world_pos: Vector3, character_scale: float = 1.0) -> void:
	if not enabled:
		return
	if _monster_foot_budget < 1.0:
		return
	_monster_foot_budget -= 1.0
	var stream := _pick(_foot_streams)
	if stream == null:
		return
	var p := _next_monster_player()
	p.stream = stream
	p.global_position = world_pos
	p.pitch_scale = clampf(1.05 / sqrt(maxf(character_scale, 0.2)), 0.5, 1.5)
	p.pitch_scale *= _rng.randf_range(0.9, 1.1)
	p.volume_db = -5.5 + clampf((character_scale - 1.0) * 2.0, -3.0, 4.0)
	p.play()


func play_debris(world_pos: Vector3) -> void:
	if not enabled:
		return
	if _debris_budget < 1.0:
		return
	_debris_budget -= 1.0
	var stream := _pick(_debris_streams)
	if stream == null:
		return
	var p := _next_player()
	p.stream = stream
	p.global_position = world_pos
	p.pitch_scale = _rng.randf_range(0.82, 1.28)
	p.volume_db = _rng.randf_range(-12.0, -5.0)
	p.play()


## Bright non-positional chime — rarer gems ring higher.
func play_gem_pickup(_world_pos: Vector3, mat_id: int = -1) -> void:
	if not enabled:
		return
	if _gem_pickup_stream == null or _gem_players.is_empty():
		return
	var p := _gem_players[_gem_player_i]
	_gem_player_i = (_gem_player_i + 1) % _gem_players.size()
	p.stream = _gem_pickup_stream
	p.pitch_scale = _gem_pickup_pitch(mat_id) * _rng.randf_range(0.985, 1.025)
	p.volume_db = -5.5
	p.play()


## Latch and lid, at the chest. Positional: a chest is a thing in the room, and the player has just
## clicked it, so it should sound like it is where he is looking.
func play_chest_open(world_pos: Vector3) -> void:
	if not enabled:
		return
	if _chest_open_stream == null:
		return
	var p := _next_player()
	p.stream = _chest_open_stream
	p.global_position = world_pos
	p.pitch_scale = _rng.randf_range(0.94, 1.07)
	p.volume_db = -4.0
	p.play()


## The haul flourish: a rising sparkle that plays once for a whole find, however many stones were
## in it. Non-positional and its own voice, so it is never one of several pickup chimes fired in
## the same frame beating against each other.
func play_treasure_bling() -> void:
	if not enabled:
		return
	if _bling_stream == null or _bling_player == null:
		return
	_bling_player.stream = _bling_stream
	_bling_player.pitch_scale = _rng.randf_range(0.99, 1.01)
	_bling_player.volume_db = -4.5
	_bling_player.play()


## Go stone settle — glass Yunzi clack on the goban, never a debris/explosion hit.
func play_go_stone_bling(world_pos: Vector3) -> void:
	if not enabled:
		return
	if _go_stone_bling_stream == null:
		return
	var p := _next_player()
	p.stream = _go_stone_bling_stream
	p.global_position = world_pos
	## Tight pitch drift: each stone should still read as glass, not a random chime.
	p.pitch_scale = _rng.randf_range(0.97, 1.04)
	p.volume_db = -4.0
	p.play()


## Panel lock-on: a quick rising latch that says "this view is the one" without stealing the
## treasure bling the Create peak will play later.
func play_lock_on(world_pos: Vector3) -> void:
	if not enabled:
		return
	if _lock_on_stream == null:
		return
	var p := _next_player()
	p.stream = _lock_on_stream
	p.global_position = world_pos
	p.pitch_scale = _rng.randf_range(0.97, 1.04)
	p.volume_db = -5.0
	p.play()


func play_laser_fire(world_pos: Vector3, character_scale: float = 1.0) -> void:
	if not enabled:
		return
	var stream := _pick(_laser_fire_streams)
	if stream == null:
		return
	var p := _next_monster_player()
	p.stream = stream
	p.global_position = world_pos
	p.pitch_scale = clampf(1.0 / sqrt(maxf(character_scale, 0.25)), 0.55, 1.35)
	p.volume_db = -2.0
	p.play()


func play_laser_impact(world_pos: Vector3, character_scale: float = 1.0) -> void:
	if not enabled:
		return
	var stream := _pick(_laser_impact_streams)
	if stream == null:
		return
	var p := _next_monster_player()
	p.stream = stream
	p.global_position = world_pos
	p.pitch_scale = clampf(1.0 / sqrt(maxf(character_scale, 0.25)), 0.55, 1.3)
	p.volume_db = -0.5
	p.play()


## Hand charge ramp — pitched so the clip roughly fills charge_sec, stopped on release.
func play_charged_blast_charge(
	world_pos: Vector3, character_scale: float = 1.0, charge_sec: float = 1.6
) -> void:
	if not enabled:
		return
	var stream := _pick(_blast_charge_streams)
	if stream == null or _blast_charge_player == null:
		return
	_blast_charge_player.stream = stream
	_blast_charge_player.global_position = world_pos
	var clip_len := _stream_length_sec(stream)
	var target := maxf(charge_sec, 0.2)
	## Stretch / squeeze the ramp to the hold window (clamped so it stays musical).
	_blast_charge_player.pitch_scale = clampf(clip_len / target, 0.55, 2.8)
	_blast_charge_player.pitch_scale *= clampf(1.0 / sqrt(maxf(character_scale, 0.25)), 0.7, 1.25)
	_blast_charge_player.volume_db = -6.0
	_blast_charge_player.play()


func move_charged_blast_charge(world_pos: Vector3) -> void:
	if _blast_charge_player != null and _blast_charge_player.playing:
		_blast_charge_player.global_position = world_pos


func stop_charged_blast_charge() -> void:
	if _blast_charge_player != null and _blast_charge_player.playing:
		_blast_charge_player.stop()


func play_charged_blast_throw(world_pos: Vector3, character_scale: float = 1.0) -> void:
	if not enabled:
		return
	stop_charged_blast_charge()
	var stream := _pick(_blast_throw_streams)
	if stream == null:
		## Fall back so a missing bank never goes silent.
		play_laser_fire(world_pos, character_scale)
		return
	var p := _next_monster_player()
	p.stream = stream
	p.global_position = world_pos
	p.pitch_scale = clampf(1.0 / sqrt(maxf(character_scale, 0.25)), 0.55, 1.35)
	p.pitch_scale *= _rng.randf_range(0.96, 1.06)
	p.volume_db = -2.0
	p.play()


func play_charged_blast_impact(world_pos: Vector3, character_scale: float = 1.0) -> void:
	if not enabled:
		return
	var stream := _pick(_blast_impact_streams)
	## Fall back to throw woosh if no impact bank is present.
	if stream == null:
		stream = _pick(_blast_throw_streams)
	if stream == null:
		play_laser_impact(world_pos, character_scale)
		return
	var pitch := clampf(1.0 / sqrt(maxf(character_scale, 0.25)), 0.65, 1.2)
	pitch *= _rng.randf_range(0.97, 1.04)
	## Dedicated 3D voice only — a non-positional bus layer was flattening distance.
	## Note: AudioStreamPlayer3D.max_db defaults to 3; volume_db above that was a no-op.
	if _blast_impact_player != null:
		_blast_impact_player.stream = stream
		_blast_impact_player.global_position = world_pos
		_blast_impact_player.pitch_scale = pitch
		_blast_impact_player.max_db = 12.0
		_blast_impact_player.volume_db = 4.0
		_blast_impact_player.play()


## Fat low boom for explosive materials.
func play_explosive_boom(world_pos: Vector3) -> void:
	if not enabled:
		return
	if _explosive_boom_stream == null or _explosive_boom_player == null:
		play_charged_blast_impact(world_pos, 3.0)
		return
	_explosive_boom_player.stream = _explosive_boom_stream
	_explosive_boom_player.global_position = world_pos
	_explosive_boom_player.pitch_scale = _rng.randf_range(0.88, 1.02)
	_explosive_boom_player.max_db = 14.0
	_explosive_boom_player.volume_db = 5.0
	_explosive_boom_player.play()


## Crystalline unravel when dissolve fabric starts cascading. Call once at the seed hit;
## `move_dissolve_hiss` keeps it on the infection front while waves run.
func play_dissolve_hiss(world_pos: Vector3) -> void:
	if not enabled:
		return
	if _dissolve_hiss_stream == null or _dissolve_hiss_player == null:
		play_laser_impact(world_pos, 1.0)
		return
	_dissolve_hiss_player.stream = _dissolve_hiss_stream
	_dissolve_hiss_player.global_position = world_pos
	_dissolve_hiss_player.pitch_scale = _rng.randf_range(0.94, 1.06)
	_dissolve_hiss_player.max_db = 10.0
	_dissolve_hiss_player.volume_db = 2.0
	_dissolve_hiss_player.play()


## Keep the dissolve bed on the living frontier so it stays with the cage as it unravels.
func move_dissolve_hiss(world_pos: Vector3) -> void:
	if _dissolve_hiss_player == null or not _dissolve_hiss_player.playing:
		return
	_dissolve_hiss_player.global_position = world_pos


## Whoosh of a claw / fist swing. Scale drops the pitch for giants.
func play_melee_swing(world_pos: Vector3, character_scale: float = 1.0) -> void:
	if not enabled:
		return
	var stream := _pick(_melee_swing_streams)
	if stream == null:
		return
	var p := _next_monster_player()
	p.stream = stream
	p.global_position = world_pos
	p.pitch_scale = clampf(1.05 / sqrt(maxf(character_scale, 0.25)), 0.5, 1.45)
	p.pitch_scale *= _rng.randf_range(0.92, 1.08)
	p.volume_db = -1.5 + clampf((character_scale - 1.0) * 1.5, -3.0, 4.0)
	p.play()


## Flesh / bone thump when a melee connects (or stomps the ground).
func play_melee_hit(world_pos: Vector3, character_scale: float = 1.0) -> void:
	if not enabled:
		return
	var stream := _pick(_melee_hit_streams)
	if stream == null:
		return
	var p := _next_monster_player()
	p.stream = stream
	p.global_position = world_pos
	p.pitch_scale = clampf(1.0 / sqrt(maxf(character_scale, 0.25)), 0.5, 1.35)
	p.pitch_scale *= _rng.randf_range(0.9, 1.1)
	p.volume_db = 0.5 + clampf((character_scale - 1.0) * 2.0, -2.0, 5.0)
	p.play()


## Stomp reuses the melee thump at a heavier pitch — same contact, bigger body.
func play_stomp(world_pos: Vector3, character_scale: float = 1.0) -> void:
	play_melee_hit(world_pos, maxf(character_scale, 1.0) * 1.35)
	## Layer a crunch so giants read as crushing pavement, not just a punch.
	play_laser_impact(world_pos, character_scale)


## Purple conversion orb leaving the caster's hand.
func play_orb_cast(world_pos: Vector3, character_scale: float = 1.0) -> void:
	if not enabled:
		return
	var stream := _pick(_orb_cast_streams)
	if stream == null:
		return
	var p := _next_monster_player()
	p.stream = stream
	p.global_position = world_pos
	p.pitch_scale = clampf(1.0 / sqrt(maxf(character_scale, 0.25)), 0.6, 1.4)
	p.pitch_scale *= _rng.randf_range(0.95, 1.08)
	p.volume_db = -1.5
	p.play()


## Orb hits a body, a wall, or burns out at range.
func play_orb_impact(world_pos: Vector3, character_scale: float = 1.0) -> void:
	if not enabled:
		return
	var stream := _pick(_orb_impact_streams)
	if stream == null:
		return
	var p := _next_monster_player()
	p.stream = stream
	p.global_position = world_pos
	p.pitch_scale = clampf(1.0 / sqrt(maxf(character_scale, 0.25)), 0.6, 1.35)
	p.pitch_scale *= _rng.randf_range(0.93, 1.1)
	p.volume_db = -0.5
	p.play()


## Hostile zoo turf biting a foot — short magical sizzle. Budgeted so a crowded
## forever-war tick does not turn into a wall of noise.
func play_zoo_plate_burn(world_pos: Vector3, character_scale: float = 1.0) -> void:
	if not enabled:
		return
	if _plate_burn_budget < 1.0:
		return
	_plate_burn_budget -= 1.0
	var stream := _pick(_zoo_plate_streams)
	if stream == null:
		return
	var p := _next_monster_player()
	p.stream = stream
	p.global_position = world_pos
	p.pitch_scale = clampf(1.05 / sqrt(maxf(character_scale, 0.25)), 0.65, 1.4)
	p.pitch_scale *= _rng.randf_range(0.9, 1.12)
	p.volume_db = -3.0
	p.play()


## Body starting to materialize under a summon gazebo — rising shimmer.
func play_zoo_summon_start(world_pos: Vector3, character_scale: float = 1.0) -> void:
	if not enabled:
		return
	var stream := _pick(_zoo_summon_start_streams)
	if stream == null:
		return
	var p := _next_monster_player()
	p.stream = stream
	p.global_position = world_pos
	p.pitch_scale = clampf(1.0 / sqrt(maxf(character_scale, 0.25)), 0.6, 1.35)
	p.pitch_scale *= _rng.randf_range(0.94, 1.06)
	p.volume_db = -1.0
	p.play()


## Materialize finished — soft solid thump as the ghost becomes a body.
func play_zoo_summon_ready(world_pos: Vector3, character_scale: float = 1.0) -> void:
	if not enabled:
		return
	var stream := _pick(_zoo_summon_ready_streams)
	if stream == null:
		return
	var p := _next_monster_player()
	p.stream = stream
	p.global_position = world_pos
	p.pitch_scale = clampf(1.0 / sqrt(maxf(character_scale, 0.25)), 0.55, 1.3)
	p.pitch_scale *= _rng.randf_range(0.92, 1.08)
	p.volume_db = -1.5
	p.play()


## Falling meteor scream — follows the body until impact / stop.
func play_meteor_whine(follow: Node3D) -> void:
	if not enabled or follow == null:
		return
	if _meteor_whine_stream == null:
		return
	_whine_follow = follow
	_whine_player.stream = _meteor_whine_stream
	_whine_player.global_position = follow.global_position
	_whine_player.pitch_scale = 0.9
	_whine_player.volume_db = -2.0
	_whine_player.play()


func stop_meteor_whine() -> void:
	_whine_follow = null
	if _whine_player != null and _whine_player.playing:
		_whine_player.stop()


## City-wide impact boom at the crater.
func play_meteor_crash(world_pos: Vector3) -> void:
	if not enabled:
		return
	if _meteor_crash_stream == null:
		return
	stop_meteor_whine()
	_crash_player.stream = _meteor_crash_stream
	_crash_player.global_position = world_pos
	_crash_player.pitch_scale = _rng.randf_range(0.92, 1.06)
	_crash_player.volume_db = 3.5
	_crash_player.play()


## Looping sick alien drone on an active spearhead tip.
func start_tendril_voice(tendril_id: int, world_pos: Vector3) -> void:
	if not enabled:
		return
	if _tendril_drone_stream == null:
		return
	if _tendril_voices.has(tendril_id):
		move_tendril_voice(tendril_id, world_pos)
		return
	if _tendril_voices.size() >= MAX_TENDRIL_VOICES:
		return
	var p := _make_dedicated_player("TendrilVoice_%d" % tendril_id, 55.0, 6.0)
	p.stream = _tendril_drone_stream
	p.global_position = world_pos
	p.pitch_scale = _rng.randf_range(0.88, 1.14)
	p.volume_db = -7.5
	p.play()
	_tendril_voices[tendril_id] = p


func move_tendril_voice(tendril_id: int, world_pos: Vector3) -> void:
	var p: Variant = _tendril_voices.get(tendril_id, null)
	if p is AudioStreamPlayer3D and is_instance_valid(p):
		(p as AudioStreamPlayer3D).global_position = world_pos


## Wet conversion click when a tip eats a voxel.
func play_tendril_transmute(world_pos: Vector3) -> void:
	if not enabled:
		return
	if _tendril_tick_stream == null:
		return
	var p := _next_player()
	p.stream = _tendril_tick_stream
	p.global_position = world_pos
	p.max_distance = 70.0
	p.unit_size = 5.0
	p.pitch_scale = _rng.randf_range(0.78, 1.22)
	p.volume_db = _rng.randf_range(-11.0, -6.0)
	p.play()


func stop_tendril_voice(tendril_id: int) -> void:
	var p: Variant = _tendril_voices.get(tendril_id, null)
	_tendril_voices.erase(tendril_id)
	if p is AudioStreamPlayer3D and is_instance_valid(p):
		var player := p as AudioStreamPlayer3D
		player.stop()
		player.queue_free()


func stop_all_tendril_voices() -> void:
	var ids: Array = _tendril_voices.keys()
	for tid in ids:
		stop_tendril_voice(int(tid))


func _stop_infection_sfx() -> void:
	stop_meteor_whine()
	if _crash_player != null and _crash_player.playing:
		_crash_player.stop()
	stop_charged_blast_charge()
	stop_all_tendril_voices()


func _make_dedicated_player(node_name: String, max_distance: float, unit_size: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = node_name
	p.max_distance = max_distance
	p.unit_size = unit_size
	p.max_db = 12.0
	p.bus = &"Master"
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(p)
	return p


func _next_player() -> AudioStreamPlayer3D:
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	## Close-range defaults (player footfalls, debris) — monster voices widen below.
	p.max_distance = LOCAL_SFX_MAX_DISTANCE
	p.unit_size = LOCAL_SFX_UNIT_SIZE
	p.max_db = 6.0
	p.attenuation_filter_cutoff_hz = 5000.0
	return p


## Combat / zoo one-shots: long carry so a district-scale fight stays audible.
func _next_monster_player() -> AudioStreamPlayer3D:
	var p := _next_player()
	p.max_distance = MONSTER_SFX_MAX_DISTANCE
	p.unit_size = MONSTER_SFX_UNIT_SIZE
	p.max_db = 10.0
	## Keep highs longer so distant hits still read as hits, not muffled dust.
	p.attenuation_filter_cutoff_hz = 14000.0
	return p


func _pick(bank: Array[AudioStream]) -> AudioStream:
	if bank.is_empty():
		return null
	return bank[_rng.randi_range(0, bank.size() - 1)]


func _play_ui(stream: AudioStream) -> void:
	## Toggle feedback plays even when SFX are off.
	if stream == null:
		return
	_ui_player.stream = stream
	_ui_player.volume_db = -8.0
	_ui_player.play()


func _load_banks() -> void:
	_foot_streams = _load_dir(FOOTSTEP_DIR, ["footstep_concrete_"])
	_debris_streams = _load_dir(DEBRIS_DIR, ["impactPlank_", "impactMining_", "impactGeneric_"])
	_laser_fire_streams = _load_dir(LASER_FIRE_DIR, ["laserLarge_"])
	_laser_impact_streams = _load_dir(LASER_FIRE_DIR, ["explosionCrunch_"])
	_blast_charge_streams = _load_dir(BLAST_DIR, ["blast_charge_"])
	_blast_throw_streams = _load_dir(BLAST_DIR, ["blast_throw_"])
	_blast_impact_streams = _load_dir(BLAST_DIR, ["blast_impact_"])
	## Explicit loads — DirAccess on res:// can miss newly added files until restart.
	_ensure_stream(_blast_charge_streams, "res://assets/audio/blast/blast_charge_ramp.wav")
	_ensure_stream(_blast_throw_streams, "res://assets/audio/blast/blast_throw_woosh.wav")
	_ensure_stream(_blast_impact_streams, "res://assets/audio/blast/blast_impact_close.wav")
	var ui := _load_dir(UI_DIR, ["switch_"])
	if ui.size() >= 2:
		_ui_on = ui[0]
		_ui_off = ui[1]
	elif ui.size() == 1:
		_ui_on = ui[0]
		_ui_off = ui[0]

	## Procedural fallbacks if packs failed to import / missing.
	if _foot_streams.is_empty():
		_foot_streams.append(_build_footstep())
	if _debris_streams.is_empty():
		_debris_streams.append(_build_debris())
	if _laser_fire_streams.is_empty():
		_laser_fire_streams.append(_build_laser_fire())
	if _laser_impact_streams.is_empty():
		_laser_impact_streams.append(_build_laser_impact())
	if _ui_on == null:
		_ui_on = _build_tone(880.0, 0.08, 0.35)
	if _ui_off == null:
		_ui_off = _build_tone(220.0, 0.08, 0.35)

	## Infection set is always procedural (no Kenney pack for this mood).
	_meteor_whine_stream = _build_meteor_whine()
	_meteor_crash_stream = _build_meteor_crash()
	_explosive_boom_stream = _build_explosive_boom()
	_dissolve_hiss_stream = _build_dissolve_hiss()
	_tendril_drone_stream = _build_tendril_drone()
	_tendril_tick_stream = _build_tendril_tick()
	_gem_pickup_stream = _build_gem_pickup()
	_chest_open_stream = _build_chest_open()
	_bling_stream = _build_treasure_bling()
	_go_stone_bling_stream = _build_go_stone_bling()
	_lock_on_stream = _build_lock_on()
	## Melee / orb — same: no pack for the mood, so synthesize a few variants.
	_melee_swing_streams = [_build_melee_swing(0), _build_melee_swing(1), _build_melee_swing(2)]
	_melee_hit_streams = [_build_melee_hit(0), _build_melee_hit(1), _build_melee_hit(2)]
	_orb_cast_streams = [_build_orb_cast(0), _build_orb_cast(1)]
	_orb_impact_streams = [_build_orb_impact(0), _build_orb_impact(1)]
	## Zoo turf / summon — procedural; no pack matches the magical pad bite.
	_zoo_plate_streams = [_build_zoo_plate_burn(0), _build_zoo_plate_burn(1), _build_zoo_plate_burn(2)]
	_zoo_summon_start_streams = [_build_zoo_summon_start(0), _build_zoo_summon_start(1)]
	_zoo_summon_ready_streams = [_build_zoo_summon_ready(0), _build_zoo_summon_ready(1)]


func _load_dir(dir_path: String, prefixes: Array[String]) -> Array[AudioStream]:
	var out: Array[AudioStream] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			var lower := name.to_lower()
			if lower.ends_with(".ogg") or lower.ends_with(".wav"):
				var ok := prefixes.is_empty()
				for prefix in prefixes:
					if name.begins_with(prefix):
						ok = true
						break
				if ok:
					var path := "%s/%s" % [dir_path, name]
					var res := load(path)
					if res is AudioStream:
						out.append(res as AudioStream)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a: AudioStream, b: AudioStream) -> bool:
		return String(a.resource_path) < String(b.resource_path)
	)
	return out


func _ensure_stream(bank: Array[AudioStream], path: String) -> void:
	for s in bank:
		if s != null and String(s.resource_path) == path:
			return
	var res := load(path)
	if res is AudioStream:
		bank.append(res as AudioStream)
	else:
		push_warning("CityAudio: failed to load blast stream %s" % path)


func _stream_length_sec(stream: AudioStream) -> float:
	if stream == null:
		return 1.0
	var len := stream.get_length()
	if len > 0.05:
		return len
	return 1.0


func _build_footstep() -> AudioStreamWAV:
	return _synthesize(0.11, func(t: float, _i: int) -> float:
		var env := exp(-t * 28.0)
		var thud := sin(TAU * 70.0 * t) * 0.55 + sin(TAU * 110.0 * t) * 0.25
		var grit := (_rng.randf() * 2.0 - 1.0) * 0.35 * exp(-t * 40.0)
		return (thud + grit) * env
	)


func _build_debris() -> AudioStreamWAV:
	return _synthesize(0.14, func(t: float, _i: int) -> float:
		var env := exp(-t * 22.0)
		var click := sin(TAU * 420.0 * t) * exp(-t * 55.0)
		var body := sin(TAU * 160.0 * t) * 0.45 + sin(TAU * 90.0 * t) * 0.3
		var noise := (_rng.randf() * 2.0 - 1.0) * 0.5 * exp(-t * 18.0)
		return (click * 0.7 + body + noise) * env
	)


func _build_laser_fire() -> AudioStreamWAV:
	return _synthesize(0.28, func(t: float, _i: int) -> float:
		var env := smoothstep(0.0, 0.04, t) * exp(-t * 4.5)
		var freq := 280.0 + 1400.0 * t
		var buzz := sin(TAU * freq * t) * 0.55
		var hum := sin(TAU * (freq * 0.5) * t) * 0.25
		var air := (_rng.randf() * 2.0 - 1.0) * 0.2 * env
		return (buzz + hum + air) * env
	)


func _build_laser_impact() -> AudioStreamWAV:
	return _synthesize(0.22, func(t: float, _i: int) -> float:
		var env := exp(-t * 14.0)
		var crack := sin(TAU * 900.0 * t) * exp(-t * 40.0)
		var boom := sin(TAU * 55.0 * t) * 0.7 + sin(TAU * 90.0 * t) * 0.35
		var noise := (_rng.randf() * 2.0 - 1.0) * 0.45 * exp(-t * 12.0)
		return (crack + boom + noise) * env
	)


func _build_meteor_whine() -> AudioStreamWAV:
	## Long metallic descending scream with dissonant beating.
	return _synthesize(3.2, func(t: float, _i: int) -> float:
		var fade_in := smoothstep(0.0, 0.18, t)
		var fade_out := 1.0 - smoothstep(2.6, 3.2, t)
		var env := fade_in * fade_out
		var prog := clampf(t / 3.2, 0.0, 1.0)
		var base_hz := lerpf(620.0, 140.0, prog * prog)
		var scream := sin(TAU * base_hz * t)
		var overtone := sin(TAU * base_hz * 1.97 * t + sin(TAU * 3.1 * t) * 0.7) * 0.55
		var beat := sin(TAU * (base_hz * 1.07) * t) * 0.4
		var grit := (_rng.randf() * 2.0 - 1.0) * 0.18 * (0.35 + prog)
		var sub := sin(TAU * (base_hz * 0.25) * t) * 0.35
		return (scream * 0.55 + overtone + beat + sub + grit) * env * 0.85
	)


func _build_meteor_crash() -> AudioStreamWAV:
	## Wide low boom + stone shatter — meant to carry across the district.
	return _synthesize(1.45, func(t: float, _i: int) -> float:
		var env := exp(-t * 2.8) * smoothstep(0.0, 0.02, t)
		var boom := sin(TAU * 38.0 * t) * 0.85 + sin(TAU * 62.0 * t) * 0.45
		var slab := sin(TAU * 95.0 * t) * exp(-t * 6.0) * 0.55
		var crack := sin(TAU * 780.0 * t) * exp(-t * 28.0)
		var rubble := (_rng.randf() * 2.0 - 1.0) * 0.7 * exp(-t * 4.5)
		var rumble := sin(TAU * 22.0 * t + sin(TAU * 7.0 * t)) * 0.4 * exp(-t * 1.6)
		return (boom + slab + crack * 0.65 + rubble + rumble) * env
	)


func _build_explosive_boom() -> AudioStreamWAV:
	## Material detonation — deep pressure thump, glass snap, short ringing tail.
	return _synthesize(1.15, func(t: float, _i: int) -> float:
		var env := exp(-t * 3.1) * smoothstep(0.0, 0.015, t)
		var boom := sin(TAU * 42.0 * t) * 0.9 + sin(TAU * 68.0 * t) * 0.5
		var pressure := sin(TAU * 28.0 * t) * 0.55 * exp(-t * 2.2)
		var glass := sin(TAU * 1400.0 * t) * exp(-t * 36.0) * 0.45
		var crack := sin(TAU * 620.0 * t) * exp(-t * 22.0) * 0.55
		var grit := (_rng.randf() * 2.0 - 1.0) * 0.55 * exp(-t * 5.5)
		var ring := sin(TAU * 210.0 * t) * exp(-t * 4.0) * 0.28
		return (boom + pressure + glass + crack + grit + ring) * env
	)


func _build_dissolve_hiss() -> AudioStreamWAV:
	## Dissolve cascade — glass crack, then a rolling crystalline unravel with a thin red-energy
	## sheen. Long enough to ride a whole cage's infection waves; no boom, no rubble thud.
	return _synthesize(1.45, func(t: float, _i: int) -> float:
		## Fast attack, slow burn, soft release so the last cells still have a tail.
		var env := smoothstep(0.0, 0.012, t) * exp(-t * 1.55) * (1.0 - smoothstep(1.15, 1.45, t))
		## Opening snap — brittle pane giving way.
		var crack := (
			sin(TAU * 1850.0 * t) * exp(-t * 42.0) * 0.7
			+ sin(TAU * 2650.0 * t) * exp(-t * 55.0) * 0.45
		)
		## Cascading shimmer: chirps that tumble downward as cells infect outwards.
		var tumble_hz := lerpf(1600.0, 420.0, clampf(t / 1.1, 0.0, 1.0))
		var shimmer := (
			sin(TAU * tumble_hz * t + sin(TAU * 9.0 * t) * 2.2) * 0.55
			+ sin(TAU * tumble_hz * 1.47 * t) * 0.32
		) * exp(-t * 1.8)
		## Soft grit of fabric unweaving — denser early, thins as the cage opens.
		var grit := (_rng.randf() * 2.0 - 1.0) * 0.38 * exp(-t * 3.2)
		## Thin energy bed under the glass (reads as the red containment line dying).
		var energy := (
			sin(TAU * 210.0 * t) * 0.28
			+ sin(TAU * 315.0 * t + sin(TAU * 6.5 * t)) * 0.22
		) * exp(-t * 2.0)
		## Late whisper of settling air — the hole left behind.
		var air := sin(TAU * 90.0 * t) * 0.12 * smoothstep(0.35, 0.9, t) * exp(-t * 1.2)
		return (crack + shimmer + grit + energy + air) * env
	)


func _build_tendril_drone() -> AudioStreamWAV:
	## Looping wet alien horror bed for active spearheads.
	var stream := _synthesize(1.85, func(t: float, i: int) -> float:
		var wobble := sin(TAU * 0.55 * t)
		var a := sin(TAU * 73.0 * t + wobble * 1.8)
		var b := sin(TAU * 97.5 * t - wobble * 2.4) * 0.7
		var c := sin(TAU * 141.0 * t + sin(TAU * 2.3 * t) * 3.0) * 0.45
		var wet := sin(TAU * 210.0 * t) * sin(TAU * 5.5 * t) * 0.35
		var breath := sin(TAU * 1.7 * t) * 0.5 + 0.5
		var hiss := (_rng.randf() * 2.0 - 1.0) * 0.22 * breath
		## Soft loop seam — duck near ends so LOOP_FORWARD isn't clicky.
		var seam := 1.0
		if t < 0.06:
			seam = smoothstep(0.0, 0.06, t)
		elif t > 1.79:
			seam = 1.0 - smoothstep(1.79, 1.85, t)
		var pulse := 0.65 + 0.35 * sin(TAU * 2.8 * t + float(i % 17) * 0.1)
		return (a * 0.4 + b * 0.35 + c + wet + hiss) * seam * pulse * 0.7
	)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(1.85 * 22050.0)
	return stream


func _build_tendril_tick() -> AudioStreamWAV:
	## Short sick conversion spit when a voxel is eaten.
	return _synthesize(0.16, func(t: float, _i: int) -> float:
		var env := exp(-t * 18.0) * smoothstep(0.0, 0.01, t)
		var squelch := sin(TAU * lerpf(340.0, 90.0, t / 0.16) * t)
		var chirp := sin(TAU * lerpf(880.0, 220.0, clampf(t / 0.08, 0.0, 1.0)) * t) * exp(-t * 30.0)
		var wet := (_rng.randf() * 2.0 - 1.0) * 0.55 * exp(-t * 14.0)
		return (squelch * 0.45 + chirp * 0.55 + wet) * env
	)


func _gem_pickup_pitch(mat_id: int) -> float:
	## Quartz → diamond: roughly a major sixth climb.
	match mat_id:
		VoxelMaterial.GEM_QUARTZ:
			return 0.92
		VoxelMaterial.GEM_AMBER:
			return 1.0
		VoxelMaterial.GEM_TOPAZ:
			return 1.08
		VoxelMaterial.GEM_SAPPHIRE:
			return 1.18
		VoxelMaterial.GEM_EMERALD:
			return 1.28
		VoxelMaterial.GEM_DIAMOND:
			return 1.4
		_:
			return 1.0


func _build_gem_pickup() -> AudioStreamWAV:
	## Short sparkly arpeggio: fundamental + fifth + octave, with a bright ping attack.
	return _synthesize(0.28, func(t: float, _i: int) -> float:
		var attack := smoothstep(0.0, 0.008, t)
		var env := attack * exp(-t * 14.0)
		var ping := sin(TAU * 1760.0 * t) * exp(-t * 55.0)
		var root := sin(TAU * 880.0 * t)
		var fifth := sin(TAU * 1320.0 * t) * 0.7
		var octave := sin(TAU * 1760.0 * t) * 0.45
		var shimmer := sin(TAU * 2340.0 * t + sin(TAU * 40.0 * t) * 0.4) * 0.28 * exp(-t * 20.0)
		return (ping * 0.85 + root * 0.55 + fifth + octave + shimmer) * env * 0.7
	)


func _build_chest_open() -> AudioStreamWAV:
	## A latch knocking loose, then the lid creaking up: a wobbling scrape that climbs as it swings,
	## over a short wooden thump. Kept dry and low so it reads as furniture, not as a chime.
	return _synthesize(0.42, func(t: float, _i: int) -> float:
		var knock := sin(TAU * 168.0 * t) * exp(-t * 44.0) * 0.7
		var body := sin(TAU * 94.0 * t) * exp(-t * 24.0) * 0.45
		var creak_env := smoothstep(0.03, 0.10, t) * (1.0 - smoothstep(0.24, 0.40, t))
		var creak_hz := lerpf(430.0, 720.0, clampf((t - 0.03) / 0.28, 0.0, 1.0))
		var creak := sin(TAU * creak_hz * t + sin(TAU * 26.0 * t) * 1.6) * 0.34 * creak_env
		var grain := (_rng.randf() * 2.0 - 1.0) * 0.14 * creak_env
		return (knock + body + creak + grain) * 0.8
	)


func _build_treasure_bling() -> AudioStreamWAV:
	## Four notes up a major triad with a shimmer tail — deliberately longer and brighter than the
	## single-nugget chime, so a haul does not sound like one more pebble off a wall.
	var notes := PackedFloat32Array([1046.5, 1318.5, 1568.0, 2093.0])
	return _synthesize(0.75, func(t: float, _i: int) -> float:
		var sum := 0.0
		for n in range(notes.size()):
			var start := float(n) * 0.075
			if t < start:
				break
			var lt := t - start
			var env := smoothstep(0.0, 0.006, lt) * exp(-lt * 7.5)
			sum += sin(TAU * notes[n] * lt) * env * 0.5
			sum += sin(TAU * notes[n] * 2.0 * lt) * env * 0.15
		var shimmer_env := smoothstep(0.0, 0.05, t) * exp(-t * 4.0)
		var shimmer := sin(TAU * 3140.0 * t + sin(TAU * 33.0 * t) * 1.4) * 0.13 * shimmer_env
		return (sum + shimmer) * 0.6
	)


func _build_go_stone_bling() -> AudioStreamWAV:
	## Glass Yunzi on kaya: a wooden contact clack, then inharmonic high rings that die fast.
	## Real stones are bright and dry — not a musical chime and not a rubble tick.
	## Partials sit off integer ratios so the ring reads as glass rather than a bell.
	var rings := PackedFloat32Array([2480.0, 3170.0, 4020.0, 5310.0, 6840.0])
	var ring_w := PackedFloat32Array([0.55, 0.42, 0.28, 0.18, 0.10])
	var ring_d := PackedFloat32Array([18.0, 22.0, 28.0, 34.0, 42.0])
	return _synthesize(0.28, func(t: float, _i: int) -> float:
		## Contact: hard wood knock + a few milliseconds of grit for the tip strike.
		var knock_env := smoothstep(0.0, 0.0015, t) * exp(-t * 55.0)
		var knock := (
			sin(TAU * 620.0 * t) * 0.55
			+ sin(TAU * 980.0 * t) * 0.35
			+ sin(TAU * 1480.0 * t) * 0.2
		) * knock_env
		var tip := (_rng.randf() * 2.0 - 1.0) * 0.55 * exp(-t * 140.0)

		## Glass body: bright partials with a tiny FM shimmer so it sings, briefly.
		var glass := 0.0
		for n in range(rings.size()):
			var env := smoothstep(0.0, 0.0025, t) * exp(-t * ring_d[n])
			var fm := sin(TAU * 27.0 * t) * (0.4 + float(n) * 0.15)
			glass += sin(TAU * rings[n] * t + fm) * env * ring_w[n]

		## Quiet board undertone — the goban answering, not a boom.
		var wood := sin(TAU * 240.0 * t) * 0.12 * exp(-t * 30.0)
		return (knock * 0.9 + tip * 0.45 + glass * 0.85 + wood) * 0.78
	)


func _build_lock_on() -> AudioStreamWAV:
	## Two tight rising pips — "target acquired" without sounding like a gem haul.
	return _synthesize(0.22, func(t: float, _i: int) -> float:
		var a_env := smoothstep(0.0, 0.008, t) * exp(-t * 28.0)
		var a := sin(TAU * 920.0 * t) * a_env
		var b_t := t - 0.055
		var b_env := 0.0
		if b_t > 0.0:
			b_env = smoothstep(0.0, 0.006, b_t) * exp(-b_t * 18.0)
		var b := sin(TAU * 1380.0 * b_t) * b_env
		var buzz := sin(TAU * 2200.0 * t) * 0.18 * a_env
		return (a * 0.7 + b * 0.85 + buzz) * 0.75
	)


func _build_melee_swing(variant: int) -> AudioStreamWAV:
	## Cloth / claw whoosh — band of noise with a quick rising then falling centre.
	var bias := 1.0 + float(variant) * 0.12
	return _synthesize(0.16, func(t: float, _i: int) -> float:
		var env := smoothstep(0.0, 0.02, t) * (1.0 - smoothstep(0.08, 0.16, t))
		var centre := lerpf(180.0, 520.0, clampf(t / 0.07, 0.0, 1.0)) * bias
		var tone := sin(TAU * centre * t) * 0.35
		var air := (_rng.randf() * 2.0 - 1.0) * 0.75 * env
		var flutter := sin(TAU * 40.0 * t) * 0.2
		return (tone + air + flutter) * env * 0.85
	)


func _build_melee_hit(variant: int) -> AudioStreamWAV:
	## Meat / bone thud with a short crack. Variant shifts the body tone.
	var body_hz := 70.0 + float(variant) * 18.0
	return _synthesize(0.2, func(t: float, _i: int) -> float:
		var env := exp(-t * 16.0) * smoothstep(0.0, 0.008, t)
		var thud := sin(TAU * body_hz * t) * 0.8 + sin(TAU * (body_hz * 1.7) * t) * 0.35
		var crack := sin(TAU * 780.0 * t) * exp(-t * 42.0)
		var slap := (_rng.randf() * 2.0 - 1.0) * 0.55 * exp(-t * 28.0)
		return (thud + crack * 0.7 + slap) * env
	)


func _build_orb_cast(variant: int) -> AudioStreamWAV:
	## Rising magical spit — dissonant pair that climbs as it leaves the hand.
	var start := 220.0 + float(variant) * 40.0
	return _synthesize(0.32, func(t: float, _i: int) -> float:
		var env := smoothstep(0.0, 0.04, t) * (1.0 - smoothstep(0.22, 0.32, t))
		var prog := clampf(t / 0.32, 0.0, 1.0)
		var hz := lerpf(start, start * 2.4, prog * prog)
		var a := sin(TAU * hz * t)
		var b := sin(TAU * hz * 1.37 * t + 0.6) * 0.55
		var swirl := sin(TAU * 9.0 * t) * 0.25
		var hiss := (_rng.randf() * 2.0 - 1.0) * 0.2 * env
		return (a * 0.55 + b + swirl + hiss) * env * 0.8
	)


func _build_orb_impact(variant: int) -> AudioStreamWAV:
	## Wet purple pop — low boom under a bright conversion spark.
	var spark := 640.0 + float(variant) * 90.0
	return _synthesize(0.24, func(t: float, _i: int) -> float:
		var env := exp(-t * 12.0) * smoothstep(0.0, 0.01, t)
		var boom := sin(TAU * 55.0 * t) * 0.65 + sin(TAU * 88.0 * t) * 0.35
		var zap := sin(TAU * spark * t) * exp(-t * 30.0)
		var fizz := (_rng.randf() * 2.0 - 1.0) * 0.45 * exp(-t * 16.0)
		return (boom + zap * 0.8 + fizz) * env
	)


func _build_zoo_plate_burn(variant: int) -> AudioStreamWAV:
	## Hostile turf bite — short electric sizzle with a glassy sting.
	var sting := 920.0 + float(variant) * 110.0
	return _synthesize(0.2, func(t: float, _i: int) -> float:
		var env := smoothstep(0.0, 0.012, t) * exp(-t * 14.0)
		var buzz := sin(TAU * 180.0 * t) * 0.4 + sin(TAU * 270.0 * t) * 0.25
		var glass := sin(TAU * sting * t + sin(TAU * 40.0 * t) * 1.2) * exp(-t * 18.0)
		var hiss := (_rng.randf() * 2.0 - 1.0) * 0.55 * exp(-t * 12.0)
		return (buzz + glass * 0.85 + hiss) * env * 0.9
	)


func _build_zoo_summon_start(variant: int) -> AudioStreamWAV:
	## Rising ward shimmer while the body materializes (~covers the first beat of fade-in).
	var base := 160.0 + float(variant) * 28.0
	return _synthesize(1.35, func(t: float, _i: int) -> float:
		var env := smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(1.0, 1.35, t))
		var prog := clampf(t / 1.35, 0.0, 1.0)
		var hz := lerpf(base, base * 2.8, prog * prog)
		var a := sin(TAU * hz * t) * 0.45
		var b := sin(TAU * hz * 1.5 * t + 0.4) * 0.35
		var swirl := sin(TAU * (7.0 + prog * 11.0) * t) * 0.2
		var sparkle := sin(TAU * (1400.0 + prog * 900.0) * t) * 0.12 * env
		var air := (_rng.randf() * 2.0 - 1.0) * 0.12 * env
		return (a + b + swirl + sparkle + air) * env * 0.75
	)


func _build_zoo_summon_ready(variant: int) -> AudioStreamWAV:
	## Soft solidify thump — body lands in the world.
	var body_hz := 62.0 + float(variant) * 14.0
	return _synthesize(0.28, func(t: float, _i: int) -> float:
		var env := exp(-t * 11.0) * smoothstep(0.0, 0.01, t)
		var thud := sin(TAU * body_hz * t) * 0.75 + sin(TAU * (body_hz * 1.6) * t) * 0.3
		var chime := sin(TAU * 520.0 * t) * exp(-t * 22.0) * 0.55
		var grit := (_rng.randf() * 2.0 - 1.0) * 0.25 * exp(-t * 20.0)
		return (thud + chime + grit) * env
	)


func _build_tone(hz: float, duration: float, volume: float) -> AudioStreamWAV:
	return _synthesize(duration, func(t: float, _i: int) -> float:
		var env := exp(-t * 18.0)
		return sin(TAU * hz * t) * volume * env
	)


func _synthesize(duration: float, sample_fn: Callable) -> AudioStreamWAV:
	var rate := 22050
	var n := int(duration * float(rate))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / float(rate)
		var v: float = float(sample_fn.call(t, i))
		var s := int(clampf(v, -1.0, 1.0) * 32767.0)
		data[i * 2] = s & 0xFF
		data[i * 2 + 1] = (s >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream
