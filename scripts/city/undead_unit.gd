## One undead soldier: Mage (convert), Minion (melee fodder), or Giant (grown + stomp).
##
## Movement is NavAgent + NavMotor over the baked span field. An UndeadGoalProvider says what
## this body wants and the six-rung ladder says what happens when it cannot get there, so
## there is deliberately no local unstick code here: TRAPPED is the only escape hatch, and it
## is counted, warned about and emitted rather than quietly relocating the body.
class_name UndeadUnit
extends CharacterBody3D

enum Role { MAGE, MINION, GIANT }
enum State { IDLE, SEEK_PED, CAST, NIBBLE, SEEK_PAD, GROWING, STOMP, SCRAPE, DEAD }

const MAGE_PACKED: PackedScene = preload("res://assets/monsters/kaykit_skeletons/characters/Skeleton_Mage.glb")
const MINION_PACKED: PackedScene = preload("res://assets/monsters/kaykit_skeletons/characters/Skeleton_Minion.glb")
const OrbScript := preload("res://scripts/city/undead_orb_projectile.gd")

## Slightly slower than the slowest walking pedestrian (1.15–1.85).
const MOVE_SPEED_MAGE := 1.05
const MOVE_SPEED_MINION := 4.2
const MOVE_SPEED_GIANT := 5.5
## KayKit walk cycle authored roughly around this ground speed.
const WALK_ANIM_REF_MPS := 1.55
## Giants keep a heavy, slow playback regardless of ground speed.
const GIANT_ANIM_SPEED := 0.38
const CAST_COOLDOWN_SEC := 20.0
const ORB_RANGE_M := 30.0
## Stop this far inside orb range, so a step of drift does not put the target out of reach.
const ORB_STANDOFF_FRACTION := 0.92
## Between casts the mage keeps closing, exactly as the old straight-line pursue did.
const MAGE_CLOSE_IN_M := 2.5
## Chase / cast acquire range — give up if the target gets farther than this.
const MAGE_PURSUE_RANGE_M := 40.0
const PAD_SEEK_RANGE_M := 75.0
const GIANT_SCALE_TARGET := 10.0
const GROW_LOG_RATE := 0.55
## Peel a facade strip this often while working on a wall.
const SCRAPE_INTERVAL_SEC := 0.32
## Hunt building fabric in this radius; ignore the player.
const GIANT_BUILDING_SEEK_M := 110.0
## Stand-off from the facade while scraping (meters).
const GIANT_SCRAPE_DIST_M := 3.6
const GIANT_APPROACH_DIST_M := 5.5
const HIT_SCORE_NORMAL := 50
const HIT_SCORE_GIANT := 1000
## Collision stays walkable — full 10× body scale on the capsule embeds in buildings.
const COL_RADIUS_MAX_M := 1.25
const COL_HEIGHT_MAX_M := 3.4
## How often prey is re-acquired for a running hunt.
const PED_QUERY_INTERVAL_SEC := 0.28
const ANIM_FAR_DIST_M := 90.0
const MINION_NIBBLE_INTERVAL_SEC := 15.0
const MINION_BUILDING_SEEK_M := 45.0
const MINION_NIBBLE_REACH_M := 2.4
## Fall acceleration for the near tier. Heavier than world gravity so a dropped body lands
## rather than floating down a facade.
const FALL_GRAVITY := 28.0
## Ground speed below which the body is treated as standing still for animation.
const MOVE_ANIM_EPS_MPS := 0.15
const FACE_LERP_RATE := 10.0
## Fraction of a ScalePad's radius that counts as standing on it.
const PAD_REACH_FRACTION := 0.85
## Drifting this far past the pad edge sends the body back to walking onto it.
const PAD_DRIFT_SLACK_M := 1.1
## Growth is done once the scale is within this of the target.
const GROW_EPSILON := 0.05
## Extra cells carved beyond the profile footprint when a giant digs itself out, so the
## pocket actually satisfies the clearance the profile asks for.
const DIG_OUT_MARGIN_CELLS := 1

signal died(unit: UndeadUnit, was_giant: bool)

