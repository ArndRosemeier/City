## One undead soldier: Mage (convert), Minion (melee fodder), or Giant (grown + stomp).
extends CharacterBody3D

enum Role { MAGE, MINION, GIANT }
enum State { IDLE, SEEK_PED, CAST, SEEK_PAD, GROWING, STOMP, DEAD }

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
## Chase / cast acquire range — give up if the target gets farther than this.
const MAGE_PURSUE_RANGE_M := 40.0
const PAD_SEEK_RANGE_M := 75.0
const GIANT_SCALE_TARGET := 10.0
const GROW_LOG_RATE := 0.55
## Peel a facade strip this often while brushing along a wall.
const SCRAPE_INTERVAL_SEC := 0.32
## Hunt building fabric in this radius; ignore the player.
const GIANT_BUILDING_SEEK_M := 110.0
const GIANT_BUILDING_QUERY_SEC := 0.45
## Stand-off from the facade while scraping (meters).
const GIANT_SCRAPE_DIST_M := 3.6
const GIANT_APPROACH_DIST_M := 5.5
## Give up on a dead face after this many empty scrapes (floor stubs / hollow shell).
const GIANT_SCRAPE_MISS_LIMIT := 2
const HIT_SCORE_NORMAL := 50
const HIT_SCORE_GIANT := 1000
## Collision stays walkable — full 10× body scale on the capsule embeds in buildings.
const COL_RADIUS_MAX_M := 1.25
const COL_HEIGHT_MAX_M := 3.4
const STUCK_TIME_SEC := 0.55
const PED_QUERY_INTERVAL_SEC := 0.28
const ANIM_FAR_DIST_M := 90.0
const MINION_NIBBLE_INTERVAL_SEC := 15.0
const MINION_BUILDING_SEEK_M := 45.0
const MINION_NIBBLE_REACH_M := 2.4

signal died(unit: Node, was_giant: bool)

var role: Role = Role.MAGE
var state: State = State.IDLE
var character_scale: float = 1.0
var _director: Node
var _city: Node
var _anim: AnimationPlayer
var _model: Node3D
var _col_shape: CollisionShape3D
var _capsule: CapsuleShape3D
var _cast_cd: float = 0.0
var _stomp_cd: float = 0.0
var _alive: bool = true
var _yaw: float = 0.0
var _target_pad: Node3D
var _wander_accum: float = 0.0
var _stuck_timer: float = 0.0
var _unstuck_cooldown: float = 0.0
var _wish_dir: Vector3 = Vector3.ZERO
var _ped_query_cd: float = 0.0
var _cached_ped_pos: Vector3 = Vector3.INF
var _current_anim: String = ""
var _anim_clips: PackedStringArray = PackedStringArray()
var _nibble_cd: float = 0.0
var _nibble_target: Vector3 = Vector3.INF
var _nibble_seek_cd: float = 0.0
var _stomp_target: Vector3 = Vector3.INF
var _stomp_seek_cd: float = 0.0
var _scrape_tangent: Vector3 = Vector3.ZERO
var _scrape_misses: int = 0
var _scrape_flip_used: bool = false
var _scrape_stall_sec: float = 0.0


func setup(p_role: Role, director: Node, city: Node, world_pos: Vector3) -> void:
	role = p_role
	_director = director
	_city = city
	global_position = world_pos
	character_scale = 1.0
	_alive = true
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.45
	safe_margin = 0.08
	_build_body()
	_load_model()
	_apply_scale()
	if role == Role.MINION:
		## Stagger nibbles so a pack doesn't all bite on the same frame.
		_nibble_cd = randf_range(0.0, MINION_NIBBLE_INTERVAL_SEC)
	if role == Role.GIANT:
		state = State.STOMP
	else:
		state = State.SEEK_PED
	## If spawn/convert dropped them in solid, escape to a free footprint once.
	call_deferred("_ensure_free_spawn_footing")
	_play_anim(["Idle", "Idle_A", "idle"])


func is_alive() -> bool:
	return _alive


func is_mage() -> bool:
	return role == Role.MAGE


