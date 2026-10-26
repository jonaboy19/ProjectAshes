# ProjectAshes whole-library animation and terrain audit — 2026-10-25

## Current source

This pass used the newest usable local checkout found: branch `claude/anim-aaa`, commit `dd0e43699847c83372741796466fec810fd1440f` (three commits ahead of its tracking ref at the time of inspection). The GitHub `main` and other inspected local checkouts are older. The current checkout has extensive pre-existing local changes; preserve them. No production animation asset was replaced in this pass.

## How to check all clips quickly

A fast, scalable first pass is a metadata/accessor sweep plus Khronos glTF validation, followed by focused rendered reviews for game-used clips. Artifacts are under `work/clip_sweep_20261025/`:

- `scan_gltf.py`, `inventory.json`, `clips.csv`: all 5,549 GLB/GLTF paths in `kingdom/assets`; 5,396 byte-unique assets; 6,147 animation entries by path (5,745 in byte-unique files), deduplicated to 3,156 clip signatures. It checked decoded samples, bounds, and finiteness: zero parse/accessor errors, malformed bounds, or non-finite samples.
- 425 heuristic tags on 141 distinct clips are leads only: constant clips and zero-duration entries often are holds/poses; translations/scales vary in units and root conventions. See the README for categories and caveats.
- Khronos `gltf-validator` v2.0.0-dev.3.10 report: 5,549 files processed with no parser failures. The full report does **not** have zero validator errors: 436 files contain severity-0 findings (178,365 total, mostly `ACCESSOR_NON_CLAMPED`); 2,034 `ANIMATION_DUPLICATE_TARGETS` findings occur in `wolf.glb`, `wolf_lod1.glb`, and `human-base-animations.glb`. Ten skin-target warnings occur in `UAL_Free_Reactions.glb`. These are structural/data diagnostics, not proof of a visible defect; triage their affected files before describing the library as validator-clean. Khronos tool: https://github.com/KhronosGroup/glTF-Validator.
- The existing Godot runtime QA sampled 1,038 actor/clip rows, with 440 PASS, 189 WARN, 409 FAIL overall; game-used rows are 297 PASS, 94 WARN, 190 FAIL. It covers only selected labels and actor/clip combinations. It does not visually certify every asset in the library.

This is the quick audit answer: use the static sweep/validator to screen the whole library quickly, then render all game-used clips by rig family and prioritize failures. A single static tool cannot determine deformation, contact, readability, transitions, or gameplay correctness for thousands of clips.

## Highest-priority live animation leads

- Sheep Run: ~145 cm/s planted-foot slip, 131.3% front-foot stretch, 0.57 s airborne, 52 pose pops. Walk stretches a forefoot 63.4%.
- Pig Run: ~105 cm/s slip, 79.2% stretch, 52 pops, 2.4 cm mesh-floor intersection. Walk stretches a forefoot 39.2%.
- Fox Run/Walk, horse family Run, and Dog Run remain listed in `work/clip_sweep_20261025/README.md`.

Scratch sheep/pig retarget experiments are in `work/animation_candidate_20261025/README.md`. Every attempted transformation-only cow-to-sheep/pig edit was rejected: it either preserved or worsened the defect, or removed useful foot travel and worsened floor penetration. Do not promote these candidates. A genuine contact-driven species gait is needed. Sheep and Pig playback rate is not the primary failure.

A read-only Blender study confirmed that UAA Alpaca Gallop (0–16 at 24 fps, ~0.67 s) is structurally retargetable only with a custom anatomical map and leg IK. The 46-bone Alpaca rig has IK/pole helpers and longer torso/neck chains; the live Sheep has 24 bones and no tail/ear chains. Direct bone-name or local-quaternion copying is unsafe. Both packs are CC0. Treat Gallop only as a comparison candidate, not a replacement, until the custom endpoint/IK retarget is rendered and passes contact QA.

