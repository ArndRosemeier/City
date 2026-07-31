## One undead soldier: Mage (convert), Minion (melee fodder), or Giant (grown + stomp).
##
## Toughness is not a property of the role: it comes off whichever body the catalogue handed
## this unit, through `creature_health.gd`, so a two-metre skeleton and a four-metre monster
## wearing the same behaviour take a different number of hits. `kill_from_player` is unchanged
## and is now what happens when the last of that runs out rather than what happens on contact.
##
## Movement is NavAgent + NavMotor over the baked span field. An UndeadGoalProvider says what
## this body wants and the six-rung ladder says what happens when it cannot get there, so
## there is deliberately no local unstick code here: TRAPPED is the only escape hatch, and it
## is counted, warned about and emitted rather than quietly relocating the body.
class_name UndeadUnit
extends CharacterBody3D

enum Role { MAGE, MINION, GIANT }
enum State { IDLE, SEEK_PED, CAST, NIBBLE, SEEK_PAD, GROWING, STOMP, SCRAPE, DEAD }

const OrbScript := preload("res://scripts/city/undead_orb_projectile.gd")
const CombatTableScript := preload("res://scripts/city/combat_table.gd")
const CreatureCatalogScript := preload("res://scripts/city/creature_catalog.gd")
const CreatureClipsScript := preload("res://scripts/city/creature_clips.gd")
const CreatureHealthScript := preload("res://scripts/city/creature_health.gd")
const CreatureVariationScript := preload("res://scripts/city/creature_variation.gd")
const DamageSourceScript := preload("res://scripts/city/damage_source.gd")
const MonsterCombatScript := preload("res://scripts/city/monster_combat.gd")
const MonsterFactionScript := preload("res://scripts/city/monster_faction.gd")
const MonsterHealthBarScript := preload("res://scripts/city/monster_health_bar.gd")

## PackedScenes stay referenced so a second summon of the same body is a cache hit, matching
## the ped/car warm-up pattern. First load of each path is still sync on the summon thread.
static var _scene_cache: Dictionary = {}  ## String path -> PackedScene

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
## Longest a body holds its flinch before locomotion may have the rig back. The clip's own
## length wins under this — the KayKit flinch is a third of a second and the Blob one shorter —
## and the cap is here so a family that ships a two-second stagger cannot stop a body walking.
const HIT_REACT_MAX_HOLD_SEC := 0.6
## Collision stays walkable — full 10× body scale on the capsule embeds in buildings.
const COL_RADIUS_MAX_M := 1.25
const COL_HEIGHT_MAX_M := 3.4
## Capsule and hit volume for a body the size of CreatureCatalog.REFERENCE_HEIGHT. Every
## other body multiplies these by its own height ratio and its rolled build, so a monster
## that is drawn half a metre wider is also hit half a metre wider.
const COL_RADIUS_BASE_M := 0.28
const COL_HEIGHT_BASE_M := 1.15
const HIT_RADIUS_BASE_M := 0.55
const HIT_HALF_HEIGHT_BASE_M := 0.95
const MUZZLE_BASE_M := 1.35
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
var _roster: MonsterRoster
## Optional UndeadInvasionDirector (giant pad / orb convert). Null for arena / free summons.
## Typed Node to avoid a class_name parse cycle with the director.
var _invasion: Node
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
## Which body this unit wears, and the roll that made it look like nobody else.
var _entry: CreatureCatalog.Entry = null
var _variation: CreatureVariation = null
var _seed: int = 0
## Catalogue entry asked for by name, empty when the seed chooses.
var _body_id: String = ""
var _nibble_cd: float = 0.0
## Points of punishment left, and how many this body started with. Both come from the
## catalogue's measurement of it, so a bigger monster is a tougher one without a table of
## fifty-four hand-written numbers.
var _health: float = 0.0
var _health_max: float = 0.0
## The strip under the feet. Null before `setup` builds one and again once death frees it.
var _health_bar: MonsterHealthBar = null
## How far the drawn body reaches from its own axis, in the units it was authored in. Measured
## once off the meshes; only the health bar needs it, and only to be pulled clear of them.
var _model_reach: float = 0.0
## Seconds the flinch still owns the rig.
var _hit_react_left: float = 0.0
## The orb is away; hold CAST one more frame so the spellcast clip is not stomped by the
## walking states' idle.
var _cast_fired: bool = false
## The building voxel the body is chewing or peeling. Vector3.INF while it has none.
var _facade_target: Vector3 = Vector3.INF
## Resolved combat kit (MonsterCombat). Null only before setup finishes.
var _combat: RefCounted = null
## MonsterFaction.Id for this body. Set once the catalogue entry is known.
var _faction: int = -1
## Cached living-prey aim for the combat tick (refreshed with the goal provider).
var _combat_prey: Vector3 = Vector3.INF


