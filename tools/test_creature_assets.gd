## Conformance for every creature body the repo ships, against the loader contract.
##
## This exists because of a bug that passed every test the project had: `_play_anim` matched
## clips by case-insensitive substring over an alphabetically sorted list, so `Idle` resolved
## to `2H_Melee_Idle` and every skeleton in the city idled holding an invisible greatsword,
## silently, for as long as the code shipped. The rule this test enforces is therefore not
## "an animation plays" but "this exact clip name is what this action resolves to".
##
## It also asserts the parts of the loader contract an asset can quietly break: a Node3D
## root, exactly one AnimationPlayer, feet on y=0, a body centred on x/z, facing +Z, and a
## height that still matches what the catalogue claims. Facing is measured, not assumed: the
## melee clip of all three rig families lunges forward, so the bone that travels furthest
## horizontally during it says which way forward is.
##
## Run: tools/godot/Godot_v4.6-voxel_win64.exe --headless --path . res://tools/test_creature_assets.tscn
extends Node

const CityVoxelNativeScript := preload("res://scripts/city/city_voxel_native.gd")

const VOXEL_SIZE := 0.5
const FIELD_Y_MAX := 47
## Parked away from every district and from the other nav tests' tiles.
const TILE := Vector2i(-260, -260)
const ORIGIN := Vector3i(90000, 0, 90000)
const SX := 96
const SZ := 96

## Rust rejects a profile that walks less than the link envelope's `min_drop`, which is how
## an earlier `car()` profile with `max_drop = 1.0` silently failed to configure and hung a
## test for half an hour. Mirrored here so the trap is named on this side too.
const LINK_MIN_DROP_VOX := 1.7

## What every action must resolve to, per rig family. The point of the whole file: an
## expectation written out in full, so a clip quietly becoming a different clip fails.
const EXPECTED_CLIPS: Dictionary[int, Dictionary] = {
	int(CreatureCatalog.Family.KAYKIT_SKELETON): {
		int(CreatureClips.Action.IDLE): "Idle",
		int(CreatureClips.Action.DEATH): "Death_A",
		int(CreatureClips.Action.CAST): "Spellcast_Shoot",
		int(CreatureClips.Action.MELEE): "Unarmed_Melee_Attack_Kick",
		int(CreatureClips.Action.LOCOMOTION): "Walking_A",
		int(CreatureClips.Action.HIT_REACT): "Hit_A",
	},
	int(CreatureCatalog.Family.QUATERNIUS_BIG): {
		int(CreatureClips.Action.IDLE): "Idle",
		int(CreatureClips.Action.DEATH): "Death",
		int(CreatureClips.Action.CAST): "Weapon",
		int(CreatureClips.Action.MELEE): "Punch",
		int(CreatureClips.Action.LOCOMOTION): "Walk",
		int(CreatureClips.Action.HIT_REACT): "HitReact",
	},
	int(CreatureCatalog.Family.QUATERNIUS_BLOB): {
		int(CreatureClips.Action.IDLE): "Idle",
		int(CreatureClips.Action.DEATH): "Death",
		int(CreatureClips.Action.CAST): "Bite_Front",
		int(CreatureClips.Action.MELEE): "Bite_Front",
		int(CreatureClips.Action.LOCOMOTION): "Walk",
		## The Blob set's own misspelling, and the reason a hit reaction cannot be resolved by
		## guessing at the name.
		int(CreatureClips.Action.HIT_REACT): "HitRecieve",
	},
}

## Bottom fraction of a body counted as the part standing on the ground.
const FOOTPRINT_SLICE := 0.12

## Which clip says which way a rig faces, and how to read it. The three families need three
## answers because they do not animate alike, and guessing one rule for all of them is how
## the Blob set first read as facing backwards.
##
## RECOIL is the honest one where it exists: a body struck from the front is pushed away from
## whatever hit it, so the bone that moves furthest during the hit clip moves toward -Z.
## The Quaternius Big rig plants its feet and flinches without translating anything, so it is
## read off `Punch` instead: an attack is a wind-up followed by a strike, and the strike is
## the later of the two extremes.
enum FacingProbe { RECOIL, STRIKE }

const FACING_CLIPS: Dictionary[int, String] = {
	int(CreatureCatalog.Family.KAYKIT_SKELETON): "Hit_A",
	int(CreatureCatalog.Family.QUATERNIUS_BIG): "Punch",
	int(CreatureCatalog.Family.QUATERNIUS_BLOB): "HitRecieve",
}
const FACING_MODES: Dictionary[int, FacingProbe] = {
	int(CreatureCatalog.Family.KAYKIT_SKELETON): FacingProbe.RECOIL,
	int(CreatureCatalog.Family.QUATERNIUS_BIG): FacingProbe.STRIKE,
	int(CreatureCatalog.Family.QUATERNIUS_BLOB): FacingProbe.RECOIL,
}

## Samples taken through the probe clip.
const FACING_SAMPLES := 32
## Movement smaller than this is not evidence of anything.
const FACING_MIN_TRAVEL := 0.05

var _failed := false
var _nav: NavService


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_test_nav_profiles()
	if _failed:
		_quit()
		return
	_test_every_model_conforms()
	if _failed:
		_quit()
		return
	_test_clip_resolution()
	if _failed:
		_quit()
		return
	_report_unspawnable()
	_test_variation_is_deterministic()
	if _failed:
		_quit()
		return
	_test_palette()
	if _failed:
		_quit()
		return
	_test_part_swap_compatibility()
	if _failed:
		_quit()
		return

	print("RESULT: OK")
	_quit()


# ---------------------------------------------------------------------------
# The mid-size nav profile
# ---------------------------------------------------------------------------

## Registration alone proves little — `register_profile` complains about a bad `max_drop` and
## then keeps the profile anyway. So the profile is used: a tile is baked, a surface is
## snapped to and a corridor is solved on it.
func _test_nav_profiles() -> void:
	_nav = NavService.instance()
	_nav.ensure_configured(VOXEL_SIZE)
	if not _nav.is_configured():
		_fail("FAIL NavService did not configure")
		return
	for id: int in _nav.profile_ids():
		var profile := _nav.profile(id)
		if profile.max_drop < LINK_MIN_DROP_VOX:
			_fail(
				"FAIL profile %s drops %.2f voxels, under the %.2f links start at"
				% [profile.display_name, profile.max_drop, LINK_MIN_DROP_VOX]
			)
			return
	if not _nav.has_profile(NavProfile.Id.MONSTER):
		_fail("FAIL the extension did not keep the mid-size profile")
		return
	var monster := _nav.profile(NavProfile.Id.MONSTER)
	if monster.radius_cells != 2 or monster.height_cells != 7:
		_fail(
			"FAIL the mid-size profile is %d x %d cells, not 2 x 7"
			% [monster.radius_cells, monster.height_cells]
		)
		return
	if not _nav.register_district(TILE, _bake_tile()):
		_fail("FAIL NavService refused the conformance tile")
		return
	var from := _w(Vector3i(8, 1, 8))
	var to := _w(Vector3i(SX - 8, 1, SZ - 8))
	var hit := _nav.nearest_surface(NavProfile.Id.MONSTER, from, 3.0)
	if not hit.found:
		_fail("FAIL the mid-size profile found no surface on an open %d x %d deck" % [SX, SZ])
		return
	if hit.clearance < monster.radius_cells or hit.headroom < monster.height_cells:
		_fail(
			"FAIL the deck gives the mid-size body clearance %d headroom %d"
			% [hit.clearance, hit.headroom]
		)
		return
	var path := _nav.find_path_now(NavProfile.Id.MONSTER, from, to)
	if path == null or not path.is_complete() or path.points.size() < 2:
		_fail(
			"FAIL the mid-size profile could not cross the deck: %s"
			% ["no result" if path == null else path.status_name()]
		)
		return
	print(
		(
			"nav: %d profiles registered, mid-size = %d cells wide / %d headroom,"
			+ " solved %d points over %.0f m"
		)
		% [
			_nav.profile_ids().size(),
			monster.radius_cells,
			monster.height_cells,
			path.points.size(),
			from.distance_to(to),
		]
	)


