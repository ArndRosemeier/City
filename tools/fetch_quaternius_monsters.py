#!/usr/bin/env python3
"""Vendor the Quaternius Ultimate Monsters pack (CC0) as .glb with one shared atlas.

The pack ships from a Google Drive folder as self-contained .gltf: every mesh, every
animation and a base64 copy of the 9 KB Atlas_Monsters.png inlined into the JSON text.
That is 30.6 MiB across the fifty files, a third of it base64 padding and fifty duplicate
atlases, so each file is rewritten as binary .glb whose image points at one external
atlas next to the folders. The vendored form is 16.4 MiB.

Drive file ids come from the public folder listing
(https://drive.google.com/drive/folders/18m4KpzpEzhC9wl7jzr6dUc0N8Jozr79C); they are
pinned here so a run is reproducible rather than depending on a scrape.

    python tools/fetch_quaternius_monsters.py
"""

from __future__ import annotations

import base64
import json
import struct
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "monsters" / "quaternius_monsters"
ATLAS_NAME = "Atlas_Monsters.png"

DRIVE_FOLDER = "18m4KpzpEzhC9wl7jzr6dUc0N8Jozr79C"
LICENSE_ID = "16GqsDGESyEOfRbc4dS7EqAwkIUSIW4_y"
ATLAS_ID = "1CtLGgAKj-6a6GGNVNQT7GRPM7uyo9Fj8"

# family -> model name -> Drive file id of the .gltf
MODELS: dict[str, dict[str, str]] = {
    "big": {
        "Alien": "1rWF4Jo_G7-odDa5LfkQ0e2d9_p9pxb3W",
        "Birb": "1x_TV2p9dZg6UKhEM-5484Wt_4Mw1zMGL",
        "BlueDemon": "1mcxtHj9Aw1uu1FWYhl1rfPenuq3My-Z4",
        "Bunny": "1wy1OR4I3CHbWqgD_JMrMkQiUABRGKQfO",
        "Cactoro": "19Po2Ae16TbImr6dCu7PRZdpPQhEA13OQ",
        "Demon": "1XhBLnR6tjqIrFy0AUfRlqKf-hYmVwIR4",
        "Dino": "1xBAObQmJQP1kCslielMmS_KMfPZUsdNm",
        "Fish": "1mQqf-c9O4u3bk2ycpt-DFraGfRjcVfZV",
        "Frog": "19QwNJOpMLNtw5jS2D6tOQQ48nPPk9VSI",
        "Monkroose": "1EhDGjdMRdNZA52otQt73a0x3VpiunwOP",
        "MushroomKing": "1sCGed1ce1CrdCdFz5bxVQMqphu5e3a1m",
        "Ninja": "1T45Ab6f3oX6m-r-kRqEOsmv0Yp9ySmDb",
        "Orc": "17675H4Owu5FeHUk_7Goyc9TKI5YK3cEM",
        "Orc_Skull": "13wbbztVj_2eYyF5lavumLvK9JyCfQEhI",
        "Tribal": "1hWEwACHKMfDzYbqG2Cum3KP6semUY_Ap",
        "Yeti": "1_skNq11VXoaGPu9D-hHb4-0OQXEWNTzY",
    },
    "blob": {
        "Alien": "1DY3eAtSljj-Iiww1Q2kWnj7t25L1Wx8F",
        "Birb": "1S3pQ-fJ3FLZjFNU2QvRI_o37dzu4LqS3",
        "Cactoro": "1zkRgEGD59pniSqIWt4ycEU4CR0wPop7u",
        "Cat": "1DaLGZYClS3GTBHVP3F6tF3mVjQ4-rTc-",
        "Chicken": "1IB0MLe3-z1oKSR2AxXBWWx5t9wzreRIe",
        "Dog": "1zLzeCmfxleaolUOPvAEDSWzWXSlKAnQe",
        "Fish": "1Fqsl3XXpkXb1w0Wxn5EikENpy-0O6bAr",
        "GreenBlob": "1Qj3EPCAzN7P3KNrfjV_sFMw98nsBUyob",
        "GreenSpikyBlob": "125zPNBLl1VAgzhfVom9Kj29hSClaZhjF",
        "Mushnub": "1bNqyLU2o3FbQueRyaHFuhxN_XEGosnwo",
        "Mushnub_Evolved": "1x86_FT5A-d7oVcCRuqczS7GB1t2GydyN",
        "Ninja": "1GXgJxRhROHmHAAcoDzIKkQgDmnLqglPf",
        "Orc": "154RnrgtkqQ_KgMhRS-Jiz7WeiSdcq4EQ",
        "Pigeon": "19-BdZiXRrGvgZFDusAxoksTWH1yqb9SP",
        "PinkBlob": "1KcjhxeBkIhsdm_lMKY-OcTmsKDQt3uoK",
        "Wizard": "1lkfBVrpoKi3JwrkJ3M_vwi7tQXG53RjV",
        "Yeti": "1VpqldMiSmrmoDtTqA5PqOZ0FrPIKKjiP",
    },
    "flying": {
        "Alpaking": "1GDlXgTJ8-eQyIsCPlhsQGHQ4yvtl_xtl",
        "Alpaking_Evolved": "11ns6AbnnC6WtC7zzrSPEWJkwQG_h0rQN",
        "Armabee": "1k7LbRse-00nyMQhTdJMvebPp8B-05hcG",
        "Armabee_Evolved": "196ay2r-nuDXcRiwYu84CoE7Qy_gBj8sB",
        "Demon": "1CLzKKcKfwGRyK4SM7w8Z0vxeH04HW4RQ",
        "Dragon": "1-mQSm6_oGt7-EEQfNj1dFWYgPQy4AdPC",
        "Dragon_Evolved": "1Mcfuavq7F4itG9xhqc-20_IL257ZY2_3",
        "Ghost": "1rUs1QRA9v1Y2wRYEXsfteBisTsz4JlLi",
        "Ghost_Skull": "1JIw8lx6H5IIhf_3Z5FprEu_yCoMcoRN7",
        "Glub": "1X-6f4qyrbloGVq3wf-IdxUgmuA0u1JGu",
        "Glub_Evolved": "1WyNv3hlbY4gIxzbm3sFyn8MzBORQHCIr",
        "Goleling": "1bVAbwxtJhLOBpuJNtl3XBbJhl4cDPdcL",
        "Goleling_Evolved": "1DXqke-QxMth9mq5eYiawcmJDACm4-jvL",
        "Hywirl": "1LJG8sJYUwdoF7zrzPbEO-Vt9Xt7MQCu-",
        "Pigeon": "1m5PJFA3ytir_ES3nPq0HC8UmCynHIzZY",
        "Squidle": "1VbcCYeqrlwYF6b64EY2S_e9hV0HXMr3O",
        "Tribal": "10vwCwj_WXcOG0PTC6l3yhaAN63DLyX9p",
    },
}

