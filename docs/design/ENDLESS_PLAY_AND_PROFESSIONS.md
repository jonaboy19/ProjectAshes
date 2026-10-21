# Endless Play and Professions (EP-1 to EP-14)

Status: design, 2026-10-21. Godot 4.6.2, PC-first, game in `kingdom/`. Read-only audit: files were listed and their header comments, function lists and greps were read; function bodies were not read in full and no Godot or git was run. Where this document says EXISTS it means the module's header or function list describes it; "verify in the work package" is the rule for anything finer.

Sources read: `LIVING_WORLD_MASTER_PLAN.md` (MW rows), `LIVING_WORLD_SANDBOX.md`, `NPC_INTELLIGENCE_MAP.md` (NI rows), and the code under `kingdom/scripts/realm`, `kingdom/scripts/sim`, `kingdom/scripts/population`, `kingdom/data/careers`, `kingdom/data/npc`.

Owner's request: "Think of ways so professions never become boring, and things that keep people playing, unlike other games where too much repeating happens once you've maxed out. I want it to never stop; people always able to find new things."

**Owners.** cloud = systems (CPU, save, tests, data). Antigravity = all animation (clips, state machines, blends, IK, reaction clips). Codex = world (regions, sites, towns, water, hidden places, dressing, map). Where a row needs two owners the logic owner is listed first.

---

## 0. The one-paragraph answer

Games go stale at max level because the **problems stay the same size while the player's numbers grow**. The fix in this design is: when a profession is mastered, the numbers stop being the point. Mastery unlocks a **different kind of problem**: other people's problems (apprentices, rivals, guilds, a town that depends on you), then the world's problems (a famine, a war, a lost craft), then **legacy problems** (a house, an order, a name that outlives you). Every one of those problems is generated from the living simulation that already exists (shortages, rumours, secrets, courts, districts, wars), filtered through a **novelty budget** so the same shape of problem does not appear twice in a row. When a life ends, or is lost, the world is still there, so the next life starts from a different place in a story that is already in motion. The loop is never "do the same job faster"; it is "the job changes, the world changes, and you change what you are."

---

## 1. Principles against grind (the rules every generator and profession obeys)

**P1. Mastery opens new problems, not bigger numbers.**
A level threshold may raise a cap by a little. It must always also unlock a new *verb* (a thing you can do), a new *class of problem* (a thing that can now go wrong or be asked of you), or a new *relationship* (someone who now treats you differently). Test: for each profession tier, the data file must list at least one new verb and one new problem class (lint, EP-2).

**P2. Diminishing numbers, rising stakes.**
Gold per task is flat or falling above journeyman (`sim/casual_work.gd` already does this for day-work: full pay for a few shifts, reduced, then nothing). Rewards at mastery are *access*: a seat, a secret, a school, a charter, a patron, a name. Access creates new play; gold only buys more of the same.

**P3. The world changes around you.**
Seasons, harvests, wars, plagues, new laws, new roads and new rivals shift what each profession needs. A blacksmith's best product in a war year is not the best product in a peace year. `emergence.gd`, `district_values.gd`, `seasons.gd`, `migration.gd` already move these levers; this design makes every profession *read* them (P3 hooks, section 3).

**P4. Other NPCs compete and evolve.**
Every profession has living NPC masters and rising apprentices that use the same rules (the project rule: player and NPC use the same calls, as in `farming.gd`, `founding.gd`). They age, retire, die, get poached, found schools, and out-do the player in places. The player is never the only master.

**P5. Consequences and legacy.**
Work leaves *records*: named works, debts, graves, laws, schools, feuds, tales. These persist across generations (`dynasties.gd`, `events.gd` compaction, `reputation.gd` house subjects). The player's old decisions come back as problems and gifts decades later.

**P6. Problems come from the simulation, not a quest script.**
Shortages, secrets, unpaid wages, an unsafe road, a dead noble: all already exist as state. The Problem Frontier (EP-2) *reads* that state and converts it into a card the player can take or ignore. Nothing is invented without a cause line the player can trace (`events.gd cause`, `trace.gd`).

**P7. Failure is content.**
Every profession has failure modes that change the game state, not game over: a ruined harvest, a lost client, a disgraced name, a burned forge, an executed apprentice. Recovery arcs ("losing it all and rebuilding", section 6) are designed play, with their own rewards.

**P8. Never the same twice (novelty budget).**
Generators remember what the player has seen and are penalised for repeating shape (section 8). A player who has seen the "wolf den near the farm" board card three times gets a different *kind* of card next, even if wolves are the most urgent need.

**P9. Choice has a cost and a shape.**
A problem offers at least two valid ways to resolve it that differ in *who benefits* (the `MW-11` winners-and-losers list in `district_values.gd`). No single obviously correct button.

**P10. The player can stop the grind by choosing a different game.**
Every profession combines with others (section 5.2) and any life can be handed to an heir, so exhaustion of one path is an invitation to switch, never a dead end. No profession is a one-way door; `sim/biography.gd` keeps chapters when careers change.

**P11. Bounded, not chaotic.**
All generation obeys the existing loop controls: `emergence` depth 4, cooldown 120, 24 live chains; per-day caps; deterministic rolls `hash([WorldSim.SEED, tag, day, id])`; no reload-scumming (MW-35). Novelty must never become noise.

**P12. Cheap by construction.**
Day-tick, closed-form, packed arrays, no per-frame work in `scripts/realm`. Every new store has a cap and a byte cost in section 14.

---

## 2. What the project already gives us (inventory used by everything below)