## Full-game terrain capture and issues

The GPU run saved all five requested views in `work/terrain_experiment_20261025/fullgame_grass_base/`:

- `ref_gate_market_noon.png`
- `w03_ironmarch_highlands_ground_noon.png`
- `w06_rift_marches_aerial120_noon.png`
- `w06_rift_marches_ground_noon.png`
- `w11_dunhallow_uplands_aerial120_noon.png`

An earlier incomplete-status note was stale: the complete five-image set exists. The capture process exited with code 1 after saving the views, so treat the screenshots as captured while retaining runtime errors in `perf.txt` and logs. Visual review: the market cobbles remain yellow/lime; Ironmarch has conspicuous stippling/dithering on surfaces; Rift aerial reads coherently; Rift ground is dark and sparse; Dunhallow aerial is washed out by distance fog. This is not a visual pass. The terrain change is limited to stabilizing Grass as the material base in the current Terrain3D bridge; it did not resolve those scene-level issues.

Runtime output during capture repeatedly reported `get_global_transform` outside-tree calls from `utility_brain.gd:681` during NPC spawn and `raw_to_base64 ret.is_empty()` during persona/psyche autosave serialization. Both are actionable live-game errors to isolate and repair. Renderer shutdown also logged geometry/light-indexing warnings. The capture had a shutdown exit code of 1; investigate before relying on aggregate aerial performance numbers.

## Next steps

1. Finish the Alpaca-to-sheep feasibility study, then only build a scratch candidate if it retains rigid limb lengths, real foot plants and correct cycle travel; compare focused Godot metrics and full-speed rendered views.
2. Reproduce and fix the NPC outside-tree access and persona/psyche serialization failures; rerun the targeted live-game capture after fixes.
3. Expand visual strips over the remaining loaded runtime clips in rig-family batches, starting with animals and then combat, reactions, traversal, work/social, and creature actions. Log a visual verdict per clip and preserve unclear source-only clips as unverified.
4. Re-capture the terrain views after code/runtime issues are isolated; inspect Ironmarch stippling and Dunhallow fog separately from the Grass-base change.

## Scope and limits

This is broad static coverage of every GLB/GLTF path and focused QA of the current runtime catalog, not visual certification of all 3,156 distinct signatures. Blender/FBX source assets, skinning, materials, runtime blends, collision and gameplay context were outside the static sweep. Static tags and validator diagnostics need rendered/gameplay confirmation.


## 2026-10-25 continuation: runtime defects fixed and rechecked

Fresh work in this checkout fixed several issues exposed by the earlier GPU run:

- `scripts/population/utility_brain.gd`: `sense_threats` now skips an observer or cached hostile unless it is inside the SceneTree before reading global transforms. The captured NPC spawn-time transform error did not recur in the fresh market capture; a focused regression test removes a cached target from the tree between sampling and evaluation.
- `scripts/realm/persona.gd`, `scripts/realm/psyche.gd`, and `scripts/realm/build_kit.gd`: empty packed buffers now serialize as an empty string instead of calling `Marshalls.raw_to_base64` on an empty array. Non-empty formats are unchanged. Regression cases cover empty Persona/Psyche state and an empty build-kit grid; the previous build-kit serialization error is absent from the rerun.
- `scripts/actors/hero_face_driver.gd`: Quality is now read through the SceneTree root because the hero model is dressed before it enters the tree. The market capture previously logged an absolute-path lookup error here; the off-tree setup test passes after the fix.
- `scripts/ui/hud_art.gd`: imported compressed icon images are decompressed before conversion/resizing in both `round_face` and `bake`. These code paths caused repeated startup image errors in the market capture. Two imported-icon GdUnit cases pass after the fix.
- `scripts/world/terrain3d_bridge.gd`: Terrain3D physics processing is disabled immediately after the node enters the tree and resumed once a viewport camera exists and is assigned. This handles the actual startup order in `main.gd`, where the TerrainStreamer exists before Player. A GdUnit case confirms wait/assign/resume; the full GPU scene has not yet been rerun after this exact change.

