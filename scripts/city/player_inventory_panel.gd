## Inventory modal: 25 stackable slots + craft list. Toggle with I; Esc closes.
class_name PlayerInventoryPanel
extends CanvasLayer

signal opened
signal closed
signal craft_requested(recipe_id: String)

const SLOT_PX := 72.0
const GRID_COLS := 5
const VIEW_SIZE := Vector2i(64, 64)
const CAM_FOV := 35.0
## Slack between the item's bounding sphere and the edge of the square render target.
const CAM_FIT_MARGIN := 1.12
## How far the camera stands above the item, as a fraction of its distance from it.
const CAM_RISE := 0.11

var _inventory: PlayerInventory
var _open: bool = false
var _dim: ColorRect
var _panel: PanelContainer
var _detail_label: Label
var _craft_box: VBoxContainer
var _slot_buttons: Array[Button] = []
var _slot_viewports: Array[SubViewport] = []
var _slot_worlds: Array[Node3D] = []
var _slot_cameras: Array[Camera3D] = []
var _slot_meshes: Array[MeshInstance3D] = []
var _slot_counts: Array[Label] = []
var _selected_index: int = -1
var _craft_buttons: Dictionary = {} ## recipe_id → Button


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


## Eye point of every slot camera: a touch above the item at the origin of the slot's own
## world, far enough back that the item's bounding sphere fits the square target at CAM_FOV.
static func slot_camera_position() -> Vector3:
	var half_fov := deg_to_rad(CAM_FOV * 0.5)
	var back := InventoryItemVisual.bounding_radius() * CAM_FIT_MARGIN / sin(half_fov)
	return Vector3(0.0, back * CAM_RISE, back)


func slot_viewport(index: int) -> SubViewport:
	if index < 0 or index >= _slot_viewports.size():
		push_error("PlayerInventoryPanel.slot_viewport: index %d out of range" % index)
		return null
	return _slot_viewports[index]


func slot_camera(index: int) -> Camera3D:
	if index < 0 or index >= _slot_cameras.size():
		push_error("PlayerInventoryPanel.slot_camera: index %d out of range" % index)
		return null
	return _slot_cameras[index]


## The preview currently shown in a slot, or null while the slot is empty.
func slot_mesh(index: int) -> MeshInstance3D:
	if index < 0 or index >= _slot_meshes.size():
		push_error("PlayerInventoryPanel.slot_mesh: index %d out of range" % index)
		return null
	return _slot_meshes[index]


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
	for mesh in _slot_meshes:
		InventoryItemVisual.tick_trap_pulse(mesh, t)


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ek := event as InputEventKey
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
	title_row.add_child(hint)

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
	_slot_viewports.clear()
	_slot_worlds.clear()
	_slot_cameras.clear()
	_slot_meshes.clear()
	_slot_counts.clear()
	for i in InventoryCatalog.SLOT_COUNT:
		grid.add_child(_make_slot(i))

	var craft_panel := PanelContainer.new()
	craft_panel.custom_minimum_size = Vector2(200, 0)
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
	_rebuild_craft_list()

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

	var vp_host := SubViewportContainer.new()
	vp_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp_host.offset_left = 4
	vp_host.offset_top = 4
	vp_host.offset_right = -4
	vp_host.offset_bottom = -4
	vp_host.stretch = true
	vp_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(vp_host)

	var vp := SubViewport.new()
	vp.size = VIEW_SIZE
	vp.transparent_bg = true
	## A slot previews one item against nothing. Without a world of its own the preview
	## camera, light and mesh would all land in the game's World3D.
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	vp_host.add_child(vp)
	_slot_viewports.append(vp)

	var world := Node3D.new()
	vp.add_child(world)
	_slot_worlds.append(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40.0, 35.0, 0.0)
	light.light_energy = 1.1
	world.add_child(light)
	var cam := Camera3D.new()
	cam.fov = CAM_FOV
	## The whole slot is built detached and only enters the tree when the caller adds it to
	## the grid, so the aim has to come from the given eye point rather than a global one.
	cam.look_at_from_position(slot_camera_position(), Vector3.ZERO, Vector3.UP)
	world.add_child(cam)
	_slot_cameras.append(cam)
	## Placeholder empty; mesh swapped on refresh.
	_slot_meshes.append(null)

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


func _rebuild_craft_list() -> void:
	for child in _craft_box.get_children():
		if child is Button:
			child.queue_free()
	_craft_buttons.clear()
	for recipe in InventoryCatalog.all_recipes():
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = _recipe_button_text(recipe)
		btn.pressed.connect(_on_craft_pressed.bind(recipe.id))
		_craft_box.add_child(btn)
		_craft_buttons[recipe.id] = btn


func _recipe_button_text(recipe: InventoryCatalog.Recipe) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for item_id in recipe.inputs.keys():
		parts.append(
			"%d %s" % [int(recipe.inputs[item_id]), InventoryCatalog.display_name(String(item_id))]
		)
	return "%s\n(%s)" % [recipe.display_name, ", ".join(parts)]


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_panel()


func _on_slot_pressed(index: int) -> void:
	_selected_index = index
	_update_detail()
	_refresh_slot_styles()


func _on_craft_pressed(recipe_id: String) -> void:
	craft_requested.emit(recipe_id)


func _refresh() -> void:
	if _inventory == null:
		return
	for i in InventoryCatalog.SLOT_COUNT:
		_refresh_slot(i)
	_update_detail()
	_refresh_craft_buttons()
	_refresh_slot_styles()


func _refresh_slot(index: int) -> void:
	var slot := _inventory.slot_at(index)
	var count_lbl := _slot_counts[index]
	var world := _slot_worlds[index]
	var old: MeshInstance3D = _slot_meshes[index]
	if old != null and is_instance_valid(old):
		## Detached first: a queued free still draws for the rest of the frame, on top of
		## the replacement that is about to be added at the same spot.
		world.remove_child(old)
		old.queue_free()
	_slot_meshes[index] = null
	if slot.is_empty():
		count_lbl.text = ""
		return
	var item_id := str(slot.get("id", ""))
	var count := int(slot.get("count", 0))
	count_lbl.text = str(count) if count > 1 else ""
	var mesh := InventoryItemVisual.make_mesh(item_id)
	if mesh == null:
		return
	world.add_child(mesh)
	if InventoryCatalog.item(item_id).is_trap:
		mesh.set_meta("trap_pulse", true)
	_slot_meshes[index] = mesh


func _refresh_craft_buttons() -> void:
	for recipe_id in _craft_buttons.keys():
		var btn: Button = _craft_buttons[recipe_id]
		var can := _inventory != null and _inventory.can_craft(String(recipe_id))
		btn.disabled = not can
		var recipe := InventoryCatalog.recipe(String(recipe_id))
		if recipe != null:
			btn.text = _recipe_button_text(recipe)
			if can:
				btn.modulate = Color(1, 1, 1)
			else:
				btn.modulate = Color(0.65, 0.65, 0.7)


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
