## Assert the authored texture pitch and the shader's tile_meters still agree.
##
## tools/generate_city_textures.py draws standing seams, pantiles, curtain panels, plates,
## floor tiles and mullions from real-world feature sizes and publishes the resulting
## repeat size per texture. VoxelSurfaceSpec declares the same number independently, and
## nothing used to connect the two: the roof rib was authored at 48 px and shipped at a
## tile_meters that put it 0.117 m wide, a quarter of a voxel, so the roof read as fabric.
extends Node

const TILE_METERS_JSON := "res://assets/city/textures/tile_meters.json"
## Repeat sizes are rounded to four places on the way out of the generator.
const TOLERANCE := 0.001

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	var authored := _load_authored()
	if not authored.is_empty():
		_check_specs(authored)
	print("RESULT: ", "FAILED" if _failed else "OK")
	get_tree().quit(1 if _failed else 0)


func _load_authored() -> Dictionary[String, Vector2]:
	var out: Dictionary[String, Vector2] = {}
	var text := FileAccess.get_file_as_string(TILE_METERS_JSON)
	if text == "":
		_fail(
			(
				"FAIL cannot read %s (error %d) — run tools/generate_city_textures.py"
				% [TILE_METERS_JSON, FileAccess.get_open_error()]
			)
		)
		return out
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		_fail("FAIL %s is not a JSON object" % TILE_METERS_JSON)
		return out
	for stem: Variant in (parsed as Dictionary).keys():
		var pair: Variant = (parsed as Dictionary)[stem]
		if pair is not Array or (pair as Array).size() != 2:
			_fail("FAIL %s: %s is not a [u, v] pair" % [TILE_METERS_JSON, stem])
			continue
		var arr := pair as Array
		out[String(stem)] = Vector2(float(arr[0]), float(arr[1]))
	return out


func _check_specs(authored: Dictionary[String, Vector2]) -> void:
	## Every material that samples an authored map has to use its published repeat size.
	## Roof and pantile each drive four slope variants as well as the flat block, so a
	## per-material walk is the only way to catch a variant left behind.
	var used: Dictionary[String, int] = {}
	for id in range(1, VoxelMaterial.COUNT):
		if VoxelSurfaceSpec.has_bespoke_shader(id):
			continue
		var spec := VoxelSurfaceSpec.for_id(id)
		var stem := spec.albedo_file.get_basename()
		if not authored.has(stem):
			continue
		used[stem] = int(used.get(stem, 0)) + 1
		var want: Vector2 = authored[stem]
		if spec.tile_meters.distance_to(want) > TOLERANCE:
			_fail(
				(
					"FAIL material %d (%s): tile_meters %s but %s authors its pitch for %s"
					% [id, spec.albedo_file, spec.tile_meters, TILE_METERS_JSON, want]
				)
			)
	for stem: String in authored:
		if not used.has(stem):
			_fail("FAIL %s authors %s.jpg, which no material samples" % [TILE_METERS_JSON, stem])
	if _failed:
		return
	var parts: Array[String] = []
	for stem: String in authored:
		parts.append("%s x%d @ %s m" % [stem, used[stem], authored[stem]])
	parts.sort()
	print("OK authored pitch matches tile_meters: %s" % ", ".join(parts))
