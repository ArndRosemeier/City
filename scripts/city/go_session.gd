## One Go table session: BoardState + optional KataGo Human-SL + mode.
class_name GoSession
extends Node

const GoEnginePoolScript := preload("res://scripts/city/go_engine_pool.gd")
const GoRankScript := preload("res://scripts/city/go_rank.gd")

signal ai_thinking(on: bool)
signal session_ended(reason: String)

enum Mode { PLAYER_VS_PED, PED_VS_PED }

var mode: int = Mode.PLAYER_VS_PED
## Ped outfit / invite preset id (novice/club/dan).
var tier: StringName = &"novice"
## Human-SL rank token ("20k"…"9d").
var rank: String = "5k"
var board: GoBoardState = null
var player_is_black: bool = true
var _eng: Object = null
var _busy: bool = false
var _owned_engine: bool = false
var _ambient_timer: float = 0.0
const AMBIENT_MOVE_SEC := 2.8


func begin(
	p_mode: int,
	p_tier: StringName = &"novice",
	n: int = 19,
	p_rank: String = ""
) -> bool:
	mode = p_mode
	tier = p_tier
	rank = GoEnginePoolScript.normalize_rank(
		p_rank if not p_rank.strip_edges().is_empty() else GoRankScript.preset_rank(p_tier)
	)
	board = GoBoardState.new()
	board.setup(n)
	_owned_engine = false
	## Ped-vs-ped ambient uses local random play — one NativeKataGo board cannot
	## back multiple concurrent sessions.
	if mode == Mode.PLAYER_VS_PED:
		_eng = GoEnginePoolScript.acquire(rank)
		if _eng == null:
			push_warning("GoSession: no KataGo — player moves only until rebuild")
		else:
			_owned_engine = true
			_eng.call("set_boardsize", n)
			_eng.call("clear_board")
	_busy = false
	if mode == Mode.PED_VS_PED:
		_ambient_timer = 0.6
		set_process(true)
	else:
		set_process(false)
	return true


func end_session(reason: String = "leave") -> void:
	set_process(false)
	if _owned_engine:
		GoEnginePoolScript.release()
		_owned_engine = false
	_eng = null
	session_ended.emit(reason)


func rank_label() -> String:
	return GoRankScript.label(rank)


func player_to_move() -> bool:
	if mode != Mode.PLAYER_VS_PED or board == null:
		return false
	var want := GoBoardState.BLACK if player_is_black else GoBoardState.WHITE
	return board.next_color == want and board.phase == &"playing"


func try_player_vertex(vertex: String) -> bool:
	if _busy or board == null or not player_to_move():
		return false
	var color := board.next_color
	if not board.try_play(color, vertex):
		return false
	_sync_engine_play(color, vertex)
	if board.phase == &"playing":
		_request_ai_move()
	return true


func try_player_pass() -> bool:
	return try_player_vertex("pass")


func try_player_resign() -> bool:
	return try_player_vertex("resign")


func _process(delta: float) -> void:
	if mode != Mode.PED_VS_PED or board == null or board.phase != &"playing":
		return
	if _busy:
		return
	_ambient_timer -= delta
	if _ambient_timer > 0.0:
		return
	_ambient_timer = AMBIENT_MOVE_SEC
	_request_ai_move()


func _request_ai_move() -> void:
	if _busy or board == null or board.phase != &"playing":
		return
	_busy = true
	ai_thinking.emit(true)
	## Let poses / UI update before kicking a potentially long genmove.
	await get_tree().process_frame
	var color := board.next_color
	var color_s := "b" if color == GoBoardState.BLACK else "w"
	var used_engine := (
		_eng != null and is_instance_valid(_eng) and bool(_eng.call("is_loaded"))
	)
	var vertex := ""
	if used_engine:
		## KataGo search must not run on the main thread — it freezes the whole game.
		vertex = await _genmove_off_main(color_s)
	else:
		vertex = _random_legal(color)
	if vertex.is_empty():
		vertex = "pass"
	## Engine already played genmove into its internal board; BoardState still needs apply.
	if used_engine:
		_apply_engine_move_to_state(color, vertex)
	else:
		board.try_play(color, vertex)
	ai_thinking.emit(false)
	_busy = false
	if board.phase != &"playing" and mode == Mode.PED_VS_PED:
		## Auto-rematch ambient games.
		await get_tree().create_timer(1.2).timeout
		if mode == Mode.PED_VS_PED and is_inside_tree():
			board.setup(board.size)
			if _eng != null:
				_eng.call("clear_board")
			_ambient_timer = 1.0


## Run NativeKataGo.genmove on WorkerThreadPool; poll so the main loop keeps rendering.
func _genmove_off_main(color_s: String) -> String:
	var eng := _eng
	var mutex := Mutex.new()
	var state := {"done": false, "vertex": ""}
	var task_id := WorkerThreadPool.add_task(
		func() -> void:
			var v := ""
			if eng != null and is_instance_valid(eng) and bool(eng.call("is_loaded")):
				v = str(eng.call("genmove", color_s))
			mutex.lock()
			state["vertex"] = v
			state["done"] = true
			mutex.unlock()
	)
	while true:
		mutex.lock()
		var done: bool = bool(state["done"])
		mutex.unlock()
		if done:
			break
		if not is_inside_tree():
			WorkerThreadPool.wait_for_task_completion(task_id)
			return "pass"
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task_id)
	mutex.lock()
	var vertex: String = str(state["vertex"])
	mutex.unlock()
	return vertex


func _apply_engine_move_to_state(color: int, vertex: String) -> void:
	## BoardState authority for visuals; trust engine legality.
	var v := vertex.strip_edges().to_lower()
	if v == "pass" or v == "resign":
		board.try_play(color, v)
		return
	var loc := GoBoardState.parse_vertex(vertex, board.size)
	if loc.x < 0:
		board.try_play(color, "pass")
		return
	## Force place even if our simple rules disagree (should be rare).
	if not board.try_play_xy(color, loc.x, loc.y):
		## Fallback: stamp without full legality.
		board.set_at(loc.x, loc.y, color)
		board.next_color = GoBoardState.WHITE if color == GoBoardState.BLACK else GoBoardState.BLACK
		board.moved.emit(color, GoBoardState.format_vertex(loc.x, loc.y, board.size), loc)


func _sync_engine_play(color: int, vertex: String) -> void:
	if _eng == null or not is_instance_valid(_eng) or not bool(_eng.call("is_loaded")):
		return
	var color_s := "b" if color == GoBoardState.BLACK else "w"
	var v := vertex.strip_edges().to_lower()
	if v == "resign":
		return
	_eng.call("play", color_s, vertex if v != "pass" else "pass")


func _random_legal(color: int) -> String:
	if board == null:
		return "pass"
	var coords: Array[Vector2i] = []
	for y in range(board.size):
		for x in range(board.size):
			if board.at(x, y) == GoBoardState.EMPTY:
				coords.append(Vector2i(x, y))
	coords.shuffle()
	for loc in coords:
		if board.is_legal_xy(color, loc.x, loc.y):
			return GoBoardState.format_vertex(loc.x, loc.y, board.size)
	return "pass"
