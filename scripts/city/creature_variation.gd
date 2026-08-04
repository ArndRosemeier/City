## The procedural layer over the authored bodies: one seed, one distinct-looking monster.
##
## Fifty models is a roster; fifty models times a palette band, a build, a set of donor
## limbs and a choice of takes is a crowd. Everything here is derived from a single integer
## so the same unit looks the same on every machine and in every screenshot, and so a test
## can assert the spread rather than eyeball it.
##
## The build is not cosmetic: `undead_unit.gd` feeds `width` and `height` straight into the
## collision capsule, `hit_radius`, `hit_half_height` and the muzzle, because the cars in
## this project already taught it what happens when a declared size drifts from the mesh.
class_name CreatureVariation
extends RefCounted

const _Self := preload("res://scripts/city/creature_variation.gd")
const CreatureCatalogScript := preload("res://scripts/city/creature_catalog.gd")
const CreatureClipsScript := preload("res://scripts/city/creature_clips.gd")
const PALETTE_SHADER := preload("res://assets/city/shaders/creature_palette.gdshader")

## Squat-and-wide through tall-and-lanky, as multipliers on the authored proportions. Wider
## than this and the capsule has to grow past what the mid-size profile promises.
const WIDTH_MIN := 0.82
const WIDTH_MAX := 1.22
const HEIGHT_MIN := 0.86
const HEIGHT_MAX := 1.18
## Chance a KayKit body borrows a given part from another KayKit body.
const PART_SWAP_CHANCE := 0.34


## An art-directed slice of colour space, and the whole reason the recolour is aimed rather
## than rotated.
##
## A hue rotation cannot be pointed at a colour. It preserves the source's saturation and its
## distance from every other hue, so any rotation wide enough to vary fifty bodies also walks
## them through mint, lilac, rose and powder blue — which is how a rank of KayKit skeletons
## came out reading as an Easter display. A band names the colour it wants and drags the body
## into it, so the range is a decision instead of a hope.
class Band:
	extends RefCounted
	var name: String = ""
	## Turns of the wheel: 0 red, 1/6 yellow, 1/3 green, 2/3 blue, 5/6 magenta.
	var hue: float = 0.0
	var hue_jitter: float = 0.0
	## Fraction of the source's own hue spread kept around `hue`. Not zero: the KayKit bone,
	## rags and steel are three hues on one texture, and flattening them onto one makes a body
	## read as a single moulded plastic shape rather than as a thing wearing rags.
	var hue_keep: float = 0.12
	## Output saturation where the source is grey, and where it is fully vivid. The source's own
	## saturation picks between the two, which is what keeps a bone skull pale while the rags
	## over it take the band's colour.
	var sat_low: float = 0.0
	var sat_high: float = 0.5
	var sat_jitter: float = 0.0
	## Output value where the source is black, and where it is white. An absolute range rather
	## than a gain on the source: a gain leaves a recolour of an already mid-dark atlas region
	## dimmer than the vendored art however high its ceiling, which is what had the orc coming
	## out muddier than the file it was loaded from.
	var value_low: float = 0.10
	var value_high: float = 0.80
	var value_jitter: float = 0.0
	## What this band's emissive parts glow. The KayKit eye sockets are the roster's only
	## emitters, and a hot spot in an otherwise dulled body carries most of the menace.
	var ember: Color = Color.WHITE


## One ShaderMaterial per source material for the whole army: the recolour is an instance
## uniform, so bodies sharing an atlas share the material and differ per MeshInstance3D.
static var _palette_materials: Dictionary[String, ShaderMaterial] = {}
static var _bands: Array[Band] = []


