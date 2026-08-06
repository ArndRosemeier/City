## Inventory modal: 25 stackable slots + craft list. Toggle with I; Esc closes.
class_name PlayerInventoryPanel
extends CanvasLayer

signal opened
signal closed
signal craft_requested(recipe_id: String)
signal unlock_requested(ability_id: String)

const SLOT_PX := 72.0
const GRID_COLS := 5
## Square corner button. Big enough to hit without aiming, small enough not to crowd the title.
const CLOSE_PX := 30.0
## Width of the recipe column. Wide enough for a two-line "name (cost)" row once the scrollbar
## has taken its strip back.
const CRAFT_COL_PX := 216.0
const VIEW_SIZE := Vector2i(64, 64)
## Badge beside a recipe row. A stretched SubViewportContainer keeps its target the size of the
## control, so this is what the badge both occupies and renders at.
const ROW_ICON_PX := 38.0
## Row height. Two text lines plus the badge, with the badge setting the floor.
const ROW_PX := 44.0
const LOCKED_BOX_META := "locked_recipe"

var _inventory: PlayerInventory
var _open: bool = false
var _dim: ColorRect
var _panel: PanelContainer
var _detail_label: Label
var _craft_box: VBoxContainer
var _recipe_list_box: VBoxContainer
var _recipe_scroll: ScrollContainer
var _close_button: Button
var _slot_buttons: Array[Button] = []
var _slot_previews: Array[IconPreview] = []
var _slot_counts: Array[Label] = []
var _selected_index: int = -1
var _recipe_rows: Array[RecipeRow] = []


## One line of the recipe column. A row the run has not found yet carries no name, no cost and
## no badge — only the fact that something is still out there.
class RecipeRow:
	extends RefCounted
	var button: Button
	var label: Label
	var preview: IconPreview
	## Recipe id for a craft row, ability id for an unlock row, empty on a locked placeholder.
	var id: String = ""
	var is_unlock: bool = false


func _ready() -> void:
	layer = UiLayers.MODAL_INVENTORY
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false
	set_process(false)
	set_process_unhandled_input(true)


func bind_inventory(inventory: PlayerInventory) -> void:
	if _inventory != null and _inventory.changed.is_connected(_on_inventory_changed):
		_inventory.changed.disconnect(_on_inventory_changed)
	_inventory = inventory
	if _inventory == null:
		push_error("PlayerInventoryPanel.bind_inventory: null inventory")
		return
	_inventory.changed.connect(_on_inventory_changed)
	_refresh()


func is_open() -> bool:
	return _open


## Eye point of every slot camera. Slots and recipe badges frame alike, so the rule lives on
## `IconPreview`; this stays as the name the panel's callers already know it by.
static func slot_camera_position() -> Vector3:
	return IconPreview.camera_position()


func close_button() -> Button:
	return _close_button


func recipe_scroll() -> ScrollContainer:
	return _recipe_scroll


func recipe_list() -> VBoxContainer:
	return _recipe_list_box


## The learned rows, in the order the column shows them.
func recipe_rows() -> Array[RecipeRow]:
	return _recipe_rows.duplicate()


## How many blank "(locked)" boxes the column is showing.
func locked_box_count() -> int:
	if _recipe_list_box == null:
		return 0
	var n := 0
	for child in _recipe_list_box.get_children():
		if child.has_meta(LOCKED_BOX_META):
			n += 1
	return n


## Rect of the whole modal, for callers that need to know where its corners are.
func panel_rect() -> Rect2:
	return Rect2() if _panel == null else _panel.get_global_rect()


func slot_preview(index: int) -> IconPreview:
	if index < 0 or index >= _slot_previews.size():
		push_error("PlayerInventoryPanel.slot_preview: index %d out of range" % index)
		return null
	return _slot_previews[index]


func slot_viewport(index: int) -> SubViewport:
	var preview := slot_preview(index)
	return null if preview == null else preview.viewport()


func slot_camera(index: int) -> Camera3D:
	var preview := slot_preview(index)
	return null if preview == null else preview.camera()


