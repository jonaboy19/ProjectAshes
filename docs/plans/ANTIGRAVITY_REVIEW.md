# Antigravity unmerged work: review for the owner (2026-10-22)

Read-only review. Nothing was edited, merged or run. Two new tracking refs were fetched (`origin/antigravity/*`, `origin/claude/world-t3d`); the ProjectAshes checkout and working tree were not touched.

Compared against `origin/claude/focused-curie-m09hbd` ("main"). Context applied: PC-first (Forward+), `PC_TIERS` + `Quality.profile` in `kingdom/scripts/core/quality.gd` on main, world rebuild on Terrain3D at 12 288 m (WORLD_BRIEF), 32 km proposal not adopted, free/commercial-OK assets only, no Meshy spend, Style G.

## 0. Headline

- **The branches are stale.** All Antigravity work forks from `eb805176` (2026-09-29). Main is **714 commits** ahead. A dry-run `git merge-tree` of aaa-mocap-animations onto main conflicts in 7 files: `quality.gd`, `main.gd`, `building_profiles.gd`, `region_sites.gd`, `author_traversal.py`, `preview_rm.gd`, `preview_free_library.gd.uid`. `project.godot`, `assets.gd`, `city_planner.gd` and `LOCAL_SESSION_HANDOFF.md` auto-merge. Do not merge the branch wholesale. Cherry-pick paths (section 11).
- `antigravity/creature-assets` is **not on origin**. It exists only as a local branch in worktree `C:\Users\Jonna\Documents\ProjectAshes-antigravity` at `1983bfeb` (2026-10-01), which is already an ancestor of main. Zero unmerged commits, clean worktree. Nothing to review.
- The ProjectAshes checkout is on `antigravity/aaa-mocap-animations` with **169 uncommitted files**, and a stash named `valencious_world_renders` exists. Neither was touched. They are presumably the source of the snapshot branch.
- No biggest-file problem: the largest blob in either branch is 45 MB (`docs/VALENCIOUS_WORLD_VIEWER.html`, docs only). No game asset is over 15 MB. The snapshot's worst file is a 24 MB `waveletNoiseTile.bin` at repo root (junk).
- Style G: the interior renders are on-style (warm timber and plaster). The Blender world and arena renders are not. The only on-style evidence in the whole set is `godot_ingame_kingsreach_gate.png` (snapshot branch), a real in-game capture.

## 1. aaa-mocap-animations: all 19 commits not in main

`origin/antigravity/aaa-mocap-animations` fc8f73a7, 166 files, +72 568 / -629. Commits oldest to newest:

| # | Commit | Subject (short) |
|---|---|---|
| 1 | f675b44b | 40 AAA mocap clips (Locomotion 15, LivingWorld 28) + finger articulation |
| 2 | d58d4bd3 | Avatar bending, Combat_Adv, LivingWorld expansion |
| 3 | bc1177fb | Combat chains / reactions / weapons / bending advanced (103 clips) |
| 4 | 5ccc8760 | Rooftop parkour, knight/assassin, chantless magic, mastery, knockbacks (136) |
| 5 | 7ede1061 | Master Combat Universe GLB (179 actions) |
| 6 | 6d083bd3 | Umbrella/Donghua weapon arts, Tensura void powers (146) |
| 7 | c954707b | Mythic martial, dual blade, 3 fantasy horses (158 clips) |
| 8 | 7bdbc352 | 32 km Valencious sectors, 6 "high-poly" races, race evolution, enterable cottage |
| 9 | b2334b36 | Interactive HTML world viewer, 2 orc variants |
| 10 | 0249b758 | Blender renders, "future regions" blueprint |
| 11 | e3a3ff70 | Docs integration, bulletproof viewer script |
| 12 | 25f3a2d3 | Renders: Ashford, interiors, 32 km map, dark elf hero |
| 13 | **b8a8c505** | **PC Master tier (quality.gd, project.godot, main.gd, manifest)** |
| 14 | 0b7bb1de | 5 new walk-in interiors + renders + viewer |
| 15 | dc62c398 | Handoff doc for the 10 interiors |
| 16 | 61a6eb10 | Colosseum model, tournament system, city/region placement, 5 discoveries |
| 17 | 40d64e74 | Handoff doc for tournament |
| 18 | 45e02581 | Blender continent aerial render, canvas radar viewer |
| 19 | fc8f73a7 | Viewer overhaul, 15-biome atlas, panoramas |

