## Solid DOOR voxel plugs for a CastleDoorway clear. Leaf meshes stay visual-only;
## motion and nav read these cells. All writes go through CityBrush.
class_name DoorBarrier
extends RefCounted


## World-voxel cells that form the clear arch / rectangle of `d`.
## `origin_vox` shifts district-local doorway coords into world space.
static func barrier_cells(d: CastleDoorway, origin_vox: Vector3i = Vector3i.ZERO) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if d == null or d.width <= 0 or d.height <= 0 or d.depth <= 0:
		return out
	var s := d.side()
	for depth_i in range(d.depth):
		for row in range(1, d.height + 1):
			var h := d.row_half(row)
			if h < 0:
				continue
			for t in range(-h, h + 1):
				var col: Vector2i = d.center + d.axis * depth_i + s * t
				out.append(Vector3i(col.x, d.floor_y + row, col.y) + origin_vox)
	return out


## Fill the clear with DOOR (closed). Nestable under an outer begin_edit.
static func apply_closed(
	brush: CityBrush, d: CastleDoorway, origin_vox: Vector3i = Vector3i.ZERO
) -> int:
	if brush == null or d == null:
		return 0
	var cells := barrier_cells(d, origin_vox)
	brush.begin_edit()
	var n := 0
	for vox in cells:
		var cur := brush.get_vox(vox)
		## Only plug empty / already-door cells — never overwrite masonry or props.
		if cur != VoxelMaterial.AIR and cur != VoxelMaterial.DOOR:
			continue
		if cur != VoxelMaterial.DOOR:
			brush.set_vox(vox, VoxelMaterial.DOOR)
			n += 1
	brush.end_edit()
	return n


## Clear DOOR plugs back to AIR (open). Uses destroy_vox so the write funnel stays singular.
static func apply_open(
	brush: CityBrush, d: CastleDoorway, origin_vox: Vector3i = Vector3i.ZERO
) -> int:
	if brush == null or d == null:
		return 0
	var cells := barrier_cells(d, origin_vox)
	brush.begin_edit()
	var n := 0
	for vox in cells:
		if brush.get_vox(vox) != VoxelMaterial.DOOR:
			continue
		n += brush.destroy_vox(vox).size()
	brush.end_edit()
	return n


## World-space centre of the threshold (for proximity / hints).
static func world_anchor(d: CastleDoorway, voxel_size: float, origin_vox: Vector3i = Vector3i.ZERO) -> Vector3:
	if d == null:
		return Vector3.ZERO
	var c := d.center
	var y := float(d.floor_y + 1) + 0.5
	return Vector3(
		(float(c.x + origin_vox.x) + 0.5) * voxel_size,
		(y + float(origin_vox.y)) * voxel_size,
		(float(c.y + origin_vox.z) + 0.5) * voxel_size
	)
