## Tetris arcade pavilion for the west lawn of a Gaming plaza.
##
## Bakes the *building*: a raised deck, a tall back wall, and pilastered bays for three
## cabinets. The cabinets themselves are not baked — TetrisMachine stamps its own voxel
## shell through the live brush, so they are spawned at district stream-in. This composer
## publishes their ground anchors on GamingLayout so the runtime needs no bake constants.
##
## The row faces east, back to the tile edge, so the walk over from the Go garden puts all
## three screens square on.
class_name GamingArcade
extends RefCounted

## Cabinet footprint, mirroring TetrisMachine.FRAME_W / FRAME_H at 0.5 m voxels. Kept as
## local constants rather than read off TetrisMachine: the composer must not preload a
## Node3D game script just to learn two numbers.
const CAB_W_VOX := 14
const CAB_H_VOX := 28
## How far the cabinet body reaches behind its anchor (the well and its backboard).
const CAB_BACK_VOX := 3

const CABINETS := 3
## Centre-to-centre along the row: the 7 m frame plus a 3 m bay gap.
const BAY_PITCH := 20
## Deck reaches this far past the outermost bay, so the row stands in a court.
const DECK_END_PAD := 14
## Standing room east of the cabinet fronts, and the sliver of deck behind the wall.
const DECK_FRONT := 22
const DECK_BACK := 8
## Two courses, so stepping up onto the arcade is a deliberate half metre.
const DECK_H := 2

## Wall thickness and how far it stands proud of the tallest cabinet.
const WALL_T := 3
const WALL_OVER := 2
## Pilasters between the bays: half-width along the row, reach east of the wall face.
const FIN_HW := 1
const FIN_OUT := 5

const DECK_MAT := VoxelMaterial.PLAZA
const KERB_MAT := VoxelMaterial.CURB
const WALL_MAT := VoxelMaterial.BRICK_DARK
const FIN_MAT := VoxelMaterial.METAL_PLATE
## Marquee strip and the bay downlights — the arcade has to read as lit at night.
const LAMP_MAT := VoxelMaterial.GLASS_LIT

var brush: CityBrush
var rng: RandomNumberGenerator
var stamper: TreeStamper
var ground_y: int = 6

var _layout: GamingLayout = null
var _zone: Rect2i = Rect2i()
## Deck footprint and the X plane the cabinet anchors sit on.
var _deck: Rect2i = Rect2i()
var _anchor_x: int = 0


func build(layout: GamingLayout) -> void:
	if not _begin(layout):
		return
	_build_deck()
	_build_wall()
	_place_cabinet_anchors()
	_plant_corners()
	print(
		"GamingArcade: deck=%s bays=%d anchor_x=%d"
		% [_deck, _layout.arcade_cabinets.size(), _anchor_x]
	)


func _begin(layout: GamingLayout) -> bool:
	if brush == null or rng == null:
		push_error("GamingArcade: brush / rng not set")
		return false
	if layout == null:
		push_error("GamingArcade: no layout")
		return false
	_layout = layout
	_layout.arcade_cabinets = []
	var a0 := layout.arcade_min
	var a1 := layout.arcade_max
	if a1.x <= a0.x or a1.z <= a0.z:
		## No west lawn was published — GamingComposer already said why.
		return false
	_zone = Rect2i(a0.x, a0.z, a1.x - a0.x, a1.z - a0.z)

	var row_span := (CABINETS - 1) * BAY_PITCH + CAB_W_VOX
	var deck_d := row_span + DECK_END_PAD * 2
	var deck_w := DECK_BACK + CAB_BACK_VOX + DECK_FRONT
	if _zone.size.x < deck_w or _zone.size.y < deck_d:
		push_error(
			"GamingArcade: zone %s cannot hold a %dx%d pavilion" % [_zone, deck_w, deck_d]
		)
		return false
	## Pushed to the western third of the lawn: the deck faces east across open grass, so
	## the row is visible on the walk over instead of being read edge-on.
	var deck_x0 := _zone.position.x + (_zone.size.x - deck_w) / 4
	var deck_z0 := _zone.position.y + (_zone.size.y - deck_d) / 2
	_deck = Rect2i(deck_x0, deck_z0, deck_w, deck_d)
	_anchor_x = deck_x0 + DECK_BACK + CAB_BACK_VOX
	return true


