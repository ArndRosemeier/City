#!/usr/bin/env python3
"""Enforce the import settings city textures need at runtime.

Godot only flips `mipmaps/generate` and `compress/mode` through the editor's detect_3d
hook, which fires when a texture is dropped on a 3D material *in the editor*. Every
texture here is assigned from GDScript instead, so detect_3d never fires and the maps
import as mip-less lossless 2D sprites: the shaders all ask for
`filter_linear_mipmap_anisotropic` and silently get plain linear, and one 1K map costs
~4 MB of VRAM instead of ~1.3 MB.

Run this after adding a texture, then reimport so the cached products are rebuilt:

    python tools/set_city_texture_imports.py
    tools\\godot\\Godot_v4.6-voxel_win64.exe --headless --path . --import
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEXTURES = ROOT / "assets" / "city" / "textures"
IMPORTED = ROOT / ".godot" / "imported"

# BC7 (compress/mode=2 + high_quality) is 1 byte/texel against 3-4 for lossless, and
# detect_3d is disarmed so a later editor session cannot overwrite the choice.
WANTED: dict[str, str] = {
    "mipmaps/generate": "true",
    "compress/mode": "2",
    "compress/high_quality": "true",
    "detect_3d/compress_to": "0",
}

# Maps whose gradients are too smooth to survive block compression. Kept lossless.
LOSSLESS: frozenset[str] = frozenset(
    {
        "water.jpg",
    }
)


def _dest_products(text: str) -> list[Path]:
    """The .ctex products this .import declares, plus their import hash sidecars."""
    out: list[Path] = []
    for line in text.splitlines():
        # A VRAM-compressed texture is declared per format, as `path.bptc=`.
        if not line.startswith("path") and not line.startswith("dest_files="):
            continue
        for chunk in line.split('"'):
            if not chunk.startswith("res://.godot/imported/"):
                continue
            product = ROOT / chunk[len("res://") :]
            out.append(product)
            out.append(product.with_suffix(product.suffix + ".md5"))
    return out


def patch(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    wanted = dict(WANTED)
    if "_normal." in path.name:
        # Left on Detect, a normal map imported from a JPEG can be classified by its
        # channel content instead of its role, which picks the wrong compressor.
        wanted["compress/normal_map"] = "1"
    if path.name.removesuffix(".import") in LOSSLESS:
        wanted["compress/mode"] = "0"
        wanted["compress/high_quality"] = "false"
    lines = text.splitlines()
    changed: list[str] = []
    for i, line in enumerate(lines):
        key = line.split("=", 1)[0]
        if key not in wanted:
            continue
        target = f"{key}={wanted.pop(key)}"
        if line != target:
            lines[i] = target
            changed.append(target)
    if wanted:
        raise RuntimeError(f"{path.name}: missing import keys {sorted(wanted)}")
    if not changed:
        return False
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    # Godot serves the cached .ctex without checking the .import when it runs outside
    # the editor, so a stale product would keep loading with the old settings.
    for product in _dest_products(text):
        if product.exists():
            product.unlink()
    print(f"{path.name}: {', '.join(changed)}")
    return True


def main() -> int:
    imports = sorted(TEXTURES.glob("*.import"))
    if not imports:
        print(f"No .import files under {TEXTURES}", file=sys.stderr)
        return 1
    touched = sum(1 for p in imports if patch(p))
    print(f"{touched} of {len(imports)} texture imports updated ({IMPORTED} products cleared)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
