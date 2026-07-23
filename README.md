# City — Procedural voxel city (Godot 4)

Phase 1 **Human POC**: skinned procedural pedestrians with proportion morphs,
anatomy proxy slot, and stubs for voxel city + cars.

## Requirements

- [Godot 4.3+](https://godotengine.org/) (Forward Plus)
- Optional: [MakeHuman](http://www.makehumancommunity.org/) or [MPFB](https://static.makehumancommunity.org/mpfb.html) to replace mannequin bases
- Optional: Python 3.10+ to regenerate POC glTF bases (`python tools/generate_human_bases.py`)

## Run

Double-click **`start.bat`** — that launches the POC showcase maximized (no editor).

Controls: **Esc** quit · **R** reshuffle crowd · **Space** pause/resume camera orbit.

Or from a terminal: open `C:\Projekte\City` in Godot 4 and run `scenes/main.tscn`.

## Layout

```
assets/humans/     glTF bases + MakeHuman replacement notes
assets/city/       (future voxel assets)
assets/vehicles/   (future car assets)
scenes/            main demo scene
scripts/humans/    Pedestrian, spawner, proportions, AnatomyProxy
scripts/city/      CityStub
scripts/vehicles/  VehicleStub
tools/             generate_human_bases.py
LICENSE_ASSETS.md  Content license provenance
```

## Design rules (from plan)

- Humans are **meshes + skeleton**, not voxels.
- Crotch / anatomy stays an **optional proxy** (`AnatomyProxy` on `Pelvis`) so
  full anatomy can be added later without remaking the crowd pipeline.
- Prefer MakeHuman/MPFB (CC0 exports) over MB-Lab / SMPL / DAZ for shipped bodies.
  See `LICENSE_ASSETS.md`.