var role: Role = Role.MAGE
var state: State = State.IDLE
var character_scale: float = 1.0
var _director: UndeadInvasionDirector
var _city: CityRoot
var _terrain: VoxelTerrain
var _lod: NavLod
var _anim: AnimationPlayer
var _model: Node3D
var _col_shape: CollisionShape3D
var _capsule: CapsuleShape3D
var _nav_agent: NavAgent
var _nav_motor: NavMotor
var _provider: UndeadGoalProvider
var _cast_cd: float = 0.0
var _scrape_cd: float = 0.0
var _alive: bool = true
var _yaw: float = 0.0
var _target_pad: ScalePad
var _retarget_cd: float = 0.0
var _current_anim: String = ""
var _anim_clips: PackedStringArray = PackedStringArray()
var _nibble_cd: float = 0.0
## The orb is away; hold CAST one more frame so the spellcast clip is not stomped by the
## walking states' idle.
var _cast_fired: bool = false
## The building voxel the body is chewing or peeling. Vector3.INF while it has none.
var _facade_target: Vector3 = Vector3.INF


func setup(
	p_role: Role,
	director: UndeadInvasionDirector,
	city: CityRoot,
	world_pos: Vector3,
	terrain: VoxelTerrain,
	lod: NavLod
) -> void:
	role = p_role
	_director = director
	_city = city
	_terrain = terrain
	_lod = lod
	global_position = world_pos
	character_scale = 1.0
	_alive = true
	collision_layer = 2
	collision_mask = 1
	_build_body()
	_load_model()
	_apply_scale()
	if role == Role.MINION:
		## Stagger nibbles so a pack doesn't all bite on the same frame.
		_nibble_cd = randf_range(0.0, MINION_NIBBLE_INTERVAL_SEC)
	state = State.STOMP if role == Role.GIANT else State.SEEK_PED
	_build_nav()
	_play_anim(["Idle", "Idle_A", "idle"])


func is_alive() -> bool:
	return _alive


func is_mage() -> bool:
	return role == Role.MAGE


func is_giant() -> bool:
	return role == Role.GIANT or character_scale >= GIANT_SCALE_TARGET * 0.95


func can_cast() -> bool:
	return _cast_cd <= 0.0


func hit_radius() -> float:
	return 0.55 * character_scale


func hit_half_height() -> float:
	return 0.95 * character_scale


## Which LOD tier the navigation is running this body at. Used to skip crowd queries for
## bodies nobody can see.
func nav_tier() -> NavLod.Tier:
	if _nav_agent == null:
		return NavLod.Tier.NEAR
	return _nav_agent.tier()


func nav_state() -> NavLadder.State:
	if _nav_agent == null:
		return NavLadder.State.PATH_OK
	return _nav_agent.state()


## The navigation brain, for anything that wants the ladder signals rather than a snapshot of
## the rung. Null between `_dispose_nav` and the rebuild a giant transformation does.
func nav_agent() -> NavAgent:
	return _nav_agent


func kill_from_player() -> int:
	if not _alive:
		return 0
	_alive = false
	state = State.DEAD
	velocity = Vector3.ZERO
	_dispose_nav()
	_play_anim(["Death_A", "Death", "death"])
	var award := HIT_SCORE_GIANT if is_giant() else HIT_SCORE_NORMAL
	died.emit(self, is_giant())
	var tree := get_tree()
	if tree != null:
		tree.create_timer(1.6).timeout.connect(queue_free)
	else:
		queue_free()
	return award


func _exit_tree() -> void:
	_dispose_nav()


# ---------------------------------------------------------------------------
# Body
# ---------------------------------------------------------------------------

func _build_body() -> void:
	for c in get_children():
		if c is CollisionShape3D:
			c.queue_free()
	_col_shape = CollisionShape3D.new()
	_col_shape.name = "BodyShape"
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.28
	_capsule.height = 1.15
	_col_shape.shape = _capsule
	_col_shape.position = Vector3(0.0, 0.9, 0.0)
	add_child(_col_shape)


func _load_model() -> void:
	var packed: PackedScene = MAGE_PACKED if role == Role.MAGE or role == Role.GIANT else MINION_PACKED
	var inst: Node = packed.instantiate()
	_model = inst as Node3D
	if _model == null:
		push_error("UndeadUnit: KayKit root is not Node3D (got %s)" % inst.get_class())
		inst.queue_free()
		return
	_model.name = "KayKitModel"
	add_child(_model)
	## KayKit roots are already ground-aligned.
	_model.position = Vector3.ZERO
	_model.rotation = Vector3.ZERO
	_anim = _find_anim(_model)
	if _anim == null:
		push_error("UndeadUnit: no AnimationPlayer in KayKit model (role=%d)" % int(role))
		return
	_anim.active = true
	_anim_clips = _anim.get_animation_list()
	_configure_locomotion_loops()
	_apply_far_visibility(_model)


