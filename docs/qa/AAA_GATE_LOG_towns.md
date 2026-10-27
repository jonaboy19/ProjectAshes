# AAA gate: towns worker (Ashford street / alley)

The towns worker's entries for `docs/qa/AAA_GATE_LOG.md`. Kept in a separate file so I don't collide with other workers' edits.

## 2026-10-27: Ashford street → alley fly-through, day and night (WIP, not for the owner)

- **Files:** `C:\Users\Jonna\Documents\PA_plans\videos\ashford_street_alley_day.mp4` and `ashford_street_alley_night.mp4` (Movie Maker, 1280x720, 30 fps, HIGH).
- **Contact sheets:** scratchpad `ashford_street_alley_day_sheet.png`.
- **Refs:** 05/08 (street closed by a landmark), 06/17 (dressing), 09/20 (night and stone lane), 11 (negative).

| Check | Result | Note |
|---|---|---|
| Street composition: enclosing building line, landmark closing the view, varied rooflines | FAIL | The main street is wide and open, with grass verges. No landmark closes the view; the chapel and bell tower are off-axis. Alleys are enclosed now, but the main street is not. |
| Dense dressing: signs, carts, laundry, flower boxes | PARTIAL | The alleys have laundry, woodpiles and lanterns. The main street has the original toy-scale crates and fruit baskets (close to negative ref 11). |
| Materials with PBR breakup, nothing flat | FAIL | Kit houses use a single vertex-colour material, which reads as warm flat wood with weathering noise rather than plaster, timber and thatch. Meshy hero buildings are fine. The CC0 real-scan materials (CC0_SLICE_KIT) are not applied yet. |
| Ground worn: ruts, mud, puddles, grass in cracks | PARTIAL | The cobbles are good. The verge transitions to grass are hard; there are no puddles and no mud at the edges. |
| Scale correct, nothing floats or clips | PASS | One exception: the camera brushed a kit roof corner in the alley. |
| Night: warm windows against a cool sky, lamps | FAIL | Alleys are lit now, but a blown-out patch on the inn porch is still there. It is pre-existing: it also appears with this pass disabled and on MEDIUM. It is not the omni light and not the bounce emission; the cause is still open. |
| No LOD pops, flicker or NPC pops | PASS (day) | Frame-difference spikes line up with camera turns only. |
| Camera doesn't clip, framed at walking height | PARTIAL | It follows the street graph now. One roof brush in a 1.6 m alley. |
| HUD / branding | PASS | HUD hidden. The loading screen now shows RISING ASHES. |
| Perf (HIGH / LOW) | measured | Ashford alley draw calls: 2152 HIGH (1972 before the pass), about 974 LOW. Occlusion culling was added after these numbers; its delta is not yet measured. |

**Verdict: FAIL. Do not send to the owner.** Next fixes, in my lane:
1. CC0 plaster, timber and roof materials on the kit, as a texture-array or atlas blend. The single vertex-colour material is the main flat look.
2. Replace the toy crates and baskets on the main street with the gated Meshy cart, well, crate stack and stall, plus the CC0 barrels.
3. Close the main street's view with a landmark and narrow it with frontage.
4. Mud and puddle decals at verges.
5. Find the cause of the inn night glare.

