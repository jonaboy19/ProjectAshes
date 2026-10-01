# Horse assets (coats, LODs, tack, cart)

Rebuild everything (idempotent, ~1-2 min; never saves `source/horse_rig.blend`):

    "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup --python kingdom/tools/anim/horse/horse_export.py
    (add  -- --no-previews  to skip the docs/anim/horses/*.png renders)

Scripts: `horse_export.py` (driver) - `horse_coats.py` (UV unwrap + Cycles bakes + numpy painting) - `horse_tack.py` (tack builders, skin weights)
- `hx_atlas.py` (512 px tack atlas) - `hx_cart.py` (cart) - `hx_common.py` (helpers).

Output dir `kingdom/assets/generated/horses/`

| file | notes |
|---|---|
| `horse_coat_{bay,chestnut,grey,black,dappled,warhorse}.png` | 1024x1024 albedo (baked AO, cool shadows, brush strokes) |
| `horse_coat_<name>.tres` | StandardMaterial3D: albedo_texture, roughness 0.75, metallic 0, no normal map |
| `horse_riding.glb` | armature node `HorseSkeleton` (66 bones incl. sockets, rest pose, no animations) + `Horse_LOD0/1/2`, material `horse_coat` (bay texture embedded) |
| `horse_tack_{saddle,bridle,reins,saddlebags,cart_harness,barding}.glb` | same armature + one skinned mesh each, material `horse_tack` |
| `horse_tack_atlas.png`, `horse_tack.tres` | shared 512 px hand-painted atlas; the .tres has `cull_mode = 2` (double sided cloth/straps) |
| `horse_cart.glb` | static two-wheel cart, material `horse_tack` |

Triangles: LOD0 7624, LOD1 about 3.4k (45%), LOD2 about 1000 (13%). Tack: saddle about 1.2k, bridle about 310, reins 200, saddlebags about 430,
cart harness about 1.5k, barding about 1.05k; cart about 1.6k (see the STATS line printed by the driver).

Notes
- Coat UVs are one island layout shared by all coats and LODs (hair strands unfold as strips). Colour is position driven, so swap coats by swapping the material.
- Hooves: dark horn on bay/black/warhorse/dappled, light horn on grey and on the bay's white hind socks; blaze on the chestnut.
- Tack is skinned to the same skeleton (saddle/stirrups rigid to `spine_3`; bridle `head`/`jaw`; reins bit end `head`, hand end `rein_grip_L/R`;
  saddlebags `spine_1/2`; harness collar `neck_1/withers`, pad/belly band barrel bones, breeching `hips/thigh`; barding body weights copied from
  the nearest LOD0 surface, chanfron rigid `head`, crinet plates on `neck_*`).
- Cart space (Blender): origin on the ground under the axle centre, faces -Y. Shaft tips: `(+-0.27, -2.03, 1.10)` m from the cart origin, i.e. exactly
  at `tug_L/tug_R` when the cart origin sits at `(0, +2.05, 0)` in horse space (Godot/glTF: 2.05 m behind the horse, z = -2.05). The cart is a single
  mesh (axle along X at height 0.55); split the wheels in Godot if they should spin.
- Known: barding hem may clip the legs when they swing; the harness collar can dip into the neck when the neck is bent far down.
