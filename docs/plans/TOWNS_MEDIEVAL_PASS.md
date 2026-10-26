# Towns medieval pass (architecture and town art, 2026-10-26)

Owner ask: "work on all buildings, city etc. to give them more of a medieval look and make them better lore-fitting."
References: KCD2 (Rattay / Kuttenberg), Bannerlord towns, AC Unity / Valhalla villages, `PA_plans/ref_videos/` (Unreal medieval
town, anime half-timbered towns). Code: `scripts/world/settlement_builder.gd` (lots, plaza, gate market, lamps), `city_planner`
(layout), `town_identity.gd` + `data/world/town_identity.json` (per-town culture / palette / roof mix / layout / wall),
`style_g.gd` + `shaders/style_lab/lab_polished.gdshader` (every building surface), `region_dressing.gd` / `region_sites.gd`
(farms, mills, ruins), `house_details.gd` / `district_props.gd` (per-lot attachments), `village_features.gd` (green, chapel, mill).

Screenshots: windowed `tools_qa/town_identity/town_sheet.gd` (1600x900, HIGH, 15:00), never headless.
Committed copies (JPEG): `docs/qa/towns_medieval/before_<Town>_<view>.jpg` and side-by-side `docs/qa/towns_medieval/<Town>_<view>_before_after.jpg`.
Full-size PNGs stay local in `work/towns_medieval/{before,after}/` (not committed).

---

## 1. Survey (before)

Rating: 1 = breaks the medieval read, 3 = generic but acceptable, 5 = reference level.

