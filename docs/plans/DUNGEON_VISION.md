# Rising Ashes — Living Dungeons (owner direction, 2026-10-27)

Source: design discussion the owner brought in (screenshots in `ref_dungeons/design_*.jpg`), adopted as direction. Names of floors/guardians below are **proposed content, not canon** until the owner confirms. Inspired by Sword Art Online's floor dungeons, but each dungeon is a *second world beneath the world*.

## ⚠ Performance target — correction from the owner
The original proposal said "16 GB RAM + 8 GB GPU". **Wrong.** Optimise for a **regular, average PC — possibly one without a dedicated GPU** (integrated graphics, e.g. Intel Iris Xe / AMD Radeon 680M class, 8–16 GB shared RAM). Every dungeon system must have a low preset that runs there: aggressive streaming, small chunks, tight draw distances, baked/cheap lighting, few dynamic lights, MultiMesh, LODs, occlusion, low NPC counts at full sim. This applies to the surface world too (see PERF60_BRIEF.md — add an iGPU tier).

## Structure: 60-floor dungeons
Each dungeon has 6 regions of 10 floors. Each region: own ecology, factions, elemental conditions, major guardian. The two floors before each guardian are expansive inhabited inner worlds; 58–59 are the largest.

| Floors | Region (proposed) | Theme | Inner worlds | Guardian |
|---|---|---|---|---|
| 1–10 | The Forgotten Depths | ancient ruins, mines, underground rivers | 8–9 Ashen underground wilderness | 10 The Buried Warden |
| 11–20 | The Drowned Dominion | flooded temples, swamps, water + lightning | 18–19 submerged kingdom | 20 Guardian of the Abyss |
| 21–30 | The Rootbound Wilds | living forests, fungi, nature + earth | 28–29 ancient forest civilisation | 30 The Root Sovereign |
| 31–40 | The Frozen Expanse | ice, wind, mountain fortresses | 38–39 snow kingdom | 40 The Winter Monarch |
| 41–50 | The Ember Warlands | volcanoes, ash, fire, ruined empires | 48–49 warring nations + cities | 50 The Ashen Emperor |
| 51–60 | The World Beyond | Rift anomalies, ancient magic, distorted reality | 58–59 two huge inhabited worlds | 60 final guardian + realm |

Bosses don't always need killing: combat, sealing rituals, political manoeuvring, or very hard alternative routes.

## Floor types (mix them; next floor's type should surprise)
- **A Labyrinths:** tunnels, chambers, vertical shafts, traps, locked doors, secret passages, underground rivers, ancient machinery; some huge with multiple paths.
- **B Underground wilderness:** giant caverns with forests, lakes, mountains, ecosystems; hunt, camp, build, native creatures.
- **C Civilised floors:** villages, kingdoms, fortresses, farmland, roads, markets, faction territories; residents live independently of the player.
- **D Elemental domains:** frozen kingdoms, volcanic wastes, storm towers, drowned ruins, living forests.
- **E Entire inner worlds:** feel like another country; several civilisations, wars, hidden settlements, huge beasts, magic skies.

