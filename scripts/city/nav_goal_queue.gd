## A provider that hands out a prepared list of goals, in order.
##
## For tools, tests and scripted actors: a real consumer decides what it wants from the world
## state instead. Counts what happened to each goal, so a caller can assert the ladder drove
## the provider rather than the agent quietly giving up.
class_name NavGoalQueue
extends NavGoalProvider

## Cycle instead of running dry.
var looping: bool = false

var _goals: Array[NavGoal] = []
var _next: int = 0
var _asked: int = 0
var _reached: int = 0
var _failed: int = 0
var _last_failure: NavLadder.State = NavLadder.State.PATH_OK


func add(goal: NavGoal) -> void:
	if goal == null:
		push_error("NavGoalQueue.add: null goal")
		return
	_goals.append(goal)


func next_goal(_request: NavGoalRequest) -> NavGoal:
	_asked += 1
	if _next >= _goals.size():
		if not looping or _goals.is_empty():
			return null
		_next = 0
	var goal := _goals[_next]
	_next += 1
	return goal


func goal_reached(_request: NavGoalRequest, _goal: NavGoal) -> void:
	_reached += 1


func goal_failed(_request: NavGoalRequest, _goal: NavGoal, state: NavLadder.State) -> void:
	_failed += 1
	_last_failure = state


func asked() -> int:
	return _asked


func reached() -> int:
	return _reached


func failed() -> int:
	return _failed


func last_failure() -> NavLadder.State:
	return _last_failure


func pending() -> int:
	return maxi(_goals.size() - _next, 0)
