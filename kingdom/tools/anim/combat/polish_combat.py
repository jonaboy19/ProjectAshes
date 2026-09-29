# Polish / retime existing attack clips on the UAL skeleton (docs/anim/COMBAT_AUDIT.md).
#
#   blender -b -P polish_combat.py -- <spec.json> <out.glb> [clip,clip,...]
#   then: python ../glb_reduce_anim.py <out.glb>
#
# Every output frame is SAMPLED from the source action at a remapped time and edited in armature space,
# then baked to plain FK quaternion keys (+ pelvis / root location). Operations per clip (spec.json):
#   "retime":   [[dst_frame, src_frame, ease], ...]   piecewise time map (ease of the segment ARRIVING at the point:
#               lin | in | in2 | out | out2 | smooth | hold). Two points with the same src = an anticipation hold
#               (the pose keeps settling via "settle" below instead of freezing dead).
#   "settle":   [[a, b, amount], ...]  inside a hold, keep a slow drift toward the next pose (amount 0..1 of the
#               way to src at b+1), so the hold reads alive (a "moving hold").
#   "chain":    {"window": [a, b], "ramp": 3, "bones": {"pelvis": -2, "spine_01": -1, "upperarm_r": 1, ...}}
#               per-bone time offset in dst frames (negative = leads, positive = lags) inside the window:
#               successive breaking of joints (hips lead the shoulders lead the arm lead the wrist).
#   "overshoot":{"at": f, "rise": 2, "fall": 6, "amount": 0.6, "bones": [...]} continue each bone's angular velocity
#               at frame f past the end of the strike, then settle back (damped bump).
#   "twist":    {"curve": [[f, deg], ...], "keep": {"spine_01": 0.35, "spine_02": 0.7, "spine_03": 1.0}}
#               extra pelvis yaw (world up, + = turn to the character's left) with the chest kept (keep = fraction of
#               the chest's original world rotation restored per spine bone) and both feet LOCKED by 2-bone leg IK.
#   "hand_roll":{"curve": [[f, deg], ...]}  roll hand_r about the blade axis (edge alignment), blade axis from
#               "blade_axis_hand" (hand-bone-local unit vector, measured by combat_studio).
#   "trim":     [a, b]  output frame range kept (after the time map).
#   "mirror":   false
# Coordinates: Blender armature space, Z up, character faces -Y, +X = character's LEFT.
import bpy, sys, math, json, os
from mathutils import Vector, Quaternion, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
SPEC_PATH = os.path.abspath(argv[0])
OUT = os.path.abspath(argv[1])
ONLY = argv[2].split(",") if len(argv) > 2 else None
SPEC = json.load(open(SPEC_PATH))
HERE = os.path.dirname(os.path.abspath(__file__))
KINGDOM = os.path.normpath(os.path.join(HERE, "../../.."))
FPS = 30

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = FPS

# ------------------------------------------------------------------ load sources
SRC_ACTIONS = {}      # (glb, name) -> action
TGT = None


def res(p):
    return os.path.join(KINGDOM, p.replace("res://", "")) if p.startswith("res://") else p


def load_glb(path):
    global TGT
    before = set(bpy.data.actions)
    before_o = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=res(path))
    new_acts = [a for a in bpy.data.actions if a not in before]
    arms = [o for o in bpy.data.objects if o not in before_o and o.type == "ARMATURE"]
    for a in new_acts:
        nm = a.name
        # the importer names actions "<clip>" or "<clip>_<armature>"; strip a trailing armature suffix
        SRC_ACTIONS[(path, nm)] = a
    if TGT is None and arms:
        TGT = arms[0]
    for o in [o for o in bpy.data.objects if o not in before_o]:
        if o.type == "MESH":
            bpy.data.objects.remove(o)
        elif o.type == "ARMATURE" and o is not TGT:
            o.hide_set(True)


def find_action(path, name):
    for (p, n), a in SRC_ACTIONS.items():
        if p == path and (n == name or n.startswith(name + "_") and n[len(name) + 1:].lower().startswith("arm")):
            return a
    for (p, n), a in SRC_ACTIONS.items():
        if p == path and n.split("|")[-1] == name:
            return a
    raise KeyError(name + " in " + path + "; have " + ", ".join(n for (p, n) in SRC_ACTIONS if p == path))


