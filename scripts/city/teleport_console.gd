## One tilted holo-console in a teleport chamber: a slice of the 5x5 district map.
##
## A console owns no map logic — TeleportChamber decides which district coordinates land on
## which console and in what order. This class only turns that list into a lectern you can
## read from the middle of the room and press.
class_name TeleportConsole
extends Ui3D

## A panel was pressed. `coord` is the *absolute* district tile, not the offset.
signal district_chosen(coord: Vector2i)

## Degrees the face leans back from vertical. A lectern, not a wall: you stand in the middle
## of the room and read outward and slightly down.
const TILT_DEG := 30.0
## Height of the panel centre above the chamber floor, in metres.
const PANEL_CENTER_Y_M := 1.05
## Gap around each panel as a fraction of its cell, so panels read as separate keys.
const PANEL_GAP_FRAC := 0.08

const COLOR_FACE := Color(0.03, 0.09, 0.14, 0.95)
const COLOR_PANEL := Color(0.05, 0.20, 0.30, 1.0)
const COLOR_PANEL_SELECTED := Color(0.10, 0.72, 0.85, 1.0)
const GLOW_FACE := Color(0.05, 0.32, 0.45, 0.95)
const GLOW_FACE_SELECTED := Color(0.12, 0.70, 0.85, 0.95)
const GLOW_ENERGY := 0.5
const GLOW_ENERGY_SELECTED := 1.6
const LABEL_ON_IDLE := Color(0.88, 0.98, 1.0, 1.0)
const LABEL_ON_SELECTED := Color(0.02, 0.10, 0.14, 1.0)
const OUTLINE_ON_IDLE := Color(0.0, 0.05, 0.08, 0.9)
const OUTLINE_ON_SELECTED := Color(0.75, 1.0, 1.0, 0.9)

## Absolute district tile per button id.
var _coord_by_id: Dictionary = {}
## Button id per absolute district tile, so selection is a lookup and not a scan.
var _id_by_coord: Dictionary = {}
var _selected: Vector2i = Vector2i.MAX


## Lay out `coords` (row-major, near row first, left to right) as `columns` columns.
## `labels` runs parallel to `coords`. `outward` is the world direction from the room centre
## to this console — the face turns back along it so the console looks at the player.
func setup(
	origin: Vector3,
	outward: Vector3,
	coords: Array[Vector2i],
	labels: PackedStringArray,
	columns: int,
	panel_size: Vector2
) -> void:
	if coords.size() != labels.size():
		push_error(
			"TeleportConsole.setup: %d coords but %d labels" % [coords.size(), labels.size()]
		)
		return
	if columns <= 0 or coords.size() % columns != 0:
		push_error(
			"TeleportConsole.setup: %d coords do not fill %d columns" % [coords.size(), columns]
		)
		return
	var rows := coords.size() / columns
	size_m = Vector2(panel_size.x * float(columns), panel_size.y * float(rows))
	surface_color = COLOR_FACE
	show_debug_marker = false
	## Ui3D faces local −Z; a yaw of atan2 of the *inward* direction turns that face back at
	## the room centre.
	begin(origin, atan2(outward.x, outward.z))
	rotation.x = deg_to_rad(TILT_DEG)
	set_surface_glow(GLOW_FACE, GLOW_ENERGY)
	clear_buttons()
	_coord_by_id.clear()
	_id_by_coord.clear()
	_selected = Vector2i.MAX
	var cell_w := 1.0 / float(columns)
	var cell_h := 1.0 / float(rows)
	for i in range(coords.size()):
		var col := i % columns
		## Index 0 is the near row, which reads at the *bottom* of a lectern.
		var row := i / columns
		var coord: Vector2i = coords[i]
		var id := _button_id(coord)
		_coord_by_id[id] = coord
		_id_by_coord[coord] = id
		## No caption here: Ui3D sizes button text off the button *height*, which a district
		## name would overrun sideways. `_add_fitted_label` sizes off the width instead.
		add_button(
			id,
			Rect2(
				(float(col) + PANEL_GAP_FRAC * 0.5) * cell_w,
				(float(row) + PANEL_GAP_FRAC * 0.5) * cell_h,
				cell_w * (1.0 - PANEL_GAP_FRAC),
				cell_h * (1.0 - PANEL_GAP_FRAC)
			),
			"",
			COLOR_PANEL,
			true
		)
	rebuild_buttons()
	for i in range(coords.size()):
		_add_fitted_label(_button_id(coords[i]), labels[i])
	if not button_pressed.is_connected(_on_button_pressed):
		button_pressed.connect(_on_button_pressed)


## District tiles this console shows, in panel order.
func coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for coord: Vector2i in _id_by_coord.keys():
		out.append(coord)
	return out


