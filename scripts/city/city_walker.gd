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
const ANIM_IDLE := &"Idle"
const ANIM_WALK := &"Walk"
const LIB_NAME := &"quat"

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
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


func _ready() -> void:
	_rng.randomize()
	_zoom = zoom_default
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.25

	_capsule = CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.7
	_capsule.shape = shape
	_capsule.position.y = 0.95
	add_child(_capsule)

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
	_camera.far = 500.0
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
	floor_snap_length = 0.25 * character_scale
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
	for anim_name in [String(ANIM_IDLE), String(ANIM_WALK)]:
		if not src_player.has_animation(anim_name):
			push_error("CityWalker: missing animation '%s'" % anim_name)
			continue
		var src: Animation = src_player.get_animation(anim_name)
		var copy: Animation = src.duplicate(true) as Animation
		_prepare_locomotion_clip(copy)
		library.add_animation(anim_name, copy)

	_anim_player.add_animation_library(String(LIB_NAME), library)
	lib_root.free()
	_anim_player.play("%s/%s" % [LIB_NAME, ANIM_IDLE])


func _prepare_locomotion_clip(anim: Animation) -> void:
	anim.loop_mode = Animation.LOOP_LINEAR
	# Drop Root translation so the clip stays in-place (CharacterBody moves the actor).
	for i in range(anim.get_track_count() - 1, -1, -1):
		var path := str(anim.track_get_path(i))
		var typ := anim.track_get_type(i)
		if typ == Animation.TYPE_POSITION_3D and path.ends_with(":Root"):
			anim.remove_track(i)


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
		if not is_on_floor():
			var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
			velocity.y -= gravity * delta
		else:
			velocity.y = 0.0
			if not _feet_aligned and _skeleton != null:
				_align_soles_to_floor()
		move_and_slide()
		_apply_camera_angles()
		return

	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
		if not _feet_aligned and _skeleton != null:
			_align_soles_to_floor()

	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir.y += 1.0
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

	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = 4.2 * sqrt(character_scale)

	move_and_slide()
	_apply_camera_angles()
	_update_locomotion_anim(speed)


func _update_locomotion_anim(move_speed: float) -> void:
	if _anim_player == null:
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
