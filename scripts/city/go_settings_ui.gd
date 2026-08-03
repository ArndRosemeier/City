## Match setup / in-play controls beside the Go board.
class_name GoSettingsUi3D
extends Ui3D

const GoRankScript := preload("res://scripts/city/go_rank.gd")

signal start_pressed(
	black_human: bool, black_rank: String, white_human: bool, white_rank: String, board_n: int
)
signal board_size_changed(board_n: int)
signal pass_pressed()
signal resign_pressed()

const BTN_N9 := &"board_9"
const BTN_N19 := &"board_19"
const BTN_BH := &"black_human"
const BTN_BA := &"black_ai"
const BTN_BM := &"black_minus"
const BTN_BR := &"black_rank"
const BTN_BP := &"black_plus"
const BTN_WH := &"white_human"
const BTN_WA := &"white_ai"
const BTN_WM := &"white_minus"
const BTN_WR := &"white_rank"
const BTN_WP := &"white_plus"
const BTN_START := &"start"
const BTN_PASS := &"pass"
const BTN_RESIGN := &"resign"

var black_human: bool = true
var white_human: bool = false
var black_rank: String = "5k"
var white_rank: String = "5k"
var board_n: int = 19
var input_enabled: bool = true
var _mode: StringName = &"setup"
var _match_actions_enabled: bool = false
## Latest root stats from an AI search, or null before the first AI move.
var _eval: GoEvalSnapshot = null


func setup(origin: Vector3, face_yaw: float, panel_w: float = 1.9) -> void:
	size_m = Vector2(panel_w, panel_w * 1.45)
	## Light plate so the face reads clearly from above (not a near-black slab).
	surface_color = Color(0.78, 0.74, 0.68, 1.0)
	show_debug_marker = false
	begin(origin, face_yaw)
	## +90° lays the Ui3D face up (−Z → +Y). −90° buried the face in the timber.
	rotation.x = deg_to_rad(90.0)
	_rebuild_chrome()
	if not button_pressed.is_connected(_on_button):
		button_pressed.connect(_on_button)


func show_setup() -> void:
	_mode = &"setup"
	input_enabled = true
	_match_actions_enabled = false
	_eval = null
	_rebuild_chrome()


func show_match() -> void:
	_mode = &"match"
	input_enabled = true
	_rebuild_chrome()


func set_match_actions_enabled(on: bool) -> void:
	_match_actions_enabled = on


## Free root stats from the AI's own search. Only the two eval strips repaint.
func set_eval(snapshot: GoEvalSnapshot) -> void:
	if snapshot == null:
		push_error("GoSettingsUi3D.set_eval: null snapshot — call clear_eval instead")
		return
	_eval = snapshot
	if _mode == &"match":
		_rebuild_chrome()


func clear_eval() -> void:
	if _eval == null:
		return
	_eval = null
	if _mode == &"match":
		_rebuild_chrome()


func set_input_enabled(on: bool) -> void:
	input_enabled = on


func set_board_n(n: int) -> void:
	if n != 9 and n != 19:
		push_error("GoSettingsUi3D.set_board_n: unsupported %d" % n)
		return
	if board_n == n:
		return
	board_n = n
	if _mode == &"setup":
		_rebuild_chrome()
	board_size_changed.emit(board_n)


func _rebuild_chrome() -> void:
	clear_buttons()
	if _mode == &"match":
		_rebuild_match_chrome()
	else:
		_rebuild_setup_chrome()
	rebuild_buttons()


func _rebuild_setup_chrome() -> void:
	## UV y grows with local +Y; after +90° lay-flat that reads toward the table's north.
	## Put Start near the player (south / low UV y).
	add_button(&"hdr", Rect2(0.06, 0.91, 0.88, 0.07), "Match setup", Color(0.32, 0.36, 0.42), true)

	var c9 := Color(0.35, 0.55, 0.38) if board_n == 9 else Color(0.22, 0.24, 0.28)
	var c19 := Color(0.35, 0.55, 0.38) if board_n == 19 else Color(0.22, 0.24, 0.28)
	## Mirrored like the Human/AI row: left-from-seat is high UV x.
	add_button(BTN_N19, Rect2(0.52, 0.81, 0.42, 0.08), "19×19", c19, true)
	add_button(BTN_N9, Rect2(0.06, 0.81, 0.42, 0.08), "9×9", c9, true)

	add_button(&"blbl", Rect2(0.06, 0.71, 0.88, 0.07), "Black", Color(0.18, 0.18, 0.2), true)
	_add_side_row(0.58, true)

	add_button(&"wlbl", Rect2(0.06, 0.38, 0.88, 0.07), "White", Color(0.62, 0.62, 0.66), true)
	_add_side_row(0.25, false)

	## Same footprint as the header strip — tall Start was covering White's rank row.
	add_button(
		BTN_START,
		Rect2(0.06, 0.04, 0.88, 0.07),
		"Start",
		Color(0.28, 0.55, 0.36),
		true
	)


