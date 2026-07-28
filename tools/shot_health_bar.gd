## Photographs the wound bar next to the energy bar at full, half and near death.
##
## The two are both hundred-point pools that refill on their own, and the whole damage model
## rests on a player never confusing them at a glance. That is not something a headless
## assertion can answer, so this boots the real city, hits the real player with real orbs and
## saves what the screen actually looked like. The numbers are printed alongside each shot so the
## picture can be checked against the pools rather than trusted.
##
## The last shot opens the inventory: modals hide the whole HUD band, and a health bar that
## survived that would be the same layering bug `ui_layers.gd` was written to end.
##
## Run: powershell -File tools\run_test.ps1 shot_health_bar -Rendered
extends Node

const WORLD_SEED := 42
const WALKER_TIMEOUT_MS := 120000
const FULL_PNG := "res://tools/health_bar_full.png"
const HURT_PNG := "res://tools/health_bar_damaged.png"
const CRITICAL_PNG := "res://tools/health_bar_critical.png"
const MODAL_PNG := "res://tools/health_bar_modal.png"
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

	var health_hud := city.get_node_or_null("PlayerHealthHud") as CanvasLayer
	var energy_hud := city.get_node_or_null("PlayerEnergyHud") as CanvasLayer
	if health_hud == null or energy_hud == null:
		_fail("FAIL CityRoot built no PlayerHealthHud / PlayerEnergyHud")
		_finish()
		return
	if health_hud.layer == energy_hud.layer:
		_fail("FAIL both bars are on layer %d" % health_hud.layer)
	_pin_hour(city)
	_set_error_panel_shown(false)

	await _shoot(FULL_PNG, city, walker, health_hud)

	## An orb takes a quarter. Two of them, and a blast's worth of energy spent, so the shot has
	## the two pools at visibly different levels — the state where confusing them costs a run.
	city.damage_player(DamageSource.Id.UNDEAD_ORB)
	city.damage_player(DamageSource.Id.UNDEAD_ORB)
	walker.try_spend_energy(walker.energy_cost_blast)
	await _shoot(HURT_PNG, city, walker, health_hud)

	## One more hit and the run is over, which is when the bar goes amber and breathes.
	city.damage_player(DamageSource.Id.UNDEAD_ORB)
	await _shoot(CRITICAL_PNG, city, walker, health_hud)
	if not city.is_player_alive():
		_fail("FAIL three orbs ended the run before the fourth")

	var inventory := city.get_node_or_null("PlayerInventory") as PlayerInventoryPanel
	if inventory == null:
		_fail("FAIL CityRoot built no PlayerInventory panel")
		_finish()
		return
	inventory.open_panel()
	await _frames(20)
	if health_hud.visible:
		_fail("FAIL the wound bar is still up with the inventory open")
	else:
		print("OK the wound bar went down with the rest of the HUD band")
	await _shoot(MODAL_PNG, city, walker, health_hud)
	inventory.close_panel()
	await _frames(10)
	if not health_hud.visible:
		_fail("FAIL the wound bar did not come back when the modal closed")

	_finish()


func _finish() -> void:
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


## Saves the frame and prints what the two pools held while it was taken, so the picture and the
## numbers can be read against each other.
func _shoot(path: String, city: CityRoot, walker: CityWalker, health_hud: CanvasLayer) -> void:
	await _frames(8)
	var drawn := float(health_hud.call("fill_fraction"))
	if absf(drawn - walker.get_health_fraction()) > 0.01:
		_fail(
			"FAIL the bar is %.3f full with the pool at %.3f"
			% [drawn, walker.get_health_fraction()]
		)
	var img := get_viewport().get_texture().get_image()
	if img == null:
		_fail("FAIL no viewport image for %s" % path)
		return
	img.save_png(path)
	print(
		"SAVED %s — health %.0f/%.0f (bar %.0f%%), energy %.0f/%.0f, alive %s"
		% [
			path,
			walker.get_health(),
			walker.get_health_max(),
			drawn * 100.0,
			walker.get_energy(),
			walker.get_energy_max(),
			str(city.is_player_alive()),
		]
	)


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


## Boot warnings would otherwise leave the error panel across the middle of every shot.
func _set_error_panel_shown(shown: bool) -> void:
	var panel := get_tree().root.get_node_or_null("ErrorOverlay") as CanvasLayer
	if panel == null:
		_fail("FAIL no ErrorOverlay autoload")
		return
	panel.visible = shown


func _pin_hour(city: CityRoot) -> void:
	var cycle := city.get_node_or_null("DayNightCycle")
	if cycle == null:
		_fail("FAIL no DayNightCycle to pin")
		return
	cycle.call("set_hour", SHOT_HOUR)


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame
