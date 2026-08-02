## Headless: every keep gets one stair flight per pair of floored storeys.
##
## A keep one flight short has a storey nothing can walk to. `CastleComposer._pick_stair_slot`
## takes lanes out of a shuffled pool of eight, and a flight grown by its margin eats most of
## one face plus both corners of the faces beside it — so on an ordinary plate the pool really
## can run dry. The seed sweep in test_castle_district only affords twenty full district bakes,
## which is far too coarse to catch a lane pool that fails on a fraction of keeps.
##
## This drives the planner alone: build the keep rect the composer would have rolled, plan its
## circulation, count the flights. No terrain, no bake, so thousands of keeps fit in a second.
extends Node

const CastleComposerScript := preload("res://scripts/city/castle_composer.gd")

## Keeps to plan. Well past the point where a percent-level failure rate is certain to show.
const SEEDS := 40000
const COURTYARD_Y := 24


func _ready() -> void:
	var short_keeps := 0
	var first_failure := ""
	var storey_counts: Dictionary[int, int] = {}
	var flights := 0
	for seed_i in range(SEEDS):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_i
		var comp: CastleComposer = CastleComposerScript.new()
		comp.rng = rng
		var layout := CastleLayout.new()
		layout.courtyard_y = COURTYARD_Y
		## The four gate faces the bailey can present, one per quarter of the sweep.
		var faces: Array[Vector2i] = [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
		]
		layout.gate_dir = faces[seed_i % faces.size()]
		var kw := rng.randi_range(CastleComposer.KEEP_W_MIN, CastleComposer.KEEP_W_MAX)
		var kd := rng.randi_range(CastleComposer.KEEP_D_MIN, CastleComposer.KEEP_D_MAX)
		layout.keep_rect = Rect2i(100, 100, kw, kd)
		layout.keep_plate_rect = layout.keep_rect.grow(-CastleComposer.KEEP_WALL_T)
		comp.call("_plan_keep_circulation", layout)
		var storeys := int(comp.get("_keep_storeys"))
		storey_counts[storeys] = int(storey_counts.get(storeys, 0)) + 1
		## One flight per pair of consecutive floored storeys. The storey above the great hall
		## carries no slab, so it is not one of them — and the crown ramp that makes up the
		## count in `test_castle_district` belongs to the bailey, not to this plate.
		var want := storeys - 2
		flights += layout.keep_stairs.size()
		if layout.keep_stairs.size() != want:
			short_keeps += 1
			if first_failure.is_empty():
				first_failure = (
					"seed %d: %s plate, %d storeys (hall %d) got %d of %d flights"
					% [
						seed_i,
						layout.keep_plate_rect.size,
						storeys,
						layout.keep_hall_storey,
						layout.keep_stairs.size(),
						want,
					]
				)
			continue
		if _lanes_overlap(layout):
			push_error("FAIL seed %d: two keep flights claim the same columns" % seed_i)
			print("RESULT: FAILED")
			get_tree().quit(1)
			return
		if not _lanes_on_plate(layout):
			push_error("FAIL seed %d: a keep flight hangs off the plate" % seed_i)
			print("RESULT: FAILED")
			get_tree().quit(1)
			return
	var tally: Array[String] = []
	for storeys: int in storey_counts.keys():
		tally.append("%d storeys x%d" % [storeys, storey_counts[storeys]])
	tally.sort()
	print("keeps: %d planned, %d flights (%s)" % [SEEDS, flights, ", ".join(tally)])
	if short_keeps > 0:
		push_error(
			"FAIL %d of %d keeps are a flight short — a storey nothing can reach. First: %s"
			% [short_keeps, SEEDS, first_failure]
		)
		print("RESULT: FAILED")
		get_tree().quit(1)
		return
	print("RESULT: OK")
	get_tree().quit(0)


## Lanes claim their margin, so two flights sharing columns would put a parapet through a tread.
func _lanes_overlap(layout: CastleLayout) -> bool:
	var claims: Array[Rect2i] = []
	for st: CastleStair in layout.keep_stairs:
		var claim := st.footprint().grow(CastleComposer.LANE_MARGIN)
		for other: Rect2i in claims:
			if other.intersects(claim):
				return true
		claims.append(claim)
	return false


func _lanes_on_plate(layout: CastleLayout) -> bool:
	for st: CastleStair in layout.keep_stairs:
		if not layout.keep_plate_rect.encloses(st.footprint()):
			return false
	return true
