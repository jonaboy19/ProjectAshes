# Region 1 look pass: the Ashford Vale (Valencious)

Owner ask (2026-09-30): "work on region 1, how it looks, build whatever you think is right; make sure there is a valley somewhere, and other unique things." No magic or VFX: the world itself.

Evidence lives in `docs/regions/look/` (before/after pairs, the valley reveal, a walk-in frame sheet, fps logs).
Tools: `kingdom/tools_qa/region1/look_capture.gd` (one boot, many free-camera views + a perf line each, `--r1off` A/B),
`bake_valley.gd` (terrain stamps), `bake_biome.gd` (biome map), `asset_sheet.gd` (asset contact sheets).

## 1. Survey verdict (22 views, before)

Contact sheet: `look/before_sheet.jpg`. Read against `docs/art/reference/00_MAIN_kingsreach_gate_market.webp` and the Valencious poster panel.

| What | Verdict |
|---|---|
| Villages (Ashford lane) | Good: warm timber, flowers at every base, saturated sky. Closest to the reference. |
| **The world past 256 m** | **The worst problem.** The streamed ring ends and the ground stops: every aerial or hill view shows a flat blue void under the horizon, towns float on a green disc, Kingsreach (440 m away) is invisible from the Ember Road, and there are no mountains on the skyline. The poster is all layered distance. |
| Terrain shape | A uniform rolling carpet of 20-40 m hills: no valley, no cliff, no landmark silhouette anywhere in the 4 x 4 km core. The upper Ashrun (the future valley) ran across a flat plain. |
| Ground colour | One lawn green everywhere. No fields, no heather, no river greens; the poster's patchwork of gold and green fields is missing. Hills read as bare yellow-green blankets. |
| River-carve bug | Rectangular plateaus with 2-4 m cliff edges beside the Ashrun (`08_north_hills_aerial`): the river levee rose away from the water (fill slope 0.14 < bank slope 0.18) and stopped at the RIVER_CELL grid. |
| Trees from above | Far trees are X-shaped cross cards; from any raised camera the forests look like scattered crosses. |
| Light | 16-18 h (the "golden hour") already has a navy sky: the sky energy followed the sun's elevation down, so afternoon views look like dusk. |
| Landmarks | None that read from afar. Sites are small (a farm, a wayshrine); nothing to walk toward. |
| Empty | Meadows between villages: grass tufts only, no hay, fences, stones or paths. |

## 2. What was built

### The valley: Hollin's Reach
The upper Ashrun (from its source at (-150, -900) down to the Ashrun Bridge) is now a deep green river valley, 780 m long:
- **Shape**: a baked terrain stamp (`data/region1/terrain/hollins_reach_design.json` -> `hollins_reach.res`) adds 0-105 m to the ground: a sheer west wall (rim 60-94 m), a cirque at the head with a notch for the falls, an east wall that turns into **terraced fields** in its lower half, and a mouth that opens onto the meadow at the Ashrun Bridge. The floor is left untouched, so the river, its levels and fords stay the game's own.
- **Hollin Falls**: a ribbon that hugs the real cliff profile (built from WorldGen heights at load), a plunge pool carved by the stamp, foam at the base.
- **The Stone Gap** (the reveal): the path from Greyseam climbs the outside of the east rim; at the top two dark ward-stones frame a notch and the whole valley opens: the falls to the right, the river winding away, the ruined village on the terraces.
- **Hollin's Reach Ruins**: three abandoned ivy houses, a small stone chapel, the well, broken walls, a scarecrow and hay on the terraces, **forty graves** in four rows, and the cut ward-stone leaning at the village edge.
- **Hollin Watch**: a stone watchtower with a red banner on the west rim above the falls.
- **The Old Span**: a stone arch bridge across the river below the ruins.
- **Cliff kit**: 620 warm limestone rocks laid along the stamped faces (MultiMesh cells), and the faces themselves painted as stone.
- **Hollin's Gate**: walls pinch into a gorge 150 m above the Ashrun Bridge, so walking in from the south the valley opens all at once with the falls at its end (walk-in frames: `look/walkin/`).
- **Erosion**: the stamp gets a gully/scree detail pass from dandrino terrain-erosion-3-ways (MIT, `tools_qa/region1/erode_valley.py`, the tool the coordinator installed), applied on the walls only (+-7 m high-pass).
- Story tie: this is Tamsin Reeve's village, left outside the ward-line when young Lieutenant Bram pulled its pin (STORY_R1 Act IV Crownstead, Act V). Hooks: `docs/regions/HOOKS_FOR_CLOUD.md`.