## `p_seed` decides which body out of the catalogue this unit wears and every procedural
## variation on top of it, so the same seed is the same monster everywhere. `p_body_id` names
## a catalogue entry instead of rolling for one, for tools and tests that are about a
## particular creature rather than about the roster.
func setup(
	p_role: Role,
	roster: MonsterRoster,
	city: CityRoot,
	world_pos: Vector3,
	terrain: VoxelTerrain,
	lod: NavLod,
	p_seed: int,
	p_body_id: String = "",
	invasion: Node = null
) -> void:
	role = p_role
	_body_id = p_body_id
	_roster = roster
	_invasion = invasion
	_city = city
	_terrain = terrain
	_lod = lod
	_seed = p_seed
	global_position = world_pos
	character_scale = 1.0
	_alive = true
	collision_layer = 2
	collision_mask = 1
	CityProfiler.begin("undead_setup")
	_build_body()
	_load_model()
	_bind_combat()
	_reset_health()
	_apply_scale()
	_build_health_bar()
	if role == Role.MINION:
		## Stagger nibbles so a pack doesn't all bite on the same frame.
		_nibble_cd = randf_range(0.0, MINION_NIBBLE_INTERVAL_SEC)
	state = State.STOMP if role == Role.GIANT else State.SEEK_PED
	_build_nav()
	_play_action(CreatureClips.Action.IDLE)
	CityProfiler.end("undead_setup")


func is_alive() -> bool:
	return _alive


func is_mage() -> bool:
	return role == Role.MAGE


func is_giant() -> bool:
	return role == Role.GIANT or character_scale >= GIANT_SCALE_TARGET * 0.95


func can_cast() -> bool:
	## Prefer the combat-table orb cooldown when this body has orb_convert.
	if _combat != null and bool(_combat.call("has_attack", "orb_convert")):
		return bool(_combat.call("is_attack_ready", "orb_convert"))
	return _cast_cd <= 0.0


## The body this unit is wearing, so a tool or a test can name it. Null before `setup`.
func creature_entry() -> CreatureCatalog.Entry:
	return _entry


func creature_variation() -> CreatureVariation:
	return _variation


func combat() -> RefCounted:
	return _combat


## MonsterFaction.Id for this body. Loud when called before setup finishes.
func faction() -> int:
	if _faction < 0:
		push_error("UndeadUnit %s: faction read before body bind" % name)
		assert(false, "UndeadUnit: no faction")
		return int(MonsterFactionScript.Id.UNDEAD)
	return _faction


## True when this unit may hunt / hurt `other` (different faction).
func is_hostile_to(other: UndeadUnit) -> bool:
	if other == null or not is_instance_valid(other):
		return false
	return MonsterFactionScript.is_hostile(_faction, other.faction())


func city() -> CityRoot:
	return _city


func muzzle_world() -> Vector3:
	return global_position + Vector3(0.0, MUZZLE_BASE_M * _span_tall() * character_scale, 0.0)


## Resolved effective stats (CombatTable.EffectiveStats), or null before setup.
func combat_stats() -> RefCounted:
	if _combat == null:
		return null
	return _combat.call("stats") as RefCounted


