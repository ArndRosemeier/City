## Photographs the inventory modal over the live city, and measures what each slot drew.
##
## The panel's item icons are Node3Ds inside per-slot SubViewports, and every way that goes
## wrong is quiet: a camera that was never aimed, an icon outside the frame, a preview world
## that is really the game's. So the pixels each slot rendered are counted here — an icon that
## drew nothing, drew off-centre, or drew the city fails the run — and the stocked gems are
## read back through CityRoot.get_gem_count, which is what the HUD tallies.
##
## Needs a renderer: SubViewport render targets never draw headless.
##
## Run: powershell -File tools\run_test.ps1 shot_inventory_panel -Rendered
extends Node

const WORLD_SEED := 42
const WALKER_TIMEOUT_MS := 120000
const PANEL_PNG := "res://tools/inventory_panel.png"
const SLOT_PNG := "res://tools/inventory_slot_quartz.png"
const GEMS_PNG := "res://tools/inventory_gems.png"
const BADGES_PNG := "res://tools/inventory_recipe_badges.png"
const LOCKED_PNG := "res://tools/inventory_panel_undiscovered.png"
## The six gems are near-identical in colour in pairs, so they are judged against each other
## rather than one at a time. Magnified, never redrawn larger: the question is what the panel
## draws at 64 px.
const GEM_STRIP_ZOOM := 3
## The panel the slots sit on, so a transparent background does not read as a silhouette.
const SLOT_BACKDROP := Color(0.06, 0.07, 0.09, 1.0)
## Distinct per-type tallies, so the slot order and the per-gem counting are both readable.
const GEM_TALLIES: Array[int] = [7, 3, 11, 2, 40, 1]
## Quartz spent on the crafted trap that fills the seventh slot.
const TRAP_COST := 5
## Opaque pixels an icon must have drawn in its 64 x 64 target to count as visible.
const MIN_OPAQUE_PX := 200
## Share of a recipe badge's target that must be drawn. Judged as a fraction because the row
## targets are half the width of a slot's, and low because the openwork badges — the portal
## ring, the tetromino — are mostly the gaps between their own parts.
const MIN_BADGE_FRAC := 0.06
## How far the drawn icon's centre of mass may sit from the middle of its target.
const MAX_CENTROID_OFF_PX := 4.0
## A transparent slot background must stay transparent: the city leaking in shows up here.
const MAX_OPAQUE_FRAC := 0.9
const SHOT_HOUR := 11.0


func _ready() -> void:
	var city := CityRoot.new()
	city.city_seed = WORLD_SEED
	add_child(city)

	var walker := await _await_walker(city)
	if walker == null:
		return
	if not await _await_boot(city, walker):
		return

	var panel := city.get_node_or_null("PlayerInventory") as PlayerInventoryPanel
	if panel == null:
		push_error("FAIL CityRoot built no PlayerInventory panel")
		get_tree().quit(1)
		return
	var occupied := _stock_inventory(city)
	if occupied == 0:
		get_tree().quit(1)
		return

	_pin_hour(city)
	_hide_error_panel()
	panel.open_panel()
	if not panel.is_open():
		push_error("FAIL panel refused to open")
		get_tree().quit(1)
		return
	await _frames(30)

	if not _check_previews(panel, occupied):
		get_tree().quit(1)
		return
	await _shoot(PANEL_PNG)
	_save_slot(panel, 0, SLOT_PNG)
	_save_gem_strip(panel, _gem_materials().size(), GEMS_PNG)
	if not _save_recipe_badges(panel, BADGES_PNG):
		get_tree().quit(1)
		return
	if not await _shoot_undiscovered_column(city, panel):
		get_tree().quit(1)
		return

	print("RESULT: OK")
	get_tree().quit(0)


## Fills the first seven slots: one stack per gem type plus a crafted trap. Returns how many
## slots should now hold an icon.
func _stock_inventory(city: CityRoot) -> int:
	var inv := city.get_inventory()
	inv.clear()
	var mats := _gem_materials()
	if mats.size() != GEM_TALLIES.size():
		push_error("FAIL %d gem materials but %d tallies" % [mats.size(), GEM_TALLIES.size()])
		return 0
	for i in mats.size():
		var item_id := InventoryCatalog.item_id_for_gem(mats[i])
		var over := inv.add(item_id, GEM_TALLIES[i] + (TRAP_COST if i == 0 else 0))
		if over != 0:
			push_error("FAIL %s did not fit (%d left)" % [item_id, over])
			return 0
	if not inv.craft(InventoryCatalog.RECIPE_TRAP):
		push_error("FAIL could not craft the trap for the seventh slot")
		return 0
	for i in mats.size():
		var have := city.get_gem_count(mats[i])
		if have != GEM_TALLIES[i]:
			push_error(
				"FAIL CityRoot.get_gem_count(%d) is %d, stocked %d"
				% [mats[i], have, GEM_TALLIES[i]]
			)
			return 0
	print(
		"stocked gems: %s  traps: %d"
		% [str(GEM_TALLIES), inv.count_of(InventoryCatalog.ID_TRAP)]
	)
	return mats.size() + 1


