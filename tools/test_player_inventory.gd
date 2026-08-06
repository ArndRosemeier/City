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


## Stands in for CityRoot so the panel can be shown a half-learned cookbook. The panel asks
## whatever is in the "city_root" group these three questions and nothing else.
class HalfLearnedCity:
	extends Node

	var recipes: PackedStringArray = PackedStringArray()
	var schematics: PackedStringArray = PackedStringArray()

	func knows_recipe(recipe_id: String) -> bool:
		return recipes.has(recipe_id)

	func knows_ability_schematic(ability_id: String) -> bool:
		return schematics.has(ability_id)

	func can_use_ability(_ability_id: String) -> bool:
		return false


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
var _reference: Vector2 = Vector2.ZERO


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	InventoryCatalog.ensure_loaded()
	_check_craft_and_stacking()
	_check_gem_tallies()
	_check_icons_spare_the_world_palette()
	_check_icons_have_their_own_cut()
	await _check_panel_previews()
	await _check_locked_recipes_stay_nameless()
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


## Two things that draw the same silhouette are two things the player cannot tell apart, which
## is exactly what six identical cubes were. Items and power badges share one tally because they
## share one column: a recipe row shows the badge of whatever it builds, so a stone and a power
## can now sit a row apart. The sweep runs over the whole catalog and the whole registry rather
## than the gems alone — an item added without an icon used to reach the panel and only fail
## there, at the moment the player crafted it.
func _check_icons_have_their_own_cut() -> void:
	var seen: Dictionary = {}  ## silhouette → the thing that claimed it
	var item_ids := InventoryCatalog.all_item_ids()
	for item_id in item_ids:
		_check_icon(item_id, InventoryItemVisual.make_mesh(item_id), seen)
	var ability_ids := _badged_ability_ids()
	for ability_id in ability_ids:
		_check_icon(ability_id, AbilityIconVisual.make_mesh(ability_id), seen)
	print("OK %d item icons and %d power badges, %d distinct cuts"
		% [item_ids.size(), ability_ids.size(), seen.size()])


## Everything the tray or the unlock list can show. Builds are placed in the world and have no
## badge of their own.
func _badged_ability_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for def in AbilityRegistry.all_defs():
		if def.kind == AbilityRegistry.KIND_BUILD:
			continue
		out.append(def.id)
	return out


func _check_icon(id: String, icon: MeshInstance3D, seen: Dictionary) -> void:
	if icon == null:
		_fail("FAIL %s has no icon mesh" % id)
		return
	if icon.material_override == null:
		_fail("FAIL %s has an icon mesh but no material" % id)
	var arrays: Array = icon.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	_check_solid_is_right_way_out(id, arrays)
	var cut := _silhouette(icon.mesh, verts)
	if seen.has(cut):
		_fail("FAIL %s and %s are cut the same: %s" % [seen[cut], id, cut])
	seen[cut] = id
	## The slot camera is placed to frame a sphere of bounding_radius(), so a cut that reaches
	## past it is a clipped icon at whatever yaw turns the far corner forward. The radius is
	## derived from the full PREVIEW_SIZE cube, which the trap is, so its corners land exactly
	## on the sphere — the tolerance is float noise, not slack.
	var reach := 0.0
	for v in verts:
		reach = maxf(reach, v.length())
	if reach > InventoryItemVisual.bounding_radius() + 0.0005:
		_fail("FAIL %s reaches %.3f, past the %.3f the slot camera frames"
			% [id, reach, InventoryItemVisual.bounding_radius()])
	icon.free()


## Box and vertex count alone would call two mirrored shapes the same cut, and the grow and
## shrink badges are exactly that pair, so the positions themselves are folded in.
func _silhouette(mesh: Mesh, verts: PackedVector3Array) -> String:
	var fold := 0.0
	for i in range(verts.size()):
		var v := verts[i]
		fold += (v.x * 3.7 + v.y * 11.3 + v.z * 29.1) * float(i + 1)
	return "%s %v x%d #%d" % [
		mesh.get_class(),
		mesh.get_aabb().size.snapped(Vector3.ONE * 0.001),
		verts.size(),
		int(roundf(fold * 100.0)),
	]


