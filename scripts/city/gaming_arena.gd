## Runtime Gaming district: one Go table (board + settings) + giant board sync.
class_name GamingArena
extends Node3D

const GoTableUi3DScript := preload("res://scripts/city/go_table_ui.gd")
const GoSettingsUi3DScript := preload("res://scripts/city/go_settings_ui.gd")
const GoGiantBoardScript := preload("res://scripts/city/go_giant_board.gd")
const GoSessionScript := preload("res://scripts/city/go_session.gd")
const GoPedActorScript := preload("res://scripts/city/go_ped_actor.gd")
const GoBoardStateScript := preload("res://scripts/city/go_board_state.gd")
const GoRankScript := preload("res://scripts/city/go_rank.gd")
const GoEnginePoolScript := preload("res://scripts/city/go_engine_pool.gd")
const GoEndPanelScript := preload("res://scripts/city/go_end_panel.gd")
const GoMoveArrowScript := preload("res://scripts/city/go_move_arrow.gd")

var layout: GamingLayout = null
var origin_vox: Vector3i = Vector3i.ZERO
var voxel_size: float = 0.5
var live_brush: Callable = Callable()
var _dseed: int = 0

var _main_board: GoBoardState = null
var _main_session: GoSession = null
var _main_table: GoTableUi3D = null
## Typed as Node — GoSettingsUi3D class_name may load after this file alphabetically.
var _settings: Node = null
var _giant: GoGiantBoard = null
var _end_panel: GoEndPanel = null
var _move_arrow: GoMoveArrow = null
var _black_ped: GoPedActor = null
var _white_ped: GoPedActor = null
var _match_active: bool = false


func setup(
	p_layout: GamingLayout,
	p_origin_vox: Vector3i,
	p_voxel_size: float,
	p_dseed: int,
	p_live_brush: Callable
) -> void:
	layout = p_layout
	origin_vox = p_origin_vox
	voxel_size = p_voxel_size
	_dseed = p_dseed
	live_brush = p_live_brush
	_spawn_main_views()
	_resume_saved_match()


func _exit_tree() -> void:
	## The row outlives the arena on purpose: streaming the district out must not forfeit a
	## game. Only finishing one clears it.
	_teardown_session("unload")
	GoEnginePoolScript.shutdown()


func interact_at_world(_pos: Vector3) -> bool:
	return false


func giant_board() -> GoGiantBoard:
	return _giant


func _spawn_main_views() -> void:
	_main_board = GoBoardStateScript.new() as GoBoardState
	_main_board.setup(layout.board_n)

	## Lay-flat panels only use yaw for in-plane spin: this is the one that puts the
	## text upright for someone standing at the south seat.
	var yaw := layout.main_table_yaw
	_main_table = GoTableUi3DScript.new() as GoTableUi3D
	_main_table.name = "MainGoTable"
	add_child(_main_table)
	_main_table.setup_board(
		_main_board, _slot_surface_world(GamingComposer.BOARD_X_FRAC), yaw, 3.0
	)
	_main_table.set_input_enabled(false)
	_main_table.vertex_chosen.connect(_on_player_vertex)

	_move_arrow = GoMoveArrowScript.new() as GoMoveArrow
	_move_arrow.name = "GoMoveArrow"
	add_child(_move_arrow)
	_main_table.move_herald = _herald_move

	_settings = GoSettingsUi3DScript.new()
	_settings.name = "GoSettings"
	add_child(_settings)
	_settings.call("setup", _slot_surface_world(GamingComposer.SETTINGS_X_FRAC), yaw, 1.9)
	_settings.set("board_n", layout.board_n)
	_settings.call("show_setup")
	_settings.connect("start_pressed", _on_start_match)
	_settings.connect("board_size_changed", _on_board_size_changed)
	_settings.connect("pass_pressed", _on_player_pass)
	_settings.connect("resign_pressed", _on_player_resign)

	_giant = GoGiantBoardScript.new() as GoGiantBoard
	_giant.name = "GiantGoBoard"
	add_child(_giant)
	_giant.setup(
		_main_board,
		live_brush,
		origin_vox,
		layout.giant_origin,
		layout.giant_cell_vox,
		voxel_size,
		layout.giant_span_vox()
	)

	_end_panel = GoEndPanelScript.new() as GoEndPanel
	_end_panel.name = "GoEndPanel"
	add_child(_end_panel)
	_end_panel.setup(_end_panel_world(), layout.main_table_yaw)
	_end_panel.dismissed.connect(_on_end_panel_dismissed)


