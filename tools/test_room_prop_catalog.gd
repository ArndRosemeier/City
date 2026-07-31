## The prop kit as a whole: every catalog entry has a mesh on disk, the ids are one
## contiguous run, the two material tables agree with the catalog, every family resolves to
## a surface, and the whole id space still fits inside the byte the navigation pipeline
## reads. The last one is the load-bearing check — overflowing it bakes a city with no
## navigation in it and nothing else complains.
##
## The catalog is generated (tools/gen_room_prop_catalog.py), so this is a check on the
## generator's output as committed, not on hand-written data.
##
## Run: powershell -File tools\run_test.ps1 test_room_prop_catalog
extends Node

const VoxelBlockLibraryScript := preload("res://scripts/city/voxel_block_library.gd")
const NavSolidityScript := preload("res://scripts/city/nav_solidity.gd")

## Widest a prop may be in any axis. The generator caps footprints at 8 cells; anything
## larger is a scale anchor that slipped, and it would claim half a room.
const MAX_AXIS := 8

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_check_ids()
	_check_meshes()
	_check_material_tables()
	_check_families()
	_check_nav_budget()
	_check_walk_through_collision()
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
		return
	print("RESULT: OK")
	get_tree().quit(0)


## The ids are positional — `PROP_FIRST + index` — so a catalog whose bounds disagree with
## its own entry count silently renames every prop past the gap.
func _check_ids() -> void:
	var n := RoomPropCatalog.ENTRIES.size()
	if n != RoomPropCatalog.PROP_COUNT:
		_fail(
			"FAIL the catalog lists %d entries but says PROP_COUNT=%d"
			% [n, RoomPropCatalog.PROP_COUNT]
		)
		return
	if RoomPropCatalog.PROP_LAST != RoomPropCatalog.PROP_FIRST + n - 1:
		_fail(
			"FAIL ids %d..%d are not %d contiguous entries"
			% [RoomPropCatalog.PROP_FIRST, RoomPropCatalog.PROP_LAST, n]
		)
		return
	var seen: Dictionary[String, bool] = {}
	for i in range(n):
		var stem := String(RoomPropCatalog.ENTRIES[i]["stem"])
		if stem.is_empty():
			_fail("FAIL catalog entry %d has no stem" % i)
			return
		if seen.has(stem):
			_fail("FAIL two catalog entries are called %s" % stem)
			return
		seen[stem] = true
		var id := RoomPropCatalog.PROP_FIRST + i
		if RoomPropCatalog.find_stem(stem) != id:
			_fail(
				"FAIL %s is entry %d but the stem index resolves it to %d"
				% [stem, id, RoomPropCatalog.find_stem(stem)]
			)
			return
		if not RoomPropCatalog.is_prop_id(id):
			_fail("FAIL id %d of %s is outside the catalog's own range" % [id, stem])
			return
	print("ids: %d props, %d..%d" % [n, RoomPropCatalog.PROP_FIRST, RoomPropCatalog.PROP_LAST])


