## One undead soldier: Mage (convert), Minion (melee fodder), or Giant (grown + stomp).
##
## Who it fights is not on this script and not in a table: `_faction` against everyone
## else's, with the player and every pedestrian counting as `human`. Buildings are not
## targets at all — area attacks still carve them, but nothing here aims at fabric.
##
## Toughness is not a property of the role: it comes off whichever body the catalogue handed
## this unit, through `creature_health.gd`, so a two-metre skeleton and a four-metre monster
## wearing the same behaviour take a different number of hits. `kill_from_player` is what happens
## when the last of that runs out rather than what happens on contact (gem haul only on player hits).
##
## Movement is NavAgent + NavMotor over the baked span field. An UndeadGoalProvider says what
## this body wants and the six-rung ladder says what happens when it cannot get there. Escape
## hops live on NavAgent (wiggle → ≤2-voxel neighbour span; TRAPPED → nearest other column),
## counted and warned — never a silent horizontal unstick hack on this script. (Naming that hack
## here would trip the source sweep in test_undead_nav, which is the point of the sweep.)
class_name UndeadUnit
extends CharacterBody3D

enum Role { MAGE, MINION, GIANT }
enum State { IDLE, SEEK_PED, CAST, GROWING, STOMP, DEAD }

const OrbScript := preload("res://scripts/city/undead_orb_projectile.gd")
const CombatTableScript := preload("res://scripts/city/combat_table.gd")
const CreatureCatalogScript := preload("res://scripts/city/creature_catalog.gd")
const CreatureClipsScript := preload("res://scripts/city/creature_clips.gd")
const CreatureHealthScript := preload("res://scripts/city/creature_health.gd")
const CreatureVariationScript := preload("res://scripts/city/creature_variation.gd")
const DamageSourceScript := preload("res://scripts/city/damage_source.gd")
const MonsterAuraScript := preload("res://scripts/city/monster_aura.gd")
const MonsterCombatScript := preload("res://scripts/city/monster_combat.gd")
const MonsterFactionScript := preload("res://scripts/city/monster_faction.gd")
const MonsterHealthBarScript := preload("res://scripts/city/monster_health_bar.gd")

## PackedScenes stay referenced so a second summon of the same body is a cache hit, matching
## the ped/car warm-up pattern. First load of each path is still sync on the summon thread.
static var _scene_cache: Dictionary = {}  ## String path -> PackedScene

## Default ground speed for ordinary undead bodies. Role no longer halves mages —
## catalogue `speed_mult` is the only throttle.
const MOVE_SPEED := 4.2
const MOVE_SPEED_GIANT := 5.5
## KayKit walk cycle authored roughly around this ground speed.
const WALK_ANIM_REF_MPS := 1.55
## Giants keep a heavy, slow playback regardless of ground speed.
const GIANT_ANIM_SPEED := 0.38
const CAST_COOLDOWN_SEC := 20.0
## Faction every pedestrian and the player belong to. Mobs hunt anything that is not their
## own faction, so this is the only thing that makes a civilian a target.
const HUMAN_FACTION := MonsterFactionScript.Id.HUMAN
const ORB_RANGE_M := 30.0
## Stop this far inside orb range, so a step of drift does not put the target out of reach.
const ORB_STANDOFF_FRACTION := 0.92
## Between casts the mage keeps closing, exactly as the old straight-line pursue did.
const MAGE_CLOSE_IN_M := 2.5
## Chase / cast acquire range — give up if the target gets farther than this.
const MAGE_PURSUE_RANGE_M := 40.0
const GIANT_SCALE_TARGET := 10.0
const GROW_LOG_RATE := 0.55
## Longest a body holds its flinch before locomotion may have the rig back. The clip's own
## length wins under this — the KayKit flinch is a third of a second and the Blob one shorter —
## and the cap is here so a family that ships a two-second stagger cannot stop a body walking.
const HIT_REACT_MAX_HOLD_SEC := 0.6
## Same idea for strike / cast clips: `_tick_nav` runs after combat every frame and would
## otherwise replace a punch with Walking_A before the swing is visible.
const COMBAT_ANIM_MAX_HOLD_SEC := 1.15
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
## Floor on every shrink, so no clamp can collapse a body to nothing.
const MIN_CHARACTER_SCALE := 0.05
## How often prey is re-acquired for a running hunt.
const PED_QUERY_INTERVAL_SEC := 0.28
const ANIM_FAR_DIST_M := 90.0
## Fall acceleration for the near tier. Heavier than world gravity so a dropped body lands
## rather than floating down a facade.
const FALL_GRAVITY := 28.0
## Ground speed below which the body is treated as standing still for animation.
const MOVE_ANIM_EPS_MPS := 0.15
const FACE_LERP_RATE := 10.0
## Growth is done once the scale is within this of the target.
const GROW_EPSILON := 0.05
## Extra cells carved beyond the profile footprint when a giant digs itself out, so the
## pocket actually satisfies the clearance the profile asks for.
const DIG_OUT_MARGIN_CELLS := 1

signal died(unit: UndeadUnit, was_giant: bool)
## Emitted whenever the pool changes (hits, grow, player-minion rebinding).
signal health_changed(current: float, maximum: float)

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
## Set when a spawner shrinks this body out of the envelope its catalogue profile assumes.
## Negative means "ask the catalogue", which is what every body does until then.
var _nav_profile_override: int = -1
var _nav_motor: NavMotor
var _provider: UndeadGoalProvider
var _cast_cd: float = 0.0
var _alive: bool = true
var _yaw: float = 0.0
var _retarget_cd: float = 0.0
var _current_anim: String = ""
var _anim_clips: PackedStringArray = PackedStringArray()
## Which body this unit wears, and the roll that made it look like nobody else.
var _entry: CreatureCatalog.Entry = null
var _variation: CreatureVariation = null
var _seed: int = 0
## Catalogue entry asked for by name, empty when the seed chooses.
var _body_id: String = ""
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
## Seconds a melee / cast clip still owns the rig against locomotion and idle.
var _combat_anim_left: float = 0.0
## The orb is away; hold CAST one more frame so the spellcast clip is not stomped by the
## walking states' idle.
var _cast_fired: bool = false
## Resolved combat kit (MonsterCombat). Null only before setup finishes.
var _combat: RefCounted = null
## Passive-driven passives (MonsterAura). Null when the body has no auras.
var _aura: RefCounted = null
## MonsterFaction.Id for this body. Set once the catalogue entry is known.
var _faction: int = -1
## Optional standing destination when no living prey is acquirable (Siege Lodestone).
var _push_aim: Vector3 = Vector3.INF
## Flat metres from `_push_aim` inside which this body stops walking and holds. The objective
## owns this number: it is the same radius that decides whether the body is hurting it, so a
## body that stopped is always a body dealing damage.
var _push_hold_m: float = 1.5
## Cached living-prey aim for the combat tick (refreshed with the goal provider).
var _combat_prey: Vector3 = Vector3.INF
## Accumulator for stride SFX while locomoting (mirrors CityWalker cadence).
var _footstep_accum: float = 0.0
## True for meshless Siege Quarter foundation towers (voxel stamp is the visual).
var _siege_tower: bool = false
## Structure towers that summon for a monster faction (crypt / castle dungeon). Same body as a
## siege pad, opposite side of the fight: the player is meant to shoot these down, and doing so
## always pays a recipe.
var _spawn_tower: bool = false
## Authored max HP for siege towers (CreatureHealth is meaningless for a building).
var _authored_hp: float = 0.0
## Flat structure volume for siege towers (stamp face + slack). Zero for creatures — they keep the
## capsule `hit_radius`. Not a physics collider; hunt engage and melee gap use it the way stones
## use `vuln_radius_m`.
var _structure_hit_radius_m: float = 0.0
## Muzzle height above this body's origin in metres, or a negative for "derive it from body span".
## Siege towers must set it: they stand inside their own voxel stamp, and the muzzle is where every
## line-of-sight probe starts. See `muzzle_world`.
var _muzzle_height_m: float = -1.0


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
	add_to_group("undead")
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
	state = State.STOMP if role == Role.GIANT else State.SEEK_PED
	_build_nav()
	_play_action(CreatureClips.Action.IDLE)
	CityProfiler.end("undead_setup")


