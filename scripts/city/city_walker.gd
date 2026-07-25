## Third-person city walker: MH body + Quaternius Idle/Walk (humanoid retarget).
class_name CityWalker
extends CharacterBody3D

signal blast_requested(hit_position: Vector3, collider: Object, radius_m: float)
## Melee strike: origin + flat facing direction, range in meters.
## CityRoot scales the carve diameter with character_scale (no break below 0.5×).
signal melee_strike_requested(origin: Vector3, direction: Vector3, max_range_m: float)
## Q stomp: feet world position + max charged-blast radius (destruction == blast).
signal stomp_requested(feet_position: Vector3, radius_m: float)
## Shared combat energy pool (0…energy_max).
signal energy_changed(current: float, maximum: float)
## M-key: aim a voxel infection meteor at hit_point (surface normal for VFX only).
signal meteor_requested(hit_point: Vector3, hit_normal: Vector3)
## T-key: summon a Game Boy Tetris machine at aim hit_point.
signal tetris_requested(hit_point: Vector3, hit_normal: Vector3)
## P-key: spawn a pedestrian at aim hit_point (plays nearby Tetris if present).
signal pedestrian_requested(hit_point: Vector3, hit_normal: Vector3)

const CharacterEditorScript := preload("res://scripts/city/character_editor.gd")
const ProportionModifierScript := preload("res://scripts/humans/proportion_modifier.gd")
const BodyProportionsScript := preload("res://scripts/humans/body_proportions.gd")
const EyeLaserVfxScript := preload("res://scripts/city/eye_laser_vfx.gd")
const BlasterBoltVfxScript := preload("res://scripts/city/blaster_bolt_vfx.gd")
const ChargedBlastVfxScript := preload("res://scripts/city/charged_blast_vfx.gd")
const PlayerControlsScript := preload("res://scripts/city/player_controls.gd")
const VoxelBodyMotionScript := preload("res://scripts/city/voxel_body_motion.gd")

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
const ANIM_JUMP_START := &"Jump_Start"
const ANIM_JUMP_LOOP := &"Jump_Loop"
const ANIM_JUMP_LAND := &"Jump_Land"
const LIB_NAME := &"quat"

@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
## Hold jump to keep rising; release or hit max height to fall. Meters at scale 1.0.
@export var jump_height_max_m: float = 10.0
## Upward speed while the jump key is held (m/s at scale 1.0).
@export var jump_rise_speed_mps: float = 9.0
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
@export var stomp_cooldown_sec: float = 0.85
@export var stomp_shake_trauma: float = 0.72
@export var camera_shake_max_offset_m: float = 0.28
@export var camera_shake_max_roll_deg: float = 4.5
@export var camera_shake_decay: float = 1.35
## Ctrl+LMB laser: click aim, punch/kick carve power, meters.
@export var laser_range_m: float = 100.0
@export var laser_cooldown_sec: float = 0.45
@export var laser_speed_mps: float = 60.0
## LMB blaster: hold for intermittent bolts; same carve as eye laser each shot.
@export var blaster_speed_mps: float = 30.0
@export var blaster_interval_sec: float = 0.25
## Shared energy pool for combat abilities.
@export var energy_max: float = 100.0
## Base regen at character_scale 1.0 (capped — smaller sizes do not regen faster).
## Larger size slows it: scale 5 → 1 energy every 5 seconds.
@export var energy_regen_per_sec: float = 1.0
@export var energy_cost_laser: float = 1.0
@export var energy_cost_blaster: float = 1.0
@export var energy_cost_stomp: float = 10.0
@export var energy_cost_blast: float = 20.0
## Hold LMB for blaster. Alt+LMB charges the bomb; Q stomps; Ctrl+LMB laser.
@export var charged_blast_speed_mps: float = 10.0
@export var charged_blast_charge_sec: float = 1.6
@export var charged_blast_radius_min_m: float = 0.54
@export var charged_blast_radius_max_m: float = 2.52
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
## Mixamo climb loops (baked as *_m).
@export var climb_up_anim: String = "Climbing_m"
@export var climb_down_anim: String = "Climbing_Down_m"
## Vertical climb speed at character_scale 1.0.
@export var climb_speed: float = 1.15
@export var climb_anim_speed: float = 1.2
## Sideways climb speed along the facade (A/D) at character_scale 1.0.
@export var climb_strafe_speed: float = 1.15
## Keep the capsule lightly pressed into the wall while climbing.
@export var climb_wall_stick: float = 0.28
## Extra clearance beyond capsule radius — too tight buries the spring arm in the facade.
@export var climb_standoff_m: float = 0.34
## How long forward motion must be blocked before a non-sprint wall-run starts climbing.
@export var climb_start_stuck_sec: float = 0.1
## Wall must still register this far above the chest (filters curbs).
@export var climb_min_wall_m: float = 1.15
## Backward drop depth that triggers climb-down (meters).
@export var climb_drop_depth_m: float = 0.85
@export var climb_probe_m: float = 0.85

## Capsule sole sits this far above the CharacterBody origin — constant at every size.
const CAPSULE_FOOT_CLEARANCE := 0.05
const FLOOR_SNAP_M := 0.2
const SAFE_MARGIN_M := 0.06
const SPRING_MARGIN_DEFAULT := 0.2
const SPRING_MARGIN_CLIMB := 0.55

enum ClimbMode { NONE, UP, DOWN }

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
var _game_over_locked: bool = false
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
var _coyote_left: float = 0.0
var _jumping: bool = false
## True while ascending under a held jump (until release or max height).
var _jump_rising: bool = false
var _jump_start_y: float = 0.0
var _was_airborne: bool = false
var _land_anim_left: float = 0.0
var _safety_deck: StaticBody3D
## Hold forward without pressing W (toggle with R).
var _auto_run: bool = false
## Void rescue only — top of the indestructible bedrock band (voxel y=0 → 0.5 m).
## Must stay below diggable stone so stomped craters are enterable.
const VOID_FLOOR_TOP_Y := 0.5
## Street deck top (ground_thickness=6 → world y 3.5). Climb-down needs a real drop.
const STREET_DECK_TOP_Y := 3.5
## Physics layer 8 — player safety deck only (not voxel terrain layer 1).
const SAFETY_DECK_LAYER := 128
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
## Live voxel AABB motion — digs/holes match voxel data immediately (no remesh wait).
var _voxel_motion: RefCounted = VoxelBodyMotionScript.new()
var _last_applied_motion: Vector3 = Vector3.ZERO
var _eye_laser: Node
var _charged_blast: Node
var _laser_ready_at_msec: int = 0
var _laser_shot_origin: Vector3 = Vector3.ZERO
var _blast_charge: float = 0.0
var _blast_ready_at_msec: int = 0
## True while LMB is held for the bomb — charge until release fires it.
var _blast_charging: bool = false
## True while LMB blaster beam is held.
var _blaster_holding: bool = false
var _blaster_accum: float = 0.0
var _live_blaster_bolts: Array[Node] = []
var _energy: float = 100.0
var _blast_fire_token: int = 0
var _blast_pending_aim: Vector3 = Vector3.ZERO
var _blast_pending_radius: float = 1.0
var _controls: PlayerControls
var _charge_orb: Node3D
var _charge_orb_core: MeshInstance3D
var _charge_orb_mesh: SphereMesh
var _charge_orb_mat: StandardMaterial3D
var _charge_orb_light: OmniLight3D
var _charge_ring_a: MeshInstance3D
var _charge_ring_b: MeshInstance3D
var _charge_ring_mesh_a: TorusMesh
var _charge_ring_mesh_b: TorusMesh
var _charge_ring_mat_a: StandardMaterial3D
var _charge_ring_mat_b: StandardMaterial3D
var _footstep_accum: float = 0.0
var _climb_mode: ClimbMode = ClimbMode.NONE
## Outward wall normal (flattened) while climbing.
var _climb_wall_n: Vector3 = Vector3.ZERO
## After starting climb-down, ignore ground so the roof lip doesn't cancel the hang.
var _climb_ignore_ground_sec: float = 0.0
## Brief forgiveness when a wall ray misses between voxel faces.
var _climb_wall_grace_sec: float = 0.0
## Body mesh Y + foot-align flag captured before climb (climb crouch must not bake in).
var _pre_climb_body_y: float = 0.0
var _pre_climb_feet_aligned: bool = false
## After climb, force zero-blend locomotion so Mixamo bone leans don't persist.
var _climb_pose_clear_sec: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_zoom = zoom_default
	_energy = energy_max
	collision_layer = 2
	## Walking uses VoxelBoxMover against live voxels — do not collide with remeshed
	## terrain (layer 1) or stale dig colliders fight the real shape. Safety deck only.
	## Climb temporarily re-enables terrain (see _set_physics_terrain_collision).
	collision_mask = SAFETY_DECK_LAYER
	floor_snap_length = 0.0
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
	_spring.margin = SPRING_MARGIN_DEFAULT
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


