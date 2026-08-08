## GoEnginePool.shutdown must return without blocking on katago_destroy, and must not
## free the native handle under an in-flight WorkerThreadPool search.
##
## Run: powershell -File tools\run_test.ps1 test_go_engine_unload
extends Node

const GoEnginePoolScript := preload("res://scripts/city/go_engine_pool.gd")
const GoSessionScript := preload("res://scripts/city/go_session.gd")

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	await _run()
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		print("RESULT: OK")
		get_tree().quit(0)


func _run() -> void:
	_test_shutdown_idempotent()
	await _test_shutdown_off_main_when_loaded()
	await _test_join_before_unload()


func _test_shutdown_idempotent() -> void:
	GoEnginePoolScript.shutdown()
	GoEnginePoolScript.shutdown()
	if GoEnginePoolScript.is_ready():
		_fail("FAIL shutdown left the pool ready")
	if GoEnginePoolScript.is_busy():
		## A prior test may have kicked unload; wait it out below when needed.
		pass


func _test_shutdown_off_main_when_loaded() -> void:
	if not ClassDB.class_exists(&"NativeKataGo"):
		print("GoEngineUnload: NativeKataGo missing — skip loaded-unload timing")
		return
	var model := ProjectSettings.globalize_path("res://tools/katago/b18c384nbt-humanv0.bin.gz")
	if not FileAccess.file_exists(model):
		print("GoEngineUnload: human model missing — skip loaded-unload timing")
		return
	## Drain any prior unload so acquire is not racing the last test.
	while GoEnginePoolScript.is_busy():
		await get_tree().process_frame
	var eng: Object = GoEnginePoolScript.acquire("5k")
	if eng == null or not GoEnginePoolScript.is_ready():
		_fail("FAIL acquire did not load KataGo")
		return
	var t0 := Time.get_ticks_msec()
	GoEnginePoolScript.shutdown()
	var elapsed := Time.get_ticks_msec() - t0
	## Destroying the Human-SL net on the main thread used to take multi-seconds.
	## Shutdown itself must only schedule the worker.
	if elapsed > 250:
		_fail("FAIL shutdown blocked the main thread for %d ms" % elapsed)
		return
	print("GoEngineUnload: shutdown returned in %d ms (unload continues off-main)" % elapsed)
	var guard := 0
	while GoEnginePoolScript.is_busy() and guard < 1200:
		await get_tree().process_frame
		guard += 1
	if GoEnginePoolScript.is_busy():
		_fail("FAIL unload worker did not finish")
		return
	if GoEnginePoolScript.is_ready():
		_fail("FAIL pool still ready after unload")


func _test_join_before_unload() -> void:
	## Fake an in-flight search with a slow WorkerThreadPool task, then end_session(unload)
	## and assert the task finished before shutdown was allowed to proceed.
	var session: Node = GoSessionScript.new()
	add_child(session)
	var mutex := Mutex.new()
	var state := {"done": false, "joined_before_done": false}
	var task_id := WorkerThreadPool.add_task(
		func() -> void:
			OS.delay_msec(120)
			mutex.lock()
			state["done"] = true
			mutex.unlock()
	)
	session.set("_search_task_id", task_id)
	## end_session joins the task synchronously before touching the pool.
	session.call("end_session", "unload")
	mutex.lock()
	var done: bool = bool(state["done"])
	mutex.unlock()
	if not done:
		_fail("FAIL end_session(unload) returned before the search worker finished")
	if int(session.get("_search_task_id")) != -1:
		_fail("FAIL search task id was not cleared after join")
	session.queue_free()
	## Let pool unload (if any) settle so later tests / process exit stay clean.
	var guard := 0
	while GoEnginePoolScript.is_busy() and guard < 1200:
		await get_tree().process_frame
		guard += 1