| Capability | Where | Status | Note |
|---|---|---|---|
| Career ladders with real requirements and vacancies | `scripts/sim/career_ladders.gd`, `careers.gd`, `data/careers/ladders.json` (farmer, soldier, merchant, blacksmith, hunter, healer, innkeeper, guard, scribe, wardwright) | EXISTS | Ladders are finite: ends at a top rank |
| Deep scripted careers | `realm/scribe.gd` (6 ranks, mini-tasks in `scribe_data.gd`), `realm/soldier.gd` (5 ranks), `realm/career_trades.gd` (farmer, soldier, merchant, blacksmith, wardwright) | EXISTS | Strong early/mid, top rank is a cap |
| Skill and experience | `sim/mastery.gd` (only grows by doing), `skill_evolution.gd` (how an element was used), `crafting.gd` (quality tiers from skill), `progression.gd` | EXISTS | Player-side only; NPC masters have static bytes (MW-32 MISSING) |
| Organisations (guilds, companies, orders, academies, syndicates, bands) | `realm/organizations.gd` (3,112 lines, 10 types: adventurer guild, craft guild, merchant company, mercenary company, farmers' co-op, criminal syndicate, religious order, academy, militia, band) | EXISTS | Player and NPC found them; schism, succession |
| Businesses and enterprise | `realm/businesses.gd`, `enterprise.gd`, `enterprise_core.gd`, `enterprise_people.gd`, `ledger.gd` | EXISTS | Weekly accounts; one scheduled ledger (MW-19) |
| Farming as a full loop (parcel, tenant, lien, herd, buildings, store) | `realm/farming.gd` (2,492 lines), `farming_fields/herd/data` | EXISTS | |
| Emergent events and chains | `realm/emergence.gd` (harvest failure, epidemic, rift activation, unsafe road, tax rise, noble death, guild collapse, mine discovery, army departure, recognition) | EXISTS | Town-level effects |
| Hidden per-quarter values and winners/losers | `realm/district_values.gd` (10 bytes per quarter) | EXISTS | |
| Person model, memory, mood | `realm/persona.gd` (24 B), `psyche.gd`, `bonds.gd` (8 axes), `secrets.gd`, `social_perception.gd` | EXISTS | NI-2/4/5/8, MW-5 landed |
| Courts, evidence, cases | `realm/courts.gd` (laws per kingdom, appeals, corruption), `population/witness.gd`, `evidence.gd` | EXISTS | |
| War layer | `realm/armies.gd`, `campaign.gd`, `war_intel.gd`, `war_advisors.gd`, `diplomacy.gd`, `siege.gd`, `tactical.gd` | EXISTS | |
| Dynasties, succession, play as heir | `realm/dynasties.gd`, `succession.gd`, `sim/family.gd` (`succeed_to`, `heir_candidates`, carries reputation and family name, heir's own skills, titles do not carry) | EXISTS | The heir mechanism exists but is not yet an *endgame loop* |
| Radiant quests from world state | `sim/radiant_quests.gd`, `sim/adventurer_guild.gd` (board rebuilt daily from wolf dens, caravans, shortages, rumours) | EXISTS | Kind choice: "every available kind once in a shuffled order, then random repeats" (only shuffle memory, no novelty ledger) |
| Discovery of named places | `sim/discovery.gd` (ids only saved), `realm/exploration.gd`, `sim/hidden_triggers.gd`, `realm/towers.gd` (NPC parties race the player, first clears, relics) | EXISTS | |
| Power paths and cultivation ladder | `realm/power_paths.gd` (5 paths), `cultivation.gd` (10 realms x 9 stages), `data/powers/*.json`, `sim/echoes.gd`, `sim/awakening.gd` | EXISTS | Player cap is "Origin Dao"; beyond-master lives in the world, not the ladder |
| Seasons, ecology, wildlife | `sim/seasons.gd` (4 x 28 days), `realm/ecology.gd`, `sim/monster_ecology.gd` | EXISTS | |
| Town mood flags | `population/town_mood.gd` (REST, FESTIVAL, WAR, MONSTER, SCARCE, MOURN, CURFEW) | EXISTS | Festivals are a flag, not a content system |
| Titles and achievements | `sim/titles.gd` (data conditions, hidden titles) | EXISTS | Passive buffs only |
| Biographies | `sim/biography.gd`, `sim/life_courses.gd` (~150 notables) | EXISTS | |
| Water | Coldharbor builds ferries on the Silverrun (`data/region1/towns/coldharbor.json`), longship asset exists, `work_jobs.gd` has a shipwright task; no sailing system, no sea in `data/world` | MISSING | Sailor depends on Codex water work |

Gaps this design fills (all MISSING today): a **Problem Frontier** per profession, a **Novelty ledger** for generators, **Named Works** and **Techniques** registries (lost knowledge), a **Legend** system (deeds retold by NPCs), **Rival Hero** arcs, **Mystery** chains, **Era** shifts, **Collections**, and a **Legacy/Ruin** loop that ties the existing heir mechanism together.

---

## 3. The mechanisms (shared across all professions)

### 3.1 Problem Frontier (EP-2)

For each profession P and the player's mastery tier T, the frontier is the set of *problem classes* currently open. A problem class is a data row:

`{id, profession, min_tier, source (what simulation state makes it appear), shape (tag for novelty), verbs [..], stakes (who wins/loses), fail_mode, reward_kind (access|record|relationship|gold)}`.

Tiers are not just a bar. They are five bands: **Early** (learn the hands), **Mid** (run the work), **Master** (teach and judge the work), **Beyond-master** (shape the field), **Legendary** (shape the world). Each band owns problem classes drawn from different sources:

| Band | Where problems come from | Typical stake |
|---|---|---|
| Early | Tutoring tasks, a boss's orders (existing mini-tasks) | Your own quality |
| Mid | Your own shop/farm/post, customers, weather, price | Your livelihood |
| Master | Apprentices, rival masters, guild rules, big commissions | Other people's livelihoods |
| Beyond-master | District values, shortages, laws, schools, techniques, wars | A town's fortune |
| Legendary | Eras, successions, lost knowledge, the player's own legend | A civilization's direction |

**Rule: each band must have a source that does not depend on the previous band's content.** That is how a master meets problems the early game never had. Data lives in `data/living_world/practice/<profession>.json`; the module `realm/practice.gd` evaluates the frontier on the day tick (closed form, no allocation beyond the offer list, capped at 6 offers per profession).

### 3.2 The Seen ledger and novelty budget (EP-1)

See section 8 for the full rules. In short: every generator (radiant quests, guild board, emergence, mysteries, practice cards, rival arcs, festival events) calls `Novelty.score(shape_hash)` before emitting and `Novelty.note(shape_hash, day)` after the player *sees* it. The ledger is a small packed ring, decaying by half every 90 game days, so old shapes can return as "again, but different".

### 3.3 Named Works and Techniques (EP-3)

- **Work**: a named, persistent artefact or achievement made by a character: a sword with a name and provenance, a vintage, a map, a chronicle, a bridge, a treatise, a ballad, a garden, a fortress. Record: id, maker, kind, quality, year, owner chain, one-line history, flags (cursed, famous, lost).
- **Technique**: a teachable method (a folding pattern, a crop rotation, a bardic mode, a siege drill, a ward glyph). Record: id, profession, requires tier, **holders** (a small list of character ids), **school**, state (common, rare, lost). Rare techniques are taught only by certain masters; a technique with zero holders is *lost*, and can return only through an artefact, a ruin, a book, or a dying master's last student.

Techniques are the carrot at beyond-master: no number, but a new thing you can *do*. Holders also give NPC masters real identity (the only smith who knows "ash-quench" lives in a certain town, is 71, and has no apprentice).

### 3.4 Legend (EP-4)

Every notable deed (the player's or an NPC's) becomes a **Deed** record: actor, kind, place, day, weight, truth bits (what really happened). Telling is derived, never stored: `tale(deed, teller) -> text variant` is a pure function of (deed id, teller persona and culture, listener, distance in days and road steps, the teller's bias toward the actor). So the same deed is told as heroic in the village that benefited, as theft in the town that lost, as a monster story across the border, and as a drunken exaggeration at the inn. `rumours.gd` already garbles claims; this adds *deeds that persist* and are retold by different people differently. Tales return as play: a stranger says "you're the one who...", a bounty appears because of a distorted tale, a child names a wooden sword after you.

### 3.5 Rival NPC heroes and masters (EP-5)

A **Rival** is a notable (`notables.gd`, `towers.gd` parties) assigned to shadow a player's profession with a `rivalry` axis (the `bonds.gd` axis already exists). Rivals have their own works, apprentices and goals; they race for firsts (towers.gd first clears), compete for commissions, and can become friends, enemies, or allies by the same bond rules. A rival is generated *only* when the player enters Master band; two at most per profession (cap).

### 3.6 Mysteries (EP-6)

A **Mystery** is a chain of 3 to 7 linked clues over real state: a secret (`secrets.gd`), a dead noble (`emergence noble_death`), a missing shipment (`caravans.gd`), a forged letter (`war_intel` interception), an odd tax gap (`ledger.gd`), an echo (`echoes.gd`). Clues are placed at real people, rumours and hidden places. The end state changes the world (a trial in `courts.gd`, a district value shift, a technique rediscovered). Mysteries are the answer to "I've done everything": there is always a thread nobody pulled.

### 3.7 Eras and world events (EP-8)

Every 6 to 10 game years (seeded, not periodic to the day) an **Era shift** lands: a long plague, a schism in a faith (`faith.gd`), a new crown, a trade war, a mineral boom, a Rift quiet or storm. An Era is a set of modifiers and new problem classes that last 3 to 8 years, and each profession's data lists how it responds. Eras make a decades-long game feel like different games.

### 3.8 Legacy and Ruin (EP-7)

The heir mechanism (`family.gd succeed_to`) already carries reputation, name and the heir's own skills. This design adds: (a) an **Estate Ledger** summarised on handover (what the old life built, owed, feuded, taught); (b) heirs are not clones: they have their own persona and often a *different calling* (the farmer's daughter wants to be a mage); (c) **ruin** (bankruptcy, exile, disgrace, defeat, plague) is a recoverable state with its own mini-ladder: "rebuilding", rewards for climbing back that a smooth life never gets.

---

## 4. Per-profession depth

Format for each profession: **Layers** (Early, Mid, Master, Beyond-master), then **Emergent problems** (generated by the simulation), **Rivalries**, **Apprentices and schools**, **Signature works**, **Specialisations**, **Failure modes**, **Cross-profession combos**, **How a master stays challenged**, **Modules (status)**.

Module paths are under `kingdom/scripts/`. "EP-n" refers to work packages in section 11.

### 4.1 Farmer

**Layers.**
- Early: field hand, tenant (`career_trades.gd` sow-and-tend, `homestead.gd` lease). Learn season and soil.
- Mid: landowner with a herd and store (`farming.gd` parcel: fields, herd, buildings, ledger).
- Master: estate owner who employs tenants, runs a granary, sells to caravans, supplies the lord's levy.
- Beyond-master: shape a district's food security (`district_values` food_security), breed lines, found a farmers' co-op (`organizations` `farmers_coop`), negotiate a charter with the crown for an irrigation canal.

**Emergent problems.** Blight on a neighbour's field that is spreading toward yours (`emergence harvest_failure`); a levy takes your workers in war season (`callups.gd`); a wolf pack moves after a hard winter (`ecology.gd`); a new mill changes grain prices; a sibling wants the land (`succession.gd`); a drought year forces a choice between selling seed grain and keeping it; an unscrupulous landlord raises rent.

**Rivalries.** A neighbouring estate owner competing for the same mill slot; the co-op leader who wants to set prices; a lord's steward who sets tithes.

**Apprentices and schools.** Tenants' children learn to farm; the master can sponsor one to the Academy; a "model farm" school teaches rotations (techniques, 3.3).

**Signature works.** A named vintage or cheese; a breed ("Silverrun Reds"); an irrigated terrace that outlasts the maker; a seed line that other farms carry for generations.

**Specialisations.** Grain, orchard and vineyard, herding, bee-keeping, hop and brewing, herb gardening (for healers), horse breeding (feeds soldier and caravan).

**Failure modes.** Debt and lien, eviction, a failed harvest chain, livestock plague, a burned granary (arson from a rival or a revenge from a secret), a lost heir.

**Cross-profession combos.** Farmer + Merchant (own the supply chain); Farmer + Healer (herb garden); Farmer + Noble/Steward (estates); Farmer + Soldier (retired veteran lord of a militia village); Farmer + Mage (growth rites, with their own risk).

**How a master stays challenged.** Climate and era shifts change what grows; breeding lines need careful keeping; a district's food security becomes the player's responsibility once they own enough land (the player cannot stop caring because other people's bellies depend on the granary).

**Modules.** Parcels, herd, store, ledger: EXISTS (`realm/farming.gd`, `farming_fields.gd`, `farming_herd.gd`). Co-op org type: EXISTS (`organizations_data.gd`). Breeding lines / signature seed lines: MISSING (EP-3 Works). Irrigation / canal project: PARTIAL (`construction.gd`, `lordship.gd` infra; no water-flow effect on yields). Food security district value: EXISTS (`district_values.gd`).

### 4.2 Blacksmith

**Layers.**
- Early: apprentice forging (heat and strike set quality tier via `crafting.gd`), `career_trades.gd` forging tasks and commissions with minimum tier.
- Mid: smith with a workshop (`enterprise.gd`), steady commissions, stock for the market.
- Master: master smith and workshop owner; teaches apprentices; named commissions.
- Beyond-master: a **lineage smith** with a school; a technique holder (e.g. "ash-quench", pattern welding); supplier to armies; ward-metal and runestone work with wardwrights.

**Emergent problems.** The mine's iron vein fails (`emergence mine_discovery` reversed when a vein runs out); war season floods you with weapon orders at poor quality ore; a noble wants a sword with a forged provenance; a captain returns a blade that broke and blames you in front of the garrison; a rival's cheaper steel undercuts; fuel (charcoal) shortage from a deforested hill.

**Rivalries.** The other smith in town; the arms master of a company who buys elsewhere; a famed foreign swordsmith whose pattern you can't copy.

**Apprentices and schools.** An apprentice may surpass you; may be poached by a guild; may betray a technique to a rival; may become the first holder of a lost technique if you teach it.

**Signature works.** A named sword that appears in later tales; a gate hinge that lasts 200 years; a masterwork test piece that wins the guild's seat; a set of armour for a king.

**Specialisations.** Blades, armour, tools and farm irons, locks and fittings, bells and ironwork for building, ward-metal, siege engines.

**Failure modes.** A flawed blade kills a customer, scandal and trial (`courts.gd`); workshop fire; debt to a metal dealer; guild expulsion for unlicensed trade.

**Cross-profession combos.** Smith + Soldier (battlefield repairs, a field forge in `campaign` supply); Smith + Mage (enchanted metal, `power_paths`); Smith + Merchant (iron trade); Smith + Architect (fortress ironwork); Smith + Scribe (provenance deeds).

**How a master stays challenged.** New alloys, new techniques (rare), shifting demand by era (peace tools vs war weapons), and a succession problem: who inherits the forge's methods.

**Modules.** Forging, quality tiers, commissions, workshops: EXISTS (`career_trades.gd`, `crafting.gd`, `enterprise.gd`). Named Works and Techniques with holders: MISSING (EP-3). Ore supply feeding price and vein depletion: PARTIAL (`emergence` has `mine_discovery`; depletion loop to verify). Wardwright overlap: EXISTS (`data/careers/wardwright.json`).

### 4.3 Merchant

**Layers.**
- Early: stall; haggling rounds and stock against demand (`career_trades.gd`).
- Mid: shop and a caravan contract (`sim/caravans.gd`, `enterprise.gd` price intel and routes).
- Master: caravan company or merchant company org (`merchant_company`), contracts with lords, loans.
- Beyond-master: a trade network across kingdoms: monopolies, embargo breaking, banking, currency stability, trade-treaty lobbying, founding a market town (`founding.gd`).

**Emergent problems.** A road becomes unsafe (`emergence unsafe_road`); a rival caravan is ambushed and the merchant is blamed; a war closes a border (`diplomacy.gd`); a shortage that you can exploit or relieve; a debtor noble cannot pay; spoilage in a hot season; forged letters of credit (`war_intel` forged-letter plans).

**Rivalries.** A competing company; a smuggler ring (`criminal_syndicate`); a lord who taxes your route.

**Apprentices and schools.** Factors (junior agents) run routes for you; some leave to compete; a "counting-house school" teaches ledger methods.

**Signature works.** A trade route named for you; a standard weight and measure adopted by a market; a famous fair founded.

**Specialisations.** Grain, textiles, metals, spices and luxuries, livestock, information (news traders using `news.gd` delay), banking.

**Failure modes.** Bankruptcy, caravan loss, seized goods, blacklisting by a guild, a scandal of false weights (`courts`).

**Cross-profession combos.** Merchant + Caravan master (the logistics side); Merchant + Spy (price intelligence, embargo runs); Merchant + Noble/Steward (tax farming); Merchant + Sailor (river and sea routes); Merchant + Bard (marketing, renown).

**How a master stays challenged.** Systemic risk (credit chains that can unwind), politics (embargoes), other merchants who learn your routes and imitate, and the temptation to monopolise (which draws the crown's attention).

**Modules.** Stall, shop, caravans, price intel: EXISTS (`career_trades.gd`, `caravans.gd`, `enterprise_core.gd`). Credit chains and banking: MISSING (builds on `ledger.gd` obligations, loans). Market-founding: EXISTS (`founding.gd`). Tax farming: PARTIAL (`stewardship.gd`, `lordship.gd`).

### 4.4 Soldier

**Layers.**
- Early: recruit to private (`realm/soldier.gd`, drills, muster, kit).
- Mid: corporal to sergeant (squad missions, orders judged against the enemy, men lost on bad calls; `sim/soldier_squad.gd`).
- Master: lieutenant to captain; officer's court-martial; campaign muster (`callups.gd`, `campaign.set_player_rank`).
- Beyond-master: commander or free-company founder (`mercenary_company`), advisor (`war_advisors.gd`), marshal of a kingdom, author of a tactical doctrine (a Technique that other armies adopt).

**Emergent problems.** Pay arrears (`ledger.gd` shortage ladder: delayed pay, resign, desert, embezzle, mutiny); a bad intel report (`war_intel` conflicting scouts); a siege with a famine inside; a prisoner exchange; a commander who is a coward; a bridge you must hold without orders; veterans who won't leave the field.

**Rivalries.** Another officer for the same promotion; an enemy general who learns your habits; a noble's son with political cover.

**Apprentices and schools.** Squire training, a drill school; the best sergeant you ever had may become your enemy's officer.

**Signature works.** A famous retreat; a holdfast built by your company; a named banner; a drill manual copied by other armies.

**Specialisations.** Line infantry, archery, cavalry (horses from farmers), engineers and sappers, scouts, cadre trainers, siege masters.

**Failure modes.** Rout and capture; court-martial; wounds (`injuries.gd`); mutiny; a massacre that ruins reputation.

**Cross-profession combos.** Soldier + Noble (landed knight); Soldier + Healer (field medic); Soldier + Scribe (staff officer); Soldier + Smith (armourer); Soldier + Spy (intel officer); Soldier + Mage (battle mage).

**How a master stays challenged.** Commanding in a war that has no clear good side (`war_intel` conflicting reports); coalitions shift; logistics, morale and weather (`campaign.gd` supply) rather than numbers; a chain of command above you with its own agendas.

**Modules.** Ranks, muster, squads: EXISTS (`soldier.gd`, `soldier_career.gd`, `soldier_squad.gd`). Campaign and war intel: EXISTS (`campaign.gd`, `war_intel.gd`, `tactical.gd`). Doctrine as Technique: MISSING (EP-3). Live battlefield hand-off: MISSING (MW-18).

### 4.5 Scribe

**Layers.**
- Early: copyist; mini-tasks (`scribe.gd`, `scribe_data.gd`).
- Mid: clerk and registrar.
- Master: steward's secretary, then steward (`stewardship.gd` offices).
- Beyond-master: envoy; **keeper of records**: chronicler of the region (the scribe writes the *official history* that NPCs read); archivist of lost knowledge; forger-hunter (detects forged deeds).

**Emergent problems.** A forged deed shows up in `courts`; an old land claim contradicts a lord's title (`land_claim.gd`, `succession.gd` claims); a tax ledger gap points to embezzle (`city_life.gd`); a letter in a dead script (glyph knowledge); a chronicle someone wants rewritten; a lord asks you to omit a massacre.

**Rivalries.** Another registrar; a church scriptorium (`faith.gd`) that controls copying; an official historian who wants his version to stand.

**Apprentices and schools.** Copyists in your scriptorium; a school of letters; a pupil who becomes a spy.

**Signature works.** A chronicle that becomes "what happened"; a treatise on law; a map; a codex that preserves a lost technique.

**Specialisations.** Law and conveyancing, chronicling, cartography, ciphers and cryptography, translation, illumination, accountancy.

**Failure modes.** Exposed forgery; imprisonment; a scandal of selective history; blindness.

**Cross-profession combos.** Scribe + Spy (ciphers); Scribe + Priest (scriptorium); Scribe + Noble (steward); Scribe + Architect (plans); Scribe + Bard (epic narrative); Scribe + Mage (spell treatises).

**How a master stays challenged.** The record is contested; other chroniclers disagree and the player's version *becomes* the world's retelling (3.4), so the stakes are moral as well as practical.

**Modules.** Ladder and mini-tasks: EXISTS (`scribe.gd`). Chronicler authority over "official history" (the text NPCs quote): MISSING (EP-4 reading from a Chronicle record). Forgery detection: PARTIAL (`courts` evidence; no document forgery check).

### 4.6 Healer

**Layers.**
- Early: herbalist assistant (hunter and farmer supply herbs; `radiant_quests` "healer wants herbs").
- Mid: village healer; fevers and wounds (`injuries.gd`, `emergence epidemic`).
- Master: physician with an infirmary; trains apprentices; advises the lord on public health.
- Beyond-master: plague response coordinator, founder of a hospital order (`religious_order`), author of medical treatises (Techniques), anatomist (morally contested), poison expert.

**Emergent problems.** An epidemic with limited herbs; a patient is a criminal in hiding; a noble's heir is dying and a rival wants it; contaminated well (`district_values` safety); a faith that bans a cure; a dead patient and a grieving family (`psyche` grief).

**Rivalries.** A quack who sells "miracle cures" with a patron; a priest-healer; another physician with a better reputation.

**Apprentices and schools.** An infirmary school; a travelling healer's network that carries remedies (Techniques).

**Signature works.** A published herbal; a famous cure; a hospital; a named remedy.

**Specialisations.** Wounds and surgery, fevers and plague, midwifery, herbalism, poisons and antidotes, mental healing (using `psyche`), animal healing.

**Failure modes.** Patient death and blame; accusation of witchcraft or poison (`courts`); plague reaches the infirmary; running out of supply.

**Cross-profession combos.** Healer + Soldier (field medic); Healer + Priest (healing orders); Healer + Spy (poisons); Healer + Farmer (herb gardens); Healer + Mage (restoration with cost).

**How a master stays challenged.** Plague variants (Era-dependent), moral choices in triage, and the politics of who gets care.

**Modules.** Ladder: EXISTS (`ladders.json` healer). Injuries and epidemic: EXISTS (`injuries.gd`, `emergence`). Disease model with variants and triage: MISSING (EP-9). Hospital org: PARTIAL (`religious_order` type exists; no infirmary function).

### 4.7 Hunter

**Layers.**
- Early: snares and small game; trails (`ecology.gd`, `monster_ecology.gd`).
- Mid: hunter-guide for caravans and nobles; tracks packs to dens (`adventurer_guild` commissions).
- Master: warden of a forest; manages game, poachers, and monster pressure on farms.
- Beyond-master: ranger-captain, species historian (collects "sightings"), tamer of a rare beast (`beast` power path), guardian of a sacred grove.

**Emergent problems.** Wolf pack moves in after a hard winter; poachers kill a protected deer; a noble wants a trophy beast whose population is endangered; a monster migration pushes game into farmland (`ecology_factions.gd`); a wounded apex predator turns on a village.

**Rivalries.** A rival hunter-guide; a noble huntsman; a poacher boss tied to the syndicate.

**Apprentices and schools.** Young trackers; a rangers' lodge.

**Signature works.** A map of game trails; a beast tamed; a cleared den; a trophy hall.

**Specialisations.** Tracker, trapper, archer, beast-tamer, falconer, fisher, guide.

**Failure modes.** Crippling wounds; wrongly killing a protected beast (law in `courts`); lost party in winter.

**Cross-profession combos.** Hunter + Farmer (pest control); Hunter + Merchant (hides, furs); Hunter + Adventurer (guides); Hunter + Healer (herbs); Hunter + Spy (tracking people).

**How a master stays challenged.** The ecology shifts: removing wolves has consequences; a master must manage populations (balance problems) rather than kill more.

**Modules.** Ladder: EXISTS. Ecology simulation: EXISTS (`ecology.gd`, `monster_ecology.gd`). Game-management consequences feeding `district_values` and farms: PARTIAL. Wardenship post: MISSING (EP-9).

### 4.8 Miner

**Layers.**
- Early: digger at an existing mine (work spots, `work_jobs.gd` sort ore).
- Mid: a shaft boss; reading veins; safety (collapse, gas).
- Master: mine owner or concession holder; hires crews; negotiates with smelters.
- Beyond-master: engineer of deep mines; discoverer of new veins; cartographer of the underworld; guild or union leader.

**Emergent problems.** A vein runs out; a collapse traps a crew; a new vein is found on a lord's land (`emergence mine_discovery`); water floods a lower shaft; a hidden cavern holds something ancient (`exploration.gd` hidden entrances); bandits attack ore shipments.

**Rivalries.** A rival concession; a smelter monopoly; a lord who revokes a lease.

**Apprentices and schools.** A mining crew's lineage; a guild school teaching shoring.

**Signature works.** A deep shaft named for you; a drainage adit; a discovered lode; a map of tunnels.

**Specialisations.** Coal and fuel, iron, precious metals, stone quarrying, gem cutting, tunnelling, rune-stone sourcing (`runestone_network.gd`).

**Failure modes.** Collapse and deaths (`courts`), debt, silicosis-type injuries, strike (`organizations`).

**Cross-profession combos.** Miner + Smith (ore to metal); Miner + Architect (quarry for building); Miner + Adventurer (dungeons); Miner + Mage (rune-stone).

**How a master stays challenged.** Deeper means riskier; each level reveals a new hazard (flood, gas, ancient wards); also the political problem of workers' rights.

**Modules.** Work tasks: EXISTS. Mine as business: PARTIAL (`businesses.gd` has no mine type; verify). Underground map and hazards: MISSING (EP-9; Codex for the world side).

### 4.9 Priest

**Layers.**
- Early: acolyte; rites and etiquette (`faith.gd`).
- Mid: village priest; marriages, funerals, confession (`secrets.gd` knowledge), charity.
- Master: abbot or high priest; manages a temple; tithes and church lands.
- Beyond-master: bishop, reformer, schismatic (`organizations` schism), inquisitor, saint-maker.

**Emergent problems.** A confessed secret that could save or ruin someone; a heresy rising in a village; a rival faith's missionary (`faith.kingdom_profile`); a temple's estate under dispute; a famine and the church's granary; a king asks for a divorce.

**Rivalries.** A rival faith (runes, dawn, wild, folk); an ambitious deacon; a noble patron.

**Apprentices and schools.** Acolytes; a monastery; a theological school.

**Signature works.** A cathedral (with Architect); a saint's cult; a rite reformed.

**Specialisations.** Healing temple, scholarly monastery, war chaplain, inquisitor, hermit mystic, missionary.

**Failure modes.** Excommunication; schism; scandal; the loss of a congregation.

**Cross-profession combos.** Priest + Healer; Priest + Scribe; Priest + Noble; Priest + Soldier (war chaplain); Priest + Mage (sacred rites with power).

**How a master stays challenged.** Faith is a contested field with doctrinal change; the master's decisions shape what a region believes (`faith` beliefs change), which in turn alters etiquette, law and prices.

**Modules.** Faiths, churches, etiquette: EXISTS (`faith.gd`). Priest career ladder and play: MISSING (EP-9; `ladders.json` has no priest). Confession mechanic: PARTIAL (`secrets.gd` holds secret state).

### 4.10 Mage

**Layers.**
- Early: apprentice at an academy (`education.gd`, `ACADEMY_PLAN.md`); basic cast (`power_paths.gd` magic path).
- Mid: practising mage (cooldowns, resources via `technique_caster`, `ashes-ability-system`).
- Master: realm-level mage in `cultivation.gd` ladder; founder of a school.
- Beyond-master: archmage; discoverer of new spells (Techniques); keeper of a Rift ward; political adviser.

**Emergent problems.** A Rift wakes (`emergence rift_activation`); a student turns to forbidden arts; an aura draws fear (`social_perception.gd` magic pressure); a rival academy steals a spell; the magicule pool is depleted in a region (`magicules.gd`).

**Rivalries.** Another school; a church that distrusts magic; a king who wants a battle mage.

**Apprentices and schools.** The academy; a private tower; a successor who may surpass you or betray you.

**Signature works.** A named spell; a ward on a city; an enchanted object.

**Specialisations.** Elemental, wards and runes, restoration, divination, summoning, alchemy, artificing.

**Failure modes.** Instability and exhaustion (`power_paths` risks); a backlash that hurts others; a witch-hunt (`courts`).

**Cross-profession combos.** Mage + Smith (enchanted weapons); Mage + Healer; Mage + Soldier; Mage + Scribe (spell texts); Mage + Architect (wards).

**How a master stays challenged.** New spells are discovered not bought; the field itself is changing with Era shifts; each advance has a social cost via aura.

**Modules.** Paths and cultivation: EXISTS (`power_paths.gd`, `cultivation.gd`, `data/powers/*.json`). Spell discovery as Techniques with holders: MISSING (EP-3). Aura projection: PARTIAL (MW-9 not verified as code).

### 4.11 Noble and Steward

**Layers.**
- Early: page or squire, or an apprentice steward (`stewardship.gd` offices).
- Mid: landed lord of a village (`lordship.gd`, `land.gd`).
- Master: lord of a town; councils (`governance.gd`); courts (`courts.gd`); marriage politics (`succession.gd`).
- Beyond-master: duke, king (`founding.gd` for new states), regent, founder of a dynasty.

**Emergent problems.** Tax dissent (`emergence tax_rise`); a delegate embezzles (`city_life.gd`, MW-13); a vassal demands land (MW-12 Theron scenario); a succession dispute; a war with a neighbour; a famine in your town; a plot to depose you.

**Rivalries.** A claimant; a powerful vassal; a foreign crown.

**Apprentices and schools.** Wards (fostered children); a court school; stewards trained by you.

**Signature works.** A charter; a law code; a castle; a treaty; a marriage alliance.

**Specialisations.** Warlord, lawgiver, patron of arts, merchant-prince, reformer.

**Failure modes.** Deposition; exile; bankruptcy; assassination; civil war.

**Cross-profession combos.** Noble + Soldier; Noble + Merchant; Noble + Priest; Noble + Architect.

**How a master stays challenged.** The job is *managing other agents* with their own wants (`persona`, `bonds`); delegation quality matters (MW-13); succession and legitimacy are never solved (MW-6).

**Modules.** Offices, lordship, courts, succession, governance: EXISTS. Delegation quality applied to output: PARTIAL (MW-13). Legitimacy per observer: PARTIAL (MW-6).

### 4.12 Innkeeper

**Layers.**
- Early: barmaid or stable hand; serve and listen.
- Mid: owner of an inn (`businesses.gd` inn type); hire staff; stock.
- Master: chain of inns on a route; rumour hub (`news.gd` tavern channel); guild of innkeepers.
- Beyond-master: patron of a town's social life; neutral ground broker (hosts treaty talks, `audiences.gd`); information dealer.

**Emergent problems.** A guest dies in a room; a bard brings a crowd and a fight; a noble's mistress hides in your upstairs; a spy ring uses your inn; the road is unsafe so guests drop; a rival inn spreads rumours.

**Rivalries.** The competing inn; the guild; the watch captain who wants bribes.

**Apprentices and schools.** Staff who learn; a cooks' school.

**Signature works.** A famous brew or dish; a legendary room; a tavern song.

**Specialisations.** Brewing, cooking, lodging, gambling hall, stable inn, information house.

**Failure modes.** Fire, closing for plague, scandal, bankruptcy, being used as a hideout (`courts` accessory).

**Cross-profession combos.** Innkeeper + Bard; Innkeeper + Spy; Innkeeper + Merchant; Innkeeper + Hunter (game dishes).

**How a master stays challenged.** Every guest is a possible problem or opportunity (people with secrets); the inn is the junction of other professions' stories.

**Modules.** Ladder and inn business: EXISTS. Rumour hub: EXISTS (`news.gd`, `rumours.gd`). Guest-secrets event stream: PARTIAL (`secrets.gd`, `micro_events.gd`; no inn-specific generator; EP-9).

### 4.13 Thief and Spy

**Layers.**
- Early: pickpocket and burglar (`pickpocket.gd`, `theft.gd`, `ashes-perception-ai`).
- Mid: fence and cat-burglar; syndicate member (`criminal_syndicate`).
- Master: guild head or spymaster; running informants.
- Beyond-master: spy-master of a kingdom (`war_intel` scouts, forged letters), intelligence broker, kingmaker through blackmail (`courts` ledger with secrets).

**Emergent problems.** A noble's secret you learn is also someone's life; a double agent; an informant is caught; a patron demands a crime; a guard captain you bribed is replaced; an assassination contract on someone you like.

**Rivalries.** A rival guild; a master investigator (courts); a counterspy.

**Apprentices and schools.** Street urchins; a hidden academy; a protégé who may be an informant.

**Signature works.** A heist remembered by the whole city; a network; a forged treaty that changed a war.

**Specialisations.** Burglar, forger, assassin, courier, infiltrator, informant runner, smuggler.

**Failure modes.** Arrest (`arrest.gd`), mutilation or execution (`courts` laws per kingdom), betrayal, exile.

**Cross-profession combos.** Spy + Scribe; Spy + Innkeeper; Spy + Merchant; Spy + Noble.

**How a master stays challenged.** The better your network the more moral compromises; counter-intelligence adapts to you (investigators use `memory of methods`, section 8.4).

**Modules.** Theft, pickpocket, witnesses, arrest, courts: EXISTS. Spy network with informants as bonds: PARTIAL (`bonds.gd`, `secrets.gd` knowledge). Counter-intel adapting: MISSING (EP-12).

### 4.14 Adventurer

**Layers.**
- Early: guild applicant; boards (`adventurer_guild.gd`, `radiant_quests.gd`).
- Mid: journeyman; dungeons and towers (`towers.gd` first clears, relics).
- Master: guildmaster or party leader; hunts apex monsters (`echoes.gd` attune).
- Beyond-master: explorer-cartographer of new regions; founder of an order; rift-sealer; legend (3.4).

**Emergent problems.** A rival party beats you to a tower floor (`towers.gd` NPC parties race); a guild commission turns out to be a trap; a lost expedition needs rescue; a relic belongs to a church; a monster's echo calls you (`echoes.gd`).

**Rivalries.** A rival hero (3.5); a corrupt guild examiner.

**Apprentices and schools.** Junior party members; an academy of adventurers.

**Signature works.** A first clear of a tower; a map of a region; a relic recovered; a slain apex.

**Specialisations.** Delver, monster-hunter, explorer, bounty hunter, escort, relic hunter.

**Failure modes.** Death inside a tower (`towers.gd` cost of dying), a party wipe, debts.

**Cross-profession combos.** Adventurer + any; the connector profession.

**How a master stays challenged.** New regions, procedural mysteries (3.6), rival heroes (3.5), and the world's escalating threats via Eras.

**Modules.** Guild, boards, towers, echoes: EXISTS. New-region unlocking as an endless loop: PARTIAL (`exploration.gd`, `discovery.gd`; region creation is Codex world work, EP-10).

### 4.15 Architect and Builder

**Layers.**
- Early: labourer or mason's assistant (`construction.gd` workers).
- Mid: master mason; blueprint to build (`build_kit.gd`, Palworld-style build mode).
- Master: master builder; speeds the crew and unlocks tall tiers (`construction.gd` says master builders speed the crew and unlock tall tiers).
- Beyond-master: city planner (`city_planner`), fortress designer, bridge and aqueduct engineer, cathedral builder, founder of a guild of builders.

**Emergent problems.** A flood damages the bridge; a cathedral takes decades and the funding stops; a fortress design is leaked to the enemy; a collapse in a rival's building; a lord wants a monument over the poor quarter; materials shortage (stone, timber, `emergence`).

**Rivalries.** A rival master builder; a church preferred architect; a lord's pet planner.

**Apprentices and schools.** A lodge of masons; a drafting school.

**Signature works.** A named bridge; a cathedral; a town you planned; a city wall that held a siege.

**Specialisations.** Fortification, civic works, religious architecture, domestic, hydraulics, ward-architecture.

**Failure modes.** Collapse with deaths; cost overrun; sabotage; design flaw found by a siege.

**Cross-profession combos.** Architect + Mage (wards); Architect + Noble (city founding); Architect + Soldier (siege defence); Architect + Scribe (plans).

**How a master stays challenged.** Long projects spanning years with changing owners; infrastructure effects on `district_values`; designs that are tested later by sieges or floods.

**Modules.** Construction and build kit: EXISTS (`construction.gd`, `build_kit.gd`, `towers.gd`). Long-project funding and legacy: PARTIAL (`ledger.gd`; no multi-year project record; EP-3 Works). Infrastructure to district loop: PARTIAL (MW-27).

### 4.16 Bard

**Layers.**
- Early: street performer; tavern audiences (`talk_bark.gd`, `town_mood.gd`).
- Mid: house bard; songs about local events (`events.gd`).
- Master: court bard and satirist; their songs *change* reputations (`reputation.gd`).
- Beyond-master: composer of a ballad cycle that outlives the actors; head of a college of bards; propagandist for a crown.

**Emergent problems.** A patron wants a flattering song about a bad deed; a satirical verse enrages a lord; a song misrepresents a hero (3.4 Legend); a festival needs a piece; a rival bard steals your work.

**Rivalries.** A rival bard; a rival patron; a church that bans a song.

**Apprentices and schools.** A bardic college; a pupil who sets your tune to different words.

**Signature works.** A ballad (a Work, 3.3) that NPCs sing for decades; an epic of the player's own deeds.

**Specialisations.** Epic singer, satirist, lyric composer, storyteller, instrumentalist, court jester.

**Failure modes.** Banishment; imprisonment for sedition; losing the voice.

**Cross-profession combos.** Bard + Innkeeper; Bard + Scribe; Bard + Spy; Bard + Noble (patronage).

**How a master stays challenged.** A bard's art is *the world's memory*; they choose what the world remembers; and the audience changes taste with Eras.

**Modules.** Town moods, barks: EXISTS. Bard career and songs as Works that propagate as tales: MISSING (EP-4, EP-9). Animation (instruments, performance): Antigravity (EP-13).

### 4.17 Caravan Master

**Layers.**
- Early: wagon hand or guard.
- Mid: driver and guide on a route (`caravans.gd`: cart, driver, guards).
- Master: company owner (`merchant_company`), multi-route logistics.
- Beyond-master: opens new routes, treaties with tribes, wayhouse network, escort doctrine.

**Emergent problems.** Ambush on a road segment (`caravans.gd` risk by road tier, runestones, guards); a bridge is out; a border closes; guard desertion; a client demands forbidden goods; plague quarantine on the route.

**Rivalries.** Another company; bandit chief; toll-collecting lord.

**Apprentices and schools.** Junior drivers; a scout school.

**Signature works.** A route; a wayhouse; a safe-conduct pact.

**Specialisations.** Bulk goods, luxury, military supply, pilgrim caravans, courier.

**Failure modes.** Lost caravan; blacklisted route; guard mutiny.

**Cross-profession combos.** Caravan + Merchant, Soldier (escorts), Hunter (guide), Healer (quarantine).

**How a master stays challenged.** The road is alive: `runestone_network.gd` wears, bandits adapt, kingdoms change borders.

**Modules.** Caravans: EXISTS (`sim/caravans.gd`). Player-run company logistics UI: PARTIAL (`enterprise.gd` routes). Road quality loop: PARTIAL (MW-27).

### 4.18 Sailor, boatman, shipwright (conditional on water)

**Current world status.** Water exists as a river (the Silverrun, ferries built at Coldharbor); a longship asset exists; there is no sea or sailing system in `data/world` or `scripts` beyond a shipwright work task. So the sailor profession is **MISSING** and depends on Codex adding a sea or at least a navigable river with ports (EP-10).

**Layers (if water exists).**
- Early: deckhand or ferry hand; river work.
- Mid: boatman with own flat boat or ferry licence (Coldharbor ferries).
- Master: captain of a coastal or river trading ship.
- Beyond-master: fleet owner, harbour master, navigator and chart maker, privateer or pirate hunter.

**Emergent problems.** Storm season; a harbour fee dispute; a river flood (`seasons.gd` spring melt); pirates; a smuggling job; a plague ship refused entry.

**Rivalries.** Rival captain; harbour master; pirate lord.

**Apprentices and schools.** Cabin boys; a navigators' school.

**Signature works.** A chart of a coast; a ship (a Work); a safe channel.

**Specialisations.** River trade, coastal trade, fishing, ferry, naval, exploration.

**Failure modes.** Wreck; piracy; seizure.

**Cross-profession combos.** Sailor + Merchant (the main combo), + Soldier (marines), + Explorer.

**How a master stays challenged.** Seasons and weather; new coasts; hostile fleets.

**Modules.** All MISSING (EP-10 Codex: water and ports; EP-9 cloud: trade and travel logic; Antigravity: ship, rowing, sailing and ferry animation, EP-13).

---

## 5. Cross-profession depth

### 5.1 The Master's Table (what masters of every trade share)

At Master band, all professions gain the same four-part toolkit, so no master is a dead end:

1. **Teach.** Take apprentices (3 at a time; they learn from the master's Techniques; their progress is a closed-form yearly step, MW-32).
2. **Judge.** Sit on a guild panel or court bench for your craft's disputes (an `organizations` rank right "judge").
3. **Found.** Charter a guild, school or company (`organizations.gd` stages: idea > members > charter > premises > standing).
4. **Leave a Work.** Commission or complete one signature piece (3.3) that the world will remember.

### 5.2 Combo matrix (profession pairs that open new problem classes)

Combos are rewarded not by multipliers but by *new problem classes* from the Problem Frontier: a combo problem class has two `requires`. A short list (the data file holds all of them):

| Combo | New problem class |
|---|---|
| Smith + Mage | Enchant a blade for a rival's execution; the spell leaves an aura that the wrong person senses |
| Healer + Priest | Plague quarantine in a church that insists on public gatherings |
| Scribe + Spy | Decode an enemy cipher before a treaty signing |
| Merchant + Sailor | Break a blockade with a ship under a flag of convenience |
| Soldier + Architect | Defend a fortress you designed against the army that stole the plans |
| Bard + Noble | Compose a dynasty's founding myth that must survive scrutiny |
| Farmer + Hunter | Manage a predator return that endangers both |
| Innkeeper + Spy | Host a secret meeting and sell its outcome |
| Miner + Mage | Wake a sealed vein that is warded for a reason |
| Caravan + Priest | Carry a relic through a heretic's territory |

---

## 6. Endgame loops (what you do after everything is "done")

### 6.1 Dynasties and heirs
- On retirement or death the player picks among `family.heir_candidates()` (exists); each heir has a `persona`, a calling (often different), a **relationship to the old life** (devoted, resentful, estranged) from `bonds`/`psyche` rules.
- An **Estate Ledger** (EP-7) shows what passes down: lands, businesses, debts, enemies, apprentices, Works, Techniques, tales. Some do not pass (titles do not, per `family.gd`).
- The heir may have been *an NPC the player met* (a ward, an apprentice adopted) if the line ends.
- Gameplay: heirs inherit *problems*, not just goods (the old feud, the unpaid oath `MW-24`, the unfinished cathedral).

### 6.2 Founding orders, guilds, kingdoms
- `organizations.gd` already supports founding; `founding.gd` supports settlements; crowns exist in `succession.gd`.
- Endgame: found something that must *survive without you*: its charter, its succession mode, its funds. NPC successors may pervert it (`MW-23` splinters), so a founder returns in a later life to reform or dissolve it.

### 6.3 Generational change
- Every NPC house changes: heirs vary, trades shift (`dynasties.gd` specialty), towns drift (`settlements.gd` identity). After 30 game years, the world the player knew is partly new; names recur but roles differ.

### 6.4 Lost knowledge and rediscovery
- Techniques with zero holders are lost (3.3). The player can find them in ruins, books (Scribe), echoes (`echoes.gd`) or a last student. Rediscovery restores a field's capabilities and raises tension (some want it buried).

### 6.5 World events and Eras
- Section 3.7. Examples in section 9.

### 6.6 Legends and tales
- Section 3.4. The player's legend is a record NPCs retell; at high legend, young NPCs seek the player (as apprentices, as challengers, as biographers).

### 6.7 Rival NPC heroes
- Section 3.5. They also come in generations; the rival's child may become the next rival.

### 6.8 New regions
- Unlocking by exploration, treaties, river or sea, or rift gates. New regions bring new cultures (`world_lore`), new Techniques, new problems. Codex produces regions through `ashes-region-content`. Each region has a **signature problem** that no other region has.

### 6.9 Seasons, festivals
- Seasons (`seasons.gd`) drive crops, roads, wolves, plague. Festivals become *events with content*: a harvest fair where Works are shown, a smiths' contest, a bards' tournament, a mourning. Each festival has a **slot** (contest, trade, ritual, plot) where a profession can compete and win a Work-record, a patron or a title. `town_mood.gd` FESTIVAL flag exists; content generator is MISSING (EP-8).

### 6.10 Collections
- Optional collections give long-horizon goals without numbers: bestiary (species seen), herbal, atlas (places), songbook, armoury (named swords), codex (Techniques learned), chronicle (events witnessed), wardrobe, relic cabinet. Collections never gate power; they give access to rare NPC masters (a collector of songs teaches a modal Technique when the songbook has 20 entries). `discovery.gd` is the data base for the atlas; others are MISSING (EP-11).

### 6.11 Mysteries
- Section 3.6 and scenarios in section 9.

### 6.12 Secrets chains
- `secrets.gd` records what each character hides, and `courts.gd` keeps who-knows-what. A **secrets chain** is a sequence where learning secret A (an affair) points to B (a debt) and C (a forged will). Play: follow, use or protect. Consequences land on `reputation`, `district_values`, `succession` claims. (EP-6.)

### 6.13 Losing it all and rebuilding
- Ruin states: bankrupt, exiled, outlawed, disgraced, defeated, plague-struck, widowed. Each has a **Rebuilding ladder** (3 stages) with its own problems: debts to renegotiate, a name to clear, allies who stayed, former apprentices who now help or hate. Reward: unique relationships (the loyal ones) and a harder-won reputation tag ("risen"). (EP-7.)

### 6.14 Playing as your heir
- After the handover, the new character has their own start, but the world remembers the old one: NPCs treat them as "child of the founder": expectations, enemies, gifts. Tales about the parent are told to the heir. The old character becomes a *legend NPC* (can be met if living, can be a ghost or echo, `echoes.gd`, if dead).

---

## 7. Discovery systems (always something new)

### 7.1 Procedural mysteries
Template-based, built from real state (3.6). Each template has: *hook* (a real event), *clues* (3 to 7 placed at real people and places), *red herrings* (bounded), *culprits* (a persona fitting motive), *resolution branches* (law, mercy, blackmail, silence), *world effect*. Mysteries live in `realm/mysteries.gd` (EP-6); their clues are written into `secrets`, `rumours` and `exploration` using existing APIs.

### 7.2 NPC-originated quests from real shortages
`radiant_quests.gd` and `adventurer_guild.gd` already read shortages, wolf dens and caravans. Extend with: *who* posts (a person with a persona and cause line), *why this person* (e.g. their business is short), and **chains**: completing one reveals the next shortage (MW-29). A shortage-based quest is only posted if the shortage is real and unresolved (check `district_values`, `businesses` stock).

### 7.3 Hidden places
`exploration.gd` handles hidden entrances; `hidden_triggers.gd` handles age-gated triggers. Add: **place seeds** per region (Codex) that are unlocked by *knowledge*, not by walking (a map held by a dying scribe, a technique name, a family secret). A hidden place without a knowledge key is not hidden, just far. Codex owns the places; cloud owns the key records. (EP-10, EP-6.)

### 7.4 Rare techniques taught only by certain masters
Techniques (3.3) have **teacher conditions**: opinion thresholds (`relationships.gd`), a test (a mini-task), a favour (`MW-24` obligations), or an apprenticeship term. A master's willingness depends on `persona` values (pride, loyalty). The player has to *find* the teacher: through rumours, books, collections, other masters' mentions. (EP-3.)

### 7.5 Foreign and strange professions
Each new region offers 1 to 2 local callings not found in Valencios: glass-reading, salt-smithing, sky-herding, rune-fishing, grave-singing. They plug into the same Problem Frontier data so they cost data, not code. (EP-9 data, EP-10 world.)

### 7.6 Apprentice sources
Apprentices arrive with their own goals: one wants to learn *everything*, one only a single Technique, one is a spy, one is a runaway noble. Each apprentice is a small mystery and a long-term relationship. (`education.gd` has apprentice age 12; `bonds.gd` deltas.)

---

## 8. Anti-repetition rules for generators

### 8.1 The Seen ledger (what the player has seen)
`realm/novelty.gd` keeps a packed ring of up to 512 entries: `{shape_hash:int32, kind:byte, last_day:int16, count:byte}`. A shape is `hash(kind, template_id, actor_role, place_kind, resolution_kind)`. "Seen" means the player was shown the offer, took part, or heard it told. Reading is O(1) via a small hash table; write on day-tick only.

### 8.2 The novelty budget
Each generator receives, per game week, a **novelty budget** (e.g. 5 points). Emitting a card costs `base + repeat_penalty(shape)`, where `repeat_penalty = 3 * count * 2^(-(day-last_day)/90)` (half-life 90 days). A card that would exceed the budget is dropped or replaced by a lower-cost variant. The most urgent *real* need is never suppressed entirely; it is **reframed**: a different poster, different complication (the wolves are now a symptom of a drought upstream), or delegated to an NPC instead of the player's board.

### 8.3 Variety floors
- No generator may emit the same `kind` more than 2 days in a row on one board.
- At least 1 in 4 offers in any profession's frontier must be a **new combo class** the player has not yet met.
- At least 1 offer per month must come from a *different* profession than the one the player is working (nudge toward cross-play).
- Shape cooldown: 40 game days minimum before an identical shape re-emits (except for emergencies flagged `urgent`).

### 8.4 Adaptive adversaries
Rivals, investigators and bandits keep a short **method memory** of the player's last 5 methods (stealth, force, bribe, magic, law); counter-measures raise cost of the most used method and open the least used. This is a bounded modifier (+/- 0.2 on thresholds), never a hard counter.

### 8.5 Determinism
All novelty rolls use `hash([WorldSim.SEED, tag, day, id])`; the ledger is saved, so reloading does not re-roll (MW-35).

### 8.6 Test hooks
`test_ep_novelty.gd`: (1) same shape three times in a row is impossible except `urgent`; (2) over 365 days, the distinct shapes shown >= 70% of shapes available; (3) save, reload, run 30 days gives the same hash.

---

## 9. Scenarios (46 concrete)

Each is written as a *state, a trigger, choices and consequences*, so tests can drive them with the sim. Professions in brackets.

1. **The failing vein** [Miner, Smith]. A master smith's iron source fails; he must choose between cheaper imported ore (weaker blades), a risky deep shaft, or retooling to bronze for a peace-year market. A rival smith buys the shaft concession first.
2. **The blamed blade** [Smith, Soldier]. A captain's sword breaks in a skirmish; he blames the smith in public; the smith has a record of the temper used; a trial (`courts`) tests the blame against the captain's own use.
3. **Ash-quench lost** [Smith]. The only holder of the technique dies without an apprentice; the player finds a half-written treatise in a scribe's archive; to rebuild it they must test, fail and test again; success restores the technique for the whole region.
4. **The dry year** [Farmer]. Drought: sell seed grain for a high price to a desperate lord or keep it; consequences compound next spring.
5. **Co-op or lien** [Farmer, Merchant]. Neighbours form a co-op; a merchant offers a lien-backed loan to buy a mill; each choice shifts `district_values` food_security and unemployment differently.
6. **The wolves' reason** [Hunter, Farmer]. A wolf board card appears repeatedly; the novelty ledger reframes: wolves are moving because a rival lord's hunters cleared the deer; the real problem is a political one.
7. **The trophy** [Hunter, Noble]. A noble wants an endangered beast; poachers shadow the player; refusing makes an enemy, accepting costs the ecology.
8. **The forged deed** [Scribe, Noble]. A scribe sees a forged land deed; exposing it favours the poor tenants but ruins a noble ally; hiding it builds a debt that returns in a later life.
9. **Rewriting the massacre** [Scribe, Soldier]. A lord asks the chronicler to omit a massacre; the scribe's version becomes the "official" retelling (Legend); a survivor's grandchild later challenges it.
10. **The cipher** [Scribe, Spy]. An enemy cipher must be broken before a treaty meeting; clues are in intercepted letters (`war_intel`).
11. **The plague ward** [Healer, Priest]. A plague variant arrives; the church's gathering rule helps the disease; the healer must reform a rite or defy it.
12. **Triage** [Healer, Soldier]. After a battle there are more wounded than herbs; a noble's son is among them; choices affect the army's trust and the healer's `psyche`.
13. **The poisoned well** [Healer, Spy]. A well is poisoned; the culprit's motive is rooted in a secret chain; revealing it ruins a house.
14. **The novice's secret** [Priest]. A confession reveals a plot; keep the seal or break it; reputational outcomes differ by faith (`faith.gd`).
15. **Schism** [Priest, Noble]. A king wants a divorce; the priest's reply splits the church (`organizations` schism) and starts an Era shift.
16. **The deep shaft** [Miner, Architect]. Flood in a deep level; engineer an adit (long project, Work) or abandon; the adit becomes a regional landmark after years.
17. **The cathedral at 40 years** [Architect, Priest]. A cathedral outlasts the architect; funding changes with Eras; the heir must decide whether to finish it, change it, or sell the stone.
18. **The leaked plan** [Architect, Soldier, Spy]. A fortress's plans are stolen; the architect must redesign without moving the walls.
19. **The ford and the ferry** [Sailor, Merchant]. Spring flood closes the ford; ferry licence disputes; a rival ferry undercuts and cuts corners.
20. **Plague ship** [Sailor, Healer]. A ship with plague is refused; the captain is a former friend; choices have district effects.
21. **Safe-conduct** [Caravan Master, Priest]. A caravan carrying a relic crosses heretic land; negotiate, bribe, disguise or fight.
22. **The border closes** [Caravan, Noble]. A war closes the border mid-route; hold, reroute or run; goods and workers' wages affected through `ledger`.
23. **The unpaid garrison** [Soldier, Noble]. Arrears cause the ladder of delayed pay > resign > desert > embezzle > mutiny; the player (as captain) can pay from own purse, steal, or negotiate.
24. **The coup** [Noble, Soldier]. Per MW-12: the commander demands land after three victories; refuse and he coups when the lord is absent; the player may have seen it coming from persona hints.
25. **The honest steward** [Noble, Scribe]. A steward's honesty changes tax output (MW-13); firing him leads to an audit that reveals the previous lord's debt.
26. **The unwanted heir** [Dynasty]. The heir wants to be a bard, not a lord; the family business decays; a cousin takes the seat; the heir must rebuild from songs.
27. **The oath returns** [Dynasty, any]. An unpaid oath from the parent (`MW-24`) comes due; a village demands payment from the heir.
28. **The song that lied** [Bard, Noble]. A flattering song hides a crime; a rival bard sings the truth at a festival; both versions persist as tales.
29. **Epic of the unknown** [Bard]. The player writes an epic of an NPC hero who is actually an impostor; the world believes it.
30. **Festival contest** [Smith, Bard, Farmer]. A harvest fair has contests; winners gain patronage; losers gain a grudge; judges can be bribed (`courts` corruption).
31. **The guest in room four** [Innkeeper, Spy]. A guest with a secret dies; the innkeeper decides whether to report (`courts`), hide, or use what is found in the room.
32. **The neutral ground** [Innkeeper, Noble]. Two houses at odds use the inn for talks; the innkeeper's neutrality is tested when one side tries to bribe.
33. **The pupil spy** [Thief/Spy, Scribe]. A bright pupil is an informant for a rival; the master discovers it and decides to use or break it.
34. **Counter-intel adapts** [Spy]. After many stealth jobs, the watch raises night guards, then adds dogs, then hires a locksmith to install new locks; the player rotates methods.
35. **The kingmaker** [Spy, Noble]. A chain of secrets can topple a regent; the cost is the player's own secret being discovered.
36. **First clear stolen** [Adventurer]. A rival party completes the player's target floor first (`towers.gd`); the player can race, sabotage, ally or find a different tower.
37. **The relic's owner** [Adventurer, Priest]. A recovered relic belongs to a church; the player's legend decides if the church treats them as thief or saint.
38. **The echo's request** [Adventurer, Mage]. An echo (`echoes.gd`) of a defeated apex asks for a task; fulfilling it changes a region's ecology.
39. **Rift storm** [Mage, Soldier]. A Rift wakes (`emergence rift_activation`); the mage's ward fails at a bad time; blame lands on the academy.
40. **The forbidden student** [Mage]. A student learns a forbidden art; the master chooses to teach safe limits or expel; the student may be an Era's villain or hero later.
41. **The spell in the church** [Mage, Priest, Scribe]. A treatise holds a lost spell; the church wants it burned; a scribe can copy it in secret.
42. **The rival hero's child** [Adventurer]. The rival's child grows up and asks the player to train them, or to stay away from their family.
43. **Legend distorted** [Any]. A small deed becomes a monster story in a far town; a bounty is posted on a "beast" that is the player; resolving it requires the original witnesses.
44. **Total ruin** [Any]. Bankruptcy and exile after a lost war; the Rebuilding ladder starts with a hut, a loyal former apprentice and an old debtor.
45. **The ruined founder** [Founder]. A founded guild turns corrupt after the player's death; the heir sees the charter perverted; they can reform, leave or burn it.
46. **New region, old curse** [Explorer, Architect]. A new region's town has a curse that is actually a lost drainage system; an architect and a priest each have a different solution.
47. **Era of ash** [All]. A volcanic winter shortens seasons for three years: farmers shift crops, smiths make fewer swords, bards sing laments, soldiers face bandit hordes of starving people; each profession's frontier changes data-wise.
48. **The collector's price** [Collections]. A collector with 20 songs teaches a rare Technique; the 21st song is in a ruined temple guarded by a rival.

---

## 10. Module map (existing support)

Status key: EXISTS = full or near; PARTIAL = pieces; MISSING = nothing found by greps. Paths are relative to `kingdom/scripts/`.

| Idea | Status | Existing modules | Gap |
|---|---|---|---|
| Career ladders with vacancies | EXISTS | `sim/careers.gd`, `sim/career_ladders.gd`, `data/careers/ladders.json` | Ladders end; need frontier beyond top (EP-2) |
| Deep careers (scribe, soldier, trades) | EXISTS | `realm/scribe.gd`, `soldier.gd`, `career_trades.gd` | Others lack depth (EP-9) |
| Professions missing from ladders: mage, priest, miner, architect, bard, spy, adventurer (partially in guild), caravan master, sailor | MISSING/PARTIAL | `adventurer_guild.gd`, `power_paths.gd`, `cultivation.gd`, `faith.gd`, `construction.gd`, `caravans.gd` | Career wrappers over existing systems (EP-9) |
| Problem Frontier | MISSING | `radiant_quests.gd`, `emergence.gd` as sources | `realm/practice.gd` + data (EP-2) |
| Novelty ledger | MISSING | `radiant_quests.gd` has shuffle-then-repeat only | `realm/novelty.gd` (EP-1) |
| Named Works | MISSING | `crafting.gd` quality tier; `titles.gd` | `realm/works.gd` (EP-3) |
| Techniques with holders; lost knowledge | MISSING | `skill_evolution.gd`, `mastery.gd` (player only), `education.gd` | `realm/techniques.gd` (EP-3) |
| NPC mastery growth | MISSING (MW-32) | `persona.gd` static skill bytes | yearly step (EP-3) |
| Legend and tales | MISSING | `rumours.gd`, `reputation.gd`, `events.gd`, `biography.gd` | `realm/legend.gd` (EP-4) |
| Rival heroes and masters | PARTIAL | `notables.gd`, `towers.gd` NPC parties, `bonds.gd` rivalry axis | `realm/rivals.gd` (EP-5) |
| Mysteries and secrets chains | PARTIAL | `secrets.gd`, `courts.gd` ledger, `evidence.gd`, `exploration.gd` | `realm/mysteries.gd` (EP-6) |
| Heir loop and estate ledger | PARTIAL | `sim/family.gd` (`succeed_to`), `dynasties.gd`, `succession.gd` | estate ledger, heir calling, tales to heir (EP-7) |
| Ruin and rebuilding | MISSING | `ledger.gd` shortage ladder, `reputation.gd` | rebuilding ladder (EP-7) |
| Eras and world events | PARTIAL | `emergence.gd`, `seasons.gd`, `faith.gd` schisms | `realm/eras.gd` (EP-8) |
| Festivals with content | PARTIAL | `town_mood.gd` FESTIVAL flag | contest/trade/ritual slots (EP-8) |
| Collections | PARTIAL | `sim/discovery.gd` | bestiary, herbal, songbook etc. (EP-11) |
| Hidden places keyed by knowledge | PARTIAL | `exploration.gd`, `hidden_triggers.gd`, `sim/discovery.gd` | key records (EP-6) and place seeds (EP-10 Codex) |
| New regions | PARTIAL | `ashes-region-content` skill, `data/world/regions.json` | content (EP-10 Codex) |
| Water, ports, sailing | MISSING | Coldharbor ferries (data), longship asset | EP-10 Codex, EP-9 cloud, EP-13 Antigravity |
| Apprentice and school model | PARTIAL | `education.gd`, `organizations.gd` academy | Master's Table apprenticeship loop (EP-2/EP-3) |
| Counter-intelligence adaptation | MISSING | `crime_watch.gd`, `courts.gd`, `perception.gd` | method memory (EP-12) |
| Animation for all new crafts and performances | PARTIAL | `actors/character_animator.gd`, `crowd_anim_lod.gd`, `smart_objects.gd` | Antigravity (EP-13) |

---

## 11. Work packages (EP-1 to EP-14)

Conventions: each package follows the `ashes-realm-module` rules (hub registration, tick tiers, chunked day ticks, determinism, saves) and `ashes-work-package`. Tests are gdUnit under `kingdom/tests/` named `test_ep_*.gd`. "Perf" lists the added cost. Save sizes are quoted against the 2.5 MB raw save limit (schema 4).

### EP-1. Novelty ledger and variety floors (cloud)
- **Build.** `scripts/realm/novelty.gd`: packed ring of 512 entries; `score(shape)`, `note(shape, day)`, weekly budget per generator; hook into `sim/radiant_quests.gd` (kind choice), `sim/adventurer_guild.gd` (board), `realm/emergence.gd` (chain start), and later EP-2/EP-6/EP-8.
- **Tests.** `test_ep_novelty.gd`: (1) repeat blocked except urgent; (2) distinct-shape ratio over 365 days on a seeded world; (3) save/reload/run 30 days equal hash; (4) half-life decay numeric check.
- **Perf.** O(1) lookups; day-tick write only; ~4 KB save.
- **Depends.** None. Do first.

### EP-2. Problem Frontier engine and profession data (cloud)
- **Build.** `scripts/realm/practice.gd` + `data/living_world/practice/*.json` (one file per profession, 5 bands each with at least one new verb and one new problem class, as in P1). Evaluates on the day tick for the player's active professions; emits up to 6 offers per profession; offers carry cause lines and winners/losers (MW-11). Lint script checks every band has a source independent of the prior band.
- **Tests.** `test_ep_practice.gd`: data lint (every profession x band has verb+class); an offer appears only if its source condition is true in a synthetic world; each offer has a cause string; capped at 6; deterministic.
- **Perf.** Day tick only, closed form; under 0.2 ms for 10 professions; no per-frame work.
- **Depends.** EP-1.

### EP-3. Works, Techniques, lost knowledge, NPC mastery step (cloud)
- **Build.** `realm/works.gd` (cap 600, ~40 B each), `realm/techniques.gd` (cap 200 techniques, holders list max 8, state common/rare/lost, teacher conditions), yearly closed-form step for NPC masters (MW-32), death of last holder flips state to lost with an event. Rediscovery hooks: book (Scribe), ruin (exploration), echo (`echoes.gd`). Tie `crafting.gd` quality rolls to emit a Work for top-tier output with a name.
- **Tests.** `test_ep_techniques.gd`: last holder dies -> lost + event; rediscovery restores; teacher condition respected; Works cap and compaction; deterministic across save/reload.
- **Perf.** Yearly step across 1,000 characters < 2 ms; weekly nothing; save ~40 KB worst case.
- **Depends.** EP-2 for card hooks.

### EP-4. Legend: Deeds and tales (cloud)
- **Build.** `realm/legend.gd`: Deed ring (cap 300, 24 B); `tale(deed, teller, listener)` pure function; NPC chat/bark and board generators read it; Chronicle record for Scribe's official history; bard Works propagate as tales. A distortion bound (magnitude changes at most 2x, kind flips only with a bias reason).
- **Tests.** `test_ep_legend.gd`: same deed, two tellers with different persona/culture/distance produce different outputs; no unbounded drift; a witness reads the true variant; a bounty from a distorted tale is cancellable by evidence.
- **Perf.** Tales computed on demand at dialogue time; no storage beyond deeds.
- **Depends.** None (reads `rumours.gd`, `persona.gd`, `reputation.gd`).

### EP-5. Rival heroes and masters (cloud)
- **Build.** `realm/rivals.gd`: assign up to 2 rivals per profession when the player enters Master; rivals have goals via `notables.gd`/`towers.gd` parties; race rules for firsts; rivalry axis in `bonds.gd`; reconcile/ally/enemy transitions; method memory (8.4) hook for adaptive counters. Rival's child becomes next rival on death.
- **Tests.** `test_ep_rivals.gd`: rival assigned at Master, capped; a rival wins a race when the player is absent; rivalry decays and can flip; child inherits.
- **Perf.** Weekly step over <= 30 rivals; negligible.
- **Depends.** EP-3, EP-4.

### EP-6. Mysteries, secrets chains, hidden-place keys (cloud)
- **Build.** `realm/mysteries.gd` + `data/living_world/mysteries/*.json` templates (hook, clues, herrings, culprit persona, branches, world effect); clue placement through `secrets.gd`, `rumours.gd`, `exploration.gd`; knowledge-key records for hidden places.
- **Tests.** `test_ep_mysteries.gd`: a generated mystery is solvable from placed clues (graph reachability); red herrings bounded; branches produce distinct court/district outcomes; no two active mysteries share a culprit; novelty hook.
- **Perf.** Generation on the weekly tick, at most 3 active mysteries; clue placement is O(clues).
- **Depends.** EP-1.

### EP-7. Legacy: estate ledger, heir calling, ruin and rebuilding (cloud)
- **Build.** Estate Ledger summary on `family.succeed_to`; heir persona/calling selection; tales of the parent told to the heir; unpaid oaths (`MW-24`) transfer; Rebuilding ladder for ruin states (bankrupt, exiled, outlawed, disgraced, defeated); a "risen" reputation tag.
- **Tests.** `test_ep_legacy.gd`: handover preserves reputation and name, not titles; oath and feud carry; rebuilding stages advance only by real actions; an heir with a different calling gets that profession's frontier.
- **Perf.** One-off at handover; negligible.
- **Depends.** EP-3, EP-4.

### EP-8. Eras, festivals with content (cloud, Codex for festival dressing)
- **Build.** `realm/eras.gd`: seeded era shifts every 6 to 10 years, 3 to 8 years long, with per-profession response tables in the practice data; festival content generator (contest, trade, ritual, plot slots) over `town_mood.gd` FESTIVAL; Codex dresses the festival grounds.
- **Tests.** `test_ep_eras.gd`: era start/end deterministic; modifiers bounded; each profession has a response; festival slots produce at most N events; save/reload equal.
- **Perf.** Yearly + day tick for active era; negligible.
- **Depends.** EP-2.

### EP-9. Missing career wrappers and new profession depth (cloud)
- **Build.** Ladders and practice data for priest, mage, miner, architect, bard, spy/thief, caravan master, adventurer (guild ranks exist); healer disease variants and triage; hunter wardenship; innkeeper guest-secrets stream; merchant credit chains. Use existing systems (`faith.gd`, `power_paths.gd`, `construction.gd`, `caravans.gd`, `secrets.gd`, `ledger.gd`).
- **Tests.** One test per profession: ladder requirements, one frontier card from each band, one failure mode.
- **Perf.** Data and day-tick evaluators; no per-frame.
- **Depends.** EP-2.

### EP-10. Water, ports, new regions, hidden places (Codex)
- **Build.** Navigable river and (if chosen) coast with ports; Coldharbor harbour; a second region with a signature problem and 1 to 2 local callings; place seeds for hidden places, keyed by cloud records (EP-6); mine depth hazards; map icons. Follow `ashes-region-content` and `ashes-world-lint`.
- **Tests.** World lint passes (no floating, clipping, road-blocking); id uniqueness; discovery ids stable; sailing route graph connected.
- **Perf.** Within per-site draw budgets; streaming via existing cell streamer.
- **Depends.** None for content; EP-9 for sailor logic.

### EP-11. Collections (cloud, UI by local PC)
- **Build.** Bestiary, herbal, atlas, songbook, armoury, codex, chronicle; collection thresholds unlock rare teachers (EP-3). Data-only collection definitions.
- **Tests.** `test_ep_collections.gd`: entries add once; thresholds unlock the teacher condition; no power gating.
- **Perf.** Bit sets; tiny.
- **Depends.** EP-3.

### EP-12. Adaptive adversaries (cloud)
- **Build.** Method memory (last 5 methods) in `crime_watch.gd` and `rivals.gd`; counter-measures within +/- 0.2 thresholds; investigators in `courts.gd` read it.
- **Tests.** `test_ep_adapt.gd`: repeating a method raises its cost within the bound; a different method resets; deterministic.
- **Perf.** Per-player constant-size record.
- **Depends.** EP-5.

### EP-13. Animation for new crafts, performances, water (Antigravity)
- **Build.** Clips and state machines for: forge variants (folding, quench), farming (grafting, threshing), scribing and illuminating, healing (bandaging, surgery), mining (shoring, hauling), bardic performance (instruments, crowd reaction), architect drafting and site direction, caravan loading, ferry poling and rowing and sailing, spell-casting for new Techniques. Use the reaction interface (MW-41) and smart-object affordances (MW-44); animation LOD per `crowd_anim_lod.gd`.
- **Tests.** Clip presence tests per craft (name list in data); animation tree validity test; frame sheets via `ashes-video-review`.
- **Perf.** Near tier only; shared clips across NPCs; within the 24 full-body budget.
- **Depends.** EP-9, EP-10 (for sailing).

### EP-14. Soak, balance and save budget (cloud)
- **Build.** A 20-game-year soak with no player and one with a scripted player in each profession; measures: distinct problem shapes shown per year, share of gold from access versus numbers, number of lost/rediscovered Techniques, number of deaths, heirs, rivals; asserts save < 2.5 MB raw, pump budget 0.6 ms, determinism hash.
- **Tests.** `test_ep_soak.gd` (headless), extending `test_lw_society_soak.gd`.
- **Perf.** CI only (use `ashes-ci`).
- **Depends.** EP-1 to EP-9.

---

## 12. Order of work

1. EP-1 (novelty) and EP-4 (legend) in parallel; they are independent and pay off at once in the boards and dialogue.
2. EP-2 (frontier) with data for the three deepest careers (smith, scribe, soldier) as proof, then EP-9 for the rest.
3. EP-3 (works and techniques), then EP-5, EP-7, EP-11.
4. EP-6 (mysteries) and EP-8 (eras) once the frontier carries content.
5. EP-10 (Codex world) runs in parallel from day one; EP-13 (Antigravity) follows each craft as data lands.
6. EP-12 and EP-14 close out.

## 13. Risks and answers

| Risk | Answer |
|---|---|
| Novelty becomes randomness | Budget and urgency rule (8.2): real needs reframed, never hidden; deterministic rolls |
| Too many systems to see | Surface through the weekly digest (MW-33), one "Problem board" per profession, no notification spam |
| Save growth | Section 14 budget; every store capped and compactable |
| Content cost per profession | Problems are data rows over existing state; professions share the frontier engine |
| Masters become unbeatable | NPC masters grow too (MW-32); rivals adapt (8.4); stakes rise with band (3.1) |
| Players ignore the new layer | Layers are access-based (seats, schools, secrets); early and mid play stays fully valid (P10) |
| Water is out of scope | Sailor stays MISSING until Codex adds it; every other profession ships without it |

## 14. Budgets

| Store | Cap | Bytes | Total |
|---|---|---|---|
| Novelty ledger | 512 | 8 | 4 KB |
| Works | 600 | 40 | 24 KB |
| Techniques | 200 | 48 + holders 8 x 4 | 16 KB |
| Deeds | 300 | 24 | 7 KB |
| Rivals | 30 | 32 | 1 KB |
| Mysteries (active 3, history 40) | 43 | 120 | 5 KB |
| Era and festival state | 1 + 40 | 24 | 1 KB |
| Collections bitsets | 8 | 64 | 0.5 KB |
| Estate ledger | 1 | 2 KB | 2 KB |
| **Total** | | | **about 60 KB** (2.4% of the 2.5 MB raw limit) |

CPU: all new work runs on day, week or year ticks inside the existing pump budget (0.6 ms), uses closed-form steps and the existing chunked `tick_day_chunks`; none adds per-frame work in `scripts/realm`. Threads follow MW-36 (pure data only).

---

## 15. Acceptance: how we know it never stops

- **Variety.** In a 20-year soak with a player in each profession, no problem shape is shown more than 3 times per year and at least 60% of shapes available to that band are seen.
- **Depth.** For every profession, each band lists at least one new verb and one new problem class (lint).
- **Persistence.** A Work or Technique from year 2 is referenced by a tale, a rival, or an heir by year 20 in at least half of the soak seeds.
- **Rebirth.** A bankrupt or exiled player reaches the second rebuilding stage using only real actions in the soak script.
- **Cost.** Total new save size under 100 KB; pump under 0.6 ms; determinism hash equal after save/reload.
