# Rising Ashes: store listing text

Everything here describes what is in the current build (a vertical slice of the first region).
Planned features from the design docs (other regions, owning land and settlements, Soulbeasts,
Rift expeditions, the capital's politics) are deliberately **not** promised. Add them to the
listing when they ship.

Character counts were checked with `wc -m` (limits in brackets).

---

## App name / title

**Rising Ashes: Medieval Life** (27 characters; Play limit 30, App Store limit 30)

Alternatives: `Rising Ashes` (12), `Rising Ashes: Frontier RPG` (26).

## App Store subtitle (30)

**Live, work and fight to rise** (28)

## Short description (Google Play, 80)

**Born a peasant in a frontier village. Work, fight and rise through the ranks.** (77)

## Promotional text (App Store, 170, can be changed without a review)

Begin as a child in Ashford, a village guarded by glowing runestones. Take a job, join the
Adventurers' Guild, face goblins and wolves, and earn your rank. (155)

---

## Full description (Play 4000 / App Store 4000)

> 2,146 characters.

```
Rising Ashes is a third-person medieval life RPG for your phone. There is no chosen hero and no fixed destiny: you are born in Ashford, a small frontier village, and what you become depends on what you do.

A LIFE FROM THE BEGINNING
Your story opens with your birth. You grow up in Ashford with parents who are real villagers, and you step into the world as a child before taking on adult life. The places you go and the things you do earn titles and shape the kind of person you become.

A VILLAGE THAT LIVES WITHOUT YOU
Villagers walk the lanes and work their trades. The market has real stock, so prices move with supply, and the merchant only has so much coin. Day turns to night, the lamps are lit, and chimneys smoke over the rooftops.

WORK FOR A LIVING
Jobs are real positions with a fixed number of seats: the town guard, the smithy, the inn and the woodcutters. Apply when there is a vacancy, turn up for your shifts, draw your wages, and earn promotion through merit. Keep an eye on hunger and fatigue: eat, and rent a bed at the inn or sleep rough.

THE ADVENTURERS' GUILD
Join the guild and take contracts from its board, from rank F all the way to S. Hunt, clear dens and deliver what the village is short of. Fail a contract and you will owe for it.

BEYOND THE RUNESTONES
Ancient runestones ring the village and hold the wilds at bay. Walk past their reach and the danger rises: wolf packs roam the forests and goblins hold their warrens. Fight with sword combos, block and dodge. Beaten monsters can yield, and you can even name them to take them into your service, at a cost.

RISE THROUGH THE RANKS
Earn merit by your deeds, win promotion from peasant upward, recruit soldiers and lead your own company in the field.

MADE FOR PHONES
- Landscape, one thumb to move and one to act, with a drag-to-look camera
- Automatic graphics quality for low, mid and high-end phones, plus a battery saver
- Save and load anywhere
- Plays fully offline: no account, no ads, no data collected

Rising Ashes is in active development. The first region around Ashford is where your life begins, and more of the world will open in future updates.
```

(Paste the block's contents, without the fences. If the store editor strips blank lines,
keep the section headings in capitals so they still read as sections.)

---

## Feature bullets (for the store's "What's in the game", press kit, or screenshot order)

1. Born in a frontier village: a life that starts at birth and grows up with you
2. A living village: villagers with trades and homes, a stock-driven market, day and night
3. Real jobs with real vacancies: guard, smithy, inn, woodcutters; shifts, wages, promotion
4. The Adventurers' Guild: contracts from rank F to S
5. Runestones hold back the wilds; step past them and danger rises
6. Melee combat with combos, block and dodge against goblins and wolf packs
7. Defeated monsters can yield and be named into your service
8. Earn merit, win promotion, recruit and lead your own soldiers
9. Hunger and fatigue, food, and a bed at the inn
10. Offline, no ads, no account, save anywhere; automatic quality for any phone

## Screenshot order and captions

| # | File | Caption (headline / sub-line) |
|---|---|---|
| 1 | `01_village_market` | LIVE A WHOLE LIFE / in a living medieval village |
| 2 | `02_goblin_combat` | FIGHT BEYOND THE WALLS / goblin warrens and wolf packs roam the wilds |
| 3 | `03_guild_hall` | JOIN THE ADVENTURERS' GUILD / take contracts and climb from rank F to S |
| 4 | `04_runestone_danger` | THE RUNESTONES PROTECT YOU / step past their reach and danger rises |
| 5 | `05_town_guard` | RISE FROM PEASANT TO LORD / earn merit, win promotion, lead your own soldiers |
| 6 | `06_inn_interior` | WORK, TRADE AND REST / take a job, sell your spoils, rent a bed at the inn |
| 7 | `07_night_plaza` | FROM DAWN TO LAMPLIGHT / a full day and night cycle |
| 8 | `08_ashford_aerial` | ASHFORD AWAITS / your village, your story |

Edit `tools/store/captions.txt` and run `tools/store/make_captions.sh` to change them.

---

## App Store keywords (100)

```
rpg,medieval,open world,fantasy,village,life sim,sword,guild,knight,adventure,offline,goblin,kingdom
```
(100 characters, the limit. Don't repeat words already in the app name or subtitle; Apple indexes those
separately. Commas, no spaces after them.)

## Category

| Store | Primary | Secondary / tags |
|---|---|---|
| Google Play | **Game → Role Playing** | Tags: Open world, Medieval, Fantasy, Life simulation, Offline, Single player, Action RPG |
| App Store | **Games → Role Playing** | Secondary: Games → Simulation (or Adventure) |

## Pricing model (for the questionnaires)

Current build: **no ads, no in-app purchases, no account**. If that changes, update the
questionnaires and the privacy answers below before the release that adds it.

---

## Content rating questionnaire draft (IARC on Google Play, age rating on App Store)

Answers based on the current build. Review them yourself; you are legally responsible
for the answers.

| Topic | Answer | Notes |
|---|---|---|
| Violence | **Yes: fantasy violence** | Third-person melee combat with swords against goblins, wolves, orcs and human raiders. Enemies fall with a death animation. |
| Violence realism | Stylised, not realistic | Low-poly stylised characters; no gore. |
| Blood / gore | **No** | Hit effects are sparks and sword arcs, no blood. |
| Violence against humans / human-like | **Yes, mild** | The player can fight human raiders and bandits, and command soldiers in skirmishes. No torture, no execution. |
| Violence against animals | **Yes, mild** | Wolves attack the player and can be killed; pelts and meat drop as loot. |
| Sexual content / nudity | No | |
| Language / profanity | No | |
| Crude humour | No | |
| Drugs | No | |
| Alcohol | No alcohol use shown | There is an inn (food, beds). No drinks are sold or shown being consumed. |
| Tobacco | No | |
| Gambling / simulated gambling | No | |
| Horror / fear | Mild | Night scenes and monsters; no jump scares. |
| User-generated content / chat | No | |
| Users can interact / communicate | No | Single player, offline. |
| Shares location | No | |
| Digital purchases | No | |
| Ads | No | |
| Unrestricted web access | No | The Credits & Licences screen opens licence URLs in the system browser only when tapped. |

**Expected outcome (not guaranteed):** IARC around PEGI 7 to PEGI 12 / ESRB Everyone 10+ /
USK 12 because of fantasy violence against human-like characters. App Store: **12+**
("Infrequent/Mild Cartoon or Fantasy Violence"; choose "Frequent/Intense" only if you feel
combat dominates play). Google Play target audience: **13+** (don't select under-13 age
groups; that pulls in the Families policy).

---

## Privacy (Data safety on Play, App Privacy "nutrition label" on the App Store)

Checked in the code on 2026-09-27:

- **No networking in the game code.** No `HTTPRequest`, `HTTPClient`, TCP/UDP, WebSocket or
  multiplayer peers in `kingdom/scripts` or `kingdom/autoload`. (The only network code in the
  repo is in editor-only plugin panels, `dialogue_manager` and `road-generator` update
  checkers, which don't run in an exported game.)
- **Android `INTERNET` permission is off** (`permissions/internet=false` in
  `kingdom/export_presets.cfg`). The only extra permission is `VIBRATE`.
- **No analytics, crash reporting, ads or account SDKs** (no Firebase, AdMob, Play Games,
  Game Center code).
- **Local storage only:** saves are JSON files in the app's private storage (`user://`,
  `Life.save_game`), and graphics settings go in `user://settings.cfg`. Nothing leaves the
  device. Backups are off (`user_data_backup/allow=false`).
- **One outbound action, user-initiated:** tapping a link on the Credits & Licences screen
  opens it in the device browser (`OS.shell_open`).

So:

- **Google Play Data safety:** "Does your app collect or share any of the required user data
  types?" → **No**. Data encrypted in transit: not applicable. Deletion: uninstalling the app
  deletes all data.
- **App Store App Privacy:** **Data Not Collected**. No tracking (no ATT prompt needed).
- **Privacy policy (still required by both stores).** Suggested text, to host at a public URL:

> Rising Ashes does not collect, store on any server, or share any personal data. The game
> runs offline. Your saves and settings stay on your device, in the app's private storage,
> and are deleted when you uninstall the app. The game contains no ads, analytics or
> third-party tracking. Contact: <your email>.

If you later add ads, analytics, cloud saves, leaderboards or crash reporting, these answers
change. Update the Data safety form, the App Privacy label and the policy **before** that
release.
