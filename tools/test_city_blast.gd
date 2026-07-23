## Legacy rubble test — structural RigidBody debris is deferred (godot_voxel dig-only for now).
extends SceneTree


func _initialize() -> void:
	print("SKIP test_city_blast: DestructionService rubble not used with VoxelTerrain dig POC")
	quit(0)
