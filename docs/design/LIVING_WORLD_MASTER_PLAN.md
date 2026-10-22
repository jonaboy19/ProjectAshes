# Living World Master Plan (MW backlog)

Status: merged backlog, 2026-10-21. Godot 4.6.2, PC-first (phone later). Merges the owner's three new spec blocks (A to L) with `LIVING_WORLD_SANDBOX.md` (LW stages) and `NPC_INTELLIGENCE_MAP.md` (NI-1..12). It adds rows only where neither plan covers the item. Duplicates are cited, not restated. Read-only audit: file existence and greps were checked, function bodies were not read and no Godot or git was run. "EXISTS" means the module is there and covers the rule in kind, not at the spec's scale.

**Owners.** cloud = systems, CPU, save, tests. local PC = visuals, GPU, editor GUI, animation feel. Codex = animation behaviour (state machines, blends, IK tuning).
**PC-first rules.** Forward+ features are allowed behind `core/quality.gd` tiers (it already has toggles for ssao, ssil, sdfgi, glow, vol_fog, ssr). Sim budgets stay the LW Part E numbers (pump 0.6 ms, near 2.0 ms, 24 full bodies) so the phone port stays viable. Nothing here adds per-frame work in `scripts/realm/`. Save impact is quoted against the 2.5 MB raw limit (schema is now 4: `save_manager.gd` `SCHEMA_VERSION := 4`).

## 1. Architecture roles mapped to existing scripts (spec I)

No new framework. Every role already has a home; the gaps are two new modules (`persona`, `psyche`, both from NI-2/NI-4) and one pure service (`social_perception`, MW-5).

| Role | Existing script(s) | Gap and plan item |
|---|---|---|
| WorldState | `autoload/world_sim.gd` (packed rows), `realm/realm_hub.gd` (module list, tiers), `realm/registry.gd` (`ch:n` ids) | none |
| NPCIdentity | `registry.gd` (16 trait words), `realm/minds.gd` (decision records), `population/utility_brain.gd personality()` (5 floats) | `persona.gd` MISSING: NI-2, extended by MW-1 |
| Knowledge | `realm/rumours.gd`, `realm/news.gd`, `realm/sighting_report.gd`, `population/witness.gd`, `evidence.gd` | memory weight/witnesses: NI-4; belief-only reads: MW-3 |
| Decision | `minds.gd _choose`, `utility_brain.gd` | shared scorer and data goals: NI-3; plans: NI-8 |
| Relationship | `sim/relationships.gd` (NPC to player), `sim/npc_social_graph.gd` (one scalar), `realm/reputation.gd`, `society.gd` (8 axes, ~200 notables) | axes for all: NI-5 |
| SocialPerception | partial pieces: `society.gd` `outfit.disguise`, `reputation.gd`, `faith.gd` etiquette, `homes.gd rank_in`, `territory.gd` legitimacy | MISSING as a service: MW-5 |
| ConsequenceEngine | `realm/emergence.gd` (10 chains, depth 4, cooldown 120, 24 live), `events.gd` | chain to person: NI-7; winners and losers: MW-11 |
| Scheduler | hub `tick_hour/day/week/day_chunks`, `minds._due` buckets, `PUMP_BUDGET_USEC` | none |
| WorldEvents | `events.gd` ring (2,000), `news.gd` delay by road, `scribe.gd` | digest: MW-33 |
| EconomyLedger | `businesses.gd` weekly accounts, `enterprise_core.gd`, `sim/economy.gd`, `lordship.gd`, `followers.gd` wages | scattered, no realm ledger: MW-19 |
| Persistence | `realm/save_codec.gd`, `sim/save_manager.gd` (schema 4, md5, zstd), `save_containers.gd` | gauges: NI-12 |

**Worker threads for pure data only.** Threads already appear in `world/terrain_streamer.gd`, `terrain3d_bridge.gd`, `thornfield/cart_route.gd` and `save_manager.gd`. Rule (MW-36): `WorkerThreadPool` jobs may take a packed snapshot and return a packed result; they never touch nodes, the hub, `WorldSim` arrays in place, or RNG state. Candidates: far-tier day aggregates (district values, ledger settle, scout-report merge), save encode. Not needed until a profile shows a day total over budget (LW Part E notes orgs and businesses day totals are 14 to 80 percent over on a debug build: re-measure on a release PC build first).

## 2. Master backlog

Status: EXISTS / PARTIAL / MISSING. "Covered" cites the plan item that already owns the work, or the new MW id. Perf is per PC budget; "none" = no runtime cost.

### A. Living world and hidden values

