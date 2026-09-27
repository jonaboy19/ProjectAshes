# Claude handoff: make the world feel physical and alive

This brief points to the evidence and proposes a safe implementation sequence. It is for the game implementation branch `claude/focused-curie-m09hbd`; the `gpt/natural-world-plan` branch contains documentation and review artifacts only. Do not merge a broad rewrite. Make each step a small change with a visible before/after result.

## Read these first

1. [Natural world feel plan](NATURAL_WORLD_FEEL_PLAN.md) — full system design, phased work, and acceptance checklist.
2. [Collision visual audit](COLLISION_VISUAL_AUDIT.html) and [method/notes](COLLISION_VISUAL_AUDIT.md) — current fitted building collider shapes and visible door/footprint issues.
3. [NPC route audit](NPC_ROUTE_AUDIT.html) and [method/notes](NPC_ROUTE_AUDIT.md) — static Ashford target segments crossing collider footprints.
4. [Locomotion speed review](LOCOMOTION_SPEED_REVIEW.html) and [findings](LOCOMOTION_SPEED_REVIEW.md), then [player blend-space audit](PLAYER_BLENDSPACE_AUDIT.html) — measured movement/clip mismatches.
5. [NPC gait phase review](NPC_PHASE_REVIEW.html) — visual demonstration of synchronized versus per-actor walk-cycle phase.
6. [Player impulse response review](PLAYER_IMPULSE_REVIEW.html) and [source notes](PLAYER_MECHANICS_RESPONSE_REVIEW.md) — calculated impact of applying a decaying knockback vector each physics tick.
7. [NPC life-loop design](NPC_LIFE_LOOP_DESIGN.md) — state priorities, goal anchors, physical movement ownership, and playtest matrix.
8. [Open-world pattern study](OPEN_WORLD_PATTERN_STUDY.md) — project patterns and source/license distinctions.

## Baseline and evidence

The inspected gameplay baseline is commit `e8ad02de` on `claude/focused-curie-m09hbd`; the handoff branch was rebased onto Claude's then-current head `e3563fc4`. That later commit changes presentation/QA assets, not the player, villager, world simulation, critter, wolf, or settlement movement controllers reviewed for this plan. Refresh this comparison before implementing if the game branch has moved since `e3563fc4`.

The evidence identifies structural problems to address before adding lots of new behavior:

- 203 of 318 Ashford residents with a work target more than 12 m away have a direct target segment through a fitted building footprint (static geometry audit; not a runtime pathfinding test).
- Current building collision is generally one simplified box per fitted building; open doors, porches, and irregular shapes need authored profiles.
- Embodied villagers are `Node3D` instances moved directly toward simulation positions, without body collision or navigation. The player can therefore overlap them, and villagers can move through obstacles.
- The game QA report flags 54 of 62 measured gait/speed cases. Examples include player walk at 4.20 m/s against a 2.09 m/s blended clip, and villager walk at 1.60 m/s against a 0.98 m/s clip.
- Near/far population LOD is already the right performance boundary. Detailed physics and avoidance should apply only to nearby embodied actors.

These findings describe a baseline, not proof that every bug still reproduces on the latest game branch. Re-run the small relevant check before changing its system.

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
