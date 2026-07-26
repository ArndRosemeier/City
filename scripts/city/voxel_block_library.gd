## Builds a VoxelBlockyLibrary with city albedo textures.
## Most types stay cubes. Detail types use VoxelBlockyModelMesh visuals.
## Park props (bark / leaves / planters / flowers) are visual-only — no collision.
class_name VoxelBlockLibrary
extends RefCounted

const TEX_DIR := "res://assets/city/textures/"
## World size of one voxel cell (matches CityRoot.VOXEL_SIZE / terrain scale).
const VOXEL_WORLD_SIZE := 0.5


static func build() -> VoxelBlockyLibrary:
	var lib := VoxelBlockyLibrary.new()
	var models: Array[VoxelBlockyModel] = []
	models.append(VoxelBlockyModelEmpty.new())
	for id in range(1, VoxelMaterial.COUNT):
		models.append(_make_model(id))
	lib.models = models
	## Our surface shader rebuilds tangent frames from world axes; generated mesh
	## tangents from SurfaceTool UVs are unused and have been a source of bad data.
	lib.bake_tangents = false
	lib.bake()
	return lib


static func _make_model(id: int) -> VoxelBlockyModel:
	match id:
		VoxelMaterial.PLANTER:
			## Visual only — park benches / planter rims must not snag giants or walkers.
			return _mesh_model(id, _mesh_planter(), false, false, AABB(), false)
		VoxelMaterial.LEAVES:
			## Walk-through foliage cards (alpha cutout). transparency_index for mesher order.
			return _mesh_model(id, _mesh_leaves(), true, false, AABB(), false)
		VoxelMaterial.YEW:
			## Same cross-cards as deciduous; walk-through (hedges / cypress needles).
			return _mesh_model(id, _mesh_yew(), true, false, AABB(), false)
		VoxelMaterial.BARK:
			## Trunk visuals only — dense groves were trapping large CharacterBodies.
			return _mesh_model(id, _mesh_trunk(), false, false, AABB(), false)
		VoxelMaterial.WATER:
			## Full-cell visual + neighbor cull so a pool reads as one volume, not a
			## grid of inset slabs. Collision stays recessed on bit 1 (swim ignores it).
			var water := _mesh_model(
				id,
				_mesh_water(),
				true,
				true,
				AABB(Vector3(0.02, 0.15, 0.02), Vector3(0.96, 0.48, 0.96))
			)
			water.collision_mask = 2
			return water
		VoxelMaterial.GLASS:
			## Visual stays inset, but collision fills the cell. An inset box left
			## 0.1–0.12 voxel seams between neighbouring panes — the capsule could
			## worm through those gaps into the hollow building instead of climbing.
			return _mesh_model(id, _mesh_glass(), true, false, AABB(Vector3.ZERO, Vector3.ONE))
		VoxelMaterial.GLASS_LIT:
			return _mesh_model(id, _mesh_glass(), true, false, AABB(Vector3.ZERO, Vector3.ONE))
		VoxelMaterial.CURB:
			## Low curb lip (~0.2 m world) so CharacterBody can step/jump it.
			return _mesh_model(id, _mesh_curb(), false, true, AABB(Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.4, 1.0)))
		VoxelMaterial.ROAD_LINE:
			return _mesh_model(id, _mesh_road_line(), false, true, AABB(Vector3.ZERO, Vector3.ONE))
		VoxelMaterial.PAINT:
			return _mesh_model(id, _mesh_flower(), false, false, AABB(), false)
		VoxelMaterial.ROOF_SLOPE_POS_X, VoxelMaterial.ROOF_CLAY_SLOPE_POS_X:
			## Collide with the wedge mesh itself — a full-cell discard collision mesh
			## baked solid sides for neighbor culling (egg-crate). A full-cell AABB alone
			## put feet on the cube top while the pitched face cut through the legs.
			return _mesh_model_slope_collision(
				id, _mesh_slope_45(VoxelMaterial.SLOPE_HIGH_POS_X), VoxelMaterial.SLOPE_HIGH_POS_X
			)
		VoxelMaterial.ROOF_SLOPE_NEG_X, VoxelMaterial.ROOF_CLAY_SLOPE_NEG_X:
			return _mesh_model_slope_collision(
				id, _mesh_slope_45(VoxelMaterial.SLOPE_HIGH_NEG_X), VoxelMaterial.SLOPE_HIGH_NEG_X
			)
		VoxelMaterial.ROOF_SLOPE_POS_Z, VoxelMaterial.ROOF_CLAY_SLOPE_POS_Z:
			return _mesh_model_slope_collision(
				id, _mesh_slope_45(VoxelMaterial.SLOPE_HIGH_POS_Z), VoxelMaterial.SLOPE_HIGH_POS_Z
			)
		VoxelMaterial.ROOF_SLOPE_NEG_Z, VoxelMaterial.ROOF_CLAY_SLOPE_NEG_Z:
			return _mesh_model_slope_collision(
				id, _mesh_slope_45(VoxelMaterial.SLOPE_HIGH_NEG_Z), VoxelMaterial.SLOPE_HIGH_NEG_Z
			)
		_:
			return _make_cube(id)


static func _make_cube(id: int) -> VoxelBlockyModelCube:
	var cube := VoxelBlockyModelCube.new()
	cube.color = Color(1, 1, 1, 1)
	cube.set_material_override(0, block_material_for(id))
	if id == VoxelMaterial.GLASS or id == VoxelMaterial.GLASS_LIT or id == VoxelMaterial.WATER:
		cube.transparency_index = 1
	return cube


## Visual mesh (surface 0) + optional collision mesh (surface 1).
## Pass collide=false for walk-through props (leaves / flowers).
static func _mesh_model(
	id: int,
	visual: ArrayMesh,
	transparent: bool,
	culls_neighbors: bool,
	collision_aabb: AABB = AABB(Vector3.ZERO, Vector3.ONE),
	collide: bool = true
) -> VoxelBlockyModelMesh:
	var model := VoxelBlockyModelMesh.new()
	var mat := block_material_for(id)
	if collide:
		model.mesh = _with_collision_box(visual, mat, collision_aabb)
		model.collision_aabbs = [collision_aabb]
		model.set_material_override(0, mat)
		model.set_material_override(1, _collision_discard_material())
		model.set_mesh_collision_enabled(0, false)
		model.set_mesh_collision_enabled(1, true)
	else:
		model.mesh = visual
		model.collision_aabbs = []
		model.collision_mask = 0
		model.set_material_override(0, mat)
		model.set_mesh_collision_enabled(0, false)
	model.culls_neighbors = culls_neighbors
	if transparent:
		model.transparency_index = 1
	return model


## Walkable roof wedge: physics uses the visual trimesh (matches the pitched face).
## Stepped AABBs approximate the solid for VoxelBoxMover / voxel raycasts — never a
## full-cell box (that floats the capsule above the slope). No second discard mesh
## (that would bake solid sides and reintroduce the egg-crate cull bug).
static func _mesh_model_slope_collision(
	id: int, visual: ArrayMesh, high_toward: int
) -> VoxelBlockyModelMesh:
	var model := VoxelBlockyModelMesh.new()
	var mat := block_material_for(id)
	model.mesh = visual
	model.set_material_override(0, mat)
	model.set_mesh_collision_enabled(0, true)
	model.collision_aabbs = _slope_collision_aabbs(high_toward, 4)
	model.culls_neighbors = false
	return model


## Stair-step boxes under the 45° pitch (unit cell). Conservative: each strip fills
## up to the high edge of that strip so the walk surface is never below the wedge.
static func _slope_collision_aabbs(high_toward: int, steps: int) -> Array[AABB]:
	var boxes: Array[AABB] = []
	var n := maxi(steps, 1)
	var w := 1.0 / float(n)
	for i in range(n):
		var t0 := float(i) * w
		var t1 := float(i + 1) * w
		match high_toward:
			VoxelMaterial.SLOPE_HIGH_POS_X:
				boxes.append(AABB(Vector3(t0, 0.0, 0.0), Vector3(w, t1, 1.0)))
			VoxelMaterial.SLOPE_HIGH_NEG_X:
				boxes.append(AABB(Vector3(t0, 0.0, 0.0), Vector3(w, 1.0 - t0, 1.0)))
			VoxelMaterial.SLOPE_HIGH_POS_Z:
				boxes.append(AABB(Vector3(0.0, 0.0, t0), Vector3(1.0, t1, w)))
			VoxelMaterial.SLOPE_HIGH_NEG_Z:
				boxes.append(AABB(Vector3(0.0, 0.0, t0), Vector3(1.0, 1.0 - t0, w)))
			_:
				push_error("VoxelBlockLibrary._slope_collision_aabbs: bad high_toward %d" % high_toward)
				return [AABB(Vector3.ZERO, Vector3.ONE)]
	return boxes


