# Rising Ashes: World Lore

A readable summary of the peoples and powers. **The data files are the source of
truth**. This page describes them; code reads the JSON.

| Data | File | Loader |
|---|---|---|
| Races | `kingdom/data/world/races.json` | `RAWorldLore.race(id)` |
| Cultures | `kingdom/data/world/cultures.json` | `RAWorldLore.culture(id)`, `random_name(culture, rng)` |
| Nations | `kingdom/data/world/nations.json` | `RAWorldLore.nation(id)`, `stance(a, b)` |
| Sects, schools, academies | `kingdom/data/world/sects.json` | `RAWorldLore.sect(id)`, `sects_with_xiava_access()` |
| Tribes and bloodlines | `kingdom/data/world/tribes_bloodlines.json` | `tribe(id)`, `bloodline(id)`, `roll_bloodline(...)` |
| First region places | `kingdom/data/world/first_region.json` | `places_in_region(kind)`, `place(id)` |
| Military ladder | `kingdom/scripts/sim/military.gd` | `RAMilitary` |

Tone: original fantasy in the spirit of donghua/xianxia cultivation, sect
rivalries, monster evolution and naming, and cultures bound to an element whose
"bending" is a martial art. All names here are this world's own.

---

## Races

| Race | Kind | Lifespan (typical / max) | Magicules | Evolution | Can others become it? |
|---|---|---|---|---|---|
| **Human** | civilised | 70 / 110 | 0.45 | none | no (the usual *source* of a blood rite) |
| **Orc** | civilised monster race | 55 / 90 | 0.35 | Orc → High Orc → Orc Warlord → Orc Sovereign | yes: the Tusk Pact (human, goblin) |
| **Goblin** | monster | 18 / 40 | 0.25 | Goblin → Hobgoblin → Goblin Knight *or* Goblin Hexer → Goblin Lord | no |
| **Beastkin** (wolf-, fox-, bear-, hawk-, tigerkin) | civilised | 65 / 100 | 0.40 | Beastkin → Greater → Primal | yes: totem adoption, bloodline awakening (human) |
| **Veyl** (elf-like forest folk) | civilised | 450 / 900 | 0.80 | Veyl → High Veyl → Star Veyl | no |
| **Durrow** (dwarf-like stone folk) | civilised | 240 / 350 | 0.50 | Durrow → Deepforged Durrow | no |
| **Drakari** (dragonkin) | civilised | 300 / 1200 | 0.95 | Drakari → Wyrmblooded → Ascendant | yes: dragon blood replacement (human, beastkin); much safer with the Wyrmvein bloodline |

Evolution needs level plus accumulated magicules; for monsters, **being named**
can substitute for the first step. Naming costs the namer magicules and can cost
levels or cause injuries that a healer must treat.

---

## Cultures (each bound to an element and an art)

| Culture | People | Element | Art | Martial affinity | Name order | Greeting |
|---|---|---|---|---|---|---|
| **Caldric** | human, Caldrenn | earth | *Stonesetting*: rooted stances, runestone waking | spear, shield, runecraft | Given Family | "Hearth keep you." / "And stone guard you." |
| **Seirune** | human, eastern isles | water (+ lightning) | *Tideweaving*, *Stormstitch* flash-step | blade, hidden arts | Family Given | bow: "The tide returns." |
| **Ongur** | human, steppe | wind | *Windstriding*: gallop-standing, curving arrows | bow, horse, sabre | Given "of the Clan" | "Is your horse strong?" / "As the wind." |
| **Solenne** | human, theocracy | fire (+ light) | *Flamecanting*, the white Dawnflame | mace, greatsword, healing | Given Family | "Dawn upon you." / "And never dusk." |
| **Urrokai** | orc | blood | *Bloodroar*: breath, heartbeat, war-cry | axe, cleaver, grapple | Given Family | forearm clasp: "Strong blood." / "Stronger clan." |
| **Shenlu** | human, mountain sects | lightning (+ metal) | *Thunderstep*: cultivated inner current | sword, fist, cultivation | Family Given | fist-in-palm: "May your path ascend." |
| **Veyl** | veyl | wood | *Rootsong*: vines, bark-skin, beast bonding | bow, glaive | Given "of the Grove" | "Root and bough." |
| **Durrow** | durrow | metal (+ fire) | *Forgeheart*: hammer-rhythm, stored heat | hammer, axe, crossbow | Given Family | two knocks on the chest: "Stone and fire." |

Each culture in the JSON also lists architecture keywords (for example Caldric:
timber frame, thatch, fieldstone, runestone circle), a clothing palette with hex
colours, values, foods and festivals (Kindling Night, Thousand Lanterns, Games of
the Three Winds, Dawnrise, The Tusking, Ascending Peaks Tournament, Night of
Falling Light, Founding Fire...).

---

## Nations

