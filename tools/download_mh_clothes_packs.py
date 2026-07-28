#!/usr/bin/env python3
"""Download CC0 MakeHuman clothing asset packs into tools/vendor and install into MPFB user data."""

from __future__ import annotations

import json
import shutil
import sys
import zipfile
import urllib.request
from pathlib import Path

VENDOR = Path(__file__).resolve().parent / "vendor"
USER_CLOTHES = VENDOR / "mpfb_user_data" / "data" / "clothes"
# tools/vendor is gitignored, so the per-asset author/licence/source record is copied out of the
# pack zips into the repo. The outfit GLBs are derived works of these assets; the record has to
# ship with them, not with the download cache.
LICENSE_DIR = Path(__file__).resolve().parent.parent / "assets" / "humans" / "outfits" / "licenses"
UA = {"User-Agent": "CityClothesFetch/1.0"}

# Only the *_cc0.zip variant of each pack is fetched, but the URL is NOT the licence boundary:
# shoes01_cc0.zip and masks01_cc0.zip each ship one item the author relicensed to CC-BY years
# after the pack was built. So the licence is read per asset from the pack's own metadata and
# anything that is not CC0 is dropped before it can reach an outfit.
#
# Wave B: civilian variety. Wave C: hostile kit — masks and helmets are Clothes-type mhclo
# assets, and so are the weapons in equipment01, which means a sword goes through the same
# add_mhclo_asset call and comes out skinned to the hand.
CC0_PACKS: dict[str, str] = {
    "shirts01": "https://files2.makehumancommunity.org/asset_packs/shirts01/shirts01_cc0.zip",
    "pants01": "https://files2.makehumancommunity.org/asset_packs/pants01/pants01_cc0.zip",
    "shoes01": "https://files2.makehumancommunity.org/asset_packs/shoes01/shoes01_cc0.zip",
    "masks01": "https://files2.makehumancommunity.org/asset_packs/masks01/masks01_cc0.zip",
    "hats02": "https://files2.makehumancommunity.org/asset_packs/hats02/hats02_cc0.zip",
    "equipment01": (
        "https://files2.makehumancommunity.org/asset_packs/equipment01/equipment01_cc0.zip"
    ),
    "suits02": "https://files2.makehumancommunity.org/asset_packs/suits02/suits02_cc0.zip",
    "gloves01": "https://files2.makehumancommunity.org/asset_packs/gloves01/gloves01_cc0.zip",
}

# Several MakeHuman community items are labelled CC0 while being fan art of trademarked
# characters. The label does not make them safe to ship, so they are removed on extraction.
# Match is case-insensitive against the asset folder name.
TRADEMARK_BLOCKLIST: tuple[str, ...] = (
    "spider",
    "gwen",
    "sailor",
    "moon",
    "wolverine",
    "rei",
    "ayanami",
    "batman",
    "superman",
    "mario",
    "pikachu",
)


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=600) as resp:
        return resp.read()


def is_blocked(asset_folder: str) -> bool:
    lowered = asset_folder.lower()
    return any(word in lowered for word in TRADEMARK_BLOCKLIST)


def read_pack_metadata(zip_path: Path, pack: str) -> dict[str, dict]:
    with zipfile.ZipFile(zip_path) as zf:
        member = f"packs/{pack}.json"
        if member not in zf.namelist():
            raise FileNotFoundError(f"{zip_path.name} has no {member} licence record")
        return json.loads(zf.read(member))


def is_cc0(entry: dict) -> bool:
    return str(entry.get("license", "")).lower().replace("-", "") == "cc0"


def save_license_record(pack: str, record: dict[str, dict]) -> None:
    """Write the per-asset author/licence/source metadata of what was actually installed."""
    LICENSE_DIR.mkdir(parents=True, exist_ok=True)
    out = LICENSE_DIR / f"{pack}.json"
    out.write_text(json.dumps(record, indent=2, sort_keys=True), encoding="utf-8")
    print(f"  licence record -> {out} ({len(record)} assets)")


def install_zip(zip_path: Path, metadata: dict[str, dict]) -> tuple[int, list[str], list[str]]:
    """Extract CC0 clothes/* folders from a pack zip into the MPFB user clothes dir.

    An asset folder is installed only when the pack metadata names it as CC0 and it is not
    trademarked fan art. Anything the metadata does not describe is refused as well: an asset
    with no recorded licence cannot be attributed, so it cannot ship.
    """
    USER_CLOTHES.mkdir(parents=True, exist_ok=True)
    count = 0
    trademarked: set[str] = set()
    non_cc0: set[str] = set()
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
            asset = rel.parts[0]
            if is_blocked(asset):
                trademarked.add(asset)
                continue
            if asset not in metadata or not is_cc0(metadata[asset]):
                non_cc0.add(asset)
                continue
            dest = USER_CLOTHES / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(zf.read(info))
            count += 1
    return count, sorted(trademarked), sorted(non_cc0)


def purge(asset: str) -> None:
    """Remove an asset folder a previous run may have installed before it was refused."""
    folder = USER_CLOTHES / asset
    if folder.exists():
        shutil.rmtree(folder)
        print(f"  purged previously installed {asset}")


def main() -> int:
    VENDOR.mkdir(parents=True, exist_ok=True)
    errors: list[str] = []
    for name, url in CC0_PACKS.items():
        dest = VENDOR / f"{name}_cc0.zip"
        try:
            if not dest.exists() or dest.stat().st_size < 100_000:
                print(f"Downloading {url}")
                dest.write_bytes(get(url))
                print(f"  wrote {dest} ({dest.stat().st_size} bytes)")
            else:
                print(f"skip existing {dest}")
            metadata = read_pack_metadata(dest, name)
            n, trademarked, non_cc0 = install_zip(dest, metadata)
            print(f"  installed {n} files from {name} into {USER_CLOTHES}")
            for folder in trademarked:
                print(f"  REFUSED trademarked fan art: {folder}")
                purge(folder)
            for folder in non_cc0:
                license_name = metadata.get(folder, {}).get("license", "<not in pack metadata>")
                print(f"  REFUSED {folder}: licence is {license_name}, not CC0")
                purge(folder)
            installed = {
                k: v
                for k, v in metadata.items()
                if is_cc0(v) and not is_blocked(k) and k not in non_cc0
            }
            save_license_record(name, installed)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{name}: {exc}")
            print(f"FAILED {name}: {exc}", file=sys.stderr)
    if errors:
        print(f"{len(errors)} pack(s) failed", file=sys.stderr)
        return 1
    print("CC0 clothing packs ready.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
