#!/usr/bin/env python3
"""Point the outfit GLBs at their extracted sibling PNGs instead of embedding the same pixels.

`gltf/embedded_image_handling=1` makes Godot extract every embedded texture to a sibling PNG with
its own `.import`, so git ends up carrying each texture twice: once in the GLB binary chunk and
once as the extracted file. Deleting the extracted copies is not an option -- their `.import`
sidecars carry the per-texture compression settings and uids, and Godot only regenerates them
(with defaults, and new uids) when the GLB itself is reimported.

So the embedded copy is the one to drop. Each `images[i]` gets a `uri` pointing at the PNG that is
already tracked next to it and loses its `bufferView`; the freed bufferViews are removed and every
accessor is re-indexed. The extracted PNGs and their tuned `.import` files stay untouched, and the
importer resolves them as external textures.

Pixels are compared before anything is rewritten, so a GLB whose embedded image has drifted from
its sibling PNG aborts instead of silently swapping in different textures.

    python tools/externalize_glb_images.py            # rewrite every outfit GLB
    python tools/externalize_glb_images.py --dry-run  # report only
"""

from __future__ import annotations

import argparse
import io
import json
import struct
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUTFIT_DIR = ROOT / "assets" / "humans" / "outfits"

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942

IMPORT_CACHE = ROOT / ".godot" / "imported"
UID_CACHE = ROOT / ".godot" / "uid_cache.bin"


def _log(msg: str) -> None:
    print(f"[externalize] {msg}", flush=True)


def _invalidate_import_cache() -> None:
    """Drop the cached import products of the outfits.

    An outfit's imported `.scn` records how it reached its textures. Once they become external
    references Godot has to reimport to notice, and a cached scene that still resolves keeps it
    from doing so, so the products are cleared here instead of hoping the scan spots the change.
    """
    if not IMPORT_CACHE.is_dir():
        return
    stems = {p.stem for p in OUTFIT_DIR.glob("*.glb")}
    removed = 0
    for artifact in IMPORT_CACHE.iterdir():
        if any(artifact.name.startswith(stem) for stem in stems):
            artifact.unlink()
            removed += 1
    UID_CACHE.unlink(missing_ok=True)
    _log(f"cleared {removed} cached import products — next Godot run reimports the outfits")


def _read_glb(path: Path) -> tuple[dict, bytearray]:
    raw = path.read_bytes()
    magic, version, total = struct.unpack_from("<III", raw, 0)
    if magic != GLB_MAGIC:
        raise ValueError(f"{path.name}: not a GLB")
    if version != 2:
        raise ValueError(f"{path.name}: glTF version {version}, expected 2")
    if total != len(raw):
        raise ValueError(f"{path.name}: header length {total} != file size {len(raw)}")
    gltf: dict | None = None
    bin_chunk = bytearray()
    offset = 12
    while offset < len(raw):
        length, kind = struct.unpack_from("<II", raw, offset)
        body = raw[offset + 8 : offset + 8 + length]
        if kind == CHUNK_JSON:
            gltf = json.loads(body.decode("utf-8"))
        elif kind == CHUNK_BIN:
            bin_chunk = bytearray(body)
        offset += 8 + length
    if gltf is None:
        raise ValueError(f"{path.name}: no JSON chunk")
    return gltf, bin_chunk


def _write_glb(path: Path, gltf: dict, bin_chunk: bytes) -> None:
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * ((4 - len(json_bytes) % 4) % 4)
    bin_bytes = bytes(bin_chunk) + b"\x00" * ((4 - len(bin_chunk) % 4) % 4)
    total = 12 + 8 + len(json_bytes) + (8 + len(bin_bytes) if bin_bytes else 0)
    out = bytearray()
    out += struct.pack("<III", GLB_MAGIC, 2, total)
    out += struct.pack("<II", len(json_bytes), CHUNK_JSON) + json_bytes
    if bin_bytes:
        out += struct.pack("<II", len(bin_bytes), CHUNK_BIN) + bin_bytes
    path.write_bytes(out)


def _same_pixels(embedded: bytes, sibling: Path) -> tuple[bool, str]:
    with Image.open(io.BytesIO(embedded)) as a, Image.open(sibling) as b:
        a.load()
        b.load()
        if a.size != b.size:
            return False, f"{a.size[0]}x{a.size[1]} embedded vs {b.size[0]}x{b.size[1]} on disk"
        mode = "RGBA" if "A" in a.getbands() or "A" in b.getbands() else "RGB"
        if a.convert(mode).tobytes() != b.convert(mode).tobytes():
            return False, "same size but different pixels"
    return True, ""


