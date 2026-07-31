## Per-body combat kit: resolved CombatTable stats, attack cooldowns, and execution.
##
## Owned by `UndeadUnit`. Keeps the unit's Role/State machine for navigation and grow/nibble/
## scrape, while attack choice and player-facing damage come from the shared combat tables.
##
## Typed loosely on purpose: this script and `undead_unit.gd` preload each other, so naming
## `UndeadUnit` / `CombatTable.EffectiveStats` here breaks class_name resolution at parse time.
class_name MonsterCombat
extends RefCounted

const CombatTableScript := preload("res://scripts/city/combat_table.gd")
const DamageSourceScript := preload("res://scripts/city/damage_source.gd")
const EyeLaserScript := preload("res://scripts/city/eye_laser_vfx.gd")
const BlasterBoltScript := preload("res://scripts/city/blaster_bolt_vfx.gd")

## Projectiles and area strikes that use preferred / monster range.
const RANGED_KINDS: PackedStringArray = [
	"eye_laser", "blaster", "orb_convert", "charged_blast", "stomp"
]

## UndeadUnit that owns this kit.
var _unit: CharacterBody3D = null
## CombatTable.EffectiveStats
var _stats: RefCounted = null
## attack_id → seconds until ready
var _cooldown: Dictionary = {}
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


func speed_mult() -> float:
	return float(_stats.get("speed_mult")) if _stats != null else 1.0


func aggro_range_m() -> float:
	return float(_stats.get("aggro_range_m")) if _stats != null else 0.0


func leash_m() -> float:
	return float(_stats.get("leash_m")) if _stats != null else 0.0


func preferred_range_m() -> float:
	return float(_stats.get("preferred_range_m")) if _stats != null else 0.0


func prey_weight(key: String) -> float:
	if _stats == null:
		return 0.0
	var weights: Dictionary = _stats.get("prey_weights") as Dictionary
	return float(weights.get(key, 0.0))


func has_living_prey() -> bool:
	return prey_weight("player") > 0.0 or prey_weight("ped") > 0.0 or prey_weight("monsters") > 0.0


func has_building_prey() -> bool:
	return prey_weight("building") > 0.0


func has_attack(attack_id: String) -> bool:
	if _stats == null:
		return false
	var attacks: PackedStringArray = _stats.get("attacks") as PackedStringArray
	for a: String in attacks:
		if a == attack_id:
			return true
	return false


func is_attack_ready(attack_id: String) -> bool:
	if not has_attack(attack_id):
		return false
	return float(_cooldown.get(attack_id, 0.0)) <= 0.0


## Stand-off the navigator aims for while hunting living prey.
func hunt_standoff_m() -> float:
	if _stats == null:
		return 2.0
	## Orb casters hold convert range when the orb is ready (legacy mage cadence).
	if has_attack("orb_convert") and is_attack_ready("orb_convert"):
		return CombatTableScript.monster_attack_range_m("orb_convert") * 0.92
	var ranged := _ready_ranged_attack()
	if ranged != "" and ranged != "orb_convert":
		return maxf(preferred_range_m(), 1.5)
	if has_attack("melee"):
		return CombatTableScript.monster_attack_range_m("melee") * 0.85
	return maxf(preferred_range_m(), 1.5)


func tick(delta: float) -> void:
	if _stats == null or _unit == null or not bool(_unit.call("is_alive")):
		return
	for attack_id: String in _cooldown.keys():
		_cooldown[attack_id] = maxf(0.0, float(_cooldown[attack_id]) - delta)
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
	var dist := _flat_distance(_unit.global_position, prey)
	var attack_id := _pick_attack(dist)
	if attack_id.is_empty():
		return false
	## Ranged kits need a clear voxel corridor — same filter as prey selection.
	if _is_ranged_attack(attack_id) and not _has_voxel_los_to(prey):
		return false
	return _begin_attack(attack_id, prey)


