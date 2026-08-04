## One monster-chess game: the board, who is human on each side, and the AI that answers.
##
## The counterpart of `GoSession`, including the off-main-thread handshake — a search on the
## main thread would freeze the city for as long as it thought. `WorkerThreadPool.add_task`
## plus a `Mutex` around a result dict and `await get_tree().process_frame` until it lands is
## the pattern already proven at the Go table.
##
## The search runs on a `clone()` of the board on purpose. A worker thread walking the live
## board would leave the arena rendering positions that only exist inside the search.
class_name ChessSession
extends Node

const ChessBoardStateScript := preload("res://scripts/city/chess_board_state.gd")
const ChessSearchScript := preload("res://scripts/city/chess_search.gd")

## The AI has started or stopped thinking. The arena leans on this for the status line.
signal ai_thinking(on: bool)
signal session_ended(reason: String)
## The game is over. `reason` is ChessBoardState's `end_reason`.
signal match_over(reason: String)
## Depth and score the AI's last move came out of, for the status panel. Free — the search
## already had them.
signal search_reported(depth: int, score: int, nodes: int, ms: int)

## Thinking time per level. Generous because a move already costs several seconds of monster
## walking, and the search runs off-thread while that happens.
## Measured against what the animation hides in tools/test_chess_search.gd, not guessed: a
## piece crossing two squares walks for about 2.8 s, and the search runs during that walk.
const LEVELS: Array[StringName] = [&"casual", &"club", &"master"]
const LEVEL_BUDGET_MS: Array[int] = [250, 900, 2000]

var board: ChessBoardState = null
var white_human: bool = true
var black_human: bool = false
var white_level: StringName = &"club"
var black_level: StringName = &"club"

## True while a search is in flight. No move may be accepted from either side meanwhile.
var _busy: bool = false
## Set while a puppet is walking. The AI may think during that walk — it is exactly the time
## the plan spends on search — but its move is not put on the board until the court is idle,
## or two moves would animate on top of each other.
var _hold: bool = false
## A searched move waiting for the hold to lift. Always for the position as it stands.
var _ready_move: int = 0
## Bumped whenever the session is restarted or torn down, so an in-flight search that
## returns late knows its answer belongs to a game that no longer exists.
var _epoch: int = 0


func begin_match(
	p_white_human: bool,
	p_white_level: StringName,
	p_black_human: bool,
	p_black_level: StringName
) -> bool:
	var fresh: ChessBoardState = ChessBoardStateScript.new() as ChessBoardState
	fresh.setup()
	return _open(fresh, p_white_human, p_white_level, p_black_human, p_black_level)


## Sit back down at a saved game. False when the row is not something this build can play,
## in which case the caller should offer a fresh board instead.
func resume_match(data: Dictionary) -> bool:
	var raw: Variant = data.get("board", null)
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("ChessSession.resume_match: the saved match carries no board")
		return false
	var restored: ChessBoardState = ChessBoardStateScript.from_save_dict(raw as Dictionary)
	if restored == null:
		return false
	if restored.phase != &"playing":
		push_error(
			"ChessSession.resume_match: that game already ended (%s)" % restored.end_reason
		)
		return false
	return _open(
		restored,
		bool(data.get("white_human", true)),
		_normalise_level(str(data.get("white_level", "club"))),
		bool(data.get("black_human", false)),
		_normalise_level(str(data.get("black_level", "club")))
	)


func _open(
	p_board: ChessBoardState,
	p_white_human: bool,
	p_white_level: StringName,
	p_black_human: bool,
	p_black_level: StringName
) -> bool:
	board = p_board
	white_human = p_white_human
	black_human = p_black_human
	white_level = _normalise_level(String(p_white_level))
	black_level = _normalise_level(String(p_black_level))
	_busy = false
	_hold = false
	_ready_move = 0
	_epoch += 1
	return true


func end_session(reason: String = "leave") -> void:
	_epoch += 1
	_busy = false
	_hold = false
	_ready_move = 0
	## "restart" is an internal handoff — announcing it would flip the arena's UI back to
	## setup in the middle of starting the next game.
	if reason != "restart":
		session_ended.emit(reason)


func is_thinking() -> bool:
	return _busy


func colour_is_human(colour: int) -> bool:
	if colour == ChessBoardStateScript.WHITE:
		return white_human
	if colour == ChessBoardStateScript.BLACK:
		return black_human
	push_error("ChessSession.colour_is_human: %d is not a colour" % colour)
	return false


func colour_level(colour: int) -> StringName:
	return white_level if colour == ChessBoardStateScript.WHITE else black_level


func is_ai_only() -> bool:
	return not white_human and not black_human


## True when the board is waiting on a tap from the player rather than on the search.
func player_to_move() -> bool:
	if board == null or board.phase != &"playing" or _busy:
		return false
	return colour_is_human(board.side_to_move)


## Play the player's move. False when it is not their turn or the move is not legal, which
## is also the answer to "did that tap mean anything?".
func try_player_move(from_sq: Vector2i, to_sq: Vector2i, promotion: int = 0) -> bool:
	if not player_to_move():
		return false
	var promo := promotion if promotion != 0 else ChessBoardStateScript.QUEEN
	if not board.try_move(from_sq, to_sq, promo):
		return false
	_after_move()
	return true


func try_player_resign() -> bool:
	if board == null or board.phase != &"playing":
		return false
	if not colour_is_human(board.side_to_move):
		return false
	if not board.resign(board.side_to_move):
		return false
	match_over.emit(board.end_reason)
	return true


