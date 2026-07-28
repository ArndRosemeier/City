## Everything a goal provider is told when an agent needs work, as a value.
##
## The agent is not passed itself: a provider decides what an actor wants from the actor's
## situation, and a shared provider (one CrowdDirector for a thousand peds) keys its own
## bookkeeping off `body` or `agent_id`. Keeping the agent out also keeps the goal layer a
## one-way dependency.
class_name NavGoalRequest
extends RefCounted

## The moving node. Null only if the agent was set up without one, which is a bug.
var body: Node3D = null
## Stable per-agent id, assigned by NavAgent. Lets a shared provider index its own arrays.
var agent_id: int = 0
var position: Vector3 = Vector3.ZERO
## NavProfile.Id this agent paths with.
var profile_id: int = -1
## Why the previous goal ended. PATH_OK means it was reached, or there was no previous goal.
var last_state: NavLadder.State = NavLadder.State.PATH_OK
## The goal that just ended, or null on the agent's first request.
var last_goal: NavGoal = null
## How often this agent has been entombed. A provider may want to stop sending an actor
## back into the same collapsing building.
var trapped_count: int = 0


func describe() -> String:
	return (
		"agent %d at %.1f,%.1f,%.1f profile=%d last=%s trapped=%d"
		% [
			agent_id,
			position.x,
			position.y,
			position.z,
			profile_id,
			NavLadder.state_name(last_state),
			trapped_count,
		]
	)