## Deck top face sits DECK_H courses above the meadow surface, which is the plane every
## cabinet anchor and the wall are measured from.
func _deck_top() -> int:
	return ground_y + 1 + DECK_H


func _build_deck() -> void:
	var kerb := _deck.grow(2)
	## Kerb first, then the deck over it, so the deck edge is a lip rather than a cliff.
	brush.fill_box(
		Vector3i(kerb.position.x, ground_y + 1, kerb.position.y),
		Vector3i(kerb.end.x, _deck_top() - 1, kerb.end.y),
		KERB_MAT
	)
	brush.fill_box(
		Vector3i(_deck.position.x, ground_y + 1, _deck.position.y),
		Vector3i(_deck.end.x, _deck_top(), _deck.end.y),
		DECK_MAT
	)


func _build_wall() -> void:
	var top := _deck_top() + CAB_H_VOX + WALL_OVER
	var wall_x0 := _deck.position.x + DECK_BACK - WALL_T
	brush.fill_box(
		Vector3i(wall_x0, _deck_top(), _deck.position.y),
		Vector3i(wall_x0 + WALL_T, top, _deck.end.y),
		WALL_MAT
	)
	## Marquee: a lit course capping the wall, so the pavilion has a skyline at night.
	brush.fill_box(
		Vector3i(wall_x0, top, _deck.position.y),
		Vector3i(wall_x0 + WALL_T, top + 1, _deck.end.y),
		LAMP_MAT
	)
	_build_fins(wall_x0, top)


## Pilasters bracketing each bay, each with a downlight over the cabinet it frames. Placed
## in the gaps between cabinets and outside the end ones, never across a bay.
func _build_fins(wall_x0: int, top: int) -> void:
	var mid_z := _deck.position.y + _deck.size.y / 2
	var half_row := (CABINETS - 1) * BAY_PITCH / 2
	for i in range(CABINETS + 1):
		var z := mid_z - half_row - BAY_PITCH / 2 + i * BAY_PITCH
		brush.fill_box(
			Vector3i(wall_x0, _deck_top(), z - FIN_HW),
			Vector3i(wall_x0 + WALL_T + FIN_OUT, top + 1, z + FIN_HW),
			FIN_MAT
		)
		brush.fill_box(
			Vector3i(wall_x0 + WALL_T, top, z - FIN_HW),
			Vector3i(wall_x0 + WALL_T + FIN_OUT, top + 1, z + FIN_HW),
			LAMP_MAT
		)


## One anchor per bay, plus the spawn point for the cabinet-playing NPC. Anchors carry the
## deck cell the cabinet stands on; the runtime lifts them by one course.
func _place_cabinet_anchors() -> void:
	var mid_z := _deck.position.y + _deck.size.y / 2
	var half_row := (CABINETS - 1) * BAY_PITCH / 2
	var stand_y := _deck_top() - 1
	for i in range(CABINETS):
		var z := mid_z - half_row + i * BAY_PITCH
		_layout.arcade_cabinets.append(Vector3i(_anchor_x, stand_y, z))
	## Local −Z of a cabinet points at the player, and that has to come out as world +X.
	_layout.arcade_yaw = -PI * 0.5
	## Well inside TetrisPedNpc.NEAR_TETRIS_M of the middle cabinet, so it walks up rather
	## than standing around.
	_layout.arcade_ped_spawn = Vector3i(_anchor_x + 10, stand_y, mid_z)


## Planters on the deck's outer corners: they stop the court reading as a bare slab and
## give the row a frame from the approach.
func _plant_corners() -> void:
	var tree := _tree_stamper()
	var inset := 5
	var xs := [_deck.position.x + DECK_BACK + CAB_BACK_VOX + DECK_FRONT - inset]
	var zs := [_deck.position.y + inset, _deck.end.y - inset - 1]
	for x_v in xs:
		var x: int = x_v
		for z_v in zs:
			var z: int = z_v
			brush.fill_box(
				Vector3i(x - 3, _deck_top(), z - 3),
				Vector3i(x + 4, _deck_top() + 2, z + 4),
				VoxelMaterial.PLANTER
			)
			tree.round_tree(x, _deck_top() + 1, z)


func _tree_stamper() -> TreeStamper:
	if stamper == null:
		stamper = TreeStamper.new()
		stamper.brush = brush
		stamper.rng = rng
	return stamper
