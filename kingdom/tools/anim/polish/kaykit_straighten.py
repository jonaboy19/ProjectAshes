# KayKit clip cleanup on the UAL skeleton: floor fix + knee straightening (pelvis raise + two-bone leg IK). Pure numpy, no Blender.
#
# README
# ------
# KayKit characters are chibi (short legs, long arms). The retarget (tools/anim/free2/retarget_free2.py) scales the hips by hip_scale
# 3.12 so most stances stand with 0.9-1.0 leg straightness, but a few clips still stand in a deep knee bend (fighting stance,
# skeleton idle / walk) or hover / sink a few cm relative to the floor.  Two operations, both keep the arms untouched:
#
#   floor      constant pelvis shift so the lowest sole point of the clip lands on the floor (z=0, ball bone rest height 0.0152).
#              Fixes feet that sink (Crouch idle -8 cm) or hover (idles 3-5 cm) without changing any joint angle.
#   straighten raise the pelvis by dy and re-solve both legs with a two-bone IK to the ORIGINAL ankle world positions, so planted feet
#              stay planted (no sliding, foot orientation kept) and only the knees open.  dy is chosen from the frames where a foot is
#              planted so that their median hip-ankle / leg length reaches --target (default 0.94), capped by --max-dy (default 0.14 m).
#              Torso, arms and hands rise with the pelvis (rigid), the legs are the only thing that changes.
#              Frames where the requested ankle is out of reach are clamped by leg_ik (leg fully straight, ankle a few mm short).
#
#   python kaykit_straighten.py <lib.glb> --clips=A,B [--floor] [--straighten] [--target=0.94] [--max-dy=0.14] [--dry]
# The GLB and its *.clips.json sidecar are rewritten in place (tracks pelvis.translation and thigh/calf/foot rotations of both legs are
# replaced by dense 30 fps tracks, all other tracks untouched).  Use kaykit_polish.py for the whole KayKit batch (it calls this module).
import os, sys, json
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, ".."))
from glb_fk import Rig, replace_channels, leg_ik, FPS   # noqa: E402
from glb_edit_clips import Glb, clip_len                 # noqa: E402

BALL_REST_Y = 0.0152          # ball bone height of the mannequin standing on the floor
ANKLE_REST_Y = 0.1037
LEG_LEN = 0.7955              # thigh + calf (0.4 + 0.3955 measured on the UAL rest pose)


def leg_len(rig):
    P, _ = rig.fk(rig.rest_t[None], rig.rest_q[None])
    I = rig.idx
    return float(np.linalg.norm(P[0, I["calf_l"]] - P[0, I["thigh_l"]]) + np.linalg.norm(P[0, I["foot_l"]] - P[0, I["calf_l"]]))


def dense_clip(rig, chans):
    nf = int(round(clip_len(chans) * FPS))
    T, Q = rig.dense(chans, nf)
    return T, Q


def planted_mask(P, rig, s):
    I = rig.idx
    return (P[:, I["foot_" + s], 1] < ANKLE_REST_Y + 0.06) & (P[:, I["ball_" + s], 1] < BALL_REST_Y + 0.05)


def straightness(P, rig):
    """(F,2) hip-ankle distance / leg length per leg (l, r)"""
    I = rig.idx
    L = leg_len(rig)
    return np.stack([np.linalg.norm(P[:, I["foot_" + s]] - P[:, I["thigh_" + s]], axis=-1) / L for s in "lr"], axis=1)


def clip_stats(rig, T, Q):
    P, _ = rig.fk(T, Q)
    I = rig.idx
    st = straightness(P, rig)
    pm = np.stack([planted_mask(P, rig, s) for s in "lr"], axis=1)
    both = pm.all(axis=1)
    lowest = np.minimum(P[:, I["ball_l"], 1], P[:, I["ball_r"], 1]).min()
    return {"leg_straight_planted_mean": float(st[pm].mean()) if pm.any() else None,
            "leg_straight_both_min": float(st[both].min()) if both.any() else None,
            "leg_straight_mean": float(st.mean()), "lowest_ball_y": float(lowest), "planted_frac": float(pm.any(axis=1).mean())}


def floor_shift(rig, T, Q, ref="min"):
    """dy (world up) to move the whole clip so its lowest ball point sits at BALL_REST_Y"""
    P, _ = rig.fk(T, Q)
    I = rig.idx
    low = np.minimum(P[:, I["ball_l"], 1], P[:, I["ball_r"], 1])
    return BALL_REST_Y - float(low.min() if ref == "min" else np.percentile(low, 5))


def raise_pelvis(rig, T, dy):
    """pelvis local translation z is world up (root is rotated -90 deg about X in the UAL rig)"""
    T = T.copy()
    T[:, rig.idx["pelvis"], 2] += dy
    return T


