## Assert roof-slope wedges use clockwise-outward winding (Godot front faces).
extends SceneTree


func _initialize() -> void:
	var failed := false
	for toward in [
		VoxelMaterial.SLOPE_HIGH_POS_X,
		VoxelMaterial.SLOPE_HIGH_NEG_X,
		VoxelMaterial.SLOPE_HIGH_POS_Z,
		VoxelMaterial.SLOPE_HIGH_NEG_Z,
	]:
		var mesh: ArrayMesh = VoxelBlockLibrary._mesh_slope_45(toward)
		var a: Array = mesh.surface_get_arrays(0)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		if ix.size() < 24:
			push_error("toward %d: expected >= 8 tris, got %d" % [toward, ix.size() / 3])
			failed = true
			continue
		var i := 0
		var pitch_tris := 0
		while i + 2 < ix.size():
			var a0 := v[ix[i]]
			var a1 := v[ix[i + 1]]
			var a2 := v[ix[i + 2]]
			var nn: Vector3 = n[ix[i]].normalized()
			var cross: Vector3 = (a1 - a0).cross(a2 - a0)
			if cross.length() < 1e-6:
				push_error("toward %d: degenerate triangle" % toward)
				failed = true
			elif cross.normalized().dot(nn) > -0.9:
				push_error(
					(
						"toward %d: winding not clockwise-from-outside (align=%.3f)"
						% [toward, cross.normalized().dot(nn)]
					)
				)
				failed = true
			if absf(nn.y) > 0.4 and (absf(nn.x) > 0.4 or absf(nn.z) > 0.4):
				pitch_tris += 1
			i += 3
		if pitch_tris < 2:
			push_error("toward %d: missing pitched face tris" % toward)
			failed = true

	var lib := VoxelBlockLibrary.build()
	for id in [
		VoxelMaterial.ROOF_CLAY_SLOPE_POS_X,
		VoxelMaterial.ROOF_SLOPE_NEG_Z,
	]:
		var model := lib.get_model(id) as VoxelBlockyModelMesh
		if model == null:
			push_error("id %d not a mesh model" % id)
			failed = true
			continue
		if model.mesh.get_surface_count() != 1:
			push_error(
				(
					"id %d: expected 1 mesh surface (no discard collision mesh), got %d"
					% [id, model.mesh.get_surface_count()]
				)
			)
			failed = true
		if not model.is_mesh_collision_enabled(0):
			push_error("id %d: wedge visual must generate mesh collision" % id)
			failed = true
		if model.collision_aabbs.size() < 2:
			push_error(
				(
					"id %d: expected stepped collision aabbs, got %d"
					% [id, model.collision_aabbs.size()]
				)
			)
			failed = true
		else:
			## Must not be a single full-cell box (feet on cube top → legs in the roof).
			var full := false
			if model.collision_aabbs.size() == 1:
				var box: AABB = model.collision_aabbs[0]
				full = (
					box.position.is_equal_approx(Vector3.ZERO)
					and box.size.is_equal_approx(Vector3.ONE)
				)
			if full:
				push_error("id %d: full-cell collision aabb" % id)
				failed = true

	print("RESULT: ", "FAIL" if failed else "OK")
	quit(1 if failed else 0)