_UA = "EccentriCityAssetFetch/1.0 (+local voxel city; CC0 assets)"


def drive_get(file_id: str) -> bytes:
    url = f"https://drive.usercontent.google.com/download?id={file_id}&export=download"
    req = urllib.request.Request(url, headers={"User-Agent": _UA, "Accept": "*/*"})
    with urllib.request.urlopen(req, timeout=180) as resp:
        data: bytes = resp.read()
    # Drive answers 200 with an HTML interstitial rather than an error status when a file
    # is not actually shareable, so the payload has to be checked, not the status code.
    if data[:15].lstrip().lower().startswith(b"<!doctype html") or data[:5] == b"<html":
        raise RuntimeError(f"Drive returned an HTML page for {file_id}, not the file")
    return data


def _align4(n: int) -> int:
    return (n + 3) & ~3


def gltf_to_glb(text: bytes, atlas_uri: str) -> tuple[bytes, int]:
    """Rewrite a self-contained .gltf as .glb whose sole image is `atlas_uri`.

    The atlas is not a data URI of its own: it is a bufferView inside the one base64
    buffer, so externalising it means dropping those views and compacting the binary,
    not just editing a string.

    Returns the .glb bytes and the number of image copies that were dropped.
    """
    doc = json.loads(text)

    blobs: list[bytes] = []
    for buf in doc.get("buffers", []):
        uri = buf.get("uri")
        if uri is None:
            raise RuntimeError("buffer without uri — file is already binary")
        if not uri.startswith("data:"):
            raise RuntimeError(f"buffer points at an external file: {uri}")
        blob = base64.b64decode(uri.split(",", 1)[1])
        if len(blob) != int(buf["byteLength"]):
            raise RuntimeError("buffer byteLength disagrees with its data URI")
        blobs.append(blob)

    images: list[dict] = doc.get("images", [])
    dropped: set[int] = set()
    for image in images:
        if "bufferView" not in image:
            raise RuntimeError("image is not a bufferView — atlas layout changed")
        dropped.add(int(image["bufferView"]))
        image.pop("bufferView", None)
        image.pop("mimeType", None)
        image["uri"] = atlas_uri

    views: list[dict] = doc.get("bufferViews", [])
    remap: dict[int, int] = {}
    kept: list[dict] = []
    binary = bytearray()
    for index, view in enumerate(views):
        if index in dropped:
            continue
        blob = blobs[int(view.get("buffer", 0))]
        start = int(view.get("byteOffset", 0))
        length = int(view["byteLength"])
        binary.extend(b"\x00" * (_align4(len(binary)) - len(binary)))
        view["byteOffset"] = len(binary)
        view["buffer"] = 0
        binary.extend(blob[start : start + length])
        remap[index] = len(kept)
        kept.append(view)
    binary.extend(b"\x00" * (_align4(len(binary)) - len(binary)))

    for accessor in doc.get("accessors", []):
        if "bufferView" in accessor:
            accessor["bufferView"] = remap[int(accessor["bufferView"])]
        sparse = accessor.get("sparse")
        if sparse is not None:
            raise RuntimeError("sparse accessor — bufferView remap would be incomplete")
    doc["bufferViews"] = kept
    doc["buffers"] = [{"byteLength": len(binary)}]

    json_chunk = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    json_chunk += b" " * (_align4(len(json_chunk)) - len(json_chunk))

    total = 12 + 8 + len(json_chunk) + 8 + len(binary)
    out = bytearray()
    out.extend(struct.pack("<III", 0x46546C67, 2, total))
    out.extend(struct.pack("<II", len(json_chunk), 0x4E4F534A))
    out.extend(json_chunk)
    out.extend(struct.pack("<II", len(binary), 0x004E4942))
    out.extend(binary)
    return bytes(out), len(dropped)


