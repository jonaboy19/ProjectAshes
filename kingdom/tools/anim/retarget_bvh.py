# retarget_bvh.py = retarget_clips_to_ual.py + the options used by the free clip library
# (kingdom/assets/incoming/animations_free): per-clip "mirror" (left/right flip of a take),
# and "fast_preview" (sample only every 30 fps frame, no smoothing; for browsing raw takes).
#
# Retarget humanoid clips (BVH mocap files, or actions inside a rigged .blend)
# onto the Quaternius UAL 65-bone skeleton and export one UAL clip-library GLB
# that can be appended to Assets.UAL_FILES (scripts/world/assets.gd).
#
# Same method as assets/incoming/characters/_tools/retarget_to_ual.py
# (direction-matched rest, world-space rotation deltas, parents first), plus:
#   * BVH sources (one armature per file), rigged .blend sources whose deform
#     bones are driven by IK/FK control rigs (constraints kept live),
#   * per-clip trim ranges (seconds), auto-trim of idle head/tail frames,
#   * light Gaussian smoothing at the source rate, then resampling to 30 fps,
#   * true in-place clips: the pelvis keeps only the sway around a smoothed
#     travel path; the travel itself goes on the `root` bone (an optional
#     root-motion track - Assets._ual_for disables it, see README),
#   * floor fix (lowest planted foot = UAL rest foot height),
#   * loop clips: best loop points + 0.25 s crossfade, last frame == first,
#   * constant finger poses sampled from a UAL clip (mocap has no fingers),
#   * Douglas-Peucker keyframe reduction, exported without resampling.
#
# usage (bpy wheel):   python retarget_clips_to_ual.py <config.json>
#        (Blender):    blender -b --python retarget_clips_to_ual.py -- <config.json>
# Paths in the config are relative to the config file.
import bpy, sys, json, re, os, math
import numpy as np
from mathutils import Matrix, Quaternion, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
CFG_PATH = os.path.abspath(argv[0])
cfg = json.load(open(CFG_PATH, encoding="utf-8"))
BASE = os.path.dirname(CFG_PATH)
def P(p):
    p = os.path.expandvars(p)
    return p if os.path.isabs(p) else os.path.normpath(os.path.join(BASE, p))

FPS = 30
ROT_TOL = math.radians(cfg.get("rot_tolerance_deg", 0.3))
POS_TOL = cfg.get("pos_tolerance_m", 0.002)
bmap = cfg["map"]                      # ual bone -> source bone
no_match = set(cfg.get("no_match", ["pelvis"]))
src_type = cfg["source_type"]          # "bvh" | "blend"

# ---------------------------------------------------------------- scene setup
if src_type == "blend":
    bpy.ops.wm.open_mainfile(filepath=P(cfg["blend"]))
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
src_actions = list(bpy.data.actions)
before = set(bpy.data.objects)
before_actions = set(bpy.data.actions)
bpy.ops.import_scene.gltf(filepath=P(cfg["ual"]))
new_objs = [o for o in bpy.data.objects if o not in before]
tgt = [o for o in new_objs if o.type == "ARMATURE"][0]
ual_actions = {a.name: a for a in bpy.data.actions if a not in before_actions}
tgt.animation_data_create()
for pb in tgt.pose.bones:
    pb.rotation_mode = "QUATERNION"
tb = tgt.data.bones
order = []
def walk(b):
    order.append(b.name)
    for c in b.children:
        walk(c)
for r in [b for b in tb if b.parent is None]:
    walk(r)
IDX = {n: i for i, n in enumerate(order)}
FINGER = [n for n in order if re.match(r"(thumb|index|middle|ring|pinky)_0[123]_[lr]$", n)]

def assign(obj, act):
    obj.animation_data.action = act
    if act is not None and hasattr(obj.animation_data, "action_slot") and len(act.slots):
        obj.animation_data.action_slot = act.slots[0]

# finger poses sampled from UAL clips: {"fist": ["Punch_Jab", 0.4]} (clip, fraction)
finger_pose = {}
for key, (clip, frac) in cfg.get("finger_poses", {}).items():
    act = ual_actions[clip]
    assign(tgt, act)
    f0, f1 = act.frame_range
    scene.frame_set(int(round(f0 + (f1 - f0) * frac)))
    finger_pose[key] = {n: tgt.pose.bones[n].rotation_quaternion.copy() for n in FINGER}