func set_combat_prey(world: Vector3) -> void:
	_combat_prey = world


func combat_prey() -> Vector3:
	return _combat_prey


func face_combat_prey(world: Vector3) -> void:
	_look_at_flat(world)


func play_combat_windup(attack_id: String) -> void:
	if attack_id == "orb_convert" or attack_id == "eye_laser" or attack_id == "blaster" or attack_id == "charged_blast":
		_play_action(CreatureClips.Action.CAST)
	else:
		_play_action(CreatureClips.Action.MELEE)


func play_combat_strike(attack_id: String) -> void:
	if attack_id == "orb_convert" or attack_id == "eye_laser" or attack_id == "blaster" or attack_id == "charged_blast":
		_play_action(CreatureClips.Action.CAST)
	else:
		_play_action(CreatureClips.Action.MELEE)


func fire_convert_orb(toward: Vector3) -> void:
	_fire_orb(toward)


## Instantly remove a pedestrian at `prey` when that prey kind is weighted. No health pool.
func try_remove_ped_at(prey: Vector3, reach_m: float) -> bool:
	if _city == null:
		return false
	if _combat != null and float(_combat.call("prey_weight", "ped")) <= 0.0:
		return false
	## One-shot remove — peds have no health pool.
	var removed: Variant = _city.call("try_kill_ped_near", prey, reach_m)
	if typeof(removed) == TYPE_NIL:
		return false
	return true


## How much bigger the drawn body is than the one the hit volume was measured on, split into
## the model's own height and the build this unit rolled.
func _span_wide() -> float:
	if _entry == null:
		return 1.0
	return _entry.collider_span() * (1.0 if _variation == null else _variation.width)


func _span_tall() -> float:
	if _entry == null:
		return 1.0
	return _entry.collider_span() * (1.0 if _variation == null else _variation.height)


func hit_radius() -> float:
	return HIT_RADIUS_BASE_M * _span_wide() * character_scale


func hit_half_height() -> float:
	return HIT_HALF_HEIGHT_BASE_M * _span_tall() * character_scale


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


func goal_provider() -> UndeadGoalProvider:
	return _provider


func health() -> float:
	return _health


func health_max() -> float:
	return _health_max


func health_fraction() -> float:
	if _health_max <= 0.0:
		return 0.0
	return clampf(_health / _health_max, 0.0, 1.0)


## The strip drawn under this body, for tools and tests. Null once the body is dead.
func health_bar() -> MonsterHealthBar:
	return _health_bar


## One hit from `source`. Returns the score award when this hit was the fatal one and 0 when the
## body is still standing, which is exactly the contract `kill_from_player` had when every hit
## was fatal — so the caller's bookkeeping never had to learn about health.
##
## Incoming damage is divided by the body's resolved `armor_mult` (1.0 = catalogue tier as-is).
func apply_damage(source: DamageSource.Id) -> int:
	return apply_damage_scaled(source, 1.0)


## Same as `apply_damage`, with the attacker's resolved `damage_mult` applied to the table amount.
## `attacker_label` is who the damage log credits (player punches stay `"player"`).
## `attacker` is promoted to forced pursuit prey (overrides table weights / LOS acquire).
func apply_damage_scaled(
	source: DamageSource.Id,
	scale: float,
	attacker_label: String = "player",
	attacker: Node = null
) -> int:
	if not _alive:
		return 0
	if scale <= 0.0:
		push_error(
			"UndeadUnit %s: apply_damage_scaled got non-positive scale %f"
			% [name, scale]
		)
		assert(false, "UndeadUnit: bad damage scale")
		return 0
	if DamageSourceScript.target(source) != DamageSourceScript.Target.CREATURE:
		push_error(
			"UndeadUnit %s: %s hurts the player, not a creature"
			% [name, DamageSourceScript.source_name(source)]
		)
		return 0
	var armor := 1.0
	if _combat != null:
		armor = maxf(float(_combat.call("armor_mult")), 0.001)
	var before := _health
	var raw := DamageSourceScript.amount(source) * scale / armor
	_health -= raw
	var taken := minf(raw, before)
	var body_name: String = _entry.id if _entry != null else String(name)
	var tree := Engine.get_main_loop() as SceneTree
	var log_node: Node = null
	if tree != null:
		log_node = tree.root.get_node_or_null("DamageLog")
	if CreatureHealthScript.is_dead(_health):
		_health = 0.0
		if log_node != null and log_node.has_method("record"):
			log_node.call(
				"record", attacker_label, body_name, source, taken, 0.0, _health_max, true
			)
		return kill_from_player()
	if log_node != null and log_node.has_method("record"):
		log_node.call(
			"record", attacker_label, body_name, source, taken, _health, _health_max, false
		)
	_update_health_bar()
	_play_hit_reaction()
	_promote_attacker_after_hit(source, attacker)
	return 0


