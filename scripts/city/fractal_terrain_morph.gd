## Budgeted live morph: bake the current Mandelbrot zoom into a height+colour field,
## then grow the glow-square plaza into a 3D sculpture through CityBrush.
##
## Columns are filled to full height starting at the Create panel's edge so the
## player sees a finished silhouette nearby first; the far side fills later.
## Each Create replaces in place (overwrite + air above) — no dissolve pass.
## Instant mode batches the grow under a wait splash with budgets off.
## Interior (set body) stays at deck height; exterior rises up to MAX_HEIGHT_M.
class_name FractalTerrainMorph
extends Node

signal morph_finished
## &"build" while baking/growing, &"idle" when done/aborted.
## PHASE_DISSOLVE kept for UI/tests that still listen for the name.
signal phase_changed(phase: StringName)

const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")

const PHASE_IDLE := &"idle"
const PHASE_DISSOLVE := &"dissolve"
const PHASE_BUILD := &"build"

const MAX_HEIGHT_M := 50.0
const MAX_GRID := 512
const MORPH_MARGIN_M := 2.5
const BUDGET_MSEC := 3
const BUDGET_MSEC_SOFT := 1
## Hard cap — time alone can miss when many columns are cheap skips or one fill_box is huge.
const MAX_COLS_PER_SLICE := 6
## Matches NativeMandelbrot.mu_interior_u16 / mu_u16_scale.
const MU_INTERIOR_U16 := 0xFFFF
const MU_U16_SCALE := 64.0

const EDGE_SOUTH := &"south"
const EDGE_NORTH := &"north"
const EDGE_WEST := &"west"
const EDGE_EAST := &"east"

var voxel_size: float = 0.5
var _brush_getter: Callable = Callable()
var _glow_min: Vector3 = Vector3.ZERO
var _glow_max: Vector3 = Vector3.ZERO
var _deck_y_vox: int = 0

var _gen: int = 0
var _running: bool = false
var _instant: bool = false
var _grid_w: int = 0
var _grid_h: int = 0
## World voxel footprint (may be larger than sample grid when downsampled).
var _span_w: int = 0
var _span_h: int = 0
var _origin_vox: Vector3i = Vector3i.ZERO
var _target_h: PackedInt32Array = PackedInt32Array()
var _target_mat: PackedInt32Array = PackedInt32Array()
var _current_h: PackedInt32Array = PackedInt32Array()
## Column sample indices, near Create panel first.
var _order: PackedInt32Array = PackedInt32Array()
var _order_i: int = 0
var _from_edge: StringName = EDGE_SOUTH


func configure(
	p_glow_min: Vector3,
	p_glow_max: Vector3,
	p_ground_y_m: float,
	p_voxel_size: float,
	brush_getter: Callable
) -> void:
	_glow_min = p_glow_min
	_glow_max = p_glow_max
	voxel_size = p_voxel_size
	_brush_getter = brush_getter
	## Walkable top of the one-voxel glow deck → deck voxel Y is one below.
	_deck_y_vox = int(floor(p_ground_y_m / voxel_size + 0.001)) - 1


func is_running() -> bool:
	return _running


func is_instant() -> bool:
	return _instant


## Drop any in-flight grow. Next Create starts clean.
func abort() -> void:
	_gen += 1
	_running = false
	_instant = false
	_current_h.clear()
	_target_h.clear()
	_target_mat.clear()
	_order.clear()
	_order_i = 0
	_set_phase(PHASE_IDLE)


## Restart if already running — Create always means "use this zoom".
## `from_edge`: EDGE_SOUTH/NORTH/WEST/EAST — fill full-height columns from that side.
## `instant`: ignore remesh stalls and batch the grow as aggressively as possible.
func start(
	cx_hp: String,
	cy_hp: String,
	scale_hp: String,
	from_edge: StringName = EDGE_SOUTH,
	instant: bool = false
) -> void:
	_gen += 1
	var gen := _gen
	_running = true
	_instant = instant
	_from_edge = from_edge
	_order_i = 0
	_set_phase(PHASE_BUILD)
	await _bake_and_grow(gen, cx_hp, cy_hp, scale_hp)
	if gen != _gen:
		return
	_instant = false
	_set_phase(PHASE_IDLE)


func _set_phase(phase: StringName) -> void:
	phase_changed.emit(phase)


