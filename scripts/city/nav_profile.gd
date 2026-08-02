## One agent body, expressed as a query-time filter over the shared span field.
##
## Clearance and headroom are baked once per district, so a minion and a giant read the
## same field and differ only here. Field names and units mirror `Profile` in
## native/city_voxel/src/nav.rs — `to_spec()` renames, it never converts.
class_name NavProfile
extends RefCounted

## Self-preload so the static factories type-check before class_cache picks us up.
const _Self := preload("res://scripts/city/nav_profile.gd")

## Registered ids. Agents pass these to NavService; the Rust world keys profiles by int.
enum Id {
	PEDESTRIAN = 0,
	UNDEAD = 1,
	GIANT = 2,
	CAR = 3,
	MONSTER = 4,
	MONSTER_BREAKER = 5,
}

var id: int = Id.PEDESTRIAN
var display_name: String = "pedestrian"

## Required geodesic clearance in cells — the body radius. Saturates at 15 in the bake.
var radius_cells: int = 1
## Required free cells above the surface — the body height. Saturates at 40 in the bake.
var height_cells: int = 4
## Largest upward surface difference walkable without a link, in voxels.
var max_step: float = 1.25
## Largest downward surface difference walkable without a link, in voxels.
var max_drop: float = 3.0
## Deepest water the body can wade through, in cells.
var max_wade: int = 1
var can_swim: bool = false
var can_climb: bool = false
var can_jump: bool = false
## Destructible fabric becomes a priced routing decision instead of a dead end.
var can_break: bool = false
## Cost multiplier per VoxelMaterial id. Length tracks NavSolidity.TABLE_SIZE; never below 1.0.
var surface_cost: PackedFloat32Array = PackedFloat32Array()


## The Dictionary NativeNavWorld.register_profile takes.
func to_spec() -> Dictionary:
	return {
		"radius_cells": radius_cells,
		"height_cells": height_cells,
		"max_step_vox": max_step,
		"max_drop_vox": max_drop,
		"max_wade_cells": max_wade,
		"can_swim": can_swim,
		"can_climb": can_climb,
		"can_jump": can_jump,
		"can_break": can_break,
		"surface_cost": surface_cost,
	}


func duplicate_as(new_id: int, new_name: String) -> _Self:
	var out: _Self = _Self.new()
	out.id = new_id
	out.display_name = new_name
	out.radius_cells = radius_cells
	out.height_cells = height_cells
	out.max_step = max_step
	out.max_drop = max_drop
	out.max_wade = max_wade
	out.can_swim = can_swim
	out.can_climb = can_climb
	out.can_jump = can_jump
	out.can_break = can_break
	out.surface_cost = surface_cost.duplicate()
	return out


## Everything NavService registers at boot.
static func defaults() -> Array[_Self]:
	return [pedestrian(), undead(), giant(), car(), monster(), monster_breaker()]


## A person: 1 m across, 2 m tall, steps a curb, drops off a kerb but not a roof.
static func pedestrian() -> _Self:
	var p: _Self = _Self.new()
	p.id = Id.PEDESTRIAN
	p.display_name = "pedestrian"
	p.radius_cells = 1
	p.height_cells = 4
	p.max_step = 1.25
	p.max_drop = 3.0
	p.max_wade = 1
	## Peds belong on the pavement; carriageway materials are dearer rather than the
	## pavement being cheaper, because costs below 1.0 break the search heuristic.
	p.surface_cost = _surface_costs({
		VoxelMaterial.ROAD: 2.5,
		VoxelMaterial.ASPHALT: 2.5,
		VoxelMaterial.ROAD_LINE: 2.5,
		VoxelMaterial.CROSSWALK: 1.25,
		VoxelMaterial.PARK: 1.125,
		VoxelMaterial.DIRT: 1.25,
		VoxelMaterial.GRAVEL: 1.25,
		VoxelMaterial.PLANTER: 1.5,
		VoxelMaterial.ROOF: 2.0,
		VoxelMaterial.ROOF_CLAY: 2.0,
	})
	return p


## Minions and mages: the same body as a person, but they scale facades and take drops
## a pedestrian would refuse, and they have no opinion about pavement.
static func undead() -> _Self:
	var p: _Self = _Self.new()
	p.id = Id.UNDEAD
	p.display_name = "undead"
	p.radius_cells = 1
	p.height_cells = 4
	p.max_step = 1.5
	p.max_drop = 6.0
	p.max_wade = 2
	p.can_climb = true
	p.can_jump = true
	p.surface_cost = _surface_costs({})
	return p


## undead_unit.gd at character_scale 10. The hit volume is 5.5 m across (0.55 m x 10), so
## the footprint is what keeps a giant out of alleys; the collision capsule stays clamped
## at COL_HEIGHT_MAX_M = 3.4 m so headroom only has to clear that plus margin. can_break
## turns "walk through that wall" into a routing decision with a price.
static func giant() -> _Self:
	var p: _Self = _Self.new()
	p.id = Id.GIANT
	p.display_name = "giant"
	p.radius_cells = 11
	p.height_cells = 8
	p.max_step = 2.0
	p.max_drop = 8.0
	p.max_wade = 6
	p.can_break = true
	p.surface_cost = _surface_costs({})
	return p


