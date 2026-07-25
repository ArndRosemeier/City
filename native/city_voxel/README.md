# Native Eccentri City voxel helpers (Rust / godot-rust GDExtension)

## What it provides

- `NativeOfflineVoxelVolume` — sparse 16³ fill / set / export for district bake workers
- `NativeCascadeDebris` — cascading voxel debris (PhysicsServer3D body pool + MultiMesh)

Loaded via `CityVoxelNative.require_loaded()` from `CityRoot` / `CityBrush`.
**Required** — a missing or unloadable DLL is a hard error (no GDScript fallback).

The crate enables godot-rust `experimental-threads` so bake workers
(`WorkerThreadPool`) can call into the native volume safely.

## Build (Windows)

The Windows `addons/city_voxel/bin/city_voxel.dll` is **committed** so installers
and clones work without a Rust toolchain. Rebuild when changing this crate:

1. Install [Rust](https://rustup.rs/) and Visual Studio with C++ / MSVC.
2. From repo root:

```powershell
powershell -ExecutionPolicy Bypass -File tools\build_city_voxel.ps1
```

3. Commit the updated DLL and restart the game.
