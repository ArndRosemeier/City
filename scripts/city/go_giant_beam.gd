## Column of light that drops onto a crossing where a giant stone is about to land.
##
## The giant stones are slate and chalk voxels, so the colour has to come from somewhere
## else: violet announces Black, yellow announces White.
class_name GoGiantBeam
extends Node3D

const BLACK_LIGHT := Color(0.66, 0.3, 1.0)
const WHITE_LIGHT := Color(1.0, 0.84, 0.3)

## Everything scales off the board's cell spacing, so 9×9 and 19×19 read the same.
const HEIGHT_CELLS := 14.0
const START_CELLS := 9.0
const CORE_RADIUS_CELLS := 0.32
const HALO_RADIUS_CELLS := 0.78
const FLARE_RADIUS_CELLS := 2.4

const DROP_SEC := 0.42
const IMPACT_SEC := 0.34
const HOLD_SEC := 0.09
const FADE_SEC := 0.34
const TEX_PX := 128

static var _fade_tex: ImageTexture = null
static var _flare_tex: ImageTexture = null

var cell_m: float = 2.0
var _shaft: Node3D = null
var _core_mat: StandardMaterial3D = null
var _halo_mat: StandardMaterial3D = null
var _flare: MeshInstance3D = null
var _flare_mat: StandardMaterial3D = null
var _light: OmniLight3D = null
var _tint: Color = WHITE_LIGHT
var _place_epoch: int = 0
var _tween: Tween = null


## Rebuilds the column for the current cell spacing. Safe to call again after a 9↔19
## switch — the old meshes go with it.
func configure(p_cell_m: float) -> void:
	if p_cell_m <= 0.0:
		push_error("GoGiantBeam.configure: bad cell size %f" % p_cell_m)
		return
	cell_m = p_cell_m
	_kill_tween()
	for c in get_children():
		c.queue_free()
	var height := cell_m * HEIGHT_CELLS

	_shaft = Node3D.new()
	_shaft.name = "Shaft"
	add_child(_shaft)
	## Cylinders are centred on their origin; lift them so the shaft's own origin is the
	## bottom of the beam, which is what the drop animation moves.
	_halo_mat = _add_column(cell_m * HALO_RADIUS_CELLS, height, 0.3)
	_core_mat = _add_column(cell_m * CORE_RADIUS_CELLS, height, 0.95)

	_flare = MeshInstance3D.new()
	_flare.name = "Flare"
	var quad := QuadMesh.new()
	quad.size = Vector2(cell_m * FLARE_RADIUS_CELLS * 2.0, cell_m * FLARE_RADIUS_CELLS * 2.0)
	_flare.mesh = quad
	_flare_mat = _glow_material(_shared_flare_tex())
	_flare.material_override = _flare_mat
	_flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	## QuadMesh faces +Z; tip it so the splash lies on the board.
	_flare.rotation.x = deg_to_rad(-90.0)
	_flare.position = Vector3(0.0, cell_m * 0.12, 0.0)
	add_child(_flare)

	_light = OmniLight3D.new()
	_light.name = "Impact"
	_light.omni_range = cell_m * 7.0
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, cell_m * 0.8, 0.0)
	add_child(_light)

	visible = false


func cancel() -> void:
	_place_epoch += 1
	_kill_tween()
	visible = false


