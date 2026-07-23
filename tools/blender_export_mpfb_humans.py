"""
Blender headless script: create MakeHuman/MPFB male+female bases and export GLB.

Run via:
  blender --background --python tools/blender_export_mpfb_humans.py
"""
from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

import bpy

ROOT = Path(r"C:\Projekte\City")
VENDOR = ROOT / "tools" / "vendor"
OUT_DIR = ROOT / "assets" / "humans"
MPFB_SRC = VENDOR / "mpfb2_plugin" / "mpfb"
ASSETS_DIR = VENDOR / "makehuman_system_assets"
USER_DATA_OVERRIDE = VENDOR / "mpfb_user_data"


def _log(msg: str) -> None:
    print(f"[mpfb-export] {msg}", flush=True)


def _mpfb_import(path: str):
    """Import a submodule from whichever MPFB package name is active."""
    errors: list[str] = []
    for root in ("bl_ext.user_default.mpfb", "mpfb"):
        try:
            return __import__(f"{root}.{path}", fromlist=["*"])
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{root}.{path}: {exc}")
    raise ImportError(" ; ".join(errors))


def _ensure_mpfb_enabled() -> None:
    candidates = [
        Path(os.path.expandvars(r"%APPDATA%\Blender Foundation\Blender\4.2\extensions\.user\user_default\mpfb")),
        Path(os.path.expandvars(r"%APPDATA%\Blender Foundation\Blender\4.2\extensions\user_default\mpfb")),
        Path(bpy.utils.user_resource("EXTENSIONS")) / "user_default" / "mpfb",
    ]
    try:
        candidates.insert(0, Path(bpy.utils.extension_path_user("bl_ext.user_default")) / "mpfb")
    except Exception:
        pass

    installed = False
    for target in candidates:
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists():
                shutil.rmtree(target)
            shutil.copytree(MPFB_SRC, target)
            _log(f"Installed MPFB to {target}")
            installed = True
            break
        except Exception as exc:  # noqa: BLE001
            _log(f"Install candidate failed {target}: {exc}")
    if not installed:
        raise RuntimeError("Could not install MPFB into any Blender extension path")

    enabled = False
    for mod in ("bl_ext.user_default.mpfb", "mpfb"):
        try:
            bpy.ops.preferences.addon_enable(module=mod)
            _log(f"Enabled addon module: {mod}")
            enabled = True
            break
        except Exception as exc:  # noqa: BLE001
            _log(f"Could not enable {mod}: {exc}")
    if not enabled:
        raise RuntimeError("Failed to enable MPFB addon/extension")
    bpy.ops.wm.save_userpref()


def _install_system_assets() -> None:
    USER_DATA_OVERRIDE.mkdir(parents=True, exist_ok=True)
    data_dir = USER_DATA_OVERRIDE / "data"
    data_dir.mkdir(parents=True, exist_ok=True)

    try:
        addon = bpy.context.preferences.addons.get("mpfb") or bpy.context.preferences.addons.get(
            "bl_ext.user_default.mpfb"
        )
        if addon and hasattr(addon.preferences, "mpfb_user_data"):
            addon.preferences.mpfb_user_data = str(USER_DATA_OVERRIDE)
            _log(f"Set mpfb_user_data={USER_DATA_OVERRIDE}")
            bpy.ops.wm.save_userpref()
    except Exception as exc:  # noqa: BLE001
        _log(f"Preference set skipped: {exc}")

    for name in (
        "clothes",
        "eyebrows",
        "eyelashes",
        "eyes",
        "hair",
        "packs",
        "proxymeshes",
        "skins",
        "teeth",
        "tongue",
    ):
        src = ASSETS_DIR / name
        dst = data_dir / name
        if not src.exists():
            continue
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
        _log(f"Installed asset folder {name}")

    try:
        AssetService = _mpfb_import("services.assetservice").AssetService
        AssetService.update_all_asset_lists()
        _log("Asset lists updated")
    except Exception as exc:  # noqa: BLE001
        _log(f"Asset list update skipped: {exc}")


def _clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in list(bpy.data.meshes):
        bpy.data.meshes.remove(block)
    for block in list(bpy.data.armatures):
        bpy.data.armatures.remove(block)
    for block in list(bpy.data.materials):
        bpy.data.materials.remove(block)


