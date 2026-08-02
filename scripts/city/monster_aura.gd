## Passive-driven passive auras on a monster body. Owned by `UndeadUnit`.
##
## Authored in gamedata.json `auras` + body/template `auras` lists; resolved onto
## `CombatTable.EffectiveStats.auras`. Unknown ids fail loud at bind time.
class_name MonsterAura
extends RefCounted

const CombatTableScript := preload("res://scripts/city/combat_table.gd")

## Below this ground speed the body counts as standing rather than striding (0.2 m/s).
const MIN_STRIDE_SPEED_SQ := 0.04

## Auras that carve fabric as the body advances. The navigator has to be willing to route
## these bodies into walls (NavProfile.monster_breaker) or the stride never happens.
const TERRAIN_CHEWING_AURAS: PackedStringArray = ["crumble_stride"]

## UndeadUnit that owns these auras.
var _unit: CharacterBody3D = null
var _aura_ids: PackedStringArray = PackedStringArray()
## aura_id → seconds until next tick
var _cooldown: Dictionary = {}


func bind(unit: CharacterBody3D, stats: RefCounted) -> void:
	if unit == null:
		push_error("MonsterAura.bind: no unit")
		assert(false, "MonsterAura: no unit")
		return
	if stats == null:
		push_error("MonsterAura.bind: no stats")
		assert(false, "MonsterAura: no stats")
		return
	_unit = unit
	_aura_ids = PackedStringArray()
	_cooldown.clear()
	var raw: Variant = stats.get("auras")
	if raw == null:
		return
	var listed: PackedStringArray = raw as PackedStringArray
	for aura_id: String in listed:
		## Loud resolve — unknown ids must fail at spawn, not on the first stride.
		var _row: Dictionary = CombatTableScript.aura_def(aura_id)
		_aura_ids.append(aura_id)
		_cooldown[aura_id] = 0.0


## True when this body eats its way through terrain, so it needs a breaking nav profile and
## closes to contact instead of holding artillery range.
func chews_terrain() -> bool:
	for aura_id: String in TERRAIN_CHEWING_AURAS:
		if _aura_ids.has(aura_id):
			return true
	return false


func tick(delta: float) -> void:
	if _unit == null or _aura_ids.is_empty():
		return
	if not is_instance_valid(_unit):
		return
	for aura_id: String in _aura_ids:
		var left := float(_cooldown.get(aura_id, 0.0))
		left = maxf(0.0, left - delta)
		_cooldown[aura_id] = left
		if left > 0.0:
			continue
		if aura_id == "crumble_stride":
			_tick_crumble_stride(aura_id)
		else:
			push_error("MonsterAura.tick: no runtime for aura '%s'" % aura_id)
			assert(false, "MonsterAura: unimplemented aura")


func _tick_crumble_stride(aura_id: String) -> void:
	var row := CombatTableScript.aura_def(aura_id)
	var tick_s := float(row.get("tick_s", 0.22))
	_cooldown[aura_id] = maxf(tick_s, 0.05)
	var along := _stride_direction()
	if along == Vector3.ZERO:
		return
	var city: Node = _unit.call("city") as Node
	if city == null or not city.has_method("undead_crumble_stride_at"):
		push_error("MonsterAura: CityRoot missing undead_crumble_stride_at")
		assert(false, "MonsterAura: no crumble API")
		return
	var reach := float(row.get("reach_m", 1.8))
	var along_half := int(row.get("along_half", 1))
	var depth_vox := int(row.get("depth_vox", 2))
	var contact: Vector3 = _unit.global_position + along * reach
	city.call("undead_crumble_stride_at", contact, along, along_half, depth_vox)


## Which way the body is chewing, or ZERO when it should not chew at all.
##
## Walking wins. A body pinned against fabric still chews toward prey it has not reached: the
## navigator only routes through a wall the body has already opened, so waiting for a stride
## that can never start left the cage boss standing in its cave. Once it is at its fighting
## distance it holds — standing still on the spot must not grind the world away.
func _stride_direction() -> Vector3:
	var vel: Vector3 = _unit.velocity
	vel.y = 0.0
	if vel.length_squared() >= MIN_STRIDE_SPEED_SQ:
		return vel.normalized()
	var prey: Vector3 = _unit.call("combat_prey") as Vector3
	if prey == Vector3.INF:
		return Vector3.ZERO
	var combat: RefCounted = _unit.call("combat") as RefCounted
	if combat == null:
		return Vector3.ZERO
	var toward := prey - _unit.global_position
	toward.y = 0.0
	if toward.length() <= maxf(float(combat.call("hunt_standoff_m")), 0.5):
		return Vector3.ZERO
	return toward.normalized()
