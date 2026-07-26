## Caps a small OmniLight pool on the nearest hill-gem clusters while underground.
## Visual glow is always on via voxel_gem.gdshader; these lights actually illuminate caves.
class_name GemLightDirector
extends Node

const POOL_SIZE := 6
const REFRESH_SEC := 0.25
const MAX_RANGE_M := 22.0
const VOXEL_SIZE := 0.5

var _tool: VoxelTool
var _camera: Camera3D
var _streamer: Node
var _lights: Array[OmniLight3D] = []
var _accum: float = 0.0
var _underground: bool = false


func setup(tool: VoxelTool, camera: Camera3D, streamer: Node) -> void:
	_tool = tool
	_camera = camera
	_streamer = streamer
	_ensure_pool()


func set_underground(active: bool) -> void:
	_underground = active
	if not active:
		_dim_all()


func _ensure_pool() -> void:
	while _lights.size() < POOL_SIZE:
		var omni := OmniLight3D.new()
		omni.name = "GemLight_%d" % _lights.size()
		omni.shadow_enabled = false
		omni.light_energy = 0.0
		omni.omni_range = 5.5
		omni.omni_attenuation = 1.6
		add_child(omni)
		_lights.append(omni)


func _process(delta: float) -> void:
	if not _underground:
		return
	_accum += delta
	if _accum < REFRESH_SEC:
		return
	_accum = 0.0
	_refresh()


func _dim_all() -> void:
	for omni in _lights:
		if is_instance_valid(omni):
			omni.light_energy = 0.0


func _refresh() -> void:
	if _tool == null or _camera == null or _streamer == null:
		_dim_all()
		return
	if not _streamer.has_method("get_loaded_districts"):
		_dim_all()
		return
	var cam := _camera.global_position
	var scored: Array[Dictionary] = []
	var districts: Array = _streamer.call("get_loaded_districts") as Array
	for entry: Variant in districts:
		var inst: DistrictInstance = entry as DistrictInstance
		if inst == null or not is_instance_valid(inst):
			continue
		var n := mini(inst.hill_gem_positions.size(), inst.hill_gem_mats.size())
		for i in range(n):
			var vox := inst.hill_gem_positions[i]
			var world := Vector3(
				(vox.x + 0.5) * VOXEL_SIZE,
				(vox.y + 0.5) * VOXEL_SIZE,
				(vox.z + 0.5) * VOXEL_SIZE
			)
			var d2 := cam.distance_squared_to(world)
			if d2 > MAX_RANGE_M * MAX_RANGE_M:
				continue
			var mat_id := int(inst.hill_gem_mats[i])
			if not VoxelMaterial.is_gem(mat_id):
				continue
			## Drop destroyed ore so lights don't float in empty air.
			var still := int(_tool.get_voxel(Vector3i(int(vox.x), int(vox.y), int(vox.z))))
			if still != mat_id:
				continue
			scored.append({"pos": world, "mat": mat_id, "d2": d2})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d2"]) < float(b["d2"]))
	## Deduplicate to one light per ~1.5 m cluster so dense veins don't monopolize the pool.
	var chosen: Array[Dictionary] = []
	for entry2: Dictionary in scored:
		var p: Vector3 = entry2["pos"]
		var clash := false
		for c: Dictionary in chosen:
			if p.distance_squared_to(c["pos"] as Vector3) < 2.25:
				clash = true
				break
		if clash:
			continue
		chosen.append(entry2)
		if chosen.size() >= POOL_SIZE:
			break
	for i in range(POOL_SIZE):
		var omni := _lights[i]
		if i >= chosen.size():
			omni.light_energy = 0.0
			continue
		var mat := int(chosen[i]["mat"])
		var pos: Vector3 = chosen[i]["pos"]
		omni.global_position = pos
		omni.light_color = _light_color(mat)
		omni.light_energy = _light_energy(mat)
		omni.omni_range = _light_range(mat)


func _light_color(mat: int) -> Color:
	match mat:
		VoxelMaterial.GEM_QUARTZ:
			return Color(0.75, 0.9, 1.0)
		VoxelMaterial.GEM_AMBER:
			return Color(1.0, 0.55, 0.15)
		VoxelMaterial.GEM_TOPAZ:
			return Color(1.0, 0.78, 0.3)
		VoxelMaterial.GEM_SAPPHIRE:
			return Color(0.3, 0.45, 1.0)
		VoxelMaterial.GEM_EMERALD:
			return Color(0.25, 1.0, 0.45)
		VoxelMaterial.GEM_DIAMOND:
			return Color(0.95, 0.98, 1.0)
		_:
			return Color(1, 1, 1)


func _light_energy(mat: int) -> float:
	match mat:
		VoxelMaterial.GEM_QUARTZ:
			return 0.7
		VoxelMaterial.GEM_AMBER:
			return 0.85
		VoxelMaterial.GEM_TOPAZ:
			return 1.0
		VoxelMaterial.GEM_SAPPHIRE:
			return 1.25
		VoxelMaterial.GEM_EMERALD:
			return 1.45
		VoxelMaterial.GEM_DIAMOND:
			return 1.9
		_:
			return 0.8


func _light_range(mat: int) -> float:
	match mat:
		VoxelMaterial.GEM_DIAMOND:
			return 7.5
		VoxelMaterial.GEM_EMERALD, VoxelMaterial.GEM_SAPPHIRE:
			return 6.5
		_:
			return 5.5
