## Look at the roster: every creature body in a rank, one of each rig family from the front
## and from behind, and the variation layer's spread across seeds from a single base model.
##
## The facing pair is the point of the front/back shots. `test_creature_assets` measures
## facing from which way the melee clip lunges, which is an argument; a picture of a face is
## the thing being argued about.
##
## Run: Godot --path . res://tools/shot_monsters.tscn
extends Node

const OUT_DIR := "res://tools/monstershots"

## Bodies per row before a rank wraps, and the floor on the gap between them. Wide families
## widen it further off their own height, because a blob is as broad as it is tall.
const RANK_COLUMNS := 9
const RANK_PITCH_MIN := 2.2

## Seeds shown in the variation spread, on one base body.
const SPREAD_BASE := "kaykit/Skeleton_Minion"
const SPREAD_BLOB := "blob/Cactoro"
const SPREAD_BIG := "big/Orc"
const SPREAD_SEEDS := 9
const SPREAD_PITCH := 1.9

## The palette's own contact sheet: one body per band, close enough to read a face by. The
## spreads are too wide to judge a colour on and the facing pair is shot as vendored, so without
## this there is no picture of what the recolour actually does to a head.
##
## Seed n lands in band n because `CreatureVariation` steps through the palette by seed, so
## these run in the order the band table is written in.
const BAND_PITCH := 1.5

## One body per family, for the facing pair.
const FACING_SUBJECTS: Array[String] = [
	"kaykit/Skeleton_Warrior", "big/Orc", "blob/Cat", "blob/Birb"
]

var _stage: Node3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_build_stage()

	await _shoot_facing_pairs()
	await _shoot_rank("kaykit", CreatureCatalog.Family.KAYKIT_SKELETON)
	await _shoot_rank("big", CreatureCatalog.Family.QUATERNIUS_BIG)
	await _shoot_rank("blob", CreatureCatalog.Family.QUATERNIUS_BLOB)
	await _shoot_rank("flying", CreatureCatalog.Family.QUATERNIUS_FLYING)
	await _shoot_spread(SPREAD_BASE)
	await _shoot_spread(SPREAD_BIG)
	await _shoot_spread(SPREAD_BLOB)
	await _shoot_bands(SPREAD_BASE)
	await _shoot_bands(SPREAD_BIG)

	print("RESULT: OK")
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# Subjects
# ---------------------------------------------------------------------------

## One body on the stage, dressed and posed the way `undead_unit.gd` would dress and pose it,
## so what is photographed is what the city spawns rather than the raw asset.
func _place(entry: CreatureCatalog.Entry, at: Vector3, unit_seed: int, vary: bool) -> Node3D:
	var packed: PackedScene = load(entry.path) as PackedScene
	if packed == null:
		push_error("FAIL %s did not load from %s" % [entry.id, entry.path])
		return null
	var root: Node3D = packed.instantiate() as Node3D
	if root == null:
		push_error("FAIL %s has no Node3D root" % entry.id)
		return null
	var pivot := Node3D.new()
	pivot.name = entry.id.replace("/", "_")
	_stage.add_child(pivot)
	pivot.position = at
	pivot.add_child(root)
	root.rotation = Vector3(0.0, entry.model_yaw, 0.0)

	var player := _find_player(root)
	if player == null:
		push_error("FAIL %s has no AnimationPlayer" % entry.id)
		return pivot
	var clips := player.get_animation_list()
	## Bodies outside the spawn tables are photographed as vendored. Rolling a variation for
	## one would ask the resolver for actions it has already reported that body cannot do —
	## flying/Demon ships a single clip — and fill the shot with its own error overlay.
	var clip := ""
	if vary and entry.is_spawnable():
		var variation := CreatureVariation.roll(entry, clips, unit_seed)
		variation.apply(root, entry)
		root.scale = Vector3(variation.width, variation.height, variation.width)
		clip = variation.clip_for(CreatureClips.Action.IDLE)
	else:
		clip = CreatureClips.try_resolve(clips, CreatureClips.Action.IDLE)
	root.position = entry.model_offset * root.scale
	if not clip.is_empty():
		var animation := player.get_animation(clip)
		animation.loop_mode = Animation.LOOP_LINEAR
		player.play(clip)
	return pivot


# ---------------------------------------------------------------------------
# Shots
# ---------------------------------------------------------------------------

## Front and back of one body per family. A body that faces +Z shows its face to a camera
## standing at +Z, and the back of its head to one standing at -Z.
func _shoot_facing_pairs() -> void:
	for id: String in FACING_SUBJECTS:
		var entry := CreatureCatalog.by_id(id)
		if entry == null:
			continue
		var pivot := _place(entry, Vector3.ZERO, 1, false)
		await _settle(0.4)
		var eye := entry.measured_height * 0.62
		var back := entry.measured_height * 1.5
		var slug := id.replace("/", "_")
		await _shoot(
			Vector3(0.0, eye, back), Vector3(0.0, eye, 0.0), "%s/facing_%s_from_plus_z.png" % [OUT_DIR, slug]
		)
		await _shoot(
			Vector3(0.0, eye, -back), Vector3(0.0, eye, 0.0), "%s/facing_%s_from_minus_z.png" % [OUT_DIR, slug]
		)
		pivot.queue_free()
		await _settle(0.2)


## Every body of one family, in rows, seen from the front. Shot twice: as vendored, and with
## the variation layer on, because the pair is the only honest way to say what the layer adds.
func _shoot_rank(slug: String, family: CreatureCatalog.Family) -> void:
	var members: Array[CreatureCatalog.Entry] = []
	var tallest := 0.0
	for entry: CreatureCatalog.Entry in CreatureCatalog.all():
		if entry.family == family:
			members.append(entry)
			tallest = maxf(tallest, entry.measured_height)
	if members.is_empty():
		return
	await _shoot_rank_pass(slug, members, tallest, false)
	await _shoot_rank_pass(slug, members, tallest, true)


