## Pure chess rules (no nodes, no AI, no views), the counterpart of GoBoardState.
##
## Complete FIDE movement: castling with rights and path safety, en passant, promotion,
## checkmate, stalemate, the fifty-move rule and threefold repetition. All of it is needed
## anyway to answer "is this tap a legal move?" for the monster board, and a move generator
## that is subtly wrong shows up later as a baffling puppet bug — so this file is validated
## by perft in tools/test_chess_rules.gd before anything visual reads it.
##
## Two layers live here on purpose:
##   * `try_move` commits a move to the game: it records history and announces it.
##   * `make_move` / `unmake_move` are the search primitives: no signals, no history, and
##     an undo stack so a tree walk can back out. Search runs on a `clone()`.
class_name ChessBoardState
extends RefCounted

## Announced once a committed move is on the board. `capture_at` is (-1, -1) when nothing
## was taken, and differs from `to_sq` on an en-passant capture. `rook_from` / `rook_to` are
## (-1, -1) unless this was a castle.
signal moved(
	colour: int,
	from_sq: Vector2i,
	to_sq: Vector2i,
	promotion: int,
	capture_at: Vector2i,
	captured_piece: int,
	rook_from: Vector2i,
	rook_to: Vector2i
)
signal game_over(reason: String)
signal reset()

const EMPTY := 0
## Piece types occupy the low three bits of a piece code.
const PAWN := 1
const KNIGHT := 2
const BISHOP := 3
const ROOK := 4
const QUEEN := 5
const KING := 6
const TYPE_MASK := 7
## Colours are bit flags rather than 1 / 2, so a piece code is just `type | colour` and
## both halves come back out with a mask. They double as the side-to-move value.
const WHITE := 8
const BLACK := 16
const COLOUR_MASK := 24

## Castling rights, one bit each.
const CASTLE_WK := 1
const CASTLE_WQ := 2
const CASTLE_BK := 4
const CASTLE_BQ := 8

## Move packing: from | to << 6 | promotion type << 12 | flags.
const MOVE_FROM_MASK := 63
const MOVE_TO_SHIFT := 6
const MOVE_PROMO_SHIFT := 12
const MOVE_PROMO_MASK := 7
const FLAG_EP := 1 << 16
const FLAG_CASTLE := 1 << 17
const FLAG_DOUBLE := 1 << 18

## Eight compass directions. Rooks take the even entries, bishops the odd ones, queens and
## kings all of them. Typed Arrays rather than PackedInt32Array because only the former is
## a constant expression, and a const container is read-only where a static var is not.
const DIR_F: Array[int] = [1, 1, 0, -1, -1, -1, 0, 1]
const DIR_R: Array[int] = [0, 1, 1, 1, 0, -1, -1, -1]
const KNIGHT_F: Array[int] = [1, 2, 2, 1, -1, -2, -2, -1]
const KNIGHT_R: Array[int] = [2, 1, -1, -2, -2, -1, 1, 2]

const START_FEN := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

## Undo record stride: move, captured piece, captured square, rights, ep square, clock.
const UNDO_STRIDE := 6

## 64 squares, index = rank * 8 + file. File 0 is the a-file, rank 0 is white's home rank.
var squares: PackedByteArray = PackedByteArray()
var side_to_move: int = WHITE
var castling_rights: int = 0
## Square a pawn may be captured *on* by en passant, or -1.
var ep_square: int = -1
## Plies since the last capture or pawn move. 100 is the fifty-move draw.
var halfmove_clock: int = 0
var fullmove_number: int = 1

## The position this game started from, kept so a save can be resumed by replay rather
## than from a snapshot (see to_save_dict).
var start_fen: String = ""
var phase: StringName = &"idle"
## Set when phase becomes &"over": mate_white_wins / mate_black_wins / stalemate /
## fifty_move / threefold / resign_white / resign_black / stopped.
var end_reason: String = ""
## Committed moves, in order, as packed ints.
var move_list: PackedInt32Array = PackedInt32Array()

## King square per side, kept incrementally so the check test never has to scan for it.
var _king_sq: PackedInt32Array = PackedInt32Array([4, 60])
var _undo: PackedInt32Array = PackedInt32Array()
## Position keys of every committed position including the start, for repetition counting.
var _keys: PackedInt64Array = PackedInt64Array()

