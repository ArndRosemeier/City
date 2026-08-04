## The monster-chess court at runtime: thirty-two puppets, one board, one collider.
##
## Selection goes through a **single** `StaticBody3D` covering the playing squares rather
## than sixty-four square colliders or a hit shape per monster. `CityWalker._try_world_interact`
## already routes an aimed shot to the nearest node in the `world_interact` group that owns
## `interact_at_world`, which is how `gem_chest.gd` is clicked, and converting the hit point
## to a square makes "tap a monster" and "tap a square" the same operation:
##
##   * the square holds one of your pieces → select it and light its legal destinations
##   * the square is a legal destination → play the move
##   * anything else → drop the selection
##
## Captures are staged, not fought. The attacker walks up, swings its MELEE clip, the
## defender plays DEATH and is freed. Routing it through `MonsterCombat` instead would let
## real damage rolls decide a chess capture, which could produce the wrong winner, and would
## drag in pursuit promotion and gem loot for a piece that is scenery with a rig.
class_name ChessArena
extends Node3D

const ChessBoardStateScript := preload("res://scripts/city/chess_board_state.gd")
const ChessCastScript := preload("res://scripts/city/chess_cast.gd")
const ChessPieceActorScript := preload("res://scripts/city/chess_piece_actor.gd")
const ChessSessionScript := preload("res://scripts/city/chess_session.gd")
const ChessSettingsUiScript := preload("res://scripts/city/chess_settings_ui.gd")

## How far above the painted squares the click slab and the highlights sit. Thin on purpose:
## the slab is on collision layer 1 so the aim ray can find it, which means the player walks
## on it too, and a step this small is not felt.
const CLICK_LIFT := 0.06
const HIGHLIGHT_LIFT := 0.07

## Highlight tints. Amber for what is picked up, green for where it may go, red for what it
## may take — the three questions a player is asking, answered without a legend.
const SEL_COLOUR := Color(1.0, 0.72, 0.15, 0.55)
const DEST_COLOUR := Color(0.3, 0.85, 0.4, 0.4)
const CAPTURE_COLOUR := Color(0.95, 0.25, 0.2, 0.5)
## Fraction of a square the markers cover, so the board pattern still reads under them.
const MARKER_FRAC := 0.82

## Panel stands this many voxels west of the board's rim, at this height.
const PANEL_WEST_VOX := 10
const PANEL_EYE_M := 1.9

var layout: GamingLayout = null
var origin_vox: Vector3i = Vector3i.ZERO
var voxel_size: float = 0.5

var _board: ChessBoardState = null
var _session: ChessSession = null
## Typed as Node, like GamingArena's settings plate: a Ui3D subclass needs its own base
## resolved first, which is not guaranteed while the global class cache is being built.
var _panel: Node = null
## Square index → the puppet standing on it.
var _actors: Dictionary[int, ChessPieceActor] = {}
var _selected: int = -1
var _dest: PackedInt32Array = PackedInt32Array()
var _marker_root: Node3D = null
var _markers: Array[MeshInstance3D] = []
## True from the moment a move is committed until its puppet has finished walking. No tap is
## accepted meanwhile, and the AI is not asked for its reply until it clears.
var _animating: bool = false
## Bumped when the court is torn down or restarted, so a choreography waiting on a clip
## knows the game it belongs to is gone.
var _epoch: int = 0


func setup(
	p_layout: GamingLayout, p_origin_vox: Vector3i, p_voxel_size: float, _p_dseed: int
) -> void:
	layout = p_layout
	origin_vox = p_origin_vox
	voxel_size = p_voxel_size
	if layout == null:
		push_error("ChessArena.setup: no layout")
		return
	if layout.chess_square_vox <= 0:
		push_error("ChessArena.setup: square pitch %d is unusable" % layout.chess_square_vox)
		return
	add_to_group("world_interact")
	_build_click_slab()
	_build_marker_pool()
	_build_panel()
	if not _resume_saved_game():
		## No saved game: stand the armies up anyway. An empty court would read as scenery
		## nobody finished rather than as a board waiting for a player.
		_adopt_board(_fresh_board())
		_rebuild_pieces()


