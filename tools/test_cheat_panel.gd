## Cheat modal: layer, buttons, district-report text shape, and compass heading math.
##
## Run: powershell -File tools\run_test.ps1 test_cheat_panel
extends Node

const CityWalkerScript := preload("res://scripts/city/city_walker.gd")
const PlayerLoadoutScript := preload("res://scripts/city/player_loadout.gd")
const DistrictEconomyScript := preload("res://scripts/city/district_economy.gd")

var _failed := false


class TestCity:
	extends CityRoot

	func _ready() -> void:
		add_to_group("city_root")


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_check_panel()
	_check_landmark_filter()
	_check_compass_heading()
	await _check_district_report()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _check_panel() -> void:
	var panel := CheatPanel.new()
	panel.name = "Cheat"
	add_child(panel)
	if panel.layer != UiLayers.MODAL_CHEAT:
		_fail("FAIL cheat panel layer is %d, want %d" % [panel.layer, UiLayers.MODAL_CHEAT])
	if panel.is_open():
		_fail("FAIL cheat panel opened itself")
	panel.open_panel()
	if not panel.is_open():
		_fail("FAIL cheat panel did not open")
	var buttons := panel.button_column()
	if buttons == null:
		_fail("FAIL cheat panel has no button column")
		return
	var labels: PackedStringArray = PackedStringArray()
	for child in buttons.get_children():
		var btn := child as Button
		if btn != null:
			labels.append(btn.text)
	for want in ["Fill gems", "Fill recipes", "Teleport to recipe"]:
		if not labels.has(want):
			_fail("FAIL cheat panel missing button '%s' (have %s)" % [want, str(labels)])
	var room := buttons.get_node_or_null("FutureButtonRoom")
	if room == null:
		_fail("FAIL cheat panel left no room for more buttons")
	var log := panel.log_view()
	if log == null or log.editable:
		_fail("FAIL cheat log must be a read-only TextEdit")
	panel.append_log("first")
	panel.append_log("second")
	if log.text != "first\nsecond":
		_fail("FAIL cheat log text is '%s'" % log.text)
	panel.close_button().emit_signal("pressed")
	if panel.is_open():
		_fail("FAIL close button left the cheat panel open")
	print("OK cheat panel: %d action buttons + log" % labels.size())


## Chest scrolls must not win a "teleport to recipe" search over a landmark that is farther.
func _check_landmark_filter() -> void:
	var hill_id := RecipePickupPlacer.site_id(
		RecipePickupPlacer.SITE_HILL_SUMMIT, Vector2i(1, 2), 0
	)
	var chest_id := RecipePickupPlacer.site_id(RecipePickupPlacer.SITE_CHEST, Vector2i(1, 2), 0)
	if not RecipePickupPlacer.is_landmark_site_id(hill_id):
		_fail("FAIL summit site '%s' is not a landmark" % hill_id)
	if RecipePickupPlacer.is_landmark_site_id(chest_id):
		_fail("FAIL chest site '%s' passed the landmark filter" % chest_id)
	print("OK landmark filter drops chest sites")


## North is world −Z (yaw 0). The rose and the label must agree with that, or the compass
## will point the wrong way relative to the minimap.
func _check_compass_heading() -> void:
	if not is_equal_approx(PlayerCompassHud.heading_degrees(0.0), 0.0):
		_fail("FAIL yaw 0 should face north (0°)")
	if absf(PlayerCompassHud.heading_degrees(-PI * 0.5) - 90.0) > 0.5:
		_fail("FAIL yaw −90° should face east")
	if absf(PlayerCompassHud.heading_degrees(PI) - 180.0) > 0.5:
		_fail("FAIL yaw 180° should face south")
	if absf(PlayerCompassHud.heading_degrees(PI * 0.5) - 270.0) > 0.5:
		_fail("FAIL yaw +90° should face west")
	if not PlayerCompassHud.heading_label(0.0).begins_with("N"):
		_fail("FAIL north label is '%s'" % PlayerCompassHud.heading_label(0.0))
	var hud := PlayerCompassHud.new()
	hud.name = "Compass"
	add_child(hud)
	if hud.layer != UiLayers.HUD_COMPASS:
		_fail("FAIL compass layer is %d, want %d" % [hud.layer, UiLayers.HUD_COMPASS])
	hud.queue_free()
	print("OK compass heading: N/E/S/W match walker yaw")


func _check_district_report() -> void:
	var city := TestCity.new()
	city.name = "ReportCity"
	add_child(city)
	city.city_seed = 42
	city._loadout = PlayerLoadoutScript.new() as PlayerLoadout
	city._loadout.reset_adventure()
	city._economy = DistrictEconomyScript.new() as DistrictEconomy
	var walker: CityWalker = CityWalkerScript.new() as CityWalker
	walker.name = "ReportWalker"
	walker.set_physics_process(false)
	walker.set_process(false)
	city.add_child(walker)
	city._walker = walker
	walker.global_position = Vector3(10.0, 2.0, 10.0)
	await get_tree().process_frame

	var report := city.build_cheat_district_report()
	if not report.begins_with("District report"):
		_fail("FAIL report missing title: %s" % report.get_slice("\n", 0))
	if not report.contains("Hidden gems:"):
		_fail("FAIL report missing hidden gems line")
	if not report.contains("Actors"):
		_fail("FAIL report missing Actors section")
	if not report.contains("Neighbors"):
		_fail("FAIL report missing Neighbors section")
	for dir_name in ["east =>", "south =>", "west =>", "north =>"]:
		if not report.contains(dir_name):
			_fail("FAIL report missing neighbor '%s'" % dir_name)
	## Opening the panel should dump the report into the log.
	city._cheat_panel = CheatPanel.new() as CheatPanel
	city.add_child(city._cheat_panel)
	city._on_cheat_opened()
	var log := city._cheat_panel.log_view()
	if log == null or not log.text.contains("Neighbors"):
		_fail("FAIL opening the cheat panel did not fill the district report")
	city.queue_free()
	print("OK district report names gems, actors, and neighbors")
