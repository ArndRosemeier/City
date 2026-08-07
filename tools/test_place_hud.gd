## Place chrome: district chip, analog clock, foldable FPS line.
##
## Run: powershell -File tools\run_test.ps1 test_place_hud
extends Node

const PlaceHudScript := preload("res://scripts/city/place_hud.gd")

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	var hud := PlaceHudScript.new() as Control
	hud.name = "PlaceHud"
	add_child(hud)
	await get_tree().process_frame

	var pos: Vector2 = hud.get("POS") as Vector2
	if not hud.position.is_equal_approx(pos):
		_fail("FAIL PlaceHud should sit at %s, got %s" % [pos, hud.position])

	hud.call("set_district_name", "Old Maren")
	var name_label := hud.get_node_or_null("Row/DistrictName/Name") as Label
	if name_label == null or name_label.text != "Old Maren":
		_fail("FAIL district name did not land on the chip")

	var clock := hud.get_node_or_null("Row/Clock") as Control
	if clock == null:
		_fail("FAIL missing analog clock")
	else:
		hud.call("set_hour", 15.5)
		if clock.get_combined_minimum_size().x < 20.0:
			_fail("FAIL clock has no size")

	var fold := hud.get_node_or_null("Fold") as Control
	var btn := hud.get_node_or_null("Row/FoldButton") as Button
	if fold == null or btn == null:
		_fail("FAIL missing fold chrome")
	elif fold.visible:
		_fail("FAIL fold should start closed")
	elif btn.text != "▸":
		_fail("FAIL closed fold arrow should be ▸, got %s" % btn.text)

	hud.call("set_fold_line", "60 FPS  Sandbox")
	var stats := hud.get_node_or_null("Fold/Stats") as Label
	if stats == null or stats.text != "60 FPS  Sandbox":
		_fail("FAIL fold line missing")

	var bottoms: Array[float] = []
	hud.connect("bottom_changed", func(y: float) -> void: bottoms.append(y))
	btn.pressed.emit()
	await get_tree().process_frame
	if not bool(hud.call("is_fold_open")) or fold == null or not fold.visible:
		_fail("FAIL fold did not open")
	elif btn.text != "▾":
		_fail("FAIL open fold arrow should be ▾, got %s" % btn.text)
	elif bottoms.is_empty():
		_fail("FAIL opening the fold did not report a new bottom")
	else:
		var want := float(hud.call("bottom_y"))
		if not is_equal_approx(bottoms[bottoms.size() - 1], want):
			_fail(
				"FAIL bottom_changed %.1f != bottom_y %.1f"
				% [bottoms[bottoms.size() - 1], want]
			)

	btn.pressed.emit()
	await get_tree().process_frame
	if bool(hud.call("is_fold_open")) or (fold != null and fold.visible):
		_fail("FAIL fold did not close again")

	hud.queue_free()
	if _failed:
		print("RESULT: FAIL")
		get_tree().quit(1)
		return
	print("RESULT: OK")
	get_tree().quit(0)