# ---------------------------------------------------------------------------
# The loader contract
# ---------------------------------------------------------------------------

## Every entry is measured and its whole row printed before anything fails, because the
## interesting answer to "does the roster conform" is the table, not the first offender.
func _test_every_model_conforms() -> void:
	print("model conformance:")
	print(
		"    %-24s %-8s %6s %6s %7s %7s %7s %7s %s"
		% ["model", "family", "height", "feet_y", "foot_x", "foot_z", "mesh_x", "mesh_z", "faces"]
	)
	var checked := 0
	var complaints: Array[String] = []
	for entry: CreatureCatalog.Entry in CreatureCatalog.all():
		if not ResourceLoader.exists(entry.path):
			_fail("FAIL %s: nothing at %s" % [entry.id, entry.path])
			return
		var packed: PackedScene = load(entry.path) as PackedScene
		if packed == null:
			_fail("FAIL %s: %s is not a PackedScene" % [entry.id, entry.path])
			return
		var instance: Node = packed.instantiate()
		var root: Node3D = instance as Node3D
		if root == null:
			_fail("FAIL %s: root is %s, not Node3D" % [entry.id, instance.get_class()])
			instance.free()
			return
		add_child(root)
		## Exactly what `undead_unit.gd` does to a freshly instantiated body, so what is
		## measured below is the body as the city poses it.
		root.position = entry.model_offset
		root.rotation = Vector3(0.0, entry.model_yaw, 0.0)

		var players: Array[AnimationPlayer] = []
		_collect_players(root, players)
		if players.size() != 1:
			_fail("FAIL %s: %d AnimationPlayers, expected exactly one" % [entry.id, players.size()])
			root.queue_free()
			return
		var skeleton := CreatureVariation.find_skeleton(root)
		if skeleton == null:
			_fail("FAIL %s: no Skeleton3D" % entry.id)
			root.queue_free()
			return

		var box := _rest_bounds(root)
		var stance := _footprint(root, box)
		var facing := 0.0
		if entry.is_spawnable():
			facing = _facing_forward(skeleton, players[0], entry)
		print(
			"    %-24s %-8s %6.3f %6.3f %7.3f %7.3f %7.3f %7.3f %s"
			% [
				entry.id,
				CreatureCatalog.family_name(entry.family).trim_prefix("quaternius_"),
				box.size.y,
				box.position.y,
				stance.x,
				stance.y,
				(box.position.x + box.end.x) * 0.5,
				(box.position.z + box.end.z) * 0.5,
				"-" if not entry.is_spawnable() else "%+.3f" % facing,
			]
		)

		var drift := absf(box.size.y - entry.measured_height) / entry.measured_height
		if drift > CreatureCatalog.HEIGHT_TOLERANCE:
			complaints.append(
				"%s measures %.3f units but the catalogue records %.3f"
				% [entry.id, box.size.y, entry.measured_height]
			)
		## Standing on the floor and standing over the nav position are only asked of bodies
		## that are actually spawned. The flying set is authored hovering and off-pivot,
		## which is exactly why it is in no spawn table.
		if entry.is_spawnable():
			## The footprint is what has to sit over the nav position, not the whole
			## silhouette: a Big monster's tail hangs a third of a metre behind it and moves
			## the mesh centre without moving where the creature stands.
			if absf(stance.x) > CreatureCatalog.CENTRE_TOLERANCE or absf(stance.y) > CreatureCatalog.CENTRE_TOLERANCE:
				complaints.append(
					"%s stands at x %.3f z %.3f, not over the origin"
					% [entry.id, stance.x, stance.y]
				)
			if absf(box.position.y) > CreatureCatalog.GROUND_TOLERANCE:
				complaints.append(
					"%s rests at y %.3f, not on the ground" % [entry.id, box.position.y]
				)
			if facing <= 0.0:
				complaints.append(
					"%s lunges toward %+.3f on z, so it does not face +Z" % [entry.id, facing]
				)
		checked += 1
		root.queue_free()
	if not complaints.is_empty():
		_fail("FAIL %d of %d bodies break the loader contract:\n  %s"
			% [complaints.size(), checked, "\n  ".join(complaints)])
		return
	print("    %d bodies load, measure, stand and face the way the catalogue claims" % checked)