func _on_board_size_changed(board_n: int) -> void:
	if layout == null or _match_active:
		return
	if board_n != 9 and board_n != 19:
		push_error("GamingArena: unsupported board_n %d" % board_n)
		return
	layout.board_n = board_n
	## Preview board only — no session yet. Both views retile immediately.
	_main_board = GoBoardStateScript.new() as GoBoardState
	_main_board.setup(board_n)
	if _main_table != null:
		_main_table.apply_board(_main_board)
		_main_table.set_input_enabled(false)
	if _giant != null:
		_giant.set_board_size(board_n, _main_board)


func _on_start_match(
	black_human: bool,
	black_rank: String,
	white_human: bool,
	white_rank: String,
	board_n: int
) -> void:
	if layout == null or _match_active:
		return
	if board_n != 9 and board_n != 19:
		push_error("GamingArena: unsupported board_n %d" % board_n)
		return
	layout.board_n = board_n
	_match_active = true
	_hide_end_panel()
	if _settings != null:
		_settings.call("show_match")

	_teardown_session("restart")
	_clear_ai_peds()

	_main_session = GoSessionScript.new() as GoSession
	_main_session.name = "MainGoSession"
	add_child(_main_session)
	## Board + input first; KataGo warms on a worker (or reuses a warm net). Human
	## Black can play while the opponent walks over.
	_main_session.begin_match(
		board_n, black_human, black_rank, white_human, white_rank
	)
	_main_board = _main_session.board
	if _giant != null:
		_giant.set_board_size(board_n, _main_board)
	_bind_main_board()
	_connect_session()
	_refresh_board_input()
	_sync_games_save()
	print(
		"GamingArena: start %dx%d black=%s white=%s"
		% [
			board_n,
			board_n,
			"human" if black_human else ("AI " + black_rank),
			"human" if white_human else ("AI " + white_rank),
		]
	)
	await _seat_ai_peds(black_human, black_rank, white_human, white_rank)
	if not is_inside_tree() or _main_session == null:
		return
	## Uses session flags (no-ops when a human is to move).
	_main_session.kick_ai_if_needed()


func _connect_session() -> void:
	_main_session.ai_thinking.connect(_on_ai_thinking)
	_main_session.session_ended.connect(_on_session_ended)
	_main_session.match_over.connect(_on_match_over)
	_main_session.eval_updated.connect(_on_eval_updated)
	_main_session.eval_cleared.connect(_on_eval_cleared)


func _seat_ai_peds(
	black_human: bool, black_rank: String, white_human: bool, white_rank: String
) -> void:
	var wait := _world_from_local_m(layout.ai_wait_local)
	var table := _slot_surface_world(0.5)
	## Count arrivals — never `await` each ped's signal in series. The second ped can
	## finish while we're still waiting on the first, and that emit is lost forever.
	var expected := 0
	var arrived := 0
	var on_arrive := func() -> void:
		arrived += 1
	if not black_human:
		_black_ped = _spawn_ai_ped(&"black", black_rank, wait)
		var seat_b := _world_from_local_m(layout.black_stand_local)
		expected += 1
		_black_ped.seat_reached.connect(on_arrive, CONNECT_ONE_SHOT)
		_black_ped.walk_path(
			_walk_waypoints(wait, seat_b, table), _yaw_toward(seat_b, table)
		)
	if not white_human:
		## Stagger second ped slightly so they don't occupy the same wait point.
		var wait_w := wait + Vector3(0.0, 0.0, 1.4)
		_white_ped = _spawn_ai_ped(&"white", white_rank, wait_w)
		var seat_w := _world_from_local_m(layout.white_stand_local)
		expected += 1
		_white_ped.seat_reached.connect(on_arrive, CONNECT_ONE_SHOT)
		_white_ped.walk_path(
			_walk_waypoints(wait_w, seat_w, table), _yaw_toward(seat_w, table)
		)
	while arrived < expected and is_inside_tree():
		await get_tree().process_frame


