---
name: ashes-mixamo-meshy
description: Getting animations and models fast for Rising Ashes - Mixamo downloads through the owner's logged-in browser pane, Meshy text-to-motion / text-to-3D with credits, and the ready-made pipelines that turn the results into graded, wired game clips on the UAL skeleton. Use whenever a motion or prop is missing.
---

> **Mandatory for every task (owner rules, 2026-10-28):** (1) `ashes-best-tool-first` — use every fitting Godot built-in, installed addon, external tool (Blender, ffmpeg, Meshy, Mixamo, Poly Haven/ambientCG CC0) and cloud offload instead of hand-rolling; (2) `ashes-aaa-gate` — nothing is done or sent until it passes the AAA gate against `docs/plans/ref_aaa/`. The game is **PC-only** (min-spec: regular PC, possibly integrated GPU); ignore any mobile/phone wording below.

# Mixamo + Meshy

## Order of preference
1. Existing library (golden_set.json gold/probation clips, Quaternius UAL/UAL2, KayKit).
2. **Mixamo** (free, commercial OK, no raw redistribution): owner is logged in in the built-in browser pane.
3. **Meshy** text-to-motion (humanoid only) / text-to-3D — costs credits; owner approved spending Meshy credits (~1000 from 2026-10-28); no other paid tools. Queue: `tools/anim/meshy_queue_2026-10-28.json`.
4. Repair in Blender (`tools/anim/mixamo_to_ual.py` foot-lock, contact IK, loop crossfade; `clip_lift.gd`, `clip_retime.gd`).

## Mixamo download procedure (browser pane)
- Search via URL: `https://www.mixamo.com/#/?page=1&query=<q>&type=Motion%2CMotionPack&limit=96` (typing into the search box doesn't register).
- `find "Description:"` → pick the exact description → `scroll_to` + click the item ref → click the `Download` button ref → dialog: FBX Binary, **Without Skin** (persists per session), 30 fps, keyframe reduction none → click dialog Download (≈ (622,282) in the 800×833 frame; take a screenshot if the frame changed).
- Tick **In Place** (checkbox next to the "In Place" label; Mirror is the other one) for loops; leave root motion for starts/stops/turns/climbs. Not every clip has In Place — treadmill bake handles it.
- Files land in `%USERPROFILE%\Downloads` as `<uuid>.tmp` then rename; move each one immediately with a mover script into `ProjectAshes_art_staging\downloads\mixamo\<set>\<name>.fbx` (verify header `Kaydara FBX Binary`). Raw FBX never goes into the repo.

## Pipelines (already built)
- Mixamo → UAL: `tools/anim/mixamo_to_ual.py` (52-bone map incl. fingers, root strip/keep, foot lock, contact IK, pelvis offset) and `treadmill_ual.py` for gait loops.
- Meshy → UAL: `tools/anim/meshy_pipeline.py all --downloads <dir>` (`--rig meshy_bvh` 78 bones / `--rig meshy` 24 bones) → retarget → library + sidecar → sheets → measure on player + 2 villager bodies → grades; `wire --apply` only after a human review verdict in `reviews.json`.
- Grade gate: `tools/qa/anim_qa/golden_gate.py`; in-game slip: `kingdom/tools_qa/anim_states/loco_slide.gd` (report child AND `--adult`).
- Look at every check sheet before calling a clip gold.