func _configure_locomotion_loops() -> void:
	## KayKit walk/run clips are often imported as one-shots — without LOOP they freeze mid-stride
	## and the body keeps sliding (reads as floating).
	if _anim == null:
		return
	for n in _anim_clips:
		var nl := str(n).to_lower()
		var loop := (
			nl.contains("walk")
			or nl.contains("run")
			or nl.contains("idle")
			or nl.contains("spellcast")
		)
		if not loop:
			continue
		var anim := _anim.get_animation(n)
		if anim == null:
			continue
		anim.loop_mode = Animation.LOOP_LINEAR


func _apply_far_visibility(n: Node) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		## No distance fade/cull — undead must stay drawable well past the 150 m radar / 200 m+.
		g.visibility_range_begin = 0.0
		g.visibility_range_begin_margin = 0.0
		g.visibility_range_end = 0.0
		g.visibility_range_end_margin = 0.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	for c in n.get_children():
		_apply_far_visibility(c)


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var found := _find_anim(c)
		if found != null:
			return found
	return null


func _apply_scale() -> void:
	## Visual only — never scale the CharacterBody3D (that blows up physics).
	if _model != null and is_instance_valid(_model):
		_model.scale = Vector3.ONE * character_scale
	_update_collision_for_scale()
	if _nav_motor != null:
		_nav_motor.speed_mps = _move_speed()


func _update_collision_for_scale() -> void:
	if _capsule == null or _col_shape == null:
		return
	## Grow with sqrt so giants stay street-capable; hard-clamp for 10×.
	var r := clampf(0.28 * sqrt(character_scale), 0.28, COL_RADIUS_MAX_M)
	var h := clampf(1.15 * sqrt(character_scale), 1.15, COL_HEIGHT_MAX_M)
	_capsule.radius = r
	_capsule.height = maxf(h, r * 2.0 + 0.05)
	_col_shape.position = Vector3(0.0, h * 0.5, 0.0)


# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

## Mages and minions read the span field as `undead`; a giant reads it as `giant`, which is
## 11 cells of clearance and `can_break` — the wall stops being a dead end and becomes a
## priced routing decision.
func nav_profile_id() -> int:
	return NavProfile.Id.GIANT if role == Role.GIANT else NavProfile.Id.UNDEAD


func _build_nav() -> void:
	var nav := NavService.instance()
	if not nav.is_configured():
		push_error("UndeadUnit %s: NavService is not configured, this body cannot navigate" % name)
		return
	var profile_id := nav_profile_id()
	var profile := nav.profile(profile_id)
	if profile == null:
		return
	_nav_motor = NavMotor.new()
	_nav_motor.speed_mps = _move_speed()
	_nav_motor.gravity = FALL_GRAVITY
	## Without a terrain the near tier has nothing to sweep against; NavMotor says so itself,
	## once, the first time a body actually gets that close.
	if _terrain != null:
		var motion := VoxelBodyMotion.new()
		motion.setup(_terrain, profile.max_step * nav.voxel_size())
		_nav_motor.attach_collider(self, _col_shape, motion)
	_provider = UndeadGoalProvider.new()
	_provider.setup(self, _city)
	_nav_agent = NavAgent.new()
	_nav_agent.setup(self, profile_id, _nav_motor, _provider, _lod)
	_nav_agent.trapped.connect(_on_trapped)
	if profile.can_break:
		_nav_agent.dig_out_requested.connect(_on_dig_out_requested)


func _rebuild_nav() -> void:
	_dispose_nav()
	_build_nav()


func _dispose_nav() -> void:
	if _nav_agent == null:
		return
	_nav_agent.dispose()
	_nav_agent = null
	_nav_motor = null
	_provider = null


