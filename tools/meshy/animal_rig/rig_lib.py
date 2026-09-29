"""Shared helpers for the farm-animal rigs: skeleton building, skinning, analytic 2-bone IK, clip authoring, GLB export.
Blender space: Z up, animals face -Y (glTF +Z, Godot forward)."""
import bpy, math, os, numpy as np
from mathutils import Vector, Quaternion, Matrix


def reset(fps=30):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = fps


def import_mesh(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    m = [o for o in new if o.type == 'MESH'][0]
    m.parent = None
    for o in new:
        if o is not m:
            bpy.data.objects.remove(o)
    bpy.context.view_layer.objects.active = m
    for o in bpy.data.objects:
        o.select_set(o == m)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return m


def verts_np(o):
    n = len(o.data.vertices)
    a = np.empty(n * 3)
    o.data.vertices.foreach_get('co', a)
    return a.reshape(n, 3)


def keep_verts(o, mask):
    """delete every vertex where mask is False"""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bm.verts.ensure_lookup_table()
    dele = [bm.verts[i] for i in range(len(bm.verts)) if not mask[i]]
    bmesh.ops.delete(bm, geom=dele, context='VERTS')
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()


def offset_mesh(o, dv, rz=0.0):
    M = Matrix.Translation(dv) @ Matrix.Rotation(rz, 4, 'Z')
    o.data.transform(M)
    o.data.update()


# ---------------------------------------------------------------- armature
def build_armature(name, bones):
    """bones: list of (name, parent|None, head, tail)."""
    arm_d = bpy.data.armatures.new(name)
    arm = bpy.data.objects.new(name, arm_d)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    for o in bpy.data.objects:
        o.select_set(o == arm)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = {}
    for n, p, h, t in bones:
        b = arm_d.edit_bones.new(n)
        b.head = Vector(h)
        b.tail = Vector(t)
        d = (b.tail - b.head).normalized()
        b.align_roll(Vector((0, 0, 1)) if abs(d.y) > 0.7 else Vector((0, 1, 0)))
        eb[n] = b
    for n, p, h, t in bones:
        if p:
            eb[n].parent = eb[p]
    bpy.ops.object.mode_set(mode='OBJECT')
    return arm


def skin(mesh, arm):
    for o in bpy.data.objects:
        o.select_set(False)
    mesh.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    bpy.ops.object.select_all(action='DESELECT')


def bone_seg(arm, name):
    b = arm.data.bones[name]
    return np.array(b.head_local), np.array(b.tail_local)


def dist_to_seg(P, a, b):
    ab = b - a
    t = np.clip(((P - a) @ ab) / max(ab @ ab, 1e-9), 0, 1)
    return np.linalg.norm(P - (a + t[:, None] * ab), axis=1)


def weights_np(mesh, arm):
    names = [b.name for b in arm.data.bones]
    idx = {n: i for i, n in enumerate(names)}
    W = np.zeros((len(mesh.data.vertices), len(names)))
    for v in mesh.data.vertices:
        for g in v.groups:
            n = mesh.vertex_groups[g.group].name
            if n in idx:
                W[v.index, idx[n]] = g.weight
    return W, names


def set_weights(mesh, W, names, topk=4):
    """W (n_verts x n_bones) -> vertex groups, normalised, top-k."""
    for vg in list(mesh.vertex_groups):
        mesh.vertex_groups.remove(vg)
    vgs = [mesh.vertex_groups.new(name=n) for n in names]
    for i in range(W.shape[0]):
        row = W[i].copy()
        if row.sum() <= 0:
            continue
        keep = np.argsort(-row)[:topk]
        r2 = np.zeros_like(row)
        r2[keep] = row[keep]
        r2 /= r2.sum()
        for j in keep:
            if r2[j] > 0.005:
                vgs[j].add([i], float(r2[j]), 'REPLACE')


def fill_orphans(mesh, arm):
    """vertices with no weight get inverse-distance weights to the 2 nearest bones"""
    W, names = weights_np(mesh, arm)
    P = verts_np(mesh)
    orphan = W.sum(1) < 1e-6
    print("orphan verts", int(orphan.sum()), "of", len(P))
    if orphan.any():
        D = np.stack([dist_to_seg(P[orphan], *bone_seg(arm, n)) for n in names], 1)
        for k, i in enumerate(np.where(orphan)[0]):
            j = np.argsort(D[k])[:2]
            w = 1 / (D[k, j] + 0.01) ** 2
            W[i, j] = w / w.sum()
        set_weights(mesh, W, names)


def report_weights(mesh, arm):
    W, names = weights_np(mesh, arm)
    tot = W.sum(1)
    print("weight coverage: min sum", tot.min().round(3), "verts with 0:", int((tot < 1e-6).sum()))
    for j, n in enumerate(names):
        print("  %-10s verts %5d  peak %.2f" % (n, int((W[:, j] > 0.3).sum()), W[:, j].max()))


# ---------------------------------------------------------------- posing
class Poser:
    def __init__(self, arm):
        self.arm = arm
        self.M = {}
        for b in arm.data.bones:
            self.M[b.name] = b.matrix_local.to_3x3()
            arm.pose.bones[b.name].rotation_mode = 'QUATERNION'
        self.state = {}

    def clear(self):
        self.state = {}

    def rot(self, bone, axis, ang_):
        """accumulate rotation of ang_ rad about the WORLD axis ('x','y','z') for bone"""
        ax = {'x': (1, 0, 0), 'y': (0, 1, 0), 'z': (0, 0, 1)}[axis]
        a = (self.M[bone].inverted() @ Vector(ax)).normalized()
        q = Quaternion(a, ang_)
        s = self.state.setdefault(bone, {})
        s['q'] = q @ s.get('q', Quaternion())

    def move(self, bone, dv):
        s = self.state.setdefault(bone, {})
        s['loc'] = s.get('loc', Vector()) + (self.M[bone].inverted() @ Vector(dv))

    def scale(self, bone, sc):
        self.state.setdefault(bone, {})['sc'] = Vector(sc) if hasattr(sc, '__len__') else Vector((sc, sc, sc))

    def apply(self):
        for b in self.arm.pose.bones:
            s = self.state.get(b.name, {})
            b.rotation_quaternion = s.get('q', Quaternion())
            b.location = s.get('loc', Vector())
            b.scale = s.get('sc', Vector((1, 1, 1)))
        bpy.context.view_layer.update()

    def head(self, bone):
        return Vector(self.arm.pose.bones[bone].head)

    def key(self, frame):
        for b in self.arm.pose.bones:
            b.keyframe_insert('rotation_quaternion', frame=frame)
            b.keyframe_insert('location', frame=frame)
            b.keyframe_insert('scale', frame=frame)


def ang(v):  # angle of (y,z) vector, increases with +X-axis rotation
    return math.atan2(v[1], v[0])


def wrap(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


class Leg2:
    """planar (Y,Z) two-bone IK: upper (hip->knee), lower (knee->ankle target point)"""

    def __init__(self, arm, upper, lower):
        self.u, self.l = upper, lower
        bu, bl = arm.data.bones[upper], arm.data.bones[lower]
        H, K, F = [np.array(v)[1:] for v in (bu.head_local, bu.tail_local, bl.tail_local)]
        self.H0, self.K0, self.F0 = H, K, F
        self.L1 = np.linalg.norm(K - H)
        self.L2 = np.linalg.norm(F - K)
        self.a1 = ang(K - H)
        self.a2 = ang(F - K)
        c = (K - H)[0] * (F - K)[1] - (K - H)[1] * (F - K)[0]
        self.bend = 1 if c >= 0 else -1

    def solve(self, poser, target_yz):
        H = np.array(poser.head(self.u))[1:]
        T = np.array(target_yz, float)
        d = T - H
        dist = np.linalg.norm(d)
        dist = min(max(dist, abs(self.L1 - self.L2) + 1e-3), self.L1 + self.L2 - 1e-3)
        a = math.acos(max(-1, min(1, (self.L1 ** 2 + dist ** 2 - self.L2 ** 2) / (2 * self.L1 * dist))))
        phiT = ang(d)
        for sgn in (1, -1):
            p1 = phiT + sgn * a
            K = H + self.L1 * np.array([math.cos(p1), math.sin(p1)])
            v1 = K - H
            v2 = T - K
            if (v1[0] * v2[1] - v1[1] * v2[0]) * self.bend >= 0:
                break
        p2 = ang(T - K)
        d1 = wrap(p1 - self.a1)
        d2 = wrap((p2 - p1) - (self.a2 - self.a1))
        poser.rot(self.u, 'x', d1)
        poser.rot(self.l, 'x', d2)
        return d1, d2


def smooth(x):
    return x * x * (3 - 2 * x)


def foot_cycle(p, duty, stride, lift):
    """gait phase p -> (dy along the forward axis, dz). stance moves backward linearly, swing arcs forward"""
    p %= 1.0
    if p < duty:
        return stride / 2 - stride * (p / duty), 0.0
    q = (p - duty) / (1 - duty)
    return -stride / 2 + stride * smooth(q), lift * math.sin(math.pi * q) ** 0.8


# ---------------------------------------------------------------- clips + export
def author_clip(arm, poser, name, nframes, fn):
    """fn(t01, frame) fills the poser; keys frames 0..nframes (last == first). Stored as an NLA strip named `name`."""
    ad = arm.animation_data or arm.animation_data_create()
    act = bpy.data.actions.new(name)
    ad.action = act
    try:
        if act.slots:
            ad.action_slot = act.slots[0]
    except Exception as e:
        print('slot', e)
    for f in range(nframes + 1):
        poser.clear()
        fn((f % nframes) / nframes, f)
        poser.apply()
        poser.key(f)
    act.use_fake_user = True
    ad.action = None
    tr = ad.nla_tracks.new()
    tr.name = name
    st = tr.strips.new(name, 0, act)
    try:
        if act.slots:
            st.action_slot = act.slots[0]
    except Exception:
        pass
    return act


def export_glb(mesh, arm, path):
    for o in bpy.data.objects:
        o.select_set(o in (mesh, arm))
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True, export_animations=True,
                              export_animation_mode='NLA_TRACKS', export_yup=True, export_apply=False,
                              export_skins=True, export_image_format='JPEG')


def _proxy_attempt(mesh, arm, voxel):
    px = mesh.copy()
    px.data = mesh.data.copy()
    px.name = 'proxy'
    bpy.context.scene.collection.objects.link(px)
    px.data.materials.clear()
    bpy.context.view_layer.objects.active = px
    for o in bpy.data.objects:
        o.select_set(o == px)
    m = px.modifiers.new('r', 'REMESH')
    m.mode = 'VOXEL'
    m.voxel_size = voxel
    bpy.ops.object.modifier_apply(modifier='r')
    for o in bpy.data.objects:
        o.select_set(False)
    px.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    cov = sum(1 for v in px.data.vertices if sum(g.weight for g in v.groups) > 0.5) / max(1, len(px.data.vertices))
    got = {px.vertex_groups[g.group].name for v in px.data.vertices for g in v.groups if g.weight > 0.2}
    return px, cov, got


def skin_via_proxy(mesh, arm, voxel):
    """Bone-heat fails on meshes made of many disconnected shells. Voxel-remesh a proxy copy (watertight), run
    Blender's automatic weights on it (retrying other voxel sizes until every bone got weights), then transfer the
    weights back to the real mesh by nearest surface."""
    nb = len(arm.data.bones)
    best = None
    for mult in (1.0, 0.75, 1.3, 0.6, 1.6, 0.5, 2.0):
        px, cov, got = _proxy_attempt(mesh, arm, voxel * mult)
        print("proxy voxel %.4f verts %d coverage %.2f bones weighted %d/%d" % (voxel * mult, len(px.data.vertices), cov, len(got), nb))
        if best is None or (len(got), cov) > best[0]:
            if best is not None:
                bpy.data.objects.remove(best[1])
            best = ((len(got), cov), px)
        else:
            bpy.data.objects.remove(px)
        if len(got) >= nb - int(os.environ.get("BONE_SLACK", 1)) and cov > 0.95:
            break
    px = best[1]
    for b in arm.data.bones:
        if b.name not in mesh.vertex_groups:
            mesh.vertex_groups.new(name=b.name)
    bpy.context.view_layer.objects.active = mesh
    for o in bpy.data.objects:
        o.select_set(o == mesh)
    dt = mesh.modifiers.new('dt', 'DATA_TRANSFER')
    dt.object = px
    dt.use_vert_data = True
    dt.data_types_verts = {'VGROUP_WEIGHTS'}
    dt.vert_mapping = 'POLYINTERP_NEAREST'
    dt.layers_vgroup_select_src = 'ALL'
    dt.layers_vgroup_select_dst = 'NAME'
    bpy.ops.object.modifier_apply(modifier='dt')
    bpy.data.objects.remove(px)
    mesh.parent = arm
    mesh.matrix_parent_inverse = arm.matrix_world.inverted()
    am = mesh.modifiers.new('Armature', 'ARMATURE')
    am.object = arm
