# Local PC session status (live)

The local session updates this file whenever a task starts or finishes. **Cloud session: read it after each pull.**
Who owns which area: `docs/LOCAL_SESSION_HANDOFF.md`.

_Last update: 2026-09-29 (feel pass: animation and movement audit + fixes)_

## Done (recent)
| Date | What | Where | Commit |
|---|---|---|---|
| 09-29 | **Feel pass (animation director)**: in-game Movie Maker audit of 18 situations (`tools_qa/feel_capture`), ranked issues in `docs/anim/FEEL_AUDIT.md`. Fixed: run stop (0.23 s dead stop -> 0.40 s with decelerating steps), walk-start foot slide, idle turn spin, combo hit and slash timing measured from the blade, lunge into enemies, enemy knockback teleport -> slide, villager idle desync. Codex patches P1-P6 in `docs/anim/patches/`. NPC foot IK was tried and reverted (-14 to -22 fps on HIGH). Before/after in `docs/anim/feel/` | `player.gd`, `wolf.gd`, `monster.gd`, `villager.gd`, `procedural_rig.gd` (surgical), `tools_qa/feel_capture/`, `tools/qa/feel_sheets.sh` | (this commit) |
| 09-28 | Boot crash fixed (threaded mesh loads → main-thread `Assets.scene`) | `scripts/world/region_dressing.gd`, `assets.gd` | 0137fa0d, 64b3698e |
| 09-28 | Godot 4.6.3 (quit crash fixed) | launchers, `tools/qa` | a5a596b7 |
| 09-29 | **L14 main quest + L16 tutorial director**: "The Stones Are Dimming" Acts I-V (30 steps, 5 dialogue files, 12-person cast), story lint with full autoplay (2592/2592 combinations), 12 contextual tutorial prompts with en/nl strings, sandbox sheet | `data/region1/quests/`, `data/region1/dialogue/`, `scripts/region1/`, `tools_qa/region1/`, `docs/regions/STORY_R1.md`, `CAST_R1.md` | e3071665 + follow-up |
| 09-29 | **Design: Retinue, Settlement and Ascension** (recruitment and the stone-borne Call with ETA, taming, Palworld-style building for thumbs, grudges and raids, conquest, the path to king via the Elder Stone Moot; 5 twists; balance targets and sims S1–S10; packages L21–L50, C14–C21, X8–X11 after the in-progress Region 1 packages) | `docs/design/RETINUE_SETTLEMENT_ASCENSION.md` | (this commit) |
| 09-29 | **L17 Region 1 audio**: 7 looping themes (village/farm, guild town, Highwatch Keep, Stagborn glade, rift wilds, night, Warden boss), rune hum, ward activate/break, glyph carve x3, Stagborn bellow/snort/Warden roar, Scar ambience, 20 barks (10 m / 10 f). Music -16.1..-16.2 LUFS-I, one-shots peak -3 dBFS, 8.3 MB, licences in LICENSES.md + CREDITS.md | `assets/audio/region1/`, `docs/regions/AUDIO_R1.md`, `tools/audio/r1_*.sh` | (this commit) |
| 09-29 | Meshy free pack round 1: 181 optimized models (CC0), not placed yet | `assets/incoming/meshy_free/` | a6c67244 |
| 09-29 | Free VFX and shader gallery (Kenney, RPicster, god rays) | `assets/incoming/vfx_free/`, `shaders/free/`, `tools_qa/vfx_gallery/` | 58f8e8c4 |
| 09-29 | Add-ons: Phantom Camera, impostors, footsteps, VoronoiShatter, SimpleGrass, DebugMenu, Sentry installer — see docs/addons/README.md | `addons/`, `tools/impostors/`, `tools_qa/addons_demo/`, `docs/addons/` | 9d2c8770 |
| 09-29 | Impostor edge pass: 3x supersampled + dilated atlases (2 MB ETC2 per species), alpha-to-coverage edge, shader crossfade demo (mesh_fade + impostor_octa), fps 117 / 235 / 211 (mesh / impostor / hybrid) | `tools/impostors/`, `assets/generated/impostors/`, `docs/addons/README.md` | 98d6b875 |
| 09-29 | Rigged farm animals (hen, rooster, 3 cows) with idle/walk/eat/flap clips, rig tools, frame sheets | `assets/incoming/meshy_free/farm/rigged/`, `tools/meshy/animal_rig/`, `docs/art/meshy_free/rigged/` | 72e1465a |
| 09-29 | Meshy fixes: bouquet_bright re-baked, ruined-hut floating debris removed (island removal); raspberry kept | `assets/incoming/meshy_free/`, `docs/art/meshy_free/fixes/` | a8558e41 |
| 09-29 | Elemental VFX set: soft fire shader, bolder lightning and dash, stop-motion sheets, perf and Compatibility checked | `scenes/vfx/elements/`, `scripts/vfx/element_fx.gd`, `docs/art/vfx_elements/` | 58abc054 + follow-up |

## Region 1 scaffold (L0), 2026-09-29: DONE
- `Region1Sim` (seeded, `tick(dt_days)`, events, `serialize`/`deserialize`/`migrate`, `digest`, `debug_image`), `Region1State` (static save registry, versioning + migration, unknown-module data kept), `Region1Root` (1 s timer, day slicing, presenter group), `Region1DemoSim`, `data/region1/{README.md,modules.json}`, headless sandbox `tools_qa/region1/region1_sandbox.tscn`, 19 gdUnit tests (`tests/test_region1_scaffold.gd`).
- Cloud: paste H1 + H2 from `docs/regions/HOOKS_FOR_CLOUD.md` (not applied; hot files untouched).
- Verified headless in a sparse worktree (no game assets): sandbox OK, 19/19 tests pass. NOT run inside the full game (hooks not wired yet).
- Backlog: windowed sandbox variant for GPU frame sheets (L8/L11); a Region1 debug overlay (module ms) once hooks land; presenter pooling helper.