## How far the body's front is toward +Z, measured rather than inferred. Positive is the
## contract; negative means the asset needs a `model_yaw` of PI and has not got one.
##
## Displacement is measured from each bone's first frame rather than from its rest pose,
## because a rig whose rest pose is a T-pose starts a combat clip already a metre away from
## it and that offset is not motion.
func _facing_forward(
	skeleton: Skeleton3D, player: AnimationPlayer, entry: CreatureCatalog.Entry
) -> float:
	var clip: String = FACING_CLIPS.get(int(entry.family), "")
	if clip.is_empty() or not player.has_animation(clip):
		_fail("FAIL %s: no '%s' to read facing off" % [entry.id, clip])
		return 0.0
	var animation := player.get_animation(clip)
	var samples: Array[PackedVector3Array] = []
	player.play(clip)
	for step in range(FACING_SAMPLES):
		player.seek(animation.length * float(step) / float(FACING_SAMPLES - 1), true)
		var frame := PackedVector3Array()
		for bone in range(skeleton.get_bone_count()):
			frame.append(skeleton.get_bone_global_pose(bone).origin)
		samples.append(frame)
	player.stop()

	## Whatever moves furthest horizontally is the part that carries the answer: the struck
	## body for a recoil, the fist for a punch.
	var limb := -1
	var travelled := 0.0
	for bone in range(skeleton.get_bone_count()):
		for frame: PackedVector3Array in samples:
			var delta := frame[bone] - samples[0][bone]
			var travel := Vector2(delta.x, delta.z).length()
			if travel > travelled:
				travelled = travel
				limb = bone
	if limb < 0 or travelled < FACING_MIN_TRAVEL:
		_fail(
			"FAIL %s: nothing in %s moves %.3f units, so facing is unmeasurable"
			% [entry.id, clip, FACING_MIN_TRAVEL]
		)
		return 0.0

	var back := 0.0
	var back_at := 0
	var forward := 0.0
	var forward_at := 0
	for step in range(samples.size()):
		var z := samples[step][limb].z - samples[0][limb].z
		if z < back:
			back = z
			back_at = step
		if z > forward:
			forward = z
			forward_at = step
	var reading := 0.0
	match FACING_MODES[int(entry.family)]:
		FacingProbe.RECOIL:
			reading = -(back if absf(back) >= forward else forward)
		FacingProbe.STRIKE:
			reading = forward if forward_at > back_at else back
	if absf(reading) < FACING_MIN_TRAVEL:
		_fail(
			"FAIL %s: %s moves %s by %.3f units but only %.3f of that along z"
			% [entry.id, clip, skeleton.get_bone_name(limb), travelled, absf(reading)]
		)
		return 0.0
	return reading


# ---------------------------------------------------------------------------
# Clip resolution — the table this test exists for
# ---------------------------------------------------------------------------