## Opponents for a resumed match are already at the table: the walk-in belongs to the
## session that started the game, not to every district stream-in afterwards.
func _seat_ai_peds_immediately() -> void:
	_clear_ai_peds()
	if _main_session == null:
		return
	var table := _slot_surface_world(0.5)
	if not _main_session.black_human:
		var seat_b := _world_from_local_m(layout.black_stand_local)
		_black_ped = _spawn_ai_ped(&"black", _main_session.black_rank, seat_b)
		_black_ped.seat_immediately(seat_b, _yaw_toward(seat_b, table))
	if not _main_session.white_human:
		var seat_w := _world_from_local_m(layout.white_stand_local)
		_white_ped = _spawn_ai_ped(&"white", _main_session.white_rank, seat_w)
		_white_ped.seat_immediately(seat_w, _yaw_toward(seat_w, table))


func _spawn_ai_ped(color_name: StringName, rank: String, at: Vector3) -> GoPedActor:
	var tier: StringName = GoRankScript.outfit_tier_for_rank(rank)
	var ped: GoPedActor = GoPedActorScript.new() as GoPedActor
	ped.name = "AiPed_%s" % String(color_name)
	add_child(ped)
	ped.begin_as_invite(at, tier, layout.main_table_yaw)
	return ped


func _clear_ai_peds() -> void:
	if _black_ped != null and is_instance_valid(_black_ped):
		_black_ped.queue_free()
	if _white_ped != null and is_instance_valid(_white_ped):
		_white_ped.queue_free()
	_black_ped = null
	_white_ped = null


func _walk_waypoints(from: Vector3, seat: Vector3, table: Vector3) -> Array[Vector3]:
	var half_w := float(GamingComposer.TABLE_W) * voxel_size * 0.5
	## Flank around the nearer table edge.
	var east_x := table.x + half_w + 2.2
	var west_x := table.x - half_w - 2.2
	var flank_x := east_x if from.x >= table.x else west_x
	return [
		Vector3(flank_x, seat.y, from.z),
		Vector3(flank_x, seat.y, seat.z),
		seat,
	]


func _yaw_toward(from: Vector3, to: Vector3) -> float:
	var look := to - from
	look.y = 0.0
	if look.length_squared() < 0.0001:
		return layout.main_table_yaw if layout != null else 0.0
	return atan2(-look.x, -look.z)


func _teardown_session(reason: String) -> void:
	_unbind_board_views()
	if _main_session == null:
		_main_board = null
		return
	if _main_session.ai_thinking.is_connected(_on_ai_thinking):
		_main_session.ai_thinking.disconnect(_on_ai_thinking)
	if _main_session.session_ended.is_connected(_on_session_ended):
		_main_session.session_ended.disconnect(_on_session_ended)
	if _main_session.match_over.is_connected(_on_match_over):
		_main_session.match_over.disconnect(_on_match_over)
	if _main_session.eval_updated.is_connected(_on_eval_updated):
		_main_session.eval_updated.disconnect(_on_eval_updated)
	if _main_session.eval_cleared.is_connected(_on_eval_cleared):
		_main_session.eval_cleared.disconnect(_on_eval_cleared)
	_main_session.end_session(reason)
	_main_session.queue_free()
	_main_session = null
	_main_board = null


func _unbind_board_views() -> void:
	if _move_arrow != null:
		_move_arrow.cancel()
	if _main_board != null:
		if _main_board.moved.is_connected(_on_board_moved):
			_main_board.moved.disconnect(_on_board_moved)
		if _main_board.passed.is_connected(_on_board_passed):
			_main_board.passed.disconnect(_on_board_passed)
	if _main_table != null:
		if _main_table.board != null:
			var tb: GoBoardState = _main_table.board
			if tb.moved.is_connected(_main_table._on_moved):
				tb.moved.disconnect(_main_table._on_moved)
			if tb.captured.is_connected(_main_table._on_captured):
				tb.captured.disconnect(_main_table._on_captured)
			if tb.reset.is_connected(_main_table._rebuild_stones):
				tb.reset.disconnect(_main_table._rebuild_stones)
		_main_table.board = null
		_main_table._rebuild_stones()
	if _giant != null:
		_giant._disconnect_board_signals()
		_giant.cancel_animations()
		_giant.board = null
		_giant._clear_all()


func _bind_main_board() -> void:
	## Grid geometry is applied via set_board_size / apply_board; this only wires signals.
	_unbind_board_views()
	if _main_table != null:
		_main_table.apply_board(_main_board)
	if _giant != null:
		_giant.board = _main_board
		_giant._connect_board_signals()
		_giant._clear_all()
	if _main_board != null:
		if not _main_board.moved.is_connected(_on_board_moved):
			_main_board.moved.connect(_on_board_moved)
		if not _main_board.passed.is_connected(_on_board_passed):
			_main_board.passed.connect(_on_board_passed)


