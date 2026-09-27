# Rising Ashes playtest report (autoplay bot, 2026-09-27)

This run played the real game on this PC (RTX 4070 Laptop, Vulkan Forward+, windowed 1280×720, Godot 4.6)
through the real input path: joystick and camera touches, HUD buttons, keys and menu clicks. It covered the
full scenario 5 times while bugs were found and fixed. The screenshots and numbers are from the final run.
Everything is in `docs/qa/playtest/` (`NN_*.jpg`, `log.txt`, `summary.json`, `errors.txt`).
Re-run: `kingdom/tools_qa/autoplay/run_autoplay.sh` (see `kingdom/tools_qa/autoplay/README.md`).

**Caveats.** The laptop was on battery (7 to 32 %, discharging). One `nvidia-smi` sample showed the GPU in P8 with
"SW power cap" and "SW thermal slowdown" active. Two other agents' Godot benchmark processes were also running.
The game also picked the **Low** quality tier (bug 3), which caps it at 30 fps. So the fps figures show what a
player gets with the current auto-detection, not what the GPU can do.

## Scenario results

| # | Step | Result |
|---|---|---|
| 1 | Boot, birth cutscene, skip | Loading screen gone at **17.3 s**. The cutscene plays well (01, 02). The double tap to skip **did not work** before the fix (bug 2, fixed). **First playable frame at 26.0 s** after launch, about 9 s of it cutscene before the skip. |
| 2 | Walk around Ashford | The plaza, guild hall, inn, healer and houses all read well and look cosy (05–13). The 360° look works. Walking with the joystick worked everywhere on the street (0 stuck events in the final run). **There is no blacksmith building in Ashford** (bug 7). The innkeeper, the Captain of the Guard and villagers were all reached (14–16). |
| 3 | Interact | Notice board (E), guild (Talk button, Register: 10 g paid, member page shown), trader (Buy Loaf: −2 g; Sell Wolf Pelt: +4 g) and Captain (Enlist menu) all work. Before the fix, the trader and inn menus sometimes opened **mostly off screen** (bug 1, fixed). |
| 4 | Enter a building | **Interior doors are not wired in the world** (0 `InteriorDoor` nodes; bug 4). The bot placed a test door at the inn to check the room: the interior loads in about 1 s, looks great and lights well, the patrons and innkeeper stand in place, and the ExitDoor + E leaves correctly (24–30). Also, at the inn door, E opens the innkeeper's menu instead of the door (bug 5). |
| 5 | Leave the runestones and fight | Danger goes from `Safe 0` (runestone coverage 0.8) to `Perilous 55` near the den (31). Wolves stalk and attack as a pack (32–34). Attack, block ("Guard broken!"), dodge, hit reactions and "+5 merit: wolf slain" all work (35–38). Goblins at Mossfang Warren fight, and 4 of them died or yielded ("drops its weapon and kneels", with the Name option) (41–48). **The player died in every fight** (bug 8), and the death pose doesn't read (bug 6). |
| 6 | Sleep and night | Renting a bed at 19:30 costs 3 g and sleeps 6 h, waking at **01:33** (52; bug 10). At night all 16 street lamps are lit. The plaza is warm and readable (53–57). |
| 7 | Save (F5) and load (F9) | Position, health, gold, time, day and inventory (apples, bread) were changed after saving, and **all were restored** by F9 (58–60). |

## Bugs, ranked

