## Combat allegiance for everything that can be hunted or do the hunting.
##
## Monster faction strings live on each monster row in `assets/gamedata.json` (authored
## in `tools/edit_gamedata.py`). `HUMAN` has no combat-table row: it is what the player
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
	## Not a side in the fight: the Monster Zoo's cloak, worn by the player to watch a war
	## nobody invited them to. No body may be authored into it — it is granted and expires.
	SPECTATOR,
	## Scripted encounter bodies (hill cave cage, …). Own no zoo turf; excluded from arena
	## / N-key summon lists. Hostile like any other combat side.
	UNIQUE,
}

## The six sides that actually hold ground. Order matches the zoo's turf plate materials.
const MONSTER_COUNT := 6


static func all() -> Array[Id]:
	return [
		Id.UNDEAD,
		Id.INFERNAL,
		Id.HORDE,
		Id.BEAST,
		Id.GROVE,
		Id.ARCANE,
		Id.HUMAN,
		Id.SPECTATOR,
		Id.UNIQUE,
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
		Id.SPECTATOR:
			return "spectator"
		Id.UNIQUE:
			return "unique"
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
		"spectator":
			return Id.SPECTATOR
		"unique":
			return Id.UNIQUE
	push_error("MonsterFaction.from_name: unknown faction '%s'" % name)
	assert(false, "MonsterFaction: unknown faction name")
	return Id.UNDEAD


## True when `a` may hunt and hurt `b`.
##
## A spectator is nobody's enemy in either direction: mobs drop the acquire, and a cloaked
## player cannot start a fight either. Environmental damage does not go through here, which
## is why zoo turf plates still burn the cloaked — sightseeing buys you out of the war, not
## out of standing on someone's ground.
static func is_hostile(a: Id, b: Id) -> bool:
	if a == Id.SPECTATOR or b == Id.SPECTATOR:
		return false
	return a != b


## The six monster factions, by the index the zoo's territories and plate materials use.
static func monster_faction_at(index: int) -> Id:
	if index < 0 or index >= MONSTER_COUNT:
		push_error("MonsterFaction.monster_faction_at: index %d is not a monster faction" % index)
		assert(false, "MonsterFaction: bad monster faction index")
		return Id.UNDEAD
	return all()[index]


## Allegiance for a CreatureCatalog / combat-table body id (`family/Name`).
## Reads the required `faction` string from gamedata via CombatTable.
static func for_body(body_id: String) -> Id:
	return from_name(CombatTableScript.faction_for(body_id))
