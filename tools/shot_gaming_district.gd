## Gaming district look inspection: giant Go board aerial, board corner, table.
##
## Run: powershell -File tools\run_test.ps1 shot_gaming_district -Rendered -GodotArgs "--spawn-theme=gaming"
extends Node

const AERIAL_PNG := "res://tools/gaming_aerial.png"
const BOARD_PNG := "res://tools/gaming_board.png"
const TABLE_PNG := "res://tools/gaming_table.png"
const PANEL_PNG := "res://tools/gaming_panel.png"
const DUAL_PNG := "res://tools/gaming_dual.png"
const VS := 0.5


func _ready() -> void:
	var city := CityRoot.new()
	city.city_seed = 42
	add_child(city)

	var deadline := Time.get_ticks_msec() + 120_000
	while city.get_node_or_null("Walker") == null:
		if Time.get_ticks_msec() > deadline:
			push_error("FAIL no walker after 120 s")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var walker: Node3D = city.get_node_or_null("Walker")

	var theme := DistrictTheme.for_district(city.city_seed, city.spawn_district_coord)
	print("spawn district %s = %s" % [city.spawn_district_coord, theme.display_name])
	if theme.id != DistrictTheme.GAMING:
		push_error("FAIL spawn district is %s, expected Gaming" % theme.display_name)
		get_tree().quit(1)
		return

	await _settle(10.0)
	var inst := _spawn_district(city)
	if inst == null:
		push_error("FAIL spawn district instance not loaded")
		get_tree().quit(1)
		return
	var layout: GamingLayout = inst.generator.get_gaming_layout()
	if layout == null:
		push_error("FAIL no gaming layout on the loaded district")
		get_tree().quit(1)
		return
	print("layout: %s" % layout.describe())

	_paint_demo_position(inst, layout.board_n)

	var origin := inst.origin_vox
	var span := layout.giant_span_vox()
	var board_mid := _world(
		origin, layout.giant_origin + Vector3i(span / 2, 0, span / 2)
	)
	var board_sw := _world(origin, layout.giant_origin)

	## Straight-down-ish aerial: the only angle where a 19x19 board reads as a board.
	walker.global_position = board_mid + Vector3(0.0, 40.0, 0.0)
	await _settle(14.0)
	await _shoot(board_mid + Vector3(0.0, 44.0, 26.0), board_mid, AERIAL_PNG)

	## Eye level at the south-west corner: does the grid read from the plaza?
	var eye := board_sw + Vector3(-6.0, 2.0, -6.0)
	walker.global_position = eye
	await _settle(10.0)
	await _shoot(eye + Vector3(0.0, 1.6, 0.0), board_mid, BOARD_PNG)

	var table := _world(
		origin,
		layout.main_table_origin
		+ Vector3i(GamingComposer.TABLE_W / 2, GamingComposer.TABLE_H, GamingComposer.TABLE_D / 2)
	)
	walker.global_position = table + Vector3(0.0, 6.0, -7.0)
	await _settle(10.0)
	await _shoot(table + Vector3(0.0, 5.0, -6.0), table, TABLE_PNG)

	## Settings panel from the seat: the only test of whether the chrome is legible.
	var panel := _world(
		origin,
		layout.main_table_origin
		+ Vector3i(
			int(round(float(GamingComposer.TABLE_W) * GamingComposer.SETTINGS_X_FRAC)),
			GamingComposer.TABLE_H,
			GamingComposer.TABLE_D / 2
		)
	)
	walker.global_position = panel + Vector3(0.0, 3.0, -4.0)
	await _settle(8.0)
	await _shoot(panel + Vector3(0.0, 1.9, -1.9), panel, PANEL_PNG)

	## Table board plus the giant board behind it: the check that both agree on which
	## side of the board a stone is on.
	var seat := _world(
		origin,
		layout.main_table_origin
		+ Vector3i(
			int(round(float(GamingComposer.TABLE_W) * GamingComposer.BOARD_X_FRAC)),
			GamingComposer.TABLE_H,
			GamingComposer.TABLE_D / 2
		)
	)
	walker.global_position = seat + Vector3(0.0, 4.0, -5.0)
	await _settle(8.0)
	await _shoot(seat + Vector3(0.0, 2.6, -2.6), seat, DUAL_PNG)

	print("RESULT: OK")
	get_tree().quit(0)


## A corner joseki plus a few loose stones — enough shapes to judge how the giant
## stones read against the grid.
func _paint_demo_position(inst: DistrictInstance, n: int) -> void:
	var arena := inst.gaming_arena
	if arena == null:
		push_error("FAIL no gaming arena on the loaded district")
		get_tree().quit(1)
		return
	var giant := arena.giant_board()
	if giant == null:
		push_error("FAIL gaming arena has no giant board")
		get_tree().quit(1)
		return
	var board := GoBoardState.new()
	board.setup(n)
	var moves: Array[String] = [
		"Q16", "D4", "Q4", "D16", "R6", "C6", "P3", "F3",
		"K10", "K4", "K16", "H17", "R14", "C11", "O17", "Q17",
	]
	for i in range(moves.size()):
		var color := GoBoardState.BLACK if i % 2 == 0 else GoBoardState.WHITE
		if not board.try_play(color, moves[i]):
			push_error("FAIL demo move %s rejected" % moves[i])
			get_tree().quit(1)
			return
	giant.paint_snapshot(board)
	## Same position on the table panel, so the two views can be compared side by side.
	var table_ui := arena.get_node_or_null("MainGoTable") as GoTableUi3D
	if table_ui == null:
		push_error("FAIL gaming arena has no MainGoTable")
		get_tree().quit(1)
		return
	table_ui.board = board
	table_ui._rebuild_stones()
	print("demo position: %d stones" % moves.size())


func _world(origin_vox: Vector3i, local: Vector3i) -> Vector3:
	return Vector3(
		float(origin_vox.x + local.x) * VS,
		float(origin_vox.y + local.y) * VS,
		float(origin_vox.z + local.z) * VS
	)


func _spawn_district(city: CityRoot) -> DistrictInstance:
	var want := city.spawn_district_coord
	var districts: Array = city._streamer.call("get_loaded_districts") as Array
	for entry: Variant in districts:
		var di: DistrictInstance = entry
		if di.coord == want and di.generator != null:
			return di
	return null


func _settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _shoot(eye: Vector3, target: Vector3, path: String) -> void:
	var cam := Camera3D.new()
	cam.position = eye
	cam.fov = 70.0
	cam.far = 4000.0
	add_child(cam)
	cam.look_at(target, Vector3.UP)
	cam.make_current()
	await _settle(3.0)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
	else:
		img.save_png(path)
		print("SAVED %s" % path)
	cam.queue_free()
