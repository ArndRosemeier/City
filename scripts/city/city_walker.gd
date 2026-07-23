## Third-person city walker: MH body + Quaternius Idle/Walk (humanoid retarget).
class_name CityWalker
extends CharacterBody3D

signal blast_requested(hit_position: Vector3, collider: Object, radius_m: float)
## Melee strike: origin + flat facing direction, range in meters.
## CityRoot scales the carve diameter with character_scale (no break below 0.5×).
signal melee_strike_requested(origin: Vector3, direction: Vector3, max_range_m: float)
## Shift+LMB stomp: feet world position + blast radius in meters.
signal stomp_requested(feet_position: Vector3, radius_m: float)

const CharacterEditorScript := preload("res://scripts/city/character_editor.gd")
const ProportionModifierScript := preload("res://scripts/humans/proportion_modifier.gd")
const BodyProportionsScript := preload("res://scripts/humans/body_proportions.gd")
const EyeLaserVfxScript := preload("res://scripts/city/eye_laser_vfx.gd")
const ChargedBlastVfxScript := preload("res://scripts/city/charged_blast_vfx.gd")

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
const ANIM_SPRINT := &"Sprint"
const LIB_NAME := &"quat"

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var jump_velocity: float = 6.8
@export var mouse_sensitivity: float = 0.0022
@export var turn_speed: float = 10.0
## A/D keyboard turn rate (radians per second).
@export var keyboard_turn_rate: float = 2.4
@export var blast_range: float = 80.0
## Dig sphere radius in meters at character_scale 1.0 (intentionally mild).
@export var dig_radius_at_scale_1: float = 1.45
## Melee reach (m at scale 1) — must be close and facing the wall.
@export var melee_reach_m: float = 1.05
@export var punch_impact_ratio: float = 0.42
@export var kick_impact_ratio: float = 0.58
@export var punch_anim: String = "Punch_Cross"
@export var kick_anim: String = "Kick_Soccerball_m"
@export var stomp_anim: String = "Stomping_m"
## Fraction into Stomping when the foot hits and voxels break.
@export var stomp_impact_ratio: float = 0.48
@export var stomp_radius_at_scale_1: float = 2.8
@export var stomp_cooldown_sec: float = 0.85
@export var stomp_shake_trauma: float = 0.72
@export var camera_shake_max_offset_m: float = 0.28
@export var camera_shake_max_roll_deg: float = 4.5
@export var camera_shake_decay: float = 1.35
## Ctrl+LMB laser: click aim, punch/kick carve power, meters.
@export var laser_range_m: float = 100.0
@export var laser_cooldown_sec: float = 0.45
@export var laser_speed_mps: float = 30.0
## Hold LMB to charge the bomb; release to fire. Shift+LMB stomps; Ctrl+LMB fires the laser.
@export var charged_blast_speed_mps: float = 10.0
@export var charged_blast_charge_sec: float = 1.6
@export var charged_blast_radius_min_m: float = 0.9
@export var charged_blast_radius_max_m: float = 4.2
@export var charged_blast_cooldown_sec: float = 0.55
@export var charged_blast_shoot_anim: String = "Spell_Simple_Shoot"
@export var charged_blast_idle_anim: String = "Spell_Simple_Idle"
## Fraction into Spell_Simple_Shoot when the orb leaves the hand.
@export var charged_blast_release_ratio: float = 0.36
@export var pivot_height: float = 1.35
@export var zoom_min: float = 1.8
@export var zoom_max: float = 12.0
@export var zoom_step: float = 0.55
@export var zoom_default: float = 4.2
## Page Up/Down pitch rate (radians per second).
@export var pitch_rate: float = 1.1
@export var pitch_min: float = -1.55
@export var pitch_max: float = 0.85
## Walk clip is authored near ~1.4 m/s; scale playback to match move speed.
@export var walk_anim_reference_speed: float = 1.4
## Sprint clip authored near ~4.2 m/s; scale playback to match sprint speed.
@export var sprint_anim_reference_speed: float = 4.2
@export var character_scale: float = 1.0
## Multiplicative +/- step (0.2×…5× range).
@export var scale_factor_step: float = 1.15
@export var scale_min: float = 0.2
@export var scale_max: float = 5.0
## Auto-step onto curbs / low ledges (meters, NOT scaled — giants ignore curbs).
@export var max_step_height: float = 0.38
@export var coyote_time_sec: float = 0.12
## How long wished move can be blocked before jump-unstuck arms.
@export var stuck_time_sec: float = 0.55
## Above this scale, Y is ray-locked to the ground (no capsule/voxel bob).
@export var ray_ground_scale: float = 1.35

## Capsule sole sits this far above the CharacterBody origin — constant at every size.
const CAPSULE_FOOT_CLEARANCE := 0.05
const FLOOR_SNAP_M := 0.2
const SAFE_MARGIN_M := 0.06

