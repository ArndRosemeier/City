## Instantiates a catalog vehicle mesh + seated passengers.
## Procedural kits are primary; Kenney GLBs are opaque last-resort fallback only.
## Missing meshes/outfits error out — no box/capsule stand-ins.
class_name VehicleVisual
extends Node3D

const PedOutfitScript := preload("res://scripts/humans/ped_outfit.gd")
const QuaterniusLocomotionScript := preload("res://scripts/city/quaternius_locomotion.gd")

var _mesh_root: Node3D
var _passengers_root: Node3D
var _entry: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _body_length: float = 4.0
var _body_width: float = 1.8
var _body_height: float = 1.4
var _mesh_scale: float = 1.0
var _used_fallback: bool = false
var ready_visual: bool = false
var glass_material_count: int = 0


func setup(entry: Dictionary, passenger_count: int, seed_value: int = -1) -> void:
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	_entry = entry
	ready_visual = false
	glass_material_count = 0
	_used_fallback = false
	_clear()
	if not _spawn_body():
		return
	_passengers_root = Node3D.new()
	_passengers_root.name = "Passengers"
	add_child(_passengers_root)
	_spawn_passengers(passenger_count)
	ready_visual = true


func sync_pose(world_pos: Vector3, yaw: float) -> void:
	global_position = world_pos
	rotation.y = yaw


func _clear() -> void:
	for c in get_children():
		c.queue_free()
	_mesh_root = null
	_passengers_root = null


func _spawn_body() -> bool:
	var id := str(_entry.get("id", "?"))
	var source := str(_entry.get("source", "kenney")).to_lower()
	_mesh_scale = float(_entry.get("scale", 1.0))

	if source == "procedural":
		_mesh_root = ProceduralVehicle.build(_entry, _rng)
		if _mesh_root == null:
			push_error("VehicleVisual: procedural build returned null (id=%s)" % id)
			return _try_kenney_fallback(id)
		var glass_meta: Variant = _mesh_root.get_meta("glass_count", 0)
		if int(glass_meta) <= 0:
			push_error("VehicleVisual: procedural car has no glass (id=%s)" % id)
			_mesh_root.free()
			_mesh_root = null
			return _try_kenney_fallback(id)
		_mesh_root.name = "Body"
		_mesh_root.scale = Vector3(_mesh_scale, _mesh_scale, _mesh_scale)
		add_child(_mesh_root)
		_normalize_body_orientation()
		_count_and_finalize_materials(true)
		if glass_material_count <= 0:
			push_error("VehicleVisual: procedural glass materials missing after spawn (id=%s)" % id)
			return false
		_apply_procedural_seats_from_meta()
		return true

	if source == "kenney":
		return _spawn_kenney_scene(str(_entry.get("path", "")), id, false)

	push_error("VehicleVisual: unknown source '%s' (id=%s)" % [source, id])
	return false


func _try_kenney_fallback(id: String) -> bool:
	var path := str(_entry.get("fallback_path", _entry.get("path", "")))
	if path == "":
		push_error("VehicleVisual: no Kenney fallback_path for id=%s" % id)
		return false
	push_warning("VehicleVisual: using Kenney fallback (opaque) for id=%s path=%s" % [id, path])
	_used_fallback = true
	return _spawn_kenney_scene(path, id, false)


func _spawn_kenney_scene(path: String, id: String, require_glass: bool) -> bool:
	if path == "":
		push_error("VehicleVisual: entry '%s' has empty path" % id)
		return false
	if not ResourceLoader.exists(path):
		push_error("VehicleVisual: mesh not importable: %s (id=%s)" % [path, id])
		return false
	var packed := load(path)
	if not (packed is PackedScene):
		push_error(
			"VehicleVisual: %s is %s, expected PackedScene (id=%s)"
			% [path, packed.get_class() if packed else "null", id]
		)
		return false
	_mesh_root = (packed as PackedScene).instantiate() as Node3D
	if _mesh_root == null:
		push_error("VehicleVisual: instantiate failed for %s" % path)
		return false
	_mesh_root.name = "Body"
	_mesh_root.scale = Vector3(_mesh_scale, _mesh_scale, _mesh_scale)
	add_child(_mesh_root)
	_normalize_body_orientation()
	_apply_kenney_materials()
	if require_glass and glass_material_count <= 0:
		push_error("VehicleVisual: no glass on Kenney mesh (id=%s path=%s)" % [id, path])
		return false
	return true