func _promote_attacker_after_hit(source: DamageSource.Id, attacker: Node) -> void:
	if _provider == null:
		return
	var who := attacker
	if who == null and DamageSourceScript.is_player_vs_creature(source):
		if _city != null and _city.has_method("get_player_node"):
			who = _city.call("get_player_node") as Node
	if who == null or not is_instance_valid(who) or who == self:
		return
	_provider.promote_attacker(who)


## Death itself, unchanged: navigation disposed, the death clip played, `died` emitted, the body
## freed 1.6 s later, and the score award returned. What changed is who calls it — the hit that
## empties the pool, rather than any hit at all.
func kill_from_player() -> int:
	if not _alive:
		return 0
	_alive = false
	state = State.DEAD
	velocity = Vector3.ZERO
	_dispose_nav()
	_drop_health_bar()
	_play_action(CreatureClips.Action.DEATH)
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
	_capsule.radius = COL_RADIUS_BASE_M
	_capsule.height = COL_HEIGHT_BASE_M
	_col_shape.shape = _capsule
	_col_shape.position = Vector3(0.0, 0.9, 0.0)
	add_child(_col_shape)


## Which kind of body this unit's behaviour asks the catalogue for. A giant keeps whatever it
## grew out of, so this only ever runs at spawn.
func _catalog_slot() -> CreatureCatalog.Slot:
	match role:
		Role.MAGE:
			return CreatureCatalog.Slot.CASTER
		Role.GIANT:
			return CreatureCatalog.Slot.BRUTE
		Role.MINION:
			return CreatureCatalog.Slot.FODDER
	push_error("UndeadUnit %s: no catalogue slot for role %d" % [name, int(role)])
	return CreatureCatalog.Slot.FODDER


## The loader contract every catalogue entry has to satisfy: the root casts to Node3D, the
## asset stands feet-on-floor over its own pivot and faces +Z, and exactly one
## AnimationPlayer is found depth-first. Nothing here carries root motion — NavMotor owns the
## body's position.
##
## A body that does not stand over its pivot gets its correction from the catalogue rather
## than from a rule here: `model_offset` and `model_yaw` are per-entry data, measured off the
## file by `tools/test_creature_assets.tscn` and zero for all but three of fifty-four.
func _load_model() -> void:
	if _body_id.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed
		_entry = CreatureCatalogScript.pick(_catalog_slot(), rng)
	else:
		_entry = CreatureCatalogScript.by_id(_body_id)
	if _entry == null:
		return
	CityProfiler.begin("undead_model_load")
	var packed := _cached_scene(_entry.path)
	CityProfiler.end("undead_model_load")
	if packed == null:
		push_error("UndeadUnit: %s did not load a scene from %s" % [_entry.id, _entry.path])
		return
	CityProfiler.begin("undead_model_setup")
	var inst: Node = packed.instantiate()
	_model = inst as Node3D
	if _model == null:
		push_error(
			"UndeadUnit: %s root is not Node3D (got %s)" % [_entry.id, inst.get_class()]
		)
		inst.queue_free()
		CityProfiler.end("undead_model_setup")
		return
	_model.name = "CreatureModel"
	add_child(_model)
	_model.rotation = Vector3(0.0, _entry.model_yaw, 0.0)
	_anim = _find_anim(_model)
	if _anim == null:
		push_error("UndeadUnit: no AnimationPlayer in %s" % _entry.id)
		CityProfiler.end("undead_model_setup")
		return
	_anim.active = true
	_anim_clips = _anim.get_animation_list()
	_variation = CreatureVariationScript.roll(_entry, _anim_clips, _seed)
	_attach_prop()
	_variation.apply(_model, _entry)
	_model_reach = MonsterHealthBarScript.body_reach(_model)
	_configure_locomotion_loops()
	_apply_far_visibility(_model)
	CityProfiler.end("undead_model_setup")


