## Full-bleed EccentriCity title shown while the spawn district boots.
## Also hosts the mid-game district-type picker (J hop).
class_name LoadingSplash
extends CanvasLayer

signal district_chosen(theme_id: int)

const TITLE_TEX := preload("res://assets/branding/eccentricity_title.png")
## Warm dusk from the title art — fills letterbox bars if the window aspect differs.
const BG_COLOR := Color(0.22, 0.14, 0.10, 1.0)
const FADE_OUT_SEC := 0.55
const PANEL_BG := Color(0.08, 0.05, 0.04, 0.92)
const BTN_NORMAL := Color(0.28, 0.18, 0.12, 0.95)
const BTN_HOVER := Color(0.42, 0.28, 0.16, 1.0)
const BTN_PRESS := Color(0.55, 0.36, 0.18, 1.0)
const TEXT_MAIN := Color(1.0, 0.94, 0.82, 0.98)
const TEXT_MUTED := Color(0.86, 0.78, 0.66, 0.9)

var _root: Control
var _status: Label
var _picker: Control
var _picker_title: Label
var _picker_subtitle: Label
var _fading: bool = false
var _awaiting_choice: bool = false


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
	_status.add_theme_color_override("font_color", TEXT_MAIN)
	_status.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.02, 0.85))
	_status.add_theme_constant_override("outline_size", 4)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_status)

	_build_picker()


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
	_hide_picker()
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


## Blocks until the player picks a district type. Returns a DistrictTheme id.
func prompt_district_choice(
	title_text: String = "Jump to District",
	subtitle_text: String = "Pick a type — we'll teleport you to the nearest matching tile.",
	status_text: String = "Choose a district type",
) -> int:
	if _picker == null:
		push_error("LoadingSplash.prompt_district_choice: picker missing")
		return DistrictTheme.CORE_HIGHRISE
	_fading = false
	visible = true
	if _root != null:
		_root.modulate = Color.WHITE
	if _picker_title != null:
		_picker_title.text = title_text
	if _picker_subtitle != null:
		_picker_subtitle.text = subtitle_text
	_picker.visible = true
	_awaiting_choice = true
	set_status(status_text)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var theme_id: int = await district_chosen
	_awaiting_choice = false
	_hide_picker()
	return theme_id


func _hide_picker() -> void:
	if _picker != null:
		_picker.visible = false
	_awaiting_choice = false


func _build_picker() -> void:
	_picker = Control.new()
	_picker.name = "DistrictPicker"
	_picker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker.mouse_filter = Control.MOUSE_FILTER_STOP
	_picker.visible = false
	_root.add_child(_picker)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.01, 0.01, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_picker.add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picker.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(520, 0)
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = PANEL_BG
	panel_sb.set_corner_radius_all(10)
	panel_sb.set_border_width_all(1)
	panel_sb.border_color = Color(0.72, 0.55, 0.32, 0.55)
	panel_sb.content_margin_left = 22
	panel_sb.content_margin_right = 22
	panel_sb.content_margin_top = 18
	panel_sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", panel_sb)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	_picker_title = Label.new()
	_picker_title.text = "Jump to District"
	_picker_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_picker_title.add_theme_font_size_override("font_size", 28)
	_picker_title.add_theme_color_override("font_color", TEXT_MAIN)
	_picker_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_picker_title.add_theme_constant_override("outline_size", 4)
	vbox.add_child(_picker_title)

	_picker_subtitle = Label.new()
	_picker_subtitle.text = "Pick a type — we'll teleport you to the nearest matching tile."
	_picker_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_picker_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_picker_subtitle.add_theme_font_size_override("font_size", 15)
	_picker_subtitle.add_theme_color_override("font_color", TEXT_MUTED)
	vbox.add_child(_picker_subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	vbox.add_child(spacer)

	for theme_id in range(DistrictTheme.COUNT):
		var theme := DistrictTheme.make(theme_id)
		vbox.add_child(_make_theme_button(theme))


func _make_theme_button(theme: DistrictTheme) -> Button:
	var btn := Button.new()
	btn.name = "Theme_%d" % theme.id
	btn.text = "%s\n%s" % [theme.display_name, theme.blurb]
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.custom_minimum_size = Vector2(0, 58)
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", TEXT_MAIN)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.9))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 0.98, 0.9))
	btn.add_theme_constant_override("outline_size", 0)

	var normal := _btn_style(BTN_NORMAL)
	var hover := _btn_style(BTN_HOVER)
	var pressed := _btn_style(BTN_PRESS)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)

	var id := theme.id
	btn.pressed.connect(func() -> void:
		if not _awaiting_choice:
			return
		district_chosen.emit(id)
	)
	return btn


func _btn_style(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.7, 0.52, 0.28, 0.4)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb
