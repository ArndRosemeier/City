## Proves Ui3D buttons + MandelbrotPanel target/zoom math + native 1000² bake.
##
## Run: powershell -File tools\run_test.ps1 test_mandelbrot_panel
extends Node

const Ui3DScript := preload("res://scripts/city/ui_3d.gd")
const MandelbrotPanelScript := preload("res://scripts/city/mandelbrot_panel.gd")
const MandelbrotArenaScript := preload("res://scripts/city/mandelbrot_arena.gd")
const DistrictPlannerScript := preload("res://scripts/city/district_planner.gd")
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")

const WORLD_SEED := 42

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _bytes_varied(bytes: PackedByteArray) -> bool:
	if bytes.size() < 16:
		return false
	var r0 := bytes[0]
	var g0 := bytes[1]
	var b0 := bytes[2]
	for i in range(0, bytes.size(), 16):
		if bytes[i] != r0 or bytes[i + 1] != g0 or bytes[i + 2] != b0:
			return true
	return false


func _ready() -> void:
	_check_ui_buttons()
	await _check_mandelbrot_zoom()
	_check_fractal_layout()
	_check_panel_faces_outward()
	_check_fractal_glow_material()
	await _check_native_bake()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _check_ui_buttons() -> void:
	var panel: Node3D = Ui3DScript.new() as Node3D
	add_child(panel)
	panel.set("size_m", Vector2(5.0, 7.0))
	panel.call(
		"add_button",
		&"zoom_in",
		Rect2(0.5, 0.0, 0.4, 0.2),
		"+",
		Color(0.2, 0.6, 0.2)
	)
	panel.call("begin", Vector3.ZERO, 0.0)
	var got := {"id": StringName()}
	panel.connect(
		"button_pressed",
		func(button_id: Variant, _uv: Variant) -> void:
			got["id"] = button_id as StringName
	)
	var hit: Vector3 = panel.to_global(panel.call("_uv_to_local", Vector2(0.7, 0.1)) as Vector3)
	if not bool(panel.call("press_at_world", hit)):
		_fail("FAIL button press_at_world rejected")
		panel.queue_free()
		return
	if got["id"] != &"zoom_in":
		_fail("FAIL expected zoom_in button, got %s" % str(got["id"]))
		panel.queue_free()
		return
	panel.queue_free()


func _check_mandelbrot_zoom() -> void:
	var panel: Node3D = MandelbrotPanelScript.new() as Node3D
	add_child(panel)
	panel.call("begin", Vector3(0.0, 3.5, 0.0), 0.0)
	if not bool(await panel.call("wait_bake_finished", 30.0)):
		_fail("FAIL initial async bake did not finish")
		panel.queue_free()
		return

	var uv := Vector2(0.35, 0.75)
	var local: Vector3 = panel.call("_uv_to_local", uv) as Vector3
	var world: Vector3 = panel.to_global(local)
	if not bool(panel.call("press_at_world", world)):
		_fail("FAIL fractal surface press rejected")
		panel.queue_free()
		return
	if not bool(panel.call("has_target")):
		_fail("FAIL MandelbrotPanel has no target after fractal press")
		panel.queue_free()
		return
	var scale0: float = float(panel.get("view_scale"))
	if not bool(panel.call("zoom_in_at_target")):
		_fail("FAIL zoom_in_at_target failed with a target set")
		panel.queue_free()
		return
	if not bool(await panel.call("wait_bake_finished", 30.0)):
		_fail("FAIL zoom-in async bake did not finish")
		panel.queue_free()
		return
	var scale1: float = float(panel.get("view_scale"))
	if scale1 >= scale0:
		_fail("FAIL zoom in did not shrink view_scale (%s -> %s)" % [scale0, scale1])
		panel.queue_free()
		return
	panel.call("zoom_out")
	if not bool(await panel.call("wait_bake_finished", 30.0)):
		_fail("FAIL zoom-out async bake did not finish")
		panel.queue_free()
		return
	var scale2: float = float(panel.get("view_scale"))
	if scale2 <= scale1:
		_fail("FAIL zoom out did not grow view_scale (%s -> %s)" % [scale1, scale2])
		panel.queue_free()
		return
	panel.queue_free()


func _check_fractal_layout() -> void:
	var coord := DistrictTheme.find_coord_for_theme(WORLD_SEED, DistrictTheme.FRACTAL, 12)
	if DistrictTheme.for_district(WORLD_SEED, coord).id != DistrictTheme.FRACTAL:
		_fail("FAIL no Fractal theme within ring 12 for seed %d" % WORLD_SEED)
		return
	var dseed := DistrictCoord.district_seed(WORLD_SEED, coord)
	var planner: DistrictPlanner = DistrictPlannerScript.new()
	planner.theme = DistrictTheme.make(DistrictTheme.FRACTAL)
	planner.build(
		DistrictCoord.SIZE_X_VOX, DistrictCoord.SIZE_Z_VOX, dseed, DistrictCoord.CELL_SIZE, coord
	)
	if planner.large_fractal.size.x <= 0:
		_fail("FAIL planner produced no large_fractal")
		return
	var lots := 0
	var fractal_cells := 0
	var roads := 0
	for z in range(planner.cells_z):
		for x in range(planner.cells_x):
			var tag := planner.tag_at(x, z)
			if LandUse.is_lot(tag):
				lots += 1
			elif tag == LandUse.FRACTAL:
				fractal_cells += 1
			elif LandUse.is_road(tag):
				roads += 1
	var mid_roads := 0
	var x0 := planner.cells_x / 4
	var x1 := (planner.cells_x * 3) / 4
	var z0 := planner.cells_z / 4
	var z1 := (planner.cells_z * 3) / 4
	for z2 in range(z0, z1):
		for x2 in range(x0, x1):
			if LandUse.is_road(planner.tag_at(x2, z2)):
				mid_roads += 1
	print(
		"fractal layout lots=%d fractal=%d roads=%d mid_roads=%d rect=%s"
		% [lots, fractal_cells, roads, mid_roads, planner.large_fractal]
	)
	if lots > 0:
		_fail("FAIL Fractal layout still has %d lots" % lots)
		return
	if fractal_cells < 100:
		_fail("FAIL Fractal layout only has %d fractal cells" % fractal_cells)
		return
	if roads < 8:
		_fail("FAIL Fractal layout missing edge roads (%d)" % roads)
		return
	if mid_roads > 0:
		_fail("FAIL Fractal middle still has %d road cells" % mid_roads)