assign(tgt, None)
for a in ual_actions.values():
    bpy.data.actions.remove(a)
for tr in list(tgt.animation_data.nla_tracks):
    tgt.animation_data.nla_tracks.remove(tr)
tgt.name = "Armature"
scene.render.fps = FPS
scene.render.fps_base = 1.0

tgt_mw = tgt.matrix_world.copy()
tgt_mw_rot = tgt_mw.to_quaternion()
rest_t = {n: tgt_mw_rot @ tb[n].matrix_local.to_quaternion() for n in order}
L = {n: tb[n].matrix_local.copy() for n in order}
Linv = {n: L[n].inverted() for n in order}
tp = tgt_mw @ tb["pelvis"].head_local
t_foot_rest = (tgt_mw @ tb["foot_l"].head_local).z
t_ball_rest = (tgt_mw @ tb["ball_l"].head_local).z
t_leg = tp.z - t_foot_rest

def world_dir(arm, mw, name):
    b = arm.data.bones[name]
    return ((mw @ b.tail_local) - (mw @ b.head_local)).normalized()

def swap_lr(name):
    if name.startswith("Left"): return "Right" + name[4:]
    if name.startswith("Right"): return "Left" + name[5:]
    return name

def rq(q, mirror):
    """Reflect a world rotation across the character's sagittal plane (x -> -x)."""
    return Quaternion((q.w, q.x, -q.y, -q.z)) if mirror else q

# --------------------------------------------------------------- retarget core
class Rig:
    """Per source armature: facing yaw, direction-matched target rest, scale."""
    def __init__(self, src, mirror=False):
        self.src = src
        self.mirror = mirror
        self.ye = Quaternion()          # extra heading (yaw about vertical), set per clip
        self.smap = {n: (swap_lr(v) if mirror else v) for n, v in bmap.items()}
        self.smap_raw = bmap
        mw = src.matrix_world.copy()
        self.mw, self.mw_rot = mw, mw.to_quaternion()
        sb = src.data.bones
        def facing(arm, foot, ball, m):
            d = (m @ arm.data.bones[ball].head_local) - (m @ arm.data.bones[foot].head_local)
            d.z = 0
            return d.normalized()
        fs = facing(src, bmap["foot_l"], bmap["ball_l"], mw)
        ft = facing(tgt, "foot_l", "ball_l", tgt_mw)
        self.yaw = fs.rotation_difference(ft)
        self.matched = {}
        for n in order:
            b = tb[n]
            s = self.smap.get(n)
            if s and s in sb and n not in no_match and "leaf" not in n:
                dt = world_dir(tgt, tgt_mw, n)
                ds = self.yaw @ world_dir(src, mw, s)
                if mirror:
                    ds = Vector((-ds.x, ds.y, ds.z))
                self.matched[n] = dt.rotation_difference(ds) @ rest_t[n]
            elif s and s in sb:
                self.matched[n] = rest_t[n]
            elif b.parent is not None:
                p = b.parent.name
                self.matched[n] = self.matched[p] @ (rest_t[p].inverted() @ rest_t[n])
            else:
                self.matched[n] = rest_t[n]
        self.src_rest_inv = {s: rq(self.yaw @ self.mw_rot @ sb[s].matrix_local.to_quaternion(), mirror).inverted()
                             for s in self.smap.values() if s in sb}
        missing = [s for s in self.smap.values() if s not in sb]
        if missing:
            print("WARNING source bones missing:", missing)
        sp = mw @ sb[bmap["pelvis"]].head_local
        sf = mw @ sb[bmap["foot_l"]].head_local
        self.k = t_leg / (sp.z - sf.z)
        if cfg.get("scale_mode") == "height" and "Head" in bmap and bmap["Head"] in sb:
            # source with unlike proportions (chibi KayKit: short legs, long torso): scale the
            # pelvis travel by overall stature (foot -> head) instead of leg length
            sh = mw @ sb[bmap["Head"]].head_local
            th = (tgt_mw @ tb["Head"].head_local).z
            self.k = (th - t_foot_rest) / (sh.z - sf.z)
        self.pelvis_src = bmap["pelvis"]

    def sample(self, frame):
        """Target local quats [nbones,4] (w,x,y,z) and pelvis world pos (scaled, yawed)."""
        scene.frame_set(frame)
        spb = self.src.pose.bones
        want = {}
        for n in order:
            b = tb[n]
            s = self.smap.get(n)
            if s in self.src_rest_inv:
                cur = self.ye @ rq(self.yaw @ self.mw_rot @ spb[s].matrix.to_quaternion(), self.mirror)
                want[n] = cur @ self.src_rest_inv[s] @ self.matched[n]
            elif b.parent is not None:
                p = b.parent.name
                want[n] = want[p] @ (self.matched[p].inverted() @ self.matched[n])
            else:
                want[n] = rest_t[n]
        q = np.zeros((len(order), 4))
        inv_mw = tgt_mw_rot.inverted()
        for i, n in enumerate(order):
            b = tb[n]
            m_b = inv_mw @ want[n]
            rest_b = b.matrix_local.to_quaternion()
            if b.parent is not None:
                m_p = inv_mw @ want[b.parent.name]
                qq = rest_b.inverted() @ b.parent.matrix_local.to_quaternion() @ m_p.inverted() @ m_b
            else:
                qq = rest_b.inverted() @ m_b
            qq.normalize()
            q[i] = (qq.w, qq.x, qq.y, qq.z)
        sw = self.yaw @ (self.mw @ spb[self.pelvis_src].head)
        if self.mirror:
            sw = Vector((-sw.x, sw.y, sw.z))
        sw = self.ye @ sw
        return q, np.array(sw) * self.k

