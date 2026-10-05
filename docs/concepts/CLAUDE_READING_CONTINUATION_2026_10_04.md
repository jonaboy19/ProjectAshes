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

## Cast and emotional staging coverage

Completed CAST_R1 and EMOTION_MAP_R1. Their named relationships, losses and reveal order constrain presentation: Maren is one-armed, Wren is her niece, Bram/Tamsin are siblings, and the first ash watcher remains faceless until the ledger reveal. Generic animation/profile selection must not expose a hidden identity or violate the one-armed contact pose. Thistle's free/keep branch changes its later age and presence; it is not a generic permanently attached pet.

The emotion document lists unique story-animation requests, but current story-director comments explicitly use short in-world staging rather than full cutscenes, consistent with the later cloud status/owner direction. Do not implement the original cinematics as an unsolicited replacement. A targeted animation-sidecar name search found no named Idra/Maren/nuzzle/lantern-hang takes; that search does not prove there is no reusable generic clip or unpublished authored work. Resolve mappings from existing assets before commissioning new ones.

AshGhostClips was read through its initial loader section, not fully. It already copies selected free packs into a small ghost library and aligns action contact to recorded instants. Keep that replay/presentation owner independent of gameplay damage and NPC witness knowledge. No story, ghost, asset or dialogue file was edited in this pass.

## Original pasted notes

Located all four original pasted-text attachments. Completed the 201-line occupation/life-experience note and 231-line character-presentation note. The other two (404 and 445 lines) remain pending explicit segmented reads. Attachment coverage is now separately recorded with content hashes in the reading index; these files are outside the repository docs inventory.

The occupation note calls for multiple concurrent occupations, actual-practice capability and world-backed work opportunities. It proposes an architecture, not delivered code. Preserve the current career/history distinction and generic action commit owner when developing it. No class-choice gate or replacement skill system is implied by this note.

The presentation note distinguishes floor IK from planted-foot locking, and highlights weapon grip, stances, directional locomotion, context hands and event/contact synchronization. Local light-flinch work addresses only the physical-reaction subset. It does not establish weapon-specific grips, finger animation, full directional starts or world-space foot locking. The proposed nearest 5–10 detailed characters are a suggested allocation, not an approved device budget; the later measured modifier/LOD cost handoff constrains it.

## Original notes completed and closed-career promotion

All four original pasted attachments have now been read in explicit sections, including a repeat of the truncated passage on rumours, professions and production chains. Their broad systems plan is reference intent, not proof those features exist. Preserve shared simulation owners, persistent identities across near/far handovers, witnessed knowledge, real work inputs/outputs and state-backed scenario casting. Interaction detail should follow body state, equipment and physical approach rather than teleporting actors into generic poses. No map work was resumed.

Source review found Biography.promote could overwrite the rank and append a promotion highlight to a previously closed chapter of the same role. It now opens a new chapter before recording that explicit promotion, using the existing start_chapter helper. Existing active same-role promotions retain their behavior. This does not wire career resignation/dismissal signals, decide concurrent occupation policy, or automatically promote unemployed characters. No schema or save format changes.

This small fix is source-reviewed only. No tests, game launch, animation capture or phone profiling were performed in this continuation. The remaining document inventory still contains partial and unread files; full project coverage is not claimed. Changes remain in the isolated Codex branch until explicitly integrated.

## Free animation handoff and elemental casting coverage

Completed HANDOFF_CODEX (remaining lines 66–463 in five bounded sections) and polish_casting (full text in two sections). The handoff is chronological: later casting v2 release frames supersede its earlier generic tables. The 18-clip elemental set supplies eight Charge/Release pairs plus AoE Slam and Channel Beam. Its mannequin/Blender measurements and composited effect sheet do not establish in-game outfit quality or phone performance. Traversal entries are authored placeholders with contact geometry requirements; simply playing them does not supply collision-safe traversal.

Current source gap: scripts/world/assets.gd UAL_FILES registers locomotion, original UAL, extra/CMU/Souls and combat packs, but not UAL_Free_CastingElements.glb. TechniqueCaster.cast_technique plays a selected definition clip, then schedules _resolve with an independent SceneTreeTimer(def.hit_time); no casting sidecar lookup appears in that file. This is a source integration gap, not evidence that every currently defined technique has incorrect timing. A follow-up should register only the required pack, select the actual available clip, derive release timing from its current sidecar and rate, and make interruption/pause behavior explicit before changing damage delivery. Avoid copying the handoff's raw timer examples into the existing pause-aware combat path. Do not silently treat elemental aliases (shadow/dark, qi/light, metal/ice) as approved gameplay equivalences.

