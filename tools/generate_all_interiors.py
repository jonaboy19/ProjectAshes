"""Batch generate all new AAA procedural interiors with Blender 5.2
Runs each builder, bakes vertex lighting, generates Godot .tscn and renders high-res preview PNGs.
"""
import os, sys, subprocess, time

BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
TOOLS_BLENDER = os.path.join(ROOT, "kingdom", "tools", "blender")

SCRIPTS = [
    "make_interior_manor.py",
    "make_interior_trader.py",
    "make_interior_sect.py",
    "make_interior_orc.py",
    "make_interior_academy.py",
]

def main():
    print("=" * 70)
    print("STARTING PROCEDURAL INTERIORS BATCH GENERATION (BLENDER 5.2)")
    print("=" * 70)
    total_start = time.time()
    
    for s in SCRIPTS:
        script_path = os.path.join(TOOLS_BLENDER, s)
        print(f"\n---> Building: {s}")
        t0 = time.time()
        cmd = [BLENDER, "-b", "--python", script_path]
        res = subprocess.run(cmd, capture_output=True, text=True)
        dt = time.time() - t0
        if res.returncode == 0:
            print(f"SUCCESS in {dt:.1f}s")
            # print last few lines of stdout
            lines = [l for l in res.stdout.splitlines() if "wrote " in l or "tris" in l]
            for l in lines[-5:]:
                print(f"    {l}")
        else:
            print(f"FAILED in {dt:.1f}s (code {res.returncode})")
            print("STDERR:")
            print(res.stderr[-500:])
            print("STDOUT:")
            print(res.stdout[-500:])

    print("\n" + "=" * 70)
    print(f"ALL INTERIORS COMPLETE IN {time.time() - total_start:.1f}s")
    print("=" * 70)

if __name__ == "__main__":
    main()
