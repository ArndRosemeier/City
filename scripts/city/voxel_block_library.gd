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
		VoxelMaterial.BRANCH_X:
			## Horizontal limb along +X — walk-through wood like bark.
			return _mesh_model(id, _mesh_branch_x(), false, false, AABB(), false)
		VoxelMaterial.BRANCH_Z:
			return _mesh_model(id, _mesh_branch_z(), false, false, AABB(), false)
		VoxelMaterial.LEAVES_DARK:
			## Same cards as LEAVES; darker tint comes from the surface spec.
			return _mesh_model(id, _mesh_leaves(), true, false, AABB(), false)
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
		VoxelMaterial.CLOUDSTONE:
			## Billowy multi-lobe puff — not a cube. Collision stays a squat box so the
			## pad is still a walkable footing under the fluff.
			return _mesh_model(
				id,
				_mesh_cloudstone(),
				true,
				false,
				AABB(Vector3(0.12, 0.0, 0.12), Vector3(0.76, 0.62, 0.76))
			)
		VoxelMaterial.ORB:
			## Energy sphere tip / prop. Culls off so a shaft under it keeps its top face.
			return _mesh_model(
				id,
				_mesh_orb(),
				true,
				false,
				AABB(Vector3(0.12, 0.12, 0.12), Vector3(0.76, 0.76, 0.76))
			)
		VoxelMaterial.GLASS:
			## Engine cube geometry — custom full-cell meshes were wound such that
			## cull_back dropped every face (windows read as air holes). Opaque cube
			## + glass shader = solid pane that sorts with brick.
			return _make_glass_cube(id)
		VoxelMaterial.GLASS_LIT, VoxelMaterial.LAB_WINDOW:
			return _make_glass_cube(id)
		VoxelMaterial.ZOO_FENCE_GLASS, VoxelMaterial.CAVE_CAGE_GLASS:
			return _make_glass_cube(id)
		VoxelMaterial.LOS_VEIL:
			## Invisible walk-through volume that still counts as solid for LOS probes.
			return _make_los_veil_model()
		VoxelMaterial.CURB:
			## Low curb lip (~0.2 m world) so CharacterBody can step/jump it.
			return _mesh_model(id, _mesh_curb(), false, true, AABB(Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.4, 1.0)))
		VoxelMaterial.ZOO_PLATE_RIM:
			## Short curb around a turf pad — taller than the glow so the lip reads.
			return _mesh_model(
				id,
				_mesh_zoo_plate_rim(),
				false,
				false,
				AABB(Vector3(0.0, 0.0, 0.0), Vector3(1.0, PLATE_RIM_H, 1.0))
			)
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
			if id == VoxelMaterial.PROP_FOOTPRINT:
				return _make_prop_footprint_model()
			if id == VoxelMaterial.DOOR:
				## Full-cell solid — motion/nav block; leaf meshes are visual only.
				return _make_cube(id)
			if VoxelMaterial.is_gem(id):
				## Faceted crystal in the cell — not a filled ore cube. Culls off so host
				## rock keeps its faces around the stone.
				return _mesh_model(
					id,
					_mesh_gem(id),
					false,
					false,
					AABB(Vector3(0.18, 0.10, 0.18), Vector3(0.64, 0.80, 0.64))
				)
			if VoxelMaterial.is_room_prop(id):
				return _make_room_prop_model(id)
			if VoxelMaterial.is_zoo_turf(id):
				## Short glowing slab — a faction pad, not a full dirt cell painted over.
				return _mesh_model(
					id,
					_mesh_zoo_turf_pad(),
					false,
					false,
					AABB(Vector3(0.0, 0.0, 0.0), Vector3(1.0, PLATE_PAD_H, 1.0))
				)
			return _make_cube(id)


static func _make_room_prop_model(id: int) -> VoxelBlockyModelMesh:
	var e := RoomPropCatalog.entry(id)
	var stem := String(e.get("stem", ""))
	var walk := bool(e.get("walk_through", false))
	var origin: Vector3 = e.get("aabb", Vector3.ZERO)
	var size: Vector3 = e.get("aabb_size", Vector3.ONE)
	var box := AABB(origin, size)
	return _mesh_model_prop(id, _mesh_prop(stem), box, walk)