## The preview currently shown in a slot, or null while the slot is empty.
func slot_mesh(index: int) -> MeshInstance3D:
	var preview := slot_preview(index)
	return null if preview == null else preview.current_mesh()


func open_panel() -> void:
	if _open:
		return
	if _inventory == null:
		push_error("PlayerInventoryPanel.open_panel: inventory not bound")
		return
	_open = true
	visible = true
	_dim.visible = true
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_process(true)
	## The cookbook can have grown since the last open, and the panel is built once at boot.
	rebuild_recipe_lists()
	_refresh()
	opened.emit()


func close_panel() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_dim.visible = false
	_panel.visible = false
	set_process(false)
	closed.emit()


func toggle_panel() -> void:
	if _open:
		close_panel()
	else:
		open_panel()


func _on_inventory_changed() -> void:
	if _open:
		_refresh()


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for preview in _slot_previews:
		InventoryItemVisual.tick_trap_pulse(preview.current_mesh(), t)


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	var ek := event as InputEventKey
	if ek != null and ek.pressed and not ek.echo:
		if ek.keycode == KEY_ESCAPE or ek.physical_keycode == KEY_ESCAPE:
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

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.visible = false
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -340.0
	_panel.offset_top = -300.0
	_panel.offset_right = 340.0
	_panel.offset_bottom = 300.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.94)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var margin := MarginContainer.new()
	_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title_row := HBoxContainer.new()
	root.add_child(title_row)
	var title := Label.new()
	title.text = "Inventory"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var hint := Label.new()
	hint.text = "I / Esc close"
	hint.modulate = Color(0.7, 0.74, 0.8)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(hint)
	## Esc and I both close the panel, but nothing on screen said so to a player who is holding
	## a mouse because the panel just put the cursor back.
	_close_button = Button.new()
	_close_button.name = "Close"
	## The same multiplication sign the detail line already draws, rather than a dingbat cross:
	## a glyph the default font is known to have cannot come out as a tofu box.
	_close_button.text = "×"
	_close_button.flat = true
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.tooltip_text = "Close (Esc)"
	_close_button.custom_minimum_size = Vector2(CLOSE_PX, CLOSE_PX)
	_close_button.add_theme_font_size_override("font_size", 18)
	_close_button.pressed.connect(close_panel)
	title_row.add_child(_close_button)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var grid_wrap := VBoxContainer.new()
	grid_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(grid_wrap)

	var grid := GridContainer.new()
	grid.columns = GRID_COLS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid_wrap.add_child(grid)

	_slot_buttons.clear()
	_slot_previews.clear()
	_slot_counts.clear()
	for i in InventoryCatalog.SLOT_COUNT:
		grid.add_child(_make_slot(i))

	var craft_panel := PanelContainer.new()
	craft_panel.custom_minimum_size = Vector2(CRAFT_COL_PX, 0)
	craft_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var craft_style := StyleBoxFlat.new()
	craft_style.bg_color = Color(0.04, 0.05, 0.07, 0.9)
	craft_style.corner_radius_top_left = 6
	craft_style.corner_radius_top_right = 6
	craft_style.corner_radius_bottom_left = 6
	craft_style.corner_radius_bottom_right = 6
	craft_style.content_margin_left = 10
	craft_style.content_margin_right = 10
	craft_style.content_margin_top = 8
	craft_style.content_margin_bottom = 8
	craft_panel.add_theme_stylebox_override("panel", craft_style)
	body.add_child(craft_panel)

	_craft_box = VBoxContainer.new()
	_craft_box.add_theme_constant_override("separation", 8)
	craft_panel.add_child(_craft_box)
	var craft_title := Label.new()
	craft_title.text = "Construct"
	craft_title.add_theme_font_size_override("font_size", 18)
	_craft_box.add_child(craft_title)
	var craft_hint := Label.new()
	craft_hint.text = "Spend inventory items"
	craft_hint.modulate = Color(0.65, 0.7, 0.78)
	craft_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_craft_box.add_child(craft_hint)
	## A full cookbook is three crafts plus a schematic for every gated power, which is far taller
	## than the panel. Without a scroller the column simply ran off the bottom edge and the last
	## rows were unreachable.
	_recipe_scroll = ScrollContainer.new()
	_recipe_scroll.name = "RecipeScroll"
	_recipe_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	## Rows are as wide as the column; sideways scrolling would only hide half a button label.
	_recipe_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_craft_box.add_child(_recipe_scroll)
	## Everything below the heading is rebuilt whenever the cookbook grows, so it lives in a box
	## of its own — clearing the whole craft column would take the title with it.
	_recipe_list_box = VBoxContainer.new()
	_recipe_list_box.add_theme_constant_override("separation", 8)
	_recipe_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_scroll.add_child(_recipe_list_box)
	rebuild_recipe_lists()

	_detail_label = Label.new()
	_detail_label.text = "Click a slot to inspect"
	_detail_label.modulate = Color(0.85, 0.88, 0.92)
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_detail_label)