A targeted search of scripts/autoload found no old MA_Punch_Heavy, MA_Combo_Heavy, Kay_Work_Hammer_Loop or Kay_Death_Fall_A names. This search only covers those patterns and locations. No casting, asset-loader or traversal code was changed; no runtime checks were run.

## Traversal geometry and historical jump design

Completed traversal_v2_HANDOFF and P7_jump, and read the traversal builder README in full. Current player.gd already implements jump buffer/coyote, delayed standing/running launches, variable-height cut, rising/falling states and landing selection. P7's opening claim that jump does not exist is historical. Its original short-hop proposal (45 percent velocity cut) differs from current minimum-age 0.1 s / 60 percent cut; preserve the later touch-tap correction rather than restoring that proposal.

The traversal handoff describes 19 clips and explicit hand/foot contact geometry, not a delivered gameplay traversal controller. A targeted scripts search found no Vault_Low/Mantle_Low/Ledge_Grab references. Ledge climb needs measured ledge height minus actual hang-root height; its 2.12 m rise is specific to the authoring fixture. Do not blindly copy the instruction to disable capsule collision: destination clearance, obstacle-specific handling, collision-safe capsule travel, interruption recovery and restore on every exit are required. Negative scale mirroring likewise needs equipment/handedness and collision review; supplied variants are preferable.

Source risk for later balance review: current _land_jump allows forward input to choose a roll at any fall height above 1.2 m, and skips damage whenever roll is chosen. Thus the 6 m range in the unconditional-roll term is not a global roll limit. This matches the older P7 statement that a roll always cancels damage, so changing it would be a gameplay decision rather than a typo fix. No landing damage change was made. No runtime traversal, fall or device validation was performed.

## Masterplan and world lore coverage

Completed all 135 lines of SYSTEMS_MASTERPLAN, repeating its truncated inventory section, and all 223 lines of WORLD_LORE. The masterplan explicitly labels its original matrix as historical source context. Its October 1 overlay still says Region1Root is absent and the manifest empty; this continuation already inspected the later root/save/module wiring. Do not rebuild those delivered hooks. The roadmap's mobile bands and brain counts are hypotheses; preserve independent animation/physics/perception budgets and one effect/movement owner across handovers. Physical activities need shared eligibility/reservation/commit semantics, conserved work inputs and evidence-backed NPC knowledge.

Lore JSON remains authoritative. Culture art/affinity/greetings constrain future presentation: Caldric rooted spear/shield, Seirune blade/hidden water arts, Ongur mounted bow/sabre, Solenne fire/light healing and greatswords, Urrokai breath/war-cry/grapple, Shenlu sword/fist cultivation, Veyl bow/glaive and beast bonding, Durrow hammer/forge rhythm. These are presentation priorities, not automatic skill locks or permission to map distinct elements together. Actual employment needs vacancies/sign-off; merit is eligibility. Rare soulbeasts, age-gated awakening and sect access should not become generic animation-triggered rewards.

Refetched the two published refs: Claude remains 1983bfeb and main 31ecc059. This confirms published state only; unpublished PC work is not ruled out. No shared checkout, asset, map, combat balance or culture data was changed. Full document coverage and runtime acceptance remain incomplete.

## Performance report and living-world microbench coverage

Completed PERFORMANCE.md (414 lines; repeated the truncated contact-budget section) and both eleven-line living_world benchmark tables. These are historical PC measurements, not new results or phone acceptance. Later entries explicitly retract the earlier RegionDressing 7 ms attribution after split ablations found no built site at the lake and near-noise subtree differences. WorldSim ablation also stops the clock and listeners, so its whole-frame delta overstates the slice's own cost. Do not optimize an old suspected bottleneck without current direct timing.

The report's opening quality matrix is superseded by its later crowd-cap pass and current quality.gd: full/sprites LOW 5/10, MEDIUM 8/22, HIGH 12/32, ULTRA 16/45; rig budgets remain 0/3/6/10. Current villager.gd has a single swept move_and_collide for moving contact overflow, unlike the earlier report's direct-position fallback. Preserve that world/player collision protection when pursuing frame savings. Neither the source path nor old screenshots prove all physical contact routes are accepted.

