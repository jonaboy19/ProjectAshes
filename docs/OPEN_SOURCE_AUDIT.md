# Open-source audit: Rising Ashes (Kingdom, Godot 4.6)

**Date:** 2026-09-27. **Scope:** everything third-party in `kingdom/` (the game that ships to the Play Store and App Store):
`kingdom/assets/incoming/*`, `kingdom/assets/kaykit`, `kingdom/assets/ui`, `kingdom/addons/*`, ported code in
`kingdom/scripts`, the Meshy output, and our own generated assets. The older `game/` prototype only uses KayKit (CC0).
**The repo is public on GitHub**, so everything committed is also *redistributed*. That matters for licences that allow
use in a game but not redistribution of the raw files.

**How this was checked**
- **Licence:** "verified" means the licence page was fetched in this audit session (2026-09-27). "Verified (Wayback)"
  means opengameart.org returned HTTP 502 all session, so the licence field was read from the Wayback Machine copy of the
  same page (2026 snapshots). "Not verified" gives the reason. Where a licence file in the repo claims an earlier check
  (2026-09-26/27), that is noted, but it isn't counted as verified here.
- **Usage:** grep of `kingdom/scripts`, `kingdom/autoload`, `kingdom/scenes`, `kingdom/data` for `res://` paths, including
  paths built from constants (`Q + "..."`, `IN + "..."`), plus `.gdignore` checks (a `.gdignore` in a folder or any
  parent means Godot doesn't import it at all).
- **Size:** `du` on disk. The Meshy `_raw/` and `rigged/` folders are git-ignored, so they're on the PC but not in the repo.

---

## 1. Summary

| Class | Packs / sources | MB on disk |
|---|---:|---:|
| **USED IN GAME** (a live `res://` path in game code) | 31 | 1,509 in `incoming/` + 22 KayKit + ~1 UI |
| **USED, derived offline** (the game loads our processed copy, not the pack) | 3 (Poly Haven models → `generated/scan`, ambientCG → baked atlases, MakeHuman/MPFB2 → `generated/characters`) | 164 imported + 200 not imported |
| **IMPORTED BUT UNUSED** (no `.gdignore`, no reference) | 20 | 528 |
| **NOT IMPORTED** (`.gdignore`) | ~163 folders (OGA 66, Kenney 26, armor 21, Quaternius 19, KayKit 9, other 22) | 3,716 (of which Meshy `_raw` is 1,830, untracked) |
| Addons in `kingdom/addons` | 11 (1 used by code, 1 tests only, 4 autoloaded but not called, 5 enabled but unused) | 153 |
| **Total `kingdom/assets/incoming`** | | **5,916 on disk; ~3,515 tracked in git** |

Plus our own work: `kingdom/assets/generated` (179 MB; Blender scripts in `kingdom/tools/blender`), KayKit starter art
`kingdom/assets/kaykit` (22 MB, CC0, used), UI `kingdom/assets/ui` (Cinzel OFL, 11 game-icons CC BY 3.0, used).

**Yes, the open-source content is real, and the game uses it.** 31 third-party packs are loaded by live code paths,
among them the Quaternius UAL1/UAL2 animation libraries (every humanoid animates with them), Quaternius base
characters/outfits, props, nature, RTS, animals and monsters, the G6 and CDmir villagers, the OpenGameArt/BigSoundBank
music and SFX, Poly Haven terrain textures and HDRI, the OGA/Poly Pizza CC-BY helmet and shield, and the 3dassets.dev camp
props. Every licence behind a *used* asset is commercial-safe (CC0, CC BY, MIT or OFL). **No NC, no SA, no
personal-use-only, no Mixamo, no paid-tier Quaternius or KayKit files, and no Hunyuan3D/Higgsfield content turned up
anywhere in the repo.**

### Red flags and to-dos (most important first)

1. **The MIT notices aren't in the game yet (required).** Godot itself, the 10 shipped addons and the ported TPS-demo
   camera shake are MIT, and MIT requires the copyright and licence text to ship with the game. **Added** the lines to
   `kingdom/CREDITS.md`. The game still needs a "Licences" screen or file that shows them, including Godot's
   `Engine.get_license_info()`.
2. **A missing CC BY credit that ships: Sky3D's Milky Way texture** (`addons/sky_3d/assets/thirdparty/textures/milkyway/`,
   "ESO/S. Brunier", CC BY 4.0, checked on eso.org). The plugin is enabled, so the JPGs get exported. **Added** the credit
   to CREDITS.md. Also added a courtesy credit for **Dejawolf**, whose chainmail texture is in Lotnik's helmet pack (the
   source page names Dejawolf).
