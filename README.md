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

Controls: **WASD** walk · **Mouse** look · **LMB** dig · **R** autorun · **Esc** quit · **N** day/night · **F7** profiler overlay · **Settings** (top-right) for quality.

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

## Design rules

- Humans and cars are **meshes**, not voxels.
- Pedestrians walk sidewalks / plazas / parks / crosswalks only (not asphalt).
- Prefer CC0 (MakeHuman/MPFB, Quaternius). See `LICENSE_ASSETS.md`.
