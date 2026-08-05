## World console at the Siege Lodestone: where a run is staked, and nothing else.
##
## Between runs only. `SiegeController._refresh_panel` hides this the whole time a run is live,
## because a `Ui3D` is pressed by *shooting* it — `CityWalker._try_world_interact` converts any shot
## that crosses the collider into a button press — and this one stands a metre and a half from the
## crystal, right where the fight is. Everything the player needs mid-run, the pot tally and the
## banking button included, lives on `SiegeHud` where no bolt can reach it.
##
## Click-aim like every other Ui3D (Zoo cloak post, Arena boards) — not the unused E key.
class_name SiegeLodestonePanel
extends "res://scripts/city/ui_3d.gd"

signal start_requested(stake: Dictionary)

const InventoryIconCacheScript := preload("res://scripts/city/inventory_icon_cache.gd")

const PANEL_W := 3.4
const PANEL_H := 2.6

## Typed array literals (not PackedStringArray(...)) — GDScript only treats `= [...]` as const.
const GEM_IDS: PackedStringArray = [
	"gem_quartz", "gem_amber", "gem_topaz", "gem_sapphire", "gem_emerald", "gem_diamond",
]

const BTN_START := &"start"
const BTN_MINUS_PREFIX := "m_"
const BTN_PLUS_PREFIX := "p_"
const BTN_COUNT_PREFIX := "c_"
const BTN_ICON_PREFIX := "i_"

const IDLE_COLOR := Color(0.78, 0.62, 0.22, 1.0)
const DANGER_COLOR := Color(0.92, 0.32, 0.28, 1.0)
const MUTED_COLOR := Color(0.28, 0.26, 0.24, 1.0)
const OK_COLOR := Color(0.28, 0.72, 0.38, 1.0)
const ICON_BG := Color(0.12, 0.10, 0.09, 1.0)
const ICON_TINT := Color.WHITE

## UV band for the six gem rows — leave a clear gap above START.
const GEM_TOP := 0.76
const GEM_BOT := 0.20
const START_Y := 0.04
const START_H := 0.13

var _controller: SiegeController = null
var _stake: Dictionary = {}
var _caption: Label3D = null
var _status: Label3D = null
var _icons_ready: bool = false


func setup_panel(origin: Vector3, face_yaw: float, controller: SiegeController) -> void:
	name = "SiegeLodestonePanel"
	_controller = controller
	size_m = Vector2(PANEL_W, PANEL_H)
	show_debug_marker = false
	surface_color = Color(0.07, 0.06, 0.05, 1.0)
	for id: String in GEM_IDS:
		_stake[id] = 0
	_rebuild_face()
	begin(origin, face_yaw)
	_build_labels()
	if not button_pressed.is_connected(_on_button_pressed):
		button_pressed.connect(_on_button_pressed)
	refresh()
	_bake_icons()


func _bake_icons() -> void:
	await InventoryIconCacheScript.bake_ids(GEM_IDS, self)
	if not is_instance_valid(self):
		return
	_icons_ready = true
	refresh()


## Full face rebuild — call on phase changes and after stake +/-.
func refresh() -> void:
	if _controller == null or not is_instance_valid(_controller):
		return
	_rebuild_face()
	_refresh_labels()


## Label text only, for the idle console's own clock. The controller stops ticking this while a run
## is live because the console is hidden then.
func tick_display() -> void:
	_refresh_labels()


func _rebuild_face() -> void:
	clear_buttons()
	if _controller == null or not is_instance_valid(_controller):
		return
	var phase: int = int(_controller.phase())
	match phase:
		SiegeController.Phase.IDLE, SiegeController.Phase.WITHDRAWN, SiegeController.Phase.LOST:
			_build_idle_face()
		SiegeController.Phase.DEPLOY, SiegeController.Phase.RUNNING:
			## Buttonless on purpose. The controller hides this console for the whole run, and a
			## pressable face behind that curtain is exactly the accident that shipped.
			pass
	rebuild_buttons()


func _build_idle_face() -> void:
	var n_rows := GEM_IDS.size()
	var row_h := 0.078
	var span := GEM_TOP - GEM_BOT
	var gap := (span - float(n_rows) * row_h) / float(maxi(n_rows - 1, 1))
	var margin_x := 0.05
	var side_w := 0.11
	## Square icon in world metres → UV width from the panel aspect.
	var icon_w := row_h * PANEL_H / PANEL_W
	for i in range(n_rows):
		var y := GEM_TOP - float(i) * (row_h + gap)
		var id := GEM_IDS[i]
		var n := int(_stake.get(id, 0))
		var y0 := y - row_h
		var x := margin_x
		add_button(
			StringName(BTN_MINUS_PREFIX + id),
			Rect2(x, y0, side_w, row_h),
			"−",
			MUTED_COLOR,
			true
		)
		x += side_w + 0.012
		var tex: Texture2D = (
			InventoryIconCacheScript.texture_for(id) if _icons_ready else null
		)
		add_button(
			StringName(BTN_ICON_PREFIX + id),
			Rect2(x, y0, icon_w, row_h),
			"",
			ICON_TINT if tex != null else MUTED_COLOR,
			true,
			tex,
			ICON_BG
		)
		x += icon_w + 0.012
		var plus_x := 1.0 - margin_x - side_w
		add_button(
			StringName(BTN_COUNT_PREFIX + id),
			Rect2(x, y0, plus_x - 0.012 - x, row_h),
			"%s  %d" % [_gem_label(id), n],
			IDLE_COLOR,
			true
		)
		add_button(
			StringName(BTN_PLUS_PREFIX + id),
			Rect2(plus_x, y0, side_w, row_h),
			"+",
			MUTED_COLOR,
			true
		)
	var total := _stake_total()
	var min_stake := _controller.min_stake_total()
	var can_start := total >= min_stake
	add_button(
		BTN_START,
		Rect2(0.10, START_Y, 0.80, START_H),
		"START  %d/%d" % [total, min_stake] if not can_start else "START  %d gems" % total,
		OK_COLOR if can_start else MUTED_COLOR,
		true
	)


