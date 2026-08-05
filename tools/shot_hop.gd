## District hop look inspection: boots the live city and plays the launch animation through the
## player's own camera, photographing what the hop actually looks like.
##
## Shot through the walker camera on purpose. Every frame of this animation is a camera angle —
## a spectator camera would prove nothing about where the player is looking.
##
## Runs as a scene (not --script) because the city scripts need the CityProfiler autoload:
##
##   powershell -File tools\run_test.ps1 shot_hop -Rendered
extends Node

const DistrictHopCutsceneScript := preload("res://scripts/city/district_hop_cutscene.gd")

const WORLD_SEED := 42
const RISE_PNG := "res://tools/hop_rise.png"
const CLOUDS_PNG := "res://tools/hop_clouds.png"
const DESCENT_PNG := "res://tools/hop_descent.png"


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
	var walker: CityWalker = city.get_node_or_null("Walker") as CityWalker
	await _settle(14.0)
	walker.set_physics_process(false)
	var feet := walker.global_position

	var scene: DistrictHopCutscene = DistrictHopCutsceneScript.new() as DistrictHopCutscene
	scene.name = "HopCutscene"
	city.add_child(scene)
	scene.begin(walker)

	## Caught partway up, where the ground is still close enough to read as ground.
	scene.start_rise()
	await _settle(DistrictHopCutscene.RISE_SEC * 0.75)
	await _shoot(RISE_PNG)
	while not scene.is_phase_done():
		await get_tree().process_frame

	## The hold, with the birds falling past. Given a beat so they spread through the box.
	scene.start_hold(walker.global_position)
	await _settle(3.0)
	await _shoot(CLOUDS_PNG)

	## Coming in, at the point the camera has swung back down onto the district.
	scene.start_descent(feet)
	await _settle(DistrictHopCutscene.DESCENT_SEC * 0.4)
	await _shoot(DESCENT_PNG)
	while not scene.is_phase_done():
		await get_tree().process_frame
	scene.finish()

	print("RESULT: OK")
	get_tree().quit(0)


func _settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _shoot(path: String) -> void:
	await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
		return
	img.save_png(path)
	print("SAVED %s" % path)