def _macro(gender: float) -> dict:
    TargetService = _mpfb_import("services.targetservice").TargetService
    d = TargetService.get_default_macro_info_dict()
    d["gender"] = gender
    d["age"] = 0.5
    d["muscle"] = 0.55 if gender > 0.5 else 0.45
    d["weight"] = 0.5
    d["height"] = 0.55 if gender > 0.5 else 0.5
    d["proportions"] = 0.5
    d["cupsize"] = 0.55 if gender < 0.5 else 0.15
    d["firmness"] = 0.5
    d["race"] = {"asian": 0.2, "caucasian": 0.6, "african": 0.2}
    return d


def _add_proportion_shape_keys(basemesh) -> None:
    HumanObjectProperties = _mpfb_import("entities.objectproperties").HumanObjectProperties
    TargetService = _mpfb_import("services.targetservice").TargetService

    if basemesh.data.shape_keys is None:
        basemesh.shape_key_add(name="Basis")

    bpy.context.view_layer.objects.active = basemesh
    basemesh.select_set(True)

    gender = HumanObjectProperties.get_value("gender", entity_reference=basemesh)
    height0 = HumanObjectProperties.get_value("height", entity_reference=basemesh)
    weight0 = HumanObjectProperties.get_value("weight", entity_reference=basemesh)
    muscle0 = HumanObjectProperties.get_value("muscle", entity_reference=basemesh)
    prop0 = HumanObjectProperties.get_value("proportions", entity_reference=basemesh)

    def set_macros(**kwargs):
        for k, v in kwargs.items():
            HumanObjectProperties.set_value(k, v, entity_reference=basemesh)
        TargetService.reapply_macro_details(basemesh)
        bpy.context.view_layer.update()

    def add_delta_key(name: str, **macros):
        set_macros(**macros)
        depsgraph = bpy.context.evaluated_depsgraph_get()
        eval_obj = basemesh.evaluated_get(depsgraph)
        coords = [v.co.copy() for v in eval_obj.data.vertices]
        set_macros(height=height0, weight=weight0, muscle=muscle0, proportions=prop0, gender=gender)
        key = basemesh.shape_key_add(name=name, from_mix=False)
        for i, vert in enumerate(key.data):
            vert.co = coords[i]
        key.value = 0.0
        _log(f"Shape key ready: {name}")

    add_delta_key("height", height=0.95)
    add_delta_key("weight", weight=0.9)
    add_delta_key("torso_length", proportions=0.85)
    add_delta_key("leg_length", height=0.85, proportions=0.35)
    add_delta_key("shoulder_width", muscle=0.9, proportions=0.7)


def _strip_shape_keys_keeping_mix(basemesh) -> None:
    """Bake current shape-key mix into the mesh and remove keys (needed to apply mask)."""
    if basemesh.data.shape_keys is None:
        return
    bpy.ops.object.select_all(action="DESELECT")
    basemesh.select_set(True)
    bpy.context.view_layer.objects.active = basemesh
    # Disable armature so evaluation is shape-only
    for mod in basemesh.modifiers:
        if mod.type == "ARMATURE":
            mod.show_viewport = False
            mod.show_render = False
    depsgraph = bpy.context.evaluated_depsgraph_get()
    eval_obj = basemesh.evaluated_get(depsgraph)
    new_mesh = bpy.data.meshes.new_from_object(eval_obj)
    old_mesh = basemesh.data
    basemesh.data = new_mesh
    bpy.data.meshes.remove(old_mesh)
    _log("Baked shape keys into mesh")


def _apply_mask_modifiers_only(basemesh) -> None:
    """Hide/remove helpers via mask. Never apply the Armature modifier."""
    bpy.ops.object.select_all(action="DESELECT")
    basemesh.select_set(True)
    bpy.context.view_layer.objects.active = basemesh
    for mod in list(basemesh.modifiers):
        if mod.type == "ARMATURE":
            mod.show_viewport = True
            mod.show_render = True
            continue
        try:
            bpy.ops.object.modifier_apply(modifier=mod.name)
            _log(f"Applied modifier {mod.name}")
        except Exception as exc:  # noqa: BLE001
            _log(f"Could not apply {mod.name}: {exc}")


