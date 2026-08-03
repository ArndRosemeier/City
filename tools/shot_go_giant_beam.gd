## Photographs the giant-board stone-placement beam at the phases that matter, without
## waiting for a match: violet mid-descent beside yellow at the moment of impact.
##
## Needs a renderer: the beam is additive geometry and never draws headless.
##
## Run: powershell -File tools\run_test.ps1 shot_go_giant_beam -Rendered
extends Node

const GoGiantBeamScript := preload("res://scripts/city/go_giant_beam.gd")

const OUT_PAIR := "res://tools/go_giant_beam_pair.png"
const OUT_IMPACT := "res://tools/go_giant_beam_impact.png"

## Matches the district: giant_cell_vox 4 at voxel_size 0.5.
const CELL_M := 2.0
const BOARD_SPAN_M := 36.0

var _root: Node3D = null
var _cam: Camera3D = null


func _ready() -> void:
	_root = Node3D.new()
	_root.name = "Stage"
	add_child(_root)
	_build_environment()
	_cam = Camera3D.new()
	_root.add_child(_cam)
	_cam.current = true

	if not await _shoot_pair():
		get_tree().quit(1)
		return
	if not await _shoot_impact():
		get_tree().quit(1)
		return

	print("RESULT: OK")
	get_tree().quit(0)


## Both colours in one frame: White's beam has already landed, Black's is still falling.
func _shoot_pair() -> bool:
	_cam.fov = 55.0
	_cam.global_position = Vector3(0.0, 17.0, 34.0)
	_cam.look_at(Vector3(0.0, 6.0, 0.0), Vector3.UP)

	var yellow := _spawn_beam("BeamWhite")
	var violet := _spawn_beam("BeamBlack")
	yellow.place_at(Vector3(9.0, 0.0, 0.0), false)
	await _seconds(0.26)
	violet.place_at(Vector3(-9.0, 0.0, 0.0), true)
	## Yellow is now past impact, violet is mid-fall.
	await _seconds(0.2)

	var ok := _grab(OUT_PAIR)
	yellow.cancel()
	violet.cancel()
	yellow.queue_free()
	violet.queue_free()
	await _seconds(0.05)
	return ok


## Close on the contact splash, where the stone is written.
func _shoot_impact() -> bool:
	_cam.fov = 50.0
	_cam.global_position = Vector3(7.0, 6.5, 13.0)
	_cam.look_at(Vector3(0.0, 3.0, 0.0), Vector3.UP)

	var violet := _spawn_beam("BeamImpact")
	violet.place_at(Vector3.ZERO, true)
	## Drop is 0.42 s; a beat past that is the brightest part of the flash.
	await _seconds(0.5)

	var ok := _grab(OUT_IMPACT)
	violet.cancel()
	violet.queue_free()
	await _seconds(0.05)
	return ok


func _spawn_beam(beam_name: String) -> GoGiantBeam:
	var beam: GoGiantBeam = GoGiantBeamScript.new() as GoGiantBeam
	beam.name = beam_name
	_root.add_child(beam)
	beam.configure(CELL_M)
	return beam


func _grab(path: String) -> bool:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
		return false
	var err := img.save_png(path)
	if err != OK:
		push_error("FAIL save_png %s → %s" % [path, error_string(err)])
		return false
	print("  wrote %s" % path)
	return true


func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.05, 0.07, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.66, 1.0)
	## Dim, so the additive beam reads the way it does under the district's night sky.
	env.ambient_light_energy = 0.55
	env.glow_enabled = true
	env.glow_intensity = 0.9
	world_env.environment = env
	_root.add_child(world_env)

	var field := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(BOARD_SPAN_M, 1.0, BOARD_SPAN_M)
	field.mesh = slab
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _grid_texture()
	mat.albedo_color = Color.WHITE
	mat.uv1_scale = Vector3.ONE
	field.material_override = mat
	field.position = Vector3(0.0, -0.5, 0.0)
	_root.add_child(field)

	## A few placed stones for scale, on the crossings either beam will hit.
	for spot: Vector3 in [Vector3(-9.0, 0.0, 6.0), Vector3(9.0, 0.0, -6.0), Vector3(-3.0, 0.0, -4.0)]:
		var stone := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(CELL_M * 0.8, CELL_M * 0.5, CELL_M * 0.8)
		stone.mesh = box
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.1, 0.1, 0.12) if spot.x < 0.0 else Color(0.88, 0.88, 0.85)
		stone.material_override = smat
		stone.position = spot + Vector3(0.0, CELL_M * 0.25, 0.0)
		_root.add_child(stone)


## Gravel field with timber lines, at the giant board's spacing.
func _grid_texture() -> ImageTexture:
	var px := 512
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.55, 0.54, 0.5, 1.0))
	var cells := int(round(BOARD_SPAN_M / CELL_M))
	var ink := Color(0.3, 0.22, 0.14, 1.0)
	for i in range(cells + 1):
		var c := clampi(int(round(float(i) / float(cells) * float(px - 1))), 0, px - 1)
		for k in range(px):
			img.set_pixel(c, k, ink)
			img.set_pixel(k, c, ink)
	return ImageTexture.create_from_image(img)


func _seconds(t: float) -> void:
	await get_tree().create_timer(t).timeout
