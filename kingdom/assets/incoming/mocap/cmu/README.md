# CMU bending / martial-arts clips (UAL skeleton)

`clips/UAL_CMU_Bending.glb`: 36 clips retargeted onto the Quaternius UAL 65-bone skeleton with
`tools/anim/retarget_clips_to_ual.py tools/anim/cfg_cmu_bending.json`, keys reduced by `glb_reduce_anim.py` (11.5 MB to 1.9 MB).
Source: CMU Graphics Lab Motion Capture Database, terms in `LICENSE` here. Raw BVHs (39 trials, 63 MB) live in `_raw/`
(gdignored, `*.bvh` git-ignored); re-fetch with `tools/anim/fetch_cmu_bending.sh`.
Previews: `_previews/*.jpg` (side strips, 8 frames per clip; `front_sheet_00.jpg` = front view of six key clips) and `docs/anim/cmu_bending/`.

Wired as library "bending" by `scripts/actors/bending_library.gd` (not in `Assets.UAL_FILES`): installed on demand on the
AnimationPlayer of a caster, played through the existing `play_upper` / `play_full` OneShot slots. Per-clip playback data
(trim window, strike frame, floor lift, blend-out) is `data/powers/bending_clips.json`, built by
`tools/anim/make_bending_sidecar.py`; the clips are played in place (root travel removed at install). Technique to clip
mapping: `anim` lists in `data/powers/*.json` and `data/skills/*.json`; see the handoff. No clip is flagged as loop.

Columns: root travel = `travel_m` stored on the `root` track; slide = mean horizontal speed (m/s) of a planted foot with the root
track enabled (`tools/anim/foot_slide.gd`; about 0.0-0.25 is planted, above 0.5 means airborne or stepping, not sliding).

