## Carve blasts and detach unsupported voxel clusters into RigidBody3Ds.
class_name DestructionService
extends Node

@export var blast_radius: float = 2.6
@export var collapse_search_radius: float = 28.0
@export var min_cluster_voxels: int = 2
@export var max_rigid_bodies: int = 400
## Soft shove — must NOT scale with huge building masses or debris flies off-map.
@export var blast_speed: float = 1.8
@export var topple_spin: float = 1.2
@export var cluster_density: float = 900.0
@export var max_piece_mass: float = 400.0
## Prefer many visible rubble pieces over one mega-body.
@export var max_voxels_per_piece: int = 48

var world: VoxelWorld
var debris_root: Node3D
var _rigid_count: int = 0


func setup(voxel_world: VoxelWorld, debris_parent: Node3D) -> void:
	world = voxel_world
	debris_root = debris_parent


func blast_at(world_pos: Vector3) -> void:
	if world == null:
		return
	world.carve_sphere(world_pos, blast_radius)
	world.carve_horizontal_disk(world_pos, blast_radius * 1.65, world.voxel_size * 1.25)
	_detach_unsupported(world_pos)
	world.remesh_dirty()


func break_rigid_cluster(body: RigidBody3D, hit_pos: Vector3) -> void:
	if body == null or not is_instance_valid(body):
		return
	var voxels_var: Variant = body.get_meta("voxels", [])
	var mats_var: Variant = body.get_meta("materials", {})
	if typeof(voxels_var) != TYPE_ARRAY:
		return
	var voxels: Array = voxels_var
	if voxels.size() < 4:
		# Keep a visible crumb instead of deleting.
		return
	var materials: Dictionary = mats_var if typeof(mats_var) == TYPE_DICTIONARY else {}
	var near: Array[Vector3i] = []
	var far: Array[Vector3i] = []
	for item in voxels:
		var v: Vector3i = item
		var c := world.voxel_to_world_center(v)
		if c.distance_to(hit_pos) < blast_radius * 0.85:
			near.append(v)
		else:
			far.append(v)
	body.queue_free()
	_rigid_count = maxi(0, _rigid_count - 1)
	if near.size() >= min_cluster_voxels:
		_spawn_pieces_from_voxels(near, materials, hit_pos)
	if far.size() >= min_cluster_voxels:
		_spawn_pieces_from_voxels(far, materials, hit_pos)


func _detach_unsupported(blast_center: Vector3) -> void:
	var components: Array = VoxelConnectivity.find_unsupported_near(
		world, blast_center, collapse_search_radius, min_cluster_voxels
	)
	for comp in components:
		var voxels: Array[Vector3i] = []
		var materials: Dictionary = {}
		for v in comp:
			voxels.append(v)
			materials[v] = world.get_voxel(v)
		# Split first; only remove voxels that become debris (never silently delete mass).
		var pieces: Array = _voxels_to_piece_groups(voxels, materials)
		for piece_voxels in pieces:
			if _rigid_count >= max_rigid_bodies:
				break
			var piece: Array[Vector3i] = []
			for pv in piece_voxels:
				piece.append(pv)
			for v in piece:
				world.set_voxel(v, VoxelMaterial.AIR)
			_spawn_rigid_from_voxel_list(piece, materials, blast_center)


func _spawn_pieces_from_voxels(
	voxels: Array[Vector3i],
	materials: Dictionary,
	blast_center: Vector3
) -> void:
	## Used when re-breaking existing debris (voxels already not in static world).
	if voxels.is_empty():
		return
	var pieces: Array = _voxels_to_piece_groups(voxels, materials)
	for piece_voxels in pieces:
		if _rigid_count >= max_rigid_bodies:
			_spawn_rigid_from_voxel_list(piece_voxels, materials, blast_center)
			break
		_spawn_rigid_from_voxel_list(piece_voxels, materials, blast_center)


