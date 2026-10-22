"""ONE COMMAND: phone video -> UAL clip GLB + review sheets.

  video_to_clip.ps1 <video.mp4> <ClipName> [-Loop] [-Fps 30]        (Windows, wraps this file)
  python video_to_clip.py <video> <ClipName> [--loop] [--fps 30] [--height 1.75] [--fov 66]
         [--face first|travel|none|DEG] [--root blend|image|feet|none] [--start S --end E]
         [--no-ik] [--no-render] [--sheet-fps N] [--model heavy|full|lite]

Steps: 1 pose landmarks (MediaPipe)  2 clean BVH  3 IK foot pinning  4 retarget to the UAL skeleton (Blender)
       5 preview render of the result on the mannequin  6 side-by-side sheets + foot-slide plot.
Outputs:
  kingdom/assets/incoming/animations_video/<ClipName>/UAL_Video_<ClipName>.glb   (+ .glb.clips.json: length, loop, travel, ik stats)
  docs/anim/advanced/video_mocap/out/<ClipName>/sheet_001.png ... foot_ik.png report.json
  work files (npz, bvh, frames): kingdom/tools/anim/video_mocap/out/<ClipName>/  (gitignored)
"""
import argparse, glob, json, os, re, shutil, subprocess, sys, time
os.environ.setdefault("GLOG_minloglevel", "2")          # quiet MediaPipe/TFLite logging
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
KINGDOM = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
REPO = os.path.dirname(KINGDOM)
BLENDER = os.environ.get("BLENDER", r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe")
UAL_STD = os.path.join(KINGDOM, "assets", "incoming", "quaternius", "universal-animation-library", "Unreal-Godot", "UAL1_Standard.glb")


class Fail(Exception):
    pass


def step(n, text):
    print("\n[%d/6] %s" % (n, text), flush=True)


def find_models_dir():
    """The pose model lives in ./models; a git worktree may share the main checkout's copy."""
    for d in (os.environ.get("VIDEO_MOCAP_MODELS", ""), os.path.join(HERE, "models")):
        if d and glob.glob(os.path.join(d, "pose_landmarker_*.task")):
            return d
    try:
        common = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=HERE, capture_output=True, text=True).stdout.strip()
        main = os.path.dirname(os.path.abspath(os.path.join(HERE, common))) if common else ""
        d = os.path.join(main, "kingdom", "tools", "anim", "video_mocap", "models")
        if glob.glob(os.path.join(d, "pose_landmarker_*.task")):
            return d
    except Exception:
        pass
    return None


def run(cmd, what, log_tail=25):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        tail = "\n".join((r.stdout + "\n" + r.stderr).strip().splitlines()[-log_tail:])
        raise Fail("%s failed (exit %d). Last output:\n%s" % (what, r.returncode, tail))
    return r.stdout


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("video")
    ap.add_argument("name")
    ap.add_argument("--loop", action="store_true", help="mark/close the clip as a loop (first frame = last frame)")
    ap.add_argument("--fps", type=float, default=30.0, help="output clip fps (default 30)")
    ap.add_argument("--height", type=float, default=1.75, help="actor height in m (only scales root travel)")
    ap.add_argument("--fov", type=float, default=66.0, help="camera FOV (deg) along the long image side")
    ap.add_argument("--face", default="first", help="first | travel | none | degrees")
    ap.add_argument("--root", default="blend", choices=["blend", "image", "feet", "none"], help="none = in-place clip")
    ap.add_argument("--start", type=float, help="trim start (s)")
    ap.add_argument("--end", type=float, help="trim end (s)")
    ap.add_argument("--no-ik", action="store_true", help="skip IK foot pinning")
    ap.add_argument("--no-render", action="store_true", help="skip the Blender preview render (sheets then show video + skeleton only)")
    ap.add_argument("--sheet-fps", type=float, default=0, help="sheet sampling fps (default: about 3 sheets)")
    ap.add_argument("--model", default="heavy", choices=["heavy", "full", "lite"])
    ap.add_argument("--azimuth", type=float, default=50.0, help="preview camera azimuth (0 = front)")
    a = ap.parse_args()
    t_start = time.time()
    try:
        return pipeline(a)
    except Fail as e:
        print("\n[video_to_clip] FAILED: %s" % e, file=sys.stderr)
        for p in (os.path.join(KINGDOM, "assets", "incoming", "animations_video", a.name),
                  os.path.join(REPO, "docs", "anim", "advanced", "video_mocap", "out", a.name)):
            try:
                os.rmdir(p)              # drop the empty output folders of a failed run
            except OSError:
                pass
        return 1