func is_giant() -> bool:
	return role == Role.GIANT or character_scale >= GIANT_SCALE_TARGET * 0.95


func _ensure_free_spawn_footing() -> void:
	if not _alive or not is_inside_tree():
		return
	if _can_stand_at(global_position):
		return
	_unstuck_cooldown = 0.0
	_unstuck_horizontal()


func hit_radius() -> float:
	return 0.55 * character_scale


func hit_half_height() -> float:
	return 0.95 * character_scale


func kill_from_player() -> int:
	if not _alive:
		return 0
	_alive = false
	state = State.DEAD
	velocity = Vector3.ZERO
	_play_anim(["Death_A", "Death", "death"])
	var award := HIT_SCORE_GIANT if is_giant() else HIT_SCORE_NORMAL
	died.emit(self, is_giant())
	var tree := get_tree()
	if tree != null:
		tree.create_timer(1.6).timeout.connect(queue_free)
	else:
		queue_free()
	return award


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
	floor_snap_length = clampf(0.35 * sqrt(character_scale), 0.35, 1.8)


func _update_collision_for_scale() -> void:
	if _capsule == null or _col_shape == null:
		return
	## Grow with sqrt so giants stay street-capable; hard-clamp for 10×.
	var r := clampf(0.28 * sqrt(character_scale), 0.28, COL_RADIUS_MAX_M)
	var h := clampf(1.15 * sqrt(character_scale), 1.15, COL_HEIGHT_MAX_M)
	_capsule.radius = r
	_capsule.height = maxf(h, r * 2.0 + 0.05)
	_col_shape.position = Vector3(0.0, h * 0.5, 0.0)


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	if _city != null and _city.has_method("is_player_alive") and not bool(_city.call("is_player_alive")):
		velocity = Vector3.ZERO
		return
	_cast_cd = maxf(0.0, _cast_cd - delta)
	_stomp_cd = maxf(0.0, _stomp_cd - delta)
	_ped_query_cd = maxf(0.0, _ped_query_cd - delta)
	_nibble_cd = maxf(0.0, _nibble_cd - delta)
	_nibble_seek_cd = maxf(0.0, _nibble_seek_cd - delta)
	_stomp_seek_cd = maxf(0.0, _stomp_seek_cd - delta)
	if not is_on_floor():
		velocity.y -= 28.0 * delta
	else:
		velocity.y = 0.0

	## Far units: skip expensive seek queries / anim switches most frames.
	var far := _distance_to_player() > ANIM_FAR_DIST_M
	if _anim != null:
		_anim.active = not far or role == Role.GIANT

	if role != Role.GIANT and _director != null and _director.has_method("wants_giant_candidate"):
		if bool(_director.call("wants_giant_candidate", self)):
			_begin_pad_seek()

	match state:
		State.SEEK_PED:
			if role == Role.MINION:
				_tick_minion_nibble(delta, far)
			elif far:
				_wander(delta)
			else:
				_tick_seek_ped(delta)
		State.CAST:
			_tick_cast()
		State.SEEK_PAD:
			_tick_seek_pad(delta)
		State.GROWING:
			_tick_growing(delta)
		State.STOMP:
			_tick_stomp(delta)
		_:
			velocity.x = 0.0
			velocity.z = 0.0
			_wish_dir = Vector3.ZERO

	move_and_slide()
	if role == Role.GIANT or not far:
		_slide_off_walls()
		_update_stuck(delta)
	if _unstuck_cooldown > 0.0:
		_unstuck_cooldown = maxf(0.0, _unstuck_cooldown - delta)
	_face_velocity(delta)


func _begin_pad_seek() -> void:
	if state == State.SEEK_PAD or state == State.GROWING or state == State.STOMP:
		return
	if _city == null or not _city.has_method("find_nearest_grow_pad"):
		return
	var pad: Node3D = _city.call("find_nearest_grow_pad", global_position, PAD_SEEK_RANGE_M) as Node3D
	if pad == null:
		return
	_target_pad = pad
	state = State.SEEK_PAD


