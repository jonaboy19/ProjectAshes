# Civilization pressure: a world that changes because things happen

The user asked for this on 2026-09-30 ("the Tensura feeling"). It is part of the Living World design (`LIVING_WORLD.md`, `REALM_WAR_SETTLEMENT.md`).

The goal is not to copy Tensura's powers. The goal is that **places grow and die, people migrate, peoples mix, politics keep moving, and the world visibly changes because of what happens, with or without the player.** You live through an era; the world wasn't finished before the game started.

The core loop is **civilization pressure**. A frontier valley has one weak runestone route, a hunter camp and a few adventurers. Then:

1. Someone discovers iron.
2. A merchant opens a caravan route.
3. Guards arrive and the runestone line is extended.
4. Families migrate in and a smith opens.
5. Bandits notice the traffic, and a lord builds a fort.
6. Fifteen years later it is a town.

None of that needs the player, but the player can speed up, redirect or ruin any step.

Timing follows `SIM_HIERARCHY.md`. Everything is day or week tier, `catch_up` is O(entities) and closed-form, and state is JSON-safe and seeded. Realm module rules are in skill `ashes-realm-module`, place rules in `ashes-region-content`.

## Existing code this extends (never duplicate)
| Existing | Already does | Extended with |
|---|---|---|
| `realm/settlements.gd` | identity drift (7 identities), supply chains, stock, population regrowth, emergencies, raid aftermath | tiers and lifecycle, boom and decline, housing/food/jobs pressure, NPC-built structures, development projects |
| `sim/runestone_network.gd`, `sim/caravans.gd` | protected roads, caravans | safety field from the network, caravans carrying real goods, route loss changing prices |
| `realm/camps.gd`, `realm/construction.gd` | player camps on scored terrain, staged construction with workers | NPC-founded camps, and NPC projects using the same staged sites (visible progress) |
| `realm/society.gd` | rumours, reputation, NPC memory and goals, relationships | incomplete-information rumours, regional news, fame travel speed, social titles |
| `realm/factions.gd`, `sim/titles.gd`, nobility and lordship | houses, marriages, church, sects, war reputation | councils, succession, laws, delegations and embassies |
| `sim/life_courses.gd`, `sim/family.gd` | NPC ageing, marriage and heirs | families as institutions, inherited businesses, generational reputation, NPC heroes |
| `realm/enterprise.gd` | workshops, caravans, companies | companies growing branches, guild competition, economic specialization |
| `realm/education.gd` | academies, teachers, rankings | school reputations drift, rivalries, teachers changing careers |
| `sim/monster_ecology.gd`, `threat_map.gd`, monster camps | dens, species, migrations | territories and nests, predator-prey balance, monster factions, domestication |
| `realm/exploration.gd` | dungeon state, leads | expeditions that get lost and later leave relics |

## Systems by package

### CIV-A: settlement lifecycle and migration (new `realm/civilization.gd` + `realm/migration.gd`; extends settlements)
- **Tiers:** camp → outpost → village → town → city (fortified) → trade hub, or → ruin. Transitions come from population, food security, safety (runestone coverage and threat), leadership quality, road links and resources, with hysteresis so places don't flicker.
- **Pressure:** housing, food and jobs are each supply/demand ratios per settlement. Shortfalls cause unrest, emigration and poorer meals. Surplus attracts immigrants.
- **Boomtowns:** a discovery event (rare Rift mineral, monster resource, a player find) adds attraction and inflow waves of merchants, workers, mercenaries, researchers and criminals. Crime and prices rise.
- **Decline:** mine depletion (resource reserves are finite), a trade route rerouting, or a runestone failing lowers attraction. The settlement slowly shrinks, buildings are abandoned, and it can end as a ruin (which stays as a landmark).
- **Migration waves:** push factors are war, monsters, famine, Rift activity and bad laws; pull factors are safety, jobs, fame and kin. Groups travel along roads over days and arrive as refugees or settlers. Refugee camps form at the edge.
- **Specialist migration:** a settlement's fame in a field attracts named master smiths, scholars, healers, architects, trainers and commanders (strategic NPCs, cap about 30 in the region).
- **Mixed districts:** each settlement keeps culture shares per district (native, foreign realms, beastfolk, refugees). Sustained inflow creates a named quarter. Cultural exchange adds foods, clothes, styles and festivals to a place over time.
- **NPC construction and development projects:** settlements queue projects by need and treasury: houses, walls, bridge, road, irrigation, mine, school, port, market, runestone extension. Each runs as a staged `construction` site (weeks to years), so progress is visible when the player is near.
- **Runestone expansion:** coverage adds safety, which makes land commercially viable. Farmsteads spread outward, caravans appear, and new camps get founded along safe routes. Those camps grow through the tiers.
- **Dynamic founding:** new settlements start as camps (existing `camps` presence) at scored terrain along safe routes, near discovered resources, or by NPC founders. Cap the region at about 12 dynamic settlements.

