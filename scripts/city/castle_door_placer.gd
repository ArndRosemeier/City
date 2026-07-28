## Hangs a mesh door in every opening of a baked castle, and swings it out of the way when
## the player walks up to it.
##
## The doors are meshes, not voxels. That is not a style choice: `DUNGEON_DOOR_W` is five
## columns against a `LANE_MARGIN` of three, which is the least the span field will path
## through, so one column of voxel jamb either side would take geodesic clearance to zero and
## the door would silently become a wall. A mesh leaf writes no voxels at all, and every leaf
## here hangs inside the reveal the masonry already has — the stone arch *is* the frame.
##
## Navigation therefore never sees a door: they are permanently passable, they register no
## blocked columns, and nothing in `NavService` knows they exist. The leaves carry no collider
## either, so a body that reaches a leaf still closing walks through it rather than being
## trapped by decoration.
class_name CastleDoorPlacer
extends Node3D

## Metres from the threshold at which a door starts to open. Ten voxels: a leaf takes about
## six tenths of a second to swing, so this is far enough ahead that a walk through the gate
## never stalls at a closed one, and near enough that a corridor of cells reads as shut from
## the far end of it.
const OPEN_DISTANCE := 5.0
## Leaves are hidden past this. A castle carries sixty-odd doors and most of them are three
## storeys underground.
const DRAW_DISTANCE := 60.0
## Radians per second. A heavy door, not a saloon door.
const SWING_SPEED := 2.6
## Seconds between distance sweeps. The swing itself runs every frame.
const REFRESH_S := 0.2
## Hairline the leaf is shrunk by on every free edge, in voxels, so it does not z-fight the
## jamb it hangs against or the other leaf it meets in the middle.
const SEAM := 0.03

## One hung door: the leaves, and how far open they currently are.
class Hung extends RefCounted:
	var at: Vector3 = Vector3.ZERO
	var open_angle: float = 0.0
	var angle: float = 0.0
	var target: float = 0.0
	var leaves: Array[MeshInstance3D] = []
	## +1 for the leaf hinged on one jamb, -1 for its mirror, so both swing the way a body
	## walks through the opening.
	var spin: Array[float] = []


var _camera: Camera3D = null
var _doors: Array[Hung] = []
## Leaf pivots in `CastleLayout.doorways()` order, `CastleDoorway.LEAVES` to an opening. Kept
## flat so the check tool can measure the geometry that was actually built rather than
## re-deriving what it should have been.
var _pivots: Array[Node3D] = []
var _vox: float = 0.5
var _origin: Vector3 = Vector3.ZERO
var _accum: float = 0.0
## One mesh per (leaf kind, width, height). A castle has a handful of distinct openings and
## sixty doors, so the geometry is built once and shared.
var _meshes: Dictionary[String, ArrayMesh] = {}
var _timber_gate: StandardMaterial3D = null
var _timber_door: StandardMaterial3D = null
var _iron: StandardMaterial3D = null


func _ready() -> void:
	set_process(false)


func clear_doors() -> void:
	_doors.clear()
	_pivots.clear()
	for c: Node in get_children():
		c.queue_free()


func door_count() -> int:
	return _doors.size()


func leaf_pivots() -> Array[Node3D]:
	return _pivots


## Points the swing at another camera. `DistrictInstance` re-binds on a camera swap, and the
## shot tool aims the doors at the camera it is about to capture from rather than at the
## player's, so a frame shows the door in the state the shot is meant to show.
func set_camera(camera: Camera3D) -> void:
	_camera = camera
	_retarget()