func _on_player_vertex(vertex: String) -> void:
	if _main_session != null:
		_main_session.try_player_vertex(vertex)
		_refresh_board_input()


func _on_player_pass() -> void:
	if _main_session != null:
		_main_session.try_player_pass()
		_refresh_board_input()


func _on_player_resign() -> void:
	if _main_session == null:
		return
	if _main_session.is_ai_only():
		_main_session.stop_match()
	else:
		_main_session.try_player_resign()
	_refresh_board_input()


func _on_ai_thinking(on: bool) -> void:
	if _main_session == null:
		return
	var color := _main_session.board.next_color if _main_session.board != null else GoBoardState.BLACK
	## While thinking, next_color is the AI about to move; after the move it flips.
	## Prefer the ped of the colour that just started thinking — use busy side:
	if on:
		if not _main_session.color_is_human(color):
			_set_ped_thinking(color, true)
	else:
		if _black_ped != null:
			_black_ped.set_thinking(false)
		if _white_ped != null:
			_white_ped.set_thinking(false)
	_refresh_board_input()


func _set_ped_thinking(color: int, on: bool) -> void:
	var ped := _black_ped if color == GoBoardState.BLACK else _white_ped
	if ped != null:
		ped.set_thinking(on)


func _refresh_board_input() -> void:
	if _main_session == null:
		return
	var human_turn := _main_session.player_to_move()
	if _main_table != null:
		_main_table.set_input_enabled(human_turn)
	if _settings != null:
		_settings.call("set_match_actions_enabled", human_turn)


func _on_session_ended(_reason: String) -> void:
	_hide_end_panel()
	_end_match_ui()


func _on_match_over(result: GoMatchResult) -> void:
	_match_active = false
	_on_eval_cleared()
	## Finishing is the one thing that retires the save row. Walking away does not.
	var games := _world_games()
	if games != null:
		games.clear_go()
	if _main_table != null:
		_main_table.set_input_enabled(false)
	if _settings != null:
		_settings.call("set_match_actions_enabled", false)
	if _end_panel != null:
		_end_panel.global_position = _end_panel_world()
		_end_panel.rotation.y = layout.main_table_yaw
		_end_panel.show_result(result)
	else:
		_end_match_ui()


# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------

## The run's match registry, which lives on CityRoot. Null in the test fixtures that stage
## an arena on its own — those play the game without a save behind it.
func _world_games() -> WorldGames:
	var tree := get_tree()
	if tree == null:
		return null
	var city := tree.get_first_node_in_group(&"city_root") as CityRoot
	if city == null:
		return null
	return city.world_games()


## Copy the live board into the registry. Runs on every move, because the autosave fires on
## a timer and must never catch the table between a stone and the record of it.
func _sync_games_save() -> void:
	var games := _world_games()
	if games == null:
		return
	var row := {} if _main_session == null else _main_session.to_save_dict()
	if row.is_empty():
		games.clear_go()
		return
	games.set_go(row)


## Sit back down at the game the save was holding, instead of opening the setup panel. The
## arena is rebuilt whenever the district streams in, so this is also what carries a match
## across walking out of the plaza and back.
func _resume_saved_match() -> void:
	var games := _world_games()
	if games == null or not games.has_go():
		return
	var row := games.go_snapshot()
	var board_n := int(row.get("board_n", 0))
	if board_n != 9 and board_n != 19:
		push_error("GamingArena: the saved match is %d wide, which no table here is" % board_n)
		games.clear_go()
		return
	var session := GoSessionScript.new() as GoSession
	session.name = "MainGoSession"
	add_child(session)
	if not session.resume_match(row):
		session.queue_free()
		games.clear_go()
		return

	_match_active = true
	layout.board_n = board_n
	_hide_end_panel()
	_main_session = session
	_main_board = session.board
	if _settings != null:
		_settings.set("board_n", board_n)
		_settings.set("black_human", session.black_human)
		_settings.set("white_human", session.white_human)
		_settings.set("black_rank", session.black_rank)
		_settings.set("white_rank", session.white_rank)
		_settings.call("show_match")
	if _giant != null:
		_giant.set_board_size(board_n, _main_board)
	_bind_main_board()
	if _giant != null:
		## Binding only clears the field — the saved stones have to be painted back on.
		_giant.paint_snapshot(_main_board)
	_connect_session()
	_refresh_board_input()
	_seat_ai_peds_immediately()
	print(
		"GamingArena: resumed %dx%d after %d moves, %s to play"
		% [
			board_n,
			board_n,
			_main_board.move_list.size(),
			"black" if _main_board.next_color == GoBoardState.BLACK else "white",
		]
	)
	_main_session.kick_ai_if_needed()


