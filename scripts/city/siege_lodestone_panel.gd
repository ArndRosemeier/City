## World console at the Siege Lodestone: start a run, or open the zone details.
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

signal start_requested
signal details_requested

const PANEL_W := 2.8
const PANEL_H := 1.7

const BTN_START := &"start"
const BTN_DETAILS := &"details"

const IDLE_COLOR := Color(0.78, 0.62, 0.22, 1.0)
const DANGER_COLOR := Color(0.92, 0.32, 0.28, 1.0)
const MUTED_COLOR := Color(0.28, 0.26, 0.24, 1.0)
const OK_COLOR := Color(0.28, 0.72, 0.38, 1.0)
const INFO_COLOR := Color(0.55, 0.68, 0.82, 1.0)

## One short line of what this district is. The Details modal carries the rest.
const BLURB := "Defend the stones. Towers cost gems from your bag.\nKill loot goes into a pot you can bank here."

const BTN_Y := 0.06
const BTN_H := 0.16
const BTN_GAP := 0.04
const BTN_SIDE_M := 0.08

var _controller: SiegeController = null
var _caption: Label3D = null
var _status: Label3D = null
var _blurb: Label3D = null


func setup_panel(origin: Vector3, face_yaw: float, controller: SiegeController) -> void:
	name = "SiegeLodestonePanel"
	_controller = controller
	size_m = Vector2(PANEL_W, PANEL_H)
	show_debug_marker = false
	surface_color = Color(0.07, 0.06, 0.05, 1.0)
	_rebuild_face()
	begin(origin, face_yaw)
	_build_labels()
	if not button_pressed.is_connected(_on_button_pressed):
		button_pressed.connect(_on_button_pressed)
	refresh()


## Full face rebuild — call on phase changes.
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
	var half := (1.0 - BTN_SIDE_M * 2.0 - BTN_GAP) * 0.5
	add_button(
		BTN_DETAILS,
		Rect2(BTN_SIDE_M, BTN_Y, half, BTN_H),
		"DETAILS",
		INFO_COLOR,
		true
	)
	add_button(
		BTN_START,
		Rect2(BTN_SIDE_M + half + BTN_GAP, BTN_Y, half, BTN_H),
		"START",
		OK_COLOR,
		true
	)


func _build_labels() -> void:
	_caption = Label3D.new()
	_caption.name = "Caption"
	_caption.font_size = 72
	_caption.pixel_size = (PANEL_H * 0.11) / 72.0
	_caption.outline_size = 16
	_caption.outline_modulate = Color(0.0, 0.0, 0.0, 0.92)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_caption.double_sided = true
	_caption.position = Vector3(0.0, PANEL_H * 0.38, -0.05)
	_caption.rotation.y = PI
	add_child(_caption)

	_status = Label3D.new()
	_status.name = "Status"
	_status.font_size = 42
	_status.pixel_size = (PANEL_H * 0.07) / 42.0
	_status.outline_size = 12
	_status.outline_modulate = Color(0.0, 0.0, 0.0, 0.92)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_status.double_sided = true
	_status.position = Vector3(0.0, PANEL_H * 0.28, -0.05)
	_status.rotation.y = PI
	add_child(_status)

	_blurb = Label3D.new()
	_blurb.name = "Blurb"
	_blurb.font_size = 36
	_blurb.pixel_size = (PANEL_H * 0.055) / 36.0
	_blurb.outline_size = 10
	_blurb.outline_modulate = Color(0.0, 0.0, 0.0, 0.92)
	_blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blurb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_blurb.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_blurb.double_sided = true
	_blurb.modulate = Color(0.86, 0.84, 0.78, 1.0)
	_blurb.position = Vector3(0.0, PANEL_H * 0.02, -0.05)
	_blurb.rotation.y = PI
	_blurb.text = BLURB
	add_child(_blurb)
	_refresh_labels()


func _refresh_labels() -> void:
	if _caption == null or _status == null:
		return
	if _controller == null or not is_instance_valid(_controller):
		return
	var phase: int = int(_controller.phase())
	if _blurb != null:
		_blurb.visible = (
			phase == SiegeController.Phase.IDLE
			or phase == SiegeController.Phase.WITHDRAWN
			or phase == SiegeController.Phase.LOST
		)
	match phase:
		SiegeController.Phase.IDLE:
			_caption.text = "LODESTONE"
			_caption.modulate = IDLE_COLOR
			_status.text = "Siege Quarter"
			_status.modulate = IDLE_COLOR
			set_surface_glow(Color(0.12, 0.09, 0.04, 1.0), 0.8)
		SiegeController.Phase.WITHDRAWN:
			_caption.text = "LODESTONE"
			_caption.modulate = OK_COLOR
			_status.text = "Banked — start again?"
			_status.modulate = OK_COLOR
			set_surface_glow(Color(0.04, 0.12, 0.06, 1.0), 1.0)
		SiegeController.Phase.LOST:
			_caption.text = "LODESTONE FALLEN"
			_caption.modulate = DANGER_COLOR
			_status.text = "Pot lost — start again?"
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
	if button_id == BTN_START:
		start_requested.emit()
		return
	if button_id == BTN_DETAILS:
		details_requested.emit()
		return