3. **RESOLVED 2026-09-27: the user confirmed the Meshy account is a paid plan, so all Meshy output is owned by the user and needs no attribution.** Original note: Meshy output relies on the plan status at generation time. The terms (updated 2026-09-19) were verified: paid-plan
   customers "own their Customer Output". Free-plan output belongs to Meshy and is licensed CC BY 4.0, with credit to
   Meshy required. The repo can't show which plan each of the 51 tasks in `tasks.tsv` (1,077 credits) ran under.
   **Check the Meshy billing history** covers every task date. If any ran on the free tier, add "Created with Meshy" to
   the credits. Separately, the provenance of the Meshy **input images** (`docs/art_reference/concept_*.png` "(user)",
   `ai3d/meshy/_input/armored_*.png`) isn't recorded. Note where they came from.
4. **AI-generated CC0 content is used in the game** (3dassets.dev *Medieval MMO Starter Realm*: fishing hut, cave mouth,
   goblin tent and totem, campfire). The pack page (fetched) says CC0 1.0. The repo's licence note says the site API
   flags it `aiGenerated=true`, but the API returned HTTP 500 this session, so that part wasn't re-verified. Risk is low
   (CC0, and AI output generally carries no copyright to infringe), but nobody can warrant the rights. The other 11
   3dassets.dev packs (91 MB) aren't used.
5. **LICENSE files missing for two shipped addons:** `addons/gloot` and `addons/quest_weaver`. Both are MIT, verified
   upstream (github.com/peter-kish/gloot, github.com/undomick/godot_nexus_quest_weaver). Copy their LICENSE files in.
   This audit can't edit `addons/`.
6. **ProtonScatter's `demos/` folder (12 MB)** holds Textures.com textures that the upstream README says can't be
   redistributed on their own. Delete `addons/proton_scatter/demos/`. It isn't needed and it would be exported.
7. **App Store blocker (not a licence issue):** `limboai.gdextension` and `terrain.gdextension` point at iOS `.dylib`
   files that aren't in the repo. Neither addon is called by game code yet, but an iOS export with them enabled will
   fail or warn. Add the iOS binaries or disable the plugins for iOS.
8. **Export bloat:** `kingdom/` has no `export_presets.cfg`. By default Godot exports *every imported resource*, so about
   528 MB of imported-but-unused packs, plus the 164 MB Poly Haven model sources, would go into the APK/IPA. See
   Cleanup (§5).
9. **Minor or unverified items, none of them used:** `opengameart/models/rigged-horse` (the licence note says "after
   Lyndon's Realtime Rancher", unclear) and `opengameart/models/blender-models-for-freeciv-units` (Freeciv art is often
   GPL). The OGA pages couldn't be checked (502, and the Wayback copies had no licence field). Keep both `.gdignore`d or
   delete them before any use. `docs/art_reference/village_target_*.png` has no recorded source and sits in the public
   repo.
10. **The GDQuest third-person controller's art is CC BY-NC-SA 4.0** (verified). We only took *ideas* from its MIT code,
    and grep finds no GDQuest files or assets. OK as long as nobody copies its art.
11. **Fixed:** `quaternius/pirate-kit/` had no licence file. Added `License.txt` (CC0, verified on quaternius.com).

---

## 2. Full table

Legend: **Lic ✓** = licence verified this session; **Attr** = attribution legally required; **CRED** = in
`kingdom/CREDITS.md` (only needed for used CC-BY/MIT items); status **USED / UNUSED** (imported but unused) /
**NOT-IMP** (`.gdignore`). A LICENSE file "in repo" means a licence or credit file sits in the pack folder or its parent.

### 2a. Used in the game