func is_blocking_ui_open() -> bool:
	if _game_over_locked:
		return true
	if is_character_editor_open():
		return true
	var parent := get_parent()
	return parent != null and parent.has_method("is_settings_open") and bool(parent.call("is_settings_open"))


func set_game_over_locked(on: bool) -> void:
	_game_over_locked = on
	if on:
		_end_jump_rise()
		_jumping = false
		if _climb_mode != ClimbMode.NONE:
			_end_climb(false)
		_auto_run = false
		_set_rmb_looking(false)
		_set_capture(false)
		velocity = Vector3.ZERO
		## Stop combat VFX mid-flight so death doesn't feel like a soft lock.
		if _eye_laser != null and is_instance_valid(_eye_laser) and _eye_laser.has_method("cancel"):
			_eye_laser.call("cancel")
		if _charged_blast != null and is_instance_valid(_charged_blast) and _charged_blast.has_method("cancel"):
			_charged_blast.call("cancel")
		_stop_blaster(true)
		_blast_charging = false
		_blast_charge = 0.0
		var audio := _city_audio()
		if audio != null and audio.has_method("stop_charged_blast_charge"):
			audio.call("stop_charged_blast_charge")


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
	if _voxel_motion != null and _voxel_motion.has_method("set_max_step_height"):
		## Step height stays absolute meters (curbs), not scaled with character size.
		_voxel_motion.call("set_max_step_height", max_step_height)
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
		if (
			key == String(ANIM_IDLE)
			or key == String(ANIM_WALK)
			or key == String(ANIM_SPRINT)
			or key == String(ANIM_JUMP_LOOP)
			or key == "Crouch_Idle"
			or key == "Crouch_Idle_Loop"
		):
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
		## Climb loops are driven by locomotion, not the action bar.
		if key.begins_with("Climbing"):
			copy.loop_mode = Animation.LOOP_LINEAR
		if library.has_animation(key):
			library.remove_animation(key)
		library.add_animation(key, copy)
		if not key.begins_with("Climbing") and _action_names.find(key) < 0:
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


func get_energy() -> float:
	return _energy


func get_energy_max() -> float:
	return energy_max


func try_spend_energy(cost: float) -> bool:
	if cost <= 0.0:
		return true
	if _energy + 0.0001 < cost:
		return false
	_energy = maxf(_energy - cost, 0.0)
	energy_changed.emit(_energy, energy_max)
	return true


func _regen_energy(delta: float) -> void:
	if _game_over_locked or _energy >= energy_max:
		return
	## 1/s at scale 1; scale N → 1 energy every N seconds (never faster than base).
	var rate := energy_regen_per_sec / maxf(character_scale, 1.0)
	var prev := _energy
	_energy = minf(_energy + rate * delta, energy_max)
	if not is_equal_approx(prev, _energy):
		energy_changed.emit(_energy, energy_max)


func play_action(anim_name: String, allow_toggle: bool = true) -> void:
	if _climb_mode != ClimbMode.NONE:
		return
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
	if _body_root == null or _skeleton == null or not _floor_contacted():
		return
	## Never measure from a crouched climb pose — that ducks the mesh permanently.
	if _climb_mode != ClimbMode.NONE:
		return
	if _anim_player != null:
		var cur := String(_anim_player.current_animation)
		if cur.contains("Climbing"):
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


func set_controls(controls: PlayerControls) -> void:
	_controls = controls


func bind_terrain(terrain: VoxelTerrain) -> void:
	_voxel_motion.call("setup", terrain, max_step_height)


func _floor_contacted() -> bool:
	if _voxel_motion != null and bool(_voxel_motion.call("has_terrain")):
		return bool(_voxel_motion.call("is_on_floor"))
	return is_on_floor() or _was_ray_grounded


func _set_physics_terrain_collision(enabled: bool) -> void:
	## Climb still uses CharacterBody slide against remeshed facades.
	if enabled:
		collision_mask = 1 | SAFETY_DECK_LAYER
	else:
		collision_mask = SAFETY_DECK_LAYER


func _ctl() -> PlayerControls:
	if _controls == null:
		_controls = PlayerControlsScript.new() as PlayerControls
	return _controls


