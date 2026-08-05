## Things a monster perceives from anywhere on the map, whatever the range and whatever is in the
## way.
##
## Normal target acquisition is earned: `UndeadGoalProvider` needs the prey inside `aggro_range_m`
## with voxel line of sight, and it drops it again past the leash. A siege stone 120 m away in
## another quarter fails every one of those tests, so without this the horde would mill about at
## the gate it walked out of. A beacon is transplanted straight into awareness instead — the goal
## system reads it directly and skips aggro, sight and leash entirely.
##
## Deliberately generic. Anything that should pull a horde across a tile registers a beacon rather
## than growing its own aggro wiring; the Siege Quarter's five stones are simply the first caller.
class_name BeaconRegistry
extends RefCounted

## One perceivable objective.
##
## `audience_faction` is what gates who cares. The stones stand in ordinary city, so a beacon every
## faction could see would have ambient wildlife chewing the north stone down before wave one —
## under the district alive cap, which would then starve the siege of the bodies it wanted to spawn.
class Entry:
	extends RefCounted

	var id: int = 0
	var pos: Vector3 = Vector3.ZERO
	## Where a body stops walking and starts hitting. Mirrors a stone's vulnerability radius, so
	## "arrived" and "hurting it" are the same test.
	var hold_radius_m: float = 1.5
	var audience_faction: int = -1
	## False leaves the beacon registered but unpickable — used for nothing yet, and kept because
	## the centre Lodestone's shielded state is a `targetable` question the moment arcs get teeth.
	var targetable: bool = true

	func describe() -> String:
		return (
			"beacon#%d at %v r=%.1f for faction %d%s"
			% [id, pos, hold_radius_m, audience_faction, "" if targetable else " (untargetable)"]
		)


## How much closer a rival beacon has to be before a body switches to it. Without this a body
## standing between two stones flips its goal every query and walks nowhere.
const STICKY_SLACK_M := 8.0

var _entries: Array[Entry] = []
var _next_id: int = 1


## Returns the new beacon's id. Ids are never reused, so a stale sticky id cannot resolve to a
## different stone after the one it named was destroyed.
func register(pos: Vector3, hold_radius_m: float, audience_faction: int) -> int:
	if hold_radius_m <= 0.0:
		push_error("BeaconRegistry.register: hold radius %f is not usable" % hold_radius_m)
		assert(false, "BeaconRegistry: bad hold radius")
		return 0
	if audience_faction < 0:
		push_error("BeaconRegistry.register: no audience faction")
		assert(false, "BeaconRegistry: bad audience faction")
		return 0
	var e := Entry.new()
	e.id = _next_id
	_next_id += 1
	e.pos = pos
	e.hold_radius_m = hold_radius_m
	e.audience_faction = audience_faction
	_entries.append(e)
	return e.id


func unregister(id: int) -> void:
	for i in range(_entries.size()):
		if _entries[i].id == id:
			_entries.remove_at(i)
			return
	push_error("BeaconRegistry.unregister: no beacon #%d" % id)


func set_targetable(id: int, on: bool) -> void:
	var e := entry(id)
	if e == null:
		push_error("BeaconRegistry.set_targetable: no beacon #%d" % id)
		return
	e.targetable = on


func entry(id: int) -> Entry:
	for e: Entry in _entries:
		if e.id == id:
			return e
	return null


func has(id: int) -> bool:
	return entry(id) != null


func count() -> int:
	return _entries.size()


func is_empty() -> bool:
	return _entries.is_empty()


## Drop every beacon a faction was meant to perceive. The siege calls this when a run ends, so a
## banked pot cannot leave the horde walking to stones that are no longer anybody's objective.
func clear_audience(audience_faction: int) -> void:
	var kept: Array[Entry] = []
	for e: Entry in _entries:
		if e.audience_faction != audience_faction:
			kept.append(e)
	_entries = kept


## The beacon `faction` should walk to from `from`, or null when it has none.
##
## Nearest by straight line, not by path length: ranking real path cost for thirty-odd bodies on
## every re-evaluation is not worth what it buys, and the approach is open city either way. Pass the
## beacon this body walked to last as `sticky_id` to get the hysteresis — a dead or deregistered id
## simply loses, which is what makes a stone falling retarget everything that was chewing it.
func nearest_for(faction: int, from: Vector3, sticky_id: int = 0) -> Entry:
	var best: Entry = null
	var best_d := INF
	var sticky_d := INF
	for e: Entry in _entries:
		if not e.targetable or e.audience_faction != faction:
			continue
		var d := Vector2(e.pos.x - from.x, e.pos.z - from.z).length()
		if e.id == sticky_id:
			sticky_d = d
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return null
	if sticky_d < INF and sticky_d - best_d <= STICKY_SLACK_M:
		return entry(sticky_id)
	return best
