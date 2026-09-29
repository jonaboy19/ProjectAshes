# retarget_loco.py = retarget_bvh.py + what the locomotion-transition / jump pass needs (see tools/anim/loco/README.md):
#   * per-clip "speed" (uniform time scale) and "warp" ([[src_s, out_s], ...] piecewise time map),
#   * "match_entry"/"match_exit": pick the trim frame whose pose best matches a UAL loop (Walk/Jog/Sprint) so the clip blends
#     into / out of the existing gait without a pop; the matched loop phase goes to the sidecar,
#   * "yaw_root": the body heading change (pivots, turns in place) is moved onto the `root` bone rotation, the pelvis keeps
#     only the residual, so root translation + yaw are the full root motion,
#   * "air_z": airborne frames keep the pelvis at ground-relative standing height (the capsule owns the ballistic arc),
#   * "travel_fit": scale the pelvis travel so planted feet do not slide,
#   * "pingpong": build a seamless hover loop from a short mocap window (jump rise / fall loops),
#   * a contact sidecar (<glb>.contacts.json): per foot planted windows, slide, root speeds, matched loop phases.
#
# (parent header follows)
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
if os.environ.get("LOCO_OUT"):
    cfg["out"] = os.environ["LOCO_OUT"]
if os.environ.get("LOCO_ONLY"):
    _only = set(os.environ["LOCO_ONLY"].split(","))
    cfg["clips"] = [c for c in cfg["clips"] if c["name"] in _only]
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
REF = {}        # loop name -> {"Q": [n, nbones, 4], "sec": duration}
for lname in cfg.get("ref_loops", []):
    act = ual_actions[lname]
    assign(tgt, act)
    f0, f1 = act.frame_range
    nfr = int(round(f1 - f0))
    rows = []; locs_ = []
    for f in range(nfr):                      # last frame == first: keep nfr samples, phase = i / nfr
        scene.frame_set(int(f0) + f)
        rows.append([tuple(tgt.pose.bones[n].rotation_quaternion) for n in order])
        locs_.append(tuple(tgt.pose.bones["pelvis"].location))
    REF[lname] = {"Q": np.array(rows), "loc": np.array(locs_), "sec": nfr / float(scene.render.fps)}
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
    def __init__(self, src, mirror=False, bm=None):
        bm = bm or bmap
        self.bmap = bm
        self.src = src
        self.mirror = mirror
        self.ye = Quaternion()          # extra heading (yaw about vertical), set per clip
        self.smap = {n: (swap_lr(v) if mirror else v) for n, v in bm.items()}
        self.smap_raw = bm
        mw = src.matrix_world.copy()
        self.mw, self.mw_rot = mw, mw.to_quaternion()
        sb = src.data.bones
        def facing(arm, foot, ball, m):
            d = (m @ arm.data.bones[ball].head_local) - (m @ arm.data.bones[foot].head_local)
            d.z = 0
            return d.normalized()
        fs = facing(src, bm["foot_l"], bm["ball_l"], mw)
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
        sp = mw @ sb[bm["pelvis"]].head_local
        sf = mw @ sb[bm["foot_l"]].head_local
        self.k = t_leg / (sp.z - sf.z)
        if cfg.get("scale_mode") == "height" and "Head" in bm and bm["Head"] in sb:
            # source with unlike proportions (chibi KayKit: short legs, long torso): scale the
            # pelvis travel by overall stature (foot -> head) instead of leg length
            sh = mw @ sb[bm["Head"]].head_local
            th = (tgt_mw @ tb["Head"].head_local).z
            self.k = (th - t_foot_rest) / (sh.z - sf.z)
        self.pelvis_src = bm["pelvis"]

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

def gauss_odd(x, sigma):
    """Gaussian smoothing with odd (point-reflected) end padding: a linear trend, e.g. the speed at the first / last frame of a
    start or stop, survives the smoothing (edge replication would flatten it)."""
    if sigma <= 0.05:
        return x.copy()
    r = int(math.ceil(3 * sigma))
    r = min(r, len(x) - 1)
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    left = 2 * x[:1] - x[1:r + 1][::-1]
    right = 2 * x[-1:] - x[-r - 1:-1][::-1]
    pad = np.concatenate([left, x, right], 0)
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
FEET = ["foot_l", "foot_r", "ball_l", "ball_r"]
POSE_BONES = ["spine_01", "spine_02", "spine_03", "thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r",
              "upperarm_l", "lowerarm_l", "upperarm_r", "lowerarm_r", "Head"]