## Region 1 N1 Wardwright: L7 Wardlines + L8 rune recognizer (2026-09-29): DONE
- **L7** `scripts/region1/wardlines.gd` (`Wardlines extends Region1Sim`), tuning `data/region1/wardlines.json`, 27 gdUnit tests (`tests/test_region1_wardlines.gd`). Rules: 5 Elder Stones hold a daily power budget; every stone needs power; power travels along links losing 4 percent a hop; nearest-first (pinned first); a stone follows its feed over days; wear + crews; carve ward/lure/alarm/bless; drag/cut/mend links (max 700 m, 4 per stone). API: `coverage_at`/`coverage_callable()` (hook H3), `carve`, `add_link`, `cut_link`, `mend_link`, `set_pinned`, `repair`, `pressure`, `notify_threat`, `bless_at`, `lure_points`, `road_coverage`, `rumours`, `flow_edges`, `elder_status`, `budget_report`, `bind_network(RARunestoneNetwork)`, snapshot/restore. Events (`road_rumour`, `road_clear`, `stone_dark`, `stone_lit`, `link_cut`, `glyph_carved`, `alarm`, `elder_strained` ...) carry a ready `rumour` string. Tick p95 1.4 ms (84 stones), coverage_at under 50 us (tested).
- **L8** `scripts/region1/rune_gesture.gd` (`RuneGesture`, multi-stroke Protractor, rotation/scale invariant, any stroke order/direction) + `data/region1/glyphs.json` (ward = diamond, lure = arrow, alarm = zigzag bolt, bless = cross) + 13 tests: 159/160 on 40 noisy strokes per glyph (six other seeds 98-100 percent), 85 percent at twice the noise, mean 0.25 ms per match (p95 0.5 ms). Learns a player style (`learn`), saves via `register_state()`, assist setting relaxes the threshold.
- Canvas `tools_qa/region1/rune_canvas.tscn` (glowing trail, carved rune flare, confidence card, practice mode with guide, `--demo`), story board `tools_qa/region1/wardlines_demo.gd`, sheets and PNGs in `tools_qa/region1/samples/`.
- Hooks for the cloud: H3 + C3 wiring in `docs/regions/HOOKS_FOR_CLOUD.md`. Wardlines is NOT in `modules.json` yet.
- Backlog (aaa-review): (1) haptic tick + rune-hum/carve SFX on each stroke and on commit (audio exists in `assets/audio/region1/`); (2) real-phone test of the canvas (touch smoothing, palm rejection, stroke width by screen dpi); (3) a stone-face 3D version: project the strokes onto the Elder Stone emissive mask (L1/L12); (4) ward-map layer using `flow_edges()` (thick = busy link) for L13; (5) more glyphs (harvest-blessing variants, ancestor-gold) need shapes that are not rotations of each other; a lone diamond drawn in two strokes is not yet a template; (6) tick cost: crews scan all stones daily, fine at 84 but bucket by road for 400+ stones; (7) IM Fell body font renders as blocks in this sparse sandbox, the canvas uses Cinzel light.

## Region 1 story + onboarding: L14 main quest + L16 tutorial director (2026-09-29): DONE
- **L14 "The Stones Are Dimming"** (Acts I-V): `data/region1/quests/r1_main.json` (30 steps; schema in `data/region1/quests/README.md`), `r1_registry.json`, `cast.json`, dialogue `data/region1/dialogue/r1_act1..5.json` (134 nodes, 158 lines, `dialogue_runner` format plus `speaker`). Runtime `scripts/region1/story_quest.gd` (`Region1StoryQuest`, saves via Region1State). Docs: `docs/regions/STORY_R1.md` (synopsis per act, branches, C9 cutscene beats), `docs/regions/CAST_R1.md` (12 bios).
- **Lint** `tools_qa/region1/lint_quests.gd`: schema, lengths (lines 120, choices 40, HUD pin 48), speakers, places, stones, glyphs, targets, items, cutscenes, tutorial ids, actions, conditions, tokens, flags (read vs set), step DAG, mechanic coverage and dialogue reachability. It then autoplays the whole quest with the real runtime and dialogue runner: 56 sampled combinations in about 10 s (0 errors, 0 warnings, 158/158 lines shown); `--exhaustive` covers all 2592 combinations, 0 failures, 8.7 min.
- **L16** `scripts/region1/tutorial_director.gd` (12 contextual prompts: move, look, talk, interact, eat, sleep, fight, block, dodge, carve, map, ashsight). Each is dismissed only by the real action, with priority and pre-emption, skip, hide all and replay, and saves as `tutorial`. Also `tutorial_prompt_view.gd` (touch-first gesture art, dark-gold pill, 48 px skip) and `tutorial_game_bridge.gd` (C8 hook: 3 lines in main.gd, see HOOKS_FOR_CLOUD.md). Locale: 29 `TUT_*` rows en/nl, translations regenerated. Sandbox `tools_qa/region1/tutorial_sandbox.tscn` autoplay: 12/12 prompts shown in context and dismissed by their action (en + nl), sheet `docs/regions/tutorial_demo_sheet.jpg`.
- Tests: `tests/test_region1_story.gd` (8) and `tests/test_region1_tutorial.gd` (17), all green together with the scaffold suite (44/44). Verified in the sparse project (no game assets); **not run inside the full game**: the hooks C7/C8 are not wired yet.
- Cloud: C7 event mapping, and C8 hook plus providers, in `docs/regions/HOOKS_FOR_CLOUD.md`; C9 beats in STORY_R1.md; C0/C1 places listed in `r1_registry.json` (status c0/c1, proposed positions).
- Backlog (aaa-review): voice-over script pass; a portrait per speaker; final gesture art for the trace/hold prompts (placeholder vector art now); the `sleep` prompt needs a bed Station in reach; wind-up detection for humanoids needs `is_winding_up()` (X4).

