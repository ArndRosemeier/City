## Floating holographic monster above the Arena pit: walk-in-place, occasional turns,
## cycles a random summonable body every 20 s. Visual-only — no collision, nav, or combat.
class_name ArenaHologram
extends Node3D

const CreatureCatalogScript := preload("res://scripts/city/creature_catalog.gd")
const CreatureClipsScript := preload("res://scripts/city/creature_clips.gd")
const MonsterSummonPanelScript := preload("res://scripts/city/monster_summon_panel.gd")

const BOX_M := 20.0
## Clear air under the hologram volume (bottom of the 20 m cube).
const HEIGHT_ABOVE_ARENA_M := 10.0
const CYCLE_SEC := 20.0
## 25% translucent → keep 75% opacity (readable against bright sky).
const ALPHA := 0.75
const TURN_PAUSE_MIN_SEC := 2.5
const TURN_PAUSE_MAX_SEC := 7.0
const TURN_DURATION_SEC := 1.35

var _ids: PackedStringArray = PackedStringArray()
var _rng := RandomNumberGenerator.new()
var _pivot: Node3D = null
var _model: Node3D = null
var _player: AnimationPlayer = null
## Source Material → translucent duplicate (keeps albedo / textures).
var _mat_cache: Dictionary = {}
var _cycle_left := CYCLE_SEC
var _turn_pause_left := 0.0
var _turning := false
var _turn_elapsed := 0.0
var _yaw_from := 0.0
var _yaw_to := 0.0
var _current_id := ""


func setup(
	p_layout: ArenaLayout, p_origin_vox: Vector3i, p_voxel_size: float, p_seed: int
) -> void:
	if p_layout == null:
		push_error("ArenaHologram.setup: null layout")
		assert(false, "ArenaHologram: layout required")
		return
	name = "ArenaHologram"
	_rng.seed = p_seed ^ 0xA0106A
	_ids = MonsterSummonPanelScript.summonable_ids()
	if _ids.is_empty():
		push_error("ArenaHologram.setup: no summonable monsters")
		assert(false, "ArenaHologram: empty summonable list")
		return

	var pit := p_layout.pit_rect
	var cx := float(p_origin_vox.x) + float(pit.position.x) + float(pit.size.x) * 0.5
	var cz := float(p_origin_vox.z) + float(pit.position.y) + float(pit.size.y) * 0.5
	## Seating deck top, then 10 m of clear air to the bottom of the 20³ m volume.
	var arena_top_m := float(p_layout.seating_y + 1) * p_voxel_size
	global_position = Vector3(
		cx * p_voxel_size, arena_top_m + HEIGHT_ABOVE_ARENA_M, cz * p_voxel_size
	)

	_pivot = Node3D.new()
	_pivot.name = "HoloPivot"
	add_child(_pivot)
	_turn_pause_left = _rng.randf_range(TURN_PAUSE_MIN_SEC, TURN_PAUSE_MAX_SEC)
	_show_random()


func _process(delta: float) -> void:
	_cycle_left -= delta
	if _cycle_left <= 0.0:
		_cycle_left = CYCLE_SEC
		_show_random()
	_update_turn(delta)
	if _player != null and is_instance_valid(_player) and not _player.is_playing():
		_player.play(_player.current_animation)


func _update_turn(delta: float) -> void:
	if _pivot == null:
		return
	if _turning:
		_turn_elapsed += delta
		var t := clampf(_turn_elapsed / TURN_DURATION_SEC, 0.0, 1.0)
		## Smoothstep so the yaw ease reads as a deliberate pivot, not a lerp snag.
		var s := t * t * (3.0 - 2.0 * t)
		_pivot.rotation.y = lerpf(_yaw_from, _yaw_to, s)
		if t >= 1.0:
			_turning = false
			_pivot.rotation.y = _yaw_to
			_turn_pause_left = _rng.randf_range(TURN_PAUSE_MIN_SEC, TURN_PAUSE_MAX_SEC)
		return
	_turn_pause_left -= delta
	if _turn_pause_left > 0.0:
		return
	_yaw_from = _pivot.rotation.y
	## Quarter to three-quarter turns so the silhouette changes without spinning forever.
	var delta_yaw := _rng.randf_range(PI * 0.35, PI * 0.95)
	if _rng.randf() < 0.5:
		delta_yaw = -delta_yaw
	_yaw_to = _yaw_from + delta_yaw
	_turn_elapsed = 0.0
	_turning = true


