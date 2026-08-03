## Pure Go board state (no nodes). Emits move/capture/reset for dual views.
class_name GoBoardState
extends RefCounted

signal moved(color: int, vertex: String, loc: Vector2i)
signal captured(color: int, locs: Array)
signal passed(color: int)
signal reset()
signal game_over(reason: String)

const EMPTY := 0
const BLACK := 1
const WHITE := 2

var size: int = 19
var next_color: int = BLACK
var phase: StringName = &"idle"
## Flat row-major: index = y * size + x. Values EMPTY/BLACK/WHITE.
var stones: PackedInt32Array = PackedInt32Array()
var move_list: Array[Dictionary] = []
var consecutive_passes: int = 0
## Simple ko: forbidden re-capture location for one ply (Vector2i or null via INF).
var ko_x: int = -1
var ko_y: int = -1
## Set when phase becomes scoring: "resign_b", "resign_w", "two_passes", or "stopped".
var end_reason: String = ""


func setup(n: int = 19) -> void:
	if n < 2 or n > 25:
		push_error("GoBoardState.setup: bad size %d" % n)
		assert(false, "GoBoardState bad size")
		return
	size = n
	stones = PackedInt32Array()
	stones.resize(size * size)
	stones.fill(EMPTY)
	next_color = BLACK
	phase = &"playing"
	move_list.clear()
	consecutive_passes = 0
	ko_x = -1
	ko_y = -1
	end_reason = ""
	reset.emit()


func at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= size or y >= size:
		return EMPTY
	return stones[y * size + x]


func set_at(x: int, y: int, color: int) -> void:
	stones[y * size + x] = color


## GTP vertex like "D4" or "pass". Returns Vector2i(-1,-1) for pass.
static func parse_vertex(vertex: String, n: int) -> Vector2i:
	var v := vertex.strip_edges().to_lower()
	if v == "pass" or v == "resign":
		return Vector2i(-1, -1)
	if v.length() < 2:
		return Vector2i(-999, -999)
	var col_ch := v[0]
	if col_ch < "a" or col_ch > "z" or col_ch == "i":
		return Vector2i(-999, -999)
	var col := int(col_ch.unicode_at(0) - "a".unicode_at(0))
	if col_ch > "i":
		col -= 1
	var row := int(v.substr(1))
	if row < 1 or row > n or col < 0 or col >= n:
		return Vector2i(-999, -999)
	## GTP: A1 is bottom-left for Black's view → y = row-1
	return Vector2i(col, row - 1)


static func format_vertex(x: int, y: int, n: int) -> String:
	if x < 0 or y < 0:
		return "pass"
	if x >= n or y >= n:
		return "pass"
	var col := x
	if col >= 8:
		col += 1
	var ch := char("a".unicode_at(0) + col)
	return "%s%d" % [ch.to_upper(), y + 1]


func try_play(color: int, vertex: String) -> bool:
	if phase != &"playing":
		return false
	if color != next_color:
		return false
	var v := vertex.strip_edges().to_lower()
	if v == "pass":
		_apply_pass(color)
		return true
	if v == "resign":
		phase = &"scoring"
		end_reason = "resign_%s" % ("b" if color == BLACK else "w")
		game_over.emit(end_reason)
		return true
	var loc := parse_vertex(vertex, size)
	if loc.x == -999:
		return false
	return try_play_xy(color, loc.x, loc.y)


## Spectator abort (AI-vs-AI STOP). Scores whatever is on the board.
func stop_play() -> bool:
	if phase != &"playing":
		return false
	phase = &"scoring"
	end_reason = "stopped"
	game_over.emit(end_reason)
	return true


func is_legal_xy(color: int, x: int, y: int) -> bool:
	if phase != &"playing" or color != next_color:
		return false
	if x < 0 or y < 0 or x >= size or y >= size:
		return false
	if at(x, y) != EMPTY:
		return false
	if x == ko_x and y == ko_y:
		return false
	var saved := stones.duplicate()
	set_at(x, y, color)
	var opp := WHITE if color == BLACK else BLACK
	var captured: Array[Vector2i] = []
	for d in _neighbors(x, y):
		if at(d.x, d.y) == opp and _liberty_count(d.x, d.y) == 0:
			captured.append_array(_collect_group(d.x, d.y))
	for c in captured:
		set_at(c.x, c.y, EMPTY)
	var ok := _liberty_count(x, y) > 0
	stones = saved
	return ok