Verification:

- GdUnit NPC, Persona, Psyche focused run: 50 cases, 0 failures, 0 orphans.
- GdUnit HUD/hero-face run: 11 cases, 0 failures, 0 orphans.
- `test_terrain3d_bridge.gd`: 21 cases, 0 failures, 0 orphans. It also verifies empty build-kit grid serialization.
- Fresh NVIDIA RTX 4070 market view saved to `work/terrain_experiment_20261025/fullgame_grass_base_postfix/ref_gate_market_noon.png`. Capture was intentionally stopped after this one view at ~8 GB process memory with ~2 GB host RAM free. Its log was produced before the HUD/hero/Terrain3D-camera fixes, but after the NPC and Persona/Psyche guards: no `utility_brain`, `get_global_transform`, `Persona`, `Psyche`, or empty-base64 errors appeared. It did show the hero-face absolute path and HUD compressed-image errors that the focused fixes now cover. Screenshot still shows overly yellow cobblestones; the earlier five-view full capture remains the terrain visual evidence.
- The wider terrain GdUnit run emits pre-existing non-failing Region1 resource/signal warnings and a `BuildKit` empty buffer error; the BuildKit error was subsequently fixed and the rerun passed. Remaining non-failing resource/signal warnings are still open.

Files changed for these fixes: `kingdom/scripts/population/utility_brain.gd`, `kingdom/scripts/realm/persona.gd`, `kingdom/scripts/realm/psyche.gd`, `kingdom/scripts/realm/build_kit.gd`, `kingdom/scripts/actors/hero_face_driver.gd`, `kingdom/scripts/ui/hud_art.gd`, `kingdom/scripts/world/terrain3d_bridge.gd`, plus focused GdUnit coverage under `kingdom/tests/`.

Do not treat these targeted improvements as an AAA completion claim. Sheep/Pig gait repairs, remaining visual terrain issues, full UI capture after the image fix, living-world behavior audit, the broader loaded-clip visual review, full-game performance profiling, and post-fix GPU verification remain open. There is no live handle for the previous Claude session to resume; continue from this newest local branch and handoff.

## Post-fix RTX startup capture and cobble A/B (2026-10-25)

Ran the same `ref_gate_market_noon` view on the RTX 4070 at 1280×720, PC profile, High quality, Terrain3D Valencious. The GPU capture reached the shot and saved it in `work/terrain_experiment_20261025/fullgame_cobble_cool_ab/`. Its render sample was avg 25.23 ms / p95 32.08 ms (~40 fps), 885 draw calls, 2,123,152 primitives and 1,058 visible objects. This is a dense single market view, not a route-wide performance result. Startup/scene construction took ~221 seconds before the shot; this and the frame sample show substantial performance work remains even on the RTX 4070.

The capture log no longer contains the previously observed `utility_brain`/global-transform, Persona/Psyche empty-base64, hero-face absolute path, HUD compressed-image, or Terrain3D no-camera errors. Remaining output includes repeated Terrain3D renderer shutdown messages (`indexing did not unpair geometries from light`) and an editor-only API call warning. The bridge camera wait/assign behavior is covered by its 21-case GdUnit pass; the scene has not yet had a full five-view rerun after the camera fix.

I tested `Terrain3DTextureAsset.albedo_color = Color(0.86, 0.92, 1.0)` for the cobble slot. In the market A/B render the paving shifted toward a green/lime cast, so this visual experiment was rejected and removed from production code. The saved A/B screenshot documents the rejected candidate; the source texture and current neutral cobble material remain unchanged. The yellow/golden paving is still an open art issue; the next experiment should alter the cobble albedo itself or rebalance the encoded base/overlay weights, with a same-resolution before/after pair.