def write_credits(atlas_bytes: int) -> None:
    text = "\n".join(
        [
            "Quaternius — Ultimate Monsters (October 2022)",
            "https://quaternius.com/packs/ultimatemonsters.html",
            f"Source: Google Drive folder {DRIVE_FOLDER} (author's own download link)",
            "",
            "License: CC0 1.0 Universal. See License.txt, which is the file bundled with",
            "the download by the author, vendored unedited. It is his boilerplate and names",
            "a different pack of his (Ultimate Platformer Pack) while stating CC0; the pack",
            "page states the same terms. Sketchfab and scraper mirrors of this pack",
            "sometimes state CC-BY; the author's page and the bundled License.txt are the",
            "terms this repository relies on.",
            "",
            "Vendored form: the pack ships self-contained .gltf with the atlas base64'd",
            "into every file. tools/fetch_quaternius_monsters.py rewrites each as .glb",
            f"referencing the single shared {ATLAS_NAME} ({atlas_bytes} bytes) in this",
            "directory. Geometry, rigs and animation clips are untouched.",
            "",
            "Rig families:",
            "  big/    16 models, 43-bone humanoid rig, 14 clips, 2.8-3.2 units tall",
            "  blob/   17 models, 4-bone rig (Body/Head/Head2/Head3), 9 clips",
            "  flying/ 17 models, flier rig; see LICENSE_ASSETS.md for spawn policy",
            "",
        ]
    )
    (OUT / "CREDITS.txt").write_text(text, encoding="utf-8")


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)

    atlas_path = OUT / ATLAS_NAME
    print(f"GET {ATLAS_NAME}")
    atlas = drive_get(ATLAS_ID)
    atlas_path.write_bytes(atlas)
    print(f"  -> {atlas_path.relative_to(ROOT)} ({len(atlas)} bytes)")

    print("GET License.txt")
    (OUT / "License.txt").write_bytes(drive_get(LICENSE_ID))

    raw_total = 0
    glb_total = 0
    failures: list[str] = []
    for family, models in MODELS.items():
        family_dir = OUT / family
        family_dir.mkdir(parents=True, exist_ok=True)
        for name, file_id in sorted(models.items()):
            dest = family_dir / f"{name}.glb"
            try:
                raw = drive_get(file_id)
                glb, images = gltf_to_glb(raw, f"../{ATLAS_NAME}")
            except (urllib.error.URLError, RuntimeError, ValueError) as exc:
                failures.append(f"{family}/{name}: {exc}")
                print(f"FAILED {family}/{name}: {exc}", file=sys.stderr)
                continue
            dest.write_bytes(glb)
            raw_total += len(raw)
            glb_total += len(glb)
            print(
                f"  {family}/{name}.glb  {len(raw) / 1024:.0f} KiB gltf"
                f" -> {len(glb) / 1024:.0f} KiB glb  ({images} atlas copy dropped)"
            )

    write_credits(len(atlas))
    print(
        f"\n{len(MODELS['big']) + len(MODELS['blob']) + len(MODELS['flying']) - len(failures)}"
        f" models: {raw_total / 1048576:.1f} MiB of .gltf ->"
        f" {glb_total / 1048576:.1f} MiB of .glb + {len(atlas) / 1024:.0f} KiB atlas"
    )
    if failures:
        print(f"{len(failures)} download(s) failed", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
