## Hangs mesh doors in castle / lot openings and seals them with solid DOOR voxels when closed.
##
## Leaves are visual only (no mesh colliders). Closed state writes `VoxelMaterial.DOOR` through
## CityBrush so VoxelBoxMover and nav both block; open restores AIR via destroy_vox.
## Player proximity + E toggles — camera no longer auto-opens.
class_name CastleDoorPlacer
extends Node3D

const DoorBarrierScript := preload("res://scripts/city/door_barrier.gd")

## Metres from the threshold for the Press-E hint / interact pick.
const INTERACT_DISTANCE := 3.2
## Leaves are hidden past this. A castle carries sixty-odd doors and most of them are three
## storeys underground.
const DRAW_DISTANCE := 60.0
## Radians per second. A heavy door, not a saloon door.
const SWING_SPEED := 2.6
## Seconds between draw-distance sweeps. The swing itself runs every frame.
const REFRESH_S := 0.2
## Hairline the leaf is shrunk by on every free edge, in voxels, so it does not z-fight the
## jamb it hangs against or the other leaf it meets in the middle.
const SEAM := 0.03

## One hung door: leaves, swing state, and the plan record for barriers.
class Hung extends RefCounted:
	var doorway: CastleDoorway = null
	## District-local → world shift used when the door was hung (ZERO for world-space lots).
	var origin_vox: Vector3i = Vector3i.ZERO
	var at: Vector3 = Vector3.ZERO
	var open_angle: float = 0.0
	var angle: float = 0.0
	var target: float = 0.0
	var closed: bool = true
	var leaves: Array[MeshInstance3D] = []
	## +1 for the leaf hinged on one jamb, -1 for its mirror.
	var spin: Array[float] = []


var _camera: Camera3D = null
var _brush: CityBrush = null
var _doors: Array[Hung] = []
## Leaf pivots in hang order, `CastleDoorway.LEAVES` to an opening.
var _pivots: Array[Node3D] = []
var _vox: float = 0.5
var _origin: Vector3 = Vector3.ZERO
var _origin_vox: Vector3i = Vector3i.ZERO
var _accum: float = 0.0
var _meshes: Dictionary[String, ArrayMesh] = {}
var _timber_gate: StandardMaterial3D = null
var _timber_door: StandardMaterial3D = null
var _iron: StandardMaterial3D = null


func _ready() -> void:
	set_process(false)


## Opens every barrier then frees leaves. Call before district unload.
func clear_doors() -> void:
	if _brush != null:
		for door: Hung in _doors:
			if door.closed and door.doorway != null:
				DoorBarrierScript.apply_open(_brush, door.doorway, door.origin_vox)
				door.closed = false
	_doors.clear()
	_pivots.clear()
	for c: Node in get_children():
		c.queue_free()


func door_count() -> int:
	return _doors.size()


func leaf_pivots() -> Array[Node3D]:
	return _pivots


func hung_doors() -> Array[Hung]:
	return _doors


func set_camera(camera: Camera3D) -> void:
	_camera = camera
	_refresh_visibility()


func set_brush(brush: CityBrush) -> void:
	_brush = brush


## Hangs every doorway on a castle layout. `layout` may be null (non-castle districts).
func place_from_layout(
	layout: CastleLayout,
	voxel_size: float,
	origin_vox: Vector3i,
	camera: Camera3D,
	brush: CityBrush = null
) -> void:
	clear_doors()
	_camera = camera
	_brush = brush
	_vox = voxel_size
	_origin_vox = origin_vox
	_origin = Vector3(float(origin_vox.x), float(origin_vox.y), float(origin_vox.z)) * voxel_size
	if layout == null:
		set_process(false)
		return
	_ensure_mats()
	for d: CastleDoorway in layout.doorways():
		_hang(d, origin_vox)
	_seal_all_closed()
	set_process(not _doors.is_empty())
	_refresh_visibility()
	print(
		"CastleDoorPlacer: %d doors (%d tree, %d loop), %d leaf profiles"
		% [
			_doors.size(),
			layout.doorway_link_count(CastleDoorway.LINK_TREE),
			layout.doorway_link_count(CastleDoorway.LINK_LOOP),
			_meshes.size(),
		]
	)


## Hang city lot doorways (already in world voxel space). Does not clear castle doors.
## Skips openings with no solid jambs/lintel (open façades, arcade niches).
func hang_lot_doorways(
	doorways: Array, voxel_size: float, camera: Camera3D, brush: CityBrush = null
) -> void:
	if brush != null:
		_brush = brush
	if camera != null:
		_camera = camera
	_vox = voxel_size
	_ensure_mats()
	var start := _doors.size()
	for item in doorways:
		var d := item as CastleDoorway
		if d == null:
			continue
		if _brush != null and not DoorBarrierScript.has_wall_frame(_brush, d):
			continue
		_hang(d, Vector3i.ZERO)
	_seal_closed_subset(start)
	set_process(not _doors.is_empty())
	_refresh_visibility()


## Nearest hung door within `INTERACT_DISTANCE` of `world_pos`, or null.
func nearest_door(world_pos: Vector3, max_dist: float = INTERACT_DISTANCE) -> Hung:
	var best: Hung = null
	var best_d2 := max_dist * max_dist
	for door: Hung in _doors:
		var d2 := door.at.distance_squared_to(world_pos)
		if d2 <= best_d2:
			best_d2 = d2
			best = door
	return best