def continuity(Q):
    """Flip quaternion signs so consecutive frames stay on one hemisphere."""
    for t in range(1, len(Q)):
        d = np.sum(Q[t] * Q[t - 1], axis=-1)
        Q[t][d < 0] *= -1
    return Q

def gauss(x, sigma):
    if sigma <= 0.05:
        return x.copy()
    r = int(math.ceil(3 * sigma))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    pad = np.concatenate([np.repeat(x[:1], r, 0), x, np.repeat(x[-1:], r, 0)], 0)
    out = np.zeros_like(x)
    for i, w in enumerate(k):
        out += w * pad[i:i + len(x)]
    return out

def norm_q(Q):
    return Q / np.linalg.norm(Q, axis=-1, keepdims=True)

def qangle(a, b):
    d = np.clip(np.abs(np.sum(a * b, axis=-1)), 0, 1)
    return 2 * np.arccos(d)

MAPPED_IDX = [IDX[n] for n in order if n in bmap]

def energy(Q, fps):
    """Per-frame angular speed summed over mapped bones (rad/s)."""
    e = np.zeros(len(Q))
    e[1:] = qangle(Q[1:, MAPPED_IDX], Q[:-1, MAPPED_IDX]).sum(1) * fps
    e[0] = e[1] if len(e) > 1 else 0
    return gauss(e[:, None], 3)[:, 0]

# FK for floor/QA: armature-space head positions of a few bones.
def fk_heads(q, loc_pelvis, loc_root, names):
    mats = {}
    out = {}
    for n in order:
        b = tb[n]
        qq = q[IDX[n]]
        basis = Quaternion((qq[0], qq[1], qq[2], qq[3])).to_matrix().to_4x4()
        if n == "pelvis":
            basis = Matrix.Translation(Vector(loc_pelvis)) @ basis
        if n == "root":
            basis = Matrix.Translation(Vector(loc_root)) @ basis
        if b.parent is None:
            m = L[n] @ basis
        else:
            p = b.parent.name
            if p not in mats:
                continue
            m = mats[p] @ (Linv[p] @ L[n]) @ basis
        mats[n] = m
        if n in names:
            out[n] = (tgt_mw @ m).translation.copy()
        if len(out) == len(names):
            break
    return out

# ------------------------------------------------------------------- per clip
CONTACT_BONES = [n for n in order if n != "root" and "leaf" not in n]
# joint centre height that means "touching the floor" (skin thickness below the joint)
CONTACT_MARGIN = {"foot_l": 0.035, "foot_r": 0.035, "ball_l": -0.005, "ball_r": -0.005}
for n in CONTACT_BONES:
    if re.match(r"(thumb|index|middle|ring|pinky)_0[23]", n):
        CONTACT_MARGIN[n] = 0.005
