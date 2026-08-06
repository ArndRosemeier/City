## ORB voxel: glowing energy sphere used as siege tips and reusable props.
##
## Run: powershell -File tools\run_test.ps1 test_orb_voxel
extends Node

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	if VoxelMaterial.ORB != 271:
		_fail("FAIL ORB id is %d, want 271" % VoxelMaterial.ORB)
	if VoxelMaterial.COUNT != VoxelMaterial.ORB + 1:
		_fail("FAIL COUNT does not follow ORB")
	if VoxelMaterial.is_gem(VoxelMaterial.ORB):
		_fail("FAIL ORB must not be a collectible gem")
	if VoxelMaterial.is_fractal_display(VoxelMaterial.ORB):
		_fail("FAIL ORB must not start a fractal cascade")
	if VoxelMaterial.hardness(VoxelMaterial.ORB) != VoxelMaterial.Hardness.EXOTIC:
		_fail("FAIL ORB should be EXOTIC hardness")
	if not VoxelMaterial.is_self_supporting_terrain(VoxelMaterial.ORB):
		_fail("FAIL ORB should be self-supporting")
	if not VoxelSurfaceSpec.has_bespoke_shader(VoxelMaterial.ORB):
		_fail("FAIL ORB needs a bespoke shader path")
	var mat := VoxelBlockLibrary.orb_material()
	if mat == null or mat.shader == null:
		_fail("FAIL orb_material missing shader")
	var lib := VoxelBlockLibrary.build()
	var model := lib.get_model(VoxelMaterial.ORB)
	if model == null:
		_fail("FAIL block library has no ORB model")
	elif model is VoxelBlockyModelMesh:
		var mesh_model := model as VoxelBlockyModelMesh
		if mesh_model.mesh == null or mesh_model.mesh.get_surface_count() < 1:
			_fail("FAIL ORB model has no mesh surface")
	else:
		_fail("FAIL ORB should be a custom mesh model, got %s" % model.get_class())
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		print("RESULT: OK")
		get_tree().quit(0)