func _rebuild_match_chrome() -> void:
	add_button(&"hdr", Rect2(0.06, 0.9, 0.88, 0.07), "In play", Color(0.32, 0.36, 0.42), true)
	var size_lbl := "%d×%d" % [board_n, board_n]
	add_button(&"size", Rect2(0.06, 0.825, 0.88, 0.06), size_lbl, Color(0.28, 0.3, 0.34), true)
	var bl := "Black: human" if black_human else ("Black: AI " + GoRankScript.label(black_rank))
	var wl := "White: human" if white_human else ("White: AI " + GoRankScript.label(white_rank))
	add_button(&"blbl", Rect2(0.06, 0.73, 0.88, 0.08), bl, Color(0.18, 0.18, 0.2), true)
	add_button(&"wlbl", Rect2(0.06, 0.635, 0.88, 0.08), wl, Color(0.62, 0.62, 0.66), true)
	_add_eval_strips()
	add_button(BTN_PASS, Rect2(0.08, 0.28, 0.84, 0.14), "Pass", Color(0.2, 0.25, 0.35), true)
	## AI-only has no human to resign — STOP aborts the spectacle.
	var abort_lbl := "STOP" if _is_ai_only() else "Resign"
	add_button(BTN_RESIGN, Rect2(0.08, 0.08, 0.84, 0.14), abort_lbl, Color(0.4, 0.15, 0.15), true)


## What the AI's own search thought, in the band between the side labels and Pass.
## Em dashes until the first AI move, so the rows never jump around mid-match.
func _add_eval_strips() -> void:
	var win_txt := "Black —   ·   —"
	var lead_txt := "Lead   —"
	## Dark when Black leads, slate when White does — readable without reading.
	var win_col := Color(0.3, 0.32, 0.36)
	if _eval != null:
		win_txt = _eval.winrate_line()
		lead_txt = _eval.lead_line()
		win_col = Color(0.55, 0.56, 0.6).lerp(Color(0.1, 0.1, 0.12), _eval.winrate_black)
	add_button(&"eval_win", Rect2(0.06, 0.53, 0.88, 0.09), win_txt, win_col, true)
	add_button(&"eval_lead", Rect2(0.06, 0.43, 0.88, 0.09), lead_txt, Color(0.2, 0.22, 0.26), true)


func _add_side_row(y: float, is_black: bool) -> void:
	var human := black_human if is_black else white_human
	var rank := black_rank if is_black else white_rank
	var bh := BTN_BH if is_black else BTN_WH
	var ba := BTN_BA if is_black else BTN_WA
	var bm := BTN_BM if is_black else BTN_WM
	var br := BTN_BR if is_black else BTN_WR
	var bp := BTN_BP if is_black else BTN_WP
	var hc := Color(0.35, 0.55, 0.38) if human else Color(0.22, 0.24, 0.28)
	var ac := Color(0.35, 0.42, 0.62) if not human else Color(0.22, 0.24, 0.28)
	## UV x runs right-to-left as seen from the seat, so the rects are laid out mirrored
	## to put Human on the left and the +/- stepper the way round a player expects.
	add_button(bh, Rect2(0.52, y, 0.42, 0.08), "Human", hc, true)
	add_button(ba, Rect2(0.06, y, 0.42, 0.08), "AI", ac, true)
	var ry := y - 0.11
	if human:
		add_button(br, Rect2(0.06, ry, 0.88, 0.08), "(human)", Color(0.2, 0.22, 0.26), true)
	else:
		add_button(bm, Rect2(0.76, ry, 0.18, 0.08), "-", Color(0.25, 0.28, 0.32), true)
		add_button(br, Rect2(0.28, ry, 0.44, 0.08), GoRankScript.label(rank), Color(0.18, 0.22, 0.28), true)
		add_button(bp, Rect2(0.06, ry, 0.18, 0.08), "+", Color(0.25, 0.28, 0.32), true)


func _on_button(button_id: StringName, _uv: Vector2) -> void:
	if not input_enabled:
		return
	if _mode == &"match":
		match button_id:
			BTN_PASS:
				if _match_actions_enabled:
					pass_pressed.emit()
			BTN_RESIGN:
				## Always hittable: human resign on your turn, or STOP for AI-vs-AI.
				resign_pressed.emit()
			_:
				pass
		return
	match button_id:
		BTN_N9:
			set_board_n(9)
		BTN_N19:
			set_board_n(19)
		BTN_BH:
			black_human = true
			_rebuild_chrome()
		BTN_BA:
			black_human = false
			_rebuild_chrome()
		BTN_WH:
			white_human = true
			_rebuild_chrome()
		BTN_WA:
			white_human = false
			_rebuild_chrome()
		BTN_BM:
			if not black_human:
				black_rank = GoRankScript.step(black_rank, -1)
				_rebuild_chrome()
		BTN_BP:
			if not black_human:
				black_rank = GoRankScript.step(black_rank, 1)
				_rebuild_chrome()
		BTN_WM:
			if not white_human:
				white_rank = GoRankScript.step(white_rank, -1)
				_rebuild_chrome()
		BTN_WP:
			if not white_human:
				white_rank = GoRankScript.step(white_rank, 1)
				_rebuild_chrome()
		BTN_START:
			start_pressed.emit(black_human, black_rank, white_human, white_rank, board_n)
		_:
			pass


func _is_ai_only() -> bool:
	return not black_human and not white_human
