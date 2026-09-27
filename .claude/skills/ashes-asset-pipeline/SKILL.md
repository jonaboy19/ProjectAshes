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

Characters: player ≤ 15k tris, NPC ≤ 6–8k, ≤ 60 bones. No Draco/meshopt (Godot can't read them). In Godot, use VRAM-compressed textures, visibility ranges for LOD switching, and instancing for repeated props.

## 5. Interiors
Meshy buildings are solid shells. A door triggers loading a **separate interior scene** (Blender room plus furniture props); the town is hidden while inside. Only one interior is loaded at a time.

## 6. Verify and deliver
- **Look** at the turnaround render with Read before calling it done. Check it matches the style and has no holes, floating parts or smeared backs.
- Output goes to `kingdom/assets/incoming/ai3d/meshy/` (Meshy) or the matching incoming pack; previews go in `_previews/`.
- Commit to `claude/focused-curie-m09hbd` (shared with the cloud session). `git pull --ff-only` first. Keep every file under 90 MB.
