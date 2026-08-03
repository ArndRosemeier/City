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
