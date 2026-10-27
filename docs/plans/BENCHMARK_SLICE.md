# Benchmark slice — the only priority until it looks finished (owner, 2026-10-27)

Owner verdict on the latest videos: movement and combat look like "AI slop"; the player and NPCs feel regressed; no real motion. Coordinator watched scenario_a: player swings in place facing away from the bandit, the bandit isn't engaged, paper debris flies, loading screen shows the wrong "Total Showdown" branding, popups/markers dominate. Metrics improved; the footage did not. From now on **quality is judged by eye on the same recorded route**, metrics are secondary.

## The slice (nothing else gets visual work until this is right)
1. **One street** in Ashford (market square → side street), **one interior** (the house/tavern used in scenario A), **one short countryside route** (Ashford edge → field wall → copse → bandit camp on the Kingsreach road).
2. **One finished player character**: coherent model, proportions, equipment, materials, camera framing at gameplay distance.
3. **Core movement**: idle → start → run → turn → stop, then slopes and ladder. Weight, pelvis motion, arm balance, varied gait (not one repetitive exaggerated cycle), planted feet, believable starts/stops/pivots. Ladder: hands/feet on rungs, full top-out with weight transfer.
4. **One complete interaction**: approach an NPC, talk, attack, believable reaction, leave — with anticipation → contact → reaction → recovery, NPC turning/spacing, camera and UI behaviour.
5. **Terrain/vegetation on the countryside route authored, not scattered**: worn paths, clusters along walls/fences, bare soil, clearings, tree groups, a landmark/view.
6. **Lighting/exposure and materials** tuned on this route (no flat-colour props: shield, ladder, platform).
7. **UI restraint**: names/markers/alerts/glow rings appear only when needed, small, never over a performance.
8. **Perf** measured on this route (HIGH and LOW/iGPU).

## Acceptance (every worker, every change)
Record the **same route** before and after with Movie Maker (same resolution, time of day, camera), make a contact sheet, **look at it**, write an honest one-paragraph visual verdict (what still looks bad), then the numbers. Never report a metric win while the footage looks wrong. The coordinator watches every video before it goes to the owner.

## Lanes
- Player worker: items 2, 3 (+ ladder), camera.
- Combat-motion worker: item 4 (fight part), NPC combat responses.
- Towns worker: street + interior dressing, materials, UI markers in town (coordinate), lighting in town.
- World worker: countryside route item 5, lighting/exposure outdoors.
- Video QA worker: records the slice route after every push, contact sheets, issue list per lane, and also fixes NPC idle/walk/crowd motion on the slice.
- Everything else (other cities, 32 km expansion, new systems) pauses for visual work; cloud code tasks continue.