func _test_clip_resolution() -> void:
	print("clip resolution:")
	print(
		"    %-24s %-6s %-18s %-18s %-18s %-18s %-18s %s"
		% ["model", "clips", "idle", "death", "cast", "melee", "locomotion", "hit_react"]
	)
	for entry: CreatureCatalog.Entry in CreatureCatalog.all():
		if not entry.is_spawnable():
			continue
		var clips := _clip_list(entry)
		if clips.is_empty():
			_fail("FAIL %s exposes no clips at all" % entry.id)
			return
		var expected: Dictionary = EXPECTED_CLIPS.get(int(entry.family), {})
		if expected.is_empty():
			_fail("FAIL no expected clip table for family %s" % CreatureCatalog.family_name(entry.family))
			return
		var row := "    %-24s %-6d" % [entry.id, clips.size()]
		for action: CreatureClips.Action in CreatureClips.all_actions():
			var got := CreatureClips.resolve(clips, action, entry.id)
			if not expected.has(int(action)):
				_fail(
					"FAIL no expected %s clip for family %s"
					% [
						CreatureClips.action_name(action),
						CreatureCatalog.family_name(entry.family),
					]
				)
				return
			var want: String = expected[int(action)]
			if got != want:
				_fail(
					"FAIL %s resolves %s to '%s', expected '%s'"
					% [entry.id, CreatureClips.action_name(action), got, want]
				)
				return
			row += " %-18s" % got
		print(row)
	print(
		"    every spawnable body resolves all %d actions to the clip named above"
		% CreatureClips.all_actions().size()
	)


## The flying set and the one sunken blob are vendored but never spawned. They are surveyed
## rather than asserted, so the report says what was left out and what it would have done.
func _report_unspawnable() -> void:
	print("not in the spawn tables:")
	for entry: CreatureCatalog.Entry in CreatureCatalog.all():
		if entry.is_spawnable():
			continue
		var clips := _clip_list(entry)
		var misses := PackedStringArray()
		for action: CreatureClips.Action in CreatureClips.all_actions():
			if CreatureClips.try_resolve(clips, action).is_empty():
				misses.append(CreatureClips.action_name(action))
		print(
			"    %-24s %2d clips, unresolved: %s — %s"
			% [
				entry.id,
				clips.size(),
				"none" if misses.is_empty() else ", ".join(misses),
				entry.note,
			]
		)


# ---------------------------------------------------------------------------
# The variation layer
# ---------------------------------------------------------------------------

func _test_variation_is_deterministic() -> void:
	var entry := CreatureCatalog.by_id("kaykit/Skeleton_Mage")
	if entry == null:
		_fail("FAIL the catalogue lost the mage")
		return
	var clips := _clip_list(entry)
	var seen: Dictionary[String, int] = {}
	for unit_seed in range(64):
		var a := CreatureVariation.roll(entry, clips, unit_seed)
		var b := CreatureVariation.roll(entry, clips, unit_seed)
		if a.describe() != b.describe():
			_fail("FAIL seed %d rolled two different bodies:\n  %s\n  %s" % [unit_seed, a.describe(), b.describe()])
			return
		for action: CreatureClips.Action in CreatureClips.all_actions():
			if a.clip_for(action) != b.clip_for(action):
				_fail("FAIL seed %d rolled two different takes of %s" % [unit_seed, CreatureClips.action_name(action)])
				return
			if not clips.has(a.clip_for(action)):
				_fail("FAIL seed %d chose '%s', which the rig does not have" % [unit_seed, a.clip_for(action)])
				return
		if a.width < CreatureVariation.WIDTH_MIN or a.width > CreatureVariation.WIDTH_MAX:
			_fail("FAIL seed %d rolled a build %.3f wide, outside the collision budget" % [unit_seed, a.width])
			return
		if a.height < CreatureVariation.HEIGHT_MIN or a.height > CreatureVariation.HEIGHT_MAX:
			_fail("FAIL seed %d rolled a build %.3f tall, outside the collision budget" % [unit_seed, a.height])
			return
		seen[a.describe()] = unit_seed
	if seen.size() < 60:
		_fail("FAIL 64 seeds produced only %d distinct bodies" % seen.size())
		return

	## Selection has to follow the seed too, or the catalogue is only half wired up.
	var picks: Dictionary[String, int] = {}
	for unit_seed in range(200):
		var rng := RandomNumberGenerator.new()
		rng.seed = unit_seed
		var picked := CreatureCatalog.pick(CreatureCatalog.Slot.FODDER, rng)
		picks[picked.id] = picks.get(picked.id, 0) + 1
	var fodder := CreatureCatalog.for_slot(CreatureCatalog.Slot.FODDER).size()
	if picks.size() < fodder / 2:
		_fail("FAIL 200 seeds only ever reached %d of the %d fodder bodies" % [picks.size(), fodder])
		return
	print(
		(
			"variation: 64 seeds give %d distinct bodies and repeat exactly;"
			+ " 200 spawns reach %d of %d fodder models"
		)
		% [seen.size(), picks.size(), fodder]
	)


