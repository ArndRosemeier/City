## Setup and in-play controls beside the monster-chess court.
##
## A vertical plate on the west apron, facing the way a player arrives from the Go garden:
## pick who plays each army and how hard the AI thinks, then watch the same plate report
## whose turn it is and what the search saw.
class_name ChessSettingsUi3D
extends Ui3D

const ChessBoardStateScript := preload("res://scripts/city/chess_board_state.gd")
const ChessSessionScript := preload("res://scripts/city/chess_session.gd")
const ChessCastScript := preload("res://scripts/city/chess_cast.gd")

signal start_pressed(
	white_human: bool, white_level: StringName, black_human: bool, black_level: StringName
)
signal resign_pressed()

const BTN_WH := &"white_human"
const BTN_WA := &"white_ai"
const BTN_WM := &"white_minus"
const BTN_WL := &"white_level"
const BTN_WP := &"white_plus"
const BTN_BH := &"black_human"
const BTN_BA := &"black_ai"
const BTN_BM := &"black_minus"
const BTN_BL := &"black_level"
const BTN_BP := &"black_plus"
const BTN_START := &"start"
const BTN_RESIGN := &"resign"

var white_human: bool = true
var black_human: bool = false
var white_level: StringName = &"club"
var black_level: StringName = &"club"
var input_enabled: bool = true

var _mode: StringName = &"setup"
## Whose turn it is, and whether the AI is thinking about it. Match mode only.
var _turn: int = 0
var _thinking: bool = false
## Depth / score / nodes / ms of the last AI move, or an empty line before the first one.
var _search_line: String = ""
## Why the game ended, shown until the next one starts.
var _result_line: String = ""


func setup(origin: Vector3, face_yaw: float, panel_w: float = 2.6) -> void:
	size_m = Vector2(panel_w, panel_w * 1.35)
	surface_color = Color(0.2, 0.24, 0.2, 1.0)
	show_debug_marker = false
	begin(origin, face_yaw)
	_rebuild_chrome()
	if not button_pressed.is_connected(_on_button):
		button_pressed.connect(_on_button)


func show_setup() -> void:
	_mode = &"setup"
	input_enabled = true
	_thinking = false
	_search_line = ""
	_rebuild_chrome()


func show_match() -> void:
	_mode = &"match"
	input_enabled = true
	_result_line = ""
	_rebuild_chrome()


func set_turn(colour: int, thinking: bool) -> void:
	if _turn == colour and _thinking == thinking:
		return
	_turn = colour
	_thinking = thinking
	if _mode == &"match":
		_rebuild_chrome()


func set_search(depth: int, score: int, nodes: int, ms: int) -> void:
	## Score is always from the mover's own point of view, so a positive number means the
	## side that just moved likes where it is — no sign convention to remember.
	_search_line = "d%d  %+.2f  %dk in %dms" % [depth, float(score) / 100.0, nodes / 1000, ms]
	if _mode == &"match":
		_rebuild_chrome()


func set_result(reason: String) -> void:
	_result_line = describe_result(reason)
	_mode = &"setup"
	input_enabled = true
	_rebuild_chrome()


## Plain-language ending, for the plate and the log.
static func describe_result(reason: String) -> String:
	match reason:
		"mate_white_wins":
			return "Beast wins by mate"
		"mate_black_wins":
			return "Grove wins by mate"
		"stalemate":
			return "Draw — stalemate"
		"fifty_move":
			return "Draw — fifty moves"
		"threefold":
			return "Draw — threefold"
		"resign_white":
			return "Beast resigned"
		"resign_black":
			return "Grove resigned"
		"stopped":
			return "Game stopped"
	push_error("ChessSettingsUi3D.describe_result: unknown reason '%s'" % reason)
	return reason


func _rebuild_chrome() -> void:
	clear_buttons()
	if _mode == &"match":
		_rebuild_match_chrome()
	else:
		_rebuild_setup_chrome()
	rebuild_buttons()


func _rebuild_setup_chrome() -> void:
	add_button(
		&"hdr", Rect2(0.06, 0.91, 0.88, 0.07), "Monster chess", Color(0.3, 0.36, 0.3), true
	)
	if not _result_line.is_empty():
		add_button(
			&"result", Rect2(0.06, 0.83, 0.88, 0.06), _result_line, Color(0.36, 0.3, 0.2), true
		)
	add_button(
		&"wlbl", Rect2(0.06, 0.72, 0.88, 0.07), "Beast (white)", Color(0.5, 0.42, 0.3), true
	)
	_add_side_row(0.6, true)
	add_button(
		&"blbl", Rect2(0.06, 0.4, 0.88, 0.07), "Grove (black)", Color(0.22, 0.4, 0.26), true
	)
	_add_side_row(0.28, false)
	add_button(BTN_START, Rect2(0.06, 0.05, 0.88, 0.11), "Start", Color(0.28, 0.55, 0.36), true)