var _yaw: float = 0.0
var _pitch: float = -0.35
## Camera yaw relative to body while / after RMB look.
var _cam_yaw_offset: float = 0.0
var _rmb_looking: bool = false
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
var _melee_strike_token: int = 0
var _stomp_token: int = 0
var _stomp_ready_at_msec: int = 0
var _shake_trauma: float = 0.0
var _stuck_timer: float = 0.0
var _unstuck_cooldown: float = 0.0
var _was_ray_grounded: bool = false
var _eye_laser: Node
var _charged_blast: Node
var _laser_ready_at_msec: int = 0
var _laser_shot_origin: Vector3 = Vector3.ZERO
var _blast_charge: float = 0.0
var _blast_ready_at_msec: int = 0
## True while LMB is held for the bomb — charge until release fires it.
var _blast_charging: bool = false
var _blast_fire_token: int = 0
var _blast_pending_aim: Vector3 = Vector3.ZERO
var _blast_pending_radius: float = 1.0
var _charge_orb: MeshInstance3D
var _charge_orb_mesh: SphereMesh
var _charge_orb_mat: StandardMaterial3D
var _charge_orb_light: OmniLight3D
var _footstep_accum: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_zoom = zoom_default
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = FLOOR_SNAP_M
	floor_max_angle = deg_to_rad(55.0)
	safe_margin = SAFE_MARGIN_M
	floor_stop_on_slope = true

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
	_camera.far = 520.0
	_camera.current = true
	_spring.add_child(_camera)

	_editor = CharacterEditorScript.new()
	_editor.name = "CharacterEditor"
	add_child(_editor)
	_editor.proportions_changed.connect(_on_editor_proportions)
	_editor.sex_change_requested.connect(_on_editor_sex)
	_editor.closed.connect(_on_editor_closed)

	_apply_camera_angles()
	## Free cursor — no mouse-look capture.
	_set_capture(false)
	_setup_eye_laser()
	_setup_charged_blast()
	_ensure_charge_orb()


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
	## Only wire lasers once the camera exists (first spawn runs before Camera3D).
	if _camera != null:
		_setup_eye_laser()
		_setup_charged_blast()
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
	_teardown_eye_laser()
	_teardown_charged_blast()
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
		_set_rmb_looking(false)
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
	set_character_scale(character_scale * factor, false)


func set_character_scale(value: float, silent: bool = false) -> void:
	var next := clampf(value, scale_min, scale_max)
	if is_equal_approx(next, character_scale):
		return
	var prev := character_scale
	var pos_before := global_position
	character_scale = next
	_apply_proportions()
	## Capsule sole clearance is constant, so scale no longer pumps world Y.
	## Re-align mesh soles only on discrete +/- steps (not every pad tick).
	if not silent:
		_feet_aligned = false
		_body_base_y = 0.0
	## Growing into walls/ceilings — roll back that step.
	if next > prev and not _can_stand_at(global_position):
		character_scale = prev
		_apply_proportions()
		global_position = pos_before
		return
	if _eye_laser != null and _eye_laser.has_method("set_character_scale"):
		_eye_laser.call("set_character_scale", _effective_body_scale())
	if not silent:
		print("CityWalker scale=%.2f dig=%.2fm speed×%.2f" % [character_scale, get_dig_radius(), character_scale])


## Continuous pad scaling: log_rate is natural-log change per second (positive = grow).
func nudge_character_scale_exp(log_rate: float, delta: float) -> void:
	if is_zero_approx(log_rate) or delta <= 0.0:
		return
	set_character_scale(character_scale * exp(log_rate * delta), true)


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
		## Keep any prior foot-align offset in body-local space (scaled visuals only).
		_body_root.position.y = _body_base_y
	_update_capsule_from_proportions()
	if _pivot != null:
		_pivot.position.y = pivot_height * character_scale
	floor_snap_length = FLOOR_SNAP_M
	safe_margin = SAFE_MARGIN_M


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
	## Sole at a FIXED clearance above the body origin — independent of scale.
	## (Old 0.1*scale floated giants and fought floor snap every frame.)
	_capsule.position.y = shape.height * 0.5 + CAPSULE_FOOT_CLEARANCE


func _on_editor_proportions(props: BodyProportions) -> void:
	apply_proportions(props)


func _on_editor_sex(female: bool) -> void:
	if _editor != null:
		_proportions = (_editor.call("get_proportions") as BodyProportions).duplicate_props()
	_spawn_human(female)


func _on_editor_closed() -> void:
	## Stay unlocked — gameplay uses a free mouse cursor.
	_set_capture(false)


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
		if key == String(ANIM_IDLE) or key == String(ANIM_WALK) or key == String(ANIM_SPRINT):
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


func play_action(anim_name: String, allow_toggle: bool = true) -> void:
	if _anim_player == null or anim_name.is_empty():
		return
	var path := "%s/%s" % [LIB_NAME, anim_name]
	if not _anim_player.has_animation(path):
		push_error("CityWalker: unknown action '%s'" % anim_name)
		return
	## Re-click same action cancels back to idle/walk (action bar only).
	if allow_toggle and _action_playing and _action_anim == anim_name:
		cancel_action()
		return
	_action_playing = true
	_action_anim = anim_name
	_anim_player.play(path, 0.12)
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
			KEY_O:
				## Sound on/off.
				_toggle_sound()
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
	if event is InputEventMouseMotion and _rmb_looking:
		var mm := event as InputEventMouseMotion
		## Turn the character with look yaw; pitch stays on the camera arm.
		rotation.y -= mm.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - mm.relative.y * mouse_sensitivity, pitch_min, pitch_max)
		_apply_camera_angles()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom = clampf(_zoom - zoom_step, zoom_min, zoom_max)
			_spring.spring_length = _zoom
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom = clampf(_zoom + zoom_step, zoom_min, zoom_max)
			_spring.spring_length = _zoom
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if Input.is_key_pressed(KEY_CTRL):
					_blast_charging = false
					_blast_charge = 0.0
					_start_laser_eyes_at_cursor()
				elif Input.is_key_pressed(KEY_SHIFT):
					_blast_charging = false
					_blast_charge = 0.0
					_start_stomp()
				else:
					_begin_charged_blast_hold()
			else:
				if _blast_charging:
					_release_charged_blast_at_cursor()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_set_rmb_looking(true)
			else:
				_set_rmb_looking(false)
			get_viewport().set_input_as_handled()


func _set_rmb_looking(on: bool) -> void:
	if on and not is_zero_approx(_cam_yaw_offset):
		## Fold any leftover camera-orbit offset into body facing so look stays coherent.
		rotation.y += _cam_yaw_offset
		_cam_yaw_offset = 0.0
	_rmb_looking = on
	## Capture only while aiming the camera; cursor free otherwise.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE
	_captured = on
	if on:
		_apply_camera_angles()