# ---------------------------------------------------------------------------
# The palette
# ---------------------------------------------------------------------------

## The three ways the recolour has broken before, all of which were invisible to the tests that
## existed and visible only in a screenshot somebody happened to look at.
##
## One: a spatial shader that writes ALPHA is compiled into the transparent pipeline and stops
## casting a shadow, which had recoloured skeletons floating like glass over the pavement.
## Two: the material cache keyed on the texture alone, which collapsed every part sharing an
## atlas onto whichever material was seen first and took the eye glow with it.
## Three: the eye sockets are the roster's only emitters, and a recolour that does not carry
## `emission` forward simply deletes them.
func _test_palette() -> void:
	var alpha := RegEx.new()
	alpha.compile("ALPHA\\s*[*+\\-/]?=")
	if alpha.search(CreatureVariation.PALETTE_SHADER.code) != null:
		_fail("FAIL the palette shader writes ALPHA, so recoloured bodies cast no shadow")
		return

	for b: CreatureVariation.Band in CreatureVariation.bands():
		if b.sat_low >= b.sat_high or b.value_low >= b.value_high:
			_fail(
				"FAIL band %s has sat %.2f..%.2f value %.2f..%.2f, which is not a range"
				% [b.name, b.sat_low, b.sat_high, b.value_low, b.value_high]
			)
			return
		## A band whose ceiling can be jittered past 1.0 is a band that clips, and a clipped
		## ceiling is the same colour for every roll above it.
		if b.sat_high + b.sat_jitter > 1.0 or b.value_high + b.value_jitter > 1.0:
			_fail("FAIL band %s can jitter its ceiling past 1.0" % b.name)
			return

	## Every band has to be reachable, or the palette is narrower than it reads.
	var entry := CreatureCatalog.by_id("kaykit/Skeleton_Minion")
	var clips := _clip_list(entry)
	var reached: Dictionary[String, int] = {}
	for unit_seed in range(64):
		var rolled := CreatureVariation.roll(entry, clips, unit_seed)
		reached[rolled.band.name] = reached.get(rolled.band.name, 0) + 1
	if reached.size() != CreatureVariation.bands().size():
		_fail(
			"FAIL 64 seeds reached %d of the %d palette bands"
			% [reached.size(), CreatureVariation.bands().size()]
		)
		return

	## And the recolour has to survive contact with a real body: the eye sockets keep their own
	## material, that material still emits, and the textured body's does not.
	CreatureVariation.clear_material_cache()
	var body: Node3D = (load(entry.path) as PackedScene).instantiate() as Node3D
	add_child(body)
	CreatureVariation.roll(entry, clips, 3).apply(body, entry)
	var eyes := _override_of(body, "_Eyes")
	var bone := _override_of(body, "_Head")
	if eyes == null or bone == null:
		_fail("FAIL the recolour left %s unmaterialised" % ["the eyes" if eyes == null else "the head"])
		body.queue_free()
		return
	if eyes == bone:
		_fail("FAIL the eye sockets and the skull share one material, so the cache does not discriminate")
		body.queue_free()
		return
	var glow: float = eyes.get_shader_parameter("emission_strength")
	var dull: float = bone.get_shader_parameter("emission_strength")
	if glow <= 0.0:
		_fail("FAIL the recoloured eye sockets emit %.3f, so the glow was dropped" % glow)
		body.queue_free()
		return
	if dull != 0.0:
		_fail("FAIL the recoloured skull emits %.3f, which the vendored material does not" % dull)
		body.queue_free()
		return
	body.queue_free()
	print(
		(
			"palette: %d bands, all reached in 64 seeds, none clipping; no ALPHA write;"
			+ " eye sockets keep their own material and emit %.2f where the skull emits %.2f"
		)
		% [reached.size(), glow, dull]
	)


