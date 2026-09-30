# Locomotion transitions + jump set (UAL skeleton)

`kingdom/assets/incoming/animations_free2/loco_transitions/UAL_Loco_Transitions.glb` (20 clips, 30 fps) with two sidecars:

| file | content |
|---|---|
| `UAL_Loco_Transitions.glb.clips.json` | list, one entry per clip (same fields as the other libraries, plus the ones below) |
| `UAL_Loco_Transitions.glb.contacts.json` | `{"clips": {name: entry}, "reference_loops": {...}}`: foot-contact windows, slide, root motion, loop hand-off phases, events |

## Rebuild
```
bash tools/anim/loco/fetch_loco_sources.sh                       # CMU BVH -> $LOCO_SRC/cmu
python tools/anim/loco/make_cfg_loco.py                          # cfg_loco.json from the CLIPS table
LOCO_SRC=... blender -b -P tools/anim/loco/retarget_loco.py -- tools/anim/loco/cfg_loco.json
python tools/anim/glb_reduce_anim.py <glb> --rot-deg 0.08 --pos-m 0.0005
python tools/anim/check_unique_clips.py
```
Env: `LOCO_OUT` (other output path), `LOCO_ONLY=NameA,NameB`, `LOCO_DEBUG=1` (dumps `<clip>.feet.npy`: world feet, root, pelvis).

## What `retarget_loco.py` adds on top of `retarget_bvh.py`
`speed`/`warp` (time), `match_entry`/`match_exit` (trim on the frame whose pose is closest to a UAL loop, phase reported),
`yaw_root` (heading change on the `root` bone rotation), `air_z` (airborne pelvis at ground-relative height, the capsule owns the arc),
`travel_fit` (scale pelvis travel so planted feet do not slide), `pingpong` (seamless hover loop from a still window),
`segments` (compose several windows, crossfaded; `{"ual": "Roll"}` takes a window of an existing UAL clip), a per-clip foot-contact report,
root speeds, and per-clip `map` (100STYLE skeleton map is in the history of this folder's notes; not used in the final set).

## Conventions (all clips)
* Character forward = the rest facing of UAL (Blender -Y, Godot +Z after import). Root motion: `root` bone position track = horizontal travel of the body,
  `root` rotation track = heading change (`yaw_root` clips). The pelvis carries only the sway and residual. The `root` position track of these clips is **enabled**
  (library lives in `animations_free2`, not in `animations/`); `sidecar.root.*` has the numbers if you would rather ignore the track.
* Yaw sign: + = turn left (counter-clockwise seen from above).
* Contact windows are frame ranges at 30 fps: a foot counts as touching when its ankle or ball is within 3 cm of the rest height. `slide_cm` = largest drift of a planted point
  (planted = low and slower than 0.5 m/s). All shipped clips are <= 6.7 cm; most are < 4.5.
* `handoff.entry / exit`: the UAL loop, the phase (0..1, `side` L when phase < 0.5, the same rule as `CharacterAnimator._phase`) whose pose is closest to the first / last frame,
  and the mean bone error in degrees (24-31 = same gait, different actor: use a 0.1 s blend).

## Sources and licences
CMU Graphics Lab Motion Capture Database (free, commercial use allowed, credit line in `kingdom/CREDITS.md`), BVH by Bruce Hahne. Takes used:
16_31, 16_33, 16_55, 16_05 (subject 16), 127_17/18/19/27 (subject 127, action adventure), 36_02/03/09 (subject 36), 13_41/42 (subject 13), 82_04 (subject 82).
`Jump_Land_Roll` reuses the UAL `Roll` clip (Quaternius UAL, CC0) after a CMU landing. 100STYLE (CC BY 4.0) was surveyed (`Neutral_TR1`): its transitions are walk-pace and
mostly sideways or backwards, and the CMU set covered every requested clip, so no 100STYLE data is in this library (the earlier `Style_*` clips are unchanged).
