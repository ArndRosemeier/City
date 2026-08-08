## One Go table session: BoardState + optional KataGo Human-SL per AI colour.
class_name GoSession
extends Node

const GoEnginePoolScript := preload("res://scripts/city/go_engine_pool.gd")
const GoRankScript := preload("res://scripts/city/go_rank.gd")
const GoMatchResultScript := preload("res://scripts/city/go_match_result.gd")
const GoEvalSnapshotScript := preload("res://scripts/city/go_eval_snapshot.gd")

signal ai_thinking(on: bool)
signal session_ended(reason: String)
signal match_over(result: GoMatchResult)
## Root stats from the AI move that just landed. Free — the search already had them.
signal eval_updated(snapshot: GoEvalSnapshot)
## The shown numbers no longer describe the position (human moved, match ended, restart).
signal eval_cleared()

## Japanese match default. End-panel Chinese recount uses the same komi so toggling
## only changes territory-vs-area accounting, not the compensation White already played under.
const KOMI := 6.5

var board: GoBoardState = null
var black_human: bool = true
var white_human: bool = false
var black_rank: String = "5k"
var white_rank: String = "5k"
var _eng: Object = null
var _busy: bool = false
var _owned_engine: bool = false
var _engine_ready: bool = false
var _active_rank: String = ""
var _board_n: int = 19
## Bumped on end_session so in-flight warmup / genmove coroutines bail out.
var _epoch: int = 0
## False once we learn the loaded GDExtension predates genmove_eval.
var _engine_has_eval: bool = true
## WorkerThreadPool task currently inside KataGo (genmove / final_status). Joined
## before pool shutdown so stream-out cannot destroy the handle under a search.
var _search_task_id: int = -1


func begin_match(
	n: int,
	p_black_human: bool,
	p_black_rank: String,
	p_white_human: bool,
	p_white_rank: String
) -> bool:
	var fresh := GoBoardState.new()
	fresh.setup(n)
	return _open(fresh, p_black_human, p_black_rank, p_white_human, p_white_rank)


## Pick a saved game back up (see `to_save_dict`). False when the row is not a board this
## build can play, in which case the caller should offer a fresh match instead.
func resume_match(data: Dictionary) -> bool:
	var raw: Variant = data.get("board", null)
	if typeof(raw) != TYPE_DICTIONARY:
		push_error("GoSession.resume_match: the saved match carries no board")
		return false
	var restored := GoBoardState.from_save_dict(raw as Dictionary)
	if restored == null:
		return false
	if restored.phase != &"playing":
		push_error(
			"GoSession.resume_match: that match already ended (%s)" % restored.end_reason
		)
		return false
	var claimed := int(data.get("board_n", restored.size))
	if claimed != restored.size:
		push_error(
			"GoSession.resume_match: the row claims %d but the board is %d wide"
			% [claimed, restored.size]
		)
		return false
	return _open(
		restored,
		bool(data.get("black_human", true)),
		str(data.get("black_rank", "5k")),
		bool(data.get("white_human", false)),
		str(data.get("white_rank", "5k"))
	)


## Adopt `p_board` as the live game and warm a net if either side needs one. A fresh match
## and a resumed one differ only in which board walks in: the engine is replayed from
## `move_list` either way, so an empty board is just the short case of the same path.
func _open(
	p_board: GoBoardState,
	p_black_human: bool,
	p_black_rank: String,
	p_white_human: bool,
	p_white_rank: String
) -> bool:
	black_human = p_black_human
	white_human = p_white_human
	black_rank = GoEnginePoolScript.normalize_rank(p_black_rank)
	white_rank = GoEnginePoolScript.normalize_rank(p_white_rank)
	_board_n = p_board.size
	board = p_board
	_owned_engine = false
	_engine_ready = false
	_active_rank = ""
	_eng = null
	_busy = false
	_epoch += 1
	_engine_has_eval = true
	set_process(false)
	eval_cleared.emit()
	## Every match needs KataGo: AI moves and endgame life/death. No local fallback.
	_owned_engine = true
	_warmup_engine(_epoch)
	return true


