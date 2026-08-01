## Builds the curated Mandelbrot spot catalog that fractal panels mark for lock-on.
##
## The catalog is committed in `assets/gamedata.json` (`mandelbrot_spots.spots`); this tool is how
## that data was produced and how it is regenerated. Nothing in the game searches at runtime.
##
## Method: start from the classic named locations (seahorse / elephant / triple spiral / the
## Misiurewicz points / mini-set islands), then beam-search downward. Every step renders candidate
## sub-windows with NativeMandelbrot and keeps the ones that score best on "lots of colours in good
## amounts": some interior for contrast, a wide spread of escape times, and no single band owning
## the frame. Windows are emitted only inside the zoom budget the morph can afford. Conjugate
## mirrors of each hit are kept too — Mandelbrot is symmetric and each mirror is a free distinct
## postcard.
##
## Run: powershell -File tools\run_test.ps1 gen_mandelbrot_spots -TimeoutSec 900 -KeepLog
extends Node

## Zoom budget. Panels bake 1000² and Create bakes the whole plaza grid, so a spot has to look
## rich without pushing iteration counts into the seconds.
const SCALE_MAX := 1e-4
const SCALE_MIN := 1e-8
## Hard reject past this even if a probe somehow lands there (plan floor).
const SCALE_HARD_MIN := 1e-9
## Default panel window (−0.5, 0) ± 1.5 — marker must be clickable before autozoom.
const VIEW_CX := -0.5
const VIEW_CY := 0.0
const VIEW_HALF := 1.5
const PROBE := 64
const OFFSETS: Array[Vector2] = [
	Vector2(0.0, 0.0),
	Vector2(0.55, 0.0),
	Vector2(-0.55, 0.0),
	Vector2(0.0, 0.55),
	Vector2(0.0, -0.55),
	Vector2(0.4, 0.4),
	Vector2(-0.4, 0.4),
	Vector2(0.4, -0.4),
	Vector2(-0.4, -0.4),
	Vector2(0.7, 0.2),
	Vector2(-0.7, 0.2),
	Vector2(0.2, 0.7),
	Vector2(0.2, -0.7),
]
const BEAM := 8
const ZOOM_PER_STEP := 0.32
const INTERIOR_LO := 0.01
const INTERIOR_HI := 0.72
const BANDS := 24
const WANT_TOTAL := 104
const START_SCALES: Array[float] = [8.0e-3, 2.5e-3, 8.0e-4]

const SEEDS: Array[Dictionary] = [
	{"name": "Seahorse Valley", "cx": -0.745, "cy": 0.113},
	{"name": "Seahorse Tail", "cx": -0.74543, "cy": 0.11301},
	{"name": "Misiurewicz M8", "cx": -0.743643887037151, "cy": 0.131825904205312},
	{"name": "Elephant Valley", "cx": 0.275, "cy": 0.007},
	{"name": "Elephant Herd", "cx": 0.2894, "cy": 0.01258},
	{"name": "Triple Spiral", "cx": -0.088, "cy": 0.654},
	{"name": "Triple Spiral Rim", "cx": -0.15625, "cy": 0.653411},
	{"name": "Scepter Spiral", "cx": -0.1592, "cy": -1.0317},
	{"name": "Mini Island", "cx": -1.25066, "cy": 0.02012},
	{"name": "Antenna Island", "cx": -1.7689, "cy": 0.0},
	{"name": "Feigenbaum", "cx": -1.401155, "cy": 0.0},
	{"name": "North Cusp", "cx": -0.125, "cy": 0.649519052838329},
	{"name": "Quarter Bulb", "cx": 0.2925, "cy": 0.4795},
	{"name": "West Filament", "cx": -1.543577, "cy": 0.0},
	{"name": "Upper Tendril", "cx": -0.10109, "cy": 0.95628},
	{"name": "Lower Spiral", "cx": -0.5626, "cy": -0.6428},
	{"name": "San Marco", "cx": -0.75, "cy": 0.1},
	{"name": "Seahorse Deep", "cx": -0.748, "cy": 0.1},
	{"name": "East Needle", "cx": 0.37, "cy": 0.16},
	{"name": "East Needle B", "cx": 0.36, "cy": 0.1},
	{"name": "Period 3 Bulb", "cx": -0.125, "cy": 0.744},
	{"name": "Period 4 Bulb", "cx": 0.375, "cy": 0.215},
	{"name": "Scepter Tip", "cx": -0.16, "cy": -1.025},
	{"name": "Julia Island", "cx": -0.1528, "cy": 1.0397},
	{"name": "Double Spiral", "cx": -0.745428, "cy": 0.113009},
	{"name": "Valley Floor", "cx": -0.739, "cy": 0.175},
	{"name": "Filament Knot", "cx": -0.16, "cy": 1.04},
	{"name": "Cardioid Tip", "cx": 0.25, "cy": 0.0},
	{"name": "West Bulb Edge", "cx": -1.0, "cy": 0.25},
	{"name": "South Antenna", "cx": -0.75, "cy": -0.15},
]

