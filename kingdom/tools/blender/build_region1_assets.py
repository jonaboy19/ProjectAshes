"""Rebuild all first-region Blender assets (GLB + preview PNG).

Run from the repo root:  python3 kingdom/tools/blender/build_region1_assets.py [--no-preview] [names...]
Outputs go to kingdom/assets/generated/<name>.glb and
docs/kingdom/blender_previews/<name>.png. Needs the bpy module (Blender 5.x).
"""
import os, sys, subprocess, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(ROOT, "kingdom", "assets", "generated")
PREV = os.path.join(ROOT, "docs", "kingdom", "blender_previews")
ASSETS = ["adventurer_guild", "healer_house", "guild_board", "pier", "rowboat",
          "orc_hut", "orc_palisade", "orc_totem"]

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    preview = "--no-preview" not in sys.argv
    names = args or ASSETS
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(PREV, exist_ok=True)
    ok = True
    for n in names:
        cmd = [sys.executable, os.path.join(HERE, f"make_{n}.py"), os.path.join(OUT, f"{n}.glb")]
        if preview:
            cmd.append(os.path.join(PREV, f"{n}.png"))
        if n in ("adventurer_guild", "healer_house"):
            cmd.append("--lod1")
        t0 = time.time()
        r = subprocess.run(cmd, capture_output=True, text=True)
        line = next((l for l in r.stdout.splitlines() if l.startswith("wrote")), None)
        if r.returncode != 0 or not line:
            ok = False
            print(f"[FAIL] {n}\n{r.stdout[-2000:]}\n{r.stderr[-2000:]}")
        else:
            print(f"[ok] {n}: {line.split('  ', 1)[-1]}  ({time.time() - t0:.0f}s)")
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
