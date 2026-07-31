## Photographs both city modals over the live city and proves the draw order around them.
##
## The inventory panel used to be half-covered by the energy bar and the F1–F6 build strip,
## because every CanvasLayer picked its own number. So each modal is opened here and the whole
## tree of CanvasLayers is read back: nothing outside the debug band may sit in front of the
## open panel, and no HUD surface may be left switched on underneath its translucent dim. The
## last shot pushes the profiler overlay and an error report on top of an open modal, because
## the one thing a panel must never be able to do is hide a failure.
##
## The Game modal is photographed the same way, and its buttons are then actually pressed against
## the live city: a save panel that draws correctly and writes nothing is the failure that would
## otherwise only surface when someone tried to load.
##
## The J-hop district picker is photographed alongside them, at the top of its list and scrolled
## down to Castle. It is a takeover rather than a modal, but it is the surface that has actually
## run out of room: nine themes are taller than the window, and the last of them was laid out
## below the bottom edge until the rows were given something to scroll in.
##
## Needs a renderer: the panel previews are SubViewport render targets.
##
## Run: powershell -File tools\run_test.ps1 shot_modal_layers -Rendered
extends Node

const WORLD_SEED := 42
const WALKER_TIMEOUT_MS := 120000
const INVENTORY_PNG := "res://tools/modal_inventory.png"
const SETTINGS_PNG := "res://tools/modal_settings.png"
const DEBUG_PNG := "res://tools/modal_debug_above.png"
const GAME_MENU_PNG := "res://tools/modal_game_menu.png"
## Scratch slots for this run, so photographing the Game modal cannot touch a real autosave.
const SHOT_SAVES_DIR := "user://shot_saves"
const SHOT_SLOT_NAME := "shot_slot"
const PICKER_TOP_PNG := "res://tools/district_picker_top.png"
const PICKER_BOTTOM_PNG := "res://tools/district_picker_bottom.png"
## One stack per gem type, so the panel has something to show.
const GEM_TALLIES: Array[int] = [7, 3, 11, 2, 40, 1]
const TRAP_COST := 5
const SHOT_HOUR := 11.0

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	var city := CityRoot.new()
	city.city_seed = WORLD_SEED
	add_child(city)

	var walker := await _await_walker(city)
	if walker == null:
		return
	if not await _await_boot(city, walker):
		return

	var inventory := city.get_node_or_null("PlayerInventory") as PlayerInventoryPanel
	var settings := city.get_node_or_null("CitySettings") as CitySettingsPanel
	if inventory == null or settings == null:
		_fail("FAIL CityRoot built no PlayerInventory / CitySettings panel")
		_finish()
		return
	if not _stock_inventory(city):
		_finish()
		return

	_pin_hour(city)
	_set_error_panel_shown(false)

	inventory.open_panel()
	await _frames(30)
	if not inventory.is_open():
		_fail("FAIL the inventory panel refused to open")
	_check_modal_owns_screen("inventory", inventory.layer)
	await _shoot(INVENTORY_PNG)
	inventory.close_panel()
	await _frames(6)
	_check_hud_returned()

	settings.open_panel()
	await _frames(20)
	if not settings.is_open():
		_fail("FAIL the settings panel refused to open")
	_check_modal_owns_screen("settings", settings.layer)
	await _shoot(SETTINGS_PNG)

	await _shoot_game_menu(city, settings)

	settings.open_panel()
	await _frames(20)
	_check_debug_outranks(settings.layer)
	await _frames(10)
	await _shoot(DEBUG_PNG)
	settings.close_panel()
	## The debug band is the subject of the shot above and would be in front of every one below.
	_set_error_panel_shown(false)
	_set_profiler_shown(false)

	await _shoot_district_picker(city, walker)

	_finish()


func _finish() -> void:
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


## Two shots of the J-hop picker, at the top of the list and scrolled down to the last theme,
## plus the thing a screenshot cannot show: the picker is a full-screen takeover, so every
## gameplay hotkey has to stop at it. Parking the walker is not enough — the build strip and the
## arcade cabinet ask the gate, not the walker's physics.
func _shoot_district_picker(city: CityRoot, walker: CityWalker) -> void:
	var splash := _splash(city) as LoadingSplash
	if splash == null:
		_fail("FAIL the loading splash is not a LoadingSplash")
		return
	if UiInputGate.gameplay_blocked(walker):
		_fail("FAIL gameplay input was already blocked with nothing on screen")
		return

	splash.open_district_picker()
	await _frames(10)
	if UiInputGate.gameplay_blocked(walker):
		print("OK the open picker stops gameplay input")
	else:
		_fail("FAIL gameplay hotkeys still reach the city behind the open district picker")
	await _shoot(PICKER_TOP_PNG)

	var last := DistrictTheme.COUNT - 1
	var label := DistrictTheme.make(last).display_name
	splash.reveal_theme_button(last)
	await _frames(6)
	var rect := splash.theme_button(last).get_global_rect()
	if get_viewport().get_visible_rect().encloses(rect):
		print("OK %s is on screen at %s with the list scrolled down" % [label, rect])
	else:
		_fail("FAIL %s is at %s, off screen even scrolled to the bottom" % [label, rect])
	await _shoot(PICKER_BOTTOM_PNG)

	splash.hide_splash()
	await _frames(10)
	if UiInputGate.gameplay_blocked(walker):
		_fail("FAIL gameplay input stayed off after the picker closed")


