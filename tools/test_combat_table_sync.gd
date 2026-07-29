## Sync guard: CombatTable.resolve must match the Python golden fixture.
##
## Golden: tools/fixtures/combat_effective_stats.json
## Regenerate: python tools/sync_combat_resolve.py --write
##
## Run: powershell -File tools\run_test.ps1 test_combat_table_sync -KeepLog
extends Node

## Preload so portable/headless runs work before global class_name cache exists.
const CombatTableScript := preload("res://scripts/city/combat_table.gd")


var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	CombatTableScript.reload()
	_check_golden_sync()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


func _check_golden_sync() -> void:
	var golden_path: String = CombatTableScript.GOLDEN_PATH
	if not FileAccess.file_exists(golden_path):
		_fail(
			"FAIL missing golden %s — run python tools/sync_combat_resolve.py --write"
			% golden_path
		)
		return

	var f := FileAccess.open(golden_path, FileAccess.READ)
	if f == null:
		_fail("FAIL cannot open %s" % golden_path)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("FAIL golden root must be an object")
		return

	var root: Dictionary = parsed
	var monsters_raw: Variant = root.get("monsters", null)
	if typeof(monsters_raw) != TYPE_DICTIONARY:
		_fail("FAIL golden 'monsters' must be an object")
		return
	var golden: Dictionary = monsters_raw

	var ids: PackedStringArray = CombatTableScript.monster_ids()
	if ids.is_empty():
		_fail("FAIL CombatTable has no monsters")
		return

	var gdscript_ids: Dictionary = {}
	for mid: String in ids:
		gdscript_ids[mid] = true

	for mid: Variant in golden.keys():
		var id_str := str(mid)
		if not gdscript_ids.has(id_str):
			_fail("FAIL golden has monster '%s' but CombatTable does not" % id_str)

	for mid: String in ids:
		if not golden.has(mid):
			_fail(
				(
					"FAIL CombatTable monster '%s' missing from golden — "
					+ "run python tools/sync_combat_resolve.py --write"
				)
				% mid
			)
			continue
		var expected_raw: Variant = golden[mid]
		if typeof(expected_raw) != TYPE_DICTIONARY:
			_fail("FAIL golden monster '%s' payload must be an object" % mid)
			continue
		var expected: Dictionary = expected_raw
		var eff: RefCounted = CombatTableScript.resolve(mid)
		if eff == null:
			_fail("FAIL resolve('%s') returned null" % mid)
			continue
		var actual: Dictionary = eff.call("to_sync_dict")
		_diff_dict(expected, actual, "monster '%s'" % mid)

	if not _failed:
		print("OK combat table sync: %d monsters match golden" % ids.size())


func _diff_dict(expected: Dictionary, actual: Dictionary, prefix: String) -> void:
	for key: Variant in expected.keys():
		var ks := str(key)
		if not actual.has(ks):
			_fail("FAIL %s: missing key '%s' in CombatTable output" % [prefix, ks])
			continue
		_diff_value(expected[ks], actual[ks], "%s.%s" % [prefix, ks])
	for key: Variant in actual.keys():
		var ks := str(key)
		if not expected.has(ks):
			_fail("FAIL %s: unexpected key '%s' from CombatTable" % [prefix, ks])


func _diff_value(expected: Variant, actual: Variant, path: String) -> void:
	var et := typeof(expected)
	var at := typeof(actual)
	if et == TYPE_DICTIONARY and at == TYPE_DICTIONARY:
		_diff_dict(expected, actual, path)
		return
	if et == TYPE_ARRAY and at == TYPE_ARRAY:
		var ea: Array = expected
		var aa: Array = actual
		if ea.size() != aa.size():
			_fail(
				"FAIL %s: array size expected %d got %d (%s vs %s)"
				% [path, ea.size(), aa.size(), str(ea), str(aa)]
			)
			return
		for i in ea.size():
			_diff_value(ea[i], aa[i], "%s[%d]" % [path, i])
		return
	if et == TYPE_FLOAT or et == TYPE_INT or at == TYPE_FLOAT or at == TYPE_INT:
		var ef := float(expected)
		var af := float(actual)
		var er: float = CombatTableScript.round_sync_float(ef)
		var ar: float = CombatTableScript.round_sync_float(af)
		if not is_equal_approx(er, ar):
			_fail("FAIL %s: expected %s got %s" % [path, str(er), str(ar)])
		return
	if str(expected) != str(actual):
		_fail("FAIL %s: expected %s got %s" % [path, str(expected), str(actual)])
