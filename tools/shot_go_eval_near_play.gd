## Photographs the near-play KataGo eval overlay without running a match: the winrate /
## score-lead strips on the settings panel and the candidate discs on the table board.
##
## The snapshot is built from the same JSON shape katago_genmove_eval emits, so this also
## checks GoEvalSnapshot.from_engine_json against the native contract.
##
## Needs a renderer: Ui3D quads and Label3D never draw headless.
##
## Run: powershell -File tools\run_test.ps1 shot_go_eval_near_play -Rendered
extends Node

const GoTableUi3DScript := preload("res://scripts/city/go_table_ui.gd")
const GoSettingsUi3DScript := preload("res://scripts/city/go_settings_ui.gd")
const GoEvalSnapshotScript := preload("res://scripts/city/go_eval_snapshot.gd")

const OUT_19 := "res://tools/go_eval_near_play_19.png"
const OUT_9 := "res://tools/go_eval_near_play_9.png"
const OUT_CLOSEUP := "res://tools/go_eval_board_closeup.png"

const TABLE_W_M := 3.0
const SETTINGS_W_M := 1.9
const TABLE_TOP_Y := 0.9
## Root visits KataGo spends per Human-SL move.
const MOCK_VISITS := 40

var _root: Node3D = null
var _cam: Camera3D = null


func _ready() -> void:
	_root = Node3D.new()
	_root.name = "Stage"
	add_child(_root)
	_build_environment()
	_cam = Camera3D.new()
	_root.add_child(_cam)
	_cam.current = true

	if not await _shoot_case(19, OUT_19, false):
		get_tree().quit(1)
		return
	if not await _shoot_case(9, OUT_9, false):
		get_tree().quit(1)
		return
	## Same overlay from overhead: the view that proves the discs sit on their crossings.
	if not await _shoot_case(19, OUT_CLOSEUP, true):
		get_tree().quit(1)
		return

	print("RESULT: OK")
	get_tree().quit(0)


func _aim_camera(closeup: bool) -> void:
	if closeup:
		_cam.fov = 46.0
		_cam.global_position = Vector3(-1.7, TABLE_TOP_Y + 2.9, -1.4)
		_cam.look_at(Vector3(-1.7, TABLE_TOP_Y, 0.0), Vector3.UP)
		return
	## Seated south of the table, looking north and down across both panels.
	_cam.fov = 58.0
	_cam.global_position = Vector3(0.0, TABLE_TOP_Y + 2.6, -2.9)
	_cam.look_at(Vector3(0.0, TABLE_TOP_Y, 0.1), Vector3.UP)


func _shoot_case(n: int, path: String, closeup: bool) -> bool:
	var board := GoBoardState.new()
	board.setup(n)
	_play_opening(board, n)

	var table: GoTableUi3D = GoTableUi3DScript.new() as GoTableUi3D
	table.name = "TableCase%d" % n
	_root.add_child(table)
	table.setup_board(board, Vector3(-1.7, TABLE_TOP_Y, 0.0), 0.0, TABLE_W_M)

	var settings: Node = GoSettingsUi3DScript.new()
	settings.name = "SettingsCase%d" % n
	_root.add_child(settings)
	settings.call("setup", Vector3(1.85, TABLE_TOP_Y, 0.0), 0.0, SETTINGS_W_M)
	settings.set("board_n", n)
	settings.set("black_human", true)
	settings.set("white_human", false)
	settings.set("white_rank", "3k")
	settings.call("show_match")

	var snap: GoEvalSnapshot = _mock_snapshot(board, n)
	if snap == null:
		push_error("FAIL GoEvalSnapshot.from_engine_json rejected the mock payload")
		return false
	if snap.candidates.is_empty():
		push_error("FAIL mock snapshot parsed with no candidates")
		return false
	if snap.chosen_loc.x < 0:
		push_error("FAIL mock snapshot lost its chosen vertex '%s'" % snap.chosen_vertex)
		return false
	settings.call("set_eval", snap)
	table.set_eval(snap)
	for cand in snap.candidates:
		print(
			"    candidate %-5s loc %s  visits %2d  order %d"
			% [cand.vertex, str(cand.loc), cand.visits, cand.order]
		)

	_aim_camera(closeup)
	await _frames(6)
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
		return false
	var err := img.save_png(path)
	if err != OK:
		push_error("FAIL save_png %s → %s" % [path, error_string(err)])
		return false
	print(
		"  %dx%d → %s (%s / %s, %d candidates)"
		% [n, n, path, snap.winrate_line(), snap.lead_line(), snap.candidates.size()]
	)
	table.queue_free()
	settings.queue_free()
	await _frames(1)
	return true


## A handful of stones so the discs are read against a real position, not an empty grid.
func _play_opening(board: GoBoardState, n: int) -> void:
	var far := n - 3
	var moves: Array[Vector2i] = [
		Vector2i(2, 2),
		Vector2i(far, far),
		Vector2i(far, 2),
		Vector2i(2, far),
	]
	for m in moves:
		var vertex := GoBoardState.format_vertex(m.x, m.y, n)
		if not board.try_play(board.next_color, vertex):
			push_error("shot_go_eval_near_play: opening move %s rejected on %d" % [vertex, n])


## Mirrors the JSON katago_genmove_eval writes, including Black-perspective values.
func _mock_snapshot(board: GoBoardState, n: int) -> GoEvalSnapshot:
	var mid := n / 2
	var chosen := Vector2i(mid, mid)
	var alts: Array[Vector2i] = [
		Vector2i(mid, 1),
		Vector2i(1, mid),
		Vector2i(mid + 1, mid - 2),
		Vector2i(mid - 2, mid + 1),
	]
	var chosen_vertex := GoBoardState.format_vertex(chosen.x, chosen.y, n)
	var parts: Array[String] = []
	parts.append(_candidate_json(chosen_vertex, 17, 0.548, 2.4, 0))
	var visits: Array[int] = [9, 6, 4, 2]
	var order := 1
	for i in range(alts.size()):
		var a: Vector2i = alts[i]
		if a.x < 0 or a.y < 0 or a.x >= n or a.y >= n:
			continue
		parts.append(
			_candidate_json(
				GoBoardState.format_vertex(a.x, a.y, n),
				visits[i],
				0.53 - 0.02 * float(i),
				1.9 - 0.7 * float(i),
				order
			)
		)
		order += 1
	var json := (
		'{"winrate_black":0.5432,"lead_black":2.30,"visits":%d,"candidates":[%s]}'
		% [MOCK_VISITS, ",".join(parts)]
	)
	## The board is only here to keep the mock honest about which move was played.
	board.try_play(board.next_color, chosen_vertex)
	return GoEvalSnapshotScript.from_engine_json(
		json, GoBoardState.WHITE, chosen_vertex, n
	)


func _candidate_json(
	vertex: String, visits: int, winrate_black: float, lead_black: float, order: int
) -> String:
	return (
		'{"vertex":"%s","visits":%d,"winrate_black":%.4f,"lead_black":%.2f,"order":%d}'
		% [vertex, visits, winrate_black, lead_black, order]
	)


func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.09, 0.11, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.92, 0.95, 1.0)
	env.ambient_light_energy = 1.15
	world_env.environment = env
	_root.add_child(world_env)
	## Timber slab under both panels, so they read as one table top.
	var top := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(9.0, 0.3, 5.0)
	top.mesh = slab
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.32, 0.22, 0.13, 1.0)
	top.material_override = mat
	top.position = Vector3(0.0, TABLE_TOP_Y - 0.16, 0.0)
	_root.add_child(top)


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame
