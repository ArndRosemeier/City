## Falling voxel Multimesh meteor: rock + glowing seed cells. Stamps on impact.
class_name InfectionMeteor
extends Node3D

signal impacted(world_pos: Vector3, seed_world_positions: Array)

const VOXEL_SIZE := 0.5
## Authored blob was ~1 voxel radius; 3× → solid rock sphere of this radius.
const BLOB_RADIUS: int = 3
## Tips per meteor — always plant in this inclusive range when capacity allows.
const SEED_COUNT_MIN: int = 2
const SEED_COUNT_MAX: int = 3

@export var fall_speed_mps: float = 42.0
@export var spawn_height_m: float = 55.0
@export var glow_pulse_hz: float = 3.5
@export var sky_beam_linger_sec: float = 11.0

const SkyBeamScript := preload("res://scripts/city/infection_sky_beam_vfx.gd")

var _terrain: VoxelTerrain
var _tool: VoxelTool
var _target: Vector3 = Vector3.ZERO
var _velocity: Vector3 = Vector3.ZERO
var _mm_rock: MultiMeshInstance3D
var _mm_glow: MultiMeshInstance3D
var _glow_mat: StandardMaterial3D
var _light: OmniLight3D
var _sky_beam: Node
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
	_spawn_sky_beam()
	_alive = true
	_impacted = false


func _spawn_sky_beam() -> void:
	var host := get_parent()
	if host == null:
		return
	_sky_beam = SkyBeamScript.attach_to_meteor(host, self)


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
	## Prefer well-spaced shell seeds so each tip lands on a distinct cell.
	if not seed_slots.is_empty():
		seed_slots.shuffle()
		var picked: Array[Vector3i] = []
		var want := SEED_COUNT_MAX
		var min_sep2 := 5
		for slot in seed_slots:
			if picked.size() >= want:
				break
			var ok := true
			for p in picked:
				if (slot - p).length_squared() < min_sep2:
					ok = false
					break
			if ok:
				picked.append(slot)
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
		## Stamp rock body.
		for cell in _blob:
			var o: Vector3i = cell["o"]
			var mid: int = int(cell["m"])
			if mid == VoxelMaterial.INFECTION_LEAD:
				continue
			var vox: Vector3i = base + o
			var existing := int(_tool.get_voxel(vox))
			if existing == VoxelMaterial.BEDROCK or existing == VoxelMaterial.WATER:
				continue
			_tool.value = VoxelMaterial.METEOR_ROCK
			_tool.do_point(vox)
		var want := _rng.randi_range(SEED_COUNT_MIN, SEED_COUNT_MAX)
		seeds = _plant_guaranteed_seeds(base, want)

	impacted.emit(hit_pos, seeds)
	## Hand the sky beam off — pins permanently at the crater as a far-field marker.
	if _sky_beam != null and is_instance_valid(_sky_beam):
		_sky_beam.call("start_lingering", hit_pos)
		_sky_beam = null
	queue_free()


## Always return `want` unique seed tips on infectable city fabric around the crater.
func _plant_guaranteed_seeds(base: Vector3i, want: int) -> Array:
	var seeds: Array = []
	var used: Dictionary = {}
	var candidates: Array[Vector3i] = _collect_seed_candidates(base)
	## Prefer sites with room to crawl (infectable neighbor after claim).
	var ranked: Array[Vector3i] = []
	var fallback: Array[Vector3i] = []
	for c in candidates:
		if _count_infectable_neighbors(c) >= 1:
			ranked.append(c)
		else:
			fallback.append(c)
	_shuffle_vox_array(ranked)
	_shuffle_vox_array(fallback)
	for site in ranked:
		if seeds.size() >= want:
			break
		_try_plant_seed_at(site, used, seeds, true)
	for site2 in fallback:
		if seeds.size() >= want:
			break
		_try_plant_seed_at(site2, used, seeds, true)
	## Absolute last resort: plant just outside the rock blob even on meteor rock /
	## sidewalk air column, as long as cells stay unique.
	if seeds.size() < want:
		var ring := BLOB_RADIUS + 1
		while seeds.size() < want and ring <= BLOB_RADIUS + 12:
			var ring_sites: Array[Vector3i] = []
			for z in range(-ring, ring + 1):
				for x in range(-ring, ring + 1):
					if maxi(absi(x), absi(z)) != ring:
						continue
					for dy in range(-1, 4):
						ring_sites.append(base + Vector3i(x, dy, z))
			_shuffle_vox_array(ring_sites)
			for site3 in ring_sites:
				if seeds.size() >= want:
					break
				_try_plant_seed_at(site3, used, seeds, false)
			ring += 1
	return seeds


func _collect_seed_candidates(base: Vector3i) -> Array[Vector3i]:
	## Annulus outside the rock sphere so tips start on city fabric, not the crater.
	var out: Array[Vector3i] = []
	var seen: Dictionary = {}
	var r0 := BLOB_RADIUS + 1
	var r1 := BLOB_RADIUS + 10
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	for z in range(-r1, r1 + 1):
		for x in range(-r1, r1 + 1):
			var d2 := x * x + z * z
			if d2 < r0 * r0 or d2 > r1 * r1:
				continue
			for dy in range(-2, 5):
				var v := base + Vector3i(x, dy, z)
				if v.y < 0 or seen.has(v):
					continue
				var id := int(_tool.get_voxel(v))
				if VoxelMaterial.is_infectable(id):
					seen[v] = true
					out.append(v)
					continue
				if id == VoxelMaterial.AIR:
					var below := v + Vector3i(0, -1, 0)
					if below.y < 0 or seen.has(below):
						continue
					var bid := int(_tool.get_voxel(below))
					if VoxelMaterial.is_infectable(bid):
						seen[below] = true
						out.append(below)
	return out


func _count_infectable_neighbors(vox: Vector3i) -> int:
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var n := 0
	for off in [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
		Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	]:
		if VoxelMaterial.is_infectable(int(_tool.get_voxel(vox + off))):
			n += 1
	return n


func _shuffle_vox_array(arr: Array[Vector3i]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Vector3i = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _try_plant_seed_at(
	vox: Vector3i, used: Dictionary, seeds: Array, require_infectable_start: bool
) -> bool:
	if used.has(vox) or vox.y < 0:
		return false
	## Keep tips spaced so they don't immediately braid.
	for u in used.keys():
		if (vox - (u as Vector3i)).length_squared() < 4:
			return false
	_tool.channel = VoxelBuffer.CHANNEL_TYPE
	var existing := int(_tool.get_voxel(vox))
	if existing == VoxelMaterial.BEDROCK or existing == VoxelMaterial.WATER:
		return false
	if existing == VoxelMaterial.INFECTION_LEAD or existing == VoxelMaterial.INFECTION:
		return false
	if require_infectable_start and not VoxelMaterial.is_infectable(existing):
		## Allow air→infectable below.
		if existing == VoxelMaterial.AIR:
			var below := vox + Vector3i(0, -1, 0)
			if below.y < 0 or used.has(below):
				return false
			var below_id := int(_tool.get_voxel(below))
			if not VoxelMaterial.is_infectable(below_id):
				return false
			vox = below
			existing = below_id
		else:
			return false
	elif existing == VoxelMaterial.AIR:
		var below2 := vox + Vector3i(0, -1, 0)
		if below2.y >= 0 and not used.has(below2):
			var below_id2 := int(_tool.get_voxel(below2))
			if (
				below_id2 != VoxelMaterial.BEDROCK
				and below_id2 != VoxelMaterial.WATER
				and below_id2 != VoxelMaterial.AIR
				and below_id2 != VoxelMaterial.INFECTION_LEAD
				and below_id2 != VoxelMaterial.INFECTION
			):
				vox = below2
				existing = below_id2
	if used.has(vox):
		return false
	var prev_for_seed := existing
	if prev_for_seed == VoxelMaterial.AIR:
		prev_for_seed = VoxelMaterial.METEOR_ROCK
	_tool.mode = VoxelTool.MODE_SET
	_tool.value = VoxelMaterial.INFECTION_LEAD
	_tool.do_point(vox)
	used[vox] = true
	seeds.append({
		"world": _terrain.to_global(
			Vector3(float(vox.x) + 0.5, float(vox.y) + 0.5, float(vox.z) + 0.5)
		),
		"vox": vox,
		"prev_mat": prev_for_seed,
	})
	return true
