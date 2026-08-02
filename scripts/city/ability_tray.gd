## Nine-slot ability bar: F1–F6 plus LMB / Ctrl+LMB / Alt+LMB labels.
##
## Shift+F1–F6 assigns those keys. Mouse slots use Shift+click on the tray button, or
## Shift+ the combat chord (Shift+LMB / Shift+Ctrl+LMB / Shift+Alt+LMB).
class_name AbilityTray
extends CanvasLayer

const AbilityRegistryScript := preload("res://scripts/city/ability_registry.gd")
const PlayerControlsScript := preload("res://scripts/city/player_controls.gd")

signal ability_requested(ability_id: String)
signal assign_changed

var _loadout: PlayerLoadout
var _buttons: Array[Button] = []
var _menu: PopupMenu
var _menu_slot: int = -1
var _menu_ids: Array[String] = []
var _controls: PlayerControls
var _walker: CityWalker
var _hint: Label


func setup(walker: CityWalker, loadout: PlayerLoadout) -> void:
	if walker == null:
		push_error("AbilityTray.setup: null walker")
		return
	if loadout == null:
		push_error("AbilityTray.setup: null loadout")
		return
	_walker = walker
	_loadout = loadout
	layer = UiLayers.HUD_ACTION_BAR
	_build_ui()
	refresh()


func set_controls(controls: PlayerControls) -> void:
	_controls = controls
	refresh()


func bind_loadout(loadout: PlayerLoadout) -> void:
	_loadout = loadout
	refresh()


func refresh() -> void:
	if _loadout == null:
		return
	var ctl := _ctl()
	var assign := ctl.binding_label("build_assign")
	for i in range(_buttons.size()):
		var id := _loadout.slot_at(i)
		var def := AbilityRegistry.get_def(id)
		var key := AbilityRegistry.slot_label(i)
		if i < 6:
			key = ctl.binding_label("build_%d" % (i + 1))
		var label := def.display_name if def != null else "—"
		_buttons[i].text = "%s\n%s" % [key, _short_label(label)]
		var hint := def.hint if def != null else "Empty"
		if i < 6:
			_buttons[i].tooltip_text = (
				"%s\n%s activate · %s+%s assign"
				% [hint, key, assign, key]
			)
		else:
			## Mouse chords need the assign mod on the click — bare "Shift+Ctrl" is a no-op.
			_buttons[i].tooltip_text = (
				"%s\n%s activate · %s+click or %s+%s assign"
				% [hint, _mouse_chord_label(i), assign, assign, _mouse_chord_label(i)]
			)
	if _hint != null:
		_hint.text = (
			"Sandbox · all powers"
			if _loadout.is_sandbox()
			else "Adventure · find recipes, then spend gems"
		)


func _ctl() -> PlayerControls:
	if _controls == null:
		_controls = PlayerControlsScript.new() as PlayerControls
	return _controls


func _unhandled_input(event: InputEvent) -> void:
	if UiInputGate.gameplay_blocked(_walker):
		return
	var ctl := _ctl()
	if event is InputEventKey:
		var ek := event as InputEventKey
		if not ek.pressed or ek.echo:
			return
		var slot := ctl.build_slot_for_key(ek)
		if slot < 0:
			return
		if ctl.is_build_assign_held(ek):
			_open_assign_menu(slot)
		else:
			_activate_slot(slot)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		## Assign only — bare combat clicks stay with the walker.
		if not ctl.is_build_assign_held(mb):
			return
		var action := ctl.resolve_mouse_action(
			mb, ["laser", "beam", "fire"] as Array[String]
		)
		var mouse_slot := AbilityRegistry.mouse_slot_for_action(action)
		if mouse_slot < 0:
			return
		_open_assign_menu(mouse_slot)
		get_viewport().set_input_as_handled()


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
	bar.offset_left = -420.0
	bar.offset_right = 420.0
	bar.offset_top = -100.0
	bar.offset_bottom = -12.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 4)
	bar.add_child(vbox)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.75, 0.9))
	vbox.add_child(_hint)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	vbox.add_child(row)

	for i in range(AbilityRegistry.SLOT_COUNT):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(76, 52)
		btn.focus_mode = Control.FOCUS_NONE
		btn.clip_text = true
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.gui_input.connect(_on_slot_gui_input.bind(i))
		row.add_child(btn)
		_buttons.append(btn)

	_menu = PopupMenu.new()
	_menu.name = "AbilityAssignMenu"
	add_child(_menu)
	_menu.id_pressed.connect(_on_menu_id_pressed)


func _short_label(name: String) -> String:
	if name.length() <= 10:
		return name
	return name.substr(0, 9) + "…"


func _on_slot_gui_input(event: InputEvent, slot: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _ctl().is_build_assign_held(mb):
		_open_assign_menu(slot)
	else:
		_activate_slot(slot)
	get_viewport().set_input_as_handled()


func _mouse_chord_label(slot: int) -> String:
	match slot:
		AbilityRegistry.SLOT_MOUSE_LMB:
			return "LMB"
		AbilityRegistry.SLOT_MOUSE_CTRL:
			return "Ctrl+LMB"
		AbilityRegistry.SLOT_MOUSE_ALT:
			return "Alt+LMB"
		_:
			return AbilityRegistry.slot_label(slot)


func _activate_slot(slot: int) -> void:
	if _loadout == null:
		return
	var id := _loadout.slot_at(slot)
	if id.is_empty():
		return
	ability_requested.emit(id)


func _open_assign_menu(slot: int) -> void:
	if _menu == null or _loadout == null or slot < 0 or slot >= AbilityRegistry.SLOT_COUNT:
		return
	_menu_slot = slot
	_menu.clear()
	_menu_ids.clear()
	_menu.add_item("(empty)", 0)
	_menu_ids.append("")
	var idx := 1
	for def in AbilityRegistry.assignable_defs():
		if not _loadout.is_unlocked(def.id):
			continue
		_menu.add_item("%s — %s" % [def.display_name, def.hint], idx)
		_menu_ids.append(def.id)
		idx += 1
	var btn := _buttons[slot]
	var origin := btn.get_global_rect().position + Vector2(0.0, -8.0)
	_menu.position = Vector2i(
		int(origin.x), int(origin.y - float(_menu.get_contents_minimum_size().y))
	)
	_menu.popup()


func _on_menu_id_pressed(id: int) -> void:
	if _loadout == null or _menu_slot < 0:
		return
	if id < 0 or id >= _menu_ids.size():
		return
	_loadout.set_slot(_menu_slot, _menu_ids[id])
	_menu_slot = -1
	refresh()
	assign_changed.emit()
