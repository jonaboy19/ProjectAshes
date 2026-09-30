"""Procedural pose authoring for the Meshy 24-bone biped rig (Blender 5.2, run headless).

Everything is done in armature space (the imported rigs carry an object scale of ~0.0107, so
1 unit != 1 m; `U` converts metres to units). A clip is a list of pose KEYS (time in seconds
plus parameters relative to a base pose). Each frame the parameters are interpolated, an
FK pose is built from the base pose (hips/spine/head deltas), arms and legs are solved with an
analytic 2-bone IK (hands follow chest-relative targets, feet stay planted at the base pose)
and the result is baked to plain FK keys. No constraints are left in the file, the mesh is
never touched.

Conventions: body frame f (forward), r (character's right), z (up).
  pitch > 0 leans forward, yaw > 0 turns to the character's LEFT (CCW seen from above), roll > 0 leans right.
"""
import bpy, math, os, sys
from mathutils import Vector, Matrix, Quaternion, Euler


class Rig:
    def __init__(self, glb):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.context.scene.render.fps = 30
        bpy.ops.import_scene.gltf(filepath=os.path.abspath(glb))
        for o in list(bpy.data.objects):
            if o.type == 'MESH' and o.name.startswith('Icosphere'):
                bpy.data.objects.remove(o)
        self.arm = [o for o in bpy.data.objects if o.type == 'ARMATURE'][0]
        self.mesh = [o for o in bpy.data.objects if o.type == 'MESH'][0]
        self.arm.animation_data_create()
        self.s = self.arm.scale[0]
        self.U = 1.0 / self.s                      # metres -> armature units
        self.order = [b.name for b in self.arm.data.bones]
        self.par = {b.name: (b.parent.name if b.parent else None) for b in self.arm.data.bones}
        self.rest = {b.name: b.matrix_local.copy() for b in self.arm.data.bones}
        self.rel = {n: (self.rest[self.par[n]].inverted() @ self.rest[n]) if self.par[n] else self.rest[n] for n in self.order}
        self.len = {b.name: b.length for b in self.arm.data.bones}
        # head of the (first) child expressed in the bone's own frame: IK aims THIS vector, not the bone's Y axis
        self.cl = {}
        for b in self.arm.data.bones:
            kids = [c for c in b.children if c.name not in ('headfront', 'head_end')]
            if kids:
                self.cl[b.name] = self.rest[b.name].inverted() @ self.rest[kids[0].name].translation
        self.acts = {a.name.split('|')[-1]: a for a in bpy.data.actions}
        for a in self.acts.values():
            a.use_fake_user = True
        self.set_action('idle')
        bpy.context.scene.frame_set(1)
        M = self.pose_matrices()
        r = M['RightArm'].translation - M['LeftArm'].translation
        r.z = 0
        r.normalize()
        self.r = r
        self.z = Vector((0, 0, 1))
        self.f = self.z.cross(self.r).normalized()

    def set_action(self, name):
        a = self.acts[name]
        ad = self.arm.animation_data
        ad.action = a
        if a.slots:
            ad.action_slot = a.slots[0]
        return a

    def frames(self, name):
        a = self.acts[name]
        return int(round(a.frame_range[0])), int(round(a.frame_range[1]))

    def pose_matrices(self):
        bpy.context.view_layer.update()
        return {n: self.arm.pose.bones[n].matrix.copy() for n in self.order}

    def base_at(self, clip, frame):
        self.set_action(clip)
        bpy.context.scene.frame_set(frame)
        return self.pose_matrices()

    def basis_from(self, Mn):
        out = {}
        for n in self.order:
            p = self.par[n]
            B = ((Mn[p] @ self.rel[n]).inverted() @ Mn[n]) if p else (self.rel[n].inverted() @ Mn[n])
            out[n] = (B.to_translation(), B.to_quaternion().normalized())
        return out

    def mesh_minz(self):
        dg = bpy.context.evaluated_depsgraph_get()
        ev = self.mesh.evaluated_get(dg)
        me = ev.to_mesh()
        z = min((ev.matrix_world @ v.co).z for v in me.vertices)
        ev.to_mesh_clear()
        return z

    def group_verts(self, bone_names):
        gi = {vg.index for vg in self.mesh.vertex_groups if vg.name in bone_names}
        return [v.index for v in self.mesh.data.vertices if any(g.group in gi and g.weight > 0.35 for g in v.groups)]

    def apply_basis(self, fb):
        ad = self.arm.animation_data
        ad.action = None
        for n in self.order:
            pb = self.arm.pose.bones[n]
            loc, q = fb[n]
            pb.rotation_mode = 'QUATERNION'
            pb.location = loc
            pb.rotation_quaternion = q
            pb.scale = (1, 1, 1)
        bpy.context.view_layer.update()

    def verts_minz(self, idx):
        dg = bpy.context.evaluated_depsgraph_get()
        ev = self.mesh.evaluated_get(dg)
        me = ev.to_mesh()
        mw = ev.matrix_world
        z = min((mw @ me.vertices[i].co).z for i in idx)
        ev.to_mesh_clear()
        return z

    def replace_action(self, name, frames_basis, f0=1):
        """frames_basis: list (per frame) of {bone:(loc,quat)}; replaces action `name` with dense FK keys."""
        old = self.acts.get(name)
        if old is not None:
            old.use_fake_user = False
            old.name = name + "__old"
        act = bpy.data.actions.new(name)
        act.use_fake_user = True
        ad = self.arm.animation_data
        ad.action = act
        for i, fb in enumerate(frames_basis):
            f = f0 + i
            for n in self.order:
                pb = self.arm.pose.bones[n]
                loc, q = fb[n]
                pb.rotation_mode = 'QUATERNION'
                pb.location = loc
                pb.rotation_quaternion = q
                pb.scale = (1, 1, 1)
                pb.keyframe_insert('location', frame=f, group=n)
                pb.keyframe_insert('rotation_quaternion', frame=f, group=n)
        if old is not None:
            bpy.data.actions.remove(old)
        self.acts[name] = act
        if act.slots:
            ad.action_slot = act.slots[0]
        return act

    def export(self, path, jpeg=92):
        ad = self.arm.animation_data
        for t in list(ad.nla_tracks):
            ad.nla_tracks.remove(t)
        ad.action = None
        for name, a in self.acts.items():
            tr = ad.nla_tracks.new()
            tr.name = name
            st = tr.strips.new(name, int(round(a.frame_range[0])), a)
            if a.slots:
                st.action_slot = a.slots[0]
        for o in bpy.data.objects:
            o.select_set(o in (self.arm, self.mesh))
        bpy.context.view_layer.objects.active = self.arm
        bpy.ops.export_scene.gltf(filepath=os.path.abspath(path), use_selection=True, export_format='GLB',
                                  export_image_format='JPEG', export_jpeg_quality=jpeg, export_animation_mode='ACTIONS',
                                  export_skins=True, export_draco_mesh_compression_enable=False, export_apply=False,
                                  export_anim_single_armature=True, export_def_bones=False)
        print("EXPORTED", path, os.path.getsize(path) // 1024, "KB")


# ----------------------------------------------------------------------------- math helpers
def rot_about(M, p, q):
    return Matrix.Translation(p) @ q.to_matrix().to_4x4() @ Matrix.Translation(-p) @ M


def ydir(M):
    return M.to_3x3().col[1].normalized()


def axis_rot(axis, deg):
    return Quaternion(axis, math.radians(deg))


def ease(kind, u):
    u = max(0.0, min(1.0, u))
    if kind == 'lin':
        return u
    if kind == 'in':
        return u * u
    if kind == 'in3':
        return u * u * u
    if kind == 'out':
        return 1 - (1 - u) * (1 - u)
    if kind == 'snap':
        return u ** 4
    return u * u * (3 - 2 * u)


def two_bone_ik(Mn, b1, b2, target, pole_dir, c1, c2):
    """Rotate b1 (about its head) and b2 (about the elbow) so the END JOINT (head of b2's child) reaches target.
    c1 = child(b1).head in b1's local frame, c2 = child(b2).head in b2's local frame. Mn[b2] must already
    inherit b1's un-rotated pose."""
    l1, l2 = c1.length, c2.length
    A = Mn[b1].translation.copy()
    v = target - A
    D = v.length
    Dmin, Dmax = abs(l1 - l2) + 1e-3 * l1, (l1 + l2) * 0.9995
    Dc = max(Dmin, min(Dmax, D))
    u = v / max(D, 1e-9)
    a = (l1 * l1 - l2 * l2 + Dc * Dc) / (2 * Dc)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    n = pole_dir - u * pole_dir.dot(u)
    if n.length < 1e-6:
        n = Vector((0, 0, 1)) - u * u.z
    n.normalize()
    E = A + u * a + n * h
    T = A + u * Dc
    d1 = ((Mn[b1] @ c1) - A).normalized()
    q1 = d1.rotation_difference((E - A).normalized())
    Mn[b1] = rot_about(Mn[b1], A, q1)
    Mn[b2] = rot_about(Mn[b2], A, q1)
    d2 = ((Mn[b2] @ c2) - Mn[b2].translation).normalized()
    q2 = d2.rotation_difference((T - Mn[b2].translation).normalized())
    Mn[b2] = rot_about(Mn[b2], Mn[b2].translation.copy(), q2)


# ----------------------------------------------------------------------------- parameters
DEFAULT = dict(
    hips=(0, 0, 0),          # metres: forward, right, up (relative to base pose)
    hips_rot=(0, 0, 0),      # deg pitch/yaw/roll about the hips joint
    spine=(0, 0, 0),         # deg pitch/yaw/roll, spread over Spine02/Spine01/Spine
    head=(0, 0, 0),
    rhand=None, lhand=None,  # (fwd, right, up) in arm lengths from that shoulder; None = FK-follow
    rhand_rot=(0, 0, 0), lhand_rot=(0, 0, 0),   # wrist delta, deg, hand-local XYZ
    relbow=None, lelbow=None,  # elbow pole direction in the body frame; None = from base pose
    rfoot=(0, 0, 0), lfoot=(0, 0, 0),           # metres offset of the planted foot (fwd, right, up)
    rfoot_pitch=0.0, lfoot_pitch=0.0,
    tremble=0.0,             # metres, 10 Hz (3-frame period) shake on hands and hips
    shoulders=(0, 0),        # shrug deg (right, left), + raises
    grip=(0, 0, 1, 0.1),     # two-hand target: (fwd, right, up) from the mid-shoulder point (arm lengths) + hand spread
    gripw=0.0,               # 0 = hands follow rhand/lhand, 1 = both hands on the grip target
)
SPINE_W = (0.30, 0.30, 0.40)


def lerp_param(a, b, t):
    if a is None or b is None:
        return b if t >= 1.0 else a
    if isinstance(a, (int, float)):
        return a + (b - a) * t
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def expand_keys(keys, defaults=None):
    full = []
    cur = dict(DEFAULT)
    if defaults:
        cur.update(defaults)
    for k in keys:
        kt, kd = k[0], k[1]
        ke = k[2] if len(k) > 2 else 'smooth'
        cur = dict(cur)
        base = dict(DEFAULT)
        if defaults:
            base.update(defaults)
        for kk, vv in kd.items():
            cur[kk] = base[kk] if (isinstance(vv, str) and vv == 'BASE') else vv
        full.append((kt, cur, ke))
    return full


def state_at(full, t):
    if t <= full[0][0]:
        return full[0][1]
    for i in range(1, len(full)):
        t0, p0, _ = full[i - 1]
        t1, p1, e1 = full[i]
        if t <= t1:
            u = ease(e1, (t - t0) / max(t1 - t0, 1e-6))
            return {k: lerp_param(p0[k], p1[k], u) for k in p1}
    return full[-1][1]


def body_quat(rig, pyr):
    p, y, r = pyr
    return axis_rot(rig.z, y) @ axis_rot(rig.f, r) @ axis_rot(rig.r, -p)


def build_pose(rig, Mb, P, fi, opts):
    U = rig.U
    f, r, z = rig.f, rig.r, rig.z

    def body(v):
        return f * v[0] + r * v[1] + z * v[2]

    K = opts.get('K', 1.0)
    trem = P['tremble'] * K * U * math.sin(2 * math.pi * fi / 3.0)
    Mn = {}
    for n in rig.order:
        p = rig.par[n]
        M = Mb[n].copy() if p is None else (Mn[p] @ Mb[p].inverted() @ Mb[n])
        if n == 'Hips':
            d = body(P['hips']) * K * U + z * trem * 0.3
            M = rot_about(M, M.translation.copy(), body_quat(rig, P['hips_rot']))
            M = Matrix.Translation(d) @ M
        elif n in ('Spine02', 'Spine01', 'Spine'):
            w = SPINE_W[('Spine02', 'Spine01', 'Spine').index(n)]
            M = rot_about(M, M.translation.copy(), body_quat(rig, tuple(w * x for x in P['spine'])))
        elif n == 'Head':
            M = rot_about(M, M.translation.copy(), body_quat(rig, P['head']))
        elif n in ('RightShoulder', 'LeftShoulder'):
            a = P['shoulders'][0 if n[0] == 'R' else 1]
            if a:
                M = rot_about(M, M.translation.copy(), axis_rot(f, a if n[0] == 'R' else -a))
        Mn[n] = M
        for side, arm_n, fa_n in (('R', 'RightArm', 'RightForeArm'), ('L', 'LeftArm', 'LeftForeArm')):
            if n == fa_n:
                tgt = P['rhand' if side == 'R' else 'lhand']
                if tgt is not None:
                    A = Mn[arm_n].translation
                    l1 = rig.cl[arm_n].length
                    l2 = rig.cl[fa_n].length
                    T = A + body(tgt) * (l1 + l2)
                    gw = P['gripw']
                    if gw > 0:
                        hA = lambda nm: Mn['Spine'] @ Mb['Spine'].inverted() @ Mb[nm].translation
                        C = (hA('RightArm') + hA('LeftArm')) * 0.5
                        g = P['grip']
                        G = C + body((g[0], g[1] + (g[3] / 2 if side == 'R' else -g[3] / 2), g[2])) * (l1 + l2)
                        T = T * (1 - gw) + G * gw
                    T = T + r * (trem * (1 if side == 'R' else -1)) + z * trem * 0.7
                    T.z += opts.get('hand_lift', (0.0, 0.0))[0 if side == 'R' else 1] * U
                    fl = opts.get('hand_floor')
                    if fl is not None and T.z < fl * U:
                        T.z = fl * U
                    ep = P['relbow' if side == 'R' else 'lelbow']
                    if ep is not None:
                        pole = body(ep).normalized()
                    else:
                        A0 = Mb[arm_n].translation
                        E0 = Mb[fa_n].translation
                        W0 = Mb['RightHand' if side == 'R' else 'LeftHand'].translation
                        m = A0 + (W0 - A0) * ((E0 - A0).dot(W0 - A0) / (W0 - A0).length_squared)
                        pole = (E0 - m).normalized()
                    two_bone_ik(Mn, arm_n, fa_n, T, pole, rig.cl[arm_n], rig.cl[fa_n])
        for side, up_n, lg_n, ft_n in (('R', 'RightUpLeg', 'RightLeg', 'RightFoot'), ('L', 'LeftUpLeg', 'LeftLeg', 'LeftFoot')):
            if n == lg_n:
                A0 = Mb[up_n].translation
                K0 = Mb[lg_n].translation
                F0 = Mb[ft_n].translation
                m = A0 + (F0 - A0) * ((K0 - A0).dot(F0 - A0) / (F0 - A0).length_squared)
                pole = (K0 - m).normalized()
                T = F0 + body(P['rfoot' if side == 'R' else 'lfoot']) * K * U + z * opts.get('foot_dz', 0.0) * U
                two_bone_ik(Mn, up_n, lg_n, T, pole, rig.cl[up_n], rig.cl[lg_n])
            if n == ft_n:
                R = Mb[ft_n].to_3x3().to_4x4()
                pit = P['rfoot_pitch' if side == 'R' else 'lfoot_pitch']
                if pit:
                    R = axis_rot(r, -pit).to_matrix().to_4x4() @ R
                R.translation = Mn[ft_n].translation
                Mn[ft_n] = R
        if n in ('RightHand', 'LeftHand'):
            e = P['rhand_rot' if n[0] == 'R' else 'lhand_rot']
            if any(e):
                Mn[n] = Mn[n] @ Euler([math.radians(x) for x in e], 'XYZ').to_matrix().to_4x4()
    return Mn


def author_clip(rig, base_clip, base_frame, keys, duration, opts=None):
    """Return per-frame FK basis for a clip. duration seconds -> round(d*30)+1 frames."""
    opts = opts or {}
    Mb = rig.base_at(base_clip, base_frame)
    if 'foot_dz' not in opts:                       # plant the feet exactly on the floor (mesh min z = 0)
        opts['foot_dz'] = -rig.mesh_minz() if opts.get('ground_feet', True) else 0.0
    full = expand_keys(keys, base_defaults(rig, Mb))
    out = []
    hv = None
    if opts.get('hand_ground') is not None:
        hv = (rig.group_verts(('RightHand', 'RightForeArm')), rig.group_verts(('LeftHand', 'LeftForeArm')))
    for i in range(int(round(duration * 30)) + 1):
        P = state_at(full, i / 30.0)
        lift = [0.0, 0.0]
        o = dict(opts)
        for it in range(4 if hv else 1):
            o['hand_lift'] = tuple(lift)
            fb = rig.basis_from(build_pose(rig, Mb, P, i, o))
            if not hv:
                break
            rig.apply_basis(fb)
            gz = opts['hand_ground']
            errs = [gz - rig.verts_minz(hv[0]), gz - rig.verts_minz(hv[1])]
            if max(errs) < 0.004:
                break
            for k in (0, 1):
                if errs[k] > 0.004:
                    lift[k] += errs[k]
        out.append(fb)
    return out


def base_defaults(rig, Mb):
    """Hand targets / elbow poles of the base pose expressed in the body frame, so keys can start from 'as is'."""
    d = {}
    f, r, z = rig.f, rig.r, rig.z
    def comp(v):
        return (v.dot(f), v.dot(r), v.dot(z))
    for side, arm_n, fa_n, ha_n, key, ekey in (('R', 'RightArm', 'RightForeArm', 'RightHand', 'rhand', 'relbow'),
                                               ('L', 'LeftArm', 'LeftForeArm', 'LeftHand', 'lhand', 'lelbow')):
        A = Mb[arm_n].translation; E = Mb[fa_n].translation; W = Mb[ha_n].translation
        L = rig.cl[arm_n].length + rig.cl[fa_n].length
        d[key] = tuple(x / L for x in comp(W - A))
        m = A + (W - A) * ((E - A).dot(W - A) / (W - A).length_squared)
        pv = (E - m).normalized()
        d[ekey] = comp(pv)
    return d


REST = {k: 'BASE' for k in DEFAULT}   # every parameter back to the base pose


def ground_lift_clip(rig, name, clearance=0.005, cyclic=True):
    """Lift the Hips (whole body) just enough that no skinned vertex sinks below the floor (per frame, smoothed).
    Only translates Hips along +Z; everything else is inherited, so slip is unchanged."""
    f0, f1 = rig.frames(name)
    Mbs, need = [], []
    for f in range(f0, f1 + 1):
        Mbs.append(rig.base_at(name, f))
        need.append(max(0.0, -rig.mesh_minz() - clearance))
    n = len(need)
    core = need[:-1] if cyclic else need[:]
    for _ in range(3):
        m = len(core)
        if cyclic:
            core = [max(core[i], 0.25 * core[i - 1] + 0.5 * core[i] + 0.25 * core[(i + 1) % m]) for i in range(m)]
        else:
            core = [max(core[i], 0.25 * core[max(i - 1, 0)] + 0.5 * core[i] + 0.25 * core[min(i + 1, m - 1)]) for i in range(m)]
    lift = core + [core[0]] if cyclic else core
    out = []
    for Mb, d in zip(Mbs, lift):
        Mn = {}
        for b in rig.order:
            p = rig.par[b]
            M = Mb[b].copy() if p is None else (Mn[p] @ Mb[p].inverted() @ Mb[b])
            if b == 'Hips':
                M = Matrix.Translation(Vector((0, 0, d * rig.U))) @ M
            Mn[b] = M
        out.append(rig.basis_from(Mn))
    print("GROUNDLIFT", name, "max lift %.3f m" % max(lift))
    return out


def loop_close(rig, name, k=12):
    """Cross-blend the last k frames into frame 1 so frame 1 == last frame (no pop at the loop point)."""
    f0, f1 = rig.frames(name)
    fbs = [rig.basis_from(rig.base_at(name, f)) for f in range(f0, f1 + 1)]
    first = fbs[0]
    n = len(fbs)
    for i in range(n - k, n):
        u = (i - (n - k - 1)) / float(k)
        w = u * u * (3 - 2 * u)
        for b in rig.order:
            loc, q = fbs[i][b]
            l0, q0 = first[b]
            fbs[i][b] = (loc.lerp(l0, w), q.slerp(q0, w))
    return fbs


def inplace_clip(rig, name):
    """Remove the horizontal Hips travel (relative to frame 1) so the clip plays in place. The Meshy `hit` clips
    stagger 0.7-1.8 m and end displaced, which pops back to the collider when the clip finishes."""
    f0, f1 = rig.frames(name)
    Mbs = [rig.base_at(name, f) for f in range(f0, f1 + 1)]
    h0 = Mbs[0]['Hips'].translation.copy()
    out = []
    worst = 0.0
    for Mb in Mbs:
        d = Mb['Hips'].translation - h0
        d.z = 0.0
        worst = max(worst, d.length * rig.s)
        Mn = {}
        for b in rig.order:
            p = rig.par[b]
            M = Mb[b].copy() if p is None else (Mn[p] @ Mb[p].inverted() @ Mb[b])
            if b == 'Hips':
                M = Matrix.Translation(-d) @ M
            Mn[b] = M
        out.append(rig.basis_from(Mn))
    print("INPLACE", name, "removed up to %.2f m of travel" % worst)
    return out