Commit sizes (assets by group, from git object sizes): mocap GLBs 41 MB (32 files), races 49 MB, interiors 35 MB, renders 44 MB, viewer HTML 45 MB, horses 2.5 MB. Branch total about 219 MB.

## 2. Per-feature review

### 2.1 Mocap animations (commits 1-7): 15 GLB packs + Master + 158 clips

- Adds: `kingdom/assets/incoming/animations/aaa/UAL_AAA_*.glb` (+ `.clips.json` sidecars), 16 GLBs totalling about 41 MB. Largest: Mythic_Martial 14.3 MB, Master_Combat_Universe 11.2 MB, Umbrella_Donghua 10.2 MB; the rest are 0.15-1.2 MB. Also 15 `cfg_aaa_*.json` configs, rewrites of `retarget_bvh.py`, `author_traversal.py`, `preview_rm.gd`, `render_trav.sh`, `kaykit_make_blend.py`.
- Wired: **no.** `git grep` for `animations/aaa` and `UAL_AAA` finds nothing in `kingdom/scripts|scenes|autoload|data|project.godot`. Assets plus tools only. The handoff states "zero modifications to kingdom/scripts" and the clips are never referenced by any animation table.
- Licence: configs point at `${ANIM_SRC}/cmu-mocap/data` (CMU BVH) retargeted onto the Quaternius UAL rig (CC0). CMU Graphics Lab mocap is free for all uses including commercial, and main already carries `animations/cmu_mocap`. No licence/source note is shipped alongside the new GLBs, so the clip-to-BVH provenance is not recorded. Some clips (KayKit rigs) go through `kaykit_make_blend.py`; KayKit is CC0.
- Quality/risk: 158 clips duplicated three ways (per-pack GLBs and the 11 MB Master) - double storage. Clip names are fan-IP flavoured ("Gluttony Void Maw", "Megiddo Solar Pillar", Avatar bending katas, "Tensura"); these are only names but should be renamed before a public build. Retarget quality has not been validated in-game (no preview captures for them in the branch). `retarget_bvh.py` and `author_traversal.py` have main-side edits since the base; they conflict.
- Recommendation: **MERGE PARTS.** Take the data, not the tooling: the per-theme GLBs and `.clips.json` for the packs main lacks (Combat_Chains, Combat_Reactions, Combat_Weapons, Combat_Knockbacks, Combat_Classes, Combat_Adv, Magic_Chantless, Traversal_Rooftops, Locomotion, LivingWorld) plus their `cfg_aaa_*.json`. Skip the 11 MB Master GLB (duplicates everything), skip the Avatar/bending, Tensura/Umbrella/Mythic packs until renamed and wired, skip rewrites of `retarget_bvh.py`/`author_traversal.py`/`preview_rm.gd` (conflicting; port by hand if needed). Reason: useful CC0/CMU-derived clip stock, but nothing uses it, so land it under `incoming/` without wiring and decide wiring separately.

### 2.2 Fantasy mount horses (commit 7)

- Adds: `animals/fantasy/horse_draco.glb`, `horse_abyssal.glb`, `horse_armored_destrier.glb` (0.9 MB each, 13 anims), `_tools/build_fantasy_mounts.py`, build JSON.
- Wired: no (`horse_draco` not referenced in game code). Built from the project's own horse via script (no third-party source).
- Style G: not viewed in isolation (the draco-horse render exists as `render_draco_horse.png`, not opened). Obsidian/crimson "dragon horse" is off the storybook palette.
- Recommendation: **DROP for now** (or park in `incoming/`). Reason: unwired, style unverified, mounts not in the current plan.

### 2.3 Race GLBs (commits 8-9)

- Adds: `characters/races/race_{beastkin_lupine,dark_elf,draken_dragonnewt,dwarf,elf,tiefling,undead_wight,ork_beast_juggernaut,ork_noble_warlord}.glb`; 3 of them are **14.8 MB each**, the rest about 0.8 MB (about 49 MB in total, inconsistent: the same generator produced 15 MB and 0.8 MB files, suggesting embedded textures or duplicated meshes in three). Also `build_high_poly_races.py`, `build_orc_variants.py`, `race_behavior_profiles.json` (176 lines), `races.json` rewrite (+/-100 lines), `race_evolution_system.gd` (189 lines), `enterable_building_manager.gd` (87 lines).
- Licence: derived from Quaternius **Universal Base Characters** (`Superhero_Male_FullBody.gltf`, CC0) with attached ears/horns/tails/beards. Fine licence-wise.
- Wired: **no.** `race_evolution_system`, `race_dark_elf`, `race_behavior_profiles`, `enterable_building_manager` have zero references from scenes, scripts or autoloads.
- Quality: the opened `render_races_lineup.png` shows **unclothed, anatomically explicit base meshes** (visible genitalia, one with a tail attached at the groin) in T-pose on a flat grey background. This is a hard blocker for shipping; Style G needs clothed, stylised characters, not realistic anatomy. `races.json` is a data file that main's systems may read: the rewrite will clash with main's current data (`races.json` changed on both sides).
- Recommendation: **DROP** the GLBs and generator. **MERGE PARTS (optional, review first)**: `race_evolution_system.gd` as design reference only. Reason: explicit untextured body meshes, no wiring, and `races.json` would overwrite main's data.

