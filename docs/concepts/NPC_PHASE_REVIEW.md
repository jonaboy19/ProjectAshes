# NPC crowd gait phase review

Open [NPC_PHASE_REVIEW.html](NPC_PHASE_REVIEW.html) in a browser for a frame selector and play control. The four WebP frames are true Blender renders from the project's `UAL1_Standard.glb` animation library.

## Setup

- Top row: four copies of `Walk_Loop` all at phase 0.
- Bottom row: same rig, clip, speed, and cycle length, with phases 0, 8, 16, and 24 frames in a 32-frame cycle.
- Four snapshots show the same global sample time across both rows. Only the lower row receives per-character offsets.
- The source asset's `License.txt` identifies CC0 1.0. The GLB remains the project's existing source asset; the review adds only rendered preview images and HTML.

## Finding

Per-character phase offsets visibly break foot-plant synchrony in this isolated sample. If applied in-game, derive a stable starting phase from the resident's persistent ID and retain it through state blends and LOD transitions. Do not continuously randomize phase, slow the animation to fake a speed match, or reset all actors to frame zero on promotion. Calibrate playback speed independently against actual travel speed and verify in a real village crowd before integration.

## Limits

This does not render the game's villager skeleton or materials, and it does not show locomotion speed matching, retarget quality, foot sliding, navigation, or contact. It demonstrates one crowd-presentation variable only. Use `docs/qa/anim_qa_report.md` and an in-game market/doorway capture for those checks.

## Reproduction

The scene was rendered in Blender 5.2 using the source `Walk_Loop` action. Each lower-row actor has its own copied action with all keyframes shifted by its phase and the cycle modifier retained. Source and intermediate `.blend` are not needed to view the shipped HTML.