static func _cached_scene(path: String) -> PackedScene:
	if path.is_empty():
		return null
	if _scene_cache.has(path):
		return _scene_cache[path] as PackedScene
	if not ResourceLoader.has_cached(path):
		CityProfiler.note_event("undead_scene_first_load %s" % path.get_file())
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	_scene_cache[path] = packed
	return packed


## Hang the body's prop off the rig's hand slot. KayKit exposes `handslot.l` / `handslot.r`
## bones for exactly this, and the staff has been sitting unreferenced in the repo since the
## pack was vendored.
func _attach_prop() -> void:
	if _entry.prop_path.is_empty() or _entry.prop_bone.is_empty():
		return
	var skeleton := CreatureVariationScript.find_skeleton(_model)
	if skeleton == null:
		push_error("UndeadUnit: %s has no Skeleton3D to hang %s off" % [_entry.id, _entry.prop_path])
		return
	if skeleton.find_bone(_entry.prop_bone) < 0:
		push_error("UndeadUnit: %s has no bone '%s'" % [_entry.id, _entry.prop_bone])
		return
	var packed := _cached_scene(_entry.prop_path)
	if packed == null:
		push_error("UndeadUnit: prop %s did not load a scene" % _entry.prop_path)
		return
	var prop: Node3D = packed.instantiate() as Node3D
	if prop == null:
		push_error("UndeadUnit: prop %s is not a Node3D" % _entry.prop_path)
		return
	var mount := BoneAttachment3D.new()
	mount.name = "PropMount"
	skeleton.add_child(mount)
	mount.bone_name = _entry.prop_bone
	mount.add_child(prop)


## Clips imported as one-shots freeze mid-stride and the body keeps sliding, which reads as
## floating. Only the two cycles this unit will actually hold are looped: the attack and the
## death are one-shots on purpose.
func _configure_locomotion_loops() -> void:
	if _anim == null:
		return
	for action: CreatureClips.Action in [CreatureClips.Action.IDLE, CreatureClips.Action.LOCOMOTION]:
		var clip := _clip_for(action)
		if clip.is_empty():
			continue
		var anim := _anim.get_animation(clip)
		if anim == null:
			push_error("UndeadUnit: %s resolved %s to a clip it does not have" % [_entry.id, clip])
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


func _bind_combat() -> void:
	if _entry == null:
		push_error("UndeadUnit %s: cannot resolve combat without a catalogue body" % name)
		assert(false, "UndeadUnit: no body for combat")
		return
	_faction = int(MonsterFactionScript.for_body(_entry.id))
	var stats: RefCounted = CombatTableScript.resolve(_entry.id)
	if stats == null:
		push_error("UndeadUnit %s: CombatTable.resolve failed for '%s'" % [name, _entry.id])
		assert(false, "UndeadUnit: combat resolve failed")
		return
	_combat = MonsterCombatScript.new()
	_combat.call("bind", self, stats)


func _reset_health() -> void:
	var base := CreatureHealthScript.for_scale(_entry, character_scale)
	var mult := 1.0
	if _combat != null:
		mult = float(_combat.call("hp_mult"))
	_health_max = base * mult
	_health = _health_max