## In progress
- **Meshy free pack round 2** (161 models) → `assets/incoming/meshy_free/`
- **Clear water shader** (lakes and rivers, quality tiers) → `shaders/water/`
- **Mocap library** (martial arts, casting, locomotion from CMU, UAL and 100STYLE) → `assets/incoming/animations_free/`
- **Boot flow** (studio intro video, title menu, pause menu, settings, platform-services stub). This **changes `run/main_scene` to a boot scene**; QA runs use `--skip-intro`.
- **Advanced animation tech** (IK, spring bones, ragdoll, more mocap, video-to-mocap) → `assets/incoming/animations_free2/`, `tools_qa/anim_tech/`
- **Godot add-on audit** (camera, impostors, debug menu, crash reporting, audio …) → `addons/`, `tools_qa/addons_demo/`

## Waiting on the cloud or Codex
- Place the Meshy free-pack models in levels (see `docs/art/meshy_free/README.md`).
- Wire the elemental VFX and clips into combat (Codex).

## Tools
- `tools/qa/video_to_sheets.sh` + skill `ashes-video-review`: stop-motion contact sheets for judging any motion (example in `docs/qa/video_review_example/`).

## Backlog (from the aaa-review loop)
- Warm up the blue lower canopy on the fluffy-tree shader.
- Fix the 4 HUD icons that still have faint smudges.
- (aaa-review, assets session) Rig the horse, wolves, fox and dragons with `animal_rig`; the cow grazing pose needs a longer neck or a kneel (muzzle stops about 20 cm above the ground); chicken wings are flat plates that swing out, an extra wing-tip bone or a re-modelled wing would sell the flap.
- (aaa-review) Impostors: wrap the real game materials in the crossfade shader (`mesh_fade.gdshader` only carries albedo/colour/roughness), tune impostor tint/up_lighting to the lit mesh (impostors are lighter than shadowed meshes), test alpha-to-coverage on a phone and provide a no-MSAA path, bake impostors for the KayKit and Meshy buildings, measure the LOW tier switch distance.
- (aaa-review) bush_raspberry still shard-like: Meshy remesh (5 cr) or hand-made bush in Blender.
- (aaa-review) Godot `--import` of the whole project takes 30 min on a cold cache and about 7 GB of disk; agents should share one `.godot` cache instead of one per worktree.

## Meshy free fixes (done 2026-09-29)
Earlier: `optimize_free.py` island arg (11) + `EMIT_ADD` / `BAKE_EXT`; re-baked lamp_post_purple_bracket, torch_dungeon_cage, house_two_story_shingle, bouquet_wild, hay_bale_yellow_large.
Now: bouquet_bright (solid, clearly better), hut_mossy_ruined_a/b LOD0+LOD1 (island removal 4 percent, floating debris gone, ground fringe remains). bush_raspberry: 4 variants tried, none clearly better, existing file kept; it still reads as shard cards and needs a Meshy remesh. Before/after in `docs/art/meshy_free/fixes/`.
Farm animal rigs: `farm/rigged/` (hen, rooster, cow_spotted, cow_brown_a/b), details and limits in `docs/art/meshy_free/README.md`. Not rigged: horse, wolves, fox, dragons (same `tools/meshy/animal_rig/rig_lib.py`, needs a quadruped template like `rig_cow.py`). Codex: play `idle`/`walk`/`eat`/`flap` (loop linear), move at the speed in the `.json` next to each GLB.
## Advanced animation (local, stopped at usage limit)
Done: KayKit + authored traversal clips (`animations_free2/`), README `docs/anim/advanced/README.md`.
Remaining: anim_tech demo (blend trees, root-motion attacks, motion warping, perf table) and video-to-BVH pipeline are with sub-agents and may be partial; finish from `docs/anim/advanced/tech/` and `docs/anim/advanced/video_mocap/`. Add `animations_free2` GLBs to `Assets.UAL_FILES` (Codex).
## Clear water (kingdom/shaders/water/clear_water.gdshader) - live in game via WaterStreamer
Done: caustics, sun glints, clearer turquoise shallows, quality tiers (Quality LOW=fake transparency, MEDIUM=refraction, HIGH/ULTRA=+caustics). Before/after: docs/art/water/{before,after}. Shots: tools/qa/water_shots/run.sh.
Remaining: HIGH/LOW fps before/after not measured (ULTRA new: lake 40, river 33, pier 27 fps on desktop; old HIGH pier 28.5); no frame-sheet animation check; no Android test; waterfall/pond presets; ULTRA river caustics slightly bright (tune caustic_strength); old shaders/water.gdshader can be deleted.

