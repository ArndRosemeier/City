## Outcome of a finished Go match (how it ended + both common score tallies).
##
## Japanese is the match default: territory + prisoners. Chinese / Tromp-Taylor area
## (stones + territory) is kept beside it so the end panel can switch without replaying.
class_name GoMatchResult
extends RefCounted

const RULES_JAPANESE := &"japanese"
const RULES_CHINESE := &"chinese"

## "resign_b", "resign_w", "two_passes", or "stopped".
var reason: String = ""
## GoBoardState.BLACK, WHITE, or 0 for jigo — under the active `rules`.
var winner: int = 0
## Active display / winner rules. Resign ignores score either way.
var rules: StringName = RULES_JAPANESE
var black_score: float = 0.0
## Includes komi.
var white_score: float = 0.0
var komi: float = 6.5
var board_n: int = 19
var black_japanese: float = 0.0
var white_japanese: float = 0.0
var black_chinese: float = 0.0
var white_chinese: float = 0.0


static func from_board(board: GoBoardState, p_reason: String, p_komi: float = 6.5) -> GoMatchResult:
	var r := GoMatchResult.new()
	r.reason = p_reason
	r.komi = p_komi
	r.board_n = board.size if board != null else 19
	r.rules = RULES_JAPANESE
	if board != null:
		var jp: Dictionary = board.score_japanese(p_komi)
		r.black_japanese = float(jp.get("black", 0.0))
		r.white_japanese = float(jp.get("white", 0.0))
		var cn: Dictionary = board.score_chinese(p_komi)
		r.black_chinese = float(cn.get("black", 0.0))
		r.white_chinese = float(cn.get("white", 0.0))
	r._apply_active_scores()
	return r


func set_rules(next: StringName) -> void:
	if next != RULES_JAPANESE and next != RULES_CHINESE:
		push_error("GoMatchResult.set_rules: unknown rules '%s'" % String(next))
		return
	rules = next
	_apply_active_scores()


func _apply_active_scores() -> void:
	if rules == RULES_CHINESE:
		black_score = black_chinese
		white_score = white_chinese
	else:
		black_score = black_japanese
		white_score = white_japanese
	if reason == "resign_b":
		winner = GoBoardState.WHITE
	elif reason == "resign_w":
		winner = GoBoardState.BLACK
	elif black_score > white_score:
		winner = GoBoardState.BLACK
	elif white_score > black_score:
		winner = GoBoardState.WHITE
	else:
		winner = 0


func winner_name() -> String:
	if winner == GoBoardState.BLACK:
		return "Black"
	if winner == GoBoardState.WHITE:
		return "White"
	return "Draw"


func headline() -> String:
	if reason == "stopped":
		return "Match stopped"
	if reason == "resign_b":
		return "White wins by resignation"
	if reason == "resign_w":
		return "Black wins by resignation"
	if winner == 0:
		return "Jigo — draw"
	return "%s wins" % winner_name()


func score_line() -> String:
	return "Black  %.1f      White  %.1f" % [black_score, white_score]


func rules_label() -> String:
	if rules == RULES_CHINESE:
		return "Chinese"
	return "Japanese"


func reason_line() -> String:
	if reason == "resign_b":
		return "Black resigned"
	if reason == "resign_w":
		return "White resigned"
	var style := "Territory + prisoners" if rules == RULES_JAPANESE else "Area (stones + territory)"
	if reason == "stopped":
		return "Stopped · %s · komi %.1f" % [style.to_lower(), komi]
	if reason == "two_passes":
		return "%s · %s · komi %.1f" % [rules_label(), style, komi]
	return reason
