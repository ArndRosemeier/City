## Debug cheat modal. Opens on Ctrl+Shift+F12 — a handful of fill / teleport buttons on the
## left, and a large text area on the right that CityRoot (or future probes) can dump into.
##
## Deliberately not remappable and deliberately a modal of its own: the gem-fill hotkey used to
## fire invisibly, which is useless when you want to see what it did, and burying these under
## Settings would put a one-press "give me everything" next to graphics knobs.
class_name CheatPanel
extends CanvasLayer

signal opened
signal closed
signal fill_gems_requested
signal fill_recipes_requested
signal teleport_nearest_recipe_requested
signal teleport_cave_cage_requested
signal teleport_murderer_requested
signal teleport_alchemy_lab_requested

const PANEL_WIDTH := 720.0
const PANEL_HEIGHT := 480.0
const BUTTON_COL_PX := 220.0
const HINT_COLOR := Color(0.76, 0.79, 0.86)

var _open: bool = false
var _dim: ColorRect
var _panel: PanelContainer
var _button_box: VBoxContainer
var _log: TextEdit
var _close_button: Button


func _ready() -> void:
	layer = UiLayers.MODAL_CHEAT
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false
	set_process_unhandled_input(true)


func is_open() -> bool:
	return _open


func open_panel() -> void:
	if _open:
		return
	_open = true
	visible = true
	_dim.visible = true
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	opened.emit()


func close_panel() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_dim.visible = false
	_panel.visible = false
	closed.emit()


func toggle_panel() -> void:
	if _open:
		close_panel()
	else:
		open_panel()


## Append a line to the debug log. The caret stays at the end so a flood of updates is readable.
func append_log(line: String) -> void:
	if _log == null:
		return
	if _log.text.is_empty():
		_log.text = line
	else:
		_log.text += "\n" + line
	_log.scroll_vertical = _log.get_line_count()


func set_log(text: String) -> void:
	if _log == null:
		return
	_log.text = text
	_log.scroll_vertical = _log.get_line_count()


func clear_log() -> void:
	set_log("")


func log_view() -> TextEdit:
	return _log


func button_column() -> VBoxContainer:
	return _button_box


func close_button() -> Button:
	return _close_button


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()


func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0.02, 0.03, 0.05, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.visible = false
	_dim.gui_input.connect(_on_dim_input)
	add_child(_dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.visible = false
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 14)
	_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.name = "Root"
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title_row := HBoxContainer.new()
	title_row.name = "TitleRow"
	title_row.add_theme_constant_override("separation", 8)
	root.add_child(title_row)

	var title := Label.new()
	title.text = "Cheat"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	var hint := Label.new()
	hint.text = "Ctrl+Shift+F12 / Esc"
	hint.modulate = HINT_COLOR
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(hint)

	_close_button = Button.new()
	_close_button.name = "Close"
	_close_button.text = "×"
	_close_button.flat = true
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.tooltip_text = "Close (Esc)"
	_close_button.custom_minimum_size = Vector2(30.0, 30.0)
	_close_button.add_theme_font_size_override("font_size", 18)
	_close_button.pressed.connect(close_panel)
	title_row.add_child(_close_button)

	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	root.add_child(body)

	## Left column owns the verbs. Extra room below the first three is intentional: new cheats
	## land here without reshuffling the log.
	_button_box = VBoxContainer.new()
	_button_box.name = "Buttons"
	_button_box.custom_minimum_size = Vector2(BUTTON_COL_PX, 0.0)
	_button_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_button_box.add_theme_constant_override("separation", 8)
	body.add_child(_button_box)

	_add_action_button("Fill gems", "Top every gem type to 99", fill_gems_requested)
	_add_action_button("Fill recipes", "Learn every recipe in the cookbook", fill_recipes_requested)
	_add_action_button(
		"Teleport to recipe",
		"Jump near the closest landmark recipe scroll (not chests)",
		teleport_nearest_recipe_requested
	)
	_add_action_button(
		"Teleport to cave cage",
		"Hop to a Hill district and stand beside the Unique boss cage",
		teleport_cave_cage_requested
	)
	_add_action_button(
		"Teleport to murderer",
		"Hop to a district with wanted bills and stand by a poster",
		teleport_murderer_requested
	)
	_add_action_button(
		"Teleport to alchemy lab",
		"Hop to a city lab and stand by the apothecary sign",
		teleport_alchemy_lab_requested
	)

	## Keeps the first buttons at the top when the column grows taller than its content.
	var spacer := Control.new()
	spacer.name = "FutureButtonRoom"
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size = Vector2(0.0, 80.0)
	_button_box.add_child(spacer)

	var log_panel := PanelContainer.new()
	log_panel.name = "LogPanel"
	log_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var log_style := StyleBoxFlat.new()
	log_style.bg_color = Color(0.04, 0.05, 0.07, 0.95)
	log_style.set_corner_radius_all(6)
	log_style.content_margin_left = 8
	log_style.content_margin_right = 8
	log_style.content_margin_top = 8
	log_style.content_margin_bottom = 8
	log_panel.add_theme_stylebox_override("panel", log_style)
	body.add_child(log_panel)

	var log_col := VBoxContainer.new()
	log_col.add_theme_constant_override("separation", 6)
	log_panel.add_child(log_col)

	var log_title := Label.new()
	log_title.text = "District report / log"
	log_title.modulate = HINT_COLOR
	log_title.add_theme_font_size_override("font_size", 13)
	log_col.add_child(log_title)

	_log = TextEdit.new()
	_log.name = "Log"
	_log.editable = false
	_log.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.placeholder_text = "Opens with a district report. Cheat actions append below."
	_log.add_theme_font_size_override("font_size", 13)
	log_col.add_child(_log)


func _add_action_button(label: String, tip: String, sig: Signal) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.tooltip_text = tip
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func() -> void: sig.emit())
	_button_box.add_child(btn)
	return btn


func _on_dim_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		close_panel()
