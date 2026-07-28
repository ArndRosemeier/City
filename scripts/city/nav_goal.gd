## What one actor currently wants, as a value instead of a Dictionary.
##
## A goal is geometry plus an arrival rule; it holds no navigation state, so a provider may
## hand the same goal to an agent twice and hand one goal to several agents. NavAgent turns
## it into a destination and paths there — see `raw_destination`.
class_name NavGoal
extends RefCounted

## Self-preload so the static factories type-check before class_cache picks us up.
const _Self := preload("res://scripts/city/nav_goal.gd")

enum Kind {
	## Walk to a fixed world point and finish.
	GO_TO_POINT = 0,
	## Stay within `radius` of a moving node, indefinitely.
	FOLLOW = 1,
	## Put `radius` metres between the body and a threat, then finish.
	FLEE = 2,
	## Pick a span within `radius` of an anchor, walk to it, finish.
	WANDER = 3,
	## Walk into reach of a node in order to interact with it, then finish.
	USE_TARGET = 4,
}

var kind: Kind = Kind.GO_TO_POINT
## GO_TO_POINT destination, WANDER anchor, FLEE threat position when `target` is null.
var point: Vector3 = Vector3.ZERO
## FOLLOW and USE_TARGET subject, FLEE threat. Null for the purely positional kinds.
var target: Node3D = null
## GO_TO_POINT and USE_TARGET arrival distance, FOLLOW hold distance, FLEE clear distance,
## WANDER pick radius. Metres.
var radius: float = 1.5
## Provider bookkeeping. NavAgent never reads it.
var tag: StringName = &""


static func go_to_point(world_point: Vector3, arrive_radius: float = 1.5) -> _Self:
	var g: _Self = _Self.new()
	g.kind = Kind.GO_TO_POINT
	g.point = world_point
	g.radius = arrive_radius
	return g


static func follow(node: Node3D, hold_distance: float = 3.0) -> _Self:
	var g: _Self = _Self.new()
	g.kind = Kind.FOLLOW
	g.target = node
	g.radius = hold_distance
	if node == null:
		push_error("NavGoal.follow: no node to follow")
	return g


static func flee(threat: Node3D, clear_distance: float = 40.0) -> _Self:
	var g: _Self = _Self.new()
	g.kind = Kind.FLEE
	g.target = threat
	g.radius = clear_distance
	if threat == null:
		push_error("NavGoal.flee: no threat to flee")
	return g


## Flee something that is not a node — a blast site, a fire, a collapsed street.
static func flee_point(threat_point: Vector3, clear_distance: float = 40.0) -> _Self:
	var g: _Self = _Self.new()
	g.kind = Kind.FLEE
	g.point = threat_point
	g.radius = clear_distance
	return g


static func wander(anchor: Vector3, pick_radius: float = 24.0) -> _Self:
	var g: _Self = _Self.new()
	g.kind = Kind.WANDER
	g.point = anchor
	g.radius = pick_radius
	return g


static func use_target(node: Node3D, reach: float = 1.5) -> _Self:
	var g: _Self = _Self.new()
	g.kind = Kind.USE_TARGET
	g.target = node
	g.radius = reach
	if node == null:
		push_error("NavGoal.use_target: no node to use")
	return g


## False once a node target has been freed: the goal cannot be pursued any more and the
## agent has to ask the provider for a different one.
func is_alive() -> bool:
	if not needs_target():
		return true
	return target != null and is_instance_valid(target)


## Kinds that cannot exist without their node.
func needs_target() -> bool:
	return kind == Kind.FOLLOW or kind == Kind.USE_TARGET


## Kinds whose destination moves while the agent walks, so it has to be re-resolved.
func tracks_target() -> bool:
	return kind == Kind.FOLLOW or kind == Kind.USE_TARGET or kind == Kind.FLEE


## FOLLOW never finishes — the agent keeps holding the distance. Everything else completes,
## and completion is what makes the provider hand out the next goal.
func is_persistent() -> bool:
	return kind == Kind.FOLLOW


## WANDER has no destination of its own: the agent picks a span near the anchor, because
## only NavService knows which points are standable.
func needs_destination_pick() -> bool:
	return kind == Kind.WANDER


## Where the node or point this goal revolves around is right now.
func subject_position() -> Vector3:
	if target != null and is_instance_valid(target):
		return target.global_position
	return point


## The world point to path to, before it is snapped onto a span. WANDER returns its anchor;
## the agent replaces that with a picked destination.
func raw_destination(from: Vector3) -> Vector3:
	match kind:
		Kind.GO_TO_POINT, Kind.WANDER:
			return point
		Kind.FOLLOW, Kind.USE_TARGET:
			return subject_position()
		Kind.FLEE:
			var away := from - subject_position()
			away.y = 0.0
			if away.length_squared() < 0.0001:
				## Standing on the threat: any direction is an improvement.
				away = Vector3.FORWARD
			return from + away.normalized() * radius
		_:
			push_error("NavGoal: unknown kind %d" % kind)
			return from


## Has the body done what the goal asked? For FOLLOW this means the distance is held, not
## that the goal is over.
func is_satisfied(from: Vector3, destination: Vector3) -> bool:
	match kind:
		Kind.GO_TO_POINT, Kind.WANDER:
			return from.distance_to(destination) <= radius
		Kind.FOLLOW, Kind.USE_TARGET:
			return from.distance_to(subject_position()) <= radius
		Kind.FLEE:
			return from.distance_to(subject_position()) >= radius
		_:
			push_error("NavGoal: unknown kind %d" % kind)
			return false


func kind_name() -> String:
	match kind:
		Kind.GO_TO_POINT:
			return "GoToPoint"
		Kind.FOLLOW:
			return "Follow"
		Kind.FLEE:
			return "Flee"
		Kind.WANDER:
			return "Wander"
		Kind.USE_TARGET:
			return "UseTarget"
		_:
			push_error("NavGoal: unknown kind %d" % kind)
			return "?"


func describe() -> String:
	if needs_target() or (kind == Kind.FLEE and target != null):
		var name := "<freed>"
		if is_instance_valid(target):
			name = String(target.name)
		return "%s(%s r=%.1f)" % [kind_name(), name, radius]
	return "%s(%.1f,%.1f,%.1f r=%.1f)" % [kind_name(), point.x, point.y, point.z, radius]
