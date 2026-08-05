## The teleport chamber's runtime furniture: eight tilted consoles around a launch pad, plus
## the beacon column standing on it.
##
## This is the only place that knows how the 5x5 district map is split across the consoles.
## The consoles just render the slice they are handed; the pad just reports clicks.
class_name TeleportChamber
extends Node3D

const TeleportConsoleScript := preload("res://scripts/city/teleport_console.gd")
const TeleportPadScript := preload("res://scripts/city/teleport_pad.gd")
const TeleportBeaconVfxScript := preload("res://scripts/city/teleport_beacon_vfx.gd")

## A destination was armed and the pad was clicked. CityRoot is asked directly as well; this
## exists so the chamber can be driven headless.
signal hop_requested(coord: Vector2i)

## Outward compass direction of each console, in district-coord space (+x east, +y south).
## Clockwise from north.
const SLOT_DIRS: Array[Vector2i] = [
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(1, 0),
	Vector2i(1, 1),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(-1, 0),
	Vector2i(-1, -1),
]
const SLOT_NAMES: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

## How far the console faces stand from the middle of the room.
const RING_RADIUS_M := 2.6
## One district panel. Consoles are this times their column and row count.
const PANEL_SIZE_M := Vector2(0.95, 0.5)
## Clearance the ring needs inside the room: console half-width plus a body's width to walk
## behind it. Below this the ring is pulled in rather than punched through the wall.
const RING_CLEARANCE_M := 1.5
const PLINTH_COLOR := Color(0.07, 0.10, 0.13, 1.0)

var _consoles: Array[TeleportConsole] = []
var _pad: TeleportPad = null
var _beacon: TeleportBeaconVfx = null
var _home: Vector2i = Vector2i.ZERO
var _armed: Vector2i = Vector2i.MAX


## Which district tiles, as offsets from the chamber's own tile, belong on the console facing
## `dir`. Row-major from the near row up, left to right as the map reads.
##
## Every non-zero offset in the 5x5 block has exactly one `(sign(x), sign(z))`, so the eight
## slots cover the 24 neighbours once each with nothing left over and nothing repeated.
static func slot_offsets(dir: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if dir.x == 0 and dir.y == 0:
		push_error("TeleportChamber.slot_offsets: (0,0) is the chamber's own tile")
		return out
	if dir.x == 0:
		## North / south console: the straight-ahead column, near ring at the bottom.
		for ring in [1, 2]:
			out.append(Vector2i(0, dir.y * ring))
	elif dir.y == 0:
		## East / west console: the same column, with depth running along x.
		for ring in [1, 2]:
			out.append(Vector2i(dir.x * ring, 0))
	else:
		## Diagonal console: the 2x2 corner block. Columns run west to east as on a map, so
		## the panel on your right really is the tile on your right.
		for ring_z in [1, 2]:
			var row: Array[Vector2i] = [
				Vector2i(dir.x, dir.y * ring_z), Vector2i(dir.x * 2, dir.y * ring_z)
			]
			if dir.x < 0:
				row.reverse()
			out.append_array(row)
	return out


static func slot_columns(dir: Vector2i) -> int:
	return 1 if dir.x == 0 or dir.y == 0 else 2


## Stand the chamber up. `floor_center` is the middle of the room at standing height, and
## `room_half_m` is the distance from there to the nearest wall.
func build(city_seed: int, home: Vector2i, floor_center: Vector3, room_half_m: float) -> void:
	_home = home
	_armed = Vector2i.MAX
	global_position = Vector3.ZERO
	var radius := minf(RING_RADIUS_M, maxf(room_half_m - RING_CLEARANCE_M, 1.2))
	for i in range(SLOT_DIRS.size()):
		_build_console(city_seed, SLOT_DIRS[i], SLOT_NAMES[i], floor_center, radius)
	_pad = TeleportPadScript.new() as TeleportPad
	_pad.name = "TeleportPad"
	add_child(_pad)
	_pad.build(floor_center)
	_pad.pad_pressed.connect(_on_pad_pressed)
	_beacon = TeleportBeaconVfxScript.new() as TeleportBeaconVfx
	_beacon.name = "TeleportBeacon"
	add_child(_beacon)
	_beacon.plant_at(floor_center)


## Light `coord` on whichever console shows it, and clear the other seven. An unknown tile
## disarms the chamber instead of silently arming nothing.
func arm(coord: Vector2i) -> void:
	var found := false
	for console in _consoles:
		if console.shows_coord(coord):
			found = true
			break
	_armed = coord if found else Vector2i.MAX
	for console in _consoles:
		console.set_selected(_armed)
	if _pad != null and is_instance_valid(_pad):
		_pad.set_armed(found)


func armed_coord() -> Vector2i:
	return _armed


func has_armed() -> bool:
	return _armed != Vector2i.MAX


func home_coord() -> Vector2i:
	return _home


func consoles() -> Array[TeleportConsole]:
	return _consoles


func pad() -> TeleportPad:
	return _pad


func _build_console(
	city_seed: int, dir: Vector2i, slot_name: String, center: Vector3, radius: float
) -> void:
	var offsets := slot_offsets(dir)
	var columns := slot_columns(dir)
	var labels := PackedStringArray()
	var coords: Array[Vector2i] = []
	for offset in offsets:
		var tile := _home + offset
		coords.append(tile)
		labels.append(DistrictName.for_district(city_seed, tile))
	## District coords are +x east, +y south, which is world +X and world +Z.
	var outward := Vector3(float(dir.x), 0.0, float(dir.y)).normalized()
	var console := TeleportConsoleScript.new() as TeleportConsole
	console.name = "Console%s" % slot_name
	add_child(console)
	console.setup(
		center + outward * radius + Vector3(0.0, TeleportConsole.PANEL_CENTER_Y_M, 0.0),
		outward,
		coords,
		labels,
		columns,
		PANEL_SIZE_M
	)
	console.district_chosen.connect(_on_district_chosen)
	_consoles.append(console)
	_build_plinth(console, center, outward, radius, columns)


## A dark wedge under the panel so the console reads as a machine standing on the floor rather
## than a sheet of light hanging in the air.
func _build_plinth(
	console: TeleportConsole,
	center: Vector3,
	outward: Vector3,
	radius: float,
	columns: int
) -> void:
	var height := TeleportConsole.PANEL_CENTER_Y_M
	var mi := MeshInstance3D.new()
	mi.name = "Plinth"
	var box := BoxMesh.new()
	box.size = Vector3(PANEL_SIZE_M.x * float(columns) * 0.9, height, 0.35)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PLINTH_COLOR
	mat.metallic = 0.75
	mat.roughness = 0.35
	mi.material_override = mat
	add_child(mi)
	mi.global_position = center + outward * (radius + 0.12) + Vector3(0.0, height * 0.5, 0.0)
	mi.rotation.y = console.rotation.y


func _on_district_chosen(coord: Vector2i) -> void:
	arm(coord)


func _on_pad_pressed() -> void:
	if not has_armed():
		return
	hop_requested.emit(_armed)
	var root := _city_root()
	if root == null:
		return
	root.request_district_hop_to(_armed)


func _city_root() -> CityRoot:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group("city_root")
	if nodes.is_empty():
		return null
	return nodes[0] as CityRoot