## Sickly greens, bruise purples, rust, ash and bone — the range the enemies are allowed.
##
## Every band is dulled or darkened enough that no roll of it can arrive at a pastel, and each
## is far enough from its neighbours to be named across a street. Bone and ash are the pair that
## has to be kept apart deliberately, because both are nearly grey: bone is a warm ivory held
## high, ash a cold grey held well below it, and their embers finish the job.
##
## Saturation floors are not zero on the warm bands. Under this project's cool sky an almost-grey
## body takes its hue from the ambient rather than from the band, which had bone photographing as
## a second, paler ash — so bone and rust carry enough of their own colour to win that argument.
##
## The value ceilings are all well clear of the floors and none of them is low. Dulling a palette
## by dropping everything toward black is the failure mode next door to pastel: bodies stop being
## different colours and start being the same silhouette, and the face — which on these rigs is
## the whole read — goes first.
static func bands() -> Array[Band]:
	if _bands.is_empty():
		_bands = [
			_band("bone", 0.105, 0.020, 0.10,
				Vector2(0.10, 0.36), 0.05, Vector2(0.18, 0.87), 0.05, Color(1.00, 0.86, 0.38)),
			_band("ash", 0.600, 0.050, 0.08,
				Vector2(0.03, 0.12), 0.03, Vector2(0.12, 0.63), 0.07, Color(0.58, 0.80, 0.96)),
			_band("sickly", 0.245, 0.040, 0.17,
				Vector2(0.10, 0.62), 0.12, Vector2(0.13, 0.78), 0.09, Color(0.56, 1.00, 0.33)),
			_band("bruise", 0.740, 0.040, 0.15,
				Vector2(0.10, 0.42), 0.09, Vector2(0.12, 0.62), 0.09, Color(0.55, 0.14, 0.98)),
			_band("rust", 0.045, 0.022, 0.13,
				Vector2(0.20, 0.70), 0.11, Vector2(0.13, 0.68), 0.09, Color(1.00, 0.46, 0.13)),
		]
	return _bands


static func _band(
	name: String,
	hue: float,
	hue_jitter: float,
	hue_keep: float,
	sat: Vector2,
	sat_jitter: float,
	value: Vector2,
	value_jitter: float,
	ember: Color
) -> Band:
	var b := Band.new()
	b.name = name
	b.hue = hue
	b.hue_jitter = hue_jitter
	b.hue_keep = hue_keep
	b.sat_low = sat.x
	b.sat_high = sat.y
	b.sat_jitter = sat_jitter
	b.value_low = value.x
	b.value_high = value.y
	b.value_jitter = value_jitter
	b.ember = ember
	return b


var seed: int = 0
## Which slice of the palette this body was cast into, and where inside it it landed.
var band: Band = null
var hue: float = 0.0
var saturation: float = 0.5
var value: float = 0.8
## Multipliers on the authored proportions, x/z and y.
var width: float = 1.0
var height: float = 1.0
## Chosen take per CreatureClips.Action.
var clips: Dictionary[int, String] = {}
## Where borrowed parts came from, "" when nothing was borrowed.
var donor_id: String = ""
## Node suffixes actually replaced, for the report and for the test.
var swapped: PackedStringArray = PackedStringArray()


## Everything a body's look is decided by, from its seed. `available` is the rig's own clip
## list, so the take chosen is always one the rig has.
static func roll(
	entry: CreatureCatalog.Entry, available: PackedStringArray, unit_seed: int
) -> _Self:
	var v: _Self = _Self.new()
	v.seed = unit_seed
	var rng := RandomNumberGenerator.new()
	rng.seed = unit_seed
	var palette := _Self.bands()
	## The band is stepped through rather than drawn, so any five consecutive seeds cover the
	## whole palette. Drawing it independently per unit leaves the count to luck — nine
	## consecutive seeds came out three rust and two ash, which looks like a narrower palette
	## than it is — and a crowd is exactly a run of consecutive seeds.
	v.band = palette[posmod(unit_seed, palette.size())]
	## Jitter moves the band's hue and its two ceilings. Both floors stay where the band put
	## them, because they are what stops a roll bottoming out into a colour it was drawn to
	## exclude. The ceilings carry most of the within-band variety, and value carries most of
	## that: two bodies of one band want to read as a pale one and a deep one.
	v.hue = fposmod(v.band.hue + rng.randf_range(-v.band.hue_jitter, v.band.hue_jitter), 1.0)
	v.saturation = clampf(
		v.band.sat_high + rng.randf_range(-v.band.sat_jitter, v.band.sat_jitter),
		v.band.sat_low,
		1.0
	)
	v.value = clampf(
		v.band.value_high + rng.randf_range(-v.band.value_jitter, v.band.value_jitter),
		v.band.value_low,
		1.0
	)
	v.width = rng.randf_range(WIDTH_MIN, WIDTH_MAX)
	v.height = rng.randf_range(HEIGHT_MIN, HEIGHT_MAX)
	for action: CreatureClips.Action in CreatureClipsScript.all_actions():
		var pool := CreatureClipsScript.variants_present(available, action, entry.id)
		if pool.is_empty():
			## resolve() has already said which model has no clip for which action.
			v.clips[int(action)] = ""
			continue
		v.clips[int(action)] = pool[rng.randi_range(0, pool.size() - 1)]
	v._roll_parts(entry, rng)
	return v


func clip_for(action: CreatureClips.Action) -> String:
	if not clips.has(int(action)):
		push_error("CreatureVariation: no take rolled for %s" % CreatureClipsScript.action_name(action))
		return ""
	return clips[int(action)]


