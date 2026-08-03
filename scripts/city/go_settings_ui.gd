## Match setup / in-play controls beside the Go board.
class_name GoSettingsUi3D
extends Ui3D

const GoRankScript := preload("res://scripts/city/go_rank.gd")

signal start_pressed(
	black_human: bool, black_rank: String, white_human: bool, white_rank: String
)
signal pass_pressed()
signal resign_pressed()

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
var input_enabled: bool = true
var _mode: StringName = &"setup"
var _match_actions_enabled: bool = false


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
	_rebuild_chrome()


func show_match() -> void:
	_mode = &"match"
	input_enabled = true
	_rebuild_chrome()


func set_match_actions_enabled(on: bool) -> void:
	_match_actions_enabled = on


func set_input_enabled(on: bool) -> void:
	input_enabled = on


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
	add_button(&"hdr", Rect2(0.06, 0.88, 0.88, 0.08), "Match setup", Color(0.32, 0.36, 0.42), true)

	add_button(&"blbl", Rect2(0.06, 0.76, 0.88, 0.07), "Black", Color(0.18, 0.18, 0.2), true)
	_add_side_row(0.62, true)

	add_button(&"wlbl", Rect2(0.06, 0.42, 0.88, 0.07), "White", Color(0.62, 0.62, 0.66), true)
	_add_side_row(0.28, false)

	add_button(
		BTN_START,
		Rect2(0.12, 0.06, 0.76, 0.14),
		"Start",
		Color(0.28, 0.55, 0.36),
		true
	)


func _rebuild_match_chrome() -> void:
	add_button(&"hdr", Rect2(0.06, 0.88, 0.88, 0.08), "In play", Color(0.32, 0.36, 0.42), true)
	var bl := "Black: human" if black_human else ("Black: AI " + GoRankScript.label(black_rank))
	var wl := "White: human" if white_human else ("White: AI " + GoRankScript.label(white_rank))
	add_button(&"blbl", Rect2(0.06, 0.72, 0.88, 0.1), bl, Color(0.18, 0.18, 0.2), true)
	add_button(&"wlbl", Rect2(0.06, 0.58, 0.88, 0.1), wl, Color(0.62, 0.62, 0.66), true)
	add_button(BTN_PASS, Rect2(0.08, 0.28, 0.84, 0.14), "Pass", Color(0.2, 0.25, 0.35), true)
	add_button(BTN_RESIGN, Rect2(0.08, 0.08, 0.84, 0.14), "Resign", Color(0.4, 0.15, 0.15), true)


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
	add_button(bh, Rect2(0.52, y, 0.42, 0.09), "Human", hc, true)
	add_button(ba, Rect2(0.06, y, 0.42, 0.09), "AI", ac, true)
	var ry := y - 0.12
	if human:
		add_button(br, Rect2(0.06, ry, 0.88, 0.09), "(human)", Color(0.2, 0.22, 0.26), true)
	else:
		add_button(bm, Rect2(0.76, ry, 0.18, 0.09), "-", Color(0.25, 0.28, 0.32), true)
		add_button(br, Rect2(0.28, ry, 0.44, 0.09), GoRankScript.label(rank), Color(0.18, 0.22, 0.28), true)
		add_button(bp, Rect2(0.06, ry, 0.18, 0.09), "+", Color(0.25, 0.28, 0.32), true)


func _on_button(button_id: StringName, _uv: Vector2) -> void:
	if not input_enabled:
		return
	if _mode == &"match":
		match button_id:
			BTN_PASS:
				if _match_actions_enabled:
					pass_pressed.emit()
			BTN_RESIGN:
				## Resign always available during a match so you can abort AI-vs-AI.
				resign_pressed.emit()
			_:
				pass
		return
	match button_id:
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
			start_pressed.emit(black_human, black_rank, white_human, white_rank)
		_:
			pass
