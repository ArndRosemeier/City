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

	eng.call("unload")
	print("RESULT: OK")
	get_tree().quit(0)
