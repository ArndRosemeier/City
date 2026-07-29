## Autoload: rolling log of every DamageSource hit. Toggle with L (rebindable).
## Right-side overlay at 70% transparency so the city stays readable underneath.
extends CanvasLayer

const PlayerControlsScript := preload("res://scripts/city/player_controls.gd")
const UiLayersScript := preload("res://scripts/city/ui_layers.gd")
const DamageSourceScript := preload("res://scripts/city/damage_source.gd")

const MAX_LINES := 80
## Panel fill alpha: 70% transparent → 30% opaque.
const PANEL_ALPHA := 0.30

var _visible: bool = false
var _panel: PanelContainer
var _scroll: ScrollContainer
var _body: RichTextLabel
var _controls: PlayerControls
## Newest last.
var _entries: Array[Dictionary] = []


func _ready() -> void:
	layer = UiLayersScript.DEBUG_DAMAGE_LOG
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_panel.visible = false


func set_controls(controls: PlayerControls) -> void:
	_controls = controls


func _ctl() -> PlayerControls:
	if _controls == null:
		_controls = PlayerControlsScript.new() as PlayerControls
	return _controls


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if _ctl().matches_key_pressed(key, "damage_log"):
		set_overlay_enabled(not _visible)
		get_viewport().set_input_as_handled()


func set_overlay_enabled(on: bool) -> void:
	_visible = on
	_panel.visible = on
	if on:
		_refresh()


func is_overlay_enabled() -> bool:
	return _visible


func clear() -> void:
	_entries.clear()
	_refresh()


func entry_count() -> int:
	return _entries.size()


## Latest entries (newest last), for tests.
func entries() -> Array[Dictionary]:
	return _entries.duplicate()


## Record one landed hit. `amount` is points actually removed after armor/scale.
## `attacker` / `victim` are short display names (e.g. "player", "kaykit/Skeleton_Minion").
func record(
	attacker: String,
	victim: String,
	source: DamageSource.Id,
	amount: float,
	remaining: float,
	maximum: float,
	fatal: bool
) -> void:
	if amount <= 0.0 and not fatal:
		return
	var row: Dictionary = {
		"msec": Time.get_ticks_msec(),
		"attacker": attacker,
		"victim": victim,
		"source": DamageSourceScript.source_name(source),
		"amount": amount,
		"remaining": remaining,
		"maximum": maximum,
		"fatal": fatal,
	}
	_entries.append(row)
	while _entries.size() > MAX_LINES:
		_entries.remove_at(0)
	if _visible:
		_refresh()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "DamageLogPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -340.0
	_panel.offset_right = -12.0
	_panel.offset_top = 48.0
	_panel.offset_bottom = -48.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.07, PANEL_ALPHA)
	style.border_color = Color(0.55, 0.62, 0.72, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Damage log  (L)"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95, 0.95))
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 12)
	_body.add_theme_color_override("default_color", Color(0.9, 0.92, 0.95, 0.95))
	_scroll.add_child(_body)


func _refresh() -> void:
	if _body == null:
		return
	if _entries.is_empty():
		_body.text = "[color=#8899aa]No damage yet.[/color]"
		return
	var lines: PackedStringArray = PackedStringArray()
	for row in _entries:
		var fatal_tag := " [color=#ff6666]KILL[/color]" if bool(row["fatal"]) else ""
		lines.append(
			"[color=#aabbcc]%s[/color] → [color=#ddeeff]%s[/color]\n  %s  −%.1f  (%.0f/%.0f)%s"
			% [
				str(row["attacker"]),
				str(row["victim"]),
				str(row["source"]),
				float(row["amount"]),
				float(row["remaining"]),
				float(row["maximum"]),
				fatal_tag,
			]
		)
	_body.text = "\n".join(lines)
	call_deferred("_scroll_to_end")


func _scroll_to_end() -> void:
	if not is_instance_valid(_scroll):
		return
	var bar := _scroll.get_v_scroll_bar()
	if bar != null:
		_scroll.scroll_vertical = int(bar.max_value)
