## Builds an Arena-theme district: a compact ~50×50 m rounded-rect colosseum with a
## rectangular sand pit, seating raised above the pit wall, gate tunnels, low board walls
## for outward summon Ui3Ds, and under-pit lift pads.
##
## District-local voxel coords. Road stubs stay as planner roads; this stamps a centered
## footprint inside the open reserve (meadow remains around it).
class_name ArenaComposer
extends RefCounted

var brush: CityBrush
var rng: RandomNumberGenerator
var ground_y: int = 6
var planner: DistrictPlanner
var cell_size: int = 28

var layout: ArenaLayout = null

## Outer mass side length: 50 m at 0.5 m voxels.
const OUTER_SIDE_VOX := 100
## Seating band depth on each side (voxels).
const SEATING_DEPTH := 14
## Pit wall height above the sand.
const PIT_WALL_H := 8
## How far seating rises above the pit wall top (spectators look over the wall).
const SEATING_ABOVE_WALL := 3
## Low parapet the summon board mounts to (voxels above seating deck).
const BOARD_WALL_H := 3
## Half-width of the board parapet along the face. Spans the straight outer side
## between corner fillets (matches ArenaSummonBoard.PANEL_W ≈ 38 m).
const BOARD_WALL_HW := 38
## Undercroft / lift shaft depth below sand.
const UNDERCROFT_H := 10
## Gate tunnel half-width and length through the seating band.
const GATE_HW := 4
const GATE_LEN := 16
## Summon pad inset from each pit face.
const LIFT_INSET := 8
const LIFT_HALF := 3
## Pit wall thickness outside the sand rectangle.
const WALL_T := 3
## Invisible walk-through LOS veil on the tribune lip (blocks shots, not bodies).
const LOS_VEIL_H := 8


func compose(min_v: Vector3i, max_v: Vector3i) -> void:
	if not _begin(min_v, max_v):
		return
	layout = _plan()
	if layout == null:
		return
	_build_outer_mass()
	_build_pit()
	_finish_seating_deck()
	_build_tribune_los_veil()
	_build_board_walls()
	_carve_gates()
	_build_lift_shafts()
	_scatter_spectators()
	print("ArenaComposer: %s" % layout.describe())


func compose_far_sparse(min_v: Vector3i, max_v: Vector3i) -> void:
	if not _begin(min_v, max_v):
		return
	layout = _plan()
	if layout == null:
		return
	_build_outer_mass()
	_build_pit()
	_finish_seating_deck()
	_build_tribune_los_veil()
	_build_board_walls()
	_carve_gates()


func _begin(_min_v: Vector3i, _max_v: Vector3i) -> bool:
	if brush == null or rng == null or planner == null:
		push_error("ArenaComposer: brush / rng / planner not set")
		return false
	if planner.large_arena.size.x <= 0:
		push_error("ArenaComposer: empty large_arena")
		return false
	return true


func _plan() -> ArenaLayout:
	var la: Rect2i = planner.large_arena
	var rx0 := la.position.x * cell_size
	var rz0 := la.position.y * cell_size
	var rx1 := la.end.x * cell_size
	var rz1 := la.end.y * cell_size
	var rw := rx1 - rx0
	var rd := rz1 - rz0
	if rw < OUTER_SIDE_VOX + 8 or rd < OUTER_SIDE_VOX + 8:
		push_error("ArenaComposer: reserve %dx%d too small for %d arena" % [rw, rd, OUTER_SIDE_VOX])
		return null
	## Center the compact colosseum in the open reserve.
	var ox0 := rx0 + (rw - OUTER_SIDE_VOX) / 2
	var oz0 := rz0 + (rd - OUTER_SIDE_VOX) / 2
	var ow := OUTER_SIDE_VOX
	var od := OUTER_SIDE_VOX
	var seat := SEATING_DEPTH
	var pit_w := ow - 2 * seat
	var pit_d := od - 2 * seat
	var px0 := ox0 + seat
	var pz0 := oz0 + seat
	var out := ArenaLayout.new()
	out.outer_rect = Rect2i(ox0, oz0, ow, od)
	out.pit_rect = Rect2i(px0, pz0, pit_w, pit_d)
	out.pit_floor_y = ground_y
	out.pit_wall_top_y = ground_y + PIT_WALL_H
	out.seating_y = out.pit_wall_top_y + SEATING_ABOVE_WALL
	out.board_wall_top_y = out.seating_y + BOARD_WALL_H
	out.corner_radius = 12
	_plan_gates_and_boards(out)
	_plan_lifts(out)
	return out


