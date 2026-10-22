# Polish of the CMU-mocap acrobatics library (UAL_Free_Acrobatics.glb + sidecar), pure numpy, reproducible from the git HEAD version:
#   python cmu_acro_fix.py [--src orig.glb] [--dst out.glb] [--only A,B]   (default: read+write the repo GLB in place, sidecar too)
# Per clip (see CLIPS): trim static holds / start pops / walking tails, rebase the root to the origin, straighten toe bones that
# curl below the floor, ground the character (no float, no sinking: per-frame vertical offset from the planted sole / palm points),
# optional foot pin (two-bone leg IK) and delete/rename.  The review that led to these choices is docs/anim/free_library/frames/polish/_fragments/acrobatics.md.
import os, sys, json, argparse
import numpy as np
from cmu_acro_lib import *   # noqa
from glb_edit_clips import trim_channel
import cmu_acro_splice
from cmu_acro_ik import limb_ik

BUILDERS = {"handstand_kicks": cmu_acro_splice.handstand_kicks}

# ------------------------------------------------------------------ per clip configuration
# trim = (first_frame, last_frame) of the ORIGINAL 30 fps clip (inclusive).  ground = floor-offset pass on/off.
CLIPS = {
    "MA_Acro_HandSpinKick":        dict(trim=(12, 114)),
    "MA_Acro_Cartwheel_A":         dict(trim=(0, 76)),
    "MA_Acro_Cartwheel_B":         dict(trim=(0, 72)),
    "MA_Acro_Cartwheel_C":         dict(trim=(0, 78)),
    "MA_Acro_Cartwheel_D":         dict(trim=(6, 108)),
    "MA_Acro_Backflip_A":          dict(trim=(0, 44)),
    "MA_Acro_Backflip_B":          dict(trim=(8, 46), unwind=20),
    "MA_Acro_Backflip_C":          dict(trim=(4, 40)),
    "MA_Acro_BackflipBackOnHands": dict(trim=(3, 63)),
    "MA_Acro_Somersault_Back":     dict(trim=(6, 105)),
    "MA_Acro_Handspring":          dict(trim=(1, 42)),
    "MA_Acro_FlipForward_Hands":   dict(trim=(0, 45)),
    "MA_Acro_FrontHandFlip_B":     dict(trim=(30, 90)),
    "MA_Acro_SideFlip":            dict(trim=(19, 69)),
    "MA_Acro_KickFlip":            dict(trim=(0, 78)),
    "MA_Acro_HandstandKicks":      dict(build="handstand_kicks", note="cmu_acro_splice.py: stand -> handstand + kicks, entry played backwards to stand"),
}
DELETE = [   # rejected, see docs/anim/free_library/frames/polish/_fragments/acrobatics.md
    "MA_Acro_Cartwheel_E",         # run-in-place with 8 m/s foot skating, then a wobbly cartwheel
    "MA_Acro_Flip_A",              # 5.5 s meander: idle, stumbling steps, twisting aerial, ends mid-stagger turned 75 degrees
    "MA_Acro_FrontHandFlip_A",     # truncated take: ends in a handstand, no landing (FrontHandFlip_B is the complete one)
    "MA_Acro_MonkeyBackflip",      # truncated take: crawl then backflip that ends inverted on the hands, 4.9 m/s foot skating
]
RENAME = {}


def gauss(a, sigma):
    if sigma <= 0:
        return a
    r = int(np.ceil(sigma * 3))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2); k /= k.sum()
    ap = np.pad(a, (r, r), mode="edge")
    return np.convolve(ap, k, mode="valid")


def maxfilt(a, r):
    ap = np.pad(a, (r, r), mode="edge")
    return np.max([ap[i:i + len(a)] for i in range(2 * r + 1)], axis=0)


def set_pelvis_world(c, newP):
    """write pelvis local translation so that the pelvis lands at newP (world)"""
    I = c.rig.idx
    Rroot = c.R[:, I["root"]]
    c.T[:, I["pelvis"]] = qrot(qconj(Rroot), newP - c.P[:, I["root"]])
    c.refk()


def toe_fix(c):
    """toe (ball) bones curl 40-70 degrees below the floor in the retarget: blend them back towards the rest pose until the toe tip
    is not below the floor"""
    I = c.rig.idx; rig = c.rig
    for s in "lr":
        b, f, leaf = I["ball_" + s], I["foot_" + s], I["ball_leaf_" + s]
        off = rig.rest_t[leaf]
        Qb = c.Q[:, b].copy(); Q0 = np.broadcast_to(rig.rest_q[b], Qb.shape)
        Rf = c.R[:, f]
        Pb = c.P[:, b]
        def tip(q):
            return (Pb + qrot(qmul(Rf, q), off))[:, 1]
        bad = tip(Qb) < 0.0
        if not bad.any():
            continue
        lo = np.zeros(len(Qb)); hi = np.ones(len(Qb))
        for _ in range(12):
            mid = (lo + hi) / 2
            ok = tip(qslerp(Q0, Qb, mid[:, None])) >= 0.0
            lo = np.where(ok, mid, lo); hi = np.where(ok, hi, mid)
        sc = np.where(bad, lo, 1.0)
        sc = np.minimum(sc, gauss(sc, 1.0) + 0.0)           # smooth, never above the safe value
        c.Q[:, b] = qslerp(Q0, Qb, sc[:, None])
    c.refk()


