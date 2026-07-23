## Catalog of precomposed MH/MPFB outfit GLBs (body + clothes + shoes).
class_name PedOutfitCatalog
extends RefCounted

const CATALOG_PATH := "res://assets/humans/outfits/catalog.json"
const FALLBACK_MALE := "res://assets/humans/male_base.glb"
const FALLBACK_FEMALE := "res://assets/humans/female_base.glb"

static var _entries: Array[Dictionary] = []
static var _loaded: bool = false


static func reload() -> void:
	_entries.clear()
	_loaded = false
	ensure_loaded()


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not ResourceLoader.exists(CATALOG_PATH) and not FileAccess.file_exists(CATALOG_PATH):
		push_warning("PedOutfitCatalog: missing %s — using nude base fallbacks" % CATALOG_PATH)
		return
	var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if f == null:
		push_error("PedOutfitCatalog: cannot open %s" % CATALOG_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_ARRAY:
		push_error("PedOutfitCatalog: catalog.json root must be an array")
		return
	for item in parsed as Array:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = item
		var path := String(d.get("path", ""))
		if path == "" or not ResourceLoader.exists(path):
			push_warning("PedOutfitCatalog: skip missing outfit %s" % path)
			continue
		_entries.append(d)
	print("PedOutfitCatalog: loaded %d outfits" % _entries.size())


static func count() -> int:
	ensure_loaded()
	return _entries.size()


static func pick(rng: RandomNumberGenerator, female: bool) -> PedOutfit:
	ensure_loaded()
	var pool: Array[Dictionary] = []
	for e in _entries:
		if bool(e.get("female", false)) == female:
			pool.append(e)
	var outfit := PedOutfit.new()
	outfit.female = female
	if pool.is_empty():
		outfit.variant_id = "fallback_nude"
		outfit.scene_path = FALLBACK_FEMALE if female else FALLBACK_MALE
		outfit.skin = _pick_skin(rng)
		outfit.proxy_color = Color(0.35, 0.42, 0.55) if not female else Color(0.45, 0.40, 0.55)
		return outfit
	var e2: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	outfit.variant_id = String(e2.get("id", "unknown"))
	outfit.scene_path = String(e2.get("path", ""))
	outfit.skin = _pick_skin(rng)
	var pc: Variant = e2.get("proxy_color", [0.4, 0.4, 0.45])
	if typeof(pc) == TYPE_ARRAY and (pc as Array).size() >= 3:
		var a: Array = pc
		outfit.proxy_color = Color(float(a[0]), float(a[1]), float(a[2]))
	else:
		outfit.proxy_color = Color(0.4, 0.4, 0.45)
	return outfit


static func _pick_skin(rng: RandomNumberGenerator) -> Color:
	const TONES: Array[Color] = [
		Color(0.94, 0.80, 0.70),
		Color(0.86, 0.68, 0.54),
		Color(0.78, 0.58, 0.44),
		Color(0.62, 0.42, 0.30),
		Color(0.45, 0.30, 0.22),
		Color(0.32, 0.22, 0.16),
	]
	return TONES[rng.randi_range(0, TONES.size() - 1)]
