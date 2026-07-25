# Eccentri City — Procedural voxel city (Godot 4)

Procedural voxel city of weird ideas (product id **EccentriCity**). Skinned MPFB
pedestrians, Quaternius cars, sidewalks/curbs, crosswalks, street lights, infection,
and oversized player power. Showcase scene still available via `start.bat`.

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
- Optional stock Godot 4.3+ for the human showcase (`start.bat` / `scenes/main.tscn`)

## Run (city)

Double-click **`start_city.bat`** — endless streamed districts.

### Install (Windows) — for players

From an unzipped release (or this repo), double-click **`install_city.bat`**.
It copies the game into `%LOCALAPPDATA%\Programs\EccentriCity` and adds Desktop /
Start Menu shortcuts.

If the engine is missing, **`EccentriCity.bat`** / **`install_city.bat`** download
Godot 4.6 + Voxel Tools 1.6 from
[Zylann/godot_voxel](https://github.com/Zylann/godot_voxel/releases/tag/v1.6).

```
install_city.bat
install_city.bat /D "D:\Games\EccentriCity"
```

### Make / publish a package — for you (developer)

- **`make_installer.bat`** — full local portable under `dist\EccentriCityPortable\`
  (engine + baked `.godot` import + validation). Handy for offline USB copies.
- **`publish_portable_release.bat`** — builds a *slim* zip (no engine / no
  `.godot`; first `EccentriCity.bat` fetches them) and uploads a GitHub Release.
  Requires `gh auth login` once.

(`tools\pack_city_portable.bat` is the older folder-only helper; prefer the scripts above.)

Controls: **WASD** walk · **Mouse** look · **LMB** dig · **R** autorun · **Esc** quit · **N** day/night · **F1–F6** build · **Shift+F1–F6** assign build · **M** meteor · **T** Tetris Game Boy · **P** pedestrian · **F7** profiler · **Settings** (top-right) for quality.

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
replays the spawn). Override with `--spawn-district=x,z`. The tile at the world
origin is still always the downtown core theme, even when you spawn elsewhere.

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

## Design rules

- Humans and cars are **meshes**, not voxels.
- Pedestrians walk sidewalks / plazas / parks / crosswalks only (not asphalt).
- Prefer CC0 (MakeHuman/MPFB, Quaternius). See `LICENSE_ASSETS.md`.
