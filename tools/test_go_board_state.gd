## Unit-ish check for GoBoardState liberties / capture / GTP verts / scoring arithmetic.
## Life-and-death is KataGo's job — tests here only cover flood-fill with explicit dead marks.
extends Node

const GoBoardStateScript := preload("res://scripts/city/go_board_state.gd")


func _ready() -> void:
	_test_play_and_capture()
	_test_empty_and_one_stone()
	_test_prisoner_and_rules_toggle()
	_test_marked_dead_pocket()
	_test_dame_scores_for_neither()
	_test_seki_shared_liberty_is_dame()
	_test_jp_prisoner_vs_cn_area()
	_test_multiple_dead_in_one_pocket()
	_test_dead_both_colours()
	print("RESULT: OK")
	get_tree().quit(0)


func _none() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	return out


func _test_play_and_capture() -> void:
	var b: GoBoardState = GoBoardStateScript.new() as GoBoardState
	b.setup(9)
	assert(b.try_play(GoBoardState.BLACK, "D5"), "black D5")
	assert(b.try_play(GoBoardState.WHITE, "E5"), "white E5")
	assert(b.at(3, 4) == GoBoardState.BLACK, "stone at D5")
	b.setup(5)
	assert(b.try_play_xy(GoBoardState.BLACK, 1, 0))
	assert(b.try_play_xy(GoBoardState.WHITE, 1, 1))
	assert(b.try_play_xy(GoBoardState.BLACK, 0, 1))
	assert(b.try_play_xy(GoBoardState.WHITE, 3, 3))
	assert(b.try_play_xy(GoBoardState.BLACK, 2, 1))
	assert(b.try_play_xy(GoBoardState.WHITE, 3, 2))
	assert(b.try_play_xy(GoBoardState.BLACK, 1, 2))
	assert(b.at(1, 1) == GoBoardState.EMPTY, "white captured")
	assert(b.black_captures == 1, "black holds one prisoner")
	assert(b.white_captures == 0, "white has no prisoners")
	var v: String = GoBoardState.format_vertex(0, 0, 19)
	assert(v == "A1", "format A1 got %s" % v)
	var loc: Vector2i = GoBoardState.parse_vertex("C3", 19)
	assert(loc == Vector2i(2, 2), "parse C3")


func _test_empty_and_one_stone() -> void:
	var b: GoBoardState = GoBoardStateScript.new() as GoBoardState
	b.setup(9)
	var jp: Dictionary = b.score_japanese(6.5, _none())
	assert(is_equal_approx(float(jp["black"]), 0.0), "empty japanese black")
	assert(is_equal_approx(float(jp["white"]), 6.5), "empty japanese white komi")
	var cn: Dictionary = b.score_chinese(6.5, _none())
	assert(is_equal_approx(float(cn["black"]), 0.0), "empty chinese black")
	assert(is_equal_approx(float(cn["white"]), 6.5), "empty chinese white komi")
	assert(b.try_play_xy(GoBoardState.BLACK, 4, 4))
	jp = b.score_japanese(6.5, _none())
	cn = b.score_chinese(6.5, _none())
	assert(is_equal_approx(float(jp["black"]), 80.0), "japanese territory around one stone")
	assert(is_equal_approx(float(cn["black"]), 81.0), "chinese adds the living stone")


func _test_prisoner_and_rules_toggle() -> void:
	var b: GoBoardState = GoBoardStateScript.new() as GoBoardState
	b.setup(5)
	assert(b.try_play_xy(GoBoardState.BLACK, 1, 0))
	assert(b.try_play_xy(GoBoardState.WHITE, 1, 1))
	assert(b.try_play_xy(GoBoardState.BLACK, 0, 1))
	assert(b.try_play_xy(GoBoardState.WHITE, 3, 3))
	assert(b.try_play_xy(GoBoardState.BLACK, 2, 1))
	assert(b.try_play_xy(GoBoardState.WHITE, 3, 2))
	assert(b.try_play_xy(GoBoardState.BLACK, 1, 2))
	assert(b.black_captures == 1, "fixture still captures once")
	var jp: Dictionary = b.score_japanese(0.0, _none())
	assert(float(jp["black"]) >= 1.0, "japanese includes the prisoner")
	var result := GoMatchResult.from_board(b, "two_passes", 6.5, _none())
	assert(result.rules == GoMatchResult.RULES_JAPANESE, "japanese is the default tally")
	result.set_rules(GoMatchResult.RULES_CHINESE)
	assert(result.rules == GoMatchResult.RULES_CHINESE, "chinese toggle sticks")
	assert(
		not is_equal_approx(result.black_japanese, result.black_chinese)
		or not is_equal_approx(result.white_japanese, result.white_chinese),
		"the two tallies must be able to disagree"
	)


