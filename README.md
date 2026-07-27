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

Controls: **WASD** walk · **Mouse** look · **LMB** dig · **R** autorun · **Esc** quit · **J** jump to district type · **N** day/night · **F1–F6** build · **Shift+F1–F6** assign build · **M** meteor · **T** Tetris Game Boy · **P** pedestrian · **F7** profiler (hitches ≥80 ms print to console as `CityProfiler HITCH`) · **Settings** (top-right) for quality. Settings → Graphics → Diagnostics → **Log stutters to file** mirrors those hitch reports into `%APPDATA%\Godot\app_userdata\EccentriCity\city_hitches.log` (the same panel has an *Open log folder* button), so a stutter can be reported without a console open.

Build: aim with the mouse, press **F1–F6** to stamp the bound recipe at the cursor (cottage / pool / hot tub / statues by default). **Shift+F1–F6** opens the full recipe list to rebind a slot. Fronts face you. Builds are session-local and disappear when that district streams out.

Tetris (after **T**): **1** left · **2** rotate · **3** right · **4** fast drop (tap once). Cabinet is `GAMEBOY` voxels — destroy any piece of it and the game breaks. **P** near a cabinet spawns a pedestrian who walks up, plays, and AI-controls the game.

## Layout

```
assets/humans/     MPFB bases, outfits, Quaternius Idle/Walk
assets/city/       Voxel textures
assets/vehicles/   Quaternius CC0 car GLBs + catalog.json
scenes/            city_poc.tscn, main.tscn
scripts/city/      District generation, crowd, street lights
scripts/vehicles/  VehicleDirector / catalog / visuals
scripts/humans/    Outfits, proportions
LICENSE_ASSETS.md  Content license provenance
```

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
