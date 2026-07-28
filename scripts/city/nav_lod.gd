## The three navigation LOD tiers and where they switch.
##
## A thousand pedestrians across nine districts cannot each afford a fine path and a collider,
## so distance from the observer decides how much machinery an agent gets:
##
## - NEAR: full profile path, VoxelBoxMover motion, steering separation.
## - MID: the same fine path, span-following motion, no colliders.
## - FAR: no per-agent pathing — one corridor every `far_corridor_sec`, interpolated. The
##   per-frame cost is a lerp.
##
## Shared: one instance per director, so a settings change moves every agent at once.
class_name NavLod
extends RefCounted

## Self-preload so the static factory type-checks before class_cache picks us up.
const _Self := preload("res://scripts/city/nav_lod.gd")

enum Tier {
	NEAR = 0,
	MID = 1,
	FAR = 2,
}

## city_root's collision VoxelViewer is 48 voxels by default, so colliders exist out to 24 m.
const COLLISION_VIEW_VOX_DEFAULT := 48
## How far inside the collider radius the near band stops. VoxelBoxMover reads voxel data
## rather than meshed colliders, but the terrain only holds blocks the viewer asked for, so
## a body on the rim would be moving against a world that is still streaming in.
const COLLISION_MARGIN_M := 4.0
## Past this, a body is out of the ped render distance (70 m) as well, so nobody can see
## whether it followed the corridor or interpolated it.
const MID_RADIUS_M := 80.0
const HYSTERESIS_M := 6.0
## The plan's "one high-level corridor every ~30 s".
const FAR_CORRIDOR_SEC := 30.0

var near_radius_m: float = float(COLLISION_VIEW_VOX_DEFAULT) * 0.5 - COLLISION_MARGIN_M
var mid_radius_m: float = MID_RADIUS_M
## Band overlap, so an agent walking the boundary does not switch tiers every frame.
var hysteresis_m: float = HYSTERESIS_M
var far_corridor_sec: float = FAR_CORRIDOR_SEC
## Shortest gap between repaths, per tier.
var near_repath_sec: float = 0.5
var mid_repath_sec: float = 1.5
## How long a corridor may stay stale after a nav_version bump before the agent repaths.
## Lazy on purpose: a blast dirties one sector and hundreds of agents must not all repath in
## the same frame.
var near_stale_sec: float = 0.2
var mid_stale_sec: float = 1.0
## Expansions a path may spend, per tier. NavService has no high-level-only query, so a far
## agent buys a coarse route by capping the fine search instead.
var near_budget: int = 0
var mid_budget: int = 0
var far_budget: int = 8000


## Tie the near band to the collision viewer the player is actually running, so raising
## `collision_view_vox` in the settings panel widens the band with it.
static func for_collision_view(view_vox: int, voxel_size: float) -> _Self:
	var lod: _Self = _Self.new()
	if view_vox <= 0 or voxel_size <= 0.0:
		push_error(
			"NavLod.for_collision_view: view_vox=%d voxel_size=%.3f must both be positive"
			% [view_vox, voxel_size]
		)
		return lod
	lod.near_radius_m = maxf(float(view_vox) * voxel_size - COLLISION_MARGIN_M, 1.0)
	return lod


## Which tier a body at `distance_m` from the observer belongs in, given the tier it is in
## now. Bands widen outwards for the current tier, so switching needs `hysteresis_m` of real
## movement in either direction.
func tier_for(distance_m: float, current: Tier) -> Tier:
	var near_edge := near_radius_m
	if current == Tier.NEAR:
		near_edge += hysteresis_m
	var mid_edge := mid_radius_m
	if current != Tier.FAR:
		mid_edge += hysteresis_m
	if distance_m <= near_edge:
		return Tier.NEAR
	if distance_m <= mid_edge:
		return Tier.MID
	return Tier.FAR


func repath_interval_sec(tier: Tier) -> float:
	match tier:
		Tier.NEAR:
			return near_repath_sec
		Tier.MID:
			return mid_repath_sec
		Tier.FAR:
			return far_corridor_sec
		_:
			push_error("NavLod: unknown tier %d" % tier)
			return mid_repath_sec


## Zero means "never on a timer": a far agent's own corridor tick is its only repath.
func stale_grace_sec(tier: Tier) -> float:
	match tier:
		Tier.NEAR:
			return near_stale_sec
		Tier.MID:
			return mid_stale_sec
		Tier.FAR:
			return 0.0
		_:
			push_error("NavLod: unknown tier %d" % tier)
			return mid_stale_sec


## 0 hands NavService its own default budget.
func path_budget(tier: Tier) -> int:
	match tier:
		Tier.NEAR:
			return near_budget
		Tier.MID:
			return mid_budget
		Tier.FAR:
			return far_budget
		_:
			push_error("NavLod: unknown tier %d" % tier)
			return mid_budget


## Only the near tier has colliders to steer around each other with.
func uses_separation(tier: Tier) -> bool:
	return tier == Tier.NEAR


## A far body's motion is a lerp along its corridor, so it cannot fail to make progress and
## the NO_PROGRESS and BLOCKED rungs would only ever be false positives.
func detects_no_progress(tier: Tier) -> bool:
	return tier != Tier.FAR


static func tier_name(tier: Tier) -> String:
	match tier:
		Tier.NEAR:
			return "NEAR"
		Tier.MID:
			return "MID"
		Tier.FAR:
			return "FAR"
		_:
			push_error("NavLod: unknown tier %d" % tier)
			return "?"
