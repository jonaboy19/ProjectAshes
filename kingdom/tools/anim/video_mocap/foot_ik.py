"""Step 2b: IK foot pinning on the cleaned BVH (pure numpy, runs between mocap_to_bvh.py and the retargeter).

  python foot_ik.py in.bvh out.bvh [--report out/foot_ik.json] [--pelvis-level 0.5] [--no-ik]
                    [--vthr 0.6] [--hthr 0.10] [--blend 0.12]

What it does (all in the BVH world, metres, Y up):
  1. floor: the lowest foot points of the clip are put on y = 0 (root shifted; only if the offset is < 15 cm).
  2. contact detection per foot: ankle speed < vthr m/s AND foot bottom (heel/toe) < hthr m above the floor,
     gaps < 3 frames closed, runs < 3 frames dropped.
  3. pelvis levelling: hip roll is damped by --pelvis-level (0 = off, 1 = fully level); the pelvis is lowered
     when a pinned foot would otherwise be out of reach (legs never over-stretch).
  4. pin: during a contact run the ankle is fixed at the run's median world position (snapped onto the floor when
     within 5 cm) and the foot yaw is fixed; weights ramp in/out over --blend seconds so there is no pop.
  5. two-bone leg IK (thigh + shin lengths of the BVH), knee plane taken from the original knee (pole vector,
     re-orthogonalised), swing-only correction so the twist of the source is kept.
  6. floor clamp: heel and toe never go below y = 0 (ankle lifted by the needed amount), in swing phase too.
Reports foot slide (cm/s during contact, same contact mask before and after) and penetration.
"""
import argparse, json, math, os
import numpy as np
from bvhlib import BVH, write_bvh
from mocap_to_bvh import swing, unit, axis_angle, smoothstep, one_euro, rot_y_mat, slerp_mat

SIDES = ("Left", "Right")


def fk_global(b, root_pos, Rg):
    """Positions from ROOT position + global rotations (offsets are in the parent's frame)."""
    T, J = Rg.shape[:2]
    P = np.zeros((T, J, 3))
    for j in range(J):
        p = b.parent[j]
        P[:, j] = root_pos if p < 0 else P[:, p] + np.einsum("tij,j->ti", Rg[:, p], b.offset[j])
    return P


def runs(mask):
    out, i, n = [], 0, len(mask)
    while i < n:
        if mask[i]:
            j = i
            while j < n and mask[j]:
                j += 1
            out.append((i, j))
            i = j
        else:
            i += 1
    return out


def clean_mask(m, gap=4, minlen=3):
    m = m.copy()
    for a, b in runs(~m):                       # close short gaps between contacts
        if a > 0 and b < len(m) and (b - a) < gap:
            m[a:b] = True
    for a, b in runs(m):                        # drop tiny contacts
        if (b - a) < minlen:
            m[a:b] = False
    return m


def foot_points(P, Rg, ix, side, ah):
    """Heel and toe world points, from the foot rotation."""
    A = P[:, ix[side + "Foot"]]
    Rf = Rg[:, ix[side + "Foot"]]
    heel = A + np.einsum("tij,j->ti", Rf, np.array([0, -ah, -0.04]))
    toe = P[:, ix[side + "ToeBase"]]
    return A, heel, toe


def detect(P, Rg, ix, ah, fps, vthr, hthr):
    T = len(P)
    bots, speeds = [], []
    for s in SIDES:
        A, heel, toe = foot_points(P, Rg, ix, s, ah)
        bots.append(np.minimum(heel[:, 1], toe[:, 1]))
        Asm = one_euro(A, fps, 3.0, 0.0)
        speeds.append(np.linalg.norm(np.gradient(Asm, axis=0), axis=1) * fps)
    floor = float(np.percentile(np.concatenate(bots), 3))
    masks = []
    for k in range(2):
        m = (speeds[k] < vthr) & (bots[k] - floor < hthr)
        masks.append(clean_mask(m))
    return masks, floor, bots