## Which rights a move touching this square destroys. Built once.
static var _rights_mask: PackedInt32Array = PackedInt32Array()
static var _zob_piece: PackedInt64Array = PackedInt64Array()
static var _zob_castle: PackedInt64Array = PackedInt64Array()
static var _zob_ep: PackedInt64Array = PackedInt64Array()
static var _zob_side: int = 0


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup() -> void:
	if not load_fen(START_FEN):
		push_error("ChessBoardState.setup: the start position failed to parse")
		return
	phase = &"playing"
	reset.emit()


## Replace the position from a FEN string. False (and nothing changed) if it is not one.
func load_fen(fen: String) -> bool:
	var parts := fen.strip_edges().split(" ", false)
	if parts.size() < 4:
		push_error("ChessBoardState.load_fen: %s has %d fields, need 4" % [fen, parts.size()])
		return false
	var board := PackedByteArray()
	board.resize(64)
	var rows := parts[0].split("/", false)
	if rows.size() != 8:
		push_error("ChessBoardState.load_fen: %d ranks in %s" % [rows.size(), parts[0]])
		return false
	## FEN writes rank 8 first, so the first row is board rank 7.
	for row_i in range(8):
		var rank := 7 - row_i
		var file := 0
		for ch in rows[row_i]:
			if ch >= "1" and ch <= "8":
				file += int(ch)
				continue
			var piece := piece_from_char(ch)
			if piece == EMPTY:
				push_error("ChessBoardState.load_fen: '%s' is not a piece" % ch)
				return false
			if file > 7:
				push_error("ChessBoardState.load_fen: rank %d overflows" % [rank + 1])
				return false
			board[rank * 8 + file] = piece
			file += 1
		if file != 8:
			push_error("ChessBoardState.load_fen: rank %d covers %d files" % [rank + 1, file])
			return false
	var side := WHITE if parts[1] == "w" else BLACK
	if parts[1] != "w" and parts[1] != "b":
		push_error("ChessBoardState.load_fen: '%s' is not a side to move" % parts[1])
		return false
	var rights := 0
	if parts[2] != "-":
		for ch in parts[2]:
			match ch:
				"K":
					rights |= CASTLE_WK
				"Q":
					rights |= CASTLE_WQ
				"k":
					rights |= CASTLE_BK
				"q":
					rights |= CASTLE_BQ
				_:
					push_error("ChessBoardState.load_fen: '%s' is not a castling right" % ch)
					return false
	var ep := -1
	if parts[3] != "-":
		ep = square_from_name(parts[3])
		if ep < 0:
			push_error("ChessBoardState.load_fen: '%s' is not a square" % parts[3])
			return false
	var wk := -1
	var bk := -1
	for sq in range(64):
		var p := int(board[sq])
		if p == (KING | WHITE):
			wk = sq
		elif p == (KING | BLACK):
			bk = sq
	if wk < 0 or bk < 0:
		push_error("ChessBoardState.load_fen: %s is missing a king" % fen)
		return false

	squares = board
	side_to_move = side
	castling_rights = rights
	ep_square = ep
	halfmove_clock = int(parts[4]) if parts.size() > 4 else 0
	fullmove_number = int(parts[5]) if parts.size() > 5 else 1
	_king_sq = PackedInt32Array([wk, bk])
	_undo = PackedInt32Array()
	move_list = PackedInt32Array()
	phase = &"playing"
	end_reason = ""
	_ensure_rights_mask()
	_keys = PackedInt64Array([position_key()])
	start_fen = to_fen()
	return true


func to_fen() -> String:
	var out := ""
	for row_i in range(8):
		var rank := 7 - row_i
		var run := 0
		for file in range(8):
			var p := int(squares[rank * 8 + file])
			if p == EMPTY:
				run += 1
				continue
			if run > 0:
				out += str(run)
				run = 0
			out += piece_to_char(p)
		if run > 0:
			out += str(run)
		if row_i < 7:
			out += "/"
	var rights := ""
	if castling_rights & CASTLE_WK:
		rights += "K"
	if castling_rights & CASTLE_WQ:
		rights += "Q"
	if castling_rights & CASTLE_BK:
		rights += "k"
	if castling_rights & CASTLE_BQ:
		rights += "q"
	if rights.is_empty():
		rights = "-"
	var ep := "-" if ep_square < 0 else square_name(ep_square)
	return "%s %s %s %s %d %d" % [
		out,
		"w" if side_to_move == WHITE else "b",
		rights,
		ep,
		halfmove_clock,
		fullmove_number,
	]


