#!/usr/bin/env python3
"""Generate POC male/female humanoid glTF bases with blend-shape morphs.

These are stand-ins until MakeHuman/MPFB exports replace them.
Topology, morph names, and skeleton are stable so Godot code keeps working.

Morph targets (Godot blend shapes):
  height, weight, torso_length, leg_length, shoulder_width

Anatomy later: Pelvis bone is the attachment point for AnatomyProxy.
"""

from __future__ import annotations

import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "humans"


def _pack_f32(values: list[float]) -> bytes:
    return struct.pack("<" + "f" * len(values), *values)


def _pack_u16(values: list[int]) -> bytes:
    return struct.pack("<" + "H" * len(values), *values)


def _pack_u8(values: list[int]) -> bytes:
    return struct.pack("<" + "B" * len(values), *values)


def _box(
    cx: float,
    cy: float,
    cz: float,
    sx: float,
    sy: float,
    sz: float,
) -> tuple[list[list[float]], list[list[float]], list[list[float]], list[int]]:
    """Axis-aligned box centered at c with full size s. Returns verts, normals, uvs, indices."""
    hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
    # 24 verts (unique normals per face)
    faces = [
        # +Z
        ([cx - hx, cy - hy, cz + hz], [cx + hx, cy - hy, cz + hz], [cx + hx, cy + hy, cz + hz], [cx - hx, cy + hy, cz + hz], [0, 0, 1]),
        # -Z
        ([cx + hx, cy - hy, cz - hz], [cx - hx, cy - hy, cz - hz], [cx - hx, cy + hy, cz - hz], [cx + hx, cy + hy, cz - hz], [0, 0, -1]),
        # +X
        ([cx + hx, cy - hy, cz + hz], [cx + hx, cy - hy, cz - hz], [cx + hx, cy + hy, cz - hz], [cx + hx, cy + hy, cz + hz], [1, 0, 0]),
        # -X
        ([cx - hx, cy - hy, cz - hz], [cx - hx, cy - hy, cz + hz], [cx - hx, cy + hy, cz + hz], [cx - hx, cy + hy, cz - hz], [-1, 0, 0]),
        # +Y
        ([cx - hx, cy + hy, cz + hz], [cx + hx, cy + hy, cz + hz], [cx + hx, cy + hy, cz - hz], [cx - hx, cy + hy, cz - hz], [0, 1, 0]),
        # -Y
        ([cx - hx, cy - hy, cz - hz], [cx + hx, cy - hy, cz - hz], [cx + hx, cy - hy, cz + hz], [cx - hx, cy - hy, cz + hz], [0, -1, 0]),
    ]
    face_uvs = [[0.0, 1.0], [1.0, 1.0], [1.0, 0.0], [0.0, 0.0]]
    verts: list[list[float]] = []
    norms: list[list[float]] = []
    uvs: list[list[float]] = []
    indices: list[int] = []
    for a, b, c, d, n in faces:
        base = len(verts)
        for p, uv in zip((a, b, c, d), face_uvs):
            verts.append(p)
            norms.append(list(n))
            uvs.append(list(uv))
        indices.extend([base, base + 1, base + 2, base, base + 2, base + 3])
    return verts, norms, uvs, indices


