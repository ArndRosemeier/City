extends SceneTree

const PedOutfitScript := preload("res://scripts/humans/ped_outfit.gd")
const PedOutfitCatalogScript := preload("res://scripts/humans/ped_outfit_catalog.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	PedOutfitCatalogScript.reload()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var o: PedOutfit = PedOutfitScript.random(rng, false)
	if o.scene_path == "":
		push_error("FAIL outfit missing scene_path")
		quit(1)
		return
	if o.variant_id == "":
		push_error("FAIL outfit missing variant_id")
		quit(1)
		return
	print(
		"PASS ped outfit pick id=",
		o.variant_id,
		" path=",
		o.scene_path,
		" catalog=",
		PedOutfitCatalogScript.count()
	)
	# If catalog empty, fallback nude is OK for CI before first export.
	if PedOutfitCatalogScript.count() == 0:
		print("WARN catalog empty — using nude fallback (export outfits to populate)")
	elif not ResourceLoader.exists(o.scene_path):
		push_error("FAIL catalog path missing on disk: %s" % o.scene_path)
		quit(1)
		return
	OS.kill(OS.get_process_id())