## Boot flow / studio intro (2026-09-29, stopped at usage limit)
Done and committed: `assets/video/studio_intro.ogv` (from download.mp4, 1280x720 q7 5.4 MB; it fades out, the other clip holds), engine boot splash (`boot_splash.png`, project.godot), `scripts/boot/studio_intro.gd` (contain-fit, skip after 1 s, still fallback), `scripts/boot/first_run.gd`, `scripts/core/app_services.gd`, `scripts/ui/world_loading.gd`, `scripts/core/platform_services.gd` + `docs/platform/ACCOUNTS_AND_SERVICES.md`, `locale/strings.csv` (en/nl).
NOT wired (unverified): everything in `docs/platform/boot_wiring_wip.patch` (apply with `git apply`): studio intro + first run in frontend/boot.gd, WorldLoading veil + pause button/Esc/back + camera sens/stick size/vibration in hud.gd, load progress in main.gd, render scale in quality.gd, settings rows, pause glyph. Also register autoloads `App` (after Quality) and `PlatformServices`. A headless run showed "Parameter t is null / convert on null" errors (source not yet traced). Still to do: run windowed, capture boot_flow screenshots + frame sheets (docs/ui/boot_flow/), 2400x1080 and 4:3 checks, handoff note.

## Animation round 3 (2026-09-29, local): DONE
- Tech demo (`tools_qa/anim_tech`, `docs/anim/advanced/tech/README.md`): partial ragdoll fixed, full-ragdoll jitter re-measured (1 mm/frame), foot IK 0 % toe penetration on stairs+ramp (was mis-measured before: IK output is only visible in `skeleton_updated`), new: additive flinch, lean + aim twist, synced loco tree, root-motion attacks, motion warp (0-6 cm landing error), hitstop + shake, perf bench. Tier table: LOW 41 / MEDIUM 5 / HIGH 4 characters per frame budget.
- Clip review (`docs/anim/free_library/review_results.md`): punch heavies are hooks (renamed `MA_Punch_Hook_*`), 8 clips rejected, trims/loop fixes, ladder/wall rebuilt, `Kay_Work_*_Loop` renamed `*_Repeat_Loop`.
- Video mocap: `video_to_clip.ps1` one command, IK foot pinning (slide 32 -> 0.5 cm/s); tested on synthetic video only.
- Handoff for Codex: `docs/anim/free_library/HANDOFF_CODEX.md` (clip -> state, blend, root motion, event frames, `UAL_FILES` lines) and the HANDOFF table in the tech README.

## Backlog (animation, from the aaa-review loop)
- (feel pass) Source and retarget run-stop, walk-start and 180° pivot clips (100STYLE/CMU) for P5; none exist in any loaded library.
- (feel pass) NearRigPool: pooled foot IK for the N nearest NPCs, accepted only if the village HIGH bench is within 1 ms (P6).
- (feel pass) Wolf `wolf2` model reads as a small dog and hides in the grass; scale it about 1.3x and re-check (F14).
- (feel pass) Camera blockers for wells, canopies and overhangs; eased pull-in; a talk-shot camera (P4, F13).
- (feel pass) The QA boot flow fails with "world veil never appeared" on this branch, with and without the feel changes. Investigate the loading or veil hand-off.
- (feel pass) Re-capture wolves and swimming with dedicated framing (the chase is too far, and the wading test did not reach swim depth).
- Film a real phone clip and run `video_to_clip.ps1` (only synthetic tested); then replace the authored ladder/wall/vault with mocap.
- Codex: fold the flinch OneShot->Add2 and the foot-IK toe probe / instant-rise into `CharacterAnimator` / `procedural_rig.gd`; add `animations_free*` to `Assets.UAL_FILES` (see HANDOFF_CODEX.md; the new folders need root motion disabled in `_ual_for`).
- Attack clips have no weapon models in the reviews; check sword/staff clips with a prop attached.
- Casting is thin (lightning-from-sky, beam loops, teleport dash missing); Kay dodges are 0.4 s bursts without recovery; no true uppercut exists.
- Performance: at most ~4 HIGH-tier characters per frame budget (AnimationTree costs 2x a clip); rank trees/modifiers by camera distance like `rig_budget`.
- Full-project headless `--import` of the new GLBs still not run (disk); a mini-project import of all 15 GLBs was clean.

## Backlog (Region 1 audio, from the aaa-review loop)
- Cloud C12: wire `docs/regions/AUDIO_R1.md` (area map, hum, ward/glyph/Stagborn events, barks); audition every theme in its area, since mood was picked without listening in-engine.
- One theme per area is repetitive: add a second village/day track (Suonatore or Nakarada Medieval Loop One) and a keep interior variant; a dedicated Scarbound Troll finale theme.
- No female greeting/yes/no/victory barks in any CC0 pack found; source or record them. Male barks are partly spoken (greet, yes, no, victory).
- Ward, glyph and rune hum are synthesised; if they sound thin next to the recorded SFX, layer in a CC0 chime or stone-scrape recording.
- Rift bed and hum were checked by numbers only (loudness, seam), not by ear; `mus_r1_night` peaks at -0.8 dBFS (trim 1 dB if it clips on device).
- Godot import of `assets/audio/region1/` not run (disk); run once and commit the `.import` files if the project tracks them.

## Open issues from the boot-flow run (2026-09-29)
- Unexplained rendering errors during world load under `--rendering-method mobile` at 1280x720 ("Parameter framebuffer is null", "Index p_mipmap out of bounds", "Uniforms were never supplied for set (0)"), hundreds per run. They do not fail the flow; cause not investigated.
- 76 leaked `JoltShape3D` RID allocations reported at exit.

