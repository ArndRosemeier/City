## Tower picker for a Siege foundation pad, opened by the pad's lay-flat "+" plate.
##
## Sits at the mouse rather than centre screen: the player just clicked a specific pad in the
## world, and a centred dialog would make them look away from the thing they are placing. Only
## recipes the pot can pay for are listed — a greyed row the player can press is a dead end.
class_name SiegeBuildPicker
extends CanvasLayer

signal opened
signal closed
signal build_requested(pad_index: int, tower_id: String)

const SiegeTowerCatalogScript := preload("res://scripts/city/siege_tower_catalog.gd")
const InventoryIconCacheScript := preload("res://scripts/city/inventory_icon_cache.gd")
const InventoryCatalogScript := preload("res://scripts/city/inventory_catalog.gd")

const PANEL_W := 320.0
## Kept clear of the cursor so the pointer never lands on a row the player did not aim at.
const MOUSE_OFFSET := Vector2(18.0, 14.0)
const EDGE_MARGIN := 12.0

var _open: bool = false
var _pad_index: int = -1
## Typed Node — a `SiegeController` field here cycles with the controller's picker calls.
var _controller: Node = null
## Elevation is the pad's whole identity, so name it before the player spends a gem.
var _pad_caption: String = ""
var _catcher: Control = null
var _panel: PanelContainer = null
var _rows: VBoxContainer = null
var _title: Label = null


func _ready() -> void:
	layer = UiLayers.MODAL_SIEGE_BUILD
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false
	set_process_unhandled_input(true)
	## Gem portraits render through a SubViewport, so they cannot be produced inside the frame
	## the player opens the picker in. Bake the whole tower gem set once at boot.
	_bake_gem_icons()


func is_open() -> bool:
	return _open


func pad_index() -> int:
	return _pad_index


## Open for one pad. `controller` answers `can_afford` and owns the pot.
func open_for_pad(pad_index_in: int, controller: Node, at: Vector2) -> void:
	if controller == null or not is_instance_valid(controller):
		push_error("SiegeBuildPicker.open_for_pad: no controller")
		assert(false, "SiegeBuildPicker: null controller")
		return
	if pad_index_in < 0:
		push_error("SiegeBuildPicker.open_for_pad: bad pad %d" % pad_index_in)
		assert(false, "SiegeBuildPicker: bad pad index")
		return
	_pad_index = pad_index_in
	_controller = controller
	_pad_caption = str(controller.call("pad_kind_label", pad_index_in))
	_rebuild_rows()
	_open = true
	visible = true
	_place_at(at)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	opened.emit()


func close_panel() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_pad_index = -1
	_controller = null
	closed.emit()


## Probe/accessibility helper: the recipes the player can actually press right now.
func listed_tower_ids() -> PackedStringArray:
	var out := PackedStringArray()
	if not _open:
		return out
	for child in _rows.get_children():
		var btn := child as Button
		if btn == null:
			continue
		out.append(String(btn.name).trim_prefix("Row_"))
	return out


## Pot changed while the list is up (a kill credited, another pad spent). Re-list in place.
func refresh() -> void:
	if not _open:
		return
	_rebuild_rows()


func _place_at(at: Vector2) -> void:
	var view := get_viewport().get_visible_rect().size
	## Panel height is only known after the rows lay out.
	var wanted := _panel.get_combined_minimum_size()
	var pos := at + MOUSE_OFFSET
	pos.x = clampf(pos.x, EDGE_MARGIN, maxf(view.x - wanted.x - EDGE_MARGIN, EDGE_MARGIN))
	pos.y = clampf(pos.y, EDGE_MARGIN, maxf(view.y - wanted.y - EDGE_MARGIN, EDGE_MARGIN))
	_panel.position = pos
	_panel.size = wanted


func _build_ui() -> void:
	## Transparent, not dimmed: the wave keeps coming while this is up and the player has to be
	## able to see it. Still MOUSE_FILTER_STOP so a click outside dismisses instead of firing.
	_catcher = Control.new()
	_catcher.name = "Catcher"
	_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.gui_input.connect(_on_catcher_input)
	add_child(_catcher)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(PANEL_W, 0.0)
	_catcher.add_child(_panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 10)
	_panel.add_child(margin)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	_title = Label.new()
	_title.name = "Title"
	_title.text = "Build tower"
	col.add_child(_title)

	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.add_theme_constant_override("separation", 4)
	col.add_child(_rows)


func _rebuild_rows() -> void:
	## Detach before freeing: `queue_free` alone leaves the old rows in `get_children()` for the
	## rest of the frame, so a re-list would stack the new rows under the stale ones.
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var listed := 0
	for def_v: Variant in SiegeTowerCatalogScript.all():
		var def: RefCounted = def_v as RefCounted
		var cost: Dictionary = def.get("cost") as Dictionary
		if not bool(_controller.call("can_afford", cost)):
			continue
		_rows.add_child(_make_row(def, cost))
		listed += 1
	if listed == 0:
		var none := Label.new()
		none.name = "Empty"
		none.text = "No gems in the pot for a tower yet."
		none.modulate = Color(0.75, 0.78, 0.85)
		_rows.add_child(none)
	_title.text = "%s — build" % _pad_caption.capitalize()


func _make_row(def: RefCounted, cost: Dictionary) -> Button:
	var tower_id := str(def.get("id"))
	var btn := Button.new()
	btn.name = "Row_%s" % tower_id
	btn.focus_mode = Control.FOCUS_NONE
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.text = "%s   %s" % [str(def.get("display_name")), _cost_label(cost)]
	btn.tooltip_text = str(def.get("hint"))
	var tex := InventoryIconCacheScript.texture_for(str(def.get("gem")))
	if tex != null:
		btn.icon = tex
		btn.expand_icon = true
	btn.pressed.connect(_on_row_pressed.bind(tower_id))
	return btn


func _cost_label(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	var keys: Array = cost.keys()
	keys.sort()
	for k: Variant in keys:
		var item_id := String(k)
		var n := int(cost[k])
		if n <= 0:
			continue
		parts.append("%d x %s" % [n, _gem_label(item_id)])
	return ", ".join(parts)


func _gem_label(item_id: String) -> String:
	return InventoryCatalogScript.display_name(item_id)


func _bake_gem_icons() -> void:
	var gems := PackedStringArray()
	for def_v: Variant in SiegeTowerCatalogScript.all():
		var gem := str((def_v as RefCounted).get("gem"))
		if not gem.is_empty() and not gems.has(gem):
			gems.append(gem)
	if gems.is_empty():
		return
	await InventoryIconCacheScript.bake_ids(gems, self)
	## District unload / shutdown can free the picker while the bake awaits frames.
	if not is_inside_tree():
		return
	refresh()


func _on_row_pressed(tower_id: String) -> void:
	if not _open:
		return
	var pad := _pad_index
	var ctrl := _controller
	## Close first: the build stamps voxels and spawns a body, and the pot refresh that follows
	## would otherwise re-list a picker for a pad that is already occupied.
	close_panel()
	if ctrl == null or not is_instance_valid(ctrl):
		push_error("SiegeBuildPicker: controller vanished before the build")
		return
	ctrl.call("build_tower", pad, tower_id)
	build_requested.emit(pad, tower_id)


func _on_catcher_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
		close_panel()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	var ek := event as InputEventKey
	if ek != null and ek.pressed and not ek.echo:
		if ek.keycode == KEY_ESCAPE or ek.physical_keycode == KEY_ESCAPE:
			close_panel()
			get_viewport().set_input_as_handled()
