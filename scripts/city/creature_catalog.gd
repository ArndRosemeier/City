## Every creature body the game may wear, as content rather than as a branch in the loader.
##
## `undead_unit.gd` used to hold two preloads and one `if role == MAGE or role == GIANT`,
## which is why two of the four vendored KayKit skeletons were never seen. A body is now a
## row here: where the model lives, which rig family it belongs to, which behaviour slots may
## spawn it, how tall it measures and which nav profile that height demands.
##
## Every entry must satisfy the loader contract in `undead_unit.gd`: a `Node3D` root, one
## AnimationPlayer, feet on y=0, centred on x/z, facing +Z at yaw 0 and no root motion.
## `tools/test_creature_assets.tscn` asserts all of it against the files on disk, so a row
## that lies here fails there rather than in the city.
class_name CreatureCatalog
extends RefCounted

const _Self := preload("res://scripts/city/creature_catalog.gd")
const NavProfileScript := preload("res://scripts/city/nav_profile.gd")

const KAYKIT_DIR := "res://assets/monsters/kaykit_skeletons/characters"
const QUATERNIUS_DIR := "res://assets/monsters/quaternius_monsters"
const STAFF_PATH := "res://assets/monsters/kaykit_skeletons/props/Skeleton_Staff.gltf"

## The KayKit Minion, which is what the capsule (radius 0.28, height 1.15), `hit_radius`
## 0.55, `hit_half_height` 0.95 and the 1.35 muzzle offset were all measured against. Every
## other body scales those by its own `collider_height` over this.
const REFERENCE_HEIGHT := 2.166

## Measured height may drift from the recorded one by this fraction before the asset is
## considered to have changed under us.
const HEIGHT_TOLERANCE := 0.02
## How far a rest-pose foot may sit off y=0, and a body off the x/z origin, in model units.
const GROUND_TOLERANCE := 0.10
const CENTRE_TOLERANCE := 0.25

enum Family { KAYKIT_SKELETON, QUATERNIUS_BIG, QUATERNIUS_BLOB, QUATERNIUS_FLYING }

## What a body is cast as. `undead_unit.gd` maps its Role onto exactly one of these; keeping
## them apart is what lets a model be listed as fodder without knowing what a Role is.
enum Slot { CASTER, FODDER, BRUTE }


class Entry:
	extends RefCounted
	var id: String = ""
	var path: String = ""
	var family: Family = Family.KAYKIT_SKELETON
	## Slot values this body may be spawned into. Empty means vendored but never spawned.
	var slots: PackedInt32Array = PackedInt32Array()
	## Rest-pose mesh height in model units, as measured off the vendored file.
	var measured_height: float = 0.0
	## Height the collision capsule and hit volume are derived from. The same as
	## `measured_height` except where headgear inflates it: all four KayKit skeletons share
	## one rig and one body, and a wizard hat is not a taller body.
	var collider_height: float = 0.0
	var nav_profile: int = NavProfileScript.Id.UNDEAD
	## Where the authored pivot is relative to where the body stands, negated — the loader
	## adds this to bring the standing footprint over the origin. Zero for an asset that
	## already conforms, which is all but a handful of them.
	var model_offset: Vector3 = Vector3.ZERO
	## Yaw the loader turns the body by so it faces +Z, in radians. `crowd_ped_visual.gd`
	## carries the same correction as a hardcoded PI for MPFB humans; here it is per body,
	## because the three rig families do not agree with each other about front.
	var model_yaw: float = 0.0
	## Bone to hang `prop_path` off, "" for a body that carries nothing.
	var prop_bone: String = ""
	var prop_path: String = ""
	## Why this body is not in the spawn tables, for entries with no slots.
	var note: String = ""

	func is_spawnable() -> bool:
		return not slots.is_empty()

	func has_slot(slot: Slot) -> bool:
		return slots.has(int(slot))

	## How much bigger this body is than the one the collision numbers were measured on.
	func collider_span() -> float:
		return collider_height / REFERENCE_HEIGHT


static var _entries: Array[Entry] = []


static func all() -> Array[Entry]:
	if _entries.is_empty():
		_entries = _build()
	return _entries


static func count() -> int:
	return all().size()


static func by_id(id: String) -> Entry:
	for entry: Entry in all():
		if entry.id == id:
			return entry
	push_error("CreatureCatalog: no entry '%s'" % id)
	return null


static func for_slot(slot: Slot) -> Array[Entry]:
	var out: Array[Entry] = []
	for entry: Entry in all():
		if entry.has_slot(slot):
			out.append(entry)
	return out


## One body for `slot`, chosen from `rng` so a unit's whole appearance follows its seed.
static func pick(slot: Slot, rng: RandomNumberGenerator) -> Entry:
	var pool := for_slot(slot)
	if pool.is_empty():
		push_error("CreatureCatalog: slot %d has no models" % int(slot))
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


