## The monster-chess court end to end, minus the voxels: tap a square, watch a monster walk.
##
## Everything here goes through the same route the player does — `interact_at_world` with a
## world point, exactly what `CityWalker._try_world_interact` hands the court after an aimed
## shot. A test that called `try_move` directly would prove the rules (already covered by
## test_chess_rules) and nothing about whether a tap finds the right square.
##
## Run: powershell -File tools\run_test.ps1 test_chess_arena -TimeoutSec 300
extends Node

const ChessArenaScript := preload("res://scripts/city/chess_arena.gd")
const ChessBoardStateScript := preload("res://scripts/city/chess_board_state.gd")
const GamingLayoutScript := preload("res://scripts/city/gaming_layout.gd")

## Same pitch the bake uses: 8 voxels at 0.5 m is a 4 m square.
const SQUARE_VOX := 8
const VOXEL_SIZE := 0.5
## Ground course the court is painted into, well clear of zero so a sign error shows up.
const BOARD_Y_VOX := 6

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	var arena: ChessArena = _stage_court()
	_check_square_mapping(arena)
	_check_armies_stand(arena)
	await _check_hotseat_move(arena)
	await _check_capture_choreography(arena)
	await _check_ai_answers(arena)
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _stage_court() -> ChessArena:
	var layout: GamingLayout = GamingLayoutScript.new() as GamingLayout
	layout.chess_square_vox = SQUARE_VOX
	layout.chess_origin = Vector3i(24, BOARD_Y_VOX, 40)
	layout.chess_min = Vector3i(0, 0, 16)
	layout.chess_max = Vector3i(160, 0, 176)
	var arena: ChessArena = ChessArenaScript.new() as ChessArena
	arena.name = "ChessArena"
	add_child(arena)
	## A non-zero tile origin is the case that catches a court placed in district-local
	## voxels and read back in world metres.
	arena.setup(layout, Vector3i(784, 0, 560), VOXEL_SIZE, 7)
	return arena


## Every square must map to itself through world space, or a tap lands one file over and the
## player is told their own knight is not theirs.
func _check_square_mapping(arena: ChessArena) -> void:
	var bad := 0
	for rank in range(8):
		for file in range(8):
			var want := rank * 8 + file
			var got := arena.square_at_world(arena.square_world(file, rank))
			if got != want:
				bad += 1
				if bad == 1:
					_fail(
						"FAIL %s round-trips to %d, expected %d"
						% [ChessBoardStateScript.square_name(want), got, want]
					)
	if bad == 0:
		print("OK all 64 square centres round-trip through world space")
	var span := float(arena.layout.chess_span_vox()) * VOXEL_SIZE
	var sw := arena.square_world(0, 0)
	## Just outside the a1 corner is off the board, not clamped onto it.
	if arena.square_at_world(sw - Vector3(span, 0.0, 0.0)) != -1:
		_fail("FAIL a point west of the board reported a square")
	if arena.square_at_world(sw + Vector3(0.0, 0.0, span * 2.0)) != -1:
		_fail("FAIL a point north of the board reported a square")


func _check_armies_stand(arena: ChessArena) -> void:
	var standing := 0
	for sq in range(64):
		if arena.actor_at(sq) != null:
			standing += 1
	if standing != 32:
		_fail("FAIL %d puppets on the board, expected 32" % standing)
		return
	var king: ChessPieceActor = arena.actor_at(ChessBoardStateScript.square_from_name("e1"))
	if king == null or king.piece_type != ChessBoardStateScript.KING:
		_fail("FAIL e1 is not holding a king")
		return
	if king.colour != ChessBoardStateScript.WHITE:
		_fail("FAIL the king on e1 is not white")
		return
	## The king is the tallest thing on the board, which is the whole point of normalising.
	var pawn: ChessPieceActor = arena.actor_at(ChessBoardStateScript.square_from_name("e2"))
	if pawn == null or pawn.stand_height() >= king.stand_height():
		_fail("FAIL the pawn on e2 is not shorter than the king")
		return
	print(
		"OK 32 puppets stand, king %.2f m over pawn %.2f m"
		% [king.stand_height(), pawn.stand_height()]
	)


