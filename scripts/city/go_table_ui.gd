## Table-top Go board as a Ui3D surface (grid + stones only).
class_name GoTableUi3D
extends Ui3D

signal vertex_chosen(vertex: String)

## Blank border kept outside the outer lines, as a fraction of the panel. Shared by the
## painted grid, the stone placement and the click mapping so all three agree.
const MARGIN_FRAC := 0.07

## Alternatives drawn beside the move the AI actually played.
const EVAL_MAX_MARKERS := 5
## Flat markers sit just above the grid, under the stone spheres at -0.03. Kept close to
## the surface so a seated (shallow-angle) view has no parallax between disc and caption.
const EVAL_DISC_Z := -0.024
const EVAL_LABEL_Z := -0.032
## Below this share of the busiest candidate a disc gets no caption — the board is small.
const EVAL_LABEL_MIN_SHARE := 0.2
const EVAL_MAX_LABELS := 3
const EVAL_TEX_PX := 96

## Stone centres float just off the surface so they never z-fight with the painted grid.
const STONE_Z := -0.03

static var _disc_tex: ImageTexture = null
static var _ring_tex: ImageTexture = null

var board: GoBoardState = null
var input_enabled: bool = true
## Optional announcement played before a stone appears, so something can fly in ahead of
## it: `func(color: int, world_target: Vector3) -> float`, returning the seconds to wait.
## The board state is already updated — only this view holds back.
var move_herald: Callable = Callable()
## Stones waiting out a herald. A capture that arrives meanwhile must not repaint early.
var _pending_paints: int = 0
## Bumped whenever the board is swapped, so heralds still in flight drop their paint.
var _paint_epoch: int = 0
var _stone_root: Node3D = null
var _eval_root: Node3D = null
var _eval: GoEvalSnapshot = null
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
	## Own root: stone rebuilds must not wipe the eval overlay and vice versa.
	if _eval_root != null:
		_eval_root.queue_free()
	_eval_root = Node3D.new()
	_eval_root.name = "EvalMarkers"
	add_child(_eval_root)
	_eval = null
	_reset_pending_paints()
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


## Swap the logical board (e.g. 9↔19 in setup) and repaint grid + stones.
func apply_board(p_board: GoBoardState) -> void:
	if board != null:
		if board.moved.is_connected(_on_moved):
			board.moved.disconnect(_on_moved)
		if board.captured.is_connected(_on_captured):
			board.captured.disconnect(_on_captured)
		if board.reset.is_connected(_rebuild_stones):
			board.reset.disconnect(_rebuild_stones)
	board = p_board
	_board_n = board.size if board != null else _board_n
	_reset_pending_paints()
	clear_eval()
	_paint_grid()
	if board != null:
		if not board.moved.is_connected(_on_moved):
			board.moved.connect(_on_moved)
		if not board.captured.is_connected(_on_captured):
			board.captured.connect(_on_captured)
		if not board.reset.is_connected(_rebuild_stones):
			board.reset.connect(_rebuild_stones)
	_rebuild_stones()


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
	var hoshi := GamingComposer.hoshi_points(n)
	for hi in range(hoshi.size()):
		var hz: int = hoshi[hi]
		for hj in range(hoshi.size()):
			var hx: int = hoshi[hj]
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
	## Nearest crossing. Lay-flat + south seat: local +X is east (right), local +Y is
	## north (far) — same axes as the giant board's GTP x/y, so no mirror.
	var last := float(_board_n - 1)
	var x := clampi(int(round(u * last)), 0, _board_n - 1)
	var y := clampi(int(round(v * last)), 0, _board_n - 1)
	vertex_chosen.emit(GoBoardState.format_vertex(x, y, _board_n))


func _on_moved(color: int, _vertex: String, loc: Vector2i) -> void:
	if move_herald.is_valid() and loc.x >= 0:
		var wait := float(move_herald.call(color, crossing_world(loc.x, loc.y)))
		if wait > 0.0:
			_paint_after(wait)
			return
	_land_stone()


func _paint_after(seconds: float) -> void:
	var epoch := _paint_epoch
	_pending_paints += 1
	await get_tree().create_timer(seconds).timeout
	## A restart or a 9↔19 switch during the flight already repainted from scratch.
	if epoch != _paint_epoch:
		return
	_pending_paints -= 1
	_land_stone()


func _land_stone() -> void:
	_rebuild_stones()
	_play_stone_bling()


func _reset_pending_paints() -> void:
	_paint_epoch += 1
	_pending_paints = 0


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
	## A capture always trails the move that caused it — let that move's paint show both,
	## or the board would lose stones before the stone that took them turns up.
	if _pending_paints > 0:
		return
	_rebuild_stones()


func _rebuild_stones() -> void:
	if _stone_root == null:
		return
	for c in _stone_root.get_children():
		c.queue_free()
	if board == null:
		return
	var cell_m := _cell_m()
	for y in range(board.size):
		for x in range(board.size):
			var c := board.at(x, y)
			if c == GoBoardState.EMPTY:
				continue
			var at := _crossing_local(x, y)
			var mesh := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = cell_m * 0.45
			sphere.height = sphere.radius * 2.0
			mesh.mesh = sphere
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.08, 0.08, 0.09) if c == GoBoardState.BLACK else Color(0.92, 0.92, 0.9)
			mesh.material_override = mat
			mesh.position = Vector3(at.x, at.y, STONE_Z)
			_stone_root.add_child(mesh)


## Distance between two neighbouring crossings, in panel-local metres.
func _cell_m() -> float:
	var span := size_m.x * (1.0 - 2.0 * MARGIN_FRAC)
	var last := float(maxi(_board_n - 1, 1))
	return span / last