## Hangs every door the plan asked for. `layout` may be null — every district but a Castle one
## has no doors, and this is a no-op there rather than an error.
func place_from_layout(
	layout: CastleLayout, voxel_size: float, origin_vox: Vector3i, camera: Camera3D
) -> void:
	clear_doors()
	_camera = camera
	_vox = voxel_size
	_origin = Vector3(float(origin_vox.x), float(origin_vox.y), float(origin_vox.z)) * voxel_size
	if layout == null:
		set_process(false)
		return
	_ensure_mats()
	var all := layout.doorways()
	for d: CastleDoorway in all:
		_hang(d)
	set_process(not _doors.is_empty())
	## Sweep once now rather than at the first `REFRESH_S` tick, so a screenshot taken on the
	## frame after the bake shows the doors instead of the empty holes.
	_retarget()
	print(
		"CastleDoorPlacer: %d doors (%d tree, %d loop), %d leaf profiles"
		% [
			_doors.size(),
			layout.doorway_link_count(CastleDoorway.LINK_TREE),
			layout.doorway_link_count(CastleDoorway.LINK_LOOP),
			_meshes.size(),
		]
	)


func _hang(d: CastleDoorway) -> void:
	var n := Vector3(float(d.axis.x), 0.0, float(d.axis.y))
	var sv := d.side()
	var s := Vector3(float(sv.x), 0.0, float(sv.y))
	var mesh := _leaf_mesh(d)
	var jamb := float(d.width / 2) + 0.5
	var sill := _world(d.center, d.floor_y + 1)
	var hung := Hung.new()
	hung.open_angle = d.swing_angle()
	hung.at = sill + n * (d.hang_plane() * _vox)
	for i in range(CastleDoorway.LEAVES):
		var spin := 1.0 if i == 0 else -1.0
		var x_axis := s * spin
		var pivot := Node3D.new()
		pivot.name = "Leaf"
		var tf := Transform3D()
		tf.basis.x = x_axis
		tf.basis.y = Vector3.UP
		tf.basis.z = x_axis.cross(Vector3.UP)
		tf.origin = sill + (n * d.hang_plane() - x_axis * jamb) * _vox
		pivot.transform = tf
		add_child(pivot)
		_pivots.append(pivot)
		var leaf := MeshInstance3D.new()
		leaf.mesh = mesh
		leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		leaf.visible = false
		pivot.add_child(leaf)
		hung.leaves.append(leaf)
		hung.spin.append(spin)
	_doors.append(hung)


# ---------------------------------------------------------------------------
# Leaf geometry
# ---------------------------------------------------------------------------