## Sibling cell of a multi-cell prop: solid for nav, no mesh (origin draws the whole piece).
static func _make_prop_footprint_model() -> VoxelBlockyModelMesh:
	var model := VoxelBlockyModelMesh.new()
	model.mesh = ArrayMesh.new()
	model.set_mesh_collision_enabled(0, false)
	model.culls_neighbors = false
	model.collision_aabbs = [AABB(Vector3.ZERO, Vector3.ONE)]
	return model


## No mesh, no collision — CharacterBody and nav pass through; ProjectileLos still hits
## because the voxel id is non-air (`VoxelMaterial.is_solid`).
static func _make_los_veil_model() -> VoxelBlockyModelMesh:
	var model := VoxelBlockyModelMesh.new()
	model.mesh = ArrayMesh.new()
	model.set_mesh_collision_enabled(0, false)
	model.culls_neighbors = false
	model.collision_aabbs = []
	model.collision_mask = 0
	return model


static func _make_cube(id: int) -> VoxelBlockyModelCube:
	var cube := VoxelBlockyModelCube.new()
	cube.color = Color(1, 1, 1, 1)
	cube.set_material_override(0, block_material_for(id))
	if id == VoxelMaterial.WATER:
		cube.transparency_index = 1
	return cube


static func _make_glass_cube(id: int) -> VoxelBlockyModelCube:
	var cube := VoxelBlockyModelCube.new()
	cube.color = Color(1, 1, 1, 1)
	cube.set_material_override(0, block_material_for(id))
	## Stay on the opaque mesher path (no transparency_index).
	return cube


## Room furniture: visual only + collision AABBs. Never attach a full-cell discard
## mesh (egg-crate cull) — props are partial fills with culls_neighbors off.
static func _mesh_model_prop(
	id: int, visual: ArrayMesh, collision_aabb: AABB, walk_through: bool = false
) -> VoxelBlockyModelMesh:
	var model := VoxelBlockyModelMesh.new()
	var mat := block_material_for(id)
	model.mesh = visual
	model.set_material_override(0, mat)
	model.set_mesh_collision_enabled(0, false)
	model.culls_neighbors = false
	if walk_through or collision_aabb.size == Vector3.ZERO:
		model.collision_aabbs = []
		model.collision_mask = 0
	else:
		## Full cell so blasts / rays hit the furniture volume (catalog AABB is only a
		## subset of the multi-cell mesh; footprint siblings use PROP_FOOTPRINT boxes).
		model.collision_aabbs = [AABB(Vector3.ZERO, Vector3.ONE)]
	return model


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
		## Skirts at chunk edges show through alpha-cut foliage as a hard horizontal band.
		model.lod_skirts_enabled = false
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
	## Full-cell height (slight overlap). Inset tops/bottoms left a sky slit between
	## stacked leaf cells — reads as one hard air-line at 16³ chunk seams.
	var y0 := -0.02
	var y1 := 1.02
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


## Thin horizontal branch along X (limb kit for landmark trees).
static func _mesh_branch_x() -> ArrayMesh:
	return _mesh_branch_cylinder(true)


## Thin horizontal branch along Z.
static func _mesh_branch_z() -> ArrayMesh:
	return _mesh_branch_cylinder(false)


## Cylinder spanning the cell on one horizontal axis. Thinner than the trunk so limbs
## read as wood at 0.5 m without becoming full beams.
static func _mesh_branch_cylinder(along_x: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 10
	var r := 0.11
	var cy := 0.52
	for i in range(sides):
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var c0 := cos(a0) * r
		var s0 := sin(a0) * r
		var c1 := cos(a1) * r
		var s1 := sin(a1) * r
		var n: Vector3
		var p0a: Vector3
		var p1a: Vector3
		var p1b: Vector3
		var p0b: Vector3
		if along_x:
			n = Vector3(0.0, cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5)).normalized()
			p0a = Vector3(0.0, cy + c0, 0.5 + s0)
			p1a = Vector3(1.0, cy + c0, 0.5 + s0)
			p1b = Vector3(1.0, cy + c1, 0.5 + s1)
			p0b = Vector3(0.0, cy + c1, 0.5 + s1)
		else:
			n = Vector3(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5), 0.0).normalized()
			p0a = Vector3(0.5 + c0, cy + s0, 0.0)
			p1a = Vector3(0.5 + c0, cy + s0, 1.0)
			p1b = Vector3(0.5 + c1, cy + s1, 1.0)
			p0b = Vector3(0.5 + c1, cy + s1, 0.0)
		_add_quad(st, p0a, p1a, p1b, p0b, n)
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


