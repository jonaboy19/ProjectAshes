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

## Reading inventory

`CLAUDE_DOCUMENT_READING_INDEX.json` indexes 188 Markdown files currently under `docs`, with line counts and SHA-256 content fingerprints. Authorship is mixed; this is a coverage inventory, not proof Claude authored every entry. Nine explicit full reads from this continuation are marked; other entries remain pending or partial, even if previous conversation may have read sections. Continue by recorded sections and refresh a changed fingerprint before carrying forward its coverage.

New full reads: P10 directional reaction handoff, character reference README, and rig deformation visual handoff. Read SYSTEMS_CLAUDE_HANDOFF first 60 lines in a truncated batch and the integration/memory handoffs in a further truncated batch; no full-read claim is made for those.

## Impact-pause integration remains open

The standing marker-window travel uses the actor action clock. The local impact pause currently freezes mixers without freezing that clock, so body travel/recovery can continue under a frozen pose. This must be addressed before visual acceptance. A fix needs to keep contact dispatch, marker travel, recovery/cancel clocks and feedback on one pause-aware action timeline; changing only recovery or a hit timer would leave inconsistent clocks. Do not treat local source commits as ready for production merge while this remains unreviewed.

The complete source-derived integration contract is now in `COMBAT_ACTION_CLOCK_INTEGRATION.md`. WeaponTrail has an independent process clock shared by its emission window and ribbon ageing; these must be separated if action time is paused. Player's first-person tween is another independent presentation path. The contract records those consumers so a recovery-only patch cannot accidentally be called complete.

## Social, family and economy reading checkpoint

Eleven further handoffs were read without truncation: social graph, temperament, dialogue topic memory, courtship cadence/proposal, LifeCourses kinship/vacancy age, child succession, market fractional carry/purse income, and property tax sale gate. The index now records 20 full reads from this continuation.

The social graph is bounded familiarity from completed nearby chats, not agreement, friendship or witness confidence. Dialogue remembers topic entry, not exact rumor content. Date cadence does not prove travel or time spent together. Preserve those distinctions in animation or dialogue presentation; do not use a gesture or a schedule approximation as proof an encounter occurred.

Source cross-check: current UtilityBrain pairing supplies the current fractional game day to `NpcSocialGraph.affinity`, matching the documented effective decay lookup. Current LifeCourses deserialization explicitly converts parent IDs into an integer array, so a normal JSON number representation alone does not establish a missing-kinship bug. The marriage guard excludes pairs sharing any accepted parent ID, including half siblings despite the handoff's narrower wording. No family or economy code was changed.

Market carry and property gates are already documented implementation slices; their remaining runtime/save checks should be finished through existing owners, not rebuilt as new systems. This reading does not approve those slices in-game.

## 5 October continuation

The reading index now records 31 full handoff reads. Additional completed reads cover observed-event memory, semantic work targets, caravan dispatch, Awakening culture, cull species/den attribution, stale wolf issues, winter ecology and three radiant-quest handoffs. Refresh fetched refs found Claude at `1983bfeb` and main at `31ecc059`.

Source comparison confirmed the historical culture and guild-species gaps still exist on the fetched Claude branch. Focused local fixes and their unchanged reward/identity boundaries are recorded in `LIFE_IDENTITY_INPUT_FIXES_HANDOFF.md` (commit `b5a52409`). Caravan dispatch remains an ownership/design question; reading its handoff is not authorization to invent an automatic funding/cargo policy.

The pause-aware player combat subset is now implemented locally in `906bf7e1`; see the latest source checkpoint in `COMBAT_ACTION_CLOCK_INTEGRATION.md`. It is not a parser/runtime/visual approval. Source review must still check reaction priority, contact frame order, older dodge/landing timers and restoration. In particular, the current take-damage path can replace attack animation with a reaction without always ending the attack action; determine whether light hits should preserve an attack through additive flinch or explicitly interrupt it. Do not silently change poise/balance to hide that ownership mismatch.

