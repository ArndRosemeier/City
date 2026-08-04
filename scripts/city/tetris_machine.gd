## Tall open-frame Tetris: GAMEBOY voxel shell + MultiMesh pieces. Summon with T.
## Controls: 1 left · 2 rotate · 3 right · 4 fast drop (tap once per piece).
## Arcade cabinets also expose a small ON/OFF + NEW plate the player can click.
## Any destroyed shell voxel breaks the machine.
class_name TetrisMachine
extends Node3D

const Ui3DScript := preload("res://scripts/city/ui_3d.gd")

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

const BTN_POWER := &"power"
const BTN_NEW := &"new"
## Pedestal face layout (free bay). SCORE / LINES stay exactly where ped cabinets put them;
## hints take the free line above SCORE; NEW/ON sit on the LINES row, left of the well.
const HUD_Y_M := 1.05
const HUD_Z_M := -0.55
## Label3D default pixel_size is 0.01, so font_size 72 is ~0.72 m per line — the same
## figure the centred SCORE\nLINES block uses to straddle HUD_Y_M.
const HUD_LINE_M := 0.72
const HINTS_Y_M := HUD_Y_M + HUD_LINE_M + 0.12
const CONTROLS_W_M := 1.45
const CONTROLS_H_M := 0.42
const CONTROLS_Y_M := HUD_Y_M - HUD_LINE_M * 0.5
const CONTROLS_X_M := -(FRAME_W * 0.5 - CONTROLS_W_M * 0.5 - 0.2)
const CONTROLS_Z_M := -0.7
## Pedestal key cheat-sheet for the free arcade bay. Same Label3D face as the score, own
## colour so it reads as help rather than status. Hidden on ped-owned cabinets.
## Keep to ←→↓ plus a word for rotate: fancy loop arrows are often missing from the
## default Label3D font and show up as the wrong glyph.
const HINTS_TEXT := "1←   2 TURN   3→   4↓"
const HINTS_COLOUR := Color(0.95, 0.82, 0.28)

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
var _hints: Label3D
var _title: Label3D
var _game_over_label: Label3D

var _mat_ghost: ShaderMaterial
var _piece_mats: Array[Material] = []
var _block_shader: Shader
var _ghost_shader: Shader

var _terrain: VoxelTerrain
var _tool: VoxelTool
## Write funnel owned by CityRoot — the cabinet shell is stamped through it.
var _brush: CityBrush
## World voxel cells that belong to this cabinet shell.
var _owned_voxels: Dictionary = {}  # Vector3i → true

## Bottom-left cell center of the playfield (local).
var _pf_origin: Vector3 = Vector3.ZERO
## Center Z of pieces inside the well.
var _piece_z: float = 0.0
## When false, keys 1–4 are ignored (NPC / AI owns the cabinet, or the cabinet is off).
var _input_enabled: bool = true
var _ai_controller: Node = null
## Owner of the canonical "some panel owns the screen" test.
var _walker: CityWalker
## Powered cabinets fall and take keys; an off cabinet freezes in place until toggled on.
var _powered: bool = true
## The arcade's free cabinet shows ON/NEW; ped-owned bays and the T-key summon hide them.
var _show_controls: bool = false
var _controls: Ui3D = null


func begin(
	terrain: VoxelTerrain,
	tool: VoxelTool,
	brush: CityBrush,
	walker: CityWalker,
	ground_hit: Vector3,
	face_yaw: float,
	cell_size: float = CELL
) -> void:
	if terrain == null or tool == null or brush == null or walker == null:
		push_error("TetrisMachine.begin: terrain/tool/brush/walker required")
		return
	_terrain = terrain
	_tool = tool
	_brush = brush
	_walker = walker
	_cell_size = maxf(cell_size, 0.1)
	_rng.randomize()
	_init_shapes()
	_init_materials()
	global_position = Vector3(ground_hit.x, ground_hit.y, ground_hit.z)
	rotation.y = face_yaw
	_stamp_voxel_shell()
	_build_piece_visuals()
	_build_labels()
	_build_controls()
	_board.resize(COLS * ROWS)
	_board.fill(0)
	_reset_bag()
	_powered = true
	_spawn_piece()
	_refresh_board_visual()
	_refresh_active_visual()
	_refresh_hud()
	_refresh_controls()
	set_process_unhandled_input(true)
	set_process(true)
	set_physics_process(true)


## Arcade policy for one bay. Ped bays stay on with no plate; the free bay starts off and
## shows ON / NEW so a player can claim it without keys fighting an NPC.
func configure_arcade(player_operable: bool) -> void:
	_show_controls = player_operable
	if player_operable:
		set_powered(false)
	else:
		set_powered(true)
	_refresh_controls()