func _unhandled_input(event: InputEvent) -> void:
	if is_blocking_ui_open():
		return
	var ctl := _ctl()
	if event is InputEventKey and not event.echo:
		var ek := event as InputEventKey
		if ek.pressed and ctl.matches_key_pressed(ek, "jump"):
			if _climb_mode != ClimbMode.NONE:
				_end_climb(true)
			else:
				_try_start_jump()
			get_viewport().set_input_as_handled()
			return
		if not ek.pressed and ctl.matches_key_released(ek, "jump"):
			_end_jump_rise()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		var ek := event as InputEventKey
		if ctl.matches_key_pressed(ek, "character_editor"):
			toggle_character_editor()
			get_viewport().set_input_as_handled()
			return
		if ctl.matches_key_pressed(ek, "autorun"):
			_auto_run = not _auto_run
			get_viewport().set_input_as_handled()
			return
		if ctl.matches_key_pressed(ek, "sound_toggle"):
			_toggle_sound()
			get_viewport().set_input_as_handled()
			return
		if ctl.matches_key_pressed(ek, "meteor"):
			_request_infection_meteor()
			get_viewport().set_input_as_handled()
			return
		if ctl.matches_key_pressed(ek, "tetris"):
			_request_tetris_machine()
			get_viewport().set_input_as_handled()
			return
		if ctl.matches_key_pressed(ek, "pedestrian"):
			_request_pedestrian()
			get_viewport().set_input_as_handled()
			return
		if ctl.matches_key_pressed(ek, "undead_radar"):
			_request_undead_radar()
			get_viewport().set_input_as_handled()
			return
		if ctl.matches_key_pressed(ek, "district_hop"):
			_request_district_hop()
			get_viewport().set_input_as_handled()
			return
		if ctl.matches_key_pressed(ek, "laser"):
			_stop_blaster(false)
			_blast_charging = false
			_blast_charge = 0.0
			_start_laser_eyes_at_cursor()
			get_viewport().set_input_as_handled()
			return
		if ctl.matches_key_pressed(ek, "beam"):
			_blast_charging = false
			_blast_charge = 0.0
			_begin_blaster_hold()
			get_viewport().set_input_as_handled()
			return
		if ctl.matches_key_pressed(ek, "stomp"):
			_stop_blaster(false)
			_blast_charging = false
			_blast_charge = 0.0
			_start_stomp()
			get_viewport().set_input_as_handled()
			return
		if ctl.matches_key_pressed(ek, "fire"):
			_stop_blaster(false)
			_begin_charged_blast_hold()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and not event.pressed:
		## Release charged blast when fire is a key bind.
		if _blast_charging and str(ctl.get_binding("fire").get("device", "")) == "key":
			var code := int(ctl.get_binding("fire").get("code", -1)) as Key
			if (event as InputEventKey).keycode == code:
				_release_charged_blast_at_cursor()
				get_viewport().set_input_as_handled()
				return
		if _blaster_holding and str(ctl.get_binding("beam").get("device", "")) == "key":
			var beam_code := int(ctl.get_binding("beam").get("code", -1)) as Key
			if (event as InputEventKey).keycode == beam_code:
				_stop_blaster(false)
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
		if mb.pressed and ctl.matches_mouse(mb, "zoom_in"):
			_zoom = clampf(_zoom - zoom_step, zoom_min, zoom_max)
			_spring.spring_length = _zoom
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and ctl.matches_mouse(mb, "zoom_out"):
			_zoom = clampf(_zoom + zoom_step, zoom_min, zoom_max)
			_spring.spring_length = _zoom
			get_viewport().set_input_as_handled()
			return
		var look_bind := ctl.get_binding("look")
		if str(look_bind.get("device", "")) == "mouse" and int(mb.button_index) == int(look_bind.get("code", -1)):
			## Look hold ignores modifiers so Shift+RMB still orbits.
			if mb.pressed:
				_set_rmb_looking(true)
			else:
				_set_rmb_looking(false)
			get_viewport().set_input_as_handled()
			return
		var fire_bind := ctl.get_binding("fire")
		var fire_btn := (
			str(fire_bind.get("device", "")) == "mouse"
			and int(mb.button_index) == int(fire_bind.get("code", -2))
		)
		var beam_bind := ctl.get_binding("beam")
		var beam_btn := (
			str(beam_bind.get("device", "")) == "mouse"
			and int(mb.button_index) == int(beam_bind.get("code", -2))
		)
		if mb.pressed:
			var combat := ctl.resolve_mouse_action(
				mb, ["laser", "beam", "fire"] as Array[String]
			)
			if combat.is_empty():
				return
			match combat:
				"laser":
					_stop_blaster(false)
					_blast_charging = false
					_blast_charge = 0.0
					_start_laser_eyes_at_cursor()
				"beam":
					_blast_charging = false
					_blast_charge = 0.0
					_begin_blaster_hold()
				"fire":
					_stop_blaster(false)
					_begin_charged_blast_hold()
			get_viewport().set_input_as_handled()
		elif beam_btn and _blaster_holding:
			_stop_blaster(false)
			get_viewport().set_input_as_handled()
		elif fire_btn and _blast_charging:
			_release_charged_blast_at_cursor()
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
	_regen_energy(delta)
	if is_blocking_ui_open():
		velocity.x = 0.0
		velocity.z = 0.0
		_end_jump_rise()
		if not _floor_contacted():
			var gravity_edit: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
			velocity.y -= gravity_edit * delta
		else:
			velocity.y = 0.0
			if not _feet_aligned and _skeleton != null and character_scale < ray_ground_scale:
				_align_soles_to_floor()
		_apply_body_motion(delta)
		_apply_camera_angles()
		return

	var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	var ray_mode := character_scale >= ray_ground_scale
	if _land_anim_left > 0.0:
		_land_anim_left = maxf(_land_anim_left - delta, 0.0)
	## Voxel motion owns contact; CharacterBody floor-snap stays off.
	floor_snap_length = 0.0

	var ctl := _ctl()
	## Look up / down (held = continuous).
	var pitch_input := 0.0
	if ctl.is_key_held("look_up"):
		pitch_input += 1.0
	if ctl.is_key_held("look_down"):
		pitch_input -= 1.0
	if not is_zero_approx(pitch_input):
		_pitch = clampf(_pitch + pitch_input * pitch_rate * delta, pitch_min, pitch_max)

	## Turn on ground; while climbing these keys strafe along the wall.
	var turn := 0.0
	if ctl.is_key_held("turn_left"):
		turn += 1.0
	if ctl.is_key_held("turn_right"):
		turn -= 1.0
	if not is_zero_approx(turn) and _climb_mode == ClimbMode.NONE:
		rotation.y += turn * keyboard_turn_rate * delta

	## Move only along body facing.
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	else:
		forward = Vector3(0.0, 0.0, -1.0)

	var forward_held := ctl.is_key_held("move_forward") or _auto_run
	var back_held := ctl.is_key_held("move_back")
	if back_held and _auto_run:
		_auto_run = false

	if _climb_mode != ClimbMode.NONE:
		_end_jump_rise()
		## Turn-left = strafe left (−), turn-right = strafe right (+) on the wall.
		var strafe := -turn
		_physics_climb(delta, forward, forward_held, back_held, strafe)
		return

	_set_physics_terrain_collision(false)
	var grounded := _floor_contacted()
	if grounded and not _jumping:
		_coyote_left = coyote_time_sec
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		_coyote_left = maxf(_coyote_left - delta, 0.0)
		velocity.y -= gravity * delta

	var input_dir := Vector2.ZERO
	if forward_held:
		input_dir.y -= 1.0
	if back_held:
		input_dir.y += 1.0

	var wish := forward * (-input_dir.y)
	wish.y = 0.0

	var sprinting := ctl.is_key_held("sprint")
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

	_update_jump_rise(delta)

	## Climb-down must arm BEFORE we walk off the lip — otherwise we only fall.
	if not ray_mode and not _jump_rising and back_held and not forward_held:
		if _try_begin_climb_down(forward):
			_apply_camera_angles()
			_update_camera_shake(delta)
			return

	## Curb steps are handled inside VoxelBoxMover (max_step_height).
	var wish_speed := speed if _moving else 0.0
	_apply_body_motion(delta)
	_stabilize_vertical(ray_mode)
	_update_stuck_timer(delta, wish_speed)
	## Auto-recover without jumping — still horizontal-only + one ground snap.
	if _stuck_timer >= stuck_time_sec:
		if _unstuck_horizontal():
			_stuck_timer = 0.0

	var airborne_now := not _floor_contacted()
	if _jumping and _floor_contacted() and velocity.y <= 0.0:
		_jumping = false
		_jump_rising = false
	if _was_airborne and not airborne_now:
		_play_jump_land_anim()
	_was_airborne = airborne_now or _jumping

	## Climb-up after this frame's stuck/slide state is known.
	## Air-grab climb-down if we already stepped off while holding S.
	## Don't steal the jump — Space is jump, climb is walk-into-wall.
	if not ray_mode and not _jumping and not _jump_rising:
		if forward_held and not back_held and _try_begin_climb_up(forward, sprinting):
			_apply_camera_angles()
			_update_camera_shake(delta)
			return
		if back_held and not forward_held and _try_begin_climb_down(forward):
			_apply_camera_angles()
			_update_camera_shake(delta)
			return

	_update_safety_deck()
	_apply_camera_angles()
	_update_camera_shake(delta)
	if _climb_pose_clear_sec > 0.0:
		_climb_pose_clear_sec = maxf(_climb_pose_clear_sec - delta, 0.0)
	_update_locomotion_anim(speed, sprinting)
	_update_footstep_sfx(delta, speed)
	_update_blast_charge(delta, _blast_charging)
	_update_blaster(delta)

	if not ray_mode and _floor_contacted() and not _feet_aligned and _skeleton != null:
		_align_soles_to_floor()
	## Absolute floor — never fall through the world into the void.
	if global_position.y < VOID_FLOOR_TOP_Y - 0.15:
		global_position.y = VOID_FLOOR_TOP_Y
		velocity.y = 0.0
		_was_ray_grounded = true
	if _unstuck_cooldown > 0.0:
		_unstuck_cooldown = maxf(_unstuck_cooldown - delta, 0.0)


func _physics_climb(
	delta: float,
	_forward: Vector3,
	forward_held: bool,
	back_held: bool,
	strafe: float
) -> void:
	_set_physics_terrain_collision(true)
	## Jump press already cancels climb in _unhandled_input.

	_climb_ignore_ground_sec = maxf(_climb_ignore_ground_sec - delta, 0.0)

	var into := -_climb_wall_n
	into.y = 0.0
	if into.length_squared() > 0.0001:
		into = into.normalized()
	else:
		into = -_forward

	## Character right while facing the wall — A/D slide along the facade.
	var right := into.cross(Vector3.UP)
	right.y = 0.0
	if right.length_squared() > 0.0001:
		right = right.normalized()
	else:
		right = Vector3.RIGHT

	var climb_v := climb_speed * character_scale
	var strafe_v := climb_strafe_speed * character_scale * strafe
	var vel := Vector3(into.x * climb_wall_stick, 0.0, into.z * climb_wall_stick)
	vel += right * strafe_v

	if _climb_mode == ClimbMode.UP:
		## Keep climbing while holding forward; release to hang/slide slowly.
		if forward_held or _auto_run:
			vel.y = climb_v
		elif back_held:
			## S while climbing up switches to climb-down on the same face.
			_climb_mode = ClimbMode.DOWN
			_climb_ignore_ground_sec = maxf(_climb_ignore_ground_sec, 0.2)
			_play_climb_anim()
			vel.y = -climb_v
		else:
			vel.y = 0.0
	else:
		## Climbing down: S continues, W switches back to up.
		if back_held:
			vel.y = -climb_v
		elif forward_held or _auto_run:
			_climb_mode = ClimbMode.UP
			_play_climb_anim()
			vel.y = climb_v
		else:
			vel.y = 0.0

	velocity = vel
	_moving = absf(vel.y) > 0.05 or absf(strafe) > 0.01
	floor_snap_length = 0.0
	move_and_slide()

	## Prefer wall contact slightly toward the strafe so corners wrap cleanly.
	var probe_dir := into
	if absf(strafe) > 0.01:
		probe_dir = (into + right * strafe * 0.35).normalized()
	var fresh := _probe_wall(probe_dir, 0.85 * character_scale, climb_probe_m + 0.45)
	if fresh.is_empty():
		fresh = _probe_wall(into, 0.4 * character_scale, climb_probe_m + 0.45)
	if not fresh.is_empty():
		var n: Vector3 = fresh.normal
		n.y = 0.0
		if n.length_squared() > 0.0001:
			_climb_wall_n = n.normalized()
			_face_into_wall(_climb_wall_n)
		_climb_wall_grace_sec = 0.28
		## Hold a clear standoff — hard-snapping to radius+ε buries the spring in the wall.
		var hit_pos: Vector3 = fresh.position
		var desired := hit_pos + _climb_wall_n * _climb_hold_distance()
		## Soft XZ pull so we track the face without vibrating into voxels.
		global_position.x = lerpf(global_position.x, desired.x, 0.45)
		global_position.z = lerpf(global_position.z, desired.z, 0.45)
	else:
		_climb_wall_grace_sec = maxf(_climb_wall_grace_sec - delta, 0.0)
		if _climb_wall_grace_sec <= 0.0 and not _climb_has_wall_contact(into):
			_end_climb(true)
			_apply_camera_angles()
			_update_camera_shake(delta)
			return

	if _climb_mode == ClimbMode.UP and _try_mount_ledge(into):
		_apply_camera_angles()
		_update_camera_shake(delta)
		return

	if (
		_climb_mode == ClimbMode.DOWN
		and _climb_ignore_ground_sec <= 0.0
		and _climb_reached_ground()
	):
		_end_climb(false)
		_apply_camera_angles()
		_update_camera_shake(delta)
		return

	_update_safety_deck()
	_apply_camera_angles()
	_update_camera_shake(delta)
	_play_climb_anim()
	_update_blast_charge(delta, false)
	if global_position.y < VOID_FLOOR_TOP_Y - 0.15:
		global_position.y = VOID_FLOOR_TOP_Y
		_end_climb(false)


