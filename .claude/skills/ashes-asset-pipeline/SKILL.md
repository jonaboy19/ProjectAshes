---
name: ashes-asset-pipeline
description: Make or bring in any 3D asset for Rising Ashes (buildings, houses, creatures, characters, armor, props) so it matches the art style and runs at 60 fps on phones. Use before generating with Meshy, building in Blender, or adding any model to kingdom/assets.
---

# Rising Ashes asset pipeline

Target: Play Store / App Store, **60 fps on mid-range phones**. Every asset gets optimized before it's committed. No exceptions.

## 1. Decide the source (cheapest good option first)
1. **Already in the repo?** Check `kingdom/assets/incoming/README.md`, `incoming/_previews/`, `incoming/characters/README.md`, `incoming/armor/README.md`.
2. **Open-source pack** (CC0/MIT; see the `ashes-open-source-sourcing` skill).
3. **Blender script** for simple props (`kingdom/tools/blender/make_*.py`). Don't spend Meshy credits on barrels, crates or fences.
4. **Meshy** for unique hero buildings, house types and creatures. The account is a **paid plan**, so no attribution is needed.

## 2. Style lock
Match `docs/art_reference/village_target_1.png` and `concept_*.png`: stylised hand-painted medieval fantasy. Cream plaster, dark oak timber, grey fieldstone, slate or terracotta roofs, warm lanterns. Painterly textures, no baked harsh shadows. Put this sentence into every Meshy `texture_prompt`.

## 3. Meshy recipe
- Input image: a crop of a concept sheet (PowerShell `System.Drawing`; no python on this PC), or Meshy `text_to_image` with `nano-banana-2` (6 cr) using the style lock, as a clean 3/4 view on a white background.
- Hero buildings and creatures: `image_to_3d`, `ai_model: meshy-7`, textured, `target_formats: ["glb"]` (30 cr).
- Creatures to animate: `pose_mode: t-pose` for bipeds, then `meshy_rig` (5 cr, includes walk and run) and `meshy_animate` (3 cr each).
- **Meshy 7 ignores target_polycount.** Raw GLBs are 4–7M triangles and 130–200 MB. Never commit raw files; `*_raw.glb` is gitignored.
- Tell the user the credit cost before spending, and check the balance with `meshy_check_balance`.

## 4. Optimize (always)
```bash
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
"$B" -b --python tools/meshy/optimize_glb.py -- <raw.glb> <out_dir> <name> <hero|house|prop|small|creature>
"$B" -b --python tools/meshy/preview_turnaround.py -- <abs lod0.glb> <abs out.png>
```
| Budget | LOD0 tris / tex | LOD1 tris / tex |
|---|---|---|
| hero | 40k / 2048 | 12k / 1024 |
| house | 20k / 1024 | 6k / 512 |
| prop | 4k / 512 | 1.2k / 256 |
| small | 1.5k / 512 | 500 / 256 |
| creature | 15k / 1024 | 5k / 512 |

**When Blender decimation fails, use Meshy remesh (5 cr).** Thin geometry (stall canopies, poles, fences, awnings) gets shredded by collapse decimation, and loose-strand meshes (thatch roofs) stall above budget. Run `meshy_remesh` on the original Meshy task with `target_polycount` set to the LOD target, then pass the result through `optimize_glb.py` for the texture size. The texture is re-baked and the result is clean (this fixed the stalls and the peasant_a LOD1 on 2026-09-27). **Always look at the preview.** Triangle counts alone don't catch a shredded mesh.