static func _collision_discard_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, shadows_disabled, cull_disabled;
void fragment() {
	discard;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


static func _with_collision_box(visual: ArrayMesh, visual_mat: Material, box: AABB) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in range(visual.get_surface_count()):
		var arrs := visual.surface_get_arrays(s)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
		out.surface_set_material(out.get_surface_count() - 1, visual_mat)
	var coll := _box_mesh(box.position, box.position + box.size)
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, coll.surface_get_arrays(0))
	out.surface_set_material(out.get_surface_count() - 1, _collision_discard_material())
	return out


static func _box_mesh(bmin: Vector3, bmax: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	## Six faces, outward normals, simple UVs.
	_add_quad(st, Vector3(bmin.x, bmin.y, bmax.z), Vector3(bmax.x, bmin.y, bmax.z), Vector3(bmax.x, bmax.y, bmax.z), Vector3(bmin.x, bmax.y, bmax.z), Vector3(0, 0, 1))
	_add_quad(st, Vector3(bmax.x, bmin.y, bmin.z), Vector3(bmin.x, bmin.y, bmin.z), Vector3(bmin.x, bmax.y, bmin.z), Vector3(bmax.x, bmax.y, bmin.z), Vector3(0, 0, -1))
	_add_quad(st, Vector3(bmin.x, bmin.y, bmin.z), Vector3(bmin.x, bmin.y, bmax.z), Vector3(bmin.x, bmax.y, bmax.z), Vector3(bmin.x, bmax.y, bmin.z), Vector3(-1, 0, 0))
	_add_quad(st, Vector3(bmax.x, bmin.y, bmax.z), Vector3(bmax.x, bmin.y, bmin.z), Vector3(bmax.x, bmax.y, bmin.z), Vector3(bmax.x, bmax.y, bmax.z), Vector3(1, 0, 0))
	_add_quad(st, Vector3(bmin.x, bmax.y, bmax.z), Vector3(bmax.x, bmax.y, bmax.z), Vector3(bmax.x, bmax.y, bmin.z), Vector3(bmin.x, bmax.y, bmin.z), Vector3(0, 1, 0))
	_add_quad(st, Vector3(bmin.x, bmin.y, bmin.z), Vector3(bmax.x, bmin.y, bmin.z), Vector3(bmax.x, bmin.y, bmax.z), Vector3(bmin.x, bmin.y, bmax.z), Vector3(0, -1, 0))
	st.index()
	return st.commit()


static func _add_quad(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	n: Vector3
) -> void:
	st.set_normal(n)
	st.set_uv(Vector2(0, 1))
	st.add_vertex(a)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(b)
	st.set_uv(Vector2(1, 0))
	st.add_vertex(c)
	st.set_uv(Vector2(0, 1))
	st.add_vertex(a)
	st.set_uv(Vector2(1, 0))
	st.add_vertex(c)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(d)


static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	st.set_normal(n)
	st.set_uv(Vector2(0, 1))
	st.add_vertex(a)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(b)
	st.set_uv(Vector2(0.5, 0))
	st.add_vertex(c)


## 45° roof wedge in the unit cube. `high_toward` is a VoxelMaterial.SLOPE_HIGH_*.
##
## Normals stay outward for lighting. Triangle winding is clockwise when viewed from
## outside (Godot's front-face convention), so (b−a)×(c−a) points *inward*. The
## opposite winding made every outside view a back face — only leftover axis edges
## drew, which looked like a hollow egg-crate.
static func _mesh_slope_45(high_toward: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match high_toward:
		VoxelMaterial.SLOPE_HIGH_POS_X:
			_add_quad(
				st,
				Vector3(1, 0, 1),
				Vector3(1, 1, 1),
				Vector3(1, 1, 0),
				Vector3(1, 0, 0),
				Vector3(1, 0, 0)
			)
			_add_tri(st, Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 0, -1))
			_add_tri(st, Vector3(0, 0, 1), Vector3(1, 1, 1), Vector3(1, 0, 1), Vector3(0, 0, 1))
			_add_quad(
				st,
				Vector3(0, 0, 0),
				Vector3(1, 1, 0),
				Vector3(1, 1, 1),
				Vector3(0, 0, 1),
				Vector3(-1, 1, 0).normalized()
			)
		VoxelMaterial.SLOPE_HIGH_NEG_X:
			_add_quad(
				st,
				Vector3(0, 0, 0),
				Vector3(0, 1, 0),
				Vector3(0, 1, 1),
				Vector3(0, 0, 1),
				Vector3(-1, 0, 0)
			)
			_add_tri(st, Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 0), Vector3(0, 0, -1))
			_add_tri(st, Vector3(1, 0, 1), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 0, 1))
			_add_quad(
				st,
				Vector3(1, 0, 1),
				Vector3(0, 1, 1),
				Vector3(0, 1, 0),
				Vector3(1, 0, 0),
				Vector3(1, 1, 0).normalized()
			)
		VoxelMaterial.SLOPE_HIGH_POS_Z:
			_add_quad(
				st,
				Vector3(0, 0, 1),
				Vector3(0, 1, 1),
				Vector3(1, 1, 1),
				Vector3(1, 0, 1),
				Vector3(0, 0, 1)
			)
			_add_tri(st, Vector3(0, 0, 0), Vector3(0, 1, 1), Vector3(0, 0, 1), Vector3(-1, 0, 0))
			_add_tri(st, Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 0, 0))
			_add_quad(
				st,
				Vector3(1, 0, 0),
				Vector3(1, 1, 1),
				Vector3(0, 1, 1),
				Vector3(0, 0, 0),
				Vector3(0, 1, -1).normalized()
			)
		VoxelMaterial.SLOPE_HIGH_NEG_Z:
			_add_quad(
				st,
				Vector3(1, 0, 0),
				Vector3(1, 1, 0),
				Vector3(0, 1, 0),
				Vector3(0, 0, 0),
				Vector3(0, 0, -1)
			)
			_add_tri(st, Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(-1, 0, 0))
			_add_tri(st, Vector3(1, 0, 1), Vector3(1, 1, 0), Vector3(1, 0, 0), Vector3(1, 0, 0))
			_add_quad(
				st,
				Vector3(0, 0, 1),
				Vector3(0, 1, 0),
				Vector3(1, 1, 0),
				Vector3(1, 0, 1),
				Vector3(0, 1, 1).normalized()
			)
		_:
			push_error("VoxelBlockLibrary._mesh_slope_45: bad high_toward %d" % high_toward)
			return _box_mesh(Vector3.ZERO, Vector3.ONE)
	_add_quad(
		st,
		Vector3(0, 0, 0),
		Vector3(0, 0, 1),
		Vector3(1, 0, 1),
		Vector3(1, 0, 0),
		Vector3(0, -1, 0)
	)
	st.index()
	return st.commit()


