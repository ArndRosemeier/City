## Third-person city walker: MH body + Quaternius Idle/Walk (humanoid retarget).
class_name CityWalker
extends CharacterBody3D

signal blast_requested(hit_position: Vector3, collider: Object, radius_m: float)

const CharacterEditorScript := preload("res://scripts/city/character_editor.gd")
const ProportionModifierScript := preload("res://scripts/humans/proportion_modifier.gd")
const BodyProportionsScript := preload("res://scripts/humans/body_proportions.gd")

const PedOutfitCatalogScript := preload("res://scripts/humans/ped_outfit_catalog.gd")
const PedOutfitApplierScript := preload("res://scripts/humans/ped_outfit_applier.gd")

const MALE_PATHS: Array[String] = [
	"res://assets/humans/male_base.gltf",
	"res://assets/humans/male_base.glb",
]
const FEMALE_PATHS: Array[String] = [
	"res://assets/humans/female_base.gltf",
	"res://assets/humans/female_base.glb",
]
const QUATERNIUS_LIB := (
	"res://assets/humans/animations/quaternius/AnimationLibrary_Godot_Standard.gltf"
)
const MIXAMO_LIB := "res://assets/humans/animations/mixamo/mixamo_actions.tres"
const ANIM_IDLE := &"Idle"
const ANIM_WALK := &"Walk"
const LIB_NAME := &"quat"

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var jump_velocity: float = 6.8
@export var mouse_sensitivity: float = 0.0022
@export var turn_speed: float = 10.0
@export var blast_range: float = 80.0
## Dig sphere radius in meters at character_scale 1.0 (intentionally mild).
@export var dig_radius_at_scale_1: float = 1.45
@export var pivot_height: float = 1.35
@export var zoom_min: float = 1.8
@export var zoom_max: float = 12.0
@export var zoom_step: float = 0.55
@export var zoom_default: float = 4.2
## Walk clip is authored near ~1.4 m/s; scale playback to match move speed.
@export var walk_anim_reference_speed: float = 1.4
@export var character_scale: float = 1.0
## Multiplicative +/- step (wide 0.1×…20× range).
@export var scale_factor_step: float = 1.15
@export var scale_min: float = 0.1
@export var scale_max: float = 20.0
## Auto-step onto curbs / low ledges (meters at scale 1).
@export var max_step_height: float = 0.38
@export var coyote_time_sec: float = 0.12

var _yaw: float = 0.0
var _pitch: float = -0.35
var _zoom: float = 4.2
var _camera: Camera3D
var _spring: SpringArm3D
var _pivot: Node3D
var _capsule: CollisionShape3D
var _captured: bool = false
var _body_root: Node3D
var _skeleton: Skeleton3D
var _mesh: MeshInstance3D
var _anim_player: AnimationPlayer
var _prop_mod: SkeletonModifier3D
var _proportions: BodyProportions = BodyProportions.identity()
var _female: bool = false
var _outfit: PedOutfit
var _editor: CanvasLayer
var _moving: bool = false
var _body_base_y: float = 0.0
var _feet_aligned: bool = false
var _rng := RandomNumberGenerator.new()
var _jump_queued: bool = false
var _coyote_left: float = 0.0
var _safety_deck: StaticBody3D
## Hold forward without pressing W (toggle with R).
var _auto_run: bool = false
## Matches district surface top: (ground_thickness+1) * 0.5 m.
const SAFETY_FLOOR_TOP_Y := 1.0
## One-shot / emote override from the action bar; blocks Idle/Walk until done.
var _action_playing: bool = false
var _action_anim: String = ""
var _action_names: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_rng.randomize()
	_zoom = zoom_default
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(55.0)
	safe_margin = 0.06

	_capsule = CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.7
	_capsule.shape = shape
	_capsule.position.y = 0.95
	add_child(_capsule)

	## Always-on safety deck under the player — catches Forget/remesh holes.
	_ensure_safety_deck()

	_female = _rng.randf() < 0.5
	_proportions = BodyProportions.identity()
	_outfit = PedOutfitCatalogScript.pick(_rng, _female)
	_spawn_human(_female)

	_pivot = Node3D.new()
	_pivot.name = "CameraPivot"
	_pivot.position = Vector3(0.0, pivot_height * character_scale, 0.0)
	add_child(_pivot)

	_spring = SpringArm3D.new()
	_spring.name = "SpringArm"
	_spring.spring_length = _zoom
	_spring.margin = 0.2
	_spring.collision_mask = 1
	_pivot.add_child(_spring)

	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = 70.0
	_camera.near = 0.08
	_camera.far = 280.0
	_camera.current = true
	_spring.add_child(_camera)

	_editor = CharacterEditorScript.new()
	_editor.name = "CharacterEditor"
	add_child(_editor)
	_editor.proportions_changed.connect(_on_editor_proportions)
	_editor.sex_change_requested.connect(_on_editor_sex)
	_editor.closed.connect(_on_editor_closed)

	_apply_camera_angles()
	_set_capture(true)


