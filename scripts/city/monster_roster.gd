## Neutral owner of living catalogue monsters: spawn, track, aim / damage queries, despawn.
## Scenario directors (undead invasion, arena) sit on top — they do not own the unit list.
class_name MonsterRoster
extends Node3D

const CreatureCatalogScript := preload("res://scripts/city/creature_catalog.gd")
const CombatTableScript := preload("res://scripts/city/combat_table.gd")
const MonsterFactionScript := preload("res://scripts/city/monster_faction.gd")

## Soft cap on *walking* units, shared by every summon path (N-key, arena, invasion, siege, zoo).
## A frame-rate safety net rather than a balance number: districts pace themselves with their own
## alive targets, and this only exists so several of them at once cannot bury the frame. Siege
## towers do not count against it — see `count_alive_walkers`.
const MAX_ALIVE_UNITS := 80
## Absolute ceiling including immobile bodies, which is what siege towers are gated on. A quarter
## offers a couple of hundred build sites, so without this the pot is the only limit on how many
## combat hosts a run can stand up.
const MAX_ALIVE_TOTAL := 220
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
	if terrain != null and is_instance_valid(terrain):
		_terrain = terrain
	elif city != null:
		## Prefer the authoritative field. Child-name lookup is a fallback only — after a
		## load/regenerate the replacement terrain may briefly not be named VoxelTerrain.
		_terrain = city.voxel_terrain()
		if _terrain == null or not is_instance_valid(_terrain):
			_terrain = city.get_node_or_null(TERRAIN_NODE_NAME) as VoxelTerrain
	if _terrain == null or not is_instance_valid(_terrain):
		push_error(
			"MonsterRoster: CityRoot has no live VoxelTerrain, monsters cannot collide with voxels"
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


## Living units that actually walk. Siege towers are excluded: they are meshless, immobile and
## nav-free, so they cost a fraction of a walker — and counting them against the walker ceiling
## would let a well-funded defence starve the horde it was built to fight.
func count_alive_walkers() -> int:
	var n := 0
	for u in _units:
		if _unit_usable(u) and u.is_alive() and not u.is_siege_tower():
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
## Meshless Siege Quarter tower. Registers like any other unit so splash / LOS / combat
## find it, but skips CreatureCatalog (the voxel stamp is the body).
func spawn_siege_tower(
	combat_id: String,
	world_pos: Vector3,
	authored_hp: float,
	muzzle_height_m: float,
	structure_hit_radius_m: float,
	body_seed: int = -1
) -> UndeadUnit:
	return _spawn_structure(
		combat_id,
		world_pos,
		authored_hp,
		muzzle_height_m,
		structure_hit_radius_m,
		int(MonsterFactionScript.Id.SIEGE_DEFENDER),
		false,
		body_seed
	)


## Hostile summoning spire (crypt / castle dungeon). Same meshless structure as a siege pad,
## but it stands for `faction_id` — the side its station summons for — so the player may shoot
## it and the horde it feeds will not.
func spawn_faction_tower(
	combat_id: String,
	world_pos: Vector3,
	authored_hp: float,
	muzzle_height_m: float,
	structure_hit_radius_m: float,
	faction_id: int,
	body_seed: int = -1
) -> UndeadUnit:
	return _spawn_structure(
		combat_id,
		world_pos,
		authored_hp,
		muzzle_height_m,
		structure_hit_radius_m,
		faction_id,
		true,
		body_seed
	)


func _spawn_structure(
	combat_id: String,
	world_pos: Vector3,
	authored_hp: float,
	muzzle_height_m: float,
	structure_hit_radius_m: float,
	faction_id: int,
	spawn_tower: bool,
	body_seed: int
) -> UndeadUnit:
	if combat_id.is_empty():
		push_error("MonsterRoster._spawn_structure: empty combat id")
		assert(false, "MonsterRoster: empty tower combat id")
		return null
	if not CombatTableScript.has_monster(combat_id):
		push_error("MonsterRoster._spawn_structure: unknown combat id '%s'" % combat_id)
		assert(false, "MonsterRoster: unknown tower combat id")
		return null
	_prune_units()
	if count_alive() >= MAX_ALIVE_TOTAL:
		## Soft cap: a pot big enough to plate the whole quarter is expected pressure, not a fault.
		return null
	var unit := UndeadUnit.new()
	unit.name = "%s_%d" % ["SpawnTower" if spawn_tower else "SiegeTower", _next_id]
	_next_id += 1
	add_child(unit)
	unit.setup_siege_tower(
		self,
		_city,
		world_pos,
		_terrain,
		_lod,
		combat_id,
		authored_hp,
		muzzle_height_m,
		structure_hit_radius_m,
		body_seed if body_seed >= 0 else randi(),
		faction_id,
		spawn_tower
	)
	unit.died.connect(_on_unit_died)
	unit.tree_exiting.connect(_on_unit_tree_exiting.bind(unit))
	_units.append(unit)
	return unit


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
	if count_alive_walkers() >= MAX_ALIVE_UNITS:
		## Soft cap: callers that care (Zoo, Siege) hold and retry; N-key just fails quietly.
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
	unit.apply_damage(source)
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
		u.apply_damage(source)
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