func _plan_gates_and_boards(out: ArenaLayout) -> void:
	var pit := out.pit_rect
	var dirs: Array[Vector2i] = [
		Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)
	]
	for d: Vector2i in dirs:
		var mid := Vector2i(pit.position.x + pit.size.x / 2, pit.position.y + pit.size.y / 2)
		var face: Vector2i
		if d.y < 0:
			face = Vector2i(mid.x, pit.position.y)
		elif d.y > 0:
			face = Vector2i(mid.x, pit.end.y - 1)
		elif d.x < 0:
			face = Vector2i(pit.position.x, mid.y)
		else:
			face = Vector2i(pit.end.x - 1, mid.y)
		var g0: Vector2i
		var gsz: Vector2i
		if d.x == 0:
			if d.y < 0:
				g0 = Vector2i(face.x - GATE_HW, face.y - GATE_LEN)
			else:
				g0 = Vector2i(face.x - GATE_HW, face.y + 1)
			gsz = Vector2i(GATE_HW * 2 + 1, GATE_LEN)
		else:
			if d.x < 0:
				g0 = Vector2i(face.x - GATE_LEN, face.y - GATE_HW)
			else:
				g0 = Vector2i(face.x + 1, face.y - GATE_HW)
			gsz = Vector2i(GATE_LEN, GATE_HW * 2 + 1)
		out.gate_rects.append(Rect2i(g0, gsz))
		## Low board wall on the seating deck, one cell outside the LOS-veil lip so the
		## wide parapet does not overwrite the invisible barrier. Ui3D faces *outward*
		## so the player looks toward the pit while using it.
		var outward := d
		var board_origin := face + outward * (WALL_T + 2)
		var yaw := atan2(-float(outward.x), -float(outward.y))
		out.board_mounts.append({
			"origin": board_origin,
			"dir": outward,
			"yaw": yaw,
		})


func _plan_lifts(out: ArenaLayout) -> void:
	var pit := out.pit_rect
	var mid := Vector2i(pit.position.x + pit.size.x / 2, pit.position.y + pit.size.y / 2)
	out.lift_pads = [
		Vector2i(mid.x, pit.position.y + LIFT_INSET),
		Vector2i(mid.x, pit.end.y - 1 - LIFT_INSET),
		Vector2i(pit.position.x + LIFT_INSET, mid.y),
		Vector2i(pit.end.x - 1 - LIFT_INSET, mid.y),
	]


func _in_rounded_outer(x: int, z: int) -> bool:
	var r := layout.outer_rect
	var rad := layout.corner_radius
	if x < r.position.x or z < r.position.y or x >= r.end.x or z >= r.end.y:
		return false
	var lx := x - r.position.x
	var lz := z - r.position.y
	var w := r.size.x
	var d := r.size.y
	if lx < rad and lz < rad:
		return Vector2(float(lx - rad), float(lz - rad)).length_squared() <= float(rad * rad)
	if lx >= w - rad and lz < rad:
		return Vector2(float(lx - (w - rad - 1)), float(lz - rad)).length_squared() <= float(rad * rad)
	if lx < rad and lz >= d - rad:
		return Vector2(float(lx - rad), float(lz - (d - rad - 1))).length_squared() <= float(rad * rad)
	if lx >= w - rad and lz >= d - rad:
		return (
			Vector2(float(lx - (w - rad - 1)), float(lz - (d - rad - 1))).length_squared()
			<= float(rad * rad)
		)
	return true


func _build_outer_mass() -> void:
	var r := layout.outer_rect
	var y0 := ground_y + 1
	var y1 := layout.seating_y + 1
	brush.fill_box(
		Vector3i(r.position.x, y0, r.position.y),
		Vector3i(r.end.x, y1, r.end.y),
		VoxelMaterial.ARENA_SHELL
	)
	var pit := layout.pit_rect
	brush.fill_box(
		Vector3i(pit.position.x, y0, pit.position.y),
		Vector3i(pit.end.x, y1, pit.end.y),
		VoxelMaterial.AIR
	)
	var rad := layout.corner_radius
	_carve_corner(r.position.x, r.position.y, rad, -1, -1, y0, y1)
	_carve_corner(r.end.x - rad, r.position.y, rad, 1, -1, y0, y1)
	_carve_corner(r.position.x, r.end.y - rad, rad, -1, 1, y0, y1)
	_carve_corner(r.end.x - rad, r.end.y - rad, rad, 1, 1, y0, y1)


