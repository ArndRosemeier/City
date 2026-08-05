## Per-body combat kit: resolved CombatTable stats, attack cooldowns, and execution.
##
## Owned by `UndeadUnit`. Keeps the unit's Role/State machine for navigation and growth,
## while attack choice and the damage it deals come from the shared combat tables.
##
## Typed loosely on purpose: this script and `undead_unit.gd` preload each other, so naming
## `UndeadUnit` / `CombatTable.EffectiveStats` here breaks class_name resolution at parse time.
class_name MonsterCombat
extends RefCounted

const CombatTableScript := preload("res://scripts/city/combat_table.gd")
const DamageSourceScript := preload("res://scripts/city/damage_source.gd")
const MonsterFactionScript := preload("res://scripts/city/monster_faction.gd")
const EyeLaserScript := preload("res://scripts/city/eye_laser_vfx.gd")
const BlasterBoltScript := preload("res://scripts/city/blaster_bolt_vfx.gd")

## Projectiles and area strikes that use preferred / monster range.
const RANGED_KINDS: PackedStringArray = [
	"eye_laser", "blaster", "orb_convert", "charged_blast", "stomp"
]

## Shared recovery after ANY attack fires. Without it a multi-attack kit empties its whole
## pool back to back the moment line of sight opens — a freed cage boss threw laser, blaster
## burst and charged blast inside three seconds. Per-attack cooldowns still apply on top.
const GLOBAL_COOLDOWN_S := 2.0

## Stand-off for a terrain-chewing body: close enough to be a physical threat, far enough that
## it is not standing inside the player.
const CHEWER_STANDOFF_M := 3.0
## Melee corridor aim as a fraction of strike reach. Must leave room for
## `UndeadGoalProvider.HUNT_ARRIVE_TOLERANCE_M` so arriving still means "can swing".
const MELEE_STANDOFF_FRACTION := 0.7
## Reference hit radius for a 1× minion — extras above this grow the swing so a fat body is
## not forever short of a prey it is already pressing against.
const MELEE_REFERENCE_HIT_RADIUS_M := 0.55

## UndeadUnit that owns this kit.
var _unit: CharacterBody3D = null
## CombatTable.EffectiveStats
var _stats: RefCounted = null
## attack_id → seconds until ready
var _cooldown: Dictionary = {}
## Seconds left on the shared post-attack recovery (blocks every attack, see GLOBAL_COOLDOWN_S).
var _global_cooldown: float = 0.0
## Seconds left on a telegraph before the pending attack fires.
var _windup_left: float = 0.0
var _windup_attack: String = ""
var _windup_prey: Vector3 = Vector3.INF
## Blaster burst remaining after the first bolt of a monster burst.
var _blaster_burst_left: int = 0
var _blaster_burst_cd: float = 0.0


func bind(unit: CharacterBody3D, stats: RefCounted) -> void:
	if unit == null:
		push_error("MonsterCombat.bind: no unit")
		assert(false, "MonsterCombat: no unit")
		return
	if stats == null:
		push_error("MonsterCombat.bind: no stats for %s" % unit.name)
		assert(false, "MonsterCombat: no stats")
		return
	_unit = unit
	_stats = stats
	_cooldown.clear()
	_global_cooldown = 0.0
	_windup_left = 0.0
	_windup_attack = ""
	_windup_prey = Vector3.INF
	_blaster_burst_left = 0
	_blaster_burst_cd = 0.0
	var attacks: PackedStringArray = _stats.get("attacks") as PackedStringArray
	for attack_id: String in attacks:
		## Loud resolve — unknown ids must fail at spawn, not on the first swing.
		var _row: Dictionary = CombatTableScript.attack_def(attack_id)
		_cooldown[attack_id] = 0.0


func stats() -> RefCounted:
	return _stats


func damage_mult() -> float:
	return float(_stats.get("damage_mult")) if _stats != null else 1.0


func armor_mult() -> float:
	return float(_stats.get("armor_mult")) if _stats != null else 1.0


func hp_mult() -> float:
	return float(_stats.get("hp_mult")) if _stats != null else 1.0


## Multiply live attack damage (and the sync `attack_damage` table) by `mult`.
func multiply_damage_mult(mult: float) -> void:
	if _stats == null:
		push_error("MonsterCombat.multiply_damage_mult: no stats")
		assert(false, "MonsterCombat: no stats")
		return
	if mult <= 0.0:
		push_error("MonsterCombat.multiply_damage_mult: non-positive %f" % mult)
		assert(false, "MonsterCombat: bad damage mult")
		return
	var next := damage_mult() * mult
	_stats.call("set_scalar", "damage_mult", next)
	var attacks: PackedStringArray = _stats.get("attacks") as PackedStringArray
	_stats.set("attack_damage", CombatTableScript.effective_attack_damages(attacks, next))


