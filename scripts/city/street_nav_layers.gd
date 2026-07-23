## Builds road + sidewalk nav graphs from DistrictPlanner topology (not voxel sampling).
## Crossings are explicit ped edges across the carriageway; cars yield via crossing occupancy.
class_name StreetNavLayers
extends RefCounted

const NavGraphScript := preload("res://scripts/city/nav_graph.gd")

var road: NavGraph
var ped: NavGraph
## crossings[i] = { "id": int, "center": Vector3, "radius": float }
var crossings: Array = []
## Live ped occupancy: crossing_id -> count.
var crossing_ped_count: Dictionary = {}
## Compact list of currently occupied crossing ids (for O(occupied) yield checks).
var occupied_crossing_ids: PackedInt32Array = PackedInt32Array()
## Spatial hash: Vector2i grid cell -> PackedInt32Array of crossing indices into `crossings`.
var _crossing_grid: Dictionary = {}
var _grid_cell_m: float = 4.0

var cell_size: int = 10
var voxel_size: float = 0.5
var ground_thickness: int = 1
var ground_y: float = 1.0


func is_ready() -> bool:
	return road != null and ped != null and not road.is_empty() and not ped.is_empty()


func build(
	planner: DistrictPlanner,
	tool: VoxelTool,
	p_cell_size: int,
	p_ground_thickness: int,
	vs: float
) -> void:
	cell_size = p_cell_size
	ground_thickness = p_ground_thickness
	voxel_size = vs
	ground_y = float(ground_thickness + 1) * vs
	crossings.clear()
	crossing_ped_count.clear()
	occupied_crossing_ids = PackedInt32Array()
	_crossing_grid.clear()
	road = NavGraphScript.new()
	ped = NavGraphScript.new()

	if planner == null:
		push_error("StreetNavLayers: planner is null")
		return

	tool.channel = VoxelBuffer.CHANNEL_TYPE
	var road_key_to_node: Dictionary = {}  # Vector2i(cx,cz) -> road node
	# Sidewalk keys: Vector3i(cx, cz, side) side: 0=N 1=S 2=E 3=W
	var sw_key_to_node: Dictionary = {}

	for cz in range(planner.cells_z):
		for cx in range(planner.cells_x):
			if not LandUse.is_road(planner.tag_at(cx, cz)):
				continue
			var center := _cell_center(cx, cz)
			center.y = _snap_y(tool, center)
			var r_idx := road.add_node(center)
			road_key_to_node[Vector2i(cx, cz)] = r_idx

			var horiz := LandUse.is_road(planner.tag_at(cx - 1, cz)) or LandUse.is_road(planner.tag_at(cx + 1, cz))
			var vert := LandUse.is_road(planner.tag_at(cx, cz - 1)) or LandUse.is_road(planner.tag_at(cx, cz + 1))
			var intersection := horiz and vert
			if intersection:
				_add_corner_sidewalks(tool, cx, cz, sw_key_to_node)
			elif horiz and not vert:
				_add_sidewalk(tool, cx, cz, 0, sw_key_to_node)  # N
				_add_sidewalk(tool, cx, cz, 1, sw_key_to_node)  # S
			else:
				# NS or stub
				_add_sidewalk(tool, cx, cz, 2, sw_key_to_node)  # E
				_add_sidewalk(tool, cx, cz, 3, sw_key_to_node)  # W

	# Link road cells to 4-neighbors.
	var road_offsets: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	for key: Variant in road_key_to_node.keys():
		var c: Vector2i = key
		var a: int = int(road_key_to_node[c])
		for off: Vector2i in road_offsets:
			var nkey: Vector2i = c + off
			if not road_key_to_node.has(nkey):
				continue
			var b: int = int(road_key_to_node[nkey])
			if a < b:
				road.link(a, b)

	# Link sidewalks along street runs + around intersections.
	_link_sidewalk_runs(planner, sw_key_to_node)
	_link_intersection_sidewalks(planner, sw_key_to_node)
	_add_crossings(planner, tool, road_key_to_node, sw_key_to_node)

	road.finalize(vs)
	ped.finalize(vs)
	ground_y = road.ground_y if not road.is_empty() else ped.ground_y
	_apply_crossing_tags()
	_rebuild_crossing_grid()
	_validate()


