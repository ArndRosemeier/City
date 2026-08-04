## Which monster plays which chess piece, and how tall it stands on the board.
##
## Content rather than a branch inside the arena, for the same reason `CreatureCatalog` is a
## table rather than an `if` in the loader: recasting the board should be editing rows.
##
## Only **beast** and **grove** have enough spawn-ready ground bodies to field six distinct
## silhouettes each (fifteen and fourteen rows, but the flying rigs hover and ship no walk
## cycle, which leaves fourteen and eight). Undead and infernal have four apiece, so a board
## cast from them would repeat bodies across ranks and the player could not tell a bishop
## from a rook at a glance.
##
## Heights are normalised on purpose. The catalogue runs 1.8 m (blob/Pigeon) to 4.41 m
## (blob/Mushnub_Evolved), and cast at authored size the tallest body would be whichever
## piece happened to be biggest rather than the one that matters. Instead rank sets height:
## the king is the tallest thing on the board because it is the king.
##
## Beast can field the Big rig throughout, which is humanoid and reads at a distance. Grove
## has only two Big bodies, so four of its six are blobs — a rounder army, which is also a
## fair description of what mushrooms and cacti look like.
class_name ChessCast
extends RefCounted

const ChessBoardStateScript := preload("res://scripts/city/chess_board_state.gd")
const CreatureVariationScript := preload("res://scripts/city/creature_variation.gd")

## Where each army's colour sits, reusing the monster recolour: one shared material for the
## whole board, the colour carried per MeshInstance3D as an instance uniform. Nothing here
## copies a mesh or a material.
##
## The tint is aimed rather than rotated, which is the only reason "toward white" is expressible
## at all — turning the wheel preserves saturation and value, so it could never take the yellow
## frog to ivory.
##
## Both bands keep a slice of each body's own hue (`hue_keep`) instead of flattening the army
## onto one colour. Rank is carried by height and body by silhouette, but hue is still what
## separates the rook from the bishop at a glance, and spending all of it on which side a piece
## is would cost more than it buys.
static var _ivory: CreatureVariation.Band = null
static var _slate: CreatureVariation.Band = null

## Standing height in metres per piece type, on a 4 m square.
##
## The spread matters more than any single figure: this is the only cue that tells a player
## what they are looking at from across the court, where colour has already been spent on
## telling the two armies apart. So the royals tower, the minor pieces hold the middle, and the
## pawns are deliberately small — better than twice the king's height between them, where a
## flatter set left the back rank reading as one crowd.
##
## The ceiling is the square, because a model scaled to height gets wider with it. A 3.4 m king
## on the widest rig in the cast still clears its neighbours; much past that and adjacent pieces
## start to overlap even though they are a full square apart.
const HEIGHT_KING := 3.4
const HEIGHT_QUEEN := 3.1
const HEIGHT_ROOK := 2.4
const HEIGHT_BISHOP := 2.4
const HEIGHT_KNIGHT := 2.4
const HEIGHT_PAWN := 1.5


## Catalogue body id for a piece, or "" with an error for a code that is not a piece.
static func body_for(colour: int, piece_type: int) -> String:
	if colour == ChessBoardStateScript.WHITE:
		match piece_type:
			ChessBoardStateScript.KING:
				return "big/Yeti"
			ChessBoardStateScript.QUEEN:
				return "big/Monkroose"
			ChessBoardStateScript.ROOK:
				return "big/Dino"
			ChessBoardStateScript.BISHOP:
				return "big/Bunny"
			ChessBoardStateScript.KNIGHT:
				## The knight is the only piece that leaves the ground — the actor hops it over
				## the corner of its L rather than walking round — so the frog plays it, and
				## the move becomes something a player recognises instead of memorises.
				return "big/Frog"
			ChessBoardStateScript.PAWN:
				## A blob body would have done for a pawn, but the blob rig is round and
				## nearly as wide as it is tall: eight of them shrunk onto the second rank
				## read as a hedge rather than as eight small soldiers. The Big rig is
				## humanoid, so it still looks like an infantryman at pawn height.
				return "big/Birb"
	elif colour == ChessBoardStateScript.BLACK:
		match piece_type:
			ChessBoardStateScript.KING:
				return "big/MushroomKing"
			ChessBoardStateScript.QUEEN:
				return "blob/Mushnub_Evolved"
			ChessBoardStateScript.ROOK:
				return "big/Cactoro"
			ChessBoardStateScript.BISHOP:
				return "blob/Mushnub"
			ChessBoardStateScript.KNIGHT:
				return "blob/GreenSpikyBlob"
			ChessBoardStateScript.PAWN:
				return "blob/GreenBlob"
	push_error("ChessCast.body_for: no body for colour %d type %d" % [colour, piece_type])
	return ""


