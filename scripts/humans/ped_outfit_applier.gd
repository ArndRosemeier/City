## Applies skin tint to the body mesh inside a dressed outfit scene (no height-band clothes).
##
## Which mesh is skin comes from the material names the exporter recorded in catalog.json.
## Node names cannot be used: every MPFB garment node is named "<sex>_body_<item>", so any
## test for "body" matches the garments too and tints the whole outfit with the skin tone.
class_name PedOutfitApplier
extends RefCounted


static func apply_to_mesh(mesh: MeshInstance3D, outfit: PedOutfit, _female: bool) -> void:
	if mesh == null or outfit == null:
		return
	if _role_of(mesh, outfit) != PedOutfit.MeshRole.SKIN:
		return
	## Read the surface material, not the active one: material_override is our own tint from a
	## previous apply on this instance and would otherwise be duplicated on top of itself.
	var source: Material = mesh.mesh.surface_get_material(0)
	var base := StandardMaterial3D.new()
	if source is StandardMaterial3D:
		base = (source as StandardMaterial3D).duplicate() as StandardMaterial3D
	elif source is BaseMaterial3D:
		var bm := source as BaseMaterial3D
		base.albedo_texture = bm.albedo_texture
		base.roughness = bm.roughness
	base.albedo_color = outfit.skin
	mesh.material_override = base


static func apply_to_body_root(root: Node, outfit: PedOutfit, female: bool) -> void:
	if root == null or outfit == null:
		return
	_apply_recursive(root, outfit, female)


## SKIN when every surface of the mesh uses the outfit's skin material, GARMENT when every
## surface is a known garment, UNKNOWN otherwise. An unclassifiable mesh is reported rather
## than guessed: it means the GLB and its catalog entry disagree.
static func _role_of(mesh: MeshInstance3D, outfit: PedOutfit) -> PedOutfit.MeshRole:
	if mesh.mesh == null:
		push_error(
			"PedOutfitApplier: mesh %s in outfit %s has no Mesh" % [mesh.name, outfit.variant_id]
		)
		return PedOutfit.MeshRole.UNKNOWN
	var surfaces := mesh.mesh.get_surface_count()
	if surfaces <= 0:
		push_error(
			"PedOutfitApplier: mesh %s in outfit %s has no surfaces"
			% [mesh.name, outfit.variant_id]
		)
		return PedOutfit.MeshRole.UNKNOWN
	var role := PedOutfit.MeshRole.UNKNOWN
	for i in surfaces:
		var surface: Material = mesh.mesh.surface_get_material(i)
		var surface_name := "" if surface == null else String(surface.resource_name)
		var surface_role := outfit.role_for_material(surface_name)
		if surface_role == PedOutfit.MeshRole.UNKNOWN:
			push_error(
				(
					"PedOutfitApplier: outfit %s (%s) has mesh %s surface %d with "
					+ "unclassified material '%s' — expected skin '%s' or one of %s"
				)
				% [
					outfit.variant_id,
					outfit.scene_path,
					mesh.name,
					i,
					surface_name,
					outfit.skin_material,
					String(", ").join(outfit.garment_materials),
				]
			)
			return PedOutfit.MeshRole.UNKNOWN
		if i == 0:
			role = surface_role
		elif surface_role != role:
			push_error(
				"PedOutfitApplier: mesh %s in outfit %s mixes skin and garment surfaces"
				% [mesh.name, outfit.variant_id]
			)
			return PedOutfit.MeshRole.UNKNOWN
	return role


static func _apply_recursive(node: Node, outfit: PedOutfit, female: bool) -> void:
	if node is MeshInstance3D:
		apply_to_mesh(node as MeshInstance3D, outfit, female)
	for child in node.get_children():
		_apply_recursive(child, outfit, female)