Quest and economy handoffs show existing small correctness slices. Reuse those producers and durable IDs rather than infer a completed quest, physical visit or observed event from its animation. The remaining reading and runtime acceptance scope stays open.

## Advanced animation tools reading checkpoint

Completed full reads of the advanced catalogue, runtime-tech README, video-mocap README and authored combat metrics. Their current content fingerprints are refreshed in the reading index. Four more documents have explicit full coverage; the overall reading task remains incomplete.

The runtime-tech document explicitly recommends folding additive flinch into CharacterAnimator's existing tree. Local commit `9652aa1a` implements a rotation-only variant using the existing directional light-reaction clips. The demo used different source clips and a OneShot/identity/Add2 topology; its measured foot offsets and timings do not establish acceptance of this implementation. See `COMBAT_REACTION_OWNERSHIP_HANDOFF.md` for the changed interruption rules and pending checks.

Performance table phone values are PC measurements multiplied by five, not S22 measurements. The catalogue's root-track loader claim still needs checking per loaded library; do not apply it universally. Authored metrics report large slide values for spin finishers and running attacks in their specific full-body/root-motion fixture. They identify review candidates, not confirmed defects in the present blended gameplay or evidence that all clips should be replaced.

Video mocap is an available offline pipeline, but the recorded validation is synthetic only. It has weak wrist/finger recovery, unreliable jumps/spins and flat-ground foot pinning. Reuse existing accepted clips first; new footage needs source-versus-retarget review before gameplay wiring. No new dependency installation or asset generation is needed for the current combat ownership patch.

## Systems and living-world reading

Read SYSTEMS_CLAUDE_HANDOFF and the full LIVING_WORLD design. SYSTEMS_CONTINUATION was read in a truncated initial output followed by its middle 95-line block; do not mark it fully covered until an explicit complete segmented read. Historical delivery sections contradict newer sections within those handoffs, so current source remains authoritative.

Current UtilityBrain and WorldSim source confirms the documented breath continuity gap: active breath affects sitting/winded choices but is excluded from the five saved need columns and offscreen catch-up. The coordinated schema/migration boundary is recorded in `NPC_BREATH_CONTINUITY_SOURCE_REVIEW.md`. No population hotpath was edited. The living-world document is a broad design target, not proof its housing, careers, crime, travel or relationship scenarios currently work.

## Career lifecycle follow-up

Completed SYSTEMS_CONTINUATION with explicit first-95/final-56 reads complementing the earlier middle-95 block. Completed CAREER_BIOGRAPHY_LIFECYCLE_CONTRACT and compared its named methods against current Careers, Biography and Life. The documented integration gaps remain in this local source. A focused Biography change permits an explicitly requested chapter restart after closure while preserving duplicate suppression for open chapters; see `BIOGRAPHY_CLOSED_CHAPTER_REENTRY.md`. Rank retention and automatic resignation/dismissal/rehire reconciliation remain unresolved. No runtime acceptance is claimed.

## Locomotion review reconciliation

Completed CODEX_INTEGRATION_REVIEW and CODEX_LOCOMOTION_JUMP. These are historical snapshots: their unwired-pivot and P9 statements must not be used to undo newer local implementations. Current player source contains both pivot clip selection and clip-time displacement sampling; this establishes source presence, not acceptance on every quality tier or device. The older phone estimates remain unmeasured multipliers.

Current player source search found no named walk-start, run-start, walk-stop, skid or turn-in-place clip wiring. CharacterAnimator registers RunStart as an available air state, which alone does not prove the player chooses it. Those transition integrations remain distinct from the existing stop/pivot work and require matching capsule acceleration, heading and contact phase; simply triggering the clip would not complete them.

Free-library HANDOFF_CODEX output was truncated. Its first 65 lines have now been explicitly read; the central clip-table rows still need segmented coverage. Its initial timer example and player `speed_scale` hitstop recipe are insufficient for the current AnimationTree and pause-aware combat clock. Use the existing local clock contract instead of copying that historical example into gameplay. No new movement or collision code was changed in this reading pass.
