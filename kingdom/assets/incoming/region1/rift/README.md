# Rift-touched kit (Region 1, work package L4)

Everything the Ashen Scar needs to look "touched by the Rift" without new meshes: **material swaps** on the existing region
nature GLBs, scar-crystal clusters, ground decals, rift wolf / boar fur, and an import check for `rift_slime` / `rift_wraith`.

**Look rule:** still the sunny storybook style, not grimdark. Rift = lavender and periwinkle leaves in full daylight, a thin
cyan vein shimmer, pale lilac ground with cyan cracks. Nothing goes black, brown-grey or burnt. Judged against
`docs/art/reference/00_MAIN_kingsreach_gate_market.webp` (renders: `docs/art/region1/rift_*.png`).

## What is here

| Path | What | Cost |
|---|---|---|
| `materials/rift_foliage.tres`, `rift_foliage_ground.tres` | shader materials that replace `rg_foliage.tres` / `rg_foliage_ground.tres` (same wind, AO, fade); violet to cyan leaf atlas + emissive vein | same draw calls as the normal materials; 1 extra 1024 atlas (+1024 vein mask, 1 channel of data) per pair |
| `materials/rift_bark.tres`, `rift_rock.tres`, `rift_moss.tres` | replace `rg_bark`, `rg_rock`, `rg_moss` (warm violet bark with glowing cracks, tinted rock, violet moss) | idem |
| `materials/rift_impostor.tres` | LOD2 impostor cards recoloured to match (`textures/rift_tree_impostors.png`) | idem |
| `shaders/rift_foliage.gdshader`, `rift_bark.gdshader` | copies of `region_foliage` / `region_nature_opaque` (`generated/region/nature/`) + `vein_texture`, `vein_color`, `vein_strength`; rift foliage ignores the season look on purpose | no extra cost |
| `crystals/scar_crystal_{a,b,c}_lod0/1.glb` | scar-crystal clusters (5 crystals each: amethyst, cyan, lilac ice), pedestals removed, ONE mesh, ONE emissive material (texture doubles as emission map, strength 0.55). About 1.4 x 1.3 x 1.2 to 1.8 m, origin at the buried base | LOD0 895 / 1,300 / 3,500 tris (prop budget 4k), LOD1 895 / 1,050 / 1,050 (budget 1.2k); 512 / 256 px; 1 draw call |
| `decals/rift_decal_{patch_a,patch_b,crack}.png` + `_em.png` | 512 px RGBA ground decals: lilac stain with a cyan crack network / sparkles / a long fissure; emission maps hold only the cracks | 1 decal each |
| `decals/rift_decal.tscn` | Godot `Decal` projector (5 x 2 x 5 m, fades at 70 to 90 m), for MEDIUM / HIGH | LOW has no decals. `cull_mask = 1`: keep characters, creatures and props on render layer 2 (or another layer) or the decal paints them lilac too |
| `decals/rift_decal_card.tscn` | flat unshaded alpha quad using the same texture, for the LOW tier (or where decals are off) | 1 draw call, 2 tris |
| `materials/rift_wolf(.tres, _lod1)`, `rift_boar(_lod1)` | ShaderMaterial (`shaders/rift_creature.gdshader`) with recoloured fur (violet, cooler highlights) and a sparse cyan emission vein; assign as `material_override` on the Meshy creature (`wolf.glb`, `boar.glb`, and their `_lod1`) | 0 extra draws |
| `textures/` | all recoloured atlases and vein masks (`rift_foliage_atlas`, `rift_bark_atlas`, `rift_moss`, `rift_tree_impostors`, `rift_wolf*`, `rift_boar*`, `*_vein.png`) | about 5.8 MB total for the folder |
| `rift_variants.gd` | `RiftVariants.apply(mesh_instance, ground)` swaps the region nature materials on one instance (surface overrides, the shared mesh is untouched); `apply_creature(node, "wolf", lod1)` | free |

## Use

```gdscript
var tree := MeshInstance3D.new()
tree.mesh = Assets.nature_mesh("region/nature/oak_a")     # any region/nature key, LOD0/1/2
RiftVariants.apply(tree)                                    # ground = true for grass / flowers / ferns
add_child(tree)

var scar := (load("res://assets/incoming/region1/rift/crystals/scar_crystal_a_lod0.glb") as PackedScene).instantiate()

var wolf: Node3D = (load("res://assets/incoming/ai3d/meshy/creatures/wolf_lod1.glb") as PackedScene).instantiate()
RiftVariants.apply_creature(wolf, "wolf", true)             # animations keep working (material only)
```

The game swaps `RG_*` materials when it builds a nature mesh (`Assets._region_materials`). For a spreading front (mechanic N2)
swap **per instance** with `RiftVariants.apply` when the corruption reaches it, or build rift and normal variants side by side
in the MultiMesh cells (a MultiMesh takes one material per surface, so use separate rift cells). The rift foliage materials do
not follow `weather_wind` (`weather.gd` updates a fixed list of materials); register the two rift foliage materials there if
storms should bend them.

## Import check: `rift_slime`, `rift_wraith`

`tools_qa/region1/rift_import_check.gd` loads both monsters (and this kit's GLBs and materials headless):
`Godot --headless --path kingdom -s res://tools_qa/region1/rift_import_check.gd`. Results (2026-09-29, Godot 4.6.3):
see the table at the end of this file (filled in by the run).

## Rebuild

```
blender -b --python kingdom/tools/blender/make_rift_textures.py      # recolours + vein masks
blender -b --python kingdom/tools/blender/make_scar_crystals.py      # crystal clusters
blender -b --python kingdom/tools/blender/make_rift_decals.py        # decals + the two decal scenes
```
Render checks: `Godot --path kingdom res://tools_qa/region1/rift_sheet.tscn --resolution 1600x900 -- --sheet=flora|fauna|vignette|silverford --out=<png>`.

Licences: crystals derive from Meshy community CC0 crystals (`meshy_free/magic/`), everything else is recoloured project art
or procedural. See `kingdom/CREDITS.md`.

## Import check results (Godot 4.6.3, 2026-09-29): 19/19 PASS

| Asset | Tris | Bones | Size m (x, y, z) | Clips (s) | Glow |
|---|---|---|---|---|---|
| `rift_slime` / `_lod1` | 1,984 / 1,000 | 12 | 0.95 x 0.73 x 1.17 | idle 2.54, walk 0.88, run 0.88, attack 0.67, hit 0.50, death 0.46 | emission texture, energy 2.5 |
| `rift_wraith` / `_lod1` | 8,000 / 2,500 | 38 | 3.57 x 1.94 x 0.88 (hovers, y0 0.20) | idle 1.17, walk 1.17, run 0.83, attack 1.17, hit 0.47, death 0.67 | emission texture |

Both load, skin and carry the six clips the game expects. Not wired into any spawner yet (`rift_slime` / `rift_wraith` are still unused
by `scripts/`). The kit's crystals (`scar_crystal_a/b/c`), all nine rift materials and both decal scenes load too.
Note: the two Meshy-style monsters carry a strong emission (slime 2.5): keep bloom threshold at 1.0 or the slime blows out.
Renders: `docs/art/region1/rift_flora.png` (normal left / rift right), `rift_fauna.png`, `rift_vignette.png`, `rift_silverford.png`.
The render harness sky is plain (procedural sky, no clouds, no dressing); it judges colour, not density.