func _normalize_body_orientation() -> void:
	var aabb := _local_mesh_aabb(_mesh_root)
	if aabb.size == Vector3.ZERO:
		push_error("VehicleVisual: body has no MeshInstance3D AABB (id=%s)" % str(_entry.get("id", "?")))
		return
	# Procedural cars already face +Z with length along Z. Only rotate Kenney if needed.
	var source := str(_entry.get("source", "")).to_lower()
	if source != "procedural" or _used_fallback:
		if aabb.size.x > aabb.size.z * 1.05:
			_mesh_root.rotate_y(PI * 0.5)
			aabb = _local_mesh_aabb(_mesh_root)
		var yaw_fix := float(_entry.get("yaw_fix", 0.0))
		if not is_zero_approx(yaw_fix):
			_mesh_root.rotate_y(yaw_fix)
			aabb = _local_mesh_aabb(_mesh_root)
	_mesh_root.position.y = -aabb.position.y + float(_entry.get("y_offset", 0.0))
	_body_length = maxf(aabb.size.z, 2.0)
	_body_width = maxf(aabb.size.x, 1.2)
	_body_height = maxf(aabb.size.y, 1.0)


func _apply_procedural_seats_from_meta() -> void:
	if not _mesh_root.has_meta("seat_offsets"):
		return
	var catalog_seats: Array = _entry.get("seat_offsets", []) as Array
	if not catalog_seats.is_empty():
		return
	var meta_seats: Variant = _mesh_root.get_meta("seat_offsets")
	if typeof(meta_seats) == TYPE_ARRAY:
		_entry["seat_offsets"] = (meta_seats as Array).duplicate(true)


func _count_and_finalize_materials(require_glass: bool) -> void:
	glass_material_count = 0
	for node in _mesh_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		var mat := mi.material_override
		if mat == null:
			continue
		var mat_name := String(mat.resource_name).to_lower()
		if mat_name == "glass":
			glass_material_count += 1
			# Ensure alpha blend survives any importer quirks.
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if require_glass and glass_material_count <= 0:
		push_error("VehicleVisual: expected glass materials, found none")


func _apply_kenney_materials() -> void:
	## Last-resort Kenney path: keep opaque materials, optional paint tint on body.
	glass_material_count = 0
	var paint := Color.from_hsv(_rng.randf(), _rng.randf_range(0.35, 0.7), _rng.randf_range(0.55, 0.95))
	var id := str(_entry.get("id", ""))
	var paint_mix := 0.0 if id == "taxi" or id == "police" else 0.45

	for node in _mesh_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var nname := String(mi.name).to_lower()
		if nname.contains("wheel") or nname.contains("tire"):
			continue
		var surface_count := mi.mesh.get_surface_count()
		for si in range(surface_count):
			var base: Material = mi.get_active_material(si)
			if base == null:
				base = mi.mesh.surface_get_material(si)
			if base == null:
				continue
			var mat_name := _material_name(base).to_lower()
			if mat_name.contains("glass"):
				# Kenney split glass was unreliable — force opaque cool tint instead of holes.
				var opaque := StandardMaterial3D.new()
				opaque.resource_name = "glass_opaque"
				opaque.albedo_color = Color(0.55, 0.65, 0.75, 1.0)
				opaque.roughness = 0.15
				opaque.metallic = 0.1
				opaque.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				mi.set_surface_override_material(si, opaque)
			elif mat_name.contains("body") or mat_name.contains("colormap"):
				mi.set_surface_override_material(si, _make_painted_body_material(base, paint, paint_mix))


func _material_name(mat: Material) -> String:
	if mat.resource_name != "":
		return mat.resource_name
	var path := mat.resource_path
	if path != "":
		return path.get_file().get_basename()
	return mat.get_class()


