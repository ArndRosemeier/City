## Placement heuristic for NPC Tetris play — holes / height / clears / bumpiness.
class_name TetrisAI
extends RefCounted

const COLS := 10
const ROWS := 20

const W_LINES := 760.0
const W_HOLES := -360.0
const W_AGG_HEIGHT := -48.0
const W_BUMPINESS := -28.0
const W_MAX_HEIGHT := -18.0


static func choose_placement(machine: Node) -> Dictionary:
	## Returns {rot, x} or {} if none.
	if machine == null or not machine.has_method("is_playable"):
		return {}
	if not bool(machine.call("is_playable")):
		return {}
	var piece: Dictionary = machine.call("get_active_piece")
	if piece.is_empty():
		return {}
	var board: PackedByteArray = machine.call("get_board_snapshot")
	var pid := int(piece.get("id", 0))
	if pid <= 0:
		return {}

	var best_score := -INF
	var best_rot := int(piece.get("rot", 0))
	var best_x := int(piece.get("x", 0))
	var found := false

	var max_rot := 1 if pid == 4 else 4  ## O piece
	for rot in max_rot:
		var cells := _cells(machine, pid, rot)
		if cells.is_empty():
			continue
		var min_cx := 0
		var max_cx := 0
		for cell in cells:
			min_cx = mini(min_cx, cell.x)
			max_cx = maxi(max_cx, cell.x)
		for x in range(-min_cx, COLS - max_cx):
			var land_y := _drop_y(board, x, cells)
			if land_y == -999:
				continue
			var score := _score_placement(board, cells, pid, x, land_y)
			if score > best_score:
				best_score = score
				best_rot = rot
				best_x = x
				found = true

	if not found:
		return {}
	return {"rot": best_rot, "x": best_x, "score": best_score}


static func _cells(machine: Node, pid: int, rot: int) -> Array[Vector2i]:
	var raw: Variant = machine.call("cells_for_piece", pid, rot)
	var out: Array[Vector2i] = []
	if raw == null:
		return out
	for c in raw as Array:
		if c is Vector2i:
			out.append(c as Vector2i)
		elif c is Vector2:
			var v := c as Vector2
			out.append(Vector2i(int(v.x), int(v.y)))
	return out


static func _drop_y(board: PackedByteArray, x: int, cells: Array[Vector2i]) -> int:
	## Highest row where the piece fits, then settle downward.
	var start := -1
	for ty in range(ROWS - 1, -1, -1):
		if _fits_board(board, cells, x, ty):
			start = ty
			break
	if start < 0:
		return -999
	var y := start
	while y > 0 and _fits_board(board, cells, x, y - 1):
		y -= 1
	return y


static func _fits_board(board: PackedByteArray, cells: Array[Vector2i], ox: int, oy: int) -> bool:
	for cell in cells:
		var x := ox + cell.x
		var y := oy + cell.y
		if x < 0 or x >= COLS or y < 0:
			return false
		if y >= ROWS:
			continue
		if board[y * COLS + x] != 0:
			return false
	return true


static func _score_placement(
	board: PackedByteArray, cells: Array[Vector2i], pid: int, x: int, y: int
) -> float:
	var sim := board.duplicate()
	for cell in cells:
		var px := x + cell.x
		var py := y + cell.y
		if py < 0 or py >= ROWS or px < 0 or px >= COLS:
			return -INF
		sim[py * COLS + px] = pid

	var lines := 0
	var compacted := PackedByteArray()
	compacted.resize(COLS * ROWS)
	compacted.fill(0)
	var dest := 0
	for row in ROWS:
		var full := true
		for col in COLS:
			if sim[row * COLS + col] == 0:
				full = false
				break
		if full:
			lines += 1
			continue
		for col in COLS:
			compacted[dest * COLS + col] = sim[row * COLS + col]
		dest += 1

	var heights: PackedInt32Array = PackedInt32Array()
	heights.resize(COLS)
	var holes := 0
	var agg := 0
	var max_h := 0
	for col in COLS:
		var h := 0
		var seen := false
		for row in range(ROWS - 1, -1, -1):
			if compacted[row * COLS + col] != 0:
				if not seen:
					h = row + 1
					seen = true
			elif seen:
				holes += 1
		heights[col] = h
		agg += h
		max_h = maxi(max_h, h)

	var bump := 0
	for col in range(1, COLS):
		bump += absi(heights[col] - heights[col - 1])

	return (
		float(lines) * W_LINES
		+ float(holes) * W_HOLES
		+ float(agg) * W_AGG_HEIGHT
		+ float(bump) * W_BUMPINESS
		+ float(max_h) * W_MAX_HEIGHT
	)
