## Headless: assert every procedural vehicle profile is buildable, that its cabin
## actually fits the seated passenger rig, and that its declared collision box matches
## the body rather than the mirrors and roof props.
extends SceneTree

const PedOutfitScript := preload("res://scripts/humans/ped_outfit.gd")
const QuaterniusLocomotionScript := preload("res://scripts/city/quaternius_locomotion.gd")
## Measured by tools/measure_passenger_seat.gd: feet-to-skull of the tallest outfit at
## the scale VehicleVisual applies. Duplicated here on purpose — the test has to fail if
## ProceduralVehicle's own constant drifts away from the rig.
const SEATED_HEAD_TOP := 1.259
## Knees reach this far ahead of the seat origin, the back this far behind.
const SEAT_KNEE_AHEAD := 0.24
const SEAT_BACK_BEHIND := 0.36
## Mirrors and roof props may stick out past the declared body box by at most this much.
const PROP_ALLOWANCE := 0.22

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	VehicleCatalog.reload()
	if not VehicleCatalog.is_ready():
		push_error("FAIL vehicle catalog not ready")
		quit(1)
		return

	var rng := RandomNumberGenerator.new()
	for i in range(VehicleCatalog.count()):
		var entry: Dictionary = VehicleCatalog.entry_at(i)
		rng.seed = 1234
		var car := ProceduralVehicle.build(entry, rng)
		if car == null:
			_fail("build returned null for %s" % str(entry.get("id", "?")))
			continue
		_check_car(str(entry.get("id", "?")), car)
		_check_determinism(entry, car)
		car.free()

	if _failures > 0:
		push_error("FAIL procedural_vehicle failures=%d" % _failures)
		quit(1)
		return
	print("OK procedural_vehicle profiles=%d" % VehicleCatalog.count())
	quit(0)


func _check_car(id: String, car: Node3D) -> void:
	for key in ["seat_offsets", "body_length", "body_width", "body_height", "glass_count"]:
		if not car.has_meta(key):
			_fail("%s: missing meta '%s'" % [id, key])
			return

	var height := float(car.get_meta("body_height"))
	var width := float(car.get_meta("body_width"))
	var length := float(car.get_meta("body_length"))
	var seats: Array = car.get_meta("seat_offsets")
	if seats.is_empty():
		_fail("%s: no seats" % id)
		return

	## Cabin has to clear the tallest rider at every seat, or heads poke through the roof.
	for si in range(seats.size()):
		var seat: Dictionary = seats[si]
		var head := float(seat["y"]) + SEATED_HEAD_TOP
		if head > height - 0.02:
			_fail(
				"%s: seat %d head reaches %.2f m but the roof tops out at %.2f m"
				% [id, si, head, height]
			)
		if absf(float(seat["x"])) + 0.24 > width * 0.5:
			_fail("%s: seat %d shoulder is outside the body width" % [id, si])

	if int(car.get_meta("glass_count")) <= 0:
		_fail("%s: no glass surfaces" % id)

	## Declared box must describe the body: mirrors and light bars may exceed it only
	## slightly, and it must never be smaller than the painted hull.
	var aabb := _mesh_aabb(car)
	if aabb.size == Vector3.ZERO:
		_fail("%s: no mesh geometry" % id)
		return
	if aabb.size.x > width + PROP_ALLOWANCE * 2.0:
		_fail("%s: mesh is %.2f m wide but declares %.2f m" % [id, aabb.size.x, width])
	if aabb.size.y > height + PROP_ALLOWANCE:
		_fail("%s: mesh is %.2f m tall but declares %.2f m" % [id, aabb.size.y, height])
	## Only surface details like door seams may break the plane, never whole parts.
	if aabb.size.z > length + 0.02:
		_fail("%s: mesh is %.2f m long but declares %.2f m" % [id, aabb.size.z, length])
	if absf(aabb.position.y) > 0.02:
		_fail("%s: wheels do not rest on y=0 (lowest mesh point %.3f)" % [id, aabb.position.y])

	## Cars used to cast nothing and floated over the road. The two big volumes carry
	## the shadow; every detail part stays off so the cost is two draws per car.
	var casters := 0
	var glass_alpha := false
	for node in car.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			_fail("%s: %s has no mesh" % [id, node.name])
			continue
		if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			casters += 1
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			_fail("%s: %s has no material" % [id, node.name])
			continue
		if String(mat.resource_name) == ProceduralVehicle.MAT_GLASS:
			if mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
				glass_alpha = true
			else:
				_fail("%s: glass on %s is not alpha blended" % [id, node.name])
	if not glass_alpha:
		_fail("%s: no alpha-blended glass" % id)
	if casters != 2:
		_fail("%s: expected hull and roof to cast shadows, found %d casters" % [id, casters])


func _check_determinism(entry: Dictionary, first: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var again := ProceduralVehicle.build(entry, rng)
	if again == null:
		_fail("%s: rebuild returned null" % str(entry.get("id", "?")))
		return
	var a := first.find_children("*", "MeshInstance3D", true, false).size()
	var b := again.find_children("*", "MeshInstance3D", true, false).size()
	if a != b:
		_fail("%s: same seed produced %d then %d meshes" % [str(entry.get("id", "?")), a, b])
	again.free()


func _mesh_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var any := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		## The shadow blob is a projection helper, not part of the silhouette.
		if mi.name == "ContactShadow":
			continue
		var xf := mi.transform
		for corner in _corners(mi.mesh.get_aabb()):
			var p: Vector3 = xf * corner
			if not any:
				out = AABB(p, Vector3.ZERO)
				any = true
			else:
				out = out.expand(p)
	return out


func _corners(a: AABB) -> Array[Vector3]:
	var p := a.position
	var s := a.size
	return [
		p,
		p + Vector3(s.x, 0.0, 0.0),
		p + Vector3(0.0, s.y, 0.0),
		p + Vector3(0.0, 0.0, s.z),
		p + Vector3(s.x, s.y, 0.0),
		p + Vector3(s.x, 0.0, s.z),
		p + Vector3(0.0, s.y, s.z),
		p + s,
	]


func _fail(msg: String) -> void:
	push_error("FAIL %s" % msg)
	_failures += 1
