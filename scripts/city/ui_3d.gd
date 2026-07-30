## Reusable vertical world-space UI surface.
##
## Local XY plane, facing −Z. Pointer hits report UV in [0,1]² (bottom-left origin).
## Named button regions live in the base class; subclasses handle `button_pressed` /
## `surface_pressed` for domain logic (Mandelbrot zoom, menus, etc.).
class_name Ui3D
extends Node3D

## Fired for any successful hit (including buttons). Prefer the specific signals below.
signal ui_pressed(uv: Vector2, local_point: Vector3, world_point: Vector3)
## Fired when the hit lands inside a registered button UV rect.
signal button_pressed(button_id: StringName, uv: Vector2)
## Fired when the hit lands on the face but outside every button.
signal surface_pressed(uv: Vector2, local_point: Vector3, world_point: Vector3)

const GROUP := "ui_3d"
const META_KEY := "ui_3d"
const HIT_EPSILON := 0.05
const COLLIDER_DEPTH_M := 0.08
const MARKER_M := 0.2
const MARKER_OFFSET_Z := -0.02
const BUTTON_Z := -0.015
const BUTTON_DEPTH := 0.03

@export var size_m: Vector2 = Vector2(5.0, 5.0)
@export var surface_color: Color = Color(0.22, 0.45, 0.72, 0.92)
@export var marker_color: Color = Color(1.0, 0.85, 0.15, 1.0)
## When true, non-button surface presses move a small square to the hit.
@export var show_debug_marker: bool = false

var _surface: MeshInstance3D = null
var _body: StaticBody3D = null
var _marker: MeshInstance3D = null
var _button_root: Node3D = null
## {id: StringName, uv_rect: Rect2, label: String, color: Color, mesh: MeshInstance3D}
var _buttons: Array[Dictionary] = []
var last_press_uv: Vector2 = Vector2.INF


func begin(origin: Vector3, face_yaw: float) -> void:
	global_position = origin
	rotation = Vector3(0.0, face_yaw, 0.0)
	_register_identity()
	_build_surface()
	_rebuild_button_meshes()


static func from_collider(collider: Variant) -> Node:
	var node := collider as Node
	while node != null:
		if node.has_method("press_at_world") and (
			node.is_in_group(GROUP)
			or bool(node.has_meta(META_KEY))
			or node.is_in_group("aim_panel")
			or bool(node.has_meta("aim_panel"))
		):
			return node
		node = node.get_parent()
	return null


func size() -> Vector2:
	return size_m


## Register a pressable UV region. Call before or after `begin` (meshes refresh either way).
func add_button(
	button_id: StringName,
	uv_rect: Rect2,
	label: String = "",
	color: Color = Color(0.15, 0.15, 0.18, 1.0)
) -> void:
	for i in range(_buttons.size()):
		if _buttons[i]["id"] == button_id:
			_buttons[i] = {
				"id": button_id,
				"uv_rect": uv_rect,
				"label": label,
				"color": color,
				"mesh": _buttons[i].get("mesh"),
			}
			_rebuild_button_meshes()
			return
	_buttons.append({
		"id": button_id,
		"uv_rect": uv_rect,
		"label": label,
		"color": color,
		"mesh": null,
	})
	_rebuild_button_meshes()


func clear_buttons() -> void:
	_buttons.clear()
	_rebuild_button_meshes()


## Live update of the face colour (e.g. Mandelbrot UI strip feedback).
func set_surface_color(color: Color) -> void:
	set_surface_glow(color, 0.0)


## Face colour plus emission strength. `emission_energy` > 0 makes the strip glow.
func set_surface_glow(color: Color, emission_energy: float) -> void:
	surface_color = color
	if _surface == null or not is_instance_valid(_surface):
		return
	var mat := _surface.material_override as StandardMaterial3D
	if mat == null:
		return
	var energy := maxf(emission_energy, 0.0)
	## Punch comes from emission; albedo stays a slightly darker base when glowing.
	mat.albedo_color = color.darkened(0.18) if energy > 0.01 else color
	mat.transparency = (
		BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 0.999
		else BaseMaterial3D.TRANSPARENCY_DISABLED
	)
	mat.emission_enabled = energy > 0.01
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = energy