## An icon wound the wrong way round is not an error anywhere — it is a slot that renders empty,
## because every face the camera can see is culled.
##
## The test is the enclosed volume, which is positive for a solid wound outward and negative for
## one turned inside out, plus a check that the shading normals agree with that winding. Both are
## measured against a cut the panel is already known to draw, rather than against a hand-picked
## sign convention: the badges are assembled from several primitives sitting away from the
## origin, so "normals lean away from the middle" — true of a single gem — is not true of them.
func _check_solid_is_right_way_out(id: String, arrays: Array) -> void:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if normals.size() != verts.size():
		_fail("FAIL %s icon has %d normals for %d vertices" % [id, normals.size(), verts.size()])
		return
	var facing := _facing(arrays)
	if absf(facing.x) < 1e-7:
		_fail("FAIL %s icon encloses nothing — it is not a closed solid" % id)
		return
	var want := _reference_facing()
	if signf(facing.x) != signf(want.x):
		_fail("FAIL %s icon is wound inside out (volume %.5f)" % [id, facing.x])
	if signf(facing.y) != signf(want.y) or absf(facing.y) < 0.5:
		_fail("FAIL %s icon shades against its winding (agreement %.2f)" % [id, facing.y])


## Signed volume of the surface and how well its normals agree with its winding.
func _facing(arrays: Array) -> Vector2:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	## Hand-built cuts hand back a plain vertex run with no index array at all.
	var raw_index: Variant = arrays[Mesh.ARRAY_INDEX]
	var index: PackedInt32Array = (
		PackedInt32Array() if raw_index == null else raw_index as PackedInt32Array
	)
	var tri_count := (index.size() if index.size() > 0 else verts.size()) / 3
	var volume := 0.0
	var agree := 0.0
	var counted := 0
	for t in range(tri_count):
		var i0 := index[t * 3] if index.size() > 0 else t * 3
		var i1 := index[t * 3 + 1] if index.size() > 0 else t * 3 + 1
		var i2 := index[t * 3 + 2] if index.size() > 0 else t * 3 + 2
		var a := verts[i0]
		var b := verts[i1]
		var c := verts[i2]
		volume += a.cross(b).dot(c) / 6.0
		var face := (b - a).cross(c - a)
		if face.length_squared() < 1e-12:
			## Degenerate sliver, as a lathe or a cone leaves at its poles.
			continue
		var shaded := (normals[i0] + normals[i1] + normals[i2])
		if shaded.length_squared() < 1e-12:
			continue
		agree += face.normalized().dot(shaded.normalized())
		counted += 1
	return Vector2(volume, 0.0 if counted == 0 else agree / float(counted))


## The trap cube: the plainest icon in the panel and one the slot previews are already proven to
## draw, so whichever way round it is wound is the way round the rest have to be.
func _reference_facing() -> Vector2:
	if _reference == Vector2.ZERO:
		var icon := InventoryItemVisual.make_mesh(InventoryCatalog.ID_TRAP)
		_reference = _facing(icon.mesh.surface_get_arrays(0))
		icon.free()
	return _reference


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
	_check_recipe_column_scrolls(panel)
	await _check_close_button(panel)
	if panel.is_open():
		panel.close_panel()
	print("OK %d slot previews framed by their own camera" % filled)


## With no CityRoot the panel shows the whole cookbook — three crafts plus a schematic for every
## gated power — which is taller than the modal. That column used to run off the bottom edge with
## no way to reach the rows below the fold.
func _check_recipe_column_scrolls(panel: PlayerInventoryPanel) -> void:
	var scroll := panel.recipe_scroll()
	var list := panel.recipe_list()
	if scroll == null or list == null:
		_fail("FAIL the recipe column has no scroller")
		return
	if list.get_parent() != scroll:
		_fail("FAIL the recipe list is not inside the scroller")
		return
	var rows := list.get_child_count()
	if rows < 4:
		_fail("FAIL only %d recipe rows built; expected the full cookbook" % rows)
		return
	var content_h := list.size.y
	var visible_h := scroll.size.y
	if content_h <= visible_h:
		## Nothing is hidden, so there is nothing to scroll to and no bar to demand.
		print("OK recipe column fits: %d rows in %.0f px" % [rows, visible_h])
		return
	var bar := scroll.get_v_scroll_bar()
	if bar == null or not bar.visible:
		_fail("FAIL %d recipe rows overflow %.0f px with no scrollbar" % [rows, visible_h])
		return
	scroll.scroll_vertical = int(content_h)
	var reached := float(scroll.scroll_vertical) + visible_h
	if reached < content_h - 1.0:
		_fail("FAIL scrolling reaches %.0f px of %.0f px of recipes" % [reached, content_h])
	scroll.scroll_vertical = 0
	print("OK %d recipe rows scroll: %.0f px of content in %.0f px" % [rows, content_h, visible_h])