## Soft cloud puff: overlapping UV-spheres in the unit cell (Minecraft-ish fluff).
static func _mesh_cloudstone() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	## Lobes sit slightly above the floor so the silhouette reads as floating fluff.
	_emit_uv_sphere(st, Vector3(0.50, 0.40, 0.50), 0.36, 10, 6)
	_emit_uv_sphere(st, Vector3(0.26, 0.36, 0.46), 0.26, 8, 5)
	_emit_uv_sphere(st, Vector3(0.74, 0.38, 0.54), 0.27, 8, 5)
	_emit_uv_sphere(st, Vector3(0.48, 0.34, 0.26), 0.24, 8, 5)
	_emit_uv_sphere(st, Vector3(0.52, 0.42, 0.74), 0.25, 8, 5)
	_emit_uv_sphere(st, Vector3(0.50, 0.62, 0.48), 0.28, 8, 5)
	_emit_uv_sphere(st, Vector3(0.34, 0.52, 0.34), 0.18, 7, 4)
	_emit_uv_sphere(st, Vector3(0.68, 0.54, 0.62), 0.17, 7, 4)
	st.index()
	return st.commit()


## Single energy sphere filling most of the cell — siege tower tip and reusable prop.
static func _mesh_orb() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_uv_sphere(st, Vector3(0.5, 0.5, 0.5), 0.42, 14, 10)
	st.index()
	return st.commit()


## World gem ore: two cuts. Common stones are a blunt hex column; sapphire+ get a
## sharp octagonal bipyramid so quartz and diamond read apart even when both glow white.
static func _mesh_gem(id: int) -> ArrayMesh:
	if VoxelMaterial.is_gem_brilliant(id):
		return _mesh_gem_brilliant()
	return _mesh_gem_column()


## Rough hexagonal prism — cheap mineral look (quartz / amber / topaz).
static func _mesh_gem_column() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cx := 0.5
	var cz := 0.5
	var y0 := 0.12
	var y1 := 0.88
	var radius := 0.30
	var sides := 6
	var ring_lo: Array[Vector3] = []
	var ring_hi: Array[Vector3] = []
	for i in sides:
		var a := TAU * float(i) / float(sides) + PI / float(sides)
		var x := cx + cos(a) * radius
		var z := cz + sin(a) * radius
		ring_lo.append(Vector3(x, y0, z))
		ring_hi.append(Vector3(x, y1, z))
	for i in sides:
		var i1 := (i + 1) % sides
		_add_facet(st, ring_lo[i], ring_lo[i1], ring_hi[i1])
		_add_facet(st, ring_lo[i], ring_hi[i1], ring_hi[i])
	## Caps — fan from centre so flat ends keep a single outward normal each.
	var top_c := Vector3(cx, y1, cz)
	var bot_c := Vector3(cx, y0, cz)
	for i in sides:
		var i1 := (i + 1) % sides
		_add_facet(st, top_c, ring_hi[i], ring_hi[i1])
		_add_facet(st, bot_c, ring_lo[i1], ring_lo[i])
	st.index()
	return st.commit()


## Cut-stone octagonal bipyramid — expensive brilliant (sapphire / emerald / diamond).
static func _mesh_gem_brilliant() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0.5, 0.5, 0.5)
	var top := Vector3(0.5, 0.92, 0.5)
	var bottom := Vector3(0.5, 0.08, 0.5)
	var radius := 0.36
	var sides := 8
	var ring: Array[Vector3] = []
	for i in sides:
		var a := TAU * float(i) / float(sides)
		ring.append(Vector3(center.x + cos(a) * radius, center.y, center.z + sin(a) * radius))
	for i in sides:
		var i1 := (i + 1) % sides
		_add_facet(st, top, ring[i], ring[i1])
		_add_facet(st, bottom, ring[i1], ring[i])
	st.index()
	return st.commit()


