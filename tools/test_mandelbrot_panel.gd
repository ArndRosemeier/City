## Proves Ui3D buttons + MandelbrotPanel target/zoom math + native 1000² bake.
##
## Run: powershell -File tools\run_test.ps1 test_mandelbrot_panel
extends Node

const Ui3DScript := preload("res://scripts/city/ui_3d.gd")
const MandelbrotPanelScript := preload("res://scripts/city/mandelbrot_panel.gd")
const MandelbrotArenaScript := preload("res://scripts/city/mandelbrot_arena.gd")
const FractalTerrainMorphScript := preload("res://scripts/city/fractal_terrain_morph.gd")
const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const DistrictPlannerScript := preload("res://scripts/city/district_planner.gd")
const DistrictInstanceScript := preload("res://scripts/city/district_instance.gd")
const DistrictGeneratorScript := preload("res://scripts/city/district_generator.gd")
const FractalComposerScript := preload("res://scripts/city/fractal_composer.gd")
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
	_check_morph_ui_feedback()
	await _check_mandelbrot_zoom()
	await _check_create_button()
	await _check_clear_button()
	await _check_instant_toggle()
	_check_loading_splash_art()
	_check_fractal_layout()
	_check_fractal_viewing_cross()
	_check_fractal_no_auto_actors()
	_check_panel_faces_outward()
	_check_fractal_glow_material()
	_check_fractal_band_materials()
	await _check_native_bake()
	_check_native_iters()
	await _check_morph_progression()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _check_morph_ui_feedback() -> void:
	var panel: Node3D = Ui3DScript.new() as Node3D
	add_child(panel)
	panel.set("size_m", Vector2(9.0, 5.0))
	panel.set("surface_color", Color(0.08, 0.08, 0.10, 1.0))
	panel.call("begin", Vector3.ZERO, 0.0)
	panel.call("set_surface_glow", Color(0.12, 0.62, 0.22, 1.0), 3.0)
	if panel.get("surface_color") != Color(0.12, 0.62, 0.22, 1.0):
		_fail("FAIL set_surface_glow did not stick")
		panel.queue_free()
		return
	var surf: MeshInstance3D = panel.find_child("Surface", true, false) as MeshInstance3D
	if surf == null or not (surf.material_override is StandardMaterial3D):
		_fail("FAIL Surface material missing after set_surface_glow")
		panel.queue_free()
		return
	var mat := surf.material_override as StandardMaterial3D
	if not mat.emission_enabled or mat.emission_energy_multiplier < 2.5:
		_fail("FAIL surface glow emission not applied")
		panel.queue_free()
		return
	var morph: FractalTerrainMorph = FractalTerrainMorphScript.new() as FractalTerrainMorph
	add_child(morph)
	var phases: Array[StringName] = []
	morph.phase_changed.connect(func(p: StringName) -> void: phases.append(p))
	morph._set_phase(FractalTerrainMorphScript.PHASE_BUILD)
	morph._set_phase(FractalTerrainMorphScript.PHASE_IDLE)
	if phases != [FractalTerrainMorphScript.PHASE_BUILD, FractalTerrainMorphScript.PHASE_IDLE]:
		_fail("FAIL morph phase_changed sequence %s" % str(phases))
		panel.queue_free()
		morph.queue_free()
		return
	panel.queue_free()
	morph.queue_free()


