## Matches the run has going, one row per title. Today that is the Go table and the
## monster-chess court on the Gaming plaza.
##
## The rows are opaque here on purpose. This class owns *that* a game is in progress and
## survives a save, load or district hop — what a match consists of is the game's own
## business, and Go answers that in `GoSession.to_save_dict`.
##
## Nothing writes a finished match: the arena clears the row the moment a game ends, so a
## row in the save always means "there is a board waiting to be sat back down at".
class_name WorldGames
extends RefCounted

## Save key for the Go table. Other titles claim their own key at this level.
const GO_KEY := "go"
## Save key for the monster-chess court on the same tile's east lawn.
const CHESS_KEY := "chess"

## title key → the game's own snapshot
var _rows: Dictionary[String, Dictionary] = {}


func set_go(snapshot: Dictionary) -> void:
	set_row(GO_KEY, snapshot)


func clear_go() -> void:
	clear_row(GO_KEY)


func go_snapshot() -> Dictionary:
	return row(GO_KEY)


func has_go() -> bool:
	return _rows.has(GO_KEY)


func set_chess(snapshot: Dictionary) -> void:
	set_row(CHESS_KEY, snapshot)


func clear_chess() -> void:
	clear_row(CHESS_KEY)


func chess_snapshot() -> Dictionary:
	return row(CHESS_KEY)


func has_chess() -> bool:
	return _rows.has(CHESS_KEY)


## An empty snapshot is a caller that meant `clear_row` and did not say so — a row that
## claims a match but carries no board resumes into an empty table.
func set_row(key: String, snapshot: Dictionary) -> void:
	if key.is_empty():
		push_error("WorldGames.set_row: a game row needs a key")
		return
	if snapshot.is_empty():
		push_error("WorldGames.set_row: '%s' has nothing to resume from" % key)
		return
	_rows[key] = snapshot.duplicate(true)


func clear_row(key: String) -> void:
	_rows.erase(key)


## The stored snapshot, or an empty dictionary when this title has no match going. Callers
## get their own copy: the live game keeps mutating and the save must not follow along.
func row(key: String) -> Dictionary:
	if not _rows.has(key):
		return {}
	return (_rows[key] as Dictionary).duplicate(true)


func clear() -> void:
	_rows.clear()


# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------

func to_save_dict() -> Dictionary:
	var out := {}
	for key: String in _rows.keys():
		out[key] = (_rows[key] as Dictionary).duplicate(true)
	return out


func load_save_dict(data: Dictionary) -> void:
	_rows.clear()
	for raw_key: Variant in data.keys():
		var key := str(raw_key)
		var raw: Variant = data[raw_key]
		if typeof(raw) != TYPE_DICTIONARY:
			push_error("WorldGames: game row '%s' is not an object" % key)
			continue
		var snapshot: Dictionary = raw
		if snapshot.is_empty():
			push_error("WorldGames: game row '%s' is empty, so there is no match in it" % key)
			continue
		_rows[key] = snapshot.duplicate(true)
