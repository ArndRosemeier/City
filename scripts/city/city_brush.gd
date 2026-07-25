## Thin brush: live VoxelTool *or* NativeOfflineVoxelVolume (thread-safe baking).
## Local district coords; live mode offsets by `origin` into world voxel space.
class_name CityBrush
extends RefCounted

const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")

var tool: VoxelTool
var origin: Vector3i = Vector3i.ZERO
## NativeOfflineVoxelVolume when baking off-thread; null in live mode.
var volume


func _init(p_tool: VoxelTool = null, p_origin: Vector3i = Vector3i.ZERO) -> void:
	tool = p_tool
	origin = p_origin
	if tool != null:
		tool.channel = VoxelBuffer.CHANNEL_TYPE
		tool.mode = VoxelTool.MODE_SET


func use_offline_volume(p_volume = null) -> void:
	if p_volume != null:
		volume = p_volume
	else:
		volume = CityVoxelNativeScript.make_volume()
	## Offline paints in local space; origin applied at commit time.
	origin = Vector3i.ZERO


func fill_box(min_v: Vector3i, max_v: Vector3i, material_id: int) -> void:
	## Inclusive min, exclusive max (local — callers use local).
	if min_v.x >= max_v.x or min_v.y >= max_v.y or min_v.z >= max_v.z:
		return
	if volume != null:
		volume.fill_box(min_v, max_v, material_id)
		return
	if tool == null:
		push_error("CityBrush.fill_box: no tool or volume")
		return
	tool.mode = VoxelTool.MODE_SET
	tool.value = material_id
	var a := min_v + origin
	var b := max_v + origin - Vector3i.ONE
	tool.do_box(a, b)


func set_vox(pos: Vector3i, material_id: int) -> void:
	if volume != null:
		volume.set_vox(pos, material_id)
		return
	if tool == null:
		push_error("CityBrush.set_vox: no tool or volume")
		return
	tool.set_voxel(pos + origin, material_id)


func get_vox(pos: Vector3i) -> int:
	if volume != null:
		return int(volume.get_vox(pos))
	if tool == null:
		return 0
	return tool.get_voxel(pos + origin)


func column(x: int, z: int, y0: int, y1: int, material_id: int) -> void:
	fill_box(Vector3i(x, y0, z), Vector3i(x + 1, y1, z + 1), material_id)


## Euclidean disk at a single Y (inclusive radius in voxels).
func fill_disk(cx: int, cz: int, y: int, radius: int, material_id: int) -> void:
	if radius < 0:
		return
	var r2 := radius * radius
	for z in range(cz - radius, cz + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			var dx := x - cx
			var dz := z - cz
			if dx * dx + dz * dz <= r2:
				set_vox(Vector3i(x, y, z), material_id)


## Solid cylinder from y0 inclusive to y1 exclusive.
func fill_cylinder(cx: int, cz: int, y0: int, y1: int, radius: int, material_id: int) -> void:
	if y0 >= y1 or radius < 0:
		return
	for y in range(y0, y1):
		fill_disk(cx, cz, y, radius, material_id)


## Hollow cylinder shell. Inner void uses Euclidean radius `radius - wall_thick`.
## When `hollow_inner` is false, behaves like fill_cylinder.
func fill_cylinder_shell(
	cx: int,
	cz: int,
	y0: int,
	y1: int,
	radius: int,
	material_id: int,
	hollow_inner: bool = true,
	wall_thick: int = 1
) -> void:
	if y0 >= y1 or radius < 0:
		return
	if not hollow_inner or wall_thick <= 0:
		fill_cylinder(cx, cz, y0, y1, radius, material_id)
		return
	var outer2 := radius * radius
	var inner_r := maxi(0, radius - wall_thick)
	var inner2 := inner_r * inner_r
	for y in range(y0, y1):
		for z in range(cz - radius, cz + radius + 1):
			for x in range(cx - radius, cx + radius + 1):
				var dx := x - cx
				var dz := z - cz
				var d2 := dx * dx + dz * dz
				if d2 <= outer2 and d2 > inner2:
					set_vox(Vector3i(x, y, z), material_id)


## Solid ellipsoid centred on `center` with per-axis radii.
func fill_ellipsoid(center: Vector3i, radii: Vector3i, material_id: int) -> void:
	if radii.x <= 0 or radii.y <= 0 or radii.z <= 0:
		return
	var fx := float(radii.x)
	var fy := float(radii.y)
	var fz := float(radii.z)
	for y in range(center.y - radii.y, center.y + radii.y + 1):
		var ny := float(y - center.y) / fy
		for z in range(center.z - radii.z, center.z + radii.z + 1):
			var nz := float(z - center.z) / fz
			for x in range(center.x - radii.x, center.x + radii.x + 1):
				var nx := float(x - center.x) / fx
				if nx * nx + ny * ny + nz * nz <= 1.0:
					set_vox(Vector3i(x, y, z), material_id)


## Hollow ellipsoid: only the outer rind is painted so the interior stays walkable.
func fill_ellipsoid_shell(
	center: Vector3i, radii: Vector3i, material_id: int, wall_thick: int = 2
) -> void:
	if radii.x <= 0 or radii.y <= 0 or radii.z <= 0:
		return
	if wall_thick <= 0:
		fill_ellipsoid(center, radii, material_id)
		return
	var fx := float(radii.x)
	var fy := float(radii.y)
	var fz := float(radii.z)
	var ix := maxf(fx - float(wall_thick), 0.001)
	var iy := maxf(fy - float(wall_thick), 0.001)
	var iz := maxf(fz - float(wall_thick), 0.001)
	for y in range(center.y - radii.y, center.y + radii.y + 1):
		var dy := float(y - center.y)
		for z in range(center.z - radii.z, center.z + radii.z + 1):
			var dz := float(z - center.z)
			for x in range(center.x - radii.x, center.x + radii.x + 1):
				var dx := float(x - center.x)
				var outer := (dx / fx) * (dx / fx) + (dy / fy) * (dy / fy) + (dz / fz) * (dz / fz)
				if outer > 1.0:
					continue
				var inner := (dx / ix) * (dx / ix) + (dy / iy) * (dy / iy) + (dz / iz) * (dz / iz)
				if inner > 1.0:
					set_vox(Vector3i(x, y, z), material_id)


## Thin ring: voxels with distance in (radius - thick, radius] (Euclidean).
func fill_disk_ring(
	cx: int, cz: int, y: int, radius: int, thick: int, material_id: int
) -> void:
	if radius < 0 or thick <= 0:
		return
	var outer2 := radius * radius
	var inner_r := maxi(0, radius - thick)
	var inner2 := inner_r * inner_r
	for z in range(cz - radius, cz + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			var dx := x - cx
			var dz := z - cz
			var d2 := dx * dx + dz * dz
			if d2 <= outer2 and d2 > inner2:
				set_vox(Vector3i(x, y, z), material_id)
