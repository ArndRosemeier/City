## Combat allegiance for creature bodies.
##
## Faction strings live on each row of `assets/monsters/combat_table.json` (authored in
## `tools/edit_combat_tables.py`). Behaviours that weight `monsters` as prey only hunt
## (and only hurt) units on a *different* faction — same-faction packs chase the player
## together instead of hugging each other forever.
class_name MonsterFaction
extends RefCounted

const CombatTableScript := preload("res://scripts/city/combat_table.gd")

enum Id {
	UNDEAD,
	INFERNAL,
	HORDE,
	BEAST,
	GROVE,
	ARCANE,
}


static func all() -> Array[Id]:
	return [
		Id.UNDEAD,
		Id.INFERNAL,
		Id.HORDE,
		Id.BEAST,
		Id.GROVE,
		Id.ARCANE,
	]


static func faction_name(id: Id) -> String:
	match id:
		Id.UNDEAD:
			return "undead"
		Id.INFERNAL:
			return "infernal"
		Id.HORDE:
			return "horde"
		Id.BEAST:
			return "beast"
		Id.GROVE:
			return "grove"
		Id.ARCANE:
			return "arcane"
	push_error("MonsterFaction: no name for id %d" % int(id))
	return "?"


static func from_name(name: String) -> Id:
	match name:
		"undead":
			return Id.UNDEAD
		"infernal":
			return Id.INFERNAL
		"horde":
			return Id.HORDE
		"beast":
			return Id.BEAST
		"grove":
			return Id.GROVE
		"arcane":
			return Id.ARCANE
	push_error("MonsterFaction.from_name: unknown faction '%s'" % name)
	assert(false, "MonsterFaction: unknown faction name")
	return Id.UNDEAD


## True when `a` may treat `b` as monster prey.
static func is_hostile(a: Id, b: Id) -> bool:
	return a != b


## Allegiance for a CreatureCatalog / combat-table body id (`family/Name`).
## Reads the required `faction` string from combat_table.json via CombatTable.
static func for_body(body_id: String) -> Id:
	return from_name(CombatTableScript.faction_for(body_id))