POSE_IDX = [IDX[n] for n in POSE_BONES if n in IDX]
POSE_W = np.array([{"foot_l": 1.5, "foot_r": 1.5, "calf_l": 1.5, "calf_r": 1.5, "thigh_l": 1.5, "thigh_r": 1.5}.get(n, 1.0)
                   for n in POSE_BONES if n in IDX])

def pose_err(qa, qb):
    """Weighted mean bone rotation difference (degrees) between two [nbones, 4] poses, pelvis yaw ignored."""
    return float(np.degrees((qangle(qa[POSE_IDX], qb[POSE_IDX]) * POSE_W).sum() / POSE_W.sum()))

def phase_errors(q, lname):
    R = REF[lname]["Q"]
    return np.array([pose_err(q, R[i]) for i in range(len(R))])

def fk_mats(q, loc_pelvis, names):
    """Armature-space matrices of the named bones (root at identity)."""
    mats = {}
    out = {}
    for n in order:
        b = tb[n]
        qq = q[IDX[n]]
        basis = Quaternion((qq[0], qq[1], qq[2], qq[3])).to_matrix().to_4x4()
        if n == "pelvis":
            basis = Matrix.Translation(Vector(loc_pelvis)) @ basis
        if b.parent is None:
            m = L[n] @ basis
        else:
            p = b.parent.name
            if p not in mats:
                continue
            m = mats[p] @ (Linv[p] @ L[n]) @ basis
        mats[n] = m
        if n in names:
            out[n] = m
        if len(out) == len(names):
            break
    return out

F0 = (tgt_mw @ tb["ball_l"].head_local) - (tgt_mw @ tb["foot_l"].head_local)
F0.z = 0
F0.normalize()                                   # character forward (horizontal) in the target frame
LEFT0 = Vector((0, 0, 1)).cross(F0)              # character left
LROT = {n: L[n].to_3x3() for n in order}

def heading_of(mats, name):
    """Yaw (rad, +CCW seen from above = turn left) of a bone frame relative to its rest heading."""
    d = mats[name].to_3x3() @ LROT[name].inverted() @ F0
    return math.atan2(d.dot(LEFT0), d.dot(F0))

def body_yaw(Q, pel):
    """Per-frame body heading (unwrapped, +left) = circular mean of pelvis and chest heading."""
    ys = []
    for t in range(len(Q)):
        lp = Linv["pelvis"] @ (tgt_mw.inverted() @ Vector(pel[t]))
        m = fk_mats(Q[t], lp, ["pelvis", "spine_03"])
        a = heading_of(m, "pelvis"); b = heading_of(m, "spine_03")
        ys.append(math.atan2(math.sin(a) + math.sin(b), math.cos(a) + math.cos(b)))
    return np.unwrap(np.array(ys))

def resample_map(clip, n_src, src_fps):
    """Source-frame positions (floats, relative to the window start) for every 30 fps output frame."""
    T_src = (n_src - 1) / src_fps
    if clip.get("pingpong"):
        n_out = int(round(clip.get("loop_seconds", 1.0) * FPS))
        u = 0.5 * (1 - np.cos(2 * math.pi * np.arange(n_out + 1) / n_out))
        return u * (n_src - 1)
    speed = clip.get("speed", 1.0)
    warp = clip.get("warp")
    if warp:
        pts = sorted([list(p) for p in warp])
        if pts[0][0] > 1e-6:
            pts.insert(0, [0.0, 0.0])
        if pts[-1][0] < T_src - 1e-6:
            pts.append([T_src, pts[-1][1] + (T_src - pts[-1][0]) / speed])
        s_pts = np.array([p[0] for p in pts]); o_pts = np.array([p[1] for p in pts])
        T_out = o_pts[-1]
        t_out = np.arange(0, int(math.floor(T_out * FPS + 1e-6)) + 1) / FPS
        return np.interp(t_out, o_pts, s_pts) * src_fps
    T_out = T_src / speed
    t_out = np.arange(0, int(math.floor(T_out * FPS + 1e-6)) + 1) / FPS
    return np.minimum(t_out * speed, T_src) * src_fps

def resample_q(Q, Pw, pos):
    i0 = np.clip(np.floor(pos).astype(int), 0, len(Q) - 1)
    i1 = np.clip(i0 + 1, 0, len(Q) - 1)
    w = (pos - i0)[:, None]
    Qa, Qb = Q[i0], Q[i1].copy()
    sign = np.sign(np.sum(Qa * Qb, axis=-1, keepdims=True)); sign[sign == 0] = 1
    Qo = norm_q(Qa * (1 - w[:, :, None]) + Qb * sign * w[:, :, None])
    Po = Pw[i0] * (1 - w) + Pw[i1] * w
    return Qo, Po

