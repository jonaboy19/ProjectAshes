"""Preview strips: source video frame | recovered skeleton (front + side view) [| retargeted character frames].

  python preview_strip.py video.mp4 clip.bvh out/strip.png [--frames 8] [--char-frames DIR] [--gif out/clip.gif]
        [--gt gt.json]     # also draw ground-truth skeleton (for synthetic tests)
Skeleton colours: left side red, right side blue, spine/head grey. Front view looks along -Z (actor faces the viewer).
"""
import argparse, json, os
import numpy as np
import cv2
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from bvhlib import BVH

BONES = [("Hips", "LowerBack"), ("LowerBack", "Spine"), ("Spine", "Spine1"), ("Spine1", "Neck"), ("Neck", "Head"),
         ("Spine1", "LeftShoulder"), ("LeftShoulder", "LeftArm"), ("LeftArm", "LeftForeArm"), ("LeftForeArm", "LeftHand"),
         ("Spine1", "RightShoulder"), ("RightShoulder", "RightArm"), ("RightArm", "RightForeArm"), ("RightForeArm", "RightHand"),
         ("Hips", "LeftUpLeg"), ("LeftUpLeg", "LeftLeg"), ("LeftLeg", "LeftFoot"), ("LeftFoot", "LeftToeBase"),
         ("Hips", "RightUpLeg"), ("RightUpLeg", "RightLeg"), ("RightLeg", "RightFoot"), ("RightFoot", "RightToeBase")]


def col(a, b):
    return "#d33" if ("Left" in a or "Left" in b) else ("#37c" if ("Right" in a or "Right" in b) else "#666")


def skeleton_image(P, ix, view, size, span, center):
    """P [J,3] -> RGB image. view 'front' (x right, y up) or 'side' (z right, y up)."""
    fig = plt.figure(figsize=(size[0] / 100, size[1] / 100), dpi=100)
    ax = fig.add_axes([0, 0, 1, 1])
    h = span
    ax.set_xlim(center[0] - h * size[0] / size[1] / 2, center[0] + h * size[0] / size[1] / 2)
    ax.set_ylim(center[1] - h / 2, center[1] + h / 2)
    ax.axhline(0, color="#9a9", lw=1)
    hx = 0 if view == "front" else 2
    for a, b in BONES:
        pa, pb = P[ix[a]], P[ix[b]]
        ax.plot([pa[hx], pb[hx]], [pa[1], pb[1]], color=col(a, b), lw=3, solid_capstyle="round")
    ax.plot([P[ix["Head"], hx]], [P[ix["Head"], 1] + 0.1], "o", color="#666", ms=14)
    ax.set_aspect("equal"); ax.axis("off")
    fig.canvas.draw()
    img = np.asarray(fig.canvas.buffer_rgba())[:, :, :3].copy()
    plt.close(fig)
    return img


def read_frames(video, idxs, height):
    cap = cv2.VideoCapture(video)
    out = {}
    i = 0
    want = set(idxs)
    while True:
        ok, f = cap.read()
        if not ok:
            break
        if i in want:
            s = height / f.shape[0]
            out[i] = cv2.cvtColor(cv2.resize(f, (int(f.shape[1] * s), height)), cv2.COLOR_BGR2RGB)
        i += 1
    return out, cap.get(cv2.CAP_PROP_FPS) or 30.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video"); ap.add_argument("bvh"); ap.add_argument("out")
    ap.add_argument("--frames", type=int, default=8)
    ap.add_argument("--char-frames", help="folder of PNG frames rendered from the retargeted clip (f0001.png ...)")
    ap.add_argument("--height", type=int, default=480)
    ap.add_argument("--crop", type=float, default=0.0, help="crop source frame to a centred fraction of its width around the actor (0 = auto)")
    ap.add_argument("--gif")
    a = ap.parse_args()
    b = BVH.load(a.bvh)
    P, R = b.fk()
    ix = {n: i for i, n in enumerate(b.names)}
    T = len(P)
    idxs = np.linspace(0, T - 1, a.frames).round().astype(int)
    frames, vfps = read_frames(a.video, idxs if not a.gif else range(T), a.height)
    rows = []
    allidx = list(range(T)) if a.gif else list(idxs)
    span = 2.1
    cx = float(np.median(P[:, ix["Hips"], 0]))
    for t in allidx:
        pel = P[t, ix["Hips"]]
        fr = frames.get(t)
        if fr is None:
            fr = np.full((a.height, int(a.height * 9 / 16), 3), 200, np.uint8)
        # crop the source around the actor if the frame is very wide
        sk = []
        for view in ("front", "side"):
            c = (pel[0] if view == "front" else pel[2], 0.95)
            sk.append(skeleton_image(P[t], ix, view, (int(a.height * 0.6), a.height), span, c))
        tiles = [fr] + sk
        if a.char_frames:
            nch = len([x for x in os.listdir(a.char_frames) if x.endswith(".png")])
            f = cv2.imread(os.path.join(a.char_frames, "f%04d.png" % (min(t, nch - 1) + 1)))
            if f is not None:
                s = a.height / f.shape[0]
                tiles.append(cv2.cvtColor(cv2.resize(f, (int(f.shape[1] * s), a.height)), cv2.COLOR_BGR2RGB))
        rows.append(np.concatenate(tiles, 1))
    if a.gif:
        import imageio.v3 as iio  # optional
        iio.imwrite(a.gif, rows[::2], duration=66, loop=0)
        return
    # tile strips: 2 columns of frames to keep width sane
    per = 2 if rows[0].shape[1] > 800 else 4
    grid = []
    for i in range(0, len(rows), per):
        chunk = rows[i:i + per]
        while len(chunk) < per:
            chunk.append(np.full_like(rows[0], 255))
        grid.append(np.concatenate(chunk, 1))
    out = np.concatenate(grid, 0)
    cv2.imwrite(a.out, cv2.cvtColor(out, cv2.COLOR_RGB2BGR))
    print("wrote", a.out, out.shape)


if __name__ == "__main__":
    main()