func _try_begin_climb_up(forward: Vector3, sprinting: bool) -> bool:
	if _climb_mode != ClimbMode.NONE:
		return false
	if character_scale >= ray_ground_scale:
		return false
	if not _floor_contacted():
		return false
	## Running into a wall, or pressing into it long enough to stick.
	if not sprinting and _stuck_timer < climb_start_stuck_sec:
		return false
	var wall := _find_climb_wall(forward)
	if wall.is_empty():
		## Capsule already grinding a vertical face — start climb from that contact
		## even if a single ray slipped through a seam.
		var n := _wall_outward_normal()
		if n == Vector3.ZERO or n.dot(forward) > -0.35:
			return false
		var head_y := 0.95 * character_scale + maxf(climb_min_wall_m, max_step_height * 2.8)
		if _probe_wall(forward, head_y, climb_probe_m + 0.1).is_empty():
			return false
		_start_climb(ClimbMode.UP, n)
		return true
	_start_climb(ClimbMode.UP, wall["normal"] as Vector3)
	return true


func _try_begin_climb_down(forward: Vector3) -> bool:
	if _climb_mode != ClimbMode.NONE:
		return false
	if character_scale >= ray_ground_scale:
		return false
	## Must be high enough that a drop exists (not sidewalk / curb).
	if global_position.y < STREET_DECK_TOP_Y + climb_drop_depth_m * 0.75:
		return false

	var grounded := _floor_contacted()
	## Allow a short air-grab after stepping off, or while falling beside a facade.
	var air_ok := (not grounded) and (_coyote_left > 0.0 or velocity.y <= 0.35)
	if not grounded and not air_ok:
		return false

	var back := -forward
	var r := _capsule_radius()
	## Confirm there is a real drop behind the feet (or already in the air over void).
	if grounded:
		if not _has_climb_drop_behind(back, r):
			return false

	var wall := _find_climb_down_wall(forward, back, r)
	if wall.is_empty():
		return false
	var n: Vector3 = wall["normal"] as Vector3
	var hit_pos: Vector3 = wall["position"] as Vector3
	_start_climb(ClimbMode.DOWN, n)
	## Hang outside the facade with real clearance (not flush) so the camera spring is free.
	var hang := hit_pos + n * _climb_hold_distance()
	hang.y = minf(global_position.y - 0.35 * character_scale, hit_pos.y)
	hang.y = minf(hang.y, global_position.y - 0.15 * character_scale)
	global_position = hang
	_climb_ignore_ground_sec = 0.45
	_climb_wall_grace_sec = 0.35
	## Drift outward slightly, not into the wall.
	velocity = Vector3(n.x * 0.35, -climb_speed * character_scale, n.z * 0.35)
	return true


func _climb_hold_distance() -> float:
	return _capsule_radius() + climb_standoff_m * maxf(character_scale, 1.0)


func _has_climb_drop_behind(back: Vector3, radius: float) -> bool:
	## Several probes past the heels — any deep void/step counts as a climbable drop.
	var offsets: Array[float] = [radius + 0.2, radius + 0.45, radius + 0.75]
	for dist in offsets:
		var probe := global_position + back * dist + Vector3(0.0, 0.25 * character_scale, 0.0)
		var down := _ray_query(probe, probe + Vector3(0.0, -(climb_drop_depth_m + 1.25), 0.0))
		if down.is_empty():
			return true
		var drop := global_position.y - (down.position as Vector3).y
		if drop >= climb_drop_depth_m:
			return true
	return false


func _find_climb_down_wall(forward: Vector3, back: Vector3, radius: float) -> Dictionary:
	## The facade sits BELOW the roof lip. Cast from over the void back into the building
	## at several heights so we hit the vertical face, not the rooftop slab.
	var cast_dists: Array[float] = [
		radius + 0.15,
		radius + 0.4,
		radius + 0.7,
		radius + 1.05,
	]
	var y_below: Array[float] = [
		0.15 * character_scale,
		0.4 * character_scale,
		0.75 * character_scale,
		1.15 * character_scale,
		1.6 * character_scale,
	]
	for dist in cast_dists:
		for y_off in y_below:
			var from := global_position + back * dist + Vector3(0.0, -y_off, 0.0)
			## Toward the building (forward).
			var to := from + forward * (climb_probe_m + radius + 0.55)
			var hit := _ray_query(from, to)
			if hit.is_empty():
				## Angle slightly down in case the lip sits between samples.
				to = from + (forward * (climb_probe_m + radius + 0.4) + Vector3(0.0, -0.35, 0.0))
				hit = _ray_query(from, to)
			if hit.is_empty():
				continue
			var n: Vector3 = hit.normal
			n.y = 0.0
			if n.length_squared() < 0.0001:
				continue
			n = n.normalized()
			## Outward normal should point roughly toward the drop (back).
			if n.dot(back) < 0.2:
				continue
			## Reject near-horizontal hits (roof tops).
			var raw_n: Vector3 = hit.normal
			if absf(raw_n.y) > 0.55:
				continue
			return {"normal": n, "position": hit.position as Vector3}
	return {}


func _start_climb(mode: ClimbMode, wall_n: Vector3) -> void:
	cancel_action()
	_blast_charging = false
	_set_physics_terrain_collision(true)
	_climb_mode = mode
	_climb_wall_n = wall_n
	_climb_wall_n.y = 0.0
	if _climb_wall_n.length_squared() > 0.0001:
		_climb_wall_n = _climb_wall_n.normalized()
	_stuck_timer = 0.0
	_coyote_left = 0.0
	_was_ray_grounded = false
	_end_jump_rise()
	_jumping = false
	## Remember standing height — never re-align soles from the crouched climb pose.
	_pre_climb_body_y = _body_root.position.y if _body_root != null else _body_base_y
	_pre_climb_feet_aligned = _feet_aligned
	_climb_wall_grace_sec = 0.3
	if mode == ClimbMode.DOWN:
		_climb_ignore_ground_sec = maxf(_climb_ignore_ground_sec, 0.35)
	else:
		_climb_ignore_ground_sec = 0.0
	_face_into_wall(_climb_wall_n)
	velocity = Vector3.ZERO
	_set_climb_camera_margin(true)
	_play_climb_anim()


func _end_climb(push_off: bool) -> void:
	var n := _climb_wall_n
	_climb_mode = ClimbMode.NONE
	_climb_wall_n = Vector3.ZERO
	_climb_ignore_ground_sec = 0.0
	_climb_wall_grace_sec = 0.0
	_moving = false
	_set_physics_terrain_collision(false)
	_set_climb_camera_margin(false)
	_restore_body_after_climb()
	if push_off and n.length_squared() > 0.0001:
		## Small outward hop so we don't immediately re-stick.
		velocity = n.normalized() * (1.6 * character_scale) + Vector3(0.0, 0.6 * character_scale, 0.0)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if velocity.y > 0.0:
			velocity.y = 0.0
	## Hard-cut climb pose — Mixamo keys bones Quaternius loco may not overwrite.
	_play_post_climb_locomotion()


func _set_climb_camera_margin(climbing: bool) -> void:
	if _spring == null:
		return
	## Extra margin while on a facade — flush hangs made the spring length chatter.
	_spring.margin = SPRING_MARGIN_CLIMB if climbing else SPRING_MARGIN_DEFAULT


func _restore_body_after_climb() -> void:
	## Climbing leaves knees bent; sole-align from that pose ducks the mesh permanently.
	if _body_root != null:
		_body_root.position.y = _pre_climb_body_y
	_body_base_y = _pre_climb_body_y
	_feet_aligned = _pre_climb_feet_aligned


