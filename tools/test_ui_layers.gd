## Guards the one thing every UI surface shares: draw order.
##
## The layer numbers used to be literals in a dozen unrelated scripts, and the inventory modal
## ended up under the energy bar and the build strip because nobody ever compared them. So the
## bands in UiLayers are checked against each other here, and then the real surfaces are built
## and asked what layer they claimed — a script that goes back to inventing its own number, or
## a band that stops separating HUD from modal, fails on this scene rather than in a screenshot.
##
## Run: powershell -File tools\run_test.ps1 test_ui_layers
extends Node

## Script → the layer its _ready must claim. Only surfaces that build without a live city; the
## build bar and the nav counters are covered by shot_modal_layers instead.
const SURFACES: Array[Dictionary] = [
	{"path": "res://scripts/city/infection_tendril_hud.gd", "layer": UiLayers.HUD_TENDRILS},
	{"path": "res://scripts/city/undead_invasion_hud.gd", "layer": UiLayers.HUD_UNDEAD},
	{"path": "res://scripts/city/city_minimap.gd", "layer": UiLayers.HUD_MINIMAP},
	{"path": "res://scripts/city/player_energy_hud.gd", "layer": UiLayers.HUD_ENERGY},
	{"path": "res://scripts/city/player_boost_hud.gd", "layer": UiLayers.HUD_BUFF},
	{"path": "res://scripts/city/player_compass_hud.gd", "layer": UiLayers.HUD_COMPASS},
	{"path": "res://scripts/city/zoo_cloak_hud.gd", "layer": UiLayers.HUD_ZOO_CLOAK},
	{"path": "res://scripts/city/siege_hud.gd", "layer": UiLayers.HUD_SIEGE},
	{"path": "res://scripts/city/city_settings_panel.gd", "layer": UiLayers.MODAL_SETTINGS},
	{"path": "res://scripts/city/player_inventory_panel.gd", "layer": UiLayers.MODAL_INVENTORY},
	{"path": "res://scripts/city/character_editor.gd", "layer": UiLayers.MODAL_CHARACTER_EDITOR},
	{"path": "res://scripts/city/monster_summon_panel.gd", "layer": UiLayers.MODAL_MONSTER_SUMMON},
	{"path": "res://scripts/city/siege_build_picker.gd", "layer": UiLayers.MODAL_SIEGE_BUILD},
	{"path": "res://scripts/city/game_menu_panel.gd", "layer": UiLayers.MODAL_GAME},
	{"path": "res://scripts/city/cheat_panel.gd", "layer": UiLayers.MODAL_CHEAT},
	{"path": "res://scripts/city/loading_splash.gd", "layer": UiLayers.LOADING_SPLASH},
]

## Autoload → the layer it must sit on. Both outrank every panel, so a hitch report or an error
## can never end up hidden behind one.
const AUTOLOADS: Dictionary = {
	"DamageLog": UiLayers.DEBUG_DAMAGE_LOG,
	"CityProfiler": UiLayers.DEBUG_PROFILER,
	"ErrorOverlay": UiLayers.ERROR_OVERLAY,
}

const HUD: Array[int] = [
	UiLayers.HUD_STATS,
	UiLayers.HUD_TENDRILS,
	UiLayers.HUD_UNDEAD,
	UiLayers.HUD_MINIMAP,
	UiLayers.HUD_ENERGY,
	UiLayers.HUD_ACTION_BAR,
	UiLayers.HUD_HEALTH,
	UiLayers.HUD_LOOT,
	UiLayers.HUD_BUFF,
	UiLayers.HUD_COMPASS,
	UiLayers.HUD_ZOO_CLOAK,
	UiLayers.HUD_SIEGE,
]

const MODALS: Array[int] = [
	UiLayers.MODAL_SETTINGS,
	UiLayers.MODAL_INVENTORY,
	UiLayers.MODAL_CHARACTER_EDITOR,
	UiLayers.MODAL_MONSTER_SUMMON,
	UiLayers.MODAL_SIEGE_BUILD,
	UiLayers.MODAL_GAME,
	UiLayers.MODAL_CHEAT,
]