func _exit_tree() -> void:
	_epoch += 1
	## The saved row outlives the court on purpose: walking out of the district must not
	## forfeit a game. Only finishing one clears it.
	if _session != null and is_instance_valid(_session):
		_session.end_session("unload")


# ---------------------------------------------------------------------------
# Board geometry
# ---------------------------------------------------------------------------

## Edge length of one square in metres.
func square_m() -> float:
	return float(layout.chess_square_vox) * voxel_size


## World Y the pieces stand on: the top face of the course the squares are painted into.
func surface_y() -> float:
	return float(origin_vox.y + layout.chess_origin.y + 1) * voxel_size


## Centre of a square in world space, on the standing surface.
func square_world(file: int, rank: int) -> Vector3:
	var local := layout.chess_square_center(file, rank)
	return Vector3(
		(float(origin_vox.x) + local.x) * voxel_size,
		surface_y(),
		(float(origin_vox.z) + local.y) * voxel_size
	)


## Square index under a world point, or -1 when the point is off the eight-by-eight. Edge
## hits fall outside by a hair, which is a miss rather than a bug.
func square_at_world(pos: Vector3) -> int:
	var pitch := float(layout.chess_square_vox)
	var vx := pos.x / voxel_size - float(origin_vox.x) - float(layout.chess_origin.x)
	var vz := pos.z / voxel_size - float(origin_vox.z) - float(layout.chess_origin.z)
	var file := int(floor(vx / pitch))
	var rank := int(floor(vz / pitch))
	if file < 0 or file > 7 or rank < 0 or rank > 7:
		return -1
	return rank * 8 + file


## Which way a piece of this colour faces when it is not walking: across the board at the
## other army. White's home rank is the south one, so white looks north (+Z).
static func home_yaw(colour: int) -> float:
	return 0.0 if colour == ChessBoardStateScript.WHITE else PI


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

## An aimed shot landed on the board. Always returns true while a game is on this court, so
## the shot is swallowed rather than turned into a bolt that carves the squares up.
func interact_at_world(world_pos: Vector3) -> bool:
	if _board == null:
		return false
	if _animating:
		return true
	if _session == null or not _session.player_to_move():
		return true
	var sq := square_at_world(world_pos)
	if sq < 0:
		_clear_selection()
		return true
	var piece := int(_board.squares[sq])
	var mine := (
		piece != ChessBoardStateScript.EMPTY
		and ChessBoardStateScript.piece_colour(piece) == _board.side_to_move
	)
	if mine:
		_select(sq)
		return true
	if _selected >= 0 and _dest.has(sq):
		var from := ChessBoardStateScript.vec_of(_selected)
		var to := ChessBoardStateScript.vec_of(sq)
		_clear_selection()
		## Promotion is always a queen here. The rules layer offers all four, but a board
		## where a monster is the piece has nothing to say about underpromotion.
		_session.try_player_move(from, to, ChessBoardStateScript.QUEEN)
		return true
	_clear_selection()
	return true


func selected_square() -> int:
	return _selected


func legal_destinations() -> PackedInt32Array:
	return _dest


func is_animating() -> bool:
	return _animating


func board() -> ChessBoardState:
	return _board


func session() -> ChessSession:
	return _session


## The puppet standing on a square, or null. Test seam as much as anything.
func actor_at(sq: int) -> ChessPieceActor:
	return _actors.get(sq, null)


func _select(sq: int) -> void:
	_selected = sq
	var from := ChessBoardStateScript.vec_of(sq)
	_dest = PackedInt32Array()
	for dest: Vector2i in _board.legal_destinations_from(from.x, from.y):
		_dest.append(ChessBoardStateScript.square_of(dest.x, dest.y))
	_paint_markers()