## Low open planter box (wood rim + floor).
static func _mesh_planter() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := 0.32
	var t := 0.1
	## Floor
	_emit_box(st, Vector3(0.08, 0.0, 0.08), Vector3(0.92, 0.06, 0.92))
	## Four rim walls
	_emit_box(st, Vector3(0.06, 0.0, 0.06), Vector3(0.94, h, 0.06 + t))
	_emit_box(st, Vector3(0.06, 0.0, 0.94 - t), Vector3(0.94, h, 0.94))
	_emit_box(st, Vector3(0.06, 0.0, 0.06), Vector3(0.06 + t, h, 0.94))
	_emit_box(st, Vector3(0.94 - t, 0.0, 0.06), Vector3(0.94, h, 0.94))
	st.index()
	return st.commit()


## Cross-plane foliage (classic plant card).
static func _mesh_leaves() -> ArrayMesh:
	return _mesh_foliage_cards()


## Yew / hedge cards — same silhouette as deciduous leaves.
static func _mesh_yew() -> ArrayMesh:
	return _mesh_foliage_cards()


static func _mesh_foliage_cards() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y0 := 0.05
	var y1 := 0.95
	var inset := 0.08
	## Plane along X
	_add_quad(
		st,
		Vector3(inset, y0, 0.5),
		Vector3(1.0 - inset, y0, 0.5),
		Vector3(1.0 - inset, y1, 0.5),
		Vector3(inset, y1, 0.5),
		Vector3(0, 0, 1)
	)
	_add_quad(
		st,
		Vector3(1.0 - inset, y0, 0.5),
		Vector3(inset, y0, 0.5),
		Vector3(inset, y1, 0.5),
		Vector3(1.0 - inset, y1, 0.5),
		Vector3(0, 0, -1)
	)
	## Plane along Z
	_add_quad(
		st,
		Vector3(0.5, y0, inset),
		Vector3(0.5, y0, 1.0 - inset),
		Vector3(0.5, y1, 1.0 - inset),
		Vector3(0.5, y1, inset),
		Vector3(1, 0, 0)
	)
	_add_quad(
		st,
		Vector3(0.5, y0, 1.0 - inset),
		Vector3(0.5, y0, inset),
		Vector3(0.5, y1, inset),
		Vector3(0.5, y1, 1.0 - inset),
		Vector3(-1, 0, 0)
	)
	st.index()
	return st.commit()


## Thin trunk cylinder with a mild base taper.
static func _mesh_trunk() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 12
	var r_bot := 0.24
	var r_top := 0.18
	var cx := 0.5
	var cz := 0.5
	for i in range(sides):
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var x0b := cx + cos(a0) * r_bot
		var z0b := cz + sin(a0) * r_bot
		var x1b := cx + cos(a1) * r_bot
		var z1b := cz + sin(a1) * r_bot
		var x0t := cx + cos(a0) * r_top
		var z0t := cz + sin(a0) * r_top
		var x1t := cx + cos(a1) * r_top
		var z1t := cz + sin(a1) * r_top
		var n := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5)).normalized()
		_add_quad(
			st,
			Vector3(x0b, 0.0, z0b),
			Vector3(x1b, 0.0, z1b),
			Vector3(x1t, 1.0, z1t),
			Vector3(x0t, 1.0, z0t),
			n
		)
	## Top disk
	for i in range(sides):
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var x0 := cx + cos(a0) * r_top
		var z0 := cz + sin(a0) * r_top
		var x1 := cx + cos(a1) * r_top
		var z1 := cz + sin(a1) * r_top
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(Vector3(cx, 1.0, cz))
		st.set_uv(Vector2(0, 0))
		st.add_vertex(Vector3(x0, 1.0, z0))
		st.set_uv(Vector2(1, 0))
		st.add_vertex(Vector3(x1, 1.0, z1))
	st.index()
	return st.commit()

## Full cell — shared faces cull between adjacent WATER so bodies look continuous.
static func _mesh_water() -> ArrayMesh:
	return _box_mesh(Vector3.ZERO, Vector3.ONE)


## Inset window pane.
static func _mesh_glass() -> ArrayMesh:
	return _box_mesh(Vector3(0.12, 0.1, 0.12), Vector3(0.88, 0.9, 0.88))


## Low curb lip — visual matches the short collision box (~0.2 m world).
static func _mesh_curb() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_box(st, Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.28, 1.0))
	_emit_box(st, Vector3(0.04, 0.28, 0.04), Vector3(0.96, 0.4, 0.96))
	st.index()
	return st.commit()


## Lane paint: full asphalt body + raised center stripe (one material).
static func _mesh_road_line() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_box(st, Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.98, 1.0))
	_emit_box(st, Vector3(0.35, 0.98, 0.05), Vector3(0.65, 1.0, 0.95))
	st.index()
	return st.commit()


## Small flower blob for park accents.
static func _mesh_flower() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_box(st, Vector3(0.3, 0.0, 0.3), Vector3(0.7, 0.2, 0.7))
	_emit_box(st, Vector3(0.22, 0.2, 0.22), Vector3(0.78, 0.55, 0.78))
	_emit_box(st, Vector3(0.35, 0.55, 0.35), Vector3(0.65, 0.75, 0.65))
	st.index()
	return st.commit()


static func _emit_box(st: SurfaceTool, bmin: Vector3, bmax: Vector3) -> void:
	_add_quad(st, Vector3(bmin.x, bmin.y, bmax.z), Vector3(bmax.x, bmin.y, bmax.z), Vector3(bmax.x, bmax.y, bmax.z), Vector3(bmin.x, bmax.y, bmax.z), Vector3(0, 0, 1))
	_add_quad(st, Vector3(bmax.x, bmin.y, bmin.z), Vector3(bmin.x, bmin.y, bmin.z), Vector3(bmin.x, bmax.y, bmin.z), Vector3(bmax.x, bmax.y, bmin.z), Vector3(0, 0, -1))
	_add_quad(st, Vector3(bmin.x, bmin.y, bmin.z), Vector3(bmin.x, bmin.y, bmax.z), Vector3(bmin.x, bmax.y, bmax.z), Vector3(bmin.x, bmax.y, bmin.z), Vector3(-1, 0, 0))
	_add_quad(st, Vector3(bmax.x, bmin.y, bmax.z), Vector3(bmax.x, bmin.y, bmin.z), Vector3(bmax.x, bmax.y, bmin.z), Vector3(bmax.x, bmax.y, bmax.z), Vector3(1, 0, 0))
	_add_quad(st, Vector3(bmin.x, bmax.y, bmax.z), Vector3(bmax.x, bmax.y, bmax.z), Vector3(bmax.x, bmax.y, bmin.z), Vector3(bmin.x, bmax.y, bmin.z), Vector3(0, 1, 0))
	_add_quad(st, Vector3(bmin.x, bmin.y, bmin.z), Vector3(bmax.x, bmin.y, bmin.z), Vector3(bmax.x, bmin.y, bmax.z), Vector3(bmin.x, bmin.y, bmax.z), Vector3(0, -1, 0))


const SURFACE_SHADER := "res://assets/city/shaders/voxel_surface.gdshader"
## Debris MultiMesh path — same look as SURFACE_SHADER but instance COLOR.a fades.
const DEBRIS_SHADER := "res://assets/city/shaders/voxel_debris.gdshader"
const GLASS_SHADER := "res://assets/city/shaders/voxel_glass.gdshader"
const WATER_SHADER := "res://assets/city/shaders/voxel_water.gdshader"
const FOLIAGE_SHADER := "res://assets/city/shaders/voxel_foliage.gdshader"
## World height of the street deck (ground_thickness+1)*voxel_size with thickness=6.
const STREET_DECK_Y := 3.5
## Building lot footprint in metres (DistrictCoord.CELL_SIZE * VOXEL_WORLD_SIZE).
const LOT_METERS := 14.0

## Shared materials, reused by terrain blocks, debris and impostors.
static var _surface_mat_cache: Dictionary = {}  # id * 2 + object_space → ShaderMaterial
static var _infection_mat_cache: Dictionary = {}  # bool is_lead → ShaderMaterial
static var _meteor_rock_mat: ShaderMaterial = null
static var _gameboy_mat: ShaderMaterial = null


## Terrain block material. Everything except infection / meteor rock / Game Boy uses
## the shared world-projected surface shaders.
static func block_material_for(id: int) -> Material:
	if id == VoxelMaterial.INFECTION or id == VoxelMaterial.INFECTION_LEAD:
		return infection_material(id == VoxelMaterial.INFECTION_LEAD)
	if id == VoxelMaterial.METEOR_ROCK:
		return meteor_rock_material()
	if id == VoxelMaterial.GAMEBOY:
		return gameboy_material()
	return surface_material(id, false)


## Same look for detached geometry (cascade debris, impostor chunks). Those bodies
## tumble, so they project in mesh-local space — world projection would swim.
static func debris_material_for(id: int) -> Material:
	if id == VoxelMaterial.INFECTION or id == VoxelMaterial.INFECTION_LEAD:
		return infection_material(id == VoxelMaterial.INFECTION_LEAD)
	if id == VoxelMaterial.METEOR_ROCK:
		return meteor_rock_material()
	if id == VoxelMaterial.GAMEBOY:
		return gameboy_material()
	return surface_material(id, true)


## World-projected surface material for one voxel type.
static func surface_material(id: int, object_space: bool) -> ShaderMaterial:
	var key := id * 2 + (1 if object_space else 0)
	var cached: Variant = _surface_mat_cache.get(key)
	if cached is ShaderMaterial:
		return cached
	var mat := _build_surface_material(id, object_space)
	_surface_mat_cache[key] = mat
	return mat


