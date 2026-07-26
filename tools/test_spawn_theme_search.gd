## Verifies theme parsing + nearest-coord search used by the start-screen picker.
extends SceneTree


func _initialize() -> void:
	var failed := false
	if DistrictTheme.parse_theme_id("hill") != DistrictTheme.HILL:
		push_error("FAIL parse hill")
		failed = true
	if DistrictTheme.parse_theme_id("graveyard") != DistrictTheme.GRAVEYARD:
		push_error("FAIL parse graveyard")
		failed = true
	if DistrictTheme.parse_theme_id("cemetery") != DistrictTheme.GRAVEYARD:
		push_error("FAIL parse cemetery")
		failed = true
	if DistrictTheme.parse_theme_id("Core High-Rise") != DistrictTheme.CORE_HIGHRISE:
		push_error("FAIL parse Core High-Rise")
		failed = true
	if DistrictTheme.parse_theme_id("5") != DistrictTheme.HILL:
		push_error("FAIL parse id 5")
		failed = true
	if DistrictTheme.parse_theme_id("6") != DistrictTheme.GRAVEYARD:
		push_error("FAIL parse id 6")
		failed = true

	var seed := 42
	var core := DistrictTheme.find_coord_for_theme(seed, DistrictTheme.CORE_HIGHRISE)
	if core != Vector2i.ZERO:
		push_error("FAIL core spawn should be origin, got %s" % core)
		failed = true
	if DistrictTheme.for_district(seed, core).id != DistrictTheme.CORE_HIGHRISE:
		push_error("FAIL origin is not Core")
		failed = true

	for theme_id in range(DistrictTheme.COUNT):
		var coord := DistrictTheme.find_coord_for_theme(seed, theme_id)
		var found := DistrictTheme.for_district(seed, coord)
		if found.id != theme_id:
			push_error(
				"FAIL search for %s returned %s at %s"
				% [DistrictTheme.make(theme_id).display_name, found.display_name, coord]
			)
			failed = true
			continue
		## Nearest: no closer tile of the same theme.
		var ring := maxi(absi(coord.x), absi(coord.y))
		var closer := false
		for r in range(0, ring):
			for cz in range(-r, r + 1):
				for cx in range(-r, r + 1):
					if maxi(absi(cx), absi(cz)) != r:
						continue
					if DistrictTheme.for_district(seed, Vector2i(cx, cz)).id == theme_id:
						closer = true
		if closer:
			push_error("FAIL %s at %s is not the nearest" % [found.display_name, coord])
			failed = true
		print("OK %s → %s (ring %d)" % [found.display_name, coord, ring])

	if failed:
		print("RESULT: FAILED")
		quit(1)
	else:
		print("RESULT: OK")
		quit(0)