The isolated living-world tables use the best of three paired 240-frame runs. Negative deferred/total data-VAT deltas show measurement noise, not negative computational cost. They cannot justify hundreds of extra actors or a universal phone per-NPC budget. Sustained real-device percentiles, memory, contact contention and animation quality remain required evidence. No profiler, bench or test was run here; no performance code was changed.

## Living-world animation integration coverage

Completed living_world/HANDOFF and P13_villager_life_clips in bounded sections. Source already installs LifeLibrary, creates LifeProps.Holder and drives accepted SmartObject sessions; do not apply those historical insertion snippets a second time. Targeted source searches did not find LifeAmbience or CrowdAnimLOD integration in villager.gd, which retains its own _anim_lod stepping. The reference LifeActor demonstrates richer ambience/carrying rather than proving those features are delivered in real villagers.

P13 reports manual AnimationPlayer.advance was significantly slower than automatic processing on its specific Godot/MakeHuman probe. This is a warning against assuming manual stepping saves time; it is not a new measurement of current code or phone hardware. Any replacement needs one animation-clock owner, current speed/phase continuity, disabled modifier behavior, restoration on demotion/exit and preserved work-event crossings. Avoid simply deleting LOD or increasing crowds from the demo's 271-person claim. The handoff's phone CPU times multiply PC results by five and cannot establish a complete 60 fps mobile frame budget.

Known clip limits matter for reuse: some social mocap includes physical steps (up to 0.5 m), tool mocap is pantomime, fingers use one curl and mouths are unanimated. Pair metadata does not by itself prevent bodies crossing, reserve interaction space or conserve work outputs. Keep existing shared action/session and movement ownership when adding presentation. No crowd, ambience, prop or animation-clock code was changed in this reading pass.

## Combat audit and source-grip metrics coverage

Completed COMBAT_AUDIT (176 lines in two sections) and library_metrics (72 lines). The audit separates game captures from studio-only authored clips; its numeric scorecard is a historical review, not acceptance of this continuation. Existing local standing-attack/alternating-slot/marker-step and light-flinch changes address parts of P9/P10, but need current in-game captures with the actual outfit. Do not reset those changes to the original patch examples.

Reuse must include the weapon grip and target contract. The audited imported libraries frequently led with the blade flat or failed to reach a target at 1.3 m; a clip's provenance or realistic mocap does not make it suitable for the current sword socket. Auto edge roll does not correct target aim. Bow grip, spear rear-foot slide, finisher spin support and death weapon attachment remain separate presentation concerns. The strike-oriented metrics cannot grade reactions/deaths, and sword flat-ratio metrics do not establish unarmed kick/punch quality. Paired finisher studio distances do not implement safe victim placement or shared interruption ownership.

The audit's phone trail cost is an estimate derived from PC measurements. No current trail benchmark, combat studio capture, player/companion frame review or mobile validation was run. CombatMarkers source was inspected through its timing/window helpers; it centralizes marker rate conversion but does not by itself grant all actions one pause/cancellation clock. No new combat code was changed in this pass.

## Original feel audit and installed addon coverage

Completed FEEL_AUDIT and addons/README, repeating the truncated impostor table. The feel audit's original movement captures are historical: subsequent combat clips, local hit pause, pivots and jump integration supersede parts of its table. Its swim scenario never reached swim depth, so a 4/5 score does not establish swimming acceptance. Talk camera obstruction remained partial; current dialogue_ui source has bust/presentation tweens, which prove UI easing exists but not world-space camera clearance. Do not report talking as passed from those tweens.

The addon note records standalone demos and integration proposals, not universal gameplay wiring. Phantom Camera requires coordination with existing camera owners; Material Footsteps must not create a second player step source after the existing foot-cue ownership fix. Resonate would duplicate Audio, Beehave/statecharts duplicate installed LimboAI, Dialogic duplicates dialogue_manager, and separate Jolt is unnecessary. Reuse existing modules first. Offline fracture tools belong in asset preparation, not mobile runtime generation. No new addon was installed or enabled.

Impostor demo results do not prove current world LOD transitions: its mesh wrapper omits some material features and differs in lighting; alpha-to-coverage relies on MSAA while LOW has no MSAA. These notes remain relevant limitations for Claude's presentation work, not authorization to alter it. No captures, tests, phone benchmarks or gameplay changes were performed in this pass.