static func _build_surface_material(id: int, object_space: bool) -> ShaderMaterial:
	var spec := VoxelSurfaceSpec.for_id(id)
	var mat := ShaderMaterial.new()
	match spec.kind:
		VoxelSurfaceSpec.Kind.GLASS:
			mat.shader = _load_shader(GLASS_SHADER)
			mat.set_shader_parameter("lit_ratio", spec.lit_ratio)
			mat.set_shader_parameter("night_factor", 0.0)
			mat.set_shader_parameter("lit_warm", Color(1.0, 0.82, 0.45, 1.0))
			mat.set_shader_parameter("lit_cool", Color(0.72, 0.86, 1.0, 1.0))
			mat.set_shader_parameter("lit_energy", 1.8)
			## One lit/dark draw per 1 m of facade — roughly one punched window.
			mat.set_shader_parameter("window_meters", 1.0)
			mat.set_shader_parameter("fresnel_strength", 0.55)
			mat.set_shader_parameter("day_sky_tint", 0.35)
		VoxelSurfaceSpec.Kind.WATER:
			mat.shader = _load_shader(WATER_SHADER)
			mat.set_shader_parameter("deep_tint", Color(0.07, 0.19, 0.28, 1.0))
			mat.set_shader_parameter("scroll_speed", 0.045)
			mat.set_shader_parameter("wave_scale", 1.6)
			mat.set_shader_parameter("wave_strength", 0.4)
			mat.set_shader_parameter("wave_speed", 0.7)
			mat.set_shader_parameter("fresnel_strength", 0.45)
			mat.set_shader_parameter("sparkle", 1.2)
		VoxelSurfaceSpec.Kind.FOLIAGE:
			## UV alpha cutout — same shader for terrain and debris (no world projection).
			mat.shader = _load_shader(FOLIAGE_SHADER)
			mat.set_shader_parameter("albedo_tex", _tex(spec.albedo_file))
			mat.set_shader_parameter("tint", spec.tint)
			mat.set_shader_parameter("roughness_base", spec.roughness)
			mat.set_shader_parameter("metallic_base", spec.metallic)
			mat.set_shader_parameter("alpha_scissor", 0.45)
			mat.set_shader_parameter("lot_meters", LOT_METERS)
			mat.set_shader_parameter("tint_variation", spec.tint_variation)
			return mat
		_:
			## Object-space materials are debris Multimeshes; they need a fade-capable
			## shader. Terrain stays on the opaque surface shader.
			mat.shader = _load_shader(DEBRIS_SHADER if object_space else SURFACE_SHADER)
			var ntex: Texture2D = null
			if spec.normal_file != "":
				ntex = _tex(spec.normal_file)
			mat.set_shader_parameter("use_normal", ntex != null)
			if ntex != null:
				mat.set_shader_parameter("normal_tex", ntex)
			mat.set_shader_parameter("normal_strength", spec.normal_strength)
			mat.set_shader_parameter("lot_meters", LOT_METERS)
			mat.set_shader_parameter("tint_variation", spec.tint_variation)
			mat.set_shader_parameter("weathering", spec.weathering)
			mat.set_shader_parameter("grime", spec.grime)
			mat.set_shader_parameter("ground_y", STREET_DECK_Y)
			mat.set_shader_parameter("grime_height", spec.grime_height)
			mat.set_shader_parameter("streaks", spec.streaks)

	mat.set_shader_parameter("albedo_tex", _tex(spec.albedo_file))
	mat.set_shader_parameter("tile_meters", spec.tile_meters)
	mat.set_shader_parameter("tint", spec.tint)
	mat.set_shader_parameter("roughness_base", spec.roughness)
	mat.set_shader_parameter("metallic_base", spec.metallic)
	mat.set_shader_parameter("object_space", 1.0 if object_space else 0.0)
	return mat


static func _load_shader(path: String) -> Shader:
	var shader := load(path) as Shader
	if shader == null:
		push_error("Missing voxel surface shader: %s" % path)
	return shader


