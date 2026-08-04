## The chess opponent, behind one function.
##
## `best_move` is deliberately the only surface. Everything inside — iterative deepening,
## alpha-beta, quiescence, move ordering, the tables — is an implementation detail, so
## replacing this with a native engine later (the `native/city_voxel` pattern) is a
## single-file swap rather than a hunt through the arena.
##
## GDScript is viable here for one reason: a move already costs several seconds of monster
## walking, so a search may take a second and still be invisible. That is why the budget is
## a parameter rather than a constant — the caller knows how long the choreography will hide.
##
## Not Stockfish. It is GPL-3 and this repository has no root LICENSE, so linking it would
## relicense the game.
class_name ChessSearch
extends RefCounted

const ChessBoardStateScript := preload("res://scripts/city/chess_board_state.gd")

## Score for a mate at the root. Mates found deeper score slightly lower so the search
## prefers the quicker kill, and the margin is wide enough that no material total reaches it.
const MATE := 30000
const INF := 100000
## Anything at least this good is a mate rather than a material judgement.
const MATE_THRESHOLD := MATE - 1000

## Centipawn worth of each piece type, indexed by ChessBoardState's type codes. The king has
## no material value: it is never captured, and giving it one would swamp every other term.
const VALUE: Array[int] = [0, 100, 320, 330, 500, 900, 0]

## How much worse than a draw the search will accept rather than take the draw — contempt, as
## engines call it. Seeing repetitions at all is what stops a winning side repeating; this is
## for the position that evaluates to exactly level, where a draw and playing on score alike
## and a deterministic search then picks whichever the move ordering happened to put first.
## A quarter of a pawn settles that in favour of playing on, and is small enough that a draw
## which rescues a lost position is still worth taking.
const CONTEMPT := 25

## How far below the best a root move may score and still be played. Two copies of a
## deterministic search replay the same game every time, which is dull to watch when both
## players are the house; picking at random among moves this search cannot meaningfully
## separate makes every match its own without making either side play worse.
##
## Deliberately smaller than CONTEMPT. A move that repeats scores exactly -CONTEMPT, so
## keeping the spread below it means variety can only ever reach for a draw once the engine is
## already worse off than the contempt margin — which is precisely when a draw is a fair
## result rather than the shuffle this whole mechanism exists to prevent.
const SPREAD := 15

## How deep iterative deepening may ever go, whatever the budget. A depth this far past what
## GDScript reaches in a second is a runaway, not a search.
const MAX_DEPTH := 8
## Extra plies of captures explored past the horizon, so the search never stops halfway
## through a trade and calls the position won.
const MAX_QUIESCENCE := 6
## Nodes between clock reads. `Time.get_ticks_msec()` is cheap but not free, and a search
## that checks it every node spends real time asking what time it is.
const CLOCK_EVERY := 1024

