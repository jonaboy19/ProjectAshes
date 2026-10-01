# Region 1 Plan: Valencious, the Ashford Vale

Owner-facing plan to **finish the whole first region** of Rising Ashes as a shippable vertical slice for mobile.
Written 2026-09-29 from `origin/claude/focused-curie-m09hbd` (read-only survey of docs, `kingdom/scripts`, `kingdom/data`, addons and asset libraries).

World posters (all planned regions): `docs/art/regions/`

| File | Content |
|---|---|
| `01_valencious_solkar_frostcrown.webp` | **Valencious (Region 1)**, Solkar Dominion, Frostcrown Holds |
| `02_eastern_church_realms.webp` | Church of the Dawn Throne: Aurelis Patriarchate, Varska Marches, Serathi Lowlands |
| `03_verdanweald_zephyr_tideclad.webp` | Verdanweald Enclaves, Zephyr Steppe, Tideclad Isles |
| `04_ashenreach_umbrafen_jadecliff.webp` | Ashenreach Forgeholds, Umbrafen Marsh, Jadecliff Dominion |
| `05_rifts_ember_bloom_tempest_glacier.webp` | Ember, Bloom, Tempest and Glacier Rifts |

Art rule: all Region 1 visuals follow the single sunny storybook look (`docs/art/reference/00_MAIN_kingsreach_gate_market.webp`, skill `ashes-art-style`). The poster's Valencious panel is the best mood reference for the region: golden light, runestone-lined cobbled road, a white castle city on a river, blue runes.

---

## 0. Which region is Region 1? (confirmed)

- `kingdom/data/world/regions.json`: `"current": "ashford_vale"`, `"realm": "Valencious"`.
- `docs/RISING_ASHES_LIFE_SIM_DESIGN.md`: "playable inside the first region (Valencious, the Ashford region)".
- `kingdom/data/world/first_region.json`: "The Ashford Vale", home `ashford`, capital `kingsreach`, `nation: caldrenn`.
- Poster 02 labels the realm west of the Church lands "Valencios: limited influence, border closures, runestone traditions endure."

**Region 1 = the Ashford Vale, the heartland of the Kingdom of Valencious.** Kingsreach is its capital.

### Canon reconciliation (decision needed from the owner; recommended defaults)
The data files predate the posters. Recommendation: keep every data **id**, change only **display names**, and record the mapping in `first_region.json` / `nations.json` (work package C0).

| Data today | Poster | Recommendation |
|---|---|---|
| Nation `caldrenn` "Kingdom of Caldrenn" | Valencious | Display "Kingdom of Valencious". **Caldrenn** becomes the ruling dynasty (King Aldric III of House Caldrenn). The **Caldric** culture stays: the people of Valencious. |
| `solmarch` Solmarch Theocracy, capital **Aurelion**, Solenne culture, Dawnflame | Church of the Dawn Throne / **Aurelis** Patriarchate | Same power. Rename it "Aurelis Patriarchate (Church of the Dawn Throne)" and move it **east** to match poster 02. Varska and Serathi become its vassal realms (new data rows). |
| `ongur` Ongur Khanate (steppe, wind) | Zephyr Steppe | Same people; region display name Zephyr Steppe |
| `veylwood` Veylwood Concord | Verdanweald Enclaves | Same people; region display name |
| `hollowdeep` Hollowdeep Holds (Durrow, forge) | Ashenreach Forgeholds | Same people; region display name |
| `shenlu` Shenlu Peaks Covenant (sects, cultivation) | Jadecliff Dominion | Same people; region display name |
| `seirune` Isles of Seirune | Tideclad Isles | Same people. Seirune's shinobi and samurai divisions stay as a Tideclad court culture. |
| — | Solkar Dominion, Frostcrown Holds, Umbrafen Marsh | New data rows (no Region 1 content beyond teasers) |
| `urrokai` Urrokai Clanlands | — | Keep; the orcs of Tuskridge Hold are its exiles |
| `docs/GDD.md` (Sugo, Aramori, Godot 4.4) and `docs/KINGDOM_DESIGN.md` (pixel look) | — | **Superseded.** Add a banner pointing to `RISING_ASHES_OPEN_WORLD.md` and this plan. |

Poster map names map onto the existing world as follows. WorldGen's `NAMES` stay unchanged; the poster names are new sites or display aliases.

| Poster name | Becomes |
|---|---|
| Highwatch | **Highwatch Keep**, the knightly stronghold on the northern ridge (upgrades the current frontier watchfort site) |
| Silverford | The **guild town** at the Ashrun ford (display alias for the WorldGen town nearest the river; C1 picks it) |
| Crownstead | The **royal crown farms** between Ashford and Kingsreach, around Cinderpost |
| Greenhollow | The farming village of the south-west meadows (display alias for Oakvale) |
| Elden Road | The **old runestone road** west past the Shrine of the Sleeping Flame to the Rift frontier |

---

## 1. Region 1 definition

### 1.1 Identity
*"A realm rooted. A people enduring."* Fertile fields, steadfast towns and rune-guarded roads. Safety exists only because people maintain it: step past the last glowing stone and the land changes. The region is **8 × 8 km** (seed 1066, streamed in 64 m chunks; it was 4 × 4 km until the outer land was added: the original valley is the ±2 km core, unchanged, with about 20 settlements, four forts, a second river and two Rifts in total). Danger climbs with distance from Kingsreach. Density stays mobile-safe because nothing per frame scales with world size (see `docs/design/SIM_HIERARCHY.md`). The map shows the other 12 realms as unexplored edges (`regions.json`).

### 1.2 Geography and sub-areas
Coordinates are metres from Ashford (0, 0); north is -z. ✅ = exists in code or data now, 🆕 = new in this plan.

