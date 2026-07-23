## Shared Quaternius Idle/Walk library for player + crowd near-LOD visuals.
class_name QuaterniusLocomotion
extends RefCounted

const LIB_PATH := "res://assets/humans/animations/quaternius/AnimationLibrary_Godot_Standard.gltf"
const ANIM_IDLE := &"Idle"
const ANIM_WALK := &"Walk"
const LIB_NAME := &"quat"

static var _cached_library: AnimationLibrary


static func get_library() -> AnimationLibrary:
	if _cached_library != null:
		return _cached_library
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
	for anim_name in [String(ANIM_IDLE), String(ANIM_WALK)]:
		if not src.has_animation(anim_name):
			push_error("QuaterniusLocomotion: missing '%s'" % anim_name)
			continue
		var copy: Animation = src.get_animation(anim_name).duplicate(true) as Animation
		_prepare_locomotion_clip(copy)
		library.add_animation(anim_name, copy)
	root.free()
	_cached_library = library
	return _cached_library


static func attach_to(player: AnimationPlayer) -> void:
	var library := get_library()
	if library == null or player == null:
		return
	if player.has_animation_library(String(LIB_NAME)):
		player.remove_animation_library(String(LIB_NAME))
	player.add_animation_library(String(LIB_NAME), library)
	player.play("%s/%s" % [LIB_NAME, ANIM_IDLE])


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


static func _prepare_locomotion_clip(anim: Animation) -> void:
	anim.loop_mode = Animation.LOOP_LINEAR
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
