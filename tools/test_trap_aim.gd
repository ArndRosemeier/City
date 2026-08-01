## Trap throw must use meteor-style world aim (cursor + destructibles, no agent magnet).
##
## Run: powershell -File tools\run_test.ps1 test_trap_aim
extends Node

const PlayerInventoryScript := preload("res://scripts/city/player_inventory.gd")
const TrapProjectileScript := preload("res://scripts/city/trap_projectile.gd")

const AIM_HIT := Vector3(12.0, 3.5, -6.0)

var _failed := false


class TestCity:
	extends CityRoot

	func _ready() -> void:
		pass

	func bind_player(walker: CityWalker) -> void:
		_walker = walker

	func bind_inventory(inv: PlayerInventory) -> void:
		_inventory = inv

	func throw_trap_for_test() -> void:
		_throw_trap()

	func trap_velocity_for_test(origin: Vector3, target: Vector3) -> Vector3:
		return _trap_throw_velocity(origin, target)


class AimStub:
	extends CityWalker
	var aim: Dictionary = {}
	var world_aim_calls: int = 0

	func aim_world_at_cursor() -> Dictionary:
		world_aim_calls += 1
		return aim


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	await _check_throw_uses_world_aim()
	await _check_miss_does_not_consume()
	_check_ballistic_points_at_target()
	_check_source_uses_world_aim()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _check_throw_uses_world_aim() -> void:
	var city := TestCity.new()
	add_child(city)
	var walker := AimStub.new()
	walker.aim = {
		"point": AIM_HIT,
		"normal": Vector3.UP,
		"did_hit": true,
		"cam_from": Vector3.ZERO,
		"cam_dir": Vector3.FORWARD,
	}
	city.bind_player(walker)
	city.add_child(walker)
	var inv: PlayerInventory = PlayerInventoryScript.new() as PlayerInventory
	inv.add(InventoryCatalog.ID_TRAP, 2)
	city.bind_inventory(inv)
	await get_tree().process_frame

	city.throw_trap_for_test()
	await get_tree().process_frame

	if walker.world_aim_calls < 1:
		_fail("FAIL trap throw did not call aim_world_at_cursor")
	if inv.count_of(InventoryCatalog.ID_TRAP) != 1:
		_fail("FAIL trap throw did not consume one trap on hit")

	var proj: TrapProjectile = null
	for child in city.get_children():
		if child is TrapProjectile:
			proj = child as TrapProjectile
			break
	if proj == null:
		_fail("FAIL trap throw did not spawn TrapProjectile")
	else:
		var to_aim := AIM_HIT - proj.global_position
		if to_aim.length_squared() > 0.0001 and proj.linear_velocity.dot(to_aim.normalized()) <= 0.0:
			_fail("FAIL trap velocity does not point toward aim hit")
		proj.queue_free()

	city.queue_free()
	print("OK trap throw aims at world hit and spawns projectile")


func _check_miss_does_not_consume() -> void:
	var city := TestCity.new()
	add_child(city)
	var walker := AimStub.new()
	walker.aim = {
		"point": Vector3(100.0, 50.0, 100.0),
		"normal": Vector3.UP,
		"did_hit": false,
		"cam_from": Vector3.ZERO,
		"cam_dir": Vector3.FORWARD,
	}
	city.bind_player(walker)
	city.add_child(walker)
	var inv: PlayerInventory = PlayerInventoryScript.new() as PlayerInventory
	inv.add(InventoryCatalog.ID_TRAP, 1)
	city.bind_inventory(inv)
	await get_tree().process_frame

	city.throw_trap_for_test()
	await get_tree().process_frame

	if inv.count_of(InventoryCatalog.ID_TRAP) != 1:
		_fail("FAIL miss consumed a trap")
	for child in city.get_children():
		if child is TrapProjectile:
			_fail("FAIL miss spawned a TrapProjectile")
			break

	city.queue_free()
	print("OK trap miss cancels without consuming")


func _check_ballistic_points_at_target() -> void:
	var city := TestCity.new()
	add_child(city)
	var origin := Vector3(0.0, 1.2, 0.0)
	var target := Vector3(8.0, 0.5, 0.0)
	var vel := city.trap_velocity_for_test(origin, target)
	if vel.x <= 0.0:
		_fail("FAIL ballistic X should push toward +X target")
	## With gravity, upward launch is expected for a forward lob.
	if vel.y <= 0.0:
		_fail("FAIL ballistic Y should loft the trap")
	city.queue_free()
	print("OK ballistic lob velocity")


func _check_source_uses_world_aim() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/city/city_root.gd")
	if not src.contains("func _throw_trap()"):
		_fail("FAIL _throw_trap missing")
		return
	var start := src.find("func _throw_trap()")
	var stop := src.find("\nfunc ", start + 1)
	var body := src.substr(start, stop - start if stop > start else src.length() - start)
	if not body.contains("aim_world_at_cursor"):
		_fail("FAIL _throw_trap no longer uses aim_world_at_cursor")
	if body.contains("-_walker.global_transform.basis.z"):
		_fail("FAIL _throw_trap still lobs from facing only")
	print("OK _throw_trap source uses world aim")
