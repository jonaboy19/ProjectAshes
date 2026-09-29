"""Compare a recovered BVH against ground-truth joint positions dumped by render_test_clip.py (gt.json).

  python compare_gt.py out/sword.bvh work/sword/gt.json [--json out/sword_compare.json]

Rotation/translation invariant: limb bone directions are expressed in each skeleton's own hips frame, so the
camera view and the world axes do not matter. Reports mean / p90 angular error per bone, plus root height and
travel-length error.
"""
import argparse, json, sys
import numpy as np
from bvhlib import BVH
from mocap_to_bvh import frame_from, unit

PAIRS = {  # name: (GT joint a, GT joint b, BVH joint a, BVH joint b)
    "L_upperarm": ("upperarm_l", "lowerarm_l", "LeftArm", "LeftForeArm"),
    "L_forearm": ("lowerarm_l", "hand_l", "LeftForeArm", "LeftHand"),
    "R_upperarm": ("upperarm_r", "lowerarm_r", "RightArm", "RightForeArm"),
    "R_forearm": ("lowerarm_r", "hand_r", "RightForeArm", "RightHand"),
    "L_thigh": ("thigh_l", "calf_l", "LeftUpLeg", "LeftLeg"),
    "L_shin": ("calf_l", "foot_l", "LeftLeg", "LeftFoot"),
    "R_thigh": ("thigh_r", "calf_r", "RightUpLeg", "RightLeg"),
    "R_shin": ("calf_r", "foot_r", "RightLeg", "RightFoot"),
    "L_foot": ("foot_l", "ball_l", "LeftFoot", "LeftToeBase"),
    "R_foot": ("foot_r", "ball_r", "RightFoot", "RightToeBase"),
}


def compare(bvh_path, gt_path, offset=0):
    b = BVH.load(bvh_path)
    P, R = b.fk()
    ix = {n: i for i, n in enumerate(b.names)}
    gt = json.load(open(gt_path))["joints"][offset:]      # offset = first video frame the BVH covers (trim)
    T = min(len(gt), len(P))
    G = {k: np.array([g[k] for g in gt[:T]]) for k in gt[0]}
    res = {k: [] for k in PAIRS}
    for t in range(T):
        # hips frames
        xg = G["thigh_l"][t] - G["thigh_r"][t]
        Fg = frame_from(xg, G["spine_03"][t] - G["pelvis"][t])
        xb = P[t, ix["LeftUpLeg"]] - P[t, ix["RightUpLeg"]]
        Fb = frame_from(xb, P[t, ix["Spine1"]] - P[t, ix["Hips"]])
        for k, (ga, gb, ba, bb) in PAIRS.items():
            dg = Fg.T @ unit(G[gb][t] - G[ga][t])
            db = Fb.T @ unit(P[t, ix[bb]] - P[t, ix[ba]])
            res[k].append(np.degrees(np.arccos(np.clip(dg @ db, -1, 1))))
    out = {"bones_deg": {k: {"mean": round(float(np.mean(v)), 1), "p90": round(float(np.percentile(v, 90)), 1)} for k, v in res.items()}}
    allv = np.concatenate([v for v in res.values()])
    out["all_mean_deg"] = round(float(allv.mean()), 1)
    out["all_p90_deg"] = round(float(np.percentile(allv, 90)), 1)
    # root
    gp = G["pelvis"][:, :]
    gh = gp[:, 2] - min(G["foot_l"][:, 2].min(), G["foot_r"][:, 2].min())
    bh = P[:T, ix["Hips"], 1]
    out["hips_height_mae_m"] = round(float(np.mean(np.abs((bh - bh.min()) - (gh - gh.min())))), 3)
    gtravel = float(np.linalg.norm(gp[-1, :2] - gp[0, :2]))
    btravel = float(np.linalg.norm(P[T - 1, ix["Hips"], [0, 2]] - P[0, ix["Hips"], [0, 2]]))
    out["travel_m"] = {"gt": round(gtravel, 2), "recovered": round(btravel, 2)}
    # foot sliding: horizontal speed of the lowest foot joint while it is near the floor
    fl = P[:T, ix["LeftFoot"]]; fr = P[:T, ix["RightFoot"]]
    slide = []
    for f in (fl, fr):
        low = f[:, 1] < f[:, 1].min() + 0.06
        v = np.linalg.norm(np.diff(f[:, [0, 2]], axis=0), axis=1) * b.fps
        slide.append(float(np.mean(v[low[1:] & low[:-1]])) if (low[1:] & low[:-1]).any() else 0.0)
    out["foot_slide_mps_recovered"] = [round(s, 3) for s in slide]
    gs = []
    for a in ("foot_l", "foot_r"):
        f = G[a]
        low = f[:, 2] < f[:, 2].min() + 0.06
        v = np.linalg.norm(np.diff(f[:, :2], axis=0), axis=1) * 30
        gs.append(float(np.mean(v[low[1:] & low[:-1]])) if (low[1:] & low[:-1]).any() else 0.0)
    out["foot_slide_mps_gt"] = [round(s, 3) for s in gs]
    # foot slide during GROUND-TRUTH contact frames (GT foot speed < 0.3 m/s and within 8 cm of its lowest point): the
    # honest before/after metric for IK foot pinning, independent of the tool's own contact detector. cm/s.
    sl, gsl = [], []
    for a, bj in (("foot_l", "LeftFoot"), ("foot_r", "RightFoot")):
        f = G[a]
        gv = np.linalg.norm(np.gradient(f[:, :2], axis=0), axis=1) * 30
        c = (gv < 0.3) & (f[:, 2] < f[:, 2].min() + 0.08)
        bv = np.linalg.norm(np.gradient(P[:T, ix[bj]][:, [0, 2]], axis=0), axis=1) * b.fps
        sl.append(bv[c]); gsl.append(gv[c])
    out["foot_slide_gt_contact_cm_s"] = {"recovered_mean": round(float(np.concatenate(sl).mean()) * 100, 1),
                                         "recovered_p90": round(float(np.percentile(np.concatenate(sl), 90)) * 100, 1),
                                         "gt_mean": round(float(np.concatenate(gsl).mean()) * 100, 1)}
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("bvh")
    ap.add_argument("gt")
    ap.add_argument("--json")
    ap.add_argument("--offset", type=int, default=0, help="frames trimmed from the start of the video")
    a = ap.parse_args()
    r = compare(a.bvh, a.gt, a.offset)
    print(json.dumps(r, indent=1))
    if a.json:
        json.dump(r, open(a.json, "w"), indent=1)
