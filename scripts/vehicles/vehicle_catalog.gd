## Catalog of traffic vehicles (procedural primary, Kenney GLB optional fallback).
## Missing catalog or unusable entries are hard errors — no silent stand-ins.
class_name VehicleCatalog
extends RefCounted

const CATALOG_PATH := "res://assets/vehicles/catalog.json"

static var _entries: Array[Dictionary] = []
static var _loaded: bool = false
static var _load_ok: bool = false


static func reload() -> void:
	_entries.clear()
	_loaded = false
	_load_ok = false
	ensure_loaded()


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_ok = false
	_entries.clear()

	if not ResourceLoader.exists(CATALOG_PATH):
		push_error("VehicleCatalog: missing %s" % CATALOG_PATH)
		return

	var f := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if f == null:
		push_error("VehicleCatalog: cannot open %s" % CATALOG_PATH)
		return

	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("VehicleCatalog: invalid JSON root in %s" % CATALOG_PATH)
		return

	var vehicles: Variant = (parsed as Dictionary).get("vehicles", [])
	if typeof(vehicles) != TYPE_ARRAY:
		push_error("VehicleCatalog: 'vehicles' must be an array")
		return

	for item: Variant in vehicles:
		if typeof(item) != TYPE_DICTIONARY:
			push_error("VehicleCatalog: vehicle entry is not an object")
			continue
		var d: Dictionary = item
		var id := str(d.get("id", ""))
		if id == "":
			push_error("VehicleCatalog: entry missing id: %s" % str(d))
			continue

		var source := str(d.get("source", "kenney")).to_lower()
		var path := str(d.get("path", ""))
		var fallback_path := str(d.get("fallback_path", path))
		var profile := str(d.get("profile", id))

		if source == "procedural":
			# Validate profile exists by attempting a dry build is too heavy; check known names.
			if not _is_known_profile(profile):
				push_error("VehicleCatalog: unknown procedural profile '%s' (id=%s)" % [profile, id])
				continue
		elif source == "kenney":
			if path == "":
				push_error("VehicleCatalog: kenney entry '%s' missing path" % id)
				continue
			if not _scene_ok(path, id):
				continue
		else:
			push_error("VehicleCatalog: unknown source '%s' (id=%s)" % [source, id])
			continue

		if fallback_path != "" and not ResourceLoader.exists(fallback_path):
			# Fallback is optional; warn but keep the entry if procedural is primary.
			if source != "procedural":
				push_error("VehicleCatalog: fallback/path missing for id=%s path=%s" % [id, fallback_path])
				continue

		_entries.append({
			"id": id,
			"source": source,
			"profile": profile,
			"path": path,
			"fallback_path": fallback_path,
			"kind": str(d.get("kind", "car")),
			"seat_offsets": d.get("seat_offsets", []),
			"scale": float(d.get("scale", 1.0)),
			"y_offset": float(d.get("y_offset", 0.0)),
			"yaw_fix": float(d.get("yaw_fix", 0.0)),
			"paint": d.get("paint", null),
		})

	if _entries.is_empty():
		push_error("VehicleCatalog: zero usable vehicles after loading %s" % CATALOG_PATH)
		return

	_load_ok = true
	print("VehicleCatalog: loaded %d vehicles" % _entries.size())


static func _is_known_profile(profile: String) -> bool:
	match profile:
		"sedan", "taxi", "police", "sedan_sports", "hatchback_sports", "suv", "suv_luxury", "van", "delivery", "truck":
			return true
		_:
			return false


static func _scene_ok(path: String, id: String) -> bool:
	if not ResourceLoader.exists(path):
		push_error(
			(
				"VehicleCatalog: mesh not importable at %s (id=%s). "
				+ "Open the project once in Godot so .glb/.gltf imports, or fix the path."
			)
			% [path, id]
		)
		return false
	var packed := load(path)
	if not (packed is PackedScene):
		push_error(
			"VehicleCatalog: %s loaded as %s, expected PackedScene (id=%s)"
			% [path, packed.get_class() if packed else "null", id]
		)
		return false
	return true


static func is_ready() -> bool:
	ensure_loaded()
	return _load_ok and not _entries.is_empty()


static func count() -> int:
	ensure_loaded()
	return _entries.size()


static func pick(rng: RandomNumberGenerator) -> Dictionary:
	ensure_loaded()
	if not is_ready():
		push_error("VehicleCatalog.pick: catalog not ready")
		return {}
	return _entries[rng.randi_range(0, _entries.size() - 1)].duplicate(true)


static func entry_at(index: int) -> Dictionary:
	ensure_loaded()
	if not is_ready():
		push_error("VehicleCatalog.entry_at: catalog not ready")
		return {}
	if index < 0 or index >= _entries.size():
		push_error("VehicleCatalog.entry_at: index %d out of range (size=%d)" % [index, _entries.size()])
		return {}
	return _entries[index].duplicate(true)


static func entry_by_id(id: String) -> Dictionary:
	ensure_loaded()
	if not is_ready():
		push_error("VehicleCatalog.entry_by_id: catalog not ready")
		return {}
	for e in _entries:
		if str(e.get("id", "")) == id:
			return e.duplicate(true)
	push_error("VehicleCatalog.entry_by_id: unknown id '%s'" % id)
	return {}