func _bake_and_grow(gen: int, cx_hp: String, cy_hp: String, scale_hp: String) -> void:
	var region := _morph_region()
	if region["w"] <= 0 or region["h"] <= 0:
		push_error("FractalTerrainMorph: empty morph region")
		_running = false
		_set_phase(PHASE_IDLE)
		return
	var prev_origin := _origin_vox
	var prev_span_w := _span_w
	var prev_span_h := _span_h
	var prev_gw := _grid_w
	var prev_gh := _grid_h
	var prev_h := _current_h.duplicate()
	var prev_max := 0
	for i in range(prev_h.size()):
		prev_max = maxi(prev_max, int(prev_h[i]))

	_span_w = int(region["span_w"])
	_span_h = int(region["span_h"])
	_grid_w = int(region["w"])
	_grid_h = int(region["h"])
	_origin_vox = region["origin"] as Vector3i
	var scale_f := float(scale_hp)
	var eng_probe: Object = CityVoxelNativeScript.make_mandelbrot()
	var max_iters := 256
	if eng_probe != null and eng_probe.has_method("approx_f64"):
		scale_f = float(eng_probe.call("approx_f64", scale_hp))
	if eng_probe != null and eng_probe.has_method("recommended_iters"):
		max_iters = int(eng_probe.call("recommended_iters", scale_f))

	var want := _grid_w * _grid_h * 2
	var mutex := Mutex.new()
	var state := {
		"done": false,
		"ok": false,
		"bytes": PackedByteArray(),
		"error": "",
	}
	var gw := _grid_w
	var gh := _grid_h
	var task_id := WorkerThreadPool.add_task(
		func() -> void:
			var eng: Object = ClassDB.instantiate("NativeMandelbrot")
			if eng == null or not eng.has_method("render_smooth_mu_u16"):
				mutex.lock()
				state["error"] = "NativeMandelbrot.render_smooth_mu_u16 unavailable"
				state["done"] = true
				mutex.unlock()
				return
			var bytes: PackedByteArray = eng.call(
				"render_smooth_mu_u16", cx_hp, cy_hp, scale_hp, gw, gh, max_iters
			) as PackedByteArray
			mutex.lock()
			state["bytes"] = bytes
			state["ok"] = bytes.size() == want
			if not state["ok"]:
				state["error"] = "smooth-μ bake size %d want %d" % [bytes.size(), want]
			state["done"] = true
			mutex.unlock()
	)
	while true:
		mutex.lock()
		var done: bool = state["done"]
		mutex.unlock()
		if done:
			break
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task_id)
	if gen != _gen:
		return
	mutex.lock()
	var ok: bool = state["ok"]
	var err: String = str(state["error"])
	var bytes: PackedByteArray = state["bytes"] as PackedByteArray
	mutex.unlock()
	if not ok:
		push_error("FractalTerrainMorph bake failed: %s" % err)
		_running = false
		_set_phase(PHASE_IDLE)
		return

	_build_targets(bytes, max_iters)
	_rebuild_order()
	var same_foot := (
		prev_gw == _grid_w
		and prev_gh == _grid_h
		and prev_span_w == _span_w
		and prev_span_h == _span_h
		and prev_origin == _origin_vox
		and prev_h.size() == _target_h.size()
	)
	if not same_foot and prev_max > 0 and prev_gw > 0 and prev_gh > 0:
		await _clear_footprint(gen, prev_origin, prev_span_w, prev_span_h, prev_gw, prev_gh, prev_h)
		if gen != _gen:
			return
		_current_h.resize(_target_h.size())
		_current_h.fill(0)
	elif same_foot:
		_current_h = prev_h
	else:
		_current_h.resize(_target_h.size())
		_current_h.fill(0)
	_order_i = 0
	await _grow_until_done(gen)
	if gen != _gen:
		return
	_running = false
	print(
		"FractalTerrainMorph done grid=%dx%d max_h=%d edge=%s instant=%s"
		% [_grid_w, _grid_h, _max_target(), str(_from_edge), str(_instant)]
	)
	morph_finished.emit()


func _morph_region() -> Dictionary:
	var min_x := _glow_min.x + MORPH_MARGIN_M
	var max_x := _glow_max.x - MORPH_MARGIN_M
	var min_z := _glow_min.z + MORPH_MARGIN_M
	var max_z := _glow_max.z - MORPH_MARGIN_M
	if max_x <= min_x or max_z <= min_z:
		return {"w": 0, "h": 0, "span_w": 0, "span_h": 0, "origin": Vector3i.ZERO}
	var ox := int(floor(min_x / voxel_size))
	var oz := int(floor(min_z / voxel_size))
	var ex := int(ceil(max_x / voxel_size))
	var ez := int(ceil(max_z / voxel_size))
	var span_w := maxi(1, ex - ox)
	var span_h := maxi(1, ez - oz)
	var w := mini(span_w, MAX_GRID)
	var h := mini(span_h, MAX_GRID)
	return {
		"w": w,
		"h": h,
		"span_w": span_w,
		"span_h": span_h,
		"origin": Vector3i(ox, _deck_y_vox, oz),
	}


