## Back-compat wrapper around the voxel study (glass single-material pass).
## Prefer: powershell -File tools\run_test.ps1 shot_voxel_study -Rendered -GodotArgs "--material=glass"
extends "res://tools/shot_voxel_study.gd"


func _resolve_materials() -> Array[int]:
	return [VoxelMaterial.GLASS] as Array[int]


func _default_out_name(_label: String) -> String:
	return "glass_shot.png"