PLANT = ("toe", "ball", "heel", "palm", "fing")


def ground_offsets(c, planted_h=0.10, target=0.006, vy_max=0.8, hs_max=2.5):
    """vertical offset (m, positive = lower the character) per frame from the planted sole / palm points"""
    pts = c.points()
    names = [k for k in pts if k.split("_")[0] in PLANT]
    H = np.stack([pts[k][:, 1] for k in names], 1)
    hmin = H.min(1); arg = H.argmin(1)
    F = len(hmin)
    vy = np.zeros((F, len(names))); hs = np.zeros((F, len(names)))
    for j, k in enumerate(names):
        p = pts[k]
        d = np.gradient(p, axis=0) * FPS
        vy[:, j] = np.abs(d[:, 1]); hs[:, j] = np.hypot(d[:, 0], d[:, 2])
    pl = np.array([(hmin[f] < planted_h) and vy[f, arg[f]] < vy_max and hs[f, arg[f]] < hs_max for f in range(F)])
    s = np.zeros(F)
    if pl.any():
        idx = np.where(pl)[0]
        s = np.interp(np.arange(F), idx, hmin[idx] - target)
    return np.clip(s, -0.10, 0.12), pl


def penetration_lift(c, tol=0.0):
    cl = c.clearance()
    m = np.min([v for v in cl.values()], axis=0)
    return np.maximum(0.0, tol - m)


def ground(c, sigma=2.0, rounds=2):
    I = c.rig.idx
    for _ in range(rounds):
        s, pl = ground_offsets(c)
        s = gauss(s, sigma)
        newP = c.P[:, I["pelvis"]].copy(); newP[:, 1] -= s
        set_pelvis_world(c, newP)
    lift = penetration_lift(c)
    lift = np.maximum(lift, gauss(maxfilt(lift, 2), 1.0))
    newP = c.P[:, I["pelvis"]].copy(); newP[:, 1] += lift
    set_pelvis_world(c, newP)
    return pl


def _plant_segments(h, sp, hthr, vthr, minlen=4):
    m = (h < hthr) & (sp < vthr)
    m2 = m.copy()
    for i in range(1, len(m) - 1):                      # close one-frame gaps
        if not m[i] and m[i - 1] and m[i + 1]:
            m2[i] = True
    return segments(m2, minlen)


def pin_limbs(c, feet=True, hands=True, hthr=0.03, vthr=0.9, maxslide=0.30, ramp=3):
    """lock the ankle / wrist of every planted segment (sole / palm on the floor, hardly moving) at the segment mean position with
    two-bone IK, so planted feet and hands do not creep.  Segments that slide by more than `maxslide` (rolls, skids) are left alone."""
    I = c.rig.idx
    pts = c.points()
    F = c.nf + 1
    changed = []
    jobs = []
    for sd in "lr":
        if feet:
            jobs.append((("thigh_" + sd, "calf_" + sd, "foot_" + sd), ("toe_" + sd, "ball_" + sd, "heel_" + sd)))
        if hands:
            jobs.append((("upperarm_" + sd, "lowerarm_" + sd, "hand_" + sd), ("palm_" + sd, "fing_" + sd)))
    n_pinned = 0
    for chain, soles in jobs:
        end = c.P[:, I[chain[2]]]
        h = np.min([pts[n][:, 1] for n in soles], axis=0)
        sp = np.hypot(*(np.gradient(end, axis=0)[:, [0, 2]].T)) * FPS
        tgt = end.copy(); w = np.zeros(F)
        for a, b in _plant_segments(h, sp, hthr, vthr):
            xz = end[a:b + 1][:, [0, 2]]
            mean = xz.mean(0)
            if np.max(np.linalg.norm(xz - mean, axis=1)) > maxslide / 2:
                continue
            tgt[a:b + 1, 0] = mean[0]; tgt[a:b + 1, 2] = mean[1]
            i = np.arange(a, b + 1)
            w[a:b + 1] = np.clip(np.minimum(i - a + 1, b - i + 1) / float(ramp), 0, 1)
            n_pinned += 1
        if w.any():
            limb_ik(c.rig, c.T, c.Q, chain, tgt, w, P=c.P, R=c.R)
            c.refk()
            changed += [I[n] for n in chain]
    return changed, n_pinned


