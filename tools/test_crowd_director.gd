extends SceneTree

const PedRoadMapScript := preload("res://scripts/city/ped_roadmap.gd")
const NavGraphScript := preload("res://scripts/city/nav_graph.gd")
const CrowdDirectorScript := preload("res://scripts/city/crowd_director.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var graph: NavGraph = NavGraphScript.new()
	var cell_to_node: Dictionary = {}
	for z in range(20):
		for x in range(20):
			cell_to_node[Vector2i(x, z)] = graph.add_node(Vector3(float(x) * 2.0, 1.0, float(z) * 2.0))
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
	graph.finalize(2.0)

	var map: PedRoadMap = PedRoadMapScript.new()
	map.bind_graph(graph)

	var cam := Camera3D.new()
	cam.position = Vector3(20, 2, 20)
	root.add_child(cam)

	var crowd: CrowdDirector = CrowdDirectorScript.new()
	crowd.pedestrian_count = 1000
	crowd.render_distance = 12.0
	crowd.stay_min_sec = 1.0
	crowd.stay_max_sec = 2.0
	root.add_child(crowd)
	crowd.setup(map, cam, 7)

	if crowd.agent_count() != 1000:
		push_error("FAIL agent_count=%d" % crowd.agent_count())
		quit(1)
		return

	print("PASS crowd director 1000 with roadmap")
	quit(0)