func _check_ui_buttons() -> void:
	var panel: Node3D = Ui3DScript.new() as Node3D
	add_child(panel)
	panel.set("size_m", Vector2(9.0, 5.0))
	panel.call(
		"add_button",
		&"zoom_in",
		Rect2(0.5, 0.0, 0.4, 0.2),
		"+",
		Color(0.2, 0.6, 0.2)
	)
	panel.call(
		"add_button",
		&"create",
		Rect2(0.08, 0.25, 0.84, 0.18),
		"Create",
		Color(0.18, 0.38, 0.72)
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
	var create_mesh: Node = panel.find_child("Btn_create", true, false)
	if create_mesh == null:
		_fail("FAIL Create button mesh missing")
		panel.queue_free()
		return
	var label_node: Node = create_mesh.find_child("Label", true, false)
	if label_node == null or not (label_node is Label3D):
		_fail("FAIL Create button has no Label3D caption")
		panel.queue_free()
		return
	if str((label_node as Label3D).text) != "Create":
		_fail("FAIL Create Label3D text is '%s'" % str((label_node as Label3D).text))
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

	## Fractal is the left 5×5 (uv.x < 5/9).
	var uv := Vector2(0.30, 0.55)
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


func _check_create_button() -> void:
	var panel: Node3D = MandelbrotPanelScript.new() as Node3D
	add_child(panel)
	panel.call("begin", Vector3(0.0, 2.5, 0.0), 0.0)
	if not bool(await panel.call("wait_bake_finished", 30.0)):
		_fail("FAIL create-test initial bake did not finish")
		panel.queue_free()
		return
	var got := {"cx": "", "cy": "", "scale": "", "n": 0}
	panel.connect(
		"create_requested",
		func(cx: Variant, cy: Variant, scale: Variant) -> void:
			got["cx"] = str(cx)
			got["cy"] = str(cy)
			got["scale"] = str(scale)
			got["n"] = int(got["n"]) + 1
	)
	## Control column: Create is the upper full-width action button.
	var hit: Vector3 = panel.to_global(panel.call("_uv_to_local", Vector2(0.78, 0.41)) as Vector3)
	if not bool(panel.call("press_at_world", hit)):
		_fail("FAIL Create press_at_world rejected")
		panel.queue_free()
		return
	if int(got["n"]) != 1:
		_fail("FAIL create_requested not emitted (n=%d)" % int(got["n"]))
		panel.queue_free()
		return
	if str(got["cx"]) != str(panel.get("view_cx_hp")):
		_fail("FAIL create_requested cx mismatch")
		panel.queue_free()
		return
	if str(got["scale"]) != str(panel.get("view_scale_hp")):
		_fail("FAIL create_requested scale mismatch")
		panel.queue_free()
		return
	panel.queue_free()


func _check_clear_button() -> void:
	var panel: Node3D = MandelbrotPanelScript.new() as Node3D
	add_child(panel)
	panel.call("begin", Vector3(0.0, 2.5, 0.0), 0.0)
	if not bool(await panel.call("wait_bake_finished", 30.0)):
		_fail("FAIL clear-test initial bake did not finish")
		panel.queue_free()
		return
	var clear_mesh: Node = panel.find_child("Btn_clear", true, false)
	if clear_mesh == null:
		_fail("FAIL Clear button mesh missing")
		panel.queue_free()
		return
	var label_node: Node = clear_mesh.find_child("Label", true, false)
	if label_node == null or not (label_node is Label3D):
		_fail("FAIL Clear button has no Label3D caption")
		panel.queue_free()
		return
	if str((label_node as Label3D).text) != "Clear":
		_fail("FAIL Clear Label3D text is '%s'" % str((label_node as Label3D).text))
		panel.queue_free()
		return
	var n := {"n": 0}
	panel.connect("clear_requested", func() -> void: n["n"] = int(n["n"]) + 1)
	## Control column: Clear is the lower full-width action button.
	var hit: Vector3 = panel.to_global(panel.call("_uv_to_local", Vector2(0.78, 0.17)) as Vector3)
	if not bool(panel.call("press_at_world", hit)):
		_fail("FAIL Clear press_at_world rejected")
		panel.queue_free()
		return
	if int(n["n"]) != 1:
		_fail("FAIL clear_requested not emitted (n=%d)" % int(n["n"]))
		panel.queue_free()
		return
	## Create press must not fire clear.
	var create_hit: Vector3 = panel.to_global(
		panel.call("_uv_to_local", Vector2(0.78, 0.41)) as Vector3
	)
	if not bool(panel.call("press_at_world", create_hit)):
		_fail("FAIL Create press after Clear rejected")
		panel.queue_free()
		return
	if int(n["n"]) != 1:
		_fail("FAIL Clear fired from Create press (n=%d)" % int(n["n"]))
		panel.queue_free()
		return
	## Morph abort must stop a running gen.
	var morph: FractalTerrainMorph = FractalTerrainMorphScript.new() as FractalTerrainMorph
	add_child(morph)
	morph._gen = 3
	morph._running = true
	morph.abort()
	if morph.is_running() or morph._gen != 4:
		_fail("FAIL morph.abort did not bump gen / clear running")
		panel.queue_free()
		morph.queue_free()
		return
	panel.queue_free()
	morph.queue_free()


func _check_instant_toggle() -> void:
	var panel: Node3D = MandelbrotPanelScript.new() as Node3D
	add_child(panel)
	panel.call("begin", Vector3(0.0, 2.5, 0.0), 0.0)
	if not bool(await panel.call("wait_bake_finished", 30.0)):
		_fail("FAIL instant-test initial bake did not finish")
		panel.queue_free()
		return
	if bool(panel.call("instant_mode")):
		_fail("FAIL Instant should start off")
		panel.queue_free()
		return
	var n := {"n": 0}
	panel.connect(
		"instant_changed",
		func(enabled: bool) -> void:
			n["n"] = int(n["n"]) + 1
			if not enabled:
				_fail("FAIL instant_changed expected true")
	)
	var hit: Vector3 = panel.to_global(panel.call("_uv_to_local", Vector2(0.78, 0.86)) as Vector3)
	if not bool(panel.call("press_at_world", hit)):
		_fail("FAIL Instant press_at_world rejected")
		panel.queue_free()
		return
	if int(n["n"]) != 1 or not bool(panel.call("instant_mode")):
		_fail("FAIL Instant toggle did not enable (n=%d)" % int(n["n"]))
		panel.queue_free()
		return
	var tex: Texture2D = panel.call("bake_texture") as Texture2D
	if tex == null or tex.get_width() != 1000:
		_fail("FAIL bake_texture missing after Instant toggle")
		panel.queue_free()
		return
	var arena: Node3D = MandelbrotArenaScript.new() as Node3D
	add_child(arena)
	arena.call("setup", Vector3(0.0, 0.0, 0.0), Vector3(40.0, 0.0, 40.0), 3.0)
	## Flip Instant on one panel — arena should sync the other three.
	var first_panel: Node = null
	for child in arena.get_children():
		if child.has_method("set_instant_mode"):
			first_panel = child
			break
	if first_panel == null:
		_fail("FAIL arena has no Instant panels")
		panel.queue_free()
		arena.queue_free()
		return
	first_panel.call("set_instant_mode", true)
	for child2 in arena.get_children():
		if child2.has_method("instant_mode") and not bool(child2.call("instant_mode")):
			_fail("FAIL Instant sync left a panel off")
			panel.queue_free()
			arena.queue_free()
			return
	if not bool(arena.call("instant_mode")):
		_fail("FAIL arena Instant flag not set")
		panel.queue_free()
		arena.queue_free()
		return
	panel.queue_free()
	arena.queue_free()


func _check_loading_splash_art() -> void:
	const LoadingSplashScript := preload("res://scripts/city/loading_splash.gd")
	var splash: CanvasLayer = LoadingSplashScript.new() as CanvasLayer
	add_child(splash)
	## Force _ready so TitleArt exists.
	splash.visible = false
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.7, 0.3, 1.0))
	var tex := ImageTexture.create_from_image(img)
	splash.call("show_splash", "Creating fractal…", tex)
	var art: TextureRect = splash.find_child("TitleArt", true, false) as TextureRect
	if art == null or art.texture != tex:
		_fail("FAIL LoadingSplash did not show custom fractal art")
		splash.queue_free()
		return
	var status_lbl: Label = splash.call("status_label") as Label
	if status_lbl == null or status_lbl.text != "Creating fractal…":
		_fail("FAIL LoadingSplash status text wrong")
		splash.queue_free()
		return
	## hide_splash fades async — restore happens in callback; set_art(null) via direct call.
	splash.call("_set_art", null)
	if art.texture == tex:
		_fail("FAIL LoadingSplash did not restore title art")
		splash.queue_free()
		return
	splash.queue_free()


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