## VFX tools and flipbooks (2026-09-29)
Done: Material Maker 1.7, Effekseer editor 1.80.7 and EffekseerForGodot4 1.80.5.1 installed in C:\Users\Jonna\Tools; 6 baked flipbooks (fire, smoke, dust, water splash, lightning, magic swirl) in `kingdom/assets/vfx/flipbooks/` with `FlipbookFX` + shader `shaders/vfx_flipbook/`; gallery `tools_qa/vfx_flipbooks/`; findings, Effekseer verdict, perf and per-element upgrade plan in `docs/art/vfx_tools/README.md`; scripts and install notes in `tools/vfx/`.
Effekseer: works on 4.6.3 desktop (Mobile renderer), draws nothing on gl_compatibility, about 0.3 ms CPU per aura on desktop (3-4 ms on a phone), addon vendored (Windows + Android only), plugin NOT enabled, not wired.
Remaining: not wired into ElementFX; fire sheet is v1 (flat disc start); no ground-plane shader mode; no phone test; Material Maker headless export does not work in 1.7; `.import` check was run on the shared kingdom/.godot only (imports fine, unrelated UID errors are pre-existing).
# Local PC session status (live)

The local session updates this file whenever a task starts or finishes. **Cloud session: read it after each pull.**
Who owns which area: `docs/LOCAL_SESSION_HANDOFF.md`.

_Last update: 2026-09-29 (feel pass: animation and movement audit + fixes)_
_Last update: 2026-09-29 (feel pass: animation and movement audit + fixes)_
_Last update: 2026-09-29 (feel pass: animation and movement audit + fixes)_

## Done (recent)
| Date | What | Where | Commit |
|---|---|---|---|
| 09-28 | Boot crash fixed (threaded mesh loads → main-thread `Assets.scene`) | `scripts/world/region_dressing.gd`, `assets.gd` | 0137fa0d, 64b3698e |
| 09-28 | Godot 4.6.3 (quit crash fixed) | launchers, `tools/qa` | a5a596b7 |
| 09-29 | **Region 1 L1**: Elder Stone (4.2k tris, emissive glyph mask, ancestor-gold variant) + 4 road stones, glow test at 60 m | `assets/incoming/region1/stones/`, `docs/art/region1/stones_*` | see git log |
| 09-29 | **Region 1 L2**: Highwatch Keep kit (32 instances = 32 draw calls, 1 atlas, site JSON, 3/4 + top previews) | `assets/incoming/region1/highwatch/`, `docs/art/region1/highwatch_*` | see git log |
| 09-29 | Meshy free pack round 1: 181 optimized models (CC0), not placed yet | `assets/incoming/meshy_free/` | a6c67244 |
| 09-29 | Free VFX and shader gallery (Kenney, RPicster, god rays) | `assets/incoming/vfx_free/`, `shaders/free/`, `tools_qa/vfx_gallery/` | 58f8e8c4 |
| 09-29 | Elemental VFX set: soft fire shader, bolder lightning and dash, stop-motion sheets, perf and Compatibility checked | `scenes/vfx/elements/`, `scripts/vfx/element_fx.gd`, `docs/art/vfx_elements/` | 58abc054 + follow-up |

| 09-29 | **L17 Region 1 audio**: 7 looping themes (village/farm, guild town, Highwatch Keep, Stagborn glade, rift wilds, night, Warden boss), rune hum, ward activate/break, glyph carve x3, Stagborn bellow/snort/Warden roar, Scar ambience, 20 barks (10 m / 10 f). Music -16.1..-16.2 LUFS-I, one-shots peak -3 dBFS, 8.3 MB, licences in LICENSES.md + CREDITS.md | `assets/audio/region1/`, `docs/regions/AUDIO_R1.md`, `tools/audio/r1_*.sh` | (this commit) |
| 09-29 | Meshy free pack round 1: 181 optimized models (CC0), not placed yet | `assets/incoming/meshy_free/` | a6c67244 |
| 09-29 | Free VFX and shader gallery (Kenney, RPicster, god rays) | `assets/incoming/vfx_free/`, `shaders/free/`, `tools_qa/vfx_gallery/` | 58f8e8c4 |
| 09-29 | Add-ons: Phantom Camera, impostors, footsteps, VoronoiShatter, SimpleGrass, DebugMenu, Sentry installer — see docs/addons/README.md | `addons/`, `tools/impostors/`, `tools_qa/addons_demo/`, `docs/addons/` | 9d2c8770 |
| 09-29 | Impostor edge pass: 3x supersampled + dilated atlases (2 MB ETC2 per species), alpha-to-coverage edge, shader crossfade demo (mesh_fade + impostor_octa), fps 117 / 235 / 211 (mesh / impostor / hybrid) | `tools/impostors/`, `assets/generated/impostors/`, `docs/addons/README.md` | 98d6b875 |
| 09-29 | Rigged farm animals (hen, rooster, 3 cows) with idle/walk/eat/flap clips, rig tools, frame sheets | `assets/incoming/meshy_free/farm/rigged/`, `tools/meshy/animal_rig/`, `docs/art/meshy_free/rigged/` | 72e1465a |
| 09-29 | Meshy fixes: bouquet_bright re-baked, ruined-hut floating debris removed (island removal); raspberry kept | `assets/incoming/meshy_free/`, `docs/art/meshy_free/fixes/` | a8558e41 |
| 09-29 | Elemental VFX set: soft fire shader, bolder lightning and dash, stop-motion sheets, perf and Compatibility checked | `scenes/vfx/elements/`, `scripts/vfx/element_fx.gd`, `docs/art/vfx_elements/` | 58abc054 + follow-up |

## Region 1 scaffold (L0), 2026-09-29: DONE
- `Region1Sim` (seeded, `tick(dt_days)`, events, `serialize`/`deserialize`/`migrate`, `digest`, `debug_image`), `Region1State` (static save registry, versioning + migration, unknown-module data kept), `Region1Root` (1 s timer, day slicing, presenter group), `Region1DemoSim`, `data/region1/{README.md,modules.json}`, headless sandbox `tools_qa/region1/region1_sandbox.tscn`, 19 gdUnit tests (`tests/test_region1_scaffold.gd`).
- Cloud: paste H1 + H2 from `docs/regions/HOOKS_FOR_CLOUD.md` (not applied; hot files untouched).
- Verified headless in a sparse worktree (no game assets): sandbox OK, 19/19 tests pass. NOT run inside the full game (hooks not wired yet).
- Backlog: windowed sandbox variant for GPU frame sheets (L8/L11); a Region1 debug overlay (module ms) once hooks land; presenter pooling helper.

## In progress
- **Meshy free pack round 2** (161 models) → `assets/incoming/meshy_free/`
- **Clear water shader** (lakes and rivers, quality tiers) → `shaders/water/`
- **Mocap library** (martial arts, casting, locomotion from CMU, UAL and 100STYLE) → `assets/incoming/animations_free/`
- **Boot flow** (studio intro video, title menu, pause menu, settings, platform-services stub). This **changes `run/main_scene` to a boot scene**; QA runs use `--skip-intro`.
- **Advanced animation tech** (IK, spring bones, ragdoll, more mocap, video-to-mocap) → `assets/incoming/animations_free2/`, `tools_qa/anim_tech/`
- **Godot add-on audit** (camera, impostors, debug menu, crash reporting, audio …) → `addons/`, `tools_qa/addons_demo/`

## Waiting on the cloud or Codex
- Place the Meshy free-pack models in levels (see `docs/art/meshy_free/README.md`).
- Wire the elemental VFX and clips into combat (Codex).

## Tools
- `tools/qa/video_to_sheets.sh` + skill `ashes-video-review`: stop-motion contact sheets for judging any motion (example in `docs/qa/video_review_example/`).

## Backlog (from the aaa-review loop)
- Warm up the blue lower canopy on the fluffy-tree shader.
- Fix the 4 HUD icons that still have faint smudges.

## Meshy free fixes (partial, stopped at usage limit)
- Done: optimize_free.py gained island_pct arg (arg 11) + env EMIT_ADD=1 / BAKE_EXT. Re-baked lamp_post_purple_bracket (solid, across 300, 1024px, EMIT_ADD), torch_dungeon_cage (island 14), house_two_story_shingle (solid, across 200), bouquet_wild (solid, across 260, smooth, 3500 tris, island 3), hay_bale_yellow_large (vox across 120, smooth, 3000 tris). Before/after in docs/art/meshy_free/fixes/.
- Remaining: bouquet_bright, bush_raspberry (blobby vox across 90-130 candidates rendered, unreviewed), ruined-hut floating debris (use island_pct), farm animal rigs (task 2) not started.
- (aaa-review, assets session) Rig the horse, wolves, fox and dragons with `animal_rig`; the cow grazing pose needs a longer neck or a kneel (muzzle stops about 20 cm above the ground); chicken wings are flat plates that swing out, an extra wing-tip bone or a re-modelled wing would sell the flap.
- (aaa-review) Impostors: wrap the real game materials in the crossfade shader (`mesh_fade.gdshader` only carries albedo/colour/roughness), tune impostor tint/up_lighting to the lit mesh (impostors are lighter than shadowed meshes), test alpha-to-coverage on a phone and provide a no-MSAA path, bake impostors for the KayKit and Meshy buildings, measure the LOW tier switch distance.
- (aaa-review) bush_raspberry still shard-like: Meshy remesh (5 cr) or hand-made bush in Blender.
- (aaa-review) Godot `--import` of the whole project takes 30 min on a cold cache and about 7 GB of disk; agents should share one `.godot` cache instead of one per worktree.