| Settlement | What reads non-medieval / generic / off-lore | Rating | Shots |
|---|---|---|---|
| **Ashford** (heartvale village, file: thatch 0.8) | Main street is good (jettied half-timber inn, hanging signs, carts, crates). Problems: every wall and roof is factory-clean (no moss, soot, sun-fade, rain grime at the true foot); the red-tile and green-slate heroes dominate a village whose lore mix is 80% thatch; the Ashford windmill is a flat-colour toy (teal shingle roof on stilts, blank plaster, no texture); aerial: one long strung street of free-standing houses with lawn between them, no church tower in the core, no enclosing hedges/fences per croft. | 3 | `before_Ashford_street.jpg`, `before_Ashford_air.jpg`, `before_Ashford_feature.jpg` |
| **Highcliff / Highwatch Keep** (slate_cool, terraced, stone wall) | Church is a clean red-brick Victorian-Gothic block (brick bond, pointy pinnacles); the plaza ring has cast-iron lamp posts on dressed stone plinths (19th-century street furniture); the healer house carries a bright green pharmacy cross (modern); plaza is a huge empty cobble disc (no well/cross/market life in the middle); wide grass gaps between houses instead of continuous facades. | 2 | `before_Highcliff_street.jpg`, `before_Highcliff_air.jpg` |
| **Harrowgate** (steppe edge, radial) | Houses stand as isolated 3-4 storey towers around a bare dirt plaza with wide lawns between them: reads as a scattered suburb, not a trading town at the Harrow Arch; no wall/palisade or caravanserai yard although it is the steppe gate; tall town houses in a frontier place. | 2 | `before_Harrowgate_air.jpg`, `before_Harrowgate_street.jpg` |
| **Millbrook** (rift marches, file: thatch 0.55) | Good hero cluster (guild hall, tower, market). Problems: very wide bare dirt street with lawn verges and no facades along it; ivy is flat paper-square cards (reads low-poly); flower boxes and fruit baskets are toy-scaled and over-saturated; a timber-frame tower house on the hill reads like a dovecote toy. | 3 | `before_Millbrook_street.jpg` |
| Stonehollow, Saltwick, Marrowick, Kingsreach | not captured this pass (the sheet run is ~2 min per town with three other agents' Godot instances); same building kit and shader, so findings 1-4 below apply | - | - |

Cross-cutting findings (all settlements):

1. **Age** (highest impact, every frame): no moss, lichen, soot or sun-bleach on roofs; grime started at the MultiMesh batch origin, not at each house's ground, so on sloped lots the dirt band floated or vanished. **Fixed this pass** (section 3).
2. **Street furniture anachronisms**: cast lamp posts on plinths (plaza rings of every town), pharmacy cross (healer texture). Plaza lamps **fixed this pass**; the cross is baked into the Meshy healer atlas (gap).
3. **Density**: towns read as houses on a lawn. Medieval towns are continuous facades on narrow burgage plots, back gardens behind, open space only at the market / church / well. Gap (CityPlanner `layout` change, needs owner OK because it moves lots, doors and saves).
4. **Repetition**: 16 Blender village houses + 5 Meshy types per town; identical copies are obvious when they weather identically. Per-building age in the shader now breaks this (section 3).
5. **Farms / mills** (region kit): flat colour primitives (barn, granary, windmill) next to textured Meshy houses: two art styles in one frame. Gap: re-texture the RG_* region kit or swap to Meshy farm buildings.

---

## 2. Architecture style guide (lore-based)

Canon: one realm, the **Kingdom of Valencious** (House Caldrenn, culture `caldric`) for all 30 settlements; the Aurelis
Patriarchate (Church of the Dawn Throne) lies east beyond the Eastern Gate; the Zephyr Steppe / Solkar beyond the south.
Faith: the Dawn Throne church + the old runestone / Elder Stone ward network (pre-church, still revered). Era target: high
medieval (13th-14th c.), Central-European (KCD2) rather than Tudor.

### 2.1 Wealth tiers (centre -> edge)

| Tier | Where | Walls | Roof | Storeys / silhouette |
|---|---|---|---|---|
| Hovel / cottar | edge, outside the wall, marsh | wattle-and-daub on a fieldstone sill, crooked posts | thick thatch, hipped, low eaves to 1.8 m, smoke hole or short clay chimney | 1, long and low, lean-tos |
| Peasant croft / longhouse | village core, farms | close-studded oak timber frame, daub limewash (cream, ochre, raw) | thatch (heartvale, westfen), oak shingle (forests, uplands) | 1-1.5, byre end, dormer in thatch |
| Burgher / craftsman | town streets | stone ground floor (shop, arched opening + shutters), jettied timber upper floors | shingle or clay tile; slate in the north | 2-3, jetty 0.4-0.6 m per floor, gable to the street, chimney stack |
| Merchant / guild | market square | dressed stone, tracery windows, carved bargeboards, painted plaster | slate or glazed tile, stepped / crow gables | 3-4, arcade on the square |
| Church / keep / walls | centre, rise | ashlar + rubble core, buttresses, lancet windows, no brick (brick is rare and late in the Caldric heartland) | slate or lead, spires shingled | tower = tallest silhouette in every town |

### 2.2 Regions (palette, material, signature)

| Sub-region (settlements) | Walls | Roofs | Palette | Signature |
|---|---|---|---|---|
| Heartvale (Ashford, Kingsreach, Greenhollow, Crownstead) | oak frame + limewash, honey fieldstone sills | thatch villages, red tile + slate in Kingsreach | honey, cream, oak brown, faded crown red/gold | runestone rings, watermills, crown banners |
| Westfen Marsh (Westfen, Brackenmoor, Stonehollow) | timber on stone plinths / stilts, reed-daub | deep reed thatch, heavy moss | moss green, peat brown, grey | boardwalks, eel traps, punts, damp foot moss |
| Rift Marches (Millbrook, Eastmere, Greywatch) | rubble stone + timber, palisades | shingle, slate | sand, grey, rust | watchtowers, scarred ground, fortified farms |
| Northern Ridge / Ironmarch (Highwatch, Ravenscar, Coldharbor, Hollowmere) | grey granite, small windows, thick walls | slate, steep pitch, snowboards | slate blue, iron grey, frost white | keeps, smoke-black chimneys, mining gear |
| Silverrun / Thornwold (Silverford, Wolfsend) | timber frame, river stone | shingle | green, silver-grey | guild halls, bridges, river quays |
| Greywood / Emberfall (Emberfall, Saltwick, Blackwater) | log + plank, salt-bleached boards on the coast | shingle, slate | plum, teal, bleached wood | net racks, smokehouses, piers |
| Dunhallow Uplands (Dunhallow, Marrowick, Skarholm) | drystone, turf | turf + shingle | umber, ochre, iron | longhouses, sheep folds, cairns |
| Harrowgate Steppe Edge (Harrowgate, Thistledown, Duskwater) | whitewashed rammed earth + stone, low | red tile, flat-ish pitches | whitewash, terracotta, plum | caravan yards, felt awnings, horse lines, the Harrow Arch |

### 2.3 What every settlement needs (by size)

- **Hamlet**: well or spring, 3-8 crofts with fenced garden plots, wayshrine or runestone, woodpile per house.
- **Village**: + chapel with bell-cote, smithy (open forge, quench trough), alehouse, mill (water or wind), green with a well, tithe barn / granary, pound, stocks.
- **Town**: + church with tower, market square with market cross or covered hall, inn with stable yard, guild hall, bakery, tannery and dyers downstream / downwind at the edge, town wall with gatehouse and toll, almshouse.
- **Castle / capital (Kingsreach)**: + keep, curtain wall with towers, barbican, great hall, chapel, stables, smithy, garrison barracks, cathedral.

### 2.4 Set-dressing rules

- Clutter clusters at doors and in yards, never evenly: barrels + sacks at shops, woodpile + chopping block at every home, laundry lines between upper windows in poor streets, hay and carts at farms and gates.
- Signs are pictorial (boot, loaf, anvil, mortar, tankard), never letters only, never modern symbols (crosses as pharmacy marks, plus signs).
- Light at night: tallow-orange windows (not white), lanterns on timber posts or wall brackets, braziers at gates; no cast-iron street lamps.
- Banners: heraldry of House Caldrenn (crown red / gold) in royal places; town colours (`town_identity.json` `banner`) elsewhere.
- Ground: mud and straw at the edges, cobbles only in the market and main streets of towns, worn path lines to every door.

### 2.5 Performance rules

All building variety goes through shared materials (one Style G shader, parameters per role), MultiMesh per model and cell, per-instance variation in the shader (instance origin hash) or MultiMesh instance colour. No new materials per house, no per-lot nodes beyond colliders, no new shader variants (new effects are uniforms in `lab_polished`).

---

## 3. Implemented this pass

1. **Age in the building shader** (`shaders/style_lab/lab_polished.gdshader`, `style_g.gd` `AGE_MOSS` / `AGE_FADE`):
   - moss and lichen on up-facing pitches (roofs, sills, wall caps), on the north-facing wall foot and a damp band at the ground, broken by the world-projected weather noise;
   - sun-fade on roofs (bleached, greyed tile / slate / thatch);
   - a per-building age 0.35-1.35 from the instance origin hash (static-merged batches: a 50 m world cell), so two copies of the same house weather differently;
   - grime / damp now start at each building's own foot (`MODEL_MATRIX[3].y`) instead of the MultiMesh node origin.
   Same shader and render modes: no new pipeline variants, ~20 ALU and one texture tap more on building pixels.
2. **Plaza lamps**: the cast lamp post on a stone plinth around every plaza is now the Meshy timber cross-post with two hanging lanterns (`mf_lamp_post_timber_cross`, already used by the AAA benchmark street); its two lantern glows replace the single one.

Result (windowed, HIGH, 15:00): `Highcliff_street_before_after.jpg` (timber cross-posts with hanging lanterns instead of cast plinth lamps; moss on the church slate and on the house roofs, red tile faded), `Millbrook_street_before_after.jpg` (moss on the guild hall and tower roofs), `Highcliff_air_before_after.jpg` / `Millbrook_air_before_after.jpg` (candy-blue and red roofs now read weathered; per-house variation visible). Tests: test_market_dressing, test_town_identity, test_technique_vfx, test_town_kit: 62 cases, 0 failures. Perf: no new materials, nodes, draw calls or shader variants; same MultiMesh batches.

## 4. Remaining gaps (ordered by impact)

1. Town density / burgage plots and continuous facades (CityPlanner layout; moves lots -> owner OK + save check).
2. Highcliff church: brick Victorian look -> ashlar re-texture or replace with a stone church model.
3. Healer house pharmacy cross baked into `assets/incoming/ai3d/meshy/healer_lod*_*.jpg`: paint a mortar-and-pestle sign over it (needs the UV island; the green test also hits the plants).
4. Region farm kit (barn, granary, windmill, coop): flat colour; re-texture (Blender, Poly Haven wood / plaster / thatch, CC0) or swap to Meshy farm buildings.
5. Per-region moss strength (marsh wet, steppe dry): needs a per-town parameter path (instance colour alpha is taken by baked VAO).
6. Harrowgate: caravan yard + palisade + low whitewashed houses instead of tall town houses.
7. Night: confirm window emission colour is tallow orange in every house type (no night capture this pass).
8. Wide streets with lawn verges (Millbrook, Harrowgate, Highcliff plaza): needs mud/straw ground paint at the verge and facades closer to the street (layout).
9. Paper-card ivy and toy-scale flower boxes / fruit baskets (house_details): swap to denser ivy meshes and smaller, desaturated goods.
10. Moss strength is one value per role across the realm; the aerial view of Highcliff is slightly dark-green on every roof: tune per region once a per-town parameter path exists (gap 5).
