# Aura Release: presence, dread and the town that clears the street (AR-1 to AR-16)

Status: design, 2026-10-21. Godot 4.6.2, PC-first. Read-only audit of the repo plus new design; no git and no Godot were run. "EXISTS" means the module is there and covers the rule in kind, not at this feature's scale. Builds on `LIVING_WORLD_MASTER_PLAN.md` (MW-5 SocialPerception, MW-37..41 Presence, MW-12..14 follower will) and `NPC_INTELLIGENCE_MAP.md` (NI-2 persona, NI-4 psyche memory). It adds no framework: one new player-side state machine (`AuraState`), one new realm service (`aura_fallout.gd`), and data tables. Everything else is a new input to modules that already exist.

**Owners.** cloud = systems, CPU, save, tests. Antigravity = ALL animation (fleeing, kneeling, fainting, child-carrying, hiding). Codex = world (shutters, empty-market dressing, aura VFX, omen props). Local PC = HUD and GPU tuning.

---

## 0. The idea in one paragraph

Power is something you wear on your skin. A strong cultivator does not walk through a town like a farmer. If you do something big in a kingdom (burn a gatehouse, slaughter a patrol, break a siege, level a street), the town does not forget, and the next time anyone actually sees you they start to hide. There is a button (default: hold `Q`) that releases your aura. The longer you hold it the more you leak. Weak people feel unease, then fear, then panic, then their legs stop working. People clear the street, parents grab their children, merchants drop their stalls, and the guards show up. An officer walks up and asks what you think you are doing. You choose: suppress it, talk, intimidate, pay, surrender, run, or fight. Every choice leaves marks in district values, courts, reputation, followers, war intel, settlement morale and, eventually, legend.

The feature is a **consequence amplifier**, not a free "win" button. Its pleasure comes from three loops:

1. Being *dreaded* is powerful and expensive (you cannot shop, rest, recruit or heal in a town that runs from you).
2. Being *controlled* is a skill (a master can walk a market and nobody looks twice).
3. Being *seen using it well* (ending a riot, scaring bandits, protecting a village) earns a different legend than being seen using it badly.

---

## 1. Core mechanic

### 1.1 Inputs and states

| Input | Action |
|---|---|
| Hold `Q` | Release: leak rises while held |
| Release `Q` | Release ends; leak decays through the **echo** (1.3) |
| Tap `Q` while Released | Surge: a one-second spike (duels of aura, 9.5) |
| Hold `Q` + `Ctrl` | Directed release (a 60 degree cone toward the look direction; costs +25 percent) |
| Tap `Z` | Rein in: raise suppression for 10 s (costs Focus, 1.5) |

State machine (`AuraState`, pure data, on the player; NPC bosses reuse it):

`SEALED -> LEAKING -> RELEASED -> SURGING -> ECHO -> SEALED`, plus `STRAINED` (exhausted) and `SLIPPED` (accidental leak, 1.6).

### 1.2 Hold-to-leak curve

`aura_emit` is the existing 0..1 key that `SocialPerception.magic_pressure` reads. It becomes the output of this curve and is never a stored stat.

Let `P` be the player's **power rating** 0..1 (2.1), `h` the seconds the button has been held, `S` the current suppression 0..1 (1.4).

```
leak(h)       = 1 - exp(-(h / T_rise))                 # T_rise = 4.0 s
raw_emit      = P * leak(h)^0.8
aura_emit     = clamp(raw_emit - S * (1 - leak(h)) * 0.5, 0, 1)
aura_suppress = S    (what SocialPerception already subtracts)
```

Design intent:

* **0 to 1 s**: a thin tell. Candle flames lean, a dog looks up. Nobody faints. A polite-warning window; tapping and releasing inside it is cheap and deniable.
* **1 to 4 s**: the climb. About 63 percent of power at 4 s, 86 percent at 8 s. Most gameplay lives here.
* **4 to 10 s**: saturation. Diminishing returns on emit, rising cost.
* **Past 10 s**: STRAINED (1.5). You can keep holding but control cost doubles and the leak gets ragged (NPCs read it as instability: more frightening, less targeted).

Radius is separate from strength. Strength falls with distance; reach is where the felt value drops below the observer threshold 0.12.

```
reach_m    = 6 + 70 * raw_emit^1.3                     # 6 m at a whisper, ~76 m at full release
felt(o, d) = aura_emit * (1 - d / reach_m)^1.5 * sens(o) * wall_factor
wall_factor= 1.0 open air, 0.7 timber wall, 0.45 stone, 0.25 behind a shuttered door
```

Walls matter: the feeling goes through a door but muffled, so a hiding family still feels you on the road. Ward items and sanctified stone (`faith.gd`) multiply `wall_factor` by 0.5.

### 1.3 Echo (decay and linger)

Releasing the button does not end the effect.

```
echo(t) = aura_emit_at_release * exp(-t / 6 s)         # 6 s half-life of the felt field
```

A short burst frightens the next three people who walk past too. Observers keep fear they already acquired by their own psyche decay (`psyche.gd` `fear`), which is the lasting damage: a mother who fainted stays shaken for a day.

### 1.4 Suppression and control skill

`S` comes from a new **Aura Control** skill (`sim/skills.gd`, 0..100) and the path:

| Source | Contribution to S |
|---|---|
| Control skill / 100 | 0 to 0.55 |
| Path discipline (sect meridian mastery, magic chantless gate met, knight reinforcement conditioning, bending breath rhythm, beast bond) | 0 to 0.25 |
| Calm state (psyche stress and anger both < 0.3) | +0.10 |
| Worn mantle (sealing cloak, damping pendant, monk's grey robe) | +0.05 to +0.25 |
| Sanctified ground / ward stone | +0.10 forced, muted for everyone |
| Emotional load (stress, anger, grief, fear) | minus up to 0.35 |

Skill rises by use under pressure: holding S while a guard talks to you; walking a crowded market at full control for an hour; sparring with a teacher who probes you (rival probing, 7). Theory (`power_paths.gd` `study_theory`) lifts the cap, not the current value.

Passive baseline (button not held): `aura_emit = P * (1 - S)^3 * 0.05`. A weak mage leaks nothing visible. A strong, untrained one leaks a discomfort even asleep.

### 1.5 Exhaustion and cooldown

Release spends a new **Focus** pool `aura_focus` (0..100, regen 1.2 per minute out of combat, 3.0 per minute meditating):

```
cost_s = 1.5 + 6 * raw_emit^2     (+25% directed, x2 past 10 s)
```

At 0 Focus: STRAINED. The release cuts out in a ragged stutter, S drops by 0.3, stress rises, and the existing `power_paths.gd` exhaustion risks fire (headaches, trembling, instability for magic; channel strain for sect; reinforcement drop for knights).

Cooldown: after a Released state longer than 6 s, a 20 s **settling** window raises passive leak by 0.1 (you are loud for a bit). Repeated releases inside 2 minutes stack "afterglow" (+0.05 baseline each, max 5) that decays over an hour.

### 1.6 Accidental leaks (emotion)

Control is lost under load. Each second `slip_chance = base * stress_load * (1 - S)`, where `stress_load` blends psyche `anger`, `fear`, `grief` and a low-health factor.

| Trigger | Result |
|---|---|
| Anger above 0.7 and S below 0.5 | SLIPPED: aura rises to `0.4 * P` for 3 s; `Z` can rein it in |
| A loved one wounded in sight | SLIPPED, no rein for 2 s |
| Nightmare (psyche memory weight above 120) | Neighbours in the inn feel it; whispers |
| Death of a follower | Grief surge: involuntary RELEASED for 5 s, scaled by bond |
| Breakthrough (`soul.gd` `attempt_breakthrough` success) | Unavoidable surge for 8 s, radius to 150 m. Towns remember this for years |
| Drunk or poisoned | S minus 0.2, slip chance times 3 |
| Starving, exhausted | S minus 0.1 |
| Sealing item broken | S minus the item's bonus |

Each SLIPPED event writes a psyche memory for every observer who felt it (weight scaled by `felt`), exactly as crimes do. A slip in a church is worse than the same slip on a road.

---

## 2. Strength versus sensitivity

### 2.1 Player power rating `P`

`P` is a read-only composite 0..1, derived, not stored:

* Soul tier (`sim/soul.gd` `tier()`, 12 tiers `ember` to `worldsoul`) as the backbone.
* Path level (`power_paths.gd` `level(path)`, up to `MAX_LEVEL = 30`) as a modifier (+0.0 to 0.1).
* Cultivation realm / aura layers for sects (`realm/cultivation.gd`, nine layers already drawn in `tab_cultivation.gd`).
* Gear and relics tagged "aura".
* A momentary term for the technique just cast (a big spell flares `aura_emit` regardless of the button, like `Stim.PUBLIC_MAGIC` today).

| Soul tier | ids | P | Practical effect |
|---|---|---|---|
| 1-2 | ember, kindled | 0.00 to 0.04 | Nothing. Dogs may glance |
| 3-4 | warmed, tempered | 0.05 to 0.15 | Sensitives, animals, children feel unease |
| 5-6 | forged, burning | 0.20 to 0.35 | Ordinary adults feel dread on release |
| 7-8 | blazing, roaring | 0.45 to 0.60 | Panic in crowds, guards waver |
| 9-10 | unbound, ascendant | 0.70 to 0.85 | Collapse in the weak, animals bolt |
| 11-12 | transcendent, worldsoul | 0.90 to 1.00 | Physical effects (4); settlements react as to a disaster |

Numbers are placeholders for `data/aura/aura_curve.json` (AR-1). P is flat below tier 3, so early play is never penalised.

### 2.2 Observer sensitivity `sens(o)`

`magic_pressure` already multiplies by `magic_sense` and adds an error term for low intelligence and high stress. AR extends the observer record:

```
sens(o) = magic_sense * K_species * K_state * K_faith * K_training * (1 + age_term)
```

| Factor | Range | Notes |
|---|---|---|
| `magic_sense` | 0..1 | Innate. Mages, seers, beastkin, old crones high; most villagers 0.1 |
| `K_species` | 0.2 to 2.5 | Dogs 1.6, horses 1.8, cats 2.0, birds 1.4, cattle 1.0, insects 0.2, undead 0.0, soul beasts 0.6 (own aura, `soulbeast_aura.gd`), spirits 2.5 |
| `K_state` | 0.6 to 1.5 | Asleep 0.7, drunk 0.8, panicked 1.3, ill or starving 1.5, praying 1.1 |
| `K_faith` | 0.6 to 1.4 | Believers read aura as divine or demonic (6) |
| `K_training` | 0.3 to 1.0 | Soldiers 0.5, mind-disciplined monks 0.3, spell-warded officers 0.4 |
| `age_term` | -0.2 to +0.3 | Infants -0.2 (they cry before they understand), the very old +0.3 |

Persona enters through the same line `bump_reaction` uses: `fear = felt * (1.2 - courage)`. A brave officer feels the same pressure and acts on it differently. Children under 6 behave as courage 0.9 (5.9, 7).

### 2.3 Perception tiers

One scalar `fear_felt = felt * (1.2 - courage)` per observer maps to tiers. Each tier is a set of reaction requests (`reaction_request.gd`).

| Tier | `fear_felt` | Name | Requests | What it looks like |
|---|---|---|---|---|
| T0 | < 0.12 | Nothing | none | Business as usual |
| T1 | 0.12 to 0.30 | Unease | GLANCE, LOOK_AWAY | Talk drops; hands to charms; dogs whine |
| T2 | 0.30 to 0.55 | Fear | STEP_BACK, FLINCH, BOW (pious), WARN | Crowds part; eyes down; mutters of "witch", "lord", "bless us" |
| T3 | 0.55 to 0.80 | Panic | FLEE (exclusive), CALL_GUARD | Dropping goods, running, carrying children, leaving the district |
| T4 | 0.80 to 1.00 | Collapse | new COLLAPSE (AR-5) | Knees give, vomiting, fainting; the weak cannot flee |
| T5 | > 1.0 (P >= 0.9 or surge) | Overwhelm | new COLLAPSE_HARD + physical effects | Unconscious for minutes, nosebleeds; bounded (3) |

T4 needs `felt` over 0.8, which an ordinary untrained person reaches only from `P` of about 0.5 within 10 m. A tier-5 cultivator can drop a market; a tier-3 cannot, so low levels cannot grief.

---

## 3. Lore-safe limits (hard rules)

1. **No mind control.** Aura changes feelings and bodies, never intentions. A frightened person flees, freezes, kneels, faints, pleads or lashes out. They never obey a command, reveal secrets, fall in love or change allegiance because of aura. The only "obedience" is the voluntary fear-driven kind in a parley, a choice that is remembered with resentment (psyche anger and fear, reputation `cruelty`).
2. **Aura never kills a healthy person.** The only medical edge is the already-dying or the extremely frail (a crisis scene, never a weapon). Tiny animals can die of shock only at T5.
3. **Aura cannot see through disguise.** It reveals that something is wrong, not who you are. Identity still comes from `SocialPerception` (`exposed`, `expose_chance`).
4. **Immune and resistant classes exist.** Undead, constructs, soul-bound beings, other high-tier cultivators, certain relics and mind-disciplined people feel less. A duel is a contest (9.5).
5. **Aura is not an attack.** It does no damage to HP or armour. Veterans (`K_training` 0.5) hold a shield wall at T2/T3 and only break at T4. Abuse is punished through fame, not hit points.
6. **Determinism.** Every roll is `hash([WorldSim.SEED, "aura", day, id])`, no `randf`.
7. **The world bends only in documented ways** (4).

---

## 4. Extreme power: physical effects

Only at `aura_emit` >= 0.7 (tier 9 and up, or a breakthrough surge) unless the table says otherwise. All effects are bounded, brief and mostly cosmetic.

| Target | Effect | Threshold | Notes |
|---|---|---|---|
| Weak beings (infants, frail, sick) | Fainting, shallow breath, vomiting | felt >= 0.8 | Recover in minutes; a healer scene may follow |
| Ordinary adults | Shaking, tears, knees give | felt >= 0.8 | Cannot flee at T4 unless carried |
| Livestock | Bolt, break tethers, stampede, milk dries a day | felt >= 0.45 | Carts overturn: a real hazard |
| Dogs, horses | Whine, bolt, refuse to approach | felt >= 0.30 | Your own mount may refuse (bond check) |
| Birds | Fall silent and leave | felt >= 0.30 | The dawn chorus goes quiet |
| Insects, rodents | Swarm away | felt >= 0.20 | Rats leave the granary the day you pass |
| Plants | Wilt, flowers close, grass lies flat in a ring | emit >= 0.7 | Recovers in 2 to 5 days; permanent only on a marked legend site |
| Water, wine | Concentric ripples, shivering cups | emit >= 0.5 | Cheap VFX |
| Flame | Candles gutter, lanterns blow out, forge dims | emit >= 0.6 | Guard lanterns (`guard_lantern.gd`) drop out around you: dark streets |
| Glass, pottery | Hairline cracks, ringing | emit >= 0.85 | Vendors bill the player (10) |
| Magic items | Wards flicker, charms burn out, cursed relics respond | emit >= 0.7 | Weak wards fail; strong ones resist |
| Soul beasts | Cower, submit or challenge by tier delta | tier compare | Uses `soulbeast_aura.gd` (`WARY` aggro multiplier) |
| Weather omens | Wind drops, stillness, clouds gather, one clear thunderclap | emit >= 0.9 | Cosmetic; towns read them as omens |
| Bells, tiles | Dust lifts, an untouched bell tolls once | emit >= 0.9 | Church folklore: a sign |
| Daylight | Dusk darkens one step for 8 s | breakthrough only | Then fades |

Gameplay stats change only for: livestock stampede (collision hazard), candle and lantern outage (night logic in `town_mood.gd`), and ward failure.

---

## 5. Fame, infamy and being recognised

### 5.1 Recognition comes first

The aura makes people afraid of a power. Recognition makes them afraid of you. "If you do something big in a kingdom or city, you won't be able to walk around" is **infamy memory** at district level, not an aura state. It works with the button released.

### 5.2 Notoriety record

`reputation.gd` already tracks `trust, reliability, generosity, cruelty`. AR adds two axes:

* `dread` 0..100: fear tied to the player here. Half-life 90 days (240 if legendary).
* `awe` 0..100: respect and reverence. Decays slower than dread when anchored by a shrine or story.

Both use `reputation.record(subject, axis, delta, sid, channel)` so they travel by witness, rumour, news and road.

| Deed | dread | awe |
|---|---|---|
| Technique killing 5+ in a street | +35 | -5 |
| Destroying a landmark (gatehouse, mill) | +25 | -10 |
| Defeating a monster that threatened the town | +5 | +30 |
| Surviving an execution attempt | +10 | +15 |
| Sparing a begging enemy | -5 | +15 |
| Assassinating a noble or officer | +30 | -15 |
| Defeating a bandit camp, freeing captives | +5 | +25 |
| Breaking a siege | +40 | +10 |
| Witnessed breakthrough surge | +15 | +20 |

### 5.3 Recognition roll

```
P(recognise) = clamp(local_axis/100*0.6 + gear_signature*0.2 + face_seen_before*0.2 + hearsay_age_factor, 0, 1)
```

Disguise rules from `SocialPerception` apply: a hooded stranger is not recognised until face, gear or unusual aura is seen. Recognition triggers the **infamy cascade** (no button needed):

1. `dread >= 30`: staring, whispering, mothers draw children close (T1/T2 behaviour).
2. `dread >= 50`: shutters close as you walk; streets thin ahead; a few merchants stay.
3. `dread >= 70`: **market empties**, stalls covered or abandoned, prices change (5.4), gates may be shut.
4. `dread >= 85`: curfew, requests to leave, officers seek you out, bounty posters.

When `awe` exceeds `dread` by 20, the cascade flips: people come out, children follow, devotees kneel, vendors give a "blessing price".

### 5.4 Economy side effects

* **Shutters.** `town_mood.gd` closes shutters on a night clock; AR adds a dread override closing shutters in a rolling radius with about 20 s delay per house.
* **Market emptiness.** `district_values.gd` `prosperity`, `safety`, `tension`, `price_mult(sid, q)`: a `dread_shock` nudges prosperity down daily, raises unemployment, and raises `price_mult` 5 to 40 percent for merchants who stay (risk premium).
* **Refusal.** At `dread >= 70` non-devotee vendors set `vendor_refuses`; shopping moves to fences and monasteries (a fallback must exist in every town, 15).
* **Protection money.** Local brokers may offer a "protection" channel: pay and the street opens (feeds `courts.district_corruption`).
* **Rumours by road.** `news.gd` `post(kind, sid, text, mag)` delays by road distance and `rumours.gd` garbles. A far town that has never seen you already fears "the one who burned Greywater".
* **Inherited fear.** Victims' kin carry long psyche memory (half-life 180 days).

---

## 6. Cultural differences

| Culture | Reads aura as | Typical response | Special |
|---|---|---|---|
| **Valencios (secular)** | A dangerous power, a crime waiting | Calls the watch; wants a licence; mage guild asks to register you | Officers have high `K_training` |
| **Eastern church kingdoms** | Holy or demonic by how it looks: warm, gold, still = blessed; black, cold, shaking = abomination | Devotees kneel; fanatics denounce; inquisitors at dread 70 | A kindly daytime release over a sick child earns awe |
| **Monster towns (beastfolk, soulbeast settlements)** | A language: greeting, test, courtesy | Elders approach to measure you; hiding yours is rude | Release expected at the gate; guards do not call it a crime |
| **Cultivation sects** | A rank, polite to compare | Disciples bow to higher; elders probe | Releasing inside the sanctum is an insult with sect-law penalties |
| **Frontier and refugee camps** | Trouble, or protection | Beg you to stay as a wall; fear the army you draw | Depends on prior experience |
| **Nobles and courts** | A bargaining chip or a threat to the throne | Invitations, summons, gifts, or a quiet knife | `legitimacy` triple (MW-6) |
| **Guilds and merchants** | A risk to profit | Insurance, closed shops, compensation demands | Fallout bill (10) |

"Holy" is judged from the aura's **visual signature** (colour, motion, source), through `K_faith`. Codex provides at least five signatures (warm still gold, cold white, dark swirl, red flicker, living green). Players learn their release has a character set by path and mood.

---

## 7. Crowd behaviour

Roles sit on top of the near-tier population (`npc_world.gd`, `utility_brain.gd`, `presence.gd`). An NPC gets a role when `fear_felt` crosses T1.

| Role | Trigger | Behaviour | Notes |
|---|---|---|---|
| **Clearer** | T2+, adult, no dependents | Step aside, walk away, shut door | Default |
| **Parent** | Dependent child within 10 m, T2+ | Scoops the child, moves into a doorway or alley, covers the child's eyes; a second parent goes back for a missing child | Child-carry animation (Antigravity); a missing child is a micro-event |
| **Elder** | Age 65+ | Slow, freezes, leans on a wall, mutters a prayer; may faint; helpers take their arm | Slow movers cause blockage |
| **Beggar** | Dread present | Some flee, some kneel and ask a blessing, some mock to prove nerve | A coin gives awe, a kick gives dread |
| **Merchant** | Stall owner, T2+ | Throws cloth over goods, locks the cash box, abandons the stall or stays and bargains (courage and greed high) | Unattended stalls enable looting |
| **Looter** | Chaos index high | Slips into gaps; may try it near you at greed and courage 0.8 | Recorded by `crime_watch` and `on_crime` |
| **Devotee** | `pious` > 0.6, church culture, "holy" read | Kneels, signs the holy sign, weeps, follows at a distance | Becomes a procession if you also heal |
| **Fanatic** | Pious and afraid, "demonic" read or inquisitor near | Accuses, points, runs to a priest, chants, throws a stone at most | Leads to a faith inquiry later |
| **Rival mage** | High `magic_sense`, magic user | Probes back with a counter-pulse; may shield the crowd | Duel (9.5) |
| **Child** | Age < 7 | Many are not afraid: stare, follow, ask "are you a wizard?"; some cry | Parents terrified of the child going to you |
| **Guard** | On duty | Calls in, forms a ring at distance, blows a horn | 8 |
| **Drunk** | Tavern night | Does not understand; wanders into you or challenges | Comic and risky |
| **Healer, priest** | Healer profession or faith | Moves toward the collapsed, tends them, shames the player | Followers react (10) |
| **Gawker** | Low sensitivity, high curiosity | Watches from a window; sells the story after | Rumour source |

Rules:

* **Clearing a street** is a soft repulsion field in `StreetGraph` (`population/street_graph.gd`): edges ahead of the player within `reach_m * 0.5` gain cost proportional to fear, so crowds flow around you instead of teleporting.
* **Fleeing the area** is a goal, not a flinch: at T3 NPCs pick a refuge (own door, temple, alley, gate) then a longer retreat (kin across town). `FLEE` is already exclusive (`EXCLUSIVE_KIND`, 6 s); AR chains FLEE bursts toward a refuge target.
* **Taking their kids**: the parent's carry attaches the child body for the duration; no physics.
* **Body cap**: `MAX_BODIES = 48` near bodies run roles. Beyond that a district tracker in `district_values` models "70 percent of the quarter indoors".
* **Chaos index**: `chaos = abandoned_stalls*0.1 + unguarded*0.2 + collapsed*0.1 - guards_near*0.3`. Above 0.6 looters activate; guards arriving lower it.
* **Stampede**: bolting animals and wagons are collision hazards; an overturned cart blocks a street and the player is blamed.

---

## 8. Escalation ladder and options

A visible release, kills or recognised infamy start a response clock in `alert_net.gd` (levels to `MAX_LEVEL = 3`, `LOCKDOWN_LEVEL = 2`) and `crime_watch.gd`. AR adds an **aura incident** type with severity from `fear_peak`, number of T3+ observers and any harm.

### 8.1 Ladder

| Step | Trigger | Who arrives | Time | Player options |
|---|---|---|---|---|
| **0 Watch** | A few T1/T2 observers, no harm | Nearby watchmen look; one questions a bystander | 0 to 15 s | Suppress, ignore, walk on |
| **1 Guard patrol** | 3+ T2 or a T3 flees | Two-man patrol, "calm yourself" | 20 to 45 s | Suppress, talk, apologise, move away |
| **2 Officer parley** | Aura sustained 10+ s, a T4 collapse, a complaint, or recognised dread >= 50 | A sergeant or officer walks up with a guard shadowing: the "officers will come up to you" beat | 45 to 90 s | Talk, bluff, fine, bribe, surrender, intimidate, leave |
| **3 Captain and mages** | Parley fails, property damage, mass T4 | Captain, 4 to 8 guards, one or two guild mages | 2 to 4 min | Negotiate, accept inquiry, run, fight non-lethally |
| **4 Knights or inquisitors** | Dread >= 70, a death, a "demonic" read in a church culture | Knight squad or inquisition with sanctified wards | 10 to 30 min | Prove innocence, flee, fight |
| **5 Royal response** | Dread >= 85, noble killed, siege-scale deed, repeated step 4 | Bounty posted, army units (`war_units.gd`), a crown champion, **siege** (`siege.gd`) of any refuge town | Hours to days | Flee the kingdom, negotiate via envoy (`war_intel.envoy_arrive`), face them |

### 8.2 Options

| Option | Mechanic | Consequence |
|---|---|---|
| **Suppress** | Release `Q` or hold `Z`; tension falls over about 10 s | Cheap; if done at the officer's request, small trust gain |
| **Talk** | Dialogue using persuasion, rank (`homes.rank_in`), reputation, awe | Dismissed, warned, fined or escorted out |
| **Intimidate** | Aim the release at the officer; ordinary officers back off at T3 | Works once; dread up; the officer's superior hears |
| **Bribe** | `courts.bribe_officer(cid, party, gold)` | Cost scales with dread; honest officers refuse; witnessed bribes are recorded; quarter corruption rises |
| **Surrender** | Hand over weapons; `courts.file_case` hearing | Non-lethal; lose time, gold or gear; trust gain for honourable surrender; a fair hearing |
| **Flee** | Street graph run; gates close; manhunt (`search.gd`) | Dread rises if you escape with violence |
| **Fight, non-lethal** | Stuns, restraint, disarms, low-power aura | Reputation stays clean; some followers find it weak |
| **Fight, lethal** | Kill guards | Major crime, dread +30, step 4 at once |
| **Hostage, threat** | Hold an official | Worst reputation outcome; never blocked by the game |
| **Appeal to a patron** | Noble, guild or temple with your awe intervenes | Costs a favour (ledger entry) |

### 8.3 Officer parley

Officer persona (courage, honesty, loyalty) and training set the opening: a proud officer demands you stand down, a cautious one asks if you are lost, a corrupt one hints at a fee. The conversation is five to seven lines gated by your current aura (you must suppress to speak without a tension penalty), identity, local law (`courts.law(kingdom, crime)`) and reputation. Outcomes: **Calmed** (dread -2), **Fined** (gold to the town ledger), **Escorted out** (staying triggers step 3), **Detained** (followers react), **Fight** (sets step 3 or 4).

---

## 9. Positive and special uses

1. **Ending riots.** A riot is 20+ hostile NPCs with a ringleader. A medium release (0.3 to 0.5) puts the crowd at T2 without T4. It disperses; ringleaders back off. `awe` up, district `tension` down, some remember the fright.
2. **Protecting villagers.** Release toward the raiders' road; most bandits (tier 3 and below) break. Carrying a child back adds awe.
3. **Intimidating bandits.** Directed cone at a camp: brave ones hold, most scatter, the leader parleys. Let go, capture or kill.
4. **Impressing recruits.** A calibrated release before hiring raises `res` and `fear` (`follower_will.gd` MOT) and leaves `aff` flat. Fear-based loyalty cracks under stress (`consider_leaving`, `organise_resistance`).
5. **Duels of aura.** `contest = P_a*leak_a*(1 - S_b*0.3) - P_b*leak_b*(1 - S_a*0.3)`. A gap of 0.2 to 0.4 breaks the loser's stance (flinch, step back, kneel in sect culture). No damage, no control. Used at sect gates, monster-town greetings, tournaments and as a prelude to a fight. Surge is the counter-spike; a cool head wins by not matching.
6. **Calming animals.** Low calm release settles spooked horses (beast or bending path).
7. **Warding spirits.** Aura near a ward breaks weak hauntings.
8. **Funerals and rituals.** A solemn held release at a grave earns clan awe.
9. **Breaking a siege's morale.** Undisciplined attackers rout at T3; veterans hold.
10. **Negotiation weight.** A measured release behind your words adds weight.
11. **Festivals.** A controlled "aura lantern" show earns awe and coin.

---

## 10. Consequence engine

Each aura incident produces one **AuraIncident** record (pure data) and fans out:

| Target | Effect | Module |
|---|---|---|
| District values | `safety` down, `tension` up, `prosperity` down while dread is high; `political_support` shifts | `realm/district_values.gd` (`on_crime`, `_nudge`, `act`) |
| Courts | Complaint "public terror" or "disturbing the peace"; severity from `fear_peak` and harm; T2+ observers become witnesses | `realm/courts.gd` (`file_case`, `add_witness`, `bring_to_court`) |
| Reputation per group | `dread` and `awe` per town and per group: peasants, guards, church, nobles, merchants, mages guild, monster towns, sects | `realm/reputation.gd` |
| Followers | `aff`, `res`, `fear`, `ide`, `pro` shift; new event kinds `aura_protect`, `aura_terrorise` | `realm/follower_will.gd` `on_event` |
| War intel | Enemy scouts report your power; envoys offer terms | `realm/war_intel.gd` (`scout_report`, `envoy_arrive`) |
| Legitimacy | A lord whose land you terrify loses face or gains an enforcer; title claims weigh awe against dread | `realm/territory.gd`, `social_perception.legitimacy` |
| Settlement morale | Mood and economic activity; migration push | `district_values.gd`, `town_mood.gd`, `migration.gd` |
| Migration | Families leave when `dread >= 60` for 14 days; vendors drop; they carry the story | `realm/migration.gd`, `governance.gd` `emigration_pressure` |
| News and rumours | Distance-delayed, distorted: "the Pale Lord walked into Hollin and every dog howled" | `realm/news.gd`, `rumours.gd` |
| Psyche memory | Each T3+ observer writes a heavy memory; you are remembered by face | `realm/psyche.gd` (`MEM_N = 5`) |
| Legends | Repeated incidents with the same story form a legend: name, deed, toast, rhyme. Slow decay; shapes reception far away | `realm/scribe.gd`, `aura_fallout.gd` legends list |

**Settlement bill.** Property damage (cracked glass, wrecked carts, lost stock) becomes a compensation claim. Pay (awe and trust up), refuse (dread up) or contest in court.

---

## 11. Scenarios (40)

Format: trigger, what happens, outcome. Roles are from 7, steps from 8.

1. **Market after burning the gatehouse.** Dread 72 in Greywater, face unmasked. Shutters close two houses ahead; merchants cover stalls; a baker stays and hisses prices; a child waves. Ladder reaches step 2 within a minute.
2. **Quiet hooded entry.** New town, hood up, S high. Nobody looks; an old woman's dog whimpers and she goes inside. Tiny rumour: "something walked in."
3. **Eight seconds in a square.** Crowd goes T2 to T3; parents scoop children; an elder faints; a horn sounds. You release; the officer asks you to apologise to the old man.
4. **Child who is not afraid.** At T2 range a six-year-old asks to see "the sparks." The mother screams. Show a harmless spark (awe) or scold (dread).
5. **Slip at a funeral.** Follower dies; grief surge flattens the churchyard grass; mourners kneel; if the read is holy, awe rises.
6. **Nightmare in an inn.** Guests wake sweating; the landlord asks you to leave quietly. Price up, welcome gone.
7. **Horse bolts.** Your mount rears at T2 and throws you; bond check fails. A beast-path player resists.
8. **Street festival.** Suppress to protect the fun. If you slip the band falters; a bow and a toast restore the mood.
9. **Bandits on the road.** Directed release: two flee, one stays, the leader parleys. Let them go with a warning; the next town hears you spared them.
10. **Rival mage probes.** A guild mage sends a counter-pulse. You hold level; she bows and says the guild will want a word. Step 2 with a polite face.
11. **Inquisitor arrives.** Dark swirl in an eastern town. Fanatics accuse; the inquisitor wards the square (S +0.1, `wall_factor` x0.5). Talk, surrender, flee or fight.
12. **Devotees kneel.** Warm gold release over a plague street while you heal. Beggars follow; a priest suspects a rival saint. Awe up, Church tension up.
13. **Looters in the gap.** Your release clears a market; four looters slip in. Stop them (awe, but more fright), ignore (town blames you) or bribe the watch.
14. **Beggar's blessing.** A beggar kneels; you give coin; the crowd sees it. Dread -5 locally.
15. **Draper's bill.** Cracked windows; the draper presents a ledger. Pay, argue in court, or threaten (dread).
16. **Elder collapses.** A 78-year-old falls at T4. Kneel and help (reverses the reaction) or leave (remembered).
17. **Lord's hawk.** The hawk panics and crashes into a hedge. The lord is furious; "injury to noble property" goes to court; you pay.
18. **Duel with a sect elder.** At a monster-town gate the elder probes. You match; he smiles and steps back; the inner gate opens.
19. **Sect sanctum breach.** Releasing inside is an insult. The gatekeeper warns once; second time disciples ring you; apology and penance.
20. **Marching column.** A sergeant orders his men to hold at T2; a few break at T3. You let them pass; he salutes the discipline.
21. **Siege morale.** At a besieged castle's gate you release at 0.6. Defenders waver and open a sally gate to parley. The attacker's general sends an envoy (`war_intel.envoy_arrive`) offering gold.
22. **Refugees at a bridge.** They fear every cultivator. You suppress and wait. A child hands you bread. Rumour of a "quiet lord."
23. **Hunting party.** You flush a stag by releasing; the forester complains; apologise and trade.
24. **Dying infant at a midwife's.** Your aura slips; the midwife begs. You step back and send a healer. The infant was already dying; the scene is hard and fair, and aura is never the cause.
25. **Haunted house.** The ghost whimpers and retreats; neighbours are grateful.
26. **Caravan on the road.** Mules bolt; you help gather goods. The caravan master spreads word of a fearsome man who helped.
27. **Drunk slaps your shoulder.** He feels nothing; the crowd gasps; he laughs. A comic beat.
28. **Bribe the sergeant.** Dread 60; he takes a fee; the road opens; quarter corruption rises; a new captain audits later.
29. **Impostor.** Someone fakes your sigil and shouts; the crowd flees; rumours blame you. Clear your name with witnesses in court.
30. **Surrender with grace.** At step 3 you hand over weapons and are held at a gatehouse. A judge notes your calm: light fine and an escort out.
31. **Royal bounty.** Step 5: posters everywhere; mid-tier bounty hunters try you at night; villagers who like you hide you.
32. **Lost daughter.** A fleeing mother loses her girl; you find her and return her. Mother kneels; dread falls; awe rises.
33. **Monster-town greeting.** A werewolf elder expects a measured release; you give it and the market opens. The same release in Valencios would have called the guard.
34. **Frontier camp.** Elders ask you to stay as a "silent wall." Word spreads; bandits avoid the camp.
35. **Breakthrough in a field.** The 8 s sun-dim surge; cows lie down; the priest declares a sign; delegations arrive next day.
36. **Tax collector flees.** He forgets the rent; the lord sends a knight; next year's rent doubles.
37. **Spy in the crowd.** An enemy scout logs your release level in `war_intel`; envoys arrive three weeks later with a specific offer.
38. **Staged panic.** A rival lord pays people to scream when you pass. Expose it with witnesses (courts) or let it ride.
39. **Quarantine wall.** Guards fear your aura more than the plague and open the gate. Safety dips, plague stops.
40. **Mercy after a fight.** You suppress at the gate and heal wounded guards. The captain lifts the warrant. Legend: "the Pale Lord who knelt."

---

## 12. Systems map

### 12.1 Status of each piece

| Piece | Status | Existing file | Gap / plan |
|---|---|---|---|
| `aura_emit`, `aura_suppress`, `magic_pressure` | PARTIAL | `kingdom/scripts/realm/social_perception.gd` | Keys read; nothing fills them from a player state. AR-1 |
| Observer sensitivity (`magic_sense`, intelligence, stress) | PARTIAL | same | Add species, state, faith, training factors via ctx. AR-2 |
| Reaction pipeline (stimuli, stages, stagger) | EXISTS | `kingdom/scripts/population/presence.gd` (`Stim.PUBLIC_MAGIC`, `STAGGER`, `MAX_BODIES = 48`) | Add `Stim.AURA` and tier mapping. AR-3 |
| Reaction kinds | PARTIAL | `kingdom/scripts/population/reaction_request.gd` (FLEE, CALL_GUARD, BOW, STEP_BACK, FLINCH) | Add COLLAPSE, KNEEL, CARRY_CHILD, SHUTTER, HIDE. AR-5 |
| Bump reaction ("flee" via fear) | EXISTS | `social_perception.gd bump_reaction` | Core of the T3 decision |
| Crowd roles | MISSING | `kingdom/scripts/population/utility_brain.gd` | `aura_roles.json` plus logic. AR-4 |
| Street clearing | MISSING | `kingdom/scripts/population/street_graph.gd` | Repulsion cost. AR-4 |
| Alert levels, lockdown | EXISTS | `kingdom/scripts/population/alert_net.gd` | Aura incident source. AR-6 |
| Crime witnessing | EXISTS | `kingdom/scripts/population/crime_watch.gd`, `evidence.gd` | "Public terror" crime. AR-6 |
| Guard escalation | PARTIAL | `alert_net.gd`, `guard_lantern*.gd`, `search.gd` | Officer parley, captain squad. AR-7 |
| Courts | EXISTS | `kingdom/scripts/realm/courts.gd` (`file_case`, `add_witness`, `bribe_officer`, `law`) | `public_terror` crime id. AR-8 |
| Reputation | EXISTS | `kingdom/scripts/realm/reputation.gd` (`record`, `on_deed`, `view`, `_distort`) | Axes `dread`, `awe`. AR-8 |
| District values | EXISTS | `kingdom/scripts/realm/district_values.gd` | `dread_shock` modifier. AR-8 |
| Follower will | EXISTS | `kingdom/scripts/realm/follower_will.gd` (`on_event`) | Kinds `aura_protect`, `aura_terrorise`, `aura_fear`. AR-9 |
| War intel | EXISTS | `kingdom/scripts/realm/war_intel.gd` | Power field in scout reports. AR-9 |
| News and rumours | EXISTS | `kingdom/scripts/realm/news.gd`, `rumours.gd` | Kinds `aura_incident`, `legend`. AR-10 |
| Psyche | EXISTS | `kingdom/scripts/realm/psyche.gd` | Memory kind `aura_dread`. AR-10 |
| Migration | EXISTS | `kingdom/scripts/realm/migration.gd` | Dread as push. AR-10 |
| Legitimacy | PARTIAL | `social_perception.legitimacy`, `realm/territory.gd` | Awe and dread in the triple. AR-10 |
| Faith and culture | EXISTS | `kingdom/scripts/realm/faith.gd` | Aura signature table. AR-2 |
| Power paths | EXISTS | `kingdom/scripts/realm/power_paths.gd` | `aura_discipline()` view. AR-1 |
| Soul tiers | EXISTS | `kingdom/scripts/sim/soul.gd`, `kingdom/data/soul/tiers.json` | `P` table. AR-1 |
| Technique flare | EXISTS | `kingdom/scripts/actors/technique_caster.gd` | `AuraState.flare(power)` on cast. AR-1 |
| Cultivation layers | PARTIAL | `realm/cultivation.gd`, `ui/gamemenu/tab_cultivation.gd` | Layer count feeds P. AR-1 |
| Soul beast aura | EXISTS | `kingdom/scripts/actors/soulbeast_aura.gd` | Reuse constants. AR-3 |
| Aura state, Focus, input | MISSING | none | `sim/aura_state.gd`, input action. AR-1 |
| Aura Control skill | MISSING | `sim/skills.gd` | New skill id. AR-1 |
| Dread/awe sync, recognition | MISSING | `social_perception.gd` identity | `realm/aura_fallout.gd`. AR-8 |
| Compensation bill | MISSING | `courts.gd` partial | AR-8 |
| Legends | MISSING | `scribe.gd` partial | AR-11 |
| HUD meter | MISSING | `ui/` | Local PC. AR-12 |
| Aura VFX | PARTIAL | `vfx/toon_vfx.gd`, `vfx/element_fx.gd` | Codex. AR-13 |
| Shutters, empty market | MISSING | world scenes | Codex. AR-14 |
| Animation set | MISSING | `assets/incoming/animations` | Antigravity. AR-15 |

### 12.2 New data and API (cloud)

```
# sim/aura_state.gd (player side, pure data + tick)
func hold(dt) / release() / surge() / rein_in(dt) / flare(power)
func subject_view(ctx) -> {aura_emit, aura_suppress, reach_m, signature, cone}
func focus() -> float ; serialize() / deserialize()

# realm/aura_fallout.gd (RealmModule, hub registered)
func on_incident(subject, sid, quarter, peak, harm, witnesses) -> int
func recognise(observer_id, subject, ctx) -> float
func dread(subject, sid) -> float ; awe(subject, sid) -> float
func bill(sid, incident) -> Dictionary ; legends(subject) -> Array
func tick_day_chunks(day, ctx) ; serialize() / deserialize()

# population/aura_field.gd (near tier, no allocation)
func tick(player_pos, aura_view, bodies) ; tier_of(felt, courage) -> int
```

Data: `data/aura/aura_curve.json` (T_rise, reach exponent, P per tier, cost), `aura_species.json`, `aura_roles.json`, `aura_culture.json` (reading table and signatures), `aura_ladder.json` (triggers, timings, units per kingdom), `aura_effects.json` (section 4 thresholds).

### 12.3 Performance budget

* `AuraState` tick: O(1), under 0.02 ms.
* `aura_field.tick`: staggered with Presence (`STAGGER = 3`), distance-squared reject first, at most one `magic_pressure` per observer with a per-second cache. Target 0.3 ms for 48 bodies.
* Street cost field: update every 0.5 s, at most 64 edges.
* Fallout day tick: chunked, 0.1 ms per day, only for towns with active dread (cap 16).
* Save: `AuraState` 48 B; dread/awe 2 B per (subject, town), up to 40 towns; incident ring 64 x 24 B; legends 20 x 60 B. Under 6 KB against the 2.5 MB raw limit.
* VFX: one shader quad plus a bounded emitter, at most 8 ring decals live; target 0.4 ms GPU on PC high (Codex).

### 12.4 Determinism and saves

All rolls hash `[WorldSim.SEED, "aura", day, id]`; no Vector2 in saved state; `AuraState` saved in the player block, fallout through `save_codec.gd`; schema bump follows the master-plan rule (SCHEMA_VERSION currently 4).

---

## 13. Ownership

| Owner | Scope |
|---|---|
| cloud | AuraState, curve, Focus, skill, slips; `aura_fallout.gd`; presence integration; role logic and street field; ladder; hooks into courts, reputation, district values, followers, war intel, news, psyche, migration; saves; all tests |
| Antigravity | ALL animation: flee (adult, child, elder), carry-child, kneel, faint (T4/T5), hide behind door, shutter-pull gesture, merchant covering stall, devotee weeping, fanatic accusing, officer approach and parley stances, rival mage counter-pulse, child stare walk-up, horse rear, guard ring. Consumes the reaction contract; no AI code |
| Codex | World: shutter states, empty-market dressing (covered stalls, dropped goods, abandoned and overturned carts), untouched bell, grass ring, candle and lantern states, wanted posters, ward stones, aura VFX per path and signature |
| local PC | HUD meter and reach ring, GPU tuning, audio (drone, silence of birds) |

---

## 14. Work packages

**AR-1 Aura core (cloud).** `sim/aura_state.gd`, input action `aura_release`, curve and cost data, Focus, slips, `P` from soul, path and cultivation, `flare()` in `technique_caster.gd`, Aura Control skill. Tests: curve values at h = 0, 1, 4, 8, 12 s; echo half-life; Focus drain and STRAINED; suppression subtracts as `magic_pressure` expects; slip chance deterministic; save round trip; P = 0 below tier 3.
**AR-2 Sensitivity and culture (cloud).** Species, state, faith, training factors via ctx; signature table in `faith.gd`; persona hook. Tests: same emit gives ordered `felt` across observers; holy vs demonic reading differs by culture; animals exceed humans at equal emit.
**AR-3 Presence integration (cloud).** `Stim.AURA`, tier mapping, hysteresis, `aura_field.gd`. Tests: tier thresholds; zero allocation per tick; 48-body budget; stagger; determinism.
**AR-4 Crowd roles and street clearing (cloud).** Role table, parent, elder, looter, devotee logic, refuge choice, repulsion field, chaos index. Tests: parent with child picks carry; looters only at high chaos; crowd flows around repulsion; no teleporting; district tracker above 48 bodies.
**AR-5 Reaction contract extension (cloud).** COLLAPSE, KNEEL, CARRY_CHILD, SHUTTER, HIDE in `reaction_request.gd` with layer, priority, duration, keeps_activity. Tests: FLEE exclusivity preserved; preemption; name round trip.
**AR-6 Incident and alert (cloud).** Aura incident type, severity, hooks in `alert_net.gd` and `crime_watch.gd`, "public terror" crime. Tests: severity monotonic in fear peak; alert steps; witnesses recorded.
**AR-7 Ladder and parley (cloud).** Steps 0 to 5, timers, unit mix per kingdom, parley model, option resolution. Tests: step N only under documented triggers; honest officer refuses bribe; surrender yields hearing; lethal fight jumps to step 4; deterministic outcomes.
**AR-8 Fallout module (cloud).** `aura_fallout.gd`: dread and awe axes, recognition roll, district shock, price and vendor refusal, compensation bill, court case. Tests: documented half-lives; recognition obeys disguise; price change bounded; bill paid once; save round trip.
**AR-9 Followers and war (cloud).** Follower event kinds; power field in scout reports; envoy offers keyed to power. Tests: protect raises `res`, terrorise raises `fear` and lowers `aff`; lifelong loyal follower never betrays on aura alone; scout error.
**AR-10 News, psyche, migration, legitimacy (cloud).** Road-delayed distorted news; psyche memory kind; migration push; legitimacy uses awe and dread. Tests: far town hears later and vaguer; memory weight scales with felt; migration wave after sustained dread; emergence caps respected.
**AR-11 Legends (cloud).** Creation from repeated incidents, decay, reception modifier, scribe entry. Tests: threshold; decay; dedupe; cap 20.
**AR-12 HUD (local PC).** Meter, reach ring, "felt by" cue, Focus bar. Test: screenshot gate.
**AR-13 Aura VFX (Codex).** Five signatures, reach ring decal, ripples, candle gutter, grass ring, glass cracks, breakthrough sky tint. Budget 0.4 ms. Tests: frame capture per signature; GPU measure.
**AR-14 World dressing (Codex).** Shutter states, covered and abandoned stalls, dropped goods, overturned cart, wanted posters, ward stones, bell prop. Tests: `ashes-world-lint` clean; draw budget per site.
**AR-15 Animation set (Antigravity).** Clips and wiring for every reaction kind above. Tests: each kind maps to a clip; contact-sheet review; foot-slide under threshold.
**AR-16 Soak and balance (cloud).** Two-game-year soak with repeated releases. Invariants: dread, migration and price caps hold; every town keeps a fallback shop; low tier unaffected.

---

## 15. Balance and guards

* **Never lock the player out.** Every town has a fallback (fence, monastery, high-courage innkeeper). Dread >= 85 brings a bounty, not starvation.
* **Early play untouched.** P < 0.05 below tier 3.
* **Recoverable.** Dread half-life 90 days; a paid bill and a public apology cut dread by 15.
* **Spread cap.** One town's dread adds at most 30 percent to a neighbour's belief unless the deed was kingdom-scale.
* **No quest griefing.** Quest-critical NPCs have a `K_training` floor.
* **Time to fun.** First release shows a visible reaction within 3 s.

## 16. Open questions

1. Default key `Q` hold: acceptable?
2. HUD shows the player's emit or the worst observer's felt value (more informative, less magical)?
3. Aura signature chosen by the player or fixed by path?
4. Keep or cut the "frail and dying" medical edge in section 3 rule 2 (recommend: keep as a non-lethal crisis scene only).