## The Game modal over a live city, and the one thing a screenshot cannot show: that the buttons
## on it actually reach disk. Both writes go to a scratch folder — a screenshot run must not
## overwrite the autosave of whoever plays on this machine.
func _shoot_game_menu(city: CityRoot, settings: CitySettingsPanel) -> void:
	if settings.get_node_or_null("TopBar/GameButton") == null:
		_fail("FAIL there is no Game button on the top bar")
		return
	GameSave.use_directory(SHOT_SAVES_DIR)
	var menu := city.get_node_or_null("GameMenu") as GameMenuPanel
	if menu == null:
		_fail("FAIL CityRoot built no GameMenu panel")
		GameSave.use_default_directory()
		return

	settings.game_menu_requested.emit()
	await _frames(20)
	if not menu.is_open():
		_fail("FAIL the Game button did not open the Game modal")
	if not city.is_modal_open():
		_fail("FAIL CityRoot does not count the open Game modal as a modal")
	_check_modal_owns_screen("game", menu.layer)

	if not city.write_quicksave("Shot"):
		_fail("FAIL Quicksave over the live city wrote nothing")
	if not city.write_named_save(SHOT_SLOT_NAME):
		_fail("FAIL the named save over the live city wrote nothing")
	menu.refresh()
	await _frames(6)
	if not city.has_quicksave():
		_fail("FAIL the live city reports no quicksave right after writing one")
	var names := PackedStringArray()
	for entry: Dictionary in city.list_named_saves():
		names.append(String(entry["name"]))
	if not names.has(SHOT_SLOT_NAME):
		_fail("FAIL the named save is not in the library: %s" % str(names))
	await _shoot(GAME_MENU_PNG)

	menu.close_panel()
	await _frames(6)
	if city.is_modal_open():
		_fail("FAIL the Game modal stayed open")
	_check_hud_returned()
	_wipe_shot_saves()
	GameSave.use_default_directory()