func _spawn_human(female: bool) -> void:
	_clear_body()
	_female = female
	if _outfit == null or _outfit.female != female:
		_outfit = PedOutfitCatalogScript.pick(_rng, female)
	var path := ""
	if _outfit != null and _outfit.scene_path != "" and ResourceLoader.exists(_outfit.scene_path):
		path = _outfit.scene_path
	else:
		var paths := FEMALE_PATHS if female else MALE_PATHS
		for candidate in paths:
			if ResourceLoader.exists(candidate):
				path = candidate
				break
	if path == "":
		push_error("CityWalker: missing human glTF")
		_spawn_fallback_body(female)
		_apply_proportions()
		return

	var packed := load(path)
	if not (packed is PackedScene):
		push_error("CityWalker: %s is not a PackedScene" % path)
		_spawn_fallback_body(female)
		_apply_proportions()
		return

	var instance := (packed as PackedScene).instantiate() as Node3D
	instance.name = "Body"
	# MakeHuman/glTF faces +Z; CharacterBody3D walk forward is -Z.
	instance.rotation.y = PI
	add_child(instance)
	_body_root = instance
	_skeleton = _find_skeleton(instance)
	if _skeleton != null:
		_skeleton.unique_name_in_owner = true
		_prop_mod = ProportionModifierScript.new()
		_prop_mod.name = "ProportionModifier"
		_skeleton.add_child(_prop_mod)

	_mesh = _find_mesh(instance)
	if _outfit != null:
		PedOutfitApplierScript.apply_to_body_root(instance, _outfit, female)
	_setup_animation_player(instance)
	_apply_proportions()
	print(
		"CityWalker body: ",
		path,
		" sex=",
		"female" if female else "male",
		" outfit=",
		_outfit.variant_id if _outfit else "none",
		" bones=",
		_skeleton.get_bone_count() if _skeleton else 0
	)


func _clear_body() -> void:
	_anim_player = null
	_prop_mod = null
	_mesh = null
	_skeleton = null
	_feet_aligned = false
	if _body_root != null and is_instance_valid(_body_root):
		_body_root.queue_free()
	_body_root = null


func apply_proportions(props: BodyProportions) -> void:
	_proportions = props.duplicate_props() if props != null else BodyProportions.identity()
	_apply_proportions()


func get_proportions() -> BodyProportions:
	return _proportions


func is_female() -> bool:
	return _female


func is_character_editor_open() -> bool:
	return _editor != null and _editor.call("is_open")


func toggle_character_editor() -> void:
	if _editor == null:
		return
	if _editor.call("is_open"):
		_editor.call("close_editor")
	else:
		_set_capture(false)
		_editor.call("open_editor", _proportions, _female)


func get_character_scale() -> float:
	return character_scale


func get_dig_radius() -> float:
	return dig_radius_at_scale_1 * character_scale