needed = sorted({c["src_glb"] for c in SPEC["clips"] if not ONLY or c["name"] in ONLY})
for g in needed:
    load_glb(g)
tgt = TGT
tgt.animation_data_create()
for pb in tgt.pose.bones:
    pb.rotation_mode = "QUATERNION"
TB = tgt.data.bones
ORDER = []


def _walk(b):
    ORDER.append(b.name)
    for c in b.children:
        _walk(c)


for r in [b for b in TB if b.parent is None]:
    _walk(r)
PARENT = {n: (TB[n].parent.name if TB[n].parent else None) for n in ORDER}
L = {n: TB[n].matrix_local.copy() for n in ORDER}
LQ = {n: L[n].to_quaternion() for n in ORDER}
# rest rotation of each bone relative to its parent (armature space rest chain)
REL = {n: (LQ[PARENT[n]].inverted() @ LQ[n]) if PARENT[n] else LQ[n] for n in ORDER}


def assign(obj, act):
    obj.animation_data.action = act
    if act is not None and hasattr(obj.animation_data, "action_slot") and len(act.slots):
        obj.animation_data.action_slot = act.slots[0]


_cache = {}
_cur_act = [None]


class VSrc:
    """several source actions played back to back (e.g. Sword_Regular_A + Sword_Regular_A_Rec): segments
    [[action, start, end], ...] in source frames; the virtual timeline is their concatenation"""
    def __init__(self, segs):
        self.segs = segs
        self.name = "+".join(a.name for a, _, _ in segs)
        self.length = sum(e - s for _, s, e in segs)


def sample(act, t):
    if isinstance(act, VSrc):
        for a, s0, e0 in act.segs:
            L = e0 - s0
            if t <= L + 1e-6 or a is act.segs[-1][0]:
                return sample(a, s0 + min(max(t, 0.0), L))
            t -= L
    return _sample(act, t)


def _sample(act, t):
    """local basis (rotation quats, locations) of every bone at source frame t (float, relative to the action start)"""
    key = (act.name, round(t, 3))
    if key in _cache:
        return _cache[key]
    if _cur_act[0] is not act:
        assign(tgt, act)
        _cur_act[0] = act
        scene.frame_set(int(act.frame_range[1]) + 11)
    f = act.frame_range[0] + t
    fi = math.floor(f)
    scene.frame_set(int(fi), subframe=f - fi)
    out = {}
    for pb in tgt.pose.bones:
        out[pb.name] = (pb.rotation_quaternion.copy().normalized(), pb.location.copy())
    _cache[key] = out
    return out


def act_len(act):
    if isinstance(act, VSrc):
        return act.length
    return act.frame_range[1] - act.frame_range[0]

# ------------------------------------------------------------------ math helpers


def ease(kind, t):
    t = max(0.0, min(1.0, t))
    if kind == "lin":
        return t
    if kind == "in":
        return t * t * t
    if kind == "in2":
        return t * t
    if kind == "out":
        return 1 - (1 - t) ** 3
    if kind == "out2":
        return 1 - (1 - t) ** 2
    if kind == "hold":
        return 0.0 if t < 1.0 else 1.0
    return t * t * (3 - 2 * t)


def time_map(points, dst):
    """points [[dst, src, ease], ...] sorted by dst -> source frame"""
    if dst <= points[0][0]:
        return points[0][1] + (dst - points[0][0])
    for i in range(len(points) - 1):
        d0, s0 = points[i][0], points[i][1]
        d1, s1 = points[i + 1][0], points[i + 1][1]
        e = points[i + 1][2] if len(points[i + 1]) > 2 else "smooth"
        if d0 <= dst <= d1:
            return s0 + (s1 - s0) * ease(e, (dst - d0) / float(d1 - d0))
    return points[-1][1] + (dst - points[-1][0])


def curve(pts, f):
    if not pts:
        return 0.0
    if f <= pts[0][0]:
        return pts[0][1]
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        if a[0] <= f <= b[0]:
            e = b[2] if len(b) > 2 else "smooth"
            return a[1] + (b[1] - a[1]) * ease(e, (f - a[0]) / float(b[0] - a[0]))
    return pts[-1][1]


def window_w(f, win, ramp):
    a, b = win
    if f < a - ramp or f > b + ramp:
        return 0.0
    if f < a:
        return ease("smooth", (f - (a - ramp)) / max(ramp, 1e-6))
    if f > b:
        return 1.0 - ease("smooth", (f - b) / max(ramp, 1e-6))
    return 1.0


