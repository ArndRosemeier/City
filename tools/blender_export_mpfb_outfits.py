"""
Blender headless: equip MakeHuman/MPFB clothes on male/female bases and export outfit GLBs.

Run via tools/export_mpfb_outfits.bat
"""
from __future__ import annotations

import json
import os
import shutil
import sys
from pathlib import Path

import bpy

ROOT = Path(r"C:\Projekte\City")
VENDOR = ROOT / "tools" / "vendor"
OUT_DIR = ROOT / "assets" / "humans" / "outfits"
MPFB_SRC = VENDOR / "mpfb2_plugin" / "mpfb"
ASSETS_DIR = VENDOR / "makehuman_system_assets"
USER_DATA_OVERRIDE = VENDOR / "mpfb_user_data"
CLOTHES_DIR = USER_DATA_OVERRIDE / "data" / "clothes"

# "garments" is the mhclo equip order: suit, shoes, then anything else (masks, helmets and
# weapons are Clothes-type mhclo assets as well).
OUTFIT_MATRIX: list[dict] = [
    {"id": "male_casual_01", "sex": "male", "garments": ["male_casualsuit01", "shoes01"], "tags": ["casual"]},
    {"id": "male_casual_02", "sex": "male", "garments": ["male_casualsuit02", "shoes02"], "tags": ["casual"]},
    {"id": "male_casual_03", "sex": "male", "garments": ["male_casualsuit03", "shoes03"], "tags": ["casual"]},
    {"id": "male_work_01", "sex": "male", "garments": ["male_worksuit01", "shoes04"], "tags": ["work"]},
    {"id": "male_elegant_01", "sex": "male", "garments": ["male_elegantsuit01", "shoes05"], "tags": ["elegant"]},
    {"id": "female_casual_01", "sex": "female", "garments": ["female_casualsuit01", "shoes01"], "tags": ["casual"]},
    {"id": "female_casual_02", "sex": "female", "garments": ["female_casualsuit02", "shoes02"], "tags": ["casual"]},
    {"id": "female_sport_01", "sex": "female", "garments": ["female_sportsuit01", "shoes03"], "tags": ["sport"]},
    {"id": "female_elegant_01", "sex": "female", "garments": ["female_elegantsuit01", "shoes05"], "tags": ["elegant"]},
    # Hostile spike: everything a bandit wears is one mhclo list, weapon included.
    {
        "id": "male_bandit_01",
        "sex": "male",
        "garments": [
            "donitz_monk_robe",
            "culturalibre_male_boots",
            "donitz_monk_robe_hood",
            "culturalibre_hero_mask_1",
            "joepal_crude_sword",
        ],
        "tags": ["bandit"],
    },
]

# A freshly exported GLB imports with no retarget bone map, and the shared Quaternius library
# then silently fails to drive it: no error, just a body frozen in its rest pose. So the import
# settings are written here, copied verbatim from an outfit that is known to animate, with only
# the skeleton node path swapped for the sex.
IMPORT_TEMPLATE_ID = "male_work_01"
IMPORT_SKELETON_KEY = 'PATH:{sex}_armature/Skeleton3D'

# Keep in step with PedOutfitCatalog.TAG_FACTIONS — a tag the runtime does not know rejects the
# entry on load.
PROXY_COLORS = {
    "casual": (0.35, 0.42, 0.55),
    "work": (0.45, 0.38, 0.28),
    "elegant": (0.18, 0.18, 0.22),
    "sport": (0.25, 0.45, 0.35),
    "bandit": (0.30, 0.26, 0.24),
}


def _log(msg: str) -> None:
    print(f"[mpfb-outfits] {msg}", flush=True)


def _mpfb_import(path: str):
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
            # Merge: keep any Wave B clothes already installed; refresh system folders.
            if name == "clothes" and dst.exists():
                for child in src.iterdir():
                    target = dst / child.name
                    if target.exists():
                        shutil.rmtree(target)
                    shutil.copytree(child, target)
                _log(f"Merged asset folder {name}")
                continue
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


def _strip_shape_keys_keeping_mix(obj) -> None:
    if obj.data.shape_keys is None:
        return
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    for mod in obj.modifiers:
        if mod.type == "ARMATURE":
            mod.show_viewport = False
            mod.show_render = False
    depsgraph = bpy.context.evaluated_depsgraph_get()
    eval_obj = obj.evaluated_get(depsgraph)
    new_mesh = bpy.data.meshes.new_from_object(eval_obj)
    old_mesh = obj.data
    obj.data = new_mesh
    bpy.data.meshes.remove(old_mesh)
    for mod in obj.modifiers:
        if mod.type == "ARMATURE":
            mod.show_viewport = True
            mod.show_render = True