func _override_of(node: Node, suffix: String) -> ShaderMaterial:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and String(mesh_instance.name).ends_with(suffix):
		return mesh_instance.get_surface_override_material(0) as ShaderMaterial
	for child in node.get_children():
		var found := _override_of(child, suffix)
		if found != null:
			return found
	return null


# ---------------------------------------------------------------------------
# Cross-model part swapping
# ---------------------------------------------------------------------------

## Whether a head from one skeleton may be worn by another comes down to one thing: the skin
## has to bind by joint name, and every joint it names has to exist on the host. Anything
## else and a graft is a guess.
func _test_part_swap_compatibility() -> void:
	var family: Array[CreatureCatalog.Entry] = []
	for entry: CreatureCatalog.Entry in CreatureCatalog.all():
		if CreatureCatalog.supports_part_swap(entry.family):
			family.append(entry)
	if family.size() < 2:
		_fail("FAIL fewer than two swap-capable bodies, so there is nothing to swap")
		return

	var roots: Dictionary[String, Node3D] = {}
	for entry: CreatureCatalog.Entry in family:
		var root: Node3D = (load(entry.path) as PackedScene).instantiate() as Node3D
		add_child(root)
		roots[entry.id] = root

	var pairs := 0
	var grafts := 0
	for host: CreatureCatalog.Entry in family:
		var skeleton := CreatureVariation.find_skeleton(roots[host.id])
		for donor: CreatureCatalog.Entry in family:
			if donor.id == host.id:
				continue
			pairs += 1
			for group: PackedStringArray in CreatureCatalog.part_slots():
				var part := _find_part(roots[donor.id], group)
				if part == null:
					continue
				if not CreatureVariation.skin_fits(part.skin, skeleton):
					_fail(
						"FAIL %s cannot wear %s's %s: the skin does not bind by name onto its rig"
						% [host.id, donor.id, group[0]]
					)
					_free_all(roots)
					return
				grafts += 1
	for root: Node3D in roots.values():
		root.queue_free()

	## And the graft has to actually happen, not merely be legal.
	var entry := CreatureCatalog.by_id("kaykit/Skeleton_Minion")
	var body: Node3D = (load(entry.path) as PackedScene).instantiate() as Node3D
	add_child(body)
	var variation := CreatureVariation.roll(entry, _clip_list(entry), 7)
	variation.donor_id = "kaykit/Skeleton_Warrior"
	variation.swapped = PackedStringArray(["_Skull", "_ArmRight"])
	variation.apply(body, entry)
	if variation.swapped.size() != 2:
		_fail("FAIL the graft kept %d of 2 parts" % variation.swapped.size())
		body.queue_free()
		return
	for group: PackedStringArray in CreatureCatalog.part_slots():
		if not variation.swapped.has(group[0]):
			continue
		if _find_part(body, group) == null:
			_fail("FAIL %s went missing after the graft" % group[0])
			body.queue_free()
			return
	body.queue_free()
	print(
		"part swap: %d donor pairs, %d name-bound skins, all compatible; a live graft kept %s"
		% [pairs, grafts, str(variation.swapped)]
	)


