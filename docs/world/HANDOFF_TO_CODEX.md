# Handoff to Codex — Valencious world + PC upgrade (2026-10-22)

The owner stopped the local Claude session to save tokens and asked Codex to continue. Everything Claude planned and built is on branch **`claude/world-t3d`** (pushed). Nothing in this handoff was GPU-verified unless marked so.

## Owner direction (in force)
- **The game is now a PC game** (2026-10-20). Higher graphics on PC (Forward+, owner GPU: RTX 4070 Laptop 8 GB). Phone builds should keep working but are no longer the target.
- **Core loop:** NPCs, recruiting, founding your own settlement → kingdom (the cloud session owns that loop; see `docs/design/RETINUE_SETTLEMENT_ASCENSION.md`).
- **World first:** build the whole Valencious world on **Terrain3D**. **No Blender yet**, no Meshy. Keep the Style G storybook look (`docs/art/reference/00_MAIN_kingsreach_gate_market.webp`; shadows cool blue-violet, never grey/black).
- Document everything. Owner wants to save tokens: prefer the Godot editor MCP (`C:\Users\Jonna\Tools\dcc-mcp`, see below) over booting the full game for screenshots.

## The plans (read these first)
All in `docs/world/plans/`:
- **`WORLD_BRIEF.md`** — the phased world plan W0–W5 (world bible → macro heightmap + Terrain3D → water/roads/pads → biome dressing → landmarks → QA/docs). Includes the geography, global rules, acceptance checks and risks. **This is the main task.**
- `PC1_BRIEF.md` — PC renderer upgrade (WP0–WP5: harness, PC quality tiers, textures, lighting/GI, density, input/HUD).
- `FACES_BRIEF.md`, `AUDIT2_BRIEF.md` — earlier, done (see status).
- `pc1_uncommitted/*.patch` — small uncommitted edits from the PC perf investigation (`--qset=key=val` override in `quality.gd`, extra AUDITPERF timings in `audit_views.gd`). Re-apply on top of `claude/pc1-tiers` work if useful.

## Status

### Done and on `claude/focused-curie-m09hbd` (main working branch)
- Animation takeover from Codex: P9 attack layering, P5 starts/stops/turns, P2b wolf set, creature tables, casting v2 (see `docs/STATUS_LOCAL.md`).
- Boot save-on-pause fix, town test fixes, shared ground-decal budget.
- Villager LifeAmbience + CrowdAnimLOD + VAT residents; T-pose fix (never freeze an unsampled villager).
- NPC/hero faces v1 (ink face card + shader brows, `docs/art/FACES.md`) — understated, 5–6/10.
- Presentation audit 2 (night grade, creator light), name-plate de-overlap, hotbar hide.
- **PC WP0+WP1**: `PC_TIERS` + `Quality.profile` ("pc"/"mobile") + capability keys, Windows export preset, FSR2/TAA AA modes (`kingdom/scripts/core/quality.gd`, `export_presets.cfg`, `project.godot`). **WP5**: mouse look + capture, gamepad sticks/buttons, PC HUD hint strip, touch controls hidden on PC (`autoload/game.gd`, `actors/player.gd`, `ui/hud.gd`, `docs/controls.md`).
- **World W0**: world bible `docs/world/VALENCIOUS_WORLD.md`, `valencious_places.json` (343 places from the live game dump; stale doc positions kept as `alt_pos`), `valencious_bible_map.png`, `kingdom/data/world/valencious_regions.json` (12 macro sub-regions), dump files.

### On `claude/world-t3d` only (WIP, this commit — not merged, not GPU-verified)
- **W1a generator** `kingdom/tools/world/gen_valencious.py` (deterministic, seed 1066; run with `py -E -B`, not `py -I` — numpy/Pillow/scipy are in the user site-packages). Outputs `kingdom/data/world/macro/`: `height_16.png` (4097², 16-bit, 3 m/px, h = −20 + v/65535·320), `biome_ids.png`, `splat_weights.png`, `preview.png`, `meta.json`; `raw_core.json` is an input (dump of the legacy core heights). `--verify` re-runs and checks byte-identical.
- **W1b adapter** `kingdom/scripts/world/world_macro.gd` (`WorldMacro`; flag `--world_macro=noise|valencious`, env `ASHES_WORLD_MACRO`, settings `[world] macro`; default `noise`). Hook in `world_gen.gd`: `setup()` loads the macro, **suspends it while settlements/camps/sites are placed** (so no id/position moves), then `_rebase_to_macro()` re-seats base heights, water, camp grounds, clearings. `_raw_height()` returns `hidden_valley.shape(x, z, WorldMacro.sample(x, z) + detail*0.6)` when active.
- **W1d textures**: 5 new Terrain3D ground slots (meadow, farmland, marsh, rift ash, snow) in `kingdom/assets/terrain3d/ground/`, wiring in `terrain3d_bridge.gd` + `tools_qa/terrain3d/pack_ground_textures.gd` (unverified).
- Tests `kingdom/tests/test_world_macro.gd` (written, **not run**), `test_terrain3d_bridge.gd` touched.
- QA helpers `kingdom/tools_qa/world/{world_views.json, fit_probe.gd, png16_probe.gd}`.

