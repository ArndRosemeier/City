## Gem ore voxels use two faceted cuts (hex column vs brilliant), not filled cubes.
##
## Run: powershell -File tools\run_test.ps1 test_gem_voxel_meshes
extends Node

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_test_tiers()
	_test_library_models()
	_test_winding(VoxelBlockLibrary._mesh_gem_column(), "column")
	_test_winding(VoxelBlockLibrary._mesh_gem_brilliant(), "brilliant")
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		print("RESULT: OK")
		get_tree().quit(0)


func _test_tiers() -> void:
	if VoxelMaterial.is_gem_brilliant(VoxelMaterial.GEM_QUARTZ):
		_fail("FAIL quartz must use the cheap column cut")
	if VoxelMaterial.is_gem_brilliant(VoxelMaterial.GEM_AMBER):
		_fail("FAIL amber must use the cheap column cut")
	if VoxelMaterial.is_gem_brilliant(VoxelMaterial.GEM_TOPAZ):
		_fail("FAIL topaz must use the cheap column cut")
	if not VoxelMaterial.is_gem_brilliant(VoxelMaterial.GEM_SAPPHIRE):
		_fail("FAIL sapphire must use the brilliant cut")
	if not VoxelMaterial.is_gem_brilliant(VoxelMaterial.GEM_EMERALD):
		_fail("FAIL emerald must use the brilliant cut")
	if not VoxelMaterial.is_gem_brilliant(VoxelMaterial.GEM_DIAMOND):
		_fail("FAIL diamond must use the brilliant cut")


func _test_library_models() -> void:
	var lib := VoxelBlockLibrary.build()
	for id in VoxelMaterial.GEM_IDS:
		var model := lib.get_model(id)
		if model == null:
			_fail("FAIL library missing model for gem %d" % id)
			continue
		if not (model is VoxelBlockyModelMesh):
			_fail("FAIL gem %d should be VoxelBlockyModelMesh, got %s" % [id, model.get_class()])
			continue
		var mesh_model := model as VoxelBlockyModelMesh
		if mesh_model.mesh == null or mesh_model.mesh.get_surface_count() < 1:
			_fail("FAIL gem %d has no mesh surface" % id)
			continue
		if mesh_model.culls_neighbors:
			_fail("FAIL gem %d must not cull neighbors (host rock faces)" % id)
		var arrays := mesh_model.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		## A unit cube visual is 24 verts; both cuts are denser faceted solids.
		if verts.size() < 36:
			_fail("FAIL gem %d mesh looks like a cube (%d verts)" % [id, verts.size()])
		var box_count := mesh_model.collision_aabbs.size()
		if box_count != 1:
			_fail("FAIL gem %d expected one collision aabb, got %d" % [id, box_count])
		elif mesh_model.collision_aabbs[0].size.is_equal_approx(Vector3.ONE):
			_fail("FAIL gem %d should not use a full-cell collision aabb" % id)


func _test_winding(mesh: ArrayMesh, label: String) -> void:
	if mesh == null or mesh.get_surface_count() < 1:
		_fail("FAIL %s mesh empty" % label)
		return
	var a: Array = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	if ix.is_empty():
		## Unindexed: walk triples directly.
		if v.size() < 9 or v.size() % 3 != 0:
			_fail("FAIL %s: bad unindexed vertex count %d" % [label, v.size()])
			return
		var i := 0
		while i + 2 < v.size():
			_check_tri(label, v[i], v[i + 1], v[i + 2], n[i])
			i += 3
		return
	var i := 0
	while i + 2 < ix.size():
		_check_tri(label, v[ix[i]], v[ix[i + 1]], v[ix[i + 2]], n[ix[i]])
		i += 3


func _check_tri(label: String, a0: Vector3, a1: Vector3, a2: Vector3, nn: Vector3) -> void:
	var cross: Vector3 = (a1 - a0).cross(a2 - a0)
	if cross.length() < 1e-6:
		_fail("FAIL %s: degenerate triangle" % label)
		return
	if cross.normalized().dot(nn.normalized()) > -0.9:
		_fail(
			(
				"FAIL %s: winding not clockwise-from-outside (align=%.3f)"
				% [label, cross.normalized().dot(nn.normalized())]
			)
		)