func _make_slot(index: int) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(SLOT_PX, SLOT_PX)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_on_slot_pressed.bind(index))
	_slot_buttons.append(btn)

	var stack := Control.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(stack)

	var preview := IconPreview.new()
	preview.name = "Preview"
	preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	preview.offset_left = 4
	preview.offset_top = 4
	preview.offset_right = -4
	preview.offset_bottom = -4
	preview.build(VIEW_SIZE)
	stack.add_child(preview)
	_slot_previews.append(preview)

	var count := Label.new()
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count.set_anchors_preset(Control.PRESET_FULL_RECT)
	count.offset_left = 4
	count.offset_top = 4
	count.offset_right = -6
	count.offset_bottom = -4
	count.add_theme_font_size_override("font_size", 14)
	count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	count.add_theme_constant_override("outline_size", 4)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(count)
	_slot_counts.append(count)
	return btn


## Learned recipes first, each with the badge of the thing it builds; then one blank box per
## recipe the run has not found. The blanks are deliberately nameless and deliberately last: a
## count of what is still out there is useful, but a row reading "Laser — locked" would hand the
## player the contents of a chest they have not opened, and keeping them in book order would
## leak the same thing by position.
func rebuild_recipe_lists() -> void:
	if _recipe_list_box == null:
		return
	for child in _recipe_list_box.get_children():
		_recipe_list_box.remove_child(child)
		child.queue_free()
	_recipe_rows.clear()

	var known_crafts: Array[InventoryCatalog.Recipe] = []
	var locked_count := 0
	for recipe in InventoryCatalog.craft_recipes():
		if _knows_recipe(recipe.id):
			known_crafts.append(recipe)
		else:
			locked_count += 1
	for recipe in known_crafts:
		var row := _add_recipe_row(
			InventoryItemVisual.make_mesh(recipe.output_id), _recipe_button_text(recipe)
		)
		row.id = recipe.id
		row.button.pressed.connect(_on_craft_pressed.bind(recipe.id))

	var known_unlocks: Array[AbilityRegistry.AbilityDef] = []
	for def in AbilityRegistry.unlockable_defs():
		if _knows_ability_schematic(def.id):
			known_unlocks.append(def)
		else:
			locked_count += 1
	if not known_unlocks.is_empty():
		var unlock_title := Label.new()
		unlock_title.text = "Unlock"
		unlock_title.add_theme_font_size_override("font_size", 16)
		_recipe_list_box.add_child(unlock_title)
	for def in known_unlocks:
		var urow := _add_recipe_row(AbilityIconVisual.make_mesh(def.id), _unlock_button_text(def))
		urow.id = def.id
		urow.is_unlock = true
		urow.button.pressed.connect(_on_unlock_pressed.bind(def.id))

	## Discovery builds: nameless blanks while missing; once learned they live on the tray assign
	## menu (nothing to craft or buy here), so they never get a named Construct row.
	for recipe in InventoryCatalog.build_discovery_recipes():
		if not _knows_recipe(recipe.id):
			locked_count += 1

	if known_crafts.is_empty() and known_unlocks.is_empty():
		var empty := Label.new()
		empty.text = "No recipes yet — explore"
		empty.modulate = Color(0.6, 0.64, 0.72)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_recipe_list_box.add_child(empty)
	if locked_count > 0:
		var locked_title := Label.new()
		locked_title.text = "Undiscovered"
		locked_title.add_theme_font_size_override("font_size", 16)
		locked_title.modulate = Color(0.6, 0.64, 0.72)
		_recipe_list_box.add_child(locked_title)
	for _i in locked_count:
		_recipe_list_box.add_child(_make_locked_box())