## Piece-square tables, in reading order: the first row is rank 8 and the first column the
## a-file, so they can be compared against the published tables without mental gymnastics.
## `_pst_index` does the flip to ChessBoardState's rank-0-is-white's-home numbering.
const PST_PAWN: Array[int] = [
	  0,   0,   0,   0,   0,   0,   0,   0,
	 50,  50,  50,  50,  50,  50,  50,  50,
	 10,  10,  20,  30,  30,  20,  10,  10,
	  5,   5,  10,  25,  25,  10,   5,   5,
	  0,   0,   0,  20,  20,   0,   0,   0,
	  5,  -5, -10,   0,   0, -10,  -5,   5,
	  5,  10,  10, -20, -20,  10,  10,   5,
	  0,   0,   0,   0,   0,   0,   0,   0,
]
const PST_KNIGHT: Array[int] = [
	-50, -40, -30, -30, -30, -30, -40, -50,
	-40, -20,   0,   0,   0,   0, -20, -40,
	-30,   0,  10,  15,  15,  10,   0, -30,
	-30,   5,  15,  20,  20,  15,   5, -30,
	-30,   0,  15,  20,  20,  15,   0, -30,
	-30,   5,  10,  15,  15,  10,   5, -30,
	-40, -20,   0,   5,   5,   0, -20, -40,
	-50, -40, -30, -30, -30, -30, -40, -50,
]
const PST_BISHOP: Array[int] = [
	-20, -10, -10, -10, -10, -10, -10, -20,
	-10,   0,   0,   0,   0,   0,   0, -10,
	-10,   0,   5,  10,  10,   5,   0, -10,
	-10,   5,   5,  10,  10,   5,   5, -10,
	-10,   0,  10,  10,  10,  10,   0, -10,
	-10,  10,  10,  10,  10,  10,  10, -10,
	-10,   5,   0,   0,   0,   0,   5, -10,
	-20, -10, -10, -10, -10, -10, -10, -20,
]
const PST_ROOK: Array[int] = [
	  0,   0,   0,   0,   0,   0,   0,   0,
	  5,  10,  10,  10,  10,  10,  10,   5,
	 -5,   0,   0,   0,   0,   0,   0,  -5,
	 -5,   0,   0,   0,   0,   0,   0,  -5,
	 -5,   0,   0,   0,   0,   0,   0,  -5,
	 -5,   0,   0,   0,   0,   0,   0,  -5,
	 -5,   0,   0,   0,   0,   0,   0,  -5,
	  0,   0,   0,   5,   5,   0,   0,   0,
]
const PST_QUEEN: Array[int] = [
	-20, -10, -10,  -5,  -5, -10, -10, -20,
	-10,   0,   0,   0,   0,   0,   0, -10,
	-10,   0,   5,   5,   5,   5,   0, -10,
	 -5,   0,   5,   5,   5,   5,   0,  -5,
	  0,   0,   5,   5,   5,   5,   0,  -5,
	-10,   5,   5,   5,   5,   5,   0, -10,
	-10,   0,   5,   0,   0,   0,   0, -10,
	-20, -10, -10,  -5,  -5, -10, -10, -20,
]
## Two king tables: hide behind the pawns while there is an army on the board, walk to the
## centre once there is not. Without the second one the endgame king cowers on g1 forever.
const PST_KING_MID: Array[int] = [
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-30, -40, -40, -50, -50, -40, -40, -30,
	-20, -30, -30, -40, -40, -30, -30, -20,
	-10, -20, -20, -20, -20, -20, -20, -10,
	 20,  20,   0,   0,   0,   0,  20,  20,
	 20,  30,  10,   0,   0,  10,  30,  20,
]
const PST_KING_END: Array[int] = [
	-50, -40, -30, -20, -20, -30, -40, -50,
	-30, -20, -10,   0,   0, -10, -20, -30,
	-30, -10,  20,  30,  30,  20, -10, -30,
	-30, -10,  30,  40,  40,  30, -10, -30,
	-30, -10,  30,  40,  40,  30, -10, -30,
	-30, -10,  20,  30,  30,  20, -10, -30,
	-30, -30,   0,   0,   0,   0, -30, -30,
	-50, -30, -30, -30, -30, -30, -30, -50,
]
## Total non-king, non-pawn material below which the endgame king table takes over. Roughly
## a queen and a rook per side gone.
const ENDGAME_MATERIAL := 1800

var _board: ChessBoardState = null
var _deadline_ms: int = 0
var _nodes: int = 0
## Set when the clock runs out mid-iteration. Everything above unwinds without judging.
var _stop: bool = false
## Best move found at the previous completed depth, searched first at the next one. Cheap
## ordering that is worth more than every table below it.
var _pv_move: int = 0
## The colour this search is playing for. Contempt is measured against it at every node, so
## both halves of the tree agree on what a draw is worth. Scoring a draw as bad for whoever
## happens to be on the move would have white and black both believing they profit from the
## same halved point, and a search that disagrees with itself oscillates.
var _engine_colour: int = ChessBoardStateScript.WHITE
## Position keys on the way to the current node: the game's own reversible history first, then
## one per ply the search has made. The last entry is always the position as it stands.
var _path: PackedInt64Array = PackedInt64Array()
## Earliest entry in `_path` the current position could still repeat. Everything before it is
## separated by a capture or a pawn move and can never come back.
var _path_base: int = 0
## Centipawns of slack allowed when picking between root moves. Zero plays the best move found
## and nothing else, which is what a test wants when it is asserting a particular reply.
var _spread: int = SPREAD
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	## Fresh entropy per search. RandomNumberGenerator seeds itself, but saying so is the
	## difference between varying and happening to vary.
	_rng.randomize()