func _apply_camera_angles() -> void:
	## Body yaw from A/D and RMB look; optional leftover orbit stays in _cam_yaw_offset.
	_yaw = rotation.y
	_pivot.rotation = Vector3(_pitch, _cam_yaw_offset, 0.0)


func add_camera_shake(trauma: float) -> void:
	_shake_trauma = clampf(_shake_trauma + maxf(trauma, 0.0), 0.0, 1.0)


func _update_camera_shake(delta: float) -> void:
	if _camera == null:
		return
	if _shake_trauma <= 0.001:
		_shake_trauma = 0.0
		_camera.position = Vector3.ZERO
		_camera.rotation = Vector3.ZERO
		return
	_shake_trauma = maxf(_shake_trauma - camera_shake_decay * delta, 0.0)
	var shake := _shake_trauma * _shake_trauma
	var ox := camera_shake_max_offset_m * shake * _rng.randf_range(-1.0, 1.0)
	var oy := camera_shake_max_offset_m * shake * _rng.randf_range(-1.0, 1.0) * 0.65
	var oz := camera_shake_max_offset_m * 0.35 * shake * _rng.randf_range(-1.0, 1.0)
	_camera.position = Vector3(ox, oy, oz)
	_camera.rotation = Vector3(
		deg_to_rad(camera_shake_max_roll_deg * 0.35 * shake * _rng.randf_range(-1.0, 1.0)),
		deg_to_rad(camera_shake_max_roll_deg * 0.25 * shake * _rng.randf_range(-1.0, 1.0)),
		deg_to_rad(camera_shake_max_roll_deg * shake * _rng.randf_range(-1.0, 1.0))
	)


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
			if not _feet_aligned and _skeleton != null and character_scale < ray_ground_scale:
				_align_soles_to_floor()
		move_and_slide()
		_apply_camera_angles()
		return

	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var ray_mode := character_scale >= ray_ground_scale
	## Large bodies: no floor-snap — Y is owned by the ground ray after the slide.
	floor_snap_length = 0.0 if ray_mode else FLOOR_SNAP_M

	if is_on_floor() or _was_ray_grounded:
		_coyote_left = coyote_time_sec
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		_coyote_left = maxf(_coyote_left - delta, 0.0)
		velocity.y -= gravity * delta

	## Page Up looks up, Page Down looks down (held = continuous).
	var pitch_input := 0.0
	if Input.is_key_pressed(KEY_PAGEUP):
		pitch_input += 1.0
	if Input.is_key_pressed(KEY_PAGEDOWN):
		pitch_input -= 1.0
	if not is_zero_approx(pitch_input):
		_pitch = clampf(_pitch + pitch_input * pitch_rate * delta, pitch_min, pitch_max)

	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) or _auto_run:
		input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir.y += 1.0
		## Manual back cancels autorun so you can stop without hunting R.
		if _auto_run:
			_auto_run = false
	## A/D (and arrows) turn in place — no strafe.
	var turn := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		turn += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		turn -= 1.0
	if not is_zero_approx(turn):
		rotation.y += turn * keyboard_turn_rate * delta

	## Move only along body facing (W/S).
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	else:
		forward = Vector3(0.0, 0.0, -1.0)
	var wish := forward * (-input_dir.y)
	wish.y = 0.0

	var shift_held := Input.is_key_pressed(KEY_SHIFT)
	var sprinting := shift_held
	var speed := sprint_speed if sprinting else walk_speed
	speed *= character_scale
	_moving = wish.length_squared() > 0.0001
	if _moving:
		wish = wish.normalized() * speed
		velocity.x = wish.x
		velocity.z = wish.z
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		sprinting = false

	var can_jump := _coyote_left > 0.0
	## Jump always tries a horizontal unstick when you've been blocked — no Y pumping.
	if _jump_queued and _stuck_timer > 0.15:
		_unstuck_horizontal()
	if _jump_queued and can_jump:
		velocity.y = jump_velocity * sqrt(character_scale)
		_coyote_left = 0.0
		_was_ray_grounded = false
		_jump_queued = false
	else:
		_jump_queued = false

	## Human-scale curb step only — giants walk over curbs via radius, no Y pops.
	if not ray_mode and _moving and is_on_floor() and velocity.y <= 0.0:
		_try_step_up(delta)

	var wish_speed := speed if _moving else 0.0
	move_and_slide()
	## Soft wall slide: push out along collision normals in XZ only (no vertical).
	if _stuck_timer > 0.12:
		_slide_out_horizontal()
	_stabilize_vertical(ray_mode)
	_update_stuck_timer(delta, wish_speed)
	## Auto-recover without jumping — still horizontal-only + one ground snap.
	if _stuck_timer >= stuck_time_sec:
		if _unstuck_horizontal():
			_stuck_timer = 0.0
	_update_safety_deck()
	_apply_camera_angles()
	_update_camera_shake(delta)
	_update_locomotion_anim(speed, sprinting)
	_update_footstep_sfx(delta, speed)
	_update_blast_charge(delta, _blast_charging)

	if not ray_mode and is_on_floor() and not _feet_aligned and _skeleton != null:
		_align_soles_to_floor()
	## Absolute floor — never drop below sidewalk height into Forget voids.
	if global_position.y < SAFETY_FLOOR_TOP_Y - 0.5:
		global_position.y = SAFETY_FLOOR_TOP_Y
		velocity.y = 0.0
		_was_ray_grounded = true
	if _unstuck_cooldown > 0.0:
		_unstuck_cooldown = maxf(_unstuck_cooldown - delta, 0.0)


