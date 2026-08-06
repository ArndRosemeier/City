## Siege Quarter look inspection: boots the live city into a Siege tile, stakes a run, and saves the
## views the mode has to survive — the tile from the air with all five stones lit, the Lodestone under
## its four shield arcs, an outer stone with its arc leaving for the centre and its build ring around
## it, a hell gate mouth, and the HUD strip reading the shield down.
##
## This exists because the outer work is the one part of the theme a headless test cannot prove is
## *there*. `test_siege_district` reads the baked block map; play streams the tile, and a write outside
## `DistrictGenerator.open_space_bounds` is dropped silently — the layout still lists the stone, the
## controller still registers a beacon at it, and the player walks out to an empty street.
##
## Run (-Command, not -File: the -File binder flattens a comma list into one argument):
##   powershell -Command "& '.\tools\run_test.ps1' -Scene shot_siege_district -Rendered
##     -GodotArgs @('--spawn-theme=siege','--city-seed=42')"
extends Node

const VOX := 0.5
const EYE := 1.7
## Mid-morning: low enough that the crystals and the arcs read against a lit sky rather than
## against their own glow, high enough that the quarter is not in its own shadow.
const SHOT_HOUR := 9.5
## What the run is staked with. Quartz only, because the pot's contents are not what this looks at.
## How far above the surface the walker is parked. It is only here to keep voxels meshed, but a body
## dropped *at* a base voxel is inside the ground — and CityRoot then reads the tile as underground,
## dims the sun and photographs a lit sky over a black city.
const ANCHOR_LIFT_M := 2.5

var _seed: int = 0
var _city: CityRoot = null
var _hud: CanvasLayer = null
var _walker: Node3D = null


func _ready() -> void:
	var city := CityRoot.new()
	city.city_seed = 42
	add_child(city)
	_city = city

	var deadline := Time.get_ticks_msec() + 120_000
	while city.get_node_or_null("Walker") == null:
		if Time.get_ticks_msec() > deadline:
			push_error("FAIL no walker after 120 s")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	_seed = city.city_seed
	_walker = city.get_node_or_null("Walker") as Node3D
	_hud = city.get_node_or_null("SiegeHud") as CanvasLayer
	_hide_overlays()

	var coord := city.spawn_district_coord
	var theme := DistrictTheme.for_district(city.city_seed, coord)
	print("spawn district %s = %s" % [coord, theme.display_name])
	if theme.id != DistrictTheme.SIEGE:
		push_error("FAIL spawn district is %s, expected Siege" % theme.display_name)
		get_tree().quit(1)
		return

	await _settle(10.0)
	var inst := _spawn_district(city)
	if inst == null:
		push_error("FAIL spawn district instance not loaded")
		get_tree().quit(1)
		return
	var layout: SiegeLayout = inst.generator.get_siege_layout()
	if layout == null:
		push_error("FAIL the streamed Siege district carries no layout")
		get_tree().quit(1)
		return
	print(layout.describe())
	var ctrl := inst.siege_controller
	if ctrl == null:
		push_error("FAIL the streamed Siege district stood up no controller")
		get_tree().quit(1)
		return

	var centre := _at(coord, layout.lodestone_xz, layout.lodestone_base_y)
	var deck := float(layout.deck_y) * VOX
	var lode_eye := centre + Vector3(24.0, deck + EYE + 2.0, 18.0)
	var lode_aim := centre + Vector3(0.0, float(layout.lodestone_height_vox) * VOX * 0.6, 0.0)
	## The resting tile: arcs already up, console standing, mouths dark, no "+" plates yet. This is
	## the first thing a player sees on arrival, and it has to explain the place on its own — four
	## bridges of light into one crystal, from a spot nobody has staked anything at.
	await _shoot(lode_eye, lode_eye, lode_aim, _png("idle"))

	if not _start_run(city, ctrl):
		get_tree().quit(1)
		return
	## Let the beads travel a little, so the arcs read as flowing rather than as static rails.
	await _settle(4.0)
	print(
		"run: %d/%d outer alive, centre shielded=%s, %s"
		% [
			ctrl.outer_stones_alive(),
			layout.outer_stone_count(),
			str(ctrl.centre_shielded()),
			ctrl.next_pressure_label(),
		]
	)

	## The same view mid-run. The arcs are unchanged from the idle frame — during a run they carry the
	## extra meaning "the centre cannot be hurt yet", and the "+" plates and lit mouths are what tell
	## the two states apart.
	await _shoot(lode_eye, lode_eye, lode_aim, _png("lodestone"))

	## Map scale, so all four bridges and the ring of mouth lights are in one frame. Pale and hazy
	## by nature: terrain meshes in detail around the walker and this is shot from 150 m off it, so
	## the city reads as a silhouette. The arcs and the lit mouths are what this frame is for.
	await _shoot(
		centre,
		centre + Vector3(0.0, 150.0, 130.0),
		centre + Vector3(0.0, 30.0, 0.0),
		_png("shield")
	)

	await _shoot_outer_stone(coord, layout, centre)
	await _shoot_hell_gate(coord, layout, ctrl)
	await _shoot_hud(centre, deck)

	print("RESULT: OK")
	get_tree().quit(0)


