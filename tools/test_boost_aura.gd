## Speed / regen tonic feedback: world aura layers and HUD chips track the walker timers.
##
## Run: powershell -File tools\run_test.ps1 test_boost_aura
extends Node

const CityWalkerScript := preload("res://scripts/city/city_walker.gd")
const BoostAuraVfxScript := preload("res://scripts/city/boost_aura_vfx.gd")
const PlayerBoostHudScript := preload("res://scripts/city/player_boost_hud.gd")

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	await _check_aura_layers()
	await _check_walker_boost_sync()
	await _check_shield_toggle()
	await _check_hud_chips()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _check_aura_layers() -> void:
	var aura: Node3D = BoostAuraVfxScript.new() as Node3D
	aura.name = "Aura"
	add_child(aura)
	aura.call("setup")
	await get_tree().process_frame
	if (
		bool(aura.call("is_speed_active"))
		or bool(aura.call("is_regen_active"))
		or bool(aura.call("is_shield_active"))
	):
		_fail("FAIL aura starts with a layer on")
	if aura.visible:
		_fail("FAIL aura root should be hidden until a tonic is active")

	aura.call("set_speed_active", true)
	aura.call("set_body_scale", 2.0)
	await get_tree().process_frame
	if not bool(aura.call("is_speed_active")) or not aura.visible:
		_fail("FAIL speed layer did not show")
	var speed_root := aura.get_node_or_null("SpeedAura") as Node3D
	var regen_root := aura.get_node_or_null("RegenAura") as Node3D
	var shield_root := aura.get_node_or_null("ShieldAura") as Node3D
	if speed_root == null or not speed_root.visible:
		_fail("FAIL SpeedAura child missing/hidden")
	if regen_root != null and regen_root.visible:
		_fail("FAIL RegenAura should stay off for speed-only")
	if shield_root != null and shield_root.visible:
		_fail("FAIL ShieldAura should stay off for speed-only")
	## Speed stole cyan from the shield ward — orange is the only colour that keeps them apart.
	if BoostAuraVfxScript.SPEED_COLOR.is_equal_approx(BoostAuraVfxScript.SHIELD_COLOR):
		_fail("FAIL speed and shield auras share a colour")
	if BoostAuraVfxScript.SPEED_COLOR.r <= BoostAuraVfxScript.SPEED_COLOR.b:
		_fail("FAIL speed aura is not orange (r should dominate b)")

	aura.call("set_regen_active", true)
	if not bool(aura.call("is_regen_active")) or regen_root == null or not regen_root.visible:
		_fail("FAIL stacked regen layer did not show")

	aura.call("set_shield_active", true)
	if not bool(aura.call("is_shield_active")) or shield_root == null or not shield_root.visible:
		_fail("FAIL stacked shield layer did not show")

	aura.call("set_speed_active", false)
	aura.call("set_regen_active", false)
	aura.call("set_shield_active", false)
	if aura.visible:
		_fail("FAIL aura stayed visible after all layers off")
	aura.queue_free()


func _check_walker_boost_sync() -> void:
	var walker: CityWalker = CityWalkerScript.new() as CityWalker
	walker.name = "Walker"
	add_child(walker)
	await get_tree().process_frame

	if walker.speed_boost_left() > 0.0 or walker.regen_boost_left() > 0.0:
		_fail("FAIL walker starts with boost time")

	walker.begin_speed_boost(1.5, 1.45)
	walker.begin_regen_boost(2.0, 2.5)
	if walker.speed_boost_left() < 1.4 or walker.regen_boost_left() < 1.9:
		_fail("FAIL begin_* did not set boost timers")

	var aura := walker.get_node_or_null("BoostAura") as Node3D
	if aura == null:
		_fail("FAIL walker did not spawn BoostAura")
	elif not bool(aura.call("is_speed_active")) or not bool(aura.call("is_regen_active")):
		_fail("FAIL BoostAura layers not both active after drink")

	## Expire speed only; regen should remain.
	walker._boost_speed_left = 0.001
	walker._tick_status_effects(0.02)
	aura = walker.get_node_or_null("BoostAura") as Node3D
	if aura == null:
		_fail("FAIL BoostAura vanished while regen still live")
	elif bool(aura.call("is_speed_active")):
		_fail("FAIL speed aura stayed after timer hit zero")
	elif not bool(aura.call("is_regen_active")):
		_fail("FAIL regen aura dropped with speed")

	walker._boost_regen_left = 0.001
	walker._tick_status_effects(0.02)
	aura = walker.get_node_or_null("BoostAura") as Node3D
	if aura != null and (bool(aura.call("is_speed_active")) or bool(aura.call("is_regen_active"))):
		_fail("FAIL aura layers still on after both timers ended")
	walker.queue_free()


