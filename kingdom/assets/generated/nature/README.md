# Generated nature set (temperate forest)

Semi-realistic, mobile-budget trees, bushes, grass and flowers, built procedurally in Blender.
Previews: `docs/kingdom/blender_previews/nature/` (includes `forest_edge.png`).

Rebuild from the repo root (needs the `bpy` module, Blender 5.x, and numpy):

    python3 kingdom/tools/blender/make_nature_textures.py      # textures/
    python3 kingdom/tools/blender/make_nature.py [names] [--no-preview]
    python3 kingdom/tools/blender/make_nature_forest_preview.py

## Assets

| file | what | height | tris |
|---|---|---|---|
| oak_a.glb / oak_b.glb | English oak, broad crown | ~12.6 m / ~9.9 m | <= 6000 |
| birch_a.glb | silver birch, white bark, weeping twigs | ~11 m | ~5200 |
| pine_a.glb | Scots pine, orange upper bark, crown in top 40% | ~17.8 m | <= 6000 |
| pine_b.glb | spruce-like conical conifer | ~14.2 m | <= 6000 |
| sapling.glb | young broadleaf | ~3.6 m | ~800 |
| dead_tree.glb | bare snag with broken limbs | ~7 m | ~2400 |
| bush_a.glb / bush_b.glb | hazel-like / low dark shrub | ~1.8 m / ~1.5 m | <= 1500 |
| grass_clump.glb / grass_clump_tall.glb | crossed blade cards | 0.5 m / 1.05 m | 64 / 120 |
| flowers_a.glb | daisies, buttercups, campion + grass skirt | 0.55 m | 88 |

Origin is at the base on the ground, +Y up in Godot. Heights include the leaf cards.

## Materials

* Bark (`Bark_Oak`, `Bark_Pine`, `Bark_Birch`) is opaque and single-sided. It has albedo and an
  OpenGL normal map. Oak and pine bark are ambientCG Bark001 and Bark012 (CC0), scaled to 1K.
  Birch bark is generated.
* Leaves and needles (`Leaves_Broadleaf`, `Needles_Conifer`) use glTF `alphaMode: MASK` with
  `alphaCutoff 0.4` and `doubleSided: true`. Godot imports them as alpha scissor, cull disabled.
  Each card is a whole leafy sprig from a 2x2 atlas.
* The GLBs do not embed their textures. They reference `textures/*.png|jpg` by relative URI, so
  every tree shares one bark texture and one leaf texture in memory. The `textures/*.import`
  files set VRAM compression with mipmaps, and mark the normal maps as normal maps.

## COLOR_0 (vertex colour) conventions

* **Trees and bushes:** COLOR_0 is an albedo tint multiplied by a baked fake ambient occlusion.
  Inner and lower leaf cards are darker, and the bark gets darker and mossier near the ground.
  Godot multiplies it into albedo automatically (`vertex_color_use_as_albedo`), which is what
  we want.
* **Grass and flowers:** COLOR_0 is wind data, not colour.
  * **R** = bend weight. It is 0 at the ground and 1 at the blade tips, linear in height, so bend
    only the tips with e.g. `COLOR.r * COLOR.r`.
  * **G** = random phase per card, from 0 to 1.
  * **B** = 0.5 (reserved). **A** = 1.

  If COLOR_0 were used as albedo, the grass would be tinted red and black. For that reason
  `grass_clump*.glb.import` and `flowers_a.glb.import` swap their `Meadow` material at import
  time for `meadow_wind_material.tres`. That material runs `foliage_wind.gdshader`, which does
  three things:
  * bends the tips by COLOR.r
  * ignores COLOR for albedo
  * keeps the custom up-facing normal on the back face, so grass does not go dark from one side

## Normals

Leaf and needle cards carry canopy normals: custom normals pointing out from the crown centre
(or from the trunk axis for the spruce), blended toward up. The crown then shades as one soft
volume. Each card's front face is turned outward, because Godot flips the normal on back faces
of double-sided materials; this way the visible cards keep the outward normal. Grass normals are
about 80% up, like terrain.

## Game-side notes

* Scatter with MultiMeshInstance3D. All grass and flowers share one material, and all broadleaf
  trees share one leaf material.
* For tree wind, sway the vertices by world height in a shader. Tree COLOR_0 is tint, not wind.
* The Blender previews add a little leaf translucency. In Godot the same look comes from
  `backlight_enabled = true` and `backlight ≈ (0.2, 0.25, 0.1)` on the leaf materials; this is
  optional. Enable it through an import-time material override if wanted.
