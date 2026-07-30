## Photographs the elevator floor selector at three shaft heights, because the things
## most likely to be wrong are invisible to geometry asserts: label legibility at hand
## size, the current-floor highlight, and the +Z/−Z mirror that decides whether the
## lowest floors sit on the viewer's left.
##
## Needs a renderer: Label3D and the panel quads never draw headless.
##
## Run: powershell -File tools\run_test.ps1 shot_elevator_panel -Rendered
extends Node

const OUT_DIR := "res://tools/"
const VOXEL_SIZE := 0.5
## Landing counts worth seeing: one column, two columns, and a tall tower keypad.
const CASES: Array[int] = [3, 12, 30]
## Camera standoff — roughly where a player's head is when facing the cabin wall.
const EYE_M := 1.15

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

	for floors in CASES:
		if not await _shoot_case(floors):
			get_tree().quit(1)
			return
	print("RESULT: OK")
	get_tree().quit(0)


func _shoot_case(floors: int) -> bool:
	var ys := PackedInt32Array()
	for f in range(floors):
		## Ground storey is 8 voxels, upper storeys 6 — same as BuildingGrammar.
		ys.append(1 if f == 0 else 8 + (f - 1) * 6)
	var shaft := ElevatorShaft.make(Rect2i(0, 0, 3, 3), ys, Vector2i(0, 1))
	var panel := ElevatorPanel.new()
	_root.add_child(panel)
	## Mid-shaft landing, so the highlight is somewhere a viewer can spot.
	panel.bind_to(shaft, floors / 2, VOXEL_SIZE)
	var at := panel.global_position
	var face := -panel.global_transform.basis.z
	_cam.global_position = at + face * EYE_M
	_cam.look_at(at)
	await _frames(4)
	var path := "%selevator_panel_%02d.png" % [OUT_DIR, floors]
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
		return false
	img.save_png(path)
	print("  %d floors → %s (buttons %d)" % [floors, path, panel.button_count()])
	panel.queue_free()
	await _frames(1)
	return true


func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	## Cabin-dark, so the unshaded panel and its labels carry the frame.
	env.background_color = Color(0.05, 0.05, 0.06, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.78, 1.0)
	env.ambient_light_energy = 1.0
	world_env.environment = env
	_root.add_child(world_env)


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame
