## Stamps a BuildCatalog recipe into the live VoxelTerrain at a world hit.
## Builds are ephemeral — they vanish when the district streams out and rebakes.
class_name BuildPlacer
extends RefCounted


static func place(
	terrain: VoxelTerrain,
	tool: VoxelTool,
	brush: CityBrush,
	recipe: BuildCatalog.Recipe,
	hit_world: Vector3,
	player_world: Vector3
) -> int:
	if terrain == null or tool == null or brush == null:
		push_error("BuildPlacer.place: terrain/tool/brush required")
		return 0
	if recipe == null or recipe.voxels.is_empty():
		push_error("BuildPlacer.place: empty recipe")
		return 0

	var local := terrain.to_local(hit_world)
	## Nudge slightly into the surface so floor() lands on the cell we clicked,
	## not the air cell above a sidewalk top.
	var into := local - Vector3(0.0, 0.02, 0.0)
	var base := Vector3i(int(floor(into.x)), int(floor(into.y)), int(floor(into.z)))
	base.y = _surface_y(tool, base) + 1
	var facing := _facing_toward(player_world - hit_world)

	var written := 0
	tool.channel = VoxelBuffer.CHANNEL_TYPE
	## One recipe stamp is one logical edit.
	brush.begin_edit()
	var n := recipe.voxels.size() / 4
	for i in range(n):
		var o := i * 4
		var rot := _rotate(
			Vector3i(recipe.voxels[o], recipe.voxels[o + 1], recipe.voxels[o + 2]),
			facing
		)
		var mat := recipe.voxels[o + 3]
		var vox := Vector3i(base.x + rot.x, base.y + rot.y, base.z + rot.z)
		var existing := int(tool.get_voxel(vox))
		if existing == VoxelMaterial.BEDROCK:
			continue
		brush.set_vox(vox, mat)
		written += 1
	brush.end_edit()
	return written


static func _surface_y(tool: VoxelTool, hint: Vector3i) -> int:
	## Find the topmost solid cell in this column near the aim hint. Search up a
	## little (curb / lip) then down a long way (aimed at a facade mid-wall).
	var start := hint.y + 2
	for y in range(start, hint.y - 48, -1):
		var here := int(tool.get_voxel(Vector3i(hint.x, y, hint.z)))
		if here == VoxelMaterial.AIR or here == VoxelMaterial.LEAVES or here == VoxelMaterial.WATER:
			continue
		if not VoxelMaterial.is_solid(here):
			continue
		## Prefer outdoor ground / roofs — skip if the cell above is still solid
		## building fabric (we're inside a wall column).
		var above := int(tool.get_voxel(Vector3i(hint.x, y + 1, hint.z)))
		if above != VoxelMaterial.AIR and above != VoxelMaterial.LEAVES and above != VoxelMaterial.WATER:
			if VoxelMaterial.is_building_fabric(here) and VoxelMaterial.is_building_fabric(above):
				continue
		return y
	return hint.y


static func _facing_toward(to_player: Vector3) -> int:
	## Snap the horizontal vector from build → player to a cardinal. Recipe −Z
	## (the "front") is rotated to point along that cardinal.
	to_player.y = 0.0
	if to_player.length_squared() < 0.0001:
		return 1
	if absf(to_player.x) > absf(to_player.z):
		return 2 if to_player.x > 0.0 else 3
	return 0 if to_player.z > 0.0 else 1


static func _rotate(o: Vector3i, facing: int) -> Vector3i:
	## facing: 0=+Z, 1=-Z, 2=+X, 3=-X — world direction recipe −Z should face.
	match facing:
		0:
			return Vector3i(-o.x, o.y, -o.z)
		1:
			return o
		2:
			return Vector3i(-o.z, o.y, o.x)
		_:
			return Vector3i(o.z, o.y, -o.x)
