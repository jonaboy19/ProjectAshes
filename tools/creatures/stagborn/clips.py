"""Clip set for the Stagborn models: renames/retimes the stock Quaternius clips and authors the new ones
(attack = telegraphed antler gore, run_charge = head-down gallop, roar = rear-up telegraph for the Warden).
Authoring works in armature space: offsets are rotations about the armature X/Y/Z axes converted into each bone's local frame,
layered on a sampled base clip (idle / stock headbutt / gallop), then baked to keys. Hooves are ground-fixed per frame."""
import bpy, math, mathutils
from mathutils import Vector, Quaternion, Euler, Matrix

RENAME = {"Idle": "idle", "Idle_2": "idle_alt", "Eating": "graze", "Walk": "walk", "Gallop": "run",
          "Attack_Headbutt": "attack_butt", "Attack_Kick": "kick", "Idle_HitReact1": "hit", "Death": "death"}
KEEP = {"elk": {"idle", "idle_alt", "graze", "walk", "run", "run_charge", "attack", "attack_butt", "hit", "death"},
        "warden": {"idle", "idle_alt", "graze", "walk", "run", "run_charge", "attack", "attack_butt", "kick", "roar", "hit", "death"}}
TS = {"elk": 1.0, "warden": 1.25}     # heavier animal = slower cycles
HOOF = ["FrontLowerLeg.L", "FrontLowerLeg.R", "BackLowerLeg.L", "BackLowerLeg.R"]

def fcurves(a):
    return [f for l in a.layers for s in l.strips for cb in s.channelbags for f in cb.fcurves]

def retime(a, k):
    for fc in fcurves(a):
        for kp in fc.keyframe_points:
            kp.co.x *= k; kp.handle_left.x *= k; kp.handle_right.x *= k
        fc.update()

def ss(t):
    t = max(0.0, min(1.0, t)); return t * t * (3 - 2 * t)

def curve(keys, e):
    """piecewise smoothstep through (frame, value) keys; clamped outside"""
    if e <= keys[0][0]: return keys[0][1]
    for (f0, v0), (f1, v1) in zip(keys, keys[1:]):
        if e <= f1: return v0 + (v1 - v0) * ss((e - f0) / (f1 - f0))
    return keys[-1][1]

class Rig:
    def __init__(self, arm):
        self.arm = arm; self.sc = bpy.context.scene
        self.M3 = {b.name: b.matrix_local.to_3x3() for b in arm.data.bones}
        arm.animation_data_create(); arm.animation_data.action = None
        for pb in arm.pose.bones:
            pb.rotation_mode = "QUATERNION"; pb.location = (0, 0, 0); pb.rotation_quaternion = (1, 0, 0, 0); pb.scale = (1, 1, 1)
        self.rest_hoof = self._hoof_min()

    def _hoof_min(self):
        bpy.context.view_layer.update()
        return min(self.arm.pose.bones[h].tail.z for h in HOOF)

    def sample(self, action, frame):
        """pose of `action` at (fractional) frame -> {bone: (loc, quat, scale)}"""
        a = self.arm; a.animation_data.action = action
        if action.slots: a.animation_data.action_slot = action.slots[0]
        fi = int(math.floor(frame)); self.sc.frame_set(fi, subframe=frame - fi)
        return {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(), pb.scale.copy()) for pb in a.pose.bones}

    def rot_local(self, bone, rx=0.0, ry=0.0, rz=0.0):
        R = Euler((math.radians(rx), math.radians(ry), math.radians(rz)), 'XYZ').to_matrix()
        M = self.M3[bone]
        return (M.inverted() @ R @ M).to_quaternion()

    def loc_local(self, bone, vec):
        return self.M3[bone].inverted() @ Vector(vec)

def blend_pose(p0, p1, w):
    out = {}
    for k in p0:
        l0, q0, s0 = p0[k]; l1, q1, s1 = p1[k]
        out[k] = (l0.lerp(l1, w), q0.slerp(q1, w), s0.lerp(s1, w))
    return out