func _build_targets(bytes: PackedByteArray, _max_iters: int) -> void:
	var n := _grid_w * _grid_h
	_target_h.resize(n)
	_target_mat.resize(n)
	var max_vox := int(round(MAX_HEIGHT_M / voxel_size))
	var mus := PackedFloat32Array()
	mus.resize(n)
	var mu_min := INF
	var mu_max := -INF
	for i in range(n):
		var packed := int(bytes[i * 2]) | (int(bytes[i * 2 + 1]) << 8)
		if packed == MU_INTERIOR_U16:
			mus[i] = -1.0
			_target_h[i] = 0
			_target_mat[i] = VoxelMaterial.FRACTAL_INTERIOR
			continue
		var mu := float(packed) / MU_U16_SCALE
		mus[i] = mu
		mu_min = minf(mu_min, mu)
		mu_max = maxf(mu_max, mu)
	var span := mu_max - mu_min
	var has_range := is_finite(span) and span > 1e-9
	for i in range(n):
		var mu2: float = mus[i]
		if mu2 < 0.0:
			continue
		## Remap this bake's exterior μ so lowest → 0 m and highest → MAX_HEIGHT_M.
		var t_h := 0.0 if not has_range else clampf((mu2 - mu_min) / span, 0.0, 1.0)
		_target_h[i] = clampi(int(round(t_h * MAX_HEIGHT_M / voxel_size)), 0, max_vox)
		## Colour from height; sqrt packs more hues into low relief (slim peaks share top bands).
		var t_col := sqrt(t_h)
		var bi := clampi(
			int(floor(t_col * float(VoxelMaterial.FRACTAL_BAND_COUNT))),
			0,
			VoxelMaterial.FRACTAL_BAND_COUNT - 1
		)
		_target_mat[i] = VoxelMaterial.fractal_band(bi)


func _rebuild_order() -> void:
	var n := _grid_w * _grid_h
	_order.resize(n)
	var k := 0
	match _from_edge:
		EDGE_NORTH:
			## Near +Z first (sample row 0 / sz=0).
			for sz in range(_grid_h):
				for sx in range(_grid_w):
					_order[k] = sx + sz * _grid_w
					k += 1
		EDGE_WEST:
			## Near −X first (sx=0).
			for sx in range(_grid_w):
				for sz in range(_grid_h):
					_order[k] = sx + sz * _grid_w
					k += 1
		EDGE_EAST:
			## Near +X first (sx = grid_w-1).
			for sx in range(_grid_w - 1, -1, -1):
				for sz in range(_grid_h):
					_order[k] = sx + sz * _grid_w
					k += 1
		_:
			## SOUTH (default): near −Z first (sample_z=0 → sz = grid_h-1).
			for depth in range(_grid_h):
				var sz := (_grid_h - 1) - depth
				for sx in range(_grid_w):
					_order[k] = sx + sz * _grid_w
					k += 1


## One-shot clear of a previous morph footprint when the sample grid changes.
func _clear_footprint(
	gen: int,
	origin: Vector3i,
	span_w: int,
	span_h: int,
	grid_w: int,
	grid_h: int,
	heights: PackedInt32Array
) -> void:
	var brush: CityBrush = _resolve_brush()
	if brush == null:
		push_error("FractalTerrainMorph: no live CityBrush during footprint clear")
		return
	var save_origin := _origin_vox
	var save_span_w := _span_w
	var save_span_h := _span_h
	var save_gw := _grid_w
	var save_gh := _grid_h
	_origin_vox = origin
	_span_w = span_w
	_span_h = span_h
	_grid_w = grid_w
	_grid_h = grid_h
	brush.begin_edit()
	for i in range(mini(heights.size(), grid_w * grid_h)):
		if gen != _gen:
			break
		var cur := int(heights[i])
		var box := _sample_box(i)
		if cur > 0:
			brush.fill_box(
				Vector3i(box.position.x, origin.y + 1, box.position.y),
				Vector3i(box.end.x, origin.y + 1 + cur, box.end.y),
				VoxelMaterial.AIR
			)
		brush.fill_box(
			Vector3i(box.position.x, origin.y, box.position.y),
			Vector3i(box.end.x, origin.y + 1, box.end.y),
			VoxelMaterial.FRACTAL_GLOW
		)
	brush.end_edit()
	_origin_vox = save_origin
	_span_w = save_span_w
	_span_h = save_span_h
	_grid_w = save_gw
	_grid_h = save_gh
	if not _instant:
		await get_tree().process_frame