## Abort a game nobody is playing (AI versus AI). Cancels the search in flight.
func stop_match() -> bool:
	if board == null or board.phase != &"playing":
		return false
	_epoch += 1
	_busy = false
	_ready_move = 0
	ai_thinking.emit(false)
	if not board.stop_play():
		return false
	match_over.emit(board.end_reason)
	return true


## Stop or resume *playing* AI moves, without stopping it thinking about them.
##
## The arena holds the session for as long as a puppet is walking. The search still starts
## the moment a move is committed, so it runs while the previous piece crosses the board and
## its answer is usually waiting by the time the walk ends — which is the whole reason a
## GDScript search is fast enough here.
func set_hold(on: bool) -> void:
	if _hold == on:
		return
	_hold = on
	if _hold:
		return
	if _ready_move != 0:
		_play_ready()
	else:
		kick_ai_if_needed()


## Ask the AI to think, if it is its turn and it is not already thinking. Safe to call while
## held: the search runs, and the move waits.
func kick_ai_if_needed() -> void:
	if board == null or board.phase != &"playing" or _busy or _ready_move != 0:
		return
	if colour_is_human(board.side_to_move):
		return
	_search_and_play()


## True when a searched move is sitting here waiting for the court to go idle.
func has_ready_move() -> bool:
	return _ready_move != 0


## The game as a `WorldGames` row, or {} when there is nothing to come back to. Only a game
## still in progress qualifies: a finished one belongs to the result panel, and resuming into
## it would put the player in front of a verdict they already read.
func to_save_dict() -> Dictionary:
	if board == null or board.phase != &"playing":
		return {}
	return {
		"white_human": white_human,
		"black_human": black_human,
		"white_level": String(white_level),
		"black_level": String(black_level),
		"board": board.to_save_dict(),
	}


static func level_budget_ms(level: StringName) -> int:
	var idx := LEVELS.find(level)
	if idx < 0:
		push_error("ChessSession.level_budget_ms: '%s' is not a level" % level)
		return LEVEL_BUDGET_MS[0]
	return LEVEL_BUDGET_MS[idx]


static func next_level(level: StringName, step: int) -> StringName:
	var idx := LEVELS.find(level)
	if idx < 0:
		push_error("ChessSession.next_level: '%s' is not a level" % level)
		return LEVELS[0]
	return LEVELS[clampi(idx + step, 0, LEVELS.size() - 1)]


static func _normalise_level(raw: String) -> StringName:
	var wanted := StringName(raw)
	if LEVELS.has(wanted):
		return wanted
	push_error("ChessSession: '%s' is not a level, using %s" % [raw, LEVELS[1]])
	return LEVELS[1]


func _search_and_play() -> void:
	var epoch := _epoch
	_busy = true
	ai_thinking.emit(true)
	var colour := board.side_to_move
	var budget := level_budget_ms(colour_level(colour))
	var reply: Dictionary = await _search_off_main(board.clone(), budget)
	if epoch != _epoch or board == null:
		return
	_busy = false
	ai_thinking.emit(false)
	if board.phase != &"playing":
		return
	var move := int(reply.get("move", 0))
	if move == 0:
		## No legal move means the board is already mate or stalemate, and the terminal test
		## inside the last move should have caught it. If it did not, that is a rules bug
		## rather than something to shrug off.
		push_error("ChessSession: the search found no move in %s" % board.to_fen())
		return
	search_reported.emit(
		int(reply.get("depth", 0)),
		int(reply.get("score", 0)),
		int(reply.get("nodes", 0)),
		int(reply.get("ms", 0))
	)
	_ready_move = move
	if not _hold:
		_play_ready()


## Put the move the search settled on onto the board. Separate from finding it, because the
## two happen at different times whenever the AI thought during someone else's walk.
func _play_ready() -> void:
	var move := _ready_move
	_ready_move = 0
	if move == 0 or board == null or board.phase != &"playing":
		return
	if not board.play_move(move):
		push_error(
			"ChessSession: the search returned %s, which the board refused"
			% ChessBoardStateScript.move_name(move)
		)
		return
	_after_move()


## Run the search on a worker and hand the answer back on the main thread. Identical
## handshake to `GoSession._genmove_off_main`, and for the same reason: a `Thread` per move
## would spend most of its life being created.
func _search_off_main(state: ChessBoardState, budget_ms: int) -> Dictionary:
	var mutex := Mutex.new()
	var slot := {"done": false, "reply": {}}
	var task_id := WorkerThreadPool.add_task(
		func() -> void:
			var search: RefCounted = ChessSearchScript.new()
			var out: Dictionary = search.call("best_move", state, budget_ms)
			mutex.lock()
			slot["reply"] = out
			slot["done"] = true
			mutex.unlock()
	)
	while true:
		mutex.lock()
		var done := bool(slot["done"])
		mutex.unlock()
		if done:
			break
		if not is_inside_tree():
			## The district streamed out from under us. Wait for the worker rather than
			## leaking it, then throw the answer away.
			WorkerThreadPool.wait_for_task_completion(task_id)
			return {"move": 0}
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task_id)
	mutex.lock()
	var reply: Dictionary = slot["reply"]
	mutex.unlock()
	return reply


## Announce the end of the game if that move was the last one. The arena drives the AI's
## reply itself, once the puppet has finished walking.
func _after_move() -> void:
	if board == null:
		return
	if board.phase != &"playing":
		match_over.emit(board.end_reason)
