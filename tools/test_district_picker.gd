## Every district theme has to be reachable in the J-hop picker.
##
## Castle went into DistrictTheme as id 8 and the picker did build a row for it — the rows come
## from range(COUNT), so that half was never the problem. What the picker had no answer for was
## the height: nine rows want 838 units of a 720-unit viewport, a CenterContainer hands its
## child the full minimum size regardless, and there was nothing to scroll, so the last theme
## was laid out fifteen pixels below the bottom edge where no click could ever land on it.
##
## Reachable therefore means all four of these at once, per theme, and theme ten will be held
## to the same bar: a row exists, it is labelled with that theme, the picker can bring it fully
## inside the rectangle it actually draws in, and pressing it answers with that theme's id.
##
## Run: powershell -File tools\run_test.ps1 test_district_picker
extends Node

var _failed := false
var _chosen: Array[int] = []


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	var splash := LoadingSplash.new()
	add_child(splash)
	splash.district_chosen.connect(_on_district_chosen)
	splash.open_district_picker()
	await _frames(4)

	_check_rows_match_the_enum(splash)
	await _check_every_theme_is_reachable(splash)

	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _on_district_chosen(theme_id: int) -> void:
	_chosen.append(theme_id)


## The rows are the enum, not a list beside it. A picker that has stopped deriving from
## DistrictTheme loses the newest theme silently, which is how this started.
func _check_rows_match_the_enum(splash: LoadingSplash) -> void:
	var rows := splash.theme_rows()
	if rows.size() != DistrictTheme.COUNT:
		_fail("FAIL the picker has %d rows for %d themes" % [rows.size(), DistrictTheme.COUNT])
		return
	print("OK the picker offers one row per DistrictTheme (%d)" % rows.size())


func _check_every_theme_is_reachable(splash: LoadingSplash) -> void:
	var view := get_viewport().get_visible_rect()
	for theme_id in range(DistrictTheme.COUNT):
		var name := DistrictTheme.make(theme_id).display_name
		var btn := splash.theme_button(theme_id)
		if btn == null:
			_fail("FAIL no picker row for theme %d (%s)" % [theme_id, name])
			continue
		if not btn.text.begins_with(name):
			_fail("FAIL the row for theme %d reads '%s', not %s" % [theme_id, btn.text, name])
			continue

		splash.reveal_theme_button(theme_id)
		await _frames(2)
		var rect := btn.get_global_rect()
		## Laid out is not the same as clickable: the list is clipped to the panel, and the
		## panel is clipped to the window.
		var clip := splash.theme_list_rect()
		if not clip.encloses(rect):
			_fail(
				"FAIL %s sits at %s, outside the %s the picker draws its rows in"
				% [name, rect, clip]
			)
			continue
		if not view.encloses(rect):
			_fail("FAIL %s sits at %s, off a %s viewport" % [name, rect, view])
			continue

		var before := _chosen.size()
		btn.pressed.emit()
		if _chosen.size() != before + 1:
			_fail("FAIL pressing %s reported no choice at all" % name)
			continue
		if _chosen[-1] != theme_id:
			_fail("FAIL pressing %s chose theme %d" % [name, _chosen[-1]])
			continue
		print("OK %-22s row at %s, scrolls into view, hops to theme %d" % [name, rect, theme_id])


func _frames(count: int) -> void:
	for _i in range(count):
		await get_tree().process_frame
