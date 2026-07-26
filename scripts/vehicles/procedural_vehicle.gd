## Builds chunky, stylised traffic cars to match the voxel city: a handful of large
## flat-shaded volumes instead of a pile of small boxes, real wheel arches cut into the
## flanks, and a cabin tall enough that full-height passengers fit under the roof.
##
## The hull is one lofted volume driven by two piecewise-linear profile lines (top line
## and plan line) plus an elliptical arch cut in the underside. Van cargo boxes and
## pickup beds are just different top lines, not extra part types.
##
## Forward matches VehicleDirector (atan2(-dir.x, -dir.z)): nose points local -Z,
## so local +X is the car's right-hand side.
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

## Passenger rig metrics, measured by tools/measure_passenger_seat.gd against the
## Driving clip. Cabin heights are derived from these, so the roof can never drift out
## of sync with the people sitting under it.
##
## Matches the smallest crowd pedestrian (CrowdDirector spawns 0.92..1.08) — passengers
## are never shrunk below that just to fit a car.
const PASSENGER_SCALE := 0.92
## Feet-to-skull height of the tallest seated outfit at scale 1.0.
const SEATED_HEIGHT_UNSCALED := 1.369
## Air above the skull so the idle sway in the Driving clip never pokes through.
const HEAD_CLEARANCE := 0.10
## Seat floor to roof underside. Every profile's roof height comes from this.
const CABIN_HEADROOM := SEATED_HEIGHT_UNSCALED * PASSENGER_SCALE + HEAD_CLEARANCE
const ROOF_THICK := 0.07

## How far surface details (lenses, bumpers, seams) stand off the panel they sit on.
## Kept tiny so nothing meaningful pokes past the declared body box, but non-zero:
## flush details z-fight with the panel, and recessed ones disappear behind it.
const PROUD := 0.006

## Clearance the arch opening leaves around the tyre, above and fore/aft. The opening
## has to clear the whole tyre (top at 2 * wheel_r) or the wheel just overlaps the flank
## instead of sitting in a hole.
const ARCH_GAP := 0.025
const ARCH_OVERHANG := 0.11
## Body left above an arch. Any less and the fender looks cut clean through.
const FENDER_MIN := 0.08
## Loft stations across each arch. More reads rounder; 8 is enough at traffic distance.
const ARCH_STATIONS := 8
const WHEEL_SEGMENTS := 20

## Rear-body shapes. The hull top line is built from these.
const DECK_TRUNK := "trunk"
const DECK_BOX := "box"
const DECK_BED := "bed"


