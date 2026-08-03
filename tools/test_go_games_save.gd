## An unfinished Go game has to survive a save, a load and a walk out of the district. What
## is actually at risk, and therefore checked here:
##   - A board is not just its stones. Ko, the pass count and the move list all decide what
##     is legal next, and the move list is the only thing KataGo can be replayed from.
##   - A capture must come back as a capture. Restoring from `stones` alone would be right
##     by accident on a quiet board and wrong the moment a group came off.
##   - `resume_match` must adopt the saved board rather than start a fresh one, which is the
##     failure that looks like a working save right up until the player sits down.
##   - A finished game must not be stored: resuming into it would put the player back in
##     front of a result they already dismissed.
##
## Run: powershell -File tools\run_test.ps1 test_go_games_save
extends Node

const GoBoardStateScript := preload("res://scripts/city/go_board_state.gd")
const GoSessionScript := preload("res://scripts/city/go_session.gd")
const WorldGamesScript := preload("res://scripts/city/world_games.gd")

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_check_board_round_trip()
	_check_board_rejects_rubbish()
	_check_registry()
	await _check_session_resume()
	_check_finished_match_is_not_stored()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


# ---------------------------------------------------------------------------
# Board
# ---------------------------------------------------------------------------

func _check_board_round_trip() -> void:
	var board := _played_board()
	if board == null:
		return
	var back := GoBoardStateScript.from_save_dict(board.to_save_dict())
	if back == null:
		_fail("FAIL a board written by to_save_dict did not read back")
		return
	if back.size != board.size:
		_fail("FAIL size want %d got %d" % [board.size, back.size])
	if Array(back.stones) != Array(board.stones):
		_fail("FAIL the restored grid is a different position")
	if back.next_color != board.next_color:
		_fail("FAIL side to play want %d got %d" % [board.next_color, back.next_color])
	if back.phase != board.phase:
		_fail("FAIL phase want %s got %s" % [board.phase, back.phase])
	if back.consecutive_passes != board.consecutive_passes:
		_fail(
			"FAIL pass count want %d got %d"
			% [board.consecutive_passes, back.consecutive_passes]
		)
	if back.ko_x != board.ko_x or back.ko_y != board.ko_y:
		_fail("FAIL ko point want (%d,%d) got (%d,%d)"
			% [board.ko_x, board.ko_y, back.ko_x, back.ko_y])
	if back.move_list.size() != board.move_list.size():
		_fail("FAIL move list want %d entries got %d"
			% [board.move_list.size(), back.move_list.size()])
	elif not board.move_list.is_empty():
		var want: Dictionary = board.move_list[0]
		var got: Dictionary = back.move_list[0]
		if str(got.get("vertex", "")) != str(want.get("vertex", "")):
			_fail("FAIL first move want %s got %s" % [want, got])

	## The capture is the point: an empty crossing that used to hold a stone.
	if back.at(1, 1) != GoBoardState.EMPTY:
		_fail("FAIL the captured stone came back from the save")
	## And the position must still play. A restored board that refuses legal moves is a
	## board whose ko or side-to-play did not survive.
	if not back.try_play(back.next_color, "A5"):
		_fail("FAIL the restored board refused a legal move")
	print("OK a board round-trips with its captures, ko, passes and move list")


func _check_board_rejects_rubbish() -> void:
	var cases: Dictionary[String, Dictionary] = {
		"no size": {"stones": [0, 0, 0, 0]},
		"short grid": {"size": 9, "stones": [0, 1, 2]},
		"no stones": {"size": 9},
		"bad cell": {"size": 2, "stones": [0, 1, 7, 2]},
		"nobody to play": {"size": 2, "stones": [0, 0, 0, 0], "next_color": 4},
	}
	for label: String in cases.keys():
		if GoBoardStateScript.from_save_dict(cases[label]) != null:
			_fail("FAIL a board with %s was accepted" % label)
	print("OK a malformed board is refused instead of half-loaded")


# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------

func _check_registry() -> void:
	var games := WorldGamesScript.new() as WorldGames
	if games.has_go():
		_fail("FAIL a fresh registry already claims a match")
	if not games.go_snapshot().is_empty():
		_fail("FAIL an absent match handed out a snapshot")

	var board := _played_board()
	if board == null:
		return
	games.set_go({"board_n": board.size, "board": board.to_save_dict()})
	if not games.has_go():
		_fail("FAIL the match did not go in")

	## Handed-out rows are copies. A caller that kept editing the live board would otherwise
	## be rewriting the save behind the registry's back.
	var taken := games.go_snapshot()
	taken["board_n"] = 19
	if int(games.go_snapshot().get("board_n", 0)) != board.size:
		_fail("FAIL the registry handed out its own row and it was edited from outside")

	var carried := WorldGamesScript.new() as WorldGames
	carried.load_save_dict(games.to_save_dict())
	if not carried.has_go():
		_fail("FAIL the match was lost between to_save_dict and load_save_dict")

	games.clear_go()
	if games.has_go():
		_fail("FAIL a cleared match is still on the books")
	print("OK the registry hands out copies, round-trips its rows and clears")