func refresh_crossing_occupancy_agents(agents: Array) -> void:
	## O(agents × local crossings). Never scan every ped against every crossing.
	crossing_ped_count.clear()
	occupied_crossing_ids = PackedInt32Array()
	if agents.is_empty() or crossings.is_empty():
		return
	for agent_v: Variant in agents:
		var pos: Vector3 = agent_v.position
		var gk := _grid_key(pos.x, pos.z)
		if not _crossing_grid.has(gk):
			continue
		var idxs: PackedInt32Array = _crossing_grid[gk]
		for ci in idxs:
			var d: Dictionary = crossings[ci]
			var center: Vector3 = d["center"]
			var radius: float = float(d["radius"])
			var dx := pos.x - center.x
			var dz := pos.z - center.z
			if dx * dx + dz * dz > radius * radius:
				continue
			var cid2 := int(d["id"])
			crossing_ped_count[cid2] = int(crossing_ped_count.get(cid2, 0)) + 1
	for cid3: Variant in crossing_ped_count.keys():
		if int(crossing_ped_count[cid3]) > 0:
			occupied_crossing_ids.append(int(cid3))


## Deprecated O(n×m) API — kept for tests; prefer refresh_crossing_occupancy_agents.
func refresh_crossing_occupancy(ped_positions: Array) -> void:
	var fake: Array = []
	fake.resize(ped_positions.size())
	for i in range(ped_positions.size()):
		fake[i] = {"position": ped_positions[i]}
	refresh_crossing_occupancy_agents(fake)


func is_crossing_occupied(crossing_id: int) -> bool:
	return int(crossing_ped_count.get(crossing_id, 0)) > 0


func yielding_for_car(car_pos: Vector3, next_waypoint: Vector3) -> bool:
	## True if the car should stop: close to an occupied crossing mid (carriageway only).
	if occupied_crossing_ids.is_empty():
		return false
	var approach := 2.25
	for oid in occupied_crossing_ids:
		# Crossing ids are assigned as append indices during build.
		if oid < 0 or oid >= crossings.size():
			continue
		var d: Dictionary = crossings[oid]
		var center: Vector3 = d["center"]
		var radius: float = float(d["radius"])
		var stop_r := radius + approach
		var stop_r2 := stop_r * stop_r
		var dx := car_pos.x - center.x
		var dz := car_pos.z - center.z
		if dx * dx + dz * dz > stop_r2:
			continue
		var wp_r := stop_r + 1.0
		var wx := next_waypoint.x - center.x
		var wz := next_waypoint.z - center.z
		if wx * wx + wz * wz <= wp_r * wp_r:
			return true
	return false


func _grid_key(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / _grid_cell_m)), int(floor(z / _grid_cell_m)))


func _rebuild_crossing_grid() -> void:
	_crossing_grid.clear()
	for i in range(crossings.size()):
		var d: Dictionary = crossings[i]
		var center: Vector3 = d["center"]
		var radius: float = float(d["radius"])
		# Index crossing into every grid cell its radius can touch.
		var min_x := int(floor((center.x - radius) / _grid_cell_m))
		var max_x := int(floor((center.x + radius) / _grid_cell_m))
		var min_z := int(floor((center.z - radius) / _grid_cell_m))
		var max_z := int(floor((center.z + radius) / _grid_cell_m))
		for gx in range(min_x, max_x + 1):
			for gz in range(min_z, max_z + 1):
				var key := Vector2i(gx, gz)
				var bucket: PackedInt32Array
				if _crossing_grid.has(key):
					bucket = _crossing_grid[key]
				else:
					bucket = PackedInt32Array()
				bucket.append(i)
				_crossing_grid[key] = bucket


func _cell_origin_vox(cx: int, cz: int) -> Vector2i:
	return Vector2i(cx * cell_size, cz * cell_size)


func _cell_center(cx: int, cz: int) -> Vector3:
	var ox := float(cx * cell_size) + float(cell_size) * 0.5
	var oz := float(cz * cell_size) + float(cell_size) * 0.5
	return Vector3(ox * voxel_size, ground_y, oz * voxel_size)


func _sidewalk_world(cx: int, cz: int, side: int) -> Vector3:
	## side: 0=N 1=S 2=E 3=W — center of the sidewalk band (~2 m).
	var o := _cell_origin_vox(cx, cz)
	var sw := clampi(int(round(2.0 / voxel_size)), 3, maxi(3, cell_size / 6))
	var x_vox := float(o.x) + float(cell_size) * 0.5
	var z_vox := float(o.y) + float(cell_size) * 0.5
	match side:
		0:  # North
			z_vox = float(o.y) + float(sw) * 0.5
		1:  # South
			z_vox = float(o.y + cell_size) - float(sw) * 0.5
		2:  # East (+X)
			x_vox = float(o.x + cell_size) - float(sw) * 0.5
		3:  # West (-X)
			x_vox = float(o.x) + float(sw) * 0.5
	return Vector3(x_vox * voxel_size, ground_y, z_vox * voxel_size)


