## Session lifecycle modal: Quicksave / Quickload, the named save library, and New Game.
##
## Deliberately not a tab inside Settings. Settings is where graphics knobs live and gets opened
## mid-play all the time; the button that throws a run away has no business one mis-click from a
## slider. The panel owns no state of its own — it asks CityRoot to do the work and re-reads the
## slot list afterwards, so what it shows is always what is on disk.
class_name GameMenuPanel
extends CanvasLayer

signal opened
signal closed
signal quicksave_requested
signal quickload_requested
signal named_save_requested(save_name: String)
signal named_load_requested(save_name: String)
signal new_game_requested

const GameSaveScript := preload("res://scripts/city/game_save.gd")

const PANEL_WIDTH := 560.0
const PANEL_HEIGHT := 560.0
const LIST_HEIGHT := 240.0
const HINT_COLOR := Color(0.76, 0.79, 0.86)
const WARN_COLOR := Color(1.0, 0.72, 0.45)

var _open: bool = false
var _dim: ColorRect
var _panel: PanelContainer
var _quickload_btn: Button
var _save_btn: Button
var _load_btn: Button
var _new_btn: Button
var _name_field: LineEdit
var _list: ItemList
var _status: Label
var _folder_hint: Label
## Row index → slot name on disk, parallel to `_list`.
var _row_names: PackedStringArray = PackedStringArray()
## Set while a destructive action waits for a second press on the same button.
var _armed: String = ""


func _ready() -> void:
	layer = UiLayers.MODAL_GAME
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
	_armed = ""
	visible = true
	_dim.visible = true
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()
	opened.emit()


func close_panel() -> void:
	if not _open:
		return
	_open = false
	_armed = ""
	visible = false
	_dim.visible = false
	_panel.visible = false
	closed.emit()


func toggle_panel() -> void:
	if _open:
		close_panel()
	else:
		open_panel()


## Re-read the slots on disk and reset the button labels. Called on open and after every write.
func refresh() -> void:
	_disarm_buttons()
	_quickload_btn.disabled = not GameSaveScript.has_quicksave()
	## The real folder rather than `user://…`: handing a save to someone else means opening it, and
	## nobody can open a Godot URI in Explorer.
	_folder_hint.text = (
		"One file each in %s — copy one to share it."
		% ProjectSettings.globalize_path(GameSaveScript.saves_dir())
	)
	_rebuild_list()
	_sync_save_button()
	_sync_load_button()