## Growing on a pad makes a body tougher as it happens rather than all at once when it finishes,
## and a monster halfway through a fight stays halfway through it — a giant that healed to full
## by growing would be a giant nobody could ever wear down.
func _update_health_for_scale() -> void:
	var base := CreatureHealthScript.for_scale(_entry, character_scale)
	var mult := 1.0
	if _combat != null:
		mult = float(_combat.call("hp_mult"))
	var next := base * mult
	if is_equal_approx(next, _health_max):
		return
	var kept := 1.0 if _health_max <= 0.0 else _health / _health_max
	_health_max = next
	_health = next * kept


func _apply_scale() -> void:
	_update_health_for_scale()
	## Visual only — never scale the CharacterBody3D (that blows up physics). The build is
	## non-uniform, so squat bodies really are squat rather than merely painted that way.
	if _model != null and is_instance_valid(_model):
		var w := 1.0 if _variation == null else _variation.width
		var h := 1.0 if _variation == null else _variation.height
		var build := Vector3(w, h, w) * character_scale
		_model.scale = build
		## The pivot correction is measured in the body's own units, so it grows with it.
		_model.position = _entry.model_offset * build
	_update_collision_for_scale()
	_update_health_bar()
	if _nav_motor != null:
		_nav_motor.speed_mps = _move_speed()


func _update_collision_for_scale() -> void:
	if _capsule == null or _col_shape == null:
		return
	## Grow with sqrt so giants stay street-capable; hard-clamp for 10×. The floor is this
	## body's own size rather than the reference skeleton's, so a three-metre monster never
	## collides as if it were a minion.
	var base_r := COL_RADIUS_BASE_M * _span_wide()
	var base_h := COL_HEIGHT_BASE_M * _span_tall()
	var r := clampf(base_r * sqrt(character_scale), base_r, COL_RADIUS_MAX_M)
	var h := clampf(base_h * sqrt(character_scale), base_h, COL_HEIGHT_MAX_M)
	_capsule.radius = r
	_capsule.height = maxf(h, r * 2.0 + 0.05)
	_col_shape.position = Vector3(0.0, h * 0.5, 0.0)


func _build_health_bar() -> void:
	if _health_bar != null:
		push_error("UndeadUnit %s: already wearing a health bar" % name)
		return
	_health_bar = MonsterHealthBarScript.new()
	add_child(_health_bar)
	_update_health_bar()


## Both halves of what the strip shows: how big this body is now, and how much of it is left.
## Runs from `_apply_scale`, so a growing giant's bar grows with it, and from the hit that took
## the points off. There is no bar before `setup` builds one or after death frees it, and both
## are states this is called in.
func _update_health_bar() -> void:
	if _health_bar == null:
		return
	_health_bar.fit_to_body(hit_radius(), body_reach_m())
	_health_bar.set_fraction(health_fraction())


## How wide the drawn body is, in metres at its current build and growth — wider than the hit
## capsule on every body that is broader than its torso. The model carries the build on its own
## scale, which `_apply_scale` has already written by the time this runs.
func body_reach_m() -> float:
	if _model == null or not is_instance_valid(_model):
		return 0.0
	return _model_reach * _model.scale.x


## A corpse has no health left to report. The body itself stays until its own timer frees it.
func _drop_health_bar() -> void:
	if _health_bar == null:
		return
	_health_bar.queue_free()
	_health_bar = null


# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

## The body decides, not the behaviour: a skeleton or a blob reads the span field as
## `undead`, a Quaternius Big monster at its native three metres reads it as `monster`, and
## a grown giant reads it as `giant`, which is 11 cells of clearance and `can_break` — the
## wall stops being a dead end and becomes a priced routing decision.
func nav_profile_id() -> int:
	if role == Role.GIANT:
		return NavProfile.Id.GIANT
	if _entry == null:
		return NavProfile.Id.UNDEAD
	return _entry.nav_profile


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
	## Combat kit owns living-prey strikes; CAST remains for the legacy mage orb cadence when
	## orb_convert is the only ready tool and the kit has not already fired.
	if _combat != null and _combat_prey != Vector3.INF:
		if bool(_combat.call("try_attack_living", _combat_prey)):
			return
	if not has_attack_id("orb_convert"):
		return
	if not can_cast():
		return
	state = State.CAST


