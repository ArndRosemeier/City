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
	]


## Hit points one landed hit removes.
##
## The player's five attacks are priced against each other by what they cost to throw: the fist
## is free and kills one skeleton, the eye laser and the blaster cost a point of energy each and
## chip, the stomp costs ten and clears a mid-size monster, the charged blast costs twenty and
## is the only thing that meaningfully hurts a giant.
##
## The two that come the other way are priced against the player's hundred points: an orb is a
## quarter of the pool, so four of them convert you, and standing where a giant is peeling a
## facade costs a tenth per strip — which at the giant's scrape cadence is about three seconds
## of not moving.
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
	push_error("DamageSource: no amount defined for id %d" % int(id))
	return 0.0


static func target(id: Id) -> Target:
	match id:
		Id.PLAYER_MELEE, Id.PLAYER_LASER, Id.PLAYER_BLASTER, Id.PLAYER_STOMP, Id.PLAYER_BLAST:
			return Target.CREATURE
		Id.UNDEAD_ORB, Id.GIANT_DEBRIS:
			return Target.PLAYER
	push_error("DamageSource: no target defined for id %d" % int(id))
	return Target.CREATURE


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
	push_error("DamageSource: no name for id %d" % int(id))
	return "?"


## What the game-over screen says when this is the source that finished the player off.
static func death_reason(id: Id) -> String:
	match id:
		Id.UNDEAD_ORB:
			return "Undead conversion orb"
		Id.GIANT_DEBRIS:
			return "Crushed under a giant's demolition"
		Id.PLAYER_MELEE, Id.PLAYER_LASER, Id.PLAYER_BLASTER, Id.PLAYER_STOMP, Id.PLAYER_BLAST:
			push_error(
				"DamageSource: %s cannot kill the player, so it has no death reason"
				% source_name(id)
			)
			return "?"
	push_error("DamageSource: no death reason for id %d" % int(id))
	return "?"
