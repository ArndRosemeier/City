## Neutral owner of living catalogue monsters: spawn, track, aim / damage queries, despawn.
## Scenario directors (undead invasion, arena) sit on top — they do not own the unit list.
class_name MonsterRoster
extends Node3D

const CreatureCatalogScript := preload("res://scripts/city/creature_catalog.gd")

## Soft cap shared by every summon path (N-key, arena, invasion waves).
const MAX_ALIVE_UNITS := 40
## CityRoot's terrain child — NavMotor near-tier needs the live VoxelTerrain node.
const TERRAIN_NODE_NAME := "VoxelTerrain"
## Units stamped by UndeadInvasionDirector (waves / orb converts). Arena uses ArenaCombat.
const META_INVASION := &"invasion_owned"

var _city: CityRoot
var _terrain: VoxelTerrain
var _lod: NavLod
var _units: Array[UndeadUnit] = []
var _next_id: int = 0


func setup(city: CityRoot, terrain: VoxelTerrain = null, lod: NavLod = null) -> void:
	_city = city
	if terrain != null:
		_terrain = terrain
	else:
		_terrain = city.get_node_or_null(TERRAIN_NODE_NAME) as VoxelTerrain
	if _terrain == null:
		push_error(
			"MonsterRoster: CityRoot has no %s child, monsters cannot collide with voxels"
			% TERRAIN_NODE_NAME
		)
	_lod = (
		lod
		if lod != null
		else NavLod.for_collision_view(NavLod.COLLISION_VIEW_VOX_DEFAULT, CityRoot.VOXEL_SIZE)
	)


func get_alive_units() -> Array[UndeadUnit]:
	_prune_units()
	var out: Array[UndeadUnit] = []
	for u in _units:
		if not _unit_usable(u):
			continue
		if u.is_alive():
			out.append(u)
	return out


func is_registered(unit: UndeadUnit) -> bool:
	return unit != null and _units.has(unit)


func tracked_count() -> int:
	return _units.size()


func count_alive() -> int:
	var n := 0
	for u in _units:
		if _unit_usable(u) and u.is_alive():
			n += 1
	return n


func count_role(want_role: UndeadUnit.Role) -> int:
	var n := 0
	for u in _units:
		if not _unit_usable(u) or not u.is_alive() or u.is_giant():
			continue
		if u.role == want_role:
			n += 1
	return n


## Debug / N-key / Arena: named catalogue body. `for_invasion` stamps wipe ownership for waves.
## `invasion` is an UndeadInvasionDirector when the body belongs to that scenario (typed Node
## to avoid a class_name cycle with the director / CityRoot).
func spawn_by_id(
	body_id: String,
	world_pos: Vector3,
	body_seed: int = -1,
	for_invasion: bool = false,
	invasion: Node = null
) -> UndeadUnit:
	if body_id.is_empty():
		push_error("MonsterRoster.spawn_by_id: empty body id")
		assert(false, "MonsterRoster: empty body id")
		return null
	var entry: CreatureCatalog.Entry = CreatureCatalogScript.by_id(body_id)
	if entry == null:
		return null
	if not entry.is_spawnable():
		push_error(
			"MonsterRoster.spawn_by_id: '%s' is not spawnable (%s)" % [body_id, entry.note]
		)
		assert(false, "MonsterRoster: body not spawnable")
		return null
	_prune_units()
	if count_alive() >= MAX_ALIVE_UNITS:
		push_error("MonsterRoster.spawn_by_id: alive cap %d reached" % MAX_ALIVE_UNITS)
		return null
	return spawn_role(
		role_for_entry(entry), world_pos, body_seed, body_id, for_invasion, invasion
	)


func spawn_role(
	spawn_role: UndeadUnit.Role,
	world_pos: Vector3,
	body_seed: int = -1,
	body_id: String = "",
	for_invasion: bool = false,
	invasion: Node = null
) -> UndeadUnit:
	if not NavService.instance().is_configured():
		push_warning("MonsterRoster: no monster spawned, the nav world is not built yet")
		return null
	var unit := UndeadUnit.new()
	unit.name = "Monster_%d" % _next_id
	_next_id += 1
	add_child(unit)
	unit.setup(
		spawn_role,
		self,
		_city,
		world_pos,
		_terrain,
		_lod,
		body_seed if body_seed >= 0 else randi(),
		body_id,
		invasion
	)
	unit.died.connect(_on_unit_died)
	unit.tree_exiting.connect(_on_unit_tree_exiting.bind(unit))
	_units.append(unit)
	if for_invasion:
		tag_invasion(unit)
	return unit