func _pick_attack(dist_m: float) -> String:
	var attacks: PackedStringArray = _stats.get("attacks") as PackedStringArray
	var best := ""
	var best_score := -1.0
	for attack_id: String in attacks:
		if float(_cooldown.get(attack_id, 0.0)) > 0.0:
			continue
		if attack_id == "nibble" or attack_id == "debris":
			## Building work stays on the role states (NIBBLE / SCRAPE).
			continue
		var reach := CombatTableScript.monster_attack_range_m(attack_id)
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
		return true
	return _execute_attack(attack_id, prey)


func _finish_windup() -> void:
	var attack_id := _windup_attack
	var prey := _windup_prey
	_windup_attack = ""
	_windup_prey = Vector3.INF
	if attack_id.is_empty() or prey == Vector3.INF:
		return
	## Re-check range after the telegraph — prey may have walked out.
	var reach := CombatTableScript.monster_attack_range_m(attack_id)
	if _flat_distance(_unit.global_position, prey) > reach * 1.15:
		return
	## Voxel LOS can close during windup (door, corner, glass lip).
	if _is_ranged_attack(attack_id) and not _has_voxel_los_to(prey):
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
	if _is_player_prey(prey):
		_hurt_player(DamageSourceScript.Id.MONSTER_MELEE)
		return true
	var mob := _hostile_monster_near(prey, CombatTableScript.monster_attack_range_m("melee"))
	if mob != null:
		_hurt_monster(mob, "melee")
		return true
	## Pedestrian: one-shot remove when weighted; buildings are not melee prey.
	_unit.call(
		"try_remove_ped_at", prey, CombatTableScript.monster_attack_range_m("melee")
	)
	return true


func _execute_orb(prey: Vector3) -> bool:
	_unit.call("play_combat_strike", "orb_convert")
	_set_cooldown("orb_convert")
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
	return true


func _on_eye_laser_impact(hit_point: Vector3, _direction: Vector3) -> void:
	if _unit == null or not bool(_unit.call("is_alive")):
		return
	if _player_near(hit_point, 2.8):
		_hurt_player(DamageSourceScript.Id.MONSTER_LASER)
		return
	var mob := _hostile_monster_near(hit_point, 2.8)
	if mob != null:
		_hurt_monster(mob, "eye_laser")


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


func _on_blaster_impact(hit_point: Vector3, _direction: Vector3, _shot_origin: Vector3) -> void:
	if _unit == null or not bool(_unit.call("is_alive")):
		return
	if _player_near(hit_point, 2.8):
		_hurt_player(DamageSourceScript.Id.MONSTER_BLASTER)
		return
	var mob := _hostile_monster_near(hit_point, 2.8)
	if mob != null:
		_hurt_monster(mob, "blaster")


func _execute_stomp(prey: Vector3) -> bool:
	_unit.call("play_combat_strike", "stomp")
	_set_cooldown("stomp")
	var row := CombatTableScript.attack_def("stomp")
	var scale: float = float(_unit.get("character_scale"))
	var radius := float(row.get("radius_m", 2.52)) * maxf(scale, 0.05)
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
	## Vertical slice: telegraphed hit on the player / hostile if still near the aim point.
	if _is_player_prey(prey):
		var city: Node = _unit.call("city") as Node
		if city != null and bool(city.call("is_player_alive")):
			var ppos: Vector3 = city.call("get_player_target_position") as Vector3
			if prey.distance_to(ppos) <= radius + 1.2:
				_hurt_player(DamageSourceScript.Id.MONSTER_BLAST)
	var mob := _hostile_monster_near(prey, radius + 1.2)
	if mob != null and prey.distance_to(mob.global_position) <= radius + 1.2:
		_hurt_monster(mob, "charged_blast")
	return true


func _hurt_player(source: DamageSource.Id) -> void:
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


func _set_cooldown(attack_id: String) -> void:
	_cooldown[attack_id] = CombatTableScript.monster_attack_cooldown_s(attack_id)


func _is_player_prey(prey: Vector3) -> bool:
	var city: Node = _unit.call("city") as Node
	if city == null or not bool(city.call("is_player_alive")):
		return false
	var ppos: Vector3 = city.call("get_player_target_position") as Vector3
	return _flat_distance(prey, ppos) <= 1.6


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
