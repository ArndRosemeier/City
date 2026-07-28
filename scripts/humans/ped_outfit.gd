## Crowd/player outfit: skinned MH outfit GLB variant (+ optional skin tint).
class_name PedOutfit
extends RefCounted

## Which pool an outfit belongs to. Civilians and the player draw from CIVILIAN only, and the
## pools are disjoint by construction in PedOutfitCatalog.
enum Faction { CIVILIAN, HOSTILE }

## What a mesh inside the outfit scene represents. Resolved from the material names the
## exporter recorded in catalog.json, never guessed from node names.
enum MeshRole { SKIN, GARMENT, UNKNOWN }

var female: bool = false
var faction: Faction = Faction.CIVILIAN
var variant_id: String = ""
var scene_path: String = ""
var skin: Color = Color(0.82, 0.65, 0.52)
var proxy_color: Color = Color(0.35, 0.42, 0.55)
## Exact material resource names inside scene_path, as written by the MPFB exporter.
var skin_material: String = ""
var garment_materials: PackedStringArray = PackedStringArray()

## Legacy color fields kept so mid-LOD / older call sites still compile.
var shirt: Color = Color(0.35, 0.42, 0.55)
var pants: Color = Color(0.22, 0.24, 0.28)
var shoes: Color = Color(0.12, 0.10, 0.09)


static func random(rng: RandomNumberGenerator, female: bool, faction: Faction) -> PedOutfit:
	return PedOutfitCatalog.pick(rng, female, faction)


func mid_proxy_color() -> Color:
	return proxy_color


func role_for_material(material_name: String) -> MeshRole:
	## An unnamed material cannot be matched against anything, so it stays unclassified rather
	## than colliding with an outfit that has no skin_material recorded.
	if material_name == "" or skin_material == "":
		return MeshRole.UNKNOWN
	if material_name == skin_material:
		return MeshRole.SKIN
	if garment_materials.has(material_name):
		return MeshRole.GARMENT
	return MeshRole.UNKNOWN
