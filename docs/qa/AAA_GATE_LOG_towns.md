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
