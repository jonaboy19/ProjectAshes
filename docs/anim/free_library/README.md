# Free animation clip library (UAL skeleton)

107 clips retargeted (114 before the round-3 review, 7 rejected) onto the Quaternius UAL 65-bone skeleton, all in place (travel on the optional `root` track), 30 fps,
GLB AnimationLibraries in `kingdom/assets/incoming/animations_free/<category>/UAL_Free_*.glb` (load like `Assets._ual_for`
does for `animations/`: instantiate the GLB, take its AnimationPlayer clips, rewrite track paths to the character's skeleton).
Full clip list (length, loop, root travel, source, use): [clip_tables.md](clip_tables.md). Licences: `assets/incoming/animations_free/LICENSES.md`
(CMU mocap: free for commercial use; KayKit: CC0). Categories: martial_arts_unarmed 19, combos 7, kicks 11, defense 8, acrobatics 20, reactions 9, casting 6 + 6 (KayKit), weapons 21.

Pipeline: `tools/anim/make_free_cfgs.py` (clip table) -> `retarget_bvh.py` (mirror, heading normalisation, KayKit glTF source) -> `glb_reduce_anim.py`;
`fetch_free_sources.sh` downloads the BVH takes; `preview_free_library.gd` renders stop-motion frames (`--stopmotion`) for `tools/qa/video_to_sheets.sh`.
Sample sheets: `frames/`.

## Known limits (review notes, round 3 = stop-motion review of martial arts, combos, weapons; details in [review_results.md](review_results.md))
- Hook / uppercut: the clips formerly named `Punch_Heavy_*` are all **hooks** (front and side stop-motion plus measured fist paths, see review_results.md); renamed `MA_Punch_Hook_*`
  and `MA_Combo_Hook*`. There is no true uppercut in the library.
- Rejected in round 3: `MA_Punch_Cross_R_Body`, combos `BodyHeadHead`, `HeavyStraightHeavy`, `Flurry_5Hit`, `Flurry_Long`, `PunchKick`, `StraightHeavy` (feet-together arm-only flurries, dancer stance,
  no clean end). Rejected earlier: sidesteps, defensive loop, JumpSpin (moved to `MA_Acro_HandSpinKick`), KayKit Spawn clips.
- Trimmed to start/end in guard: both `Cross_*_Head_A/L`, `Cross_R_Head_B`, `JabCross` (+ Southpaw), `StraightStraight`, `HookJab`, `HookHook`, `HookStraight`.
- Boxing takes wind up with the torso yawed up to 90 degrees from the strike direction (back to the camera in a side view); all combos land their hits right after that whip.
- Foot/hand dips of 4-7 cm below floor in flips/get-ups (metrics) - use foot IK. `MA_Guard_Boxing_Loop` wobbles slightly. `Weapon_DW_Chop` lifts both feet 10-15 cm at the strikes.
- KayKit weapon clips were reviewed without a weapon prop (`Weapon_1H_Chop`, `Slice_*` have compressed arcs, attach the sword and check).
- Kicks, defense, acrobatics, reactions, casting were sampled in an earlier round and not re-read in round 3.
- Roundhouse/side/back kicks: use existing `animations/cmu_mocap` Karate clips.
- Round-3 tools: `tools/anim/glb_edit_clips.py` (trim / rename / delete clips in a GLB + sidecar, fix double-counted pelvis travel), `tools/anim/measure_events.gd`
  (hit / release frames and reach from the bone motion), `tools/anim/build_handoff.py` (writes the HANDOFF tables).

## Hand-off for Codex
Clips are ready; behaviour wiring (state machine, blending, input) is yours. Nothing in `assets.gd` was changed. The full handoff (clip -> state, blend times, root motion,
hit / release frames, `ElementFX` pairing, the exact `UAL_FILES` lines and the root-motion caveat) is in [HANDOFF_CODEX.md](HANDOFF_CODEX.md).