## Reads back every slot's render target. An icon that never drew leaves it empty, one drawn
## by a mis-aimed camera leaves the mass off centre, and a preview sharing the game's World3D
## fills it with city.
func _check_previews(panel: PlayerInventoryPanel, occupied: int) -> bool:
	var ok := true
	for i in InventoryCatalog.SLOT_COUNT:
		var vp := panel.slot_viewport(i)
		var img := vp.get_texture().get_image()
		if img == null:
			push_error("FAIL slot %d has no render target image" % i)
			return false
		var opaque := 0
		var sum := Vector2.ZERO
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				if img.get_pixel(x, y).a < 0.5:
					continue
				opaque += 1
				sum += Vector2(float(x) + 0.5, float(y) + 0.5)
		var total := img.get_width() * img.get_height()
		if i >= occupied:
			if opaque != 0:
				push_error("FAIL empty slot %d drew %d opaque pixels" % [i, opaque])
				ok = false
			continue
		if opaque < MIN_OPAQUE_PX:
			push_error("FAIL slot %d drew only %d opaque pixels of %d" % [i, opaque, total])
			ok = false
			continue
		if float(opaque) / float(total) > MAX_OPAQUE_FRAC:
			push_error(
				"FAIL slot %d covered %.0f%% of its target — the preview world is not empty"
				% [i, float(opaque) / float(total) * 100.0]
			)
			ok = false
			continue
		var centroid := sum / float(opaque)
		var off := centroid - Vector2(img.get_size()) * 0.5
		if off.length() > MAX_CENTROID_OFF_PX:
			push_error(
				"FAIL slot %d icon mass sits %.1f px off centre at %s"
				% [i, off.length(), str(centroid)]
			)
			ok = false
			continue
		print(
			"slot %d: %d px (%.0f%% of target) centred within %.1f px"
			% [i, opaque, float(opaque) / float(total) * 100.0, off.length()]
		)
	return ok


## The first slot on its own, so the icon can be judged at more than four screen pixels.
func _save_slot(panel: PlayerInventoryPanel, index: int, path: String) -> void:
	var img := panel.slot_viewport(index).get_texture().get_image()
	if img == null:
		push_error("FAIL slot %d has no render target to save" % index)
		return
	img.resize(256, 256, Image.INTERPOLATE_NEAREST)
	img.save_png(path)
	print("SAVED %s" % path)


## Every gem slot in one row over the panel's own backdrop. Quartz and diamond share a palette
## with the ore in the hills, so what separates them is the cut, and a cut is only judgeable
## next to the others.
func _save_gem_strip(panel: PlayerInventoryPanel, count: int, path: String) -> void:
	var cell := PlayerInventoryPanel.VIEW_SIZE.x
	var strip := Image.create_empty(cell * count, cell, false, Image.FORMAT_RGBA8)
	strip.fill(SLOT_BACKDROP)
	for i in count:
		var img := panel.slot_viewport(i).get_texture().get_image()
		if img == null:
			push_error("FAIL slot %d has no render target for the gem strip" % i)
			return
		img.convert(Image.FORMAT_RGBA8)
		strip.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(cell * i, 0))
	strip.resize(
		strip.get_width() * GEM_STRIP_ZOOM,
		strip.get_height() * GEM_STRIP_ZOOM,
		Image.INTERPOLATE_NEAREST
	)
	strip.save_png(path)
	print("SAVED %s" % path)


## The column as an Adventure run first sees it: nothing learned, so every recipe is a blank
## box. Shot from the real loadout rather than a stub, because "how many boxes and what do they
## say" is exactly what a fresh Adventure start is.
func _shoot_undiscovered_column(city: CityRoot, panel: PlayerInventoryPanel) -> bool:
	city.get_loadout().reset_adventure()
	panel.rebuild_recipe_lists()
	await _frames(6)
	var rows := panel.recipe_rows()
	var locked := panel.locked_box_count()
	var total := InventoryCatalog.craft_recipes().size() + AbilityRegistry.unlockable_defs().size()
	if not rows.is_empty():
		push_error("FAIL an empty cookbook still listed %d recipes by name" % rows.size())
		return false
	if locked != total:
		push_error("FAIL %d locked boxes for a cookbook of %d recipes" % [locked, total])
		return false
	await _shoot(LOCKED_PNG)
	print("locked column: %d blank boxes" % locked)
	return true


