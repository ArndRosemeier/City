## Measures where a pedestrian outfit's first-load cost goes: texture decode vs mesh/scene.
## Run: Godot --headless --path . --script tools/bench_ped_outfit_load.gd
## Textures are loaded before the scene so the scene timing excludes them; a second load of
## the same scene is timed too, to show what the resource cache saves.
extends SceneTree

const OUTFIT_DIR := "res://assets/humans/outfits"


func _initialize() -> void:
	var dir := DirAccess.open(OUTFIT_DIR)
	if dir == null:
		push_error("bench: cannot open %s" % OUTFIT_DIR)
		quit(1)
		return
	var outfits: PackedStringArray = PackedStringArray()
	for file in dir.get_files():
		if file.ends_with(".glb"):
			outfits.append(file)
	outfits.sort()
	if outfits.is_empty():
		push_error("bench: no .glb found in %s" % OUTFIT_DIR)
		quit(1)
		return

	var all_files: PackedStringArray = dir.get_files()
	var total_tex_ms := 0.0
	var total_scene_ms := 0.0
	var total_tex_bytes := 0
	print("--- per outfit ---")
	for outfit in outfits:
		var base := outfit.trim_suffix(".glb")
		var tex_ms := 0.0
		var tex_parts: PackedStringArray = PackedStringArray()
		var tex_bytes := 0
		for file in all_files:
			if not file.ends_with(".png") or not file.begins_with(base + "_"):
				continue
			var path := "%s/%s" % [OUTFIT_DIR, file]
			var t0 := Time.get_ticks_usec()
			var tex := load(path) as Texture2D
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0
			if tex == null:
				push_error("bench: %s did not load as Texture2D" % path)
				quit(1)
				return
			tex_ms += ms
			var image := tex.get_image()
			tex_bytes += image.get_data().size()
			tex_parts.append(
				"%dx%d %s %.0fms"
				% [tex.get_width(), tex.get_height(), _format_name(image), ms]
			)

		var t1 := Time.get_ticks_usec()
		var packed := load("%s/%s" % [OUTFIT_DIR, outfit]) as PackedScene
		var scene_ms := float(Time.get_ticks_usec() - t1) / 1000.0
		if packed == null:
			push_error("bench: %s did not load as PackedScene" % outfit)
			quit(1)
			return

		var t2 := Time.get_ticks_usec()
		var inst := packed.instantiate() as Node3D
		var inst_ms := float(Time.get_ticks_usec() - t2) / 1000.0
		var verts := _count_vertices(inst)
		inst.free()

		total_tex_ms += tex_ms
		total_scene_ms += scene_ms
		total_tex_bytes += tex_bytes
		print(
			"%-24s first load %6.1f ms = textures %6.1f ms + scene %5.1f ms  |  instantiate"
			% [base, tex_ms + scene_ms, tex_ms, scene_ms]
			+ " %4.1f ms · %d verts · %.1f MB decoded" % [inst_ms, verts, float(tex_bytes) / 1048576.0]
		)
		print("    textures: " + ", ".join(tex_parts))

	print("--- cached reload (resource cache hit) ---")
	for outfit in outfits:
		var path := "%s/%s" % [OUTFIT_DIR, outfit]
		var t0 := Time.get_ticks_usec()
		var packed := load(path) as PackedScene
		var ms := float(Time.get_ticks_usec() - t0) / 1000.0
		if packed == null:
			push_error("bench: reload failed for %s" % path)
			quit(1)
			return
		print("%-24s reload %.2f ms" % [outfit.trim_suffix(".glb"), ms])

	print(
		"--- totals: %d outfits · first load %.0f ms (textures %.0f ms = %d%%) · %.0f MB decoded ---"
		% [
			outfits.size(),
			total_tex_ms + total_scene_ms,
			total_tex_ms,
			int(round(100.0 * total_tex_ms / maxf(total_tex_ms + total_scene_ms, 0.001))),
			float(total_tex_bytes) / 1048576.0,
		]
	)
	quit(0)


func _count_vertices(root: Node) -> int:
	var total := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return total


## Image.FORMAT_* has no built-in name lookup; only the formats these assets can hit.
func _format_name(image: Image) -> String:
	match image.get_format():
		Image.FORMAT_RGBA8:
			return "RGBA8(uncompressed)"
		Image.FORMAT_RGB8:
			return "RGB8(uncompressed)"
		Image.FORMAT_DXT1:
			return "DXT1"
		Image.FORMAT_DXT5:
			return "DXT5"
		Image.FORMAT_BPTC_RGBA:
			return "BPTC"
		_:
			return "format%d" % image.get_format()
