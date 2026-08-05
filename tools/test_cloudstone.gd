## Cloudstone craft, build stamp cost, and gravity-buff stack timing.
##
## Run: powershell -File tools\run_test.ps1 test_cloudstone
extends Node

const PlayerInventoryScript := preload("res://scripts/city/player_inventory.gd")
const PlayerLoadoutScript := preload("res://scripts/city/player_loadout.gd")
const CityWalkerScript := preload("res://scripts/city/city_walker.gd")
const CityAudioScript := preload("res://scripts/city/city_audio.gd")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog()
	_test_adventure_locked()
	_test_craft_and_consume_fields()
	_test_gravity_stacks()
	await _test_cloud_wobble_audio()
	print("RESULT: OK")
	get_tree().quit(0)


func _fail(msg: String) -> void:
	push_error(msg)
	print(msg)
	get_tree().quit(1)


func _test_catalog() -> void:
	var item := InventoryCatalog.item(InventoryCatalog.ID_CLOUDSTONE)
	if item == null or not item.is_cloudstone:
		_fail("FAIL cloudstone item missing or unflagged")
		return
	var craft := InventoryCatalog.recipe(InventoryCatalog.RECIPE_CLOUDSTONE)
	if craft == null or craft.output_id != InventoryCatalog.ID_CLOUDSTONE:
		_fail("FAIL cloudstone craft recipe missing")
		return
	if int(craft.inputs.get(InventoryCatalog.ID_AMBER, 0)) != 2:
		_fail("FAIL cloudstone craft should cost 2 amber")
		return
	var build := BuildCatalog.by_id("cloudstone")
	if build == null:
		_fail("FAIL cloudstone build recipe missing")
		return
	if build.consume_item != InventoryCatalog.ID_CLOUDSTONE or build.consume_count != 1:
		_fail("FAIL cloudstone build must consume one inventory charge")
		return
	if build.voxels.size() != 4 or build.voxels[3] != VoxelMaterial.CLOUDSTONE:
		_fail("FAIL cloudstone build must stamp CLOUDSTONE mat")
		return
	if VoxelMaterial.color(VoxelMaterial.CLOUDSTONE).r < 0.5:
		_fail("FAIL cloudstone colour looks wrong")
		return
	var spec := VoxelSurfaceSpec.for_id(VoxelMaterial.CLOUDSTONE)
	if spec.kind != VoxelSurfaceSpec.Kind.CLOUDSTONE:
		_fail("FAIL cloudstone surface kind")
		return
	var shader := load("res://assets/city/shaders/voxel_cloudstone.gdshader") as Shader
	if shader == null:
		_fail("FAIL cloudstone shader missing")
		return
	var mat := VoxelBlockLibrary.surface_material(VoxelMaterial.CLOUDSTONE, false)
	if mat == null or mat.shader == null:
		_fail("FAIL cloudstone block material")
		return
	var lib := VoxelBlockLibrary.build()
	var model := lib.get_model(VoxelMaterial.CLOUDSTONE)
	if model == null or not (model is VoxelBlockyModelMesh):
		_fail("FAIL cloudstone should use a custom mesh model")
		return
	var mesh_model := model as VoxelBlockyModelMesh
	if mesh_model.mesh == null or mesh_model.mesh.get_surface_count() < 1:
		_fail("FAIL cloudstone mesh is empty")
		return
	## Cube would be a single surface with 24 verts; the puff is many overlapping lobes.
	var arrays := mesh_model.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.size() < 200:
		_fail("FAIL cloudstone mesh looks too simple (%d verts)" % verts.size())
		return
	var icon := InventoryItemVisual.make_mesh(InventoryCatalog.ID_CLOUDSTONE)
	if icon == null:
		_fail("FAIL cloudstone inventory icon")
		return
	icon.queue_free()


