## Run readout and cash-out for the Siege Quarter: wave, Lodestone HP, wave clock, the itemised pot,
## and the button that banks it.
##
## This carries the banking control because the world console cannot. A `Ui3D` is pressed by shooting
## it (`CityWalker._try_world_interact` converts any shot crossing the collider into a press), so a
## console standing by the crystal during a fight ends runs by accident — it did. Screen space is out
## of the line of fire, and the strip sits at the top where nothing is usually aimed.
##
## Shown while a run is live. CityRoot owns CanvasLayer visibility for the HUD band; this
## toggles an inner root the same way ZooCloakHud and LootToast do.
extends CanvasLayer

const InventoryIconCacheScript := preload("res://scripts/city/inventory_icon_cache.gd")

const ACCENT := Color(0.92, 0.72, 0.28, 1.0)
const DANGER := Color(1.0, 0.42, 0.32, 1.0)
const OK := Color(0.45, 0.88, 0.55, 1.0)
const MUTED := Color(0.62, 0.60, 0.58, 1.0)

## Typed array literal (not PackedStringArray(...)) — GDScript only treats `= [...]` as const.
## Same order as the stake console, so the tally reads the way the stake was chosen.
const GEM_IDS: PackedStringArray = [
	"gem_quartz", "gem_amber", "gem_topaz", "gem_sapphire", "gem_emerald", "gem_diamond",
]

const STRIP_W := 460.0
## Clear of the compass rose, which owns top-centre and was being covered by this strip — while the
## strip was telling the player which cardinal the next wave comes from.
const STRIP_TOP := PlayerCompassHud.BAND_BOTTOM + 10.0
const ICON_PX := 20.0
## How long a refused press holds the reason line before it goes back to the standing state.
const NOTICE_SEC := 3.0
## How long the first click stays armed. Banking is irreversible and ends the run, and this button
## shares screen with anything the player aims high at — a roof pad's "+" plate, for one. One stray
## click must not be able to cash out a run; two in three seconds is not stray.
const ARM_SEC := 3.0

@export var refresh_sec: float = 0.15

var _city: Node = null
var _root: Control
var _panel: PanelContainer
var _title: Label
var _wave: Label
var _pot: Label
## Outer stones left, and where the next wave is heading. The shield is the run's real clock, so it
## sits above the Lodestone's own bar.
var _stones: Label
var _lode: Label
var _clock: Label
var _tally: HBoxContainer
var _bank: Button
var _reason: Label
var _style: StyleBoxFlat
var _accum: float = 0.0
var _icons_ready: bool = false
var _icons_baking: bool = false
## item_id → the chip that shows it, so a refresh only retexts labels.
var _chips: Dictionary = {}
var _notice_text: String = ""
var _notice_until_msec: int = 0
var _armed_until_msec: int = 0


func _ready() -> void:
	layer = UiLayers.HUD_SIEGE
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.name = "SiegeStrip"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Top-centre, width fixed, height grown to fit the tally — anchors rather than a container
	## parent, so `_fit_strip` owns the box.
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -STRIP_W * 0.5
	_panel.offset_right = STRIP_W * 0.5
	_panel.offset_top = STRIP_TOP
	_panel.offset_bottom = STRIP_TOP + 120.0
	_style = StyleBoxFlat.new()
	_style.bg_color = Color(0.05, 0.04, 0.03, 0.90)
	_style.border_color = ACCENT
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(6)
	_style.content_margin_left = 14
	_style.content_margin_right = 14
	_style.content_margin_top = 6
	_style.content_margin_bottom = 6
	_panel.add_theme_stylebox_override("panel", _style)
	_root.add_child(_panel)

	var col := VBoxContainer.new()
	col.name = "Column"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 1)
	_panel.add_child(col)

	_title = _line("SIEGE", 14, ACCENT)
	col.add_child(_title)
	_wave = _line("Wave 0", 18, Color(0.95, 0.95, 0.92))
	col.add_child(_wave)
	_stones = _line("", 16, Color(0.62, 0.90, 1.0))
	col.add_child(_stones)
	_lode = _line("Lodestone —", 16, Color(0.92, 0.92, 0.88))
	col.add_child(_lode)
	_clock = _line("", 15, OK)
	col.add_child(_clock)
	_pot = _line("Pot 0", 16, Color(0.92, 0.92, 0.88))
	col.add_child(_pot)

	_tally = HBoxContainer.new()
	_tally.name = "Tally"
	_tally.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tally.alignment = BoxContainer.ALIGNMENT_CENTER
	_tally.add_theme_constant_override("separation", 10)
	col.add_child(_tally)
	_build_chips()

	_bank = Button.new()
	_bank.name = "BankButton"
	_bank.text = "STOP & WITHDRAW"
	_bank.focus_mode = Control.FOCUS_NONE
	_bank.custom_minimum_size = Vector2(0.0, 30.0)
	_bank.add_theme_font_size_override("font_size", 15)
	## The one node in the band that takes the mouse. `CityWalker` fires from `_unhandled_input`,
	## which never sees an event the GUI consumed, so a click here cannot also loose a bolt — the
	## same arrangement the ability tray uses.
	_bank.mouse_filter = Control.MOUSE_FILTER_STOP
	_bank.gui_input.connect(_on_bank_gui_input)
	col.add_child(_bank)

	_reason = _line("", 13, MUTED)
	col.add_child(_reason)
	set_process(true)


