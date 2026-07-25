## Headless smoke: spiral + cylinder + L mass paint without crashing.
## Run: Godot --headless --path . -s res://tools/test_eccentric_massing.gd
extends SceneTree

const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const BuildingGrammarScript := preload("res://scripts/city/building_grammar.gd")


func _init() -> void:
	var ok := true
	ok = _smoke_theme_weights() and ok
	ok = _smoke_spiral() and ok
	ok = _smoke_cylinder() and ok
	ok = _smoke_l_mass() and ok
	ok = _smoke_wild() and ok
	ok = _smoke_height_report() and ok
	ok = _smoke_impostor_parts() and ok
	ok = _smoke_part_shapes() and ok
	print("RESULT: %s" % ("OK" if ok else "FAILED"))
	quit(0 if ok else 1)


func _smoke_theme_weights() -> bool:
	var core := DistrictTheme.make(DistrictTheme.CORE_HIGHRISE)
	var civic := DistrictTheme.make(DistrictTheme.CIVIC_QUARTER)
	var garden := DistrictTheme.make(DistrictTheme.GARDEN_RESIDENTIAL)
	if core.spiral_chance < 0.1 or civic.spiral_chance < 0.2:
		push_error("FAIL spiral_chance too low on core/civic")
		return false
	if garden.spiral_chance != 0.0:
		push_error("FAIL garden should not spawn spirals")
		return false
	if core.cylinder_chance != 0.0:
		push_error("FAIL core must not use cylinder midrise (keeps skyline)")
		return false
	if core.l_mass_chance <= 0.0 or civic.cylinder_chance <= 0.0:
		push_error("FAIL massing weights missing")
		return false
	print("OK theme weights")
	return true


func _make_grammar(theme: DistrictTheme, max_h: int = 120) -> BuildingGrammar:
	var brush: CityBrush = CityBrushScript.new()
	brush.use_offline_volume()
	var g: BuildingGrammar = BuildingGrammarScript.new()
	g.brush = brush
	g.rng = RandomNumberGenerator.new()
	g.rng.seed = 42
	g.theme = theme
	g.max_height = max_h
	return g


func _count_solid(brush: CityBrush, bmin: Vector3i, bmax: Vector3i) -> int:
	var n := 0
	for y in range(bmin.y, bmax.y):
		for z in range(bmin.z, bmax.z):
			for x in range(bmin.x, bmax.x):
				if int(brush.get_vox(Vector3i(x, y, z))) != VoxelMaterial.AIR:
					n += 1
	return n


func _smoke_spiral() -> bool:
	var g := _make_grammar(DistrictTheme.make(DistrictTheme.CORE_HIGHRISE), 160)
	var bmin := Vector3i(4, 6, 4)
	var bmax := Vector3i(28, 6, 28)
	g.spiral_tower(bmin, bmax, 0, false)
	var solids := _count_solid(g.brush, Vector3i(0, 6, 0), Vector3i(32, 200, 32))
	var top := 0
	for y in range(6, 220):
		for z in range(0, 32):
			for x in range(0, 32):
				if int(g.brush.get_vox(Vector3i(x, y, z))) != VoxelMaterial.AIR:
					top = y
	var height_m := float(top - 6) * 0.5
	if solids < 200 or height_m < 50.0:
		push_error("FAIL spiral_tower too small solids=%d height_m=%.1f" % [solids, height_m])
		return false
	print("OK spiral_tower solids=%d height_m=%.1f" % [solids, height_m])
	return true


func _smoke_cylinder() -> bool:
	var g := _make_grammar(DistrictTheme.make(DistrictTheme.WATERFRONT_INDUSTRIAL), 80)
	g.cylinder_midrise(Vector3i(4, 6, 4), Vector3i(28, 6, 28), 0, false)
	var solids := _count_solid(g.brush, Vector3i(0, 6, 0), Vector3i(32, 80, 32))
	if solids < 80:
		push_error("FAIL cylinder_midrise painted too little (%d)" % solids)
		return false
	print("OK cylinder_midrise solids=%d" % solids)
	return true