func _test_marked_dead_pocket() -> void:
	##   . B B B .
	##   B . W . B
	##   . B B B .
	var b := _board_with(
		5,
		[
			Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
			Vector2i(0, 1), Vector2i(4, 1),
			Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2),
		],
		[Vector2i(2, 1)]
	)
	var dead: Array[Vector2i] = [Vector2i(2, 1)]
	var jp: Dictionary = b.score_japanese(0.0, dead)
	var cn: Dictionary = b.score_chinese(0.0, dead)
	assert(int(jp["territory_black"]) >= 3, "dead pocket becomes black territory")
	assert(int(jp["captures_black"]) == 1, "marked dead white is a prisoner")
	assert(int(cn["stones_white"]) == 0, "chinese does not count the dead white stone")
	assert(b.at(2, 1) == GoBoardState.WHITE, "scoring must not lift stones off the live board")
	assert(b.black_captures == 0, "scoring must not mutate capture counters")
	var jp_alive: Dictionary = b.score_japanese(0.0, _none())
	assert(int(jp_alive["captures_black"]) == 0, "unmarked white is not a prisoner")
	assert(
		float(jp["black"]) > float(jp_alive["black"]),
		"marking the dead white must raise Black's score"
	)


## Empties that touch both colours are dame — neither side scores them.
##   B W
##   B W
##   . .   ← bottom row touches both via the column above / connections
func _test_dame_scores_for_neither() -> void:
	## Closed corridor: only the middle file is empty, and it borders B and W.
	##   B . W
	##   B . W
	##   B . W
	var b := _board_with(
		3,
		[Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)],
		[Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2)]
	)
	var jp: Dictionary = b.score_japanese(0.0, _none())
	assert(int(jp["territory_black"]) == 0, "dame corridor is not black territory")
	assert(int(jp["territory_white"]) == 0, "dame corridor is not white territory")
	var cn: Dictionary = b.score_chinese(0.0, _none())
	assert(int(cn["territory_black"]) == 0, "chinese dame black")
	assert(int(cn["territory_white"]) == 0, "chinese dame white")
	## Living stones still count under Chinese.
	assert(int(cn["stones_black"]) == 3, "chinese counts living black stones")
	assert(int(cn["stones_white"]) == 3, "chinese counts living white stones")


## Seki-shaped share: one empty touching both colours. Leaving both groups unmarked,
## that point is dame — not territory for either side.
##   B B B
##   B W .
##   B W B
##   B B B
func _test_seki_shared_liberty_is_dame() -> void:
	var b := _board_with(
		4,
		[
			Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
			Vector2i(0, 1),
			Vector2i(0, 2), Vector2i(2, 2),
			Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3),
		],
		[Vector2i(1, 1), Vector2i(1, 2)]
	)
	## Shared empty at (2,1) borders W and B.
	var jp: Dictionary = b.score_japanese(0.0, _none())
	assert(int(jp["territory_white"]) == 0, "seki eye is not white territory")
	assert(int(jp["captures_black"]) == 0, "unmarked seki white is not a prisoner")
	assert(int(jp["captures_white"]) == 0, "unmarked seki black is not a prisoner")
	## Marking white dead would invent a fight result — only the engine may do that.
	var falsely_dead: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 2)]
	var jp_kill: Dictionary = b.score_japanese(0.0, falsely_dead)
	assert(int(jp_kill["captures_black"]) == 2, "explicit marks still apply if the engine said so")
	assert(float(jp_kill["black"]) > float(jp["black"]), "killing seki white raises Black if marked")


