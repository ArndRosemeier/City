## Human-SL rank ladder tokens (KataGo rank_20k … rank_9d).
class_name GoRank
extends RefCounted

## Weak → strong order.
const RANKS: PackedStringArray = [
	"20k", "19k", "18k", "17k", "16k", "15k", "14k", "13k", "12k", "11k",
	"10k", "9k", "8k", "7k", "6k", "5k", "4k", "3k", "2k", "1k",
	"1d", "2d", "3d", "4d", "5d", "6d", "7d", "8d", "9d",
]

## Invite ped presets (outfit tiers) → default ranks.
const PRESET_RANKS := {
	"novice": "15k",
	"club": "5k",
	"dan": "1d",
}

static var RANK_INDEX: Dictionary = {}


static func _ensure_index() -> void:
	if not RANK_INDEX.is_empty():
		return
	for i in range(RANKS.size()):
		RANK_INDEX[RANKS[i]] = i


static func clamp_index(i: int) -> int:
	return clampi(i, 0, RANKS.size() - 1)


static func index_of(rank: String) -> int:
	_ensure_index()
	var t := rank.strip_edges().to_lower()
	if t.begins_with("rank_"):
		t = t.substr(5)
	return int(RANK_INDEX.get(t, 14)) ## default 5k


static func at(i: int) -> String:
	return RANKS[clamp_index(i)]


static func step(rank: String, delta: int) -> String:
	return at(index_of(rank) + delta)


static func preset_rank(tier: StringName) -> String:
	return str(PRESET_RANKS.get(String(tier), "5k"))


static func label(rank: String) -> String:
	return rank.strip_edges().to_lower()
