# Retinue, Settlement and Ascension

**From a nobody to a warband leader, settlement founder and lord, then king by merit or marriage.**

This is the design for recruitment and the retinue, the Call, taming, settlement founding and building, threats and grudges, conquest and politics, and the road to the throne of Valencious.
Written 2026-09-29 from `origin/claude/focused-curie-m09hbd`, after a read-only survey. Standard: skill `ashes-game-design`. Execution: skill `ashes-work-package`.

It builds on:
- `docs/regions/REGION_1_PLAN.md` (Wardwright N1, Scar Tide N2, Ember Legacy N3, Ashsight N4; packages L0–L20, C0–C13, X1–X7; hooks H1–H7)
- `docs/regions/OWNER_DECISIONS.md` (poster names on screen, data ids kept)
- `docs/RISING_ASHES_LIFE_SIM_DESIGN.md` and `docs/RISING_ASHES_OPEN_WORLD.md` ("becoming king is never a level-50 perk; there must be an actual path")
- `docs/WORLD_LORE.md` and the five posters in `docs/art/regions/`

Time scale used throughout (existing code): **1 game day = 720 real seconds** (`WorldSim.DAY_LENGTH`), **1 year = 12 days** (`RALifePath.DAYS_PER_YEAR`), **1 season = 28 days** (`seasons.gd`). Adulthood starts at 16 (day 192 of a life). "Adult day N" means N days after the character turns 16. Money is **gold**. A villager earns 5–15 gold a day (`WorldSim.WAGES`), a loaf costs 2, an iron sword 45 and a horse 60 (`data/items.json`).

---

## 0. What already exists and how this design reuses it

| Existing (path under `kingdom/`) | What it gives us | Role here |
|---|---|---|
| `scripts/region1/region1_sim.gd`, `region1_state.gd`, `region1_root.gd`, `data/region1/modules.json` (L0) | Deterministic `RefCounted` sims, versioned save registry under `region1` in `Life.snapshot`, 1 s ticker, presenters | **Every new sim extends `Region1Sim` and goes live with one `modules.json` row.** No new save hook is needed (H2 covers it). |
| `autoload/world_sim.gd` (~20,000 people as packed rows) + `scripts/population/*` (LOD, utility brain, street graph) | Every person already exists as data | Recruits are WorldSim rows with a retinue flag, not new actors. Settlers get rows. |
| `scripts/sim/relationships.gd` | Opinion −100..100 with fading modifiers; tiers up to enemy; faction reputation | Individual and faction layers of enmity; loyalty modifiers; grudge seeds |
| `scripts/sim/careers.gd` (seats with vacancies, wages) | Jobs have real seats | Hiring someone empties their seat; council seats reuse the seat model |
| `scripts/sim/naming.gd` (`RANaming`: named subordinates, loyalty, desertion, Soul Name bonds) | Goblins, wolves, orcs, kobolds and others as named followers | Named monsters join the retinue as the "monster" recruit type |
| `scripts/sim/lordship.gd` + `ui/lord_council.gd` + `world/lord_hall.gd` | A held village: treasury, tax, loyalty 0..100, food, militia, issues, projects, unrest at 25, revolt at 8 | The governing layer for every holding. A founded settlement at Village tier registers here with reason `founded`. |
| `scripts/sim/nobility.gd` + `ui/nobility_screen.gd` + `world/noble_courts.gd` | 6 noble houses, fiefs, mills, bridges, tolls, feuds, sales, loans, audiences | Charters are bought here; houses vote in the Moot; feuds become Writs of Feud |
| `scripts/sim/family.gd` (courtship stages, arranged noble marriages, heirs, succession) | Marriage and succession | The royal suit extends its stages; succession feeds the Ember Legacy (N3) |
| `scripts/sim/homestead.gd` + `ui/build_menu.gd` + `world/homestead_view.gd` | 2 m grid, catalogue with gold and materials, rotation, crops, farm hands | The build grid generalises this; the homestead becomes the "Freehold" tutorial plot |
| `scripts/army/squad.gd`, `soldier.gd`, `morale.gd`, `formation.gd`, `sim/military.gd`, `sim/war_sim.gd` | Formation AI (one brain per 100 men), morale, 6 formations, ranks Hand (5) to Army (12,500), War Merit Ledger, war with a neighbour | Warband squads, raids, sieges and levies; merit feeds knighthood |
| `scripts/sim/monster_ecology.gd`, `runestone_network.gd`, `autoload/frontier.gd`, `sim/threat_map.gd` | Dens, apex migration, stone coverage, threat per cell | Taming sources, claim rules, raid pressure, Call delays |
| `scripts/world/road_events.gd` | Bandit ambushes on rural and frontier roads (bandits ignore runestones) | Robbers scale with wealth and visibility |
| `scripts/actors/mount_controller.gd` | Walk, canter, gallop; claims a Critter as the mount | Horse and Stagborn mounts; mounted Call speed |
| `scripts/sim/economy.gd`, `market.gd`, `caravans.gd` | A market per settlement, drift, war and festival modifiers, carts, contracts | Settlement trade, food prices, raid targets |
| `scripts/sim/injuries.gd`, `needs.gd`, `soul.gd` (12 soul tiers), `titles.gd`, `biography.gd` | Injuries, hunger, power tiers, titles, life log | Follower injuries, tame gates, deeds, grudge origin text |
| `addons/road-generator` (RoadManager, RoadContainer, RoadPoint, RoadLane) | Spline roads with lanes, currently unused | Finger-drawn settlement roads |
| `addons/gloot` | Inventory | Settlement storage and follower kit |
| `addons/limboai` (0 uses so far) | Behaviour trees | Follower and beast near-player behaviour (X packages) |
| `addons/quest_weaver`, `dialogue_runner.gd` (5 JSON dialogues) | Quest and dialogue plumbing | Companion quests and royal suit dialogue in the L14 format |
| `addons/GodotGAS` | Attributes and effects | Beast bond abilities and follower buffs (optional; plain dictionaries are fine) |

**Integration rules.** These are the same rules as Region 1 §4, with a new folder:
- Sims go in `kingdom/scripts/ascension/` (`extends Region1Sim`, module names `asc_*`) and presenters and UI in `scripts/ascension/ui/`.
- Data goes in `kingdom/data/ascension/*.json`, tests in `tests/test_asc_*.gd`, and sandboxes in `tools_qa/ascension/`.
- Pure sims never touch `Game.gold` or autoloads. A single non-pure adapter, `scripts/ascension/asc_bridge.gd`, moves gold, reads `WorldSim`, `Frontier` and `Life`, and spawns bodies.
- Hot files are no-touch for L. The cloud applies hooks H8–H14 (§10.1).

---

## 1. Pillars and fantasy

| # | Pillar | Rule it enforces |
|---|---|---|
| P1 | **People are the resource.** | Every follower is a WorldSim person with a home, a family, a wage and an opinion. Nothing is a unit card. |
| P2 | **Bread before banners.** | Food, wages and shelter limit power before combat does. The first winter is the first boss. |
| P3 | **Power is earned in public.** | Rank, favour and legitimacy come from logged deeds (the War Merit Ledger plus the Deeds ledger), never from XP. |
| P4 | **The land remembers.** | Every wrong can grow a grudge. Every meal given is a debt. Ashsight can show both. |
| P5 | **The stones decide.** | Where you settle, how fast help arrives and who may be king all run through the runestone network (N1) and the embers resting in it (N3). |

### 1.1 The ascension arc

Real time assumes a 12-minute day.

| Stage | Title on screen | Adult days | Real time | You can | Typical failure |
|---|---|---|---|---|---|
| 0 | Nobody | 0–5 | 0–1 h | Work, hire 1 companion | Broke after one bad week |
| 1 | Sellsword / Freeholder | 5–25 | 1–5 h | 3 followers, a first camp, a first tame | Camp starves or gets robbed in its first winter |
| 2 | Warband Captain | 25–60 | 5–12 h | 6 followers, a hamlet, raids on bandit camps | Desertion from unpaid wages |
| 3 | Founder / Banneret | 60–110 | 12–22 h | A chartered village, knighthood, first holding | A raid spiral; a grudge agent sabotaging the granary |
| 4 | Baron | 110–180 | 22–36 h | 2+ holdings, a stronghold, your own house and sigil | Rebellion in a conquered village |
| 5 | Earl / Warden of a March | 180–240 | 36–48 h | A council seat, Writs of Feud, levies of 100 | Council enemies, Church schemes |
| 6 | Crown | 240–320 | 48–64 h | King by the Moot, or crowned consort-king | Losing the succession Moot; civil strife |

**Harsh start (numbers in §9).** Wages are paid daily at dawn and each follower eats 1 ration a day (1.4 in winter). A new camp has no walls, no stores and no ward. Robbers pick soft targets. Only one companion is free (a friend works for a share of the loot).

---

## 2. Recruitment and retinue

### 2.1 Who can be recruited

Almost any adult WorldSim person, plus authored companions and named monsters.

| Type | Where | Requirement | Hire fee | Wage/day | Rations/day | Base loyalty | Skills (1–10) | Cap by rank |
|---|---|---|---|---|---|---|---|---|
| **Villager** (labourer, farmer, woodcutter) | any settlement; jobless or `Laborer` rows first | opinion ≥ acquaintance; a bed at your camp or an inn room paid | 0 | 3 | 1.0 | 45 | work 1–4 | — |
| **Craftsman** (smith, carpenter, mason, tailor, brewer, miller, tanner) | village services, career seats | opinion ≥ 30 (friend) **or** buy out their seat: 60–200 | 0–200 | 8–14 | 1.0 | 40 | craft 3–7 | needs a workshop to be useful |
| **Soldier** (militia, levy) | guards, Greywatch Spear Hall, your holdings' militia | Warband Captain (R2) + barracks or tents | 20 | 6 | 1.2 | 50 | combat 2–4 | R2+ |
| **Veteran / knight** | Highwatch Keep, retired soldiers (`life_courses.gd`) | Banneret (R3); War Merit Ledger ≥ 40 | 150 | 15 | 1.3 | 55 | combat 5–8 | R3+ |
| **Mercenary** | taverns, Rift's Edge Camp, Solkar caravans | gold only; 7 days paid in advance | 30 | 12 | 1.2 | 30, capped at 60 until **Sworn** | combat 3–6 | any |
| **Specialist**: scout, runecarver, beast handler, healer, steward, quartermaster, engineer, spy | guilds, Royal Ember Academy, Runeward Legion | a quest or a guild rank; some need Renown R3 | 100–400 | 15–30 | 1.0 | 40 | role skill 5–8 | 1 of each per settlement tier |
| **Named companion** (8, §2.8) | authored intro scenes | their intro quest | 0 | **Share**: 10% of loot and bounties | 1.0 | 60 | unique | 8 |
| **Named monster** (goblin, wolf, orc, kobold …) | camps, via `RANaming` | naming cost in magicules | 0 | 0 | 1.5 (orc 2.0) | 75 (`BASE_LOYALTY`) | species class | Soul Name bonds per tier |
| **Refugee** | lordship refugee waves, Scar displacement | a free bed | 0 | 0 for 7 days, then 2 | 1.0 | 55 (gratitude) | work 1–3 | — |
| **Prisoner on parole** | spared robbers and bandits | spared at "Yield" | 0 | 1 | 1.0 | 15 | combat 2–5 | 1 per 5 loyal followers |
| **Tamed beast** (§3) | wild, dens, eggs | taming | 0 | 0 | species diet | bond based | species roles | §3.6 |

Recruiting someone vacates their career seat (`careers.gd`). Their employer's opinion drops by 5, and their family's opinion drops by 20 if you get them killed (§5.2).

### 2.2 Follower record

Stored in `asc_retinue`, JSON-safe, ~350 B each:

`{id (WorldSim row or "c:<companion>"), type, name, age_day0, traits[≤3], skills{}, gear{weapon, armour, mount}, wage, share, loyalty 0..100, morale 0..100, fatigue 0..100, mode, assignment{kind, site, pos}, injured_until, oaths[], friends[], rivals[], bread_debt, joined_day, deeds[]}`.

Beyond 60 individual records, extra soldiers are pooled into **companies** (`{count, avg_skill, loyalty, gear_tier}`). That keeps the save small and matches `squad.gd` (one brain per 100).

### 2.3 Costs and loyalty

**Loyalty** is long-term and decides desertion and refusal. **Morale** is short-term and battle-level (`army/morale.gd`).

| Loyalty driver (per day unless noted) | Δ |
|---|---|
| Wage paid at dawn / unpaid | +0.5 / −6 |
| Fed ≥ 1 ration / hungry (< 0.7) / starving (< 0.3) | +0.3 / −4 / −10 |
| Housed in a bed / tent / sleeping rough | +0.3 / 0 / −1 (−2 in rain or snow) |
| Victory they fought in (per battle) / defeat / rout | +3 / −4 / −6 |
| A friend died / a rival died | −10 / +2 |
| Gift (via `relationships.gd` gift prefs) | +2 to +6 |
| Promoted (sergeant, steward …) | +8 once |
| You broke a value they hold (see Traits) | −5 to −15 |
| Called more than 3 times in a day | −1 per extra call |
| Funeral held for a fallen follower (20 gold) | +3 to all |

| Loyalty band | Effect |
|---|---|
| ≥ 80 Devoted | Never refuses the Call; +10% work; may take a blow for you (X9) |
| 50–79 Loyal | Normal |
| 25–49 Wavering | Refusal chance rises (§2.5); −10% work |
| 10–24 Disloyal | Daily desertion roll `p = (25 − L) × 0.02` |
| < 10 Mutinous | **Ambitious** followers with Renown ≥ 30 attempt a mutiny and take every follower whose opinion of them beats their loyalty to you |

**Traits.** Three at most, taken from WorldSim tendencies (`tendencies.gd`) and careers.

