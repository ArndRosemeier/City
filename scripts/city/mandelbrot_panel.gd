## 5×7 m Ui3D: top 5×5 shows a Mandelbrot set; bottom strip has zoom + / − buttons.
##
## Fire on the fractal to place a target marker, then fire "+" to zoom into that
## point. "−" zooms out around the current view centre (no target required).
##
## Always baked at TEX_RES² via NativeMandelbrot on WorkerThreadPool; the main
## thread only applies the finished ImageTexture (stale jobs are dropped).
class_name MandelbrotPanel
extends "res://scripts/city/ui_3d.gd"

signal bake_finished(success: bool)

const PANEL_W := 5.0
const PANEL_H := 7.0
const FRACTAL_H := 5.0
const UI_H := 2.0
const TEX_RES := 1000
const ZOOM_IN := 0.5
const ZOOM_OUT := 2.0
const MAX_SCALE := 3.0
const BTN_ZOOM_IN := &"zoom_in"
const BTN_ZOOM_OUT := &"zoom_out"
const TEX_SHADER_PATH := "res://scripts/city/mandelbrot_tex.gdshader"
const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")

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


func begin(origin: Vector3, face_yaw: float) -> void:
	name = "MandelbrotPanel"
	size_m = Vector2(PANEL_W, PANEL_H)
	show_debug_marker = false
	surface_color = Color(0.08, 0.08, 0.10, 1.0)
	marker_color = Color(1.0, 0.92, 0.2, 1.0)
	clear_buttons()
	var ui_v := UI_H / PANEL_H
	add_button(
		BTN_ZOOM_OUT,
		Rect2(0.08, 0.06, 0.38, ui_v - 0.10),
		"-",
		Color(0.55, 0.18, 0.18, 1.0)
	)
	add_button(
		BTN_ZOOM_IN,
		Rect2(0.54, 0.06, 0.38, ui_v - 0.10),
		"+",
		Color(0.18, 0.55, 0.28, 1.0)
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


func is_baking() -> bool:
	return _baking


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
	_start_bake_job()


func zoom_in_at_target() -> bool:
	if not has_target():
		return false
	view_cx_hp = target_cx_hp
	view_cy_hp = target_cy_hp
	view_scale_hp = _mul_hp(view_scale_hp, str(ZOOM_IN))
	_clamp_scale_hp()
	rebuild_fractal()
	_place_marker(_fractal_uv_to_local(Vector2(0.5, 0.5)))
	return true


func zoom_out() -> void:
	view_scale_hp = _mul_hp(view_scale_hp, str(ZOOM_OUT))
	_clamp_scale_hp()
	rebuild_fractal()


func complex_at_uv(uv: Vector2) -> Vector2:
	var hp := _complex_hp_pair(_fractal_uv(uv))
	return Vector2(float(hp[0]), float(hp[1]))


func _on_button_pressed(button_id: StringName, _uv: Vector2) -> void:
	match button_id:
		BTN_ZOOM_IN:
			if not zoom_in_at_target():
				target_cx_hp = view_cx_hp
				target_cy_hp = view_cy_hp
				target_cx = view_cx
				target_cy = view_cy
				zoom_in_at_target()
		BTN_ZOOM_OUT:
			zoom_out()


func _on_surface_pressed(uv: Vector2, local_point: Vector3, _world: Vector3) -> void:
	if not _uv_in_fractal(uv):
		return
	var hp := _complex_hp_pair(_fractal_uv(uv))
	target_cx_hp = hp[0]
	target_cy_hp = hp[1]
	target_cx = float(hp[0])
	target_cy = float(hp[1])
	_place_marker(local_point)


func _uv_in_fractal(uv: Vector2) -> bool:
	return uv.y >= UI_H / PANEL_H


func _fractal_uv(uv: Vector2) -> Vector2:
	var v0 := UI_H / PANEL_H
	var fy := (uv.y - v0) / maxf(1.0 - v0, 0.001)
	return Vector2(clampf(uv.x, 0.0, 1.0), clampf(fy, 0.0, 1.0))


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
	var v0 := UI_H / PANEL_H
	var uv := Vector2(fuv.x, v0 + fuv.y * (1.0 - v0))
	return _uv_to_local(uv)


func _build_fractal_view() -> void:
	if _fractal_mesh != null and is_instance_valid(_fractal_mesh):
		_fractal_mesh.queue_free()
	_fractal_mesh = MeshInstance3D.new()
	_fractal_mesh.name = "FractalView"
	var quad := QuadMesh.new()
	quad.size = Vector2(PANEL_W, FRACTAL_H)
	_fractal_mesh.mesh = quad
	var tex_shader := load(TEX_SHADER_PATH) as Shader
	_bake_mat = ShaderMaterial.new()
	_bake_mat.shader = tex_shader
	_bake_tex = ImageTexture.new()
	_fractal_mesh.material_override = _bake_mat
	var half := _half_extents()
	var fractal_center_y := -half.y + UI_H + FRACTAL_H * 0.5
	_fractal_mesh.position = Vector3(0.0, fractal_center_y, -0.01)
	add_child(_fractal_mesh)


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