def feet_world(Q, pel, root_xy):
    n = len(Q)
    P = np.zeros((n, 4, 3))
    for t in range(n):
        lp = Linv["pelvis"] @ (tgt_mw.inverted() @ Vector(pel[t]))
        h = fk_heads(Q[t], lp, (0, 0, 0), FEET)
        for j, nm in enumerate(FEET):
            P[t, j] = h[nm]
        P[t, :, 0] += root_xy[t, 0]; P[t, :, 1] += root_xy[t, 1]
    return P

def windows(mask, min_len=2):
    out = []; a = None
    for i, m in enumerate(mask):
        if m and a is None:
            a = i
        if (not m) and a is not None:
            if i - a >= min_len: out.append([a, i - 1])
            a = None
    if a is not None and len(mask) - a >= min_len: out.append([a, len(mask) - 1])
    return out

TOUCH = 0.03
def contact_report(P, root_xy):
    hf = P[:, :2, 2] - t_foot_rest          # ankles (foot_l, foot_r)
    hb = P[:, 2:, 2] - t_ball_rest          # balls
    rep = {"left": [], "right": [], "flat_left": [], "flat_right": [], "slide_cm": {}, "airborne": [], "slide_windows": []}
    worst = 0.0
    for j, side in enumerate(("left", "right")):
        touch = np.minimum(hf[:, j], hb[:, j]) < TOUCH
        flat = (hf[:, j] < TOUCH * 1.5) & (hb[:, j] < TOUCH)
        rep[side] = windows(touch, 2)
        rep["flat_" + side] = windows(flat, 2)
        sl = []
        # ball while it touches; heel point (ankle pushed 6 cm back along the foot) while only the heel touches
        d_fb = P[:, j, :2] - P[:, 2 + j, :2]
        d_fb = d_fb / np.maximum(np.linalg.norm(d_fb, axis=1, keepdims=True), 1e-6)
        heel = P[:, j, :2] + d_fb * 0.06
        def pspeed(pts):
            v = np.zeros(len(pts))
            if len(pts) > 2:
                v[1:-1] = np.linalg.norm(pts[2:] - pts[:-2], axis=1) * FPS / 2
                v[0] = v[1]; v[-1] = v[-2]
            return v
        SLOW = 0.5      # m/s: a point that is low but still travels faster than this is a foot in swing, not a planted one
        for pts, mask, pn, ml in ((P[:, 2 + j, :2], (hb[:, j] < TOUCH) & (pspeed(P[:, 2 + j, :2]) < SLOW), "ball", 3),
                                  (heel, (hf[:, j] < TOUCH) & (hb[:, j] >= TOUCH) & (pspeed(heel) < SLOW), "heel", 2)):
            for a, b in windows(mask, ml):
                a2 = a + 1                              # first frame is the touch-down itself
                d = np.linalg.norm(pts[a2:b + 1] - pts[a2], axis=1)
                sl.append(float(d.max()) * 100 if len(d) else 0.0)
                rep["slide_windows"].append([side, pn, a, b, round(sl[-1], 1)])
        rep["slide_cm"][side] = round(max(sl), 1) if sl else 0.0
        worst = max(worst, rep["slide_cm"][side])
    rep["slide_max_cm"] = round(worst, 1)
    air = np.minimum(np.minimum(hf[:, 0], hb[:, 0]), np.minimum(hf[:, 1], hb[:, 1])) > TOUCH
    rep["airborne"] = windows(air, 1)
    return rep, hf, hb