## Pick a move for the side to move within `budget_ms`.
##
## Returns {"move": int, "depth": int, "score": int, "nodes": int, "ms": int}. `move` is 0
## when the position has no legal moves, which is checkmate or stalemate and the caller's
## business rather than ours. `depth` is the deepest iteration that *completed*: a partial
## one is discarded, because a half-searched depth can be worse than the full one below it.
##
## `state` must carry its game history, because avoiding a repetition means knowing which
## positions have already stood. Passing a bare position makes the search play the position
## correctly and the *game* badly.
##
## `state` is searched in place. It is left exactly as it was found (make/unmake pair
## strictly), but the caller should still hand over a `clone()` if the board is live — this
## runs on a worker thread and a UI reading a board mid-search would see a phantom position.
##
## `spread_cp` is how much worse than the best a move may be and still get played, so two
## engines do not replay the same game every time. Pass 0 for the single best move the search
## found, which is what a test asserting a particular reply needs.
func best_move(state: ChessBoardState, budget_ms: int, spread_cp: int = SPREAD) -> Dictionary:
	if state == null:
		push_error("ChessSearch.best_move: no board")
		return {"move": 0, "depth": 0, "score": 0, "nodes": 0, "ms": 0}
	_board = state
	_nodes = 0
	_stop = false
	_pv_move = 0
	_spread = maxi(spread_cp, 0)
	_engine_colour = state.side_to_move
	_path = state.reversible_keys()
	_path_base = 0
	var began := Time.get_ticks_msec()
	_deadline_ms = began + maxi(budget_ms, 1)

	var moves := _board.generate_legal_moves()
	if moves.is_empty():
		return {"move": 0, "depth": 0, "score": 0, "nodes": 0, "ms": 0}
	var best := moves[0]
	var best_score := -INF
	var reached := 0
	## Root moves and their exact scores from the newest iteration that judged anything, kept
	## so the spread can be applied once at the end rather than per iteration — picking a
	## near-equal move early would hand the next iteration a worse move to order by.
	var choices := PackedInt32Array()
	var choice_scores := PackedInt32Array()
	for depth in range(1, MAX_DEPTH + 1):
		var scored := _search_root(moves, depth)
		## Root moves are searched best-guess first, so an iteration that ran out of time
		## part-way still improves on the one below it as long as one move got a full window.
		## Keeping that partial answer is what lets a bigger budget buy anything at all: the
		## next ply costs several times the last, so a search that only ever kept completed
		## plies would throw away most of the time it was given.
		if int(scored["searched"]) > 0:
			best = int(scored["move"])
			best_score = int(scored["score"])
			_pv_move = best
			choices = scored["choices"]
			choice_scores = scored["scores"]
		if _stop:
			break
		reached = depth
		## A forced mate is the end of the search: no deeper look changes the answer.
		if absi(best_score) >= MATE_THRESHOLD:
			break
		if Time.get_ticks_msec() >= _deadline_ms:
			break
	var played := _pick(choices, choice_scores, best, best_score)
	_board = null
	_path = PackedInt64Array()
	return {
		"move": int(played["move"]),
		"depth": reached,
		"score": int(played["score"]),
		"nodes": _nodes,
		"ms": Time.get_ticks_msec() - began,
	}


## One iteration over the root moves. `searched` counts how many got a full window before
## the clock ran out, so the caller knows whether the answer is worth keeping. `choices` and
## `scores` are the moves judged this iteration and what they came back as.
func _search_root(moves: PackedInt32Array, depth: int) -> Dictionary:
	var order := _order_moves(moves, _pv_move)
	var best := order[0]
	var best_score := -INF
	## The window floor sits a spread *below* the best rather than on it. Narrowing it to the
	## best — the usual thing to do — makes every later move fail low, and a fail-low score is
	## only an upper bound on the truth: picking among those would be picking among numbers the
	## search never established. Widening by the spread costs a little pruning and buys an
	## exact score for every move that could possibly be chosen.
	var alpha := -INF
	var searched := 0
	var base := _path_base
	var choices := PackedInt32Array()
	var scores := PackedInt32Array()
	for i in range(order.size()):
		var m: int = order[i]
		_board.make_move(m)
		_push_key()
		var score := -_negamax(depth - 1, -INF, -alpha)
		_pop_key(base)
		_board.unmake_move()
		if _stop:
			break
		searched += 1
		choices.append(m)
		scores.append(score)
		if score > best_score:
			best_score = score
			best = m
			alpha = best_score - _spread
	return {
		"move": best,
		"score": best_score,
		"searched": searched,
		"choices": choices,
		"scores": scores,
	}