## Replace hp_mult so `_reset_health` / grow pads keep a chosen max HP at the current scale.
func set_hp_mult(value: float) -> void:
	if _stats == null:
		push_error("MonsterCombat.set_hp_mult: no stats")
		assert(false, "MonsterCombat: no stats")
		return
	if value <= 0.0:
		push_error("MonsterCombat.set_hp_mult: non-positive %f" % value)
		assert(false, "MonsterCombat: bad hp mult")
		return
	_stats.call("set_scalar", "hp_mult", value)


func speed_mult() -> float:
	return float(_stats.get("speed_mult")) if _stats != null else 1.0


func aggro_range_m() -> float:
	return float(_stats.get("aggro_range_m")) if _stats != null else 0.0


func leash_m() -> float:
	return float(_stats.get("leash_m")) if _stats != null else 0.0


func preferred_range_m() -> float:
	return float(_stats.get("preferred_range_m")) if _stats != null else 0.0


## Whether this body hunts at all. Who it hunts is not a property of the kit — that is
## faction against faction — so the only question left is whether it has something to swing
## and a range at which it notices anyone. Ambient bodies have neither.
func hunts_living() -> bool:
	if _stats == null:
		return false
	var attacks: PackedStringArray = _stats.get("attacks") as PackedStringArray
	return not attacks.is_empty() and aggro_range_m() > 0.0


func has_attack(attack_id: String) -> bool:
	if _stats == null:
		return false
	var attacks: PackedStringArray = _stats.get("attacks") as PackedStringArray
	for a: String in attacks:
		if a == attack_id:
			return true
	return false


## Whether this one attack's own timer is up. Deliberately blind to the shared recovery:
## callers ask about a specific tool (`UndeadUnit.can_cast`, orb stand-off), and folding the
## GCD in here made a mage "done casting" the moment it fired anything at all.
func is_attack_ready(attack_id: String) -> bool:
	if not has_attack(attack_id):
		return false
	return float(_cooldown.get(attack_id, 0.0)) <= 0.0


## Seconds left on the shared recovery — 0 when any attack may start.
func global_cooldown_left() -> float:
	return _global_cooldown


## Stand-off the navigator aims for while hunting living prey.
func hunt_standoff_m() -> float:
	if _stats == null:
		return 2.0
	## A body that chews terrain closes to contact. Holding artillery range meant the cage
	## boss was already "in range" from across the cave, so the provider handed it no goal at
	## all and it never took the step its aura needs.
	if _unit != null and bool(_unit.call("chews_terrain")):
		return CHEWER_STANDOFF_M
	## Orb casters hold convert range when the orb is ready (legacy mage cadence).
	if has_attack("orb_convert") and is_attack_ready("orb_convert"):
		return CombatTableScript.monster_attack_range_m("orb_convert") * 0.92
	var ranged := _ready_ranged_attack()
	if ranged != "" and ranged != "orb_convert":
		return maxf(preferred_range_m(), 1.5)
	if has_attack("melee"):
		## Inside strike reach, with slack for the hunt arrive radius. Standing at 0.85× and
		## arriving with 1.5 m of slop used to land bodies outside the swing entirely.
		return CombatTableScript.monster_attack_range_m("melee") * MELEE_STANDOFF_FRACTION
	return maxf(preferred_range_m(), 1.5)


## Hold-and-strike distance for a hunt. Wider than `hunt_standoff_m` on purpose: the corridor
## aims at the stand-off, but once the body is inside swing reach it must stop pathing and hit.
func hunt_engage_m() -> float:
	if has_attack("melee"):
		return _melee_reach_m()
	return hunt_standoff_m()


func tick(delta: float) -> void:
	if _stats == null or _unit == null or not bool(_unit.call("is_alive")):
		return
	for attack_id: String in _cooldown.keys():
		_cooldown[attack_id] = maxf(0.0, float(_cooldown[attack_id]) - delta)
	_global_cooldown = maxf(0.0, _global_cooldown - delta)
	_blaster_burst_cd = maxf(0.0, _blaster_burst_cd - delta)
	if _blaster_burst_left > 0 and _blaster_burst_cd <= 0.0:
		_fire_blaster_bolt(_windup_prey if _windup_prey != Vector3.INF else _unit.global_position)
		return
	if _windup_left > 0.0:
		_windup_left = maxf(0.0, _windup_left - delta)
		if _windup_left > 0.0:
			return
		_finish_windup()


