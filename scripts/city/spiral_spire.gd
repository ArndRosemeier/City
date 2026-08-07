## Thin helix-wrapped shaft: Arena corner towers and the Hill cave-gate pair share this stamp.
##
## Foot is the solid deck voxel the shaft sits on (arena seating / hill meadow). The climb is a
## one-voxel helix so the crown stays reachable without thickening the silhouette into a cone.
class_name SpiralSpire
extends RefCounted

## Shaft half-width — ~5×5 footprint.
const HALF := 2
## Default rise above the foot deck (24 m at 0.5 m voxels).
const RISE := 48
const CROWN_HALF := 4
const PARAPET_H := 2
const STEP_RISE := 1
const STEPS_PER_TURN := 16
const STEP_HALF := 1
## Orbit of step centres from the shaft axis.
const STEP_RADIUS := 4


## Stamp one spire. Returns the crown-top Y (parapet inclusive), or -1 when args are unusable.
static func stamp(
	brush: CityBrush, centre: Vector2i, foot_y: int, mat: int, rise: int = RISE
) -> int:
	if brush == null:
		push_error("SpiralSpire.stamp: brush is null")
		return -1
	if mat == VoxelMaterial.AIR:
		push_error("SpiralSpire.stamp: material must be solid")
		return -1
	if rise < 8:
		push_error("SpiralSpire.stamp: rise %d is too short" % rise)
		return -1
	var shaft_top := foot_y + rise
	brush.fill_box(
		Vector3i(centre.x - HALF, foot_y + 1, centre.y - HALF),
		Vector3i(centre.x + HALF + 1, shaft_top + 1, centre.y + HALF + 1),
		mat
	)
	_helix(brush, centre, foot_y, shaft_top, mat)
	var deck_y := shaft_top + 1
	brush.fill_box(
		Vector3i(centre.x - CROWN_HALF, deck_y, centre.y - CROWN_HALF),
		Vector3i(centre.x + CROWN_HALF + 1, deck_y + 1, centre.y + CROWN_HALF + 1),
		mat
	)
	var ring_top := deck_y + PARAPET_H
	for z in range(centre.y - CROWN_HALF, centre.y + CROWN_HALF + 1):
		for x in range(centre.x - CROWN_HALF, centre.x + CROWN_HALF + 1):
			var edge := (
				x == centre.x - CROWN_HALF or x == centre.x + CROWN_HALF
				or z == centre.y - CROWN_HALF or z == centre.y + CROWN_HALF
			)
			if not edge:
				continue
			brush.fill_box(
				Vector3i(x, deck_y + 1, z),
				Vector3i(x + 1, ring_top + 1, z + 1),
				mat
			)
	return ring_top


static func _helix(
	brush: CityBrush, centre: Vector2i, foot_y: int, shaft_top: int, mat: int
) -> void:
	var step := 0
	var y := foot_y + 1
	while y <= shaft_top:
		var angle := TAU * float(step) / float(STEPS_PER_TURN)
		var sx := centre.x + int(round(cos(angle) * float(STEP_RADIUS)))
		var sz := centre.y + int(round(sin(angle) * float(STEP_RADIUS)))
		brush.fill_box(
			Vector3i(sx - STEP_HALF, y, sz - STEP_HALF),
			Vector3i(sx + STEP_HALF + 1, y + 1, sz + STEP_HALF + 1),
			mat
		)
		step += 1
		y += STEP_RISE
