## What the chess opponent is worth, and how deep it gets for the time it is given.
##
## Two jobs. The first is correctness the way a player notices it: take a free queen, find a
## mate in one, do not walk into a mate in one. The second is measurement — this file prints
## the depth each level's budget actually buys, which is the only way to know whether the
## GDScript search is good enough or whether the seam behind `best_move` needs a native
## engine on the other side of it.
##
## Run: powershell -File tools\run_test.ps1 test_chess_search -TimeoutSec 300 -KeepLog
extends Node

const ChessBoardStateScript := preload("res://scripts/city/chess_board_state.gd")
const ChessSearchScript := preload("res://scripts/city/chess_search.gd")
const ChessSessionScript := preload("res://scripts/city/chess_session.gd")

## Positions with one move a player would call obvious, and what it is.
const TACTICS: Array = [
	{
		"name": "mate in one (back rank)",
		"fen": "6k1/5ppp/8/8/8/8/8/R6K w - - 0 1",
		"want": "a1a8",
	},
	{
		"name": "take the free queen",
		"fen": "4k3/8/8/3q4/4B3/8/8/4K3 w - - 0 1",
		"want": "e4d5",
	},
	{
		## Checked down the h-file with g7 covered by the pawn: Kg8 is the only legal move,
		## so anything else is a generator or a filter that disagrees with the search.
		"name": "the only legal move",
		"fen": "7k/8/5P2/8/8/8/8/K6R b - - 0 1",
		"want": "h8g8",
	},
	{
		## The black king is two squares from the pawn, so anything but promoting now loses
		## it. A position where promotion merely happens to be best would not test anything:
		## with a spare tempo the engine is right to keep the pawn and improve its king.
		"name": "promote or lose the pawn",
		"fen": "8/P7/8/k7/8/8/8/K7 w - - 0 1",
		"want": "a7a8q",
	},
]

## Positions the depth report is taken from: an opening with everything on, a middlegame with
## the board half empty, and an endgame where depth is cheap and matters most.
const DEPTH_CASES: Array = [
	{"name": "start position", "fen": ChessBoardState.START_FEN},
	{
		"name": "middlegame (Kiwipete)",
		"fen": "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
	},
	{"name": "rook endgame", "fen": "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"},
]

## What the choreography hides. The arena starts the search the moment a move is committed,
## so the AI thinks while the piece that just moved is still walking: two squares is 8 m at
## ChessPieceActor.WALK_SPEED plus two turns, and a budget inside that is a budget the player
## never waits on. A one-square king shuffle is shorter, so the hardest level can still leave
## a beat of thinking visible in an endgame.
const HIDDEN_MS := 2350

## Below this the opponent is a random-mover with extra steps: it sees a capture and the
## recapture, and nothing else.
const MIN_CLUB_DEPTH := 3

## A rook up with a bare king to hunt: a position no engine should agree to halve.
const WINNING_FEN := "7k/8/8/8/8/8/8/R6K w - - 0 1"
## Four reversible plies that put that position back exactly where it started. Afterwards every
## square the rook and the black king stood on is inside the repetition window, so any of them
## the search revisits is a draw it chose.
const SHUFFLE: Array[String] = ["a1a2", "h8g8", "a2a1", "g8h8"]

## How much of an engine-against-engine game to play out, and how long each move may think.
## Short thinking on purpose: a weaker search is likelier to shuffle, which is the failure this
## is watching for. The cap stops well short of the bare-king endgames where a draw becomes an
## honest result rather than a bug.
const GAME_PLIES := 120
const GAME_BUDGET_MS := 150

## How much of two separate games to compare when checking they are not the same game. Long
## enough that two runs would have to agree by luck at every single ply to look identical.
const VARIETY_PLIES := 24

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_check_tactics()
	_check_budget_is_respected()
	_check_winner_declines_a_draw()
	_check_ai_game_avoids_threefold()
	_check_games_differ()
	_check_seam_is_one_file()
	_report_depth()
	_check_levels_fit_the_animation()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


## Left on the default spread on purpose. These are the positions where one move is obviously
## right, so they are also the check that playing varied moves never costs the obvious one.
func _check_tactics() -> void:
	for entry: Variant in TACTICS:
		var case: Dictionary = entry
		var board: ChessBoardState = ChessBoardStateScript.new() as ChessBoardState
		if not board.load_fen(str(case["fen"])):
			_fail("FAIL %s did not parse" % case["name"])
			continue
		var search: ChessSearch = ChessSearchScript.new() as ChessSearch
		var reply := search.best_move(board, 900)
		var got := ChessBoardStateScript.move_name(int(reply["move"]))
		if got != str(case["want"]):
			_fail("FAIL %s: played %s, wanted %s" % [case["name"], got, case["want"]])
			continue
		print(
			"OK %s: %s at depth %d (%d nodes, %d ms)"
			% [case["name"], got, int(reply["depth"]), int(reply["nodes"]), int(reply["ms"])]
		)