def bake_clip(rig, f_start, f_end, src_fps, clip):
    frames = list(range(f_start, f_end + 1))
    Qs, Ps = [], []
    for f in frames:
        q, p = rig.sample(f)
        Qs.append(q); Ps.append(p)
    Q = continuity(np.array(Qs))
    Pw = np.array(Ps)
    sig = clip.get("smooth", cfg.get("smooth", 0.0)) * src_fps
    if sig > 0:
        Q = norm_q(gauss(Q.reshape(len(Q), -1), sig).reshape(Q.shape))
        Pw = gauss(Pw, sig)
    if clip.get("pingpong"):
        # hover loop from a still window: palindrome through the window with cosine easing, pelvis fixed at the window mean
        Pw = np.repeat(Pw.mean(0, keepdims=True), len(Pw), 0)
    pos = resample_map(clip, len(Q), src_fps)
    Q, Pw = resample_q(Q, Pw, pos)
    fp = clip.get("fingers", cfg.get("fingers"))
    if fp in finger_pose:
        for n, qq in finger_pose[fp].items():
            Q[:, IDX[n]] = (qq.w, qq.x, qq.y, qq.z)
    Q = continuity(Q)
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
        traj = gauss_odd(H, clip.get("inplace_sigma", 0.2) * FPS)
    sway = H - traj
    root_xy = traj - traj[0]
    pel = np.zeros_like(Pw)
    pel[:, 0] = tp.x + sway[:, 0]
    pel[:, 1] = tp.y + sway[:, 1]
    pel[:, 2] = Pw[:, 2]
    pel[:, 0] -= np.mean(sway[:, 0]); pel[:, 1] -= np.mean(sway[:, 1])
    def locs(t):
        lp = Linv["pelvis"] @ (tgt_mw.inverted() @ Vector(pel[t]))
        return lp
    feet = FEET
    floor = clip.get("floor", cfg.get("floor", "auto"))
    fix = 0.0
    def foot_heights():
        out = []
        for t in range(len(Q)):
            h = fk_heads(Q[t], locs(t), (0, 0, 0), feet)
            out.append([h["foot_l"].z - t_foot_rest, h["foot_r"].z - t_foot_rest,
                        h["ball_l"].z - t_ball_rest, h["ball_r"].z - t_ball_rest])
        return np.array(out)
    if floor != "none":
        hh = foot_heights()
        gl = hh.min(axis=1)
        standing = pel[:, 2] > 0.7 * tp.z
        gs = gl[standing]
        if floor == "min":
            gs = gl
        if floor == "start":
            gs = gl[:3]
        if floor == "end":
            gs = gl[-3:]
        if len(gs) >= 3:
            fix = -float(np.percentile(gs, 5)) if floor in ("auto", "min") else -float(np.mean(gs))
            lim = clip.get("floor_limit", 0.2)
            fix = max(-lim, min(lim, fix))
            pel[:, 2] += fix
    # airborne: the capsule owns the ballistic arc, the pelvis keeps its ground-relative height
    if clip.get("air_z"):
        hh = foot_heights()
        air = hh.min(axis=1) > 0.05
        n = len(Q)
        for a, b in windows(air, 1):
            za = pel[a - 1, 2] if a > 0 else None
            zb = pel[b + 1, 2] if b < n - 1 else None
            if za is None: za = zb
            if zb is None: zb = za
            if za is None: za = zb = tp.z
            az = clip.get("air_z")
            if isinstance(az, (int, float)) and not isinstance(az, bool):
                za = zb = float(az) * tp.z
            for i in range(a, b + 1):
                u = (i - a + 1) / (b - a + 2)
                u = u * u * (3 - 2 * u)
                pel[i, 2] = za + (zb - za) * u
    # loop: pick loop points and crossfade (same as retarget_bvh)
    if clip.get("loop") and not clip.get("loop_native") and not clip.get("pingpong"):
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
    # contact lift (toes that dig in, hands/knees in rolls): smallest smooth vertical lift keeping joints above the floor
    lift_max = 0.0
    if clip.get("contact", cfg.get("contact", True)):
        need = np.zeros(len(Q))
        for t in range(len(Q)):
            h = fk_heads(Q[t], locs(t), (0, 0, 0), CONTACT_BONES)
            need[t] = max(0.0, max(CONTACT_MARGIN.get(n, 0.02) - h[n].z for n in h))
        if need.max() > 0.003:
            r = int(0.12 * FPS)
            mx = np.array([need[max(0, t - r): t + r + 1].max() for t in range(len(need))])
            sm = gauss(mx[:, None], 0.06 * FPS)[:, 0]
            lift = np.maximum(sm, need)
            pel[:, 2] += lift
            lift_max = float(lift.max())
    clip["_contact_lift"] = round(lift_max, 3)
    # planted feet must not slide: fit the horizontal pelvis travel to the stance feet (one scale factor per clip)
    fit = 1.0
    if clip.get("travel_fit", True) and not clip.get("pingpong") and np.abs(root_xy).max() > 0.05:
        P0 = feet_world(Q, pel, root_xy)
        hb0 = P0[:, 2:, 2] - t_ball_rest
        num = den = 0.0
        pelw = pel[:, :2] + root_xy
        for j in (0, 1):
            rel = P0[:, 2 + j, :2] - pelw            # ball relative to pelvis (world axes)
            for t in range(len(Q) - 1):
                if hb0[t, j] < TOUCH and hb0[t + 1, j] < TOUCH:
                    dP = pelw[t + 1] - pelw[t]; dF = rel[t + 1] - rel[t]
                    num += float(dP @ dF); den += float(dP @ dP)
        fm = clip.get("fit_max", 1.25)
        if den > 1e-6:
            fit = min(fm, max(1 / fm, -num / den))
        root_xy = root_xy * fit
        pel[:, 0] = tp.x + (pel[:, 0] - tp.x) * fit
        pel[:, 1] = tp.y + (pel[:, 1] - tp.y) * fit
    clip["_travel_fit"] = round(fit, 3)
    P = feet_world(Q, pel, root_xy)
    rep, hf, hb = contact_report(P, root_xy)
    clip["_min_foot"] = round(float(min(hf.min(), hb.min())), 3)
    clip["_floor_fix"] = round(fix, 3)
    clip["_travel"] = round(float(np.linalg.norm(root_xy[-1])), 2)
    yaw = None
    yaw_full = body_yaw(Q, pel)
    ys = gauss(yaw_full[:, None], clip.get("yaw_sigma", 0.08) * FPS)[:, 0]
    ys = ys - ys[0]
    clip["_yaw_deg"] = round(math.degrees(float(ys[-1])), 1)
    if clip.get("yaw_root"):
        yaw = ys
    return Q, pel, root_xy, yaw, rep, P

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