| clip | s | CMU trial | window (s) | root travel m | foot slide m/s |
|---|---:|---|---|---:|---:|
| `Water_Flow_SunSalute` | 4.7 | 144/144_31 | 0.7-5.4 | 0.05 | 0.00 | 0.02 |
| `Water_Dance_ArmsHigh` | 3.8 | 049/49_09 | 0.4-4.2 | 0.24 | 0.02 | 0.06 |
| `Water_Lean_Sway_A` | 3.6 | 005/05_04 | 4.8-8.4 | 0.97 | 0.98 | 0.20 |
| `Water_SpinReach_L` | 2.4 | 144/144_15 | 4.4-6.8 | 0.04 | 0.03 | 0.18 |
| `Water_Whirl` | 6.0 | 055/55_01 | 0.5-6.5 | 1.5 | 1.48 | 0.55 |
| `Air_Evade_L` | 1.77 | 078/78_18 | 0-1.8 | 4.0 | 4.14 | 0.75 |
| `Air_Evade_R` | 1.47 | 078/78_19 | 0-1.5 | 3.42 | 4.41 | 0.48 |
| `Air_Duck_Weave_L` | 1.1 | 078/78_13 | 0-1.1 | 2.02 | 1.94 | 0.72 |
| `Air_Balance_OneLeg` | 4.0 | 049/49_18 | 0.3-4.3 | 0.07 | 0.02 | 0.05 |
| `Air_SpinJump_360` | 1.4 | 075/75_08 | 1.6-3.0 | 0.41 | 0.40 | 0.18 |
| `Air_Handspring_Evade` | 1.3 | 088/88_04 | 3.3-4.6 | 2.08 | 2.82 | 1.00 |
| `Air_Jump_Twist` | 1.6 | 141/141_06 | 3.6-5.2 | 0.15 | 0.24 | 0.37 |
| `Earth_Lunge_R` | 2.5 | 144/144_17 | 3.2-5.7 | 0.04 | 0.02 | 0.23 |
| `Earth_Lunge_L` | 2.5 | 144/144_11 | 2.9-5.4 | 0.02 | 0.04 | 0.23 |
| `Earth_PunchSeq_L` | 5.0 | 144/144_13 | 1.5-6.5 | 0.05 | 0.15 | 0.20 |
| `Earth_PunchSeq_Deep` | 1.6 | 144/144_20 | 3-4.6 | 0.0 | 0.01 | 0.17 |
| `Earth_Crouch_Reach_R` | 1.8 | 144/144_24 | 15.9-17.7 | 0.16 | 0.02 | 0.10 |
| `Fire_Box_Combo_A` | 4.4 | 013/13_17 | 4.6-9 | 0.14 | 0.14 | 0.60 |
| `Fire_Box_Combo_B` | 1.4 | 014/14_02 | 20.6-22.0 | 0.54 | 0.40 | 0.36 |
| `Fire_Box_Combo_C` | 4.4 | 017/17_10 | 3.8-8.2 | 0.97 | 1.05 | 0.32 |
| `Fire_Punch_Kick` | 4.3 | 141/141_14 | 0.5-4.8 | 0.51 | 0.78 | 0.42 |
| `Fire_Aerial_Flip` | 1.9 | 088/88_06 | 0-1.9 | 1.8 | 1.90 | 0.79 |
| `Lightning_Point_Snap` | 2.9 | 013/13_26 | 6.1-9.0 | 0.33 | 0.24 | 0.22 |
| `Lightning_Punch_Snap` | 1.2 | 143/143_23 | 5.4-6.6 | 0.02 | 0.03 | 0.08 |
| `Guard_Ready_Defensive` | 3.17 | 076/76_04 | 0.3-3.5 | 0.36 | 0.16 | 0.10 |
| `Fire_Box_Jab_Hook_B` | 2.7 | 013/13_17 | 13.7-16.4 | 0.32 | 0.28 | 0.41 |
| `Fire_Box_Straight_C` | 3.0 | 013/13_17 | 16.4-19.4 | 0.39 | 0.62 | 0.45 |
| `Fire_Box_Hooks_D` | 2.2 | 014/14_02 | 5.3-7.5 | 0.32 | 0.46 | 0.35 |
| `Fire_Box_Flurry_E` | 1.9 | 014/14_02 | 7.5-9.4 | 0.21 | 0.35 | 0.45 |
| `Fire_Stride_Strike_F` | 3.4 | 017/17_10 | 11.0-14.4 | 1.04 | 0.79 | 0.37 |
| `Earth_Crouch_Reach_L` | 2.8 | 144/144_22 | 17.8-20.6 | 0.09 | 0.06 | 0.11 |
| `Earth_Spin_Reach_R` | 3.9 | 144/144_28 | 1.1-5.0 | 0.09 | 0.11 | 0.17 |
| `Earth_Punch_Hold_Deep` | 6.7 | 144/144_13 | 5-11.7 | 0.08 | 0.05 | 0.18 |
| `Cultivate_Yoga_Floor_Flow` | 7.2 | 144/144_31 | 7.9-15.1 | 0.4 | 1.01 | 0.07 |
| `Water_Lean_Sway_B` | 3.5 | 049/49_12 | 1.9-5.4 | 0.07 | 0.04 | 0.06 |
| `Air_Jump_Kick` | 2.43 | 090/90_07 | 5.0-7.5 | 2.19 | 2.39 | 0.14 |

## Known issues (fixed at playback by BendingLibrary.prepare, the GLB is unchanged)
- Floor penetration flagged by `preview_free_library.gd --metrics` (lowest joint 5-7 cm below the floor): `Fire_Box_Combo_A`, `Fire_Stride_Strike_F`, `Water_Whirl`. FIXED: per-clip pelvis lift curve while a bone is under the floor (`lift` in the sidecar; `tools/anim/bending_measure.gd --prepared` shows the result, all clips within 2 cm).
- `Air_Evade_L/R` travel 4 m: they are basketball evasive runs (Subject 78 "WalkEvasive"), FIXED: the root travel track is removed at install, the clips play in place; dash movement belongs to the caster.
- `Air_Handspring_Evade` and `Fire_Aerial_Flip` are acrobatic flips (airborne; slide values are meaningless).
- `Earth_Punch_Hold_Deep` ends in a crouch (the source performer drops at the end); FIXED: played as 0-4.6 s with the last 0.7 s easing back to the first pose.
- `Lightning_*` are placeholders from a traffic-pointing and a punching take; a sharp snap-to-point set should be keyed by hand.
- Hands are constant finger poses (fist for strikes, relaxed otherwise); mocap has no fingers.
- Source performers are mixed (CMU subjects 05, 13, 14, 17, 49, 55, 75, 78, 88, 90, 141, 143, 144), so strides and posture differ between clips; the retarget scales by leg length only.