func is_powered() -> bool:
	return _powered


func set_powered(on: bool) -> void:
	if _broken:
		return
	if _powered == on:
		_refresh_controls()
		return
	_powered = on
	if not on:
		## Freeze mid-game rather than wiping it: a toggle is a power switch, not NEW.
		set_input_enabled(false)
		_soft_dropping = false
		_das_dir = 0
		_das_repeating = false
		_locking = false
		_lock_accum = 0.0
	elif _active_id == 0 and not _game_over and not _clearing:
		_spawn_piece()
	_refresh_active_visual()
	_refresh_hud()
	_refresh_controls()


## Wipe score and board and, if the cabinet is on, drop a fresh piece. Broken shells stay
## broken — NEW is not a repair kit.
func new_game() -> void:
	if _broken:
		push_error("TetrisMachine.new_game: cabinet is destroyed")
		return
	if has_ai_controller():
		push_error("TetrisMachine.new_game: an NPC owns this board")
		return
	_score = 0
	_lines = 0
	_level = 1
	_game_over = false
	_clearing = false
	_clear_timer = 0.0
	_clear_rows.clear()
	_active_id = 0
	_soft_dropping = false
	_locking = false
	_lock_accum = 0.0
	_lock_resets = 0
	_fall_t = 0.0
	_das_dir = 0
	_das_repeating = false
	_board.fill(0)
	_reset_bag()
	if _game_over_label != null:
		_game_over_label.visible = false
	_refresh_board_visual()
	if _powered:
		_spawn_piece()
	else:
		_refresh_active_visual()
	_refresh_hud()
	_refresh_controls()


func _ready() -> void:
	## Idle until begin() hands over the world to stamp into and the walker whose open panels
	## decide whether the cabinet keys count.
	set_process_unhandled_input(false)
	set_process(false)
	set_physics_process(false)


func is_playable() -> bool:
	return (
		_powered
		and not _broken
		and not _game_over
		and not _clearing
		and _active_id > 0
	)


func is_broken() -> bool:
	return _broken


func is_game_over() -> bool:
	return _game_over


func is_soft_dropping() -> bool:
	return _soft_dropping


## Idempotent on purpose: the proximity gate that picks which cabinet in a row hears keys
## 1–4 calls this every frame, and clearing DAS on every one of those calls would kill
## auto-repeat while a key is held. An off cabinet stays deaf even when the gate asks
## otherwise — power is the stronger rule.
func set_input_enabled(enabled: bool) -> void:
	if enabled and (not _powered or _broken):
		enabled = false
	if _input_enabled == enabled:
		return
	_input_enabled = enabled
	_das_dir = 0
	_das_repeating = false


func is_input_enabled() -> bool:
	return _input_enabled


## True while an NPC or AI owns the board, in which case the player-proximity gate must
## leave its input alone.
func has_ai_controller() -> bool:
	return _ai_controller != null and is_instance_valid(_ai_controller)


func claim_ai_controller(controller: Node) -> bool:
	if _broken or not _powered:
		return false
	if _ai_controller != null and is_instance_valid(_ai_controller) and _ai_controller != controller:
		return false
	_ai_controller = controller
	set_input_enabled(false)
	return true


func release_ai_controller(controller: Node) -> void:
	if _ai_controller == controller:
		_ai_controller = null
		if not _broken and not _game_over and _powered:
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


## Local-space centre of a board cell — used by well-alignment tests.
func cell_local_center(col: int, row: int) -> Vector3:
	return _cell_world_local(float(col), float(row))


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
	_piece_z = depth * 0.5
	## Provisional origin — replaced after stamp so MultiMesh cells track the floored rails.
	_pf_origin = Vector3(x0 + cs * 0.5, y0 + cs * 0.5, _piece_z)

	_owned_voxels.clear()
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	## Whole cabinet is one logical edit — subscribers get a single dirty region.
	_brush.begin_edit()

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
	_brush.end_edit()
	_align_playfield_to_rails(x0, well_w, y0, cs)

	_title = Label3D.new()
	_title.name = "Title"
	_title.text = "TETRIS"
	_title.font_size = 160
	_title.modulate = Color(0.15, 0.22, 0.12)
	_title.outline_size = 24
	_title.outline_modulate = Color(0.75, 0.88, 0.55, 1.0)
	## Sit proud of the voxel header face (local -Z = toward the player).
	_title.position = Vector3(0.0, FRAME_H - 0.9, -0.55)
	_title.rotation.y = PI
	_configure_cabinet_label(_title, 10)
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
	var vox := _local_to_vox(local_pos)
	if vox.y < 1:
		vox.y = 1
	var existing := int(_tool.get_voxel(vox))
	if existing == VoxelMaterial.BEDROCK or existing == VoxelMaterial.WATER:
		return
	_brush.set_vox(vox, VoxelMaterial.GAMEBOY)
	_owned_voxels[vox] = true


