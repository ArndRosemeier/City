## Wanted bill look inspection: the sepia mugshot on its own, the whole 5×10 m sheet on a test
## wall, and — with `-GodotArgs "--spawn-district=0,0"` — a bill on a real avenue facade with
## the city booted around it.
##
## Run: powershell -File tools\run_test.ps1 shot_wanted_poster -Rendered
extends Node3D

const WantedPosterScript := preload("res://scripts/city/wanted_poster.gd")
const WantedSuspectScript := preload("res://scripts/city/wanted_suspect.gd")
const CityBrushScript := preload("res://scripts/city/city_brush.gd")

const VOX := 0.5
const WORLD_SEED := 42
const SHEET_PNG := "res://tools/wanted_poster.png"
const CLOSE_PNG := "res://tools/wanted_poster_close.png"
const FACE_PNG := "res://tools/wanted_suspect.png"
const STREET_PNG := "res://tools/wanted_poster_street.png"
## Wall-clock, not frames: the tile bakes on worker threads while the loop spins.
const BOOT_TIMEOUT_MS := 120_000


func _ready() -> void:
	_build_stage()
	PedOutfitCatalog.reload()
	await WantedSuspectScript.ensure_portrait(WORLD_SEED, self)
	var portrait := WantedSuspectScript.portrait()
	if portrait == null:
		push_error("FAIL no mugshot was baked — run this rendered, not headless")
		get_tree().quit(1)
		return
	portrait.get_image().save_png(FACE_PNG)

	var site := WantedPoster.Site.new()
	site.origin_vox = Vector3i(0, 4, 0)
	site.run = Vector3i(1, 0, 0)
	site.out_dir = Vector3i(0, 0, -1)
	site.span = Vector2i(
		int(ceil(WantedPoster.SHEET_M.x / VOX)), int(ceil(WantedPoster.SHEET_M.y / VOX))
	)
	var brush: CityBrush = CityBrushScript.new() as CityBrush
	brush.use_offline_volume()
	brush.fill_box(Vector3i(-4, 0, 0), Vector3i(14, 30, 1), VoxelMaterial.BRICK)
	var poster: WantedPoster = WantedPosterScript.new() as WantedPoster
	add_child(poster)
	poster.setup(brush, site, VOX, portrait)

	var middle := Vector3(2.5, 7.0, 0.0)
	await _settle(0.5)
	await _shoot(middle + Vector3(0.0, -1.5, -14.0), middle, SHEET_PNG)
	await _shoot(middle + Vector3(0.4, 1.6, -5.0), middle + Vector3(0.0, 1.4, 0.0), CLOSE_PNG)
	poster.queue_free()
	await _shoot_in_city()
	print("RESULT: OK")
	get_tree().quit(0)


## The same sheet where it actually hangs: boot the city, find a tile that posted bills and
## look at one from the middle of the avenue it faces.
func _shoot_in_city() -> void:
	var city := CityRoot.new()
	city.city_seed = WORLD_SEED
	add_child(city)
	var deadline := Time.get_ticks_msec() + BOOT_TIMEOUT_MS
	while city.get_node_or_null("Walker") == null:
		if Time.get_ticks_msec() > deadline:
			push_error("FAIL no walker after %d s" % (BOOT_TIMEOUT_MS / 1000))
			return
		await get_tree().process_frame
	## Streaming keeps going after the walker exists; the bills go up late in the tile.
	var bill: WantedPoster = null
	while bill == null and Time.get_ticks_msec() < deadline:
		await _settle(1.0)
		bill = _first_bill(city)
	if bill == null:
		push_error("FAIL no tile posted a bill within the boot window")
		return
	var sheet := bill.global_position
	var out := bill.global_transform.basis.z
	print("street bill at %s facing %s" % [str(sheet), str(out)])
	## Back off across the pavement, at the height of the middle of the sheet.
	await _shoot(sheet + out * 16.0 - Vector3(0.0, 2.0, 0.0), sheet, STREET_PNG)


func _first_bill(city: CityRoot) -> WantedPoster:
	var districts: Array = city._streamer.call("get_loaded_districts") as Array
	for d: Variant in districts:
		var di: DistrictInstance = d
		if di == null or not is_instance_valid(di):
			continue
		for poster: WantedPoster in di.wanted_posters:
			if poster != null and is_instance_valid(poster):
				return poster
	return null


func _build_stage() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.55, 0.72)
	sky_mat.sky_horizon_color = Color(0.72, 0.76, 0.80)
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34.0, 160.0, 0.0)
	sun.light_energy = 1.25
	add_child(sun)

	## Stand-in masonry: the offline brush the poster boards has no meshes of its own.
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(18.0 * VOX, 30.0 * VOX, 1.0 * VOX)
	wall.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.44, 0.34, 0.30)
	mat.roughness = 0.95
	wall.material_override = mat
	wall.position = Vector3(2.5, 7.5, 0.25)
	add_child(wall)


func _settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _shoot(eye: Vector3, target: Vector3, path: String) -> void:
	var cam := Camera3D.new()
	cam.position = eye
	cam.fov = 50.0
	add_child(cam)
	cam.look_at(target, Vector3.UP)
	cam.make_current()
	await _settle(0.4)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
	else:
		img.save_png(path)
	cam.queue_free()