## The band a colour's pieces are painted into.
##
## The value ranges are the load-bearing part, and they are chosen so the two armies cannot be
## confused under any lighting: ivory's floor sits above slate's ceiling, which means no part of
## a light piece is ever darker than any part of a dark one. `chess_puppets` asserts it, because
## it is the kind of relationship that quietly stops holding the third time someone nudges a
## number to make a screenshot look better.
##
## Slate stops well short of black on purpose. The palette notes are blunt about where that road
## goes — bodies stop being different colours and start being the same silhouette, and the face
## goes first — and the faces are what makes a monster army worth having on a chessboard.
static func band_for(colour: int) -> CreatureVariation.Band:
	if colour == ChessBoardStateScript.WHITE:
		if _ivory == null:
			_ivory = CreatureVariationScript.make_band(
				"ivory",
				0.10,  ## warm, so it reads as ivory rather than as a grey undercoat
				0.16,
				Vector2(0.05, 0.22),
				Vector2(0.42, 0.97),
				Color(1.00, 0.95, 0.82)
			)
		return _ivory
	if colour == ChessBoardStateScript.BLACK:
		if _slate == null:
			_slate = CreatureVariationScript.make_band(
				"slate",
				0.58,  ## cold, and far enough from ivory's hue to survive the hue_keep blend
				0.16,
				Vector2(0.06, 0.24),
				Vector2(0.05, 0.40),
				Color(0.62, 0.80, 0.98)
			)
		return _slate
	push_error("ChessCast.band_for: %d is not a colour" % colour)
	return band_for(ChessBoardStateScript.WHITE)


static func height_for(piece_type: int) -> float:
	match piece_type:
		ChessBoardStateScript.KING:
			return HEIGHT_KING
		ChessBoardStateScript.QUEEN:
			return HEIGHT_QUEEN
		ChessBoardStateScript.ROOK:
			return HEIGHT_ROOK
		ChessBoardStateScript.BISHOP:
			return HEIGHT_BISHOP
		ChessBoardStateScript.KNIGHT:
			return HEIGHT_KNIGHT
		ChessBoardStateScript.PAWN:
			return HEIGHT_PAWN
	push_error("ChessCast.height_for: %d is not a piece type" % piece_type)
	return HEIGHT_PAWN


## The army a colour fields, for pre-warming the GLBs before the board is set up. First load
## of each file is synchronous, and twelve of them at once during setup is a visible hitch.
static func bodies() -> PackedStringArray:
	var out := PackedStringArray()
	for colour: int in [ChessBoardStateScript.WHITE, ChessBoardStateScript.BLACK]:
		for t: int in [
			ChessBoardStateScript.KING,
			ChessBoardStateScript.QUEEN,
			ChessBoardStateScript.ROOK,
			ChessBoardStateScript.BISHOP,
			ChessBoardStateScript.KNIGHT,
			ChessBoardStateScript.PAWN,
		]:
			out.append(body_for(colour, t))
	return out


## Human-readable side name, for logs and the arena's status line.
static func colour_name(colour: int) -> String:
	if colour == ChessBoardStateScript.WHITE:
		return "beast"
	if colour == ChessBoardStateScript.BLACK:
		return "grove"
	push_error("ChessCast.colour_name: %d is not a colour" % colour)
	return "?"
