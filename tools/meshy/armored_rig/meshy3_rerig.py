#!/usr/bin/env python3
"""Re-rig the Meshy batch 3 "biped" characters (Mixamo-style 23-24 bone skeleton, kingdom/assets/incoming/meshy_dl3/characters_rigged)
onto the game's 65-bone Quaternius UAL skeleton, so every UAL clip plays through Assets._ual_for with no BoneMap.
It does what the armored characters did (armored_rig.py): per character it (1) bakes the REST-pose mesh out of the skinned GLB
(armature and Meshy clip dropped), (2) extracts the base-colour JPEG, (3) writes a config and runs armored_rig.py (landmarks, bone-heat
weights, cloth/helmet clean-up, UAL fit, LOD0/LOD1, 1024/512 px).
Usage (bpy as a Python module, see .claude/skills/ashes-cloud-blender):
  /tmp/claude-0/bpyenv/bin/python tools/meshy/armored_rig/meshy3_rerig.py <work_dir> name [name ...]
Results land in kingdom/assets/incoming/meshy_dl3/characters_ual/<name>.glb (+ _lod1.glb, _report.json). Review with
tools_qa/meshy3/rig_sheet.gd (poses) before using; see docs/art/meshy_dl3/README.md for which ones pass.
Known fails (kept out): noblewoman_cape (the cape and sword confuse the arm landmark fit: arms stay out, cape spreads) and
soldier_shield_sword (shield and sword mesh are stretched by the arm weights). They need hand-placed landmarks via the config
"overrides" (arm_fit_range, shoulder) or a Blender weight clean-up; knight_plate_grey has no texture."""
import json, os, struct, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
INC = os.path.join(REPO, "kingdom", "assets", "incoming")
SRC = os.path.join(INC, "meshy_dl3", "characters_rigged")
OUT = os.path.join(INC, "meshy_dl3", "characters_ual")
UAL = os.path.join(INC, "quaternius", "universal-animation-library", "Unreal-Godot", "UAL1_Standard.glb")
HEIGHTS = {"guardian_hooded": 1.75, "knight_plate_a": 1.85, "merchant_cloaked": 1.72, "noblewoman_cape": 1.68, "peasant_hooded": 1.70,
           "soldier_shield_sword": 1.82, "villager_green_vest": 1.75, "villager_hat": 1.72, "villager_white_shirt": 1.72}
PREP = r'''
import bpy, sys
src, out = sys.argv[-2], sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
for o in bpy.data.objects:
    if o.type == 'ARMATURE':
        o.data.pose_position = 'REST'
        if o.animation_data: o.animation_data_clear()
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
for m in [o for o in bpy.data.objects if o.type == 'MESH' and o.vertex_groups]:
    me = bpy.data.meshes.new_from_object(m.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    me.transform(m.matrix_world.copy())
    new = bpy.data.objects.new(m.name + "_rest", me)
    bpy.context.scene.collection.objects.link(new)
    for mat in m.data.materials: new.data.materials.append(mat)
for o in list(bpy.data.objects):
    if o.type != 'MESH' or not o.name.endswith('_rest'):
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', export_image_format='JPEG', export_animations=False)
'''


def extract_texture(glb, dest):
    b = open(glb, "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + n])
    bv = j["bufferViews"][j["images"][0]["bufferView"]]
    off = 20 + n + 8 + bv.get("byteOffset", 0)
    open(dest, "wb").write(b[off:off + bv["byteLength"]])


def main():
    work, names = os.path.abspath(sys.argv[1]), sys.argv[2:]
    os.makedirs(work, exist_ok=True)
    open(os.path.join(work, "prep_rest.py"), "w").write(PREP)
    for n in names:
        glb = os.path.join(SRC, n + "_lod0.glb")
        tex = os.path.join(work, n + "_tex.jpg")
        rest = os.path.join(work, n + "_src.glb")
        extract_texture(glb, tex)
        subprocess.run([sys.executable, os.path.join(work, "prep_rest.py"), "--", glb, rest], capture_output=True, check=True)
        cfg = {"name": n, "height": HEIGHTS[n], "source": rest, "texture": tex, "ual": UAL, "out_dir": OUT, "lod0_tris": 8000,
               "lod1_tris": 3000, "tex_lod0": 1024, "tex_lod1": 512, "overrides": {}}
        cp = os.path.join(work, "cfg_%s.json" % n)
        json.dump(cfg, open(cp, "w"), indent=1)
        r = subprocess.run([sys.executable, os.path.join(HERE, "armored_rig.py"), "--", cp], capture_output=True, text=True)
        rep = [x for x in r.stdout.splitlines() if x.startswith("REPORT")]
        print(n, rep[-1] if rep else r.stderr[-500:])


if __name__ == "__main__":
    main()
