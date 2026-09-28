# Local PC session ↔ cloud session: coordination

The user runs **two Claude sessions on this branch at the same time**: the cloud session and a local PC session (with GPU, Blender GUI access and the Meshy MCP). This file keeps them from stepping on each other. **Read it after every pull.**

## Split of work (from 2026-09-27)
| Area | Owner | Notes |
|---|---|---|
| Game code, world layout, placing assets in scenes, lighting and grading | **cloud** | Keep doing what you're doing |
| New 3D assets (Meshy, Blender, open-source sourcing), optimization, previews | **local** | Only adds new files under `kingdom/assets/incoming/`, `kingdom/assets/generated/`, `tools/`, `docs/asset_gallery/` |
| Interiors (inn, blacksmith, guild, healer, houses) | **local** builds the room scenes in `kingdom/scenes/interiors/` (new files) | **cloud** wires the door triggers into the world (the local side will leave a small, self-contained `interior_door.gd` you can drop in) |

Rules:
- The local session **doesn't edit** existing game scripts or scenes unless this file says otherwise. If the local side needs a hook, it writes the request here instead.
- Both sides: `git fetch`, then merge before pushing (the cloud session pushes often).

## Ready for the cloud to integrate
Everything below is optimized for mobile, licence-checked (CC0/MIT, or CC-BY with credit), and has previews in `docs/asset_gallery/index.html`.