def slide_stats(P, ix, masks, fps):
    """Horizontal speed (cm/s) of ankle and toe over consecutive contact frames."""
    res = {}
    for name, key in (("ankle", "Foot"), ("toe", "ToeBase")):
        v = []
        for k, s in enumerate(SIDES):
            X = P[:, ix[s + key]][:, [0, 2]]
            sp = np.linalg.norm(np.diff(X, axis=0), axis=1) * fps * 100
            ok = masks[k][1:] & masks[k][:-1]
            v.append(sp[ok])
        v = np.concatenate(v) if v else np.zeros(1)
        res[name + "_mean_cm_s"] = round(float(v.mean()), 1) if len(v) else 0.0
        res[name + "_p90_cm_s"] = round(float(np.percentile(v, 90)), 1) if len(v) else 0.0
    return res


def bottoms(P, Rg, ix, ah):
    out = []
    for s in SIDES:
        A, heel, toe = foot_points(P, Rg, ix, s, ah)
        out.append(np.minimum(heel[:, 1], toe[:, 1]))
    return np.stack(out, 1)


def ramp_weights(mask, R):
    """1 inside a contact run, smoothstep ramp over R frames on each side."""
    T = len(mask)
    w = np.zeros(T)
    idx = np.arange(T)
    for a, b in runs(mask):
        w[a:b] = 1.0
        for t in range(max(0, a - R), a):
            w[t] = max(w[t], smoothstep(0, 1, 1 - (a - t) / (R + 1.0)))
        for t in range(b, min(T, b + R)):
            w[t] = max(w[t], smoothstep(0, 1, 1 - (t - b + 1) / (R + 1.0)))
    return w


