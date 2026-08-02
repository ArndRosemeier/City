## Loads shared combat JSON and resolves per-monster effective stats.
##
## Python mirror (must stay identical): tools/combat_resolve.py
## Sync guard: tools/sync_combat_resolve.py + tools/fixtures/combat_effective_stats.json
## Godot check: tools/test_combat_table_sync.gd
##
## Merge rules (same names as Python):
##   merge_template_scalars — max across templates; body scalars replace
##   merge_template_lists / apply_body_list_overrides — union; *_extra adds; bare hard-replaces
##   attacks_from_behaviours + body attacks_extra (add) / attacks (hard-replace)
##   effective_attack_damage — attack damage_vs_* × damage_mult
##
## There is no prey table: who a body hunts is its faction against everyone else's.
class_name CombatTable
extends RefCounted

const GameDataScript := preload("res://scripts/city/game_data.gd")
const GOLDEN_PATH := "res://tools/fixtures/combat_effective_stats.json"

## Keep aligned with tools/combat_resolve.py SCALAR_KEYS
const SCALAR_KEYS: PackedStringArray = [
	"hp_mult",
	"damage_mult",
	"speed_mult",
	"aggro_range_m",
	"leash_m",
	"preferred_range_m",
	"armor_mult",
	"score_mult",
]

## Keep aligned with tools/combat_resolve.py LIST_KEYS
const LIST_KEYS: PackedStringArray = ["behaviour", "attacks", "tags", "crowd_roles", "auras"]

const SYNC_FLOAT_DECIMALS := 6

## Resolved effective combat for one monster body.
class EffectiveStats:
	extends RefCounted
	var monster_id: String = ""
	var hp_mult: float = 1.0
	var damage_mult: float = 1.0
	var speed_mult: float = 1.0
	var aggro_range_m: float = 0.0
	var leash_m: float = 0.0
	var preferred_range_m: float = 0.0
	var armor_mult: float = 1.0
	var score_mult: float = 1.0
	var behaviour: PackedStringArray = PackedStringArray()
	var attacks: PackedStringArray = PackedStringArray()
	var tags: PackedStringArray = PackedStringArray()
	var crowd_roles: PackedStringArray = PackedStringArray()
	var auras: PackedStringArray = PackedStringArray()
	## attack_id → { "vs_player": float, "vs_mob": float } (base × damage_mult)
	var attack_damage: Dictionary = {}

	func scalar(key: String) -> float:
		match key:
			"hp_mult":
				return hp_mult
			"damage_mult":
				return damage_mult
			"speed_mult":
				return speed_mult
			"aggro_range_m":
				return aggro_range_m
			"leash_m":
				return leash_m
			"preferred_range_m":
				return preferred_range_m
			"armor_mult":
				return armor_mult
			"score_mult":
				return score_mult
			_:
				push_error("CombatTable.EffectiveStats: unknown scalar '%s'" % key)
				return 0.0

	func set_scalar(key: String, value: float) -> void:
		match key:
			"hp_mult":
				hp_mult = value
			"damage_mult":
				damage_mult = value
			"speed_mult":
				speed_mult = value
			"aggro_range_m":
				aggro_range_m = value
			"leash_m":
				leash_m = value
			"preferred_range_m":
				preferred_range_m = value
			"armor_mult":
				armor_mult = value
			"score_mult":
				score_mult = value
			_:
				push_error("CombatTable.EffectiveStats: unknown scalar '%s'" % key)

	## Sync-normalized Dictionary matching tools/fixtures/combat_effective_stats.json rows.
	func to_sync_dict() -> Dictionary:
		var atk: Array = []
		for a: String in attacks:
			atk.append(a)
		atk.sort()
		var beh: Array = []
		for b: String in behaviour:
			beh.append(b)
		var tag_list: Array = []
		for t: String in tags:
			tag_list.append(t)
		tag_list.sort()
		var roles: Array = []
		for r: String in crowd_roles:
			roles.append(r)
		roles.sort()
		beh.sort()
		var aura_list: Array = []
		for aura_id: String in auras:
			aura_list.append(aura_id)
		aura_list.sort()
		var dmg_out: Dictionary = {}
		var dmg_keys: Array = attack_damage.keys()
		dmg_keys.sort()
		for aid_v: Variant in dmg_keys:
			var aid := str(aid_v)
			var pair_raw: Variant = attack_damage[aid]
			if typeof(pair_raw) != TYPE_DICTIONARY:
				push_error("CombatTable.EffectiveStats: attack_damage['%s'] must be an object" % aid)
				assert(false, "CombatTable: bad attack_damage entry")
				continue
			var pair: Dictionary = pair_raw
			dmg_out[aid] = {
				"vs_player": _round_sync(float(pair.get("vs_player", 0.0))),
				"vs_mob": _round_sync(float(pair.get("vs_mob", 0.0))),
			}
		return {
			"hp_mult": _round_sync(hp_mult),
			"damage_mult": _round_sync(damage_mult),
			"speed_mult": _round_sync(speed_mult),
			"aggro_range_m": _round_sync(aggro_range_m),
			"leash_m": _round_sync(leash_m),
			"preferred_range_m": _round_sync(preferred_range_m),
			"armor_mult": _round_sync(armor_mult),
			"score_mult": _round_sync(score_mult),
			"behaviour": beh,
			"attacks": atk,
			"attack_damage": dmg_out,
			"tags": tag_list,
			"crowd_roles": roles,
			"auras": aura_list,
		}

	func _round_sync(value: float) -> float:
		var scale := pow(10.0, 6.0)
		return roundf(value * scale) / scale


