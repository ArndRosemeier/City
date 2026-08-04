## Headless in-process KataGo Human-SL smoke via NativeKataGo GDExtension.
##
##   powershell -File tools\build_city_katago.ps1
##   powershell -File tools\ensure_katago.ps1
##   powershell -File tools\run_test.ps1 -Scene test_katago_gdextension -TimeoutSec 600
extends Node

const BOARD := 19
const VISITS := 40


func _ready() -> void:
	if not ClassDB.class_exists(&"NativeKataGo"):
		push_error("FAIL NativeKataGo class missing - build tools/build_city_katago.ps1 and ensure .godot/extension_list.cfg lists city_katago.gdextension")
		get_tree().quit(1)
		return

	var eng: Object = ClassDB.instantiate(&"NativeKataGo")
	print("KatagoGdext: version = %s" % eng.call("version"))

	var model := ProjectSettings.globalize_path("res://tools/katago/b18c384nbt-humanv0.bin.gz")
	var cfg := ProjectSettings.globalize_path("res://addons/city_katago/human_rank.cfg")
	if not FileAccess.file_exists(model):
		push_error("FAIL missing human model %s - run tools/ensure_katago.ps1" % model)
		get_tree().quit(1)
		return

	print("KatagoGdext: loading Human-SL embed (visits=%d, board=%d)..." % [VISITS, BOARD])
	if not bool(eng.call("load", model, cfg, VISITS)):
		push_error("FAIL NativeKataGo.load")
		get_tree().quit(1)
		return

	eng.call("set_boardsize", BOARD)
	eng.call("clear_board")
	eng.call("set_rank", "10k")
	var t0 := Time.get_ticks_msec()
	var v1 := str(eng.call("genmove", "b"))
	print("KatagoGdext: rank 10k black -> %s (%d ms)" % [v1, Time.get_ticks_msec() - t0])
	if v1.is_empty():
		push_error("FAIL empty genmove at 10k")
		eng.call("unload")
		get_tree().quit(1)
		return

	eng.call("set_rank", "2d")
	t0 = Time.get_ticks_msec()
	var v2 := str(eng.call("genmove", "w"))
	print("KatagoGdext: rank 2d white -> %s (%d ms)" % [v2, Time.get_ticks_msec() - t0])
	if v2.is_empty():
		push_error("FAIL empty genmove at 2d")
		eng.call("unload")
		get_tree().quit(1)
		return

	if not _check_genmove_eval(eng):
		eng.call("unload")
		get_tree().quit(1)
		return

	if not _check_scoring_cases(eng):
		eng.call("unload")
		get_tree().quit(1)
		return

	eng.call("unload")
	print("RESULT: OK")
	get_tree().quit(0)


## genmove_eval must hand back the same move plus the root stats that search already had.
func _check_genmove_eval(eng: Object) -> bool:
	if not eng.has_method("genmove_eval"):
		push_error("FAIL NativeKataGo.genmove_eval missing - rebuild tools/build_city_katago.ps1")
		return false
	var t0 := Time.get_ticks_msec()
	var reply: Dictionary = eng.call("genmove_eval", "b")
	var vertex := str(reply.get("vertex", ""))
	var eval_json := str(reply.get("eval_json", ""))
	print(
		"KatagoGdext: genmove_eval black -> %s (%d ms) json=%s"
		% [vertex, Time.get_ticks_msec() - t0, eval_json]
	)
	if vertex.is_empty():
		push_error("FAIL genmove_eval returned no vertex")
		return false
	var snap: GoEvalSnapshot = GoEvalSnapshot.from_engine_json(
		eval_json, GoBoardState.BLACK, vertex, BOARD
	)
	if snap == null:
		push_error("FAIL genmove_eval produced no usable snapshot: %s" % eval_json)
		return false
	if snap.visits <= 0:
		push_error("FAIL snapshot reports %d visits" % snap.visits)
		return false
	if snap.winrate_black <= 0.0 or snap.winrate_black >= 1.0:
		push_error("FAIL implausible Black winrate %f" % snap.winrate_black)
		return false
	if absf(snap.lead_black) > 400.0:
		push_error("FAIL implausible Black lead %f" % snap.lead_black)
		return false
	if snap.candidates.is_empty():
		push_error("FAIL snapshot has no candidate moves")
		return false
	for cand in snap.candidates:
		if cand.vertex != "pass" and not cand.is_on_board():
			push_error("FAIL candidate '%s' is not a board vertex" % cand.vertex)
			return false
	print(
		"KatagoGdext: %s / %s over %d candidates (best %s, %d visits)"
		% [
			snap.winrate_line(),
			snap.lead_line(),
			snap.candidates.size(),
			snap.candidates[0].vertex,
			snap.candidates[0].visits,
		]
	)
	return true


## Tricky life-and-death / scoring fixtures. Ownership search must agree with the labels.
func _check_scoring_cases(eng: Object) -> bool:
	if not eng.has_method("final_status_list") or not eng.has_method("final_score"):
		push_error("FAIL NativeKataGo scoring methods missing - rebuild tools/build_city_katago.ps1")
		return false
	if not eng.has_method("set_komi"):
		push_error("FAIL NativeKataGo.set_komi missing - rebuild tools/build_city_katago.ps1")
		return false
	if not _case_dead_in_pocket(eng):
		return false
	if not _case_two_eye_lives(eng):
		return false
	if not _case_two_dead_in_pocket(eng):
		return false
	if not _case_empty_finished_status(eng):
		return false
	return true