func _stabilize_vertical(ray_mode: bool) -> void:
	## Kill residual vertical chatter after the slide.
	if not ray_mode:
		_was_ray_grounded = false
		if is_on_floor() and velocity.y <= 0.0:
			velocity.y = 0.0
		return
	## Giant mode: own Y via a single ground ray. Capsule/voxel micro-hits cannot bob us.
	if velocity.y > 0.15:
		_was_ray_grounded = false
		return
	var hit := _ray_ground(0.0, 6.0 * character_scale)
	if hit.is_empty():
		_was_ray_grounded = false
		return
	var ground_y: float = hit.position.y
	## Never stick upward onto a surface above the feet (ceilings / overhangs).
	if ground_y > global_position.y + 0.35 * character_scale:
		_was_ray_grounded = false
		return
	## Only stick when close to ground (airborne jumps/falls keep physics Y).
	if global_position.y - ground_y > 1.25 * character_scale and not is_on_floor():
		_was_ray_grounded = false
		return
	global_position.y = ground_y
	velocity.y = 0.0
	_was_ray_grounded = true


func _ray_ground(_up_m: float, down_m: float) -> Dictionary:
	## Cast from just above the feet downward only. Starting high above used to hit
	## ceilings / upper floors first and teleport the player onto roofs.
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0.0, 0.2 * maxf(character_scale, 1.0), 0.0)
	var to := global_position + Vector3(0.0, -maxf(down_m, 0.5), 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	var exclude: Array[RID] = [get_rid()]
	if _safety_deck != null and is_instance_valid(_safety_deck):
		exclude.append(_safety_deck.get_rid())
	q.exclude = exclude
	return space.intersect_ray(q)


func _ensure_safety_deck() -> void:
	if _safety_deck != null and is_instance_valid(_safety_deck):
		return
	_safety_deck = StaticBody3D.new()
	_safety_deck.name = "SafetyDeck"
	_safety_deck.collision_layer = 1
	_safety_deck.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	_safety_deck.add_child(shape)


func _update_safety_deck() -> void:
	## Always well below the feet so it never fights the real floor (old fixed-Y deck
	## at sidewalk height dual-contacted giants and caused vertical jitter).
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
		global_position.y - 8.0,
		global_position.z
	)


func _clamp_wish_to_solid_ground() -> void:
	## Disabled: blocked walking/jumping off roofs and ledges.
	pass


func _rescue_from_void() -> void:
	## Last-resort snap if we somehow fell through checkerboard collision gaps.
	## Only accept surfaces at or below us — never teleport upward onto a roof.
	var hit := _find_ground_below(50.0)
	if hit.is_empty():
		return
	global_position = Vector3(hit.position.x, hit.position.y, hit.position.z)
	velocity = Vector3.ZERO
	_was_ray_grounded = true


func _find_ground_below(down_m: float) -> Dictionary:
	var offsets: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(-3.0, 0.0, 0.0),
		Vector3(3.0, 0.0, 0.0),
		Vector3(0.0, 0.0, -3.0),
		Vector3(0.0, 0.0, 3.0),
		Vector3(-6.0, 0.0, 0.0),
		Vector3(6.0, 0.0, 0.0),
		Vector3(0.0, 0.0, -6.0),
		Vector3(0.0, 0.0, 6.0),
	]
	var origin := global_position
	for offset in offsets:
		global_position = origin + offset
		var hit := _ray_ground(0.0, down_m)
		global_position = origin
		if hit.is_empty():
			continue
		var p: Vector3 = hit["position"] as Vector3
		if p.y > origin.y + 0.5:
			continue
		hit["position"] = Vector3(origin.x + offset.x, p.y, origin.z + offset.z)
		return hit
	return {}


func _update_stuck_timer(delta: float, wish_speed: float) -> void:
	if wish_speed < 0.35 * character_scale:
		_stuck_timer = 0.0
		return
	var real := get_real_velocity()
	var real_h := Vector2(real.x, real.z).length()
	if real_h < wish_speed * 0.1:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0


func _capsule_radius() -> float:
	if _capsule == null:
		return 0.35 * character_scale
	var shape := _capsule.shape as CapsuleShape3D
	if shape == null:
		return 0.35 * character_scale
	return shape.radius


## Push away from walls using slide normals — XZ only, tiny steps, no Y change.
func _slide_out_horizontal() -> void:
	var count := get_slide_collision_count()
	if count <= 0:
		return
	var push := Vector3.ZERO
	for i in count:
		var col := get_slide_collision(i)
		var n := col.get_normal()
		n.y = 0.0
		if n.length_squared() < 0.0001:
			continue
		push += n.normalized()
	if push.length_squared() < 0.0001:
		return
	## Scale with size so giants clear voxel facades; keep small to avoid pops.
	var dist := clampf(0.04 * character_scale, 0.04, 0.35)
	global_position += push.normalized() * dist


## Find a free footprint at the SAME height, then one ground-ray snap (same as stabilize).
## Never lifts in a loop — that was the jitter source.
func _unstuck_horizontal() -> bool:
	if _unstuck_cooldown > 0.0:
		return false
	_unstuck_cooldown = 0.45
	var origin := global_position
	var r0 := maxf(_capsule_radius() * 0.4, 0.25)
	var radii: Array[float] = [r0, r0 * 2.0, r0 * 3.5, r0 * 5.5, r0 * 8.0]
	## Prefer escaping opposite to facing.
	var prefer := Vector3(-global_transform.basis.z.x, 0.0, -global_transform.basis.z.z)
	if prefer.length_squared() < 0.0001:
		prefer = Vector3(0.0, 0.0, -1.0)
	else:
		prefer = prefer.normalized()

	for radius in radii:
		for i in 12:
			var ang := atan2(prefer.x, prefer.z) + TAU * float(i) / 12.0
			var candidate := origin + Vector3(sin(ang) * radius, 0.0, cos(ang) * radius)
			if not _can_stand_at(candidate):
				continue
			global_position = candidate
			_snap_y_to_ground_once()
			velocity.x = 0.0
			velocity.z = 0.0
			_stuck_timer = 0.0
			return true
	## Last resort: re-snap Y only (clears micro-embed in floor mesh).
	global_position = origin
	_snap_y_to_ground_once()
	_stuck_timer = 0.0
	return false


