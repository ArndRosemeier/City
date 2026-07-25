# City — Procedural voxel city (Godot 4)

Voxel district POC with skinned MPFB pedestrians, Quaternius cars, sidewalks/curbs,
crosswalks, and street lights. Showcase scene still available via `start.bat`.

## Requirements

- Godot **4.6 + Voxel Tools** (`tools/godot/Godot_v4.6-voxel_win64.exe`) for the city POC
- **`addons/city_voxel/bin/city_voxel.dll`** (required — bake volume + cascade debris; rebuild with `tools/build_city_voxel.ps1`)
- Optional stock Godot 4.3+ for the human showcase (`start.bat` / `scenes/main.tscn`)

## Run (city)

Double-click **`start_city.bat`** — endless streamed districts.

### Install (Windows) — for players

Double-click **`install_city.bat`** on a machine that already has this project
(or an unzipped City package). It copies the game into
`%LOCALAPPDATA%\Programs\City` and adds Desktop / Start Menu shortcuts.

If `tools\godot\Godot_v4.6-voxel_win64.exe` is missing, it **downloads**
Godot 4.6 + Voxel Tools 1.6 from the official
[Zylann/godot_voxel](https://github.com/Zylann/godot_voxel/releases/tag/v1.6) release.
`addons/city_voxel/bin/city_voxel.dll` is shipped in the repo.

```
install_city.bat
install_city.bat /D "D:\Games\City"
```

### Make a shareable package — for you (developer)

From the repo root, double-click **`make_installer.bat`**.

That stages a clean copy, runs a full Godot import *on the staged folder*, and
validates every `scripts/` file + `city_poc`:

- `dist\CityPortable\` — full playable folder (engine + fresh `.godot` import)

Zip that folder yourself if you want an archive. You should not need to edit the
installer when adding scripts/assets — new content is picked up by the staged
import + validation. Recipients run **`City.bat`** or **`install_city.bat`**.
Keep the packaged `.godot` folder.

(`tools\pack_city_portable.bat` is the older folder-only helper; prefer `make_installer.bat`.)

Controls: **WASD** walk · **Mouse** look · **LMB** dig · **R** autorun · **Esc** quit · **N** day/night · **M** meteor · **T** Tetris Game Boy · **P** pedestrian · **F7** profiler · **Settings** (top-right) for quality.

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
means "pick a new one". The tile at the world origin is always the downtown core
regardless of seed, so the player spawns downtown.

## District themes

Every district tile picks a theme deterministically from the world seed and its grid
coordinate (`scripts/city/district_theme.gd`): **Core High-Rise**, **Old Town**,
**Waterfront Industrial**, **Garden Residential** or **Civic Quarter**. The theme sets
the wall / roof / paving palette, the building archetype weights and a height scale, so
the tile at the world origin is always the downtown core and the quarters around it get
lower and older.

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
