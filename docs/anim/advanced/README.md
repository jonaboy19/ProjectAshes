# Advanced animation: extra clips, runtime techniques, video mocap

Three parts, three owners of files (Codex still owns animation *behaviour*):

| part | where | status |
|---|---|---|
| A. more clips (UAL skeleton, commercial-safe) | `kingdom/assets/incoming/animations_free2/`, this file | 102 clips, see below |
| B. runtime techniques demo (IK, look-at, springs, ragdoll, blend trees, hitstop, warping) + perf | `kingdom/tools_qa/anim_tech/`, `docs/anim/advanced/tech/README.md` | see that README |
| C. own mocap from a phone video | `kingdom/tools/anim/video_mocap/`, `docs/anim/advanced/video_mocap/README.md` | one command `video_to_clip.ps1` (video -> UAL GLB + sheets) with IK foot pinning; tested on synthetic video only |

Preview strips (contact sheets, one row per clip, time in seconds under each frame) are in `docs/anim/advanced/preview/`.

## A. Clip catalogue (all on the Quaternius UAL 65-bone skeleton, prefix `Kay_` or plain names)

Files are GLB AnimationLibraries like `assets/incoming/animations/*`; add them to `Assets.UAL_FILES`
or load with `ResourceLoader.load(path)` and copy the clips (`_Loop` suffix imports as looping).
Per-clip length/loop/travel is in `*.glb.clips.json` next to each GLB.

| library | clips | content |
|---|---:|---|
| `kaykit_life_sim/UAL_Kay_life_sim.glb` | 33 | `Kay_Work_Chop_Tree`, `_Dig`, `_Mine`, `_Hammer`, `_Saw`, `Kay_Lockpick`, `Kay_Work_Bench_A/B/C` (each as one-shot + `_Loop`), `Kay_Hold_Item_A/B/C_Loop`, fishing set (`Cast`, `Idle_Loop`, `Bite`, `Tug`, `Reel_Loop`, `Struggle`, `Catch`), `Kay_Emote_Wave_Loop`, `Kay_Emote_Cheer_Loop`, `Kay_Interact_Reach`, `Kay_Pick_Up_Ground`, `Kay_Use_Item_Kay` |
| `kaykit_combat_reactions/UAL_Kay_combat_reactions.glb` | 15 | `Kay_Hit_React_A/B`, `Kay_Death_Fall_A/B`, block set (`Block_Raise`, `Block_Hold_Loop`, `Block_Impact`, `Block_Counter`), `Kay_Stance_2H_Idle_Loop`, `Kay_Stance_Fists_Idle_Loop`, `Kay_Dodge_Fwd/Back/L/R` (0.4 s, root travel 0.3-0.8 m), `Kay_Attack_2H_Spin_Long` |
| `kaykit_movement_ext/UAL_Kay_movement_ext.glb` | 17 | crouch idle, sneak walk, walk backwards, run strafe L/R, 3 walks, 2 runs, jump start/air/land/short/long, 2 idles |
| `kaykit_ranged/UAL_Kay_ranged.glb` | 14 | bow idle/aim/draw/release (+ "up" variants), pistol aim/shoot/reload, rifle aim/shoot/reload, run holding bow / rifle |
| `kaykit_undead/UAL_Kay_undead.glb` | 9 | skeleton enemy: idle, walk, taunt, long taunt, awaken (standing/floor), collapse (death), resurrect, rise from ground |
| `traversal_authored/UAL_Authored_Traversal.glb` | 13 | `Ladder_Climb_Up/Down_Loop` (0.6 m rise per 1.2 s, root Z = climb), `Wall_Climb_Up_Loop`, `Ledge_Hang_Idle_Loop`, `Ledge_Shimmy_L/R_Loop`, `Vault_Low` (0.9 m obstacle, root Y 2.7 m), horse riding `Ride_Idle/Walk/Trot/Gallop_Loop`, `Ride_Lean_L/R_Loop` |

### Categories covered by the whole project (this wave + `animations/` + `animations_free/`)

sword combat, unarmed and martial arts, spellcasting, hit reactions, deaths, blocks, dodges: see the `animations` and `animations_free` READMEs;
this wave adds KayKit reactions/blocks/dodges/stances, ranged, undead, life-sim work and fishing, emotes, and hand-authored ladder, wall, ledge, vault and horse riding.
Swimming, sitting and lying already exist (UAL `Swim_*`, `Sitting_*`; CMU `Swim_*`, `Lie_Down`); dance: UAL `Dance_Loop`, 100STYLE in `animations_free`.

## Licences and sources (verified at the source, commercial use)

| source | licence | used |
|---|---|---|
| **KayKit Character Animations 1.1** (Kay Lousberg, kaylousberg.com), copy of `License.txt` in `animations_free2/LICENSE_KayKit.txt` | CC0 1.0; text: "free to use in personal, educational and commercial projects" | yes: `Kay_*` libraries. Credit optional, listed in `CREDITS.md` |
| Authored traversal clips | own work made with Blender IK on the CC0 UAL rig (CC0, same as the project) | yes |
| Quaternius UAL 1/2, Cat Prisbrey, CMU, 100STYLE, Mesh2Motion | see `animations/` and `animations_free/LICENSES.md` | (other libraries) |

