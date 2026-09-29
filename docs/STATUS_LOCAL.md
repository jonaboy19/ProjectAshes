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

## Meshy free fixes (partial, stopped at usage limit)
- Done: optimize_free.py gained island_pct arg (arg 11) + env EMIT_ADD=1 / BAKE_EXT. Re-baked lamp_post_purple_bracket (solid, across 300, 1024px, EMIT_ADD), torch_dungeon_cage (island 14), house_two_story_shingle (solid, across 200), bouquet_wild (solid, across 260, smooth, 3500 tris, island 3), hay_bale_yellow_large (vox across 120, smooth, 3000 tris). Before/after in docs/art/meshy_free/fixes/.
- Remaining: bouquet_bright, bush_raspberry (blobby vox across 90-130 candidates rendered, unreviewed), ruined-hut floating debris (use island_pct), farm animal rigs (task 2) not started.