## Flat facet with outward lighting normal. Winds clockwise from outside so Godot
## front faces stay visible (cross points inward — see voxel-custom-meshes rule).
static func _add_facet(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var mid := (a + b + c) * (1.0 / 3.0)
	var toward_out := mid - Vector3(0.5, 0.5, 0.5)
	var cross := (b - a).cross(c - a)
	if cross.length_squared() < 1e-12:
		return
	## If the geometric cross already points outward, flip winding so it points in.
	if toward_out.length_squared() > 1e-10 and cross.dot(toward_out) > 0.0:
		var tmp := b
		b = c
		c = tmp
		cross = (b - a).cross(c - a)
	var outward := -cross.normalized()
	_add_tri(st, a, b, c, outward)


static func _emit_uv_sphere(
	st: SurfaceTool, center: Vector3, radius: float, segments: int, rings: int
) -> void:
	var segs := maxi(segments, 4)
	var rngs := maxi(rings, 2)
	for ring in range(rngs):
		var v0 := float(ring) / float(rngs)
		var v1 := float(ring + 1) / float(rngs)
		var y0 := cos(PI * v0)
		var y1 := cos(PI * v1)
		var r0 := sin(PI * v0)
		var r1 := sin(PI * v1)
		for seg in range(segs):
			var u0 := float(seg) / float(segs)
			var u1 := float(seg + 1) / float(segs)
			var a0 := u0 * TAU
			var a1 := u1 * TAU
			var n00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var n10 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var n11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			var n01 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p00 := center + n00 * radius
			var p10 := center + n10 * radius
			var p11 := center + n11 * radius
			var p01 := center + n01 * radius
			## Skip degenerate rings at the poles.
			if r0 > 0.0001:
				st.set_normal(n00.normalized())
				st.set_uv(Vector2(u0, v0))
				st.add_vertex(p00)
				st.set_normal(n10.normalized())
				st.set_uv(Vector2(u1, v0))
				st.add_vertex(p10)
				st.set_normal(n11.normalized())
				st.set_uv(Vector2(u1, v1))
				st.add_vertex(p11)
			if r1 > 0.0001:
				st.set_normal(n00.normalized())
				st.set_uv(Vector2(u0, v0))
				st.add_vertex(p00)
				st.set_normal(n11.normalized())
				st.set_uv(Vector2(u1, v1))
				st.add_vertex(p11)
				st.set_normal(n01.normalized())
				st.set_uv(Vector2(u0, v1))
				st.add_vertex(p01)


## Full-cell glass volume (same idea as water — continuous sheet, not inset panes).
static func _mesh_glass() -> ArrayMesh:
	return _box_mesh(Vector3.ZERO, Vector3.ONE)


## Low curb lip — visual matches the short collision box (~0.2 m world).
static func _mesh_curb() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_emit_box(st, Vector3(0.0, 0.0, 0.0), Vector3(1.0, 0.28, 1.0))
	_emit_box(st, Vector3(0.04, 0.28, 0.04), Vector3(0.96, 0.4, 0.96))
	st.index()
	return st.commit()


## Unit-cell heights for zoo faction pads (cell is 0..1). Short on purpose — less than a
## full voxel of drop from neighbouring dirt, with the rim a hair taller as the lip.
const PLATE_PAD_H := 0.32
const PLATE_RIM_H := 0.48


## Glowing 2×2 pad body: a low slab with a slight bevel so it does not read as a flat stamp.
static func _mesh_zoo_turf_pad() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := PLATE_PAD_H
	_emit_box(st, Vector3(0.0, 0.0, 0.0), Vector3(1.0, h * 0.72, 1.0))
	_emit_box(st, Vector3(0.06, h * 0.72, 0.06), Vector3(0.94, h, 0.94))
	st.index()
	return st.commit()


## Dark lip around the pad — taller than the glow, still well under a full cell.
static func _mesh_zoo_plate_rim() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := PLATE_RIM_H
	_emit_box(st, Vector3(0.0, 0.0, 0.0), Vector3(1.0, h * 0.7, 1.0))
	_emit_box(st, Vector3(0.05, h * 0.7, 0.05), Vector3(0.95, h, 0.95))
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


static var _prop_mesh_cache: Dictionary = {}  # stem → ArrayMesh


## Unit-cell prop OBJ from tools/gen_room_prop_catalog.py (0..1).
static func _mesh_prop(stem: String) -> ArrayMesh:
	var cached: Variant = _prop_mesh_cache.get(stem)
	if cached is ArrayMesh:
		return cached
	var path := RoomPropCatalog.PROP_MESH_DIR + stem + ".obj"
	var loaded: Resource = load(path)
	var mesh: ArrayMesh = null
	if loaded is ArrayMesh:
		mesh = loaded
	elif loaded is Mesh:
		## Importer may yield Mesh; copy surfaces into ArrayMesh for the library.
		var src := loaded as Mesh
		mesh = ArrayMesh.new()
		for s in range(src.get_surface_count()):
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(s))
	if mesh == null or mesh.get_surface_count() == 0:
		push_error("VoxelBlockLibrary._mesh_prop: missing/empty %s — using planter stub" % path)
		mesh = _mesh_planter()
	_prop_mesh_cache[stem] = mesh
	return mesh


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
const CLOUDSTONE_SHADER := "res://assets/city/shaders/voxel_cloudstone.gdshader"
const FOLIAGE_SHADER := "res://assets/city/shaders/voxel_foliage.gdshader"
## World height of the street deck (ground_thickness+1)*voxel_size with thickness=6.
const STREET_DECK_Y := 3.5
## Building lot footprint in metres (DistrictCoord.CELL_SIZE * VOXEL_WORLD_SIZE).
const LOT_METERS := 14.0

