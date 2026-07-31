## A district's street layout as the navigation stack uses it: pavement and crossings for
## pedestrians, directed lanes for cars.
##
## Both halves are annotation layers over the span field, not graphs anyone walks. They exist
## because the planner knows things the voxels cannot say — that this strip of asphalt is the
## eastbound lane, that this stretch of paint is a crossing and the one twenty metres along is
## not — and that knowledge is what keeps peds off the carriageway and cars on their own side
## of it while the span field does the actual routing.
##
## Nothing here reads voxels. The graphs this replaces sampled a column per node to find its
## height, which cost a scan of the whole street grid on the main thread and was wrong the
## moment anything was dug; heights now come from the span field, at the point of use.
class_name StreetTopology
extends RefCounted

const SidewalkMapScript := preload("res://scripts/city/sidewalk_map.gd")
const CarLaneGraphScript := preload("res://scripts/city/car_lane_graph.gd")

## Fraction of pavement nodes the largest connected piece must hold on an ordinary city tile.
const PAVEMENT_CONNECTED_MIN := 0.40

var sidewalks: SidewalkMap = null
var lanes: CarLaneGraph = null

## Themes whose streets are deliberately stubs around a feature, so a fragmented layout is the
## design rather than a bug.
var _allow_fragmented: bool = false


func is_ready() -> bool:
	return (
		sidewalks != null
		and lanes != null
		and not sidewalks.is_empty()
		and not lanes.is_empty()
	)


func build(
	planner: DistrictPlanner,
	cell_size: int,
	voxel_size: float,
	ground_thickness: int,
	origin_vox: Vector3i = Vector3i.ZERO
) -> void:
	sidewalks = SidewalkMapScript.new()
	lanes = CarLaneGraphScript.new()
	if planner == null:
		push_error("StreetTopology.build: no planner")
		return
	_allow_fragmented = _theme_is_fragmented(planner)
	## The deck sits one voxel above the ground slab. Only a starting guess: every consumer
	## snaps onto a span before it uses a point.
	var nominal_y := float(ground_thickness + 1) * voxel_size
	sidewalks.build(planner, cell_size, voxel_size, origin_vox, nominal_y)
	lanes.build(planner, cell_size, voxel_size, origin_vox, nominal_y)
	_validate()


## Special tiles get edge stubs instead of a grid, so their pavement is expected to come in
## disconnected pieces. Same set as `DistrictTheme.is_special`, and for the same reason.
static func _theme_is_fragmented(planner: DistrictPlanner) -> bool:
	if planner.theme == null:
		return false
	return planner.theme.is_special()


func _validate() -> void:
	if sidewalks.is_empty():
		push_error("StreetTopology: no pavement")
		return
	if lanes.is_empty():
		push_error("StreetTopology: no lanes")
		return
	if sidewalks.crossings.is_empty():
		push_error("StreetTopology: pavement with no crossings, so no ped ever crosses a road")
	var connected := sidewalks.largest_component_ratio()
	if not _allow_fragmented and connected < PAVEMENT_CONNECTED_MIN:
		push_error(
			"StreetTopology: pavement fragmented (largest=%.2f of %d nodes in %d pieces)"
			% [connected, sidewalks.node_count, sidewalks.component_count()]
		)
	print(
		"StreetTopology: pavement=%d edges=%d crossings=%d connected=%.2f lanes=%d turns=%d"
		% [
			sidewalks.node_count,
			sidewalks.edge_count,
			sidewalks.crossings.size(),
			connected,
			lanes.node_count,
			lanes.edge_count,
		]
	)