- `incoming/ai3d/meshy/`: 5 house types (`house_peasant_a/b`, `house_family`, `house_trader`, `house_manor`) and 2 market stalls, each with `_lod0`/`_lod1`. **These replace the Blender village houses.** Use the same near/far LOD swap as the hero buildings.
- `incoming/ai3d/meshy/creatures/`: goblin, orc, troll, wolf, boar, bear, spider and wyvern (rigged; clips idle/walk/run/attack/hit/death; `_lod1` files). Meshy bipeds have empty hands, so attach weapons to `RightHand`.
- `generated/props/`: 21 upgraded village props sharing `props_atlas.png` (replaces the old lamp post, notice board, signpost and fence).
- `incoming/characters/`: more NPCs on the UAL skeleton (G6, CDmir) plus 166 extra UAL clips. See the "Recommendation" section of its README for the `Assets.UAL_FILES` lines.
- `incoming/animals/`: 26 CC0 animals.
- `incoming/armor/`: armor library. Most plate pieces are off-style; armored characters are coming from Meshy instead (below).
- **Landmarks** in `incoming/ai3d/meshy/`: `landmark_runestone` (8k/2.5k tris; replaces the Blender runestone across the runestone network; its glowing channels suit an emissive pulse tied to stone power/condition), `landmark_rift` (the Rift entrance, 20k/6k), `landmark_watchfort` (frontier outpost with tower and palisade, 40k/12k). Each has `_lod0`/`_lod1`.
- **Region 1 assets** in `generated/region/` (all procedural Blender scripts, no third-party content): **nature** (5 painterly oaks/beeches, 2 spruces + Scots pine, dead snag, dark oak, 4 bushes, grass/flower clumps, 2 ferns, 4 rocks, mossy stumps and logs; trees 650–1600 tris LOD0, ≤ 482 LOD1, plus a 4-tri `_lod2` impostor; one 1024 foliage atlas, alpha scissor), **farm** (barn, granary, windmill + separately rotating `windmill_sails` at the `sail_hub` empty, chicken coop, pig sty, wheat and cabbage rows, 3 fence pieces, scarecrow, hay wagon), **mine** (entrance in a rock face with timber supports and track, rail straight/curve/end, cart, 3 ore piles, head-frame winch, miner's log hut, tunnel support, yard props), **road** (roadside inn, wayshrine, milestone, stone + wooden bridge, checkpoint barrier + separate `checkpoint_boom`, toll booth, covered caravan wagon), **ruins** (collapsed tower, overgrown shrine, bandit tent/lean-to/campfire/stash/palisade, 2 goblin totems). Every asset has `_lod1`. **Wind:** nature GLBs carry COLOR_0 = R sway, G phase, B AO, and their `.glb.import` files already swap in the wind ShaderMaterials (`generated/region/nature/*.tres`), so don't run them through `Assets._windy_leaves()` / `tree_wind.gdshader`. Sets 2–5 use COLOR_0 as a normal tint (default import). Details, markers, rails/bridge orientation, LOD distances: `kingdom/assets/generated/region/README.md`. Previews: `docs/kingdom/blender_previews/region_{nature,farm,mine,road,ruins}_sheet.png` and `region_forest_scene.png` (the style check next to the Meshy house).
- **Interiors ready.** `scenes/interiors/{inn,blacksmith,guild,healer,house}_interior.tscn` (the house one is shared by all 5 house types). Each has 23k–58k tris, 4 materials, vertex-baked lighting, at most 2 unshadowed OmniLights, box colliders, `PlayerSpawn`, an `ExitDoor`, and `NPC_*` markers. To wire them, drop an `Area3D` with `scripts/interiors/interior_door.gd` on each building door and set `interior_scene`. Exact code, the building→scene table and how it works: `kingdom/scenes/interiors/README.md`. Previews: `docs/kingdom/blender_previews/_interiors_sheet.png`. Rebuild with `tools/blender/make_interior_*.py`.
- **More monsters (CC0, harmonised)** in `incoming/monsters/quaternius/`: `giant_rat` and `blight_rat` (cellars and mines; dark-forest variant with ember eyes), `bog_toad` (marsh), `giant_wasp` (forest; hovers 1.2 m up), `ghoul` (Rift-risen dead, violet eye glow), `fungal_brute` and `blackcap_brute` (deep forest and caves), `rift_slime` and `rift_wraith` (Rift creatures with a cyan emissive texture). Each is ≤ 8k/2.5k tris (`_lod1`), 512 px painted texture, ≤ 40 bones. Clips are named like the Meshy creatures (`idle/walk/run/attack/hit/death`); a few hit, death and alias clips are synthesised and flagged in the README. The folder has a `.gdignore`, so remove it when wiring. Roles, habitats, danger tiers, sizes and known limits (wasp death ends in mid-air, brute death sinks 0.2 m): `kingdom/assets/incoming/monsters/README.md`. Previews: `incoming/monsters/_previews/monsters_lineup.png` and `monsters_poses.png`. Rebuild with `tools/monsters/`.

## In progress on the local side
- Done: armored characters (`incoming/ai3d/meshy/armored/`; the cloud has already wired them) and interiors (above). **Cloud: please wire the door triggers** with `interior_door.gd` on the inn, blacksmith, guild, healer and the 5 house types (see `kingdom/scenes/interiors/README.md`), and call `InteriorDoor.active.leave()` on player death.
- **NOW (2026-09-28, user priority): the local side owns FRAME RATE / LAG.** The goal is the highest fps and no hitches on every tier. The local side profiles on the real GPU and changes whatever costs frames (CPU scripts, streaming, rendering, assets) in small commits merged from origin first. Cloud and Codex: keep building features, but if you touch `population_lod.gd`, `terrain_streamer.gd`, `settlement_builder.gd`, `region_dressing.gd`, `assets.gd`, `quality.gd` or `world_sim.gd`, fetch first and keep changes small. **Avoid per-frame work in `_process` / `_physics_process`: prefer timers or slices, and cache node lookups.** Results go into `docs/qa/PERFORMANCE.md`.

- **2026-09-28 (user request to the cloud session): the cloud is editing animation-adjacent code right now.** That covers foot IK and spring bones (new `scripts/actors/procedural_rig.gd`, hooks in `player.gd` / `character_animator.gd`), ragdolls (new `scripts/actors/ragdoll.gd`, hooks in `monster.gd`, `wolf.gd`, `army/soldier.gd`, plus Jolt in `project.godot [physics]`), and new free animation clips retargeted to UAL (`assets/incoming/animations/`, the `Assets.UAL_FILES` section). Codex: please fetch before touching those files. Clip choice and locomotion tuning stay with Codex.

## Merge etiquette (learned 2026-09-27)
A local Godot import creates `.import` files and extracted textures that the cloud side also commits. If a merge aborts with "untracked working tree files would be overwritten", delete only the listed `.import`/`.jpg` files (they're regenerated) and merge again.

## Requests for the cloud session
- **UPDATE 2026-09-27: the user asked the LOCAL session to do items 1–4 below itself, plus a "runs on any phone" pass** (automatic quality tiers for low-end, mid and high phones, the Compatibility renderer fallback, render scale, LOD, shadow, NPC-density and FPS settings, and Android/iOS export presets). **Cloud: please don't start these.** The local side makes small, focused commits and merges often. If you touch `project.godot`, export presets or the settings menu, fetch first.
- **From `docs/OPEN_SOURCE_AUDIT.md` (store-release blockers, game-code side):**
  1. Add an in-game **Licences/Credits screen** that shows `kingdom/CREDITS.md`. The MIT notices for Godot and the addons, and the CC-BY credits, must ship with the app.
  2. Add an **export preset** that excludes `assets/incoming/**` packs the game doesn't load (about 528 MB imported but unused) and the Poly Haven model sources. Otherwise the store build bloats by about 700 MB.
  3. **LimboAI and Terrain3D** point at iOS binaries that aren't in the repo. Disable those plugins until they're used, or the iOS export fails.
  4. Wire in the 166 extra CC0 UAL clips already in `incoming/characters/_library` (dodges, deaths, bow, climb, two-handed, social). The clip list is in the "Recommendation" section of `characters/README.md`.
  (The local side already added the missing gloot and quest_weaver LICENSE files and removed `proton_scatter/demos` because of its non-redistributable textures.)
- Place the new houses, stalls, props, animals and monsters when convenient. When they're in, add a note here so the local side can check the look on a real GPU.
- **From the playtest bot (2026-09-27, `docs/qa/PLAYTEST_REPORT.md`; re-run with `kingdom/tools_qa/autoplay/run_autoplay.sh`).** Already fixed by the local side (small commits): off-screen HUD menus (`hud.gd`), tap-to-skip cutscenes (`cutscene_player.gd`), and the chase camera going inside walls (`player.gd`, ray pull-in). Still open, for the cloud:
  1. **Wire the interior doors.** There are 0 `InteriorDoor` nodes in the world. Also move the innkeeper Station away from the inn door (it stands 5.2 m out, so E opens the inn menu instead of the door), or put her inside at `NPC_Innkeeper`.
  2. **The death pose doesn't read.** `UAL_Extra_Mesh2Motion.glb` has its own 4.46 s `Death_A`, which wins over the `Death_A → Death01` alias in `Assets._ual_for` (the aliases only fill missing names). The player is still upright 1.2 s after dying and respawns at 3 s. Let gameplay aliases take precedence, or play `Death01`.
  3. **Foliage covers the camera in forest fights** (report shots 33–37). Trees have no colliders, so the new camera ray can't help. Fade leaves near the camera, or sphere-cast against the trunks.
  4. **Balance.** The player died in all 4 fights. Wounded wolves (< 15 hp) flee at 8 m/s, faster than the player's 7 m/s run, so they can never be finished (`wolf.gd` `_decide`). A whole goblin warren aggros at once.
  5. **Ashford has no blacksmith building** (no `blacksmith` lot) although the Smithy hires and NPCs are labelled "Blacksmith".
  6. The raider banner "☠ 12" (`squad.gd:109`) shows through everything: in the birth cutscene sky, over the plaza, at the warren. Hide it in cutscenes, or fade it by distance.
  7. Renting a bed at 19:30 wakes you at 01:33 "rested". Wake at the next morning.
  8. The child's first frame after the birth cutscene faces the family house wall (`main.gd` `_after_birth` teleports with yaw 0 toward the house). Face the street.
- **For the local quality/anim agents (their uncommitted work, not touched by the bot):** `quality.gd:214` calls `RenderingDevice.get_device_type()`, which doesn't exist in 4.6 (a SCRIPT ERROR at boot), so an RTX 4070 gets the **Low** tier (30 fps cap, 540p 3D, sprite villagers at 4 m). `RenderingServer.get_video_adapter_type()` is the 4.6 call. Separately, `_library/.gdignore` is still committed while `assets.gd` loads `UAL_Extra_*.glb` from that folder. On a clean checkout that means `No loader found` in `_ual_for` and **every character T-poses** (seen in the first bot run). Commit the `.gdignore` removal together with the 4 `.import` files.
- **2026-09-27: CANCELLED. Local will NOT do the locomotion speed / foot-slide fix.** The user assigned all animation work (locomotion speed, foot slide, clip choice such as Death_A vs Death01, blend times) to a separate **Codex** session. Findings and suggested values for it are in `docs/qa/anim_qa_report.md` ("For the cloud session"). The local side stays out of `character_animator.gd`, `player.gd`, `villager.gd`, `soldier.gd`, `wolf.gd`, `monster.gd` and `critter.gd` animation code.

## Audio and atmosphere (local, 2026-09-27)
New sound set in `kingdom/assets/audio/` (music, 14 ambience loops, ambience spot sounds, footsteps by surface, combat, creatures, farm animals, UI; all CC0 except two CC-BY packs credited in `CREDITS.md`). List, sources, licences, loudness and loop points: `kingdom/assets/audio/README.md`. Rebuild: `py tools/audio/build_audio.py`.

**Wired (the only edit to existing files is one line in `project.godot`):**
`Audio="*res://scripts/audio/audio_director.gd"` (was `res://autoload/audio.gd`). The director keeps the old API (`Audio.listener`, `Audio.set_mood()`, `Audio.sfx("swing"|"hit"|"clash"|"bell", pos, db)`), so `main.gd`, `player.gd`, `wolf.gd` and `soldier.gd` work unchanged. To roll back, restore that line; `autoload/audio.gd` is untouched. Also new: `kingdom/default_bus_layout.tres` (Master with a hard limiter, Music, Ambience, SFX, UI, Interior = light reverb sending to SFX).

What it does on its own: ambience bed + music from location (inn/smithy/healer/guild/house interior via `InteriorDoor.active`, monster camp, town, danger > 55 threat, forest, water, open meadow) and time of day, with crossfades; random spot sounds (rooster, hammering, well bucket, owls, distant howls, glass clinks, anvil, pages...); player footsteps from `WorldGen.color_at()` (cobble/dirt/stone/leaves/grass, wood or stone inside); positional 3D SFX (it sets `audio_listener_enable_3d` on the game SubViewport; tested: panning and distance work) capped at 12 voices with oldest-voice stealing; creature hurt/death sounds by polling nearby combatants' `health`; creature and farm-animal idle voices (`Critter.kind`, `CampMonster.species`, `Wolf`); a click on every `BaseButton`; coin and level-up from `Game.stats_changed`; the town bell at 7/12/18 h; door sounds from `InteriorDoor` signals. `Audio.set_weather("rain"|"storm"|"wind"|"")` is ready for a weather system. Debug builds print `[audio]` lines (bed/music changes, a 30 s play count).

**Optional call sites for the cloud / Codex sessions** (better timing and material than the polling; all names exist):
- `player.gd:292` swing: `Audio.play_sfx("swing_heavy" if _combo == COMBO.size() - 1 else "swing", global_position, -4.0)`.
- `player.gd:324` hit: `Audio.play_sfx("hit_flesh", enemy.global_position)` per enemy hit (use `hit_metal` for armored targets, `hit_wood` for shields/props).
- `player.gd:363` block: `Audio.play_sfx("block", global_position)`. `player.gd:329` `dodge()`: `Audio.play_sfx("dodge", global_position)` (the director currently infers it from `_dodge`). `player.gd:345` hurt/death: `player_hurt` / `player_death` (inferred from `health` today).
- `wolf.gd:122` attack: `Audio.play_sfx("wolf_growl", global_position)`; `wolf.gd:129`/`:139` hurt/death: `wolf_hurt` / `wolf_death`.
- `monster.gd:217` attack: `Audio.play_sfx("orc_roar" if species == "orc" else "goblin_chatter", global_position)`; `monster.gd:241` `"%s_hurt" % species`; `monster.gd:260` `goblin_death` / `monster_death`. Meshy creatures when they land: `boar_squeal`/`boar_grunt`, `bear_roar`/`bear_growl`, `spider_hiss`, `wyvern_screech`, `wolf_howl`.
- `hud.gd:279` `show_menu`: `Audio.play_ui("open")`; `hud.gd:285` `close_menu`: `Audio.play_ui("close")`. `adventurer_guild.gd:409` / `scouts.gd:206` accept: `Audio.play_ui("quest_accepted")`; quest done: `quest_complete`; refused purchase/action: `error`; death screen: `defeat`.
- Bows (none yet): `bow_shot`, `arrow_hit`. Settings menu: bus volumes are `AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"|"Ambience"|"SFX"|"UI"), db)`.

**Export:** ship `assets/audio/**` (about 25 MB). `assets/incoming/audio/` has a `.gdignore`. After this swap the game no longer loads `incoming/opengameart/music`, `incoming/opengameart/ambience` or `incoming/bigsoundbank`, so the export filter can drop them.

## Release + any-phone pass: DONE by the local session (2026-09-27)
Commits 62c06d0e, 13c66309, 63db0337, 82f50dca, 77a1c958 and the perf/doc commit after them.
- **Quality autoload** `scripts/core/quality.gd` (LOW/MEDIUM/HIGH/ULTRA + AUTO with device detection and a
  20 s frame-time adaptation). It adjusts nodes as they enter the tree (viewport scale/AA/LOD, environment
  effects, sun and lamp shadows, visibility ranges, grass/undergrowth thinning, particles), so new game code
  usually needs nothing. Game code reads `Quality.npc_full`, `Quality.npc_sprites` (PopulationLOD) and
  `Quality.view_radius` (main.gd); react to runtime changes with `Quality.changed`. `--quality=low` forces a tier.
  Tier table and numbers: `docs/qa/PERFORMANCE.md`.
- **Settings & Credits** (Pack menu): tier override, 30 fps battery saver, and the Credits & Licences screen
  (`scripts/ui/settings_menu.gd`, `scripts/ui/credits_screen.gd`). Bus volume sliders could go in the same menu.
- **Plugins:** LimboAI and Terrain3D are disabled with a `.gdignore` in their folders and Terrain3D is removed
  from `editor_plugins` (no game code used them; their iOS and armv7 binaries are missing). To use one later,
  delete its `.gdignore`, re-enable it, and add the missing platform binaries before exporting.
- **Export presets** `kingdom/export_presets.cfg` (Android arm64+armv7, iOS). The `exclude_filter` drops the
  unused packs: **if game code starts loading something under an excluded path, remove that entry** (e.g. the
  Meshy creatures are *included*; the 11 unused 3dassets-dev-ai packs, Poly Haven models, unused HDRIs and
  textures, `ai3d/meshy/rigged|_input|_previews`, `armored/_work` are excluded). How-to and signing:
  `docs/RELEASE.md`.
- **Extra UAL clips** are in `Assets.UAL_FILES` (221 clips, 0 unresolved; `tools/qa/bench/check_clips.gd`).
  Clip-choice fixes (e.g. the extra `Death_A` shadowing the `Death_A -> Death01` alias) are left to the
  animation (Codex) session as the user asked.
- **Perf fixes in shared code:** `Assets._transformed` now builds meshes through `ImporterMesh.generate_lods()`
  (merged trees/buildings had lost their LODs: 13 M -> 5 M primitives at HIGH); ImpostorBaker's viewport idles
  between bakes. Cloud: when you add a new big mesh path, going through `Assets.building_mesh/nature_mesh`
  keeps the LODs.
- **For the cloud (optional):** main.gd `_build_environment()` still enables SDFGI/SSIL/volumetric fog before
  Quality turns them off, which prints harmless "only available in Forward+" warnings on phones.

## Low-end phone budget pass: DONE by the local session (2026-09-27)
Numbers and details: `docs/qa/PERFORMANCE.md` ("Low-end budget pass"). Village LOW: 0.83 M -> 0.29 M
primitives, 336 -> 294 draws (234 without HUD), ~121 MB textures in the phone export. Notes for the cloud:
- **Buildings:** `Assets.BUILDINGS` entries may now carry `lod2`/`lod3` pairs (`[lod0, size, lod1, d1, lod2, d2, lod3, d3]`);
  `building_lod_level_mesh/_distance()`. Meshy meshes skip `generate_lods()` (they have their own LOD files). On LOW,
  `SettlementBuilder` never loads LOD0 of buildings that have a LOD2. Buildings with a LOD3 and greenery are batched per
  40 m cell. New Meshy LODs: `tools/meshy/bake_lod.py` (voxel + bake; doesn't shred), check with `tools/meshy/compare_lods.py`.
- **Trees:** forest and village greenery use `region/nature/*` trees via `TerrainStreamer.region_tree_chain()`;
  `Assets.nature_mesh("region/...")` applies the wind materials itself (the region `.glb.import` files don't).
- **Textures:** new glTF/texture imports come in Lossless (4 B/px on phones) because nobody opens them in the editor.
  After adding assets run `py tools/qa/texture_vram.py --write` and reimport. `addons/mobile_texture_limit` caps textures
  at 1024 px (512 for scans/animals) in Android/iOS exports only; keep it enabled.
## Codex natural-world/animation handoff (2026-09-27)

The separate `gpt/ai3d-assets` branch has merged the latest Claude performance and audio commits. It keeps the Codex gait calibration and near-actor collision work, and adds eased starts/stops/turns for roaming animals plus a Blender-derived fox gallop. Read `docs/concepts/NATURAL_WORLD_CLAUDE_HANDOFF.md` for the implementation sequence and `docs/qa/animal_fox_review.html` for the source/derived animation comparison. The original fox GLB is unchanged; its derived clip reduces measured Tail1 stretch from 30.3% to 1.7%. Fox Run speed is still not verified by the foot-contact sampler. Please preserve the source asset and keep the remaining QA failure visible during future merges.

## Cloud session: placed (please check the look on a real GPU)

- **Region sets** are placed by `scripts/world/region_sites.gd` (planning, in `WorldGen.setup`, clears and
  levels ground) and `region_dressing.gd` (builds within 240 m, LOD1 past 55 m):
  - a farmstead with a turning windmill outside every village
  - bridges where roads cross water
  - Cinderpost Waystation
  - waystones and wayshrines along the roads
  - the Shrine of the Sleeping Flame and Whisper Hollow
  - a bandit camp in Duskbriar
  - the collapsed tower west of Ashford
  - Greyseam Mine in the northern hills
  - Ember Watch (Meshy watchfort, 15 m)
  - the Rift (Meshy, 10 m, violet light)
- **Meshy runestone** replaces the Blender one in `frontier_presence.gd` (3.4 m, LOD1 past 60 m).
- **Upgraded village props** (`generated/props`): lamp post, signpost, barrel, crate, bench, hay bales, plus
  new keys in `Assets.BUILDINGS`.
- **Interiors** are wired on every building (see `scenes/interiors/README.md`).


## Cloud session, 2026-09-28: new systems to check on a real GPU and phone
All are merged on `claude/focused-curie-m09hbd` and `main` (214 GdUnit tests pass). Cost notes are the cloud's
estimates; the local side owns the real numbers.
- **World:**
  - weather (`scripts/world/weather.gd`: mist, rain, storm with lightning, wet terrain);
  - seasons (`scripts/sim/seasons.gd`, global shader params `season_tint`, `autumn_amount`, `winter_amount`, `snow_amount`, `bloom_amount`; force one with `--season=autumn`);
  - GPU ambience (`scripts/world/ambient_fx.gd`: flocks, fireflies, butterflies, leaves, motes, embers, fish);
  - grass trampling and water ripples (`grass_interactors.gd`, eight `ashes_interactor_*` globals);
  - Jolt physics (`project.godot [physics]`).
- **Characters:**
  - foot IK and secondary motion (`procedural_rig.gd`, near the camera only);
  - ragdolls (`ragdoll.gd`, cap 3, frozen after 3 s);
  - 66 new UAL clips (`assets/incoming/animations/`);
  - utility-AI villagers (`population/utility_brain.gd`, 0.9 s ticks).
- **Combat and army:**
  - attack tokens, parry, lock-on, stealth noise radius;
  - formations and morale (`army/formation.gd`, `morale.gd`);
  - VFX library (`scripts/vfx/*`; `VFX.warmup()` at boot pre-compiles the shaders).
- **Life systems:**
  - hunting, fishing, foraging;
  - crafting and equipment;
  - skills and cultivation (`data/skills/*`);
  - dialogue, relationships and radiant quests (`dialogue/*.json`);
  - homestead building (`homestead.gd`, `build_menu.gd`);
  - discovery, compass, world map, fast travel, photo mode;
  - adaptive music (`scripts/audio/*`);
  - save slots, autosave and backups (`save_manager.gd`, `user://saves/`).
- **HUD:** Items, Crafting, Arts, Photo and Save/Load live in the Pack menu. The dock holds Map, Lock and Sneak; the four technique slots sit on an arc left of Attack.
- **Please check on a GPU:**
  - frame time with 3 ragdolls plus rain plus ambience in the village;
  - the new shaders on the Mobile renderer (terrain wetness and snow, grass, water sunset);
  - the `--shot=homestead` view;
  - touch sizes of the technique arc and the seal pad on a phone.

## 2026-09-28: local session takes PLAYER MOVEMENT FEEL + NPC DENSITY + OUTDOOR GROUNDING (user request)
- **Player movement/controls** (`scripts/actors/player.gd` movement, input and dodge only): the user finds movement glitchy and
  "Space/back does a shadow dash with afterimage". It should be an **ability** (cooldown, its own button), not the default on
  Space/back. The local side reworks locomotion feel (acceleration, turning, grounding, slopes, jump/dodge mapping) using proven
  open-source Godot 4 controllers as reference. **Codex:** clip choice and blend timing stay yours; the local side only changes
  speeds, input and state flow and will list any animation hooks it needs here. **Cloud:** please avoid the movement block of
  `player.gd` until the local side notes it's done.
- **NPC density:** the user says there are far too many NPCs walking around. The local side tunes the crowd counts (WorldSim
  local density, PopulationLOD budgets per tier).
- **Outdoor look and grounding:** the user says the outdoors looks fake and things don't sit on the floor. The local side does a
  visual sweep and fixes grounding and dressing (region_dressing, settlement_builder props, terrain scatter).

## DONE: player movement (local, 2026-09-28)

**Root cause of the "Space/back does a shadow dash" complaint:** `Game._setup_input()` bound Space straight to the
`"dodge"` action, and `Player._start_dodge()` had only one code path — a 4→12 m/s burst roll that always called
`VFX.afterimage(...)` (the shadow/ghost trail), with no cooldown beyond a flat stamina check. Pressing Space with no
direction held (e.g. while backing away with S) hit the `backward = dir.length() < 0.1` branch and played
`Dodge_Backward` with the same afterimage — that's the "back" trigger the user saw. Base locomotion
(`_steer`/`_update_facing` accel/brake/pivot/turn-rate, floor snapping, foot IK in `procedural_rig.gd`) was already solid
and needed no changes.

**Fix — split into a plain dodge and an explicit ability, in `kingdom/scripts/actors/player.gd`:**
- `dodge()` (still Space + the existing HUD dodge button) is now a short defensive roll, 3.2→7.0 m/s, **no VFX**, 15
  stamina, 0.35 s i-frames — the GDD's ordinary combat dodge, not a special effect.
- `ability_dash()` (new) is the old fast burst: 4.0→12.0 m/s, **still plays the afterimage VFX**, 30 stamina, a new
  4 s cooldown (`dash_cooldown`), 0.4 s i-frames. Bound to a new `ability_dash` action: **R** (keyboard), left shoulder
  (gamepad), and a new violet HUD button (`hud.gd`, dims + shows seconds left while on cooldown). `main.gd`'s
  `_unhandled_input` now also routes `ability_dash` -> `player.ability_dash()`.
- Both reuse the **same** `Dodge_Forward`/`Dodge_Backward` clips — only speed, VFX, stamina and cooldown differ, so
  clip choice and blend timing are untouched (Codex's territory).
- Space was **not** remapped to Jump: there is no jump today, and `docs/qa/anim_qa_report.md` shows the one `Jump*`
  clip in the library fails badly (8–13 cm below floor at every test) and isn't one of the clips the game plays, so
  wiring it up now would trade one glitch for another. Flagging a real jump as a Codex-then-local follow-up once a
  grounded jump clip exists (the physics side — coyote time / buffering — is already there in `_air_time`/`COYOTE_TIME`).
- **Speeds left unchanged** (WALK 2.4 m/s, RUN 6.5 m/s) — `anim_qa_report.md` says Codex already speed-matched the
  humanoid blend space to these exact values to remove foot slide; changing them here without a matching blend-space
  retune would reintroduce it. **Codex: no speed change from before this session.**

**Verification:** new bot `kingdom/tools_qa/movement_qa` (same real-input pattern as `tools_qa/autoplay`) recorded
frame strips for walk/run/stop/turn180/backward/slope/dodge/dash to `docs/qa/movement/` and they were looked at with
Read. Full writeup, before/after context and the new control table are in this session's final report (the harness
would not let this session write a new `docs/qa/movement/REPORT.md`; ask the user for the transcript if a persisted
copy is needed, or have a non-subagent session write it from the frames in `docs/qa/movement/`).

## 2026-09-28: addons approved by the user (local side adds them, in this order)
1. **antzGames/Godot_Vertex_Animation_Textures_Plugin** (MIT): VAT crowds for background villagers (after the NPC-density pass). Foreground NPCs stay on skeleton + AnimationTree (Codex's area); VAT is only for distant crowd instances that are sprites today.
2. **Phantom Camera** (MIT): smoother follow, lock-on and cutscene cameras (after the movement pass). The local side retests it on 4.6 (it was on hold for an editor error).
3. **godot-sqlite** (MIT, Android + iOS arm64 binaries): world-state database. **Cloud: this touches saving.** The local side will vendor it plus a thin `WorldDB` wrapper only and will NOT migrate the save system without agreeing it with you here first. Please note in this file whether you want to own the migration.
Sources and licences: `docs/qa/github_tools_survey.md`, `docs/OPEN_SOURCE_AUDIT.md`. Every GDExtension must ship Android and iOS binaries (the audit's red flag 7), or it stays disabled.

### 2026-09-28: DONE: godot-sqlite vendored (no save migration)

Vendored `kingdom/addons/godot-sqlite/` from upstream release **v4.8** ("Update to Godot 4.6.3", MIT, `compatibility_minimum = "4.5"`). Binaries included: Windows x86_64 (debug + release, covers the editor), Linux x86_64 (debug + release), macOS (debug + release), Android arm64-v8a + x86_64 (debug + release), iOS arm64 device (debug + release; simulator slices were stripped from the xcframeworks to stay well under the 90 MB file limit — not needed since we only ship device/App-Store iOS builds). Web/wasm binaries were dropped (not a build target). Total addon size ≈111 MB across 25 files, largest single file ≈43 MB (`libgodot-cpp.ios.template_debug.xcframework/ios-arm64/...arm64.a`).

**armeabi-v7a gap, checked and handled, not a blocker:** I checked every godot-sqlite GDExtension release from v4.0 through the current v4.9 (via the GitHub API tree/`gdsqlite.gdextension` for each tag) — none of them has ever shipped an armeabi-v7a (32-bit ARM) Android binary, only arm64-v8a and x86_64. Per the main session's decision, `kingdom/export_presets.cfg` keeps `architectures/armeabi-v7a=true` (old 32-bit phones still need to run the game), and `addons/godot-sqlite/gdsqlite.gdextension` simply has no `android.debug.arm32`/`android.release.arm32` keys at all (rather than declaring them and pointing at a missing file). Godot 4.6's GDExtension loader resolves the `[libraries]` table by matching the running platform+arch against declared keys; an arch with no matching key is treated as "this GDExtension doesn't support it" and is skipped, not as a load error — this is the same mechanism that already lets this addon ship without web/wasm on non-web exports. That's a different failure mode from the audit's red flag 7 (a *declared-but-missing* binary path, e.g. Terrain3D/LimboAI's absent iOS binaries), which does not apply here since no arm32 keys are declared. I confirmed this isn't just docs-reasoning: I ran an actual `--export-debug "Android"` of this project (with the vendored addon, unchanged `architectures/armeabi-v7a=true`/`arm64-v8a=true` preset) using the local Android SDK/build-tools already on this machine; see this session's final report for the exit code and log excerpt. At runtime on an armeabi-v7a device, `ClassDB.class_exists("SQLite")` is false.

`kingdom/scripts/core/world_db.gd` (new, not an autoload, not called from anywhere yet) is the thin wrapper:

```gdscript
class_name WorldDB
static func available() -> bool                          # ClassDB.class_exists("SQLite")
func open(path: String = "user://world.db") -> bool       # false + push_warning if unavailable or open fails
func is_open() -> bool
func exec(sql: String, params: Array = []) -> bool        # prepared statement, no-op(false) if not open
func query(sql: String, params: Array = []) -> Array[Dictionary]  # no-op([]) if not open
func begin_transaction() -> bool
func commit_transaction() -> bool
func rollback_transaction() -> bool
func close() -> void
```

Every method fails soft (no push_error, no exceptions) when SQLite isn't available or the db isn't open, so a caller that forgets to check `available()`/`is_open()` degrades instead of crashing. **Cloud: whenever you decide to move any world state onto this, you still need to keep the existing JSON save path as the fallback for `WorldDB.available() == false` (armeabi-v7a devices) — this wrapper does not and will not silently choose a storage backend for you.** No save-system code was touched.

Test: `kingdom/tests/test_world_db.gd` (gdUnit4) — open/exec/query/close round trip, an `available()`-false soft-degrade check, and a 10k-row bulk insert (single transaction) + full query-back with measured timing (printed by the test and reported in this session's final report). Verified headless on Windows.

## DONE: outdoor grounding/look (2026-09-28)

Visual QA + fix pass for the outdoor world (village, forest, camp), per the user's
"looks fake outside the city, things aren't on the floor" report. Full writeup:
`docs/qa/grounding/report.md` and `docs/qa/grounding/animation_timing.md`.

- **`tools/qa/perf_visual/perf_visual.gd`** now drives the player through the real
  touch-input path (joystick + camera, same `InputEventScreenTouch/Drag` calls as
  `tools_qa/autoplay/autoplay.gd`) instead of teleporting every frame, cycling
  idle/walk/run so walk/run animations actually play during a capture and the
  recorder window titles itself so it's clear it's a QA bot, not broken input.
  `--teleport` keeps the old mode for pure streaming benchmarks.
- **New `tools/qa/grounding/grounding_check.gd`**: samples every placed prop/tree/
  building/character within 150 m of several locations against `WorldGen.height()`.
  Found forest scatter (trees/rocks placed by `TerrainStreamer._plan_forest`) was
  the dominant floating/buried source on slopes — **fixed** with a slope-scaled
  sink. Also found (not fixed, flagged for follow-up): village building/prop
  batches in `settlement_builder.gd` float more than the region-site buildings do
  (median 29 cm), because they don't use `RegionDressing._footprint_ground()`'s
  per-corner snap. Also found and worked around a real asset bug: every GLB under
  `kingdom/assets/generated/region/**` has an invalid embedded resource UID,
  making every load fall back to slow text-path re-resolution — worth a reimport,
  separate from this pass.
- **"Fake look" fixes** (`world_gen.gd` `color_at()`, `settlement_builder.gd`,
  `region_dressing.gd`): every building/prop footprint and region-site clearing now
  gets a worn-dirt ring in the terrain vertex colours (previously only streets/
  paths/plaza did — buildings elsewhere met grass with a hard edge), plus small
  base clutter (stones/weeds/ferns) at building bases in villages and at farm/mine/
  camp buildings. SSAO/contact-shadow settings in `main.gd` were reviewed and left
  alone (already reasonable). ProtonScatter/terrain_layered_shader (surveyed in
  `docs/qa/github_tools_survey.md`) were deliberately not adopted this pass — the
  in-house `WorldGen.color_at()` approach was cheaper and lower-risk given the time
  available; ProtonScatter's ground-projection modifier is still a good follow-up
  for scatter variety.
- Not done: `settlement_builder.gd` per-corner footprint snap (flagged above, not
  implemented), region-site numeric grounding re-verification (region build is slow,
  see above — checked by code review instead), and a full per-NPC/animal animation-
  timing sweep (`animation_timing.md` covers the player in detail; NPCs/animals were
  only spot-checked by eye).

## 2026-09-28: movement QA v2 + camera jitter fix (local, follow-up to player movement)

The user said movement still felt "glitchy as f***" after the dash/dodge split above. The
v1 `movement_qa` strips were invalid: the fixed spawn offset (`home["pos"] + Vector2(2,10)`)
happened to land the player pinned against a market stall, so 01_walk/02_run/03_stop never
actually displaced (every frame identical) and 04_turn180's "camera in the head" was the
`SpringArm3D` starting its cast from inside geometry, not a standalone bug.

**Fixed the harness** (`kingdom/tools_qa/movement_qa/`): spawns on open ground along the
village's own gate/road direction (`WorldGen.settlements[0].plan.gates[0]`), verified clear
with a ring of raycasts, and asserts real displacement (or a facing/grounded condition)
after every scenario — PASS/FAIL in `log.txt`, non-zero exit on any failure. Added strafe,
wall-collision and crowd scenarios (11 total).

**Real bugs found and fixed in `player.gd`/`project.godot` (not animation — Codex's clips
were untouched):**
1. `physics/common/physics_interpolation` was never enabled, and the whole camera rig runs
   only from `_physics_process`. Without it, ordinary frame-time variance against the
   physics tick (routine on mobile) reads directly as character/camera jitter, independent
   of any movement tuning. Enabled project-wide; added `reset_physics_interpolation()` at
   every player teleport (`main.gd::_teleport`, mount, dismount, respawn, the
   anti-fall-through catch) so a teleport snaps instead of smearing for a frame.
2. The manual wall-avoidance raycast in `_update_camera` (added on top of the spring arm's
   own collision to fix the guild-hall/stall clipping noted earlier in this file) snapped
   `camera.global_position` straight to the hit point every tick, so a hit flickering in and
   out (corners, thin awnings) jerked the camera. Pull-in (new occlusion) stays instant —
   never show through a wall — but release-back-out now eases.

**Phantom Camera (addon #2 in the approved list above):** re-cloned `v0.9.4.2` — pure
GDScript (34 files, no binaries, so mobile-safe as claimed), Godot 4.4+ per its README
(project is 4.6). **Not vendored/swapped in this pass**: I couldn't safely retest an actual
editor load (the thing it was on hold for) without competing for the GPU/Vulkan device with
other agents' live Godot sessions on this machine, and the current camera is tightly coupled
to features Phantom Camera would need to fully replace — the four-distance zoom rig, lock-on
framing (shifts the pivot toward the target), mounted rider offset, first-person viewmodel
swap, aging body-scale, and the playtest bot's direct reference to `player.camera`. Swapping
it in without being able to verify all of that first felt like trading a verified jitter fix
for an unverified regression risk. Recommend a proper editor retest + incremental adoption
(third-person follow + damping only, keep everything else) as a follow-up when the machine
isn't under load.

**QA capture blocked this session:** the real-input GPU capture (`run_movement_qa.sh`)
crashed 5 times in a row during initial world/region load (every `kingdom/assets/generated/
region/**` GLB has the invalid-UID issue already flagged above, which forces slow text-path
resource re-resolution during that load) while 1-2 other Godot processes were also running
on this machine; free RAM was as low as ~3.6 GB of 16 GB during the failures. One run got
as far as this session's new open-ground spawn logic succeeding (`open ground found at
(68.0, -51.0)...`) before dying, confirming the harness fix itself works — but no before/after
frame strips were captured. Please re-run `kingdom/tools_qa/movement_qa/run_movement_qa.sh
--out=docs/qa/movement/v2/after` (and ideally a `before` from the previous commit) when the
machine has a few GB more headroom, and look at the strips with Read.

## DONE: NPC density (local, 2026-09-28)

**Root cause:** `population_lod.gd` capped sprite NPCs per job look (peasant/worker/merchant/
guard) instead of as one shared budget, so the real ceiling was 4x the intended one — the
capital was hitting `npc_sprites: 1200` at hour 9/13/18, with frame time spiking to ~117 ms
average (8.6 fps) at the worst point, far past the reported "~10 ms/frame". Fixed the loop to
share one running total across looks (nearest-first, so the closest people still win the
budget), lowered `MAX_SPRITES` 300 -> 140, and cut `Quality` tier budgets: HIGH `npc_full`
24 -> 16, `npc_sprites` 300 -> 55 (LOW/MEDIUM/ULTRA similarly cut; sprites down ~75-85% across
tiers). Also widened `DailyRhythm.MAX_DELAY` 0.9 h -> 2.0 h so schedule-boundary crowds (e.g.
17:00 market call) stagger onto the street over ~2 minutes instead of a few seconds. The
"anyone within 9 m is a full model" rule, WorldSim's population counts/economy, and all
animation code are untouched.

Capital (city, hour 18) best-of-two: cpu_process_ms 150.8 -> 50.4, average frame 116.8 ms ->
16.0 ms, fps 8.6 -> 62.6. Sprite counts: village/capital both 287-1200 -> 55 during the day
(cut well over 50%), full models 24 -> 16. Full counts, per-hour tables and 4 before/after
screenshots (village plaza + capital street, midday and night): `docs/qa/npc_density.md`.
Files: `kingdom/scripts/population/population_lod.gd`, `kingdom/scripts/core/quality.gd`,
`kingdom/scripts/population/daily_rhythm.gd`.

**Follow-up, not done:** `npc_full`/`npc_sprites` budgets are tier-only, not scene-aware, so
the village plaza and a capital street land on the same combined count today (both have enough
population in `SPRITE_RANGE` to fill the shared budget). A future pass wanting the village
specifically emptier than the capital needs a per-settlement-size budget.