static func family_name(family: Family) -> String:
	match family:
		Family.KAYKIT_SKELETON:
			return "kaykit"
		Family.QUATERNIUS_BIG:
			return "quaternius_big"
		Family.QUATERNIUS_BLOB:
			return "quaternius_blob"
		Family.QUATERNIUS_FLYING:
			return "quaternius_flying"
	push_error("CreatureCatalog: no name for family %d" % int(family))
	return "?"


## Bodies whose skins bind by joint name onto a rig they were not authored for. Only the
## KayKit skeletons qualify: all four share one 41-bone rig and split the body into the same
## eight named meshes, which is what makes a head from one and legs from another legal.
static func supports_part_swap(family: Family) -> bool:
	return family == Family.KAYKIT_SKELETON


## Body parts the KayKit meshes are cut into, one group per slot. A group lists the node
## suffixes that mean the same slot: the mage's skull node is `_Skull` where everyone else's
## is `_Head`, and refusing to treat those as one slot would rule the mage out of head swaps
## for a naming reason. The prefix is the model name, so `Skeleton_Mage` + `_Skull`.
static func part_slots() -> Array[PackedStringArray]:
	return [
		PackedStringArray(["_Skull", "_Head"]),
		PackedStringArray(["_Jaw"]),
		PackedStringArray(["_ArmLeft"]),
		PackedStringArray(["_ArmRight"]),
		PackedStringArray(["_LegLeft"]),
		PackedStringArray(["_LegRight"]),
	]