| Trait | Effect | Hates |
|---|---|---|
| Brave | −50% refusal; +5 morale | fleeing |
| Craven | +15% refusal in T3+ zones | night calls |
| Greedy | wants a 1.3× wage; may steal on desertion | pay cuts |
| Frugal | ×0.8 wage | lavish feasts |
| Glutton | ×1.5 rations | hunger (double penalty) |
| Oathsworn | refuses the Call only below loyalty 20; +1 loyalty a day while Sworn | oath breaking |
| Loner | −morale in squads over 10 | barracks |
| Gregarious | +2 loyalty for friends nearby | solitude posts |
| Pious (Dawn Throne) | +healing | Scar goods, rune heresy (−5 when you carve) |
| Rune-true (Caldric) | +ward work | Church relics |
| Rift-touched | immune to scar sickness; others fear them (−2 opinion) | — |
| Beastfriend | +30% taming; beast upkeep −20% | beast killing |
| Green Hand | +25% farm yield | — |
| Night Owl | ×1.0 speed at night (not ×0.85) | dawn shifts |
| Drunkard | −10% work; +3 loyalty when ale is stocked | dry camps |
| Ambitious | asks for promotion every 20 days; mutiny risk | being passed over |
| Honourable | +loyalty for mercy | robbery, harsh tax, torture |
| Cutthroat | +loot share | mercy to robbers |
| Homesick | −1 loyalty a day beyond 1 km from home | long campaigns |

**Relationships between followers.** Each pair has an opinion in `relationships.gd`, keyed `f:<a>|<b>`. Friends near each other give +3 morale. Rivals spark **camp brawls** (p 0.05 a day when both are at camp) that cause injury and a −3 opinion chain. Friendships can become romances. A settled couple can have children (`family.gd` rules applied to NPC rows), which is the only natural population growth besides immigration.

### 2.4 Modes

| Mode | Where they are | Output | Wage | Call prep time (§2.5) | Body on screen |
|---|---|---|---|---|---|
| **Follow** | with you | combat, carrying (+20 kg each) | full | 0 | yes, up to the body cap below |
| **Column** (overflow of Follow) | abstract, marching with you | none until they deploy | full | 8 s (deploy at the edge of view) | spawned when combat starts |
| **Standby** | a chosen post (camp, inn, road stone) | none | full | 5 s | only near you |
| **Task** | a workstation or job site | production, construction, hauling, farming | full | 30–90 s to drop tools | only near you (WorldSim LOD) |
| **Garrison** | a settlement or holding | defence value (§5.5) | full | 60 s, and only with **Strip garrison** (defence drops at once) | only near you |
| **Errand** | travelling (scout a place, deliver, buy, escort a caravan, carry a letter) | the errand result | full + risk | not callable until they return | abstract |
| **Recovering** | a healer bed | none | half | not callable | only near you |

Physical follow bodies depend on the quality tier: **LOW 4 · MEDIUM 6 · HIGH 10 · ULTRA 12**. The rest are in the Column. Squads (R4+) use `squad.gd` with its sprite LOD beyond 45 m.

### 2.5 The Call

A horn blast or a rune signal: everyone chosen drops what they are doing and comes to you.

**Channels.** Higher tiers unlock with rank.

| Channel | Unlock | Reach | Notice delay | Needs |
|---|---|---|---|---|
| **Hunting horn** | start | 450 m | 2 s | — |
| **Runner** | R1 | any | distance / 4 m/s | a free follower as runner (or a paid village boy, 2 gold) |
| **Raven** | R2 | any | distance / 25 m/s | a rookery piece at your camp |
| **Rune signal** | R3 + Wardwright rank 2 **or** a runecarver follower | the connected lit ward graph (L7 `Wardlines`) | 0.5 s per stone hop, then a horn relay of 450 m from the stone nearest each person | your camp's stone linked into the graph |
| **Ember Beacon** | Warden of a March (R5) | the whole region | 3 s | a relit Elder Stone you hold; musters every holding's garrison (a levy) |

If a person is farther than 450 m from any connected lit stone, the rune signal falls back to a raven or a runner. **A dark or sabotaged stone breaks the chain** (twist T1, §8).

**ETA.** All in real seconds, computed on a 32 m travel grid (the same grid as the Scar Tide), with roads snapped and results cached for 60 s:

```
ETA = t_notice + t_prep(mode) + Σ_seg  len / (v_base · m_mount · m_surface · m_weather · m_night)
      + t_crossings + t_events
v_base  = 3.2 m/s abstract jog   (Swift +15 %, injured ×0.6, heavy armour ×0.9, hauling ×0.8)
m_mount = horse 2.6 · Stagborn 3.0 · boar 1.8 · wolf (runs alone) 2.2
m_surface = cobble 1.0 · dirt road 0.95 · your gravel road 0.9 · trail 0.75 · meadow 0.65
            forest 0.5 (Stagborn 0.9) · hills 0.55 · snow 0.45 · marsh 0.35 · Scar cell 0.6
m_weather = rain 0.9 · storm 0.75 · snow 0.8        m_night = 0.85 (Night Owl and beasts 1.0)
t_crossings = river ford +45 s, bridge 0
t_events: per segment through a cell with threat > 0.4 (threat_map), p = threat × 0.25 →
          "Delayed" (+20–90 s), or with p = 0.05 × threat "Ambushed" (arrives injured, or not at all)
```

Examples: 1 km on a dirt road on foot takes 5 min 30 s. Mounted it takes about 2 min 5 s. Through forest on foot it takes about 10 min 25 s. A Stagborn rider through forest takes about 2 min.

**Refusal** (rolled once per Call; the reason is shown on the card):

`P = clamp(0.02 + max(0, 50 − loyalty) × 0.012 + fear + 0.1·[fatigue > 70] + 0.2·[target is their friend or kin] − trait bonuses, 0, 0.9)`
- `fear = 0.08 × (danger tier of your position − their courage tier)`
- Brave: −50%. Oathsworn: 0 above loyalty 20. Mercenaries refuse unpaid Calls to battles in tier T4 or higher.

**Arrival.** When the remaining ETA is under 15 s and the person is inside the 200 m streaming radius, a body spawns 120 m out along the path (off screen) and runs in with an arrival bark (L17 barks). The horn has a 60 s cooldown.

**ETA UI.** Touch-first, in the dark-gold `ashes_frame.gd` style:
- **Hold the horn button** (HUD, 64 dp) to open a radial: *All · Fighters · Workers · Beasts · Named · Custom group*. Release to call.
- A collapsible **ETA sheet** appears top right. It holds up to 6 cards sorted by ETA, then "+N more". Each card shows a portrait, name, a mount icon and a live countdown `0:42`.
- A status chip on each card: *Coming* (gold) · *Delayed: wolves at Cinderpost* (amber) · *Refused: unpaid* (red) · *Out of reach* (grey) · *Garrison: strip?* (a button).
- **Compass pips** move toward the centre as people approach. The **map** shows a ribbon per person along their path, and a broken chain icon where a dark stone cut the signal.
- Tapping a card pins that person on the compass. A long press cancels their Call (no loyalty cost).

Per-call cost: ≤ 3 ms total for 12 path queries, spread over frames. The sheet refreshes at 4 Hz.

### 2.6 Party size by rank

**Renown** comes from deeds and fame. **Rank** also needs holdings (§6.7).

| Rank | Renown | Follow cap | Roster cap | Squads (`squad.gd`) | Beasts following | Call channels |
|---|---|---|---|---|---|---|
| R0 Nobody | 0 | 1 | 1 | — | 1 (pet or horse) | horn |
| R1 Sellsword / Freeholder | 15 | 3 | 5 | — | 1 | + runner |
| R2 Warband Captain | 40 | 6 | 14 | — | 2 | + raven |
| R3 Founder / Banneret | 90 | 8 | 40 | 1 × 20 | 2 | + rune signal |
| R4 Baron | 160 | 10 | 120 | 2 × 20 | 3 | + rune |
| R5 Earl / Warden | 260 | 12 | 400 (companies) | 5 × 20 | 3 | + Ember Beacon |
| R6 Crown | — | 12 | realm levy (abstract) | 5 × 20 + royal host | 4 | all |

Leadership mastery (`mastery.gd`, discipline `command`) of 5 or more adds +1 to the follow cap. Command also limits squads: one squad per 2 command levels.

### 2.7 Desertion, injury and death

| Event | Rule |
|---|---|
| **Down** | At 0 HP in combat a follower goes Down, not dead. They die if left Down for 30 s with an enemy within 6 m, or on an execution hit. A healer follower or the player revives them with a 3 s hold. |
| **Injury** | Every Down rolls `injuries.gd`: light (2 days), serious (6 days, −50% stats), maimed (permanent, 1 trait slot). Recovery needs a bed; ×0.5 time with a healer. |
| **Death** | Permanent. Friends lose 10 loyalty. Their kin get a grudge (§5.2) against the killer's faction, **or against you** if you ordered a suicidal hold (a Hold order in a fight whose defeat odds were > 70%). The biography logs it. Named companions can choose an **Ember** (N3): their stone warns you in their voice. |
| **Desertion** | Loyalty < 25 rolls daily. The deserter leaves with their gear; Greedy ones also steal 5–15% of camp stores. Deserters may become **robbers** (p 0.3, twist T3). |
| **Mutiny** | Loyalty < 10 + Ambitious + Renown ≥ 30. They take followers, the camp store and a grudge with them. You can talk them down (Renown check), buy them off (30 days of wages) or duel them (§6.2). |
| **Old age** | Followers age 1 year per 12 days. Past 55, a yearly retirement roll. Veterans retire into your settlement as teachers (+10% training speed). |

### 2.8 Named companions and personal quests

Eight companions. Each is an **Ember candidate** and each ties to one mechanic and one future region.

| Companion | Who | Joins after | Personal quest (3 steps) | Payoff | Ties |
|---|---|---|---|---|---|
| **Wren Coldbrook** | Maren's niece, staff fighter, childhood friend | Act I, age 12 | *The Yard's Last Lesson*: Maren's old Runeward debt, a dark stone on the Elden Road | the Staff Yard becomes your first training hall (+15% soldier training) | N1, tutorial companion |
| **Brannoc Tallow** | an Ashen Hand robber you spared | beat him at a road ambush, then Parole | *Ashes of the Hand*: Ashsight at his old camp, confront the Hand's fence | a spy role; the robbers' raid telegraphs become visible 1 day early | N4, robbers |
| **Sister Oriel Vane** | a Dawn Throne healer who defects | Act III chapel scene (L3 chapel) | *A Relic Unburned*: hide or return a Dawn relic | a healer; Church standing becomes a lever in the Moot | Church realms tease |
| **Hesk Ironbrow** | a Durrow mason, exiled | buy his debt (120) in Silverford | *The Unfinished Arch*: finish his guild test piece | unlocks stone tier building and the siege engineer | Ashenreach tease |
| **Tamsin Reedwhistle** | a Veyl ranger and beast tamer | Stagborn Glade, Act IV | *The Glade Remembers*: settle the herd's grudge (§5.2) | taming mentor; unlocks Rune Bond | Verdanweald tease, Stagborn |
| **Grukka Ashmaw** | Harrok's nephew, orc | Tuskridge diplomacy | *The Tusking*: a clan challenge duel | unlocks orc recruits and named-orc squads | Urrokai exiles |
| **Sir Alaric Venn** | a disgraced Highwatch knight, a drunkard | a tavern at Cinderpost | *Oath at Grimfen*: redeem his lost patrol | **sponsors your dubbing** (knight rank without a vacancy) | the Order of the Highwatch, Frostcrown tease |
| **Marisol Qadir** | a Solkar spice trader's daughter | Midsummer Fair | *Sun-Road Ledger*: open a caravan contract to the south | steward and quartermaster; hire mercenary companies at −25% | Solkar tease |

Personal quests unlock at loyalty 60 and 10 days of service. A companion who is ignored for 40 days leaves politely (no grudge). Companions have opinions about your acts: Honourable Alaric leaves if you sack a village; Cutthroat Brannoc leaves if you hang robbers.

---

## 3. Taming

### 3.1 Tameable creatures

| Creature | Where (Region 1) | Diff. 1–5 | Methods | Gate | Roles | Diet · rations/day | Housing |
|---|---|---|---|---|---|---|---|
| Hound pup | village litters (buy for 15) | 1 | raise | — | guard, tracker | omnivore · 0.4 | kennel |
| Riding horse | bought (60) or wild herds at Crownstead meadow | 1 / 2 wild | feed | — | mount, hauler (cart) | grain or hay · 1.0 | stable |
| Fox | Duskbriar, fields | 2 | feed | — | scout (finds forage nodes and rare herbs), thief | omnivore · 0.3 | kennel |
| Wolf | wolf dens (`monster_ecology`) | 2 | subdue, raise cub | level 6 | guard, combat, tracker | meat · 0.8 | kennel |
| Boar | woods, the autumn rut | 2 | subdue | level 7 | hauler (pack saddle, +60 kg), charge, truffle forage | omnivore · 0.8 | sty |
| Bog toad | Westfen | 2 | feed | — | pest control (eats blight rats: −30% spoilage), alchemy mucus | insects · 0.2 | pond |
| Giant wasp | nest brood in the deep wood | 3 | raise (brood) | Kindled | pollinator (+15% crop yield in 40 m), scout | nectar and sugar · 0.2 | hive |
| Bear (apex) | northern hills | 4 | subdue | Tempered (soul tier 4) + 4 fighters | combat tank, hauler (+120 kg) | omnivore · 2.0 | den pen |
| **Stagborn elk** | Stagborn Glade | 3 | **Rune Bond only** (harming one makes the herd a grudge enemy) | Wardwright rank 2 | **mount (the fastest in forest)**, hauler, **Wardwalker** (§3.7) | grass · 1.2 | open pasture |
| Antlered Warden | glade miniboss | — | cannot be tamed; **Sworn** as an ally after its trial (called once per season) | Act IV | guardian ally | — | — |
| Rift wolf / rift boar | Scar cells | 3 | Rune Bond with the Scar glyph, inside the Scar only | soul tier 3 + the Scar glyph | combat; **Scar-grazer** (§3.7) | scar shards · 0.2 + meat 0.5 | rift pen |
| Rift slime | Ashen Scar | 3 | feed scar crystal | Kindled | "living chest" hauler (+40 kg, follows you), alchemy | scar crystal · 0.1 | vat |
| Wyvern | apex nest (rare) | 5 | raise from an egg (28-day incubation in a warm den) | the Region 1 finale; tier 6 | flying scout now; flying mount in Region 2 | meat · 3.0 | aerie |
| Troll, Scarbound Troll | — | untameable | — | — | — | — | — |
| Goblin, kobold, orc, lizardfolk, ogre, spider, slime | camps | — | **naming** (`RANaming`), not taming | existing | existing classes | as recruits | — |

