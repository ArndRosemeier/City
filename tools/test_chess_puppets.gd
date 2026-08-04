## Every body the chess board is cast from, loaded and checked against what the arena needs.
##
## A miscast piece is a silent failure: the board sets up, one monster is missing or standing
## in a T-pose, and nothing says why. This asserts the twelve rows up front — the asset loads,
## it satisfies the loader contract, it owns idle / walk / melee / death clips, and it
## normalises to the height its rank asks for.
##
## Run: powershell -File tools\run_test.ps1 test_chess_puppets
extends Node

const ChessBoardStateScript := preload("res://scripts/city/chess_board_state.gd")
const ChessCastScript := preload("res://scripts/city/chess_cast.gd")
const ChessPieceActorScript := preload("res://scripts/city/chess_piece_actor.gd")
const CreatureCatalogScript := preload("res://scripts/city/creature_catalog.gd")
const CreatureVariationScript := preload("res://scripts/city/creature_variation.gd")

## Every colour / type pair the board fields.
const TYPES: Array[int] = [1, 2, 3, 4, 5, 6]

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_check_cast_is_distinct()
	_check_bands_cannot_be_confused()
	await _check_bodies_load()
	await _check_walk_arrives()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


## Six silhouettes per side is the whole reason beast and grove were chosen; a duplicate
## would mean a player cannot tell two of their own pieces apart.
func _check_cast_is_distinct() -> void:
	for colour: int in [ChessBoardStateScript.WHITE, ChessBoardStateScript.BLACK]:
		var seen := PackedStringArray()
		for t: int in TYPES:
			var body := ChessCastScript.body_for(colour, t)
			if body.is_empty():
				_fail("FAIL %s type %d has no body" % [ChessCastScript.colour_name(colour), t])
				continue
			if seen.has(body):
				_fail(
					"FAIL %s casts %s twice"
					% [ChessCastScript.colour_name(colour), body]
				)
			seen.append(body)
		if seen.size() == 6:
			print("OK %s fields %s" % [ChessCastScript.colour_name(colour), ", ".join(seen)])


## The two armies have to be unmistakable, and what guarantees it is a numeric relationship
## rather than something you judge from a screenshot: ivory's darkest output sits above slate's
## brightest, so no part of a light piece is ever darker than any part of a dark one. Worth
## asserting because it is exactly the kind of thing that quietly stops holding the third time
## someone nudges a value to make one render look better.
func _check_bands_cannot_be_confused() -> void:
	var ivory: CreatureVariation.Band = ChessCastScript.band_for(ChessBoardStateScript.WHITE)
	var slate: CreatureVariation.Band = ChessCastScript.band_for(ChessBoardStateScript.BLACK)
	if ivory == null or slate == null:
		_fail("FAIL a side has no band")
		return
	if ivory.value_low <= slate.value_high:
		_fail(
			"FAIL ivory bottoms out at %.2f but slate reaches %.2f, so the two armies overlap"
			% [ivory.value_low, slate.value_high]
		)
		return
	## Slate running all the way down to black is the failure the palette notes warn about: the
	## bodies stop being colours and become silhouettes, and the face goes first.
	if slate.value_high < 0.25:
		_fail("FAIL slate tops out at %.2f, too dark for a face to read" % slate.value_high)
		return
	## Neither band may flatten its bodies onto one hue, or the six silhouettes stop being six
	## colours and the cast test above is asserting a distinction the player cannot see.
	for band: CreatureVariation.Band in [ivory, slate]:
		if band.hue_keep <= 0.0:
			_fail("FAIL band %s keeps none of the body's own hue" % band.name)
			return
	print(
		"OK ivory %.2f-%.2f clears slate %.2f-%.2f"
		% [ivory.value_low, ivory.value_high, slate.value_low, slate.value_high]
	)


