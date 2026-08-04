## Conformance test for ChessBoardState's move generator, plus the game-ending rules.
##
## Perft is the whole point of this file. It counts leaf nodes of the move tree to a given
## depth and compares against numbers the chess world has agreed on for decades: if a
## generator matches them it is correct, and if it does not, every later symptom — a monster
## refusing a legal square, a king walking into check, a rook teleporting — will look like a
## puppet or UI bug instead of what it is. The positions are the standard set, chosen so
## that between them they exercise castling through attacked squares, en-passant pins,
## promotion with capture, and double check.
##
## Run: powershell -File tools\run_test.ps1 test_chess_rules -TimeoutSec 300
extends Node

const ChessBoardStateScript := preload("res://scripts/city/chess_board_state.gd")

## fen, then the expected leaf count at depths 1..n.
const CASES: Array = [
	{
		"name": "start position",
		"fen": ChessBoardState.START_FEN,
		"counts": [20, 400, 8902, 197281],
	},
	{
		"name": "Kiwipete (castling, checks, pins)",
		"fen": "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
		"counts": [48, 2039, 97862],
	},
	{
		"name": "position 3 (en passant, rook endgame)",
		"fen": "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
		"counts": [14, 191, 2812, 43238],
	},
	{
		"name": "position 4 (promotion with capture)",
		"fen": "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
		"counts": [6, 264, 9467],
	},
	{
		"name": "position 5 (castling rights lost by capture)",
		"fen": "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
		"counts": [44, 1486, 62379],
	},
]

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_check_perft()
	_check_square_naming()
	_check_fen_roundtrip()
	_check_loud_generator()
	_check_castling_moves_the_rook()
	_check_en_passant_removes_the_pawn()
	_check_promotion_choice()
	_check_checkmate()
	_check_stalemate()
	_check_fifty_move()
	_check_threefold()
	_check_save_resume()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _check_perft() -> void:
	for entry: Variant in CASES:
		var case: Dictionary = entry
		var board: ChessBoardState = ChessBoardStateScript.new() as ChessBoardState
		if not board.load_fen(str(case["fen"])):
			_fail("FAIL %s did not parse" % case["name"])
			continue
		var counts: Array = case["counts"]
		for i in range(counts.size()):
			var depth := i + 1
			var want := int(counts[i])
			var t0 := Time.get_ticks_msec()
			var got := board.perft(depth)
			var ms := Time.get_ticks_msec() - t0
			if got != want:
				_fail(
					"FAIL %s perft(%d) = %d, expected %d"
					% [case["name"], depth, got, want]
				)
				return
			print("OK %s perft(%d) = %d  [%d ms]" % [case["name"], depth, got, ms])
			## An unmake that does not exactly reverse its make shows up as a position that
			## drifted, which every later depth would then measure from the wrong board.
			if board.to_fen() != str(case["fen"]):
				_fail(
					"FAIL %s drifted to %s after perft(%d)"
					% [case["name"], board.to_fen(), depth]
				)
				return


func _check_square_naming() -> void:
	if ChessBoardState.square_name(0) != "a1":
		_fail("FAIL square 0 is %s, not a1" % ChessBoardState.square_name(0))
	if ChessBoardState.square_name(63) != "h8":
		_fail("FAIL square 63 is %s, not h8" % ChessBoardState.square_name(63))
	if ChessBoardState.square_from_name("e4") != 28:
		_fail("FAIL e4 is %d, not 28" % ChessBoardState.square_from_name("e4"))
	if ChessBoardState.square_from_name("j9") != -1:
		_fail("FAIL j9 parsed as a square")


func _check_fen_roundtrip() -> void:
	for entry: Variant in CASES:
		var case: Dictionary = entry
		var board: ChessBoardState = ChessBoardStateScript.new() as ChessBoardState
		if not board.load_fen(str(case["fen"])):
			_fail("FAIL %s did not parse" % case["name"])
			continue
		if board.to_fen() != str(case["fen"]):
			_fail("FAIL %s round-tripped to %s" % [case["name"], board.to_fen()])