## Call after seating (or immediately) when an AI side is to move.
func kick_ai_if_needed() -> void:
	_kick_ai_if_needed()


func end_session(reason: String = "leave") -> void:
	set_process(false)
	_epoch += 1
	_busy = false
	## Must finish before pool.shutdown may tear down the native handle.
	_join_search_if_pending()
	if _owned_engine:
		GoEnginePoolScript.release()
		_owned_engine = false
		## Destroy the net only when the district leaves — restart reuses it warm.
		## Shutdown returns immediately; destroy runs on WorkerThreadPool.
		if reason == "unload":
			GoEnginePoolScript.shutdown()
	_eng = null
	_engine_ready = false
	eval_cleared.emit()
	## "restart" is an internal handoff; emitting would flip the arena UI mid-start.
	if reason != "restart":
		session_ended.emit(reason)


## Exactly one caller joins each search task (this session or the awaiter — not both).
func _join_search_if_pending() -> void:
	var id := _search_task_id
	if id < 0:
		return
	_search_task_id = -1
	WorkerThreadPool.wait_for_task_completion(id)


## The match as a `WorldGames` row, or {} when there is nothing to come back to. Only a game
## still being played qualifies: a scored board belongs to the end panel, and resuming into
## one would put the player in front of a result they already dismissed.
##
## Safe to take while the AI is thinking. The board holds completed moves only, so the worst
## a save mid-search loses is the move being searched — `kick_ai_if_needed` asks again.
func to_save_dict() -> Dictionary:
	if board == null or board.phase != &"playing":
		return {}
	return {
		"board_n": _board_n,
		"black_human": black_human,
		"white_human": white_human,
		"black_rank": black_rank,
		"white_rank": white_rank,
		"board": board.to_save_dict(),
	}


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
	## The shown numbers described the position before this stone.
	eval_cleared.emit()
	_sync_engine_play(color, vertex)
	if board.phase == &"playing":
		_kick_ai_if_needed()
	else:
		_finish_match()
	return true


func try_player_pass() -> bool:
	return try_player_vertex("pass")


func try_player_resign() -> bool:
	return try_player_vertex("resign")


func is_ai_only() -> bool:
	return not black_human and not white_human


## Abort an in-progress match (AI-vs-AI STOP). Cancels in-flight genmove.
func stop_match() -> bool:
	if board == null or board.phase != &"playing":
		return false
	_epoch += 1
	_busy = false
	ai_thinking.emit(false)
	if not board.stop_play():
		return false
	eval_cleared.emit()
	_finish_match()
	return true


func _warmup_engine(epoch: int) -> void:
	var start_rank := black_rank if not black_human else white_rank
	var eng: Object = await GoEnginePoolScript.acquire_async(self, start_rank)
	if epoch != _epoch or not _owned_engine or not is_inside_tree():
		## acquire_async already took a pool ref — drop it if this session abandoned the wait.
		if eng != null and (epoch != _epoch or not _owned_engine):
			GoEnginePoolScript.release()
		return
	if eng == null:
		push_error(
			"GoSession: KataGo required — build tools/build_city_katago.ps1 and run tools/ensure_katago.ps1"
		)
		assert(false, "GoSession: KataGo missing")
		_owned_engine = false
		_eng = null
		_engine_ready = false
		return
	_eng = eng
	_active_rank = start_rank
	_prime_engine_board()
	if epoch != _epoch:
		return
	_engine_ready = true
	## A human stone may have landed during prime; rebuild once more so GTP matches.
	_prime_engine_board()
	## AI-vs-AI: don't wait for seating — open as soon as the net is ready.
	if board != null and not color_is_human(board.next_color):
		_kick_ai_if_needed()


