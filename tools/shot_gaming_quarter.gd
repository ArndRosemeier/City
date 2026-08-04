## Gaming-quarter satellite inspection: the Tetris arcade on the west lawn and the monster
## chess court on the east one, with the Go garden left as the centrepiece between them.
##
## The arcade is judged from where a player stands: three bays have to read as three
## separate cabinets under one wall, not as a single striped slab. The chess court is judged
## for square contrast — a checkerboard that reads as grey at standing height is useless no
## matter how correct the rules behind it are.
##
## Run: powershell -File tools\run_test.ps1 shot_gaming_quarter -Rendered -TimeoutSec 400 -GodotArgs "--spawn-theme=gaming"
extends Node

const ARCADE_PNG := "res://tools/quarter_arcade.png"
const ARCADE_BAY_PNG := "res://tools/quarter_arcade_bay.png"
const CHESS_PNG := "res://tools/quarter_chess.png"
const CHESS_AERIAL_PNG := "res://tools/quarter_chess_aerial.png"
const WIDE_PNG := "res://tools/quarter_wide.png"
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
	if theme.id != DistrictTheme.GAMING:
		push_error("FAIL spawn district is %s, expected Gaming" % theme.display_name)
		get_tree().quit(1)
		return

	await _settle(12.0)
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
	if not _check_zones(layout, inst):
		get_tree().quit(1)
		return

	var origin := inst.origin_vox
	print(
		"arcade %s..%s  chess %s..%s  board a1=%s pitch=%d"
		% [
			layout.arcade_min, layout.arcade_max, layout.chess_min, layout.chess_max,
			layout.chess_origin, layout.chess_square_vox,
		]
	)

	## Whole row head on, from where you walk in off the meadow.
	var mid_cab: Vector3i = layout.arcade_cabinets[1]
	var row_eye := _world(origin, mid_cab + Vector3i(56, 18, 0))
	walker.global_position = row_eye + Vector3(0.0, 1.0, 0.0)
	await _settle(14.0)
	await _shoot(row_eye, _world(origin, mid_cab + Vector3i(0, 16, 0)), ARCADE_PNG)

	## One bay close up and off-axis: pilasters, marquee, and the NPC at the controls.
	var bay_eye := _world(origin, mid_cab + Vector3i(20, 8, -18))
	walker.global_position = bay_eye + Vector3(0.0, 1.0, 0.0)
	await _settle(8.0)
	await _shoot(bay_eye, _world(origin, mid_cab + Vector3i(0, 12, 0)), ARCADE_BAY_PNG)

	## Board from behind white's home rank, which is where a player arrives from the garden.
	var half := layout.chess_span_vox() / 2
	var board_mid := layout.chess_origin + Vector3i(half, 0, half)
	var seat_eye := _world(origin, board_mid + Vector3i(0, 14, -half - 26))
	walker.global_position = seat_eye + Vector3(0.0, 1.0, 0.0)
	await _settle(14.0)
	await _shoot(seat_eye, _world(origin, board_mid), CHESS_PNG)

	## Straight down the board: do 64 squares alternate cleanly, and does the rim frame them?
	var top_eye := _world(origin, board_mid + Vector3i(0, 120, -40))
	walker.global_position = _world(origin, board_mid) + Vector3(0.0, 2.0, 0.0)
	await _settle(8.0)
	await _shoot(top_eye, _world(origin, board_mid), CHESS_AERIAL_PNG)

	## The quarter as one composition: arcade, garden, court, and the meadow left over.
	var pad_mid := (layout.pad_min + layout.pad_max) / 2
	var wide := _world(origin, pad_mid)
	walker.global_position = wide + Vector3(0.0, 60.0, 0.0)
	await _settle(14.0)
	await _shoot(wide + Vector3(0.0, 170.0, 150.0), wide, WIDE_PNG)

	print("RESULT: OK")
	get_tree().quit(0)


func _check_zones(layout: GamingLayout, inst: DistrictInstance) -> bool:
	if layout.arcade_cabinets.size() != GamingArcade.CABINETS:
		push_error(
			"FAIL layout published %d arcade bays, expected %d"
			% [layout.arcade_cabinets.size(), GamingArcade.CABINETS]
		)
		return false
	if inst.gaming_cabinets.size() != GamingArcade.CABINETS:
		push_error(
			"FAIL %d cabinets streamed in, expected %d"
			% [inst.gaming_cabinets.size(), GamingArcade.CABINETS]
		)
		return false
	for machine in inst.gaming_cabinets:
		if bool(machine.call("is_broken")):
			push_error("FAIL cabinet %s stamped itself broken" % machine.name)
			return false
	if inst.gaming_cabinet_ped == null:
		push_error("FAIL no arcade ped — the quarter streams in deserted")
		return false
	if layout.chess_origin == Vector3i.ZERO or layout.chess_max == layout.chess_min:
		push_error("FAIL layout carries no chess court")
		return false
	if inst.chess_arena == null:
		push_error("FAIL no chess arena — the court streams in as bare squares")
		return false
	var arena: ChessArena = inst.chess_arena as ChessArena
	var standing := 0
	for sq in range(64):
		if arena.actor_at(sq) != null:
			standing += 1
	if standing != 32:
		push_error("FAIL %d monsters on the chess court, expected 32" % standing)
		return false
	return true


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
