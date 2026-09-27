"""Rebuild the Blender village building set (GLB + preview PNG) and the street
composite preview.

Run from the repo root:
    python3 kingdom/tools/blender/build_village_assets.py [--no-preview] [--no-street] [--out DIR] [names...]

Names are output names (e.g. village_house_a_2); default is the full set.
Outputs go to kingdom/assets/generated/<name>.glb and
docs/kingdom/blender_previews/<name>.png. Needs the bpy module (Blender 5.x).
Colour variants: <asset>_N.glb is the same generator run with --variant=N (houses
have 4 variants each: palette, roof, dormers, signs, ivy, planters, mirroring).
Buildings also write <name>_lod1.glb. Shared detail textures come from
make_village_textures.py (run automatically if village_tex/ is missing).
"""
import os, sys, subprocess, time, re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(ROOT, "kingdom", "assets", "generated")
PREV = os.path.join(ROOT, "docs", "kingdom", "blender_previews")
ASSETS = ([f"village_house_{t}{s}" for t in "abcd" for s in ("", "_2", "_3", "_4")] +
          ["village_inn", "village_smithy", "village_barn", "village_stall", "village_stall_2", "village_stall_3",
           "village_stall_4", "fence_section", "planter_box", "flower_bed"])
# buildings also get <name>_lod1.glb (same build, detail faces swapped for stand-ins)
LOD1 = ("village_house_", "village_inn", "village_smithy", "village_barn")


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
    if not os.path.exists(os.path.join(ROOT, "kingdom", "assets", "generated", "village_tex", "ra_wood_alb.png")):
        subprocess.run([sys.executable, os.path.join(HERE, "make_village_textures.py")], check=True)
    ok = True
    for n in names:
        m = re.match(r"(.+?)_(\d+)$", n)
        script, variant = (m.group(1), int(m.group(2))) if m else (n, 1)
        cmd = [sys.executable, os.path.join(HERE, f"make_{script}.py"), os.path.join(out_dir, f"{n}.glb"),
               f"--variant={variant}"]
        if preview:
            cmd.append(os.path.join(prev_dir, f"{n}.png"))
        if n.startswith(LOD1):
            cmd.append("--lod1")
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