## Shared materials, reused by terrain blocks, debris and impostors.
static var _surface_mat_cache: Dictionary = {}  # id * 2 + object_space → ShaderMaterial
static var _infection_mat_cache: Dictionary = {}  # bool is_lead → ShaderMaterial
static var _gem_mat_cache: Dictionary = {}  # gem id → ShaderMaterial
static var _fractal_glow_mat: ShaderMaterial = null
static var _fractal_band_mat_cache: Dictionary = {}  # band id → ShaderMaterial
static var _fractal_interior_mat: ShaderMaterial = null
static var _orb_mat: ShaderMaterial = null
static var _alchemy_catalyst_mat: ShaderMaterial = null
static var _meteor_rock_mat: ShaderMaterial = null
static var _gameboy_mat: ShaderMaterial = null
static var _zoo_fence_line_mat: ShaderMaterial = null
static var _zoo_turf_mat_cache: Dictionary = {}


## Terrain block material. Everything except infection / meteor rock / Game Boy / gems
## / fractal glow uses the shared world-projected surface shaders.
static func block_material_for(id: int) -> Material:
	if id == VoxelMaterial.INFECTION or id == VoxelMaterial.INFECTION_LEAD:
		return infection_material(id == VoxelMaterial.INFECTION_LEAD)
	if id == VoxelMaterial.METEOR_ROCK:
		return meteor_rock_material()
	if id == VoxelMaterial.GAMEBOY:
		return gameboy_material()
	if VoxelMaterial.is_gem(id):
		return gem_material(id)
	if id == VoxelMaterial.FRACTAL_GLOW:
		return fractal_glow_material()
	if id == VoxelMaterial.FRACTAL_INTERIOR:
		return fractal_interior_material()
	if VoxelMaterial.is_fractal_band(id):
		return fractal_band_material(id)
	if id == VoxelMaterial.ORB:
		return orb_material()
	if id == VoxelMaterial.ALCHEMY_CATALYST:
		return alchemy_catalyst_material()
	if id == VoxelMaterial.ZOO_FENCE_LINE or id == VoxelMaterial.CAVE_CAGE_LINE:
		return zoo_fence_line_material()
	if VoxelMaterial.is_zoo_turf(id):
		return zoo_turf_material(id)
	## Room props are authored meshes — grain follows the prop, not the street.
	if VoxelMaterial.is_room_prop(id) or id == VoxelMaterial.PROP_FOOTPRINT:
		return surface_material(id, true)
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
	if VoxelMaterial.is_gem(id):
		return gem_material(id)
	if id == VoxelMaterial.FRACTAL_GLOW:
		return fractal_glow_material()
	if id == VoxelMaterial.FRACTAL_INTERIOR:
		return fractal_interior_material()
	if VoxelMaterial.is_fractal_band(id):
		return fractal_band_material(id)
	if id == VoxelMaterial.ORB:
		return orb_material()
	if id == VoxelMaterial.ALCHEMY_CATALYST:
		return alchemy_catalyst_material()
	if id == VoxelMaterial.ZOO_FENCE_LINE or id == VoxelMaterial.CAVE_CAGE_LINE:
		return zoo_fence_line_material()
	if VoxelMaterial.is_zoo_turf(id):
		return zoo_turf_material(id)
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
			## Warm/cool variation cell — roughly one punched window.
			mat.set_shader_parameter("window_meters", 1.0)
			mat.set_shader_parameter("fresnel_strength", 0.85)
			mat.set_shader_parameter("day_sky_tint", 0.4)
		VoxelSurfaceSpec.Kind.WATER:
			mat.shader = _load_shader(WATER_SHADER)
			mat.set_shader_parameter("deep_tint", Color(0.07, 0.19, 0.28, 1.0))
			mat.set_shader_parameter("scroll_speed", 0.045)
			mat.set_shader_parameter("wave_scale", 1.6)
			mat.set_shader_parameter("wave_strength", 0.4)
			mat.set_shader_parameter("wave_speed", 0.7)
			mat.set_shader_parameter("fresnel_strength", 0.45)
			mat.set_shader_parameter("sparkle", 1.2)
		VoxelSurfaceSpec.Kind.CLOUDSTONE:
			mat.shader = _load_shader(CLOUDSTONE_SHADER)
			mat.set_shader_parameter("tint", spec.tint)
			mat.set_shader_parameter("shadow_tint", Color(0.55, 0.62, 0.78, 1.0))
			mat.set_shader_parameter("roughness_base", spec.roughness)
			mat.set_shader_parameter("metallic_base", spec.metallic)
			mat.set_shader_parameter("object_space", 1.0 if object_space else 0.0)
			mat.set_shader_parameter("puff_scale", 1.15)
			mat.set_shader_parameter("puff_speed", 0.22)
			mat.set_shader_parameter("emission_strength", 0.35)
			mat.set_shader_parameter("edge_softness", 0.45)
			return mat
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
			mat.set_shader_parameter("patch_variation", spec.patch_variation)
			mat.set_shader_parameter("patch_meters", spec.patch_meters)
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



