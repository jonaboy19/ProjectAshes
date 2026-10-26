# PC quality continuation — 2026-10-26

The full game-quality goal remains open. This file records evidence and remaining
work for Claude/Codex; passing one gait or one camera does not certify the game.

## Source

Worktree `C:/Users/Jonna/Documents/PA_wt_w3`, branch `claude/anim-aaa`, HEAD
`dd0e43699847c83372741796466fec810fd1440f`, with preserved local changes.
Fresh `git fetch --all --prune` left the relevant branch tips unchanged.
`claude/perf60` (`4c19d337`) is newer by timestamp and divergent. Existing branch,
worktree and handoff comparisons are in `work/quality_continuation_20261026.md`.
Saved Claude work can be continued from source/artifacts; no live Claude session
has been established. No commits or remote publication were performed.

## Implemented and measured

| Change | Current evidence | Limits |
|---|---|---|
| Sheep Walk rebuilt with rigid analytic limb chains and periodic hoof contacts | Production catalog: PASS, 0.60m/s, 1.8cm/s slip, 0 stretch/scale/pops/seam, 0.9cm penetration. Side/front full-cycle GPU frames and controller start/stop/turn recording. Actual production controller rechecked at 480 samples. | Isolated terrain patch, existing low-poly art. Run still fails; slopes and populated gameplay remain open. |
| Preserve other Sheep motions while weighted hooves join the limb chain | Independent 480Hz source/output node comparison: worst error0.491mm. Original mesh, skin and source binary unchanged. Khronos validator: zero errors. | Inherited non-root-skinned-mesh warning and unused-data information remain. Existing motion defects are retained. |
| Terrain3D far-ground coverage follows loaded 384m regions separately from 64m vegetation chunks | Two focused mask checks pass, including equal-count membership replacement. Matched RTX4070 PC High camera captures are being evaluated. | Visual review is camera-specific; no frame-time claim. |
| Recently completed SHOP/PLAY/CHORE station receives a temporary soft revisit penalty | Nine focused cases pass, including variant bags, sole-station fallback, bounded travel, work/water/owned-query stability, interruptions and expiration. | Busy-market visual behavior and long simulations remain open. Memory is transient120sec local brain state. |

Full details and raw artifacts:

- `work/animal_repair_action_20261026/README.md`
- `work/terrain_horizon_fix_20261026.md`
- `work/living_world_revisit_fix_20261026.md`
- `docs/world/HANDOFF_TO_CODEX.md`

## Required work still open

- Repair Sheep Run, Pig Walk/Run and remaining runtime animation failures. The
  earlier1038-clip GPU QA recorded190 failing game-used rows; that library count
  predates the promoted Sheep Walk and is not a fresh whole-library pass.
- Validate blends, turning, uneven ground, interaction contact and combat in
  representative gameplay. Preserve intentionally static holds separately from
  malformed/frozen clips.
- Finish Terrain3D visual A/B and inspect biome edges, water, fog, lighting,
  dressing, landmarks, world edge and dawn/noon/dusk. Fresh Greywood baseline
  exposes repeated faceted far-canopy domes; a replacement using existing tree
  impostors is under investigation.
- Verify living-world population variety, station usage, interruptions, needs,
  travel, social interaction and LOD transitions in actual settlements.
- Collect controlled PC_HIGH town/aerial route p50/p95/p99/max/hitch and memory
  evidence on AC power without another renderer/profiler. Current battery
  discharge and fluctuating RAM headroom invalidate performance certification.
  A zero-lag guarantee has no supporting evidence.
- Triage whole-library validator findings and remaining asset/source coverage.
  The previous5557-path metadata scan covers glTF/GLB data, not every source file
  or every rendered clip. Do not claim every project file was fully reviewed.
- Resolve capture shutdown/resource lifecycle problems. A saved baseline PNG was
  followed by a confirmed hung Godot process; it was stopped by verified PID.
  A scene-drain shutdown change is being checked on the after capture.

## Tools and provenance

Godot4.6.3, RTX4070 Laptop Vulkan Forward+, existing Blender5.2 investigations,
SciPy/NumPy GLB reconstruction and independent comparison, Khronos glTF Validator,
FFmpeg videos and project GdUnit checks supplied evidence. New repeatable tools
live beside the animal artifacts. Existing custom ProjectAshes quality skills
and plugin instructions were used. Rigify was not used in this retained custom
rig repair. No private assets were uploaded to external preview/generation sites.

Quality, visual fidelity and performance remain separate gates. The original
PC-only scope has not been narrowed to these completed changes.