def apply_offsets(rig, pose, rot_offs, loc_offs, e):
    """rot_offs {bone: {'x': keys,'y':..,'z':..}} degrees ; loc_offs {bone: {'x','y','z': keys}} metres (armature space)"""
    out = {k: (v[0].copy(), v[1].copy(), v[2].copy()) for k, v in pose.items()}
    for b, ch in rot_offs.items():
        rx, ry, rz = (curve(ch[c], e) if c in ch else 0.0 for c in "xyz")
        if rx or ry or rz:
            l, q, s = out[b]; out[b] = (l, q @ rig.rot_local(b, rx, ry, rz), s)
    for b, ch in loc_offs.items():
        v = Vector([curve(ch[c], e) if c in ch else 0.0 for c in "xyz"])
        if v.length:
            l, q, s = out[b]; out[b] = (l + rig.loc_local(b, v), q, s)
    return out

def bake(rig, name, poses, ground=True, ground_fix_body="Body"):
    """poses: list of {bone:(loc,quat,scale)} per frame -> new action with keys on every frame"""
    D = bpy.data; arm = rig.arm
    arm.animation_data.action = None
    final = []
    for f, pose in enumerate(poses):
        for pb in arm.pose.bones:
            l, q, s = pose[pb.name]
            pb.location = l; pb.rotation_quaternion = q; pb.scale = s
        if ground:
            bpy.context.view_layer.update()
            dz = rig.rest_hoof - min(arm.pose.bones[h].tail.z for h in HOOF)
            pb = arm.pose.bones[ground_fix_body]; pb.location = pb.location + rig.loc_local(ground_fix_body, (0, 0, dz))
        final.append({pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(), pb.scale.copy()) for pb in arm.pose.bones})
    act = D.actions.new(name)
    arm.animation_data.action = act
    for f, pose in enumerate(final):
        for pb in arm.pose.bones:
            l, q, s = pose[pb.name]
            pb.location = l; pb.rotation_quaternion = q; pb.scale = s
            pb.keyframe_insert("location", frame=f); pb.keyframe_insert("rotation_quaternion", frame=f); pb.keyframe_insert("scale", frame=f)
    return act