## The leaf, in its own frame: +X runs from the hinge to the middle of the opening, +Y up from
## the threshold, Z is the thickness.
##
## Built course by course to `CastleDoorway.row_half()`, which is the same profile the masonry
## was cut to, so the leaf fills the stepped arch instead of sitting as a short rectangle
## under it. A dungeon opening keeps its full width for only three courses out of five; a leaf
## sized to that rectangle would be a 1.5 m hatch in a 2.5 m hole.
func _leaf_mesh(d: CastleDoorway) -> ArrayMesh:
	var key := "%d|%d|%d" % [d.leaf, d.width, d.height]
	if _meshes.has(key):
		return _meshes[key]
	var timber := SurfaceTool.new()
	var iron := SurfaceTool.new()
	timber.begin(Mesh.PRIMITIVE_TRIANGLES)
	iron.begin(Mesh.PRIMITIVE_TRIANGLES)
	var solid := d.leaf != CastleDoorway.LEAF_GRATE
	var reach := d.leaf_reach() - SEAM
	var half := float(d.width / 2)
	var t := CastleDoorway.LEAF_T * 0.5
	## Courses the ledgers sit on, and how many: the gate carries a third band and studs.
	var bands: Array[int] = _band_rows(d)
	var crown := d.height
	while crown > 1 and d.row_half(crown) < 0:
		crown -= 1
	for row in range(1, crown + 1):
		var h := d.row_half(row)
		if h < 0:
			continue
		var x_lo := half - float(h) + SEAM
		## Courses meet flush inside the leaf; only the edges that face stone are held off it.
		var y_lo := float(row - 1) + (SEAM if row == 1 else 0.0)
		var y_hi := float(row) - (SEAM if row == crown else 0.0)
		if solid:
			_box(timber, Vector3(x_lo, y_lo, -t), Vector3(reach, y_hi, t))
		else:
			_bars(iron, x_lo, reach, y_lo, y_hi, t)
		if not bands.has(row):
			continue
		## Ledger across the course, standing off both faces. Both, because either side of an
		## interior door is a room and the leaf is 20 cm thick.
		var band_t := t + CastleDoorway.BAND_STANDOFF
		_box(
			iron,
			Vector3(x_lo, y_lo + 0.15, -band_t),
			Vector3(reach, y_hi - 0.15, band_t)
		)
		if d.leaf != CastleDoorway.LEAF_GATE:
			continue
		var stud := CastleDoorway.STUD_STANDOFF
		var studs := maxi(int((reach - x_lo) / 0.7), 1)
		for k in range(studs):
			var sx := x_lo + (float(k) + 0.5) * (reach - x_lo) / float(studs)
			_box(
				iron,
				Vector3(sx - stud, (y_lo + y_hi) * 0.5 - stud, -band_t - stud),
				Vector3(sx + stud, (y_lo + y_hi) * 0.5 + stud, band_t + stud)
			)
	## Meeting stile down the middle of a solid leaf, so a closed double door reads as two
	## leaves rather than as one boarded-up hole.
	if solid:
		_box(
			iron,
			Vector3(reach - 0.18, SEAM, -t - CastleDoorway.BAND_STANDOFF),
			Vector3(reach, float(d.clear_rows()), t + CastleDoorway.BAND_STANDOFF)
		)
	var mesh := ArrayMesh.new()
	if solid:
		_commit(
			timber,
			mesh,
			_timber_gate if d.leaf == CastleDoorway.LEAF_GATE else _timber_door
		)
	_commit(iron, mesh, _iron)
	if mesh.get_surface_count() == 0:
		push_error("CastleDoorPlacer: %s produced no leaf geometry" % d.describe())
	_meshes[key] = mesh
	return mesh


## Courses the iron ledgers land on. Spread over the clear rectangle rather than the whole
## opening, so a band never lands in the arch where the leaf has already stepped in.
func _band_rows(d: CastleDoorway) -> Array[int]:
	var rows := d.clear_rows()
	var want := 3 if d.leaf == CastleDoorway.LEAF_GATE else 2
	var out: Array[int] = []
	for i in range(want):
		var row := clampi(
			int(ceil(float(rows) * float(i + 1) / float(want + 1))), 1, maxi(rows, 1)
		)
		if not out.has(row):
			out.append(row)
	return out


## Vertical bars across one course of a grille, laid out from the middle of the opening
## outwards so they line up across courses of different width.
func _bars(st: SurfaceTool, x_lo: float, x_hi: float, y_lo: float, y_hi: float, t: float) -> void:
	const PITCH := 0.62
	const BAR := 0.22
	## Stiles down both edges of the course: a grille of loose bars reads as a fence.
	_box(st, Vector3(x_lo, y_lo, -t), Vector3(x_lo + BAR, y_hi, t))
	_box(st, Vector3(x_hi - BAR, y_lo, -t), Vector3(x_hi, y_hi, t))
	var x := x_hi - BAR - PITCH
	while x - BAR * 0.5 > x_lo + BAR:
		_box(st, Vector3(x - BAR * 0.5, y_lo, -t), Vector3(x + BAR * 0.5, y_hi, t))
		x -= PITCH


func _commit(st: SurfaceTool, mesh: ArrayMesh, mat: StandardMaterial3D) -> void:
	st.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