func button_at_uv(uv: Vector2) -> StringName:
	for btn in _buttons:
		var rect: Rect2 = btn["uv_rect"]
		if rect.has_point(uv):
			return btn["id"] as StringName
	return StringName()


func world_to_uv(hit: Vector3) -> Vector2:
	var local := world_to_local_on_face(hit)
	if not is_finite(local.x):
		return Vector2.INF
	return _local_to_uv(local)


func world_to_local_on_face(hit: Vector3) -> Vector3:
	var local := to_local(hit)
	if not _local_on_face(local):
		return Vector3.INF
	var half := _half_extents()
	return Vector3(
		clampf(local.x, -half.x, half.x),
		clampf(local.y, -half.y, half.y),
		0.0
	)


func press_at_world(hit: Vector3) -> bool:
	var local := world_to_local_on_face(hit)
	if not is_finite(local.x):
		return false
	var uv := _local_to_uv(local)
	last_press_uv = uv
	ui_pressed.emit(uv, local, hit)
	var button_id := button_at_uv(uv)
	if button_id != StringName():
		button_pressed.emit(button_id, uv)
		return true
	if show_debug_marker:
		_place_marker(local)
	surface_pressed.emit(uv, local, hit)
	return true


func mark_at_world(hit: Vector3) -> bool:
	var local := world_to_local_on_face(hit)
	if not is_finite(local.x):
		return false
	var uv := _local_to_uv(local)
	_place_marker(local)
	last_press_uv = uv
	ui_pressed.emit(uv, local, hit)
	var button_id := button_at_uv(uv)
	if button_id != StringName():
		button_pressed.emit(button_id, uv)
	else:
		surface_pressed.emit(uv, local, hit)
	return true


func has_marker() -> bool:
	return _marker != null and is_instance_valid(_marker)


func marker_local_position() -> Vector3:
	if not has_marker():
		return Vector3.INF
	return _marker.position


func clear_marker() -> void:
	if _marker != null and is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null


func _register_identity() -> void:
	add_to_group(GROUP)
	set_meta(META_KEY, true)
	add_to_group("aim_panel")
	set_meta("aim_panel", true)


func _half_extents() -> Vector2:
	return Vector2(maxf(size_m.x, 0.001) * 0.5, maxf(size_m.y, 0.001) * 0.5)


func _local_to_uv(local: Vector3) -> Vector2:
	var half := _half_extents()
	var w := maxf(size_m.x, 0.001)
	var h := maxf(size_m.y, 0.001)
	return Vector2((local.x + half.x) / w, (local.y + half.y) / h)


func _uv_to_local(uv: Vector2) -> Vector3:
	var half := _half_extents()
	return Vector3(
		uv.x * size_m.x - half.x,
		uv.y * size_m.y - half.y,
		0.0
	)


func _local_on_face(local: Vector3) -> bool:
	var half := _half_extents()
	return (
		absf(local.x) <= half.x + HIT_EPSILON
		and absf(local.y) <= half.y + HIT_EPSILON
	)


func _build_surface() -> void:
	if _surface != null and is_instance_valid(_surface):
		_surface.queue_free()
	if _body != null and is_instance_valid(_body):
		_body.queue_free()

	_surface = MeshInstance3D.new()
	_surface.name = "Surface"
	var quad := QuadMesh.new()
	quad.size = size_m
	_surface.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = surface_color
	mat.transparency = (
		BaseMaterial3D.TRANSPARENCY_ALPHA if surface_color.a < 0.999
		else BaseMaterial3D.TRANSPARENCY_DISABLED
	)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_surface.material_override = mat
	add_child(_surface)

	_body = StaticBody3D.new()
	_body.name = "HitBody"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.add_to_group(GROUP)
	_body.set_meta(META_KEY, true)
	_body.add_to_group("aim_panel")
	_body.set_meta("aim_panel", true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size_m.x, size_m.y, COLLIDER_DEPTH_M)
	shape.shape = box
	_body.add_child(shape)
	add_child(_body)


