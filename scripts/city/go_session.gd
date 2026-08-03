## One Go table session: BoardState + optional KataGo Human-SL per AI colour.
class_name GoSession
extends Node

const GoEnginePoolScript := preload("res://scripts/city/go_engine_pool.gd")
const GoRankScript := preload("res://scripts/city/go_rank.gd")

signal ai_thinking(on: bool)
signal session_ended(reason: String)
signal match_over(reason: String)

var board: GoBoardState = null
var black_human: bool = true
var white_human: bool = false
var black_rank: String = "5k"
var white_rank: String = "5k"
var _eng: Object = null
var _busy: bool = false
var _owned_engine: bool = false
var _active_rank: String = ""


func begin_match(
	n: int,
	p_black_human: bool,
	p_black_rank: String,
	p_white_human: bool,
	p_white_rank: String
) -> bool:
	black_human = p_black_human
	white_human = p_white_human
	black_rank = GoEnginePoolScript.normalize_rank(p_black_rank)
	white_rank = GoEnginePoolScript.normalize_rank(p_white_rank)
	board = GoBoardState.new()
	board.setup(n)
	_owned_engine = false
	_active_rank = ""
	if needs_engine():
		var start_rank := black_rank if not black_human else white_rank
		_eng = GoEnginePoolScript.acquire(start_rank)
		if _eng == null:
			push_warning("GoSession: no KataGo — AI sides will use random legal moves")
		else:
			_owned_engine = true
			_active_rank = start_rank
			_eng.call("set_boardsize", n)
			_eng.call("clear_board")
	_busy = false
	set_process(false)
	## If Black is AI, kick the opening move after one frame.
	if not black_human and board.phase == &"playing":
		call_deferred("_kick_ai_if_needed")
	return true


func end_session(reason: String = "leave") -> void:
	set_process(false)
	if _owned_engine:
		GoEnginePoolScript.release()
		_owned_engine = false
	_eng = null
	session_ended.emit(reason)


func needs_engine() -> bool:
	return not black_human or not white_human


func color_is_human(color: int) -> bool:
	if color == GoBoardState.BLACK:
		return black_human
	if color == GoBoardState.WHITE:
		return white_human
	return false


func color_rank(color: int) -> String:
	return black_rank if color == GoBoardState.BLACK else white_rank


func player_to_move() -> bool:
	if board == null or board.phase != &"playing" or _busy:
		return false
	return color_is_human(board.next_color)


func try_player_vertex(vertex: String) -> bool:
	if not player_to_move():
		return false
	var color := board.next_color
	if not board.try_play(color, vertex):
		return false
	_sync_engine_play(color, vertex)
	if board.phase == &"playing":
		_kick_ai_if_needed()
	else:
		match_over.emit(String(board.phase))
	return true


func try_player_pass() -> bool:
	return try_player_vertex("pass")


func try_player_resign() -> bool:
	return try_player_vertex("resign")


func _kick_ai_if_needed() -> void:
	if board == null or board.phase != &"playing":
		return
	if color_is_human(board.next_color):
		return
	_request_ai_move()


func _request_ai_move() -> void:
	if _busy or board == null or board.phase != &"playing":
		return
	if color_is_human(board.next_color):
		return
	_busy = true
	ai_thinking.emit(true)
	await get_tree().process_frame
	var color := board.next_color
	var color_s := "b" if color == GoBoardState.BLACK else "w"
	var rank := color_rank(color)
	_ensure_rank(rank)
	var used_engine := (
		_eng != null and is_instance_valid(_eng) and bool(_eng.call("is_loaded"))
	)
	var vertex := ""
	if used_engine:
		vertex = await _genmove_off_main(color_s)
	else:
		vertex = _random_legal(color)
	if vertex.is_empty():
		vertex = "pass"
	if used_engine:
		_apply_engine_move_to_state(color, vertex)
	else:
		board.try_play(color, vertex)
	ai_thinking.emit(false)
	_busy = false
	if board == null:
		return
	if board.phase != &"playing":
		match_over.emit(String(board.phase))
		return
	if not color_is_human(board.next_color):
		## AI vs AI: brief beat so the giant hand / stones can settle.
		await get_tree().create_timer(0.35).timeout
		if is_inside_tree() and board != null and board.phase == &"playing":
			_kick_ai_if_needed()


func _ensure_rank(rank: String) -> void:
	if _eng == null or not is_instance_valid(_eng) or not bool(_eng.call("is_loaded")):
		return
	if rank == _active_rank:
		return
	_eng.call("set_rank", rank)
	_active_rank = rank


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
	var v := vertex.strip_edges().to_lower()
	if v == "pass" or v == "resign":
		board.try_play(color, v)
		return
	var loc := GoBoardState.parse_vertex(vertex, board.size)
	if loc.x < 0:
		board.try_play(color, "pass")
		return
	if not board.try_play_xy(color, loc.x, loc.y):
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