## An axis-aligned box in voxel units, written into the surface in metres.
func _box(st: SurfaceTool, lo: Vector3, hi: Vector3) -> void:
	var a := lo * _vox
	var b := hi * _vox
	_quad(st, Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z),
		Vector3(a.x, b.y, b.z), Vector3(0.0, 0.0, 1.0))
	_quad(st, Vector3(b.x, a.y, a.z), Vector3(a.x, a.y, a.z), Vector3(a.x, b.y, a.z),
		Vector3(b.x, b.y, a.z), Vector3(0.0, 0.0, -1.0))
	_quad(st, Vector3(b.x, a.y, b.z), Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z),
		Vector3(b.x, b.y, b.z), Vector3(1.0, 0.0, 0.0))
	_quad(st, Vector3(a.x, a.y, a.z), Vector3(a.x, a.y, b.z), Vector3(a.x, b.y, b.z),
		Vector3(a.x, b.y, a.z), Vector3(-1.0, 0.0, 0.0))
	_quad(st, Vector3(a.x, b.y, b.z), Vector3(b.x, b.y, b.z), Vector3(b.x, b.y, a.z),
		Vector3(a.x, b.y, a.z), Vector3(0.0, 1.0, 0.0))
	_quad(st, Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z),
		Vector3(a.x, a.y, b.z), Vector3(0.0, -1.0, 0.0))


func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3) -> void:
	for p: Vector3 in [p0, p1, p2, p0, p2, p3]:
		st.set_normal(n)
		st.add_vertex(p)


func _ensure_mats() -> void:
	if _iron != null:
		return
	## Both faces are drawn: a leaf is a 20 cm slab with a room on either side of it.
	_timber_gate = StandardMaterial3D.new()
	_timber_gate.albedo_color = Color(0.23, 0.15, 0.09)
	_timber_gate.roughness = 0.88
	_timber_gate.cull_mode = BaseMaterial3D.CULL_DISABLED
	_timber_door = StandardMaterial3D.new()
	_timber_door.albedo_color = Color(0.40, 0.26, 0.14)
	_timber_door.roughness = 0.82
	_timber_door.cull_mode = BaseMaterial3D.CULL_DISABLED
	_iron = StandardMaterial3D.new()
	_iron.albedo_color = Color(0.15, 0.15, 0.17)
	_iron.metallic = 0.62
	_iron.roughness = 0.44
	_iron.cull_mode = BaseMaterial3D.CULL_DISABLED


# ---------------------------------------------------------------------------
# Swing
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_accum += delta
	if _accum >= REFRESH_S:
		_accum = 0.0
		_retarget()
	CityProfiler.begin("castle_doors")
	_advance(delta)
	CityProfiler.end("castle_doors")


## Which doors are worth drawing, and which are being walked up to.
##
## Measured against the camera alone. The crowd and the undead have no shared registry of
## agents to poll, so a skeleton walks through a closed leaf — which is right for navigation,
## since nav treats every door as air, and wrong only for the look of it.
func _retarget() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var eye := _camera.global_position
	var draw_r2 := DRAW_DISTANCE * DRAW_DISTANCE
	var open_r2 := OPEN_DISTANCE * OPEN_DISTANCE
	for door: Hung in _doors:
		var d2 := door.at.distance_squared_to(eye)
		var shown := d2 <= draw_r2
		door.target = door.open_angle if d2 <= open_r2 else 0.0
		for leaf: MeshInstance3D in door.leaves:
			leaf.visible = shown


func _advance(delta: float) -> void:
	var step := SWING_SPEED * delta
	for door: Hung in _doors:
		if is_equal_approx(door.angle, door.target):
			continue
		door.angle = move_toward(door.angle, door.target, step)
		for i in range(door.leaves.size()):
			var leaf: MeshInstance3D = door.leaves[i]
			leaf.rotation.y = door.angle * door.spin[i]


## District-local voxel column and voxel Y to world metres, on the column centre.
func _world(column: Vector2i, y: int) -> Vector3:
	return _origin + Vector3(
		(float(column.x) + 0.5) * _vox, float(y) * _vox, (float(column.y) + 0.5) * _vox
	)