## Every badge the recipe column drew, in one row. A row shows what it builds, and a badge that
## came out as a speck or as nothing at all is invisible in the panel shot at 38 px — the same
## blind spot the slot strip exists to cover.
func _save_recipe_badges(panel: PlayerInventoryPanel, path: String) -> bool:
	var rows := panel.recipe_rows()
	if rows.is_empty():
		push_error("FAIL the recipe column built no rows")
		return false
	var cell := int(PlayerInventoryPanel.ROW_ICON_PX)
	var sheet := Image.create_empty(cell * rows.size(), cell, false, Image.FORMAT_RGBA8)
	sheet.fill(SLOT_BACKDROP)
	var ok := true
	for i in rows.size():
		var row := rows[i]
		var img := row.preview.viewport().get_texture().get_image()
		if img == null:
			push_error("FAIL recipe row '%s' has no render target" % row.id)
			return false
		var opaque := 0
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				if img.get_pixel(x, y).a >= 0.5:
					opaque += 1
		var covered := float(opaque) / float(img.get_width() * img.get_height())
		if covered < MIN_BADGE_FRAC:
			push_error(
				"FAIL badge for '%s' covered %.1f%% of its %dx%d target"
				% [row.id, covered * 100.0, img.get_width(), img.get_height()]
			)
			ok = false
		img.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(cell * i, 0))
	sheet.resize(
		sheet.get_width() * GEM_STRIP_ZOOM,
		sheet.get_height() * GEM_STRIP_ZOOM,
		Image.INTERPOLATE_NEAREST
	)
	sheet.save_png(path)
	print("SAVED %s (%d badges)" % [path, rows.size()])
	return ok


func _await_walker(city: CityRoot) -> CityWalker:
	var deadline := Time.get_ticks_msec() + WALKER_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var walker := city.get_node_or_null("Walker") as CityWalker
		if walker != null:
			return walker
	push_error("FAIL no walker after %d ms" % WALKER_TIMEOUT_MS)
	get_tree().quit(1)
	return null


## Boot is over when the walker has physics and the title splash has let go of the screen.
## CityRoot holds physics off until the spawn column has stamped solid, and the splash then fades over
## half a second — a wait counted in frames outruns that fade at rendered frame rates and used
## to photograph the panel through the title art.
func _await_boot(city: CityRoot, walker: CityWalker) -> bool:
	var splash := _splash(city)
	if splash == null:
		get_tree().quit(1)
		return false
	var deadline := Time.get_ticks_msec() + WALKER_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if walker.is_physics_processing() and not splash.visible:
			await _frames(4)
			return true
	push_error("FAIL the walker never got physics in %d ms" % WALKER_TIMEOUT_MS)
	get_tree().quit(1)
	return false


## CityRoot leaves the splash unnamed, so it is found by the layer it reserves.
func _splash(city: CityRoot) -> CanvasLayer:
	for child in city.get_children():
		var canvas := child as CanvasLayer
		if canvas != null and canvas.layer == UiLayers.LOADING_SPLASH:
			return canvas
	push_error("FAIL no loading splash on layer %d" % UiLayers.LOADING_SPLASH)
	return null


## The autoloaded error panel sits over the middle of the frame, which is where the inventory
## is. Everything it lists is also on stderr, so hiding it hides nothing from the reviewer.
func _hide_error_panel() -> void:
	var panel := get_tree().root.get_node_or_null("ErrorOverlay") as CanvasLayer
	if panel == null:
		push_error("FAIL no ErrorOverlay autoload to hide")
		return
	panel.visible = false


func _pin_hour(city: CityRoot) -> void:
	var cycle := city.get_node_or_null("DayNightCycle")
	if cycle == null:
		push_error("FAIL no DayNightCycle to pin")
		return
	cycle.call("set_hour", SHOT_HOUR)


func _shoot(path: String) -> void:
	await _frames(6)
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
		return
	img.save_png(path)
	print("SAVED %s" % path)


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame


func _gem_materials() -> Array[int]:
	var out: Array[int] = []
	for mat_id in range(VoxelMaterial.GEM_QUARTZ, VoxelMaterial.GEM_DIAMOND + 1):
		out.append(mat_id)
	return out