func _free_all(roots: Dictionary[String, Node3D]) -> void:
	for root: Node3D in roots.values():
		root.queue_free()


# ---------------------------------------------------------------------------
# Measurement
# ---------------------------------------------------------------------------

## Rest-pose bounds from the vertex arrays, in the space the body is placed in — so the
## catalogue's declared offset and yaw are part of what is measured.
##
## `MeshInstance3D.get_aabb()` cannot answer this: on a skinned mesh it reports a
## skeleton-expanded box, which has every Quaternius Big model 4.65 units wide and standing
## well below its own feet.
func _rest_bounds(root: Node3D) -> AABB:
	var box := AABB()
	var have := false
	for mesh_instance: MeshInstance3D in _meshes(root):
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		var placed := mesh_instance.global_transform
		for surface in range(mesh.get_surface_count()):
			var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for v: Vector3 in verts:
				var p := placed * v
				if have:
					box = box.expand(p)
				else:
					box = AABB(p, Vector3.ZERO)
					have = true
	return box


## Where the body actually stands, as the x/z centre of the vertices in the bottom slice of
## it. The whole-mesh centre answers a different question — a tail, a raised arm or a
## wizard's hat all move it — and the one that matters is whether the part touching the
## ground sits over the nav position the motor puts the body on.
func _footprint(root: Node3D, box: AABB) -> Vector2:
	var ceiling := box.position.y + box.size.y * FOOTPRINT_SLICE
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for mesh_instance: MeshInstance3D in _meshes(root):
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		var placed := mesh_instance.global_transform
		for surface in range(mesh.get_surface_count()):
			var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for v: Vector3 in verts:
				var p := placed * v
				if p.y > ceiling:
					continue
				lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
				hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	if lo.x == INF:
		_fail("FAIL a model has no vertices in its own bottom slice")
		return Vector2.ZERO
	return (lo + hi) * 0.5


func _clip_list(entry: CreatureCatalog.Entry) -> PackedStringArray:
	var root: Node = (load(entry.path) as PackedScene).instantiate()
	var players: Array[AnimationPlayer] = []
	_collect_players(root, players)
	var out := PackedStringArray()
	if players.size() == 1:
		out = players[0].get_animation_list()
	root.free()
	return out


func _collect_players(node: Node, out: Array[AnimationPlayer]) -> void:
	if node is AnimationPlayer:
		out.append(node as AnimationPlayer)
	for child in node.get_children():
		_collect_players(child, out)


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_meshes(child))
	return out


func _find_part(node: Node, group: PackedStringArray) -> MeshInstance3D:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null:
		for suffix: String in group:
			if String(mesh_instance.name).ends_with(suffix):
				return mesh_instance
	for child in node.get_children():
		var found := _find_part(child, group)
		if found != null:
			return found
	return null


func _bake_tile() -> RefCounted:
	var volume = CityVoxelNativeScript.make_volume()
	volume.fill_box(Vector3i.ZERO, Vector3i(SX, 1, SZ), VoxelMaterial.CONCRETE)
	var tables := _nav.solidity_tables()
	var bake = CityVoxelNativeScript.make_nav_bake()
	var ok: bool = bake.bake_from_volume(
		volume,
		ORIGIN,
		SX,
		SZ,
		0,
		FIELD_Y_MAX,
		tables["class"],
		tables["top"],
		tables["destructible"],
		tables["climbable"],
		_nav.link_params()
	)
	if not ok:
		_fail("FAIL bake_from_volume rejected the conformance tile")
		return null
	return bake as RefCounted


func _w(vox: Vector3i) -> Vector3:
	return Vector3(
		float(ORIGIN.x + vox.x), float(ORIGIN.y + vox.y), float(ORIGIN.z + vox.z)
	) * VOXEL_SIZE


func _quit() -> void:
	NavService.reset()
	if _failed:
		print("RESULT: FAILED")
		get_tree().quit(1)
	else:
		get_tree().quit(0)