func adjust_character_scale(direction: float) -> void:
	## direction > 0 grows, < 0 shrinks (multiplicative for the wide scale range).
	if is_zero_approx(direction):
		return
	var factor := scale_factor_step if direction > 0.0 else 1.0 / scale_factor_step
	var next := clampf(character_scale * factor, scale_min, scale_max)
	if is_equal_approx(next, character_scale):
		return
	character_scale = next
	_apply_proportions()
	print("CityWalker scale=%.2f dig=%.2fm speed×%.2f" % [character_scale, get_dig_radius(), character_scale])


func _effective_body_scale() -> float:
	var prop_s := 1.0
	if _proportions != null:
		prop_s = _proportions.body_uniform_scale()
	return prop_s * character_scale


func _apply_proportions() -> void:
	if _proportions == null:
		_proportions = BodyProportions.identity()
	if _mesh != null:
		_proportions.apply_to_mesh(_mesh)
	if _prop_mod != null:
		_prop_mod.call("set_proportions", _proportions)
	if _body_root != null:
		var s := _effective_body_scale()
		_body_root.scale = Vector3(s, s, s)
		_body_root.position.y = 0.0
	_update_capsule_from_proportions()
	if _pivot != null:
		_pivot.position.y = pivot_height * character_scale
	floor_snap_length = 0.35 * character_scale
	_feet_aligned = false
	_body_base_y = 0.0


func _update_capsule_from_proportions() -> void:
	if _capsule == null:
		return
	var shape := _capsule.shape as CapsuleShape3D
	if shape == null:
		shape = CapsuleShape3D.new()
		_capsule.shape = shape
	var prop_h := 1.7
	var prop_r := 0.35
	if _proportions != null:
		prop_h = _proportions.capsule_height(1.7)
		prop_r = _proportions.capsule_radius(0.35)
	shape.height = prop_h * character_scale
	shape.radius = prop_r * character_scale
	_capsule.position.y = shape.height * 0.5 + 0.1 * character_scale


func _on_editor_proportions(props: BodyProportions) -> void:
	apply_proportions(props)


func _on_editor_sex(female: bool) -> void:
	if _editor != null:
		_proportions = (_editor.call("get_proportions") as BodyProportions).duplicate_props()
	_spawn_human(female)


func _on_editor_closed() -> void:
	_set_capture(true)


func _setup_animation_player(body: Node3D) -> void:
	_anim_player = AnimationPlayer.new()
	_anim_player.name = "AnimationPlayer"
	body.add_child(_anim_player)
	_action_playing = false
	_action_anim = ""
	_action_names = PackedStringArray()

	if not ResourceLoader.exists(QUATERNIUS_LIB):
		push_error("CityWalker: missing Quaternius library at %s" % QUATERNIUS_LIB)
		return
	var lib_packed := load(QUATERNIUS_LIB)
	if not (lib_packed is PackedScene):
		push_error("CityWalker: Quaternius library did not load as PackedScene")
		return
	var lib_root: Node = (lib_packed as PackedScene).instantiate()
	var src_player := _find_animation_player(lib_root)
	if src_player == null:
		push_error("CityWalker: Quaternius scene has no AnimationPlayer")
		lib_root.free()
		return

	var library := AnimationLibrary.new()
	var names: PackedStringArray = src_player.get_animation_list()
	var skip := {"A_TPose": true}
	for anim_name in names:
		var key := String(anim_name)
		if skip.has(key):
			continue
		## Prefer non-root-motion variants when both exist (Roll vs Roll_RM).
		if key.ends_with("_RM"):
			var base := key.substr(0, key.length() - 3)
			if src_player.has_animation(base):
				continue
		var src: Animation = src_player.get_animation(anim_name)
		if src == null:
			continue
		var copy: Animation = src.duplicate(true) as Animation
		_strip_root_translation(copy)
		## Keep locomotion looping even if import flags slip.
		if key == String(ANIM_IDLE) or key == String(ANIM_WALK):
			copy.loop_mode = Animation.LOOP_LINEAR
		library.add_animation(key, copy)
		_action_names.append(key)

	_action_names.sort()
	_anim_player.add_animation_library(String(LIB_NAME), library)
	lib_root.free()
	_merge_mixamo_actions(library)
	_action_names.sort()
	if not _anim_player.animation_finished.is_connected(_on_animation_finished):
		_anim_player.animation_finished.connect(_on_animation_finished)
	if library.has_animation(String(ANIM_IDLE)):
		_anim_player.play("%s/%s" % [LIB_NAME, ANIM_IDLE])
	elif _action_names.size() > 0:
		_anim_player.play("%s/%s" % [LIB_NAME, _action_names[0]])