func _local_to_vox(local_pos: Vector3) -> Vector3i:
	var world := to_global(local_pos)
	var local_t := _terrain.to_local(world)
	return Vector3i(
		int(floor(local_t.x)),
		int(floor(local_t.y)),
		int(floor(local_t.z))
	)


func _vox_center_to_local(vox: Vector3i) -> Vector3:
	var terrain_local := Vector3(
		float(vox.x) + 0.5, float(vox.y) + 0.5, float(vox.z) + 0.5
	)
	return to_local(_terrain.to_global(terrain_local))


## Arcade cabinets stand on voxel centres; `floor` then parks the GAMEBOY side rails one
## cell off the continuous well, so locked pieces look shifted inside the harness. Seat
## `_pf_origin` on the lattice the rails actually occupied.
func _align_playfield_to_rails(x0: float, well_w: float, y0: float, cs: float) -> void:
	if _terrain == null:
		return
	var left_c := _vox_center_to_local(
		_local_to_vox(Vector3(x0 - cs * 0.5, y0 + cs * 0.5, _piece_z))
	)
	var right_c := _vox_center_to_local(
		_local_to_vox(Vector3(x0 + well_w + cs * 0.5, y0 + cs * 0.5, _piece_z))
	)
	var bottom_c := _vox_center_to_local(
		_local_to_vox(Vector3(0.0, y0 - cs * 0.5, _piece_z))
	)
	var x_left := left_c.x
	var x_right := right_c.x
	if x_right < x_left:
		var tmp := x_left
		x_left = x_right
		x_right = tmp
	var expected := float(COLS - 1) * cs
	var actual := x_right - x_left - 2.0 * cs
	if absf(actual - expected) > cs * 0.51:
		push_error(
			"TetrisMachine: stamped well span %.3fm (want %.3fm) — leaving provisional origin"
			% [actual, expected]
		)
		return
	_pf_origin = Vector3(x_left + cs, bottom_c.y + cs, _piece_z)


func clear_shell() -> void:
	## Remove remaining cabinet voxels (replace / regenerate). Leaves debris alone.
	if _tool == null or _owned_voxels.is_empty():
		_owned_voxels.clear()
		return
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	_brush.begin_edit()
	for key in _owned_voxels.keys():
		var vox: Vector3i = key
		if int(_tool.get_voxel(vox)) == VoxelMaterial.GAMEBOY:
			_brush.set_vox(vox, VoxelMaterial.AIR)
	_brush.end_edit()
	_owned_voxels.clear()


func notify_voxels_carved(vox_entries: Array) -> void:
	if _broken or _owned_voxels.is_empty():
		return
	for item in vox_entries:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var entry := item as Dictionary
		var vox: Vector3i = entry.get("vox", Vector3i(2147483647, 2147483647, 2147483647))
		var mat_id := int(entry.get("mat", -1))
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
	_powered = false
	_game_over = true
	_active_id = 0
	_soft_dropping = false
	_locking = false
	_clearing = false
	_das_dir = 0
	_refresh_active_visual()
	## Labels / HUD are Node3D props — hide them so they don't float after the shell is gone.
	_hide_overlay_labels()
	_refresh_controls()
	for mmi in _board_mms:
		if mmi != null:
			mmi.visible = false


func _hide_overlay_labels() -> void:
	if _title != null:
		_title.visible = false
	if _hud != null:
		_hud.visible = false
	if _hints != null:
		_hints.visible = false
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
	## Front of pedestal — identical anchor on free and ped cabinets so SCORE/LINES line up.
	_hud.position = Vector3(0.0, HUD_Y_M, HUD_Z_M)
	_hud.rotation.y = PI
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hud.outline_size = 18
	_hud.outline_modulate = Color(0.02, 0.06, 0.02, 0.95)
	_configure_cabinet_label(_hud, 10)
	add_child(_hud)

	_hints = Label3D.new()
	_hints.name = "ControlHints"
	_hints.text = HINTS_TEXT
	_hints.font_size = 72
	_hints.modulate = HINTS_COLOUR
	## Free line above SCORE (not on top of it — the centred two-line HUD already owns that).
	_hints.position = Vector3(0.0, HINTS_Y_M, HUD_Z_M)
	_hints.rotation.y = PI
	_hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hints.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hints.outline_size = 18
	_hints.outline_modulate = Color(0.08, 0.05, 0.01, 0.95)
	_configure_cabinet_label(_hints, 10)
	_hints.visible = false
	add_child(_hints)

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
	_configure_cabinet_label(_game_over_label, 11)
	_game_over_label.visible = false
	add_child(_game_over_label)