func _add_sidewalk(tool: VoxelTool, cx: int, cz: int, side: int, sw_key_to_node: Dictionary) -> int:
	var key := Vector3i(cx, cz, side)
	if sw_key_to_node.has(key):
		return int(sw_key_to_node[key])
	var pos := _sidewalk_world(cx, cz, side)
	pos.y = _snap_y(tool, pos)
	var idx := ped.add_node(pos)
	sw_key_to_node[key] = idx
	return idx


func _add_corner_sidewalks(tool: VoxelTool, cx: int, cz: int, sw_key_to_node: Dictionary) -> void:
	# Four corner sidewalk pads at intersection.
	for side: int in [0, 1, 2, 3]:
		_add_sidewalk(tool, cx, cz, side, sw_key_to_node)


func _link_sidewalk_runs(planner: DistrictPlanner, sw_key_to_node: Dictionary) -> void:
	for cz in range(planner.cells_z):
		for cx in range(planner.cells_x):
			if not LandUse.is_road(planner.tag_at(cx, cz)):
				continue
			var horiz := LandUse.is_road(planner.tag_at(cx - 1, cz)) or LandUse.is_road(planner.tag_at(cx + 1, cz))
			var vert := LandUse.is_road(planner.tag_at(cx, cz - 1)) or LandUse.is_road(planner.tag_at(cx, cz + 1))
			var intersection := horiz and vert
			# Along +X
			if LandUse.is_road(planner.tag_at(cx + 1, cz)):
				if intersection or horiz:
					_try_link_sw(sw_key_to_node, Vector3i(cx, cz, 0), Vector3i(cx + 1, cz, 0))
					_try_link_sw(sw_key_to_node, Vector3i(cx, cz, 1), Vector3i(cx + 1, cz, 1))
			# Along +Z
			if LandUse.is_road(planner.tag_at(cx, cz + 1)):
				if intersection or vert:
					_try_link_sw(sw_key_to_node, Vector3i(cx, cz, 2), Vector3i(cx, cz + 1, 2))
					_try_link_sw(sw_key_to_node, Vector3i(cx, cz, 3), Vector3i(cx, cz + 1, 3))


func _link_intersection_sidewalks(planner: DistrictPlanner, sw_key_to_node: Dictionary) -> void:
	## Connect N/E/S/W sidewalk pads around an intersection so peds can turn the corner.
	for cz in range(planner.cells_z):
		for cx in range(planner.cells_x):
			if not LandUse.is_road(planner.tag_at(cx, cz)):
				continue
			var horiz := LandUse.is_road(planner.tag_at(cx - 1, cz)) or LandUse.is_road(planner.tag_at(cx + 1, cz))
			var vert := LandUse.is_road(planner.tag_at(cx, cz - 1)) or LandUse.is_road(planner.tag_at(cx, cz + 1))
			if not (horiz and vert):
				continue
			var sides: Array[int] = [0, 2, 1, 3]  # walk around
			for i in range(sides.size()):
				var a := Vector3i(cx, cz, sides[i])
				var b := Vector3i(cx, cz, sides[(i + 1) % sides.size()])
				_try_link_sw(sw_key_to_node, a, b)


func _add_crossings(
	planner: DistrictPlanner,
	tool: VoxelTool,
	road_key_to_node: Dictionary,
	sw_key_to_node: Dictionary
) -> void:
	var next_id := 0
	for cz in range(planner.cells_z):
		for cx in range(planner.cells_x):
			if not LandUse.is_road(planner.tag_at(cx, cz)):
				continue
			var horiz := LandUse.is_road(planner.tag_at(cx - 1, cz)) or LandUse.is_road(planner.tag_at(cx + 1, cz))
			var vert := LandUse.is_road(planner.tag_at(cx, cz - 1)) or LandUse.is_road(planner.tag_at(cx, cz + 1))
			var intersection := horiz and vert
			if not intersection and not _hash_crosswalk(cx, cz):
				continue
			# NS crossing: north sidewalk <-> south sidewalk
			if intersection or horiz:
				next_id = _make_crossing(
					tool, next_id, cx, cz, 0, 1, road_key_to_node, sw_key_to_node
				)
			# EW crossing: east <-> west
			if intersection or vert:
				next_id = _make_crossing(
					tool, next_id, cx, cz, 2, 3, road_key_to_node, sw_key_to_node
				)