func try_play_xy(color: int, x: int, y: int) -> bool:
	if not is_legal_xy(color, x, y):
		return false
	## Commit place (is_legal already validated; recompute captures).
	set_at(x, y, color)
	var opp := WHITE if color == BLACK else BLACK
	var captured_locs: Array[Vector2i] = []
	for d in _neighbors(x, y):
		if at(d.x, d.y) == opp and _liberty_count(d.x, d.y) == 0:
			captured_locs.append_array(_collect_group(d.x, d.y))
	var uniq: Dictionary = {}
	for c in captured_locs:
		uniq[c] = true
	captured_locs.clear()
	for k: Vector2i in uniq.keys():
		captured_locs.append(k)
		set_at(k.x, k.y, EMPTY)
	if captured_locs.size() == 1 and _group_size(x, y) == 1:
		ko_x = captured_locs[0].x
		ko_y = captured_locs[0].y
	else:
		ko_x = -1
		ko_y = -1
	consecutive_passes = 0
	var vertex := format_vertex(x, y, size)
	move_list.append({"color": color, "vertex": vertex, "x": x, "y": y})
	next_color = opp
	var caps: Array = []
	for c in captured_locs:
		caps.append(c)
	if not caps.is_empty():
		captured.emit(opp, caps)
	moved.emit(color, vertex, Vector2i(x, y))
	return true


func _apply_pass(color: int) -> void:
	consecutive_passes += 1
	ko_x = -1
	ko_y = -1
	move_list.append({"color": color, "vertex": "pass", "x": -1, "y": -1})
	next_color = WHITE if color == BLACK else BLACK
	passed.emit(color)
	if consecutive_passes >= 2:
		phase = &"scoring"
		end_reason = "two_passes"
		game_over.emit(end_reason)


## Tromp-Taylor area score. Empty regions bordered by only one colour count for that
## colour; stones count; dame (touched by both) count for neither. White gets `komi`.
func score_tromp_taylor(komi: float = 7.5) -> Dictionary:
	var owner := PackedInt32Array()
	owner.resize(size * size)
	owner.fill(-1)
	var seen: Dictionary = {}
	for y in range(size):
		for x in range(size):
			var c := at(x, y)
			if c != EMPTY:
				owner[y * size + x] = c
				continue
			var key := Vector2i(x, y)
			if seen.has(key):
				continue
			var region: Array[Vector2i] = []
			var borders: Dictionary = {}
			var stack: Array[Vector2i] = [key]
			seen[key] = true
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				region.append(p)
				for d in _neighbors(p.x, p.y):
					var nc := at(d.x, d.y)
					if nc == EMPTY:
						if not seen.has(d):
							seen[d] = true
							stack.append(d)
					else:
						borders[nc] = true
			var sole := EMPTY
			if borders.size() == 1:
				var bkeys: Array = borders.keys()
				sole = int(bkeys[0])
			for p2 in region:
				owner[p2.y * size + p2.x] = sole
	var black_pts := 0
	var white_pts := 0
	for i in range(owner.size()):
		if owner[i] == BLACK:
			black_pts += 1
		elif owner[i] == WHITE:
			white_pts += 1
	return {
		"black": float(black_pts),
		"white": float(white_pts) + komi,
		"komi": komi,
	}


func _neighbors(x: int, y: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if x > 0:
		out.append(Vector2i(x - 1, y))
	if x < size - 1:
		out.append(Vector2i(x + 1, y))
	if y > 0:
		out.append(Vector2i(x, y - 1))
	if y < size - 1:
		out.append(Vector2i(x, y + 1))
	return out


func _liberty_count(x: int, y: int) -> int:
	var color := at(x, y)
	if color == EMPTY:
		return 0
	var seen: Dictionary = {}
	var libs: Dictionary = {}
	var stack: Array[Vector2i] = [Vector2i(x, y)]
	seen[Vector2i(x, y)] = true
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		for d in _neighbors(p.x, p.y):
			var c := at(d.x, d.y)
			if c == EMPTY:
				libs[d] = true
			elif c == color and not seen.has(d):
				seen[d] = true
				stack.append(d)
	return libs.size()


func _collect_group(x: int, y: int) -> Array[Vector2i]:
	var color := at(x, y)
	var out: Array[Vector2i] = []
	if color == EMPTY:
		return out
	var seen: Dictionary = {}
	var stack: Array[Vector2i] = [Vector2i(x, y)]
	seen[Vector2i(x, y)] = true
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		out.append(p)
		for d in _neighbors(p.x, p.y):
			if at(d.x, d.y) == color and not seen.has(d):
				seen[d] = true
				stack.append(d)
	return out


func _group_size(x: int, y: int) -> int:
	return _collect_group(x, y).size()
