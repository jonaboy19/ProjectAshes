# Own mocap from a phone video

Film a move, run ONE command, get an animation on the game skeleton (UAL, 65 bones) plus review pictures.

## How to film
- Whole body in frame, head to feet, with a margin on all sides for the whole clip (tight framing is the #1 failure).
- Side-on or 3/4 view (about 45 degrees). Not exactly from behind (left/right get swapped).
- Phone steady: tripod or leaning on something, camera at hip/chest height, level, no zoom, no stabilisation.
- 30-60 fps, bright even light, plain background, tight/fitted clothes that contrast with the background, shoes visible.
- One person only. 2-10 seconds. Stand still (or T/A-pose) for 1 s at the start and end, then do the move a bit slower and bigger than in game.
- Walks/runs: walk across the frame, 3+ steps. Attacks that thrust at the camera: film a second take from 45 degrees.

## The command
```powershell
cd kingdom\tools\anim\video_mocap
powershell -File video_to_clip.ps1 C:\path\to\clip.mp4 Sword_Slash_1 -Loop -Fps 30     # -Loop only for loops (walk, idle)
```
First time on a PC: `powershell -File setup.ps1` (venv + 30 MB pose model). Git Bash: `./video_to_clip.sh clip.mp4 Name --loop`.
Extra options: `--fov 66` (camera field of view along the long side, matters for how far the actor travels; phone main lens 66-70),
`--root none` (in-place clip), `--face travel`, `--start 1.0 --end 4.5` (trim), `--no-ik`, `--no-render`. Errors say what to fix.

## Where it lands
- `kingdom/assets/incoming/animations_video/<Name>/UAL_Video_<Name>.glb` (one clip, same skeleton as `UAL1_Standard.glb`) and `.glb.clips.json` (length, loop, root travel, foot slide numbers).
- `docs/anim/advanced/video_mocap/out/<Name>/sheet_00N.png`: rows of source video | recovered skeleton front | side | retargeted mannequin on a checker floor, labelled `#frame time`; `foot_ik.png`: ankle speed before/after IK with contact phases shaded.
- Raw work files (pose, BVH, frames) in `kingdom/tools/anim/video_mocap/out/<Name>/` (gitignored).
- Preview: open the sheets. In Godot add the GLB to `Assets.UAL_FILES` like the other libraries (Codex owns the wiring).

## What the tool does after the pose estimate
Gap fill + smoothing, fixed bone lengths, trim of frames where the actor touches the frame edge, then **IK foot pinning**: contact detection (ankle speed
+ height), feet locked to the floor during contact with a 0.12 s blend, two-bone leg IK keeping the knee direction, feet never below the floor, pelvis lowered when a locked leg would over-stretch, hip roll damped.
Measured on a synthetic walk (`Test_Walk`, ground truth known): foot sliding in contact **32 cm/s -> 0.5 cm/s** against the ground-truth contact frames (37 -> 0.4 by the tool's own detector); floor penetration frames 153 -> 0; limb-direction error 22.7 -> 23.5 degrees (IK trades a little pose accuracy for planted feet); hip height error 1 -> 3 cm.

## Known limits
- Single camera = depth guesses: arms/legs pointing at or away from the camera are off by 20-40 degrees (MediaPipe limit). A second angle or a hand fix in Blender is the remedy.
- Test so far is SYNTHETIC only (mannequin rendered in Blender). Not yet tried on real phone footage: expect worse jitter, tune `--fov`.
- No finger or wrist twist (hand follows the forearm), weak head roll, root travel only as good as `--fov` and the foot odometry.
- Jumps, floor work, fast spins and clips where the actor leaves the frame are unreliable; camera must be static and level.
- Pinning assumes flat ground; on stairs or slopes feet snap to y = 0.
- Tech details and tool comparison: `kingdom/tools/anim/video_to_bvh/README.md`.
- Older first-version test files here (`sword_*`, `walk_*`, `*.bvh`, `Sword_Video_Test_UAL.glb`) were made without IK pinning.