static func role_for_entry(entry: CreatureCatalog.Entry) -> UndeadUnit.Role:
	if entry.has_slot(CreatureCatalogScript.Slot.CASTER):
		return UndeadUnit.Role.MAGE
	if entry.has_slot(CreatureCatalogScript.Slot.FODDER):
		return UndeadUnit.Role.MINION
	if entry.has_slot(CreatureCatalogScript.Slot.BRUTE):
		return UndeadUnit.Role.MINION
	push_error("MonsterRoster: '%s' has no role slot" % entry.id)
	assert(false, "MonsterRoster: no role for body")
	return UndeadUnit.Role.MINION


static func tag_invasion(unit: Node) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	unit.set_meta(META_INVASION, true)


static func is_invasion_owned(unit: Node) -> bool:
	return (
		unit != null
		and is_instance_valid(unit)
		and unit.has_meta(META_INVASION)
		and bool(unit.get_meta(META_INVASION))
	)


func query_segment_hit(from: Vector3, to: Vector3) -> Dictionary:
	_prune_units()
	var best_dist := INF
	var best: Dictionary = {}
	var seg := to - from
	var seg_len := seg.length()
	if seg_len < 0.05:
		return best
	var dir := seg / seg_len
	for u in _units:
		if not _unit_usable(u) or not u.is_alive():
			continue
		var r := u.hit_radius()
		var hh := u.hit_half_height()
		var center := u.global_position + Vector3(0.0, hh * 0.85, 0.0)
		var hit := CrowdDirector._segment_hits_capsule(from, dir, seg_len, center, r, hh)
		if hit.is_empty():
			continue
		var dist: float = float(hit["distance"])
		if dist >= best_dist:
			continue
		best_dist = dist
		best = {
			"distance": dist,
			"point": hit["point"],
			"unit": u,
		}
	return best


func damage_unit(unit: UndeadUnit, source: DamageSource.Id) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	if not unit.is_alive():
		return false
	_award(unit.apply_damage(source))
	return true


func damage_units_in_sphere(center: Vector3, radius: float, source: DamageSource.Id) -> int:
	_prune_units()
	var hit := 0
	var caught: Array[UndeadUnit] = _units.duplicate()
	for u in caught:
		if not _unit_usable(u) or not u.is_alive():
			continue
		var chest := u.global_position + Vector3(0.0, u.hit_half_height() * 0.85, 0.0)
		if chest.distance_to(center) > radius + u.hit_radius():
			continue
		_award(u.apply_damage(source))
		hit += 1
	return hit


func unregister_unit(unit: UndeadUnit) -> void:
	if unit == null:
		push_error("MonsterRoster.unregister_unit: null unit")
		assert(false, "MonsterRoster: unregister null")
		return
	var idx := _units.find(unit)
	if idx < 0:
		push_error(
			"MonsterRoster.unregister_unit: '%s' was not registered (double-remove?)"
			% unit.name
		)
		assert(false, "MonsterRoster: double unregister")
		return
	_units.remove_at(idx)


func despawn_unit(unit: UndeadUnit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if _units.has(unit):
		unregister_unit(unit)
	unit.queue_free()


## Drop every living body (city regenerate).
func clear_all() -> void:
	var doomed: Array[UndeadUnit] = _units.duplicate()
	_units.clear()
	for u in doomed:
		if u != null and is_instance_valid(u):
			u.queue_free()
	for c in get_children():
		if str(c.name).begins_with("UndeadOrb"):
			c.queue_free()


## Drop only invasion-tagged bodies (toggle invasion off). Arena / N-key summons stay.
func clear_invasion_units() -> void:
	var doomed: Array[UndeadUnit] = []
	for u in _units:
		if _unit_usable(u) and is_invasion_owned(u):
			doomed.append(u)
	for u in doomed:
		despawn_unit(u)
	for c in get_children():
		if str(c.name).begins_with("UndeadOrb"):
			c.queue_free()


func _award(score: int) -> void:
	if _city != null and score != 0:
		_city.adjust_player_score(score)


func _on_unit_died(unit: UndeadUnit, _was_giant: bool) -> void:
	unregister_unit(unit)


func _on_unit_tree_exiting(unit: UndeadUnit) -> void:
	if unit == null or not _units.has(unit):
		return
	push_error(
		"MonsterRoster: '%s' exited the tree while still registered — forcing unregister"
		% unit.name
	)
	unregister_unit(unit)


func _unit_usable(u: UndeadUnit) -> bool:
	return u != null and is_instance_valid(u)


func _prune_units() -> void:
	var kept: Array[UndeadUnit] = []
	var dropped := 0
	for u in _units:
		if _unit_usable(u):
			kept.append(u)
		else:
			dropped += 1
	if dropped > 0:
		push_error(
			"MonsterRoster._prune_units: dropped %d freed ref(s) — unregister-on-death missed"
			% dropped
		)
	_units = kept