func _check_panel_faces_outward() -> void:
	var arena: Node3D = MandelbrotArenaScript.new() as Node3D
	add_child(arena)
	arena.call("setup", Vector3(0.0, 0.0, 0.0), Vector3(40.0, 0.0, 40.0), 3.0)
	var panels: Array[Node3D] = []
	for child in arena.get_children():
		if child.has_method("rebuild_fractal"):
			panels.append(child as Node3D)
	if panels.size() != 4:
		_fail("FAIL expected 4 Mandelbrot panels, got %d" % panels.size())
		arena.queue_free()
		return
	var center := Vector3(20.0, 3.0, 20.0)
	for panel in panels:
		var face_dir: Vector3 = -panel.global_transform.basis.z
		var away := panel.global_position - center
		away.y = 0.0
		if away.length_squared() < 0.01:
			_fail("FAIL panel sitting on centre")
			arena.queue_free()
			return
		if face_dir.dot(away.normalized()) < 0.85:
			_fail(
				"FAIL panel face not outward: pos=%s face=%s"
				% [str(panel.global_position), str(face_dir)]
			)
			arena.queue_free()
			return
	arena.queue_free()


func _check_fractal_glow_material() -> void:
	if VoxelMaterial.FRACTAL_GLOW >= VoxelMaterial.COUNT:
		_fail("FAIL FRACTAL_GLOW id out of range")
		return
	if VoxelMaterial.is_gem(VoxelMaterial.FRACTAL_GLOW):
		_fail("FAIL FRACTAL_GLOW must not be classified as a gem")
		return
	if VoxelMaterial.is_player_carve_immune(VoxelMaterial.FRACTAL_GLOW):
		_fail("FAIL FRACTAL_GLOW must be carveable (unlike gems)")
		return
	if not VoxelMaterial.is_walkable_surface(VoxelMaterial.FRACTAL_GLOW):
		_fail("FAIL FRACTAL_GLOW should be walkable")
		return
	var mat: Material = VoxelBlockLibrary.block_material_for(VoxelMaterial.FRACTAL_GLOW)
	if mat == null:
		_fail("FAIL FRACTAL_GLOW has no block material")
		return


func _check_native_bake() -> void:
	## async waits below — caller must await this function.
	var eng: Object = CityVoxelNativeScript.make_mandelbrot()
	if eng == null:
		_fail("FAIL NativeMandelbrot missing")
		return
	var left: Dictionary = eng.call(
		"complex_at_uv", "-1.999999999999999", "0", "1e-20", 0.0, 0.5
	)
	var right: Dictionary = eng.call(
		"complex_at_uv", "-1.999999999999999", "0", "1e-20", 1.0, 0.5
	)
	if str(left.get("re", "")) == str(right.get("re", "")):
		_fail("FAIL HP complex_at_uv edges collapsed at 1e-20")
		return
	var sample: PackedByteArray = eng.call(
		"render_rgba8", "-0.5", "0", "1.5", 64, 64, 256
	) as PackedByteArray
	if sample.size() != 64 * 64 * 4 or not _bytes_varied(sample):
		_fail("FAIL native sample bake flat/wrong size")
		return
	## Interior of the main cardioid should be the shared black.
	var cardioid: PackedByteArray = eng.call(
		"render_rgba8", "-0.2", "0", "0.15", 32, 32, 256
	) as PackedByteArray
	var blackish := 0
	for i in range(0, cardioid.size(), 4):
		if cardioid[i] <= 10 and cardioid[i + 1] <= 10 and cardioid[i + 2] <= 20:
			blackish += 1
	if blackish < 32:
		_fail("FAIL missing interior black spots (blackish=%d)" % blackish)
		return
	var panel: Node3D = MandelbrotPanelScript.new() as Node3D
	add_child(panel)
	panel.call("begin", Vector3(0.0, 3.5, 0.0), 0.0)
	if not bool(await panel.call("wait_bake_finished", 30.0)):
		_fail("FAIL async bake never produced a texture")
		panel.queue_free()
		return
	if int(panel.call("bake_resolution")) != 1000:
		_fail("FAIL bake_resolution is not 1000")
		panel.queue_free()
		return
	var tex0: Vector2i = panel.call("bake_texture_size") as Vector2i
	if tex0 != Vector2i(1000, 1000):
		_fail("FAIL initial panel texture not 1000², got %s" % str(tex0))
		panel.queue_free()
		return
	panel.set("view_scale_hp", "1e-6")
	panel.call("rebuild_fractal")
	if not bool(await panel.call("wait_bake_finished", 30.0)):
		_fail("FAIL zoomed async bake never produced a texture")
		panel.queue_free()
		return
	var tex1: Vector2i = panel.call("bake_texture_size") as Vector2i
	if tex1 != Vector2i(1000, 1000):
		_fail("FAIL zoomed panel texture not 1000², got %s" % str(tex1))
		panel.queue_free()
		return
	panel.queue_free()
