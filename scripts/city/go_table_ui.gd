## Table-top Go board as a Ui3D surface (grid + stones + pass/resign + rank).
class_name GoTableUi3D
extends Ui3D

const GoRankScript := preload("res://scripts/city/go_rank.gd")
const GoEnginePoolScript := preload("res://scripts/city/go_engine_pool.gd")

signal vertex_chosen(vertex: String)
signal pass_pressed()
signal resign_pressed()
signal invite_pressed(tier: StringName)
signal rank_changed(rank: String)

const BTN_PASS := &"pass"
const BTN_RESIGN := &"resign"
const BTN_RANK_MINUS := &"rank_minus"
const BTN_RANK := &"rank"
const BTN_RANK_PLUS := &"rank_plus"
const BTN_INV_N := &"invite_novice"
const BTN_INV_C := &"invite_club"
const BTN_INV_D := &"invite_dan"

var board: GoBoardState = null
var input_enabled: bool = true
var selected_rank: String = "5k"
var _stone_root: Node3D = null
var _grid_img: Image = null
var _grid_tex: ImageTexture = null
var _board_n: int = 19


func setup_board(p_board: GoBoardState, origin: Vector3, face_yaw: float, panel_w: float = 2.4) -> void:
	board = p_board
	_board_n = board.size if board != null else 19
	size_m = Vector2(panel_w, panel_w * 1.15)
	surface_color = Color(0.76, 0.58, 0.32, 1.0)
	show_debug_marker = false
	begin(origin, face_yaw)
	## Ui3D is an upright XY face (normal −Z). Lay it flat on the table, face up.
	rotation.x = deg_to_rad(-90.0)
	_build_chrome()
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
	if not button_pressed.is_connected(_on_button):
		button_pressed.connect(_on_button)
	if not surface_pressed.is_connected(_on_surface):
		surface_pressed.connect(_on_surface)


func set_input_enabled(on: bool) -> void:
	input_enabled = on


func set_selected_rank(rank: String) -> void:
	var next: String = GoEnginePoolScript.normalize_rank(rank)
	if next == selected_rank:
		_refresh_rank_label()
		return
	selected_rank = next
	_refresh_rank_label()
	rank_changed.emit(selected_rank)


func _build_chrome() -> void:
	clear_buttons()
	## Bottom strip: pass/resign | rank stepper | invite presets (15k/5k/1d).
	add_button(BTN_PASS, Rect2(0.02, 0.02, 0.14, 0.08), "Pass", Color(0.2, 0.25, 0.35), true)
	add_button(BTN_RESIGN, Rect2(0.17, 0.02, 0.14, 0.08), "Resign", Color(0.4, 0.15, 0.15), true)
	add_button(BTN_RANK_MINUS, Rect2(0.33, 0.02, 0.08, 0.08), "-", Color(0.25, 0.28, 0.32), true)
	add_button(
		BTN_RANK,
		Rect2(0.42, 0.02, 0.12, 0.08),
		GoRankScript.label(selected_rank),
		Color(0.18, 0.22, 0.28),
		true
	)
	add_button(BTN_RANK_PLUS, Rect2(0.55, 0.02, 0.08, 0.08), "+", Color(0.25, 0.28, 0.32), true)
	add_button(BTN_INV_N, Rect2(0.66, 0.02, 0.10, 0.08), "15k", Color(0.35, 0.55, 0.35), true)
	add_button(BTN_INV_C, Rect2(0.77, 0.02, 0.10, 0.08), "5k", Color(0.35, 0.4, 0.6), true)
	add_button(BTN_INV_D, Rect2(0.88, 0.02, 0.10, 0.08), "1d", Color(0.55, 0.35, 0.15), true)
	rebuild_buttons()


func _refresh_rank_label() -> void:
	add_button(
		BTN_RANK,
		Rect2(0.42, 0.02, 0.12, 0.08),
		GoRankScript.label(selected_rank),
		Color(0.18, 0.22, 0.28),
		false
	)