## The quiescence generator is a shortcut past the self-check filter, so it has to agree
## exactly with filtering the full legal list. A shortcut that quietly keeps one illegal
## capture would have the search counting material it cannot actually win.
func _check_loud_generator() -> void:
	for entry: Variant in CASES:
		var case: Dictionary = entry
		var board: ChessBoardState = ChessBoardStateScript.new() as ChessBoardState
		if not board.load_fen(str(case["fen"])):
			_fail("FAIL %s did not parse" % case["name"])
			continue
		## One ply deep as well as at the root: en-passant and promotion captures only
		## appear once a pawn has moved.
		var positions: Array[int] = [0]
		positions.append_array(board.generate_legal_moves())
		for move: int in positions:
			if move != 0:
				board.make_move(move)
			var want := PackedInt32Array()
			for m: int in board.generate_legal_moves():
				if board.is_loud(m):
					want.append(m)
			var got := board.generate_legal_captures()
			if got != want:
				_fail(
					"FAIL %s after %s: %d loud moves, expected %d"
					% [
						case["name"],
						ChessBoardState.move_name(move),
						got.size(),
						want.size(),
					]
				)
				if move != 0:
					board.unmake_move()
				return
			if move != 0:
				board.unmake_move()
	print("OK the quiescence generator matches the filtered legal list")