## Independent copy for a search to chew on. History is carried so the search still sees
## repetitions that the game already reached.
func clone() -> ChessBoardState:
	var out := ChessBoardState.new()
	out.squares = squares.duplicate()
	out.side_to_move = side_to_move
	out.castling_rights = castling_rights
	out.ep_square = ep_square
	out.halfmove_clock = halfmove_clock
	out.fullmove_number = fullmove_number
	out.phase = phase
	out.end_reason = end_reason
	out.start_fen = start_fen
	out.move_list = move_list.duplicate()
	out._king_sq = _king_sq.duplicate()
	out._keys = _keys.duplicate()
	return out


# ---------------------------------------------------------------------------
# Reading the board
# ---------------------------------------------------------------------------

## Piece code at a file / rank, or EMPTY. Off-board reads are EMPTY rather than an error:
## generators probe past the edge by design.
func at(file: int, rank: int) -> int:
	if file < 0 or file > 7 or rank < 0 or rank > 7:
		return EMPTY
	return int(squares[rank * 8 + file])


static func piece_type(piece: int) -> int:
	return piece & TYPE_MASK


static func piece_colour(piece: int) -> int:
	return piece & COLOUR_MASK


static func opponent(colour: int) -> int:
	return BLACK if colour == WHITE else WHITE


static func square_of(file: int, rank: int) -> int:
	return rank * 8 + file


static func file_of(sq: int) -> int:
	return sq & 7


static func rank_of(sq: int) -> int:
	return sq >> 3


static func vec_of(sq: int) -> Vector2i:
	return Vector2i(sq & 7, sq >> 3)


static func square_name(sq: int) -> String:
	return "%s%d" % [char("a".unicode_at(0) + (sq & 7)), (sq >> 3) + 1]


## -1 when `name` is not an algebraic square like "e4".
static func square_from_name(sq_name: String) -> int:
	var s := sq_name.strip_edges().to_lower()
	if s.length() != 2:
		return -1
	var file := s.unicode_at(0) - "a".unicode_at(0)
	var rank := s.unicode_at(1) - "1".unicode_at(0)
	if file < 0 or file > 7 or rank < 0 or rank > 7:
		return -1
	return rank * 8 + file


static func piece_from_char(ch: String) -> int:
	var colour := WHITE if ch == ch.to_upper() else BLACK
	match ch.to_lower():
		"p":
			return PAWN | colour
		"n":
			return KNIGHT | colour
		"b":
			return BISHOP | colour
		"r":
			return ROOK | colour
		"q":
			return QUEEN | colour
		"k":
			return KING | colour
	return EMPTY


static func piece_to_char(piece: int) -> String:
	var letters := ["", "p", "n", "b", "r", "q", "k"]
	var ch: String = letters[piece & TYPE_MASK]
	return ch.to_upper() if (piece & COLOUR_MASK) == WHITE else ch


static func move_from(move: int) -> int:
	return move & MOVE_FROM_MASK


static func move_to(move: int) -> int:
	return (move >> MOVE_TO_SHIFT) & MOVE_FROM_MASK


static func move_promotion(move: int) -> int:
	return (move >> MOVE_PROMO_SHIFT) & MOVE_PROMO_MASK


static func pack_move(from_sq: int, to_sq: int, promotion: int = 0, flags: int = 0) -> int:
	return from_sq | (to_sq << MOVE_TO_SHIFT) | (promotion << MOVE_PROMO_SHIFT) | flags


## Long algebraic ("e2e4", "e7e8q") — the format the search and the tests talk in.
static func move_name(move: int) -> String:
	var out := square_name(move_from(move)) + square_name(move_to(move))
	var promo := move_promotion(move)
	if promo != 0:
		out += piece_to_char(promo | BLACK)
	return out


func king_square(colour: int) -> int:
	return _king_sq[0 if colour == WHITE else 1]


func in_check(colour: int) -> bool:
	return is_attacked(king_square(colour), opponent(colour))