const TAKEOVERS: Array[int] = [
	UiLayers.GAME_OVER,
	UiLayers.LOADING_SPLASH,
]

const DEBUG: Array[int] = [
	UiLayers.DEBUG_NAV_COUNTERS,
	UiLayers.DEBUG_DAMAGE_LOG,
	UiLayers.DEBUG_PROFILER,
	UiLayers.ERROR_OVERLAY,
]

var _failed := false


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _ready() -> void:
	_check_bands()
	_check_unique()
	_check_surfaces()
	_check_autoloads()
	print("RESULT: %s" % ("OK" if not _failed else "FAILED"))
	get_tree().quit(1 if _failed else 0)


## HUD < modal < takeover < debug, with the HUD band bounds tight enough that CityRoot's
## "hide everything in the HUD band" sweep cannot catch a modal.
func _check_bands() -> void:
	for layer in HUD:
		if layer < UiLayers.HUD_MIN or layer > UiLayers.HUD_MAX:
			_fail("FAIL HUD layer %d is outside the band %d..%d"
				% [layer, UiLayers.HUD_MIN, UiLayers.HUD_MAX])
	for layer in MODALS:
		if layer <= UiLayers.HUD_MAX:
			_fail("FAIL modal layer %d is not above the HUD band (%d)" % [layer, UiLayers.HUD_MAX])
	var top_modal: int = MODALS.max()
	for layer in TAKEOVERS:
		if layer <= top_modal:
			_fail("FAIL takeover layer %d is not above every modal (%d)" % [layer, top_modal])
	if UiLayers.LOADING_SPLASH <= UiLayers.GAME_OVER:
		_fail("FAIL the splash must cover the game over overlay")
	var top_takeover: int = TAKEOVERS.max()
	for layer in DEBUG:
		if layer <= top_takeover:
			_fail("FAIL debug layer %d is not above every takeover (%d)" % [layer, top_takeover])
	if UiLayers.ERROR_OVERLAY != (DEBUG + TAKEOVERS + MODALS + HUD).max():
		_fail("FAIL the error panel must be the frontmost surface in the game")
	print("OK bands: hud %s < modals %s < takeovers %s < debug %s"
		% [str(HUD), str(MODALS), str(TAKEOVERS), str(DEBUG)])


## Two surfaces sharing a layer fall back to tree order, which is the ambiguity this replaced.
func _check_unique() -> void:
	var seen: Array[int] = []
	for layer in HUD + MODALS + TAKEOVERS + DEBUG:
		if seen.has(layer):
			_fail("FAIL layer %d is claimed by two surfaces" % layer)
		seen.append(layer)


func _check_surfaces() -> void:
	for row in SURFACES:
		var path := str(row["path"])
		var want := int(row["layer"])
		var script: GDScript = load(path) as GDScript
		if script == null:
			_fail("FAIL %s is not a GDScript" % path)
			continue
		var surface: CanvasLayer = script.new() as CanvasLayer
		if surface == null:
			_fail("FAIL %s does not extend CanvasLayer" % path)
			continue
		## No frame is allowed to pass: these run _process against directors and a city that
		## this scene does not have.
		add_child(surface)
		var got := surface.layer
		remove_child(surface)
		surface.free()
		if got != want:
			_fail("FAIL %s claimed layer %d, expected %d" % [path, got, want])
			continue
		print("OK %s on layer %d" % [path.get_file(), got])


func _check_autoloads() -> void:
	for name in AUTOLOADS.keys():
		var autoload_name := str(name)
		var surface := get_tree().root.get_node_or_null(autoload_name) as CanvasLayer
		if surface == null:
			_fail("FAIL no %s autoload CanvasLayer" % autoload_name)
			continue
		var want := int(AUTOLOADS[name])
		if surface.layer != want:
			_fail("FAIL %s on layer %d, expected %d" % [autoload_name, surface.layer, want])
			continue
		print("OK %s autoload on layer %d" % [autoload_name, surface.layer])
