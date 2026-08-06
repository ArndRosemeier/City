## Every CanvasLayer number in the game, back to front. These used to be literals spread over
## a dozen scripts, which is how the energy bar and the build strip ended up drawing on top of
## the inventory modal; a new surface takes its constant from here instead of picking a number.
##
## Bands, in draw order: HUD (10–20) < modals (21–29) < screen takeovers (40–59) < debug and
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
## Buff area under the FPS line (cloud stacks, tonic chips, grow/shrink). Below loot so a
## find still owns the eye. `HUD_BOOST` kept as an alias for older call sites / tests.
const HUD_BUFF := 18
const HUD_BOOST := HUD_BUFF
## Heading rose. Top of the band with loot: always-on travel chrome, never over a find card.
const HUD_COMPASS := 19
## Monster Zoo spectator cloak countdown. Top of the band because it is the one readout that
## says whether the thing walking at you is allowed to hit you, and it expires on a clock.
const HUD_ZOO_CLOAK := 20
## Siege Quarter run strip: wave, pot, Lodestone HP. Above the cloak because a live defence
## is the thing that decides whether the pot survives, and it has a clock of its own.
const HUD_SIEGE := 21
const HUD_MAX := 21

## Panels that own the screen while open. Above every HUD surface, below every takeover.
## CityRoot closes the other one when either opens, so only ever one of these is up.
const MODAL_SETTINGS := 22
const MODAL_INVENTORY := 23
const MODAL_CHARACTER_EDITOR := 24
const MODAL_MONSTER_SUMMON := 25
## Save / load / new game. Session lifecycle, kept out of Settings so graphics knobs and the
## decision to throw the run away are never one mis-click apart.
const MODAL_GAME := 26
## Debug fill / teleport panel. A modal rather than a debug overlay so it owns the cursor and
## the HUD the same way Inventory does — dumping a probe into a translucent layer over play
## left the mouse stuck in freelook.
const MODAL_CHEAT := 27
## Siege tower picker, opened from a pad's "+" plate. A modal rather than a HUD popup: it owns
## the cursor the player just clicked a world panel with, and leaving blaster fire live under an
## open recipe list is how you spend a gem and shoot your own Lodestone in the same click.
const MODAL_SIEGE_BUILD := 28
## Siege zone helper sheet, opened from the Lodestone console's Details button.
const MODAL_SIEGE_DETAILS := 29

## Whole-screen state changes, above any modal.
const GAME_OVER := 40
const LOADING_SPLASH := 50
## Boot ran out of ways to place the player. Above the splash, which is still up when this
## appears and would otherwise bury the only way out of a world that failed to build.
const BOOT_FAILURE := 55

## Debug and failure surfaces, above modals and takeovers.
const DEBUG_NAV_COUNTERS := 110
const DEBUG_DAMAGE_LOG := 115
const DEBUG_PROFILER := 120
const ERROR_OVERLAY := 128