## Toggle closed/open for one hung door. Returns true if state changed.
func toggle_door(door: Hung) -> bool:
	if door == null or door.doorway == null:
		return false
	return set_door_closed(door, not door.closed)


func set_door_closed(door: Hung, closed: bool) -> bool:
	if door == null or door.doorway == null or door.closed == closed:
		return false
	if _brush == null:
		push_error("CastleDoorPlacer: no CityBrush — cannot toggle barrier")
		return false
	if closed:
		DoorBarrierScript.apply_closed(_brush, door.doorway, door.origin_vox)
		door.target = 0.0
	else:
		DoorBarrierScript.apply_open(_brush, door.doorway, door.origin_vox)
		door.target = door.open_angle
	door.closed = closed
	return true


func _seal_all_closed() -> void:
	_seal_closed_subset(0)


func _seal_closed_subset(from_index: int) -> void:
	for i in range(maxi(from_index, 0), _doors.size()):
		var door: Hung = _doors[i]
		door.closed = true
		door.target = 0.0
		door.angle = 0.0
	## Mesh-only hangs (geometry tests) skip barriers until a brush is bound.
	if _brush == null:
		return
	_brush.begin_edit()
	for i in range(maxi(from_index, 0), _doors.size()):
		var door: Hung = _doors[i]
		DoorBarrierScript.apply_closed(_brush, door.doorway, door.origin_vox)
	_brush.end_edit()


func _hang(d: CastleDoorway, origin_vox: Vector3i) -> void:
	var n := Vector3(float(d.axis.x), 0.0, float(d.axis.y))
	var sv := d.side()
	var s := Vector3(float(sv.x), 0.0, float(sv.y))
	var mesh := _leaf_mesh(d)
	var jamb := float(d.width / 2) + 0.5
	var sill := _world(d.center, d.floor_y + 1, origin_vox)
	var hung := Hung.new()
	hung.doorway = d
	hung.origin_vox = origin_vox
	hung.open_angle = d.swing_angle()
	hung.closed = true
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

func _leaf_mesh(d: CastleDoorway) -> ArrayMesh:
	var key := "%d|%d|%d|%d" % [d.leaf, d.width, d.height, d.arch_courses]
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
	var bands: Array[int] = _band_rows(d)
	var crown := d.height
	while crown > 1 and d.row_half(crown) < 0:
		crown -= 1
	for row in range(1, crown + 1):
		var h := d.row_half(row)
		if h < 0:
			continue
		var x_lo := half - float(h) + SEAM
		var y_lo := float(row - 1) + (SEAM if row == 1 else 0.0)
		var y_hi := float(row) - (SEAM if row == crown else 0.0)
		if solid:
			_box(timber, Vector3(x_lo, y_lo, -t), Vector3(reach, y_hi, t))
		else:
			_bars(iron, x_lo, reach, y_lo, y_hi, t)
		if not bands.has(row):
			continue
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
	if solid:
		_box(
			iron,
			Vector3(reach - 0.18, SEAM, -t - CastleDoorway.BAND_STANDOFF),
			Vector3(reach, float(maxi(d.clear_rows(), 1)), t + CastleDoorway.BAND_STANDOFF)
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


func _band_rows(d: CastleDoorway) -> Array[int]:
	var rows := maxi(d.clear_rows(), 1)
	var want := 3 if d.leaf == CastleDoorway.LEAF_GATE else 2
	var out: Array[int] = []
	for i in range(want):
		var row := clampi(
			int(ceil(float(rows) * float(i + 1) / float(want + 1))), 1, maxi(rows, 1)
		)
		if not out.has(row):
			out.append(row)
	return out


func _bars(st: SurfaceTool, x_lo: float, x_hi: float, y_lo: float, y_hi: float, t: float) -> void:
	const PITCH := 0.62
	const BAR := 0.22
	_box(st, Vector3(x_lo, y_lo, -t), Vector3(x_lo + BAR, y_hi, t))
	_box(st, Vector3(x_hi - BAR, y_lo, -t), Vector3(x_hi, y_hi, t))
	var x := x_hi - BAR - PITCH
	while x - BAR * 0.5 > x_lo + BAR:
		_box(st, Vector3(x - BAR * 0.5, y_lo, -t), Vector3(x + BAR * 0.5, y_hi, t))
		x -= PITCH


func _commit(st: SurfaceTool, mesh: ArrayMesh, mat: StandardMaterial3D) -> void:
	st.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


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
# Swing + draw cull
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_accum += delta
	if _accum >= REFRESH_S:
		_accum = 0.0
		_refresh_visibility()
	CityProfiler.begin("castle_doors")
	_advance(delta)
	CityProfiler.end("castle_doors")


func _refresh_visibility() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var eye := _camera.global_position
	var draw_r2 := DRAW_DISTANCE * DRAW_DISTANCE
	for door: Hung in _doors:
		var shown := door.at.distance_squared_to(eye) <= draw_r2
		## Swing target follows barrier state, not camera distance.
		door.target = 0.0 if door.closed else door.open_angle
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


func _world(column: Vector2i, y: int, origin_vox: Vector3i) -> Vector3:
	var ox := float(origin_vox.x)
	var oy := float(origin_vox.y)
	var oz := float(origin_vox.z)
	return Vector3(
		(float(column.x) + ox + 0.5) * _vox,
		(float(y) + oy) * _vox,
		(float(column.y) + oz + 0.5) * _vox
	)