| Ring | Sub-area | Where | Role | State |
|---|---|---|---|---|
| Home | **Ashford** village + runestone circle, Old Mill Staff Yard | (0, 0) | Birth, childhood, tutorial hub, first home | ✅ settlement, services, interiors |
| Home | **Emberglass Mere** + jetty, **the Ashrun** river, Ashrun Bridge | SW / W | Fishing, water, hidden **Whisper Hollow** | ✅ |
| Farmland | **Crownstead** royal farms, farmsteads with windmills around every village, **Greenhollow** | Ring around villages | Farming career, harvest events, livestock | ✅ farms / 🆕 names and crown estate |
| Road | **King's Ember Road** → **Cinderpost Waystation** → **Kingsreach** | NE, 700 m | Safe kingdom road, caravans, patrols | ✅ |
| Capital | **Kingsreach**: royal castle-city, Royal Ember Academy, court, noble houses | (560, -420) | Politics, academy scouting, big market, tournaments | ✅ city / partial: court content |
| Town | **Silverford** guild town: Masons' and Runecarvers' Guild, Merchants' Hall, Adventurer Guild branch | on the Ashrun | Crafting careers, guild ranks, runecarving teacher | 🆕 identity (settlement exists) |
| Villages | Millbrook, Stonehollow, Eastmere, Redwater, Thornfield, Oakvale/Greenhollow, Brackenmoor, Westfen | spread | 6–10 villages with their own trades | ✅ generated; 🆕 identity per village |
| Stronghold | **Highwatch Keep** (Order of the Highwatch, the Ember Lancers), **Greywatch Spear Hall** | N ridge / Greywatch | Soldier career, knighthood, sparring, north-pass garrison | partial: watchfort landmark; 🆕 keep |
| Mine | **Greyseam Mine** (iron, copper, coal) | northern hills | Miner career, ore economy; 🆕 a short mine interior with a rift seam | ✅ exterior + ore veins |
| Forest | **Duskbriar Wood**: bandit camp, **Mossfang Warren** (goblins), collapsed tower | SE (380, 480) | First combat zone, hunting, foraging | ✅ |
| Beyond | **Tuskridge Hold** (orc exiles, Chief Harrok Ashmaw) | (300, 930) | Diplomacy or war, naming, orc village | ✅ |
| Old road | **Elden Road**, **Shrine of the Sleeping Flame** (age-8 trigger) | W (-700, -160) | Weak frontier road, hidden trigger | ✅ shrine / 🆕 road identity |
| Wilds | **Rift-touched wilds**: *the Ashen Scar*, the Rift entrance + Rift's Edge Camp, a spreading violet corruption (mechanic N2) | frontier edge | Late-region danger, rare materials, region finale | partial: landmark + camp only |
| Sacred | **Stagborn Glade**: an ancient grove where the stagborn herd gathers around a fallen Elder Stone | NW woodland | Signature creatures, Elder Stone quest | 🆕 |
| Network | **Runestone network**: the village ring, road stones every 180–420 m, and 🆕 **five Elder Stones** (hubs) | region-wide | Safety, the signature mechanic (N1) | ✅ sim + visuals / 🆕 Elder hubs |

### 1.3 Factions

| Faction | Seat | Wants | Player hook |
|---|---|---|---|
| **The Crown** (King Aldric III, Council of Wardens) | Kingsreach | Order, taxes, keep the Church out | Court access, lordship, war |
| **Runeward Legion** (the stone-keepers) | Kingsreach + every road | Keep the stones glowing, never enough hands | Wardwright career (N1), maintenance jobs |
| **Order of the Highwatch** (knights, Ember Lancers) | Highwatch Keep | Hold the north pass | Soldier → knight ladder, merit ledger |
| **Silverford Guilds** (Masons and Runecarvers, Merchants, Adventurers) | Silverford | Contracts, prices, guild monopoly on runecarving | Crafting and merchant careers, guild ranks |
| **Noble houses** (generated by `nobility.gd`) | fief towns | Land, marriages, rivalry | Sponsorship, leases, feuds |
| **Church of the Dawn Throne** envoys (Aurelis) | a mission chapel in Kingsreach | Replace the "pagan" runestones with Dawn relics | Political tension, tempting power, border tease |
| **Duskbriar bandits** (the Ashen Hand) | bandit camp | Toll the rural roads, sabotage stones for hire | Combat, the Ashsight investigation (N4) |
| **Mossfang goblins** (Snikkit the Twice-Bitten), **Tuskridge orcs** (Harrok Ashmaw) | warren / hold | Survive, grow, evolve | Naming, diplomacy, raids |
| **Stagborn** (not a faction: a herd) | Stagborn Glade | Graze, migrate along old ward-lines | Sacred beasts, Elder Stone key |

### 1.4 NPC roles (minimum cast for a complete region)
- **Named story cast (12):** mother and father (exist: `parents.json`), Maren Coldbrook (staff teacher), the Ashford Guard Captain, Warden Idra Vell (Runeward stone-keeper, the main quest giver), Guildmaster of Runecarvers (Silverford), Sir Rowan Ashby (Highwatch knight-captain), Envoy Lucan of the Dawn Throne, Harrok Ashmaw, Snikkit, a Solkar spice merchant (tease), the Rift's Edge quartermaster.
- **Service roles per settlement:** trader, innkeeper, smith, healer/herbalist, guild clerk, guard, farmer, fisher, miner, carter (existing `village_services.gd`, `careers.gd`, `life_courses.gd`).
- **Ambient:** patrols, caravans, riders (`road_traffic.gd`), pilgrims heading east, Runeward maintenance crews (🆕, visible stone repair).

### 1.5 Creatures

| Tier | Creature | Where | State |
|---|---|---|---|
| Ambient | deer, **stag**, rabbit, fox, birds, livestock, fish | everywhere | ✅ (`ambient_life.gd`, `critter.gd`) |
| Common | wolf packs, boar, blight rat, giant rat | woods, fields at night | ✅ |
| Camp | goblins, orcs, bandits | Duskbriar, Tuskridge, roads | ✅ (bandit humanoid variety partial) |
| Uncommon | fungal brute, bear, giant wasp, bog toad, ghoul | deep wood, Westfen, ruins | ✅ first three / models exist but unused for the rest |
| Signature | 🆕 **Stagborn**: a *Stagborn elk* herd (passive, antler charge when threatened) and the **Antlered Warden** (guardian miniboss) | Stagborn Glade, migration routes | 🆕 model (Meshy) + behaviour |
| Rift-touched | 🆕 rift wolf (material variant), **rift_slime**, **rift_wraith** (models exist, unused), mutated flora | Ashen Scar, spreading (N2) | partial |
| Apex | troll, wyvern (rare) | hills, far north | ✅ ecology + models |
| Finale | 🆕 **the Scarbound Troll** (rift-mutated apex boss) at the Rift mouth | Ashen Scar | 🆕 |

### 1.6 Day and season feel
- **Day** (`daily_rhythm.gd`, `weather.gd`): dawn bells and mist on the Mere → market mornings, carts on the Ember Road → noon fieldwork → dusk: gates close, lanterns, stones glow brighter → night: taverns full, wolves at the edge of the ward, danger felt through sound before it is shown.
- **Seasons** (`seasons.gd`: 4 × 28 days; festivals Planting, Midsummer Fair, Harvest, Winter Solstice):

| Season | Feel | Region 1 specifics |
|---|---|---|
| Spring | green, lambing, floods | Planting Festival; Stagborn migration north along old ward-lines; Ashrun runs high (bridge events) |
| Summer | gold, fairs, travel | Midsummer Fair + Highwatch tournament; Solkar caravans arrive; the Scar spreads fastest (heat) |
| Autumn | amber, harvest, taxes | Harvest Festival; tithe dispute with the Church envoy; boar rut; Kindling Night (Caldric) |
| Winter | blue, scarcity | Stones decay faster, wolves bolder; the north pass snows shut; Solstice; the Scar goes dormant (a containment window) |

### 1.7 Links to future regions (teases, not content)

| Direction | Physical tease in Region 1 | Leads to |
|---|---|---|
| East | **The Eastern Gate**: a closed border post with Church banners beyond, pilgrims turned back; the envoy's chapel in Kingsreach | Church realms (Aurelis, Varska, Serathi) |
| South | Solkar spice caravans at the Midsummer Fair, desert goods at the Silverford market, a sunstone relic in a quest | Solkar Dominion |
| North | **Grimfen Pass** above Highwatch Keep: snowed shut, frost-horned bones, aurora on clear winter nights | Frostcrown Holds |
| South-west | Westfen marsh edge, Veyl rangers (allied) at the Stagborn Glade | Verdanweald, Umbrafen |
| The Rift | The Ashen Scar's mouth: in the finale the player glimpses one ember-red and one bloom-violet chamber beyond it | Ember and Bloom Rifts (the expansion layer) |