## A stem without an `.obj` bakes an invisible prop that still blocks the room.
func _check_meshes() -> void:
	var rotated := 0
	var biggest := Vector3i.ONE
	for i in range(RoomPropCatalog.ENTRIES.size()):
		var id := RoomPropCatalog.PROP_FIRST + i
		var stem := RoomPropCatalog.stem_of(id)
		var path := RoomPropCatalog.mesh_path(id)
		if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
			_fail("FAIL %s has no mesh at %s" % [stem, path])
			return
		var size := RoomPropCatalog.size_of_id(id)
		if size.x < 1 or size.y < 1 or size.z < 1:
			_fail("FAIL %s has a footprint of %s" % [stem, size])
			return
		if maxi(size.x, maxi(size.y, size.z)) > MAX_AXIS:
			_fail("FAIL %s is %s cells — the cap is %d per axis" % [stem, size, MAX_AXIS])
			return
		if size.x * size.y * size.z > biggest.x * biggest.y * biggest.z:
			biggest = size
		if not stem.ends_with(RoomPropCatalog.ROT_SUFFIX):
			continue
		rotated += 1
		## A turned twin is the same mesh a quarter turn round Y, so its footprint has to
		## be the original's with X and Z swapped. Anything else is a different prop.
		var base := stem.trim_suffix(RoomPropCatalog.ROT_SUFFIX)
		if not RoomPropCatalog.has_stem(base):
			_fail("FAIL %s is a turned twin of %s, which is not in the catalog" % [stem, base])
			return
		var from := RoomPropCatalog.size_of_stem(base)
		if size != Vector3i(from.z, from.y, from.x):
			_fail("FAIL %s is %s, but %s is %s turned" % [stem, size, base, from])
			return
	print(
		"meshes: every stem has an .obj, %d turned twins, biggest footprint %s"
		% [rotated, biggest]
	)


## `VoxelMaterial` and the Rust `materials.rs` are patched by the generator from the same
## run that wrote the catalog. When they drift, GDScript and native disagree about what a
## voxel id means and the mismatch shows up as scenery in the wrong place.
func _check_material_tables() -> void:
	if VoxelMaterial.PROP_FIRST != RoomPropCatalog.PROP_FIRST:
		_fail(
			"FAIL VoxelMaterial.PROP_FIRST=%d, the catalog starts at %d"
			% [VoxelMaterial.PROP_FIRST, RoomPropCatalog.PROP_FIRST]
		)
		return
	if VoxelMaterial.PROP_LAST != RoomPropCatalog.PROP_LAST:
		_fail(
			"FAIL VoxelMaterial.PROP_LAST=%d, the catalog ends at %d"
			% [VoxelMaterial.PROP_LAST, RoomPropCatalog.PROP_LAST]
		)
		return
	if VoxelMaterial.PROP_FOOTPRINT != VoxelMaterial.PROP_LAST + 1:
		_fail(
			"FAIL PROP_FOOTPRINT=%d sits on a prop id" % VoxelMaterial.PROP_FOOTPRINT
		)
		return
	if VoxelMaterial.DOOR != VoxelMaterial.PROP_FOOTPRINT + 1:
		_fail("FAIL DOOR=%d is not the id after PROP_FOOTPRINT" % VoxelMaterial.DOOR)
		return
	if VoxelMaterial.ARENA_SHELL != VoxelMaterial.DOOR + 1:
		_fail(
			"FAIL ARENA_SHELL=%d is not the id after DOOR=%d"
			% [VoxelMaterial.ARENA_SHELL, VoxelMaterial.DOOR]
		)
		return
	if VoxelMaterial.LOS_VEIL != VoxelMaterial.ARENA_SHELL + 1:
		_fail(
			"FAIL LOS_VEIL=%d is not the id after ARENA_SHELL=%d"
			% [VoxelMaterial.LOS_VEIL, VoxelMaterial.ARENA_SHELL]
		)
		return
	if VoxelMaterial.BRANCH_X != VoxelMaterial.LOS_VEIL + 1:
		_fail(
			"FAIL BRANCH_X=%d is not the id after LOS_VEIL=%d"
			% [VoxelMaterial.BRANCH_X, VoxelMaterial.LOS_VEIL]
		)
		return
	if VoxelMaterial.BRANCH_Z != VoxelMaterial.BRANCH_X + 1:
		_fail(
			"FAIL BRANCH_Z=%d is not the id after BRANCH_X=%d"
			% [VoxelMaterial.BRANCH_Z, VoxelMaterial.BRANCH_X]
		)
		return
	if VoxelMaterial.LEAVES_DARK != VoxelMaterial.BRANCH_Z + 1:
		_fail(
			"FAIL LEAVES_DARK=%d is not the id after BRANCH_Z=%d"
			% [VoxelMaterial.LEAVES_DARK, VoxelMaterial.BRANCH_Z]
		)
		return
	if VoxelMaterial.COUNT != VoxelMaterial.LEAVES_DARK + 1:
		_fail(
			"FAIL COUNT=%d leaves a gap after LEAVES_DARK=%d"
			% [VoxelMaterial.COUNT, VoxelMaterial.LEAVES_DARK]
		)
		return
	if VoxelMaterial.is_destructible(VoxelMaterial.ARENA_SHELL):
		_fail("FAIL ARENA_SHELL must not be destructible")
		return
	if VoxelMaterial.is_destructible(VoxelMaterial.LOS_VEIL):
		_fail("FAIL LOS_VEIL must not be destructible")
		return
	var rs := FileAccess.get_file_as_string("res://native/city_voxel/src/materials.rs")
	if rs.is_empty():
		_fail("FAIL could not read native/city_voxel/src/materials.rs")
		return
	for pair: Array in [
		["PROP_FIRST", VoxelMaterial.PROP_FIRST],
		["PROP_LAST", VoxelMaterial.PROP_LAST],
		["PROP_FOOTPRINT", VoxelMaterial.PROP_FOOTPRINT],
		["DOOR", VoxelMaterial.DOOR],
		["ARENA_SHELL", VoxelMaterial.ARENA_SHELL],
		["LOS_VEIL", VoxelMaterial.LOS_VEIL],
		["BRANCH_X", VoxelMaterial.BRANCH_X],
		["BRANCH_Z", VoxelMaterial.BRANCH_Z],
		["LEAVES_DARK", VoxelMaterial.LEAVES_DARK],
		["COUNT", VoxelMaterial.COUNT],
		["TIMBER", VoxelMaterial.TIMBER],
	]:
		var want := "pub const %s: i32 = %d;" % [pair[0], int(pair[1])]
		if not rs.contains(want):
			_fail("FAIL materials.rs does not say `%s` — regenerate the catalog" % want)
			return
	print(
		(
			"tables: props %d..%d, footprint %d, door %d, arena_shell %d, los_veil %d, "
			+ "branch %d..%d, leaves_dark %d, count %d, agreed with materials.rs"
		)
		% [
			VoxelMaterial.PROP_FIRST,
			VoxelMaterial.PROP_LAST,
			VoxelMaterial.PROP_FOOTPRINT,
			VoxelMaterial.DOOR,
			VoxelMaterial.ARENA_SHELL,
			VoxelMaterial.LOS_VEIL,
			VoxelMaterial.BRANCH_X,
			VoxelMaterial.BRANCH_Z,
			VoxelMaterial.LEAVES_DARK,
			VoxelMaterial.COUNT,
		]
	)