## Meshless foundation turret. Combat comes from a table row (`siege/…` for a bought pad,
## `spawn/…` for a district's summoning spire); the voxel stamp is the visual.
##
## `faction_id` decides which side owns it, and with it who may shoot it: a `SIEGE_DEFENDER`
## tower is the player's own pad and rejects their fire, any other side is a target. Not added
## to the `undead` group — hunt and aim reach a structure through the roster, not the group.
func setup_siege_tower(
	roster: MonsterRoster,
	city: CityRoot,
	world_pos: Vector3,
	terrain: VoxelTerrain,
	lod: NavLod,
	combat_id: String,
	authored_hp: float,
	muzzle_height_m: float,
	structure_hit_radius_m: float,
	p_seed: int,
	faction_id: int,
	p_spawn_tower: bool
) -> void:
	if combat_id.is_empty():
		push_error("UndeadUnit.setup_siege_tower: empty combat_id")
		assert(false, "UndeadUnit: empty tower combat id")
		return
	if authored_hp <= 0.0:
		push_error("UndeadUnit.setup_siege_tower: non-positive hp %f" % authored_hp)
		assert(false, "UndeadUnit: bad tower hp")
		return
	if muzzle_height_m <= 0.0:
		push_error(
			"UndeadUnit.setup_siege_tower: non-positive muzzle height %f" % muzzle_height_m
		)
		assert(false, "UndeadUnit: bad tower muzzle height")
		return
	if structure_hit_radius_m <= 0.0:
		push_error(
			"UndeadUnit.setup_siege_tower: non-positive structure hit radius %f"
			% structure_hit_radius_m
		)
		assert(false, "UndeadUnit: bad tower structure hit radius")
		return
	role = Role.MINION
	_siege_tower = true
	_spawn_tower = p_spawn_tower
	_authored_hp = authored_hp
	_muzzle_height_m = muzzle_height_m
	_structure_hit_radius_m = structure_hit_radius_m
	_body_id = combat_id
	_roster = roster
	_invasion = null
	_city = city
	_terrain = terrain
	_lod = lod
	_seed = p_seed
	global_position = world_pos
	character_scale = 1.0
	_alive = true
	collision_layer = 2
	collision_mask = 1
	name = "%s_%s" % [
		"SpawnTower" if p_spawn_tower else "SiegeTower", combat_id.get_file()
	]
	CityProfiler.begin("undead_setup")
	_build_body()
	_bind_combat_for_id(combat_id)
	set_faction(faction_id)
	_reset_health()
	_apply_scale()
	_build_health_bar()
	state = State.SEEK_PED
	_build_nav()
	CityProfiler.end("undead_setup")


func is_siege_tower() -> bool:
	return _siege_tower


## A hostile summoning spire rather than a pad the player paid for.
func is_spawn_tower() -> bool:
	return _spawn_tower


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


## How tall the drawn body stands, in metres, at the scale it wears now.
##
## Measured off the mesh rather than the collider on purpose: headgear is what fouls a low
## ceiling, and all four KayKit skeletons declare the same `collider_height` no matter how
## tall they are actually drawn.
func standing_height_m() -> float:
	if _entry == null:
		push_error("UndeadUnit %s: standing_height_m before the body is bound" % name)
		assert(false, "UndeadUnit: no entry to measure")
		return 0.0
	var build_h := 1.0 if _variation == null else _variation.height
	return _entry.measured_height * build_h * character_scale


## Shrink until this body is at most `max_m` tall. Bodies already shorter are left as they are.
##
## For spawners that own a cramped room. A four-metre body dropped into a dungeon corridor
## with 2.5 m of headroom is wedged between slab and ceiling and never walks, so the pad that
## placed it says how tall its room can take. The collider and hit volume come along with the
## mesh, and a body that no longer needs monster headroom is handed the undead profile —
## otherwise the corridor has no walkable span for it at all and it stands still anyway.
func clamp_standing_height(max_m: float) -> void:
	if max_m <= 0.0:
		push_error("UndeadUnit %s: clamp_standing_height needs a positive limit" % name)
		assert(false, "UndeadUnit: bad height clamp")
		return
	var tall := standing_height_m()
	if tall <= max_m:
		return
	character_scale = maxf(character_scale * (max_m / tall), MIN_CHARACTER_SCALE)
	_apply_scale()
	## MONSTER_BREAKER keeps its own profile: that body is meant to make its own room, and
	## without `can_break` a walled-in chewer is handed no corridor and stands there forever.
	if nav_profile_id() == NavProfile.Id.MONSTER:
		_nav_profile_override = NavProfile.Id.UNDEAD
		_rebuild_nav()


func combat() -> RefCounted:
	return _combat


## MonsterFaction.Id for this body. Loud when called before setup finishes.
func faction() -> int:
	if _faction < 0:
		push_error("UndeadUnit %s: faction read before body bind" % name)
		assert(false, "UndeadUnit: no faction")
		return int(MonsterFactionScript.Id.UNDEAD)
	return _faction


## True when this unit may hurt `other`. Fresh prey acquisition is `can_acquire_prey`.
func is_hostile_to(other: UndeadUnit) -> bool:
	if other == null or not is_instance_valid(other):
		return false
	return MonsterFactionScript.is_hostile(_faction, other.faction())


## True when this unit may pick `other` as a fresh hunt target (not forced retaliation).
func can_acquire_prey(other: UndeadUnit) -> bool:
	if other == null or not is_instance_valid(other):
		return false
	return MonsterFactionScript.can_acquire(_faction, other.faction())


## Spawn-time (or controller) faction override. Loud on a bad id — silently wearing SPECTATOR
## or SIEGE_DEFENDER would make a body un-huntable for the wrong reason.
func set_faction(id: int) -> void:
	if not MonsterFactionScript.all().has(id as MonsterFactionScript.Id):
		push_error("UndeadUnit.set_faction: %d is not a MonsterFaction.Id" % id)
		assert(false, "UndeadUnit: bad faction")
		return
	_faction = id


## Per-body standing objective for when nothing living is worth hunting: the goal provider walks here
## before it wanders. `Vector3.INF` clears it.
##
## The siege stones used to be stamped in here at spawn and are not any more — they are `BeaconRegistry`
## entries, which the provider prefers, because a stone can die while a body is still walking to it
## and an aim frozen at spawn would keep sending it to a crater. This stays as the per-body form of
## the same idea for anything that wants one body to hold one spot.
func set_push_aim(world: Vector3, hold_m: float = 1.5) -> void:
	_push_aim = world
	_push_hold_m = maxf(hold_m, 0.5)


func push_aim() -> Vector3:
	return _push_aim


func push_hold_m() -> float:
	return _push_hold_m


## Scale HP and damage after spawn for a wave multiplier. Keeps the current health fraction
## so a mid-fight respec would not heal; fresh spawns are at full either way.
func scale_for_wave(hp_factor: float, damage_factor: float) -> void:
	if _combat == null:
		push_error("UndeadUnit %s: scale_for_wave before combat bind" % name)
		assert(false, "UndeadUnit: no combat for wave scale")
		return
	if hp_factor <= 0.0 or damage_factor <= 0.0:
		push_error(
			"UndeadUnit.scale_for_wave: non-positive factors hp=%f dmg=%f"
			% [hp_factor, damage_factor]
		)
		assert(false, "UndeadUnit: bad wave scale")
		return
	var next_hp := float(_combat.call("hp_mult")) * hp_factor
	_combat.call("set_hp_mult", next_hp)
	_combat.call("multiply_damage_mult", damage_factor)
	_update_health_for_scale()


## Player Minion power: same catalogue body, human allegiance, half size / HP / attack damage.
func become_player_minion() -> void:
	const MULT := 0.5
	if not _alive:
		push_error("UndeadUnit %s: become_player_minion on a dead body" % name)
		assert(false, "UndeadUnit: dead minion")
		return
	if _entry == null or _combat == null:
		push_error("UndeadUnit %s: become_player_minion before combat bind" % name)
		assert(false, "UndeadUnit: no combat for minion")
		return
	_faction = int(MonsterFactionScript.Id.HUMAN)
	var target_hp := _health_max * MULT
	_combat.call("multiply_damage_mult", MULT)
	character_scale = maxf(character_scale * MULT, MIN_CHARACTER_SCALE)
	var base := CreatureHealthScript.for_scale(_entry, character_scale)
	if base <= 0.0:
		push_error("UndeadUnit %s: minion scale has no health base" % name)
		assert(false, "UndeadUnit: minion health base")
		return
	## Keep grow-pad HP math honest: hp_mult is whatever makes max HP == half the original pool
	## at this scale (scale alone would only soft-reduce via GIANT_SCALE_EXPONENT).
	_combat.call("set_hp_mult", target_hp / base)
	_apply_scale()
	if absf(_health_max - target_hp) > 0.05:
		push_error(
			"UndeadUnit %s: minion HP %.2f want %.2f"
			% [name, _health_max, target_hp]
		)


func city() -> CityRoot:
	return _city


