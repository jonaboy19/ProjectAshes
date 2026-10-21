# NPC Intelligence Map: audit, gaps and work plan (NI-1 to NI-12)

Status: read-only audit of the repo as it stands on 2026-10-21, Godot 4.6.2, game in `kingdom/`. No git and no Godot were run; every statement below comes from reading source and docs. Stage 8 (LW-8.1 to 8.3) was still being written by another agent while this was audited: its six modules exist and are described in `docs/design/LIVING_WORLD_SANDBOX.md` "Stage 8 built and measured". Re-check the Stage 8 rows (section 2) before starting NI-2.

Goal restated: deeply individual NPCs (the same situation gives different outcomes for different people), causal chains of consequence, bounded (no random chaos, no endless loops, ordinary stability), no runtime LLM, three-tier simulation inside the existing budgets.

## 0. Headline findings

1. The project already has most of the machinery. There are TWO existing decision engines and they do not talk to each other: the embodied near-tier `population/utility_brain.gd` (28 acts, response curves, 5 personality floats, needs) and the registry-tier `realm/minds.gd` (five layers, 11 goals, tiers, due-day buckets, chunked day tick). The big missing piece is a shared individual-person record that both read, not a third AI framework.
2. Individuality today is thin: `utility_brain.personality()` is 5 floats (sociable, lazy, pious, greedy, courage) derived from the row index; `registry.traits_for(row)` gives a list of 16 trait words; `minds._choose` gives individuality only through age, cash, a `_h("amb")` ambition hash and a +-0.1 noise term. Two people in the same situation differ mostly by hash, not by temperament, values, history or relationships.
3. Memory exists in three disconnected places (registry `m`: 12 lines of text, rumours `_mem`: 4 tuples per character, utility_brain `remember_danger`: 3 spatial slots), none carries witnesses or emotional weight, and none feeds `_choose`.
4. The causal-chain layer (`emergence.gd`) is real and well loop-controlled, but it works at town level. No chain reaches a single person's mood, trait or plan.
5. Addon verdict: neither a GOAP addon nor LimboAI fills a gap that cannot be filled in about 400 lines of in-house GDScript on top of the existing scorer. LimboAI in `kingdom/addons/limboai/` is an unusable binary drop (no `plugin.cfg`, no `.gdextension`, not enabled, 63 MB). Recommendation: ONE planner, a small data-driven bounded GOAP-lite inside the existing utility scoring (section 4).
6. Biggest performance risk is not CPU, it is save size and per-character allocation if the new psychology record is stored as Dictionaries. Keep it packed (section 7).

## 1. Compatibility map (phases 2 to 6)

Legend for "how fully": FULL, PARTIAL, THIN, NONE.

### Phase 1: audit (this document)
Key existing contracts the new work must obey:
- `scripts/realm/realm_module.gd` + `realm_hub.gd`: module base (`tick_hour/day/week`, `tick_day_chunks`, `catch_up`, `serialize/deserialize`); hub `ORDER` list; `PUMP_BUDGET_USEC = 600`.
- `scripts/realm/registry.gd`: persistent ids (`ch:n`), alias map, `CHAR_MAX = 1000` upgraded characters.
- `scripts/realm/events.gd`: EventRecord ring (2,000 rows, packed `[n, day, kind, where, actors[], cause, outcome, weight]`).
- Determinism rule: every roll is `hash([WorldSim.SEED, tag, day, id])`, no global RNG, no Vector2 in saved state.
- `autoload/world_sim.gd` (704 lines): ~20,000 people as packed arrays (`home, job, pos, target, money, health, phase`), sliced update with `BUDGET_US = 500`, `NEAR_RADIUS = 320`.

### Phase 2: identity and psychology

