#!/usr/bin/env python3
"""Download CC0 MakeHuman clothing asset packs into tools/vendor and install into MPFB user data."""

from __future__ import annotations

import sys
import zipfile
import urllib.request
from pathlib import Path

VENDOR = Path(__file__).resolve().parent / "vendor"
USER_CLOTHES = VENDOR / "mpfb_user_data" / "data" / "clothes"
UA = {"User-Agent": "CityClothesFetch/1.0"}

# Wave B — CC0 mesh packs for more variety (system clothes already vendored).
WAVE_B: dict[str, str] = {
    "shirts01": "https://files2.makehumancommunity.org/asset_packs/shirts01/shirts01_cc0.zip",
    "pants01": "https://files2.makehumancommunity.org/asset_packs/pants01/pants01_cc0.zip",
    "shoes01": "https://files2.makehumancommunity.org/asset_packs/shoes01/shoes01_cc0.zip",
}


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=600) as resp:
        return resp.read()


def install_zip(zip_path: Path) -> int:
    """Extract clothes/* folders from pack zip into MPFB user clothes dir."""
    USER_CLOTHES.mkdir(parents=True, exist_ok=True)
    count = 0
    with zipfile.ZipFile(zip_path) as zf:
        for info in zf.infolist():
            if info.is_dir():
                continue
            parts = Path(info.filename.replace("\\", "/")).parts
            if "clothes" not in parts:
                continue
            idx = parts.index("clothes")
            rel = Path(*parts[idx + 1 :])
            if not rel.parts:
                continue
            dest = USER_CLOTHES / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(zf.read(info))
            count += 1
    return count


def main() -> int:
    VENDOR.mkdir(parents=True, exist_ok=True)
    errors: list[str] = []
    for name, url in WAVE_B.items():
        dest = VENDOR / f"{name}_cc0.zip"
        try:
            if not dest.exists() or dest.stat().st_size < 100_000:
                print(f"Downloading {url}")
                dest.write_bytes(get(url))
                print(f"  wrote {dest} ({dest.stat().st_size} bytes)")
            else:
                print(f"skip existing {dest}")
            n = install_zip(dest)
            print(f"  installed {n} files from {name} into {USER_CLOTHES}")
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{name}: {exc}")
            print(f"FAILED {name}: {exc}", file=sys.stderr)
    if errors:
        print(f"{len(errors)} pack(s) failed", file=sys.stderr)
        return 1
    print("Wave B clothing packs ready.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
