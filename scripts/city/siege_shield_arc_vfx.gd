## The light bridge from a living outer stone to the Lodestone: the tell that the centre cannot be
## hurt yet, and the countdown from four to none.
##
## Purely informational. No damage, no collision, no gameplay state — the shield itself lives in
## `SiegeController._tick_stones`, and this is how the player reads it from anywhere on the tile.
## Four arcs standing means "the crystal in the middle is untouchable"; the last one snapping out is
## the loudest thing that happens in a run.
##
## Up whenever the tile is, not just during a run. It is also the quarter's only signage: someone who
## has never started a run reads "these four protect that one" off the geometry alone, which is the
## difference between finding the console and wandering past an odd monument.
##
## Built as a chain of emissive cylinder segments along a high parabola rather than as one mesh: the
## arc has to clear a skyline of roofs between two points 100 m apart, and a bright bead travelling
## along it toward the centre is what makes the direction of the flow legible.
class_name SiegeShieldArcVfx
extends Node3D

## Segments along the curve. Enough that the chain reads as smooth at 100 m and cheap enough that
## four arcs are not a draw-call problem.
const SEGMENTS := 20
const CORE_RADIUS_M := 0.55
## Apex lift over the straight chord, as a fraction of chord length and as a floor. The arc has to
## pass over the city between the two stones, not through it.
const LIFT_FRACTION := 0.32
const MIN_LIFT_M := 26.0
## Bead travel, in arcs per second, and how much brighter the bead is than the body of the arc.
const FLOW_HZ := 0.45
const BEAD_GAIN := 3.4
## Width of the travelling bead as a fraction of the arc.
const BEAD_WIDTH := 0.16

var _mats: Array[StandardMaterial3D] = []
var _age: float = 0.0
var _fading: bool = false
var _fade_sec: float = 0.0
var _fade_elapsed: float = 0.0
var _colour: Color = Color(0.55, 0.86, 1.0)


## Stand an arc from `from` to `to`, both world-space apex points. Idempotent per instance: call once
## after adding the node to the tree.
func setup_arc(from: Vector3, to: Vector3) -> void:
	if not _mats.is_empty():
		push_error("SiegeShieldArcVfx.setup_arc: already built")
		assert(false, "SiegeShieldArcVfx: double setup")
		return
	global_position = Vector3.ZERO
	var chord := from.distance_to(to)
	if chord < 1.0:
		push_error("SiegeShieldArcVfx.setup_arc: %v and %v are the same place" % [from, to])
		assert(false, "SiegeShieldArcVfx: degenerate arc")
		return
	var lift := maxf(chord * LIFT_FRACTION, MIN_LIFT_M)
	## Quadratic control point over the midpoint. Pulled to twice the wanted apex because a
	## quadratic Bézier only reaches halfway to its control point.
	var control := (from + to) * 0.5 + Vector3.UP * lift * 2.0
	var prev := from
	for i in range(SEGMENTS):
		var t := float(i + 1) / float(SEGMENTS)
		var next := _bezier(from, control, to, t)
		_add_segment(prev, next)
		prev = next
	set_process(true)


## Snap the bridge out. The stone that anchored it is gone, so this is a death, not a dimming.
func begin_fade_out(duration_sec: float = 0.6) -> void:
	_fading = true
	_fade_sec = maxf(duration_sec, 0.05)
	_fade_elapsed = 0.0
	set_process(true)


func _process(delta: float) -> void:
	_age += delta
	if _fading:
		_fade_elapsed += delta
		var t := clampf(_fade_elapsed / _fade_sec, 0.0, 1.0)
		var drain := 1.0 - t
		for mat: StandardMaterial3D in _mats:
			mat.emission_energy_multiplier = 2.0 * drain * drain
			mat.albedo_color.a = 0.85 * drain
		if t >= 1.0:
			queue_free()
		return
	## Bead position along the arc, wrapping. Each segment knows where it sits, so brightness is a
	## distance to the bead rather than per-frame geometry work.
	var head := fposmod(_age * FLOW_HZ, 1.0)
	for i in range(_mats.size()):
		var at := float(i) / float(maxi(_mats.size(), 1))
		var gap := absf(at - head)
		gap = minf(gap, 1.0 - gap)
		var near := clampf(1.0 - gap / BEAD_WIDTH, 0.0, 1.0)
		_mats[i].emission_energy_multiplier = 1.5 + BEAD_GAIN * near * near


func _add_segment(from: Vector3, to: Vector3) -> void:
	var mid := (from + to) * 0.5
	var span := to - from
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(_colour.r, _colour.g, _colour.b, 0.85)
	mat.emission_enabled = true
	mat.emission = _colour
	mat.emission_energy_multiplier = 1.5
	mat.disable_receive_shadows = true
	_mats.append(mat)

	var mesh := CylinderMesh.new()
	mesh.top_radius = CORE_RADIUS_M
	mesh.bottom_radius = CORE_RADIUS_M
	## Overlap a little so the chain has no visible gaps where the curvature is sharpest.
	mesh.height = span.length() * 1.08
	mesh.radial_segments = 6
	mesh.rings = 1
	var mi := MeshInstance3D.new()
	mi.name = "Segment%d" % _mats.size()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = mid
	mi.global_basis = _basis_along(span.normalized())


## Rotate the cylinder's +Y axis onto `dir`.
func _basis_along(dir: Vector3) -> Basis:
	var dot := clampf(Vector3.UP.dot(dir), -1.0, 1.0)
	if dot > 0.9999:
		return Basis()
	if dot < -0.9999:
		return Basis(Vector3.RIGHT, PI)
	return Basis(Vector3.UP.cross(dir).normalized(), acos(dot))


func _bezier(a: Vector3, control: Vector3, b: Vector3, t: float) -> Vector3:
	var inv := 1.0 - t
	return a * (inv * inv) + control * (2.0 * inv * t) + b * (t * t)