## One outer stone three-quarters on: the crystal, its arc leaving for the centre, and the build ring
## the composer swept around it. A flank with no pads is a flank that cannot be held.
func _shoot_outer_stone(coord: Vector2i, layout: SiegeLayout, centre: Vector3) -> void:
	var stone := layout.outer_stone_at(0)
	var at := _at(coord, stone.xz, stone.base_y)
	var pads := 0
	for pad: Vector3i in layout.pads:
		var d := Vector2(float(pad.x - stone.xz.x), float(pad.z - stone.xz.y)).length()
		if d <= float(SiegeComposer.OUTER_PAD_RING):
			pads += 1
	print("outer stone 0 at %s, %d build sites within its ring" % [stone.xz, pads])
	## Backed off along the line away from the centre, so the arc runs away from the camera over
	## the city instead of across the frame.
	var away := (at - centre)
	away.y = 0.0
	away = away.normalized()
	var side := Vector3(-away.z, 0.0, away.x)
	## Beside the crystal rather than in it — the stone is solid, and the walker has to stand on
	## ground for the tile to be lit as ground.
	await _shoot(
		at + away * 10.0,
		at + away * 34.0 + side * 22.0 + Vector3(0.0, 16.0, 0.0),
		at + Vector3(0.0, float(stone.height_vox) * VOX * 0.7, 0.0),
		_png("outer_stone")
	)


## A mouth from the ground a body walks out onto: the fence frame, the veil filling it, and the
## forecast light burning behind it. Shot at the gate the *next* wave is weighted toward, so the
## frame is also the tell working.
func _shoot_hell_gate(coord: Vector2i, layout: SiegeLayout, ctrl: SiegeController) -> void:
	var weights := ctrl.next_gate_weights()
	var pick := 0
	for i in range(weights.size()):
		if weights[i] > weights[pick]:
			pick = i
	var gate := layout.hell_gate_at(pick)
	print(
		"hell gate %d is the forecast mouth (weight %.2f, %s)"
		% [pick, weights[pick], ctrl.gate_bearing_label(pick)]
	)
	var at := _at(coord, Vector2i(gate.mouth.x, gate.mouth.z), gate.mouth.y)
	## Out in front of the mouth, off axis, at head height — where the horde arrives.
	var out := Vector3(-float(gate.outward.x), 0.0, -float(gate.outward.y)).normalized()
	var side := Vector3(-out.z, 0.0, out.x)
	await _shoot(
		at + out * 18.0,
		at + out * 18.0 + side * 9.0 + Vector3(0.0, EYE + 3.0, 0.0),
		at + Vector3(0.0, float(SiegeComposer.HELL_GATE_H) * VOX * 0.5, 0.0),
		_png("hell_gate")
	)