## Meshy free fixes (done 2026-09-29)
Earlier: `optimize_free.py` island arg (11) + `EMIT_ADD` / `BAKE_EXT`; re-baked lamp_post_purple_bracket, torch_dungeon_cage, house_two_story_shingle, bouquet_wild, hay_bale_yellow_large.
Now: bouquet_bright (solid, clearly better), hut_mossy_ruined_a/b LOD0+LOD1 (island removal 4 percent, floating debris gone, ground fringe remains). bush_raspberry: 4 variants tried, none clearly better, existing file kept; it still reads as shard cards and needs a Meshy remesh. Before/after in `docs/art/meshy_free/fixes/`.
Farm animal rigs: `farm/rigged/` (hen, rooster, cow_spotted, cow_brown_a/b), details and limits in `docs/art/meshy_free/README.md`. Not rigged: horse, wolves, fox, dragons (same `tools/meshy/animal_rig/rig_lib.py`, needs a quadruped template like `rig_cow.py`). Codex: play `idle`/`walk`/`eat`/`flap` (loop linear), move at the speed in the `.json` next to each GLB.
## Advanced animation (local, stopped at usage limit)
Done: KayKit + authored traversal clips (`animations_free2/`), README `docs/anim/advanced/README.md`.
Remaining: anim_tech demo (blend trees, root-motion attacks, motion warping, perf table) and video-to-BVH pipeline are with sub-agents and may be partial; finish from `docs/anim/advanced/tech/` and `docs/anim/advanced/video_mocap/`. Add `animations_free2` GLBs to `Assets.UAL_FILES` (Codex).
## Clear water (kingdom/shaders/water/clear_water.gdshader) - live in game via WaterStreamer
Done: caustics, sun glints, clearer turquoise shallows, quality tiers (Quality LOW=fake transparency, MEDIUM=refraction, HIGH/ULTRA=+caustics). Before/after: docs/art/water/{before,after}. Shots: tools/qa/water_shots/run.sh.
Remaining: HIGH/LOW fps before/after not measured (ULTRA new: lake 40, river 33, pier 27 fps on desktop; old HIGH pier 28.5); no frame-sheet animation check; no Android test; waterfall/pond presets; ULTRA river caustics slightly bright (tune caustic_strength); old shaders/water.gdshader can be deleted.

## Boot flow / studio intro (2026-09-29, stopped at usage limit)
Done and committed: `assets/video/studio_intro.ogv` (from download.mp4, 1280x720 q7 5.4 MB; it fades out, the other clip holds), engine boot splash (`boot_splash.png`, project.godot), `scripts/boot/studio_intro.gd` (contain-fit, skip after 1 s, still fallback), `scripts/boot/first_run.gd`, `scripts/core/app_services.gd`, `scripts/ui/world_loading.gd`, `scripts/core/platform_services.gd` + `docs/platform/ACCOUNTS_AND_SERVICES.md`, `locale/strings.csv` (en/nl).
NOT wired (unverified): everything in `docs/platform/boot_wiring_wip.patch` (apply with `git apply`): studio intro + first run in frontend/boot.gd, WorldLoading veil + pause button/Esc/back + camera sens/stick size/vibration in hud.gd, load progress in main.gd, render scale in quality.gd, settings rows, pause glyph. Also register autoloads `App` (after Quality) and `PlatformServices`. A headless run showed "Parameter t is null / convert on null" errors (source not yet traced). Still to do: run windowed, capture boot_flow screenshots + frame sheets (docs/ui/boot_flow/), 2400x1080 and 4:3 checks, handoff note.

## Animation round 3 (2026-09-29, local): DONE
- Tech demo (`tools_qa/anim_tech`, `docs/anim/advanced/tech/README.md`): partial ragdoll fixed, full-ragdoll jitter re-measured (1 mm/frame), foot IK 0 % toe penetration on stairs+ramp (was mis-measured before: IK output is only visible in `skeleton_updated`), new: additive flinch, lean + aim twist, synced loco tree, root-motion attacks, motion warp (0-6 cm landing error), hitstop + shake, perf bench. Tier table: LOW 41 / MEDIUM 5 / HIGH 4 characters per frame budget.
- Clip review (`docs/anim/free_library/review_results.md`): punch heavies are hooks (renamed `MA_Punch_Hook_*`), 8 clips rejected, trims/loop fixes, ladder/wall rebuilt, `Kay_Work_*_Loop` renamed `*_Repeat_Loop`.
- Video mocap: `video_to_clip.ps1` one command, IK foot pinning (slide 32 -> 0.5 cm/s); tested on synthetic video only.
- Handoff for Codex: `docs/anim/free_library/HANDOFF_CODEX.md` (clip -> state, blend, root motion, event frames, `UAL_FILES` lines) and the HANDOFF table in the tech README.

## Backlog (animation, from the aaa-review loop)
- Film a real phone clip and run `video_to_clip.ps1` (only synthetic tested); then replace the authored ladder/wall/vault with mocap.
- Codex: fold the flinch OneShot->Add2 and the foot-IK toe probe / instant-rise into `CharacterAnimator` / `procedural_rig.gd`; add `animations_free*` to `Assets.UAL_FILES` (see HANDOFF_CODEX.md; the new folders need root motion disabled in `_ual_for`).
- Attack clips have no weapon models in the reviews; check sword/staff clips with a prop attached.
- Casting is thin (lightning-from-sky, beam loops, teleport dash missing); Kay dodges are 0.4 s bursts without recovery; no true uppercut exists.
- Performance: at most ~4 HIGH-tier characters per frame budget (AnimationTree costs 2x a clip); rank trees/modifiers by camera distance like `rig_budget`.
- Full-project headless `--import` of the new GLBs still not run (disk); a mini-project import of all 15 GLBs was clean.
## Region 1 art L1 + L2 (2026-09-29, local): DONE, not yet imported in Godot
Files and specs: `assets/incoming/region1/stones/README.md` (emissive spec: drive `emission_energy_multiplier` 0.3 dim to 4 bright, `COLOR_0.R` sweep) and `assets/incoming/region1/highwatch/README.md` (+ `highwatch_site.json`, assign `highwatch_kit.tres`).
Cloud (C1): place the site from the JSON, 5 Elder Stones (rotate the one hero, use the gold variant for ancestor stones), road stones beside roads. Needs one Godot open to generate `.import` files (no import was run: disk was tight).
AAA-review backlog from this task:
- Import + in-game check of both sets (fps, LOD fade, glow with the real bloom, Compatibility renderer).
- Elder Stone: 2-3 more silhouettes so the five hubs are not clones; moss/grass tuft cards at the dais rim; a rune-hum audio hook and the L12 flare VFX; wave shader using `COLOR_0.R`.
- Keep: 10 px/m texel density and no interior; add colliders, wall-walk nav, a hall interior scene, blue roofs on keep turrets.
- Kit: 120k tris at LOD0 is heavy for LOW tier, start LOD1 at 30 m; consider a proper retopo of gate/towers to ~4k (Blender collapse decimation shreds these Meshy shells; use Meshy remesh 5 cr if wanted).
- Guards/knights: markers reference the rigged `armored/*.glb`; sparring and wall-sentry behaviours still to do (Codex X4).