def _delete_non_body_vertices(basemesh) -> None:
    """Fallback: delete verts not in the 'body' vertex group (removes helper cubes)."""
    body = basemesh.vertex_groups.get("body")
    if body is None:
        _log("No 'body' vertex group; cannot strip helpers by group")
        return
    bpy.ops.object.select_all(action="DESELECT")
    basemesh.select_set(True)
    bpy.context.view_layer.objects.active = basemesh
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    for v in basemesh.data.vertices:
        v.select = False
        try:
            w = body.weight(v.index)
        except RuntimeError:
            w = 0.0
        if w < 0.1:
            v.select = True
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.delete(type="VERT")
    bpy.ops.object.mode_set(mode="OBJECT")
    _log(f"Stripped non-body verts; remaining={len(basemesh.data.vertices)}")


def _limit_weights_to_four(basemesh) -> None:
    """Godot/glTF only use 4 influences per vertex. Extra weights cause rest-OK / pose-garbage."""
    bpy.ops.object.select_all(action="DESELECT")
    basemesh.select_set(True)
    bpy.context.view_layer.objects.active = basemesh
    # Do not probe vg.weight() for missing verts — Blender prints Error for each miss.
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    _log("Limited vertex groups to 4 influences per vertex")


def _assign_unweighted_verts_to_spine(basemesh) -> None:
    """Prevent Blender glTF from inventing neutral_bone for nipple tips (chest spikes in Godot)."""
    spine = basemesh.vertex_groups.get("spine_03")
    if spine is None:
        _log("No spine_03 vertex group; skip unweighted-vert fix")
        return
    deform_groups = [
        vg for vg in basemesh.vertex_groups if vg.name != "body" and not vg.name.startswith("joint-")
    ]
    fixed = 0
    for v in basemesh.data.vertices:
        total = 0.0
        for vg in deform_groups:
            try:
                total += vg.weight(v.index)
            except RuntimeError:
                pass
        if total > 1e-4:
            continue
        spine.add([v.index], 1.0, "REPLACE")
        fixed += 1
    _log(f"Assigned {fixed} unweighted verts to spine_03")


def _assign_skin_material(basemesh, sex: str) -> None:
    mat = bpy.data.materials.new(name=f"{sex}_skin")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    bsdf = nodes.get("Principled BSDF")
    skin = (0.86, 0.68, 0.54, 1.0) if sex == "female" else (0.78, 0.58, 0.44, 1.0)
    if bsdf:
        bsdf.inputs["Base Color"].default_value = skin
        bsdf.inputs["Roughness"].default_value = 0.65

    tex_candidates = []
    if sex == "female":
        tex_candidates = [
            ASSETS_DIR / "skins" / "young_caucasian_female" / "young_lightskinned_female_diffuse.png",
        ]
    else:
        tex_candidates = [
            ASSETS_DIR / "skins" / "young_caucasian_male" / "young_lightskinned_male_diffuse.png",
        ]
    if not any(p.exists() for p in tex_candidates):
        skins_root = ASSETS_DIR / "skins"
        if skins_root.exists():
            pattern = "*female*diffuse*.png" if sex == "female" else "*male*diffuse*.png"
            for p in skins_root.rglob(pattern):
                if "darkskinned" in p.name:
                    continue
                tex_candidates.insert(0, p)
                break

    tex_path = next((p for p in tex_candidates if p.exists()), None)
    if tex_path and bsdf:
        tex = nodes.new("ShaderNodeTexImage")
        img = bpy.data.images.load(str(tex_path))
        tex.image = img
        links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        _log(f"Skin texture: {tex_path}")
    else:
        _log("Skin texture not found; using solid skin color")

    basemesh.data.materials.clear()
    basemesh.data.materials.append(mat)


