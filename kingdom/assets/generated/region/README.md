# Region 1 assets (first 8 x 8 km region)

Painterly, mobile-budget assets for the first region, built entirely by Blender scripts in this
repo. Everything is procedural (geometry and hand-painted-style textures), so no third-party pack
is reused and there is nothing to credit.

| set | folder | script | preview sheet |
|---|---|---|---|
| 1 Nature (trees, pines, dead/dark trees, bushes, grass, flowers, ferns, rocks, stumps, logs) | `nature/` | `tools/blender/make_region_nature.py` | `docs/kingdom/blender_previews/region_nature_sheet.png` |
| 2 Farm | `farm/` | `tools/blender/make_region_farm.py` | `region_farm_sheet.png` |
| 3 Mine | `mine/` | `tools/blender/make_region_mine.py` | `region_mine_sheet.png` |
| 4 Road and travel | `road/` | `tools/blender/make_region_road.py` | `region_road_sheet.png` |
| 5 Ruins and hidden places | `ruins/` | `tools/blender/make_region_ruins.py` | `region_ruins_sheet.png` |

Style check: `docs/kingdom/blender_previews/region_forest_scene.png` (new trees, bushes, grass,
rocks, stumps and logs around the Meshy `house_peasant_b` at its in-game 8 m height).
Per-asset renders: `docs/kingdom/blender_previews/region/`.

Every asset has `<name>.glb` (LOD0) and `<name>_lod1.glb`; the 10 trees also have `<name>_lod2.glb`
(two crossed impostor cards, 4 tris). Metres, origin at the base / ground centre, front faces
Godot +Z. No Draco or meshopt.

## Rebuild

From the repo root (Blender 5.2, headless; no system python needed):

    B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
    "$B" -b --factory-startup --python kingdom/tools/blender/make_region_nature.py -- all --textures --impostors --sheet --scene --godot
    "$B" -b --factory-startup --python kingdom/tools/blender/make_region_farm.py  -- all --sheet
    "$B" -b --factory-startup --python kingdom/tools/blender/make_region_mine.py  -- all --sheet
    "$B" -b --factory-startup --python kingdom/tools/blender/make_region_road.py  -- all --sheet
    "$B" -b --factory-startup --python kingdom/tools/blender/make_region_ruins.py -- all --sheet

Names instead of `all` rebuild single assets. `--textures` repaints every texture
(`region_paint.py`); `--impostors` re-renders `textures/tree_impostors.png` and the `_lod2` files.
Shared code: `region_paint.py` (texture painting), `region_kit.py` (mesh builder, materials,
export, previews), `region_struct.py` (building parts and the set runner).

## Textures (shared by every set, referenced by relative URI, never embedded)

| file | size | used by |
|---|---|---|
| `textures/foliage_atlas.png` | 1024, RGBA | all leaf/needle/grass/flower/fern/twig/moss cards (4 x 4 cells: oak x2, beech, dark forest, spruce, pine, bush, berry bush, grass, seed grass, warm flowers, cool flowers, fern, bare twigs, hanging moss, wheat) and the farm crops/ivy (`RG_Crop`) |
| `textures/bark_atlas.png` | 1024 | trunks, branches, logs, stumps, log posts: 4 columns (oak/beech bark, pine bark, dead silver bark, end-grain rings) |
| `textures/tree_impostors.png` | 1024, RGBA | tree `_lod2` impostor cards |
| `textures/rock.png`, `moss.png` | 512 tiled | rocks, cliffs, moss |
| `textures/planks.png`, `timber.png`, `stone_wall.png`, `plaster.png`, `thatch.png`, `shingle.png`, `slate.png`, `iron.png`, `canvas.png`, `hay.png`, `soil.png` | 512 tiled | structures |

The `.png.import` files set VRAM compression + mipmaps. Alpha cards use alpha **scissor**
(glTF `MASK`, cutoff 0.5), never blend.

## Materials and COLOR_0 (important)

All GLBs share materials by name. Two conventions, decided by the material:

* **Nature materials `RG_Foliage`, `RG_Bark`, `RG_Rock`, `RG_Moss` (set 1 only): COLOR_0 is WIND DATA.**
  * **R = sway weight** (0 = rigid: trunk base, rocks, grass roots; 1 = free: crown rim, blade tips).
    Trunks ramp from 0 at 25 % of the tree height; leaf cards are 0.35-1 by distance from the crown
    centre; grass/flowers/ferns are 0 at the ground to 1 at the tip.
  * **G = phase** 0..1 per leaf clump / branch / grass card, so clumps don't move in lock-step.
  * **B = baked ambient occlusion** (inner and lower cards darker, trunk base darker). Multiply it
    into albedo.
  * A = 1.
  * The `nature/*.glb.import` files already swap these materials for the ShaderMaterials in
    `nature/`: `rg_foliage.tres` (trees and bushes), `rg_foliage_ground.tres` (grass, flowers,
    ferns: gentler, faster wind), `rg_bark.tres`, `rg_rock.tres`, `rg_moss.tres`. Shaders:
    `region_foliage.gdshader` (alpha scissor, AO from COLOR.b, backlight, wind from COLOR.r/g, keeps
    the authored canopy normal on back faces) and `region_nature_opaque.gdshader` (same wind so
    branches move with their leaves). Tune `wind_direction / wind_strength / wind_speed` on the
    .tres files (keep foliage and bark equal). Verified in Godot 4.6 (isolated import + render).
  * Do **not** run these surfaces through `Assets._windy_leaves()` / `tree_wind.gdshader`: that
    shader multiplies COLOR into albedo and would tint the leaves red/black. The imported scenes
    already carry the right materials.
* **Every other `RG_*` material (sets 2-5): COLOR_0 = albedo tint** (sRGB authored, baked grime at
  the base). Godot's default glTF import multiplies it in (no override, no .tres needed).
  `RG_Crop` (wheat, cabbage leaves, ivy, weeds, shrine flowers) is an alpha-scissor card material
  with tint colours, no wind. `RG_Glow` is vertex colour + emission (lanterns, lit inn windows,
  embers, rune, goblin eyes).

Canopy normals: leaf cards carry custom normals pointing out of their clump/crown (glTF NORMAL),
which is what makes a crown shade as one soft painterly mass instead of flat planes.

## Integration notes

* **LOD**: trees LOD0 -> LOD1 at ~35-45 m, LOD1 -> `_lod2` impostor at ~90 m (visibility ranges
  like the Meshy buildings). Grass/flowers LOD1 is 1-3 cards (use it past ~15 m or just fade out).
* **Impostors** (`_lod2`) have lighting baked in the texture; `RG_Impostor` imports as a plain
  alpha-scissor StandardMaterial3D. Setting it unshaded (or low roughness influence) matches LOD1 best.
* **Windmill**: `farm/windmill.glb` has an empty `sail_hub`; place `farm/windmill_sails.glb` there
  and rotate it around its local Z (the sails face Godot +Z).
* **Checkpoint**: `road/checkpoint_barrier.glb` includes the boom at the empty `boom_pivot`;
  `road/checkpoint_boom.glb` is the same boom alone (origin = pivot, rotate around Z to raise) if
  the barrier should open: hide the built-in one or use the barrier without it.
* **Markers** (empties exported in the GLB): `farm/windmill: sail_hub`, `mine/miners_hut:
  chimney_top`, `mine/rail_curve: track_end`, `road/roadside_inn: chimney_top, door`,
  `road/wayshrine: interact`, `ruins/campfire: fire` (put fire VFX + an OmniLight here),
  `ruins/overgrown_shrine: altar`, `ruins/collapsed_tower: interior`, `ruins/goblin_totem_b: warning`.
* **Rails**: gauge 0.9 m. `rail_straight` runs 4 m along Godot -Z from the origin; `rail_curve` turns
  45 degrees on a 6 m radius; `rail_end` is a buffer stop. The mine entrance already has track
  leading out of the portal.
