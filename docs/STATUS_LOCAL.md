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

## In progress
- **Meshy free pack round 2** (161 models) → `assets/incoming/meshy_free/`
- **Clear water shader** (lakes and rivers, quality tiers) → `shaders/water/`
- **Mocap library** (martial arts, casting, locomotion from CMU, UAL and 100STYLE) → `assets/incoming/animations_free/`
- **Elemental VFX** (8 elements × charge/projectile/impact/AOE/status, plus slashes) → `scenes/vfx/elements/`, `scripts/vfx/element_fx.gd`
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

## Clear water (kingdom/shaders/water/clear_water.gdshader) - live in game via WaterStreamer
Done: caustics, sun glints, clearer turquoise shallows, quality tiers (Quality LOW=fake transparency, MEDIUM=refraction, HIGH/ULTRA=+caustics). Before/after: docs/art/water/{before,after}. Shots: tools/qa/water_shots/run.sh.
Remaining: HIGH/LOW fps before/after not measured (ULTRA new: lake 40, river 33, pier 27 fps on desktop; old HIGH pier 28.5); no frame-sheet animation check; no Android test; waterfall/pond presets; ULTRA river caustics slightly bright (tune caustic_strength); old shaders/water.gdshader can be deleted.

## Boot flow / studio intro (2026-09-29, stopped at usage limit)
Done and committed: `assets/video/studio_intro.ogv` (from download.mp4, 1280x720 q7 5.4 MB; it fades out, the other clip holds), engine boot splash (`boot_splash.png`, project.godot), `scripts/boot/studio_intro.gd` (contain-fit, skip after 1 s, still fallback), `scripts/boot/first_run.gd`, `scripts/core/app_services.gd`, `scripts/ui/world_loading.gd`, `scripts/core/platform_services.gd` + `docs/platform/ACCOUNTS_AND_SERVICES.md`, `locale/strings.csv` (en/nl).
NOT wired (unverified): everything in `docs/platform/boot_wiring_wip.patch` (apply with `git apply`): studio intro + first run in frontend/boot.gd, WorldLoading veil + pause button/Esc/back + camera sens/stick size/vibration in hud.gd, load progress in main.gd, render scale in quality.gd, settings rows, pause glyph. Also register autoloads `App` (after Quality) and `PlatformServices`. A headless run showed "Parameter t is null / convert on null" errors (source not yet traced). Still to do: run windowed, capture boot_flow screenshots + frame sheets (docs/ui/boot_flow/), 2400x1080 and 4:3 checks, handoff note.