func bind_city(city: Node) -> void:
	_city = city
	_refresh()


func clear_display() -> void:
	_city = null
	if _root != null:
		_root.visible = false


## Baked on the first live run rather than at startup: each icon is an offscreen render, and most
## sessions never open a Siege Quarter.
func _bake_icons() -> void:
	_icons_baking = true
	await InventoryIconCacheScript.bake_ids(GEM_IDS, self)
	if not is_instance_valid(self):
		return
	_icons_ready = true
	_icons_baking = false
	for gem_id: String in GEM_IDS:
		var chip: Control = _chips.get(gem_id) as Control
		if chip == null:
			continue
		var tex := chip.get_node("Icon") as TextureRect
		tex.texture = InventoryIconCacheScript.texture_for(gem_id)


## One chip per gem type, built once and hidden until the pot holds that gem. Rebuilding the row
## every refresh would churn nodes six times a second for a readout that rarely changes.
func _build_chips() -> void:
	for gem_id: String in GEM_IDS:
		var chip := HBoxContainer.new()
		chip.name = "Chip_" + gem_id
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_theme_constant_override("separation", 3)
		chip.visible = false
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chip.add_child(icon)
		var count := _line("0", 15, Color(0.95, 0.95, 0.92))
		count.name = "Count"
		chip.add_child(count)
		_tally.add_child(chip)
		_chips[gem_id] = chip


func _line(text: String, size_px: int, color: Color) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", size_px)
	lab.add_theme_color_override("font_color", color)
	lab.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	lab.add_theme_constant_override("outline_size", 3)
	return lab


func _process(delta: float) -> void:
	_accum += delta
	if _accum < refresh_sec:
		return
	_accum = 0.0
	_refresh()


func _controller() -> SiegeController:
	if _city == null or not is_instance_valid(_city) or not _city.has_method("active_siege_run"):
		return null
	var ctrl: SiegeController = _city.call("active_siege_run") as SiegeController
	if ctrl == null or not is_instance_valid(ctrl) or not ctrl.is_running():
		return null
	return ctrl


func _refresh() -> void:
	if _root == null:
		return
	var ctrl := _controller()
	if ctrl == null:
		_root.visible = false
		return
	var stats: Dictionary = ctrl.get_hud_stats()
	_root.visible = true
	if not _icons_ready and not _icons_baking:
		_bake_icons()
	var phase := int(stats.get("phase", 0))
	var wave := int(stats.get("wave", 0))
	var pot := int(stats.get("pot_total", 0))
	var hp := float(stats.get("lodestone_hp", 0.0))
	var hp_max := float(stats.get("lodestone_hp_max", 1.0))
	var frac := 0.0 if hp_max <= 0.0 else hp / hp_max
	_wave.text = "Wave %d" % wave
	_pot.text = "Pot  %d gems" % pot
	_refresh_stones(stats)
	## While the shield holds, the centre's percentage is not the number that matters — say so
	## rather than showing a full bar the player might read as safety.
	var shielded := bool(stats.get("centre_shielded", false))
	_lode.text = (
		"Lodestone  shielded" if shielded else "Lodestone  %d%%" % int(round(frac * 100.0))
	)
	var centre_hurt := not shielded and frac < 0.35
	_lode.add_theme_color_override(
		"font_color", DANGER if centre_hurt else Color(0.92, 0.92, 0.88)
	)
	_style.border_color = DANGER if centre_hurt else ACCENT
	if phase == int(SiegeController.Phase.DEPLOY):
		var left := float(stats.get("deploy_left", 0.0))
		_clock.text = "Build — first wave in %s" % _clock_text(left)
		_clock.add_theme_color_override("font_color", OK)
		_title.text = "SIEGE · DEPLOY"
	else:
		var alive := int(stats.get("alive", 0))
		var queued := int(stats.get("queued", 0))
		var next := float(stats.get("wave_left", 0.0))
		_clock.text = "Alive %d · inbound %d · next %s" % [alive, queued, _clock_text(next)]
		_clock.add_theme_color_override("font_color", DANGER)
		_title.text = "SIEGE · HOLD"
	_refresh_tally(stats.get("pot", {}) as Dictionary)
	_refresh_bank(String(stats.get("withdraw_reason", "")), pot)
	_fit_strip()