def wrap(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


def apply(bvh_in, bvh_out, pelvis_level=0.5, vthr=0.8, hthr=0.10, blend=0.12, do_ik=True, flat=1.0, log=print):
    b = BVH.load(bvh_in)
    assert b.channels[0][:3] == ["Xposition", "Yposition", "Zposition"], "unexpected root channels"
    fps = b.fps
    P0, Rg0 = b.fk()
    T = len(P0)
    ix = {n: i for i, n in enumerate(b.names)}
    root = b.frames[:, :3].copy()
    ah = float(-b.offset[ix["LeftToeBase"]][1])

    masks, floor, _ = detect(P0, Rg0, ix, ah, fps, vthr, hthr)
    info = {"frames": T, "fps": fps, "floor_offset_m": round(floor, 3),
            "contact_frac": [round(float(m.mean()), 2) for m in masks],
            "contact_runs": [len(runs(m)) for m in masks]}
    before = slide_stats(P0, ix, masks, fps)
    bot0 = bottoms(P0, Rg0, ix, ah)
    info["slide_before"] = before
    info["min_foot_before_m"] = round(float(bot0.min()), 3)
    info["penetration_frames_before"] = int((bot0 < -0.01).sum())
    if not do_ik:
        return info

    # 1. floor snap
    if abs(floor) < 0.15:
        root[:, 1] -= floor
    Rg = Rg0.copy()

    # 3a. pelvis roll levelling (global rotation of Hips only; the spine keeps its world orientation)
    H = ix["Hips"]
    if pelvis_level > 0:
        roll0 = np.degrees(np.arcsin(np.clip(Rg[:, H, 1, 0], -1, 1)))
        for t in range(T):
            r = math.asin(float(np.clip(Rg[t, H, 1, 0], -1, 1)))
            Rg[t, H] = axis_angle(Rg[t, H][:, 2], r * pelvis_level) @ Rg[t, H]
        roll1 = np.degrees(np.arcsin(np.clip(Rg[:, H, 1, 0], -1, 1)))
        info["hip_roll_std_deg"] = [round(float(roll0.std()), 2), round(float(roll1.std()), 2)]
    P = fk_global(b, root, Rg)
    P_ank_orig = P0[:, [ix["LeftFoot"], ix["RightFoot"]]].copy()
    P_ank_orig[:, :, 1] -= floor if abs(floor) < 0.15 else 0.0

    # 4. pins (target ankle, weight, yaw correction)
    Rr = max(1, int(round(blend * fps)))
    tgt = P_ank_orig.copy()
    yaw_fix = np.zeros((T, 2))
    yaw_ref = np.zeros((T, 2))
    W = np.zeros((T, 2))
    for k, s in enumerate(SIDES):
        w = ramp_weights(masks[k], Rr)
        W[:, k] = w
        Rf = Rg[:, ix[s + "Foot"]]
        fwd = np.einsum("tij,j->ti", Rf, np.array([0, 0, 1.0]))
        yaw = np.arctan2(fwd[:, 0], fwd[:, 2])
        for a, e in runs(masks[k]):
            seg = np.arange(a, e)
            core = seg[len(seg) // 5: len(seg) - len(seg) // 5] if len(seg) >= 5 else seg
            pin = np.median(P_ank_orig[core, k], axis=0)
            ref = math.atan2(float(np.mean(np.sin(yaw[core]))), float(np.mean(np.cos(yaw[core]))))
            lo, hi = max(0, a - Rr), min(T, e + Rr)
            for t in range(lo, hi):
                wt = w[t]
                if wt <= 0:
                    continue
                tgt[t, k] = tgt[t, k] * (1 - wt) + pin * wt
                yaw_fix[t, k] = wt * wrap(ref - yaw[t])
                yaw_ref[t, k] = ref
    # feet at the floor snap: after the yaw fix, ankle_y = lowest that keeps heel/toe on the floor (below)

    # foot rotations: yaw pinned, then blended towards a flat foot (sole on the floor) while planted
    for k, s in enumerate(SIDES):
        for t in range(T):
            if W[t, k] > 1e-3:
                Rn = rot_y_mat(yaw_fix[t, k]) @ Rg[t, ix[s + "Foot"]]
                if flat > 0:
                    Rn = slerp_mat(Rn, rot_y_mat(yaw_ref[t, k]), min(1.0, flat * W[t, k]))
                Rg[t, ix[s + "Foot"]] = Rn
        Rg[:, ix[s + "ToeBase"]] = Rg[:, ix[s + "Foot"]]

    # 6. floor clamp on targets (ankle height so that heel and toe are >= 0); planted feet land ON the floor
    toe_off = b.offset[ix["LeftToeBase"]]
    for k, s in enumerate(SIDES):
        Rf = Rg[:, ix[s + "Foot"]]
        pts = [np.einsum("tij,j->ti", Rf, np.array([0, -ah, -0.04]))[:, 1],
               np.einsum("tij,j->ti", Rf, toe_off)[:, 1]]
        ymin = -np.minimum(pts[0], pts[1])               # ankle must be at least this high
        planted = W[:, k] > 0.5
        snap = planted & (tgt[:, k, 1] - ymin < 0.06)
        # planted, near the floor: stand on it (blend by weight so swing frames keep their own height)
        tgt[:, k, 1] = np.where(snap, tgt[:, k, 1] * (1 - W[:, k]) + ymin * W[:, k], tgt[:, k, 1])
        tgt[:, k, 1] = np.maximum(tgt[:, k, 1], ymin)

    # 3b. pelvis drop so that pinned legs are never over-stretched
    UL, LL, FT = [ix[s + "UpLeg"] for s in SIDES], [ix[s + "Leg"] for s in SIDES], [ix[s + "Foot"] for s in SIDES]
    L1 = [float(np.linalg.norm(b.offset[LL[k]])) for k in range(2)]
    L2 = [float(np.linalg.norm(b.offset[FT[k]])) for k in range(2)]
    drop = np.zeros(T)
    for it in range(2):
        P = fk_global(b, root - np.array([0, 1, 0]) * drop[:, None], Rg)
        need = np.zeros(T)
        for k in range(2):
            d = np.linalg.norm(tgt[:, k] - P[:, UL[k]], axis=1)
            over = d - 0.985 * (L1[k] + L2[k])
            vert = np.maximum(np.abs(P[:, UL[k], 1] - tgt[:, k, 1]) / np.maximum(d, 1e-6), 0.4)
            need = np.maximum(need, np.where(W[:, k] > 0.01, over * W[:, k] / vert, 0))
        drop = drop + np.maximum(need, 0)
    drop = np.clip(one_euro(drop[:, None], fps, 2.5, 0.0)[:, 0] * 1.0, 0, 0.12)
    info["pelvis_drop_max_cm"] = round(float(drop.max()) * 100, 1)
    root[:, 1] -= drop
    P = fk_global(b, root, Rg)

    # 5. two-bone IK
    reach_fail = 0
    for k, s in enumerate(SIDES):
        prev_pole = None
        for t in range(T):
            Hh = P[t, UL[k]]
            K0, A0 = P0[t, LL[k]], P0[t, FT[k]]
            ax0 = A0 - P0[t, UL[k]]
            ax0 = ax0 / max(np.linalg.norm(ax0), 1e-9)
            p0 = (K0 - P0[t, UL[k]])
            p0 = p0 - ax0 * (p0 @ ax0)
            n0 = float(np.linalg.norm(p0))
            fwd = Rg[t, H][:, 2]
            if n0 < 0.02:
                p0 = prev_pole if prev_pole is not None else fwd
            else:
                p0 = p0 / n0
            A = tgt[t, k]
            v = A - Hh
            d = float(np.linalg.norm(v))
            u = v / max(d, 1e-9)
            dmax, dmin = 0.999 * (L1[k] + L2[k]), abs(L1[k] - L2[k]) + 0.02
            if d > dmax:
                reach_fail += 1
            dc = min(max(d, dmin), dmax)
            A = Hh + u * dc
            pole = p0 - u * (p0 @ u)
            if np.linalg.norm(pole) < 1e-4:
                pole = fwd - u * (fwd @ u)
            pole = pole / np.linalg.norm(pole)
            prev_pole = pole
            a = (L1[k] ** 2 - L2[k] ** 2 + dc ** 2) / (2 * dc)
            h = math.sqrt(max(L1[k] ** 2 - a * a, 0.0))
            K = Hh + u * a + pole * h
            e1 = b.offset[LL[k]] / L1[k]
            e2 = b.offset[FT[k]] / L2[k]
            Rg[t, UL[k]] = swing(Rg[t, UL[k]] @ e1, K - Hh) @ Rg[t, UL[k]]
            Rg[t, LL[k]] = swing(Rg[t, LL[k]] @ e2, A - K) @ Rg[t, LL[k]]
    info["unreachable_frames"] = reach_fail
    P1 = fk_global(b, root, Rg)

    # ---- outputs
    Rl = np.zeros_like(Rg)
    for j in range(len(b.names)):
        pj = b.parent[j]
        Rl[:, j] = Rg[:, j] if pj < 0 else np.matmul(np.transpose(Rg[:, pj], (0, 2, 1)), Rg[:, j])
    write_bvh(bvh_out, b.names, b.parent, b.offset, {j: tuple(v) for j, v in b.end_sites.items()}, root, Rl, fps)
    P2, _ = BVH.load(bvh_out).fk()            # measure what was actually written
    info["slide_after"] = slide_stats(P2, ix, masks, fps)
    b2 = BVH.load(bvh_out)
    P2, R2 = b2.fk()
    bot1 = bottoms(P2, R2, ix, ah)
    info["min_foot_after_m"] = round(float(bot1.min()), 3)
    info["penetration_frames_after"] = int((bot1 < -0.01).sum())
    # knee/hip sanity: how far did the IK move joints relative to the input
    info["max_ankle_shift_cm"] = round(float(np.max(np.linalg.norm(P2[:, [ix["LeftFoot"], ix["RightFoot"]]] - P0[:, [ix["LeftFoot"], ix["RightFoot"]]], axis=2))) * 100, 1)
    info["max_knee_shift_cm"] = round(float(np.max(np.linalg.norm(P2[:, [ix["LeftLeg"], ix["RightLeg"]]] - P0[:, [ix["LeftLeg"], ix["RightLeg"]]], axis=2))) * 100, 1)
    return info, masks


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bvh_in")
    ap.add_argument("bvh_out")
    ap.add_argument("--report")
    ap.add_argument("--pelvis-level", type=float, default=0.5)
    ap.add_argument("--vthr", type=float, default=0.8, help="max ankle speed (m/s) for a contact")
    ap.add_argument("--hthr", type=float, default=0.10, help="max foot-bottom height above floor (m) for a contact")
    ap.add_argument("--blend", type=float, default=0.12, help="blend in/out seconds at contact boundaries")
    ap.add_argument("--flat", type=float, default=1.0, help="0..1 how flat the foot is kept while planted")
    ap.add_argument("--no-ik", action="store_true", help="only measure")
    a = ap.parse_args()
    r = apply(a.bvh_in, a.bvh_out, a.pelvis_level, a.vthr, a.hthr, a.blend, not a.no_ik, a.flat)
    info = r[0] if isinstance(r, tuple) else r
    print(json.dumps(info, indent=1))
    if a.report:
        os.makedirs(os.path.dirname(os.path.abspath(a.report)), exist_ok=True)
        json.dump(info, open(a.report, "w"), indent=1)


if __name__ == "__main__":
    main()
