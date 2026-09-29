"""Godot side of the village art pass (plain Python, no bpy):

1. village_tex/*.png.import: VRAM compressed + mipmaps, *_nrm flagged as normal maps
   (only written when missing; Godot fills in uid / dest paths on import).
2. village_tex/ra_<family>.tres: one shared StandardMaterial3D per detail family, identical to
   what Godot's glTF importer builds from the GLBs (albedo texture x vertex colour, normal map,
   roughness = G, metallic = B of the metallicRoughness map).
3. every generated building/prop .glb.import: maps the GLB's RA_* materials to those shared .tres
   files (use_external), so all buildings share 7 material resources instead of one copy per GLB.
   Existing .import files keep their uid; new GLBs get a minimal .import that Godot completes.

Run from anywhere:  python3 write_village_godot_materials.py
"""
import os, re, glob

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))            # kingdom/
GEN = os.path.join(ROOT, "assets", "generated")
TEX = os.path.join(GEN, "village_tex")
RES_TEX = "res://assets/generated/village_tex/"

# material name in the GLBs -> (family, metallic)
SHARED = {"RA_Wood": ("wood", 0.0), "RA_Plank": ("wood", 0.0), "RA_Board": ("wood", 0.0), "RA_Deck": ("wood", 0.0),
          "RA_Plaster": ("plaster", 0.0), "RA_Matte": ("stone", 0.0), "RA_Stone": ("stone", 0.0),
          "RA_Roof": ("roof", 0.0), "RA_Shingle": ("roof", 0.0), "RA_Thatch": ("thatch", 0.0),
          "RA_Cloth": ("cloth", 0.0), "RA_Rope": ("cloth", 0.0), "RA_Metal": ("iron", 1.0)}
# hand-painted art families (ra_polish.ART_FAMS): GLB material names carry an _hp suffix. One shared
# material each: painted albedo (kingdom/assets/art/textures) x vertex colour, constant roughness.
ART_SHARED = {"RA_Wood_hp": "wood", "RA_Plank_hp": "wood", "RA_Board_hp": "wood", "RA_Deck_hp": "wood",
              "RA_Hull_hp": "wood", "RA_Matte_hp": "stone", "RA_Stone_hp": "stone", "RA_Roof_hp": "slate",
              "RA_Shingle_hp": "slate", "RA_Paving_hp": "cobble"}
ART_MAT = {"wood": ("wood_planks.png", 0.74), "stone": ("stone_wall_blocks.png", 0.92),
           "slate": ("roof_slate_blue.png", 0.7), "cobble": ("cobblestone.png", 0.9)}
ART_TEX = "res://assets/art/textures/"
ART_TRES = """[gd_resource type="StandardMaterial3D" load_steps=2 format=3]

[ext_resource type="Texture2D" path="{t}{png}" id="1"]

[resource]
resource_name = "RA_{F}_hp"
vertex_color_use_as_albedo = true
albedo_texture = ExtResource("1")
metallic = 0.0
roughness = {rough}
"""
FAMILIES = sorted({f for f, _ in SHARED.values()})

TEX_IMPORT = '''[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="{src}"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map={nm}
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
'''

MAT = '''[gd_resource type="StandardMaterial3D" load_steps=4 format=3]

[ext_resource type="Texture2D" path="{t}ra_{f}_alb.png" id="1"]
[ext_resource type="Texture2D" path="{t}ra_{f}_nrm.png" id="2"]
[ext_resource type="Texture2D" path="{t}ra_{f}_mr.png" id="3"]

[resource]
resource_name = "RA_{F}"
vertex_color_use_as_albedo = true
albedo_texture = ExtResource("1")
metallic = {metal}
metallic_texture = ExtResource("3")
metallic_texture_channel = 2
roughness_texture = ExtResource("3")
roughness_texture_channel = 1
normal_enabled = true
normal_texture = ExtResource("2")
'''

GLB_IMPORT = '''[remap]

importer="scene"
importer_version=1
type="PackedScene"

[deps]

source_file="res://assets/generated/{name}"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/root_script=null
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=1
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=true
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path=""
materials/extract=0
materials/extract_format=0
materials/extract_path=""
_subresources={{}}
gltf/naming_version=2
gltf/embedded_image_handling=1
'''


def glb_materials(path):
    import json, struct
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + n])
    uses_tex = any("village_tex/" in im.get("uri", "") or "art/textures/" in im.get("uri", "")
                   for im in j.get("images", []))
    return [m.get("name", "") for m in j.get("materials", [])], uses_tex


def subresources(mats):
    ent = []
    for m in mats:
        if m in ART_SHARED:
            p = f"{RES_TEX}ra_hp_{ART_SHARED[m]}.tres"
        elif m in SHARED:
            p = f"{RES_TEX}ra_{SHARED[m][0]}.tres"
        else:
            continue
        if True:
            ent.append(f'"{m}": {{\n"use_external/enabled": true,\n"use_external/fallback_path": "{p}",\n'
                       f'"use_external/path": "{p}"\n}}')
    if not ent:
        return "{}"
    return '{\n"materials": {\n' + ",\n".join(ent) + "\n}\n}"


def main():
    for p in sorted(glob.glob(os.path.join(TEX, "ra_*.png"))):
        imp = p + ".import"
        if not os.path.exists(imp):
            open(imp, "w").write(TEX_IMPORT.format(src=RES_TEX + os.path.basename(p),
                                                   nm=1 if p.endswith("_nrm.png") else 2))
            print("wrote", os.path.relpath(imp, ROOT))
    for f in FAMILIES:
        metal = next(m for fam, m in SHARED.values() if fam == f)
        out = os.path.join(TEX, f"ra_{f}.tres")
        open(out, "w").write(MAT.format(t=RES_TEX, f=f, F=f.capitalize(), metal=metal))
        print("wrote", os.path.relpath(out, ROOT))
    for f, (png, rough) in ART_MAT.items():
        out = os.path.join(TEX, f"ra_hp_{f}.tres")
        open(out, "w").write(ART_TRES.format(t=ART_TEX, png=png, F=f.capitalize(), rough=rough))
        print("wrote", os.path.relpath(out, ROOT))
    for glb in sorted(glob.glob(os.path.join(GEN, "*.glb"))):
        mats, uses_tex = glb_materials(glb)
        if not uses_tex:
            continue          # not part of the textured village set (orc camp, pier, old field crops...)
        imp = glb + ".import"
        name = os.path.basename(glb)
        txt = open(imp).read() if os.path.exists(imp) else GLB_IMPORT.format(name=name)
        sub = subresources(mats)
        txt2 = re.sub(r"_subresources=\{.*?\n\}\n(?=gltf/)|_subresources=\{\}\n", "_subresources=" + sub + "\n", txt,
                      flags=re.S)
        if txt2 != txt or not os.path.exists(imp):
            open(imp, "w").write(txt2)
            print("updated" if os.path.exists(imp) else "wrote", os.path.relpath(imp, ROOT))


if __name__ == "__main__":
    main()
