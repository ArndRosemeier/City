## Process-wide refcounted NativeKataGo handle (Human-SL rank ladder).
## Model load runs on WorkerThreadPool so match start stays hitch-free.
## Unload also runs off the main thread — stream-out must not block on
## `katago_destroy` / NNEvaluator teardown (multi-second hitches).
class_name GoEnginePool
extends RefCounted

const GoRankScript := preload("res://scripts/city/go_rank.gd")

## Fixed visit budget for Human-SL play (pass/resign + light search). Rank sets strength.
const HUMAN_VISITS := 40

static var _refs: int = 0
static var _eng: Object = null
static var _rank: String = "5k"
static var _loading: bool = false
static var _monitor_running: bool = false
static var _load_task_id: int = -1
static var _load_mutex: Mutex = Mutex.new()
static var _load_state: Dictionary = {"done": true, "ok": false}
## When true, the in-flight loader must unload as soon as it finishes.
static var _shutdown_pending: bool = false
## Background `katago_destroy` in flight (district stream-out).
static var _unloading: bool = false
static var _unload_task_id: int = -1
static var _unload_monitor_running: bool = false


static func is_ready() -> bool:
	return (
		_eng != null
		and is_instance_valid(_eng)
		and bool(_eng.call("is_loaded"))
	)


## True while a background load or unload still owns the native handle.
static func is_busy() -> bool:
	return _loading or _unloading


## Synchronous load (blocks the calling thread). Prefer `acquire_async` from gameplay.
static func acquire(rank: String) -> Object:
	if not ClassDB.class_exists(&"NativeKataGo"):
		push_error("GoEnginePool: NativeKataGo missing — build tools/build_city_katago.ps1")
		return null
	## Sync callers (tests) must not race a stream-out unload still tearing down the net.
	_join_unload_if_pending()
	var token := normalize_rank(rank)
	_refs += 1
	_shutdown_pending = false
	if is_ready():
		_eng.call("set_rank", token)
		_rank = token
		return _eng
	if _eng == null:
		_eng = ClassDB.instantiate(&"NativeKataGo")
		if _eng == null:
			push_error("GoEnginePool: instantiate failed")
			_refs = maxi(_refs - 1, 0)
			return null
	if _loading:
		push_error("GoEnginePool.acquire: background load already in progress — use acquire_async")
		_refs = maxi(_refs - 1, 0)
		return null
	var model := ProjectSettings.globalize_path("res://tools/katago/b18c384nbt-humanv0.bin.gz")
	var cfg := ProjectSettings.globalize_path("res://addons/city_katago/human_rank.cfg")
	if not FileAccess.file_exists(model):
		push_error("GoEnginePool: missing human model %s — run tools/ensure_katago.ps1" % model)
		_refs = maxi(_refs - 1, 0)
		_eng = null
		return null
	if not bool(_eng.call("load", model, cfg, HUMAN_VISITS)):
		push_error("GoEnginePool: NativeKataGo.load failed")
		_refs = maxi(_refs - 1, 0)
		_eng = null
		return null
	_eng.call("set_rank", token)
	_rank = token
	return _eng


## Begin (or join) a background load. Returns the engine once ready, or null.
## Call as `await GoEnginePool.acquire_async(self, rank)` from a Node.
static func acquire_async(host: Node, rank: String) -> Object:
	if not ClassDB.class_exists(&"NativeKataGo"):
		push_error("GoEnginePool: NativeKataGo missing — build tools/build_city_katago.ps1")
		return null
	if host == null or not is_instance_valid(host):
		push_error("GoEnginePool.acquire_async: host Node required")
		return null
	var token := normalize_rank(rank)
	_refs += 1
	_shutdown_pending = false
	## Wait out a district-unload destroy so we do not instantiate a second net on top of it.
	while _unloading:
		if not is_instance_valid(host) or not host.is_inside_tree():
			release()
			return null
		await host.get_tree().process_frame
	if is_ready():
		_eng.call("set_rank", token)
		_rank = token
		return _eng
	if _eng == null:
		_eng = ClassDB.instantiate(&"NativeKataGo")
		if _eng == null:
			push_error("GoEnginePool: instantiate failed")
			_refs = maxi(_refs - 1, 0)
			return null
	if not _loading and not is_ready():
		if not _kick_background_load(token):
			_refs = maxi(_refs - 1, 0)
			_eng = null
			return null
	while _loading:
		if not is_instance_valid(host) or not host.is_inside_tree():
			release()
			return null
		await host.get_tree().process_frame
	if _shutdown_pending or _unloading or not is_ready():
		release()
		return null
	_eng.call("set_rank", token)
	_rank = token
	return _eng