static var _loaded: bool = false
static var _attacks: Dictionary = {}
static var _auras: Dictionary = {}
static var _behaviours: Dictionary = {}
static var _templates: Dictionary = {}
## monster_id → body Dictionary from gamedata.json
static var _monsters: Dictionary = {}
static var _monster_ids: PackedStringArray = PackedStringArray()


static func reload() -> void:
	_loaded = false
	_attacks.clear()
	_auras.clear()
	_behaviours.clear()
	_templates.clear()
	_monsters.clear()
	_monster_ids = PackedStringArray()
	ensure_loaded()


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	## Authored rows live in gamedata.json — GameData is the only JSON reader.
	GameDataScript.ensure_loaded()
	_attacks = GameDataScript.attacks()
	_auras = GameDataScript.auras()
	_behaviours = GameDataScript.behaviours()
	_templates = GameDataScript.templates()
	_monsters.clear()
	_monster_ids = PackedStringArray()
	for item: Variant in GameDataScript.monsters_array():
		if typeof(item) != TYPE_DICTIONARY:
			push_error("CombatTable: monster entry is not an object")
			assert(false, "CombatTable: bad monster entry")
			continue
		var body: Dictionary = item
		var mid := str(body.get("id", ""))
		if mid.is_empty():
			push_error("CombatTable: monster entry missing string id")
			assert(false, "CombatTable: monster missing id")
			continue
		if _monsters.has(mid):
			push_error("CombatTable: duplicate monster id '%s'" % mid)
			assert(false, "CombatTable: duplicate monster id")
			continue
		_monsters[mid] = body
		_monster_ids.append(mid)
	_monster_ids.sort()


static func monster_ids() -> PackedStringArray:
	ensure_loaded()
	return _monster_ids


static func has_monster(monster_id: String) -> bool:
	ensure_loaded()
	return _monsters.has(monster_id)


## Required `faction` string on the combat-table body (`undead`, `beast`, …).
static func faction_for(monster_id: String) -> String:
	ensure_loaded()
	if not _monsters.has(monster_id):
		push_error("CombatTable.faction_for: unknown monster '%s'" % monster_id)
		assert(false, "CombatTable: unknown monster for faction")
		return ""
	var body: Dictionary = _monsters[monster_id]
	var faction := str(body.get("faction", ""))
	if faction.is_empty():
		push_error("CombatTable.faction_for: monster '%s' has no faction" % monster_id)
		assert(false, "CombatTable: missing faction")
		return ""
	return faction


## Bodies marked `spawn_ready` in gamedata. Summon UI and tools use this roster.
static func spawnable_ids() -> PackedStringArray:
	ensure_loaded()
	var out := PackedStringArray()
	for mid: String in _monster_ids:
		var body: Dictionary = _monsters[mid]
		if bool(body.get("spawn_ready", false)):
			out.append(mid)
	return out


## `spawn_ready` bodies of one faction string (`undead`, `beast`, …), sorted by id.
## Empty is a content bug for any caller that spawns per faction, so it complains here
## rather than letting a whole faction quietly stop showing up.
static func spawnable_ids_for_faction(faction: String) -> PackedStringArray:
	ensure_loaded()
	var out := PackedStringArray()
	for mid: String in spawnable_ids():
		if faction_for(mid) == faction:
			out.append(mid)
	if out.is_empty():
		push_error(
			"CombatTable.spawnable_ids_for_faction: no spawn_ready body is '%s'" % faction
		)
	return out


