# Market goods kit

56 small props for market stalls, shop fronts and stacks (produce, bread, cheese, fish, pottery, sacks, crates,
barrels, buckets, candles, books, bottles, tools, lanterns). Built by `tools/blender/make_market_goods.py`.

| Source | Licence | Credit |
|---|---|---|
| Quaternius **Fantasy Props MegaKit** (free version), 39 pieces | **CC0 1.0** (https://creativecommons.org/publicdomain/zero/1.0/) | Quaternius, https://quaternius.com (courtesy) |
| Quaternius **Ultimate Food Pack**, 14 pieces (fish twice) | **CC0 1.0** | Quaternius (courtesy) |
| cheese wheel, cheese wedge, round loaf (3 plain primitives) | own work, CC0 | |

* `market_goods.glb`: one mesh per piece (names in `pieces.json`, with triangle counts and sizes), no materials.
  Origin at the bottom centre ("base") or at the hanging point at the top centre ("top"); real-world metres,
  scaled up a little for chunky readability; decimated to <= 100 tris (small) / <= 260 tris (large).
* `market_goods_atlas.png`: 1024 px atlas shared by every piece. The four Quaternius trim sheets, tinted warm
  and saturated for the painted palette (the metal trim repainted as dull iron/brass) and tiled 3x3 so the
  trim UVs that repeat still sample the right texture, plus a white swatch for the flat-colour food.
  The per-piece colour is baked in COLOR_0 (linear).
* `source/` (gdignored, not imported): only the selected original glTF/FBX files and trim textures with the
  licence texts (`License_Standard.txt`, `License.txt`), for regeneration.
* Game side: `scripts/world/market_goods.gd` composes the pieces into per-theme layouts (one surface each);
  `SettlementBuilder._market_dressing()` places them as MultiMesh batches, never colliding.
