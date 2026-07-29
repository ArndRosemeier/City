## The player's failsafe deck is owned by the walker so it cannot outlive the body it catches,
## and top-level so it keeps the world placement `_update_safety_deck` writes. Both halves are
## load-bearing: a deck parented under the walker without `top_level` turns with the body and
## grows with its transform, and a deck left parentless leaks its collision RID.
##
## Run: powershell -File tools\run_test.ps1 test_walker_safety_deck
extends Node

## Metres the deck rides below the feet (CityWalker._update_safety_deck).
const DECK_DROP_M := 8.0
const DECK_SIZE := Vector3(80.0, 1.0, 80.0)
## How far the deck's axes may drift from the world axes before it counts as turned/stretched.
const BASIS_TOL := 0.0001
## How far the deck may sit from the place `_update_safety_deck` writes.
const PLACE_TOL_M := 0.01


func _ready() -> void:
	await get_tree().physics_frame

	## The host is itself turned and scaled, and the walker is turned inside it: a deck that
	## reads its parent chain on entering the tree bakes that in and never sheds it.
	var host := Node3D.new()
	host.rotation.y = deg_to_rad(37.0)
	host.scale = Vector3(2.0, 2.0, 2.0)
	add_child(host)

	var walker := CityWalker.new()
	walker.rotation.y = deg_to_rad(-64.0)
	host.add_child(walker)
	walker.global_position = Vector3(120.0, 30.0, -45.0)
	await get_tree().physics_frame

	var deck: StaticBody3D = walker.get_node_or_null("SafetyDeck") as StaticBody3D
	if deck == null:
		push_error("FAIL the walker owns no SafetyDeck child — it would outlive the walker")
		return _fail()
	if not deck.top_level:
		push_error("FAIL SafetyDeck is not top_level — it turns and grows with the walker")
		return _fail()
	if deck.collision_layer != CityWalker.SAFETY_DECK_LAYER:
		push_error(
			"FAIL SafetyDeck layer %d is not SAFETY_DECK_LAYER %d"
			% [deck.collision_layer, CityWalker.SAFETY_DECK_LAYER]
		)
		return _fail()

	if not _check_placement(walker, deck, "spawned under a turned, scaled host"):
		return _fail()

	## Turning is what `top_level` is here for: the box must not yaw with the body.
	for step in [45.0, 120.0, -175.0, 359.0]:
		walker.set_yaw(deg_to_rad(float(step)))
		await get_tree().physics_frame
		if not _check_placement(walker, deck, "yaw %+.0f°" % float(step)):
			return _fail()

	for s in [0.2, 1.0, 5.0]:
		walker.set_character_scale(float(s), true)
		await get_tree().physics_frame
		if not _check_placement(walker, deck, "character_scale %.2f" % float(s)):
			return _fail()
		var box := (deck.get_child(0) as CollisionShape3D).shape as BoxShape3D
		if box.size.distance_to(DECK_SIZE) > PLACE_TOL_M:
			push_error(
				"FAIL deck box grew to %s at character_scale %.2f (want %s)"
				% [box.size, float(s), DECK_SIZE]
			)
			return _fail()

	## Walked far from the origin the deck was built at, so a deck that stopped tracking shows.
	walker.global_position = Vector3(-812.5, 4.25, 630.0)
	await get_tree().physics_frame
	if not _check_placement(walker, deck, "moved 1 km from the build position"):
		return _fail()

	## A walker whose physics never ticks used to leak the deck outright, because the deck was
	## only ever adopted from inside `_physics_process`.
	var idle := CityWalker.new()
	idle.set_physics_process(false)
	add_child(idle)
	await get_tree().physics_frame
	var idle_deck: StaticBody3D = idle.get_node_or_null("SafetyDeck") as StaticBody3D
	if idle_deck == null:
		push_error("FAIL a walker with physics disabled owns no SafetyDeck")
		return _fail()
	print("PASS deck exists on a walker whose physics never ticked")

	walker.queue_free()
	idle.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(deck) or is_instance_valid(idle_deck):
		push_error(
			"FAIL a SafetyDeck outlived its walker (ticked=%s idle=%s) — the RID leaks"
			% [is_instance_valid(deck), is_instance_valid(idle_deck)]
		)
		return _fail()
	for orphan: Node in host.get_children() + get_children():
		if orphan is StaticBody3D:
			push_error("FAIL '%s' was left behind when the walker was freed" % orphan.name)
			return _fail()
	print("PASS both decks were freed with their walker, nothing left in the host")

	print("RESULT: OK")
	get_tree().quit(0)


## The deck sits `DECK_DROP_M` under the feet, square with the world and unscaled.
func _check_placement(walker: CityWalker, deck: StaticBody3D, what: String) -> bool:
	var want := walker.global_position - Vector3(0.0, DECK_DROP_M, 0.0)
	var off := deck.global_position.distance_to(want)
	var err := _basis_error(deck.global_transform.basis)
	if off > PLACE_TOL_M:
		push_error(
			"FAIL deck at %s, %.3fm off the %s it should hold (%s)"
			% [deck.global_position, off, want, what]
		)
		return false
	if err > BASIS_TOL:
		push_error(
			"FAIL deck basis turned/stretched by %.4f (%s): %s"
			% [err, what, deck.global_transform.basis]
		)
		return false
	print(
		"PASS %s: deck at %s, %.2fm under the feet, basis square (err %.6f)"
		% [what, deck.global_position, walker.global_position.y - deck.global_position.y, err]
	)
	return true


## Worst axis drift between `b` and the world axes: 0 means unrotated and unscaled.
func _basis_error(b: Basis) -> float:
	return maxf(
		maxf(b.x.distance_to(Vector3.RIGHT), b.y.distance_to(Vector3.UP)),
		b.z.distance_to(Vector3.BACK)
	)


func _fail() -> void:
	print("RESULT: FAILED")
	get_tree().quit(1)
