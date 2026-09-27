# Claude handoff: make the world feel physical and alive

This brief points to the evidence and proposes a safe implementation sequence. It is for the game implementation branch `claude/focused-curie-m09hbd`; the `gpt/natural-world-plan` branch contains documentation and review artifacts only. Do not merge a broad rewrite. Make each step a small change with a visible before/after result.

## Read these first

1. [Natural world feel plan](NATURAL_WORLD_FEEL_PLAN.md) — full system design, phased work, and acceptance checklist.
2. [Collision visual audit](COLLISION_VISUAL_AUDIT.html) and [method/notes](COLLISION_VISUAL_AUDIT.md) — current fitted building collider shapes and visible door/footprint issues.
3. [Collision facade review](COLLISION_FACADE_REVIEW.html) — four-sided views of the inn, blacksmith, healer house, and guild with current proxy dimensions overlaid.
4. [NPC route audit](NPC_ROUTE_AUDIT.html) and [method/notes](NPC_ROUTE_AUDIT.md) — static Ashford target segments crossing collider footprints.
5. [Locomotion speed review](LOCOMOTION_SPEED_REVIEW.html) and [findings](LOCOMOTION_SPEED_REVIEW.md), then [player blend-space audit](PLAYER_BLENDSPACE_AUDIT.html) — measured movement/clip mismatches.
6. [NPC gait phase review](NPC_PHASE_REVIEW.html) — visual demonstration of synchronized versus per-actor walk-cycle phase.
7. [Player impulse response review](PLAYER_IMPULSE_REVIEW.html) and [source notes](PLAYER_MECHANICS_RESPONSE_REVIEW.md) — calculated impact of applying a decaying knockback vector each physics tick.
8. [NPC life-loop design](NPC_LIFE_LOOP_DESIGN.md) — state priorities, goal anchors, physical movement ownership, and playtest matrix.
9. [World daily-rhythm review](WORLD_DAILY_RHYTHM_REVIEW.html) and [design notes](WORLD_DAILY_RHYTHM_DESIGN.md) — current job-group clock boundaries and a deterministic schedule-stagger design.
10. [Open-world pattern study](OPEN_WORLD_PATTERN_STUDY.md) — project patterns and source/license distinctions.
11. [Current playtest visual and movement review](CURRENT_RUN_VISUAL_REVIEW.md) — a reproducible camera obstruction, a clear line between static screenshot evidence and unverified NPC collision, and a focused moving-runtime capture matrix.
12. [Near-NPC follower and gait-state review](NPC_FOLLOWER_ANIMATION_REVIEW.html) and [source notes](NPC_FOLLOWER_ANIMATION_REVIEW.md) — interactive model of population-sliced gait selection and frame-dependent turn easing.
13. [Combat pressure and readability handoff](COMBAT_PRESSURE_AND_READABILITY.md) and [pressure-window viewer](COMBAT_PRESSURE_WINDOW_REVIEW.html) — source-backed diagnosis, encounter sequencing, fair hit validation, and acceptance checks. The interactive chart is a design model, not runtime evidence or a balance simulator.
14. [Godot 4.6 NPC navigation notes](NPC_NAVIGATION_GODOT46_NOTES.md) and [motion-pipeline review](NPC_MOTION_PIPELINE_REVIEW.html) — movement ownership, NavigationAgent/avoidance/physics distinctions, streamed map synchronization, and source-linked NPC collision failures.
15. [NPC behavior/animation transition design](NPC_ANIMATION_TRANSITION_DESIGN.md) and [interactive handoff viewer](NPC_TRANSITION_HANDOFF_REVIEW.html) — priority interruptions with safe switch-out, action cleanup, readable entry poses, and goal revalidation, informed by published Warhorse ambient-AI research.
16. [Locomotion phase and foot-contact design](LOCOMOTION_PHASE_AND_FOOT_CONTACT_DESIGN.md) — a post-QA walk/run phase-sync A/B, bounded TwoBoneIK foot-contact experiment, Blender/game-loader review strip, and measurable per-rig acceptance evidence.

## Baseline and evidence

The inspected gameplay baseline is commit `e8ad02de` on `claude/focused-curie-m09hbd`; the handoff branch was rebased onto Claude's then-current head `e3563fc4`. That later commit changes presentation/QA assets, not the player, villager, world simulation, critter, wolf, or settlement movement controllers reviewed for this plan. Refresh this comparison before implementing if the game branch has moved since `e3563fc4`.

The evidence identifies structural problems to address before adding lots of new behavior:

