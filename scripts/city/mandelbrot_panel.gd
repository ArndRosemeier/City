## 9×5 m Ui3D: 5×5 Mandelbrot + 4 m control column.
##
## Ui3D quads face +Z while the readable side is −Z, which mirrors X for the
## viewer — so the control column is authored on the high-UV (+X) side and
## appears on the viewer's left, with the fractal on their right.
##
## Fire on the fractal to place a target marker, then fire "+" to zoom into that
## point. "−" zooms out around the current view centre (no target required).
## "Create" asks the arena to morph the glow plaza into the current zoom.
## "Instant" runs Create behind a wait splash at full speed.
## "Clear" rebuilds the district (wait splash) so the plaza is pristine again.
##
## Each panel also carries one curated lock-on spot: a marker on the default view.
## Fire the marker to autozoom into that postcard; Create without further zooming
## is what earns the peak recipe (see MandelbrotArena).
##
## Always baked at TEX_RES² via NativeMandelbrot on WorkerThreadPool; the main
## thread only applies the finished ImageTexture (stale jobs are dropped).
class_name MandelbrotPanel
extends "res://scripts/city/ui_3d.gd"

signal bake_finished(success: bool)
signal create_requested(cx_hp: String, cy_hp: String, scale_hp: String)
signal clear_requested()
signal instant_changed(enabled: bool)
## Fired when a lock-on autozoom lands on the curated postcard.
signal lock_engaged()

const PANEL_W := 9.0
const PANEL_H := 5.0
const FRACTAL_W := 5.0
const FRACTAL_H := 5.0
const UI_W := 4.0
const TEX_RES := 1000
const ZOOM_IN := 0.5
const ZOOM_OUT := 2.0
const MAX_SCALE := 3.0
const BTN_ZOOM_IN := &"zoom_in"
const BTN_ZOOM_OUT := &"zoom_out"
const BTN_CREATE := &"create"
const BTN_CLEAR := &"clear"
const BTN_INSTANT := &"instant"
const TEX_SHADER_PATH := "res://scripts/city/mandelbrot_tex.gdshader"
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")
const INSTANT_OFF_COLOR := Color(0.28, 0.28, 0.32, 1.0)
const INSTANT_ON_COLOR := Color(0.16, 0.52, 0.42, 1.0)
## Lock marker on the default view — cyan so it reads apart from the gold target.
const LOCK_MARKER_COLOR := Color(0.25, 0.95, 1.0, 1.0)
const LOCK_MARKER_M := 0.28
## Fractal-UV hit radius for the lock marker (panel is 5×5 m of fractal).
const LOCK_HIT_UV := 0.045
## Relative scale equality for "still on the locked postcard".
const LOCK_SCALE_EPS := 1e-4

## High-precision view state (decimal strings). Float mirrors are approx only.
var view_cx_hp: String = "-0.5"
var view_cy_hp: String = "0"
var view_scale_hp: String = "1.5"
var target_cx_hp: String = ""
var target_cy_hp: String = ""

var view_cx: float = -0.5
var view_cy: float = 0.0
var view_scale: float = 1.5
var target_cx: float = INF
var target_cy: float = INF

var _fractal_mesh: MeshInstance3D = null
var _bake_mat: ShaderMaterial = null
var _bake_tex: ImageTexture = null
var _native: Object = null
## Bumped on every rebuild; worker results with an older gen are discarded.
var _bake_gen: int = 0
var _baking: bool = false
var _instant: bool = true
var _instant_rect: Rect2 = Rect2()

## Curated postcard this panel offers. Empty until the arena assigns one.
var _lock_cx_hp: String = ""
var _lock_cy_hp: String = ""
var _lock_scale_hp: String = ""
var _lock_fuv: Vector2 = Vector2.INF
var _lock_marker: MeshInstance3D = null
## True after autozoom until the player zooms / retargets away from the postcard.
var _lock_active: bool = false
## Edge index 0..3 for recipe site ids (south/north/west/east spawn order).
var lock_edge_index: int = -1