## Every prop needs a surface to be drawn with. A family the spec table has never heard of
## falls through to the wood default, which is how a wrought iron railing ends up looking
## like a fence post.
func _check_families() -> void:
	var known: Array[String] = [
		"wood", "timber", "fabric", "metal", "ceramic", "foliage", "iron", "stone"
	]
	var per_family: Dictionary[String, int] = {}
	for i in range(RoomPropCatalog.ENTRIES.size()):
		var id := RoomPropCatalog.PROP_FIRST + i
		var family := RoomPropCatalog.family_of(id)
		if not known.has(family):
			_fail(
				"FAIL %s is family '%s', which no surface spec covers"
				% [RoomPropCatalog.stem_of(id), family]
			)
			return
		per_family[family] = per_family.get(family, 0) + 1
		var spec := VoxelSurfaceSpec.for_id(id)
		if spec == null or spec.albedo_file.is_empty():
			_fail("FAIL %s (%s) resolves to no albedo" % [RoomPropCatalog.stem_of(id), family])
			return
	var parts: Array[String] = []
	for f: String in known:
		parts.append("%s %d" % [f, per_family.get(f, 0)])
	print("families: %s" % ", ".join(parts))


## Nav tables track VoxelMaterial.COUNT (16-bit capable). Props must stay inside that palette.
func _check_nav_budget() -> void:
	if NavSolidityScript.TABLE_SIZE != VoxelMaterial.COUNT:
		_fail(
			"FAIL NavSolidity.TABLE_SIZE=%d must equal VoxelMaterial.COUNT=%d"
			% [NavSolidityScript.TABLE_SIZE, VoxelMaterial.COUNT]
		)
		return
	var lib := VoxelBlockLibraryScript.build()
	var models: Array = lib.models
	if models.size() < VoxelMaterial.COUNT:
		_fail(
			"FAIL the block library has %d models for %d materials"
			% [models.size(), VoxelMaterial.COUNT]
		)
		return
	var sol: NavSolidity = NavSolidityScript.build(lib)
	var walkable := 0
	for i in range(RoomPropCatalog.ENTRIES.size()):
		var id := RoomPropCatalog.PROP_FIRST + i
		if sol.is_traversable(id) != RoomPropCatalog.walk_through_of(id):
			_fail(
				"FAIL %s is walk_through=%s in the catalog and %s to nav"
				% [
					RoomPropCatalog.stem_of(id),
					RoomPropCatalog.walk_through_of(id),
					sol.kind_name(id),
				]
			)
			return
		if sol.is_traversable(id):
			walkable += 1
	print(
		"nav: palette %d ids (16-bit), %d props a body walks through"
		% [VoxelMaterial.COUNT, walkable]
	)