static func _build() -> Array[Entry]:
	var out: Array[Entry] = []
	var caster := PackedInt32Array([int(Slot.CASTER)])
	var fodder := PackedInt32Array([int(Slot.FODDER)])
	var fodder_brute := PackedInt32Array([int(Slot.FODDER), int(Slot.BRUTE)])
	var caster_brute := PackedInt32Array([int(Slot.CASTER), int(Slot.BRUTE)])

	## KayKit skeletons: one rig, one texture, four dressings. Heights include headgear;
	## the shared body is REFERENCE_HEIGHT tall, so that is what the capsule follows.
	out.append(
		_kaykit("Skeleton_Mage", 2.630, caster_brute, "handslot.r", STAFF_PATH)
	)
	out.append(_kaykit("Skeleton_Minion", 2.166, fodder, "", ""))
	out.append(_kaykit("Skeleton_Rogue", 2.308, caster, "handslot.l", ""))
	out.append(_kaykit("Skeleton_Warrior", 2.590, fodder_brute, "", ""))

	## Quaternius Big: 43-bone humanoid rig (49 on Bunny, which adds ear bones), 14 clips,
	## in-place locomotion. 2.70-3.96 units puts every one of them on the mid-size profile.
	for row: Array in [
		["Alien", 3.547], ["Birb", 3.328], ["BlueDemon", 2.841], ["Bunny", 3.444],
		["Cactoro", 3.957], ["Demon", 3.120], ["Dino", 3.226], ["Fish", 3.755],
		["Frog", 2.695], ["Monkroose", 2.985], ["MushroomKing", 3.609], ["Ninja", 3.021],
		["Orc", 3.209], ["Orc_Skull", 3.268], ["Tribal", 3.929], ["Yeti", 2.828],
	]:
		out.append(
			_quaternius(
				"big", row[0], row[1], Family.QUATERNIUS_BIG, fodder_brute,
				NavProfileScript.Id.MONSTER, ""
			)
		)
	## Hill-cave caged boss — same Demon mesh, distinct combat id / Unique faction.
	out.append(
		_alias_quaternius(
			"big/CageDemon",
			"big",
			"Demon",
			3.120,
			Family.QUATERNIUS_BIG,
			fodder_brute,
			NavProfileScript.Id.MONSTER,
			"hill cave cage boss — Demon mesh alias"
		)
	)

	## City hostiles — the Ninja mesh under two combat identities. Both are people the street
	## turned on the player rather than monsters that walked in, so they wear the one humanoid
	## silhouette in the set. Out of the spawn tables on purpose: the crowd promotes them.
	out.append(
		_alias_quaternius(
			"city/mad_citizen",
			"big",
			"Ninja",
			3.021,
			Family.QUATERNIUS_BIG,
			PackedInt32Array(),
			NavProfileScript.Id.MONSTER,
			"lab infection convert — spawned by the infestation only"
		)
	)
	out.append(
		_alias_quaternius(
			"city/wanted_killer",
			"big",
			"Ninja",
			3.021,
			Family.QUATERNIUS_BIG,
			PackedInt32Array(),
			NavProfileScript.Id.MONSTER,
			"wanted hunt — spawned when the marked ped is attacked"
		)
	)

	## Quaternius Blob: a four-bone rig (Body/Head/Head2/Head3) that shares nothing with the
	## Big one, 9 clips, 1.0-4.9k triangles. Cheap enough to spawn in packs.
	##
	## Three of them are authored off their own pivot — the bird stands three quarters of a
	## unit in front of it — so they carry the z correction that puts their feet back over
	## the nav position. The rest need none, and the conformance test measures all of them.
	for row: Array in [
		["Alien", 3.243, true, 0.315], ["Birb", 2.612, false, -0.771],
		["Cactoro", 3.574, true, 0.0], ["Cat", 1.944, false, 0.0],
		["Chicken", 2.347, false, -0.211], ["Dog", 1.828, false, 0.0],
		["Fish", 2.731, false, -0.440], ["GreenBlob", 1.853, false, 0.0],
		["GreenSpikyBlob", 4.143, true, 0.0], ["Mushnub", 3.296, true, 0.0],
		["Mushnub_Evolved", 4.411, true, 0.0], ["Orc", 2.347, false, 0.0],
		["Pigeon", 1.802, false, 0.0], ["PinkBlob", 2.009, false, 0.0],
		["Yeti", 2.437, false, 0.0],
	]:
		var blob := _quaternius(
			"blob", row[0], row[1], Family.QUATERNIUS_BLOB, fodder,
			NavProfileScript.Id.MONSTER if bool(row[2]) else NavProfileScript.Id.UNDEAD, ""
		)
		blob.model_offset = Vector3(0.0, 0.0, float(row[3]))
		out.append(blob)
	out.append(
		_quaternius(
			"blob", "Wizard", 2.601, Family.QUATERNIUS_BLOB, caster,
			NavProfileScript.Id.UNDEAD, ""
		)
	)
	## Rest pose puts this one 0.23 units through the pavement, which the loader contract
	## does not allow and the loader must not paper over.
	out.append(
		_quaternius(
			"blob", "Ninja", 3.011, Family.QUATERNIUS_BLOB, PackedInt32Array(),
			NavProfileScript.Id.UNDEAD, "rest pose sits 0.23 units below y=0"
		)
	)

	## Quaternius Flying: vendored for completeness, spawned by nothing. Most of the set is
	## authored hovering (Pigeon's lowest vertex is 1.57 units up), the locomotion clips are
	## Fast_Flying and Flying_Idle with no walk cycle at all, and flying/Demon ships a single
	## clip. Navigation here is ground spans with no flight system, so walking them would be
	## a floating, gliding lie.
	for row: Array in [
		["Alpaking", 2.139], ["Alpaking_Evolved", 3.192], ["Armabee", 1.886],
		["Armabee_Evolved", 2.138], ["Demon", 1.676], ["Dragon", 1.541],
		["Dragon_Evolved", 2.858], ["Ghost", 3.101], ["Ghost_Skull", 3.101],
		["Glub", 2.351], ["Glub_Evolved", 3.707], ["Goleling", 1.552],
		["Goleling_Evolved", 2.568], ["Hywirl", 2.745], ["Pigeon", 1.370],
		["Squidle", 1.987], ["Tribal", 4.108],
	]:
		out.append(
			_quaternius(
				"flying", row[0], row[1], Family.QUATERNIUS_FLYING, PackedInt32Array(),
				NavProfileScript.Id.UNDEAD, "flying rig: hovers, and has no ground locomotion clip"
			)
		)
	return out


static func _kaykit(
	name: String, height: float, slots: PackedInt32Array, bone: String, prop: String
) -> Entry:
	var e := Entry.new()
	e.id = "kaykit/%s" % name
	e.path = "%s/%s.glb" % [KAYKIT_DIR, name]
	e.family = Family.KAYKIT_SKELETON
	e.slots = slots
	e.measured_height = height
	e.collider_height = REFERENCE_HEIGHT
	e.nav_profile = NavProfileScript.Id.UNDEAD
	e.prop_bone = bone
	e.prop_path = prop
	return e


static func _quaternius(
	family_dir: String,
	name: String,
	height: float,
	family: Family,
	slots: PackedInt32Array,
	nav_profile: int,
	note: String
) -> Entry:
	var e := Entry.new()
	e.id = "%s/%s" % [family_dir, name]
	e.path = "%s/%s/%s.glb" % [QUATERNIUS_DIR, family_dir, name]
	e.family = family
	e.slots = slots
	e.measured_height = height
	e.collider_height = height
	e.nav_profile = nav_profile
	e.note = note
	return e


## Same mesh path as `family_dir/name`, but a distinct catalogue id (encounter variants).
static func _alias_quaternius(
	id: String,
	family_dir: String,
	name: String,
	height: float,
	family: Family,
	slots: PackedInt32Array,
	nav_profile: int,
	note: String
) -> Entry:
	var e := _quaternius(family_dir, name, height, family, slots, nav_profile, note)
	e.id = id
	return e
