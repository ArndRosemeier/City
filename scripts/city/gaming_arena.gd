## Runtime Gaming district: main Go table + giant board + invite peds + side ambient.
class_name GamingArena
extends Node3D

const GoTableUi3DScript := preload("res://scripts/city/go_table_ui.gd")
const GoGiantBoardScript := preload("res://scripts/city/go_giant_board.gd")
const GoSessionScript := preload("res://scripts/city/go_session.gd")
const GoPedActorScript := preload("res://scripts/city/go_ped_actor.gd")
const GoBoardStateScript := preload("res://scripts/city/go_board_state.gd")
const GoRankScript := preload("res://scripts/city/go_rank.gd")

var layout: GamingLayout = null
var origin_vox: Vector3i = Vector3i.ZERO
var voxel_size: float = 0.5
var live_brush: Callable = Callable()
var _dseed: int = 0

var _main_board: GoBoardState = null
var _main_session: GoSession = null
var _main_table: GoTableUi3D = null
var _giant: GoGiantBoard = null
var _opponent: GoPedActor = null
var _invite_peds: Dictionary = {}
var _side_sessions: Array[GoSession] = []


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
	_spawn_invites()
	_spawn_sides()


func _exit_tree() -> void:
	if _main_session != null:
		_main_session.end_session("unload")
		_main_session = null
	for s in _side_sessions:
		if s != null:
			s.end_session("unload")
	_side_sessions.clear()


func interact_at_world(_pos: Vector3) -> bool:
	## Used when a child StaticBody forwards via meta; prefer invite_tier meta on collider chain.
	return false


func invite_tier(tier: StringName) -> bool:
	## Ped presets snap the rank stepper, then start.
	if _main_table != null:
		_main_table.set_selected_rank(GoRankScript.preset_rank(tier))
	_start_match_with_tier(tier)
	return true


func _spawn_main_views() -> void:
	_main_board = GoBoardStateScript.new() as GoBoardState
	_main_board.setup(layout.board_n)

	_main_table = GoTableUi3DScript.new() as GoTableUi3D
	_main_table.name = "MainGoTable"
	add_child(_main_table)
	var yaw := layout.main_table_yaw + PI
	## Above the timber slab (not at the voxel floor — that buried the board under the top).
	_main_table.setup_board(
		_main_board, _table_surface_world(layout.main_table_origin), yaw, 2.6
	)
	_main_table.set_input_enabled(false)
	_main_table.vertex_chosen.connect(_on_player_vertex)
	_main_table.pass_pressed.connect(_on_player_pass)
	_main_table.resign_pressed.connect(_on_player_resign)
	_main_table.invite_pressed.connect(_on_invite)

	_giant = GoGiantBoardScript.new() as GoGiantBoard
	_giant.name = "GiantGoBoard"
	add_child(_giant)
	_giant.setup(
		_main_board,
		live_brush,
		origin_vox,
		layout.giant_origin,
		layout.giant_cell_vox,
		voxel_size
	)


func _spawn_invites() -> void:
	for stand in layout.invite_stands:
		var tier := StringName(str(stand.get("tier", "novice")))
		var local: Vector3 = stand.get("local", Vector3.ZERO)
		var ped: GoPedActor = GoPedActorScript.new() as GoPedActor
		ped.name = "Invite_%s" % String(tier)
		add_child(ped)
		ped.begin_as_invite(_world_from_local_m(local), tier, float(stand.get("yaw", 0.0)))
		_invite_peds[tier] = ped

		var body := StaticBody3D.new()
		body.name = "InviteHit"
		body.collision_layer = 1
		body.add_to_group("world_interact")
		body.set_meta("go_invite_tier", String(tier))
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.5
		capsule.height = 1.85
		shape.shape = capsule
		shape.position.y = 0.95
		body.add_child(shape)
		ped.add_child(body)
		## CityWalker calls interact_at_world on the collider node or parents — attach script method via bind.
		body.set_script(load("res://scripts/city/go_invite_hit.gd"))


func _spawn_sides() -> void:
	var i := 0
	for side in layout.side_tables:
		var session: GoSession = GoSessionScript.new() as GoSession
		session.name = "SideGoSession_%d" % i
		add_child(session)
		var tier: StringName = &"novice" if i == 0 else &"club"
		session.begin(GoSession.Mode.PED_VS_PED, tier, layout.board_n)
		_side_sessions.append(session)

		var table: GoTableUi3D = GoTableUi3DScript.new() as GoTableUi3D
		table.name = "SideGoTable_%d" % i
		add_child(table)
		var origin: Vector3i = side["origin"]
		table.setup_board(
			session.board,
			_table_surface_world(origin),
			float(side.get("yaw", 0.0)) + PI,
			1.8
		)
		table.set_input_enabled(false)

		var ped_a: GoPedActor = GoPedActorScript.new() as GoPedActor
		ped_a.name = "SidePedA_%d" % i
		add_child(ped_a)
		ped_a.begin_as_invite(_world_from_local_m(side["ped_a"]), tier, float(side.get("yaw", 0.0)))
		var ped_b: GoPedActor = GoPedActorScript.new() as GoPedActor
		ped_b.name = "SidePedB_%d" % i
		add_child(ped_b)
		ped_b.begin_as_invite(_world_from_local_m(side["ped_b"]), tier, float(side.get("yaw", 0.0)) + PI)
		session.ai_thinking.connect(
			func(on: bool) -> void:
				if session.board != null and session.board.next_color == GoBoardState.BLACK:
					ped_a.set_thinking(on)
				else:
					ped_b.set_thinking(on)
		)
		i += 1


