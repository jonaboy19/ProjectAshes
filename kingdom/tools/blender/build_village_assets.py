"""Rebuild the Blender village building set (GLB + preview PNG) and the street
composite preview.

Run from the repo root:
    python3 kingdom/tools/blender/build_village_assets.py [--no-preview] [--no-street] [--out DIR] [names...]

Names are output names (e.g. village_house_a_2); default is the full set.
Outputs go to kingdom/assets/generated/<name>.glb and
docs/kingdom/blender_previews/<name>.png. Needs the bpy module (Blender 5.x).
Colour variants: <asset>_2.glb is the same generator run with --variant=2.
"""
import os, sys, subprocess, time, re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(ROOT, "kingdom", "assets", "generated")
PREV = os.path.join(ROOT, "docs", "kingdom", "blender_previews")
ASSETS = ["village_house_a", "village_house_a_2", "village_house_b", "village_house_b_2",
          "village_house_c", "village_house_c_2", "village_house_d", "village_house_d_2",
          "village_inn", "village_smithy", "village_barn", "village_stall", "village_stall_2",
          "fence_section"]


def main():
    argv = sys.argv[1:]
    out_dir, prev_dir = OUT, PREV
    if "--out" in argv:
        i = argv.index("--out")
        out_dir = prev_dir = os.path.abspath(argv[i + 1])
        del argv[i:i + 2]
    names = [a for a in argv if not a.startswith("--")] or ASSETS
    preview = "--no-preview" not in argv
    os.makedirs(out_dir, exist_ok=True)
    os.makedirs(prev_dir, exist_ok=True)
    ok = True
    for n in names:
        m = re.match(r"(.+?)_(\d+)$", n)
        script, variant = (m.group(1), int(m.group(2))) if m else (n, 1)
        cmd = [sys.executable, os.path.join(HERE, f"make_{script}.py"), os.path.join(out_dir, f"{n}.glb"),
               f"--variant={variant}"]
        if preview:
            cmd.append(os.path.join(prev_dir, f"{n}.png"))
        t0 = time.time()
        r = subprocess.run(cmd, capture_output=True, text=True)
        fp = next((l for l in r.stdout.splitlines() if l.startswith("footprint")), "")
        warn = [l for l in r.stdout.splitlines() if l.startswith("WARNING")]
        if r.returncode != 0 or not fp:
            ok = False
            print(f"[FAIL] {n}\n{r.stdout[-2000:]}\n{r.stderr[-2000:]}")
        else:
            print(f"[{'ok' if not warn else 'WARN'}] {n}: {fp.split(': ', 1)[1]}  ({time.time() - t0:.0f}s)")
            for w in warn:
                print("      " + w)
                ok = False
    if preview and "--no-street" not in argv and not [a for a in argv if not a.startswith("--")]:
        cmd = [sys.executable, os.path.join(HERE, "make_village_street_preview.py"), out_dir,
               os.path.join(prev_dir, "village_street.png")]
        r = subprocess.run(cmd, capture_output=True, text=True)
        print("[ok] street preview" if r.returncode == 0 else f"[FAIL] street\n{r.stderr[-2000:]}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