## One frame of navigation, plus whatever animation the distance covered implies.
func _tick_nav(delta: float) -> void:
	if _nav_agent == null:
		return
	var before := global_position
	_nav_agent.tick(delta, _observer_position())
	if _retarget_cd <= 0.0:
		_retarget_cd = PED_QUERY_INTERVAL_SEC
		_provider.retarget(_nav_agent)
	_animate_motion(global_position - before, delta)


## The LOD tiers are measured from the player camera.
func _observer_position() -> Vector3:
	var p := _city.get_player_position()
	if p == Vector3.INF:
		return global_position
	return p


## The state changed under a running goal, so the corridor is for something this body no
## longer wants.
func _restart_goal() -> void:
	if _nav_agent == null:
		return
	_nav_agent.abandon_goal()


## Entombment. NavAgent has already counted it, warned and moved or dug the body out; all
## this has to do is forget the wall it was working on.
func _on_trapped(_world_pos: Vector3, _escape: NavLadder.Escape) -> void:
	_facade_target = Vector3.INF
	if state == State.NIBBLE or state == State.SCRAPE:
		state = State.STOMP if role == Role.GIANT else State.SEEK_PED


## A `can_break` body is entombed, and breaking out is what the profile promised. The pocket
## is carved through CityBrush — the one live write funnel — so `voxels_changed` fires and
## the nav field rebuilds over the hole instead of the body standing in a stale one.
func _on_dig_out_requested(world_pos: Vector3) -> void:
	if _terrain == null:
		push_error("UndeadUnit %s: entombed with no terrain to dig out of" % name)
		return
	var brush := _city.voxel_brush()
	if brush == null:
		push_error("UndeadUnit %s: entombed and CityRoot has no brush to dig with" % name)
		return
	var profile := NavService.instance().profile(nav_profile_id())
	if profile == null:
		return
	var local := _terrain.to_local(world_pos)
	var cx := floori(local.x)
	var cz := floori(local.z)
	## From the feet up: the voxel below stays, so the pocket has a floor to be a span on.
	var floor_y := floori(local.y)
	var r := profile.radius_cells + DIG_OUT_MARGIN_CELLS
	brush.fill_box(
		Vector3i(cx - r, floor_y, cz - r),
		Vector3i(cx + r + 1, floor_y + profile.height_cells + DIG_OUT_MARGIN_CELLS, cz + r + 1),
		VoxelMaterial.AIR
	)
	CityProfiler.add_counter("undead_dig_out")


# ---------------------------------------------------------------------------
# Goal callbacks — the provider drives the state machine from what the ladder reports
# ---------------------------------------------------------------------------

## Standing on the firing spot. While the orb is on cooldown the provider simply hands out
## another approach, so the mage keeps pressing instead of loitering at orb range.
func on_prey_in_range() -> void:
	if not can_cast():
		return
	state = State.CAST


func on_facade_in_reach(point: Vector3, working: State) -> void:
	_facade_target = point
	state = working


func on_pad_in_reach() -> void:
	state = State.GROWING
	_play_anim(["Idle", "Idle_A", "idle"])


## The ladder abandoned a goal — GOAL_UNREACHABLE or TRAPPED, both already reported by
## NavAgent. Drop whatever the goal was about so the next one is picked from scratch.
func on_goal_failed(_goal: NavGoal, _ladder_state: NavLadder.State) -> void:
	_facade_target = Vector3.INF
	if state == State.SEEK_PAD:
		abandon_pad()
	elif state == State.NIBBLE or state == State.SCRAPE:
		state = State.STOMP if role == Role.GIANT else State.SEEK_PED


func target_pad() -> ScalePad:
	if _target_pad != null and is_instance_valid(_target_pad):
		return _target_pad
	return null


## The pad went away with its district.
func abandon_pad() -> void:
	_target_pad = null
	state = State.SEEK_PED


func pad_reach(pad: ScalePad) -> float:
	return pad.pad_radius * PAD_REACH_FRACTION


## How far out from building fabric this body wants to stand while working on it: inside bite
## reach for a minion, arm's length plus its own bulk for a giant.
func facade_standoff_m() -> float:
	if role == Role.GIANT:
		return GIANT_APPROACH_DIST_M
	return MINION_NIBBLE_REACH_M * 0.6


# ---------------------------------------------------------------------------
# Frame
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	tick(delta)