Characters: player ≤ 15k tris, NPC ≤ 6–8k, ≤ 60 bones. No Draco/meshopt (Godot can't read them). In Godot, use VRAM-compressed textures, visibility ranges for LOD switching, and instancing for repeated props.

## 5. Interiors
Meshy buildings are solid shells. A door triggers loading a **separate interior scene** (Blender room plus furniture props); the town is hidden while inside. Only one interior is loaded at a time.

## 6. Verify and deliver
- **Look** at the turnaround render with Read before calling it done. Check it matches the style and has no holes, floating parts or smeared backs.
- Output goes to `kingdom/assets/incoming/ai3d/meshy/` (Meshy) or the matching incoming pack; previews go in `_previews/`.
- Commit to `claude/focused-curie-m09hbd` (shared with the cloud session). `git pull --ff-only` first. Keep every file under 90 MB.

## Always show the user
The user wants to **see a PNG of everything that gets made**. After each batch:
1. Send the preview sheet(s) to the user (SendUserFile).
2. Rebuild the gallery with `bash tools/gallery/build_gallery.sh` (add a section there for any new category) and commit `docs/asset_gallery/`.
3. The gallery is browsable at http://localhost:8765 via `tools/gallery/serve.ps1` (in the desktop app, use preview_start with the `asset-gallery` launch config).

## Parallel agents: rules
- **Never** kill Blender globally (`taskkill /IM blender.exe`). Other agents run headless Blender jobs at the same time. Kill only your own process by its PID.
- The Meshy account is shared, so check the balance before and after and report only your own task costs (log them in `tasks.tsv`).
- Agents don't commit. The main session reviews the previews and commits specific paths.
- Rigged monsters are in `ai3d/meshy/creatures/`. Meshy biped rigs strip Hips scale keys (Meshy idle clips scale the hips by about 1.18). Quadrupeds reuse the CC0 Quaternius Ultimate Animated Animals rigs. See `tools/meshy/creature_rig/`.

## Animation QA
Run it **after adding or changing any rigged character, creature, animal or clip library**, after re-rigging / re-exporting a GLB, and after the game changes movement speeds or which clips it plays:
```bash
bash tools/qa/anim_qa/run.sh               # metrics + 8-frame strips + contact sheets (GPU window)
bash tools/qa/anim_qa/run.sh --no-strips   # headless metrics only (~2 min)
bash tools/qa/anim_qa/run.sh --only=<id>   # one character/creature
```
It loads every type through the game's own loaders, samples each clip at 30 fps and grades foot sliding, floor penetration, floating, bone stretch, scale keys, pops, loop seams, T-pose leaks, root drift and clip speed vs. the in-game movement speed. Read `docs/qa/anim_qa_report.md` (ranked problems first) and **look** at `docs/qa/anim_sheet_<group>.jpg` and the worst `docs/qa/anim_strips/*.jpg`. New character types or clips must be added to `tools/qa/anim_qa/catalog.gd` (details in `tools/qa/anim_qa/README.md`). The script reverts `.import` files the Godot run rewrites; never kill other agents' Godot processes.

## Playtest bot
Run it **after any change a player would notice** (new assets placed in Ashford, lighting, UI, combat, performance work), before telling the user something "looks good in game":
```bash
kingdom/tools_qa/autoplay/run_autoplay.sh             # ~4 min, windowed on the real GPU
kingdom/tools_qa/autoplay/run_autoplay.sh --uncapped  # vsync/fps cap off, to see GPU headroom
```
It boots the real game and plays it through the real input path (joystick and camera touches, HUD buttons, keys, menu clicks): birth cutscene skip, a walk round Ashford with NPCs, notice board / guild / trader / Captain, the inn interior, wolves and the goblin warren, inn sleep and night, F5/F9. Output in `docs/qa/playtest/`: `NN_<step>.jpg` screenshots, `log.txt` (actions, a perf line every 0.5 s with fps, GPU ms, draw calls, primitives and nodes, per-step summaries, `FINDING` lines, engine errors counted), `summary.json`, `errors.txt`. **Look at every screenshot** (T-poses, camera inside walls, floating props, pink/white textures, UI overlap) and write up what you see in `docs/qa/PLAYTEST_REPORT.md`. Details and how to add a step: `kingdom/tools_qa/autoplay/README.md`. A Godot run can rewrite `.import` files: revert only the ones your run changed.