### 2.4 32 km world data (commit 8, `valencious_32km_sectors.json`, `world_optimizer_32km.py`)

- Adds a 1 MB JSON (53 k lines) of sector data plus an optimizer script, `enterable_cottage.glb`, `build_enterable_buildings.py`. Nothing references it.
- Conflicts with plan: the owner decision is Terrain3D at 12 288 m, 32 km not adopted.
- Recommendation: **DROP.** Reason: superseded by WORLD_BRIEF, unwired.

### 2.4b World viewer and renders (commits 9-12, 18-19)

- Adds: `docs/VALENCIOUS_WORLD_VIEWER.html` (**45 MB** single-file HTML with base64 art, rewritten 6 times, plus `tools/build_comprehensive_viewer.py`, `generate_valencious_html_viewer.py`, `build_bulletproof_viewer.py`), about 35 PNG/JPG renders in `docs/img/actual_renders/` (43.6 MB), `docs/kingdom/blender_previews/valencious_full_world_overview.png`, `make_valencious_world_overview.py`, `render_actual_assets.py`.
- Wired: docs only. No game code.
- Quality: viewed `render_valencious_32km_full_world.png`: a very dark low-poly heightfield with unlit black blocks (buildings) and craters: not Style G, not useful (it documents the 32 km proposal that was dropped). `render_valencious_tournament_arena.png` shows a **geometry bug**: three-quarter arch rings floating over an arena, towers detached from the bowl, seating floating as scattered benches. `render_kingsreach_town_gate.png` and `render_ashford_village_square_pbr.png` are clean Blender turntable shots of existing main assets (blue conical-roof gate, half-timber houses), plausible Style G for assets but on a flat green plane with grey sky, not game footage. The reference image `00_MAIN_kingsreach_gate_market.webp` (sunlit market, warm, saturated, flowers, red banners) is far more painterly than any of them.
- Risk: a 45 MB HTML in git history is permanent and will bloat clones; each rewrite of it in commits 9-12/18-19 stacks 5-45 MB of history.
- Recommendation: **DROP** the viewer HTML and generator scripts, the 32 km overview, atlas/panorama JPGs (`ashford_vale_golden_hour_river_panorama.jpg`, `races_and_civilizations_of_valencious.jpg`, `valencious_world_atlas_all_regions.jpg`, `duskbriar...`, `mount_taiyun...`: they appear to be AI-generated concept art with no source note: licence unknown, which breaks the free/commercial-OK rule). **MERGE PARTS (optional)**: `docs/img/actual_renders/render_interior_*.png` (9) as interior QA references, ~12 MB, only if wanted.

### 2.5 Ten walk-in interiors (commit 14, docs in 15)

Five new interiors (the other five already existed on main; commit 15 just documents the ten).