func _check_fractal_viewing_cross() -> void:
	var coord := DistrictTheme.find_coord_for_theme(WORLD_SEED, DistrictTheme.FRACTAL, 12)
	if DistrictTheme.for_district(WORLD_SEED, coord).id != DistrictTheme.FRACTAL:
		_fail("FAIL viewing-cross: no Fractal theme")
		return
	var dseed := DistrictCoord.district_seed(WORLD_SEED, coord)
	var planner: DistrictPlanner = DistrictPlannerScript.new()
	planner.theme = DistrictTheme.make(DistrictTheme.FRACTAL)
	planner.build(
		DistrictCoord.SIZE_X_VOX, DistrictCoord.SIZE_Z_VOX, dseed, DistrictCoord.CELL_SIZE, coord
	)
	var brush: CityBrush = CityBrushScript.new() as CityBrush
	brush.use_offline_volume()
	var composer: FractalComposer = FractalComposerScript.new() as FractalComposer
	composer.brush = brush
	composer.rng = RandomNumberGenerator.new()
	composer.ground_y = 6
	composer.planner = planner
	composer.cell_size = DistrictCoord.CELL_SIZE
	var lf := planner.large_fractal
	composer.compose(
		Vector3i(lf.position.x * DistrictCoord.CELL_SIZE, 6, lf.position.y * DistrictCoord.CELL_SIZE),
		Vector3i(lf.end.x * DistrictCoord.CELL_SIZE, 7, lf.end.y * DistrictCoord.CELL_SIZE)
	)
	if composer.last_view_y != composer.ground_y + FractalComposerScript.VIEW_RISE_VOX:
		_fail(
			"FAIL viewing deck y %d want %d"
			% [composer.last_view_y, composer.ground_y + FractalComposerScript.VIEW_RISE_VOX]
		)
		return
	var gx0 := composer.last_glow_min.x
	var gz0 := composer.last_glow_min.z
	var gx1 := composer.last_glow_max.x
	var gz1 := composer.last_glow_max.z
	var cx := (gx0 + gx1) / 2
	var cz := (gz0 + gz1) / 2
	var top := composer.last_view_y
	## Circle centre + four arm samples must be glass.
	if brush.get_vox(Vector3i(cx, top, cz)) != VoxelMaterial.GLASS:
		_fail("FAIL viewing circle centre is not glass")
		return
	if brush.get_vox(Vector3i(cx + FractalComposerScript.CIRCLE_RADIUS_VOX + 4, top, cz)) != VoxelMaterial.GLASS:
		_fail("FAIL east arm missing glass")
		return
	if brush.get_vox(Vector3i(cx, top, cz + FractalComposerScript.CIRCLE_RADIUS_VOX + 4)) != VoxelMaterial.GLASS:
		_fail("FAIL north arm missing glass")
		return
	## Sideways stair along the south edge (not cutting inward through the plaza).
	var mid_step := FractalComposerScript.VIEW_RISE_VOX / 2
	var mid_y := composer.ground_y + 1 + mid_step
	var edge_z := gz0 + FractalComposerScript.EDGE_INSET_VOX
	var mid_x := cx - FractalComposerScript.VIEW_RISE_VOX + mid_step * FractalComposerScript.STAIR_RUN
	if brush.get_vox(Vector3i(mid_x, mid_y, edge_z)) != VoxelMaterial.GLASS:
		_fail("FAIL south sideways stair missing at mid height x=%d" % mid_x)
		return
	## Below view height, no glass on the inward path toward the circle (sculpture zone).
	var inward_z := edge_z + 20
	if brush.get_vox(Vector3i(cx, mid_y, inward_z)) == VoxelMaterial.GLASS:
		_fail("FAIL glass stair cuts inward below view height at z=%d" % inward_z)
		return
	## Arm tip only at view height on the panel centre-line — not a mid-edge runway.
	if brush.get_vox(Vector3i(cx, top, edge_z)) != VoxelMaterial.GLASS:
		_fail("FAIL south arm tip missing at view height")
		return
	var runway_glass := 0
	for x in range(gx0 + 8, gx1 - 8):
		if absi(x - cx) <= FractalComposerScript.ARM_HALF_W:
			continue ## arm tip / final stair tread
		## Stair occupies the climb approach west of centre; skip that strip at top too.
		if x < cx and x >= cx - FractalComposerScript.VIEW_RISE_VOX - 2:
			continue
		if brush.get_vox(Vector3i(x, top, edge_z)) == VoxelMaterial.GLASS:
			runway_glass += 1
	if runway_glass > 0:
		_fail("FAIL perimeter glass runway still present (%d cells)" % runway_glass)
		return
	## Deck under the circle stays glow (platform is only at view height).
	if brush.get_vox(Vector3i(cx, composer.ground_y, cz)) != VoxelMaterial.FRACTAL_GLOW:
		_fail("FAIL glow deck lost under viewing circle")
		return
	print(
		"fractal viewing cross top_y=%d circle_r=%d sideways stairs ok"
		% [top, FractalComposerScript.CIRCLE_RADIUS_VOX]
	)


