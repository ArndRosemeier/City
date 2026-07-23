## City SFX. Off by default; toggle with O.
## Prefers Kenney CC0 clips under res://assets/audio/; procedural fallback if missing.
class_name CityAudio
extends Node

const GROUP_NAME := &"city_audio"
const POOL_SIZE := 12
const MAX_DEBRIS_PER_SEC := 14.0

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

var _pool: Array[AudioStreamPlayer3D] = []
var _pool_i: int = 0
var _rng := RandomNumberGenerator.new()
var _debris_budget: float = 0.0
var _ui_player: AudioStreamPlayer


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


func _process(delta: float) -> void:
	_debris_budget = minf(_debris_budget + MAX_DEBRIS_PER_SEC * delta, MAX_DEBRIS_PER_SEC)


func toggle() -> bool:
	enabled = not enabled
	if enabled:
		_play_ui(_ui_on)
	else:
		_play_ui(_ui_off)
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


func _next_player() -> AudioStreamPlayer3D:
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
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