## A recipe row: the badge of what it builds, then name and cost. The button sits under the
## content rather than owning it, because a `Button` lays its own text out and would give the
## badge nowhere to go; the row is a stack instead, so the two share one hit area and the row
## still grows to fit a cost line that wraps.
func _add_recipe_row(icon: MeshInstance3D, text: String) -> RecipeRow:
	var row := RecipeRow.new()
	var stack := MarginContainer.new()

	row.button = Button.new()
	row.button.focus_mode = Control.FOCUS_NONE
	row.button.custom_minimum_size = Vector2(0.0, ROW_PX)
	stack.add_child(row.button)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_theme_constant_override("margin_right", 8)
	pad.add_theme_constant_override("margin_top", 5)
	pad.add_theme_constant_override("margin_bottom", 5)
	stack.add_child(pad)

	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 8)
	pad.add_child(line)

	row.preview = IconPreview.new()
	row.preview.name = "Badge"
	row.preview.custom_minimum_size = Vector2(ROW_ICON_PX, ROW_ICON_PX)
	row.preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.preview.build(Vector2i(int(ROW_ICON_PX), int(ROW_ICON_PX)))
	line.add_child(row.preview)
	row.preview.show_mesh(icon)

	row.label = Label.new()
	row.label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	## The column is fixed and a cost line can be long; wrapping grows the row instead of
	## cutting the ingredient list off mid-word.
	row.label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.label.add_theme_font_size_override("font_size", 13)
	row.label.text = text
	line.add_child(row.label)

	_recipe_list_box.add_child(stack)
	_recipe_rows.append(row)
	return row


## Placeholder for a recipe still out in the world: an empty badge frame and the word, nothing
## that could be read back as a name.
func _make_locked_box() -> Control:
	var box := PanelContainer.new()
	## Marked rather than named: siblings cannot share a name, so a dozen blanks would come out
	## as LockedRecipe, @LockedRecipe@2 and so on, and only the first would ever be counted.
	box.set_meta(LOCKED_BOX_META, true)
	box.custom_minimum_size = Vector2(0.0, ROW_PX)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.85)
	style.border_color = Color(0.24, 0.27, 0.33)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	box.add_theme_stylebox_override("panel", style)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	box.add_child(line)

	var frame := Panel.new()
	frame.custom_minimum_size = Vector2(ROW_ICON_PX, ROW_ICON_PX)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.05, 0.06, 0.08, 0.9)
	frame_style.border_color = Color(0.22, 0.25, 0.31)
	frame_style.set_border_width_all(1)
	frame_style.set_corner_radius_all(3)
	frame.add_theme_stylebox_override("panel", frame_style)
	line.add_child(frame)

	var text := Label.new()
	text.text = "(locked)"
	text.modulate = Color(0.52, 0.56, 0.64)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", 13)
	line.add_child(text)
	return box


func _unlock_button_text(def: AbilityRegistry.AbilityDef) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for item_id in def.unlock_cost.keys():
		parts.append(
			"%d %s" % [int(def.unlock_cost[item_id]), InventoryCatalog.display_name(String(item_id))]
		)
	return "%s\n(%s)" % [def.display_name, ", ".join(parts)]


func _recipe_button_text(recipe: InventoryCatalog.Recipe) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for item_id in recipe.inputs.keys():
		parts.append(
			"%d %s" % [int(recipe.inputs[item_id]), InventoryCatalog.display_name(String(item_id))]
		)
	return "%s\n(%s)" % [recipe.display_name, ", ".join(parts)]


func _on_dim_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		close_panel()


func _on_slot_pressed(index: int) -> void:
	_selected_index = index
	_update_detail()
	_refresh_slot_styles()


func _on_craft_pressed(recipe_id: String) -> void:
	craft_requested.emit(recipe_id)


func _on_unlock_pressed(ability_id: String) -> void:
	unlock_requested.emit(ability_id)