func _carve_corner(
	bx: int, bz: int, rad: int, sx: int, sz: int, y0: int, y1: int
) -> void:
	for lz in range(rad):
		for lx in range(rad):
			var cx := rad - 1 if sx > 0 else 0
			var cz := rad - 1 if sz > 0 else 0
			var dx := float(lx - cx)
			var dz := float(lz - cz)
			if dx * dx + dz * dz <= float(rad * rad):
				continue
			var x := bx + lx
			var z := bz + lz
			brush.fill_box(
				Vector3i(x, y0, z),
				Vector3i(x + 1, y1, z + 1),
				VoxelMaterial.AIR
			)


func _build_pit() -> void:
	var pit := layout.pit_rect
	var sand_y := layout.pit_floor_y
	var t := WALL_T
	brush.fill_box(
		Vector3i(pit.position.x, sand_y - UNDERCROFT_H, pit.position.y),
		Vector3i(pit.end.x, sand_y, pit.end.y),
		VoxelMaterial.ARENA_SHELL
	)
	brush.fill_box(
		Vector3i(pit.position.x, sand_y, pit.position.y),
		Vector3i(pit.end.x, sand_y + 1, pit.end.y),
		VoxelMaterial.DIRT
	)
	var wt := layout.pit_wall_top_y
	brush.fill_box(
		Vector3i(pit.position.x - t, sand_y + 1, pit.position.y - t),
		Vector3i(pit.end.x + t, wt + 1, pit.position.y),
		VoxelMaterial.ARENA_SHELL
	)
	brush.fill_box(
		Vector3i(pit.position.x - t, sand_y + 1, pit.end.y),
		Vector3i(pit.end.x + t, wt + 1, pit.end.y + t),
		VoxelMaterial.ARENA_SHELL
	)
	brush.fill_box(
		Vector3i(pit.position.x - t, sand_y + 1, pit.position.y),
		Vector3i(pit.position.x, wt + 1, pit.end.y),
		VoxelMaterial.ARENA_SHELL
	)
	brush.fill_box(
		Vector3i(pit.end.x, sand_y + 1, pit.position.y),
		Vector3i(pit.end.x + t, wt + 1, pit.end.y),
		VoxelMaterial.ARENA_SHELL
	)
	## Lower the wall-ring mass to the pit wall top so the raised seating deck looks over it.
	var wall_band := pit.grow(t)
	for z in range(wall_band.position.y, wall_band.end.y):
		for x in range(wall_band.position.x, wall_band.end.x):
			if pit.has_point(Vector2i(x, z)):
				continue
			brush.fill_box(
				Vector3i(x, wt + 1, z),
				Vector3i(x + 1, layout.seating_y + 1, z + 1),
				VoxelMaterial.AIR
			)


func _finish_seating_deck() -> void:
	## Flat raised gravel deck — no steps down toward the pit (that buried spectators).
	var outer := layout.outer_rect
	var pit := layout.pit_rect
	var wall_band := pit.grow(WALL_T)
	var seat_y := layout.seating_y
	for z in range(outer.position.y, outer.end.y):
		for x in range(outer.position.x, outer.end.x):
			if pit.has_point(Vector2i(x, z)) or wall_band.has_point(Vector2i(x, z)):
				continue
			if not _in_rounded_outer(x, z):
				continue
			brush.set_vox(Vector3i(x, seat_y, z), VoxelMaterial.GRAVEL)


func _build_board_walls() -> void:
	## Short parapets on the seating face of each side — boards mount to the outward face.
	var seat_y := layout.seating_y
	var top := layout.board_wall_top_y
	for mount: Dictionary in layout.board_mounts:
		var origin: Vector2i = mount["origin"] as Vector2i
		var outward: Vector2i = mount["dir"] as Vector2i
		var along := Vector2i(-outward.y, outward.x)
		for i in range(-BOARD_WALL_HW, BOARD_WALL_HW + 1):
			var p := origin + along * i
			## One-cell-thick wall; fill solid up from the deck.
			brush.fill_box(
				Vector3i(p.x, seat_y + 1, p.y),
				Vector3i(p.x + 1, top + 1, p.y + 1),
				VoxelMaterial.ARENA_SHELL
			)


func _build_tribune_los_veil() -> void:
	## One-cell invisible LOS veil on the seating lip. Tall enough to cover a standing
	## spectator; walk-through so players can jump in. Gates carve through it afterward.
	var pit := layout.pit_rect
	var wall := pit.grow(WALL_T)
	var lip := pit.grow(WALL_T + 1)
	var seat_y := layout.seating_y
	var y0 := seat_y + 1
	var y1 := seat_y + 1 + LOS_VEIL_H
	for z in range(lip.position.y, lip.end.y):
		for x in range(lip.position.x, lip.end.x):
			var p := Vector2i(x, z)
			if wall.has_point(p):
				continue
			if _in_any_gate(p):
				continue
			brush.fill_box(
				Vector3i(x, y0, z),
				Vector3i(x + 1, y1, z + 1),
				VoxelMaterial.LOS_VEIL
			)