func _play_post_climb_locomotion() -> void:
	if _anim_player == null:
		return
	## Drop climb immediately (no blend keep-state), then restore bind pose for any
	## bones Idle/Walk don't key — otherwise hips/spine lean sticks forever.
	_anim_player.stop()
	if _skeleton != null:
		_skeleton.reset_bone_poses()
	var idle_path := "%s/%s" % [LIB_NAME, ANIM_IDLE]
	var walk_path := "%s/%s" % [LIB_NAME, ANIM_WALK]
	var path := walk_path if _moving and _anim_player.has_animation(walk_path) else idle_path
	if not _anim_player.has_animation(path):
		if _anim_player.has_animation(idle_path):
			path = idle_path
		else:
			_climb_pose_clear_sec = 0.25
			return
	_anim_player.play(path, 0.0)
	_anim_player.seek(0.0, true)
	_anim_player.speed_scale = clampf(1.0 / maxf(character_scale, 0.001), 0.05, 4.0)
	if _skeleton != null:
		_skeleton.force_update_all_bone_transforms()
	_climb_pose_clear_sec = 0.35


func _face_into_wall(wall_n: Vector3) -> void:
	## Face the wall (forward = into the facade = -outward normal).
	var look := -wall_n
	look.y = 0.0
	if look.length_squared() < 0.0001:
		return
	look = look.normalized()
	rotation.y = atan2(-look.x, -look.z)


func _play_climb_anim() -> void:
	if _anim_player == null:
		return
	## Climb-down uses the up clip reversed — the dedicated down clip looks off.
	var path := "%s/%s" % [LIB_NAME, climb_up_anim]
	if not _anim_player.has_animation(path):
		path = "%s/%s" % [LIB_NAME, &"Jump_Loop"]
		if not _anim_player.has_animation(path):
			return
	var going_down := _climb_mode == ClimbMode.DOWN
	if _anim_player.current_animation != path:
		## from_end so reverse starts at the top of the cycle.
		_anim_player.play(path, 0.12, 1.0, going_down)
	var size_anim := clampf(1.0 / maxf(character_scale, 0.001), 0.05, 4.0)
	var moving_scale := climb_anim_speed if _moving else climb_anim_speed * 0.15
	var signed := moving_scale * size_anim
	## Negative playback = climb down.
	_anim_player.speed_scale = (-signed if going_down else signed)


func _find_climb_wall(forward: Vector3) -> Dictionary:
	var chest_y := 0.95 * character_scale
	var hit := _probe_wall(forward, chest_y, climb_probe_m)
	if hit.is_empty():
		hit = _probe_wall(forward, 0.55 * character_scale, climb_probe_m)
	## Side offsets: a single centre ray can miss a thin seam between panes / bricks.
	if hit.is_empty():
		var side := Vector3(-forward.z, 0.0, forward.x)
		for sign_s in [-1.0, 1.0]:
			hit = _probe_wall_from(
				global_position + side * (0.22 * character_scale * sign_s),
				forward,
				chest_y,
				climb_probe_m
			)
			if not hit.is_empty():
				break
	if hit.is_empty():
		return {}
	var n: Vector3 = hit.normal
	n.y = 0.0
	if n.length_squared() < 0.0001:
		return {}
	n = n.normalized()
	## Wall must face the player (we're running into it).
	if n.dot(forward) > -0.35:
		return {}
	## Tall enough that curb-step won't handle it.
	var head_y := chest_y + maxf(climb_min_wall_m, max_step_height * 2.8)
	var head := _probe_wall(forward, head_y, climb_probe_m + 0.1)
	if head.is_empty():
		## Head probe also gets a side try — ribbon windows leave lintels off-centre.
		var side2 := Vector3(-forward.z, 0.0, forward.x)
		for sign_h in [-1.0, 1.0]:
			head = _probe_wall_from(
				global_position + side2 * (0.22 * character_scale * sign_h),
				forward,
				head_y,
				climb_probe_m + 0.1
			)
			if not head.is_empty():
				break
	if head.is_empty():
		return {}
	return {"normal": n, "hit": hit}


func _probe_wall(dir: Vector3, from_y: float, dist: float) -> Dictionary:
	return _probe_wall_from(global_position, dir, from_y, dist)


func _probe_wall_from(origin: Vector3, dir: Vector3, from_y: float, dist: float) -> Dictionary:
	var d := dir
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return {}
	d = d.normalized()
	var from := origin + Vector3(0.0, from_y, 0.0)
	return _ray_query(from, from + d * dist)


