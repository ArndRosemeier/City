## Monster-chess court for the east lawn of a Gaming plaza.
##
## Bakes an 8×8 checkerboard at GamingLayout.chess_square_vox (4 m a square), a dark rim,
## a stone apron, and a stand behind each home rank. Nothing here moves: the pieces are
## runtime puppets spawned by ChessArena, which reads `chess_origin` off the layout.
##
## Files run west→east and ranks south→north, so white's home rank faces the garden and a
## player walking over from the Go pad arrives behind their own pieces.
class_name GamingChessCourt
extends RefCounted

## Dark border around the playing squares, then the walkable apron outside that.
const RIM := 3
const APRON := 12
## Two courses of plinth under the board, so it steps up out of the meadow.
const PLINTH_H := 2

## Pale and dark squares. GRAVE_MARBLE is the palette's brightest stone and BRICK_DARK its
## deepest built value — anything closer together stops reading as a board from the stand.
const LIGHT_MAT := VoxelMaterial.GRAVE_MARBLE
const DARK_MAT := VoxelMaterial.BRICK_DARK
const RIM_MAT := VoxelMaterial.GRAVE_STONE
const APRON_MAT := VoxelMaterial.STONE
const PLINTH_MAT := VoxelMaterial.CONCRETE
## Stands: three stepped tiers of seating behind each home rank.
const STAND_TIERS := 3
const STAND_MAT := VoxelMaterial.SIDEWALK
const STAND_RAIL_MAT := VoxelMaterial.METAL_PLATE
## Lit bollards down the two flanks, so the board is legible at night.
const BOLLARD_H := 5
const BOLLARD_MAT := VoxelMaterial.STONE
const LAMP_MAT := VoxelMaterial.GLASS_LIT

var brush: CityBrush
var rng: RandomNumberGenerator
var ground_y: int = 6

var _layout: GamingLayout = null
var _board: Rect2i = Rect2i()


func build(layout: GamingLayout) -> void:
	if not _begin(layout):
		return
	_build_plinth()
	_paint_squares()
	_build_stands()
	_place_bollards()
	print("GamingChessCourt: board=%s square=%d" % [_board, _layout.chess_square_vox])


func _begin(layout: GamingLayout) -> bool:
	if brush == null or rng == null:
		push_error("GamingChessCourt: brush / rng not set")
		return false
	if layout == null:
		push_error("GamingChessCourt: no layout")
		return false
	_layout = layout
	var c0 := layout.chess_min
	var c1 := layout.chess_max
	if c1.x <= c0.x or c1.z <= c0.z:
		## No east lawn was published — GamingComposer already said why.
		return false
	var span := layout.chess_span_vox()
	if span <= 0:
		push_error("GamingChessCourt: square pitch %d is unusable" % layout.chess_square_vox)
		return false
	_board = Rect2i(layout.chess_origin.x, layout.chess_origin.z, span, span)
	var court := _board.grow(RIM + APRON)
	var zone := Rect2i(c0.x, c0.z, c1.x - c0.x, c1.z - c0.z)
	if not zone.encloses(court):
		push_error("GamingChessCourt: court %s does not fit zone %s" % [court, zone])
		return false
	return true


## Board course is `chess_origin.y`; everything below it is plinth, and the apron is flush
## with the top of that so you can walk right up to the rim.
func _build_plinth() -> void:
	var court := _board.grow(RIM + APRON)
	var top := _layout.chess_origin.y + 1
	brush.fill_box(
		Vector3i(court.position.x, ground_y + 1, court.position.y),
		Vector3i(court.end.x, top, court.end.y),
		PLINTH_MAT
	)
	brush.fill_box(
		Vector3i(court.position.x, top - 1, court.position.y),
		Vector3i(court.end.x, top, court.end.y),
		APRON_MAT
	)
	var rim := _board.grow(RIM)
	brush.fill_box(
		Vector3i(rim.position.x, top - 1, rim.position.y),
		Vector3i(rim.end.x, top, rim.end.y),
		RIM_MAT
	)


## 64 blocks of `chess_square_vox`, a1 dark, painted into the board course itself so the
## squares are flush and a piece never straddles a lip.
func _paint_squares() -> void:
	var pitch := _layout.chess_square_vox
	var y := _layout.chess_origin.y
	for rank in range(8):
		for file in range(8):
			var mat := LIGHT_MAT if (file + rank) % 2 == 1 else DARK_MAT
			var x0 := _board.position.x + file * pitch
			var z0 := _board.position.y + rank * pitch
			brush.fill_box(
				Vector3i(x0, y, z0), Vector3i(x0 + pitch, y + 1, z0 + pitch), mat
			)


## Stepped stands behind both home ranks — the two players watch from opposite ends, which
## is also how the board's orientation reads at a glance.
func _build_stands() -> void:
	var top := _layout.chess_origin.y + 1
	var rim := _board.grow(RIM)
	var stand_w := rim.size.x
	for side in range(2):
		var out_dir := -1 if side == 0 else 1
		## Front edge of the stand, just outside the rim on this side.
		var front := rim.position.y - 3 if side == 0 else rim.end.y + 2
		for tier in range(STAND_TIERS):
			var z0 := front + out_dir * (tier * 2)
			var z1 := z0 + out_dir * 2
			brush.fill_box(
				Vector3i(rim.position.x, ground_y + 1, mini(z0, z1)),
				Vector3i(rim.position.x + stand_w, top + tier + 1, maxi(z0, z1)),
				STAND_MAT
			)
		## Rail across the back of the top tier, so the seating has an edge.
		var back := front + out_dir * (STAND_TIERS * 2)
		brush.fill_box(
			Vector3i(rim.position.x, top + STAND_TIERS, mini(back, back - out_dir)),
			Vector3i(
				rim.position.x + stand_w,
				top + STAND_TIERS + 2,
				maxi(back, back - out_dir)
			),
			STAND_RAIL_MAT
		)


## Lit posts down the east and west flanks, one per rank boundary.
func _place_bollards() -> void:
	var top := _layout.chess_origin.y + 1
	var pitch := _layout.chess_square_vox
	var west := _board.position.x - RIM - 3
	var east := _board.end.x + RIM + 2
	for i in range(9):
		var z := _board.position.y + i * pitch
		for x in [west, east]:
			var xi: int = x
			brush.fill_box(
				Vector3i(xi, top, z), Vector3i(xi + 1, top + BOLLARD_H, z + 1), BOLLARD_MAT
			)
			brush.set_vox(Vector3i(xi, top + BOLLARD_H, z), LAMP_MAT)