var _eng: Object = null
var _mu_interior := 0xFFFF
var _mu_scale := 64.0


func _ready() -> void:
	_eng = ClassDB.instantiate("NativeMandelbrot")
	if _eng == null or not _eng.has_method("render_smooth_mu_u16"):
		push_error("gen_mandelbrot_spots: NativeMandelbrot unavailable")
		print("RESULT: FAILED")
		get_tree().quit(1)
		return
	_mu_interior = int(_eng.call("mu_interior_u16"))
	_mu_scale = float(_eng.call("mu_u16_scale"))

	var found: Array[Dictionary] = []
	for seed_i in range(SEEDS.size()):
		var seed_entry: Dictionary = SEEDS[seed_i]
		found.append_array(_dive(seed_entry))
		print(
			"seed %d/%d %s -> %d spots"
			% [seed_i + 1, SEEDS.size(), str(seed_entry["name"]), found.size()]
		)
	found = _with_conjugates(found)
	found = _filter_visible(found)
	found = _dedupe(found)
	found.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return float(b["score"]) < float(a["score"])
	)
	if found.size() > WANT_TOTAL:
		found.resize(WANT_TOTAL)
	_print_table(found)
	if found.size() >= 80:
		_write_gamedata_spots(found)
	print("RESULT: %s" % ("OK" if found.size() >= 80 else "FAILED"))
	get_tree().quit(0 if found.size() >= 80 else 1)