## 2026-10-25 source freshness and post-fix Rift capture

- Compared registered ProjectAshes checkouts, staging folders, and remote branch heads. `PA_wt_w3` at `claude/anim-aaa` / `dd0e4369` is still the newest usable animation and Terrain3D source. Its traversal GLB is a dirty local build (617,004 bytes, SHA-256 prefix `0B1EBBA5`); `PA_wt_audit` has an older 616,436-byte build. The main `ProjectAshes` checkout contains 16 distinct older candidate asset/sidecar paths absent from W3; these are being scanned separately before closing the local-assets coverage claim. Preserve W3's dirty files.
- Sheep and Pig runtime GLBs are byte-identical across checked worktrees; no newer species-specific livestock gait was found. A CC0 Alpaca `Gallop` is a scratch retarget lead, not an approved replacement. Existing sheep/pig retargets regress and remain out of production.
- Revalidated the W06 Rift aerial at `(1020, 900)`: worldgen and Terrain3D heights both report 10.82495 m and 32 Terrain3D regions are loaded. The earlier `w06_rift_marches_aerial120_noon.png` in `fullgame_grass_base/` is actually an Ashford screenshot, so its 1 FPS line is invalid. The corrected 960x540 Forward+ / RTX 4070 capture is `work/terrain_experiment_20261025/w06_revalidate/w06_rift_marches_aerial120_noon.png`. It shows the Rift with a saturated pink ground patch and washed aerial haze. Measured 14.48 ms average / 27.14 ms p95 (69 FPS), 389 draws, 626,532 primitives, 450 visible objects. This is one view, not a route pass. Cold scene setup took about 189 seconds before the timed shot.
- The first retry passed a view JSON outside the project's `res://` root to a harness that only accepts `res://`; it emitted zero-view out-of-bounds errors and no image. `kingdom/tools_qa/region1/look_capture.gd` now rejects malformed JSON, missing view names, empty selections, and missing/uncreatable output directories with a clear error and nonzero exit. A headless negative check selected no views and exited with code 2; the corrected GPU capture completed using the absolute JSON path.
- The corrected run used Godot 4.6.3 Forward+ on the RTX 4070 and AA mode 2. It had no script errors during capture; shutdown still emits Godot/Terrain3D `BUG, indexing did not unpair geometries from light` messages. Generated building imports also emit invalid-UID fallback warnings. Both remain open issues.
- No live Claude session/process handle is available to resume. This report and the linked handoffs carry the current state; continue from W3 and preserve its dirty files.
## Additional local animation assets discovered (2026-10-25)

A second checkout (`ProjectAshes` HEAD `fc8f73a79d0e247c7306f4317dc818b72837e727`) contains nine animated GLBs absent from the newest W3 checkout. These are older candidate sources, not newer production assets. They contain 268 embedded animation entries; six sidecars list 186 clips. `Master_Combat_Universe` embeds 179 clips while its sidecar lists 136, so its metadata needs reconciliation before use.

Static scan found no malformed accessors, non-finite samples, count mismatches, or zero-duration clips. Khronos validation reported zero errors; each file has one `NODE_SKINNED_MESH_NON_ROOT` warning, and the master combat file has 17 informational unused-object notices. Visual review candidates include 13 clips longer than 10 seconds (longest: `Bow_Point_Blank_Arrow_Stab`, 83.97 seconds) and four constant clips in `Master_Combat_Universe`: `A_TPose`, `Pistol_Aim_Down`, `Pistol_Aim_Neutral`, and `Pistol_Aim_Up`. These files have not been visually approved or wired into the game. Scanner scratch outputs are under `work/clip_sweep_20261025/candidate16/`; the older source checkout was not modified.

## 2026-10-25 fog A/B capture attempt

