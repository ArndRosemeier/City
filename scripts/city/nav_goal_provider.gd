## What an actor wants next. One provider per actor kind — peds pick errands, undead pick
## prey, cars pick lanes — and NavAgent only ever asks.
##
## Abstract: `next_goal` must be overridden. The two notifications are optional, and both
## fire on the main thread inside the agent's tick, so a provider may spawn, despawn or
## re-target from them.
class_name NavGoalProvider
extends RefCounted


## The next goal, or null for "nothing to do", which parks the agent until it is asked again.
func next_goal(_request: NavGoalRequest) -> NavGoal:
	push_error(
		"NavGoalProvider.next_goal is abstract: %s must override it"
		% get_script().resource_path
	)
	return null


## The goal was satisfied.
func goal_reached(_request: NavGoalRequest, _goal: NavGoal) -> void:
	pass


## The ladder gave up on the goal at `state` — GOAL_UNREACHABLE or TRAPPED. The agent will
## call `next_goal` straight after this, so re-planning here is the intended place.
func goal_failed(_request: NavGoalRequest, _goal: NavGoal, _state: NavLadder.State) -> void:
	pass