* **Modular fences**: `fence_rail` (3 m), `fence_picket` (2 m), `fence_gate`; tile along X.
* **Bridges** span along Godot Z: `bridge_stone` 12 m (deck 2.6 m high, 6 m arch),
  `bridge_wood` 14 m with ramps (deck 1.6 m).

## Licences

All geometry and textures are original procedural output of the scripts above (same licence as the
game code). No third-party asset pack was reused for this set, so no credit lines are needed.
(Quaternius Stylized Nature MegaKit, CC0, stays in `incoming/` and is what the game uses today;
these region assets are its painterly replacement.)

## Asset list

LOD0/LOD1 triangle counts are exact (from `<set>/_report.json`). Budgets: trees <= 3000 / 800,
grass <= 150 per clump, props <= 4000 / 1200, houses <= 20k / 6k. Everything is well inside.

### nature

| asset | LOD0 tris | LOD1 tris | size x/y/h (m) | materials | notes |
|---|---|---|---|---|---|
| `beech_a` | 1332 | 406 | 8.0 / 6.95 / 9.97 | Bark, Foliage | + `_lod2` impostor (4 tris) |
| `beech_b` | 1058 | 330 | 6.04 / 6.5 / 8.18 | Bark, Foliage | + `_lod2` impostor (4 tris) |
| `boulder_large` | 1280 | 80 | 2.24 / 1.46 / 1.75 | Rock, Moss |  |
| `bush_berry` | 316 | 84 | 2.06 / 1.81 / 1.37 | Bark, Foliage |  |
| `bush_dark` | 316 | 84 | 2.25 / 2.18 / 1.62 | Bark, Foliage |  |
| `bush_hazel` | 356 | 96 | 2.99 / 3.11 / 2.27 | Bark, Foliage |  |
| `bush_round` | 316 | 84 | 2.23 / 2.4 / 1.59 | Bark, Foliage |  |
| `dark_oak` | 727 | 379 | 7.98 / 7.04 / 7.41 | Bark, Foliage | + `_lod2` impostor (4 tris) |
| `dead_snag` | 894 | 380 | 8.54 / 6.83 / 8.31 | Bark, Foliage | + `_lod2` impostor (4 tris) |
| `fern_a` | 54 | 6 | 1.93 / 1.9 / 0.59 | Foliage |  |
| `fern_b` | 42 | 4 | 1.04 / 0.91 / 0.49 | Foliage |  |
| `flowers_cool` | 36 | 6 | 0.83 / 0.84 / 0.6 | Foliage |  |
| `flowers_warm` | 36 | 6 | 0.96 / 0.84 / 0.63 | Foliage |  |
| `grass_a` | 40 | 6 | 0.81 / 0.85 / 0.62 | Foliage |  |
| `grass_tall` | 40 | 6 | 1.2 / 1.06 / 1.08 | Foliage |  |
| `log_branchy` | 190 | 76 | 3.24 / 1.15 / 0.81 | Bark, Moss |  |
| `log_mossy` | 136 | 40 | 4.24 / 0.72 / 0.62 | Bark, Moss |  |
| `oak_a` | 1606 | 482 | 9.38 / 8.05 / 8.29 | Bark, Foliage | + `_lod2` impostor (4 tris) |
| `oak_b` | 1280 | 392 | 7.56 / 8.61 / 7.62 | Bark, Foliage | + `_lod2` impostor (4 tris) |
| `pine_scots` | 1202 | 376 | 8.04 / 9.15 / 11.0 | Bark, Foliage | + `_lod2` impostor (4 tris) |
| `rock_cluster` | 960 | 240 | 2.43 / 1.71 / 1.35 | Rock, Moss |  |
| `rock_medium` | 320 | 80 | 1.37 / 0.96 / 0.84 | Rock, Moss |  |
| `rock_slab` | 320 | 80 | 1.77 / 1.34 / 0.77 | Rock, Moss |  |
| `spruce_a` | 1493 | 139 | 7.73 / 7.73 / 13.25 | Bark, Foliage | + `_lod2` impostor (4 tris) |
| `spruce_b` | 1277 | 129 | 5.71 / 5.99 / 8.75 | Bark, Foliage | + `_lod2` impostor (4 tris) |
| `stump_broken` | 164 | 119 | 1.2 / 1.16 / 1.42 | Bark, Moss |  |
| `stump_mossy` | 142 | 103 | 1.43 / 1.41 / 0.58 | Bark, Moss |  |
| `young_oak` | 656 | 246 | 4.17 / 4.43 / 4.7 | Bark, Foliage | + `_lod2` impostor (4 tris) |