---

## 2. Gap analysis

Legend: ✅ works, 🟡 partial or unwired, ❌ missing. Paths are relative to `kingdom/`.

### 2.1 Systems
| Area | State | Evidence / gap |
|---|---|---|
| Streaming world, terrain, water, roads, settlements | ✅ | `scripts/world/world_gen.gd`, `terrain_streamer.gd`, `water_streamer.gd`, `settlement_builder.gd`, `city_planner.gd` |
| Region sites (farms, bridges, waystation, mine, shrine, bandit camp, watchfort, Rift + camp) | ✅ | `scripts/world/region_sites.gd`, `region_dressing.gd` |
| Runestone network (power, condition, decay, failure, rumours) + threat map | ✅ sim / 🟡 play | `scripts/sim/runestone_network.gd`, `threat_map.gd`, `autoload/frontier.gd`, `world/frontier_presence.gd`. **Gap:** the player can't *do* much with stones beyond repair jobs: no player-driven routing, carving or expansion. No Elder Stones. |
| Monster ecology (dens, migration, apex, Rift dens) | ✅ | `scripts/sim/monster_ecology.gd`. **Gap:** the Rift only adds a den; there is no spreading corruption. |
| Population and daily life (WorldSim rows, LOD, utility AI, street graph) | ✅ | `autoload/world_sim.gd`, `scripts/population/*` |
| Careers, ladders, mastery, biography, titles, archetypes | ✅ | `scripts/sim/careers.gd`, `career_ladders.gd`, `mastery.gd`, `biography.gd`, `titles.gd`, `archetypes.gd` |
| Life path: birth, childhood events, tendencies, Blessing at 12 | ✅ | `life_path.gd`, `childhood_events.gd`, `tendencies.gd`, `awakening.gd`, `cinematic/birth_cutscene.gd` |
| Family, generations, succession | ✅ data / 🟡 play | `scripts/sim/family.gd`, `ui/family_screen.gd`. Death → heir exists; nothing in the world marks a lineage. |
| Soul, echoes, skill evolution, naming, magicules | ✅ data / 🟡 | `soul.gd`, `echoes.gd` (its header says "not wired yet"), `skill_evolution.gd`, `naming.gd` |
| Economy, markets, caravans, property, homestead, nobility, lordship, war sim | ✅ | `economy.gd`, `market.gd`, `caravans.gd`, `property.gd`, `homestead.gd`, `nobility.gd`, `lordship.gd`, `war_sim.gd`. **Gap:** no long-run balance run (30–100 days), and money sinks are unproven. |
| Save / load (3 slots, autosaves) | ✅ | `scripts/sim/save_manager.gd`, `Life.snapshot/restore` |
| Discovery, compass, world map, fast travel, photo mode | ✅ | `sim/discovery.gd`, `ui/compass.gd`, `ui/world_map.gd`, `ui/photo_mode.gd` |
| Interiors | 🟡 | 5 interiors (`scenes/interiors/`); **missing:** mine tunnel, Highwatch hall, guild hall, chapel, Rift pocket |
| AI addons | 🟡 | **LimboAI: 0 uses** (utility AI in GDScript instead). **GodotGAS:** referenced in `skills.gd` only. **quest_weaver:** only signal forwarding, **no quest graphs**. **dialogue_manager:** bypassed by the custom `dialogue_runner.gd` (5 JSON files). **terrain_3d, road-generator, proton_scatter:** unused. That's fine: don't adopt them for Region 1 unless a package needs one. |

### 2.2 Content
| Area | State | Gap |
|---|---|---|
| Buildings and village kit | ✅ | Meshy houses and stalls, generated props, PBR detail street |
| Region kits (farm, mine, road, ruins, nature) | ✅ | `assets/generated/region/` (152 GLBs) |
| `meshy_free` (385 models: castle pieces ×27, churches ×20, 4 runestones, 5 portals, crystals, ruins, furniture) | 🟡 **0 placed** | Main source for Highwatch Keep, the Silverford guild hall, Elder Stones, the Rift-touched kit |
| Creatures | 🟡 | 8 Meshy rigged creatures in use. **Unused:** rift_slime, rift_wraith, ghoul, giant_wasp, bog_toad, the Meshy armored humanoids (bandit, knight, guard, mercenary), riding horse. **Missing:** Stagborn, the boss. |
| Settlement identity | ❌ | The 12 settlements are generated alike. Each needs a trade, a landmark, a named NPC and a rumour set. |

### 2.3 Quests and story
| Area | State | Gap |
|---|---|---|
| Radiant jobs (herbs, wolves, deliver, escort, lost child), guild board, career-born work | ✅ | `radiant_quests.gd`, `adventurer_guild.gd` |
| Parent, gossip, guild and innkeeper dialogue | ✅ thin | `dialogue/*.json` (5 files) |
| Hidden triggers (age-8 shrine) | ✅ | `hidden_triggers.gd` |
| **Main questline for the region** | ❌ | No authored arc, no finale, no "Region 1 complete" moment |
| Authored side quests per settlement (target: 12–15) | ❌ | none |
| Cutscenes beyond the birth | ❌ | `cutscene_player.gd` exists; only the birth shot list |

### 2.4 Combat
| Area | State | Gap |
|---|---|---|
| Player melee: combo, block, parry, dodge, lock-on, hitstop, shake, ragdoll | ✅ | `actors/player.gd`, `ragdoll.gd`, `camera_shake.gd` |
| Techniques and elemental VFX (8 elements × 7 effect types) | ✅ | `technique_caster.gd`, `vfx/element_fx.gd`, `scenes/vfx/elements/` |
| Enemy AI: wolves (ward response), camp monsters, squads, attack tokens | ✅ | `wolf.gd`, `monster.gd`, `creature_attack_tokens.gd`, `army/*` |
| Humanoid enemies with weapons (bandits, knights) | 🟡 | Armored Meshy models exist; no dedicated duel controller |
| Ranged (bow) | ❌ | "Bows (none yet)" in the handoff; clips exist in `animations_free2` |
| Boss fights (phases, arena, telegraphs) | ❌ | |
| Mounted combat / riding | 🟡 | `mount_controller.gd` exists; ride clips unwired |
| New clip libraries | 🟡 | `animations_free/` (114 clips) and `animations_free2/` (life-sim, traversal, ranged) are **not in `Assets.UAL_FILES`** |

### 2.5 Economy and progression
- ✅ Per-settlement markets, dynamic prices, wages, property, taxes, crafting quality, equipment slots.
- 🟡 No balance pass: time-to-first-house, sword-vs-wage curve and the pace from Levy to Captain are unmeasured.
- ❌ No regional **progression spine**: what a player should reach by the end of Region 1 (soul tier, career rank, gear tier), and what gates the Rift.

