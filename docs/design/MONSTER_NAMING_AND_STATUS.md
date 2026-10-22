# Monster Naming, Companion Recruitment and Social Status

Status: design, 2026-10-21. Godot 4.6.2, PC-first. Read-only audit of the repo; no code, git or Godot was run. Owners: **cloud = systems** (all `scripts/realm/*`, `scripts/sim/*`, saves, tests); **Antigravity = all animation** (evolution morphs, speech/emote clips, gate and crowd reactions); **Codex = world** (monster districts, gates, props, placement).

Owner request (verbatim intent): naming monsters should become a real mechanic; recruiting a monster means some towns refuse you if your status is too low, and people in your settlement leave too; social status matters everywhere; NPCs do and talk a lot.

## 0. WARNING: inspiration only

The naming-gives-evolution idea is a well-known isekai trope (the most famous example is a light-novel and anime about a man reborn as a slime). This design takes only the generic premise "a powerful being gives a creature a true name; the creature grows". Rules for every contributor, writer and asset generator:

1. **No copied names.** No character, nation, skill, title or place names from that series or any similar series. That includes famous slime-ruler names, "Great Sage"-style skill names, "Demon Lord"-ranking schemes, "Tempest"-style nation names, "Harvest Festival"-style event names, and the term **magicule(s)**.
2. **No copied text or scenes.** No lines, plot beats in sequence, or recognisable set pieces (for example a named creature instantly becoming a handsome humanoid after a feast scene).
3. **Existing repo risk to fix.** `scripts/sim/naming.gd` uses the class `RAMagicules` and the player-facing word "magicules", and ships a `slime` species whose evolution reads "Spirit Slime ... absorb and mimic what they eat". "Magicules" is series vocabulary. Action item MN-0: keep the internal class name if renaming is costly, but every player-visible string must say **soul reserve** (the pool) and **ember** (one unit of reserve cost). Re-check the slime hint text against the series; keep slime only as one species among ten, with no special primacy and no "absorb and mimic everything" signature power (give it "filters water, mends rot" instead).
4. **Original lore.** Rising Ashes already has its own frame: Soul Power, Soul Tier, Soul Name ritual, Ashborn/Ashmarked forms, the Rift, the Urrokai and Veyl minorities, the Church of the Dawn Throne, Valencios runestones. Everything below hangs on those. New proper nouns are invented fresh and listed in section 14 for a lore review.
5. **Review gate.** Any new monster name, title, rank or line of dialogue passes a one-line check: "would this make a fan of that series say that is theirs?" If yes, rename. MN-14 adds a test that scans new data files for a deny-list of the series' proper nouns.

## 1. What already exists (audit)

| Area | Status | Evidence | Gap |
|---|---|---|---|
| Ordinary naming of a monster (cost, risk, evolve, class, loyalty, desertion) | EXISTS, NOT WIRED | `kingdom/scripts/sim/naming.gd` (`RANaming`: `preview`, `name_monster`, `tick_day`, `adjust_loyalty`, `dismiss`, 8 species, 7 classes, level-loss, Soul Fatigue, Fractured Core); `tests/test_soul_naming.gd`, `test_guild_naming.gd` | header says "not wired yet"; no UI, no world body change, no social effect |
| Soul Name ritual (permanent share of max Soul Power, tier gate, bond limits, monster or person) | EXISTS, NOT WIRED | `naming.gd` `soul_name_ritual`, `SOUL_FORMS` (10 species), `BOND_LIMITS_BY_TIER` | no evolution of body, intelligence or speech; no consequences for bystanders |
| Soulbeast companions (brain, save, aura, director) | EXISTS | `actors/soulbeast.gd`, `soulbeast_brain.gd`, `soulbeast_save.gd`, `soulbeast_aura.gd`, `world/soulbeast_director.gd`, `tests/test_soulbeast.gd` | beast-only; no society reaction |
| Monster settlements | PARTIAL | `world/monster_camps.gd` (goblin_warren, orc_village, residents on demand, attack tokens); map text in `ui/world_map.gd`; `realm/ecology_data.gd DUNGEON_KINDS`; `realm/ecology_factions.gd`; `sim/monster_ecology.gd`; CIVILIZATION.md "intelligent monster factions" | monsters are hostile props; no trade, law, gate, district or citizenship |
| Observer reads a subject (`companions`, `title_rank`, `insignia`, `disguise`) | PARTIAL | `realm/social_perception.gd` (`read`, `identity`, `bump_reaction`); companions only add to threat/protection | no species-aware prejudice, no "monster-bonded" flag |
| Multi-axis reputation with belief delay | EXISTS | `realm/reputation.gd` (9 axes, scopes `i h t f r a k`, `record`, `on_deed`, `view`, messengers/traders/rumours) | axes lack fame, infamy, "company kept"; no monster-related deeds |
| Titles, ranks, sponsors | PARTIAL | `audiences.gd` (`rank_of`, `title_rank`, `sponsor`, `gate_words`), `campaign.gd` player rank, `career_trades.gd rank_title`, `homes.gd title_recognised` | no single Status number; no entry check |
| Recruitment (contracts, evaluate, notices, chains) | EXISTS | `realm/recruitment.gd` (1,242 lines) | humans only; no monster recruit path |
| Follower motives/orders/betrayal | EXISTS | `realm/follower_will.gd` (7 motives, hidden agenda, `respond`, `on_event`, `wanted_request`, `appoint_governor`) | no species drives; not hooked to naming loyalty |
| Settlement founding, land law, districts | EXISTS | `realm/founding.gd`, `land_law.gd`, `district_values.gd` (quarters, culture mix, tension), `homes.gd` (moves between towns) | no monster quarter kind; no leave-because-of-monsters reason |
| Faith | EXISTS | `realm/faith.gd` (runes, dawn, wild, folk; church influence; `etiquette_mod`, `law_mult`) | no stance on monsters or ensouled beasts |
| Laws and curfew | PARTIAL | `governance.gd curfew_active`, `stewardship.gd permits`, CIVILIZATION.md "laws per region" | no entry law, no gate check, no monster-part or beast-in-town law |
| Rumours, news, barks | EXISTS | `rumours.gd`, `news.gd` (has `monster_settled`), `population/talk_bark.gd`, `talk_pose.gd` | no status-aware lines |

Conclusion: the numbers for naming exist; the world does not yet notice. This design wires naming to bodies, then to a Status model, then to gates and settlement reactions, using only existing modules plus three new ones.

## 2. The naming bond (mechanics)

### 2.1 Two grades

- **Lesser Name** (existing `name_monster`). Paid from the soul reserve. Evolves the creature one step, grants a class, loyalty starts at `BASE_LOYALTY` 75 (+10 if class is favoured). Any caster with reserve. Unlimited roster size in theory, bounded by loyalty upkeep (section 2.6).
- **True Name** (existing `soul_name_ritual`). Permanently shares 8% of the namer's max Soul Power (`SHARE_FRACTION`), needs Soul Tier 3+, bond slots by tier (`[[3,1],[5,2],[7,3],[9,4],[11,6]]`), loyalty 90. Only a True Name opens the **speech** and **second evolution** branches. A True Name can be spoken to a trusted person too (existing), which is how a human sworn-companion is made; same bond record.

Player-facing words: reserve = "soul reserve", unit = "ember", Lesser = "calling-name", True = "soul-name". (Original; neutral.)

### 2.2 Cost and risk (extend, do not replace)

