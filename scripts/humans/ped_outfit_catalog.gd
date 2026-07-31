## Catalog of precomposed MH/MPFB outfit GLBs (body + garments), split into disjoint faction
## pools at load time so civilian and hostile gear can never be drawn from the same list.
class_name PedOutfitCatalog
extends RefCounted

const CATALOG_PATH := "res://assets/humans/outfits/catalog.json"
const FALLBACK_MALE := "res://assets/humans/male_base.glb"
const FALLBACK_FEMALE := "res://assets/humans/female_base.glb"
## The nude bases carry the same skin material the outfit exporter writes.
const FALLBACK_MALE_SKIN_MATERIAL := "male_skin"
const FALLBACK_FEMALE_SKIN_MATERIAL := "female_skin"
## Variant id the nude fallback reports, so a save can name it and get it back.
const FALLBACK_VARIANT_ID := "fallback_nude"

## Every tag the exporter may write, mapped to the pool it feeds. A tag that is not registered
## here rejects the whole entry, so a newly invented hostile tag cannot reach any pool until it
## is classified — it can never fall through into the civilian pool by omission.
const TAG_FACTIONS: Dictionary[String, int] = {
	"casual": PedOutfit.Faction.CIVILIAN,
	"work": PedOutfit.Faction.CIVILIAN,
	"elegant": PedOutfit.Faction.CIVILIAN,
	"sport": PedOutfit.Faction.CIVILIAN,
	"bandit": PedOutfit.Faction.HOSTILE,
}

static var _entries: Array[Dictionary] = []
static var _civilian: Array[Dictionary] = []
static var _hostile: Array[Dictionary] = []
static var _loaded: bool = false


static func reload() -> void:
	reload_from(CATALOG_PATH)


## Load a specific catalog file. Production always uses CATALOG_PATH; the faction tests point
## this at a fixture so the hostile pool can be exercised before hostile outfits are exported.
static func reload_from(path: String) -> void:
	_entries.clear()
	_civilian.clear()
	_hostile.clear()
	_loaded = false
	_load(path)


static func ensure_loaded() -> void:
	if _loaded:
		return
	_load(CATALOG_PATH)


static func count() -> int:
	ensure_loaded()
	return _entries.size()


static func count_for(faction: PedOutfit.Faction) -> int:
	ensure_loaded()
	return _pool_for(faction).size()


## Every catalog outfit in file order, with deterministic skins — for boot warm-up and the
## look-inspection tool, which both need the whole set rather than a random pick.
static func all_outfits() -> Array[PedOutfit]:
	ensure_loaded()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0
	var out: Array[PedOutfit] = []
	for entry in _entries:
		out.append(_outfit_from(entry, rng))
	return out


## Outfits of one faction in file order with deterministic skins, for per-pool inspection.
static func outfits_for_faction(faction: PedOutfit.Faction) -> Array[PedOutfit]:
	ensure_loaded()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0
	var out: Array[PedOutfit] = []
	for entry in _pool_for(faction):
		out.append(_outfit_from(entry, rng))
	return out


## Callers must name the pool they want. There is no implicit default, and _civilian never
## holds a hostile entry, so a civilian or player spawn structurally cannot draw hostile gear.
static func pick(rng: RandomNumberGenerator, female: bool, faction: PedOutfit.Faction) -> PedOutfit:
	ensure_loaded()
	var matching: Array[Dictionary] = []
	for e in _pool_for(faction):
		if bool(e["female"]) == female:
			matching.append(e)
	if matching.is_empty():
		return _fallback(rng, female, faction)
	return _outfit_from(matching[rng.randi_range(0, matching.size() - 1)], rng)


## The exact outfit a save named, with a deterministic skin the caller then overwrites with the
## saved one. Null when the catalog no longer carries that id, which a restore reports rather than
## papering over with a different look.
static func by_variant_id(id: String, female: bool) -> PedOutfit:
	ensure_loaded()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0
	if id == FALLBACK_VARIANT_ID:
		return _fallback(rng, female, PedOutfit.Faction.CIVILIAN)
	for entry in _entries:
		if String(entry["id"]) == id:
			return _outfit_from(entry, rng)
	return null


