extends SceneTree

const PedRoadMapScript := preload("res://scripts/city/ped_roadmap.gd")
const CrowdDirectorScript := preload("res://scripts/city/crowd_director.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var map: PedRoadMap = PedRoadMapScript.new()
	map.voxel_size = 2.0
	map.stride_vox = 1
	map.ground_y = 1.0
	for z in range(20):
		for x in range(20):
			var idx := map.positions.size()
			map._cell_to_node[Vector2i(x, z)] = idx
			map.positions.append(Vector3(float(x) * 2.0, 1.0, float(z) * 2.0))
			map.neighbors.append(PackedInt32Array())
	map.node_count = map.positions.size()
	var offsets: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	for cell: Variant in map._cell_to_node.keys():
		var c: Vector2i = cell
		var a: int = int(map._cell_to_node[c])
		for off in offsets:
			var nkey := c + off
			if not map._cell_to_node.has(nkey):
				continue
			var b: int = int(map._cell_to_node[nkey])
			if a < b:
				var na: PackedInt32Array = map.neighbors[a]
				na.append(b)
				map.neighbors[a] = na
				var nb: PackedInt32Array = map.neighbors[b]
				nb.append(a)
				map.neighbors[b] = nb

	var cam := Camera3D.new()
	cam.position = Vector3(20, 2, 20)
	root.add_child(cam)

	var crowd: CrowdDirector = CrowdDirectorScript.new()
	crowd.pedestrian_count = 1000
	crowd.near_distance = 12.0
	crowd.mid_distance = 40.0
	crowd.decision_min_sec = 10.0
	crowd.decision_max_sec = 60.0
	root.add_child(crowd)
	crowd.setup(map, cam, 7)

	if crowd.agent_count() != 1000:
		push_error("FAIL agent_count=%d" % crowd.agent_count())
		quit(1)
		return

	print("PASS crowd director 1000 with roadmap")
	OS.kill(OS.get_process_id())
