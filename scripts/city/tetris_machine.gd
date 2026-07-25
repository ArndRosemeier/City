## Tall open-frame Tetris: GAMEBOY voxel shell + MultiMesh pieces. Summon with T.
## Controls: 1 left · 2 rotate · 3 right · 4 fast drop (tap once per piece).
## Any destroyed shell voxel breaks the machine.
class_name TetrisMachine
extends Node3D

const COLS := 10
const ROWS := 20
const CELL := 0.5
## Outer frame / pedestal (meters).
const FRAME_W := 7.0
const FRAME_H := 14.0
const WELL_DEPTH := 1.2
const LOCK_DELAY_SEC := 0.5
const LOCK_RESET_MAX := 15
const DAS_DELAY_SEC := 0.18
const DAS_REPEAT_SEC := 0.05
const CLEAR_FLASH_SEC := 0.22
## Seconds per cell at level 1 (continuous fall).
const GRAVITY_BASE_SEC := 1.4
## Tap 4: latch fast continuous fall until lock (not instant hard drop).
const SOFT_DROP_SEC := 0.07
const INTEGRITY_CHECK_SEC := 0.2
## Cube edge as a fraction of the cell — gap keeps neighbour faces from touching.
const BLOCK_FILL := 0.9

const PIECE_I := 1
const PIECE_J := 2
const PIECE_L := 3
const PIECE_O := 4
const PIECE_S := 5
const PIECE_T := 6
const PIECE_Z := 7

var _SHAPES: Dictionary = {}

var _cell_size: float = CELL
var _board: PackedByteArray = PackedByteArray()
var _bag: Array[int] = []
var _rng := RandomNumberGenerator.new()

var _active_id: int = 0
var _active_rot: int = 0
var _active_x: int = 0
var _active_y: int = 0
var _game_over: bool = false
var _broken: bool = false
var _clearing: bool = false
var _clear_timer: float = 0.0
var _clear_rows: Array[int] = []
var _integrity_timer: float = 0.0

## 0..1 progress toward the next cell below (smooth visual fall).
var _fall_t: float = 0.0
var _lock_accum: float = 0.0
var _locking: bool = false
var _lock_resets: int = 0
var _soft_dropping: bool = false

var _score: int = 0
var _lines: int = 0
var _level: int = 1

var _das_dir: int = 0
var _das_timer: float = 0.0
var _das_repeating: bool = false

## Per-piece-type locked Multimeshes (no vertex-color buffer rebuilds → no flicker).
var _board_mms: Array[MultiMeshInstance3D] = []
var _active_blocks: Array[MeshInstance3D] = []
var _ghost_blocks: Array[MeshInstance3D] = []
var _hud: Label3D
var _title: Label3D
var _game_over_label: Label3D

var _mat_ghost: ShaderMaterial
var _piece_mats: Array[Material] = []
var _block_shader: Shader
var _ghost_shader: Shader

var _terrain: VoxelTerrain
var _tool: VoxelTool
## World voxel cells that belong to this cabinet shell.
var _owned_voxels: Dictionary = {}  # Vector3i → true

## Bottom-left cell center of the playfield (local).
var _pf_origin: Vector3 = Vector3.ZERO
## Center Z of pieces inside the well.
var _piece_z: float = 0.0
## When false, keys 1–4 are ignored (NPC / AI owns the cabinet).
var _input_enabled: bool = true
var _ai_controller: Node = null


func begin(
	terrain: VoxelTerrain,
	tool: VoxelTool,
	ground_hit: Vector3,
	face_yaw: float,
	cell_size: float = CELL
) -> void:
	if terrain == null or tool == null:
		push_error("TetrisMachine.begin: terrain/tool required")
		return
	_terrain = terrain
	_tool = tool
	_cell_size = maxf(cell_size, 0.1)
	_rng.randomize()
	_init_shapes()
	_init_materials()
	global_position = Vector3(ground_hit.x, ground_hit.y, ground_hit.z)
	rotation.y = face_yaw
	_stamp_voxel_shell()
	_build_piece_visuals()
	_build_labels()
	_board.resize(COLS * ROWS)
	_board.fill(0)
	_reset_bag()
	_spawn_piece()
	_refresh_board_visual()
	_refresh_active_visual()
	_refresh_hud()


