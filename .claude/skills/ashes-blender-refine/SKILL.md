---
name: ashes-blender-refine
description: Refine props to the Rising Ashes AAA bar in headless Blender 5.2 - re-material Meshy GLBs with real-scan CC0 Poly Haven materials (clean, real-world scale, origin at the feet, decimate to budget, per-part material from the Meshy colours, one baked 1K/2K texture set with edge wear, cavity grime, ground mud and colour variation), or build a prop procedurally at exact real dimensions with the same bake. Includes budgets and the render gate (side-by-side and contact sheet against refs 06/17/20). Use for any prop that comes out of Meshy looking AI-painted or toy-like, any prop Meshy can't make, and before placing new props in towns.
---

> **Mandatory for every task (owner rules, 2026-10-28):** (1) `ashes-best-tool-first` — use every fitting Godot built-in, installed addon, external tool (Blender, ffmpeg, Meshy, Mixamo, Poly Haven/ambientCG CC0) and cloud offload instead of hand-rolling; (2) `ashes-aaa-gate` — nothing is done or sent until it passes the AAA gate against `docs/plans/ref_aaa/`. The game is **PC-only** (min-spec: regular PC, possibly integrated GPU); ignore any mobile/phone wording below.

# Blender prop refine (Meshy re-material and procedural builds)

Code: `tools/blender/props/refine_lib.py` (shared: material library, weathering stack, bake, export, gate render),
`refine_meshy.py` (Task A, Meshy in), `build_village_props.py` (Task B, procedural). Output goes to
`kingdom/assets/props_refined/<name>/<name>.glb` with a `LICENSE.txt`. The last run's results are in `docs/plans/props_refined/README.md` and `sheet.jpg`.

## Running it
- Always use `tools/external/blender.sh <script> -- [names] [--work DIR]` through the Bash tool (Git Bash). Run **one Blender at a time**: the laptop has 16 GB and Godot workers run beside it.
- Blender can't open script paths longer than about 260 characters, so keep work files in `C:\Users\Jonna\Tools\_scratch\refine` (the default `--work`), not in the Claude scratchpad.
- Bakes run on **Cycles CPU**, because the RTX 4070's 8 GB is usually full of Godot. A 1K set (5 passes) takes about 1 min per prop, and 2K takes about 3 min.
- `refine_meshy.py -- <name> --debug` renders only the per-face material classification (flat colours) to `gate/<name>_classes.jpg`. Check it before baking.
- Temporary bake PNGs are deleted after export. The gate JPGs are about 60 KB each. Disk is tight (about 10 GB free), so don't keep extra renders.

## Task A: re-material a Meshy prop (`refine_meshy.py`)
1. Import the GLB, join the meshes, and rename the Meshy UV layer to `meshy_uv`. Keep Meshy's base-colour image: it is used for classification and detail transfer.
2. **Clean**: merge by distance (0.04 % of the diagonal), dissolve degenerate faces, drop tiny loose islands (fewer than 24 faces and under 1.5 % of the size), delete loose edges and verts, and recalculate normals.
3. **Scale** to the real size with `RULES[name]["size"]` (`longest`, `height` or `base_width`), and put the origin at the centre of the footprint at z = 0. Check the result against human scale: doors are 2.1 m, people 1.75 m, seats 0.45 m and tables 0.76–0.78 m.
4. **Decimate** (collapse) only when the mesh is over budget.
5. **Classify** each face from Meshy's painted colour (HSV, median of the centroid and corner samples) plus its relative height and radius, using a per-prop rule function. Then run two passes of neighbour-majority smoothing. Don't use island voting: Meshy meshes are fused into one or two shells, so voting erases small parts.
6. **Materials** come from `refine_lib.LIB`. Scan materials are box-projected in object space at real tile size and get bump from the scan's AO plus luminance. Tangent-space scan normals are wrong under box projection, so don't use them. Meshy's greyscale albedo is **overlaid** at `detail` (0.5, or 0.75 for stone) so the plank lines and stone joints Meshy painted stay readable. Parts with no CC0 scan on disk (iron, burlap, canvas, leather, produce) keep Meshy's albedo (`meshy*` classes, desaturated) or use a procedural base, plus a weave, grain or rust breakup.
7. Then UV, bake and export (shared steps below), and render the original and the refined prop from the same camera.