func shows_coord(coord: Vector2i) -> bool:
	return _id_by_coord.has(coord)


## The tile lit on this console, or Vector2i.MAX when none is.
func selected_coord() -> Vector2i:
	return _selected


func has_selection() -> bool:
	return _selected != Vector2i.MAX


## Light `coord` and darken everything else here. Pass Vector2i.MAX to clear the console —
## that is what the other seven get when one of them is armed.
func set_selected(coord: Vector2i) -> void:
	if coord != Vector2i.MAX and not _id_by_coord.has(coord):
		coord = Vector2i.MAX
	if _selected == coord:
		return
	_selected = coord
	for tile: Vector2i in _id_by_coord.keys():
		var id: StringName = _id_by_coord[tile]
		var lit := tile == coord
		_recolor(id, COLOR_PANEL_SELECTED if lit else COLOR_PANEL)
	var armed := coord != Vector2i.MAX
	set_surface_glow(
		GLOW_FACE_SELECTED if armed else GLOW_FACE,
		GLOW_ENERGY_SELECTED if armed else GLOW_ENERGY
	)


## Rough advance width of one glyph as a fraction of the font size, for the default face.
## Only used to shrink long names until they fit — an over-estimate just leaves margin.
const GLYPH_ADVANCE_FRAC := 0.55
## Fraction of the panel width a name is allowed to fill.
const LABEL_FILL_FRAC := 0.88


## District names run from four to a dozen characters, so the type has to shrink to the
## longest one rather than to a fixed size. Ui3D's own captions scale off button height only.
func _add_fitted_label(id: StringName, text: String) -> void:
	if text.is_empty():
		push_error("TeleportConsole: panel %s has no district name" % id)
		return
	var mesh := _panel_mesh(id)
	if mesh == null:
		push_error("TeleportConsole: panel %s has no mesh to caption" % id)
		return
	var quad := mesh.mesh as QuadMesh
	if quad == null:
		push_error("TeleportConsole: panel %s is not a quad" % id)
		return
	var by_width := (
		quad.size.x * LABEL_FILL_FRAC
		/ (float(text.length()) * GLYPH_ADVANCE_FRAC * float(LABEL_FONT_PX))
	)
	var by_height := quad.size.y * 0.42 / float(LABEL_FONT_PX)
	var lbl := Label3D.new()
	lbl.name = "Name"
	lbl.text = text
	lbl.font_size = LABEL_FONT_PX
	lbl.pixel_size = minf(by_width, by_height)
	lbl.modulate = LABEL_ON_IDLE
	lbl.outline_size = int(round(14.0 * float(LABEL_FONT_PX) / 64.0))
	lbl.outline_modulate = OUTLINE_ON_IDLE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lbl.double_sided = true
	lbl.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	lbl.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	## QuadMesh faces −Z; Label3D faces +Z by default.
	lbl.position = Vector3(0.0, 0.0, -BUTTON_DEPTH)
	lbl.rotation.y = PI
	mesh.add_child(lbl)


func _panel_mesh(id: StringName) -> MeshInstance3D:
	for btn in _buttons:
		if btn["id"] == id:
			return btn.get("mesh") as MeshInstance3D
	return null


static func _button_id(coord: Vector2i) -> StringName:
	return StringName("tile_%d_%d" % [coord.x, coord.y])


## Repaint one panel without rebuilding the console: `add_button` on an existing id keeps the
## rect and the label, and a rebuild would respawn every Label3D on every press.
func _recolor(id: StringName, color: Color) -> void:
	for btn in _buttons:
		if btn["id"] != id:
			continue
		btn["color"] = color
		var mesh: MeshInstance3D = btn.get("mesh") as MeshInstance3D
		if mesh == null or not is_instance_valid(mesh):
			return
		var mat := mesh.material_override as StandardMaterial3D
		if mat == null:
			push_error("TeleportConsole._recolor: panel %s has no material" % id)
			return
		var lit := color == COLOR_PANEL_SELECTED
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = Color(color.r, color.g, color.b)
		mat.emission_energy_multiplier = 1.4 if lit else 0.35
		## Pale type on a lit panel washes out; the armed one reads as ink on a bright key.
		var lbl := mesh.get_node_or_null("Name") as Label3D
		if lbl != null:
			lbl.modulate = LABEL_ON_SELECTED if lit else LABEL_ON_IDLE
			lbl.outline_modulate = (
				OUTLINE_ON_SELECTED if lit else OUTLINE_ON_IDLE
			)
		return


func _on_button_pressed(button_id: StringName, _uv: Vector2) -> void:
	if not _coord_by_id.has(button_id):
		push_error("TeleportConsole: panel %s is not on the map" % button_id)
		return
	district_chosen.emit(_coord_by_id[button_id] as Vector2i)