func set_status(text: String, warn: bool = false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", WARN_COLOR if warn else HINT_COLOR)


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
		margin.add_theme_constant_override("margin_%s" % side, 16)
	_panel.add_child(margin)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var title := Label.new()
	title.text = "Game"
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_status = Label.new()
	_status.name = "Status"
	_status.text = "Saves keep your character and where he stood, not the city."
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", HINT_COLOR)
	col.add_child(_status)

	var quick_row := HBoxContainer.new()
	quick_row.name = "QuickRow"
	quick_row.add_theme_constant_override("separation", 8)
	col.add_child(quick_row)

	var quicksave_btn := Button.new()
	quicksave_btn.text = "Quicksave"
	quicksave_btn.focus_mode = Control.FOCUS_NONE
	quicksave_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quicksave_btn.pressed.connect(_on_quicksave_pressed)
	quick_row.add_child(quicksave_btn)

	_quickload_btn = Button.new()
	_quickload_btn.text = "Quickload"
	_quickload_btn.focus_mode = Control.FOCUS_NONE
	_quickload_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quickload_btn.pressed.connect(_on_quickload_pressed)
	quick_row.add_child(_quickload_btn)

	col.add_child(HSeparator.new())

	var save_label := Label.new()
	save_label.text = "Named saves"
	save_label.add_theme_font_size_override("font_size", 15)
	col.add_child(save_label)

	_folder_hint = Label.new()
	_folder_hint.name = "FolderHint"
	_folder_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_folder_hint.add_theme_font_size_override("font_size", 12)
	_folder_hint.add_theme_color_override("font_color", HINT_COLOR)
	col.add_child(_folder_hint)

	var save_row := HBoxContainer.new()
	save_row.name = "SaveRow"
	save_row.add_theme_constant_override("separation", 8)
	col.add_child(save_row)

	_name_field = LineEdit.new()
	_name_field.name = "SaveName"
	_name_field.placeholder_text = "Save name"
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_field.max_length = GameSaveScript.NAME_MAX_LENGTH
	_name_field.text_changed.connect(_on_name_changed)
	_name_field.text_submitted.connect(_on_name_submitted)
	save_row.add_child(_name_field)

	_save_btn = Button.new()
	_save_btn.text = "Save"
	_save_btn.focus_mode = Control.FOCUS_NONE
	_save_btn.custom_minimum_size = Vector2(110.0, 0.0)
	_save_btn.pressed.connect(_on_save_pressed)
	save_row.add_child(_save_btn)

	_list = ItemList.new()
	_list.name = "SaveList"
	_list.custom_minimum_size = Vector2(PANEL_WIDTH - 48.0, LIST_HEIGHT)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.allow_reselect = true
	_list.item_selected.connect(_on_item_selected)
	_list.item_activated.connect(_on_item_activated)
	col.add_child(_list)

	var bottom := HBoxContainer.new()
	bottom.name = "BottomRow"
	bottom.add_theme_constant_override("separation", 8)
	col.add_child(bottom)

	_load_btn = Button.new()
	_load_btn.text = "Load"
	_load_btn.focus_mode = Control.FOCUS_NONE
	_load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_btn.pressed.connect(_on_load_pressed)
	bottom.add_child(_load_btn)

	_new_btn = Button.new()
	_new_btn.name = "NewGameButton"
	_new_btn.text = "New Game"
	_new_btn.focus_mode = Control.FOCUS_NONE
	_new_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_btn.pressed.connect(_on_new_game_pressed)
	bottom.add_child(_new_btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(110.0, 0.0)
	close_btn.pressed.connect(close_panel)
	bottom.add_child(close_btn)


func _rebuild_list() -> void:
	_list.clear()
	_row_names = PackedStringArray()
	var saves := GameSaveScript.list_named()
	for entry: Dictionary in saves:
		var name := String(entry["name"])
		var when := String(entry["saved_at"])
		var label := name if when.is_empty() else "%s   ·   %s" % [name, when]
		_row_names.append(name)
		_list.add_item(label)
	if saves.is_empty():
		var empty_row := _list.add_item("no named saves yet")
		_list.set_item_selectable(empty_row, false)
		_list.set_item_disabled(empty_row, true)
		_row_names.append("")


func _selected_name() -> String:
	var rows := _list.get_selected_items()
	if rows.is_empty():
		return ""
	var row := rows[0]
	if row < 0 or row >= _row_names.size():
		return ""
	return _row_names[row]


func _sync_save_button() -> void:
	var raw := _name_field.text
	var clean := GameSaveScript.sanitize_name(raw)
	_save_btn.disabled = clean.is_empty() or GameSaveScript.is_reserved_name(raw)
	_save_btn.text = "Save"


func _sync_load_button() -> void:
	_load_btn.disabled = _selected_name().is_empty()
	_load_btn.text = "Load"


## Destructive actions take two presses on the same button rather than a second window: the first
## press says what is about to happen, the second does it. Returns true on the confirming press.
func _arm(action: String, button: Button, idle_text: String, armed_text: String) -> bool:
	if _armed == action:
		_armed = ""
		button.text = idle_text
		return true
	_disarm_buttons()
	_armed = action
	button.text = armed_text
	return false


func _disarm_buttons() -> void:
	_armed = ""
	_quickload_btn.text = "Quickload"
	_load_btn.text = "Load"
	_new_btn.text = "New Game"


func _on_quicksave_pressed() -> void:
	_disarm_buttons()
	quicksave_requested.emit()


func _on_quickload_pressed() -> void:
	if not GameSaveScript.has_quicksave():
		set_status("There is no autosave to load yet.", true)
		return
	if not _arm("quickload", _quickload_btn, "Quickload", "Quickload — confirm?"):
		set_status("Loading the autosave rebuilds the world. Press again to confirm.", true)
		return
	quickload_requested.emit()


func _on_save_pressed() -> void:
	_disarm_buttons()
	var raw := _name_field.text
	if GameSaveScript.is_reserved_name(raw):
		set_status("'%s' is the autosave slot — pick another name." % GameSaveScript.QUICKSAVE_NAME, true)
		return
	var clean := GameSaveScript.sanitize_name(raw)
	if clean.is_empty():
		set_status("That name has no letters or digits in it.", true)
		return
	named_save_requested.emit(raw)


func _on_load_pressed() -> void:
	var name := _selected_name()
	if name.is_empty():
		set_status("Pick a save from the list first.", true)
		return
	if not _arm("load", _load_btn, "Load", "Load — confirm?"):
		set_status("Loading '%s' rebuilds the world. Press again to confirm." % name, true)
		return
	named_load_requested.emit(name)


func _on_new_game_pressed() -> void:
	if not _arm("new", _new_btn, "New Game", "New Game — confirm?"):
		set_status(
			"A new game drops the autosave and builds a new city. Press again to confirm.", true
		)
		return
	new_game_requested.emit()


func _on_name_changed(_text: String) -> void:
	_sync_save_button()


func _on_name_submitted(_text: String) -> void:
	if not _save_btn.disabled:
		_on_save_pressed()


func _on_item_selected(_index: int) -> void:
	_disarm_buttons()
	_name_field.text = _selected_name()
	_sync_save_button()
	_sync_load_button()


func _on_item_activated(index: int) -> void:
	_list.select(index)
	_on_item_selected(index)
	_on_load_pressed()


func _on_dim_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		close_panel()