func _merge_mixamo_actions(library: AnimationLibrary) -> void:
	## Optional Mixamo bake (tools/bake_mixamo_library.gd). Names already end with _m.
	if not ResourceLoader.exists(MIXAMO_LIB):
		return
	var mix: Resource = load(MIXAMO_LIB)
	if not (mix is AnimationLibrary):
		push_warning("CityWalker: Mixamo library is not AnimationLibrary: %s" % MIXAMO_LIB)
		return
	var mix_lib := mix as AnimationLibrary
	var added := 0
	for anim_name in mix_lib.get_animation_list():
		var key := String(anim_name)
		if not key.ends_with("_m"):
			key = key + "_m"
		var src: Animation = mix_lib.get_animation(anim_name)
		if src == null:
			continue
		var copy: Animation = src.duplicate(true) as Animation
		_strip_root_translation(copy)
		## Also strip Hips translation (Mixamo often roots on Hips).
		_strip_hips_translation(copy)
		if library.has_animation(key):
			library.remove_animation(key)
		library.add_animation(key, copy)
		if _action_names.find(key) < 0:
			_action_names.append(key)
		added += 1
	if added > 0:
		print("CityWalker: merged %d Mixamo actions (*_m)" % added)


func _strip_hips_translation(anim: Animation) -> void:
	for i in range(anim.get_track_count() - 1, -1, -1):
		var path := str(anim.track_get_path(i))
		var typ := anim.track_get_type(i)
		if typ != Animation.TYPE_POSITION_3D:
			continue
		if path.ends_with(":Hips") or path.ends_with("/Hips"):
			anim.remove_track(i)


func _strip_root_translation(anim: Animation) -> void:
	## Drop Root translation so the clip stays in-place (CharacterBody moves the actor).
	for i in range(anim.get_track_count() - 1, -1, -1):
		var path := str(anim.track_get_path(i))
		var typ := anim.track_get_type(i)
		if typ == Animation.TYPE_POSITION_3D and path.ends_with(":Root"):
			anim.remove_track(i)


func list_action_animations() -> PackedStringArray:
	return _action_names.duplicate()


func has_action_animation(anim_name: String) -> bool:
	if _anim_player == null or anim_name.is_empty():
		return false
	return _anim_player.has_animation("%s/%s" % [LIB_NAME, anim_name])


func is_playing_action() -> bool:
	return _action_playing


func play_action(anim_name: String) -> void:
	if _anim_player == null or anim_name.is_empty():
		return
	var path := "%s/%s" % [LIB_NAME, anim_name]
	if not _anim_player.has_animation(path):
		push_error("CityWalker: unknown action '%s'" % anim_name)
		return
	## Re-click same action cancels back to idle/walk.
	if _action_playing and _action_anim == anim_name:
		cancel_action()
		return
	_action_playing = true
	_action_anim = anim_name
	_anim_player.play(path, 0.15)
	_anim_player.speed_scale = clampf(1.0 / maxf(character_scale, 0.001), 0.05, 4.0)


func cancel_action() -> void:
	if not _action_playing:
		return
	_action_playing = false
	_action_anim = ""
	## Locomotion will restore Idle/Walk next physics frame.