## Try to strike living prey this frame. Returns true when an attack started or landed.
func try_attack_living(prey: Vector3) -> bool:
	if _stats == null or _unit == null or not bool(_unit.call("is_alive")):
		return false
	if prey == Vector3.INF:
		return false
	if _windup_left > 0.0 or _blaster_burst_left > 0:
		return true
	## Still recovering from the last attack — busy, not out of options.
	if _global_cooldown > 0.0:
		return true
	var dist := _flat_distance(_unit.global_position, prey)
	var attack_id := _pick_attack(dist)
	if attack_id.is_empty():
		return false
	## Ranged kits need a clear voxel corridor — same filter as prey selection.
	if _is_ranged_attack(attack_id) and not _has_voxel_los_to(prey):
		return false
	return _begin_attack(attack_id, prey)


func _pick_attack(dist_m: float) -> String:
	if _global_cooldown > 0.0:
		return ""
	var attacks: PackedStringArray = _stats.get("attacks") as PackedStringArray
	var best := ""
	var best_score := -1.0
	for attack_id: String in attacks:
		if float(_cooldown.get(attack_id, 0.0)) > 0.0:
			continue
		var reach := _attack_reach_m(attack_id)
		if dist_m > reach:
			continue
		var score := reach
		## Prefer a ready ranged poke when inside preferred range; otherwise melee.
		if attack_id == "melee":
			score = 1000.0 - dist_m
		elif attack_id == "orb_convert":
			score = 800.0
		elif attack_id == "eye_laser":
			score = 700.0
		elif attack_id == "blaster":
			score = 650.0
		elif attack_id == "stomp":
			score = 600.0
		elif attack_id == "charged_blast":
			score = 550.0
		if score > best_score:
			best_score = score
			best = attack_id
	return best


func _attack_reach_m(attack_id: String) -> float:
	if attack_id == "melee":
		return _melee_reach_m()
	return CombatTableScript.monster_attack_range_m(attack_id)


## Contact swing, grown with the body's hit volume so a broad attacker is not short of a prey
## it is already touching.
func _melee_reach_m() -> float:
	var base := CombatTableScript.monster_attack_range_m("melee")
	if _unit == null or not _unit.has_method("hit_radius"):
		return base
	var hit_r := float(_unit.call("hit_radius"))
	return base + maxf(0.0, hit_r - MELEE_REFERENCE_HIT_RADIUS_M)


## Ranged tool whose own timer is up, for the stand-off the navigator holds. Like
## `is_attack_ready` this ignores the shared recovery — a two-second GCD must not make a
## ranged body abandon its distance and charge.
func _ready_ranged_attack() -> String:
	for attack_id: String in RANGED_KINDS:
		if not has_attack(attack_id):
			continue
		if float(_cooldown.get(attack_id, 0.0)) > 0.0:
			continue
		return attack_id
	return ""


func _begin_attack(attack_id: String, prey: Vector3) -> bool:
	var windup := CombatTableScript.monster_attack_windup_s(attack_id)
	_unit.call("face_combat_prey", prey)
	if windup > 0.0:
		_windup_left = windup
		_windup_attack = attack_id
		_windup_prey = prey
		_unit.call("play_combat_windup", attack_id)
		## Charged blast holds the same charge ramp the player hears while winding up.
		if attack_id == "charged_blast":
			_sfx(
				"play_charged_blast_charge",
				_unit.global_position,
				_scale(),
				windup
			)
		return true
	return _execute_attack(attack_id, prey)


func _finish_windup() -> void:
	var attack_id := _windup_attack
	var prey := _windup_prey
	_windup_attack = ""
	_windup_prey = Vector3.INF
	if attack_id.is_empty() or prey == Vector3.INF:
		_stop_charged_sfx()
		return
	## Re-check range after the telegraph — prey may have walked out.
	var reach := _attack_reach_m(attack_id)
	if _flat_distance(_unit.global_position, prey) > reach * 1.15:
		_stop_charged_sfx()
		return
	## Voxel LOS can close during windup (door, corner, glass lip).
	if _is_ranged_attack(attack_id) and not _has_voxel_los_to(prey):
		_stop_charged_sfx()
		return
	_execute_attack(attack_id, prey)


