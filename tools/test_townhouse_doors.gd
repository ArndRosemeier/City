## Townhouse / small-lot façades must record hung doors with solid wall frames.
## Run: powershell -File tools\run_test.ps1 test_townhouse_doors
extends Node

const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const BuildingGrammarScript := preload("res://scripts/city/building_grammar.gd")

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_check_townhouse_doors()
	_check_narrow_shell_skips_empty_hole()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _make_grammar(seed: int) -> BuildingGrammar:
	var brush: CityBrush = CityBrushScript.new()
	brush.use_offline_volume()
	var g: BuildingGrammar = BuildingGrammarScript.new()
	g.brush = brush
	g.rng = RandomNumberGenerator.new()
	g.rng.seed = seed
	g.theme = DistrictTheme.make(DistrictTheme.GARDEN_RESIDENTIAL)
	g.max_height = 40
	return g


func _check_townhouse_doors() -> void:
	var hung := 0
	var builds := 0
	for seed in range(20):
		for facing in range(4):
			var g := _make_grammar(seed * 17 + facing)
			## Typical ~12 m town lot footprint in voxels.
			var bmin := Vector3i(4, 4, 4)
			var bmax := Vector3i(28, 4, 28)
			g.townhouse_row(bmin, bmax, facing)
			builds += 1
			if g.lot_doorways.is_empty():
				_fail("FAIL seed=%d facing=%d townhouse has no lot_doorways" % [seed, facing])
				continue
			for item in g.lot_doorways:
				var d: CastleDoorway = item as CastleDoorway
				if d == null:
					_fail("FAIL null doorway seed=%d facing=%d" % [seed, facing])
					continue
				if not DoorBarrier.has_wall_frame(g.brush, d):
					_fail(
						"FAIL seed=%d facing=%d doorway %s lacks wall frame"
						% [seed, facing, d.describe() if d.has_method("describe") else str(d.center)]
					)
					continue
				hung += 1
	print("townhouse_doors builds=%d hung=%d" % [builds, hung])
	if hung < builds:
		_fail("FAIL expected at least one hung door per townhouse build")


func _check_narrow_shell_skips_empty_hole() -> void:
	## A façade shorter than jamb reach must not punch a width-3 air hole.
	var g := _make_grammar(1)
	var min_v := Vector3i(10, 4, 10)
	var max_v := Vector3i(14, 12, 20)  ## along X = 4 < 5
	g._fill_shell(min_v, max_v, VoxelMaterial.BRICK, 0, true, false, true)
	if not g.lot_doorways.is_empty():
		_fail("FAIL narrow shell recorded a doorway")
	var cx := (min_v.x + max_v.x) / 2
	var z := max_v.z - 1
	var air_n := 0
	for x in range(min_v.x, max_v.x):
		if g.brush.get_vox(Vector3i(x, min_v.y + 2, z)) == VoxelMaterial.AIR:
			air_n += 1
	if air_n >= 3 and absi(cx - min_v.x) <= 2:
		## Center band should stay masonry when hang is skipped.
		var center_air := g.brush.get_vox(Vector3i(cx, min_v.y + 2, z)) == VoxelMaterial.AIR
		if center_air:
			_fail("FAIL narrow shell punched a door-sized air clear")
	print("narrow_shell air_on_face=%d doorways=%d" % [air_n, g.lot_doorways.size()])