func _on_animation_finished(anim_name: StringName) -> void:
	if not _action_playing:
		return
	var finished := String(anim_name)
	var expected := "%s/%s" % [LIB_NAME, _action_anim]
	if finished != expected and finished != _action_anim:
		return
	## Looping clips keep playing; one-shots end the override.
	var path := expected if _anim_player.has_animation(expected) else _action_anim
	if _anim_player.has_animation(path):
		var anim: Animation = _anim_player.get_animation(path)
		if anim != null and anim.loop_mode != Animation.LOOP_NONE:
			return
	_action_playing = false
	_action_anim = ""


func _finish_body_setup() -> void:
	pass


func _align_soles_to_floor() -> void:
	## Match lowest sole to the capsule contact plane — only valid after grounding.
	if _body_root == null or _skeleton == null or not is_on_floor():
		return
	_skeleton.force_update_all_bone_transforms()
	var contact_y := _capsule_bottom_world_y()
	var sole_y := _lowest_sole_world_y()
	if is_nan(sole_y):
		push_warning("CityWalker: foot align skipped (no sole bones/mesh)")
		return
	var delta := contact_y - sole_y
	_body_root.position.y += delta
	_body_base_y = _body_root.position.y
	_feet_aligned = true
	print("CityWalker foot align: contact_y=%.3f sole_y=%.3f delta=%.3f" % [contact_y, sole_y, delta])


func _capsule_bottom_world_y() -> float:
	var shape := _capsule.shape as CapsuleShape3D
	var half := shape.height * 0.5
	return to_global(Vector3(0.0, _capsule.position.y - half, 0.0)).y


func _lowest_sole_world_y() -> float:
	var min_y := INF
	var found := false
	for bone_name: StringName in [&"LeftToes", &"RightToes", &"LeftFoot", &"RightFoot", &"ball_l", &"ball_r"]:
		var idx := _skeleton.find_bone(String(bone_name))
		if idx < 0:
			continue
		var world := _skeleton.to_global(_skeleton.get_bone_global_pose(idx).origin)
		min_y = minf(min_y, world.y)
		found = true
	var mesh := _find_mesh(_body_root)
	if mesh != null:
		min_y = minf(min_y, (mesh.global_transform * mesh.get_aabb()).position.y)
		found = true
	return min_y if found else NAN


func _spawn_fallback_body(female: bool) -> void:
	var body := Node3D.new()
	body.name = "Body"
	body.rotation.y = PI
	add_child(body)
	_body_root = body
	_skeleton = null
	_prop_mod = null
	var mi := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.18 if female else 0.2
	capsule.height = 1.7 if female else 1.8
	mi.mesh = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.68, 0.54) if female else Color(0.78, 0.58, 0.44)
	mi.material_override = mat
	mi.position.y = capsule.height * 0.5
	body.add_child(mi)
	_mesh = mi
	_body_base_y = 0.0


func _set_capture(on: bool) -> void:
	_captured = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func is_captured() -> bool:
	return _captured


func toggle_capture() -> void:
	_set_capture(not _captured)


func release_capture() -> void:
	_set_capture(false)


func is_feet_aligned() -> bool:
	return _feet_aligned


func _unhandled_input(event: InputEvent) -> void:
	if _editor != null and _editor.call("is_open"):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_C:
				toggle_character_editor()
				get_viewport().set_input_as_handled()
				return
			KEY_R:
				_auto_run = not _auto_run
				get_viewport().set_input_as_handled()
				return
			KEY_SPACE:
				_jump_queued = true
				get_viewport().set_input_as_handled()
				return
			KEY_EQUAL, KEY_KP_ADD:
				adjust_character_scale(1.0)
				get_viewport().set_input_as_handled()
				return
			KEY_MINUS, KEY_KP_SUBTRACT:
				adjust_character_scale(-1.0)
				get_viewport().set_input_as_handled()
				return
	if event is InputEventMouseMotion and _captured:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - mm.relative.y * mouse_sensitivity, -1.2, 0.45)
		_apply_camera_angles()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom = clampf(_zoom - zoom_step, zoom_min, zoom_max)
			_spring.spring_length = _zoom
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom = clampf(_zoom + zoom_step, zoom_min, zoom_max)
			_spring.spring_length = _zoom
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if not _captured:
				_set_capture(true)
				return
			_fire_blast()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not _captured:
			_set_capture(true)