func _on_board_moved(_color: int, _vertex: String, _loc: Vector2i) -> void:
	_sync_games_save()


func _on_board_passed(_color: int) -> void:
	_sync_games_save()


## Throws a dart of light from the mover's hand at the crossing and reports how long the
## table should hold the stone back, so the stone lands under the strike.
func _herald_move(color: int, world_target: Vector3) -> float:
	if _move_arrow == null:
		return 0.0
	var hand := _hand_world_for(color)
	## No hand in the world (an off-screen player, a ped still walking over) — no throw.
	if not hand.is_finite():
		return 0.0
	return _move_arrow.fly(hand, world_target, color == GoBoardState.BLACK)


func _hand_world_for(color: int) -> Vector3:
	if _main_session == null:
		return Vector3.INF
	if _main_session.color_is_human(color):
		return _player_hand_world()
	var ped := _black_ped if color == GoBoardState.BLACK else _white_ped
	if ped == null or not is_instance_valid(ped):
		return Vector3.INF
	return ped.hand_world_pos()


func _player_hand_world() -> Vector3:
	var tree := get_tree()
	if tree == null:
		return Vector3.INF
	var city := tree.get_first_node_in_group(&"city_root") as CityRoot
	if city == null:
		return Vector3.INF
	var walker := city.player_walker()
	if walker == null:
		return Vector3.INF
	return walker.hand_world_pos()


func _on_eval_updated(snapshot: GoEvalSnapshot) -> void:
	if _settings != null:
		_settings.call("set_eval", snapshot)
	if _main_table != null:
		_main_table.set_eval(snapshot)


func _on_eval_cleared() -> void:
	if _settings != null:
		_settings.call("clear_eval")
	if _main_table != null:
		_main_table.clear_eval()


func _on_end_panel_dismissed() -> void:
	_end_match_ui()


func _hide_end_panel() -> void:
	if _end_panel != null:
		_end_panel.hide_panel()


func _end_match_ui() -> void:
	_match_active = false
	_hide_end_panel()
	if _settings != null:
		_settings.call("show_setup")
	if _main_table != null:
		_main_table.set_input_enabled(false)


## Billboard centre: south of the giant board, facing the table / spawn.
func _end_panel_world() -> Vector3:
	var span := layout.giant_span_vox()
	var mid_x_vox := float(origin_vox.x + layout.giant_origin.x) + float(span) * 0.5
	## A few metres in front of the south edge of the grid.
	var front_z_vox := float(origin_vox.z + layout.giant_origin.z) - 8.0 / voxel_size
	var pad_y_m := float(origin_vox.y + layout.giant_origin.y) * voxel_size
	return Vector3(
		mid_x_vox * voxel_size,
		pad_y_m + GoEndPanel.PANEL_H_M * 0.5,
		front_z_vox * voxel_size
	)

## World point on the table timber at a fractional X along the table width.
func _slot_surface_world(x_frac: float) -> Vector3:
	var top_vox_y: int = layout.main_table_origin.y + GamingComposer.TABLE_H
	var ox := layout.main_table_origin
	var cx: int = ox.x + int(round(float(GamingComposer.TABLE_W) * x_frac))
	var cz: int = ox.z + GamingComposer.TABLE_D / 2
	return Vector3(
		(float(origin_vox.x + cx) + 0.5) * voxel_size,
		float(origin_vox.y + top_vox_y + 1) * voxel_size + 0.04,
		(float(origin_vox.z + cz) + 0.5) * voxel_size
	)


func _world_from_local_m(local: Vector3) -> Vector3:
	return Vector3(
		float(origin_vox.x) * voxel_size + local.x,
		float(origin_vox.y) * voxel_size + local.y,
		float(origin_vox.z) * voxel_size + local.z
	)
