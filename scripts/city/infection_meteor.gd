## Falling voxel Multimesh meteor: rock + glowing seed cells. Stamps on impact.
class_name InfectionMeteor
extends Node3D

signal impacted(world_pos: Vector3, seed_world_positions: Array)

const VOXEL_SIZE := 0.5
## Authored blob was ~1 voxel radius; 3× → solid rock sphere of this radius.
const BLOB_RADIUS: int = 3
## Glowing tips stamped on the outer shell (spread around the sphere).
const SEED_COUNT: int = 8

@export var fall_speed_mps: float = 42.0
@export var spawn_height_m: float = 55.0
@export var glow_pulse_hz: float = 3.5

var _terrain: VoxelTerrain
var _tool: VoxelTool
var _target: Vector3 = Vector3.ZERO
var _velocity: Vector3 = Vector3.ZERO
var _mm_rock: MultiMeshInstance3D
var _mm_glow: MultiMeshInstance3D
var _glow_mat: StandardMaterial3D
var _light: OmniLight3D
var _alive: bool = false
var _age: float = 0.0
var _impacted: bool = false
var _blob: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


static func spawn(
	parent: Node,
	terrain: VoxelTerrain,
	tool: VoxelTool,
	aim_hit: Vector3,
	spawn_height: float = 55.0
) -> InfectionMeteor:
	var m := InfectionMeteor.new()
	m.name = "InfectionMeteor"
	parent.add_child(m)
	m.begin(terrain, tool, aim_hit, spawn_height)
	return m


func begin(terrain: VoxelTerrain, tool: VoxelTool, aim_hit: Vector3, spawn_height: float = 55.0) -> void:
	_terrain = terrain
	_tool = tool
	_target = aim_hit
	spawn_height_m = spawn_height
	_rng.randomize()
	_blob = _build_blob()
	var start := Vector3(aim_hit.x + 8.0, aim_hit.y + spawn_height_m, aim_hit.z - 6.0)
	global_position = start
	var to := aim_hit - start
	var dist := to.length()
	if dist < 0.01:
		to = Vector3(0, -1, 0)
		dist = 1.0
	_velocity = to.normalized() * fall_speed_mps
	_build_visuals()
	_alive = true
	_impacted = false


func _build_blob() -> Array[Dictionary]:
	## Rough sphere of rock; place infection seeds on the shell so tips fan out on impact.
	var cells: Array[Dictionary] = []
	var seed_slots: Array[Vector3i] = []
	var r := BLOB_RADIUS
	var r2 := float(r * r) + 0.35
	for z in range(-r, r + 1):
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				var d2 := float(x * x + y * y + z * z)
				if d2 > r2:
					continue
				var o := Vector3i(x, y, z)
				cells.append({"o": o, "m": VoxelMaterial.METEOR_ROCK})
				## Outer shell candidates for glowing seeds.
				if d2 >= float((r - 1) * (r - 1)):
					seed_slots.append(o)
	## Pick spread-out seed cells (avoid clustering).
	if not seed_slots.is_empty():
		seed_slots.shuffle()
		var picked: Array[Vector3i] = []
		var want := mini(SEED_COUNT, seed_slots.size())
		for slot in seed_slots:
			if picked.size() >= want:
				break
			var ok := true
			for p in picked:
				if (slot - p).length_squared() < 4:
					ok = false
					break
			if ok:
				picked.append(slot)
		## If spacing was too strict, fill remaining.
		for slot2 in seed_slots:
			if picked.size() >= want:
				break
			if not picked.has(slot2):
				picked.append(slot2)
		for i in range(cells.size()):
			var o2: Vector3i = cells[i]["o"]
			if picked.has(o2):
				cells[i] = {"o": o2, "m": VoxelMaterial.INFECTION_LEAD}
	return cells


func _build_visuals() -> void:
	var rock_cells: Array[Vector3i] = []
	var glow_cells: Array[Vector3i] = []
	for cell in _blob:
		var o: Vector3i = cell["o"]
		var mid: int = int(cell["m"])
		if mid == VoxelMaterial.INFECTION_LEAD:
			glow_cells.append(o)
		else:
			rock_cells.append(o)

	_mm_rock = _make_mm("RockCells", rock_cells.size())
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.28, 0.24, 0.2)
	rock_mat.roughness = 0.95
	rock_mat.vertex_color_use_as_albedo = true
	_mm_rock.material_override = rock_mat
	_place_cells(_mm_rock, rock_cells, Color(0.45, 0.4, 0.35))

	_mm_glow = _make_mm("GlowCells", glow_cells.size())
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = Color(0.55, 1.0, 0.3)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = Color(0.45, 1.0, 0.2)
	_glow_mat.emission_energy_multiplier = 5.0
	_glow_mat.roughness = 0.3
	_glow_mat.vertex_color_use_as_albedo = true
	_mm_glow.material_override = _glow_mat
	_place_cells(_mm_glow, glow_cells, Color(0.7, 1.0, 0.35))

	_light = OmniLight3D.new()
	_light.light_color = Color(0.55, 1.0, 0.35)
	_light.light_energy = 6.5
	_light.omni_range = 28.0
	_light.shadow_enabled = false
	add_child(_light)


