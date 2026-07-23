## Fills every block with air so the district can be stamped via VoxelTool.
extends VoxelGeneratorScript


func _get_used_channels_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_TYPE


func _generate_block(out_buffer: VoxelBuffer, _origin_in_voxels: Vector3i, lod: int) -> void:
	if lod != 0:
		return
	out_buffer.fill(VoxelMaterial.AIR, VoxelBuffer.CHANNEL_TYPE)
