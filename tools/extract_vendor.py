"""Extract Blender + MPFB and inspect package layout."""
from __future__ import annotations

import zipfile
from pathlib import Path

VENDOR = Path(__file__).resolve().parent / "vendor"
ROOT = Path(__file__).resolve().parents[1]


def unzip(src: Path, dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    marker = dest / ".extracted"
    if marker.exists():
        print(f"already extracted: {dest}")
        return
    print(f"Extracting {src.name} -> {dest}")
    with zipfile.ZipFile(src, "r") as zf:
        zf.extractall(dest)
    marker.write_text("ok", encoding="utf-8")


def main() -> None:
    blender_name = (VENDOR / "blender_zip_name.txt").read_text(encoding="utf-8").strip()
    unzip(VENDOR / blender_name, VENDOR / "blender")
    unzip(VENDOR / "mpfb2-plugin.zip", VENDOR / "mpfb2_plugin")
    unzip(VENDOR / "makehuman_system_assets_cc0.zip", VENDOR / "makehuman_system_assets")

    # Show top-level MPFB layout
    plugin_root = VENDOR / "mpfb2_plugin"
    print("\nMPFB plugin top entries:")
    for p in sorted(plugin_root.iterdir())[:30]:
        print(" ", p.name, "DIR" if p.is_dir() else p.stat().st_size)

    # Find blender.exe
    exes = list((VENDOR / "blender").rglob("blender.exe"))
    print("\nBlender exes:")
    for e in exes:
        print(" ", e)


if __name__ == "__main__":
    main()
