## A fingerpost: one timber pole carrying arrow boards, each naming a neighbouring district
## and physically pointing at it.
##
## ORIENTATION — read this before changing any yaw here.
##
## A board is modelled along local **+X with the arrow tip at +X**, faces on ±Z. Yaw θ about
## Y gives the basis whose x column is `(cos θ, 0, -sin θ)`, so aiming the tip along a world
## direction `d` needs `θ = atan2(-d.z, d.x)`. The engine-wide "local −Z looks at (x, z)" rule
## used elsewhere in the city is `atan2(-x, -z)`, and it drops out of that same basis (the −z
## column is `(-sin θ, 0, -cos θ)`) — so the two conventions cannot silently disagree.
##
## Both faces of a board get their own Label3D, each single-sided and facing outward, so the
## name reads the right way round from either side of the post. The arrow tip is one physical
## direction, so it appears on the reader's left from one side and the right from the other —
## that is a real fingerpost, not a bug.
##
## The root node stays unrotated: board yaw is absolute world yaw.
class_name Signpost
extends Node3D

const POLE_HEIGHT_M := 4.4
const POLE_TOP_RADIUS_M := 0.07
const POLE_BOTTOM_RADIUS_M := 0.09
## Straight part of a board, measured out from the pole axis, then the triangular tip.
const PLANK_LEN_M := 1.7
const TIP_LEN_M := 0.5
const BOARD_HEIGHT_M := 0.34
const BOARD_THICKNESS_M := 0.07
## Highest board's centre, then each further board sits this much lower.
const BOARD_TOP_Y_M := 4.0
const BOARD_PITCH_M := 0.46

const FONT_PX := 48
## Mean glyph advance of the default font in ems — used to fit a caption to the plank.
const GLYPH_ADVANCE_EM := 0.55
const LABEL_LIFT_M := 0.012

var _boards: Array[Node3D] = []
var _tips: Array[Node3D] = []
var _labels: Array[Label3D] = []
var _pole_mat: StandardMaterial3D
var _board_mat: StandardMaterial3D


## Yaw that aims a board's local +X tip along the world XZ direction `direction`.
static func board_yaw(direction: Vector3) -> float:
	var flat := Vector2(direction.x, direction.z)
	if flat.length_squared() < 0.000001:
		push_error("Signpost.board_yaw: direction has no horizontal component")
		return 0.0
	flat = flat.normalized()
	return atan2(-flat.y, flat.x)


## Build the bare pole. Call once, before any add_board().
func build_pole() -> void:
	_ensure_mats()
	var pole := MeshInstance3D.new()
	pole.name = "Pole"
	var shaft := CylinderMesh.new()
	shaft.top_radius = POLE_TOP_RADIUS_M
	shaft.bottom_radius = POLE_BOTTOM_RADIUS_M
	shaft.height = POLE_HEIGHT_M
	pole.mesh = shaft
	pole.material_override = _pole_mat
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pole.position.y = POLE_HEIGHT_M * 0.5
	add_child(pole)

	var finial := MeshInstance3D.new()
	finial.name = "Finial"
	var knob := SphereMesh.new()
	knob.radius = POLE_TOP_RADIUS_M * 1.8
	knob.height = POLE_TOP_RADIUS_M * 3.2
	finial.mesh = knob
	finial.material_override = _pole_mat
	finial.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	finial.position.y = POLE_HEIGHT_M
	add_child(finial)


## Hang one arrow board pointing along `direction` (world XZ), captioned `text`.
## Boards stack downward in call order, so pass the most useful one first.
func add_board(direction: Vector3, text: String) -> void:
	_ensure_mats()
	var board := Node3D.new()
	board.name = "Board_%s" % text.replace(" ", "_")
	board.position.y = BOARD_TOP_Y_M - float(_boards.size()) * BOARD_PITCH_M
	board.rotation.y = board_yaw(direction)
	add_child(board)

	var plank := MeshInstance3D.new()
	plank.name = "Plank"
	var plank_mesh := BoxMesh.new()
	plank_mesh.size = Vector3(PLANK_LEN_M, BOARD_HEIGHT_M, BOARD_THICKNESS_M)
	plank.mesh = plank_mesh
	plank.material_override = _board_mat
	plank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plank.position.x = PLANK_LEN_M * 0.5
	board.add_child(plank)

	## PrismMesh tapers along +Y, so roll it -90° about Z to send the apex to +X.
	var tip := MeshInstance3D.new()
	tip.name = "Tip"
	var tip_mesh := PrismMesh.new()
	tip_mesh.size = Vector3(BOARD_HEIGHT_M, TIP_LEN_M, BOARD_THICKNESS_M)
	tip.mesh = tip_mesh
	tip.material_override = _board_mat
	tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tip.rotation.z = -PI * 0.5
	tip.position.x = PLANK_LEN_M + TIP_LEN_M * 0.5
	board.add_child(tip)

	## One caption per face. A Label3D reads from its own local +Z, so the face on the
	## board's −Z side is the one that needs the PI flip.
	var front := _make_label(text)
	front.name = "CaptionFront"
	front.position = Vector3(
		PLANK_LEN_M * 0.5, 0.0, -(BOARD_THICKNESS_M * 0.5 + LABEL_LIFT_M)
	)
	front.rotation.y = PI
	board.add_child(front)

	var back := _make_label(text)
	back.name = "CaptionBack"
	back.position = Vector3(
		PLANK_LEN_M * 0.5, 0.0, BOARD_THICKNESS_M * 0.5 + LABEL_LIFT_M
	)
	board.add_child(back)

	_boards.append(board)
	_tips.append(tip)
	_labels.append(front)
	_labels.append(back)


func board_count() -> int:
	return _boards.size()


## World-space XZ direction from the pole to a board's physical arrow tip. Read off the live
## node transforms rather than the requested direction, so a flipped board shows up here.
func board_tip_direction(index: int) -> Vector3:
	var tip: Node3D = _tips[index]
	var away := tip.global_position - global_position
	away.y = 0.0
	return away.normalized()


## Where a board meets the pole, in world space.
func board_origin(index: int) -> Vector3:
	return _boards[index].global_position


## Global transforms of the two captions on board `index`, as [front, back]. A Label3D reads
## from its local +Z, so `basis.z` is the side you can read it from — exposed so a test can
## prove each caption sits on, and faces out of, the plank face it belongs to.
func caption_transforms(index: int) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.append((_labels[index * 2] as Label3D).global_transform)
	out.append((_labels[index * 2 + 1] as Label3D).global_transform)
	return out


func board_text(index: int) -> String:
	return _labels[index * 2].text


func _make_label(text: String) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = FONT_PX
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	## Shrink long names until they fit the plank instead of overhanging the tip.
	var chars := maxf(1.0, float(text.length()))
	var em := minf(
		BOARD_HEIGHT_M * 0.74, PLANK_LEN_M * 0.9 / (GLYPH_ADVANCE_EM * chars)
	)
	label.pixel_size = em / float(FONT_PX)
	label.modulate = Color(0.11, 0.09, 0.08)
	label.outline_size = 10
	label.outline_modulate = Color(0.93, 0.90, 0.82)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	return label


func _ensure_mats() -> void:
	if _pole_mat != null:
		return
	_pole_mat = StandardMaterial3D.new()
	_pole_mat.albedo_color = Color(0.34, 0.23, 0.14)
	_pole_mat.roughness = 0.85
	_board_mat = StandardMaterial3D.new()
	_board_mat.albedo_color = Color(0.90, 0.87, 0.78)
	_board_mat.roughness = 0.7