| Pack | Type | Source URL | Lic ✓ | Attr | CRED | Status | MB | Notes (where used) |
|---|---|---|---|---|---|---|---:|---|
| quaternius/universal-animation-library | anim | quaternius.com/packs/universalanimationlibrary.html | yes (CC0, free Standard tier) | no | n/a | USED | 15.4 | `Assets.UAL_FILES`; every humanoid's clips. License.txt in repo |
| quaternius/universal-animation-library-2 | anim | quaternius.com/packs/universalanimationlibrary2.html | yes (CC0) | no | n/a | USED | 17.7 | `Assets.UAL_FILES` |
| quaternius/universal-base-characters | model | quaternius.com/packs/universalbasecharacters.html | yes (CC0) | no | n/a | USED | 125.4 | `Assets.humanoid()` body and hair. License_Standard.txt (free tier) |
| quaternius/modular-character-outfits-fantasy | model | quaternius.com/packs/modularcharacteroutfitsfantasy.html | yes (CC0) | no | n/a | USED | 281.7 | Only the 4 free outfits (Peasant/Ranger M/F) used. No paid Source files present |
| quaternius/fantasy-props-megakit | model | quaternius.com/packs/fantasypropsmegakit.html | yes (CC0) | no | n/a | USED | 81.1 | `village_services.gd`, `Assets.WEAPONS`, interiors (via `tools/blender/interior_kit.py`) |
| quaternius/medieval-village-pack | model | quaternius.com/packs/medievalvillage.html | yes (CC0) | no | n/a | USED | 3.1 | sawmill, mill, barrel, crate, hay, bench |
| quaternius/ultimate-fantasy-rts | model | quaternius.com/packs/ultimatefantasyrts.html | yes (CC0) | no | n/a | USED | 72.1 | watchtower only (1 file of the pack) |
| quaternius/stylized-nature-megakit | model | quaternius.com/packs/stylizednaturemegakit.html | yes (CC0) | no | n/a | USED | 87.9 | `Assets.NATURE` trees, bushes, rocks |
| quaternius/ultimate-animated-character | model+anim | quaternius.com/packs/ultimatedanimatedcharacter.html | yes (CC0) | no | n/a | USED | 100.8 | `monster.gd` models |
| quaternius/ultimate-animated-animals | model+anim | quaternius.com/packs/ultimateanimatedanimals.html | yes (CC0) | no | n/a | USED | 36.0 | `wolf.gd`; also the source of `animals/quaternius` and the Meshy wolf/boar/bear rigs |
| animals/quaternius (our processed copies) | model+anim | UAA, farmanimal.html, animatedfish.html, poly.pizza/m/iltq5bVNaV, OGA animal pack vol.2 | yes (CC0, all 4 fetched pages; the OGA cat page not fetched) | no | n/a | USED | 13.5 | `critter.gd`: horses, cow, ox, sheep, pig, goat, dogs, cats. LICENSE.txt in repo |
| animals/procedural | model+anim | own work (`animals/_tools`) | n/a (own) | no | n/a | USED | 1.6 | chicken, rooster, duck, goose, pigeon, crow, rabbit |
| characters/g6-ual | model | opengameart.org/content/modular-rpg-characters (System G6) | yes (Wayback: CC0) | no | n/a | USED | 41.6 | 8 villager variants in the NPC mix. Licence in `oga-system-g6-modular-rpg/LICENSE.txt` |
| characters/cdmir-ual | model | opengameart.org/content/monk , /old-lady (CDmir) | yes (Wayback: CC0 both) | no | n/a | USED | 9.2 | monk, old lady. Licence in `oga-cdmir-kelgar/LICENSE.txt` |
| armor/opengameart/cc-by/anglo-saxon-helmets | model | opengameart.org/content/anglo-saxons-helmets-and-spears (Lotnik) | yes (CC BY 3.0) | **yes** | **yes** (+ Dejawolf added) | USED | 1.9 | `Assets.GUARD_HELM` |
| armor/polypizza_sel (Knights Character Kit) | model | poly.pizza/m/3r2JcOZShpE (Jacques Fourie) | yes (CC BY 3.0) | **yes** | **yes** | USED | 0.1 | `Assets.GUARD_SHIELD` |
| 3dassets-dev-ai/medieval-mmo-starter-realm | model (AI) | 3dassets.dev/packs/medieval-mmo-starter-realm | yes (CC0; AI flag not re-verified, API 500) | no | n/a | USED | 14.5 | `lakeside.gd`, `monster_camps.gd`. See red flag 4 |
| polyhaven/hdris | HDRI | polyhaven.com/license | yes (CC0) | no | n/a | USED | 87 | 1 of 5 used (`kloofendal_43d_clear`) |
| polyhaven/textures | texture | polyhaven.com/license | yes (CC0) | no | n/a | USED | 202 | 5 of 22 used by `terrain_streamer.gd` (leafy_grass, forest_ground_04, grass_path_2, rocky_terrain_02, cobblestone_floor_01) |
| opengameart/music (RandomMind ×5) | music | opengameart.org/content/medieval-market-day, -minstrel-dance, -kings-feast, -the-bards-tale, -the-old-tower-inn | yes (CC0, all 5) | no | n/a | USED | ~9 | `audio.gd` town/wild moods |
| opengameart/music/cynicmusic_battleThemeA.mp3 | music | opengameart.org/content/battle-theme-a | yes (CC0) | no (asks "cynicmusic.com pixelsphere.org") | n/a | USED | ~1 | `audio.gd` battle |
| opengameart/ambience (TinyWorlds, Wolfgang_) | ambience | opengameart.org/content/forest-ambience , /crickets-ambient-noise-loopable | yes (CC0, both) | no | n/a | USED | 0.9 | `audio.gd` day/night |
| opengameart/sfx/sword-clashes-starninjas | sfx | opengameart.org/content/20-sword-sound-effects-attacks-and-clashes | yes (CC0) | no | n/a | USED | 0.2 | `audio.gd` clash. Licence only in parent `opengameart/LICENSE.md` |
| bigsoundbank | sfx | bigsoundbank.com/droit.html | yes (CC0) | no | n/a | USED | 10 | `audio.gd` swing/hit/bell (horse, anvil and herd sounds unused) |
| ai3d/meshy (buildings) | model (AI, paid) | meshy.ai/terms-of-use | yes (paid plan owns output) | no (if paid) | n/a | USED | 112.5 | guild, inn, blacksmith, healer, 5 house types, 2 stalls, LOD0/1. See red flag 3 |
| ai3d/meshy/armored | model (AI, paid) + UAL rig | meshy.ai/terms-of-use | yes | no (if paid) | n/a | USED | 182.9 | guard, knight, mercenary, bandit, noble, orc warchief (`Assets.ARMORED`). `_work/` subfolder is imported too |
| kingdom/assets/kaykit (Adventurers 1.0 + Medieval Hexagon) | model | github.com/KayKit-Game-Assets/KayKit-Character-Pack-Adventures-1.0 | yes (CC0, Adventurers page) | no | n/a | USED | 22 | `Assets.CHAR_DIR/MED_DIR/WEAPON_DIR`. LICENSE.txt in each folder. Hexagon page not fetched |
| assets/ui/fonts/Cinzel | font | github.com/google/fonts/tree/main/ofl/cinzel | yes (OFL folder, OFL.txt) | notice only | **yes** | USED | <1 | `ui_theme.gd` |
| assets/ui/icons (11 game-icons) | icon | game-icons.net/about.html | yes (CC BY 3.0) | **yes** | **yes** | USED | <1 | Lorc, Delapouite, Felbrigg |
| scripts/actors/camera_shake.gd (TPS demo) | code | github.com/godotengine/tps-demo (LICENSE.md) | yes (code MIT, art CC BY 3.0, no art taken) | MIT notice | **yes (added)** | USED | – | `player.gd` |
| addons/gloot | code | github.com/peter-kish/gloot | yes (MIT) | MIT notice | **yes (added)** | USED | 1 | `autoload/life.gd` player inventory. **No LICENSE file in repo** |