func _clear_selection() -> void:
	_selected = -1
	_dest = PackedInt32Array()
	_paint_markers()


# ---------------------------------------------------------------------------
# Games
# ---------------------------------------------------------------------------

func _fresh_board() -> ChessBoardState:
	var fresh: ChessBoardState = ChessBoardStateScript.new() as ChessBoardState
	fresh.setup()
	return fresh


func _adopt_board(next: ChessBoardState) -> void:
	if _board != null and _board.moved.is_connected(_on_board_moved):
		_board.moved.disconnect(_on_board_moved)
	_board = next
	if _board != null and not _board.moved.is_connected(_on_board_moved):
		_board.moved.connect(_on_board_moved)


## Start a hotseat game: both armies are played by whoever is standing on the court. The
## plate offers the same thing; this is the seam a test (or a debug key) uses.
func begin_hotseat() -> void:
	_on_start_pressed(true, &"club", true, &"club")


## Start a game against the search. `human_plays_white` decides which army is the player's.
func begin_versus_ai(human_plays_white: bool, level: StringName) -> void:
	_on_start_pressed(human_plays_white, level, not human_plays_white, level)


func _on_start_pressed(
	white_human: bool, white_level: StringName, black_human: bool, black_level: StringName
) -> void:
	_epoch += 1
	_clear_selection()
	_teardown_session("restart")
	var session: ChessSession = ChessSessionScript.new() as ChessSession
	session.name = "ChessSession"
	add_child(session)
	if not session.begin_match(white_human, white_level, black_human, black_level):
		session.queue_free()
		return
	_session = session
	_adopt_board(session.board)
	_rebuild_pieces()
	_connect_session()
	_sync_saved_game()
	if _panel != null:
		## Keep the plate honest when the game was started from somewhere other than the
		## plate — a debug key, a test, or a later hook.
		_panel.set("white_human", white_human)
		_panel.set("black_human", black_human)
		_panel.set("white_level", white_level)
		_panel.set("black_level", black_level)
		_panel.call("show_match")
	_refresh_panel()
	print(
		"ChessArena: start beast=%s grove=%s"
		% [
			"human" if white_human else "AI " + String(white_level),
			"human" if black_human else "AI " + String(black_level),
		]
	)
	_session.kick_ai_if_needed()


func _on_resign_pressed() -> void:
	if _session == null:
		return
	if _session.is_ai_only():
		_session.stop_match()
	else:
		_session.try_player_resign()


func _connect_session() -> void:
	_session.ai_thinking.connect(_on_ai_thinking)
	_session.match_over.connect(_on_match_over)
	_session.search_reported.connect(_on_search_reported)


func _teardown_session(reason: String) -> void:
	if _session == null or not is_instance_valid(_session):
		_session = null
		return
	if _session.ai_thinking.is_connected(_on_ai_thinking):
		_session.ai_thinking.disconnect(_on_ai_thinking)
	if _session.match_over.is_connected(_on_match_over):
		_session.match_over.disconnect(_on_match_over)
	if _session.search_reported.is_connected(_on_search_reported):
		_session.search_reported.disconnect(_on_search_reported)
	_session.end_session(reason)
	_session.queue_free()
	_session = null


func _on_ai_thinking(_on: bool) -> void:
	_refresh_panel()


func _on_search_reported(depth: int, score: int, nodes: int, ms: int) -> void:
	if _panel != null:
		_panel.call("set_search", depth, score, nodes, ms)


func _on_match_over(reason: String) -> void:
	_clear_selection()
	## Finishing is the one thing that retires the save row. Walking away does not.
	var games := _world_games()
	if games != null:
		games.clear_chess()
	if _panel != null:
		_panel.call("set_result", reason)
	print("ChessArena: %s" % ChessSettingsUiScript.describe_result(reason))
	_teardown_session("over")


func _refresh_panel() -> void:
	if _panel == null:
		return
	if _session == null or _board == null:
		return
	_panel.call("set_turn", _board.side_to_move, _session.is_thinking())