- Adds per interior: GLB (3.8-8.2 MB), `.glb.import`, `.json` stats, `.tscn` scene (170-235 lines), and a Blender maker script: **manor** (`interior_manor.glb` 5.7 MB, 48 099 tris), **trader** (8.2 MB, 61 844 tris), **sect** (wuxia hall, 5.2 MB, 42 686 tris), **orc longhouse** (3.8 MB, 32 258 tris), **academy** (6.8 MB, 54 654 tris). Total about 29 MB + 5 scenes. Also modified `interior_blacksmith.glb` (+8 bytes) and its `.json`/`.tscn` (re-export noise).
- Wired: **partly.** `building_profiles.gd` gains `INTERIORS`/`PROMPTS` entries: `mhouse_manor`, `mhouse_trader`, `sect_hall`, `shrine`, `orc_longhouse`, `orc_stronghold`, `academy`, `magic_school`. Main already uses `mhouse_manor` and `mhouse_trader` as real lot types (`city_planner.gd`, `property.gd`, `SHOP_BUILDINGS`), so manor and trader would become enterable in existing towns after merge. `sect_hall`, `orc_longhouse`, `academy` names have no producing code on main (only `cultivation.gd` mentions `sect_hall` as an XP source), so those three are dead entries until a region needs them. Each scene uses `interior_door.gd` and `interior_room.gd` (both exist on main) and a single NPC marker.
- Licence: procedural Blender output using the in-repo `interior_kit` and the project's `RA_*` materials; no third-party content found in the make scripts (checked manor, orc).
- Quality: viewed the noble manor (timber beams, plaster, fireplace, banners, red/yellow rugs): clean, warm, closest thing to Style G in the branch. Orc longhouse render: a giant glowing pink disc under a cauldron and a bare stone arch: blown-out emissive, reads as an unfinished placeholder. Main's own README rule says every interior is under 60 k tris with 4 materials and baked vertex lighting: trader (61.8 k) busts it and all five use `RA_Wood_hp` (a high-poly variant of the material) instead of the shared kit. Each has only one NPC marker (vs 2-3 in main's interiors), so they are mostly empty rooms.
- Conflicts: `building_profiles.gd` conflicts (main has since added `SLICE_LAYOUTS`, `Layouts`, `SHOP_BUILDINGS`, `TAVERN_BUILDINGS`); resolve by hand-adding the 8 `INTERIORS` rows and prompts. `kingdom/scenes/interiors/README.md` on main should be updated.
- Recommendation: **MERGE PARTS**: `interior_manor.*` and `interior_trader.*` (+ their two `.tscn`, `make_interior_manor.py`, `make_interior_trader.py`) and the manor/trader `building_profiles` rows; **hold** sect/orc/academy GLBs and scenes (no producer; orc glow broken; sect/academy unviewed) until a region needs them. Do not take the blacksmith re-export. Reason: manor and trader plug into existing lot types, the rest would add 16 MB of unreferenced content.

### 2.6 Grand Tournament Colosseum + tournament system + 5 wilderness discoveries (commits 16-17)

- Adds: `arena_colosseum.glb` (0.76 MB), `make_tournament_arena.py` (204 lines), `tournament_system.gd` (182 lines: 4 tiers Bronze to Mythic, entry fees, purses, reward items, betting odds), plus edits: `assets.gd` (2 BUILDINGS rows), `city_planner.gd` (adds an arena landmark in every castle/major city), `region_sites.gd` (+90 lines: `_tournament_arena`, `_hidden_discoveries`: smuggler cove, runestone grove, dwarf cavern gate, hermit sanctuary; bandit vault is described but not implemented).
- Wired: **yes for the world placement, no for the system.** The arena landmark and discovery sites are generated by `region_sites.plan()` and `city_planner.plan()`. `TournamentSystem` is a `Node` with no autoload, no scene, no caller; reward ids (`weapon_obsidian_sunblade`, `armor_caldric_knight_plate`, `weapon_iron_broadsword_master`) were not checked against `data/items`, so may not exist.
- Risk: (a) the arena model is broken geometry (see 2.4b render): arches and towers float, seating scattered; (b) `city_planner.gd` edit adds a landmark in every city, which shifts layouts for every seed and will invalidate the saved/snapshot layouts and tests that depend on plan determinism; (c) `region_sites._hidden_discoveries` uses hard-coded legacy `WorldGen` coordinate ranges (-900..900, y -1400..-800, etc.) for the old procedural world, which the Terrain3D 12 288 m rebuild replaces; it also consumes `rng` draws, changing every later site's position; (d) uses `meshy:landmark_runestone` (existing Meshy asset in repo: no new spend, but a Meshy licence dependency); (e) `region_sites.gd` conflicts with main's edits.
- Recommendation: **MERGE PARTS (design only):** keep `tournament_system.gd` as a reference/prototype under a docs or `scripts/sim` path **only if** a hooking plan exists; **DROP** `arena_colosseum.glb` + `make_tournament_arena.py` (rebuild the arena properly on the new world), **DROP** the `city_planner.gd`/`region_sites.gd`/`assets.gd` edits (legacy coordinates, conflicts, layout churn). Salvage the 5 discovery concepts as text for the Terrain3D POI list. Reason: good design ideas, broken model, wired into a world that is being replaced.

### 2.7 PC Master tier settings: b8a8c505 (commit 13)