## Two taps: pick up the e2 pawn, put it on e4. This is the whole player-facing loop.
func _check_hotseat_move(arena: ChessArena) -> void:
	arena.begin_hotseat()
	var e2 := ChessBoardStateScript.square_from_name("e2")
	var e4 := ChessBoardStateScript.square_from_name("e4")
	if not arena.interact_at_world(_tap(arena, e2)):
		_fail("FAIL tapping own pawn on e2 was refused")
		return
	if arena.selected_square() != e2:
		_fail("FAIL tapping e2 selected %d" % arena.selected_square())
		return
	if not arena.legal_destinations().has(e4):
		_fail("FAIL e4 is not offered as a destination for the e2 pawn")
		return
	arena.interact_at_world(_tap(arena, e4))
	if not arena.is_animating():
		_fail("FAIL tapping e4 did not start a move")
		return
	await _settle(arena)
	if arena.board().to_fen().begins_with("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b"):
		print("OK e2-e4 walked and the board agrees")
	else:
		_fail("FAIL after e2-e4 the board is %s" % arena.board().to_fen())
		return
	if arena.actor_at(e2) != null:
		_fail("FAIL a puppet is still standing on e2")
		return
	var moved: ChessPieceActor = arena.actor_at(e4)
	if moved == null:
		_fail("FAIL nothing is standing on e4")
		return
	var want := arena.square_world(4, 3)
	if moved.global_position.distance_to(want) > 0.1:
		_fail("FAIL the e4 pawn stopped at %s, wanted %s" % [moved.global_position, want])
		return
	if moved.square != Vector2i(4, 3):
		_fail("FAIL the e4 pawn reports square %s" % moved.square)


## 1...d5 2.exd5: the pawn walks up, swings, and the defender is gone rather than vanishing
## the instant the rules said so.
func _check_capture_choreography(arena: ChessArena) -> void:
	var d7 := ChessBoardStateScript.square_from_name("d7")
	var d5 := ChessBoardStateScript.square_from_name("d5")
	arena.interact_at_world(_tap(arena, d7))
	arena.interact_at_world(_tap(arena, d5))
	await _settle(arena)
	if arena.actor_at(d5) == null:
		_fail("FAIL black's d5 pawn did not arrive")
		return
	var victim: ChessPieceActor = arena.actor_at(d5)
	var e4 := ChessBoardStateScript.square_from_name("e4")
	arena.interact_at_world(_tap(arena, e4))
	if not arena.legal_destinations().has(d5):
		_fail("FAIL exd5 is not offered as a capture")
		return
	arena.interact_at_world(_tap(arena, d5))
	await _settle(arena)
	if is_instance_valid(victim):
		_fail("FAIL the captured pawn is still in the tree")
		return
	var winner: ChessPieceActor = arena.actor_at(d5)
	if winner == null or winner.colour != ChessBoardStateScript.WHITE:
		_fail("FAIL d5 is not held by the white pawn that took it")
		return
	var standing := 0
	for sq in range(64):
		if arena.actor_at(sq) != null:
			standing += 1
	if standing != 31:
		_fail("FAIL %d puppets after a capture, expected 31" % standing)
		return
	print("OK exd5 played its melee and the defender was freed")


## Hand black to the search and check it answers with something the board accepts. The point
## is the wiring — the thread handshake, the reply, the animation — not the move's quality.
func _check_ai_answers(arena: ChessArena) -> void:
	arena.begin_versus_ai(true, &"casual")
	var e2 := ChessBoardStateScript.square_from_name("e2")
	var e4 := ChessBoardStateScript.square_from_name("e4")
	arena.interact_at_world(_tap(arena, e2))
	arena.interact_at_world(_tap(arena, e4))
	await _settle(arena)
	var board := arena.board()
	## White's move has landed; now black is the search's problem.
	var deadline := Time.get_ticks_msec() + 60000
	while board.move_list.size() < 2 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if board.move_list.size() < 2:
		_fail("FAIL the AI never moved")
		return
	await _settle(arena)
	if board.side_to_move != ChessBoardStateScript.WHITE:
		_fail("FAIL it is not white's turn after the AI replied")
		return
	var reply := board.move_list[1]
	var landed := ChessBoardStateScript.move_to(reply)
	if arena.actor_at(landed) == null:
		_fail(
			"FAIL the AI played %s but nothing is standing on it"
			% ChessBoardStateScript.move_name(reply)
		)
		return
	print("OK the AI answered with %s and its puppet walked" % ChessBoardStateScript.move_name(reply))


## World point an aimed shot would report for a square: the centre, on the click slab.
func _tap(arena: ChessArena, sq: int) -> Vector3:
	var at := ChessBoardStateScript.vec_of(sq)
	var world := arena.square_world(at.x, at.y)
	return world + Vector3(0.0, ChessArena.CLICK_LIFT, 0.0)


## Wait out the move animation. Walking a few squares plus a melee is seconds of wall clock,
## so the ceiling is generous — but it is a ceiling, because a choreography that never
## finishes is exactly the failure this guards against.
func _settle(arena: ChessArena) -> void:
	var deadline := Time.get_ticks_msec() + 40000
	while arena.is_animating() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if arena.is_animating():
		_fail("FAIL a move animation never finished")
