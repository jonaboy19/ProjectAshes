"""Shared helpers for the wolf pipeline (Blender 5.2, run with -b --python).
Rig facts (glTF import): wolf faces -Y in Blender (glTF +Z), Z up, X lateral (+X = wolf's LEFT? see LEFT_SIGN).
The armature object carries the scale (0.38 in the original, 0.38*1.3 after the resize); all bone data
is in 'rig units'. Everything measured/reported is converted to metres through arm.matrix_world."""
import bpy, math, os, sys, mathutils
import numpy as np
from mathutils import Vector, Matrix, Quaternion

PAW_BONES = {"FL": "FrontLowerLeg.L", "FR": "FrontLowerLeg.R", "BL": "BackLowerLeg.L", "BR": "BackLowerLeg.R"}

def load_glb(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(path))
    for o in list(bpy.data.objects):
        if o.type == 'MESH' and o.name.startswith('Icosphere'): bpy.data.objects.remove(o)
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    mesh = [o for o in bpy.data.objects if o.type == 'MESH'][0]
    return arm, mesh

def clip_actions():
    return {a.name.split('|')[-1]: a for a in bpy.data.actions}

def assign(arm, act):
    arm.animation_data_create(); arm.animation_data.action = act
    if act.slots: arm.animation_data.action_slot = act.slots[0]

def mesh_world_np(mesh):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = mesh.evaluated_get(dg); me = ev.to_mesh()
    n = len(me.vertices); a = np.empty(n * 3, np.float32); me.vertices.foreach_get('co', a); ev.to_mesh_clear()
    a = a.reshape(n, 3)
    M = np.array(ev.matrix_world); return a @ M[:3, :3].T + M[:3, 3]

def paw_sets(mesh, arm):
    """vertex index sets of the paws (weight > .5 to that lower-leg bone, lowest 0.25 rig-units of the rest pose)."""
    names = {v.index: v.name for v in mesh.vertex_groups}
    gi = {k: mesh.vertex_groups[b].index for k, b in PAW_BONES.items()}
    out = {}
    co = np.array([v.co[:] for v in mesh.data.vertices])
    for k, g in gi.items():
        idx = [v.index for v in mesh.data.vertices if any(gr.group == g and gr.weight > 0.5 for gr in v.groups)]
        idx = np.array(idx); zmin = co[idx, 2].min()
        out[k] = idx[co[idx, 2] < zmin + 0.25]
    return out

def frame_range(a):
    return int(round(a.frame_range[0])), int(round(a.frame_range[1]))


def add_nla(arm, name, action, start=None):
    ad = arm.animation_data or arm.animation_data_create()
    tr = ad.nla_tracks.new(); tr.name = name
    s = int(start if start is not None else action.frame_range[0])
    st = tr.strips.new(name, s, action)
    try:
        if action.slots: st.action_slot = action.slots[0]
    except Exception as e: print("slot warn", e)
    action.name = name
    action.use_fake_user = True
    tr.mute = False
    return tr


def export(path, objs):
    for o in bpy.data.objects: o.select_set(o in objs)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format='GLB',
        export_image_format='JPEG', export_jpeg_quality=88, export_animation_mode='ACTIONS',
        export_skins=True, export_draco_mesh_compression_enable=False, export_apply=False,
        export_anim_single_armature=True, export_def_bones=False)
    print("EXPORTED", path, os.path.getsize(path) // 1024, "KB")
