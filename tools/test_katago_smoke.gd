## Headless KataGo probe: 19x19, a few genmoves, no UI.
##
##   powershell -File tools\ensure_katago.ps1
##   powershell -File tools\run_test.ps1 -Scene test_katago_smoke -TimeoutSec 600
extends Node

const KatagoEngineScript := preload("res://scripts/city/katago_engine.gd")
const MOVES := 6
const BOARD := 19
const VISITS := 16


func _ready() -> void:
	var eng: KatagoEngine = KatagoEngineScript.new() as KatagoEngine
	print("KatagoSmoke: starting Eigen backend (visits=%d, board=%d)..." % [VISITS, BOARD])
	eng.start("eigen", VISITS)
	print("KatagoSmoke: engine name = %s" % eng.engine_name())
	eng.set_boardsize(BOARD)
	eng.clear_board()

	var colors: PackedStringArray = ["b", "w"]
	for i in range(MOVES):
		var color := colors[i % 2]
		var t0 := Time.get_ticks_msec()
		var vertex := eng.genmove(color)
		var dt := Time.get_ticks_msec() - t0
		print("KatagoSmoke: move %d %s -> %s (%d ms)" % [i + 1, color, vertex, dt])
		if vertex.is_empty():
			push_error("FAIL empty genmove")
			eng.stop()
			get_tree().quit(1)
			return

	eng.stop()
	print("RESULT: OK")
	get_tree().quit(0)
