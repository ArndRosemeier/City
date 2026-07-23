## Builds mid-poly traffic cars with real glass, raked greenhouse, and -Z forward.
## Forward matches VehicleDirector (atan2(-dir.x, -dir.z)): nose points local -Z.
class_name ProceduralVehicle
extends RefCounted

const MAT_BODY := "body"
const MAT_GLASS := "glass"
const MAT_TRIM := "trim"
const MAT_LIGHT_F := "light_front"
const MAT_LIGHT_R := "light_rear"
const MAT_TIRE := "tire"
const MAT_RIM := "rim"
const MAT_ACCENT := "accent"
const MAT_CHROME := "chrome"

const WHEEL_SEGMENTS := 36


static func build(entry: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var profile_name := str(entry.get("profile", entry.get("id", "sedan")))
	var profile := _profile(profile_name)
	var paint := _resolve_paint(entry, profile, rng)
	var root := Node3D.new()
	root.name = "ProceduralCar_%s" % profile_name

	var mats := _make_materials(paint, profile)
	var cabin := _cabin_layout(profile)
	_build_lower_body(root, profile, cabin, mats)
	_build_greenhouse(root, profile, cabin, mats)
	_build_lights(root, profile, mats)
	_build_wheels(root, profile, mats)
	_build_extras(root, profile, cabin, mats, entry)

	root.set_meta("seat_offsets", _seat_offsets(profile, cabin))
	root.set_meta("body_length", float(profile["length"]))
	root.set_meta("body_width", float(profile["width"]))
	root.set_meta("body_height", float(profile["total_height"]))
	root.set_meta("glass_count", _count_named_mats(root, MAT_GLASS))
	root.set_meta("forward_axis", "-Z")
	# Match crowd pedestrians — never shrink people to fit a too-small cabin.
	root.set_meta("passenger_scale", float(profile.get("passenger_scale", 0.92)))
	return root


static func profile_seat_offsets(profile_name: String) -> Array:
	var p := _profile(profile_name)
	return _seat_offsets(p, _cabin_layout(p))


static func _profile(name: String) -> Dictionary:
	match name:
		"sedan", "taxi", "police":
			# Modern compact sedan: long hood rake, fastback rear, low greenhouse.
			return {
				"style": name,
				"length": 4.70,
				"width": 1.84,
				"lower_h": 0.48,
				"cabin_h": 0.82,
				"clearance": 0.14,
				"hood_z": 1.35,
				"cabin_z": 1.75,
				"trunk_z": 1.10,
				"cabin_inset": 0.10,
				"ws_rake": 0.95,
				"rw_rake": 0.85,
				"roof_drop": 0.16,
				"hood_nose_ratio": 0.32,
				"modern": true,
				"wheel_r": 0.34,
				"wheel_w": 0.24,
				"wheelbase": 2.75,
				"bumper": 0.13,
				"passenger_scale": 0.92,
				"total_height": 0.14 + 0.48 + 0.82,
			}
		"sedan_sports", "hatchback_sports":
			return {
				"style": "hatch",
				"length": 4.35,
				"width": 1.82,
				"lower_h": 0.44,
				"cabin_h": 0.78,
				"clearance": 0.12,
				"hood_z": 1.25,
				"cabin_z": 1.95,
				"trunk_z": 0.65,
				"cabin_inset": 0.08,
				"ws_rake": 1.10,
				"rw_rake": 1.00,
				"roof_drop": 0.22,
				"hood_nose_ratio": 0.28,
				"modern": true,
				"wheel_r": 0.34,
				"wheel_w": 0.26,
				"wheelbase": 2.55,
				"bumper": 0.11,
				"sport": true,
				"passenger_scale": 0.90,
				"total_height": 0.12 + 0.44 + 0.78,
			}
		"suv", "suv_luxury":
			# Crossover: still raked, not a brick.
			return {
				"style": "suv",
				"length": 4.80,
				"width": 1.96,
				"lower_h": 0.56,
				"cabin_h": 0.92,
				"clearance": 0.20,
				"hood_z": 1.15,
				"cabin_z": 2.30,
				"trunk_z": 0.85,
				"cabin_inset": 0.09,
				"ws_rake": 0.72,
				"rw_rake": 0.55,
				"roof_drop": 0.10,
				"hood_nose_ratio": 0.40,
				"modern": true,
				"wheel_r": 0.38,
				"wheel_w": 0.26,
				"wheelbase": 2.85,
				"bumper": 0.14,
				"rails": true,
				"passenger_scale": 0.94,
				"total_height": 0.20 + 0.56 + 0.92,
			}
		"van", "delivery":
			return {
				"style": "van",
				"length": 5.15,
				"width": 1.98,
				"lower_h": 0.68,
				"cabin_h": 1.15,
				"clearance": 0.20,
				"hood_z": 0.70,
				"cabin_z": 3.75,
				"trunk_z": 0.20,
				"cabin_inset": 0.06,
				"ws_rake": 0.32,
				"rw_rake": 0.08,
				"roof_drop": 0.0,
				"hood_nose_ratio": 0.78,
				"modern": false,
				"wheel_r": 0.36,
				"wheel_w": 0.25,
				"wheelbase": 3.15,
				"bumper": 0.15,
				"boxy": true,
				"passenger_scale": 0.95,
				"total_height": 0.20 + 0.68 + 1.15,
			}
		"truck":
			return {
				"style": "truck",
				"length": 5.45,
				"width": 2.08,
				"lower_h": 0.68,
				"cabin_h": 1.05,
				"clearance": 0.22,
				"hood_z": 1.25,
				"cabin_z": 1.50,
				"trunk_z": 2.20,
				"cabin_inset": 0.08,
				"ws_rake": 0.48,
				"rw_rake": 0.14,
				"roof_drop": 0.0,
				"hood_nose_ratio": 0.55,
				"modern": false,
				"wheel_r": 0.40,
				"wheel_w": 0.28,
				"wheelbase": 3.25,
				"bumper": 0.16,
				"flatbed": true,
				"passenger_scale": 0.94,
				"total_height": 0.22 + 0.68 + 1.05,
			}
		_:
			push_error("ProceduralVehicle: unknown profile '%s', using sedan" % name)
			return _profile("sedan")


## Cabin opening in vehicle space. Nose / windshield toward -Z.
static func _cabin_layout(p: Dictionary) -> Dictionary:
	var length: float = p["length"]
	var lower_h: float = p["lower_h"]
	var cabin_h: float = p["cabin_h"]
	var clearance: float = p["clearance"]
	var hood_z: float = p["hood_z"]
	var cabin_z: float = p["cabin_z"]
	var trunk_z: float = p["trunk_z"]
	var bumper: float = p["bumper"]
	var ws_rake: float = p["ws_rake"]
	var rw_rake: float = p["rw_rake"]
	var roof_drop: float = float(p.get("roof_drop", 0.0))
	var width: float = p["width"]
	var inset: float = p["cabin_inset"]

	var z_nose := -length * 0.5
	var z_tail := length * 0.5
	# Belt front = rear edge of hood (still toward nose from cabin).
	var z_belt_f := z_nose + bumper + hood_z
	var z_belt_r := z_belt_f + cabin_z
	z_belt_r = minf(z_belt_r, z_tail - bumper - maxf(trunk_z * 0.3, 0.12))
	var y_belt := clearance + lower_h
	var y_roof_f := y_belt + cabin_h
	var y_roof_r := y_roof_f - roof_drop
	# Roof starts behind windshield rake, ends before rear-window rake.
	var z_roof_f := z_belt_f + ws_rake
	var z_roof_r := z_belt_r - rw_rake
	if z_roof_r <= z_roof_f + 0.35:
		z_roof_r = z_roof_f + 0.35
		z_belt_r = z_roof_r + rw_rake

	var cabin_w := width - inset * 2.0
	var pillar := 0.07
	return {
		"z_nose": z_nose,
		"z_tail": z_tail,
		"z_belt_f": z_belt_f,
		"z_belt_r": z_belt_r,
		"z_roof_f": z_roof_f,
		"z_roof_r": z_roof_r,
		"y_belt": y_belt,
		"y_roof": y_roof_f,
		"y_roof_f": y_roof_f,
		"y_roof_r": y_roof_r,
		"cabin_w": cabin_w,
		"pillar": pillar,
		"glass_inset": 0.016,
		"clearance": clearance,
		"passenger_scale": float(p.get("passenger_scale", 0.92)),
	}


static func _resolve_paint(entry: Dictionary, profile: Dictionary, rng: RandomNumberGenerator) -> Color:
	var id := str(entry.get("id", ""))
	if id == "taxi":
		return Color(0.92, 0.78, 0.12)
	if id == "police":
		return Color(0.92, 0.93, 0.95)
	if entry.has("paint") and entry["paint"] != null:
		var pv: Variant = entry["paint"]
		if typeof(pv) == TYPE_ARRAY and (pv as Array).size() >= 3:
			var a: Array = pv
			return Color(float(a[0]), float(a[1]), float(a[2]))
	var hue := rng.randf()
	if hue > 0.28 and hue < 0.42:
		hue = rng.randf()
	var sat := rng.randf_range(0.42, 0.78)
	var val := rng.randf_range(0.48, 0.92)
	if bool(profile.get("sport", false)):
		sat = rng.randf_range(0.55, 0.9)
		val = rng.randf_range(0.4, 0.85)
	return Color.from_hsv(hue, sat, val)


static func _make_materials(paint: Color, profile: Dictionary) -> Dictionary:
	var body := _std(MAT_BODY, paint, 0.38, 0.18)
	var glass := _std(MAT_GLASS, Color(0.35, 0.52, 0.64, 0.32), 0.05, 0.08)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var trim := _std(MAT_TRIM, Color(0.10, 0.10, 0.11), 0.6, 0.25)
	var chrome := _std(MAT_CHROME, Color(0.78, 0.80, 0.84), 0.22, 0.85)
	var lf := _std(MAT_LIGHT_F, Color(0.95, 0.94, 0.82), 0.15, 0.05)
	lf.emission_enabled = true
	lf.emission = Color(0.9, 0.88, 0.7)
	lf.emission_energy_multiplier = 0.7
	var lr := _std(MAT_LIGHT_R, Color(0.78, 0.10, 0.08), 0.28, 0.05)
	lr.emission_enabled = true
	lr.emission = Color(0.75, 0.08, 0.05)
	lr.emission_energy_multiplier = 0.55
	var tire := _std(MAT_TIRE, Color(0.07, 0.07, 0.08), 0.9, 0.0)
	var rim := _std(MAT_RIM, Color(0.70, 0.72, 0.76), 0.3, 0.65)
	var accent := paint
	if str(profile.get("style", "")) == "police":
		accent = Color(0.12, 0.28, 0.72)
	elif str(profile.get("style", "")) == "taxi":
		accent = Color(0.14, 0.14, 0.15)
	return {
		MAT_BODY: body,
		MAT_GLASS: glass,
		MAT_TRIM: trim,
		MAT_CHROME: chrome,
		MAT_LIGHT_F: lf,
		MAT_LIGHT_R: lr,
		MAT_TIRE: tire,
		MAT_RIM: rim,
		MAT_ACCENT: _std(MAT_ACCENT, accent, 0.42, 0.1),
	}


static func _std(mat_name: String, color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	return m


static func _build_lower_body(root: Node3D, p: Dictionary, cabin: Dictionary, mats: Dictionary) -> void:
	## Hollow cabin: solid bulk only under hood/trunk + thin side sills.
	## A full-length lower box buried passengers (only heads stuck out of the belt).
	var length: float = p["length"]
	var width: float = p["width"]
	var lower_h: float = p["lower_h"]
	var clearance: float = p["clearance"]
	var hood_z: float = p["hood_z"]
	var trunk_z: float = p["trunk_z"]
	var bumper: float = p["bumper"]
	var z_nose := -length * 0.5
	var z_tail := length * 0.5
	var z_bf: float = cabin["z_belt_f"]
	var z_br: float = cabin["z_belt_r"]
	var y0 := clearance

	# Front bulkhead / nose volume (hood bay) — stops at cabin front.
	var front_len := maxf(z_bf - (z_nose + bumper), 0.4)
	_box(
		root, "FrontBulk",
		Vector3(width, lower_h, front_len),
		Vector3(0.0, y0 + lower_h * 0.5, z_nose + bumper + front_len * 0.5),
		mats[MAT_BODY]
	)

	# Rear bulk / trunk volume — starts at cabin rear (skip for long vans that are all cabin).
	var rear_start := z_br
	var rear_end := z_tail - bumper
	var rear_len := rear_end - rear_start
	if rear_len > 0.25 and not bool(p.get("boxy", false)):
		_box(
			root, "RearBulk",
			Vector3(width, lower_h, rear_len),
			Vector3(0.0, y0 + lower_h * 0.5, rear_start + rear_len * 0.5),
			mats[MAT_BODY]
		)
	elif bool(p.get("boxy", false)) and rear_len > 0.1:
		# Van: thin rear panel only.
		_box(
			root, "RearPanel",
			Vector3(width, lower_h, minf(rear_len, 0.2)),
			Vector3(0.0, y0 + lower_h * 0.5, rear_end - 0.1),
			mats[MAT_BODY]
		)

	# Side sills + door skins along cabin (thin — leave interior hollow).
	var cabin_len := maxf(z_br - z_bf, 0.5)
	var sill_h := lower_h * 0.28
	var door_h := lower_h * 0.92
	var sides: Array[float] = [-1.0, 1.0]
	for side in sides:
		_box(
			root, "Sill_%d" % int(side),
			Vector3(0.08, sill_h, cabin_len * 0.98),
			Vector3(side * (width * 0.5 - 0.04), y0 + sill_h * 0.5, (z_bf + z_br) * 0.5),
			mats[MAT_TRIM]
		)
		_box(
			root, "DoorSkin_%d" % int(side),
			Vector3(0.045, door_h, cabin_len * 0.96),
			Vector3(side * (width * 0.5 - 0.02), y0 + door_h * 0.5, (z_bf + z_br) * 0.5),
			mats[MAT_BODY]
		)

	# Firewall between hood bay and cabin.
	_box(
		root, "Firewall",
		Vector3(width * 0.92, lower_h * 0.95, 0.06),
		Vector3(0.0, y0 + lower_h * 0.48, z_bf - 0.03),
		mats[MAT_TRIM]
	)

	# Hood wedge: aggressive nose drop on modern cars.
	var hood_rear_h := lower_h * 1.02
	var nose_ratio: float = float(p.get("hood_nose_ratio", 0.62))
	var hood_front_h := lower_h * nose_ratio
	var hood_z0 := z_nose + bumper
	var hood_z1 := hood_z0 + hood_z
	_wedge_z(
		root, "Hood",
		width * 0.96,
		hood_z0, hood_front_h,
		hood_z1, hood_rear_h,
		y0, mats[MAT_BODY]
	)

	# Soft nose / front fascia slope above bumper (modern cars).
	if bool(p.get("modern", false)):
		_wedge_z(
			root, "Nose",
			width * 0.88,
			z_nose + bumper * 0.2, lower_h * 0.18,
			hood_z0 + hood_z * 0.15, lower_h * 0.55,
			y0, mats[MAT_BODY]
		)

	if not bool(p.get("flatbed", false)) and trunk_z > 0.35:
		if bool(p.get("modern", false)):
			var deck_z0 := z_tail - bumper - trunk_z
			var deck_z1 := z_tail - bumper
			_wedge_z(
				root, "Trunk",
				width * 0.94,
				deck_z0, lower_h * 0.95,
				deck_z1, lower_h * 0.45,
				y0, mats[MAT_BODY]
			)
		else:
			var trunk_h := lower_h * 0.82
			_box(root, "Trunk", Vector3(width * 0.96, trunk_h, trunk_z * 0.88),
				Vector3(0.0, y0 + trunk_h * 0.5 + 0.015, z_tail - bumper - trunk_z * 0.5), mats[MAT_BODY])

	# Bumpers with chrome lip
	_box(root, "BumperFront", Vector3(width * 1.03, lower_h * 0.36, bumper),
		Vector3(0.0, y0 + lower_h * 0.26, z_nose + bumper * 0.5), mats[MAT_TRIM])
	_box(root, "BumperFrontLip", Vector3(width * 0.55, 0.04, 0.05),
		Vector3(0.0, y0 + lower_h * 0.42, z_nose + bumper + 0.01), mats[MAT_CHROME])
	_box(root, "BumperRear", Vector3(width * 1.03, lower_h * 0.36, bumper),
		Vector3(0.0, y0 + lower_h * 0.26, z_tail - bumper * 0.5), mats[MAT_TRIM])

	_box(root, "Undertray", Vector3(width * 0.82, 0.035, length * 0.72),
		Vector3(0.0, clearance * 0.4, 0.0), mats[MAT_TRIM])

	# Wheel-arch lips
	var wb: float = p["wheel_r"]
	var wheelbase: float = p["wheelbase"]
	var z_signs: Array[float] = [-1.0, 1.0]
	for side in sides:
		for zs in z_signs:
			_box(root, "Arch_%d_%d" % [int(side), int(zs)],
				Vector3(0.07, lower_h * 0.5, wb * 1.7),
				Vector3(side * (width * 0.5 - 0.03), y0 + lower_h * 0.42, zs * wheelbase * 0.5),
				mats[MAT_TRIM])


static func _build_greenhouse(root: Node3D, p: Dictionary, c: Dictionary, mats: Dictionary) -> void:
	var cabin_w: float = c["cabin_w"]
	var pillar: float = c["pillar"]
	var inset: float = c["glass_inset"]
	var y_belt: float = c["y_belt"]
	var y_rf: float = c["y_roof_f"]
	var y_rr: float = c["y_roof_r"]
	var z_bf: float = c["z_belt_f"]
	var z_br: float = c["z_belt_r"]
	var z_rf: float = c["z_roof_f"]
	var z_rr: float = c["z_roof_r"]
	var clearance: float = c["clearance"]
	var roof_h := 0.055
	var half_w := cabin_w * 0.5
	var glass_half := half_w - pillar - inset

	# Roof panel — supports fastback drop (front roof higher than rear).
	var hw := cabin_w * 0.49
	var roof_verts := PackedVector3Array([
		Vector3(-hw, y_rf - roof_h, z_rf), Vector3(hw, y_rf - roof_h, z_rf),
		Vector3(hw, y_rf, z_rf), Vector3(-hw, y_rf, z_rf),
		Vector3(-hw, y_rr - roof_h, z_rr), Vector3(hw, y_rr - roof_h, z_rr),
		Vector3(hw, y_rr, z_rr), Vector3(-hw, y_rr, z_rr),
	])
	var roof_faces := [
		[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0],
	]
	_mesh_from_faces(root, "Roof", roof_verts, roof_faces, mats[MAT_BODY])

	# Belt / sill
	_box(root, "Belt", Vector3(cabin_w, 0.05, maxf(z_br - z_bf, 0.4)),
		Vector3(0.0, y_belt + 0.02, (z_bf + z_br) * 0.5), mats[MAT_BODY])

	# A/C pillars follow glass rake to the (possibly dropping) roof line.
	var sides: Array[float] = [-1.0, 1.0]
	for side in sides:
		var x: float = side * (half_w - pillar * 0.45)
		_pillar_rake(root, "PillarA_%d" % int(side), x, pillar,
			z_bf, y_belt, z_rf, y_rf - roof_h * 0.15, mats[MAT_BODY])
		_pillar_rake(root, "PillarC_%d" % int(side), x, pillar,
			z_br, y_belt, z_rr, y_rr - roof_h * 0.15, mats[MAT_BODY])

	if z_rr - z_rf > 0.75:
		var z_mid: float = (z_rf + z_rr) * 0.5
		var y_mid: float = lerpf(y_rf, y_rr, 0.5)
		for side in sides:
			var x2: float = side * (half_w - pillar * 0.45)
			_box(root, "PillarB_%d" % int(side),
				Vector3(pillar * 0.8, maxf(y_mid - y_belt - roof_h * 0.2, 0.2), pillar),
				Vector3(x2, (y_belt + y_mid) * 0.5, z_mid), mats[MAT_BODY])

	_box(root, "HeaderFront", Vector3(cabin_w * 0.96, 0.045, 0.055),
		Vector3(0.0, y_rf - 0.035, z_rf), mats[MAT_BODY])
	_box(root, "HeaderRear", Vector3(cabin_w * 0.96, 0.045, 0.055),
		Vector3(0.0, y_rr - 0.035, z_rr), mats[MAT_BODY])

	# Windshield — deep rake into roof front.
	_glass_quad(
		root, "GlassWindshield",
		Vector3(-glass_half, y_belt + inset, z_bf + inset * 0.4),
		Vector3(glass_half, y_belt + inset, z_bf + inset * 0.4),
		Vector3(glass_half, y_rf - roof_h - inset, z_rf - inset * 0.2),
		Vector3(-glass_half, y_rf - roof_h - inset, z_rf - inset * 0.2),
		mats[MAT_GLASS]
	)
	# Rear window follows roof drop.
	_glass_quad(
		root, "GlassRear",
		Vector3(-glass_half, y_belt + inset, z_br - inset * 0.4),
		Vector3(glass_half, y_belt + inset, z_br - inset * 0.4),
		Vector3(glass_half, y_rr - roof_h - inset, z_rr + inset * 0.2),
		Vector3(-glass_half, y_rr - roof_h - inset, z_rr + inset * 0.2),
		mats[MAT_GLASS]
	)

	var has_b := z_rr - z_rf > 0.75
	var z_mid2: float = (z_rf + z_rr) * 0.5
	var y_mid2: float = lerpf(y_rf, y_rr, 0.5)
	for side in sides:
		var x_out: float = side * (half_w - inset)
		if has_b:
			_glass_quad(
				root, "GlassSideFront_%d" % int(side),
				Vector3(x_out, y_belt + inset * 2.0, z_bf + pillar + inset),
				Vector3(x_out, y_belt + inset * 2.0, z_mid2 - pillar - inset),
				Vector3(x_out, y_mid2 - roof_h - inset, z_mid2 - pillar - inset),
				Vector3(x_out, y_rf - roof_h - inset, z_rf + pillar + inset),
				mats[MAT_GLASS]
			)
			_glass_quad(
				root, "GlassSideRear_%d" % int(side),
				Vector3(x_out, y_belt + inset * 2.0, z_mid2 + pillar + inset),
				Vector3(x_out, y_belt + inset * 2.0, z_br - pillar - inset),
				Vector3(x_out, y_rr - roof_h - inset, z_rr - pillar - inset),
				Vector3(x_out, y_mid2 - roof_h - inset, z_mid2 + pillar + inset),
				mats[MAT_GLASS]
			)
		else:
			_glass_quad(
				root, "GlassSide_%d" % int(side),
				Vector3(x_out, y_belt + inset * 2.0, z_bf + pillar + inset),
				Vector3(x_out, y_belt + inset * 2.0, z_br - pillar - inset),
				Vector3(x_out, y_rr - roof_h - inset, z_rr - pillar - inset),
				Vector3(x_out, y_rf - roof_h - inset, z_rf + pillar + inset),
				mats[MAT_GLASS]
			)

	# Cabin floor + seats inside the hollow cabin volume.
	var floor_y: float = clearance + 0.08
	_box(root, "CabinFloor",
		Vector3(cabin_w * 0.72, 0.03, maxf(z_br - z_bf, 0.5) * 0.70),
		Vector3(0.0, floor_y, (z_bf + z_br) * 0.5),
		mats[MAT_TRIM])
	var seat_w := cabin_w * 0.28
	var seat_z := z_bf + (z_br - z_bf) * 0.36
	# Cushion near real hip height; passenger root stays on the floor.
	var seat_top := floor_y + 0.38
	_box(root, "SeatL", Vector3(seat_w, 0.10, 0.42),
		Vector3(-cabin_w * 0.20, seat_top, seat_z), mats[MAT_TRIM])
	_box(root, "SeatR", Vector3(seat_w, 0.10, 0.42),
		Vector3(cabin_w * 0.20, seat_top, seat_z), mats[MAT_TRIM])
	_box(root, "SeatBackL", Vector3(seat_w * 0.9, 0.45, 0.07),
		Vector3(-cabin_w * 0.20, seat_top + 0.22, seat_z + 0.18), mats[MAT_TRIM])
	_box(root, "SeatBackR", Vector3(seat_w * 0.9, 0.45, 0.07),
		Vector3(cabin_w * 0.20, seat_top + 0.22, seat_z + 0.18), mats[MAT_TRIM])
	# Dash on the belt / firewall.
	_box(root, "Dash", Vector3(cabin_w * 0.82, 0.14, 0.20),
		Vector3(0.0, y_belt + 0.05, z_bf + 0.12), mats[MAT_TRIM])



static func _build_lights(root: Node3D, p: Dictionary, mats: Dictionary) -> void:
	var length: float = p["length"]
	var width: float = p["width"]
	var lower_h: float = p["lower_h"]
	var clearance: float = p["clearance"]
	var bumper: float = p["bumper"]
	var z_nose := -length * 0.5
	var z_tail := length * 0.5
	var y := clearance + lower_h * 0.55
	var housing_d := 0.08
	var lens_d := 0.035

	# Headlight housings + lenses (left/right), with chrome surround
	var light_sides: Array[float] = [-1.0, 1.0]
	for side in light_sides:
		var x: float = side * width * 0.33
		_box(root, "HL_Housing_%d" % int(side),
			Vector3(width * 0.26, lower_h * 0.34, housing_d),
			Vector3(x, y, z_nose + bumper + housing_d * 0.45), mats[MAT_TRIM])
		_box(root, "HL_Chrome_%d" % int(side),
			Vector3(width * 0.24, lower_h * 0.30, 0.02),
			Vector3(x, y, z_nose + bumper + housing_d * 0.15), mats[MAT_CHROME])
		_box(root, "HL_Lens_%d" % int(side),
			Vector3(width * 0.20, lower_h * 0.24, lens_d),
			Vector3(x, y, z_nose + bumper + 0.01), mats[MAT_LIGHT_F])
		# Inner projector circle proxy
		_cyl(root, "HL_Projector_%d" % int(side), lower_h * 0.08, lens_d * 0.8,
			Vector3(x, y, z_nose + bumper - 0.005), mats[MAT_LIGHT_F], 16)

		_box(root, "TL_Housing_%d" % int(side),
			Vector3(width * 0.24, lower_h * 0.30, housing_d),
			Vector3(x * 1.02, y, z_tail - bumper - housing_d * 0.45), mats[MAT_TRIM])
		_box(root, "TL_Lens_%d" % int(side),
			Vector3(width * 0.18, lower_h * 0.22, lens_d),
			Vector3(x * 1.02, y, z_tail - bumper - 0.01), mats[MAT_LIGHT_R])

	# Center grille with chrome bars
	_box(root, "GrillFrame", Vector3(width * 0.40, lower_h * 0.28, 0.05),
		Vector3(0.0, clearance + lower_h * 0.48, z_nose + bumper + 0.04), mats[MAT_TRIM])
	for i in range(3):
		var gy: float = clearance + lower_h * 0.38 + float(i) * lower_h * 0.08
		_box(root, "GrillBar_%d" % i, Vector3(width * 0.34, 0.015, 0.02),
			Vector3(0.0, gy, z_nose + bumper + 0.06), mats[MAT_CHROME])


static func _build_wheels(root: Node3D, p: Dictionary, mats: Dictionary) -> void:
	var width: float = p["width"]
	var wheel_r: float = p["wheel_r"]
	var wheel_w: float = p["wheel_w"]
	var wb: float = p["wheelbase"]
	var y := wheel_r
	var sides: Array[float] = [-1.0, 1.0]
	var z_signs: Array[float] = [-1.0, 1.0]
	for side in sides:
		for zs in z_signs:
			var wx: float = side * (width * 0.5 - wheel_w * 0.4)
			var wz: float = zs * wb * 0.5
			var tire := _cyl(root, "Tire_%d_%d" % [int(side), int(zs)],
				wheel_r, wheel_w, Vector3(wx, y, wz), mats[MAT_TIRE], WHEEL_SEGMENTS)
			tire.rotation.z = PI * 0.5
			# Rim barrel
			var rim := _cyl(root, "Rim_%d_%d" % [int(side), int(zs)],
				wheel_r * 0.62, wheel_w * 0.55, Vector3(wx, y, wz), mats[MAT_RIM], WHEEL_SEGMENTS)
			rim.rotation.z = PI * 0.5
			# Hub
			var hub := _cyl(root, "Hub_%d_%d" % [int(side), int(zs)],
				wheel_r * 0.18, wheel_w * 0.35, Vector3(wx, y, wz), mats[MAT_CHROME], 16)
			hub.rotation.z = PI * 0.5
			# Five spokes in the wheel plane
			for s_i in range(5):
				var ang: float = float(s_i) * TAU / 5.0
				var spoke := _box(root, "Spoke_%d_%d_%d" % [int(side), int(zs), s_i],
					Vector3(wheel_w * 0.14, wheel_r * 0.40, wheel_r * 0.07),
					Vector3(
						wx,
						y + cos(ang) * wheel_r * 0.30,
						wz + sin(ang) * wheel_r * 0.30
					),
					mats[MAT_RIM]
				)
				spoke.rotation.x = ang


static func _build_extras(
	root: Node3D, p: Dictionary, c: Dictionary, mats: Dictionary, entry: Dictionary
) -> void:
	var id := str(entry.get("id", ""))
	var width: float = p["width"]
	var length: float = p["length"]
	var lower_h: float = p["lower_h"]
	var clearance: float = p["clearance"]
	var bumper: float = p["bumper"]
	var y_roof: float = c["y_roof"]
	var z_bf: float = c["z_belt_f"]
	var z_br: float = c["z_belt_r"]
	var z_rf: float = c["z_roof_f"]
	var z_rr: float = c["z_roof_r"]
	var cabin_w: float = c["cabin_w"]
	var z_nose: float = c["z_nose"]
	var z_tail: float = c["z_tail"]

	# Mirrors near A-pillar
	var sides: Array[float] = [-1.0, 1.0]
	for side in sides:
		_box(root, "MirrorArm_%d" % int(side), Vector3(0.08, 0.04, 0.12),
			Vector3(side * (width * 0.5 + 0.02), c["y_belt"] + (y_roof - c["y_belt"]) * 0.45, z_bf + 0.05),
			mats[MAT_TRIM])
		_box(root, "MirrorGlass_%d" % int(side), Vector3(0.16, 0.10, 0.04),
			Vector3(side * (width * 0.5 + 0.12), c["y_belt"] + (y_roof - c["y_belt"]) * 0.45, z_bf + 0.02),
			mats[MAT_CHROME])

	if bool(p.get("rails", false)):
		for side in sides:
			_box(root, "Rail_%d" % int(side), Vector3(0.045, 0.035, (z_br - z_bf) * 0.7),
				Vector3(side * cabin_w * 0.28, y_roof + 0.025, (z_rf + z_br) * 0.5), mats[MAT_TRIM])

	if id == "taxi":
		_box(root, "TaxiSign", Vector3(0.5, 0.16, 0.24),
			Vector3(0.0, y_roof + 0.12, (z_rf + z_br) * 0.4), mats[MAT_ACCENT])

	if id == "police":
		_box(root, "LightBar", Vector3(width * 0.55, 0.11, 0.3),
			Vector3(0.0, y_roof + 0.09, (z_rf + z_br) * 0.42), mats[MAT_ACCENT])
		for side in sides:
			_box(root, "Stripe_%d" % int(side), Vector3(0.03, lower_h * 0.32, length * 0.42),
				Vector3(side * (width * 0.5 + 0.01), clearance + lower_h * 0.55, 0.0), mats[MAT_ACCENT])

	if bool(p.get("flatbed", false)):
		var bed_len := z_tail - bumper - z_br
		_box(root, "Flatbed", Vector3(width * 0.95, 0.08, bed_len),
			Vector3(0.0, clearance + lower_h + 0.04, z_br + bed_len * 0.5), mats[MAT_TRIM])
		for side in sides:
			_box(root, "BedRail_%d" % int(side), Vector3(0.05, 0.38, bed_len * 0.95),
				Vector3(side * width * 0.45, clearance + lower_h + 0.26, z_br + bed_len * 0.5), mats[MAT_TRIM])

	if bool(p.get("sport", false)):
		_box(root, "Spoiler", Vector3(width * 0.72, 0.045, 0.2),
			Vector3(0.0, y_roof + 0.02, z_br - 0.05), mats[MAT_BODY])
		_box(root, "SpoilerStalkL", Vector3(0.04, 0.12, 0.04),
			Vector3(-width * 0.25, y_roof - 0.02, z_br), mats[MAT_TRIM])
		_box(root, "SpoilerStalkR", Vector3(0.04, 0.12, 0.04),
			Vector3(width * 0.25, y_roof - 0.02, z_br), mats[MAT_TRIM])

	# Antenna on roof
	_box(root, "Antenna", Vector3(0.015, 0.32, 0.015),
		Vector3(cabin_w * 0.15, y_roof + 0.16, z_rr - 0.1), mats[MAT_TRIM])


static func _seat_offsets(p: Dictionary, c: Dictionary) -> Array:
	var width: float = p["width"]
	var clearance: float = float(c.get("clearance", p["clearance"]))
	var z_bf: float = c["z_belt_f"]
	var z_br: float = c["z_belt_r"]
	# Full-size humans: feet on cabin floor. Cabin is hollow so bodies fit under the roof.
	var seat_y := clearance + 0.08
	var seat_z := z_bf + (z_br - z_bf) * 0.36
	var half_w := width * 0.18
	var seats: Array = [
		{"x": -half_w, "y": seat_y, "z": seat_z},
		{"x": half_w, "y": seat_y, "z": seat_z},
	]
	if str(p.get("style", "")) == "van" or float(p["cabin_z"]) > 2.8:
		seats.append({"x": -half_w, "y": seat_y, "z": seat_z + 0.9})
		seats.append({"x": half_w, "y": seat_y, "z": seat_z + 0.9})
	return seats


# --- Mesh helpers ---

static func _box(
	parent: Node3D, node_name: String, size: Vector3, pos: Vector3, mat: Material
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


static func _cyl(
	parent: Node3D,
	node_name: String,
	radius: float,
	depth: float,
	pos: Vector3,
	mat: Material,
	segments: int
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = depth
	mesh.radial_segments = segments
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


## Wedge along Z: height at z0 / z1, bottom at y_bottom.
static func _wedge_z(
	parent: Node3D,
	node_name: String,
	width: float,
	z0: float,
	h0: float,
	z1: float,
	h1: float,
	y_bottom: float,
	mat: Material
) -> MeshInstance3D:
	var hw := width * 0.5
	var y00 := y_bottom
	var y01 := y_bottom + h0
	var y10 := y_bottom
	var y11 := y_bottom + h1
	# 8 corners of a tapered box
	var verts := PackedVector3Array([
		Vector3(-hw, y00, z0), Vector3(hw, y00, z0), Vector3(hw, y01, z0), Vector3(-hw, y01, z0),
		Vector3(-hw, y10, z1), Vector3(hw, y10, z1), Vector3(hw, y11, z1), Vector3(-hw, y11, z1),
	])
	var faces := [
		[0, 1, 2, 3], # z0
		[5, 4, 7, 6], # z1
		[4, 0, 3, 7], # -X
		[1, 5, 6, 2], # +X
		[3, 2, 6, 7], # top
		[4, 5, 1, 0], # bottom
	]
	return _mesh_from_faces(parent, node_name, verts, faces, mat)


static func _pillar_rake(
	parent: Node3D,
	node_name: String,
	x: float,
	thickness: float,
	z_bot: float,
	y_bot: float,
	z_top: float,
	y_top: float,
	mat: Material
) -> MeshInstance3D:
	var ht := thickness * 0.5
	var zt := thickness * 0.45
	var verts := PackedVector3Array([
		Vector3(x - ht, y_bot, z_bot - zt),
		Vector3(x + ht, y_bot, z_bot - zt),
		Vector3(x + ht, y_bot, z_bot + zt),
		Vector3(x - ht, y_bot, z_bot + zt),
		Vector3(x - ht, y_top, z_top - zt),
		Vector3(x + ht, y_top, z_top - zt),
		Vector3(x + ht, y_top, z_top + zt),
		Vector3(x - ht, y_top, z_top + zt),
	])
	var faces := [
		[0, 1, 2, 3],
		[5, 4, 7, 6],
		[4, 0, 3, 7],
		[1, 5, 6, 2],
		[3, 2, 6, 7],
		[4, 5, 1, 0],
	]
	return _mesh_from_faces(parent, node_name, verts, faces, mat)


static func _glass_quad(
	parent: Node3D,
	node_name: String,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	mat: Material
) -> MeshInstance3D:
	# Two-sided quad (front + back) so alpha glass reads from both sides.
	var verts := PackedVector3Array([a, b, c, d])
	var faces := [[0, 1, 2, 3], [0, 3, 2, 1]]
	return _mesh_from_faces(parent, node_name, verts, faces, mat)


static func _mesh_from_faces(
	parent: Node3D,
	node_name: String,
	corners: PackedVector3Array,
	faces: Array,
	mat: Material
) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face: Variant in faces:
		var idx: Array = face
		var i0: int = idx[0]
		var i1: int = idx[1]
		var i2: int = idx[2]
		var i3: int = idx[3]
		var n := (corners[i2] - corners[i0]).cross(corners[i1] - corners[i0]).normalized()
		if n.length_squared() < 0.0001:
			n = Vector3.UP
		st.set_normal(n)
		st.add_vertex(corners[i0])
		st.set_normal(n)
		st.add_vertex(corners[i1])
		st.set_normal(n)
		st.add_vertex(corners[i2])
		st.set_normal(n)
		st.add_vertex(corners[i0])
		st.set_normal(n)
		st.add_vertex(corners[i2])
		st.set_normal(n)
		st.add_vertex(corners[i3])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


static func _count_named_mats(root: Node3D, mat_name: String) -> int:
	var n := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null:
			continue
		var mat := mi.material_override
		if mat != null and String(mat.resource_name).to_lower() == mat_name:
			n += 1
	return n
