## N-key monster summon modal: Random first, then every spawnable catalogue body
## grouped by combat-table faction (with section dividers). Confirm with Enter / click;
## Esc or dim dismisses without spawning.
class_name MonsterSummonPanel
extends CanvasLayer

signal opened
signal closed
signal summon_requested(monster_id: String)

const CreatureCatalogScript := preload("res://scripts/city/creature_catalog.gd")
const MonsterFactionScript := preload("res://scripts/city/monster_faction.gd")
const CombatTableScript := preload("res://scripts/city/combat_table.gd")

const RANDOM_ID := ""
## Sentinel in `_row_ids` for non-selectable faction headers.
const HEADER_ID := "__faction_header__"
## Wide enough for long body ids + faction chrome, with room to grow.
const PANEL_WIDTH := 820.0
const PANEL_HEIGHT := 640.0
const LIST_HEIGHT := 500.0

var _open: bool = false
var _dim: ColorRect
var _panel: PanelContainer
var _list: ItemList
var _hint: Label
## Row index → monster id (empty = Random; HEADER_ID = section divider).
var _row_ids: PackedStringArray = PackedStringArray()


func _ready() -> void:
	layer = UiLayers.MODAL_MONSTER_SUMMON
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false
	set_process_unhandled_input(true)


func is_open() -> bool:
	return _open


## Ids shown under Random: every CreatureCatalog body with spawn slots, faction order.
static func summonable_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for group: Dictionary in summonable_groups():
		var ids: PackedStringArray = group["ids"] as PackedStringArray
		out.append_array(ids)
	return out


## Faction bands for boards / lists: [{ "faction": Id, "name": String, "ids": PackedStringArray }].
## Empty factions are omitted. Ids within a band are sorted.
static func summonable_groups() -> Array[Dictionary]:
	var buckets: Dictionary = {}  ## String faction name → PackedStringArray
	for entry: CreatureCatalog.Entry in CreatureCatalogScript.all():
		if not entry.is_spawnable():
			continue
		if not CombatTableScript.has_monster(entry.id):
			push_error(
				"MonsterSummonPanel: spawnable '%s' has no combat_table faction" % entry.id
			)
			assert(false, "MonsterSummonPanel: spawnable missing combat row")
			continue
		var fname := CombatTableScript.faction_for(entry.id)
		if not buckets.has(fname):
			buckets[fname] = PackedStringArray()
		var arr: PackedStringArray = buckets[fname] as PackedStringArray
		arr.append(entry.id)
		buckets[fname] = arr
	var groups: Array[Dictionary] = []
	for fid: MonsterFaction.Id in MonsterFactionScript.all():
		## Unique is encounter-only — never arena pads or the N-key catalogue.
		if fid == MonsterFaction.Id.UNIQUE:
			continue
		var name := MonsterFactionScript.faction_name(fid)
		if not buckets.has(name):
			continue
		var ids: PackedStringArray = buckets[name] as PackedStringArray
		ids.sort()
		groups.append({"faction": fid, "name": name, "ids": ids})
	## Loud if a combat faction string is not in MonsterFaction.all().
	for fname: Variant in buckets.keys():
		var known := false
		for fid2: MonsterFaction.Id in MonsterFactionScript.all():
			if MonsterFactionScript.faction_name(fid2) == str(fname):
				known = true
				break
		if not known:
			push_error("MonsterSummonPanel: unknown faction '%s' on spawnable bodies" % str(fname))
			assert(false, "MonsterSummonPanel: unknown faction")
	return groups


## Display labels in list order (Random first; faction headers included).
static func list_labels() -> PackedStringArray:
	var labels := PackedStringArray(["Random"])
	for group: Dictionary in summonable_groups():
		var name: String = str(group["name"])
		labels.append("—— %s ——" % name.capitalize())
		var ids: PackedStringArray = group["ids"] as PackedStringArray
		for mid: String in ids:
			labels.append(mid)
	return labels


func open_panel() -> void:
	if _open:
		return
	_rebuild_list()
	_open = true
	visible = true
	_dim.visible = true
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _list.item_count > 0:
		_list.select(0)
		_list.ensure_current_is_visible()
		_list.grab_focus()
	opened.emit()