func _smoke_l_mass() -> bool:
	var g := _make_grammar(DistrictTheme.make(DistrictTheme.OLD_TOWN), 60)
	g.theme.l_mass_chance = 1.0
	g.midrise_classic(Vector3i(4, 6, 4), Vector3i(28, 6, 28), 0, false)
	var solids := _count_solid(g.brush, Vector3i(0, 6, 0), Vector3i(32, 60, 32))
	if solids < 80:
		push_error("FAIL L-mass midrise painted too little (%d)" % solids)
		return false
	print("OK l_mass midrise solids=%d" % solids)
	return true


## Highest non-air voxel, as voxels above `base_y`. -1 when nothing was painted.
func _measure_height(brush: CityBrush, base_y: int, span: int, ceiling: int) -> int:
	var top := -1
	for y in range(base_y, ceiling):
		for z in range(0, span):
			for x in range(0, span):
				if int(brush.get_vox(Vector3i(x, y, z))) != VoxelMaterial.AIR:
					top = y
					break
	return -1 if top < 0 else top - base_y + 1


func _smoke_wild() -> bool:
	var ok := true
	for spec in [
		["hole_tower", DistrictTheme.CORE_HIGHRISE, 200],
		["arch_gate", DistrictTheme.CIVIC_QUARTER, 140],
		["blob_stack", DistrictTheme.WATERFRONT_INDUSTRIAL, 140],
		["twisted_stack", DistrictTheme.CORE_HIGHRISE, 200],
	]:
		var name := String(spec[0])
		var g := _make_grammar(DistrictTheme.make(int(spec[1])), int(spec[2]))
		var bmin := Vector3i(4, 6, 4)
		var bmax := Vector3i(30, 6, 30)
		if name == "hole_tower":
			g.hole_tower(bmin, bmax, 0, false)
		elif name == "arch_gate":
			g.arch_gate(bmin, bmax, 0)
		elif name == "blob_stack":
			g.blob_stack(bmin, bmax, 0)
		else:
			g.twisted_stack(bmin, bmax, 0)
		var solids := _count_solid(g.brush, Vector3i(0, 6, 0), Vector3i(34, 240, 34))
		var height_m := float(g.built_height_vox) * 0.5
		if solids < 300 or height_m < 12.0:
			push_error(
				"FAIL %s too small solids=%d height_m=%.1f" % [name, solids, height_m]
			)
			ok = false
			continue
		var measured := _measure_height(g.brush, 6, 34, 260)
		if g.built_height_vox > measured + 2:
			push_error(
				"FAIL %s impostor overshoots reported=%d measured=%d"
				% [name, g.built_height_vox, measured]
			)
			ok = false
			continue
		print("OK %s solids=%d height_m=%.1f measured=%d" % [name, solids, height_m, measured])
	## The arch has to leave a walkable void under the span, or it is just a box.
	var ga := _make_grammar(DistrictTheme.make(DistrictTheme.CIVIC_QUARTER), 140)
	ga.arch_gate(Vector3i(4, 6, 4), Vector3i(30, 6, 30), 0)
	var gap := 0
	for z in range(12, 22):
		for x in range(12, 22):
			if int(ga.brush.get_vox(Vector3i(x, 9, z))) == VoxelMaterial.AIR:
				gap += 1
	if gap < 20:
		push_error("FAIL arch_gate has no open passage under the span (air=%d)" % gap)
		ok = false
	else:
		print("OK arch_gate passage air=%d" % gap)
	return ok