func _apply_camera_angles() -> void:
	_pivot.rotation = Vector3(_pitch, _yaw - rotation.y, 0.0)


func _physics_process(delta: float) -> void:
	if _editor != null and _editor.call("is_open"):
		velocity.x = 0.0
		velocity.z = 0.0
		_jump_queued = false
		if not is_on_floor():
			var gravity_edit: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
			velocity.y -= gravity_edit * delta
		else:
			velocity.y = 0.0
			if not _feet_aligned and _skeleton != null:
				_align_soles_to_floor()
		move_and_slide()
		_apply_camera_angles()
		return

	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	if is_on_floor():
		_coyote_left = coyote_time_sec
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		_coyote_left = maxf(_coyote_left - delta, 0.0)
		velocity.y -= gravity * delta

	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or _auto_run:
		input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir.y += 1.0
		## Manual back cancels autorun so you can stop without hunting R.
		if _auto_run:
			_auto_run = false
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_dir.x += 1.0
	input_dir = input_dir.normalized()

	var cam_yaw_basis := Basis.from_euler(Vector3(0.0, _yaw, 0.0))
	var forward := -cam_yaw_basis.z
	var right := cam_yaw_basis.x
	var wish := forward * (-input_dir.y) + right * input_dir.x
	wish.y = 0.0

	var speed := sprint_speed if Input.is_key_pressed(KEY_SHIFT) else walk_speed
	speed *= character_scale
	_moving = wish.length_squared() > 0.0001
	if _moving:
		wish = wish.normalized() * speed
		var face_yaw := atan2(-wish.x, -wish.z)
		rotation.y = lerp_angle(rotation.y, face_yaw, clampf(turn_speed * delta, 0.0, 1.0))
		velocity.x = wish.x
		velocity.z = wish.z
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	var can_jump := _coyote_left > 0.0
	if _jump_queued and can_jump:
		velocity.y = jump_velocity * sqrt(character_scale)
		_coyote_left = 0.0
		_jump_queued = false
	else:
		_jump_queued = false

	if _moving and is_on_floor() and velocity.y <= 0.0:
		_try_step_up(delta)

	## Soft void gate: don't walk off stamped/meshed ground into empty air.
	if _moving:
		_clamp_wish_to_solid_ground()

	move_and_slide()
	_update_safety_deck()
	_apply_camera_angles()
	_update_locomotion_anim(speed)

	if is_on_floor() and not _feet_aligned and _skeleton != null:
		_align_soles_to_floor()
	elif not is_on_floor() and velocity.y < -2.0:
		_rescue_from_void()
	## Absolute floor — never drop below sidewalk height into Forget voids.
	if global_position.y < SAFETY_FLOOR_TOP_Y - 0.5:
		global_position.y = SAFETY_FLOOR_TOP_Y + 0.15 * character_scale
		velocity.y = 0.0


func _ensure_safety_deck() -> void:
	if _safety_deck != null and is_instance_valid(_safety_deck):
		return
	_safety_deck = StaticBody3D.new()
	_safety_deck.name = "SafetyDeck"
	_safety_deck.collision_layer = 1
	_safety_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(64.0, 0.8, 64.0)
	shape.shape = box
	_safety_deck.add_child(shape)