def rebase_root(c):
    """the clip starts at the world origin (horizontal root translation of frame 0 removed)"""
    I = c.rig.idx
    r = I["root"]
    c.T[:, r, 0] -= c.T[0, r, 0]; c.T[:, r, 2] -= c.T[0, r, 2]
    c.refk()


def unwind_yaw(c, f0, target_deg=None):
    """turn the whole character about the vertical through the pelvis, ramping from 0 at frame f0 to the angle that brings the final
    facing back to the start facing (root rotation + root translation are rewritten, so the planted feet pivot instead of skating)"""
    I = c.rig.idx
    r = I["root"]
    fa = c.facing()
    d = (fa[-1] - fa[0] + 180) % 360 - 180
    ang = -d if target_deg is None else target_deg
    F = c.nf + 1
    w = np.clip((np.arange(F) - f0) / max(1.0, (F - 1 - f0)), 0, 1)
    w = w * w * (3 - 2 * w)
    T0, Q0 = c.T.copy(), c.Q.copy()
    pv = c.P[:, I["pelvis"]].copy(); pv[:, 1] = T0[:, r, 1]
    for sign in (1.0, -1.0):
        qy = qaxis(UP, np.radians(sign * ang) * w)
        c.T, c.Q = T0.copy(), Q0.copy()
        c.T[:, r] = pv + qrot(qy, T0[:, r] - pv)
        c.Q[:, r] = qnorm(qmul(qy, Q0[:, r]))
        c.refk()
        if abs((c.facing()[-1] - fa[0] + 180) % 360 - 180) < 8:
            return sign * ang
    raise RuntimeError("unwind_yaw: could not reach the start facing")


def process(rig, chans, cfg):
    ch = [dict(node=x["node"], path=x["path"], t=x["t"].copy(), v=x["v"].copy()) for x in chans]
    if cfg.get("build"):
        ch = BUILDERS[cfg["build"]](rig, ch, **cfg.get("build_args", {}))
    if cfg.get("trim"):
        a, b = cfg["trim"]
        end = clip_len(ch)
        t0, t1 = a / FPS, min(b / FPS, end)
        for x in ch:
            trim_channel(x, t0, t1)
    c = Clip(rig, ch)
    I = rig.idx
    changed_t = [I["root"], I["pelvis"]]
    changed_q = [I["ball_l"], I["ball_r"]]
    toe_fix(c)
    rebase_root(c)
    if cfg.get("unwind") is not None:
        unwind_yaw(c, cfg["unwind"])
        changed_t.append(I["root"]); changed_q.append(I["root"])
    if cfg.get("ground", True):
        c.pl = ground(c)
    if cfg.get("pin", True):
        pc, npin = pin_limbs(c)
        changed_q += pc
    new = c.rig.to_chans(c.T, c.Q, nodes_t=changed_t, nodes_q=changed_q)
    replace_channels(ch, new)
    return ch, c


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=GLB); ap.add_argument("--dst", default=None); ap.add_argument("--only", default=None)
    o = ap.parse_args()
    dst = o.dst or o.src
    g, rig, an = load(o.src)
    side_src = o.src + ".clips.json"
    only = o.only.split(",") if o.only else None
    out = {}
    for name, ch in an.items():
        if name in DELETE:
            print("delete", name); continue
        if name in CLIPS and (not only or name in only or name.replace("MA_Acro_", "") in only):
            ch2, c = process(rig, ch, CLIPS[name])
            print("%-30s %3d -> %3d frames" % (name, int(round(clip_len(ch) * FPS)), c.nf))
            ch = ch2
        out[RENAME.get(name, name)] = ch
    g.write(out, dst)
    if os.path.exists(side_src):
        rows = json.load(open(side_src, encoding="utf-8"))
        keep = []
        for r in rows:
            n = r["name"]
            if n in DELETE:
                continue
            if n in CLIPS and RENAME.get(n, n) in out:
                cfg = CLIPS[n]
                nf = int(round(clip_len(out[RENAME.get(n, n)]) * FPS)) + 1
                r["frames"] = nf; r["seconds"] = round((nf - 1) / FPS, 2)
                r["keys"] = int(sum(len(x["t"]) for x in out[RENAME.get(n, n)]))
                if cfg.get("trim"):
                    a, b = cfg["trim"]
                    if r.get("range_s") and r["range_s"][0] is not None:
                        r["range_s"] = [round(r["range_s"][0] + a / FPS, 2), round(r["range_s"][0] + b / FPS, 2)]
                    r["trimmed_from_s"] = [round(a / FPS, 2), round(b / FPS, 2)]
                r["polish"] = cfg.get("note", "cmu_acro_fix.py: trim, root rebased, toes straightened, grounded")
            if n in RENAME:
                r["renamed_from"] = n; r["name"] = RENAME[n]
            keep.append(r)
        json.dump(keep, open(dst + ".clips.json", "w", encoding="utf-8"), indent=1)
    print("wrote", dst)


if __name__ == "__main__":
    main()
