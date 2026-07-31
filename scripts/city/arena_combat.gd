## Shared arena fight helpers: mark units that belong to an ArenaController wipe roster.
class_name ArenaCombat
extends RefCounted

const META_OWNED := &"arena_owned"


## Stamp ownership so Clear / wipe can find arena summons.
static func tag_unit(unit: Node) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	unit.set_meta(META_OWNED, true)


static func is_arena_owned(unit: Node) -> bool:
	return (
		unit != null
		and is_instance_valid(unit)
		and unit.has_meta(META_OWNED)
		and bool(unit.get_meta(META_OWNED))
	)
