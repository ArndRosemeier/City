"""
Split Kenney Car Kit body window faces onto a dedicated 'glass' material.

Kenney uses one colormap atlas. Windows are UV'd onto known blue-grey swatches.
We classify each body face by nearest-neighbour sampling the atlas at the face UV
centroid, then assign matching faces to a real glass material and re-export GLB.

Usage:
  blender -b --python tools/blender_split_kenney_glass.py -- <src_glb_dir> <colormap.png> <out_dir> [names...]
"""
from __future__ import annotations

import math
import os
import sys
from collections import Counter

import bpy
from mathutils import Color


# Exact body UV colors observed on Kenney sedan (bottom-left V): blue-grey window swatches.
# Dark chassis greys like (56,56,61) are NOT included.
WINDOW_RGB = {
    (113, 115, 136),
    (114, 116, 137),
    (115, 117, 138),
    (115, 118, 139),
    (112, 114, 135),
    (109, 110, 131),
    (108, 109, 130),
    (107, 109, 130),
    (107, 108, 129),
    (106, 107, 128),
    (105, 106, 127),
    (104, 105, 126),
    (102, 103, 124),
    (134, 139, 161),
    (136, 143, 171),
    (157, 164, 196),
    (160, 168, 201),
    (177, 185, 222),
    (125, 128, 150),
    (106, 107, 128),
}

# Max Chebyshev distance in 8-bit RGB to still count as a window swatch.
WINDOW_TOL = 8


def _argv_after_dd() -> list[str]:
    if "--" not in sys.argv:
        raise SystemExit("Expected args after --")
    return sys.argv[sys.argv.index("--") + 1 :]


def _load_colormap(path: str) -> list[list[tuple[int, int, int]]]:
    # Prefer bpy image for headless; fall back to pure python if needed.
    img = bpy.data.images.load(path)
    w, h = img.size
    pixels = list(img.pixels)  # RGBA float 0-1, bottom-left origin in Blender
    grid: list[list[tuple[int, int, int]]] = []
    for y in range(h):
        row: list[tuple[int, int, int]] = []
        for x in range(w):
            # Blender stores bottom-left; glTF/Kenney UVs are top-left origin typically.
            i = (y * w + x) * 4
            r = int(round(pixels[i] * 255.0))
            g = int(round(pixels[i + 1] * 255.0))
            b = int(round(pixels[i + 2] * 255.0))
            row.append((r, g, b))
        grid.append(row)
    return grid


def _sample(grid: list[list[tuple[int, int, int]]], u: float, v: float, top_left_v: bool) -> tuple[int, int, int]:
    h = len(grid)
    w = len(grid[0])
    uu = u % 1.0
    vv = v % 1.0
    if top_left_v:
        vv = 1.0 - vv
    x = min(w - 1, max(0, int(uu * w)))
    y = min(h - 1, max(0, int(vv * h)))
    return grid[y][x]


def _is_window(rgb: tuple[int, int, int]) -> bool:
    r, g, b = rgb
    # Windows are blue-grey: clearly blue-biased, not dark chassis, not saturated paint.
    if b < r + 14 or b < g + 10:
        return False
    luma = 0.299 * r + 0.587 * g + 0.114 * b
    if luma < 95 or luma > 200:
        return False
    sat = max(r, g, b) - min(r, g, b)
    if sat < 12 or sat > 55:
        return False
    for wr, wg, wb in WINDOW_RGB:
        if max(abs(r - wr), abs(g - wg), abs(b - wb)) <= WINDOW_TOL:
            return True
    # Accept any blue-grey that passes the bias/sat/luma gates (atlas variants).
    return True


def _face_uv_centroid(mesh: bpy.types.Mesh, poly: bpy.types.MeshPolygon, uv_layer) -> tuple[float, float]:
    us = []
    vs = []
    for li in poly.loop_indices:
        uv = uv_layer.data[li].uv
        us.append(uv.x)
        vs.append(uv.y)
    return (sum(us) / len(us), sum(vs) / len(vs))


def _ensure_glass_material() -> bpy.types.Material:
    name = "glass"
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (0.35, 0.50, 0.62, 1.0)
    if "Alpha" in bsdf.inputs:
        bsdf.inputs["Alpha"].default_value = 0.35
    if "Transmission Weight" in bsdf.inputs:
        bsdf.inputs["Transmission Weight"].default_value = 0.85
    elif "Transmission" in bsdf.inputs:
        bsdf.inputs["Transmission"].default_value = 0.85
    if "Roughness" in bsdf.inputs:
        bsdf.inputs["Roughness"].default_value = 0.08
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    mat.blend_method = "BLEND"
    if hasattr(mat, "shadow_method"):
        mat.shadow_method = "NONE"
    return mat