def build_humanoid(sex: str) -> dict:
    female = sex == "female"
    # Base proportions (meters)
    shoulder = 0.36 if female else 0.42
    hip = 0.34 if female else 0.32
    torso_h = 0.52 if female else 0.56
    leg_h = 0.82 if female else 0.88
    arm_len = 0.55 if female else 0.58
    head_s = 0.20 if female else 0.21
    skin = [0.86, 0.68, 0.54, 1.0] if female else [0.78, 0.58, 0.44, 1.0]

    pelvis_y = leg_h
    chest_y = pelvis_y + torso_h * 0.55
    neck_y = pelvis_y + torso_h
    head_y = neck_y + head_s * 0.55

    parts: list[tuple[str, float, float, float, float, float, float, int]] = []
    # name, cx, cy, cz, sx, sy, sz, bone_index
    # Bones: 0 Root, 1 Pelvis, 2 Spine, 3 Chest, 4 Neck, 5 Head,
    #        6 LeftUpLeg, 7 LeftLeg, 8 RightUpLeg, 9 RightLeg,
    #        10 LeftArm, 11 RightArm
    parts.append(("pelvis", 0, pelvis_y, 0, hip, 0.14, 0.16, 1))
    parts.append(("torso", 0, chest_y, 0, shoulder * 0.85, torso_h * 0.7, 0.18, 2))
    parts.append(("chest", 0, neck_y - 0.08, 0, shoulder, 0.16, 0.2, 3))
    parts.append(("head", 0, head_y, 0, head_s, head_s * 1.15, head_s * 1.05, 5))
    parts.append(("left_thigh", -hip * 0.28, pelvis_y - leg_h * 0.28, 0, 0.12, leg_h * 0.48, 0.12, 6))
    parts.append(("left_shin", -hip * 0.28, pelvis_y - leg_h * 0.72, 0, 0.1, leg_h * 0.4, 0.1, 7))
    parts.append(("right_thigh", hip * 0.28, pelvis_y - leg_h * 0.28, 0, 0.12, leg_h * 0.48, 0.12, 8))
    parts.append(("right_shin", hip * 0.28, pelvis_y - leg_h * 0.72, 0, 0.1, leg_h * 0.4, 0.1, 9))
    parts.append(("left_arm", -shoulder * 0.55, neck_y - 0.12, 0, 0.09, arm_len, 0.09, 10))
    parts.append(("right_arm", shoulder * 0.55, neck_y - 0.12, 0, 0.09, arm_len, 0.09, 11))
    # Subtle breast / chest difference for sex readability (not anatomy proxy)
    if female:
        parts.append(("breast_l", -0.08, chest_y + 0.06, 0.09, 0.1, 0.1, 0.1, 3))
        parts.append(("breast_r", 0.08, chest_y + 0.06, 0.09, 0.1, 0.1, 0.1, 3))

    all_pos: list[float] = []
    all_norm: list[float] = []
    all_uv: list[float] = []
    all_idx: list[int] = []
    all_joints: list[int] = []
    all_weights: list[float] = []
    vert_regions: list[str] = []

    for name, cx, cy, cz, sx, sy, sz, bone in parts:
        verts, norms, uvs, indices = _box(cx, cy, cz, sx, sy, sz)
        base = len(all_pos) // 3
        for v, n, uv in zip(verts, norms, uvs):
            all_pos.extend(v)
            all_norm.extend(n)
            all_uv.extend(uv)
            # 4 joint influences; only first used
            all_joints.extend([bone, 0, 0, 0])
            all_weights.extend([1.0, 0.0, 0.0, 0.0])
            vert_regions.append(name)
        for i in indices:
            all_idx.append(base + i)

    n_verts = len(all_pos) // 3

    def morph_deltas(kind: str) -> list[float]:
        deltas = [0.0] * (n_verts * 3)
        for vi in range(n_verts):
            x = all_pos[vi * 3]
            y = all_pos[vi * 3 + 1]
            z = all_pos[vi * 3 + 2]
            region = vert_regions[vi]
            dx = dy = dz = 0.0
            if kind == "height":
                dy = (y - 0.9) * 0.18
            elif kind == "weight":
                if region in ("pelvis", "torso", "chest", "breast_l", "breast_r"):
                    dx = x * 0.22
                    dz = z * 0.18
                else:
                    dx = x * 0.08
                    dz = z * 0.08
            elif kind == "torso_length":
                if y >= pelvis_y - 0.05:
                    dy = (y - pelvis_y) * 0.2
            elif kind == "leg_length":
                if y < pelvis_y:
                    dy = (y - pelvis_y) * 0.25
            elif kind == "shoulder_width":
                if region in ("chest", "left_arm", "right_arm", "breast_l", "breast_r"):
                    dx = x * 0.28
            deltas[vi * 3] = dx
            deltas[vi * 3 + 1] = dy
            deltas[vi * 3 + 2] = dz
        return deltas

    morph_names = ["height", "weight", "torso_length", "leg_length", "shoulder_width"]
    morphs = {name: morph_deltas(name) for name in morph_names}

    # Skeleton rests (local transforms relative to parent)
    # glTF: node matrix or TRS. We'll use translation.
    bones = [
        ("Root", -1, [0, 0, 0]),
        ("Pelvis", 0, [0, pelvis_y, 0]),
        ("Spine", 1, [0, torso_h * 0.35, 0]),
        ("Chest", 2, [0, torso_h * 0.35, 0]),
        ("Neck", 3, [0, 0.1, 0]),
        ("Head", 4, [0, head_s * 0.5, 0]),
        ("LeftUpLeg", 1, [-hip * 0.28, -leg_h * 0.05, 0]),
        ("LeftLeg", 6, [0, -leg_h * 0.45, 0]),
        ("RightUpLeg", 1, [hip * 0.28, -leg_h * 0.05, 0]),
        ("RightLeg", 8, [0, -leg_h * 0.45, 0]),
        ("LeftArm", 3, [-shoulder * 0.55, 0, 0]),
        ("RightArm", 3, [shoulder * 0.55, 0, 0]),
    ]

    return {
        "sex": sex,
        "skin": skin,
        "positions": all_pos,
        "normals": all_norm,
        "uvs": all_uv,
        "indices": all_idx,
        "joints": all_joints,
        "weights": all_weights,
        "morphs": morphs,
        "morph_names": morph_names,
        "bones": bones,
        "n_verts": n_verts,
    }