func _rebuild_button_meshes() -> void:
	if _button_root != null and is_instance_valid(_button_root):
		_button_root.queue_free()
	_button_root = null
	## Buttons registered before begin wait until the surface exists.
	if _surface == null or _buttons.is_empty():
		return
	_button_root = Node3D.new()
	_button_root.name = "Buttons"
	add_child(_button_root)
	for i in range(_buttons.size()):
		var btn: Dictionary = _buttons[i]
		var rect: Rect2 = btn["uv_rect"]
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.name = "Btn_%s" % str(btn["id"])
		var quad := QuadMesh.new()
		quad.size = Vector2(rect.size.x * size_m.x, rect.size.y * size_m.y)
		mesh_inst.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = btn["color"] as Color
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_inst.material_override = mat
		var center_uv := rect.position + rect.size * 0.5
		var local := _uv_to_local(center_uv)
		mesh_inst.position = Vector3(local.x, local.y, BUTTON_Z)
		_button_root.add_child(mesh_inst)
		var label := str(btn.get("label", ""))
		if label == "+" or label == "-":
			## Geometric glyphs stay sharper than tiny font strokes for ±.
			_add_button_glyph(mesh_inst, label, btn["color"] as Color)
		elif not label.is_empty():
			_add_button_label(mesh_inst, label, btn["color"] as Color)
		_buttons[i]["mesh"] = mesh_inst


func _add_button_glyph(parent: MeshInstance3D, label: String, base: Color) -> void:
	var glyph := MeshInstance3D.new()
	glyph.name = "Glyph"
	var quad := QuadMesh.new()
	## Horizontal bar shared by + and −.
	quad.size = Vector2(parent.mesh.size.x * 0.45, parent.mesh.size.y * 0.12)
	glyph.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0).lerp(base.inverted(), 0.15)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	glyph.material_override = mat
	glyph.position = Vector3(0.0, 0.0, -BUTTON_DEPTH)
	parent.add_child(glyph)
	if label == "+":
		var vert := MeshInstance3D.new()
		vert.name = "GlyphV"
		var vquad := QuadMesh.new()
		vquad.size = Vector2(parent.mesh.size.x * 0.12, parent.mesh.size.y * 0.45)
		vert.mesh = vquad
		vert.material_override = mat
		vert.position = Vector3(0.0, 0.0, -BUTTON_DEPTH)
		parent.add_child(vert)


## World-space text for ordinary button captions (e.g. "Create"). Faces the panel −Z.
func _add_button_label(parent: MeshInstance3D, label: String, base: Color) -> void:
	var lbl := Label3D.new()
	lbl.name = "Label"
	lbl.text = label
	lbl.font_size = 64
	var btn_h: float = (parent.mesh as QuadMesh).size.y
	lbl.pixel_size = (btn_h * 0.52) / 64.0
	lbl.modulate = Color(1.0, 1.0, 1.0, 1.0).lerp(base.lightened(0.65), 0.35)
	lbl.outline_size = 16
	lbl.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	lbl.double_sided = true
	lbl.no_depth_test = false
	## QuadMesh faces −Z; Label3D faces +Z by default — flip to match the panel face.
	lbl.position = Vector3(0.0, 0.0, -BUTTON_DEPTH)
	lbl.rotation.y = PI
	parent.add_child(lbl)


func _place_marker(local: Vector3) -> void:
	_ensure_marker()
	_marker.position = Vector3(local.x, local.y, MARKER_OFFSET_Z)


func _ensure_marker() -> void:
	if _marker != null and is_instance_valid(_marker):
		return
	_marker = MeshInstance3D.new()
	_marker.name = "Ui3DMarker"
	var quad := QuadMesh.new()
	quad.size = Vector2(MARKER_M, MARKER_M)
	_marker.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = marker_color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_marker.material_override = mat
	add_child(_marker)
