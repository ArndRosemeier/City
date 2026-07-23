"""Download MakeHuman/MPFB assets and Blender tooling for City human bases."""
from __future__ import annotations

import re
import sys
import urllib.request
from pathlib import Path

VENDOR = Path(__file__).resolve().parent / "vendor"
VENDOR.mkdir(parents=True, exist_ok=True)

UA = {"User-Agent": "CityHumanPOC/1.0 (asset fetch)"}


def fetch(url: str, dest: Path) -> None:
    print(f"GET {url}")
    print(f" -> {dest}")
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=600) as resp:
        data = resp.read()
    dest.write_bytes(data)
    print(f"    {len(data)} bytes")


def find_hrefs(page_url: str) -> list[str]:
    req = urllib.request.Request(page_url, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as resp:
        html = resp.read().decode("utf-8", "replace")
    return re.findall(r'href="([^"]+)"', html)


def main() -> int:
    # Discover MPFB release / nightly zip URLs
    pages = [
        "https://static.makehumancommunity.org/mpfb/downloads.html",
        "https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_assets.html",
    ]
    for page in pages:
        print(f"\n=== {page} ===")
        try:
            hrefs = find_hrefs(page)
        except Exception as exc:  # noqa: BLE001
            print(f"FAILED: {exc}")
            continue
        for h in hrefs:
            if any(x in h.lower() for x in ("mpfb", "makehuman", "system", "download", "tuxfamily", "zip", "mirror")):
                print(h)

    # Try known candidate URLs
    candidates = [
        # System assets (from docs / common mirrors)
        (
            "makehuman_system_assets.zip",
            [
                "http://www.makehumancommunity.org/sites/default/files/assetpacks/makehuman_system_assets.zip",
                "https://download.tuxfamily.org/makehuman/assetpacks/makehuman_system_assets.zip",
                "http://download.tuxfamily.org/makehuman/assetpacks/makehuman_system_assets.zip",
            ],
        ),
        (
            "mpfb.zip",
            [
                "https://github.com/makehumancommunity/mpfb2/archive/refs/tags/v2.0.16.zip",
                "https://extensions.blender.org/api/v1/download/file/mpfb/",
            ],
        ),
    ]

    print("\n=== probing downloads ===")
    for name, urls in candidates:
        dest = VENDOR / name
        if dest.exists() and dest.stat().st_size > 1000:
            print(f"already have {dest} ({dest.stat().st_size} bytes)")
            continue
        for url in urls:
            try:
                fetch(url, dest)
                break
            except Exception as exc:  # noqa: BLE001
                print(f"  fail {url}: {exc}")
        else:
            print(f"NO DOWNLOAD for {name}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
