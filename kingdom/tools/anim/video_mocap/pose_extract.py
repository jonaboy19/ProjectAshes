"""Step 1: video -> per-frame MediaPipe landmarks (npz).

  python pose_extract.py clip.mp4 out/clip_pose.npz [--model heavy|full|lite] [--max-frames N]

Saves:  world[T,33,3] (metres, hip-centred, MediaPipe axes x right / y down / z away from camera; NaN = no person),
        image[T,33,3] (normalised image coords x,y in 0..1 and relative depth), vis[T,33], fps, width, height.
Licences: MediaPipe code + Pose Landmarker models are Apache-2.0 (commercial use OK).
"""
import argparse, os, sys, urllib.request
import numpy as np, cv2
import mediapipe as mp
from mediapipe.tasks.python import vision, BaseOptions

HERE = os.path.dirname(os.path.abspath(__file__))
URL = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_%s/float16/latest/pose_landmarker_%s.task"

def get_model(kind):
    for d in (os.path.join(HERE, "models"), os.environ.get("VIDEO_MOCAP_MODELS", "")):
        p = os.path.join(d, "pose_landmarker_%s.task" % kind) if d else ""
        if p and os.path.exists(p):
            return p
    os.makedirs(os.path.join(HERE, "models"), exist_ok=True)
    p = os.path.join(HERE, "models", "pose_landmarker_%s.task" % kind)
    print("downloading", kind, "model (Apache-2.0) ...")
    urllib.request.urlretrieve(URL % (kind, kind), p)
    return p

def extract(video, model="heavy", max_frames=0, log=print):
    cap = cv2.VideoCapture(video)
    if not cap.isOpened():
        raise SystemExit("cannot open " + video)
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    opts = vision.PoseLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=get_model(model)),
        running_mode=vision.RunningMode.VIDEO, num_poses=1,
        min_pose_detection_confidence=0.4, min_pose_presence_confidence=0.4, min_tracking_confidence=0.4)
    W, V, I, S = [], [], [], []
    t = 0
    with vision.PoseLandmarker.create_from_options(opts) as lm:
        while True:
            ok, bgr = cap.read()          # OpenCV applies the phone's rotation metadata
            if not ok or (max_frames and t >= max_frames):
                break
            h, w = bgr.shape[:2]
            img = mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
            r = lm.detect_for_video(img, int(round(t * 1000.0 / fps)))
            if r.pose_world_landmarks:
                wl, il = r.pose_world_landmarks[0], r.pose_landmarks[0]
                W.append([[p.x, p.y, p.z] for p in wl])
                I.append([[p.x, p.y, p.z] for p in il])
                V.append([min(p.visibility, p.presence) if p.presence is not None else p.visibility for p in wl])
            else:
                W.append(np.full((33, 3), np.nan)); I.append(np.full((33, 3), np.nan)); V.append(np.zeros(33))
            t += 1
            if t % 30 == 0:
                log("  frame %d" % t)
    cap.release()
    return dict(world=np.array(W, float), image=np.array(I, float), vis=np.array(V, float),
                fps=fps, width=w, height=h)

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("video"); ap.add_argument("out")
    ap.add_argument("--model", default="heavy", choices=["lite", "full", "heavy"])
    ap.add_argument("--max-frames", type=int, default=0)
    a = ap.parse_args()
    d = extract(a.video, a.model, a.max_frames)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    np.savez_compressed(a.out, **d)
    miss = int(np.isnan(d["world"][:, 0, 0]).sum())
    print("saved", a.out, "frames", len(d["world"]), "fps", d["fps"], "no-person frames", miss)