func close_panel() -> void:
	if not _open:
		return
	_open = false
	visible = false
	_dim.visible = false
	_panel.visible = false
	closed.emit()


func toggle_panel() -> void:
	if _open:
		close_panel()
	else:
		open_panel()


## Confirm the current selection. Empty string means Random (caller rolls).
func selected_monster_id() -> String:
	if _list == null or _list.item_count == 0:
		return RANDOM_ID
	var selected := _list.get_selected_items()
	if selected.is_empty():
		return RANDOM_ID
	var idx: int = selected[0]
	if idx < 0 or idx >= _row_ids.size():
		push_error("MonsterSummonPanel.selected_monster_id: index %d out of range" % idx)
		return RANDOM_ID
	var mid := _row_ids[idx]
	if mid == HEADER_ID:
		return RANDOM_ID
	return mid


## Probe/accessibility helper: choose a concrete row through the same list the player sees.
func select_monster_id(monster_id: String) -> void:
	var index := _row_ids.find(monster_id)
	if index < 0:
		push_error("MonsterSummonPanel.select_monster_id: '%s' is not in the panel" % monster_id)
		assert(false, "MonsterSummonPanel: missing requested row")
		return
	_list.select(index)
	_list.ensure_current_is_visible()


func confirm_selection() -> void:
	if not _open:
		return
	var mid := selected_monster_id()
	if mid == HEADER_ID:
		return
	## Aim was sampled when N opened the panel (world aim point). Closing must not re-aim.
	summon_requested.emit(mid)
	close_panel()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	var ek := event as InputEventKey
	if ek != null and ek.pressed and not ek.echo:
		if ek.keycode == KEY_ESCAPE or ek.physical_keycode == KEY_ESCAPE:
			close_panel()
			get_viewport().set_input_as_handled()
			return
		if ek.keycode == KEY_ENTER or ek.physical_keycode == KEY_ENTER \
				or ek.keycode == KEY_KP_ENTER or ek.physical_keycode == KEY_KP_ENTER:
			confirm_selection()
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
	title.text = "Summon Monster"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	_hint = Label.new()
	_hint.text = "Look at ground before N · Enter / click to spawn there · Esc to cancel"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.modulate = Color(0.75, 0.78, 0.85)
	col.add_child(_hint)

	_list = ItemList.new()
	_list.name = "MonsterList"
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(PANEL_WIDTH - 48.0, LIST_HEIGHT)
	_list.allow_reselect = true
	_list.item_activated.connect(_on_item_activated)
	col.add_child(_list)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.pressed.connect(close_panel)
	row.add_child(cancel_btn)

	var summon_btn := Button.new()
	summon_btn.text = "Summon"
	summon_btn.focus_mode = Control.FOCUS_NONE
	summon_btn.pressed.connect(confirm_selection)
	row.add_child(summon_btn)


func _rebuild_list() -> void:
	_list.clear()
	_row_ids = PackedStringArray()
	_row_ids.append(RANDOM_ID)
	_list.add_item("Random")
	for group: Dictionary in summonable_groups():
		var name: String = str(group["name"])
		var header_i := _list.add_item("—— %s ——" % name.capitalize())
		_list.set_item_selectable(header_i, false)
		_list.set_item_disabled(header_i, true)
		_list.set_item_custom_fg_color(header_i, Color(0.72, 0.78, 0.88, 1.0))
		_row_ids.append(HEADER_ID)
		var ids: PackedStringArray = group["ids"] as PackedStringArray
		for mid: String in ids:
			_row_ids.append(mid)
			_list.add_item(mid)
	if _list.item_count == 0:
		push_error("MonsterSummonPanel: no summonable monsters")
		assert(false, "MonsterSummonPanel: empty roster")


func _on_item_activated(index: int) -> void:
	if index < 0 or index >= _row_ids.size():
		return
	if _row_ids[index] == HEADER_ID:
		return
	_list.select(index)
	confirm_selection()


func _on_dim_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		close_panel()
