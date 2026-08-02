## Facades mix two glass materials. Only one of them is allowed to lamp at night — and that
## one must glow as a flat pane, not a crawling hash grid.
##
## Building grammar picks GLASS vs GLASS_LIT per punched window (~28% lit). The night flicker
## the player sees on "about half" the panes is the lit material drawing a second on/off
## pattern in the shader. This test pins the split and the flat-lamp contract:
##
##   left   = plain GLASS      (lit_ratio 0) → dark, quiet
##   middle = GLASS_LIT        (lit_ratio > 0) → bright, low grain
##   right  = checkerboard mix → same two materials the grammar actually stamps
##
## Writes tools/glass_lit_flicker.png for eyeballing.
##
## Run: powershell -File tools\run_test.ps1 test_glass_lit_flicker -Rendered
extends Node

const OUT := "res://tools/glass_lit_flicker.png"
## Absolute luminance stddev. A flat lamp stays low; the old on/off hash grid was ~0.2+.
const MAX_LIT_STDDEV := 0.08
const MIN_LIT_MEAN := 0.25
## Moon-lit dark glass still reflects a little; anything brighter is emitting.
const MAX_DARK_MEAN := 0.12

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	var root := Node3D.new()
	add_child(root)
	_build_environment(root)
	VoxelBlockLibrary.set_glass_lit_night_factor(1.0)

	var glass_mat := VoxelBlockLibrary.surface_material(VoxelMaterial.GLASS, false)
	var lit_mat := VoxelBlockLibrary.surface_material(VoxelMaterial.GLASS_LIT, false)
	_assert_material_split(glass_mat, lit_mat)

	_add_panel(root, Vector3(-3.2, 1.6, 0.0), glass_mat)
	_add_panel(root, Vector3(0.0, 1.6, 0.0), lit_mat)
	_add_checker_panel(root, Vector3(3.2, 1.6, 0.0), glass_mat, lit_mat)
	_add_labels(root)

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.fov = 40.0
	cam.global_position = Vector3(0.0, 1.6, 6.2)
	cam.look_at(Vector3(0.0, 1.6, 0.0))

	await get_tree().create_timer(1.0).timeout
	var img := get_viewport().get_texture().get_image()
	if img == null:
		_fail("FAIL no viewport image")
		_finish()
		return
	img.save_png(OUT)
	print("GLASS_LIT_FLICKER wrote %s" % OUT)

	## Three equal horizontal bands across the middle of the frame (left / centre / right).
	var band := _panel_bands(img)
	_assert_roi("GLASS", img, band[0], true)
	_assert_roi("GLASS_LIT", img, band[1], false)
	_finish()


func _assert_material_split(glass_mat: ShaderMaterial, lit_mat: ShaderMaterial) -> void:
	if glass_mat == lit_mat:
		_fail("FAIL GLASS and GLASS_LIT share one ShaderMaterial — night params cannot differ")
		return
	var glass_ratio := float(glass_mat.get_shader_parameter("lit_ratio"))
	var lit_ratio := float(lit_mat.get_shader_parameter("lit_ratio"))
	if glass_ratio > 0.001:
		_fail("FAIL plain GLASS lit_ratio is %.3f, want 0 (must stay dark at night)" % glass_ratio)
	if lit_ratio < 0.05:
		_fail("FAIL GLASS_LIT lit_ratio is %.3f, want a lit material" % lit_ratio)
	print(
		"OK materials split: GLASS lit_ratio=%.2f, GLASS_LIT lit_ratio=%.2f"
		% [glass_ratio, lit_ratio]
	)


## Three horizontal thirds, vertically centred on the panels (skip labels / floor).
func _panel_bands(img: Image) -> Array[Rect2i]:
	var w := img.get_width()
	var h := img.get_height()
	var third := w / 3
	var y0 := int(float(h) * 0.22)
	var y1 := int(float(h) * 0.78)
	var pad := third / 6
	return [
		Rect2i(pad, y0, third - pad * 2, y1 - y0),
		Rect2i(third + pad, y0, third - pad * 2, y1 - y0),
		Rect2i(third * 2 + pad, y0, third - pad * 2, y1 - y0),
	]


