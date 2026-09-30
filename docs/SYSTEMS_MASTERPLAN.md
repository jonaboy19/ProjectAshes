# Systems masterplan: a coherent mobile living world

Current implementation status is recorded in [SYSTEMS_CONTINUATION.md](SYSTEMS_CONTINUATION.md), **Latest continuation checkpoint**. The matrix and delivery order below began as a source audit against `origin/main` at `4e03e000`; they are historical roadmap context, not current status. Use the overlay below and re-read the source before taking a task.

Audit baseline: `origin/main` 4e03e000d2e68e32fea7bb0625d373e72bbbfe0d, 29 September 2026. This document is a proposed sequence, not proof of implemented features. The source is authoritative when older design progress lists disagree. Scope: systems and world building; Claude owns current models, environment and presentation work.

## Direction from the supplied material

The four supplied notes describe lives formed through actions, careers without class selection, natural contextual interactions, and scenarios caused by persistent world state. They also identify weapon/camera/animation presentation defects. Preserve their systems direction; reserve presentation changes for Claude. The latest user instruction expressly permits isolated additive systems integration while requiring existing functionality and other workers' ownership to be preserved.

A character starts as a person. Occupation does not gate capability. Apprenticeships are opportunities with people, travel and obligations. Shared activities connect professions. NPCs resolve matters without the player. Animations express simulation state. Scenario casting requires real entities and prerequisites; random timers alone do not establish believable causality.

## Current source overlay — 30 September 2026