def fk(basis):
    """armature-space rotation and head position of every bone from local basis rotations/locations"""
    A = {}
    P = {}
    for n in ORDER:
        q, loc = basis[n]
        p = PARENT[n]
        if p is None:
            A[n] = LQ[n] @ q
            P[n] = L[n].translation + LQ[n] @ loc
        else:
            A[n] = A[p] @ REL[n] @ q
            # head offset from the parent head in the parent's rest frame, rotated by the parent's pose
            off = LQ[p].inverted() @ (L[n].translation - L[p].translation)
            P[n] = P[p] + A[p] @ (off + (REL[n] @ loc))
    return A, P


def to_basis(n, A, An):
    p = PARENT[n]
    if p is None:
        return LQ[n].inverted() @ An
    return (A[p] @ REL[n]).inverted() @ An


def yaw_q(deg):
    return Quaternion((0, 0, 1), math.radians(deg))


def bone_len(n):
    return (TB[n].tail_local - TB[n].head_local).length


def solve_leg(side, A, P, hip_pos, ankle_target, knee_hint, foot_rot):
    """analytic 2-bone IK in armature space: returns armature rotations for thigh, calf, foot"""
    th, ca, fo = "thigh_" + side, "calf_" + side, "foot_" + side
    l1 = (L[ca].translation - L[th].translation).length
    l2 = (L[fo].translation - L[ca].translation).length
    d = ankle_target - hip_pos
    dist = max(min(d.length, l1 + l2 - 1e-4), abs(l1 - l2) + 1e-4)
    dn = d.normalized()
    # knee angle via the law of cosines, bend plane from the hint
    cos_a = (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)
    a = math.acos(max(-1.0, min(1.0, cos_a)))
    hint = knee_hint - hip_pos
    side_v = dn.cross(hint).normalized()
    bend = side_v.cross(dn).normalized()
    knee = hip_pos + dn * (math.cos(a) * l1) + bend * (math.sin(a) * l1)
    # rotate the old thigh so its bone axis (+Y in bone space) points at the knee, keeping the twist minimal
    def aim(old_q, rest_head, rest_tail_dir_world, from_p, to_p):
        cur_dir = (old_q @ Vector((0, 1, 0))).normalized()
        want = (to_p - from_p).normalized()
        return cur_dir.rotation_difference(want) @ old_q
    thq = aim(A[th], None, None, hip_pos, knee)
    caq = aim(A[ca], None, None, knee, knee + (ankle_target - knee))
    return thq, caq, foot_rot

# ------------------------------------------------------------------ per-clip processing