## A root move at random from those the search could not meaningfully separate from the best.
##
## Only scores above the window floor are exact, and the floor was the best-so-far less the
## spread, so any move that came back above `best_score - _spread` was searched with a window
## wide enough to report it truthfully. Everything else is an upper bound that already sits
## below the cut, which is why filtering on the same margin is sound rather than convenient.
func _pick(
	choices: PackedInt32Array, scores: PackedInt32Array, best: int, best_score: int
) -> Dictionary:
	if _spread <= 0 or choices.is_empty():
		return {"move": best, "score": best_score}
	## A forced mate is played, not sampled. Mates are scored by distance and the margin
	## between a mate in one and a mate in four is a handful of points, so a spread of any use
	## elsewhere would happily trade the quick kill for a slow one in front of an audience.
	if absi(best_score) >= MATE_THRESHOLD:
		return {"move": best, "score": best_score}
	var cut := best_score - _spread
	var pool := PackedInt32Array()
	var pool_scores := PackedInt32Array()
	for i in range(choices.size()):
		if scores[i] > cut:
			pool.append(choices[i])
			pool_scores.append(scores[i])
	if pool.is_empty():
		return {"move": best, "score": best_score}
	var idx := _rng.randi_range(0, pool.size() - 1)
	return {"move": pool[idx], "score": pool_scores[idx]}


func _negamax(depth: int, alpha: int, beta: int) -> int:
	_nodes += 1
	if (_nodes & (CLOCK_EVERY - 1)) == 0 and Time.get_ticks_msec() >= _deadline_ms:
		_stop = true
	if _stop:
		return 0
	## Both draws by attrition, and both invisible to a material count, so the search has to
	## test for them or it will shuffle into one while a rook up.
	if _board.halfmove_clock >= 100:
		return _draw_score()
	if _is_repetition():
		return _draw_score()
	if depth <= 0:
		return _quiescence(alpha, beta, MAX_QUIESCENCE)

	var moves := _board.generate_legal_moves()
	if moves.is_empty():
		## Mated positions are scored by distance so a mate in one beats a mate in three,
		## and a stalemate is a draw however lost the position looked.
		if _board.in_check(_board.side_to_move):
			return -MATE + (MAX_DEPTH - depth)
		return _draw_score()

	var order := _order_moves(moves, 0)
	var best := -INF
	var a := alpha
	var base := _path_base
	for i in range(order.size()):
		_board.make_move(int(order[i]))
		_push_key()
		var score := -_negamax(depth - 1, -beta, -a)
		_pop_key(base)
		_board.unmake_move()
		if _stop:
			return 0
		if score > best:
			best = score
		if score > a:
			a = score
		if a >= beta:
			break
	return best


## Captures only, past the horizon. Without this the search stops mid-trade and reports a
## position as won because it counted the queen it just took and not the one taking it back.
func _quiescence(alpha: int, beta: int, depth: int) -> int:
	_nodes += 1
	if (_nodes & (CLOCK_EVERY - 1)) == 0 and Time.get_ticks_msec() >= _deadline_ms:
		_stop = true
	if _stop:
		return 0
	var stand := _evaluate()
	if depth <= 0 or stand >= beta:
		return stand
	var a := maxi(alpha, stand)
	var loud := _board.generate_legal_captures()
	if loud.is_empty():
		return a
	var order := _order_moves(loud, 0)
	for i in range(order.size()):
		_board.make_move(int(order[i]))
		var score := -_quiescence(-beta, -a, depth - 1)
		_board.unmake_move()
		if _stop:
			return 0
		if score > a:
			a = score
		if a >= beta:
			break
	return a


## Record the position just made, and note whether it is one nothing earlier can reach again.
##
## Quiescence deliberately does not do this. Every move it plays is a capture or a promotion,
## both irreversible, so no line it walks can repeat anything.
func _push_key() -> void:
	_path.append(_board.position_key())
	if _board.halfmove_clock == 0:
		## A capture or a pawn move draws a line under the history: nothing before it can come
		## back, so later scans stop here.
		_path_base = _path.size() - 1


func _pop_key(base: int) -> void:
	_path.resize(_path.size() - 1)
	_path_base = base


## True when the position on top of the path has already stood in this line.
##
## One repetition is enough — the rules need three before it is a draw, but a position that
## came back once will come back again if both sides are content, so treating the first as a
## draw is both cheaper to detect and a stronger judgement than waiting for the third.
func _is_repetition() -> bool:
	var last := _path.size() - 1
	if last <= 0:
		return false
	var key := _path[last]
	for i in range(_path_base, last):
		if _path[i] == key:
			return true
	return false