func _voxels_to_piece_groups(voxels: Array[Vector3i], materials: Dictionary) -> Array:
	## Group voxels into chunks of at most max_voxels_per_piece for visible rubble.
	var remaining: Dictionary = {}
	for v in voxels:
		remaining[v] = true
	var groups: Array = []
	var sorted := voxels.duplicate()
	sorted.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.y != b.y:
			return a.y < b.y
		if a.z != b.z:
			return a.z < b.z
		return a.x < b.x
	)
	for start: Vector3i in sorted:
		if not remaining.has(start):
			continue
		var group: Array[Vector3i] = []
		var q: Array[Vector3i] = [start]
		remaining.erase(start)
		var qi := 0
		while qi < q.size() and group.size() < max_voxels_per_piece:
			var cur: Vector3i = q[qi]
			qi += 1
			group.append(cur)
			for d in VoxelConnectivity.NEIGHBORS:
				var n: Vector3i = cur + d
				if not remaining.has(n):
					continue
				# Keep same material runs together when possible.
				if int(materials.get(n, -1)) != int(materials.get(start, -2)) and group.size() > 8:
					continue
				remaining.erase(n)
				q.append(n)
		if group.size() >= min_cluster_voxels:
			groups.append(group)
		elif group.size() > 0:
			# Tiny crumbs still visible as 1-voxel pieces.
			groups.append(group)
	return groups


func _spawn_single_aabb_piece(
	voxels: Array[Vector3i],
	materials: Dictionary,
	blast_center: Vector3
) -> void:
	_spawn_rigid_from_voxel_list(voxels, materials, blast_center)


func _spawn_rigid_from_voxel_list(
	voxels: Array[Vector3i],
	materials: Dictionary,
	blast_center: Vector3
) -> void:
	if voxels.is_empty():
		return
	var boxes: Array = GreedyMesher.boxes_from_voxels(voxels, materials, world.voxel_size)
	if boxes.is_empty():
		# Fallback: one box per voxel.
		for v in voxels:
			boxes.append({
				"pos": world.voxel_to_world_center(v),
				"size": Vector3.ONE * world.voxel_size,
				"material": int(materials.get(v, VoxelMaterial.CONCRETE)),
			})

	var com := Vector3.ZERO
	var total_vol := 0.0
	for box in boxes:
		var size: Vector3 = box["size"]
		var vol: float = size.x * size.y * size.z
		com += box["pos"] * vol
		total_vol += vol
	if total_vol <= 0.0:
		return
	com /= total_vol

	var body := RigidBody3D.new()
	body.name = "DebrisPiece"
	body.collision_layer = 1
	body.collision_mask = 1
	body.position = com
	body.continuous_cd = true
	body.can_sleep = true
	body.gravity_scale = 1.0
	body.physics_material_override = _debris_phys_mat()
	body.mass = clampf(total_vol * cluster_density, 0.5, max_piece_mass)
	body.set_meta("voxels", voxels)
	body.set_meta("materials", materials)

	for box in boxes:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = box["size"]
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = VoxelMaterial.color(int(box["material"]))
		mat.roughness = 0.9
		mi.material_override = mat
		mi.position = box["pos"] - com
		body.add_child(mi)

		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = box["size"]
		cs.shape = shape
		cs.position = box["pos"] - com
		body.add_child(cs)

	debris_root.add_child(body)
	_rigid_count += 1
	body.tree_exited.connect(_on_body_exited)

	# Gentle topple: small outward nudge + spin. Velocity-based so mass cannot fling debris away.
	var away := com - blast_center
	away.y = maxf(away.y, 0.0)
	if away.length_squared() < 0.0001:
		away = Vector3(1.0, 0.2, 0.0)
	away = away.normalized()
	body.linear_velocity = away * blast_speed + Vector3.UP * (blast_speed * 0.35)
	body.angular_velocity = Vector3(
		randf_range(-topple_spin, topple_spin),
		randf_range(-topple_spin * 0.5, topple_spin * 0.5),
		randf_range(-topple_spin, topple_spin)
	)


func _debris_phys_mat() -> PhysicsMaterial:
	var pm := PhysicsMaterial.new()
	pm.friction = 0.95
	pm.bounce = 0.05
	return pm


func _on_body_exited() -> void:
	_rigid_count = maxi(0, _rigid_count - 1)


func clear_debris() -> void:
	if debris_root == null:
		return
	for c in debris_root.get_children():
		c.queue_free()
	_rigid_count = 0
