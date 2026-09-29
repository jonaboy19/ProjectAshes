"""Side-by-side review sheets: source video | recovered skeleton (front) | retargeted character, one row per sampled frame,
labelled '#frame t=seconds' (same idea as tools/qa/video_to_sheets.sh, but the three views are aligned in time),
plus foot_ik.png (ankle speed before/after IK with the contact phases shaded).

  build(video, bvh, char_frames_dir|None, out_dir, sheet_fps=0, trim=None, vfps=30, ik_json=None, raw_bvh=None) -> number of sheets
"""
import glob, os
import numpy as np, cv2
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from bvhlib import BVH
from preview_strip import skeleton_image


def label(img, text):
    cv2.rectangle(img, (0, 0), (img.shape[1], 22), (0, 0, 0), -1)
    cv2.putText(img, text, (5, 16), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1, cv2.LINE_AA)
    return img


def crop_actor(img, pose_img, k):
    """Crop the frame to a 3:4 (w:h) box around the detected person so a small actor stays readable."""
    if pose_img is None or not (0 <= k < len(pose_img)):
        return img
    H, W = img.shape[:2]
    lo, hi = max(0, k - 4), min(len(pose_img), k + 5)
    p = pose_img[lo:hi]
    ok = ~np.isnan(p[:, :, 0])
    if not ok.any():
        return img
    xs, ys = p[:, :, 0][ok] * W, p[:, :, 1][ok] * H
    cx, cy = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
    h = max((ys.max() - ys.min()) * 1.35, (xs.max() - xs.min()) * 1.35 / 0.6, 0.35 * H)
    h = min(h, H)
    w = min(h * 0.6, W)
    h = min(h, w / 0.6)
    x0 = int(np.clip(cx - w / 2, 0, W - w)); y0 = int(np.clip(cy - h / 2, 0, H - h))
    return img[y0:y0 + int(h), x0:x0 + int(w)]


def fit(img, h):
    s = h / img.shape[0]
    return cv2.resize(img, (max(1, int(img.shape[1] * s)), h), interpolation=cv2.INTER_AREA)


def build(video, bvh_path, char_dir, out_dir, sheet_fps=0, trim=None, vfps=30.0, ik_json=None, raw_bvh=None, tile_h=300, pose_img=None):
    b = BVH.load(bvh_path)
    P, R = b.fk()
    ix = {n: i for i, n in enumerate(b.names)}
    T = len(P)
    dur = T / b.fps
    sfps = sheet_fps or min(10.0, max(2.0, 27.0 / dur))
    step = max(1, int(round(b.fps / sfps)))
    idxs = list(range(0, T, step))
    off0 = trim[0] if trim else 0
    want = {int(round(i / b.fps * vfps)) + off0: i for i in idxs}
    src = {}
    cap = cv2.VideoCapture(video)
    k = 0
    while True:
        ok, f = cap.read()
        if not ok:
            break
        if k in want:
            src[want[k]] = fit(crop_actor(cv2.cvtColor(f, cv2.COLOR_BGR2RGB), pose_img, k - off0), tile_h)
        k += 1
    cap.release()
    nchar = len(glob.glob(os.path.join(char_dir, "f*.png"))) if char_dir else 0
    rows = []
    for i in idxs:
        t = i / b.fps
        s = src.get(i)
        if s is None:
            s = np.full((tile_h, int(tile_h * 9 / 16), 3), 90, np.uint8)
        tiles = [label(s.copy(), "#%d  %.2fs  video" % (i, t))]
        pel = P[i, ix["Hips"]]
        for view, cxv in (("front", pel[0]), ("side", pel[2])):
            sk = skeleton_image(P[i], ix, view, (int(tile_h * 0.5), tile_h), 2.1, (cxv, 0.95))
            tiles.append(label(sk, "skel " + view))
        if nchar:
            c = cv2.imread(os.path.join(char_dir, "f%04d.png" % (min(i, nchar - 1) + 1)))
            if c is not None:
                tiles.append(label(fit(cv2.cvtColor(c, cv2.COLOR_BGR2RGB), tile_h), "retargeted"))
        rows.append(np.concatenate(tiles, 1))
    mw = max(r.shape[1] for r in rows)
    rows = [np.pad(r, ((0, 0), (0, mw - r.shape[1]), (0, 0)), constant_values=32) for r in rows]
    rw = mw + 6
    cols = max(1, 1500 // rw)
    rows_per = 3
    per = cols * rows_per
    n_sheets = 0
    for s0 in range(0, len(rows), per):
        chunk = rows[s0:s0 + per]
        grid = []
        for r0 in range(0, len(chunk), cols):
            line = [np.pad(x, ((3, 3), (3, 3), (0, 0)), constant_values=32) for x in chunk[r0:r0 + cols]]
            while len(line) < cols:
                line.append(np.full_like(line[0], 32))
            grid.append(np.concatenate(line, 1))
        n_sheets += 1
        cv2.imwrite(os.path.join(out_dir, "sheet_%03d.png" % n_sheets), cv2.cvtColor(np.concatenate(grid, 0), cv2.COLOR_RGB2BGR))
    if ik_json and raw_bvh and os.path.isfile(raw_bvh):
        foot_plot(raw_bvh, bvh_path, os.path.join(out_dir, "foot_ik.png"))
    return n_sheets


def foot_plot(raw_bvh, ik_bvh, out):
    import foot_ik
    fig, axs = plt.subplots(2, 1, figsize=(10, 5.2), sharex=True)
    b0, b1 = BVH.load(raw_bvh), BVH.load(ik_bvh)
    P0, R0 = b0.fk()
    P1, R1 = b1.fk()
    ix = {n: i for i, n in enumerate(b0.names)}
    ah = float(-b0.offset[ix["LeftToeBase"]][1])
    masks, floor, _ = foot_ik.detect(P0, R0, ix, ah, b0.fps, 0.8, 0.10)
    t = np.arange(len(P0)) / b0.fps
    for k, s in enumerate(("Left", "Right")):
        ax = axs[k]
        for P, c, lab in ((P0, "#c33", "before IK"), (P1, "#27a", "after IK")):
            v = np.linalg.norm(np.gradient(P[:, ix[s + "Foot"]][:, [0, 2]], axis=0), axis=1) * b0.fps
            ax.plot(t, v, color=c, lw=1.6, label=lab)
        for a, e in foot_ik.runs(masks[k]):
            ax.axvspan(t[a], t[min(e, len(t) - 1)], color="#8c8", alpha=0.3, lw=0)
        ax.set_ylim(0, 3.5)
        ax.set_ylabel("%s ankle m/s" % s)
        ax.legend(loc="upper right", fontsize=8)
    axs[1].set_xlabel("time (s); green = detected foot contact (ankle horizontal speed should be ~0 there)")
    plt.tight_layout()
    plt.savefig(out, dpi=90)
    plt.close(fig)
