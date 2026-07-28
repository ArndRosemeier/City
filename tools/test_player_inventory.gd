## Inventory feature test: per-gem tallies, craft and stacking, the cut each gem icon is drawn
## with, and the slot previews the panel builds.
##
## The cuts are checked because the palette cannot carry the icons on its own: quartz and
## diamond are both near-white and amber and topaz both near-orange, and those colours are the
## ore in the hills, not the panel's to change. So the silhouettes have to stay six different
## shapes, and the preview material has to stay a copy of the world one.
##
## The preview half matters as much as the arithmetic. Every slot holds a Camera3D aimed at a
## mesh inside its own SubViewport, and all three ways that goes wrong — an aim that never
## happened, a preview outside the frame, a preview leaking into the game's World3D — leave
## the panel looking merely empty. So an engine Logger is armed while the panel builds and
## every error or warning it catches fails the run, and the framing is then checked by
## projecting the item through the slot camera it is supposed to face.
##
## Run: powershell -File tools\run_test.ps1 test_player_inventory
extends Node

## Distinct per-type tallies, so a count that leaks between gem types cannot pass.
const GEM_TALLIES: Array[int] = [7, 3, 11, 2, 40, 1]
## Slack for the aim: the slot camera must face the item, not nearly face it.
const AIM_DOT_MIN := 0.9999
## How far off the middle of the render target the item may project, in pixels.
const CENTER_TOLERANCE_PX := 5.0
## An item that projects smaller than this fraction of the target is an unreadable speck. A
## framed icon spans about 0.7 of it, and the trap icon shrinks to 0.72 of that on its pulse.
const MIN_FILL_FRAC := 0.3
## Corners must land inside the target with a pixel to spare, or the icon is clipped.
const EDGE_INSET_PX := 1.0
## The panel builds 25 SubViewports; a couple of frames lets them size and draw.
const SETTLE_FRAMES := 8


## Records what the engine reported while it was armed. Assertion noise from this test is
## kept out by only arming it around the panel build.
class ErrorSink:
	extends Logger

	var errors: PackedStringArray = PackedStringArray()
	var warnings: PackedStringArray = PackedStringArray()

	func _log_error(
		function: String,
		file: String,
		line: int,
		code: String,
		rationale: String,
		_editor_notify: bool,
		error_type: int,
		_script_backtraces: Array
	) -> void:
		var detail := rationale.strip_edges()
		if detail.is_empty():
			detail = code.strip_edges()
		var entry := "%s:%d %s(): %s" % [file, line, function, detail]
		if error_type == Logger.ERROR_TYPE_WARNING:
			warnings.append(entry)
		else:
			errors.append(entry)


var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	InventoryCatalog.ensure_loaded()
	_check_craft_and_stacking()
	_check_gem_tallies()
	_check_icons_spare_the_world_palette()
	_check_gem_icons_have_their_own_cut()
	await _check_panel_previews()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _check_craft_and_stacking() -> void:
	var inv := PlayerInventory.new()
	if inv.slot_count() != InventoryCatalog.SLOT_COUNT:
		_fail("FAIL slot_count want %d got %d" % [InventoryCatalog.SLOT_COUNT, inv.slot_count()])

	if inv.can_craft(InventoryCatalog.RECIPE_TRAP):
		_fail("FAIL empty inventory can craft trap")

	var left := inv.add(InventoryCatalog.ID_QUARTZ, 5)
	if left != 0:
		_fail("FAIL add 5 quartz leftover %d" % left)
	if inv.count_of(InventoryCatalog.ID_QUARTZ) != 5:
		_fail("FAIL quartz count want 5 got %d" % inv.count_of(InventoryCatalog.ID_QUARTZ))

	var slot0 := inv.slot_at(0)
	if str(slot0.get("id", "")) != InventoryCatalog.ID_QUARTZ or int(slot0.get("count", 0)) != 5:
		_fail("FAIL slot 0 should be 5 quartz: %s" % slot0)

	if not inv.can_craft(InventoryCatalog.RECIPE_TRAP):
		_fail("FAIL expected can_craft trap with 5 quartz")
	if not inv.craft(InventoryCatalog.RECIPE_TRAP):
		_fail("FAIL craft trap")
	if inv.count_of(InventoryCatalog.ID_QUARTZ) != 0:
		_fail("FAIL quartz should be spent, have %d" % inv.count_of(InventoryCatalog.ID_QUARTZ))
	if inv.count_of(InventoryCatalog.ID_TRAP) != 1:
		_fail("FAIL trap count want 1 got %d" % inv.count_of(InventoryCatalog.ID_TRAP))

	var found_trap := false
	for i in inv.slot_count():
		var s := inv.slot_at(i)
		if str(s.get("id", "")) == InventoryCatalog.ID_TRAP and int(s.get("count", 0)) == 1:
			found_trap = true
			break
	if not found_trap:
		_fail("FAIL trap not present in any slot")

	## Stacking: fill one stack to max then spill into the next.
	inv.clear()
	var max_stack := InventoryCatalog.item(InventoryCatalog.ID_QUARTZ).stack_max
	left = inv.add(InventoryCatalog.ID_QUARTZ, max_stack + 3)
	if left != 0:
		_fail("FAIL stack spill leftover %d" % left)
	if int(inv.slot_at(0).get("count", 0)) != max_stack:
		_fail("FAIL first stack not full")
	if int(inv.slot_at(1).get("count", 0)) != 3:
		_fail("FAIL spill stack want 3 got %s" % inv.slot_at(1))

	if InventoryCatalog.display_name(InventoryCatalog.ID_TRAP) != "Trap":
		_fail("FAIL trap display name")
	var recipe := InventoryCatalog.recipe(InventoryCatalog.RECIPE_TRAP)
	if int(recipe.inputs.get(InventoryCatalog.ID_QUARTZ, 0)) != 5:
		_fail("FAIL trap recipe inputs %s" % recipe.inputs)
	if recipe.output_id != InventoryCatalog.ID_TRAP:
		_fail("FAIL trap recipe output %s" % recipe.output_id)
	print("OK craft and stacking")


