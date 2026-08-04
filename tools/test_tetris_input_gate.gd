## Proves the arcade cabinet stops taking keys while a panel owns the screen.
##
## Keys 1–4 used to be gated on the cabinet's own state alone, so a piece could be walked
## across the board from behind an open inventory, settings panel or character editor. The gate
## is UiInputGate over the walker's is_blocking_ui_open(), and the only way to know it is wired
## is to press the keys: a real cabinet is stamped into a real voxel world here, a real walker
## opens a real modal over it, and the events go in through the viewport the way a player's do.
##
## Keys 1, 3 and 4 are judged by the board — the piece column and the soft-drop latch. Key 2 is
## only observable when the active tetromino actually changes under rotation, which the square
## does not, so it is judged when it can be and reported when it cannot. The held-key case has
## its own check: a panel opening mid-hold swallows the release, and the auto-repeat behind it
## used to keep sliding the piece.
##
## Run: powershell -File tools\run_test.ps1 test_tetris_input_gate
extends Node

const AirGeneratorScript := preload("res://scripts/city/air_generator.gd")
const VoxelBlockLibraryScript := preload("res://scripts/city/voxel_block_library.gd")
const CityBrushScript := preload("res://scripts/city/city_brush.gd")
const TetrisMachineScript := preload("res://scripts/city/tetris_machine.gd")

const VOXEL_SIZE := 0.5
## Cabinet foot in world voxels, high enough that the shell never clamps against bedrock.
const ORIGIN := Vector3i(64, 8, 64)
## The cabinet is 7 m wide and 14 m tall; the bubble has to cover all of it and then some.
const EDIT_BOX := AABB(Vector3(44.0, 0.0, 44.0), Vector3(40.0, 60.0, 40.0))
const EDITABLE_TIMEOUT_FRAMES := 900
## Past DAS_DELAY_SEC plus several repeats at the fixed physics step.
const DAS_FRAMES := 25

var _terrain: VoxelTerrain
var _tool: VoxelTool
var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	await _make_terrain()
	if _failed:
		_finish()
		return
	var walker := await _make_walker()
	var machine := _make_machine(walker)
	if _failed:
		_finish()
		return

	_check_keys_reach_the_board(machine, walker)
	await _check_keys_stop_at_a_modal(machine, walker)
	_check_power_and_new(machine)
	_check_arcade_well_alignment(walker)
	_finish()


func _finish() -> void:
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


## Nothing is open: every cabinet key must do what the label says, or the blocked half below
## proves nothing.
func _check_keys_reach_the_board(machine: TetrisMachine, walker: CityWalker) -> void:
	if UiInputGate.gameplay_blocked(walker):
		_fail("FAIL the gate reports a panel open before anything was opened")
		return
	var start := _column(machine)
	_tap(KEY_1)
	if _column(machine) != start + 1:
		_fail("FAIL key 1 left column %d, expected %d" % [_column(machine), start + 1])
		return
	_tap(KEY_3)
	if _column(machine) != start:
		_fail("FAIL key 3 right column %d, expected %d" % [_column(machine), start])
		return
	if _rotation_shows(machine):
		var spin := _rotation(machine)
		_tap(KEY_2)
		if _rotation(machine) == spin:
			_fail("FAIL key 2 left the piece at rotation %d" % spin)
			return
	else:
		print("note: the square is up, so key 2 has nothing to show — rotation unjudged")
	## Key 4 is left for the far end: its latch holds until the piece locks, so pressing it
	## here would arm the very thing the blocked half has to find switched off.
	print("OK keys 1–3 drive the cabinet with nothing open")