## Where this body looks and shoots from. Prey acquisition traces voxel LOS from here, so a muzzle
## inside solid rock is a body that can never see anything — which is why buildings carry an
## explicit height instead of one derived from a collider span they do not have.
func muzzle_world() -> Vector3:
	if _muzzle_height_m >= 0.0:
		return global_position + Vector3(0.0, _muzzle_height_m, 0.0)
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
	## Restart so the telegraph always begins at the wind-up pose.
	_play_combat_clip(_combat_clip_action(attack_id), true)


func play_combat_strike(attack_id: String) -> void:
	## After a windup the same clip is already running — continue it rather than restarting.
	_play_combat_clip(_combat_clip_action(attack_id), false)


func _combat_clip_action(attack_id: String) -> CreatureClips.Action:
	if (
		attack_id == "orb_convert"
		or attack_id == "eye_laser"
		or attack_id == "blaster"
		or attack_id == "charged_blast"
	):
		return CreatureClips.Action.CAST
	return CreatureClips.Action.MELEE


## Play (or continue) a combat clip and pin the rig so locomotion cannot erase it mid-swing.
func _play_combat_clip(action: CreatureClips.Action, restart: bool) -> void:
	if _anim == null:
		return
	var clip := _clip_for(action)
	if clip.is_empty():
		push_error(
			"UndeadUnit %s: %s has no %s clip to play"
			% [name, "no body" if _entry == null else _entry.id, CreatureClips.action_name(action)]
		)
		return
	var anim := _anim.get_animation(clip)
	if anim == null:
		push_error(
			"UndeadUnit: %s resolved %s to %s, a clip it does not have"
			% [
				"no body" if _entry == null else _entry.id,
				CreatureClips.action_name(action),
				clip,
			]
		)
		return
	_set_anim_speed(1.0 if not is_giant() else GIANT_ANIM_SPEED)
	var need_start := restart or _current_anim != clip or not _anim.is_playing()
	if need_start:
		_current_anim = clip
		if _anim.active:
			_anim.play(clip)
			_anim.seek(0.0, true)
	var left := anim.length
	if _anim.active and _current_anim == clip and _anim.is_playing():
		left = maxf(anim.length - _anim.current_animation_position, 0.05)
	_combat_anim_left = minf(left, COMBAT_ANIM_MAX_HOLD_SEC)


func fire_convert_orb(toward: Vector3) -> void:
	_fire_orb(toward)


## Instantly remove a pedestrian at `prey`, if this body is hostile to humans. No health pool.
func try_remove_ped_at(prey: Vector3, reach_m: float) -> bool:
	if _city == null:
		return false
	if not MonsterFactionScript.is_hostile(_faction, HUMAN_FACTION):
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
	## Towers: the stamp footprint, not the invisible host capsule. Hunt / melee / bolts all aim
	## at the host point inside the mass; without this, a body at the wall is forever out of reach.
	if _structure_hit_radius_m > 0.0:
		return _structure_hit_radius_m
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


## One hit from `source`. True when this hit was the fatal one, false while the body still stands.
##
## Incoming damage is divided by the body's resolved `armor_mult` (1.0 = catalogue tier as-is).
func apply_damage(source: DamageSource.Id) -> bool:
	return apply_damage_scaled(source, 1.0)


