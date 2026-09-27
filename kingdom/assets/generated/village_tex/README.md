# Village / town art pass (round 6): shared detail textures, weathering, LODs

This covers the Blender-built buildings, stalls and props in `kingdom/assets/generated/`. The generators are
`kingdom/tools/blender/make_*.py`, built on `ra_kit.py`, `village_kit.py`, `town_kit.py` and `ra_polish.py`.

The goal was a more crafted look at the same or lower triangle counts and no extra runtime cost:

- The detail comes from shared textures and a weathering bake in the vertex colours.
- Shapes got bevels, dormers, signs and banners, paid for by deleting faces nobody sees.

Rebuild everything from the repo root (needs `bpy`, Blender 5.x, and numpy):

    python3 kingdom/tools/blender/make_village_textures.py   # this folder
    python3 kingdom/tools/blender/build_village_assets.py    # houses (4 variants each), inn, smithy, barn, stalls, fence, planter, flower bed
    python3 kingdom/tools/blender/build_town_assets.py       # well, bell tower, chapel, temple, walls, gate, keep, props
    python3 kingdom/tools/blender/build_region1_assets.py adventurer_guild healer_house

## Textures (this folder)

There are seven surface families. Each one has three 512×512 maps that tile seamlessly:

| file | contents |
|---|---|
| `ra_<family>_alb.png` | Detail albedo, sRGB. Near-neutral, mean 0.86, softly posterized so it reads hand-painted. |
| `ra_<family>_nrm.png` | OpenGL tangent-space normal map (glTF convention). |
| `ra_<family>_mr.png` | glTF metallicRoughness: G = roughness, B = metalness (iron only; rust is non-metal). |

| family | used by material | source | tile |
|---|---|---|---|
| plaster | `RA_Plaster` | generated: lime blotches, trowel strokes, sand, hairline cracks | 2.4 m |
| wood | `RA_Wood` | generated: long grain, growth lines, checks, knots | 1.2 m |
| stone | `RA_Matte` (stone, mortar, pots) | generated: pitted mottled rock, fractures, lichen specks | 1.1 m |
| roof | `RA_Roof` (slate, shingle, tile) | generated: riven grain down the slope, lichen | 1.0 m |
| thatch | `RA_Thatch` | generated: combed straw strands down the slope | 0.9 m |
| cloth | `RA_Cloth` (awnings, banners, sacks, rope) | ambientCG Fabric061 (CC0) weave + generated wrinkles | 0.7 m |
| iron | `RA_Metal` | generated: hammer dimples, scale, rust blooms | 0.6 m |

`RA_Plant`, `RA_Glass`, `RA_WindowLit` (warm emissive windows, used on about 40% of windows, 85% on the
inn), `RA_Lamp`, `RA_Coals` and `RA_Water` stay plain vertex colour. None of the materials uses alpha.

**Why seven sets and not one atlas.** A tiling detail map cannot wrap inside an atlas cell with a stock
`StandardMaterial3D`; that would need a custom shader doing `fract()` on UVs, plus padding and mip
handling. Instead the GLBs do two things:

- They *reference* these PNGs by relative URI (`village_tex/ra_wood_alb.png`) instead of embedding them.
  Godot resolves each URI to the one imported texture, so every building shares a single copy in VRAM:
  21 maps, about 7 MB with BPTC/S3TC and about 4 MB with ETC2/ASTC.
- They use the same material names in every file (`RA_Wood`, `RA_Plaster`, and so on).

Each `.png.import` file here sets `compress/mode=2` (VRAM compressed) with `mipmaps/generate=true`. The
`*_nrm` maps are also marked as normal maps. Godot's glTF importer then gives each material:

- albedo texture × vertex colour (`vertex_color_use_as_albedo`)
- the normal map
- the roughness and metallic textures (G/B channels)

**UVs.** UVs are a box projection in each primitive's own metres (the same texel density everywhere).
Timber grain follows the long axis of each beam. Plank walls, doors and staves run their grain upright.

**COLOR_0.** COLOR_0 is the palette tint × weathering, divided by the albedo mean, so tint × detail
matches the old colours on average. Recolouring a variant is still just a vertex-colour change.

## Weathering baked into COLOR_0 (`ra_polish.weather`)

The weathering costs nothing at runtime. It includes:

- ray-traced ambient occlusion against the asset plus a ground plane, which gives:
  - contact shadow at the base of every prop and building
  - darkening under eaves, in corners, and under balconies and jetties
- a contact band at the ground line; tall faces get one extra vertex row at 0.14 m (props) or 0.32 m
  (buildings) so the band doesn't smear up the whole face
- a damp tide line with a ragged top on plaster, stone and timber wall bases
- grime streaks under every window sill
- faint rain banding on plaster
- sun-bleached upper roofs
- moss creeping up north-facing (+Y in Blender, −Z in Godot) roof eaves, and moss on north- and
  up-facing low stone
- sun-greyed tops of timber
- low-frequency dirt over everything

## Geometry pass (`ra_polish`)

- **Hidden-face removal.** A face is deleted when every ray from every sample point on it is blocked,
  either by the asset or by the ground within 0.4 m. This catches bottoms on the ground and faces sealed
  inside the shell. It removes 10–25% of each building's triangles, and that pays for the new detail.
- **Displacement.** A tiny smooth displacement bows wall lines by about 2 cm and sags long ridges by up
  to 8 cm, so no 20 m edge is ruler-straight. It is zero at the ground, so footprints stay put. Long
  timbers are cut every 2.6 m so they bend too.
  - Tiling pieces (`town_wall`, `fence_section`) are not deformed, so their seams still match.

## LODs

Every building writes `<name>.glb` (LOD0) and `<name>_lod1.glb` from the same build:

- **Detail** faces are tagged in the kits and dropped from LOD1: individual stones, shingles, straw rows,
  boards, pane bars, flowers, clutter.
- **Stand-ins** are cheap LOD1-only replacements: one quad per course run, one strip per roof course, a
  coarse thatch sheet, a single door leaf, plain un-bevelled boxes.
- When the stand-ins are not enough, a final quadric collapse brings LOD1 to ≤ 34% of LOD0.
- LOD1 keeps the same silhouette, materials and colours.

The four big landmarks (`temple`, `castle_keep`, `town_gate`, `bell_tower`) also get `<name>_lod2.glb`.
It is a voxel-remeshed, collapse-decimated proxy of about 420 triangles, with materials and colours taken
from the nearest LOD1 face.

Suggested switch distances (camera to object centre, metres). Use `GeometryInstance3D.visibility_range_*`
on one MeshInstance3D / MultiMeshInstance3D per level, with ~5 m hysteresis margins and fade mode
*Disabled* (no alpha):

| asset class | LOD0 | LOD1 | LOD2 / cull |
|---|---|---|---|
| houses, inn, smithy, barn, guild, healer, chapel | 0–45 | 45–160 | cull > 260 (or keep LOD1 for the aerial view) |
| temple, castle_keep, town_gate, bell_tower | 0–70 | 70–220 | LOD2 beyond 220, never culled |
| town_wall, town_wall_tower | 0–50 | 50–200 | cull > 400 |
| stalls, carts, well, lamp post, signpost, planter, flower bed | 0–40 | – | cull > 80 |
| fence, woodpile, haystack, washing line, garden plot | 0–35 | – (`_lod1` exists for fences/walls) | cull > 70 |

## Markers

Buildings with chimneys carry empties (Node3D in Godot) named `chimney_top`, `chimney_top_2`, and so on,
at the top centre of each chimney opening, for cheap smoke particles. `Assets.merged_mesh()` ignores
them, because it only collects MeshInstance3D.
