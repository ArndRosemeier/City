## The Help sheet: what the systems are, and what each kind of district is for.
##
## The copy is not in this file. It lives in `assets/help.md` and is edited in the gamedata
## editor's Help tab, because the one thing a help text has to be is easy to fix — a sentence
## that stops being true should not need a programmer, a rebuild, or a BBCode lesson.
##
## Scrollable rather than paged: there is more here than fits a screen, and a modal that hides
## half its content behind a Next button is how a player misses the district they are standing
## in. `MarkdownToBbcode` does the rendering; this panel only owns the frame and the cursor.
class_name HelperModal
extends CanvasLayer

signal opened
signal closed

const MarkdownToBbcodeScript := preload("res://scripts/city/markdown_to_bbcode.gd")

const HELP_PATH := "res://assets/help.md"

const PANEL_W := 660.0
## Air above and below the sheet. Everything else is the sheet — the text is long enough that
## a shorter panel just means more scrolling.
const FRAME_MARGIN := 44
const PANEL_BG := Color(0.06, 0.07, 0.09, 0.95)
const BODY_COLOR := Color(0.88, 0.88, 0.84)
const TITLE_COLOR := Color(0.95, 0.9, 0.8)

var _open: bool = false
var _catcher: Control = null
var _panel: PanelContainer = null
var _scroll: ScrollContainer = null
var _body: RichTextLabel = null


func _ready() -> void:
	layer = UiLayers.MODAL_HELPER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	reload_text()
	visible = false
	set_process_unhandled_input(true)


func is_open() -> bool:
	return _open


func open_panel() -> void:
	if _open:
		return
	_open = true
	## Re-read on every open: the editor writes `help.md` while the game may already be running.
	reload_text()
	visible = true
	_scroll.scroll_vertical = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	opened.emit()


func close_panel() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit()


func toggle_panel() -> void:
	if _open:
		close_panel()
	else:
		open_panel()


## The rendered sheet, for tests that need to know the file made it through the converter.
func body_text() -> String:
	return "" if _body == null else _body.text


## Read `assets/help.md` and hand it to the converter. A missing or empty help file is a broken
## build, not a panel with nothing in it — say so.
func reload_text() -> void:
	if _body == null:
		push_error("HelperModal.reload_text: called before the panel was built")
		return
	var markdown := _read_help_markdown()
	_body.text = MarkdownToBbcodeScript.convert(markdown)


func _read_help_markdown() -> String:
	if not FileAccess.file_exists(HELP_PATH):
		push_error("HelperModal: missing %s" % HELP_PATH)
		return ""
	var file := FileAccess.open(HELP_PATH, FileAccess.READ)
	if file == null:
		push_error("HelperModal: cannot open %s" % HELP_PATH)
		return ""
	var text := file.get_as_text()
	if text.strip_edges().is_empty():
		push_error("HelperModal: %s is empty" % HELP_PATH)
	return text


func _build_ui() -> void:
	_catcher = Control.new()
	_catcher.name = "Catcher"
	_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.gui_input.connect(_on_catcher_input)
	add_child(_catcher)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.02, 0.03, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_catcher.add_child(dim)

	## A margin frame rather than a CenterContainer: the sheet takes the height the window can
	## spare and the ScrollContainer inside it owns the overflow, which a centred panel sized to
	## its own content cannot do.
	var frame := MarginContainer.new()
	frame.name = "Frame"
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		frame.add_theme_constant_override("margin_%s" % side, FRAME_MARGIN)
	_catcher.add_child(frame)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(PANEL_W, 0.0)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.size_flags_vertical = Control.SIZE_FILL
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = PANEL_BG
	panel_sb.set_corner_radius_all(10)
	panel_sb.set_border_width_all(1)
	panel_sb.border_color = Color(0.72, 0.55, 0.32, 0.55)
	panel_sb.content_margin_left = 20
	panel_sb.content_margin_right = 20
	panel_sb.content_margin_top = 16
	panel_sb.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", panel_sb)
	frame.add_child(_panel)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.add_theme_constant_override("separation", 12)
	_panel.add_child(col)

	var title := Label.new()
	title.name = "Title"
	title.text = "Help"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", TITLE_COLOR)
	col.add_child(title)

	_scroll = ScrollContainer.new()
	_scroll.name = "BodyScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_scroll)

	_body = RichTextLabel.new()
	_body.name = "Body"
	_body.bbcode_enabled = true
	## The ScrollContainer above scrolls; the label grows to its text instead of scrolling itself.
	_body.fit_content = true
	_body.scroll_active = false
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 15)
	_body.add_theme_color_override("default_color", BODY_COLOR)
	_scroll.add_child(_body)

	var close_btn := Button.new()
	close_btn.name = "Close"
	close_btn.text = "Got it"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close_panel)
	col.add_child(close_btn)


func _on_catcher_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_RIGHT:
		return
	## Only the dim dismisses — a click on the sheet itself must not close it.
	if not _panel.get_global_rect().has_point(mb.position):
		close_panel()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	var ek := event as InputEventKey
	if ek != null and ek.pressed and not ek.echo:
		if ek.keycode == KEY_ESCAPE or ek.physical_keycode == KEY_ESCAPE:
			close_panel()
			get_viewport().set_input_as_handled()
