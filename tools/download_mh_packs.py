"""List remote MakeHuman file mirrors and download required packs."""
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


def list_dir(url: str) -> list[str]:
    html = get(url).decode("utf-8", "replace")
    return re.findall(r'href="([^"]+)"', html)


def download(url: str, dest: Path) -> None:
    if dest.exists() and dest.stat().st_size > 1_000_000:
        print(f"skip existing {dest} ({dest.stat().st_size} bytes)")
        return
    print(f"Downloading {url}")
    data = get(url)
    dest.write_bytes(data)
    print(f"  wrote {dest} ({len(data)} bytes)")


def main() -> int:
    for base in (
        "https://files2.makehumancommunity.org/releases/",
        "https://files2.makehumancommunity.org/plugins/",
        "https://files.makehumancommunity.org/releases/",
        "https://files.makehumancommunity.org/plugins/",
    ):
        print(f"\n=== {base} ===")
        try:
            hrefs = list_dir(base)
        except Exception as exc:  # noqa: BLE001
            print(f"  fail: {exc}")
            continue
        for h in hrefs:
            if "mpfb" in h.lower() or h.endswith(".zip"):
                print(h)

    # System assets (CC0) — required skins/eyes/teeth/etc for MPFB
    download(
        "https://files2.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip",
        VENDOR / "makehuman_system_assets_cc0.zip",
    )

    # MPFB source contains the basemesh + targets (CC0 assets inside)
    download(
        "https://github.com/makehumancommunity/mpfb2/archive/refs/tags/v2.0.16.zip",
        VENDOR / "mpfb2-v2.0.16-src.zip",
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
