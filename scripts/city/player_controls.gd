## Rebindable player controls. Stored as Dictionaries; consumed by walker / root / bars.
class_name PlayerControls
extends RefCounted

## device: "key" | "mouse"; code: Key or MouseButton; optional shift/ctrl/alt.
const ACTION_META: Array[Dictionary] = [
	{"id": "move_forward", "label": "Move forward", "group": "Movement"},
	{"id": "move_back", "label": "Move back", "group": "Movement"},
	{"id": "turn_left", "label": "Turn left", "group": "Movement"},
	{"id": "turn_right", "label": "Turn right", "group": "Movement"},
	{"id": "jump", "label": "Jump (hold to rise)", "group": "Movement"},
	{"id": "sprint", "label": "Sprint", "group": "Movement"},
	{"id": "autorun", "label": "Autorun toggle", "group": "Movement"},
	{"id": "district_hop", "label": "Jump to district type (J)", "group": "Movement"},
	{"id": "look_up", "label": "Look up", "group": "Camera"},
	{"id": "look_down", "label": "Look down", "group": "Camera"},
	{"id": "look", "label": "Hold to look", "group": "Camera"},
	{"id": "zoom_in", "label": "Zoom in", "group": "Camera"},
	{"id": "zoom_out", "label": "Zoom out", "group": "Camera"},
	{"id": "fire", "label": "Charged blast (Alt+LMB)", "group": "Combat"},
	{"id": "laser", "label": "Eye laser (Ctrl+LMB)", "group": "Combat"},
	{"id": "beam", "label": "Blaster beam (LMB)", "group": "Combat"},
	{"id": "stomp", "label": "Stomp (tray only)", "group": "Combat"},
	{"id": "character_editor", "label": "Character editor", "group": "Character"},
	{"id": "inventory", "label": "Inventory", "group": "Character"},
	{"id": "sound_toggle", "label": "Sound on/off", "group": "Character"},
	{"id": "monster_summon", "label": "Summon monster (N)", "group": "World"},
	{"id": "tetris", "label": "Spawn Tetris", "group": "World"},
	{"id": "aim_panel", "label": "Spawn aim panel (Z)", "group": "World"},
	{"id": "day_night", "label": "Day / night (Y)", "group": "World"},
	{"id": "interact", "label": "Interact", "group": "World"},
	{"id": "build_1", "label": "Build slot 1", "group": "Build"},
	{"id": "build_2", "label": "Build slot 2", "group": "Build"},
	{"id": "build_3", "label": "Build slot 3", "group": "Build"},
	{"id": "build_4", "label": "Build slot 4", "group": "Build"},
	{"id": "build_5", "label": "Build slot 5", "group": "Build"},
	{"id": "build_6", "label": "Build slot 6", "group": "Build"},
	{"id": "build_assign", "label": "Build assign modifier", "group": "Build"},
	{"id": "damage_log", "label": "Damage log (L)", "group": "System"},
	{"id": "profiler", "label": "Profiler overlay", "group": "System"},
	{"id": "nav_overlay", "label": "Navigation overlay", "group": "System"},
	{"id": "nav_overlay_colour", "label": "Navigation overlay colouring", "group": "System"},
	{"id": "quit", "label": "Quit", "group": "System"},
	{"id": "retry", "label": "Retry (game over)", "group": "System"},
]

## Extra always-on keys (not shown in UI) so arrows / numpad keep working.
const ALIASES: Dictionary = {
	"move_forward": [KEY_UP],
	"move_back": [KEY_DOWN],
	"turn_left": [KEY_LEFT],
	"turn_right": [KEY_RIGHT],
	"retry": [KEY_KP_ENTER],
}

var _binds: Dictionary = {}  # action_id → Dictionary


func _init() -> void:
	reset_to_defaults()


func reset_to_defaults() -> void:
	_binds.clear()
	for row in ACTION_META:
		_binds[str(row["id"])] = default_binding(str(row["id"]))