## Same cleaned pocket: Japanese pays the prisoner; Chinese folds the point into area.
## Exact 3×3 with only the pocket and walls — no stray dame.
##   B B B
##   B W B
##   B B B
func _test_jp_prisoner_vs_cn_area() -> void:
	var b := _board_with(
		3,
		[
			Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
			Vector2i(0, 1), Vector2i(2, 1),
			Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
		],
		[Vector2i(1, 1)]
	)
	var dead: Array[Vector2i] = [Vector2i(1, 1)]
	var jp: Dictionary = b.score_japanese(0.0, dead)
	var cn: Dictionary = b.score_chinese(0.0, dead)
	## After removal: 1 empty (territory) + 8 living black stones.
	assert(int(jp["territory_black"]) == 1, "jp pocket territory got %s" % jp["territory_black"])
	assert(int(jp["captures_black"]) == 1, "jp prisoner")
	assert(is_equal_approx(float(jp["black"]), 2.0), "jp = 1 terr + 1 prisoner")
	assert(int(cn["territory_black"]) == 1, "cn pocket territory")
	assert(int(cn["stones_black"]) == 8, "cn living stones")
	assert(int(cn["stones_white"]) == 0, "cn dead stone gone")
	assert(is_equal_approx(float(cn["black"]), 9.0), "cn = 8 stones + 1 terr")
	## The classic JP/CN split on a fully surrounded dead stone: CN is +7 here (stones).
	assert(
		is_equal_approx(float(cn["black"]) - float(jp["black"]), 7.0),
		"cn area leads jp territory+prisoner by the living stones"
	)


## Two dead whites and the empties between them all become Black territory + 2 prisoners.
##   . B B B .
##   B W . W B
##   . B B B .
func _test_multiple_dead_in_one_pocket() -> void:
	var b := _board_with(
		5,
		[
			Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
			Vector2i(0, 1), Vector2i(4, 1),
			Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2),
		],
		[Vector2i(1, 1), Vector2i(3, 1)]
	)
	var dead: Array[Vector2i] = [Vector2i(1, 1), Vector2i(3, 1)]
	var jp: Dictionary = b.score_japanese(0.0, dead)
	assert(int(jp["captures_black"]) == 2, "two dead whites are two prisoners")
	assert(int(jp["territory_black"]) >= 3, "pocket empties + vacated points")
	assert(is_equal_approx(float(jp["black"]), float(jp["territory_black"]) + 2.0), "jp sums")


## Dead stones of both colours: each side gains the other's corpses as prisoners (JP).
func _test_dead_both_colours() -> void:
	## Two separate pockets on 5×5.
	## Black dead at A5 (top-left corner eye of white), white dead at E1 (bottom-right of black).
	var b: GoBoardState = GoBoardStateScript.new() as GoBoardState
	b.setup(5)
	## White surrounds top-left: empties would be only (0,4) with W around — place W wall + dead B.
	for p in [Vector2i(1, 4), Vector2i(0, 3), Vector2i(1, 3)]:
		b.set_at(p.x, p.y, GoBoardState.WHITE)
	b.set_at(0, 4, GoBoardState.BLACK)
	## Black surrounds bottom-right dead white.
	for p in [Vector2i(3, 0), Vector2i(4, 1), Vector2i(3, 1)]:
		b.set_at(p.x, p.y, GoBoardState.BLACK)
	b.set_at(4, 0, GoBoardState.WHITE)
	var dead: Array[Vector2i] = [Vector2i(0, 4), Vector2i(4, 0)]
	var jp: Dictionary = b.score_japanese(0.0, dead)
	assert(int(jp["captures_black"]) == 1, "black holds the dead white")
	assert(int(jp["captures_white"]) == 1, "white holds the dead black")
	var cn: Dictionary = b.score_chinese(0.0, dead)
	assert(int(cn["stones_black"]) == 3, "only living black remain")
	assert(int(cn["stones_white"]) == 3, "only living white remain")


func _board_with(n: int, black: Array, white: Array) -> GoBoardState:
	var b: GoBoardState = GoBoardStateScript.new() as GoBoardState
	b.setup(n)
	for p in black:
		b.set_at(p.x, p.y, GoBoardState.BLACK)
	for p in white:
		b.set_at(p.x, p.y, GoBoardState.WHITE)
	return b