## The rook has to come with the king, and both rights have to go. A castle that only moves
## the king is the kind of bug perft catches at depth 3 and a player catches immediately.
func _check_castling_moves_the_rook() -> void:
	var board := _board("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	if not board.try_move(Vector2i(4, 0), Vector2i(6, 0)):
		_fail("FAIL white cannot castle short from a clear back rank")
		return
	if board.at(6, 0) != (ChessBoardState.KING | ChessBoardState.WHITE):
		_fail("FAIL the king is not on g1 after castling short")
	if board.at(5, 0) != (ChessBoardState.ROOK | ChessBoardState.WHITE):
		_fail("FAIL the rook did not come to f1")
	if board.at(7, 0) != ChessBoardState.EMPTY:
		_fail("FAIL the rook is still on h1")
	if board.castling_rights & (ChessBoardState.CASTLE_WK | ChessBoardState.CASTLE_WQ):
		_fail("FAIL white kept castling rights after castling")

	var long := _board("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1")
	if not long.try_move(Vector2i(4, 7), Vector2i(2, 7)):
		_fail("FAIL black cannot castle long from a clear back rank")
		return
	if long.at(2, 7) != (ChessBoardState.KING | ChessBoardState.BLACK):
		_fail("FAIL the black king is not on c8")
	if long.at(3, 7) != (ChessBoardState.ROOK | ChessBoardState.BLACK):
		_fail("FAIL the black rook did not come to d8")

	## Through check: f1 is covered, so short castling is not on offer.
	var blocked := _board("4k3/8/8/8/8/8/5r2/R3K2R w KQ - 0 1")
	if blocked.legal_moves_from(4, 0).has(
		ChessBoardState.pack_move(4, 6, 0, ChessBoardState.FLAG_CASTLE)
	):
		_fail("FAIL white castled short through an attacked f1")


func _check_en_passant_removes_the_pawn() -> void:
	var board := _board("4k3/8/8/8/8/8/4P3/4K3 w - - 0 1")
	if not board.try_move(Vector2i(4, 1), Vector2i(4, 3)):
		_fail("FAIL the double push e2e4 was refused")
		return
	if board.ep_square != ChessBoardState.square_from_name("e3"):
		_fail("FAIL e2e4 set the en-passant square to %d" % board.ep_square)

	var take := _board("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1")
	if not take.try_move(Vector2i(4, 4), Vector2i(3, 5)):
		_fail("FAIL the en-passant capture exd6 was refused")
		return
	if take.at(3, 4) != ChessBoardState.EMPTY:
		_fail("FAIL the captured pawn is still on d5")
	if take.at(3, 5) != (ChessBoardState.PAWN | ChessBoardState.WHITE):
		_fail("FAIL the capturing pawn is not on d6")


func _check_promotion_choice() -> void:
	var board := _board("7k/4P3/8/8/8/8/8/4K3 w - - 0 1")
	if board.legal_moves_from(4, 6).size() != 4:
		_fail(
			"FAIL a pawn on e7 offers %d promotions, expected 4"
			% board.legal_moves_from(4, 6).size()
		)
	if not board.try_move(Vector2i(4, 6), Vector2i(4, 7), ChessBoardState.KNIGHT):
		_fail("FAIL promoting to a knight was refused")
		return
	if board.at(4, 7) != (ChessBoardState.KNIGHT | ChessBoardState.WHITE):
		_fail("FAIL e8 holds %d, not a white knight" % board.at(4, 7))


func _check_checkmate() -> void:
	## Back-rank mate in one: Ra8#.
	var board := _board("6k1/5ppp/8/8/8/8/8/R6K w - - 0 1")
	if not board.try_move(Vector2i(0, 0), Vector2i(0, 7)):
		_fail("FAIL Ra1a8 was refused")
		return
	if not board.is_over():
		_fail("FAIL Ra8 is mate and the board is still playing")
		return
	if board.end_reason != "mate_white_wins":
		_fail("FAIL Ra8 ended as '%s'" % board.end_reason)


func _check_stalemate() -> void:
	## Black to move, not in check, and every square its king can reach is covered.
	var board := _board("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
	if not board.generate_legal_moves().is_empty():
		_fail(
			"FAIL black has %d moves in a stalemate"
			% board.generate_legal_moves().size()
		)
		return
	if board.in_check(ChessBoardState.BLACK):
		_fail("FAIL the stalemate position has black in check")
	## Reaching it by a move is what actually latches the result.
	var play := _board("7k/8/5QK1/8/8/8/8/8 w - - 0 1")
	if not play.try_move(Vector2i(5, 5), Vector2i(5, 6)):
		_fail("FAIL Qf6f7 was refused")
		return
	if play.end_reason != "stalemate":
		_fail("FAIL Qf7 ended as '%s', expected stalemate" % play.end_reason)


func _check_fifty_move() -> void:
	## One ply short of the draw, so a single quiet move has to trip it.
	var board := _board("4k3/8/8/8/8/8/8/R3K3 w - - 99 60")
	if not board.try_move(Vector2i(0, 0), Vector2i(1, 0)):
		_fail("FAIL Ra1b1 was refused")
		return
	if board.end_reason != "fifty_move":
		_fail("FAIL the hundredth quiet ply ended as '%s'" % board.end_reason)


func _check_threefold() -> void:
	var board := _board("4k3/8/8/8/8/8/8/R3K2R w - - 0 1")
	## Rooks shuffle a1-b1-a1 and h8-g8-h8 twice: the start position comes up three times.
	var shuffle: Array[Array] = [
		[Vector2i(0, 0), Vector2i(1, 0)],
		[Vector2i(4, 7), Vector2i(3, 7)],
		[Vector2i(1, 0), Vector2i(0, 0)],
		[Vector2i(3, 7), Vector2i(4, 7)],
		[Vector2i(0, 0), Vector2i(1, 0)],
		[Vector2i(4, 7), Vector2i(3, 7)],
		[Vector2i(1, 0), Vector2i(0, 0)],
		[Vector2i(3, 7), Vector2i(4, 7)],
	]
	for step in shuffle:
		if board.is_over():
			break
		if not board.try_move(step[0], step[1]):
			_fail("FAIL %s%s was refused during the shuffle" % [step[0], step[1]])
			return
	if board.end_reason != "threefold":
		_fail("FAIL the third repetition ended as '%s'" % board.end_reason)


## A resumed game has to remember the positions it already stood in, or a draw it was one
## move away from silently disappears. That is what makes the save a move list, not a FEN.
func _check_save_resume() -> void:
	var board := _board("4k3/8/8/8/8/8/8/R3K2R w - - 0 1")
	var opening: Array[Array] = [
		[Vector2i(0, 0), Vector2i(1, 0)],
		[Vector2i(4, 7), Vector2i(3, 7)],
		[Vector2i(1, 0), Vector2i(0, 0)],
		[Vector2i(3, 7), Vector2i(4, 7)],
		[Vector2i(0, 0), Vector2i(1, 0)],
		[Vector2i(4, 7), Vector2i(3, 7)],
	]
	for step in opening:
		if not board.try_move(step[0], step[1]):
			_fail("FAIL %s%s was refused before saving" % [step[0], step[1]])
			return
	var row := board.to_save_dict()
	var resumed := ChessBoardStateScript.from_save_dict(row) as ChessBoardState
	if resumed == null:
		_fail("FAIL the saved game did not resume")
		return
	if resumed.to_fen() != board.to_fen():
		_fail("FAIL the resumed board is %s, not %s" % [resumed.to_fen(), board.to_fen()])
		return
	if resumed.move_list != board.move_list:
		_fail("FAIL the resumed game lost its move list")
		return
	## Two more plies bring the start position up for the third time, on the resumed board.
	if not resumed.try_move(Vector2i(1, 0), Vector2i(0, 0)):
		_fail("FAIL Rb1a1 was refused after resuming")
		return
	if not resumed.try_move(Vector2i(3, 7), Vector2i(4, 7)):
		_fail("FAIL Kd8e8 was refused after resuming")
		return
	if resumed.end_reason != "threefold":
		_fail(
			"FAIL the resumed game ended as '%s' — the repetition history was lost"
			% resumed.end_reason
		)


func _board(fen: String) -> ChessBoardState:
	var board: ChessBoardState = ChessBoardStateScript.new() as ChessBoardState
	if not board.load_fen(fen):
		_fail("FAIL the test position %s did not parse" % fen)
	return board