def _ensure_body_material(colormap_path: str) -> bpy.types.Material:
    name = "body"
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex = nt.nodes.new("ShaderNodeTexImage")
    img = bpy.data.images.load(colormap_path, check_existing=True)
    tex.image = img
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    mat.blend_method = "OPAQUE"
    return mat


def _clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def _process_file(src_path: str, colormap_path: str, out_path: str, grid) -> dict:
    _clear_scene()
    bpy.ops.import_scene.gltf(filepath=src_path)
    glass_mat = _ensure_glass_material()
    body_mat = _ensure_body_material(colormap_path)

    stats = {"file": os.path.basename(src_path), "body_faces": 0, "glass_faces": 0, "colors": Counter()}

    for obj in list(bpy.context.scene.objects):
        if obj.type != "MESH":
            continue
        # Only split the main body mesh (windows live there). Keep wheels/spoilers as-is.
        lname = obj.name.lower()
        if "wheel" in lname or "tire" in lname:
            continue
        if "body" not in lname:
            # Secondary props (spoiler, etc.) — leave original materials.
            continue
        mesh = obj.data
        if not mesh.polygons or not mesh.uv_layers:
            continue
        uv_layer = mesh.uv_layers.active
        if uv_layer is None:
            continue

        # Build new material slots: 0=body, 1=glass
        mesh.materials.clear()
        mesh.materials.append(body_mat)
        mesh.materials.append(glass_mat)

        # Kenney glTF UVs use bottom-left V (verified on sedan body dumps).
        labels = []
        colors = Counter()
        glass_count = 0
        for poly in mesh.polygons:
            u, v = _face_uv_centroid(mesh, poly, uv_layer)
            rgb = _sample(grid, u, v, top_left_v=False)
            colors[rgb] += 1
            is_g = _is_window(rgb)
            labels.append(1 if is_g else 0)
            if is_g:
                glass_count += 1
        ratio = glass_count / max(1, len(labels))
        stats["colors"] = colors
        stats["v_origin"] = "bottom_left"
        stats["glass_ratio"] = ratio

        for poly, label in zip(mesh.polygons, labels):
            poly.material_index = label

        body_count = len(labels) - glass_count
        stats["body_faces"] += body_count
        stats["glass_faces"] += glass_count

        if glass_count == 0:
            top = colors.most_common(15)
            raise RuntimeError(
                f"{src_path}: no glass faces on '{obj.name}'. top_colors={top}"
            )
        # Low-poly Kenney bodies are mostly large window panes; ~0.5 glass is normal.
        if ratio > 0.70:
            raise RuntimeError(
                f"{src_path}: glass ratio {ratio:.3f} too high on '{obj.name}' (likely misclassification). "
                f"top_colors={colors.most_common(12)}"
            )
        if ratio < 0.08:
            raise RuntimeError(
                f"{src_path}: glass ratio {ratio:.3f} too low on '{obj.name}'. "
                f"top_colors={colors.most_common(12)}"
            )

    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        export_apply=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )
    return stats


def main() -> None:
    args = _argv_after_dd()
    if len(args) < 3:
        raise SystemExit("Usage: -- <src_dir> <colormap.png> <out_dir> [optional glb names]")
    src_dir, colormap_path, out_dir = args[0], args[1], args[2]
    names = args[3:]
    if not names:
        names = [
            "sedan.glb",
            "sedan-sports.glb",
            "hatchback-sports.glb",
            "suv.glb",
            "suv-luxury.glb",
            "taxi.glb",
            "police.glb",
            "van.glb",
            "delivery.glb",
            "truck.glb",
        ]

    grid = _load_colormap(colormap_path)
    print(f"COLORMAP {colormap_path} size={len(grid[0])}x{len(grid)}")

    for name in names:
        src = os.path.join(src_dir, name)
        out = os.path.join(out_dir, name)
        if not os.path.isfile(src):
            raise FileNotFoundError(src)
        stats = _process_file(src, colormap_path, out, grid)
        top = stats["colors"].most_common(12)
        print(
            f"OK {name} glass={stats['glass_faces']} body={stats['body_faces']} "
            f"ratio={stats['glass_ratio']:.3f} v={stats['v_origin']} top_colors={top}"
        )


if __name__ == "__main__":
    main()