## True when `by_colour` could capture something standing on `sq` this instant. Castling
## path safety and the self-check filter both rest on this, so it must consider every
## attacker type, pawns included.
func is_attacked(sq: int, by_colour: int) -> bool:
	var file := sq & 7
	var rank := sq >> 3
	## Pawns: a white pawn attacks upward, so it has to be a rank below the target.
	var pawn_rank := rank - 1 if by_colour == WHITE else rank + 1
	if pawn_rank >= 0 and pawn_rank <= 7:
		var want_pawn := PAWN | by_colour
		if file > 0 and int(squares[pawn_rank * 8 + file - 1]) == want_pawn:
			return true
		if file < 7 and int(squares[pawn_rank * 8 + file + 1]) == want_pawn:
			return true
	var want_knight := KNIGHT | by_colour
	for i in range(8):
		var f := file + KNIGHT_F[i]
		var r := rank + KNIGHT_R[i]
		if f < 0 or f > 7 or r < 0 or r > 7:
			continue
		if int(squares[r * 8 + f]) == want_knight:
			return true
	var want_king := KING | by_colour
	var want_queen := QUEEN | by_colour
	var want_rook := ROOK | by_colour
	var want_bishop := BISHOP | by_colour
	for i in range(8):
		var df := DIR_F[i]
		var dr := DIR_R[i]
		## Even directions are the rook lines, odd ones the bishop diagonals.
		var want_slider := want_rook if i % 2 == 0 else want_bishop
		var f := file + df
		var r := rank + dr
		var step := 1
		while f >= 0 and f <= 7 and r >= 0 and r <= 7:
			var p := int(squares[r * 8 + f])
			if p != EMPTY:
				if p == want_queen or p == want_slider:
					return true
				if step == 1 and p == want_king:
					return true
				break
			f += df
			r += dr
			step += 1
	return false


# ---------------------------------------------------------------------------
# Move generation
# ---------------------------------------------------------------------------

## Every move the side to move may actually play. Pseudo-legal moves are filtered by
## playing them and asking whether the mover's own king ends up attacked, which is slower
## than pin analysis and impossible to get subtly wrong.
func generate_legal_moves() -> PackedInt32Array:
	var pseudo := _generate_pseudo()
	var out := PackedInt32Array()
	var mover := side_to_move
	for i in range(pseudo.size()):
		var m := pseudo[i]
		make_move(m)
		if not is_attacked(king_square(mover), side_to_move):
			out.append(m)
		unmake_move()
	return out


## Legal captures and promotions only, which is what a search's quiescence pass wants.
##
## The same answer as generating everything and filtering, for a fraction of the cost: the
## self-check test is the expensive half of move generation and this only pays it for the
## moves it is going to keep. Quiescence is the hottest caller in the engine, and most moves
## in a position are quiet.
func generate_legal_captures() -> PackedInt32Array:
	var pseudo := _generate_pseudo()
	var out := PackedInt32Array()
	var mover := side_to_move
	for i in range(pseudo.size()):
		var m := pseudo[i]
		if not is_loud(m):
			continue
		make_move(m)
		if not is_attacked(king_square(mover), side_to_move):
			out.append(m)
		unmake_move()
	return out


## True when this move takes something or makes a queen — the moves a search must keep
## looking at past its horizon. Reads the board, so it only answers for the position the
## move was generated in.
func is_loud(move: int) -> bool:
	if move_promotion(move) != 0:
		return true
	if (move & FLAG_EP) != 0:
		return true
	return int(squares[move_to(move)]) != EMPTY


## Legal moves whose origin is this square. Empty when the square is not the side to
## move's — which is exactly what "you cannot pick up that piece" means.
func legal_moves_from(file: int, rank: int) -> PackedInt32Array:
	var from := square_of(file, rank)
	var out := PackedInt32Array()
	if file < 0 or file > 7 or rank < 0 or rank > 7:
		return out
	if piece_colour(int(squares[from])) != side_to_move:
		return out
	var all := generate_legal_moves()
	for i in range(all.size()):
		if move_from(all[i]) == from:
			out.append(all[i])
	return out


