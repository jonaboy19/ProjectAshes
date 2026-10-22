"""Pose-authoring toolkit for the group-Q creatures (Blender 5.2, headless).
Everything works in ARMATURE SPACE with our own forward kinematics, so a pose can be built from world-axis rotations
about bone heads plus foot IK, without touching the depsgraph. Units in scripts are METRES (converted with rig.s).
Axes (Blender): the creature faces -Y, +Z is up, +X is the creature's left. Rotation about +X by +deg pitches the nose
DOWN (the nose is at -Y)."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mq import *
from mathutils import Matrix, Vector, Quaternion

def T(v): return Matrix.Translation(v)

class Rig:
    def __init__(self, arm, mesh, acts):
        self.arm, self.mesh, self.acts = arm, mesh, acts
        self.s = arm.scale[0]
        bones = list(arm.data.bones)
        def depth(b): return 0 if b.parent is None else 1 + depth(b.parent)
        self.names = [b.name for b in sorted(bones, key=depth)]
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in bones}
        self.R = {b.name: b.matrix_local.copy() for b in bones}
        self.O = {n: (self.R[p].inverted() @ self.R[n] if p else self.R[n].copy()) for n, p in self.parent.items()}
        self.children = {n: [] for n in self.names}
        for n, p in self.parent.items():
            if p: self.children[p].append(n)
        for pb in arm.pose.bones: pb.rotation_mode = 'QUATERNION'

    # ---- channels <-> matrices
    def read(self, clip, f):
        set_clip(self.arm, self.acts[clip]); bpy.context.scene.frame_set(int(f))
        return {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(), pb.scale.copy()) for pb in self.arm.pose.bones}

    def L(self, c): return Matrix.LocRotScale(c[0], c[1], c[2])

    def fk(self, ch):
        P = {}
        for n in self.names:
            p = self.parent[n]
            P[n] = (P[p] if p else Matrix.Identity(4)) @ self.O[n] @ self.L(ch[n])
        return P

    def channels(self, P, prev=None):
        ch = {}
        for n in self.names:
            p = self.parent[n]
            Lm = ((P[p] if p else Matrix.Identity(4)) @ self.O[n]).inverted() @ P[n]
            l, q, sc = Lm.decompose()
            if prev is not None and q.dot(prev[n][1]) < 0: q = -q          # keep quaternion continuity
            ch[n] = (l, q, sc)
        return ch

    # ---- mesh points bound to a bone (foot points etc)
    def rest_points(self, idx):
        """arm-space rest position of mesh verts idx (rest pose)"""
        self.arm.data.pose_position = 'REST'; bpy.context.view_layer.update()
        V = eval_verts(self.mesh)[idx]
        self.arm.data.pose_position = 'POSE'; bpy.context.view_layer.update()
        M = np.array(self.arm.matrix_world.inverted())
        return V @ M[:3, :3].T + M[:3, 3]

    def attach(self, bone, p_arm_rest):
        """a point fixed to a bone: bone-local coordinates of an armature-space REST point"""
        return self.R[bone].inverted() @ Vector(p_arm_rest)

    # ---- rotations of a bone's whole subtree
    def subtree(self, n):
        out = [n]
        for c in self.children[n]: out += self.subtree(c)
        return out

    def rotate_subtree(self, P, n, center, axis, deg):
        R = T(center) @ Matrix.Rotation(math.radians(deg), 4, axis) @ T(-center)
        for m in self.subtree(n): P[m] = R @ P[m]

    def rotate_subtree_q(self, P, n, center, q):
        R = T(center) @ q.to_matrix().to_4x4() @ T(-center)
        for m in self.subtree(n): P[m] = R @ P[m]

    def ccd(self, P, chain, foot_bone, foot_loc, target, iters=60, tol=1e-6, w=None):
        """rotate chain bones (root->tip) about their heads until the point foot_loc (attached to foot_bone) hits target.
        Returns the remaining error (arm units)."""
        for it in range(iters):
            if ((P[foot_bone] @ foot_loc) - target).length < tol: break
            for k in range(len(chain) - 1, -1, -1):
                h = P[chain[k]].translation
                a = (P[foot_bone] @ foot_loc) - h; b = target - h
                if a.length < 1e-9 or b.length < 1e-9: continue
                q = a.rotation_difference(b)
                if w: q = Quaternion().slerp(q, w[k])
                self.rotate_subtree_q(P, chain[k], h, q)
        return ((P[foot_bone] @ foot_loc) - target).length


def new_action(arm, name):
    """replace the action `name` by an empty one bound to the armature (fake user so the exporter keeps it)"""
    old = bpy.data.actions.get(name)
    if old: old.name = name + "_old"
    act = bpy.data.actions.new(name); act.use_fake_user = True
    arm.animation_data.action = act
    return act


def write_clip(rig, name, frames_ch):
    """frames_ch: list (index = frame 0..N) of channel dicts -> Blender action `name` keyed on every bone every frame"""
    arm = rig.arm
    new_action(arm, name)
    pbs = arm.pose.bones
    for f, ch in enumerate(frames_ch):
        for n in rig.names:
            pb = pbs[n]; l, q, sc = ch[n]
            pb.location = l; pb.rotation_quaternion = q; pb.scale = sc
            pb.keyframe_insert('location', frame=f); pb.keyframe_insert('rotation_quaternion', frame=f); pb.keyframe_insert('scale', frame=f)


def export_anims(arm, mesh, path):
    for o in bpy.data.objects: o.select_set(o in (arm, mesh))
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True, export_format='GLB', export_image_format='JPEG', export_jpeg_quality=88,
        export_animation_mode='ACTIONS', export_skins=True, export_draco_mesh_compression_enable=False, export_apply=False,
        export_anim_single_armature=True, export_def_bones=False)


# ---- easing helpers for authoring
def smooth(t): t = max(0.0, min(1.0, t)); return t * t * (3 - 2 * t)
def ease_out(t): t = max(0.0, min(1.0, t)); return 1 - (1 - t) ** 3
def ease_in(t): t = max(0.0, min(1.0, t)); return t ** 3
def ease_snap(t): t = max(0.0, min(1.0, t)); return 1 - (1 - t) ** 2      # fast start, soft end (a strike)
def lerp(a, b, t): return a + (b - a) * t

def interp_keys(keys, t, ease=smooth):
    """keys: [(time, value[, ease_fn_for_the_segment_ending_here])]; values numeric or tuples."""
    if t <= keys[0][0]: return keys[0][1]
    for i in range(len(keys) - 1):
        t0, v0 = keys[i][0], keys[i][1]; t1, v1 = keys[i + 1][0], keys[i + 1][1]
        e = keys[i + 1][2] if len(keys[i + 1]) > 2 else ease
        if t <= t1:
            u = e((t - t0) / (t1 - t0)) if t1 > t0 else 1.0
            if isinstance(v0, (tuple, list)): return tuple(lerp(a, b, u) for a, b in zip(v0, v1))
            return lerp(v0, v1, u)
    return keys[-1][1]