func _grow_until_done(gen: int) -> void:
	_order_i = 0
	if _instant:
		## One edit batch under the wait splash — no remesh stalls / column caps.
		while _order_i < _order.size():
			if gen != _gen:
				return
			var brush_i: CityBrush = _resolve_brush()
			if brush_i == null:
				push_error("FractalTerrainMorph: no live CityBrush")
				return
			brush_i.begin_edit()
			while _order_i < _order.size():
				_grow_full_column(int(_order[_order_i]), brush_i)
				_order_i += 1
			brush_i.end_edit()
			await get_tree().process_frame
		return
	while _order_i < _order.size():
		if gen != _gen:
			return
		var pressure := CityProfiler.remesh_pressure()
		if pressure >= 2:
			await get_tree().process_frame
			continue
		var brush: CityBrush = _resolve_brush()
		if brush == null:
			push_error("FractalTerrainMorph: no live CityBrush")
			return
		var budget_ms := BUDGET_MSEC_SOFT if pressure >= 1 else BUDGET_MSEC
		var t0 := Time.get_ticks_msec()
		var cols := 0
		brush.begin_edit()
		while _order_i < _order.size():
			_grow_full_column(int(_order[_order_i]), brush)
			_order_i += 1
			cols += 1
			if cols >= MAX_COLS_PER_SLICE or Time.get_ticks_msec() - t0 >= budget_ms:
				break
		brush.end_edit()
		await get_tree().process_frame


## Deck + full pillar for one sample column; air-clears above when shorter than before.
func _grow_full_column(i: int, brush: CityBrush) -> void:
	var box := _sample_box(i)
	var old := int(_current_h[i]) if i < _current_h.size() else 0
	var deck_mat := (
		VoxelMaterial.FRACTAL_INTERIOR
		if int(_target_mat[i]) == VoxelMaterial.FRACTAL_INTERIOR
		else VoxelMaterial.FRACTAL_GLOW
	)
	brush.fill_box(
		Vector3i(box.position.x, _deck_y_vox, box.position.y),
		Vector3i(box.end.x, _deck_y_vox + 1, box.end.y),
		deck_mat
	)
	var tgt := int(_target_h[i])
	if tgt > 0:
		brush.fill_box(
			Vector3i(box.position.x, _deck_y_vox + 1, box.position.y),
			Vector3i(box.end.x, _deck_y_vox + 1 + tgt, box.end.y),
			int(_target_mat[i])
		)
	if old > tgt:
		brush.fill_box(
			Vector3i(box.position.x, _deck_y_vox + 1 + tgt, box.position.y),
			Vector3i(box.end.x, _deck_y_vox + 1 + old, box.end.y),
			VoxelMaterial.AIR
		)
	_current_h[i] = tgt


func _sample_box(i: int) -> Rect2i:
	var sx := i % _grid_w
	var sz := i / _grid_w
	## Top-left sample row 0 → +Z end of the plaza (image v=1).
	var sample_z := (_grid_h - 1) - sz
	var x0 := _origin_vox.x + int(floor(float(sx) * float(_span_w) / float(_grid_w)))
	var x1 := _origin_vox.x + int(floor(float(sx + 1) * float(_span_w) / float(_grid_w)))
	var z0 := _origin_vox.z + int(floor(float(sample_z) * float(_span_h) / float(_grid_h)))
	var z1 := _origin_vox.z + int(floor(float(sample_z + 1) * float(_span_h) / float(_grid_h)))
	x1 = maxi(x1, x0 + 1)
	z1 = maxi(z1, z0 + 1)
	return Rect2i(x0, z0, x1 - x0, z1 - z0)


func _max_target() -> int:
	var m := 0
	for i in range(_target_h.size()):
		m = maxi(m, int(_target_h[i]))
	return m


func _max_current() -> int:
	var m := 0
	for i in range(_current_h.size()):
		m = maxi(m, int(_current_h[i]))
	return m


