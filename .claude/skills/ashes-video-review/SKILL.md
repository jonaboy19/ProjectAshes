---
name: ashes-video-review
description: Review motion (videos, animations, VFX, UI transitions, camera moves, gameplay) "stop-motion" style - capture many frames, tile them into numbered/timestamped contact sheets plus a motion-difference sheet, and read them in order. Use whenever something moves and must be judged - mocap clips, attack combos, spell VFX, intro/cutscene videos, menu transitions, fps hitches, or any video the owner sends.
---

# Stop-motion video review

Claude can't watch a video, but it can read images. So we turn motion into **ordered contact sheets**: many frames per image, each labelled `#frame  hh:mm:ss.mmm`, read left→right and top→bottom like a comic.

## 1. Get frames
**A video file** (for example one the owner sends, or a phone recording): use it directly.

**The game or a test scene**, using Godot Movie Maker (deterministic, and a fixed fps even when the PC is slow):
```bash
G="C:/Users/Jonna/Downloads/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe"
"$G" --path kingdom --write-movie /tmp/cap/frame.png --fixed-fps 30 --quit-after 150 res://tools_qa/<scene>.tscn
# → frame00000000.png … (150 frames = 5 s). Never add --headless (black frames).
```
- Use `.avi` instead of `.png` if you also want a video file to send the owner.
- To capture from a script, save `get_viewport().get_texture().get_image()` every N frames.

**Blender animation previews:** render a PNG sequence with `bpy.ops.render.render(animation=True)` (Workbench/EEVEE, low resolution).

## 2. Make the sheets
```bash
tools/qa/video_to_sheets.sh <video|frames_dir> <out_dir> [fps=6] [cols=4] [rows=3] [width=480]
# frames dir: set SRC_FPS=<capture fps> (default 30)
```
Output:
- `sheet_001.png …`: frames tiled in order, labelled with frame number and time.
- `motion.png`: the difference between consecutive frames (white = moved, black = still).
- `info.txt`: duration, and seconds covered per sheet.

Pick the sampling rate for the job:

| What | Sample fps | Why |
|---|---|---|
| Intro/cutscene, menu flow | 4–6 | overall story and timing |
| Locomotion loop, idle | 10–12 | foot plants, sliding, loop pop |
| Attack combo, hit reaction, VFX impact | 15–30 (short window) | anticipation, impact frame, hitstop |
| Hunting a hitch or stutter | capture 60 and use `motion.png` | a frozen frame shows as a black tile; a pop shows as a very bright tile |

Zoom in on detail by cropping first, e.g. `ffmpeg -i in.mp4 -vf crop=w:h:x:y …`, or capture at a closer camera.

## 3. Read like an animator
Read **every** sheet in order. For each one, write down what happens and when (with the frame number), then check:

- **Timing:** anticipation → action → impact → recovery. Is the impact 1–3 frames at 30 fps? Is there hitstop? Is it snappy, not floaty?
- **Motion:** feet planted during contact (no sliding), no knee/wrist snapping, facing correct, root motion moving the body, a clean loop (last frame ≈ first frame).
- **VFX:** the effect reads at phone size, spawns on the right frame (hand or impact), fades cleanly, doesn't cover the character, and matches the warm storybook style.
- **UI and transitions:** no black flash, no pop-in, text readable, the fade finishes.
- **Camera:** no jitter (compare static objects between frames), and shake is short.
- **`motion.png`:**
  - uniform noise across the frame = camera jitter;
  - one very bright tile = a pop or teleport;
  - a black tile in the middle of an action = a freeze or hitch.

## 4. Report
- Send the owner 1–3 of the best sheets (SendUserFile) and name the frames that matter ("impact at #14, 0.47 s").
- Put the sheets in `docs/<area>/<topic>/frames/`, or keep them outside the repo if they are large.
- Feed the gaps into `ashes-aaa-review`.