def build(variant, arm):
    D = bpy.data; W = variant == "warden"; ts = TS[variant]; K = 1.5 if W else 1.0
    stock = {}
    for old, new in RENAME.items():
        a = D.actions.get(old)
        if a:
            a.name = new
            k = 1.25 * ts * (1.0 if new not in ("hit",) else 0.9 if W else 1.0)
            L0 = a.frame_range[1] - a.frame_range[0]
            if new in ("walk", "run", "idle", "idle_alt", "graze"):     # loops: whole number of frames so the seam is exact
                k = round(L0 * k) / L0
            retime(a, k); stock[new] = a
    rig = Rig(arm)
    for nm in ("walk", "run"):
        equalize_stance(rig, nm)
    lock_feet(rig, "walk")                       # planted hooves pinned (IK, baked): no slide
    stock["walk"] = D.actions["walk"]; stock["run"] = D.actions["run"]
    idle = stock["idle"]; idle_len = idle.frame_range[1] - idle.frame_range[0]
    def idle_at(f): return rig.sample(idle, (f % idle_len))

    # ---------------------------------------------------- attack: telegraph -> stock antler strike -> gore toss -> recover
    T0, T1 = 22, 24                # telegraph frames (elk-time); stock strike length
    butt = stock["attack_butt"]; b_len = 24 * ts * 1.25 / 1.25
    tele_rot = {
        "Neck1": {"x": [(0, 0), (6, 5), (14, 11), (22, 12)]}, "Neck2": {"x": [(0, 0), (6, 6), (14, 14), (22, 16)]},
        "Neck3": {"x": [(0, 0), (6, 8), (14, 18), (22, 20)]}, "Head": {"x": [(0, 0), (6, 12), (14, 30), (22, 42)],
                                                                    "z": [(0, 0), (12, 0), (14, -7), (17, 7), (20, -5), (22, 0)]},
        "Torso": {"x": [(0, 0), (10, -3), (22, -3)]},
        "FrontUpperLeg.L": {"x": [(0, 0), (4, 0), (7, -44), (11, 14), (14, -44), (18, 14), (22, 0)]},
        "FrontLowerLeg.L": {"x": [(0, 0), (4, 0), (7, 60), (11, 6), (14, 60), (18, 6), (22, 0)]},
        "Tail1": {"x": [(0, 0), (8, -12), (16, -6), (22, -14)]},
    }
    lean = 0.10 * K
    ang = math.degrees(math.asin(min(0.99, lean / (0.86 * K))))
    strike_rot = {
        "Neck1": {"x": [(8, 0), (11, -6), (14, -10), (20, -4), (24, 0)]}, "Neck2": {"x": [(8, 0), (11, -8), (14, -14), (20, -5), (24, 0)]},
        "Neck3": {"x": [(8, 0), (11, -10), (14, -17), (20, -6), (24, 0)]}, "Head": {"x": [(8, 0), (11, -14), (14, -26), (20, -8), (24, 0)]},
        "FrontUpperLeg.L": {"x": [(0, 0), (3, ang), (10, ang), (20, 0)]}, "FrontUpperLeg.R": {"x": [(0, 0), (3, ang), (10, ang), (20, 0)]},
    }
    strike_loc = {"Torso": {"y": [(0, 0), (3, -lean), (10, -lean), (20, 0)]}}
    n_att = int(round((T0 + T1 + 10) * ts))
    poses_att = []
    hold = None
    for f in range(n_att):
        e = f / ts
        if e < T0:
            p = apply_offsets(rig, idle_at(f), tele_rot, {}, e)
            hold = p
        elif e < T0 + T1:
            st = e - T0
            sp = rig.sample(butt, st * ts)
            p = blend_pose(hold, sp, ss(st / 6.0))
            p = apply_offsets(rig, p, strike_rot, strike_loc, st)
        else:
            k = (e - T0 - T1) / 10.0
            end_pose = apply_offsets(rig, rig.sample(butt, (T1) * ts), strike_rot, strike_loc, T1 - 0.01)
            p = blend_pose(end_pose, idle_at(f), ss(k))
        poses_att.append(p)
    bake(rig, "attack", poses_att)

    # ---------------------------------------------------- run_charge: gallop with the head down, antlers levelled at the target
    run = stock["run"]; rl = int(round(run.frame_range[1] - run.frame_range[0]))
    ch_rot = {"Neck1": {"x": [(0, 6)]}, "Neck2": {"x": [(0, 8)]}, "Neck3": {"x": [(0, 10)]}, "Head": {"x": [(0, 56)]}}
    poses = [apply_offsets(rig, rig.sample(run, f), ch_rot, {}, 0) for f in range(rl + 1)]
    bake(rig, "run_charge", poses)

    # ---------------------------------------------------- roar (Warden): crouch, rear up, head thrown back and shaken, slam down
    if W:
        R = {
            "Neck1": {"x": [(0, 0), (8, 6), (14, -8), (26, -20), (40, -18), (50, 6), (56, 0)]},
            "Neck2": {"x": [(0, 0), (8, 8), (14, -10), (26, -24), (40, -22), (50, 8), (56, 0)]},
            "Neck3": {"x": [(0, 0), (8, 8), (14, -12), (26, -26), (40, -24), (50, 8), (56, 0)]},
            "Head": {"x": [(0, 0), (8, 10), (14, -10), (26, -30), (40, -26), (50, 10), (56, 0)],
                     "z": [(24, 0), (27, 12), (30, -12), (33, 12), (36, -12), (39, 10), (42, -6), (45, 0)]},
            "Torso": {"x": [(0, 0), (8, 4), (26, -34), (40, -34), (48, 6), (52, -2), (56, 0)]},
            "Torso2": {"x": [(0, 0), (8, 3), (26, -8), (40, -8), (48, 3), (56, 0)]},
            "FrontUpperLeg.L": {"x": [(0, 0), (8, 6), (22, -38), (40, -38), (48, 10), (52, 0)]},
            "FrontUpperLeg.R": {"x": [(0, 0), (8, 6), (22, -30), (40, -34), (48, 10), (52, 0)]},
            "FrontLowerLeg.L": {"x": [(0, 0), (22, 62), (40, 66), (48, 0)]}, "FrontLowerLeg.R": {"x": [(0, 0), (22, 55), (40, 60), (48, 0)]},
            "BackUpperLeg.L": {"x": [(0, 0), (8, -4), (26, -10), (40, -10), (50, 0)]}, "BackUpperLeg.R": {"x": [(0, 0), (8, -4), (26, -10), (40, -10), (50, 0)]},
            "Tail1": {"x": [(0, 0), (26, 30), (40, 30), (52, 0)]},
        }
        for b in ("Neck1", "Neck2", "Neck3", "Head"):      # head throw-back reduced: the 3.3 m antlers no longer lie through the back
            R[b]["x"] = [(f, v * 0.5 if v < 0 else v) for f, v in R[b]["x"]]
        n_r = int(round(58 * ts)); poses = []
        for f in range(n_r):
            poses.append(apply_offsets(rig, idle_at(f), R, {}, f / ts))
        bake(rig, "roar", poses)
    mesh = [o for o in D.objects if o.type == 'MESH' and len(o.vertex_groups) > 5][0]
    for nm, lim in (("run_charge", 30.0), ("attack", 30.0)):     # antler tips must not dip below the ground
        if nm in D.actions: raise_antlers(rig, mesh, nm, lim)
    for nm in ("death", "walk", "run", "run_charge", "attack", "attack_butt", "kick", "roar"):
        if nm in D.actions: fix_floor(rig, mesh, nm, recenter=(nm == "death"))
    arm.animation_data.action = None
    return rig

