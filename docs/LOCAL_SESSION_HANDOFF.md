# Local PC session ↔ cloud session: coordination

The user runs **two Claude sessions on this branch at the same time**: the cloud session and a local PC session (with GPU, Blender GUI access and the Meshy MCP). This file keeps them from stepping on each other. **Read it after every pull.**

## Animation behaviour now owned by local session (owner decision 2026-10-06); Codex branches merged up to 83535327 (living-world-integration), fa4b483e (bending-current), 06871693 (character-feel-finish)
- `gpt/living-world-integration` and `gpt/character-feel-finish` were already ancestors of the Claude branch. `gpt/bending-current` (21 commits: casting ownership, hit-pause sync, gather cancel, camera lifecycle) merged cleanly. `test_technique_caster_port` now asserts the single-owner windup rule (`overlap_windups = false`).
- Failing on the pre-merge base too, so not from the merge: boot_flow "no save written on NOTIFICATION_APPLICATION_PAUSED", `test_market_dressing`, `test_town_identity`, `test_town_kit`.
- `player.gd` was converted to CRLF upstream (cd01c726); keep it CRLF (a whole-file conflict otherwise).
- What was wired afterwards: `docs/STATUS_LOCAL.md`.

## FOUNDATION FREEZE (user decision, 2026-10-05): read docs/design/FOUNDATION_PLAN.md first
The big simulation features (13 kingdoms, politics, wars, settlement founding, civilization pressure, Soulbeast evolution, economy simulation) are frozen until the first milestone is done: Thornfield, the wilderness, one town, one Rift and one outpost, all fully playable. They get bug fixes only.
- **Cloud is doing now:** F1 interaction framework, F3 combat basics (heavy attack, spear/bow/staff, knockdown and get-up, pooled projectiles, touch lock-on), F4 in-world conversation. Next: F2 traversal, F5 ownership/theft.
- **Codex, please:** (1) run your nine-step runtime validation of jump, land, run-stop and pivot from docs/anim/CODEX_LOCOMOTION_JUMP.md and fix what fails; (2) wire walk/run starts, walk stop, sprint skid and idle turn; (3) add sword-stance armed locomotion (idle/walk/run with the weapon drawn) and additive hit reactions; (4) once F2 lands, tune the timing of the traversal clips (Ledge_*, Mantle_*, Vault_*).
- **Codex, feel list from F2/F3 (2026-10-05).** All clip names and timings are in data (data/movement/traversal.json, data/combat/player_weapons.json):
  - **Traversal:** the capsule follows scripted curves rather than clip root motion. Check:
    - foot slide after the vault handover;
    - the 0.12 s shuffle before a standing mantle;
    - the Vault_Low/_B side mapping;
    - the ledge top landing being 10 cm off;
    - the Ledge_Hang_Idle loop blending into the climb;
    - step-up floating at run speed.
  - **Combat:**
    - The Lie_Down at 3x into Stand_From_Floor will likely pop. UAL_Free_Reactions has Fall_Forward_Knockdown/GetUp_* but is not in Assets.UAL_FILES.
    - Staff light attacks borrow Sword_Regular_* clips.
    - The Bow_Hold loop is a re-fired one-shot, so it may seam.
    - There is no charge or draw meter yet (the `charge_changed` signal exists).
- **Local PC, please:** check the touch layout on a portrait phone (Jump and Attack overlap, thumb reach), then re-run tools_qa/movement_qa on the new jump and land code.

## AAA camera + clean-screen pass (local, 2026-10-06, owner's direct request) -> cloud + Codex
Owner: "looks good but doesn't FEEL AAA" (S22 screens) + `docs/art/AAA_PRESENTATION_REVIEW.md`. Skill `ashes-aaa-camera-hud` has the rules and the harness. Cloud-owned files touched, minimal and documented:
- **Camera (player.gd, chase_camera.gd):** `VIEW_RIG` THIRD 3.9 m / -0.2, `SHOULDER_HEIGHT` 1.62, `SHOULDER_OFFSET` 0.42 (rotated by `_yaw`; the old `talk_shift` was added in world X and is now camera-local too), `BASE_FOV` 54, `OPEN_DIST/LIFT` 0.35/0.1, eased collision release, global shader param `hero_cam_dist`, child node `CameraOccluders`. No animation code touched (Codex).
- **HUD (hud.gd):** `_update_calm_fade` fades `_chrome` to 22 % after 7 s calm. **tutorial_prompt_view.gd / tutorial_director.gd:** button lessons sit beside their button; calm prompts settle (SKIPPED) after 9 s.
- **World text:** villager plate = name (debug text behind new setting `dev_sim_overlay`), plate range 4.5 m; `Nameplates` 12 m / 3 shown; barks 11 m / 2; alert glyphs smooth, 14 m (test updated).
- **Art:** critter horses use `HorseRig` (coats, bridle; mount_controller still drives `play_gait`, rider seat height on the new model NOT checked in a ride), brazier mesh + `shaders/brazier_fire.gdshader`, frayed gate cobble aprons (rng3 sequence changed, so gate-side carts/barrels moved), `style_g.gd _game_environment` grade, contact blobs under player/villagers/horses, contact_shadow shader `fog_disabled`.
- **Main menu:** big RISING ASHES + "A Total Showdown Studios Game".
- **Please (cloud):** keep `#include camera_see_through` + the discard line when editing lab shaders; new world shaders should include it. **Codex:** check rider seat on the HorseRig town horse.
- **Later passes (owner list, not done):** hero model, dialogue presentation, faces/eyes, NPC tiers, map as a cartographic object, element-world interaction, audio layers, Ashford benchmark block.

