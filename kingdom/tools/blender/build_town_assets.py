"""Rebuild the Blender landmark / fortification / prop set (GLB + preview PNG)
and the village-square composite preview.

Run from anywhere:
    python3 kingdom/tools/blender/build_town_assets.py [--no-preview] [--no-square] [--out DIR] [names...]

Names are output names (e.g. town_wall); default is the full set. Outputs go
to kingdom/assets/generated/<name>.glb and docs/kingdom/blender_previews/<name>.png.
Needs the bpy module (Blender 5.x). Each generator is make_<name>.py and uses
town_kit.py (which builds on village_kit.py / ra_kit.py).
"""
import os, sys, subprocess, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(ROOT, "kingdom", "assets", "generated")
PREV = os.path.join(ROOT, "docs", "kingdom", "blender_previews")
ASSETS = ["village_well", "bell_tower", "chapel", "temple", "town_wall", "town_wall_tower", "town_gate",
          "castle_keep", "market_cart", "hand_cart", "lamp_post", "signpost", "haystack", "woodpile",
          "washing_line", "garden_plot", "field_crops",
          "market_stall_red", "market_stall_green", "street_lamp", "banner_pole", "wall_banner", "shop_sign",
          "bunting", "flower_strip", "barrel_cluster"]
# <name>_lod1.glb for buildings, plus a remeshed <name>_lod2.glb proxy for the big landmarks
LOD1 = {"bell_tower", "chapel", "temple", "town_wall", "town_wall_tower", "town_gate", "castle_keep"}
LOD2 = {"temple", "castle_keep", "town_gate", "bell_tower"}


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
        cmd = [sys.executable, os.path.join(HERE, f"make_{n}.py"), os.path.join(out_dir, f"{n}.glb")]
        if preview:
            cmd.append(os.path.join(prev_dir, f"{n}.png"))
        if n in LOD2:
            cmd.append("--lod2")
        elif n in LOD1:
            cmd.append("--lod1")
        t0 = time.time()
        r = subprocess.run(cmd, capture_output=True, text=True)
        fp = next((l for l in r.stdout.splitlines() if l.startswith("footprint")), "")
        warn = [l for l in r.stdout.splitlines() if l.startswith("WARNING")]
        if r.returncode != 0 or not fp:
            ok = False
            print(f"[FAIL] {n}\n{r.stdout[-2000:]}\n{r.stderr[-3000:]}")
        else:
            print(f"[{'ok' if not warn else 'WARN'}] {n}: {fp.split(': ', 1)[1]}  ({time.time() - t0:.0f}s)")
            for w in warn:
                print("      " + w)
                ok = False
    if preview and "--no-square" not in argv and not [a for a in argv if not a.startswith("--")]:
        cmd = [sys.executable, os.path.join(HERE, "make_village_square_preview.py"), out_dir,
               os.path.join(prev_dir, "village_square.png")]
        r = subprocess.run(cmd, capture_output=True, text=True)
        print("[ok] village square preview" if r.returncode == 0 else f"[FAIL] square\n{r.stderr[-2000:]}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