## Elements vs biomes (separate systems)
Biome = base environment; element = force acting on it. Storm (lightning on tall structures, metal conducts, wind hampers climbing), Frozen (lakes freeze, blizzards hide roads, ice beasts), Fire (lava reroutes paths, water → steam, heat hits survival/machines), Nature (roots grow over paths, plants react to magic, migrations); also earth, water, wind, light, shadow, poison, gravity, rare Rift corruption. Change over time on three scales: short (weather/storms/surges by conditions, not a timer), long (migrations, seasons, water levels, faction machinery, days), historical (permanent: boss defeated, relic destroyed, war, player action — e.g. floor 19's water recedes revealing a city that refugees and creatures move into).

## Safe cities and settlements
Categories: protected cities, fortified towns, frontier villages, faction fortresses, homesteads. Safe cities have families, farmers, traders, guards, healers, scholars, children; homes to rent/buy/build; markets fed by real supply routes; guilds/factions; workshops, schools, libraries, inns, temples, warehouses, hospitals; government (elections/appointments/hereditary); laws, crime, justice, tax, territory. Player can live there, join the army, run a business, marry, recruit people to found a village elsewhere. Settlements function without the player. Some cities grew around a dead guardian's remains whose protection may start failing (crisis arc).

## War on inhabited floors
War is an ongoing possibility, not nonstop combat. Example floor 48: Iron Bastion (militarised human kingdom: mines, roads, towns), Ashborn Clans (beastkin tribes: forests, passes), Free Enclave (neutral trade city), Hollow Court (subterranean faction using hidden tunnels). Territory, supply lines, diplomacy, migration change even while the player is elsewhere. Safe cities stay reliable; frontier/military settlements can be attacked/captured/abandoned with warnings and recovery.

## Layout archetypes
- **A Branching labyrinth:** entrance → hall → crossing → guardian; side puzzle, safe camp, treasure, rare secret; primary route + loops + concealed branches (ruins, prisons, tombs).
- **B Inhabited open-world floor:** river, roads, borders, sanctuary city, factions' fortress/war camp, beast territory, ruins, independent NPC travel.
- **C Multi-layer elemental:** stacked layers (e.g. Storm Galleries / Molten Forges / Void Chambers) with lifts, shafts, secret drops; a machine on one layer changes another (bridges, draining, shifting passages).

## Living beasts and people
Persistent regions: NPC society with memory/property/jobs; beast ecology (hunt, breed, migrate, territory, raid settlements); factions recruit/patrol/trade/negotiate/conquer; player can rent/buy/claim land and build; survival (food, water, shelter, medicine, gear wear, rest, supplies). Special beasts have personalities (a giant guardian tolerates villages but retaliates if its nesting grounds are cut); some can be befriended, studied, domesticated or recruited.

## Hidden mechanics and rare secrets (never highlighted; clues only: drafts, older stonework, echoes, diaries)
Brittle walls (pickaxe/heavy weapon/spell; sometimes cave-in), hidden floors not on maps, false architecture (statue over door, rotating shelf), living labyrinths (creatures dig new tunnels, destroy bridges — layout truly changes), lost NPC expeditions (camps, journals, survivors, rivals who take artifacts first), ancient mechanisms (redirect rivers, repair elevators, counterweights), hidden monster civilisations (combat optional), world-changing discoveries (a passage linking distant kingdoms changes trade/war). Design-target frequencies (per dungeon, not per-floor rolls): loot alcoves common; breakable secret wall ~6 %; secret puzzle chamber ~4 %; hidden subfloor ~2 %; unique hidden boss ~1 %; forgotten settlement < 1 %; legendary world mysteries: a handful in the whole world. None required for the main story.

Dungeons are decisions, not just fights: e.g. a mine with a flooded quarry, a bandit-held entrance, unstable shafts — negotiate, drain via machinery, recruit a miner guide, or risk the shafts; inside, monsters migrate, rivals advance, supplies run low, rooms flood after rain.

## Technical architecture (Godot)
- Dungeon registry with all dungeons/floor definitions; only the current floor is instantiated.
- Chunk streaming via `ResourceLoader.load_threaded_request()`; chunk sizes tuned per space (64–128 m start; smaller on the iGPU preset); scene-tree insertion on the main thread.
- Mesh LOD, visibility ranges, occlusion culling for interiors, MultiMeshInstance3D vegetation, per-region navigation meshes + links.
- NPC sim tiers: full near the player, simplified mid-range, abstract off-floor; other floors/dungeons keep saved state + lightweight simulation, not loaded scenes. Neighbour floors may preload entrance assets only.
- Persistence: procedural seeds + deltas (player/NPC/faction changes).
- Validate with the Godot profiler / ObjectDB profiler / GPU memory on the **min-spec iGPU tier** first.

## Build order
Specify all 60 floors on paper, but build a vertical slice of dungeon 1 first: generator, environment/element systems, faction sim, persistence; then 7 representative playable areas — labyrinth, cavern, elemental region, inhabited village, safe city, multi-route inner world, boss encounter. Expand only once those run well on min-spec. The `claude/dungeons` cloud task (seeded labyrinth generator + tests) is step 1 of this.
