# Authored traversal clips v2 (ladder, wall, ledge, vault, horse riding)

Hand-authored on the Quaternius UAL skeleton with Blender IK. Output: `kingdom/assets/incoming/animations_free2/traversal_authored/UAL_Authored_Traversal.glb`
(+ `.clips.json`). Replaces the placeholders of `../free2/author_traversal.py` (which is still imported for the rig setup).

## Rebuild

```
BL="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
"$BL" -b -P author_traversal_v2.py -- <out.glb> [Clip,Clip,...]          # all clips, or a comma list of names (without _Loop)
"C:/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" ../glb_reduce_anim.py <out.glb> --rot-deg 0.08 --pos-m 0.0005
```

Check the result with `blender -b -P scan_motion.py -- <glb> <out.json> [--clips=A,B] [--top=6]` (jump limits below) and render with
`blender -b -P render_clips_trav.py -- <glb> <dir> --props --follow --fps=30` (`--fps=15` for long clips), tile with `../polish/make_sheets.sh`.

The run prints, per clip, `REACH` (IK effector misses larger than 2 cm: a hand/foot that could not reach its world target)
and, for the vaults, `BOX` (penetration of limbs/pelvis/torso into the 0.92 m box). Both should be `none` / below about 2 cm.
The build takes about a minute (Blender start + 14 clips).

## Files

| file | what |
|---|---|
| `author_traversal_v2.py` | driver: imports the clip modules, bakes every clip, exports the GLB (NLA tracks, `_Loop` suffix for loops) and the `.clips.json` sidecar |
| `trav_lib.py` | keyframe tracks (`Trk`, Hermite, zero tangents at holds so plants never slide), hand/foot geometry (`hand_rot`, `foot_rot`, ball-of-foot and palm-centre anchoring), `bake2` (absolute hand/foot orientation, subtree follows), reach + box checks |
| `clips_vault.py` | `Vault_Low` (left side, pivot on the right hand), `Vault_Low_B` (mirror: right side) |
| `clips_climb.py` | `Ladder_Climb_Up/Down`, `Wall_Climb_Up`, `Ledge_Hang_Idle`, `Ledge_Shimmy_L/R` |
| `clips_ride.py` | `Ride_Idle/Walk/Trot/Gallop`, `Ride_Lean_L/R` (`Ride_Trot` = rising / posting trot) |
| `clips_ledge.py` | `Ledge_Grab`, `Ledge_Climb_Up`, `Ledge_Drop_Down` (v2 helpers, chain with `Ledge_Hang_Idle_Loop`) |
| `clips_mantle.py` | `Mantle_Low` (1.0 m wall), `Mantle_High` (1.8 m wall; reuses the `Ledge_Climb_Up` pull / knee-up / stand) |
| `scan_motion.py` | per-frame motion scan of any clip GLB: bone head deltas (world and root-motion-removed = character space), local rotation deltas, per group maxima, contact drift from the sidecar, loop gap |
| `frames_sheet.sh` | tiles chosen source frames (side + front) into one labelled jpg (before / after comparisons) |
| `render_clips_trav.py` | copy of `../polish/render_clips.py` whose props match this geometry (see below); same CLI, plus `--follow[=span]` (camera follows the pelvis height, for tall climbs) |

## Geometry contract (world, metres; character faces -Y, +Z up, +X = character's left; root starts at the origin)

* Vault: box x +-0.9, y -1.4..-0.9, top z 0.92. Root Y travels 2.7 m (monotone). Palms flat on the top at y -1.05 (hand-fixed while planted).
* Ladder: rails x +-0.27, rung plane y = -0.31, rungs every 0.3 m at z = 0.3k (hands on rungs 1.5 and 1.8 m at the start, i.e. the handoff's
  "first hand rung ~1.45 m"), root Z rises 0.6 m per 1.2 s loop (two rungs). Feet: ball of the foot on a rung. Down = the same cycle played backwards with root Z -0.6.
* Wall: face y = -0.36, holds 6 cm deep on four limb lines (hands x +-0.30, feet x +-0.22, one hold per 0.5 m per line), root Z 0.5 m per 1.4 s loop.
* Ledge: top z = 2.12, front face y = -0.20. Hang: hands on top (x +-0.21), pelvis 1.125 m, feet dangle 0.2 m above the floor. Shimmy: four 0.25 m hand steps per 1.0 s
  loop (lead, trail, lead, trail), root X travels 0.5 m (L = +X, R = -X).
* Ledge helpers (same ledge: top z 2.12, face y -0.20): `Ledge_Grab` starts standing (root at the origin, 0.2 m in front of the face), hands land on the top at
  (+-0.21, -0.27, 2.14) at f15 and stay world-fixed; it ends exactly on frame 0 of `Ledge_Hang_Idle_Loop`. `Ledge_Climb_Up` starts on that hang pose and ends standing on the
  top at (0, -0.50, 2.12): root travels 0.5 m forward and 2.12 m up. `Ledge_Drop_Down` starts on the hang pose, ends standing on the floor 0.36 m away from the face (root +0.36 back).
* Mantle_Low: wall box x +-1.0, y -1.6..-0.85, top z 1.0; start = run-ready stance at the origin, 0.85 m in front of the face; end = stand on the top at (0, -1.27, 1.0)
  (root travels 1.27 m forward, 1.0 m up). Mantle_High: wall box x +-1.2, y -1.5..-0.60, top z 1.8, start at the origin (0.6 m from the face), hands land at (+-0.21, -0.67, 1.82),
  end = stand on the top at (0, -0.90, 1.8) (root 0.9 m forward, 1.8 m up).
* Horse: static frame. Saddle top 1.12 m, seat = pelvis 1.205 m, stirrup ball-of-foot at (+-0.37, -0.10, 0.665), hands on the reins just ahead of the pommel
  (y -0.34, z 1.27; half-seat gallop: on the neck, y -0.57, z 1.38). The horse itself (bob, head nod) comes from the horse animation; the rider only absorbs a few cm.

## Notes

* Pole continuity (`trav_lib.solve_continuous`): a 2-bone Blender IK knee / elbow can swing 0.3-0.5 m around the hip-ankle axis in one frame when the authored pole direction moves
  near a folded limb (the old 0.36 m calf snap of `Vault_Low` was this plus a pelvis anchor that released 0.5 m at once), and an almost straight limb has no defined bend plane
  (upper arms rolled 120+ degrees right before a hand released the wall). Since v2.1 the bake pulls a jumping pole toward the previous joint direction and freezes the pole of a
  straight limb. Hand orientations are blended with slerp over stages (`hand_stages`), never by lerping the finger / palm vectors.
* Jump limits used by `scan_motion.py`: 0.12 m / 35 degrees per 30 fps frame for trunk, hips, shoulders, elbows and knees; hands and feet may whip (arm throw of a jump, leg swing over
  an obstacle, leg extension before a landing). The METRICS.txt of `docs/anim/free_library/frames/traversal_v2/` lists every remaining frame over the limit and why.

* Loop clips: frame 0 and the last frame are the same pose (plus the root travel per cycle); every periodic term uses whole cycles.
* Foot/hand contacts are IK targets held constant in world space (no sliding by construction); `bake2` bakes plain FK quaternions, no constraints in the GLB.
* `render_clips_trav.py` differs from `../polish/render_clips.py` only in the props (rungs at 0.3k, wall holds on the limb lines, stirrups, narrower horse barrel,
  saddle top 1.12) and in hiding the wall / ledge / horse head+neck in the front view so the character is visible.