func _check_fractal_no_auto_actors() -> void:
	var di: DistrictInstance = DistrictInstanceScript.new() as DistrictInstance
	var gen: DistrictGenerator = DistrictGeneratorScript.new() as DistrictGenerator
	di.generator = gen
	gen.theme = DistrictTheme.make(DistrictTheme.FRACTAL)
	if di.allows_auto_actors():
		_fail("FAIL Fractal district still allows auto actors")
		return
	gen.theme = DistrictTheme.make(DistrictTheme.CORE_HIGHRISE)
	if not di.allows_auto_actors():
		_fail("FAIL Core High-Rise should allow auto actors")


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


func _check_fractal_band_materials() -> void:
	if VoxelMaterial.FRACTAL_BAND_COUNT != 16:
		_fail("FAIL expected 16 FRACTAL_BAND slots, got %d" % VoxelMaterial.FRACTAL_BAND_COUNT)
		return
	if VoxelMaterial.FRACTAL_BAND_LAST >= VoxelMaterial.COUNT:
		_fail("FAIL FRACTAL_BAND ids out of range")
		return
	var colors: Array[Color] = []
	for i in range(VoxelMaterial.FRACTAL_BAND_COUNT):
		var id := VoxelMaterial.fractal_band(i)
		if VoxelMaterial.is_gem(id):
			_fail("FAIL FRACTAL_BAND_%d classified as gem" % i)
			return
		if VoxelMaterial.is_player_carve_immune(id):
			_fail("FAIL FRACTAL_BAND_%d must be carveable" % i)
			return
		if not VoxelMaterial.is_self_supporting_terrain(id):
			_fail("FAIL FRACTAL_BAND_%d should be self-supporting" % i)
			return
		var mat: Material = VoxelBlockLibrary.block_material_for(id)
		if mat == null or not (mat is ShaderMaterial):
			_fail("FAIL FRACTAL_BAND_%d has no ShaderMaterial" % i)
			return
		var sm := mat as ShaderMaterial
		var shader: Shader = sm.shader
		if shader == null or not str(shader.resource_path).ends_with("voxel_fractal_band.gdshader"):
			_fail("FAIL FRACTAL_BAND_%d not using voxel_fractal_band.gdshader" % i)
			return
		var base: Color = sm.get_shader_parameter("base_color") as Color
		colors.append(base)
	var c0: Color = colors[0]
	var c5: Color = colors[5]
	var c10: Color = colors[10]
	## Hue wheel: red-ish, green-ish, blue-ish must differ strongly.
	if c0.r < 0.6 or c5.g < 0.6 or c10.b < 0.6:
		_fail(
			"FAIL sculpture bands not on a vivid hue wheel: 0=%s 5=%s 10=%s"
			% [str(c0), str(c5), str(c10)]
		)
		return
	var interior_mat: Material = VoxelBlockLibrary.block_material_for(VoxelMaterial.FRACTAL_INTERIOR)
	if interior_mat == null or not (interior_mat is ShaderMaterial):
		_fail("FAIL FRACTAL_INTERIOR has no ShaderMaterial")
		return
	var ic: Color = (interior_mat as ShaderMaterial).get_shader_parameter("base_color") as Color
	if ic.r + ic.g + ic.b > 0.35:
		_fail("FAIL FRACTAL_INTERIOR base_color too bright %s" % str(ic))
		return
	var em: float = float((interior_mat as ShaderMaterial).get_shader_parameter("emission_strength"))
	if em > 0.01:
		_fail("FAIL FRACTAL_INTERIOR must not emit (emission_strength=%s)" % em)
		return