func _build_labels() -> void:
	_caption = Label3D.new()
	_caption.name = "Caption"
	_caption.font_size = 72
	_caption.pixel_size = (PANEL_H * 0.10) / 72.0
	_caption.outline_size = 16
	_caption.outline_modulate = Color(0.0, 0.0, 0.0, 0.92)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_caption.double_sided = true
	_caption.position = Vector3(0.0, PANEL_H * 0.42, -0.05)
	_caption.rotation.y = PI
	add_child(_caption)

	_status = Label3D.new()
	_status.name = "Status"
	_status.font_size = 48
	_status.pixel_size = (PANEL_H * 0.07) / 48.0
	_status.outline_size = 12
	_status.outline_modulate = Color(0.0, 0.0, 0.0, 0.92)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_status.double_sided = true
	_status.position = Vector3(0.0, PANEL_H * 0.34, -0.05)
	_status.rotation.y = PI
	add_child(_status)
	_refresh_labels()


func _refresh_labels() -> void:
	if _caption == null or _status == null:
		return
	if _controller == null or not is_instance_valid(_controller):
		return
	var phase: int = int(_controller.phase())
	match phase:
		SiegeController.Phase.IDLE:
			_caption.text = "LODESTONE"
			_caption.modulate = IDLE_COLOR
			_status.text = "Stake gems to begin"
			_status.modulate = IDLE_COLOR
			set_surface_glow(Color(0.12, 0.09, 0.04, 1.0), 0.8)
		SiegeController.Phase.WITHDRAWN:
			_caption.text = "LODESTONE"
			_caption.modulate = OK_COLOR
			_status.text = "Banked — stake again?"
			_status.modulate = OK_COLOR
			set_surface_glow(Color(0.04, 0.12, 0.06, 1.0), 1.0)
		SiegeController.Phase.LOST:
			_caption.text = "LODESTONE FALLEN"
			_caption.modulate = DANGER_COLOR
			_status.text = "Pot lost — stake again?"
			_status.modulate = DANGER_COLOR
			set_surface_glow(Color(0.14, 0.03, 0.03, 1.0), 1.2)
		SiegeController.Phase.DEPLOY, SiegeController.Phase.RUNNING:
			## Hidden while a run is live; this is only what a stray frame would show.
			_caption.text = "SIEGE UNDER WAY"
			_caption.modulate = DANGER_COLOR
			_status.text = "Bank from the siege readout"
			_status.modulate = DANGER_COLOR
			set_surface_glow(Color(0.14, 0.04, 0.04, 1.0), 1.6)


func _on_button_pressed(button_id: StringName, _uv: Vector2) -> void:
	var id := String(button_id)
	if button_id == BTN_START:
		_try_start()
		return
	if id.begins_with(BTN_ICON_PREFIX) or id.begins_with(BTN_COUNT_PREFIX):
		return
	if id.begins_with(BTN_PLUS_PREFIX):
		_bump_stake(id.substr(BTN_PLUS_PREFIX.length()), 1)
		return
	if id.begins_with(BTN_MINUS_PREFIX):
		_bump_stake(id.substr(BTN_MINUS_PREFIX.length()), -1)
		return


func _try_start() -> void:
	if _stake_total() < _controller.min_stake_total():
		return
	var stake: Dictionary = {}
	for gem_id: String in GEM_IDS:
		var n := int(_stake.get(gem_id, 0))
		if n > 0:
			stake[gem_id] = n
	start_requested.emit(stake)


func _bump_stake(gem_id: String, delta: int) -> void:
	if not GEM_IDS.has(gem_id):
		return
	var inv := _inventory()
	if inv == null:
		return
	var have := inv.count_of(gem_id)
	var next := clampi(int(_stake.get(gem_id, 0)) + delta, 0, have)
	_stake[gem_id] = next
	refresh()


func _stake_total() -> int:
	var n := 0
	for gem_id: String in GEM_IDS:
		n += int(_stake.get(gem_id, 0))
	return n


func _inventory() -> PlayerInventory:
	if _controller == null or not is_instance_valid(_controller):
		return null
	return _controller.inventory()


func _gem_label(gem_id: String) -> String:
	var def := InventoryCatalog.item(gem_id)
	if def == null:
		return gem_id
	return def.display_name