static func default_binding(action_id: String) -> Dictionary:
	match action_id:
		"move_forward":
			return _key(KEY_W)
		"move_back":
			return _key(KEY_S)
		"turn_left":
			return _key(KEY_A)
		"turn_right":
			return _key(KEY_D)
		"jump":
			return _key(KEY_SPACE)
		"sprint":
			return _key(KEY_SHIFT)
		"autorun":
			return _key(KEY_R)
		"district_hop":
			return _key(KEY_J)
		"look_up":
			return _key(KEY_PAGEUP)
		"look_down":
			return _key(KEY_PAGEDOWN)
		"look":
			return _mouse(MOUSE_BUTTON_RIGHT)
		"zoom_in":
			return _mouse(MOUSE_BUTTON_WHEEL_UP)
		"zoom_out":
			return _mouse(MOUSE_BUTTON_WHEEL_DOWN)
		"fire":
			return _mouse(MOUSE_BUTTON_LEFT, false, false, true)
		"laser":
			return _mouse(MOUSE_BUTTON_LEFT, false, true, false)
		"beam":
			return _mouse(MOUSE_BUTTON_LEFT)
		"stomp":
			## Tray-assignable only — no default key (was Q).
			return _key(KEY_NONE)
		"character_editor":
			return _key(KEY_C)
		"inventory":
			return _key(KEY_I)
		"sound_toggle":
			return _key(KEY_O)
		"monster_summon":
			return _key(KEY_N)
		"tetris":
			return _key(KEY_T)
		"aim_panel":
			return _key(KEY_Z)
		"day_night":
			return _key(KEY_Y)
		"interact":
			return _key(KEY_E)
		"build_1":
			return _key(KEY_F1)
		"build_2":
			return _key(KEY_F2)
		"build_3":
			return _key(KEY_F3)
		"build_4":
			return _key(KEY_F4)
		"build_5":
			return _key(KEY_F5)
		"build_6":
			return _key(KEY_F6)
		"build_assign":
			return _key(KEY_SHIFT)
		"damage_log":
			return _key(KEY_L)
		"profiler":
			return _key(KEY_F7)
		"nav_overlay":
			return _key(KEY_F8)
		## Shares F8 with the toggle; the shift-carrying bind is resolved first, exactly
		## like Alt+LMB blast wins over bare LMB beam.
		"nav_overlay_colour":
			return _key(KEY_F8, true)
		"quit":
			return _key(KEY_ESCAPE)
		"retry":
			return _key(KEY_ENTER)
		_:
			push_error("PlayerControls.default_binding: unknown action '%s'" % action_id)
			return _key(KEY_NONE)


static func _key(code: Key, shift := false, ctrl := false, alt := false) -> Dictionary:
	return {
		"device": "key",
		"code": int(code),
		"shift": shift,
		"ctrl": ctrl,
		"alt": alt,
	}


static func _mouse(code: MouseButton, shift := false, ctrl := false, alt := false) -> Dictionary:
	return {
		"device": "mouse",
		"code": int(code),
		"shift": shift,
		"ctrl": ctrl,
		"alt": alt,
	}


func get_binding(action_id: String) -> Dictionary:
	if _binds.has(action_id):
		return (_binds[action_id] as Dictionary).duplicate(true)
	return default_binding(action_id)


func set_binding(action_id: String, binding: Dictionary) -> void:
	if action_id.is_empty():
		return
	_binds[action_id] = {
		"device": str(binding.get("device", "key")),
		"code": int(binding.get("code", 0)),
		"shift": bool(binding.get("shift", false)),
		"ctrl": bool(binding.get("ctrl", false)),
		"alt": bool(binding.get("alt", false)),
	}


func to_save_dict() -> Dictionary:
	var out := {}
	for id in _binds.keys():
		out[id] = (_binds[id] as Dictionary).duplicate(true)
	return out


func load_save_dict(data: Dictionary) -> void:
	reset_to_defaults()
	for id in data.keys():
		var sid := str(id)
		if not _binds.has(sid):
			continue
		var raw: Variant = data[id]
		if raw is Dictionary:
			set_binding(sid, raw as Dictionary)


func binding_label(action_id: String) -> String:
	return format_binding(get_binding(action_id))


static func format_binding(b: Dictionary) -> String:
	var parts: PackedStringArray = []
	if bool(b.get("ctrl", false)):
		parts.append("Ctrl")
	if bool(b.get("shift", false)):
		parts.append("Shift")
	if bool(b.get("alt", false)):
		parts.append("Alt")
	var device := str(b.get("device", "key"))
	var code := int(b.get("code", 0))
	if device == "mouse":
		parts.append(_mouse_name(code as MouseButton))
	else:
		parts.append(_key_name(code as Key))
	return "+".join(parts)


static func _key_name(code: Key) -> String:
	if code == KEY_NONE or code == KEY_UNKNOWN:
		return "?"
	var label := OS.get_keycode_string(code)
	if label.is_empty():
		return "Key%d" % int(code)
	return label


static func _mouse_name(button: MouseButton) -> String:
	match button:
		MOUSE_BUTTON_LEFT:
			return "LMB"
		MOUSE_BUTTON_RIGHT:
			return "RMB"
		MOUSE_BUTTON_MIDDLE:
			return "MMB"
		MOUSE_BUTTON_WHEEL_UP:
			return "Wheel Up"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "Wheel Down"
		MOUSE_BUTTON_WHEEL_LEFT:
			return "Wheel Left"
		MOUSE_BUTTON_WHEEL_RIGHT:
			return "Wheel Right"
		MOUSE_BUTTON_XBUTTON1:
			return "Mouse4"
		MOUSE_BUTTON_XBUTTON2:
			return "Mouse5"
		_:
			return "Mouse%d" % int(button)


