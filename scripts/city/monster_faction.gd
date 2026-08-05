## Combat allegiance for everything that can be hunted or do the hunting.
##
## Monster faction strings live on each monster row in `assets/gamedata.json` (authored
## in `tools/edit_gamedata.py`). `HUMAN` has no combat-table row: it is what the player
## and every pedestrian are, so a mob hunts them for the same reason it hunts a monster of
## another faction.
##
## Hostility is usually "not the same faction", but the Siege Quarter needs a split the
## older rule conflated: *may A damage B?* versus *may A acquire B as fresh prey?* Towers
## and the defending player must be able to shoot the horde without the horde turning on
## them unprovoked — retaliation still works because forced pursuit bypasses acquisition.
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
	## Siege Quarter horde. Spawn-time override so wave bodies never civil-war each other.
	SIEGE_ATTACKER,
	## Siege Quarter towers and the player for the duration of a run. Unacquirable as fresh
	## prey, but they may shoot (and be damaged once something has forced retaliation).
	SIEGE_DEFENDER,
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
		Id.SIEGE_ATTACKER,
		Id.SIEGE_DEFENDER,
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
		Id.SIEGE_ATTACKER:
			return "siege_attacker"
		Id.SIEGE_DEFENDER:
			return "siege_defender"
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
		"siege_attacker":
			return Id.SIEGE_ATTACKER
		"siege_defender":
			return Id.SIEGE_DEFENDER
	push_error("MonsterFaction.from_name: unknown faction '%s'" % name)
	assert(false, "MonsterFaction: unknown faction name")
	return Id.UNDEAD


## True when `a` may hurt `b` (and, for most sides, hunt them).
##
## A spectator is nobody's enemy in either direction: mobs drop the acquire, and a cloaked
## player cannot start a fight either. Environmental damage does not go through here, which
## is why zoo turf plates still burn the cloaked — sightseeing buys you out of the war, not
## out of standing on someone's ground.
##
## Siege attackers and defenders *are* hostile both ways for damage: a tower shot may land,
## and a retaliating attacker may land. Fresh acquisition is a separate question — see
## `can_acquire`.
static func is_hostile(a: Id, b: Id) -> bool:
	if a == Id.SPECTATOR or b == Id.SPECTATOR:
		return false
	if a == b:
		return false
	## Siege defenders only fight the horde. Without this, a tower (or the defending player)
	## would treat every pedestrian as prey, and stray undead would hunt the defender for
	## being "not human" rather than for being in the fight.
	if a == Id.SIEGE_DEFENDER or b == Id.SIEGE_DEFENDER:
		return a == Id.SIEGE_ATTACKER or b == Id.SIEGE_ATTACKER
	return true


## True when `hunter` may pick `prey` as a *fresh* target.
##
## Forced retaliation (`UndeadGoalProvider.promote_attacker`) bypasses this: once something
## shoots, the victim turns on it even if it would never have acquired it. That is what lets
## the siege horde walk past silent towers toward the Lodestone, and still answer fire.
static func can_acquire(hunter: Id, prey: Id) -> bool:
	if not is_hostile(hunter, prey):
		return false
	## Defenders are never fresh prey. The horde's standing goal is the Lodestone; aggro is
	## earned by shooting. Towers still acquire attackers (prey is not a defender).
	if prey == Id.SIEGE_DEFENDER:
		return false
	return true


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