def bake_clip(rig, f_start, f_end, step, clip):
    fast = clip.get("fast_preview", cfg.get("fast_preview", False))
    frames = list(range(f_start, f_end + 1, step if fast else 1))
    Qs, Ps = [], []
    for f in frames:
        q, p = rig.sample(f)
        Qs.append(q); Ps.append(p)
    Q = continuity(np.array(Qs))
    Pw = np.array(Ps)
    src_fps = FPS * step
    # light smoothing at the source rate (mocap jitter), then resample
    sig = 0 if fast else clip.get("smooth", cfg.get("smooth", 0.0)) * src_fps
    if sig > 0:
        Q = norm_q(gauss(Q.reshape(len(Q), -1), sig).reshape(Q.shape))
        Pw = gauss(Pw, sig)
    if not fast:
        Q = Q[::step]; Pw = Pw[::step]
    # auto-trim still head/tail
    if clip.get("autotrim", False) and len(Q) > 20:
        e = energy(Q, FPS)
        thr = max(0.15 * np.percentile(e, 90), 0.4)
        act = np.where(e > thr)[0]
        if len(act):
            a = max(0, act[0] - 6); b = min(len(Q), act[-1] + 7)
            Q, Pw = Q[a:b], Pw[a:b]
            clip["_autotrim"] = [round(a / FPS, 2), round(b / FPS, 2)]
    # fingers
    fp = clip.get("fingers", cfg.get("fingers"))
    if fp in finger_pose:
        for n, qq in finger_pose[fp].items():
            Q[:, IDX[n]] = (qq.w, qq.x, qq.y, qq.z)
    Q = continuity(Q)
    # travel -> root (optional track); pelvis keeps sway only
    mode = clip.get("inplace", cfg.get("inplace", "smooth"))
    H = Pw[:, :2].copy()
    if mode == "linear":
        tt = np.linspace(0, 1, len(H))[:, None]
        traj = H[:1] + (H[-1:] - H[:1]) * tt
    elif mode == "full":
        traj = H.copy()
    elif mode == "none":
        traj = np.repeat(H[:1], len(H), 0)
    else:
        traj = gauss(H, clip.get("inplace_sigma", 0.3) * FPS)
    sway = H - traj
    root_xy = traj - traj[0]
    pel = np.zeros_like(Pw)
    pel[:, 0] = tp.x + sway[:, 0]
    pel[:, 1] = tp.y + sway[:, 1]
    pel[:, 2] = Pw[:, 2]
    # center: remove the mean sway offset so the body stands over the origin
    pel[:, 0] -= np.mean(sway[:, 0]); pel[:, 1] -= np.mean(sway[:, 1])
    # floor: lowest planted foot at the UAL rest foot height
    floor = clip.get("floor", cfg.get("floor", "auto"))
    fix = 0.0
    def locs(t):
        lp = Linv["pelvis"] @ (tgt_mw.inverted() @ Vector(pel[t]))
        lr = L["root"].to_3x3().inverted() @ Vector((root_xy[t, 0], root_xy[t, 1], 0.0))
        return lp, lr
    feet = ["foot_l", "foot_r", "ball_l", "ball_r"]
    if floor != "none":
        g = []
        for t in range(len(Q)):
            lp, _ = locs(t)
            h = fk_heads(Q[t], lp, (0, 0, 0), feet)
            gl = min(h["foot_l"].z - t_foot_rest, h["foot_r"].z - t_foot_rest,
                     h["ball_l"].z - t_ball_rest, h["ball_r"].z - t_ball_rest)
            standing = pel[t, 2] > 0.7 * tp.z
            g.append((gl, standing))
        gs = np.array([x[0] for x in g if x[1]])
        if floor == "min":
            gs = np.array([x[0] for x in g])
        if len(gs) >= 3:
            fix = -float(np.percentile(gs, 5))
            lim = clip.get("floor_limit", 0.2)
            fix = max(-lim, min(lim, fix))
            pel[:, 2] += fix
    # loop: pick loop points and crossfade
    if clip.get("loop") and not clip.get("loop_native"):
        n = len(Q)
        W = int(clip.get("loop_search", 0.6) * FPS)
        F = int(clip.get("loop_blend", 0.25) * FPS)
        minlen = int(clip.get("loop_min", 1.0) * FPS)
        best = None
        for s in range(F, min(F + W, n - minlen)):
            for e in range(max(s + minlen, n - W), n):
                qa = Q[s, MAPPED_IDX]; qb = Q[e, MAPPED_IDX]
                d = qangle(qa, qb).sum() + abs(pel[s, 2] - pel[e, 2]) * 20 + np.linalg.norm(sway[s] - sway[e]) * 20
                if best is None or d < best[0]:
                    best = (d, s, e)
        if best:
            _, s, e = best
            for j in range(F):
                w = (j + 1) / F
                w = w * w * (3 - 2 * w)
                a_i, b_i = e - F + j, s - F + j
                qa, qb = Q[a_i], Q[b_i].copy()
                dots = np.sum(qa * qb, -1); qb[dots < 0] *= -1
                Q[a_i] = norm_q(qa * (1 - w) + qb * w)
                pel[a_i] = pel[a_i] * (1 - w) + pel[b_i] * w
            Q = np.concatenate([Q[s:e], Q[s:s + 1]], 0)
            pel = np.concatenate([pel[s:e], pel[s:s + 1]], 0)
            root_xy = root_xy[s:e + 1] - root_xy[s]
            clip["_loop"] = [round(s / FPS, 2), round(e / FPS, 2), round(best[0], 2)]
        Q = continuity(Q)
    # contact lift: per-frame smallest vertical lift that keeps every joint centre
    # above the floor (hands/knees/head in rolls, get-ups and lying poses, toes that
    # dig in because the UAL foot is longer than the source foot), max-filtered and
    # smoothed so it never pops.
    lift_max = 0.0
    if clip.get("contact", cfg.get("contact", True)):
        need = np.zeros(len(Q))
        for t in range(len(Q)):
            lp, _ = locs(t)
            h = fk_heads(Q[t], lp, (0, 0, 0), CONTACT_BONES)
            need[t] = max(0.0, max(CONTACT_MARGIN.get(n, 0.02) - h[n].z for n in h))
        if need.max() > 0.003:
            r = int(0.12 * FPS)
            mx = np.array([need[max(0, t - r): t + r + 1].max() for t in range(len(need))])
            sm = gauss(mx[:, None], 0.06 * FPS)[:, 0]
            lift = np.maximum(sm, need)
            pel[:, 2] += lift
            lift_max = float(lift.max())
    clip["_contact_lift"] = round(lift_max, 3)
    # QA: min foot height and max rotation from rest
    qa_min_foot = 9.0
    for t in range(0, len(Q), 2):
        lp, _ = locs(t)
        h = fk_heads(Q[t], lp, (0, 0, 0), feet)
        qa_min_foot = min(qa_min_foot, min(h["foot_l"].z - t_foot_rest, h["foot_r"].z - t_foot_rest,
                                           h["ball_l"].z - t_ball_rest, h["ball_r"].z - t_ball_rest))
    clip["_floor_fix"] = round(fix, 3)
    clip["_min_foot"] = round(qa_min_foot, 3)
    clip["_travel"] = round(float(np.linalg.norm(root_xy[-1])), 2)
    return Q, pel, root_xy