| ID | Item | Status | Evidence / gap | Covered | Owner | Perf |
|---|---|---|---|---|---|---|
| A1 | World runs without the player | EXISTS | `realm/civilization.gd`, `migration.gd`, `notables.gd`, `minds.gd`; `tests/test_lw_society_soak` (2 game years, no player) | LW-1, LW-8 | cloud | done |
| A2 | NPCs act on beliefs only (rumours, mistaken, deceived) | PARTIAL | `minds` layer 5 reads only `news.heard_kinds`; `rumours.gd` garbles claims. Other layers (cash, town facts) read ground truth; no per-person belief store feeds `_choose` | NI-3, NI-4, MW-3 | cloud | read-only lookups, no alloc |
| MW-3 | Belief-only rule: any `_choose` input about a third party or distant place comes from the actor's belief (confidence, age), with a lint test that fails on direct module reads from `minds` for non-local facts | MISSING | no lint | new | cloud | none at runtime |
| MW-1 | Layered hidden values for NPC and player: innate aptitudes, skills, core personality, psych state, beliefs, social tendencies, hidden motivations, circumstances, public identity vs true identity, magical presence. Player gets the same record (`pl:` alias exists in `registry.gd`) | PARTIAL | NI-2 plans temperament 4 B, values 6 B, intelligence, 4 to 6 skills, culture, birth_sid (no code yet: `realm/persona.gd` absent). `sim/tendencies.gd`, `sim/soul.gd`, `sim/skills.gd` hold player-only bits | NI-2 plus MW-1 extension: aptitude (4 B), public_id vs true_id flag, magic_pot (1 B), motive slot (1 B) | cloud | +8 B x 1,000 = 8 KB |
| A3 | Per-person relationships | PARTIAL | `npc_social_graph` one scalar, `society.gd` 8 axes for ~200 | NI-5 | cloud | 32 KB |
| MW-2 | People learn differently from the same experience (appraisal: same event, different lesson by temperament, values, history) | MISSING | NI-4 caps value drift at 3 points per year but defines no appraisal function | extends NI-4 with `appraise(persona, memory) -> value deltas`; test: 2 personas, same witnessed crime, different drift | cloud | weekly, closed form |

### B. Social perception, legitimacy, disguise

| ID | Item | Status | Evidence / gap | Covered | Owner | Perf |
|---|---|---|---|---|---|---|
| MW-5 | `SocialPerception.read(observer, subject) -> {wealth, authority, reputation, threat, magic_pressure, protection, local_influence, legitimacy}`. A pure static function of persona, outfit/gear, reputation axes, culture, territory, escort; derived, never stored | MISSING | inputs exist, no composer | new | cloud | O(1) per call, cache per pair for 1 game hour, near tier only |
| B1 | Apparent wealth, reputation inputs | PARTIAL | `reputation.gd` multi-axis (town level), `society.gd outfit` (kind, dirty) | MW-5 | cloud | n/a |
| B2 | Recognised authority, rank not recognised abroad | PARTIAL | `homes.gd rank_in` is 0 abroad unless crowns allied; `stewardship.gd` authority chain; `titles.gd` | MW-5, MW-6 | cloud | n/a |
| MW-6 | Legitimacy triple: title vs actual power vs perception, per observer culture and kingdom (eastern kingdoms need not honour Valencios nobility) | PARTIAL | `territory.gd` has sovereignty/ownership/occupation layers and "capture is not lawful lordship"; `faith.kingdom_profile` per kingdom; none for persons | MW-5 reads these | cloud | n/a |
| B3 | Physical threat, social protection, local influence | PARTIAL | `utility_brain` threat inputs; `territory.gd` influence/patrol layers; escort cuts encounter odds in `homes.gd` travel parties | MW-5 | cloud | n/a |
| MW-7 | Bump-into-stranger encounter varies by status (peasant, noble, armed, hooded, mage) | MISSING | no bump event | MW-5 plus MW-37 (presence bus) | cloud (logic) + Codex (reaction clips) | event only |
| MW-8 | Disguise, hidden identity, impersonation, exposure | PARTIAL | `society.gd set_outfit(kind, dirty, disguise)` is player-only; no NPC identity swap, no exposure roll | extends MW-5 (`public_id` from MW-1) | cloud | n/a |

### C. Magic aura

| ID | Item | Status | Evidence / gap | Covered | Owner | Perf |
|---|---|---|---|---|---|---|
| MW-9 | Aura: emission (from power/pool), suppression and concealment (skill, item), projection (deliberate), observer sensitivity (own aptitude), misjudgement (error from intelligence and stress). Output feeds MW-5 `magic_pressure` and the alert scalar. Never mind control or forced behaviour: it shifts scores and thresholds only | MISSING | `sim/magicules.gd` is a pool; `actors/soulbeast_aura.gd` and aura bits in wolf/monster are creature VFX/aggro | new (reads MW-1 `magic_pot`) | cloud (data) + local PC (visual hint) | O(1), near tier |

### D. Districts and winners/losers

| ID | Item | Status | Evidence / gap | Covered | Owner | Perf |
|---|---|---|---|---|---|---|
| D1 | Noble, poor, merchant, military quarters | PARTIAL | `world/districts.gd` = layout anchors only; `migration.gd` has culture shares per district; `settlements.gd` identity drift | LW-5.2 (districts) | cloud | n/a |
| MW-10 | Hidden district values (prosperity, unemployment, housing cost, food security, safety, corruption, political support, culture mix, tension) as 9 bytes per district, evolving on the day tick from existing modules (businesses, homes rent, farming, crime_watch, courts, governance) | MISSING | settlement-level aggregates exist; no per-district vector | new, extends LW-5.2 | cloud | ~40 districts x 9 B; day tick 0.1 ms, far tier |
| MW-11 | Winners and losers per action: every player or NPC action that writes an EventRecord also lists affected groups; `emergence` effects reference a district/group delta | PARTIAL | `emergence` effects are multipliers per town; `events.gd` has actors/weight but no beneficiary list | extends NI-7 and MW-10 | cloud | adds <=4 B per event |

### E. Followers and delegation