## Same as `apply_damage`, with the attacker's resolved `damage_mult` applied to the table amount.
## `attacker_label` is who the damage log credits (player punches stay `"player"`).
## `attacker` is promoted to forced pursuit prey (overrides table weights / LOS acquire).
func apply_damage_scaled(
	source: DamageSource.Id,
	scale: float,
	attacker_label: String = "player",
	attacker: Node = null
) -> bool:
	if not _alive:
		return false
	if scale <= 0.0:
		push_error(
			"UndeadUnit %s: apply_damage_scaled got non-positive scale %f"
			% [name, scale]
		)
		assert(false, "UndeadUnit: bad damage scale")
		return false
	if DamageSourceScript.target(source) != DamageSourceScript.Target.CREATURE:
		push_error(
			"UndeadUnit %s: %s hurts the player, not a creature"
			% [name, DamageSourceScript.source_name(source)]
		)
		return false
	## Own towers are unshootable — the player is SIEGE_DEFENDER during a run, and splash
	## from player weapons must not chew the pads they just spent the pot on. A structure on
	## any other side is an ordinary target: that is the whole point of a spawn spire.
	if (
		_siege_tower
		and _faction == int(MonsterFactionScript.Id.SIEGE_DEFENDER)
		and DamageSourceScript.is_player_vs_creature(source)
	):
		return false
	var armor := 1.0
	if _combat != null:
		armor = maxf(float(_combat.call("armor_mult")), 0.001)
	var before := _health
	var raw := DamageSourceScript.amount(source) * scale / armor
	_health -= raw
	var taken := minf(raw, before)
	var body_name: String = _body_id if not _body_id.is_empty() else String(name)
	if _entry != null:
		body_name = _entry.id
	var tree := Engine.get_main_loop() as SceneTree
	var log_node: Node = null
	if tree != null:
		log_node = tree.root.get_node_or_null("DamageLog")
	if CreatureHealthScript.is_dead(_health):
		_health = 0.0
		health_changed.emit(_health, _health_max)
		if log_node != null and log_node.has_method("record"):
			log_node.call(
				"record", attacker_label, body_name, source, taken, 0.0, _health_max, true
			)
		kill_from_player(DamageSourceScript.is_player_vs_creature(source), attacker)
		return true
	if log_node != null and log_node.has_method("record"):
		log_node.call(
			"record", attacker_label, body_name, source, taken, _health, _health_max, false
		)
	health_changed.emit(_health, _health_max)
	_update_health_bar()
	_play_hit_reaction()
	_promote_attacker_after_hit(source, attacker)
	return false


## Restore up to `amount` HP. Returns how much was actually applied (0 at full / dead).
## Used by the Siege Quarter repair channel — towers have no passive regen.
func apply_heal(amount: float) -> float:
	if not _alive:
		return 0.0
	if amount <= 0.0:
		push_error(
			"UndeadUnit %s: apply_heal got non-positive amount %f" % [name, amount]
		)
		assert(false, "UndeadUnit: bad heal amount")
		return 0.0
	if _health_max <= 0.0:
		return 0.0
	var room := _health_max - _health
	if room <= 0.0:
		return 0.0
	var add := minf(amount, room)
	_health += add
	health_changed.emit(_health, _health_max)
	_update_health_bar()
	return add


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


## Death: navigation disposed, the death clip played, `died` emitted, the body freed 1.6 s later.
## Called by the hit that empties the pool. Gem haul for player kills, and for siege-tower
## kills during a run (those feed the pot the same way). A spawn spire pays a recipe instead of
## stones — it is a landmark the player went underground to break, not another body in a wave.
func kill_from_player(player_kill: bool = false, killer: Node = null) -> void:
	if not _alive:
		return
	_alive = false
	state = State.DEAD
	velocity = Vector3.ZERO
	_dispose_nav()
	_drop_health_bar()
	_play_action(CreatureClips.Action.DEATH)
	var credit := player_kill
	if not credit and killer != null and is_instance_valid(killer) and killer.has_method("faction"):
		if int(killer.call("faction")) == int(MonsterFactionScript.Id.SIEGE_DEFENDER):
			credit = true
	if credit and _city != null:
		if _spawn_tower:
			if _city.has_method("grant_spawn_tower_kill"):
				_city.call("grant_spawn_tower_kill", global_position)
		elif not _siege_tower and _city.has_method("grant_monster_kill_haul"):
			_city.call("grant_monster_kill_haul", global_position, _health_max)
	died.emit(self, is_giant())
	var tree := get_tree()
	if tree != null:
		tree.create_timer(1.6 if not _siege_tower else 0.05).timeout.connect(queue_free)
	else:
		queue_free()


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
		## No distance fade/cull — undead must stay drawable well past typical fight range.
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
	_bind_combat_for_id(_entry.id)


func _bind_combat_for_id(combat_id: String) -> void:
	var stats: RefCounted = CombatTableScript.resolve(combat_id)
	if stats == null:
		push_error("UndeadUnit %s: CombatTable.resolve failed for '%s'" % [name, combat_id])
		assert(false, "UndeadUnit: combat resolve failed")
		return
	_combat = MonsterCombatScript.new()
	_combat.call("bind", self, stats)
	var aura_list: PackedStringArray = stats.get("auras") as PackedStringArray
	if aura_list != null and not aura_list.is_empty():
		_aura = MonsterAuraScript.new()
		_aura.call("bind", self, stats)
	else:
		_aura = null


