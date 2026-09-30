"""Alternative step 1: video -> per-frame 2D keypoints with RTMPose (rtmlib, onnxruntime, CPU or CUDA). Apache-2.0 code + weights.

  <rtmlib venv>\\Scripts\\python.exe rtm_extract.py clip.mp4 out/clip_rtm.npz [--mode lightweight|balanced|performance] [--max-frames N]

venv: C:\\Users\\Jonna\\Tools\\rtmlib\\venv   (pip install rtmlib onnxruntime opencv-python-headless numpy)
Saves:
  coco17[T,17,2]   pixel coords (COCO order: nose, eyes, ears, shoulders, elbows, wrists, hips, knees, ankles)
  score[T,17]
  image[T,33,3]    MediaPipe-indexed copy (x,y normalised 0..1, z=0; only the 13 joints COCO has, rest NaN) so 2D tools can swap detectors
  fps, width, height
2D ONLY: RTMPose-m has no depth. mocap_to_bvh.py needs the 3D world landmarks that MediaPipe gives, so this is a
2D accuracy upgrade / cross-check today, not yet a drop-in replacement. 3D options: rtmlib Wholebody3d (RTMW3D), or fuse
RTM 2D with MediaPipe depth.
"""
import argparse, os, sys
import numpy as np, cv2
from rtmlib import Body

# COCO17 index -> MediaPipe Pose index
COCO_TO_MP = {0: 0, 1: 2, 2: 5, 3: 7, 4: 8, 5: 11, 6: 12, 7: 13, 8: 14, 9: 15, 10: 16, 11: 23, 12: 24, 13: 25, 14: 26, 15: 27, 16: 28}


def extract(video, mode="balanced", max_frames=0, device="cpu", log=print):
    cap = cv2.VideoCapture(video)
    if not cap.isOpened():
        raise SystemExit("cannot open " + video)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    body = Body(mode=mode, to_openpose=False, backend="onnxruntime", device=device)
    K, S = [], []
    t = 0
    while True:
        ok, bgr = cap.read()
        if not ok or (max_frames and t >= max_frames):
            break
        h, w = bgr.shape[:2]
        kp, sc = body(bgr)                       # (N,17,2), (N,17)
        if len(kp):
            i = int(np.argmax(sc.mean(axis=1)))  # most confident person
            K.append(kp[i]); S.append(sc[i])
        else:
            K.append(np.full((17, 2), np.nan)); S.append(np.zeros(17))
        t += 1
        if t % 30 == 0:
            log("  frame %d" % t)
    cap.release()
    K = np.array(K, float); S = np.array(S, float)
    img = np.full((len(K), 33, 3), np.nan)
    for c, m in COCO_TO_MP.items():
        img[:, m, 0] = K[:, c, 0] / w; img[:, m, 1] = K[:, c, 1] / h; img[:, m, 2] = 0
    return dict(coco17=K, score=S, image=img, fps=fps, width=w, height=h)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("video"); ap.add_argument("out")
    ap.add_argument("--mode", default="balanced", choices=["lightweight", "balanced", "performance"])
    ap.add_argument("--device", default="cpu")
    ap.add_argument("--max-frames", type=int, default=0)
    a = ap.parse_args()
    d = extract(a.video, a.mode, a.max_frames, a.device)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    np.savez_compressed(a.out, **d)
    miss = int(np.isnan(d["coco17"][:, 0, 0]).sum())
    print("saved", a.out, "frames", len(d["coco17"]), "fps", d["fps"], "no-person frames", miss)