| ID | Item | Status | Evidence / gap | Covered | Owner | Perf |
|---|---|---|---|---|---|---|
| E1 | Followers with agency, wages, disputes, post assignment, summon delay | EXISTS | `realm/followers.gd` (`recruit`, `hire`, `decide` with disputes, `assign_post`), `actors/follower_brain.gd` | LW-2.1 | cloud | done |
| MW-12 | Mixed motivations and roles (personal, military, economic, settlement, political, social); request, disagree, refuse, leave, demand, betray, coup. Acceptance scenario "Theron" (commander): loyal to the person not the realm, demands land after three wins, leaves if unpaid, coups if the lord is absent and he holds the garrison | PARTIAL | loyalty and disputes exist; no motivation vector, no demand/betray/coup verbs; `succession.gd` has coups for crowns only | extends LW-2.3 (command chain) with persona motive (MW-1) | cloud | day tick, event-driven via `poke` |
| MW-13 | Delegation quality: a governor or steward's competence and honesty change real outcomes (tax collected, corruption leak) | PARTIAL | `stewardship.gd` offices have holders, permissions, limits; `city_life.gd` has embezzle; no competence or honesty applied to output | extends LW-6.2 | cloud | day tick |
| MW-14 | Audit, reward, dismiss, imprison a delegate | PARTIAL | `courts.gd`, `arrest`, `audiences.gd` exist; no audit action on the ledger | needs MW-19 | cloud | on demand |

### F. War as emergent system

| ID | Item | Status | Evidence / gap | Covered | Owner | Perf |
|---|---|---|---|---|---|---|
| MW-15 | Scout reliability and conflicting reports (each scout has accuracy, bias, loyalty; two reports can disagree) | PARTIAL | `sim/scouts.gd`, `realm/sighting_report.gd`, `campaign.gd` intel ageing | extends LW-7.2 | cloud | per report |
| MW-16 | Envoy audiences with personal agendas; neutrality outcome computed from state (trade ties, fear, debts, kin), not a dice roll | PARTIAL | `diplomacy.gd`, `audiences.gd`, `war_advisors.gd`; envoy has no agenda field | extends LW-6.3 | cloud | event |
| MW-17 | Offscreen war: supply, morale, weather, intel as inputs to the resolved outcome | PARTIAL | `campaign.gd` supply/attrition/depots, `armies.gd`; weather input not found in grep of war code | extends LW-7.1; weather read via `world/weather.gd` state only | cloud | hour tick, 10 armies 0.3 ms |
| MW-18 | Live battlefield reconstruction when the player arrives mid-battle (sim state to playable units, positions, losses so far, morale) | MISSING | `tactical.gd` is a grid battle; no hand-off from `campaign` engagement state to bodies | extends LW-7.2 | cloud (state to spawn plan) + local PC (feel, camera) | spawn cap `MAX_SPAWNS_PER_FRAME 1`, <=24 full bodies, rest sprites |

### G. Ledger and finance

| ID | Item | Status | Evidence / gap | Covered | Owner | Perf |
|---|---|---|---|---|---|---|
| G1 | Business weekly accounts (wages, rent, upkeep, interest, credit limit) | EXISTS | `realm/businesses.gd` | LW-4.3 | cloud | done |
| MW-19 | One realm ledger: wages, taxes, rent, upkeep, loans, contracts on a schedule; each payment moves gold to a real recipient (`ch:`, `org:`, `bz:`, treasury), never destroys it. Adapters over `followers` wages, `lordship` treasury/taxes, `homes` rent, `enterprise_core` ledger, `armies` upkeep | PARTIAL | five separate ledgers; no common payment record or conservation check | new (uses LW `Contract` ct:n) | cloud | weekly settle, chunked; 64 B per live obligation |
| MW-20 | Shortage ladder: delayed pay, then resign, desert, embezzle, mutiny, in that order by persona (loyalty, honesty) | PARTIAL | desertion in `soldier.gd`/`power_paths.gd`, embezzle in `city_life.gd`, unpaid-leaves in LW-2.1; no shared ladder | MW-19 plus MW-1 | cloud | event-driven |
| MW-21 | Treasurer/steward delegation: budgets, warnings, weekly report | PARTIAL | `enterprise.hire_leader`, business `report_log` ring of 8, `stewardship.gd` | LW-4.3 plus MW-33 | cloud | weekly |

### H. Additional missing systems

