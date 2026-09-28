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

## 2026-09-28: addons approved by the user (local side adds them, in this order)
1. **antzGames/Godot_Vertex_Animation_Textures_Plugin** (MIT): VAT crowds for background villagers (after the NPC-density pass). Foreground NPCs stay on skeleton + AnimationTree (Codex's area); VAT is only for distant crowd instances that are sprites today.
2. **Phantom Camera** (MIT): smoother follow, lock-on and cutscene cameras (after the movement pass). The local side retests it on 4.6 (it was on hold for an editor error).
3. **godot-sqlite** (MIT, Android + iOS arm64 binaries): world-state database. **Cloud: this touches saving.** The local side will vendor it plus a thin `WorldDB` wrapper only and will NOT migrate the save system without agreeing it with you here first. Please note in this file whether you want to own the migration.
Sources and licences: `docs/qa/github_tools_survey.md`, `docs/OPEN_SOURCE_AUDIT.md`. Every GDExtension must ship Android and iOS binaries (the audit's red flag 7), or it stays disabled.