## Tools you can use (read this first)
Free, licence-checked tools are installed on the local PC in `C:\Users\Jonna\Tools\` and documented with exact headless commands in `tools/README_EXTERNAL_TOOLS.md` and the skill `.claude/skills/ashes-external-tools/SKILL.md`: scrcpy and Perfetto (S22 recording and traces), RenderDoc and AGI (GPU), gltfpack (auto-LOD; use `-noq` for Godot), Instant Meshes (retopo), Real-ESRGAN and Krita (textures), RTMPose (better video mocap), Piper (NPC voices, licence-cleared voices only), rFXGen and jsfxr (SFX), plus Rigify/Wiggle/erosion/Azgaar from round 1. Phone/GPU/Windows-binary tools work only on the local PC; cloud sessions should ask the local session to run them. No Ollama or local LLM.

## Build kit and medieval towns (local, 2026-10-05) -> cloud
- Build kit: read skill `ashes-build-kit`; cloud requests listed in `docs/regions/HOOKS_FOR_CLOUD.md` (2026-10-05 section): founding flow via `build_kit.ensure_grid`, crafting stations / storage / beds from kit pieces, build camera, road speeds. Lab: `tools_qa/build_lab/build_lab.tscn -- --shots=<dir>`.
- Medieval towns: placements in `data/region1/world/meshy_extra.json` (`docs/qa/MESHY_PLACEMENT.md`); town code edits marked "# Medieval pass (local)", A/B with `--medievaloff`. Note: `town_sheet.gd` must be run WITHOUT `--shot=none` (main.gd takes `--shot` first). Open: phone/LOW draw-call check of towns, per-copy cloth colours.

## Bending / martial-arts clips and VFX lab (cloud, 2026-10-05) -> local PC + Codex
Full research (licences with verbatim lines, move list per technique id, VFX analysis): `docs/research/BENDING_SOURCES.md`. Clips only; **no animation behaviour was touched** (blends, speeds, `character_animator` wiring, `Assets.UAL_FILES` are Codex's and unchanged).
- **What is ready:** `kingdom/assets/incoming/mocap/cmu/clips/UAL_CMU_Bending.glb` (+ `.clips.json`, imported, 1.9 MB). 36 clips on the 65-bone UAL skeleton, all in place, root travel on the optional `root` track (same convention as `animations/README.md`), none flagged loop: Water 6 (`Water_Flow_SunSalute`, `Water_Dance_ArmsHigh`, `Water_SpinReach_L`, `Water_Whirl`, `Water_Lean_Sway_A/B`), Air 8 (`Air_Evade_L/R`, `Air_Duck_Weave_L`, `Air_Balance_OneLeg`, `Air_SpinJump_360`, `Air_Jump_Twist`, `Air_Jump_Kick`, `Air_Handspring_Evade`), Earth 9 (`Earth_Lunge_R/L`, `Earth_PunchSeq_L`, `Earth_PunchSeq_Deep`, `Earth_Punch_Hold_Deep`, `Earth_Crouch_Reach_R/L`, `Earth_Spin_Reach_R`), Fire 9 (`Fire_Box_Combo_A/B/C`, `Fire_Box_Jab_Hook_B`, `_Straight_C`, `_Hooks_D`, `_Flurry_E`, `Fire_Stride_Strike_F`, `Fire_Punch_Kick`, `Fire_Aerial_Flip`), Lightning 2 placeholders, `Guard_Ready_Defensive`, `Cultivate_Yoga_Floor_Flow`. The per-stance table with CMU subject_trial numbers and the technique ids (`bn_*`, `st_*`, `kn_*`) is in `BENDING_SOURCES.md` section 3; the clip table with durations, source windows and measured foot slide is in `assets/incoming/mocap/cmu/README.md`.
- **Previews (read before wiring):** `docs/anim/cmu_bending/` (`side_sheet_00..03.jpg`, 8 frames per clip; `front_sheet_00.jpg` front view of Air_Evade_L, Earth_Lunge_R, Earth_Punch_Hold_Deep, Fire_Box_Combo_A, Fire_Punch_Kick, Water_Dance_ArmsHigh). Metrics: `godot --headless --path kingdom -s tools/anim/preview_free_library.gd -- --glb=res://assets/incoming/mocap/cmu/clips/UAL_CMU_Bending.glb --metrics` and the new `tools/anim/foot_slide.gd` (same args). No NaN, no exploding bones; foot slide of planted feet 0.0-0.25 m/s on the stance clips.
- **Needs cleanup (local):** (1) floor penetration 5-7 cm on `Fire_Box_Combo_A`, `Fire_Stride_Strike_F`, `Water_Whirl`: add the contact lift or a +Y offset on those frames. (2) `Air_Evade_L/R` are 4 m basketball dodge-runs: play with root motion or as a dash. (3) `Earth_Punch_Hold_Deep` ends in a crouch (trim to 4.6 s). (4) `Lightning_*` are placeholders; key a sharp snap-to-point set by hand (or film it, see below). (5) Fingers are constant fist/relaxed poses. (6) Strides differ between source performers (CMU subjects 05, 13, 14, 17, 49, 55, 75, 78, 88, 90, 141, 143, 144), so expect small scale/posture mismatch when chaining clips. (7) Foot IK on top (SkeletonModifier3D) would fix most sliding in the lunges.
- **Needs wiring (Codex):** add the GLB to `Assets.UAL_FILES`; choose events per clip (hit frame for the punches and kicks, VFX spawn frame for `ElementFX.play`, approximate from the contact sheets: `Water_Dance_ArmsHigh` peak about 3.3 s, `Fire_Punch_Kick` kick about 2.2 s, `Earth_Lunge_R` strike about 1.1 s; measure properly with `tools/anim/measure_events.gd`), blend times, and which stance state uses which clip. Suggested pairing is the table in `BENDING_SOURCES.md` (technique id to clip). Existing Taichi/Karate/Kata/MA_*/Cast_* clips stay the base; these add variety.
- **Not done / honest gaps:** CMU has only ONE tai chi trial (12_04, already used) and no Bagua or Wing Chun; Water/Air flow comes from modern dance, yoga and basketball footwork, so it reads as dance more than martial art. Real bending feel needs the owner's own recordings (below). Raw BVHs (63 MB) are local only (`_raw/` is gdignored and `*.bvh` git-ignored); `bash tools/anim/fetch_cmu_bending.sh` restores them. Licence: CMU (credit line already in `CREDITS.md`).
- **VFX lab:** `kingdom/scenes/vfx_lab/vfx_lab.tscn` (water whip, fire blast, earth spikes, Godot-native, procedural, no new textures). Sheets and budget table in `docs/art/vfx_lab/` (`vfx_lab_sheet_high.png`, `_low.png`). Effects are `LabFX` nodes (`play()`, `seek()`, `finished`, `quality` 0..2), NOT hooked into `ElementFX`. To check on the S22: fire blast pixel cost close to the camera, GPUParticles3D on the Compatibility renderer (ElementEffect converts to CPU particles, these do not yet), total particles when several casters fire at once. Nothing was measured on a phone.
- **Making original moves with mocap-ts (owner's own recordings):** the repo already has a local MediaPipe pipeline (`kingdom/tools/anim/video_to_bvh/README.md`, `tools/anim/video_mocap/`) with foot-contact cleanup; use it first. `mocap-ts` (MIT, https://github.com/ellyseum/mocap_ts) is the Node alternative: `npm`/`pnpm install`, needs ffmpeg and Node 20+, then `mocap-ts --input kick.mp4 --output kick.bvh --fps 30 --smoothing 0.5`. Film per the how-to-film rules in `video_to_bvh/README.md` (tripod at 1 m height, whole body in frame, front 3/4 view, 30-60 fps, plain background, move slower and larger than in game, start and end in a neutral pose). Then `python tools/anim/video_mocap/retarget_video_bvh.py kick.bvh --name Water_Whip_Own --out Water_Whip_Own_UAL.glb [--inplace linear --start 1.0 --end 3.2]`, or put the BVH in a new `cfg_*.json` for `retarget_clips_to_ual.py` (copy `cfg_cmu_bending.json`; mocap-ts BVH bone names differ from CMU, so edit the `map` block; its README does not document bone names, check the first lines of an output file). Confirm which pose model mocap-ts downloads and its licence before shipping anything recorded with a third party's face or body; your own body is fine. mocap-ts has no foot-contact lock yet (its roadmap says so), so expect sliding; fix with the foot IK or the cleaner in `video_mocap/foot_ik.py`.
- Side effect to know about: running `godot --import` in the cloud container also generated `.import` files for the unimported `assets/ui/icons/items/pm_m_*.svg` icons (from another session's work); they are harmless but show up as untracked.

### WIRED (cloud, 2026-10-05): the CMU bending clips now play on technique casts. Note for Codex
- **What exists:** `kingdom/scripts/actors/bending_library.gd` (no class_name) installs the GLB as AnimationLibrary **"bending"** on a character's AnimationPlayer on demand (cached per skeleton path, like `LifeLibrary`; `Assets.UAL_FILES`, blends, speeds and the state machine are untouched). Clips are addressed `bending/<name>`; `BendingLibrary.pick/resolve/play_cast` do the lookup. **Playback reuses the existing OneShot slots**: `CharacterAnimator.play_upper` / `play_full` (nothing added to the animator). Per-clip data: `data/powers/bending_clips.json` (made by `tools/anim/make_bending_sidecar.py` from `measure_events.gd` + the new `tools/anim/bending_measure.gd`).
- **Data:** `anim` lists (bending clip first, the old clip(s) kept after it so a stock clip is always last) and `anim_mode` set on: powers `bn_water_whip/mend/tide_wall/flow/shape, bn_gust/air_step/cyclone, bn_stone_fist/rampart/quake, bn_flame_jab/fire_wheel/dragon_breath, bn_storm`, `st_palm/circ/step/nine/shield/flowing_palm/thunder_palm/breath_gather/nine_breaths`, `kn_guard/brace/bulwark/charge/shoulder_rush` (`data/powers/{bending,sect,knight}.json`); legacy `fire_*`, `water_*`, `wind_gale_burst/dash/whirlwind`, `earth_*`, `lightning_spark/chain`, `qi_gathering/barrier`, `fist_deflecting_palm/earthshaker` (`data/skills/*.json`). Cultivation and meditation use `Cultivate_Yoga_Floor_Flow`, guard stances use `Guard_Ready_Defensive`, charges use `Fire_Stride_Strike_F`.
- **Who plays them:** the player via `technique_caster._play_clip` (now `BendingLibrary.play_cast`, same call sites, same fallback clips); NPC casters via `soldier.gd` (`_on_cast_started`, so chanted casts show Spellcast_Raise first, then the bending clip at windup start; non-bending abilities keep the old Spellcast_* calls).
- **Timing:** `play_cast` scales `anim_speed` by `clamp(hit / windup, 0.75, 1.8)` so the clip's strike frame (`hit` in the sidecar, seconds inside the played window; 0 = flow clip, not retimed) lands near the technique's windup (the release the runner and TechniqueVfx use). Strike frames come from `measure_events.gd` (hand/foot reach peak); `Fire_Punch_Kick` (kick at 2.4 s) and `Fire_Stride_Strike_F` (2.75 s) are set by hand. Long takes are trimmed to about 2 s around the strike.
- **Clip fixes (at install, GLB unchanged):** root travel track removed (clips are in place: `Air_Evade_L/R` 4 m of travel gone; the dash distance still comes from the caster's `_resolve` dash); pelvis lift curve while a bone is under the floor (`Fire_Box_Combo_A`, `Fire_Stride_Strike_F`, `Water_Whirl` were 8 cm under; now every clip is within 2 cm; check with `godot --headless -s tools/anim/bending_measure.gd -- --prepared`); `Earth_Punch_Hold_Deep` is played 0-4.6 s and the last 0.7 s ease back to the first pose.
- **Test:** `tests/test_technique_anims.gd` (every mapped clip exists in the library, fixes hold, stock clip last, routing and retiming). Capture: `tools_qa/anim_tech/bending_cast_capture.tscn` (player casts one technique per element); sheet `bending_anims_sheet.png`.
- **Blending polish still open (yours):** (1) the clips are cut mid-motion by the trim, so the first frame is a mid-action pose and the OneShot fade-in (0.06-0.08 s) shows a small pop; a short per-clip lead-in or a longer fade for bending clips would hide it. (2) `upper` mode plays only spine and arms over locomotion: for strikes while running the legs keep jogging; a few clips (`Fire_Box_*`, `Earth_Lunge_*`) were made for planted legs, so consider rooting the player (a brief move lock for `full` casts) or a lower-body freeze. (3) `full` clips override locomotion for their length (2-3.4 s for the flow clips): consider letting input cancel via `stop_full()` after the hit frame. (4) hit/release events are only used to retime speed; no per-clip `ElementFX` spawn frame callback exists yet (TechniqueVfx still spawns at the runner's windup), so a hand bone follow for the VFX origin would line the flash up with the fist. (5) The Lightning clips remain placeholders; `Water_Lean_Sway_A` is a walking sway (bn/st flow only). (6) Crossfades between two bending clips in a row were not tuned.

## Style G (local art-director pass, 2026-10-01): target 03 gate market
Skills: `ashes-style-g`, `ashes-style-g-assets`, `ashes-style-g-qa` (updated with this pass). Sheets: `docs/art/style_g/compare/` (`2026-10-01_over_before_target_after.jpg` is the one to send).
- **Score (honest, PC GPU, Mobile renderer):** cloud kit re-scored ~56/100 (hero 2: grey-helmet head; light 5: pink LUT; material 4). After this pass ~64 (hero 5, light 7, material 5, colour 7). Ship bar 75 not reached.
- **Hero model** (local owns model/materials; Codex owns animation): `scripts/actors/hero_outfit.gd` = one skinned mesh on the UAL skeleton (tunic skirt, jerkin, hood collar + drape, bracers, belt, satchel, pouch). Used by `lab_chars.hero_g()` and by `player.gd _build_body` for the default hero (no appearance). Animation code untouched; every UAL clip drives it. Open: satchel strap, shaggy hair, real hood.
- **Surfaces:** weathering in `lab_polished(_lite)` from `assets/generated/style_g/weather_pack.png` (`StyleG.WEATHER` per role). Bump off (sparkled). Vertex AO not baked yet (height AO only).
- **Light:** LUT mid `8a8a94`, sun `ffd396` x2.9, ambient 0.56, contrast 1.38; baked `resources/style_g/*.tres` re-baked.
- **LOW:** 286k tris / 114 draws (was 325k on the PC Mobile renderer, 379k xvfb): guard lod1, folk lod1 beyond 10 m, LOD2 houses beyond 8 m. gltfpack/impostors not needed for the lab; still the lever for the game town.
- **Phone:** S22 was NOT connected during this pass (`adb devices` empty), so no phone fps yet. A debug APK with the lab bench was exported to `C:/Users/Jonna/Documents/sg_build/` (see the QA skill, "Phone", for the one-line bench command per tier).
- **For the cloud:** (1) apply StyleG env/sun/fill + `material_for` in the game town (the game `gate` shot still uses the old environment); (2) HUD vs target 03: the game has compass, portrait, joystick, round attack/dodge buttons; missing the stats card (gold, merit, soldiers, health/stamina bars, Fed/Rested) and the right column of round labelled buttons (Map, Look, Lock, Sneak, Talk) plus the two "+" quick slots.

- **Pass 2 (same day, ~67):** vertex AO bake (houses), sparkle fix (bump back at 0.3), deeper cobbles + gate block detail, calmer stall cloth, hood bag + shaggy hair tufts + strap on the jerkin, brown boots, blue guards, VAT far crowd, warmth 1.46 -> 1.42. LOW 297k/128. Codex merge (PA_wt_codexint, 0fa52409) not on origin yet: outfit NOT re-verified on Codex's new clips. S22 still unplugged: no phone fps.

- **Pass 3 (~70):** contrast/warmth grade (metrics now within the QA ranges except contrast 0.22 vs 0.23), satchel strap continuous across the front. Spring bones NOT added (would need new bones on the shared skeleton). Codex merge 0fa52409 still not on origin; S22 still unplugged.

- **Pass 4 (~71):** outfit checked on all 62 Codex/UAL action clips after a43f7a1e (`tools_qa/style_lab/hero_preview.gd --clips=...`, sheets `docs/anim/hero_outfit/`); skirt front now follows the thighs (high-knee jumps/tucks pierced it). Ivy 5 -> 3 vines (green metric 0.053 -> 0.035). Lab regression from the game rollout fixed: `goods` hue_var only in game_mode (lab goods have COLOR.a = 1 -> every barrel/sack turned yellow). **Not done by local (needs owner OK):** the Loco_Pivot180 wiring and run-stop sword pop in player.gd are animation behaviour, which the owner reserved for Codex.

- **Pass 5 (10-05, ~73):** QA camera matches target 03 framing (full-body hero). For the cloud/Codex: the game camera should frame the hero full-body like target 03 (about 3.8 m back, 1.8 m high). Placement/build-kit agent owns placement; local owns light/material/hero look. Phone still unplugged.

- **Pass 6 (10-05, ~74):** calmer character saturation (lab_char 1.3 -> 1.1, StyleG + lab), olive tunic, darker boots, wood/goods saturation 0.9. **BROKEN ON ORIGIN (for cloud):** `player.gd` preloads `res://scripts/actors/chase_camera.gd` (added by aca4555b "Combat feel") but the file was never committed: player.gd fails to parse, so the game cannot spawn the player. Please commit the file.

## Region 1 look pass (local, 2026-09-30): valley, landmarks, horizon, biome patchwork
- Built: the Hollin's Reach valley (upper Ashrun: cliffs, falls, terraces, ruins, Stone Gap reveal, gorge gate), the Drowned Bell + Emberglass Ferry, Crownstead Mill Hill, Stagborn Glade, the Wyrm's Ribs; far horizon (whole-world low mesh + canopy domes), biome map + field patchwork, warm rock, golden-hour sky, river-carve fix, updated parchment map.
- Code: `scripts/region1/region1_{terrain,landmarks,look,horizon}.gd`, `shaders/region1/{biome.gdshaderinc,horizon_*,waterfall}`, data in `data/region1/{landmarks,terrain_stamps}.json` + `data/region1/terrain/`.
- Hot-file one-liners (world_gen, region_sites, region_dressing, main.gd daylight, terrain shader): see `docs/regions/HOOKS_FOR_CLOUD.md` "Region 1 look pass". Please keep them when merging; `--r1off` is the A/B switch.
- Two valleys kept (Hollin's Reach = public story valley, Hidden Vale = secret bowl): decision in `docs/regions/LOOK_R1.md` 3b. Hidden Vale fixes (item 2 of the cloud handoff) in 3c; small edits in `vale_look.gd`, `hidden_valley.gd` (`_put`, paint litter 0.3->0.1), `exploration_director.gd` (stream focus during the flyover), `main.gd` (`terrain.focus = Engine.get_meta("stream_focus", focus)`), `terrain_streamer.gd` (`slope_basis` for floor cards).
- `godot -s` tools that touch WorldGen may fail to compile when a dependency uses an autoload; run them through `tools_qa/region1/run_tool.tscn -- --tool=res://...gd`.
- Tools: `tools_qa/region1/look_capture.gd` (multi-view shots + perf), `bake_valley.gd` (+ `erode_valley.py`, dandrino erosion detail), `bake_biome.gd`, `walkin.gd` (Movie Maker walk), `asset_sheet.gd`.

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

## Clips available for Codex (added 2026-09-28, 100STYLE locomotion set)

New library: `kingdom/assets/incoming/characters/_library/UAL_Extra_100STYLE.glb` (14 clips, CC BY 4.0, credited
in `kingdom/CREDITS.md`; not yet in `Assets.UAL_FILES`). Fills the **directional/styled locomotion** gap — UAL1/UAL2
only have straight `Walk_Loop`/`Jog_Fwd_Loop`/`Sprint_Loop`, no turns, no strafes, no backward walk, no start/stop
transitions. Preview: `characters/_previews/100style_poses.png`.

| clip | what it is | suggested use |
|---|---|---|
| `Style_Neutral_Walk_Loop` | forward walk cycle, different gait feel from UAL's `Walk_Loop` | alt/varied villager walk |
| `Style_Neutral_Run_Loop` | forward run cycle | alt run, or blend target for run speed tiers |
| `Style_Neutral_WalkBack_Loop` | backward walk | player/NPC backing away, retreat, dialogue distancing |
| `Style_Neutral_Strafe_Loop` | sideways walk | strafing around a locked target in combat |
| `Style_Rushed_Sprint_Loop` | a faster, more urgent gait than UAL's own `Sprint_Loop` | fleeing NPCs, alarm state, top player speed tier |
| `Style_Walk_Start` | non-looping accel from standstill into a walk | play once when leaving `Idle_Loop`, before crossfading to a walk loop |
| `Style_Walk_Stop` | non-looping decel from a walk into standstill | play once before `Idle_Loop` when the player/NPC stops |
| `Style_Turn_InPlace` | non-looping pivot turn, feet stepping around | snap-turns, guard patrol direction changes, dialogue facing |
| `Style_Guard_March_Loop` | stiff, formal march | town guards / soldiers on patrol routes |
| `Style_Old_Walk_Loop` | hunched, slow gait | elderly NPCs (works well with the CDmir old lady) |
| `Style_Wounded_Walk_Loop` | limping walk, weight favouring one leg | low-health player/NPC movement, post-hit-reaction locomotion |
| `Style_Sneak_Walk_Loop` | crouched, careful walk | stealth movement; complements the existing `Walk_Stealth` (upright, faster) |
| `Style_Shielded_Walk_Loop` | walk with a raised/carried-shield stance | guards and soldiers holding a shield up while moving |
| `Style_Unarmed_Punch_Idle_Loop` | a punching-ready idle stance/shuffle | bandits/brawlers without weapons, boxing-style NPCs |

All are **in place** (no baked root travel — same convention as the other `_library` files), 24 fps after resampling
(matches the rest of the library). Blend time suggestion: 0.15–0.2 s for the loops, 0.1 s for `Style_Walk_Start` /
`Style_Walk_Stop` / `Style_Turn_InPlace` since they're short transitional clips, not loops.

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

## 2026-09-28: for Codex and the cloud session (from local)
- `procedural_rig.gd` now has a **rig budget**: only the nearest `Quality.value("rig_budget")` NPC rigs (0/3/6/10 per tier) within 25 m run
  IK and springs. The player is always active. If an NPC looks stiff up close, raise the budget. Don't remove it.
- The village lag was an **engine error flood** ("axis must be normalized" from `Vector3.slerp` / `set_axis_angle` on non-unit vectors) costing ~16 ms per rig stage.
  Please normalize vectors before `slerp`, `Quaternion(axis, angle)` and `rotated()`, and check your logs for per-frame ERROR spam. See `docs/qa/PERFORMANCE.md`.

## 2026-09-28: engine switched to Godot 4.6.3 (all sessions, please use it)
- Path: `C:\Users\Jonna\Downloads\Godot_v4.6.3-stable_win64\Godot_v4.6.3-stable_win64(_console).exe` (official build, SHA512 verified).
  The launchers and all `tools/qa/*` / `kingdom/tools_qa/*` scripts now default to it; the bats fall back to 4.6.0 if it's missing.
- Why: 4.6.0 crashed (0xC0000005) on **every** quit, even from an empty SceneTree script. 4.6.3 exits cleanly, and on the village route
  it measured p99 29.3 → 24.9 ms and hitches 43 → 21. Details in `docs/qa/stability.md`.
- Heads-up: `kingdom/.godot/extension_list.cfg` was missing, so Terrain3D, LimboAI and godot-sqlite were **not loaded** in dev and QA runs
  (exports do load them). Opening the editor once regenerates it.

## 2026-09-29: free addons + impostors (local, done)
- Installed/tested Phantom Camera (enabled, idle autoload `PhantomCameraManager`), Debug Menu, Material Footsteps, SimpleGrassTextured, VoronoiShatter; Sentry via `tools/install_sentry.sh` (not committed). Nothing is wired into gameplay. Demos: `kingdom/tools_qa/addons_demo/`. Table, perf, plans: `docs/addons/README.md`.
- **Octahedral impostors** (own baker `kingdom/tools/impostors/`, 6 baked in `assets/generated/impostors/`): in a 3000-tree + 80-house scene hybrid (full < 45 m) gave 142 vs 75 fps, GPU 2.9 vs 12.4 ms, 0.42M vs 2.0M tris. Cloud session: please use `*_octa.tscn` beyond ~45 m in tree/building scatter.
- Godot rewrites `project.godot` (drops renderer lines, adds `[debug]`/`[sentry]`) whenever the editor/import runs with Sentry installed: check `git diff kingdom/project.godot` before committing.

## Elemental VFX set (fire, water, earth, wind, lightning, ice, light, dark)
- 61 pooled scenes in `kingdom/scenes/vfx/elements/` (charge, aura, projectile, beam, impact, aoe, status per element + generic slash/sparks/dash/level-up), spawn API `kingdom/scripts/vfx/element_fx.gd` (`ElementFX.play/attach/projectile/beam/aoe/chain/slash/dash/level_up`), shaders `kingdom/shaders/vfx_elements/`.
- Catalogue, API, animation-clip pairing and perf table: `docs/art/vfx_elements/README.md`. Gallery: `kingdom/tools_qa/vfx_gallery/elements_gallery.tscn`. Scenes are generated by `tools_qa/vfx_gallery/build_element_scenes.gd` (rebuild after editing).
- Not wired into gameplay: casters should call ElementFX from their animation events (see the pairing table). Existing `VFX` (vfx.gd) is untouched.

## 2026-09-29: free animation library (from local)
114 martial-arts / acrobatics / reaction / casting / weapon clips on the UAL skeleton in `kingdom/assets/incoming/animations_free/` (CMU + KayKit CC0). Ready for wiring by Codex; see `docs/anim/free_library/README.md`. Not yet in `Assets.UAL_FILES`.

## 2026-09-29: free animation library (from local)
114 martial-arts / acrobatics / reaction / casting / weapon clips on the UAL skeleton in `kingdom/assets/incoming/animations_free/` (CMU + KayKit CC0). Ready for wiring by Codex; see `docs/anim/free_library/README.md`. Not yet in `Assets.UAL_FILES`.

## 2026-09-29: boot flow QA and main scene changes (from local)
- Boot chain (real path): engine splash -> studio intro (`scripts/boot/studio_intro.gd`, tap to skip) -> title splash -> first run (language, privacy, how to play) -> main menu -> New Game -> loading -> WorldLoading veil -> birth cutscene -> gameplay. Main menu and pause menu labels now use `tr()` keys; Quit is hidden only on iOS.
- `main.gd` `_process` returns early while the world is still being built (terrain/army/hud nil during `_ready` awaits); `load_watcher.gd` tolerates a freed veil.
- QA driver: `kingdom/tools_qa/boot_flow/boot_flow.gd` drives the flow with synthetic taps and saves stills (contact sheets: `docs/qa/boot_flow/`). Run: `godot --path kingdom --resolution 1280x720 --rendering-method mobile -s res://tools_qa/boot_flow/boot_flow.gd`, env `BOOT_FLOW_OUT=<dir>`, `BOOT_FLOW_SKIP=1` skips the studio intro by tap (no user args: those make boot skip straight into the game, the QA `--skip-intro` path). It restores `user://settings.cfg` at the end. Result: BOOTFLOW OK.
- Import gotcha: after a disk-full import, `.godot/imported` can hold truncated scenes and empty font `.import` files; delete the bad ones (and their .md5) and re-import.
## 2026-09-29 (local): water views are CPU-bound, RegionDressing subtree is the biggest measured cost (cloud-owned code)
Measured with `tools/qa/water_shots/prof.sh` at the lake, HIGH: switching off `RegionDressing` (process mode DISABLED on
`scripts/world/region_dressing.gd` and children) drops the frame from 28.0 to 20.7 ms (p99 50 -> 28). Not a rewrite request yet:
please check what in that subtree runs every frame (flicker lights, `Breakable` bodies, VFX, per-site nodes) and whether sites can be
built with fewer nodes, and drop `_process` work when no site is within BUILD. I will run `--census` to name the node classes.

## 2026-09-29 (local): perf round 2 (for the cloud session)
- **RegionDressing is not a cost** (0.085 ms/frame, nothing built at the lake; the earlier 7 ms claim was noise). Only change there: two QA counters (`dbg_usec`, `dbg_frames`) around `_process`; behaviour unchanged. Do not spend time optimising it.
- **`autoload/world_sim.gd` `_simulate_slice` is now time-budgeted** (`BUDGET_US`, near-player people first, `NEAR_RADIUS` 320 m; `UPDATES_PER_FRAME` removed). Same results (dt-based movement), about 0.7 ms/frame less CPU. Two QA counters `dbg_slice_usec/dbg_frames`.
- `boot_flow.gd` now drives character creation (Next x3, Begin Life). `spinning-wheel.glb` imports without its broken animation (fixes "Node not found spinning-wheel/spindle").
- Measurement rule: the PC is shared; only compare configs from the same run (`water_prof.gd`, `--only=`, `--rdprof`, `--sysprof --systier=N`).

## 2026-09-30 (cloud -> local): visual QA + perf on a real GPU (cloud container keeps OOM-killing renders)
The cloud container has ~15 GB shared by all agents; full-game captures die. These need your GPU/RAM. Commits: `c30ad754` (dungeons), `eadbfd71` (Region 1 world, story, Hidden Vale, POIs). Skills to read first: `ashes-cloud-testing`, `ashes-region-content`, `ashes-visual-qa`, `ashes-handoff`.

1. **Region 1 world sweep (nobody has seen it rendered).** 30 views in `kingdom/tools_qa/region1/world_views.json`, capture script `kingdom/tools_qa/region1/look_capture.gd` (the cloud wrapper was `run_cap.sh <tag> ALL`). Check every settlement landmark, Highwatch Keep, the 3 Elder Stones + waymark road, Crownstead Steward's Hall, Scar Mouth Arena, Dawn Throne chapel + guild hall, Eastern Gate queue, Grimfen Pass snow + aurora, Solkar camp (summer). Look for floating/clipping/overlapping props, and whether each town is recognisable. Done = contact sheet + list of bugs (fix placement offsets in `region1_world.gd` / `region_dressing.gd` part y-offsets yourself if trivial, else list them here).
2. **DONE (local, 2026-09-30, see docs/regions/LOOK_R1.md 3c):** **Hidden Vale bugs** (see cloud sheet frames 2, 6, 17): boulders float mid-air inside the gorge (`scripts/world/hidden_valley.gd` / `vale_look.gd`), floating strips in the herb-patch view, the last cutscene frame shows void past the terrain ring (check the real horizon mesh in-game), gorge walls plain, ground a bit olive. Art fixes are yours; placement code fixes are fine too (tell us the lines).
3. **Caves on real terrain:** hidden entrances (waterfall behind Hollin Falls, vines, rockfall, night) were only shot on a flat stand-in hill. Walk into one of each theme and fight one boss (`scripts/interiors/dungeon_*.gd`, harness `tools_qa/caves/caves_standalone.gd`). Cave mouths were too white (switched to textured rock, not re-rendered).
4. **Map carve rim:** carve a ward stone and confirm the teal rim (`scripts/region1/r1_map_layer.gd`) reads on the map.
5. **Perf round 3 on the real GPU + phone:** city views ~300 draw calls vs 150 budget; Hidden Vale wide views 165-180 draws (eye level 121-149); dungeons ≤ 74. Stalls/plants LOD and guard impostors were the next ideas.
6. **Play the first 20 minutes + Act I on the phone** ("The Stones Are Dimming"): the headless autoplay passes; the in-game run was OOM-killed at the Blessing Eve step.
7. **Asset audit (user request):** list imported models/animations that nothing references (meshy_free packs, animation libraries, region kits) and propose where each goes; place the art-side ones.
   **Audit DONE (cloud-side, from git, no Blender needed):** `docs/qa/ASSET_AUDIT.md` + `docs/qa/asset_audit_unreferenced.csv` (413 MB UNREF, 555 MB unused by the game incl. tools-only; 68 MB safe to exclude from the APK now). Still open for local: the placement and art-side items in sections A and E (scale and y-offset checks on the GPU build), decimating `generated/scan`, and a measured before/after test export.
8. **TikTok teaser** fallback if the cloud video agent fails again: 15-30 s vertical 1080x1920 gameplay (gate market, aerial, combat, building, war map, keep).

Free CI now runs the whole gdUnit suite + secret scan + 90 MB guard on every push (`.github/workflows/tests.yml`, see skill `ashes-ci`), so you don't need to run the full suite locally before pushing; check the Actions tab after.

## 2026-10-01 (cloud -> local + Codex): vertical slice "perfect the basics" (read docs/design/VERTICAL_SLICE.md)
The user watched the full 1:47 build. Don't push graphics up globally; perfect the basics around Thornfield. Your items:
1. **P0 ground pass:** terrain seams and dark square patches outside town, road edges blending into mud and grass, dirt beside buildings, wheel ruts and foot traffic at gates and markets, stones, weeds, broken wood and drainage, contact shadows where buildings meet the ground, decals at doors, stalls, wells and stables, subtle elevation instead of dead-flat lots. Run `world_lint` (skill `ashes-world-lint`) after any placement change. Ask cloud for code changes in `settlement_builder.gd`, `region_dressing.gd` or `terrain` if needed.
2. **P0 player character (with Codex for animation):** proportions (currently small, thin, simple next to the world), walk, run, idle variants, accel/decel, turning, foot IK, weapon hand, cloth and hair springs where cheap, plus exhausted, injured and carrying gaits. Later: outfits per career.
3. **P1 building and material unification:** one timber thickness, plaster, stone size, roof, window, door and foundation standard, the same weathering and saturation. Plus 20–30 modular detail props (chimney, flower boxes, firewood, sign, damaged plaster, shutters, barrels, laundry, fence). Cloud will attach them procedurally per house; tell us the asset keys.
4. **P1 look pass for the Thornfield districts and the runestone road identity** once cloud's layout lands (screenshots, judge against the art reference).
**Codex:** item 2 animation (locomotion set, turns, foot placement, gait variants).

## 2026-10-01 (cloud -> local): verify town life, HUD and travel on the real GPU (the cloud capture was unusable)
- **Micro-events and schedules** (commit "Town life: ..."): run `kingdom/tools_qa/micro_events/events_capture.tscn --skipintro` in the third-person view, and dismiss the Scribe job modal first. Check all 69 scenes look right; `broken_cart` failed to start and `crate_haul` was never retested. Then run `tools_qa/micro_events/budget_probe.tscn` and report near-NPC AI ms with 24 NPCs and 2 events (budget 2 ms).
- **NPC AI:** confirm wolf flee, firefighting and the green build ghost (`/tmp`-style scenes are listed in the NPC AI notes; re-create with the e2e driver).
- **HUD:** check it on the S22 including the safe area and 4:3, and check the one-line quest tracker.
- **12 km world:** repaint the parchment map (`tools_qa/map/run_paint.sh`, see `docs/LOCAL_PC_TASKS.md`). Play one coach trip, one night camp and a long road walk, and say whether travel feels right.

## 2026-10-01 (cloud -> local): Style Lab on the phone (user wants to choose the look)
The user isn't happy with the overall look on phone, or with the main character. Cloud is building `kingdom/scenes/style_lab/style_lab.tscn`: 4–5 small dioramas of the same medieval street corner plus the main character. The styles are A current, B storybook painterly, C grounded medieval PBR, D polished stylised, and E a low-end-safe version. When it lands:
1. Render it on the GPU (`--shot=style_lab`) and **run it on the S22** (flag `--style_lab`). Send the user screenshots or a short screen recording of each box, plus fps and draws per box.
2. Upgrade the character models in each box with the best free models you have. The asset audit's unused list (555 MB) is the first place to look.
3. Don't apply anything game-wide until the user picks a style. After that, the chosen style is rolled out (`docs/design/STYLE_LAB.md`).
**Unused models (user request):** keep the audit list. Anything that doesn't fit Region 1 gets tagged for Region 2 in the audit doc, so nothing is wasted.

## 2026-10-01 (cloud -> local + Codex): STYLE G IS THE GAME STYLE (user decision). Art pass to bring G to 75%+
The user picked Style Lab box **G** (`kingdom/scenes/style_lab`, run `--style_lab --box=G`), the recreation of `docs/art/reference/03_TARGET_gate_market_detailed.webp`. It's at about 55–60% of the target today. Cloud is writing the skills `ashes-style-g`, `ashes-style-g-assets` and `ashes-style-g-qa`, refactoring G into a reusable style resource, and adding ivy, props, crowd, arch and warm bounce in the lab. **Your art pass** (judge on GPU and the S22 against 03 with `ashes-style-g-qa`):
1. **Hero (top priority; the user dislikes the current one):** a hooded traveller. Brown hair, green tunic, hooded brown leather vest, satchel, bracers, boots, believable proportions, under about 6k tris, on the existing UAL skeleton. Codex checks animation fit.
2. **Houses and stalls in G quality:** weathered painterly-real timber, plaster and stone (replace the flat Meshy atlases), LOD0/1/2, at 1K textures on the phone.
3. **Foliage and dressing kit:** ivy, flower boxes, potted plants, produce, pottery, sacks.
4. **Lighting on the real GPU:** golden bounce, local contrast, and 2 shadow splits at 60 m on the phone. Report fps and draws for G on the S22.
5. Then roll G out to Thornfield first (`docs/design/VERTICAL_SLICE.md`), then all towns.
## 2026-09-30 (Codex PR #4): feel/system continuation
- Branch `gpt/locomotion-jump-integration` is synced with the latest fetched Claude head `b6cc215c` by merge commit `89498a11`; review the branch before cherry-picking or merging because it touches player, HUD, input, life and combat-adjacent code.
- Preserved Claude's player appearance/death flow while keeping the jump-enabled animator, local hit-pause helper, and dodge lane probe. Controls are now **Space = Jump, K = Dodge, F2 = Pack Skills**; the central input map, tab hotkey, and `docs/controls.md` agree.
- Added 0.25 s dialogue shade/UI and portrait reveals (F13 presentation only; camera framing inside the speaker/cart remains open), plus event-only dodge sweeps to choose a clear side lane around a hostile capsule (F15). Claude should visually verify both in the real game, including mobile touch.
- Added restored Journal responses for persistent scout offers and documented that the shown ongoing wage is not active payroll yet; see `docs/concepts/CODEX_SYSTEMS_HANDOFF.md`.
- **Runtime validation remains pending.** No test suite was run in this continuation; `git diff --check` passed. Keep the captured-game validation list in `docs/anim/CODEX_LOCOMOTION_JUMP.md` current.

## 2026-09-30 (Codex): NPC need continuity handoff
- Initial source review found that `UtilityBrain` needs did not survive body LOD or save/load. This finding is superseded by the partial implementation below.
- Added the handoff and current-source snapshot; these docs now distinguish implemented persistence from unfinished offline progression.

## 2026-09-30 (Codex): single-owner NPC position integration
- `Villager` physics bodies already route and move near actors; `WorldSim._step()` also advanced their data positions until the next 4 Hz `PopulationLOD._write_back()`. Added a packed ownership flag so the world slice continues schedule/economy updates but skips position integration for embodied residents.
- Promotion writes the route-cleared spawn position into `WorldSim` and claims ownership. On body exit, the resolved final position is stored and ownership is released. Time skips remain explicit bulk settles followed by `Villager.resync()`.
- Updated the current-state sections of `NPC_CONTACT_LOD_CONTRACT.md` and `NPC_LIFE_LOOP_DESIGN.md`; the old e3563fc4 findings remain clearly labeled as historical. The distant data/sprite mover still follows direct targets and is the next NPC/building pathing gap.
- Source reviewed and `git diff --check` passed. No Godot runtime check or test suite was run; confirm body lifecycle/reset ordering and movement feel in the playable project before merge.

## 2026-09-30 (Codex): local routes for visible sprite residents
- Selected sprite residents near their home settlement now check direct-line clearance against the existing `StreetGraph`. Only obstructed routes claim temporary position ownership and move along validated waypoints; clear routes keep the existing `WorldSim` mover.
- Route planning consumes the existing two-per-physics-frame budget shared with near villagers. When that budget is unavailable or a path is invalid, the sprite holds its last safe position and retries; no 3D navigation agent, NPC node, or physics body was added.
- Route state is discarded when a sprite leaves the visible sprite set or a time skip settles the population. Data-only residents and field/forest travel outside the local graph remain coarse direct movement. This narrows the building-crossing gap but does not solve all distant-world navigation.
- `NPC_CONTACT_LOD_CONTRACT.md` and `NPC_LIFE_LOOP_DESIGN.md` now distinguish these current limits. `git diff --check` passed; no runtime or test suite was run. Validate blocked routes, target changes, LOD promotion/demotion, time skips, and frame cost in Godot.

## 2026-09-30 (Codex): source-specific NPC position ownership
- Replaced the boolean `WorldSim.external_position_owner` marker with a packed instance-ID owner token. A release now succeeds only when its caller is still the recorded owner.
- This closes a concrete LOD transition race: `PopulationLOD` can `queue_free()` a body and route the same resident as a sprite before the old body's deferred `_exit_tree()` runs. The old body's cleanup previously could release the sprite's claim and write its stale position over the routed position. Body and sprite movement owners now have distinct tokens, so delayed cleanup cannot displace a newer claim.
- Updated `NPC_CONTACT_LOD_CONTRACT.md`. `git diff --check` passed; no Godot runtime check or test suite was run. Validate repeated body↔sprite transitions and world reset with deferred body exits during Claude's captured-game pass.

## 2026-09-30 (Codex): NPC need continuity transfer and save layer
- Added five flat per-person need values, game-hour timestamps, and validity bytes in `WorldSim`; the save payload uses versioned packed fields. Old/malformed fields use the seeded fallback, and loading clears prior in-memory need state first.
- `UtilityBrain` exports/imports the existing five needs without changing scoring or rates. Villagers restore on promotion, sync after the existing staggered brain tick and on exit, and preserve state through resync. A body advances at most the existing two-game-hour catch-up bound; schedule-aware unembodied need progression remains open.
- `Life.restore()` refreshes active brains from the selected save immediately, so loading while still in the world does not let a subsequent resync overwrite saved need values with the previous session. Deferred body cleanup now unregisters only its own instance, preserving a newly promoted body's registry entry.
- Need writes require the current Villager instance to own that resident row, preventing a deferred old body from saving into a reset/new run.
- Updated `NPC_NEEDS_CONTINUITY_HANDOFF.md`, `NPC_LIFE_LOOP_DESIGN.md`, and `CODEX_SYSTEMS_HANDOFF.md` with implemented behavior and remaining work. `git diff --check` passed; no runtime or test suite was run. Validate old/new save round trips, LOD churn, reset/deferred exits, time skips, serialized size, and mobile cost in Godot.

## 2026-09-30 (Codex): time-sliced unembodied need progression
- Added `scripts/sim/npc_need_rules.gd` as the shared source for depletion rates, deterministic personality traits, and meal hours used by both embodied brains and WorldSim rows.
- `WorldSim._step()` now advances only initialized, non-body-owned need rows when those residents are already visited by the existing time-sliced simulation. The existing `advance_hours()` settle loop does the same once for unembodied rows; embodied Villagers retain exclusive brain ownership and apply their existing two-hour catch-up.
- Coarse offline rules use the existing three meal hours, half-hour meal recovery at the current eat rate, and night rest when the resident's shared schedule is home. The 24-hour cap bounds stale/corrupt catch-up. No new all-population per-frame pass or resident Nodes were added. This is a continuity approximation, not exact daily act history.
- On save load while the world is alive, active brains are refreshed from deserialized rows; Villager brain ownership is re-established before the next simulation step. Runtime/save-size/mobile-cost acceptance still needs a real Godot capture; no tests or runtime were run here.
- Save format is now version 2 with double-precision need timestamps; the reader accepts version 1's float32 timestamp format so an already-created Codex-branch save remains readable.

## 2026-09-30 (Codex): route around solid plaza carts
- `SettlementBuilder` now writes the actual six solid cart placements into the shared settlement plan as fitted horizontal obstacle boxes. The existing `StreetGraph` syncs those boxes lazily, including when the graph was cached before settlement dressing finished, and rebuilds its route edges once to avoid those cart footprints.
- Cart placement and collision proxies are unchanged; this only gives local NPC routes the same blocker information already used by the physical world. No broad prop rewrite or extra runtime navigation nodes were added.
- Updated F17 in `docs/anim/FEEL_AUDIT.md` and the current `NPC_CONTACT_LOD_CONTRACT.md`. `git diff --check` passed; no runtime or tests were run. Validate route paths through the plaza and verify detours do not deadlock at stalls.

## 2026-10-05 (cloud): asset-use pass (docs/qa/ASSET_AUDIT.md), LOCAL list
Cloud placed the unused models through the data tables and builders (details: `docs/qa/ASSET_AUDIT.md`, "2026-10-05 pass") and excluded what does not fit Region 1 from the Android and iOS export (`kingdom/export_presets.cfg`, nothing deleted). What is left for the local session (art rework or GPU checks):
- **Look pass on a GPU build** (cloud only had xvfb at the LOW tier): yaw and scale of the new fill clusters (`data/region1/world/fill_sites.json`; house fronts face +y, if one faces the wrong way add 180 to its yaw), Style G colour of the new pieces (`lantern_post_purple` and `lamp_post_purple_bracket` at the Scar Mouth Arena, `tower_pink_flag` at Greywatch, the two dragon statues at Emberfall and the Grimfen winter gate), the code-built halls (`scenes/interiors/steward_hall_interior.tscn`, `keep_hall_interior.tscn`: plain plaster shell, add a real room mesh or textures), frame cost of the new roadside clusters on the S22.
- **Decimate then place** the nine 2-3 MB photo scans in `assets/generated/scan/` (dandelion_01, dead_tree_trunk, fern_02, nettle_plant, root_cluster_01, shrub_03, stone_fire_pit, tree_stump_01, tree_stump_02): they are tagged "reserve" and are in the export `exclude_filter` until then; remove their lines from both presets when they are placed (`tools/blender/decimate_scans.py`).
- **Horse_White / Husky** are loaded from the Quaternius source glTF (3.6 / 3.1 MB with embedded textures). Convert them like `animals/quaternius/horse_grey.glb` (atlas, trimmed) and point `Critter.KINDS["horse_white"|"husky"]` at the converted files.
- **KayKit skeletons** (crypt enemies, `dungeon_creature.gd` kinds `skeleton_*`) keep their flat KayKit toon look; repaint or restyle if they clash in the crypt renders. Their weapons hang on `handslot.l/r` through BoneAttachment3D: check the grip rotation.
- **Rigged Meshy farm animals** (`Critter` kinds `cow_brown_a|b`, `cow_spotted`, `hen_meshy`, `rooster_meshy`): check scale against the Quaternius cow and the walk speed (`KINDS` speeds were copied from the Quaternius ones; `ANIM_GROUND_SPEEDS` has no entry for them).
- **Meshy MAYBE humanoids** (about 50 models in `docs/art/meshy_free_triage.md`, "needs rigging/pose and a paint pass") are still not optimized; the static `maybe/` pieces are decided in the audit CSV (column "Region 2 / reserve / reject").
- **Delete or archive** (repo size only, already excluded from the APK): the exact duplicate groups in audit section F (armor source copies, doubled `WoodenDockSet.glb`), `generated/nature`, `generated/village_inn|smithy|stall*`, `generated/fence_section.glb`, `polyhaven/models` (164 MB of sources), the legacy `quaternius/ultimate-animated-character` (keep `Goblin_Male` and the 7 dynamic ones), `ultimate-modular-men|women`, `ultimate-fantasy-rts`, `kenney/*`, `polypizza/*`.
- **Region 2 reserve** (tagged "reserve", excluded, keep in the tree): `quaternius/pirate-kit`, `kaykit/dungeon-remastered`, `quaternius/medieval-village-megakit`, `styloo/the-company`, `modular-wooden-docks` (a 308-part kit sheet, needs a builder), the 11 `meshy_free/water/bridge_*` footbridges (Region 1 has no 3-9 m water crossing: `tools_qa/asset_use/probe_world.gd --crossings` finds 0), `maybe/` brutes, gargoyles, hellhounds, relics.
- **Not touched** (other agents): animation libraries under `assets/incoming/animations_free*`, `ai3d/animations`, `characters/_library`, `kaykit/character-animations` is excluded from export only (clips are already merged into the `UAL_Kay_*` libraries).
- New `.import` files were generated only for the packs the game now loads (KayKit skeletons, Ultimate Monsters); every other pack without a committed `.import` is still unimported, so the editor will import it on first open (they are excluded from export anyway).


## 2026-10-06 Cloud LOW budget audit (cloud session; local performance agent: read before touching the same files)

**Method.** `kingdom/tools_qa/perf/low_budget.gd` (new, run through `--qa=`): teleports to fixed views, lets the dressing queue drain, then counts every GeometryInstance3D the camera draws (frustum plus visibility range plus sun-shadow reach, like `town_route.gd`'s census) as surfaces (about the colour-pass draws), triangles (LOD0 index counts times MultiMesh instances) and sun-shadow surfaces, attributed to cloud-added content versus older content. It also audits unique materials and textures per source. Run headless (`$GODOT --headless --path kingdom -- --adult --quality=low --qa=res://tools_qa/perf/low_budget.gd --out=x.json [--views=ashford,...]`): the xvfb + llvmpipe Vulkan boot stalls in this container, and headless has no draw counter, so the numbers are census surfaces, not `RENDER_TOTAL_DRAW_CALLS`. **Please re-run it on the PC with the real counters** (the script prints `measured_draws/prims` there). Views: Ashford benchmark street, Thornfield plaza, Redwater plaza, the Ash Hand bandit camp, the Rift mouth, the Thornfield Millers' Lane Meshy3 yard.

**Finding 1: the cloud's static additions are not why the phone is over budget.** At the plaza views (Ashford, Thornfield, Redwater) the cloud share is 0-6k tris and 0-4 surfaces. What every view carries, and is not cloud-added (yours): `HorizonGround` (region1_look) is **57,800 tris in every view** (a third to half of the whole view on LOW), SettlementBuilder buildings 16-46k, chars 20-64k (a single UAL villager is 6.8-7.8k tris, `armored/guard` 11.9k), terrain ground 8-14k. Static memory in the headless run grows 1.43 -> 1.60 GB across the six views.

**Finding 2: three cloud sources were heavy; now cut (LOW only).**
| source | before (LOW) | after (LOW) |
|---|---|---|
| Meshy3 re-rigged looks (7.0k tris, 1024 px) on embodied NPCs: Ashford / Thornfield / Redwater / camp | 14.0k / 11.0k / 11.0k / 14.0k tris | 2.9k / 0 / 5.8k / 2.9k (2.9k each, random look picks differ run to run) |
| Fence sections in fill + Meshy3 yards (Meshy `fence_picket_*`, plank, palisade, rail: 2.5-3k tris, no LOD1, the engine cannot generate one: unique flat-shaded vertices; 8-15 per yard) | 92+ pieces at 2.5-3k | generated Style G picket / rail (60-190 tris), same length and height |
| Wilds extras (Ash Hand camp, outpost, Rift): horse 7.0k, stall 4.5k, shields on every raider/soldier (4 surfaces each) | camp cloud 43 surf / 45.7k tris | camp cloud 22 surf / 26.5k tris |
| Meshy3 yard (Millers' Lane) | 11 surf / 34.2k tris | 12 surf / 15.1k tris |

Whole data set (`tests/test_low_budget.gd` prints it): fill_sites + meshy3_sites LOD0 triangles 1,613k all-tiers -> 1,071k on LOW (-34 %), worst single yard 49.9k (`fill_grimfen_gate`). Cloud share per benchmark view on LOW is now <= 6k tris / <= 4 surfaces at the three town views, 15k / 12 at the Meshy3 yard, 26k / 22 at the camp: inside 30 draws / 50k tris everywhere.

**What changed (all behind `LowBudget.low()`, tier LOW only; MEDIUM and up are untouched):**
- new `scripts/world/low_budget.gd` + `data/region1/world/model_tris.json` ([lod0, lod1] tris of every placed Meshy model, generated from the GLB headers).
- `region_dressing.gd`: thins heavy loose clutter of fill/Meshy3 sites (bouquets 1 in 4, wall battlement blocks 1 in 3, kegs 1 in 3, banners, hay, bushes, bench sets 1 in 2; parts with a collider are never skipped), fence proxy, LOD0->LOD1 swap at half the distance for the kit pieces (55/85 m -> 27/42 m before the 0.55 range multiplier).
- `thornfield/wilds_props.gd` (`model()`): LOD1 for wilds extras, small extras without sun shadow, heavy small extras with no LOD1 left out (stall). `bandit_camp.gd`, `outpost.gd`: no shield attachments on squads.
- `assets.gd` (`character()`): the seven re-rigged Meshy looks use their LOD1 (2.9k tris, 512 px) on LOW. At 7.0k tris they were on par with the UAL villagers (6.8k, not over budget), so no embody cap was needed; LOD1 makes them 2.4x cheaper than a UAL villager.
- Not changed because already cheap: town-kit pens (one MultiMesh per town, no shadows, 1 draw), clues and stashes (0-2 surfaces), livestock; shadows on small props are already dropped by `Quality._small_shadow` (3 m on LOW).

**Memory.** FillStyle already shares materials (cache per source material + treatment), `tests/test_low_budget.gd` pins it: two instances of one treated model hold the same material objects. Audit of the built world (headless): Meshy3 yards 45 instances -> 27 materials / 27 textures (one bake texture per model, not per instance); wilds 53 -> 34 / 14; town kit 16 -> 14 / 3. Textures over 512 px from cloud assets: meshy3 12, wilds 7, town kit 2, all capped to 512 on the phone by `mobile_texture_limit` (`meshy_dl3/`, `meshy_free/` are not HERO paths); estimated at the cap: meshy3 9 MB, wilds 4 MB, town kit 1 MB, the seven characters 1 MB. Cloud content is about 15 MB of texture memory, nowhere near the 3.2 GB: look at SettlementBuilder (29 MB, 103 textures, 24 over 512), chars (11 MB), region_look (11 MB), terrain.

**Still to do (local / Blender):**
1. `HorizonGround` 57.8k tris in every view: the biggest single LOW cut left. A coarse far ring or a lower subdivision on LOW.
2. 196 of the 287 Meshy models referenced by Region 1 data have no LOD1 (list: `model_tris.json`, entries with `[n, 0]`; worst: castle `wall_battlement_block` 4.0k, `wall_stone_railing` 3.0k, `bouquet_wild` 3.5k, `street_lantern_gothic` 3.0k, `stall_rug_wood` 4.5k, goblins/wolves/cows 6-7k). A Blender decimate pass producing `_lod1.glb` (about 25-30 %) would let the engine swap them everywhere instead of the thinning above (gltfpack/Instant Meshes in `ashes-external-tools`).
3. Baked fill/Meshy3 sites (`RegionDressing._bake_site`) merge each range group into one mesh: while any part is in view, the whole group's triangles draw. A smaller bake radius on LOW (split groups by 30 m cell) would cut the near yard further.
4. Re-run `low_budget.gd` on the PC and the S22 route after these changes; the S22 numbers are still owed.


## 2026-10-06 Cloud CPU / memory / save pass (cloud session): scripts only, NOT rendering

The cloud took **CPU, memory and save work only**. It did not touch models, LODs, textures, materials, shaders, lights, shadows, render
resolution, draw distances, foliage density, crowd counts or animation quality; GPU and rendering performance stay with the local session
(Perf pass 1-3, `docs/qa/RELEASE_READINESS.md`). Full numbers, method and file list: `docs/qa/CPU_MEMORY_SAVE.md`.

- **CPU** (headless PC, per rendered frame, best-of runs): Ashford 6.9 -> 4.8 ms, Thornfield 7.3 -> 5.3 ms, wilds 4.6 -> 3.2 ms; script time in callbacks
  3.9 -> 1.9 ms. Biggest: the tutorial bridge built a context every frame (0.94 -> 0.07 ms), WorldSim's far loop burned its whole 0.5 ms budget every frame
  (0.60 -> 0.17 ms), `Life._on_hour` was a 26 ms hitch every game hour because the economy ticked 8 282 goods rows in it (now 1.5 ms plus 15 spread jobs).
- **Edits near your files** (read before you merge): `ui/hud.gd` (`_ease_buttons` settles, same-value position writes skipped, `Probe` lines),
  `world/weather.gd` (`_key()` cache for the base / wrote bookkeeping, same writes), `world/grass_interactors.gd` (a slot is only re-sent when its value
  changed), `population/population_lod.gd` (only `Probe` timers), `world/exploration_director.gd` and `world/street_routines.gd` (throttles).
  Values reaching the renderer are identical.
- **Save**: schema 3. A save of 64 KB or more is stored zstd + base64 in the same JSON envelope (checksum, atomic write, `.bak` fallback unchanged);
  2 years of play is 2.0 MB of JSON and 0.36 MB on disk (was 2.0 MB), day 1 175 KB. Schema 1 and 2 files still load (tests). Small saves stay plain JSON.
- **Memory**: unchanged in the world (1.45-1.58 GB headless, dominated by nodes and resources, not scripts); scripted data is a few MB. Findings for you:
  idle pooled creature bodies never shrink (113 critters with skeletons at the end of the route; `NodePool.trim_all` is only called after teleports),
  and the headless dummy renderer keeps CPU copies of textures, so `MEMORY_STATIC` there is not the phone's number.
- **Tools** you can run on the PC: `kingdom/tools_qa/cpu_mem/cpu_profile.gd` (per-script ms per frame, route in Ashford, Thornfield and the wilds),
  `sim_save_probe.gd` (per-hour handlers, hub jobs, save sizes and times by game day), `mem_census.gd`, `ab_overlay.sh <git-ref> <dir>` (before / after without a second checkout).
  Gotchas found: a headless window sleeps 6.9 ms per frame unless `OS.low_processor_usage_mode_sleep_usec = 0`, and `Performance.TIME_PROCESS` /
  `TIME_PHYSICS_PROCESS` are the max of the last second, not a mean.
- **Still the biggest CPU left** (not touched, gameplay-visible): the 30 Hz physics tick (villager, critter, soldier, player scripts: 3.5 ms per tick, the p95 / p99
  frames) and `PopulationLOD` spawns (3.7-6 ms each). On the S22 these need a visual check of any rate change.
