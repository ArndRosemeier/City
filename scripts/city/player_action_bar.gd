## Bottom action bar: 6 slots. RMB assigns a Quaternius clip; LMB plays it.
class_name PlayerActionBar
extends CanvasLayer

const SLOT_COUNT := 6
const DEFAULT_BINDS: Array[String] = [
	"Dance",
	"Idle_Talking",
	"Interact",
	"Punch_Jab",
	"Kicking_m",
	"Stomping_m",
]
const DEFAULT_FALLBACKS: Array[String] = [
	"Dance",
	"Idle_Talking",
	"Interact",
	"Punch_Jab",
	"Sitting_Idle",
	"Roll",
]

var _walker: CityWalker
var _slots: Array[String] = []
var _buttons: Array[Button] = []
var _menu: PopupMenu
var _menu_slot: int = -1


func setup(walker: CityWalker) -> void:
	_walker = walker
	layer = 30
	_slots.resize(SLOT_COUNT)
	for i in range(SLOT_COUNT):
		var preferred := DEFAULT_BINDS[i] if i < DEFAULT_BINDS.size() else ""
		var fallback := DEFAULT_FALLBACKS[i] if i < DEFAULT_FALLBACKS.size() else ""
		if preferred != "" and walker != null and walker.has_action_animation(preferred):
			_slots[i] = preferred
		elif fallback != "" and walker != null and walker.has_action_animation(fallback):
			_slots[i] = fallback
		else:
			_slots[i] = ""
	_build_ui()
	_refresh_labels()


func _build_ui() -> void:
	for c in get_children():
		c.queue_free()
	_buttons.clear()

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_left = -230.0
	bar.offset_right = 230.0
	bar.offset_top = -92.0
	bar.offset_bottom = -16.0
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09, 0.82)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	bar.add_theme_stylebox_override("panel", sb)
	root.add_child(bar)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	bar.add_child(vbox)

	var hint := Label.new()
	hint.text = "LMB play · RMB assign · Esc frees mouse"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.75, 0.9))
	vbox.add_child(hint)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	for i in range(SLOT_COUNT):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(68, 52)
		btn.focus_mode = Control.FOCUS_NONE
		btn.clip_text = true
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.gui_input.connect(_on_slot_gui_input.bind(i))
		## Swallow default press so walker never sees these clicks.
		btn.pressed.connect(func() -> void: pass)
		row.add_child(btn)
		_buttons.append(btn)

	_menu = PopupMenu.new()
	_menu.name = "ActionAssignMenu"
	add_child(_menu)
	_menu.id_pressed.connect(_on_menu_id_pressed)
	_rebuild_menu()


func _rebuild_menu() -> void:
	_menu.clear()
	if _walker == null:
		return
	var names := _walker.list_action_animations()
	for i in range(names.size()):
		_menu.add_item(names[i], i)
	if names.is_empty():
		_menu.add_item("(no animations)", 0)
		_menu.set_item_disabled(0, true)


func _refresh_labels() -> void:
	for i in range(_buttons.size()):
		var name := _slots[i]
		_buttons[i].text = _short_label(name) if name != "" else "—"
		_buttons[i].tooltip_text = (
			"%s\nLMB play · RMB assign" % name if name != "" else "Empty — RMB to assign"
		)


func _short_label(anim_name: String) -> String:
	var s := anim_name.replace("_", " ")
	if s.length() <= 10:
		return s
	return s.substr(0, 9) + "…"


func _on_slot_gui_input(event: InputEvent, slot: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		_play_slot(slot)
		get_viewport().set_input_as_handled()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_open_assign_menu(slot)
		get_viewport().set_input_as_handled()


func _play_slot(slot: int) -> void:
	if _walker == null or not is_instance_valid(_walker):
		return
	if slot < 0 or slot >= _slots.size():
		return
	var anim := _slots[slot]
	if anim.is_empty():
		return
	_walker.play_action(anim)


func _open_assign_menu(slot: int) -> void:
	if _menu == null or slot < 0 or slot >= _slots.size():
		return
	_menu_slot = slot
	_rebuild_menu()
	var btn := _buttons[slot]
	var origin := btn.get_global_rect().position + Vector2(0.0, -8.0)
	_menu.position = Vector2i(int(origin.x), int(origin.y - float(_menu.get_contents_minimum_size().y)))
	_menu.popup()


func _on_menu_id_pressed(id: int) -> void:
	if _walker == null or _menu_slot < 0 or _menu_slot >= _slots.size():
		return
	var names := _walker.list_action_animations()
	if id < 0 or id >= names.size():
		return
	_slots[_menu_slot] = names[id]
	_refresh_labels()
	_menu_slot = -1
