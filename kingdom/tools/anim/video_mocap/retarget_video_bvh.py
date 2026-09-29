"""Step 3: video BVH -> UAL 65-bone GLB clip, using the EXISTING tools/anim/retarget_clips_to_ual.py (run inside Blender).

  python retarget_video_bvh.py out/sword.bvh --name Sword_Video_Test --out out/sword_ual.glb
         [--loop] [--inplace smooth|linear|full|none] [--fingers relaxed|fist] [--start S --end E] [--blender PATH]

Writes out/<name>.cfg.json (same format as tools/anim/cfg_cmu.json; the joint map is copied from it) and runs
  blender -b --python retarget_clips_to_ual.py -- cfg.json
The produced GLB has one clip, on the same skeleton as UAL_Souls_Cat.glb / UAL_CMU_Mocap.glb, and can be added to
Assets.UAL_FILES like them.
"""
import argparse, json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ANIM = os.path.dirname(HERE)
KINGDOM = os.path.dirname(os.path.dirname(ANIM))
BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bvh")
    ap.add_argument("--name", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--loop", action="store_true")
    ap.add_argument("--inplace", default="smooth", choices=["smooth", "linear", "full", "none"])
    ap.add_argument("--fingers", default="relaxed")
    ap.add_argument("--smooth", type=float, default=0.02, help="extra Gaussian smoothing (s) inside the retargeter")
    ap.add_argument("--start", type=float)
    ap.add_argument("--end", type=float)
    ap.add_argument("--no-root-track", action="store_true", help="omit the root-motion track (in-place clip only)")
    ap.add_argument("--blender", default=os.environ.get("BLENDER", BLENDER))
    a = ap.parse_args()
    base = json.load(open(os.path.join(ANIM, "cfg_cmu.json")))
    bvh = os.path.abspath(a.bvh)
    clip = {"name": a.name, "file": os.path.basename(bvh), "fingers": a.fingers, "inplace": a.inplace}
    if a.loop:
        clip["loop"] = True
    if a.start is not None:
        clip["start"] = a.start
    if a.end is not None:
        clip["end"] = a.end
    cfg = {"source_type": "bvh", "bvh_dir": os.path.dirname(bvh),
           "ual": os.path.join(KINGDOM, "assets", "incoming", "quaternius", "universal-animation-library", "Unreal-Godot", "UAL1_Standard.glb"),
           "out": os.path.abspath(a.out), "smooth": a.smooth, "fingers": a.fingers,
           "finger_poses": base["finger_poses"], "map": base["map"], "check_directions": True,
           "root_motion_track": not a.no_root_track, "clips": [clip]}
    cfgp = os.path.splitext(os.path.abspath(a.out))[0] + ".cfg.json"
    os.makedirs(os.path.dirname(cfgp), exist_ok=True)
    json.dump(cfg, open(cfgp, "w"), indent=1)
    cmd = [a.blender, "-b", "--python", os.path.join(ANIM, "retarget_clips_to_ual.py"), "--", cfgp]
    r = subprocess.run(cmd, capture_output=True, text=True)
    for line in r.stdout.splitlines():
        if line.startswith(("CLIP", "DIRCHECK", "EXPORTED", "WARNING")):
            print(line)
    if r.returncode != 0 or not os.path.exists(a.out):
        print(r.stdout[-3000:], r.stderr[-2000:])
        sys.exit(1)


if __name__ == "__main__":
    main()