## Recolour `model`, then graft on whatever limbs the roll borrowed. The build multipliers
## are deliberately not applied here: they belong on the body's own scale, next to the
## collision numbers that have to agree with them.
func apply(model: Node3D, entry: CreatureCatalog.Entry) -> void:
	_apply_parts(model, entry)
	_Self.paint(model, band, hue, saturation, value)


func describe() -> String:
	var parts := "none" if swapped.is_empty() else "%s from %s" % [", ".join(swapped), donor_id]
	return (
		"seed %d  %-6s hue %.3f sat %.2f val %.2f  build %.2fx%.2f  parts %s"
		% [seed, band.name, hue, saturation, value, width, height, parts]
	)


# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------

## Recolour every mesh under `node` into `band`, landing at an explicit point inside it.
##
## Static and band-first because not every caller wants a rolled monster. The chess set fields
## two fixed armies and has no use for random limbs or random takes, so it needs the recolour
## without `roll()` around it. The material cache is shared either way: a tinted chess board and
## a street full of monsters wearing the same atlas still come to one ShaderMaterial between
## them, because the colour rides on the MeshInstance3D rather than on the material.
static func paint(
	node: Node, band: Band, hue: float, sat_high: float, value_high: float
) -> void:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		var mesh := mesh_instance.mesh
		for surface in range(mesh.get_surface_count()):
			var material := _palette_material(mesh.surface_get_material(surface), mesh_instance.name)
			if material == null:
				continue
			mesh_instance.set_surface_override_material(surface, material)
		mesh_instance.set_instance_shader_parameter("band_hue", hue)
		mesh_instance.set_instance_shader_parameter("band_hue_keep", band.hue_keep)
		mesh_instance.set_instance_shader_parameter("band_sat_low", band.sat_low)
		mesh_instance.set_instance_shader_parameter("band_sat_high", sat_high)
		mesh_instance.set_instance_shader_parameter("band_value_low", band.value_low)
		mesh_instance.set_instance_shader_parameter("band_value_high", value_high)
		mesh_instance.set_instance_shader_parameter(
			"band_ember", Vector3(band.ember.r, band.ember.g, band.ember.b)
		)
	for child in node.get_children():
		paint(child, band, hue, sat_high, value_high)


## The band at its own nominal colour, with none of the per-unit jitter a roll adds.
static func paint_flat(node: Node, band: Band) -> void:
	paint(node, band, band.hue, band.sat_high, band.value_high)


## A band built from scratch, for callers outside the enemy palette. Deliberately not appended
## to `bands()`: that list is the range the roster is allowed, and `roll()` steps through it by
## seed, so a sixth entry would recolour every monster in the city.
static func make_band(
	name: String,
	hue: float,
	hue_keep: float,
	sat: Vector2,
	value: Vector2,
	ember: Color
) -> Band:
	return _band(name, hue, 0.0, hue_keep, sat, 0.0, value, 0.0, ember)


static func _palette_material(source: Material, who: String) -> ShaderMaterial:
	var base := source as BaseMaterial3D
	if base == null:
		push_error(
			"CreatureVariation: %s uses %s, not a BaseMaterial3D, so it cannot be recoloured"
			% [who, "nothing" if source == null else source.get_class()]
		)
		return null
	## A part with no texture is not a fault: the KayKit eyes are flat-coloured, and they have to
	## take the same band as the body or a recoloured skeleton keeps white eyes.
	var albedo := base.albedo_texture
	var texture_key := "flat"
	if albedo != null:
		texture_key = (
			"rid:%d" % albedo.get_rid().get_id()
			if albedo.resource_path.is_empty()
			else albedo.resource_path
		)
	## Every Quaternius body shares one atlas, and the KayKit eyes share the untextured "flat"
	## key with anything else untextured, so the texture alone does not identify a material.
	## Everything the shader reads off the source belongs in the key, or a body silently inherits
	## another body's roughness and the eye sockets stop glowing.
	var emission := 0.0
	if base.emission_enabled:
		emission = base.emission.get_luminance() * base.emission_energy_multiplier
	var key := "%s|%s|%.4f|%.4f|%.4f" % [
		texture_key, base.albedo_color.to_html(false), base.roughness, base.metallic, emission
	]
	if _palette_materials.has(key):
		return _palette_materials[key]
	var material := ShaderMaterial.new()
	material.shader = PALETTE_SHADER
	material.resource_name = "CreaturePalette:%s" % texture_key.get_file()
	material.set_shader_parameter("albedo_tex", albedo)
	material.set_shader_parameter("albedo_base", base.albedo_color)
	material.set_shader_parameter("roughness_base", base.roughness)
	material.set_shader_parameter("metallic_base", base.metallic)
	material.set_shader_parameter("emission_strength", emission)
	_palette_materials[key] = material
	return material