### CIV-B: government, leaders, NPC agency, information (new `realm/governance.gd` + `realm/notables.gd` + `realm/news.gd`; extends society and factions)
- **Leaders:** every settlement, guild, company and order has a named leader with traits (competence, greed, piety, martial, openness). Leaders age, die, retire, get replaced or promoted. Succession runs by election, appointment or heredity per institution. Leader traits drive the settlement's choices and quality.
- **Councils** (towns and up): seats for merchants, military, landowners, guilds, temple and commons. They vote on taxes, projects, laws and diplomacy, weighted by bloc power.
- **Laws per region:** weapons restrictions, hunting rights, monster-part trade, curfew, land ownership, guild licensing, magic use, conscription. They are real gameplay: guards react, crime flags, shops refuse. They change through councils, lords and events, and they drive migration.
- **Public opinion by bloc:** merchants, farmers, soldiers, scholars, clergy, poor and outsiders. The player's leadership (if they rule) is judged per bloc, and blocs react (petitions, strikes, emigration, revolt).
- **Player-led settlements run themselves.** The player sets priorities (growth, defence, trade, welfare, faith, accepting outsiders) and appoints people. Citizens build and work.
- **Notables and NPC heroes:** a pool of about 60 named adventurers, officers, merchants and scholars with ambitions. They rise and fall and can found companies, guilds, orders, mercenary bands, settlements or even states. "The boy you met at 10 now governs Emberford." Some become the player's rivals or allies.
- **Families as institutions:** the smithy passes to the child, and families earn specialties and reputations (military, healing, trade, crime). Generational reputation means help given to a family is remembered by its heirs.
- **Guild and company competition** over contracts, territory, recruits and influence. A tiny caravan company can grow warehouses and branches.
- **NPC research projects** (runestone designs, agriculture, medicine, Rift gear) take years and can fail. Successes spread as knowledge.
- **Academies:** school reputations drift by results, rival schools compete and exchange students, and teachers leave to found schools or get poached.
- **Expeditions:** governments and guilds send named expeditions into Rifts and dungeons. The player can join, fund, sabotage or rescue them. A lost expedition becomes a famous mystery, and its gear appears later deeper in a dungeon (an exploration lead).
- **Information travels:** rumours carry incomplete facts ("something destroyed a caravan east of X") that sharpen as they spread. Regional news reaches taverns, notice boards and travellers with delay. Fame spreads at road speed. **Social titles** form as people start calling you something; the nickname spreads, becomes established, then formal.
- **The world solves problems without you.** Crises can be resolved by NPC heroes, armies or factions, or they can fail, with consequences either way.
- **Delegations and embassies:** negotiations bring physical delegations (presentation in CIV-D). Lasting alliances create embassy compounds and foreign communities. Political marriages reshape alliances without the player.

### CIV-C: living ecology (new `realm/ecology.gd`; extends monster_ecology, monster camps)
- **Territories:** each species has nests and hunting ranges. Dangerous roads come from a specific pack that moved in, never random spawns everywhere.
- **Population dynamics:** predator-prey dynamics per zone (discrete Lotka-Volterra, closed-form catch-up). Killing the apex predator makes prey explode; wiping out one species lets a worse one spread.
- **Monster migration:** seasons, stronger predators and Rift instability push species into human land, so villages see species they never saw before.
- **Intelligent monster factions** (goblins, orcs, others): they negotiate, trade, raid, migrate and settle. Their intent isn't shown; the player has to find it out.
- **Domestication over generations:** settlements near a species slowly tame it for farming, transport, guarding or resources. This is a settlement tech, not a click.
- **Adventurer economy:** danger level drives adventurer inflow, inns, equipment shops, healers, guides and bounty offices. If the danger is cleared, that economy collapses. Dungeon safe-zone towns live on explorer traffic.

### CIV-D: making it visible (presentation; after A to C land)
- **Festivals and public events** physically change a city for several days: decorations, stalls, crowds, tournaments, parades, coronations, monster hunts, diplomatic arrivals.
- **Delegations** arrive as carriages, soldiers and servants walking in. Embassy compounds and foreign quarters use their home realm's props and clothing.
- **War scars and reconstruction:** burned farms, damaged walls, abandoned gear, widows and veterans. Villagers clear rubble and rebuild over weeks (construction stages). Old battlefields become memorials, scavenger sites or new settlements.
- **Threat build-up before disasters:** scouts report, merchants vanish, refugees arrive, armies mobilise, and only then does the threat arrive.
- **Visible trade:** caravans with cargo, and market stalls that show shortages (empty stalls, poorer meals, protests).
- **Recognisable cities:** each settlement is recognisable without its name, from architecture, clothing, industries, food, guards and street activity (from identity, culture shares and tier).
- **Visual QA is local-session work** on a real GPU (see `ashes-handoff`).

## Budgets
- **Region scale:** about 20 static settlements, up to about 12 dynamic ones, about 60 notables, about 30 specialists, and migration groups pooled to 16 active.
- **Cost per game day:** each module's day tick is chunked (`tick_day_chunks`) with each pump job at or under 0.6 ms. `catch_up` is closed-form.
- **Save size:** the 2-year save must stay under 1 MB. Prune dead notables into short history lines.

## Acceptance (per package)
- A 15-year headless sim (`docs/balance/data/progression_sim.gd` style) shows a frontier camp growing into a town when iron and runestones are present. A cut-off mining town shrinks. At least one migration wave, one leader succession, one NPC-founded organisation and one lost expedition appear. Output goes to a readable chronicle log.
- Tests: determinism, catch_up equivalent to day-by-day within tolerance, save round-trip, and cost.
- The digest ("While you were away...") and tavern news show the changes in plain words.
