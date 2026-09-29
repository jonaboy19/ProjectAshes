"""Step 2: MediaPipe landmarks (npz from pose_extract.py) -> cleaned BVH (Y-up, +Z forward, T-pose rest, CMU-style joint names).

  python mocap_to_bvh.py out/clip_pose.npz out/clip.bvh [--height 1.75] [--fov 66] [--root blend|image|feet|none]
                         [--face first|travel|none|DEG] [--fps 30] [--no-foot-clean] [--report out/clip_report.json]

What it does (details: tools/anim/video_to_bvh/README.md):
  gap fill + outlier rejection + zero-lag One-Euro smoothing -> fixed bone lengths (no stretching) -> joint rotations
  (swing + elbow/knee-plane twist) -> foot-contact detection -> floor / root height from planted feet ->
  root translation (image projection + foot odometry) -> foot flattening on contact -> BVH.
"""
import argparse, json, math, os
import numpy as np
from bvhlib import write_bvh

# MediaPipe landmark ids
NOSE, L_EAR, R_EAR = 0, 7, 8
L_SH, R_SH, L_EL, R_EL, L_WR, R_WR = 11, 12, 13, 14, 15, 16
L_HIP, R_HIP, L_KN, R_KN, L_AN, R_AN = 23, 24, 25, 26, 27, 28
L_HEEL, R_HEEL, L_FI, R_FI = 29, 30, 31, 32
CORE = [L_SH, R_SH, L_EL, R_EL, L_WR, R_WR, L_HIP, R_HIP, L_KN, R_KN, L_AN, R_AN]


# ------------------------------------------------------------------ small math
def unit(v):
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-9)


def rotvec_to_mat(v):
    a = float(np.linalg.norm(v))
    if a < 1e-9:
        return np.eye(3)
    k = v / a
    K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return np.eye(3) + math.sin(a) * K + (1 - math.cos(a)) * K @ K


def mat_to_rotvec(R):
    c = float(np.clip((np.trace(R) - 1) / 2, -1, 1))
    a = math.acos(c)
    if a < 1e-9:
        return np.zeros(3)
    if math.pi - a < 1e-4:
        w, V = np.linalg.eigh((R + R.T) / 2)
        return V[:, -1] * a
    k = np.array([R[2, 1] - R[1, 2], R[0, 2] - R[2, 0], R[1, 0] - R[0, 1]]) / (2 * math.sin(a))
    return k * a


def swing(a, b):
    """Shortest rotation taking vector a to vector b."""
    a, b = unit(a), unit(b)
    c = float(np.clip(a @ b, -1, 1))
    ax = np.cross(a, b)
    s = float(np.linalg.norm(ax))
    if s < 1e-9:
        if c > 0:
            return np.eye(3)
        p = np.cross(a, [1, 0, 0])
        if np.linalg.norm(p) < 1e-3:
            p = np.cross(a, [0, 0, 1])
        return rotvec_to_mat(unit(p) * math.pi)
    return rotvec_to_mat(ax / s * math.atan2(s, c))


def axis_angle(axis, ang):
    return rotvec_to_mat(unit(axis) * ang)


def frame_from(x, y_hint):
    """Right-handed frame (columns x,y,z): x as given, y as close to y_hint as possible."""
    x = unit(x)
    z = unit(np.cross(x, y_hint))
    y = np.cross(z, x)
    return np.stack([x, y, z], axis=-1)


def smoothstep(a, b, x):
    t = float(np.clip((x - a) / (b - a), 0, 1))
    return t * t * (3 - 2 * t)


