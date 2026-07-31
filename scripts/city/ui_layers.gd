## Every CanvasLayer number in the game, back to front. These used to be literals spread over
## a dozen scripts, which is how the energy bar and the build strip ended up drawing on top of
## the inventory modal; a new surface takes its constant from here instead of picking a number.
##
## Bands, in draw order: HUD (10–19) < modals (20–29) < screen takeovers (40–59) < debug and
## failure surfaces (110+). The debug band outranks everything on purpose — a modal must never
## be able to hide a hitch report or an error.
class_name UiLayers
extends RefCounted

## Always-on gameplay readouts. CityRoot hides this whole band while a modal is open, so the
## band bounds have to stay tight around the HUD entries below.
const HUD_MIN := 10
const HUD_STATS := 10
const HUD_TENDRILS := 11
const HUD_UNDEAD := 12
const HUD_MINIMAP := 13
const HUD_ENERGY := 14
const HUD_ACTION_BAR := 15
## Wounds. Above the energy bar because the two never overlap on screen and, if a future layout
## ever puts them close, the one that decides whether the run continues should be the one on top.
const HUD_HEALTH := 16
## The loot card. Top of the HUD band: it is transient and sits over the bars for a second or two,
## and a find the player cannot see is the whole thing this surface exists to fix.
const HUD_LOOT := 17
const HUD_MAX := 19

## Panels that own the screen while open. Above every HUD surface, below every takeover.
## CityRoot closes the other one when either opens, so only ever one of these is up.
const MODAL_SETTINGS := 20
const MODAL_INVENTORY := 21
const MODAL_CHARACTER_EDITOR := 22
const MODAL_MONSTER_SUMMON := 23
## Save / load / new game. Session lifecycle, kept out of Settings so graphics knobs and the
## decision to throw the run away are never one mis-click apart.
const MODAL_GAME := 24

## Whole-screen state changes, above any modal.
const GAME_OVER := 40
const LOADING_SPLASH := 50

## Debug and failure surfaces, above modals and takeovers.
const DEBUG_NAV_COUNTERS := 110
const DEBUG_DAMAGE_LOG := 115
const DEBUG_PROFILER := 120
const ERROR_OVERLAY := 128
