# Eccentri City voxels

Procedural district on **Zylann Voxel Tools** (`godot_voxel` module build):

- Engine: `tools/godot/Godot_v4.6-voxel_win64.exe` (Godot 4.6 + Voxel Tools 1.6) via `EccentriCity.bat`
- `VoxelTerrain` + `VoxelMesherBlocky` + `VoxelBlockyLibrary` — 0.5 m cubes, collision
- `textures/` — ambientCG CC0 albedos + project-authored facade/roof maps with normals (see `textures/CREDITS.txt`)
- Layout: `DistrictPlanner` (avenues, plazas, parks, zones) → `PlazaComposer` / `ParkComposer` → `BuildingGrammar`
- Scale: ~14 m streets / single lots; CORE towers merge 3×3–4×4 cells (~42–56 m parcels, ~40–54 m plates); ~3.0 m floors, 100 m height ceiling; district ~392×280 m
- Humans: MPFB bodies + Quaternius Idle/Walk (CC0), humanoid retarget — see `assets/humans/animations/`
- `CityRoot` + `scenes/city_poc.tscn` — third-person walk, LMB dig, R autorun

Refresh textures:

```
python tools/fetch_city_textures.py
python tools/generate_city_textures.py
```

Crowd demo: `start_crowd.bat`.
