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
| hearth | Meshy base + Blender hood | 10.5k | 1K | 1.78 × 1.35 × 3.00 (the flue meets a 3.0 m ceiling) | white-grey cartoon stones, copper cauldron, brown boulder-shaped hood | sooty fieldstone, black iron cauldron, timber mantel. Meshy's hood is deleted and replaced by a modelled lime-plastered smoke hood (moulded lip) and flue against the back wall, sooted at the mouth. | PASS (borderline): the plaster scan is a bit blotchy, more like render than limewash |
| market_stall | Meshy, re-materialed | 14.0k | 2K | 3.03 × 2.40 × 2.30 | saturated ochre canvas, flat grey frame | weathered grey timber frame, faded ochre-linen canvas (-35 % saturation, hue nudged to yellow), produce kept with DeepBump normals | PASS (borderline): the produce is still Meshy's soft AI painting, though it's fine at street distance |
| belt_pouch | Meshy, re-materialed | 1.7k | 1K | 0.20 × 0.07 × 0.17 | good stitched leather (Meshy) | the same albedo with leather grain, slight edge wear and less plastic shine (DeepBump tried: it doubled Meshy's painted facets into a crumpled look, so it is off for the pouch) | PASS (a small gain; Meshy was already good) |
| bench_hewn | procedural | 1.2k | 1K | 1.80 × 0.43 × 0.47 (seat 0.45) | – (Meshy v1/v2 rejected) | split-log seat with bark underside, 4 splayed wedged legs | PASS (borderline): the top is flat and clean, with no adze facets |
| trough_granite | procedural | 2.0k | 1K | 2.00 × 0.70 × 0.60 | – (Meshy rejected) | hewn grey granite: exact-boolean tapered basin, crisp 7 mm arrises, boolean chips, chisel tooling and mica/feldspar speckle baked in, rain streaks, moss on the rim, water plane | PASS (borderline): the long faces show slightly regular vertical streaking (tooling + drip noise); a real granite scan would beat the procedural colour |
| tavern_sign | procedural | 3.1k | 1K | 1.09 × 0.06 × 0.91 | – (Meshy garbled text, broken bracket) | wrought-iron wall plate, arm and two scrolls; chains from hooks on the arm to eye bolts in the board top; dark oak board with a hand-painted burgundy field, gold border and foaming tankard (both faces), paint chipped along the grain | PASS |
| barrel_rack | procedural | 10.1k | 1K | 1.99 × 0.86 × 0.86 | – (Meshy fused/floating) | 3 oak barrels (18 gapped staves, recessed heads, 4 proud iron hoops) on a hewn cradle rack with chocks | PASS |
| fence_wattle | procedural | 4.6k | 1K | 2.11 × 0.10 × 1.13 | – | 7 axe-cut stakes, 42 courses of thin irregular hazel rods (9–15 mm, tapered, random overruns) woven in and out and packed so nothing shows through at 3 m | PASS |
| fence_post_rail | procedural | 0.5k | 1K | 2.80 × 0.13 × 1.25 (posts 2.4 m apart) | – | 2 hewn posts with pyramid tops, 2 sagging split rails through mortises | PASS (the rails are a bit pale) |
| haystack | procedural | 1.9k | 1K | 2.26 × 2.33 × 2.85 | – | a rick around a centre pole, scanned straw (thatch_roof_angled), lumpy profile with a skirt | PASS (borderline): the silhouette is too smooth. Real ricks have loose straw tufts, which would need alpha cards. The ropes were dropped because they floated on the lumpy surface. |
| hay_bundle | procedural | 1.0k | 1K | 0.85 × 0.44 × 0.42 | – | a straw truss pinched by two straw-rope bands (a period-correct "bale"; rectangular baler bales are anachronistic) | PASS |
| firewood_stack | procedural | 3.2k | 1K | 1.66 × 0.51 × 1.06 | – | ~110 split billets (bark, split faces, end grain) between end stakes on sleepers | PASS |

## What still fails / open issues
The three FAILs (hearth, trough, wattle) were fixed on 2026-10-28 in round 2. Remaining issues:
1. **Downloads not done.** The coordinator asked for 1K Poly Haven rock/granite, iron, burlap, canvas and leather sets. I did not download them: a download needs the owner's own OK, and an agent's approval doesn't count under the session rules. Granite, iron, burlap, canvas and leather therefore stay procedural or Meshy-albedo based. Once the owner approves, put the sets under `kingdom/assets/cc0/textures/<id>/` and point `refine_lib.LIB` at them by name.
2. **trough_granite**: the slightly regular vertical streaking on the long faces.
3. **hearth**: the hood plaster is a little blotchy.
4. **haystack**: a smooth silhouette with no straw cards.
5. **market_stall**: Meshy's soft produce.
6. **End-grain rings** are subtle at 1K, and the barrel heads are a bit dark.
7. **DeepBump** normals are on the cart, market_stall and trestle_table Meshy parts. They are off on the pouch, where they made it worse.
8. **Not yet checked in-game**: the towns worker re-gates each prop in context after placing it.

# Buildings batch (2026-10-28, revised), `kingdom/assets/props_refined/buildings/<name>/`
Sheet: `buildings_sheet.jpg` (Meshy original | refined, same camera; the red cylinder is a 1.75 m figure). Code: `tools/blender/props/refine_buildings.py`.

Pipeline:
- Import the old Meshy building from `ProjectAshes_art_staging/meshy_keep` and scale it to real size.
- **Weld**: glTF splits every UV seam, so million-tri Meshy meshes are mostly loose triangles.
- Collapse-decimate to ≤ 40k. The detail that removes is baked back from the original as a high→low normal map (whiteout blend).
- The per-face classifier assigns: roof by slope; stone plinth; chimneys; ivy and lit windows keep Meshy's paint.
- One 2K albedo/ORM/normal set. Godot generates LODs on import.

Round-2 changes (coordinator review):
- **Value contrast restored on the half-timbered houses (B43, B44, B52, B53, B60)**:
  - The walls use a per-pixel `b_frame` material. Meshy's painted framing (luminance, linear 0.12–0.22) decides **off-white limewash vs dark weathered oak**, because decimated faces are far too coarse to carry the frame pattern.
  - Dirt now sits only in the bottom 0.9 m, in eave AO and in rain streaks, not all over.
- **Roof courses follow the slope**: roof scans use a projection with u along the eave (the face azimuth snapped to 45°, so a whole roof plane shares one direction) and v along the height, instead of box projection.
- **B07**: stepped buttresses with weathered tops (3 per long wall between the windows, plus corner pairs), a stone bell-cote with an arched opening and a bell on the west gable, and darker slate.
- **B16 dropped** (it reads Victorian). The campfire (P99) and tent (P112) stay dropped.

Variant picks:
- Gate: **B10** (towers, passage about 4.5 m wide and 5.5 m high), over B26 and B04.
- Tower: **B42**, over B15 (a squat 9 × 6 m octagon).

Verdicts are against refs 05/08/18 (street composition) and 20 (real stone lane); 11 and 16 are the negatives.

| code / name | tris | tex | size (m) | after | still reads stylised | verdict |
|---|---|---|---|---|---|---|
| B07 church_parish_grim | 10.4k | 2K | 11.3 × 8.2 × 10.1 (nave 8 m, bell-cote to 10.1 m) | grey slate-stone, dark slate, buttresses, bell-cote | the window reveals are shallow; the bell-cote is plain (no gable cross) | PASS (borderline) |
| B28 chapel_stone_small | 23.0k | 2K | 5.8 × 10.0 × 8.4 | rubble stone, slate, moss and grime | the bell-cote is a little soft | PASS |
| B10 castle_gate_towers | 39.2k | 2K | 16.0 × 4.6 × 9.7 | grey ashlar, timber gates with iron | soft, rounded merlons (Meshy); no portcullis | PASS (borderline) |
| B42 tower_square | 6.1k | 2K | 8.9 × 8.6 × 12.0 | rubble stone, timber door | bulging, tapered silhouette | PASS (borderline) |
| B43 house_two_storey_dormer | 39.2k | 2K | 7.5 × 9.6 × 10.0 | limewash and timber walls, shingle | the gable reads as stone, and the balcony is mushy after decimation | PASS (borderline) |
| B44 house_tall_timber | 39.2k | 2K | 4.8 × 6.3 × 12.0 | crisp limewash and dark oak frame, weathered tile | – | PASS |
| B14 blacksmith_thatch | 39.2k | 2K | 8.2 × 7.1 × 7.5 | scanned thatch, rubble, timber | the thatch roll is bulbous; the walls are still a bit grey (the old classifier) | PASS (borderline) |
| B52 house_tudor_stone_base | 21.4k | 2K | 10.9 × 9.7 × 9.0 | limewash and oak upper storey on a rubble ground floor | the shingle roof reads noisy, close to thatch | PASS (borderline) |
| B53 house_tudor_corner | 23.0k | 2K | 10.9 × 11.6 × 9.0 | as B52 | as B52; the roofscape is busy | PASS (borderline) |
| B54 row_half_timbered | 38.7k | 2K | 20.0 × 9.0 × 12.0 | brown tile, timber frame, plaster, ivy kept | – (closest to ref 08/18) | PASS |
| B70 tavern_dark_roof | 38.6k | 2K | 11.3 × 10.2 × 10.0 | dark board walls, slate, lit windows, sign | the slate is lighter than the original's near-black | PASS |
| B60 cottage_thatch | 39.0k | 2K | 5.2 × 5.3 × 6.5 | limewash and dark frame, thatch | small light flecks on the thatch | PASS |
| B16 church_brick_spire | – | – | – | **DROPPED** (Victorian) | – | DROPPED |
| P99 campfire_cooking / P112 tent_canvas_shop | – | – | – | **DROPPED** (melt or shatter at budget, even via gltfpack) | – | DROPPED |

Open issues:
- **No Poly Haven downloads.** The download request was relayed by the coordinator, and my session rules accept a download approval only from the owner directly in chat, not relayed by an agent. Everything uses scans already on disk: rough_plaster_03 (limewash), rough_wood (oak), stone_wall_04, old_stone_wall, rustic_stone_wall, castle_wall_slates, roof_slates_02, clay_roof_tiles, thatch_roof_angled, old_planks_02 and castle_brick_07. To use new sets, put them in `kingdom/assets/cc0/textures/<id>/`, log them in `docs/plans/DOWNLOADS.md`, and change `tex=` in `refine_buildings.LIB`.
- **Not checked in-game or in the street yet** (towns worker).
- **Windows and doors are Meshy geometry**: no real reveals or glass.