func _make_painted_body_material(base: Material, paint: Color, paint_mix: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	if base is StandardMaterial3D:
		var src := base as StandardMaterial3D
		mat.albedo_texture = src.albedo_texture
		mat.albedo_color = src.albedo_color.lerp(
			Color(src.albedo_color.r * paint.r, src.albedo_color.g * paint.g, src.albedo_color.b * paint.b, 1.0),
			paint_mix
		)
		mat.roughness = src.roughness
		mat.metallic = src.metallic
	else:
		mat.albedo_color = paint
		mat.roughness = 0.55
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.resource_name = "body"
	return mat


func _local_mesh_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var any := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var local_xf := _xform_to_ancestor(mi, root)
		var mesh_aabb := mi.mesh.get_aabb()
		for corner in _aabb_corners(mesh_aabb):
			var p: Vector3 = local_xf * corner
			if not any:
				out = AABB(p, Vector3.ZERO)
				any = true
			else:
				out = out.expand(p)
	return out


func _xform_to_ancestor(node: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var walk: Node = node
	while walk != null and walk != ancestor:
		if walk is Node3D:
			xf = (walk as Node3D).transform * xf
		walk = walk.get_parent()
	return xf


func _aabb_corners(a: AABB) -> Array[Vector3]:
	var p := a.position
	var s := a.size
	return [
		p,
		p + Vector3(s.x, 0, 0),
		p + Vector3(0, s.y, 0),
		p + Vector3(0, 0, s.z),
		p + Vector3(s.x, s.y, 0),
		p + Vector3(s.x, 0, s.z),
		p + Vector3(0, s.y, s.z),
		p + s,
	]


func _spawn_passengers(count: int) -> void:
	if count <= 0:
		return
	var seats: Array = _entry.get("seat_offsets", []) as Array
	if seats.is_empty():
		seats = _auto_seats()
	var n := mini(count, seats.size())
	for i in range(n):
		var seat: Dictionary = seats[i]
		var female := _rng.randf() < 0.5
		var outfit: PedOutfit = PedOutfitScript.random(_rng, female)
		if outfit == null or outfit.scene_path == "":
			push_error("VehicleVisual: PedOutfit missing scene_path (female=%s)" % female)
			continue
		if not ResourceLoader.exists(outfit.scene_path):
			push_error("VehicleVisual: passenger outfit not importable: %s" % outfit.scene_path)
			continue
		var passenger := _make_passenger(outfit.scene_path)
		if passenger == null:
			continue
		var local := Vector3(
			float(seat.get("x", 0.0)),
			float(seat.get("y", 0.45)),
			float(seat.get("z", 0.2))
		)
		passenger.position = _mesh_root.transform * local
		passenger.rotation.y = 0.0
		var pscale := 0.92
		if _mesh_root.has_meta("passenger_scale"):
			pscale = float(_mesh_root.get_meta("passenger_scale"))
		elif _entry.has("passenger_scale"):
			pscale = float(_entry.get("passenger_scale"))
		passenger.scale = Vector3(pscale, pscale, pscale)
		_passengers_root.add_child(passenger)


func _auto_seats() -> Array:
	var half_w := clampf(_body_width * 0.22, 0.28, 0.42)
	var seat_y := clampf(_body_height * 0.35, 0.35, 0.7)
	var seat_z := clampf(_body_length * 0.05, 0.05, 0.45)
	return [
		{"x": -half_w, "y": seat_y, "z": seat_z},
		{"x": half_w, "y": seat_y, "z": seat_z},
	]


func _make_passenger(scene_path: String) -> Node3D:
	var packed := load(scene_path)
	if not (packed is PackedScene):
		push_error(
			"VehicleVisual: passenger %s is %s, expected PackedScene"
			% [scene_path, packed.get_class() if packed else "null"]
		)
		return null
	var root := Node3D.new()
	root.name = "Passenger"
	var body := (packed as PackedScene).instantiate() as Node3D
	if body == null:
		push_error("VehicleVisual: passenger instantiate failed: %s" % scene_path)
		root.free()
		return null
	body.name = "Body"
	# Outfit meshes face +Z by default. VehicleDirector forward is local -Z, and
	# procedural cars put the nose on -Z — PI aligns passengers with the windshield.
	body.rotation.y = PI
	root.add_child(body)
	var skel := _find_skeleton(body)
	if skel == null:
		push_error("VehicleVisual: passenger has no Skeleton3D: %s" % scene_path)
		root.free()
		return null
	skel.unique_name_in_owner = true
	var anim := AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	body.add_child(anim)
	QuaterniusLocomotionScript.attach_passenger(anim)
	QuaterniusLocomotionScript.play_driving(anim)
	return root


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s != null:
			return s
	return null
