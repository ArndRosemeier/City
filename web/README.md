# Eccentri City website

Static landing page for GitHub Pages.

## Local preview

```powershell
cd web
python -m http.server 8080
```

Open `http://localhost:8080`.

## Rebuild media from source folders

Tracked sources:

- `screenshots/*.png` — gameplay stills (labels = filename without `.png`)
- `videos/*` — clips for the gallery

Rebuild optimized site media + `media/gallery.json`:

```powershell
python web/tools/rebuild_media.py
```

Outputs:

- `media/screenshots/` — HUD-cropped JPEGs
- `media/clips/` — copied videos (web-safe filenames)
- `media/art/` — optimized hero/section art
- `media/gallery.json` — machine-readable manifest
- `gallery-data.js` — embedded into the page (no fetch required)

Preview with a local server (`python -m http.server` from `web/`), not by double-clicking `index.html`.

## Deploy (futuremagic.de)

From the repo root (FTP password via `$env:FTP_PASSWORD` or prompt):

```powershell
.\deploy-clean.ps1
```

This rebuilds media, stages `web/dist`, uploads to `/webseiten/EccentriCity/`, and
registers the site in the Futuremagic hub (`apps.json`). Live URL:

`https://futuremagic.de/EccentriCity/`

Optional flags: `-SkipClean`, `-SkipRebuild`.

## GitHub Pages (optional)

`.github/workflows/deploy-pages.yml` can also publish `web/` from `main`.
Download links on the site point at:

`https://github.com/ArndRosemeier/City/releases/latest/download/EccentriCityPortable-windows.zip`