## Buildings and heavy Meshy meshes (`refine_buildings.py`)
- The source is `ProjectAshes_art_staging/meshy_keep/<cat>/` (the codes are in `CATALOG.md`). Run `-- <codes> --preview` first: it renders the scaled original next to a **1.75 m figure** so you can check scale (doors 2–2.5 m, a gate passage ≥ 3.5 m, a nave about 8 m) and pick between variants.
- **Weld before decimating** (`refine_meshy.weld`). glTF import splits vertices at every UV seam, so a 1M+ Meshy mesh is mostly loose triangles, and the collapse decimator turns it into shards. The tavern went from shattered to clean with this alone.
- If the collapse decimator still stalls on fragment soup (cluttered props above about 2M tris), pre-simplify with **gltfpack** `-noq -si 0.006 -sa` and put the result in `<work>/simpl/<code>.glb` (`SIMPL` in the script). If the result melts or shatters at budget, **drop the asset**: that happened to the campfire and the tent.
- When the source is more than 1.3 × the budget, a copy of the original is kept as the high-poly. `bake_asset(high=...)` bakes it onto the low mesh (selected-to-active, cage extrusion and ray distance at 0.4 % and 1.2 % of the diagonal) and whiteout-blends that with the material normal.
- The `rules()` classifier works in this order:
  1. ivy and plants keep Meshy's paint;
  2. sloped faces high on the building (`nz` 0.3–0.97, z > `roof_z`) become the roof class;
  3. lit windows (vertical faces) keep Meshy's paint;
  4. a base slab;
  5. dark faces become the `dark` class, and dark board walls the `dark_walls` class;
  6. red becomes brick;
  7. light, low-saturation faces become plaster;
  8. brown faces with saturation above `timber_s` become timber;
  9. everything else becomes stone.

  Tune `timber_s` per building: brown stone and brick get misread as timber at 0.22, and a gate door is lost at 0.45.
- Building scans in `LIB` (`b_*`) use real tile sizes (2.2–3 m) and Meshy detail overlay at 0.35, so Meshy's painted joints and the scan's joints don't double up.

## Task B: procedural build (`build_village_props.py`)
- Every asset is a function that returns a `Part` (bmesh with per-face material classes and an `aux` UV). It is built in metres with +Z up, from the real dimensions in its docstring.
- Building blocks: `Part.loft` (rings to quads, with caps), `tube` (a polyline with a radius function, a profile and noise roughness; caps get ring-centred `aux` UVs for end grain), and `box` (a chamfered section with jitter).
- Real-world detail that sells it:
  - split timber has a flat split face plus bark on the outer arc;
  - end grain gets rings (the `endgrain` class reads `aux` as cross-section metres around the pith);
  - wedged through-tenons;
  - chain links alternate 90°;
  - staves have gaps, hoops stand proud, and heads sit in the croze;
  - wattle weavers alternate in front of and behind the stakes;
  - stone is voxel-remeshed (14 mm) with layered noise displacement and chipped corners, then decimated.
- Painted emblems are drawn into an RGBA image with numpy (`make_paint`) and mixed in on the `aux` UV. The paint is chipped by noise and sits on the raised grain. Don't use lettering (it garbles at 1K).
- Hewn stone (`trough_granite`): use an exact boolean for the basin and booleans with low-poly icospheres to chip the arrises, then a 7 mm angle-limited bevel, then subdivide the long edges and add a 2 mm wobble. Chisel tool marks are in the material (`tooled`: a sawtooth wave plus pits in the height, so they bake into the normal map), and the granite colour is procedural (`granite`). Don't voxel-remesh hewn stone: it melts the edges.
- Dense weaves (`fence_wattle`): rods of 9–15 mm radius, 4-sided tubes with 16 rings, each course stacked 0.95 × its diameter above the last so the rods overlap with no see-through gaps. They alternate in front of and behind the stakes by course, with random radius, taper and overrun. About 36 courses come to 5k tris.
- Replacing bad Meshy parts (`refine_meshy.replace_hood`): delete the faces of one class with bmesh, measure what's left (here the mantel shelf), and loft a chamfered replacement in place (here a plaster hood and flue up to a 3.0 m ceiling). It gets its own class (`plaster_hood`: lime plaster with a streaked `soot` band over a Z range) and a dummy `meshy_uv` so the join keeps the UV layers.
- Avoid anachronisms: no rectangular baler hay bales (use a rick or a bound truss), no modern saws or hardware.

## Shared: UV, bake, export (`refine_lib`)
- `smart_uv` makes a new `bake_uv` (66° for Meshy, 60° for builds) and packs the islands.
- `bake_asset` builds one set from every bakeable slot by rewiring each material's `OUT_albedo`, `OUT_rough`, `OUT_metal` and `OUT_ao` into an Emission node, baking EMIT, then baking the tangent NORMAL (OpenGL, as Godot expects):
  - **albedo** (sRGB, with a little AO multiplied in for the low tier, which has no SSAO);
  - **ORM** (R = AO softened to 0.35–1, G = roughness, B = metallic), wired to glTF through a `glTF Material Output` group;
  - **normal**.
- The weathering stack sits on every material:
  - **edge wear**: convex edges from Cycles AO *inside* over 2 cm × noise. Don't use the Bevel-vs-normal mask: it leaves triangle patches on scans.
  - **cavity grime**: AO over 24 cm × noise.
  - **ground mud**: the bottom 28 cm.
  - **colour variation**: low-frequency multiply.
  - **moss**: on stone, up-facing and in cavities.
- Unbaked slots (`water`) stay as their own tiny material. Join them after the bake (see the trough).
- `export_glb` keeps only `bake_uv`, embeds JPEG q88 and uses +Y up. Godot extracts the images and generates LODs and shadow meshes on import (the `.import` defaults are fine), so no LOD GLBs are written.
- Remove `bpy.data.node_groups` before re-importing a GLB in the same session: the importer breaks on our minimal `glTF Material Output` group.

