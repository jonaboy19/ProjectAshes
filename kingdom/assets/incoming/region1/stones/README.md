# Region 1 stones: Elder Stone + 4 road stones (work package L1)

Runestones for the Ashford Vale runestone network: one grand **Elder Stone** (hub, five of them in the region) and four
**road-stone variants** (every 180-420 m along the roads). All are Blender-built (no Meshy credits, no third-party source
meshes), painted in the warm storybook palette (`docs/art/reference/00_MAIN_...`): warm tan stone, sunny moss, blue-violet
rune light. Y-up, origin at ground level under the centre, real-world metres, front (glyph face) toward +Z.

Preview: `docs/art/region1/stones_contact_sheet.png` (next to the style reference) and
`docs/art/region1/stones_glow_60m.png` (glow test at 60 m, Godot-default 75 deg FOV; top row noon, bottom row dusk, left
dim, right bright; crops are 2x nearest).

## Pieces

| File | What | Tris LOD0 / LOD1 | Height | Textures |
|---|---|---|---|---|
| `elder_stone_lod0/1.glb` | dais (3 steps, r 3.6 m), 5.6 m monolith with carved glyph column, 2 leaning shards, 6 ward menhirs, rubble | 4204 / 1152 | 6.4 m | 2048 albedo (jpg), 1024 normal, 1024 emissive |
| `road_stone_a_slab_lod0/1.glb` | standing slab, key-glyph + 3 runes | 504 / 176 | 1.7 m | 512 |
| `road_stone_b_menhir_lod0/1.glb` | tapering menhir, spiral + chevrons | 536 / 196 | 2.1 m | 512 |
| `road_stone_c_squat_lod0/1.glb` | squat waystone, rune band | 536 / 196 | 1.1 m | 512 |
| `road_stone_d_pillar_lod0/1.glb` | collared pillar, eye ring + rune | 632 / 256 | 1.8 m | 512 |

Each stone is one mesh, one material = **1 draw call** (the hero is 4204 tris, under the 6k limit). LOD1 is a rebuilt
low-segment version of the same shape with the same UVs and textures, switch at about 45 m (Elder) / 25 m (road stones).

## Materials

One StandardMaterial3D per stone and colour variant (`*.tres`, albedo + normal + emission wired):

* `<name>.tres` blue rune light.
* `<name>_ancestor_gold.tres` **ancestor-gold variant**: gilded stone speckle, gold channel floor, gold emission.
  Same mesh/UVs, only the albedo and emissive textures differ, so it is a pure material swap
  (`mesh_instance.set_surface_override_material(0, load(...))`). Use it for ancestor stones (Ember Legacy) and lit heirloom stones.
* The glb also embeds the blue material, so it works without the `.tres` (then set emission by hand).

## Emissive glow spec (drive it at runtime, dim to bright)

The glyph light is a **separate emissive mask**, not baked into the albedo:

1. `*_emissive.png` (sRGB, black = no light): RGB = rune colour (blue `0.22,0.62,1.0` with a near-white core; gold
   `1.0,0.66,0.16` for the gold variant), value = channel intensity, plus a small halo bleed. Only glyph channels are non-black.
2. In the albedo the unlit channel floor stays a dark blue (or dark gold) so a **dim stone still reads as carved runes**.
3. Drive the glow with the material property `emission_energy_multiplier` (the emission colour is white, the texture holds the
   colour): **dim/dormant 0.15-0.35, awake 1.0, bright/flare 3.0-4.0** (Compatibility renderer: keep <= 3, glow/bloom
   threshold at about 0.9). Animate it with a tween per stone; 1 material per variant, so do not share one material between
   stones that need different glow levels (duplicate the resource, it is tiny).
4. Optional per-vertex sweep: glTF `COLOR_0` (vertex colour) on every stone:
   * `R` = position along the energy path 0..1 (Elder: outer menhirs 0.0-0.2, dais 0.1-0.3, monolith base 0.3 to crown 1.0;
     road stones: base 0.2 to top 1.0). A shader can light the glyphs as a wave: `glow = smoothstep(t-0.15, t, R)`.
   * `G` = 1 on glyph-bearing parts, 0 on rubble (mask out of the pulse).
   * `B` = cheap ambient-occlusion proxy (0.55 at the ground contact to 1.0). Not applied by default; multiply into albedo
     in a shader if wanted. StandardMaterial3D ignores vertex colour unless `vertex_color_use_as_albedo` is on, so the default look is unchanged.
5. Radius of the light: bloom only (no Light3D). If you want a light, add one `OmniLight3D` (blue, range 8 m, energy
   `0.4 * emission_energy_multiplier`) at the Elder Stone crown, `shadow_enabled = false`, LOW tier: none.

## Placement

* Origin is the ground contact point; sink Elder and road stones 5-10 cm into the terrain (the dais and plinth bottoms are open).
* Elder Stone footprint radius 5.2 m incl. menhirs and rubble (keep trees out of 5.5 m, the sim reserves 6 m).
* Road stones: place 0.8-1.2 m beside the road, glyph face toward the road (front = +Z, so rotate `yaw` to point +Z at the road).
* Read the glow at distance: at 60 m the Elder crown is about 6 percent of screen height; dim (0.3) is a faint blue thread,
  bright (4.0) clearly reads (see the glow sheet). Road stones at 60 m are about 2 percent: keep them 0.7+ energy in gameplay.

## How it is built (re-runnable)

`kingdom/tools/blender/region1/`: `elder_stone.py`, `road_stones.py` (`blender -b --python ... -- <out_dir>`), shared
`stonekit.py`, `stonepipe.py`, `stonepaint.py`, `stoneshapes.py`, `paint.py`. Charts are planar projections with correct tangent
handedness, so the normal map comes straight from the painted height map (carved channels 2 cm deep); no high-poly bake, no
Meshy, no third-party geometry. Licence: our own work (CC0-style, see CREDITS.md).
