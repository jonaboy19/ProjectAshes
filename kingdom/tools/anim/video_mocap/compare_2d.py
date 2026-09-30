"""2D accuracy of MediaPipe vs RTMPose on the synthetic Blender clip (ground truth known).

  python compare_2d.py gt.json mp_pose.npz rtm.npz [--json out.json]

Ground-truth 3D joints (gt.json from render_test_clip.py) are projected with a pinhole camera that mimics the render script
(lens 35 mm on a 36 mm sensor along the long side, 720x1280, camera at height 1.25 m looking at the pelvis midpoint).
Camera azimuth and distance are not stored, so they are FITTED (grid search) to minimise the mean of both detectors' error;
the same camera is used for both, so the comparison is fair. Error unit: fraction of the GT torso length (shoulder-mid to hip-mid in pixels).
Joints: shoulders, elbows, wrists, hips, knees, ankles (GT joint names in brackets: upperarm, lowerarm, hand, thigh, calf, foot).
"""
import argparse, json, math
import numpy as np

JOINTS = [("shoulder_l", "upperarm_l", 11, 5), ("shoulder_r", "upperarm_r", 12, 6), ("elbow_l", "lowerarm_l", 13, 7), ("elbow_r", "lowerarm_r", 14, 8),
          ("wrist_l", "hand_l", 15, 9), ("wrist_r", "hand_r", 16, 10), ("hip_l", "thigh_l", 23, 11), ("hip_r", "thigh_r", 24, 12),
          ("knee_l", "calf_l", 25, 13), ("knee_r", "calf_r", 26, 14), ("ankle_l", "foot_l", 27, 15), ("ankle_r", "foot_r", 28, 16)]
W, H, LENS, SENSOR = 720, 1280, 35.0, 36.0


def project(P, az, r, center):
    a = math.radians(az)
    cam = np.array([center[0] + r * math.sin(a), center[1] + r * math.cos(a), 1.25])
    tgt = np.array([center[0], center[1], 0.95])
    f = tgt - cam; f /= np.linalg.norm(f)
    right = np.cross(f, [0, 0, 1.0]); right /= np.linalg.norm(right)
    up = np.cross(right, f)
    d = P - cam
    x, y, z = d @ right, d @ up, d @ f
    fpx = LENS / SENSOR * max(W, H)
    return np.stack([W / 2 + fpx * x / z, H / 2 - fpx * y / z], -1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("gt"); ap.add_argument("mp"); ap.add_argument("rtm"); ap.add_argument("--json")
    a = ap.parse_args()
    gt = json.load(open(a.gt))["joints"]
    T = len(gt)
    G = {k: np.array([g[k] for g in gt]) for k in gt[0]}
    mp = np.load(a.mp)["image"][:T]
    rt = np.load(a.rtm)["coco17"][:T]
    T = min(T, len(mp), len(rt))
    mp_px = mp[:, :, :2] * np.array([W, H])
    c = (G["pelvis"][0] + G["pelvis"][-1]) / 2
    def err(az, r, which):
        P3 = np.stack([G[j[1]] for j in JOINTS], 1)[:T]       # T,12,3
        p2 = np.stack([project(P3[:, i], az, r, c) for i in range(len(JOINTS))], 1)
        det = np.stack([(mp_px[:, j[2]] if which == "mp" else rt[:, j[3]]) for j in JOINTS], 1)
        return p2, np.linalg.norm(det - p2, axis=-1)
    best = None
    for az in range(0, 360, 5):
        for r in np.arange(2.5, 6.01, 0.25):
            s = np.nanmedian(err(az, r, "mp")[1]) + np.nanmedian(err(az, r, "rtm")[1])
            if np.isfinite(s) and (best is None or s < best[0]):
                best = (s, az, r)
    _, az, r = best
    p2, _ = err(az, r, "mp")
    torso = np.linalg.norm((p2[:, 0] + p2[:, 1]) / 2 - (p2[:, 6] + p2[:, 7]) / 2, axis=-1).mean()
    out = {"fitted_camera": {"azimuth_deg": az, "distance_m": float(r)}, "torso_px": round(float(torso), 1), "frames": T}
    for name, which in (("mediapipe_heavy", "mp"), ("rtmpose_body", "rtm")):
        e = err(az, r, which)[1] / torso
        out[name] = {"mean_torso": round(float(np.nanmean(e)), 3), "median_torso": round(float(np.nanmedian(e)), 3),
                     "pck_0.1": round(float(np.nanmean(e < 0.1)), 3), "pck_0.05": round(float(np.nanmean(e < 0.05)), 3),
                     "per_joint_mean": {j[0]: round(float(np.nanmean(e[:, i])), 3) for i, j in enumerate(JOINTS)}}
    print(json.dumps(out, indent=1))
    if a.json:
        json.dump(out, open(a.json, "w"), indent=1)


if __name__ == "__main__":
    main()
