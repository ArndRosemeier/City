## Applies skin tint to body mesh inside a dressed outfit scene (no height-band clothes).
class_name PedOutfitApplier
extends RefCounted


static func apply_to_mesh(mesh: MeshInstance3D, outfit: PedOutfit, _female: bool) -> void:
	if mesh == null or outfit == null:
		return
	# Only tint the skin surface — leave cloth materials alone.
	var mat_name := String(mesh.name).to_lower()
	var active: Material = mesh.get_active_material(0)
	if active == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
		active = mesh.mesh.surface_get_material(0)
	var looks_like_skin := (
		mat_name.contains("skin")
		or mat_name.contains("body")
		or (active != null and String(active.resource_name).to_lower().contains("skin"))
	)
	if not looks_like_skin:
		# Heuristic: first mesh without a cloth-like name may still be body.
		if active is StandardMaterial3D:
			var std := active as StandardMaterial3D
			if std.albedo_texture != null and std.metallic < 0.2:
				# Likely skin if it has the MH diffuse and no cloth keywords.
				if (
					mat_name.contains("suit")
					or mat_name.contains("shoe")
					or mat_name.contains("cloth")
					or mat_name.contains("fedora")
				):
					return
				looks_like_skin = true
	if not looks_like_skin:
		return
	var base := StandardMaterial3D.new()
	if active is StandardMaterial3D:
		base = (active as StandardMaterial3D).duplicate() as StandardMaterial3D
	elif active is BaseMaterial3D:
		var bm := active as BaseMaterial3D
		base.albedo_texture = bm.albedo_texture
		base.roughness = bm.roughness
	base.albedo_color = outfit.skin
	mesh.material_override = base


static func apply_to_body_root(root: Node, outfit: PedOutfit, female: bool) -> void:
	if root == null or outfit == null:
		return
	_apply_recursive(root, outfit, female)


static func _apply_recursive(node: Node, outfit: PedOutfit, female: bool) -> void:
	if node is MeshInstance3D:
		apply_to_mesh(node as MeshInstance3D, outfit, female)
	for child in node.get_children():
		_apply_recursive(child, outfit, female)
