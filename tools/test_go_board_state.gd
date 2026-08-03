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
	var v: String = GoBoardState.format_vertex(0, 0, 19)
	assert(v == "A1", "format A1 got %s" % v)
	var loc: Vector2i = GoBoardState.parse_vertex("C3", 19)
	assert(loc == Vector2i(2, 2), "parse C3")
	print("RESULT: OK")
	get_tree().quit(0)
