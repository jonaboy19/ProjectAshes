# Highwatch Keep kit (Region 1, work package L2)

The knightly stronghold of the Order of the Highwatch (Valencious, Ashford Vale, northern ridge). A modular kit that is
placed as **one site** from `highwatch_site.json`: 32 instances, **one shared material = 32 draw calls (target <= 40)**.

Previews (Blender, storybook lighting, atlas material): `docs/art/region1/highwatch_iso.jpg` (3/4), `highwatch_top.jpg`
(top-down), `highwatch_front.jpg`, `highwatch_gate.jpg`, `highwatch_yard.jpg`, LOD1 checks `highwatch_iso_lod1.jpg`, `highwatch_gate_lod1.jpg`.

**Not yet imported in Godot** (the local disk is too tight for an import in the work tree). The cloud session should open
the project once so the `.import` files are generated, then run the placement check below.

## Pieces (Y-up, origin at ground under the piece centre, front = +Z)

| Piece | Source | Tris LOD0 / LOD1 | Size m (x, y, z) | Used |
|---|---|---|---|---|
| `gate` | Meshy CC0 `gate_twin_towers_blue` (blue banners kept, recoloured royal blue / gold) | 11999 / 3598 | 14.0 x 10.5 x 4.6 | 1 |
| `tower_round` | Meshy CC0 `tower_round` | 7990 / 2397 | 5.8 x 10.6 x 7.1 | 4 (corners) |
| `tower_roof` | Blender-built conical royal-blue scale roof, gold eave band and finial | 180 / 104 | 7.5 x 5.9 x 7.5 | 4 (on the corner towers) |
| `watchtower` | Meshy CC0 `watchtower_stone_small` | 8000 / 2400 | 6.4 x 8.6 x 6.2 | 2 (mid east/west wall, door to the yard) |
| `wall_14` | Blender-built 14.6 m curtain wall: battered stone, merlons, buttresses, arrow slits | 108 / 28 | 14.6 x 7.5 x 3.0 | 9 |
| `keep` | Meshy CC0 `keep_small_on_plinth` (16 m wide) | 15000 / 4500 | 16.0 x 11.4 x 16.0 | 1 |
| `banner_pole` | Blender-built pole banner, Valencious blue, gold border, golden tree crest | 176 / 96 | 1.05 x 4.3 x 0.5 | 6 |
| `training_yard` | one merged mesh: packed-earth yard 11 x 15 m with sparring ring, fence, 3 straw dummies, 2 archery targets (blue/gold rings), sword rack, spear rack, 3 hay bales | 12861 / 4493 | 11 x 2.4 x 15 | 1 |
| `guard_post` | one merged mesh: flagstone plinth, armour stand (knight), heraldic shield, 2 torches | 10503 / 3156 | 2.4 x 2.1 x 2.4 | 2 (inside the gate) |
| `supplies` | merged: barrels + crates, hay bale, torch | 5993 / 1797 | 3 x 1.7 x 2 | 1 |
| `well` | Meshy CC0 `well_stone_roofed` | 2491 / 747 | 2.3 x 3.0 x 1.8 | 1 |
| `highwatch_site_far.glb` | whole site merged from LOD1 and decimated, 1 draw call | 8995 | 58 x 12 x 42 | far LOD |

Whole site: **120,058 tris at LOD0, 37,079 at LOD1, 8,995 as the far mesh** (1 draw call).
Guard NPC markers reference the existing rigged Meshy `armored/guard|knight|mercenary.glb` (`npc_markers` in the JSON); they are not part of the kit meshes.

## Materials, palette, texel density

* One 2048 atlas `textures/highwatch_atlas.jpg` (+ `_1024.jpg` for the LOW tier) and one material `highwatch_kit.tres`
  (`highwatch_kit_low.tres` uses the 1024 atlas). **The .glb files carry no texture**: assign the .tres to every kit mesh
  (`for each MeshInstance3D: mesh_instance.material_override = kit_mat` or surface override 0).
* Palette: the Meshy source textures were graded to one warm palette (stone `#c7b590` to `#786858`, oak, moss), reds/pinks/dark
  blues recoloured to Valencious royal blue `#244da8` and gold `#f2bd38`; the wall, roof, banner and yard textures are painted in the same colours.
* Texel density: architecture **about 23 px/m** on every piece (gate 18.5 - it is the largest Meshy source; towers/watchtower 23.6; walls 23),
  props 40-60 px/m. The keep is only 10 px/m (its Meshy source is 15 px/m native); it is seen from afar. LOD1 tiles are half that.

## How to place

`highwatch_site.json`: `placements[]` = `{piece, pos:[x,y,z], yaw_deg, note}`, Godot metres, site-local. Origin = centre of the gate
threshold on the ground; the compound extends toward -Z (north) 37 m and +-27 m in X; the gate faces +Z. Sample:

```gdscript
var site = JSON.parse_string(FileAccess.get_file_as_string("res://assets/incoming/region1/highwatch/highwatch_site.json"))
var mat: Material = load("res://assets/incoming/region1/highwatch/highwatch_kit.tres")
for p in site.placements:
    var info = site.pieces[p.piece]
    var n: Node3D = load("res://assets/incoming/region1/highwatch/" + info.lod0).instantiate()
    # set material_override on the MeshInstance3D child, position/rotation:
    n.position = Vector3(p.pos[0], p.pos[1], p.pos[2]) ; n.rotation_degrees.y = p.yaw_deg
    root.add_child(n)
```

* Flatten the terrain under the compound (a 56 x 40 m pad, walls sit at ground level; sink pieces 5 cm). The keep and towers are
  ground-anchored; the yard is a 14 cm slab.
* LOD: LOD0 to 60 m, LOD1 60-160 m, `highwatch_site_far.glb` beyond (`visibility_range_end` / `_begin`, fade mode self).
  On the LOW tier start LOD1 at 30 m.
* No colliders are included: walls 14.6 x 7.5 x 2.6 boxes, keep 16 x 12 x 16 box, towers cylinders r 2.9 (or generate trimeshes from LOD1).
* Wall walks are not walkable in this kit (decorative crenellated tops); guards stand on the ground or at the `wall_sentry` marker.

## How it is built (re-runnable)

`blender -b --python kingdom/tools/blender/region1/highwatch_kit.py -- <kingdom dir> <out dir> [preview dir]` (Blender 5.2, about 1 minute).
Helpers: `kitpaint.py` (palette grading, bricks, cloth, roof tiles), `stonekit.py`, `paint.py`, `sheet.py`.
Decimating the 8-12k-tri Meshy meshes destroys them (thin shells shred), so the big pieces keep their optimized LOD0 and use the
shipped Meshy LOD1 files; only the small props are decimated for LOD1 (UV borders locked).

## Known gaps (next tasks)

* Not imported/tested in Godot; the site total at LOD0 is 120k tris, place LOD1 early on LOW.
* Keep and gate could be re-painted with blue roofs; the interior of the keep is not modelled (interior scene "Highwatch hall" is still missing).
* Add trimesh/box colliders, and a wall-walk nav mesh if guards should patrol the walls.