static func build(entry: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var profile_name := str(entry.get("profile", entry.get("id", "sedan")))
	var p := _profile(profile_name)
	var lay := _layout(p)
	var livery := str(entry.get("id", ""))
	var mats := _make_materials(_resolve_paint(entry, p, rng), livery)

	var root := Node3D.new()
	root.name = "ProceduralCar_%s" % profile_name
	_build_hull(root, p, lay, mats)
	_build_greenhouse(root, p, lay, mats)
	_build_interior(root, p, lay, mats)
	_build_wheels(root, p, lay, mats)
	_build_lights(root, p, lay, mats)
	_build_trim(root, p, lay, mats)
	_build_livery(root, p, lay, mats, livery)

	root.set_meta("seat_offsets", _seat_offsets(p, lay))
	## Collision extents deliberately describe the body only. Mirrors and roof props
	## used to leak into the mesh AABB and made cars collide far wider than they look.
	root.set_meta("body_length", float(p["length"]))
	root.set_meta("body_width", float(p["width"]))
	root.set_meta("body_height", float(lay["roof_y"]))
	root.set_meta("glass_count", _count_named_mats(root, MAT_GLASS))
	root.set_meta("forward_axis", "-Z")
	root.set_meta("passenger_scale", PASSENGER_SCALE)
	return root


# --- Profiles ---

static func _profile(name: String) -> Dictionary:
	match name:
		"sedan", "taxi", "police":
			return {
				"family": "sedan",
				"length": 4.40,
				"width": 1.94,
				"clearance": 0.15,
				"wheel_r": 0.35,
				"wheel_w": 0.25,
				"wheelbase": 2.70,
				"floor_y": 0.24,
				"belt_y": 0.94,
				"hood_len": 1.28,
				"cabin_len": 1.86,
				"ws_rake": 0.44,
				"rw_rake": 0.38,
				"roof_taper": 0.86,
				"roof_drop": 0.0,
				"nose_drop": 0.24,
				"nose_crease": 0.26,
				"rear_deck": DECK_TRUNK,
				"deck_drop": 0.02,
				"tail_drop": 0.14,
				"rear_glass": true,
				"seat_columns": 2,
			}
		"sedan_sports", "hatchback_sports":
			return {
				"family": "hatch",
				"length": 4.14,
				"width": 1.90,
				"clearance": 0.13,
				"wheel_r": 0.35,
				"wheel_w": 0.27,
				"wheelbase": 2.58,
				"floor_y": 0.22,
				"belt_y": 0.90,
				"hood_len": 1.14,
				"cabin_len": 1.94,
				"ws_rake": 0.52,
				"rw_rake": 0.62,
				"roof_taper": 0.82,
				"roof_drop": 0.06,
				"nose_drop": 0.26,
				"nose_crease": 0.24,
				"rear_deck": DECK_TRUNK,
				"deck_drop": 0.04,
				"tail_drop": 0.16,
				"rear_glass": true,
				"sport": true,
				"seat_columns": 2,
			}
		"suv", "suv_luxury":
			return {
				"family": "suv",
				"length": 4.72,
				"width": 2.00,
				"clearance": 0.24,
				"wheel_r": 0.40,
				"wheel_w": 0.28,
				"wheelbase": 2.84,
				"floor_y": 0.36,
				"belt_y": 1.06,
				"hood_len": 1.15,
				"cabin_len": 2.60,
				"ws_rake": 0.40,
				"rw_rake": 0.16,
				"roof_taper": 0.90,
				"roof_drop": 0.0,
				"nose_drop": 0.24,
				"nose_crease": 0.22,
				"rear_deck": DECK_TRUNK,
				"deck_drop": 0.02,
				"tail_drop": 0.12,
				"rear_glass": true,
				"rails": true,
				"seat_columns": 2,
			}
		"van", "delivery":
			return {
				"family": "van",
				"length": 5.10,
				"width": 2.00,
				"clearance": 0.22,
				"wheel_r": 0.37,
				"wheel_w": 0.26,
				"wheelbase": 3.10,
				"floor_y": 0.34,
				"belt_y": 1.06,
				"hood_len": 0.62,
				"cabin_len": 1.70,
				"ws_rake": 0.30,
				"rw_rake": 0.06,
				"roof_taper": 0.94,
				"roof_drop": 0.0,
				"nose_drop": 0.20,
				"nose_crease": 0.20,
				"rear_deck": DECK_BOX,
				"deck_drop": 0.0,
				"tail_drop": 0.0,
				## Cargo bulkhead sits behind the cab, so there is nothing to see through.
				"rear_glass": false,
				## Cab bench seats three; VehicleDirector asks vans for up to 3 riders.
				"seat_columns": 3,
			}
		"truck":
			return {
				"family": "truck",
				"length": 5.20,
				"width": 2.06,
				"clearance": 0.26,
				"wheel_r": 0.42,
				"wheel_w": 0.30,
				"wheelbase": 3.20,
				"floor_y": 0.40,
				"belt_y": 1.14,
				"hood_len": 1.30,
				"cabin_len": 1.50,
				"ws_rake": 0.34,
				"rw_rake": 0.20,
				"roof_taper": 0.90,
				"roof_drop": 0.0,
				"nose_drop": 0.12,
				"nose_crease": 0.25,
				"rear_deck": DECK_BED,
				"deck_drop": 0.0,
				"tail_drop": 0.0,
				"bed_drop": 0.16,
				"bed_wall": 0.42,
				"rear_glass": true,
				"seat_columns": 2,
			}
		_:
			push_error("ProceduralVehicle: unknown profile '%s'" % name)
			return _profile("sedan")


## Derived geometry: every downstream builder reads this instead of recomputing.
static func _layout(p: Dictionary) -> Dictionary:
	var length: float = p["length"]
	var hw: float = float(p["width"]) * 0.5
	var clearance: float = p["clearance"]
	var floor_y: float = p["floor_y"]
	var belt_y: float = p["belt_y"]
	var z_nose := -length * 0.5
	var z_tail := length * 0.5

	if floor_y < clearance + 0.04:
		push_error(
			"ProceduralVehicle: profile '%s' seat floor %.2f is below its underbody %.2f"
			% [str(p["family"]), floor_y, clearance]
		)
	if belt_y - floor_y < 0.45:
		push_error(
			"ProceduralVehicle: profile '%s' door height %.2f leaves no room for a torso"
			% [str(p["family"]), belt_y - floor_y]
		)

	var roof_inner := floor_y + CABIN_HEADROOM
	var roof_y := roof_inner + ROOF_THICK
	var z_bf := z_nose + float(p["hood_len"])
	var z_br := z_bf + float(p["cabin_len"])
	var z_rf := z_bf + float(p["ws_rake"])
	var z_rr := z_br - float(p["rw_rake"])
	if z_rr <= z_rf + 0.30:
		push_error(
			"ProceduralVehicle: profile '%s' rakes leave a %.2f m roof — that reads as a tent"
			% [str(p["family"]), z_rr - z_rf]
		)

	var lay := {
		"z_nose": z_nose,
		"z_tail": z_tail,
		"z_belt_f": z_bf,
		"z_belt_r": z_br,
		"z_roof_f": z_rf,
		"z_roof_r": z_rr,
		"hw": hw,
		"hw_roof": hw * float(p["roof_taper"]),
		"belt_y": belt_y,
		"floor_y": floor_y,
		"roof_inner": roof_inner,
		"roof_y": roof_y,
		"roof_inner_r": roof_inner - float(p["roof_drop"]),
		"arch_y": float(p["wheel_r"]) * 2.0 + ARCH_GAP,
		"arch_half": float(p["wheel_r"]) + ARCH_OVERHANG,
	}
	lay["top_line"] = _top_line(p, lay)
	lay["plan_line"] = _plan_line(p, lay)

	var wb: float = p["wheelbase"]
	var axles: Array[float] = [-wb * 0.5, wb * 0.5]
	for axle: float in axles:
		var fender := _line_at(lay["top_line"] as Array[Vector2], axle) - float(lay["arch_y"])
		if fender < FENDER_MIN:
			push_error(
				"ProceduralVehicle: profile '%s' leaves only %.2f m of fender over the axle at z=%.2f"
				% [str(p["family"]), fender, axle]
			)
	return lay


## Side-view silhouette of the hull top, nose to tail.
static func _top_line(p: Dictionary, lay: Dictionary) -> Array[Vector2]:
	var belt_y: float = lay["belt_y"]
	var z_nose: float = lay["z_nose"]
	var z_tail: float = lay["z_tail"]
	var z_bf: float = lay["z_belt_f"]
	var z_br: float = lay["z_belt_r"]
	var nose_drop: float = p["nose_drop"]
	var line: Array[Vector2] = [
		Vector2(z_nose, belt_y - nose_drop),
		## Crease where the fascia turns into the bonnet — the one shape line up front.
		Vector2(z_nose + float(p["nose_crease"]), belt_y - nose_drop * 0.42),
		Vector2(z_bf, belt_y),
		Vector2(z_br, belt_y),
	]
	match str(p["rear_deck"]):
		DECK_TRUNK:
			line.append(Vector2(z_tail - 0.36, belt_y - float(p["deck_drop"])))
			line.append(Vector2(z_tail, belt_y - float(p["tail_drop"])))
		DECK_BOX:
			## Cargo box rises to roof height immediately behind the cab.
			line.append(Vector2(z_br + 0.10, float(lay["roof_y"])))
			line.append(Vector2(z_tail, float(lay["roof_y"])))
		DECK_BED:
			var bed_y := belt_y - float(p["bed_drop"])
			line.append(Vector2(z_br + 0.10, bed_y))
			line.append(Vector2(z_tail, bed_y))
		_:
			push_error("ProceduralVehicle: unknown rear_deck '%s'" % str(p["rear_deck"]))
	return line


## Plan-view half width. Pinched at both ends so the body is not a rectangle.
static func _plan_line(p: Dictionary, lay: Dictionary) -> Array[Vector2]:
	var hw: float = lay["hw"]
	var z_nose: float = lay["z_nose"]
	var z_tail: float = lay["z_tail"]
	return [
		Vector2(z_nose, hw * 0.88),
		Vector2(z_nose + 0.55, hw),
		Vector2(z_tail - 0.55, hw),
		Vector2(z_tail, hw * 0.91),
	]


# --- Paint ---

## Curated palette. Random HSV produced muddy pinks and browns that read as bugs;
## neutrals repeat so traffic skews grey/white the way real traffic does.
static func _palette() -> PackedColorArray:
	return PackedColorArray([
		Color(0.88, 0.89, 0.91),
		Color(0.88, 0.89, 0.91),
		Color(0.60, 0.62, 0.66),
		Color(0.60, 0.62, 0.66),
		Color(0.22, 0.23, 0.26),
		Color(0.13, 0.14, 0.16),
		Color(0.66, 0.15, 0.13),
		Color(0.14, 0.26, 0.55),
		Color(0.10, 0.42, 0.44),
		Color(0.16, 0.36, 0.23),
		Color(0.84, 0.44, 0.13),
		Color(0.80, 0.66, 0.20),
		Color(0.86, 0.83, 0.72),
		Color(0.42, 0.58, 0.72),
		Color(0.38, 0.13, 0.19),
		Color(0.45, 0.46, 0.28),
	])


static func _sport_palette() -> PackedColorArray:
	return PackedColorArray([
		Color(0.78, 0.13, 0.11),
		Color(0.90, 0.48, 0.06),
		Color(0.88, 0.76, 0.10),
		Color(0.10, 0.22, 0.60),
		Color(0.08, 0.48, 0.52),
		Color(0.10, 0.11, 0.13),
		Color(0.92, 0.93, 0.95),
	])


static func _resolve_paint(entry: Dictionary, p: Dictionary, rng: RandomNumberGenerator) -> Color:
	var id := str(entry.get("id", ""))
	if id == "taxi":
		return Color(0.93, 0.74, 0.10)
	if id == "police":
		return Color(0.91, 0.92, 0.94)
	if entry.has("paint") and entry["paint"] != null:
		var pv: Variant = entry["paint"]
		if typeof(pv) == TYPE_ARRAY and (pv as Array).size() >= 3:
			var a: Array = pv
			return Color(float(a[0]), float(a[1]), float(a[2]))
	var pool := _sport_palette() if bool(p.get("sport", false)) else _palette()
	return pool[rng.randi_range(0, pool.size() - 1)]


static func _make_materials(paint: Color, livery: String) -> Dictionary:
	## Matte-ish paint. The old kits were near-chrome and read as wet plastic.
	var body := _std(MAT_BODY, paint, 0.52, 0.06)
	var glass := _std(MAT_GLASS, Color(0.20, 0.28, 0.34, 0.44), 0.08, 0.0)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	## Single-layer greenhouse shell: both faces must draw or the far side vanishes.
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var trim := _std(MAT_TRIM, Color(0.11, 0.11, 0.13), 0.62, 0.05)
	var lf := _std(MAT_LIGHT_F, Color(0.96, 0.95, 0.84), 0.16, 0.0)
	lf.emission_enabled = true
	lf.emission = Color(0.95, 0.92, 0.74)
	lf.emission_energy_multiplier = 0.55
	var lr := _std(MAT_LIGHT_R, Color(0.74, 0.10, 0.08), 0.24, 0.0)
	lr.emission_enabled = true
	lr.emission = Color(0.78, 0.09, 0.06)
	lr.emission_energy_multiplier = 0.5
	var tire := _std(MAT_TIRE, Color(0.07, 0.07, 0.08), 0.95, 0.0)
	var rim := _std(MAT_RIM, Color(0.72, 0.74, 0.78), 0.34, 0.45)

	var accent := Color(0.14, 0.15, 0.17)
	if livery == "police":
		accent = Color(0.10, 0.26, 0.72)
	elif livery == "taxi":
		accent = Color(0.13, 0.13, 0.15)

	return {
		MAT_BODY: body,
		MAT_GLASS: glass,
		MAT_TRIM: trim,
		MAT_LIGHT_F: lf,
		MAT_LIGHT_R: lr,
		MAT_TIRE: tire,
		MAT_RIM: rim,
		MAT_ACCENT: _std(MAT_ACCENT, accent, 0.5, 0.05),
	}


static func _std(mat_name: String, color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = mat_name
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	return m


# --- Hull ---

static func _build_hull(root: Node3D, p: Dictionary, lay: Dictionary, mats: Dictionary) -> void:
	var stations := _hull_stations(p, lay)
	if stations.size() < 3:
		push_error("ProceduralVehicle: hull needs at least 3 stations, got %d" % stations.size())
		return
	## The cabin is an open channel: passengers sit down inside the hull, and the
	## greenhouse caps it. A closed deck here buried everyone below the waist.
	var hull := _loft_z(
		root, "Hull", stations, mats[MAT_BODY],
		Vector2(float(lay["z_belt_f"]), float(lay["z_belt_r"]))
	)
	## The two big volumes are the only parts that cast: everything else is detail that
	## would cost shadow draws without changing the silhouette on the road. Double-sided
	## so the open cabin channel does not punch a hole through the shadow.
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED


static func _hull_stations(p: Dictionary, lay: Dictionary) -> Array[Dictionary]:
	var top_line: Array[Vector2] = lay["top_line"]
	var plan_line: Array[Vector2] = lay["plan_line"]
	var out: Array[Dictionary] = []
	for z in _station_zs(p, lay):
		out.append({
			"z": z,
			"y0": _hull_bottom(p, lay, z),
			"y1": _line_at(top_line, z),
			"hw": _line_at(plan_line, z),
		})
	return out


## Station positions: every profile-line corner, both cabin edges, and a fan across
## each wheel arch so the opening reads as a curve instead of a notch.
static func _station_zs(p: Dictionary, lay: Dictionary) -> PackedFloat32Array:
	var z_nose: float = lay["z_nose"]
	var z_tail: float = lay["z_tail"]
	var raw := PackedFloat32Array()
	for v: Vector2 in lay["top_line"] as Array[Vector2]:
		raw.append(v.x)
	for v: Vector2 in lay["plan_line"] as Array[Vector2]:
		raw.append(v.x)
	raw.append(float(lay["z_belt_f"]))
	raw.append(float(lay["z_belt_r"]))
	var arch_half: float = lay["arch_half"]
	var wb: float = p["wheelbase"]
	var axles: Array[float] = [-wb * 0.5, wb * 0.5]
	for axle: float in axles:
		for i in range(ARCH_STATIONS + 1):
			var t := float(i) / float(ARCH_STATIONS)
			raw.append(axle - arch_half + t * arch_half * 2.0)

	var clamped := PackedFloat32Array()
	for z in raw:
		clamped.append(clampf(z, z_nose, z_tail))
	clamped.sort()
	var out := PackedFloat32Array()
	for z in clamped:
		if out.is_empty() or z - out[out.size() - 1] > 0.012:
			out.append(z)
	return out


## Underbody line: flat at ride height, lifting into a half-ellipse over each axle.
static func _hull_bottom(p: Dictionary, lay: Dictionary, z: float) -> float:
	var base: float = p["clearance"]
	var arch_top: float = lay["arch_y"]
	var arch_half: float = lay["arch_half"]
	var wb: float = p["wheelbase"]
	var axles: Array[float] = [-wb * 0.5, wb * 0.5]
	var y := base
	for axle: float in axles:
		var t := absf(z - axle) / arch_half
		if t < 1.0:
			y = maxf(y, base + (arch_top - base) * sqrt(1.0 - t * t))
	return y


# --- Greenhouse ---

static func _build_greenhouse(root: Node3D, p: Dictionary, lay: Dictionary, mats: Dictionary) -> void:
	var hb: float = lay["hw"]
	var hr: float = lay["hw_roof"]
	var y_belt: float = lay["belt_y"]
	var y_rf: float = lay["roof_inner"]
	var y_rr: float = lay["roof_inner_r"]
	var z_bf: float = lay["z_belt_f"]
	var z_br: float = lay["z_belt_r"]
	var z_rf: float = lay["z_roof_f"]
	var z_rr: float = lay["z_roof_r"]

	## Belt corners share the hull's half width, so glass rises straight off the door
	## skin with no ledge to catch the light. Tumblehome comes from the roof taper.
	var bfl := Vector3(-hb, y_belt, z_bf)
	var bfr := Vector3(hb, y_belt, z_bf)
	var brl := Vector3(-hb, y_belt, z_br)
	var brr := Vector3(hb, y_belt, z_br)
	var rfl := Vector3(-hr, y_rf, z_rf)
	var rfr := Vector3(hr, y_rf, z_rf)
	var rrl := Vector3(-hr, y_rr, z_rr)
	var rrr := Vector3(hr, y_rr, z_rr)

	_quad(root, "GlassWindshield", bfl, bfr, rfr, rfl, mats[MAT_GLASS])
	_quad(root, "GlassSide_-1", bfl, rfl, rrl, brl, mats[MAT_GLASS])
	_quad(root, "GlassSide_1", bfr, brr, rrr, rfr, mats[MAT_GLASS])
	var rear_mat: Material = mats[MAT_GLASS] if bool(p["rear_glass"]) else mats[MAT_BODY]
	var rear_name := "GlassRear" if bool(p["rear_glass"]) else "Bulkhead"
	_quad(root, rear_name, rrl, rrr, brr, brl, rear_mat)

	## Roof cap as a shallow loft: bevelled edges keep it from reading as a lid.
	var cap: Array[Dictionary] = [
		{"z": z_rf, "y0": y_rf, "y1": y_rf + ROOF_THICK, "hw": hr},
		{"z": z_rf + 0.10, "y0": y_rf, "y1": y_rf + ROOF_THICK, "hw": hr + 0.012},
		{"z": z_rr - 0.10, "y0": y_rr, "y1": y_rr + ROOF_THICK, "hw": hr + 0.012},
		{"z": z_rr, "y0": y_rr, "y1": y_rr + ROOF_THICK, "hw": hr},
	]
	var roof := _loft_z(root, "Roof", cap, mats[MAT_BODY], Vector2.ZERO)
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	## Pillars along the glass edges. Four corners plus one B-pillar per side is all a
	## chunky car needs to read as having doors.
	## Thick enough to belong on a chunky body; thin struts read as wire.
	var pillar := 0.105
	_strut(root, "PillarA_-1", bfl, rfl, pillar, mats[MAT_BODY])
	_strut(root, "PillarA_1", bfr, rfr, pillar, mats[MAT_BODY])
	_strut(root, "PillarC_-1", brl, rrl, pillar, mats[MAT_BODY])
	_strut(root, "PillarC_1", brr, rrr, pillar, mats[MAT_BODY])
	if z_rr - z_rf > 0.55:
		var z_mid := (z_rf + z_rr) * 0.5
		var y_mid := (y_rf + y_rr) * 0.5
		_strut(
			root, "PillarB_-1",
			Vector3(-hb, y_belt, z_mid), Vector3(-hr, y_mid, z_mid),
			pillar * 0.9, mats[MAT_BODY]
		)
		_strut(
			root, "PillarB_1",
			Vector3(hb, y_belt, z_mid), Vector3(hr, y_mid, z_mid),
			pillar * 0.9, mats[MAT_BODY]
		)


# --- Interior ---

## Inward-facing liner for the open cabin channel, plus seats the riders sit on.
## Without the liner you would see straight through the hull's back-facing skin.
static func _build_interior(root: Node3D, p: Dictionary, lay: Dictionary, mats: Dictionary) -> void:
	var hw: float = lay["hw"]
	var y0: float = lay["floor_y"]
	var y1: float = lay["belt_y"]
	var z0: float = lay["z_belt_f"]
	var z1: float = lay["z_belt_r"]
	var trim: Material = mats[MAT_TRIM]

	## Corners of the tub, listed so each quad's normal points into the cabin.
	_quad(root, "TubFloor",
		Vector3(-hw, y0, z0), Vector3(hw, y0, z0), Vector3(hw, y0, z1), Vector3(-hw, y0, z1), trim)
	_quad(root, "TubWall_-1",
		Vector3(-hw, y0, z0), Vector3(-hw, y0, z1), Vector3(-hw, y1, z1), Vector3(-hw, y1, z0), trim)
	_quad(root, "TubWall_1",
		Vector3(hw, y0, z0), Vector3(hw, y1, z0), Vector3(hw, y1, z1), Vector3(hw, y0, z1), trim)
	_quad(root, "TubFront",
		Vector3(-hw, y0, z0), Vector3(-hw, y1, z0), Vector3(hw, y1, z0), Vector3(hw, y0, z0), trim)
	_quad(root, "TubRear",
		Vector3(-hw, y0, z1), Vector3(hw, y0, z1), Vector3(hw, y1, z1), Vector3(-hw, y1, z1), trim)

	var seats: Array = _seat_offsets(p, lay)
	for i in range(seats.size()):
		var seat: Dictionary = seats[i]
		var sx := float(seat["x"])
		var sz := float(seat["z"])
		## Cushion top sits just under the rig's hips so nobody floats.
		var cushion_top := y0 + 0.42
		_box(root, "SeatCushion_%d" % i, Vector3(0.46, 0.10, 0.46),
			Vector3(sx, cushion_top - 0.05, sz + 0.10), trim)
		_box(root, "SeatBack_%d" % i, Vector3(0.46, 0.52, 0.09),
			Vector3(sx, cushion_top + 0.26, sz + 0.40), trim)

	_box(root, "Dash", Vector3(hw * 1.9, 0.18, 0.24),
		Vector3(0.0, y1 - 0.11, z0 + 0.15), trim)
	## Steering wheel on the left: cheap, but it is what sells the cabin at a glance.
	var wheel := _cyl(root, "SteeringWheel", 0.17, 0.035,
		Vector3(float((seats[0] as Dictionary)["x"]), y1 - 0.03, z0 + 0.33), trim, 16)
	wheel.rotation.x = PI * 0.5


static func _seat_offsets(p: Dictionary, lay: Dictionary) -> Array:
	var z0: float = lay["z_belt_f"]
	var seat_y: float = lay["floor_y"]
	## Knees reach ~0.24 m forward of the seat origin; keep them behind the firewall.
	var seat_z := z0 + 0.55
	var columns := int(p["seat_columns"])
	var out: Array = []
	if columns == 3:
		var spread: float = float(lay["hw"]) * 0.58
		out.append({"x": -spread, "y": seat_y, "z": seat_z})
		out.append({"x": 0.0, "y": seat_y, "z": seat_z})
		out.append({"x": spread, "y": seat_y, "z": seat_z})
		return out
	var half: float = float(lay["hw"]) * 0.38
	out.append({"x": -half, "y": seat_y, "z": seat_z})
	out.append({"x": half, "y": seat_y, "z": seat_z})
	return out


# --- Wheels ---

static func _build_wheels(root: Node3D, p: Dictionary, lay: Dictionary, mats: Dictionary) -> void:
	var wheel_r: float = p["wheel_r"]
	var wheel_w: float = p["wheel_w"]
	var wb: float = p["wheelbase"]
	var sides: Array[float] = [-1.0, 1.0]
	var ends: Array[float] = [-1.0, 1.0]
	for side: float in sides:
		for zs: float in ends:
			var wz := zs * wb * 0.5
			## Sit the tread a hair outside the flank so wheels read as planted.
			var hw_here := _line_at(lay["plan_line"] as Array[Vector2], wz)
			var wx := side * (hw_here + 0.012 - wheel_w * 0.5)
			var at := Vector3(wx, wheel_r, wz)
			var tire := _cyl(root, "Tire_%d_%d" % [int(side), int(zs)],
				wheel_r, wheel_w, at, mats[MAT_TIRE], WHEEL_SEGMENTS)
			tire.rotation.z = PI * 0.5
			## One proud disc instead of a hub plus five spokes: same read, 5 fewer nodes.
			var rim := _cyl(root, "Rim_%d_%d" % [int(side), int(zs)],
				wheel_r * 0.58, wheel_w * 1.06, at, mats[MAT_RIM], WHEEL_SEGMENTS)
			rim.rotation.z = PI * 0.5
			var hub := _cyl(root, "Hub_%d_%d" % [int(side), int(zs)],
				wheel_r * 0.22, wheel_w * 1.12, at, mats[MAT_TRIM], 12)
			hub.rotation.z = PI * 0.5


# --- Lights, bumpers, trim ---

static func _build_lights(root: Node3D, p: Dictionary, lay: Dictionary, mats: Dictionary) -> void:
	var z_nose: float = lay["z_nose"]
	var z_tail: float = lay["z_tail"]
	var top_line: Array[Vector2] = lay["top_line"]
	var plan_line: Array[Vector2] = lay["plan_line"]
	var hw_nose := _line_at(plan_line, z_nose)
	var hw_tail := _line_at(plan_line, z_tail)
	## Ride the actual nose and tail caps, so lights land on the panel at any profile.
	var nose_y := lerpf(_hull_bottom(p, lay, z_nose), _line_at(top_line, z_nose), 0.66)
	var tail_y := lerpf(_hull_bottom(p, lay, z_tail), _line_at(top_line, z_tail), 0.62)

	var lens_d := 0.12
	var sides: Array[float] = [-1.0, 1.0]
	for side: float in sides:
		_box(root, "Headlight_%d" % int(side),
			Vector3(hw_nose * 0.38, 0.14, lens_d),
			Vector3(side * hw_nose * 0.57, nose_y, z_nose - PROUD + lens_d * 0.5),
			mats[MAT_LIGHT_F])
		_box(root, "Taillight_%d" % int(side),
			Vector3(hw_tail * 0.36, 0.15, lens_d),
			Vector3(side * hw_tail * 0.58, tail_y, z_tail + PROUD - lens_d * 0.5),
			mats[MAT_LIGHT_R])

	var grille_d := 0.10
	_box(root, "Grille", Vector3(hw_nose * 0.66, 0.15, grille_d),
		Vector3(0.0, nose_y, z_nose - PROUD + grille_d * 0.5), mats[MAT_TRIM])


static func _build_trim(root: Node3D, p: Dictionary, lay: Dictionary, mats: Dictionary) -> void:
	var z_nose: float = lay["z_nose"]
	var z_tail: float = lay["z_tail"]
	var z_bf: float = lay["z_belt_f"]
	var z_br: float = lay["z_belt_r"]
	var hw: float = lay["hw"]
	var plan_line: Array[Vector2] = lay["plan_line"]
	var clearance: float = p["clearance"]
	var arch_y: float = lay["arch_y"]
	var trim: Material = mats[MAT_TRIM]

	## Bumpers stay inside the body width. The old ones were 3% wider and jutted out at
	## every corner like bolted-on planks.
	var bumper_h := (arch_y - clearance) * 0.72
	var bumper_d := 0.13
	_box(root, "BumperFront",
		Vector3(_line_at(plan_line, z_nose) * 2.0, bumper_h, bumper_d),
		Vector3(0.0, clearance + bumper_h * 0.5, z_nose - PROUD + bumper_d * 0.5), trim)
	_box(root, "BumperRear",
		Vector3(_line_at(plan_line, z_tail) * 2.0, bumper_h, bumper_d),
		Vector3(0.0, clearance + bumper_h * 0.5, z_tail + PROUD - bumper_d * 0.5), trim)

	## Rocker runs arch to arch like a real sill; clipping it to the cabin left a dark
	## line that stopped halfway along the flank.
	var rocker_z0 := -float(p["wheelbase"]) * 0.5 + float(lay["arch_half"])
	var rocker_z1 := float(p["wheelbase"]) * 0.5 - float(lay["arch_half"])
	var cabin_len := z_br - z_bf
	var sides: Array[float] = [-1.0, 1.0]
	for side: float in sides:
		_box(root, "Rocker_%d" % int(side), Vector3(0.03, 0.075, rocker_z1 - rocker_z0),
			Vector3(side * (hw + 0.012), clearance + 0.055, (rocker_z0 + rocker_z1) * 0.5), trim)
		## Door shut lines, so the side is not one blank panel.
		_box(root, "DoorSeam_%d" % int(side), Vector3(0.02, float(lay["belt_y"]) - arch_y, 0.022),
			Vector3(side * (hw + 0.008), (arch_y + float(lay["belt_y"])) * 0.5, (z_bf + z_br) * 0.5),
			trim)
		## Mirror overlaps the greenhouse base so it is attached, not hovering.
		_box(root, "Mirror_%d" % int(side), Vector3(0.17, 0.075, 0.10),
			Vector3(side * (hw + 0.068), float(lay["belt_y"]) + 0.06, z_bf + 0.17), trim)


# --- Per-livery and per-family props ---

static func _build_livery(
	root: Node3D, p: Dictionary, lay: Dictionary, mats: Dictionary, livery: String
) -> void:
	var hw: float = lay["hw"]
	var hr: float = lay["hw_roof"]
	var roof_y: float = lay["roof_y"]
	var z_rf: float = lay["z_roof_f"]
	var z_rr: float = lay["z_roof_r"]
	var z_br: float = lay["z_belt_r"]
	var z_tail: float = lay["z_tail"]
	var sides: Array[float] = [-1.0, 1.0]

	if bool(p.get("rails", false)):
		for side: float in sides:
			_box(root, "Rail_%d" % int(side), Vector3(0.06, 0.045, (z_rr - z_rf) * 0.82),
				Vector3(side * hr * 0.74, roof_y + 0.022, (z_rf + z_rr) * 0.5), mats[MAT_TRIM])

	if bool(p.get("sport", false)):
		_box(root, "Spoiler", Vector3(hr * 1.7, 0.05, 0.20),
			Vector3(0.0, float(lay["roof_inner_r"]) + ROOF_THICK + 0.02, z_rr + 0.06),
			mats[MAT_BODY])

	match str(p["rear_deck"]):
		DECK_BED:
			var bed_y := float(lay["belt_y"]) - float(p["bed_drop"])
			var wall: float = p["bed_wall"]
			var bed_z0 := z_br + 0.10
			var bed_len := z_tail - bed_z0
			for side: float in sides:
				_box(root, "BedRail_%d" % int(side), Vector3(0.09, wall, bed_len),
					Vector3(side * (hw - 0.045), bed_y + wall * 0.5, bed_z0 + bed_len * 0.5),
					mats[MAT_BODY])
			_box(root, "Tailgate", Vector3(hw * 1.9, wall, 0.09),
				Vector3(0.0, bed_y + wall * 0.5, z_tail - 0.045), mats[MAT_BODY])
		DECK_BOX:
			## Cargo doors: two seams on the tail panel keep the box from being a slab.
			var seam_d := 0.024
			for side: float in sides:
				_box(root, "CargoSeam_%d" % int(side),
					Vector3(seam_d, roof_y - float(lay["arch_y"]) - 0.14, seam_d),
					Vector3(
						side * 0.02,
						(float(lay["arch_y"]) + roof_y) * 0.5,
						z_tail + PROUD - seam_d * 0.5
					),
					mats[MAT_TRIM])
			for side: float in sides:
				_box(root, "CargoBand_%d" % int(side), Vector3(0.02, 0.09, (z_tail - z_br) * 0.9),
					Vector3(side * (hw + 0.008), float(lay["belt_y"]) + 0.10,
						(z_br + z_tail) * 0.5),
					mats[MAT_TRIM])

	if livery == "taxi":
		_box(root, "TaxiSign", Vector3(0.56, 0.15, 0.26),
			Vector3(0.0, roof_y + 0.075, z_rf + 0.34), mats[MAT_ACCENT])
		for side: float in sides:
			_box(root, "TaxiStripe_%d" % int(side), Vector3(0.02, 0.13, (z_rr - z_rf) + 0.7),
				Vector3(side * (hw + 0.01), float(lay["belt_y"]) - 0.22, (z_rf + z_rr) * 0.5),
				mats[MAT_ACCENT])
	elif livery == "police":
		## Split bar: accent blue one side, tail red the other.
		_box(root, "LightBar_-1", Vector3(hr * 0.7, 0.10, 0.22),
			Vector3(-hr * 0.4, roof_y + 0.05, z_rf + 0.30), mats[MAT_ACCENT])
		_box(root, "LightBar_1", Vector3(hr * 0.7, 0.10, 0.22),
			Vector3(hr * 0.4, roof_y + 0.05, z_rf + 0.30), mats[MAT_LIGHT_R])
		for side: float in sides:
			_box(root, "PoliceStripe_%d" % int(side),
				Vector3(0.02, 0.18, float(p["length"]) * 0.46),
				Vector3(side * (hw + 0.01), float(lay["belt_y"]) - 0.24, 0.0),
				mats[MAT_ACCENT])


# --- Mesh helpers ---
#
# Face winding convention for _quad / _mesh_from_faces: order the four corners so that
# (c2 - c0).cross(c1 - c0) points along the outward normal.

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
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Box spanning two points, used for pillars.
static func _strut(
	parent: Node3D, node_name: String, a: Vector3, b: Vector3, thickness: float, mat: Material
) -> MeshInstance3D:
	var span := b - a
	var length := span.length()
	if length < 0.001:
		push_error("ProceduralVehicle: degenerate strut '%s'" % node_name)
		length = 0.001
		span = Vector3.UP * length
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = Vector3(thickness, length, thickness)
	mi.mesh = mesh
	mi.position = (a + b) * 0.5
	mi.quaternion = Quaternion(Vector3.UP, span / length)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Lofted volume along Z. Stations carry z, underside y0, top y1 and half width; the
## surface between them is quads, so a rising y0 cuts a wheel arch into the flanks.
## `open_top` (x < y) drops the top face over that Z range, leaving the cabin channel.
static func _loft_z(
	parent: Node3D,
	node_name: String,
	stations: Array[Dictionary],
	mat: Material,
	open_top: Vector2
) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_opening := open_top.x < open_top.y

	for i in range(stations.size() - 1):
		var a := stations[i]
		var b := stations[i + 1]
		var za := float(a["z"])
		var zb := float(b["z"])
		var a0 := float(a["y0"])
		var a1 := float(a["y1"])
		var b0 := float(b["y0"])
		var b1 := float(b["y1"])
		var ha := float(a["hw"])
		var hb := float(b["hw"])

		var mid := (za + zb) * 0.5
		if not (has_opening and mid > open_top.x and mid < open_top.y):
			_add_quad(st,
				Vector3(-ha, a1, za), Vector3(ha, a1, za), Vector3(hb, b1, zb), Vector3(-hb, b1, zb))
		_add_quad(st,
			Vector3(-ha, a0, za), Vector3(-hb, b0, zb), Vector3(hb, b0, zb), Vector3(ha, a0, za))
		_add_quad(st,
			Vector3(-ha, a0, za), Vector3(-ha, a1, za), Vector3(-hb, b1, zb), Vector3(-hb, b0, zb))
		_add_quad(st,
			Vector3(ha, a0, za), Vector3(hb, b0, zb), Vector3(hb, b1, zb), Vector3(ha, a1, za))

	var first := stations[0]
	var fz := float(first["z"])
	var fh := float(first["hw"])
	_add_quad(st,
		Vector3(-fh, float(first["y0"]), fz), Vector3(fh, float(first["y0"]), fz),
		Vector3(fh, float(first["y1"]), fz), Vector3(-fh, float(first["y1"]), fz))
	var last := stations[stations.size() - 1]
	var lz := float(last["z"])
	var lh := float(last["hw"])
	_add_quad(st,
		Vector3(-lh, float(last["y1"]), lz), Vector3(lh, float(last["y1"]), lz),
		Vector3(lh, float(last["y0"]), lz), Vector3(-lh, float(last["y0"]), lz))

	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _quad(
	parent: Node3D,
	node_name: String,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	mat: Material
) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_quad(st, a, b, c, d)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Flat-shaded: one normal for the whole quad, written per vertex. SurfaceTool's
## generate_normals() welds coincident vertices and averages, which rounded every crease
## off and turned the nose and tail into smooth loaves instead of faceted panels.
static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var cross := (c - a).cross(b - a)
	if cross.length_squared() < 1.0e-12:
		push_error("ProceduralVehicle: degenerate quad at %s" % a)
		return
	var n := cross.normalized()
	for v: Vector3 in [a, b, c, a, c, d]:
		st.set_normal(n)
		st.add_vertex(v)


## Piecewise-linear lookup, clamped past both ends.
static func _line_at(line: Array[Vector2], z: float) -> float:
	if line.is_empty():
		push_error("ProceduralVehicle: empty profile line")
		return 0.0
	if z <= line[0].x:
		return line[0].y
	for i in range(1, line.size()):
		var a := line[i - 1]
		var b := line[i]
		if z <= b.x:
			var span := b.x - a.x
			if span <= 0.0001:
				return b.y
			return lerpf(a.y, b.y, (z - a.x) / span)
	return line[line.size() - 1].y


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
