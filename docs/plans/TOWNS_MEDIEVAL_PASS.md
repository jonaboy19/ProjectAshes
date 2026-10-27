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

---

## 5. Medieval city anatomy (c. 1150-1450, reference cities)

Reference set: Rothenburg ob der Tauber (walled Franconian trade town, intact circuit, Plönlein fork, Markus tower = older inner
wall), Carcassonne (double curtain wall, barbicans, Cité on the hill + Ville Basse grid below), York (Shambles, Snickelways,
Minster close, Micklegate Bar, Ouse staithes), Bruges (canals, Markt + Belfry + Cloth Hall, Burg square with the count's
buildings, beguinage), Prague (Old Town Square + town hall, Judengasse, Charles Bridge with mills on the Vltava, castle hill),
Kutná Hora / KCD2 Kuttenberg (mining town: Italian Court mint, St Barbara, smelters and slag heaps at the edge, miners' quarters
on the slopes). Common anatomy, as rules the generator and the art follow:

| Element | How it really worked | Where / how it looks |
|---|---|---|
| Walls, gates, toll | Curtain wall with towers every 40-60 m, gatehouse with portcullis and a toll house; the gate is also the customs, the watch and the market's mouth. Older inner wall lines often survive as streets. | Gate square just inside, toll booth, guard post, wagons queuing; wall walk; tower roofs conical or pyramidal |
| Suburbs (faubourgs) | Outside each main gate: inns for those who arrive after curfew, stables, smithies, tanneries, potteries, the poor, the lepers' house, gardens and orchards. Often bigger than the walled core. | Low, poor, irregular, mud, sheds, fences, livestock along the approach road |
| Market square | Widened street or square at the crossing of the main roads; market cross or well in it, pillory; the town hall / guildhall, the weigh house and the richest merchants' houses face it; arcades in southern Germany / Bohemia. | Paved, stalls by day, the tallest facades, stepped / crow gables in stone towns |
| Town hall, guildhalls, weigh house | Town hall with a council chamber over an open trading hall, bell tower or belfry; guildhalls of the rich guilds on the square or their street; public scales (weigh house) by the market. | Stone, tracery, painted coats of arms, clock |
| Churches | Cathedral or main parish church with its churchyard (burials, a cross, a charnel house) beside the market; several small parish churches across town; chapels at gates and bridges. | The tallest silhouette; graveyard walls, yews |
| Monastery / friary | Friars (mendicant orders) inside the walls near the poor, often by the wall; older Benedictine houses outside. Cloister, gardens, hospital. | Long walls, a cloister garth, a gatehouse |
| Castle / keep | The lord's seat on the high point or the river bend, with its own wall, often a separate jurisdiction (castle ward). | Bailey, keep, chapel, stables, barracks |
| River: bridges, mills, quays | Stone bridge with a chapel or tower, mills on the river or a mill race (grain, fulling, saws), quays and warehouses (staithes), fish market by the water. | Waterwheels, cranes, barrels, boats |
| Craft quarters | Trades clustered by street (the street takes their name): smiths and armourers near the gates (fire risk, horses), butchers' shambles (narrow street, overhanging upper floors, gutter down the middle), tanners and dyers downstream / downwind at the edge (stink, water), potters and tile makers at the edge (kilns), coopers, weavers, bakers spread out. | Smoke, racks of hides, dye vats, coloured water, kilns |
| Inns, taverns, bathhouse | Inns at the gates and on the market with a stable yard behind a carriage arch; taverns everywhere (sign: a bush or a tankard); a public bathhouse (often of ill repute) by the water. | Hanging signs, yard arches, benches outside |
| Bakehouse / communal oven | Lords' or town ovens where households baked their dough for a fee; also the brewhouse. | Domed oven, smoke, firewood stack |
| Water | Wells in squares and yards, public fountains (stone basin, later), horse troughs at gates and inns, water carriers. | Well heads with roofs, troughs |
| Justice | Pillory / stocks on the market, gallows outside the walls on a hill by a road (visible deterrent), town jail in a gate tower. | Gallows hill on the approach |
| Hospital, almshouse | Hospital (often of the Holy Spirit) near a gate or the river, almshouses, lepers' house outside. | Long hall with a chapel end |
| Foreign / minority quarter | Merchant colonies (Hanseatic Kontor, Italian merchants) and Jewish quarters with their own street, synagogue, baths and gate. In Valencious lore: an **Aurelis (Solmarch) merchants' court** in the eastern towns and a **steppe caravan court** at Harrowgate fit; no real-world religion is imported. | Walled court, foreign colours |
| Plots | Burgage plots: narrow street frontage (3-8 m), long and deep; house at the street, workshop / yard / garden / privy / pigsty behind; back lanes along the rear. Rich plots merged into wide frontages. | Continuous facades, gable or eaves to the street, back gardens visible from above |
| Streets | Hierarchy: main street (6-10 m) from gate to market, side streets (4-6 m), alleys and passages (1-2.5 m, the Snickelways / Durchgänge), dead-end courts, back lanes. Organic, following old paths and the ground. | Overhanging jetties make streets darker and narrower above |
| Ground | Paved only in the market and main streets of rich towns (late); mud, straw, dung and planks elsewhere; open central gutter (kennel) in the street; the poor quarter is mud. | Mud and straw at edges, central gutter, puddles |
| Signs, street life | Pictorial hanging signs, shop shutters folding down into counters, livestock in the streets (pigs!), laundry between windows, refuse at the back, criers, water carriers, beggars at church doors. | Laundry lines, pigs, carts, refuse |