func _can_stand_at(pos: Vector3) -> bool:
	var xf := global_transform
	xf.origin = pos
	var s := clampf(0.12 * character_scale, 0.1, 0.45)
	var free := 0
	var dirs: Array[Vector3] = [
		Vector3(s, 0.0, 0.0),
		Vector3(-s, 0.0, 0.0),
		Vector3(0.0, 0.0, s),
		Vector3(0.0, 0.0, -s),
	]
	for d in dirs:
		if not test_move(xf, d):
			free += 1
	## Need room to move in at least two horizontal directions.
	return free >= 2


func _snap_y_to_ground_once() -> void:
	var down := 8.0 * maxf(character_scale, 1.0)
	var hit := _ray_ground(0.0, down)
	if hit.is_empty():
		return
	var ground_y: float = (hit.position as Vector3).y
	## Never snap upward onto ceilings / roofs above the current feet.
	if ground_y > global_position.y + 0.35 * maxf(character_scale, 1.0):
		return
	global_position.y = ground_y
	velocity.y = 0.0
	_was_ray_grounded = true


func _try_step_up(delta: float) -> void:
	## Human-scale curb assist only (absolute meters, never grows with character_scale).
	var step := max_step_height
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


func _update_locomotion_anim(move_speed: float, sprinting: bool = false) -> void:
	if _anim_player == null:
		return
	if _action_playing:
		## One-shots (punch/kick) play out; looping emotes cancel when you walk.
		if _moving and _action_is_looping():
			cancel_action()
		else:
			return
	var idle_path := "%s/%s" % [LIB_NAME, ANIM_IDLE]
	var walk_path := "%s/%s" % [LIB_NAME, ANIM_WALK]
	var sprint_path := "%s/%s" % [LIB_NAME, ANIM_SPRINT]
	# Bigger → slower playback (long strides / heavy idle). Tiny → snappier.
	var size_anim := clampf(1.0 / character_scale, 0.05, 4.0)
	if _moving:
		var use_sprint := sprinting and _anim_player.has_animation(sprint_path)
		var loco_path := sprint_path if use_sprint else walk_path
		if _anim_player.current_animation != loco_path:
			_anim_player.play(loco_path, 0.15 if use_sprint else 0.2)
		var unscaled_speed := move_speed / maxf(character_scale, 0.001)
		var ref_speed := sprint_anim_reference_speed if use_sprint else walk_anim_reference_speed
		var cadence := unscaled_speed / maxf(ref_speed, 0.01)
		_anim_player.speed_scale = clampf(cadence * size_anim, 0.05, 4.0)
	else:
		if _anim_player.current_animation != idle_path:
			_anim_player.play(idle_path, 0.25)
		_anim_player.speed_scale = size_anim


func _action_is_looping() -> bool:
	if _anim_player == null or _action_anim.is_empty():
		return false
	var path := "%s/%s" % [LIB_NAME, _action_anim]
	if not _anim_player.has_animation(path):
		return false
	var anim: Animation = _anim_player.get_animation(path)
	return anim != null and anim.loop_mode != Animation.LOOP_NONE


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


func _city_audio() -> Node:
	return get_tree().get_first_node_in_group(&"city_audio")


func _toggle_sound() -> void:
	var audio := _city_audio()
	if audio != null and audio.has_method("toggle"):
		var on: bool = bool(audio.call("toggle"))
		print("CityAudio: %s" % ("ON" if on else "OFF"))


func _update_footstep_sfx(delta: float, move_speed: float) -> void:
	if not _moving:
		_footstep_accum = 0.0
		return
	var grounded := is_on_floor() or _was_ray_grounded
	if not grounded:
		_footstep_accum = 0.0
		return
	## Stride interval grows with size so giants don't machine-gun footsteps.
	var interval := clampf(0.32 * sqrt(character_scale), 0.22, 0.85)
	var cadence := clampf(move_speed / maxf(walk_speed * character_scale, 0.01), 0.55, 1.6)
	_footstep_accum += delta * cadence
	if _footstep_accum < interval:
		return
	_footstep_accum = 0.0
	var audio := _city_audio()
	if audio != null and audio.has_method("play_footstep"):
		audio.call("play_footstep", global_position, character_scale)


func _setup_eye_laser() -> void:
	_teardown_eye_laser()
	_eye_laser = EyeLaserVfxScript.new()
	_eye_laser.name = "EyeLaserVfx"
	add_child(_eye_laser)
	_eye_laser.call("setup")
	_eye_laser.call("set_character_scale", _effective_body_scale())
	if _eye_laser.has_method("set_obstacle_probe"):
		_eye_laser.call(
			"set_obstacle_probe",
			func(from: Vector3, tip: Vector3) -> float:
				var root := _city_root()
				if root == null or not root.has_method("laser_probe_agent_distance"):
					return -1.0
				return float(root.call("laser_probe_agent_distance", from, tip))
		)
	if _eye_laser.has_signal("impact") and not _eye_laser.is_connected("impact", _on_laser_impact):
		_eye_laser.connect("impact", _on_laser_impact)


func _teardown_eye_laser() -> void:
	if _eye_laser != null and is_instance_valid(_eye_laser):
		if _eye_laser.has_signal("impact") and _eye_laser.is_connected("impact", _on_laser_impact):
			_eye_laser.disconnect("impact", _on_laser_impact)
		_eye_laser.queue_free()
	_eye_laser = null