## Backlog (Region 1 audio, from the aaa-review loop)
- Cloud C12: wire `docs/regions/AUDIO_R1.md` (area map, hum, ward/glyph/Stagborn events, barks); audition every theme in its area, since mood was picked without listening in-engine.
- One theme per area is repetitive: add a second village/day track (Suonatore or Nakarada Medieval Loop One) and a keep interior variant; a dedicated Scarbound Troll finale theme.
- No female greeting/yes/no/victory barks in any CC0 pack found; source or record them. Male barks are partly spoken (greet, yes, no, victory).
- Ward, glyph and rune hum are synthesised; if they sound thin next to the recorded SFX, layer in a CC0 chime or stone-scrape recording.
- Rift bed and hum were checked by numbers only (loudness, seam), not by ear; `mus_r1_night` peaks at -0.8 dBFS (trim 1 dB if it clips on device).
- Godot import of `assets/audio/region1/` not run (disk); run once and commit the `.import` files if the project tracks them.

## Open issues from the boot-flow run (2026-09-29)
- Unexplained rendering errors during world load under `--rendering-method mobile` at 1280x720 ("Parameter framebuffer is null", "Index p_mipmap out of bounds", "Uniforms were never supplied for set (0)"), hundreds per run. They do not fail the flow; cause not investigated.
- 76 leaked `JoltShape3D` RID allocations reported at exit.

## Crash investigation (2026-09-29, local) - see docs/qa/stability.md
- All 9 recent Godot exe crashes (`+0x539f5a9`, 28 Sep 17:49-19:16) are the threaded mesh-load race that `0137fa0d` fixed; no Godot crash event since. 58 boots on latest origin (direct, loading screen, real menu path, mobile renderer) crashed 0 times.
- Fixed: freed-instance errors in RegionDressing queue and audio_director debug loop; QA harnesses now survive the self-freeing world veil (`hud._veil()`).
- Not done: 20 min play soak, GDExtension-loaded boots. Open: mobile renderer + glow errors (`p_mipmap`), boot_flow.gd stale after character creation.
## L5 Stagborn models (2026-09-29, local): DONE (Blender-verified, not yet in Godot)
- `stagborn_elk` (3,668 / 2,000 tris) and `stagborn_warden` (5,728 / 4,600 tris) in `assets/incoming/ai3d/meshy/creatures/`, rigged (26 bones), clips idle, idle_alt, graze, walk, run, run_charge, attack (antler gore with a 0.9 s telegraph), attack_butt, hit, death; Warden also kick and roar (rear-up). LOD1 for both. Emissive rune mask (Warden: flank glyphs, leg bands, antler rings; elk: faint antler rings). Source: CC0 Quaternius UAA Stag, customised in Blender, no Meshy credits.
- README with the **Codex handoff for X3** (clip names, event frames, speeds, no root motion): `assets/incoming/ai3d/meshy/creatures/stagborn_README.md`. Turntables + one frame-sheet folder per clip: `docs/art/region1/stagborn/`. Scripts: `tools/creatures/stagborn/`. Licence in `kingdom/CREDITS.md`.
- Backlog (aaa-review): (1) import into Godot, add to `tools/qa/anim_qa/catalog.gd`, run anim QA and a windowed shot in the glade; (2) Warden antlers are 5 m tall in total and thin at the tips: consider a 0.8 scale and a fatter beam; (3) foot IK for walk (stance slide up to 20 %); (4) SpringBone on the mane cones and tail; (5) hide the antler tips dipping under the ground in `run_charge` with grass or a shorter head-down pitch; (6) rune pulse shader (emission_energy animate, phase 3 brighter) and a hit-flash; (7) a proper 3D-sculpted head and antler pass or a Meshy remesh once credits are available; (8) `kick` hit frame, `roar` and `attack` audio and VFX hooks.

## L5 Warden art pass 2: remaining (stopped at usage limit, 2026-09-29)
- New Warden (8,288 / 5,000 tris) is in; only the turntable was reviewed. Re-render and READ frame sheets for roar, attack, walk, run_charge, death (scripts `tools/creatures/stagborn/`, `render_clip.py` + `sheet.sh`); the sheets in `docs/art/region1/stagborn/` are from the previous mesh.
- Art: antler rune channels are too wide and bright on the front beam (narrow the `Chn` line smoothstep); ivy leaves are sparse; neck braid and knot lines could be finer; check the saddle and belly gradient against the storybook reference; elk untouched apart from clips.
- Walk foot slide was tuned only by the stance-speed metric (per-leg amplitude scale); confirm visually or use foot IK. Update the README speeds (Warden walk about 1.2 m/s, run about 5.6 m/s) from `stagborn_warden_metrics.json`.
- Godot import and anim QA still not run.
