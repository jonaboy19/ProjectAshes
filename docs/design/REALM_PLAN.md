# Realm plan: what implements the design docs

Sources: `REALM_WAR_SETTLEMENT.md` (R§n) and `LIVING_WORLD.md` (L§n). Timing: `SIM_HIERARCHY.md`.

Code lives in `kingdom/scripts/realm/`. Every module extends `realm_module.gd` and is owned by `realm_hub.gd`, which in turn is owned by `Life.realm`. That wiring is done: `Life._on_hour` queues ticks, `Life._process` pumps them, and the save round-trips under the `"realm"` key. Modules reach siblings with `hub.mod("name")` and the rest of the game through `ctx["life"]` (read-only use of `life.war`, `life.lordship`, `life.nobility`, `life.careers`, `life.economy`, `life.property`, `life.relationships`, `life.homestead`, `life.guild`). Modules **extend** those systems and never duplicate them.

Tests go in `kingdom/tests/test_realm_<module>.gd`; follow the pattern of `tests/test_war.gd`.

## Modules

| Module | Covers | Builds on |
|---|---|---|
| `followers.gd` | R§1 followers are real people (traits, loyalty, needs, their own opinions), R§2 summons with travel delay along roads, L§18/19 temporary vs permanent companions, L§42/43 travel companions and party disagreements, R§31/32 creature taming per species and settlement roles | relationships.gd, monster_ecology.gd |
| `camps.gd` | R§3 camps on chosen terrain (terrain score: water, wood, defence, road access), R§4 free construction as data (placed structures, supply-chain stations), R§5 roads matter (road condition affects travel time, trade and raids) | homestead.gd, build_menu, economy |
| `settlements.gd` | R§6 settlement identity (merchant, fortress, religious, farming, mining, scholarly, criminal) that drifts from what is built and who lives there, not tiers; R§37 emergencies; R§36 player absence digest; supply chains per settlement | economy.gd, WorldGen.settlements |
| `land.gd` | R§7 land ownership and deeds (legal claim vs occupation), R§8 conquest ≠ ownership (loyalty, unrest, rebellion), R§34 territory memory (massacres and kindness are remembered), R§38 generational consequences | property.gd, lordship.gd |
| `factions.gd` | R§23 diplomacy map data, R§24 relationship networks between houses, R§25 political marriages, R§26 many paths to kingship, R§27 church influence, R§28 sects and independent powers, R§22 war reputation | nobility.gd, titles.gd, war_sim.gd |
| `strongholds.gd` | R§29 strongholds controlling passes, bridges and roads (tolls, chokepoints), R§30 dynamic raids, R§33 regional difficulty as "recommended preparation" | region_sites, threat_map.gd, monster_camps |
| `campaign.gd` | R§9/10 War Room and campaign map showing **only known intelligence** (it ages), R§11 armies moving on the road graph, R§12 courier-delayed orders, R§13 commander autonomy (personality decides), R§14–16 live vs strategic resolution vs hybrid, R§17 formations as data, R§18/19 logistics and supply lines, R§20 retreat types, R§21 covert ops with evidence, R§35 war councils | war_sim.gd, military.gd, army/formation.gd |
| `city_life.gd` | L§4 inns (rooms, rumours, rest quality), L§5 renting, L§7–11 jobs with qualifications and interviews, employment, career progression and job failure, L§12 quest boards per district, L§13/14 hidden work and hidden careers (assassin/thief/smuggler found through exploration, never offered), L§15–17 guild entry and internal politics, L§35 districts at night, L§49 schedules create opportunities | careers.gd, career_ladders.gd, adventurer_guild.gd, radiant_quests.gd, property.gd |
| `society.gd` | L§20/21 NPC and reputation tiers, L§22/23 provocation and duels, L§24–30 relationships, dating, compatibility, noble courtship, marriage, problems, families, L§31/32 social classes and clothing effects, L§33/34 crime with witnesses, evidence and criminal reputation, L§36 information travels (rumours), L§37/38 NPC memory and goals, L§40/41 apprenticeships, L§46 failure creates stories, L§48 knowledge progression | relationships.gd, family.gd, life_courses.gd, nobility.gd |

The rest (R§39/40, L§1/2/3/44/45/47/50) are design rules: the player never controls everything, there are no glowing markers, and the endgame isn't an ending. Every module has to respect them. For example, followers and commanders can refuse, the quest board has no map pin, and a finished war seeds the next conflict.

## Presentation (after the data)

1. **World:**
   - Strongholds and camps are placed at pass/bridge sites.
   - Faction banners use each faction's colours.
   - An inn and a War Room table go in the lord hall interior.
   - Build all of it with MultiMesh cells.
2. **UI (AshesFrame style):**
   - War Room campaign map: the world_map in embedded mode plus known-intel icons and an orders panel.
   - Diplomacy overlay.
   - District quest board.
   - Inn and rent dialog.
   - Job interview dialog.
   - Followers and summons panel.
3. **Performance pass:** profile the gate market city on LOW and keep it within the SIM_HIERARCHY budgets.

## Queued (user direction, 2026-09-30)

- **Survival building** (in progress, `realm/construction.gd`):
  - You gather and process resources yourself.
  - Buildings unlock in tiers and levels, with prerequisites and tech.
  - Construction happens in visible stages, with a worker count and skill-based speed.
  - You can build anywhere, and builders and haulers walk real paths to the site.
- **Wars rarer and more realistic:** today about 17–19 wars in 2 simulated years, at war about 31% of the time. The target is roughly one war every 1–3 years, lasting weeks to months. Wars need causes: claims, feuds, succession, raids, Rift crises. Raise the war-declaration tension threshold and the post-war tension (`war_sim.gd`), add war weariness and treaty durations.
- **The player's character can influence wars at any rank:**
  - enlist or raise a militia
  - scout and carry messages
  - supply the army as a merchant
  - sabotage, spy or assassinate (with evidence)
  - negotiate and broker peace, or provoke incidents
  - fight in engagements personally
  - defend their home settlement
  - run a caravan through the front
  - shift war goals through a lord or council
  Each action feeds `war_sim` tension, campaign engagements, `factions` war reputation and diplomacy. This starts after war map phase B lands, since both touch campaign code.

## Freedom and exploration first (user direction, 2026-09-30)

- **Quests are optional.** Players can do anything, go anywhere and become anything. Exploration is the core pleasure, so reward curiosity: secrets, lore, rare resources, knowledge facts, vistas and hidden places.
- **No hard boss gates.** The user doesn't like "real bosses". Big creatures, such as the Scarbound Troll or the Antlered Warden, are optional encounters you can avoid, outwit, tame or appease. They are never required walls for progress.
- **One power path is the main one.** Magic, bending, knight arts or martial arts. A second path is very hard to learn, as `power_paths.gd` already models.
- **Dungeons and caves:** caves, hidden caves (behind waterfalls, vines, collapsed rock) and small dungeons across the region, each with its own danger tier, loot, lore and puzzles.
- **The hidden valley:** a secluded, untouched valley reached through a hidden pass. On first discovery a short discovery cutscene plays: a camera sweep, music and a line like "No one has walked here in an age…". It is lush, pristine and an ideal place to found your own settlement.
- **Priority:** finish the beginning of the game so new players have hours of play across the whole first region.

## Progression and content scale (user direction, 2026-09-30)

- **Level range:** the whole game runs to level 500, and Region 1 caps around 50–60. Clearing Region 1 must take weeks, not hours. Protections against rushing:
  - repetition decay
  - regional saturation past about level 55
  - several parallel sources of XP
- **Cultivation** is required on every path: one shared ladder of realms and stages, with a different flavour per path. Region 1 reaches the first two or three realms. Breakthroughs carry risk, and manuals come from schools, dungeons and towers.
- **Natural dungeons end in a boss.** Separately, **dungeon towers** work like Sword Art Online's Aincrad: floors, labyrinths, safe zones, boss doors and first-clear rewards, with NPC parties racing you to the next floor.
- **Items:** a full set of hundreds of items with recipes, market stock by town identity, and loot tables.
- **Unused models and animations:** once the current agents land, audit all imported models and animations and place or wire everything unused, such as meshy_free packs, the animation libraries and the region kits.