func begin(origin: Vector3, face_yaw: float) -> void:
	name = "MandelbrotPanel"
	size_m = Vector2(PANEL_W, PANEL_H)
	show_debug_marker = false
	surface_color = Color(0.08, 0.08, 0.10, 1.0)
	marker_color = Color(1.0, 0.92, 0.2, 1.0)
	clear_buttons()
	## Control column on +X (high UV) → viewer's left after the +Z/−Z mirror.
	var col0 := FRACTAL_W / PANEL_W
	var pad := 0.02
	var col_w := (1.0 - col0) - 2.0 * pad
	var half_w := (col_w - pad) * 0.5
	var x0 := col0 + pad
	## Top → bottom: Instant, −/+, Create, Clear (Create/Clear full width — no label clash).
	_instant_rect = Rect2(x0, 0.78, col_w, 0.16)
	add_button(
		BTN_INSTANT,
		_instant_rect,
		_instant_label(),
		_instant_color()
	)
	add_button(
		BTN_ZOOM_OUT,
		Rect2(x0, 0.56, half_w, 0.16),
		"-",
		Color(0.55, 0.18, 0.18, 1.0)
	)
	add_button(
		BTN_ZOOM_IN,
		Rect2(x0 + half_w + pad, 0.56, half_w, 0.16),
		"+",
		Color(0.18, 0.55, 0.28, 1.0)
	)
	add_button(
		BTN_CREATE,
		Rect2(x0, 0.32, col_w, 0.18),
		"Create",
		Color(0.18, 0.38, 0.72, 1.0)
	)
	add_button(
		BTN_CLEAR,
		Rect2(x0, 0.08, col_w, 0.18),
		"Clear",
		Color(0.55, 0.22, 0.18, 1.0)
	)
	super.begin(origin, face_yaw)
	if not button_pressed.is_connected(_on_button_pressed):
		button_pressed.connect(_on_button_pressed)
	if not surface_pressed.is_connected(_on_surface_pressed):
		surface_pressed.connect(_on_surface_pressed)
	_ensure_native()
	_build_fractal_view()
	rebuild_fractal()


func has_target() -> bool:
	return not target_cx_hp.is_empty() and not target_cy_hp.is_empty()


func clear_target() -> void:
	target_cx_hp = ""
	target_cy_hp = ""
	target_cx = INF
	target_cy = INF
	clear_marker()


func bake_resolution() -> int:
	return TEX_RES


func bake_texture_size() -> Vector2i:
	if _bake_tex == null:
		return Vector2i.ZERO
	return Vector2i(_bake_tex.get_width(), _bake_tex.get_height())


func bake_texture() -> Texture2D:
	return _bake_tex


func is_baking() -> bool:
	return _baking


func instant_mode() -> bool:
	return _instant


func set_instant_mode(enabled: bool) -> void:
	if _instant == enabled:
		return
	_instant = enabled
	_refresh_instant_button()
	instant_changed.emit(_instant)


## Await until the latest bake finishes (or timeout). For tests / tools.
func wait_bake_finished(timeout_sec: float = 30.0) -> bool:
	if not _baking and bake_texture_size() == Vector2i(TEX_RES, TEX_RES):
		return true
	var deadline := Time.get_ticks_msec() + int(timeout_sec * 1000.0)
	while _baking and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return bake_texture_size() == Vector2i(TEX_RES, TEX_RES)


func rebuild_fractal() -> void:
	_sync_float_mirrors()
	_refresh_lock_marker()
	_start_bake_job()


func zoom_in_at_target() -> bool:
	if not has_target():
		return false
	_break_lock()
	view_cx_hp = target_cx_hp
	view_cy_hp = target_cy_hp
	view_scale_hp = _mul_hp(view_scale_hp, str(ZOOM_IN))
	_clamp_scale_hp()
	rebuild_fractal()
	_place_marker(_fractal_uv_to_local(Vector2(0.5, 0.5)))
	return true


func zoom_out() -> void:
	_break_lock()
	view_scale_hp = _mul_hp(view_scale_hp, str(ZOOM_OUT))
	_clamp_scale_hp()
	rebuild_fractal()


func complex_at_uv(uv: Vector2) -> Vector2:
	var hp := _complex_hp_pair(_fractal_uv(uv))
	return Vector2(float(hp[0]), float(hp[1]))


## Assign the curated postcard this panel marks on its default view.
func assign_lock_spot(spot: Dictionary, edge_index: int) -> void:
	_lock_cx_hp = str(spot.get("cx", ""))
	_lock_cy_hp = str(spot.get("cy", ""))
	_lock_scale_hp = str(spot.get("scale", ""))
	lock_edge_index = edge_index
	_lock_active = false
	if _lock_cx_hp.is_empty() or _lock_cy_hp.is_empty() or _lock_scale_hp.is_empty():
		push_error("MandelbrotPanel.assign_lock_spot: incomplete spot %s" % str(spot))
		_clear_lock_marker()
		return
	_lock_fuv = MandelbrotSpots.default_view_uv(_lock_cx_hp, _lock_cy_hp)
	_refresh_lock_marker()


