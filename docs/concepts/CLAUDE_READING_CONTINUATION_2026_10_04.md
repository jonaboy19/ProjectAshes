# Claude documentation continuation — 4 October

This is an incremental reading/source checkpoint. The full project documentation audit remains open; a filename inventory or truncated batch is not evidence of complete reading.

## Additional full reads

- `NPC_PARTIAL_ROUTE_ARRIVAL_HANDOFF.md`
- `NPC_OPTIONAL_INN_ROUTINE_HANDOFF.md`
- `NPC_OFFSCREEN_NEEDS_HANDOFF.md`
- `NPC_MOVEMENT_HEARING_HANDOFF.md`
- `P15_codex_integration_fixes.md`
- `P9_attack_layering.md` across successive sections

Partial reads include the behavior/animation transition design, need continuity, well activity, footstep/activity audio, integration review, combat audit and local status. Remaining sections need explicit follow-up. Earlier reading checkpoints cover additional animation libraries and source contracts.

Additional reads: free-library HANDOFF_CODEX lines 86–133 (martial arts naming and event timing); advanced-tech README first 45 lines requested, partly truncated in combined output. The technical handoff specifically warns that post-modifier bone metrics must be sampled at `Skeleton3D.skeleton_updated`, not ordinary `_process`. Its phone cost column is a multiplier estimate, not phone measurements. Preserve both constraints in future capture work.

## Partial route: stronger source evidence, runtime still unknown

Current `population/street_graph.gd` resets and sets `last_route_partial`. On failed search it constructs the closest reachable settled-node path. On failed endpoint attachment it instead returns the goal directly while flagging partial. These are different failure cases and should not receive an identical retry policy blindly.

Current `population/villager.gd::_plan_route()` consumes the returned path but not its partial flag. `_steer()` marks arrival at the final returned waypoint without checking distance to the requested goal. Thus the source can classify a partial endpoint as arrived. Water separately checks distance to its actual slot before granting recovery, so this observation is not evidence that water need is restored remotely. Other activity presentation consumes `_arrived`; inspect each effect/slot contract before proposing a global fix.

No routing code was changed. Reproduce against an unreachable goal and current settlement before coordinating a correction with the route/LOD owner. Avoid unconditional per-frame retries or position snapping.

## Architecture learned from needs/hearing handoffs

Offscreen needs use bounded arithmetic approximations of schedule windows, not fabricated visits or relationships. Preserve the split between cheap persistent rows and embodied physical action effects. Anonymous sounds are bounded, approximate perception stimuli; they do not prove identity, crime or witness facts. Movement hearing uses the existing decision cadence and settlement footprint checks, with no added per-NPC raycast or node.

The new footstep ownership adapter changes audio playback only. It does not publish new hearing/witness events, and should not be described as a stealth simulation improvement until its noise event contract is reviewed separately.

## Current changes awaiting runtime review

- `7719c0d8`: exhausted action clocks aligned with existing clip rate.
- `bd261dfc`: existing P9 standing attack layers and marker-timed steps.
- `5921f1f5`: one player footstep owner using the existing audio pool.

These commits are local on `gpt/character-feel-finish`; no push or merge is claimed. Their handoffs explicitly retain runtime, visual/audio and phone acceptance gaps. Continue source review and current-Claude comparison before integration.
