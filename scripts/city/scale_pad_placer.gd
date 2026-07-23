## Places grow / shrink ScalePads on plazas and a few sidewalk spots per district.
class_name ScalePadPlacer
extends Node3D

const ScalePadScript := preload("res://scripts/city/scale_pad.gd")
const KIND_GROW := 0
const KIND_SHRINK := 1

@export var max_pads_per_district: int = 4
@export var pad_radius: float = 3.2


func clear_pads() -> void:
	for c in get_children():
		c.queue_free()


func place_from_planner(
	planner: DistrictPlanner,
	cell_size: int,
	voxel_size: float,
	ground_thickness: int,
	origin_vox: Vector3i,
	district_seed: int
) -> void:
	clear_pads()
	if planner == null:
		return

	var gy := float(ground_thickness + 1) * voxel_size
	var oxw := float(origin_vox.x) * voxel_size
	var ozw := float(origin_vox.z) * voxel_size
	var rng := RandomNumberGenerator.new()
	rng.seed = int(district_seed) ^ 0x5CA1EAD

	var sites: Array = []  ## {pos: Vector3, kind: int}

	## Grand plaza → grow (easy landmark near spawn districts).
	if planner.grand_plaza.size.x > 0 and planner.grand_plaza.size.y > 0:
		sites.append({
			"pos": _rect_world_center(planner.grand_plaza, cell_size, voxel_size, oxw, ozw, gy),
			"kind": KIND_GROW,
		})

	## Satellite plazas → shrink / grow alternating.
	var si := 0
	for rect in planner.satellite_plazas:
		if sites.size() >= max_pads_per_district:
			break
		var k: int = KIND_SHRINK if (si % 2) == 0 else KIND_GROW
		sites.append({
			"pos": _rect_world_center(rect, cell_size, voxel_size, oxw, ozw, gy),
			"kind": k,
		})
		si += 1

	## Extra sidewalk / avenue spots so every district has both kinds when possible.
	_append_sidewalk_sites(sites, planner, cell_size, voxel_size, oxw, ozw, gy, rng)

	## Ensure at least one of each kind when we have 2+ slots filled.
	_balance_kinds(sites, rng)

	var placed := 0
	for site in sites:
		if placed >= max_pads_per_district:
			break
		_spawn_pad(site["pos"] as Vector3, int(site["kind"]))
		placed += 1

	print("ScalePadPlacer: pads=%d (district seed=%d)" % [placed, district_seed])


func _append_sidewalk_sites(
	sites: Array,
	planner: DistrictPlanner,
	cell_size: int,
	voxel_size: float,
	oxw: float,
	ozw: float,
	gy: float,
	rng: RandomNumberGenerator
) -> void:
	if planner.avenue_light_cells.is_empty():
		return
	var need := maxi(0, max_pads_per_district - sites.size())
	if need <= 0:
		return
	## Spread picks across the avenue list.
	var step := maxi(1, planner.avenue_light_cells.size() / (need + 2))
	var start := rng.randi_range(0, maxi(0, step - 1))
	var i := start
	var added := 0
	while i < planner.avenue_light_cells.size() and added < need:
		var cell: Vector2i = planner.avenue_light_cells[i]
		var wx := oxw + (float(cell.x) + 0.5) * float(cell_size) * voxel_size
		var wz := ozw + (float(cell.y) + 0.5) * float(cell_size) * voxel_size
		## Offset onto the curb / sidewalk band, not the road center.
		var ox := 3.4 if (cell.x % 2) == 0 else -3.4
		var oz := 3.4 if (cell.y % 2) == 0 else -3.4
		var pos := Vector3(wx + ox, gy, wz + oz)
		if not _too_close(sites, pos, pad_radius * 4.0):
			var k: int = KIND_SHRINK if (added % 2) == 0 else KIND_GROW
			sites.append({"pos": pos, "kind": k})
			added += 1
		i += step


func _balance_kinds(sites: Array, rng: RandomNumberGenerator) -> void:
	if sites.size() < 2:
		return
	var has_grow := false
	var has_shrink := false
	for s in sites:
		if int(s["kind"]) == KIND_GROW:
			has_grow = true
		else:
			has_shrink = true
	if has_grow and has_shrink:
		return
	var flip_i := rng.randi_range(0, sites.size() - 1)
	if not has_grow:
		sites[flip_i]["kind"] = KIND_GROW
	else:
		sites[flip_i]["kind"] = KIND_SHRINK


func _too_close(sites: Array, pos: Vector3, min_dist: float) -> bool:
	var min_d2 := min_dist * min_dist
	for s in sites:
		var p: Vector3 = s["pos"]
		var d := Vector2(p.x - pos.x, p.z - pos.z)
		if d.length_squared() < min_d2:
			return true
	return false


func _rect_world_center(
	rect: Rect2i,
	cell_size: int,
	voxel_size: float,
	oxw: float,
	ozw: float,
	gy: float
) -> Vector3:
	var cx := float(rect.position.x) + float(rect.size.x) * 0.5
	var cz := float(rect.position.y) + float(rect.size.y) * 0.5
	var wx := oxw + cx * float(cell_size) * voxel_size
	var wz := ozw + cz * float(cell_size) * voxel_size
	return Vector3(wx, gy, wz)


func _spawn_pad(origin: Vector3, kind: int) -> void:
	var pad: Node = ScalePadScript.new()
	pad.name = "ScalePadGrow" if kind == KIND_GROW else "ScalePadShrink"
	add_child(pad)
	pad.position = origin
	pad.call("configure", kind, pad_radius)