func has_lock_spot() -> bool:
	return not _lock_cx_hp.is_empty() and not _lock_cy_hp.is_empty() and not _lock_scale_hp.is_empty()


## True when the view still matches the curated postcard after lock-on autozoom.
func is_lock_active() -> bool:
	return _lock_active and _view_matches_lock()


func lock_spot() -> Dictionary:
	if not has_lock_spot():
		return {}
	return {"cx": _lock_cx_hp, "cy": _lock_cy_hp, "scale": _lock_scale_hp}


## Jump straight to the curated postcard. Plays as the lock-on; further +/− clears it.
func engage_lock() -> bool:
	if not has_lock_spot():
		return false
	view_cx_hp = _lock_cx_hp
	view_cy_hp = _lock_cy_hp
	view_scale_hp = _lock_scale_hp
	_clamp_scale_hp()
	target_cx_hp = _lock_cx_hp
	target_cy_hp = _lock_cy_hp
	target_cx = float(_lock_cx_hp)
	target_cy = float(_lock_cy_hp)
	_lock_active = true
	rebuild_fractal()
	_place_marker(_fractal_uv_to_local(Vector2(0.5, 0.5)))
	_hide_lock_marker()
	lock_engaged.emit()
	return true


func _on_button_pressed(button_id: StringName, _uv: Vector2) -> void:
	match button_id:
		BTN_INSTANT:
			set_instant_mode(not _instant)
		BTN_ZOOM_IN:
			if not zoom_in_at_target():
				target_cx_hp = view_cx_hp
				target_cy_hp = view_cy_hp
				target_cx = view_cx
				target_cy = view_cy
				zoom_in_at_target()
		BTN_ZOOM_OUT:
			zoom_out()
		BTN_CREATE:
			create_requested.emit(view_cx_hp, view_cy_hp, view_scale_hp)
		BTN_CLEAR:
			clear_requested.emit()


func _on_surface_pressed(uv: Vector2, local_point: Vector3, _world: Vector3) -> void:
	if not _uv_in_fractal(uv):
		return
	var fuv := _fractal_uv(uv)
	## Lock marker only lives on the default overview — once zoomed, a surface press is a target.
	if (
		has_lock_spot()
		and not _lock_active
		and _is_default_overview()
		and _lock_fuv.distance_to(fuv) <= LOCK_HIT_UV
	):
		engage_lock()
		return
	_break_lock()
	var hp := _complex_hp_pair(fuv)
	target_cx_hp = hp[0]
	target_cy_hp = hp[1]
	target_cx = float(hp[0])
	target_cy = float(hp[1])
	_place_marker(local_point)


func _uv_in_fractal(uv: Vector2) -> bool:
	return uv.x < FRACTAL_W / PANEL_W


func _fractal_uv(uv: Vector2) -> Vector2:
	var u1 := FRACTAL_W / PANEL_W
	var fx := uv.x / maxf(u1, 0.001)
	return Vector2(clampf(fx, 0.0, 1.0), clampf(uv.y, 0.0, 1.0))


func _complex_hp_pair(fuv: Vector2) -> PackedStringArray:
	_ensure_native()
	if _native != null and _native.has_method("complex_at_uv"):
		var d: Dictionary = _native.call(
			"complex_at_uv", view_cx_hp, view_cy_hp, view_scale_hp, fuv.x, fuv.y
		)
		var out := PackedStringArray()
		out.append(str(d.get("re", view_cx_hp)))
		out.append(str(d.get("im", view_cy_hp)))
		return out
	var half := view_scale
	var re := view_cx + (fuv.x - 0.5) * 2.0 * half
	var im := view_cy + (fuv.y - 0.5) * 2.0 * half
	var out2 := PackedStringArray()
	out2.append("%.17g" % re)
	out2.append("%.17g" % im)
	return out2


func _fractal_uv_to_local(fuv: Vector2) -> Vector3:
	var u1 := FRACTAL_W / PANEL_W
	var uv := Vector2(fuv.x * u1, fuv.y)
	return _uv_to_local(uv)


