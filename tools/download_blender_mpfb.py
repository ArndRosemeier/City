"""Download Blender portable + MPFB nightly plugin zip."""
from __future__ import annotations

import re
import sys
import urllib.request
from pathlib import Path

VENDOR = Path(__file__).resolve().parent / "vendor"
VENDOR.mkdir(parents=True, exist_ok=True)
UA = {"User-Agent": "CityHumanPOC/1.0"}


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=600) as resp:
        return resp.read()


def download(url: str, dest: Path) -> None:
    if dest.exists() and dest.stat().st_size > 1_000_000:
        print(f"skip {dest.name} ({dest.stat().st_size} bytes)")
        return
    print(f"GET {url}")
    data = get(url)
    dest.write_bytes(data)
    print(f"  -> {dest} ({len(data)} bytes)")


def main() -> int:
    download(
        "https://files2.makehumancommunity.org/plugins/mpfb2-20260721.zip",
        VENDOR / "mpfb2-plugin.zip",
    )
    # Mirror alternate if needed
    if not (VENDOR / "mpfb2-plugin.zip").exists() or (VENDOR / "mpfb2-plugin.zip").stat().st_size < 1_000_000:
        download(
            "https://files.makehumancommunity.org/plugins/mpfb2-latest.zip",
            VENDOR / "mpfb2-plugin.zip",
        )

    # Blender 4.2 LTS windows x64 zip (official CDN)
    mirror = "https://download.blender.org/release/Blender4.2/"
    html = get(mirror).decode("utf-8", "replace")
    zips = re.findall(r'href="(blender-4\.2[\d.]*-windows-x64\.zip)"', html)
    if not zips:
        zips = ["blender-4.2.9-windows-x64.zip"]
    blender_name = sorted(zips)[-1]
    download(mirror + blender_name, VENDOR / blender_name)
    (VENDOR / "blender_zip_name.txt").write_text(blender_name, encoding="utf-8")
    print(f"Blender zip: {blender_name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