func has_attack_id(attack_id: String) -> bool:
	return _combat != null and bool(_combat.call("has_attack", attack_id))


func on_facade_in_reach(point: Vector3, working: State) -> void:
	_facade_target = point
	state = working


func on_pad_in_reach() -> void:
	state = State.GROWING
	_play_action(CreatureClips.Action.IDLE)


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
	CityProfiler.begin("undead_unit")
	_cast_cd = maxf(0.0, _cast_cd - delta)
	_scrape_cd = maxf(0.0, _scrape_cd - delta)
	_nibble_cd = maxf(0.0, _nibble_cd - delta)
	_retarget_cd = maxf(0.0, _retarget_cd - delta)
	_hit_react_left = maxf(0.0, _hit_react_left - delta)
	if _provider != null:
		_provider.tick_pursuit(delta)
	if _combat != null:
		_combat.call("tick", delta)

	## Far units: skip anim switches most frames.
	var far := _distance_to_player() > ANIM_FAR_DIST_M
	if _anim != null:
		_anim.active = not far or role == Role.GIANT

	if (
		role != Role.GIANT
		and _invasion != null
		and _invasion.has_method("wants_giant_candidate")
		and bool(_invasion.call("wants_giant_candidate", self))
	):
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
			## Walking states: corridor plus table-driven strikes when prey is close.
			if state == State.SEEK_PED or state == State.STOMP:
				_tick_combat_strikes()
		_:
			push_error("UndeadUnit %s: unknown state %d" % [name, state])
	CityProfiler.begin("undead_nav")
	_tick_nav(delta)
	CityProfiler.end("undead_nav")
	CityProfiler.end("undead_unit")


func _tick_combat_strikes() -> void:
	if _combat == null or _combat_prey == Vector3.INF:
		return
	if not bool(_combat.call("has_living_prey")):
		return
	_combat.call("try_attack_living", _combat_prey)


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
	_play_action(CreatureClips.Action.CAST)
	## Fresh aim — never fire at the position the hunt goal was built from.
	var prey := _combat_prey
	if prey == Vector3.INF:
		var range_m := ORB_RANGE_M
		if has_attack_id("orb_convert"):
			range_m = CombatTableScript.monster_attack_range_m("orb_convert")
		prey = _city.find_nearest_ped_position(global_position, range_m)
	if prey == Vector3.INF:
		return
	_look_at_flat(prey)
	_fire_orb(prey)
	if has_attack_id("orb_convert"):
		## Keep the legacy cast_cd in sync with the table cooldown so can_cast() stays honest.
		_cast_cd = CombatTableScript.monster_attack_cooldown_s("orb_convert")
	else:
		_cast_cd = CAST_COOLDOWN_SEC


## Locked on a facade — keep swinging the whole time; the voxel only dies every 15 s.
func _tick_nibble() -> void:
	_look_at_flat(_facade_target)
	if _hit_react_left <= 0.0:
		_replay_action(CreatureClips.Action.MELEE)
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
	if _invasion != null and _invasion.has_method("notify_giant_ready"):
		_invasion.call("notify_giant_ready", self)
	_play_action(CreatureClips.Action.IDLE)


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
	var parent: Node = _roster if _roster != null else self
	parent.add_child(orb)
	var muzzle := global_position + Vector3(0.0, MUZZLE_BASE_M * _span_tall() * character_scale, 0.0)
	## Prey aim point already includes chest height from LOS selection.
	## Convert callback is invasion-only; arena mages still fire for player hit via city.
	if orb.has_method("launch"):
		orb.call("launch", muzzle, toward, _invasion, _city)


func _distance_to_player() -> float:
	var p := _city.get_player_position()
	if p == Vector3.INF:
		return 0.0
	return global_position.distance_to(p)


