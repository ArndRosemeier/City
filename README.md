# City — Procedural voxel city (Godot 4)

Voxel district POC with skinned MPFB pedestrians, Quaternius cars, sidewalks/curbs,
crosswalks, and street lights. Showcase scene still available via `start.bat`.

## Requirements

- Godot **4.6 + Voxel Tools** (`tools/godot/Godot_v4.6-voxel_win64.exe`) for the city POC
- Optional stock Godot 4.3+ for the human showcase (`start.bat` / `scenes/main.tscn`)

## Run (city)

Double-click **`start_city.bat`** — endless streamed districts.

### Install (Windows)

Double-click **`install_city.bat`** to copy a portable build into
`%LOCALAPPDATA%\Programs\City` and add Desktop / Start Menu shortcuts.

If `tools\godot\Godot_v4.6-voxel_win64.exe` is missing, the installer
**downloads** Godot 4.6 + Voxel Tools 1.6 from the official
[Zylann/godot_voxel](https://github.com/Zylann/godot_voxel/releases/tag/v1.6) release.
If `city_voxel.dll` is missing, it tries a local Rust build (optional; GDScript bake fallback works without it).

```
install_city.bat
install_city.bat /D "D:\Games\City"
install_city.bat /S /D "%LOCALAPPDATA%\Programs\City"
```

To build a shareable folder: **`tools\pack_city_portable.bat`** → `dist\CityPortable\`.

Controls: **WASD** walk · **Mouse** look · **LMB** dig · **R** autorun · **Esc** quit · **N** day/night · **Settings** (top-right) for quality.

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