func _update_safety_deck() -> void:
	if _safety_deck == null or not is_instance_valid(_safety_deck):
		return
	var host := get_parent()
	if host == null:
		return
	if _safety_deck.get_parent() != host:
		if _safety_deck.get_parent() != null:
			_safety_deck.get_parent().remove_child(_safety_deck)
		host.add_child(_safety_deck)
	_safety_deck.global_position = Vector3(
		global_position.x,
		SAFETY_FLOOR_TOP_Y - 0.4,
		global_position.z
	)


func _clamp_wish_to_solid_ground() -> void:
	## If the next step has no floor within ~2 m below, cancel horizontal motion that way.
	var space := get_world_3d().direct_space_state
	var step := Vector3(velocity.x, 0.0, velocity.z).normalized() * 0.9
	if step.length_squared() < 0.0001:
		return
	var probe := global_position + step + Vector3(0.0, 1.2, 0.0)
	var q := PhysicsRayQueryParameters3D.create(probe, probe + Vector3(0.0, -4.0, 0.0))
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		velocity.x = 0.0
		velocity.z = 0.0
		_moving = false


func _rescue_from_void() -> void:
	## Last-resort snap if we somehow fell through checkerboard collision gaps.
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0.0, 8.0, 0.0)
	var to := global_position + Vector3(0.0, -40.0, 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		## Search nearby for any floor.
		for ox in [-3.0, 0.0, 3.0, -6.0, 6.0]:
			for oz in [-3.0, 0.0, 3.0, -6.0, 6.0]:
				var f2 := global_position + Vector3(ox, 8.0, oz)
				var q2 := PhysicsRayQueryParameters3D.create(f2, f2 + Vector3(0.0, -40.0, 0.0))
				q2.collision_mask = 1
				q2.exclude = [get_rid()]
				hit = space.intersect_ray(q2)
				if not hit.is_empty():
					break
			if not hit.is_empty():
				break
	if hit.is_empty():
		return
	global_position = hit.position + Vector3(0.0, 0.15, 0.0)
	velocity = Vector3.ZERO


func _try_step_up(delta: float) -> void:
	## If horizontal motion is blocked by a low ledge, lift onto it (curbs, planters).
	var step := max_step_height * character_scale
	if step <= 0.001:
		return
	var motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if motion.length_squared() < 0.000001:
		return
	if not test_move(global_transform, motion):
		return
	var up := Vector3(0.0, step, 0.0)
	if test_move(global_transform, up):
		return
	var raised := global_transform.translated(up)
	if test_move(raised, motion):
		return
	global_position.y += step
	floor_snap_length = maxf(floor_snap_length, step * 0.5)


func _update_locomotion_anim(move_speed: float) -> void:
	if _anim_player == null:
		return
	if _action_playing:
		if _moving:
			cancel_action()
		else:
			return
	var idle_path := "%s/%s" % [LIB_NAME, ANIM_IDLE]
	var walk_path := "%s/%s" % [LIB_NAME, ANIM_WALK]
	# Bigger → slower playback (long strides / heavy idle). Tiny → snappier.
	var size_anim := clampf(1.0 / character_scale, 0.05, 4.0)
	if _moving:
		if _anim_player.current_animation != walk_path:
			_anim_player.play(walk_path, 0.2)
		var unscaled_speed := move_speed / maxf(character_scale, 0.001)
		var cadence := unscaled_speed / walk_anim_reference_speed
		_anim_player.speed_scale = clampf(cadence * size_anim, 0.05, 4.0)
	else:
		if _anim_player.current_animation != idle_path:
			_anim_player.play(idle_path, 0.25)
		_anim_player.speed_scale = size_anim


func _fire_blast() -> void:
	var from := _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var to := from + dir * blast_range
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	blast_requested.emit(hit["position"], hit["collider"], get_dig_radius())


func set_yaw(yaw: float) -> void:
	_yaw = yaw
	rotation.y = yaw
	_apply_camera_angles()


func get_camera() -> Camera3D:
	return _camera


func _find_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root as MeshInstance3D
	for child in root.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null