| Rank | Bug | Evidence | Likely cause and where | Status |
|---|---|---|---|---|
| 1 | **Menus open mostly off screen** (trader, inn): the panel kept a height of 1985–2685 px, the buttons were at y = −822, and taps did nothing. The player couldn't buy, sell or rent a bed. | `log.txt` of the earlier runs: `menu rect [P: (336,-982), S: (608,2685)]`. The earlier `19_trader_menu` showed a dark full-height panel with no content. | `HUD._rebuild_menu` (`scripts/ui/hud.gd`): a Control grows but never shrinks, and the panel kept a stale size from an earlier page. | **Fixed**: the outgoing page is hidden, then `_fit_menu()` resizes and re-centres the panel after layout. Verified: trader, inn and guild all fit on screen, and buy, sell and sleep work. |
| 2 | **Tap-to-skip the birth cutscene didn't work**. Taps and clicks never reached the cutscene, so only Esc worked (there is no Esc on a phone). | First run: `double tap skip: DID NOT SKIP`. | `CutscenePlayer._input` lives inside the world SubViewport, whose container has `MOUSE_FILTER_IGNORE`, so touch and mouse events are never pushed into it (`scripts/cinematic/cutscene_player.gd`). | **Fixed**: it also listens on the root window's `window_input` for touch and real mouse events. Verified: "Tap again to skip" shows, and the second tap skips. |
| 3 | **Quality auto-detect picks Low on an RTX 4070**: a 30 fps cap and 3D at 540p. That explains the soft image and why villagers 4 m away are flat sprites (09, 10, 22). | `godot_stdout.txt`: `Quality: Low (auto)`. First run: `SCRIPT ERROR: Nonexistent function 'get_device_type' in base 'RenderingDevice'` (quality.gd:214). | `scripts/core/quality.gd` (the local quality-tier agent's uncommitted work) calls `RenderingDevice.get_device_type()`, which doesn't exist in 4.6. Use `RenderingServer.get_video_adapter_type()`, and check that a Low choice saved during the failed run isn't sticking. | Reported (their file, work in progress) |
| 4 | **Buildings can't be entered**: there are no `InteriorDoor` nodes in the world. | 23 and log. | The doors aren't wired yet (`scenes/interiors/README.md` describes how). | Request for the cloud session |
| 5 | **The innkeeper blocks the inn door**: with a door at the inn front, E opens the innkeeper menu because the Station is nearer and `InteriorDoor` yields to the nearest interactable. | 23, and log `nearest interactable at the door: 'Ashford Inn'`. | The innkeeper Station stands 5.2 m in front of the inn door (`village_services.gd`), inside the 3.2 m interact radius of any door there. | Request: move the innkeeper inside (the interior has `NPC_Innkeeper`) or off to the side |
| 6 | **The death pose doesn't read**: 1.2 s after dying, the hips are still ~0.93 m high (standing). In one goblin fight the player fell (0.16 m) and was standing again 1.2 s later. Then the 3 s respawn. | 39 and 49, and log `death anim: 'Death_A' … hips 0.88 m -> 0.93 m`. | `UAL_Extra_Mesh2Motion.glb` has its own 4.46 s `Death_A`, which wins over the `Death_A → Death01` alias in `Assets._ual_for` (`scripts/world/assets.gd`, the alias loop only adds missing names). That clip keeps the body up for a long time, and `Player._die` respawns after 3 s. | Request: prefer the alias for gameplay names, or play `Death01` |
| 7 | **No blacksmith in Ashford**: the Smithy org hires ("Ashford Smithy" on the notice board) and villagers are labelled "Blacksmith", but the plan has no `blacksmith` lot. | log `Ashford lots: {...}` | `city_planner.gd` TRADES picks for the home village. | Request |
| 8 | **Fights are very lethal**: the player died in all 4 fights (4 wolves, or 7 goblins at once) while swinging, blocking and dodging. Wounded wolves (< 15 hp) flee at 8 m/s, faster than the player's 7 m/s run, so they can never be finished (`45->13` three times). | 33–39 and 42–49, and log `enemy hp` lines. | `wolf.gd` `_decide` (flee < 15 hp, speed 8), bite 9 dmg every 1.2–1.8 s per wolf, and whole goblin warrens aggro together. | Balance request |
| 9 | **The camera went inside walls, stalls and foliage** (the guild hall was a brown smear, the stall canopy filled the screen, the game started facing a house wall). | Earlier-run 03, 08, 09 and 30. In the final run 03, 08 and 09 are fixed. Foliage (35, 37, 49) still covers the view because trees have no colliders. | `Player._update_camera` only clamped to terrain and water. | **Fixed** for anything with a collider: a ray from head to camera pulls the camera in (third person, outside interiors). **Still open, and serious in forest fights:** conifer branches fill the screen for most of the final wolf fight (33, 34, 35, 37), so the wolves can hardly be seen. Needs a fade for foliage near the camera, or a sphere cast against the trunks. |
| 10 | **Sleeping at the inn wakes you at 01:33**, "rested", in the middle of the night. | 52 | `Life.sleep` sleeps `hours_to_rest` hours from now. | Suggest waking at the next 06:00–07:00 |
| 11 | **The raider-camp banner "☠ 12" shows through everything**: it's in the birth cutscene sky (02), over the Ashford plaza (06, 14, 15) and at the goblin warren (49). | 02, 06, 14, 15 and 49 | `squad.gd:109`, the banner Label3D has no depth test and no distance limit | Request: hide it during cutscenes, fade it past ~60 m, or keep the depth test |
| 12 | **Committed branch: T-poses everywhere**. In a clean checkout, `_library/.gdignore` is committed, but `assets.gd` loads `UAL_Extra_*.glb` from it. The first run (before this PC imported it) logged 25,000 errors (`No loader found … UAL_Extra_Mesh2Motion.glb`, `Animation not found: Idle/Walking_A`) and every character T-posed. | First-run log (overwritten), and the `ENGINE` lines at `assets.gd:490` | The `.gdignore` deletion and the new `.import` files are uncommitted local changes | Request: commit the `.gdignore` removal together with the 4 `.import` files, and null-check the load in `_ual_for` |
| 13 | A villager was standing inside the house front (16), and wolves clip into the player during bites (34). | 16, 34 | Villager targets on lot footprints. Wolves move by setting their position directly (no body). | Minor |
| 14 | The night sky still shows bright daytime HDRI clouds at 22:40 (55). | 55 | The panorama sky is only dimmed by `background_energy_multiplier` | Minor, look |
| 15 | `ERROR: Lambda capture at index 0 was freed` (once per run), plus invalid-UID warnings on several gltf and glb files. | `errors.txt` | A menu lambda outliving its node, and stale UIDs after reimports | Minor |

## What works well
- **The look.** Ashford's plaza, the guild hall with its banners and quest board, the inn, the healer's stall and the thatched houses are cosy and readable (08, 09, 11, 13). The night with lit lamps looks lovely (53). The inn interior is the best-looking space in the game (24–29).
- **Controls.** The joystick, camera swipe, and Talk / Attack / Block / Dodge buttons all respond. Walking is smooth, with no stuck events on the streets in the final run.
- **Systems.** Menus, trading, guild registration, the Captain's enlist menu, merit toasts, goblin yielding and naming, the danger readout and save/load all work end to end.
- **Stability.** 0 SCRIPT ERRORs in the final run, and 2 engine warnings or errors in total.

## fps per area (final run: tier Low, 30 fps cap, laptop on battery)

| Area (step) | fps avg (min) | 3D GPU ms avg (max) | Draw calls avg / max | Primitives max | Nodes |
|---|---|---|---|---|---|
| Boot and cutscene | 27 (1) | 3.7 (20.1) | 258 / 604 | 1.69 M | 2,561 |
| Ashford village walk | 28 (8) | 8.4 (25.4) | 498 / 833 | 2.05 M | 3,400 |
| Menus in the plaza | 27 (14) | 9.5 (12.5) | 558 / 819 | 1.99 M | 3,499 |
| Inn interior | 29 (12) | 7.2 (16.6) | 311 / 616 | 1.84 M | 3,516 |
| Forest, wolves | 28 (1) | 7.2 (24.7) | 365 / 711 | 1.91 M | 2,946 |
| Goblin warren | 27 (1) | 8.4 (12.0) | 393 / 686 | 1.93 M | 2,800 |
| Night plaza | 22 (1) | 14.2 (62.4) | 495 / 679 | 1.89 M | 3,322 |
| Save/load | 22 (2) | 7.2 (12.4) | 584 / 710 | 1.94 M | 3,449 |

The 3D GPU time is 7–14 ms, so there is headroom for 60 fps once bug 3 is fixed. The fps minimum of 1 and the
"worst frame" of 5–6 s both come from the bot's fast travel (`_teleport` → `build_all_now`), not from walking.
Walking hitches were at most 0.6 s. In earlier runs, while other agents' GPU jobs were running, the village fell to
5–13 fps with 3D GPU at 130–140 ms. That's worth rechecking on mains power.

## Six screenshots to show
1. `docs/qa/playtest/09_guild_hall.jpg`: the guild hall with its quest board and villagers
2. `docs/qa/playtest/08_plaza_look_360.jpg`: the market plaza with the well, stalls and NPCs
3. `docs/qa/playtest/25_interior_walk.jpg`: inside the inn (fire, bar, patrons)
4. `docs/qa/playtest/45_goblin_melee.jpg`: a sword slash at the Mossfang goblin warren
5. `docs/qa/playtest/53_night_plaza.jpg`: Ashford at night with the lamps lit
6. `docs/qa/playtest/20_trader_menu.jpg`: the trader menu, fixed and on screen
