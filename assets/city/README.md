# City voxels

Procedural district on **Zylann Voxel Tools** (`godot_voxel` module build):

- Engine: `tools/godot/Godot_v4.6-voxel_win64.exe` (Godot 4.6 + Voxel Tools 1.6) via `start_city.bat`
- `VoxelTerrain` + `VoxelMesherBlocky` + `VoxelBlockyLibrary` — 0.5 m cubes, collision
- `textures/` — ambientCG CC0 albedos + project-authored maps (see `textures/CREDITS.txt`)
- Layout: `DistrictPlanner` (avenues, plazas, parks, zones) → `PlazaComposer` / `ParkComposer` → `BuildingGrammar`
- Humans: MPFB bodies + Quaternius Idle/Walk (CC0), humanoid retarget — see `assets/humans/animations/`
- `CityRoot` + `scenes/city_poc.tscn` — third-person walk, LMB dig, R new seed

Refresh textures:

```
python tools/fetch_city_textures.py
python tools/generate_city_textures.py
```

Crowd demo: `start_crowd.bat`.
