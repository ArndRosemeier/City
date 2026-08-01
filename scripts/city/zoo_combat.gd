## Marks the bodies the Monster Zoo's stations put on the field.
##
## The zoo's census and its unload wipe both need to tell its own war apart from whatever
## else is walking the city, and a district that streams out has to take its forty
## territories' worth of monsters with it rather than leaving them fighting in empty space.
class_name ZooCombat
extends RefCounted

const META_OWNED := &"zoo_owned"
## Territory index the unit was spawned into, so the census does not have to re-resolve
## every body's position against the ownership grid every tick.
const META_TERRITORY := &"zoo_territory"


static func tag_unit(unit: Node, territory: int) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	unit.set_meta(META_OWNED, true)
	unit.set_meta(META_TERRITORY, territory)


static func is_zoo_owned(unit: Node) -> bool:
	return (
		unit != null
		and is_instance_valid(unit)
		and unit.has_meta(META_OWNED)
		and bool(unit.get_meta(META_OWNED))
	)


## Territory the unit was spawned into, or -1 when it is not a zoo body.
static func territory_of(unit: Node) -> int:
	if not is_zoo_owned(unit) or not unit.has_meta(META_TERRITORY):
		return -1
	return int(unit.get_meta(META_TERRITORY))
