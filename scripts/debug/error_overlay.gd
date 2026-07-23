## Autoload: shows engine/script errors in a fullscreen-ish popup (not just the console).
## Registers a Logger in _init so early load failures (e.g. main-scene parse errors) appear.
extends CanvasLayer

const MAX_ENTRIES := 40
const LoggerScript := preload("res://scripts/debug/error_overlay_logger.gd")

var _logger: Logger
var _panel: PanelContainer
var _title: Label
var _body: RichTextLabel
var _close_btn: Button
var _pending: Array = []
var _visible_count: int = 0


func _init() -> void:
	var logger = LoggerScript.new()
	logger.configure(self)
	_logger = logger
	OS.add_logger(_logger)


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_panel.visible = false
	## Flush anything that arrived before the UI existed.
	_flush_pending()


func _exit_tree() -> void:
	if _logger != null:
		OS.remove_logger(_logger)
		_logger = null


func enqueue_error(kind: String, detail: String, location: String, _error_type: int) -> void:
	## Filter engine noise that isn't actionable for gameplay.
	if detail.contains("ObjectDB instances leaked"):
		return
	if detail.contains("PagedAllocator"):
		return
	if detail.contains("condition \"!is_inside_tree()\" is true"):
		return
	_pending.append({"kind": kind, "detail": detail, "location": location})
	while _pending.size() > MAX_ENTRIES:
		_pending.pop_front()
	if not is_node_ready() or _panel == null:
		return
	_flush_pending()


func _flush_pending() -> void:
	if _pending.is_empty() or _panel == null:
		return
	var block := ""
	for item in _pending:
		var kind: String = str(item.get("kind", "ERROR"))
		var detail: String = str(item.get("detail", ""))
		var location: String = str(item.get("location", ""))
		var color := "#ff8866" if kind == "SCRIPT" else "#ffaa55"
		block += "[color=%s][b]%s[/b][/color]" % [color, kind]
		if not location.is_empty():
			block += "  [color=#99aacc]%s[/color]" % location
		block += "\n%s\n\n" % detail
		_visible_count += 1
	_pending.clear()
	if _body != null:
		_body.append_text(block)
	_title.text = "Errors (%d) — Esc / Close to dismiss" % _visible_count
	_panel.visible = true
	## Free the mouse so the player can dismiss without fighting capture.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -420.0
	_panel.offset_right = 420.0
	_panel.offset_top = -260.0
	_panel.offset_bottom = 260.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.06, 0.94)
	sb.border_color = Color(0.85, 0.35, 0.25, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", sb)
	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	var header := HBoxContainer.new()
	vbox.add_child(header)
	_title = Label.new()
	_title.text = "Errors"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.add_theme_font_size_override("font_size", 16)
	_title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.65))
	header.add_child(_title)

	_close_btn = Button.new()
	_close_btn.text = "Close"
	_close_btn.focus_mode = Control.FOCUS_NONE
	_close_btn.pressed.connect(_dismiss)
	header.add_child(_close_btn)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = false
	_body.scroll_active = true
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.custom_minimum_size = Vector2(0, 360)
	_body.add_theme_font_size_override("normal_font_size", 13)
	_body.add_theme_color_override("default_color", Color(0.92, 0.9, 0.88))
	vbox.add_child(_body)

	var hint := Label.new()
	hint.text = "Script/engine errors surface here so a gray screen is not a mystery."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.58))
	vbox.add_child(hint)


func _unhandled_input(event: InputEvent) -> void:
	if not _panel.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_dismiss()
			get_viewport().set_input_as_handled()


func _dismiss() -> void:
	_panel.visible = false
	if _body != null:
		_body.clear()
	_visible_count = 0
	_title.text = "Errors"
