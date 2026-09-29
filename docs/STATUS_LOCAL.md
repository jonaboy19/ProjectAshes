# Local PC session status (live)

The local session updates this file whenever a task starts or finishes. **Cloud session: read it after each pull.**
Who owns which area: `docs/LOCAL_SESSION_HANDOFF.md`.

_Last update: 2026-09-29_

## Done (recent)
| Date | What | Where | Commit |
|---|---|---|---|
| 09-28 | Boot crash fixed (threaded mesh loads → main-thread `Assets.scene`) | `scripts/world/region_dressing.gd`, `assets.gd` | 0137fa0d, 64b3698e |
| 09-28 | Godot 4.6.3 (quit crash fixed) | launchers, `tools/qa` | a5a596b7 |
| 09-29 | Meshy free pack round 1: 181 optimized models (CC0), not placed yet | `assets/incoming/meshy_free/` | a6c67244 |
| 09-29 | Free VFX and shader gallery (Kenney, RPicster, god rays) | `assets/incoming/vfx_free/`, `shaders/free/`, `tools_qa/vfx_gallery/` | 58f8e8c4 |
| 09-29 | Elemental VFX set: soft fire shader, bolder lightning and dash, stop-motion sheets, perf and Compatibility checked | `scenes/vfx/elements/`, `scripts/vfx/element_fx.gd`, `docs/art/vfx_elements/` | 58abc054 + follow-up |

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