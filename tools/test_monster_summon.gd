## N-key summon panel: Random first, cached world aim (meteor path), combat aim untouched.
##
## Run: powershell -File tools\run_test.ps1 test_monster_summon
extends Node

const MonsterSummonPanelScript := preload("res://scripts/city/monster_summon_panel.gd")
const PlayerControlsScript := preload("res://scripts/city/player_controls.gd")
const BODY_CLEARANCE_M := 0.06

var _failed := false


class TestCity:
	extends CityRoot

	func _ready() -> void:
		pass

	func bind_player(walker: CityWalker) -> void:
		_walker = walker

	func bind_undead(director: UndeadInvasionDirector) -> void:
		_undead = director

	func _ensure_undead_director() -> void:
		if _undead == null or not is_instance_valid(_undead):
			push_error("TestCity: undead director not bound before summon")
			assert(false, "TestCity: no undead")


## A real walker whose cursor aim is scripted, so the summon path is exercised with the
## walker type CityRoot actually holds rather than a look-alike.
class AimStub:
	extends CityWalker
	var aim: Dictionary = {}

	func aim_world_at_cursor() -> Dictionary:
		return aim


class RecordingDirector:
	extends UndeadInvasionDirector

	var last_body_id: String = ""
	var last_pos: Vector3 = Vector3.INF
	var spawn_count: int = 0

	func spawn_monster_by_id(body_id: String, world_pos: Vector3, _body_seed: int = -1) -> UndeadUnit:
		last_body_id = body_id
		last_pos = world_pos
		spawn_count += 1
		var unit := UndeadUnit.new()
		unit.name = "SummonProbe"
		add_child(unit)
		unit.global_position = world_pos
		unit.set_physics_process(false)
		unit.set_process(false)
		return unit


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_test_key_bindings()
	_test_summon_list()
	_test_cached_aim_spawn()
	_test_combat_aim_path_untouched()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _test_key_bindings() -> void:
	var ctl := PlayerControlsScript.new()
	var summon: Dictionary = ctl.default_binding("monster_summon")
	var day: Dictionary = ctl.default_binding("day_night")
	if int(summon.get("code", 0)) != int(KEY_N):
		_fail("FAIL monster_summon default is not KEY_N")
		return
	if int(day.get("code", 0)) != int(KEY_Y):
		_fail("FAIL day_night default is not KEY_Y")
		return
	print("keys: N=summon, Y=day/night")


func _test_summon_list() -> void:
	var labels: PackedStringArray = MonsterSummonPanelScript.list_labels()
	if labels.is_empty() or labels[0] != "Random":
		_fail("FAIL summon list does not start with Random")
		return
	var ids: PackedStringArray = MonsterSummonPanelScript.summonable_ids()
	if ids.is_empty():
		_fail("FAIL summonable_ids is empty")
		return
	if not ids.has("kaykit/Skeleton_Minion"):
		_fail("FAIL summonable_ids missing kaykit/Skeleton_Minion")
		return
	## Non-spawnable catalogue rows (empty slots) must not appear.
	if ids.has("flying/Pigeon"):
		_fail("FAIL non-spawnable flying/Pigeon listed")
		return
	var panel: CanvasLayer = MonsterSummonPanelScript.new()
	add_child(panel)
	if panel.layer != UiLayers.MODAL_MONSTER_SUMMON:
		_fail("FAIL summon panel layer %d" % panel.layer)
		panel.queue_free()
		return
	panel.call("open_panel")
	if not bool(panel.call("is_open")):
		_fail("FAIL summon panel did not open")
		panel.queue_free()
		return
	if str(panel.call("selected_monster_id")) != "":
		_fail("FAIL default selection is not Random")
		panel.queue_free()
		return
	panel.call("close_panel")
	panel.queue_free()
	print("summon UI: Random first, %d spawnable bodies" % ids.size())


func _test_cached_aim_spawn() -> void:
	var city := TestCity.new()
	city.name = "TestCity"
	add_child(city)
	var director := RecordingDirector.new()
	director.name = "RecordingDirector"
	city.add_child(director)
	city.bind_undead(director)

	var aim_pos := Vector3(40.0, 1.0, 28.0)
	var stub := AimStub.new()
	stub.name = "AimStub"
	stub.aim = {"point": aim_pos, "normal": Vector3.UP, "did_hit": true}
	city.add_child(stub)
	stub.set_physics_process(false)
	city.bind_player(stub)
	city._booting = false
	city._game_over = false

	city.capture_summon_aim()
	## Move the stub aim after capture — confirm must use the cached point.
	stub.aim = {
		"point": Vector3(1.0, 0.0, 1.0),
		"normal": Vector3.UP,
		"did_hit": true,
	}
	var unit := city.summon_monster_at_aim("kaykit/Skeleton_Minion")
	if unit == null:
		_fail("FAIL summon_monster_at_aim returned null on cached hit")
		city.queue_free()
		return
	var expected := aim_pos + Vector3.UP * BODY_CLEARANCE_M
	if director.last_pos.distance_to(expected) > 0.001:
		_fail(
			"FAIL spawn used %s want cached aim %s (live stub was moved)"
			% [str(director.last_pos), str(expected)]
		)
		city.queue_free()
		return
	if director.last_body_id != "kaykit/Skeleton_Minion":
		_fail("FAIL spawn body id %s" % director.last_body_id)
		city.queue_free()
		return
	unit.queue_free()

	city._summon_aim = {"point": Vector3.ZERO, "normal": Vector3.UP, "did_hit": false}
	var before := director.spawn_count
	var missed := city.summon_monster_at_aim("kaykit/Skeleton_Minion")
	if missed != null or director.spawn_count != before:
		_fail("FAIL summon_monster_at_aim must not spawn on aim miss")
		if missed != null:
			missed.queue_free()
		city.queue_free()
		return
	print("summon aim: cached hit at %s, miss refused" % str(aim_pos))
	city.queue_free()


## Meteor / world aim stays agent-free; combat still magnets agents (see test_meteor_aim).
func _test_combat_aim_path_untouched() -> void:
	var src := FileAccess.open("res://scripts/city/city_walker.gd", FileAccess.READ)
	if src == null:
		_fail("FAIL cannot read city_walker.gd")
		return
	var text := src.get_as_text()
	src.close()
	if not text.contains("func aim_world_at_cursor() -> Dictionary:"):
		_fail("FAIL aim_world_at_cursor missing")
		return
	if not text.contains("return _aim_ray_at_cursor(false, Vector3.INF, true)"):
		_fail("FAIL aim_world_at_cursor no longer skips agent magnet")
		return
	if not text.contains("var aim := _aim_ray_at_cursor(true, hand)"):
		_fail("FAIL blaster combat aim no longer magnets agents")
		return
	if not text.contains("func _request_infection_meteor() -> void:"):
		_fail("FAIL meteor request path missing")
		return
	if not text.contains("var aim := aim_world_at_cursor()"):
		_fail("FAIL meteor no longer uses aim_world_at_cursor")
		return
	print("combat/meteor aim paths unchanged in city_walker")
