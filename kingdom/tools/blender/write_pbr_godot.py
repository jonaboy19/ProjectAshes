"""Godot side of the high-to-low PBR bake (plain Python, no bpy). Run after pbr_kit baked assets:

1. kingdom/assets/generated/pbr/*.png.import: VRAM compressed + mipmaps, *_nrm flagged as normal map
   (only written when missing; Godot fills in uid / dest paths on import).
2. every generated .glb whose glTF images point into pbr/: its .import gets `_subresources={}` so the GLB's own
   PBR material (baseColor x COLOR_0, normal, occlusion + metallicRoughness) is used -- the RA_* -> shared .tres
   remap of write_village_godot_materials.py must not touch these (their material names are RA_PBR_<asset>).

Run from anywhere:  python3 write_pbr_godot.py
"""
import os, re, glob, json, struct

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))            # kingdom/
GEN = os.path.join(ROOT, "assets", "generated")
PBR = os.path.join(GEN, "pbr")
RES_PBR = "res://assets/generated/pbr/"

TEX_IMPORT = '''[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="{src}"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.8
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


def glb_uses_pbr(path):
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + n])
    return any(im.get("uri", "").replace("\\", "/").startswith("pbr/") for im in j.get("images", []))


def main():
    for p in sorted(glob.glob(os.path.join(PBR, "*.png"))):
        imp = p + ".import"
        if not os.path.exists(imp):
            nm = 1 if p.endswith("_nrm.png") else 2
            open(imp, "w").write(TEX_IMPORT.format(src=RES_PBR + os.path.basename(p), nm=nm))
            print("wrote", os.path.relpath(imp, ROOT))
    for glb in sorted(glob.glob(os.path.join(GEN, "*.glb"))):
        if not glb_uses_pbr(glb):
            continue
        imp = glb + ".import"
        name = os.path.basename(glb)
        txt = open(imp).read() if os.path.exists(imp) else GLB_IMPORT.format(name=name)
        txt2 = re.sub(r"_subresources=\{.*?\n\}\n(?=gltf/)|_subresources=\{\}\n", "_subresources={}\n", txt, flags=re.S)
        if txt2 != txt or not os.path.exists(imp):
            open(imp, "w").write(txt2)
            print("updated" if os.path.exists(imp) else "wrote", os.path.relpath(imp, ROOT))


if __name__ == "__main__":
    main()
