## Outcome of one navigation query, whether it was served synchronously or from the queue.
##
## Status values mirror `PathStatus::code()` in native/city_voxel/src/nav_world.rs. Every
## failure is distinguishable so the agent layer can escalate deliberately instead of
## silently standing still.
class_name NavPathResult
extends RefCounted

## Self-preload so the static factory type-checks before class_cache picks us up.
const _Self := preload("res://scripts/city/nav_path_result.gd")

enum Status {
	OK = 0,
	## Reached the closest reachable span to the goal instead of the goal itself.
	PARTIAL = 1,
	## A route exists only by destroying something, and the profile allows that.
	BREACH = 2,
	## The agent is not standing anywhere the profile considers navigable.
	NO_START = 3,
	## The goal is not navigable for this profile.
	NO_GOAL = 4,
	## Start and goal are navigable but disconnected.
	UNREACHABLE = 5,
}

## Mirror of the `LINK_*` constants in native/city_voxel/src/nav.rs. NavService pins
## LINK_WALK against the extension at configure time.
const LINK_CLIMB := 0
const LINK_DROP := 1
const LINK_JUMP := 2
const LINK_WALK := 255

var request_id: int = 0
var profile_id: int = -1
var status: Status = Status.NO_START
## Corridor in world metres, starting at the requested `from`.
var points: PackedVector3Array = PackedVector3Array()
## Link kind used to enter each point; LINK_WALK for ordinary walking.
var link_kinds: PackedByteArray = PackedByteArray()
## Points the search produced before smoothing pulled the corridor straight, which is what
## makes the price of cost-aware smoothing visible next to `points.size()`.
var raw_points: int = 0
## Nodes the search expanded, for budgeting and the debug overlay.
var expanded: int = 0
## NavService version this path was built against — a newer one means repath.
var nav_version: int = 0
var from_world: Vector3 = Vector3.ZERO
var to_world: Vector3 = Vector3.ZERO


## Follow the corridor: the goal may not have been reached, but the route is real.
func is_usable() -> bool:
	return status == Status.OK or status == Status.PARTIAL or status == Status.BREACH


## The goal itself was reached.
func is_complete() -> bool:
	return status == Status.OK


func status_name() -> String:
	match status:
		Status.OK:
			return "OK"
		Status.PARTIAL:
			return "PARTIAL"
		Status.BREACH:
			return "BREACH"
		Status.NO_START:
			return "NO_START"
		Status.NO_GOAL:
			return "NO_GOAL"
		Status.UNREACHABLE:
			return "UNREACHABLE"
		_:
			push_error("NavPathResult: unknown status %d" % status)
			return "?"


func length_m() -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i].distance_to(points[i - 1])
	return total


## True when the corridor uses a baked traversal rather than plain walking anywhere.
func uses_links() -> bool:
	for i in range(link_kinds.size()):
		if int(link_kinds[i]) != LINK_WALK:
			return true
	return false


## Wrap the Dictionary NativeNavWorld.find_path returns.
static func from_query(
	p_request_id: int,
	p_profile_id: int,
	p_from: Vector3,
	p_to: Vector3,
	p_nav_version: int,
	raw: Dictionary
) -> _Self:
	var out: _Self = _Self.new()
	out.request_id = p_request_id
	out.profile_id = p_profile_id
	out.from_world = p_from
	out.to_world = p_to
	out.nav_version = p_nav_version
	var code := int(raw["status"])
	if code < int(Status.OK) or code > int(Status.UNREACHABLE):
		push_error("NavPathResult: extension returned unknown status %d" % code)
	out.status = code as Status
	out.points = raw["points"]
	out.link_kinds = raw["links"]
	out.raw_points = int(raw["raw_points"])
	out.expanded = int(raw["expanded"])
	return out