func _build_fractal_view() -> void:
	if _fractal_mesh != null and is_instance_valid(_fractal_mesh):
		_fractal_mesh.queue_free()
	_fractal_mesh = MeshInstance3D.new()
	_fractal_mesh.name = "FractalView"
	var quad := QuadMesh.new()
	quad.size = Vector2(FRACTAL_W, FRACTAL_H)
	_fractal_mesh.mesh = quad
	var tex_shader := load(TEX_SHADER_PATH) as Shader
	_bake_mat = ShaderMaterial.new()
	_bake_mat.shader = tex_shader
	_bake_tex = ImageTexture.new()
	_fractal_mesh.material_override = _bake_mat
	var half := _half_extents()
	## Fractal on −X (low UV) → viewer's right after the +Z/−Z mirror.
	var fractal_center_x := -half.x + FRACTAL_W * 0.5
	_fractal_mesh.position = Vector3(fractal_center_x, 0.0, -0.01)
	add_child(_fractal_mesh)


func _instant_label() -> String:
	return "Instant [x]" if _instant else "Instant [ ]"


func _instant_color() -> Color:
	return INSTANT_ON_COLOR if _instant else INSTANT_OFF_COLOR


func _refresh_instant_button() -> void:
	if _instant_rect.size == Vector2.ZERO:
		return
	add_button(BTN_INSTANT, _instant_rect, _instant_label(), _instant_color())


func _start_bake_job() -> void:
	_bake_gen += 1
	var gen := _bake_gen
	var cx := view_cx_hp
	var cy := view_cy_hp
	var scale := view_scale_hp
	var iters := 256
	_ensure_native()
	if _native != null and _native.has_method("recommended_iters"):
		iters = int(_native.call("recommended_iters", view_scale))
	_baking = true
	## Fire-and-forget coroutine — does not block the caller / main-thread zoom.
	_run_bake_job(gen, cx, cy, scale, iters)


func _run_bake_job(gen: int, cx: String, cy: String, scale: String, iters: int) -> void:
	var want := TEX_RES * TEX_RES * 4
	var mutex := Mutex.new()
	var state := {
		"done": false,
		"ok": false,
		"bytes": PackedByteArray(),
		"error": "",
	}
	var task_id := WorkerThreadPool.add_task(
		func() -> void:
			## Fresh native handle on the worker — do not touch the main-thread instance.
			var eng: Object = ClassDB.instantiate("NativeMandelbrot")
			if eng == null or not eng.has_method("render_rgba8"):
				mutex.lock()
				state["error"] = "NativeMandelbrot unavailable on worker"
				state["done"] = true
				mutex.unlock()
				return
			var bytes: PackedByteArray = eng.call(
				"render_rgba8", cx, cy, scale, TEX_RES, TEX_RES, iters
			) as PackedByteArray
			var colored := false
			if bytes.size() == want:
				var r0 := bytes[0]
				var g0 := bytes[1]
				var b0 := bytes[2]
				var i := 0
				while i + 3 < bytes.size():
					if bytes[i] != r0 or bytes[i + 1] != g0 or bytes[i + 2] != b0:
						colored = true
						break
					i += 4 * 97
			mutex.lock()
			if bytes.size() != want:
				state["error"] = "bake bytes=%d want=%d" % [bytes.size(), want]
			elif not colored:
				state["error"] = "bake flat/black"
			else:
				state["bytes"] = bytes
				state["ok"] = true
			state["done"] = true
			mutex.unlock()
	)
	while true:
		mutex.lock()
		var done: bool = bool(state["done"])
		mutex.unlock()
		if done:
			break
		if not is_inside_tree():
			WorkerThreadPool.wait_for_task_completion(task_id)
			if gen == _bake_gen:
				_baking = false
			return
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task_id)
	mutex.lock()
	var ok: bool = bool(state["ok"])
	var bytes: PackedByteArray = state["bytes"] as PackedByteArray
	var err: String = str(state["error"])
	mutex.unlock()
	if gen != _bake_gen:
		## A newer zoom superseded this job.
		return
	_baking = false
	if not ok:
		push_error("MandelbrotPanel: %s (scale=%s)" % [err, scale])
		bake_finished.emit(false)
		return
	if not _apply_bake_bytes(bytes, iters, scale):
		bake_finished.emit(false)
		return
	bake_finished.emit(true)