func _is_ranged_attack(attack_id: String) -> bool:
	for kind: String in RANGED_KINDS:
		if kind == attack_id:
			return true
	return false


func _has_voxel_los_to(prey: Vector3) -> bool:
	var city: Node = _unit.call("city") as Node
	if city == null or not city.has_method("has_voxel_line_of_sight"):
		return true
	var muzzle: Vector3 = _unit.call("muzzle_world") as Vector3
	return bool(city.call("has_voxel_line_of_sight", muzzle, prey))


## Shared CityRoot solid-voxel (+ optional agent) mid-flight probe. Mobs ignore agents so
## packs do not block each other's shots; walls / glass / arena shell still stop bolts.
func _bind_projectile_probe(bolt: Node, include_agents: bool = false) -> void:
	if bolt == null or not bolt.has_method("set_obstacle_probe"):
		return
	var city: Node = _unit.call("city") as Node
	if city == null or not city.has_method("projectile_obstacle_distance"):
		return
	bolt.call(
		"set_obstacle_probe",
		func(from: Vector3, tip: Vector3) -> float:
			return float(city.call("projectile_obstacle_distance", from, tip, include_agents))
	)


func _execute_attack(attack_id: String, prey: Vector3) -> bool:
	match attack_id:
		"melee":
			return _execute_melee(prey)
		"orb_convert":
			return _execute_orb(prey)
		"eye_laser":
			return _execute_eye_laser(prey)
		"blaster":
			return _execute_blaster(prey)
		"stomp":
			return _execute_stomp(prey)
		"charged_blast":
			return _execute_charged_blast(prey)
		_:
			push_error(
				"MonsterCombat: body '%s' has unimplemented attack '%s'"
				% [str(_stats.get("monster_id")), attack_id]
			)
			assert(false, "MonsterCombat: unimplemented attack")
			return false


func _execute_melee(prey: Vector3) -> bool:
	_unit.call("play_combat_strike", "melee")
	_set_cooldown("melee")
	var scale := _scale()
	var at: Vector3 = _unit.global_position
	var reach := _melee_reach_m()
	_sfx("play_melee_swing", at, scale)
	_sfx("play_melee_hit", prey, scale)
	if _is_player_prey(prey):
		_hurt_player(DamageSourceScript.Id.MONSTER_MELEE)
		return true
	var mob := _hostile_monster_near(prey, reach)
	if mob != null:
		_hurt_monster(mob, "melee")
		return true
	## Pedestrian: one-shot remove. Nothing here swings at fabric.
	_unit.call("try_remove_ped_at", prey, reach)
	return true


func _execute_orb(prey: Vector3) -> bool:
	_unit.call("play_combat_strike", "orb_convert")
	_set_cooldown("orb_convert")
	var muzzle: Vector3 = _unit.call("muzzle_world") as Vector3
	_sfx("play_orb_cast", muzzle, _scale())
	_unit.call("fire_convert_orb", prey)
	return true


func _execute_eye_laser(prey: Vector3) -> bool:
	_unit.call("play_combat_strike", "eye_laser")
	_set_cooldown("eye_laser")
	var row := CombatTableScript.attack_def("eye_laser")
	var speed := float(row.get("speed_mps", 60.0))
	var muzzle: Vector3 = _unit.call("muzzle_world") as Vector3
	var bolt: Node3D = EyeLaserScript.new() as Node3D
	_vfx_parent().add_child(bolt)
	bolt.call("setup")
	var scale: float = float(_unit.get("character_scale"))
	bolt.call("set_character_scale", maxf(scale, 0.05))
	_bind_projectile_probe(bolt, false)
	bolt.connect("impact", _on_eye_laser_impact)
	## Prey is already an aim-height point from LOS selection.
	bolt.call("fire", muzzle, prey, speed, scale)
	_sfx("play_laser_fire", muzzle, scale)
	return true


func _on_eye_laser_impact(hit_point: Vector3, direction: Vector3) -> void:
	if _unit == null or not bool(_unit.call("is_alive")):
		return
	_sfx("play_laser_impact", hit_point, _scale())
	if _player_near_los(hit_point, 2.8):
		_hurt_player(DamageSourceScript.Id.MONSTER_LASER)
		return
	var mob := _hostile_monster_near(hit_point, 2.8)
	if mob != null:
		_hurt_monster(mob, "eye_laser")
		return
	_strike_voxels_at_impact(hit_point, direction)