## The Quaternius Big monsters at native scale: 2.7-4.0 m of body, so 2 m across and 3.5 m
## of headroom. The rung between UNDEAD (1 m wide, 2 m headroom) and GIANT (11 m wide, known
## not to fit indoors) that these bodies had no profile for.
##
## No climbing: a two-metre body pulling itself up a facade on the climb links a minion uses
## is not what those links were baked for. It keeps `can_jump` so it can still take the gap
## links, and it cannot break, so a wall is a wall — being blocked is a ladder report, which
## is the behaviour this project wants over a monster that quietly walks through masonry.
##
## `max_drop` has to clear the link envelope's `min_drop` of 1.7 voxels: a body that walks
## less than that meets descents it can neither walk down nor take a link for, which is the
## bug the `car()` profile shipped with.
static func monster() -> _Self:
	var p: _Self = _Self.new()
	p.id = Id.MONSTER
	p.display_name = "monster"
	p.radius_cells = 2
	p.height_cells = 7
	p.max_step = 1.75
	p.max_drop = 6.0
	p.max_wade = 3
	p.can_jump = true
	p.surface_cost = _surface_costs({})
	return p


## `monster()`, except destructible fabric is a priced route instead of a dead end. For bodies
## whose aura chews terrain as they walk: on the plain monster profile the navigator hands a
## walled-in body no corridor at all, so it never takes the step the aura fires on — the cage
## boss stood still in its cave forever. Breaking also wires up the entombment dig-out, which
## `NavAgent._report_trapped` only offers to a `can_break` profile.
static func monster_breaker() -> _Self:
	var p: _Self = monster().duplicate_as(Id.MONSTER_BREAKER, "monster_breaker")
	p.can_break = true
	return p


## A car: 2.3 m across, no climbing, no jumping, and it drowns. `max_step` clears the
## painted kerb line, which `voxel_block_library` gives a 0.4 collision top while the
## asphalt and pavement either side of it are full cells — a 0.3 m gutter dip that runs
## between every street cell's carriageway and the asphalt of the intersection it meets, so
## a car that could not step it would be confined to the cell it spawned in. Everything off
## the carriageway is priced up rather than forbidden: CarLaneGraph decides where a car may
## go, and the cost only settles how it gets between two lane points.
static func car() -> _Self:
	var p: _Self = _Self.new()
	p.id = Id.CAR
	p.display_name = "car"
	p.radius_cells = 2
	p.height_cells = 4
	p.max_step = 0.75
	## A metre is a hard landing for a saloon and half of one would be kinder, but drop links
	## do not start until 1.7 voxels: a car that walked less than that would meet descents it
	## could neither drive down nor take a link for, and would sit on the ledge forever.
	p.max_drop = 2.0
	p.max_wade = 0
	## Fractal glow / sculpture bands are a hard no-go for traffic (edge roads only).
	## Cost must beat a short cut across the plaza vs driving around the stubs.
	##
	## Everything off the carriageway is priced well above it, because the corridor is what
	## decides where between two lane points the car goes and VehicleMotor's lane glue steps
	## aside once the corridor detours far enough: a path that pays for pavement is a path the
	## car will be held on. CURB is the exception and stays cheap — the painted kerb line runs
	## between every cell's carriageway and the asphalt of the junction it meets, so a car
	## crosses one on any normal drive.
	var car_costs := {
		VoxelMaterial.SIDEWALK: 8.0,
		VoxelMaterial.CURB: 2.0,
		VoxelMaterial.PLAZA: 8.0,
		VoxelMaterial.TILES: 8.0,
		VoxelMaterial.PARK: 12.0,
		VoxelMaterial.DIRT: 8.0,
		VoxelMaterial.GRAVEL: 6.0,
		VoxelMaterial.GRAVE_PATH: 12.0,
		VoxelMaterial.GRAVE_SOIL: 12.0,
		VoxelMaterial.CAVE_FLOOR: 12.0,
		VoxelMaterial.ROOF: 16.0,
		VoxelMaterial.ROOF_CLAY: 16.0,
		VoxelMaterial.FRACTAL_GLOW: 16.0,
		VoxelMaterial.FRACTAL_INTERIOR: 16.0,
	}
	for band_i in range(VoxelMaterial.FRACTAL_BAND_COUNT):
		car_costs[VoxelMaterial.fractal_band(band_i)] = 16.0
	p.surface_cost = _surface_costs(car_costs)
	return p


## Multipliers indexed by VoxelMaterial id, defaulting to 1.0.
static func _surface_costs(penalties: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(NavSolidity.TABLE_SIZE)
	out.fill(1.0)
	for key: Variant in penalties.keys():
		var mat: int = key
		var cost: float = float(penalties[key])
		if cost < 1.0:
			push_error(
				"NavProfile: surface cost %.3f for material %d is below 1.0" % [cost, mat]
			)
		if mat < 0 or mat >= NavSolidity.TABLE_SIZE:
			push_error("NavProfile: surface cost for material %d is out of range" % mat)
			continue
		out[mat] = cost
	return out