def solve_dy(rig, T, Q, target=0.94, max_dy=0.14):
    """raise needed so the median planted hip-ankle / leg length reaches `target` (0 if already there)"""
    P, _ = rig.fk(T, Q)
    I = rig.idx
    L = leg_len(rig)
    vals = []
    for s in "lr":
        m = planted_mask(P, rig, s)
        if not m.any():
            continue
        D = P[m, I["thigh_" + s]] - P[m, I["foot_" + s]]
        vals.append(D)
    if not vals:
        return 0.0
    D = np.concatenate(vals)
    cur = np.median(np.linalg.norm(D, axis=-1)) / L
    if cur >= target:
        return 0.0
    # |D + dy*up| for the median vector, monotone in dy
    med = np.median(D, axis=0)
    a, b = 0.0, max_dy
    for _ in range(40):
        m_ = 0.5 * (a + b)
        if np.linalg.norm(med + np.array([0, m_, 0])) / L < target:
            a = m_
        else:
            b = m_
    return min(max_dy, 0.5 * (a + b))


def planted_weight(rig, T, Q, half=4, circular=False):
    """(F,) 0..1: 1 while any foot is planted, faded over +-`half` frames (box blur) so airborne / crouch-launch phases are not lifted"""
    P, _ = rig.fk(T, Q)
    m = np.stack([planted_mask(P, rig, s) for s in "lr"], axis=1).any(axis=1).astype(float)
    k = np.ones(2 * half + 1) / (2 * half + 1)
    if circular:      # loop clips: wrap so first and last frame get the same lift
        pad = np.concatenate([m[-half - 1:-1], m, m[1:half + 1]])
    else:
        pad = np.concatenate([np.full(half, m[0]), m, np.full(half, m[-1])])
    return np.convolve(pad, k, mode="valid")


def straighten(rig, T, Q, dy):
    """pelvis up by dy (scalar or per-frame array), both ankles pinned to their source world position, knees re-solved by leg_ik"""
    I = rig.idx
    P0, _ = rig.fk(T, Q)
    targets = {s: P0[:, I["foot_" + s]].copy() for s in "lr"}
    T2 = raise_pelvis(rig, T, dy)
    Q2 = Q.copy()
    w = np.ones(T.shape[0])
    for s in "lr":
        P, R = rig.fk(T2, Q2)
        leg_ik(rig, T2, Q2, s, targets[s], w, P=P, R=R, keep_foot_world=True)
    return T2, Q2


def commit(rig, chans, T, Q, with_pelvis=True, extra_t=()):
    I = rig.idx
    nodes_q = [I[n + s] for s in "lr" for n in ("thigh_", "calf_", "foot_")]
    new = rig.to_chans(T, Q, nodes_t=([I["pelvis"]] if with_pelvis else []) + list(extra_t), nodes_q=nodes_q)
    return replace_channels(chans, new)


def update_sidecar(path, name, **kw):
    side = path + ".clips.json"
    if not os.path.exists(side):
        return
    rows = json.load(open(side, encoding="utf-8"))
    for r in rows:
        if r["name"] == name:
            r.update(kw)
    json.dump(rows, open(side, "w", encoding="utf-8"), indent=1)


def process(path, clips, do_floor, do_straight, target, max_dy, dry=False):
    g = Glb(path)
    rig = Rig(g)
    anims = g.anims()
    report = {}
    for name in clips:
        chans = anims[name]
        T, Q = dense_clip(rig, chans)
        before = clip_stats(rig, T, Q)
        dy_s = dy_f = 0.0
        if do_straight:
            dy_s = solve_dy(rig, T, Q, target, max_dy)
            if dy_s > 0.005:
                T, Q = straighten(rig, T, Q, dy_s * planted_weight(rig, T, Q))
            else:
                dy_s = 0.0
        if do_floor:
            dy_f = floor_shift(rig, T, Q)
            if abs(dy_f) > 0.004:
                T = raise_pelvis(rig, T, dy_f)
            else:
                dy_f = 0.0
        after = clip_stats(rig, T, Q)
        report[name] = {"before": before, "after": after, "raise_m": round(dy_s, 3), "floor_shift_m": round(dy_f, 3)}
        if not dry and (dy_s or dy_f):
            commit(rig, chans, T, Q)
            update_sidecar(path, name, straighten_raise_m=round(dy_s, 3), floor_shift_m=round(dy_f, 3),
                           keys=int(sum(len(c["t"]) for c in chans)))
    if not dry:
        g.write(anims)
    return report


if __name__ == "__main__":
    a = [x for x in sys.argv[1:] if not x.startswith("--")]
    opt = {x[2:].split("=")[0]: (x.split("=")[1] if "=" in x else "1") for x in sys.argv[1:] if x.startswith("--")}
    rep = process(a[0], opt["clips"].split(","), "floor" in opt, "straighten" in opt, float(opt.get("target", 0.94)),
                  float(opt.get("max-dy", 0.14)), "dry" in opt)
    print(json.dumps(rep, indent=1))
