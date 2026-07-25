## Full-bleed EccentriCity title shown while the spawn district boots.
## Covers the empty VoxelTerrain so the long bake does not look like a hang.
class_name LoadingSplash
extends CanvasLayer

const TITLE_TEX := preload("res://assets/branding/eccentricity_title.png")
## Warm dusk from the title art — fills letterbox bars if the window aspect differs.
const BG_COLOR := Color(0.22, 0.14, 0.10, 1.0)
const FADE_OUT_SEC := 0.55

var _root: Control
var _status: Label
var _fading: bool = false


func _ready() -> void:
	layer = 50
	name = "LoadingSplash"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	var art := TextureRect.new()
	art.name = "TitleArt"
	art.texture = TITLE_TEX
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(art)

	## Soft bottom scrim so status text stays readable over busy skyline.
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(0.04, 0.02, 0.02, 0.55)
	scrim.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	scrim.offset_top = -110.0
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(scrim)

	_status = Label.new()
	_status.name = "Status"
	_status.text = "Loading EccentriCity…"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_top = -88.0
	_status.offset_bottom = -28.0
	_status.add_theme_font_size_override("font_size", 22)
	_status.add_theme_color_override("font_color", Color(1.0, 0.94, 0.82, 0.95))
	_status.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.02, 0.85))
	_status.add_theme_constant_override("outline_size", 4)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_status)


func status_label() -> Label:
	return _status


func set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func show_splash(status: String = "Loading EccentriCity…") -> void:
	_fading = false
	set_status(status)
	visible = true
	if _root != null:
		_root.modulate = Color.WHITE


func hide_splash() -> void:
	if not visible or _fading:
		return
	_fading = true
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, FADE_OUT_SEC).set_ease(Tween.EASE_IN).set_trans(
		Tween.TRANS_CUBIC
	)
	tw.tween_callback(func() -> void:
		visible = false
		_fading = false
		if _root != null:
			_root.modulate = Color.WHITE
	)