def externalize(path: Path, dry_run: bool) -> tuple[int, int]:
    before_size = path.stat().st_size
    gltf, bin_chunk = _read_glb(path)
    images = gltf.get("images", [])
    if not images:
        _log(f"{path.name}: no images")
        return before_size, before_size

    embedded_views: set[int] = set()
    for index, image in enumerate(images):
        if "uri" in image:
            _log(f"  {image.get('name', index)}: already external ({image['uri']})")
            continue
        if "bufferView" not in image:
            raise ValueError(f"{path.name}: image {index} has neither uri nor bufferView")
        name = image.get("name")
        if not name:
            raise ValueError(f"{path.name}: image {index} has no name, cannot match a sibling PNG")
        sibling = path.parent / f"{path.stem}_{name}.png"
        if not sibling.is_file():
            raise ValueError(
                f"{path.name}: image '{name}' has no extracted sibling at {sibling.name} -- "
                "reimport the GLB in Godot first so the PNG and its .import exist"
            )
        view = gltf["bufferViews"][image["bufferView"]]
        start = view.get("byteOffset", 0)
        data = bytes(bin_chunk[start : start + view["byteLength"]])
        ok, why = _same_pixels(data, sibling)
        if not ok:
            raise ValueError(f"{path.name}: '{name}' does not match {sibling.name} -- {why}")
        _log(f"  {name}: -{len(data) / 1024:.0f}K embedded -> {sibling.name}")
        embedded_views.add(image["bufferView"])
        image["uri"] = sibling.name
        image["mimeType"] = "image/png"
        del image["bufferView"]

    if not embedded_views:
        _log(f"{path.name}: nothing embedded")
        return before_size, before_size

    views = gltf["bufferViews"]
    keep = [i for i in range(len(views)) if i not in embedded_views]
    remap = {old: new for new, old in enumerate(keep)}
    payloads: list[bytes] = []
    for old in keep:
        view = views[old]
        if view.get("buffer", 0) != 0:
            raise ValueError(f"{path.name}: multiple buffers are not supported")
        start = view.get("byteOffset", 0)
        payloads.append(bytes(bin_chunk[start : start + view["byteLength"]]))

    if dry_run:
        after = before_size - sum(
            views[i]["byteLength"] for i in embedded_views
        )
        return before_size, after

    gltf["bufferViews"] = [views[i] for i in keep]
    out = bytearray()
    for index, view in enumerate(gltf["bufferViews"]):
        pad = (4 - len(out) % 4) % 4
        out += b"\x00" * pad
        view["byteOffset"] = len(out)
        view["byteLength"] = len(payloads[index])
        out += payloads[index]
    gltf["buffers"][0]["byteLength"] = len(out) + ((4 - len(out) % 4) % 4)

    for accessor in gltf.get("accessors", []):
        if "bufferView" in accessor:
            accessor["bufferView"] = remap[accessor["bufferView"]]
        sparse = accessor.get("sparse")
        if sparse is not None:
            sparse["indices"]["bufferView"] = remap[sparse["indices"]["bufferView"]]
            sparse["values"]["bufferView"] = remap[sparse["values"]["bufferView"]]
    for mesh in gltf.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            if "extensions" in primitive:
                raise ValueError(f"{path.name}: primitive extensions may hold bufferView indices")

    _write_glb(path, gltf, out)
    after_size = path.stat().st_size
    _log(f"{path.name}: {before_size / 1e6:.1f} MB -> {after_size / 1e6:.1f} MB")
    return before_size, after_size


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("glb", nargs="*", help="GLB files (default: every outfit GLB)")
    args = parser.parse_args()

    targets = [Path(p) for p in args.glb] if args.glb else sorted(OUTFIT_DIR.glob("*.glb"))
    if not targets:
        print(f"no GLBs found in {OUTFIT_DIR}", file=sys.stderr)
        return 1
    total_before = 0
    total_after = 0
    for path in targets:
        _log(f"{path.name}")
        before, after = externalize(path, args.dry_run)
        total_before += before
        total_after += after
    if not args.dry_run and total_after != total_before:
        _invalidate_import_cache()
    _log(
        f"TOTAL {total_before / 1e6:.1f} MB -> {total_after / 1e6:.1f} MB "
        f"({100.0 * (1.0 - total_after / total_before):.0f}% smaller)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
