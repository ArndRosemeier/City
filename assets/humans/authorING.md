# MakeHuman / MPFB human bases

Runtime bodies:

- `male_base.gltf` (+ `.bin`) — also `.glb`
- `female_base.gltf` (+ `.bin`) — also `.glb`
- `outfits/*.glb` — dressed variants (body + system suit + shoes) for crowd/player

These are **real MakeHuman/MPFB meshes** with the **game_engine** skeleton
(53 bones: `pelvis`, `thigh_*`, `calf_*`, `upperarm_*`, `lowerarm_*`, …).
Anatomy proxy bone: **`pelvis`**.

## Regenerate

```bat
tools\export_mpfb_humans.bat
tools\export_mpfb_outfits.bat
```

Optional extra CC0 clothes packs: `python tools\download_mh_clothes_packs.py`

Requires vendored Blender + MPFB under `tools/vendor/` (see download/extract scripts).

## License

Core MakeHuman/MPFB assets and these exports: **CC0**.
See `LICENSE_ASSETS.md` and `outfits/CREDITS.txt`.
