## One candidate move the AI's search considered, normalized to Black's perspective.
class_name GoEvalCandidate
extends RefCounted

## GTP vertex ("D4") or "pass".
var vertex: String = ""
## Board coordinates, or Vector2i(-1, -1) for pass / unparseable.
var loc: Vector2i = Vector2i(-1, -1)
var visits: int = 0
## 0..1, Black's chance to win.
var winrate_black: float = 0.5
## Points; positive means Black is ahead.
var lead_black: float = 0.0
## 0 is the search's preferred move.
var order: int = 0


func is_on_board() -> bool:
	return loc.x >= 0 and loc.y >= 0