## Outer stones left plus the forecast, on one line. "LAST STAND" is the loudest state the strip has
## because it is the only one where the pot can actually be lost.
func _refresh_stones(stats: Dictionary) -> void:
	var alive := int(stats.get("outer_alive", 0))
	var total := int(stats.get("outer_total", 0))
	var pressure := String(stats.get("next_pressure", ""))
	if total <= 0:
		_stones.visible = false
		return
	_stones.visible = true
	if alive <= 0:
		_stones.text = "LAST STAND — %s" % pressure if not pressure.is_empty() else "LAST STAND"
		_stones.add_theme_color_override("font_color", DANGER)
		return
	_stones.text = (
		"Outer stones %d/%d · %s" % [alive, total, pressure]
		if not pressure.is_empty()
		else "Outer stones %d/%d" % [alive, total]
	)
	_stones.add_theme_color_override("font_color", Color(0.62, 0.90, 1.0))


func _refresh_tally(pot: Dictionary) -> void:
	var shown := 0
	for gem_id: String in GEM_IDS:
		var chip: Control = _chips.get(gem_id) as Control
		if chip == null:
			continue
		var n := int(pot.get(gem_id, 0))
		chip.visible = n > 0
		if n > 0:
			shown += 1
			(chip.get_node("Count") as Label).text = "×%d" % n
	## Spending a tower can leave a zero-count key behind, so count what is actually drawn — an
	## empty row would still claim its height in the strip.
	_tally.visible = shown > 0


func _refresh_bank(reason: String, pot: int) -> void:
	var clear := reason.is_empty()
	if not clear:
		## Losing the ring disarms: a confirm the player lined up before a body walked in must not
		## still be waiting when they click again.
		_armed_until_msec = 0
	if _armed():
		_bank.text = "CONFIRM  bank %d gems" % pot
		_bank.add_theme_color_override("font_color", DANGER)
	else:
		_bank.text = (
			"STOP & WITHDRAW  %d gems" % pot if clear else "STOP & WITHDRAW  (blocked)"
		)
		_bank.add_theme_color_override("font_color", OK if clear else MUTED)
	if _notice_active():
		_reason.text = _notice_text
		_reason.add_theme_color_override("font_color", DANGER)
		return
	_reason.text = reason if not clear else "Banking ends the run and keeps the pot"
	_reason.add_theme_color_override("font_color", MUTED if clear else ACCENT)


## Hug the content: the tally row and the reason line change height as the run goes on, and a fixed
## box would either clip the chips or float a slab of empty background over the sky.
func _fit_strip() -> void:
	var wanted := _panel.get_combined_minimum_size().y
	if wanted > 0.0 and not is_equal_approx(_panel.offset_bottom, STRIP_TOP + wanted):
		_panel.offset_bottom = STRIP_TOP + wanted


func _on_bank_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	## Handled either way: the walker fires from `_unhandled_input`, and a press that banked a run
	## must not also loose a bolt into the crowd the player just cleared.
	get_viewport().set_input_as_handled()
	var ctrl := _controller()
	if ctrl == null:
		return
	var reason := ctrl.withdraw_block_reason()
	if not reason.is_empty():
		_armed_until_msec = 0
		_show_notice(reason)
		return
	if not _armed():
		_armed_until_msec = Time.get_ticks_msec() + int(ARM_SEC * 1000.0)
		_show_notice("Click again to bank %d gems and end the run" % ctrl.pot_total())
		return
	_armed_until_msec = 0
	if not ctrl.withdraw():
		## The ring can turn between the two clicks; that is the mode working, not a fault.
		_show_notice(ctrl.withdraw_block_reason())


func _show_notice(text: String) -> void:
	_notice_text = text
	_notice_until_msec = Time.get_ticks_msec() + int(NOTICE_SEC * 1000.0)
	_reason.text = text
	_reason.add_theme_color_override("font_color", DANGER)


func _armed() -> bool:
	if _armed_until_msec <= 0:
		return false
	if Time.get_ticks_msec() >= _armed_until_msec:
		_armed_until_msec = 0
		return false
	return true


func _notice_active() -> bool:
	if _notice_text.is_empty():
		return false
	if Time.get_ticks_msec() >= _notice_until_msec:
		_notice_text = ""
		return false
	return true


static func _clock_text(seconds: float) -> String:
	var whole := maxi(int(ceil(seconds)), 0)
	return "%d:%02d" % [whole / 60, whole % 60]