### 2b. Used, derived offline (the game loads our processed output)

| Pack | Type | Source URL | Lic ✓ | Attr | CRED | Status | MB | Notes |
|---|---|---|---|---|---|---|---:|---|
| polyhaven/models | model | polyhaven.com/license | yes (CC0) | no | n/a | UNUSED directly; derived copies USED | 164 | `tools/blender/decimate_scans.py` → `generated/scan/*` (crates, baskets, ferns, moss rocks...). The 164 MB source is imported by Godot but never loaded |
| ambientcg (14 materials) | texture | docs.ambientcg.com/license | yes (CC0) | no | n/a | NOT-IMP; baked into `generated/` | 200 | Fabric061/066/083 in the villager atlas; others in `make_village_textures.py` / `make_nature_textures.py` |
| MakeHuman / MPFB2 data (not in repo) | base mesh, targets | github.com/makehumancommunity/mpfb2 (LICENSE.ASSETS.md / LICENSE.CODE.md) | yes: assets CC0, code GPLv3 | no | n/a | derived → `generated/characters` (USED) | – | `mh_core.py` only *reads* the CC0 data files and imports no MPFB (GPL) Python, so no GPL obligation |

### 2c. Imported but unused (no `.gdignore`, no reference)

| Pack | Type | Source URL | Lic ✓ | Attr | CRED | Status | MB | Notes |
|---|---|---|---|---|---|---|---:|---|
| 3dassets-dev-ai (11 packs: blacksmith-forge, canal-town, equestrian-yard, farm-livestock, castle-construction, monastery, rts-faction, siege-and-castle-defence, tournament, watermill, swords-shields) | model (AI) | 3dassets.dev/packs/... | no (only mmo-starter-realm page fetched; same site-wide CC0 statement on /about, fetched) | no | n/a | UNUSED | 90.9 | LICENSE.txt in each. AI-generated per our notes |
| ai3d/meshy/creatures | model (AI) + CC0 rigs | meshy.ai/terms-of-use; Quaternius UAA | yes | no | n/a | UNUSED | 20.1 | goblin, orc, troll, wolf, boar, bear, spider, wyvern: rigged and animated but no code loads them yet |
| ai3d/meshy/rigged | model (AI) | meshy.ai | yes | no | n/a | UNUSED (git-ignored, but Godot imports it locally) | 296.3 | Raw rigged/animation GLBs. Add a `.gdignore` |
| ai3d/meshy/_input, _previews | image | own/user | – | – | – | UNUSED | 85.3 | Concept inputs and renders. Add a `.gdignore` |
| quaternius/lowpoly-animated-knight | model | quaternius.com | not fetched (same CC0 License.txt as the others) | no | n/a | UNUSED | 8.1 | Only the dead constant `Assets.HELMET` (0 uses) |
| quaternius/lowpoly-medieval-weapons | model | quaternius.com | not fetched | no | n/a | UNUSED | 8.9 | |
| quaternius/modular-medieval-buildings | model | quaternius.com | not fetched | no | n/a | UNUSED | 0.9 | |
| opengameart/sfx: death-pain-grunts-thebardofblasphemy, male-yelling-haeldb, swishes-artisticdude | sfx | OGA (see `opengameart/LICENSE.md`) | not verified (OGA 502) | no (CC0 per notes) | n/a | UNUSED | 17.1 | |
| addons/sky_3d | code + textures | github.com/TokisanGames/Sky3D | yes (MIT; Milky Way CC BY 4.0 verified at eso.org/public/copyright) | **yes** (ESO) | **yes (added)** | enabled, not used by code | 12 | Exported anyway, so the credit is needed |
| addons/terrain_3d | code (C++) | github.com/TokisanGames/Terrain3D | yes (MIT) | MIT notice | yes (added) | enabled, not used by code | 44 | iOS binary missing |
| addons/limboai | code (C++) | github.com/limbonaut/limboai | yes (MIT; logo/demo art CC BY 4.0) | MIT notice | yes (added) | not enabled as a plugin, not used by code | 63 | iOS binary missing. The CC BY logo is editor-only |
| addons/road-generator | code | github.com/TheDuckCow/godot-road-generator | yes (MIT) | MIT notice | yes (added) | enabled, not used by code | 7 | |
| addons/proton_scatter | code | github.com/HungryProton/scatter | yes (MIT; demo textures from Textures.com, not redistributable standalone) | MIT notice | yes (added) | enabled, not used by code | 13 | Delete `demos/` (12 MB) |
| addons/dialogue_manager | code | github.com/nathanhoad/godot_dialogue_manager | yes (MIT) | MIT notice | yes (added) | autoloaded, not called | 2 | |
| addons/guide | code | github.com/godotneers/G.U.I.D.E | yes (MIT) | MIT notice | yes (added) | autoloaded, not called | 3 | |
| addons/quest_weaver | code | github.com/undomick/godot_nexus_quest_weaver | yes (MIT) | MIT notice | yes (added) | autoloaded; only mentioned in a comment (`hidden_triggers.gd`) | 4 | **No LICENSE file in repo** |
| addons/GodotGAS | code | github.com/yulrun/godot-gas | yes (MIT) | MIT notice | yes (added) | autoload `GameplayCueManager`; no ability code yet | 2 | |
| addons/gdUnit4 | code | github.com/MikeSchulze/gdUnit4 | yes (MIT) | MIT notice if shipped | n/a (tests) | tests only (7 test files) | 5 | Exclude from exports |