## What CityRoot.get_gem_count reads: one tally per GEM_* material, kept apart from the rest.
func _check_gem_tallies() -> void:
	var inv := PlayerInventory.new()
	var mats := _gem_materials()
	if mats.size() != GEM_TALLIES.size():
		_fail("FAIL %d gem materials but %d tallies" % [mats.size(), GEM_TALLIES.size()])
		return
	var seen: PackedStringArray = PackedStringArray()
	for i in mats.size():
		var item_id := InventoryCatalog.item_id_for_gem(mats[i])
		if item_id == "":
			_fail("FAIL gem material %d maps to no item" % mats[i])
			return
		if seen.has(item_id):
			_fail("FAIL gem material %d maps to '%s' again" % [mats[i], item_id])
			return
		seen.append(item_id)
		var over := inv.add(item_id, GEM_TALLIES[i])
		if over != 0:
			_fail("FAIL %d %s did not fit (%d left)" % [GEM_TALLIES[i], item_id, over])
	for i in mats.size():
		var item_id := InventoryCatalog.item_id_for_gem(mats[i])
		var have := inv.count_of(item_id)
		if have != GEM_TALLIES[i]:
			_fail("FAIL %s tally want %d got %d" % [item_id, GEM_TALLIES[i], have])

	## Spending one type must not touch the others.
	if not inv.remove(InventoryCatalog.ID_TOPAZ, 4):
		_fail("FAIL could not remove 4 topaz from %d" % inv.count_of(InventoryCatalog.ID_TOPAZ))
	for i in mats.size():
		var item_id := InventoryCatalog.item_id_for_gem(mats[i])
		var want := GEM_TALLIES[i] - (4 if item_id == InventoryCatalog.ID_TOPAZ else 0)
		var have := inv.count_of(item_id)
		if have != want:
			_fail("FAIL %s tally after topaz spend want %d got %d" % [item_id, want, have])
	print("OK per-gem tallies %s" % str(GEM_TALLIES))


## VoxelBlockLibrary hands out one shared cached material per gem id and the ore underground is
## drawn with it, so the icon look has to be a copy. Deriving it by editing would re-tune every
## gem seam in the world from the inventory panel. Runs before the panel builds, because the
## icon materials are cached on first use.
func _check_icons_spare_the_world_palette() -> void:
	for mat_id in _gem_materials():
		var world := VoxelBlockLibrary.gem_material(mat_id)
		var world_glow := float(world.get_shader_parameter("emission_base"))
		var icon := InventoryItemVisual.gem_icon_material(mat_id)
		if icon == world:
			_fail("FAIL gem %d icon is the world material itself" % mat_id)
			continue
		var after := float(world.get_shader_parameter("emission_base"))
		if not is_equal_approx(after, world_glow):
			_fail("FAIL gem %d world glow went %f → %f building its icon"
				% [mat_id, world_glow, after])
		if world.get_shader_parameter("base_color") != icon.get_shader_parameter("base_color"):
			_fail("FAIL gem %d icon drifted off the world palette" % mat_id)
		if float(icon.get_shader_parameter("emission_base")) >= world_glow:
			_fail("FAIL gem %d icon glow is not dimmed for a lit 64 px slot" % mat_id)
	print("OK %d gem icons copy the world palette without touching it" % _gem_materials().size())


