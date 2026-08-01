## Curated Mandelbrot windows for fractal-panel lock-on markers.
##
## Each entry is a centre + half-extent that fits the Create morph budget and is visible on the
## default panel view (−0.5, 0) ± 1.5 so a marker can sit on it before autozoom. Regenerated /
## expanded by `tools/gen_mandelbrot_spots.gd` into `assets/gamedata.json`; the game only samples
## that table through GameData.
class_name MandelbrotSpots
extends RefCounted

const GameDataScript := preload("res://scripts/city/game_data.gd")

## Locked half-extent must sit in this band (plan budget).
static var SCALE_MAX: float = 1.0e-4
static var SCALE_MIN: float = 1.0e-8
static var DEFAULT_VIEW_CX: float = -0.5
static var DEFAULT_VIEW_CY: float = 0.0
static var DEFAULT_VIEW_HALF: float = 1.5

static var _spots: Array = []
static var _loaded: bool = false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var sec: Dictionary = GameDataScript.mandelbrot_spots()
	SCALE_MAX = float(sec.get("scale_max", 1.0e-4))
	SCALE_MIN = float(sec.get("scale_min", 1.0e-8))
	var view: Dictionary = sec.get("default_view", {}) as Dictionary
	DEFAULT_VIEW_CX = float(view.get("cx", -0.5))
	DEFAULT_VIEW_CY = float(view.get("cy", 0.0))
	DEFAULT_VIEW_HALF = float(view.get("half", 1.5))
	_spots = GameDataScript.mandelbrot_spot_list()


static func spot_count() -> int:
	ensure_loaded()
	return _spots.size()


static func spot_at(index: int) -> Dictionary:
	ensure_loaded()
	if index < 0 or index >= _spots.size():
		push_error("MandelbrotSpots.spot_at: %d is out of range" % index)
		return {}
	return _spots[index] as Dictionary


## Four distinct catalog entries for one fractal district. Deterministic in `district_seed`.
static func pick_for_district(district_seed: int, count: int = 4) -> Array[Dictionary]:
	ensure_loaded()
	var n := _spots.size()
	if n < count:
		push_error("MandelbrotSpots.pick_for_district: need %d spots, have %d" % [count, n])
		return []
	var order: Array[int] = []
	order.resize(n)
	for i in range(n):
		order[i] = i
	var rng := RandomNumberGenerator.new()
	rng.seed = district_seed ^ 0x4D414E44
	## Fisher–Yates — same four every time this tile is streamed.
	for i in range(n - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := order[i]
		order[i] = order[j]
		order[j] = tmp
	var out: Array[Dictionary] = []
	for k in range(count):
		out.append(_spots[order[k]] as Dictionary)
	return out


## Fractal UV [0,1]² of a centre on the default panel view.
static func default_view_uv(cx_hp: String, cy_hp: String) -> Vector2:
	ensure_loaded()
	var cx := float(cx_hp)
	var cy := float(cy_hp)
	var u := (cx - (DEFAULT_VIEW_CX - DEFAULT_VIEW_HALF)) / (DEFAULT_VIEW_HALF * 2.0)
	var v := (cy - (DEFAULT_VIEW_CY - DEFAULT_VIEW_HALF)) / (DEFAULT_VIEW_HALF * 2.0)
	return Vector2(clampf(u, 0.0, 1.0), clampf(v, 0.0, 1.0))


static func scale_in_budget(scale_hp: String) -> bool:
	ensure_loaded()
	var s := absf(float(scale_hp))
	return s <= SCALE_MAX + 1e-20 and s >= SCALE_MIN - 1e-20


static func centre_in_default_view(cx_hp: String, cy_hp: String) -> bool:
	ensure_loaded()
	var cx := float(cx_hp)
	var cy := float(cy_hp)
	return (
		absf(cx - DEFAULT_VIEW_CX) <= DEFAULT_VIEW_HALF + 1e-9
		and absf(cy - DEFAULT_VIEW_CY) <= DEFAULT_VIEW_HALF + 1e-9
	)