### 5.1 What Rising Ashes has vs what is missing

| Element | Have | Missing -> action |
|---|---|---|
| Walls / gatehouse / towers | yes (stone, palisade, low, hedge by identity) | toll booth + queue at the gate (later), gallows hill (Meshy list) |
| Suburbs outside gates | `_gate_outskirts`, `_homesteads` | **poor hovel suburb along the gate road** (this pass: hovel kit; placement next) |
| Market square + well | yes (plaza, well, stalls, gate market) | market cross / pillory (Blender, small), weigh house (Meshy list) |
| Town hall / guildhall | guild hall, courthouse (manor) | belfry town hall (Meshy list) |
| Church + churchyard | temple / chapel / bell tower | churchyard wall + graves (Blender, small) |
| Monastery | - | Meshy list |
| Castle / keep | Kingsreach castle, Highwatch keep | - |
| River bridges, mills, quays | bridges, region mills, pier, Saltwick | town quays + warehouses (Meshy list) |
| Craft quarters | district system (craft, market, poor, inn, military, admin), smithies, district props | tannery racks, dye vats, kilns (Blender props, next) |
| Inns / taverns | inn, tavern lots, stables | bathhouse (Meshy list) |
| Bakehouse | bakery lot (town kit) | communal oven (Blender prop) |
| Wells / troughs | well, water trough | fountain basin for rich towns (Blender) |
| Justice | - | stocks + pillory (Blender, next), gallows (Meshy list) |
| Hospital / almshouse | healer house | almshouse (reuse long hall) |
| Narrow burgage plots, alleys | **this pass**: small house kit + alley network + quarter-aware frontage | back gardens / privies behind plots |
| Poverty | **this pass**: poor houses (patched, sagging, boarded), hovels with lean-tos, dirty plaster, mud alleys | refuse heaps, pigs, laundry across alleys (props exist: washing_line, woodpile) |

**Meshy list (no credits spent; owner decides):** belfry town hall, weigh house, bathhouse, monastery gatehouse + cloister
range, gallows, quay warehouse with crane, market cross with steps.

---

## 6. National identity vs regional variety

