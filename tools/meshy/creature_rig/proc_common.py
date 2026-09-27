"""Helpers for procedural rigs: normalise a static Meshy mesh, build an armature, nearest-segment skin weights,
world-axis pose keys, IK bake."""
import bpy, math
import numpy as np
from mathutils import Vector, Matrix, Quaternion, Euler
from common import *


def load_normalised(path, mode, val):
    objs, _ = import_new(path)
    m = [o for o in objs if o.type == 'MESH'][0]
    bpy.context.view_layer.objects.active = m
    for o in bpy.data.objects: o.select_set(o == m)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    mn, mx = world_bbox([m])
    m.data.transform(Matrix.Translation(Vector((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))))
    d = mx - mn
    k = val / (d.z if mode == 'height' else d.x)
    m.data.transform(Matrix.Scale(k, 4)); m.data.update()
    return m


def build_armature(name, bones):
    """bones: list of dicts name, head, tail, parent(None), deform(True)"""
    ad = bpy.data.armatures.new(name + "_arm")
    arm = bpy.data.objects.new(name + "_rig", ad)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    for o in bpy.data.objects: o.select_set(o == arm)
    bpy.ops.object.mode_set(mode='EDIT')
    for b in bones:
        eb = ad.edit_bones.new(b["name"])
        eb.head = Vector(b["head"]); eb.tail = Vector(b["tail"]); eb.roll = 0
        eb.use_deform = b.get("deform", True)
    for b in bones:
        if b.get("parent"):
            ad.edit_bones[b["name"]].parent = ad.edit_bones[b["parent"]]
            ad.edit_bones[b["name"]].use_connect = False
    bpy.ops.object.mode_set(mode='OBJECT')
    for pb in arm.pose.bones: pb.rotation_mode = 'QUATERNION'
    return arm


def seg_dist(P, a, b):
    ab = b - a; L2 = max(1e-9, ab @ ab)
    t = np.clip(((P - a) @ ab) / L2, 0, 1)
    Q = a + t[:, None] * ab
    return np.linalg.norm(P - Q, axis=1)


def skin_nearest(mesh, arm, zones=(), k=3, power=4.0, eps=0.01, exclude=()):
    """Nearest-bone-segment weights. zones: [(center, radii, [bones])] vertices inside an ellipsoid get only those bones."""
    P = np.array([v.co[:] for v in mesh.data.vertices])
    deform = [b for b in arm.data.bones if b.use_deform and b.name not in exclude]
    names = [b.name for b in deform]
    mw = arm.matrix_world
    D = np.stack([seg_dist(P, np.array((mw @ b.head_local)[:]), np.array((mw @ b.tail_local)[:])) for b in deform], axis=1)
    allowed = np.ones_like(D, dtype=bool)
    for z in zones:
        if callable(z[0]):
            inside = z[0](P); bl = z[1]
        else:
            c, r, bl = z
            inside = (((P - np.array(c)) / np.array(r)) ** 2).sum(axis=1) <= 1.0
        mask = np.array([n in bl for n in names])
        allowed[inside] = mask
    D = np.where(allowed, D, 1e9)
    for vg in list(mesh.vertex_groups): mesh.vertex_groups.remove(vg)
    groups = {n: mesh.vertex_groups.new(name=n) for n in names}
    idx = np.argsort(D, axis=1)[:, :k]
    for i in range(len(P)):
        ds = D[i, idx[i]]
        w = 1.0 / (ds + eps) ** power
        w = w / w.sum()
        for j, wt in zip(idx[i], w):
            if wt > 0.03:
                groups[names[j]].add([i], float(wt), 'REPLACE')
    for o in bpy.data.objects: o.select_set(o == mesh)
    bpy.context.view_layer.objects.active = mesh
    bpy.ops.object.vertex_group_normalize_all(group_select_mode='ALL', lock_active=False)
    mesh.parent = arm
    mod = mesh.modifiers.new("Armature", 'ARMATURE'); mod.object = arm


def world_rot(arm, bname, axis, deg):
    """Quaternion for pose-bone basis that rotates the bone about an armature-space axis."""
    B = arm.data.bones[bname].matrix_local.to_quaternion()
    R = Quaternion(Vector(axis).normalized(), math.radians(deg))
    return B.inverted() @ R @ B


def world_loc(arm, bname, vec):
    B = arm.data.bones[bname].matrix_local.to_3x3()
    return B.inverted() @ Vector(vec)


class Anim:
    """Collects keys {frame: {bone: (quat or None, loc or None)}} and writes them into a new action."""
    def __init__(self, arm, name):
        self.arm = arm; self.name = name; self.keys = {}
    def rot(self, f, b, axis, deg):
        q = world_rot(self.arm, b, axis, deg)
        k = self.keys.setdefault(f, {}).setdefault(b, [Quaternion(), None])
        k[0] = q @ k[0]
    def rotq(self, f, b, q):
        self.keys.setdefault(f, {}).setdefault(b, [Quaternion(), None])[0] = q
    def loc(self, f, b, vec):
        self.keys.setdefault(f, {}).setdefault(b, [Quaternion(), None])[1] = world_loc(self.arm, b, vec)
    def write(self, all_bones=True):
        arm = self.arm
        ac = bpy.data.actions.new(self.name + "_ctl")
        arm.animation_data_create(); arm.animation_data.action = ac
        frames = sorted(self.keys)
        used = sorted({b for f in frames for b in self.keys[f]})
        for f in frames:
            for pb in arm.pose.bones:
                pb.rotation_quaternion = Quaternion(); pb.location = Vector()
            for b, (q, l) in self.keys[f].items():
                arm.pose.bones[b].rotation_quaternion = q
                if l is not None: arm.pose.bones[b].location = l
            for b in used:
                pb = arm.pose.bones[b]
                pb.keyframe_insert("rotation_quaternion", frame=f)
                pb.keyframe_insert("location", frame=f)
        return ac, frames[0], frames[-1]


def bake(arm, ctl, f0, f1, name):
    arm.animation_data.action = ctl
    try: arm.animation_data.action_slot = ctl.slots[0]
    except Exception: pass
    bpy.context.view_layer.objects.active = arm
    for o in bpy.data.objects: o.select_set(o == arm)
    bpy.ops.object.mode_set(mode='POSE')
    bpy.ops.pose.select_all(action='SELECT')
    bpy.ops.nla.bake(frame_start=int(f0), frame_end=int(f1), step=1, only_selected=False, visual_keying=True,
                     clear_constraints=False, clear_parents=False, use_current_action=False, bake_types={'POSE'})
    bpy.ops.object.mode_set(mode='OBJECT')
    ac = arm.animation_data.action
    ac.name = name; ac.use_fake_user = True
    ac.slots[0].name_display = arm.name
    arm.animation_data.action = None
    bpy.data.actions.remove(ctl)
    return ac


def add_ik(arm, bone, target, chain, pole=None, pole_angle=0.0):
    c = arm.pose.bones[bone].constraints.new('IK')
    c.target = arm; c.subtarget = target; c.chain_count = chain
    if pole:
        c.pole_target = arm; c.pole_subtarget = pole; c.pole_angle = math.radians(pole_angle)
    return c


def clear_constraints(arm):
    for pb in arm.pose.bones:
        for c in list(pb.constraints): pb.constraints.remove(c)