func _rebuild_match_chrome() -> void:
	add_button(&"hdr", Rect2(0.06, 0.91, 0.88, 0.07), "In play", Color(0.3, 0.36, 0.3), true)
	var side := ChessCastScript.colour_name(_turn) if _turn != 0 else "?"
	var turn_txt := "%s thinking…" % side if _thinking else "%s to move" % side
	var turn_col := (
		Color(0.5, 0.42, 0.3) if _turn == ChessBoardStateScript.WHITE else Color(0.22, 0.4, 0.26)
	)
	add_button(&"turn", Rect2(0.06, 0.78, 0.88, 0.1), turn_txt, turn_col, true)
	add_button(
		&"wlbl",
		Rect2(0.06, 0.66, 0.88, 0.08),
		"Beast: %s" % _side_label(white_human, white_level),
		Color(0.3, 0.28, 0.24),
		true
	)
	add_button(
		&"blbl",
		Rect2(0.06, 0.56, 0.88, 0.08),
		"Grove: %s" % _side_label(black_human, black_level),
		Color(0.24, 0.3, 0.26),
		true
	)
	var search_txt := _search_line if not _search_line.is_empty() else "—"
	add_button(&"search", Rect2(0.06, 0.42, 0.88, 0.09), search_txt, Color(0.2, 0.22, 0.26), true)
	var abort := "STOP" if _is_ai_only() else "Resign"
	add_button(BTN_RESIGN, Rect2(0.06, 0.08, 0.88, 0.13), abort, Color(0.4, 0.15, 0.15), true)


func _add_side_row(y: float, is_white: bool) -> void:
	var human := white_human if is_white else black_human
	var level := white_level if is_white else black_level
	var bh := BTN_WH if is_white else BTN_BH
	var ba := BTN_WA if is_white else BTN_BA
	var bm := BTN_WM if is_white else BTN_BM
	var bl := BTN_WL if is_white else BTN_BL
	var bp := BTN_WP if is_white else BTN_BP
	var hc := Color(0.35, 0.55, 0.38) if human else Color(0.22, 0.24, 0.28)
	var ac := Color(0.35, 0.42, 0.62) if not human else Color(0.22, 0.24, 0.28)
	add_button(bh, Rect2(0.06, y, 0.42, 0.08), "Human", hc, true)
	add_button(ba, Rect2(0.52, y, 0.42, 0.08), "AI", ac, true)
	var ry := y - 0.1
	if human:
		add_button(bl, Rect2(0.06, ry, 0.88, 0.08), "(human)", Color(0.2, 0.22, 0.26), true)
	else:
		add_button(bm, Rect2(0.06, ry, 0.18, 0.08), "-", Color(0.25, 0.28, 0.32), true)
		add_button(bl, Rect2(0.28, ry, 0.44, 0.08), String(level), Color(0.18, 0.22, 0.28), true)
		add_button(bp, Rect2(0.76, ry, 0.18, 0.08), "+", Color(0.25, 0.28, 0.32), true)


func _side_label(human: bool, level: StringName) -> String:
	return "human" if human else "AI %s" % String(level)


func _is_ai_only() -> bool:
	return not white_human and not black_human


func _on_button(button_id: StringName, _uv: Vector2) -> void:
	if not input_enabled:
		return
	if _mode == &"match":
		if button_id == BTN_RESIGN:
			resign_pressed.emit()
		return
	match button_id:
		BTN_WH:
			white_human = true
			_rebuild_chrome()
		BTN_WA:
			white_human = false
			_rebuild_chrome()
		BTN_BH:
			black_human = true
			_rebuild_chrome()
		BTN_BA:
			black_human = false
			_rebuild_chrome()
		BTN_WM:
			_step_level(true, -1)
		BTN_WP:
			_step_level(true, 1)
		BTN_BM:
			_step_level(false, -1)
		BTN_BP:
			_step_level(false, 1)
		BTN_START:
			start_pressed.emit(white_human, white_level, black_human, black_level)
		_:
			pass


func _step_level(is_white: bool, step: int) -> void:
	if is_white:
		if white_human:
			return
		white_level = ChessSessionScript.next_level(white_level, step)
	else:
		if black_human:
			return
		black_level = ChessSessionScript.next_level(black_level, step)
	_rebuild_chrome()