Keep `BASE_COST`, `SHORTFALL_RISK`, `LEVEL_GAP_RISK`, `POWER_RISK` constants. Add:

- `cost = BASE_COST * level * power * form_factor * tribe_factor`, where `tribe_factor` = 1.0 for a lone creature, 0.7 per member when naming a group in one rite (section 2.7), minimum total 1.4x single.
- **Exhaustion tiers** after the rite, by fraction of reserve spent: under 40% none; 40-70% "winded" (-20% regen 1 day); 70-100% **Soul Fatigue** (existing; no spells 1-3 days, deterministic); overdrawn (cost above reserve, allowed with a confirm) rolls the existing injury table, up to **Fractured Core** until a healer treats it, and a **sleep** state: namer collapses for 6-24 game hours, helpless. Collapse outdoors near hostiles is the real danger; the world must run (the monster you named is the only guard, and a loyal one defends you).
- **Naming too strong**: if `target power x level` exceeds the namer's effective capacity (`Soul.tier()` and `level - level_penalty`) by ratio r:
  - r <= 1.0: normal.
  - 1.0 < r <= 1.5: success chance falls; failure = **refused name** (2.8) plus backlash.
  - r > 1.5: the creature may accept the name and the namer pays more than they have: **hollowing**, the namer's max pool loses the shortfall permanently (floored at 25% of max, recoverable only by a shrine quest). The creature still evolves, but its **will** starts at independence 0.8 (section 6): you made something stronger than you.
  - r > 2.5: naming is **refused outright** by the interface (preview shows "it would be like naming a storm"); only an Ancient True Name quest (MN later) bypasses it.
- All rolls from the seeded RNG already serialized in `RANaming`, with `(seed, day, bond_id)` tags so tests are deterministic.

### 2.3 What changes in the creature (evolution)