| Item | Existing code | How fully | Integration point |
|---|---|---|---|
| Unique ids | `realm/registry.gd` (`ch:n`, never reused, aliases for `ws:`, `lc:`, `nt:`, `fo:`, `sn:`, `pl:`) | FULL | Keep. All new records key on `ch:n`. |
| Family | `realm/dynasties.gd` (houses, heads, feuds, estates), `realm/homes.gd` (households, children, spouse), `minds` (`sp`, `pa`, `_kids`), `sim/family.gd` (player family), `sim/life_courses.gd` (parents/children for notables) | PARTIAL: strong at house level, parentage stored as strings per mind row; no siblings/in-laws graph | Derive a read-only kin view from `minds._kids` + `dynasties._kin`; do not add a second family store. |
| Origin | `minds` `rec["r"]` (WorldSim row), settlement via `c["sid"]`, `homes` history of residences | THIN: no birthplace or upbringing field | Add `birth_sid` to the new person record (NI-2). |
| Culture | `realm/faith.gd` culture tags per TOWN (caldric, urrokai, veyl, solenne, frontier), etiquette/price/law multipliers | PARTIAL: town-level only; the person inherits nothing | NI-2: person `culture` = town tag at birth, drifting with residence; influences weights, never fixes them. |
| Languages | none found (no NPC language field); `scribe` has glyph knowledge for the player | NONE | NI-2 (small bitmask, 1 byte). Low gameplay priority; gate by culture/region. |
| Education | `realm/education.gd` (2,750 lines, academies, ages), `homes` (school 7, academy 9, apprentice 12), `minds` rec `ed` | PARTIAL: `ed` is a small int on mind rows | Map `ed` to skill priors in NI-2. |
| Occupation | `minds` `c["prof"]` (8 profs), `WorldSim.job` (6 jobs), `sim/careers.gd`, `career_ladders.gd`, `realm/businesses.gd`, `farming.gd`, `organizations.gd` | FULL (two vocabularies; mapped by `minds.JOB_PROF`) | Keep both; person record stores `prof` only by reference. |
| Hidden traits | `registry.TRAITS` (16 words) via `traits_for(row)`; read by `faith.seed_belief` only | THIN: list stored, almost never read by decisions | NI-2/NI-3: convert to a weight vector. |
| Temperament | `utility_brain.personality()` 5 floats from `NeedRules.trait_value(p, k)` | THIN (near tier only, not shared with `minds`) | Single source: the new person record; `personality()` becomes a view of it. |
| Intelligence | none (grep: no NPC intelligence field) | NONE | NI-2 (one byte). Used to scale mistake rate and plan depth. |
| Skills | `registry` char `s: {}` (empty), `sim/mastery.gd` and `progression.gd` are player-oriented, `society.gd` tiers (commoner..legend) for ~200 notables | THIN for ordinary NPCs | NI-2: 4 to 6 skill bytes, seeded from prof + education. |
| Ambitions | `minds` `c["amb"]` ("found"/"join") + `_h("amb")` hash; `notables.gd` ambitions for notables | PARTIAL | Replace the two-valued flag with a ranked goal-weight vector (NI-3). |
| Vulnerabilities / morals / values | `faith` belief intensity; `registry` traits (honest, greedy); `sim/pickpocket`, `theft.gd` act on player only | THIN | NI-2: values vector (honesty, loyalty, piety, ambition, mercy, pride). |
| Needs | `sim/needs.gd` + `npc_need_rules.gd` (food, rest, water, company, faith), `utility_brain` per-person decay, `WorldSim.npc_need_*` arrays; `minds` layer 1 (cash, work, belonging, safety) | FULL near tier, PARTIAL registry tier | Two need sets; unify names in NI-3 (map, do not duplicate). |
| Moods | `population/town_mood.gd` (town flags: REST, FESTIVAL, WAR, MONSTER, SCARCE, MOURN, CURFEW), `living_world/face_state.gd` | PARTIAL: town-level mood and facial state; no per-person mood | NI-4: per-person mood scalar(s) updated from memory events. |
| Physical / psychological states | `sim/injuries.gd` (player), `WorldSim.health` byte, fever/famine multipliers in `emergence`/`minds` | THIN | NI-4: add stress and grief as decaying scalars; reuse `health`. |
| Private goals / plans / secrets | `minds` `g` (current goal), `fo` (founding in progress), `notables` | THIN: goal = enum index; no secret or plan object | NI-3 (plan state), NI-8 (secrets as memory kind with a "hidden" flag). |
| Possessions / debts / property | `sim/property.gd`, `ownership.gd`, `homes.gd` (homes, rent, arrears), `organizations` char purse `cash`, `dynasties` estates, `farming` land | PARTIAL: money and property real; debt only as rent arrears | NI-9 (debt records, small). |
| Relationship axes | `sim/relationships.gd` (NPC to PLAYER opinion with modifier stack), `society.gd` `DIMS` = trust, affection, respect, fear, attraction, loyalty, resentment, familiarity, debt (for ~200 notables), `sim/npc_social_graph.gd` (sparse NPC to NPC edges: familiarity/affinity only, 2,048 edges), `reputation.gd` (multi-axis, town level) | PARTIAL: all eight spec axes exist, only for notables; NPC to NPC is one scalar | NI-5: extend `npc_social_graph` edges with 4 to 8 quantised axes. Do not build a new graph. |
| Memories with witnesses, reliability, emotional weight, uncertainty | `rumours.gd` (claims with told vs true magnitude, confidence 45 to 60 percent for believers, 100 for witness, investigation); `population/witness.gd` + `evidence.gd` (crime witnessing as a task); `registry.remember` (text lines) | PARTIAL: reliability and uncertainty exist as claim confidence; `MEM_MAX = 4`; no emotional weight; witnesses not stored on the memory | NI-4: one memory tuple format shared by rumours and registry. |
| Traits evolve with experience | none (traits static from `traits_for`) | NONE | NI-4: slow trait drift from memories, capped per year. |
| Culture influences, never determines | `faith.etiquette_mod`/`price_mult`/`law_mult` (-0.5..0.5 multipliers) | PARTIAL (pattern is right) | Reuse the same bounded-modifier pattern. |
| Inconsistency, mistakes, changing minds | `minds` noise term `(_roll("gn") - 0.5) * 0.2`; failed attempts back off (`rec["f"]`); `rumours` believers misjudge | PARTIAL (noise only, no deliberate misjudgement) | NI-3: mistake probability from intelligence + stress; commitment with decay so minds can change. |