## Relative pick weight for random spawning. Bodies without the key weigh 1.
static func spawn_weight_for(monster_id: String) -> float:
	ensure_loaded()
	if not _monsters.has(monster_id):
		push_error("CombatTable.spawn_weight_for: unknown monster '%s'" % monster_id)
		assert(false, "CombatTable: unknown monster for spawn weight")
		return 0.0
	var body: Dictionary = _monsters[monster_id]
	if not body.has("spawn_weight"):
		return 1.0
	return _require_number(body["spawn_weight"], "monster '%s' spawn_weight" % monster_id)


## Cooldown a monster uses for `attack_id`. Prefers `monster_cooldown_s`, else `cooldown_s`.
static func monster_attack_cooldown_s(attack_id: String) -> float:
	var row := attack_def(attack_id)
	if row.has("monster_cooldown_s"):
		return _require_number(row["monster_cooldown_s"], "attack '%s' monster_cooldown_s" % attack_id)
	return _require_number(row.get("cooldown_s", 0.0), "attack '%s' cooldown_s" % attack_id)


## Engagement reach a monster uses for `attack_id`. Prefers `monster_range_m`, else `range_m`.
static func monster_attack_range_m(attack_id: String) -> float:
	var row := attack_def(attack_id)
	if row.has("monster_range_m"):
		return _require_number(row["monster_range_m"], "attack '%s' monster_range_m" % attack_id)
	return _require_number(row.get("range_m", 0.0), "attack '%s' range_m" % attack_id)


## Telegraph before a monster fires. Prefers `monster_windup_s`, else `windup_s`, else 0.
static func monster_attack_windup_s(attack_id: String) -> float:
	var row := attack_def(attack_id)
	if row.has("monster_windup_s"):
		return _require_number(row["monster_windup_s"], "attack '%s' monster_windup_s" % attack_id)
	if row.has("windup_s"):
		return _require_number(row["windup_s"], "attack '%s' windup_s" % attack_id)
	return 0.0


static func attack_def(attack_id: String) -> Dictionary:
	ensure_loaded()
	if not _attacks.has(attack_id):
		push_error("CombatTable: unknown attack '%s'" % attack_id)
		assert(false, "CombatTable: unknown attack")
		return {}
	return _attacks[attack_id]


static func aura_def(aura_id: String) -> Dictionary:
	ensure_loaded()
	if not _auras.has(aura_id):
		push_error("CombatTable: unknown aura '%s'" % aura_id)
		assert(false, "CombatTable: unknown aura")
		return {}
	return _auras[aura_id]


## Off-budget gem haul on player kill. Returns Vector2i(min, max); both 0 when none.
static func kill_gems_range(monster_id: String) -> Vector2i:
	ensure_loaded()
	if not _monsters.has(monster_id):
		push_error("CombatTable.kill_gems_range: unknown monster '%s'" % monster_id)
		assert(false, "CombatTable: unknown monster for kill gems")
		return Vector2i.ZERO
	var body: Dictionary = _monsters[monster_id]
	var gmin := int(body.get("kill_gems_min", 0))
	var gmax := int(body.get("kill_gems_max", 0))
	if gmin < 0 or gmax < 0:
		push_error("CombatTable.kill_gems_range: negative haul on '%s'" % monster_id)
		assert(false, "CombatTable: bad kill_gems")
		return Vector2i.ZERO
	if gmin > gmax:
		push_error(
			"CombatTable.kill_gems_range: kill_gems_min > max on '%s'" % monster_id
		)
		assert(false, "CombatTable: bad kill_gems range")
		return Vector2i.ZERO
	return Vector2i(gmin, gmax)


## Python: combat_resolve.effective_attack_damage
static func effective_attack_damage(attack_id: String, damage_mult: float) -> Dictionary:
	if damage_mult <= 0.0:
		push_error("CombatTable.effective_attack_damage: damage_mult %f is not positive" % damage_mult)
		assert(false, "CombatTable: bad damage_mult")
		return {"vs_player": 0.0, "vs_mob": 0.0}
	var row := attack_def(attack_id)
	var vs_player := _require_number(
		row.get("damage_vs_player", null), "attack '%s' damage_vs_player" % attack_id
	)
	var vs_mob := _require_number(
		row.get("damage_vs_mob", null), "attack '%s' damage_vs_mob" % attack_id
	)
	return {
		"vs_player": vs_player * damage_mult,
		"vs_mob": vs_mob * damage_mult,
	}