| ID | Item | Status | Evidence / gap | Covered | Owner | Perf |
|---|---|---|---|---|---|---|
| H1 | Generational sim, legacy bloodlines | EXISTS | `dynasties.gd`, `minds.gd` life cycle, `homes.gd`, `succession.gd` | LW-8.1..3 | cloud | done |
| H2 | Witnesses and rumours | EXISTS | `population/witness.gd`, `evidence.gd`, `rumours.gd` | LW-8, NI-4 | cloud | done |
| MW-22 | Evidence, investigation as case records, trials, appeals | PARTIAL | `courts.gd` (trial/appeal strings found), `society.gd` evidence ageing; NPC investigator cases not verified | LW-6.4 | cloud | day tick |
| MW-23 | Internal faction politics: elections, coups, splinters | PARTIAL | `organizations.gd` schism, `governance.gd` councils, `succession.gd` coup | LW-4.2, MW-12 | cloud | weekly |
| MW-24 | Obligations: promises, oaths, favours, debts of honour as a record with due date and breach consequence | MISSING | `society.gd` has a `debt` axis; `land.gd`/`news.gd` mention oaths as text; no Obligation record | new, rides on `Contract` (LW-2.1) and NI-9 debts | cloud | 40 B each, cap 2,000 |
| MW-25 | Social influence verbs: persuade, intimidate, blackmail, patronage with success from persona and MW-5 | PARTIAL | verbs appear in `city_life.gd`, `followers.gd`; not one resolver | LW §17 action framework gap | cloud | on demand |
| H3 | Teaching, apprentices, schools | EXISTS | `education.gd`, `career_trades.gd`, `homes.gd` school ages | LW-2.2 | cloud | done |
| H4 | Autonomous organizations | EXISTS | `organizations.gd`, `notables.gd`, `faith.gd` churches | LW-4.2 | cloud | done |
| MW-26 | Communication and travel delay: messengers (EXISTS: `news.gd` road delay, campaign couriers), intercepted letters, outdated info acted on | PARTIAL | interception and forged/stale-letter decisions missing | extends LW-7.2 and MW-15 | cloud | event |
| MW-27 | Infrastructure: roads, bridges, wells, granaries as upgradable assets changing district values | PARTIAL | `lordship.gd` infra, `construction.gd`, `towers.gd`; no road quality to travel time loop | MW-10 | cloud | day tick |
| H5 | Ecology and wildlife migration | EXISTS | `realm/ecology.gd`, `ecology_factions.gd`, `sim/monster_ecology.gd` | LW-8 | cloud | done |
| MW-28 | Daily social interactions and etiquette (greetings, bows, who speaks first by status) | PARTIAL | `faith.gd` etiquette mods, `population/talk_bark.gd`, `talk_pose.gd` | MW-5 plus MW-41 | cloud + Codex | bark budget existing |
| MW-29 | Emergent opportunities from real shortages (NPC and player contracts generated from a shortage, not scripted) | PARTIAL | `settlements.gd` emergencies, `radiant_quests.gd`, `enterprise` price intel | extends LW-8.2 | cloud | day tick |
| MW-30 | Historical memory and legacy across generations (a house remembers a feud or a famine) | PARTIAL | `events.gd` compaction keeps 200 historic lines; `dynasties.gd` feuds | extends NI-4 | cloud | tiny |
| MW-31 | NPC-to-NPC life stories (readable biography of non-notables from their events) | PARTIAL | `sim/biography.gd`, `life_courses.gd` (~150 notables) | NI-6 trace reuse | cloud | on demand |
| MW-32 | NPC ability progression: capacity vs control, ageing, injury | MISSING | `skill_evolution.gd`, `mastery.gd` are player-side; `injuries.gd` player; NI-2 skills are static bytes | extends NI-2/NI-4 | cloud | yearly step, closed form |
| MW-33 | Information delivery without notification spam: messenger reports, rumours at the inn, one steward weekly report, urgent only for direct threats | PARTIAL | `news.gd` delay, `ui/notify_stack.gd` | new digest over `events.after(n)` | cloud (data) + local PC (UI) | weekly |
| MW-34 | Ordinary peaceful life is valued; the game continues after becoming king | PARTIAL | LW rule 5 ("income without a quest"); crowns/lordship exist; no acceptance sims | LW-8.4; add 2 scenarios: farmer with no quests for 1 year ends richer and better known; king reign 5 years has playable loop | cloud | CI only |

### I. Consequence engine principles

| ID | Principle | Status | Evidence | Covered | Owner | Perf |
|---|---|---|---|---|---|---|
| I1 | Causality first | EXISTS | `emergence.gd` stages; `events.gd cause` string | NI-6 adds numeric parent | cloud | n/a |
| I2 | Seeded controlled variation | EXISTS | rolls are `hash([SEED, tag, day, id])` | LW Part E 6 | cloud | n/a |
| I3 | Persistent consequences | EXISTS | per-module containers, schema 4 | LW Part E | cloud | n/a |
| MW-35 | Deterministic saves, no reload-scumming: outcomes are keyed by (day, id), never by load count or wall clock; test that saving, reloading and re-acting yields the same result | PARTIAL | determinism asserted per module; no end-to-end reload test | extends NI-10 (add "save at day N, reload, run 30 days, same hash") | cloud | CI only |
| I4 | Relevance and time-limited propagation | EXISTS | `emergence` MAX_DEPTH 4, COOLDOWN 120, MAX_LIVE 24; `news` delay; NI-7 person caps | NI-7 | cloud | n/a |
| MW-36 | Worker threads for pure data only | PARTIAL | see section 1 | new rule | cloud | see section 1 |

### J. Reactive Presence System

Single stimulus path: extend `population/npc_world.gd` (incident ring, `report()`), `perception.gd` (vision/hearing), `alert_net.gd`, `witness.gd`, `trespass.gd`, and the alert scalar in the `ashes-perception-ai` skill. Do not add a parallel bus.