### Landmarks
| Landmark | Where | What | Gameplay hook (for the cloud) |
|---|---|---|---|
| **The Drowned Bell** + **Emberglass Ferry** | Emberglass Mere (-446, 318) / west shore | the belfry of the old town Ashford rose out of, standing in the lake; a lantern-lit ferry landing (pier, rowing boat, ferry hut, lamps that light at night) | ferry crossing as a travel node; Kindling Night lanterns float to the bell; diving/fishing spot |
| **Crownstead Mill Hill** | (430, -190) | a levelled round hill (stamp) with three crown windmills (sails turn), banners, granary, hay, white fences; the Crownstead Elder Stone on the crown | Act IV Crownstead (two ash layers, route to Kingsreach); harvest festival hub; a beacon visible from the Ember Road |
| **Stagborn Glade** | (-1345, -1062), NW woods | a flower meadow in the forest ringed by nine standing stones, the fallen Glade Elder Stone, the Hollow Oak shrine (26 m) | Act III/IV Glade and the Antlered Warden arena; stagborn herd gathering point |
| **The Wyrm's Ribs** | (-60, -1700), north of Highwatch | the bones of a frost-horned giant beast on a raised whaleback ridge (new Blender kit, `assets/incoming/region1/landmarks/`) | Highwatch oath site; Frostcrown tease; apex danger beyond |

### Region-wide
| Change | How |
|---|---|
| **Far horizon** | `Region1Horizon`: the whole 8 km world as one 58k-tri mesh outside the streamed ring (discarded under it), plus 30k painted canopy domes (30 tris) in 512 m cells. Mountains, valley walls and forests now fill the skyline. |
| **Biome colour + field patchwork** | `bake_biome.gd` -> `assets/incoming/region1/terrain/biome_map.png` (R farmland, G heather, B lush river, A dry gold); `shaders/region1/biome.gdshaderinc` tints the grass and draws rotated blocks of wheat, green, barley, ploughed and flax fields with hedgerow seams, in the terrain shader and on the horizon. |
| **Warm stone** | Terrain rock layer tinted warm and lighter (was grey-green). |
| **Golden hour** | `main.gd` `_update_daylight`: sky energy, ambient and fog colour stay bright until sunset (3 lines). |
| **River-carve fix** | `world_gen.gd`: levee fill slope 0.14 -> 0.32 (1 number): no more rectangular plateaus. |
| **Trails** | Dirt paths painted from data (`terrain_stamps.json` trails): Greyseam -> Stone Gap -> valley floor -> Old Span -> Ashrun Bridge, and to the falls. |

## 3. Hot-file edits (all one-liners, commented "Region1 look")
| File | Change |
|---|---|
| `scripts/world/world_gen.gd` | `Region1Terrain.setup()` in `setup`; `return Region1Terrain.stamp(...)` at the end of `height`; `return Region1Terrain.paint(...)` at the end of `color_at`; `* Region1Terrain.tree_keep(...)` at the end of `forest_density`; river levee fill slope 0.32. |
| `scripts/world/region_sites.gd` | append `Region1Landmarks.sites()` after the academy (ids of every earlier site unchanged). |
| `scripts/world/region_dressing.gd` | `add_child(region1_look.gd.new())` at the end of `_ready`. |
| `scripts/core/main.gd` | `sky_amount` in `_update_daylight` (golden hour). |
| `shaders/terrain.gdshader` | include `region1/biome.gdshaderinc`, 2 lines to apply it, 1 line warm rock. |

## 3b. Two valleys, one region (decision, 2026-09-30)
The cloud built **the Hidden Vale** (`scripts/world/hidden_valley.gd`, commit eadbfd71) while this pass built **Hollin's Reach**. They do not overlap and are kept as two distinct places:
| | Hollin's Reach | The Hidden Vale |
|---|---|---|
| Where | upper Ashrun, (-205, -660), 700 m from Ashford | far west, (-2040, 40), 2 km from Ashford |
| Shape | open river valley, 780 m long, cliffs 60-100 m, falls at the head, terraces, gorge gate at the mouth | enclosed bowl behind a rim, one S-bend slot 6-7 m wide |
| Role | public story place: Tamsin's abandoned village, forty graves, the cut ward-stone (Acts IV-V); on the map | secret: found by rumours and a burnt map fragment; the dream settlement site; off the map until found |
| Tech | terrain stamp as data (`Region1Terrain`, applied after all shaping) | shape function inside `_raw_height` |
Shared: both use the Region1Look presenter (ValeLook extends it), the cliff-rock kit and `mesh_floor()` seating, the terrain shader stone and strata, and the biome map (the vale is baked lush). The Hidden Vale cave "Hollin Falls Grotto" (`region_caves.gd`) sits behind Hollin Falls, tying the two together.