### Known problems in the current terrain (from reading `preview.png`)
1. Heartvale core: crumpled relief with a cliff crescent on the west side of the Ashford/Kingsreach hold zone. Planned fix: strict hold only 300 m (Ashford) / 350 m (Kingsreach), then blend to a σ≈60 m smoothed version out to 1600 m (`w = smoothstep(...)`), no clamp.
2. North: the main ridge reads as one snow blob around Grimfen Pass. Planned fix: a continuous WSW–ENE spine from ≈(−3500,−3800) through Grimfen Pass (559,−3597) to ≈(3200,−3300), crest 180–260 m, width ~1.2 km, spurs south toward Highwatch; snow only on the crest. Dunhallow plateau and Ironmarch mesas already read OK.
3. Ashen Scar gullies too maze-like across the whole badlands; Rift trench not checked up close.
4. Ashrun meander valley hard to see in the preview.

### Not started
- W1c (re-run `tools_qa/region1/bake_valley.gd` with the macro on), W1e (offline Terrain3D bake: measure disk + hitch), W2 water/roads/pads, W3 biome dressing (incl. porting `scar_mask`/weather/season/snow to a Terrain3D shader override), W4 landmarks, W5 QA/docs.
- **PC performance**: PC_HIGH measured 16–30 fps at 1440p, but the laptop was **on battery** — re-measure on AC before tuning. FSR2 logs `FFX_ERROR_INVALID_ARGUMENT (uavMip >= mip_slice_rids.size())` ×72 — investigate (or fall back to FSR1 + TAA). WP2 textures, WP3 lighting/GI, WP4 density not started.
- Test baseline for the world branch was never recorded. gdUnit needs `--ignoreHeadlessMode`.

## Owner questions still open (from the world bible)
1. Silverford: keep at Ironmarch (2092,−2007) as `WORLD_R1.md` says (recommended) or move near Ashford (−640,480) as the parchment proposed?
2. Repaint the parchment map for the full ±6144 m world after terrain lands (recommended)?
3. Regions 2–4 without terrain for now (recommended)?
4. Treat the live game positions as canon and correct the docs (recommended)?

## Tools on this PC
- Godot 4.6.3: `C:\Users\Jonna\Downloads\Godot_v4.6.3-stable_win64\Godot_v4.6.3-stable_win64_console.exe`.
- **Godot editor MCP (dcc-mcp)**: `C:\Users\Jonna\Tools\dcc-mcp` (venv `Scripts\dcc-mcp-godot.exe`, `dcc-mcp-godot-install.exe`, `dcc-mcp-server.exe`; adapter 0.9.0; `mcpcall.sh <url> <method> '<params>'` for raw JSON-RPC; previous run logs in `logs\` — editor plugin on TCP 6008, bootstrap file `kingdom/.godot/dcc_mcp_godot_bootstrap.json`). It was used on 2026-10-01 on a now-deleted worktree; setup was started again and stopped. Run it on a dedicated worktree, never on one another agent uses.
- Python 3.14 + numpy, Pillow, scipy, opencv; ffmpeg. No Gaea/World Machine/GDAL/Material Maker.
- Antigravity's 32 km world proposal and viewer are on branch `antigravity/aaa-mocap-animations` (`7bdbc352`, `fc8f73a7`) — inspiration only; the world stays 12 288 m.

## Rules that bit us
- Use `export MSYS_NO_PATHCONV=1` and quoted Windows paths for worktrees in Git Bash (otherwise paths become `C:\c\...`).
- Never `taskkill` all Godot; kill only your own PIDs. Never `rm -rf` outside your worktree. Don't commit `.import`/`.uid` churn or `kingdom/.godot/`.
- `player.gd` and `hero_face_driver.gd` are CRLF; keep them CRLF.
- Disk was nearly full twice; check `df -h /c` before importing or copying `.godot` (~14 GB per worktree).
- Never spend Meshy credits without the owner's OK in chat.
