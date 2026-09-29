# Free animation clip library (UAL skeleton)

114 clips retargeted onto the Quaternius UAL 65-bone skeleton, all in place (travel on the optional `root` track), 30 fps,
GLB AnimationLibraries in `kingdom/assets/incoming/animations_free/<category>/UAL_Free_*.glb` (load like `Assets._ual_for`
does for `animations/`: instantiate the GLB, take its AnimationPlayer clips, rewrite track paths to the character's skeleton).
Full clip list (length, loop, root travel, source, use): [clip_tables.md](clip_tables.md). Licences: `assets/incoming/animations_free/LICENSES.md`
(CMU mocap: free for commercial use; KayKit: CC0). Categories: martial_arts_unarmed 20, combos 13, kicks 11, defense 9, acrobatics 19, reactions 9, casting 6 + 7 (KayKit), weapons 20.

Pipeline: `tools/anim/make_free_cfgs.py` (clip table) -> `retarget_bvh.py` (mirror, heading normalisation, KayKit glTF source) -> `glb_reduce_anim.py`;
`fetch_free_sources.sh` downloads the BVH takes; `preview_free_library.gd` renders stop-motion frames (`--stopmotion`) for `tools/qa/video_to_sheets.sh`.
Sample sheets: `frames/`.

## Known limits (review notes)
- Hook/uppercut clips are named `Punch_Heavy_*`: side-view review could not confirm the arc, so they are not labelled hook/uppercut.
- Sidesteps, defensive loop, JumpSpin (moved to `MA_Acro_HandSpinKick`), KayKit Spawn clips were rejected.
- Foot/hand dips of 4-7 cm below floor in flips/get-ups (metrics) - use foot IK. `MA_Guard_Boxing_Loop` wobbles slightly.
- Not every clip got a full stop-motion read (kicks, punches, defense, acrobatics, reactions, casting sampled; KayKit weapons and combos not).
- Roundhouse/side/back kicks: use existing `animations/cmu_mocap` Karate clips.

## Hand-off for Codex
Clips are ready; behaviour wiring (state machine, blending, input) is yours. Nothing in `assets.gd` was changed; add the GLBs to `UAL_FILES` when wanted.