## Two gems that draw the same silhouette are two gems the player cannot tell apart, which is
## exactly what six identical cubes were.
func _check_gem_icons_have_their_own_cut() -> void:
	var seen: Dictionary = {}  ## silhouette → the item that claimed it
	for mat_id in _gem_materials():
		var item_id := InventoryCatalog.item_id_for_gem(mat_id)
		var icon := InventoryItemVisual.make_mesh(item_id)
		if icon == null:
			_fail("FAIL %s has no icon mesh" % item_id)
			continue
		var verts: PackedVector3Array = icon.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var cut := "%s %v x%d" % [
			icon.mesh.get_class(),
			icon.mesh.get_aabb().size.snapped(Vector3.ONE * 0.001),
			verts.size(),
		]
		if seen.has(cut):
			_fail("FAIL %s and %s are cut the same: %s" % [seen[cut], item_id, cut])
		seen[cut] = item_id
		## The slot camera is placed to frame a sphere of bounding_radius(), so a cut that
		## reaches past it is a clipped icon at whatever yaw turns the far corner forward.
		var reach := 0.0
		for v in verts:
			reach = maxf(reach, v.length())
		if reach > InventoryItemVisual.bounding_radius():
			_fail("FAIL %s reaches %.3f, past the %.3f the slot camera frames"
				% [item_id, reach, InventoryItemVisual.bounding_radius()])
		icon.free()
	print("OK %d gem icons, %d distinct cuts" % [_gem_materials().size(), seen.size()])


## Builds the real panel over a stocked inventory and judges what each slot would draw.
func _check_panel_previews() -> void:
	var inv := PlayerInventory.new()
	var mats := _gem_materials()
	for i in mats.size():
		inv.add(InventoryCatalog.item_id_for_gem(mats[i]), GEM_TALLIES[i])
	inv.add(InventoryCatalog.ID_TRAP, 2)
	var occupied := mats.size() + 1

	var sink := ErrorSink.new()
	OS.add_logger(sink)
	var panel := PlayerInventoryPanel.new()
	panel.name = "PlayerInventory"
	add_child(panel)
	panel.bind_inventory(inv)
	panel.open_panel()
	for _i in range(SETTLE_FRAMES):
		await get_tree().process_frame
	OS.remove_logger(sink)

	for msg in sink.errors:
		_fail("FAIL engine error while the panel built: %s" % msg)
	for msg in sink.warnings:
		_fail("FAIL engine warning while the panel built: %s" % msg)
	if not panel.is_open():
		_fail("FAIL panel did not open")

	var world := get_viewport().find_world_3d()
	var filled := 0
	for i in InventoryCatalog.SLOT_COUNT:
		var mesh := panel.slot_mesh(i)
		if i >= occupied:
			if mesh != null:
				_fail("FAIL slot %d is empty but holds a preview" % i)
			continue
		if mesh == null:
			_fail("FAIL slot %d holds an item but no preview" % i)
			continue
		filled += 1
		_check_slot(panel, i, mesh, world)
	if filled != occupied:
		_fail("FAIL %d slots previewed, expected %d" % [filled, occupied])
	panel.close_panel()
	print("OK %d slot previews framed by their own camera" % filled)


func _check_slot(
	panel: PlayerInventoryPanel, index: int, mesh: MeshInstance3D, game: World3D
) -> void:
	var vp := panel.slot_viewport(index)
	if vp.find_world_3d() == game:
		_fail("FAIL slot %d previews into the game world" % index)
		return
	if not mesh.is_visible_in_tree():
		_fail("FAIL slot %d preview is hidden" % index)
		return
	if mesh.mesh == null:
		_fail("FAIL slot %d preview has no mesh" % index)
		return

	var cam := panel.slot_camera(index)
	var eye := PlayerInventoryPanel.slot_camera_position()
	if cam.global_position.distance_to(eye) > 0.001:
		_fail("FAIL slot %d camera at %s, expected %s" % [index, cam.global_position, eye])
		return
	var aim := (-cam.global_transform.basis.z).dot(eye.direction_to(mesh.global_position))
	if aim < AIM_DOT_MIN:
		_fail("FAIL slot %d camera aim off item by dot %.6f" % [index, aim])
		return

	var target := Vector2(vp.size)
	var box := mesh.get_aabb()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for corner in range(8):
		var at := mesh.global_transform * box.get_endpoint(corner)
		var px := cam.unproject_position(at)
		lo = lo.min(px)
		hi = hi.max(px)
	if lo.x < EDGE_INSET_PX or lo.y < EDGE_INSET_PX:
		_fail("FAIL slot %d preview clipped at %s of %s" % [index, lo, target])
		return
	if hi.x > target.x - EDGE_INSET_PX or hi.y > target.y - EDGE_INSET_PX:
		_fail("FAIL slot %d preview clipped at %s of %s" % [index, hi, target])
		return
	var span := hi - lo
	if span.x < target.x * MIN_FILL_FRAC or span.y < target.y * MIN_FILL_FRAC:
		_fail("FAIL slot %d preview only spans %s of %s" % [index, span, target])
		return
	var off := (lo + hi) * 0.5 - target * 0.5
	if off.length() > CENTER_TOLERANCE_PX:
		_fail("FAIL slot %d preview sits %.1f px off centre" % [index, off.length()])


func _gem_materials() -> Array[int]:
	var out: Array[int] = []
	for mat_id in range(VoxelMaterial.GEM_QUARTZ, VoxelMaterial.GEM_DIAMOND + 1):
		out.append(mat_id)
	return out