func _setup_charged_blast() -> void:
	_teardown_charged_blast()
	_charged_blast = ChargedBlastVfxScript.new()
	_charged_blast.name = "ChargedBlastVfx"
	add_child(_charged_blast)
	_charged_blast.call("setup")
	if _charged_blast.has_method("set_obstacle_probe"):
		_charged_blast.call(
			"set_obstacle_probe",
			func(from: Vector3, tip: Vector3) -> float:
				var root := _city_root()
				if root == null or not root.has_method("laser_probe_agent_distance"):
					return -1.0
				return float(root.call("laser_probe_agent_distance", from, tip))
		)
	if _charged_blast.has_signal("impact") and not _charged_blast.is_connected(
		"impact", _on_charged_blast_impact
	):
		_charged_blast.connect("impact", _on_charged_blast_impact)


func _teardown_charged_blast() -> void:
	if _charged_blast != null and is_instance_valid(_charged_blast):
		if _charged_blast.has_signal("impact") and _charged_blast.is_connected(
			"impact", _on_charged_blast_impact
		):
			_charged_blast.disconnect("impact", _on_charged_blast_impact)
		_charged_blast.queue_free()
	_charged_blast = null


func _ensure_charge_orb() -> void:
	if _charge_orb != null and is_instance_valid(_charge_orb):
		return
	_charge_orb_mat = StandardMaterial3D.new()
	_charge_orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_charge_orb_mat.albedo_color = Color(1.0, 0.2, 0.05, 0.85)
	_charge_orb_mat.emission_enabled = true
	_charge_orb_mat.emission = Color(1.0, 0.15, 0.02)
	_charge_orb_mat.emission_energy_multiplier = 10.0
	_charge_orb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_charge_orb_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_charge_orb_mesh = SphereMesh.new()
	_charge_orb_mesh.radial_segments = 14
	_charge_orb_mesh.rings = 8
	_charge_orb = MeshInstance3D.new()
	_charge_orb.name = "ChargeOrb"
	_charge_orb.mesh = _charge_orb_mesh
	_charge_orb.material_override = _charge_orb_mat
	_charge_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_charge_orb.visible = false
	add_child(_charge_orb)
	_charge_orb_light = OmniLight3D.new()
	_charge_orb_light.name = "ChargeLight"
	_charge_orb_light.light_color = Color(1.0, 0.28, 0.05)
	_charge_orb_light.shadow_enabled = false
	_charge_orb_light.visible = false
	_charge_orb.add_child(_charge_orb_light)


func _charged_blast_radius() -> float:
	var scale := maxf(character_scale, 0.05)
	var t := clampf(_blast_charge / maxf(charged_blast_charge_sec, 0.05), 0.0, 1.0)
	## Smooth ease-out so early hold grows quickly, then settles toward max.
	var eased := 1.0 - (1.0 - t) * (1.0 - t)
	var base := lerpf(charged_blast_radius_min_m, charged_blast_radius_max_m, eased)
	return base * scale


func _update_blast_charge(delta: float, charging_now: bool) -> void:
	_ensure_charge_orb()
	if charging_now:
		_blast_charge = minf(_blast_charge + delta, charged_blast_charge_sec)
		_ensure_spell_charge_pose()
	elif not _blast_charging:
		_blast_charge = maxf(_blast_charge - delta * 2.4, 0.0)
	## While LMB is held, charge grows; release fires. Frozen charge only if somehow interrupted.
	var show_orb := _blast_charging and _blast_charge > 0.02
	if _charge_orb == null:
		return
	_charge_orb.visible = show_orb
	if _charge_orb_light != null:
		_charge_orb_light.visible = show_orb
	if not show_orb:
		return
	var radius := _charged_blast_radius()
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
	var orb_r := radius * (0.09 + 0.03 * pulse)
	if _charge_orb_mesh != null:
		_charge_orb_mesh.radius = orb_r
		_charge_orb_mesh.height = orb_r * 2.0
	_charge_orb.global_position = _spell_hand_origin()
	if _charge_orb_mat != null:
		_charge_orb_mat.emission_energy_multiplier = 8.0 + 10.0 * pulse
	if _charge_orb_light != null:
		_charge_orb_light.light_energy = 2.0 + 8.0 * (_blast_charge / maxf(charged_blast_charge_sec, 0.05))
		_charge_orb_light.omni_range = orb_r * 8.0


func _ensure_spell_charge_pose() -> void:
	## Hold the casting pose while charging; Shoot replaces it on release.
	if _action_playing and _action_anim == charged_blast_idle_anim:
		return
	if _action_playing and _action_anim == charged_blast_shoot_anim:
		return
	if not has_action_animation(charged_blast_idle_anim):
		return
	var path := "%s/%s" % [LIB_NAME, charged_blast_idle_anim]
	var anim: Animation = _anim_player.get_animation(path)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
	play_action(charged_blast_idle_anim, false)


func _begin_charged_blast_hold() -> void:
	_blast_charging = true
	_blast_charge = maxf(_blast_charge, 0.05)
	_ensure_spell_charge_pose()


func _release_charged_blast_at_cursor() -> void:
	_blast_charging = false
	if _charge_orb != null:
		_charge_orb.visible = false
	if _charge_orb_light != null:
		_charge_orb_light.visible = false
	_start_charged_blast_at_cursor()


func _spell_hand_origin() -> Vector3:
	## Spell_Simple_* casts from the left hand; spawn well in front of the palm.
	var hand := _bone_world_pos(
		[&"LeftHand", &"hand_l", &"hand.L", &"LeftLowerArm", &"lowerarm_l"]
	)
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3(0.0, 0.0, -1.0)
	else:
		fwd = fwd.normalized()
	var s := character_scale
	## ~1 m in front of the hand at human scale (grows with the character).
	var ahead := 1.0 * s
	if hand.is_finite():
		return hand + fwd * ahead + Vector3.UP * (0.05 * s)
	return global_position + Vector3(0.0, 1.15 * s, 0.0) + fwd * (ahead + 0.35 * s)