### Rejected after reading the terms

| source | terms found | verdict |
|---|---|---|
| SFU Motion Capture Database / NUS MOCAP | "free for research purposes. The data cannot be used for commercial products or resale" | rejected |
| MoCap Online free packs (T.C. Sword, sampler; itch.io) | proprietary "Standard License": no redistribution of the files, assets must not be extractable, no AI use | rejected (can't ship extractable clips in a public repo/pck) |
| Truebones free BVH (Gumroad) | free for any use, but "re-distribution ... of Truebones in .FBX, .BVH ... strictly prohibited"; checkout on Gumroad | rejected (repo redistributes derived clips) |
| MocapFlow "Free-Mocap-Library" (GitHub) | repo says CC0 but README badge says CC BY 4.0, downloads sit behind an ad wall, filenames are stock-video ids (AI video-to-motion, provenance unclear) | rejected |
| RancidMilk "Massive Library of Free 3D Character Animations" | it is the CMU dataset repackaged (958 MB); CMU is already covered by `animations_free` | skipped (duplicate) |
| Rokoko free packs, Mixamo | account required | not used |
| LaFAN1, Bandai-Namco, Motorica dance | CC BY-NC(-ND) | rejected |

## Retarget notes

- Tool: `kingdom/tools/anim/retarget_clips_to_ual.py` (direction-matched rest, world-space deltas) via a copy `tools/anim/free2/retarget_free2.py`
  with one change: pelvis height is scaled about the source foot height, and only *above* standing height with body
  height (jumps/leaps), because KayKit is a chibi rig (leg length ratio to UAL is about 2.3, body height ratio 1.2).
- Steps: `kaykit_make_blend.py` merges the 8 KayKit GLBs into one .blend at 30 fps, `make_kaykit_cfgs.py` writes the configs, `build_kaykit.sh` runs Blender and `glb_reduce_anim.py`.
- Loops: KayKit's own loops are used as is (`loop_native`), travel of loops is kept on `root` (mostly 0).
- Known limits: KayKit legs are short and knees are bent in most idles (style, not a bug); arms are long, so hands reach further than a UAL body would. Ground-contact poses (sit on floor/chair, lie, push-ups, sit-ups, crawl) do not fit UAL proportions (feet float) and were dropped; use UAL `Sitting_*`.
  Undead `Awaken_*`, `Resurrect` and `Rise_Ground` are big leaps that leave the frame in the strips: use them only with a ground clamp.
- Authored clips: `tools/anim/free2/author_traversal.py` (Blender IK: world-space hand/foot targets keyed on rungs, ledge, box, stirrups; pelvis and `root` keyed directly, baked to FK, GLB reduced). Rebuild: `blender -b -P author_traversal.py -- <out.glb>`; preview: `tools/anim/free2/render_trav.sh`.
  Quality: readable and loop-clean, but hand-authored: the ladder/wall legs are tucked, the vault is a stylised side vault. Treat as good placeholders for gameplay wiring; replace with mocap from the video pipeline (part C) when the owner films them.
- Preview tools: `tools/anim/free2/preview.sh` (filmstrips through `tools/anim/preview_free_library.gd`), `preview_rm.gd` (filmstrips with root motion and props: ladder, ledge, wall, vault, horse), `preview_src.gd` (source mannequin).

## HANDOFF for Codex (clips)

- Load: `Assets.UAL_FILES` gets the six new GLBs (or add them in `Assets._ual_for`); they follow the same convention as `animations/`: the `root` position track is disabled for in-place play.
- Clip name to gameplay: work/chop/mine/dig/hammer/saw = life-sim jobs (`_Loop` while the job runs, the one-shot for the full cycle), fishing = `Cast` -> `Idle_Loop` -> `Bite` -> `Tug`/`Reel_Loop` -> `Catch`, `Hit_React_A/B` = flinch (stagger), `Death_Fall_A/B` = death (B is the long face-plant), block set = `Block_Raise` -> `Block_Hold_Loop` -> `Block_Impact`, dodge = 4 directional 0.4 s clips.
- Root motion clips: enable the `root` track on a duplicate of the Animation (README of `animations/`, "Root motion"); `Ladder_Climb_*` (vertical, 0.6 m per cycle), `Vault_Low` (2.7 m forward), `Ledge_Shimmy_L/R` (0.5 m per cycle), dodges.
- Ladder/ledge/vault need the character placed at the right spot: ladder rail plane 0.30 m in front of the root, first hand rung at 1.45 m, rungs every 0.3 m; ledge top at 2.12 m above the root, 0.24 m in front; vault obstacle 0.92 m tall starting 0.9 m ahead; horse saddle top about 1.12 m, seat = pelvis 1.20 m above the ground.

For techniques (IK, look-at, springs, ragdoll ...) and their perf table see `docs/anim/advanced/tech/README.md`; for phone-filmed mocap see `docs/anim/advanced/video_mocap/README.md`.