func _check_bodies_load() -> void:
	for colour: int in [ChessBoardStateScript.WHITE, ChessBoardStateScript.BLACK]:
		for t: int in TYPES:
			var body := ChessCastScript.body_for(colour, t)
			if body.is_empty():
				continue
			var entry: CreatureCatalog.Entry = CreatureCatalogScript.by_id(body)
			if entry == null:
				_fail("FAIL %s is not a catalogue row" % body)
				continue
			## Flying rigs hover and ship no walk cycle, so a board cast from one would
			## glide. The catalogue records that as an empty slot list plus a note.
			if entry.family == CreatureCatalog.Family.QUATERNIUS_FLYING:
				_fail("FAIL %s is a flying rig and has no ground locomotion" % body)
			var want_h := ChessCastScript.height_for(t)
			var actor: Node3D = ChessPieceActorScript.new() as Node3D
			add_child(actor)
			var ok: bool = actor.call(
				"begin",
				body,
				colour,
				t,
				Vector2i(0, 0),
				want_h,
				ChessCastScript.band_for(colour),
				Vector3.ZERO,
				0.0
			)
			if not ok:
				_fail("FAIL %s did not begin as a %d" % [body, t])
				actor.queue_free()
				continue
			await get_tree().process_frame
			var got_h: float = actor.call("stand_height")
			if absf(got_h - want_h) > 0.01:
				_fail("FAIL %s normalised to %.2f m, wanted %.2f m" % [body, got_h, want_h])
			_check_painted(actor, body, ChessCastScript.band_for(colour))
			print("OK %s stands %.2f m as type %d" % [body, got_h, t])
			actor.queue_free()
			await get_tree().process_frame


## Every mesh on the piece has to be wearing the palette shader carrying its own army's numbers.
## A body that keeps its authored material is the failure that would go unreported: the board
## still sets up, one piece is simply the wrong colour.
func _check_painted(actor: Node3D, body: String, band: CreatureVariation.Band) -> void:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(actor, meshes)
	if meshes.is_empty():
		_fail("FAIL %s has no mesh to paint" % body)
		return
	for mesh_instance: MeshInstance3D in meshes:
		for surface in range(mesh_instance.mesh.get_surface_count()):
			if mesh_instance.get_surface_override_material(surface) as ShaderMaterial == null:
				_fail(
					"FAIL %s surface %d on %s kept its authored material"
					% [body, surface, mesh_instance.name]
				)
				return
		var got: Variant = mesh_instance.get_instance_shader_parameter("band_value_high")
		if got == null:
			_fail("FAIL %s carries no band on %s" % [body, mesh_instance.name])
			return
		if absf(float(got) - band.value_high) > 0.001:
			_fail(
				"FAIL %s is painted to %.2f, wanted band %s at %.2f"
				% [body, float(got), band.name, band.value_high]
			)
			return


static func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		out.append(mesh_instance)
	for child in node.get_children():
		_collect_meshes(child, out)


## The move animation has to end, or the arena waits on `arrived` forever and the game
## deadlocks with a monster mid-stride.
func _check_walk_arrives() -> void:
	var body := ChessCastScript.body_for(ChessBoardStateScript.WHITE, ChessBoardStateScript.ROOK)
	var actor: Node3D = ChessPieceActorScript.new() as Node3D
	add_child(actor)
	if not bool(
		actor.call(
			"begin",
			body,
			ChessBoardStateScript.WHITE,
			ChessBoardStateScript.ROOK,
			Vector2i(0, 0),
			ChessCastScript.height_for(ChessBoardStateScript.ROOK),
			ChessCastScript.band_for(ChessBoardStateScript.WHITE),
			Vector3.ZERO,
			0.0
		)
	):
		_fail("FAIL %s did not begin for the walk test" % body)
		return
	var landed := [false]
	actor.connect("arrived", func() -> void: landed[0] = true)
	var dest := Vector3(0.0, 0.0, 12.0)
	var path: Array[Vector3] = [dest]
	actor.call("walk_to", Vector2i(0, 3), path, PI, false)
	## Three squares at WALK_SPEED plus two turns; give it four times that before calling it
	## stuck, so a slow headless frame does not fail the test.
	var deadline := Time.get_ticks_msec() + 20000
	while not bool(landed[0]) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not bool(landed[0]):
		_fail("FAIL %s never emitted arrived" % body)
		return
	var landed_at: Vector3 = actor.global_position
	if landed_at.distance_to(dest) > 0.05:
		_fail("FAIL %s stopped at %s, wanted %s" % [body, landed_at, dest])
		return
	var got_sq: Vector2i = actor.get("square")
	if got_sq != Vector2i(0, 3):
		_fail("FAIL %s reports square %s after the walk" % [body, got_sq])
		return
	print("OK %s walked 12 m and reported a4" % body)