# ---------------------------------------------------------------------------
# Puppets
# ---------------------------------------------------------------------------

func _rebuild_pieces() -> void:
	for sq: int in _actors.keys():
		var actor: ChessPieceActor = _actors[sq]
		if actor != null and is_instance_valid(actor):
			actor.queue_free()
	_actors.clear()
	if _board == null:
		return
	for sq in range(64):
		var piece := int(_board.squares[sq])
		if piece == ChessBoardStateScript.EMPTY:
			continue
		_spawn_actor(sq, piece)


func _spawn_actor(sq: int, piece: int) -> ChessPieceActor:
	var colour := ChessBoardStateScript.piece_colour(piece)
	var type := ChessBoardStateScript.piece_type(piece)
	var body := ChessCastScript.body_for(colour, type)
	if body.is_empty():
		return null
	var actor: ChessPieceActor = ChessPieceActorScript.new() as ChessPieceActor
	actor.name = "Piece_%s_%s" % [
		ChessBoardStateScript.piece_to_char(piece), ChessBoardStateScript.square_name(sq)
	]
	add_child(actor)
	var at := ChessBoardStateScript.vec_of(sq)
	if not actor.begin(
		body,
		colour,
		type,
		at,
		ChessCastScript.height_for(type),
		ChessCastScript.band_for(colour),
		square_world(at.x, at.y),
		home_yaw(colour)
	):
		actor.queue_free()
		return null
	_actors[sq] = actor
	return actor


func _on_board_moved(
	_colour: int,
	from_sq: Vector2i,
	to_sq: Vector2i,
	promotion: int,
	capture_at: Vector2i,
	_captured_piece: int,
	rook_from: Vector2i,
	rook_to: Vector2i
) -> void:
	_animating = true
	_clear_selection()
	## Think during the walk, play after it. The position is already final — the rules
	## committed the move before this signal — so the search has everything it needs, and
	## the seconds a monster spends crossing the board are seconds the opponent is not
	## making the player wait for.
	if _session != null:
		_session.set_hold(true)
		_session.kick_ai_if_needed()
	_refresh_panel()
	_choreograph(from_sq, to_sq, promotion, capture_at, rook_from, rook_to)