def fix_floor(rig, mesh, nm, recenter=False):
    """lift the Body per frame so no part of the skinned mesh dips below the ground plane"""
    D = bpy.data; arm = rig.arm
    a = D.actions[nm]; f0 = a.frame_range[0]; n = int(round(a.frame_range[1] - f0)) + 1
    poses = [rig.sample(a, f0 + i) for i in range(n)]
    arm.animation_data.action = None
    out = []; cx0 = None
    for pose in poses:
        for pb in arm.pose.bones:
            l, q, s = pose[pb.name]; pb.location = l; pb.rotation_quaternion = q; pb.scale = s
        bpy.context.view_layer.update()
        ev = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()); me = ev.to_mesh()
        mz = min(v.co.z for v in me.vertices); cx = sum(v.co.x for v in me.vertices) / len(me.vertices); ev.to_mesh_clear()
        if cx0 is None: cx0 = cx
        dz = max(0.0, -mz); dx = (cx0 - cx) if recenter else 0.0
        l, q, s = pose["Body"]; pose = dict(pose); pose["Body"] = (l + rig.loc_local("Body", (dx, 0, dz)), q, s)
        out.append(pose)
    D.actions.remove(a)
    bake(rig, nm, out, ground=False)


LEGS = {"FL": ["FrontShoulder.L", "FrontUpperLeg.L", "FrontLowerLeg.L"], "FR": ["FrontShoulder.R", "FrontUpperLeg.R", "FrontLowerLeg.R"],
        "BL": ["BackShoulder.L", "BackLeg.L", "BackUpperLeg.L", "BackLowerLeg.L"], "BR": ["BackShoulder.R", "BackLeg.R", "BackUpperLeg.R", "BackLowerLeg.R"]}
HOOF_OF = {"FL": "FrontLowerLeg.L", "FR": "FrontLowerLeg.R", "BL": "BackLowerLeg.L", "BR": "BackLowerLeg.R"}

def _set_pose(rig, pose):
    for pb in rig.arm.pose.bones:
        l, q, s = pose[pb.name]; pb.location = l; pb.rotation_quaternion = q; pb.scale = s
    bpy.context.view_layer.update()

def stance_speeds(rig, poses):
    """implied ground speed of each hoof while it is planted (positive = backwards relative to the body)"""
    rows = []
    for pose in poses:
        _set_pose(rig, pose)
        rows.append({k: (rig.arm.pose.bones[h].tail.y, rig.arm.pose.bones[h].tail.z) for k, h in HOOF_OF.items()})
    out = {}
    for k in HOOF_OF:
        z0 = min(r[k][1] for r in rows); v = []
        for i in range(1, len(rows)):
            if rows[i][k][1] < z0 + 0.025 and rows[i - 1][k][1] < z0 + 0.025:
                v.append((rows[i][k][0] - rows[i - 1][k][0]) * 30.0)
        out[k] = sum(v) / len(v) if v else None
    return out

def scale_rot(q, f):
    ax, ang = q.to_axis_angle()
    if ang > math.pi: ang -= 2 * math.pi
    return Quaternion(ax, ang * f)

def foot_speed(rig, poses, k, f):
    """stance speed of hoof k when that leg's swing amplitude is scaled by f"""
    rows = []
    for pose in poses:
        pz = dict(pose)
        for bn in LEGS[k][1:]:
            l, q, sc_ = pz[bn]; pz[bn] = (l, scale_rot(q, f), sc_)
        _set_pose(rig, pz)
        pb = rig.arm.pose.bones[HOOF_OF[k]]; rows.append((pb.tail.y, pb.tail.z))
    z0 = min(r[1] for r in rows); v = []
    for i in range(1, len(rows)):
        if rows[i][1] < z0 + 0.025 and rows[i - 1][1] < z0 + 0.025:
            v.append((rows[i][0] - rows[i - 1][0]) * 30.0)
    return (sum(v) / len(v)) if v else None

