## City SFX. Off by default; toggle with O.
## Prefers Kenney CC0 clips under res://assets/audio/; procedural fallback if missing.
class_name CityAudio
extends Node

const GROUP_NAME := &"city_audio"
const POOL_SIZE := 12
const MAX_DEBRIS_PER_SEC := 14.0
const MAX_TENDRIL_VOICES := 10

const FOOTSTEP_DIR := "res://assets/audio/footstep"
const DEBRIS_DIR := "res://assets/audio/debris"
const LASER_FIRE_DIR := "res://assets/audio/laser"
const UI_DIR := "res://assets/audio/ui"

var enabled: bool = false

var _foot_streams: Array[AudioStream] = []
var _debris_streams: Array[AudioStream] = []
var _laser_fire_streams: Array[AudioStream] = []
var _laser_impact_streams: Array[AudioStream] = []
var _ui_on: AudioStream
var _ui_off: AudioStream
var _meteor_whine_stream: AudioStream
var _meteor_crash_stream: AudioStream
var _tendril_drone_stream: AudioStream
var _tendril_tick_stream: AudioStream

var _pool: Array[AudioStreamPlayer3D] = []
var _pool_i: int = 0
var _rng := RandomNumberGenerator.new()
var _debris_budget: float = 0.0
var _ui_player: AudioStreamPlayer
var _whine_player: AudioStreamPlayer3D
var _whine_follow: Node3D
var _crash_player: AudioStreamPlayer3D
var _tendril_voices: Dictionary = {}  # tendril_id → AudioStreamPlayer3D


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_rng.randomize()
	_load_banks()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.name = "Sfx_%d" % i
		p.max_distance = 80.0
		p.unit_size = 4.0
		p.bus = &"Master"
		add_child(p)
		_pool.append(p)
	_ui_player = AudioStreamPlayer.new()
	_ui_player.name = "UiSfx"
	_ui_player.bus = &"Master"
	add_child(_ui_player)
	_whine_player = _make_dedicated_player("MeteorWhine", 420.0, 18.0)
	_crash_player = _make_dedicated_player("MeteorCrash", 720.0, 42.0)
	_crash_player.attenuation_filter_cutoff_hz = 5000.0


func _process(delta: float) -> void:
	_debris_budget = minf(_debris_budget + MAX_DEBRIS_PER_SEC * delta, MAX_DEBRIS_PER_SEC)
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


func play_laser_fire(world_pos: Vector3, character_scale: float = 1.0) -> void:
	if not enabled:
		return
	var stream := _pick(_laser_fire_streams)
	if stream == null:
		return
	var p := _next_player()
	p.stream = stream
	p.global_position = world_pos
	p.pitch_scale = clampf(1.0 / sqrt(maxf(character_scale, 0.25)), 0.55, 1.35)
	p.volume_db = -5.0
	p.play()


func play_laser_impact(world_pos: Vector3, character_scale: float = 1.0) -> void:
	if not enabled:
		return
	var stream := _pick(_laser_impact_streams)
	if stream == null:
		return
	var p := _next_player()
	p.stream = stream
	p.global_position = world_pos
	p.pitch_scale = clampf(1.0 / sqrt(maxf(character_scale, 0.25)), 0.55, 1.3)
	p.volume_db = -3.0
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
	stop_all_tendril_voices()


func _make_dedicated_player(node_name: String, max_distance: float, unit_size: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = node_name
	p.max_distance = max_distance
	p.unit_size = unit_size
	p.bus = &"Master"
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(p)
	return p


func _next_player() -> AudioStreamPlayer3D:
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	## Reset pool defaults in case a one-shot temporarily widened range.
	p.max_distance = 80.0
	p.unit_size = 4.0
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
	_tendril_drone_stream = _build_tendril_drone()
	_tendril_tick_stream = _build_tendril_tick()


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
