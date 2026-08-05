## Top-centre heading rose. North is world −Z (same convention as CityWalker / the minimap).
##
## The ring turns under a fixed caret so the letter at the top is the direction the body faces.
## Pitch and camera orbit are ignored on purpose: a compass that swings with look-up would lie
## about which way the character is pointed for travel.
class_name PlayerCompassHud
extends CanvasLayer

const SIZE_PX := 72.0
## The strip of screen top-centre belongs to: margin above the disc, and the heading line under it.
## Published because anything else that wants top-centre has to start below `band_bottom()` —
## the Siege strip used to open at y=18 and read "attack from the west" across the rose that was the
## only thing on screen saying which way west is.
const TOP_MARGIN := 10.0
const HEADING_H := 18.0
## Bottom edge of the compass in screen pixels. Other top-centre HUDs anchor under this.
const BAND_BOTTOM := TOP_MARGIN + SIZE_PX + HEADING_H
const RING_COLOR := Color(0.75, 0.88, 0.92, 0.9)
const CARDINAL_COLOR := Color(0.95, 0.97, 1.0, 0.95)
const NORTH_COLOR := Color(1.0, 0.45, 0.38, 0.98)
const CARET_COLOR := Color(0.98, 0.92, 0.45, 0.95)
const DISC_COLOR := Color(0.04, 0.06, 0.08, 0.72)
const ROSE_LIGHT := Color(0.88, 0.93, 0.96, 0.92)
const ROSE_DARK := Color(0.42, 0.52, 0.58, 0.9)
const ROSE_NORTH_LIGHT := Color(1.0, 0.55, 0.48, 0.96)
const ROSE_NORTH_DARK := Color(0.62, 0.22, 0.18, 0.95)
const ROSE_INTER_LIGHT := Color(0.7, 0.78, 0.82, 0.75)
const ROSE_INTER_DARK := Color(0.32, 0.4, 0.45, 0.8)

## Labels and their bearing from north, clockwise in degrees (N=0, E=90, S=180, W=270).
const CARDINALS: Array[Dictionary] = [
	{"letter": "N", "deg": 0.0},
	{"letter": "E", "deg": 90.0},
	{"letter": "S", "deg": 180.0},
	{"letter": "W", "deg": 270.0},
]

var _walker: Node
var _root: Control
var _rose: Control
var _heading_label: Label
## Last drawn yaw, so we do not queue_redraw every frame when standing still.
var _drawn_yaw: float = INF


func _ready() -> void:
	layer = UiLayers.HUD_COMPASS
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var panel := Control.new()
	panel.name = "CompassPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -SIZE_PX * 0.5
	panel.offset_right = SIZE_PX * 0.5
	panel.offset_top = TOP_MARGIN
	panel.offset_bottom = BAND_BOTTOM
	_root.add_child(panel)

	_rose = Control.new()
	_rose.name = "Rose"
	_rose.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rose.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_rose.offset_bottom = SIZE_PX
	_rose.draw.connect(_on_rose_draw)
	panel.add_child(_rose)

	_heading_label = Label.new()
	_heading_label.name = "Heading"
	_heading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading_label.add_theme_font_size_override("font_size", 12)
	_heading_label.add_theme_color_override("font_color", Color(0.82, 0.9, 0.88, 0.9))
	_heading_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_heading_label.add_theme_constant_override("outline_size", 2)
	_heading_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_heading_label.offset_top = -16.0
	_heading_label.text = "N"
	panel.add_child(_heading_label)

	set_process(false)


func bind_walker(walker: Node) -> void:
	_walker = walker
	_drawn_yaw = INF
	set_process(_walker != null and is_instance_valid(_walker))
	if is_processing():
		_refresh()


func clear_display() -> void:
	_walker = null
	set_process(false)


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if _walker == null or not is_instance_valid(_walker):
		return
	var yaw := 0.0
	if _walker.has_method("get_yaw"):
		yaw = float(_walker.call("get_yaw"))
	elif _walker is Node3D:
		yaw = (_walker as Node3D).rotation.y
	if is_finite(_drawn_yaw) and absf(angle_difference(_drawn_yaw, yaw)) < 0.002:
		return
	_drawn_yaw = yaw
	_rose.queue_redraw()
	_heading_label.text = heading_label(yaw)


## Bearing the body faces, degrees clockwise from north (0=N, 90=E).
static func heading_degrees(yaw: float) -> float:
	## yaw 0 → forward −Z (north). Positive yaw turns left (CCW), so east is −90°.
	var deg := rad_to_deg(-yaw)
	return fposmod(deg, 360.0)