(Addons are counted in the addon line of the summary, not in the 20 unused packs.)

### 2d. Not imported (`.gdignore`)

| Pack | Type | Source URL | Lic ✓ | Attr | CRED | Status | MB | Notes |
|---|---|---|---|---|---|---|---:|---|
| ai3d/meshy/_raw | model (AI) | meshy.ai | yes | no | n/a | NOT-IMP (git-ignored) | 1,830 | Local only, never pushed |
| ambientcg | texture | ambientcg.com | yes (CC0) | no | n/a | NOT-IMP (source for baked textures) | 200 | see 2b |
| opengameart/models (26 folders: 3TD ruins/harbour/starter, longbow, archery set, battering ram, Freeciv units, cart, chicken, dog, church bell, carriage, knight statue, church + interior, hreikin props and tavern, System G6 props, weapon pack, merchant tent, modular castle kit, docks, old windmill, rigged horse, rooster, wooden bridge) | model | OGA (per-folder LICENSE.txt) | not verified (OGA 502). Freeciv units and rigged horse unclear | no (CC0 per notes) | n/a | NOT-IMP | 443 | Flag: Freeciv units, rigged horse |
| opengameart/cc-by (music ×8: Matthew Pablo, Zhelanov, Kraus, Yubatake, TAD; audio ×4; models ×8; NorthFantasyMusic, JC Sounds, Little Robot, congusbongus) | music/sfx/model | OGA (credit line in each LICENSE.txt) | not verified (OGA 502) | **yes** when used | not needed yet | NOT-IMP | 280 | Credit lines are already written in the LICENSE files |
| opengameart/music subfolders (free-music-pack, Dowland 1597, medieval-standoff, medieval-theme) | music | OGA | not verified | no (CC0 per notes) | n/a | NOT-IMP | 43.1 | |
| opengameart/sfx (12 folders: rubberduck ×4, 3-melee, battle-sfx-ogrebane, crowd, horse-trotting, rain, artisticdude RPG pack, sword-attacks-starninjas, voice-clip pack) | sfx | OGA | sword-attacks verified (same page as the clashes, CC0); rest not verified | no | n/a | NOT-IMP | 37.8 | |
| quaternius (19 packs: animated-men/women, background-posed-humans, lowpoly-animated-animals, lowpoly-farm-buildings, medieval-dungeon, medieval-village-megakit, pirate-kit, rpg-characters, ships, survival, textured-lowpoly-trees, ultimate-crops/food/modular-men/modular-ruins/modular-women/rpg-items/textured-buildings) | model | quaternius.com | pirate-kit and farm animals verified; others not fetched (all ship CC0 License.txt, free tier) | no | n/a | NOT-IMP | 492 | megakit 154 MB is the big one. Added the missing pirate-kit License.txt |
| kenney (26 packs: castle, cube-pets, cursor, fantasy-town, UI borders, game-icons, graveyard, impact/interface sounds, medieval-rts, mini-characters, mini-forest, modular-dungeon, music-jingles, nature, particles, pirate, retro-fantasy, rpg-audio, smoke, splat, survival, ui-audio, ui-pack-rpg, voiceover ×2, watercraft) | model/sfx/UI | kenney.nl/support | yes (CC0, site-wide) | no | n/a | NOT-IMP | 86 | License.txt in each |
| kaykit incoming (9: character-animations, skeletons, dungeon-remastered, fantasy-weapons, forest-nature, furniture, resource, restaurant, rpg-tools) | model/anim | kaylousberg.itch.io / KayKit GitHub | forest verified (CC0; asks not to resell unmodified copies); others not fetched | no | n/a | NOT-IMP | 57 | License.txt in each |
| polypizza (76 models, cc0 + cc-by) | model | poly.pizza (per-model URLs in LICENSE.md) | not verified per model | **yes** for cc-by | n/a | NOT-IMP | 20 | 47 CC-BY rows, credits in LICENSE.md |
| armor/opengameart (17 pieces except the Anglo-Saxon helmets), armor/kaykit, armor/polypizza, armor/quaternius | model | see `armor/README.md` | not verified (OGA 502) except the Knights kit | **yes** for cc-by | lines in armor/README | NOT-IMP | 55 | |
| characters/_library (UAL extra clips), mesh2motion, oga-cdmir-kelgar, oga-system-g6-modular-rpg | anim/model | github.com/Mesh2Motion/mesh2motion-app; OGA | yes (Mesh2Motion: code MIT, art CC0; OGA via Wayback) | no | n/a | NOT-IMP | 64 | The 166 extra UAL clips are ready but not in `UAL_FILES` |
| animals/_sources, _tools, _previews; armor/_tools, _previews; characters/_tools, _previews; incoming/_previews | tools/renders | own | – | – | – | NOT-IMP | 25 | |
| incompetech (12 Kevin MacLeod tracks) | music | incompetech.com/music/royalty-free/licenses/ | partly (page says CC "credit the music"; version not shown). LICENSE.txt says CC BY 4.0 | **yes** | not needed yet | NOT-IMP | 71 | |
| music-cc-by (Scott Buckley ×2, Alexander Nakarada ×2) | music | scottbuckley.com.au/library ; free-stock-music.com | Buckley yes (CC BY 4.0); Nakarada not fetched | **yes** | not needed yet | NOT-IMP | 29 | |
| game-icons (4000+ SVG) | icon | game-icons.net | yes (CC BY 3.0) | **yes** | the 11 used are credited | NOT-IMP | 17 | |
| fonts (Cinzel, IM Fell English + SC, MedievalSharp, Almendra) | font | Google Fonts | Cinzel yes (OFL); others not fetched | OFL notice | Cinzel yes | NOT-IMP | 2 | The used Cinzel copy is in `assets/ui/fonts` |
| creatus/knight-pack-1 | model | linktr.ee/creatus (Licence.txt in repo) | not verified (itch URL 404) | no (CC0 per file) | n/a | NOT-IMP | 26 | 15-29k tris, over budget |
| styloo/the-company | model | styloo.itch.io/company | yes (CC0) | no | n/a | NOT-IMP | 24 | |
| chilly-durango/retro-medieval-building-kit | model | chilly-durango.itch.io/medieval-building-parts | yes (CC0) | no | n/a | NOT-IMP | 4 | |
| fertile-soil/modular-village-pack | model | fertile-soil-productions.itch.io/modular-village-pack | yes (CC0) | no | n/a | NOT-IMP | 7 | |
| lowpolyassets/low-poly-medieval-weapons | model | lowpolyassets.itch.io/low-poly-medieval-weapons | yes (CC0) | no | n/a | NOT-IMP | 3 | |
| cc0gameassets/swordtember2022 | model | cc0gameassets.itch.io/swordtember2022 | yes (CC0) | no | n/a | NOT-IMP | 2 | |
| shaders/pixelart-outline-leopeltola | shader | github.com/leopeltola/Godot-3d-pixelart-demo | not fetched (search result says MIT; LICENSE in repo is MIT) | MIT notice | n/a | NOT-IMP | 1 | `kingdom/shaders/*` are our own (no ported code found) |