## Budgets
| class | tris | texture |
|---|---|---|
| small hand / table prop | ≤ 5k | 1K (512 is fine under 0.3 m) |
| furniture, fences, stacks | ≤ 8k | 1K |
| big street props (cart, hearth, rack) | ≤ 15k | 1K |
| hero street props (well, market stall) | ≤ 15k | 2K |
| buildings (LOD0; Godot makes LODs) | ≤ 40k | 2K |
A whole prop gets one material, plus at most one unbaked slot (water or glass). Godot auto-LOD handles distance.

## Gate (mandatory, `ashes-aaa-gate`)
1. `render_view` gives a gameplay-like 3/4 view: about 22° down, a 50 mm lens, Eevee, the `kloofendal_overcast_puresky_4k` HDRI plus a soft sun, a dark neutral ground, and AgX. Render the **re-imported GLB** (what Godot gets), not the Blender scene.
2. Build the side-by-side (Meshy | refined) and the contact sheet with ffmpeg `hstack`/`vstack` and labels (`drawtext` needs `fontfile=C\\:/Windows/Fonts/arial.ttf`). **Look at it** next to refs 06, 17 and 20 (targets) and 11 and 16 (negatives).
3. Judge it as the harshest reviewer: wood reads as weathered timber, not plastic or paint; stone has joints and grime; metal is dark with rust; there are no AI smears or flat colours; the silhouette isn't toy-like; the scale is right. Fix and re-bake until it passes. Otherwise write the FAIL honestly in `docs/plans/props_refined/README.md`.
4. Final AAA sign-off still needs the asset in-game, in context, at gameplay distance. The towns worker does that when placing it.

## Blender extensions and AI tools (best-tool check, 2026-10-28)
The extensions are installed in `%APPDATA%\Blender Foundation\Blender\5.2\extensions\user_default\` (see `ashes-external-tools`). `tools/external/blender.sh` loads them through a directory junction, `C:\Users\Jonna\Tools\blender-ext-headless\user_default`, which points at that folder. Enable one in a script with `addon_utils.enable("bl_ext.user_default.<id>", default_set=True)`, because `--factory-startup` doesn't auto-enable anything.

**Never point a `--factory-startup` run straight at the `%APPDATA%` extensions folder.** With nothing enabled, Blender's wheel sync empties `%APPDATA%\...\extensions\.local\lib\python3.13\site-packages`, which deletes the GUI's cv2, PIL and m_tree. That happened once on 2026-10-28, and starting Blender normally once (`blender -b --python-expr pass`) restored it. The junction gives headless runs their own `.local` beside it, so the GUI install is never touched.

| Tool | Use here | Verdict for this pipeline |
|---|---|---|
| `thebetterbaker`, `paws_bakery`, `bake_to_single_material` | multi-material → one PBR set | Good for one-off bakes in the GUI. `refine_lib.bake_asset` already does multi-slot → one albedo/ORM/normal set headless, with the weathering stack wired into the emission passes, so keep it for batch work. If you need more passes (curvature, thickness, ID), these add-ons are the fallback. |
| `lod_gen`, `lodify_optimizer` | LOD meshes | Only when a prop needs hand-tuned LOD GLBs. By default Godot generates LODs on import (`meshes/generate_lods=true`), which is the better runtime tool. |
| `texel_density_checker` | check px/m after `smart_uv` | Use it when a prop looks blurry next to its neighbours. Target 400–512 px/m for street props at 1K, about 1000 for hand props. |
| `ivygen`, `Bagapie` | ivy and moss on walls and wells (ref 20) | Ivy needs alpha-cut leaf cards, which breaks the one-opaque-set rule. Put ivy on **walls in the town scene** (the towns worker), not baked into props. Moss on props is done in the shader stack (`moss` in LIB). |
| `looptools`, `bool_tool` | modelling helpers | Plain `BOOLEAN` modifiers (EXACT) do the job headless, as in the trough basin. |
| DeepBump (`C:\Users\Jonna\Tools\deepbump`) | normal maps from Meshy's painted albedo (stitching, folds) for `meshy*` classes | **Used.** Shrink the Meshy `base_color.png` to 1K, then run `PYTHONIOENCODING=utf-8 C:\Users\Jonna\Tools\deepbump\venv\Scripts\python.exe cli.py in.png <work>\deepbump\<name>_nrm.png color_to_normals` from `DeepBump-8` (about 7 s each). `refine_meshy.py` picks up `<work>/deepbump/<name>_nrm.png` automatically (`RL.MESHY_NRM`), and a Normal Map node on `meshy_uv` feeds it under the micro bump. |

## Known gaps
No real-scan iron, fabric, leather or hay-twine is on disk. Downloading Poly Haven `rusty_metal_02`, `fabric_pattern_07`/burlap-like and `leather_*` sets (CC0, needs owner OK to download) would replace the procedural bases in `LIB`.