## Fractal plaza uni-cubes — same gem shader as ore, sapphire-cyan pulse, but not a GEM_*.
static func fractal_glow_material() -> ShaderMaterial:
	if _fractal_glow_mat != null:
		return _fractal_glow_mat
	var shader: Shader = load("res://assets/city/shaders/voxel_gem.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("base_color", VoxelMaterial.color(VoxelMaterial.FRACTAL_GLOW))
	mat.set_shader_parameter("emission_color", Color(0.25, 0.55, 1.0))
	mat.set_shader_parameter("emission_base", 1.6)
	mat.set_shader_parameter("emission_peak", 4.4)
	mat.set_shader_parameter("pulse_hz", 0.9)
	mat.set_shader_parameter("sparkle_scale", 4.0)
	mat.set_shader_parameter("metallic_base", 0.2)
	mat.set_shader_parameter("roughness_base", 0.18)
	_fractal_glow_mat = mat
	return mat


## Hot white energy node — brighter and faster pulse than ore so it reads as a firing tip.
static func orb_material() -> ShaderMaterial:
	if _orb_mat != null:
		return _orb_mat
	var shader: Shader = load("res://assets/city/shaders/voxel_gem.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("base_color", VoxelMaterial.color(VoxelMaterial.ORB))
	mat.set_shader_parameter("emission_color", Color(0.85, 0.95, 1.0))
	mat.set_shader_parameter("emission_base", 2.4)
	mat.set_shader_parameter("emission_peak", 7.5)
	mat.set_shader_parameter("pulse_hz", 1.6)
	mat.set_shader_parameter("sparkle_scale", 5.5)
	mat.set_shader_parameter("metallic_base", 0.05)
	mat.set_shader_parameter("roughness_base", 0.12)
	_orb_mat = mat
	return mat


## Alchemy vat — acid green with a slow, uneasy churn. Deliberately the only glowing thing
## in a furnished room so the eye lands on it and the player decides whether to shoot it.
static func alchemy_catalyst_material() -> ShaderMaterial:
	if _alchemy_catalyst_mat != null:
		return _alchemy_catalyst_mat
	var shader: Shader = load("res://assets/city/shaders/voxel_gem.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("base_color", VoxelMaterial.color(VoxelMaterial.ALCHEMY_CATALYST))
	mat.set_shader_parameter("emission_color", Color(0.45, 1.0, 0.35))
	mat.set_shader_parameter("emission_base", 1.5)
	mat.set_shader_parameter("emission_peak", 4.0)
	mat.set_shader_parameter("pulse_hz", 0.55)
	mat.set_shader_parameter("sparkle_scale", 3.0)
	mat.set_shader_parameter("metallic_base", 0.15)
	mat.set_shader_parameter("roughness_base", 0.25)
	_alchemy_catalyst_mat = mat
	return mat


## Zoo containment line — the same emissive cube shader the fractal deck uses, pushed
## hard into red. Slow pulse: this is a standing hazard, not a landmark that sparkles.
static func zoo_fence_line_material() -> ShaderMaterial:
	if _zoo_fence_line_mat != null:
		return _zoo_fence_line_mat
	var shader: Shader = load("res://assets/city/shaders/voxel_gem.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("base_color", VoxelMaterial.color(VoxelMaterial.ZOO_FENCE_LINE))
	mat.set_shader_parameter("emission_color", Color(1.0, 0.08, 0.06))
	mat.set_shader_parameter("emission_base", 3.6)
	mat.set_shader_parameter("emission_peak", 7.5)
	mat.set_shader_parameter("pulse_hz", 0.25)
	mat.set_shader_parameter("sparkle_scale", 1.2)
	mat.set_shader_parameter("metallic_base", 0.0)
	mat.set_shader_parameter("roughness_base", 0.35)
	_zoo_fence_line_mat = mat
	return mat


## Faction home-turf plate — saturated ground that glows in the owner's colour so a
## visitor can tell whose field they are about to stand on before it starts burning.
static func zoo_turf_material(id: int) -> ShaderMaterial:
	if not VoxelMaterial.is_zoo_turf(id):
		push_error("VoxelBlockLibrary.zoo_turf_material: %d is not zoo turf" % id)
		return zoo_fence_line_material()
	var cached: Variant = _zoo_turf_mat_cache.get(id)
	if cached is ShaderMaterial:
		return cached as ShaderMaterial
	var albedo := VoxelMaterial.color(id)
	var emit := Color(
		clampf(albedo.r * 1.15, 0.0, 1.0),
		clampf(albedo.g * 1.15, 0.0, 1.0),
		clampf(albedo.b * 1.15, 0.0, 1.0)
	)
	var shader: Shader = load("res://assets/city/shaders/voxel_gem.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("base_color", albedo)
	mat.set_shader_parameter("emission_color", emit)
	mat.set_shader_parameter("emission_base", 2.8)
	mat.set_shader_parameter("emission_peak", 5.8)
	mat.set_shader_parameter("pulse_hz", 0.4)
	mat.set_shader_parameter("sparkle_scale", 2.2)
	mat.set_shader_parameter("metallic_base", 0.05)
	mat.set_shader_parameter("roughness_base", 0.45)
	_zoo_turf_mat_cache[id] = mat
	return mat


## Mandelbrot set body — dark, no glow (contrasts with FRACTAL_GLOW plaza).
static func fractal_interior_material() -> ShaderMaterial:
	if _fractal_interior_mat != null:
		return _fractal_interior_mat
	var shader: Shader = load("res://assets/city/shaders/voxel_fractal_band.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var albedo := VoxelMaterial.color(VoxelMaterial.FRACTAL_INTERIOR)
	mat.set_shader_parameter("base_color", albedo)
	mat.set_shader_parameter("emission_color", albedo)
	mat.set_shader_parameter("emission_strength", 0.0)
	mat.set_shader_parameter("pulse_hz", 0.0)
	mat.set_shader_parameter("metallic_base", 0.05)
	mat.set_shader_parameter("roughness_base", 0.55)
	_fractal_interior_mat = mat
	return mat


## Mandelbrot sculpture bands — albedo-first palette shader (not gem ore wash).
static func fractal_band_material(id: int) -> ShaderMaterial:
	if not VoxelMaterial.is_fractal_band(id):
		push_error("VoxelBlockLibrary.fractal_band_material: not a band id %d" % id)
		return fractal_glow_material()
	var cached: Variant = _fractal_band_mat_cache.get(id)
	if cached is ShaderMaterial:
		return cached
	var albedo := VoxelMaterial.color(id)
	var shader: Shader = load("res://assets/city/shaders/voxel_fractal_band.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("base_color", albedo)
	mat.set_shader_parameter("emission_color", albedo)
	mat.set_shader_parameter("emission_strength", 0.22)
	mat.set_shader_parameter("pulse_hz", 0.2)
	mat.set_shader_parameter("metallic_base", 0.1)
	mat.set_shader_parameter("roughness_base", 0.38)
	_fractal_band_mat_cache[id] = mat
	return mat


## Glowing gem ore — one shared shader, per-id colors / emission strength.
static func gem_material(id: int) -> ShaderMaterial:
	if not VoxelMaterial.is_gem(id):
		push_error("VoxelBlockLibrary.gem_material: not a gem id %d" % id)
		return surface_material(VoxelMaterial.STONE, false)
	var cached: Variant = _gem_mat_cache.get(id)
	if cached is ShaderMaterial:
		return cached
	var shader: Shader = load("res://assets/city/shaders/voxel_gem.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var albedo := VoxelMaterial.color(id)
	var emit := albedo
	var em_base := 1.0
	var em_peak := 2.8
	var pulse := 0.8
	match id:
		VoxelMaterial.GEM_QUARTZ:
			emit = Color(0.75, 0.9, 1.0)
			em_base = 0.9
			em_peak = 2.4
			pulse = 0.7
		VoxelMaterial.GEM_AMBER:
			emit = Color(1.0, 0.55, 0.12)
			em_base = 1.1
			em_peak = 3.0
			pulse = 0.75
		VoxelMaterial.GEM_TOPAZ:
			emit = Color(1.0, 0.78, 0.25)
			em_base = 1.25
			em_peak = 3.4
			pulse = 0.85
		VoxelMaterial.GEM_SAPPHIRE:
			emit = Color(0.25, 0.45, 1.0)
			em_base = 1.5
			em_peak = 4.2
			pulse = 0.95
		VoxelMaterial.GEM_EMERALD:
			emit = Color(0.2, 1.0, 0.45)
			em_base = 1.7
			em_peak = 4.8
			pulse = 1.05
		VoxelMaterial.GEM_DIAMOND:
			emit = Color(0.95, 0.98, 1.0)
			em_base = 2.2
			em_peak = 6.5
			pulse = 1.25
	mat.set_shader_parameter("base_color", albedo)
	mat.set_shader_parameter("emission_color", emit)
	mat.set_shader_parameter("emission_base", em_base)
	mat.set_shader_parameter("emission_peak", em_peak)
	mat.set_shader_parameter("pulse_hz", pulse)
	mat.set_shader_parameter("sparkle_scale", 4.5)
	mat.set_shader_parameter("metallic_base", 0.18 if id != VoxelMaterial.GEM_DIAMOND else 0.35)
	mat.set_shader_parameter("roughness_base", 0.2 if id != VoxelMaterial.GEM_DIAMOND else 0.08)
	_gem_mat_cache[id] = mat
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
	for id in [VoxelMaterial.GLASS, VoxelMaterial.GLASS_LIT, VoxelMaterial.LAB_WINDOW]:
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