## Drops the column onto `world_target` and returns at the moment of impact, so the
## caller can put the stone down inside the flash. The retract plays on afterwards.
func place_at(world_target: Vector3, is_black: bool) -> void:
	if _shaft == null:
		push_error("GoGiantBeam.place_at: configure was never called")
		return
	_place_epoch += 1
	var epoch := _place_epoch
	_kill_tween()
	_tint = BLACK_LIGHT if is_black else WHITE_LIGHT
	_apply_tint(0.0)
	global_position = world_target
	_shaft.position.y = cell_m * START_CELLS
	_flare.scale = Vector3.ONE * 0.35
	_light.light_energy = 0.0
	visible = true

	_tween = create_tween()
	_tween.set_parallel(true)
	## Accelerating fall, so it lands rather than drifts.
	(
		_tween
		. tween_property(_shaft, "position:y", 0.0, DROP_SEC)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	_tween.tween_method(_apply_tint, 0.0, 1.0, DROP_SEC * 0.4)
	await _tween.finished
	if epoch != _place_epoch:
		return

	_flash(epoch)
	await get_tree().create_timer(HOLD_SEC).timeout
	if epoch != _place_epoch:
		return
	_retract(epoch)


## Splash of light on the board plus a short-lived point light. Not awaited: the stone
## should appear while this is still bright.
func _flash(epoch: int) -> void:
	var flash := create_tween()
	flash.set_parallel(true)
	flash.tween_property(_flare, "scale", Vector3.ONE * 1.35, IMPACT_SEC).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(Tween.EASE_OUT)
	flash.tween_method(_apply_flare_alpha, 1.0, 0.0, IMPACT_SEC)
	flash.tween_property(_light, "light_energy", 0.0, IMPACT_SEC).from(cell_m * 2.6)
	await flash.finished
	if epoch == _place_epoch:
		_light.light_energy = 0.0


func _retract(epoch: int) -> void:
	_kill_tween()
	_tween = create_tween()
	_tween.set_parallel(true)
	(
		_tween
		. tween_property(_shaft, "position:y", cell_m * START_CELLS * 0.6, FADE_SEC)
		. set_trans(Tween.TRANS_SINE)
		. set_ease(Tween.EASE_IN)
	)
	_tween.tween_method(_apply_tint, 1.0, 0.0, FADE_SEC)
	await _tween.finished
	if epoch != _place_epoch:
		return
	visible = false
	_tween = null


func _apply_tint(strength: float) -> void:
	if _core_mat == null or _halo_mat == null:
		return
	_core_mat.albedo_color = Color(_tint.r, _tint.g, _tint.b, 0.95 * strength)
	_halo_mat.albedo_color = Color(_tint.r, _tint.g, _tint.b, 0.3 * strength)


func _apply_flare_alpha(alpha: float) -> void:
	if _flare_mat == null:
		return
	_flare_mat.albedo_color = Color(_tint.r, _tint.g, _tint.b, alpha)


func _add_column(radius: float, height: float, alpha: float) -> StandardMaterial3D:
	var inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 40
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	inst.mesh = cyl
	var mat := _glow_material(_shared_fade_tex())
	## CylinderMesh packs the side into v 0..0.5 (v=0 is the top rim) and the caps into
	## the rest. Doubling v spreads the ramp texture across the side alone.
	mat.uv1_scale = Vector3(1.0, 2.0, 1.0)
	mat.albedo_color = Color(_tint.r, _tint.g, _tint.b, alpha)
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.position = Vector3(0.0, height * 0.5, 0.0)
	_shaft.add_child(inst)
	return mat


static func _glow_material(tex: Texture2D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	## Additive so the beam brightens whatever is behind it instead of tinting it.
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = tex
	mat.disable_receive_shadows = true
	return mat


## Vertical ramp: solid where the beam meets the board, thinning out toward the sky.
static func _shared_fade_tex() -> ImageTexture:
	if _fade_tex == null:
		var img := Image.create(4, TEX_PX, false, Image.FORMAT_RGBA8)
		for py in range(TEX_PX):
			## Row 0 is the top of the column, the last row is where it meets the board.
			var down := float(py) / float(TEX_PX - 1)
			var body := pow(down, 1.6) * 0.85 + 0.15
			## Only the leading tip is soft, so a falling column has no cut-off edge
			## while a landed one still meets the board solidly.
			var tip := 0.55 + 0.45 * (1.0 - smoothstep(0.93, 1.0, down))
			for px in range(4):
				img.set_pixel(px, py, Color(1.0, 1.0, 1.0, body * tip))
		_fade_tex = ImageTexture.create_from_image(img)
	return _fade_tex


## Soft round splash for the moment of contact.
static func _shared_flare_tex() -> ImageTexture:
	if _flare_tex == null:
		var img := Image.create(TEX_PX, TEX_PX, false, Image.FORMAT_RGBA8)
		img.fill(Color(1.0, 1.0, 1.0, 0.0))
		var half := float(TEX_PX) * 0.5
		for py in range(TEX_PX):
			for px in range(TEX_PX):
				var dx := (float(px) + 0.5 - half) / half
				var dy := (float(py) + 0.5 - half) / half
				var r := sqrt(dx * dx + dy * dy)
				if r >= 1.0:
					continue
				## Bright core with a long tail, so the edge never shows as a ring.
				var a := pow(1.0 - r, 2.4)
				img.set_pixel(px, py, Color(1.0, 1.0, 1.0, a))
		_flare_tex = ImageTexture.create_from_image(img)
	return _flare_tex


func _kill_tween() -> void:
	if _tween != null and is_instance_valid(_tween):
		_tween.kill()
	_tween = null