## 2026-10-27 · towns lane · Ashford slice route re-gate (same route, after steps 1-5) — FAIL (honest try; remaining list below)
Files (Movie Maker 1280x720 30 fps, HIGH, 0 script errors): PA_plans/videos/slice_ashford_street_final.mp4 (14:30), slice_ashford_street_night_final.mp4 (21:30), slice_ashford_interior_final.mp4 (13:00); tools_qa/towns_medieval/flythrough.gd --path=slice, interior_walk.gd. Refs 05/06/08/09/17/20.
| Check | Result | Note |
|---|---|---|
| Main street composition (05/08) | PASS (partial) | frontage + narrowed street, chapel on the axis closes the view; waiting on the refined church tower / gate from props_refined/buildings to replace the chapel |
| Materials, no flat colour (06/17) | PASS main street / FAIL edge | CC0 timber, plaster, slate, cobble on the kit and hero houses; the edge kit houses (end of the route) still read pale beige planks, nearly self-lit at night |
| Dressing supports focal points (06/17) | PASS (partial) | Meshy/refined cart, well, crate stacks, stall, CC0 barrels/pots replace the toy props; no toy baskets on the route |
| Ground: mud, puddles, grass in cracks (09/20) | PASS (partial) | verge mud decals + cobble cracks; puddles only by the wet map |
| Night (09/20) | PASS (partial) | inn porch glare FIXED (street_benchmark door-lantern emission decal 3.0 -> 0.5); warm windows vs cool sky; FAIL: tiled cloud pattern in the night sky reads repetitive; one fully black frame where the camera enters a building at the edge |
| Camera | FAIL | brushes through NPCs and a wall corner on the side street; one frame inside a building at night |
| NPCs | FAIL (NPC lane) | faceted low-poly villager bodies at close range next to the realistic props |
| Interior (scenario-A house) | FAIL | CC0 detail now on walls/floor, but walls read grey stone instead of limewashed plaster, flat blue-grey daylight, windows flat white panes |
| Beds (for the NPC lane) | PASS | interior kit beds now use the smart-object bed frame: Life_Mz_Sleep_Bed lies on the mattress (scenario house: 4 sleepers at 23:30, inn loft: 2), headboard lowered to 0.55 m |
**Verdict: FAIL. Not sent to the owner.** Remaining, in order: (1) edge kit-house plaster/limewash + night exposure, (2) interior plaster tone + warm window light, (3) camera path clearance (NPC + wall avoidance), (4) landmark swap when the refined tower/gate lands, (5) night sky cloud tiling (sky owner), (6) NPC bodies (NPC lane).

## 2026-10-27 · towns lane · Ashford slice re-gate 2 (real world, shared grade) — FAIL (closer; list below)
Files: PA_plans/videos/slice_ashford_street_v4.mp4 (14:30), slice_ashford_street_night_v4.mp4 (21:30), slice_ashford_interior_v5.mp4 (13:00); all `--world_macro=real --terrain_backend=terrain3d` (the slice world), Movie Maker 1280x720 30 fps HIGH, 0 script errors.
| Check | Result | Note |
|---|---|---|
| Grade / sky consistency town vs country | PASS (partial) | town now records under the countryside AgX grade + sky; town timber/roof/cloth albedo -25% saturation toward grey-brown (Style G TOWN_DESAT). Sky HDRI swap is the world worker's (in progress) |
| Camera path | PASS (partial) | root cause found: in the real world the plaza was an NPC routing island (stalls on street mouths and on the well ring) so the route cut through houses; fixed for every town (plaza->street partial routes 260 -> 7 segments). Remaining: brushes standing stones / a kit-house corner at the lane end; NPCs within 1.6 m hidden for the shot |
| Night | PASS (partial) | kit houses no longer self-lit (bounce/rim emission x0.12 after dusk); warm lamps vs cool sky; no black frames |
| Interior | PASS (partial) | review camera now films with the room's own Environment (it used the outdoor grade: that was the blue-grey); VoxelGI baked at entry + ReflectionProbe + thin volumetric haze (HIGH); weathered limewash walls (worn_mossy_plasterwall, soft), plank floor. Still: flat light-wood furniture boxes, plain window panes |
| Street ground | FAIL (world lane) | streets/plaza read as meadow in the real world: the Terrain3D instancer put grass on them; world worker fix in progress |
| View closer | FAIL | B28 stone chapel (pr_chapel) wired + occluder, but the slice camera looks at the plaza bell tower; chapel placement on the real-world main-street axis not yet confirmed on screen |
| Edge kit houses (poor lane) | FAIL | still pale plank/plaster boxes next to the hero houses |
| NPCs / crowd impostors | FAIL (NPC lane) | faceted bodies; grey-blue distant impostors |
| UI restraint | FAIL (UI lane) | "ASHFORD RING" world sign board and nameplates: core/nameplates.gd + main.gd:1062 station labels (not towns code) |
**Verdict: FAIL. Not sent.**