## One frame of behaviour and navigation. Public so a headless test can step a body on a
## fixed delta instead of at whatever rate the physics server happens to run.
func tick(delta: float) -> void:
	if not _alive:
		return
	if not _city.is_player_alive():
		return
	_cast_cd = maxf(0.0, _cast_cd - delta)
	_scrape_cd = maxf(0.0, _scrape_cd - delta)
	_nibble_cd = maxf(0.0, _nibble_cd - delta)
	_retarget_cd = maxf(0.0, _retarget_cd - delta)

	## Far units: skip anim switches most frames.
	var far := _distance_to_player() > ANIM_FAR_DIST_M
	if _anim != null:
		_anim.active = not far or role == Role.GIANT

	if role != Role.GIANT and _director.wants_giant_candidate(self):
		_begin_pad_seek()

	match state:
		State.CAST:
			_tick_cast()
		State.NIBBLE:
			_tick_nibble()
		State.GROWING:
			_tick_growing(delta)
		State.SCRAPE:
			_tick_scrape()
		State.IDLE, State.SEEK_PED, State.SEEK_PAD, State.STOMP, State.DEAD:
			## Walking states: the corridor is the behaviour.
			pass
		_:
			push_error("UndeadUnit %s: unknown state %d" % [name, state])
	_tick_nav(delta)


func _begin_pad_seek() -> void:
	if state == State.SEEK_PAD or state == State.GROWING or state == State.STOMP:
		return
	var pad := _city.find_nearest_grow_pad(global_position, PAD_SEEK_RANGE_M) as ScalePad
	if pad == null:
		return
	_target_pad = pad
	state = State.SEEK_PAD
	_restart_goal()


func _tick_cast() -> void:
	if _cast_fired:
		_cast_fired = false
		state = State.SEEK_PED
		return
	_cast_fired = true
	_play_anim(["Spellcast_Shoot", "Spellcast_Raise", "Attack", "Spellcast"])
	## Fresh aim — never fire at the position the hunt goal was built from.
	var prey := _city.find_nearest_ped_position(global_position, ORB_RANGE_M)
	if prey == Vector3.INF:
		return
	_look_at_flat(prey)
	_fire_orb(prey)
	_cast_cd = CAST_COOLDOWN_SEC


## Locked on a facade — keep swinging the whole time; the voxel only dies every 15 s.
func _tick_nibble() -> void:
	_look_at_flat(_facade_target)
	_play_anim_looping(["Kick_A", "Punch_A", "Attack", "Hit_A", "Spellcast_Shoot"])
	if _nibble_cd > 0.0:
		return
	if _city.undead_nibble_building_near(global_position, MINION_NIBBLE_REACH_M + 1.2):
		_nibble_cd = MINION_NIBBLE_INTERVAL_SEC
		return
	## Nothing left within reach: the provider picks the next piece of fabric.
	_facade_target = Vector3.INF
	state = State.SEEK_PED
	_restart_goal()


func _tick_growing(delta: float) -> void:
	var pad := target_pad()
	if pad == null:
		abandon_pad()
		_restart_goal()
		return
	var d := Vector2(
		global_position.x - pad.global_position.x, global_position.z - pad.global_position.z
	).length()
	if d > pad_reach(pad) + PAD_DRIFT_SLACK_M:
		state = State.SEEK_PAD
		_restart_goal()
		return
	character_scale = minf(GIANT_SCALE_TARGET, character_scale * exp(GROW_LOG_RATE * delta))
	_apply_scale()
	if character_scale < GIANT_SCALE_TARGET - GROW_EPSILON:
		return
	_become_giant()


func _become_giant() -> void:
	character_scale = GIANT_SCALE_TARGET
	role = Role.GIANT
	state = State.STOMP
	_target_pad = null
	_apply_scale()
	## A giant is a different body to the field: it re-registers on the giant profile.
	_rebuild_nav()
	_director.notify_giant_ready(self)
	_play_anim(["Idle", "Idle_A", "idle"])