def dp_keep(err_fn, n, tol):
    """Douglas-Peucker on frame indices; err_fn(i, j) -> errors of frames i+1..j-1."""
    keep = {0, n - 1}
    stack = [(0, n - 1)]
    while stack:
        i, j = stack.pop()
        if j - i < 2:
            continue
        e = err_fn(i, j)
        k = int(np.argmax(e))
        if e[k] > tol:
            m = i + 1 + k
            keep.add(m)
            stack.append((i, m)); stack.append((m, j))
    return sorted(keep)

def write_action(name, Q, pel, root_xy):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    assign(tgt, act)
    n = len(Q)
    t = np.arange(n, dtype=float)
    nkeys = 0
    def put(path, idx, frames, values):
        fc = act.fcurve_ensure_for_datablock(tgt, path, index=idx)
        fc.keyframe_points.add(len(frames))
        co = np.empty(len(frames) * 2)
        co[0::2] = frames; co[1::2] = values
        fc.keyframe_points.foreach_set("co", co)
        fc.keyframe_points.foreach_set("interpolation", [bpy.types.Keyframe.bl_rna.properties["interpolation"].enum_items["LINEAR"].value] * len(frames))
        fc.update()
    for n_ in order:
        if "leaf" in n_:
            continue
        q = Q[:, IDX[n_]]
        if n_ == "root":
            continue
        const = qangle(q, q[:1]).max() < math.radians(0.05)
        if const and qangle(q[:1], np.array([[1, 0, 0, 0]]))[0] < math.radians(0.05) and n_ != "pelvis":
            continue
        if const:
            keys = [0, n - 1]
        else:
            def err(i, j, q=q):
                w = ((t[i + 1:j] - i) / (j - i))[:, None]
                qi, qj = q[i], q[j].copy()
                if np.dot(qi, qj) < 0: qj = -qj
                interp = norm_q(qi * (1 - w) + qj * w)
                return qangle(interp, q[i + 1:j])
            keys = dp_keep(err, n, ROT_TOL)
            if n_ == "pelvis":
                def perr(i, j):
                    w = ((t[i + 1:j] - i) / (j - i))[:, None]
                    return np.linalg.norm(pel[i] * (1 - w) + pel[j] * w - pel[i + 1:j], axis=1)
                keys = sorted(set(keys) | set(dp_keep(perr, n, POS_TOL)))
        path = 'pose.bones["%s"].rotation_quaternion' % n_
        for c in range(4):
            put(path, c, np.array(keys, float), q[keys, c])
        nkeys += len(keys)
        if n_ == "pelvis":
            locs = np.array([list(Linv["pelvis"] @ (tgt_mw.inverted() @ Vector(p))) for p in pel])
            for c in range(3):
                put('pose.bones["pelvis"].location', c, np.array(keys, float), locs[keys, c])
    # optional root-motion track (root bone location, horizontal travel)
    if cfg.get("root_motion_track", True) and np.abs(root_xy).max() > 0.02:
        R = np.array([list(L["root"].to_3x3().inverted() @ (tgt_mw.to_3x3().inverted() @ Vector((x, y, 0.0)))) for x, y in root_xy])
        def rerr(i, j):
            w = ((t[i + 1:j] - i) / (j - i))[:, None]
            return np.linalg.norm(R[i] * (1 - w) + R[j] * w - R[i + 1:j], axis=1)
        keys = dp_keep(rerr, n, POS_TOL)
        for c in range(3):
            put('pose.bones["root"].location', c, np.array(keys, float), R[keys, c])
    assign(tgt, None)
    return act, nkeys