func _make_crossing(
	tool: VoxelTool,
	crossing_id: int,
	cx: int,
	cz: int,
	side_a: int,
	side_b: int,
	road_key_to_node: Dictionary,
	sw_key_to_node: Dictionary
) -> int:
	var ka := Vector3i(cx, cz, side_a)
	var kb := Vector3i(cx, cz, side_b)
	if not sw_key_to_node.has(ka) or not sw_key_to_node.has(kb):
		return crossing_id
	var a: int = int(sw_key_to_node[ka])
	var b: int = int(sw_key_to_node[kb])
	# Midpoint on carriageway — ped path through crossing.
	var mid := (ped.positions[a] + ped.positions[b]) * 0.5
	mid.y = _snap_y(tool, mid)
	var mid_idx := ped.add_node(mid)
	ped.link(a, mid_idx)
	ped.link(mid_idx, b)

	var rkey := Vector2i(cx, cz)
	crossings.append({
		"id": crossing_id,
		# Tight radius on the carriageway mid only — sidewalk curb pads must NOT count as occupied.
		"center": mid,
		"radius": 1.6,
		"road_cell": rkey,
		"road_node": int(road_key_to_node.get(rkey, -1)),
		"ped_nodes": PackedInt32Array([a, mid_idx, b]),
	})
	crossing_ped_count[crossing_id] = 0
	return crossing_id + 1


func _apply_crossing_tags() -> void:
	for cinfo: Variant in crossings:
		var d: Dictionary = cinfo
		var cid := int(d["id"])
		var rnode := int(d.get("road_node", -1))
		if rnode >= 0:
			road.set_crossing_id(rnode, cid)
		# Tag only the carriageway mid for ped spawn/idle filtering.
		# Sidewalk curb pads stay normal sidewalk nodes.
		var pnodes: Variant = d.get("ped_nodes", PackedInt32Array())
		if typeof(pnodes) == TYPE_PACKED_INT32_ARRAY:
			var arr: PackedInt32Array = pnodes
			if arr.size() >= 2:
				# ped_nodes = [side_a, mid, side_b]
				ped.set_crossing_id(int(arr[1]), cid)


func _try_link_sw(sw_key_to_node: Dictionary, a: Vector3i, b: Vector3i) -> void:
	if not sw_key_to_node.has(a) or not sw_key_to_node.has(b):
		return
	var ia: int = int(sw_key_to_node[a])
	var ib: int = int(sw_key_to_node[b])
	if ia < ib:
		ped.link(ia, ib)


func _snap_y(tool: VoxelTool, world: Vector3) -> float:
	var x := clampi(int(floor(world.x / voxel_size)), 0, 100000)
	var z := clampi(int(floor(world.z / voxel_size)), 0, 100000)
	# Prefer authored ground thickness; fall back to scan.
	var y := ground_thickness
	var mat := tool.get_voxel(Vector3i(x, y, z))
	if mat == VoxelMaterial.AIR:
		for yy in range(ground_thickness + 4, maxi(ground_thickness - 2, 0), -1):
			if tool.get_voxel(Vector3i(x, yy, z)) != VoxelMaterial.AIR:
				y = yy
				break
	return float(y + 1) * voxel_size


func _hash_crosswalk(cx: int, cz: int) -> bool:
	## Sparse mid-block crossings (matches generator intent roughly).
	return ((cx * 17 + cz * 31) % 7) == 0


func _validate() -> void:
	if road.is_empty():
		push_error("StreetNavLayers: road graph empty")
		return
	if ped.is_empty():
		push_error("StreetNavLayers: sidewalk graph empty")
		return
	if road.edge_count < maxi(road.node_count / 2, 1):
		push_error(
			"StreetNavLayers: road edges too few (nodes=%d edges=%d)"
			% [road.node_count, road.edge_count]
		)
	if ped.edge_count < maxi(ped.node_count / 2, 1):
		push_error(
			"StreetNavLayers: ped edges too few (nodes=%d edges=%d)"
			% [ped.node_count, ped.edge_count]
		)
	var road_ratio := road.largest_component_ratio()
	var ped_ratio := ped.largest_component_ratio()
	if road_ratio < 0.55:
		push_error(
			"StreetNavLayers: road graph fragmented (largest=%.2f nodes=%d comps=%d)"
			% [road_ratio, road.node_count, road.component_count]
		)
	if ped_ratio < 0.40:
		push_error(
			"StreetNavLayers: ped graph fragmented (largest=%.2f nodes=%d comps=%d)"
			% [ped_ratio, ped.node_count, ped.component_count]
		)
	if crossings.is_empty():
		push_error("StreetNavLayers: no crossings generated")
	print(
		"StreetNavLayers: road_nodes=%d road_edges=%d ped_nodes=%d ped_edges=%d crossings=%d road_comp=%.2f ped_comp=%.2f"
		% [
			road.node_count,
			road.edge_count,
			ped.node_count,
			ped.edge_count,
			crossings.size(),
			road_ratio,
			ped_ratio,
		]
	)
