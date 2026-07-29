# Eccentri City — Procedural voxel city (Godot 4)

Procedural voxel city of weird ideas (product id **EccentriCity**). Skinned MPFB
pedestrians, Quaternius cars, sidewalks/curbs, crosswalks, street lights, infection,
and oversized player power. Human showcase: `start_crowd.bat` / `scenes/main.tscn`.

Title art: `assets/branding/eccentricity_title.png` (cinematic; alt sketch in
`eccentricity_title_a.png`).

## Download (Windows)

Grab the latest player build from
[**GitHub Releases**](https://github.com/ArndRosemeier/City/releases/latest):

1. Download **EccentriCityPortable-windows.zip** and unzip it.
2. Double-click **`EccentriCity.bat`**.
3. First launch downloads Godot 4.6 + Voxel Tools (~80 MB; internet once) and
   imports assets (a few minutes). Later launches work offline.

No Rust or Visual Studio required. `city_voxel.dll` is included in the zip.

## Requirements (developers)

- Godot **4.6 + Voxel Tools** (`tools/godot/Godot_v4.6-voxel_win64.exe`) for the city POC
- **`addons/city_voxel/bin/city_voxel.dll`** (required — bake volume + cascade debris; rebuild with `tools/build_city_voxel.ps1`)
- Optional stock Godot 4.3+ for the human showcase (`start_crowd.bat` / `scenes/main.tscn`)

## Run (city)

Double-click **`EccentriCity.bat`** — downloads
the voxel engine if needed, imports assets on first run, then starts the city.

### Install (Windows) — for players

From an unzipped release (or a folder built by `make_installer.bat`), double-click
**`install_city.bat`**. It copies the game into `%LOCALAPPDATA%\Programs\EccentriCity`
and adds Desktop / Start Menu shortcuts.

If the engine is missing, **`EccentriCity.bat`** / **`install_city.bat`** download
Godot 4.6 + Voxel Tools 1.6 from
[Zylann/godot_voxel](https://github.com/Zylann/godot_voxel/releases/tag/v1.6).

```
install_city.bat
install_city.bat /D "D:\Games\EccentriCity"
```

### Make / publish a package — for you (developer)

One pipeline: **`tools/pack_release.ps1`**. It stages **git-tracked files only**
(so dirty working-tree junk cannot leak in), imports, validates, then emits a folder
and/or zip.

```
make_installer.bat              -> dist\EccentriCityPortable\   (engine + .godot)
publish_portable_release.bat    -> slim zip + GitHub Release
publish_portable_release.bat /SkipUpload   -> zip only
powershell -File tools\pack_release.ps1 -Mode Check   -> tracking policy only
powershell -File tools\check_tracking.ps1             -> same check
```

`city_voxel.dll` must be committed. Player excludes (pack scripts, `native/` sources,
`.cursor/`, …) live in `tools/ship_excludes.txt`.

### Tracking policy

**Track by default.** Anything not listed in `.gitignore` is expected to be in git.
`tools/check_tracking.ps1` fails on unexpected untracked files and on missing required
ship files / `.uid` sidecars. CI runs the same check on every push to `main`.

Controls: **WASD** walk · **Mouse** look · **LMB** dig · **R** autorun · **Esc** quit · **I** inventory · **J** jump to district type · **Y** day/night · **F1–F6** build · **Shift+F1–F6** assign build · **N** summon monster at mouse aim (Random + catalogue spawnables) · **M** meteor · **T** Tetris Game Boy · **P** pedestrian · **L** damage log (right-side overlay) · **F7** profiler (hitches ≥80 ms print to console as `CityProfiler HITCH`) · **Settings** (top-right) for quality. Settings → Graphics → Diagnostics → **Log stutters to file** mirrors those hitch reports into `%APPDATA%\Godot\app_userdata\EccentriCity\city_hitches.log` (the same panel has an *Open log folder* button), so a stutter can be reported without a console open.

Build: aim with the mouse, press **F1–F6** to stamp the bound recipe at the cursor (cottage / pool / hot tub / statues by default). **Shift+F1–F6** opens the full recipe list to rebind a slot. Fronts face you. Builds are session-local and disappear when that district streams out.

Tetris (after **T**): **1** left · **2** rotate · **3** right · **4** fast drop (tap once). Cabinet is `GAMEBOY` voxels — destroy any piece of it and the game breaks. **P** near a cabinet spawns a pedestrian who walks up, plays, and AI-controls the game.

## Layout

```
assets/humans/     MPFB bases, outfits, Quaternius Idle/Walk
assets/city/       Voxel textures
assets/combat/     Shared attacks.json + behaviours.json
assets/monsters/   combat_table.json (templates + per-body rows)
assets/vehicles/   Quaternius CC0 car GLBs + catalog.json
scenes/            city_poc.tscn, main.tscn
scripts/city/      District generation, crowd, street lights; CombatTable resolver
scripts/vehicles/  VehicleDirector / catalog / visuals
scripts/humans/    Outfits, proportions
LICENSE_ASSETS.md  Content license provenance
```

## Combat tables

Editable data for monster templates, behaviours, attacks, and per-body overrides lives in
JSON under `assets/combat/` and `assets/monsters/combat_table.json`. Resolve rules
(template scalar **max**, list **union**, prey-weight **average**, body
`attacks_extra` / hard `attacks`, attack damage = `damage_vs_*` × `damage_mult`)
are implemented twice and kept in lockstep:

- Python: `tools/combat_resolve.py` (used by the editor and validators)
- Godot: `scripts/city/combat_table.gd` (`CombatTable.resolve`)

```
python tools/edit_combat_tables.py          # tkinter editor (effective-stats preview)
python tools/validate_combat_tables.py      # schema + refs + golden sync check
python tools/sync_combat_resolve.py --write # regenerate tools/fixtures/combat_effective_stats.json
powershell -File tools/run_test.ps1 test_combat_table_sync
```

After changing merge rules, update **both** Python and GDScript, then rewrite the golden
fixture. This does not by itself wire AI to the tables — it restores the data + sync guard.

## World seed

Every launch draws a fresh world seed, so each game starts in a different city. District
layouts still come from that seed mixed with the district's grid coordinate, so a world is
fully reproducible: the seed is printed at startup and `--city-seed=N` replays it. Setting
`city_seed` in the scene or from code (as the tools do) pins it as well; leaving it at `0`
means "pick a new one". The player boots into a random district tile within three
tiles of the world origin (chosen from the same seed, so `--city-seed=N` also
replays the spawn). Override with `--spawn-district=x,z` or `--spawn-theme=hill`
(etc.). In-game, **J** opens a district-type picker and teleports to the nearest
matching tile. The tile at the world origin is still always the downtown core theme,
even when you spawn elsewhere.

## District themes

Every district tile picks a theme deterministically from the world seed and its grid
coordinate (`scripts/city/district_theme.gd`): **Core High-Rise**, **Old Town**,
**Waterfront Industrial**, **Garden Residential** or **Civic Quarter**. The theme sets
the wall / roof / paving palette, the building archetype weights and a height scale, so
the tile at the world origin is always the downtown core and the quarters around it get
lower and older. Themes also weight **eccentric massing**: spiral stair towers
(`spiral_chance`), L/T footprints (`l_mass_chance`), and cylinder midrise / silos
(`cylinder_chance`) — see `BuildingGrammar.spiral_tower` / `cylinder_midrise`.

Inside a tile, land use comes from a noise **intensity field** computed on world cell
coordinates (`DistrictPlanner.intensity`) rather than distance from the tile centre, so
dense clusters run across district borders and the same field drives per-lot building
heights — the skyline has peaks and valleys instead of one plateau per tile.

Terrain voxels share three shaders (`assets/city/shaders/voxel_surface.gdshader`,
`voxel_glass.gdshader`, `voxel_water.gdshader`). They project textures from world space
onto the dominant face axis, so materials read at real-world scale (a brick course is a
brick course, not one texture per 0.5 m cube) and get per-lot tint variation, grime and
ground-contact dirt. `scripts/city/voxel_surface_spec.gd` holds the per-material table.

Parks (`scripts/city/park_composer.gd`) are laid out as landscaping rather than a lawn
with props on it: a meandering tree-lined promenade, a strolling loop just inside the
border, a pond scaled to the park with a stone rim and a spur path to the water, clustered
groves over worn earth, hedges framing the edge, and a few flower beds and benches beside
the walkways. Planting only ever lands on lawn voxels, which keeps it off the paths and
out of the water automatically.

Checks: `tools/test_voxel_surface_shader.gd` (run with `--script`),
`tools/test_district_themes.tscn` and `tools/shot_city_parks.tscn` (run as scenes — the
city scripts need the `CityProfiler` autoload).

## Vehicles

Cars are generated by `scripts/vehicles/procedural_vehicle.gd` from the profiles in
`assets/vehicles/catalog.json`. Each profile lofts a hull from a top line and a plan
line, with elliptical arch cutouts over the axles; every quad carries explicit
per-face normals so the result stays faceted instead of smooth-shaded. Cabins are
sized from a measured seated passenger (1.259 m at scale 0.92 — see
`tools/measure_passenger_seat.gd`) so riders never clip the roof.

The mesh root publishes `body_length` / `body_width` / `body_height`; `VehicleVisual`
uses those for collision and hit tests so mirrors and antennas cannot inflate a car's
extents.

Checks: `tools/test_procedural_vehicle.gd` and `tools/test_vehicle_glass.gd` (run with
`--script`). Looks: `tools/shot_car_showroom.tscn` for a lit pad lineup and per-profile
close-ups, `tools/shot_city_traffic.tscn` for cars photographed in live traffic.

## Voxel write funnel

Every live voxel write goes through `CityBrush` (`scripts/city/city_brush.gd`). Nothing
else may call `VoxelTool.do_point` / `do_box` / `set_voxel` on the city terrain — blasts,
melee, gem pickup, giant scrapes, infection tendrils, meteors, the Tetris cabinet and
`BuildPlacer` all use the one brush `CityRoot.voxel_brush()` hands out.

The brush publishes `voxels_changed(aabb_vox: AABB)` after each finished edit, in world
voxel space (`position` = inclusive min, `end` = exclusive max). Wrap a multi-voxel edit
in `begin_edit()` / `end_edit()` so it reports one region instead of one per cell.
Subscribers (navigation rebuild) connect on the brush; district *bake* brushes paint into
an offline volume and stay silent, because baked tiles publish their own data at load.

`NativeCascadeDebris` clears collapsing columns from Rust over several frames
(`native/city_voxel/src/cascade_debris.rs`, `clear_voxel`) — spread neighbours and bark
canopy that GDScript cannot predict — so it cannot route through the brush. It publishes
the same `voxels_changed(aabb_vox: AABB)` instead, one region per navigation sector per
frame, and `NavDirtyTracker` subscribes to both. District loading stays outside either
signal: it commits whole 16³ blocks with `VoxelTerrain.try_set_block_data` rather than
editing cells, and the tile it loads brings its own baked navigation.

What a frame pays for that is bounded twice. `NavDirtyTracker` coalesces edits into queued
*regions* of up to 2x2 navigation sectors, because a burst of writes in one place must not
cost a rescan each — but it drains them one **sector** at a time, so a blast straddling a
sector border cannot hand a frame an indivisible rebuild larger than the ~2 ms budget.
`NavService` starts another unit only while the budget it has left covers the dearest unit
measured so far; the first always runs, so the queue cannot stall. The material copy each
unit reads spans the voxel rows the navigation field was baked over plus the link probes'
reach above them (`NativeNavWorld.rebuild_y_range`), not the terrain's full 220 rows.

Checks: `tools/test_voxel_write_funnel.tscn` for the brush funnel,
`tools/test_nav_dirty_rebuild.tscn` for both signals reaching navigation (run as scenes).

## Navigation

One `NavService` owns the navigation world: a native span field per district (walkable
surface spans with the clearance over them, portals between sectors, links for drops and
climbs) and one `NavProfile` per kind of walker. The profile decides what is legal — radius,
height, `max_step`, `max_drop`, `max_wade`, whether it can swim or climb — so pedestrians,
undead and a giant-scaled player read the same field and get different answers out of it.

An actor drives a `NavAgent`: it takes a goal from a `NavGoalProvider`, asks `NavService`
for a corridor, walks it with `NavMotor` and climbs a six-rung failure ladder (`NavLadder`)
when the world will not cooperate. That rung is both a signal (`ladder_changed`) and
state — a failed goal leaves `has_failed()`, `last_failure()`, `failure_count()` and
`failure_age_sec()` standing on the agent after the next goal is adopted, so a consumer that
only samples the agent still sees the failure it would otherwise have missed.

A corridor is repathed only when an edit actually touched it. `NavAgent.dirty_probe` defaults
to the Callable `NavService.corridor_probe()` hands out, which answers whether any navigation
sector along the current corridor changed since the version the path was built at. Measured
over 120 peds and 20 s of blasting (`tools/test_nav_lazy_repath.tscn`): 252 repaths with the
probe against 1439 without — 82% fewer, with 3758 version bumps proved irrelevant.

Water is a depth, not a wall. A submerged span carries the depth of water over it and each
profile wades up to its own `max_wade`, which is why the overlay's span field looks as though
it runs out over a lake: the field carries the lake bed, and the overlay draws every span it
finds. A pedestrian has no footing past its wade depth — over the seed-42 lake the deepest
bed span sits under 5 cells of water, `nearest_surface` for a pedestrian there reports
nothing, and a pedestrian route to it comes back `NO_GOAL`. Only the giant, wading six, walks
in.

**F8** toggles the debug overlay, **Shift+F8** cycles what colours the spans. It draws the
span field, portals, corridors and the live blocked columns around whatever node it follows,
plus a counter line on the debug HUD layer. Blocks come back out of `NavService`
(`is_column_blocked`, `blocked_columns`, expiring against the clock the native world was last
advanced to), so the overlay also draws blocks it did not write.

Peds, undead and cars all run on this: there is no second movement system left. Cars keep one
thing the span field cannot carry, which is lane semantics — `StreetTopology` holds a
`SidewalkMap` of kerb pads and crossings and a `CarLaneGraph` of directed lanes, both derived
from the district planner and neither of them walked. The lane graph says which side of a
carriageway runs which way and which turns a junction allows, and `NavService` routes between
two lane points over whatever spans are actually there, so blowing a hole in a road reroutes
the traffic and takes the lane points over the crater out of service until it is filled in.

Checks: `tools/test_nav_bake`, `test_nav_links`, `test_nav_service`, `test_nav_agent`,
`test_nav_dirty_rebuild`, `test_nav_debug_overlay`, `test_nav_lazy_repath`, `test_ped_nav`,
`test_undead_nav`, `test_car_nav` and `test_hill_district` (run as scenes). Looks:
`tools/shot_nav_overlay.tscn` for the synthetic span field,
`tools/shot_nav_overlay_city.tscn` for the overlay over the streamed city and the water case.

## Running test scenes

Always run scene tests through **`tools/run_test.ps1`**, never by calling Godot directly.
It runs each scene headless behind a hard timeout, kills anything that overruns, prints
the scene's own `RESULT:` line with the wall-clock time, and dumps the log and stderr on
failure.

```
powershell -File tools\run_test.ps1 test_ped_nav
powershell -File tools\run_test.ps1 test_nav_agent test_nav_service test_ped_nav
powershell -File tools\run_test.ps1 test_nav_bake -TimeoutSec 300 -KeepLog
powershell -File tools\run_test.ps1 shot_ped_crowd -Rendered -GodotArgs "--spawn-district=0,0"
```

`-Rendered` drops `--headless` for the screenshot tools, which need a real renderer because
the district bake waits on `is_area_editable`; `-GodotArgs` passes CityRoot's own flags such as
`--spawn-district=x,z` through. The hang guard is the same.

Exit code 0 = every scene printed `RESULT: OK`, 1 = a scene failed, 2 = a scene was killed
on timeout. The default timeout is 180 s; the whole nav suite runs in well under a minute,
so anything near that is hung rather than slow. Logs go to `tools\<scene>.log` / `.err`
(gitignored) and are deleted on success unless `-KeepLog` is passed.

The timeout is a backstop, not the guard. **A test that waits for a condition must bound
the wait itself and fail loudly when the bound is exceeded** — a hang is the most silent
failure there is, and a hung headless Godot also holds `city_voxel.dll` open, which blocks
every later `tools/build_city_voxel.ps1` until it is killed.

## Design rules

- Humans and cars are **meshes**, not voxels.
- Pedestrians walk sidewalks / plazas / parks / crosswalks only (not asphalt).
- Prefer CC0 (MakeHuman/MPFB, Quaternius). See `LICENSE_ASSETS.md`.

## Known issues

### Directional shadows vanish far from the world origin

The sun casts no shadows at all in districts far from `(0, 0)`. Everything is still
lit by it — only the shadows are missing, so cars, props and pedestrians look pasted
onto the ground.

Observed with `tools/shot_city_traffic.tscn`: shadows render at world coords
`(231, 72)` (district `0,0`) but are completely absent at `(562, -483)` (district
`1,-2`) and `(-990, 1099)` (district `-3,3`). A stock `BoxMesh` with
`SHADOW_CASTING_SETTING_ON` dropped into the far districts casts nothing either, so
this is not specific to any one mesh or material.

Ruled out: time of day (pinned to 10:00), a paused `SceneTree`, and the voxel-tuned
`shadow_bias` / `shadow_normal_bias` / `directional_shadow_pancake_size` in
`CityRoot._configure_sun_shadows` (relaxing them changes nothing). Distance from the
origin is the variable that tracks.

Reproduce:

```
tools/godot/Godot_v4.6-voxel_win64.exe --path . res://tools/shot_city_traffic.tscn -- --spawn-district=0,0
tools/godot/Godot_v4.6-voxel_win64.exe --path . res://tools/shot_city_traffic.tscn -- --spawn-district=1,-2
```