func _status(eng: Object) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var dead := str(eng.call("final_status_list", "dead")).strip_edges()
	var alive := str(eng.call("final_status_list", "alive")).strip_edges()
	var score := str(eng.call("final_score")).strip_edges()
	print(
		"KatagoGdext: dead=[%s] alive=[%s] score=%s (%d ms)"
		% [dead, alive, score, Time.get_ticks_msec() - t0]
	)
	return {"dead": dead.to_upper(), "alive": alive.to_upper(), "score": score}


func _has_vertex(listing: String, vertex: String) -> bool:
	var needle := vertex.to_upper()
	if listing == needle:
		return true
	return (" " + listing + " ").find(" " + needle + " ") >= 0


## Dead white in a black pocket.
##   . B B B .     (row 3)
##   B . W . B     (row 2)  W = C2
##   . B B B .     (row 1)
func _case_dead_in_pocket(eng: Object) -> bool:
	print("KatagoGdext: case dead-in-pocket")
	eng.call("set_boardsize", 5)
	eng.call("clear_board")
	eng.call("set_komi", 6.5)
	for v in ["B1", "C1", "D1", "A2"]:
		eng.call("play", "b", v)
		eng.call("play", "w", "pass")
	eng.call("play", "b", "E2")
	eng.call("play", "w", "C2")
	for v in ["B3", "C3", "D3"]:
		eng.call("play", "b", v)
		eng.call("play", "w", "pass")
	eng.call("play", "b", "pass")
	eng.call("play", "w", "pass")
	var st: Dictionary = _status(eng)
	if not _has_vertex(str(st["dead"]), "C2"):
		push_error("FAIL dead-in-pocket: expected dead C2 in '%s'" % st["dead"])
		return false
	if str(st["score"]).is_empty():
		push_error("FAIL dead-in-pocket: empty final_score")
		return false
	return true


## Solid two-eye living white sealed by a black wall — must not be marked dead.
##   W W W W B .
##   W . W W B .
##   W W . W B .
##   W W W W B .
##   B B B B B .
## Eyes at B2 and C3.
func _case_two_eye_lives(eng: Object) -> bool:
	print("KatagoGdext: case two-eye-lives")
	eng.call("set_boardsize", 6)
	eng.call("clear_board")
	eng.call("set_komi", 6.5)
	var white_stones := [
		"A1", "B1", "C1", "D1",
		"A2", "C2", "D2",
		"A3", "B3", "D3",
		"A4", "B4", "C4", "D4",
	]
	eng.call("play", "b", "pass")
	for v in white_stones:
		eng.call("play", "w", v)
		eng.call("play", "b", "pass")
	## White to play after the last Black pass — hand the turn back before the wall.
	eng.call("play", "w", "pass")
	for v in ["E1", "E2", "E3", "E4", "A5", "B5", "C5", "D5", "E5"]:
		eng.call("play", "b", v)
		eng.call("play", "w", "pass")
	eng.call("play", "b", "pass")
	eng.call("play", "w", "pass")
	var st: Dictionary = _status(eng)
	for v in white_stones:
		if _has_vertex(str(st["dead"]), v):
			push_error("FAIL two-eye-lives: %s wrongly dead in '%s'" % [v, st["dead"]])
			return false
	## Spot-check the eyes are not reported as dead stones, and a wall stone is alive.
	if _has_vertex(str(st["dead"]), "B2") or _has_vertex(str(st["dead"]), "C3"):
		push_error("FAIL two-eye-lives: empty eye listed as dead")
		return false
	if not _has_vertex(str(st["alive"]), "A1"):
		push_error("FAIL two-eye-lives: expected alive A1 in '%s'" % st["alive"])
		return false
	return true


## Two dead whites in one black pocket (and the gap between them).
##   . B B B .
##   B W . W B
##   . B B B .
func _case_two_dead_in_pocket(eng: Object) -> bool:
	print("KatagoGdext: case two-dead-in-pocket")
	eng.call("set_boardsize", 5)
	eng.call("clear_board")
	eng.call("set_komi", 6.5)
	for v in ["B1", "C1", "D1", "A2"]:
		eng.call("play", "b", v)
		eng.call("play", "w", "pass")
	eng.call("play", "b", "E2")
	eng.call("play", "w", "B2")
	eng.call("play", "b", "pass")
	eng.call("play", "w", "D2")
	for v in ["B3", "C3", "D3"]:
		eng.call("play", "b", v)
		eng.call("play", "w", "pass")
	eng.call("play", "b", "pass")
	eng.call("play", "w", "pass")
	var st: Dictionary = _status(eng)
	for v in ["B2", "D2"]:
		if not _has_vertex(str(st["dead"]), v):
			push_error("FAIL two-dead-in-pocket: expected dead %s in '%s'" % [v, st["dead"]])
			return false
	for v in ["B1", "C1", "D1", "A2", "E2", "B3", "C3", "D3"]:
		if _has_vertex(str(st["dead"]), v):
			push_error("FAIL two-dead-in-pocket: living black %s marked dead" % v)
			return false
	return true


## Finished empty board: no stones to mark. (Exact komi is local arithmetic —
## Japanese encore makes GTP final_score a lead estimate, not W+6.5.)
func _case_empty_finished_status(eng: Object) -> bool:
	print("KatagoGdext: case empty-finished-status")
	eng.call("set_boardsize", 9)
	eng.call("clear_board")
	eng.call("set_komi", 6.5)
	eng.call("play", "b", "pass")
	eng.call("play", "w", "pass")
	var st: Dictionary = _status(eng)
	if not str(st["dead"]).is_empty():
		push_error("FAIL empty-finished-status: dead list should be empty, got '%s'" % st["dead"])
		return false
	if not str(st["alive"]).is_empty():
		push_error("FAIL empty-finished-status: alive list should be empty, got '%s'" % st["alive"])
		return false
	if str(st["score"]).is_empty():
		push_error("FAIL empty-finished-status: empty final_score")
		return false
	return true
