## Monster Zoo arrival spectacle: a shield-style halo and a few seconds of the body
## fading from ghost to solid under the summon gazebo.
##
## Parent is the ZooController (always ticking). The unit itself is frozen for the
## duration so it cannot fight or walk while it is still half air.
extends Node

const BoostAuraVfxScript := preload("res://scripts/city/boost_aura_vfx.gd")

## How long the body takes to become solid. Short enough to keep the war moving,
## long enough to read as a summon rather than a teleport.
const MATERIALIZE_SEC := 2.8
const START_ALPHA := 0.04
const END_ALPHA := 1.0


var _unit: UndeadUnit = null
var _aura: Node3D = null
var _ghost_mats: Array[StandardMaterial3D] = []
var _restore: Array[Dictionary] = []


## Freeze `unit`, wrap it in a faction-coloured ward, and fade its mesh to solid.
func begin(unit: UndeadUnit, halo_color: Color) -> void:
	if unit == null or not is_instance_valid(unit):
		queue_free()
		return
	name = "ZooSummonVfx"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_unit = unit
	unit.velocity = Vector3.ZERO
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	_apply_ghost_look(unit)
	_spawn_halo(unit, halo_color)
	_sfx("play_zoo_summon_start", unit.global_position, unit.character_scale)
	var tw := create_tween()
	tw.set_parallel(true)
	for mat: StandardMaterial3D in _ghost_mats:
		tw.tween_method(_set_mat_alpha.bind(mat), START_ALPHA, END_ALPHA, MATERIALIZE_SEC).set_trans(
			Tween.TRANS_CUBIC
		).set_ease(Tween.EASE_OUT)
	tw.finished.connect(_finish)


func _spawn_halo(unit: UndeadUnit, color: Color) -> void:
	_aura = BoostAuraVfxScript.new() as Node3D
	_aura.name = "SummonHalo"
	_aura.process_mode = Node.PROCESS_MODE_ALWAYS
	unit.add_child(_aura)
	_aura.call("setup")
	_aura.call("set_shield_color", color)
	_aura.call("set_body_scale", maxf(unit.character_scale, 0.5))
	_aura.call("set_shield_active", true)


func _apply_ghost_look(unit: UndeadUnit) -> void:
	var model := unit.get_node_or_null("CreatureModel")
	if model == null:
		return
	_walk_meshes(model)


func _walk_meshes(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mesh := mi.mesh
		if mesh != null:
			for s in range(mesh.get_surface_count()):
				var src := mi.get_active_material(s)
				var ghost := _ghost_copy(src)
				_restore.append({
					"mi": mi,
					"surface": s,
					"override": mi.get_surface_override_material(s),
				})
				mi.set_surface_override_material(s, ghost)
				_ghost_mats.append(ghost)
	for c in n.get_children():
		_walk_meshes(c)


## Flatten to an alpha-capable StandardMaterial3D. The creature palette shader never
## writes ALPHA, so running it in the transparent pipeline would leave the body opaque.
func _ghost_copy(src: Material) -> StandardMaterial3D:
	var out := StandardMaterial3D.new()
	out.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	out.cull_mode = BaseMaterial3D.CULL_DISABLED
	out.albedo_color = Color(1.0, 1.0, 1.0, START_ALPHA)
	if src is StandardMaterial3D:
		var m := src as StandardMaterial3D
		out.albedo_texture = m.albedo_texture
		var c := m.albedo_color
		c.a = START_ALPHA
		out.albedo_color = c
		out.emission_enabled = m.emission_enabled
		out.emission = m.emission
		out.emission_energy_multiplier = m.emission_energy_multiplier
	elif src is ShaderMaterial:
		var sm := src as ShaderMaterial
		var tex: Variant = sm.get_shader_parameter("albedo_tex")
		if tex is Texture2D:
			out.albedo_texture = tex as Texture2D
		var base: Variant = sm.get_shader_parameter("albedo_base")
		if base is Color:
			var bc := base as Color
			bc.a = START_ALPHA
			out.albedo_color = bc
		## Soft self-light so a near-invisible body still reads in daylight.
		out.emission_enabled = true
		out.emission = out.albedo_color
		out.emission_energy_multiplier = 1.4
	return out


func _set_mat_alpha(alpha: float, mat: StandardMaterial3D) -> void:
	if mat == null:
		return
	var c := mat.albedo_color
	c.a = alpha
	mat.albedo_color = c
	if mat.emission_enabled:
		mat.emission_energy_multiplier = lerpf(2.4, 0.2, alpha)


func _finish() -> void:
	if _unit != null and is_instance_valid(_unit):
		_sfx("play_zoo_summon_ready", _unit.global_position, _unit.character_scale)
		_restore_materials()
		_unit.process_mode = Node.PROCESS_MODE_INHERIT
	if _aura != null and is_instance_valid(_aura):
		_aura.queue_free()
	_aura = null
	_unit = null
	_ghost_mats.clear()
	_restore.clear()
	queue_free()


func _sfx(method: String, world_pos: Vector3, character_scale: float) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var audio := tree.get_first_node_in_group(&"city_audio")
	if audio != null and audio.has_method(method):
		audio.call(method, world_pos, character_scale)


func _restore_materials() -> void:
	for row: Dictionary in _restore:
		var mi: MeshInstance3D = row.get("mi") as MeshInstance3D
		if mi == null or not is_instance_valid(mi):
			continue
		var surface: int = int(row.get("surface", 0))
		var override: Material = row.get("override") as Material
		mi.set_surface_override_material(surface, override)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