## World centre of the largest walkable plateau on the finished sculpture: the biggest
## 4-connected block of columns that share one height (> 0). Thin unreachable spires lose to a
## wide shelf even when the shelf is lower. Tie-break: taller plateau, then lower sample index.
## INF when the morph has no exterior relief.
func largest_plateau_world() -> Vector3:
	if _current_h.is_empty() or _grid_w <= 0 or _grid_h <= 0:
		return Vector3(INF, INF, INF)
	var n := _grid_w * _grid_h
	var seen := PackedByteArray()
	seen.resize(n)
	seen.fill(0)
	var best_size := 0
	var best_h := -1
	var best_cells: PackedInt32Array = PackedInt32Array()
	for start in range(n):
		if seen[start] != 0:
			continue
		var h := int(_current_h[start])
		if h <= 0:
			seen[start] = 1
			continue
		var cells := PackedInt32Array()
		var stack: Array[int] = [start]
		seen[start] = 1
		while not stack.is_empty():
			var i: int = stack.pop_back()
			cells.append(i)
			var sx := i % _grid_w
			var sz := i / _grid_w
			var nbs: Array[Vector2i] = [
				Vector2i(sx + 1, sz),
				Vector2i(sx - 1, sz),
				Vector2i(sx, sz + 1),
				Vector2i(sx, sz - 1),
			]
			for nb: Vector2i in nbs:
				if nb.x < 0 or nb.y < 0 or nb.x >= _grid_w or nb.y >= _grid_h:
					continue
				var ni := nb.x + nb.y * _grid_w
				if seen[ni] != 0 or int(_current_h[ni]) != h:
					continue
				seen[ni] = 1
				stack.append(ni)
		var size := cells.size()
		if (
			size > best_size
			or (size == best_size and h > best_h)
			or (size == best_size and h == best_h and cells[0] < best_cells[0])
		):
			best_size = size
			best_h = h
			best_cells = cells
	if best_size <= 0 or best_h <= 0:
		return Vector3(INF, INF, INF)
	## Middle of the plateau: cell closest to the component's sample-centroid.
	var sum_x := 0.0
	var sum_z := 0.0
	for i2 in range(best_cells.size()):
		var ci := int(best_cells[i2])
		sum_x += float(ci % _grid_w)
		sum_z += float(ci / _grid_w)
	var mid_x := sum_x / float(best_cells.size())
	var mid_z := sum_z / float(best_cells.size())
	var best_i := int(best_cells[0])
	var best_d2 := INF
	for i3 in range(best_cells.size()):
		var ci2 := int(best_cells[i3])
		var dx := float(ci2 % _grid_w) - mid_x
		var dz := float(ci2 / _grid_w) - mid_z
		var d2 := dx * dx + dz * dz
		if d2 < best_d2 or (is_equal_approx(d2, best_d2) and ci2 < best_i):
			best_d2 = d2
			best_i = ci2
	var box := _sample_box(best_i)
	var wx := (float(box.position.x) + float(box.end.x)) * 0.5 * voxel_size
	var wz := (float(box.position.y) + float(box.end.y)) * 0.5 * voxel_size
	var wy := (float(_deck_y_vox + 1 + best_h)) * voxel_size
	return Vector3(wx, wy, wz)


func _resolve_brush() -> CityBrush:
	if not _brush_getter.is_valid():
		return null
	var b: Variant = _brush_getter.call()
	return b as CityBrush


## Test helper: decode a smooth-μ bake into target heights/mats (no grow).
func preview_targets_from_mu(
	bytes: PackedByteArray, max_iters: int, grid_w: int, grid_h: int
) -> Dictionary:
	_grid_w = grid_w
	_grid_h = grid_h
	_span_w = grid_w
	_span_h = grid_h
	_build_targets(bytes, max_iters)
	return {"heights": _target_h.duplicate(), "mats": _target_mat.duplicate()}


## Test helper: inject a finished heightfield and grow without native bake.
func start_from_targets(
	origin: Vector3i,
	grid_w: int,
	grid_h: int,
	heights: PackedInt32Array,
	mats: PackedInt32Array,
	from_edge: StringName = EDGE_SOUTH,
	instant: bool = false
) -> void:
	_gen += 1
	var gen := _gen
	_running = true
	_instant = instant
	_from_edge = from_edge
	_origin_vox = origin
	_deck_y_vox = origin.y
	_grid_w = grid_w
	_grid_h = grid_h
	_span_w = grid_w
	_span_h = grid_h
	_target_h = heights.duplicate()
	_target_mat = mats.duplicate()
	if _current_h.size() != _target_h.size():
		_current_h.resize(_target_h.size())
		_current_h.fill(0)
	_rebuild_order()
	_order_i = 0
	_set_phase(PHASE_BUILD)
	await _grow_until_done(gen)
	if gen != _gen:
		return
	_running = false
	_instant = false
	_set_phase(PHASE_IDLE)
	morph_finished.emit()