func _reset_health() -> void:
	if _siege_tower:
		_health_max = _authored_hp
		_health = _health_max
		health_changed.emit(_health, _health_max)
		return
	var base := CreatureHealthScript.for_scale(_entry, character_scale)
	var mult := 1.0
	if _combat != null:
		mult = float(_combat.call("hp_mult"))
	_health_max = base * mult
	_health = _health_max
	health_changed.emit(_health, _health_max)


## Growing on a pad makes a body tougher as it happens rather than all at once when it finishes,
## and a monster halfway through a fight stays halfway through it — a giant that healed to full
## by growing would be a giant nobody could ever wear down.
func _update_health_for_scale() -> void:
	if _siege_tower:
		## A tower's pool is authored in `siege_towers` and there is no catalogue entry to
		## derive a tier from. Buildings never stand on a grow pad either, so the scale that
		## drives this recompute never moves.
		return
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
	health_changed.emit(_health, _health_max)


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
	## Grow with sqrt so giants stay street-capable; hard-clamp for 10×. The base is this
	## body's own size rather than the reference skeleton's, so a three-metre monster never
	## collides as if it were a minion.
	##
	## Shrinking is linear and is allowed to go under that base: a body a spawner squeezed
	## into a low room has to collide small too, or it keeps the capsule that wedged it into
	## the floor and the clamp buys nothing but a smaller drawing.
	var base_r := COL_RADIUS_BASE_M * _span_wide()
	var base_h := COL_HEIGHT_BASE_M * _span_tall()
	var factor := sqrt(character_scale) if character_scale > 1.0 else character_scale
	var r := minf(base_r * factor, COL_RADIUS_MAX_M)
	var h := minf(base_h * factor, COL_HEIGHT_MAX_M)
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
	if _siege_tower:
		## Half-size horizontal strip on the foundation cell under the host.
		var vox := 0.5
		var nav := NavService.instance()
		if nav != null and nav.is_configured():
			vox = nav.voxel_size()
		_health_bar.fit_over_structure(hit_radius(), _muzzle_height_m, vox)
	else:
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
	if _nav_profile_override >= 0:
		return _nav_profile_override
	if _entry == null:
		return NavProfile.Id.UNDEAD
	## A body that eats its way forward needs a navigator willing to route it into fabric.
	## On the plain monster profile a walled-in body is handed no goal, so it never strides
	## and its aura never fires — see NavProfile.monster_breaker.
	if _entry.nav_profile == NavProfile.Id.MONSTER and chews_terrain():
		return NavProfile.Id.MONSTER_BREAKER
	return _entry.nav_profile


## True when an aura on this body carves terrain as it advances (MonsterAura.chews_terrain).
func chews_terrain() -> bool:
	return _aura != null and bool(_aura.call("chews_terrain"))


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


## Entombment. NavAgent has already counted it, warned and moved or dug the body out, and the
## hunting states this body can be in survive being relocated — so there is nothing to undo.
func _on_trapped(_world_pos: Vector3, _escape: NavLadder.Escape) -> void:
	pass


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


## The ladder abandoned a goal — GOAL_UNREACHABLE or TRAPPED, both already reported by
## NavAgent. The provider picks the next goal from scratch; nothing on the body to unwind.
func on_goal_failed(_goal: NavGoal, _ladder_state: NavLadder.State) -> void:
	pass


# ---------------------------------------------------------------------------
# Frame
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	tick(delta)


## One frame of behaviour and navigation. Public so a headless test can step a body on a
## fixed delta instead of at whatever rate the physics server happens to run.
func begin_trap_hold(duration_sec: float) -> void:
	set_meta("trap_hold_until", Time.get_ticks_msec() + int(maxf(duration_sec, 0.0) * 1000.0))
	velocity = Vector3.ZERO


func is_trap_held() -> bool:
	if not has_meta("trap_hold_until"):
		return false
	if Time.get_ticks_msec() < int(get_meta("trap_hold_until")):
		return true
	remove_meta("trap_hold_until")
	return false