def _apply_non_armature_modifiers(obj) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    for mod in list(obj.modifiers):
        if mod.type == "ARMATURE":
            mod.show_viewport = True
            mod.show_render = True
            continue
        # Skip subdiv on clothes for game polycount.
        if mod.type == "SUBSURF":
            obj.modifiers.remove(mod)
            continue
        try:
            bpy.ops.object.modifier_apply(modifier=mod.name)
            _log(f"Applied modifier {mod.name} on {obj.name}")
        except Exception as exc:  # noqa: BLE001
            _log(f"Could not apply {mod.name} on {obj.name}: {exc}")


def _delete_non_body_vertices(basemesh) -> None:
    body = basemesh.vertex_groups.get("body")
    if body is None:
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


def _limit_weights_to_four(obj) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)


def _assign_unweighted_verts_to_spine(obj) -> None:
    spine = obj.vertex_groups.get("spine_03")
    if spine is None:
        return
    deform_groups = [
        vg for vg in obj.vertex_groups if vg.name != "body" and not vg.name.startswith("joint-")
    ]
    fixed = 0
    for v in obj.data.vertices:
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
    if fixed:
        _log(f"{obj.name}: assigned {fixed} unweighted verts to spine_03")


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
    skins_root = ASSETS_DIR / "skins"
    if skins_root.exists() and not any(p.exists() for p in tex_candidates):
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

    basemesh.data.materials.clear()
    basemesh.data.materials.append(mat)


def _mhclo_path(folder_name: str) -> Path:
    folder = CLOTHES_DIR / folder_name
    if not folder.exists():
        folder = ASSETS_DIR / "clothes" / folder_name
    matches = list(folder.glob("*.mhclo"))
    if not matches:
        raise FileNotFoundError(f"No .mhclo in {folder}")
    return matches[0]


def _find_clothes_objects(basemesh) -> list:
    ObjectService = _mpfb_import("services.objectservice").ObjectService
    return list(ObjectService.find_all_objects_of_type_amongst_nearest_relatives(basemesh, "Clothes"))


def _garments_of(spec: dict) -> list[str]:
    garments = spec["garments"]
    if not garments:
        raise RuntimeError(f"{spec['id']}: garments list is empty")
    return garments


def _write_import_settings(out_glb: Path, sex: str) -> None:
    """Give the new GLB the same scene-import settings as an outfit that already animates.

    Godot fills in [remap] uid/path itself on first import; [params] and the _subresources
    retarget block are what it will not invent, and what the animation library depends on.
    """
    template_path = OUT_DIR / f"{IMPORT_TEMPLATE_ID}.glb.import"
    if not template_path.exists():
        raise FileNotFoundError(
            f"no import template at {template_path} — cannot set the retarget bone map"
        )
    template = template_path.read_text(encoding="utf-8")
    marker = "[params]"
    if marker not in template:
        raise RuntimeError(f"{template_path} has no [params] section")
    params = template[template.index(marker) :]
    template_key = IMPORT_SKELETON_KEY.format(sex=_sex_of_import_template())
    wanted_key = IMPORT_SKELETON_KEY.format(sex=sex)
    if template_key not in params:
        raise RuntimeError(f"{template_path} has no {template_key} subresource block")
    params = params.replace(template_key, wanted_key)

    target = out_glb.with_suffix(".glb.import")
    if target.exists():
        existing = target.read_text(encoding="utf-8")
        if wanted_key in existing:
            _log(f"Import settings already carry {wanted_key}: {target.name}")
            return
        head = existing[: existing.index(marker)] if marker in existing else _import_head()
        target.write_text(head + params, encoding="utf-8")
        _log(f"Repaired missing retarget block in {target.name}")
        return
    target.write_text(_import_head() + params, encoding="utf-8")
    _log(f"Wrote import settings with {wanted_key}: {target.name}")


def _import_head() -> str:
    return '[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n'


def _sex_of_import_template() -> str:
    for spec in OUTFIT_MATRIX:
        if spec["id"] == IMPORT_TEMPLATE_ID:
            return spec["sex"]
    raise RuntimeError(f"{IMPORT_TEMPLATE_ID} is not in OUTFIT_MATRIX")


def _material_names(obj) -> list[str]:
    names = [slot.name for slot in obj.data.materials if slot is not None]
    if not names:
        raise RuntimeError(f"{obj.name}: no material to name in the catalog")
    return names


