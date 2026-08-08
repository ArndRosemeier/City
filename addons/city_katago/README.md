# city_katago

In-process KataGo for Eccentri City (`NativeKataGo`).

Build: `tools/build_city_katago.ps1`  
Deps: `tools/ensure_katago_embed_deps.ps1`  
Net: `tools/ensure_katago.ps1` → `tools/katago/*.bin.gz`

The Gaming district loads the net on invite and unloads when the session/district ends
(search workers are joined first; destroy runs off the main thread).
See `tools/katago/README.md` for portable packaging notes.
