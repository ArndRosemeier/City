## Photographs the Go end-game billboard without playing a match.
##
## Needs a renderer: Ui3D / Label3D never draw headless.
##
## Run: powershell -File tools\run_test.ps1 shot_go_end_panel -Rendered
extends Node

const OUT_RESIGN := "res://tools/go_end_panel_resign.png"
const OUT_SCORE := "res://tools/go_end_panel_score.png"


func _ready() -> void:
	var root := Node3D.new()
	root.name = "Stage"
	add_child(root)
	_build_environment(root)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true

	var panel := GoEndPanel.new()
	root.add_child(panel)
	## Ui3D faces local −Z; yaw 0 → world −Z (same as the arena billboard).
	panel.setup(Vector3(0.0, GoEndPanel.PANEL_H_M * 0.5, 0.0), 0.0)

	## Stand in front of the face (along −basis.z), looking at the panel.
	## 20 m wide at ~18 m needs a wide FOV so captions aren't cropped.
	var face := -panel.global_transform.basis.z
	cam.global_position = panel.global_position + face * 18.0
	cam.look_at(panel.global_position, Vector3.UP)
	cam.fov = 75.0

	var resign := _fake_resign_result()
	panel.show_result(resign)
	await _frames(6)
	if not _shoot(OUT_RESIGN):
		get_tree().quit(1)
		return
	print("  resign → %s (%s)" % [OUT_RESIGN, resign.headline()])

	var scored := _fake_score_result()
	panel.show_result(scored)
	await _frames(6)
	if not _shoot(OUT_SCORE):
		get_tree().quit(1)
		return
	print("  score → %s (%s / %s)" % [OUT_SCORE, scored.headline(), scored.score_line()])

	print("RESULT: OK")
	get_tree().quit(0)


func _fake_resign_result() -> GoMatchResult:
	var board := GoBoardState.new()
	board.setup(9)
	## A few stones so the area totals are non-trivial under the resign banner.
	assert(board.try_play_xy(GoBoardState.BLACK, 2, 2))
	assert(board.try_play_xy(GoBoardState.WHITE, 6, 6))
	assert(board.try_play_xy(GoBoardState.BLACK, 2, 3))
	assert(board.try_play(GoBoardState.WHITE, "resign"))
	return GoMatchResult.from_board(board, board.end_reason, 6.5)


func _fake_score_result() -> GoMatchResult:
	var board := GoBoardState.new()
	board.setup(5)
	## Black surrounds the SW; White the NE — two_passes territory / area score.
	assert(board.try_play_xy(GoBoardState.BLACK, 0, 0))
	assert(board.try_play_xy(GoBoardState.WHITE, 4, 4))
	assert(board.try_play_xy(GoBoardState.BLACK, 1, 0))
	assert(board.try_play_xy(GoBoardState.WHITE, 3, 4))
	assert(board.try_play_xy(GoBoardState.BLACK, 0, 1))
	assert(board.try_play_xy(GoBoardState.WHITE, 4, 3))
	assert(board.try_play(GoBoardState.BLACK, "pass"))
	assert(board.try_play(GoBoardState.WHITE, "pass"))
	return GoMatchResult.from_board(board, board.end_reason, 6.5)


func _build_environment(root: Node3D) -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.1, 0.12, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.92, 1.0)
	env.ambient_light_energy = 1.1
	world_env.environment = env
	root.add_child(world_env)
	## Soft ground so the 20×10 billboard has a horizon.
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	floor_mi.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.2, 0.28, 0.18, 1.0)
	floor_mi.material_override = mat
	floor_mi.position.y = 0.0
	root.add_child(floor_mi)


func _shoot(path: String) -> bool:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
		return false
	var err := img.save_png(path)
	if err != OK:
		push_error("FAIL save_png %s → %s" % [path, error_string(err)])
		return false
	return true


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame
