## Table-top Go board as a Ui3D surface (grid + stones only).
class_name GoTableUi3D
extends Ui3D

signal vertex_chosen(vertex: String)

## Blank border kept outside the outer lines, as a fraction of the panel. Shared by the
## painted grid, the stone placement and the click mapping so all three agree.
const MARGIN_FRAC := 0.07

var board: GoBoardState = null
var input_enabled: bool = true
var _stone_root: Node3D = null
var _grid_img: Image = null
var _grid_tex: ImageTexture = null
var _board_n: int = 19


func setup_board(p_board: GoBoardState, origin: Vector3, face_yaw: float, panel_w: float = 2.4) -> void:
	board = p_board
	_board_n = board.size if board != null else 19
	## Square playfield — Pass/Resign live on the settings panel beside the board.
	size_m = Vector2(panel_w, panel_w)
	surface_color = Color(0.76, 0.58, 0.32, 1.0)
	show_debug_marker = false
	begin(origin, face_yaw)
	## Ui3D is an upright XY face (normal −Z). +90° lays that face up toward the player.
	rotation.x = deg_to_rad(90.0)
	clear_buttons()
	rebuild_buttons()
	_paint_grid()
	if _stone_root != null:
		_stone_root.queue_free()
	_stone_root = Node3D.new()
	_stone_root.name = "Stones"
	add_child(_stone_root)
	if board != null:
		if not board.moved.is_connected(_on_moved):
			board.moved.connect(_on_moved)
		if not board.captured.is_connected(_on_captured):
			board.captured.connect(_on_captured)
		if not board.reset.is_connected(_rebuild_stones):
			board.reset.connect(_rebuild_stones)
	_rebuild_stones()
	if not surface_pressed.is_connected(_on_surface):
		surface_pressed.connect(_on_surface)


func set_input_enabled(on: bool) -> void:
	input_enabled = on


func _paint_grid() -> void:
	var px := 512
	_grid_img = Image.create(px, px, false, Image.FORMAT_RGBA8)
	_grid_img.fill(Color(0.78, 0.6, 0.34, 1.0))
	var margin := int(round(MARGIN_FRAC * float(px)))
	var n := _board_n
	var inner := float(px - 2 * margin)
	var ink := Color(0.12, 0.1, 0.08)
	## n lines, first and last on the border of the playfield: stones go on the n×n
	## crossings between them, never inside a cell.
	for i in range(n):
		var c := margin + int(round(float(i) / float(n - 1) * inner))
		c = clampi(c, margin, px - margin - 1)
		for k in range(margin, px - margin):
			_grid_img.set_pixel(c, k, ink)
			_grid_img.set_pixel(k, c, ink)
	for hz in [3, 9, 15]:
		if hz >= n:
			continue
		for hx in [3, 9, 15]:
			if hx >= n:
				continue
			var tx := margin + int(round(float(hx) / float(n - 1) * inner))
			var ty := margin + int(round(float(hz) / float(n - 1) * inner))
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if dx * dx + dy * dy <= 4:
						_grid_img.set_pixel(tx + dx, ty + dy, ink)
	_grid_tex = ImageTexture.create_from_image(_grid_img)
	if _surface != null:
		var mat := _surface.material_override as StandardMaterial3D
		if mat == null:
			mat = StandardMaterial3D.new()
			_surface.material_override = mat
		mat.albedo_texture = _grid_tex
		mat.albedo_color = Color.WHITE


func _on_surface(uv: Vector2, _local: Vector3, _world: Vector3) -> void:
	if not input_enabled or board == null:
		return
	var lo := MARGIN_FRAC
	var hi := 1.0 - MARGIN_FRAC
	var u := inverse_lerp(lo, hi, clampf(uv.x, lo, hi))
	var v := inverse_lerp(lo, hi, clampf(uv.y, lo, hi))
	## Nearest crossing, and UV x runs right-to-left from the seat, so mirror it: a stone
	## played on the left of the table lands on the left of the giant board too.
	var last := float(_board_n - 1)
	var x := clampi(_board_n - 1 - int(round(u * last)), 0, _board_n - 1)
	var y := clampi(int(round(v * last)), 0, _board_n - 1)
	vertex_chosen.emit(GoBoardState.format_vertex(x, y, _board_n))


func _on_moved(_color: int, _vertex: String, _loc: Vector2i) -> void:
	_rebuild_stones()
	_play_stone_bling()


func _play_stone_bling() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var nodes := tree.get_nodes_in_group(CityAudio.GROUP_NAME)
	if nodes.is_empty():
		return
	var audio := nodes[0] as CityAudio
	if audio != null and audio.has_method("play_go_stone_bling"):
		audio.call("play_go_stone_bling", global_position)


func _on_captured(_color: int, _locs: Array) -> void:
	_rebuild_stones()


func _rebuild_stones() -> void:
	if _stone_root == null or board == null:
		return
	for c in _stone_root.get_children():
		c.queue_free()
	var half := size_m * 0.5
	var play_bottom := -half.y + size_m.y * MARGIN_FRAC
	var play_top := half.y - size_m.y * MARGIN_FRAC
	var play_left := -half.x + size_m.x * MARGIN_FRAC
	var play_right := half.x - size_m.x * MARGIN_FRAC
	var last := float(board.size - 1)
	var cell_m := (play_right - play_left) / last
	for y in range(board.size):
		for x in range(board.size):
			var c := board.at(x, y)
			if c == GoBoardState.EMPTY:
				continue
			var u := float(board.size - 1 - x) / last
			var v := float(y) / last
			var lx := lerpf(play_left, play_right, u)
			var ly := lerpf(play_bottom, play_top, v)
			var mesh := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = cell_m * 0.45
			sphere.height = sphere.radius * 2.0
			mesh.mesh = sphere
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.08, 0.08, 0.09) if c == GoBoardState.BLACK else Color(0.92, 0.92, 0.9)
			mesh.material_override = mat
			mesh.position = Vector3(lx, ly, -0.03)
			_stone_root.add_child(mesh)