def _create_and_export_outfit(spec: dict) -> dict:
    HumanService = _mpfb_import("services.humanservice").HumanService
    sex = spec["sex"]
    outfit_id = spec["id"]

    _clear_scene()
    gender = 0.05 if sex == "female" else 0.95
    basemesh = HumanService.create_human(
        mask_helpers=True,
        detailed_helpers=True,
        extra_vertex_groups=True,
        feet_on_ground=True,
        scale=0.1,
        macro_detail_dict=_macro(gender),
    )
    basemesh.name = f"{sex}_body"
    _log(f"Created basemesh for {outfit_id}")

    armature = HumanService.add_builtin_rig(basemesh, "game_engine", import_weights=True)
    if armature is None:
        raise RuntimeError("Failed to add game_engine rig")
    armature.name = f"{sex}_armature"

    # Weapons and masks ship as Clothes-type mhclo assets too, so everything a variant wears
    # goes through the same call in equip order.
    garments = _garments_of(spec)
    for garment in garments:
        garment_path = _mhclo_path(garment)
        _log(f"Equipping {garment_path.name}")
        HumanService.add_mhclo_asset(
            str(garment_path),
            basemesh,
            asset_type="Clothes",
            subdiv_levels=0,
            material_type="GAMEENGINE",
            set_up_rigging=True,
            interpolate_weights=True,
            import_subrig=False,
            import_weights=True,
        )

    clothes_objs = _find_clothes_objects(basemesh)
    _log(f"Clothes objects: {[o.name for o in clothes_objs]}")

    # Bake body helpers / delete groups (skin under cloth).
    _strip_shape_keys_keeping_mix(basemesh)
    _apply_non_armature_modifiers(basemesh)
    if len(basemesh.data.vertices) > 14000:
        _delete_non_body_vertices(basemesh)
    _assign_unweighted_verts_to_spine(basemesh)
    _limit_weights_to_four(basemesh)
    _assign_skin_material(basemesh, sex)
    skin_material = _material_names(basemesh)[0]

    garment_materials: list[str] = []
    for clothes in clothes_objs:
        _apply_non_armature_modifiers(clothes)
        _assign_unweighted_verts_to_spine(clothes)
        _limit_weights_to_four(clothes)
        garment_materials.extend(_material_names(clothes))
    if skin_material in garment_materials:
        raise RuntimeError(f"{outfit_id}: garment reuses the skin material {skin_material}")

    bpy.ops.object.select_all(action="DESELECT")
    basemesh.select_set(True)
    armature.select_set(True)
    for clothes in clothes_objs:
        clothes.select_set(True)
    bpy.context.view_layer.objects.active = armature

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_glb = OUT_DIR / f"{outfit_id}.glb"
    if out_glb.exists():
        out_glb.unlink()

    bpy.ops.export_scene.gltf(
        filepath=str(out_glb),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_animations=False,
        export_skins=True,
        export_morph=False,
        export_yup=True,
    )
    _log(f"Exported {out_glb} ({out_glb.stat().st_size} bytes)")
    _write_import_settings(out_glb, sex)

    tag = spec["tags"][0] if spec["tags"] else "casual"
    rgb = PROXY_COLORS.get(tag, (0.4, 0.4, 0.45))
    # The runtime tints the skin mesh by matching material names, so record the names that were
    # actually exported instead of letting Godot re-derive them from node names.
    return {
        "id": outfit_id,
        "sex": sex,
        "female": sex == "female",
        "path": f"res://assets/humans/outfits/{outfit_id}.glb",
        "tags": spec["tags"],
        "garments": list(garments),
        "skin_material": skin_material,
        "garment_materials": garment_materials,
        "proxy_color": list(rgb),
    }


def main() -> None:
    _log("Starting MPFB outfit export")
    if not MPFB_SRC.exists():
        raise FileNotFoundError(MPFB_SRC)
    _ensure_mpfb_enabled()
    _install_system_assets()

    LocationService = _mpfb_import("services.locationservice").LocationService
    _log(f"MPFB user data: {LocationService.get_user_data()}")

    only = os.environ.get("OUTFIT_ONLY", "").strip()
    matrix = OUTFIT_MATRIX
    if only:
        matrix = [s for s in OUTFIT_MATRIX if s["id"] == only]
        if not matrix:
            raise RuntimeError(f"OUTFIT_ONLY={only} not in matrix")

    catalog: list[dict] = []
    for spec in matrix:
        try:
            entry = _create_and_export_outfit(spec)
            catalog.append(entry)
        except Exception as exc:  # noqa: BLE001
            _log(f"FAILED {spec['id']}: {exc}")
            import traceback

            traceback.print_exc()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    catalog_path = OUT_DIR / "catalog.json"
    # Merge with existing catalog entries not in this run.
    existing: dict[str, dict] = {}
    if catalog_path.exists():
        try:
            for e in json.loads(catalog_path.read_text(encoding="utf-8")):
                existing[e["id"]] = e
        except Exception:
            pass
    for e in catalog:
        existing[e["id"]] = e
    merged = list(existing.values())
    merged.sort(key=lambda e: e["id"])
    catalog_path.write_text(json.dumps(merged, indent=2), encoding="utf-8")
    _log(f"Wrote catalog {catalog_path} ({len(merged)} outfits)")
    _log("DONE")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback

        traceback.print_exc()
        sys.exit(1)
