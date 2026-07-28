## Reports where each garment's skin weights landed, per outfit mesh.
##
## This is the mhclo question that a screenshot cannot answer: MPFB fits a Clothes-type asset
## against the rest pose and derives its weights by interpolating the body's, so a weapon can
## come out smeared across the forearm instead of rigidly gripped. A weapon that is >95% on one
## hand bone will not float; one spread over several bones will swim as the arm bends.
##
## Run: powershell -File tools\run_test.ps1 probe_mhclo_weights -GodotArgs "--outfit=<id>"
extends Node

## Below this share on the single dominant bone, a rigid prop will visibly wobble.
const RIGID_SHARE := 0.95

var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	PedOutfitCatalog.reload()
	var outfits := _selected_outfits()
	if outfits.is_empty():
		_fail("no outfit selected")
		_finish()
		return
	for outfit in outfits:
		_report(outfit)
	_finish()


func _selected_outfits() -> Array[PedOutfit]:
	var wanted := ""
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--outfit="):
			wanted = arg.substr("--outfit=".length())
	var all := PedOutfitCatalog.all_outfits()
	if wanted == "":
		return all
	var out: Array[PedOutfit] = []
	for outfit in all:
		if outfit.variant_id == wanted:
			out.append(outfit)
	return out


func _report(outfit: PedOutfit) -> void:
	var packed: Resource = load(outfit.scene_path)
	if not (packed is PackedScene):
		_fail("%s: not a PackedScene" % outfit.variant_id)
		return
	var root: Node = (packed as PackedScene).instantiate()
	var skeleton := _find_skeleton(root)
	if skeleton == null:
		_fail("%s: no Skeleton3D" % outfit.variant_id)
		root.free()
		return
	print("=== ", outfit.variant_id, "  bones=", skeleton.get_bone_count())
	for mesh in _collect_meshes(root):
		_report_mesh(outfit, skeleton, mesh)
	root.free()


func _report_mesh(outfit: PedOutfit, skeleton: Skeleton3D, mesh: MeshInstance3D) -> void:
	var surface: Material = mesh.mesh.surface_get_material(0)
	var material_name := "" if surface == null else String(surface.resource_name)
	var role := outfit.role_for_material(material_name)
	var arrays: Array = mesh.mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if bones.is_empty() or weights.is_empty():
		_fail("%s / %s: no skin weights" % [outfit.variant_id, mesh.name])
		return
	var vertex_count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var influences := bones.size() / vertex_count
	var totals: Dictionary[int, float] = {}
	var total_weight := 0.0
	var max_used := 0
	for v in vertex_count:
		var used := 0
		for i in influences:
			var w := weights[v * influences + i]
			if w <= 0.0:
				continue
			used += 1
			var b := bones[v * influences + i]
			totals[b] = float(totals.get(b, 0.0)) + w
			total_weight += w
		max_used = maxi(max_used, used)
	var ranked: Array[int] = []
	for b: int in totals:
		ranked.append(b)
	ranked.sort_custom(func(a: int, b: int) -> bool: return totals[a] > totals[b])
	var summary := PackedStringArray()
	for i in mini(4, ranked.size()):
		summary.append(
			"%s %.0f%%" % [skeleton.get_bone_name(ranked[i]), 100.0 * totals[ranked[i]] / total_weight]
		)
	var top_share := totals[ranked[0]] / total_weight
	print(
		"  %-42s role=%-7s verts=%-6d influences=%d max_used=%d bones_touched=%d  %s"
		% [
			material_name,
			_role_name(role),
			vertex_count,
			influences,
			max_used,
			ranked.size(),
			String(", ").join(summary),
		]
	)
	if max_used > 4:
		_fail(
			"%s / %s: %d influences per vertex — over the 4 the exporter limits to"
			% [outfit.variant_id, material_name, max_used]
		)
	if material_name.contains("sword") or material_name.contains("dagger"):
		if top_share < RIGID_SHARE:
			print(
				"  NOTE weapon %s is only %.0f%% on %s — expect it to swim as the arm bends"
				% [material_name, 100.0 * top_share, skeleton.get_bone_name(ranked[0])]
			)
		else:
			print(
				"  weapon %s is %.0f%% rigid on %s"
				% [material_name, 100.0 * top_share, skeleton.get_bone_name(ranked[0])]
			)


func _role_name(role: PedOutfit.MeshRole) -> String:
	match role:
		PedOutfit.MeshRole.SKIN:
			return "skin"
		PedOutfit.MeshRole.GARMENT:
			return "garment"
	return "UNKNOWN"


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


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


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
