## Photographs the move arrow — the dart of light thrown from a player's hand at the
## crossing their stone is about to take — without waiting for a match.
##
## Also exercises the handover: the table's `move_herald` has to hold the stone back for
## exactly as long as the dart is in the air, so the stone lands under the strike.
##
## Needs a renderer: the dart is additive geometry and never draws headless.
##
## Run: powershell -File tools\run_test.ps1 shot_go_move_arrow -Rendered
extends Node

const GoTableUi3DScript := preload("res://scripts/city/go_table_ui.gd")
const GoMoveArrowScript := preload("res://scripts/city/go_move_arrow.gd")

const OUT_PAIR := "res://tools/go_move_arrow_pair.png"
const OUT_INBOUND := "res://tools/go_move_arrow_inbound.png"
const OUT_LANDED := "res://tools/go_move_arrow_landed.png"

const BOARD_N := 19
const TABLE_W_M := 3.0
const TABLE_TOP_Y := 0.9
## Where the two players' hands hover: Black south-west of the table, White north-east.
const BLACK_HAND := Vector3(-2.1, TABLE_TOP_Y + 0.35, -1.9)
const WHITE_HAND := Vector3(2.0, TABLE_TOP_Y + 0.4, 1.8)

var _root: Node3D = null
var _cam: Camera3D = null
var _table: GoTableUi3D = null
var _board: GoBoardState = null
var _arrow: GoMoveArrow = null
var _flight_sec: float = 0.0


func _ready() -> void:
	_root = Node3D.new()
	_root.name = "Stage"
	add_child(_root)
	_build_environment()
	_cam = Camera3D.new()
	_root.add_child(_cam)
	_cam.current = true

	_board = GoBoardState.new()
	_board.setup(BOARD_N)
	_play_opening()
	_table = GoTableUi3DScript.new() as GoTableUi3D
	_table.name = "Table"
	_root.add_child(_table)
	_table.setup_board(_board, Vector3(0.0, TABLE_TOP_Y, 0.0), 0.0, TABLE_W_M)

	_arrow = _spawn_arrow("Arrow")
	await _frames(1)

	if not await _shoot_pair():
		get_tree().quit(1)
		return
	if not await _shoot_live_move():
		get_tree().quit(1)
		return

	print("RESULT: OK")
	get_tree().quit(0)


## Both colours frozen on their arcs. A live tween is a third of a second long and cannot
## be caught on a chosen frame, so the darts are posed instead.
func _shoot_pair() -> bool:
	_aim_camera(false)
	var second := _spawn_arrow("ArrowSecond")
	_arrow.preview_at(BLACK_HAND, _table.crossing_world(4, 13), true, 0.55)
	second.preview_at(WHITE_HAND, _table.crossing_world(14, 5), false, 0.78)
	await _frames(4)

	var ok := _grab(OUT_PAIR)
	second.cancel()
	second.queue_free()
	_arrow.cancel()
	await _frames(1)
	return ok


## The real handover: play a move on the board and check the table withholds the stone for
## the flight, then paints it as the dart strikes.
func _shoot_live_move() -> bool:
	_aim_camera(true)
	var stones := _table.get_node("Stones") as Node3D
	if stones == null:
		push_error("FAIL the table has no Stones root")
		return false
	var before := stones.get_child_count()

	_table.move_herald = _herald
	var loc := Vector2i(9, 9)
	var vertex := GoBoardState.format_vertex(loc.x, loc.y, BOARD_N)
	var color := _board.next_color
	if not _board.try_play(color, vertex):
		push_error("FAIL the board rejected %s" % vertex)
		return false
	if _flight_sec <= 0.0:
		push_error("FAIL move_herald never launched a dart")
		return false

	## Four fifths in: the dart is diving at its crossing and the crossing is still bare.
	await _seconds(_flight_sec * 0.8)
	if stones.get_child_count() != before:
		push_error(
			"FAIL the stone appeared while the dart was still in the air (%d → %d)"
			% [before, stones.get_child_count()]
		)
		return false
	if not _grab(OUT_INBOUND):
		return false

	## Just past impact: the flash is still bright and the stone is down.
	await _seconds(_flight_sec * 0.2 + 0.07)
	var ok := _grab(OUT_LANDED)
	await _frames(1)
	if stones.get_child_count() <= before:
		push_error("FAIL the stone never landed after the dart struck")
		return false
	print("  flight %.2f s, stones %d → %d" % [_flight_sec, before, stones.get_child_count()])
	return ok


func _herald(color: int, world_target: Vector3) -> float:
	var hand := BLACK_HAND if color == GoBoardState.BLACK else WHITE_HAND
	_flight_sec = _arrow.fly(hand, world_target, color == GoBoardState.BLACK)
	return _flight_sec


func _aim_camera(closeup: bool) -> void:
	if closeup:
		## Across the flight rather than along it: the dive only reads in profile.
		_cam.fov = 46.0
		_cam.global_position = Vector3(2.9, TABLE_TOP_Y + 1.5, -2.2)
		_cam.look_at(Vector3(-0.3, TABLE_TOP_Y + 0.25, 0.0), Vector3.UP)
		return
	## Standing south of the table: both arcs cross the frame side on.
	_cam.fov = 60.0
	_cam.global_position = Vector3(0.0, TABLE_TOP_Y + 2.1, -3.7)
	_cam.look_at(Vector3(0.0, TABLE_TOP_Y + 0.45, 0.1), Vector3.UP)


func _spawn_arrow(node_name: String) -> GoMoveArrow:
	var arrow: GoMoveArrow = GoMoveArrowScript.new() as GoMoveArrow
	arrow.name = node_name
	_root.add_child(arrow)
	return arrow


## A handful of stones so the dart is read against a real position, not an empty grid.
func _play_opening() -> void:
	var far := BOARD_N - 4
	var moves: Array[Vector2i] = [
		Vector2i(3, 3),
		Vector2i(far, far),
		Vector2i(far, 3),
		Vector2i(3, far),
		Vector2i(9, 3),
		Vector2i(9, far),
	]
	for m in moves:
		var vertex := GoBoardState.format_vertex(m.x, m.y, BOARD_N)
		if not _board.try_play(_board.next_color, vertex):
			push_error("shot_go_move_arrow: opening move %s rejected" % vertex)


func _grab(path: String) -> bool:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
		return false
	var err := img.save_png(path)
	if err != OK:
		push_error("FAIL save_png %s → %s" % [path, error_string(err)])
		return false
	print("  wrote %s" % path)
	return true


func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.08, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.95, 1.0)
	## Dim, the way the district reads at night, so the additive dart carries the frame.
	env.ambient_light_energy = 0.7
	env.glow_enabled = true
	env.glow_intensity = 0.9
	world_env.environment = env
	_root.add_child(world_env)

	var top := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(6.0, 0.3, 4.0)
	top.mesh = slab
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.22, 0.13, 1.0)
	top.material_override = mat
	top.position = Vector3(0.0, TABLE_TOP_Y - 0.16, 0.0)
	_root.add_child(top)


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _seconds(t: float) -> void:
	await get_tree().create_timer(t).timeout