## A search that overruns its budget freezes a worker thread past the animation that was
## hiding it, so the deadline is a promise rather than a hint.
func _check_budget_is_respected() -> void:
	var board: ChessBoardState = ChessBoardStateScript.new() as ChessBoardState
	board.setup()
	for budget: int in [50, 250, 900]:
		var search: ChessSearch = ChessSearchScript.new() as ChessSearch
		var reply := search.best_move(board, budget)
		var spent := int(reply["ms"])
		## One clock check every CLOCK_EVERY nodes plus the ply that was abandoned, so a
		## little overshoot is expected; a multiple of the budget is not.
		if spent > budget + 400:
			_fail("FAIL a %d ms budget took %d ms" % [budget, spent])
			continue
		if int(reply["move"]) == 0:
			_fail("FAIL no move came back from a %d ms search" % budget)
			continue
		print("OK %d ms budget spent %d ms, reached depth %d" % [budget, spent, int(reply["depth"])])
	## The board must come back exactly as it was handed over, or a search on the live board
	## would leave phantom pieces behind.
	if board.to_fen() != ChessBoardState.START_FEN:
		_fail("FAIL the search left the board as %s" % board.to_fen())


## A search that scores a draw as dead level is indifferent between repeating and playing on,
## and a rook up it should be anything but. This hands it a position it has already visited
## twice and checks that its move goes somewhere new — whichever move that turns out to be,
## which is the invariant rather than one hand-picked reply.
func _check_winner_declines_a_draw() -> void:
	var board: ChessBoardState = ChessBoardStateScript.new() as ChessBoardState
	if not board.load_fen(WINNING_FEN):
		_fail("FAIL the winning endgame did not parse")
		return
	for step: String in SHUFFLE:
		var from := ChessBoardStateScript.square_from_name(step.substr(0, 2))
		var to := ChessBoardStateScript.square_from_name(step.substr(2, 2))
		if not board.try_move(
			ChessBoardStateScript.vec_of(from), ChessBoardStateScript.vec_of(to)
		):
			_fail("FAIL the shuffle move %s was refused" % step)
			return
	if board.to_fen() != WINNING_FEN.replace(" 0 1", " 4 3"):
		_fail("FAIL the shuffle ended at %s, not back where it started" % board.to_fen())
		return

	var search: ChessSearch = ChessSearchScript.new() as ChessSearch
	var reply := search.best_move(board.clone(), 900)
	var move := int(reply["move"])
	if move == 0:
		_fail("FAIL no move came back from the winning endgame")
		return
	## Played on a copy, because what is being judged is where the move lands rather than the
	## rest of the game from there.
	var after := board.clone()
	if not after.play_move(move):
		_fail("FAIL %s was refused" % ChessBoardStateScript.move_name(move))
		return
	if after.repetition_count() > 1:
		_fail(
			"FAIL a rook up, the search played %s back into a position that already stood %d times"
			% [ChessBoardStateScript.move_name(move), after.repetition_count()]
		)
		return
	print(
		"OK a rook up, the search played %s rather than repeat (score %d)"
		% [ChessBoardStateScript.move_name(move), int(reply["score"])]
	)


## The regression this whole mechanism exists for: two copies of the engine playing each other
## used to draw by repetition, because a deterministic search meeting a position it has already
## judged picks the same move again, forever. Playing it out is the only test that would have
## caught it.
func _check_ai_game_avoids_threefold() -> void:
	var board := _play_game(GAME_PLIES, GAME_BUDGET_MS)
	if board == null:
		return
	if board.end_reason == "threefold":
		_fail(
			"FAIL engine against engine repeated into a draw after %d plies"
			% board.move_list.size()
		)
		return
	print(
		"OK %d plies of engine against engine, no threefold (%s)"
		% [board.move_list.size(), board.end_reason if board.is_over() else "still playing"]
	)


## Watching the house play itself is only worth doing if it is not the same match every time.
## Two games rather than one position, because what the player notices is the game diverging
## somewhere, not any particular move being unpredictable.
func _check_games_differ() -> void:
	var first := _play_game(VARIETY_PLIES, GAME_BUDGET_MS)
	if first == null:
		return
	var second := _play_game(VARIETY_PLIES, GAME_BUDGET_MS)
	if second == null:
		return
	var one := _moves_of(first)
	var two := _moves_of(second)
	if one == two:
		_fail("FAIL two engine games ran identical for %d plies: %s" % [VARIETY_PLIES, one])
		return
	print("OK two engine games diverged\n    %s\n    %s" % [one, two])


