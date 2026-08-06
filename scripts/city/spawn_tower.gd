## A destructible summoning spire: the voxel stamp, the combat host standing inside it, and the
## station that keeps summoning while it stands.
##
## Crypts and castle dungeon vaults used to summon out of a bare `Node3D` — a timer with no body,
## so a player who found the room had nothing to fight and no way to stop the tap. The spire is
## that timer given a target: authored hit points, a convert orb, the faction its station summons
## for, and one guaranteed recipe when the player brings it down.
##
## Everything it already summoned stays alive. Killing the spire closes the tap; it does not undo
## what came out of it.
class_name SpawnTower
extends Node3D

const SiegeTowerCatalogScript := preload("res://scripts/city/siege_tower_catalog.gd")

## Row in `siege_towers`. World-placed (`buildable: false`) — no gem price, never on a pad list.
const TOWER_ID := "spawn_spire"
## The host stands inside its own stamp, lifted off the plate the way a siege pad's is so the
## capsule is not half-sunk in the floor below it.
const HOST_LIFT_M := 0.15
## Cells probed downward from the station point for the plate the spire stands on. The crypt and
## the castle dungeon hand out their pad Y differently (air cell vs. floor slab), and a stamp
## anchored one cell out either floats or buries its base.
const FLOOR_PROBE_CELLS := 3
## Cells the summon point steps aside from the spire's centre. The stamp is a radius-1 diamond,
## so two cells puts fresh bodies on open floor instead of inside the mass.
const SUMMON_OFFSET_VOX := 2

## The combat body. Null before `raise`, freed on its own timer after death.
var unit: UndeadUnit = null

var _city: CityRoot = null
var _station: Node3D = null
var _cells: Array[Vector3i] = []


## Where a station under this spire should put fresh bodies: beside the mass, not in it.
static func summon_world(pad_world: Vector3, voxel_size: float) -> Vector3:
	return pad_world + Vector3(float(SUMMON_OFFSET_VOX) * voxel_size, 0.0, 0.0)


## Stamp the spire at `station_world` and stand its host up. `faction_id` is a `MonsterFaction.Id`
## — the side the station summons for, which is also the side that owns the tower.
##
## `station` is the summoner node; it is told to stop when the spire falls.
## Returns false when the district could not place it, having written nothing.
func raise(
	city: CityRoot,
	voxel_size: float,
	station_world: Vector3,
	faction_id: int,
	station: Node3D
) -> bool:
	if city == null or not is_instance_valid(city):
		push_error("SpawnTower.raise: a city is required to stamp and spawn")
		return false
	if station == null or not is_instance_valid(station):
		push_error("SpawnTower.raise: a spire with no station has nothing to guard")
		return false
	if voxel_size <= 0.0:
		push_error("SpawnTower.raise: bad voxel size %f" % voxel_size)
		return false
	var def: RefCounted = SiegeTowerCatalogScript.by_id(TOWER_ID) as RefCounted
	if def == null:
		return false
	var brush: CityBrush = city.voxel_brush()
	var terrain: VoxelTerrain = city.voxel_terrain()
	if brush == null or terrain == null:
		push_error("SpawnTower.raise: the city has no brush / terrain to stamp into")
		return false
	var pad_world := _plate_world(terrain, brush, station_world)
	if pad_world == Vector3.INF:
		return false
	_cells = SiegeTowerCatalogScript.stamp_at(terrain, brush, def, pad_world)
	if _cells.is_empty():
		push_error("SpawnTower.raise: stamp wrote nothing at %v" % pad_world)
		return false
	var muzzle_h := SiegeTowerCatalogScript.muzzle_height_m(def, voxel_size) - HOST_LIFT_M
	var hit_r := SiegeTowerCatalogScript.structure_hit_radius_m(def, voxel_size)
	unit = city.spawn_faction_tower_at(
		str(def.get("combat_id")),
		pad_world + Vector3(0.0, HOST_LIFT_M, 0.0),
		float(def.get("hp")),
		muzzle_h,
		hit_r,
		faction_id
	)
	if unit == null or not is_instance_valid(unit):
		push_error("SpawnTower.raise: no host body for '%s'" % str(def.get("combat_id")))
		_demolish(false)
		return false
	_city = city
	_station = station
	global_position = pad_world
	var ward := city.voxel_ward()
	if ward != null:
		ward.claim(unit.get_instance_id(), _cells)
	unit.died.connect(_on_unit_died)
	print(
		"SpawnTower: %s spire at %v (%d cells, %.0f hp)"
		% [station.name, pad_world, _cells.size(), float(def.get("hp"))]
	)
	return true


## District teardown. The stamp goes quietly (no debris storm on a tile the player left) and the
## host is dropped without a death, so nothing pays a recipe for an unload.
func clear() -> void:
	if unit != null and is_instance_valid(unit):
		if unit.died.is_connected(_on_unit_died):
			unit.died.disconnect(_on_unit_died)
	_demolish(false)
	if unit != null and is_instance_valid(unit) and _city != null and is_instance_valid(_city):
		_city.despawn_undead_unit(unit)
	unit = null
	_station = null


## The spire came down. Its stamp falls with it and the station stops summoning — but nothing it
## already put in the room is touched.
func _on_unit_died(_unit: UndeadUnit, _was_giant: bool) -> void:
	_demolish(true)
	if _station != null and is_instance_valid(_station):
		_station.call("stop_spawning")


func _demolish(scatter: bool) -> void:
	if _cells.is_empty():
		return
	var cells := _cells
	_cells = []
	if _city == null or not is_instance_valid(_city):
		return
	var ward := _city.voxel_ward()
	if ward != null and unit != null and is_instance_valid(unit):
		ward.release(unit.get_instance_id())
	_city.destroy_voxels_with_debris(cells, global_position, scatter)


## The solid plate the spire stands on, as the world point on that voxel's bottom face — the same
## anchor a siege pad hands `stamp_at`, which measures its muzzle from there.
##
## `stamp_at` builds on the air cell above whatever voxel the point it is handed sits in, so the
## anchor has to be the floor rather than the air a body spawns in. The crypt names the first air
## cell and a castle vault names the slab below it, so this reads the world instead of trusting
## either convention.
func _plate_world(
	terrain: VoxelTerrain, brush: CityBrush, station_world: Vector3
) -> Vector3:
	var tool: VoxelTool = brush.tool
	if tool == null:
		push_error("SpawnTower._plate_world: the brush has no tool to read with")
		return Vector3.INF
	var local := terrain.to_local(station_world)
	var vox := Vector3i(int(floor(local.x)), int(floor(local.y)), int(floor(local.z)))
	for step in range(FLOOR_PROBE_CELLS + 1):
		var probe := vox - Vector3i(0, step, 0)
		if int(tool.get_voxel(probe)) != VoxelMaterial.AIR:
			return terrain.to_global(
				Vector3(float(probe.x) + 0.5, float(probe.y), float(probe.z) + 0.5)
			)
	push_error(
		"SpawnTower: no floor within %d cells under the station at %v"
		% [FLOOR_PROBE_CELLS, station_world]
	)
	return Vector3.INF