A same-camera Forward+ RTX 4070 fog comparison was launched for baseline, reduced fog (`fog_density=0.00125`, volumetric `0.0009`), and reduced non-volumetric fog (`fog_density=0.0010`, volumetric disabled). The baseline reached the correct W06 Rift camera at `t=188s` and confirmed matching world/Terrain3D height plus 32 loaded regions, but the renderer emitted repeated Terrain3D shutdown/indexing errors before any screenshot or performance line was saved. The process became unresponsive at about 4.5 GB RAM and 3.2 GB GPU memory, so it was stopped. No fog variant has a valid visual result; no production fog values were changed. The log and JSON remain at `work/terrain_experiment_20261025/w06_fog_ab/` and `work/terrain_experiment_20261025/views_w06_fog_ab.json`. The next attempt should isolate why this harness sequence triggers renderer teardown before images are written, and should not attribute the incomplete A/B to fog quality.

## Fresh whole-library animation recheck (2026-10-25)

- Re-ran `work/clip_sweep_20261025/scan_gltf.py` against the current W3 asset tree in 114.2 seconds: 5,549 GLB/GLTF paths, 5,396 byte-unique assets, 5,745 animation entries in byte-unique assets, and 3,156 deduplicated clip signatures. No parser/accessor errors, non-finite samples, or malformed accessor bounds were found. The latest authored traversal GLB is included.
- Re-ran the local six-worker Khronos validator batch across all 5,549 paths; it completed in about 42 seconds with zero parse failures. Validator severities must be read from `khronos_validation.json`: 436 files have severity-0 findings, chiefly `ACCESSOR_NON_CLAMPED`, and animation duplicate-target findings are limited to the three paths listed above. The traversal GLB itself has zero severity-0 findings and one warning. The audit’s earlier phrase “zero errors” referred to the custom scanner’s parsing/accessor checks and was inaccurate for Khronos validation; this section supersedes that wording.
- AnimationSight 0.7.2 was checked in the existing local package and accepts BVH only; it cannot directly process this GLB/GLTF library. Khronos Validator is fast for batch structural screening. I did not find an external service that can automatically assess this whole GLB library for motion quality; the tools checked provide structural validation or per-asset preview. For motion quality, continue with the Godot game-loader metrics and rendered strips, then contextual in-game review.

Combined local path coverage for this audit is now 5,558 GLB/GLTF paths and 6,415 embedded clip entries (6,147 from W3 plus 268 in the older candidate-only files). The exact cross-checkout union of unique clip signatures has not been recomputed; do not add the 268 directly to the 3,156 signature count. Game-used visual approval remains narrower than this inventory.

## 2026-10-26 refreshed animation inventory and branch freshness

The scanner and validator were rerun after additional scratch candidates appeared in `kingdom/assets`. Current W3 totals now supersede the Oct 25 figures above:

- Custom scan (`scan_gltf.py`): 5,557 GLB/GLTF paths, 5,404 byte-unique assets, 153 exact duplicates, 489 animated asset paths, 6,230 animation entries including duplicates (5,828 in byte-unique assets), and 3,180 deduplicated clip signatures. It flagged 425 heuristic cases; those are leads, not automatic defects. Runtime-visible coverage remains the separate 1,038-row Godot QA report. The scan took 79.9 seconds and found zero parse/accessor errors, malformed bounds, or non-finite values.
- Khronos Validator 2.0.0-dev.3.10: all 5,557 paths processed in six workers with zero parser failures. It reported 178,367 severity-0 issues across 437 files, 214,000 warnings, 11,398 infos, and 8,484 hints. The largest codes were `ACCESSOR_NON_CLAMPED` (175,444, severity 0) and `ACCESSOR_JOINTS_USED_ZERO_WEIGHT` (211,809, severity 1); `ANIMATION_DUPLICATE_TARGETS` remains 2,034 and needs asset-level interpretation. These diagnostics do not establish visual motion quality.
- Freshness check: current animation checkout is still `claude/anim-aaa` at `dd0e4369`, ahead of its tracking ref. `origin/claude/perf60` has a tip timestamp several minutes later, but it is a divergent older animation snapshot: its AAA packs use colliding names (`Bow_Draw`, `Jump_Land_Soft`, and `Ledge_Shimmy_*`) where W3 has the manifest-reviewed `_Mocap` names; its tree also lacks the AAA clip manifest and deletes `UAL_Life_AAA` despite current `LifeLibrary` wiring for its three reviewed sit clips. Do not treat that performance branch as the newer animation source or copy its asset changes into W3.
- No production animation was changed by this recheck. Sheep/Pig and the other game-used gait failures remain unresolved. The full-library pass is still structural screening, not rendered approval of every clip.

