## Unit-ish check for GoBoardState liberties / capture / GTP verts.
extends Node

const GoBoardStateScript := preload("res://scripts/city/go_board_state.gd")


func _ready() -> void:
	var b: GoBoardState = GoBoardStateScript.new() as GoBoardState
	b.setup(9)
	assert(b.try_play(GoBoardState.BLACK, "D5"), "black D5")
	assert(b.try_play(GoBoardState.WHITE, "E5"), "white E5")
	assert(b.at(3, 4) == GoBoardState.BLACK, "stone at D5")
	## Capture: surround a white stone.
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
	## Empty 9×9: White wins on komi alone under both tallies.
	b.setup(9)
	var jp: Dictionary = b.score_japanese(6.5)
	assert(is_equal_approx(float(jp["black"]), 0.0), "empty japanese black")
	assert(is_equal_approx(float(jp["white"]), 6.5), "empty japanese white komi")
	var cn: Dictionary = b.score_chinese(6.5)
	assert(is_equal_approx(float(cn["black"]), 0.0), "empty chinese black")
	assert(is_equal_approx(float(cn["white"]), 6.5), "empty chinese white komi")
	## One black stone owns every empty point as territory. Japanese = empties;
	## Chinese = empties + the stone itself.
	assert(b.try_play_xy(GoBoardState.BLACK, 4, 4))
	jp = b.score_japanese(6.5)
	cn = b.score_chinese(6.5)
	assert(is_equal_approx(float(jp["black"]), 80.0), "japanese territory around one stone")
	assert(is_equal_approx(float(cn["black"]), 81.0), "chinese adds the living stone")
	## A capture pays under Japanese (prisoner) even when the point is empty again.
	b.setup(5)
	assert(b.try_play_xy(GoBoardState.BLACK, 1, 0))
	assert(b.try_play_xy(GoBoardState.WHITE, 1, 1))
	assert(b.try_play_xy(GoBoardState.BLACK, 0, 1))
	assert(b.try_play_xy(GoBoardState.WHITE, 3, 3))
	assert(b.try_play_xy(GoBoardState.BLACK, 2, 1))
	assert(b.try_play_xy(GoBoardState.WHITE, 3, 2))
	assert(b.try_play_xy(GoBoardState.BLACK, 1, 2))
	assert(b.black_captures == 1, "fixture still captures once")
	jp = b.score_japanese(0.0)
	assert(float(jp["black"]) >= 1.0, "japanese includes the prisoner")
	## End panel toggles recount without replaying: Japanese first, Chinese optional.
	var result := GoMatchResult.from_board(b, "two_passes", 6.5)
	assert(result.rules == GoMatchResult.RULES_JAPANESE, "japanese is the default tally")
	result.set_rules(GoMatchResult.RULES_CHINESE)
	assert(result.rules == GoMatchResult.RULES_CHINESE, "chinese toggle sticks")
	assert(
		not is_equal_approx(result.black_japanese, result.black_chinese)
		or not is_equal_approx(result.white_japanese, result.white_chinese),
		"the two tallies must be able to disagree"
	)
	print("RESULT: OK")
	get_tree().quit(0)
