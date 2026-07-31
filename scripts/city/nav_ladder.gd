## The six navigation failure states, and how a TRAPPED agent got out.
##
## Named states instead of silent fallbacks: an agent that cannot reach its goal escalates
## one rung at a time and every rung is observable, so "the mob is standing still" is always
## answerable. NavAgent walks the ladder; the debug overlay and goal providers read it.
class_name NavLadder
extends RefCounted

## Rungs in escalation order — a higher value is a worse situation.
enum State {
	## The corridor reaches the goal; follow it.
	PATH_OK = 0,
	## The goal is unreachable for this profile, but the corridor reaches the closest span
	## to it. Walk that, then re-evaluate.
	PATH_PARTIAL = 1,
	## Displacement along the corridor fell below what the motor asked for. Repath inside
	## the current sector.
	NO_PROGRESS = 2,
	## Local repathing did not help. Write the offending column into the dynamic-block
	## overlay so every other agent routes around it too, then repath.
	BLOCKED = 3,
	## Nothing routes to this goal. Abandon it and ask the provider for another.
	GOAL_UNREACHABLE = 4,
	## Entombed: no goal is reachable because the body is not anywhere navigable. Last
	## resort, always reported.
	TRAPPED = 5,
}

## How a TRAPPED agent was freed.
enum Escape {
	NONE = 0,
	## can_break profile: the consumer was asked to dig, and the voxels are its business.
	DUG_OUT = 1,
	## Moved to the nearest span the profile can stand on.
	TELEPORTED = 2,
	## No span within reach. The agent stays put; consumers may despawn the body.
	LOST = 3,
}


static func state_name(state: State) -> String:
	match state:
		State.PATH_OK:
			return "PATH_OK"
		State.PATH_PARTIAL:
			return "PATH_PARTIAL"
		State.NO_PROGRESS:
			return "NO_PROGRESS"
		State.BLOCKED:
			return "BLOCKED"
		State.GOAL_UNREACHABLE:
			return "GOAL_UNREACHABLE"
		State.TRAPPED:
			return "TRAPPED"
		_:
			push_error("NavLadder: unknown state %d" % state)
			return "?"


static func escape_name(escape: Escape) -> String:
	match escape:
		Escape.NONE:
			return "NONE"
		Escape.DUG_OUT:
			return "DUG_OUT"
		Escape.TELEPORTED:
			return "TELEPORTED"
		Escape.LOST:
			return "LOST"
		_:
			push_error("NavLadder: unknown escape %d" % escape)
			return "?"


## A failure the goal cannot survive: the provider is going to be asked for another one.
static func is_terminal(state: State) -> bool:
	return state == State.GOAL_UNREACHABLE or state == State.TRAPPED
