## Crowd/player outfit: skinned MH outfit GLB variant (+ optional skin tint).
class_name PedOutfit
extends RefCounted

var female: bool = false
var variant_id: String = ""
var scene_path: String = ""
var skin: Color = Color(0.82, 0.65, 0.52)
var proxy_color: Color = Color(0.35, 0.42, 0.55)

## Legacy color fields kept so mid-LOD / older call sites still compile.
var shirt: Color = Color(0.35, 0.42, 0.55)
var pants: Color = Color(0.22, 0.24, 0.28)
var shoes: Color = Color(0.12, 0.10, 0.09)


static func random(rng: RandomNumberGenerator, female: bool = false) -> PedOutfit:
	return PedOutfitCatalog.pick(rng, female)


func mid_proxy_color() -> Color:
	return proxy_color
