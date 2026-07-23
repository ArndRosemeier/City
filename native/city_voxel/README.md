# Native City voxel bake helpers (Rust / godot-rust GDExtension).

## What it provides

`NativeOfflineVoxelVolume` — drop-in for the GDScript `OfflineVoxelVolume`:
sparse 16³ fill / set / export to uint16 for `try_set_block_data`.

Loaded explicitly via `CityVoxelNative.ensure_loaded()` (used from `CityRoot` / `CityBrush`).
Falls back to the pure-GDScript volume if the DLL is missing.

The crate enables godot-rust `experimental-threads` so bake workers
(`WorkerThreadPool`) can call into the native volume safely.

## Build (Windows)

1. Install [Rust](https://rustup.rs/) and Visual Studio with C++ / MSVC.
2. From repo root:

```powershell
powershell -ExecutionPolicy Bypass -File tools\build_city_voxel.ps1
```

3. Restart the game so it picks up `addons/city_voxel/bin/city_voxel.dll`.
