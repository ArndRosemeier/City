## Planned geometry for an Arena-theme district (district-local voxel coords).
##
## Survives the composer so runtime can place summon boards, lifts, and wipe the pit.
class_name ArenaLayout
extends RefCounted

## Outer footprint of the rounded mass (axis-aligned bounds; corners are filleted in voxels).
var outer_rect: Rect2i = Rect2i()
## Hard rectangular sand pit (inclusive min, exclusive end in XZ).
var pit_rect: Rect2i = Rect2i()
## Top solid Y of the sand / walk surface in the pit.
var pit_floor_y: int = 0
## Inner face of the pit wall rises to this solid Y (exclusive air above).
var pit_wall_top_y: int = 0
## Seating deck Y (spectator walk) — above `pit_wall_top_y` so the pit wall does not block view.
var seating_y: int = 0
## Top solid Y of the low summon-board parapets on the seating deck.
var board_wall_top_y: int = 0
## Corner fillet radius in voxels used when painting the outer rounded mass.
var corner_radius: int = 0
## Gate tunnel footprints on each side (district-local XZ), facing inward.
var gate_rects: Array[Rect2i] = []
## Board mount: center column on the seating face + outward normal (gate_dir style).
## Each entry: { "origin": Vector2i, "dir": Vector2i, "yaw": float }
var board_mounts: Array[Dictionary] = []
## Summon lift pad centers in the pit (district-local XZ), one near each side.
var lift_pads: Array[Vector2i] = []


## Clear air volume above the sand for decorate / wipe (lift pads stay clear).
func pit_volume(air_h: int = 8) -> RoomVolume:
	var v := RoomVolume.make(pit_rect, pit_floor_y, air_h)
	for pad: Vector2i in lift_pads:
		v.keep_clear.append(Rect2i(pad.x - 4, pad.y - 4, 9, 9))
	return v


func describe() -> String:
	return (
		(
			"arena outer=%s pit=%s floor_y=%d wall_top=%d seating_y=%d board_wall=%d r=%d boards=%d lifts=%d"
			% [
				outer_rect,
				pit_rect,
				pit_floor_y,
				pit_wall_top_y,
				seating_y,
				board_wall_top_y,
				corner_radius,
				board_mounts.size(),
				lift_pads.size(),
			]
		)
	)
