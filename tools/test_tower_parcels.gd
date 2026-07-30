## Assert CORE tower parcels are multi-cell (~26–56 m) and secondaries don't double-build.
##
## Two cells is the floor: a tower needs ~24 m across for a core plus usable floor depth
## (core-to-glass caps out at 12–15 m for daylight), and one 14 m cell cannot supply it.
## Run: powershell -File tools\run_test.ps1 test_tower_parcels
extends Node

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_check_core_parcels()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _check_core_parcels() -> void:
	var theme: DistrictTheme = DistrictTheme.make(DistrictTheme.CORE_HIGHRISE)
	var planner := DistrictPlanner.new()
	planner.theme = theme
	planner.build(
		DistrictCoord.SIZE_X_VOX,
		DistrictCoord.SIZE_Z_VOX,
		DistrictCoord.district_seed(42, Vector2i(0, 0)),
		DistrictCoord.CELL_SIZE,
		Vector2i(0, 0)
	)
	if planner.tower_parcels.is_empty():
		_fail("FAIL expected at least one tower parcel in CORE_HIGHRISE")
		return
	var cell_m := float(DistrictCoord.CELL_SIZE) * 0.5
	var seen_anchor := {}
	for rect in planner.tower_parcels:
		if rect.size.x < 2 or rect.size.y < 2:
			_fail("FAIL parcel too small %s" % str(rect))
			continue
		if rect.size.x > 4 or rect.size.y > 4:
			_fail("FAIL parcel too large %s" % str(rect))
			continue
		## Rectangles are allowed — square-only packing stranded a third of downtown as
		## lone cells — so the short side is what has to clear the tower minimum.
		var short_m := float(mini(rect.size.x, rect.size.y)) * cell_m
		## After 1 m setback each side the plate is ~short_m - 2 m, so 28 m is the floor.
		if short_m < 27.0 or short_m > 57.0:
			_fail("FAIL parcel short side %.1f m out of 28–56 m range (%s)" % [short_m, str(rect)])
		if short_m - 2.0 < DistrictGenerator.MIN_TOWER_SIDE_M:
			_fail(
				"FAIL parcel %s plate is %.1f m — under the %.0f m tower minimum"
				% [str(rect), short_m - 2.0, DistrictGenerator.MIN_TOWER_SIDE_M]
			)
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if planner.tag_at(x, z) != LandUse.CORE_LOT:
					_fail("FAIL parcel cell %d,%d is not CORE_LOT" % [x, z])
		var key := "%d,%d" % [rect.position.x, rect.position.y]
		if seen_anchor.has(key):
			_fail("FAIL duplicate anchor %s" % key)
		seen_anchor[key] = true
		if not planner.is_tower_parcel_anchor(rect.position.x, rect.position.y):
			_fail("FAIL anchor helper missed %s" % key)
		## One secondary must exist and must not be an anchor.
		var sx := rect.position.x + 1
		var sz := rect.position.y
		if not planner.is_tower_parcel_secondary(sx, sz):
			_fail("FAIL expected secondary at %d,%d" % [sx, sz])
		if planner.is_tower_parcel_anchor(sx, sz):
			_fail("FAIL secondary reported as anchor at %d,%d" % [sx, sz])
	## Parcels must not overlap.
	for i in range(planner.tower_parcels.size()):
		for j in range(i + 1, planner.tower_parcels.size()):
			if planner.tower_parcels[i].intersects(planner.tower_parcels[j]):
				_fail(
					"FAIL overlapping parcels %s vs %s"
					% [str(planner.tower_parcels[i]), str(planner.tower_parcels[j])]
				)
	print(
		"tower_parcels=", planner.tower_parcels.size(),
		" sample=", planner.tower_parcels[0] if not planner.tower_parcels.is_empty() else Rect2i()
	)