func _tick_seek_ped(_delta: float) -> void:
	if role == Role.MAGE:
		_tick_mage_pursue(_delta)
		return
	var ped_pos := _nearest_ped_pos(12.0)
	if ped_pos == Vector3.INF:
		_wander(_delta)
		return
	var to := ped_pos - global_position
	to.y = 0.0
	_move_toward(to.normalized(), _move_speed())


func _tick_mage_pursue(_delta: float) -> void:
	var ped_pos := _nearest_ped_pos(MAGE_PURSUE_RANGE_M)
	if ped_pos == Vector3.INF:
		_wander(_delta)
		return
	var to := ped_pos - global_position
	to.y = 0.0
	var dist := to.length()
	## Soft leash — stop chasing once they break 40 m.
	if dist > MAGE_PURSUE_RANGE_M:
		_wander(_delta)
		return
	if dist <= ORB_RANGE_M * 0.92 and _cast_cd <= 0.0:
		state = State.CAST
		velocity.x = 0.0
		velocity.z = 0.0
		return
	_move_toward(to.normalized(), _move_speed())


func _tick_minion_nibble(delta: float, far: bool) -> void:
	if _nibble_seek_cd <= 0.0 or _nibble_target == Vector3.INF:
		_nibble_seek_cd = 0.7 if far else 0.35
		_nibble_target = _nearest_building_pos(MINION_BUILDING_SEEK_M)
	if _nibble_target == Vector3.INF:
		_wander(delta)
		return
	var to := _nibble_target - global_position
	to.y = 0.0
	var dist := to.length()
	if dist > MINION_NIBBLE_REACH_M:
		_move_toward(to.normalized(), _move_speed())
		return
	## Locked on facade — keep swinging the whole time; voxel only dies every 15s.
	velocity.x = 0.0
	velocity.z = 0.0
	_wish_dir = Vector3.ZERO
	_look_at_flat(_nibble_target)
	_play_anim_looping(["Kick_A", "Punch_A", "Attack", "Hit_A", "Spellcast_Shoot"])
	if _nibble_cd > 0.0:
		return
	if _city != null and _city.has_method("undead_nibble_building_near"):
		var ok: bool = bool(_city.call("undead_nibble_building_near", global_position, MINION_NIBBLE_REACH_M + 1.2))
		if ok:
			_nibble_cd = MINION_NIBBLE_INTERVAL_SEC
			## Stay on this facade and keep kicking — only reacquire if the wall is gone.
		else:
			_nibble_target = Vector3.INF
			_nibble_seek_cd = 0.15


func _tick_cast() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_play_anim(["Spellcast_Shoot", "Spellcast_Raise", "Attack", "Spellcast"])
	## Fresh aim — don't fire at a stale cached flee position.
	_ped_query_cd = 0.0
	var ped_pos := _nearest_ped_pos(ORB_RANGE_M)
	if ped_pos == Vector3.INF:
		state = State.SEEK_PED
		return
	_look_at_flat(ped_pos)
	_fire_orb(ped_pos)
	_cast_cd = CAST_COOLDOWN_SEC
	state = State.SEEK_PED


func _tick_seek_pad(_delta: float) -> void:
	if _target_pad == null or not is_instance_valid(_target_pad):
		state = State.SEEK_PED
		return
	var pad_pos := _target_pad.global_position
	var to := pad_pos - global_position
	to.y = 0.0
	var dist := to.length()
	var reach := 2.4
	if _target_pad.get("pad_radius") != null:
		reach = float(_target_pad.pad_radius) * 0.85
	if dist <= reach:
		state = State.GROWING
		velocity.x = 0.0
		velocity.z = 0.0
		_play_anim(["Idle", "Idle_A", "idle"])
		return
	_move_toward(to.normalized(), _move_speed())