# ---------------------------------------------------------------------------
# Session
# ---------------------------------------------------------------------------

## Resuming must adopt the saved board. Starting a fresh one instead is the bug this test
## exists for: everything else about the session would look perfectly healthy.
func _check_session_resume() -> void:
	var board := _played_board()
	if board == null:
		return
	var row := {
		"board_n": board.size,
		## Both human, so no KataGo is acquired: this checks the handover, not the engine.
		"black_human": true,
		"white_human": true,
		"black_rank": "5k",
		"white_rank": "3k",
		"board": board.to_save_dict(),
	}
	var session := GoSessionScript.new() as GoSession
	session.name = "ResumedSession"
	add_child(session)
	await get_tree().process_frame
	if not session.resume_match(row):
		_fail("FAIL resume_match refused a match it had just written")
		session.queue_free()
		return
	if session.board == null:
		_fail("FAIL the resumed session has no board")
		session.queue_free()
		return
	if session.board.move_list.size() != board.move_list.size():
		_fail(
			"FAIL the resumed session started a fresh board (%d moves, want %d)"
			% [session.board.move_list.size(), board.move_list.size()]
		)
	if Array(session.board.stones) != Array(board.stones):
		_fail("FAIL the resumed session is looking at a different position")
	if session.board.next_color != board.next_color:
		_fail("FAIL the resumed session hands the move to the wrong colour")
	if session.white_human != true or session.black_human != true:
		_fail("FAIL the resumed session lost who is sitting at the table")
	if session.white_rank != "3k":
		_fail("FAIL the resumed session lost White's rank: %s" % session.white_rank)
	if not session.player_to_move():
		_fail("FAIL a resumed human turn does not accept input")

	## And it is a live game, not a museum piece.
	if not session.try_player_vertex("A5"):
		_fail("FAIL the resumed session would not take the next move")
	elif session.board.move_list.size() != board.move_list.size() + 1:
		_fail("FAIL the move landed somewhere other than the resumed board")

	var wrong_size := row.duplicate(true)
	wrong_size["board_n"] = 19
	if session.resume_match(wrong_size):
		_fail("FAIL a row whose board_n disagrees with its board was resumed anyway")
	session.queue_free()
	print("OK a saved match resumes onto its own board and keeps playing")


## A scored game is the end panel's business. Storing it would resume the player into a
## result they already closed.
func _check_finished_match_is_not_stored() -> void:
	var session := GoSessionScript.new() as GoSession
	session.name = "FinishedSession"
	add_child(session)
	var board := GoBoardStateScript.new() as GoBoardState
	board.setup(9)
	if not session.resume_match(
		{"board_n": 9, "black_human": true, "white_human": true, "board": board.to_save_dict()}
	):
		_fail("FAIL could not set up the match that is about to end")
		session.queue_free()
		return
	if session.to_save_dict().is_empty():
		_fail("FAIL a game in progress refused to be saved")
	if not session.try_player_pass() or not session.try_player_pass():
		_fail("FAIL the two passes that end a game did not go through")
	if session.board.phase != &"scoring":
		_fail("FAIL two passes left the game running")
	if not session.to_save_dict().is_empty():
		_fail("FAIL a finished game was written into the save")

	var reopened := GoSessionScript.new() as GoSession
	reopened.name = "ReopenSession"
	add_child(reopened)
	if reopened.resume_match({"board_n": 9, "board": session.board.to_save_dict()}):
		_fail("FAIL resume_match reopened a game that was already scored")
	reopened.queue_free()
	session.queue_free()
	print("OK a finished game is neither saved nor resumable")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## A 5x5 with a capture on it, so the save is tested against a position that stones alone
## cannot describe.
func _played_board() -> GoBoardState:
	var board := GoBoardStateScript.new() as GoBoardState
	board.setup(5)
	var moves: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(1, 1),
		Vector2i(0, 1),
		Vector2i(3, 3),
		Vector2i(2, 1),
		Vector2i(3, 2),
		Vector2i(1, 2),
	]
	for m in moves:
		if not board.try_play_xy(board.next_color, m.x, m.y):
			_fail("FAIL the fixture board rejected %s" % str(m))
			return null
	if board.at(1, 1) != GoBoardState.EMPTY:
		_fail("FAIL the fixture was meant to capture at (1,1)")
		return null
	return board
