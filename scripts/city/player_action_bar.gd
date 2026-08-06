## Bottom build bar: F1–F6 place the bound recipe at the cursor; Shift+F1–F6 assign.
class_name PlayerActionBar
extends CanvasLayer

const BuildCatalogScript := preload("res://scripts/city/build_catalog.gd")
const PlayerControlsScript := preload("res://scripts/city/player_controls.gd")

const SLOT_COUNT := 6
const DEFAULT_BINDS: Array[String] = [
	"cottage",
]

signal build_requested(recipe_id: String)

var _slots: Array[String] = []
var _buttons: Array[Button] = []
var _menu: PopupMenu
var _menu_slot: int = -1
var _recipes: Array = []
var _controls: PlayerControls
## Owner of the canonical "some panel owns the screen" test.
var _walker: CityWalker


func setup(walker: CityWalker) -> void:
	if walker == null:
		push_error("PlayerActionBar.setup: null walker")
		return
	_walker = walker
	layer = UiLayers.HUD_ACTION_BAR
	_recipes = BuildCatalogScript.all()
	_slots.resize(SLOT_COUNT)
	for i in range(SLOT_COUNT):
		_slots[i] = DEFAULT_BINDS[i] if i < DEFAULT_BINDS.size() else ""
	_build_ui()
	_refresh_labels()


func set_controls(controls: PlayerControls) -> void:
	_controls = controls
	_refresh_labels()


func _ctl() -> PlayerControls:
	if _controls == null:
		_controls = PlayerControlsScript.new() as PlayerControls
	return _controls


func _unhandled_input(event: InputEvent) -> void:
	## A modal owns the screen while it is up, so a build key must not reach the world behind
	## it. Same gate the walker puts on its own hotkeys.
	if UiInputGate.gameplay_blocked(_walker):
		return
	var ek := event as InputEventKey
	if ek == null or not ek.pressed or ek.echo:
		return
	var ctl := _ctl()
	var slot := ctl.build_slot_for_key(ek)
	if slot < 0:
		return
	if ctl.is_build_assign_held(ek):
		_open_assign_menu(slot)
	else:
		_place_slot(slot)
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
	bar.offset_left = -260.0
	bar.offset_right = 260.0
	bar.offset_top = -92.0
	bar.offset_bottom = -16.0
	## Ignore mouse on the bar itself so aiming through it still hits the world;
	## slot buttons stay clickable for place / (via keyboard) assign.
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

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "Build slots · Settings → Controls to rebind"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.75, 0.9))
	vbox.add_child(hint)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	for i in range(SLOT_COUNT):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(78, 52)
		btn.focus_mode = Control.FOCUS_NONE
		btn.clip_text = true
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.gui_input.connect(_on_slot_gui_input.bind(i))
		row.add_child(btn)
		_buttons.append(btn)

	_menu = PopupMenu.new()
	_menu.name = "BuildAssignMenu"
	add_child(_menu)
	_menu.id_pressed.connect(_on_menu_id_pressed)
	_rebuild_menu()


func _rebuild_menu() -> void:
	_menu.clear()
	for i in range(_recipes.size()):
		var recipe: BuildCatalog.Recipe = _recipes[i]
		_menu.add_item("%s — %s" % [recipe.display_name, recipe.hint], i)
	if _recipes.is_empty():
		_menu.add_item("(no builds)", 0)
		_menu.set_item_disabled(0, true)


func _refresh_labels() -> void:
	var ctl := _ctl()
	var assign := ctl.binding_label("build_assign")
	for i in range(_buttons.size()):
		var id := _slots[i]
		var key := ctl.binding_label("build_%d" % (i + 1))
		var recipe := _recipe_named(id)
		var label := recipe.display_name if recipe != null else "—"
		_buttons[i].text = "%s\n%s" % [key, _short_label(label)]
		_buttons[i].tooltip_text = (
			"%s\n%s place at cursor · %s+%s assign"
			% [recipe.hint if recipe != null else "Empty", key, assign, key]
		)


func _recipe_named(id: String) -> BuildCatalog.Recipe:
	if id.is_empty():
		return null
	for r: Variant in _recipes:
		var recipe: BuildCatalog.Recipe = r
		if recipe.id == id:
			return recipe
	return null


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
	## Clicking a slot places using the *current* cursor ray — move the mouse off
	## the button first, or prefer the F-key so aim stays on the world.
	_place_slot(slot)
	get_viewport().set_input_as_handled()


func _place_slot(slot: int) -> void:
	if slot < 0 or slot >= _slots.size():
		return
	var id := _slots[slot]
	if id.is_empty():
		return
	build_requested.emit(id)


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
	if _menu_slot < 0 or _menu_slot >= _slots.size():
		return
	if id < 0 or id >= _recipes.size():
		return
	var recipe: BuildCatalog.Recipe = _recipes[id]
	_slots[_menu_slot] = recipe.id
	_refresh_labels()
	_menu_slot = -1
