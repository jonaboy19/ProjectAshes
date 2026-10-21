"""Screenshot Capture & World Preview Automation Tool.

Captures automated high-resolution screenshots from either the Godot 4.6 Engine runtime
or Blender 5.2 headless rendering, and automatically displays them on Windows desktop.

Usage:
  python tools/capture_screenshots.py --godot [shot_name]
  python tools/capture_screenshots.py --blender [shot_name]
  python tools/capture_screenshots.py --open
"""

import os
import sys
import subprocess

PROJECT_DIR = r"C:\Users\Jonna\Documents\ProjectAshes"
KINGDOM_DIR = os.path.join(PROJECT_DIR, "kingdom")
OUT_DIR = os.path.join(PROJECT_DIR, r"docs\img\actual_renders")
os.makedirs(OUT_DIR, exist_ok=True)

GODOT_BIN = r"C:\Users\Jonna\Downloads\Godot_v4.6-stable_win64.exe"
BLENDER_BIN = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"

SHOTS = [
    "explore", "first", "town", "command", "castle",
    "site_farm", "site_mine", "site_ruins", "site_bridge",
    "interior_inn", "interior_blacksmith", "interior_guild", "interior_healer", "interior_house",
    "guildhall", "orcs"
]

def capture_godot(shot_name="town"):
    out_file = os.path.join(OUT_DIR, f"godot_shot_{shot_name}.png")
    cmd = [
        GODOT_BIN,
        "--path", KINGDOM_DIR,
        "--headless",
        "--",
        f"--shot={shot_name}",
        f"--out={out_file}"
    ]
    print(f"Executing Godot shot: {' '.join(cmd)}")
    res = subprocess.run(cmd, capture_output=True, text=True)
    print(res.stdout)
    if os.path.exists(out_file):
        print(f"Captured: {out_file}")
        open_image(out_file)
    else:
        print(f"Failed to generate {out_file}: {res.stderr}")

def capture_blender():
    render_script = os.path.join(r"C:\Users\Jonna\.gemini\antigravity\brain\3da776b7-bb83-47d1-9df4-df5aec1eeb7f\scratch\render_world_and_interiors.py")
    if os.path.exists(render_script):
        cmd = [BLENDER_BIN, "-b", "-P", render_script]
        print("Executing Blender render...")
        subprocess.run(cmd)

def open_image(path):
    if os.path.exists(path):
        os.startfile(path)

def open_folder():
    os.startfile(OUT_DIR)

if __name__ == "__main__":
    if "--godot" in sys.argv:
        idx = sys.argv.index("--godot")
        shot = sys.argv[idx + 1] if len(sys.argv) > idx + 1 else "town"
        capture_godot(shot)
    elif "--blender" in sys.argv:
        capture_blender()
    else:
        open_folder()
