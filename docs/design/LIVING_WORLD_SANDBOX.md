# Living World and Medieval Sandbox Expansion

Owner master spec, condensed, mapped onto the real code, and cut into work packages. Delivered 2026-10-21. It extends `LIVING_WORLD.md` (L§ numbers), `CIVILIZATION.md` (CIV-A..D), `RETINUE_SETTLEMENT_ASCENSION.md`, `REALM_WAR_SETTLEMENT.md`, `WAR_COMMAND_RULEBOOK.md` and `SIM_HIERARCHY.md`. It does not replace them.

**Platform decision (this doc):** the game is PC-first. The phone port is kept for later, so nothing here may hard-require a PC, but PC budgets lead. Performance still matters: every package below carries a tick and save budget. **Owner decision kept:** the player-settlement cap stays at **3** (`BuildKit.MAX_GRIDS`, `docs/regions/OWNER_DECISIONS.md`). Holdings taken by conquest or inheritance do not count toward it.

**Audit method and honesty note.** The gap map is built from a header-level read of each file named in the task (doc comments, public function lists, constants), the three design docs, and greps for key verbs. I did not read every function body. "Done" means the module exists, is registered or used, and covers the spec rule in kind; it does not mean the spec's scale is met. Test counts were not re-run (no Godot run in this task).

---

## Part A. The spec, condensed (all 20 sections, every rule and system name kept)

### 1. Fundamental rules
1. **Careers are not locked.** A character can change career at any time; skills, reputation, property and relationships carry over.
2. **Joining and founding are equal routes.** Every profession and organization can be entered by joining an existing one or by starting one independently. Neither is a lesser path.
3. **Four separate axes:** **membership** (belongs to an organization), **employment** (works for someone and is paid), **loyalty** (a feeling, per person), **ownership** (property and shares). None implies another. A member can be disloyal; an employee is not a member; an owner may employ their own rival.
4. **Authority has limits.** A rank grants specific rights (command, hire, tax, judge), never unlimited power. Orders can be refused, and refusal has consequences.
5. **The world runs without the player.** NPCs found, trade, marry, fight and fail on their own. The player can speed up, redirect or ruin a process, never start it alone.

### 2. Universal recruitment
- **Every recruit is a real character** (a persistent person with a life, not a counter).
- Routes: **offers**, **notices** (boards, criers), **apprenticeships**, **migration** (people arrive looking for work), and **absorbing organizations** (merge a band, guild or company into yours).
- **Recruits keep agency:** they can refuse, negotiate terms, quit, disagree, leave with their skills.
- **Organization members versus personal followers:** members belong to the organization and follow its rank rules; personal followers follow the person and leave or stay with them.
- **Delegated command chains:** the leader commands officers, who command their own people. Orders pass down; results and reports pass up.

### 3. Farming as a full career
- Ladder: **farmhand → tenant → owner → estate.**
- **Physical, expandable farms** (real fields on the ground that grow by building out).
- **Per-field soil**, **seasons**, **rotation** and **pests**.
- **Livestock.**
- **Workers** (hire, assign, pay).
- **Selling and relocating** a farm.
- **A political route:** estate owners gain seats, votes and a place in the nobility.