This overlay reflects the current source-reviewed state of Codex branch `gpt/living-world-integration`, merged with Claude remote head `1d5b8d2e`. Review is in [draft PR #5](https://github.com/jonaboy19/ProjectAshes/pull/5). Claude's life clip library and VAT crowd path remain visual/presentation work. Codex has integrated a near-ring-only SmartObjects destination lookup into WorldSim schedule changes; embodied Villager session use remains unconnected. Claude's local checkout may contain unpublished work. The earlier inventory and implementation order are historical context, not an instruction to rebuild delivered systems.

- **Persistent facts and actions:** `world_event_log.gd` is bounded, queryable and included in Life save/restore; real Life-action and craft producers publish facts. `action_runtime.gd` provides bounded atomic multi-resource leases and idempotent commits. The journal is not a rumor bus, and publishing a fact does not give it to every NPC.
- **Crafting station identity:** `station_identity.gd`, `crafting.gd` and `Life` use semantic station references plus live registration generations. Crafting reserves the player and exact station channel together and revalidates the same station at commit. This does not make NPCs walk to stations.
- **Population continuity:** embodied position has an instance-tokened `WorldSim` owner handoff; five utility needs persist across LOD and save/load, with bounded catch-up. A time skip preserves an embodied actor's resolved position while updating its destination. Eight actors use the multi-slide path; other moving villagers inside contact range use a single swept world/player collision query.
- **Near perception and social memory:** shared sight requests are FIFO and bounded, with four raycasts per 500 ms and short anonymous last-seen danger memory. Conspicuous resolved combat techniques add short-lived, bounded spectacle stimuli; these encourage looking but are not line-of-sight evidence or culprit identification. Relationships have bounded conversation-topic memory attached to actual dialogue-node presentation. Hearing, durable witnessed-crime evidence, and NPC-to-NPC rumor propagation remain absent.
- **NPC-to-NPC ties:** `npc_social_graph.gd` now stores bounded familiarity from completed close-range villager conversations; it is separate from player-facing opinions. Current keys wrap the fixed-seed WorldSim person index, so identity migration remains required before generator changes. The ties do not yet influence partner choice, dialogue, rumor or offscreen life simulation.
- **Live activity:** villagers now use the shared action lease authority for a narrow water-fetch activity with two approach slots (or abstract plaza-break points when a generated settlement has no well). Existing movement/collision remains authoritative. Thirst recovery and the existing animation candidates require arrival, stop, facing and a working lease. This is pushed but not validated in Godot or on a phone; see [NPC_WELL_ACTIVITY_HANDOFF.md](concepts/NPC_WELL_ACTIVITY_HANDOFF.md).
- **Still absent or unintegrated:** embodied NPC station approaches and interactions, shared work orders/opportunities, evidence-backed crime and law, hearing/search, significant event memories and uncertain rumor propagation, social-tie effects on partner choice/dialogue/offscreen simulation, scenario casting, and fully conserved physical production/cargo. `Region1State` now has a Life snapshot/restore hook on the Codex branch, but `Main` does not instantiate `Region1Root`, the manifest is empty, and `region_event_bridge.gd` is not wired into live gameplay. WorldSim's new schedule lookup changes near-ring data targets only; it does not claim a physical arrival or animation.
- **Claude-owned queued work:** survival construction and cause-driven/rarer wars with player influence are described in `docs/design/REALM_PLAN.md`. This branch does not implement or take ownership of those concurrent features.

No full-game parser/runtime, visual acceptance, behavioral, save/load, or mobile-performance result is claimed by this overlay. Static checks recorded in the continuation document apply only to the specific files and commits named there.

## Evidence-based inventory

| Area | Status | Existing source and evidence | Gap / next extension |
|---|---|---|---|
| Population | PARTIAL | `kingdom/autoload/world_sim.gd`: packed home/job/position/money/health columns, sliced update, deterministic schedule and settlement ranges; embodied position ownership and five saved utility needs are integrated | Distinct persistent identity domains still need a shared mapping; most residents are not complete persistent life records |
| Nearby AI | PARTIAL | `scripts/population/utility_brain.gd`: needs, personality, utility commitment, FIFO bounded sight requests, anonymous last-seen danger, social pairs and contextual goals | Hearing, identification confidence, durable significant memories and wider intent remain; do not replace this brain |
| Embodiment | IMPLEMENTED | `scripts/population/population_lod.gd`: full/sprite ranges, budgets, write-back ownership, contact hold, time-skip handling; `Villager` uses multi-slide for 8 selected actors and a swept single-contact fallback for moving overflow actors in contact range | Rendering, collision-query and cognition budgets need separate measurement; do not treat distance as the only promotion criterion |
| Childhood | IMPLEMENTED | `scripts/sim/life_path.gd`, `childhood_events.gd`, `tendencies.gd`, `awakening.gd` | Activities/opportunities should feed existing lived experience rather than introduce class choices |
| Careers | PARTIAL | `careers.gd`, `career_ladders.gd`, `mastery.gd`, `biography.gd`, `radiant_quests.gd` | Shared work/activity primitives and multiple occupations; preserve vacancies and actual-practice progression |
| Notable lives | IMPLEMENTED | `life_courses.gd`: named people, families, yearly career/marriage/death progression, capped news | Not the same database as WorldSim; promote continuity through a mapping rather than conflating integer IDs |
| Social | PARTIAL | `relationships.gd`: player-facing opinions/factions/gifts plus bounded conversation-topic memory recorded from dialogue presentation | Sparse NPC-to-NPC links, evidence-aware and uncertain rumors, and their consequences |
| Economy | PARTIAL | `economy.gd`, `market.gd`, `caravans.gd`: hourly production/consumption/modifiers, trade, contracts and abstract transport | Physical transport must share one cargo/entity record; deeper production must conserve goods and money |
| Property/state | PARTIAL | `property.gd`, `nobility.gd`, `lordship.gd`, `homestead.gd` | Construction labour/material/time and settlement migration reasons should connect through existing owners |
| World causes | PARTIAL | `runestone_network.gd`, `monster_ecology.gd`, `threat_map.gd`, `seasons.gd`, `war_sim.gd` | Causal event records and scenario consequences; road_events.gd still uses a slow proximity/random ambush check |
| Skills/power | PARTIAL | `skills.gd`, `soul.gd`, `skill_evolution.gd`, `magicules.gd`, `echoes.gd` | Shared ability/effect interfaces around existing systems, not a second progression model |
| Persistence | IMPLEMENTED | `save_manager.gd`: atomic writes, backups, checksums, migration and autosave; `Life.snapshot/restore` owns module state | Extend the existing snapshot with optional versioned fields; missing legacy fields must reset new state |
| Integration | PARTIAL | `autoload/life.gd` plus bounded event log, atomic action leases, semantic station identities, exact craft reservation/commit, and the narrow live water activity | Region event bridge is not wired to gameplay; no generic NPC activity/work-order adapter or broad consequence routing |


Status means source coverage of the stated feature, not a runtime quality guarantee. IMPLEMENTED means a concrete execution path exists; PARTIAL means a useful base exists but the requested richer model does not; MISSING means no shared implementation was located in the audited scripts; NEEDS INTEGRATION means existing pieces need cross-system wiring.

| Requested system | Status | Concrete source evidence | Remaining scope |
|---|---|---|---|
| Equipment | PARTIAL | `kingdom/scripts/sim/equipment.gd` equip/unequip, inventory transfer, stats, durability, timed buffs, serialization; player reads its stats | Physical visual/grip/stance metadata belongs to Claude; retain statistical mechanics |
| Combat | PARTIAL | `kingdom/scripts/actors/player.gd` buffered combo, `_parry`, block/stamina, dodge, `_resolve_hit`, damage/death | Event-driven weapon traces, regional armour/poise and bounded tactical decisions are further work |
| Traversal | PARTIAL | player `_update_swim_state`, swimming stamina, `toggle_mount`/mounted physics, crouch and ground handling | No mantle/vault implementation found in player traversal audit; add only after shared action contract |
| Weather | IMPLEMENTED | `kingdom/scripts/world/weather.gd` scheduled states, transitions, rain/snow, quality-aware particles, noise/fire multipliers, lightning/audio; utility brain consumes raining state | Wider hearing/stealth/crop consequences NEED INTEGRATION; multipliers alone do not prove all consumers |
| Dialogue | PARTIAL | `kingdom/scripts/sim/dialogue_runner.gd` data-driven runner; Life and TalkTarget expose dialogue/menu integration | Context barks, believable world-space interruption and belief-aware reports remain |
| Interaction/SmartObjects | PARTIAL | `ActionRuntime` supports atomic transient resource leases; crafting uses semantic station references/generations; WorldSim resolves near-ring schedule targets against transient SmartObject slots, field rows and exact market stall placements; Villager has one leased water activity | General embodied SmartObject sessions, shared eligibility/work orders and production activity effects are absent; route arrival, contact alignment and activity animation remain separate |
| Work opportunities/knowledge | PARTIAL | Careers supplies real vacancies; mastery/biography/childhood/radiant exist | Shared Activity/WorkOrder, apprenticeship obligations and knowledge/qualification model |
| Crime/law | MISSING | No unified witness/jurisdiction/offence/report model located | Ownership, identification confidence, guard knowledge and persistent punishment |
| Stealth/perception/memory | PARTIAL | player `noise_radius`, crouch; weather noise hook; utility cached hazard and spectacle sensing | Sight/hearing evidence, suspicion/search, significant bounded memory |
| Rumours/social graph | PARTIAL | economy price rumours, life_courses capped news, relationship opinion/faction modifiers | Sparse NPC edges and geographically propagated uncertain claims |
| Emergent scenarios/personal stories | PARTIAL | Childhood event pool, road ambushes, life_courses yearly biographies and world issues exist | State-cast ScenarioDefinition/Instance and persistent personal matters, bounded causal chains |
| War/military | PARTIAL | `war_sim.gd` war declarations, fronts, daily outcomes/raids/treaties; `military.gd` rank data | Logistics, prisoners, wounded, replacement continuity and concrete deed ledger |
| Animals/Soulbeasts | PARTIAL | Wolf/monster AI and ecology; naming and subordinate systems | Shared persistent creature lifecycle/trust/training and Soulbeast extension |
| Ability/status | PARTIAL | `technique_caster.gd` cast/cost/effect execution; soul and evolution; injuries/equipment buffs | Unified modifier semantics across statuses, cancel rules and contextual mastery |
| Settlement/transport | PARTIAL | lordship projects/issues, property holdings, economy abstract caravans, roadside presentation | One physical/abstract cargo identity; cause-based migration/construction continuity |
| Player presentation | PARTIAL / CLAUDE OWNED | Existing animator/procedural rig and player animation calls | Supplied weapon/IK/camera proposals reserved for Claude; no presentation edits in this slice |
Paths in the table omit the common `kingdom/` prefix where unambiguous. Presence of a file proves implementation exists, not gameplay completeness or device performance.

## Historical delivery order and ownership

### 1. Persistent event spine, wired to real actions

Add a bounded pure-data event history and integrate actual successful Life.record and crafting producers. Preserve every current signal consumer and effect calculation. Query by cursor/type for later AI and debug tooling. Save/restore this history through Life. This first slice records facts; it does not yet implement witness perception, rumours, jobs or consequences.

The journal schema carries a version; records carry monotonic ID, type, namespaced actor/target references, game time, payload and optional cause. Facts and beliefs are separate: an event being logged does not mean every NPC knows it. Payloads are explicitly selected JSON-compatible values, no Nodes/Resources/Callable references. Bounded history may expire; delayed consumers must detect an expired cursor rather than silently invent continuity. Essential permanent achievements belong in the owning biography/ledger, not solely this rolling journal.

### 2. Shared contextual actions and reservations

New ActionDefinition/ActionInstance runtime: eligibility -> reserve -> approach -> prepare -> perform -> finish, with graceful cancel and explicit commit boundary. Shared player/NPC API; nearby presentation adapters execute movement and contact, distant execution uses validated abstract effects. Object-slot reservation tokens include owner, generation and lease; expired tokens cannot release a new owner's slot. Recheck prerequisites at commit. Effects use existing inventory/economy/needs services. Never reward twice after marker retries, time skip, reload or cancellation.

First vertical slice: a well drink action with a real slot, approach/facing constraints, water state and actual need change; or an existing crafting station activity with real inventory input/output. Choose the slice with Claude after auditing current wiring. Do not pretend menu availability is a physical action implementation. Claude owns animation/IK/socket adapters; systems own eligibility, phases, effects and persistence.

### 3. Perception, memory and social evidence

Add budgeted sensor requests around existing utility context. Nearby perception uses actual visibility/hearing checks, last-known position and identification confidence. Reserve rays for important candidates using settlement/spatial filtering. Update cognition at staggered intervals; event urgency can interrupt routine work. Significant memory stores event reference, subject, interpretation, confidence, emotional weight and expiry. NPC relationships are sparse edges with bounded degree plus protected family/employer links. Anonymous reports do not grant exact offender identity. Conversations propagate beliefs, not omniscient facts.

### 4. Activities, work orders and opportunities

Activity definitions declare duration, tools, input/output, location, needs, mastery discipline, interruption and event output. Work orders reserve materials and capacity, track partial progress, deadlines, compensation and ownership. Reuse crafting/economy/radiant/career rules. Opportunities cast real masters/employers/vacancies with age/access/travel prerequisites. Apprentices may quit; knowledge, qualifications and reputation persist. Farming, smithing, healing, inns, hunting, mining, fishing and scholarship become combinations of shared primitives.

### 5. Law, stealth and rumour consequences

Create local law definitions and ownership-aware offences. Witness evidence becomes reports; authority response depends on jurisdiction, confidence, severity and existing social state. Stealth combines noise, light, motion and concealment without all-NPC-per-frame rays. Rumours carry source, claim, confidence and propagation limits. Guards act on received knowledge. Connect fines/confiscation to actual inventory/money and detention to navigable world state. No automatic universal bounty for an unseen act.

### 6. State-cast scenarios and personal matters

Authored definitions declare real participant roles, locations, prerequisites, exclusivity, responses and consequences. Bounded indexed casting discovers overdue debt, shortages, injury, rivalry, vacancy or threatened roads; avoid scanning every person pair. Personal matters contain responsibility, unresolved issue, goal and obligation. Deduplicate scenarios by cause/participants; prevent causal loops with depth/rate limits. NPCs can resolve scenarios offscreen. Do not automatically create quests: the player may observe, ignore or encounter aftermath.

### 7. Deep world coupling

Economy: conserved production chains, shortages, transport delays and actual purchases. Settlements: housing/jobs/food/security/tax-driven migration and businesses. War: supply, morale, wounded, replacements, prisoners and deed-based merit. Ecology: persistent animals, territory, needs and trust; Soulbeasts extend this record. Abilities: data definitions around existing techniques/soul growth. Effects: a shared modifier evaluation pipeline around injuries, equipment and elemental states. Each remains one coherent subsystem with narrow adapters and its own migration/verification.

## Mobile budget contract

The suggested 0–25 / 25–80 / 80–300 metre bands and 20–40 expensive brains are hypotheses, not measurements or guaranteed phone limits. Existing source budgets differ: FULL_RANGE 45 m, MAX_FULL 24, MAX_PHYSICS_CONTACT 8; quality settings narrow limits further. Keep them until measured changes justify promotion.

Maintain independent render, animation, physics, sensor, cognition and strategic tiers. Important contact/combat/story actors receive priority; hysteresis and leases prevent tier chatter. Only one movement owner and one action effect owner exist across handoff. Store distant lives as data; avoid an idle Node per resident. Scheduler provides deterministic ordering, staggered work, bounded queue/candidate counts, cancellation and overflow counters. Clock jumps process strategic elapsed-time effects without issuing thousands of catch-up visual actions.

Profile representative low-tier devices with warm sustained runs, not desktop FPS alone. Capture p50/p95/worst frame, allocations, sensors/path queries, body count, action/event backlog and dropped/coalesced work. Set numerical ceilings from evidence. A 10,000-person data simulation is an architectural aim, not currently verified performance.

## Acceptance gates

Each delivered slice must prove current producer integration, correct effects, cancellation, identity references, versioned save/load, old-save defaults and deterministic replay boundaries. The supplied roadmap proposes unit/headless/integration/soak/performance/mobile tests; runtime/device gates remain unverified. Schedule checks for each accepted implementation slice and record what was actually run. Avoid declaring a whole subsystem complete from syntax checks alone.

Key routes: two NPCs compete for one slot; threat interrupts work; save during action then reload; skip a day; unload/reload settlement; near/far promotion during an action; witness loses sight; event cursor expires; malformed state is rejected; craft fails with no materials; one successful action grants mastery once. Long runs must show bounded memory and queue growth. Visual/runtime capture remains necessary for physical naturalism and Claude owns that presentation verification.

## Reuse policy

Evaluate external code for current engine support, licence, maintenance, integration cost and tests. Wrap useful components behind project interfaces. A discontinued repository is not permission to reuse its proprietary game assets. Altering models does not remove copyright restrictions. This slice uses project-owned source and adds original systems; no third-party asset import is proposed.


## Remaining work and sequence

Continue from [SYSTEMS_CONTINUATION.md](SYSTEMS_CONTINUATION.md) and [CODEX_CLAUDE_LIVING_WORLD_INTEGRATION.md](concepts/CODEX_CLAUDE_LIVING_WORLD_INTEGRATION.md). The systems PR is still draft; implementation presence is not acceptance evidence.

1. **Verify the current integration in the real game.** Claude checks this branch against unpushed work; then verify the water approach/slot geometry, actor and slot release, interruption, save/load, time skip and LOD transitions. Capture two/three-user contention and measure LOW-tier CPU/frame-time before expanding the actor cap.
2. **Add evidence-based NPC memory.** Define a verified event-to-witness producer first. Keep event facts separate from what a particular observer perceived, retain confidence/age/source, coalesce repeated observations and impose per-observer/global bounds. Do not invent offender identity or let journal queries imply omniscience. NPC familiarity is now recorded separately; it is not evidence or belief.
3. **Expand physical activities only after water acceptance.** Reuse one route/body owner and ActionRuntime. Workstations need exact semantic slots, reachability, queue or fallback, a task/effect owner and interruption/LOD rules; retain the established crafting station registry. Claude owns rigs, clips, props and contact markers.
4. **Connect life and economy.** Add work orders/opportunities and make bounded NPC-to-NPC familiarity useful through existing careers, relationship and economy owners. Track conserved inputs/outputs and compensation; distant simulation stays data-only and bounded. Resolve canonical person identity before generator migration.
5. **Add law, rumors and personal matters as causal systems.** Require local jurisdiction and actual evidence for crime response; reports and rumor claims carry provenance and confidence. Scenario instances must reference real participants/causes and bound casting/resolution work.
6. **Keep Claude-owned tracks separate.** Survival construction, campaign map/war causes/player influence, assets, animations and world presentation stay with Claude unless task ownership is explicitly coordinated.
7. **Measure mobile limits.** Use representative low-tier hardware and warm sustained captures. Record frame-time percentiles, active physics/animation bodies, sight queue wait/expiry, path work and bounded data sizes. Current numeric caps are safeguards, not proof of mobile performance.

No full-game parser/runtime, visual acceptance, save/load, behavioral, or phone-performance result is claimed by the current branch. Record evidence and limitations per slice; do not call a system accepted from static review alone.