## Engine against engine from the start position, stopping at `plies` or at a result. Null when
## a move was refused, which would mean the search and the rules disagree about legality.
func _play_game(plies: int, budget_ms: int) -> ChessBoardState:
	var board: ChessBoardState = ChessBoardStateScript.new() as ChessBoardState
	board.setup()
	while not board.is_over() and board.move_list.size() < plies:
		var search: ChessSearch = ChessSearchScript.new() as ChessSearch
		var reply := search.best_move(board.clone(), budget_ms)
		var move := int(reply["move"])
		if move == 0:
			_fail("FAIL no move at ply %d of %s" % [board.move_list.size(), board.to_fen()])
			return null
		if not board.play_move(move):
			_fail(
				"FAIL ply %d: %s was refused"
				% [board.move_list.size(), ChessBoardStateScript.move_name(move)]
			)
			return null
	return board


func _moves_of(board: ChessBoardState) -> String:
	var out := PackedStringArray()
	for i in range(board.move_list.size()):
		out.append(ChessBoardStateScript.move_name(board.move_list[i]))
	return " ".join(out)


## Swapping this engine for a native one is a single-file change only while exactly one file
## knows the engine exists and asks it exactly one thing. Both halves are checked against the
## source, because the day someone reaches for a second entry point is the day that stops
## being true and nothing else would notice.
func _check_seam_is_one_file() -> void:
	var dir := DirAccess.open("res://scripts")
	if dir == null:
		_fail("FAIL cannot read res://scripts to check the search seam")
		return
	var users := PackedStringArray()
	_collect_users(dir, "res://scripts", users)
	if users.size() != 1 or users[0] != "res://scripts/city/chess_session.gd":
		_fail("FAIL chess_search.gd is loaded by %s" % ", ".join(users))
		return
	var text := FileAccess.get_file_as_string("res://scripts/city/chess_session.gd")
	for line: String in text.split("\n"):
		if not line.contains("ChessSearchScript"):
			continue
		if line.contains("preload") or line.contains(".new()"):
			continue
		_fail("FAIL the session reaches into the search: %s" % line.strip_edges())
	var search: ChessSearch = ChessSearchScript.new() as ChessSearch
	if not search.has_method("best_move"):
		_fail("FAIL ChessSearch has no best_move")
		return
	print("OK only chess_session.gd loads the engine, and only through best_move")


func _collect_users(dir: DirAccess, path: String, out: PackedStringArray) -> void:
	for sub: String in dir.get_directories():
		var child := DirAccess.open("%s/%s" % [path, sub])
		if child != null:
			_collect_users(child, "%s/%s" % [path, sub], out)
	for file: String in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var full := "%s/%s" % [path, file]
		if full.ends_with("chess_search.gd"):
			continue
		if FileAccess.get_file_as_string(full).contains("chess_search.gd"):
			out.append(full)


## Not an assertion, a measurement: what each level buys, so tuning is done against numbers.
func _report_depth() -> void:
	for level: StringName in ChessSessionScript.LEVELS:
		var budget := ChessSessionScript.level_budget_ms(level)
		for entry: Variant in DEPTH_CASES:
			var case: Dictionary = entry
			var board: ChessBoardState = ChessBoardStateScript.new() as ChessBoardState
			if not board.load_fen(str(case["fen"])):
				_fail("FAIL %s did not parse" % case["name"])
				continue
			var search: ChessSearch = ChessSearchScript.new() as ChessSearch
			## No spread here: a measurement is worth more when two runs of it can be
			## compared, and the varied move would make the last column noise.
			var reply := search.best_move(board, budget, 0)
			print(
				"    %-8s %-22s depth %d  %6d nodes  %4d ms  best %s"
				% [
					String(level),
					str(case["name"]),
					int(reply["depth"]),
					int(reply["nodes"]),
					int(reply["ms"]),
					ChessBoardStateScript.move_name(int(reply["move"])),
				]
			)
			if level == &"club" and int(reply["depth"]) < MIN_CLUB_DEPTH:
				_fail(
					"FAIL club only reached depth %d on %s"
					% [int(reply["depth"]), case["name"]]
				)


## Every level has to finish inside the walk that hides it, or the player watches a monster
## stand still and think.
func _check_levels_fit_the_animation() -> void:
	for level: StringName in ChessSessionScript.LEVELS:
		var budget := ChessSessionScript.level_budget_ms(level)
		if budget > HIDDEN_MS:
			_fail(
				"FAIL level %s asks for %d ms but only %d ms is hidden by the walk"
				% [String(level), budget, HIDDEN_MS]
			)
	if not _failed:
		print("OK every level's budget fits inside the move animation (%d ms)" % HIDDEN_MS)