## Peel a full-height strip off whatever the corridor walked the giant up to. A scrape that
## removes nothing means the face is gone, so the provider picks the next building.
func _tick_scrape() -> void:
	_look_at_flat(_facade_target)
	if _scrape_cd > 0.0:
		return
	_scrape_cd = SCRAPE_INTERVAL_SEC
	var inward := _facade_target - global_position
	inward.y = 0.0
	if inward.length_squared() < 0.0001:
		inward = Vector3(sin(_yaw), 0.0, cos(_yaw))
	inward = inward.normalized()
	var along := Vector3(-inward.z, 0.0, inward.x)
	var contact := global_position + inward * GIANT_SCRAPE_DIST_M
	contact.y = global_position.y + 1.2
	if _city.undead_giant_scrape_at(contact, inward, along) > 0:
		return
	_facade_target = Vector3.INF
	state = State.STOMP
	_restart_goal()


func _fire_orb(toward: Vector3) -> void:
	var orb: Node = OrbScript.new()
	orb.name = "UndeadOrb"
	var parent: Node = _director if _director != null else self
	parent.add_child(orb)
	var muzzle := global_position + Vector3(0.0, 1.35 * character_scale, 0.0)
	if orb.has_method("launch"):
		orb.call("launch", muzzle, toward + Vector3(0.0, 1.0, 0.0), _director)


func _distance_to_player() -> float:
	var p := _city.get_player_position()
	if p == Vector3.INF:
		return 0.0
	return global_position.distance_to(p)


func _move_speed() -> float:
	match role:
		Role.MAGE:
			return MOVE_SPEED_MAGE
		Role.GIANT:
			## Cover ground at giant size without becoming unreadable.
			return MOVE_SPEED_GIANT * clampf(0.55 + 0.12 * character_scale, 1.0, 2.4)
		_:
			return MOVE_SPEED_MINION


# ---------------------------------------------------------------------------
# Presentation
# ---------------------------------------------------------------------------

func _animate_motion(moved: Vector3, delta: float) -> void:
	var flat := Vector3(moved.x, 0.0, moved.z)
	var ground_speed := flat.length() / delta
	if ground_speed < MOVE_ANIM_EPS_MPS:
		## Casting, chewing and peeling drive their own clips.
		if state != State.CAST and state != State.NIBBLE and state != State.SCRAPE:
			_play_anim(["Idle", "Idle_A", "idle"])
		return
	_face_direction(flat, delta)
	_play_locomotion(ground_speed)


func _play_locomotion(ground_speed: float) -> void:
	if is_giant():
		## Don't speed the cycle up with the giant's long stride — keep it ponderous.
		_set_anim_speed(GIANT_ANIM_SPEED)
	else:
		_set_anim_speed(clampf(ground_speed / WALK_ANIM_REF_MPS, 0.4, 1.4))
	_play_anim_looping(["Walking_A", "Walking_B", "Walking_C", "Walk", "Running_A", "Run"])


func _set_anim_speed(scale: float) -> void:
	if _anim == null:
		return
	if is_giant():
		## Idle / scrape clips stay heavy too.
		_anim.speed_scale = minf(scale, GIANT_ANIM_SPEED)
	else:
		_anim.speed_scale = scale


func _face_direction(flat: Vector3, delta: float) -> void:
	var want := atan2(flat.x, flat.z)
	_yaw = lerp_angle(_yaw, want, clampf(FACE_LERP_RATE * delta, 0.0, 1.0))
	rotation.y = _yaw


func _look_at_flat(world: Vector3) -> void:
	if world == Vector3.INF:
		return
	var to := world - global_position
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	_yaw = atan2(to.x, to.z)
	rotation.y = _yaw


func _play_anim(candidates: Array) -> void:
	if _anim == null or not _anim.active:
		return
	_set_anim_speed(1.0 if not is_giant() else GIANT_ANIM_SPEED)
	for want in candidates:
		var w := str(want).to_lower()
		for n in _anim_clips:
			var nl := str(n).to_lower()
			if nl == w or nl.contains(w):
				if _current_anim == n and _anim.is_playing():
					return
				_current_anim = n
				_anim.play(n)
				return


## Keep a one-shot attack clip restarting so minions look busy between voxel kills.
func _play_anim_looping(candidates: Array) -> void:
	if _anim == null or not _anim.active:
		return
	for want in candidates:
		var w := str(want).to_lower()
		for n in _anim_clips:
			var nl := str(n).to_lower()
			if nl == w or nl.contains(w):
				if _current_anim == n and _anim.is_playing():
					return
				_current_anim = n
				_anim.play(n)
				return