func _execute_blaster(prey: Vector3) -> bool:
	_unit.call("play_combat_strike", "blaster")
	_set_cooldown("blaster")
	var row := CombatTableScript.attack_def("blaster")
	var burst := int(row.get("monster_burst_count", row.get("burst_count", 1)))
	_blaster_burst_left = maxi(burst - 1, 0)
	_windup_prey = prey
	_fire_blaster_bolt(prey)
	return true


func _fire_blaster_bolt(prey: Vector3) -> void:
	var row := CombatTableScript.attack_def("blaster")
	var speed := float(row.get("speed_mps", 30.0))
	var interval := float(row.get("monster_fire_interval_s", row.get("fire_interval_s", 0.35)))
	var muzzle: Vector3 = _unit.call("muzzle_world") as Vector3
	var bolt: Node3D = BlasterBoltScript.new() as Node3D
	_vfx_parent().add_child(bolt)
	bolt.call("setup")
	var scale: float = float(_unit.get("character_scale"))
	bolt.call("set_character_scale", maxf(scale, 0.05))
	_bind_projectile_probe(bolt, false)
	bolt.connect("impact", _on_blaster_impact)
	## Prey is already an aim-height point from LOS selection.
	bolt.call("fire", muzzle, prey, speed, scale)
	_sfx("play_laser_fire", muzzle, scale)
	if _blaster_burst_left > 0:
		_blaster_burst_left -= 1
		_blaster_burst_cd = interval
	else:
		_windup_prey = Vector3.INF


func _vfx_parent() -> Node:
	var parent := _unit.get_parent()
	if parent != null and is_instance_valid(parent):
		return parent
	return _unit


func _on_blaster_impact(hit_point: Vector3, direction: Vector3, _shot_origin: Vector3) -> void:
	if _unit == null or not bool(_unit.call("is_alive")):
		return
	_sfx("play_laser_impact", hit_point, _scale())
	if _player_near_los(hit_point, 2.8):
		_hurt_player(DamageSourceScript.Id.MONSTER_BLASTER)
		return
	var mob := _hostile_monster_near(hit_point, 2.8)
	if mob != null:
		_hurt_monster(mob, "blaster")
		return
	_strike_voxels_at_impact(hit_point, direction)


func _strike_voxels_at_impact(hit_point: Vector3, direction: Vector3) -> void:
	var city: Node = _unit.call("city") as Node
	if city == null or not city.has_method("apply_voxel_strike"):
		return
	var dir := direction
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
	else:
		dir = dir.normalized()
	var scale: float = float(_unit.get("character_scale"))
	city.call(
		"apply_voxel_strike",
		hit_point - dir * 0.15,
		dir,
		maxf(2.5, scale * 2.0),
		maxf(scale, 0.5)
	)


func _execute_stomp(prey: Vector3) -> bool:
	_unit.call("play_combat_strike", "stomp")
	_set_cooldown("stomp")
	var row := CombatTableScript.attack_def("stomp")
	var scale: float = float(_unit.get("character_scale"))
	var radius := float(row.get("radius_m", 2.52)) * maxf(scale, 0.05)
	_sfx("play_stomp", _unit.global_position, scale)
	if _is_player_prey(prey) and _flat_distance(_unit.global_position, prey) <= radius:
		_hurt_player(DamageSourceScript.Id.MONSTER_STOMP)
	var mob := _hostile_monster_near(prey, radius)
	if mob != null and _flat_distance(_unit.global_position, mob.global_position) <= radius:
		_hurt_monster(mob, "stomp")
	return true


func _execute_charged_blast(prey: Vector3) -> bool:
	_unit.call("play_combat_strike", "charged_blast")
	_set_cooldown("charged_blast")
	var row := CombatTableScript.attack_def("charged_blast")
	var radius := float(row.get("radius_m", 2.52))
	var scale := _scale()
	var at: Vector3 = _unit.global_position
	_sfx("play_charged_blast_throw", at, scale)
	_sfx("play_charged_blast_impact", prey, scale)
	## Vertical slice: telegraphed hit on the player / hostile if still near the aim point.
	var city: Node = _unit.call("city") as Node
	if _is_player_prey(prey):
		if city != null and bool(city.call("is_player_alive")):
			var ppos: Vector3 = city.call("get_player_target_position") as Vector3
			if prey.distance_to(ppos) <= radius + 1.2:
				_hurt_player(DamageSourceScript.Id.MONSTER_BLAST)
	var mob := _hostile_monster_near(prey, radius + 1.2)
	if mob != null and prey.distance_to(mob.global_position) <= radius + 1.2:
		_hurt_monster(mob, "charged_blast")
	## Always carve when the attack row says so — caves need the sphere to open rock.
	if bool(row.get("carves_voxels", false)):
		if city == null or not city.has_method("apply_charged_blast"):
			push_error("MonsterCombat: CityRoot missing apply_charged_blast")
			assert(false, "MonsterCombat: no charged blast carve")
		else:
			city.call("apply_charged_blast", prey, radius * scale)
	return true