func _ray_query(from: Vector3, to: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1
	var exclude: Array[RID] = [get_rid()]
	if _safety_deck != null and is_instance_valid(_safety_deck):
		exclude.append(_safety_deck.get_rid())
	q.exclude = exclude
	return space.intersect_ray(q)


func _climb_has_wall_contact(into: Vector3) -> bool:
	for y_off in [0.35, 0.85, 1.25]:
		var hit := _probe_wall(into, y_off * character_scale, climb_probe_m + 0.35)
		if not hit.is_empty():
			return true
	## Also accept capsule slide contacts that are near-vertical.
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		if absf(n.y) < 0.45 and n.length_squared() > 0.0001:
			return true
	return false


func _try_mount_ledge(into: Vector3) -> bool:
	var r := _capsule_radius()
	## Sample just past the facade lip, above current feet.
	var over := global_position + into * (r + 0.5) + Vector3(0.0, 0.65 * character_scale, 0.0)
	var ground := _ray_query(
		over + Vector3(0.0, 0.9 * character_scale, 0.0),
		over + Vector3(0.0, -1.8 * character_scale, 0.0)
	)
	if ground.is_empty():
		return false
	var gy: float = (ground.position as Vector3).y
	## Ledge should be near mid-body — not far below (still climbing) or way above.
	if gy < global_position.y + 0.15 * character_scale:
		return false
	if gy > global_position.y + 1.35 * character_scale:
		return false
	## Waist-forward should be clear of wall (we've cleared the lip).
	var waist := _probe_wall(into, 0.55 * character_scale, r + 0.55)
	if not waist.is_empty():
		## Still blocked at waist — keep climbing unless ground is clearly standable ahead
		## and head is free.
		var head := _probe_wall(into, 1.35 * character_scale, r + 0.4)
		if not head.is_empty():
			return false
	## Mount onto the ledge.
	global_position = Vector3(over.x, gy, over.z)
	velocity = Vector3.ZERO
	_was_ray_grounded = true
	_end_climb(false)
	return true


func _climb_reached_ground() -> bool:
	if _floor_contacted():
		return true
	var hit := _ray_ground(0.0, 0.55 * character_scale)
	if hit.is_empty():
		return false
	var gy: float = (hit.position as Vector3).y
	return global_position.y - gy <= 0.28 * character_scale


func _try_start_jump() -> void:
	if _jumping or _jump_rising:
		return
	## Coyote: press on the lip still launches immediately.
	if _coyote_left <= 0.0 and not _floor_contacted():
		return
	_coyote_left = 0.0
	_was_ray_grounded = false
	_jumping = true
	_jump_rising = true
	_jump_start_y = global_position.y
	_was_airborne = true
	_land_anim_left = 0.0
	velocity.y = jump_rise_speed_mps * maxf(character_scale, 0.001)
	cancel_action()
	_play_jump_start_anim()


## Stop ascending — fall begins (key released or max height reached).
func _end_jump_rise() -> void:
	if not _jump_rising:
		return
	_jump_rising = false
	if velocity.y > 0.0:
		velocity.y = 0.0


func _update_jump_rise(_delta: float) -> void:
	if not _jump_rising:
		return
	## Missed key-up (focus blur) still ends the rise.
	if not _ctl().is_key_held("jump"):
		_end_jump_rise()
		return
	var max_h := jump_height_max_m * maxf(character_scale, 0.001)
	if global_position.y - _jump_start_y >= max_h:
		_end_jump_rise()
		return
	## Hold cancels gravity — keep rising until release or ceiling.
	velocity.y = jump_rise_speed_mps * maxf(character_scale, 0.001)


func _play_jump_start_anim() -> void:
	if _anim_player == null:
		return
	var start_path := "%s/%s" % [LIB_NAME, ANIM_JUMP_START]
	var loop_path := "%s/%s" % [LIB_NAME, ANIM_JUMP_LOOP]
	var path := start_path if _anim_player.has_animation(start_path) else loop_path
	if not _anim_player.has_animation(path):
		return
	_anim_player.play(path, 0.08)
	_anim_player.speed_scale = clampf(1.0 / maxf(character_scale, 0.001), 0.05, 4.0)


func _play_jump_land_anim() -> void:
	if _anim_player == null:
		return
	var path := "%s/%s" % [LIB_NAME, ANIM_JUMP_LAND]
	if not _anim_player.has_animation(path):
		return
	_land_anim_left = 0.28
	_anim_player.play(path, 0.06)
	_anim_player.speed_scale = clampf(1.15 / maxf(character_scale, 0.001), 0.05, 4.0)


func _apply_body_motion(delta: float) -> void:
	## Central path: slide against live voxels. Holes are just missing blocks.
	var before := global_position
	if _voxel_motion != null and bool(_voxel_motion.call("has_terrain")):
		_voxel_motion.call("move", self, _capsule, velocity, delta)
		_last_applied_motion = global_position - before
		if bool(_voxel_motion.call("is_on_floor")):
			_was_ray_grounded = true
			if velocity.y < 0.0:
				velocity.y = 0.0
		elif velocity.y > 0.0:
			_was_ray_grounded = false
		return
	move_and_slide()
	_last_applied_motion = global_position - before


func _stabilize_vertical(ray_mode: bool) -> void:
	## Kill residual vertical chatter after the slide.
	if _jumping:
		_was_ray_grounded = false
		return
	if not ray_mode:
		if _floor_contacted() and velocity.y <= 0.0:
			velocity.y = 0.0
		return
	## Giant mode: snap to voxel / physics ground when close.
	if velocity.y > 0.15:
		_was_ray_grounded = false
		return
	if _floor_contacted():
		velocity.y = 0.0
		_was_ray_grounded = true
		return
	var hit := _ray_ground(0.0, 6.0 * character_scale)
	if hit.is_empty():
		_was_ray_grounded = false
		return
	var ground_y: float = hit.position.y
	if ground_y > global_position.y + 0.35 * character_scale:
		_was_ray_grounded = false
		return
	if global_position.y - ground_y > 1.25 * character_scale:
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
	## Own layer so cascading debris (mask=terrain) never rests on this failsafe.
	_safety_deck.collision_layer = SAFETY_DECK_LAYER
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
	var dt := maxf(delta, 0.0001)
	var real_h := Vector2(_last_applied_motion.x, _last_applied_motion.z).length() / dt
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
	var delta := push.normalized() * dist
	## Never move into a wall contact — only along / away from the outward normal.
	if test_move(global_transform, delta):
		return
	global_position += delta


## Average outward (flattened) normal from this frame's wall slides. Empty if none.
func _wall_outward_normal() -> Vector3:
	var push := Vector3.ZERO
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n := col.get_normal()
		n.y = 0.0
		if n.length_squared() < 0.0001:
			continue
		## Near-vertical contacts only — floors / steps don't count as a facade.
		if absf(col.get_normal().y) > 0.45:
			continue
		push += n.normalized()
	if push.length_squared() < 0.0001:
		return Vector3.ZERO
	return push.normalized()


## Find a free footprint at the SAME height, then one ground-ray snap (same as stabilize).
## Never lifts in a loop — that was the jitter source.
func _unstuck_horizontal() -> bool:
	if _unstuck_cooldown > 0.0:
		return false
	_unstuck_cooldown = 0.45
	var origin := global_position
	var r0 := maxf(_capsule_radius() * 0.4, 0.25)
	var radii: Array[float] = [r0, r0 * 2.0, r0 * 3.5, r0 * 5.5, r0 * 8.0]
	## Prefer escaping opposite to facing, and never cross to the inside of a facade.
	var prefer := Vector3(-global_transform.basis.z.x, 0.0, -global_transform.basis.z.z)
	if prefer.length_squared() < 0.0001:
		prefer = Vector3(0.0, 0.0, -1.0)
	else:
		prefer = prefer.normalized()
	var wall_out := _wall_outward_normal()
	if wall_out != Vector3.ZERO:
		prefer = wall_out

	for radius in radii:
		for i in 12:
			var ang := atan2(prefer.x, prefer.z) + TAU * float(i) / 12.0
			var offset := Vector3(sin(ang) * radius, 0.0, cos(ang) * radius)
			## Crossing a facade into a hollow building looks free (empty room) — reject
			## any candidate that moves against the wall's outward normal.
			if wall_out != Vector3.ZERO and offset.dot(wall_out) < -0.05 * radius:
				continue
			var candidate := origin + offset
			if not _can_stand_at(candidate):
				continue
			if _is_enclosed_footprint(candidate):
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
	var s := clampf(0.12 * character_scale, 0.1, 0.45)
	var free := 0
	var dirs: Array[Vector3] = [
		Vector3(s, 0.0, 0.0),
		Vector3(-s, 0.0, 0.0),
		Vector3(0.0, 0.0, s),
		Vector3(0.0, 0.0, -s),
	]
	var use_voxel := _voxel_motion != null and bool(_voxel_motion.call("has_terrain"))
	if use_voxel:
		var offset0 := pos - global_position
		if bool(_voxel_motion.call("intersects_at", self, _capsule, offset0)):
			return false
		for d in dirs:
			if not bool(_voxel_motion.call("intersects_at", self, _capsule, offset0 + d)):
				free += 1
		return free >= 2
	var xf := global_transform
	xf.origin = pos
	for d in dirs:
		if not test_move(xf, d):
			free += 1
	return free >= 2


## True when a candidate sits in a room-like pocket (walls on 3+ sides within a few metres).
## Street / plaza footprints stay open on most sides; hollow building interiors do not.
func _is_enclosed_footprint(pos: Vector3) -> bool:
	var reach := 2.4 * maxf(character_scale, 1.0)
	var hits := 0
	var dirs: Array[Vector3] = [
		Vector3(1.0, 0.0, 0.0),
		Vector3(-1.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 1.0),
		Vector3(0.0, 0.0, -1.0),
	]
	var from := pos + Vector3(0.0, 0.9 * character_scale, 0.0)
	for d in dirs:
		var hit := _ray_query(from, from + d * reach)
		if not hit.is_empty():
			hits += 1
	return hits >= 3


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
	if _climb_mode != ClimbMode.NONE:
		_play_climb_anim()
		return
	if _action_playing:
		## One-shots (punch/kick) play out; looping emotes cancel when you walk.
		if _moving and _action_is_looping():
			cancel_action()
		else:
			return
	var size_anim := clampf(1.0 / character_scale, 0.05, 4.0)
	var airborne := _jumping or _jump_rising or not _floor_contacted()
	if airborne and _land_anim_left <= 0.0:
		var start_path := "%s/%s" % [LIB_NAME, ANIM_JUMP_START]
		var loop_path := "%s/%s" % [LIB_NAME, ANIM_JUMP_LOOP]
		var cur := String(_anim_player.current_animation)
		## Keep Jump_Start until it finishes, then hold Jump_Loop in the air.
		if cur == start_path and _anim_player.is_playing():
			_anim_player.speed_scale = size_anim
			return
		if _anim_player.has_animation(loop_path):
			if cur != loop_path:
				_anim_player.play(loop_path, 0.1)
			_anim_player.speed_scale = size_anim
			return
		if _anim_player.has_animation(start_path):
			if cur != start_path:
				_anim_player.play(start_path, 0.08)
			_anim_player.speed_scale = size_anim
			return
	if _land_anim_left > 0.0:
		var land_path := "%s/%s" % [LIB_NAME, ANIM_JUMP_LAND]
		if _anim_player.has_animation(land_path):
			if String(_anim_player.current_animation) != land_path:
				_anim_player.play(land_path, 0.06)
			_anim_player.speed_scale = clampf(1.15 * size_anim, 0.05, 4.0)
			return
	var idle_path := "%s/%s" % [LIB_NAME, ANIM_IDLE]
	var walk_path := "%s/%s" % [LIB_NAME, ANIM_WALK]
	var sprint_path := "%s/%s" % [LIB_NAME, ANIM_SPRINT]
	## Right after climb: zero blend so Mixamo leans can't soften back in.
	var just_climbed := _climb_pose_clear_sec > 0.0
	var blend_loco := 0.0 if just_climbed else (0.15 if sprinting else 0.2)
	var blend_idle := 0.0 if just_climbed else 0.25
	if _moving:
		var use_sprint := sprinting and _anim_player.has_animation(sprint_path)
		var loco_path := sprint_path if use_sprint else walk_path
		if _anim_player.current_animation != loco_path:
			_anim_player.play(loco_path, blend_loco)
		var unscaled_speed := move_speed / maxf(character_scale, 0.001)
		var ref_speed := sprint_anim_reference_speed if use_sprint else walk_anim_reference_speed
		var cadence := unscaled_speed / maxf(ref_speed, 0.01)
		_anim_player.speed_scale = clampf(cadence * size_anim, 0.05, 4.0)
	else:
		if _anim_player.current_animation != idle_path:
			_anim_player.play(idle_path, blend_idle)
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
	if not _floor_contacted():
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
	_charge_orb = Node3D.new()
	_charge_orb.name = "ChargeOrb"
	_charge_orb.visible = false
	add_child(_charge_orb)

	_charge_orb_mat = _make_charge_mat(Color(1.0, 0.45, 0.12, 0.9), Color(1.0, 0.4, 0.1))
	_charge_orb_mesh = SphereMesh.new()
	_charge_orb_mesh.radial_segments = 14
	_charge_orb_mesh.rings = 8
	_charge_orb_core = MeshInstance3D.new()
	_charge_orb_core.name = "Core"
	_charge_orb_core.mesh = _charge_orb_mesh
	_charge_orb_core.material_override = _charge_orb_mat
	_charge_orb_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_charge_orb.add_child(_charge_orb_core)

	_charge_ring_mat_a = _make_charge_mat(Color(1.0, 0.5, 0.15, 0.55), Color(1.0, 0.45, 0.12))
	_charge_ring_mat_b = _make_charge_mat(Color(1.0, 0.55, 0.2, 0.4), Color(1.0, 0.5, 0.15))
	_charge_ring_mesh_a = TorusMesh.new()
	_charge_ring_mesh_a.rings = 22
	_charge_ring_mesh_a.ring_segments = 8
	_charge_ring_mesh_b = TorusMesh.new()
	_charge_ring_mesh_b.rings = 20
	_charge_ring_mesh_b.ring_segments = 8
	_charge_ring_a = MeshInstance3D.new()
	_charge_ring_a.name = "ChargeRingA"
	_charge_ring_a.mesh = _charge_ring_mesh_a
	_charge_ring_a.material_override = _charge_ring_mat_a
	_charge_ring_a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_charge_ring_a.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_charge_orb.add_child(_charge_ring_a)
	_charge_ring_b = MeshInstance3D.new()
	_charge_ring_b.name = "ChargeRingB"
	_charge_ring_b.mesh = _charge_ring_mesh_b
	_charge_ring_b.material_override = _charge_ring_mat_b
	_charge_ring_b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_charge_ring_b.rotation_degrees = Vector3(70.0, 25.0, 0.0)
	_charge_orb.add_child(_charge_ring_b)

	_charge_orb_light = OmniLight3D.new()
	_charge_orb_light.name = "ChargeLight"
	_charge_orb_light.light_color = Color(1.0, 0.45, 0.12)
	_charge_orb_light.shadow_enabled = false
	_charge_orb_light.visible = false
	_charge_orb.add_child(_charge_orb_light)


func _make_charge_mat(albedo: Color, emission: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = albedo
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = 10.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return mat


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
		var audio_off := _city_audio()
		if audio_off != null and audio_off.has_method("stop_charged_blast_charge"):
			audio_off.call("stop_charged_blast_charge")
		return
	var frac := clampf(_blast_charge / maxf(charged_blast_charge_sec, 0.05), 0.0, 1.0)
	## Faster pulse near full charge.
	var pulse_hz := lerpf(8.0, 22.0, frac * frac)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * pulse_hz)
	## Compact core — not tied to carve radius.
	var body_s := maxf(_effective_body_scale(), 0.05)
	var orb_r := lerpf(0.07, 0.14, frac) * body_s * (0.92 + 0.12 * pulse)
	if _charge_orb_mesh != null:
		_charge_orb_mesh.radius = orb_r
		_charge_orb_mesh.height = orb_r * 2.0
	## Slight pull toward the cast hand (already at hand; nudge inward along -forward).
	var hand := _spell_hand_origin()
	var inward := global_transform.basis.z
	if inward.length_squared() > 0.0001:
		inward = inward.normalized()
	else:
		inward = Vector3.BACK
	_charge_orb.global_position = hand + inward * (0.04 * body_s * (1.0 - frac * 0.35))
	var audio := _city_audio()
	if audio != null and audio.has_method("move_charged_blast_charge"):
		audio.call("move_charged_blast_charge", _charge_orb.global_position)
	## Dull orange → white-hot.
	var hot := Color(
		1.0,
		lerpf(0.38, 0.92, frac),
		lerpf(0.08, 0.55, frac)
	)
	if _charge_orb_mat != null:
		_charge_orb_mat.albedo_color = Color(hot.r, hot.g, hot.b, 0.88)
		_charge_orb_mat.emission = hot
		_charge_orb_mat.emission_energy_multiplier = lerpf(6.0, 18.0, frac) * (0.85 + 0.35 * pulse)
	var ring_outer_a := orb_r * lerpf(1.7, 2.6, frac)
	var ring_outer_b := orb_r * lerpf(2.1, 3.2, frac)
	var tube_a := orb_r * 0.18
	var tube_b := orb_r * 0.14
	if _charge_ring_mesh_a != null:
		_charge_ring_mesh_a.outer_radius = ring_outer_a
		_charge_ring_mesh_a.inner_radius = maxf(ring_outer_a - tube_a, 0.01)
	if _charge_ring_mesh_b != null:
		_charge_ring_mesh_b.outer_radius = ring_outer_b
		_charge_ring_mesh_b.inner_radius = maxf(ring_outer_b - tube_b, 0.01)
	if _charge_ring_a != null:
		_charge_ring_a.rotate_object_local(Vector3.UP, delta * lerpf(2.5, 5.5, frac))
	if _charge_ring_b != null:
		_charge_ring_b.rotate_object_local(Vector3.UP, -delta * lerpf(3.2, 7.0, frac))
	if _charge_ring_mat_a != null:
		_charge_ring_mat_a.albedo_color = Color(hot.r, hot.g, hot.b, lerpf(0.35, 0.65, frac))
		_charge_ring_mat_a.emission = hot
		_charge_ring_mat_a.emission_energy_multiplier = lerpf(4.0, 12.0, frac)
	if _charge_ring_mat_b != null:
		_charge_ring_mat_b.albedo_color = Color(hot.r, hot.g * 0.9, hot.b * 0.8, lerpf(0.25, 0.5, frac))
		_charge_ring_mat_b.emission = hot
		_charge_ring_mat_b.emission_energy_multiplier = lerpf(3.0, 10.0, frac)
	if _charge_orb_light != null:
		_charge_orb_light.light_color = hot
		_charge_orb_light.light_energy = lerpf(1.5, 10.0, frac) * (0.9 + 0.25 * pulse)
		_charge_orb_light.omni_range = orb_r * 10.0 + frac * 1.2 * body_s


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
	var audio := _city_audio()
	if audio != null and audio.has_method("play_charged_blast_charge"):
		audio.call(
			"play_charged_blast_charge",
			_spell_hand_origin(),
			character_scale,
			charged_blast_charge_sec
		)


func _release_charged_blast_at_cursor() -> void:
	_blast_charging = false
	var audio := _city_audio()
	if audio != null and audio.has_method("stop_charged_blast_charge"):
		audio.call("stop_charged_blast_charge")
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
	if audio != null and audio.has_method("play_charged_blast_impact"):
		audio.call("play_charged_blast_impact", hit_point, character_scale)
	elif audio != null and audio.has_method("play_laser_impact"):
		audio.call("play_laser_impact", hit_point, character_scale)
	var root := _city_root()
	## Agents at the impact still die / flip; carved fabric tumbles then cascades columns.
	if root != null and root.has_method("apply_laser_agent_hit"):
		var from := hit_point - dir * maxf(radius_m, 0.5)
		root.call("apply_laser_agent_hit", from, hit_point, dir)
	if root != null and root.has_method("apply_charged_blast"):
		root.call("apply_charged_blast", hit_point, radius_m)


func _aim_point_at_cursor() -> Vector3:
	return _aim_ray_at_cursor()["point"] as Vector3


## Ground / wall under the cursor — no agent magnet (builds shouldn't snap to peds).
func aim_ground_at_cursor() -> Dictionary:
	return _aim_ray_at_cursor(false)


## Camera/crosshair ray: point + normal (UP if miss / far clip).
## Combat aim (magnet_agents) also voxel-marches so walk-through park mats
## (bark/leaves/planters) stay targetable without solid collision.
## shot_origin: second agent-magnet probe (eyes / hand). Empty → eye laser origin.
func _aim_ray_at_cursor(
	magnet_agents: bool = true,
	shot_origin: Vector3 = Vector3.INF
) -> Dictionary:
	if _camera == null:
		var fallback := global_position - global_transform.basis.z * 10.0
		return {
			"point": fallback,
			"normal": Vector3.UP,
			"did_hit": false,
			"cam_from": fallback,
			"cam_dir": -global_transform.basis.z,
		}
	var mouse := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse)
	var ray_dir := _camera.project_ray_normal(mouse)
	if ray_dir.length_squared() < 0.0001:
		ray_dir = -global_transform.basis.z
	ray_dir = ray_dir.normalized()
	var to := from + ray_dir * laser_range_m
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var aim_point := to
	var aim_normal := Vector3.UP
	var did_hit := not hit.is_empty()
	if did_hit:
		aim_point = hit["position"] as Vector3
		aim_normal = hit["normal"] as Vector3
	var root := _city_root()
	if magnet_agents and root != null and root.has_method("probe_destructible_ray"):
		## Full ray — trees sit in front of ground/walls the physics hit would prefer.
		var vhit: Variant = root.call("probe_destructible_ray", from, to)
		if vhit is Dictionary and not (vhit as Dictionary).is_empty():
			var vd := Dictionary(vhit)
			var vdist := float(vd.get("distance", INF))
			var pdist := from.distance_to(aim_point) if did_hit else INF
			if vdist + 0.02 < pdist:
				aim_point = vd["point"] as Vector3
				aim_normal = vd.get("normal", -ray_dir) as Vector3
				did_hit = true
	if magnet_agents and root != null and root.has_method("resolve_laser_aim"):
		var origin := shot_origin if shot_origin.is_finite() else _laser_eye_origin()
		aim_point = root.call("resolve_laser_aim", from, aim_point, origin) as Vector3
	return {
		"point": aim_point,
		"normal": aim_normal,
		"did_hit": did_hit,
		"cam_from": from,
		"cam_dir": ray_dir,
	}


