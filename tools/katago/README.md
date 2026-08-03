# KataGo (local fetch + Gaming district)

## Fetch engines + nets

```text
powershell -File tools\ensure_katago.ps1
```

Downloads Eigen + OpenCL Windows engines, the strong self-play net, and the
**Human-SL** net (`b18c384nbt-humanv0.bin.gz`) into this folder (gitignored).

## Strength = Human-SL rank (20k–9d)

In-process play uses the Human-SL model as the **main** net with
`humanSLProfile = rank_<token>` (`20k`…`1k`, `1d`…`9d`). Rank is selected on the
table (− / label / +) or via invite presets (15k / 5k / 1d).

This is KataGo’s official human-rank ladder (v1.15+), not visit-count difficulty.
Visit budget stays modest (~40) for pass/resign and light search.

**Caveat:** at high dan, raw Human-SL imitates *style/policy* of that rank; without
the dual-model + deep search calibration it is not a true KGS 9d. The ladder is
still ordered and far more meaningful than visit tiers on a superhuman net.

Config: `res://addons/city_katago/human_rank.cfg`  
Pool: `GoEnginePool.acquire("5k")` → `NativeKataGo.set_rank`.

## In-process product path

```text
powershell -File tools\ensure_katago_embed_deps.ps1
powershell -File tools\build_city_katago.ps1
```

Produces:

- `addons/city_katago/bin/city_katago.dll` (Godot binding)
- `addons/city_katago/bin/city_katago_native.dll` (Eigen embed)

Headless smoke:

```text
powershell -File tools\run_test.ps1 -Scene test_katago_gdextension -TimeoutSec 600
```

## Portable packaging notes

- Ship both DLLs under `addons/city_katago/bin/`.
- Ship or first-run-download `b18c384nbt-humanv0.bin.gz` (~100 MB) — path the pool
  loads: `res://tools/katago/…` or a future `user://` cache.
- The strong `kata1-b18c384nbt.bin.gz` net is optional for play (Human-SL is required).
- Do **not** ship CUDA/cuDNN redistributables; Eigen is the reliable default, OpenCL later.
- Gaming district loads the human net when the player invites a ped (refcount unload when
  the district streams out / session ends). Ambient ped-vs-ped tables do not hold a net.