## Wolf clip handoff and gait reference correction

Completed P2b_wolf_turn_and_pack_clips and read the full wolf TABLE.txt. Inspected the shipped wolf.glb animation names directly from its JSON chunk: it includes the rebuilt walk/run plus walk_orig/run_orig and the documented turn, circle, stalk, lunge, howl, flinch and limp names. Current controller still selects idle/walk/run and normal attack; having the clips does not implement their behaviors.

Corrected creature_models.gd wolf authored gait reference speeds from 0.85/2.6 to the documented exported-clip measurements 1.07/4.95 m/s. Model scale remains 1.0 because size is baked; impact remains 0.27. This changes playback matching and the existing walk/run selection threshold, not species movement speeds, damage, collision dimensions or attack range. No lunge/pack behavior was copied from the sketch. The generic wolf controller also serves other species, so future wolf-specific roles must check species/clip availability and preserve existing fallback behavior.

The current turning slowdown means actual travel can be below _speed, while gait playback still uses _speed; this separate residual mismatch needs review. Turn/lunge action clocks also need the previously documented impact-pause ownership solution. Source-only change: no game launch, tests, new foot-slip measurement or phone validation. Authored speeds rely on the checked-in measurement record; GLB name inspection is only corroboration of library identity, not independent speed measurement.

## Turning creature gait pace

Followed the confirmed P2b gait mismatch into wolf.gd's current physics path. Movement multiplies _speed by turn_pace but the locomotion role and playback rate previously read _speed. They now use a local gait_speed from the commanded planar step velocity after turning slowdown. When no travel is requested (inside target tolerance), gait_speed is zero, so a residual speed accumulator no longer selects a moving loop. The speed accumulator, acceleration, turn trajectory, collision path, attack and species behavior remain unchanged.

This generic controller serves multiple creatures; all inherit the same movement/animation correction. The retained 0.6–1.9 playback clamp can still mismatch very slow motion, and commanded velocity is not actual displacement after collision. Those are separate remaining limitations, not solved planted-foot contact. No run-turn clips or pause-aware enemy action changes were added. Source diff reviewed only; no runtime capture or tests run.

## Free-library review provenance and trimmed contact timing

Completed review_results.md (109 lines), and read polish_review.md through line 75; the latter remains partial. Review results distinguishes hook punches from true uppercuts, rejects clips without readable recovery, and explicitly notes weapon previews lacked the weapon prop. Its early KayKit weapon OK verdicts therefore do not override the later actual-sword combat audit. Boxing takes need target facing before a large torso wind-up, and multi-hit take names do not reliably describe strike count.

The later polish note changes some clip lengths without changing names. JumpHigh_B loses 0.75 s at the start and Swing_R loses 0.35 s, so older handoff hit markers need corresponding trim offsets; use current sidecar rather than copied tables. It also renames Kay_Crouch_Idle to Kay_Crouch_Walk because it is a stride cycle, not a stationary pose. A targeted search of skills.gd and technique_caster.gd found none of these named kick/boxing/crouch identifiers, so no currently proven caller was altered. Traversal v2.1 supersedes the older vault calf-snap and rung notes in these reviews.

No clips were regenerated, no assets changed and no tests or captures run. Complete polish-review coverage remains pending from line 76 onward.

## Polish review completed: posture and root ownership

Completed polish_review.md through line 270 in three remaining sections. Get-up floor correction and appended idle recovery do not remove crawl-foot slide; fall/get-up pose families are not guaranteed to match. Any reuse must match the actual lying pose, preserve one root/capsule displacement owner and blend from ragdoll pose rather than simply replacing the animation. Acrobatic clips often end turned or in a guard/celebration pose; they need authored yaw/contact handovers and obstacle-safe travel, not generic looping locomotion.

Some prose is misleading without its later table: Somersault_Back is described as a forward ground roll in one row and backward root travel in the handoff; use actual exported root data before wiring. Handspring starts mid-run with pelvis offset by design; it is not a standing evade. HandstandKicks remains partial with large entry/exit foot skate. Do not rerun the non-idempotent acrobatics fix on an already polished GLB.