## 3c. Hidden Vale fixes (handoff item 2, "2026-09-30 cloud -> local")
| Bug | Cause | Fix |
|---|---|---|
| Boulders floating in the gorge | rocks sat on the exact WorldGen height; the rendered 2 m grid runs well below it on a sheer wall | `Region1Look.mesh_floor()` seats every cliff rock on the lowest mesh vertex of its footprint (`vale_look.gd` line ~90, and the Hollin's Reach kit) |
| Floating strips in the herb-patch view | flat leaf-litter / moss cards laid horizontally on slopes | `TerrainStreamer.slope_basis()` tilts `floor/` cards to the ground normal (`_plan_floor`), same in `HiddenValley._put` |
| Void past the terrain ring in the last cutscene frame | the flyover looks 300 m past the frozen player, whose ring was the only one streamed; the far canopy domes hovered over the gap | the vale sequence streams around the flyover (`Engine.set_meta("stream_focus")`, read by `main.gd` for terrain/water focus); the horizon only gives way where a chunk is really built (built-chunk mask); domes sit on the horizon grid |
| Gorge walls plain | the grey-green scan read olive, and leaf litter/path blended into steep faces | terrain shader: sandstone hue for the rock layer, steep faces drop litter/path weights, strata bands; rocks seated on the walls |
| Ground a bit olive | the biome map (baked before the vale) painted dry gold there; the vale compensated with 30 % leaf litter | biome map re-baked vale-aware (lush, no dry/heather/fields); vale litter blend 0.3 -> 0.1 |
Proof: `look/vale/*_before.jpg` / `*_after.jpg`, `look/vale/sheet_before.jpg`, `sheet_after.jpg`. Still open: gorge walls read smooth up close (a proper rock-face kit with LOD1 is in the backlog); far horizon rims are soft at 48 m.

## 4. Proof
| | |
|---|---|
| Survey before / after (22 views) | `look/survey_before_sheet.jpg`, `look/survey_after_sheet.jpg`, pairs `look/<view>_before.jpg` / `_after.jpg` |
| The valley | `look/v1_reveal_stone_gap.jpg` (reveal), `v2_falls_from_floor.jpg`, `v3_valley_aerial.jpg`, `v4_mouth_up_valley.jpg`, `v5_ruins_terraces.jpg`, `v6_approach_ridge.jpg`, `valley_hillshade.png` |
| Walk-in (Movie Maker, 30 fps, 2 fps sheets) | `look/walkin/sheet_*.png` |
| Landmarks | `look/l1_drowned_bell_ferry.jpg`, `l2_crownstead_hill.jpg`, `l3_stagborn_glade.jpg`, `l4_wyrms_ribs.jpg` |
| Map | `look/map_parchment_after_1024.jpg`, `map_valley_zoom.jpg` (before: `map_valley_zoom_before.jpg`); the game sheet `kingdom/assets/ui/maps/region1_parchment.png` (2048 px) |
| Performance | `look/PERF.md` (A/B with `--r1off`, HIGH and LOW) |
| QA boot test | `tools_qa/boot_flow/boot_flow.gd` with `BOOT_FLOW_SKIP=1`: BOOTFLOW OK |

## 5. Look-dev plan (next)
See the backlog in `docs/STATUS_LOCAL.md`. In order of value:
1. Far towns: roof clusters / impostors of Kingsreach and the towns on the horizon mesh (Kingsreach is still invisible past 440 m).
2. Replace the X-card far trees of the streamed ring with the canopy domes (one visual language near and far).
3. Terraces: crop scatter (wheat, cabbage) on the treads; lanterns on the graves on Kindling Night.
4. Field scatter near villages: hay bales, fence lines along the patchwork seams (MultiMesh by the biome map).
5. Erosion detail on the valley walls (dandrino erosion over the stamp window: the export/detail path exists in `bake_valley.gd`).
6. Elden Arches (ruined aqueduct on the Elden Road) and a lantern line along the ferry crossing.