## Pedestal plate facing the stand. Built once; `configure_arcade` decides whether it is live.
func _build_controls() -> void:
	if _controls != null:
		return
	var panel: Ui3D = Ui3DScript.new() as Ui3D
	panel.name = "ArcadeControls"
	panel.size_m = Vector2(CONTROLS_W_M, CONTROLS_H_M)
	panel.surface_color = Color(0.10, 0.11, 0.13, 0.94)
	panel.show_debug_marker = false
	add_child(panel)
	## Child of the cabinet: `begin` writes local yaw, and the parent already carries
	## `face_yaw`. Passing that again stacked a second turn and stood the plate edge-on.
	## Local 0 keeps Ui3D's −Z on the cabinet's −Z (the stand). Do *not* copy the score
	## label's π flip — Label3D faces +Z, Ui3D faces −Z, so the same flip would point the
	## plate into the shell. Same row as LINES, left of the well.
	var at := to_global(Vector3(CONTROLS_X_M, CONTROLS_Y_M, CONTROLS_Z_M))
	panel.begin(at, 0.0)
	if not panel.button_pressed.is_connected(_on_controls_button):
		panel.button_pressed.connect(_on_controls_button)
	_controls = panel
	_refresh_controls()


func _refresh_controls() -> void:
	var live := _show_controls and not _broken
	if _hints != null:
		_hints.visible = live
	if _controls == null:
		return
	_controls.set_hit_enabled(live)
	if not live:
		_controls.clear_buttons()
		return
	_controls.clear_buttons()
	## Label is the action, not the state: an off cabinet offers ON, an on one offers OFF.
	var power_label := "OFF" if _powered else "ON"
	var power_col := (
		Color(0.45, 0.22, 0.18) if _powered else Color(0.18, 0.42, 0.24)
	)
	_controls.add_button(
		BTN_POWER, Rect2(0.04, 0.12, 0.44, 0.76), power_label, power_col, true
	)
	var new_col := Color(0.22, 0.28, 0.42) if _powered else Color(0.16, 0.18, 0.22)
	_controls.add_button(BTN_NEW, Rect2(0.52, 0.12, 0.44, 0.76), "NEW", new_col, true)
	_controls.rebuild_buttons()


func _on_controls_button(button_id: StringName, _uv: Vector2) -> void:
	if _broken or not _show_controls:
		return
	if has_ai_controller():
		return
	if UiInputGate.gameplay_blocked(_walker):
		return
	match button_id:
		BTN_POWER:
			set_powered(not _powered)
		BTN_NEW:
			new_game()
		_:
			push_error("TetrisMachine: unknown control '%s'" % String(button_id))


## Depth-tested labels: no_depth_test made score/title paint over the player whenever
## you stood in front of the cabinet. Opaque prepass still keeps glyphs readable against
## the voxel shell without sorting them as translucent overlays.
func _configure_cabinet_label(label: Label3D, priority: int) -> void:
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = true
	label.no_depth_test = false
	label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	label.render_priority = priority


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
	if not _powered:
		_das_dir = 0
		_das_repeating = false
		return
	if UiInputGate.gameplay_blocked(_walker):
		## A panel that opens mid-hold swallows the key release below it, so the latched
		## repeat has to be dropped here or the piece keeps sliding behind the modal.
		_das_dir = 0
		_das_repeating = false
		return
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
	## Off means frozen: the well keeps whatever was on it, but nothing falls.
	if not _powered:
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
	if _broken or not _powered or _game_over or not _input_enabled:
		return
	## A modal owns the screen while it is up, so a cabinet key must not reach the board behind
	## it. Same gate the walker and the build bar put on their own hotkeys.
	if UiInputGate.gameplay_blocked(_walker):
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
	## An off cabinet hides the falling piece so the well reads as dormant rather than paused
	## mid-drop. Locked blocks stay — they are the machine's last game, not its current one.
	if not _powered or _active_id <= 0:
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
	## Two lines on every live cabinet. Free-bay ON/NEW buttons carry power/restart state, so
	## do not append a third status line there — that is what shoved SCORE up into the hints.
	_hud.text = "SCORE %d\nLINES %d  LV %d" % [_score, _lines, _level]
	if _broken:
		_hud.text += "\nCABINET DESTROYED"
	elif not _show_controls and not _powered:
		_hud.text += "\nOFF"
	elif not _show_controls and _game_over:
		_hud.text += "\nNEW TO RESTART"