## Python: combat_resolve.effective_attack_damages
static func effective_attack_damages(
	attack_ids: PackedStringArray, damage_mult: float
) -> Dictionary:
	var out: Dictionary = {}
	var keys: Array = []
	for aid: String in attack_ids:
		keys.append(aid)
	keys.sort()
	for aid_v: Variant in keys:
		var aid := str(aid_v)
		out[aid] = effective_attack_damage(aid, damage_mult)
	return out


static func behaviour_def(behaviour_id: String) -> Dictionary:
	ensure_loaded()
	if not _behaviours.has(behaviour_id):
		push_error("CombatTable: unknown behaviour '%s'" % behaviour_id)
		assert(false, "CombatTable: unknown behaviour")
		return {}
	return _behaviours[behaviour_id]


## Resolve effective stats for a CreatureCatalog / combat_table monster id.
static func resolve(monster_id: String) -> EffectiveStats:
	ensure_loaded()
	if not _monsters.has(monster_id):
		push_error("CombatTable: unknown monster '%s'" % monster_id)
		assert(false, "CombatTable: unknown monster")
		return null
	var body: Dictionary = _monsters[monster_id]
	var tids := _require_string_array(body.get("templates", null), "monster '%s' templates" % monster_id)
	if tids.is_empty():
		push_error("CombatTable: monster '%s' has empty templates" % monster_id)
		assert(false, "CombatTable: empty templates")
		return null
	return effective_monster_combat(monster_id, tids, body)


## Python: combat_resolve.effective_monster_combat
static func effective_monster_combat(
	monster_id: String, template_ids: PackedStringArray, body: Dictionary
) -> EffectiveStats:
	ensure_loaded()
	var scalars := merge_template_scalars(template_ids)
	for key: String in SCALAR_KEYS:
		if body.has(key):
			scalars[key] = _require_number(body[key], "monster '%s' scalar '%s'" % [monster_id, key])
	var lists := apply_body_list_overrides(merge_template_lists(template_ids), body)
	var behaviour_ids: PackedStringArray = lists["behaviour"] as PackedStringArray
	# specialty = template specialty ∪ body attacks_extra (or hard body attacks list).
	var specialty: PackedStringArray = lists["attacks"] as PackedStringArray
	var derived := attacks_from_behaviours(behaviour_ids)
	var attacks: PackedStringArray
	if body.has("attacks"):
		# Hard replace: body attacks alone (drops behaviour-derived).
		attacks = specialty
	else:
		attacks = union_lists(derived, specialty)

	var eff := EffectiveStats.new()
	eff.monster_id = monster_id
	for key: String in SCALAR_KEYS:
		eff.set_scalar(key, float(scalars[key]))
	eff.behaviour = behaviour_ids
	eff.attacks = attacks
	eff.tags = lists["tags"] as PackedStringArray
	eff.crowd_roles = lists["crowd_roles"] as PackedStringArray
	eff.auras = lists["auras"] as PackedStringArray
	eff.attack_damage = effective_attack_damages(attacks, eff.damage_mult)
	return eff


