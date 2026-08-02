## Far→full must overwrite shared blocks, then AIR-wipe only orphans — never pre-clear ground.
##
## Pre-stamping every far key to AIR left rectangular bedrock voids whenever restamp aborted
## or skipped a key. This pins the orphan-key math and the substrate invariant the fill
## pipeline owes every column.
##
## Run: powershell -File tools\run_test.ps1 test_upgrade_orphan_wipe
extends Node

const OfflineVolumeCommitterScript := preload("res://scripts/city/offline_volume_committer.gd")
const DistrictGeneratorScript := preload("res://scripts/city/district_generator.gd")

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_check_orphan_keys()
	_check_bad_payload_refuses_air()
	_check_ground_slab_has_bedrock()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(0 if not _failed else 1)


func _check_orphan_keys() -> void:
	var prev: Array[Vector3i] = [
		Vector3i(0, 0, 0),
		Vector3i(1, 0, 0),
		Vector3i(2, 3, 4),
		Vector3i(1, 0, 0),  ## duplicate
	]
	var bake := {
		Vector3i(0, 0, 0): PackedByteArray([1, 0]),
		Vector3i(9, 9, 9): PackedByteArray([2, 0]),
	}
	var orphans: Array[Vector3i] = OfflineVolumeCommitterScript.orphan_block_keys(prev, bake)
	if orphans.size() != 2:
		_fail("FAIL orphan count %d want 2" % orphans.size())
		return
	if orphans[0] != Vector3i(1, 0, 0) or orphans[1] != Vector3i(2, 3, 4):
		_fail("FAIL orphan order/content %s" % str(orphans))
		return
	print("OK orphan_block_keys keeps only far-only blocks, deduped")


func _check_bad_payload_refuses_air() -> void:
	var buf := OfflineVolumeCommitterScript.make_buffer_u16(PackedByteArray())
	if buf != null:
		_fail("FAIL empty payload must not become an AIR block buffer")
		return
	var truncated := PackedByteArray()
	truncated.resize(16)
	buf = OfflineVolumeCommitterScript.make_buffer_u16(truncated)
	if buf != null:
		_fail("FAIL truncated payload must not become an AIR block buffer")
		return
	var air := OfflineVolumeCommitterScript.make_buffer_u16(PackedByteArray([0, 0]))
	if air == null:
		_fail("FAIL uniform AIR sentinel must still decode")
		return
	print("OK make_buffer_u16 refuses bad payloads instead of filling AIR")


func _check_ground_slab_has_bedrock() -> void:
	## Small offline slab — every column must keep indestructible bedrock at y=0.
	var gen: DistrictGenerator = DistrictGeneratorScript.new()
	gen.size_x = 48
	gen.size_z = 48
	gen.cell_size = 16
	gen.begin_generate_offline(7, Vector3i.ZERO, Vector2i.ZERO)
	gen.paint_district_ground_slab()
	var volume: NativeOfflineVoxelVolume = gen.get_offline_volume()
	if volume == null:
		_fail("FAIL offline volume missing after ground slab")
		return
	var missing := 0
	var sample: Vector3i = Vector3i(-1, -1, -1)
	for z in range(gen.size_z):
		for x in range(gen.size_x):
			if int(volume.get_vox(Vector3i(x, 0, z))) != VoxelMaterial.BEDROCK:
				missing += 1
				if sample.x < 0:
					sample = Vector3i(x, 0, z)
	if missing > 0:
		_fail(
			"FAIL ground slab left %d columns without BEDROCK at y=0 (first %s)"
			% [missing, str(sample)]
		)
		return
	## Sparse export must include every ground block the live commit will stamp.
	var blocks: Dictionary = volume.export_blocks_u16()
	var want_bx := int(ceili(float(gen.size_x) / 16.0))
	var want_bz := int(ceili(float(gen.size_z) / 16.0))
	var ground_blocks := 0
	for key: Variant in blocks.keys():
		var bp: Vector3i = key
		if bp.y == 0:
			ground_blocks += 1
	if ground_blocks != want_bx * want_bz:
		_fail(
			"FAIL sparse export ground blocks %d want %d (%dx%d)"
			% [ground_blocks, want_bx * want_bz, want_bx, want_bz]
		)
		return
	print("OK ground slab paints bedrock under every column and exports all ground blocks")
	gen.end_generate()