| Nation | Where | Government | Culture | Capital | Special divisions |
|---|---|---|---|---|---|
| **Kingdom of Caldrenn** (home) | first region | feudal monarchy (King Aldric III; Council of Wardens) | Caldric | Kingsreach | Runeward Legion, Ember Lancers, Royal Soulbeast Riders |
| **Isles of Seirune** | east, over the Glass Strait | sacred Tide Empress with a military Regent | Seirune | Umikage | **Veiled Lantern Corps** (shinobi-like), **Oathblade Retinue** (samurai-like) |
| **Ongur Khanate** | north-east steppe | elective khanate | Ongur | Kharun Camp (moves) | Thousand Winds Horde, Skyhawk Riders |
| **Solmarch Theocracy** | south | theocracy (Hierarch, Flame-Bishops) | Solenne | Aurelion | Dawnflame Paladins, Penitent Host |
| **Urrokai Clanlands** | west | tribal confederacy (Warchief) | Urrokai | Grakmoor | Bloodtusk Berserkers |
| **Shenlu Peaks Covenant** | far north mountains | sect covenant: the sect masters rule | Shenlu | Ninefold Summit | Ninefold Sword Guard |
| **Veylwood Concord** | south-west forests | council of elders | Veyl | Silverbough | Thornwarden Rangers |
| **Hollowdeep Holds** | north-west, under the Greyspine | guild oligarchy (Hammer Moot) | Durrow | Karnhollow | Anvil Guard |

Caldrenn's towns are exactly WorldGen's settlements (Ashford, Kingsreach,
Millbrook, Stonehollow, Eastmere, Redwater, Thornfield, Greywatch, Oakvale,
Highcliff, Brackenmoor, Westfen). Relations are mutual and use six stances:
allied, friendly, neutral, wary, hostile, war. Notable ones: Caldrenn and
Veylwood are allied; Caldrenn and the Urrokai are hostile; Solmarch and the
Urrokai are at **war** (an eleven-year crusade).

---

## Sects, schools and academies

| Name | Type | Nation / seat | Discipline | Xiava |
|---|---|---|---|---|
| **Royal Ember Academy** | academy | Caldrenn / Kingsreach | sword, spear, elemental arts, beast taming, statecraft | **yes** |
| **Ninefold Sword Pavilion** | sect | Shenlu / Ninefold Summit | sword, lightning, cultivation | **yes** |
| **Verdant Oath Sanctuary** | sect | Veylwood / Mistwillow | beast taming, wood arts, bow | **yes** |
| Iron Lotus Monastery | sect | Shenlu / Stone Lotus Village | fist, palm, body tempering | no |
| Greywatch Spear Hall | school | Caldrenn / Greywatch | spear, shield, earth arts | no |
| Old Mill Staff Yard | school | Caldrenn / **Ashford** | staff, fist (village teacher Maren Coldbrook, a former Runeward officer) | no |
| Hall of the Four Currents | academy | Seirune / Tsukiharu | elemental arts | no |
| School of the Hollow Moon | sect (hidden) | Seirune / Oboroshima | hidden arts, infiltration, poison | no |
| Seminary of the Dawnflame | academy | Solmarch / Aurelion | fire and healing arts | no |
| Windstep Riders' Lodge | school | Ongur / Kharun Camp | bow, riding, wind arts | no |
| Brotherhood of the Anvil | school | Hollowdeep / Karnhollow | hammer, forge arts | no |

Every sect lists entry requirements (age range, minimum talent, affinity, a
test, a fee, allowed races) and a rank ladder. For example, the Ninefold
Pavilion runs Servant, Outer, Inner, Core and True Disciple, then Sword Elder,
Grand Elder and Pavilion Master.

**Xiava's Lake**, the land of soulbeasts and a later region, can be reached only
with a Xiava Writ. Three holders exist: the Royal Academy and two sects.
Soulbeasts are meant to be very rare.

---

## Tribes and bloodlines

Tribes include:
- the **Tuskridge Clan**: exiled orcs near Ashford, chief Harrok Ashmaw.
- the **Mossfang Warren**: goblins, led by Snikkit the Twice-Bitten, close to becoming a hobgoblin.
- the Greymane wolfkin pack.
- Ongur tribes: Seven Hooves and Red Sky.
- orc clans: Ironhide and Bloodtusk.
- the Sunscale Foxkin.
- the Durrow Deepdelver Clan.

Bloodlines carry dormant traits that awaken on a trigger, which ties into the
hidden, age-gated design:

| Bloodline | Rarity | Awakens when... |
|---|---|---|
| Ashen Phoenix | legendary | a child (8+) survives fire that should have killed them |
| Thunder Crane | legendary | someone meditates on Ninefold Summit in a storm (16+) |
| Wyrmvein | epic | they touch a true dragon's relic; makes the Drakari rite survivable |
| Moonshade | epic | they pass a night unseen in an enemy camp |
| Stormeye, Tidecaller, Dawnblood | rare | lightning, near-drowning, self-sacrificing healing |
| Stoneheart, Skywind, Verdant Pulse | uncommon | holding ground, a fall into the wind, befriending a beast |
| Iron Tusk | common (orc) | winning a clan challenge |

Birth chances by rarity run from 8% (common) to 0.01% (legendary).

---