## The run strip with the shield readout, which is the only place the four-to-none countdown is a
## number rather than a picture. Shot with the compass up, because the strip names the cardinal the
## next wave comes from and used to sit on top of the rose that gives that word a meaning.
func _shoot_hud(centre: Vector3, deck: float) -> void:
	if _hud == null:
		push_error("FAIL CityRoot stood up no SiegeHud")
		return
	var compass := _city.get_node_or_null("PlayerCompassHud") as CanvasLayer
	if compass == null:
		push_error("FAIL CityRoot stood up no PlayerCompassHud")
		return
	var eye := centre + Vector3(26.0, deck + EYE + 4.0, 26.0)
	_walker.global_position = eye
	await _settle(6.0)
	_hud.visible = true
	compass.visible = true
	await _frame(eye, centre + Vector3(0.0, 14.0, 0.0), _png("hud"))
	_hud.visible = false
	compass.visible = false


func _start_run(_city: CityRoot, ctrl: SiegeController) -> bool:
	if not ctrl.start_run():
		push_error("FAIL the run would not start")
		return false
	return true


func _png(name: String) -> String:
	return "res://tools/siege_%s_s%d.png" % [name, _seed]


## Parks the walker at `anchor` so the voxels there mesh, then frames `target` from `eye`. The two
## are separate because the aerial frames are taken from further out than terrain meshes.
func _shoot(anchor: Vector3, eye: Vector3, target: Vector3, path: String) -> void:
	_walker.global_position = anchor + Vector3(0.0, ANCHOR_LIFT_M, 0.0)
	await _settle(10.0)
	await _frame(eye, target, path)


func _frame(eye: Vector3, target: Vector3, path: String) -> void:
	## Both of these are re-done per frame rather than once at boot. The walker grows meshes as it
	## streams (and this tool parks it in shot after shot), and the day clock is re-pinned because
	## a district reload puts the cycle back — one frame of this set came out at dusk that way.
	_hide_meshes(_walker)
	_pin_the_sun()
	var cam := Camera3D.new()
	cam.position = eye
	cam.fov = 70.0
	cam.far = 4000.0
	add_child(cam)
	cam.look_at(target, Vector3.UP)
	cam.make_current()
	await _settle(3.0)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
	else:
		img.save_png(path)
		print("SAVED %s" % path)
	cam.queue_free()


## District-local voxel column + Y → world metres, on the voxel centre.
func _at(coord: Vector2i, column: Vector2i, y: int) -> Vector3:
	var origin := DistrictCoord.origin_world(coord, VOX)
	return origin + Vector3(
		(float(column.x) + 0.5) * VOX, float(y) * VOX, (float(column.y) + 0.5) * VOX
	)


func _spawn_district(city: CityRoot) -> DistrictInstance:
	var want := city.spawn_district_coord
	var districts: Array = city._streamer.call("get_loaded_districts") as Array
	for entry: Variant in districts:
		var di: DistrictInstance = entry
		if di.coord == want and di.generator != null:
			return di
	return null


## A full day is 420 s and this tool spends minutes settling, so left alone the later frames drift
## into the dark. Stretching the day past the run and pinning the hour freezes the sun.
func _pin_the_sun() -> void:
	var cycle := _city.get_node_or_null("DayNightCycle")
	if cycle == null:
		push_error("FAIL no DayNightCycle to pin the sun with")
		return
	cycle.set("day_length_sec", 1_000_000.0)
	cycle.call("set_hour", SHOT_HOUR)


## Every HUD band sits in front of the camera, and the error popup opens over whatever it likes —
## streaming a fresh district is exactly when a missing texture is asked for again.
func _hide_overlays() -> void:
	for child: Node in _city.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
	var errors := get_node_or_null("/root/ErrorOverlay")
	assert(errors is CanvasLayer, "the ErrorOverlay autoload is what covers the frame")
	(errors as CanvasLayer).visible = false


func _hide_meshes(node: Node) -> void:
	for child: Node in node.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).visible = false
		_hide_meshes(child)


func _settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