Files: `kingdom/project.godot` (+/-9), `scripts/core/main.gd` (1 line), `scripts/core/quality.gd` (18 lines), `tools/pc_world_upgrade.py` (88), `data/world/pc_world_assets_manifest.json` (1284 lines).

What it actually does:
- Edits the **mobile `TIERS`[ULTRA]** row, not a PC table. That row now lives in the mobile profile on main, so those edits would raise phone ULTRA to 380 m shadows, 8 chunks and 36 NPCs: harmful for the phone target. This is the core reason it cannot be merged as is.
- Changes `detect_tier()` so any desktop with at least 6 GB RAM is ULTRA, and integrated GPUs go to HIGH. Main already has an `is_pc()` branch (4080/4090/50-series/RX 79xx = ULTRA; other discrete = HIGH; integrated = LOW). The 6 GB rule would put an integrated-graphics laptop on ULTRA; it contradicts PC1_BRIEF.
- `project.godot`: viewport 1920x1080 + window override 1920x1080 + `resizable=true`, and `pointing/emulate_touch_from_mouse` true -> **false**. On main (and world-t3d) desktop mouse-look works only because of that emulation (PC1_BRIEF section 0 item 4: look is a drag on the HUD look area, `move_*` keys only). Flipping it without a real mouse-look path breaks camera control on PC. It is the only line in this commit that is both harmful and easy to miss.
- `main.gd`: `terrain.view_radius = Quality.view_radius` (+2 capped at 12 in command view) replaces the old `mini(5/4, Quality.view_radius)`. Main has since replaced this whole line with `CellStreamer` radii (`cells.radius_cells("terrain")`), so the line conflicts and is obsolete.
- Manifest + script: audits 514 `*_lod0.glb` etc. (triangles, max texture px) but hard-codes `C:\Users\Jonna\...` paths and lists Meshy assets (already in repo). The JSON has no consumer in the game. Marketing text "8GB RAM / 4GB VRAM PC certified" is unsupported (no measurement was run).

Comparison against main's `PC_TIERS` (the b8a8c505 ULTRA row vs `PC_ULTRA`; keys it did not set are the mobile defaults):