def write_action(name, Q, pel, root_xy, yaw=None):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    assign(tgt, act)
    n = len(Q)
    t = np.arange(n, dtype=float)
    nkeys = 0
    root_q = None
    if yaw is not None:
        # heading change -> root bone rotation; the pelvis (and everything under it) keeps its world orientation
        Q = Q.copy(); pel = pel.copy()
        Lr, Lp = LROT["root"], LROT["pelvis"]
        root_q = np.zeros((n, 4))
        for i in range(n):
            Rz = Matrix.Rotation(float(yaw[i]), 3, "Z")
            rqq = (Lr.inverted() @ Rz @ Lr).to_quaternion()
            root_q[i] = (rqq.w, rqq.x, rqq.y, rqq.z)
            corr = (Lp.inverted() @ Rz.inverted() @ Lp).to_quaternion()
            qp = Quaternion(tuple(Q[i, IDX["pelvis"]]))
            nq = corr @ qp
            Q[i, IDX["pelvis"]] = (nq.w, nq.x, nq.y, nq.z)
            c, s_ = math.cos(-float(yaw[i])), math.sin(-float(yaw[i]))
            x, y = pel[i, 0], pel[i, 1]
            pel[i, 0] = c * x - s_ * y; pel[i, 1] = s_ * x + c * y
        Q = continuity(Q)
        root_q = continuity(root_q[:, None, :])[:, 0, :]
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
    if root_q is not None:
        def qerr(i, j):
            w = ((t[i + 1:j] - i) / (j - i))[:, None]
            qi, qj = root_q[i], root_q[j].copy()
            if np.dot(qi, qj) < 0: qj = -qj
            return qangle(norm_q(qi * (1 - w) + qj * w), root_q[i + 1:j])
        keys = dp_keep(qerr, n, ROT_TOL)
        for c in range(4):
            put('pose.bones["root"].rotation_quaternion', c, np.array(keys, float), root_q[keys, c])
        nkeys += len(keys)
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
def side_of(phase):
    return "L" if phase < 0.5 else "R"

def match_frame(rig, src_fps, f_first, rng, lname, side=None, want=None):
    """Best (frame, phase, err) over source frames in the time range `rng` (s) against the UAL loop `lname`.
    side "L"/"R" restricts the loop phase to the left / right half of the cycle."""
    step = max(1, int(round(src_fps / FPS / 2)))
    best = None
    for f in range(f_first + int(round(rng[0] * src_fps)), f_first + int(round(rng[1] * src_fps)) + 1, step):
        q, _ = rig.sample(f)
        errs = phase_errors(q, lname)
        for i, e in enumerate(errs):
            ph = i / len(errs)
            if side and side_of(ph) != side:
                continue
            if best is None or e < best[2]:
                best = (f, ph, float(e))
    return best

def loop_hint(q, lname):
    errs = phase_errors(q, lname)
    i = int(np.argmin(errs))
    ph = i / len(errs)
    return {"loop": lname, "phase": round(ph, 3), "side": side_of(ph), "err_deg": round(float(errs[i]), 1),
            "loop_seconds": round(REF[lname]["sec"], 4)}

