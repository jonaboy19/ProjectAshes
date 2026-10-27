---
name: ashes-aaa-gate
description: MANDATORY quality gate for everything in Rising Ashes - nothing is called done, committed as finished, or sent to the owner (video, screenshot, clip, model, town, terrain, UI) until it passes this AAA check against the owner's reference images. If it fails, fix it (or keep fixing) instead of sending. Use before every report, every SendUserFile, every "done", and when choosing/making any asset.
---

> **Mandatory for every task (owner rules, 2026-10-28):** (1) `ashes-best-tool-first` — use every fitting Godot built-in, installed addon, external tool (Blender, ffmpeg, Meshy, Mixamo, Poly Haven/ambientCG CC0) and cloud offload instead of hand-rolling; (2) `ashes-aaa-gate` — nothing is done or sent until it passes the AAA gate against `docs/plans/ref_aaa/`. The game is **PC-only** (min-spec: regular PC, possibly integrated GPU); ignore any mobile/phone wording below.

# AAA gate (owner rule, 2026-10-28)

Owner: "Before you send me the video check if it's AAA quality first ... only make things on AAA quality, fix things if they're not AAA quality." The owner judges by eye against KCD2, Assassin's Creed, Bellwright, Manor Lords, Blight. Metrics never override the eye.

## The rule
0. **Best tools used?** (owner, 2026-10-28: "always use all the built-in tools and external tools"). Before and after the work, run `ashes-best-tool-first`: Godot 4.6.3 built-ins (Movie Maker, SpringBone, PhysicalBone, IK modifiers, LookAt, root motion, occlusion, LOD, LightmapGI, volumetric fog, decals, MultiMesh…), installed addons (Terrain3D, ProtonScatter, Phantom Camera, LimboAI, Sky3D, Road Generator…), external tools (Blender + Python, ffmpeg, gltfpack, Meshy, Mixamo, Poly Haven/ambientCG CC0) and cloud offload. If a better tool exists for the job and wasn't used, that's a FAIL: redo it with the tool. State in the gate log which tools were used.
1. **Look first.** Contact sheet (one frame per 0.5 s) + 3 full-res stills of the worst moments (`ashes-video-review`). Never judge something you haven't seen.
2. **Put it next to the closest reference** in `docs/plans/ref_aaa/` (list below). Build a side-by-side image (ffmpeg `hstack`) and look at both.
3. **Score every checklist line below** that applies: PASS / FAIL + one sentence. Be the harshest reviewer in the room: "would a player think this screenshot came from the reference game?" If no → FAIL.
4. **Any FAIL → don't send, fix.** Fix in your lane or hand it to the owning worker with the exact frame and the fix. Re-record the same route and re-gate.
5. Only send when all applicable lines pass. If the owner explicitly asks to see work in progress, send it labelled **WIP** with the FAIL list on top — never present a FAIL as finished.
6. Write the gate result (date, file, PASS/FAIL table) into `docs/qa/AAA_GATE_LOG.md`.

## Reference board (`docs/plans/ref_aaa/`)
| # | What it shows | Use as the bar for |
|---|---|---|
| 01 | KCD2 country road: rutted dirt road, puddle, tall grass edge with flowers, grouped tree masses, layered haze, soft cumulus sky | countryside route, terrain/paths, vegetation, sky, exposure |
| 02 | Ladder climb (Elden Ring): hands grip rungs, alternating limbs, body tight to the ladder, rope-lashed rungs | ladder, climbing |
| 03 | Sword duel: wide bent-knee stances, weight forward, blades actually meet, shields raised, dust, rim light, crowd | combat poses, contact, spacing, VFX |
| 04 | KCD mounted: rider seated with reins, horse gait with planted hooves, NPC mounting | horses, mounting |
| 05, 08, 09, 18, 19 | Streets with a landmark closing the view (gate, castle, tower), timber-framed upper storeys, overhangs, varied roof heights | town street composition |
| 06, 17 | Cobbles, carts, hanging laundry, banners, flower boxes | street dressing |
| 07, 10, 16 | Walled town and castle from above, dense roofs, organic streets | town layout, overview shots |
| 09, 20 | Night lamps and a real stone lane: warm windows against a cool sky, wet cobbles, hanging shop signs, ivy, plants by doors | night lighting, materials, alleys |
| 11 | **Negative**: flat untextured market stalls, empty street | what NOT to ship |
| 12, 14, 15 | Bellwright village: wattle fences, thatch, dirt paths, small HUD in corners, NPCs on paths | villages, HUD restraint |
| 13 | Manor Lords in snow: cloak cloth motion, snow on roofs, mud path | snow biome, cloth |
| 16 (low-poly horse) | **Negative** for characters: toy, low-poly look | character/model style |

## Checklist
**Motion (player, NPC, creatures)**
- Feet planted on contact with no sliding or floor sinking, visible weight shift through the pelvis, arms counter-swing, gait not robotic or overly bouncy.
- Starts, stops and turns have anticipation and settle (no snapping or instant 180°s); blends under about 0.2 s with no pops.
- Combat: wind-up → contact → follow-through → recovery. Blades and fists reach the target, the target reacts in the hit direction, attackers face and close distance, stances are wide and bent-kneed (ref 03).
- Ladders and props: hands on rungs, handles and tools; the item is held in the hand and doesn't float; clean top-out (ref 02).
- Cloth, cloaks and hair have secondary motion where present (ref 13).
- NPCs never pop in or out on screen; no T-poses; no idle crowds frozen in sync.

**World and towns**
- Ground reads as worn and used: ruts, mud, puddles, grass breaking through cobbles, soft transitions at edges (refs 01, 20). No uniform single-texture ground.
- Vegetation is clustered and authored (along walls, fences and road edges, groups of trees); no even random scatter.
- Streets are composed: an enclosing building line, a landmark terminating the view, varied heights and rooflines, overhangs, alleys (refs 05, 08, 18).
- Dense dressing: signs, carts, barrels, laundry, flower boxes, ivy, lamps, banners (refs 06, 17, 20). No empty plazas (ref 11).
- Materials have PBR breakup (dirt, wear, roughness variation); nothing flat-coloured or untextured; no texture stretching or obvious tiling.
- Scale is correct (doors 2.1 m, people 1.75 m); nothing floats or clips.

**Light, camera, UI**
- Exposure is natural with no blown sky or crushed shadows; aerial perspective and haze give depth (ref 01); warm/cool contrast at night (ref 09).
- Shadows are stable (no acne, no peter-panning); no LOD popping or flicker.
- Camera is framed at gameplay distance and doesn't clip into walls.
- HUD is small and in the corners, and markers appear only when needed (ref 14). No debug text, wrong branding or placeholder labels in footage.

**Assets (generated, downloaded or built)**
- Style is grounded stylised-realism (`docs/plans/ART_DIRECTION.md`), never toy or low-poly (negative ref 16).
- Fits min-spec: a sensible triangle count with LODs, and textures ≤2K (1K for props).
- Licence is OK (CC0/CC-BY/MIT; `ashes-open-source-sourcing`), and Meshy outputs are logged.
- Looked at in-game, in context, at gameplay distance, next to its neighbours.

**Tech**
- Zero errors in the log during the recording; perf is measured (HIGH and LOW tiers).
- A runtime config dump (terrain backend, quality tier, resolution) is printed in the recording log.

## Meshy budget rule
The owner allows unlimited Meshy use as long as **at least 200 credits stay unspent**. Check `meshy_check_balance` before every batch, and stop at 200.