func _check_native_iters() -> void:
	var eng: Object = CityVoxelNativeScript.make_mandelbrot()
	if eng == null or not eng.has_method("render_iters_u16"):
		_fail("FAIL NativeMandelbrot.render_iters_u16 missing")
		return
	var max_iters := 256
	var bytes: PackedByteArray = eng.call(
		"render_iters_u16", "-0.5", "0", "1.5", 48, 48, max_iters
	) as PackedByteArray
	if bytes.size() != 48 * 48 * 2:
		_fail("FAIL iters bake wrong size %d" % bytes.size())
		return
	var interior := 0
	var exterior := 0
	var seen: Dictionary = {}
	for i in range(0, bytes.size(), 2):
		var n := int(bytes[i]) | (int(bytes[i + 1]) << 8)
		seen[n] = true
		if n >= max_iters:
			interior += 1
		else:
			exterior += 1
	if interior < 8:
		_fail("FAIL iters bake missing interior (interior=%d)" % interior)
		return
	if exterior < 8:
		_fail("FAIL iters bake missing exterior (exterior=%d)" % exterior)
		return
	if seen.size() < 3:
		_fail("FAIL iters bake too uniform (%d distinct)" % seen.size())
		return
	## Deep cardioid should be mostly interior.
	var card: PackedByteArray = eng.call(
		"render_iters_u16", "-0.2", "0", "0.15", 24, 24, max_iters
	) as PackedByteArray
	var black := 0
	for j in range(0, card.size(), 2):
		var n2 := int(card[j]) | (int(card[j + 1]) << 8)
		if n2 >= max_iters:
			black += 1
	if black < 16:
		_fail("FAIL cardioid iters missing interior (black=%d)" % black)
	if not eng.has_method("render_smooth_mu_u16"):
		_fail("FAIL NativeMandelbrot.render_smooth_mu_u16 missing")
		return
	var mu_bytes: PackedByteArray = eng.call(
		"render_smooth_mu_u16", "-0.5", "0", "1.5", 48, 48, max_iters
	) as PackedByteArray
	if mu_bytes.size() != 48 * 48 * 2:
		_fail("FAIL smooth-μ bake wrong size %d" % mu_bytes.size())
		return
	var mu_interior := int(eng.call("mu_interior_u16"))
	var mu_in := 0
	var mu_out := 0
	for k in range(0, mu_bytes.size(), 2):
		var packed := int(mu_bytes[k]) | (int(mu_bytes[k + 1]) << 8)
		if packed == mu_interior:
			mu_in += 1
		else:
			mu_out += 1
	if mu_in < 8 or mu_out < 8:
		_fail("FAIL smooth-μ bake interior/exterior (%d/%d)" % [mu_in, mu_out])
		return
	var morph_preview: FractalTerrainMorph = FractalTerrainMorphScript.new() as FractalTerrainMorph
	add_child(morph_preview)
	morph_preview.voxel_size = 0.5
	var preview: Dictionary = morph_preview.call(
		"preview_targets_from_mu", mu_bytes, max_iters, 48, 48
	) as Dictionary
	var mats: PackedInt32Array = preview["mats"] as PackedInt32Array
	var heights: PackedInt32Array = preview["heights"] as PackedInt32Array
	var want_max_h := int(round(50.0 / 0.5))
	var ext_min_h := 2147483647
	var ext_max_h := -1
	var interior_cols := 0
	var mono_ok := true
	for mi in range(mats.size()):
		if int(mats[mi]) == VoxelMaterial.FRACTAL_INTERIOR:
			interior_cols += 1
			if int(heights[mi]) != 0:
				_fail("FAIL interior column has non-zero height")
				morph_preview.queue_free()
				return
			continue
		var h := int(heights[mi])
		ext_min_h = mini(ext_min_h, h)
		ext_max_h = maxi(ext_max_h, h)
		var band_i := int(mats[mi]) - VoxelMaterial.FRACTAL_BAND_FIRST
		## height→band via sqrt is monotonic: taller column must not use a lower band.
		for mj in range(mi + 1, mats.size()):
			if int(mats[mj]) == VoxelMaterial.FRACTAL_INTERIOR:
				continue
			var h2 := int(heights[mj])
			var band_j := int(mats[mj]) - VoxelMaterial.FRACTAL_BAND_FIRST
			if h2 > h and band_j < band_i:
				mono_ok = false
				break
			if h > h2 and band_i < band_j:
				mono_ok = false
				break
		if not mono_ok:
			break
	if interior_cols < 8:
		_fail("FAIL default-view morph missing dark interior (interior=%d)" % interior_cols)
		morph_preview.queue_free()
		return
	if ext_max_h != want_max_h:
		_fail(
			"FAIL exterior max height %d want %d (full 0–50 m remap)"
			% [ext_max_h, want_max_h]
		)
		morph_preview.queue_free()
		return
	if ext_min_h != 0:
		_fail("FAIL exterior min height %d want 0" % ext_min_h)
		morph_preview.queue_free()
		return
	if not mono_ok:
		_fail("FAIL height→band mapping is not monotonic")
		morph_preview.queue_free()
		return
	morph_preview.queue_free()