| ID | Item | Status | Evidence / gap | Covered | Owner | Perf |
|---|---|---|---|---|---|---|
| MW-37 | Body-proximity stimuli: staring (head and eye direction, not camera), following, blocking a doorway, bumping, running through a crowd | MISSING | `villager.gd` has head look and `_crime_input`; no stare/follow/block/bump kinds in `NpcWorld.Kind` | new kinds on the existing ring | cloud (rules) + Codex (reactions) | stare check on the existing 3.3 Hz think tick; no new rays |
| J1 | Drawn weapon in tavern/shop, trespass, taking objects | EXISTS | `trespass.gd`, `sim/theft.gd`, `pickpocket.gd`, `crime_watch.gd`; drawn-weapon kind not verified | LW-1, F5 | cloud | done |
| MW-38 | Social-cue stimuli: eavesdropping, public magic (needs MW-9), kindness, enemy insignia, injured player, repeated visits | MISSING | `relationships.gd` familiarity exists; no visit counter feeding reactions | MW-5, MW-9 | cloud | counters packed per NPC near tier |
| J2 | Awareness channels (vision, hearing) | EXISTS | `perception.gd`, `alert_net.gd` | perception skill | cloud | existing budget <=0.25 ms |
| MW-39 | Awareness channels: social, magical, environmental; limited attention budget (each NPC attends to <=2 targets, ranked by MW-5 salience) | MISSING | none | new | cloud | caps work at 24 NPCs x 2 |
| MW-40 | Multi-stage responses with de-escalation and memory (glance, warn, confront, act; player can apologise or leave; result stored as a NI-4 memory) | PARTIAL | alert classes with hysteresis exist (suspicious, searching, alarmed); no de-escalation script or memory write for social incidents | NI-4 | cloud + Codex | event |
| J3 | NPC-to-NPC observation | PARTIAL | `alert_net.gd`, `micro_events.gd`; NPCs mostly sense threats and the player | MW-37/38 same path, observer is any body | cloud | same budgets |

### K. Animation (behaviour belongs to Codex and local)

| ID | Item | Status | Evidence / gap | Covered | Owner | Perf |
|---|---|---|---|---|---|---|
| MW-41 | One reaction interface: AI requests abstract reactions (`glance`, `step_back`, `bow`, `flinch`, `confront`, `wave`, `return_to_work`) with a priority; animation layer maps them to clips and adapts over the current activity instead of cancelling it | MISSING | `villager.gd` plays reactions in-script; no request contract | cloud writes the contract and tests (enum, priority, interrupt rules); Codex implements | cloud (contract) + Codex | request is an int enqueue |
| K1 | Layered animation: base, directional, upper body, eyes/head, face, gestures, posture, flinch, object interaction, combat, secondary motion | PARTIAL | `actors/character_animator.gd` (AnimationTree, BlendSpace2D, OneShot), `living_world/face_state.gd`, `hero_face_driver.gd`, `crowd_anim_lod.gd`; additive hit reactions and armed locomotion open per `FOUNDATION_PLAN.md` | Codex list in FOUNDATION_PLAN | Codex | per-body budgets in `ashes-performance` |
| K2 | LookAtModifier3D, SpringBoneSimulator3D | EXISTS | `procedural_rig.gd`, `life_actor.gd`, `horses/horse_springs.gd` | none | Codex | done |
| K3 | TwoBoneIK3D / FABRIK3D / CCDIK3D | PARTIAL | referenced in `procedural_rig.gd`, `horses/rider_ik.gd`; not used for hand-on-door, foot placement, sitting | trial in MW-44 | Codex | near tier only |
| K4 | PhysicalBoneSimulator3D (ragdoll) | EXISTS | `actors/ragdoll.gd` (pooled) | none | Codex | done |
| K5 | RetargetModifier3D | MISSING | not referenced; retargeting is done offline in Blender (`ashes-animation-pipeline`) | TRIAL only if runtime sharing of clips across skeletons is needed | Codex + local | none until used |
| K6 | Root motion | PARTIAL | referenced in `combat_moves.gd`, `combat_action.gd`, `player.gd` | Codex | Codex | n/a |
| K7 | Motion matching | MISSING | experimental in engine | REJECT for now; revisit after 4.7 trial | n/a | n/a |
| MW-44 | Smart-object affordances: chair, door, forge, fallen body, horse with safe interruption (finish the current step, release the slot) and synchronized multi-character actions (handshake, carry, duel) | PARTIAL | `living_world/smart_objects.gd` (types in `data/living_world/smart_objects.json`, claim/release, enter/loop/exit); no interrupt rule set, no multi-claim action | extends F1/F6 in FOUNDATION_PLAN | cloud (claims/interrupt rules) + Codex (clips) | per claim, near tier |
| K8 | Animation LOD | EXISTS | `crowd_anim_lod.gd`, `vat_crowd.gd`, `vat_residents.gd` | none | Codex | done |

### M. 8 GB RAM PC preset (owner request)

Goal: the full feature set runs on an 8 GB RAM PC. The 16 GB quality path (existing `Quality.PC_TIERS`, tiers Low/Medium/High/Ultra, `profile == "pc"`) is not changed. Simulation data is not the bottleneck: LW Part E caps the sim at about 2.5 MB raw save and a few MB of packed arrays. Memory is textures, meshes, GI and streaming.