## The far-LOD impostor reads `built_height_vox`, so it must match the real voxels.
func _smoke_height_report() -> bool:
	var ok := true
	var zones := [
		LandUse.CORE_LOT, LandUse.MID_LOT, LandUse.CIVIC_LOT, LandUse.TOWN_LOT,
		LandUse.COURTYARD_LOT
	]
	for theme_id in range(DistrictTheme.COUNT):
		for zone in zones:
			for seed in [1, 7, 99]:
				var g := _make_grammar(DistrictTheme.make(theme_id), 160)
				g.rng.seed = seed
				g.build_for_zone(
					Vector3i(4, 6, 4), Vector3i(30, 6, 30), zone, 0, false, false, false
				)
				var measured := _measure_height(g.brush, 6, 34, 260)
				if g.built_height_vox <= 0:
					push_error(
						"FAIL no height reported theme=%d zone=%d seed=%d"
						% [theme_id, zone, seed]
					)
					ok = false
					continue
				if measured < 0:
					push_error(
						"FAIL nothing painted theme=%d zone=%d seed=%d"
						% [theme_id, zone, seed]
					)
					ok = false
					continue
				## Impostors may not overshoot the voxels (that is the LOD bug), and a
				## large undershoot means an archetype forgot to report its spires.
				if g.built_height_vox > measured + 2:
					push_error(
						"FAIL impostor overshoots theme=%d zone=%d seed=%d reported=%d measured=%d"
						% [theme_id, zone, seed, g.built_height_vox, measured]
					)
					ok = false
				elif g.built_height_vox < measured - 8:
					push_error(
						"FAIL impostor undershoots theme=%d zone=%d seed=%d reported=%d measured=%d"
						% [theme_id, zone, seed, g.built_height_vox, measured]
					)
					ok = false
	if ok:
		print("OK built_height_vox matches painted voxels across themes/zones")
	return ok


## Every lot must describe its massing to the far LOD, the parts must agree with the
## voxels, and round / pierced archetypes must not be described as one plain box.
func _smoke_impostor_parts() -> bool:
	var ok := true
	var zones := [
		LandUse.CORE_LOT, LandUse.MID_LOT, LandUse.CIVIC_LOT, LandUse.TOWN_LOT,
		LandUse.COURTYARD_LOT
	]
	var shapes_seen: Dictionary = {}
	for theme_id in range(DistrictTheme.COUNT):
		for zone in zones:
			for seed in [1, 7, 99]:
				var g := _make_grammar(DistrictTheme.make(theme_id), 160)
				g.rng.seed = seed
				var bmin := Vector3i(4, 6, 4)
				var bmax := Vector3i(30, 6, 30)
				g.build_for_zone(bmin, bmax, zone, 0, false, false, false)
				var label := "theme=%d zone=%d seed=%d" % [theme_id, zone, seed]
				if g.impostor_parts.is_empty():
					push_error("FAIL no impostor parts %s" % label)
					ok = false
					continue
				var part_top := -INF
				for part: Dictionary in g.impostor_parts:
					var c: Vector3 = part["center"]
					var s: Vector3 = part["size"]
					shapes_seen[int(part["shape"])] = true
					part_top = maxf(part_top, c.y + s.y * 0.5)
					if s.x < 1.0 or s.y < 1.0 or s.z < 1.0:
						push_error("FAIL degenerate part %s size=%s" % [label, s])
						ok = false
					## Parts must stay on the lot: an overhang would poke a distant shell
					## out over the carriageway where no voxels exist. `size` is in the
					## part's own frame, so yawed parts (pitched roofs, twisted slabs)
					## need their rotated world extent.
					var yaw := float(part["yaw"])
					var ca := absf(cos(yaw))
					var sa := absf(sin(yaw))
					var hx := (ca * s.x + sa * s.z) * 0.5
					var hz := (sa * s.x + ca * s.z) * 0.5
					if c.x - hx < float(bmin.x) - 2.0 or c.x + hx > float(bmax.x) + 2.0:
						push_error("FAIL part outside lot in X %s center=%s half=%.1f" % [label, c, hx])
						ok = false
					if c.z - hz < float(bmin.z) - 2.0 or c.z + hz > float(bmax.z) + 2.0:
						push_error("FAIL part outside lot in Z %s center=%s half=%.1f" % [label, c, hz])
						ok = false
				var measured := _measure_height(g.brush, 6, 34, 260)
				var part_h := int(part_top) - 6
				if part_h > measured + 2:
					push_error(
						"FAIL parts overshoot voxels %s parts=%d measured=%d"
						% [label, part_h, measured]
					)
					ok = false
	if not shapes_seen.has(BuildingGrammar.ImpostorShape.CYLINDER):
		push_error("FAIL no cylinder impostor parts — round buildings would render as boxes")
		ok = false
	if not shapes_seen.has(BuildingGrammar.ImpostorShape.PRISM):
		push_error("FAIL no prism impostor parts — pitched roofs would render as boxes")
		ok = false
	if ok:
		print("OK impostor parts present, on-lot and within voxel height (%d shapes)" % shapes_seen.size())
	return ok


