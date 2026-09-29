# Phone video -> UAL clip (own mocap)

Pipeline (all local, CPU, no accounts): **video -> MediaPipe Pose Landmarker (heavy, 3D world landmarks) -> cleaned BVH
-> `retarget_clips_to_ual.py` -> GLB clip on the 65-bone UAL skeleton**. Scripts live in `../video_mocap/`.

## Setup (once)
```powershell
cd kingdom\tools\anim\video_mocap
powershell -File setup.ps1 -Python C:\Users\Jonna\AppData\Local\Python\pythoncore-3.14-64\python.exe   # venv (gitignored) + 30 MB model
```
Tested: Python 3.14.2, mediapipe 1.0.1, Blender 5.2. Keep videos and outputs OUTSIDE the repo (e.g. `C:\Users\Jonna\Documents\ProjectAshes_art_staging\anim_raw2\video_mocap`).

## Run (three commands)
```powershell
$py = ".venv\Scripts\python.exe"; $o = "C:\...\video_mocap\out"
& $py pose_extract.py  C:\...\kick.mp4 $o\kick_pose.npz                     # 1. landmarks (~10 fps on CPU)
& $py mocap_to_bvh.py  $o\kick_pose.npz $o\kick.bvh --height 1.75 --fov 66 --face first --root blend
& $py retarget_video_bvh.py $o\kick.bvh --name My_Kick --out $o\My_Kick_UAL.glb [--loop] [--inplace linear] [--start 1.0 --end 3.2]
```
`--fov` = camera field of view along the LONG image side (phone main lens ~66-70; wide 0.5x ~ 100+). Only matters for root travel.
`--root none` gives a fully in-place clip. `--face travel` turns the actor to face +Z along the walking direction.
Check the result: `preview_strip.py video bvh strip.png [--char-frames DIR]` (source frame | skeleton front | skeleton side | character),
`render_test_clip.py` renders a UAL clip as a fake video with ground truth (`gt.json`), `compare_gt.py` scores a BVH against it.
The GLB then goes to `assets/incoming/animations_free2/`-style folders like the other libraries (add to `Assets.UAL_FILES`).

## How to film
- Phone on a **tripod or fixed prop**, landscape or portrait, **camera at hip/chest height (~1 m), level (no tilt)**, 3-5 m from the actor so the whole body incl. feet is in frame with 20 % margin the whole time.
- **One person only**; plain uncluttered background; bright even light (overcast/daylight, no strong backlight). Fitted clothes contrasting with the background; no long coats/skirts/hoods, shoes visible, hair off the neck.
- **30 or 60 fps**, fast shutter (bright light), no digital stabilisation/zoom. Start and end in a neutral standing pose for 1 s.
- **Front-3/4 view (~30-45 degrees off the camera axis)** gives the best depth cues for punches/kicks; pure side view for walks/runs; avoid exact back view (left/right flips). For attacks that thrust toward/away from the camera, film two takes (front and 45 degrees).
- Do the move slightly slower and larger than in game; 3-10 s clips. Walking clips: walk across the frame, 3+ steps.

## Limitations of monocular mocap (and what the cleaner does)
| problem | cleaner |
|---|---|
| depth ambiguity (limbs pointing at/away from the camera are wrong by 20-40 degrees; measured 26 deg mean bone error vs ground truth on a synthetic mannequin, all in MediaPipe itself) | none possible: film a second angle, or fix the pose by hand in Blender |
| jitter | forward+backward One-Euro filter (`--mincut`, `--beta`), outlier rejection, gap filling |
| bones stretch | fixed per-actor bone lengths, rotations only |
| foot sliding / floating | foot-contact detection, floor and hip height from planted feet, root travel from foot odometry blended with image projection, foot flattened while planted (walk test: 4.1 m recovered vs 3.9 m true; residual slide ~0.6 m/s vs 0.2 truth) |
| no wrist / finger rotation | hand follows forearm; retargeter adds relaxed/fist fingers |
| head roll/pitch weak | neutral-head calibration; expect small errors |
| actor cut off by the frame edge | pose collapses for those frames: trim with `--start/--end` |
| camera pitch / zoom / handheld | assumed level and static; root height/travel drift otherwise |

## Tools evaluated (licences)
| tool | verdict |
|---|---|
| **MediaPipe Pose Landmarker** (Apache-2.0 code; heavy/full/lite `.task` models Apache-2.0 per model card) | USED: pip install, CPU, no account, commercial output OK |
| FreeMoCap (AGPL-3.0, uses MediaPipe/Blender) | heavier, multi-camera oriented, AGPL; not needed |
| video2bvh (MIT) | old (OpenPose/VideoPose3D weights are non-commercial); superseded by this pipeline |
| BlendArMocap (GPL-3 Blender add-on, MediaPipe based) | works in Blender live; same core model, no cleaning; alternative for quick tests |
| Rokoko Video (free tier) | needs account, cloud, terms limit; document only |
| MotionBERT (Apache-2.0 code, weights research-only?), 4DHumans/HMR2 (weights under SMPL licence: non-commercial), WHAM/GVHMR (SMPL body model non-commercial) | NOT used: SMPL licences forbid commercial use without a paid licence; GPU setup heavy. Revisit only with a commercial SMPL licence |

## Remaining work
- Only tested on synthetic mannequin videos (Blender renders of UAL clips); run on a real phone clip and tune `--fov`, `--mincut/--beta`.
- No hand/finger orientation, no IK foot pinning (only flattening + odometry), no automatic loop closing (retargeter `--loop` handles it).
- Add a one-shot wrapper and a `docs/anim/advanced/README.md` link (owned by another agent).