## Walk the move. A coroutine: signal handlers return at the first `await`, so the board
## finishes committing the move while the monsters are still getting there.
func _choreograph(
	from_sq: Vector2i,
	to_sq: Vector2i,
	promotion: int,
	capture_at: Vector2i,
	rook_from: Vector2i,
	rook_to: Vector2i
) -> void:
	var epoch := _epoch
	var from_i := ChessBoardStateScript.square_of(from_sq.x, from_sq.y)
	var to_i := ChessBoardStateScript.square_of(to_sq.x, to_sq.y)
	var mover: ChessPieceActor = _actors.get(from_i, null)
	if mover == null:
		push_error(
			"ChessArena: nothing is standing on %s to play that move"
			% ChessBoardStateScript.square_name(from_i)
		)
		_after_move()
		return
	_actors.erase(from_i)

	var victim: ChessPieceActor = null
	if capture_at.x >= 0:
		var cap_i := ChessBoardStateScript.square_of(capture_at.x, capture_at.y)
		victim = _actors.get(cap_i, null)
		if victim == null:
			push_error(
				"ChessArena: %s was captured but nothing was standing there"
				% ChessBoardStateScript.square_name(cap_i)
			)
		_actors.erase(cap_i)

	var target := square_world(to_sq.x, to_sq.y)
	var home := home_yaw(mover.colour)
	## Only the knight leaves its rank and file, and only the knight may pass over an
	## occupied square — so it is the only piece that needs to be in the air.
	var hop := mover.piece_type == ChessBoardStateScript.KNIGHT

	if victim != null:
		var walk_in: Array[Vector3] = [
			_staging_point(mover.global_position, victim.global_position)
		]
		mover.walk_to(to_sq, walk_in, 0.0, hop)
		await mover.arrived
		if epoch != _epoch or not is_inside_tree():
			return
		mover.face_towards(victim.global_position)
		mover.play_melee()
		await mover.struck
		if epoch != _epoch or not is_inside_tree():
			return
		victim.play_death()
		await victim.death_done
		if epoch != _epoch or not is_inside_tree():
			return
		victim.queue_free()
		var step_on: Array[Vector3] = [target]
		mover.walk_to(to_sq, step_on, home)
		await mover.arrived
	else:
		var straight: Array[Vector3] = [target]
		mover.walk_to(to_sq, straight, home, hop)
		await mover.arrived
	if epoch != _epoch or not is_inside_tree():
		return

	## The rook follows the king rather than crossing it: kingside castling has the two of
	## them swapping through the same two squares, and sending both at once walks a rook
	## through a king.
	if rook_from.x >= 0:
		var rf := ChessBoardStateScript.square_of(rook_from.x, rook_from.y)
		var rt := ChessBoardStateScript.square_of(rook_to.x, rook_to.y)
		var rook: ChessPieceActor = _actors.get(rf, null)
		if rook == null:
			push_error(
				"ChessArena: castling with no rook on %s"
				% ChessBoardStateScript.square_name(rf)
			)
		else:
			_actors.erase(rf)
			var rook_path: Array[Vector3] = [square_world(rook_to.x, rook_to.y)]
			rook.walk_to(
				ChessBoardStateScript.vec_of(rt), rook_path, home_yaw(rook.colour)
			)
			await rook.arrived
			if epoch != _epoch or not is_inside_tree():
				return
			_actors[rt] = rook

	if promotion != 0:
		## The pawn that walked here is gone; what stands on the square is a new body. This
		## is the one point where the puppet is not the piece that started the move.
		var colour := mover.colour
		mover.queue_free()
		_spawn_actor(to_i, promotion | colour)
	else:
		_actors[to_i] = mover
	_after_move()


## Where the attacker stops to swing: just short of the defender, on the line between them.
func _staging_point(attacker: Vector3, defender: Vector3) -> Vector3:
	var flat := Vector3(defender.x - attacker.x, 0.0, defender.z - attacker.z)
	if flat.length() < 0.01:
		return attacker
	return defender - flat.normalized() * (square_m() * 0.55)


func _after_move() -> void:
	_animating = false
	_sync_saved_game()
	_refresh_panel()
	if _session == null or _board == null or _board.phase != &"playing":
		return
	## Lifting the hold plays the move the AI found during the walk, or starts the search if
	## it has not run yet.
	_session.set_hold(false)


# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------

## The run's match registry on CityRoot. Null in the test fixtures that stage a court on its
## own — those play without a save behind them.
func _world_games() -> WorldGames:
	var tree := get_tree()
	if tree == null:
		return null
	var city := tree.get_first_node_in_group(&"city_root") as CityRoot
	if city == null:
		return null
	return city.world_games()


## Copy the live game into the registry after every move, because the autosave fires on a
## timer and must never catch the board between a move and the record of it.
func _sync_saved_game() -> void:
	var games := _world_games()
	if games == null:
		return
	var row: Dictionary = {} if _session == null else _session.to_save_dict()
	if row.is_empty():
		games.clear_chess()
		return
	games.set_chess(row)


## Sit back down at the game the save was holding. The court is rebuilt whenever the district
## streams in, so this is also what carries a game across walking away and back.
func _resume_saved_game() -> bool:
	var games := _world_games()
	if games == null or not games.has_chess():
		return false
	var row := games.chess_snapshot()
	var session: ChessSession = ChessSessionScript.new() as ChessSession
	session.name = "ChessSession"
	add_child(session)
	if not session.resume_match(row):
		session.queue_free()
		games.clear_chess()
		return false
	_session = session
	_adopt_board(session.board)
	_rebuild_pieces()
	_connect_session()
	if _panel != null:
		_panel.set("white_human", session.white_human)
		_panel.set("black_human", session.black_human)
		_panel.set("white_level", session.white_level)
		_panel.set("black_level", session.black_level)
		_panel.call("show_match")
	_refresh_panel()
	print(
		"ChessArena: resumed after %d moves, %s to play"
		% [
			_board.move_list.size(),
			ChessCastScript.colour_name(_board.side_to_move),
		]
	)
	_session.kick_ai_if_needed()
	return true