## Walk-through ground decor must not carry collision AABBs, and multi-cell stamps must
## not leave solid PROP_FOOTPRINT siblings (that was how tall flowers snagged walkers).
func _check_walk_through_collision() -> void:
	var lib := VoxelBlockLibraryScript.build()
	var models: Array = lib.models
	var checked := 0
	for i in range(RoomPropCatalog.ENTRIES.size()):
		var id := RoomPropCatalog.PROP_FIRST + i
		if not RoomPropCatalog.walk_through_of(id):
			continue
		checked += 1
		if id >= models.size():
			_fail("FAIL walk-through %s has no library model" % RoomPropCatalog.stem_of(id))
			return
		var model: VoxelBlockyModel = models[id]
		if model.collision_aabbs.size() > 0:
			_fail(
				"FAIL %s is walk_through but has %d collision AABBs"
				% [RoomPropCatalog.stem_of(id), model.collision_aabbs.size()]
			)
			return
	var brush := CityBrush.new(null, Vector3i.ZERO)
	brush.use_offline_volume()
	## Tall flower (2 cells high) and wide grass — both used to leave colliding footprints.
	for stem: String in ["flower_redA", "grass", "rock_smallA"]:
		var origin := Vector3i(4, 2, 4)
		if not RoomPropKit.stamp_brush(brush, origin, stem):
			_fail("FAIL could not stamp walk-through %s for footprint check" % stem)
			return
		var size := RoomPropCatalog.size_of_stem(stem)
		for y in range(size.y):
			for z in range(size.z):
				for x in range(size.x):
					var at := origin + Vector3i(x, y, z)
					var id2 := brush.get_vox(at)
					if Vector3i(x, y, z) == Vector3i.ZERO:
						continue
					if id2 == VoxelMaterial.PROP_FOOTPRINT:
						_fail(
							"FAIL %s wrote a solid PROP_FOOTPRINT at offset %s"
							% [stem, Vector3i(x, y, z)]
						)
						return
					if id2 != VoxelMaterial.AIR:
						_fail(
							"FAIL %s left non-air %d at offset %s (want air siblings)"
							% [stem, id2, Vector3i(x, y, z)]
						)
						return
		## Clear for the next stamp.
		brush.destroy_vox(origin)
	print("walk-through: %d props collision-free; multi-cell stamps leave no footprint solids" % checked)
