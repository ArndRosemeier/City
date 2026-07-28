#!/usr/bin/env python3
"""Collapse byte-identical outfit textures into one shared file per image.

Every outfit GLB is a full replacement body, so each one carries its own copy of the same skin
diffuse, and outfits that share a shoe or a suit carry that texture twice as well. Once
`externalize_glb_images.py` has turned the embedded copies into `uri` references, the duplicates
are ordinary sibling PNGs and can simply be pointed at one shared file: git stores it once, Godot
imports it once, and a new variant costs its own garments instead of another skin sheet.

The shared file keeps the uid and the tuned `[params]` of the copy it was renamed from, so
compression settings and size limits survive; Godot recomputes the `.godot/imported` paths on the
next import.

Files are grouped by content hash, and a group whose members do not all describe the same image
aborts the run rather than silently merging two different textures.

    python tools/dedupe_outfit_textures.py            # rewrite GLBs, rename and drop duplicates
    python tools/dedupe_outfit_textures.py --dry-run  # report only
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUTFIT_DIR = ROOT / "assets" / "humans" / "outfits"

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942

SHARED_PREFIX = "shared_"

IMPORT_CACHE = ROOT / ".godot" / "imported"
UID_CACHE = ROOT / ".godot" / "uid_cache.bin"


def _log(msg: str) -> None:
    print(f"[dedupe] {msg}", flush=True)


def _read_glb(path: Path) -> tuple[dict, bytes]:
    raw = path.read_bytes()
    magic, version, total = struct.unpack_from("<III", raw, 0)
    if magic != GLB_MAGIC:
        raise ValueError(f"{path.name}: not a GLB")
    if version != 2:
        raise ValueError(f"{path.name}: glTF version {version}, expected 2")
    if total != len(raw):
        raise ValueError(f"{path.name}: header length {total} != file size {len(raw)}")
    gltf: dict | None = None
    bin_chunk = b""
    offset = 12
    while offset < len(raw):
        length, kind = struct.unpack_from("<II", raw, offset)
        body = raw[offset + 8 : offset + 8 + length]
        if kind == CHUNK_JSON:
            gltf = json.loads(body.decode("utf-8"))
        elif kind == CHUNK_BIN:
            bin_chunk = bytes(body)
        offset += 8 + length
    if gltf is None:
        raise ValueError(f"{path.name}: no JSON chunk")
    return gltf, bin_chunk


def _write_glb(path: Path, gltf: dict, bin_chunk: bytes) -> None:
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * ((4 - len(json_bytes) % 4) % 4)
    bin_bytes = bin_chunk + b"\x00" * ((4 - len(bin_chunk) % 4) % 4)
    total = 12 + 8 + len(json_bytes) + (8 + len(bin_bytes) if bin_bytes else 0)
    out = bytearray()
    out += struct.pack("<III", GLB_MAGIC, 2, total)
    out += struct.pack("<II", len(json_bytes), CHUNK_JSON) + json_bytes
    if bin_bytes:
        out += struct.pack("<II", len(bin_bytes), CHUNK_BIN) + bin_bytes
    path.write_bytes(out)


def _referenced_images() -> dict[str, list[tuple[Path, int]]]:
    """Map sibling PNG filename -> [(glb, image index)] for every external image reference."""
    refs: dict[str, list[tuple[Path, int]]] = {}
    for glb in sorted(OUTFIT_DIR.glob("*.glb")):
        gltf, _ = _read_glb(glb)
        for index, image in enumerate(gltf.get("images", [])):
            uri = image.get("uri")
            if uri is None:
                raise RuntimeError(
                    f"{glb.name}: image {index} is still embedded — run "
                    "tools/externalize_glb_images.py first"
                )
            refs.setdefault(uri, []).append((glb, index))
    return refs


def _image_name(filename: str, glb_stems: set[str]) -> str:
    """The image's own name, with the owning outfit's stem stripped off the front."""
    stem = Path(filename).stem
    if stem.startswith(SHARED_PREFIX):
        return stem[len(SHARED_PREFIX) :]
    for glb_stem in sorted(glb_stems, key=len, reverse=True):
        if stem.startswith(glb_stem + "_"):
            return stem[len(glb_stem) + 1 :]
    raise RuntimeError(f"{filename}: does not start with any outfit stem, cannot name it")


def _rewrite_import(source: Path, target: Path) -> None:
    """Move `<source>.import` to `<target>.import`, keeping its uid and [params].

    The `[remap] path.*`, `metadata`, `generator_parameters` and `[deps] dest_files` entries all
    encode a hash of the old source path, so they are dropped and left for Godot to recompute.
    """
    src_import = source.with_name(source.name + ".import")
    if not src_import.is_file():
        raise FileNotFoundError(f"no import settings at {src_import.name}")
    text = src_import.read_text(encoding="utf-8")
    uid_match = re.search(r'^uid="([^"]+)"$', text, re.MULTILINE)
    if uid_match is None:
        raise RuntimeError(f"{src_import.name} has no uid")
    if "[params]" not in text:
        raise RuntimeError(f"{src_import.name} has no [params] section")
    params = text[text.index("[params]") :]
    rel = target.relative_to(ROOT).as_posix()
    out = (
        "[remap]\n\n"
        'importer="texture"\n'
        'type="CompressedTexture2D"\n'
        f'uid="{uid_match.group(1)}"\n'
        "\n[deps]\n\n"
        f'source_file="res://{rel}"\n\n'
        f"{params}"
    )
    target.with_name(target.name + ".import").write_text(out, encoding="utf-8")
    src_import.unlink()


def _invalidate_import_cache() -> None:
    """Drop the cached import products of the outfits.

    An outfit's imported `.scn` records the uid of every texture it referenced. After a rename
    those uids are gone, and Godot then aborts the reimport it needs in order to notice the new
    references -- it logs "Unrecognized UID" and keeps serving the stale scene, so the outfit
    loads with missing textures instead of reimporting. Clearing the cached products here means
    the next Godot run rebuilds them from the files as they are now.
    """
    if not IMPORT_CACHE.is_dir():
        return
    stems = {p.stem for p in OUTFIT_DIR.glob("*.glb")}
    removed = 0
    for artifact in IMPORT_CACHE.iterdir():
        if any(artifact.name.startswith(stem) for stem in stems) or artifact.name.startswith(
            SHARED_PREFIX
        ):
            artifact.unlink()
            removed += 1
    UID_CACHE.unlink(missing_ok=True)
    _log(f"cleared {removed} cached import products — next Godot run reimports the outfits")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    glb_stems = {p.stem for p in OUTFIT_DIR.glob("*.glb")}
    if not glb_stems:
        print(f"no GLBs found in {OUTFIT_DIR}", file=sys.stderr)
        return 1
    refs = _referenced_images()

    groups: dict[str, list[str]] = {}
    for filename in sorted(refs):
        path = OUTFIT_DIR / filename
        if not path.is_file():
            raise FileNotFoundError(f"{filename} is referenced by a GLB but missing on disk")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        groups.setdefault(digest, []).append(filename)

    saved = 0
    renames: dict[str, str] = {}
    for members in sorted(groups.values(), key=lambda m: m[0]):
        if len(members) == 1:
            continue
        names = {_image_name(m, glb_stems) for m in members}
        if len(names) != 1:
            ## MakeHuman ships the same normal map under several garment names. Merging those
            ## would put one asset's texture behind another asset's filename, so they are
            ## reported and left alone rather than quietly renamed.
            _log(f"identical bytes under different image names {sorted(names)} — left alone")
            continue
        image_name = names.pop()
        shared = f"{SHARED_PREFIX}{image_name}.png"
        keep = members[0]
        size = (OUTFIT_DIR / keep).stat().st_size
        saved += size * (len(members) - 1)
        _log(
            f"{image_name}: {len(members)} copies of {size / 1024:.0f}K -> {shared} "
            f"(keeping {keep})"
        )
        for member in members:
            renames[member] = shared
        if args.dry_run:
            continue
        if keep != shared:
            _rewrite_import(OUTFIT_DIR / keep, OUTFIT_DIR / shared)
            (OUTFIT_DIR / keep).rename(OUTFIT_DIR / shared)
        for member in members[1:]:
            (OUTFIT_DIR / member).unlink()
            (OUTFIT_DIR / (member + ".import")).unlink(missing_ok=True)

    if not renames:
        _log("nothing to merge")
        return 0
    if not args.dry_run:
        for glb in sorted(OUTFIT_DIR.glob("*.glb")):
            gltf, bin_chunk = _read_glb(glb)
            changed = False
            for image in gltf.get("images", []):
                shared = renames.get(image["uri"])
                if shared is not None and shared != image["uri"]:
                    image["uri"] = shared
                    changed = True
            if changed:
                _write_glb(glb, gltf, bin_chunk)
                _log(f"{glb.name}: image references updated")
        _invalidate_import_cache()
    _log(f"{'would save' if args.dry_run else 'saved'} {saved / 1e6:.1f} MB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