func _refresh() -> void:
	if _inventory == null:
		return
	for i in InventoryCatalog.SLOT_COUNT:
		_refresh_slot(i)
	_update_detail()
	_refresh_recipe_rows()
	_refresh_slot_styles()


func _refresh_slot(index: int) -> void:
	var slot := _inventory.slot_at(index)
	var count_lbl := _slot_counts[index]
	var preview := _slot_previews[index]
	if slot.is_empty():
		preview.show_mesh(null)
		count_lbl.text = ""
		return
	var item_id := str(slot.get("id", ""))
	var count := int(slot.get("count", 0))
	count_lbl.text = str(count) if count > 1 else ""
	var mesh := InventoryItemVisual.make_mesh(item_id)
	if mesh != null and InventoryCatalog.item(item_id).is_trap:
		mesh.set_meta("trap_pulse", true)
	preview.show_mesh(mesh)


func _refresh_recipe_rows() -> void:
	for row in _recipe_rows:
		if row.is_unlock:
			var def := AbilityRegistry.get_def(row.id)
			if def == null:
				push_error("PlayerInventoryPanel: unlock row for unknown ability '%s'" % row.id)
				continue
			var built := _is_ability_unlocked(row.id)
			var can_unlock := not built and _can_afford_unlock(def)
			row.button.disabled = built or not can_unlock
			row.label.text = (
				"%s\nbuilt" % def.display_name if built else _unlock_button_text(def)
			)
			_dim_row(row, can_unlock)
			continue
		var recipe := InventoryCatalog.recipe(row.id)
		if recipe == null:
			push_error("PlayerInventoryPanel: craft row for unknown recipe '%s'" % row.id)
			continue
		var can := _inventory != null and _inventory.can_craft(row.id)
		row.button.disabled = not can
		row.label.text = _recipe_button_text(recipe)
		_dim_row(row, can)


## Only the text greys out when a row cannot be pressed. Dimming the whole row would take the
## badge with it, and a washed-out badge reads as "not found yet" — which is the one thing a
## listed row is not.
func _dim_row(row: RecipeRow, lit: bool) -> void:
	row.label.modulate = Color(1, 1, 1) if lit else Color(0.65, 0.65, 0.7)


func _can_afford_unlock(def: AbilityRegistry.AbilityDef) -> bool:
	if _inventory == null:
		return false
	for item_id: Variant in def.unlock_cost.keys():
		if _inventory.count_of(str(item_id)) < int(def.unlock_cost[item_id]):
			return false
	return true


func _is_ability_unlocked(ability_id: String) -> bool:
	var city := _city_root()
	if city != null and city.has_method("can_use_ability"):
		return bool(city.call("can_use_ability", ability_id))
	return false


func _knows_recipe(recipe_id: String) -> bool:
	var city := _city_root()
	if city != null and city.has_method("knows_recipe"):
		return bool(city.call("knows_recipe", recipe_id))
	## Standalone panel tests have no city; show the full book rather than an empty panel.
	return true


func _knows_ability_schematic(ability_id: String) -> bool:
	var city := _city_root()
	if city != null and city.has_method("knows_ability_schematic"):
		return bool(city.call("knows_ability_schematic", ability_id))
	return true


func _city_root() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group("city_root")
	if nodes.is_empty():
		return null
	return nodes[0] as Node


func _refresh_slot_styles() -> void:
	for i in _slot_buttons.size():
		var btn := _slot_buttons[i]
		if i == _selected_index:
			btn.modulate = Color(1.15, 1.2, 0.95)
		else:
			btn.modulate = Color(1, 1, 1)


func _update_detail() -> void:
	if _inventory == null or _selected_index < 0 or _selected_index >= InventoryCatalog.SLOT_COUNT:
		_detail_label.text = "Click a slot to inspect"
		return
	var slot := _inventory.slot_at(_selected_index)
	if slot.is_empty():
		_detail_label.text = "Empty slot"
		return
	var item_id := str(slot.get("id", ""))
	var count := int(slot.get("count", 0))
	var name := InventoryCatalog.display_name(item_id)
	_detail_label.text = "%s × %d" % [name, count]