func _make_mm(node_name: String, count: int) -> MultiMeshInstance3D:
	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = maxi(count, 1)
	mm.visible_instance_count = count
	var box := BoxMesh.new()
	box.size = Vector3.ONE * (VOXEL_SIZE * 0.92)
	mm.mesh = box
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _place_cells(mi: MultiMeshInstance3D, cells: Array[Vector3i], color: Color) -> void:
	var mm := mi.multimesh
	for i in range(cells.size()):
		var o: Vector3i = cells[i]
		var pos := Vector3(
			(float(o.x) + 0.5) * VOXEL_SIZE,
			(float(o.y) + 0.5) * VOXEL_SIZE,
			(float(o.z) + 0.5) * VOXEL_SIZE
		)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
		mm.set_instance_color(i, color)


func _physics_process(delta: float) -> void:
	if not _alive or _impacted:
		return
	_age += delta
	global_position += _velocity * delta
	## Mild spin for presence.
	rotate_y(1.6 * delta)
	rotate_x(0.7 * delta)
	if _glow_mat != null:
		var pulse := 0.5 + 0.5 * sin(_age * TAU * glow_pulse_hz)
		_glow_mat.emission_energy_multiplier = lerpf(3.2, 7.5, pulse)
	if _light != null:
		_light.light_energy = lerpf(3.0, 6.5, 0.5 + 0.5 * sin(_age * TAU * glow_pulse_hz))

	## Impact when we reach / pass the aim height or hit something via ray.
	if global_position.y <= _target.y + 0.6:
		_do_impact(_target)
		return
	var space := get_world_3d().direct_space_state
	if space != null:
		var from := global_position
		var to := global_position + _velocity.normalized() * maxf(_velocity.length() * delta * 2.0, 1.5)
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collide_with_areas = false
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			_do_impact(hit["position"] as Vector3)


func _do_impact(hit_pos: Vector3) -> void:
	if _impacted:
		return
	_impacted = true
	_alive = false
	var seeds: Array = []
	if _terrain != null and _tool != null:
		var local := _terrain.to_local(hit_pos)
		var base := Vector3i(int(floor(local.x)), int(floor(local.y)), int(floor(local.z)))
		## Nudge up if we drilled into the ground plane.
		if base.y < 1:
			base.y = 1
		_tool.channel = VoxelBuffer.CHANNEL_TYPE
		_tool.mode = VoxelTool.MODE_SET
		for cell in _blob:
			var o: Vector3i = cell["o"]
			var mid: int = int(cell["m"])
			var vox: Vector3i = base + o
			var existing := int(_tool.get_voxel(vox))
			if existing == VoxelMaterial.BEDROCK or existing == VoxelMaterial.WATER:
				continue
			if mid == VoxelMaterial.INFECTION_LEAD:
				## Prefer attaching to fabric: if this cell is air, try one below.
				if existing == VoxelMaterial.AIR:
					var below := vox + Vector3i(0, -1, 0)
					var below_id := int(_tool.get_voxel(below))
					if (
						VoxelMaterial.is_infectable(below_id)
						or VoxelMaterial.is_building_fabric(below_id)
					):
						vox = below
						existing = below_id
				var prev_for_seed := existing
				if prev_for_seed == VoxelMaterial.AIR:
					prev_for_seed = VoxelMaterial.METEOR_ROCK
				_tool.value = VoxelMaterial.INFECTION_LEAD
				_tool.do_point(vox)
				seeds.append({
					"world": _terrain.to_global(
						Vector3(float(vox.x) + 0.5, float(vox.y) + 0.5, float(vox.z) + 0.5)
					),
					"vox": vox,
					"prev_mat": prev_for_seed,
				})
			else:
				_tool.value = VoxelMaterial.METEOR_ROCK
				_tool.do_point(vox)

	impacted.emit(hit_pos, seeds)
	queue_free()