| Key | b8a8c505 ULTRA | PC_ULTRA (main) | PC_HIGH (main) | Verdict |
|---|---|---|---|---|
| shadow_dist | 380 | 300 | 220 | candidate: raise PC_ULTRA 300 -> 380 only if cascade cost is measured; main row is already tuned for 4080+ |
| shadow_size | 4096 | 8192 | 4096 | keep main (8192) |
| ssr | true | true (64 steps) | true (48) | already covered, and main also has `ssr_steps`/`water_ssr` |
| sdfgi / ssil / ssao / glow / vol_fog | true | true (plus cascade/ray/cell tuning) | | covered, main has finer keys |
| lod_threshold | 0.5 | 0.75 | 1.0 | candidate: PC_ULTRA 0.75 -> 0.5 (higher mesh detail at distance). Perf-gate it |
| range | 2.0 | 2.0 | 1.5 | same |
| aniso | 4 | 4 | 4 | same |
| msaa | 3 (8x) | 0 (FSR2 scale 1.0) | 0 | **reject**: 8x MSAA on Forward+ is very expensive and clashes with main's FSR2 path (settings_store also overwrites MSAA); main chose FSR2/TAA |
| npc_full | 36 | 36 | 28 | same |
| rig_budget | 24 | 16 | 12 | candidate: PC_ULTRA 16 -> 24 only with a measured CPU budget |
| npc_sprites | 120 | 200 | 140 | **reject**: lower than main's 200 |
| view_radius | 8 | 7 | 6 | candidate: PC_ULTRA 7 -> 8. Check against RAM8 cap and CellStreamer `stream_mul` first (main's streaming uses `stream_mul: 1.5` on top) |
| light_fade | 160 | 0 (no fade) | 0 | **reject**: 0 already means no fade, so 160 would add a fade |
| fxaa | true | false | false | **reject** (main uses FSR2/TAA) |
| town_far | 0 | 0 | 0 | same |

**Exactly what to adopt into `PC_TIERS`:** nothing is a clear win; at most four optional PC_ULTRA-only raises, each needing a measured frame-time pass on an RTX 4080-class GPU before landing: `shadow_dist` 300 -> 380, `lod_threshold` 0.75 -> 0.5, `view_radius` 7 -> 8, `rig_budget` 16 -> 24. Do **not** adopt: `msaa` 3, `fxaa`, `npc_sprites` 120, `light_fade` 160, the `shadow_size`, the `detect_tier` RAM >= 6 GB rule, the `emulate_touch_from_mouse=false` flip, the `main.gd` view_radius line, and none of it into the mobile `TIERS`. Safe, separate item: 1920x1080 base viewport + `resizable=true` could go into `project.godot`, but check with the PC1 owner first because the HUD and look area were authored against 1280x720 (`canvas_items`/`expand` stretch should absorb it).

- Recommendation: **DROP** (no merge). Reason: it edits the mobile table, regresses PC detection, would break mouse-look, and main's `PC_TIERS`/`CellStreamer` already supersede every setting it touches. Take the four optional values above by hand after a perf test.

### 2.8 Docs and handoffs

- Adds: `HANDOFF_AAA_ANIMATIONS.md` (root, duplicated in `docs/anim/HANDOFF_AAA_MOCAP_LIVING_WORLD.md`), `HANDOFF_VALENCIOUS_32KM_RACES.md` (root + `docs/anim/`), edits to `docs/LOCAL_SESSION_HANDOFF.md` (conflicts with main's rewrites), future-regions blueprint (Greek/Rome/Egypt/Sky Islands/Dwarf Cavern, in the viewer).
- Recommendation: **DROP** the duplicated root-level docs and the `LOCAL_SESSION_HANDOFF.md` edits (stale, 32 km). Keep one copy of the animation handoff only if the clips merge (`docs/anim/HANDOFF_AAA_MOCAP_LIVING_WORLD.md`).

## 3. uncommitted-snapshot-2026-10-22 (afc1b2fd)

One commit on top of fc8f73a7: "Snapshot of uncommitted Antigravity work ... Not reviewed." Relative to the aaa branch it adds 1256 files (+/- about 134 MB blob content, 1097 added, 158 modified, 1 renamed). Breakdown, from the diff:

| Group | Files | Content | Verdict |
|---|---|---|---|
| `docs/qa/perf_visual`, `docs/qa/grounding`, `kingdom/docs/qa` | about 860 | QA captures: 56.8 MB + 34.3 MB of screenshots/CSVs | DROP (generated QA output, bloat) |
| `docs/kingdom/blender_previews` | 78 | previews of existing assets (31.9 MB) | DROP (main already has a preview set; regenerate on demand) |
| `kingdom/assets/kaykit` + `game/assets/kaykit` | 61 + 39 | M entries with equal add/del = line-ending churn | DROP |
| `game/*` (old prototype project) | about 25 files | **CRLF-only changes**: `git diff --ignore-cr-at-eol` on `game/`, `kingdom/scripts`, `GDD.md`, etc. shows 125 real insertions in total | DROP |
| `kingdom/assets/incoming/**/License.txt`, `OFL.txt`, `Readme.txt`, `Overview.html` | about 30 | line-ending churn on licence files (Kenney, Quaternius, IM Fell) | DROP (do not rewrite licence files) |
| `*.import*.tmp`, `*.import~RF*.TMP` | 14 | Godot editor temp files in `polyhaven/`, `quaternius/` | DROP (junk, must not be committed) |
| `waveletNoiseTile.bin` (repo root) | 1 | 24 MB stray binary | DROP |
| `tools/vfx/__pycache__/*.pyc` | 3 | cache | DROP |
| `docs/art/water/tmp_new_low`, `tmp_old_low` | 4 | temp water compares | DROP |
| `docs/img/valencious`, `docs/img/actual_renders/godot_ingame_*` | 6 + 4 | 4 real in-game captures (3.1 MB each) | MERGE PARTS (only `godot_ingame_kingsreach_gate.png` as a Style G progress shot) |
| `kingdom/addons/effekseer/` | 32 | Effekseer for Godot 4 v1.80.5.1 (MIT; includes Windows DLL and Android .so) | see below |
| `kingdom/assets/vfx/effekseer/` | 50 | demo effects from the Effekseer editor samples (CC0; neon/anime style, README itself says "not our storybook look") | DROP |
| `kingdom/assets/vfx/flipbooks/` + `tools/vfx/*.py` + `kingdom/shaders/vfx_flipbook/flipbook.gdshader` + `kingdom/scripts/vfx/flipbook_fx.gd` + `kingdom/tools_qa/vfx_flipbooks/` | about 25 | 6 flipbook atlases (fire, smoke, dust, splash, lightning, swirl) baked by Blender Mantaflow / numpy scripts, `LICENSE.md` says original project work with no third-party content | MERGE PARTS (see below) |
| `kingdom/tools_qa/world_tour/` | 2 | QA tour scene | DROP |
| `kingdom/addons/terrain_3d/.gdignore.bak` | 1 | marker file only | DROP |
| `kingdom/project.godot` | 1 | enables `res://addons/terrain_3d/plugin.cfg` as an editor plugin, but the addon was not added (only a `.bak` file) | DROP (main/world-t3d own Terrain3D integration) |
| `kingdom/shaders/impostor.gdshader`, `pixel_post.gdshader`, `kingdom/scripts/actors/camera_shake.gd`, `kingdom/scenes/main.tscn` | 4 | mostly CRLF; real content change is small or none | DROP (`git diff --ignore-cr-at-eol` of `kingdom/scripts` and `shaders` shows only the 3 new vfx files) |
| `kingdom/assets/incoming/animations_free2/traversal_authored/UAL_Authored_Traversal.glb` | 3 | authored traversal clips (hand-authored via `author_traversal.py`) | MERGE PARTS (only if the traversal tooling is also ported) |

Effekseer: MIT-licensed plugin, binaries for Windows x64 and Android arm32/arm64 only (no Linux/macOS libs). Adds a native GDExtension dependency to a game that already has its own pooled `ElementFX` VFX set (main commit eb805176 context). Recommendation: **DROP** unless the owner explicitly wants Effekseer; main already has a VFX system and the shipped sample effects are anime-neon.

Flipbooks: the six atlases are 1024x1024 PNGs, original, with a clear `LICENSE.md`: **MERGE PARTS** (`kingdom/assets/vfx/flipbooks/*`, `kingdom/shaders/vfx_flipbook/`, `kingdom/scripts/vfx/flipbook_fx.gd`, `tools/vfx/bake_*.py`, `flipbook_common.py`) only if the VFX owner wants a flipbook path alongside ElementFX; they have not been checked against Style G (not viewed).

Overall snapshot recommendation: **DROP the branch as a whole**, **MERGE PARTS** only the items marked above. It is a working-tree dump, commit message says "Not reviewed", and 1256 files are mostly churn.

## 4. creature-assets

Not on origin; local only, worktree `C:\Users\Jonna\Documents\ProjectAshes-antigravity`, `1983bfeb`, clean tree. Ancestor of main: nothing unmerged. **DROP** (nothing to do; delete the local branch/worktree when convenient).

## 5. Licence and source notes summary

| Item | Source | Licence status |
|---|---|---|
| Mocap GLBs | CMU BVH (and KayKit/Quaternius) retargeted to UAL | CMU: free for all uses; UAL/KayKit: CC0. No source note in the new folder; add one when merging |
| Race GLBs | Quaternius Universal Base Characters | CC0; ok, but unsuitable (explicit) |
| Interiors, arena, horses | in-repo Blender scripts | project-owned |
| Renders in `docs/img/actual_renders` | Blender (own assets) | ok; the 5 atlas/panorama JPGs look AI-generated, no source note: treat as unknown, do not ship |
| Effekseer plugin | effekseer/Effekseer | MIT, ok |
| Effekseer sample effects | Effekseer editor samples | CC0 (credit requested), style mismatch |
| Flipbooks | Blender Mantaflow / numpy | project-owned (LICENSE.md present) |
| `pc_world_assets_manifest.json` | audit of existing Meshy lod0 | lists Meshy assets already in repo (no new spend) |

No new asset in any branch was purchased or generated by Meshy; the existing Meshy files it audits and the `meshy:landmark_runestone` reference are already on main.

## 6. File-size and conflict checklist

- Over 50 MB: none in git objects. Largest: `VALENCIOUS_WORLD_VIEWER.html` 45.0 MB (docs), `waveletNoiseTile.bin` 24 MB (snapshot junk).
- Over 10 MB (game assets): races x3 14.8 MB, Mythic_Martial 14.3 MB, Master_Combat_Universe 11.2 MB, Umbrella_Donghua 10.2 MB.
- Files changed on both sides since merge-base `eb805176`: `LOCAL_SESSION_HANDOFF.md`, `project.godot`, `main.gd`, `quality.gd`, `assets.gd`, `building_profiles.gd`, `city_planner.gd`, `region_sites.gd`, 4 files under `kingdom/tools/anim/free2/`, `preview_free_library.gd.uid` (add/add). Hard textual conflicts: `quality.gd`, `main.gd`, `building_profiles.gd`, `region_sites.gd`, `author_traversal.py`, `preview_rm.gd`, `preview_free_library.gd.uid`. Also `world_gen.gd` is not touched by Antigravity, but `region_sites` calls `WorldGen.lake_center`, `lake_radius`, `forest_density`, `height`, `settlements`: these APIs are what the Terrain3D rebuild replaces.

## 7. Summary table

| Item | Rec | Reason |
|---|---|---|
| 19 aaa commits as a branch | DROP wholesale | 714 commits stale, 7 hard conflicts |
| Mocap packs (non-themed ones) | MERGE PARTS | CMU-derived, CC0 rig, useful, unwired |
| Master GLB, Mythic, Umbrella, Avatar packs | DROP for now | duplicate / fan-IP names / unwired |
| Fantasy horses | DROP | unwired, off-style |
| Race GLBs + `races.json` | DROP | explicit meshes, would overwrite main data |
| `race_evolution_system.gd`, `enterable_building_manager.gd` | MERGE PARTS (as design reference) | unwired scripts |
| 32 km data + optimizer | DROP | superseded by 12 288 m Terrain3D |
| World viewer HTML + generators | DROP | 45 MB, 32 km, regenerate if ever needed |
| 5 AI-looking panorama/atlas JPGs | DROP | no source/licence note |
| Interiors: manor, trader | MERGE PARTS | plug into existing lot types, on-style |
| Interiors: sect, orc, academy | DROP for now | no producing code, orc render broken, trader >60k tris |
| Colosseum GLB | DROP | geometry broken |
| `tournament_system.gd` | MERGE PARTS (reference) | unwired, rewards unchecked |
| 5 wilderness discoveries | DROP code, keep concept | legacy WorldGen coords |
| b8a8c505 PC Master tier | DROP | edits mobile table, breaks mouse-look, detection regresses; 4 optional PC_ULTRA numbers by hand |
| Snapshot branch | DROP (cherry-pick flipbooks, one in-game shot, traversal clips) | 1256 files, mostly churn/junk |
| creature-assets | DROP | already in main |

## 8. Ordered merge plan

1. Do nothing on the ProjectAshes checkout until its 169 uncommitted files and the `valencious_world_renders` stash are triaged by the owner (they are the likely source of the snapshot).
2. In a fresh worktree off main, `git checkout origin/antigravity/aaa-mocap-animations -- <paths>` for the mocap data only (the non-Master, non-fan-IP packs listed in 2.1) plus their `cfg_aaa_*.json`. Add a `SOURCES.md` next to them (CMU mocap + Quaternius UAL, CC0 / free-commercial). Commit as an unwired `incoming/` import. Do not take `retarget_bvh.py` / `author_traversal.py` / `preview_rm.gd` rewrites.
3. Interiors: check out `interior_manor.*`, `interior_trader.*`, `manor_interior.tscn`, `trader_interior.tscn`, `make_interior_manor.py`, `make_interior_trader.py`. Hand-merge the two `INTERIORS`/`PROMPTS` rows into main's `building_profiles.gd`. Re-export trader under 60 k tris (or switch to `RA_Wood`), add 2-3 NPC markers, update `scenes/interiors/README.md`, then run the interior door test and a visual check. Leave sect/orc/academy parked.
4. PC tier: run a perf pass on a 4080-class GPU for the four optional PC_ULTRA raises (`shadow_dist` 380, `lod_threshold` 0.5, `view_radius` 8, `rig_budget` 24) and adopt only the ones that stay inside the frame budget. Reject everything else in b8a8c505. Decide separately on 1920x1080 base viewport; do not touch `emulate_touch_from_mouse` until a real mouse-look path exists.
5. Tournament and discoveries: copy `tournament_system.gd` to a design folder with the item ids checked, move the 5 discovery ideas into the Terrain3D POI list in the WORLD_BRIEF, and rebuild the arena properly on the new world; do not merge the arena GLB or `city_planner`/`region_sites`/`assets` edits.
6. Snapshot: cherry-pick `kingdom/assets/vfx/flipbooks/*` (+ shader, `flipbook_fx.gd`, bake scripts) only if the VFX owner wants it, and `docs/img/actual_renders/godot_ingame_kingsreach_gate.png` as a progress capture. Add `*.import*.tmp`, `*.TMP`, `__pycache__/` and `waveletNoiseTile.bin` to `.gitignore` if not already there.
7. Retire: delete `origin/antigravity/uncommitted-snapshot-2026-10-22`, the local `antigravity/creature-assets` branch/worktree, and (after step 2) the aaa branch; ask Antigravity to stop committing base64 HTML, QA screenshots and licence-file line-ending rewrites.
