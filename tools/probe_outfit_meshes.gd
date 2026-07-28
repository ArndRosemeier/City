## Dumps node + material names of every catalog outfit GLB, plus what the current
## PedOutfitApplier heuristic decides for each mesh. Diagnostic only.
extends Node

const PedOutfitApplierScript := preload("res://scripts/humans/ped_outfit_applier.gd")


func _ready() -> void:
	PedOutfitCatalog.reload()
	var outfits := PedOutfitCatalog.all_outfits()
	if outfits.is_empty():
		push_error("FAIL catalog empty")
		get_tree().quit(1)
		return
	for outfit in outfits:
		print("=== ", outfit.variant_id, "  ", outfit.scene_path)
		var packed: Resource = load(outfit.scene_path)
		if not (packed is PackedScene):
			push_error("FAIL not a PackedScene: %s" % outfit.scene_path)
			get_tree().quit(1)
			return
		var root: Node = (packed as PackedScene).instantiate()
		_dump(root, outfit)
		root.free()
	## The nude bases are what PedOutfitCatalog falls back to, so they are dumped against a
	## stand-in of that fallback outfit rather than against a catalog entry, whose skin material
	## belongs to the other sex half the time.
	const BASES: Array[String] = [
		"res://assets/humans/male_base.glb",
		"res://assets/humans/male_base.gltf",
		"res://assets/humans/female_base.glb",
		"res://assets/humans/female_base.gltf",
	]
	for base_path in BASES:
		print("=== BASE ", base_path, " exists=", ResourceLoader.exists(base_path))
		if not ResourceLoader.exists(base_path):
			continue
		var base_packed: Resource = load(base_path)
		if not (base_packed is PackedScene):
			continue
		var female := base_path.contains("female")
		var fallback := PedOutfit.new()
		fallback.female = female
		fallback.variant_id = "fallback_nude"
		fallback.scene_path = base_path
		fallback.skin_material = (
			PedOutfitCatalog.FALLBACK_FEMALE_SKIN_MATERIAL
			if female
			else PedOutfitCatalog.FALLBACK_MALE_SKIN_MATERIAL
		)
		var base_root: Node = (base_packed as PackedScene).instantiate()
		_dump(base_root, fallback)
		base_root.free()
	print("RESULT: OK")
	get_tree().quit(0)


func _dump(node: Node, outfit: PedOutfit) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var active: Material = mi.get_active_material(0)
		var surf: Material = null
		if mi.mesh != null and mi.mesh.get_surface_count() > 0:
			surf = mi.mesh.surface_get_material(0)
		var before: Color = Color(1, 1, 1, 1)
		if active is BaseMaterial3D:
			before = (active as BaseMaterial3D).albedo_color
		PedOutfitApplierScript.apply_to_mesh(mi, outfit, outfit.female)
		var tinted := mi.material_override != null
		print(
			"  node=%s  surfaces=%d  active_res_name=%s  surf_res_name=%s  albedo_before=%s  TINTED=%s"
			% [
				String(mi.name),
				mi.mesh.get_surface_count() if mi.mesh != null else 0,
				String(active.resource_name) if active != null else "<null>",
				String(surf.resource_name) if surf != null else "<null>",
				str(before),
				str(tinted),
			]
		)
	for child in node.get_children():
		_dump(child, outfit)