def equalize_stance(rig, nm, grid=(0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95, 1.0, 1.05, 1.1, 1.15, 1.2, 1.3)):
    """pick, per leg, the swing-amplitude scale that brings its planted-hoof speed closest to the mean of the original four (less foot slide)"""
    D = bpy.data; arm = rig.arm
    a = D.actions[nm]; f0 = a.frame_range[0]; n = int(round(a.frame_range[1] - f0)) + 1
    poses = [rig.sample(a, f0 + i) for i in range(n)]
    arm.animation_data.action = None
    v0 = {k: foot_speed(rig, poses, k, 1.0) for k in LEGS}
    vals = [x for x in v0.values() if x]
    if not vals: return
    vt = sum(vals) / len(vals); best = {}
    for k in LEGS:
        if v0[k] is None: best[k] = 1.0; continue
        sc_ = []
        for f in grid:
            v = foot_speed(rig, poses, k, f)
            if v is not None: sc_.append((abs(v - vt), f, v))
        best[k] = min(sc_)[1]
    print("STANCE", nm, {k: round(x, 2) if x else None for k, x in v0.items()}, "target", round(vt, 2), "scales", best)
    for k, bones in LEGS.items():
        for pose in poses:
            for bn in bones[1:]:
                l, q, s = pose[bn]; pose[bn] = (l, scale_rot(q, best[k]), s)
    D.actions.remove(a)
    bake(rig, nm, poses, ground=False)

def raise_antlers(rig, mesh, nm, limit=45.0):
    """per frame, pitch the head up just enough that the antlers never dip below the ground"""
    D = bpy.data; arm = rig.arm; me = mesh.data
    hg = mesh.vertex_groups["Head"].index
    hv = [v.index for v in me.vertices if any(g.group == hg and g.weight > 0.9 for g in v.groups)]
    a = D.actions[nm]; f0 = a.frame_range[0]; n = int(round(a.frame_range[1] - f0)) + 1
    poses = [rig.sample(a, f0 + i) for i in range(n)]
    arm.animation_data.action = None
    out = []; fixed = 0
    for pose in poses:
        pose = dict(pose); tot = 0.0
        for it in range(20):
            _set_pose(rig, pose)
            ev = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get()); m = ev.to_mesh()
            mz = min(m.vertices[i].co.z for i in hv); ev.to_mesh_clear()
            if mz > -0.004 or tot >= limit: break
            step = min(3.0, max(1.0, -mz * 100 * 0.9)); tot += step
            l, q, s = pose["Head"]; pose["Head"] = (l, q @ rig.rot_local("Head", -step, 0, 0), s)
        if tot: fixed += 1
        out.append(pose)
    print("RAISE", nm, "frames adjusted", fixed, "of", n)
    D.actions.remove(a)
    bake(rig, nm, out, ground=False)


# ------------------------------------------------------------------------------------------------------------------
# Foot lock (walk): pin each planted hoof to the ground with a temporary IK constraint, baked back to FK keys.
IK_CHAIN = {"FL": 2, "FR": 2, "BL": 3, "BR": 3}      # bones counted from the hoof bone upwards

def _hoof_world(rig, pose):
    _set_pose(rig, pose)
    return {k: rig.arm.matrix_world @ rig.arm.pose.bones[h].tail for k, h in HOOF_OF.items()}

def _runs(flags):
    """contiguous True runs on a cyclic list -> list of index lists (each in cyclic order, starting inside the run)"""
    n = len(flags)
    if all(flags): return [list(range(n))]
    if not any(flags): return []
    s = next(i for i in range(n) if not flags[i])          # start scanning at a swing frame so no run wraps
    out, cur = [], []
    for j in range(1, n + 1):
        i = (s + j) % n
        if flags[i]: cur.append(i)
        elif cur: out.append(cur); cur = []
    if cur: out.append(cur)
    return out