### farm

| asset | LOD0 tris | LOD1 tris | size x/y/h (m) | materials | notes |
|---|---|---|---|---|---|
| `barn` | 1380 | 520 | 12.76 / 8.89 / 8.05 | Stone, Planks, Timber, Iron, Shingle, Hay |  |
| `chicken_coop` | 536 | 184 | 3.41 / 3.61 / 2.35 | Timber, Planks, Shingle, Log, Hay |  |
| `crop_cabbage` | 682 | 538 | 4.0 / 3.65 / 0.38 | Soil, Plaster, Crop |  |
| `crop_wheat` | 210 | 140 | 4.0 / 4.05 / 1.17 | Soil, Crop |  |
| `fence_gate` | 128 | 116 | 1.8 / 0.64 / 1.4 | Log, Timber, Iron |  |
| `fence_picket` | 192 | 60 | 2.12 / 0.15 / 1.15 | Timber, Planks |  |
| `fence_rail` | 72 | 44 | 3.24 / 0.22 / 1.15 | Log |  |
| `granary` | 1000 | 544 | 5.0 / 4.97 / 5.59 | Stone, Timber, Planks, Iron, Thatch, Canvas |  |
| `hay_wagon` | 1772 | 984 | 5.59 / 2.04 / 2.27 | Planks, Timber, Iron, Hay |  |
| `pig_sty` | 308 | 216 | 5.0 / 4.02 / 2.5 | Stone, Planks, Timber, Soil, Thatch, Hay |  |
| `scarecrow` | 384 | 202 | 1.87 / 0.72 / 2.32 | Log, Canvas, Hay, Timber |  |
| `windmill` | 1272 | 628 | 6.6 / 7.0 / 12.8 | Stone, Timber, Shingle, Planks, Iron, Canvas | markers: sail_hub |
| `windmill_sails` | 668 | 332 | 14.57 / 0.55 / 7.29 | Timber, Canvas |  |

### mine

| asset | LOD0 tris | LOD1 tris | size x/y/h (m) | materials | notes |
|---|---|---|---|---|---|
| `mine_cart` | 452 | 240 | 0.99 / 1.62 / 1.02 | Planks, Iron, Cliff, Timber |  |
| `mine_entrance` | 2868 | 780 | 14.43 / 10.41 / 9.98 | Cliff, Soil, Timber, Planks, Glow, Iron |  |
| `mine_props` | 868 | 504 | 3.21 / 2.61 / 1.3 | Planks, Timber, Iron, Cliff |  |
| `mine_winch` | 944 | 484 | 4.34 / 6.21 / 6.37 | Timber, Iron, Hay, Planks, Log |  |
| `miners_hut` | 1464 | 720 | 5.85 / 5.04 / 4.85 | Stone, Log, Plaster, Timber, Planks, Iron, Shingle, Glow | markers: chimney_top |
| `ore_pile_coal` | 544 | 160 | 2.57 / 2.15 / 1.11 | Soil, Cliff, Timber, Iron |  |
| `ore_pile_copper` | 544 | 160 | 2.52 / 2.33 / 1.11 | Soil, Cliff, Timber, Iron |  |
| `ore_pile_iron` | 544 | 160 | 2.62 / 2.37 / 1.11 | Soil, Cliff, Timber, Iron |  |
| `rail_curve` | 240 | 120 | 2.87 / 4.62 / 0.17 | Iron, Timber | markers: track_end |
| `rail_end` | 200 | 128 | 2.59 / 3.84 / 0.91 | Iron, Timber, Soil |  |
| `rail_straight` | 108 | 60 | 1.4 / 4.0 / 0.17 | Iron, Timber |  |
| `tunnel_support` | 132 | 84 | 3.2 / 1.75 / 3.23 | Timber, Planks |  |

### road

| asset | LOD0 tris | LOD1 tris | size x/y/h (m) | materials | notes |
|---|---|---|---|---|---|
| `bridge_stone` | 310 | 222 | 3.7 / 12.56 / 3.16 | Stone, Soil |  |
| `bridge_wood` | 856 | 332 | 3.2 / 14.06 / 2.6 | Planks, Timber, Log |  |
| `caravan_wagon` | 2304 | 940 | 6.18 / 2.16 / 2.58 | Planks, Timber, Iron, Canvas, Glow |  |
| `checkpoint_barrier` | 196 | 112 | 5.22 / 0.42 / 1.25 | Log, Timber, Planks, Stone, Iron, Canvas | markers: boom_pivot |
| `checkpoint_boom` | 128 | 80 | 5.17 / 0.4 / 0.2 | Planks, Stone, Iron |  |
| `milestone` | 108 | 80 | 0.7 / 0.5 / 1.31 | Stone, Cliff, Timber |  |
| `roadside_inn` | 2320 | 1480 | 13.07 / 8.5 / 10.28 | Stone, Plaster, Timber, Planks, Iron, Glow, Slate, Shingle, Canvas, Thatch, Hay | markers: chimney_top, door |
| `toll_booth` | 700 | 364 | 3.64 / 3.2 / 3.6 | Stone, Planks, Timber, Shingle, Iron, Glow, Log, Canvas |  |
| `wayshrine` | 254 | 215 | 1.6 / 1.85 / 2.68 | Stone, Timber, Plaster, Shingle, Planks, Glow, Crop | markers: interact |

### ruins

| asset | LOD0 tris | LOD1 tris | size x/y/h (m) | materials | notes |
|---|---|---|---|---|---|
| `bandit_lean_to` | 256 | 72 | 3.6 / 2.89 / 1.9 | Log, Canvas, Planks, Timber |  |
| `bandit_palisade` | 274 | 108 | 4.1 / 0.4 / 3.13 | Log |  |
| `bandit_stash` | 740 | 368 | 3.75 / 2.78 / 2.15 | Planks, Timber, Iron, Canvas |  |
| `bandit_tent` | 334 | 74 | 4.42 / 4.02 / 2.35 | Log, Canvas, Timber, Hay |  |
| `campfire` | 448 | 188 | 3.6 / 1.84 / 1.16 | Cliff, Soil, Log, Glow, Timber, Iron | markers: fire |
| `collapsed_tower` | 618 | 234 | 11.49 / 9.02 / 10.07 | Stone, Timber, Crop | markers: interior |
| `goblin_totem_a` | 470 | 200 | 1.45 / 1.04 / 3.61 | Log, Canvas, Timber, Glow, Plaster, Hay, Cliff |  |
| `goblin_totem_b` | 734 | 308 | 2.62 / 0.32 / 2.95 | Log, Plaster, Timber, Hay, Canvas | markers: warning |
| `overgrown_shrine` | 676 | 332 | 6.81 / 7.92 / 5.17 | Stone, Plaster, Glow, Crop | markers: altar |
## Open issues / next steps

* Grass, flower and fern clumps are deliberately cheap (36-54 tris); for dense meadows scatter them
  with a MultiMesh and a distance fade rather than LOD swaps.
* Structures use 3-8 materials each (one per shared tiled texture). Fine for props; for very
  frequent buildings a baked per-asset atlas would cut draw calls.
* Spruce LOD1 (about 135 tris) is noticeably sparser than LOD0; use it only past ~45 m.
* The dark oak's hanging-moss cards read as grey curtains up close; they look right at distance.
* Farm crops, ivy and weeds (`RG_Crop`) don't sway; they could use the foliage wind shader if they
  get the nature COLOR_0 convention.