func _ready() -> void:
	set_process_unhandled_input(true)
	set_process(true)
	set_physics_process(true)


func is_playable() -> bool:
	return not _broken and not _game_over and not _clearing and _active_id > 0


func is_broken() -> bool:
	return _broken


func is_game_over() -> bool:
	return _game_over


func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	_das_dir = 0
	_das_repeating = false


func claim_ai_controller(controller: Node) -> bool:
	if _broken:
		return false
	if _ai_controller != null and is_instance_valid(_ai_controller) and _ai_controller != controller:
		return false
	_ai_controller = controller
	set_input_enabled(false)
	return true


func release_ai_controller(controller: Node) -> void:
	if _ai_controller == controller:
		_ai_controller = null
		if not _broken and not _game_over:
			set_input_enabled(true)


func get_stand_world_position() -> Vector3:
	## Pedestal front (local −Z), where an NPC faces the screen.
	return to_global(Vector3(0.0, 0.0, -1.85))


func get_facing_yaw() -> float:
	return rotation.y


func get_board_snapshot() -> PackedByteArray:
	return _board.duplicate()


func get_active_piece() -> Dictionary:
	if _active_id <= 0:
		return {}
	return {
		"id": _active_id,
		"rot": _active_rot,
		"x": _active_x,
		"y": _active_y,
	}


func cells_for_piece(piece_id: int, rot: int) -> Array[Vector2i]:
	return _cells_for(piece_id, rot)


func fits_at(piece_id: int, rot: int, ox: int, oy: int) -> bool:
	return _fits(piece_id, rot, ox, oy)


func try_ai_left() -> bool:
	if not is_playable():
		return false
	return _try_move(1, 0)


func try_ai_right() -> bool:
	if not is_playable():
		return false
	return _try_move(-1, 0)


func try_ai_rotate(dir: int = 1) -> bool:
	if not is_playable():
		return false
	return _try_rotate(dir)


func try_ai_soft_drop() -> bool:
	if not is_playable():
		return false
	_soft_dropping = true
	return true


func _init_shapes() -> void:
	_SHAPES[PIECE_I] = [[Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]]
	_SHAPES[PIECE_J] = [[Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0)]]
	_SHAPES[PIECE_L] = [[Vector2i(1, 1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0)]]
	_SHAPES[PIECE_O] = [[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]]
	_SHAPES[PIECE_S] = [[Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1)]]
	_SHAPES[PIECE_T] = [[Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]]
	_SHAPES[PIECE_Z] = [[Vector2i(-1, 0), Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)]]


func _cells_for(piece_id: int, rot: int) -> Array[Vector2i]:
	var base: Array = _SHAPES[piece_id][0]
	var out: Array[Vector2i] = []
	var r := rot % 4
	if piece_id == PIECE_O:
		r = 0
	for raw in base:
		var c: Vector2i = raw
		for _i in r:
			c = Vector2i(c.y, -c.x)
		out.append(c)
	return out


func _init_materials() -> void:
	_block_shader = load("res://assets/city/shaders/tetris_block.gdshader") as Shader
	_ghost_shader = load("res://assets/city/shaders/tetris_ghost.gdshader") as Shader
	if _block_shader == null or _ghost_shader == null:
		push_error("TetrisMachine: tetris block/ghost shader missing")
		return
	_mat_ghost = _make_ghost_mat(Color(0.8, 0.96, 0.62))
	_piece_mats.clear()
	_piece_mats.resize(8)
	_piece_mats[0] = null
	_piece_mats[PIECE_I] = _make_block_mat(Color(0.15, 0.9, 0.95), 0.45, 1.3)
	_piece_mats[PIECE_J] = _make_block_mat(Color(0.2, 0.35, 0.95), 0.4, 1.15)
	_piece_mats[PIECE_L] = _make_block_mat(Color(0.98, 0.55, 0.12), 0.42, 1.2)
	_piece_mats[PIECE_O] = _make_block_mat(Color(0.98, 0.9, 0.15), 0.45, 1.3)
	_piece_mats[PIECE_S] = _make_block_mat(Color(0.2, 0.92, 0.3), 0.4, 1.15)
	_piece_mats[PIECE_T] = _make_block_mat(Color(0.78, 0.28, 0.95), 0.42, 1.2)
	_piece_mats[PIECE_Z] = _make_block_mat(Color(0.95, 0.18, 0.22), 0.42, 1.2)