func _laser_eye_origin() -> Vector3:
	## Midpoint between approximate eye sockets (head center, slight forward/up).
	var head := _bone_world_pos([&"Head", &"head"])
	if not head.is_finite():
		head = global_position + Vector3(0.0, 1.55 * character_scale, 0.0)
	var up := Vector3.UP
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3(0.0, 0.0, -1.0)
	else:
		fwd = fwd.normalized()
	var s := character_scale
	return head + up * (0.015 * s) + fwd * (0.09 * s)


func _on_laser_impact(hit_point: Vector3, direction: Vector3) -> void:
	## Arrive: kill ped / flip car if the shot landed on an agent; else carve voxels.
	var dir := direction
	if dir.length_squared() < 0.0001:
		dir = -global_transform.basis.z
	else:
		dir = dir.normalized()
	var audio := _city_audio()
	if audio != null and audio.has_method("play_laser_impact"):
		audio.call("play_laser_impact", hit_point, character_scale)
	var from := _laser_shot_origin
	if from.length_squared() < 0.0001:
		from = hit_point - dir * 0.15
	var root := _city_root()
	if root != null and root.has_method("apply_laser_agent_hit"):
		if bool(root.call("apply_laser_agent_hit", from, hit_point, dir)):
			return
	## Short march into fabric at the impact — not the full laser range (avoids
	## hitting agents behind walls).
	var origin := hit_point - dir * 0.15
	melee_strike_requested.emit(origin, dir, maxf(2.5, character_scale * 2.0))


func _on_charged_blast_impact(hit_point: Vector3, direction: Vector3, radius_m: float) -> void:
	var dir := direction
	if dir.length_squared() < 0.0001:
		dir = -global_transform.basis.z
	else:
		dir = dir.normalized()
	var audio := _city_audio()
	if audio != null and audio.has_method("play_laser_impact"):
		audio.call("play_laser_impact", hit_point, character_scale)
	var root := _city_root()
	## Agents at the impact still die / flip; the blast itself does not cascade fabric.
	if root != null and root.has_method("apply_laser_agent_hit"):
		var from := hit_point - dir * maxf(radius_m, 0.5)
		root.call("apply_laser_agent_hit", from, hit_point, dir)
	if root != null and root.has_method("apply_charged_blast"):
		root.call("apply_charged_blast", hit_point, radius_m)


func _aim_point_at_cursor() -> Vector3:
	if _camera == null:
		return global_position - global_transform.basis.z * 10.0
	var mouse := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse)
	var ray_dir := _camera.project_ray_normal(mouse)
	if ray_dir.length_squared() < 0.0001:
		return from + (-global_transform.basis.z) * laser_range_m
	ray_dir = ray_dir.normalized()
	var to := from + ray_dir * laser_range_m
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var aim_point := to
	if not hit.is_empty():
		aim_point = hit["position"] as Vector3
	var origin := _laser_eye_origin()
	var root := _city_root()
	if root != null and root.has_method("resolve_laser_aim"):
		aim_point = root.call("resolve_laser_aim", from, aim_point, origin) as Vector3
	return aim_point


func _start_charged_blast_at_cursor() -> void:
	if _camera == null:
		_blast_charge = 0.0
		return
	var now := Time.get_ticks_msec()
	if now < _blast_ready_at_msec:
		_blast_charge = 0.0
		return
	if _charged_blast != null and bool(_charged_blast.call("is_firing")):
		_blast_charge = 0.0
		return
	## Tap-release still fires a minimum bomb.
	if _blast_charge < 0.05:
		_blast_charge = 0.05
	_blast_pending_radius = _charged_blast_radius()
	_blast_pending_aim = _aim_point_at_cursor()
	_blast_charge = 0.0
	_blast_ready_at_msec = now + int(maxi(int(charged_blast_cooldown_sec * 1000.0), 50))
	if _charge_orb != null:
		_charge_orb.visible = false
	if _charge_orb_light != null:
		_charge_orb_light.visible = false

	if has_action_animation(charged_blast_shoot_anim):
		play_action(charged_blast_shoot_anim, false)
		_schedule_charged_blast_release()
	else:
		push_error("CityWalker: charged blast anim missing (%s)" % charged_blast_shoot_anim)
		_fire_charged_blast_projectile()


func _schedule_charged_blast_release() -> void:
	_blast_fire_token += 1
	var token := _blast_fire_token
	var delay := 0.22
	var speed := 1.0
	if _anim_player != null:
		speed = maxf(_anim_player.speed_scale, 0.05)
		var path := "%s/%s" % [LIB_NAME, charged_blast_shoot_anim]
		if _anim_player.has_animation(path):
			var anim: Animation = _anim_player.get_animation(path)
			if anim != null:
				delay = maxf(anim.length * clampf(charged_blast_release_ratio, 0.05, 0.95), 0.05)
	## Wall-clock delay: slower playback (large characters) waits longer for the hand pose.
	delay /= speed
	var tree := get_tree()
	if tree == null:
		_fire_charged_blast_projectile()
		return
	tree.create_timer(delay).timeout.connect(
		func() -> void:
			if token != _blast_fire_token or not is_instance_valid(self):
				return
			_fire_charged_blast_projectile()
	)


func _fire_charged_blast_projectile() -> void:
	var origin := _spell_hand_origin()
	_laser_shot_origin = origin
	var aim_point := _blast_pending_aim
	if aim_point.distance_squared_to(origin) < 0.25:
		var fwd := -global_transform.basis.z
		if fwd.length_squared() > 0.0001:
			aim_point = origin + fwd.normalized() * 8.0
	var audio := _city_audio()
	if audio != null and audio.has_method("play_laser_fire"):
		audio.call("play_laser_fire", origin, character_scale)
	if _charged_blast != null and _charged_blast.has_method("fire"):
		_charged_blast.call(
			"fire",
			origin,
			aim_point,
			_blast_pending_radius,
			charged_blast_speed_mps,
			_effective_body_scale()
		)


