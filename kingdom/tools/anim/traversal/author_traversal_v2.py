# Hand-authored traversal clips v2 (ladder, wall, ledge, vault, horse riding) on the Quaternius UAL skeleton.
#   blender -b -P author_traversal_v2.py -- <out.glb> [Clip,Clip,...]
# Every clip is built from world-space keyed tracks (hands and feet are IK targets: they are world-fixed while in contact),
# solved with Blender IK, baked to plain FK quaternion keys and exported as GLB with NLA tracks (loop clips get the _Loop
# suffix). A <out.glb>.clips.json sidecar (name, loop, frames, seconds) is written next to it. Run glb_reduce_anim.py after
# (see README.md). Helpers: trav_lib.py (tracks, geometry, bake, validation); rig setup is reused from
# ../free2/author_traversal.py; clips live in clips_*.py.
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from trav_lib import *
import trav_lib as TL
import clips_vault
import clips_climb
import clips_ride

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.abspath(argv[0])
ONLY = argv[1].split(",") if len(argv) > 1 and argv[1] else None


def export(made, report, out):
    A.assign(tgt, None)
    for k, e in T.items():
        bpy.data.objects.remove(e)
    for pb in tgt.pose.bones:
        for c in list(pb.constraints):
            pb.constraints.remove(c)
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
    me = bpy.data.meshes.new("UAL_Skin_Stub")
    me.from_pydata([(0, 0, 0.9), (0.01, 0, 0.9), (0, 0.01, 0.9)], [], [(0, 1, 2)])
    ob = bpy.data.objects.new("UAL_Skin_Stub", me)
    A.scene.collection.objects.link(ob)
    ob.parent = tgt
    vg = ob.vertex_groups.new(name="pelvis")
    vg.add([0, 1, 2], 1.0, "REPLACE")
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = tgt
    tgt.name = "Armature"
    loops = dict((r["name"], r["loop"]) for r in report)
    for name, a in made:
        tr = tgt.animation_data.nla_tracks.new()
        tr.name = name + ("_Loop" if loops[name] else "")
        tr.strips.new(tr.name, 0, a)
    bpy.ops.object.select_all(action="DESELECT")
    tgt.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = tgt
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_force_sampling=False,
                              export_optimize_animation_size=False, export_draco_mesh_compression_enable=False,
                              export_materials="NONE", export_apply=False, export_yup=True, export_def_bones=False,
                              export_anim_single_armature=True, export_reset_pose_bones=True)
    json.dump(report, open(out + ".clips.json", "w"), indent=1)
    print("EXPORTED", out, len(made))


if __name__ == "__main__":
    A.pole_calibrate()
    report, made = [], []
    for name, fn in TL.CLIPS.items():
        if ONLY and name not in ONLY:
            continue
        poses, loop = fn()
        act, diag = bake2(name, poses)
        report_reach(name, diag)
        if name.startswith("Vault"):
            report_box(name, diag, clips_vault.BOX)
        made.append((name, act))
        report.append({"name": name, "loop": loop, "frames": len(poses), "seconds": round((len(poses) - 1) / FPS, 2)})
        print("CLIP", name, len(poses), flush=True)
    export(made, report, OUT)
