## Shared Quaternius Idle/Walk/Run/Driving library for player, crowd, and vehicle passengers.
class_name QuaterniusLocomotion
extends RefCounted

const LIB_PATH := "res://assets/humans/animations/quaternius/AnimationLibrary_Godot_Standard.gltf"
const ANIM_IDLE := &"Idle"
const ANIM_WALK := &"Walk"
const ANIM_RUN := &"Sprint"
const ANIM_DEATH := &"Death01"
const ANIM_DRIVING := &"Driving"
const ANIM_SITTING := &"Sitting_Idle"
const LIB_NAME := &"quat"

static var _cached_library: AnimationLibrary
static var _cached_passenger_library: AnimationLibrary
static var _library_built: bool = false


static func get_library() -> AnimationLibrary:
	## Build at most once. Never tear down the cache mid-frame — that reloaded the
	## full Quaternius GLTF for every fleeing ped and tanked FPS to single digits.
	if _library_built:
		return _cached_library
	_library_built = true
	_cached_library = _build_library(
		[String(ANIM_IDLE), String(ANIM_WALK), String(ANIM_RUN), String(ANIM_DEATH)],
		{String(ANIM_DEATH): Animation.LOOP_NONE}
	)
	return _cached_library


static func get_passenger_library() -> AnimationLibrary:
	if _cached_passenger_library != null:
		return _cached_passenger_library
	_cached_passenger_library = _build_library(
		[String(ANIM_DRIVING), String(ANIM_SITTING), String(ANIM_IDLE)]
	)
	return _cached_passenger_library


static func attach_to(player: AnimationPlayer) -> void:
	_attach_library(player, get_library(), ANIM_IDLE)


static func attach_passenger(player: AnimationPlayer) -> void:
	var lib := get_passenger_library()
	if lib == null or player == null:
		return
	_attach_library(player, lib, ANIM_DRIVING if lib.has_animation(String(ANIM_DRIVING)) else ANIM_SITTING)


static func play_idle(player: AnimationPlayer) -> void:
	if player == null:
		return
	var path := "%s/%s" % [LIB_NAME, ANIM_IDLE]
	if player.current_animation != path:
		player.play(path, 0.25)
	player.speed_scale = 1.0


static func play_walk(player: AnimationPlayer, speed: float, reference_speed: float = 1.4) -> void:
	if player == null:
		return
	var path := "%s/%s" % [LIB_NAME, ANIM_WALK]
	if player.current_animation != path:
		player.play(path, 0.2)
	player.speed_scale = clampf(speed / reference_speed, 0.5, 2.2)


static func play_run(player: AnimationPlayer, speed: float, reference_speed: float = 4.2) -> void:
	if player == null:
		return
	var run_path := "%s/%s" % [LIB_NAME, ANIM_RUN]
	if player.has_animation(run_path):
		if player.current_animation != run_path:
			player.play(run_path, 0.12)
		player.speed_scale = clampf(speed / reference_speed, 0.7, 2.4)
		return
	## No Sprint on this player — speed up Walk (never reload assets here).
	play_walk(player, speed, 1.4)


static func play_death(player: AnimationPlayer) -> void:
	if player == null:
		return
	var path := "%s/%s" % [LIB_NAME, ANIM_DEATH]
	if not player.has_animation(path):
		push_error("QuaterniusLocomotion: Death01 missing on AnimationPlayer")
		return
	player.play(path, 0.08)
	player.speed_scale = 1.0


static func is_death_playing(player: AnimationPlayer) -> bool:
	if player == null:
		return false
	return player.current_animation == "%s/%s" % [LIB_NAME, ANIM_DEATH]


static func play_driving(player: AnimationPlayer) -> void:
	if player == null:
		return
	var drive := "%s/%s" % [LIB_NAME, ANIM_DRIVING]
	var sit := "%s/%s" % [LIB_NAME, ANIM_SITTING]
	if player.has_animation(drive):
		if player.current_animation != drive:
			player.play(drive, 0.15)
	elif player.has_animation(sit):
		if player.current_animation != sit:
			player.play(sit, 0.15)
	player.speed_scale = 1.0


static func _attach_library(player: AnimationPlayer, library: AnimationLibrary, start: StringName) -> void:
	if library == null or player == null:
		return
	if player.has_animation_library(String(LIB_NAME)):
		player.remove_animation_library(String(LIB_NAME))
	player.add_animation_library(String(LIB_NAME), library)
	var path := "%s/%s" % [LIB_NAME, start]
	if player.has_animation(path):
		player.play(path)
	elif library.get_animation_list().size() > 0:
		player.play("%s/%s" % [LIB_NAME, library.get_animation_list()[0]])


static func _build_library(
	anim_names: Array[String],
	loop_overrides: Dictionary = {}
) -> AnimationLibrary:
	if not ResourceLoader.exists(LIB_PATH):
		push_error("QuaterniusLocomotion: missing %s" % LIB_PATH)
		return null
	var packed := load(LIB_PATH)
	if not (packed is PackedScene):
		push_error("QuaterniusLocomotion: library is not a PackedScene")
		return null
	var root: Node = (packed as PackedScene).instantiate()
	var src := _find_animation_player(root)
	if src == null:
		root.free()
		push_error("QuaterniusLocomotion: no AnimationPlayer in library")
		return null
	var library := AnimationLibrary.new()
	for anim_name in anim_names:
		if not src.has_animation(anim_name):
			push_warning("QuaterniusLocomotion: missing '%s'" % anim_name)
			continue
		var copy: Animation = src.get_animation(anim_name).duplicate(true) as Animation
		var loop_mode := Animation.LOOP_LINEAR
		if loop_overrides.has(anim_name):
			loop_mode = int(loop_overrides[anim_name])
		_prepare_locomotion_clip(copy, loop_mode)
		library.add_animation(anim_name, copy)
	root.free()
	return library


static func _prepare_locomotion_clip(anim: Animation, loop_mode: int = Animation.LOOP_LINEAR) -> void:
	anim.loop_mode = loop_mode
	for i in range(anim.get_track_count() - 1, -1, -1):
		var path := str(anim.track_get_path(i))
		var typ := anim.track_get_type(i)
		if typ == Animation.TYPE_POSITION_3D and path.ends_with(":Root"):
			anim.remove_track(i)


static func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