## Alpaca-to-Sheep Run candidate disposition (2026-10-25)

The scratch IK/FK candidate was rejected after Godot 4.6.3 runtime metrics and a GPU side strip. Baseline Sheep Run measures 2.17 m/s, 144.6 cm/s planted-foot slip, 1.3 cm penetration, 0.57 s airborne, 131.32% limb stretch, and 52 pops. Candidate has no usable ground-contact frames and zero cycle travel, 1.0 cm penetration, 0.51 s airborne, 863.96% stretch, six pops, and 2.4° seam. The side strip shows detached/incorrect limbs and extreme deformation. Donor contact detection found only 1–3 samples per foot; semantic mapping and target IK could not overcome the rig/hierarchy mismatch. Candidate and measurements are scratch-only under `work/alpaca_sheep_retarget_20261025/`; no production animal clip changed. Do not promote this bake.

## 2026-10-25 latest animal clip triage

The authoritative source is `docs/qa/anim_qa_results.csv` / `docs/qa/anim_qa_report.md` (Oct 25 18:29; 1,038 rows). Earlier animal-only per-subject reports and strip timestamps are older. QA strips are posed samples and cannot certify live movement.

Priority order from game-used metrics plus strip review:

1. Sheep Run/Walk: 144.5 cm/s p75 slip, 131.32% forefoot stretch, 0.57 s airborne, 52 pops; Walk has 63.44% stretch and 27 pops. Strips visibly show overextended forelegs and snapping.
2. Pig Run/Walk: Run has 105.1 cm/s slip, 79.19% stretch, 0.21 s airborne, 52 pops, 2.4 cm penetration; Walk has 39.24% stretch and 27 pops. Both show low crouch/drag and poor contact. Cow-derived clips are not repaired by playback-rate changes.
3. Horse/grey/draft shared Run: 159.6/154.6/193.3 cm/s slip and 15.44% shoulder stretch; Walk has 96.5–108.6 cm/s slip and 4.1–4.7 cm penetration. Metrics are severe although strips look less clearly broken than sheep/pig; confirm in actual movement before family-wide edits.
4. Dog/Sheepdog: Walk 57–62 cm/s slip; Run 106–112 cm/s, dog Tail1 32.28% stretch; strips show crossing forelimbs and compressed stride.
5. Cow/Ox: Walk 84.9–92 cm/s slip, Run 126.4–135.8 cm/s, ~6% shoulder stretch and 7.9° seam; speed ratios pass, so contact authoring is suspect rather than speed_scale.
6. Goat/deer/stag/donkey/fox: Walk slip 34.4–96.5 cm/s; Run loop seams 17.2–24.5° for goat/deer/stag/donkey/fox, plus fox 62.6 cm/s slip and 3 pops. Prioritize after sheep/pig and representative horse/dog work.

The one-frame Pig diagnostic's initial “bone corruption” conclusion is retracted: its metric was wrong. A clean single-action export removes 15 irrelevant actions and missing-IK-target warnings, but both it and the multi-action export have 0% parent-origin limb stretch on the sampled pose. The full-cycle failure remains unresolved; a scratch diagnosis is checking the exact bad frames/channels. These are diagnostic exports, not approved gaits.