## Python: combat_resolve.union_lists
static func union_lists(a: PackedStringArray, b: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var seen: Dictionary = {}
	var out := PackedStringArray()
	for item: String in a:
		if seen.has(item):
			continue
		seen[item] = true
		out.append(item)
	for item: String in b:
		if seen.has(item):
			continue
		seen[item] = true
		out.append(item)
	return out


## Python: combat_resolve.attacks_from_behaviours
static func attacks_from_behaviours(behaviour_ids: PackedStringArray) -> PackedStringArray:
	ensure_loaded()
	var out := PackedStringArray()
	for bid: String in behaviour_ids:
		if not _behaviours.has(bid):
			push_error("CombatTable: unknown behaviour '%s'" % bid)
			assert(false, "CombatTable: unknown behaviour in attacks_from_behaviours")
			continue
		var row: Dictionary = _behaviours[bid]
		var attacks := _optional_string_array(row.get("attacks", []), "behaviour '%s' attacks" % bid)
		out = union_lists(out, attacks)
	return out


## Python: combat_resolve.merge_template_scalars
static func merge_template_scalars(template_ids: PackedStringArray) -> Dictionary:
	ensure_loaded()
	var out: Dictionary = {}
	for key: String in SCALAR_KEYS:
		var values: Array[float] = []
		for tid: String in template_ids:
			if not _templates.has(tid):
				push_error("CombatTable: missing template '%s'" % tid)
				assert(false, "CombatTable: missing template")
				continue
			var tmpl: Dictionary = _templates[tid]
			if not tmpl.has(key):
				push_error("CombatTable: template '%s' missing scalar '%s'" % [tid, key])
				assert(false, "CombatTable: template scalar missing")
				continue
			values.append(_require_number(tmpl[key], "template '%s' scalar '%s'" % [tid, key]))
		if values.is_empty():
			push_error("CombatTable: no values for scalar '%s'" % key)
			assert(false, "CombatTable: empty scalar merge")
			out[key] = 0.0
		else:
			var best := values[0]
			for i in range(1, values.size()):
				best = maxf(best, values[i])
			out[key] = best
	return out


## Python: combat_resolve.merge_template_lists
static func merge_template_lists(template_ids: PackedStringArray) -> Dictionary:
	ensure_loaded()
	var out: Dictionary = {}
	for key: String in LIST_KEYS:
		out[key] = PackedStringArray()
	for tid: String in template_ids:
		if not _templates.has(tid):
			push_error("CombatTable: missing template '%s'" % tid)
			assert(false, "CombatTable: missing template")
			continue
		var tmpl: Dictionary = _templates[tid]
		for key: String in LIST_KEYS:
			if not tmpl.has(key):
				continue
			var raw := _optional_string_array(tmpl[key], "template '%s' '%s'" % [tid, key])
			out[key] = union_lists(out[key], raw)
	return out


## Python: combat_resolve.apply_body_list_overrides
static func apply_body_list_overrides(merged_lists: Dictionary, body: Dictionary) -> Dictionary:
	var lists: Dictionary = {}
	for key: String in LIST_KEYS:
		var base: PackedStringArray = merged_lists[key]
		lists[key] = base.duplicate()
	for key: String in LIST_KEYS:
		var extra_key := "%s_extra" % key
		if body.has(key):
			lists[key] = _require_string_array(body[key], "body list override '%s'" % key)
			continue
		if body.has(extra_key):
			var extra := _require_string_array(body[extra_key], "body '%s'" % extra_key)
			lists[key] = union_lists(lists[key], extra)
	return lists


static func round_sync_float(value: float) -> float:
	var scale := pow(10.0, float(SYNC_FLOAT_DECIMALS))
	return roundf(value * scale) / scale


static func _load_json_object(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("CombatTable: missing %s" % path)
		assert(false, "CombatTable: missing JSON")
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("CombatTable: cannot open %s" % path)
		assert(false, "CombatTable: cannot open JSON")
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("CombatTable: invalid JSON root in %s" % path)
		assert(false, "CombatTable: invalid JSON root")
		return {}
	return parsed


static func _load_object_map(path: String, key: String) -> Dictionary:
	var root := _load_json_object(path)
	var raw: Variant = root.get(key, null)
	if typeof(raw) != TYPE_DICTIONARY or (raw as Dictionary).is_empty():
		push_error("CombatTable: %s '%s' must be a non-empty object" % [path, key])
		assert(false, "CombatTable: empty object map")
		return {}
	return raw


static func _require_number(raw: Variant, where: String) -> float:
	var t := typeof(raw)
	if t != TYPE_FLOAT and t != TYPE_INT:
		push_error("CombatTable: %s must be numeric, got %s" % [where, type_string(t)])
		assert(false, "CombatTable: non-numeric")
		return 0.0
	return float(raw)


static func _require_string_array(raw: Variant, where: String) -> PackedStringArray:
	if typeof(raw) != TYPE_ARRAY:
		push_error("CombatTable: %s must be a list of strings" % where)
		assert(false, "CombatTable: not a string list")
		return PackedStringArray()
	var out := PackedStringArray()
	for item: Variant in raw:
		if typeof(item) != TYPE_STRING:
			push_error("CombatTable: %s must be a list of strings" % where)
			assert(false, "CombatTable: non-string in list")
			continue
		out.append(item)
	return out


static func _optional_string_array(raw: Variant, where: String) -> PackedStringArray:
	if raw == null:
		return PackedStringArray()
	return _require_string_array(raw, where)