## A modal owns the screen: the same events, pressed the same way, must die at the gate.
func _check_keys_stop_at_a_modal(machine: TetrisMachine, walker: CityWalker) -> void:
	## Held across the opening: the press latches the auto-repeat while the board is still
	## live, and the panel then swallows the release. The repeat used to slide the piece on.
	_press(KEY_1, true)
	var start := _column(machine)
	walker.toggle_character_editor()
	if not walker.is_character_editor_open():
		_fail("FAIL the character editor refused to open, so nothing was tested")
		return
	if not UiInputGate.gameplay_blocked(walker):
		_fail("FAIL the gate reports nothing open with the character editor up")
		return
	await _physics_frames(DAS_FRAMES)
	if _column(machine) != start:
		_fail("FAIL auto-repeat slid the piece to column %d behind the modal" % _column(machine))
		return
	_press(KEY_1, false)

	var spin := _rotation(machine)
	## One key at a time: a leaked 1 followed by a leaked 3 lands back on the start column.
	_tap(KEY_1)
	if _column(machine) != start:
		_fail("FAIL key 1 moved the piece to column %d behind the modal" % _column(machine))
		return
	_tap(KEY_3)
	if _column(machine) != start:
		_fail("FAIL key 3 moved the piece to column %d behind the modal" % _column(machine))
		return
	_tap(KEY_2)
	if _rotation(machine) != spin:
		_fail("FAIL key 2 turned the piece to rotation %d behind the modal" % _rotation(machine))
		return
	if machine.is_soft_dropping():
		_fail("FAIL the soft drop was still latched when the modal opened")
		return
	_tap(KEY_4)
	if machine.is_soft_dropping():
		_fail("FAIL key 4 latched the soft drop behind the modal")
		return
	print("OK keys 1–4 and the held-key repeat all stop at the open modal")

	walker.toggle_character_editor()
	if walker.is_character_editor_open():
		_fail("FAIL the character editor refused to close")
		return
	## The release was swallowed, so a repeat left armed would run the moment the panel goes.
	await _physics_frames(DAS_FRAMES)
	if _column(machine) != start:
		_fail("FAIL the piece slid to column %d as the modal closed" % _column(machine))
		return
	_tap(KEY_4)
	if not machine.is_soft_dropping():
		_fail("FAIL key 4 stayed dead after the modal closed")
		return
	print("OK the cabinet takes keys again once the modal is gone")


func _column(machine: TetrisMachine) -> int:
	var piece := machine.get_active_piece()
	if piece.is_empty():
		_fail("FAIL the cabinet has no active piece to read")
		return -1
	return int(piece["x"])


func _rotation(machine: TetrisMachine) -> int:
	var piece := machine.get_active_piece()
	if piece.is_empty():
		_fail("FAIL the cabinet has no active piece to read")
		return -1
	return int(piece["rot"])


## The square occupies the same four cells at every angle, so pressing rotate on it changes
## nothing a test can see.
func _rotation_shows(machine: TetrisMachine) -> bool:
	var id := int(machine.get_active_piece()["id"])
	return machine.cells_for_piece(id, 0) != machine.cells_for_piece(id, 1)


func _physics_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


func _tap(code: Key) -> void:
	_press(code, true)
	_press(code, false)