def heading_fix(rig, f0, f1, mode, offset_deg=0.0):
    """Yaw correction so the clip faces UAL forward. The take's world heading is arbitrary
    (mocap actors face any way). Body heading = mean of the hip line and the shoulder line
    (unit vectors, circular mean) over the first 0.3 s ("start") or the whole clip ("mean")."""
    def lat(pbs, l, r):
        v = (rig.yaw @ (rig.mw @ pbs[rig.smap_raw[r]].head)) - (rig.yaw @ (rig.mw @ pbs[rig.smap_raw[l]].head))
        if rig.mirror:
            v = Vector((v.x, -v.y, -v.z))
        v.z = 0
        return v.normalized() if v.length > 1e-6 else v
    tl = ((tgt_mw @ tb["thigh_r"].head_local) - (tgt_mw @ tb["thigh_l"].head_local)); tl.z = 0; tl.normalize()
    if mode == "none":
        return Quaternion((0, 0, 1), math.radians(offset_deg))
    if mode == "strike":
        # aim the strongest strike (largest horizontal hand/foot reach from the pelvis) along +forward
        fwd = (tgt_mw @ tb["ball_l"].head_local) - (tgt_mw @ tb["foot_l"].head_local); fwd.z = 0; fwd.normalize()
        best = (0.0, None)
        for f in range(f0, f1 + 1, max(1, (f1 - f0) // 60 or 1)):
            scene.frame_set(f)
            pbs = rig.src.pose.bones
            pel = rig.yaw @ (rig.mw @ pbs[rig.smap_raw["pelvis"]].head)
            for k in ("hand_l", "hand_r", "foot_l", "foot_r"):
                d = (rig.yaw @ (rig.mw @ pbs[rig.smap_raw[k]].head)) - pel
                d.z = 0
                if d.length > best[0]:
                    best = (d.length, d)
        if best[1] is None or best[0] < 0.25 * 0.9:
            mode = "mean"
        else:
            d = best[1].normalized()
            if rig.mirror:
                d = Vector((-d.x, d.y, 0))
            ang = math.atan2(d.cross(fwd).z, d.dot(fwd))
            return Quaternion((0, 0, 1), ang + math.radians(offset_deg))
    n_end = f1 if mode == "mean" else min(f1, f0 + 10)
    acc = Vector((0, 0, 0))
    for f in range(f0, n_end + 1, max(1, (n_end - f0) // 12 or 1)):
        scene.frame_set(f)
        pbs = rig.src.pose.bones
        acc += lat(pbs, "thigh_l", "thigh_r") + lat(pbs, "upperarm_l", "upperarm_r")
    acc.z = 0
    if acc.length < 1e-6:
        return Quaternion()
    a = acc.normalized()
    ang = math.atan2(a.cross(tl).z, a.dot(tl))
    return Quaternion((0, 0, 1), ang + math.radians(offset_deg))

# ------------------------------------------------------------------ main loop
GLTF_CACHE = {}
made = []
report = []
for clip in cfg["clips"]:
    name = clip["name"]
    loop_name = name + ("_Loop" if clip.get("loop") else "")
    if src_type == "bvh":
        bpy.ops.object.select_all(action="DESELECT")
        bset = set(bpy.data.objects); aset = set(bpy.data.actions)
        path = P(os.path.join(cfg["bvh_dir"], clip["file"]))
        bpy.ops.import_anim.bvh(filepath=path, global_scale=1.0, use_fps_scale=False,
                                update_scene_fps=False, update_scene_duration=False, rotate_mode="NATIVE")
        src = [o for o in bpy.data.objects if o not in bset][0]
        act = src.animation_data.action
        ft = float(re.search(r"Frame Time:\s*([0-9.eE+-]+)", open(path).read(4000000)).group(1))
        src_fps = 1.0 / ft
        f_first = int(act.frame_range[0])
    elif src_type == "gltf":
        # source = a glTF/GLB whose armature carries named actions (KayKit, Quaternius ...)
        gpath = P(clip["glb"])
        if gpath not in GLTF_CACHE:
            bset = set(bpy.data.objects); aset = set(bpy.data.actions)
            bpy.ops.import_scene.gltf(filepath=gpath)
            arm = [o for o in bpy.data.objects if o not in bset and o.type == "ARMATURE"][0]
            acts = {a.name: a for a in bpy.data.actions if a not in aset}
            GLTF_CACHE[gpath] = (arm, acts)
        src, acts = GLTF_CACHE[gpath]
        act = acts[clip["action"]]
        if not src.animation_data:
            src.animation_data_create()
        assign(src, act)
        src_fps = cfg.get("source_fps", 30)
        f_first = int(math.floor(act.frame_range[0]))
    else:
        src = bpy.data.objects[cfg.get("source_armature", "Armature")]
        act = bpy.data.actions[clip["action"]]
        if not src.animation_data:
            src.animation_data_create()
        # remove NLA influence (the .blend may be saved in NLA tweak mode)
        if src.animation_data.use_tweak_mode:
            src.animation_data.use_tweak_mode = False
        for tr in src.animation_data.nla_tracks:
            tr.mute = True
        src.animation_data.use_nla = False
        assign(src, act)
        src_fps = cfg.get("source_fps", 30)
        f_first = int(math.floor(act.frame_range[0]))
    step = max(1, int(round(src_fps / FPS)))
    rig = Rig(src, bool(clip.get("mirror", False)))
    a0 = clip.get("start", None); a1 = clip.get("end", None)
    f_last = int(math.ceil(act.frame_range[1]))
    fs = f_first + int(round(a0 * src_fps)) if a0 is not None else f_first + clip.get("skip_frames", 0)
    fe = min(f_last, f_first + int(round(a1 * src_fps))) if a1 is not None else f_last
    rig.ye = heading_fix(rig, fs, fe, clip.get("heading", cfg.get("heading", "strike")), clip.get("heading_deg", 0.0))
    Q, pel, root_xy = bake_clip(rig, fs, fe, step, clip)
    new, nkeys = write_action(loop_name, Q, pel, root_xy)
    if cfg.get("check_directions") and not clip.get("loop"):
        # bone direction error target vs source (world, after yaw), mapped bones
        errs = []
        assign(tgt, new)
        for fi in range(0, len(Q), max(1, len(Q) // 6)):
            scene.frame_set(fs + fi * step)
            sdir = {}
            for n_, s_ in bmap.items():
                if n_ in ("pelvis",) or s_ not in src.pose.bones or "_0" in n_:
                    continue
                pb = src.pose.bones[s_]
                sdir[n_] = (rig.yaw @ ((rig.mw @ pb.tail) - (rig.mw @ pb.head))).normalized()
            scene.frame_set(fi)
            for n_, d in sdir.items():
                pb = tgt.pose.bones[n_]
                td = ((tgt_mw @ pb.tail) - (tgt_mw @ pb.head)).normalized()
                if td.length < 1e-6 or d.length < 1e-6:
                    continue
                errs.append((math.degrees(td.angle(d)), n_, fi))
        assign(tgt, None)
        errs.sort(reverse=True)
        print("DIRCHECK", name, "mean %.1f" % (sum(e[0] for e in errs) / len(errs)), "worst", [(round(e[0]), e[1], e[2]) for e in errs[:5]])
    made.append((loop_name, new))
    info = {"name": name, "loop": bool(clip.get("loop")), "seconds": round((len(Q) - 1) / FPS, 2),
            "frames": len(Q), "keys": nkeys, "source": clip.get("file", clip.get("action")),
            "range_s": [a0, a1], "autotrim": clip.get("_autotrim"), "loop_pts": clip.get("_loop"),
            "floor_fix_m": clip["_floor_fix"], "contact_lift_m": clip.get("_contact_lift"), "min_foot_m": clip["_min_foot"], "travel_m": clip["_travel"],
            "hip_scale": round(rig.k, 4)}
    report.append(info)
    print("CLIP", json.dumps(info))
    if src_type == "bvh":
        assign(src, None)
        bpy.data.objects.remove(src)
        bpy.data.actions.remove(act)

# ------------------------------------------------------------------- export
assign(tgt, None)
for pb in tgt.pose.bones:
    pb.rotation_quaternion = Quaternion(); pb.location = Vector()
if src_type == "blend":
    src = bpy.data.objects.get(cfg.get("source_armature", "Armature"))
    if src and src.animation_data:
        src.animation_data.action = None
for a in list(bpy.data.actions):
    if a not in [m[1] for m in made]:
        try:
            bpy.data.actions.remove(a)
        except Exception:
            pass
# Keep the export light: replace the 13.7k-tri mannequin with one skinned
# triangle (Godot still builds the 65-bone Skeleton3D from the glTF skin).
keep = [tgt]
for o in new_objs:
    if o.type == "MESH":
        if cfg.get("tiny_mesh", True):
            bpy.data.objects.remove(o)
        else:
            keep.append(o)
if cfg.get("tiny_mesh", True):
    me = bpy.data.meshes.new("UAL_Skin_Stub")
    me.from_pydata([(0, 0, 0.9), (0.01, 0, 0.9), (0, 0.01, 0.9)], [], [(0, 1, 2)])
    ob = bpy.data.objects.new("UAL_Skin_Stub", me)
    scene.collection.objects.link(ob)
    ob.parent = tgt
    vg = ob.vertex_groups.new(name="pelvis")
    vg.add([0, 1, 2], 1.0, "REPLACE")
    mod = ob.modifiers.new("Armature", "ARMATURE")
    mod.object = tgt
    keep.append(ob)
for name, a in made:
    tr = tgt.animation_data.nla_tracks.new()
    tr.name = name
    tr.strips.new(name, 0, a)
bpy.ops.object.select_all(action="DESELECT")
for o in keep:
    o.select_set(True)
bpy.context.view_layer.objects.active = tgt
out = P(cfg["out"])
os.makedirs(os.path.dirname(out), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True,
                          export_animations=True, export_animation_mode="NLA_TRACKS",
                          export_force_sampling=cfg.get("force_sampling", False),
                          export_optimize_animation_size=False,
                          export_draco_mesh_compression_enable=False, export_materials="NONE",
                          export_apply=False, export_yup=True, export_def_bones=False,
                          export_anim_single_armature=True, export_reset_pose_bones=True)
json.dump(report, open(out + ".clips.json", "w"), indent=1)
print("EXPORTED", out, len(made), "clips", os.path.getsize(out), "bytes")