## Dark panel must stay dark. Lit panel must be bright and flat (no hash grain).
func _assert_roi(label: String, img: Image, roi: Rect2i, expect_dark: bool) -> void:
	var stats := _roi_stats(img, roi)
	print(
		"%s ROI mean=%.4f stddev=%.4f (n=%d) at %s"
		% [label, stats["mean"], stats["stddev"], stats["n"], roi]
	)
	if expect_dark:
		if float(stats["mean"]) > MAX_DARK_MEAN:
			_fail(
				"FAIL %s panel is glowing (mean %.4f > %.4f) — plain GLASS must not lamp"
				% [label, stats["mean"], MAX_DARK_MEAN]
			)
		else:
			print("OK %s panel stays dark (mean %.4f)" % [label, stats["mean"]])
		return
	if float(stats["mean"]) < MIN_LIT_MEAN:
		_fail(
			"FAIL %s panel is too dark (mean %.4f < %.4f) — GLASS_LIT must lamp at night"
			% [label, stats["mean"], MIN_LIT_MEAN]
		)
	if float(stats["stddev"]) > MAX_LIT_STDDEV:
		_fail(
			"FAIL %s panel is grainy (stddev %.4f > %.4f) — lit panes must be flat lamps, not a hash grid"
			% [label, stats["stddev"], MAX_LIT_STDDEV]
		)
	else:
		print("OK %s panel is a flat lamp (stddev %.4f)" % [label, stats["stddev"]])


func _roi_stats(img: Image, roi: Rect2i) -> Dictionary:
	var n := 0
	var sum := 0.0
	var sum_sq := 0.0
	var x1 := mini(roi.position.x + roi.size.x, img.get_width())
	var y1 := mini(roi.position.y + roi.size.y, img.get_height())
	for y in range(maxi(roi.position.y, 0), y1):
		for x in range(maxi(roi.position.x, 0), x1):
			var c := img.get_pixel(x, y)
			var ylin := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			sum += ylin
			sum_sq += ylin * ylin
			n += 1
	if n < 1:
		return {"mean": 0.0, "stddev": 999.0, "n": 0}
	var mean := sum / float(n)
	var variance := maxf(sum_sq / float(n) - mean * mean, 0.0)
	return {"mean": mean, "stddev": sqrt(variance), "n": n}


func _build_environment(root: Node3D) -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.045)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.08, 0.10, 0.16)
	env.ambient_light_energy = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = env
	root.add_child(we)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	moon.light_energy = 0.12
	moon.light_color = Color(0.55, 0.65, 1.0)
	root.add_child(moon)


func _add_panel(root: Node3D, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.6, 3.2, 0.5)
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	root.add_child(mi)


## Same 28%-ish lit mix the facade punch uses, so the shot matches a real building face.
func _add_checker_panel(
	root: Node3D, origin: Vector3, glass_mat: Material, lit_mat: Material
) -> void:
	var holder := Node3D.new()
	holder.position = origin
	root.add_child(holder)
	const CELL := 0.5
	const NX := 5
	const NY := 6
	for iy in range(NY):
		for ix in range(NX):
			var mi := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(CELL, CELL, 0.5)
			mi.mesh = box
			## Match building_grammar: a minority of panes are the lit variant.
			mi.material_override = lit_mat if ((ix * 3 + iy * 5) % 7) < 2 else glass_mat
			mi.position = Vector3(
				(float(ix) - float(NX - 1) * 0.5) * CELL,
				(float(iy) - float(NY - 1) * 0.5) * CELL,
				0.0
			)
			holder.add_child(mi)


func _add_labels(root: Node3D) -> void:
	_label(root, Vector3(-3.2, 3.55, 0.0), "GLASS (dark)")
	_label(root, Vector3(0.0, 3.55, 0.0), "GLASS_LIT (lamp)")
	_label(root, Vector3(3.2, 3.55, 0.0), "mix like facade")


func _label(root: Node3D, pos: Vector3, text: String) -> void:
	var n := Label3D.new()
	n.text = text
	n.font_size = 48
	n.modulate = Color(0.95, 0.92, 0.85)
	n.position = pos
	n.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(n)


func _finish() -> void:
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)
