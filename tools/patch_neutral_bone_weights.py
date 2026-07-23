"""Reassign verts skinned only to Blender's neutral_bone onto spine_03.

Blender's glTF exporter creates neutral_bone for unweighted nipple tips. Godot
humanoid Rest Fixer then leaves those tips at the wrong bind, causing chest spikes.
"""
from __future__ import annotations

import json
import struct
from pathlib import Path

ROOT = Path(r"C:\Projekte\City\assets\humans")
TARGETS = ("male_base", "female_base")


def _accessor_view(doc: dict, accessor_idx: int) -> tuple[dict, dict, int]:
	acc = doc["accessors"][accessor_idx]
	view = doc["bufferViews"][acc["bufferView"]]
	offset = int(view.get("byteOffset", 0)) + int(acc.get("byteOffset", 0))
	return acc, view, offset


def _patch_file(stem: str) -> None:
	gltf_path = ROOT / f"{stem}.gltf"
	bin_path = ROOT / f"{stem}.bin"
	doc = json.loads(gltf_path.read_text(encoding="utf-8"))
	blob = bytearray(bin_path.read_bytes())

	skin = doc["skins"][0]
	joint_nodes: list[int] = skin["joints"]
	node_names = [doc["nodes"][i].get("name", "") for i in joint_nodes]
	try:
		neutral_joint = node_names.index("neutral_bone")
		spine_joint = node_names.index("spine_03")
	except ValueError as exc:
		raise SystemExit(f"{stem}: missing bone in skin joints: {exc}") from exc

	prim = doc["meshes"][0]["primitives"][0]
	attrs = prim["attributes"]
	j_acc, _, j_off = _accessor_view(doc, attrs["JOINTS_0"])
	w_acc, _, w_off = _accessor_view(doc, attrs["WEIGHTS_0"])
	count = int(j_acc["count"])
	if j_acc["componentType"] != 5121:  # UNSIGNED_BYTE
		raise SystemExit(f"{stem}: unexpected JOINTS_0 componentType {j_acc['componentType']}")
	if w_acc["componentType"] != 5126:  # FLOAT
		raise SystemExit(f"{stem}: unexpected WEIGHTS_0 componentType {w_acc['componentType']}")

	patched = 0
	for vi in range(count):
		j_base = j_off + vi * 4
		w_base = w_off + vi * 16
		joints = list(blob[j_base : j_base + 4])
		weights = list(struct.unpack_from("<4f", blob, w_base))
		changed = False
		for slot in range(4):
			if joints[slot] == neutral_joint and weights[slot] > 1e-6:
				joints[slot] = spine_joint
				changed = True
		if not changed:
			continue
		# Collapse duplicate spine slots.
		merged: dict[int, float] = {}
		for slot in range(4):
			if weights[slot] <= 1e-8:
				continue
			merged[joints[slot]] = merged.get(joints[slot], 0.0) + weights[slot]
		items = sorted(merged.items(), key=lambda kv: kv[1], reverse=True)[:4]
		total = sum(w for _, w in items) or 1.0
		new_joints = [0, 0, 0, 0]
		new_weights = [0.0, 0.0, 0.0, 0.0]
		for i, (j, w) in enumerate(items):
			new_joints[i] = j
			new_weights[i] = w / total
		blob[j_base : j_base + 4] = bytes(new_joints)
		struct.pack_into("<4f", blob, w_base, *new_weights)
		patched += 1

	bin_path.write_bytes(blob)
	print(f"{stem}: reweighted {patched} verts neutral_bone[{neutral_joint}] -> spine_03[{spine_joint}]")


def main() -> None:
	for stem in TARGETS:
		_patch_file(stem)


if __name__ == "__main__":
	main()