func _on_invite(tier: StringName) -> void:
	_start_match_with_tier(tier)


func _start_match_with_tier(tier: StringName) -> void:
	if layout == null:
		return
	if _main_session != null:
		_main_session.end_session("reinvite")
		_main_session.queue_free()
		_main_session = null

	## Rank comes from the table stepper (invite buttons/peds snap presets first).
	var rank := (
		_main_table.selected_rank if _main_table != null else GoRankScript.preset_rank(tier)
	)

	_main_session = GoSessionScript.new() as GoSession
	_main_session.name = "MainGoSession"
	add_child(_main_session)
	_main_session.begin(GoSession.Mode.PLAYER_VS_PED, tier, layout.board_n, rank)
	_main_board = _main_session.board
	_bind_main_board()
	_main_table.set_input_enabled(true)
	_main_session.ai_thinking.connect(_on_ai_thinking)

	var ped: GoPedActor = _invite_peds.get(tier) as GoPedActor
	if ped != null:
		_opponent = ped
		var seat := _world_from_local_m(layout.main_ped_stand_local)
		var table := _table_surface_world(layout.main_table_origin)
		## Face the board (look toward table centre), not the arrival travel heading.
		var face := _yaw_toward(seat, table)
		ped.walk_path(_opponent_walk_waypoints(seat, table), face)
	print("GamingArena: invited %s at Human-SL rank %s" % [String(tier), _main_session.rank_label()])


## Route around the table pad (west flank) so the ped does not walk through the board.
func _opponent_walk_waypoints(seat: Vector3, table: Vector3) -> Array[Vector3]:
	var half_w := float(GamingComposer.TABLE_W) * voxel_size * 0.5
	var west_x := table.x - half_w - 2.8
	var south_z := table.z - 2.0
	if _opponent != null:
		south_z = minf(_opponent.global_position.z, table.z - 2.0)
	var path: Array[Vector3] = [
		Vector3(west_x, seat.y, south_z),
		Vector3(west_x, seat.y, seat.z),
		seat,
	]
	return path


func _yaw_toward(from: Vector3, to: Vector3) -> float:
	var look := to - from
	look.y = 0.0
	if look.length_squared() < 0.0001:
		return layout.main_table_yaw if layout != null else 0.0
	## Match GoPedActor / Quaternius forward (−Z).
	return atan2(-look.x, -look.z)


func _bind_main_board() -> void:
	_main_table.board = _main_board
	if not _main_board.moved.is_connected(_main_table._on_moved):
		_main_board.moved.connect(_main_table._on_moved)
		_main_board.captured.connect(_main_table._on_captured)
		_main_board.reset.connect(_main_table._rebuild_stones)
	_main_table._rebuild_stones()
	_giant.board = _main_board
	if not _main_board.moved.is_connected(_giant._on_moved):
		_main_board.moved.connect(_giant._on_moved)
		_main_board.captured.connect(_giant._on_captured)
		_main_board.reset.connect(_giant._clear_all)
	_giant._clear_all()


func _on_player_vertex(vertex: String) -> void:
	if _main_session != null:
		_main_session.try_player_vertex(vertex)


func _on_player_pass() -> void:
	if _main_session != null:
		_main_session.try_player_pass()


func _on_player_resign() -> void:
	if _main_session != null:
		_main_session.try_player_resign()


func _on_ai_thinking(on: bool) -> void:
	if _opponent != null:
		_opponent.set_thinking(on)
	if _main_table != null and _main_session != null:
		_main_table.set_input_enabled(not on and _main_session.player_to_move())


func _world_from_local_vox(local: Vector3i) -> Vector3:
	return Vector3(
		(float(origin_vox.x + local.x) + 0.5) * voxel_size,
		float(origin_vox.y + local.y) * voxel_size,
		(float(origin_vox.z + local.z) + 0.5) * voxel_size
	)


## World point on the top face of the platform timber cap.
func _table_surface_world(table_origin: Vector3i) -> Vector3:
	## Composer platform: timber at Y = ground_y+TABLE_H (table_origin.y is ground_y).
	var top_vox_y: int = table_origin.y + GamingComposer.TABLE_H
	var cx: int = table_origin.x + GamingComposer.TABLE_W / 2
	var cz: int = table_origin.z + GamingComposer.TABLE_D / 2
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