### 2e. Our own content (no third-party licence)

| What | Where | Notes |
|---|---|---|
| 60+ Blender-scripted buildings, props, interiors, nature, runestone | `kingdom/assets/generated/` (179 MB), `kingdom/tools/blender/make_*.py` | Own code. Textures are baked from CC0 ambientCG / Poly Haven |
| MakeHuman villagers on the UAL rig | `generated/characters/` | From CC0 MPFB2/MakeHuman data; no GPL code used |
| Procedural animals, spider/wyvern rigs | `animals/procedural`, `ai3d/meshy/creatures` | Own scripts |
| Shaders | `kingdom/shaders/*.gdshader`, `generated/nature/foliage_wind.gdshader` | Own work (headers checked; no attribution or port notes) |
| Meshy AI models | `ai3d/meshy/` | Paid plan: we own the output (see red flag 3) |

---

## 3. Code and projects we built on

| Project | Licence (verified) | What we used | Does the code exist in `kingdom/`? |
|---|---|---|---|
| godotengine/tps-demo | Code MIT; art CC BY 3.0; music CC BY 3.0 | Trauma-based camera shake; AnimationTree blend pattern | **Yes:** `scripts/actors/camera_shake.gd` (header credits it) and `player.gd:55` uses it. No art taken. MIT notice now in CREDITS |
| GDQuest/godot-4-3d-third-person-controller | Code MIT; **art CC BY-NC-SA 4.0** | Reference only (camera-relative movement, facing) | No copied code or art found (grep for gdquest/sophia: only a comment in `character_animator.gd`). Never import its art |
| Mesh2Motion/mesh2motion-app | Code MIT; art CC0 | Rigs, horse, CMU-derived mocap clips | Assets only (`characters/mesh2motion`, `_library`); no Mesh2Motion code in the game |
| Quaternius UAL skeleton | CC0 | The master skeleton; our retarget and rebind tools (`characters/_tools`, `tools/blender/ual_rig.py`) | Yes, as data. The tools are ours |
| makehumancommunity/mpfb2 | Assets CC0; code GPLv3 | Base mesh, targets, masks | Data only. `mh_core.py` imports only gzip/json/numpy (no MPFB modules), so the GPL doesn't apply |
| peter-kish/gloot | MIT | Inventory | **Used** (`autoload/life.gd`, `Inventory.new()`) |
| nathanhoad/godot_dialogue_manager | MIT | Dialogue | Autoloaded; no `.dialogue` files or calls yet |
| undomick/godot_nexus_quest_weaver | MIT | Authored quests | Autoloaded; mentioned in a comment only |
| godotneers/G.U.I.D.E | MIT | Input | Autoloaded; no `GUIDEAction` resources used yet |
| yulrun/godot-gas | MIT | Abilities/effects | Autoload + `kingdom/godot_gas/` tag registry; no abilities in game code yet |
| limbonaut/limboai | MIT | Behaviour trees | Not referenced (0 `BTPlayer`/`LimboHSM`) |
| TokisanGames/Terrain3D | MIT | Terrain | Not referenced (terrain is our `terrain_streamer.gd`) |
| TokisanGames/Sky3D | MIT (+ ESO CC BY 4.0 texture) | Sky | Not referenced (the sky is a Poly Haven HDRI in `main.gd`) |
| TheDuckCow/godot-road-generator | MIT | Roads | Not referenced |
| HungryProton/scatter | MIT | Scatter | Not referenced (scatter is our MultiMesh code) |
| MikeSchulze/gdUnit4 | MIT | Tests | Used by 7 tests in `kingdom/tests` |
| In `OPEN_SOURCE_REFERENCES.md` but not in the repo: beehave (rejected in favour of LimboAI), godot-statecharts (MIT, verified), phantom-camera (MIT, verified), godot-motion-matching, expressobits character-controller, Kenney starter kits | – | Ideas only | Not present; nothing to check |

