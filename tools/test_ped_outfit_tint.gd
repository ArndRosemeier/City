## Skin tint targeting: for every catalog outfit the tint must land on exactly the skin mesh
## and on no garment mesh.
##
## The old applier classified meshes by node name, and MPFB names every garment node
## "<sex>_body_<item>" — so a test for "body" matched the garments too and every mesh in the
## outfit was multiplied by the wearer's skin tone.
extends Node

const PedOutfitApplierScript := preload("res://scripts/humans/ped_outfit_applier.gd")

var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	PedOutfitCatalog.reload()
	var outfits := PedOutfitCatalog.all_outfits()
	if outfits.is_empty():
		_fail("catalog is empty — export outfits before running this test")
		_finish()
		return
	for outfit in outfits:
		_check_outfit(outfit)
	_check_nude_fallback()
	_finish()


func _check_outfit(outfit: PedOutfit) -> void:
	var packed: Resource = load(outfit.scene_path)
	if not (packed is PackedScene):
		_fail("%s: %s is not a PackedScene" % [outfit.variant_id, outfit.scene_path])
		return
	var root: Node = (packed as PackedScene).instantiate()
	add_child(root)
	PedOutfitApplierScript.apply_to_body_root(root, outfit, outfit.female)

	var meshes := _collect_meshes(root)
	if meshes.is_empty():
		_fail("%s: outfit scene has no MeshInstance3D" % outfit.variant_id)
		root.queue_free()
		return
	var tinted: PackedStringArray = PackedStringArray()
	var garment_count := 0
	for mesh in meshes:
		var surface: Material = mesh.mesh.surface_get_material(0)
		var surface_name := "" if surface == null else String(surface.resource_name)
		var role := outfit.role_for_material(surface_name)
		if role == PedOutfit.MeshRole.UNKNOWN:
			_fail(
				"%s: mesh %s material '%s' is not classified by the catalog entry"
				% [outfit.variant_id, mesh.name, surface_name]
			)
			continue
		if role == PedOutfit.MeshRole.GARMENT:
			garment_count += 1
		if mesh.material_override == null:
			if role == PedOutfit.MeshRole.SKIN:
				_fail("%s: skin mesh %s was not tinted" % [outfit.variant_id, mesh.name])
			continue
		tinted.append(String(mesh.name))
		if role != PedOutfit.MeshRole.SKIN:
			_fail(
				"%s: garment mesh %s (material '%s') was tinted with the skin tone"
				% [outfit.variant_id, mesh.name, surface_name]
			)
			continue
		var override := mesh.material_override as BaseMaterial3D
		if override == null:
			_fail("%s: skin mesh %s override is not a BaseMaterial3D" % [outfit.variant_id, mesh.name])
		elif not override.albedo_color.is_equal_approx(outfit.skin):
			_fail(
				"%s: skin mesh %s albedo %s does not match outfit skin %s"
				% [outfit.variant_id, mesh.name, override.albedo_color, outfit.skin]
			)
	if tinted.size() != 1:
		_fail(
			"%s: expected exactly 1 tinted mesh, got %d (%s)"
			% [outfit.variant_id, tinted.size(), String(", ").join(tinted)]
		)
	if garment_count <= 0:
		_fail("%s: no garment mesh found — the catalog entry lists none" % outfit.variant_id)
	root.queue_free()


## The nude base is what a civilian pick returns before any outfit is exported, so its single
## body mesh must still be recognised as skin.
func _check_nude_fallback() -> void:
	for female: bool in [false, true]:
		var path: String = (
			PedOutfitCatalog.FALLBACK_FEMALE if female else PedOutfitCatalog.FALLBACK_MALE
		)
		var packed: Resource = load(path)
		if not (packed is PackedScene):
			_fail("nude fallback %s is not a PackedScene" % path)
			continue
		var outfit := PedOutfit.new()
		outfit.female = female
		outfit.variant_id = "fallback_nude"
		outfit.scene_path = path
		outfit.skin = Color(0.32, 0.22, 0.16)
		outfit.skin_material = (
			PedOutfitCatalog.FALLBACK_FEMALE_SKIN_MATERIAL
			if female
			else PedOutfitCatalog.FALLBACK_MALE_SKIN_MATERIAL
		)
		var root: Node = (packed as PackedScene).instantiate()
		add_child(root)
		PedOutfitApplierScript.apply_to_body_root(root, outfit, female)
		var tinted := 0
		for mesh in _collect_meshes(root):
			if mesh.material_override != null:
				tinted += 1
		if tinted != 1:
			_fail("nude fallback %s: expected 1 tinted mesh, got %d" % [path, tinted])
		root.queue_free()


func _collect_meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			out.append(n as MeshInstance3D)
		for c in n.get_children():
			stack.append(c)
	return out


func _fail(msg: String) -> void:
	_failures.append(msg)
	print("FAIL ", msg)


func _finish() -> void:
	if _failures.is_empty():
		print("RESULT: OK")
		get_tree().quit(0)
		return
	print("RESULT: FAIL (%d)" % _failures.size())
	get_tree().quit(1)