static func heading_label(yaw: float) -> String:
	var deg := heading_degrees(yaw)
	var names: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	var idx := int(floor((deg + 22.5) / 45.0)) % 8
	return "%s %d°" % [names[idx], int(round(deg)) % 360]


func _on_rose_draw() -> void:
	var center := Vector2(SIZE_PX * 0.5, SIZE_PX * 0.5)
	var radius := SIZE_PX * 0.44
	_rose.draw_circle(center, radius + 4.0, DISC_COLOR)
	_rose.draw_arc(center, radius, 0.0, TAU, 48, RING_COLOR, 1.5, true)

	## Fixed caret at the top: the direction the character faces.
	var caret := PackedVector2Array([
		Vector2(center.x, center.y - radius - 2.0),
		Vector2(center.x - 5.0, center.y - radius + 8.0),
		Vector2(center.x + 5.0, center.y - radius + 8.0),
	])
	_rose.draw_colored_polygon(caret, CARET_COLOR)

	var yaw := _drawn_yaw if is_finite(_drawn_yaw) else 0.0
	## Rotate the rose so the facing bearing sits under the caret.
	var face := heading_degrees(yaw)
	## Sit the letters just inside the ring — an earlier inset left a dead disc in the middle
	## with the cardinals clustered like a tiny inner dial.
	var letter_radius := (radius - 3.0) * 0.8
	_draw_compass_rose(center, letter_radius * 0.62, face)
	var font := ThemeDB.fallback_font
	var font_size := 16
	var ascent := font.get_ascent(font_size)
	for card: Dictionary in CARDINALS:
		var letter: String = str(card["letter"])
		var bearing: float = float(card["deg"])
		## Angle on the dial: 0 at top, clockwise. Subtract facing so that letter moves.
		var dial := deg_to_rad(bearing - face) - PI * 0.5
		var at := center + Vector2(cos(dial), sin(dial)) * letter_radius
		var color := NORTH_COLOR if letter == "N" else CARDINAL_COLOR
		var size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		## draw_string's point is the baseline, not the glyph centre. A constant screen-space
		## fudge (the old +size.y*0.35) shifted every letter the same way and moved the whole
		## letter circle off the disc's centre.
		var baseline := Vector2(at.x - size.x * 0.5, at.y - size.y * 0.5 + ascent)
		_rose.draw_string(
			font,
			baseline,
			letter,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			color
		)


## Classic 8-point rose: split diamonds for cardinals (north tinted) and smaller intercardinals.
## Rotates with `face` so the red tip stays under N.
func _draw_compass_rose(center: Vector2, outer: float, face: float) -> void:
	var hub := outer * 0.14
	var inter_outer := outer * 0.58
	var half_width := outer * 0.18
	## Intercardinals under the cardinals so the main points sit on top.
	for i: int in 4:
		var bearing := 45.0 + float(i) * 90.0
		_draw_rose_petal(
			center,
			inter_outer,
			hub,
			half_width * 0.7,
			bearing,
			face,
			ROSE_INTER_LIGHT,
			ROSE_INTER_DARK
		)
	for i: int in 4:
		var bearing := float(i) * 90.0
		var light := ROSE_NORTH_LIGHT if i == 0 else ROSE_LIGHT
		var dark := ROSE_NORTH_DARK if i == 0 else ROSE_DARK
		_draw_rose_petal(center, outer, hub, half_width, bearing, face, light, dark)
	_rose.draw_circle(center, hub * 0.85, Color(0.12, 0.16, 0.18, 0.95))
	_rose.draw_circle(center, hub * 0.35, ROSE_LIGHT)


func _draw_rose_petal(
	center: Vector2,
	tip_r: float,
	hub_r: float,
	half_w: float,
	bearing: float,
	face: float,
	light: Color,
	dark: Color
) -> void:
	## Same dial convention as the letters: 0° at top when facing north.
	var dial := deg_to_rad(bearing - face) - PI * 0.5
	var dir := Vector2(cos(dial), sin(dial))
	var perp := Vector2(-dir.y, dir.x)
	var tip := center + dir * tip_r
	var left := center + perp * half_w
	var right := center - perp * half_w
	var hub := center + dir * hub_r
	_rose.draw_colored_polygon(PackedVector2Array([tip, left, hub]), light)
	_rose.draw_colored_polygon(PackedVector2Array([tip, hub, right]), dark)
