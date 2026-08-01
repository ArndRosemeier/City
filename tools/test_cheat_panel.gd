## Cheat modal: layer, buttons, and the nameless log that future probes will dump into.
##
## Run: powershell -File tools\run_test.ps1 test_cheat_panel
extends Node

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_check_panel()
	_check_landmark_filter()
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