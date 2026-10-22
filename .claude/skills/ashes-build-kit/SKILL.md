---
name: ashes-build-kit
description: The Rising Ashes modular build kit and Palworld-style build mode - grid, sockets, support, costs/tiers, plans built by construction crews, renderer, save format, and how to add a piece. Use before touching data/build_kit, scripts/realm/build_kit.gd, scripts/build/*, or assets/incoming/build_kit.
---

# Build kit

Files: `kingdom/data/build_kit/pieces.json` (catalogue, roads, blueprints) - `scripts/realm/build_kit.gd` (realm module "build_kit": grids, snap, support, plans, roads, save) - `scripts/build/kit_meshes.gd` (meshes + shared kit materials) - `scripts/build/build_renderer.gd` (MultiMesh per kind/look) - `scripts/build/build_mode.gd` (touch UI) - `scripts/build/road_tool.gd` - lab `tools_qa/build_lab/build_lab.tscn` - tests `tests/test_build_kit.gd`. Art: `assets/incoming/build_kit/<id>_lod0.glb` (+ `_lod1`), scripts `tools/blender/build_kit/`, sheets `docs/art/build_kit/`.

## Grid
- Cell 2 m. Cell (i,k) centre (2i, 2k). Storey 3 m; floor of storey L at y = 0.5 + 3L (foundation top 0.5; foundation spans y -0.5..0.5).
- Edges: `ex(i,k)` along X at (2i, 2k+1) (rot 0/2); `ez(i,k)` along Z at (2i+1, 2k) (rot 1/3). Rot parity picks the edge type.
- Free props: 0.5 m, 15 degree steps (rot < 24 = steps, else degrees).
- Model conventions: walls 2 m along X, 3 m tall, 0.24 thick, origin bottom centre. Roof slope: eave at local +z (y 0), ridge at -z (y 2), 45 deg. Ridge cap: an EDGE piece on the ridge line, cap at y 2. Gable: right triangle, high side at local x = -1 (rot 1 = high toward +z). Stairs 2x4 m rising toward -z by 3 m.
- Settlement grid: origin snapped to 2 m at founding; radius 64 m; max 3 grids (OWNER_DECISIONS). Caps LOW 1400 / HIGH 2200 pieces.

## Sockets and support
Occupancy keys `slot:i:k:L:layer` (layers foundation, wall, floor, roof, ridge, gable, door, pillar, stairs, fence, ground). Supporters (`_supporters`): wall <- foundation (L0) / wall below / floor at L; floor & roof <- walls of L-1 on its 4 edges, pillar below, same-layer neighbour (horizontal); gable <- wall below or roof; ridge <- roofs either side; door <- doorway wall. Integrity = max(supporter - loss): vertical 0.1 wood / 0.05 stone, horizontal 1/3 wood / 1/5 stone. <= 0: red ghost "Nothing holds it up"; on removal anything at 0 collapses (25% refund, removed piece 50%).

## Plans and crews
Pieces without materials (or Plan toggle) are plans. `hand_to_workers(gid)` turns loose plans into ONE construction site of hidden kind `kit_plan` (`construction.place_kit_plan`) with the summed bill and hours; the cloud's crews, hauling, stalls and stages raise it. Pieces appear bottom-up with site progress; `tick_hour` turns them into real pieces when the site is done (cancelled site -> loose plans again).

## Rendering and perf
One MultiMeshInstance3D per (kind x look) per settlement; plans draw with one translucent blueprint material. Blender pieces use LOD0 only (<= 700 tris; gltfpack LOD1 tore them) and NO visibility range (ranges on these MMIs culled everything in the lab); meshy_* pieces swap to LOD1 at 45 m (LOW) / 70 m. Lab: 234 pieces = 53 MMIs, 144 draw calls incl. shadows. One StaticBody3D per settlement with boxes per structural piece.

## Save
Per piece 16 B: u16 catalogue index, s16 x*4, s16 z*4, s16 y*10, u8 rot, u8 state, u8 hp, u8 slot|L<<2, u32 site. Base64 in the realm save. **pieces.json is append-only** (the index is the saved kind).

## Add a piece
1. Model it on the grid above in `tools/blender/build_kit/make_kit.py` (material slots named `kit_<plaster|timber|plank|log|stone|cobble|thatch|slate|shingle|iron|cloth|clay|dirt|hay|coal>`, cube UVs 1 m = 0.5 UV) or clean a Meshy model with `clean_meshy.py` (origin bottom centre, target height, textures <= 512, material names containing wood/stone/roof/cloth/iron), name it `meshy_<name>`.
2. LOD1 with `make_lods.sh` (gltfpack -noq) only matters for meshy pieces. Render the sheet (`render_sheet.py`) and LOOK at it.
3. APPEND an entry to `pieces.json`: id, name, cat, tier (0-4), know (optional build:carpentry|masonry|architecture), snap cell|edge|free, layer, fp, mat wood|stone|"", cost (construction materials + cloth), hours, hp; flags doorway, needs_doorway, ground_only, min_level, low, station, store, beds.
4. Import in Godot, run `tests/test_build_kit.gd`, run the lab (`--shots=<dir>`) and look at the frames.