## Fresh cursor target + hand muzzle for one blaster bolt (retargets every shot).
func _blaster_shot_endpoints() -> Dictionary:
	var s := maxf(character_scale, 0.05)
	var hand := _bone_world_pos(
		[&"LeftHand", &"hand_l", &"hand.L", &"LeftLowerArm", &"lowerarm_l"]
	)
	if not hand.is_finite():
		hand = global_position + Vector3(0.0, 1.15 * s, 0.0)
	var aim := _aim_ray_at_cursor(true, hand)
	var aim_point: Vector3 = aim["point"] as Vector3
	var cam_dir: Vector3 = aim["cam_dir"] as Vector3
	var to_aim := aim_point - hand
	var dir: Vector3
	if to_aim.length_squared() < 0.0001:
		dir = cam_dir
	else:
		dir = to_aim.normalized()
		## Hand can sit past a close cursor hit — shoot along the camera ray instead.
		if dir.dot(cam_dir) < 0.2:
			dir = cam_dir
			var cam_from: Vector3 = aim["cam_from"] as Vector3
			var along := maxf(cam_from.distance_to(aim_point), 1.25 * s)
			aim_point = hand + dir * along
	var origin := hand + dir * (0.2 * s)
	return {"origin": origin, "aim_point": aim_point}