func _prime_engine_board() -> void:
	if _eng == null or not is_instance_valid(_eng) or not bool(_eng.call("is_loaded")):
		return
	_eng.call("set_boardsize", _board_n)
	_eng.call("clear_board")
	_eng.call("set_komi", KOMI)
	if not _active_rank.is_empty():
		_eng.call("set_rank", _active_rank)
	if board == null:
		return
	## Replay any stones the human (or prior AI) already played during warmup.
	for m in board.move_list:
		var vertex := str(m.get("vertex", ""))
		var v := vertex.strip_edges().to_lower()
		if v.is_empty() or v == "resign":
			continue
		var color := int(m.get("color", GoBoardState.BLACK))
		var color_s := "b" if color == GoBoardState.BLACK else "w"
		_eng.call("play", color_s, "pass" if v == "pass" else vertex)


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
	var epoch := _epoch
	_busy = true
	ai_thinking.emit(true)
	await get_tree().process_frame
	if epoch != _epoch:
		return
	## Human may already have moved; wait for the net — there is no random fallback.
	if _owned_engine and not _engine_ready:
		while _owned_engine and not _engine_ready and is_inside_tree() and epoch == _epoch:
			await get_tree().process_frame
	if epoch != _epoch or board == null or board.phase != &"playing" or not is_inside_tree():
		if epoch == _epoch:
			_busy = false
			ai_thinking.emit(false)
		return
	if _eng == null or not is_instance_valid(_eng) or not bool(_eng.call("is_loaded")):
		_busy = false
		ai_thinking.emit(false)
		push_error("GoSession: AI to move but KataGo is not loaded")
		assert(false, "GoSession: KataGo required for AI move")
		return
	var color := board.next_color
	var color_s := "b" if color == GoBoardState.BLACK else "w"
	var rank := color_rank(color)
	_ensure_rank(rank)
	var moved: Dictionary = await _genmove_off_main(color_s)
	var vertex := str(moved.get("vertex", ""))
	var eval_json := str(moved.get("eval_json", ""))
	if epoch != _epoch:
		return
	if vertex.is_empty():
		vertex = "pass"
	_apply_engine_move_to_state(color, vertex)
	## Clear busy before the signal so listeners' player_to_move() sees a free board.
	_busy = false
	ai_thinking.emit(false)
	_emit_eval(eval_json, color, vertex)
	if board == null:
		return
	if board.phase != &"playing":
		_finish_match()
		return
	if not color_is_human(board.next_color):
		## AI vs AI: brief beat so the giant hand / stones can settle.
		await get_tree().create_timer(0.35).timeout
		if epoch == _epoch and is_inside_tree() and board != null and board.phase == &"playing":
			_kick_ai_if_needed()


func _emit_eval(eval_json: String, color: int, vertex: String) -> void:
	if eval_json.is_empty():
		return
	var snap: GoEvalSnapshot = GoEvalSnapshotScript.from_engine_json(
		eval_json, color, vertex, _board_n
	)
	if snap == null:
		return
	eval_updated.emit(snap)


## Score on a worker thread (ownership search), then emit match_over.
func _finish_match() -> void:
	var epoch := _epoch
	var result: GoMatchResult = await _build_result_async()
	if epoch != _epoch or not is_inside_tree():
		return
	match_over.emit(result)


func _build_result_async() -> GoMatchResult:
	var reason := board.end_reason if board != null else "two_passes"
	if reason.is_empty():
		reason = "two_passes"
	if _owned_engine and not _engine_ready:
		while _owned_engine and not _engine_ready and is_inside_tree():
			await get_tree().process_frame
	if _eng == null or not is_instance_valid(_eng) or not bool(_eng.call("is_loaded")):
		push_error("GoSession: cannot score without KataGo")
		assert(false, "GoSession: KataGo required for scoring")
		var none: Array[Vector2i] = []
		return GoMatchResultScript.from_board(board, reason, KOMI, none)
	if not _eng.has_method("final_status_list"):
		push_error(
			"GoSession: NativeKataGo.final_status_list missing — rebuild tools/build_city_katago.ps1"
		)
		assert(false, "GoSession: rebuild city_katago for scoring")
		var none2: Array[Vector2i] = []
		return GoMatchResultScript.from_board(board, reason, KOMI, none2)
	## Resign never reached the engine; always re-prime so status matches GoBoardState.
	_prime_engine_board()
	var dead_raw := await _final_status_off_main("dead")
	var dead := _parse_status_vertices(dead_raw)
	return GoMatchResultScript.from_board(board, reason, KOMI, dead)


