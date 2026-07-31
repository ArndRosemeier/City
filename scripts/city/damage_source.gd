## Every way a body in this city gets hurt, and how much each one hurts by.
##
## The amounts are here rather than at the five call sites that deal them, because a damage
## model spread across the melee handler, the laser impact, the blaster impact, the stomp and
## the orb is a model nobody can read: the reason a skeleton falls to one punch and a giant
## does not is this table sitting next to `creature_health.gd`, not a number buried in a VFX
## script.
##
## Nothing here has a fallback. An id with no amount, no name or no target is a content bug and
## complains by name instead of quietly dealing zero — a damage source that silently does
## nothing is the one bug in a combat system that never shows up in a screenshot.
##
## The scale is one pool: the player's hundred points and a creature's tier are the same units,
## so `PLAYER_MELEE` 34 against a 34-point skeleton and `UNDEAD_ORB` 25 against the player's
## hundred can be read against each other without conversion.
##
## Monster→player rows match `assets/combat/attacks.json` `damage_vs_player` at 1× `damage_mult`.
## Live units multiply those bases by their resolved combat `damage_mult`.
class_name DamageSource
extends RefCounted

## Which pool a source is allowed to drain. The player's attacks and the undead's are not
## interchangeable, and handing one to the wrong pool is a wiring mistake worth a complaint
## rather than a hit that lands on the wrong body.
enum Target { PLAYER, CREATURE }

enum Id {
	PLAYER_MELEE,
	PLAYER_LASER,
	PLAYER_BLASTER,
	PLAYER_STOMP,
	PLAYER_BLAST,
	UNDEAD_ORB,
	GIANT_DEBRIS,
	MONSTER_MELEE,
	MONSTER_LASER,
	MONSTER_BLASTER,
	MONSTER_STOMP,
	MONSTER_BLAST,
	## Monster→creature mirrors of the player-facing rows. Same base amounts as the MONSTER_*
	## player hits; `UndeadUnit.apply_damage` only accepts CREATURE sources, so these exist
	## so faction fights can drain a body without pretending a player punch landed.
	MONSTER_MELEE_MOB,
	MONSTER_LASER_MOB,
	MONSTER_BLASTER_MOB,
	MONSTER_STOMP_MOB,
	MONSTER_BLAST_MOB,
}


static func all() -> Array[Id]:
	return [
		Id.PLAYER_MELEE,
		Id.PLAYER_LASER,
		Id.PLAYER_BLASTER,
		Id.PLAYER_STOMP,
		Id.PLAYER_BLAST,
		Id.UNDEAD_ORB,
		Id.GIANT_DEBRIS,
		Id.MONSTER_MELEE,
		Id.MONSTER_LASER,
		Id.MONSTER_BLASTER,
		Id.MONSTER_STOMP,
		Id.MONSTER_BLAST,
		Id.MONSTER_MELEE_MOB,
		Id.MONSTER_LASER_MOB,
		Id.MONSTER_BLASTER_MOB,
		Id.MONSTER_STOMP_MOB,
		Id.MONSTER_BLAST_MOB,
	]


## Hit points one landed hit removes at 1× scale.
##
## The player's five attacks are priced against each other by what they cost to throw: the fist
## is free and kills one skeleton, the eye laser and the blaster cost a point of energy each and
## chip, the stomp costs ten and clears a mid-size monster, the charged blast costs twenty and
## is the only thing that meaningfully hurts a giant.
##
## Undead orb and giant debris keep their live invasion numbers. Monster contact / ranged rows
## mirror attacks.json so a body's `damage_mult` scales a known base rather than inventing one.
static func amount(id: Id) -> float:
	match id:
		Id.PLAYER_MELEE:
			return 34.0
		Id.PLAYER_LASER:
			return 18.0
		Id.PLAYER_BLASTER:
			return 18.0
		Id.PLAYER_STOMP:
			return 110.0
		Id.PLAYER_BLAST:
			return 150.0
		Id.UNDEAD_ORB:
			return 25.0
		Id.GIANT_DEBRIS:
			return 10.0
		Id.MONSTER_MELEE, Id.MONSTER_MELEE_MOB:
			return 12.0
		Id.MONSTER_LASER, Id.MONSTER_LASER_MOB:
			return 18.0
		Id.MONSTER_BLASTER, Id.MONSTER_BLASTER_MOB:
			return 18.0
		Id.MONSTER_STOMP, Id.MONSTER_STOMP_MOB:
			return 50.0
		Id.MONSTER_BLAST, Id.MONSTER_BLAST_MOB:
			return 50.0
	push_error("DamageSource: no amount defined for id %d" % int(id))
	return 0.0


static func target(id: Id) -> Target:
	match id:
		Id.PLAYER_MELEE, Id.PLAYER_LASER, Id.PLAYER_BLASTER, Id.PLAYER_STOMP, Id.PLAYER_BLAST:
			return Target.CREATURE
		Id.MONSTER_MELEE_MOB, Id.MONSTER_LASER_MOB, Id.MONSTER_BLASTER_MOB, Id.MONSTER_STOMP_MOB, Id.MONSTER_BLAST_MOB:
			return Target.CREATURE
		Id.UNDEAD_ORB, Id.GIANT_DEBRIS, Id.MONSTER_MELEE, Id.MONSTER_LASER, Id.MONSTER_BLASTER, Id.MONSTER_STOMP, Id.MONSTER_BLAST:
			return Target.PLAYER
	push_error("DamageSource: no target defined for id %d" % int(id))
	return Target.CREATURE


## True for the player's creature-hitting attacks (melee / laser / blaster / stomp / blast).
static func is_player_vs_creature(id: Id) -> bool:
	match id:
		Id.PLAYER_MELEE, Id.PLAYER_LASER, Id.PLAYER_BLASTER, Id.PLAYER_STOMP, Id.PLAYER_BLAST:
			return true
		_:
			return false


## Short name for logs and test output.
static func source_name(id: Id) -> String:
	match id:
		Id.PLAYER_MELEE:
			return "melee"
		Id.PLAYER_LASER:
			return "eye laser"
		Id.PLAYER_BLASTER:
			return "blaster"
		Id.PLAYER_STOMP:
			return "stomp"
		Id.PLAYER_BLAST:
			return "charged blast"
		Id.UNDEAD_ORB:
			return "undead orb"
		Id.GIANT_DEBRIS:
			return "giant debris"
		Id.MONSTER_MELEE:
			return "monster melee"
		Id.MONSTER_LASER:
			return "monster eye laser"
		Id.MONSTER_BLASTER:
			return "monster blaster"
		Id.MONSTER_STOMP:
			return "monster stomp"
		Id.MONSTER_BLAST:
			return "monster charged blast"
		Id.MONSTER_MELEE_MOB:
			return "monster melee (mob)"
		Id.MONSTER_LASER_MOB:
			return "monster eye laser (mob)"
		Id.MONSTER_BLASTER_MOB:
			return "monster blaster (mob)"
		Id.MONSTER_STOMP_MOB:
			return "monster stomp (mob)"
		Id.MONSTER_BLAST_MOB:
			return "monster charged blast (mob)"
	push_error("DamageSource: no name for id %d" % int(id))
	return "?"


## What the game-over screen says when this is the source that finished the player off.
static func death_reason(id: Id) -> String:
	match id:
		Id.UNDEAD_ORB:
			return "Undead conversion orb"
		Id.GIANT_DEBRIS:
			return "Crushed under a giant's demolition"
		Id.MONSTER_MELEE:
			return "Torn apart in melee"
		Id.MONSTER_LASER:
			return "Burned by a monster's eye laser"
		Id.MONSTER_BLASTER:
			return "Cut down by a monster's blaster"
		Id.MONSTER_STOMP:
			return "Crushed under a monster's stomp"
		Id.MONSTER_BLAST:
			return "Caught in a monster's charged blast"
		Id.PLAYER_MELEE, Id.PLAYER_LASER, Id.PLAYER_BLASTER, Id.PLAYER_STOMP, Id.PLAYER_BLAST, Id.MONSTER_MELEE_MOB, Id.MONSTER_LASER_MOB, Id.MONSTER_BLASTER_MOB, Id.MONSTER_STOMP_MOB, Id.MONSTER_BLAST_MOB:
			push_error(
				"DamageSource: %s cannot kill the player, so it has no death reason"
				% source_name(id)
			)
			return "?"
	push_error("DamageSource: no death reason for id %d" % int(id))
	return "?"


## Map a combat-table attack id to the DamageSource used when that attack hits the player.
## Building-only attacks (`nibble`) and null-source rows have no player mapping.
static func for_monster_attack(attack_id: String) -> Id:
	match attack_id:
		"melee":
			return Id.MONSTER_MELEE
		"eye_laser":
			return Id.MONSTER_LASER
		"blaster":
			return Id.MONSTER_BLASTER
		"stomp":
			return Id.MONSTER_STOMP
		"charged_blast":
			return Id.MONSTER_BLAST
		"orb_convert":
			return Id.UNDEAD_ORB
		"debris":
			return Id.GIANT_DEBRIS
		"nibble", "fist":
			push_error(
				"DamageSource.for_monster_attack: '%s' does not hurt the player"
				% attack_id
			)
			return Id.MONSTER_MELEE
		_:
			push_error("DamageSource.for_monster_attack: unknown attack '%s'" % attack_id)
			assert(false, "DamageSource: unknown monster attack")
			return Id.MONSTER_MELEE


## Map a combat-table attack id to the CREATURE-targeting source used when that attack hits
## another monster. Orb convert and debris stay player/building-only.
static func for_monster_attack_mob(attack_id: String) -> Id:
	match attack_id:
		"melee":
			return Id.MONSTER_MELEE_MOB
		"eye_laser":
			return Id.MONSTER_LASER_MOB
		"blaster":
			return Id.MONSTER_BLASTER_MOB
		"stomp":
			return Id.MONSTER_STOMP_MOB
		"charged_blast":
			return Id.MONSTER_BLAST_MOB
		"orb_convert", "debris", "nibble", "fist":
			push_error(
				"DamageSource.for_monster_attack_mob: '%s' does not hurt creatures"
				% attack_id
			)
			assert(false, "DamageSource: attack cannot hurt mobs")
			return Id.MONSTER_MELEE_MOB
		_:
			push_error(
				"DamageSource.for_monster_attack_mob: unknown attack '%s'" % attack_id
			)
			assert(false, "DamageSource: unknown monster attack")
			return Id.MONSTER_MELEE_MOB