func _paint_grid() -> void:
	var px := 512
	_grid_img = Image.create(px, px, false, Image.FORMAT_RGBA8)
	_grid_img.fill(Color(0.78, 0.6, 0.34, 1.0))
	var margin := 36
	var n := _board_n
	var inner := float(px - 2 * margin)
	## n×n empty fields → n+1 grid lines at cell boundaries.
	for i in range(n + 1):
		var c := margin + int(round(float(i) / float(n) * inner))
		c = clampi(c, margin, px - margin - 1)
		for y in range(margin, px - margin):
			_grid_img.set_pixel(c, y, Color(0.12, 0.1, 0.08))
			_grid_img.set_pixel(y, c, Color(0.12, 0.1, 0.08))
	for hz in [3, 9, 15]:
		if hz >= n:
			continue
		for hx in [3, 9, 15]:
			if hx >= n:
				continue
			## Hoshi at field centres.
			var tx := margin + int(round((float(hx) + 0.5) / float(n) * inner))
			var ty := margin + int(round((float(hz) + 0.5) / float(n) * inner))
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if dx * dx + dy * dy <= 4:
						_grid_img.set_pixel(tx + dx, ty + dy, Color(0.1, 0.08, 0.06))
	_grid_tex = ImageTexture.create_from_image(_grid_img)
	if _surface != null:
		var mat := _surface.material_override as StandardMaterial3D
		if mat == null:
			mat = StandardMaterial3D.new()
			_surface.material_override = mat
		mat.albedo_texture = _grid_tex
		mat.albedo_color = Color.WHITE


func _on_button(button_id: StringName, _uv: Vector2) -> void:
	if not input_enabled:
		return
	match button_id:
		BTN_PASS:
			pass_pressed.emit()
		BTN_RESIGN:
			resign_pressed.emit()
		BTN_RANK_MINUS:
			set_selected_rank(GoRankScript.step(selected_rank, -1))
		BTN_RANK_PLUS:
			set_selected_rank(GoRankScript.step(selected_rank, 1))
		BTN_RANK:
			## Start a match at the currently selected rank (club outfit ped).
			invite_pressed.emit(&"club")
		BTN_INV_N:
			set_selected_rank(GoRankScript.preset_rank(&"novice"))
			invite_pressed.emit(&"novice")
		BTN_INV_C:
			set_selected_rank(GoRankScript.preset_rank(&"club"))
			invite_pressed.emit(&"club")
		BTN_INV_D:
			set_selected_rank(GoRankScript.preset_rank(&"dan"))
			invite_pressed.emit(&"dan")


func _on_surface(uv: Vector2, _local: Vector3, _world: Vector3) -> void:
	if not input_enabled or board == null:
		return
	## Board playfield occupies UV y 0.14..0.98, x 0.04..0.96
	if uv.y < 0.14:
		return
	var u := inverse_lerp(0.04, 0.96, clampf(uv.x, 0.04, 0.96))
	var v := inverse_lerp(0.14, 0.98, clampf(uv.y, 0.14, 0.98))
	## Click empty fields (cell centres), not line intersections.
	var x := clampi(int(floor(u * float(_board_n))), 0, _board_n - 1)
	var y := clampi(int(floor(v * float(_board_n))), 0, _board_n - 1)
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
	var play_bottom := -half.y + size_m.y * 0.14
	var play_top := half.y
	var play_left := -half.x + size_m.x * 0.04
	var play_right := half.x - size_m.x * 0.04
	for y in range(board.size):
		for x in range(board.size):
			var c := board.at(x, y)
			if c == GoBoardState.EMPTY:
				continue
			var u := (float(x) + 0.5) / float(board.size)
			var v := (float(y) + 0.5) / float(board.size)
			var lx := lerpf(play_left, play_right, u)
			var ly := lerpf(play_bottom, play_top, v)
			var mesh := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = size_m.x / float(board.size) * 0.38
			sphere.height = sphere.radius * 2.0
			mesh.mesh = sphere
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.08, 0.08, 0.09) if c == GoBoardState.BLACK else Color(0.92, 0.92, 0.9)
			mesh.material_override = mat
			mesh.position = Vector3(lx, ly, -0.03)
			_stone_root.add_child(mesh)
