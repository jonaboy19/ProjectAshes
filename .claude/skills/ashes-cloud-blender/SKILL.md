---
name: ashes-cloud-blender
description: Run Blender for Rising Ashes inside the cloud container (no Blender binary; bpy Python module), build/regenerate procedural assets and delegate Blender work to cheaper agents safely. Use whenever a cloud session needs to model, texture, rig or preview anything.
---

# Blender in the cloud session

The container has no Blender and blocks blender.org, but PyPI works: Blender 5.0.1 as a Python module.
```bash
python3 -m venv /tmp/claude-0/bpyenv && /tmp/claude-0/bpyenv/bin/pip install -q bpy   # once per container
/tmp/claude-0/bpyenv/bin/python kingdom/tools/blender/make_<name>.py <out.glb>          # one asset
/tmp/claude-0/bpyenv/bin/python kingdom/tools/blender/build_town_assets.py [names...]   # GLB + LOD + preview
cd kingdom/tools/blender && /tmp/claude-0/bpyenv/bin/python make_humans.py --only a,b [--no-atlas] [--sixsheet]
```
Headless only: previews render with Cycles CPU (keep each < 2 min). Read every preview PNG before calling it done.

## Kit and conventions
- Generators: `kingdom/tools/blender/make_*.py` on top of `ra_kit.py` → `village_kit.py` → `town_kit.py`; `ra_polish.py` exports.
  Outputs: `kingdom/assets/generated/<name>.glb` (+ `_lod1`, `_lod2`), previews `docs/kingdom/blender_previews/<name>.png`.
- Origin at ground centre, front faces Blender -Y = Godot +Z, metres. Register new buildings in `Assets.BUILDINGS`
  (`scripts/world/assets.gd`) and their size in `BuildingProfiles.SIZE`; houses must be named `house_*` to be enterable.
- Shared textures (village_tex/ and `kingdom/assets/art/**`) are referenced by relative URI, never embedded.
- Hanging/sagging props (banners, bunting) need `k.polish = False` — the polish pass treats z=0 as the floor.
- Humans: `make_humans.py` recipes on the shared 65-bone UAL skeleton (`ual_rig.py`). Never change bone names/rest pose;
  `--only` with new names and `--no-atlas` leaves existing variants byte-identical. Looks are mapped in `Assets.MH_LOOKS`.
- Budgets from `ashes-asset-pipeline` (house 20k/6k, prop 4k, NPC 8k, player 15k, textures ≤ 1024).

## Delegating to cheaper agents (Sonnet)
Opus plans, reviews previews, places assets in Godot and commits; Sonnet agents build. Every brief must say:
never run git; don't edit .gd/.tscn (report hook lines instead); only touch named files; never regenerate existing
variants they weren't asked to; read their own previews; give a final report with dimensions, tris, facing, door points.
Run at most ~3 in parallel on disjoint files. After an agent: check `git status` for files it shouldn't have touched
(restore with `git checkout -- <file>`), import, render the in-game shot (`ashes-visual-qa`), then commit.