static func _load(path: String) -> void:
	_loaded = true
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		push_warning("PedOutfitCatalog: missing %s — using nude base fallbacks" % path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("PedOutfitCatalog: cannot open %s" % path)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_ARRAY:
		push_error("PedOutfitCatalog: %s root must be an array" % path)
		return
	for item: Variant in parsed as Array:
		if typeof(item) != TYPE_DICTIONARY:
			push_error("PedOutfitCatalog: %s holds a non-object entry" % path)
			continue
		var entry := _validate(item as Dictionary, path)
		if entry.is_empty():
			continue
		_entries.append(entry)
		_pool_for(entry["faction"] as PedOutfit.Faction).append(entry)
	print(
		"PedOutfitCatalog: loaded %d outfits (%d civilian, %d hostile)"
		% [_entries.size(), _civilian.size(), _hostile.size()]
	)


## Returns a normalised entry, or an empty dictionary when the raw entry is unusable. Every
## rejection is an error: catalog.json is generated, so a malformed entry means the exporter
## and the runtime have drifted apart and silently spawning something else would hide that.
static func _validate(raw: Dictionary, path: String) -> Dictionary:
	var id := String(raw.get("id", ""))
	if id == "":
		push_error("PedOutfitCatalog: %s has an entry without an id" % path)
		return {}
	var scene_path := String(raw.get("path", ""))
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		push_error("PedOutfitCatalog: outfit %s points at missing scene %s" % [id, scene_path])
		return {}
	var skin_material := String(raw.get("skin_material", ""))
	if skin_material == "":
		push_error("PedOutfitCatalog: outfit %s has no skin_material — re-run the exporter" % id)
		return {}
	var raw_tags: Variant = raw.get("tags", null)
	if typeof(raw_tags) != TYPE_ARRAY or (raw_tags as Array).is_empty():
		push_error("PedOutfitCatalog: outfit %s has no tags" % id)
		return {}
	var faction := PedOutfit.Faction.CIVILIAN
	var faction_seen := false
	for tag: Variant in raw_tags as Array:
		var name := String(tag)
		if not TAG_FACTIONS.has(name):
			push_error(
				(
					"PedOutfitCatalog: outfit %s carries unregistered tag '%s' — add it to "
					+ "TAG_FACTIONS with its faction"
				)
				% [id, name]
			)
			return {}
		var tag_faction := TAG_FACTIONS[name] as PedOutfit.Faction
		if faction_seen and tag_faction != faction:
			push_error("PedOutfitCatalog: outfit %s mixes civilian and hostile tags" % id)
			return {}
		faction = tag_faction
		faction_seen = true
	var garments := PackedStringArray()
	var raw_garments: Variant = raw.get("garment_materials", null)
	if typeof(raw_garments) != TYPE_ARRAY:
		push_error("PedOutfitCatalog: outfit %s has no garment_materials array" % id)
		return {}
	for garment: Variant in raw_garments as Array:
		garments.append(String(garment))
	var proxy_color := Color(0.4, 0.4, 0.45)
	var raw_proxy: Variant = raw.get("proxy_color", null)
	if typeof(raw_proxy) != TYPE_ARRAY or (raw_proxy as Array).size() < 3:
		push_error("PedOutfitCatalog: outfit %s has no proxy_color triple" % id)
		return {}
	var proxy: Array = raw_proxy
	proxy_color = Color(float(proxy[0]), float(proxy[1]), float(proxy[2]))
	return {
		"id": id,
		"path": scene_path,
		"female": bool(raw.get("female", false)),
		"faction": int(faction),
		"skin_material": skin_material,
		"garment_materials": garments,
		"proxy_color": proxy_color,
	}


static func _pool_for(faction: PedOutfit.Faction) -> Array[Dictionary]:
	match faction:
		PedOutfit.Faction.CIVILIAN:
			return _civilian
		PedOutfit.Faction.HOSTILE:
			return _hostile
	push_error("PedOutfitCatalog: unhandled faction %d" % int(faction))
	return []


static func _outfit_from(entry: Dictionary, rng: RandomNumberGenerator) -> PedOutfit:
	var outfit := PedOutfit.new()
	outfit.variant_id = entry["id"] as String
	outfit.scene_path = entry["path"] as String
	outfit.female = entry["female"] as bool
	outfit.faction = entry["faction"] as PedOutfit.Faction
	outfit.skin_material = entry["skin_material"] as String
	outfit.garment_materials = entry["garment_materials"] as PackedStringArray
	outfit.proxy_color = entry["proxy_color"] as Color
	outfit.skin = _pick_skin(rng)
	return outfit


## Nude base body. Expected before the first outfit export (and in CI), which is why the
## civilian case is only a fallback — an empty hostile pool means a missing export instead.
static func _fallback(
	rng: RandomNumberGenerator, female: bool, faction: PedOutfit.Faction
) -> PedOutfit:
	if faction == PedOutfit.Faction.HOSTILE:
		push_error(
			"PedOutfitCatalog: no hostile outfit for %s — export one before spawning hostiles"
			% ("female" if female else "male")
		)
	var outfit := PedOutfit.new()
	outfit.female = female
	outfit.faction = faction
	outfit.variant_id = FALLBACK_VARIANT_ID
	outfit.scene_path = FALLBACK_FEMALE if female else FALLBACK_MALE
	outfit.skin_material = (
		FALLBACK_FEMALE_SKIN_MATERIAL if female else FALLBACK_MALE_SKIN_MATERIAL
	)
	outfit.skin = _pick_skin(rng)
	outfit.proxy_color = Color(0.45, 0.40, 0.55) if female else Color(0.35, 0.42, 0.55)
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
