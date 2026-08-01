## A sealed recipe waiting at the end of a climb: walk into it (or click it) and it becomes
## something the player does not know yet.
##
## The prop is deliberately anonymous. Every one of these looks identical wherever it stands, so
## a rooftop cannot be judged worth the climb by squinting at what is on it — the scroll only
## decides what it is at the moment it is opened (see `CityRoot.collect_recipe_pickup`).
##
## Walk-over is the primary collect: an Area3D watches the walker's layer. Click still works
## through the same `world_interact` path as chests, so a scroll perched on a thin spire tip can
## be taken without having to stand exactly on it.
class_name RecipePickup
extends Node3D

## Parchment roll: half a metre of scroll, which reads at arm's length without dwarfing a bench.
const ROLL_LENGTH := 0.46
const ROLL_RADIUS := 0.085
const CAP_RADIUS := 0.104
const CAP_THICK := 0.04
const BAND_RADIUS := 0.11

## Clickable box around the whole prop, generous enough to hit from a running jump.
const CLICK_EXTENTS := Vector3(0.34, 0.26, 0.26)
## Walk-over bubble. Wider than the mesh so a running approach still pays, tall enough that a
## jump-land on a roof does not miss the slab the scroll is sitting on.
const COLLECT_RADIUS := 1.15
const COLLECT_HEIGHT := 2.2

## Idle motion, so a scroll on a dark roof still catches the eye.
const SPIN_DEG_PER_SEC := 34.0
const BOB_AMPLITUDE := 0.07
const BOB_PERIOD_SEC := 2.6
## Light range is small on purpose: a landmark beacon, not a street lamp.
const GLOW_RANGE := 3.2
const GLOW_ENERGY := 0.9

const PARCHMENT := Color(0.94, 0.88, 0.68)
const SEAL := Color(0.62, 0.16, 0.19)
const RIBBON := Color(0.83, 0.68, 0.28)

## Stable id of the spot this scroll sits at, e.g. "hill:3,-1:summit". The run remembers looted
## sites by this string, so re-streaming the district cannot pay it twice.
var site_id: String = ""

var _pivot: Node3D
var _base_y: float = 0.0
var _age: float = 0.0
var _taken: bool = false


## Stand a scroll at `world_pos`. `phase_seed` only staggers the idle bob, so two pickups in view
## of each other do not pulse in lockstep; what the scroll turns out to be is decided on pickup.
func build(id: String, world_pos: Vector3, phase_seed: int) -> bool:
	if id.is_empty():
		push_error("RecipePickup.build: a pickup with no site id cannot be marked as looted")
		return false
	site_id = id
	global_position = world_pos
	_base_y = world_pos.y
	_age = float(absi(phase_seed) % 1000) * 0.01 * BOB_PERIOD_SEC
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_build_model(_pivot)
	_add_glow(_pivot)
	_add_click_body()
	_add_collect_area()
	add_to_group("world_interact")
	set_process(true)
	return true


func is_taken() -> bool:
	return _taken


## Clicked. Always returns true: the click belonged to the scroll whether or not it still had
## anything to give, so the shot that found it is swallowed rather than turned into a bolt.
func interact_at_world(_world_pos: Vector3) -> bool:
	_try_collect()
	return true


func _process(delta: float) -> void:
	_age += delta
	if _pivot == null or not is_instance_valid(_pivot):
		return
	_pivot.rotate_y(deg_to_rad(SPIN_DEG_PER_SEC * delta))
	var bob := sin(TAU * _age / BOB_PERIOD_SEC) * BOB_AMPLITUDE
	position.y = _base_y + bob


func _build_model(parent: Node3D) -> void:
	## The roll lies along X, so the spin shows its length rather than an end-on circle.
	var lie := Basis(Vector3.FORWARD, PI * 0.5)

	var roll := MeshInstance3D.new()
	roll.name = "Roll"
	var roll_mesh := CylinderMesh.new()
	roll_mesh.top_radius = ROLL_RADIUS
	roll_mesh.bottom_radius = ROLL_RADIUS
	roll_mesh.height = ROLL_LENGTH
	roll_mesh.radial_segments = 14
	roll.mesh = roll_mesh
	roll.material_override = _make_material(PARCHMENT, 0.55)
	roll.transform = Transform3D(lie, Vector3.ZERO)
	parent.add_child(roll)

	for side in [-1.0, 1.0]:
		var cap := MeshInstance3D.new()
		cap.name = "Cap%s" % ("L" if side < 0.0 else "R")
		var cap_mesh := CylinderMesh.new()
		cap_mesh.top_radius = CAP_RADIUS
		cap_mesh.bottom_radius = CAP_RADIUS
		cap_mesh.height = CAP_THICK
		cap_mesh.radial_segments = 14
		cap.mesh = cap_mesh
		cap.material_override = _make_material(SEAL, 0.7)
		cap.transform = Transform3D(
			lie, Vector3(side * (ROLL_LENGTH * 0.5 - CAP_THICK * 0.5), 0.0, 0.0)
		)
		parent.add_child(cap)

	var band := MeshInstance3D.new()
	band.name = "Ribbon"
	var band_mesh := TorusMesh.new()
	band_mesh.inner_radius = ROLL_RADIUS
	band_mesh.outer_radius = BAND_RADIUS
	band_mesh.rings = 14
	band_mesh.ring_segments = 8
	band.mesh = band_mesh
	band.material_override = _make_material(RIBBON, 1.1)
	band.transform = Transform3D(lie, Vector3.ZERO)
	parent.add_child(band)


func _make_material(colour: Color, emission: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.65
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = emission
	return mat


func _add_glow(parent: Node3D) -> void:
	var light := OmniLight3D.new()
	light.name = "Glow"
	light.light_color = RIBBON
	light.light_energy = GLOW_ENERGY
	light.omni_range = GLOW_RANGE
	light.shadow_enabled = false
	parent.add_child(light)


func _add_click_body() -> void:
	var body := StaticBody3D.new()
	body.name = "ClickBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = CLICK_EXTENTS * 2.0
	shape.shape = box
	body.add_child(shape)
	add_child(body)


## Watches the walker's layer. Peds and undead share that layer, so the body filter below is what
## keeps a crowd from vacuuming a rooftop scroll the player has not reached yet.
func _add_collect_area() -> void:
	var area := Area3D.new()
	area.name = "CollectArea"
	area.collision_layer = 0
	area.collision_mask = 2
	area.monitoring = true
	area.monitorable = false
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = COLLECT_RADIUS
	capsule.height = COLLECT_HEIGHT
	shape.shape = capsule
	## Centre of the capsule sits a little above the scroll so the lower hemisphere covers the
	## roof slab the player is standing on.
	shape.position = Vector3(0.0, COLLECT_HEIGHT * 0.25, 0.0)
	area.add_child(shape)
	area.body_entered.connect(_on_collect_body_entered)
	add_child(area)


func _on_collect_body_entered(body: Node) -> void:
	if body is CityWalker:
		_try_collect()


func _try_collect() -> void:
	if _taken:
		return
	var city := _city_root()
	if city == null:
		push_error("RecipePickup: picked up with no CityRoot to hand the find to")
		return
	_taken = true
	city.collect_recipe_pickup(site_id, global_position)
	queue_free()


func _city_root() -> CityRoot:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group("city_root")
	if nodes.is_empty():
		return null
	return nodes[0] as CityRoot
