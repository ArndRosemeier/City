## Which authored animation clip an action means, across three unrelated rigs.
##
## KayKit skeletons ship 95 clips, Quaternius Big ships 14 and Quaternius Blob ships 9, and
## none of the three name anything the same way. Resolution is exact-first for the whole
## candidate list before any substring is considered: `Idle` has to beat `2H_Melee_Idle`, and
## a loose earlier candidate must never win over a later exact one.
##
## The substring pass, when it is reached at all, takes the shortest matching clip rather
## than the first. `AnimationPlayer.get_animation_list()` is sorted alphabetically, so "first
## hit" silently means "whichever decorated variant sorts earliest", which is how every
## skeleton in this game ended up idling in a two-handed weapon stance.
##
## Nothing here falls back to silence: an action that resolves to no clip is a content bug
## and says so.
class_name CreatureClips
extends RefCounted

enum Action { IDLE, DEATH, CAST, MELEE, LOCOMOTION, HIT_REACT }


## Ordered preferences for one action. Earlier is better, but only within a pass.
static func candidates(action: Action) -> PackedStringArray:
	match action:
		Action.IDLE:
			return PackedStringArray(["Idle", "Unarmed_Idle", "Flying_Idle"])
		Action.DEATH:
			return PackedStringArray(["Death_A", "Death"])
		Action.CAST:
			return PackedStringArray(
				["Spellcast_Shoot", "Spellcast_Raise", "Weapon", "Punch", "Bite_Front"]
			)
		Action.MELEE:
			## `Kick_A` and `Punch_A` were the old candidates and neither is a KayKit clip;
			## `Punch_A` only ever landed by substring inside Unarmed_Melee_Attack_Punch_A.
			return PackedStringArray(
				[
					"Unarmed_Melee_Attack_Kick",
					"Unarmed_Melee_Attack_Punch_A",
					"Punch",
					"Bite_Front",
					"Headbutt",
					"Hit_A",
				]
			)
		Action.LOCOMOTION:
			return PackedStringArray(["Walking_A", "Walk", "Running_A", "Run", "Fast_Flying"])
		Action.HIT_REACT:
			## All three families ship a flinch and all three spell it differently —
			## `HitRecieve` is the Blob set's own misspelling and is the name on the asset.
			return PackedStringArray(["Hit_A", "HitReact", "HitRecieve"])
	push_error("CreatureClips: no candidates for action %d" % int(action))
	return PackedStringArray()


## Interchangeable takes of one action, for per-unit clip randomisation. Exact names only —
## a variant pool built by substring is how a walk cycle becomes a backwards walk.
static func variant_pool(action: Action) -> PackedStringArray:
	match action:
		Action.IDLE:
			return PackedStringArray(["Idle", "Idle_B", "Idle_Combat", "Unarmed_Idle"])
		Action.DEATH:
			return PackedStringArray(["Death_A", "Death_B", "Death_C_Skeletons"])
		Action.LOCOMOTION:
			return PackedStringArray(["Walking_A", "Walking_B", "Walking_C", "Walking_D_Skeletons"])
		Action.HIT_REACT:
			return PackedStringArray(["Hit_A", "Hit_B"])
		Action.CAST, Action.MELEE:
			return PackedStringArray()
	push_error("CreatureClips: no variant pool for action %d" % int(action))
	return PackedStringArray()


static func action_name(action: Action) -> String:
	match action:
		Action.IDLE:
			return "idle"
		Action.DEATH:
			return "death"
		Action.CAST:
			return "cast"
		Action.MELEE:
			return "melee"
		Action.LOCOMOTION:
			return "locomotion"
		Action.HIT_REACT:
			return "hit_react"
	push_error("CreatureClips: no name for action %d" % int(action))
	return "?"


static func all_actions() -> Array[Action]:
	return [
		Action.IDLE,
		Action.DEATH,
		Action.CAST,
		Action.MELEE,
		Action.LOCOMOTION,
		Action.HIT_REACT,
	]


## The clip `action` means on a rig that owns `clips`, or "" with an error if the rig has
## nothing that answers to it. `who` names the model in that error.
static func resolve(clips: PackedStringArray, action: Action, who: String) -> String:
	var found := try_resolve(clips, action)
	if found == "":
		push_error(
			"CreatureClips: %s has no clip for %s — tried %s against %d clips: %s"
			% [who, action_name(action), str(candidates(action)), clips.size(), ", ".join(clips)]
		)
	return found


## The same resolution without the complaint, for surveying models that are deliberately
## not in the spawn tables and would otherwise fill the log with expected misses.
static func try_resolve(clips: PackedStringArray, action: Action) -> String:
	var wanted := candidates(action)
	var lowered := PackedStringArray()
	for clip: String in clips:
		lowered.append(clip.to_lower())

	for want: String in wanted:
		var w := want.to_lower()
		for i in range(lowered.size()):
			if lowered[i] == w:
				return clips[i]

	var best := ""
	for want: String in wanted:
		var w := want.to_lower()
		for i in range(lowered.size()):
			if not lowered[i].contains(w):
				continue
			if best == "" or clips[i].length() < best.length():
				best = clips[i]
		if best != "":
			return best
	return ""


## Every clip in `action`'s pool that this rig actually has, plus the resolved base clip, so
## a rig with no alternatives still yields exactly one deterministic choice.
static func variants_present(
	clips: PackedStringArray, action: Action, who: String
) -> PackedStringArray:
	var out := PackedStringArray()
	for name: String in variant_pool(action):
		if clips.has(name):
			out.append(name)
	if out.is_empty():
		var base := resolve(clips, action, who)
		if base != "":
			out.append(base)
	return out