| ID | Item | Status | Evidence / gap | Covered | Owner | Perf |
|---|---|---|---|---|---|---|
| MW-8GB | New "8 GB" PC preset added beside the existing tiers, selectable and auto-detected from `OS.get_memory_info()`: half-resolution texture mipmap limit, smaller cell/stream radius (`cell_streamer` profile), fewer full-body NPCs nearby (`PopulationLOD` full count below 24, more sprites), SDFGI and VoxelGI off, baked light (VAO recipe, LightmapGI where baked) plus SSAO. No feature is removed: sim, NPC counts in the data tiers and saves are identical | MISSING (tiers exist in `core/quality.gd`, no memory-targeted preset) | `quality.gd` has `PC_TIERS` and ssao/ssil/sdfgi/vol_fog keys; `addons/mobile_texture_limit` exists for texture caps | extends spec L Forward+ rows | cloud (preset data, detection, tests) + local PC (look check) | target process RSS under about 5 GB in a busy town |
| MW-8GB-T | Headless memory-budget gate test: loads the preset, runs the Ashford/Thornfield benchmark scene and the 1,000-character soak, records `OS.get_static_memory_usage()` and process RSS, fails above the budget (about 5 GB). Cloud measures what it can (no GPU, so VRAM and GPU-side texture memory are not seen); the gate lists that limit | MISSING | `perf_probe.gd` and `tools_qa/cpu_mem/` exist; no RSS gate | extends NI-12 gauges | cloud (CI only, not the memory-short container) | CI only |
| MW-8GB-L | Real RAM/VRAM measurement in a busy town on a PC, both presets, with the Godot monitors and RenderDoc/task manager; feed the numbers back to tune the preset | MISSING | none | new | local PC | n/a |
| MW-8GB-A | Asset pass: the 196 Meshy LOD1 pass lowers mesh and texture memory and helps both the 8 GB and 16 GB presets; schedule it ahead of tuning | PARTIAL (per owner's note) | `ashes-asset-pipeline`, gltfpack `-noq` | existing asset work | local PC | helps both |

## 3. Tool verdicts (spec L)

Sizes are from `du` of `kingdom/addons/*` on 2026-10-21. Licences marked (up) are from the upstream project as I know it and must be re-read from the addon's LICENSE before any new vendor. "Local" = needs the PC editor/GPU.

| Tool | Verdict | Reason | Licence | Size | Owner |
|---|---|---|---|---|---|
| Terrain3D | ALREADY HAVE (flag) | `addons/terrain_3d` v1.0.2; code reads `terrain_backend`; handoff doc says it is disabled with `.gdignore` and also that `extension_list.cfg` was missing, so confirm loaded state locally | MIT (up) | 44 MB | local PC |
| ProtonScatter | ALREADY HAVE | enabled in `project.godot`; `world/scatter_chunk.gd` uses it behind `terrain_backend = terrain3d` | MIT (up) | 1.8 MB | cloud + local |
| Road Generator | TRIAL (flag) | v0.9.3 present; try for visual road meshes only; `StreetGraph` stays the pathing truth | MIT (up) | 6.9 MB | local PC |
| Cyclops / CSG level tools | REJECT | CSG is a greybox tool, slow at runtime; levels come from `city_planner`/`build_kit` | n/a | n/a | n/a |
| Voxel Tools | REJECT | native module/GDExtension, large binary, no voxel terrain need; caves are authored | MIT (up) | big | n/a |
| Graph-based procgen | REJECT | `city_planner.gd`, `region_sites` already generate; a graph tool is a second generator | n/a | n/a | n/a |
| Chunk streaming addons | ALREADY HAVE | `terrain_streamer.gd`, `cell_streamer`, `PopulationLOD` | own | 0 | cloud |
| GridMap | REJECT | `build_kit.gd` owns snap grid and save format; no GridMap in scripts | engine | 0 | n/a |
| MultiMesh | ALREADY HAVE | `vat_crowd.gd`, `dungeon_build.gd`, `camera_occluders.gd` | engine | 0 | local |
| Modular Builder (alpha) | REJECT | alpha, duplicates `build_kit` | unverified | n/a | n/a |
| Roommate | REJECT | not verified what it adds; interiors are `interiors/modular_interior.gd`; revisit only with a link | unverified | n/a | n/a |
| Asset Placer / scene painter | REJECT in repo | ProtonScatter covers placement; an editor-only helper may live outside the repo, never committed | unverified | n/a | local |
| Tree3D (experimental) | REJECT | experimental; trees are baked/impostor assets | unverified | n/a | n/a |
| Sky3D | ALREADY HAVE | enabled, v2.1; physical sky comes from it | MIT (up) | 12 MB | local |
| Ocean / water addon | TRIAL later | only when a coastal scene exists; `quality.gd` already has `water_ssr` | varies | n/a | local |
| FastNoiseLite | ALREADY HAVE | engine built-in, used in UI/camera/map code | engine | 0 | cloud |
| GPUParticles3D | ALREADY HAVE | `world/weather.gd`, `settlement_builder.gd`; Effekseer is also vendored | engine / MPL-2 (up) | 7.8 MB | local |
| FogVolume | ADOPT (PC tier) | add pockets for Rift, dungeon, dawn mist when `vol_fog` is on | engine | 0 | local |
| Decal | ALREADY HAVE | `settlement_builder.gd`, `thornfield/clues.gd` | engine | 0 | local |
| SDFGI, SSAO, SSIL, SSR, volumetric fog | ALREADY HAVE (toggles) | `core/quality.gd` carries all; PC "high/ultra" tier tuning is local work with `ashes-style-g-qa` | engine | 0 | local |
| LightmapGI / VoxelGI | TRIAL | interiors and dungeons; baked VAO recipe (`ashes-baked-quality`) is the cheaper default | engine | scene size | local |
| ReflectionProbe | ADOPT (PC) | interiors and water-adjacent plazas | engine | 0 | local |
| SSS, physical sky | ALREADY HAVE | hero skin shader (`ashes-hero-character`); Sky3D | engine | 0 | local |
| CompositorEffect | TRIAL | optional post stack for PC only; Compatibility/mobile renderers cannot use it | engine | 0 | local |
| HDR output | TRIAL | verify engine support on 4.6.2 and display path first | engine | 0 | local |
| LimboAI | REJECT (verdict stays) | `addons/limboai` v1.8.1 is an inert 63 MB binary drop (no `plugin.cfg`); the near-body layer works via `utility_brain` + `smart_objects`; a BT would be a third engine. Newer 4.7 releases do not change that. Owner action: delete the folder (separate cleanup) | MIT (up) | 63 MB | owner / local |
| GOAP addons | REJECT | NI-8 bounded GOAP-lite in `plan_core.gd` | various | n/a | n/a |
| State charts | REJECT | `rec["g"]` plus `tp` flag cover life states | MIT (up) | n/a | n/a |
| NavigationServer3D / NavigationAgent3D | TRIAL (flag) | repo uses custom `StreetGraph` and no Navigation nodes (grep empty). FOUNDATION gap #10 says no off-road, indoor or stair routes. Trial for indoor and off-road only; `StreetGraph` remains primary | engine | 0 | cloud + local |
| Dialogue Manager 4 | ALREADY HAVE (unused) | `addons/dialogue_manager`; JSON runner serves personas; fix stale "autoloaded" comment in `sim/dialogue_runner.gd` | MIT (up) | 1.3 MB | cloud |
| Quest / inventory addons | REJECT replacing | `gloot` (624 KB) and `quest_weaver` (4.7 MB) are vendored; `ItemsDB`, `radiant_quests`, F7 objectives own the game. Do not migrate | MIT (up) | 5.3 MB | n/a |
| Jolt Physics | ALREADY HAVE | `project.godot` physics engine is Jolt; add a regression check at any engine upgrade (ragdoll, mounts, projectiles) | MIT (up) | 0 | cloud + local |
| Dungeon generators | REJECT | `interiors/dungeon_build.gd`, `towers.gd` | n/a | n/a | n/a |
| FMOD | REJECT | proprietary licence terms, extra GDExtension, Godot buses suffice | proprietary | n/a | n/a |
| Material Footsteps | ALREADY HAVE | `addons/godot_material_footsteps` | verify LICENSE | 1.2 MB | local |
| Settings-menu addon | REJECT | `core/quality.gd` and frontend UI exist | n/a | n/a | n/a |
| Translation | ADOPT policy | keep `text_key` in events and dialogue data, use `TranslationServer` CSV when strings are frozen; no addon | engine | 0 | cloud |
| Godot profiler, LOD, HLOD (visibility ranges), occlusion | ADOPT | built-ins; add `OccluderInstance3D` for PC town views; HLOD recipe in `ashes-baked-quality` | engine | 0 | local |
| Tracy | REJECT now | needs a custom engine build; `perf_probe.gd` plus RenderDoc suffice | BSD-3 (up) | n/a | n/a |
| RenderDoc | ALREADY HAVE | `tools/external/renderdoc_godot.ps1` | MIT | outside repo | local |
| gdUnit4 + GitHub Action | ALREADY HAVE | `addons/gdUnit4` (6.2 MB), `.github/workflows/tests.yml` pins `GODOT_VERSION` 4.6.2 | MIT | 6.2 MB | cloud |
| Git LFS | REJECT | public repo, free LFS quota is small; the size guard and keeping heavy sources outside the repo are the policy | n/a | n/a | n/a |
| Gitot | REJECT (unknown) | cannot verify what it is; no adoption without a link and licence | unverified | n/a | n/a |
| GDExtension (own) | REJECT now | no profiled CPU hotspot needs it; already shipped ones: debug_draw_3d, godot-sqlite, effekseer | n/a | n/a | n/a |
| Steam integration | LATER | after content freeze; GodotSteam-class addon, check licence then | MIT (up) | n/a | owner |
| Procedural texture baker | REJECT in-engine | Blender/Krita offline bakes are the pipeline | n/a | n/a | local |

**Storage warning (public repo).** Addons are about 270 MB: `godot-sqlite` 111 MB, `limboai` 63 MB, `terrain_3d` 44 MB, `sky_3d` 12 MB, `debug_draw_3d` 11 MB. Removing LimboAI saves 63 MB with no code change. `godot-sqlite` ships Android, iOS and macOS slices; with PC-first, owner may strip mobile slices now and re-add at the phone port. Both are owner decisions.

## 4. Engine version: 4.6.2 vs 4.7.2 / 4.8 beta

Recommendation: stay on 4.6.2 for the main line until LW Stage 8 plus NI-1..3 are merged and green. Then run one trial branch on 4.7.2 stable. Do not use 4.8 beta (a beta on a project with GDExtensions and baked shaders is all risk, no schedule gain).

Migration gate for the 4.7.2 branch (cloud runs CI, local PC runs the visual checks):
1. `tests.yml` `GODOT_VERSION` changed on the branch only; full suite green (2,243 cases at last count per `FOUNDATION_PLAN.md`).
2. `test_lw_society_soak` determinism hash equal to the 4.6.2 run (rolls use `hash()`, so a change signals an engine-level difference).
3. GDExtensions load: `terrain_3d`, `debug_draw_3d`, `godot-sqlite`, `effekseer` need builds that declare 4.7 compatibility (check each `.gdextension`/release notes before branching).
4. Jolt regression: ragdoll, mount, projectile tests.
5. Visual: `ashes-style-g-qa` screenshots of the fixed views; the `gltfpack -noq` import rule stays.
6. Revert rule: if any of 1 to 5 fails and cost to fix is over two days, stay on 4.6.x and retry at the next point release.
I did not read 4.7 release notes in this task; verify features before relying on them.

## 5. Prioritized execution order (cloud, PC-first)

Precondition: LW Stage 8 merged, NI-1 (red harness), NI-2 (persona), NI-3 (shared scorer) done. Each package is small, ends with tests through CI (`ashes-ci`), and leaves existing tests green.

| # | Package | Contains | Why now | Verify |
|---|---|---|---|---|
| 1 | NI-4 plus MW-2 | psyche module, memory tuple, mood, appraisal | everything downstream (reactions, followers, shortages) needs mood and memory | psyche tests; divergence still green; +<=5 B/char |
| 2 | MW-5 | `SocialPerception.read` pure service, with MW-6 legitimacy and MW-8 disguise inputs | single read used by encounters, audiences, followers | table-driven tests (noble vs peasant vs disguised); cost test |
| 3 | MW-19 and MW-20 | realm ledger adapters, conservation check, shortage ladder | wages exist in five places; unifies without rewriting | gold conserved over a 1-year sim; unpaid army deserts in persona order |
| 4 | MW-12, MW-13, MW-14 | follower motives, demand/betray/coup, delegate competence, audit | owner's Theron scenario | Theron scenario headless, both outcomes reachable |
| 5 | MW-9 plus MW-39 | aura model, attention budget | feeds MW-5 and public-magic reactions | aura never forces actions; budget test for 24 NPCs |
| 6 | MW-10 and MW-11 | district values, winners and losers list | makes player actions legible | 1-year sim: rent, safety, unemployment move in expected direction |
| 7 | MW-15, MW-16, MW-17, MW-26, MW-33 | scout reliability, envoy agendas, war factors, stale letters, weekly digest | the emergent war example and no notification spam | conflicting-reports scenario; digest caps at one weekly report |
| 3b | MW-8GB, MW-8GB-T | 8 GB preset data and memory gate (owner priority: ship-ability on common PCs) | before any new content grows memory | RSS under about 5 GB on CI harness; 16 GB tiers unchanged |
| 8 | MW-37, MW-38, MW-40, MW-41 | presence stimulus kinds, de-escalation, reaction request contract (data and tests only) | unblocks Codex and local PC without cloud animating | ring cost test; contract enum frozen and documented |

After 8: NI-5 to NI-9 in order, MW-18 (battlefield hand-off), MW-22 to MW-25, MW-27 to MW-32, MW-34/35 acceptance sims, NI-10 and NI-12 gates. Budgets for every package: new day jobs chunked (`tick_day_chunks`), no per-frame realm work, save growth reported by NI-12 gauge.

## 6. Local PC session list

0. MW-8GB-L: measure RAM/VRAM in a busy town on both presets; judge the 8 GB look; run the 196 Meshy LOD1 pass.
1. Confirm Terrain3D load state and `terrain_backend` flag behaviour; ProtonScatter forest chunk look.
2. Forward+ quality tiers: tune SDFGI, SSIL, SSAO, SSR, volumetric fog on the Ashford benchmark views; add FogVolume pockets and ReflectionProbes; trial LightmapGI/VoxelGI for interiors; CompositorEffect and HDR trials.
3. Road Generator trial against `StreetGraph` roads (visual only).
4. NavigationServer3D indoor/off-road trial (with cloud).
5. 4.7.2 trial branch visual and GDExtension checks (section 4).
6. NI-11 inspector UI; MW-33 digest UI; recruit/org/business panels (LW-2.4, 4.5).
7. Battlefield reconstruction feel and camera (MW-18); aura visual hint (MW-9).
8. Delete `addons/limboai` and optionally trim `godot-sqlite` mobile slices (owner approval); check export still builds.
9. RenderDoc and Godot profiler pass on a PC mid-spec target; HLOD/occluder tuning.
10. With Codex: IK use for hands/feet (K3), reaction clips for MW-41, synchronized actions (MW-44).

## 7. Explicitly not doing

LimboAI, GOAP or state-chart addons (one scorer: NI-3/NI-8); replacing `ItemsDB`, quest or inventory systems with addons; replacing `StreetGraph` with NavigationServer (trial for indoor only); GridMap, Modular Builder, Voxel Tools, Cyclops, Tree3D, graph procgen (we own the generators); FMOD; Git LFS; Tracy; motion matching; runtime LLM or Ollama (owner rule); mind-control magic; a second event bus, memory store or decision engine; per-NPC UI nodes or per-frame loops over all villagers; Godot 4.8 beta; storing derived perception values in the save; threads that touch nodes or hub state.

## 8. Open questions for the owner

1. Delete `addons/limboai` (63 MB) now? Trim `godot-sqlite` mobile slices until the phone port?
2. Confirm the 2.5 MB raw save limit (inherited from LW Part E) with MW-1/10/24 added.
3. Confirm troops stay stacks and only officers and the retinue are Characters (inherited).
4. Provide links for Roommate, Gitot and the "20 more" professions (inherited).