func _start_laser_eyes_at_cursor() -> void:
	if _camera == null:
		return
	var now := Time.get_ticks_msec()
	if now < _laser_ready_at_msec:
		return
	if _eye_laser != null and bool(_eye_laser.call("is_firing")):
		return

	var aim_point := _aim_point_at_cursor()
	_laser_ready_at_msec = now + int(maxi(int(laser_cooldown_sec * 1000.0), 50))

	var origin := _laser_eye_origin()
	_laser_shot_origin = origin
	var audio := _city_audio()
	if audio != null and audio.has_method("play_laser_fire"):
		audio.call("play_laser_fire", origin, character_scale)
	if _eye_laser != null and _eye_laser.has_method("fire"):
		## Pass current body scale so dart length/thickness match the character.
		_eye_laser.call("fire", origin, aim_point, laser_speed_mps, _effective_body_scale())


func _city_root() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("resolve_laser_aim") and n.has_method("apply_laser_agent_hit"):
			return n
		n = n.get_parent()
	return null


func _start_melee_punch() -> void:
	if not has_action_animation(punch_anim):
		push_error("CityWalker: punch anim missing (%s)" % punch_anim)
		return
	play_action(punch_anim, false)
	_schedule_melee_impact(true, punch_impact_ratio)


func _start_melee_kick() -> void:
	if not has_action_animation(kick_anim):
		push_error("CityWalker: kick anim missing (%s)" % kick_anim)
		return
	play_action(kick_anim, false)
	_schedule_melee_impact(false, kick_impact_ratio)


func _start_stomp() -> void:
	var now := Time.get_ticks_msec()
	if now < _stomp_ready_at_msec:
		return
	if not has_action_animation(stomp_anim):
		push_error("CityWalker: stomp anim missing (%s)" % stomp_anim)
		return
	_stomp_ready_at_msec = now + int(maxi(int(stomp_cooldown_sec * 1000.0), 50))
	play_action(stomp_anim, false)
	_schedule_stomp_impact()


func _schedule_stomp_impact() -> void:
	_stomp_token += 1
	var token := _stomp_token
	var delay := 0.35
	var speed := 1.0
	if _anim_player != null:
		speed = maxf(_anim_player.speed_scale, 0.05)
		var path := "%s/%s" % [LIB_NAME, stomp_anim]
		if _anim_player.has_animation(path):
			var anim: Animation = _anim_player.get_animation(path)
			if anim != null:
				delay = maxf(anim.length * clampf(stomp_impact_ratio, 0.05, 0.95), 0.05)
	delay /= speed
	var tree := get_tree()
	if tree == null:
		_emit_stomp()
		return
	tree.create_timer(delay).timeout.connect(
		func() -> void:
			if token != _stomp_token or not is_instance_valid(self):
				return
			_emit_stomp()
	)


func _emit_stomp() -> void:
	var feet := _stomp_feet_origin()
	var radius := stomp_radius_at_scale_1 * character_scale
	add_camera_shake(stomp_shake_trauma * clampf(0.55 + 0.2 * character_scale, 0.55, 1.0))
	var audio := _city_audio()
	if audio != null and audio.has_method("play_laser_impact"):
		audio.call("play_laser_impact", feet, character_scale)
	stomp_requested.emit(feet, radius)


func _stomp_feet_origin() -> Vector3:
	var foot := _bone_world_pos(
		[&"LeftFoot", &"foot_l", &"RightFoot", &"foot_r", &"ball_l", &"ball_r"]
	)
	if foot.is_finite():
		return Vector3(global_position.x, foot.y, global_position.z)
	return global_position + Vector3(0.0, 0.08 * character_scale, 0.0)


func _schedule_melee_impact(is_punch: bool, ratio: float) -> void:
	_melee_strike_token += 1
	var token := _melee_strike_token
	var delay := 0.28
	if _anim_player != null:
		var path := "%s/%s" % [LIB_NAME, _action_anim]
		if _anim_player.has_animation(path):
			var anim: Animation = _anim_player.get_animation(path)
			if anim != null:
				delay = maxf(anim.length * clampf(ratio, 0.05, 0.95), 0.05)
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(delay).timeout.connect(
		func() -> void:
			if token != _melee_strike_token or not is_instance_valid(self):
				return
			_emit_melee_strike(is_punch)
	)


func _emit_melee_strike(is_punch: bool) -> void:
	var origin := _melee_origin(is_punch)
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3(0.0, 0.0, -1.0)
	else:
		forward = forward.normalized()
	## Slight downward bias for kicks so the foot voxel is preferred.
	if not is_punch:
		forward = (forward + Vector3(0.0, -0.12, 0.0)).normalized()
	var reach := melee_reach_m * character_scale
	melee_strike_requested.emit(origin, forward, reach)


func _melee_origin(is_punch: bool) -> Vector3:
	## Prefer live bone at impact time so the chisel lines up with the limb.
	if is_punch:
		var hand := _bone_world_pos(
			[&"RightHand", &"LeftHand", &"hand_r", &"hand_l", &"RightLowerArm", &"lowerarm_r"]
		)
		if hand.is_finite():
			return hand
		return global_position + Vector3(0.0, 1.22 * character_scale, 0.0)
	var foot := _bone_world_pos(
		[&"RightFoot", &"LeftFoot", &"RightToes", &"foot_r", &"foot_l", &"ball_r", &"ball_l"]
	)
	if foot.is_finite():
		return foot
	return global_position + Vector3(0.0, 0.22 * character_scale, 0.0)


func _bone_world_pos(names: Array) -> Vector3:
	if _skeleton == null or not is_instance_valid(_skeleton):
		return Vector3.INF
	_skeleton.force_update_all_bone_transforms()
	for n in names:
		var idx := _skeleton.find_bone(String(n))
		if idx < 0:
			continue
		return _skeleton.to_global(_skeleton.get_bone_global_pose(idx).origin)
	return Vector3.INF


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