### 2.6 UI
- ✅ Dark-gold front end, tabbed game menu (Inventory, Character, Skills, Quests, Map, Journal), HUD, touch controls, technique arc, discovery banner (`ui/frontend/*`, `ui/gamemenu/*`, `ui/hud.gd`).
- 🟡 The boot-flow wiring patch is unapplied (`docs/platform/boot_wiring_wip.patch`).
- ❌ UI for the new mechanics: ward map layer, runecarving canvas, Scar overlay, ember placement, Ashsight replay controls, quest-tracker pin on the HUD.

### 2.7 Audio
- ✅ `scripts/audio/audio_director.gd`, adaptive music (`music_bank.gd`, 19 interactive files), 39 ambience beds, about 210 SFX.
- 🟡 Only 9 music tracks. The incoming packs (incompetech 12, music-cc-by 4, bigsoundbank 79, OpenGameArt about 1,280) are unused.
- ❌ Per-area themes (capital, guild town, keep, glade, Scar), a rune hum and ward sounds, Stagborn calls, Rift ambience, a boss theme, NPC voice barks (grunts and greetings).

### 2.8 Onboarding and tutorial
- ✅ `boot/first_run.gd` (language, privacy, a 4-line hint); the birth cutscene; childhood as a soft tutorial.
- ❌ No guided first 20 minutes: no contextual prompts (move, talk, interact, fight, block, eat, sleep, repair a stone), no failure-safe first fight, no "why the stones matter" moment. This is the **biggest shipping risk** for mobile retention.

**Top gaps, in order:** (1) main questline, finale and onboarding; (2) signature mechanics that make the runestone and Rift fantasy *playable*; (3) settlement identity plus `meshy_free` placement (the keep, the guild town, the Elder Stones); (4) humanoid, ranged and boss combat plus the unwired clip libraries; (5) region audio and a balance pass.

---

## 3. Never-seen-before mechanics

Each builds on systems that already exist, so it's cheap relative to its novelty. Cost: S ≈ 1–2 packages, M ≈ 3–4, L ≈ 5+.

### N1. Wardwright: carve and route the runestone network ★ pick
- **Pitch:** Every runestone is a node in a living power grid. You **carve glyphs with your finger** onto stones (a stroke grammar), and **drag ward-lines** between stones on the map to route a limited flow of power. Coverage decides where monsters roam, where farmers dare to settle and which roads caravans take.
- **Player fantasy:** "I am the one who decides where civilization ends."
- **30-second loop:** reach a dim stone → trace a 2–3-stroke glyph (ward, lure, alarm or bless-harvest) → the stone flares, and the map shows the ward bubble shifting → a wolf pack visibly redirects toward the new gap you left → decide: patch it, or leave it as a lure for a hunt.
- **Novel because:** Okami-style drawing and Zelda runes are *combat and puzzle* tools. Here the strokes **program persistent infrastructure** that an NPC and monster simulation reacts to for days. Mount & Blade has territory but no player-shaped safety field. Stardew has no danger geography.
- **Systems:** `RARunestoneNetwork` (exists) + 🆕 `wardlines.gd` (flow budget per Elder Stone, routing graph, coverage override) + 🆕 `rune_gesture.gd` (a $1 unistroke recognizer, glyphs in JSON) + map layer + career hook (Runeward Legion ranks).
- **Mobile UX:** a full-screen stone face and one-finger strokes with generous tolerance; the map uses drag-from-stone-to-stone with snap; haptic tick on each correct stroke; auto-complete assist in settings.
- **Cost:** M.

### N2. The Scar Tide: a Rift corruption that spreads, mutates and can be farmed ★ pick
- **Pitch:** Rift-touched land spreads outward from the Ashen Scar cell by cell (32 m grid), like weather fronts on a slow clock. It turns grass violet, mutates crops into rare "scarbloom" variants, and turns wolves and boars into rift variants. Wards slow it, fire burns it back, winter freezes it. It is also the region's most valuable harvest.
- **Player fantasy:** "I tame a spreading apocalypse, or I profit from it."
- **30-second loop:** see the violet edge on the map creep toward Greenhollow's fields → go there: rift-touched boars, glowing crystals → harvest scar-crystal (big money), or burn and ward the front (villagers cheer, prices drop) → the next in-game day the front has moved according to your choice.
- **Novel because:** Genshin, Zelda (Gloom) and Dragon's Dogma have **static** corruption zones. Here it is a **simulated, spreading, player-contestable biome** that feeds the economy (scar goods crash or boom prices) and the ecology (displacement chains). It's a strategic resource and a threat at once.
- **Systems:** 🆕 `scar_tide.gd` (grid, spread rules by season, wards and fire), `monster_ecology.gd` rift dens (exist), economy goods (exist), a terrain tint via a global shader parameter texture, variant materials.
- **Mobile UX:** readable violet overlay on the map and compass; one-button "burn" or "ward" at the front; containment progress ring.
- **Cost:** M.

