## Combat allegiance for everything that can be hunted or do the hunting.
##
## Monster faction strings live on each row of `assets/monsters/combat_table.json` (authored
## in `tools/edit_combat_tables.py`). `HUMAN` has no combat-table row: it is what the player
## and every pedestrian are, so a mob hunts them for the same reason it hunts a monster of
## another faction. Hostility is nothing but "not the same faction".
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
	HUMAN,
}


static func all() -> Array[Id]:
	return [
		Id.UNDEAD,
		Id.INFERNAL,
		Id.HORDE,
		Id.BEAST,
		Id.GROVE,
		Id.ARCANE,
		Id.HUMAN,
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
		Id.HUMAN:
			return "human"
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
		"human":
			return Id.HUMAN
	push_error("MonsterFaction.from_name: unknown faction '%s'" % name)
	assert(false, "MonsterFaction: unknown faction name")
	return Id.UNDEAD


## True when `a` may hunt and hurt `b`.
static func is_hostile(a: Id, b: Id) -> bool:
	return a != b


## Allegiance for a CreatureCatalog / combat-table body id (`family/Name`).
## Reads the required `faction` string from combat_table.json via CombatTable.
static func for_body(body_id: String) -> Id:
	return from_name(CombatTableScript.faction_for(body_id))