def write_gltf(data: dict, out_path: Path) -> None:
    pos_b = _pack_f32(data["positions"])
    norm_b = _pack_f32(data["normals"])
    uv_b = _pack_f32(data["uvs"])
    idx_b = _pack_u16(data["indices"])
    # joints as UNSIGNED_BYTE vec4
    joints_b = _pack_u8(data["joints"])
    weights_b = _pack_f32(data["weights"])
    morph_blobs = [_pack_f32(data["morphs"][n]) for n in data["morph_names"]]

    blobs = [pos_b, norm_b, uv_b, idx_b, joints_b, weights_b, *morph_blobs]
    # Align each blob to 4 bytes
    aligned: list[bytes] = []
    for b in blobs:
        pad = (4 - (len(b) % 4)) % 4
        aligned.append(b + b"\x00" * pad)

    bin_blob = b"".join(aligned)
    bin_name = out_path.with_suffix(".bin").name

    offsets: list[int] = []
    o = 0
    for b in aligned:
        offsets.append(o)
        o += len(b)

    n_verts = data["n_verts"]
    n_idx = len(data["indices"])
    n_bones = len(data["bones"])

    # Accessor helpers
    def accessor_f32_vec3(bufview: int, count: int, mins: list[float], maxs: list[float]) -> dict:
        return {
            "bufferView": bufview,
            "componentType": 5126,
            "count": count,
            "type": "VEC3",
            "min": mins,
            "max": maxs,
        }

    pos = data["positions"]
    xs = pos[0::3]
    ys = pos[1::3]
    zs = pos[2::3]
    pos_min = [min(xs), min(ys), min(zs)]
    pos_max = [max(xs), max(ys), max(zs)]

    buffer_views = []
    for i, b in enumerate(aligned):
        buffer_views.append(
            {
                "buffer": 0,
                "byteOffset": offsets[i],
                "byteLength": len(blobs[i]),
            }
        )
    # ARRAY_BUFFER for attributes; ELEMENT_ARRAY for indices
    for i in [0, 1, 2, 4, 5]:
        buffer_views[i]["target"] = 34962
    buffer_views[3]["target"] = 34963  # indices
    buffer_views[4]["byteStride"] = 4  # joints UNSIGNED_BYTE vec4
    for mi in range(len(morph_blobs)):
        buffer_views[6 + mi]["target"] = 34962

    accessors = [
        accessor_f32_vec3(0, n_verts, pos_min, pos_max),  # 0 positions
        {
            "bufferView": 1,
            "componentType": 5126,
            "count": n_verts,
            "type": "VEC3",
        },  # 1 normals
        {
            "bufferView": 2,
            "componentType": 5126,
            "count": n_verts,
            "type": "VEC2",
        },  # 2 uvs
        {
            "bufferView": 3,
            "componentType": 5123,
            "count": n_idx,
            "type": "SCALAR",
        },  # 3 indices
        {
            "bufferView": 4,
            "componentType": 5121,
            "count": n_verts,
            "type": "VEC4",
        },  # 4 joints
        {
            "bufferView": 5,
            "componentType": 5126,
            "count": n_verts,
            "type": "VEC4",
        },  # 5 weights
    ]

    morph_accessor_indices = []
    for mi, name in enumerate(data["morph_names"]):
        d = data["morphs"][name]
        dx, dy, dz = d[0::3], d[1::3], d[2::3]
        acc_i = len(accessors)
        accessors.append(
            accessor_f32_vec3(
                6 + mi,
                n_verts,
                [min(dx), min(dy), min(dz)],
                [max(dx), max(dy), max(dz)],
            )
        )
        morph_accessor_indices.append(acc_i)
    # Inverse bind matrices
    # For simplicity use identity * -rest_world — compute simple chain
    inv_binds: list[float] = []
    world_pos = [[0.0, 0.0, 0.0] for _ in range(n_bones)]
    for i, (_name, parent, t) in enumerate(data["bones"]):
        if parent < 0:
            world_pos[i] = list(t)
        else:
            world_pos[i] = [
                world_pos[parent][0] + t[0],
                world_pos[parent][1] + t[1],
                world_pos[parent][2] + t[2],
            ]
    # Inverse bind = translate(-world)
    ibm_bytes_list: list[float] = []
    for i in range(n_bones):
        wx, wy, wz = world_pos[i]
        # column-major 4x4
        mat = [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            -wx, -wy, -wz, 1,
        ]
        ibm_bytes_list.extend(mat)
    ibm_b = _pack_f32(ibm_bytes_list)
    pad = (4 - (len(ibm_b) % 4)) % 4
    ibm_aligned = ibm_b + b"\x00" * pad
    ibm_offset = len(bin_blob)
    bin_blob = bin_blob + ibm_aligned
    ibm_view = len(buffer_views)
    buffer_views.append(
        {"buffer": 0, "byteOffset": ibm_offset, "byteLength": len(ibm_b)}
    )
    ibm_acc = len(accessors)
    accessors.append(
        {
            "bufferView": ibm_view,
            "componentType": 5126,
            "count": n_bones,
            "type": "MAT4",
        }
    )

    # Nodes: bone nodes then mesh node
    nodes = []
    for name, parent, t in data["bones"]:
        nodes.append({"name": name, "translation": t})
    # set children
    children_map: dict[int, list[int]] = {i: [] for i in range(n_bones)}
    for i, (_n, parent, _t) in enumerate(data["bones"]):
        if parent >= 0:
            children_map[parent].append(i)
    for i, ch in children_map.items():
        if ch:
            nodes[i]["children"] = ch

    mesh_node_index = len(nodes)
    nodes.append({"name": "BodyMesh", "mesh": 0, "skin": 0})

    # Root also parents mesh for convenience? Skin uses skeleton roots.
    # Put mesh under scene root alongside skeleton root.
    scene_root = len(nodes)
    nodes.append(
        {
            "name": f"{data['sex']}_base",
            "children": [0, mesh_node_index],  # Root bone + mesh
        }
    )

    targets = [{"POSITION": ai} for ai in morph_accessor_indices]
    weights = [0.5] * len(data["morph_names"])  # rest mid so +/- maps cleanly

    gltf = {
        "asset": {"version": "2.0", "generator": "City POC humanoid generator"},
        "scene": 0,
        "scenes": [{"name": "Scene", "nodes": [scene_root]}],
        "nodes": nodes,
        "meshes": [
            {
                "name": "Body",
                "primitives": [
                    {
                        "attributes": {
                            "POSITION": 0,
                            "NORMAL": 1,
                            "TEXCOORD_0": 2,
                            "JOINTS_0": 4,
                            "WEIGHTS_0": 5,
                        },
                        "indices": 3,
                        "material": 0,
                        "targets": targets,
                    }
                ],
                "weights": weights,
                "extras": {
                    "targetNames": data["morph_names"],
                    "anatomyProxyBone": "Pelvis",
                    "sex": data["sex"],
                },
            }
        ],
        "materials": [
            {
                "name": "Skin",
                "pbrMetallicRoughness": {
                    "baseColorFactor": data["skin"],
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.75,
                },
                "doubleSided": True,
            }
        ],
        "skins": [
            {
                "name": "Armature",
                "inverseBindMatrices": ibm_acc,
                "joints": list(range(n_bones)),
                "skeleton": 0,
            }
        ],
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(bin_blob), "uri": bin_name}],
    }

    # Godot reads morph names from mesh extras targetNames or KHR — also add
    # extras on primitive for compatibility
    gltf["meshes"][0]["primitives"][0]["extras"] = {
        "targetNames": data["morph_names"]
    }

    out_path.parent.mkdir(parents=True, exist_ok=True)
    bin_path = out_path.with_suffix(".bin")
    bin_path.write_bytes(bin_blob)
    out_path.write_text(json.dumps(gltf, indent=2), encoding="utf-8")
    print(f"Wrote {out_path} + {bin_name} ({n_verts} verts, {n_bones} bones)")


def main() -> None:
    for sex in ("male", "female"):
        data = build_humanoid(sex)
        write_gltf(data, OUT_DIR / f"{sex}_base.gltf")


if __name__ == "__main__":
    main()