func _block_half_extent() -> float:
	return _cell_size * BLOCK_FILL * 0.5


func _make_block_mat(color: Color, emission_base: float, emission_peak: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _block_shader
	m.set_shader_parameter("block_color", color)
	m.set_shader_parameter("edge_color", Color(1, 1, 1).lerp(color.lightened(0.5), 0.4))
	m.set_shader_parameter("core_color", color.lightened(0.65))
	m.set_shader_parameter("mesh_half", _block_half_extent())
	m.set_shader_parameter("emission_base", emission_base)
	m.set_shader_parameter("emission_peak", emission_peak)
	m.set_shader_parameter("pulse_hz", 0.75)
	m.set_shader_parameter("bevel", 0.22)
	m.set_shader_parameter("seam", 0.05)
	m.set_shader_parameter("ring_radius", 0.56)
	m.set_shader_parameter("ring_width", 0.07)
	m.set_shader_parameter("stud_scale", 3.0)
	m.set_shader_parameter("stud_size", 0.17)
	m.set_shader_parameter("gloss", 0.6)
	return m


func _make_ghost_mat(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _ghost_shader
	m.set_shader_parameter("ghost_color", color)
	m.set_shader_parameter("mesh_half", _block_half_extent())
	m.set_shader_parameter("frame_width", 0.15)
	m.set_shader_parameter("strength", 0.5)
	m.set_shader_parameter("fill", 0.06)
	m.set_shader_parameter("pulse_hz", 1.0)
	return m


func _stamp_voxel_shell() -> void:
	## Open well facing -Z: stamp GAMEBOY voxels. Pieces stay MultiMesh inside the well.
	var cs := _cell_size
	var well_w := float(COLS) * cs
	var well_h := float(ROWS) * cs
	var ped_h := 2.0
	var rail := cs
	var depth := WELL_DEPTH

	var x0 := -well_w * 0.5
	var y0 := ped_h
	_pf_origin = Vector3(x0 + cs * 0.5, y0 + cs * 0.5, depth * 0.5)
	_piece_z = depth * 0.5

	_owned_voxels.clear()
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = VoxelMaterial.GAMEBOY

	_stamp_box_m(Vector3(0.0, ped_h * 0.5, depth * 0.5 + 0.05), Vector3(FRAME_W, ped_h, depth + 0.4))
	_stamp_box_m(
		Vector3(x0 - rail * 0.5, y0 + well_h * 0.5, depth * 0.5),
		Vector3(rail, well_h, depth)
	)
	_stamp_box_m(
		Vector3(x0 + well_w + rail * 0.5, y0 + well_h * 0.5, depth * 0.5),
		Vector3(rail, well_h, depth)
	)
	_stamp_box_m(Vector3(0.0, y0 - rail * 0.5, depth * 0.5), Vector3(well_w, rail, depth))
	_stamp_box_m(
		Vector3(0.0, y0 + well_h * 0.5, depth - rail * 0.25),
		Vector3(well_w, well_h, rail * 0.5)
	)
	_stamp_box_m(
		Vector3(0.0, y0 + well_h + rail * 0.75, depth * 0.5),
		Vector3(well_w + rail * 2.0, rail * 1.5, depth)
	)
	var header_y := y0 + well_h + rail * 1.5
	var header_h := FRAME_H - header_y
	_stamp_box_m(
		Vector3(0.0, header_y + header_h * 0.5, depth * 0.5 + 0.075),
		Vector3(FRAME_W * 0.84, header_h, depth + 0.35)
	)
	var btn := cs * 0.55
	var btn_y := 0.7
	for d in [
		Vector3(-1.2, 0, 0),
		Vector3(-0.7, 0, 0),
		Vector3(-1.7, 0, 0),
		Vector3(-1.2, 0.5, 0),
		Vector3(-1.2, -0.5, 0),
	]:
		_stamp_box_m(Vector3(d.x, btn_y + d.y, -0.05), Vector3(btn, btn, btn))
	_stamp_box_m(Vector3(1.0, btn_y + 0.35, -0.05), Vector3(btn, btn, btn))
	_stamp_box_m(Vector3(1.6, btn_y, -0.05), Vector3(btn, btn, btn))

	_title = Label3D.new()
	_title.name = "Title"
	_title.text = "TETRIS"
	_title.font_size = 160
	_title.modulate = Color(0.15, 0.22, 0.12)
	_title.outline_size = 24
	_title.outline_modulate = Color(0.75, 0.88, 0.55, 1.0)
	## Sit proud of the voxel header face (local -Z = toward the player).
	_title.position = Vector3(0.0, FRAME_H - 0.9, -0.55)
	_title.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_title.rotation.y = PI
	_title.double_sided = true
	_title.no_depth_test = true
	_title.render_priority = 10
	add_child(_title)


func _stamp_box_m(center_local: Vector3, size_m: Vector3) -> void:
	var cs := _cell_size
	var half := size_m * 0.5
	var min_c := center_local - half
	var max_c := center_local + half
	var x := min_c.x + cs * 0.5
	while x < max_c.x - 0.001:
		var y := min_c.y + cs * 0.5
		while y < max_c.y - 0.001:
			var z := min_c.z + cs * 0.5
			while z < max_c.z - 0.001:
				_stamp_local_point(Vector3(x, y, z))
				z += cs
			y += cs
		x += cs


func _stamp_local_point(local_pos: Vector3) -> void:
	var world := to_global(local_pos)
	var local_t := _terrain.to_local(world)
	var vox := Vector3i(
		int(floor(local_t.x)),
		int(floor(local_t.y)),
		int(floor(local_t.z))
	)
	if vox.y < 1:
		vox.y = 1
	var existing := int(_tool.get_voxel(vox))
	if existing == VoxelMaterial.BEDROCK or existing == VoxelMaterial.WATER:
		return
	_tool.value = VoxelMaterial.GAMEBOY
	_tool.do_point(vox)
	_owned_voxels[vox] = true


func clear_shell() -> void:
	## Remove remaining cabinet voxels (replace / regenerate). Leaves debris alone.
	if _tool == null or _owned_voxels.is_empty():
		_owned_voxels.clear()
		return
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = VoxelMaterial.AIR
	for key in _owned_voxels.keys():
		var vox: Vector3i = key
		if int(_tool.get_voxel(vox)) == VoxelMaterial.GAMEBOY:
			_tool.do_point(vox)
	_owned_voxels.clear()


func notify_voxels_carved(vox_entries: Array) -> void:
	if _broken or _owned_voxels.is_empty():
		return
	for item in vox_entries:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var vox: Vector3i = item.get("vox", Vector3i(2147483647, 2147483647, 2147483647))
		var mat_id := int(item.get("mat", -1))
		if mat_id == VoxelMaterial.GAMEBOY or _owned_voxels.has(vox):
			_break_machine()
			return


func check_integrity() -> void:
	if _broken or _tool == null or _owned_voxels.is_empty():
		return
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	for key in _owned_voxels.keys():
		var vox: Vector3i = key
		if int(_tool.get_voxel(vox)) != VoxelMaterial.GAMEBOY:
			_break_machine()
			return


func _break_machine() -> void:
	if _broken:
		return
	_broken = true
	_game_over = true
	_active_id = 0
	_soft_dropping = false
	_locking = false
	_clearing = false
	_das_dir = 0
	_refresh_active_visual()
	## Labels / HUD are Node3D props — hide them so they don't float after the shell is gone.
	_hide_overlay_labels()
	for mmi in _board_mms:
		if mmi != null:
			mmi.visible = false


func _hide_overlay_labels() -> void:
	if _title != null:
		_title.visible = false
	if _hud != null:
		_hud.visible = false
	if _game_over_label != null:
		_game_over_label.visible = false


func _build_piece_visuals() -> void:
	_board_mms.clear()
	_board_mms.resize(8)
	var cap := COLS * ROWS
	for pid in range(1, 8):
		var mmi := _alloc_mm("Board_%d" % pid, cap, _piece_mats[pid])
		mmi.multimesh.visible_instance_count = 0
		_board_mms[pid] = mmi

	_active_blocks.clear()
	_ghost_blocks.clear()
	for i in 4:
		var a := _make_block_mi("Active_%d" % i, _piece_mats[PIECE_I])
		a.visible = false
		_active_blocks.append(a)
		var g := _make_block_mi("Ghost_%d" % i, _mat_ghost)
		g.visible = false
		_ghost_blocks.append(g)


func _disable_shadows(gi: GeometryInstance3D) -> void:
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED


func _alloc_mm(mm_name: String, count: int, mat: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.instance_count = maxi(count, 1)
	mm.visible_instance_count = 0
	var box := BoxMesh.new()
	## Full cell cubes with tiny gap so faces read as 3D voxels.
	box.size = Vector3.ONE * (_cell_size * BLOCK_FILL)
	mm.mesh = box
	var inst := MultiMeshInstance3D.new()
	inst.name = mm_name
	inst.multimesh = mm
	inst.material_override = mat
	_disable_shadows(inst)
	## Huge AABB so the open well never frustum-culls mid-play.
	mm.custom_aabb = AABB(Vector3(-20, -5, -5), Vector3(40, 40, 20))
	add_child(inst)
	return inst


func _make_block_mi(mi_name: String, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = mi_name
	var box := BoxMesh.new()
	box.size = Vector3.ONE * (_cell_size * BLOCK_FILL)
	mi.mesh = box
	mi.material_override = mat
	_disable_shadows(mi)
	add_child(mi)
	return mi


func _build_labels() -> void:
	_hud = Label3D.new()
	_hud.name = "ScoreHud"
	_hud.font_size = 72
	_hud.modulate = Color(0.2, 0.95, 0.35)
	## Front of pedestal, clear of voxel volume so score stays readable.
	_hud.position = Vector3(0.0, 1.15, -0.55)
	_hud.rotation.y = PI
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hud.outline_size = 18
	_hud.outline_modulate = Color(0.02, 0.06, 0.02, 0.95)
	_hud.no_depth_test = true
	_hud.render_priority = 10
	_hud.double_sided = true
	add_child(_hud)

	_game_over_label = Label3D.new()
	_game_over_label.name = "GameOver"
	_game_over_label.text = "GAME OVER"
	_game_over_label.font_size = 110
	_game_over_label.modulate = Color(1.0, 0.25, 0.2)
	_game_over_label.position = _pf_origin + Vector3(
		float(COLS - 1) * _cell_size * 0.5,
		float(ROWS - 1) * _cell_size * 0.45,
		-_cell_size * 1.2
	)
	_game_over_label.rotation.y = PI
	_game_over_label.outline_size = 20
	_game_over_label.outline_modulate = Color(0, 0, 0, 0.95)
	_game_over_label.no_depth_test = true
	_game_over_label.render_priority = 11
	_game_over_label.visible = false
	add_child(_game_over_label)


func _board_index(x: int, y: int) -> int:
	return y * COLS + x


func _get_cell(x: int, y: int) -> int:
	if x < 0 or x >= COLS or y < 0 or y >= ROWS:
		return -1
	return int(_board[_board_index(x, y)])


func _set_cell(x: int, y: int, v: int) -> void:
	if x < 0 or x >= COLS or y < 0 or y >= ROWS:
		return
	_board[_board_index(x, y)] = v


func _reset_bag() -> void:
	_bag = [PIECE_I, PIECE_J, PIECE_L, PIECE_O, PIECE_S, PIECE_T, PIECE_Z]
	for i in range(_bag.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := _bag[i]
		_bag[i] = _bag[j]
		_bag[j] = tmp


func _next_from_bag() -> int:
	if _bag.is_empty():
		_reset_bag()
	return _bag.pop_back()


func _spawn_piece() -> void:
	_active_id = _next_from_bag()
	_active_rot = 0
	_active_x = COLS / 2 - 1
	_active_y = ROWS - 2
	_fall_t = 0.0
	_locking = false
	_lock_accum = 0.0
	_lock_resets = 0
	_soft_dropping = false
	if not _fits(_active_id, _active_rot, _active_x, _active_y):
		_game_over = true
		_game_over_label.visible = true
		_active_id = 0
		_refresh_active_visual()
		_refresh_hud()
		return
	_refresh_active_visual()


func _fits(pid: int, rot: int, ox: int, oy: int) -> bool:
	if pid <= 0:
		return false
	for c in _cells_for(pid, rot):
		var x := ox + c.x
		var y := oy + c.y
		if x < 0 or x >= COLS or y < 0:
			return false
		if y >= ROWS:
			continue
		if _get_cell(x, y) != 0:
			return false
	return true


func _try_move(dx: int, dy: int) -> bool:
	if _game_over or _clearing or _active_id <= 0:
		return false
	var nx := _active_x + dx
	var ny := _active_y + dy
	if not _fits(_active_id, _active_rot, nx, ny):
		return false
	_active_x = nx
	_active_y = ny
	if dy != 0:
		_locking = false
		_lock_accum = 0.0
		_fall_t = 0.0
	elif _locking and _lock_resets < LOCK_RESET_MAX:
		_lock_accum = 0.0
		_lock_resets += 1
	_refresh_active_visual()
	return true


func _try_rotate(dir: int) -> bool:
	if _game_over or _clearing or _active_id <= 0:
		return false
	if _active_id == PIECE_O:
		return true
	var nrot := (_active_rot + dir) % 4
	if nrot < 0:
		nrot += 4
	var kicks: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(0, -1),
		Vector2i(-2, 0),
		Vector2i(2, 0),
		Vector2i(-1, -1),
		Vector2i(1, -1),
		Vector2i(0, 1),
	]
	for k in kicks:
		if _fits(_active_id, nrot, _active_x + k.x, _active_y + k.y):
			_active_rot = nrot
			_active_x += k.x
			_active_y += k.y
			if _locking and _lock_resets < LOCK_RESET_MAX:
				_lock_accum = 0.0
				_lock_resets += 1
			_refresh_active_visual()
			return true
	return false


func _hard_drop() -> void:
	if _game_over or _clearing or _active_id <= 0:
		return
	var dist := 0
	while _fits(_active_id, _active_rot, _active_x, _active_y - 1):
		_active_y -= 1
		dist += 1
	_fall_t = 0.0
	_score += dist * 2
	_lock_piece()


func _lock_piece() -> void:
	if _active_id <= 0:
		return
	for c in _cells_for(_active_id, _active_rot):
		var x := _active_x + c.x
		var y := _active_y + c.y
		if y >= ROWS:
			continue
		if y < 0 or x < 0 or x >= COLS:
			_game_over = true
			_game_over_label.visible = true
			_active_id = 0
			_refresh_active_visual()
			_refresh_hud()
			return
		_set_cell(x, y, _active_id)
	_active_id = 0
	_locking = false
	_refresh_board_visual()
	_refresh_active_visual()
	_find_and_clear_lines()


func _find_and_clear_lines() -> void:
	_clear_rows.clear()
	for y in ROWS:
		var full := true
		for x in COLS:
			if _get_cell(x, y) == 0:
				full = false
				break
		if full:
			_clear_rows.append(y)
	if _clear_rows.is_empty():
		_spawn_piece()
		_refresh_hud()
		return
	_clearing = true
	_clear_timer = CLEAR_FLASH_SEC
	_refresh_board_visual_hiding_rows(_clear_rows)


func _finish_clear() -> void:
	var n := _clear_rows.size()
	var new_board := PackedByteArray()
	new_board.resize(COLS * ROWS)
	new_board.fill(0)
	var dest := 0
	for y in ROWS:
		if _clear_rows.has(y):
			continue
		for x in COLS:
			new_board[dest * COLS + x] = _board[y * COLS + x]
		dest += 1
	_board = new_board
	var points := 0
	match n:
		1:
			points = 100
		2:
			points = 300
		3:
			points = 500
		_:
			points = 800
	_score += points * _level
	_lines += n
	_level = 1 + int(_lines / 10)
	_clearing = false
	_clear_rows.clear()
	_refresh_board_visual()
	_spawn_piece()
	_refresh_hud()


func _gravity_interval() -> float:
	## Gentle level ramp; tap 4 latches a fast continuous fall until the piece locks.
	if _soft_dropping:
		return SOFT_DROP_SEC
	var base := GRAVITY_BASE_SEC / (1.0 + float(_level - 1) * 0.12)
	return maxf(base, 0.45)


func _display_y() -> float:
	if _locking or not _fits(_active_id, _active_rot, _active_x, _active_y - 1):
		return float(_active_y)
	return float(_active_y) - clampf(_fall_t, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	_update_das(delta)


func _process(delta: float) -> void:
	if _broken:
		return
	_integrity_timer += delta
	if _integrity_timer >= INTEGRITY_CHECK_SEC:
		_integrity_timer = 0.0
		check_integrity()
		if _broken:
			return
	if _game_over:
		return
	if _clearing:
		_clear_timer -= delta
		## Hold cleared rows hidden (no buffer thrash / blink flicker).
		if _clear_timer <= 0.0:
			_finish_clear()
		return
	if _active_id <= 0:
		return

	var can_fall := _fits(_active_id, _active_rot, _active_x, _active_y - 1)
	if can_fall:
		_locking = false
		_lock_accum = 0.0
		var interval := _gravity_interval()
		_fall_t += delta / interval
		while _fall_t >= 1.0:
			if not _fits(_active_id, _active_rot, _active_x, _active_y - 1):
				_fall_t = 0.0
				_locking = true
				break
			_active_y -= 1
			_fall_t -= 1.0
			if _soft_dropping:
				_score += 1
				_refresh_hud()
		_refresh_active_visual()
	else:
		_fall_t = 0.0
		if not _locking:
			_locking = true
			_lock_accum = 0.0
		_refresh_active_visual()

	if _locking:
		_lock_accum += delta
		if _lock_accum >= LOCK_DELAY_SEC:
			_lock_piece()


func _tetris_key_id(ek: InputEventKey) -> int:
	## Number-row / numpad 1–4 — same physical place on QWERTY/QWERTZ/AZERTY.
	match ek.physical_keycode:
		KEY_1, KEY_KP_1:
			return 1
		KEY_2, KEY_KP_2:
			return 2
		KEY_3, KEY_KP_3:
			return 3
		KEY_4, KEY_KP_4:
			return 4
		_:
			pass
	match ek.keycode:
		KEY_1, KEY_KP_1:
			return 1
		KEY_2, KEY_KP_2:
			return 2
		KEY_3, KEY_KP_3:
			return 3
		KEY_4, KEY_KP_4:
			return 4
		_:
			return 0


func _unhandled_input(event: InputEvent) -> void:
	if _broken or _game_over or not _input_enabled:
		return
	if event is InputEventKey:
		var ek := event as InputEventKey
		var kid := _tetris_key_id(ek)
		if kid == 0:
			return
		if ek.echo:
			return
		if ek.pressed:
			match kid:
				1:
					## Screen-left from the player facing the machine (local +X).
					_das_dir = 1
					_das_timer = 0.0
					_das_repeating = false
					_try_move(1, 0)
				2:
					_try_rotate(1)
				3:
					## Screen-right from the player facing the machine (local -X).
					_das_dir = -1
					_das_timer = 0.0
					_das_repeating = false
					_try_move(-1, 0)
				4:
					## One tap: keep falling fast until this piece locks.
					_soft_dropping = true
			get_viewport().set_input_as_handled()
		else:
			match kid:
				1:
					if _das_dir > 0:
						_das_dir = 0
				3:
					if _das_dir < 0:
						_das_dir = 0
			get_viewport().set_input_as_handled()


func _update_das(delta: float) -> void:
	if _das_dir == 0 or _game_over or _clearing:
		return
	_das_timer += delta
	if not _das_repeating:
		if _das_timer >= DAS_DELAY_SEC:
			_das_repeating = true
			_das_timer = 0.0
			_try_move(_das_dir, 0)
	else:
		if _das_timer >= DAS_REPEAT_SEC:
			_das_timer = 0.0
			_try_move(_das_dir, 0)


func _cell_world_local(bx: float, by: float) -> Vector3:
	return Vector3(
		_pf_origin.x + bx * _cell_size,
		_pf_origin.y + by * _cell_size,
		_piece_z
	)


func _refresh_board_visual() -> void:
	_refresh_board_visual_hiding_rows([])


func _refresh_board_visual_hiding_rows(hide: Array[int]) -> void:
	if _board_mms.is_empty():
		return
	var counts: PackedInt32Array = PackedInt32Array()
	counts.resize(8)
	counts.fill(0)
	for y in ROWS:
		if hide.has(y):
			continue
		for x in COLS:
			var v := _get_cell(x, y)
			if v <= 0 or v >= 8:
				continue
			var mmi := _board_mms[v]
			if mmi == null:
				continue
			var i := int(counts[v])
			if i >= mmi.multimesh.instance_count:
				continue
			mmi.multimesh.set_instance_transform(
				i, Transform3D(Basis.IDENTITY, _cell_world_local(x, y))
			)
			counts[v] = i + 1
	for pid in range(1, 8):
		var mmi2 := _board_mms[pid]
		if mmi2 != null:
			mmi2.multimesh.visible_instance_count = int(counts[pid])


func _refresh_active_visual() -> void:
	if _active_blocks.is_empty():
		return
	if _active_id <= 0:
		for b in _active_blocks:
			b.visible = false
		for g in _ghost_blocks:
			g.visible = false
		return

	var cells := _cells_for(_active_id, _active_rot)
	var mat := _piece_mats[_active_id]
	var dy := _display_y()
	var i := 0
	for c in cells:
		var x := float(_active_x + c.x)
		var y := dy + float(c.y)
		var block := _active_blocks[i]
		if y >= float(ROWS):
			block.visible = false
		else:
			block.material_override = mat
			block.position = _cell_world_local(x, y)
			block.visible = true
		i += 1
	while i < 4:
		_active_blocks[i].visible = false
		i += 1

	var gy := _active_y
	while _fits(_active_id, _active_rot, _active_x, gy - 1):
		gy -= 1
	if gy == _active_y:
		for g in _ghost_blocks:
			g.visible = false
	else:
		var gi := 0
		for c in cells:
			var x := _active_x + c.x
			var y := gy + c.y
			var ghost := _ghost_blocks[gi]
			if y >= ROWS:
				ghost.visible = false
			else:
				ghost.position = _cell_world_local(float(x), float(y))
				ghost.visible = true
			gi += 1
		while gi < 4:
			_ghost_blocks[gi].visible = false
			gi += 1


func _refresh_hud() -> void:
	if _hud == null:
		return
	_hud.text = "SCORE %d\nLINES %d  LV %d" % [_score, _lines, _level]
	if _broken:
		_hud.text += "\nCABINET DESTROYED"
	elif _game_over:
		_hud.text += "\nT TO RESTART"