**Bottom line:** the only third-party *code* running in game logic today is GLoot, the TPS-demo camera shake, and the
autoload bootstraps of Dialogue Manager, G.U.I.D.E, QuestWeaver and GodotGAS. Six addons (LimboAI, Terrain3D, Sky3D, Road
Generator, ProtonScatter, plus GodotGAS beyond its autoload) are adopted on paper (`DEPENDENCIES.md`) but not wired into
gameplay yet.

---

## 4. Recommended next pulls (licence verified this session)

1. **Quaternius *Ultimate Monsters*** (quaternius.com/packs/ultimatemonsters.html, **CC0**, "fully animated", glTF).
   Fifty animated monsters in the same Quaternius family we already use, which gives far more enemy variety than the 8
   Meshy creatures. Check it for an orc or humanoid brute (the page doesn't list species).
2. **godot-sqlite** (github.com/2shady4u/godot-sqlite, **MIT**, Android arm64 and **iOS arm64** binaries). This is the
   planned authoritative world-state store in `DEPENDENCIES.md` and fits the "systems stay ours" rule. On mobile, copy the
   DB to `user://`.
3. **Phantom Camera** (github.com/ramokz/phantom-camera, **MIT**, Godot 4.4+). Framing, transitions and cutscenes for
   the birth cutscene, dialogue and battles. It was on hold for one editor-start error, so retest the latest release on
   4.6.2.
4. **SimpleGrassTextured** (github.com/IcterusGames/SimpleGrassTextured, **MIT**, built for Godot 4). Painted and
   baked grass with LOD and a shadow toggle. Mobile support isn't stated, so profile it against our `grass.gdshader`
   before adopting.
5. **More UAL clips:** first wire in what's already here. `characters/_library/` holds **166 extra CC0 clips** (bow,
   climb, dodge, deaths, two-handed, crossbow, fishing, social; Mesh2Motion and System G6 were verified CC0) that aren't in
   `Assets.UAL_FILES` yet. For more, the Quaternius UAL1/UAL2 **Pro/Source** tiers are paid; the pages list the Pro tier
   as free to use in commercial projects. The FAQ doesn't cover redistributing paid files, so keep them out of the public
   repo until confirmed.