func tick(delta: float) -> void:
	if not _alive:
		return
	if not _city.is_player_alive():
		return
	if is_trap_held():
		velocity = Vector3.ZERO
		return
	CityProfiler.begin("undead_unit")
	_cast_cd = maxf(0.0, _cast_cd - delta)
	_retarget_cd = maxf(0.0, _retarget_cd - delta)
	_hit_react_left = maxf(0.0, _hit_react_left - delta)
	_combat_anim_left = maxf(0.0, _combat_anim_left - delta)
	if _provider != null:
		_provider.tick_pursuit(delta)
	if _combat != null:
		_combat.call("tick", delta)
	if _aura != null:
		_aura.call("tick", delta)

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
		_begin_growth()

	match state:
		State.CAST:
			_tick_cast()
		State.GROWING:
			_tick_growing(delta)
		State.IDLE, State.SEEK_PED, State.STOMP, State.DEAD:
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
	if _combat == null:
		return
	if _combat_prey != Vector3.INF:
		if bool(_combat.call("hunts_living")):
			_combat.call("try_attack_living", _combat_prey)
		return
	## Nothing living to swing at, but this body may be standing on an objective it is grinding down.
	if _provider == null:
		return
	var aim := _provider.objective_strike_aim()
	if aim == Vector3.INF:
		return
	_combat.call("strike_structure", aim)


## The director has picked this body to become the invasion's giant. It swells where it stands:
## the glowing grow pads it used to walk to are gone, and having to escort a candidate to a
## street fixture was the one part of an invasion the player could trivially defuse.
func _begin_growth() -> void:
	if state == State.GROWING or state == State.STOMP:
		return
	state = State.GROWING
	_play_action(CreatureClips.Action.IDLE)
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


func _tick_growing(delta: float) -> void:
	character_scale = minf(GIANT_SCALE_TARGET, character_scale * exp(GROW_LOG_RATE * delta))
	_apply_scale()
	if character_scale < GIANT_SCALE_TARGET - GROW_EPSILON:
		return
	_become_giant()


func _become_giant() -> void:
	character_scale = GIANT_SCALE_TARGET
	role = Role.GIANT
	state = State.STOMP
	_apply_scale()
	## A giant is a different body to the field: it re-registers on the giant profile.
	_rebuild_nav()
	if _invasion != null and _invasion.has_method("notify_giant_ready"):
		_invasion.call("notify_giant_ready", self)
	_play_action(CreatureClips.Action.IDLE)


func _fire_orb(toward: Vector3) -> void:
	var orb: Node = OrbScript.new()
	orb.name = "UndeadOrb"
	var parent: Node = _roster if _roster != null else self
	parent.add_child(orb)
	var muzzle := muzzle_world()
	## Prey aim point already includes chest height from LOS selection.
	## Convert callback is invasion-only; arena mages still fire for player hit via city.
	## Human-faction allies must not convert the player they fight beside.
	var hits_player := MonsterFactionScript.is_hostile(_faction, HUMAN_FACTION)
	if orb.has_method("launch"):
		orb.call("launch", muzzle, toward, _invasion, _city, hits_player)


func _distance_to_player() -> float:
	var p := _city.get_player_position()
	if p == Vector3.INF:
		return 0.0
	return global_position.distance_to(p)


func _move_speed() -> float:
	var base := MOVE_SPEED
	if role == Role.GIANT:
		## Cover ground at giant size without becoming unreadable.
		base = MOVE_SPEED_GIANT * clampf(0.55 + 0.12 * character_scale, 1.0, 2.4)
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
		_footstep_accum = 0.0
		## Casting, striking, and flinching drive their own clips.
		if state != State.CAST and _hit_react_left <= 0.0 and _combat_anim_left <= 0.0:
			_play_action(CreatureClips.Action.IDLE)
		return
	_face_direction(flat, delta)
	## A staggered or swinging body still turns — only the locomotion clip waits.
	if _hit_react_left > 0.0 or _combat_anim_left > 0.0:
		return
	_update_footstep_sfx(delta, ground_speed)
	_play_locomotion(ground_speed)


func _update_footstep_sfx(delta: float, ground_speed: float) -> void:
	if not is_on_floor():
		_footstep_accum = 0.0
		return
	## Stride interval grows with size so giants don't machine-gun footsteps.
	var interval := clampf(0.34 * sqrt(character_scale), 0.24, 0.9)
	var cadence := clampf(ground_speed / maxf(_move_speed(), 0.01), 0.55, 1.6)
	_footstep_accum += delta * cadence
	if _footstep_accum < interval:
		return
	_footstep_accum = 0.0
	var tree := get_tree()
	if tree == null:
		return
	var audio := tree.get_first_node_in_group(&"city_audio")
	if audio != null and audio.has_method("play_monster_footstep"):
		audio.call("play_monster_footstep", global_position, character_scale)


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