func _press(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	get_viewport().push_input(ev)


## Arcade free bay: starts off, refuses keys, toggles back on, and NEW wipes a finished board.
func _check_power_and_new(machine: TetrisMachine) -> void:
	machine.configure_arcade(true)
	if machine.is_powered():
		_fail("FAIL configure_arcade(true) left the cabinet powered")
		return
	if machine.is_playable():
		_fail("FAIL an off cabinet still reports playable")
		return
	var hints := machine.get_node_or_null("ControlHints") as Label3D
	if hints == null or not hints.visible:
		_fail("FAIL free bay has no visible key hints above the score")
		return
	if not str(hints.text).contains("1") or not str(hints.text).contains("4"):
		_fail("FAIL key hints do not list keys 1–4: %s" % hints.text)
		return
	var hud := machine.get_node_or_null("ScoreHud") as Label3D
	if hud == null:
		_fail("FAIL free bay has no ScoreHud")
		return
	if hints.position.y <= hud.position.y + 0.5:
		_fail(
			"FAIL hints at y=%.2f sit on the score at y=%.2f"
			% [hints.position.y, hud.position.y]
		)
		return
	if str(hud.text).contains("\nOFF") or str(hud.text).contains("\nNEW"):
		_fail("FAIL free-bay HUD still carries a third status line: %s" % hud.text)
		return
	var panel := machine.get_node_or_null("ArcadeControls") as Node3D
	if panel == null:
		_fail("FAIL free bay has no ArcadeControls plate")
		return
	if panel.position.x >= -0.5:
		_fail("FAIL controls are not left-aligned (local x=%.2f)" % panel.position.x)
		return
	if absf(panel.position.y - (hud.position.y - 0.36)) > 0.2:
		_fail(
			"FAIL controls y=%.2f are not on the LINES row under score y=%.2f"
			% [panel.position.y, hud.position.y]
		)
		return
	_check_controls_face_the_stand(machine)
	var col_before := _column(machine)
	_tap(KEY_1)
	if _column(machine) != col_before:
		_fail("FAIL key 1 moved a piece on an off cabinet")
		return
	if machine.claim_ai_controller(self):
		_fail("FAIL an off cabinet accepted an AI claim")
		machine.release_ai_controller(self)
		return
	machine.set_powered(true)
	if not machine.is_powered() or not machine.is_playable():
		_fail("FAIL turning the cabinet on did not restore play")
		return
	machine.new_game()
	if machine.get_active_piece().is_empty():
		_fail("FAIL NEW on a powered cabinet left no active piece")
		return
	machine.set_powered(false)
	machine.new_game()
	if machine.is_powered():
		_fail("FAIL NEW powered the cabinet on by itself")
		return
	if not machine.get_active_piece().is_empty():
		_fail("FAIL NEW on an off cabinet left a falling piece for the rules")
		return
	print("OK power toggle and NEW keep an off cabinet quiet and a restart clean")


## The plate is a child of the cabinet. A world yaw passed into `Ui3D.begin` stacks on the
## parent's face and stands the buttons edge-on to the player — assert the face points at
## the stand, which is the only orientation a player at the controls can read.
func _check_controls_face_the_stand(machine: TetrisMachine) -> void:
	var panel := machine.get_node_or_null("ArcadeControls") as Node3D
	if panel == null:
		_fail("FAIL free bay has no ArcadeControls plate")
		return
	var face := -panel.global_transform.basis.z
	var stand := machine.get_stand_world_position() - machine.global_position
	stand.y = 0.0
	if stand.length_squared() < 0.01:
		_fail("FAIL stand is on top of the cabinet origin")
		return
	stand = stand.normalized()
	var align := face.dot(stand)
	if align < 0.9:
		_fail(
			"FAIL controls face %s but the stand is %s (dot %.2f) — plate is sideways"
			% [face, stand, align]
		)
		return
	print("OK controls face the stand (dot %.2f)" % align)


## Arcade cabinets stand on voxel centres and face sideways — that used to floor() the
## GAMEBOY rails one cell off the MultiMesh playfield (gap on one side, flush on the other).
func _check_arcade_well_alignment(walker: CityWalker) -> void:
	var brush: CityBrush = CityBrushScript.new(_tool) as CityBrush
	var machine: TetrisMachine = TetrisMachineScript.new() as TetrisMachine
	machine.name = "ArcadeAlignCabinet"
	add_child(machine)
	## Same footing DistrictInstance._stand_world uses, plus the arcade's east-facing yaw.
	var ground := Vector3(
		(float(ORIGIN.x) + 0.5) * VOXEL_SIZE,
		float(ORIGIN.y) * VOXEL_SIZE,
		(float(ORIGIN.z + 48) + 0.5) * VOXEL_SIZE
	)
	machine.begin(_terrain, _tool, brush, walker, ground, -PI * 0.5, VOXEL_SIZE)
	if machine.is_broken() or not machine.is_playable():
		_fail("FAIL arcade-align cabinet did not come up playable")
		machine.queue_free()
		return
	var c0: Vector3 = machine.cell_local_center(0, 2)
	var c9: Vector3 = machine.cell_local_center(9, 2)
	var span := absf(c9.x - c0.x)
	var want := float(TetrisMachine.COLS - 1) * VOXEL_SIZE
	if absf(span - want) > 0.02:
		_fail("FAIL playfield span %.3f (want %.3f)" % [span, want])
		machine.queue_free()
		return
	## Side rails are one cell outside the first/last column centres.
	var left_rail := _nearest_shell_local_x(machine, c0.x - VOXEL_SIZE, c0.y)
	var right_rail := _nearest_shell_local_x(machine, c9.x + VOXEL_SIZE, c9.y)
	if left_rail == INF or right_rail == INF:
		_fail("FAIL could not find stamped side rails beside the playfield")
		machine.queue_free()
		return
	var left_gap := absf(c0.x - left_rail) - VOXEL_SIZE
	var right_gap := absf(right_rail - c9.x) - VOXEL_SIZE
	if absf(left_gap) > 0.08 or absf(right_gap) > 0.08:
		_fail(
			"FAIL well misaligned with harness (left err %.3f, right err %.3f)"
			% [left_gap, right_gap]
		)
		machine.queue_free()
		return
	if absf(left_gap - right_gap) > 0.08:
		_fail(
			"FAIL asymmetric well gaps left=%.3f right=%.3f"
			% [left_gap, right_gap]
		)
		machine.queue_free()
		return
	print("OK arcade well centres sit one cell inside each stamped rail")
	machine.queue_free()


## Closest owned GAMEBOY voxel centre (machine-local X) near an expected rail column.
func _nearest_shell_local_x(machine: TetrisMachine, expect_x: float, at_y: float) -> float:
	var best := INF
	var best_d := INF
	for vox_v: Variant in machine._owned_voxels.keys():
		var vox: Vector3i = vox_v as Vector3i
		var terrain_local := Vector3(
			float(vox.x) + 0.5, float(vox.y) + 0.5, float(vox.z) + 0.5
		)
		var local: Vector3 = machine.to_local(_terrain.to_global(terrain_local))
		if absf(local.y - at_y) > VOXEL_SIZE:
			continue
		var d := absf(local.x - expect_x)
		if d < best_d:
			best_d = d
			best = local.x
	return best


func _make_machine(walker: CityWalker) -> TetrisMachine:
	var brush: CityBrush = CityBrushScript.new(_tool) as CityBrush
	var machine: TetrisMachine = TetrisMachineScript.new() as TetrisMachine
	machine.name = "TetrisMachine"
	add_child(machine)
	machine.begin(_terrain, _tool, brush, walker, Vector3(ORIGIN) * VOXEL_SIZE, 0.0, VOXEL_SIZE)
	if machine.is_broken():
		_fail("FAIL the cabinet broke while it was being stamped")
		return machine
	if not machine.is_playable():
		_fail("FAIL the cabinet has no playable board after begin()")
	return machine


## A real walker, because it owns the predicate and the character editor the modal half needs.
## Physics is off for the same reason CityRoot holds it off at spawn: there is no ground here.
func _make_walker() -> CityWalker:
	var walker := CityWalker.new()
	walker.name = "Walker"
	add_child(walker)
	walker.set_physics_process(false)
	walker.global_position = Vector3(ORIGIN) * VOXEL_SIZE + Vector3(0.0, 0.0, -6.0)
	await get_tree().process_frame
	await get_tree().process_frame
	return walker


func _make_terrain() -> void:
	_terrain = VoxelTerrain.new()
	_terrain.name = "VoxelTerrain"
	add_child(_terrain)
	_terrain.scale = Vector3(VOXEL_SIZE, VOXEL_SIZE, VOXEL_SIZE)
	var mesher := VoxelMesherBlocky.new()
	mesher.library = VoxelBlockLibraryScript.build()
	_terrain.mesher = mesher
	_terrain.generator = AirGeneratorScript.new()
	_terrain.bounds = AABB(Vector3(-2000, 0, -2000), Vector3(4000, 220, 4000))
	_terrain.max_view_distance = 512
	_terrain.generate_collisions = false
	_tool = _terrain.get_voxel_tool()
	_tool.channel = VoxelBuffer.CHANNEL_TYPE

	var anchor := VoxelViewer.new()
	anchor.name = "EditAnchor"
	anchor.view_distance = 512
	anchor.requires_visuals = false
	anchor.requires_collisions = false
	add_child(anchor)
	anchor.global_position = Vector3(ORIGIN) * VOXEL_SIZE

	for _i in range(EDITABLE_TIMEOUT_FRAMES):
		await get_tree().process_frame
		if _tool.is_area_editable(EDIT_BOX):
			return
	_fail("FAIL area %s never became editable" % EDIT_BOX)
