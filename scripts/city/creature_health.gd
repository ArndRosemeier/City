## How much punishment each creature body takes, derived from the catalogue rather than
## hand-assigned.
##
## Fifty-four bodies is too many to tune one at a time, and a per-model number would go stale
## the moment the roster grows again. The catalogue already measures every body off the file,
## so toughness comes off that measurement: a taller body of a family is a tougher body of that
## family, and each family sets where its own scale starts.
##
## Height is read off `collider_height`, the same field the collision capsule uses, because that
## is already the catalogue's answer to "how big is this body really" — all four KayKit
## skeletons share one rig and one body, so the mage's hat measures 2.63 units and still gets
## the shared body's 2.166.
##
## The Blob family is the reason the height term is not one rule for everybody. Its
## `collider_height` *is* its raw measured height, and a Blob's height is substantially
## decoration: `Mushnub_Evolved` measures 4.41 units because of a mushroom cap and
## `GreenSpikyBlob` 4.14 because of spikes, while the actual body under both is about the size
## of the 1.85-unit `GreenBlob`. Taking those at face value would make a small blob in a tall
## hat tougher than a Quaternius Big monster twice its bulk. So Blob heights go through a square
## root: the tallest blob still outlasts the shortest by half again, which is honest — it is a
## bigger silhouette — but the whole family stays inside its own band, below every Big monster.
class_name CreatureHealth
extends RefCounted

const CreatureCatalogScript := preload("res://scripts/city/creature_catalog.gd")
const DamageSourceScript := preload("res://scripts/city/damage_source.gd")

## Health at or under this counts as dead. Not zero: a tier that is an exact multiple of a
## damage amount has to fall on the hit that spends it, and float arithmetic does not promise
## that 34.0 - 34.0 stays on the right side of a bare `<= 0.0` once either number is derived
## from a measurement.
const LETHAL_EPSILON := 0.001

## Health of a body standing exactly at its family's reference height.
##
## KayKit skeletons are the floor of the roster: 34 points is one punch, which keeps the fodder
## dying the way it always has. A Quaternius Big monster is a real fight at 110 — three or four
## punches, or one stomp. The Blob set are pack animals at 45 and die in two of anything.
const BASE_KAYKIT := 34.0
const BASE_QUATERNIUS_BIG := 110.0
const BASE_QUATERNIUS_BLOB := 45.0
## Vendored, in no spawn table, and still given a number: an undefined health is worse than an
## unused one.
const BASE_QUATERNIUS_FLYING := 45.0

## The height each family's base is quoted at. KayKit's is the shared body every skeleton in the
## catalogue collides as; the two Quaternius numbers sit in the middle of their measured ranges
## (Big 2.70–3.96, Blob 1.80–4.41).
const REFERENCE_KAYKIT := CreatureCatalogScript.REFERENCE_HEIGHT
const REFERENCE_QUATERNIUS_BIG := 3.2
const REFERENCE_QUATERNIUS_BLOB := 2.4

## How hard height pushes on health, per family. 1.0 is proportional; 0.5 is the square root the
## file comment explains. KayKit is proportional and every KayKit body is the same height, so
## the exponent never bites there.
const EXPONENT_PROPORTIONAL := 1.0
const EXPONENT_DECORATED := 0.5

## A grown giant is tougher than the body it grew out of, but not by its full ten times over —
## `pow(scale, 0.85)` puts a 10× giant at about seven times its own base, which is five charged
## blasts for a mid-size monster and two for a skeleton.
const GIANT_SCALE_EXPONENT := 0.85


static func family_base(family: CreatureCatalog.Family) -> float:
	match family:
		CreatureCatalog.Family.KAYKIT_SKELETON:
			return BASE_KAYKIT
		CreatureCatalog.Family.QUATERNIUS_BIG:
			return BASE_QUATERNIUS_BIG
		CreatureCatalog.Family.QUATERNIUS_BLOB:
			return BASE_QUATERNIUS_BLOB
		CreatureCatalog.Family.QUATERNIUS_FLYING:
			return BASE_QUATERNIUS_FLYING
	push_error("CreatureHealth: no base health for family %d" % int(family))
	return 0.0


static func family_reference_height(family: CreatureCatalog.Family) -> float:
	match family:
		CreatureCatalog.Family.KAYKIT_SKELETON:
			return REFERENCE_KAYKIT
		CreatureCatalog.Family.QUATERNIUS_BIG:
			return REFERENCE_QUATERNIUS_BIG
		CreatureCatalog.Family.QUATERNIUS_BLOB:
			return REFERENCE_QUATERNIUS_BLOB
		CreatureCatalog.Family.QUATERNIUS_FLYING:
			return REFERENCE_QUATERNIUS_BLOB
	push_error("CreatureHealth: no reference height for family %d" % int(family))
	return 0.0


## Whether this family's measured height is a body height or a body plus its hat.
static func family_height_exponent(family: CreatureCatalog.Family) -> float:
	match family:
		CreatureCatalog.Family.KAYKIT_SKELETON:
			return EXPONENT_PROPORTIONAL
		CreatureCatalog.Family.QUATERNIUS_BIG:
			return EXPONENT_PROPORTIONAL
		CreatureCatalog.Family.QUATERNIUS_BLOB:
			return EXPONENT_DECORATED
		CreatureCatalog.Family.QUATERNIUS_FLYING:
			return EXPONENT_DECORATED
	push_error("CreatureHealth: no height exponent for family %d" % int(family))
	return EXPONENT_PROPORTIONAL


## Health this body has at its authored size, before any growth.
static func for_entry(entry: CreatureCatalog.Entry) -> float:
	if entry == null:
		push_error("CreatureHealth: no catalogue entry, so this body has no health tier")
		return 0.0
	var reference := family_reference_height(entry.family)
	if reference <= 0.0:
		return 0.0
	return family_base(entry.family) * pow(
		entry.collider_height / reference, family_height_exponent(entry.family)
	)


## Health this body has at `character_scale`, which is 1.0 for everything that has not stood on
## a grow pad.
static func for_scale(entry: CreatureCatalog.Entry, character_scale: float) -> float:
	if character_scale <= 0.0:
		push_error("CreatureHealth: character scale %f is not a size" % character_scale)
		return 0.0
	return for_entry(entry) * pow(character_scale, GIANT_SCALE_EXPONENT)


static func is_dead(health: float) -> bool:
	return health <= LETHAL_EPSILON


## How many hits of `source` it takes, counted the way `UndeadUnit.apply_damage` counts rather
## than by dividing — so a tier that is an exact multiple of the damage answers the same here as
## it does in the city.
static func hits_to_kill(health: float, source: DamageSource.Id) -> int:
	var per := DamageSourceScript.amount(source)
	if per <= 0.0:
		push_error(
			"CreatureHealth: %s deals no damage, so it never kills anything"
			% DamageSourceScript.source_name(source)
		)
		return 0
	var left := health
	var hits := 0
	while not is_dead(left):
		left -= per
		hits += 1
	return hits