func _request_infection_meteor() -> void:
	var aim := _aim_ray_at_cursor()
	meteor_requested.emit(aim["point"] as Vector3, aim["normal"] as Vector3)


func _request_tetris_machine() -> void:
	var aim := _aim_ray_at_cursor()
	tetris_requested.emit(aim["point"] as Vector3, aim["normal"] as Vector3)


func _request_pedestrian() -> void:
	var aim := _aim_ray_at_cursor()
	pedestrian_requested.emit(aim["point"] as Vector3, aim["normal"] as Vector3)


func _request_undead_radar() -> void:
	var root := _city_root()
	if root == null:
		push_error("CityWalker: undead radar — no CityRoot parent")
		return
	if root.has_method("request_undead_radar"):
		var ok: bool = bool(root.call("request_undead_radar"))
		if not ok:
			## Cooldown / boot / game-over — still feedback via HUD timer when cooling.
			pass
	else:
		push_error("CityWalker: CityRoot missing request_undead_radar")


func _request_district_hop() -> void:
	var root := _city_root()
	if root == null:
		push_error("CityWalker: district hop — no CityRoot parent")
		return
	if root.has_method("request_district_hop"):
		root.call("request_district_hop")
	else:
		push_error("CityWalker: CityRoot missing request_district_hop")


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
	if not try_spend_energy(energy_cost_blast):
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
	if audio != null and audio.has_method("play_charged_blast_throw"):
		audio.call("play_charged_blast_throw", origin, character_scale)
	elif audio != null and audio.has_method("play_laser_fire"):
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
	if not try_spend_energy(energy_cost_laser):
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


func _begin_blaster_hold() -> void:
	if _camera == null or _game_over_locked:
		return
	_blast_charging = false
	_blast_charge = 0.0
	var audio := _city_audio()
	if audio != null and audio.has_method("stop_charged_blast_charge"):
		audio.call("stop_charged_blast_charge")
	_blaster_holding = true
	_blaster_accum = 0.0
	## Same hand cast pose as charged-blast hold.
	_ensure_spell_charge_pose()
	_fire_blaster_bolt()


func _stop_blaster(cancel_in_flight: bool) -> void:
	_blaster_holding = false
	_blaster_accum = 0.0
	if (
		_action_anim == charged_blast_idle_anim
		or _action_anim == charged_blast_shoot_anim
	):
		cancel_action()
	if not cancel_in_flight:
		return
	for bolt in _live_blaster_bolts:
		if bolt != null and is_instance_valid(bolt) and bolt.has_method("cancel"):
			bolt.call("cancel")
	_live_blaster_bolts.clear()


func _update_blaster(delta: float) -> void:
	if not _blaster_holding:
		return
	if _game_over_locked or not _is_beam_held():
		_stop_blaster(false)
		return
	## Keep Spell_Simple_Idle between shots (Shoot overrides while a bolt leaves).
	if not (_action_playing and _action_anim == charged_blast_shoot_anim):
		_ensure_spell_charge_pose()
	_blaster_accum += delta
	var interval := maxf(blaster_interval_sec, 0.05)
	while _blaster_accum >= interval:
		_blaster_accum -= interval
		_fire_blaster_bolt()


func _is_beam_held() -> bool:
	var ctl := _ctl()
	var b := ctl.get_binding("beam")
	if str(b.get("device", "")) == "key":
		return ctl.is_key_held("beam")
	var code := int(b.get("code", -1)) as MouseButton
	if code < 0 or not Input.is_mouse_button_pressed(code):
		return false
	## Shift is sprint — never blocks bare LMB beam. Alt/Ctrl still exclusive so
	## Alt+LMB blast / Ctrl+LMB laser don't keep the blaster streaming.
	if bool(b.get("shift", false)) and not Input.is_key_pressed(KEY_SHIFT):
		return false
	if bool(b.get("ctrl", false)) != Input.is_key_pressed(KEY_CTRL):
		return false
	if bool(b.get("alt", false)) != Input.is_key_pressed(KEY_ALT):
		return false
	return true


func _fire_blaster_bolt() -> void:
	if _camera == null:
		return
	if not try_spend_energy(energy_cost_blaster):
		return
	## Same shoot flick as charged blast release — hand casts each bolt.
	if has_action_animation(charged_blast_shoot_anim):
		play_action(charged_blast_shoot_anim, false)
	## Retarget every bolt from the live mouse cursor (camera ray → voxels/agents).
	var shot := _blaster_shot_endpoints()
	var origin: Vector3 = shot["origin"] as Vector3
	var aim_point: Vector3 = shot["aim_point"] as Vector3
	var audio := _city_audio()
	if audio != null and audio.has_method("play_laser_fire"):
		audio.call("play_laser_fire", origin, character_scale)

	var bolt: Node = BlasterBoltVfxScript.new()
	bolt.name = "BlasterBoltVfx"
	add_child(bolt)
	_live_blaster_bolts.append(bolt)
	bolt.tree_exiting.connect(
		func() -> void:
			_live_blaster_bolts.erase(bolt)
	)
	bolt.call("setup")
	bolt.call("set_character_scale", _effective_body_scale())
	if bolt.has_method("set_obstacle_probe"):
		bolt.call(
			"set_obstacle_probe",
			func(from: Vector3, tip: Vector3) -> float:
				var root := _city_root()
				if root == null or not root.has_method("laser_probe_agent_distance"):
					return -1.0
				return float(root.call("laser_probe_agent_distance", from, tip))
		)
	if bolt.has_signal("impact"):
		bolt.connect("impact", _on_blaster_impact)
	bolt.call("fire", origin, aim_point, blaster_speed_mps, _effective_body_scale())


func _on_blaster_impact(hit_point: Vector3, direction: Vector3, shot_origin: Vector3) -> void:
	## Same destruction as the eye-laser dart (agent hit or melee carve + cascade).
	var dir := direction
	if dir.length_squared() < 0.0001:
		dir = -global_transform.basis.z
	else:
		dir = dir.normalized()
	var audio := _city_audio()
	if audio != null and audio.has_method("play_laser_impact"):
		audio.call("play_laser_impact", hit_point, character_scale)
	var from := shot_origin
	if from.length_squared() < 0.0001:
		from = hit_point - dir * 0.15
	var root := _city_root()
	if root != null and root.has_method("apply_laser_agent_hit"):
		if bool(root.call("apply_laser_agent_hit", from, hit_point, dir)):
			return
	var origin := hit_point - dir * 0.15
	melee_strike_requested.emit(origin, dir, maxf(2.5, character_scale * 2.0))


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
	if not try_spend_energy(energy_cost_stomp):
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
	## Same carve/debris as a fully charged LMB blast at the feet.
	var radius := charged_blast_radius_max_m * maxf(character_scale, 0.05)
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
