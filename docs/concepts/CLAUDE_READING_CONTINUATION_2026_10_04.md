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

Completed P5 locomotion transition contract. Comparing its nonzero authored start speeds against current zero-speed, speed-dependent player acceleration confirms why exit-rate matching alone is insufficient. `LOCOMOTION_START_REUSE_REVIEW.md` records the required collision, analog-input and interruption boundaries for using these existing clips without forced travel or double movement. This is an integration design review, not a shipped start implementation.

## Horse and crowd contracts

Completed P14b rider-sync, P13 smart-object schedule, P13 population VAT, P6 NPC IK cost and P13 optional life-library handoffs. Source search of current player and population_lod found no RiderSync, VatResidents or CrowdAnimLOD identifiers; player riding still updates its normal animator and uses MountController's rider offset. These handoffs are proposals relative to this local source, not current gameplay acceptance. Re-read the latest Claude implementation before taking any broader riding/LOD ownership.

P6 explains why attaching dormant skeleton modifiers defeated animation throttling in the measured fixture. A rig pool is proposed, not delivered or performance-approved. P13's approximately-zero CPU VAT statement excludes other world simulation, refresh and rendering costs; it must not become an overall crowd budget claim.

The mount transition now reuses `_interrupt_swing()` rather than a partial manual reset. This is a combat-ownership cleanup only, with mount-under-impact-pause/runtime checks still pending in the reaction handoff.

## Enemy and camera follow-up

Completed P11 enemy wind-up, P12 hitstop/FOV, P3 get-up and P4 camera-occluder handoffs. Their patches describe historical states, so they must not be reapplied wholesale. Current ImpactPause, Monster/Wolf countdown and hyper-armour paths reveal an enemy timing risk not covered by the player's shared action clock: enemy winding continues during mixer pause and snap can overwrite the frozen AnimationPlayer rate. See `ENEMY_IMPACT_PAUSE_CLOCK_REVIEW.md`. This is source evidence, not a captured failure or an implemented enemy fix.

## Horse-controller and creature reading

Completed P14a controller and P14c ambient horse/herd contracts, farm animation README and free-library README. Refetched main/Claude heads; published Claude remains `1983bfeb`. Its player still uses `rider_offset`, and its MountController still has walk 1.7, no named TROT_SPEED, and distance-based HOOF_SPACING. The same specific source paths in this worktree agree. Published source therefore does not implement the proposed P14 controller/rider contract; unpublished worker progress is unknown.

P14 swimming and horse-jump proposals are optional behavior changes, not accepted defaults. They require collision-resolved surface/arc ownership and rider synchronization; an animated horse jumping while its capsule stays grounded is not a physical traversal implementation. Preserve the existing deep-water limits until that complete path is coordinated.

Farm README reports retained clip names but changed chicken flap semantics and bone count; callers should use the burst as specified rather than assume a constant wing cycle. Free-library README also identifies rejected and renamed combat takes and weapon clips reviewed without held props. Reuse the surviving named assets and recheck weapon contact rather than select a clip solely from its filename. No animal assets or movement were edited.

## Region 1 ownership and hook coverage

Completed HOOKS_FOR_CLOUD in four explicit 120-line sections after its initial truncated read, and completed OWNER_DECISIONS. Current main.gd instantiates Region1Root; Life snapshot/restore contains the region1 block; modules.json enables Wardlines, Scar Tide, Ember Legacy and Ash Memory; runestone coverage delegates to coverage_override when valid. Thus the hook guide's opening unwired/empty-manifest statements are historical and contradicted by present source. Do not add a second regional root, save block or wear ticker. Source presence does not prove runtime restore or all downstream story hooks.

The decision document assigns retinue/settlement/ascension implementation to Claude cloud and local animation feel work through patches. Keep those implementation boundaries when continuing. Its tax increase is an undecided balance proposal; do not turn it into a silent economy fix. Ashsight camera ownership persists through its return blend, not merely while the replay's active flag is true. Any future player-camera integration must respect that handover. Map-related passages were read for coverage only; map work remains outside the current mission.