KayKit gait estimates explicitly allow roughly 20 percent uncertainty. Bent knees in sneak, crouch and landing absorption are intentional; straightening all clips would remove their body mechanics. Ranged props can need 5–10 cm attachment adjustment on UAL proportions, while firearm shoot clips start neutral and cannot automatically chain from aim. No firearm feature was proposed for this world. Older undead travel values (4.65/5.65 m) were reduced to 0.98/1.19 m in this pass; old handoff values must not drive capsule movement. The newer traversal v2.1 handoff supersedes this review's vault calf-snap and partial trot findings. These are reading conclusions, not new visual/runtime acceptance. No assets or gameplay code changed.

## Full horse handoff coverage

Completed horses/HANDOFF.md (223 lines in three sections). The newer Horse_Ride_* set has a distinct saddle-delta and normalized-time contract; it is not interchangeable with earlier Ride_* clips. Current mount_controller still uses distance-based HOOF_SPACING and rider_offset, and player uses that offset, corroborating the previously recorded lack of HorseRig/RiderSync integration. Demo measurements do not establish the real mount path is integrated.

RiderSync must be the sole mounted pose/phase owner when adopted; mount, dismount, horse death and fall-off need explicit full-body handovers and safe ground destinations. RiderIK hands should release for sword/bow actions, with rein ends following released fists. Jump arcs need an actual vertical capsule consumer, not a model-only animation. Keep the existing player combat interruption on mount; do not attach another independent AnimationTree over the existing player tree.

Known measured rider croup penetration reaches 6–10 cm during mount/dismount; mannequin pose matching is not acceptance on the real outfit. Foot IK on slopes and spinning cart wheels remain backlog in the handoff. Its phone performance values are PC estimates multiplied by five. The busy-scene prose compares 1.8 ms estimated phone horse cost with 1.7 ms PC villager cost; the living-world note estimates those villagers at 8–9 ms phone, so the units must be aligned before deciding a frame budget. No horse, rider, camera, cart or asset code was changed; no tests or captures were run.

## NPC transitions, daily rhythm and locomotion phase coverage

Completed NPC_ANIMATION_TRANSITION_DESIGN.md (70 lines), WORLD_DAILY_RHYTHM_DESIGN.md (57), LOCOMOTION_PHASE_AND_FOOT_CONTACT_DESIGN.md (67), and CODEX_SYSTEMS_HANDOFF.md (40).

Daily rhythm is already implemented in scripts/population/daily_rhythm.gd and consumed by villagers, UtilityBrain and PopulationLOD. Stable per-person/day delay, schedule circumstance flags and settlement inn availability already exist. Do not introduce another schedule controller. The old design's fixed 1,500 updates/frame is superseded by WorldSim's BUDGET_US = 500 time budget; the old completion-time claim is not a current phone measurement. Coarse schedule/wage ownership and delayed near-person presentation remain separate and require coherent handovers.

The transition design proposes request, switch-out, switch-in, run, resume and cleanup phases. Implementation should extend existing brain and SmartObject owners: release reservations, tools and speech on interruption; revalidate goal, occupancy and schedule before resuming; invalidate delayed contact effects after cancellation; bound blocked-route recovery. These are design requirements, not evidence that all transitions have been implemented. One body-motion owner must control each handover.

The locomotion note proposes phase matching for compatible walk/run cycles. Current character_animator creates a BlendSpace1D but the targeted source search found no sync_mode assignment. This does not establish a bug or authorize synchronizing idle and every action. Start/stop, pivots, TimeSeek and contact markers require separate phase contracts. Grounded IK should be limited by reach, contact phase and nearby-character budget, with the capsule retaining movement authority; prior expensive villager IK must not be reintroduced wholesale.

The earlier Codex systems handoff explicitly leaves accepted scout offers without ongoing payroll or organization transition. Current Life.answer_offer still contains the recruitment flag and signing bonus path. Treat displayed recurring wages as an integration requirement, not proof they are paid. Preserve existing persistent offer records and expiry handling when a career transition is designed. Dialogue camera focus likewise requires a reliable actor target and camera ownership before introducing a talk shot.

This pass changed documentation and reading coverage only. No gameplay, assets, tests, captures or benchmarks were changed or run. All four documents are recorded as fully read; overall project reading remains incomplete.

## Life-loop and simulation hierarchy reconciled

Completed NPC_LIFE_LOOP_DESIGN.md (173 lines, including a separate reread of the truncated activity/contact section) and docs/design/SIM_HIERARCHY.md (91 lines). The life-loop document contains historical baselines and multiple dated snapshots. Its old Node3D chase, three-phase schedule and fixed 1,500-row claims are not current-source diagnoses. Its reference map also labels older movement patterns; inspect actual controllers before porting any remedy.

