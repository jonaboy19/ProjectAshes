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
- **Interiors ready.** `scenes/interiors/{inn,blacksmith,guild,healer,house}_interior.tscn` (the house one is shared by all 5 house types). Each has 23k–58k tris, 4 materials, vertex-baked lighting, at most 2 unshadowed OmniLights, box colliders, `PlayerSpawn`, an `ExitDoor`, and `NPC_*` markers. To wire them, drop an `Area3D` with `scripts/interiors/interior_door.gd` on each building door and set `interior_scene`. Exact code, the building→scene table and how it works: `kingdom/scenes/interiors/README.md`. Previews: `docs/kingdom/blender_previews/_interiors_sheet.png`. Rebuild with `tools/blender/make_interior_*.py`.

## In progress on the local side
- Done: armored characters (`incoming/ai3d/meshy/armored/`; the cloud has already wired them) and interiors (above). **Cloud: please wire the door triggers** with `interior_door.gd` on the inn, blacksmith, guild, healer and the 5 house types (see `kingdom/scenes/interiors/README.md`), and call `InteriorDoor.active.leave()` on player death.
- Next on the local side: real-GPU performance pass (fps and frame times in village, capital and battle on this PC's RTX 4070, then Android export), with results written here.

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
- **2026-09-27, local (in progress): locomotion speed / foot-slide fix.** The local side is editing `character_animator.gd`, `player.gd`, `villager.gd`, `soldier.gd`, `wolf.gd`, `monster.gd`, `critter.gd` (locomotion playback only: blend points, time-scale by ground speed, walk->run switch points, animal speed tables, wolf flee cap) plus the anim QA speed catalog. Cloud: please avoid those movement/animation blocks until this lands (a note will follow here).