def process(c):
    if "sources" in c:
        segs = []
        for nm, s0, e0 in c["sources"]:
            a = find_action(c["src_glb"], nm)
            segs.append((a, s0, e0 if e0 is not None else act_len(a)))
        src = VSrc(segs)
    else:
        src = find_action(c["src_glb"], c["src"])
    L0 = act_len(src)
    pts = c.get("retime") or [[0, 0, "lin"], [round(L0), L0, "lin"]]
    n_out = int(round(pts[-1][0]))
    if "trim" in c:
        a, b = c["trim"]
    else:
        a, b = 0, n_out
    chain = c.get("chain")
    ov = c.get("overshoot")
    tw = c.get("twist")
    hr = c.get("hand_roll")
    settle = c.get("settle", [])
    frames = []
    # angular velocity per bone at the overshoot frame (local basis delta per frame)
    ov_vel = {}
    if ov:
        f0 = ov["at"]
        s1 = sample(src, time_map(pts, f0))
        s0 = sample(src, time_map(pts, f0 - 1))
        for n in ov.get("bones", []):
            ov_vel[n] = s0[n][0].rotation_difference(s1[n][0])
    for f in range(a, b + 1):
        base_t = time_map(pts, f)
        for sa, sb, amt in settle:
            if sa <= f <= sb:
                nxt = time_map(pts, sb + 1)
                base_t = base_t + (nxt - base_t) * amt * (f - sa) / max(sb - sa, 1)
        base = sample(src, max(0.0, min(L0, base_t)))
        basis = dict(base)
        if chain:
            w = window_w(f, chain["window"], chain.get("ramp", 3))
            if w > 0:
                for n, off in chain["bones"].items():
                    t = time_map(pts, f - off * w)
                    basis[n] = (sample(src, max(0.0, min(L0, t)))[n][0], base[n][1] if n != "pelvis" else sample(src, max(0.0, min(L0, t)))[n][1])
        if ov:
            k = f - ov["at"]
            if 0 < k <= ov["rise"] + ov["fall"]:
                if k <= ov["rise"]:
                    amp = ease("out2", k / ov["rise"])
                else:
                    amp = 1.0 - ease("smooth", (k - ov["rise"]) / ov["fall"])
                amp *= ov["amount"] * ov["rise"]
                for n, dq in ov_vel.items():
                    ax, ang = dq.to_axis_angle()
                    extra = Quaternion(ax, ang * amp)
                    q, loc = basis[n]
                    basis[n] = ((q @ extra).normalized(), loc)
        if tw or hr:
            A0, P0 = fk(basis)
            A = dict(A0)
            if tw:
                deg = curve(tw["curve"], f)
                if abs(deg) > 1e-4:
                    R = yaw_q(deg)
                    A["pelvis"] = R @ A0["pelvis"]
                    # re-propagate: children keep their local basis except the kept spine and the legs
                    newb = dict(basis)
                    newb["pelvis"] = (to_basis("pelvis", A, A["pelvis"]), basis["pelvis"][1])
                    A1, P1 = fk(newb)
                    for sb_, frac in tw.get("keep", {}).items():
                        want = A1[sb_].slerp(A0[sb_], frac)
                        A1[sb_] = want
                        newb[sb_] = (to_basis(sb_, A1, want), basis[sb_][1])
                        A1, P1 = fk(newb)
                    # legs: keep ankles + foot rotation where they were
                    for side in ("l", "r"):
                        th, ca, fo = "thigh_" + side, "calf_" + side, "foot_" + side
                        knee_hint = P0[ca] + (A0[th] @ Vector((0, 0, 0.3)))
                        thq, caq, foq = solve_leg(side, A1, P1, P1[th], P0[fo], P0[ca] + (P0[ca] - (P0[th] + P0[fo]) * 0.5) * 2.0, A0[fo])
                        A1[th] = thq
                        newb[th] = (to_basis(th, A1, thq), basis[th][1])
                        A1, P1 = fk(newb)
                        A1[ca] = caq
                        # re-aim the calf from the solved knee to the ankle target
                        cur = (A1[ca] @ Vector((0, 1, 0))).normalized()
                        want = (P0[fo] - P1[ca]).normalized()
                        A1[ca] = cur.rotation_difference(want) @ A1[ca]
                        newb[ca] = (to_basis(ca, A1, A1[ca]), basis[ca][1])
                        A1, P1 = fk(newb)
                        A1[fo] = A0[fo]
                        newb[fo] = (to_basis(fo, A1, A0[fo]), basis[fo][1])
                        A1, P1 = fk(newb)
                    basis = newb
                    A, P = A1, P1
            if hr:
                deg = curve(hr["curve"], f)
                if abs(deg) > 1e-4:
                    A2, _ = fk(basis)
                    axis_local = (LQ["hand_r"].inverted() @ Vector((0, 0, 1))).normalized()   # rest blade is straight up (combat_studio --probe)
                    axis_w = (A2["hand_r"] @ axis_local).normalized()
                    want = Quaternion(axis_w, math.radians(deg)) @ A2["hand_r"]
                    basis["hand_r"] = (to_basis("hand_r", A2, want), basis["hand_r"][1])
        frames.append(basis)
    if c.get("auto_edge"):
        auto_edge(frames, c["auto_edge"])
    return frames


BLADE_AXIS_W = Vector((0, 0, 1))     # rest pose (T-pose) blade axis, world (combat_studio --probe)
BLADE_FLAT_W = Vector((0, -1, 0))    # rest pose blade flat normal, world


