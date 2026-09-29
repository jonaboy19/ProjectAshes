# Authored traversal clips v2 (ladder, wall, ledge, vault, horse riding)

Hand-authored on the Quaternius UAL skeleton with Blender IK. Output: `kingdom/assets/incoming/animations_free2/traversal_authored/UAL_Authored_Traversal.glb`
(+ `.clips.json`). Replaces the placeholders of `../free2/author_traversal.py` (which is still imported for the rig setup).

## Rebuild

```
BL="C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
"$BL" -b -P author_traversal_v2.py -- <out.glb> [Clip,Clip,...]          # all clips, or a comma list of names (without _Loop)
"C:/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe" ../glb_reduce_anim.py <out.glb> --rot-deg 0.08 --pos-m 0.0005
```

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
| `clips_ride.py` | `Ride_Idle/Walk/Trot/Gallop`, `Ride_Lean_L/R` |
| `render_clips_trav.py` | copy of `../polish/render_clips.py` whose props match this geometry (see below); same CLI |

## Geometry contract (world, metres; character faces -Y, +Z up, +X = character's left; root starts at the origin)

* Vault: box x +-0.9, y -1.4..-0.9, top z 0.92. Root Y travels 2.7 m (monotone). Palms flat on the top at y -1.05 (hand-fixed while planted).
* Ladder: rails x +-0.27, rung plane y = -0.31, rungs every 0.3 m at z = 0.3k (hands on rungs 1.5 and 1.8 m at the start, i.e. the handoff's
  "first hand rung ~1.45 m"), root Z rises 0.6 m per 1.2 s loop (two rungs). Feet: ball of the foot on a rung. Down = the same cycle played backwards with root Z -0.6.
* Wall: face y = -0.36, holds 6 cm deep on four limb lines (hands x +-0.30, feet x +-0.22, one hold per 0.5 m per line), root Z 0.5 m per 1.4 s loop.
* Ledge: top z = 2.12, front face y = -0.20. Hang: hands on top (x +-0.21), pelvis 1.125 m, feet dangle 0.2 m above the floor. Shimmy: four 0.25 m hand steps per 1.0 s
  loop (lead, trail, lead, trail), root X travels 0.5 m (L = +X, R = -X).
* Horse: static frame. Saddle top 1.12 m, seat = pelvis 1.205 m, stirrup ball-of-foot at (+-0.37, -0.10, 0.665), hands on the reins just ahead of the pommel
  (y -0.34, z 1.27; half-seat gallop: on the neck, y -0.57, z 1.38). The horse itself (bob, head nod) comes from the horse animation; the rider only absorbs a few cm.

## Notes

* Loop clips: frame 0 and the last frame are the same pose (plus the root travel per cycle); every periodic term uses whole cycles.
* Foot/hand contacts are IK targets held constant in world space (no sliding by construction); `bake2` bakes plain FK quaternions, no constraints in the GLB.
* `render_clips_trav.py` differs from `../polish/render_clips.py` only in the props (rungs at 0.3k, wall holds on the limb lines, stirrups, narrower horse barrel,
  saddle top 1.12) and in hiding the wall / ledge / horse head+neck in the front view so the character is visible.