func _apply_bake_bytes(bytes: PackedByteArray, iters: int, scale: String) -> bool:
	if _fractal_mesh == null or _bake_mat == null:
		return false
	var img := Image.create_from_data(TEX_RES, TEX_RES, false, Image.FORMAT_RGBA8, bytes)
	if img == null or img.is_empty():
		push_error("MandelbrotPanel: Image.create_from_data failed")
		return false
	if img.get_width() != TEX_RES or img.get_height() != TEX_RES:
		push_error(
			"MandelbrotPanel: image size %dx%d, want %d²"
			% [img.get_width(), img.get_height(), TEX_RES]
		)
		return false
	img.clear_mipmaps()
	_bake_tex = ImageTexture.create_from_image(img)
	if _bake_tex.get_width() != TEX_RES or _bake_tex.get_height() != TEX_RES:
		push_error(
			"MandelbrotPanel: texture size %dx%d, want %d²"
			% [_bake_tex.get_width(), _bake_tex.get_height(), TEX_RES]
		)
		return false
	_bake_mat.set_shader_parameter("bake_tex", _bake_tex)
	_fractal_mesh.material_override = _bake_mat
	print(
		"MandelbrotPanel bake texture=%dx%d iters=%d scale=%s"
		% [_bake_tex.get_width(), _bake_tex.get_height(), iters, scale]
	)
	return true


func _ensure_native() -> void:
	if _native != null and is_instance_valid(_native):
		return
	_native = CityVoxelNativeScript.make_mandelbrot()


func _sync_float_mirrors() -> void:
	_ensure_native()
	if _native != null and _native.has_method("approx_f64"):
		view_cx = float(_native.call("approx_f64", view_cx_hp))
		view_cy = float(_native.call("approx_f64", view_cy_hp))
		view_scale = float(_native.call("approx_f64", view_scale_hp))
	else:
		view_cx = float(view_cx_hp)
		view_cy = float(view_cy_hp)
		view_scale = float(view_scale_hp)


func _mul_hp(a: String, b: String) -> String:
	_ensure_native()
	if _native != null and _native.has_method("mul_decimal"):
		return str(_native.call("mul_decimal", a, b))
	return str(float(a) * float(b))


func _clamp_scale_hp() -> void:
	_ensure_native()
	var s: float
	if _native != null and _native.has_method("approx_f64"):
		s = absf(float(_native.call("approx_f64", view_scale_hp)))
	else:
		s = absf(float(view_scale_hp))
	var min_s := 1e-40
	if _native != null and _native.has_method("min_scale"):
		min_s = float(_native.call("min_scale"))
	if s > MAX_SCALE:
		view_scale_hp = str(MAX_SCALE)
	elif s < min_s:
		view_scale_hp = _mul_hp("1", "%.17e" % min_s)


func _is_default_overview() -> bool:
	return (
		view_cx_hp == "-0.5"
		and view_cy_hp == "0"
		and view_scale_hp == "1.5"
	)


func _view_matches_lock() -> bool:
	if not has_lock_spot():
		return false
	if view_cx_hp != _lock_cx_hp or view_cy_hp != _lock_cy_hp:
		return false
	var a := absf(float(view_scale_hp))
	var b := absf(float(_lock_scale_hp))
	if b <= 0.0:
		return false
	return absf(a - b) / b <= LOCK_SCALE_EPS


func _break_lock() -> void:
	if not _lock_active:
		return
	_lock_active = false
	_refresh_lock_marker()


func _refresh_lock_marker() -> void:
	if not has_lock_spot() or _lock_active or not _is_default_overview():
		_hide_lock_marker()
		return
	_ensure_lock_marker()
	_lock_marker.visible = true
	_lock_marker.position = _fractal_uv_to_local(_lock_fuv) + Vector3(0.0, 0.0, -0.025)


func _hide_lock_marker() -> void:
	if _lock_marker != null and is_instance_valid(_lock_marker):
		_lock_marker.visible = false


func _clear_lock_marker() -> void:
	if _lock_marker != null and is_instance_valid(_lock_marker):
		_lock_marker.queue_free()
	_lock_marker = null


func _ensure_lock_marker() -> void:
	if _lock_marker != null and is_instance_valid(_lock_marker):
		return
	_lock_marker = MeshInstance3D.new()
	_lock_marker.name = "LockMarker"
	var quad := QuadMesh.new()
	quad.size = Vector2(LOCK_MARKER_M, LOCK_MARKER_M)
	_lock_marker.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = LOCK_MARKER_COLOR
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = LOCK_MARKER_COLOR
	mat.emission_energy_multiplier = 2.2
	_lock_marker.material_override = mat
	add_child(_lock_marker)