def _create_and_export(sex: str) -> Path:
    HumanService = _mpfb_import("services.humanservice").HumanService

    _clear_scene()
    gender = 0.05 if sex == "female" else 0.95
    # Keep helper geometry until AFTER rigging — game_engine bone placement needs joints.
    basemesh = HumanService.create_human(
        mask_helpers=True,
        detailed_helpers=True,  # joint-* helpers required for game_engine bone fit
        extra_vertex_groups=True,
        feet_on_ground=True,
        scale=0.1,
        macro_detail_dict=_macro(gender),
    )
    basemesh.name = f"{sex}_body"
    _log(f"Created basemesh {basemesh.name} verts={len(basemesh.data.vertices)}")

    armature = HumanService.add_builtin_rig(basemesh, "game_engine", import_weights=True)
    if armature is None:
        raise RuntimeError("Failed to add game_engine rig")
    armature.name = f"{sex}_armature"
    _log(f"Added rig {armature.name} bones={len(armature.data.bones)} verts={len(basemesh.data.vertices)}")
    _log_rig_alignment(basemesh, armature)

    # Bake macros / strip helpers only after bones are placed and weighted.
    _strip_shape_keys_keeping_mix(basemesh)
    _apply_mask_modifiers_only(basemesh)
    if len(basemesh.data.vertices) > 14000:
        _log(f"Vert count still high ({len(basemesh.data.vertices)}); deleting non-body verts")
        _delete_non_body_vertices(basemesh)

    _assign_unweighted_verts_to_spine(basemesh)
    _limit_weights_to_four(basemesh)
    _assign_skin_material(basemesh, sex)
    _log_rig_alignment(basemesh, armature)

    bpy.ops.object.select_all(action="DESELECT")
    basemesh.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_gltf = OUT_DIR / f"{sex}_base.gltf"
    out_glb = OUT_DIR / f"{sex}_base.glb"
    for old in (out_gltf, OUT_DIR / f"{sex}_base.bin", out_glb):
        if old.exists():
            old.unlink()

    bpy.ops.export_scene.gltf(
        filepath=str(out_gltf),
        export_format="GLTF_SEPARATE",
        use_selection=True,
        export_apply=False,
        export_animations=False,
        export_skins=True,
        export_morph=True,
        export_yup=True,
    )
    _log(f"Exported {out_gltf} ({out_gltf.stat().st_size} bytes)")

    bpy.ops.export_scene.gltf(
        filepath=str(out_glb),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_animations=False,
        export_skins=True,
        export_morph=True,
        export_yup=True,
    )
    _log(f"Exported {out_glb} ({out_glb.stat().st_size} bytes)")
    return out_gltf


def _log_rig_alignment(basemesh, armature) -> None:
    """Bone pivots must sit inside the mesh (hip near pelvis height, not near feet)."""
    mesh_zs = [basemesh.matrix_world @ v.co for v in basemesh.data.vertices]
    ys = [p.z for p in mesh_zs]  # Blender Z-up
    mesh_min, mesh_max = min(ys), max(ys)
    _log(f"Mesh world Z range [{mesh_min:.3f}, {mesh_max:.3f}] height={mesh_max - mesh_min:.3f}")

    bpy.context.view_layer.update()
    for bone_name in ("pelvis", "thigh_l", "calf_l", "foot_l", "head"):
        bone = armature.pose.bones.get(bone_name)
        if bone is None:
            _log(f"Bone missing: {bone_name}")
            continue
        head = armature.matrix_world @ bone.head
        _log(f"Bone {bone_name} head world=({head.x:.3f},{head.y:.3f},{head.z:.3f})")
        if bone_name == "pelvis":
            # Hip should be near mid-upper body, not near feet.
            rel = (head.z - mesh_min) / max(mesh_max - mesh_min, 1e-6)
            _log(f"Pelvis height ratio along mesh={rel:.3f} (expect ~0.5)")
            if rel < 0.35:
                _log("WARNING: pelvis too low — helpers were likely stripped before rigging")


def main() -> None:
    _log("Starting MPFB human export")
    if not MPFB_SRC.exists():
        raise FileNotFoundError(MPFB_SRC)
    _ensure_mpfb_enabled()
    _install_system_assets()

    LocationService = _mpfb_import("services.locationservice").LocationService
    _log(f"MPFB user data: {LocationService.get_user_data()}")

    male = _create_and_export("male")
    female = _create_and_export("female")
    _log(f"DONE male={male} female={female}")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback

        traceback.print_exc()
        sys.exit(1)