Current living_world/smart_objects.gd already provides claim_token, owns_claim, release_claim and Session interruption/cancellation. Token-checked release protects a newer claim from an older session. The life-loop's generic occupancy work is therefore partly implemented: extend that authority rather than introduce a duplicate reservation table. Existing implementations still need evidence for real arrival, animation-contact effects, interrupted tasks, blocked routes and complete job cycles; a class or API alone does not prove those scenarios pass.

SIM_HIERARCHY is an architectural target with stale fixed-row and character-count values. WorldSim currently uses a 500 microsecond budget; realm_hub uses PUMP_BUDGET_USEC = 600. The realm pump executes a complete job before checking elapsed time, deliberately guarantees at least one job, and can expand daily jobs via tick_day_chunks. Consequently 600 microseconds is a cooperative scheduling threshold, not a hard maximum for an indivisible job. Expensive modules must split work to bound individual chunks. catch_up first drains queued jobs synchronously and then calls each module; its O(entities) requirement needs per-module evidence, not inference from the hub. Do not label these numbers measured phone performance.

The hierarchy distinguishes far aggregate settlement simulation from resident WorldSim rows, but its statement that other settlements have no rows must not be treated as proof of exclusive population ownership. Review each producer and identity mapping before adding birth, death, migration or wage effects, to avoid double counting across resident and aggregate representations. Crime-witness fidelity likewise is not proved by a hierarchy bullet; perception cues alone do not establish culprit identity or durable evidence.

No runtime changes, tests, captures or benchmarks were made in this pass. Reading coverage remains incomplete. Next useful reading includes civilization, realm plans and the large settlement/retinue/war contracts, followed by source ownership checks.

## Civilization, realm plan and tower contract coverage

Completed CIVILIZATION.md (89 lines), REALM_PLAN.md (85) and DUNGEON_TOWERS.md (56). Civilization's proposed new modules are already registered in realm_hub MODULES and ORDER, including civilization, migration, governance, notables, news and ecology. Do not implement those packages a second time from the historical proposal. The older region-scale targets (20 static places) are superseded by the realm plan's later 30-settlement/12 km status; its remaining weather, rideable-cart and river backlog needs fresh source review before implementation.

Source catch-up inspection: civilization.catch_up limits integration to at most 12 windows, calls migration.catch_begin/step/end inside those windows, and advances housing/development alongside migration. migration.catch_up has a _driven == days guard that returns its existing digest rather than replaying an already-driven interval; its independent fallback caps at eight windows. Preserve the cooperation and guard when changing hub order or long absence handling. These bounded approximations are not proof of exact day-by-day equivalence or of the 15-year chronicle acceptance scenario. Source registration likewise does not establish physical refugee presentation or resident identity transfers.

Realm modules explicitly extend existing Life systems. Construction sites, career progression, relationship memory and population effects must retain a single owner; proposals for extra wages or migration should first inspect existing transactions. Civilization requires finite resources, tier hysteresis, causal decline and recovery, bounded named specialists/notables and pruned saves. The stated two-year save below 1 MB and per-chunk timings are acceptance targets, not measurements established by this reading.

Progression context matters: REALM_PLAN first says no hard boss gates for open-world progression, then records later natural-dungeon and tower boss direction. DUNGEON_TOWERS explicitly gates higher floors on player OR NPC party clears, distinguishes towers from caves, and limits teleport destinations by cleared/activated state. Do not remove tower gating based only on the earlier broad statement or impose it across the open world. The tower document lists hook additions despite its implemented status; integration must be checked at callers, not assumed from that label. Knowledge-based telegraphs, unique first-clear rewards, abstract allies and non-permadeath tower loss have their own contracts.

This pass recorded existing architecture and design boundaries; no gameplay code, assets, map, tests or runtime captures changed. Remaining large settlement/retinue/war documents still need full reading before cross-system implementation.

## Retinue/settlement/ascension: partial read through line 310

Read RETINUE_SETTLEMENT_ASCENSION.md lines 1–310 completely; the remaining 796 lines are unread and this document is not marked complete in the index. Covered existing-system reuse, authority rules, recruitment types, follower records, wages and loyalty, modes, Call channels/ETA/refusal, rank caps, death/injury, named companions and the beginning of taming.