- 203 of 318 Ashford residents with a work target more than 12 m away have a direct target segment through a fitted building footprint (static geometry audit; not a runtime pathfinding test).
- Current building collision is generally one simplified box per fitted building; open doors, porches, and irregular shapes need authored profiles.
- Embodied villagers are `Node3D` instances moved directly toward simulation positions, without body collision or navigation. The player can therefore overlap them, and villagers can move through obstacles.
- The game QA report flags 54 of 62 measured gait/speed cases. Examples include player walk at 4.20 m/s against a 2.09 m/s blended clip, and villager walk at 1.60 m/s against a 0.98 m/s clip.
- Near/far population LOD is already the right performance boundary. Detailed physics and avoidance should apply only to nearby embodied actors.

These findings describe a baseline, not proof that every bug still reproduces on the latest game branch. Re-run the small relevant check before changing its system.

## Current Claude checkout and evidence snapshot

Checked 2026-09-27 (local evening): Claude's game checkout is still on `claude/focused-curie-m09hbd` at `e3563fc4`. Its working tree has generated QA and Blender-preview outputs, but no tracked gameplay-source edits were present at this check. The animation report was regenerated at 13:47 and still records 54 of 62 speed cases as failing; it is not evidence that a locomotion fix has landed. The report also documents the existing armored-boot weight repair, so do not redo that asset work without finding a regression.

The current playtest report lists a villager standing inside a house front and wolves clipping into the player during bites (`docs/qa/PLAYTEST_REPORT.md`, issue 13). Treat those as reported runtime failures with likely causes, not fully verified visual diagnoses: screenshot 16 is a plaza view, while screenshot 34 is heavily obscured by conifer branches. Reproduce both with collision shapes, NPC target/path, wolf root/body, and attack reach visible before accepting the reported cause. Preserve real doorways; do not fix either symptom by disabling collision or moving visible meshes away from their intended footprints.

Two newer raw benchmark rows were appended at 17:32: village LOW/Mobile measured 56.1 FPS average, 17.8 ms frame average, 42.8 ms p95, 235 draw calls, and about 292k primitives with 12 full NPCs; village HIGH/Forward+ measured 39.0 FPS, 25.7 ms average, 32.1 ms p95, and 948 draw calls with 24 full NPCs. These differ from earlier tables and are one short local run, so treat them as a fresh signal to reproduce, not a new device guarantee or proof that the performance pass is complete. Compare quiet-machine runs and inspect CPU time as well as GPU time before spending performance budget on more embodied actors.

Use Claude's current source and latest QA before each implementation step; these local files can change independently of the branch commit. Keep the game checkout untouched while preparing this documentation handoff. The navigation plan addresses the gap between visible NPC behavior and physical world contact; it does not duplicate the active animation/asset QA.

## Suggested first implementation slice

Start with a reproducible village doorway and crowd QA route, then fix the solid-world collision profiles that route exposes. This addresses the visible “walk through Meshy buildings” fault and creates a safe basis for navigation and NPC contact work.

1. Record the current player route through one open doorway, one wall corner, a stall/cart, and a fence. Capture normal play and collision debug shapes.
2. Inspect the actual asset footprints and entrances in the collision audit. Replace only the incorrect fitted collider profiles in this slice; use a few primitive shapes and preserve genuinely walkable openings.
3. Verify collision layers/masks for the player and static world. Keep camera queries on the world layer.
4. Repeat the route from both sides of each opening. Confirm that walls and props block, intended openings stay clear, and the player cannot get caught on eaves or invisible slabs.
5. Include before/after captures and a short list of assets/entrances checked with the change.

Do not add NPC physics bodies in this first slice. That is the next dependency: first establish that the player has reliable world collision, then add a capped near-NPC body tier and test yielding without pile-ups. Navigation comes after walkable collision/entrance profiles are reliable, so paths can represent the same world the player sees.

## Follow-up order

1. **World collision profiles:** complete the doorway/prop route and debug view above.
2. **Near-actor contact:** add physics bodies to a capped local NPC/animal tier; keep `WorldSim` as intent authority and synchronize positions only at explicit LOD/movement handoffs.
3. **Navigation and local steering:** route local agents around static obstacles, validate destinations, and handle streamed-region boundaries. Retain physical collision; avoidance alone does not stop penetration.
4. **Locomotion calibration:** tune per-rig clip speeds using measured velocity, then improve starts, braking, turns, combat transitions, and dodge recovery.
5. **Daily-life states:** add meaningful arrival, work, wait, yield, react, and departure behaviors with occupied interaction anchors and varied animation timing.
6. **Performance and regression pass:** compare LOW/HIGH frame timing and active body/agent counts on the same route.

For each step, update the plan's acceptance checklist and provide a screenshot or clip plus the measurement that demonstrates the result. Keep the game branch's scope to the smallest system needed for that step; this documentation branch does not change scripts, scenes, or `project.godot`.
