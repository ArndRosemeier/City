## Every street door must be reachable: a walker standing on the pavement has to get to
## the leaf without climbing. This bakes a spread of districts and walks outward from each
## recorded doorway, failing on any door hidden behind a mass.
##
## Run: powershell -File tools\run_test.ps1 test_door_access
extends Node

const DistrictBakeJobScript := preload("res://scripts/city/district_bake_job.gd")

const WORLD_SEED := 42
## Downtown, mid-rise, town fabric and two more tiles: the amalgamation and party-wall
## rules behave differently per density, and a needle tile hides a needle bug.
const COORDS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, 0),
	Vector2i(0, 1),
	Vector2i(-1, 1),
	Vector2i(2, -1),
]
## Voxels of approach a door needs. 4 = 2 m, enough to stand and swing a leaf.
const CLEAR := 4
## Clear voxels above the walking surface: the walker is 3 tall and needs a hat.
const HEADROOM := 4
## A stoop or kerb is fine; anything taller is a wall to the walker.
const MAX_STEP := 2
## How far below the last surface a step down may go before the path counts as broken.
const MAX_DROP := 3
const MAX_REPORTS := 12


func _ready() -> void:
	var failed := false
	var doors := 0
	var blocked := 0
	var edge := 0
	var reports: Array[String] = []
	for coord in COORDS:
		var payload: Dictionary = DistrictBakeJobScript.bake({
			"coord": coord,
			"world_seed": WORLD_SEED,
			"quality": DistrictBakeJobScript.QUALITY_FULL,
			"bake_nav": false,
		})
		if not bool(payload.get("ok", false)):
			push_error("FAIL bake %s: %s" % [coord, payload.get("error", "?")])
			failed = true
			continue
		var gen: DistrictGenerator = payload.get("generator") as DistrictGenerator
		var volume: NativeOfflineVoxelVolume = gen.get_offline_volume()
		if volume == null:
			push_error("FAIL bake %s has no offline volume" % coord)
			failed = true
			continue
		var origin: Vector3i = payload.get("origin_vox", Vector3i.ZERO) as Vector3i
		var theme := DistrictTheme.for_district(WORLD_SEED, coord)
		var here := 0
		var here_doors := 0
		for door_v in payload.get("lot_doorways", []):
			var door: CastleDoorway = door_v as CastleDoorway
			## A door on the tile seam opens onto voxels this bake never wrote; the
			## neighbouring tile owns them.
			if _leaves_tile(gen, origin, door):
				edge += 1
				continue
			doors += 1
			here_doors += 1
			var hit := _blocked_approach(volume, origin, door)
			if hit.is_empty():
				continue
			here += 1
			blocked += 1
			if blocked == 1:
				_probe(volume, origin, door)
			if reports.size() < MAX_REPORTS:
				reports.append(
					"    %s %s door at %s faces %s: %s %d vox out (mat %d)"
					% [
						coord,
						theme.display_name,
						door.center,
						-door.axis,
						str(hit["why"]),
						int(hit["dist"]),
						int(hit["mat"]),
					]
				)
		print("  %s %s: %d doors, %d blocked" % [coord, theme.display_name, here_doors, here])
	for line in reports:
		print(line)
	if doors <= 0:
		push_error("FAIL no lot doorways in any baked district")
		failed = true
	elif blocked > 0:
		push_error(
			"FAIL %d of %d street doors are blocked within %d voxels"
			% [blocked, doors, CLEAR]
		)
		failed = true
	print("  doors: %d checked, %d blocked, %d skipped on the tile seam" % [doors, blocked, edge])
	print("RESULT: %s" % ("OK" if not failed else "FAILED"))
	get_tree().quit(1 if failed else 0)


func _leaves_tile(gen: DistrictGenerator, origin: Vector3i, door: CastleDoorway) -> bool:
	var far: Vector2i = door.center - door.axis * (CLEAR + 1)
	var x := far.x - origin.x
	var z := far.y - origin.z
	return x < 0 or z < 0 or x >= gen.size_x or z >= gen.size_z


## Material section through the doorway, inside on the left, street on the right, so a
## blocked approach can be read off the log instead of guessed at.
func _probe(volume: NativeOfflineVoxelVolume, origin: Vector3i, door: CastleDoorway) -> void:
	var out := -door.axis
	print("    probe door %s facing %s floor_y=%d" % [door.center, out, door.floor_y])
	for y in range(door.floor_y + 8, door.floor_y - 3, -1):
		var row := ""
		for dist in range(-2, CLEAR + 2):
			var xz: Vector2i = door.center + out * dist
			row += "%4d" % _mat_at(volume, origin, xz, y)
		print("      y%+3d |%s" % [y - door.floor_y, row])
	print("      dist  |  -2  -1   0  +1  +2  +3  +4  +5")


## Walk a body out of the door, one voxel at a time, and report where it gets stuck.
## `axis` points inward, so the pavement lies along -axis. Returns {} when the walker
## reaches CLEAR voxels of open ground.
##
## The threshold sits one voxel above the shell floor: BuildingGrammar fills the ground
## storey solid to floor_y + 1, so that course is what both sides stand on.
func _blocked_approach(
	volume: NativeOfflineVoxelVolume, origin: Vector3i, door: CastleDoorway
) -> Dictionary:
	var out := -door.axis
	var surface := door.floor_y + 1
	for dist in range(1, CLEAR + 1):
		var xz: Vector2i = door.center + out * dist
		var found := _surface_at(volume, origin, xz, surface)
		if found > surface + MAX_STEP:
			return {
				"dist": dist,
				"mat": _mat_at(volume, origin, xz, found),
				"why": "step up %d to" % (found - surface),
			}
		if found < surface - MAX_DROP:
			return {"dist": dist, "mat": 0, "why": "drops away"}
		for h in range(1, HEADROOM + 1):
			var mat := _mat_at(volume, origin, xz, found + h)
			if not _passable(mat):
				return {"dist": dist, "mat": mat, "why": "no headroom"}
		surface = found
	return {}


## Topmost solid voxel the walker could step onto from `from`, or the bottom of the
## search range when the column is empty (an open drop, not an obstruction). Searching
## no higher than one step up keeps canopies and lintels from reading as ground.
func _surface_at(
	volume: NativeOfflineVoxelVolume, origin: Vector3i, xz: Vector2i, from: int
) -> int:
	var bottom := from - MAX_DROP - 1
	for y in range(from + MAX_STEP, bottom - 1, -1):
		if not _passable(_mat_at(volume, origin, xz, y)):
			return y
	return bottom


## Foliage is deliberately non-solid in this city — a branch over a door is scenery,
## not a barrier (see DistrictGenerator's median planting).
func _passable(mat: int) -> bool:
	return mat == VoxelMaterial.AIR or VoxelMaterial.is_vegetation(mat)


func _mat_at(
	volume: NativeOfflineVoxelVolume, origin: Vector3i, xz: Vector2i, y: int
) -> int:
	return int(
		volume.get_vox(Vector3i(xz.x - origin.x, y - origin.y, xz.y - origin.z))
	)