## What a draw is worth, from the point of view of whoever is to move at this node. Negative
## for the side the search plays for, positive for the opponent, so it stays one consistent
## opinion however deep in the tree it is asked.
func _draw_score() -> int:
	return -CONTEMPT if _board.side_to_move == _engine_colour else CONTEMPT


## Moves sorted best-guess first, which is what makes alpha-beta cut anything at all.
## MVV-LVA: take the most valuable victim with the least valuable attacker, so QxP is tried
## after PxQ rather than before it.
func _order_moves(moves: PackedInt32Array, first: int) -> Array[int]:
	var scores: Array[int] = []
	var out: Array[int] = []
	for i in range(moves.size()):
		var m := moves[i]
		out.append(m)
		scores.append(_move_score(m, first))
	## Insertion sort, descending. Move lists here are a few dozen entries and already
	## roughly ordered by the generator, which is the case insertion sort is fastest at.
	for i in range(1, out.size()):
		var m: int = out[i]
		var s: int = scores[i]
		var j := i - 1
		while j >= 0 and scores[j] < s:
			out[j + 1] = out[j]
			scores[j + 1] = scores[j]
			j -= 1
		out[j + 1] = m
		scores[j + 1] = s
	return out


func _move_score(move: int, first: int) -> int:
	if move == first and first != 0:
		return 1000000
	var score := 0
	var promo := ChessBoardStateScript.move_promotion(move)
	if promo != 0:
		score += 90000 + VALUE[promo]
	var to := ChessBoardStateScript.move_to(move)
	var victim := int(_board.squares[to])
	if (move & ChessBoardStateScript.FLAG_EP) != 0:
		victim = ChessBoardStateScript.PAWN
	if victim != ChessBoardStateScript.EMPTY:
		var attacker := int(_board.squares[ChessBoardStateScript.move_from(move)])
		score += (
			50000
			+ VALUE[ChessBoardStateScript.piece_type(victim)] * 10
			- VALUE[ChessBoardStateScript.piece_type(attacker)]
		)
	return score


## Material plus piece placement, from the side to move's point of view — negamax requires
## that, and a score that silently means "good for white" is the classic way to build an
## engine that plays well as one colour and terribly as the other.
func _evaluate() -> int:
	var white := 0
	var black := 0
	var heavy := 0
	## Two passes would be tidier, but this is the hottest function in the search and the
	## king tables need the material total, so collect it on the way past.
	var kings := PackedInt32Array([-1, -1])
	for sq in range(64):
		var piece := int(_board.squares[sq])
		if piece == ChessBoardStateScript.EMPTY:
			continue
		var type := piece & ChessBoardStateScript.TYPE_MASK
		var is_white := (piece & ChessBoardStateScript.COLOUR_MASK) == ChessBoardStateScript.WHITE
		if type == ChessBoardStateScript.KING:
			kings[0 if is_white else 1] = sq
			continue
		if type != ChessBoardStateScript.PAWN:
			heavy += VALUE[type]
		var v := VALUE[type] + _pst_value(type, sq, is_white)
		if is_white:
			white += v
		else:
			black += v
	var king_table := PST_KING_END if heavy <= ENDGAME_MATERIAL else PST_KING_MID
	if kings[0] >= 0:
		white += king_table[_pst_index(kings[0], true)]
	if kings[1] >= 0:
		black += king_table[_pst_index(kings[1], false)]
	var score := white - black
	return score if _board.side_to_move == ChessBoardStateScript.WHITE else -score


func _pst_value(type: int, sq: int, is_white: bool) -> int:
	var idx := _pst_index(sq, is_white)
	match type:
		ChessBoardStateScript.PAWN:
			return PST_PAWN[idx]
		ChessBoardStateScript.KNIGHT:
			return PST_KNIGHT[idx]
		ChessBoardStateScript.BISHOP:
			return PST_BISHOP[idx]
		ChessBoardStateScript.ROOK:
			return PST_ROOK[idx]
		ChessBoardStateScript.QUEEN:
			return PST_QUEEN[idx]
	push_error("ChessSearch: no table for piece type %d" % type)
	return 0


## Board square → table index. The tables are written rank 8 first, so white reads them
## upside down and black reads them straight.
static func _pst_index(sq: int, is_white: bool) -> int:
	var file := sq & 7
	var rank := sq >> 3
	return (7 - rank) * 8 + file if is_white else rank * 8 + file