def pipeline(a):
    # ---------------------------------------------------------------- checks
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]{0,47}", a.name):
        raise Fail("ClipName '%s' must be letters, digits and _ only (start with a letter), e.g. Sword_Slash_1" % a.name)
    video = os.path.abspath(a.video)
    if not os.path.isfile(video):
        raise Fail("video not found: %s" % video)
    try:
        import numpy as np, cv2
        import mediapipe  # noqa: F401
    except ImportError as e:
        raise Fail("python packages missing (%s). Run once:  powershell -File %s" % (e, os.path.join(HERE, "setup.ps1")))
    cap = cv2.VideoCapture(video)
    if not cap.isOpened():
        raise Fail("OpenCV cannot open %s (unsupported codec? try re-exporting as H.264 .mp4)" % video)
    vfps = cap.get(cv2.CAP_PROP_FPS) or 0
    nframes = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    vw, vh = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    cap.release()
    dur = nframes / vfps if vfps else 0
    print("video: %dx%d, %.1f fps, %d frames, %.1f s" % (vw, vh, vfps, nframes, dur))
    if dur < 0.5:
        raise Fail("video is only %.2f s long; need at least 1 s (2-10 s recommended)" % dur)
    if dur > 30:
        print("WARNING: %.0f s is long; consider --start/--end (pose extraction runs ~10 fps on CPU)" % dur)
    if not os.path.isfile(BLENDER):
        raise Fail("Blender not found at %s (set env BLENDER to blender.exe)" % BLENDER)
    if not os.path.isfile(UAL_STD):
        raise Fail("UAL mannequin GLB missing: %s (git lfs / checkout problem?)" % UAL_STD)
    md = find_models_dir()
    if md:
        os.environ["VIDEO_MOCAP_MODELS"] = md
    else:
        print("note: no pose model found; it will be downloaded once (30 MB, Apache-2.0) into %s" % os.path.join(HERE, "models"))

    work = os.path.join(HERE, "out", a.name)
    if os.path.isdir(work):
        shutil.rmtree(work)
    os.makedirs(work)
    glb_dir = os.path.join(KINGDOM, "assets", "incoming", "animations_video", a.name)
    glb = os.path.join(glb_dir, "UAL_Video_%s.glb" % a.name)
    docs = os.path.join(REPO, "docs", "anim", "advanced", "video_mocap", "out", a.name)
    os.makedirs(glb_dir, exist_ok=True)
    os.makedirs(docs, exist_ok=True)
    for f in glob.glob(os.path.join(docs, "*")):
        os.remove(f)
    report = {"clip": a.name, "video": os.path.basename(video), "video_fps": vfps, "video_s": round(dur, 2)}

    # ---------------------------------------------------------------- 1 pose
    step(1, "pose landmarks (MediaPipe %s, CPU) ..." % a.model)
    import pose_extract
    d = pose_extract.extract(video, a.model, 0, log=lambda s: print(s, flush=True))
    miss = int(np.isnan(d["world"][:, 0, 0]).sum())
    frac = miss / max(1, len(d["world"]))
    print("  no-person frames: %d of %d" % (miss, len(d["world"])))
    if frac > 0.5:
        raise Fail("no person found in %.0f%% of the frames. Film the whole body (head to feet) in frame, one person, good light." % (frac * 100))
    if frac > 0.1:
        print("WARNING: person lost in %.0f%% of frames (gaps are interpolated). Check the sheets." % (frac * 100))
    # frames where the actor touches / leaves the image (pose collapses there): report, and trim them off the ends
    core = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]
    im = d["image"][:, core, :2]
    edge = np.isnan(im[:, :, 0]).any(1) | (im[:, :, 0] < 0.10).any(1) | (im[:, :, 0] > 0.90).any(1) | (im[:, :, 1] < 0.0).any(1) | (im[:, :, 1] > 0.985).any(1)
    i0, i1 = 0, len(d["world"])
    if a.start is not None or a.end is not None:
        i0 = int((a.start or 0) * d["fps"])
        i1 = int(a.end * d["fps"]) if a.end else len(d["world"])
    elif edge.any():
        ok = np.where(~edge)[0]
        if len(ok) < 10:
            raise Fail("the actor is cut off by the frame edge in almost every frame. Film from further away so head to feet stay inside the frame.")
        i0, i1 = max(0, int(ok[0]) - 0), min(len(edge), int(ok[-1]) + 1)
        if i0 or i1 < len(edge):
            print("  actor cut off by the frame edge in frames 0-%d and %d-%d: trimming to %d-%d (%.2f s). Use --start/--end to override." % (
                i0 - 1, i1, len(edge) - 1, i0, i1 - 1, (i1 - i0) / d["fps"]))
        mid = int(edge[i0:i1].sum())
        if mid:
            print("WARNING: %d frame(s) inside the clip have the actor touching the frame edge; those poses are unreliable." % mid)
    if i1 - i0 < 10:
        raise Fail("fewer than 10 usable frames after trimming (%d-%d)" % (i0, i1))
    if i0 or i1 < len(d["world"]):
        for k in ("world", "image", "vis"):
            d[k] = d[k][i0:i1]
        report["trim_frames"] = [i0, i1]
    npz = os.path.join(work, "pose.npz")
    np.savez_compressed(npz, **d)
    report["pose"] = {"no_person_frames": miss}

    # ---------------------------------------------------------------- 2 bvh
    step(2, "clean skeleton (gap fill, smoothing, fixed bone lengths) -> BVH")
    import mocap_to_bvh
    from bvhlib import write_bvh
    r = mocap_to_bvh.solve(d, a.height, a.fov, a.root, a.face, a.fps, True)
    raw_bvh = os.path.join(work, "clip_raw.bvh")
    write_bvh(raw_bvh, mocap_to_bvh.JOINTS, mocap_to_bvh.PARENT, list(r["off"]), dict(r["end"]), r["root"], r["Rl"], r["fps"])
    report["solve"] = r["info"]
    print("  %d frames @ %.0f fps, root travel %.2f m" % (len(r["root"]), r["fps"], float(((r["root"][-1] - r["root"][0]) ** 2)[[0, 2]].sum() ** 0.5)))

    # ---------------------------------------------------------------- 3 ik
    step(3, "IK foot pinning (contact detection, two-bone leg IK, floor clamp, pelvis level)")
    bvh = os.path.join(work, "clip.bvh")
    if a.no_ik:
        shutil.copy(raw_bvh, bvh)
        print("  skipped (--no-ik)")
    else:
        import foot_ik
        res = foot_ik.apply(raw_bvh, bvh)
        info = res[0] if isinstance(res, tuple) else res
        report["foot_ik"] = info
        sb, sa = info["slide_before"], info["slide_after"]
        print("  contacts L/R: %s runs %s" % (info["contact_frac"], info["contact_runs"]))
        print("  foot slide during contact (ankle): %.1f -> %.1f cm/s, toe %.1f -> %.1f cm/s" % (
            sb["ankle_mean_cm_s"], sa["ankle_mean_cm_s"], sb["toe_mean_cm_s"], sa["toe_mean_cm_s"]))
        print("  floor penetration frames: %d -> %d, pelvis lowered max %.1f cm, %d unreachable frames" % (
            info["penetration_frames_before"], info["penetration_frames_after"], info["pelvis_drop_max_cm"], info["unreachable_frames"]))
        json.dump(info, open(os.path.join(work, "foot_ik.json"), "w"), indent=1)

    # ---------------------------------------------------------------- 4 retarget
    step(4, "retarget to the UAL skeleton (Blender) -> %s" % os.path.relpath(glb, REPO))
    cmd = [sys.executable, os.path.join(HERE, "retarget_video_bvh.py"), bvh, "--name", a.name, "--out", glb]
    if a.loop:
        cmd.append("--loop")
    if a.root == "none":
        cmd.append("--no-root-track")
    print(run(cmd, "retarget").strip())
    if not os.path.isfile(glb):
        raise Fail("retarget produced no GLB")
    cj = glb + ".clips.json"
    clips = json.load(open(cj)) if os.path.isfile(cj) else [{}]
    clips[0].update({"video": os.path.basename(video), "video_mocap": True, "foot_ik": (not a.no_ik)})
    if not a.no_ik:
        clips[0]["foot_slide_cm_s"] = [report["foot_ik"]["slide_before"]["ankle_mean_cm_s"], report["foot_ik"]["slide_after"]["ankle_mean_cm_s"]]
    json.dump(clips, open(cj, "w"), indent=1)
    report["clip"] = clips[0]
    print("  clip %s: %.2f s, loop=%s, travel %s m" % (a.name, clips[0].get("seconds", 0), clips[0].get("loop"), clips[0].get("travel_m")))

    # ---------------------------------------------------------------- 5 render
    frames = os.path.join(work, "char")
    if a.no_render:
        step(5, "preview render skipped (--no-render)")
        frames = None
    else:
        step(5, "preview render of the result on the mannequin (Blender EEVEE, ~1 min)")
        env = dict(os.environ, CLIPGLB=glb, RESPCT="50", CAMR="3.4", CHECKER="1", FOLLOW="1")
        cmd = [BLENDER, "-b", "--python", os.path.join(HERE, "render_test_clip.py"), "--", UAL_STD, "Idle_Loop", frames, str(a.azimuth), "1"]
        rr = subprocess.run(cmd, capture_output=True, text=True, env=env)
        if rr.returncode != 0 or not glob.glob(os.path.join(frames, "f*.png")):
            print("WARNING: preview render failed; sheets will show video + skeleton only.\n" + "\n".join((rr.stdout + rr.stderr).splitlines()[-8:]))
            frames = None

    # ---------------------------------------------------------------- 6 sheets
    step(6, "sheets -> %s" % os.path.relpath(docs, REPO))
    import make_sheets
    n = make_sheets.build(video, bvh, frames, docs, a.sheet_fps, trim=report.get("trim_frames"), vfps=vfps, pose_img=d["image"],
                          ik_json=None if a.no_ik else os.path.join(work, "foot_ik.json"), raw_bvh=raw_bvh)
    json.dump(report, open(os.path.join(docs, "report.json"), "w"), indent=1, default=float)
    print("\nDONE")
    print("  GLB     : %s" % glb)
    print("  clips   : %s" % cj)
    print("  sheets  : %s  (%d sheet(s); READ them: sliding, jitter, facing, mirrored limbs)" % (docs, n))
    print("  add the GLB to Assets.UAL_FILES (Codex owns wiring); it uses the same 65-bone skeleton as UAL1_Standard.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
