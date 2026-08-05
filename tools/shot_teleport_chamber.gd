## Teleport chamber look inspection: boots the live city, finds the spawn tile's chamber and
## photographs it from the street, from the middle of the console ring, and from close enough
## to one console to read the district names off it.
##
## The names are the whole point of the room, and they are Label3D glyphs sized to fit a panel
## about a metre wide. Nothing but a rendered close-up says whether they are legible.
##
## Runs as a scene (not --script) because the city scripts need the CityProfiler autoload:
##
##   powershell -File tools\run_test.ps1 shot_teleport_chamber -Rendered
extends Node

const WORLD_SEED := 42
const EXTERIOR_PNG := "res://tools/teleport_exterior.png"
const RING_PNG := "res://tools/teleport_ring.png"
const CONSOLE_PNG := "res://tools/teleport_console.png"


func _ready() -> void:
	var city := CityRoot.new()
	city.city_seed = WORLD_SEED
	add_child(city)
	var deadline := Time.get_ticks_msec() + 120_000
	while city.get_node_or_null("Walker") == null:
		if Time.get_ticks_msec() > deadline:
			push_error("FAIL no walker after 120 s")
			get_tree().quit(1)
			return
		await get_tree().process_frame
	var walker: Node3D = city.get_node_or_null("Walker")
	await _settle(10.0)

	var district := _spawn_district(city)
	if district == null:
		push_error("FAIL spawn district not loaded")
		get_tree().quit(1)
		return
	var chamber := district.teleport_chamber
	if chamber == null or not is_instance_valid(chamber):
		push_error("FAIL district %s has no teleport chamber" % str(district.coord))
		get_tree().quit(1)
		return
	var pad := chamber.pad()
	var centre := pad.global_position
	print("chamber on %s at %s, %d consoles" % [
		str(district.coord), str(centre), chamber.consoles().size()
	])

	## Terrain only meshes around the walker, so it has to move in before anything is shot —
	## but parked off to one side, or the body fills every interior frame.
	await _goto(walker, centre + Vector3(2.6, 0.0, 2.6))

	## From outside and above, where the beacon column and the open roof are both in frame.
	await _shoot(centre + Vector3(22.0, 18.0, 22.0), centre + Vector3(0.0, 6.0, 0.0), EXTERIOR_PNG)

	## Standing on the pad, looking at the ring the way the player does.
	await _shoot(centre + Vector3(0.0, 1.7, 0.0), centre + Vector3(-3.4, 0.9, -3.4), RING_PNG)

	## One console, close enough that the names have to hold up. Armed first, so the shot also
	## shows what a selected panel looks like against its neighbours.
	var console: TeleportConsole = chamber.consoles()[1]
	var tiles := console.coords()
	if not tiles.is_empty():
		chamber.arm(tiles[0])
	var face := console.global_position
	var inward := (centre - face).normalized()
	await _shoot(face + inward * 1.1 + Vector3(0.0, 0.35, 0.0), face, CONSOLE_PNG)

	print("RESULT: OK")
	get_tree().quit(0)


func _spawn_district(city: CityRoot) -> DistrictInstance:
	var want := city.spawn_district_coord
	var districts: Array = city._streamer.call("get_loaded_districts") as Array
	for inst: Variant in districts:
		var di: DistrictInstance = inst
		if di.coord == want and di.generator != null:
			return di
	return null


func _settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _goto(walker: Node3D, target: Vector3) -> void:
	walker.global_position = target + Vector3(0.0, 1.0, 0.0)
	await _settle(12.0)


func _shoot(from: Vector3, look_at: Vector3, path: String) -> void:
	var cam := Camera3D.new()
	cam.position = from
	cam.fov = 60.0
	cam.near = 0.02
	cam.far = 4000.0
	add_child(cam)
	cam.look_at(look_at, Vector3.UP)
	cam.make_current()
	await _settle(2.0)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
	else:
		img.save_png(path)
		print("SAVED %s" % path)
	cam.queue_free()