func _show_random() -> void:
	if _ids.is_empty():
		return
	var pick := _ids[_rng.randi_range(0, _ids.size() - 1)]
	if _ids.size() > 1:
		var guard := 0
		while pick == _current_id and guard < 8:
			pick = _ids[_rng.randi_range(0, _ids.size() - 1)]
			guard += 1
	_show_monster(pick)


func _show_monster(monster_id: String) -> void:
	_clear_model()
	_current_id = monster_id
	var entry: CreatureCatalog.Entry = CreatureCatalogScript.by_id(monster_id)
	if entry == null:
		push_error("ArenaHologram: unknown id '%s'" % monster_id)
		return
	var packed: PackedScene = load(entry.path) as PackedScene
	if packed == null:
		push_error("ArenaHologram: failed to load '%s' (%s)" % [monster_id, entry.path])
		return
	_model = packed.instantiate() as Node3D
	if _model == null:
		push_error("ArenaHologram: root is not Node3D for '%s'" % monster_id)
		return
	_pivot.add_child(_model)
	_model.rotation = Vector3(0.0, entry.model_yaw, 0.0)
	_model.position = entry.model_offset
	_disable_physics(_model)
	_apply_hologram_look(_model)
	_fit_in_box(_model, entry)
	_player = _find_player(_model)
	if _player == null:
		push_error("ArenaHologram: no AnimationPlayer on '%s'" % monster_id)
		return
	var clip := CreatureClipsScript.resolve(
		_player.get_animation_list(), CreatureClips.Action.LOCOMOTION, monster_id
	)
	if clip.is_empty():
		return
	## Do not mutate shared Animation resources — `_process` restarts when a take ends.
	_player.play(clip)
	print("ArenaHologram: showing '%s' (walk-in-place)" % monster_id)


func _fit_in_box(root: Node3D, entry: CreatureCatalog.Entry) -> void:
	## Same footing convention as UndeadUnit / icon bake: scale from measured height, then
	## `model_offset * scale` so feet sit on the volume floor (local y = 0).
	var tall := maxf(entry.measured_height, 0.25)
	var s := BOX_M / tall
	root.scale = Vector3(s, s, s)
	root.position = entry.model_offset * s


func _apply_hologram_look(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.material_override = null
		var mesh := mi.mesh
		if mesh != null:
			for s in range(mesh.get_surface_count()):
				var src := mi.get_active_material(s)
				mi.set_surface_override_material(s, _translucent_copy(src))
	for c in n.get_children():
		_apply_hologram_look(c)


## Keep the body's authored colours; only open the alpha so it reads as a hologram.
func _translucent_copy(src: Material) -> Material:
	if src == null:
		var flat := StandardMaterial3D.new()
		flat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flat.albedo_color = Color(1.0, 1.0, 1.0, ALPHA)
		return flat
	if _mat_cache.has(src):
		return _mat_cache[src] as Material
	var out: Material = null
	if src is StandardMaterial3D:
		var m := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var c := m.albedo_color
		c.a = ALPHA
		m.albedo_color = c
		out = m
	elif src is ShaderMaterial:
		## Pull atlas / base colour off the palette shader; do not run an opaque shader in
		## the transparent pipeline (creature_palette deliberately never writes ALPHA).
		var sm := src as ShaderMaterial
		var m2 := StandardMaterial3D.new()
		m2.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var tex: Variant = sm.get_shader_parameter("albedo_tex")
		if tex is Texture2D:
			m2.albedo_texture = tex as Texture2D
		var base: Variant = sm.get_shader_parameter("albedo_base")
		if base is Color:
			var bc := base as Color
			bc.a = ALPHA
			m2.albedo_color = bc
		else:
			m2.albedo_color = Color(1.0, 1.0, 1.0, ALPHA)
		out = m2
	else:
		out = src.duplicate()
	_mat_cache[src] = out
	return out


func _disable_physics(n: Node) -> void:
	## Neutralise collision without freeing nodes that may own mesh children.
	if n is CollisionShape3D:
		(n as CollisionShape3D).disabled = true
	elif n is CollisionObject3D:
		var co := n as CollisionObject3D
		co.collision_layer = 0
		co.collision_mask = 0
	for c in n.get_children():
		_disable_physics(c)


func _clear_model() -> void:
	_player = null
	_mat_cache.clear()
	if _model != null and is_instance_valid(_model):
		_model.queue_free()
	_model = null


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var found := _find_player(c)
		if found != null:
			return found
	return null
