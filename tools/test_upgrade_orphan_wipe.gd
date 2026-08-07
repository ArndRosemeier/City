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
	_check_ground_orphans_never_wiped()
	_check_oob_ground_orphans_are_wipeable()
	_check_filter_blocks_to_footprint()
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


## In-footprint ground-band orphans must be partitioned out of the AIR wipe set — wiping
## them is the rectangular bedrock void left when a full bake omits a far ground key.
func _check_ground_orphans_never_wiped() -> void:
	var orphans: Array[Vector3i] = [
		Vector3i(1, 0, 0),
		Vector3i(2, -1, 4),
		Vector3i(3, 1, 0),
		Vector3i(4, 2, 1),
	]
	var ground: Array[Vector3i] = OfflineVolumeCommitterScript.ground_orphan_keys(orphans)
	var upper: Array[Vector3i] = OfflineVolumeCommitterScript.upper_orphan_keys(orphans)
	if ground.size() != 2 or ground[0] != Vector3i(1, 0, 0) or ground[1] != Vector3i(2, -1, 4):
		_fail("FAIL ground_orphan_keys %s" % str(ground))
		return
	if upper.size() != 2 or upper[0] != Vector3i(3, 1, 0) or upper[1] != Vector3i(4, 2, 1):
		_fail("FAIL upper_orphan_keys %s" % str(upper))
		return
	if ground.size() + upper.size() != orphans.size():
		_fail("FAIL ground/upper partition lost keys")
		return
	print("OK ground orphans are partitioned out of the AIR wipe set")


## Edge-bleed blocks (e.g. far canopy at z=-1) are ground-band but outside the footprint —
## they must wipe with the upper set, not trip the refuse-AIR guard.
func _check_oob_ground_orphans_are_wipeable() -> void:
	var size_x := 48
	var size_z := 48
	var orphans: Array[Vector3i] = [
		Vector3i(1, 0, 0), ## in footprint, ground — refuse
		Vector3i(2, 0, -1), ## OOB south, ground — wipe
		Vector3i(-1, 0, 1), ## OOB west, ground — wipe
		Vector3i(3, 1, 0), ## upper — wipe
		Vector3i(34, 0, -1), ## classic far→full spam key shape — wipe
	]
	var ground: Array[Vector3i] = OfflineVolumeCommitterScript.ground_orphan_keys(
		orphans, size_x, size_z
	)
	var wipe: Array[Vector3i] = OfflineVolumeCommitterScript.upper_orphan_keys(
		orphans, size_x, size_z
	)
	if ground.size() != 1 or ground[0] != Vector3i(1, 0, 0):
		_fail("FAIL footprint ground orphans %s" % str(ground))
		return
	if wipe.size() != 4:
		_fail("FAIL wipeable orphans count %d want 4: %s" % [wipe.size(), str(wipe)])
		return
	if not OfflineVolumeCommitterScript.block_intersects_footprint(Vector3i(0, 0, 0), size_x, size_z):
		_fail("FAIL origin block should intersect footprint")
		return
	if OfflineVolumeCommitterScript.block_intersects_footprint(Vector3i(2, 0, -1), size_x, size_z):
		_fail("FAIL z=-1 block must be outside footprint")
		return
	if ground.size() + wipe.size() != orphans.size():
		_fail("FAIL footprint partition lost keys")
		return
	print("OK out-of-footprint ground orphans are wipeable")


func _check_filter_blocks_to_footprint() -> void:
	var blocks := {
		Vector3i(0, 0, 0): PackedByteArray([1, 0]),
		Vector3i(2, 0, -1): PackedByteArray([2, 0]),
		Vector3i(-1, 1, 0): PackedByteArray([3, 0]),
		Vector3i(1, 2, 1): PackedByteArray([4, 0]),
	}
	var filtered: Dictionary = OfflineVolumeCommitterScript.filter_blocks_to_footprint(
		blocks, 48, 48
	)
	if filtered.size() != 2:
		_fail("FAIL filter kept %d keys want 2" % filtered.size())
		return
	if not filtered.has(Vector3i(0, 0, 0)) or not filtered.has(Vector3i(1, 2, 1)):
		_fail("FAIL filter keys %s" % str(filtered.keys()))
		return
	print("OK filter_blocks_to_footprint drops edge-bleed keys")


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