func _test_adventure_locked() -> void:
	var loadout: PlayerLoadout = PlayerLoadoutScript.new() as PlayerLoadout
	loadout.reset_adventure()
	if loadout.knows_recipe(InventoryCatalog.RECIPE_CLOUDSTONE):
		_fail("FAIL adventure must not start knowing cloudstone craft")
		return
	if not loadout.learn_recipe(InventoryCatalog.RECIPE_CLOUDSTONE):
		_fail("FAIL learn cloudstone craft")
		return
	if not loadout.knows_recipe(InventoryCatalog.RECIPE_CLOUDSTONE):
		_fail("FAIL cloudstone craft not known after learn")
		return


func _test_craft_and_consume_fields() -> void:
	var inv: PlayerInventory = PlayerInventoryScript.new() as PlayerInventory
	inv.add(InventoryCatalog.ID_AMBER, 4)
	if not inv.craft(InventoryCatalog.RECIPE_CLOUDSTONE):
		_fail("FAIL craft cloudstone from amber")
		return
	if inv.count_of(InventoryCatalog.ID_CLOUDSTONE) != 1:
		_fail("FAIL craft output count")
		return
	if inv.count_of(InventoryCatalog.ID_AMBER) != 2:
		_fail("FAIL amber spend on cloudstone craft")
		return
	if not inv.craft(InventoryCatalog.RECIPE_CLOUDSTONE):
		_fail("FAIL second cloudstone craft")
		return
	if inv.count_of(InventoryCatalog.ID_CLOUDSTONE) != 2:
		_fail("FAIL stacked cloudstone charges")
		return
	if not inv.remove(InventoryCatalog.ID_CLOUDSTONE, 1):
		_fail("FAIL remove cloudstone charge")
		return
	if inv.count_of(InventoryCatalog.ID_CLOUDSTONE) != 1:
		_fail("FAIL cloudstone charge after remove")
		return


func _test_gravity_stacks() -> void:
	var walker: CityWalker = CityWalkerScript.new() as CityWalker
	add_child(walker)
	var base_g := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	if not is_equal_approx(walker._effective_gravity(), base_g):
		_fail("FAIL zero stacks should leave gravity alone")
		return
	walker._cloud_stacks = 5
	if not is_equal_approx(walker._effective_gravity(), base_g * 0.0):
		_fail("FAIL 5 stacks should zero gravity (5 * 0.2g)")
		return
	walker._cloud_stacks = 10
	if walker._effective_gravity() >= 0.0:
		_fail("FAIL 10 stacks should invert gravity")
		return
	if not is_equal_approx(walker._effective_gravity(), base_g * -1.0):
		_fail("FAIL 10 stacks should be -1.0 * g")
		return
	walker._cloud_stacks = 0
	if not is_equal_approx(walker._cloud_speed_mul(), 1.0):
		_fail("FAIL zero stacks should leave speed alone")
		return
	walker._cloud_stacks = 3
	if not is_equal_approx(walker._cloud_speed_mul(), 1.3):
		_fail("FAIL 3 stacks should be +30% speed")
		return
	walker._cloud_stacks = 10
	if not is_equal_approx(walker._cloud_speed_mul(), 2.0):
		_fail("FAIL 10 stacks should double speed")
		return
	walker.queue_free()


func _test_cloud_wobble_audio() -> void:
	var audio: CityAudio = CityAudioScript.new() as CityAudio
	audio.name = "CloudAudio"
	add_child(audio)
	## _ready loads banks; give one frame for the player node to exist.
	await get_tree().process_frame
	if not audio.has_method("set_cloud_buff_wobble"):
		_fail("FAIL CityAudio missing set_cloud_buff_wobble")
		audio.queue_free()
		return
	audio.call("set_cloud_buff_wobble", 3)
	var player := audio.get_node_or_null("CloudBuffWobble") as AudioStreamPlayer
	if player == null or not player.playing:
		_fail("FAIL cloud wobble should play while stacks > 0")
		audio.queue_free()
		return
	if player.volume_db > -12.0:
		_fail("FAIL cloud wobble should stay soft (volume_db=%s)" % player.volume_db)
		audio.queue_free()
		return
	audio.call("set_cloud_buff_wobble", 0)
	if player.playing:
		_fail("FAIL cloud wobble should stop at zero stacks")
		audio.queue_free()
		return
	audio.queue_free()
