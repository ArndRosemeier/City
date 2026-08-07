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

### Delta upload (new screenshots / clips)

The gallery is driven by `gallery-data.js`, so new media only needs the new files
plus the updated gallery list — old remote files can stay. After a successful
clean deploy, `.deploy/manifest.json` stores SHA-256 hashes for each file.

```powershell
.\deploy-delta.ps1            # rebuild, upload only new/changed files
.\deploy-delta.ps1 -DryRun    # print the plan, no FTP
.\deploy-delta.ps1 -MediaOnly # only gallery-data.js + media/**
.\deploy-delta.ps1 -SkipRebuild
```

Delta never wipes the remote. Use `deploy-clean.ps1` when the remote is unknown
or you need a full refresh.

## GitHub Pages (optional)

`.github/workflows/deploy-pages.yml` can also publish `web/` from `main`.
Download links on the site point at:

`https://github.com/ArndRosemeier/City/releases/latest/download/EccentriCityPortable-windows.zip`