func _move_speed() -> float:
	var base := MOVE_SPEED_MINION
	match role:
		Role.MAGE:
			base = MOVE_SPEED_MAGE
		Role.GIANT:
			## Cover ground at giant size without becoming unreadable.
			base = MOVE_SPEED_GIANT * clampf(0.55 + 0.12 * character_scale, 1.0, 2.4)
		_:
			base = MOVE_SPEED_MINION
	var mult := 1.0
	if _combat != null:
		mult = float(_combat.call("speed_mult"))
	return base * mult


# ---------------------------------------------------------------------------
# Presentation
# ---------------------------------------------------------------------------

func _animate_motion(moved: Vector3, delta: float) -> void:
	var flat := Vector3(moved.x, 0.0, moved.z)
	var ground_speed := flat.length() / delta
	if ground_speed < MOVE_ANIM_EPS_MPS:
		## Casting, chewing, peeling and flinching drive their own clips.
		if state != State.CAST and state != State.NIBBLE and state != State.SCRAPE:
			if _hit_react_left <= 0.0:
				_play_action(CreatureClips.Action.IDLE)
		return
	_face_direction(flat, delta)
	## A staggered body still turns and still walks its corridor — only the rig is busy.
	if _hit_react_left > 0.0:
		return
	_play_locomotion(ground_speed)


func _play_locomotion(ground_speed: float) -> void:
	if is_giant():
		## Don't speed the cycle up with the giant's long stride — keep it ponderous.
		_set_anim_speed(GIANT_ANIM_SPEED)
	else:
		_set_anim_speed(clampf(ground_speed / WALK_ANIM_REF_MPS, 0.4, 1.4))
	_replay_action(CreatureClips.Action.LOCOMOTION)


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


## The take this unit rolled for `action`. Empty only when the rig has no clip for it at all,
## which CreatureClips has already reported by name at load — there is nothing left to say
## about it once per frame.
func _clip_for(action: CreatureClips.Action) -> String:
	if _variation == null:
		return ""
	return _variation.clip_for(action)


## The visible half of a non-fatal hit. Every rig family in the catalogue ships a flinch, so a
## body with nothing to play here is a content bug rather than a body that stoically ignores
## being hit, and it says so by name.
func _play_hit_reaction() -> void:
	if _anim == null:
		return
	var clip := _clip_for(CreatureClips.Action.HIT_REACT)
	if clip.is_empty():
		push_error(
			"UndeadUnit %s: %s has no hit reaction to play"
			% [name, "no body" if _entry == null else _entry.id]
		)
		return
	var anim := _anim.get_animation(clip)
	if anim == null:
		push_error(
			"UndeadUnit: %s resolved its hit reaction to %s, a clip it does not have"
			% [_entry.id, clip]
		)
		return
	_hit_react_left = minf(anim.length, HIT_REACT_MAX_HOLD_SEC)
	if not _anim.active:
		## Ninety metres out with nobody to see it. The clip resolved, which is what mattered.
		return
	_set_anim_speed(1.0 if not is_giant() else GIANT_ANIM_SPEED)
	## Restarted rather than continued: two hits inside one flinch are two flinches, and
	## `_start` would keep the first one running because the clip name has not changed.
	_current_anim = clip
	_anim.play(clip)
	_anim.seek(0.0, true)


func _play_action(action: CreatureClips.Action) -> void:
	if _anim == null or not _anim.active:
		return
	_set_anim_speed(1.0 if not is_giant() else GIANT_ANIM_SPEED)
	_start(_clip_for(action))


## Let a finished one-shot come round again, so a minion keeps swinging between voxel kills
## instead of standing in the last frame of a punch.
func _replay_action(action: CreatureClips.Action) -> void:
	if _anim == null or not _anim.active:
		return
	_start(_clip_for(action))


func _start(clip: String) -> void:
	if clip.is_empty():
		return
	if _current_anim == clip and _anim.is_playing():
		return
	_current_anim = clip
	_anim.play(clip)
