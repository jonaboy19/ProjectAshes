# Refined props (2026-10-28)

GLBs are in `kingdom/assets/props_refined/<name>/<name>.glb`. Each folder has a `LICENSE.txt`, and Godot extracts the textures into the same folder on import. **Nothing has been placed in any scene yet**: the towns worker does placement.

- Contact sheet: `sheet.jpg`. Task A is shown as Meshy original | refined pairs from the same camera, and Task B is the procedural builds. The renders use Eevee, the `kloofendal_overcast_puresky_4k` HDRI plus a soft sun, and a gameplay 3/4 camera.
- Pipeline and how to rerun: `.claude/skills/ashes-blender-refine/SKILL.md`. The code is in `tools/blender/props/refine_lib.py`, `refine_meshy.py`, `build_village_props.py` and `make_sheet.py`.

All props use one material each: albedo + ORM (AO/rough/metal) + an OpenGL normal map, embedded as JPEG. The trough also has a small untextured water material. The origin is at the feet (footprint centre, z = 0). The tavern sign is the exception: its origin is at the wall mount, at the top of the wall plate, and the board hangs about 0.83 m below it. Scale is real metres. There are no LOD GLBs: Godot generates LODs on import (`generate_lods=true`, the default `.import`).

## Verdicts (asset-level gate vs refs 06/17/20; 11/16 negative)
These are asset-level checks. The final AAA sign-off still needs each prop in-game, in context and at gameplay distance once it is placed.

| name | source | tris | texture | size (m) | before | after | verdict |
|---|---|---|---|---|---|---|---|
| cart | Meshy, re-materialed | 10.0k | 1K | 2.20 × 1.33 × 1.43 | painted grey wood, beige plastic-looking sacks | scanned weathered grey oak (grain, edge wear, mud at the wheels); sacks keep Meshy's folds with burlap weave, dulled | PASS |
| well | Meshy, re-materialed | 12.2k | 2K | 2.24 × 2.25 × 2.30 | orange-tan toy shingles and clean beige stone | grey weathered shingles, oak posts, fieldstone ring with moss and grime in the joints | PASS (the bucket came out almost all dark iron; it should be oak staves with iron hoops) |
| crate_stack | Meshy, re-materialed | 5.5k | 1K | 1.21 × 0.86 × 1.20 | pale, clean, AI-smeared planks | used brown oak with grain and dark joints | PASS |
| trestle_table | Meshy, re-materialed | 4.9k | 1K | 1.64 × 1.36 × 0.78 (table + 2 benches) | glossy, varnished baked sheen | matte dark oak with grain and worn edges | PASS |
| hearth | Meshy, re-materialed | 10.1k | 1K | 1.78 × 1.35 × 2.00 | white-grey cartoon stones, copper cauldron, brown blob hood | sooty fieldstone, black iron cauldron, timber mantel | **FAIL (geometry)**: Meshy's "hood" is a boulder-shaped lump on the mantel, and it reads as a rock whatever its material. Remodel the hood in Blender (a tapered plastered smoke hood) or cut it off and use the hearth under a separate chimney breast. |
| market_stall | Meshy, re-materialed | 14.0k | 2K | 3.03 × 2.40 × 2.30 | saturated ochre canvas, flat grey frame | weathered grey timber frame, canvas with weave and grime, produce kept (desaturated) | PASS (borderline): the produce is still Meshy's soft AI painting, though it's fine at street distance |
| belt_pouch | Meshy, re-materialed | 1.7k | 1K | 0.20 × 0.07 × 0.17 | good stitched leather (Meshy) | the same albedo with leather grain, slight edge wear and less plastic shine | PASS (a small gain; Meshy was already good) |
| bench_hewn | procedural | 1.2k | 1K | 1.80 × 0.43 × 0.47 (seat 0.45) | – (Meshy v1/v2 rejected) | split-log seat with bark underside, 4 splayed wedged legs | PASS (borderline): the top is flat and clean, with no adze facets |
| trough_granite | procedural | 9.0k | 1K | 2.01 × 0.71 × 0.61 | – (Meshy rejected) | carved block with a tapered basin, chipped corners, moss in the low areas, water plane | **FAIL (borderline)**: the rock_face scan reads as streaky concrete, and the voxel-remeshed edges are too soft and even. It needs a coarser granite scan (download one) and sharper tooled arrises. |
| tavern_sign | procedural | 3.1k | 1K | 1.09 × 0.06 × 0.91 | – (Meshy garbled text, broken bracket) | wrought-iron wall plate, arm and two scrolls; chains from hooks on the arm to eye bolts in the board top; dark oak board with a hand-painted burgundy field, gold border and foaming tankard (both faces), paint chipped along the grain | PASS |
| barrel_rack | procedural | 10.1k | 1K | 1.99 × 0.86 × 0.86 | – (Meshy fused/floating) | 3 oak barrels (18 gapped staves, recessed heads, 4 proud iron hoops) on a hewn cradle rack with chocks | PASS |
| fence_wattle | procedural | 8.2k | 1K | 2.06 × 0.13 × 1.10 | – | 7 axe-cut stakes, 25 hazel weavers alternating front and back | **FAIL (borderline)**: too open and regular. It reads as a lattice rather than dense wattle (ref 12/14 Bellwright). It needs thicker, touching weavers with random thickness and longer overruns, and it is slightly over the small-prop tri budget. |
| fence_post_rail | procedural | 0.5k | 1K | 2.80 × 0.13 × 1.25 (posts 2.4 m apart) | – | 2 hewn posts with pyramid tops, 2 sagging split rails through mortises | PASS (the rails are a bit pale) |
| haystack | procedural | 1.9k | 1K | 2.26 × 2.33 × 2.85 | – | a rick around a centre pole, scanned straw (thatch_roof_angled), lumpy profile with a skirt | PASS (borderline): the silhouette is too smooth. Real ricks have loose straw tufts, which would need alpha cards. The ropes were dropped because they floated on the lumpy surface. |
| hay_bundle | procedural | 1.0k | 1K | 0.85 × 0.44 × 0.42 | – | a straw truss pinched by two straw-rope bands (a period-correct "bale"; rectangular baler bales are anachronistic) | PASS |
| firewood_stack | procedural | 3.2k | 1K | 1.66 × 0.51 × 1.06 | – | ~110 split billets (bark, split faces, end grain) between end stakes on sleepers | PASS |

## What still fails / open issues
1. **hearth**: the hood geometry is wrong (see the table).
2. **trough_granite**: the material reads as concrete and the edges are too soft.
3. **fence_wattle**: the weave is too sparse.
4. **No real-scan iron, fabric, leather or granite on disk.** Iron, burlap and leather are procedural or Meshy-albedo based, and granite is the `rock_face` scan desaturated. Downloading Poly Haven CC0 sets (`rusty_metal_02`, a burlap or fabric set, a `leather_*` set, a granite rock) needs the owner's OK. The scripts pick them up by name through `refine_lib.LIB`.
5. **End-grain rings** (the firewood and bench ends) are subtle at 1K. **Barrel heads** look a little dark.
6. **DeepBump** (normal maps from Meshy albedo) was not used: its venv has no numpy or onnxruntime installed.
7. **Not yet checked in-game.** Normal-map handedness and ORM read fine in Blender re-imports, but check them in Godot when placing the props.