def rot_y_mat(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def slerp_mat(A, B, t):
    return A @ rotvec_to_mat(mat_to_rotvec(A.T @ B) * t)


# ------------------------------------------------------------------ filtering
def one_euro_pass(x, fps, mincut, beta, dcut=1.0):
    def alpha(c):
        tau = 1 / (2 * math.pi * c)
        return 1 / (1 + tau * fps)
    out = np.empty_like(x)
    out[0] = x[0]
    dx_hat = np.zeros_like(x[0])
    ad = alpha(dcut)
    for t in range(1, len(x)):
        dx = (x[t] - out[t - 1]) * fps
        dx_hat = ad * dx + (1 - ad) * dx_hat
        a = alpha(mincut + beta * np.abs(dx_hat))
        out[t] = a * x[t] + (1 - a) * out[t - 1]
    return out


def one_euro(x, fps, mincut=1.2, beta=6.0):
    """Zero-lag One-Euro: forward and backward pass averaged. x [T, ...]."""
    s = x.reshape(len(x), -1)
    f = one_euro_pass(s, fps, mincut, beta)
    b = one_euro_pass(s[::-1], fps, mincut, beta)[::-1]
    return ((f + b) / 2).reshape(x.shape)


def fill_gaps(x, ok):
    idx = np.arange(len(x))
    s = x.reshape(len(x), -1).copy()
    if ok.sum() == 0:
        raise SystemExit("no person detected in any frame")
    for c in range(s.shape[1]):
        s[:, c] = np.interp(idx, idx[ok], s[ok, c])
    return s.reshape(x.shape)


def reject_outliers(x, win=7, thr=0.35):
    """x [T,J,3]: replace samples that jump > thr metres away from the local median."""
    T = len(x)
    h = win // 2
    out = x.copy()
    n = 0
    for t in range(T):
        med = np.median(x[max(0, t - h):t + h + 1], axis=0)
        bad = np.linalg.norm(x[t] - med, axis=-1) > thr
        out[t][bad] = med[bad]
        n += int(bad.sum())
    return out, n


# ------------------------------------------------------------------ skeleton definition
JOINTS = ["Hips", "LowerBack", "Spine", "Spine1", "Neck", "Head",
          "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
          "RightShoulder", "RightArm", "RightForeArm", "RightHand",
          "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
          "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]
PARENT_NAME = {"LowerBack": "Hips", "Spine": "LowerBack", "Spine1": "Spine", "Neck": "Spine1", "Head": "Neck",
               "LeftShoulder": "Spine1", "LeftArm": "LeftShoulder", "LeftForeArm": "LeftArm", "LeftHand": "LeftForeArm",
               "RightShoulder": "Spine1", "RightArm": "RightShoulder", "RightForeArm": "RightArm", "RightHand": "RightForeArm",
               "LeftUpLeg": "Hips", "LeftLeg": "LeftUpLeg", "LeftFoot": "LeftLeg", "LeftToeBase": "LeftFoot",
               "RightUpLeg": "Hips", "RightLeg": "RightUpLeg", "RightFoot": "RightLeg", "RightToeBase": "RightFoot"}
J = {n: i for i, n in enumerate(JOINTS)}
PARENT = [-1] + [J[PARENT_NAME[n]] for n in JOINTS[1:]]


def build_rest(L):
    """Measured lengths -> T-pose offsets [J,3] (facing +Z, actor's left = +X) and end-site offsets."""
    off = np.zeros((len(JOINTS), 3))
    s = L["spine"]
    off[J["Hips"]] = (0, L["leg"], 0)
    off[J["LowerBack"]] = (0, 0.1 * s, 0)
    off[J["Spine"]] = (0, 0.3 * s, 0)
    off[J["Spine1"]] = (0, 0.3 * s, 0)
    off[J["Neck"]] = (0, 0.3 * s, 0)
    off[J["Head"]] = (0, L["neck"], 0)
    for side, sx in (("Left", 1), ("Right", -1)):
        off[J[side + "Shoulder"]] = (0, 0.3 * s, 0)
        off[J[side + "Arm"]] = (sx * L["sw"] / 2, 0, 0)
        off[J[side + "ForeArm"]] = (sx * L["uarm"], 0, 0)
        off[J[side + "Hand"]] = (sx * L["farm"], 0, 0)
        off[J[side + "UpLeg"]] = (sx * L["hw"] / 2, 0, 0)
        off[J[side + "Leg"]] = (0, -L["thigh"], 0)
        off[J[side + "Foot"]] = (0, -L["shin"], 0)
        off[J[side + "ToeBase"]] = (0, -L["ankle_h"], L["foot"])
    end = {J["Head"]: (0, L["head"], 0), J["LeftHand"]: (L["hand"], 0, 0), J["RightHand"]: (-L["hand"], 0, 0),
           J["LeftToeBase"]: (0, 0, L["toe"]), J["RightToeBase"]: (0, 0, L["toe"])}
    return off, end


def twist_to(R0, axis_dir, rest_normal, target_n, w):
    """Rotate R0 about axis_dir so that R0 @ rest_normal matches target_n (projected on the plane), weighted by w."""
    if w <= 0 or np.linalg.norm(target_n) < 1e-6:
        return R0
    a = unit(axis_dir)
    m = R0 @ rest_normal
    mp_ = m - a * (m @ a)
    tp_ = target_n - a * (target_n @ a)
    if np.linalg.norm(mp_) < 1e-6 or np.linalg.norm(tp_) < 1e-6:
        return R0
    mp_, tp_ = unit(mp_), unit(tp_)
    ang = math.atan2(float(a @ np.cross(mp_, tp_)), float(mp_ @ tp_))
    return axis_angle(a, ang * w) @ R0


# ------------------------------------------------------------------ main solve
def solve(d, height=1.75, fov=66.0, root_mode="blend", face="first", fps_out=None, foot_clean=True,
          mincut=1.2, beta=6.0, log=print):
    fps = float(d["fps"])
    W, H = int(d["width"]), int(d["height"])
    world = d["world"].copy()
    img = d["image"].copy()
    det = ~np.isnan(world[:, 0, 0])
    info = {"frames": int(len(world)), "no_person_frames": int((~det).sum())}
    world = fill_gaps(world, det)
    img = fill_gaps(img, det)
    # MediaPipe axes (x right, y down, z away from camera) -> world (X right, Y up, Z toward camera)
    P = world * np.array([1, -1, -1.0])
    P, nout = reject_outliers(P)
    info["outliers_fixed"] = nout
    P = one_euro(P, fps, mincut, beta)
    T = len(P)

    def dist(a, b):
        return float(np.median(np.linalg.norm(P[:, a] - P[:, b], axis=-1)))
    pelvis = (P[:, L_HIP] + P[:, R_HIP]) / 2
    neck = (P[:, L_SH] + P[:, R_SH]) / 2
    ears = (P[:, L_EAR] + P[:, R_EAR]) / 2
    Lm = {"hw": dist(L_HIP, R_HIP), "sw": dist(L_SH, R_SH),
          "uarm": (dist(L_SH, L_EL) + dist(R_SH, R_EL)) / 2, "farm": (dist(L_EL, L_WR) + dist(R_EL, R_WR)) / 2,
          "thigh": (dist(L_HIP, L_KN) + dist(R_HIP, R_KN)) / 2, "shin": (dist(L_KN, L_AN) + dist(R_KN, R_AN)) / 2,
          "spine": float(np.median(np.linalg.norm(neck - pelvis, axis=-1))),
          "foot": (dist(L_AN, L_FI) + dist(R_AN, R_FI)) / 2}
    Lm["foot"] = min(max(Lm["foot"] * 0.8, 0.10), 0.18)
    Lm["ankle_h"] = 0.085
    Lm["toe"] = 0.06
    Lm["hand"] = 0.09
    Lm["neck"] = float(np.median(np.linalg.norm(ears - neck, axis=-1))) * 0.9
    Lm["head"] = 0.20
    Lm["leg"] = Lm["thigh"] + Lm["shin"] + Lm["ankle_h"]
    est_h = Lm["leg"] + Lm["spine"] + Lm["neck"] + Lm["head"]
    sc = height / est_h if height else 1.0
    for k in Lm:
        Lm[k] *= sc
    P = P * sc
    pelvis, neck, ears = pelvis * sc, neck * sc, ears * sc
    info["scale_applied"] = round(sc, 4)
    info["est_height_m"] = round(est_h, 3)
    info["lengths_m"] = {k: round(v, 3) for k, v in Lm.items()}
    off, end_sites = build_rest(Lm)

    # ---- joint orientations
    NJ = len(JOINTS)
    Rg = np.zeros((T, NJ, 3, 3))
    nrest_arm = {"Left": np.array([0, -1.0, 0]), "Right": np.array([0, 1.0, 0])}
    rest_arm = {"Left": np.array([1.0, 0, 0]), "Right": np.array([-1.0, 0, 0])}
    nrest_leg = np.array([1.0, 0, 0])
    foot_rest = unit(np.array([0, -Lm["ankle_h"], Lm["foot"]]))
    down = np.array([0, -1.0, 0])
    head_pitch = []
    for t in range(T):
        p = P[t]
        Rh = frame_from(p[L_HIP] - p[R_HIP], neck[t] - pelvis[t])
        Rc = frame_from(p[L_SH] - p[R_SH], neck[t] - pelvis[t])
        Rq = rotvec_to_mat(mat_to_rotvec(Rh.T @ Rc) / 3.0)
        Rg[t, 0] = Rh
        Rg[t, J["LowerBack"]] = Rh @ Rq
        Rg[t, J["Spine"]] = Rg[t, J["LowerBack"]] @ Rq
        Rg[t, J["Spine1"]] = Rg[t, J["Spine"]] @ Rq
        ex = p[L_EAR] - p[R_EAR]
        Rhd = frame_from(ex, np.cross(p[NOSE] - ears[t], unit(ex)))
        Rg[t, J["Head"]] = Rhd
        head_pitch.append(mat_to_rotvec(Rg[t, J["Spine1"]].T @ Rhd))
    med = float(np.median(np.array(head_pitch)[:, 0]))          # neutral head: assume level on average
    corr = axis_angle(np.array([1.0, 0, 0]), -med)
    for t in range(T):
        p = P[t]
        Rg[t, J["Head"]] = Rg[t, J["Head"]] @ corr
        Rc, Rhd = Rg[t, J["Spine1"]], Rg[t, J["Head"]]
        Rg[t, J["Neck"]] = Rc @ rotvec_to_mat(mat_to_rotvec(Rc.T @ Rhd) * 0.4)
        for side, SH, EL, WR, HIP, KN, AN, FI in (("Left", L_SH, L_EL, L_WR, L_HIP, L_KN, L_AN, L_FI),
                                                  ("Right", R_SH, R_EL, R_WR, R_HIP, R_KN, R_AN, R_FI)):
            rd = rest_arm[side]
            cl = swing(Rc @ rd, p[SH] - neck[t]) @ Rc
            Rg[t, J[side + "Shoulder"]] = cl
            d1, d2 = p[EL] - p[SH], p[WR] - p[EL]
            w = smoothstep(math.radians(15), math.radians(40), math.acos(float(np.clip(unit(d1) @ unit(d2), -1, 1))))
            n = np.cross(d1, d2)
            Ru = twist_to(swing(cl @ rd, d1) @ cl, d1, nrest_arm[side], n, w)
            Rf = twist_to(swing(Ru @ rd, d2) @ Ru, d2, nrest_arm[side], n, w)
            Rg[t, J[side + "Arm"]] = Ru
            Rg[t, J[side + "ForeArm"]] = Rf
            Rg[t, J[side + "Hand"]] = Rf
            Rh = Rg[t, 0]
            e1, e2 = p[KN] - p[HIP], p[AN] - p[KN]
            w = smoothstep(math.radians(10), math.radians(30), math.acos(float(np.clip(unit(e1) @ unit(e2), -1, 1))))
            n = np.cross(e1, e2)
            Rt = twist_to(swing(Rh @ down, e1) @ Rh, e1, nrest_leg, n, w)
            Rs = twist_to(swing(Rt @ down, e2) @ Rt, e2, nrest_leg, n, w)
            Rg[t, J[side + "UpLeg"]] = Rt
            Rg[t, J[side + "Leg"]] = Rs
            Rft = swing(Rs @ foot_rest, p[FI] - p[AN]) @ Rs
            Rg[t, J[side + "Foot"]] = Rft
            Rg[t, J[side + "ToeBase"]] = Rft

    # ---- image-based root (weak perspective scale from metric 3D vs 2D landmarks)
    bottoms = np.stack([np.minimum(P[:, L_HEEL, 1], P[:, L_FI, 1]), np.minimum(P[:, R_HEEL, 1], P[:, R_FI, 1])], 1)
    fpx = (max(W, H) / 2) / math.tan(math.radians(fov) / 2)
    px = (img[:, :, 0] - 0.5) * W
    py = (img[:, :, 1] - 0.5) * H
    hip_px = (px[:, L_HIP] + px[:, R_HIP]) / 2
    hip_py = (py[:, L_HIP] + py[:, R_HIP]) / 2
    num = np.zeros(T)
    den = np.zeros(T)
    for j in CORE:
        rx, ry = px[:, j] - hip_px, py[:, j] - hip_py
        num += rx * world[:, j, 0] * sc + ry * world[:, j, 1] * sc
        den += (world[:, j, 0] * sc) ** 2 + (world[:, j, 1] * sc) ** 2
    s_ppm = np.maximum(num / np.maximum(den, 1e-6), 1e-3)          # pixels per metre at the hips
    s_ppm = np.exp(one_euro(np.log(s_ppm)[:, None], fps, 0.6, 0.5)[:, 0])
    Zc = fpx / s_ppm                                                 # camera depth of the hips (m)
    hpx = one_euro(np.stack([hip_px, hip_py], 1), fps, 1.5, 4.0)
    img_root = np.stack([hpx[:, 0] / s_ppm, -hpx[:, 1] / s_ppm, -Zc], 1)      # X right, Y up, Z toward camera
    info["camera_dist_m"] = [round(float(Zc.min()), 2), round(float(Zc.max()), 2)]

    # ---- foot contacts
    contact = np.zeros((T, 2), bool)
    joint_ank = (L_AN, R_AN)
    for si in range(2):
        ank_w = P[:, joint_ank[si]] + (img_root if root_mode != "none" else 0)
        vel = np.linalg.norm(np.gradient(one_euro(ank_w, fps, 2.0, 0.5), axis=0), axis=-1) * fps
        contact[:, si] = vel < 0.45
    win = int(fps * 1.0)
    for t in range(T):
        lo = float(np.min(bottoms[max(0, t - win):t + win + 1]))
        for si in range(2):
            if bottoms[t, si] - lo > 0.09:
                contact[t, si] = False

    def morph(c, n=3):
        c = c.copy()
        i = 0
        while i < len(c):
            j = i
            while j < len(c) and c[j] == c[i]:
                j += 1
            if (j - i) < n and i > 0 and j < len(c):
                c[i:j] = c[i - 1]
            i = j
        return c
    for si in range(2):
        contact[:, si] = morph(morph(contact[:, si]))
    if not foot_clean:
        contact[:] = False
    info["contact_frac"] = [round(float(contact[:, 0].mean()), 2), round(float(contact[:, 1].mean()), 2)]

    # ---- root height: planted feet define the floor; image vertical bridges flight phases
    hy_contact = np.full(T, np.nan)
    for t in range(T):
        ys = [-bottoms[t, si] for si in range(2) if contact[t, si]]
        if ys:
            hy_contact[t] = float(np.mean(ys))
    okc = ~np.isnan(hy_contact)
    if okc.sum() >= 3:
        off_y = np.interp(np.arange(T), np.where(okc)[0], (hy_contact - img_root[:, 1])[okc])
        hips_y = img_root[:, 1] + off_y
    else:
        hips_y = -bottoms.min(1)
    hips_y = one_euro(hips_y[:, None], fps, 2.0, 2.0)[:, 0]
    hips_y = np.maximum(hips_y, -bottoms.min(1))                 # no foot below the floor

    # ---- root horizontal: image projection, refined by foot odometry
    root_xz = img_root[:, [0, 2]].copy()
    if root_mode == "none":
        root_xz[:] = 0
    elif root_mode in ("feet", "blend") and contact.any():
        ank = np.stack([P[:, L_AN][:, [0, 2]], P[:, R_AN][:, [0, 2]]], 1)      # [T, feet, xz]
        dr = np.gradient(ank, axis=0)
        v_img = np.gradient(img_root[:, [0, 2]], axis=0)
        vfull = v_img.copy()
        for t in range(T):
            cs = [si for si in range(2) if contact[t, si]]
            if cs:
                vfull[t] = -np.mean([dr[t, si] for si in cs], axis=0)     # planted foot is stationary
        path = np.cumsum(vfull, axis=0)
        path += img_root[0, [0, 2]] - path[0]
        if root_mode == "blend":                                          # keep the image path's slow trend, drop its jitter
            k = int(fps * 2)
            resid = img_root[:, [0, 2]] - path
            pad = np.concatenate([np.repeat(resid[:1], k, 0), resid, np.repeat(resid[-1:], k, 0)])
            ker = np.ones(2 * k + 1) / (2 * k + 1)
            path = path + np.stack([np.convolve(pad[:, c], ker, "valid") for c in range(2)], 1)
        root_xz = path
    root = np.stack([root_xz[:, 0], hips_y, root_xz[:, 1]], 1)

    # ---- facing normalisation (yaw about Y)
    hipfwd = np.stack([Rg[:, 0, 0, 2], Rg[:, 0, 2, 2]], 1)
    n0 = max(5, min(T, int(fps * 0.5)))
    yaw_deg = 0.0
    if face == "first":
        m = np.median(hipfwd[:n0], axis=0)
        yaw_deg = math.degrees(math.atan2(m[0], m[1]))
    elif face == "travel":
        tr = root_xz[-1] - root_xz[0]
        if np.linalg.norm(tr) > 0.3:
            yaw_deg = math.degrees(math.atan2(tr[0], tr[1]))
        else:
            m = np.median(hipfwd[:n0], axis=0)
            yaw_deg = math.degrees(math.atan2(m[0], m[1]))
    elif face not in ("none", None):
        yaw_deg = float(face)
    Ry = rot_y_mat(-math.radians(yaw_deg))
    info["facing_yaw_removed_deg"] = round(yaw_deg, 1)
    Rg = np.matmul(Ry, Rg)
    root = root @ Ry.T
    root[:, [0, 2]] -= root[0, [0, 2]]

    # ---- foot flattening while planted
    if foot_clean:
        for si, side in enumerate(("Left", "Right")):
            w = one_euro(contact[:, si].astype(float)[:, None], fps, 3.0, 0.0)[:, 0]
            for t in range(T):
                if w[t] < 0.02:
                    continue
                Rs = Rg[t, J[side + "Leg"]]
                cur = Rg[t, J[side + "Foot"]] @ foot_rest
                hz = np.array([cur[0], 0, cur[2]])
                if np.linalg.norm(hz) < 1e-3:
                    continue
                flat = unit(unit(hz) * Lm["foot"] + np.array([0, -Lm["ankle_h"], 0]))
                tgt = unit(cur * (1 - w[t]) + flat * w[t])
                Rf_ = swing(Rs @ foot_rest, tgt) @ Rs
                Rg[t, J[side + "Foot"]] = Rf_
                Rg[t, J[side + "ToeBase"]] = Rf_

    # ---- local rotations
    Rl = np.zeros_like(Rg)
    for j in range(NJ):
        pj = PARENT[j]
        Rl[:, j] = Rg[:, j] if pj < 0 else np.matmul(np.transpose(Rg[:, pj], (0, 2, 1)), Rg[:, j])

    out_fps = fps_out or (30.0 if (fps > 45 or abs(fps - 30) < 1) else fps)
    if abs(out_fps - fps) > 0.5:
        n_out = int(round((T - 1) / fps * out_fps)) + 1
        ti = np.arange(n_out) / out_fps * fps
        i0 = np.clip(np.floor(ti).astype(int), 0, T - 1)
        i1 = np.clip(i0 + 1, 0, T - 1)
        fr = ti - i0
        root = root[i0] * (1 - fr)[:, None] + root[i1] * fr[:, None]
        newR = np.zeros((n_out,) + Rl.shape[1:])
        for k in range(n_out):
            for j in range(NJ):
                newR[k, j] = slerp_mat(Rl[i0[k], j], Rl[i1[k], j], fr[k])
        Rl = newR
        contact = contact[i0]
    return dict(off=off, end=end_sites, root=root, Rl=Rl, fps=out_fps, contact=contact, info=info)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("npz")
    ap.add_argument("bvh")
    ap.add_argument("--height", type=float, default=1.75, help="actor height (m); only scales the root travel, the retargeter rescales to the game rig")
    ap.add_argument("--fov", type=float, default=66.0, help="camera field of view (deg) along the LONG image side; phone main camera ~ 66-70")
    ap.add_argument("--root", default="blend", choices=["blend", "image", "feet", "none"])
    ap.add_argument("--face", default="first", help="first | travel | none | degrees: yaw applied so the actor faces +Z")
    ap.add_argument("--fps", type=float, default=0, help="output fps (default 30)")
    ap.add_argument("--no-foot-clean", action="store_true")
    ap.add_argument("--mincut", type=float, default=1.2, help="One-Euro min cutoff Hz: lower = smoother when slow")
    ap.add_argument("--beta", type=float, default=6.0, help="One-Euro speed coefficient: higher = less lag when fast")
    ap.add_argument("--report")
    a = ap.parse_args()
    d = dict(np.load(a.npz))
    r = solve(d, a.height, a.fov, a.root, a.face, a.fps or None, not a.no_foot_clean, a.mincut, a.beta)
    write_bvh(a.bvh, JOINTS, PARENT, list(r["off"]), dict(r["end"]), r["root"], r["Rl"], r["fps"])
    r["info"]["out_frames"] = int(len(r["root"]))
    r["info"]["out_fps"] = r["fps"]
    print(json.dumps(r["info"], indent=1))
    if a.report:
        json.dump(r["info"], open(a.report, "w"), indent=1)
    np.savez_compressed(os.path.splitext(a.bvh)[0] + "_contacts.npz", contact=r["contact"])


if __name__ == "__main__":
    main()
