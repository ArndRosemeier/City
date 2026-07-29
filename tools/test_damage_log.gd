## DamageLog records every DamageSource hit and toggles on the damage_log bind (L).
##
## Run: powershell -File tools\run_test.ps1 test_damage_log
extends Node

const PlayerHealthScript := preload("res://scripts/city/player_health.gd")
const DamageSourceScript := preload("res://scripts/city/damage_source.gd")
const PlayerControlsScript := preload("res://scripts/city/player_controls.gd")
const UiLayersScript := preload("res://scripts/city/ui_layers.gd")
const DamageLogScript := preload("res://scripts/debug/damage_log.gd")


func _ready() -> void:
	var failed := false
	var log_node := get_tree().root.get_node_or_null("DamageLog") as DamageLogScript
	if log_node == null:
		push_error("FAIL DamageLog autoload missing")
		print("RESULT: FAILED")
		get_tree().quit(1)
		return
	if int(log_node.layer) != UiLayersScript.DEBUG_DAMAGE_LOG:
		push_error(
			"FAIL DamageLog layer %d != %d"
			% [int(log_node.layer), UiLayersScript.DEBUG_DAMAGE_LOG]
		)
		failed = true

	log_node.call("clear")
	var controls := PlayerControlsScript.new()
	log_node.call("set_controls", controls)
	if bool(log_node.call("is_overlay_enabled")):
		push_error("FAIL overlay should start hidden")
		failed = true

	var hp: RefCounted = PlayerHealthScript.new()
	hp.call("configure", 100.0, 4.0, 6.0)
	var taken: float = float(hp.call("apply_damage", DamageSourceScript.Id.UNDEAD_ORB))
	if not is_equal_approx(taken, 25.0):
		push_error("FAIL expected 25 from orb, got %f" % taken)
		failed = true
	var entries: Array = log_node.call("entries") as Array
	if entries.size() != 1:
		push_error("FAIL expected 1 log entry, got %d" % entries.size())
		failed = true
	else:
		var row: Dictionary = entries[0]
		if str(row.get("victim", "")) != "player":
			push_error("FAIL victim should be player, got %s" % str(row.get("victim", "")))
			failed = true
		if str(row.get("source", "")) != "undead orb":
			push_error("FAIL source label wrong: %s" % str(row.get("source", "")))
			failed = true
		if not is_equal_approx(float(row.get("amount", 0.0)), 25.0):
			push_error("FAIL logged amount %s" % str(row.get("amount", 0.0)))
			failed = true

	## Four orbs kill a 100-pool player — last entry must be fatal.
	hp.call("apply_damage", DamageSourceScript.Id.UNDEAD_ORB)
	hp.call("apply_damage", DamageSourceScript.Id.UNDEAD_ORB)
	hp.call("apply_damage", DamageSourceScript.Id.UNDEAD_ORB)
	entries = log_node.call("entries") as Array
	if entries.size() != 4:
		push_error("FAIL expected 4 entries after lethal sequence, got %d" % entries.size())
		failed = true
	else:
		var last: Dictionary = entries[3]
		if not bool(last.get("fatal", false)):
			push_error("FAIL last orb should be fatal")
			failed = true

	log_node.call("set_overlay_enabled", true)
	if not bool(log_node.call("is_overlay_enabled")):
		push_error("FAIL overlay failed to enable")
		failed = true
	log_node.call("set_overlay_enabled", false)

	var bind: Dictionary = controls.call("default_binding", "damage_log") as Dictionary
	if int(bind.get("code", -1)) != int(KEY_L):
		push_error("FAIL default damage_log bind is not KEY_L")
		failed = true

	print("RESULT: %s" % ("OK" if not failed else "FAILED"))
	get_tree().quit(1 if failed else 0)