Four independent tracks, each a small integer 0..4, stored on the bond record. They rise at naming and again at **growth moments** (day ticks, deeds, shared battles, being addressed by name, the namer's tier rising). The names of the stages are original.

| Track | 0 | 1 | 2 | 3 | 4 |
|---|---|---|---|---|---|
| **Form** | wild body | grown (`evolves_to`: Hobgoblin, Storm Wolf, High Orc ...) | soul form (`SOUL_FORMS`: Goblin Chief, Warlord Orc ...) | kin-shaped: bipedal, hands, clothing-capable | lord-form: unique silhouette, aura visible |
| **Mind** | instinct | cunning (plans, remembers faces) | reasoning (uses tools, haggles) | letters (reads, writes, keeps accounts) | counsel (can govern, advise, lie well) |
| **Speech** | growls | understood words (obeys commands) | pidgin (short phrases, 4-word barks) | fluent (full barks, can talk to any NPC) | eloquent (formal register, can petition a court) |
| **Ability** | one innate | + class stat offsets (`CLASSES`) | + species trait (below) | + a learned technique from the namer's path | + a signature unique power |

Rules:
- At naming, the target stages are set by `min(namer_power_band, species_ceiling)`. Namer band uses Soul Tier: tier 3-4 gives up to Form 2/Mind 2/Speech 2; tier 5-6 up to 3; tier 7+ up to 4. Lesser Name caps all tracks at 2. True Name unlocks 3 and 4.
- **Bond depth** (0..100, new field) = shared fights + days together + gifts + being spoken to. Each track above the cap-at-naming needs bond depth thresholds (30, 55, 80). A monster named by a weak namer can still become eloquent if the bond is deep, but only to the species ceiling.
- **Species ceilings** (per track; `power` values from `naming.gd`): slime 3/4/3/3 (mind-heavy, body-light); goblin 3/3/3/3; kobold 3/3/3/3; wolf 3/2/2/4 (wolves reach Speech 2 only: short phrases, never letters); bear/troll/ogre 4/2/3/4; spider 3/4/2/4 (clever, silent-ish: speech is gestures and web-signs, a design rather than a limit); orc 4/3/4/4; lizardfolk 4/4/4/4 (the ceiling species, long-lived scholars). **Undead** and **dragonkin** are new species (section 4).
- Evolution takes **three days of dormancy** for stage jumps (cocoon, fever, sleep) during which the creature is vulnerable, cannot be commanded, and its wild kin may hunt it. Antigravity owns the morph animation, a vignette (dormancy pose, form swap, first-standing) and the speech-lip/emote set.
- Evolution never produces a human-looking person automatically. Kin-shaped Form 3 stays clearly a hobgoblin, an orc, a lizardfolk. This avoids the trope's signature beat and gives gates a real question: "what is it?"

### 2.4 Species traits (Ability 3)

One per species, original and cheap: goblin = "tinker" (+craft speed, repairs gear), wolf = "tracker" (follows a scent trail across days), kobold = "vein-nose" (ore sense), slime = "clarifier" (purifies water, mends rot in a building), lizardfolk = "cold-blooded counsel" (resists charm, reads lies), orc = "oathkeeper" (breaking its sworn word costs it health; it rarely breaks it), spider = "silken ward" (alarm threads on a camp), ogre = "tireless" (carries 3x), bear = "winter-sleep" (dormant but healed over winter), troll = "bridge-keeper" (holds a chokepoint).

### 2.5 The namer's ledger

Each bond stores: `bond_id, namer, subject_id, species, grade, day, cost_paid, form/mind/speech/ability, depth, loyalty (0..100), independence (0..1), ambition, grudge_list, name_story_id`. Budget: about 140 bytes packed; 16 bonds max per save is 2.2 KB.

### 2.6 Upkeep and decay

- A named monster has a **keep**: food, a place to sleep, and being spoken to. Each missing keep drops loyalty 1-3/day (existing `tick_day` desertion below `DESERT_BELOW` 25 with 10% chance; keep that, add scaling).
- Reserve is **not** drained per day for Lesser Names. True Names keep the permanent 8%, plus a regen tax of `SHARE_REGEN_FRACTION` 2% on regen. Dismissing a True Name gives back half of the shared pool (a "release"), the rest remains lost: leaving costs.
- A named monster dies: namer takes a one-time **grief** debuff (loyalty of all other bonds -5, Soul Fatigue chance for True Names). The name is not lost; it is carried by rumour as a legend (section 2.9).

### 2.7 Naming tribes and groups

- **Rite of the Many**: the namer names a leader (True or Lesser), and the leader then calls the tribe. The tribe members take **kin-names** derived from the leader's: they cost a fraction (`tribe_factor` 0.7) and each gets Form 1 / Mind 1 / Speech 1 only.
- Limits: tribe size `<= 3 + tier*2` members per rite; total cost scales so a tribe of 12 costs about 5x a single, still a large share of a day's reserve. A big tribe needs a **feast** (food items) as an offering, else loyalty of the whole tribe starts at 55.
- Result: the camp (`monster_camps.gd`) flips from hostile to **vassal** with a `master` field; residents stop attacking the namer, gain nameplates, and may be **given work** (patrol, farm, forge). The tribe also gets an **elder voice**: the leader's Speech/Mind track gates what the tribe can negotiate.
- Mass naming has a visible side effect: Ashen weight (a small area aura, `soulbeast_aura.gd`) that frightens animals and adds district tension if inside a town (section 8).
- Failure mode: the leader accepts, one lieutenant refuses (2.8) and leaves with a faction, becoming a **rival** (section 2.10).

### 2.8 Refused names

A creature can refuse. Chance rises with: pride (species/individual trait), grudge against the namer's kind (the namer killed its kin), an existing bond to another namer or to a god (wild faith), `level >= namer power`, and being named while injured/starving (starvation lowers refusal but lowers loyalty too). Outcomes: nothing happens and a cooldown of 7 days for that creature; backlash (cost half paid, Fatigue); or **the creature names the namer back**: it says its own name and the namer takes a lesser bond obligation (a debt quest). Humans can refuse a True Name too; a refused person loses trust (-15).

### 2.9 Names spread as legend

When a name is given, a **name story** is written to `rumours.gd`/`news.gd`: `{subject, namer, species, form, place, day}`. It spreads by existing channels (messengers fast, traders slow, rumours garbled via `reputation._distort`). Three effects:
1. **Fame/infamy** on the namer in each town that believes it (section 3).
2. **Legend rank** of the creature: after N shared deeds the creature gets a **byname** ("Ember-Fang of the Eastern Pass"; generated from a template list authored by a writer, not from the series). Barks quote it.
3. **Pull**: monsters hear it. Wild monsters of the same species within 3 regions may seek the namer (petition: "name me too") - section 5.2.

### 2.10 Rivals naming monsters

Rival namers are NPCs from existing factions (Church inquisitors, wild-faith shamans, a rival warlord, a Rift-touched hermit). They use the same `RANaming` calls with their own reserves. Events:
- **Race for a tribe**: both approach the same goblin warren; the first to complete the rite wins it; the second may try to **overwrite** (name over a name): a contested rite with a win roll on depth, tier and loyalty. The loser's bond is broken and the subject takes a "torn name" (-30 loyalty to the winner, -20 to everything for 5 days).
- **Stolen beast**: a rival renames your companion if loyalty < 40 and independence > 0.6 and a rival is within 20 m for a day.
- **Poisoned name**: a rival names a lone monster and sends it as an assassin; it carries a **tell** (a name-mark visible to Perception).
- **Duel of names** (late game): two named lords meet; bonds can be strained by commanding the same creature.

### 2.11 Loyalty, independence and ambition (use follower_will)

Every named monster is a follower row in `followers.gd` and gets a `follower_will` record. Map the seven motives to monsters:

| follower_will motive | Monster meaning |
|---|---|
| affection | bond depth, being spoken to, gifts |
| respect | namer's tier vs. the creature's power; battles won together |
| fear | namer's demonstrated strength; punishments |
| ideals | species ethos (orc oath, wolf pack, goblin clan, lizardfolk law) |
| greed | hoard, food, territory |
| protection | its tribe, young, den |
| hidden agenda | **ambition**: found a tribe, avenge kin, gain a seat at a council, own territory, be named a lord |

Add (new, `monster_will.gd`, small): an `independence` float 0..1 that rises with Mind/Speech tracks and falls with respect/fear. It selects `respond()` outcomes; at independence > 0.7 a named monster can: negotiate wages (recruitment contract path), refuse a moral order (`refuse_moral`: orders to burn a village), leave to found its own tribe (`consider_leaving` then `founding.gd`), or lead a coup (`attempt_takeover`) against the player's settlement. Monster ambitions are visible in dialogue after Speech 2.
- Wolf and bear species rarely roll hidden agendas; orc and lizardfolk often have ideals-based ones; goblins roll greed and power.
- Loyalty (existing 0..100) and independence are separate: a loyal, independent orc *advises*; a disloyal, dependent goblin *flees*.

## 3. Social status as a world pillar

### 3.1 The Status model

Status is **derived, never stored** (like `social_perception`), recomputed on demand from existing sources, and **per observer** (a town, a faction, a faith, a guild). Components, each 0..1 unless noted:

| Component | Source (existing) | Notes |
|---|---|---|
| Title | `audiences.title_rank` (0..5), `campaign.player_rank`, `homes.title_recognised` | recognised or not by the observer's kingdom |
| Wealth | `reputation` axis `wealth`, `ledger.gd` purse, property in `homes.gd` | visible wealth only (gear_value, property) |
| Reputation | `reputation.view(subject, observer)` axes competence, reliability, generosity, cruelty, legitimacy, trust | the town's belief, delayed |
| Faith standing | `faith.gd` (belief record, church influence, scandals) | new: `faith.standing(subject, church)` -1..1 |
| Guild rank | `organizations.gd` membership, `career_trades.rank_of` | highest rank among recognised guilds |
| Fame | new axis `fame` in reputation, 0..100 | being known; neutral |
| Infamy | new axis `infamy`, 0..100 | being known for the wrong things |
| Company kept | new, derived from `companions` and bonds | see 3.2 |

Observer-side modifiers: the observer's own Status (a noble reads you differently from a farmer), persona (`persona.gd` pious/courage), and `knows_true_id` as in `social_perception`.

```
base      = 0.20*title + 0.15*wealth + 0.25*trust_mix + 0.15*faith + 0.10*guild + 0.10*fame - 0.20*infamy
company   = sum over companions c of company_delta(c, observer_culture)    (can be +/-)
status    = clamp(base + company, 0, 1)             # 0 outcast ... 1 exalted
band      = outcast <.15, low <.35, common <.55, respected <.75, noble <.9, exalted
```

`trust_mix` = mean of reputation.view axes weighted (reliability, legitimacy, trust high; cruelty negative). The numbers are tunable in `data/world/status_weights.json`.

### 3.2 Company kept: companions modify status per culture

New table `data/world/culture_attitudes.json`: for each culture tag (from `faith.culture_tags(sid)`), an attitude toward each companion **kind** (human, tame beast, named monster by species, undead, dragonkin, spirit) as an integer -3..+3, plus a modifier by the companion's Form/Mind/Speech:

```
company_delta(c) = attitude[culture][kind] * (1 + 0.3*speech_track) * (0.5 + 0.5*civility(c)) * 0.06
```

Civility is a derived 0..1: clothed, quiet, leashed or heeled (+), has a name and a byname (+), recent harm to townsfolk (-). Examples per culture (original groupings):
- **Valencios (secular, runestone, mercantile)**: monsters are *property or labour*, not sinful. Named, speaking, taxed companions: +1 for useful guild-sponsored ones (a goblin accountant has a ledger), 0 for beasts, -1 for large predators loose in streets. Status penalty is mostly **legal** (permits), not moral.
- **Dawn Throne church kingdoms**: monsters are unclean; a soul-named monster is *unsanctioned binding* of a soul (heresy risk). Attitude -3 for orc/goblin/ogre/undead, -2 for wolf/spider, -1 for a tame ox-like beast. Wearing a **church seal** (sponsor from a bishop or a cleansing rite) flips one step upward. `faith.standing` drops by 0.2 per named monster in sight of a priest.
- **Wild-faith minorities (Urrokai, Veyl)**: beasts and some monsters are kin-spirits. A named wolf or bear: +2. Undead: -3 (they oppose the dead being kept).
- **Frontier hold towns**: +1 to usable fighters (orc guards, wolf scouts); status gain, not loss, if the player's company scares bandits.
- **Monster towns** (section 7): status is computed in the monster polity's own terms (power, oath-keeping, name-count); humans without a named companion read as *low*.
- **Folk (no church)**: tolerant; reaction driven by individual persona.

Total company bonus/penalty is clamped to +/-0.25 so a single disaster in company cannot erase a hero, and a monster court cannot buy a noble.

### 3.3 Status as the gate to everything

Status feeds: gate entry (4), tax and permit price (4), who speaks first (`MW-28`, etiquette), who sits with whom at a feast, whether a court hears you (`audiences.gd`), recruitment willingness (`recruitment.evaluate` trust/reputation inputs), housing rent (`homes.listings` multiplier), shop prices (`faith.price_mult` pattern), and NPC emigration (6). Always show it to the player as a plain-words **standing line** in the journal for the town you are in: "Respected in Ashford, Wary in Caldrenn."

## 4. Recruiting monsters (fit to existing species)

### 4.1 Paths

1. **Tame** (beasts): feed, patience, skill. No name needed. Wolf, bear, spider, ogre (hard). Status company = "beast". Mind 0-1.
2. **Name** (section 2): the main path for goblin, kobold, slime, lizardfolk, orc, ogre, troll, spider, wolf. Becomes a follower row.
3. **Hire** (contract, no name): intelligent monsters with Speech >= 2 may be recruited through `recruitment.engage` with `terms {w, d, n, h, x}`; they negotiate. Housing term `h` is crucial: a monster needs a **den or a room**, and towns may not allow it (4.5).
4. **Surrender**: defeated chieftains yield; they offer a tribe in exchange for protection (a quest hook).
5. **Petition**: a named legend draws wild kin (2.9): the creature arrives and asks to be named.

### 4.2 Species roster fit

| Species | Source in repo | Role fit | Attitude summary | Notes |
|---|---|---|---|---|
| goblin | `naming.gd`, `monster_camps.gd` goblin warren | clerks, smiths, scouts, raiders | disliked by all but frontier/Valencios guilds | Hobgoblin, Goblin Chief; high independence rolls |
| kobold | `naming.gd` | miners, tunnellers | tolerated by mining towns | vein-nose |
| slime | `naming.gd` | water, healers, builders | oddly accepted; "harmless" | de-emphasise per warning |
| wolf | `naming.gd`, `actors/wolf.gd` | scouts, hunters | accepted by hunting folk; feared in streets | Speech cap 2 |
| bear, troll | `SOUL_FORMS` | guards, porters | feared | |
| spider | `naming.gd` | alarms, weavers | dread | silent speech |
| lizardfolk | `naming.gd` | scholars, envoys | curious; Dawn Throne dislikes | **best diplomatic companion**; dragonkin precursor |
| orc | `naming.gd`, orc village | soldiers, guards | feared, respected by soldiers | oathkeeper trait |
| ogre | `naming.gd` | labour, siege | feared | tireless |
| **undead** | MISSING (no file) | sentinels, tomb guards | extreme revulsion; illegal in most places | new species; requires a graveyard dispute; Dawn Throne treats as capital offence; **do not allow naming undead in v1**; they can be *sealed servants* only (no name, no evolution), flagged `forbidden` |
| **dragonkin** | PARTIAL (`lizardfolk` -> Drakeblood trace) | apex envoy | awe and fear | v1: a Form 4 branch of lizardfolk only (**"Drakeblood Elder"**), not a separate recruit; no free dragons |

### 4.3 Recruit UX

Recruit interaction calls `preview()` and shows cost, risk, evolved form (silhouette only), and **expected social cost** in plain words: "Wolfhaven would admit you, with a muzzle on it. Caldrenn would turn you away." That line comes from a `gate_forecast(player, [companions])` for the nearest known towns (section 5). The player is never surprised by a gate; they are only surprised by a *rival's* consequence.

### 4.4 The party limit

Active companions follow you (max 3 + tier/3); the rest are **stationed** in your settlement (garrison, workers, outpost) or **kept** at a den (a lair building from `build_kit`). Stationed monsters are rows in WorldSim (cheap); only the active companions become full bodies near the player (`soulbeast_director.gd` budget).

### 4.5 Housing

A named monster needs: a den (build kit piece), a stable (beasts), a room (Form 3+), or a bed in a barracks. If none is available in a town where you rent a house, `homes.gd` gains a `monster_lodging` rent multiplier (x1.5) and a landlord **refusal** flag by culture; a refused lease falls back to a contract in a monster-friendly district.

## 5. Town gates and laws

### 5.1 The gate check

New module `realm/entry_law.gd` (pure + small state). Called when the player or an NPC party reaches a gate trigger (Codex-owned `world/gate_post.gd` places the trigger and a guard post). Inputs: `party` = list of {actor, kind, species, form, speech, civility, bond_id}, `town sid`, `hour`, `ctx`. Output:

```
{ verdict: "admit"|"admit_with_terms"|"turn_back"|"bar", terms: [...], reasons: [...], bribe_price, sponsor_options: [...], lines: [...] }
```

Algorithm (deterministic with `(seed, day, sid, party_hash)` noise):
1. Compute `status_to_town = status(player, observer=town)`; for each companion compute `required_status(c, town)` = `law_floor[town.culture][c.kind] + 0.03*c.power_level` (e.g. Dawn Throne: orc 0.6, wolf 0.45, goblin 0.55; Valencios guild-sponsored: 0.25).
2. If `status_to_town >= required_status` for all: admit (maybe with a permit fee).
3. Else produce **options** (not a flat refusal): leave the companion outside (stable or camp at the gate: it waits `n` days then wanders; loyalty -1/day), buy a **bribe** (price = `base * (0.3 + 0.7*corruption(town)) * danger`), get a **sponsor** (an NPC with `status >= required` vouches: `audiences.sponsor`), show a **permit** (guild charter, church seal, noble letter), take a **disguise** (muzzle, hood, cart, a "servant" cover; `social_perception.disguise.quality` vs the guard's perception; failure = arrest and fine), or **talk it down** (Charm/Persuade check scaled by Speech track of the companion: an eloquent lizardfolk may argue its own admission).
4. Hours matter: **curfew** (`governance.curfew_active`) excludes monsters entirely after dusk in strict towns even with permits ("no beast in the street after bell").
5. The result is logged to `reputation` as a deed (guard refusal is a witness event) and to `rumours`.

### 5.2 Law types (data)

`data/world/entry_laws.json`, per kingdom and per town override:
- **Open**: all admitted (Valencios free ports).
- **Registry**: companions must be recorded; fee per head; collar tag. (Valencios guild-towns.)
- **Escort**: only with a sponsor or with a handler of status >= 0.5.
- **Blessing**: church seal required (Dawn Throne).
- **Ban**: no named or unnamed monsters; beasts only with a pen.
- **Reserve**: monsters allowed only in a designated quarter (`district_values` kind `monster_quarter`).
- **Quarantine**: sudden after an attack by a named monster; lifted by a petition or time.
Laws change by events (`governance.gd`, `courts.gd`) and by **petition** (7.3).

### 5.3 Permit economy

Permits are items (ITEMS data) with ids, a price, an issuer (town, guild, church), an expiry, and a species/head limit. They can be forged (Intelligence or a forger NPC; failure at a gate is an arrest). A **Companion Charter** from the player's own settlement, once it has a recognised governor (`governance.gd`) and `status >= 0.55`, becomes a diplomatic instrument other towns can accept (reciprocity treaties in `diplomacy.gd`).

### 5.4 Sponsors and bribes

Sponsors are NPCs with `status >= 0.55` who like you (reputation trust >= 40). A sponsor costs favour: they ask for a deed, a gift, or a vote. Bribe amounts scale with corruption (`district_values` corruption value and `stewardship` governor traits) and each bribe leaves **evidence** (witness) that can be used against the guard or you later. Repeated bribes raise your **infamy**.

### 5.5 Disguises

A named Form 3+ monster can be disguised as a hooded servant or a masked porter. Success uses `social_perception.read` with the guard's `perception`, `intelligence`, and `magic_sense` (aura leaks, 2.x), quality of the disguise, and time of day. Failure outcomes: confiscation, fine, jail for the player (via `courts.gd`), the monster flees or fights.

### 5.6 Leaving monsters outside

The player can use a **gate-camp** (a hitching post and stable outside the walls, Codex prop) or a **den** nearby. Left companions: guard the camp, hunt for food, meet wandering NPCs (a trader may talk to them, a bandit may attack), and reappear on whistle (if loyalty >= 50 and distance < 400 m).

## 6. Settlement reactions

### 6.1 Residents leave

When the player's settlement (founded via `founding.gd`) houses named monsters or monster workers, each household computes **comfort** = `1 - prejudice(household.culture_tags, monster_kinds) * exposure` where exposure is the count of monsters in their quarter (`district_values` culture mix and tension) and whether they have been harmed. Below threshold the household rolls (weekly):
1. **Complain** (a gossip item to `rumours`).
2. **Petition** the governor (`audiences.gd` queue) with demands: move them, muzzle them, register them.
3. **Protest** (crowd event at the town hall; `city_life.gd`).
4. **Leave** (migration out via `migration.gd`; `homes.gd` relocation; `migration.reason = "monsters"`).
5. **Riot / expel** (rare; tension > 0.8 and an incident).
Emigration is also a *status loss*: the settlement's `legitimacy` and `prosperity` fall (`district_values`). Opposite: some households **arrive** (monster-friendly folk, kobold miners seeking a safe home, merchants who see an angle). Net effect is a real design choice, not a punishment.

### 6.2 Mixed districts

`district_values` quarter kinds extend with `monster_quarter` and `mixed_quarter`. Culture mix is already a hidden value; add a **contact** driver: positive contact (trade, shared work, a rescue) lowers prejudice slowly; incidents raise it. Quarter etiquette changes: bows, greetings, who speaks first.

### 6.3 Monster workers

Monsters can be assigned jobs (`businesses.gd`, `enterprise_people.gd`): goblin smith or clerk, kobold miner, ogre porter, orc guard, wolf courier, lizardfolk scribe. They earn wages (or keep rations), generate output, and add **employer status** if productive (+) or **resentment** among displaced human workers (-). Unemployment drives hostility (district value `unemployment` already exists).

### 6.4 Intermarriage tensions

Named monsters of Form 4 with Speech 4 may marry humans (very rare; a late-game civic story). Hidden law: not allowed in Dawn Throne lands; allowed with penalties in Valencios (inheritance disputes); accepted in wild-faith minorities and monster towns. Households react through the same comfort/prejudice model; children (if any) are out of scope in v1 (flagged for a lore review).

### 6.5 Prejudice softens over generations

Per `(culture_tag, species)` store a prejudice float 0..1 in the town record (not per NPC; 2 bytes per pair). Daily drift is toward a target set by **contact**, **incidents**, **faith doctrine**, and a slow **generation term**: every in-game year of positive contact reduces prejudice by 0.01; children raised beside monsters start at `parent_prejudice - 0.15`. An atrocity raises it by 0.2 instantly. This gives a 20-30 year arc across a long game. Church doctrine changes (council rulings) are the slow lever for church kingdoms.

### 6.6 Church kingdoms vs. secular Valencios vs. monster towns

| Axis | Dawn Throne kingdoms | Valencios (secular) | Monster towns |
|---|---|---|---|
| Entry law | Blessing / Ban | Registry / Open | Reserve for humans in their own terms |
| Monster legal status | unclean, soul-binding is heresy | property or labourer; taxable | citizens by oath and power |
| Status effect of company | strongly negative | mild; positive if useful or licensed | positive when named and oath-bound; humans without names rank low |
| Church response | inquisition, cleansing rite, excommunication | tolerated; tithe a concern | wild-faith shamans, ancestor cults |
| Typical NPC bark | "Unclean. Turn back." | "That'll be four marks for the hitching rail." | "Name-bearer. The Elders will hear you." |
| Escalation | bounty on the monster, a crusade | tariff war, guild boycott | raids, alliance, secession |

## 7. Monster towns and politics

- **Seeds in repo**: `goblin_warren`, `orc_village` (`monster_camps.gd`, `world_map.gd`). Plan: convert each from a hostile site into a **polity** (a settlement record in `settlements.gd` with `kind = "monster_town"`), using `founding.gd` for evolution into a real town (houses, forge, shrine, market), `politics_data` for a faction, `diplomacy` for treaties.
- **Governance**: council of named elders (leader Form 3+, Mind 3+, Speech 3+); `follower_will.appoint_governor` handles a human governor; for monsters, `monster_will` picks an elder by `power + oath`.
- **Trade**: monster towns sell ore, hides, charms; buy iron, salt, grain. Valencios merchants open caravans; Dawn Throne bans them (smuggling = infamy).
- **Visiting**: humans entering a monster town pass the **inverse gate** (status in monster terms: name-count, oath, scars, gifts). Without a named companion or sponsor, entry is "tolerated, not welcomed": no shops, prices x2, curfew at dusk. Codex builds gates, banners, name-poles (original design, no copied totems).
- **Politics**: the player can petition for a monster-town **charter** inside a kingdom (`audiences`), turning raiders into allies; the Church may declare a crusade.

## 8. NPC talk: gossip, barks, rumours by status

### 8.1 Line selection

`talk_bark.gd` already picks barks. Add a `StatusBarks` data file `data/world/barks_status.json` with keys `(situation, status_band, culture, species, tone)`. The picker chooses by observer persona (`persona.gd`), their own status vs the subject, and whether they have heard a rumour (`rumours.view`). Never more than one gossip line per NPC per 3 game hours; throttle to 24 NPCs near the player (MW-39 attention budget).

### 8.2 Sample lines (original; ~40 to seed the writer)

Observer lower status to subject:
- "Lord's own hound? Mind your feet." (respect, worry)
- "That thing eats more than my whole house." (fear)
- "They say you spoke it a name. What's it feel like, to be answered?" (curious)
Observer higher status:
- "A named beast. Is it papers it carries, or only a tooth for show?" (testing)
- "Come back with a charter and I'll hear you." (gate)
Church:
- "The Throne counts souls. Yours is on loan to that creature." (sermon)
- "Be cleansed or be elsewhere." (ultimatum)
Valencios:
- "Registry's at the red door. Collar's three marks, tags are free." (neutral)
- "Your goblin did my accounts better than my nephew. Don't tell him." (warm)
Monster town:
- "Name-bearer. The ash-poles know your face." (greeting)
- "A walker with no name walks alone." (low status)
Gossip about the player:
- "The knight with the ogre? He pays for his own broken doors."
- "Heard she named a whole pack. Hair went white that night."
Rumour variants carry error (`reputation._distort`): "named a dragon," "named a demon," "was named by the monster."

### 8.3 Rumour types

1. **Name deeds**: `name_given`, `name_refused`, `name_torn`, `tribe_named`.
2. **Entry events**: `gate_turned_back`, `bribe_found`, `disguise_caught`.
3. **Settlement events**: `petition`, `exodus`, `monster_incident`, `charter_granted`.
4. **Rivals**: `rival_named`, `name_stolen`.
Each uses `news.gd` templates (an `EVENT` row for each), the existing `monster_settled` line stays.

### 8.4 NPCs "do a lot"

Add to `city_life.gd` event pool: a child dares to pet the wolf; a priest follows the party for three streets; a guard quietly lets the goblin in; a baker leaves bread; a mob gathers; a merchant asks your lizardfolk for a ruling; a rival namer taunts you; an old widow asks your ogre to carry her stones. These are scripted scenarios in section 11, driven by status and prejudice, not hand-placed cutscenes.

## 9. Concrete scenarios (36)

Each lists trigger, rules, outcomes.

1. **First goblin name, low reserve.** Tier 3, reserve 60, goblin level 4. Preview: cost 36 embers, risk 22%. Success: Hobgoblin, Form 1, Speech 1. Namer winded. Gate forecast shows Ashford is fine, Caldrenn is not.
2. **Overdrawn at night.** Same cost, reserve 30. Confirm overdraw; roll injury; namer collapses 8 hours outdoors; the goblin guards; a wolf pack is drawn by scent. Loyalty +10 if it holds the line.
3. **Naming a wolf too strong.** Dire wolf r = 1.7: it accepts, the namer's max pool permanently drops 12%; wolf's independence 0.8. Later it hunts alone and returns with prey (a gift) or doesn't.
4. **Refused by an orc captain.** The namer killed its brother. The orc says its own name; debt quest opens ("pay the blood price").
5. **Tribe naming.** A tier 5 namer names a warren leader then 7 goblins with a feast. Warren becomes a vassal camp; the Church of the Dawn Throne hears and sends an observer in 6 days.
6. **A lieutenant defects.** One goblin refuses the rite, leaves with 3 others. Becomes a rival band; later they raid the namer's caravan.
7. **Rival shaman wins the race.** A wild-faith shaman names the ogre first. Player may duel the name (contest) or ally.
8. **Name legend spreads.** Three days after a pack naming, a Valencios caravan driver tells the next town: "a woman who names beasts." Fame +; Church towns: infamy +. A hunter's guild sends a recruiter.
9. **Wild kin petition.** A lone kobold follows the party for two days and asks for a name. If refused, it hangs around the settlement and steals; if granted, becomes a miner.
10. **Evolution dormancy ambush.** Hobgoblin evolves into Goblin Chief over 3 days; hunters from a rival warren raid the den; the player must defend.
11. **Speech milestone.** The named wolf says its first words ("Cold. Rain. Stay."); NPC bark: "That wolf spoke!"; the Church sends a priest to examine.
12. **Orc oath.** The named orc swears an oath at a temple; breaking it costs health; it declines an order to burn a granary (`refuse_moral`).
13. **Dawn Throne gate, no seal.** Status 0.45, orc required 0.6. Options: leave the orc at the gate camp (-1 loyalty/day), pay a church sponsor 80 marks, or go through a cleansing rite (3 days, -3 gold/day, one-time status +0.1).
14. **Valencios gate, registry.** Party of player + goblin clerk. Collar tag 3 marks. Pass. NPC: "Your goblin did my accounts better than my nephew."
15. **Curfew bar.** After dusk, a strict town bars all monsters even with a permit. The party must camp outside; a thief steals from the camp.
16. **Bribe backfires.** The player bribes a guard to let an ogre in. A rival witness reports. Next day the town raises the law level to Ban; the guard is sacked and spreads it.
17. **Disguise success.** A hooded Form 3 lizardfolk passes as a monk-scribe; a priest notices the scales and says nothing (his own sister is married to one).
18. **Disguise failure.** A muzzled Form 2 goblin sneezes; the guard checks the permit; fine + 2 days jail; goblin flees outside.
19. **Sponsor.** A guild factor sponsors your wolf scout; asks you to fetch a stolen ledger (deed). Sponsor leaves you in debt if you fail.
20. **Eloquent argument.** A Speech 4 lizardfolk argues for the party at a Dawn Throne gate using doctrine; success chance 55%; success gives faith standing +0.1.
21. **Left outside, alone.** The ogre waits 5 days; a hunter's party tries to kill it; it kills two and flees; loyalty -20; infamy +.
22. **Charter in your own town.** Your governor issues a companion charter; two allied towns recognise it; gates open without fees.
23. **Residents leave.** After a goblin forge opens in the market quarter, 6 households petition; 3 leave; rent in that quarter drops; kobold miners arrive instead.
24. **Protest.** A crowd forms at the town hall. The governor (human, `follower_will` honourable) listens; the player can concede a muzzle ordinance, bribe the crowd's leader, or send the ogre to calm them (bad idea).
25. **Mixed district.** Over a year of contact, prejudice in the quarter falls from 0.7 to 0.55; children play near the kobold stalls; the priest preaches against it; sermon pushes prejudice to 0.65.
26. **Intermarriage scandal.** A Form 4 orc and a widow wed; her in-laws sue in court; the case reaches the king; ruling sets precedent.
27. **Monster worker conflict.** Ogre porters undercut human porters; the guild strikes; settlement tension up; resolve with quotas or new jobs.
28. **A monster town invites you.** You enter the orc stronghold with a named orc; name-poles line the road; the elders ask you to settle a boundary; humans without names are barred from the forge.
29. **Charter petition.** The player petitions a king to charter the goblin warren as a vassal town; a vote; the Church opposes; result depends on status, fame, and tariffs.
30. **Crusade.** After an incident, the Dawn Throne declares the named orc a heretic servant; bounty on it; the player's status in all Dawn Throne towns -0.15 until a council absolves.
31. **Grief.** The named wolf dies; the namer loses 5 loyalty on every bond and is fatigued; the wolf becomes a legend, barks quote its byname.
32. **Ambition.** A Goblin Chief with greed and power ambition asks for land; refused, it quits and founds a tribe with `founding.gd`; later it trades with you or raids you.
33. **Coup.** An overpowered named ogre (independence 0.9) takes over the garrison while the player is away; resolution: parley, duel, or give it a seat.
34. **Rival buys a name.** A rival warlord pays a priest to cleanse your wolf's name; if loyalty < 40, the wolf serves the warlord.
35. **Soul Name for a person.** The namer True Names a trusted human knight; no evolution of form, but Mind/Ability tracks rise; church towns treat it as sorcery; the knight must choose between lord and church.
36. **Amnesty.** A drought, a plague, and a hero's rescue by the named ogre. The town votes to lift the ban for one season; status +0.1; prejudice -0.08.

## 10. Systems mapping (modules, data, API, budgets)

### 10.1 Existing modules reused

| Need | Module | Status |
|---|---|---|
| Name/Soul Name cost, risk, roster | `scripts/sim/naming.gd` | EXISTS (not wired) |
| Companions in the world | `actors/soulbeast*.gd`, `world/soulbeast_director.gd` | EXISTS (beast-only) |
| Reputation, fame/infamy | `realm/reputation.gd` | PARTIAL (two new axes) |
| Observer reads subject | `realm/social_perception.gd` | PARTIAL (companions flag) |
| Titles, sponsors | `realm/audiences.gd`, `homes.gd`, `campaign.gd` | PARTIAL |
| Contracts | `realm/recruitment.gd` | EXISTS (humans only) |
| Will, ambition, orders | `realm/follower_will.gd` | EXISTS |
| Founding, land law | `realm/founding.gd`, `land_law.gd` | EXISTS |
| Quarters, tension | `realm/district_values.gd` | EXISTS |
| Faith | `realm/faith.gd` | EXISTS (needs `standing`) |
| Laws, curfew | `realm/governance.gd`, `stewardship.gd`, `courts.gd` | PARTIAL |
| Rumours, news, barks | `rumours.gd`, `news.gd`, `population/talk_bark.gd` | EXISTS |
| Monster camps | `world/monster_camps.gd`, `realm/ecology*.gd` | PARTIAL |
| Migration | `realm/migration.gd` | EXISTS |

### 10.2 New modules (MISSING)

- `realm/status.gd` (derived Status, `status(subject, observer)`, `standing_line`). Pure; no save.
- `realm/entry_law.gd` (gate verdict, laws, permits, forecast). Small save: active permits and bribe log (about 80 bytes each, cap 64).
- `realm/monster_will.gd` (independence, ambition, species drives; wraps `follower_will`). Save 8 bytes per bond.
- `realm/prejudice.gd` (culture x species prejudice, contact/incident drivers). Save 2 bytes per pair per town (about 64 towns x 12 species = 1.5 KB).
- `sim/bond_growth.gd` (form/mind/speech/ability tracks, dormancy, byname). Stored on the naming record.
- Data: `data/world/status_weights.json`, `culture_attitudes.json`, `entry_laws.json`, `barks_status.json`, `species_tracks.json`, `monster_names_lore.json` (name pools/bynames; original).

### 10.3 API sketch

```
Status.of(subject_id, observer_key, ctx := {}) -> {value, band, parts, company, lines}
Status.forecast(subject, towns: Array, party) -> Array of {sid, verdict, cost}
EntryLaw.check(party, sid, hour, ctx) -> {verdict, terms, options, bribe_price, lines}
EntryLaw.apply_option(party, sid, option_id) -> {ok, result}
RANaming.name_monster_v2(namer, target, opts) -> {ok, text, bond_id, tracks, damage}
BondGrowth.tick_day(day) -> events
MonsterWill.respond(bond_id, order, situation) -> {action, line}
Prejudice.of(sid, culture, species) / .tick_day(day)
Reputation axes added: "fame", "infamy"  (the 9-axis constant becomes 11; test_reputation must be updated)
```

### 10.4 Perf and save budgets

- All new logic is **on demand or day-tick**, never per frame. Gate checks run once per arrival. Status is computed lazily and cached per `(subject, observer, day)`; cache size 64 entries.
- Day tick: `Prejudice.tick_day` 64 towns x 12 species = 768 float updates = about 0.05 ms; `BondGrowth.tick_day` <= 16 bonds; `MonsterWill` <= 16 bonds, each `respond` only when an order or event arrives. Total added: under 0.2 ms/day-tick, under the 0.6 ms pump budget.
- Bark picker: O(30) rows filter; 24 NPCs per frame budget stays.
- Save: bonds 2.2 KB, permits and bribe log 5 KB, prejudice 1.5 KB, new reputation axes 2 bytes x existing keys (already evicted via `_evict`), roughly +12 KB total; the save budget is 2.5 MB raw (schema 4). Bump schema to 5 with a migration that defaults missing fields.
- 16 MB-class memory: barks and law JSON under 200 KB.
- Bodies: max 4 active named monsters as full bodies; tribe members are WorldSim rows with nameplates only.

### 10.5 Ownership

- **cloud (systems)**: `naming.gd` wiring, `status.gd`, `entry_law.gd`, `monster_will.gd`, `prejudice.gd`, `bond_growth.gd`, reputation axes, rumours and news templates, tests, saves, MN-14 deny-list scan.
- **Antigravity (all animation)**: evolution/dormancy morph clips, speech visemes and emote set per species, gate reactions (guard waves off, spits, salutes), crowd protest loops, monster work loops (hammering, hauling), disguised posture, mourning pose.
- **Codex (world)**: monster districts (`monster_quarter` kit, den/stable/name-pole props), gate posts and hitching camps, monster-town layouts (goblin warren and orc village into real settlements), signage, banners, placement in `monster_camps.gd`. World-lint pass required.

## 11. Work packages

Each package lists scope, files, tests, owner. All tests are gdUnit4 in `kingdom/tests/`.

- **MN-0 Naming hygiene and wiring audit** (cloud). Replace player-visible "magicules" with "soul reserve/ember"; re-write the slime hint; add `data/world/lore_denylist.json`. Tests: `test_lore_denylist.gd` scans text data and fails on any listed proper noun; `test_soul_naming.gd` still passes.
- **MN-1 Wire naming into Life** (cloud). Implement the integration header of `naming.gd`; "Name this creature" interaction on tamed/defeated monsters; preview shows cost, risk, forecast. Tests: preview equals actual cost within rounding; roster serialize round trip; level loss expires.
- **MN-2 Bond tracks and growth** (cloud, with Antigravity assets). `bond_growth.gd`: form/mind/speech/ability, caps by tier/species, depth thresholds, dormancy. Tests: caps respected; True Name unlocks 3-4; dormancy blocks commands; determinism across two runs.
- **MN-3 Risk and exhaustion rework** (cloud). Tiered exhaustion, hollowing, refusal outcomes, name-torn contest. Tests: r thresholds; hollowing floor 25%; refused cooldown 7 days; overdraw collapse duration.
- **MN-4 Monster will** (cloud). `monster_will.gd` on top of `follower_will`: independence, ambition, species drives, coup and founding paths. Tests: honourable orc refuses burn order; goblin with greed leaves when denied land; wolf rarely rolls agendas.
- **MN-5 Group naming and tribes** (cloud + Codex). Rite of the Many; `monster_camps.gd` vassal flip; rebel lieutenant. Tests: cost scaling; tribe size cap; vassal camp does not attack the namer; defector spawns rival.
- **MN-6 Status model** (cloud). `status.gd`, `status_weights.json`, `faith.standing`, `fame/infamy` axes, `culture_attitudes.json`, social_perception companions flag. Tests: monotonic in each component; company clamp +/-0.25; Dawn Throne vs Valencios differ for the same orc.
- **MN-7 Entry law and gates** (cloud for logic, Codex for gate posts). `entry_law.gd`, laws, permits, bribes, sponsors, disguises, curfew. Tests: each verdict path; bribe price scales with corruption; forged permit failure; curfew bars monsters.
- **MN-8 Settlement reactions** (cloud). Comfort, petitions, protests, emigration with reason "monsters"; arrival of monster-friendly households; district value changes. Tests: threshold produces petition then departures within N weeks; deterministic; `migration` receives rows.
- **MN-9 Prejudice and generations** (cloud). `prejudice.gd`, contact and incident drivers, generation term. Tests: 1 year positive contact reduces by 0.01; atrocity +0.2; children offset.
- **MN-10 Monster towns and charters** (cloud + Codex). Convert goblin warren and orc village to polities; inverse gate; charter petition via `audiences`. Tests: visiting rules; charter vote outcomes.
- **MN-11 NPC talk** (cloud + writer). `barks_status.json` (>= 120 lines), selection by status/culture/species, rumour templates in `news.gd`. Tests: no line repeats within 3 game hours per NPC; band selection; every status band has >= 5 lines.
- **MN-12 Legends and rivals** (cloud). Name stories in rumours, bynames, wild-kin petitions, rival namers (race, steal, poison). Tests: rumour distortion; contest roll fairness; stolen-beast preconditions.
- **MN-13 Animation set** (Antigravity). Evolution morph, dormancy, speech/emote per species, gate reactions, protest crowd, work loops. Done when `ashes-video-review` contact sheets show no pops, and clips load from the AnimationLibrary names listed in `species_tracks.json`.
- **MN-14 Acceptance sims and budgets** (cloud). 30-day headless soak with 10 bonds and 12 towns: tick < 0.2 ms, save delta < 15 KB, no RNG drift; scenario tests for scenarios 1, 5, 13, 23, 30, 33. Save schema 5 migration test.

Order: MN-0, MN-1, MN-6, MN-7, MN-2, MN-3, MN-4, MN-8, MN-9, MN-5, MN-11, MN-12, MN-10, MN-13, MN-14.

## 12. Balance targets

- A first naming at Tier 3 costs 30-50% of the reserve; overdrawing is a choice, never an accident.
- A Valencios gate admits a status 0.35 party with a named goblin for a fee; a Dawn Throne gate does not admit a named orc below 0.6 without a seal or sponsor.
- 90% of settlement departures come after a visible incident or sustained exposure above threshold, not from a single named monster alone.
- A playthrough with no monster companions loses nothing in status; companions are an optional power with a social price.

## 13. Open questions for the owner

1. Is undead naming permanently forbidden or a late-game forbidden art?
2. Is intermarriage in scope for v1 or a story-only event?
3. Should monsters be able to vote in a charter council?
4. Does dragonkin appear as a recruitable creature or only as a Form 4 branch?

## 14. New names list for lore review

calling-name, soul-name, ember (unit), Rite of the Many, kin-name, name-pole, hollowing, torn name, Companion Charter, gate-camp, Drakeblood Elder (already in naming.gd as Drakeblood), bynames to be authored. All checked for no overlap with the inspiration; MN-0 test enforces a deny-list.

## 15. Implemented (cloud), 2026-10-21

Order done: MN-0, MN-1, MN-6, MN-7, MN-2, MN-3, MN-4 (compact), MN-8, MN-9, MN-5, MN-11 (partial). Not done: MN-10 (monster towns, charters, inverse gate), MN-12 (legends beyond the name story and byname, rival namers race/steal/poison, wild-kin petitions), MN-13 (animation, Antigravity), MN-14 (30 day soak, schema 5 bump). Barks: 76 lines, not the 120 asked for (every status band has at least 10; a writer pass is still needed).

**Files.** Data in `kingdom/data/world/`: `lore_denylist.json`, `mn_flags.json`, `species_tracks.json`, `status_weights.json`, `culture_attitudes.json`, `entry_laws.json`, `barks_status.json`. Code in `kingdom/scripts/realm/`: `mn_data.gd` (cached tables and flags), `status.gd` (pure), `entry_law.gd` (pure), `monster_bonds.gd` (realm module `monster_bonds`), `monster_society.gd` (realm module `monster_society`), `monster_barks.gd`; plus `scripts/sim/lore_terms.gd`. Both modules are registered at the end of `realm_hub.gd` ORDER. Tests: `tests/test_mn_lore.gd`, `test_mn_naming.gd`, `test_mn_status.gd`, `test_mn_society.gd`.

**MN-0.** All player-visible "magicules" strings are now "soul reserve" / "ember" (pool messages, naming costs, item descriptions, technique wheel cost, injury name "Ember Burn", village services). Internal identifiers and save keys (`RAMagicules`, the `"magicules"` resource key, `magicule_regen`) are unchanged; `lore_terms.gd` maps new aliases (`soul_reserve`, `embers`, `ember_regen`...) to them. Slime hint is now "filter water and mend rot". A series character name in `monster.gd` NAMES and a test wolf name were renamed. `test_mn_lore` scans every JSON string value and every script string literal for the deny-list.

**Owner questions as data flags** (`mn_flags.json`, read through `MNData.flag`): `undead_naming_forbidden` true (undead species row has `forbidden`, gate bars undead), `intermarriage` "story_only" (no code path), `monsters_can_vote` false, `dragonkin_mode` "late_lizardfolk_form" with `dragonkin_recruitable` false.

**Naming (MN-1..3).** `Life.name_monster` now calls `monster_bonds.name_creature`, which wraps `RANaming` and adds: ratio r = power x level / capacity (r > 2.5 refused outright, 1.5 < r <= 2.5 hollows the max pool by (r-1.5) x 0.6, floored at 25% of the peak, independence 0.8), refused names (pride, grudge, bound elsewhere, level >= namer; 7 day cooldown; outcomes refused / backlash at half cost plus Soul Fatigue / the creature names the namer back as a debt), exhaustion tiers (none, winded, fatigue, overdrawn with a 6..24 hour collapse), and the bond record (form/mind/speech/ability 0..4, species ceilings, depth thresholds 30/55/80, three day dormancy that blocks commands, byname after 3 deeds). `Life._new_life` lends `Life.naming` to the module so there is one ledger. Tribe rite: `tribe_name` (cost 0.7 per kin, at least 1.4x single, at most 3 + 2 x tier kin, loyalty 55 without a feast, vassal camp that does not attack its master, a lieutenant may defect and found a rival band). Recruiting: `recruit_follower(bond)` makes a named monster a follower row (flags `monster`, `bond`; traits from species ethos), `hire_monster` is the contract path (speech >= 2, a den, a wage). `respond` and `consider_leaving` give the compact monster will (oath species refuse moral orders; greedy independent goblins leave when denied land).

**Status and gates (MN-6/7).** `Status.of(subject, observer)` follows section 3.1 with weights from data; title honour is scaled by `SocialPerception.legitimacy`; company is per culture, clamped at +/-0.25, with church seal and guild sponsor modifiers; faith standing drops 0.2 per named monster in unclean-doctrine culture. Culture names map to the repo's tags: caldric = the secular runestone culture the design calls Valencios, solenne = Dawn Throne church kingdoms. Fame and infamy live in `monster_society` (not as reputation axes, so `test_reputation` is untouched); a name story is believed at once locally and by each culture NEWS_DELAY days later. `EntryLaw.check` gives verdict, terms, fee, options (leave outside, bribe, sponsor, permit, cleansing rite, disguise, talk); `apply_option` rolls deterministically; `forecast` writes the plain-words line. Forged permits fail about 55% of the time with arrest; disguises use `SocialPerception.identity`; strict-curfew cultures bar monsters after the bell even with permits.

**Settlement and talk (MN-8/9/11).** `monster_society.weekly_reaction` runs household comfort (1 - prejudice x exposure) through complain, petition, protest, leave (queued in `take_departures`, reason "monsters", news posted) and riot (tension > 0.8 and an incident); friendly households can arrive. It runs from `tick_week` for bonds stationed in a settlement. Prejudice: per (settlement, culture, species), baseline from the culture attitude, -0.01 per year of daily positive contact, +0.2 per atrocity, `child_prejudice` = parent - 0.15, `doctrine_shift` as the slow lever. `gossip` picks a line by status band, culture and species, at most one per NPC per 3 game hours and 24 per hour.

**Not wired (for follow-up).** `migration.gd` does not yet read `take_departures()` (another agent owns it); `homes.gd` has no `monster_lodging` rent or landlord refusal; `district_values.gd` has no `monster_quarter` kind; `news.gd` has no templates for `name_given`, `gate_turned_back`, `bribe_found`, `disguise_caught`, `exodus` (the module posts plain text; `petition` already exists); `village_services` still shows the old naming menu text and does not call the gate forecast; the `_do_soul_name_monster` menu path still performs the ritual and then a Lesser naming (pre-existing). No UI for status standing lines yet.
