## Helper sheet for the Siege Quarter, opened from the Lodestone console's Details button.
##
## A screen modal rather than another shootable world face: the console already has to be short
## enough to read at a glance, and a second Ui3D next to the crystal would inherit every fight-time
## problem the Lodestone panel already has. Esc / outside click dismisses, like the tower picker.
class_name SiegeDetailsModal
extends CanvasLayer

signal opened
signal closed

const PANEL_W := 460.0

const BODY := (
	"Four outer stones shield the Lodestone. Monsters will try to destroy them — "
	+ "the centre cannot fall while any still stand.\n\n"
	+ "Hell gates send waves on a clock. The forecast names a bearing, not a single mouth: "
	+ "most of the wave pours from that arc, but neighbouring gates still spit harassment. "
	+ "Build for a wide front, not one doorway.\n\n"
	+ "Towers are built from pads and paid from your bag. Kill loot goes into a pot.\n\n"
	+ "Bank the pot at the Lodestone when the ground around it is clear. Wait too long and "
	+ "you may not clear it again."
)

var _open: bool = false
var _catcher: Control = null
var _panel: PanelContainer = null


func _ready() -> void:
	layer = UiLayers.MODAL_SIEGE_DETAILS
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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	opened.emit()


func close_panel() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit()


func _build_ui() -> void:
	_catcher = Control.new()
	_catcher.name = "Catcher"
	_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.gui_input.connect(_on_catcher_input)
	add_child(_catcher)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.02, 0.03, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_catcher.add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_catcher.add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(PANEL_W, 0.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	_panel.add_child(margin)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var title := Label.new()
	title.name = "Title"
	title.text = "Siege Quarter"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	col.add_child(title)

	var body := Label.new()
	body.name = "Body"
	body.text = BODY
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(PANEL_W - 32.0, 0.0)
	body.add_theme_font_size_override("font_size", 15)
	body.modulate = Color(0.88, 0.88, 0.84)
	col.add_child(body)

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
	## Only the dim/catcher dismisses — clicks on the panel itself must not.
	var local := _panel.get_global_rect().has_point(mb.position)
	if not local:
		close_panel()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	var ek := event as InputEventKey
	if ek != null and ek.pressed and not ek.echo:
		if ek.keycode == KEY_ESCAPE or ek.physical_keycode == KEY_ESCAPE:
			close_panel()
			get_viewport().set_input_as_handled()
