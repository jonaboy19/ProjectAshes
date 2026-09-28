# Rising Ashes: "What life did this character live?"

The user's direction as of 2026-09-28. It extends `docs/RISING_ASHES_OPEN_WORLD.md` and all existing
content (Ashford region lore, cultures, nations, sects, naming, guild, military, skills). Nothing existing is
removed; it is folded into this structure. The story bends to what the player does: many scenarios, many outcomes.
**Everything below is to be playable inside the first region (Valencious, the Ashford region).**

## Pillars
1. **Civilization is safe because people made it safe; the world is not.** Roads, runestones, patrols and
   walls push into dangerous wilderness. Leaving them is a real risk decision, worse at dusk and night.
2. **You are a person, not a class.** What you repeat becomes who you are. Careers accumulate into a
   biography; switching paths keeps your history, reputation and contacts. You never get years of experience for free.
3. **The world never waits.** NPCs age, marry, die and rise; prices, wars, monsters, nobles and roads change
   whether the player looks or not. Each save grows its own history.
4. **Rising Ashes' own power system**, not a renamed Tensura: Soul Power → Blessing (age 12) → Elemental
   Mastery → Techniques → Paths → Mutations → Echoes → Inner Worlds, with 12 soul tiers. Abilities evolve by
   *how* they are used (a smith's fire is not a soldier's fire). Naming = a rare Soul Name ritual that shares Soul Power.

## World structure (rings)
City centre → paved roads → outer farms → maintained kingdom road → rural runestone road → weak frontier
road → wilderness trail → unprotected wilderness → mountains/ruins → Rift frontier. Journeys take time
(horses, inns, camps, caravans matter).