func _tick_growing(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _target_pad == null or not is_instance_valid(_target_pad):
		state = State.SEEK_PED
		return
	var d := Vector2(
		global_position.x - _target_pad.global_position.x,
		global_position.z - _target_pad.global_position.z
	).length()
	var reach := 3.5
	if _target_pad.get("pad_radius") != null:
		reach = float(_target_pad.pad_radius) + 0.8
	if d > reach:
		state = State.SEEK_PAD
		return
	character_scale = minf(GIANT_SCALE_TARGET, character_scale * exp(GROW_LOG_RATE * delta))
	_apply_scale()
	if character_scale >= GIANT_SCALE_TARGET - 0.05:
		character_scale = GIANT_SCALE_TARGET
		_apply_scale()
		role = Role.GIANT
		state = State.STOMP
		if _director != null and _director.has_method("notify_giant_ready"):
			_director.call("notify_giant_ready", self)
		_play_anim(["Idle", "Idle_A", "idle"])


func _tick_stomp(delta: float) -> void:
	## Approach a facade, then walk parallel while peeling full-height strips.
	if _stomp_seek_cd <= 0.0 or _stomp_target == Vector3.INF:
		_stomp_seek_cd = GIANT_BUILDING_QUERY_SEC
		_stomp_target = _nearest_building_pos(GIANT_BUILDING_SEEK_M)
		if _stomp_target != Vector3.INF:
			_scrape_misses = 0
			_scrape_flip_used = false
			_scrape_stall_sec = 0.0
			_scrape_tangent = Vector3.ZERO
	if _stomp_target == Vector3.INF:
		_scrape_tangent = Vector3.ZERO
		_wander(delta)
		return
	var to_wall := _stomp_target - global_position
	to_wall.y = 0.0
	var dist := to_wall.length()
	if dist < 0.05:
		_abandon_scrape_face(true)
		return
	var inward := to_wall / dist
	## Still closing distance — walk straight at the wall.
	if dist > GIANT_APPROACH_DIST_M:
		_scrape_tangent = Vector3.ZERO
		_move_toward(inward, _move_speed())
		return
	## Pick / keep a tangent along the facade.
	if _scrape_tangent.length_squared() < 0.01:
		_scrape_tangent = Vector3(-inward.z, 0.0, inward.x)
		if randf() < 0.5:
			_scrape_tangent = -_scrape_tangent
		_scrape_tangent = _scrape_tangent.normalized()
	## Hold standoff: ease in/out so the capsule brushes the wall without embedding.
	var hold := GIANT_SCRAPE_DIST_M
	var radial := Vector3.ZERO
	if dist > hold + 0.55:
		radial = inward
	elif dist < hold - 0.45:
		radial = -inward
	var wish := (_scrape_tangent + radial * 0.55).normalized()
	_move_toward(wish, _move_speed() * 0.82)
	## Face along the scrape so the brush reads as dragging the shoulder into the wall.
	_look_at_flat(global_position + _scrape_tangent)
	if _stomp_cd > 0.0:
		return
	_stomp_cd = SCRAPE_INTERVAL_SEC
	var contact := global_position + inward * maxf(dist * 0.92, hold * 0.85)
	contact.y = global_position.y + 1.2
	var removed := 0
	if _city != null and _city.has_method("undead_giant_scrape_at"):
		removed = int(_city.call("undead_giant_scrape_at", contact, inward, _scrape_tangent))
	if removed <= 0:
		_scrape_misses += 1
		_scrape_stall_sec += SCRAPE_INTERVAL_SEC
		if _scrape_misses >= GIANT_SCRAPE_MISS_LIMIT or _scrape_stall_sec >= 1.2:
			_on_scrape_face_dead()
	else:
		_scrape_misses = 0
		_scrape_stall_sec = 0.0
		## Nudge the aim point along the wall so we keep peeling the next strip.
		_stomp_target = _stomp_target + _scrape_tangent * 1.6


func _on_scrape_face_dead() -> void:
	## Hollow shell / floor stubs — reverse once, then abandon for a fresh building.
	if not _scrape_flip_used and _scrape_tangent.length_squared() > 0.01:
		_scrape_tangent = -_scrape_tangent
		_scrape_flip_used = true
		_scrape_misses = 0
		_scrape_stall_sec = 0.0
		_stomp_target = global_position + _scrape_tangent * 4.0 + _wish_dir * 0.1
		return
	_abandon_scrape_face(true)


func _abandon_scrape_face(step_out: bool) -> void:
	_scrape_misses = 0
	_scrape_stall_sec = 0.0
	_scrape_flip_used = false
	_scrape_tangent = Vector3.ZERO
	_stomp_target = Vector3.INF
	_stomp_seek_cd = 0.55
	if step_out:
		## Back off the hollow facade so the next seek doesn't re-lock the same stubs.
		var back := -_wish_dir
		back.y = 0.0
		if back.length_squared() < 0.01:
			back = Vector3(-sin(_yaw), 0.0, -cos(_yaw))
		else:
			back = back.normalized()
		global_position += back * 2.4
		_wish_dir = back
		velocity.x = back.x * _move_speed()
		velocity.z = back.z * _move_speed()


func _do_stomp(_toward_wish: bool) -> void:
	## Stuck recovery: peel whatever is ahead, then change course off this face.
	_stomp_cd = SCRAPE_INTERVAL_SEC
	var ahead := _wish_dir
	if ahead.length_squared() < 0.01:
		ahead = Vector3(sin(_yaw), 0.0, cos(_yaw))
	ahead = ahead.normalized()
	var contact := global_position + ahead * GIANT_SCRAPE_DIST_M
	contact.y = global_position.y + 1.2
	if _city != null and _city.has_method("undead_giant_scrape_at"):
		_city.call("undead_giant_scrape_at", contact, ahead, Vector3(-ahead.z, 0.0, ahead.x))
	_abandon_scrape_face(true)


func _fire_orb(toward: Vector3) -> void:
	var orb: Node = OrbScript.new()
	orb.name = "UndeadOrb"
	var parent: Node = _director if _director != null else self
	parent.add_child(orb)
	var muzzle := global_position + Vector3(0.0, 1.35 * character_scale, 0.0)
	if orb.has_method("launch"):
		orb.call("launch", muzzle, toward + Vector3(0.0, 1.0, 0.0), _director)


func _nearest_ped_pos(max_dist: float) -> Vector3:
	if _ped_query_cd > 0.0 and _cached_ped_pos != Vector3.INF:
		return _cached_ped_pos
	_ped_query_cd = PED_QUERY_INTERVAL_SEC
	if _city == null or not _city.has_method("find_nearest_ped_position"):
		_cached_ped_pos = Vector3.INF
		return Vector3.INF
	_cached_ped_pos = _city.call("find_nearest_ped_position", global_position, max_dist) as Vector3
	return _cached_ped_pos


func _nearest_building_pos(max_dist: float) -> Vector3:
	if _city == null or not _city.has_method("find_nearest_building_nibble"):
		return Vector3.INF
	return _city.call("find_nearest_building_nibble", global_position, max_dist) as Vector3


func _distance_to_player() -> float:
	if _city == null or not _city.has_method("get_player_position"):
		return 0.0
	var p: Vector3 = _city.call("get_player_position") as Vector3
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


func _move_toward(dir: Vector3, speed: float) -> void:
	_wish_dir = dir
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_play_locomotion(speed)


func _wander(delta: float) -> void:
	_wander_accum += delta
	if _wander_accum > 2.2 or _wish_dir.length_squared() < 0.01:
		_wander_accum = 0.0
		var ang := randf() * TAU
		_wish_dir = Vector3(cos(ang), 0.0, sin(ang))
	var spd := _move_speed() * 0.55
	velocity.x = _wish_dir.x * spd
	velocity.z = _wish_dir.z * spd
	_play_locomotion(spd)


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
		## Idle / scrape / unstuck clips stay heavy too.
		_anim.speed_scale = minf(scale, GIANT_ANIM_SPEED)
	else:
		_anim.speed_scale = scale


func _slide_off_walls() -> void:
	var count := get_slide_collision_count()
	if count <= 0:
		return
	var push := Vector3.ZERO
	for i in range(count):
		var col := get_slide_collision(i)
		if col == null:
			continue
		var n := col.get_normal()
		n.y = 0.0
		if n.length_squared() < 0.0001:
			continue
		push += n.normalized()
	if push.length_squared() < 0.0001:
		return
	push = push.normalized()
	## Tiny separation only — large position pops read as teleports on slow mages.
	var sep := clampf(0.025 * maxf(character_scale * 0.2, 1.0), 0.025, 0.12)
	global_position += push * sep
	## Prefer sliding along the wall rather than cancelling all wish motion.
	if _wish_dir.length_squared() > 0.01:
		var slide := _wish_dir.slide(push)
		if slide.length_squared() > 0.01:
			var spd := maxf(Vector2(velocity.x, velocity.z).length(), _move_speed() * 0.65)
			slide = slide.normalized()
			velocity.x = slide.x * spd
			velocity.z = slide.z * spd
			_wish_dir = slide


func _update_stuck(delta: float) -> void:
	## Compare wish vs actual horizontal speed — never use a fixed m/frame gate
	## (slow mages move ~0.017 m/tick at 60 Hz and falsely tripped the old 0.05 check).
	var wish_spd := _move_speed() if _wish_dir.length_squared() > 0.01 else 0.0
	if wish_spd < 0.2:
		_stuck_timer = 0.0
		return
	var real := get_real_velocity()
	var real_h := Vector2(real.x, real.z).length()
	if real_h < wish_spd * 0.12:
		_stuck_timer += delta
	else:
		_stuck_timer = maxf(0.0, _stuck_timer - delta * 1.5)
	if _stuck_timer < STUCK_TIME_SEC:
		return
	_stuck_timer = 0.0
	## Giants peel then abandon the face; everyone else relocates to a free footprint.
	if role == Role.GIANT or character_scale >= 2.0:
		_do_stomp(true)
		return
	if not _unstuck_horizontal():
		## Soft pivot if no free cell — keep moving, don't hop into solids.
		var side := Vector3(-_wish_dir.z, 0.0, _wish_dir.x)
		if side.length_squared() < 0.01:
			side = Vector3.RIGHT
		else:
			side = side.normalized()
		if randf() < 0.5:
			side = -side
		_wish_dir = side
		velocity.x = side.x * _move_speed()
		velocity.z = side.z * _move_speed()


func _unstuck_horizontal() -> bool:
	if _unstuck_cooldown > 0.0:
		return false
	_unstuck_cooldown = 0.5
	var origin := global_position
	var r0 := 0.45 * maxf(sqrt(character_scale), 1.0)
	var radii: Array[float] = [r0, r0 * 2.0, r0 * 3.5, r0 * 5.5]
	var prefer := _wish_dir
	prefer.y = 0.0
	if prefer.length_squared() < 0.0001:
		prefer = Vector3(sin(_yaw), 0.0, cos(_yaw))
	else:
		prefer = prefer.normalized()
	## Prefer escaping opposite the jammed wish (usually out of a facade).
	prefer = -prefer
	for radius in radii:
		for i in 12:
			var ang := atan2(prefer.x, prefer.z) + TAU * float(i) / 12.0
			var candidate := origin + Vector3(sin(ang) * radius, 0.0, cos(ang) * radius)
			if not _can_stand_at(candidate):
				continue
			global_position = candidate
			velocity.x = prefer.x * _move_speed()
			velocity.z = prefer.z * _move_speed()
			_wish_dir = prefer
			return true
	return false


func _can_stand_at(pos: Vector3) -> bool:
	var xf := global_transform
	xf.origin = pos
	var s := clampf(0.14 * maxf(sqrt(character_scale), 1.0), 0.12, 0.4)
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
	return free >= 2


func _face_velocity(delta: float) -> void:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length_squared() < 0.04:
		return
	var want := atan2(flat.x, flat.z)
	_yaw = lerp_angle(_yaw, want, clampf(10.0 * delta, 0.0, 1.0))
	rotation.y = _yaw


func _look_at_flat(world: Vector3) -> void:
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