### 4. Every other profession (join route and independent route each)
Merchant, soldier, smith, builder, miner, hunter, healer, innkeeper, adventurer, assassin, scholar, priest, administrator, **plus 20 more** (the owner's list is open-ended; the work packages below treat "profession" as data in one table, see LW-4.1). Each profession has: a join route, an independent route, a skill ladder, and income that does not need a quest.

### 5. Organizations
- **Types** (guild, company, band, order, house, church branch, school, militia, court, council, and others).
- **Rank ladders** per organization, each rank with defined rights.
- **Recruit rights:** which ranks may recruit, dismiss and promote.
- **Founding stages** (idea → members → charter/recognition → premises → standing).
- **Internal mechanics:** treasury, dues, wages, internal politics, schisms.
- **Growth ladder: Party → Clan → Legion → Great House.**

### 6. Settlement founding
- **Site evaluation** (water, soil, defence, roads, resources, danger).
- **Legal land status** (owned, claimed, crown, wild, contested). **Illegal-build escalation:** building without right draws warnings, fines, demolition, then force.
- **Founding stages**, **modular construction**, **strongholds**, **scale classes**, **districts**.
- **Residents with their own lives**, **migration**, **appointed officials**, **emergent problems**.
- **The hidden valley** (a secret, hard-to-reach site with its own rules).

### 7. Nobility
- Hierarchy; **petitions and audiences in 8 steps** (request → clerk → queue → chamberlain → hearing → ruling → record → consequence); **access to the king** by rank and favour.
- **Multi-axis reputation** (not one number).
- **Marriage and inheritance**; **running a territory**.

### 8. Kingdoms
- **Layered territory maps**; **visibility of growth** (a rising independent faction shows on the map); **diplomacy**; **reactions to independent factions** (ignore, tax, recognize, suppress); **capturing territory**.

### 9. Military forces
- **Types**; **recruiting and training**; **officers**; **command from third person** with **couriers** and **fog of war**; **logistics cost**; **settlement defence**.

### 10. Economy
- **Production chains**; **prices**; **ownership records**; **business accounts**; **remote management via reports** (you run a far business from reports, not presence).

### 11. Smart NPCs
- **5 decision layers**; **NPC life arcs**; **NPCs founding organizations**; **competition**; **autonomy**; **memory and rumour**.

### 12. Personal life
- **Homes**, **families**, **education ages**, **travel and relocation**.

### 13. Justice
- **Laws per kingdom**; **investigation and evidence**; **courts**; **inequality and liberation**.

### 14. Religion and culture
### 15. Emergent events
### 16. Example paths A to E (worked player stories; used as acceptance scenarios, see Part D)

### 17. Godot architecture
- **Shared entities:** Character, Household, Organization, Contract, Property, Building, Business, Settlement, Territory, Army, FactionRelationship, EventRecord, TravelParty.
- **3-tier simulation** (near / mid / far).
- **Universal action framework** (one action record used by player and NPCs).
- **Manual / delegated / autonomous modes** per organization or business.
- **Save integrity** (versioned, checksummed, migratable, bounded growth).

### 18. Progressive disclosure UI
Systems appear when the player first touches them; defaults are simple; detail is one tap deeper.

### 19. Stages
1 Living Thornfield, 2 Recruitment, 3 Property and farming, 4 Guilds and businesses, 5 Settlement founding, 6 Politics and territory, 7 Military, 8 Advanced society.

### 20. Final rules
The section 1 rules are the test for every feature; nothing ships that locks a career, forces a route, merges the four axes, grants unlimited authority, or needs the player present to progress.

---

## Part B. Gap map (spec section → existing code)

Legend: **DONE** = covers the rule in kind. **PARTIAL** = real foundation, spec rule missing. **MISSING** = no code.

### Existing-code anchors (what is already real)
- **Hub and tiers:** `kingdom/scripts/realm/realm_hub.gd` registers 29 modules (followers, camps, civilization, migration, settlements, land, factions, strongholds, campaign, city_life, society, governance, notables, news, exploration, power_paths, education, cultivation, household, callups, work, scribe, soldier, trades, enterprise, construction, towers, ecology, build_kit). `PUMP_BUDGET_USEC = 600`; hour/day/week jobs queued, one module per frame; `catch_up(days, ctx)` closed-form (`realm_module.gd`, `SIM_HIERARCHY.md`).
- **People:** `kingdom/autoload/world_sim.gd` (about 10,000 people as packed arrays, int index ids, sliced rows, dead list, heir_of, needs, `people_near`). `scripts/sim/life_courses.gd` (about 150 notable residents with real lives, int ids). `realm/notables.gd` (about 60 agents, string ids, families, orgs founded by NPCs). `population/*` (near bodies: utility_brain, villager, schedule, perception, witness, evidence, crime_watch; LOD in `population_lod.gd`).
- **Save:** `scripts/sim/save_manager.gd` schema 3, atomic writes, md5 checksum, zstd, 3 slots + 3 autosaves + quicksave, dirty-container snapshot (`save_containers.gd`).

### §1 Fundamental rules - PARTIAL
- Career switching exists: `sim/careers.gd` (vacancies by seat), `sim/career_ladders.gd` (ranks need mastery/rep/time/property/money/seat/sponsorship), `realm/career_trades.gd` (join/offers, four trades), `data/careers/ladders.json`. Four axes are not separated: membership and employment are both a "seat" in `careers.gd`; loyalty lives in `followers.gd` and `relationships.gd`; ownership in `sim/ownership.gd` (owner is a plain string) and `property.gd`. No code expresses "authority has limits" as rights per rank.
- World runs without player: DONE in kind (`civilization.gd`, `migration.gd`, `notables.gd`, `governance.gd`, `ecology.gd`, `news.gd`; CIV-A..C). **Gap:** the four axes as separate data, and rank-bound rights.

### §2 Universal recruitment - PARTIAL
- Followers with agency: `realm/followers.gd` (`recruit`, `hire`, `hire_temp`, `make_permanent`, `summon` with travel delay, `decide` with disputes, `assign_post`, wages, party). Troop recruit pools gated by relation: `realm/enterprise_people.gd` (`recruit_pool`, `recruit`, mercenaries, vassalage). Notable leaders: `notables.gd recruit_leader`. Offers: `callups.gd offers/offer`, `scribe.gd`, `career_trades.gd offers`. Builders: `construction.gd hire_builder`.
- **Missing:** troops in `enterprise_people.gd` are counts, not persistent characters (recruit = number); notices/boards as a generic recruitment channel; apprenticeships (only academies in `education.gd`); absorbing organizations; org member vs personal follower distinction; delegated command chains with refusal (campaign has officers, see §9).

### §3 Farming - PARTIAL (thin)
- `sim/homestead.gd` (880 lines): three fixed 11x11-cell plots outside Ashford, `soil_quality(plot)`, `plant/harvest` of wheat and cabbage, `hire(plot, name, wage, skill)`. UI: `scripts/ui/farm_ledger.gd`; view: `world/homestead_view.gd`; `world/farm_work_spot.gd`; animals ambient: `world/town_kit/town_livestock.gd`. Seasons: `sim/seasons.gd` (4x28 days). Property: `sim/property.gd` (rent/buy/sell lots).
- **Missing:** farmhand → tenant → owner → estate ladder; per-field soil state, rotation, pests; livestock as owned production; selling/relocating a farm; expandable farm beyond three plots; political route.

### §4 Professions - PARTIAL
- `career_trades.gd` ladders for four working trades; `sim/soldier_career.gd` + `realm/soldier.gd` (recruit → lieutenant, Scribe depth), `realm/scribe.gd`, `sim/adventurer_guild.gd` (join, commission board), `realm/enterprise*.gd` (merchant/caravan/workshop guild), `realm/work.gd` + `work_jobs.gd` (shift mechanics per job), `city_life.gd` (jobs, guilds), `sim/crafting.gd` (687 recipes, `items_db`), `construction.gd` (builder skill), `sim/monster_ecology.gd` (hunting).
- **Missing:** independent routes for most; miner, healer, innkeeper, assassin, priest, administrator, hunter as ladders; the "20 more" as data. No single profession table.

### §5 Organizations - PARTIAL
- `city_life.gd` (`join_guild`, `found_guild`), `enterprise.gd` (workshop guild, clan renown/influence, fiefs), `governance.gd` (leaders, succession, councils), `notables.gd` (NPC-founded companies, guilds, orders, bands, `orgs`), `education.gd` (clubs, factions, schools), `factions.gd` (houses, Church, sects), `sim/military.gd` (rank ladder, divisions), `followers.gd` party.
- **Missing:** one Organization record with type, rank-rights table, recruit rights, founding stages, treasury, schism; Party → Clan → Legion → Great House growth ladder (enterprise has clan tiers only).

### §6 Settlement founding - PARTIAL (strong build, weak law)
- Found: `realm/camps.gd found_camp`, `civilization.gd found_place` (tier camp → outpost → village → town → city → trade hub or ruin, pressure, hysteresis), `migration.gd` (waves, refugee camp), `settlements.gd` (identity drift, supply chains, emergencies, regrowth), `strongholds.gd`, `realm/land_claim.gd` (distance, water, road rules only), `construction.gd` (staged, workers, materials), `build_kit.gd` (modular snap kit, support, 3-grid cap, 2 m cell, 16 bytes per piece save, `PIECE_CAP` 1400/1800/2200), `world/hidden_valley.gd`, `world/city_planner.gd`, `world/districts.gd`, `construction_nav.gd`.
- **Missing:** legal land status ladder (header of `land_claim.gd` says charter/ward claim/owner stones not implemented); illegal-build escalation; site evaluation score shown to player (camps score terrain internally); appointed officials for player settlements (governance has leaders but not player appointment UI); scale classes beyond tier names; hidden valley rules beyond placement.

### §7 Nobility - PARTIAL
- `sim/nobility.gd` (houses, land owners), `sim/lordship.gd` (treasury, taxes, infra, militia), `sim/titles.gd`, `sim/family.gd` (courtship, marriage, heirs), `realm/factions.gd`, `realm/land.gd` (deeds, loyalty, rebellion), `ui/lord_council.gd`, `governance.gd` councils, `news.gd` (political marriages, delegations).
- **Missing:** 8-step petition/audience pipeline; access-to-king gating; multi-axis reputation per bloc (governance has public opinion per bloc; `relationships.gd` has per-NPC and faction numbers, not multi-axis per noble); inheritance beyond the player's own line (`heir_of` exists in world_sim).

### §8 Kingdoms - PARTIAL
- `data/world/nations.json`, `factions.gd`, `sim/war_sim.gd` (Caldrenn vs two neighbours), `realm/land.gd` (conquest is not ownership), `campaign.gd` (4,334 lines: armies on the road graph, intel ageing), `siege.gd`, `war_influence.gd`, `news.gd`.
- **Missing:** layered territory map data model (Territory as polygons/cells with owners); growth visibility on the map; a kingdom's reaction table to independent factions; diplomacy beyond war and marriages (13 kingdoms are frozen by `FOUNDATION_PLAN.md`; unfreeze needed at Stage 6).

### §9 Military - PARTIAL (strong)
- `campaign.gd` (armies, couriers, depots, covert ops, engagements), `tactical.gd`/`tactical_ai.gd` (grid battle, 10 s step), `war_units.gd`, `siege.gd`, `soldier.gd`, `sim/soldier_squad.gd`, `callups.gd`, `enterprise_people.gd` (recruit pools, mercenaries), `war_advisors.gd`, `WAR_COMMAND_RULEBOOK.md`.
- **Missing:** third-person command of a unit in the field (campaign is map-level); fog of war on the player's own units' view in the field; logistics cost surfaced as upkeep per unit (campaign has supply/attrition, check mapping); settlement defence for player-founded settlements (strongholds/towers exist).

### §10 Economy - PARTIAL (strong prices, weak ownership)
- `sim/economy.gd` (one RAMarket per settlement, hourly drift, events), `sim/market.gd`, `enterprise_core.gd` (ledger, per-settlement prices from supply chains, price intel, bulk trading, routes), `settlements.gd` (supply chains), `sim/caravans.gd`, `ownership.gd` (items/containers), `property.gd`, `work_jobs.gd`.
- **Missing:** a general Business record with account book and ownership shares; production chains owned by NPCs/players as Businesses (chains are per settlement); remote management by reports (enterprise has hired leader `hire_leader` and informants, but no report object).

### §11 Smart NPCs - PARTIAL
- Near: `population/utility_brain.gd` (utility AI), `schedule.gd`, `perception.gd`, `daily_rhythm.gd`. Far: `life_courses.gd` (life arcs), `notables.gd` (ambitions, found orgs), `society.gd` (about 200 full records, memory, goals, rumours), `news.gd` (rumours sharpen), `sim/npc_social_graph.gd` (bounded ties), `sim/relationships.gd`.
- **Missing:** the named 5 decision layers as an explicit pipeline (needs / routine / goals / social / strategic exist as separate code, not one contract); NPC competition over the same contract or customer.

### §12 Personal life - PARTIAL
- `sim/property.gd` (rent, buy, sell, inn room), `sim/homestead.gd`, `realm/household.gd` (1,584 lines, family economy), `sim/family.gd`, `realm/education.gd` (2,750 lines, academies, ages), `data/childhood`, `world/travel_rules.gd`, fast-travel coach.
- **Missing:** relocation as a first-class action (move household to another settlement); homes for NPCs as owned/rented Property (town lots exist: `world/town_kit/town_lots.gd`).

### §13 Justice - PARTIAL
- `population/witness.gd`, `evidence.gd`, `crime_watch.gd`, `search.gd`, `trespass.gd`, `sim/theft.gd`, `sim/pickpocket.gd`, `sim/arrest.gd` (pay/jail), `society.gd` (bounties, evidence ageing), `governance.gd law(sid, key)` (regional laws).
- **Missing:** laws per kingdom (laws per settlement exist); courts and trial flow; investigation by NPC officers as a case record; inequality/liberation mechanics (slavery, serfdom) - none.

### §14 Religion and culture - PARTIAL
- `factions.gd` (Church influence, sects), `data/world/cultures.json`, `town_identity.json`, `sects.json`, `migration.gd` (culture shares per district), `news.gd`. No priest career, no temples as buildings with function, no festivals (CIV-D presentation is unbuilt).

### §15 Emergent events - PARTIAL
- `settlements.gd` emergencies, `callups.gd`, `strongholds.gd` raids, `ecology.gd`, `population/micro_events.gd`, `radiant_quests.gd`, `scouts.gd`, `news.gd`. **Missing:** one EventRecord log that all systems write to (see Part C).

### §16 Example paths A to E - MISSING as scenarios. Turned into acceptance scenarios in Part D.

### §17 Architecture - PARTIAL
- Tiering exists (`SIM_HIERARCHY.md` tiers 0 to 4). Universal action framework: MISSING (each system has its own verbs). Manual/delegated/autonomous modes: partial (`enterprise.hire_leader`, `lordship`, player-led settlements run themselves in `civilization`). Save integrity: DONE for the existing save (schema 3, checksum), growth limits partial (comment in CIVILIZATION.md: 2-year save under 1 MB).

### §18 Progressive disclosure UI - PARTIAL
- `scripts/ui/` has career_screen, family_screen, farm_ledger, lord_council, build_menu, construction_panel, chronicle_screen, hud_mode. No organization/business/territory screens; no disclosure rule.

### §19 Stages / §20 Final rules - covered by Part D and this section's checklist.

---

## Part C. Shared entity plan (§17.1)

### Identity rules (apply to all)
- **Persistent ID format:** a string `"<prefix>:<n>"` where `n` is a monotonically increasing integer per prefix, never reused, stored in one new counter dict `ids` in a new module `realm/registry.gd`. Prefixes: `ch`, `hh`, `org`, `ct`, `pr`, `bl`, `bz`, `st`, `tr`, `ar`, `fr`, `ev`, `tp`.
- **Bridge, do not rewrite.** Existing ids stay valid (WorldSim int index, life_courses int id, notables string, followers `fid`, settlement int `sid`, civilization place string, camps int, construction site int, build_kit grid). `registry.gd` holds a two-way map `legacy_key -> persistent id` (for example `"ws:1234" -> "ch:1234"`, `"nt:n17" -> "ch:9001"`). A Character that is only a WorldSim row is created lazily when something references it (hire, marry, accuse, found).
- **Save impact rule:** each entity adds at most the byte budget below at the stated population; 1,000 simulated NPCs must stay under the save limits in Part E.

| §17.1 entity | Maps onto today | What to add | ID | Save impact |
|---|---|---|---|---|
| **Character** | `world_sim.gd` packed rows (about 10k, cheap); `life_courses.gd` (about 150 with biography); `notables.gd` (about 60); `society.gd` (about 200 full records); `followers.gd` followers; player `Game` state | A `Character` view over those four sources (`realm/registry.gd`), plus an "upgrade" path: row → full record when recruited, named, or hired. Fields added only on upgrade: `traits`, `skills`, `loyalty{}`, `memory[]` (bounded 12) | `ch:n`, alias map from legacy ids | Row stays 0 bytes extra. Full record about 400 B. Cap 1,000 full records = 400 KB raw (about 80 KB zstd) |
| **Household** | `realm/household.gd` (player's family economy), `sim/family.gd`, `world_sim` home index | Generic household: `{id, members[], home: Property id, purse, food}`; far households are aggregates (count, wealth, food) per settlement | `hh:n` | Aggregate 24 B each; full households only for upgraded characters |
| **Organization** | `city_life.gd` guilds, `notables.gd orgs`, `enterprise` clan/workshop guild, `education` clubs/factions, `governance` orders, `factions` houses, `careers.gd` orgs | One record: `{id, type, name, leader, members[{ch, rank, since}], ranks[{name, rights[]}], treasury, charter, stage, parent}` and a **rights table** (data JSON `data/living_world/org_types.json`). Existing modules keep their state and expose an adapter that yields this record | `org:n` | About 150 B + 24 B per member. Cap 400 orgs and 4,000 member rows ≈ 160 KB raw |
| **Contract** | `enterprise_people.gd` mercenary contracts, `callups.gd` offers, `followers.gd recruit(terms)`, `property.gd` leases, `caravans.gd` hires, `construction.gd` hired builders, `radiant_quests` | `Contract {id, kind, parties[], terms{}, start, end, status}` as the single record; modules write one and keep their own derived state | `ct:n` | 60 B each. Prune expired after 30 days into a count |
| **Property** | `property.gd` lots (rent/buy/sell), `homestead.gd` plots, `land.gd` deeds, `ownership.gd` owner strings, `build_kit.gd` grids | Unify under `Property {id, kind, where, owner(ch/org/bz), tenant, legal_status}`; `legal_status` is the §6 ladder (owned, leased, claimed, crown, wild, contested, illegal) | `pr:n` | 48 B each; lots already deterministic from plan, store only changed ones |
| **Building** | `construction.gd` sites + staged structures, `build_kit.gd` pieces (16 B each, up to 2,200 per grid), `camps.gd` structures with roles, `town_kit` lots | Building record points to a Property and holds function (house, smithy, farm, barracks, temple) and condition; pieces stay packed in build_kit | `bl:n` | 40 B each; kit pieces unchanged |
| **Business** | `enterprise_core.gd` ledger/workshops, `economy.gd` markets, `city_life.gd` jobs, `homestead.gd` farm | `Business {id, owner, building, kind, account{in,out,balance}, staff[], mode(manual/delegated/autonomous), report_log[]}`; reports ring buffer 8 | `bz:n` | About 200 B; 500 businesses = 100 KB raw |
| **Settlement** | `settlements.gd` (int sid), `civilization.gd` (place ids, tier), `camps.gd`, `migration.gd`, `WorldGen.settlements` | Keep int `sid` as the key. Add `st:n` alias for dynamic ones (camps/founded). Add `scale_class`, `legal_status`, `officials[]` fields on the existing civilization place record | `st:n` | Existing; +60 B each |
| **Territory** | `land.gd` per-region loyalty/deeds, `factions.gd`, `nobility.gd` house land, `strongholds.gd` | New: `Territory {id, owner, layer, cells/bounds, parent}` stored as chunk-grid ownership (one byte per 256 m cell) in layers (kingdom, county, holding, claim) | `tr:n` | 12 km world / 256 m ≈ 2,200 cells per layer; 4 layers ≈ 9 KB raw, tiny |
| **Army** | `campaign.gd` armies (dict on road graph), `soldier_squad.gd`, `enterprise_people.gd` troops, `war_units.gd` | Army links `org` + commander `ch` + troop roster as aggregated counts by unit kind plus a few named officers (full Characters). Do NOT make every soldier a Character unless recruited by the player | `ar:n` | 120 B + 8 B per unit stack |
| **FactionRelationship** | `factions.gd` relations, `relationships.gd` faction standing, `war_sim.gd` | Normalize to a sparse pair table `{a,b,axes{trust,fear,trade,kin},treaty}` with sparse storage (only non-default) | `fr` = pair key `a|b` | 40 B per non-default pair; cap 600 |
| **EventRecord** | `news.gd` rumours/news, `society.gd` memory/evidence, `scribe.gd`, `chronicle_screen.gd`, settlement emergencies, `war_sim` log | One append-only ring `EventRecord {id, day, kind, where, actors[ch/org], cause, text_key, weight}`. Systems write; news, rumour, memory, chronicle and justice read | `ev:n` | Ring of 2,000 recent (about 60 B each = 120 KB raw), older compacted into per-settlement counts and 200 "historic" lines |
| **TravelParty** | `followers.gd summon` (travel delay), `migration.gd` waves (pooled to 16), `caravans.gd`, `campaign.gd` couriers, `enterprise` routes, `scouts.gd` | `TravelParty {id, members[], from, to, eta, route, purpose}` as the one moving-group record; migration, caravans, couriers and delegations become party kinds | `tp:n` | 70 B each, max 64 active |

### Cross-cutting additions
- **Universal action framework:** `Action {id, actor(ch/org/bz), verb, target, cost, duration, mode}` resolved by one `ActionResolver` in `realm/actions.gd` with verb handlers registered by existing modules (recruit, hire, found, build, buy, sell, accuse, petition, march). Player UI and NPC planners both submit Actions. Existing public functions (`followers.recruit`, `camps.found_camp`, `city_life.join_guild`) become handlers, not rewritten.
- **Modes:** each Organization and Business has `mode` in `manual | delegated | autonomous`. Delegated runs a planner each day under the owner's standing orders and writes reports to EventRecord.
- **Save:** bump `SCHEMA_VERSION` 3 → 4. Migration adds an empty `registry`, `orgs`, `contracts`, `events` block with no change to existing blocks. Existing dirty-container mechanism (`save_containers.gd`) holds each new block as its own container so autosave only rewrites dirty ones.

---

## Part D. Work packages by stage

Owner key: **cloud** = systems (pure data, GDScript, tests, balance sims); **local PC** = visuals and animation (needs GPU, Blender, real screenshots). Test files go in `kingdom/tests/test_lw_*.gd`; headless sims in `docs/balance/data/`. Every package: determinism test, catch_up equals day-by-day within tolerance, save round-trip, cost test.

**Budget columns.** Tick = worst single job at that tier on a mid PC (target 60 fps = 16.6 ms frame, scripts share about 6 ms). Tiers follow Part E: **T-near** (player bubble, per frame), **T-mid** (same settlement, hour tick), **T-far** (day/week tick, aggregates). Save = added KB at the stage-end population.

### Stage 1. Living Thornfield
Goal: spec §1 rules and §11 and §12 shown in one village.

| ID | Scope | Files | Depends | Acceptance tests | Budget (tick ms / save KB) | Owner |
|---|---|---|---|---|---|---|
| LW-1.1 | **Registry and IDs.** `realm/registry.gd` with persistent id counters, legacy alias map, lazy Character upgrade from WorldSim row. Register in `realm_hub.gd`. | new `realm/registry.gd`; edit `realm_hub.gd`, `save_manager.gd` (schema 4 + migration) | none | Old schema-3 save loads; ids never reused after save/load; alias round-trips; upgrade of 200 rows is deterministic | near 0 / mid 0.1 / far 0.3; save +20 KB | cloud |
| LW-1.2 | **EventRecord ring** written by `settlements.gd` emergencies, `society.gd` crimes, `family`/`life_courses` births and deaths, `news.gd`. Reader API by actor/where. | new `realm/events.gd`; edit the listed writers (one call each) | LW-1.1 | 30-day Thornfield sim yields at least 50 records; ring capped at 2,000; compaction keeps counts | write <0.02 per event; save ≤120 KB raw | cloud |
| LW-1.3 | **Four axes record** (membership, employment, loyalty, ownership) as separate fields; adapter from `careers.gd` seats, `followers.gd` loyalty, `ownership.gd`. Rank-rights table loader. | new `data/living_world/org_types.json`, `realm/axes.gd`; edit `sim/careers.gd` | LW-1.1 | Test: an employee who is not a member; a member who is disloyal; owner employing a rival; rights check refuses an action above rank | mid 0.1 | cloud |
| LW-1.4 | **Thornfield residents with lives:** every Thornfield villager (15 to 30 from `town_roster.gd`) upgrades to a full Character with home Property, job, household, goal and memory; daily routine already in `schedule.gd`. | edit `world/town_kit/town_roster.gd`, `population/utility_brain.gd`; new `realm/npc_goals.gd` (the 5 decision layers contract) | LW-1.1, 1.2 | Run 60 days headless with player absent: at least 3 births/deaths/marriages/job changes recorded; no villager idle for more than 2 game days; goals change after events | near 2.0 (existing utility budget), mid 0.3; save +12 KB | cloud |
| LW-1.5 | **Decision-layer contract** (needs, routine, goals, social, strategy) as one `decide(ch)` pipeline calling the existing code per layer. | new `realm/npc_goals.gd`; edit `utility_brain.gd` | LW-1.4 | Each layer unit-tested with a stub; layer order fixed; layers can be switched off per tier (far tier runs only goals) | far 0.05 per NPC per day | cloud |
| LW-1.6 | **Visual pass of the living village:** door-to-interior walk, visible routines, work animations, family at home. | `scripts/world/town_kit/*`, animation files | LW-1.4 | Local PC screenshot review against Style G; no pop-in | GPU only | local PC |

### Stage 2. Recruitment
| ID | Scope | Files | Depends | Acceptance | Budget | Owner |
|---|---|---|---|---|---|---|
| LW-2.1 | **Recruit as Character:** `enterprise_people.recruit` produces named Characters for the player's retinue and officers (troops stay stack counts); recruits keep agency (refuse, quit, negotiate terms). Contract record. | edit `realm/enterprise_people.gd`, `followers.gd`; new `realm/contracts.gd` | LW-1.1, 1.3 | Recruit with bad terms refused; leaves when unpaid; Contract saved/loaded; stack recruits still work | mid 0.2; save +30 KB per 100 | cloud |
| LW-2.2 | **Channels:** offers, notices (board/crier), apprenticeships, migration arrivals as candidates, absorbing an organization (merge). | edit `callups.gd`, `city_life.gd` (boards), `migration.gd`, `education.gd`; new `realm/recruitment.gd` | LW-2.1, 1.2 | Each channel yields a candidate with source tag; absorb moves members with their rank mapped; migration wave produces recruitable settlers | far 0.3 | cloud |
| LW-2.3 | **Members vs personal followers** + **delegated command chains** (leader → officer → squad), orders with refusal and reports up. | edit `followers.gd`, `soldier.gd`; new `realm/command_chain.gd` | LW-2.1, 1.3 | Order passes 3 levels; officer refuses an order above his rights; report arrives next day as EventRecord | mid 0.2 | cloud |
| LW-2.4 | Recruitment UI: progressive disclosure (one list with source tags, terms sheet on tap). | `scripts/ui/` new `recruit_panel.gd` | LW-2.2 | PC pass | none | local PC |

### Stage 3. Property and farming
| ID | Scope | Files | Depends | Acceptance | Budget | Owner |
|---|---|---|---|---|---|---|
| LW-3.1 | **Property record** unifying `property.gd` lots, `homestead.gd` plots, `land.gd` deeds, with `legal_status`. | new `realm/properties.gd`; edit `property.gd`, `homestead.gd`, `land.gd` | LW-1.1 | Buy/sell/lease adjust one record; legal_status transitions tested | mid 0.1; save +8 KB | cloud |
| LW-3.2 | **Farm model:** per-field soil (fertility, moisture), crop rotation effect, pests, seasons (`seasons.gd`), field as expandable cells beyond three plots; livestock herds as production (owned, fed, sold). | edit `sim/homestead.gd` (split to `homestead_fields.gd`), `world/town_kit/town_livestock.gd` | LW-3.1 | 4-season sim: monoculture yield falls 20 to 40%, rotation recovers it; pest outbreak reduces yield and is cured; herd grows and feeds | day tick 0.4 per farm; far farms closed-form; save 0.3 KB per field | cloud |
| LW-3.3 | **Farming ladder:** farmhand → tenant (rent/share to a landowner) → owner → estate (multiple farms, workers). Hire/assign/pay workers, sell and relocate a farm; political route (estate seat in governance council). | edit `career_trades.gd` or new `realm/farming_career.gd`; `governance.gd` seat hook; `data/careers/ladders.json` | LW-3.1, 3.2, 1.3 | Path A scenario (below) runs headless; ladder requirements enforced; relocate moves Property and workers | day 0.3; save +6 KB | cloud |
| LW-3.4 | Farm visuals: fields growing by stage, pests, animals, seasons, expandable fence/build. | `homestead_view.gd`, assets | LW-3.2 | PC review | draw budget per Style G | local PC |

### Stage 4. Guilds and businesses
| ID | Scope | Files | Depends | Acceptance | Budget | Owner |
|---|---|---|---|---|---|---|
| LW-4.1 | **Profession table** (`data/living_world/professions.json`): 13 named plus 20 more, each with join route, independent route, ladder, income source. Adapters to `career_trades`, `soldier`, `adventurer_guild`, etc. | new data + `realm/professions.gd` | LW-1.3 | Every profession reachable by both routes; table lint test | none at runtime | cloud |
| LW-4.2 | **Organization record** and rank-rights, founding stages, treasury, dues, schism; adapters for guilds, bands, orders. Growth ladder Party → Clan → Legion → Great House. | new `realm/organizations.gd`; edit `city_life.gd`, `enterprise.gd`, `notables.gd` | LW-1.3, 2.3 | Found-by-player and found-by-NPC both reach stage 3; growth thresholds tested; schism splits members | day 0.5 across 400 orgs | cloud |
| LW-4.3 | **Business accounts, ownership shares, production chains** per Business, remote management by reports (manual/delegated/autonomous). | new `realm/businesses.gd`; edit `enterprise_core.gd`, `economy.gd`, `settlements.gd` | LW-3.1, 4.2 | Delegated shop yields a weekly report and profit within 10% of manual manager; autonomous business can go bankrupt | day 0.4 for 500 businesses (aggregate far); save 100 KB | cloud |
| LW-4.4 | **NPC competition** (two businesses/guilds target same contract) and NPC-founded orgs through goals. | edit `notables.gd`, `city_life.gd` | LW-4.2, 4.3 | 1-year sim shows at least 2 NPC-founded orgs and one price war | far 0.3 | cloud |
| LW-4.5 | Organization/business screens, disclosure UI, reports inbox. | `scripts/ui/` new `org_panel.gd`, `business_panel.gd` | LW-4.2, 4.3 | PC pass | none | local PC |

### Stage 5. Settlement founding
| ID | Scope | Files | Depends | Acceptance | Budget | Owner |
|---|---|---|---|---|---|---|
| LW-5.1 | **Site evaluation** score (water, soil, defence, roads, resources, danger) shown before claim. **Legal land ladder** + **illegal-build escalation** (warning, fine, demolish, force). | edit `realm/land_claim.gd`, `camps.gd`, `land.gd`, `governance.gd law()` | LW-3.1 | Claiming crown land builds an illegal record; escalation steps tested on a timer; legal charter removes it | day 0.2 | cloud |
| LW-5.2 | **Founding stages, scale classes, districts, appointed officials, emergent problems** on top of `civilization.gd`; keeps the 3-settlement cap (`BuildKit.MAX_GRIDS`). | edit `civilization.gd`, `settlements.gd`, `world/districts.gd` | LW-5.1, 4.2 | Founder appoints reeve/captain/steward; absent player: settlement still grows and has 1 emergent problem per season | day 0.6 per settlement (existing chunking) | cloud |
| LW-5.3 | **Residents with their own lives, migration in/out**, settlement defence, strongholds for player. Hidden valley rules. | edit `migration.gd`, `strongholds.gd`, `world/hidden_valley.gd` | LW-5.2, 1.4 | 1-year sim: residents arrive, work, leave; Path B and hidden valley scenarios | far 0.5 per settlement | cloud |
| LW-5.4 | Build-mode integration, site preview, districts and illegal-site visuals. | `scripts/build/*`, `ui/build_menu.gd` | LW-5.1 | PC pass on build kit | piece cap 1400/1800/2200 | local PC |

### Stage 6. Politics and territory
| ID | Scope | Files | Depends | Acceptance | Budget | Owner |
|---|---|---|---|---|---|---|
| LW-6.1 | **Territory layers** (kingdom, county, holding, claim) as a chunk grid, visibility of growth on the map. | new `realm/territory.gd`; edit `land.gd`, `factions.gd`, `ui/map_icons.gd` | LW-3.1 | Layers render from data; claim grows when settlement grows | day 0.1; save 9 KB | cloud |
| LW-6.2 | **Nobility:** 8-step petition/audience pipeline, access to the king, multi-axis reputation, marriage/inheritance for all houses, running a territory. | edit `nobility.gd`, `lordship.gd`, `family.gd`; new `realm/audiences.gd` | LW-1.1, 6.1 | Petition goes through 8 steps with a record; blocked by rank; multi-axis rep changes by axis | mid 0.1 | cloud |
| LW-6.3 | **Kingdoms and diplomacy:** FactionRelationship table, reaction table to independent factions (ignore/tax/recognize/suppress), capturing territory. Unfreeze the 13-kingdom work from `FOUNDATION_PLAN.md`. | edit `factions.gd`, `war_sim.gd`, `news.gd` | LW-6.1 | A growing player faction triggers each reaction at its threshold; capture is not ownership (keeps `land.gd`) | far 0.4 | cloud |
| LW-6.4 | **Justice:** laws per kingdom, case records, investigation by officers, courts, inequality/liberation. | edit `governance.gd`, `society.gd`, `population/evidence.gd`; new `realm/courts.gd` | LW-6.3, 1.2 | Accused → case → trial → sentence; a law change by kingdom changes verdicts | day 0.3 | cloud |
| LW-6.5 | Audience scenes, court, map layers visuals. | UI + scene | LW-6.1, 6.2 | PC pass | GPU | local PC |

### Stage 7. Military
| ID | Scope | Files | Depends | Acceptance | Budget | Owner |
|---|---|---|---|---|---|---|
| LW-7.1 | **Army entity** linking org, commander, stacks, named officers; types, recruiting and training pipeline, upkeep (**logistics cost**). | edit `campaign.gd`, `war_units.gd`, `enterprise_people.gd`; new `realm/armies.gd` | LW-2.3, 4.2 | Training takes days and costs; unpaid army desertion; upkeep visible in ledger | hour 0.3 per 10 armies | cloud |
| LW-7.2 | **Third-person field command** with couriers and fog of war for player-owned units; delegated mode. | edit `tactical.gd`, `campaign.gd` couriers | LW-7.1 | Orders arrive after courier delay; units outside sight not shown; delegated mode follows standing orders | near 1.0 for 24 visible units | cloud (logic), local PC (feel) |
| LW-7.3 | **Settlement defence** for player settlements (garrison, walls, alert), siege hook. | edit `siege.gd`, `strongholds.gd`, `towers.gd` | LW-5.3, 7.1 | Raid on player settlement resolved with garrison and walls; absent-player outcome logged | day 0.3 | cloud |
| LW-7.4 | Army visuals, formation animation, battle camera. | `scripts/combat/*`, animation | LW-7.2 | PC review | GPU | local PC |

### Stage 8. Advanced society
| ID | Scope | Files | Depends | Acceptance | Budget | Owner |
|---|---|---|---|---|---|---|
| LW-8.1 | **Religion and culture:** priest career, temples as functional Buildings, festivals, culture shares effects. | edit `factions.gd`, `migration.gd`; new `realm/faith.gd` | LW-4.1, 5.2 | Festival changes mood/trade for days; priest ladder both routes | day 0.2 | cloud |
| LW-8.2 | **Emergent events** director over EventRecord (causes → effects, chains). | new `realm/emergence.gd`; edit `settlements.gd`, `ecology.gd` | LW-1.2 | 5-year headless sim produces at least 20 distinct chains and no repeating loop | day 0.3 | cloud |
| LW-8.3 | **Personal life:** relocation of household, education ages for children of all houses, travel parties for families. | edit `household.gd`, `education.gd`, `followers.gd`; TravelParty | LW-3.1, 1.1 | Relocate moves household, job, property; child enters school at the right age | day 0.2 | cloud |
| LW-8.4 | **Example paths A to E** scripted as headless acceptance sims; chronicle log readable. | `docs/balance/data/lw_paths_sim.gd` | all earlier | All five complete without a locked career, with and without joining | n/a | cloud |
| LW-8.5 | **Progressive disclosure UI** pass over all new panels. | `scripts/ui/*` | all | PC pass; first-touch reveals tested | GPU | local PC |

---

## Part E. Performance rules for 1,000+ simulated NPCs

Baseline today: WorldSim rows (about 10k people) are packed arrays sliced at about 1,500 rows per frame at about 1.0 ms; near NPCs ≤ 24 animated bodies (`MAX_FULL = 24`); realm hub pump ≤ 0.6 ms per frame (`PUMP_BUDGET_USEC = 600`); each module's hour tick ≤ 0.3 ms.

**Tier budgets (PC-first, tighter than needed so the phone port stays viable):**

| Tier | Who | Cost rule | Budget |
|---|---|---|---|
| T-near | up to 24 full bodies in the player bubble | full utility AI, perception, animation | ≤ 2.0 ms/frame (existing) |
| T-mid | same settlement, up to 250 m: WorldSim rows and upgraded Characters | sliced round-robin, O(1) per row, no nodes; decision layers 1 to 2 only | ≤ 1.0 ms/frame |
| T-far | everyone else | no per-person work between ticks; day/week aggregate | day tick ≤ 0.6 ms per job, chunked; `catch_up` O(entities) closed-form |

Rules:
1. **Event-driven, not polled.** A character is only re-evaluated when something that affects its goals fires (EventRecord with its id in `actors`, need threshold crossed, contract due, schedule edge). Timers use due-day queues (a heap/bucket by day), never a per-frame scan.
2. **Aggregate households far away.** Outside the player's region, households are counts per settlement (population, wealth, food, job shares). They become individual Characters only when referenced (recruit, marry, accuse, hire) and fall back to aggregates when idle for 30 game days and not tied to an org, contract or property. Same for troops: stacks, with named officers only.
3. **Full records are rare and capped:** 1,000 upgraded Characters, 400 Organizations, 500 Businesses, 64 active TravelParties, 16 active migration waves (existing cap), 2,000 EventRecords.
4. **Decision layers by tier:** near uses all five; mid uses needs and routine plus goals hourly; far uses goals/strategy only on the day tick, at most 1 decision per Character per 3 game days (jittered by id).
5. **No new per-frame work in `scripts/realm/`.** Everything goes through hub `tick_hour/tick_day/tick_week` and `pump()`. Any new job over 0.6 ms must chunk (`tick_day_chunks`).
6. **Determinism:** each module seeds from `hash([WorldSim.SEED, tag, day, id])`; no global RNG, no Vector2 in saved state.
7. **Pathing and spawning** stay on existing limits (`MAX_SPAWNS_PER_FRAME = 1`, `MAX_FULL`, `MAX_SPRITES = 140`). Batch registration work (the known 600 ms `StreetGraph` registration when many buildings finish in one `catch_up`, from `FOUNDATION_PLAN.md`) must be fixed before Stage 5 content lands.

**Save growth limits (JSON schema 4, zstd on disk):**

| Item | Limit |
|---|---|
| Full save raw JSON at 1,000 upgraded Characters, all caps reached | ≤ 2.5 MB raw, ≤ 600 KB zstd |
| Growth per game year after the first year | ≤ 150 KB raw (prune: dead characters become 1-line history; expired contracts → counts; events compacted) |
| Autosave write time | ≤ 1 frame of work per step (existing stepped job `_job`), dirty containers only |
| Each new block | own container so unchanged blocks are not re-serialized |

Existing note: `CIVILIZATION.md` set the two-year save at under 1 MB; this doc raises it to 2.5 MB raw because of the 1,000-character target. Confirm the owner accepts that.

**How to verify:** a headless sim (`docs/balance/data/` pattern) with 1,000 upgraded Characters over 5 game years prints per-module tick maxima and save size; CI fails on a budget breach. Run through CI (`ashes-ci`), not the memory-short container.

---

## Part F. Order of work and open questions

1. LW-1.1 and LW-1.2 first; everything else depends on ids and the event ring.
2. Stage 5 depends on the StreetGraph batching fix.
3. Stage 6 unfreezes the 13-kingdom work that `FOUNDATION_PLAN.md` froze; the owner should confirm the foundation milestone is accepted as shipped before LW-6.3.
4. Open: (a) the "20 more" professions need the owner's list; (b) confirm the 2.5 MB raw save limit; (c) confirm that troops stay aggregate stacks and only officers and the player's retinue are Characters.