## A recipe the run has not found is a blank box, not a greyed-out row with its name still on
## it: the column may say how much is left out there, never what it is. Checked against a
## half-learned cookbook, because with no CityRoot the panel shows the whole book and a leak
## would look exactly like the normal case.
func _check_locked_recipes_stay_nameless() -> void:
	var city := HalfLearnedCity.new()
	city.name = "FakeCityRoot"
	city.recipes.append(InventoryCatalog.RECIPE_TRAP)
	city.schematics.append(AbilityRegistry.ID_LASER)
	city.add_to_group("city_root")
	add_child(city)

	var panel := PlayerInventoryPanel.new()
	panel.name = "HalfLearnedPanel"
	add_child(panel)
	panel.bind_inventory(PlayerInventory.new())
	panel.open_panel()
	for _i in range(SETTLE_FRAMES):
		await get_tree().process_frame

	var total := (
		InventoryCatalog.craft_recipes().size()
		+ AbilityRegistry.unlockable_defs().size()
		+ InventoryCatalog.build_discovery_recipes().size()
	)
	var rows := panel.recipe_rows()
	var locked := panel.locked_box_count()
	if rows.size() != 2:
		_fail("FAIL %d rows shown for a cookbook of 2 learned entries" % rows.size())
	if locked != total - 2:
		_fail("FAIL %d locked boxes for %d undiscovered recipes" % [locked, total - 2])
	for row in rows:
		if row.preview.current_mesh() == null:
			_fail("FAIL learned row '%s' shows no badge" % row.id)

	var shown := _column_text(panel.recipe_list())
	for recipe in InventoryCatalog.craft_recipes():
		if recipe.id == InventoryCatalog.RECIPE_TRAP:
			continue
		if shown.contains(recipe.display_name):
			_fail("FAIL undiscovered recipe '%s' is named in the column" % recipe.display_name)
	for def in AbilityRegistry.unlockable_defs():
		if def.id == AbilityRegistry.ID_LASER:
			continue
		if shown.contains(def.display_name):
			_fail("FAIL undiscovered power '%s' is named in the column" % def.display_name)
	if not shown.contains("(locked)"):
		_fail("FAIL nothing in the column says a recipe is missing")

	panel.close_panel()
	panel.queue_free()
	city.queue_free()
	await get_tree().process_frame
	print("OK 2 learned rows with badges, %d nameless locked boxes" % locked)


## Every scrap of text the recipe column draws, rows and headings alike.
func _column_text(node: Node) -> String:
	var out := ""
	var label := node as Label
	if label != null:
		out += label.text + "\n"
	for child in node.get_children():
		out += _column_text(child)
	return out


## Esc and I still close the panel, but a player whose hand is on the mouse needs a target.
func _check_close_button(panel: PlayerInventoryPanel) -> void:
	var btn := panel.close_button()
	if btn == null:
		_fail("FAIL the panel has no close button")
		return
	if not btn.is_visible_in_tree():
		_fail("FAIL the close button is not visible")
		return
	var frame := panel.panel_rect()
	var at := btn.get_global_rect().get_center()
	if at.x <= frame.get_center().x or at.y >= frame.get_center().y:
		_fail("FAIL the close button sits at %s, not the top right of %s" % [at, frame])
	btn.emit_signal("pressed")
	await get_tree().process_frame
	if panel.is_open():
		_fail("FAIL pressing the close button left the panel open")
		return
	panel.open_panel()
	await get_tree().process_frame
	print("OK close button at the top right shuts the panel")


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
