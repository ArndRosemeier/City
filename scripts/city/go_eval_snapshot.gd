## Root statistics harvested from the AI's own genmove search — no extra search cost.
##
## Every winrate and lead is stored from Black's perspective so the table UI never has
## to know which colour was thinking.
class_name GoEvalSnapshot
extends RefCounted

const GoEvalCandidateScript := preload("res://scripts/city/go_eval_candidate.gd")

## Colour whose search produced these numbers.
var searched_color: int = GoBoardState.BLACK
## Vertex that search actually played ("D4" / "pass" / "resign").
var chosen_vertex: String = ""
var chosen_loc: Vector2i = Vector2i(-1, -1)
## 0..1, Black's chance to win.
var winrate_black: float = 0.5
## Points; positive means Black is ahead.
var lead_black: float = 0.0
var visits: int = 0
var board_n: int = 19
## Sorted best-first (candidate.order ascending).
var candidates: Array[GoEvalCandidate] = []


## Returns null when the engine reported nothing usable — callers should treat that as
## "no eval yet" rather than as a zeroed snapshot.
static func from_engine_json(
	json_text: String, color: int, vertex: String, p_board_n: int
) -> GoEvalSnapshot:
	if json_text.strip_edges().is_empty():
		return null
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var root: Dictionary = parsed
	if not root.has("visits") or not root.has("winrate_black"):
		return null
	var snap := GoEvalSnapshot.new()
	snap.searched_color = color
	snap.chosen_vertex = vertex
	snap.board_n = p_board_n
	snap.winrate_black = clampf(float(root.get("winrate_black", 0.5)), 0.0, 1.0)
	snap.lead_black = float(root.get("lead_black", 0.0))
	snap.visits = int(root.get("visits", 0))
	snap.chosen_loc = _loc_of(vertex, p_board_n)
	var raw: Variant = root.get("candidates", [])
	if typeof(raw) == TYPE_ARRAY:
		for entry: Variant in raw as Array:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var d: Dictionary = entry
			var cand: GoEvalCandidate = GoEvalCandidateScript.new() as GoEvalCandidate
			cand.vertex = str(d.get("vertex", ""))
			cand.loc = _loc_of(cand.vertex, p_board_n)
			cand.visits = int(d.get("visits", 0))
			cand.winrate_black = clampf(float(d.get("winrate_black", 0.5)), 0.0, 1.0)
			cand.lead_black = float(d.get("lead_black", 0.0))
			cand.order = int(d.get("order", 0))
			snap.candidates.append(cand)
	snap.candidates.sort_custom(
		func(a: GoEvalCandidate, b: GoEvalCandidate) -> bool: return a.order < b.order
	)
	return snap


## Highest visit count among the candidates — the scale for marker sizes.
func top_visits() -> int:
	var best := 0
	for c in candidates:
		best = maxi(best, c.visits)
	return best


func winrate_line() -> String:
	return "Black %d%%   ·   %dv" % [int(round(winrate_black * 100.0)), visits]


func lead_line() -> String:
	if absf(lead_black) < 0.05:
		return "Lead   even"
	if lead_black > 0.0:
		return "Lead   B+%.1f" % lead_black
	return "Lead   W+%.1f" % -lead_black


static func _loc_of(vertex: String, n: int) -> Vector2i:
	var v := vertex.strip_edges().to_lower()
	if v.is_empty() or v == "pass" or v == "resign":
		return Vector2i(-1, -1)
	var loc := GoBoardState.parse_vertex(vertex, n)
	if loc.x < 0 or loc.y < 0 or loc.x >= n or loc.y >= n:
		return Vector2i(-1, -1)
	return loc