Also worth a look: **Spatial Gardener** (MIT, Godot 4.2+; overlaps ProtonScatter), **Waterways** (MIT; Godot 4
support unclear from the README), **godot-statecharts** (MIT; overlaps LimboAI's HSM).

- **Riding animations:** no free, redistributable rider clips turned up in this session either. Meshy's own gallery
  models are advertised as CC0, but that was a search result, not a fetched page. Options: author `Ride_Idle`/`Ride_Trot`/
  `Ride_Gallop` on the UAL rig in Blender and mount on the Mesh2Motion or Quaternius horse, or try Meshy's paid-plan
  animation library.
- **Terrain3D-type, dialogue and quest addons:** already vendored (Terrain3D, Dialogue Manager, QuestWeaver). The win now
  is wiring them in, not pulling more.
- **Audio:** the repo already holds a lot of unused, verified or documented audio (BigSoundBank horse, anvil and bells;
  Kenney RPG audio; OGA footsteps and gallop (CC-BY)). Wire these in before sourcing more.

---

## 5. Cleanup (candidates only; nothing was deleted)

Biggest wins first. "Repo" = saves git size; "APK" = stops Godot exporting it (no export filter exists yet).

| Candidate | MB | Status | Why | Saves |
|---|---:|---|---|---|
| `ai3d/meshy/_raw/` | 1,830 | NOT-IMP, git-ignored | Raw Meshy downloads; local only | PC disk |
| `opengameart/models/` | 443 | NOT-IMP | Style clashes (README), mixed or unverified licences (Freeciv, rigged horse) | Repo |
| `ai3d/meshy/rigged/` | 296 | UNUSED, git-ignored but **imported** | Add a `.gdignore` (the creatures are already merged into `creatures/`) | PC import time |
| `quaternius/modular-character-outfits-fantasy/` | 282 | USED (4 outfits) | 126 MB `Textures/`; keep only Peasant/Ranger files | Repo + APK |
| `opengameart/cc-by/` | 280 | NOT-IMP | CC-BY obligations and unused; keep only what gets wired in | Repo |
| `ambientcg/` | 200 | NOT-IMP | Already baked into `generated/`; keep only if the Blender scripts are rerun | Repo |
| `polyhaven/textures/` | 202 | USED (5 of 22) | Remove the 17 unused sets or `.gdignore` them | Repo + APK (~150) |
| `polyhaven/models/` | 164 | imported, only derived copies used | `.gdignore` it (decimate_scans reads it outside Godot) | APK |
| `quaternius/medieval-village-megakit/` | 154 | NOT-IMP | Unused | Repo |
| `quaternius/universal-base-characters/`, `ultimate-animated-character/` | 125 + 101 | USED (few files) | Prune to the files referenced | Repo + APK |
| `3dassets-dev-ai/` (11 unused packs) | 91 | UNUSED | AI-generated, "blocky" per README; `.gdignore` or delete | Repo + APK |
| `polyhaven/hdris/` (4 unused 4K HDRIs) | ~70 | USED (1 of 5) | Keep one or two | Repo + APK |
| `kenney/` | 86 | NOT-IMP | Toy style, unused | Repo |
| `incompetech/` | 71 | NOT-IMP | Unused; CC-BY credits needed if used | Repo |
| `addons/limboai` + `addons/terrain_3d` | 63 + 44 | not used by code | Keep if planned; otherwise remove until needed. iOS binaries missing | Repo + APK |
| `ai3d/meshy/_input` + `_previews` | 85 | UNUSED, imported | `.gdignore` | APK |
| `opengameart/sfx` 3 unused imported folders | 17 | UNUSED | `.gdignore` | APK |
| `addons/proton_scatter/demos/` | 12 | shipped | Textures.com licence (red flag 6) | APK + licence |

The first step for shipping is an **export preset with an include/exclude filter** (for example, exclude
`assets/incoming/*` except the used folders, plus `addons/gdUnit4/*`), so nothing unused reaches the store build even
before any deletion.

---

## 6. Changes made by this audit

- **New:** `docs/OPEN_SOURCE_AUDIT.md` (this file).
- **New:** `kingdom/assets/incoming/quaternius/pirate-kit/License.txt` (CC0, verified).
- **Appended to** `kingdom/CREDITS.md`: the Dejawolf courtesy credit, the ESO/S. Brunier Milky Way (CC BY 4.0) credit,
  and MIT notices for Godot, the TPS-demo port and the 10 shipped addons.
- **README fixes:** `incoming/characters/README.md` (the `.gdignore` statement was stale: g6-ual and cdmir-ual are now
  used); `incoming/README.md` (the "addons not vendored" heading was stale).