## World point where a stone on this crossing sits — what off-board effects aim at.
func crossing_world(x: int, y: int) -> Vector3:
	var at := _crossing_local(x, y)
	return to_global(Vector3(at.x, at.y, STONE_Z))


## Panel-local XY of a board crossing (same axes the click mapping uses).
func _crossing_local(x: int, y: int) -> Vector2:
	var half := size_m * 0.5
	var play_bottom := -half.y + size_m.y * MARGIN_FRAC
	var play_top := half.y - size_m.y * MARGIN_FRAC
	var play_left := -half.x + size_m.x * MARGIN_FRAC
	var play_right := half.x - size_m.x * MARGIN_FRAC
	var last := float(maxi(_board_n - 1, 1))
	return Vector2(
		lerpf(play_left, play_right, float(x) / last),
		lerpf(play_bottom, play_top, float(y) / last)
	)


## Show what the AI's own search considered. Stays up through the human's reply so the
## position can be studied; the session clears it as soon as a stone lands.
func set_eval(snapshot: GoEvalSnapshot) -> void:
	if snapshot == null:
		push_error("GoTableUi3D.set_eval: null snapshot — call clear_eval instead")
		return
	_eval = snapshot
	_rebuild_eval_markers()


func clear_eval() -> void:
	_eval = null
	_rebuild_eval_markers()


func _rebuild_eval_markers() -> void:
	if _eval_root == null:
		return
	for c in _eval_root.get_children():
		c.queue_free()
	if _eval == null or _eval.board_n != _board_n:
		return
	var top := _eval.top_visits()
	if top <= 0:
		return
	var cell_m := _cell_m()
	var shown := 0
	var labelled := 0
	for cand in _eval.candidates:
		if shown >= EVAL_MAX_MARKERS:
			break
		if not cand.is_on_board():
			continue
		## Tail entries carry a policy prior but no search — they were never considered.
		if cand.visits <= 0:
			continue
		## The played move wears the ring instead — a disc there hides under its stone.
		if cand.loc == _eval.chosen_loc:
			continue
		var share := clampf(float(cand.visits) / float(top), 0.0, 1.0)
		_add_candidate_disc(cand.loc, share, cell_m)
		shown += 1
		if labelled < EVAL_MAX_LABELS and share >= EVAL_LABEL_MIN_SHARE and _eval.visits > 0:
			var pct := int(round(float(cand.visits) * 100.0 / float(_eval.visits)))
			_add_marker_label("%d" % pct, cand.loc, cell_m)
			labelled += 1
	if _eval.chosen_loc.x >= 0:
		_add_chosen_ring(_eval.chosen_loc, cell_m)


func _add_candidate_disc(loc: Vector2i, share: float, cell_m: float) -> void:
	var radius := cell_m * lerpf(0.3, 0.52, share)
	var tint := Color(0.13, 0.79, 0.48, lerpf(0.55, 0.95, share))
	_add_marker_quad(_shared_disc_tex(), tint, loc, radius)


func _add_chosen_ring(loc: Vector2i, cell_m: float) -> void:
	_add_marker_quad(_shared_ring_tex(), Color(1.0, 0.76, 0.22, 0.95), loc, cell_m * 0.66)


## Flat sprite in the panel plane. A QuadMesh needs no rotation here (same convention as
## every Ui3D button), which keeps the marker orientation independent of mesh defaults.
func _add_marker_quad(tex: Texture2D, tint: Color, loc: Vector2i, radius: float) -> void:
	var at := _crossing_local(loc.x, loc.y)
	var mesh_inst := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	mesh_inst.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.albedo_color = tint
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_inst.material_override = mat
	mesh_inst.position = Vector3(at.x, at.y, EVAL_DISC_Z)
	_eval_root.add_child(mesh_inst)


static func _shared_disc_tex() -> ImageTexture:
	if _disc_tex == null:
		_disc_tex = _make_radial_tex(0.0, 0.94)
	return _disc_tex


static func _shared_ring_tex() -> ImageTexture:
	if _ring_tex == null:
		_ring_tex = _make_radial_tex(0.7, 0.96)
	return _ring_tex


## White sprite whose alpha covers the band between two radii (0..1 of the half-width),
## with a one-texel-ish feather so small on-screen markers do not look jagged.
static func _make_radial_tex(inner: float, outer: float) -> ImageTexture:
	var img := Image.create(EVAL_TEX_PX, EVAL_TEX_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 0.0))
	var half := float(EVAL_TEX_PX) * 0.5
	var feather := 1.5 / half
	for py in range(EVAL_TEX_PX):
		for px in range(EVAL_TEX_PX):
			var dx := (float(px) + 0.5 - half) / half
			var dy := (float(py) + 0.5 - half) / half
			var r := sqrt(dx * dx + dy * dy)
			var a := smoothstep(outer, outer - feather, r)
			if inner > 0.0:
				a = minf(a, smoothstep(inner, inner + feather, r))
			if a > 0.0:
				img.set_pixel(px, py, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


func _add_marker_label(text: String, loc: Vector2i, cell_m: float) -> void:
	var at := _crossing_local(loc.x, loc.y)
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 64
	lbl.pixel_size = (cell_m * 0.34) / 64.0
	lbl.modulate = Color(1.0, 1.0, 1.0)
	lbl.outline_size = 18
	lbl.outline_modulate = Color(0.0, 0.12, 0.07, 0.95)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lbl.double_sided = true
	## Sorted after its own disc. `no_depth_test` would instead hide the disc entirely,
	## because Godot draws depth-test-disabled transparents ahead of the rest.
	lbl.render_priority = 1
	## QuadMesh faces −Z; Label3D faces +Z by default — flip to match the panel face.
	lbl.position = Vector3(at.x, at.y, EVAL_LABEL_Z)
	lbl.rotation.y = PI
	_eval_root.add_child(lbl)