func _dive(seed_entry: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for start_scale: float in START_SCALES:
		var beam: Array[Dictionary] = [
			{
				"cx": float(seed_entry["cx"]),
				"cy": float(seed_entry["cy"]),
				"scale": start_scale,
				"score": 0.0,
			}
		]
		while not beam.is_empty():
			var next: Array[Dictionary] = []
			for parent: Dictionary in beam:
				var scale := float(parent["scale"]) * ZOOM_PER_STEP
				if scale < SCALE_MIN:
					continue
				for off: Vector2 in OFFSETS:
					var cx := float(parent["cx"]) + off.x * float(parent["scale"])
					var cy := float(parent["cy"]) + off.y * float(parent["scale"])
					if not _in_default_view(cx, cy):
						continue
					var score := _score(cx, cy, scale)
					if score <= 0.0:
						continue
					next.append({"cx": cx, "cy": cy, "scale": scale, "score": score})
			if next.is_empty():
				break
			next.sort_custom(
				func(a: Dictionary, b: Dictionary) -> bool:
					return float(b["score"]) < float(a["score"])
			)
			if next.size() > BEAM:
				next.resize(BEAM)
			for cand: Dictionary in next:
				var s := float(cand["scale"])
				if s <= SCALE_MAX and s >= SCALE_HARD_MIN:
					var named := cand.duplicate()
					named["name"] = str(seed_entry["name"])
					out.append(named)
			beam = next
	return out


func _score(cx: float, cy: float, scale: float) -> float:
	var iters := 256
	if _eng.has_method("recommended_iters"):
		iters = int(_eng.call("recommended_iters", scale))
	var bytes: PackedByteArray = _eng.call(
		"render_smooth_mu_u16", _dec(cx), _dec(cy), _dec(scale), PROBE, PROBE, iters
	) as PackedByteArray
	var n := PROBE * PROBE
	if bytes.size() != n * 2:
		return 0.0
	var interior := 0
	var mus := PackedFloat32Array()
	mus.resize(n)
	var mu_min := INF
	var mu_max := -INF
	for i in range(n):
		var packed := int(bytes[i * 2]) | (int(bytes[i * 2 + 1]) << 8)
		if packed == _mu_interior:
			interior += 1
			mus[i] = -1.0
			continue
		var mu := float(packed) / _mu_scale
		mus[i] = mu
		mu_min = minf(mu_min, mu)
		mu_max = maxf(mu_max, mu)
	var exterior := n - interior
	if exterior < 12 or not is_finite(mu_min) or mu_max - mu_min <= 1e-6:
		return 0.0
	var interior_frac := float(interior) / float(n)
	if interior_frac < INTERIOR_LO or interior_frac > INTERIOR_HI:
		return 0.0

	var hist := PackedInt32Array()
	hist.resize(BANDS)
	hist.fill(0)
	var span := mu_max - mu_min
	for i in range(n):
		var mu2: float = mus[i]
		if mu2 < 0.0:
			continue
		var t := sqrt(clampf((mu2 - mu_min) / span, 0.0, 1.0))
		var bi := clampi(int(floor(t * float(BANDS))), 0, BANDS - 1)
		hist[bi] += 1
	var used := 0
	var entropy := 0.0
	var biggest := 0
	for b in range(BANDS):
		var c := int(hist[b])
		if c <= 0:
			continue
		used += 1
		biggest = maxi(biggest, c)
		var p := float(c) / float(exterior)
		entropy -= p * log(p)
	var spread := entropy / log(float(BANDS))
	var coverage := float(used) / float(BANDS)
	var dominance := float(biggest) / float(exterior)
	var contrast := 1.0 - absf(interior_frac - 0.2) / 0.4
	return spread * 0.45 + coverage * 0.3 + (1.0 - dominance) * 0.15 + maxf(contrast, 0.0) * 0.1


func _with_conjugates(spots: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = spots.duplicate()
	for s: Dictionary in spots:
		var cy := float(s["cy"])
		if absf(cy) < 1e-9:
			continue
		var mir := s.duplicate()
		mir["cy"] = -cy
		mir["name"] = "%s*" % str(s["name"])
		out.append(mir)
	return out


func _filter_visible(spots: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Dictionary in spots:
		if _in_default_view(float(s["cx"]), float(s["cy"])):
			out.append(s)
	return out


static func _in_default_view(cx: float, cy: float) -> bool:
	return (
		absf(cx - VIEW_CX) <= VIEW_HALF + 1e-9
		and absf(cy - VIEW_CY) <= VIEW_HALF + 1e-9
	)


func _dedupe(spots: Array[Dictionary]) -> Array[Dictionary]:
	var sorted := spots.duplicate()
	sorted.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return float(b["score"]) < float(a["score"])
	)
	var kept: Array[Dictionary] = []
	for cand: Dictionary in sorted:
		var clash := false
		for k: Dictionary in kept:
			## Same postcard at nearly the same depth — keep the better score.
			var reach: float = maxf(float(k["scale"]), float(cand["scale"])) * 0.9
			var scale_ratio := (
				maxf(float(k["scale"]), float(cand["scale"]))
				/ maxf(minf(float(k["scale"]), float(cand["scale"])), 1e-40)
			)
			if (
				scale_ratio < 2.5
				and absf(float(k["cx"]) - float(cand["cx"])) < reach
				and absf(float(k["cy"]) - float(cand["cy"])) < reach
			):
				clash = true
				break
		if not clash:
			kept.append(cand)
	return kept


func _print_table(spots: Array[Dictionary]) -> void:
	print("--- BEGIN SPOT TABLE (%d) ---" % spots.size())
	for s: Dictionary in spots:
		print(
			'\t{"name": "%s", "cx": "%s", "cy": "%s", "scale": "%s"},'
			% [
				str(s["name"]),
				_dec(float(s["cx"])),
				_dec(float(s["cy"])),
				_dec(float(s["scale"])),
			]
		)
	print("--- END SPOT TABLE ---")


func _write_gamedata_spots(spots: Array[Dictionary]) -> void:
	const PATH := "res://assets/gamedata.json"
	var raw := FileAccess.get_file_as_string(PATH)
	if raw.is_empty():
		push_error("gen_mandelbrot_spots: cannot read %s" % PATH)
		assert(false, "gen_mandelbrot_spots: missing gamedata.json")
		return
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("gen_mandelbrot_spots: %s root must be an object" % PATH)
		assert(false, "gen_mandelbrot_spots: bad gamedata root")
		return
	var doc: Dictionary = parsed
	var sec: Variant = doc.get("mandelbrot_spots", {})
	if typeof(sec) != TYPE_DICTIONARY:
		sec = {}
	var rows: Array = []
	for s: Dictionary in spots:
		rows.append(
			{
				"name": str(s["name"]),
				"cx": _dec(float(s["cx"])),
				"cy": _dec(float(s["cy"])),
				"scale": _dec(float(s["scale"])),
			}
		)
	var section: Dictionary = (sec as Dictionary).duplicate(true)
	section["spots"] = rows
	doc["mandelbrot_spots"] = section
	var out := JSON.stringify(doc, "  ")
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("gen_mandelbrot_spots: cannot write %s" % PATH)
		assert(false, "gen_mandelbrot_spots: write failed")
		return
	f.store_string(out + "\n")
	f.close()
	print("Wrote %d spots → %s" % [rows.size(), PATH])


static func _dec(x: float) -> String:
	var s := "%.20f" % x
	if s.contains("."):
		s = s.rstrip("0")
		if s.ends_with("."):
			s += "0"
	return s