# ---------------------------------------------------------------------------
# Furniture
# ---------------------------------------------------------------------------

## One box over the playing squares, on layer 1 so the aim ray finds it. Thin enough that
## standing on it is not standing on anything.
func _build_click_slab() -> void:
	var span := float(layout.chess_span_vox()) * voxel_size
	var body := StaticBody3D.new()
	body.name = "BoardClickBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(span, CLICK_LIFT, span)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	var sw := square_world(0, 0)
	body.global_position = Vector3(
		sw.x - square_m() * 0.5 + span * 0.5,
		surface_y() + CLICK_LIFT * 0.5,
		sw.z - square_m() * 0.5 + span * 0.5
	)


## Sixty-four flat quads, hidden until a selection needs them. Pooled rather than spawned per
## selection: a board this size repaints its highlights on every tap.
func _build_marker_pool() -> void:
	_marker_root = Node3D.new()
	_marker_root.name = "Highlights"
	add_child(_marker_root)
	var side := square_m() * MARKER_FRAC
	for i in range(64):
		var mi := MeshInstance3D.new()
		mi.name = "Marker_%d" % i
		var quad := QuadMesh.new()
		quad.size = Vector2(side, side)
		mi.mesh = quad
		## QuadMesh faces +Z; a quarter turn about X lays it face-up.
		mi.rotation.x = -PI * 0.5
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = DEST_COLOUR
		mi.material_override = mat
		mi.visible = false
		_marker_root.add_child(mi)
		_markers.append(mi)


func _paint_markers() -> void:
	if _markers.size() != 64:
		return
	var used := 0
	if _selected >= 0:
		_place_marker(used, _selected, SEL_COLOUR)
		used += 1
		for i in range(_dest.size()):
			var sq := _dest[i]
			var occupied := int(_board.squares[sq]) != ChessBoardStateScript.EMPTY
			## An empty square that a pawn may take diagonally is en passant, and it wants
			## the same warning colour as any other capture.
			var takes := occupied or sq == _board.ep_square
			_place_marker(used, sq, CAPTURE_COLOUR if takes else DEST_COLOUR)
			used += 1
	for i in range(used, _markers.size()):
		_markers[i].visible = false


func _place_marker(slot: int, sq: int, tint: Color) -> void:
	var mi := _markers[slot]
	var at := ChessBoardStateScript.vec_of(sq)
	var world := square_world(at.x, at.y)
	mi.global_position = Vector3(world.x, surface_y() + HIGHLIGHT_LIFT, world.z)
	var mat := mi.material_override as StandardMaterial3D
	mat.albedo_color = tint
	mi.visible = true


## The control plate, west of the board and facing the way a player arrives from the garden.
func _build_panel() -> void:
	var panel: Node = ChessSettingsUiScript.new()
	panel.name = "ChessSettings"
	add_child(panel)
	var sw := square_world(0, 0)
	var span := float(layout.chess_span_vox()) * voxel_size
	var at := Vector3(
		sw.x - square_m() * 0.5 - float(PANEL_WEST_VOX) * voxel_size,
		surface_y() + PANEL_EYE_M,
		sw.z - square_m() * 0.5 + span * 0.5
	)
	## Ui3D faces its own −Z, so this yaw turns the plate to look west, back down the walk
	## in from the Go pad.
	panel.call("setup", at, PI * 0.5)
	panel.connect("start_pressed", _on_start_pressed)
	panel.connect("resign_pressed", _on_resign_pressed)
	_panel = panel
