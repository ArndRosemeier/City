extends SceneTree

const PedRoadMapScript := preload("res://scripts/city/ped_roadmap.gd")
const NavGraphScript := preload("res://scripts/city/nav_graph.gd")
const CrowdDirectorScript := preload("res://scripts/city/crowd_director.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Tiny fake city grid: walkable ring around a blocked center (building).
	var graph: NavGraph = NavGraphScript.new()
	var cell_to_node: Dictionary = {}
	for z in range(5):
		for x in range(5):
			if x == 2 and z == 2:
				continue  # building hole
			cell_to_node[Vector2i(x, z)] = graph.add_node(Vector3(float(x), 1.0, float(z)))
	for cell: Variant in cell_to_node.keys():
		var c: Vector2i = cell
		var a: int = int(cell_to_node[c])
		var offsets: Array[Vector2i] = [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
		]
		for off: Vector2i in offsets:
			var nkey: Vector2i = c + off
			if not cell_to_node.has(nkey):
				continue
			var b: int = int(cell_to_node[nkey])
			if a < b:
				graph.link(a, b)
	graph.finalize(1.0)

	var map: PedRoadMap = PedRoadMapScript.new()
	map.bind_graph(graph)

	var start := int(cell_to_node[Vector2i(0, 2)])
	var goal := int(cell_to_node[Vector2i(4, 2)])
	var path := map.find_path(start, goal)
	print("path_len=", path.size(), " nodes=", path)
	if path.size() < 5:
		push_error("FAIL path should go around the building, got len=%d" % path.size())
		quit(1)
		return
	for node_i in path:
		var p: Vector3 = map.positions[node_i]
		if is_equal_approx(p.x, 2.0) and is_equal_approx(p.z, 2.0):
			push_error("FAIL path cut through building cell")
			quit(1)
			return

	var cam := Camera3D.new()
	cam.position = Vector3(2, 3, 2)
	root.add_child(cam)

	var crowd: CrowdDirector = CrowdDirectorScript.new()
	crowd.pedestrian_count = 50
	crowd.render_distance = 5.0
	root.add_child(crowd)
	crowd.setup(map, cam, 3)
	if crowd.agent_count() != 50:
		push_error("FAIL agent_count")
		quit(1)
		return

	for agent in crowd._agents:
		agent.walk_tendency = 1.0
		crowd._decide(agent)
	for _i in range(90):
		await physics_frame

	var off_road := 0
	for agent2 in crowd._agents:
		var nearest := map.nearest_node(agent2.position)
		var d := map.positions[nearest].distance_to(agent2.position)
		if d > 1.25:
			off_road += 1
	print("off_road=", off_road)
	if off_road > 5:
		push_error("FAIL too many agents left the roadmap (%d)" % off_road)
		quit(1)
		return

	print("PASS ped roadmap routing")
	quit(0)