## Olive Game Boy plastic — animated LCD sheen (gameboy_shell.gdshader).
static func gameboy_material() -> ShaderMaterial:
	if _gameboy_mat != null:
		return _gameboy_mat
	var shader: Shader = load("res://assets/city/shaders/gameboy_shell.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var plas: Texture2D = _tex("plaster.jpg")
	if plas != null:
		mat.set_shader_parameter("albedo_tex", plas)
		mat.set_shader_parameter("texture_mix", 0.58)
	else:
		mat.set_shader_parameter("texture_mix", 0.0)
	mat.set_shader_parameter("plastic_tint", Color(0.56, 0.66, 0.42, 1.0))
	mat.set_shader_parameter("seam_color", Color(0.14, 0.18, 0.11, 1.0))
	mat.set_shader_parameter("lcd_glow", Color(0.4, 0.98, 0.45, 1.0))
	mat.set_shader_parameter("lcd_deep", Color(0.1, 0.24, 0.08, 1.0))
	## Panel layout keyed to the voxel grid so each cell reads as a moulded brick.
	mat.set_shader_parameter("cell_size", VOXEL_WORLD_SIZE)
	mat.set_shader_parameter("seam_width", 0.07)
	mat.set_shader_parameter("bevel", 0.24)
	mat.set_shader_parameter("grain_scale", 7.0)
	mat.set_shader_parameter("grain_strength", 0.35)
	mat.set_shader_parameter("cell_tint_variation", 0.1)
	mat.set_shader_parameter("emission_base", 0.14)
	mat.set_shader_parameter("emission_peak", 0.45)
	mat.set_shader_parameter("pulse_hz", 0.35)
	mat.set_shader_parameter("scan_strength", 0.32)
	mat.set_shader_parameter("sheen", 0.55)
	_gameboy_mat = mat
	return mat


## Dark rock with red glowing veins only (emission masked to cracks).
static func meteor_rock_material() -> ShaderMaterial:
	if _meteor_rock_mat != null:
		return _meteor_rock_mat
	var shader: Shader = load("res://assets/city/shaders/meteor_rock_veins.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var rock: Texture2D = _tex("rock.jpg")
	if rock != null:
		mat.set_shader_parameter("albedo_tex", rock)
	mat.set_shader_parameter("rock_tint", Color(0.48, 0.4, 0.35, 1.0))
	mat.set_shader_parameter("vein_color", Color(1.0, 0.16, 0.04, 1.0))
	mat.set_shader_parameter("vein_hot", Color(1.0, 0.5, 0.1, 1.0))
	mat.set_shader_parameter("texture_mix", 0.82)
	mat.set_shader_parameter("vein_emission", 4.2)
	mat.set_shader_parameter("flow_speed", 0.32)
	mat.set_shader_parameter("vein_scale", 1.9)
	mat.set_shader_parameter("vein_threshold", 0.64)
	mat.set_shader_parameter("vein_width", 0.1)
	mat.set_shader_parameter("pulse_hz", 0.5)
	_meteor_rock_mat = mat
	return mat



## Animated infection look — GPU TIME/noise only; shared across all infected voxels.
static func infection_material(is_lead: bool) -> ShaderMaterial:
	var cached: Variant = _infection_mat_cache.get(is_lead)
	if cached is ShaderMaterial:
		return cached
	var shader: Shader = load("res://assets/city/shaders/infection_alive.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var leaves: Texture2D = _tex("leaves.png")
	if leaves != null:
		mat.set_shader_parameter("albedo_tex", leaves)
	if is_lead:
		mat.set_shader_parameter("base_color", Color(0.4, 0.85, 0.28, 1.0))
		mat.set_shader_parameter("vein_color", Color(0.75, 1.0, 0.35, 1.0))
		mat.set_shader_parameter("pulse_color", Color(0.95, 1.0, 0.55, 1.0))
		mat.set_shader_parameter("emission_base", 1.6)
		mat.set_shader_parameter("emission_peak", 5.5)
		mat.set_shader_parameter("pulse_hz", 1.8)
		mat.set_shader_parameter("flow_speed", 0.95)
		mat.set_shader_parameter("lead_boost", 1.0)
		mat.set_shader_parameter("texture_mix", 0.35)
	else:
		mat.set_shader_parameter("base_color", Color(0.22, 0.48, 0.18, 1.0))
		mat.set_shader_parameter("vein_color", Color(0.45, 0.92, 0.28, 1.0))
		mat.set_shader_parameter("pulse_color", Color(0.7, 1.0, 0.4, 1.0))
		mat.set_shader_parameter("emission_base", 0.45)
		mat.set_shader_parameter("emission_peak", 2.1)
		mat.set_shader_parameter("pulse_hz", 1.05)
		mat.set_shader_parameter("flow_speed", 0.55)
		mat.set_shader_parameter("lead_boost", 0.0)
		mat.set_shader_parameter("texture_mix", 0.5)
	_infection_mat_cache[is_lead] = mat
	return mat


## Drive emissive punched windows with day/night (shared GLASS_LIT materials).
static func set_glass_lit_night_factor(night_factor: float) -> void:
	var n := clampf(night_factor, 0.0, 1.0)
	for id in [VoxelMaterial.GLASS, VoxelMaterial.GLASS_LIT]:
		surface_material(id, false).set_shader_parameter("night_factor", n)
		surface_material(id, true).set_shader_parameter("night_factor", n)


static func _tex(file_name: String) -> Texture2D:
	var path := TEX_DIR + file_name
	if not ResourceLoader.exists(path):
		push_error("Missing city texture: %s" % path)
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		push_error("Failed to load city texture: %s" % path)
	return tex