**Roads:** tiered width and surface (stone near settlements, packed dirt, trail), drainage, bridges, markers,
traffic (carts, riders, caravans, patrols). **Runestones** line the major roads with overlapping radii and
have a condition (glowing, dim, cracked, dark) that can fail and be repaired. They shape behaviour rather than
walls: weak monsters refuse, strong ones enter briefly, intelligent ones wait at the edge, corrupted ones
barely care, bandits ignore them. Rumours carry stone failures ("two stones on the western road stopped
glowing"). Time of day scales danger: dusk predators, night creatures near civilization, deep wilderness at
night you should flee from (heard, not labelled).

## Life stages
- **4–7 childhood:** experience the world (fields, soldiers passing, caravans, Rift stories, a Soulbeast
  carcass, festivals, nobles, the smithy, sneaking to the forest, letters, discipline). Choices form quiet
  *tendencies*, never "+5 soldier".
- **8–11 formative:** meaningful events from a large pool (harvest help, travelling martial instructor, raid on
  a farm, wounded adventurer, noble procession, a friend disappears, strange object, priest notices Soul Power).
  Two childhoods differ.
- **12 Blessing / Awakening:** a cultural ceremony; element(s), strength, rare dual, or none, each with social
  consequences (apprenticeship offers, attention, stigma, hidden paths/mutations).
- **12–15 adolescence:** the natural tutorial: apprenticeships, training, work, short travel, youth militia,
  crime, friendships, enemies, reputation.
- **16+: "Live."** No forced save-the-world; story events happen around you.

## Careers (ladders that accumulate)
- **Farmer:** field hand → lease plot → own plot → employ workers → landholder → estate → regional supplier
  (crops by season/soil/demand; mills, granaries, livestock, orchards; war demand and requisitions; drought, migrations).
- **Soldier:** militia → recruit → soldier → veteran → squad leader → junior officer → captain → commander →
  general. Promotion needs reputation, discipline, ability, leadership, political support, open posts, wartime.
  Personal troops grow 5 → 20 → 60 → hundreds, with doctrine, equipment, formation, training, recruitment region,
  elemental composition and specialists.
- **Merchant:** carry goods → cart → guard → caravan → shops, warehouses, companies, contracts, loans,
  expeditions. Dynamic prices from roads, mines, war and Rift finds.
- **Blacksmith:** apprentice → journeyman → independent → master → workshop owner → guild master → royal or
  legendary smith. Metals, Soulbeast materials, conductivity, balance, inscriptions; commissions from generals and nobles.
- **Plus:** alchemist, herbalist, healer, hunter/monster hunter, miner, carpenter, mason, tailor, leatherworker,
  fisher, innkeeper, brewer, cook, scholar, priest, scribe, architect, shipbuilder, courier, explorer, mercenary,
  guard, caravan master, beast tamer, martial instructor, elemental researcher, adventurer. Skills overlap
  (a hunter's beast anatomy helps Soulbeast processing).
- **Career-born work** replaces "!" quests: a farmer's 40 sacks before winter, a merchant's collapsed bridge, a
  soldier's report to the eastern fort, a smith's 30 spearheads, a lord's irrigation dispute. Authored quests still exist.

## Property, nobility, lordship
Rent a room → rent a house → buy → multiple properties (cottage … manor, castle; workshop, store, inn,
warehouse). Land law: nobles own land; buildings still owe land tax; lease farmland; negotiate ownership.
Nobles own villages, forests, mines, bridges, markets, mills, fishing rights and tolls, and compete economically
and politically; they sponsor, invest, marry and feud. Earning or buying land makes you a **lord**: residents,
repairs, runestones, wolves, merchants, bandits, taxes, refugees, wages and winter, a settlement layer on
top of the RPG.

## Living world simulation
NPCs have life courses (join the army at 18, marry, retire, open an inn, die at 67, or die at 19). Families,
generations, inheritance, bloodlines, apprentices, succession. Monsters have territories, prey and
migrations, so chains emerge (a strong beast moves in → wolves displaced → livestock lost → hunters find the
real cause). War reaches ordinary people: prices, horses, recruitment, contracts, refugees, danger, fortified
borders, crime. Day and night change routines (gates close at night, guards increase, taverns fill). Seasons
change planting, floods, campaigns, harvest, winter logistics and monster behaviour.

## Late game
Rifts are bridges to other ecosystems, societies and laws of nature; this era pushes deeper. That is the
expansion layer after Valencious.

---

## Build plan (first region). Existing code each step extends is in brackets.
**Phase 1: foundations (now)**
1. Roads and runestone corridor: road tiers and widths, runestones along roads with condition and failure,
   behaviour by monster class, bandits, rumours, day/night danger, road traffic
   [world_gen roads, runestone_network, frontier, monster_ecology, wolf/monster AI, region_sites waystones].
2. Childhood 4–15: start age 4, childhood and formative event pools, tendencies, the age-12 Blessing ceremony,
   adolescence apprenticeships [life_path, hidden_triggers, archetypes, birth cutscene, dialogue].
3. Biography and mastery: per-activity experience that accumulates, profession reputation, a biography log,
   career ladders for farmer, soldier, merchant and smith with promotion rules, career-born work
   [careers, military, crafting, market, radiant_quests, titles].

**Phase 2: property and economy.** Renting, buying, land tax, leases [homestead]; merchant carts, caravans,
shops, dynamic regional prices and trade routes [market]; farm employees and estates.

**Phase 3: nobility and lordship.** Noble houses with holdings and rivalries; earning or buying land;
village management [WorldSim settlements].

**Phase 4: living simulation.** NPC life courses, marriage and families, generations and inheritance;
monster migration chains; war and economy coupling [WorldSim, monster_ecology, military].

**Phase 5: Soul system.** 12 soul tiers, Blessing affinities, Paths, usage-driven skill evolution, Soul Name
ritual reworking naming, Echoes and Inner Worlds hooks [skills, magicules, naming].

**Phase 6: region scale.** Ring layout, longer journeys, forts, frontier towns, Rift frontier site.