Future regions add their poster beasts in data only: sandstriders and drakes (Solkar), frosthorns and dire wolves (Frostcrown), barkhorns and stag spirits (Verdanweald), thunderhoof and sky elk (Zephyr), marshbeasts (Umbrafen), obsidian beasts (Ashenreach), reef leviathans (Tideclad, taming by bond only), celestial beasts (Jadecliff, Soulbeast rules through Xiava's Lake).

### 3.2 Methods

| Method | Flow | Time | Risk | Best for |
|---|---|---|---|---|
| **Feed** | Offer a preferred food on approach. Trust fills 10–20 per offering. Move slowly (walk speed). A sudden move adds fear. | 3–6 offerings across 1–2 days (it must find you again) | low | horse, fox, toad, slime |
| **Subdue then befriend** | Fight until the beast **Yields** (the `CampMonster` yield state exists), below 30% HP. Then play the **Calm** minigame (§3.3). | one fight + 20–40 s | medium: overkill kills it; a failed Calm makes it flee or attack | wolf, boar, bear |
| **Rune Bond** | Inside ward coverage (N1), carve the **Hearthbond** glyph (L8 recognizer, 3 strokes) on a stone the beast can see. Then hold still while it approaches (5–10 s). Rift beasts need the **Scar glyph**, carved inside a Scar cell. | 30 s | low; a bad glyph spooks the herd (fear +40) | Stagborn, rift beasts |
| **Raise young** | Take a cub, brood or egg from a den. The mother and pack get +0.3 aggression and a grudge (§5.2). Incubate or nurse it at a housing piece. | 7 days (pup, cub) to 28 days (egg) | the den raid itself | wolf, wasp, wyvern, hound |

### 3.3 The Calm minigame (one thumb)

- The yielded beast's **heartbeat ring** pulses around it. The player holds the food button, and each tap must land on the beat (±120 ms window, widening to ±180 ms with Beastfriend or with a beast handler within 15 m).
- A hit gives trust +12. A miss gives fear +15. Holding still between beats is required, because movement drains trust by 2 per second.
- The beat accelerates as trust rises (a calming heart slows, so the *ring* shrinks and the window narrows).
- Tame at trust 100. At fear 100 it flees, or attacks if it is apex.
- 3–5 cycles, 20–40 s in total. Haptic tick on a hit. It fits a 48 dp button in the bottom-right thumb zone.

Accessibility: a **timing assist** setting doubles the window. A **no-rhythm option** makes it a hold-to-fill with the same trust and fear logic, driven by staying still.

### 3.4 Difficulty curve

`p_first_try = clamp(base[diff] × (1 + 0.12 × (player_level − beast_level)) × food_pref × assist, 0.05, 0.9)`
- `base` = [0.8, 0.6, 0.45, 0.3, 0.15] for difficulty 1–5.
- `food_pref`: loved 1.3, liked 1.0, wrong 0.5.
- `assist`: Beastfriend 1.3, handler 1.15, Tamsin 1.25.

In the Calm minigame this sets the starting trust and the beat speed. Target at the recommended level: a 35–60% first-try success (sim test S9).

### 3.5 Bond, upkeep and housing

| Bond level | Needs | Unlocks |
|---|---|---|
| 1 Wary | tamed | follows; flees at 30% HP |
| 2 Settled | 5 days fed + 1 shared fight | commands (stay, guard, fetch) |
| 3 Trusting | 15 days + 5 fights | its role ability (charge, pack saddle, track) |
| 4 Bonded | 30 days + a named deed together | a Soul Name bond (existing `naming.gd` soul bonds, tier-gated) |
| 5 Kin | 60 days + a Soul Name | evolution (Storm Wolf and others from `RANaming.SPECIES`) + a beast **Ember** at death |

Neglect costs 1 bond point per 10 days without being fed by you or a handler. Starvation turns a beast **feral** in 3 days and it leaves; a feral apex attacks the settlement. A tamed beast sells for at most 60% of its market value (sim test S3).

### 3.6 Roles

| Role | Beasts | Effect |
|---|---|---|
| Mount | horse, Stagborn, (wyvern in R2) | `mount_controller.gd` gaits; Stagborn ignores the forest speed penalty and can jump fences (X8) |
| Guard | hound, wolf, bear | +6 defence each at a garrison; barks at intruders (raid telegraph +30 s) |
| Hauler | horse + cart, boar, bear, rift slime | carry capacity; +40% hauling speed at the settlement |
| Combat | wolf, boar, bear, rift beasts | follows the attack tokens (`creature_attack_tokens.gd`) |
| Scout / forager | fox, wasp, hound | reveals forage and dens within 150 m on the compass; finds truffles and herbs |
| Utility | toad (pests), wasp (pollination), slime (storage, alchemy) | settlement modifiers |

### 3.7 Ties to Wardwright and the Scar Tide (twist T4)

- **Wardwalker (Stagborn).** Assign a bonded Stagborn to a ward-line (L7 link). It grazes along the line daily. Stones it passes gain +0.1 power, and their decay is halved. A herd of 5 keeps a 3-stone road glowing without a runecarver. Stagborn only walk links with coverage ≥ 0.3 (they follow the old ward-lines, as in Region 1 lore).
- **Scar-grazer (rift beasts).** Assign one to a Scar front cell (L9 grid). It eats 1 front cell per 2 days (a containment tool) but gains +5 "saturation" per cell. At 100 it mutates (a stronger combat form) with a 30% chance of going **feral**. Scar-grazing is the only way to push the Tide without fire in winter.
- **Scar sickness.** Normal beasts in Scar cells lose 2% HP a minute and 1 bond point a day. Rift beasts in ward cells above 0.6 coverage are **ward-sick** instead. You can't keep both kinds in one pen unless there is a ward-dampening *rift pen*.
- **Beast Ember (N3).** A Kin-bond beast that dies can rest in a stone. The stone then **howls** (an audio alarm, L17) when raiders come within 200 m. This is the only way to get a stone alarm without the Alarm glyph.

---

## 4. Settlement founding and building

### 4.1 Claiming land

| Claim | How | Cost | Legal status | Max tier | Obligations |
|---|---|---|---|---|---|
| **Squat** | build a tent anywhere allowed | 0 | none: the land's holder (a house or the Crown) finds you in 7–14 days | Camp | the holder's bailiff demands rent (15/day), a charter purchase, or leaving; refusing is a grudge + eviction force (§5) |
| **Freehold** | buy a homestead plot (`homestead.gd`, 150/300/600) | as now | owned | Camp (the tutorial plot) | land tax (`property.gd`) |
| **Settler's Charter** | audience with the holder at `noble_courts.gd` (or the Crown steward in Kingsreach) | `400 × fertility (0.6–1.2) × safety mult (coverage 0.8 → 1.5, 0.2 → 0.6)` | chartered | Town | seasonal tithe 35% of tax (`lordship.TITHE_RATE`), levy in war; **Licence to Fortify** needed for stone walls and a keep (Crown favour ≥ 40, 300 gold) |
| **Ward Claim** (Frontier Law) | beyond the kingdom's last lit stone: raise **your own runestone** (8 stone blocks + 3 rune dust + a runecarver), carve the **Hearth glyph** (L8), and **hold it lit for 28 days** (one season) | materials + defence | freehold after 28 days | Stronghold | none until the Crown demands **fealty** (an event at Village tier): swear (you become a vassal, tithe 20%) or refuse (Crown favour −30; you are safe from the tithe but a march lord may feud) |

**Where claiming is allowed.** `land_claim.gd` validates each placement.

| Rule | Value |
|---|---|
| Distance from any existing settlement's centre | ≥ 350 m (village), ≥ 600 m (town or capital) |
| Distance from another owner's lit stone (Ward Claim only) | ≥ 420 m (the frontier road spacing, so bubbles don't overlap) |
| Distance from a monster den | ≥ 250 m, or clear the den first (`monster_ecology`) |
| Scar cells (L9) | forbidden; a claim that the Scar later reaches loses 10 contentment a day until it is contained |
| Slope | foundations need ground within ±1.5 m across a 2 m cell; foundations adapt in steps (§4.3) |
| Water | a well needs a groundwater cell (terrain moisture > 0.4) **or** a river or lake within 120 m |
| Roads, bridges, runestones, noble courts and region sites (`region_sites.gd`) | no pieces within 6 m of a road centreline or 10 m of a site |
| Crown land (Kingsreach ring, Crownstead, the King's Ember Road) | never claimable; only buy existing lots (`property.gd`) |
| Max player-built settlements | **3** (the mobile budget). More are held as holdings (§6) without free building. |

### 4.2 Legal ladder of a founded settlement

Squat → Freehold or Charter or Ward Claim → (Village) registered in `lordship.gd` with reason `founded` → (Town) a market charter, 150 gold from the Crown, adds a `RAMarket` → (Stronghold) the Licence to Fortify plus a keep → it can become the seat of a **March** (R5).

### 4.3 Building

Free placement with snapping, in the spirit of Palworld and Valheim but made for thumbs.

**Grid.** Structural pieces use a **2 m grid** (the homestead's `GRID`). The vertical grid is 3 m (1 storey), with 2 storeys plus an attic at most. Props snap at 0.5 m with 15° rotation. Structure rotates in 90° steps. Foundations on a slope auto-pick a 0, 0.5, 1.0 or 1.5 m stilt height.

**Support** (Valheim-lite, no physics): wood pieces carry at most 3 cells from a supported column, stone 5. Unsupported pieces show red and can't be placed. Destroying a support **drops** the dependents as debris (VoronoiShatter on HIGH, a simple fade on LOW).

**Pieces (`data/ascension/pieces.json`).** Materials per piece; *lh* = labour-hours.

| Group | Pieces | Materials (typical) | lh | HP | Tier |
|---|---|---|---|---|---|
| Camp | tent (2 beds), lean-to, campfire, bedroll, stash (40 slots), drying rack, rookery | cloth 2 / logs 2 | 1–2 | 60 | Camp |
| Wood structure | foundation, floor, wall, window wall, door wall, half-wall, stairs, pillar, beam, roof 26° / 45°, gable, roof corner, thatch roof | planks 4–8, logs 1–2, thatch 4 | 2–4 | 150 | Camp |
| Stone structure | foundation, wall, window, arch, stairs, pillar, slate roof | stone blocks 6–10, mortar 1, planks 2 | 5–8 | 500 | Village (Hesk or a mason) |
| Defence | palisade (3 m), spiked stakes, pit trap, watchtower (wood), gate (wood), stone wall, stone gate, stone tower, arrow slit, murder hole, alarm bell | logs / stone / iron | 3–20 | 200–1,200 | Camp → Stronghold |
| Ward | **own runestone**, ward post (+0.1 coverage, 40 m), alarm stone | stone 8 + rune dust 3 | 12 | 800 | Hamlet (Ward Claim: Camp) |
| Work | woodcutter's block, sawpit → sawmill, quarry, charcoal kiln, smelter, smithy, carpenter, mason's yard, tannery, loom, mill, bakery oven, brewery, smokehouse, herbalist, runecarver's bench | see chains §4.5 | 4–30 | 200 | per tier |
| Farm | field (3 × 3 plots), orchard tree, barn, coop, sty, stable, kennel, pasture fence, beehive, pond | as `homestead.CATALOG` | 1–10 | 100 | Camp |
| Storage | stash, storehouse (200), root cellar (roots, 0.2% spoilage), granary (grain, 0.3%), treasury chest | planks / stone | 6–16 | 300 | Camp → Village |
| Civic | well, shrine / ring stone, tavern, market stall, meeting hall, bathhouse, school yard, healer's house, barracks (12), longhouse (10 beds), cottage (4), manor (8 + steward) | mixed | 8–60 | 300–800 | per tier |
| Deco | fence, lamp, bench, banner (your sigil), planter, well bucket, sign, statue | small | 0.2–2 | 30 | any |

**Blueprints.** One tap places a whole building. `data/ascension/blueprints.json` is a list of pieces with relative cells.
- Built-in: cottage, longhouse, barracks, smithy, granary, tavern, watchtower, gatehouse, manor, keep.
- **Save as blueprint**: select a built group (a lasso on the build camera). Blueprints are stored in the save as compact piece lists (§4.10).
- **Plan mode**: pieces placed without materials become *plans*. Workers build them as soon as materials reach storage.

**Construction by workers.** Each piece moves through **Plan → Delivered → Frame → Done**, with 3 mesh states (scaffold, frame, finished).
- Builders do 1 lh per game hour × `(0.6 + 0.1 × building skill)`.
- Haulers move materials from storage (abstract: a hauling distance cost of 1 lh per 40 m per 20 kg; carts and boars halve it).
- **The player can help**: holding the hammer button on a piece gives 3× speed and builds your *building* mastery.
- Job priority is a single slider sheet: *Food · Build · Defend · Craft*.

### 4.4 Roads drawn with a finger

- **Draw mode** (build camera, top-down at 55°): drag a finger along the ground.
- The stroke is resampled every 4 m, simplified (Ramer–Douglas–Peucker, ε 1.5 m) and smoothed (Catmull-Rom), then snapped to existing road ends within 8 m.
- Output: `addons/road-generator` `RoadContainer` + `RoadPoint`s, built at runtime. **Fallback** if runtime generation is too slow on mobile: our own ribbon mesh with the existing road materials (L36 decides with a benchmark).
- Workers pave it progressively, the same as other pieces.

| Road tier | Width | Materials per 10 m | lh per 10 m | Speed mult | Other |
|---|---|---|---|---|---|
| Path | 1.5 m | — | 0.5 | 0.75 (trail) | cuts forest penalty |
| Dirt road | 3 m | logs 1 | 2 | 0.95 | carts allowed |
| Gravel road | 4 m | stone 2 | 4 | 0.9 (dirt in rain), plus the "no-mud" flag | caravans consider it |
| Cobbled road | 5 m | stone blocks 4 | 8 | 1.0 | +5 contentment in town; land value +10% within 30 m |

A settlement road that joins the kingdom network (within 8 m of a `WorldGen` road) makes the settlement a caravan stop (`caravans.gd`, `road_traffic.gd`). Visibility rises too (§5.3). **Roads shorten Call ETAs** (§2.5), so the road web is a defence decision.

### 4.5 Gathering and production chains

Rates are per worker per game day at skill 5 (×0.6 at skill 1, ×1.4 at skill 10).

| Chain | Steps | Rate | Station |
|---|---|---|---|
| Wood | tree → **logs** (3) → **planks** (1 log → 3 planks) | 12 logs; 24 planks | woodcutter's block; sawpit (sawmill ×2, Village) |
| Stone | rock or quarry → **stone** → **stone blocks** (2 → 1) | 10 stone; 6 blocks | quarry; mason's yard |
| Iron | vein (`ore_vein.gd`) → **iron ore** → **ingot** (2 ore + 1 charcoal) → tools, weapons, nails | 8 ore; 4 ingots; 1 tool or 0.3 swords | mine or quarry; smelter; smithy |
| Charcoal | logs → charcoal (3 → 2) | 6 | kiln |
| Grain | field → wheat/barley → **flour** (mill) → **bread** (1 flour → 2 bread) | a field gives 12 wheat per 4-day cycle | field; mill; bakery oven |
| Roots and veg | field → turnip (winter-hardy) / cabbage | 9 turnips or 10 cabbages per cycle | field; root cellar |
| Ale | barley + hops → ale | 6 casks | brewery |
| Livestock | coop → eggs; sty → pork (every 4 days); cow → milk | existing `homestead.gd` rates | coop, sty, barn |
| Hunting and fishing | game → meat + hides; fish | 3 meat (falls 3% a day per local hunter, recovers 5% a day); 5 fish | hunter's lodge; jetty |
| Cloth and leather | flax → linen; wool → cloth; hides → leather | 3; 3; 4 | loom; tannery |
| Herbs | forage → herbs → poultice | 6; 4 | herbalist |
| Rune | stone chips + scar crystal or Elder shard → **rune dust** → ward pieces, glyph tools | 2 dust | runecarver's bench (runecarver follower) |
| Scar | scar crystal (L9 harvest) → **rift alloy** (late gear, sells high) | 1 | smelter + runecarver |

### 4.6 Food and upkeep: why the early game is hard

**Ration values** (1 ration = 1 person-day): bread 0.5 · flour 0.4 · wheat (raw) 0.25 · cabbage 0.4 · turnip 0.4 · meat 0.6 · fish 0.5 · eggs 0.2 · ale 0.2 (+1 contentment). The market price is about 4 gold per ration.

| Upkeep | Value |
|---|---|
| Each person | 1.0 ration a day; 1.4 in winter (`lordship.WINTER_FOOD_MULT`) |
| Each follower wage | §2.1 (paid by you, or by the settlement treasury once assigned there) |
| Spoilage | ground pile 3%/day · stash 2% · storehouse 1% · granary (grain) 0.3% · root cellar (roots) 0.2% · smoked meat 0.5%; winter halves spoilage |
| Firewood (winter) | 0.5 logs a day per 4 beds; with none, contentment −15 and sickness p 0.05 a day |
| Tools | each worker wears out 1 tool per 20 days (−40% output without one) |
| Piece upkeep | wood pieces lose 0.2% HP a day (repair 10% of materials); stone 0.05% |

**Worked example (the target feeling).** You found a squat camp on adult day 12, day 10 of autumn, with 3 followers (a labourer, a hunter and a carpenter). The stash holds 12 rations.
- Needs: 3 rations a day. The hunter brings 1.8 rations a day (falling 3% a day). The labourer sows 2 turnip fields, which yield 7.2 rations every 4 days (1.8 a day) from day 16.
- Net: about +0.5 a day after spoilage. Winter starts on day 28 of autumn and needs 3 × 1.4 × 28 = **118 rations** stored. By then you will have about 30.
- **Without a plan the camp starves by winter day 10.** The fixes all cost something: buy 90 rations (360 gold, which is 20+ days of your wages), fish the Mere, raid a bandit camp's store, trade scar crystal, recruit a Green Hand, or send people home for winter (loyalty −10).

This is exactly sim test S1 (§9.3).

**Share of the population that must farm.** A farmer with 2 fields gives about 1.8 rations a day in growing seasons and 0 in winter (turnips excepted). Banking a winter needs about 0.47 extra rations per person per day over 84 growing days.
- Early game: **about 70% of people on food.**
- Mill (+30% from bread conversion), granary, oxen and plough (+50% fields per farmer), fishing jetty and trade bring this to **about 45% at Village** and **about 30% at Town**.

### 4.7 Happiness, housing and jobs

`Contentment (0..100) = 50 + food(−30..+10) + housing(−20..+10) + safety(−25..+10) + work(−10..+5) + amenities(0..+15) + fairness(−10..+5) + leader(−5..+10) − tax(0..15) + events`

| Factor | Measured by |
|---|---|
| Food | days of stores: < 3 → −30; 3–10 → −10; > 30 → +10; variety (3+ foods) +3 |
| Housing | a bed each (tent −5, cottage 0, manor +5); crowding more than 4 per cottage −10 |
| Safety | ward coverage (monsters) + defence vs visibility (bandits, §5.3); a raid in the last 7 days −15 |
| Work | idle > 20% of the time −10; matching their skill +5 |
| Amenities | tavern +5 (+3 with ale), shrine or ring stone +3, bathhouse +3, market +4 |
| Fairness | wage vs regional wage; rationing split evenly |
| Leader | your Renown and presence (seen in the last 3 days) |
| Tax | `lordship` rates: low 0, fair −5, harsh −15 |

| Contentment | Effect |
|---|---|
| ≥ 70 | work ×1.15; +1 immigrant per 2 days while beds are free; a festival request (+5 for 7 days if held) |
| 40–69 | normal |
| 25–39 | work ×0.85; no immigration |
| < 25 | **unrest** (the `lordship.UNREST_LOYALTY` band): strikes, 1 person leaves every 2 days |
| < 8 | **revolt** (`REVOLT_LOYALTY`): they seize the stores and elect a grudge agent as leader (§6.5) |

**Jobs.** Workstations have seats (the `careers.gd` pattern), so jobs auto-assign by skill and the player overrides by dragging a portrait onto a station card. There is no micromanagement of hauling.

### 4.8 Growth tiers

| Tier | People | Requires | Unlocks | Radius | Piece cap | Raid band |
|---|---|---|---|---|---|---|
| **Camp** | 1–8 | a tent + a campfire | camp pieces, fields, wood structure, 1 blueprint | 30 m | 150 | robbers 2–4 |
| **Hamlet** | 9–20 | any claim except Squat · well · storehouse · 3 houses (beds for all) · 1 lit stone within 120 m | work stations tier 1, ward pieces, a steward follower | 50 m | 400 | 3–6 |
| **Village** | 21–60 | charter or freehold · palisade ring · granary · 3 workshops · shrine or ring stone · a road to the network · Renown R3 | stone structure, mill, tavern, **lordship registration** (Lord's Council) | 80 m | 900 | 5–12 |
| **Town** | 61–150 | market charter · 2 connected roads · stone walls on 50% of the perimeter · 6 workshops · contentment ≥ 55 for 10 days | market, bathhouse, school yard, guild office, caravan stop | 120 m | 1,600 | 8–20 + monster migrations |
| **Stronghold** | 151–250 | Licence to Fortify (or Ward-Claim freehold) · a **keep** · a stone curtain wall · garrison ≥ 30 · Renown R4 | keep, siege workshop, royal audiences held at home, march seat | 150 m | 2,200 | 15–40 + sieges |

Population means data rows. Bodies are WorldSim LOD, so about 24 are animated near you, whatever the tier.

### 4.9 Mobile build UX

| Gesture or control | Action |
|---|---|
| Build button (Pack menu, or the hammer on HUD inside your claim) | enters the build camera: top-down orbit at 55°, pinch zoom 8–60 m |
| Bottom tray (tabs: Camp · Structure · Defence · Work · Farm · Civic · Deco · Blueprints) | tap a piece; the ghost appears under the centre reticle, snapped |
| One-finger drag on the ground | moves the ghost (sockets snap within 0.6 m; haptic tick on snap) |
| Two-finger twist | rotates 90° (props 15°) |
| ✓ / ✗ buttons (64 dp, thumb zone) | place / cancel |
| **Row** toggle | drag start→end to place a run of walls, fences or palisade |
| Long press on a placed piece | select → Move · Remove (50% refund) · Repair · Copy |
| Lasso (two-finger hold, then drag) | select a group → Save blueprint · Remove |
| Undo | 20 steps in the session |
| Ghost colours | blue: snap OK and materials OK · amber: a plan (missing materials, listed on a chip) · red: invalid (the reason on a chip: "slope", "support", "claim edge") |
| Draw road | a separate mode: finger stroke → cost preview → ✓ |
| Workers sheet | Food · Build · Defend · Craft sliders; station cards with portraits |

All targets are ≥ 48 dp. The primary flow is one thumb and needs 3 taps to place a blueprint house.

### 4.10 Performance and save budgets

| Budget | LOW tier | HIGH tier | How |
|---|---|---|---|
| Pieces per settlement (hard cap by tier) | 1,400 at Stronghold | 2,200 | the tier table; the cap blocks placement with a chip |
| Draw calls, the whole settlement in view | ≤ 60 | ≤ 120 | a `MultiMeshInstance3D` per (piece kind × build state × material atlas); **baking**: 10 s after a building is Done its pieces merge into one mesh (`build_renderer.gd`, in a background-free main-thread slice of ≤ 2 ms per frame; never `load_threaded_request`, per `ashes-agent-orchestration`) |
| Triangles in view | ≤ 250k | ≤ 600k | kit pieces ≤ 400 tris LOD0 and ≤ 120 LOD1; LOD1 at 45 m (LOW) / 70 m (HIGH) |
| Distant settlement | a single HLOD proxy beyond 250 m (LOW) / 400 m (HIGH) | same | proxy baked when leaving the claim (one mesh, ≤ 4k tris), stored as a resource in `user://` |
| Ghost placement cost | ≤ 1 ms | ≤ 1 ms | a spatial hash on the 2 m grid; support check local only |
| Settlement sim tick | ≤ 2 ms per game hour | same | `Region1Sim` contract, ticked by `Region1Root` |
| Follower bodies | 4 | 10–12 | §2.4 |
| Physics | static bodies only for walls, gates and foundations; deco has no collision | same | one merged collision shape per baked building |
| Save per piece | 16 B packed (kind u16, x/z i16 at 0.25 m, y i16 at 0.1 m, rot u8, state u8, hp u8, owner u8, pad) | same | a `PackedByteArray` as base64 in JSON |
| Save per settlement | ≤ 60 KB (2,200 pieces ≈ 47 KB + roads ≤ 40 × 64 points + stores) | same | — |
| **Total ascension save** | **≤ 400 KB** (3 settlements 180 KB + 60 followers 24 KB + companies + beasts 10 KB + grudges ≤ 200 × 120 B + holdings + crown 30 KB) | same | the Region 1 DoD keeps the whole save under 2 MB |

---

## 5. Threats and enmity

### 5.1 Reputation layers

| Layer | Stored in | Range | Moves with |
|---|---|---|---|
| Individual | `relationships.gd` opinion (existing) | −100..100 | everything personal |
| Settlement | new: `asc_rep.settlements[id]` | −100..100 | how you treat its people: hiring, evicting, raids, aid, bread given |
| Faction | `relationships.reputation` (existing: towns, houses, sects, the Runeward Legion, the Ashen Hand, goblins, orcs, the Stagborn herd) | −100..100 | deeds against or for them |
| **Renown** (fame) | `asc_rep.renown` | 0..∞ | Deeds of the Realm (§6.7); decays 0.2 a day above your rank's floor |
| **Notoriety** (infamy) | `asc_rep.notoriety` | 0..100 | crimes, massacres, breaking the Crown's Peace; decays 0.5 a day; ≥ 40 → wanted in Crown towns |
| **Bread Debt** (twist T2) | per person / settlement, `asc_rep.bread` | rations given | feeding people in need (§8) |

### 5.2 Grudges: anyone can become an enemy

A **grudge** is a sim object: `{holder (WorldSim row, companion, house, faction, herd), target, cause, heat 0..100, born_day, source_event (an Ashsight record id when available), kin_share}`.

| Cause | Heat |
|---|---|
| Killed their kin (spouse, parent, child, sibling) | +60 (kin get 50% each) |
| Killed a member of their faction / band | +25 |
| Conquered their village or evicted them | +45 / +25 |
| Fired them, or seized their seat by recruiting their worker | +10 / +8 |
| Unpaid wages owed (per 3 days) | +15 |
| Stole from them, robbed their caravan | +20 |
| Beat them in a public duel | +15 (0 if Honourable, who respects it) |
| Rejected their courtship, broke a betrothal | +10 / +35 |
| Harsh tax on their village (per season) | +5 |
| Den raided (a wolf pack or boar sounder) / a Stagborn harmed | +30 (pack) / +50 (herd) |
| You out-competed their shop (market share −30%) | +8 |

Heat decays 1 a day, stops decaying while the holder can see the cause (living in the conquered village, the grave nearby), and halves on restitution.

| Heat | Stage | What the holder does (weekly action budget) |
|---|---|---|
| 25 | Resentful | slander: −2 settlement reputation where they live; refuses trade |
| 50 | **Enemy (agent)** | one action a week: sabotage (burn 1 piece, poison 5% of stores), theft, a false rumour (N6), joining a rival house or the robbers, testifying against you |
| 75 | **Vendetta** | hires robbers (if they can pay), a single-assassin attempt, bribes your steward |
| 90 | **Blood feud** | inherited by kin (and by **your** heir through Ember Legacy); a house-level feud (`nobility.gd`) if the holder is noble |

**Resolution:** restitution (pay weregild: 30 days of the victim's wage, heat −60), an apology quest, a duel (a win halves heat; a loss clears it but costs Renown), marriage into the family (clears it), exile or imprisonment (lordship justice: +10 heat to kin), or killing them (heat spreads to kin at 50%).

**Budget.** At most **12 active agents** are simulated at once, the hottest first. The rest are dormant rows (≤ 200 stored). Agents act on their weekly tick only. The cost is nothing per frame.

**Beasts and monsters bear grudges too.** A raided wolf den becomes a pack grudge: that pack hunts your haulers. A harmed Stagborn herd refuses Rune Bonds and charges your riders. The goblin warren remembers raids (`relationships` faction).

### 5.3 Robbers and raids

**Wealth visibility:**

`W = 0.01 × (stores value + treasury) + 0.4 × population + 0.02 × pieces + 5 × connected roads + 0.05 × Renown`
- ×0.7 if hidden (no road link and forest cover over 50% within 150 m)
- ×1.3 during the Midsummer Fair and after a big sale

**Defence against bandits** (who ignore runestones, as in the existing code):

`D = Σ wall/gate HP / 100 + 3 × (garrison fighters × combat skill / 5) + 8 × towers + 6 × guard beasts + 5 × traps`

**Wards count only against monsters.** Monster raids use `threat_map` pressure against ward coverage and D.

| Quantity | Formula |
|---|---|
| Raid chance per day | `tier_base[T] × W/(W+60) × (1 − min(0.8, D/(W+1)))`, with `tier_base` = [0, 0.01, 0.02, 0.035, 0.05, 0.07, —] for T0–T6 |
| Raid size (robbers) | `ceil(2 + W/20)`, capped by tier: T1 4 · T2 6 · T3 12 · T4 20 · T5 40 |
| Telegraph | a rumour 1 day before (scouts seen, smoke); **an extortion letter** 50% of the time: "Pay W × 2 gold, or burn" → **Pay** (heat 0, but the band returns in 14 days with +20% demand), **Refuse**, or **Ambush** (Call your people, set traps) |
| Minimum gap | 5 days between raids on the same settlement; at most 1 during the first 10 days of a new claim ("beginner's grace") |
| Robber bands | sim entities (the Ashen Hand in Region 1; band origin, twist T3): `{treasury, men, morale, grudge_list}`. A band that loses more than 40% flees. Wiping it out ends that band, and a new band forms from grudge agents after 20+ days. |

**Resolution.** If you are within 350 m, the raid is physical: the raiders are a `squad.gd` block against your garrison and followers, with the Call live.
If you are farther away, it is resolved abstractly: `loss = clamp((A − D) / A, 0, 0.8)` of targeted stores, plus burned pieces, where `A = raiders × 3`. The raid is recorded for **Ashsight** (L11), so you can read what happened when you arrive.

### 5.4 Danger tiers and region gates

`player_level = 1 + √merit + age/4` (existing `Life.player_level`). Soul tiers come from `soul.gd` (Ember, Kindled, Warmed, Tempered …).

| Tier | Name | Rec. level | Soul tier | Retinue | Region 1 areas | Founding allowed | Required to hold a claim there |
|---|---|---|---|---|---|---|---|
| T0 | Hearth | 1–5 | — | — | the Ashford ring, Kingsreach, Crownstead, the King's Ember Road | no (buy lots only) | — |
| T1 | Warded | 5–7 | Ember | 0–1 | village rings, Silverford surrounds, Millbrook fields | Freehold, Charter | — |
| T2 | Rural | 6–9 | Kindled | 2+ | Greenhollow edge, inner Elden Road, the Eastmere meadows | Squat, Charter | 10 days of food, a tent per 2 |
| T3 | Frontier | 8–12 | Warmed | 4+ | Duskbriar Wood, Westfen edge, Greyseam hills, the Grimfen approach | + Ward Claim | a palisade within 7 days, 4 fighters, 20 days of food |
| T4 | Wilds | 11–15 | Tempered | 8+ | Tuskridge, outer Stagborn Glade, deep Duskbriar | Ward Claim | own runestone at power ≥ 0.6, 8 fighters, a runecarver, stone walls by Village tier |
| T5 | Rift-touched | 14–18 | tier 5 | 12+ | the Ashen Scar edges (contained cells only) | Ward Claim on contained cells | + a Scar-grazer or 2 fire teams, rift pens |
| T6 | Rift mouth | 18+ | tier 6 | — | the Scar mouth and arena | never | — |

The map and compass show the tier as a small shield icon with the recommended level. Entering a zone 3+ levels above you shows a single warning card ("Wolves hunt here in packs of 6. Recommended level 11.") once per zone, then only a subtle red shield edge. It is *heard, not labelled*, per the life-sim design.

**Region gates** (teases now, content later):

| Gate | Requirement |
|---|---|
| Eastern Gate → Church realms | a **Travel Writ**: Crown favour ≥ 30 **or** Church standing ≥ 40 (Oriel's route) |
| Grimfen Pass → Frostcrown Holds | spring thaw, level ≥ 10, winter gear, **or** Alaric's quest |
| Sun-Road → Solkar Dominion | Marisol's caravan contract, **or** 2 caravans owned |
| Rift → Ember and Bloom Rifts | Region 1 complete (the finale) |
| Westfen → Verdanweald / Umbrafen | Tamsin's trust **or** Veyl ranger standing ≥ 40 |

### 5.5 Defence

| Tool | Against | Value |
|---|---|---|
| Palisade / stone wall / gate | bandits, beasts | HP 200 / 1,200 / 600–1,500; raiders must breach (X11 ram and ladder behaviours at sieges) |
| Watchtower / stone tower | all | +8 D; 2 archers fire at 40 m (the bow from X5) |
| Traps (stakes, pits) | all | +5 D each; one use, then repair |
| Alarm bell / alarm stone / beast Ember stone | all | telegraph +30–60 s; auto-Call of the garrison |
| **Runestone / ward posts** | monsters only | coverage (N1); strong monsters enter briefly, weak ones refuse (existing rules) |
| Garrison + guard beasts | all | D (above) |
| Hired guard companies | bandits | 12/day per man, arrive by raven Call |
| Diplomacy | robbers | tribute (the extortion letter), or hire the band (§6.2 "purchase") |

---

## 6. Conquest and politics

### 6.1 What can be taken, and how

✓ = allowed · ~ = conditional · ✗ = not possible.

| Target | Force | Siege | Intrigue | Purchase | Duel | Loyalty | Becomes |
|---|---|---|---|---|---|---|---|
| **Bandit camp** (Ashen Hand) | ✓ | — | ✓ turn a lieutenant | ✓ hire the band as mercenaries | ✓ challenge the chief (outlaw code) | ✗ | an outpost (Camp-tier holding) or your robbers |
| **Monster warren / orc hold** | ✓ | ~ (Tuskridge palisade) | ~ | ✗ | ✓ **the Tusking** (orc chief challenge) | ✓ gifts + protection 30 days | a vassal tribe (tribute, named-monster recruits) |
| **Village** (a house's fief) | ~ only with a casus belli | ~ | ✓ discredit the lord → the Crown revokes the fief | ✓ `nobility.gd` sale (struggling houses sell) | ✗ | ✓ **petition**: residents ask the Crown for you | a holding (`lordship.grant`) |
| **Stronghold / keep** | ~ casus belli | ✓ if held by outlaws, rebels, foreigners or a feud enemy | ✓ a bribed castellan opens the gate | ~ buy the castellan office (Council) | ✓ trial by combat for the castellanship | ~ | a holding + garrison |
| **Faction** (Silverford Guilds, Runeward Legion, Order of the Highwatch) | ✗ | ✗ | ✓ buy votes, blackmail (Ashsight evidence) | ✓ majority share of the Merchants' Hall (Guilds only) | ✓ Highwatch Grand Tourney (Order) | ✓ rise through seats (`careers.gd`) | you lead it (a guildmaster, Grand Warden or Lord Commander seat) |
| **Sect / school** (Old Mill Staff Yard, Greywatch Spear Hall; foreign sects later) | ✗ | ✗ | ~ | ✓ **patronage**: fund it (small schools only) | ✓ **sect challenge ladder**: defeat its elders | ✓ rise as a disciple (the `sects.json` ranks) | patron or master; its disciples become recruits |
| **The Crown / a kingdom** | ✗ | ✗ | ✗ | ✗ | ✗ | the path to king (§6.7) | — |

**Casus belli** (a *Writ of Feud* from the Council of Wardens, §6.7). Without one, force against a Crown vassal is **Breaking the Crown's Peace**: Notoriety +40, Crown favour −50, every house −20, and a royal punitive force (a 2 × 100 company) marches in 5 days.

| Valid casus belli |
|---|
| The holder is at blood feud with you (heat ≥ 90) |
| The holder harboured robbers who raided you (proved by an Ashsight record) |
| The holder broke a contract or charter with you |
| The holding is in revolt, or held by outlaws |
| War: an enemy nation's holding (`war_sim.gd` front regions) |
| A Crown commission: the Council orders you to take it |

### 6.2 Methods in detail

| Method | Mechanics | Time | Costs and risks |
|---|---|---|---|
| **Force** | a field battle: your squads + followers against the defenders (`squad.gd`, `morale.gd`, formations); win when the defender morale is Shattered or their leader is captured | minutes (physical) | casualties, grudges from the defenders' kin |
| **Siege** | `siege.gd`: `{defenders, stores_days, walls_hp, morale, relief_eta}`. Each day: stores −1 (−2 while bombarded), defender morale −3 while < 5 days of stores remain, your camp costs rations + wages, and disease p 0.02 per 20 men. You can **Assault** (ladders or ram; physical near you), **Starve** (they surrender at 0 stores or morale < 15), or **Negotiate** (terms: let the garrison walk out, which gives +legitimacy). A relief force arrives at `relief_eta`. | 3–20 days | very expensive; the Crown watches (a casus belli is needed) |
| **Intrigue** | ops run by a **spy** follower (Brannoc) or bought agents: *Bribe* (gold = 10× the target's wage), *Blackmail* (needs an Ashsight record of a crime), *Discredit* (plant rumours, N6), *Turn* (a grudge agent against their own lord). Each op: `success = spy skill × 0.08 + evidence 0.3 − target vigilance`. A failed op reveals you (Notoriety +10, the target's grudge +30). | 3–10 days per op | failure = scandal |
| **Purchase** | houses sell when wealth < 800 (`STRUGGLE_WEALTH`) or they are in debt (`LOAN_*`). Price = `property value × 1.2 + (loyalty of residents to the old lord) × 5`. Bandits sell themselves for 20 days of wages. | instant + audience | gold |
| **Duel** | formal, one versus one (X11), in a chalk ring or before the court; its rules come from culture: Caldric *trial of steel* (first blood ×3), the Urrokai *Tusking* (to yield), a sect challenge (3 elders in sequence), and the outlaw code (to the death). The winner takes the prize; the loser's side accepts (no grudge from Honourable traits). | minutes | death is possible (to the death only in the outlaw code) |
| **Loyalty** | residents' opinion of you vs their lord. When `avg opinion of you − avg opinion of lord > 30` for 14 days and your **Bread Debt** there is ≥ 20 × population, they **petition** the Crown; with Crown favour ≥ 20 the Council grants you the fief. Needs no violence. | weeks | slow; the old lord gets a grudge (+45) |

### 6.3 Holding and governing

Every holding runs on `lordship.gd` (treasury, tax, loyalty, food, militia, issues, projects), extended by `holdings.gd`:

| Stat | Range | Set by |
|---|---|---|
| **Legitimacy** | 0..100 | how you took it: appointment 85 · marriage 75 · purchase 70 · petition 80 · duel 55 · negotiated surrender 45 · conquest by force 25 · siege assault 15. It drifts toward 50 at +0.2 a day when governed fairly, and receives +1 per 50 Bread Debt rations. |
| **Control** | 0..100 | garrison strength ÷ population + walls; a steward present +20 |
| **Loyalty** | 0..100 | existing `lordship` loyalty; it cannot exceed legitimacy + 30 |

A **steward** follower (stewardship skill) auto-resolves issues by a policy you choose: *Thrifty · Generous · Martial · Pious · Rune-true*. That adds +10% tax efficiency and skips issue popups, which matters on mobile with 8 holdings.

Holdings you did not build get **districts**: a 40 × 40 m plot where free building is allowed (≤ 150 pieces), plus the existing lordship projects.

### 6.4 Rebellion

`Rebel strength = population × (1 − loyalty/100) × (1 + grievances × 0.2) × (1 − control/150)`, where grievances are active grudge agents in the holding plus harsh tax plus famine.

| Stage | Trigger | What happens | Player options |
|---|---|---|---|
| Murmurs | loyalty < 40 | rumours, −10% tax | feast (the festival project), lower tax, a public justice ruling |
| Unrest | loyalty < 25 (existing) | strikes, sabotage by agents | a garrison surge, arrest the leaders (+kin grudges), bread distribution (Bread Debt) |
| **Uprising** | loyalty < 8, or rebel strength > garrison × 3 | rebels seize the holding (the steward is captured) | retake it (a siege without a Writ is needed: it is your own land), **negotiate** (their demands: a lower tax, a new steward, weregild), or let it go (Renown −20) |
| **Your own followers** | an Ambitious lieutenant with Renown ≥ 30 and loyalty < 10 | a mutiny (§2.7), possibly taking a holding they garrison | duel, buy off, exile |

### 6.5 Why kingdoms cannot be conquered

| Reason | Type | Rule |
|---|---|---|
| **The Crown of Wards** | lore + mechanic | The runestone network of Valencious is oath-keyed to the anointed line at the five Elder Stones. A crown taken by force breaks the oath and **every Crown-keyed stone goes dark**: the realm floods with monsters and no house or village follows the usurper. Crown-flagged entities (Kingsreach, the Crownstead estate, the King's Ember Road stones, Highwatch while loyal) carry `unconquerable_crown`. |
| Scale | sim | the realm army goes up to 12,500 (`RAMilitary`); the player's max is 5 × 20 plus companies |
| The Church and the neighbours | politics | an attack on the Crown triggers Church intervention (Aurelis) and the war candidates (`war_sim.gd`) |
| Design | pillar P3 | the owner's brief: *"becoming king is never a level-50 perk; there must be an actual path"*. Kingship must be earned in public. |

Treason is still possible as a **doomed scenario**. It sets the *Kinbreaker* flag: stones dark within 1 km of all your holdings, all houses at −60, the royal host marches, and the result is the "Usurper's End" epilogue. The character's Ember is lost (it cannot rest in any stone). It is a teaching failure, telegraphed with two confirmation cards.

### 6.6 Noble ranks of Valencious

| Rank | Title on screen | Requirements | Grants |
|---|---|---|---|
| 0 | Commoner | — | — |
| 1 | **Freeholder** | own land (a freehold, charter or ward-claim freehold) | vote at your village moot; charter audiences |
| 2 | **Knight** | dubbed by the Order of the Highwatch (seat vacancy + War Merit Ledger ≥ 40), by the Crown for a Deed, or sponsored by Sir Alaric | court access; retinue R3 cap; the right to bear arms in Kingsreach |
| 3 | **Banneret** | a knight holding a Village-tier holding (founded or granted) with ≥ 20 men | your own banner (the **sigil editor**, L45); Writ of Feud petitions |
| 4 | **Baron** | 2+ holdings, one Town or Stronghold; Crown favour ≥ 40; you **found a House** (a dynasty record in `nobility.gd`, so you become house #7) | a house vote in the Moot; arranged marriages offered to your children |
| 5 | **Earl / Warden of a March** | 4+ holdings forming a contiguous March (≤ 1.2 km between seats); defended a frontier (a Deed); Crown favour ≥ 60 | eligible for a **Council seat**; Ember Beacon; levy rights |
| 6 | **Council of Wardens** (a seat, not a rank) | a vacancy + the King's approval (favour ≥ 70) or a council vote (4/7) | a seat power (below) |
| 7 | **Crown** | §6.7 | King or Queen of Valencious |

**Royal favour** (−100..100) is the `crown` faction reputation.

| Favour change | Δ |
|---|---|
| Relight an Elder Stone (Act IV) | +15 each |
| Contain the Scar front (per 10 cells pushed back) | +3 |
| Tithes paid on time (per season) / late | +2 / −6 |
| A court audience with a gift (≥ 100 gold of goods) | +3 (once a week) |
| Win a war battle / hold a front town | +5 / +8 |
| Win the Midsummer tournament at Highwatch | +6 |
| Break the Crown's Peace | −50 |
| Scar spreading on your land (per week uncontained) | −2 |
| A scandal (a failed intrigue op, an elopement) | −10 to −30 |

**Council of Wardens.** 7 seats, using the `careers.gd` seat model. The current holders are generated from the noble houses.

| Seat | Requires | Weekly duty (one decision card) | Power |
|---|---|---|---|
| Lord Marshal | war merit ≥ 120, Earl | muster levies, pick war targets | issues Writs of Feud; commands the royal host in war |
| Lord Steward | treasury ≥ 5,000 managed, Merchant ladder rank 5 | taxes and tolls | ±10% on crown tolls; buys offices |
| **Warden of Stones** | Wardwright rank 4, the Runeward Legion | ward budget priorities (L7) | +20% flow budget on your stones; decides which roads go dark |
| Master of Roads | 3 caravan routes, 2 km of built road | road works | builds kingdom roads (road-generator); tolls |
| Keeper of Whispers | spy network ≥ 3 agents, Notoriety < 30 | intrigue reports | sees every active grudge agent against the Crown and you |
| Lord Chancellor | Scholar / Scribe career, law | judgements and inheritance | rules on succession claims (+1 tie-break vote in the Moot) |
| Warden of the North | holds Highwatch or a northern March | the Grimfen Pass | opens the Frostcrown gate (Region 2) |

### 6.7 The path to king

**The royal family.** Generated from the seed with fixed roles:

| Royal | Age at the player's 16th | Role | Traits | Courtable |
|---|---|---|---|---|
| King Aldric III Caldrenn | 68 | the king; failing health (yearly death roll from age 70: 8%, rising 4% a year; a year is 12 days) | honourable, rune-true | — |
| Crown Prince Edric | 34 | heir; a warrior who leads the war front | martial, proud | yes (unwed) |
| Princess Maerwen | 22 | a runecraft scholar at the Royal Ember Academy; anti-Church | curious, rune-true | yes |
| Prince Corwin | 15 (adult 12 days later) | ambitious; Church-leaning (Envoy Lucan's favourite) | ambitious, pious | yes, from 16 |
| Lady Isolde Caldrenn | 31 | the king's widowed niece; one son (age 4) | shrewd | yes (opens the Regent route) |

Any adult royal can be courted by a player of any sex. Heirs from a same-sex royal marriage come by adopting a Caldrenn ward, an existing custom invented here for succession clarity.

**Deeds of the Realm** extend the War Merit Ledger. Each gives Renown, favour and **Legend**:

| Deed | Renown | Legend |
|---|---|---|
| Relight an Elder Stone | 25 | 10 |
| Slay the Scarbound Troll (the Region 1 finale) | 60 | 30 |
| Contain the Scar to its mouth | 40 | 20 |
| Found a Town / a Stronghold | 30 / 45 | 10 / 15 |
| Defend a settlement against a raid of 20+ | 20 | 5 |
| Win the Midsummer tournament | 20 | 5 |
| Save a royal's life (event) | 40 | 20 |
| End a blood feud by peace | 15 | 5 |
| Tame a Stagborn / raise a wyvern | 10 / 30 | 3 / 10 |
| Hold a front town in war for 7 days | 35 | 10 |

**The royal suit** (extends `family.gd` courtship: interested → courting → betrothed):

| Stage | Needs |
|---|---|
| Presented at court | Knight or higher; court access (an audience granted) |
| Interested | the royal's opinion ≥ 30; 3 audiences with conversation (dialogue) |
| Courting | opinion ≥ 65 (close friend); Banneret or higher |
| **Suit** (new) | three **Proofs**: a Deed (Legend ≥ 20), a gift of rare worth (a relic, a wyvern egg, rift alloy jewellery, ≥ 800 gold of value), and a sponsor on the Council (opinion ≥ 50) |
| Betrothed | the King's approval: favour ≥ 60 **or** the royal is of age and insists (the King at −10; it raises a house grudge from rival suitors) |
| Wed | a royal wedding event (Kingsreach cathedral-yard **ring stone**, not a Church altar: Oriel and Lucan react) |
| Elopement (alternative) | skip the approval: favour −40, the royal is disinherited, and you lose the marriage route to the crown but keep the spouse (a romance ending) |

**Succession crisis.** It fires when King Aldric dies (a natural death roll, or events: an assassination plot by the Church faction, a war death, Scar plague).
- If Crown Prince Edric is alive and of good standing, he accedes and the crisis is *minor*: only a claimant with a royal spouse can contest.
- If Edric is dead (war, or a Scar event if the Scar is not contained by Act V), there is a *major* crisis: the **Moot of Wardens** meets 7 days later.

Claimants (major crisis): Princess Maerwen (or her spouse), Prince Corwin (the Church-backed claimant), Lady Isolde's son (a regency), the strongest house head, and **the player** if eligible. The player is eligible if any of these holds:
- (a) married to a royal
- (b) Earl + Legend ≥ 120 + favour ≥ 60
- (c) named heir by the King (an adoption event: favour ≥ 90 and Edric dead or disinherited)

**The Moot vote** (twist T5): 18 votes, **10 needed**.

| Voters | Count | Votes for |
|---|---|---|
| Council seats | 7 | the claimant the seat-holder likes most (opinion + policy alignment); bribable (a seat's price is 10% of their house wealth + −10 favour if revealed) |
| Noble houses | 6 (+1 if you founded a House, which votes for you) | house opinion + marriage alliances + feud enemies against |
| **Elder Stones** | 5 | the claimant with the highest **Hearth-right** at that stone: relit it (claimant or kin) +3, each ancestor Ember resting in it +2, holding the land it stands on +1. A tie abstains. |

**Routes to the crown:**

| Route | Summary | Typical adult day |
|---|---|---|
| **By marriage** | wed Maerwen, Edric or Isolde. If your spouse accedes, you are crowned **consort-king/queen** when the Council approves (4/7). To rule *in your own right*, win a Moot on your spouse's death or in a crisis. | 200–280 |
| **By merit** | Earl + Council seat + Legend ≥ 120 + relight Elder Stones (they vote for you) → win the Moot in a major crisis, **or** be adopted as heir | 260–320 |
| **Kingmaker** | back a claimant and win the Moot for them → you become **Regent** (under Isolde's son) or **Hand of the Crown**, then take the crown if the child dies or on a later crisis | 220–300 |
| **Dynastic** (Ember Legacy) | your child with a royal spouse inherits; your ancestors' Embers in the Elder Stones carry the Moot generations later | the next life |

**Ember Legacy tie-in.** Ancestors resting in stones give **Hearth-right**. A family of Wardwrights that puts its dead into the Elder Stones owns the Moot over generations. Your heir inherits (N3 + `family.gd`):
- retinue loyalty ×0.6 (Oathsworn and companions ×0.9)
- holdings (legitimacy −15)
- grudges (heat ×0.5)
- Renown ×0.3
- Bread Debt ×0.5
- the rank one step down (a Baron's heir is a Banneret until confirmed by the Crown within 28 days)

**After the crown** (post-game): a King mode with weekly council cards, war and peace with the neighbours, the Church question, and the Region 2 gates opened by royal decree. You can still ride out with your retinue. The throne room is a Stronghold-tier blueprint for your capital.

---

## 7. Integration

### 7.1 With the Region 1 mechanics

| Mechanic | Retinue | Taming | Settlement | Threats | Politics |
|---|---|---|---|---|---|
| **N1 Wardwright** (L7, L8) | the rune-signal Call runs on the ward graph | Rune Bond glyph; Stagborn Wardwalkers | Ward Claim (Hearth glyph, own stone); coverage for Hamlet tier; ward posts | wards stop monsters, not robbers; sabotaged stones cut Calls | Warden of Stones seat; Elder Stones vote |
| **N2 Scar Tide** (L9) | Rift-touched trait; scar sickness | rift beasts, Scar-grazers | no claims in Scar cells; scar crystal → rift alloy economy | scar-mutant raids on T5 claims | containment gives favour; Edric's fate depends on the Scar |
| **N3 Ember Legacy** (L10) | companion Embers (warning voices); heir inherits the retinue | beast Embers (howling alarm stones) | your settlement passes to your heir | grudges inherited by kin and heirs | Hearth-right in the Moot; dynastic route |
| **N4 Ashsight** (L11) | find a traitor or thief in the retinue | read what happened to a lost beast | read abstract raids after the fact | **grudge origins** (twist T3); proof for a casus belli | blackmail evidence for intrigue |
| N6 Rumour Market (read side) | — | — | — | extortion and raid telegraphs as rumour cards | Discredit ops plant rumours |

### 7.2 With the main quest, "The Stones Are Dimming"

| Act | New beats from this design | Teaches |
|---|---|---|
| I, Ashford (to age 12) | Wren joins as a friend (1 follower; Follow and Standby); the first horn from Maren | the Call with 1 person |
| II, the Vale | an apprentice wage; the first hire (a labourer) for the harvest; Brannoc's ambush and the parole choice | wages, rations, loyalty, prisoners |
| III, Silverford and Kingsreach | **"Rekindle Emberpost"**: Warden Idra asks you to found a Ward-Claim camp around a dark stone on the Elden Road (a guided founding: tent → fields → palisade → relight). The first winter follows. Hesk and Oriel become available. | claim, build, food math, the first raid (a scripted small raid in the grace window) |
| IV, the Elder Stones | each relight needs retinue roles: **Glade** (a Rune Bond with a Stagborn + Tamsin), **Greyseam Mine** (6 haulers or miners for 2 days), **Highwatch** (knighthood or Alaric's sponsorship), **Crownstead** (Crown favour ≥ 20), **Elden Road** (your Emberpost at Hamlet tier) | taming, tasks, rank, settlement growth |
| Finale, the Ashen Scar | **the Great Call**: an Ember Beacon, or every channel you have; allies arrive by ETA while you hold the line; Scar-grazers and fire teams push the Tide | the Call at scale |
| Post-game | Council, succession crisis, the Moot | politics |

The Act III founding and the Act IV role requirements go into L14's quest data as new steps. That is package C20 (a data addendum; L14 itself is not reopened).

### 7.3 Future regions

| Region (poster) | Retinue | Beasts | Settlement rules | Politics twist |
|---|---|---|---|---|
| Solkar Dominion | caravan guards, sun-mages | sandstriders, drakes | water rights instead of ward coverage; oasis claims | the Sun-Court's merchant-princes: kingship bought with water |
| Frostcrown Holds | clan warriors, skalds | frosthorns, dire wolves | winter lasts 2 seasons; firewood ×3 | kin-moots: a jarl is elected by feats |
| Church realms (Aurelis, Varska, Serathi) | knights of the orders, inquisitors | — | parish charters; tithes 50% | the Church crowns kings: a relic-legitimacy mirror of the Elder Stones |
| Verdanweald | Veyl rangers | barkhorns, stag spirits | no felling of old trees; living-wood building | elders' circle; bonds over rule |
| Zephyr Steppe | horse archers | thunderhoof, sky elk | **mobile camps** (yurts), no fixed claims | khan by the Games of the Three Winds |
| Ashenreach, Umbrafen, Jadecliff, Tideclad | forge guilds, alchemists, sect disciples, sailors | obsidian beasts, marshbeasts, celestial beasts, reef leviathans | forge-heat, stilts, terraces, harbours | guild oligarchy, secret councils, sect ascension, sea-empress favour |
| The Rifts | expedition crews (the existing Rift career) | rift fauna by element | expedition camps only (no permanent claims) | none: survival |

---

## 8. Never-seen-before: five original twists

| # | Twist | What it is | Why it's new |
|---|---|---|---|
| **T1** | **The Call rides the stones** | Your summon travels over the ward grid you maintain. Each dark stone is a gap in who can hear you. Roads you drew shorten each ETA. Robbers learn this: a raid is **preceded by stone sabotage** so your Call chain breaks (Ashsight can prove it). The ETA sheet is a live readout of your infrastructure. | Mount & Blade and Bannerlord parties are always with you. Palworld and Valheim bases are islands. Here reinforcement is a **physical, simulated signal** that depends on player-built infrastructure, and enemies can target it. |
| **T2** | **Kings are made of bread** (the Bread Debt ledger) | Every ration you give to someone in need is logged against their name and village: followers in a famine, refugees, a starving holding, winter aid to a rival's village. The debt is *called in* at key moments. Fed villagers **open siege gates** for you, petition the Crown to hand you their fief, vote your way through their house, and back you in rebellions. It decays only by 1% a day. | Legitimacy in Crusader Kings and Bannerlord is an abstract meter. Here it is a **ledger of real, attributable acts** inside a living food economy, so the harsh early-game food math becomes the late-game political currency. |
| **T3** | **Every robber was someone** | Raiders are not spawned from nothing. Robber bands recruit from **actual grudge agents**: tenants you evicted, workers you fired, kin of bandits you hanged, deserters you starved. Ashsight shows the moment the grudge was born. You can end a band by **restitution** instead of the sword, and grudges pass to kin and to your heir. | Kingdom Come and Bannerlord bandits are faceless respawns. Nemesis-style systems (Shadow of Mordor) track enemies you fought; this tracks **people your economy and politics wronged**, and makes peace a playable answer. |
| **T4** | **Living wards** | Tamed beasts are infrastructure. Stagborn Wardwalkers keep ward-lines lit by grazing along them. Scar-grazers eat the corruption front but may mutate and turn feral. Beast Embers become howling alarm stones. | Palworld pals work stations inside a base. Here beasts **reshape the region-scale safety simulation** (N1 and N2) outside any base, with a real risk. |
| **T5** | **The stones crown the king** | The crown can't be seized, because the realm's wards are oath-keyed to the anointed. It is decided at a **Moot where the five Elder Stones vote** through the embers of the dead who rest in them. A dynasty that puts its ancestors into the stones earns the throne across generations. | No game ties its **succession law to player-maintained world infrastructure plus the player's own dead characters**. The title "Rising Ashes" becomes the literal path to power. |

**Differentiation check** (the `ashes-game-design` list):

| Game | What it does | What we do differently |
|---|---|---|
| Mount & Blade / Bannerlord | party follows the map icon; conquer any castle; kingdoms can be founded by force | the physical Call with ETA and refusal; the Crown can't be conquered, only earned (T5); legitimacy from bread (T2) |
| Palworld | capture creatures with spheres; base automation | subdue plus the rhythm Calm, Rune Bond or raising young; beasts as world infrastructure (T4); starvation that bites |
| Valheim | free building with structural support; raids by biome progress | the same freedom, made for thumbs (blueprints, Row, Plan mode, worker-built); raids from wealth, visibility and grudges |
| Manor Lords | a settlement sim with fields, burgage plots and a small retinue | you are an embodied person in an open world; the settlement is one of up to 3; politics climbs to the throne |
| Kingdom Come | grounded medieval RPG; no founding | founding, taming and ruling in a grounded economy |
| Zelda / Genshin | companions as combat add-ons; corruption set pieces | companions with wages, grudges and embers; corruption as a contested, farmable resource |
| Stardew / Fable | a farm and a family; generational legacy (Fable) | farming is a survival constraint for a whole community; legacy decides a royal Moot |

---

## 9. Economy and balance targets

### 9.1 Targets by phase

| Metric | Early (adult days 0–25) | Mid (25–110) | Late (110–300) |
|---|---|---|---|
| Player income per day | 12–40 (wages, guild F–D jobs) | 60–180 (a C–B guild rank, career rank 3–4, settlement surplus) | 250–900 (holdings, trade, office) |
| Retinue (roster / follow) | 0–3 / 1–3 | 6–20 / 6 | 40–400 / 10–12 + squads |
| Retinue upkeep per day | 8–30 | 60–200 | 300–1,500 (paid mostly by treasuries) |
| Upkeep ÷ income | **60–90%** (harsh) | 50–70% | 30–50% |
| Settlements | 0–1 Camp | 1 Hamlet → Village | up to 3 (Town / Stronghold) + 3–8 holdings |
| Food buffer | 3–10 days | 20–40 days | a full winter (40 days × population) |
| Beasts | 0–1 | 2–4 | 4–10 + a Stagborn herd |
| Rank | Commoner → Freeholder | Knight → Banneret | Baron → Earl → Council → Crown |
| Raids per season | ≤ 1 (2–4 robbers) | 2–3 (5–12) | 3–4 (12–40) + 0–1 siege |
| Real time | ≈ 5 h | +17 h | +38 h |

### 9.2 Milestone pacing (the balance bot, median of 20 seeds)

| Milestone | Target adult day | Hard bounds |
|---|---|---|
| First paid follower | 3 | 2–8 |
| First camp | 12 | 8–25 |
| First winter survived with ≥ 70% of people | — | 60% of bot runs on the "sane" policy; ≤ 20% on the "naive" policy |
| Hamlet | 35 | 25–60 |
| Knight | 60 | 45–90 |
| Village + lordship registration | 70 | 55–110 |
| Baron | 140 | 110–190 |
| Council seat | 200 | 170–260 |
| Crown (marriage route, given a crisis) | 240 | 200–280 |
| Crown (merit route) | 290 | 260–320; **never before day 150** |

### 9.3 Sim tests to validate

In `tools_qa/ascension/asc_balance.gd`, extending the L18 balance tool with archetypes *Warband*, *Founder*, *Courtier*, *Tyrant* and *Saint*.

| ID | Test | Pass |
|---|---|---|
| S1 | **Starvation spiral**: a 6-person camp founded mid-autumn with 10 days of food and 2 farmers, naive policy | collapses (≥ 50% leave or starve) by winter day 20; the sane policy (4 farmers + hunter + storehouse + a 90-ration purchase) keeps ≥ 80% |
| S2 | **Wage runway** | the early archetype sustains 2 followers from wages by day 10, not before day 5 |
| S3 | **No money loops**: hire/dismiss, gear resale (50%), beast resale (≤ 60%), deconstruct refunds (50%), own-settlement arbitrage | no loop yields > 1.2× market over 30 days; the gold-per-hour curve is monotonic, with no spikes > 3× the phase target |
| S4 | **Raid fairness** | with a "reasonable defence" build per tier, the median raid loses < 15% of stores and the worst 5% < 40%; no raid above the tier cap; beginner's grace is honoured |
| S5 | **Grudge equilibrium** (300 days) | active agents ≤ 12; the Saint ends with ≤ 3 enemies, the Tyrant with ≥ 20 grudges and ≥ 1 uprising |
| S6 | **Rebellion math** | a conquered village on harsh tax revolts in 20–40 days; fair tax + bread distribution lifts loyalty above 50 in about 30 days |
| S7 | **Crown pacing** | the merit and marriage bots hit the crown inside §9.2 bounds in ≥ 60% of seeds; 0% before day 150 |
| S8 | **Call ETA properties** (gdUnit) | ETA monotonic in distance; a road cuts ETA ≥ 25%; mounted ≤ 45% of on foot; one dark stone breaks the rune chain → raven fallback; deterministic per seed |
| S9 | **Taming curve** | first-try success is 35–60% at the recommended level; a wolf is feasible at level 6; a bear needs Tempered (< 10% below it) |
| S10 | **Performance** | a Stronghold with 2,200 pieces, 12 followers and 20 soldiers holds ≥ 30 fps on LOW and ≥ 60 on HIGH (`tools/qa/bench`); ghost placement < 1 ms; settlement tick < 2 ms; ascension save ≤ 400 KB; a no-hitch check (> 50 ms) over a 10-minute route through 3 settlements |

**Tuning flag for C21.** `lordship.BASE_TAX_PER_POP` (0.045 gold per person per day) makes a 60-person village yield about 3 gold a day, which is far below the mid-game target. The proposal is 0.25 plus production-surplus sales through `economy.gd`. Re-run L18 and L47 after the change.

---

## 10. Work packages

These come after the Region 1 packages in progress now: **L3, L4, L7, L8, L10, L11, L14, L16**. IDs continue the Region 1 numbering: **L21+, C14+, X8+**.

Each package is one Sonnet agent working 1–3 hours and follows `ashes-work-package`. The sandbox for sims is `tools_qa/region1/region1_sandbox.tscn --module=asc_<name>`, which works because the sims extend `Region1Sim`. Tests go in `tests/test_asc_*.gd` and run with gdUnit4, headless. UI screenshots are taken at 2400×1080 and 4:3. Motion is checked with frame sheets via `tools/qa/video_to_sheets.sh`, which the agent reads.

### 10.1 New hooks for the cloud (each ≤ 10 lines, commented `# Ascension hook (docs/design/RETINUE_SETTLEMENT_ASCENSION.md)`)

| Hook | File | Change |
|---|---|---|
| H8 | `scripts/ui/hud.gd` | `add_child(preload("res://scripts/ascension/ui/asc_hud.gd").new())`: the horn button, ETA sheet and build hammer |
| H9 | `scripts/world/terrain_streamer.gd` | a height-override Callable for claimed foundation cells (flatten or steps) |
| H10 | `autoload/world_sim.gd` | a `retinue_override: Callable` (person id → position or task) + `add_person(row)` for settlers |
| H11 | `autoload/life.gd` `record()` | forward actions to `AscBridge.on_life_event(tag, data)` (grudge causes, deeds) |
| H12 | `scripts/actors/monster.gd` / `wolf.gd` yield | offer "Tame" beside "Name" (≤ 5 lines; Codex owns the files' animation code, so C adds only the menu call) |
| H13 | `scripts/sim/lordship.gd` | reason `founded` + a pseudo-settlement registry for founded settlements (id ≥ 1000) |
| H14 | `scripts/actors/player.gd` | a horn-blow action trigger (the animation is from X9) |

### 10.2 Package list

**M6: Retinue and the Call**

| ID | Owner | Package | Outputs | Depends | Acceptance |
|---|---|---|---|---|---|
| **L21** | L | **Ascension scaffold + data**: `scripts/ascension/` layout, `asc_bridge.gd` stub, `data/ascension/{recruit_types,traits,ranks,deeds}.json`, `asc_rep.gd` (renown, notoriety, settlement rep, bread debt) | module + JSON + tests | L0 | gdUnit: rep math, bread-debt decay, JSON schema lint; sandbox runs `asc_rep` 60 days deterministically |
| **L22** | L | **Retinue sim** `asc_retinue.gd`: roster, wages at dawn (as bridge requests), rations, loyalty drivers, traits, modes, companies > 60, desertion, mutiny, injury and death, follower relationships | sim + tests | L21 | gdUnit: unpaid 3 days → desertion rolls; ration shortfall → loyalty table exact; save round trip; tick < 1 ms for 60 followers |
| **L23** | L | **Call sim** `asc_call.gd`: channels, 32 m travel grid A*, ETA formula, refusal, delay and ambush events, arrival triggers; reads a wardline graph via a Callable (L7 API) with a stub fallback | sim + tests | L22, **L7** | S8 passes; 12 path queries ≤ 3 ms; debug PNG of ETA ribbons |
| **L24** | L | **Recruitment** `asc_recruit.gd`: candidate generation from WorldSim rows (via ctx), offers and counter-offers, seat vacating, mercenary companies, parole prisoners | sim + tests | L22 | gdUnit: the cap by rank is enforced; the seat is vacated; the mercenary loyalty cap is 60 until Sworn |
| **L25** | L | **Retinue UI**: roster screen, recruit card, mode assignment (drag portrait), the horn radial, ETA sheet, compass pips widget (standalone Controls, `ashes_frame.gd` style) | `scripts/ascension/ui/*` | L22, L23 | screenshots 2400×1080 + 4:3; targets ≥ 48 dp; a frame sheet of the ETA countdown and status chips |
| **L26** | L | **Companion content**: 8 bios, intro scenes, personal quests (3 steps each) in the L14 quest and dialogue format; a lint | data + dialogue JSON | **L14** format | the L14 lint passes; each quest names its NPC, reward, mechanic and region tie |
| **X9** | X | **Follower behaviour** (LimboAI BT): follow formation around the player, standby idles, task work loops (chop, mine, hammer, carry, farm), the arrival run-in, Down and revive, taking a blow, the player's horn-blow animation | controller + BTs | X1, L22 | frame sheets: 6 followers on stairs, a gate and a bridge, no clipping; revive 3 s; the horn anim front and side |
| **C14** | C | **Retinue integration**: H8, H10, H11, H14; spawn follower bodies (a presenter); a recruit option in `talk_target` and `village_services`; wages from `Game.gold` via the bridge; modules.json rows | small hooks | L22–L25, X9 | in game: hire → follow → Call from 600 m with the ETA shown → arrives (video sheet); the save round trip keeps the retinue |

**M7: Taming**

| ID | Owner | Package | Outputs | Depends | Acceptance |
|---|---|---|---|---|---|
| **L27** | L | **Taming sim** `asc_taming.gd`: species table, trust and fear, 4 methods, bond levels, upkeep and feral, roles, Wardwalker and Scar-grazer effects (Callables into L7 and L9) | sim + tests | L22 | S9 passes; a Wardwalker raises stone power by exactly +0.1 per pass (stubbed wardlines); save round trip |
| **L28** | L | **Calm minigame + Rune Bond flow**: the heartbeat ring (`calm_ring.gd`), timing assist and no-rhythm modes; the Hearthbond and Scar glyphs added to `glyphs.json` via the L8 recognizer | UI + data | **L8**, L27 | windowed sandbox frame sheet; ≥ 95% recognition of the new glyphs on 40 strokes; input latency < 16 ms |
| **L29** | L | **Beast tack and housing art**: horse and Stagborn saddles, boar pack saddle, kennel, stable, sty, hive, rift pen, aerie (kit style, LOD1) | `assets/incoming/ascension/beasts/` + contact sheet | L5 | tris ≤ 3k per piece; storybook palette check; a turntable sheet |
| **X8** | X | **Beast companion behaviour**: follow, guard, fetch, haul (pack walk), Stagborn mount on `mount_controller` (forest speed, fence jump), Calm reactions (flinch, lean-in), Scar-grazer eat loop | controllers | X3, X7, L27 | frame sheets per role; Stagborn gallop without foot slide |
| **C15** | C | **Taming integration**: H12; tame from Yield; pens in the settlement; beasts in the Call; beast Ember choice via C5 | small hooks | L27, L28, X8, C5 | in game: subdue a wolf → Calm → it follows → guards the camp (video sheet) |

**M8: Settlement founding and building**

| ID | Owner | Package | Outputs | Depends | Acceptance |
|---|---|---|---|---|---|
| **L30** | L | **Land claims** `asc_claims.gd`: Squat, Freehold, Charter and Ward Claim; every rule in §4.1 (coverage, dens, Scar mask, distances, water, slope); the 28-day hold; bailiff and fealty events | sim + tests | L21, **L7** (coverage Callable), L9 stub | gdUnit per rule (a table-driven test); a debug PNG of the legal claim map for the whole region |
| **L31** | L | **Build grid + catalogue** `asc_build_grid.gd` + `pieces.json` + `blueprints.json`: sockets, support, plan states, packed 16 B saves | module + data + tests | L21 | gdUnit: snap cases, support failure and debris lists, 2,200 pieces save ≤ 60 KB, place check < 1 ms |
| **L32** | L | **Settlement sim** `asc_settlement.gd`: construction labour, hauling, jobs and seats, production chains, food, spoilage, firewood, contentment, housing, immigration, growth tiers | sim + tests + a 120-day CSV and PNG | L22, L31 | **S1** passes both policies; tick < 2 ms at 250 pop; tier transitions exact |
| **L33** | L | **Building kit art**: the Caldric wood and stone modular pieces with 3 build states (scaffold, frame, done), camp pieces, defences, the ward stone; an atlas material; LOD1 (Meshy + Blender, the `ashes-art-style` look) | `assets/incoming/ascension/kit/` + contact sheets | — | LOD0 ≤ 400 tris, LOD1 ≤ 120; one atlas; the style reference check; seams snap at 2 m (a Blender grid test render) |
| **L34** | L | **Build renderer** `asc_build_renderer.gd`: MultiMesh per kind, state and material; baking of Done buildings (≤ 2 ms slices, main thread); the HLOD proxy; LOD distances by tier | presenter + tests | L31, L33 | a bench: 2,200 pieces ≤ 60 draw calls on LOW; screenshots at 30, 120 and 400 m; S10 perf numbers logged |
| **L35** | L | **Build mode UI**: build camera, tray, ghost, Row, lasso, blueprint save, undo, Plan mode chips, the workers sheet | UI + sandbox | L31, L34 | 2400×1080 and 4:3 screenshots; 3 taps to place a cottage (scripted input test); a frame sheet of snapping |
| **L36** | L | **Finger roads** `asc_road_draw.gd`: resample, RDP, Catmull-Rom, snap; road-generator runtime build **or** the ribbon fallback (benchmark both, pick one, document it); tiers and costs; export surface multipliers to L23 | module + bench note | L31 | draw → road in < 50 ms for 200 m; screenshot per tier; ETA reduction ≥ 25% (S8) |
| **L37** | L | **Settlement ledger UI**: food days left, a contentment breakdown, jobs, tier progress checklist, raid log with an Ashsight link | UI | L32 | screenshots; every value traces to the sim (a test that binds fake sim values) |
| **X10** | X | **Builder animations**: hammering on a scaffold, carrying planks and stone, placing, sawing, paving; the player's hold-to-help | controllers | X1, X9 | frame sheets; hands on the tools; no foot slide on a scaffold |
| **C16** | C | **Settlement integration**: H9, H13; claim flow in the world; build mode from the Pack menu (absorbs `build_menu.gd`, homestead plots become the Freehold); settlers as WorldSim rows; the road join to `road_traffic` and `caravans` | small hooks + layout | L30–L37, X10 | in game: squat → build a camp → hamlet (video sheet, ≈10 min scripted); fps within 5% at Camp; the save round trip |

**M9: Threats and enmity**

| ID | Owner | Package | Outputs | Depends | Acceptance |
|---|---|---|---|---|---|
| **L38** | L | **Grudges** `asc_grudges.gd`: causes table, heat, decay, stages, a weekly agent action budget (≤ 12), kin inheritance, restitution paths, beast and herd grudges; Ashsight record ids stored when present | sim + tests | L21, **L11** (record id API; a stub if late) | **S5**; gdUnit per cause and stage; the agent cap holds under 500 grudges |
| **L39** | L | **Raid director** `asc_raids.gd`: W and D formulas, the raid chance, size caps, the extortion letter flow, robber bands formed from grudge agents (T3), abstract resolution, the beginner's grace | sim + tests + CSV | L32, L38 | **S4**; a 300-day CSV per tier; bands form only from agents |
| **L40** | L | **Danger tiers + gates**: `danger_tiers.json` for Region 1 areas (polygons from `first_region.json`), the recommended-level shield widget for compass and map, and the gate requirements table | data + widget | C0 | screenshots of the map with shields; lint: every Region 1 sub-area has a tier |
| **C17** | C | **Threat integration**: grudge causes from `life.gd` (H11 path); raids spawn as `squad.gd` blocks at your settlement; stone sabotage before raids (T1); raid records to Ashsight (C6); settlement threat into `Frontier` | small hooks | L38, L39, C6 | in game: evict a tenant → an agent → he joins a band → a raid, then Ashsight shows the eviction (log + frame sheet) |

**M10: Conquest and the Crown**

| ID | Owner | Package | Outputs | Depends | Acceptance |
|---|---|---|---|---|---|
| **L41** | L | **Holdings and conquest** `asc_holdings.gd`: the target × method matrix, casus belli and Writ of Feud, purchase, duel rules by culture, intrigue ops, loyalty petitions, legitimacy and control, rebellion stages, districts | sim + tests | L38, L32 | **S6**; gdUnit per method; the Crown's Peace penalties exact |
| **L42** | L | **Siege sim** `asc_siege.gd`: stores, walls, morale, disease, assault, starve and negotiate, a relief force | sim + tests | L41 | gdUnit: starve time matches the formula; negotiated terms give +legitimacy |
| **L43** | L | **Crown politics** `asc_crown.gd`: noble ranks, favour, Council seats (the `careers.gd` pattern), the Deeds ledger, royal family generation and ageing, crisis triggers, the **Moot vote** with Elder Stone Hearth-right (L10 ember API) | sim + tests | **L10**, L41 | 3 scripted crises give the expected winners; **S7** with the bot; the Kinbreaker path goes dark as specified |
| **L44** | L | **Royal suit** `asc_royal_suit.gd`: stages over `family.gd`, Proofs, approval, elopement, consort crowning rules | sim + tests | L43 | gdUnit: stage gates; elopement effects; a consort-king needs 4/7 Council votes |
| **L45** | L | **Politics UI + sigil editor**: rank and favour panel, Council chamber cards, the Moot vote screen (18 seats lighting up), holdings map layer (H6), the House sigil and banner editor (4 shapes × 12 charges × storybook palette) | UI | L43 | screenshots; the Moot animation frame sheet; the sigil renders on a banner material |
| **L46** | L | **Politics content**: royal family and Council bios, 20 politics event cards, 12 grudge and raid cards, conquest, duel and petition dialogue, the Act III "Rekindle Emberpost" and Act IV role-gate quest steps as data | data + dialogue | L43, **L14**, **L16** (tutorial prompts for founding) | the L14 lint; the owner reads the script |
| **L48** | L | **Court art**: Kingsreach throne hall + Council chamber interiors, coronation props, the Moot ring (`meshy_free` castle and church pieces, as in L2 and L3) | `scenes/interiors/throne_hall.tscn`, `council_chamber.tscn` | **L3** (style match) | `--shot=interior_throne_hall`; ≤ 150 draws |
| **X11** | X | **Duels and sieges**: a formal duel ceremony (bow, circle, yield), the Tusking, siege ladder climb, ram crew, gate breach | controllers | X4, L42 | 1v1 duel video sheet; a ladder climb with no hand float |
| **C18** | C | **Conquest integration**: holdings on the map, bandit camp and warren takeovers, `noble_courts` options (charter, petition, buy), siege spawn at keeps, Writ of Feud flow | small hooks | L41, L42, X11 | in game: buy a charter; duel a bandit chief → outpost; siege a rebel keep (video sheet) |
| **C19** | C | **Crown integration**: court sessions in Kingsreach, Council weekly cards, the succession crisis chain, a coronation cutscene (`cutscene_player.gd`), the King-mode post-game shell | small hooks + cutscene | L43–L46, L48, C9 | a headless bot reaches the Moot; a coronation frame sheet |
| **C20** | C | **Main quest tie-ins**: Act III founding, Act IV role gates, the finale **Great Call** (Ember Beacon) | quest data wiring | C7, C14, C16, L46 | autoplay completes Act III founding; a finale video sheet with ≥ 10 arrivals by ETA |

**M11: Balance, performance, review**

| ID | Owner | Package | Outputs | Depends | Acceptance |
|---|---|---|---|---|---|
| **L47** | L | **Ascension balance run**: `tools_qa/ascension/asc_balance.gd` (Warband, Founder, Courtier, Tyrant and Saint bots, 300 days × 20 seeds) → CSV + `docs/design/BALANCE_ASCENSION.md` | tool + report | L22–L43, L18 | S1–S7 and S9 reported pass or fail with numbers |
| **C21** | C | **Balance fixes**: lordship tax rescale (§9.3 flag), tuning JSON | small edits | L47 | a re-run meets §9.1 and §9.2 |
| **L49** | L | **Performance pass**: a Stronghold with 2,200 pieces + 12 followers + 20 soldiers + 3 settlements on LOW and HIGH | bench + `docs/qa/PERFORMANCE.md` update | C16–C19 | **S10** |
| **L50** | L | **Ascension review**: an aaa-review loop, stop-motion sheets of every flow (Call, tame, build, raid, duel, Moot) | `docs/design/ASCENSION_REVIEW.md` | all | pass or fail per section of this doc |

### 10.3 Milestone order and parallel lanes

| Wave | Starts when | Packages |
|---|---|---|
| **0 (now, alongside the in-progress Region 1 packages L3 L4 L7 L8 L10 L11 L14 L16)** | nothing needed | **L21 · L33 · L29** (L5 is done) |
| 1 | L21 done | L22 · L31 · L40 · L48 (after L3) |
| 2 | L22 / L31 done; L7, L8, L14 landed | L23 · L24 · L27 · L32 · L34 · L26 · L36 · X9 |
| 3 | L32 / L34 done; L11 landed | L25 · L28 · L30 · L35 · L37 · L38 · X8 · X10 |
| 4 | the M6–M8 sims done | **C14 · C15 · C16** · L39 · L41 · L42 |
| 5 | L10 landed; L41 done | L43 · L44 · C17 · X11 |
| 6 | L43 done | L45 · L46 · C18 |
| 7 | content done | C19 · C20 · L47 |
| 8 | last | C21 · L49 · L50 |

| Milestone | Contents | Exit check |
|---|---|---|
| **M6 Retinue and Call** | L21–L26, X9, C14 | hire, follow, the Call with ETA and refusal, all in game; the save round trip |
| **M7 Taming** | L27–L29, X8, C15 | tame a wolf, Rune Bond a Stagborn, a Wardwalker lights a road |
| **M8 Settlement** | L30–L37, X10, C16 | squat → Hamlet in a playtest; S1 passes; perf within 5% |
| **M9 Threats** | L38–L40, C17 | a grudge-born raid with an Ashsight origin; S4 and S5 pass |
| **M10 Conquest and Crown** | L41–L46, L48, X11, C18–C20 | a charter, a duel takeover, a siege, the Moot, a coronation; S6 and S7 |
| **M11 Balance and review** | L47, L49, L50, C21 | S1–S10 green; the review signed off |

---

## 11. Open decisions for the owner (recommended defaults)

| # | Question | Default |
|---|---|---|
| D1 | Permadeath for followers? | **On**, with Down-and-revive; a "Story" difficulty makes death an injury |
| D2 | Treason (the Usurper path) as a playable doomed scenario? | **Yes**, behind two confirmations |
| D3 | Royal courtship open to any sex, with adoption for heirs? | **Yes** |
| D4 | Max player-built settlements | **3** (the mobile budget) |
| D5 | Lordship tax rescale (0.045 → 0.25 per person per day) | **Yes**, after the L47 run |
| D6 | A Moot of 18 votes with 5 Elder Stones | **Yes**; it ties the crown to N1 and N3 |

## 12. Self-review (aaa loop on this design)

| Question | Answer |
|---|---|
| Done? | Every requested area has rules, numbers, UX, budgets, tests and packages. |
| What's generic? | The piece list and the production chains are genre-standard on purpose, because readability matters on mobile. The novelty lives in T1–T5. Risk: players may read the building as "Valheim-lite", so the first-hour hook must be the **first Call over the stones** (Act III founding) and the **first winter**. |
| What's missing? | Naval and Rift expeditions are deferred to their regions. There is no multiplayer. Children as future recruits are sketched only (via `family.gd` rules on NPC rows). |
| Biggest risks | (1) Runtime road-generator performance on phones: L36 benchmarks it, with a fallback. (2) The load of too many popups: stewards, policies and cards keep one decision a day at most. (3) Balance of the lordship tax (D5). (4) L7 and L10 API drift: every dependency goes through Callables, with stubs. |