REF_REPORT = {}
for lname, R in REF.items():
    Qr, LOC = R["Q"], R["loc"]
    n = len(Qr)
    PFT = np.zeros((n, 4, 3)); PEL = np.zeros((n, 3))
    for t in range(n):
        h = fk_heads(Qr[t], tuple(LOC[t]), (0, 0, 0), FEET + ["pelvis"])
        for j, nm in enumerate(FEET):
            PFT[t, j] = h[nm]
        PEL[t] = h["pelvis"]
    hf = PFT[:, :2, 2] - t_foot_rest; hb = PFT[:, 2:, 2] - t_ball_rest
    dt = R["sec"] / n
    rep = {"seconds": round(R["sec"], 4), "samples": n}
    speeds = []
    for j, side in enumerate(("left", "right")):
        touch = np.minimum(hf[:, j], hb[:, j]) < TOUCH
        # circular windows (the cycle wraps): rotate so that index 0 is a swing frame
        wins = windows(touch, 2)
        rep[side + "_stance_phase"] = [[round(a / n, 3), round((b + 1) / n, 3)] for a, b in wins]
        rel = PFT[:, j, :2] - PEL[:, :2]
        for a, b in wins:
            if b - a >= 2:
                v = np.linalg.norm(rel[b] - rel[a]) / ((b - a) * dt)
                speeds.append(float(v))
    rep["natural_speed_mps"] = round(float(np.median(speeds)), 2) if speeds else 0.0
    REF_REPORT[lname] = rep
    print("REF", lname, json.dumps(rep))

GLTF_CACHE = {}
made = []
report = []
def bake_source(clip):
    """import the take, retarget + bake one source window -> (Q, pel, root_xy, yaw, rep, Pfeet, matched, hip_scale)."""
    bpy.ops.object.select_all(action="DESELECT")
    bset = set(bpy.data.objects)
    path = P(os.path.join(cfg["bvh_dir"], clip["file"]))
    bpy.ops.import_anim.bvh(filepath=path, global_scale=1.0, use_fps_scale=False,
                            update_scene_fps=False, update_scene_duration=False, rotate_mode="NATIVE")
    src = [o for o in bpy.data.objects if o not in bset][0]
    act = src.animation_data.action
    ft = float(re.search(r"Frame Time:\s*([0-9.eE+-]+)", open(path).read(4000000)).group(1))
    src_fps = 1.0 / ft
    f_first = int(act.frame_range[0])
    rig = Rig(src, bool(clip.get("mirror", False)), cfg.get("maps", {}).get(clip.get("map")))
    a0 = clip.get("start", None); a1 = clip.get("end", None)
    f_last = int(math.ceil(act.frame_range[1]))
    fs = f_first + int(round(a0 * src_fps)) if a0 is not None else f_first + clip.get("skip_frames", 0)
    fe = min(f_last, f_first + int(round(a1 * src_fps))) if a1 is not None else f_last
    rig.ye = heading_fix(rig, fs, fe, clip.get("heading", cfg.get("heading", "start")), clip.get("heading_deg", 0.0))
    matched = {}
    if clip.get("match_entry"):
        me = clip["match_entry"]
        r = match_frame(rig, src_fps, f_first, me["range"], me["loop"], me.get("side"))
        fs = r[0]; matched["entry"] = {"loop": me["loop"], "phase": round(r[1], 3), "err_deg": round(r[2], 1),
                                       "source_s": round((r[0] - f_first) / src_fps, 3)}
    if clip.get("match_exit"):
        mx = clip["match_exit"]
        r = match_frame(rig, src_fps, f_first, mx["range"], mx["loop"], mx.get("side"))
        fe = r[0]; matched["exit"] = {"loop": mx["loop"], "phase": round(r[1], 3), "err_deg": round(r[2], 1),
                                      "source_s": round((r[0] - f_first) / src_fps, 3)}
    if fe - fs < 6:
        raise SystemExit("clip %s: window too short (%d..%d)" % (clip["name"], fs, fe))
    clip["_window_s"] = [round((fs - f_first) / src_fps, 3), round((fe - f_first) / src_fps, 3)]
    out = bake_clip(rig, fs, fe, src_fps, clip)
    k = rig.k
    assign(src, None)
    bpy.data.objects.remove(src)
    bpy.data.actions.remove(act)
    return out + (matched, k)

def bake_ual_segment(sg):
    """A window of an existing UAL clip (sampled by ref_loops) as a composition segment: (Q, pel, root_xy) at 30 fps."""
    R = REF[sg["ual"]]
    n = len(R["Q"]); fps_ref = n / R["sec"]
    a = int(round(sg.get("start", 0.0) * fps_ref)); b = min(n - 1, int(round(sg.get("end", R["sec"]) * fps_ref)))
    Qs = continuity(R["Q"][a:b + 1].copy())
    pos = []
    for t in range(len(Qs)):
        m = Matrix.Translation(Vector(R["loc"][a + t]))
        pos.append((L["pelvis"] @ m).translation[:])
    pos = np.array(pos)
    rs = resample_map(dict(speed=sg.get("speed", 1.0)), len(Qs), fps_ref)
    Qo, Po = resample_q(Qs, pos, rs)
    pel = Po.copy(); root_xy = np.zeros((len(Qo), 2))
    return Qo, pel, root_xy