## Drop one session ref. Keeps the neural net loaded for the next match.
static func release() -> void:
	_refs = maxi(_refs - 1, 0)


## Unload the net (district stream-out / process exit). Safe with zero refs.
## Returns immediately; `katago_destroy` runs on WorkerThreadPool.
static func shutdown() -> void:
	_refs = 0
	_shutdown_pending = true
	if _loading:
		## `_monitor_load` will begin unload when the load task finishes.
		return
	_begin_unload()


static func normalize_rank(rank: String) -> String:
	var t := rank.strip_edges().to_lower()
	if t.begins_with("rank_"):
		t = t.substr(5)
	for r in GoRankScript.RANKS:
		if String(r) == t:
			return t
	push_warning("GoEnginePool: unknown rank '%s', using 5k" % rank)
	return "5k"


## Detach the pool ref and destroy the native handle off the main thread.
static func _begin_unload() -> void:
	if _unloading:
		return
	var eng := _eng
	_eng = null
	_rank = "5k"
	if eng == null or not is_instance_valid(eng):
		_shutdown_pending = false
		return
	_unloading = true
	## Capture keeps the RefCounted alive until unload finishes; Drop is then a no-op.
	_unload_task_id = WorkerThreadPool.add_task(
		func() -> void:
			if eng != null and is_instance_valid(eng):
				eng.call("unload")
	)
	if not _unload_monitor_running:
		_unload_monitor_running = true
		_monitor_unload()


## Join the unload worker exactly once (monitor or a sync acquire — not both).
static func _join_unload_if_pending() -> void:
	var id := _unload_task_id
	if id < 0:
		return
	_unload_task_id = -1
	WorkerThreadPool.wait_for_task_completion(id)
	_unloading = false
	_shutdown_pending = false


static func _monitor_unload() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	while true:
		var id := _unload_task_id
		if id < 0:
			break
		if WorkerThreadPool.is_task_completed(id):
			break
		if tree != null:
			await tree.process_frame
		else:
			OS.delay_msec(5)
	_join_unload_if_pending()
	_unload_monitor_running = false


static func _kick_background_load(rank: String) -> bool:
	var model := ProjectSettings.globalize_path("res://tools/katago/b18c384nbt-humanv0.bin.gz")
	var cfg := ProjectSettings.globalize_path("res://addons/city_katago/human_rank.cfg")
	if not FileAccess.file_exists(model):
		push_error("GoEnginePool: missing human model %s — run tools/ensure_katago.ps1" % model)
		return false
	_loading = true
	_load_mutex.lock()
	_load_state = {"done": false, "ok": false}
	_load_mutex.unlock()
	var eng := _eng
	var visits := HUMAN_VISITS
	_load_task_id = WorkerThreadPool.add_task(
		func() -> void:
			var ok := false
			if eng != null and is_instance_valid(eng):
				ok = bool(eng.call("load", model, cfg, visits))
				if ok:
					eng.call("set_rank", rank)
			_load_mutex.lock()
			_load_state["ok"] = ok
			_load_state["done"] = true
			_load_mutex.unlock()
	)
	if not _monitor_running:
		_monitor_running = true
		_monitor_load()
	return true


## Fire-and-forget: finishes the worker task and clears `_loading` even if no awaiter remains.
static func _monitor_load() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	while true:
		_load_mutex.lock()
		var done: bool = bool(_load_state["done"])
		_load_mutex.unlock()
		if done:
			break
		if tree != null:
			await tree.process_frame
		else:
			OS.delay_msec(5)
	if _load_task_id >= 0:
		WorkerThreadPool.wait_for_task_completion(_load_task_id)
		_load_task_id = -1
	_load_mutex.lock()
	var ok: bool = bool(_load_state["ok"])
	_load_mutex.unlock()
	if not ok:
		push_error("GoEnginePool: NativeKataGo.load failed")
	_loading = false
	_monitor_running = false
	## Failed load or stream-out during load: destroy any wrapper/handle off-main.
	if _shutdown_pending or not ok:
		_begin_unload()