func is_key_held(action_id: String) -> bool:
	var b := get_binding(action_id)
	if str(b.get("device", "")) != "key":
		return false
	var code := int(b.get("code", 0)) as Key
	if code == KEY_NONE or not Input.is_key_pressed(code):
		## Aliases (arrows / numpad).
		if ALIASES.has(action_id):
			for alt_code in ALIASES[action_id]:
				if Input.is_key_pressed(alt_code as Key):
					return true
		return false
	if bool(b.get("shift", false)) and not Input.is_key_pressed(KEY_SHIFT):
		return false
	if bool(b.get("ctrl", false)) and not Input.is_key_pressed(KEY_CTRL):
		return false
	if bool(b.get("alt", false)) and not Input.is_key_pressed(KEY_ALT):
		return false
	return true


func matches_key_pressed(event: InputEventKey, action_id: String) -> bool:
	if not event.pressed or event.echo:
		return false
	return _matches_key_event(event, action_id)


func matches_key_released(event: InputEventKey, action_id: String) -> bool:
	if event.pressed or event.echo:
		return false
	return _matches_key_event(event, action_id)


func _matches_key_event(event: InputEventKey, action_id: String) -> bool:
	var b := get_binding(action_id)
	if str(b.get("device", "")) != "key":
		## Alias-only match when primary is a mouse bind? skip.
		if ALIASES.has(action_id):
			for alt_code in ALIASES[action_id]:
				if event.keycode == (alt_code as Key) or event.physical_keycode == (alt_code as Key):
					return true
		return false
	var code := int(b.get("code", 0)) as Key
	if code == KEY_NONE:
		## Unbound action (e.g. stomp is tray-only).
		return false
	var hit := event.keycode == code or event.physical_keycode == code
	if not hit and ALIASES.has(action_id):
		for alt_code in ALIASES[action_id]:
			if event.keycode == (alt_code as Key) or event.physical_keycode == (alt_code as Key):
				hit = true
				break
	if not hit:
		return false
	## Required modifiers must be held; extra modifiers are OK.
	## (Otherwise Shift+Space fails jump while sprinting — bare Space demanded shift=off.)
	if bool(b.get("shift", false)) and not event.shift_pressed:
		return false
	if bool(b.get("ctrl", false)) and not event.ctrl_pressed:
		return false
	if bool(b.get("alt", false)) and not event.alt_pressed:
		return false
	return true


func matches_mouse(event: InputEventMouseButton, action_id: String) -> bool:
	var b := get_binding(action_id)
	if str(b.get("device", "")) != "mouse":
		return false
	if int(event.button_index) != int(b.get("code", -1)):
		return false
	## Same as keys: require listed mods only. resolve_mouse_action still prefers
	## the more-specific bind (Alt+LMB blast over bare LMB beam).
	if bool(b.get("shift", false)) and not event.shift_pressed:
		return false
	if bool(b.get("ctrl", false)) and not event.ctrl_pressed:
		return false
	if bool(b.get("alt", false)) and not event.alt_pressed:
		return false
	return true


## Prefer the mouse action whose modifiers match most specifically.
func resolve_mouse_action(event: InputEventMouseButton, action_ids: Array[String]) -> String:
	var best := ""
	var best_score := -1
	for id in action_ids:
		if not matches_mouse(event, id):
			continue
		var b := get_binding(id)
		var score := 0
		if bool(b.get("ctrl", false)):
			score += 1
		if bool(b.get("shift", false)):
			score += 1
		if bool(b.get("alt", false)):
			score += 1
		## Prefer modifier-heavy binds over bare LMB when both somehow match.
		if score > best_score:
			best_score = score
			best = id
	return best


func build_slot_for_key(event: InputEventKey) -> int:
	## Slot keys ignore modifiers so Shift/Ctrl+slot can mean assign.
	for i in range(6):
		var b := get_binding("build_%d" % (i + 1))
		if str(b.get("device", "")) != "key":
			continue
		var code := int(b.get("code", 0)) as Key
		if event.keycode == code or event.physical_keycode == code:
			return i
	return -1


func is_build_assign_held(event: InputEvent) -> bool:
	## True when the build-assign modifier is down for this event (Shift by default).
	## Used for Shift+F1–F6 and Shift+click on tray buttons — not for world mouse combat.
	var b := get_binding("build_assign")
	if str(b.get("device", "")) != "key":
		var with_mods := event as InputEventWithModifiers
		return with_mods != null and with_mods.shift_pressed
	var code := int(b.get("code", KEY_SHIFT)) as Key
	## When assign modifier is Shift/Ctrl/Alt, use the event flag so slot key+mod works.
	var with_m := event as InputEventWithModifiers
	match code:
		KEY_SHIFT:
			return with_m != null and with_m.shift_pressed
		KEY_CTRL:
			return with_m != null and with_m.ctrl_pressed
		KEY_ALT:
			return with_m != null and with_m.alt_pressed
		_:
			return Input.is_key_pressed(code)
