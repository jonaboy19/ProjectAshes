"""Shared helpers for the group-Q creature motion tools (Blender 5.2, run headless with -b).
Import a creature GLB at 30 fps, address clips by name, sample world-space points per frame."""
import bpy, sys, os, math, mathutils
import numpy as np
FPS = 30
CREATURES = {
 'boar':  ('kingdom/assets/incoming/ai3d/meshy/creatures/boar', 'quad'),
 'bear':  ('kingdom/assets/incoming/ai3d/meshy/creatures/bear', 'quad'),
 'spider':('kingdom/assets/incoming/ai3d/meshy/creatures/spider', 'spider'),
 'giant_wasp': ('kingdom/assets/incoming/monsters/quaternius/giant_wasp', 'wasp'),
}
def repo():
    return os.environ.get('MQ_REPO', 'C:/Users/Jonna/Documents/PA_wt_creature')

def load(glb):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    bpy.ops.import_scene.gltf(filepath=glb)
    for o in list(bpy.data.objects):
        if o.type == 'MESH' and o.name.startswith('Icosphere') and o.parent is None:
            bpy.data.objects.remove(o)
    arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
    meshes = [o for o in bpy.data.objects if o.type == 'MESH']
    acts = {a.name.split('|')[-1]: a for a in bpy.data.actions}
    arm.animation_data_create()
    return arm, meshes, acts

def set_clip(arm, a):
    arm.animation_data.action = a
    if a.slots: arm.animation_data.action_slot = a.slots[0]

def clip_frames(a):
    f0, f1 = a.frame_range
    return f0, f1, (f1 - f0) / FPS

def eval_verts(mesh):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = mesh.evaluated_get(dg); me = ev.to_mesh()
    n = len(me.vertices); co = np.empty(n * 3, dtype=np.float32); me.vertices.foreach_get('co', co)
    ev.to_mesh_clear()
    co = co.reshape(-1, 3)
    M = np.array(mesh.matrix_world)
    return co @ M[:3, :3].T + M[:3, 3]

def group_verts(mesh, names, minw=0.5):
    """indices of vertices whose summed weight on the named groups >= minw"""
    gi = {vg.index for vg in mesh.vertex_groups if vg.name in names}
    out = []
    for v in mesh.data.vertices:
        w = sum(g.weight for g in v.groups if g.group in gi)
        if w >= minw: out.append(v.index)
    return np.array(out, dtype=int)

def frames_of(a, step=1):
    f0, f1 = a.frame_range
    n = int(round((f1 - f0)))          # frames at 30 fps
    return [f0 + k for k in range(0, n + 1, step)]
