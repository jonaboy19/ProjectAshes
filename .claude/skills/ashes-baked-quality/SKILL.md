---
name: ashes-baked-quality
description: Recipe for making Rising Ashes look richer on LOW/phones while getting cheaper - offline-baked vertex AO + painterly warm/cool light for town buildings (BakedVao), how to (re)bake, how it reaches materials, how to measure before/after against the gate-market target. Use when touching town building looks, LOW-tier richness, lightmaps/AO, atlases, HLOD/impostors or "LOW looks flat".
---

# Baked quality (mobile looks come from baking, not runtime power)

## Shipped (2026-10-06, phase 1)
- `kingdom/scripts/world/baked_vao.gd` (BakedVao): per-vertex AO (voxel hemisphere rays, `style_g_vao.gd`) baked OFFLINE,
  stored as 1 byte/vertex zstd blobs in `kingdom/assets/baked/vao/<key>[_lodN].res` (199 meshes, 1.4 MB).
- At load `Assets._transformed(..., key)` -> `BakedVao.apply` writes COLOR: rgb = cool (occluded) -> warm (open/up-facing)
  painterly ramp x grime band at wall feet x AO (sRGB-encoded); a = AO. Then `BakedVao.fix_materials` gives baked surfaces a
  cached material duplicate that multiplies COLOR (polished: use_vertex_color, vao_strength 0; Standard: vertex_color_use_as_albedo).
  Town-identity instance tints still work (instance colour multiplies COLOR).
- Zero per-frame cost, works on every tier, including LOW where sun shadows are off.
- Missing/stale blob (vertex count changed) = mesh unchanged; never computed at runtime.

## Re-bake (after any building GLB changes)
`godot --headless --path kingdom -s res://tools_qa/baked_quality/bake_town_vao.gd [-- --only=house_1,wall]` (~50 s for all).
Skips roles goods/tree/ivy/banner/flag (goods use COLOR.a for hue variation).

## Measure (gate market = bench "city")
`bench.gd -- --quality=low|high --scene=city --png=... --csv=docs/art/baked_quality/bench_*.jsonl` on the Mobile renderer, absolute paths.
PLUG THE LAPTOP IN: on battery (2026-10-06, 18 %) the game ran ~5-8 fps and fps numbers are meaningless; compare draws/prims/VRAM.
NPC/stall streaming differs run to run, so draw deltas under ~10 % are noise; compare with `cmp_<tier>.png` side by side.

## Fresh worktree gotchas
- Hardlink `.godot/imported|exported` from a worktree at the same commit, copy the rest, then `--headless --import`.
- Copy git-ignored `*_lod_bake.jpg` etc. from the main checkout (`git ls-files --others --ignored --exclude-standard kingdom/assets`), or Meshy GLBs fail to load.

## Next (not done yet, in priority order)
1. fix_materials duplicates break material sharing: merge per role so HIGH draws do not rise (check `--drawcensus`).
2. Bake gatehouse/walls (built procedurally in settlement_builder `_wall_ring`/`_medieval_gates`, not BUILDINGS keys).
3. Per-district atlas + static merge of props (MultiMesh cells already exist; target <=150 draws LOW).
4. Painted grime/edge-highlight into building atlases (Material Maker), ETC2/ASTC 1k atlases.
5. Skyline HLOD via kingdom/tools/impostors/ + fog gradient.

## Phase 2 (2026-10-06)
- `scripts/world/town_atlas.gd` + `tools_qa/baked_quality/bake_town_atlas.gd`: far stages (LOD2/3, 256 px LOD1) share one 2048 page
  (`assets/baked/atlas/`), UVs moved at load in `Assets.building_mesh`. Re-bake + `--import` after texture changes. NO_TOWN_ATLAS=1 disables.
- `scripts/world/static_merge.gd`: LOW only, merges atlas stages per 40 m cell (time-sliced from SettlementBuilder). LOW 172 -> 131 draws. NO_STATIC_MERGE=1 disables.
- Surface collapse runs on HIGH too; HIGH shadow_min 2.5 / dist 60 (shadow passes were ~290 of 700 draws).
- Bench flags: `--noshadow`, `--hidetown` (floor), `--drawcensus --census_n=300 --matcensus`.
- Lessons: merging plain props or merging on HIGH is not worth it; the 557->701 jump was noise, not material copies. Bench segfaults at exit are harmless.
- Still open: gatehouse/walls, haze + skyline impostors, HIGH <300 needs merged near stages (needs a near atlas and a cheaper merge).