func _wipe_shot_saves() -> void:
	var dir := DirAccess.open(SHOT_SAVES_DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		DirAccess.remove_absolute("%s/%s" % [SHOT_SAVES_DIR, file])


## An open modal owns the screen: only the debug band may draw in front of it, and the HUD it
## replaced must be switched off rather than left bleeding through the dim.
func _check_modal_owns_screen(label: String, modal_layer: int) -> void:
	var over: PackedStringArray = PackedStringArray()
	var hud_up: PackedStringArray = PackedStringArray()
	for canvas in _canvas_layers():
		if not canvas.visible:
			continue
		if canvas.layer >= UiLayers.HUD_MIN and canvas.layer <= UiLayers.HUD_MAX:
			hud_up.append("%s (layer %d)" % [canvas.name, canvas.layer])
		if canvas.layer > modal_layer and canvas.layer < UiLayers.DEBUG_NAV_COUNTERS:
			over.append("%s (layer %d)" % [canvas.name, canvas.layer])
	for entry in over:
		_fail("FAIL %s draws over the open %s modal on layer %d" % [entry, label, modal_layer])
	for entry in hud_up:
		_fail("FAIL HUD surface %s is still on with the %s modal open" % [entry, label])
	if over.is_empty() and hud_up.is_empty():
		print("OK %s modal on layer %d: nothing above it, HUD band off" % [label, modal_layer])


## The HUD has to come back, or the fix traded a covered panel for a lost readout.
func _check_hud_returned() -> void:
	var off: PackedStringArray = PackedStringArray()
	var on := 0
	for canvas in _canvas_layers():
		if canvas.layer < UiLayers.HUD_MIN or canvas.layer > UiLayers.HUD_MAX:
			continue
		if canvas.visible:
			on += 1
		else:
			off.append("%s (layer %d)" % [canvas.name, canvas.layer])
	for entry in off:
		_fail("FAIL HUD surface %s stayed hidden after the modal closed" % entry)
	if off.is_empty():
		print("OK %d HUD surfaces back on after the modal closed" % on)


## Errors and hitch reports outrank every panel. Both surfaces are switched on over the open
## modal so the shot shows what a failure would look like from behind one.
func _check_debug_outranks(modal_layer: int) -> void:
	var profiler := get_tree().root.get_node_or_null("CityProfiler") as CanvasLayer
	var errors := get_tree().root.get_node_or_null("ErrorOverlay") as CanvasLayer
	if profiler == null or errors == null:
		_fail("FAIL no CityProfiler / ErrorOverlay autoload")
		return
	if profiler.layer <= modal_layer:
		_fail("FAIL the profiler overlay (layer %d) is not above the modal on layer %d"
			% [profiler.layer, modal_layer])
	if errors.layer <= profiler.layer:
		_fail("FAIL the error panel (layer %d) is not above the profiler (layer %d)"
			% [errors.layer, profiler.layer])
	_set_profiler_shown(true)
	_set_error_panel_shown(true)
	errors.call(
		"enqueue_error",
		"SCRIPT",
		"Sample report: an open modal must never be able to hide this panel.",
		"tools/shot_modal_layers.gd",
		0
	)
	print("OK profiler on layer %d and errors on layer %d, both over the modal on %d"
		% [profiler.layer, errors.layer, modal_layer])


func _canvas_layers() -> Array[CanvasLayer]:
	var out: Array[CanvasLayer] = []
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var canvas := node as CanvasLayer
		if canvas != null:
			out.append(canvas)
	return out


func _stock_inventory(city: CityRoot) -> bool:
	var inv := city.get_inventory()
	inv.clear()
	var mats := _gem_materials()
	if mats.size() != GEM_TALLIES.size():
		_fail("FAIL %d gem materials but %d tallies" % [mats.size(), GEM_TALLIES.size()])
		return false
	for i in mats.size():
		var item_id := InventoryCatalog.item_id_for_gem(mats[i])
		var over := inv.add(item_id, GEM_TALLIES[i] + (TRAP_COST if i == 0 else 0))
		if over != 0:
			_fail("FAIL %s did not fit (%d left)" % [item_id, over])
			return false
	if not inv.craft(InventoryCatalog.RECIPE_TRAP):
		_fail("FAIL could not craft the trap for the seventh slot")
		return false
	return true


func _await_walker(city: CityRoot) -> CityWalker:
	var deadline := Time.get_ticks_msec() + WALKER_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var walker := city.get_node_or_null("Walker") as CityWalker
		if walker != null:
			return walker
	_fail("FAIL no walker after %d ms" % WALKER_TIMEOUT_MS)
	_finish()
	return null


## Boot is over when the walker has physics and the title splash has let go of the screen.
## CityRoot holds physics off until ground collision exists, and the splash then fades out over
## half a second — long enough that a wait counted in frames photographs the title art instead.
func _await_boot(city: CityRoot, walker: CityWalker) -> bool:
	var splash := _splash(city)
	if splash == null:
		_finish()
		return false
	var deadline := Time.get_ticks_msec() + WALKER_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if walker.is_physics_processing() and not splash.visible:
			await _frames(4)
			return true
	_fail("FAIL the walker never got physics in %d ms" % WALKER_TIMEOUT_MS)
	_finish()
	return false


## CityRoot leaves the splash unnamed, so it is found by the layer it reserves.
func _splash(city: CityRoot) -> CanvasLayer:
	for child in city.get_children():
		var canvas := child as CanvasLayer
		if canvas != null and canvas.layer == UiLayers.LOADING_SPLASH:
			return canvas
	_fail("FAIL no loading splash on layer %d" % UiLayers.LOADING_SPLASH)
	return null


## Boot warnings would otherwise leave the error panel over the middle of every shot, which is
## exactly where the modals are. The last shot switches it back on deliberately.
func _set_error_panel_shown(shown: bool) -> void:
	var panel := get_tree().root.get_node_or_null("ErrorOverlay") as CanvasLayer
	if panel == null:
		_fail("FAIL no ErrorOverlay autoload")
		return
	panel.visible = shown


func _set_profiler_shown(shown: bool) -> void:
	var profiler := get_tree().root.get_node_or_null("CityProfiler") as CanvasLayer
	if profiler == null:
		_fail("FAIL no CityProfiler autoload")
		return
	profiler.call("set_overlay_enabled", shown)


func _pin_hour(city: CityRoot) -> void:
	var cycle := city.get_node_or_null("DayNightCycle")
	if cycle == null:
		_fail("FAIL no DayNightCycle to pin")
		return
	cycle.call("set_hour", SHOT_HOUR)


func _shoot(path: String) -> void:
	await _frames(6)
	var img := get_viewport().get_texture().get_image()
	if img == null:
		_fail("FAIL no viewport image for %s" % path)
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
