## Headless: load each catalog vehicle and assert real alpha glass on procedural kits.
extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	VehicleCatalog.reload()
	if not VehicleCatalog.is_ready():
		push_error("FAIL vehicle catalog not ready")
		quit(1)
		return

	var failures := 0
	var n := VehicleCatalog.count()
	for i in range(n):
		var entry: Dictionary = VehicleCatalog.entry_at(i)
		var id := str(entry.get("id", "?"))
		var source := str(entry.get("source", ""))
		var visual := VehicleVisual.new()
		get_root().add_child(visual)
		visual.setup(entry, 1, 7)
		await process_frame
		if not visual.ready_visual:
			push_error("FAIL visual not ready id=%s" % id)
			failures += 1
		elif source == "procedural" and visual.glass_material_count <= 0:
			push_error("FAIL no glass materials id=%s" % id)
			failures += 1
		elif source == "procedural":
			var found_named_glass := false
			for node in visual.find_children("*", "MeshInstance3D", true, false):
				var mi := node as MeshInstance3D
				if mi == null:
					continue
				var mat := mi.material_override
				if mat == null:
					continue
				var mname := String(mat.resource_name).to_lower()
				if mname == "glass" and mat is StandardMaterial3D:
					var sm := mat as StandardMaterial3D
					if sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
						found_named_glass = true
			if not found_named_glass:
				push_error("FAIL glass material not alpha-transparent id=%s" % id)
				failures += 1
			else:
				print("OK id=%s source=%s glass_surfaces=%d" % [id, source, visual.glass_material_count])
		else:
			print("OK id=%s source=%s (kenney/fallback)" % [id, source])
		visual.queue_free()
		await process_frame

	if failures > 0:
		push_error("FAIL vehicle_glass_smoke failures=%d" % failures)
		quit(1)
		return
	print("OK vehicle_glass_smoke count=%d" % n)
	quit(0)