## Military ranks (`RAMilitary`)

Unit sizes follow the depth of historical Chinese military organisation:

| Unit | Size | Led by |
|---|---|---|
| Hand | 5 | Leader of Five |
| Squad | 10 | Tenwarden |
| Banner | 50 | Banner Sergeant |
| Company | 100 | Captain of a Hundred |
| Battalion | 500 | Warden of Five Hundred |
| Regiment | 2,500 | Standard Commander |
| Army | 12,500 | Field General |
| Host | several armies | Grand Marshal |

The ladder has 15 grades. Merit, pay and command never decrease going up. Pay
is gold per day and matches the village guard career: guard 9, sergeant 18,
captain 30.

| Grade | Rank | Command | Merit | Pay |
|---|---|---|---|---|
| enlisted | Levy Recruit | 1 | 0 | 7 |
| enlisted | Sworn Soldier | 1 | 25 | 9 |
| enlisted | Seasoned Blade | 1 | 60 | 11 |
| NCO | Leader of Five | 5 | 90 | 13 |
| NCO | Tenwarden | 10 | 130 | 15 |
| NCO | Banner Sergeant | 50 | 190 | 18 |
| officer | Second of the Hundred | 100 | 280 | 24 |
| officer | Captain of a Hundred | 100 | 400 | 30 |
| officer | Battalion Second | 500 | 600 | 38 |
| officer | Warden of Five Hundred | 500 | 850 | 48 |
| officer | Standard Second | 2,500 | 1,200 | 62 |
| officer | Standard Commander | 2,500 | 1,600 | 80 |
| general | Vice General | 12,500 | 2,400 | 105 |
| general | Field General | 12,500 | 3,200 | 140 |
| general | Grand Marshal | 25,000 | 6,000 | 240 |

Merit only makes someone *eligible*. A real promotion still needs a vacancy and
a superior who signs for it (`RACareers`).

**Per-nation overrides** change titles and apply a pay multiplier; thresholds and
command sizes stay the same:
- Seirune ×1.1: House Captain, Tide Commander...
- Ongur ×0.8: Hundred-Khanling, Horsetail Lord...
- Solmarch ×0.9: Knight-Captain, Lord Preceptor...
- Urrokai ×0.5: War-Band Chief, Clan Warlord...
- Shenlu ×1.2
- Veylwood ×1.0
- Hollowdeep ×1.3

**Special divisions** have entry requirements (minimum rank and merit, plus
skills, sect training, race, affinity, a soulbeast bond or a warhorse) and a
daily pay bonus. For example, the Veiled Lantern Corps needs Sworn Soldier rank,
100 merit, Hollow Moon training and stealth 40. The Royal Soulbeast Riders need
Banner Sergeant rank, 400 merit, Royal Academy training and a soulbeast bond.

API:
- `rank_for_merit(merit)`, `next_rank(id)`, `merit_to_next(id, merit)`
- `command_size(id)`, `pay(id, nation, division)`, `title(id, nation)`
- `check_division(div, candidate)`
- `build_formation(troops, nation)`: a formation tree whose leaves (Hands of at most five) sum to the troop count
- `formation_troops`, `formation_counts`
- roster instance: `enlist`, `add_merit`, `promote`, `join_division`, `daily_pay`, `serialize` / `deserialize`

---

## The first region: the Ashford Vale

Coordinates are metres on the ground plane (x, z) from Ashford at (0, 0), in the
4 × 4 km streamed world (seed 1066). North is -z, matching WorldGen, where
Kingsreach sits at (560, -420).

| Place | Kind | Position (x, z) | Distance | Notes |
|---|---|---|---|---|
| Ashford | village | (0, 0) | 0 m | home |
| Kingsreach | capital | (560, -420) | 700 m | royal castle-city, NE |
| The King's Ember Road | road | (0, 0) → (288, -199) → (560, -420) | 700 m long | WorldGen's Ashford–Kingsreach road |
| Cinderpost Waystation | waystation | (288, -199) | 350 m | halfway post: stable, bunkhouse, patrol |
| Emberglass Mere | lake | (-420, 300), r 90 | 516 m | SW; fishers' jetty on the east shore |
| The Ashrun | river | (-150, -900) → (-330, -150) → Mere → (-1500, 1200) | 9 m wide | from the northern hills, through the Mere, SW to Westfen |
| Ashrun Bridge | bridge | (-318, -214) | 383 m | where the Oakvale road crosses the Ashrun |
| Duskbriar Wood | forest | (380, 480), r 330 | 612 m | SE, beyond the runestone ward |
| Mossfang Warren | goblin warren | (560, 250) | 613 m | Duskbriar's northern edge |
| Tuskridge Hold | orc village | (300, 930) | 977 m | hilltop beyond the wood; Chief Harrok Ashmaw |
| Shrine of the Sleeping Flame | ruined shrine | (-700, -160) | 718 m | hilltop west of the Ashrun; hidden age-8 trigger |
| Whisper Hollow | hidden place | (-560, 520) | 764 m | on the Ashrun below the Mere |