func _shoot_rank_pass(
	slug: String, members: Array[CreatureCatalog.Entry], tallest: float, vary: bool
) -> void:
	var pitch := maxf(RANK_PITCH_MIN, tallest * 0.95)
	var row_gap := pitch * 1.8
	var rows := int(ceil(float(members.size()) / float(RANK_COLUMNS)))
	var columns := mini(members.size(), RANK_COLUMNS)
	var pivots: Array[Node3D] = []
	for i in range(members.size()):
		var row := i / RANK_COLUMNS
		var column := i % RANK_COLUMNS
		var wide := mini(members.size() - row * RANK_COLUMNS, RANK_COLUMNS)
		## Back rows step half a pitch sideways so nobody stands directly behind anybody.
		var x := (float(column) - float(wide - 1) * 0.5) * pitch + float(row % 2) * pitch * 0.5
		var z := -float(row) * row_gap
		var pivot := _place(members[i], Vector3(x, 0.0, z), 1000 + i, vary)
		if pivot != null:
			pivots.append(pivot)
	await _settle(0.7)
	## Fit the widest row across the frame, then look down over the depth behind it. At the
	## stage's 45 degree vertical fov a 16:9 frame holds half its width per 0.68 of the
	## distance, and the back row's half-pitch stagger adds to the span that has to fit.
	var width := pitch * (float(columns) + 0.3)
	var depth := float(rows - 1) * row_gap
	await _shoot(
		Vector3(0.0, tallest * 1.15 + depth * 0.30, width * 0.68 + depth * 0.30),
		Vector3(0.0, tallest * 0.55, -depth * 0.5),
		"%s/rank_%s%s.png" % [OUT_DIR, slug, "" if vary else "_stock"]
	)
	for pivot: Node3D in pivots:
		pivot.queue_free()
	await _settle(0.3)


## One body, nine seeds. Palette, build and borrowed limbs all come off the seed, so this is
## the whole variation layer in one frame.
func _shoot_spread(id: String) -> void:
	var entry := CreatureCatalog.by_id(id)
	if entry == null:
		return
	var pivots: Array[Node3D] = []
	var pitch := SPREAD_PITCH * maxf(1.0, entry.measured_height / CreatureCatalog.REFERENCE_HEIGHT)
	for i in range(SPREAD_SEEDS):
		var x := (float(i) - float(SPREAD_SEEDS - 1) * 0.5) * pitch
		var pivot := _place(entry, Vector3(x, 0.0, 0.0), i + 1, true)
		if pivot != null:
			pivots.append(pivot)
	await _settle(0.7)
	var width := float(SPREAD_SEEDS) * pitch
	await _shoot(
		Vector3(0.0, entry.measured_height * 0.75, width * 0.72),
		Vector3(0.0, entry.measured_height * 0.45, 0.0),
		"%s/spread_%s.png" % [OUT_DIR, id.replace("/", "_")]
	)
	for pivot: Node3D in pivots:
		pivot.queue_free()
	await _settle(0.3)


## One body per palette band, framed on the head and shoulders. Every band is named in the file
## by position rather than in the image, which the report has to say out loud.
func _shoot_bands(id: String) -> void:
	var entry := CreatureCatalog.by_id(id)
	if entry == null:
		return
	var bands := CreatureVariation.bands()
	var pivots: Array[Node3D] = []
	var pitch := BAND_PITCH * maxf(1.0, entry.measured_height / CreatureCatalog.REFERENCE_HEIGHT)
	for i in range(bands.size()):
		var x := (float(i) - float(bands.size() - 1) * 0.5) * pitch
		var pivot := _place(entry, Vector3(x, 0.0, 0.0), i, true)
		if pivot != null:
			pivots.append(pivot)
	await _settle(0.7)
	## Tighter than the spread on purpose: the eye glow and the bone tone are the whole point and
	## neither survives being 90 pixels tall.
	var width := float(bands.size()) * pitch
	var eye := entry.measured_height * 0.74
	await _shoot(
		Vector3(0.0, eye, width * 0.78),
		Vector3(0.0, entry.measured_height * 0.55, 0.0),
		"%s/band_%s.png" % [OUT_DIR, id.replace("/", "_")]
	)
	for pivot: Node3D in pivots:
		pivot.queue_free()
	await _settle(0.3)


# ---------------------------------------------------------------------------
# Stage
# ---------------------------------------------------------------------------

func _build_stage() -> void:
	_stage = Node3D.new()
	_stage.name = "Stage"
	add_child(_stage)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.55, 0.72)
	sky_mat.sky_horizon_color = Color(0.72, 0.76, 0.80)
	sky_mat.ground_bottom_color = Color(0.24, 0.24, 0.26)
	sky_mat.ground_horizon_color = Color(0.45, 0.45, 0.47)
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42.0, 155.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)

	var pad := MeshInstance3D.new()
	pad.name = "Pad"
	var plane := PlaneMesh.new()
	plane.size = Vector2(160.0, 160.0)
	pad.mesh = plane
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.30, 0.31, 0.33)
	pad_mat.roughness = 0.95
	pad.material_override = pad_mat
	add_child(pad)


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null


func _settle(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _shoot(eye: Vector3, target: Vector3, path: String) -> void:
	var cam := Camera3D.new()
	cam.position = eye
	cam.fov = 45.0
	cam.far = 900.0
	add_child(cam)
	cam.look_at(target, Vector3.UP)
	cam.make_current()
	await _settle(0.35)
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("FAIL no viewport image for %s" % path)
	else:
		img.save_png(path)
	cam.queue_free()