def auto_edge(frames, cfg):
    """roll hand_r about the blade axis so the blade's flat normal is perpendicular to the tip velocity (the edge leads)
    inside cfg["window"] (dst frames, ramp cfg.get("ramp", 2)), clamped to +-cfg.get("max_deg", 40), smoothed over 3 frames"""
    ax_l = (LQ["hand_r"].inverted() @ BLADE_AXIS_W).normalized()
    fl_l = (LQ["hand_r"].inverted() @ BLADE_FLAT_W).normalized()
    blen = cfg.get("blade_len", 0.85)
    tips, fk_cache = [], []
    for b in frames:
        A, P = fk(b)
        fk_cache.append((A, P))
        tips.append(P["hand_r"] + (A["hand_r"] @ ax_l) * blen)
    th = [0.0] * len(frames)
    for i in range(1, len(frames) - 1):
        w = window_w(i, cfg["window"], cfg.get("ramp", 2))
        if w <= 0:
            continue
        A, P = fk_cache[i]
        a = (A["hand_r"] @ ax_l).normalized()
        n = (A["hand_r"] @ fl_l).normalized()
        v = tips[i + 1] - tips[i - 1]
        vp = v - a * a.dot(v)
        if vp.length < 1e-4:
            continue
        nt = a.cross(vp).normalized()
        if nt.dot(n) < 0:
            nt = -nt
        ang = math.atan2(a.dot(n.cross(nt)), n.dot(nt))
        lim = math.radians(cfg.get("max_deg", 40))
        th[i] = max(-lim, min(lim, ang)) * w
    sm = [(th[max(i - 1, 0)] + 2 * th[i] + th[min(i + 1, len(th) - 1)]) / 4 for i in range(len(th))]
    for i, b in enumerate(frames):
        if abs(sm[i]) < 1e-5:
            continue
        A, P = fk(b)
        a = (A["hand_r"] @ ax_l).normalized()
        want = Quaternion(a, sm[i]) @ A["hand_r"]
        b["hand_r"] = (to_basis("hand_r", A, want), b["hand_r"][1])
    print("AUTO_EDGE max roll %.1f deg" % math.degrees(max((abs(x) for x in sm), default=0)))


def bake(name, frames):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    assign(tgt, act)
    _cur_act[0] = None
    pbs = tgt.pose.bones
    for i, basis in enumerate(frames):
        for n in ORDER:
            q, loc = basis[n]
            pbs[n].rotation_quaternion = q
            pbs[n].keyframe_insert("rotation_quaternion", frame=i)
            if n in ("root", "pelvis"):
                pbs[n].location = loc
                pbs[n].keyframe_insert("location", frame=i)
    assign(tgt, None)
    return act


if __name__ == "__main__":
    made = []
    report = []
    for c in SPEC["clips"]:
        if ONLY and c["name"] not in ONLY:
            continue
        fr = process(c)
        act = bake(c["name"], fr)
        made.append((c["name"], c.get("loop", False), act))
        report.append({"name": c["name"], "src": c.get("src") or "+".join(x[0] for x in c["sources"]), "frames": len(fr), "seconds": round((len(fr) - 1) / FPS, 3),
                       "note": c.get("note", "")})
        print("CLIP", c["name"], len(fr))
    assign(tgt, None)
    for pb in tgt.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
    for o in [o for o in bpy.data.objects if o is not tgt]:
        bpy.data.objects.remove(o)
    for a in [a for a in bpy.data.actions if a not in [m[2] for m in made]]:
        bpy.data.actions.remove(a)
    tgt.animation_data.action = None
    for tr in list(tgt.animation_data.nla_tracks):
        tgt.animation_data.nla_tracks.remove(tr)
    me = bpy.data.meshes.new("UAL_Skin_Stub")
    me.from_pydata([(0, 0, 0.9), (0.01, 0, 0.9), (0, 0.01, 0.9)], [], [(0, 1, 2)])
    ob = bpy.data.objects.new("UAL_Skin_Stub", me)
    scene.collection.objects.link(ob)
    ob.parent = tgt
    vg = ob.vertex_groups.new(name="pelvis")
    vg.add([0, 1, 2], 1.0, "REPLACE")
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = tgt
    tgt.name = "Armature"
    tgt.hide_set(False)
    for name, loop, a in made:
        tr = tgt.animation_data.nla_tracks.new()
        tr.name = name + ("_Loop" if loop else "")
        tr.strips.new(tr.name, 0, a)
    bpy.ops.object.select_all(action="DESELECT")
    tgt.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = tgt
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_force_sampling=False,
                              export_optimize_animation_size=False, export_draco_mesh_compression_enable=False,
                              export_materials="NONE", export_apply=False, export_yup=True, export_def_bones=False,
                              export_anim_single_armature=True, export_reset_pose_bones=True)
    json.dump(report, open(OUT + ".clips.json", "w"), indent=1)
    print("EXPORTED", OUT, len(made))