def compose_parts(parts, nx_list):
    """Concatenate baked segments (Q, pel, root_xy) with crossfades; returns Q, pel, root_xy (world path re-split)."""
    Qc = None
    for idx, (Q, pel, root_xy) in enumerate(parts):
        W = root_xy + pel[:, :2]; Z = pel[:, 2]
        if Qc is None:
            Qc, Wc, Zc = Q.copy(), W.copy(), Z.copy(); continue
        nx = nx_list[idx - 1]
        W = W + (Wc[-nx] - W[0])
        for j in range(nx):
            w = (j + 1) / (nx + 1); w = w * w * (3 - 2 * w)
            qa, qb = Qc[-nx + j], Q[j].copy()
            sg = np.sign(np.sum(qa * qb, -1, keepdims=True)); sg[sg == 0] = 1
            Qc[-nx + j] = norm_q(qa * (1 - w) + qb * sg * w)
            Wc[-nx + j] = Wc[-nx + j] * (1 - w) + W[j] * w
            Zc[-nx + j] = Zc[-nx + j] * (1 - w) + Z[j] * w
        Qc = np.concatenate([Qc, Q[nx:]], 0); Wc = np.concatenate([Wc, W[nx:]], 0); Zc = np.concatenate([Zc, Z[nx:]], 0)
    Qc = continuity(Qc)
    traj = gauss_odd(Wc, 0.2 * FPS)
    sway = Wc - traj
    root_xy = traj - traj[0]
    pel = np.zeros((len(Qc), 3))
    pel[:, 0] = tp.x + sway[:, 0] - sway[:, 0].mean(); pel[:, 1] = tp.y + sway[:, 1] - sway[:, 1].mean(); pel[:, 2] = Zc
    return Qc, pel, root_xy