func _check_morph_progression() -> void:
	var brush: CityBrush = CityBrushScript.new() as CityBrush
	brush.use_offline_volume()
	var morph: FractalTerrainMorph = FractalTerrainMorphScript.new() as FractalTerrainMorph
	add_child(morph)
	morph.configure(
		Vector3(0.0, 0.0, 0.0),
		Vector3(20.0, 0.0, 20.0),
		3.0,
		0.5,
		func() -> CityBrush: return brush
	)
	## South edge: first ordered sample is sz = h-1 (world −Z).
	morph.set("_grid_w", 4)
	morph.set("_grid_h", 3)
	morph.set("_from_edge", FractalTerrainMorphScript.EDGE_SOUTH)
	morph.call("_rebuild_order")
	var order_s: PackedInt32Array = morph.get("_order") as PackedInt32Array
	if int(order_s[0]) != 0 + 2 * 4:
		_fail("FAIL south order starts at %d want 8" % int(order_s[0]))
		morph.queue_free()
		return
	morph.set("_from_edge", FractalTerrainMorphScript.EDGE_NORTH)
	morph.call("_rebuild_order")
	var order_n: PackedInt32Array = morph.get("_order") as PackedInt32Array
	if int(order_n[0]) != 0:
		_fail("FAIL north order starts at %d want 0" % int(order_n[0]))
		morph.queue_free()
		return
	var w := 4
	var h := 4
	var heights := PackedInt32Array()
	var mats := PackedInt32Array()
	heights.resize(w * h)
	mats.resize(w * h)
	for i in range(w * h):
		heights[i] = 1 + (i % 3)
		mats[i] = VoxelMaterial.fractal_band(i % VoxelMaterial.FRACTAL_BAND_COUNT)
	var origin := Vector3i(10, 5, 10)
	await morph.start_from_targets(
		origin, w, h, heights, mats, FractalTerrainMorphScript.EDGE_SOUTH
	)
	if morph.is_running():
		_fail("FAIL morph still running after start_from_targets")
		morph.queue_free()
		return
	for i2 in range(w * h):
		var tgt := int(heights[i2])
		var sx := i2 % w
		var sz := i2 / w
		var sample_z := (h - 1) - sz
		var x := origin.x + sx
		var z := origin.z + sample_z
		for layer in range(1, tgt + 1):
			var got_mat := brush.get_vox(Vector3i(x, origin.y + layer, z))
			if got_mat != int(mats[i2]):
				_fail(
					"FAIL morph column %d layer %d mat %d want %d"
					% [i2, layer, got_mat, int(mats[i2])]
				)
				morph.queue_free()
				return
		var above := brush.get_vox(Vector3i(x, origin.y + tgt + 1, z))
		if above != VoxelMaterial.AIR:
			_fail("FAIL morph left solid above target at col %d" % i2)
			morph.queue_free()
			return
	## Second Create: replace in place — air-clears taller leftovers, no dissolve phase.
	var flat := PackedInt32Array()
	var flat_mats := PackedInt32Array()
	flat.resize(w * h)
	flat_mats.resize(w * h)
	for i3 in range(w * h):
		flat[i3] = 1
		flat_mats[i3] = VoxelMaterial.fractal_band(0)
	var phases2: Array[StringName] = []
	morph.phase_changed.connect(func(p: StringName) -> void: phases2.append(p))
	await morph.start_from_targets(origin, w, h, flat, flat_mats)
	if phases2.has(FractalTerrainMorphScript.PHASE_DISSOLVE):
		_fail("FAIL replace morph still emitted dissolve phase")
		morph.queue_free()
		return
	for i4 in range(w * h):
		var sx2 := i4 % w
		var sz2 := i4 / w
		var sample_z2 := (h - 1) - sz2
		var x2 := origin.x + sx2
		var z2 := origin.z + sample_z2
		if brush.get_vox(Vector3i(x2, origin.y + 2, z2)) != VoxelMaterial.AIR:
			_fail("FAIL replace left tall voxels at col %d" % i4)
			morph.queue_free()
			return
		if brush.get_vox(Vector3i(x2, origin.y, z2)) != VoxelMaterial.FRACTAL_GLOW:
			_fail("FAIL replace did not keep glow deck at col %d" % i4)
			morph.queue_free()
			return
		if brush.get_vox(Vector3i(x2, origin.y + 1, z2)) != VoxelMaterial.fractal_band(0):
			_fail("FAIL replace grow missing stub at col %d" % i4)
			morph.queue_free()
			return
	## Instant path finishes without dissolve and sets heights in one batch.
	var tall := PackedInt32Array()
	var tall_mats := PackedInt32Array()
	tall.resize(w * h)
	tall_mats.resize(w * h)
	for i5 in range(w * h):
		tall[i5] = 3
		tall_mats[i5] = VoxelMaterial.fractal_band(2)
	await morph.start_from_targets(
		origin, w, h, tall, tall_mats, FractalTerrainMorphScript.EDGE_SOUTH, true
	)
	if morph.is_running() or morph.is_instant():
		_fail("FAIL instant morph still marked running/instant")
		morph.queue_free()
		return
	if brush.get_vox(Vector3i(origin.x, origin.y + 3, origin.z + (h - 1))) != VoxelMaterial.fractal_band(2):
		_fail("FAIL instant morph missing tall pillar")
		morph.queue_free()
		return
	morph.queue_free()


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