## Round and pierced archetypes must describe themselves with more than one box.
func _smoke_part_shapes() -> bool:
	var ok := true
	var cases := [
		["spiral_tower", DistrictTheme.CORE_HIGHRISE, BuildingGrammar.ImpostorShape.CYLINDER],
		["cylinder_midrise", DistrictTheme.WATERFRONT_INDUSTRIAL, BuildingGrammar.ImpostorShape.CYLINDER],
		["blob_stack", DistrictTheme.WATERFRONT_INDUSTRIAL, BuildingGrammar.ImpostorShape.SPHERE],
	]
	for spec in cases:
		var name := String(spec[0])
		var g := _make_grammar(DistrictTheme.make(int(spec[1])), 160)
		var bmin := Vector3i(4, 6, 4)
		var bmax := Vector3i(30, 6, 30)
		if name == "spiral_tower":
			g.spiral_tower(bmin, bmax, 0, false)
		elif name == "cylinder_midrise":
			g.cylinder_midrise(bmin, bmax, 0, false)
		else:
			g.blob_stack(bmin, bmax, 0)
		var want := int(spec[2])
		var found := false
		for part: Dictionary in g.impostor_parts:
			if int(part["shape"]) == want:
				found = true
				break
		if not found:
			push_error("FAIL %s emitted no shape %d part" % [name, want])
			ok = false
		else:
			print("OK %s describes itself with shape %d (%d parts)" % [name, want, g.impostor_parts.size()])
	## Pitched roofs: one prism per row unit, ridge turned to match the street.
	for facing in [0, 2]:
		var gt := _make_grammar(DistrictTheme.make(DistrictTheme.GARDEN_RESIDENTIAL), 60)
		gt.theme.l_mass_chance = 0.0
		gt.townhouse_row(Vector3i(4, 6, 4), Vector3i(30, 6, 30), facing)
		var prisms := 0
		for part: Dictionary in gt.impostor_parts:
			if int(part["shape"]) != BuildingGrammar.ImpostorShape.PRISM:
				continue
			prisms += 1
			var want_yaw := 0.0 if facing == 0 else PI * 0.5
			if not is_equal_approx(float(part["yaw"]), want_yaw):
				push_error(
					"FAIL gable ridge misaligned facing=%d yaw=%.2f want=%.2f"
					% [facing, float(part["yaw"]), want_yaw]
				)
				ok = false
		if prisms == 0:
			push_error("FAIL townhouse_row facing=%d emitted no pitched roof prism" % facing)
			ok = false
		else:
			print("OK townhouse_row facing=%d has %d pitched roofs" % [facing, prisms])
	## The arch and the courtyard have to stay hollow: one shell would fill the void.
	for spec2 in [["arch_gate", DistrictTheme.CIVIC_QUARTER], ["courtyard_block", DistrictTheme.OLD_TOWN]]:
		var n2 := String(spec2[0])
		var g2 := _make_grammar(DistrictTheme.make(int(spec2[1])), 140)
		if n2 == "arch_gate":
			g2.arch_gate(Vector3i(4, 6, 4), Vector3i(30, 6, 30), 0)
		else:
			g2.courtyard_block(Vector3i(4, 6, 4), Vector3i(30, 6, 30), 0)
		if g2.impostor_parts.size() < 3:
			push_error("FAIL %s described by %d parts — void would be filled in" % [n2, g2.impostor_parts.size()])
			ok = false
		else:
			print("OK %s keeps its void (%d parts)" % [n2, g2.impostor_parts.size()])
	return ok
