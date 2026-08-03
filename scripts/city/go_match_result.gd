## Outcome of a finished Go match (area score + how it ended).
class_name GoMatchResult
extends RefCounted

## "resign_b", "resign_w", "two_passes", or "stopped".
var reason: String = ""
## GoBoardState.BLACK, WHITE, or 0 for jigo.
var winner: int = 0
var black_score: float = 0.0
## Includes komi.
var white_score: float = 0.0
var komi: float = 7.5
var board_n: int = 19


static func from_board(board: GoBoardState, p_reason: String, p_komi: float = 7.5) -> GoMatchResult:
	var r := GoMatchResult.new()
	r.reason = p_reason
	r.komi = p_komi
	r.board_n = board.size if board != null else 19
	var scored: Dictionary = board.score_tromp_taylor(p_komi) if board != null else {}
	r.black_score = float(scored.get("black", 0.0))
	r.white_score = float(scored.get("white", 0.0))
	if p_reason == "resign_b":
		r.winner = GoBoardState.WHITE
	elif p_reason == "resign_w":
		r.winner = GoBoardState.BLACK
	elif r.black_score > r.white_score:
		r.winner = GoBoardState.BLACK
	elif r.white_score > r.black_score:
		r.winner = GoBoardState.WHITE
	else:
		r.winner = 0
	return r


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


func reason_line() -> String:
	if reason == "stopped":
		return "Stopped · area so far · komi %.1f" % komi
	if reason == "resign_b":
		return "Black resigned"
	if reason == "resign_w":
		return "White resigned"
	if reason == "two_passes":
		return "Area score · Tromp-Taylor · komi %.1f" % komi
	return reason
