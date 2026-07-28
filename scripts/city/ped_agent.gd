## One city pedestrian: the body the navigation stack drives, plus the presentation state the
## crowd director and the skinned visual read back.
##
## A CharacterBody3D rather than a plain brain, because the near tier moves peds with
## VoxelBoxMover through NavMotor, which needs a body and a capsule to sweep. The capsule is
## built only once a ped comes close enough to be simulated that way, and the body sits on no
## collision layer at all: peds have never blocked cars, corpses or the player, and giving them
## a physics presence here would change that.
##
## `position` is the inherited Node3D translation, and every consumer — the visual, crossing
## occupancy in street_nav_layers.gd, the vehicle director — reads it as a world position, so
## CrowdDirector asserts that the crowd hangs off an untransformed parent chain.
class_name PedAgent
extends CharacterBody3D

enum State { STAY, WALK }
enum Lod { CULLED, NEAR }

## Mirrors whether the nav agent holds a corridor, for the visual's locomotion clip.
var state: int = State.STAY
## Visual LOD, which is about render distance and has nothing to do with the nav tier.
var lod: int = Lod.CULLED
var yaw: float = 0.0

## 0 = prefers staying, 1 = prefers walking.
var walk_tendency: float = 0.5
var walk_speed: float = 1.35
var female: bool = false
var body_scale: float = 1.0
var outfit: PedOutfit

## Goal, corridor and failure ladder. Built by CrowdDirector.
var nav: NavAgent = null
var motor: NavMotor = null
## Near-tier collider, absent until this ped has been close to the observer once.
var capsule: CollisionShape3D = null
var motion: VoxelBodyMotion = null

## Bound skinned visual while inside render distance; null when culled.
var visual: Node3D = null
## Avoid duplicate entries in the budgeted visual-creation queue.
var visual_queued: bool = false
## Laser/melee kill — stops simulation; Death01 holds on the visual.
var dead: bool = false

## True while sprinting away from a threat (player destruction or undead mage).
var fleeing: bool = false
## Latest threat point to run away from.
var flee_from: Vector3 = Vector3.ZERO
## Stop fleeing once at least this far from flee_from.
var flee_clear_m: float = 200.0
## Avoid duplicate entries in the budgeted flee-goal queue.
var flee_goal_queued: bool = false

## The goal provider hands out no errand before this: the pause between two walks, and the
## rarer decision to stay put for a while.
var paused_until: float = 0.0
## World points left in the current errand, walked one NavGoal at a time. Usually just the
## destination; a crossing on the way adds its curb pads and carriageway mid in front of it.
var legs: Array[Vector3] = []
## Where the body stood on the previous tick, which is what it is facing away from.
var last_pos: Vector3 = Vector3.ZERO
## Seconds owed to a far-tier body, which is stepped every few frames rather than every one.
var owed_delta: float = 0.0


func is_walking() -> bool:
	return (not dead) and state == State.WALK


func is_fleeing() -> bool:
	return (not dead) and fleeing


func move_speed(flee_mul: float = 2.6) -> float:
	if is_fleeing():
		return walk_speed * flee_mul
	return walk_speed


func has_collider() -> bool:
	return capsule != null and motion != null