func _in_any_gate(p: Vector2i) -> bool:
	for g: Rect2i in layout.gate_rects:
		if g.has_point(p):
			return true
	return false


func _carve_gates() -> void:
	var seat_y := layout.seating_y
	var clear_top := maxi(seat_y + 4, layout.pit_wall_top_y + 1)
	for g: Rect2i in layout.gate_rects:
		brush.fill_box(
			Vector3i(g.position.x, ground_y + 1, g.position.y),
			Vector3i(g.end.x, clear_top, g.end.y),
			VoxelMaterial.AIR
		)
		brush.fill_box(
			Vector3i(g.position.x, ground_y, g.position.y),
			Vector3i(g.end.x, ground_y + 1, g.end.y),
			VoxelMaterial.GRAVEL
		)
		## Simple stair rise from meadow deck up to seating through the gate.
		_stair_gate(g, seat_y)


func _stair_gate(g: Rect2i, seat_y: int) -> void:
	## Rise from meadow deck to seating along the gate, stepping from the outer end.
	var rise := seat_y - ground_y
	if rise <= 1:
		return
	var pit := layout.pit_rect
	var along_x := g.size.x > g.size.y
	var steps := mini(rise, maxi(g.size.x, g.size.y) - 2)
	for s in range(steps):
		var y_top := ground_y + s
		if along_x:
			var from_low_x := g.end.x <= pit.position.x
			var x := (g.position.x + s) if from_low_x else (g.end.x - 1 - s)
			brush.fill_box(
				Vector3i(x, ground_y, g.position.y),
				Vector3i(x + 1, y_top + 1, g.end.y),
				VoxelMaterial.ARENA_SHELL
			)
			brush.fill_box(
				Vector3i(x, y_top, g.position.y),
				Vector3i(x + 1, y_top + 1, g.end.y),
				VoxelMaterial.GRAVEL
			)
		else:
			var from_low_z := g.end.y <= pit.position.y
			var z := (g.position.y + s) if from_low_z else (g.end.y - 1 - s)
			brush.fill_box(
				Vector3i(g.position.x, ground_y, z),
				Vector3i(g.end.x, y_top + 1, z + 1),
				VoxelMaterial.ARENA_SHELL
			)
			brush.fill_box(
				Vector3i(g.position.x, y_top, z),
				Vector3i(g.end.x, y_top + 1, z + 1),
				VoxelMaterial.GRAVEL
			)


func _build_lift_shafts() -> void:
	var sand := layout.pit_floor_y
	for pad: Vector2i in layout.lift_pads:
		var x0 := pad.x - LIFT_HALF
		var z0 := pad.y - LIFT_HALF
		var x1 := pad.x + LIFT_HALF + 1
		var z1 := pad.y + LIFT_HALF + 1
		brush.fill_box(
			Vector3i(x0, sand - UNDERCROFT_H + 1, z0),
			Vector3i(x1, sand, z1),
			VoxelMaterial.AIR
		)
		brush.fill_box(
			Vector3i(x0, sand, z0),
			Vector3i(x1, sand + 1, z1),
			VoxelMaterial.GRAVEL
		)


func _scatter_spectators() -> void:
	if rng == null:
		return
	var outer := layout.outer_rect
	var pit := layout.pit_rect
	var seat_y := layout.seating_y
	var tries := 120
	var made := 0
	var stems: Array[String] = [
		"benchStone",
		"benchStone_z",
		"pillarSmall",
		"urnRound",
		"statue_column",
	]
	while made < 28 and tries > 0:
		tries -= 1
		var x := rng.randi_range(outer.position.x + 3, outer.end.x - 4)
		var z := rng.randi_range(outer.position.y + 3, outer.end.y - 4)
		if pit.grow(WALL_T + 4).has_point(Vector2i(x, z)):
			continue
		if not _in_rounded_outer(x, z):
			continue
		if brush.get_vox(Vector3i(x, seat_y, z)) != VoxelMaterial.GRAVEL:
			continue
		var stem: String = stems[rng.randi() % stems.size()]
		if RoomPropKit.stamp_brush(brush, Vector3i(x, seat_y + 1, z), stem):
			made += 1