**Valencious national kit (everywhere, so every town is clearly one country):**
- Roof language: steep pitch 50-55 degrees, gable to the street, jettied upper floors on burgher houses, stone chimney stacks.
- Heraldry: House Caldrenn crown red (#9E2B25) and gold (#D8B04A) on the royal posts (gate, keep, guard post); each town adds its
  own two colours (`town_identity.json` `banner`) on banners and awnings, never instead of the crown at the gate.
- Church typology: Church of the Dawn Throne = west tower with a shingled / slate spire, limestone ashlar, lancet windows;
  village chapels with a bell-cote; the old runestones and Elder Stones stand outside, revered, never inside the church.
- Guildhall typology: stone ground floor with an open arcade, timber hall above, guild sign on a bracket.
- Signs: pictorial iron brackets with painted boards (tankard, anvil, loaf, mortar), the realm's coin (crowned sun) for money
  changers.
- Street furniture: timber cross-post lanterns (this pass), roofed well heads, stone horse troughs, braziers at gates.

**Per-city signatures (materials / palette / layout):**

| Type | Towns | Signature |
|---|---|---|
| Capital | Kingsreach | Castle on the rise, double wall, cathedral, wide paved main street, royal red-gold everywhere, rich stone centre, big suburbs |
| Hill fortress | Highwatch (Highcliff), Ravenscar | Terraced streets, grey granite and slate, keep visible from every street, small windows, smoke-black chimneys |
| River / guild town | Silverford (Ironmarch), Millbrook, Eastmere | Bridge with a chapel, mills and quays, guildhalls on the square, timber frames over river-stone |
| Port | Saltwick, Blackwater, Duskwater | Piers, net racks, salt-bleached boards, teal / slate, fish market, warehouses on the water |
| Steppe caravan town | Harrowgate, Thistledown | Palisade, caravan court, low whitewashed houses, red tile, felt awnings, horse lines |
| Mining town | Skarholm, Coldharbor, Hollowmere | Slag heaps and smelters at the edge, miners' rows (narrow poor houses), dark stone, iron palette |
| Marsh town | Westfen, Brackenmoor, Stonehollow | Houses on stone plinths / stilts, heavy reed thatch, boardwalks, moss (the regional damp map makes roofs green) |
| Upland village | Dunhallow, Marrowick | Drystone, turf and shingle, longhouses, sheep folds |
| Heartvale village | Ashford, Oakvale (Greenhollow) | Thatch, limewash, green, runestone ring, mills |

---

## 7. Owner reference sets per city (docs/plans/ref_towns/ref_N.jpg, numbers as on disk; contact sheet work/towns_medieval/refs_sheet.jpg)

| City / type | Reference set | What to match |
|---|---|---|
| Ashford (ground level, first priority) | 28, 41, 31 | KCD village path: dirt lane, timber and log houses, wattle fences, gardens, dovecote, NPCs walking |
| Ashford / villages (aerial) | 3, 35, 25 | small palisade ring, thatch cottages packed inside, fields beyond, manor |
| Dense town streets (Millbrook, Eastmere, Silverford, Wolfsend) | 1, 39, 21, 9 / 30, 5, 45 | jettied half-timber canyon, laundry across the street, carts, stairs to doors, signs, church spire as focal point |
| Dense town from above (all towns) | 6, 33, 4 / 38 | tight clusters, mixed slate / shingle / thatch / tile roofs, clock towers, dirt streets between plots, many small huts inside the palisade |
| Kingsreach (capital) | 43, 27, 11, 13, 19 | Carcassonne double wall + round towers, suburb outside, heraldic banners, gate with statues, cathedral at golden hour |
| Highwatch / Highcliff, Ravenscar (hill fortress) | 18, 10 | stone hill town packed under the keep, grey stone, arcades |
| Saltwick, Blackwater, Duskwater (ports) | 2 / 40, 7 | Dubrovnik: sea wall, terracotta packed solid, harbour, suburbs outside; lakeside castle with docks and ships |
| Harrowgate, Thistledown (steppe / caravan, foreign quarter) | 22, 26 | bazaar with rugs, pottery, awnings; red stalls, bunting, clock tower |
| Stone alleys, poor quarter, night mood | 8 / 44, 16, 14, 15, 17, 20 | cobbled stone alley with hanging signs and plants; wet cobbles and decayed plaster; lantern-lit night alleys with warm windows |
| Northern towns (Frostmere, Coldharbor, Highwatch winter) | 12, 32 | snow on roofs and streets, A-frame timber, open market stalls |
| Landscape around towns | 37, 42, 46, 47, 48 | rolling meadows with wildflowers, castle on a hill as a skyline landmark (battle content is for the war system) |
| Lakeside village under cliffs | 23, 24 | church on the shore, cliffs behind (Hollowmere / Eastmere) |
