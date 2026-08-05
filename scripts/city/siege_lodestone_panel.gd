## World console at the Siege Lodestone: stake gems to start, withdraw between waves.
##
## Click-aim like every other Ui3D (Zoo cloak post, Arena boards) — not the unused E key.
## The stake is chosen here and handed to `SiegeController.start_run`; the pot itself lives
## on the controller and is shown on `SiegeHud` once a run is live.
class_name SiegeLodestonePanel
extends "res://scripts/city/ui_3d.gd"

signal start_requested(stake: Dictionary)
signal withdraw_requested()

const InventoryIconCacheScript := preload("res://scripts/city/inventory_icon_cache.gd")

const PANEL_W := 3.4
const PANEL_H := 2.6

## Typed array literals (not PackedStringArray(...)) — GDScript only treats `= [...]` as const.
const GEM_IDS: PackedStringArray = [
	"gem_quartz", "gem_amber", "gem_topaz", "gem_sapphire", "gem_emerald", "gem_diamond",
]

const BTN_START := &"start"
const BTN_WITHDRAW := &"withdraw"
const BTN_MINUS_PREFIX := "m_"
const BTN_PLUS_PREFIX := "p_"
const BTN_COUNT_PREFIX := "c_"
const BTN_ICON_PREFIX := "i_"

const IDLE_COLOR := Color(0.78, 0.62, 0.22, 1.0)
const RUN_COLOR := Color(0.35, 0.78, 0.92, 1.0)
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


## Clock / HP text only. Cheap enough for a quarter-second tick during a live run.
func tick_display() -> void:
	_refresh_labels()
	if _controller == null or not is_instance_valid(_controller):
		return
	## Withdraw button carries the live pot total — refresh just that label while waiting.
	if int(_controller.phase()) == int(SiegeController.Phase.INTERMISSION):
		add_button(
			BTN_WITHDRAW,
			Rect2(0.10, 0.08, 0.80, 0.22),
			"WITHDRAW  pot %d" % _controller.pot_total(),
			OK_COLOR
		)


func _rebuild_face() -> void:
	clear_buttons()
	if _controller == null or not is_instance_valid(_controller):
		return
	var phase: int = int(_controller.phase())
	match phase:
		SiegeController.Phase.IDLE, SiegeController.Phase.WITHDRAWN, SiegeController.Phase.LOST:
			_build_idle_face()
		SiegeController.Phase.INTERMISSION:
			_build_intermission_face()
		SiegeController.Phase.WAVE:
			_build_wave_face()
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


func _build_intermission_face() -> void:
	add_button(
		BTN_WITHDRAW,
		Rect2(0.10, 0.08, 0.80, 0.22),
		"WITHDRAW  pot %d" % _controller.pot_total(),
		OK_COLOR,
		true
	)


func _build_wave_face() -> void:
	## No controls mid-wave — withdrawing mid-fight would be an exploit and the design
	## only allows it between waves. The face still swallows clicks so the Lodestone is not
	## a free shoot-through.
	add_button(
		&"wave_status",
		Rect2(0.10, 0.20, 0.80, 0.30),
		"WAVE %d" % _controller.wave_number(),
		RUN_COLOR,
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
		SiegeController.Phase.INTERMISSION:
			_caption.text = "WAVE %d CLEAR" % _controller.wave_number()
			_caption.modulate = RUN_COLOR
			_status.text = "Next in %s · pot %d" % [
				_clock(_controller.intermission_left()),
				_controller.pot_total(),
			]
			_status.modulate = RUN_COLOR
			set_surface_glow(Color(0.04, 0.10, 0.14, 1.0), 1.4)
		SiegeController.Phase.WAVE:
			_caption.text = "WAVE %d" % _controller.wave_number()
			_caption.modulate = DANGER_COLOR
			var frac := 0.0
			if _controller.lodestone_hp_max() > 0.0:
				frac = _controller.lodestone_hp() / _controller.lodestone_hp_max()
			_status.text = "Lodestone %d%% · pot %d" % [
				int(round(frac * 100.0)),
				_controller.pot_total(),
			]
			_status.modulate = DANGER_COLOR
			set_surface_glow(Color(0.14, 0.04, 0.04, 1.0), 1.6)


func _on_button_pressed(button_id: StringName, _uv: Vector2) -> void:
	var id := String(button_id)
	if button_id == BTN_START:
		_try_start()
		return
	if button_id == BTN_WITHDRAW:
		withdraw_requested.emit()
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


static func _clock(seconds: float) -> String:
	var whole := maxi(int(ceil(seconds)), 0)
	return "%d:%02d" % [whole / 60, whole % 60]