### Phase 3: autonomous decisions

| Item | Existing code | How fully | Integration point |
|---|---|---|---|
| Utility AI | `population/utility_brain.gd` (1,792 lines): `ACTIONS` table of `[weight, [[input, curve, a, b], ...]]`, 5 response curves, product with compensation factor, `COMMIT_BONUS 1.45`, `KEEP_BONUS 1.15`; `tests/test_utility_brain.gd` | FULL for near tier | Keep. It is the house scorer. |
| Registry-tier decisions | `realm/minds.gd` `_choose` (if-chain over 11 goals; scores `0.15..0.7` plus noise), `GOAL_WAIT` cooldowns, `rec["f"]` failure backoff, chunked day tick | FULL as behaviour, THIN as data: weights are hard-coded in code | NI-3: move the table to data and score with the shared scorer. |
| GOAP / planning | none (`grep -i goap`: only two research notes about the Skelerealms project) | NONE | Section 4. Multi-step needs are today hand-coded sequences (`founding` stages, `advance_founding`). |
| Actions from goals, resources, info, emotion, social expectation, risk, relationships, world | resources (cash, `ties`), info (`news.heard_kinds`, `town_facts`), relationships (opinion via `rumours.opinion`, feuds), world (danger, hunger, fever, boom); emotion NONE; social expectation THIN; risk THIN | PARTIAL | Add emotion (mood) and risk terms as extra considerations. |
| Change jobs, found businesses, join guilds, hire, recruit, marry, relocate, buy property, seek advancement | `minds._act` -> `businesses.hire`, `farming.hire_on`, `businesses.npc_try_found`, `organizations.apply/start_founding`, `homes.marry`, `homes.relocate`, `farming.take_tenancy/buy_direct`, `armies.enlist`, `audiences.file`; `enterprise_people`, `recruitment`, `followers` for the player side | FULL as actions (all through the player's own APIs) | Do not write new actions; new goals only select among these. Missing: buy a non-farm house (`homes` has the API), seek promotion in `career_ladders` (only player), hire others as an NPC employer. |
| Embodied execution | `villager.gd` (2,353 lines), `street_graph.gd`, `smart_objects.gd` (claim slots), `schedule.gd`, `daily_rhythm.gd` | FULL | Registry-tier goals reach bodies only through `schedule` flags and `town_mood`; keep that one-way. |

### Phase 4: living world (events and consequences)

| Item | Existing code | How fully | Integration point |
|---|---|---|---|
| Persistent event architecture | `realm/events.gd` (ring + compaction), `news.gd` (delay by road distance), `rumours.gd`, `scribe.gd`, `sim/echoes.gd` | FULL | Single bus. New causal rules read the ring via `after(n)`. |
| Social life, culture, religion | `faith.gd` (4 faiths, churches as organizations, festivals, priest ladder), `town_mood.gd`, `micro_events.gd`, `living_events.gd` | FULL at town level | Person-level hook: belief already per character. |
| Law, governance | `courts.gd`, `governance.gd`, `stewardship.gd`, `audiences.gd`, `society.gd`, `crime_watch.gd`, `arrest.gd`, `trespass.gd` | FULL | Crimes by NPCs: `minds` has no crime goal (see gaps). |
| Commerce, production, property, food | `sim/economy.gd` + `market.gd` (per-settlement markets), `businesses.gd`, `farming*.gd`, `enterprise*.gd`, `homes.gd`, `ecology.gd`, `seasons.gd` | FULL | Price/famine multipliers already read by `minds` through `emergence.effect()`. |
| Migration | `migration.gd`, `minds._a_move`, `homes.relocate` | FULL | |
| Crime | `society.commit_crime`, `witness.gd`, `evidence.gd`, `dynasties` feuds | PARTIAL (player crimes and feud violence; ordinary NPC theft/need-driven crime missing) | NI-9. |
| Diplomacy, war | `diplomacy.gd`, `factions.gd`, `armies.gd` (1,974 lines), `campaign`, `siege`, `callups` | FULL | |
| Weather, threats, Rifts, Soulbeasts | `emergence.gd` `rift_activation`, `epidemic`; `ecology*.gd`, `monster_ecology.gd`, `actors/soulbeast*.gd`, `town_threat.gd`, MONSTER flag in `schedule` | PARTIAL (Rift is a town-level chain; no per-person fear/trauma) | NI-4/NI-7. |
| Causal rules, delays, imperfect knowledge | `emergence` stages from a day queue, news dated in the future, `rumours` garbling, `minds` known-world layer | FULL | |
| Chain-depth limits, cooldowns, duplicate prevention | `emergence`: `MAX_DEPTH 4`, `COOLDOWN 120` per (kind, place), no repeat of a kind in ancestry, `MAX_LIVE 24`, `MAX_NEW 2`/day, `FX_MAX 160` | FULL | Reuse these constants as the contract for any new chain kind. |
| Resource limits | `agg_*` aggregate households, `CHAR_MAX 1000`, `MIND_MAX 960`, `agg_take` | FULL | |
| The 13 kingdoms; Valencios vs eastern church kingdoms | `politics_data.gd` `GOVERNMENT` lists all 13: caldrenn (Valencios), seirune_isles, ongur_khanate, solmarch, urrokai_clanlands, shenlu_peaks, veylwood, hollowdeep, varska_marches, serathi_lowlands, solkar_dominion, frostcrown_holds, umbrafen_marsh. `faith.kingdom_profile`: Valencios church power 0.25 (secular law, runestone keepers in 14 towns, one Dawn chapel in the capital); church kingdoms solmarch/varska_marches/serathi_lowlands 0.6 to 0.85 (closed border, 6 to 10 percent tithe, stricter fines written into `courts.gd`) | FULL | Any person-level culture/morals work must read these profiles; never write a second kingdom table. |

### Phase 5: three-tier simulation

| Item | Existing code | How fully | Integration point |
|---|---|---|---|
| Tiers with promotion/demotion | Tier A "data": WorldSim packed rows (~20,000). Tier B "registry": `registry.upgrade_row`, `minds.ensure_row` (promote) and `minds._demote` into `agg_*` (demote, 30 days idle, far, untied). Tier C "body": `PopulationLOD` (full model within 45 m, nearest 24; sprites to 220 m, max 140), `cell_streamer` profile "population" (full 45, load 220, hyst 10). `minds.tier_of` near/mid/far with `CADENCE_NEAR 1` / `CADENCE_MID 3` days | FULL | These are exactly the three tiers the spec wants; do not add a fourth. |
| Scheduled decisions | `minds._due` bucket queue, `poke` / `poke_town` pull a day forward; jitter by id | FULL | |
| Budgets, batching | `CHUNK 5`, `CHUNK_UNITS 14` work units (not a clock, deterministic), hub `PUMP_BUDGET_USEC 600`, `WorldSim.BUDGET_US 500`, `Probe` timers, `MAX_SPAWNS_PER_FRAME 1`, `SENSE_INTERVAL_MS 500`, ray budgets | FULL | |
| No runtime LLM | all systems are hashes and tables | FULL | Keep. Text for explanations comes from templates (NI-6). |
| Near-tier decision cadence | `utility_brain` every few tenths of a second per embodied villager (never per frame) | FULL | |

### Phase 6: tests, inspector, profiling

| Item | Existing code | How fully | Integration point |
|---|---|---|---|
| Tests | gdUnit4 in `kingdom/tests/`: `test_lw_minds` (21), `test_lw_rumours` (13), `test_lw_dynasties` (9), `test_lw_personal` (18), `test_lw_faith` (10), `test_lw_emergence` (17), `test_lw_society_soak` (2 game years, no player), `test_utility_brain`, `test_witness`, `test_relationships`, `test_family`, `test_life_courses`, `test_town_schedule` | FULL harness, but no test asserts divergence | NI-1, NI-10. |
| Divergent outcomes for identical situations | none | NONE | NI-1 builds the harness first (it fails for the current code, which is the point). |
| Dev inspector: why an NPC decided; chain tracing | `minds.intent()`, `stats`, `perf()`; `emergence` history lines (60); `DebugMenu` autoload and `debug_draw_3d` addons; `scripts/ui/nameplates.gd`. No decision explanation, no chain trace UI | THIN | NI-6 (data) and NI-11 (UI, needs the editor). |
| Profiling CPU, RAM, scene counts, planning, save size | `scripts/core/perf_probe.gd` (`Probe.t()` / `add`), `perf_overlay.gd`, `tools_qa/cpu_mem/`, `minds.profile` + `_prof` (choose us, per-goal us), `docs/perf/`, `test_lw_society_soak` | PARTIAL: CPU probes real; no save-size or planner-depth gauge | NI-12. |

## 2. What the running Stage 8 already covers (do not duplicate)

Registered in `realm_hub.gd` after `armies`, in this order: `emergence, faith, dynasties, homes, minds, rumours`. All have a section in `LIVING_WORLD_SANDBOX.md` and a `test_lw_*`. File timestamps show several were saved today (minds 13:00, faith 12:58, rumours 12:55, dynasties 12:54, emergence 12:51), so expect churn.

| Spec item | Stage 8 owner | State |
|---|---|---|
| Five decision layers (needs, responsibilities, goals, relationships, known world) | `minds.gd` | Done for registry characters; goals are an 11-entry enum picked by a hard-coded if-chain. Do NOT write a second decision layer; NI-3 refactors the same function. |
| Tiers, due-day queue, chunks, aggregate households, promotion/demotion | `minds.gd` | Done. NPCs far from the player fold back into counts. |
| Life cycle: birthday death check, marriage, children to adults, inheritance | `minds.gd`, `dynasties.gd`, `homes.gd` | Done. |
| Memory and rumour: 4 lines/character, claims travel at 45 units/day, garbled by hash of (claim, town), believers at 45 to 60 percent confidence, investigation corrects and costs the liar reliability | `rumours.gd` | Done for town and character opinion. No emotional weight, no per-memory witnesses list, not read by `_choose` except marriage opinion. |
| Houses, family reputation (`h:<house>` in `reputation.gd`), specialties, feuds, estates, noble mortality driving `succession.gd` | `dynasties.gd` | Done. |
| Homes, rent, arrears, households, school ages, relocation, travel parties `tp:n` | `homes.gd` | Done. |
| Faiths, churches, belief per character, culture tags, festivals, priest ladder, church kingdoms vs Valencios | `faith.gd` | Done. |
| Ten emergent chains with knock-on effects, news delay, loop control | `emergence.gd` | Done at town scale. |
| Docs/perf: `test_lw_society_soak` 2-year headless run | tests | Done. |

New Stage 8 file search (`decision`, `memory`, `rumour`, `dynasty`, `religion`): all hits are the six modules above plus older readers (`news.gd`, `society.gd`, `reputation.gd`, `notables.gd`, `migration.gd`, `armies.gd`, `tactical_ai.gd`, `civilization.gd`). No separate `decision_log`, `inspector`, `personality` or `memory` module was found. If the other agent adds one before NI-2 starts, merge, do not fork.

## 3. Gaps (ranked by value for the owner's goals)

G1. **No shared person record.** Temperament, values, intelligence, skills, culture, languages live nowhere (or as 5 floats in the near tier and 16 words in the registry). Result: the same situation gives different outcomes only through a hash.
G2. **Decisions are not explainable.** `_choose` returns an int; neither engine records per-option scores or inputs, so a dev cannot ask "why".
G3. **Memory has no emotional weight, witnesses or effect.** 4 slots, never fed back into traits, mood or goals.
G4. **No per-person mood / stress / grief.** Mood is town-level.
G5. **Relationships between NPCs are one scalar** (`npc_social_graph.affinity`); the 8 axes exist only for ~200 society notables and for the player.
G6. **No multi-step planning.** Goals are single actions; compound plans (save for land, then buy, then hire) are hard-coded or impossible.
G7. **No mistakes / changed minds beyond noise.** Plans are not committed and re-evaluated.
G8. **Chains never touch individuals.** `emergence` effects change multipliers, not who is afraid, grieving or bankrupt.
G9. **Ordinary NPC crime, debt and secrets missing.**
G10. **No divergence test and no save-size gauge.**
G11. **Stale comment:** `sim/dialogue_runner.gd` says Dialogue Manager is "autoloaded"; `project.godot` shows it is not (not in `[autoload]` and not in `[editor_plugins] enabled`). Dialogue Manager is present at `kingdom/addons/dialogue_manager` but unused by runtime code by design.

## 4. Addon verdict and the one planning approach

Facts:
- **LimboAI** (`kingdom/addons/limboai`, v1.8.1): contains only `LICENSE.md`, `README.md`, `version.txt`, `icons/`, and `bin/*.so` (63 MB). There is no `plugin.cfg`, no `.gdextension`, it is not in `editor_plugins/enabled`, and nothing references `BTPlayer` or `LimboHSM`. It is an inert partial drop. It is a GDExtension (native); that is a build-matrix and mobile-export risk (arm32/arm64/x86 `.so` per platform, no web). Its strengths are behaviour trees and a state machine, which suit the near-tier, body-level behaviour (walk, claim a smart object, react to a scare). That layer already works in `villager.gd` with `smart_objects.gd`, `perception.gd` and `utility_brain.Act`.
- **GOAP addon (pure GDScript, with debugger):** none present. Plans in this game are long-horizon and slow-cadence (days), executed through realm module APIs, not per-frame action sequencing. A generic GOAP addon would plan over world-state flags per agent; the world state here is the realm modules, which no addon can read. An addon's A* over a dictionary of bools would also need to be bridged to every action precondition.
- **Overlap rule:** `utility_brain` (near) and `minds` (registry) already are two goal-selection engines. A third (GOAP or a BT with utility selectors) would be the third overlapping framework, which the rule forbids.

**Verdict:**
- LimboAI: NOT adopted. It does not fill a gap (the body layer works), it overlaps `utility_brain` (BT selectors with utility = same job) and adds a native dependency. Action: remove the dead 63 MB folder from the working tree in a separate cleanup task (owner decision), or keep it ignored; do not enable it.
- Generic GOAP addon: NOT adopted. The gap (G6 multi-step plans) is real but small.
- State-chart addon: NOT adopted. Life states (child, apprentice, adult, retired) are already a table in `minds`/`homes`; a state chart adds nothing the `rec["g"]` goal plus `tp` travel flag does not.
- Dialogue Manager: leave as is (present, unused, by decision recorded in `dialogue_runner.gd`). Fix the stale comment.
- gdUnit4: keep; it is the test harness.

**Recommended ONE planning approach: "utility-selected, bounded GOAP-lite" inside the existing scorer, in pure GDScript, no addon.**
- Keep the response-curve scorer from `utility_brain.gd` as the single scoring engine. Extract it to a static, node-free `scripts/sim/utility_core.gd` (NI-3) so `minds` and `utility_brain` share it. Behaviour of `utility_brain` must not change (its tests are the guard).
- Goals are rows in data (`data/npc/goals.json`): considerations (including personality, values, mood, relationships), and an optional PLAN TEMPLATE: a short list of steps, each `{action, needs (preconditions read from module APIs), effect}`. A plan has max depth 3 steps, costs one "work unit" per step evaluated, is committed with a decaying commitment value (so a mind can change), and is re-scored when a `poke` arrives. No A* search: forward-chaining over a hand-listed template is enough for 11 to 20 goals and is fully deterministic and explainable.
- Execution of each step stays the existing module APIs in `minds._act`.
- The debugger the owner wants is the inspector in NI-6/NI-11, fed by the decision trace.

## 5. Staged work plan NI-1 to NI-12

Each item is small and verifiable. Models: haiku for data and tests, sonnet for systems. Run tests through CI (`ashes-ci`) or the documented cloud-testing commands; do not run the whole suite in the container (shared-memory OOM).

### NI-1. Divergence test harness (red first) [haiku]
- Files: new `kingdom/tests/test_npc_divergence.gd`; helper `kingdom/tests/helpers/npc_fixture.gd` if needed.
- Content: build N=40 `minds` characters via `adopt` with identical age, cash, town, house and no spouse (or identical `ensure_row` rows), differing only in a person seed; present the same town facts (hunger, boom) and assert at least 3 distinct goals chosen and that the identical fixture twice gives identical results (determinism). Expected to fail or be weak on current code; mark the divergence assertion `@warning_ignore` / skipped with a TODO until NI-3. Add the same for `utility_brain.decide` with different `personality` dictionaries (this one passes today, document it).
- Perf budget: test under 2 s.
- Depends: none.

### NI-2. Person record (psychology data) [sonnet; data tables haiku]
- Files: new `kingdom/scripts/realm/persona.gd` (a hub module `persona`, added to `ORDER` after `minds`); `kingdom/data/npc/traits.json`, `values.json`, `cultures.json`, `languages.json`; edit `registry.gd` (only: `traits_for` reads from persona when present); `realm_hub.gd` (register).
- Content: per `ch:n`, one packed row of bytes: temperament (4 bytes: boldness, warmth, discipline, volatility), values (6 bytes: honesty, loyalty, piety, ambition, mercy, pride), intelligence, 4 to 6 skills, culture id, language mask, birth_sid, education prior. Seeded from `hash([SEED, "persona", id])` plus prior from town culture (`faith`), parents (`minds._kids`) at birth (heritable with variance), and education. Store as `PackedByteArray` indexed by a slot map, not Dictionaries. Provide `persona.get(ch)` returning a view; `utility_brain.personality(p)` for embodied villagers delegates to it when the villager's row has a `ch` (else the old hash).
- Tests: `test_npc_persona.gd` (determinism, bounds 0..255, same culture different people differ, culture shifts the mean but ranges overlap, save/load round trip, size <= 40 bytes/char).
- Perf/save budget: 40 B x 1,000 chars = 40 KB raw; no per-frame work; creation O(1).

### NI-3. Shared scorer + data-driven goals + decision trace [sonnet]
- Files: new `kingdom/scripts/sim/utility_core.gd` (static), `kingdom/data/npc/goals.json`; edit `utility_brain.gd` (call the core; keep its const table), `minds.gd` (`_choose` reads goals.json; persona weights as considerations; keep `GOAL_WAIT`, `cd`, failure backoff; keep +-noise but make amplitude depend on persona volatility).
- Content: the decision returns `{goal, scores: [[goal, score, top_considerations]...]}` kept in a ring of the last K decisions per tier-near character only (K=3, 32 B each), not for far characters (they keep only the last result). Add emotion (mood) and risk considerations as inputs (default neutral until NI-4).
- Tests: extend `test_lw_minds` unchanged (must still pass); `test_utility_brain` unchanged (must still pass); NI-1 divergence test now enabled and green; new `test_npc_decision_trace.gd`.
- Perf budget: `minds` `CHUNK_UNITS` stays 14; `_choose` total <= 1.3x its current microseconds (compare via `minds.profile` `choose`/`n`); no allocation per option beyond one small Array in the near tier.
- Depends: NI-2.

### NI-4. Memory, mood, trait drift [sonnet]
- Files: new `kingdom/scripts/realm/psyche.gd` (hub module after `rumours`); edit `rumours.gd` (memory tuple gets fields: emotional weight, witness count, source reliability; `MEM_MAX` 4 to 6; keep claim logic untouched); edit `registry.gd` `remember` to delegate (stop having a third memory store).
- Content: per character mood (valence, stress, grief; 3 bytes) updated from events the person witnessed or heard (EventRecord `after(n)` already used by `rumours`); mood decays toward a baseline set by temperament; trait drift: values move at most 3 points per game year, only when a memory with high weight and matching theme exists. Mistake model: probability from `(1 - intelligence) * stress`, effect = scoring a candidate with a perception error, never an illegal action.
- Tests: `test_npc_psyche.gd` (decay, bounds, drift cap, determinism, a violent witnessed crime lowers a high-mercy person's mood more than a low-mercy person's).
- Perf: weekly decay for mid/far characters, daily for near; 5 B/char saved plus memory tuples (<= 6 x 8 B).
- Depends: NI-2.

### NI-5. NPC to NPC relationship axes [sonnet]
- Files: edit `scripts/sim/npc_social_graph.gd` (edges gain trust, resentment, respect, affection as signed bytes; keep `MAX_EDGES 2048`, `VERSION` bump with migration), plus a thin adapter `scripts/realm/bonds.gd` (not a new store) that maps `minds`/`dynasties`/`rumours` events to edge changes; `minds` marriage choice reads the axes.
- Tests: `test_npc_bonds.gd` (a betrayal event moves trust down more for a high-honesty person; edge cap respected; old saves load).
- Perf/save: 2,048 edges x ~16 B = 32 KB; update only on events.
- Depends: NI-2, NI-4.

### NI-6. Decision and causal trace service (data only) [sonnet]
- Files: new `kingdom/scripts/sim/trace.gd` (static ring, off in release unless `OS.is_debug_build()`); edit `emergence.gd` to stamp each effect with `(chain id, cause event n)`; edit `events.gd` only to carry an optional `cause` event number if not already there (the `cause` string exists; add a numeric parent).
- Content: `trace.why(ch)` returns text built from templates (no LLM): chosen goal, top 3 considerations with values, persona terms that mattered, memory lines cited. `trace.chain(event_n)` walks parents up to depth 8.
- Tests: `test_npc_trace.gd` (why() mentions the top consideration; chain walk stops at depth cap; no cycles).
- Perf: zero cost when off; when on, near tier only.
- Depends: NI-3.

### NI-7. Chain-to-person effects (bounded) [sonnet]
- Files: edit `emergence.gd` (each stage may call `psyche.apply(sid, kind, intensity)` for the town's characters via `minds.witnesses_at`/`believers_at`, 3 to 12 characters, not all); edit `faith.gd` (festival boosts mood, church shelter reduces stress).
- Rules (the contract the owner asked for): reuse `MAX_DEPTH 4`, `COOLDOWN 120`, `MAX_LIVE 24`, `MAX_NEW 2`, no kind repeated in ancestry; add a person-level cooldown (a character cannot take the same mood effect from the same chain twice) and a global cap on person effects per day (e.g. 40).
- Tests: extend `test_lw_emergence` (existing 17 still pass); new `test_npc_chain_effects.gd` (a harvest failure raises stress in the town, a priest-run shelter lowers it, no loop in a 5-year headless run).
- Depends: NI-4.

### NI-8. GOAP-lite plan templates [sonnet]
- Files: `data/npc/plans.json` (templates), `scripts/sim/plan_core.gd` (static forward-chain, depth <= 3, work-unit cost), edit `minds.gd` (`rec["pl"]` plan id + step, commitment decay, `poke` can break it).
- First templates (all through existing APIs): save, then rent land, then hire a farmhand; join an organization, then seek a seat, then petition for a charter; marry, then relocate to the spouse's town, then buy a home. Secrets: a plan may be tagged hidden, kept as a memory kind not shared in `rumours` until a witness reports it.
- Tests: `test_npc_plans.gd` (depth cap, cooldown, a failed step re-plans or aborts, two personalities choose different plans from the same state, determinism).
- Perf budget: planning only on a character's due day; step evaluation counts as work units inside `CHUNK_UNITS 14`; planner share <= 15 percent of the minds day tick.
- Depends: NI-3, NI-4.

### NI-9. Debt, ordinary crime, advancement [sonnet]
- Files: edit `homes.gd` (arrears already exist; expose as debt), new small `scripts/realm/debts.gd` only if `homes` and `organizations` cannot hold it; edit `minds.gd` (goal "steal" / "borrow" for high-need low-honesty people through `society.commit_crime` with witnesses; goal "promotion" for `career_ladders`); verify `courts.gd` and `faith.law_mult` apply per kingdom (Valencios secular vs church kingdoms stricter fines).
- Tests: `test_npc_crime_debt.gd` (starving low-honesty person steals more often than a high-honesty one; church kingdom penalty > Valencios; no crime spiral: per-town cap per week).
- Depends: NI-3, NI-8.

### NI-10. Soak and divergence at scale [haiku]
- Files: extend `tests/test_lw_society_soak.gd`; new `tests/test_npc_soak_divergence.gd`.
- Content: 2 game years, 300 characters, three towns; asserts: divergence (distribution of goals/professions across personas), stability (population within +-30 percent, price indices bounded, no goal flip-flop faster than `GOAL_WAIT`), no event storm (events/day below the ring's compaction rate), determinism across two runs.
- Perf: runs on CI only (headless, long).

### NI-11. Dev inspector UI [sonnet; verification on local PC]
- Files: new `kingdom/scripts/ui/dev/npc_inspector.gd` (+ a small scene), registered with the existing `DebugMenu` (`addons/debug_menu`); draws a selected NPC's persona, mood, last K decisions with considerations, memories, relationship edges, current plan, and a chain tree; `debug_draw_3d` for the selected NPC's path and perceived hazards.
- Tests: logic in `trace.gd` is already tested (NI-6); UI gets a smoke test (builds, no errors) only.
- Perf: only exists in debug builds; refresh at 4 Hz for one selected NPC.
- Depends: NI-6.

### NI-12. Profiling gauges and budgets [haiku]
- Files: extend `minds.perf()`, `scripts/core/perf_probe.gd` keys (`npc.persona`, `npc.psyche`, `npc.plan`), `tools_qa/cpu_mem/` runner; new `docs/perf/NPC_INTELLIGENCE_BUDGET.md` report (generated, not hand-written numbers).
- Gauges: CPU per module per day tick, RAM (character count x record size), scene counts (nodes under PopulationLOD), planner depth histogram, `JSON.stringify(hub.serialize()).length` per module for save size.
- Budget gates (fail the CI job if exceeded): per-day mind tick worst chunk <= 2.0 ms desktop (current design: CHUNK 5 or 14 units), pump job <= `PUMP_BUDGET_USEC 600`, total NPC additions to the save <= 250 KB at 1,000 characters (so the whole save stays inside the 2.5 MB raw limit the Living World doc proposes), scene nodes unchanged (this work adds no nodes).

## 6. Work that needs a graphical editor or a GPU (for the local PC)

- NI-11 inspector UI: layout, theme and readability on a real viewport; confirm `DebugMenu` integration; screenshot review (`ashes-visual-qa`).
- Visual confirmation that persona differences read in the street: two NPCs with different temperaments in the same scene (nameplate, bark, face state through `living_world/face_state.gd`, `npc_face_card.gd`). Needs rendering (xvfb in the cloud OOMs).
- Mood-driven animation or posture blends (`crowd_anim_lod.gd`, `vat_crowd.gd`, `talk_pose.gd`): the data side is cloud work, the look is local.
- Real-device profiling on the Samsung S22 (Perfetto/AGI per `ashes-external-tools`): body-layer cost with 24 full models plus per-NPC mood reads.
- Decision on the inert `addons/limboai` folder: removing 63 MB of `.so` files and testing that an Android export still builds is a local export check.
- Optional: authoring `.dialogue` content for personality-flavoured lines, only if the owner wants Dialogue Manager enabled (needs the Godot editor import). The current JSON runner can serve personas without it.

## 7. Performance risks

1. **Save size.** Stage 8 already stores ~60 B/character in registry plus mind rows (15 fields) plus memories. If persona, psyche and plans are stored as Dictionaries or strings, 1,000 characters x ~400 B = 400 KB extra. Mitigation: packed bytes, quantised axes, budget gate in NI-12.
2. **Dictionary churn in `_choose`.** `minds` builds facts and compares floats per character per day; moving to a data table must not add per-option allocations. Gate: `minds.profile` before/after.
3. **Memory growth with mid/far characters.** The decision trace ring must exist only for near-tier characters; far ones keep one result.
4. **Event storms.** Chain-to-person effects can multiply (`emergence` MAX_NEW 2/day x characters). Cap person effects per day (NI-7) and sample 3 to 12 characters per chain, never the whole town.
5. **Hub order.** Appending modules after `minds`/`rumours` means they tick last in the same day chunk; if all day ticks land on 06:00 the pump (600 us budget) delays them across frames. Keep new modules chunked (`tick_day_chunks`) or weekly.
6. **Determinism.** New code must use the same `hash([SEED, tag, day, id])` rolls and never iterate Dictionaries unsorted when order affects results (minds sorts ids on load; follow that).
7. **Two sources of truth.** Persona vs `registry.traits_for` vs `utility_brain.personality`: NI-2 must make persona authoritative and the others views, or divergence tests will pass for the wrong reason.
8. **Near-tier cost.** `utility_brain` scores 28 acts x ~5 considerations per decision per embodied villager (up to 24 full + the sensing budgets). Adding mood/values considerations must stay on the same table with precomputed inputs; no new raycasts.
9. **Catch-up.** `catch_up(days)` must stay O(entities): mood decay and trait drift need closed forms (exponential decay), not day loops.
10. **Inert LimboAI folder.** 63 MB of binaries in the repo slows clones and CI checkout; remove or ignore after the owner confirms.

## 8. Summary of the order of work

NI-1 (test, red) -> NI-2 (persona) -> NI-3 (shared scorer, goals data, trace; turns NI-1 green) -> NI-4 (memory/mood) -> NI-5 (bonds) -> NI-6 (trace) -> NI-7 (chains to people) -> NI-8 (GOAP-lite) -> NI-9 (crime, debt) -> NI-10 (soak) -> NI-11 (inspector UI, local PC) -> NI-12 (gauges). NI-1, NI-10 and NI-12 are haiku-sized; NI-2 data tables are haiku, the rest sonnet. Each stage lands on its own and leaves the existing 90-odd Stage 8 tests green.