## Tools that reload assets between shots must not keep materials pointing at freed
## textures.
static func clear_material_cache() -> void:
	_palette_materials.clear()


# ---------------------------------------------------------------------------
# Part swapping
# ---------------------------------------------------------------------------

func _roll_parts(entry: CreatureCatalog.Entry, rng: RandomNumberGenerator) -> void:
	if not CreatureCatalogScript.supports_part_swap(entry.family):
		return
	var donors: Array[CreatureCatalog.Entry] = []
	for other: CreatureCatalog.Entry in CreatureCatalogScript.all():
		if other.family == entry.family and other.id != entry.id:
			donors.append(other)
	if donors.is_empty():
		return
	var donor := donors[rng.randi_range(0, donors.size() - 1)]
	donor_id = donor.id
	for group: PackedStringArray in CreatureCatalogScript.part_slots():
		if rng.randf() >= PART_SWAP_CHANCE:
			continue
		swapped.append(group[0])


func _apply_parts(model: Node3D, entry: CreatureCatalog.Entry) -> void:
	if swapped.is_empty() or donor_id.is_empty():
		return
	var host_skeleton := find_skeleton(model)
	if host_skeleton == null:
		push_error("CreatureVariation: %s has no Skeleton3D to graft parts onto" % entry.id)
		return
	var donor: CreatureCatalog.Entry = CreatureCatalogScript.by_id(donor_id)
	if donor == null:
		return
	var donor_scene: PackedScene = load(donor.path) as PackedScene
	if donor_scene == null:
		push_error("CreatureVariation: donor %s did not load from %s" % [donor.id, donor.path])
		return
	var donor_root: Node = donor_scene.instantiate()
	var groups := CreatureCatalogScript.part_slots()
	var done := PackedStringArray()
	for group: PackedStringArray in groups:
		if not swapped.has(group[0]):
			continue
		if _graft(model, host_skeleton, donor_root, group, entry.id, donor.id):
			done.append(group[0])
	swapped = done
	donor_root.queue_free()


## Move one part from the donor rig onto the host rig. Both KayKit bodies split into the same
## named meshes over the same 41-bone rig, and the import writes named skin binds, so the
## graft is legal exactly when every bind the donor skin asks for exists on the host.
func _graft(
	model: Node3D,
	host_skeleton: Skeleton3D,
	donor_root: Node,
	group: PackedStringArray,
	host_id: String,
	donor_label: String
) -> bool:
	var host_part := _find_part(model, group)
	var donor_part := _find_part(donor_root, group)
	if host_part == null or donor_part == null:
		return false
	if not skin_fits(donor_part.skin, host_skeleton):
		push_error(
			"CreatureVariation: %s cannot wear %s's %s — the skin binds to joints it lacks"
			% [host_id, donor_label, group[0]]
		)
		return false
	var host_name := String(host_part.name)
	var skin := donor_part.skin
	donor_part.get_parent().remove_child(donor_part)
	host_part.get_parent().remove_child(host_part)
	host_part.queue_free()
	## `remove_child` leaves the donor scene as the owner, and re-parenting a node that still
	## points at an owner outside its new branch is what `add_child` warns about.
	donor_part.owner = null
	host_skeleton.add_child(donor_part)
	donor_part.name = host_name
	donor_part.skeleton = NodePath("..")
	donor_part.skin = skin
	return true


## Does every joint this skin binds exist on that skeleton? A skin imported with named binds
## re-binds by name, so this is the whole compatibility question for a cross-model graft.
static func skin_fits(skin: Skin, skeleton: Skeleton3D) -> bool:
	if skin == null or skeleton == null:
		return false
	for i in range(skin.get_bind_count()):
		var bone := skin.get_bind_name(i)
		if bone.is_empty():
			## An index-bound skin means the two rigs have to agree on bone order as well as
			## on bone names, which is not something this catalogue can promise.
			return false
		if skeleton.find_bone(bone) < 0:
			return false
	return true


## First Skeleton3D under `node`, depth-first. Every rig in the catalogue has exactly one.
static func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := find_skeleton(child)
		if found != null:
			return found
	return null


static func _find_part(node: Node, group: PackedStringArray) -> MeshInstance3D:
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