func _scale() -> float:
	return maxf(float(_unit.get("character_scale")), 0.05)


func _city_audio() -> Node:
	var tree := _unit.get_tree() if _unit != null else null
	if tree == null:
		return null
	return tree.get_first_node_in_group(&"city_audio")


## Optional fourth arg for charge_sec on play_charged_blast_charge.
func _sfx(method: String, world_pos: Vector3, character_scale: float, extra: float = -1.0) -> void:
	var audio := _city_audio()
	if audio == null or not audio.has_method(method):
		return
	if extra >= 0.0:
		audio.call(method, world_pos, character_scale, extra)
	else:
		audio.call(method, world_pos, character_scale)


func _stop_charged_sfx() -> void:
	var audio := _city_audio()
	if audio != null and audio.has_method("stop_charged_blast_charge"):
		audio.call("stop_charged_blast_charge")


func _hurt_player(source: DamageSource.Id) -> void:
	if not _hostile_to_player():
		return
	var city: Node = _unit.call("city") as Node
	if city == null:
		return
	city.call("damage_player_scaled", source, damage_mult())


func _hurt_monster(target: CharacterBody3D, attack_id: String) -> void:
	if target == null or not is_instance_valid(target):
		return
	if not bool(target.call("is_alive")):
		return
	if not bool(_unit.call("is_hostile_to", target)):
		return
	var source: DamageSource.Id = DamageSourceScript.for_monster_attack_mob(attack_id)
	var attacker_label: String = str(_stats.get("monster_id"))
	## Direct apply — mob kills must not award player score via the director.
	## Pass self so the victim promotes this body as forced pursuit prey.
	target.call("apply_damage_scaled", source, damage_mult(), attacker_label, _unit)


func _hostile_monster_near(near: Vector3, radius_m: float) -> CharacterBody3D:
	var city: Node = _unit.call("city") as Node
	if city == null or not city.has_method("find_nearest_hostile_monster"):
		return null
	var unit: CharacterBody3D = city.call(
		"find_nearest_hostile_monster", near, radius_m, _unit
	) as CharacterBody3D
	return unit


func _player_near(hit_point: Vector3, radius_m: float) -> bool:
	var city: Node = _unit.call("city") as Node
	if city == null or not bool(city.call("is_player_alive")):
		return false
	var ppos: Vector3 = city.call("get_player_target_position") as Vector3
	return hit_point.distance_squared_to(ppos) <= radius_m * radius_m


## Impact splash must not reach the player through a solid wall / arena shell.
func _player_near_los(hit_point: Vector3, radius_m: float) -> bool:
	if not _player_near(hit_point, radius_m):
		return false
	var city: Node = _unit.call("city") as Node
	if city == null or not city.has_method("has_voxel_line_of_sight"):
		return false
	var ppos: Vector3 = city.call("get_player_target_position") as Vector3
	return bool(city.call("has_voxel_line_of_sight", hit_point, ppos))


## Every `_execute_*` path routes here, so the shared recovery starts with the per-attack one
## and no execute site can forget it. A blaster burst already in flight is not cut short —
## remaining bolts run off `_blaster_burst_left`, not attack selection.
func _set_cooldown(attack_id: String) -> void:
	_cooldown[attack_id] = CombatTableScript.monster_attack_cooldown_s(attack_id)
	_global_cooldown = GLOBAL_COOLDOWN_S


func _is_player_prey(prey: Vector3) -> bool:
	if not _hostile_to_player():
		return false
	var city: Node = _unit.call("city") as Node
	if city == null or not bool(city.call("is_player_alive")):
		return false
	var ppos: Vector3 = city.call("get_player_target_position") as Vector3
	return _flat_distance(prey, ppos) <= 1.6


## Same rule as hunting: a body only hurts the player when their factions differ.
func _hostile_to_player() -> bool:
	var city: Node = _unit.call("city") as Node
	if city == null or not city.has_method("player_faction"):
		return true
	var mine: int = int(_unit.call("faction"))
	var theirs: int = int(city.call("player_faction"))
	return MonsterFactionScript.is_hostile(mine, theirs)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