### N3. Ember Legacy: the dead become the stones ★ pick
- **Pitch:** When your character dies, or retires as an elder, their soul is an **Ember**. You choose where it rests: in a **runestone** (the stone gains power and speaks as your ancestor, voicing rumours and warnings in your old character's words), in your **heir** (inherit one Echo and a skill trace), or in a **weapon or tool** (an heirloom that levels with the family).
- **Player fantasy:** "My family literally protects this land. I walk the road my grandmother warded."
- **30-second loop:** at death, a cinematic ember rises → a simple 3-choice radial → as the heir, you pass *her* stone on the Ember Road; it glows gold and greets you by name, warning of a pack at dusk.
- **Novel because:** Fable and Crusader Kings have heirs, and Rogue Legacy has lineage, but none turn **past playthrough characters into permanent world infrastructure** that keeps simulating (stone power, personalised barks). It gives the title "Rising Ashes" a mechanic.
- **Systems:** `family.gd` succession + `echoes.gd` (both exist) + 🆕 `ember_legacy.gd` + an ancestor-stone flag in `RARunestoneNetwork` + bark templates built from the biography (`biography.gd`).
- **Mobile UX:** a 3-card choice; ancestor stones marked gold on the map and compass; a tap on a stone shows the ancestor's biography card.
- **Cost:** S–M.

### N4. Ashsight: replay what really happened ★ pick
- **Pitch:** At burnt farms, broken stones and ambush sites you can kneel and see **ash-ghost replays of the real simulated events** that happened there: the bandit raid three nights ago, which way the wolves fled, who sabotaged the stone. The replay is recorded from the simulation log, not scripted.
- **Player fantasy:** "Nothing in this world is hidden from me if I arrive before the ashes cool."
- **30-second loop:** a rumour: "Two stones on the western road went dark" → reach the stone, tap Ashsight → the screen drains to grey, and translucent figures re-enact a hooded man chiselling the glyph and fleeing north-east → follow the ember-trail footsteps → find the Ashen Hand's hideout.
- **Novel because:** Detective modes (Batman, Witcher senses) replay **authored** scenes. Here the "crime" was produced by the sim (`road_events`, `monster_ecology` and `runestone_network` events), so every save has different cases. The evidence also cools with time, so it rewards reacting to rumours.
- **Systems:** 🆕 `ash_memory.gd` (ring buffer of positioned events + actor paths sampled at 1 Hz near significant events), 🆕 ghost replay node (reusing impostor or sprite crowds, one shader), hooks into the existing event emitters.
- **Mobile UX:** hold to see; a scrub bar under the thumb; tap a ghost to pin its trail on the compass.
- **Cost:** M.

### N5. Taught Hands: your style spreads through the world
- **Pitch:** The moves you use most (combo patterns, parry timing, favourite element) are recorded. When you teach at the Staff Yard, train your squad or raise an heir, NPCs **inherit your weights**, and bandits who survive you adapt to them.
- **Novel because:** no open-world RPG turns the player's own playstyle into NPC AI parameters that propagate socially.
- **Systems:** a move histogram in `player.gd` (hook), attack-weight tables in `monster.gd` and `army/soldier.gd`. **Cost:** M. Defer to Region 2, apart from the histogram.

### N6. Rumour Market: trade in (false) news
- **Pitch:** Rumours are items. Buy them, verify them (Ashsight), sell them, or **forge them** to move prices or lure bandits into a guarded ambush.
- **Novel because:** information as a falsifiable, tradeable commodity inside a live economy.
- **Systems:** `runestone_network.rumours()`, economy events, a rumour item type. **Cost:** M. Region 1 only needs the read side (rumour cards feed N4).

### N7. Hearth Oaths: seasonal vows
- **Pitch:** At each season's festival, swear one oath at the village ring ("I will not shed blood this spring", "I carry the harvest"). Keeping it grants a Blessing boon; breaking it has social and soul consequences.
- **Novel because:** a pact system tied to the calendar and community memory, sized for mobile sessions. **Cost:** S. A good stretch goal for Region 1.

### N8. Weather-forged Blessings
- **Pitch:** Your element leaves marks the world remembers: scorched wheat regrows as fire-lilies, frozen ponds stay as ice paths for a day, lightning-struck stones hold charge. Villagers recognise you by your marks. **Cost:** M. It's partially covered by `skill_evolution.gd`, and it's the least novel of the set (compare Divinity and Zelda). Defer.

### Ranking and choice

| Rank | Mechanic | Novelty | Fit | Mobile | Cost | Region 1 |
|---|---|---|---|---|---|---|
| 1 | N1 Wardwright | ★★★ | ★★★ (poster pillar "runestones keep the roads safe") | ★★★ | M | **Yes (core)** |
| 2 | N3 Ember Legacy | ★★★ | ★★★ (the title, family sim) | ★★★ | S–M | **Yes** |
| 3 | N2 Scar Tide | ★★★ | ★★★ ("rift-touched wilds") | ★★ | M | **Yes** |
| 4 | N4 Ashsight | ★★☆ | ★★★ (uses sim logs) | ★★★ | M | **Yes** |
| 5 | N7 Hearth Oaths | ★★ | ★★ | ★★★ | S | stretch |
| 6 | N6 Rumour Market | ★★★ | ★★ | ★★ | M | read side only |
| 7 | N5 Taught Hands | ★★★ | ★★ | ★★★ | M | histogram only |
| 8 | N8 Weather-forged | ★☆ | ★★ | ★★ | M | later |

**Region 1 ships N1, N2, N3 and N4.** They interlock: the Scar pushes on the ward (N2 vs N1), ancestors power stones (N3 → N1), and sabotage and raids leave ash to read (N4 → N1/N2).

### How they tie into the main questline, "The Stones Are Dimming"
1. **Act I, Ashford (childhood → 12):** a road stone goes dark. Warden Idra teaches the first glyph (tutorial N1). The Blessing ceremony follows.
2. **Act II, the Vale (adolescence):** apprenticeship choice (guild, knight or Runeward). Stones fail across the region, and the first Ashsight (N4) at a raided farm points to the Ashen Hand.
3. **Act III, Silverford and Kingsreach:** the Church envoy offers Dawn relics to replace the stones (a political choice). The Scar starts spreading (N2); the Stagborn Glade holds a fallen Elder Stone.
4. **Act IV, the Elder Stones:** re-light the five Elder Stones: Glade (Antlered Warden trial), Greyseam Mine rift seam, Highwatch, Crownstead, Elden Road. Each is a wardline hub.
5. **Finale, the Ashen Scar:** push the tide back to the Rift mouth and fight the Scarbound Troll. The Rift is sealed "for now", with glimpses of the Ember and Bloom Rifts beyond. **Region 1 complete.** Your first ancestor's ember (N3) can later sit in the Scar stone.

---

## 4. Implementation plan (work packages)

Each package is sized for **one Sonnet agent, about 1–3 hours**. IDs: **L** = local session (this PC: assets, VFX, tools, standalone systems in **new files**), **C** = cloud session (world layout, integration into existing game scripts), **X** = Codex (animation behaviour and controllers).

### Integration rules
- New code lives in **`kingdom/scripts/region1/`** (pure `RefCounted` sims + small `Node3D` presenters), data in **`kingdom/data/region1/`**, tests in `kingdom/tests/test_region1_*.gd` (gdUnit4).
- **Only these hooks** may touch hot files. The cloud adds each one in a single small commit, with a comment `# Region1 hook (docs/regions/REGION_1_PLAN.md)`:

| Hook | File | Change |
|---|---|---|
| H1 | `scripts/core/main.gd` `_ready` | `world.add_child(preload("res://scripts/region1/region1_root.gd").new())` (1 line) |
| H2 | `autoload/life.gd` `snapshot/restore` | `d["region1"] = Region1State.snapshot()` / `restore` (2 lines) |
| H3 | `autoload/frontier.gd` `threat_at` / coverage | coverage Callable overridable by `Wardlines` (≤ 5 lines) |
| H4 | `scripts/sim/monster_ecology.gd` | spawn-variant callback for Scar cells (≤ 5 lines) |
| H5 | terrain shader | sample the global `scar_mask` texture parameter for a violet tint (≤ 10 lines) |
| H6 | `ui/world_map.gd` / `gamemenu/tab_map.gd` | `add_layer(Control)` extension point (≤ 10 lines) |
| H7 | `family.gd` / `ui/frontend/death_screen.gd` | emit `life_ended(biography)` before the heir takes over (≤ 5 lines) |

- Hot files are otherwise **no-touch** for local agents: `main.gd`, `life.gd`, `player.gd`, `hud.gd`, `world_gen.gd`, `settlement_builder.gd`, `terrain_streamer.gd`, `population_lod.gd`, `assets.gd`, `quality.gd`, `world_sim.gd`. Codex owns animation code in `player.gd`, `character_animator.gd`, `wolf.gd`, `monster.gd`, `critter.gd`, `villager.gd` and `soldier.gd`.
- Never run a Godot import in a temporary worktree. Fetch and merge origin before every push. Update `docs/STATUS_LOCAL.md` and the handoff.

### Cloud integration status (C-H, H3-H7, C3-C8, C12), 2026-09-30
All wired through one node, `kingdom/scripts/region1/region1_glue.gd` (created in `main.gd` after H1), plus the hooks below. Nothing is locked behind the story: quests are optional, the tracker can be hidden, and big creatures have a parley route.
| Package | Status | Where |
|---|---|---|
| C-H (H1, H2) | done, test `tests/test_region1_hooks.gd` | `main.gd`, `life.gd` (also `Life.region1_kill` signal) |
| H3 + C3 Wardlines | done: override, elder stones as network stones, stone menu (carve, mend, link, relight), carve canvas `r1_carve_view.gd`, map layer `r1_map_layer.gd`, daily push-back | `runestone_network.gd`, glue |
| H4, H5, C4 Scar Tide | done: `scar_tide.gd` written here (L9 had not landed), variants + rift fur, `scar_mask` global in `terrain.gdshader`, burn / harvest / ward station, scar goods + price multiplier, story outbreaks | `monster_ecology.gd`, `frontier_presence.gd`, `economy.gd`, `terrain.gdshader`, `project.godot` |
| H6 parchment | done (`add_layer`, hud wiring) | `world_map.gd`, `hud.gd` |
| H7 + C5 Ember Legacy | done: emit on succession and old-age death, 3-card ember menu, ancestor stones (bark page, card, Wardlines bubble), Rowan's ember | `family.gd`, `life.gd`, glue |
| C6 + C6b Ashsight | done: raid emitters, flagged sites, kneel station, staged memories for story sites, controller (camera, grade, HUD) | `road_events.gd`, `monster_ecology.gd`, glue |
| C7 story runtime | done: `r1_story_director.gd` (talk, areas, kills, tracker text lead + compass hint, Quests tab, Journal page), Act I autoplay test `tests/test_region1_story_play.gd` | `hud.gd`, `menu_data.gd`, `tab_journal.gd` |
| C8 onboarding | done: tutorial bridge, safe first wolf (`r1_safe`), settings toggle + "Show all tips again" | glue, `wolf.gd`, settings |
| C12 audio | done: area themes + hysteresis, story cues, scar bed, rune hum, ward / carve SFX | `audio_director.gd`, `music_bank.gd` |
| QA 2026-09-30 | full gdUnit suite 1184 cases, 2 failures outside Region 1 (see handoff); Region 1 suites green; in-game Act I autoplay reaches the Blessing (`tools_qa/region1/r1_hooks_qa.gd --r1=act1`); screenshots + sheet via `--r1=shots` / `--r1=ashsight` | `/tmp/claude-0/shots/r1_hooks_sheet.png` |
| Extras | tower_site hook in `main.gd`, `society.gd` `tower_clear`, XP via `Life.award_progress`, cave rumours in villager gossip (`exploration.rumour_for` + `learn_lead`) | `villager.gd` |
| C7b whole story (2026-10-01) | done: Acts I-V all playable. Places keyed to the 12 km world by site id/name (`Places.SITES` in `region1_places.gd`: r1id, region1 id, exact site name, settlement, or offset from another place); the story's runestones exist (`_ensure_story_stones`: Miller's, Silverford test, edge anchor at Scar Watch, Kingsreach gate stone, Rift's Edge ring of three); creatures: rift wolves at the ring and the Highwatch gate, Ashen Hand raiders (camp roster kills counted, camp refills), Antlered Warden (world den, kill or parley), Scarbound Troll at the Scar Mouth (spawn, kill or parley); finale at Scar Mouth Arena (`rift_mouth`); news echoes + fame deeds per step (`ECHOES`). Tests: `tests/test_region1_story_full.gd` (whole-story autoplay, save/load at 4 points, journal + tracker for every step), `tests/test_region1_story_world.gd` (real-world place, water and wardline-feed checks) | `r1_story_director.gd`, `region1_places.gd`, `region1_glue.gd`, `region1_creatures.gd`, `life.gd`, `r1_main.json`, `r1_registry.json` |
Cutscenes: only the Blessing (the game's own age-12 ceremony) is used; other `cutscene` actions are short in-world staging (banner, music cue, camera nudge).

### Acceptance-test toolkit (existing)
- Screenshots: `godot --path kingdom -- --shot=<name> --out=<png>` (`main.gd`; supports `site_<kind>`, `interior_<name>`, `city`, `guild` …). Add new shot names for new sites.
- Frame sheets: `tools/qa/video_to_sheets.sh` (skill `ashes-video-review`) for any motion or VFX.
- Tests: gdUnit4 (`kingdom/tests/`, 84 files today). Perf: `tools/qa/bench`, `docs/qa/PERFORMANCE.md` (target 60 fps high tier, 30 fps low tier, no hitch over 50 ms).

### M0: canon and scaffolding
| ID | Owner | Package | Inputs → outputs | Depends | Acceptance |
|---|---|---|---|---|---|
| **C0** | cloud | **Canon data**: nation display names, Church realms and new nations as data rows, poster places (Highwatch Keep, Silverford alias, Crownstead, Greenhollow, Elden Road, Stagborn Glade, 5 Elder Stones, Eastern Gate, Grimfen Pass, Ashen Scar) in `data/world/first_region.json` + `nations.json`; banner on `GDD.md` / `KINGDOM_DESIGN.md` **[DONE 2026-09-30 (nations renamed, teaser realms, poster places in first_region.json, banners; see WORLD_R1.md)]** | §0 tables → JSON + docs | owner OK on §0 | `RAWorldLore` tests pass; world map shows new names (screenshot) |
| **L0** | local | **Region1 scaffold**: `scripts/region1/region1_root.gd`, `region1_state.gd` (snapshot and restore registry), `data/region1/README.md`, test harness `tools_qa/region1/region1_sandbox.tscn` (a standalone scene that runs sims without `main`) | → new files | — | Sandbox runs headless; gdUnit smoke test |
| **C-H** | cloud | **Hooks H1 + H2** | L0 → 3 lines | L0 | Save/load round-trip keeps `region1` data (test) |

### M1: the region is physically complete
| ID | Owner | Package | Inputs → outputs | Depends | Acceptance |
|---|---|---|---|---|---|
| **L1** | local | **Elder Stone + runestone variants**: hero Elder Stone (Meshy or `meshy_free/magic` runestones → Blender cleanup, LOD0/1, emissive glyph channel mask), 4 road-stone variants, ancestor-gold material | → `assets/incoming/region1/stones/` + contact sheet | — | ≤ 6k tris LOD0; contact sheet in the style check; glow reads at 60 m (screenshot) |
| **L2** | local | **Highwatch Keep kit** from the `meshy_free` castle pieces (27) + armored guard/knight props; a modular set placeable as one site | → `assets/incoming/region1/highwatch/` + `site` JSON layout | — | Draw calls ≤ 40 for the site; 3/4 and top preview; storybook palette |
| **L3** | local | **Silverford guild hall + chapel of the Dawn Throne** (Meshy or `meshy_free` churches, warm white and gold Church palette) + interiors (new `scenes/interiors/guildhall_interior.tscn`, `chapel_interior.tscn`) | → assets + interior scenes | — | `--shot=interior_guildhall`, `interior_chapel` |
| **L4** | local | **Rift-touched kit**: violet foliage variants (material swap on the existing nature GLBs), scar-crystal clusters (`meshy_free` crystals), rift ground decals, rift-wolf/boar material variants, import check for `rift_slime` / `rift_wraith` | → `assets/incoming/region1/rift/` | — | Side-by-side normal vs rift sheet; still reads as the sunny look, not grimdark |
| **L5** | local | **Stagborn models**: Stagborn elk (herd) and the Antlered Warden (Meshy rigged, idle/walk/run/attack/hit/death; LOD1) | → `assets/incoming/ai3d/meshy/creatures/stagborn_*` | — | Turntable frame sheet; tris ≤ 8k / 15k |
| **C1** | cloud | **Region layout**: add sites to `region_sites.gd` (Highwatch Keep, Elder Stones ×5, Stagborn Glade, Eastern Gate, Grimfen Pass barrier, Crownstead estate, Rift-mouth arena); pick the Silverford town; place L1–L3 **[DONE 2026-09-30 (Highwatch Keep, 5 Elder Stones, Eastern Gate, Grimfen Pass, Scar Mouth Arena, Crownstead Steward's Hall, Dawn chapel, Silverford = Ironmarch; see WORLD_R1.md)]** | L1–L3 → site entries | C0, L1–L3 | `--shot=site_<kind>` for each; no tree intersection; fps unchanged ±5 % |
| **C2** | cloud | **Settlement identity**: one trade, landmark, named NPC and rumour set per settlement; place `meshy_free` market, farm and water props **[DONE 2026-09-30 (20 settlements: trade, landmark, named NPC, rumours)]** | C0 → data + dressing | C1 | Screenshot per settlement (12); a playtester can name each town from its screenshot |
| **L6** | local | **Mine and Rift pocket interiors**: a short Greyseam tunnel with a rift seam, and the Scar-mouth arena room | → `scenes/interiors/mine_interior.tscn`, `scar_arena.tscn` | L4 | `--shot=interior_mine`; ≤ 150 draws |

### M2: signature mechanics playable
| ID | Owner | Package | Inputs → outputs | Depends | Acceptance |
|---|---|---|---|---|---|
| **L7** | local | **Wardlines sim** `scripts/region1/wardlines.gd`: Elder Stone budgets, routing graph, player links, coverage override, rumours on change | `RARunestoneNetwork` API → pure sim + tests | L0 | gdUnit: routing conserves budget; cutting a link drops coverage on the right road; deterministic by seed |
| **L8** | local | **Rune gesture recognizer** `rune_gesture.gd` + `data/region1/glyphs.json` (ward, lure, alarm, bless) + test canvas in the sandbox | → module + canvas | L0 | ≥ 95 % recognition on 40 recorded strokes per glyph; < 1 ms per match; frame sheet of the canvas |
| **L9** | local | **Scar Tide sim** `scar_tide.gd`: 32 m grid, seasonal spread, ward and fire containment, mutation tables, `scar_mask` ImageTexture output | → sim + tests + debug PNG | L0, L7 | 60-day headless run PNG sequence; the tide never crosses a glowing-stone cell; tick < 2 ms |
| **L10** | local | **Ember Legacy** `ember_legacy.gd`: ember choices, ancestor-stone data, heirloom item, bark templates from the biography | `family.gd`, `echoes.gd`, `biography.gd` → sim + tests | L0 | Tests: stone power bonus, echo inherited, heirloom persists through save |
| **L11** | local | **Ashsight** `ash_memory.gd` (event ring buffer, 1 Hz path samples within 60 m of flagged events, cooling timer) + `ash_ghost.tscn` (grey ghost shader, pooled) | → module + scene | L0 | Sandbox: record a fake raid, replay matches paths within 1 m; frame sheet of the ghost look; ≤ 0.3 ms per frame |
| **L12** | local | **Mechanic VFX**: ward-line beam, glyph stroke trail + stone flare, scar front shimmer, burn-back fire line, ember soul rise, ancestor-gold glow | `element_fx.gd` API → `scenes/vfx/region1/*` | L1, L4 | Stop-motion sheets; Compatibility renderer check; pooled, with no hitch |
| **L13** | local | **Mechanic UI** (standalone controls): runecarve canvas, ward map layer, scar overlay, ember 3-card radial, Ashsight scrub bar, in the dark-gold style (`ashes_frame.gd`) | → `scripts/region1/ui/*` | L7–L11 | 2400×1080 and 4:3 screenshots; touch targets ≥ 48 dp |
| **C3** | cloud | **Integrate N1**: stone interaction → canvas, H3 coverage, H6 map layer, Runeward career rank hook | existing scripts → small hooks | L7, L8, L13 | Carve a stone in game → coverage change visible on the map and in wolf behaviour (video sheet) |
| **C4** | cloud | **Integrate N2**: H4 variants, H5 terrain tint, economy goods (scar crystal, scarbloom), burn and ward actions | existing scripts → small hooks | L9, L4 | Screenshot of the violet front; prices react (test); fps ±5 % |
| **C5** | cloud | **Integrate N3**: H7 death/retire → ember choice → ancestor stone barks via `Game.say` / talk | existing scripts → small hooks | L10, L13 | New-life playthrough: the ancestor stone greets the heir (screenshot + log) |
| **C6** | cloud | **Integrate N4**: event emitters (`road_events`, `monster_ecology`, `runestone_network`) → `ash_memory`; interact at a cooled site | existing scripts → small hooks | L11 | A real sim raid replays in game (frame sheet) |

### M3: story, onboarding and cast
| ID | Owner | Package | Inputs → outputs | Depends | Acceptance |
|---|---|---|---|---|---|
| **L14** | local | **Main quest content** "The Stones Are Dimming", Acts I–V: quest step data (`data/region1/quests/*.json`) + dialogue JSON in the `dialogue_runner` format; 12 named cast bios | §3 story → new data files | C0 | Lint script validates every step, speaker and flag; the owner reads the script |
| **L15** | local | **Side quests** (12–15, one or two per settlement, each using a mechanic or career) as data + dialogue | → data | L14 | Lint passes; each quest names its settlement, NPC, reward and mechanic |
| **L16** | local | **Tutorial director** `scripts/region1/tutorial_director.gd`: contextual prompt queue (move, look, talk, interact, eat, sleep, fight, block, dodge, carve, map), skip and replay, touch-first art | → module + prompt strings (`locale/strings.csv` en/nl rows, new file if needed) | L0 | Sandbox demo sheet; each prompt dismisses on the real action |
| **C7** | cloud | **Quest runtime wiring**: step triggers (enter area, talk, kill, carve, ashsight, festival), quest tracker pin on the HUD, compass markers, rewards, Journal tab | existing scripts → small hooks | L14, L15 | Headless autoplay completes Act I; Quests tab shows correct steps |
| **C8** | cloud | **Onboarding flow**: birth → first 20 minutes with L16 prompts, a safe first fight (one wolf at the ring edge at dusk), first stone repair; apply `boot_wiring_wip.patch` | existing scripts → small hooks | L16 | New player reaches "first glyph" in ≤ 20 min in a playtest-bot run; screenshots per step |
| **C9** | cloud | **Cutscenes**: Blessing ceremony, Elder Stone relight, finale (shot lists for `cutscene_player.gd`) | existing scripts → small hooks | L14 | Frame sheets of each cutscene |
| **C10** | cloud | **Border teases**: Eastern Gate post + pilgrims, Solkar caravans at the Midsummer Fair, Grimfen Pass snow barrier, envoy chapel NPC **[DONE 2026-09-30 (Eastern Gate + pilgrims, Solkar camp in summer, Grimfen snow barrier, Envoy Lucan; map exits). Ambient pilgrim traffic on the road is still open]** | existing scripts → small hooks | C1, L3 | Screenshots; map shows locked exits with hints |

### M4: combat and creatures
| ID | Owner | Package | Inputs → outputs | Depends | Acceptance |
|---|---|---|---|---|---|
| **X1** | Codex | **Wire the clip libraries**: `animations_free` + `animations_free2` into `Assets.UAL_FILES`; life-sim clips for chop, mine, fish, hammer and pick-up | libraries → `assets.gd` UAL section | — | Import check; stop-motion sheet per clip family in game |
| **X2** | Codex | **Runecarve and maintain animations**: kneel-and-trace loop, palm-on-stone flare, Ashsight kneel | clips → controller | X1 | Front and side frame sheets, no foot slide |
| **X3** | Codex | **Stagborn behaviour**: herd graze, alert, flee, antler charge; the Antlered Warden's 3-phase moveset with telegraphs | clips → controller | L5 | Frame sheets; herd flees the player but charges a wolf |
| **X4** | Codex | **Humanoid duel controller**: bandits, Ashen Hand saboteurs, Highwatch sparring (armored Meshy models, weapon in `RightHand`) | clips → controller | X1 | 1v1 and 1v3 videos; attack tokens respected |
| **X5** | Codex | **Bow**: player draw, aim and release on touch (hold-to-aim, auto-assist) + bandit archers | clips → controller | X1 | Hit test; frame sheets |
| **X6** | Codex | **Boss: the Scarbound Troll**: phases, arena hazards (scar crystals), stagger windows | clips → controller | L6, X1 | Full-fight video sheet; beatable at the target progression |
| **X7** | Codex | **Riding**: ride idle, walk, trot, gallop on `mount_controller.gd` with the riding horse | clips → controller | X1 | Frame sheets at every gait; no foot slide |
| **C11** | cloud | **Creature placement and ecology tuning**: Stagborn herds and migration, rift variants from Scar cells, ghoul, wasp and bog toad dens, bandit roster **[DONE 2026-09-30 (placement: Stagborn herds + migration, Warden, ghoul/wasp/toad/rift dens, bandit rosters). Behaviour is Codex X3/X4]** | existing scripts → small hooks | X3, X4, C4 | 3-day headless ecology log; screenshot per creature in habitat |

### M5: polish and balance
| ID | Owner | Package | Inputs → outputs | Depends | Acceptance |
|---|---|---|---|---|---|
| **L17** | local | **Region audio**: 6 area themes (from incompetech, music-cc-by and OpenGameArt; licences checked), rune hum and ward SFX, Stagborn calls, Scar ambience, boss theme, 20 voice barks (grunts and greetings) | → `assets/audio/region1/` + `CREDITS` | — | Loudness −16 LUFS ±1; licence table |
| **C12** | cloud | **Audio wiring**: area → theme map in `audio_director.gd` (small hook), mechanic SFX call sites | existing scripts → small hooks | L17 | Walk the region: themes switch at the right borders (log) |
| **L18** | local | **Balance simulator** `tools_qa/region1/balance_run.gd`: 100 headless days for 3 archetypes (farmer, soldier, Wardwright) → CSV of gold, rank, soul tier and gear | → tool + report | M2 | Report in `docs/regions/BALANCE_R1.md`: first house ≤ 25 days, Captain ≥ 60 days, no infinite-money loop |
| **C13** | cloud | **Balance fixes + progression spine**: end-of-region targets (soul tier 3–4, career rank 4–5, gear tier 2) and the Rift gate | existing scripts → small hooks | L18 | Re-run meets targets |
| **L19** | local | **Performance pass on the full region** (new sites, Scar tint, ghosts, VFX) on high and low tiers | → new files | all | `docs/qa/PERFORMANCE.md` updated; 60 / 30 fps held; no hitch over 50 ms on a 10-minute route |
| **L20** | local | **Region 1 review**: aaa-review loop, stop-motion sheets of every mechanic, screenshot atlas of every sub-area | → new files | all | `docs/regions/REGION_1_REVIEW.md` with pass/fail per DoD item |

### Launch order (parallel lanes)
1. **Now, in parallel:** C0 · L0 → C-H · L1 · L2 · L5 · X1 · L17
2. **Then:** L3 · L4 · L7 · L8 · L10 · L11 · L14 · L16 · X2 · X4
3. **Then:** C1 · L9 · L12 · L13 · L15 · X3 · X5 · X7
4. **Then:** C2 · C3 · C4 · C5 · C6 · L6 · C7 · C8
5. **Then:** C9 · C10 · C11 · X6 · C12 · L18
6. **Last:** C13 · L19 · L20

---

## 5. Milestones and definition of done

| Milestone | Contents | Exit check |
|---|---|---|
| **M0 Canon and scaffold** | C0, L0, C-H | Names settled; `region1` saves round-trip |
| **M1 Physically complete** | L1–L6, C1, C2 | Every sub-area in §1.2 exists with a screenshot; fps within 5 % of today |
| **M2 Signature mechanics** | L7–L13, C3–C6 | N1–N4 each playable end to end in the main game, with video sheets |
| **M3 Story and onboarding** | L14–L16, C7–C10 | Act I–V completable; a new player reaches the first glyph in ≤ 20 min |
| **M4 Combat and creatures** | X1–X7, C11 | Stagborn, rift variants, bandit duels, bow, riding and the boss all in game |
| **M5 Polish and balance** | L17–L20, C12, C13 | DoD below is all green |

### Definition of done: "Region 1 complete"
1. **World:** all sub-areas in §1.2 are placed, named on the map, discoverable, and dressed in the storybook style. Each of the 12 settlements has its own trade, landmark, named NPC and rumours.
2. **Story:** "The Stones Are Dimming" is playable from birth to the finale with no blockers. 12 or more side quests. Four cutscenes (birth, Blessing, Elder Stone, finale). A "Region 1 complete" moment unlocks the post-game (keep living: careers, lordship and family continue).
3. **Mechanics:** Wardwright, Scar Tide, Ember Legacy and Ashsight all work in the main game, save and load correctly, and are taught in context.
4. **Onboarding:** the first 20 minutes are guided, skippable and touch-first. The playtest bot and one human playtest finish Act I without help.
5. **Combat:** melee, techniques, bow, riding; enemies include wolves, boars, bandits, goblins, orcs, Stagborn, rift variants and the boss. Every enemy clip passes the frame-sheet review.
6. **Economy and progression:** a 100-day balance run meets the targets; no exploit loops; the end-of-region power spine is met.
7. **Audio:** area themes, mechanic SFX, creature voices; no silent areas.
8. **Teasers:** the Eastern Gate, Grimfen Pass, Solkar caravans and the Rift glimpse all point to the posters' future regions.
9. **Tech:** 60 fps on the high tier and 30 fps on the low tier on the reference phones, no hitch over 50 ms, save size under 2 MB, all gdUnit tests green, Android export builds.
10. **Review:** `docs/regions/REGION_1_REVIEW.md` shows every item above passed, with screenshots and frame sheets.