func _parse_status_vertices(raw: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var s := raw.strip_edges()
	if s.is_empty() or board == null:
		return out
	for part in s.split(" ", false):
		var token := str(part).strip_edges()
		if token.is_empty():
			continue
		var loc := GoBoardState.parse_vertex(token, board.size)
		if loc.x < 0:
			push_error("GoSession: bad final_status_list vertex '%s'" % token)
			assert(false, "GoSession: bad status vertex")
			continue
		if board.at(loc.x, loc.y) == GoBoardState.EMPTY:
			push_error("GoSession: final_status_list marked empty %s" % token)
			assert(false, "GoSession: status on empty")
			continue
		out.append(loc)
	return out


func _final_status_off_main(which: String) -> String:
	var eng := _eng
	var mutex := Mutex.new()
	var state := {"done": false, "text": ""}
	var task_id := WorkerThreadPool.add_task(
		func() -> void:
			var text := ""
			if eng != null and is_instance_valid(eng) and bool(eng.call("is_loaded")):
				text = str(eng.call("final_status_list", which))
			mutex.lock()
			state["text"] = text
			state["done"] = true
			mutex.unlock()
	)
	_search_task_id = task_id
	while true:
		mutex.lock()
		var done: bool = bool(state["done"])
		mutex.unlock()
		if done:
			break
		if not is_inside_tree():
			break
		await get_tree().process_frame
	_join_search_if_pending()
	mutex.lock()
	var out := str(state["text"])
	mutex.unlock()
	return out


func _ensure_rank(rank: String) -> void:
	if _eng == null or not is_instance_valid(_eng) or not bool(_eng.call("is_loaded")):
		return
	if rank == _active_rank:
		return
	_eng.call("set_rank", rank)
	_active_rank = rank


## Returns {"vertex": String, "eval_json": String}. "eval_json" is empty when the loaded
## GDExtension has no genmove_eval, or when the search reported nothing usable.
func _genmove_off_main(color_s: String) -> Dictionary:
	var eng := _eng
	var with_eval := _engine_has_eval and eng.has_method("genmove_eval")
	if _engine_has_eval and not with_eval:
		_engine_has_eval = false
		push_warning(
			"GoSession: NativeKataGo has no genmove_eval — rebuild via "
			+ "tools/build_city_katago.ps1 to see live winrate / score lead"
		)
	var mutex := Mutex.new()
	var state := {"done": false, "vertex": "", "eval_json": ""}
	var task_id := WorkerThreadPool.add_task(
		func() -> void:
			var v := ""
			var json := ""
			if eng != null and is_instance_valid(eng) and bool(eng.call("is_loaded")):
				if with_eval:
					var reply: Dictionary = eng.call("genmove_eval", color_s)
					v = str(reply.get("vertex", ""))
					json = str(reply.get("eval_json", ""))
				else:
					v = str(eng.call("genmove", color_s))
			mutex.lock()
			state["vertex"] = v
			state["eval_json"] = json
			state["done"] = true
			mutex.unlock()
	)
	_search_task_id = task_id
	while true:
		mutex.lock()
		var done: bool = bool(state["done"])
		mutex.unlock()
		if done:
			break
		if not is_inside_tree():
			break
		await get_tree().process_frame
	_join_search_if_pending()
	mutex.lock()
	var out := {"vertex": str(state["vertex"]), "eval_json": str(state["eval_json"])}
	mutex.unlock()
	return out


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
	if not _engine_ready:
		return
	if _eng == null or not is_instance_valid(_eng) or not bool(_eng.call("is_loaded")):
		return
	var color_s := "b" if color == GoBoardState.BLACK else "w"
	var v := vertex.strip_edges().to_lower()
	if v == "resign":
		return
	_eng.call("play", color_s, vertex if v != "pass" else "pass")