def lock_feet(rig, nm, ramp=3, tol=0.045):
    """Planted hooves get a constant world position (in-place clip: they slide back at the clip's ground speed, exactly),
    blended in/out over `ramp` frames. Solved with IK constraints, then baked to FK keys (last frame duplicates the first for loops)."""
    D = bpy.data; arm = rig.arm
    a = D.actions[nm]; f0 = a.frame_range[0]; n = int(round(a.frame_range[1] - f0)) + 1
    poses = [rig.sample(a, f0 + i) for i in range(n)]
    arm.animation_data.action = None
    m = n - 1                                             # cycle length (last key == first key)
    hw = [_hoof_world(rig, p) for p in poses]
    speeds = stance_speeds(rig, poses)
    vals = [v for v in speeds.values() if v is not None]
    v_tgt = sum(vals) / len(vals)                        # signed mean stance speed = the gait's ground speed
    inv = arm.matrix_world.inverted()
    tgt = {k: [None] * m for k in LEGS}
    for k in LEGS:
        zs = [hw[i][k].z for i in range(m)]; z0 = min(zs)
        ysl = [hw[i][k].y for i in range(m)]
        vel = [(ysl[(i + 1) % m] - ysl[(i - 1) % m]) * 15.0 / v_tgt for i in range(m)]   # ~1 while the hoof moves like the ground
        flags = [z < z0 + tol and 0.4 < v < 2.2 for z, v in zip(zs, vel)]
        for i in range(m):                       # bridge short gaps (the stock clip skates the hoof forward 0.4 m in 2 frames mid-stance)
            if not flags[i] and zs[i] < z0 + 0.07:
                back = any(flags[(i - j) % m] for j in range(1, 4)); fwd = any(flags[(i + j) % m] for j in range(1, 4))
                if back and fwd: flags[i] = True
        for run in _runs(flags):
            # unwrap the run so the frame index grows monotonically
            idx = []; base = run[0]
            for r in run: idx.append(r if r >= base else r + m)
            mid = idx[len(idx) // 2]
            ys = [hw[i % m][k].y for i in idx]; xs = [hw[i % m][k].x for i in idx]
            ymean = sum(ys) / len(ys); xmean = sum(xs) / len(xs); imean = sum(idx) / len(idx)
            def lockpos(i, ymean=ymean, xmean=xmean, imean=imean, z0=z0):
                return mathutils.Vector((xmean, ymean + v_tgt * (i - imean) / 30.0, z0))
            for i in range(idx[0] - ramp, idx[-1] + ramp + 1):
                d = 0 if idx[0] <= i <= idx[-1] else min(abs(i - idx[0]), abs(i - idx[-1]))
                w = 1.0 if d == 0 else ss(1.0 - d / (ramp + 1.0))
                cur = tgt[k][i % m]
                base_p = hw[i % m][k]
                p = base_p.lerp(lockpos(i), w)
                if cur is None or w > cur[1]: tgt[k][i % m] = (p, w)
    empties = {}
    for k, h in HOOF_OF.items():
        e = bpy.data.objects.new("iktgt_" + k, None); bpy.context.scene.collection.objects.link(e); empties[k] = e
        c = arm.pose.bones[h].constraints.new('IK'); c.target = e; c.chain_count = IK_CHAIN[k]; c.iterations = 300; c.use_stretch = False
        c.name = "lockik"
    out = []
    for i in range(m):
        pose = poses[i]
        for pb in arm.pose.bones:
            l, q, s = pose[pb.name]; pb.location = l; pb.rotation_quaternion = q; pb.scale = s
        for k, e in empties.items():
            t = tgt[k][i]
            e.location = t[0] if t else hw[i][k]
        bpy.context.view_layer.update()
        newp = {}
        for pb in arm.pose.bones:
            if pb.name in HOOF_OF.values() or any(pb.name in LEGS[k] for k in LEGS):
                mb = arm.convert_space(pose_bone=pb, matrix=pb.matrix, from_space='POSE', to_space='LOCAL')
                loc, rot, sc_ = mb.decompose()
                q0 = pose[pb.name][1]
                if rot.dot(q0) < 0: rot = -rot
                newp[pb.name] = (loc, rot, sc_)
            else:
                newp[pb.name] = pose[pb.name]
        out.append(newp)
    for k, h in HOOF_OF.items():
        for c in list(arm.pose.bones[h].constraints):
            if c.name == "lockik": arm.pose.bones[h].constraints.remove(c)
        bpy.data.objects.remove(empties[k])
    out.append({kk: (v[0].copy(), v[1].copy(), v[2].copy()) for kk, v in out[0].items()})
    D.actions.remove(a)
    bake(rig, nm, out, ground=False)
    print("LOCKFEET", nm, "v_tgt", round(v_tgt, 3))