## Distinct destination squares reachable from a square, for highlighting. The four
## promotion moves onto one square collapse to a single entry.
func legal_destinations_from(file: int, rank: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen: Dictionary = {}
	var moves := legal_moves_from(file, rank)
	for i in range(moves.size()):
		var to := move_to(moves[i])
		if seen.has(to):
			continue
		seen[to] = true
		out.append(vec_of(to))
	return out


func _generate_pseudo() -> PackedInt32Array:
	var out := PackedInt32Array()
	var us := side_to_move
	for sq in range(64):
		var piece := int(squares[sq])
		if piece == EMPTY or (piece & COLOUR_MASK) != us:
			continue
		match piece & TYPE_MASK:
			PAWN:
				_gen_pawn(sq, us, out)
			KNIGHT:
				_gen_hops(sq, us, KNIGHT_F, KNIGHT_R, out)
			BISHOP:
				_gen_slides(sq, us, 1, out)
			ROOK:
				_gen_slides(sq, us, 0, out)
			QUEEN:
				_gen_slides(sq, us, 0, out)
				_gen_slides(sq, us, 1, out)
			KING:
				_gen_hops(sq, us, DIR_F, DIR_R, out)
	_gen_castles(us, out)
	return out


func _gen_pawn(sq: int, us: int, out: PackedInt32Array) -> void:
	var file := sq & 7
	var rank := sq >> 3
	var dir := 1 if us == WHITE else -1
	var home := 1 if us == WHITE else 6
	var last := 7 if us == WHITE else 0
	var ahead := rank + dir
	if ahead < 0 or ahead > 7:
		## A pawn on the last rank is not a position this generator can be handed.
		push_error("ChessBoardState: a pawn is standing on rank %d" % [rank + 1])
		return
	var one := ahead * 8 + file
	if int(squares[one]) == EMPTY:
		if ahead == last:
			_push_promotions(sq, one, out)
		else:
			out.append(pack_move(sq, one))
			if rank == home:
				var two := (rank + dir * 2) * 8 + file
				if int(squares[two]) == EMPTY:
					out.append(pack_move(sq, two, 0, FLAG_DOUBLE))
	var side := -1
	while side <= 1:
		var f := file + side
		side += 2
		if f < 0 or f > 7:
			continue
		var target := ahead * 8 + f
		var occupant := int(squares[target])
		if occupant != EMPTY:
			if (occupant & COLOUR_MASK) != us:
				if ahead == last:
					_push_promotions(sq, target, out)
				else:
					out.append(pack_move(sq, target))
		elif target == ep_square:
			out.append(pack_move(sq, target, 0, FLAG_EP))


func _push_promotions(from_sq: int, to_sq: int, out: PackedInt32Array) -> void:
	## Queen first: it is the move the search wants to try before the others.
	out.append(pack_move(from_sq, to_sq, QUEEN))
	out.append(pack_move(from_sq, to_sq, ROOK))
	out.append(pack_move(from_sq, to_sq, BISHOP))
	out.append(pack_move(from_sq, to_sq, KNIGHT))


func _gen_hops(
	sq: int, us: int, offs_f: Array[int], offs_r: Array[int], out: PackedInt32Array
) -> void:
	var file := sq & 7
	var rank := sq >> 3
	for i in range(offs_f.size()):
		var f := file + offs_f[i]
		var r := rank + offs_r[i]
		if f < 0 or f > 7 or r < 0 or r > 7:
			continue
		var target := r * 8 + f
		var occupant := int(squares[target])
		if occupant == EMPTY or (occupant & COLOUR_MASK) != us:
			out.append(pack_move(sq, target))


## `parity` 0 walks the rook lines, 1 the bishop diagonals.
func _gen_slides(sq: int, us: int, parity: int, out: PackedInt32Array) -> void:
	var file := sq & 7
	var rank := sq >> 3
	var i := parity
	while i < 8:
		var df := DIR_F[i]
		var dr := DIR_R[i]
		var f := file + df
		var r := rank + dr
		while f >= 0 and f <= 7 and r >= 0 and r <= 7:
			var target := r * 8 + f
			var occupant := int(squares[target])
			if occupant == EMPTY:
				out.append(pack_move(sq, target))
			else:
				if (occupant & COLOUR_MASK) != us:
					out.append(pack_move(sq, target))
				break
			f += df
			r += dr
		i += 2


## Castling needs the rights, an empty path, and safety on the king's start and transit
## squares. The destination square is left to the self-check filter, which covers it.
func _gen_castles(us: int, out: PackedInt32Array) -> void:
	var them := opponent(us)
	var king := 4 if us == WHITE else 60
	var short_right := CASTLE_WK if us == WHITE else CASTLE_BK
	var long_right := CASTLE_WQ if us == WHITE else CASTLE_BQ
	if (castling_rights & short_right) != 0:
		if squares[king + 1] == EMPTY and squares[king + 2] == EMPTY:
			if not is_attacked(king, them) and not is_attacked(king + 1, them):
				out.append(pack_move(king, king + 2, 0, FLAG_CASTLE))
	if (castling_rights & long_right) != 0:
		if (
			squares[king - 1] == EMPTY
			and squares[king - 2] == EMPTY
			and squares[king - 3] == EMPTY
		):
			if not is_attacked(king, them) and not is_attacked(king - 1, them):
				out.append(pack_move(king, king - 2, 0, FLAG_CASTLE))


# ---------------------------------------------------------------------------
# Search primitives
# ---------------------------------------------------------------------------

## Play a move with no validation, no signals and no history. Pairs strictly with
## `unmake_move`; the caller is responsible for having generated the move.
func make_move(move: int) -> void:
	var from := move & MOVE_FROM_MASK
	var to := (move >> MOVE_TO_SHIFT) & MOVE_FROM_MASK
	var promo := (move >> MOVE_PROMO_SHIFT) & MOVE_PROMO_MASK
	var piece := int(squares[from])
	var us := piece & COLOUR_MASK
	var cap_sq := to
	if (move & FLAG_EP) != 0:
		cap_sq = to - 8 if us == WHITE else to + 8
	var captured := int(squares[cap_sq])

	_undo.append(move)
	_undo.append(captured)
	_undo.append(cap_sq)
	_undo.append(castling_rights)
	_undo.append(ep_square)
	_undo.append(halfmove_clock)

	squares[cap_sq] = EMPTY
	squares[from] = EMPTY
	squares[to] = piece if promo == 0 else (promo | us)
	if (move & FLAG_CASTLE) != 0:
		## Kingside puts the rook where the king passed through; queenside likewise.
		if to > from:
			squares[to + 1] = EMPTY
			squares[to - 1] = ROOK | us
		else:
			squares[to - 2] = EMPTY
			squares[to + 1] = ROOK | us
	if (piece & TYPE_MASK) == KING:
		_king_sq[0 if us == WHITE else 1] = to

	_ensure_rights_mask()
	castling_rights &= ~(_rights_mask[from] | _rights_mask[to])
	ep_square = (from + to) / 2 if (move & FLAG_DOUBLE) != 0 else -1
	if (piece & TYPE_MASK) == PAWN or captured != EMPTY:
		halfmove_clock = 0
	else:
		halfmove_clock += 1
	if us == BLACK:
		fullmove_number += 1
	side_to_move = BLACK if us == WHITE else WHITE


func unmake_move() -> void:
	if _undo.size() < UNDO_STRIDE:
		push_error("ChessBoardState.unmake_move: nothing on the undo stack")
		return
	var base := _undo.size() - UNDO_STRIDE
	var move := _undo[base]
	var captured := _undo[base + 1]
	var cap_sq := _undo[base + 2]
	castling_rights = _undo[base + 3]
	ep_square = _undo[base + 4]
	halfmove_clock = _undo[base + 5]
	_undo.resize(base)

	var from := move & MOVE_FROM_MASK
	var to := (move >> MOVE_TO_SHIFT) & MOVE_FROM_MASK
	var promo := (move >> MOVE_PROMO_SHIFT) & MOVE_PROMO_MASK
	## The mover is whoever was *not* to move while the move stood.
	var us := BLACK if side_to_move == WHITE else WHITE
	side_to_move = us
	if us == BLACK:
		fullmove_number -= 1

	var piece := int(squares[to])
	if promo != 0:
		piece = PAWN | us
	squares[to] = EMPTY
	squares[from] = piece
	squares[cap_sq] = captured
	if (move & FLAG_CASTLE) != 0:
		if to > from:
			squares[to - 1] = EMPTY
			squares[to + 1] = ROOK | us
		else:
			squares[to + 1] = EMPTY
			squares[to - 2] = ROOK | us
	if (piece & TYPE_MASK) == KING:
		_king_sq[0 if us == WHITE else 1] = from


## Leaf count at `depth`, the standard move-generator conformance measure.
func perft(depth: int) -> int:
	if depth <= 0:
		return 1
	var moves := generate_legal_moves()
	if depth == 1:
		return moves.size()
	var total := 0
	for i in range(moves.size()):
		make_move(moves[i])
		total += perft(depth - 1)
		unmake_move()
	return total


# ---------------------------------------------------------------------------
# Committing a move to the game
# ---------------------------------------------------------------------------

## Play a move for real: validated against the legal list, recorded, announced, and
## followed by a terminal test. `promotion` is a piece type (QUEEN…KNIGHT) and is required
## when the move is a promotion; it is ignored otherwise.
func try_move(from_sq: Vector2i, to_sq: Vector2i, promotion: int = QUEEN) -> bool:
	if phase != &"playing":
		return false
	var from := square_of(from_sq.x, from_sq.y)
	var to := square_of(to_sq.x, to_sq.y)
	if from_sq.x < 0 or from_sq.x > 7 or from_sq.y < 0 or from_sq.y > 7:
		return false
	if to_sq.x < 0 or to_sq.x > 7 or to_sq.y < 0 or to_sq.y > 7:
		return false
	var chosen := 0
	var needs_promo := false
	for m in generate_legal_moves():
		if move_from(m) != from or move_to(m) != to:
			continue
		var promo := move_promotion(m)
		if promo == 0:
			chosen = m
			break
		needs_promo = true
		if promo == promotion:
			chosen = m
			break
	if chosen == 0:
		if needs_promo:
			push_error(
				"ChessBoardState.try_move: %s%s promotes, and %d is not a piece to promote to"
				% [square_name(from), square_name(to), promotion]
			)
		return false
	return play_move(chosen)


## Commit an already-generated legal move. This is the seam the AI uses, so it does not
## re-generate the list a search has just walked.
func play_move(move: int) -> bool:
	if phase != &"playing":
		return false
	var from := move_from(move)
	var to := move_to(move)
	var mover := piece_colour(int(squares[from]))
	if mover != side_to_move:
		push_error(
			"ChessBoardState.play_move: %s is not %s's to move"
			% [move_name(move), "white" if side_to_move == WHITE else "black"]
		)
		return false
	var cap_sq := to
	if (move & FLAG_EP) != 0:
		cap_sq = to - 8 if mover == WHITE else to + 8
	var captured := int(squares[cap_sq])
	var rook_from := -1
	var rook_to := -1
	if (move & FLAG_CASTLE) != 0:
		rook_from = to + 1 if to > from else to - 2
		rook_to = to - 1 if to > from else to + 1

	make_move(move)
	## Committed moves are never unmade; keeping records would grow without bound.
	_undo.resize(0)
	move_list.append(move)
	_keys.append(position_key())

	moved.emit(
		mover,
		vec_of(from),
		vec_of(to),
		move_promotion(move),
		vec_of(cap_sq) if captured != EMPTY else Vector2i(-1, -1),
		captured,
		vec_of(rook_from) if rook_from >= 0 else Vector2i(-1, -1),
		vec_of(rook_to) if rook_to >= 0 else Vector2i(-1, -1)
	)
	_check_terminal()
	return true


## Concede. `colour` is the side giving up.
func resign(colour: int) -> bool:
	if phase != &"playing":
		return false
	_finish("resign_white" if colour == WHITE else "resign_black")
	return true


## Spectator abort of an AI-vs-AI game — no winner, the board just stops.
func stop_play() -> bool:
	if phase != &"playing":
		return false
	_finish("stopped")
	return true


func is_over() -> bool:
	return phase == &"over"


func _check_terminal() -> void:
	if generate_legal_moves().is_empty():
		if in_check(side_to_move):
			## The side with no moves is mated, so the other one won.
			_finish("mate_black_wins" if side_to_move == WHITE else "mate_white_wins")
		else:
			_finish("stalemate")
		return
	if halfmove_clock >= 100:
		_finish("fifty_move")
		return
	if repetition_count() >= 3:
		_finish("threefold")


func _finish(reason: String) -> void:
	phase = &"over"
	end_reason = reason
	game_over.emit(reason)


## How often the current position has stood in this game. Only positions since the last
## capture or pawn move can repeat, so the scan stops at the fifty-move counter.
func repetition_count() -> int:
	var window := reversible_keys()
	if window.is_empty():
		return 0
	var current := window[window.size() - 1]
	var count := 0
	for i in range(window.size()):
		if window[i] == current:
			count += 1
	return count


## Keys of every position a future one could still repeat: back to the last capture or pawn
## move, current position included and last.
##
## A search needs this. Repetition is a property of the game so far, not of the search tree,
## and an engine that only looks inside its own tree walks into a draw it could have seen
## coming — or, worse, repeats deliberately because a draw and a level position score alike.
func reversible_keys() -> PackedInt64Array:
	if _keys.is_empty():
		push_error("ChessBoardState.reversible_keys: no history, so the board was never loaded")
		return PackedInt64Array()
	return _keys.slice(maxi(0, _keys.size() - 1 - halfmove_clock))


## Zobrist key of the position as it stands. Computed rather than maintained: only
## committed moves need one, and a search hot loop must not pay for it.
##
## The en-passant file is folded in whenever a target square is set, even if no pawn could
## actually take it. That can only make two positions look different when they are the
## same, never the other way round, so repetition detection stays sound.
func position_key() -> int:
	_ensure_zobrist()
	var h := 0
	for sq in range(64):
		var p := int(squares[sq])
		if p != EMPTY:
			h ^= _zob_piece[p * 64 + sq]
	if side_to_move == BLACK:
		h ^= _zob_side
	h ^= _zob_castle[castling_rights]
	if ep_square >= 0:
		h ^= _zob_ep[ep_square & 7]
	return h


static func _ensure_rights_mask() -> void:
	if not _rights_mask.is_empty():
		return
	_rights_mask = PackedInt32Array()
	_rights_mask.resize(64)
	## Only the king and rook home squares carry rights: a move out of one, or a capture
	## onto one, is what destroys them.
	_rights_mask[0] = CASTLE_WQ
	_rights_mask[7] = CASTLE_WK
	_rights_mask[4] = CASTLE_WK | CASTLE_WQ
	_rights_mask[56] = CASTLE_BQ
	_rights_mask[63] = CASTLE_BK
	_rights_mask[60] = CASTLE_BK | CASTLE_BQ


static func _ensure_zobrist() -> void:
	if not _zob_piece.is_empty():
		return
	## Fixed seed: a saved game has to hash the same way in the next session.
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x43_48_45_53_53  # "CHESS"
	_zob_piece = PackedInt64Array()
	## Piece codes reach KING | BLACK = 22, so the table is indexed by code directly.
	_zob_piece.resize(24 * 64)
	for i in range(_zob_piece.size()):
		_zob_piece[i] = _rand64(rng)
	_zob_castle = PackedInt64Array()
	_zob_castle.resize(16)
	for i in range(16):
		_zob_castle[i] = _rand64(rng)
	_zob_ep = PackedInt64Array()
	_zob_ep.resize(8)
	for i in range(8):
		_zob_ep[i] = _rand64(rng)
	_zob_side = _rand64(rng)


static func _rand64(rng: RandomNumberGenerator) -> int:
	return (int(rng.randi()) << 32) | int(rng.randi())


# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------

## The opening position plus every move played from it. A snapshot FEN alone cannot resume
## a game correctly: threefold repetition is a property of the *history*, and a board
## rebuilt from one position would have forgotten the ones it already stood in. The current
## FEN rides along anyway, as a checksum on the replay.
func to_save_dict() -> Dictionary:
	return {
		"start_fen": start_fen,
		"fen": to_fen(),
		"phase": String(phase),
		"end_reason": end_reason,
		"moves": Array(move_list),
	}


## Null when the payload is not a chess game — resuming into a half-parsed board would be
## playing a different game than the save.
static func from_save_dict(data: Dictionary) -> ChessBoardState:
	var opening := str(data.get("start_fen", ""))
	if opening.is_empty():
		push_error("ChessBoardState.from_save_dict: no opening FEN in the payload")
		return null
	var raw: Variant = data.get("moves", [])
	if typeof(raw) != TYPE_ARRAY:
		push_error("ChessBoardState.from_save_dict: moves is not an array")
		return null
	var board := ChessBoardState.new()
	if not board.load_fen(opening):
		return null
	for entry: Variant in raw as Array:
		if not board._replay(int(entry)):
			return null
	var expected := str(data.get("fen", ""))
	if not expected.is_empty() and board.to_fen() != expected:
		push_error(
			"ChessBoardState.from_save_dict: replaying %d moves landed on %s, not the saved %s"
			% [board.move_list.size(), board.to_fen(), expected]
		)
		return null
	board.phase = StringName(str(data.get("phase", "playing")))
	board.end_reason = str(data.get("end_reason", ""))
	return board


## Re-apply one saved move: legality-checked, recorded, but silent. Views bind to the
## restored board and paint it once, rather than watching a game replay itself.
func _replay(move: int) -> bool:
	var legal := generate_legal_moves()
	if not legal.has(move):
		push_error(
			"ChessBoardState: saved move %s is not legal in %s"
			% [move_name(move), to_fen()]
		)
		return false
	make_move(move)
	_undo.resize(0)
	move_list.append(move)
	_keys.append(position_key())
	return true
