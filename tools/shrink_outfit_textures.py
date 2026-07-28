#!/usr/bin/env python3
"""Downscale the textures embedded in the outfit GLBs, in place.

Each outfit GLB is a full replacement body, so the same 2048 skin diffuse is duplicated into
every file and MakeHuman's cloth normals run to 4096 (9.6 MB in one file). Six hostile variants
on top of that would add 100-150 MB of committed binary, so the sources are shrunk here rather
than only limited on import: Godot's importer caps what reaches VRAM, not what git stores.

Roles come from the glTF material graph, not from image names: an image reached through a
normalTexture is a normal map, and a baseColorTexture on a material named "<sex>_skin" is the
skin diffuse. Nothing else is touched, so accessors, skins and node hierarchy are byte-identical
apart from bufferView offsets.

    python tools/shrink_outfit_textures.py            # rewrite every outfit GLB
    python tools/shrink_outfit_textures.py --dry-run   # report only
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

# Peds are seen from ~1 m at closest and are 1.7 m tall, so 1024 across a whole body is about
# one texel per screen pixel at that distance. Normals only carry cloth wrinkles and read fine
# at a quarter of that.
MAX_EDGE = {
    "skin_diffuse": 1024,
    "garment_diffuse": 1024,
    "normal": 512,
    "other": 512,
}


def _log(msg: str) -> None:
    print(f"[shrink-outfits] {msg}", flush=True)


def _invalidate_import_cache() -> None:
    """Drop the cached import products of the outfits.

    Godot re-extracts a sibling PNG only when it reimports the GLB, and it skips the reimport
    when the cached product still looks current -- which leaves shrunk textures on disk beside
    full-size extracted copies. Clearing the products makes the next run rebuild both.
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


def _image_roles(gltf: dict) -> dict[int, str]:
    """Map image index -> role, resolved through textures and materials."""
    textures = gltf.get("textures", [])
    roles: dict[int, str] = {}

    def assign(texture_ref: dict | None, role: str) -> None:
        if not texture_ref:
            return
        source = textures[texture_ref["index"]].get("source")
        if source is None:
            return
        # A normal map shared with a diffuse slot would be ambiguous; keep the stricter role.
        if source in roles and roles[source] != role:
            raise ValueError(f"image {source} used as both {roles[source]} and {role}")
        roles[source] = role

    for material in gltf.get("materials", []):
        name = str(material.get("name", ""))
        pbr = material.get("pbrMetallicRoughness", {})
        diffuse_role = "skin_diffuse" if name.endswith("_skin") else "garment_diffuse"
        assign(pbr.get("baseColorTexture"), diffuse_role)
        assign(pbr.get("metallicRoughnessTexture"), "other")
        assign(material.get("normalTexture"), "normal")
        assign(material.get("occlusionTexture"), "other")
        assign(material.get("emissiveTexture"), "other")
    for index in range(len(gltf.get("images", []))):
        roles.setdefault(index, "other")
    return roles


def _downscale(data: bytes, max_edge: int) -> tuple[bytes, tuple[int, int], tuple[int, int]]:
    with Image.open(io.BytesIO(data)) as img:
        img.load()
        before = img.size
        longest = max(img.size)
        if longest <= max_edge:
            return data, before, before
        ratio = max_edge / longest
        target = (max(1, round(img.width * ratio)), max(1, round(img.height * ratio)))
        resized = img.resize(target, Image.LANCZOS)
        buf = io.BytesIO()
        resized.save(buf, format="PNG", optimize=True)
        return buf.getvalue(), before, target


def _repack(gltf: dict, bin_chunk: bytearray, new_images: dict[int, bytes]) -> bytearray:
    """Rebuild the BIN chunk with the replaced image payloads, fixing every bufferView offset."""
    views = gltf.get("bufferViews", [])
    payloads: list[bytes] = []
    for view in views:
        if view.get("buffer", 0) != 0:
            raise ValueError("multiple buffers are not supported")
        start = view.get("byteOffset", 0)
        payloads.append(bytes(bin_chunk[start : start + view["byteLength"]]))
    for image_index, data in new_images.items():
        view_index = gltf["images"][image_index]["bufferView"]
        payloads[view_index] = data

    out = bytearray()
    for index, view in enumerate(views):
        pad = (4 - len(out) % 4) % 4
        out += b"\x00" * pad
        view["byteOffset"] = len(out)
        view["byteLength"] = len(payloads[index])
        out += payloads[index]
    gltf["buffers"][0]["byteLength"] = len(out) + ((4 - len(out) % 4) % 4)
    return out


def _shrink_external(path: Path, image: dict, role: str, dry_run: bool) -> int:
    """Downscale a sibling PNG the GLB references by uri. Returns the bytes saved."""
    sibling = path.parent / str(image["uri"])
    if not sibling.is_file():
        raise ValueError(f"{path.name}: image uri {image['uri']} does not exist")
    data = sibling.read_bytes()
    shrunk, before_px, after_px = _downscale(data, MAX_EDGE[role])
    if len(shrunk) >= len(data):
        return 0
    _log(
        f"  {sibling.name} [{role}] {before_px[0]}x{before_px[1]} {len(data) / 1024:.0f}K -> "
        f"{after_px[0]}x{after_px[1]} {len(shrunk) / 1024:.0f}K"
    )
    if not dry_run:
        sibling.write_bytes(shrunk)
    return len(data) - len(shrunk)


def shrink(path: Path, dry_run: bool) -> tuple[int, int]:
    before_size = path.stat().st_size
    gltf, bin_chunk = _read_glb(path)
    images = gltf.get("images", [])
    if not images:
        _log(f"{path.name}: no images")
        return before_size, before_size
    roles = _image_roles(gltf)
    new_images: dict[int, bytes] = {}
    external_saved = 0
    for index, image in enumerate(images):
        ## Textures the GLB references by uri live in the sibling PNGs, so they are shrunk there
        ## rather than treated as an error: this tool stays the one entry point for texture
        ## budget whether or not externalize_glb_images.py has already run.
        if "uri" in image:
            external_saved += _shrink_external(path, image, roles[index], dry_run)
            continue
        if "bufferView" not in image:
            raise ValueError(f"{path.name}: image {index} has neither uri nor bufferView")
        view = gltf["bufferViews"][image["bufferView"]]
        start = view.get("byteOffset", 0)
        data = bytes(bin_chunk[start : start + view["byteLength"]])
        role = roles[index]
        shrunk, before_px, after_px = _downscale(data, MAX_EDGE[role])
        _log(
            f"  {image.get('name', f'image{index}')} [{role}] "
            f"{before_px[0]}x{before_px[1]} {len(data) / 1024:.0f}K -> "
            f"{after_px[0]}x{after_px[1]} {len(shrunk) / 1024:.0f}K"
        )
        if len(shrunk) < len(data):
            new_images[index] = shrunk

    if not new_images:
        if external_saved == 0:
            _log(f"{path.name}: already within budget")
        return before_size, before_size - external_saved
    if dry_run:
        saved = sum(
            gltf["bufferViews"][gltf["images"][i]["bufferView"]]["byteLength"] - len(d)
            for i, d in new_images.items()
        )
        return before_size, before_size - saved - external_saved
    new_bin = _repack(gltf, bin_chunk, new_images)
    _write_glb(path, gltf, new_bin)
    after_size = path.stat().st_size
    _log(f"{path.name}: {before_size / 1e6:.1f} MB -> {after_size / 1e6:.1f} MB")
    return before_size, after_size - external_saved


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
        before, after = shrink(path, args.dry_run)
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