The proposed scripts/ascension directory is absent in this worktree, and region1/modules.json currently enables only wardlines, scar_tide, ember_legacy and ash_memory. That is evidence the specified asc_* registration is absent here, not evidence all retinue features are absent. realm/followers.gd already has recruit, hire, wages_due, summon, trait-driven agency, loyalty and taming methods; it is registered in the existing realm hub. Preserve and inspect these producers before applying this older package layout or introducing asc_retinue. Current occupation salaries differ from the proposal; changing economy balance is not an incidental integration fix.

realm/callups.gd is an offer/job system (roll_day, raise_offer, accept, complete), not proof of the design's horn/runner/raven/ward-network Call. The relevant existing summon entry is followers.summon. Future Call work must preserve one travel/arrival owner, distinguish notice, preparation and physical travel, and validate darkness/disconnected wards, refusal and interrupted work. Quality follow-body caps must share the total near-character budget rather than be added independently to civilian/companion caps. Never spawn an arriving follower solely from an ETA timer inside visible solid geometry.

The document requires recruits to retain WorldSim identity, family and career history, with career seats released on recruitment. Current follower module also defines its own seeded names and record generator, so a durable resident-to-follower identity adapter needs proof before describing generic hires as the same resident. Preserve identity mappings rather than merging every similarly named person. It also requires permanent death and kin consequences, while existing APIs alone do not prove those event paths are integrated.

Confirmed source time units remain DAY_LENGTH = 720 and DAYS_PER_YEAR = 12. This unusually compressed ageing must remain distinct from 28-day seasons and the document's adult-day progression; do not translate all year/season intervals with a single constant. The design's strict stages, prerequisites and numbers are proposals to reconcile with later player-direction and existing balance, not an instruction to replace current progression wholesale.

No code, assets, tests or captures changed. Next reading resumes at line 311 of RETINUE_SETTLEMENT_ASCENSION.md.

## Retinue/settlement/ascension: partial read through line 620

Continued lines 311–620 completely. Covered taming accessibility, bond/upkeep, beast roles and ward/Scar ties, land-claim legality, building/support/blueprints, roads, production/rations, contentment/tier budgets and the beginning of grudges/raids. The document remains partial; next read starts at line 621.

Current realm/construction.gd already owns holding storage/deposit/withdraw, placement and upgrade costs, grid snapping and terrain/overlap/settlement/site/road/forest/homestead exclusions. Its can_place_here uses current settlement radii and building footprints, rather than this proposal's universal 350/600 m setbacks. Do not overwrite that API with a separate land_claim implementation simply because the old design names one. Legal tenure, permission to fortify, Ward Claim duration and structural support remain distinct requirements whose implementation must be checked individually. No files matching grudge, land_claim or build_renderer were found by the targeted path search; that does not prove equivalent functionality is absent elsewhere.

Construction has pending_gold and take_pending_gold, and Life contains the adapter consumption path. Preserve this transaction boundary and trace exact-once costs, delivery, refunds and resource storage before extending building stages. The proposal's 1 ration/person-day economy differs from realm aggregate and household food accounting; avoid treating those different units as interchangeable or paying/feeding one resident in multiple systems. Careful unit reconciliation is required before copying its winter balance numbers.

Building bodies and follow bodies must fit shared mobile budgets. The document's proposed ascension Region1Sim 2 ms hourly tick, settlement piece rendering/baking costs and follower caps are design limits, not measured runtime values. Packed 16-byte pieces acquire base64/JSON overhead; the cited settlement and total save targets require actual encoded save measurements including roads, inventories and history. The newer civilization document's 1 MB two-year whole-save target differs from this document's 2 MB Region1 rule, so acceptance must use the current agreed scope.

Taming accessibility explicitly requires both wider timing windows and a no-rhythm hold alternative, preserving trust/fear logic. Future implementation must not make precise taps the only route. Wardwalker/Scar-grazer and beast Ember effects need authoritative links to wardlines/scar_tide/ember systems and bounded cadence; adding a second coverage or front-cell simulator would duplicate Region1 ownership. Grudge causality must distinguish observed evidence from world facts before NPCs retaliate; the proposed source_event/Ashsight id is not itself proof a living NPC witnessed the act.

No gameplay, assets, tests, benchmarks or captures changed.
