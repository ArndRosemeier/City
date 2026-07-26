## Print the Hill planner road mask so connector stubs can be eyeballed.
extends SceneTree

const DistrictPlannerScript := preload("res://scripts/city/district_planner.gd")
const WORLD_SEED := 42


func _initialize() -> void:
	var coord := DistrictTheme.find_coord_for_theme(WORLD_SEED, DistrictTheme.HILL)
	var dseed := DistrictCoord.district_seed(WORLD_SEED, coord)
	var planner: DistrictPlanner = DistrictPlannerScript.new()
	planner.theme = DistrictTheme.make(DistrictTheme.HILL)
	planner.build(
		DistrictCoord.SIZE_X_VOX, DistrictCoord.SIZE_Z_VOX, dseed, DistrictCoord.CELL_SIZE, coord
	)
	print("coord=%s cells=%dx%d" % [coord, planner.cells_x, planner.cells_z])
	var roads := 0
	var mid := 0
	var x0 := planner.cells_x / 4
	var x1 := (planner.cells_x * 3) / 4
	var z0 := planner.cells_z / 4
	var z1 := (planner.cells_z * 3) / 4
	for z in range(planner.cells_z):
		var line := ""
		for x in range(planner.cells_x):
			var road := LandUse.is_road(planner.tag_at(x, z))
			line += "#" if road else "."
			if road:
				roads += 1
				if x >= x0 and x < x1 and z >= z0 and z < z1:
					mid += 1
		print("%02d %s" % [z, line])
	print("roads=%d mid_roads=%d (mid=%d..%d, %d..%d)" % [roads, mid, x0, x1, z0, z1])
	quit()