## Shield is a toggle: one press raises the cyan ward, the next drops it. Release must not
## empty the bar — that was the hold-to-drain bug.
func _check_shield_toggle() -> void:
	var walker: CityWalker = CityWalkerScript.new() as CityWalker
	walker.name = "ShieldWalker"
	add_child(walker)
	await get_tree().process_frame
	walker.set_energy_points(walker.energy_max)

	walker.toggle_shield()
	if not walker.is_shield_held():
		_fail("FAIL first shield toggle did not raise the ward")
	var aura := walker.get_node_or_null("BoostAura") as Node3D
	if aura == null or not bool(aura.call("is_shield_active")):
		_fail("FAIL shield aura missing while the ward is up")

	## Idempotent set — a release path must not drop a ward that is already up.
	walker.set_shield_held(true)
	if not walker.is_shield_held():
		_fail("FAIL set_shield_held(true) dropped the ward")

	walker.toggle_shield()
	if walker.is_shield_held():
		_fail("FAIL second shield toggle left the ward up")
	aura = walker.get_node_or_null("BoostAura") as Node3D
	if aura != null and bool(aura.call("is_shield_active")):
		_fail("FAIL shield aura stayed after the ward dropped")

	## Empty energy cannot raise it.
	walker.set_energy_points(0.0)
	walker.toggle_shield()
	if walker.is_shield_held():
		_fail("FAIL shield raised with no energy")
	walker.queue_free()


func _check_hud_chips() -> void:
	var walker: CityWalker = CityWalkerScript.new() as CityWalker
	walker.name = "HudWalker"
	add_child(walker)
	var hud: CanvasLayer = PlayerBoostHudScript.new() as CanvasLayer
	hud.name = "BoostHud"
	add_child(hud)
	await get_tree().process_frame
	hud.call("bind_walker", walker)
	await get_tree().process_frame

	var root := hud.get_node_or_null("Root") as Control
	if root == null:
		_fail("FAIL boost HUD missing Root")
		walker.queue_free()
		hud.queue_free()
		return
	if root.visible:
		_fail("FAIL boost HUD shows chips with no tonic")

	walker.begin_speed_boost(12.0)
	hud.call("_refresh")
	if not root.visible:
		_fail("FAIL boost HUD stayed hidden after speed tonic")
	var speed_chip := root.get_node_or_null("BoostRow/SpeedChip") as Control
	var regen_chip := root.get_node_or_null("BoostRow/RegenChip") as Control
	if speed_chip == null or not speed_chip.visible:
		_fail("FAIL Speed chip not visible")
	if regen_chip != null and regen_chip.visible:
		_fail("FAIL Regen chip visible without regen tonic")

	walker.begin_regen_boost(8.0)
	hud.call("_refresh")
	if regen_chip == null or not regen_chip.visible:
		_fail("FAIL Regen chip not visible after regen tonic")

	var grow_chip := root.get_node_or_null("BoostRow/GrowChip") as Control
	var shrink_chip := root.get_node_or_null("BoostRow/ShrinkChip") as Control
	if grow_chip != null and grow_chip.visible:
		_fail("FAIL Grow chip visible without temp scale")
	if shrink_chip != null and shrink_chip.visible:
		_fail("FAIL Shrink chip visible without temp scale")

	var base_scale := walker.get_character_scale()
	walker.begin_temp_scale(base_scale * 1.45, 25.0)
	hud.call("_refresh")
	if grow_chip == null or not grow_chip.visible:
		_fail("FAIL Grow chip not visible after grow")
	if shrink_chip != null and shrink_chip.visible:
		_fail("FAIL Shrink chip visible during grow")
	var grow_label := grow_chip.get_node_or_null("Label") as Label
	if grow_label == null or not grow_label.text.begins_with("Grow"):
		_fail("FAIL Grow chip label missing countdown")

	## Same timer; retarget below the restore size so the chip flips to Shrink.
	walker.begin_temp_scale(base_scale / 1.45, 25.0)
	hud.call("_refresh")
	if shrink_chip == null or not shrink_chip.visible:
		_fail("FAIL Shrink chip not visible after shrink")
	if grow_chip != null and grow_chip.visible:
		_fail("FAIL Grow chip still visible during shrink")

	hud.call("clear_display")
	if root.visible:
		_fail("FAIL boost HUD root stayed up after clear_display")
	walker.queue_free()
	hud.queue_free()