for clip in cfg["clips"]:
    name = clip["name"]
    loop_name = name + ("_Loop" if clip.get("loop") else "")
    if clip.get("segments"):
        parts = []; matched = {"segments": []}
        for sg in clip["segments"]:
            sc_ = dict(sg); sc_.setdefault("name", name)
            for kk in ("mirror", "map"):
                if kk in clip: sc_.setdefault(kk, clip[kk])
            sc_["travel_fit"] = False
            if sg.get("ual"):
                o = bake_ual_segment(sg)
                parts.append(o); matched["segments"].append({"file": "UAL:" + sg["ual"], "window_s": [sg.get("start", 0.0), sg.get("end")]})
                continue
            o = bake_source(sc_)
            parts.append((o[0], o[1], o[2])); matched["segments"].append({"file": sg["file"], "window_s": sc_["_window_s"], **o[6]})
            k_hip = o[7]
        Q, pel, root_xy = compose_parts(parts, clip.get("xfade_frames", [4] * (len(parts) - 1)))
        clip["_travel_fit"] = 1.0
        # contact report / yaw for the composite
        P_ = feet_world(Q, pel, root_xy)
        rep, hf_, hb_ = contact_report(P_, root_xy)
        clip["_min_foot"] = round(float(min(hf_.min(), hb_.min())), 3); clip["_floor_fix"] = 0.0
        clip["_travel"] = round(float(np.linalg.norm(root_xy[-1])), 2)
        ys = gauss(body_yaw(Q, pel)[:, None], clip.get("yaw_sigma", 0.08) * FPS)[:, 0]; ys = ys - ys[0]
        clip["_yaw_deg"] = round(math.degrees(float(ys[-1])), 1)
        yaw = ys if clip.get("yaw_root") else None
        Pfeet = P_
        clip["_window_s"] = [s_["window_s"] for s_ in matched["segments"]]
        clip["file"] = "+".join(s_.get("file", "UAL:" + s_.get("ual", "")) for s_ in clip["segments"])
        class _R: pass
        rig_k = k_hip
    else:
        Q, pel, root_xy, yaw, rep, Pfeet, matched, rig_k = bake_source(clip)
    new, nkeys = write_action(loop_name, Q, pel, root_xy, yaw)
    made.append((loop_name, new))
    n = len(Q)
    sp = np.linalg.norm(np.diff(root_xy, axis=0), axis=1) * FPS
    sp = gauss(sp[:, None], 1.5)[:, 0] if len(sp) else np.zeros(1)
    end = root_xy[-1] - root_xy[0]
    root_info = {"distance_m": round(float(np.linalg.norm(end)), 3),
                 "forward_m": round(float(end[0] * F0.x + end[1] * F0.y), 3),
                 "left_m": round(float(end[0] * LEFT0.x + end[1] * LEFT0.y), 3),
                 "yaw_deg": clip["_yaw_deg"], "yaw_on_root_bone": bool(yaw is not None),
                 "speed_in_mps": round(float(sp[:4].mean()), 2), "speed_out_mps": round(float(sp[-4:].mean()), 2),
                 "speed_max_mps": round(float(sp.max()), 2),
                 "speed_curve_mps": [round(float(x), 2) for x in sp[::3]],
                 "yaw_curve_deg": [round(math.degrees(float(y)), 1) for y in (yaw if yaw is not None else np.zeros(n))[::3]]}
    hand = {}
    if clip.get("entry_loop"):
        hand["entry"] = loop_hint(Q[0], clip["entry_loop"])
    if clip.get("exit_loop"):
        hand["exit"] = loop_hint(Q[-1], clip["exit_loop"])
    lf = rep["left"] and rep["left"][-1][1] >= n - 2
    rf = rep["right"] and rep["right"][-1][1] >= n - 2
    end_foot = "both" if (lf and rf) else "left" if lf else "right" if rf else "air"
    if clip.get("pingpong"):
        rep = dict(rep); rep["left"] = []; rep["right"] = []; rep["flat_left"] = []; rep["flat_right"] = []
        rep["airborne"] = [[0, n - 1]]; rep["slide_windows"] = []; rep["slide_cm"] = {"left": 0.0, "right": 0.0}; rep["slide_max_cm"] = 0.0
        end_foot = "air"
    ev = dict(clip.get("events", {}))
    steps = sorted([[w[0], "left"] for w in rep["left"]] + [[w[0], "right"] for w in rep["right"]])
    ev["footstep_frames"] = [{"frame": int(f), "foot": ft_} for f, ft_ in steps if f > 0]
    if name.startswith("Jump_") and not clip.get("pingpong"):
        ev.setdefault("takeoff_frame", int(rep["airborne"][0][0]) if rep["airborne"] and rep["airborne"][0][0] > 0 else None)
        ev.setdefault("touchdown_frame", None)
    else:
        ev["takeoff_frame"] = None; ev["touchdown_frame"] = None
    both = [t for t in range(n) if any(w[0] <= t <= w[1] for w in rep["left"]) and any(w[0] <= t <= w[1] for w in rep["right"])]
    settled = [t for t in both if sp[min(t, len(sp) - 1)] < 0.8]
    ev["plant_frame"] = int(settled[0]) if settled else None
    ev.setdefault("skid_frames", [])
    info = {"name": loop_name, "loop": bool(clip.get("loop")), "seconds": round((n - 1) / FPS, 3),
            "frames": n, "fps": FPS, "keys": nkeys, "source": clip.get("file"), "source_window_s": clip["_window_s"],
            "mirrored": bool(clip.get("mirror")), "note": clip.get("note", ""),
            "speed_up": clip.get("speed", 1.0), "hip_scale": round(rig_k, 4),
            "floor_fix_m": clip["_floor_fix"], "contact_lift_m": clip.get("_contact_lift"), "min_foot_m": clip["_min_foot"],
            "travel_fit": clip["_travel_fit"], "travel_m": clip["_travel"],
            "root": root_info, "contacts": {k: rep[k] for k in ("left", "right", "flat_left", "flat_right", "airborne")},
            "slide_cm": rep["slide_cm"], "slide_max_cm": rep["slide_max_cm"], "slide_windows": rep["slide_windows"], "end_foot": ("air" if clip.get("pingpong") else end_foot),
            "matched_trim": matched, "handoff": hand, "events": ev}
    report.append(info)
    if os.environ.get("LOCO_DEBUG"):
        np.save(os.path.join(os.path.dirname(P(cfg["out"])), name + ".feet.npy"), np.concatenate([Pfeet.reshape(n, 12), root_xy, pel], axis=1))
    print("CLIP", json.dumps({k: info[k] for k in ("name", "seconds", "frames", "travel_m", "travel_fit", "slide_max_cm", "end_foot", "matched_trim", "handoff")}))
    print("   root", json.dumps({k: root_info[k] for k in ("forward_m", "left_m", "yaw_deg", "speed_in_mps", "speed_out_mps")}),
          "contacts L", rep["left"], "R", rep["right"], "air", rep["airborne"])
    print("   slide", [w for w in rep["slide_windows"] if w[4] > 6])

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
json.dump({"clips": {r["name"]: r for r in report}, "reference_loops": REF_REPORT}, open(out + ".contacts.json", "w"), indent=1)
print("EXPORTED", out, len(made), "clips", os.path.getsize(out), "bytes")
