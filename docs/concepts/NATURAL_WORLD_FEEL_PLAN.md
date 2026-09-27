# Rising Ashes: natural world feel plan

**Status:** implementation handoff for Claude  
**Scope:** implementation handoff. This branch adds documentation, visual review artifacts, and one explicitly non-integrated animation experiment; it does not edit game scripts, scenes, or project settings.  
**Gameplay baseline inspected:** `e8ad02de` on `claude/focused-curie-m09hbd` (Godot 4.6). **PR rebased onto current Claude head:** `e3563fc4`; intervening commits update store/sky/character appearance assets, not the movement, NPC, or animation-controller scripts reviewed here.

## Goal

Make movement, combat, crowds, animals, buildings, and daily routines feel connected to one physical world. The player should read weight and intent in motion; feet should agree with ground speed; actors should route around solid geometry; nearby people should notice, yield, stop, and resume naturally; and buildings should block where their visible structure is solid while keeping real doors and walkways usable.

Keep the systems that already give the game its scale: `WorldSim` remains the inexpensive source of population and schedule intent, `PopulationLOD` controls who gets an embodied model, `SettlementBuilder` builds streamed settlements and batches meshes, and the existing player/combat/animation systems remain the starting point. Improve them in small, measurable steps. Do not turn the whole population into physics bodies or replace the world simulation wholesale.

## Current baseline and specific causes

These findings come from reading the current source and QA report, not from guessing at the screenshots:

| Area | Current implementation | Likely player-visible result |
|---|---|---|
| Player locomotion | `kingdom/scripts/actors/player.gd` uses `CharacterBody3D.move_and_slide()`, but blends horizontal velocity toward a target with a single fixed factor. Walk/run/block/attack/dodge all change speed abruptly or by fixed multipliers. | Starts, stops, direction changes, slopes, and combat transitions can feel slippery or abruptly damped. |
| Player animation | `CharacterAnimator` blends idle/walk/run from horizontal speed and overlays block/one-shot attacks. | The basic layering is already there, but it needs speed calibration, start/stop/turn behavior, and more state-aware transitions. |
| Villager bodies | `WorldSim` stores position and moves simulated people toward a target in slices. Near villagers are `Villager : Node3D`; `_process()` moves the model directly toward that stored position. They have no physics body or collision shape. | Player and villager models can overlap/pass through one another. They also do not navigate around buildings. |
| Crowd LOD | `PopulationLOD` keeps a limited number of nearby characters as full models; farther people are MultiMesh impostors or data only. | LOD is the right scalability foundation, but only the embodied tier can collide or animate in detail. Do not promise contact behavior for distant sprites. |
| Buildings | `SettlementBuilder` places a single `BoxShape3D` per lot, 80% of the model bounds in X/Z and full model height. Building visuals are batched separately. | A box ignores a door opening, porch, arch, thin wall, or irregular footprint. It can block an entrance or leave a corner visually exposed. |
| Small props | A separate builder path also uses simple box footprints for some props. | Stalls, carts, clutter, fences, and decor need deliberate choices about which objects stop the player and which are visual-only. |
| Navigation | No runtime `NavigationAgent3D` use was found in the game scripts. The Terrain3D addon includes editor support for baking navigation regions, but that is not evidence of a runtime route system being used by NPCs. A static Ashford audit found that 203 of 318 residents with a work target more than 12 m away have direct target segments crossing current fitted building collider footprints (63.8%). | Scheduled targets can be reached by straight-line travel through buildings and other obstacles. The [interactive route audit](NPC_ROUTE_AUDIT.html) shows every flagged segment; its method and limits are in [NPC_ROUTE_AUDIT.md](NPC_ROUTE_AUDIT.md). |
| Animals | `Critter` moves directly over terrain and explicitly documents “No physics or navigation.” | Animals can cross props/buildings and can overlap one another or the player. |
| Gait | `docs/qa/anim_qa_report.md` measures the current player walk at 4.20 m/s against a 2.09 m/s blended clip speed (2.01 ratio); villager walk at 1.60 vs 0.98 m/s (1.64); player block at 2.10 vs 0.63 m/s (3.32). The report flags visible skating for these cases. | Foot motion and travel distance disagree, so otherwise good clips still look fake. |
| Character awareness and state transitions | The player adds a `LookAtModifier3D` only when a rig has a bone named exactly `head`; villagers use `AnimationPlayer` and switch directly between `Walking_A` and `Idle`. No shared near-NPC stateful blend tree or look-at behavior is used. | People can move and animate without reacting to the player, settling into an activity, or turning their attention naturally. |

The first fixes should address those structural causes. Adding more animations, more NPCs, or more random wandering before movement and collision work will make the same faults more visible.

## Design rules

1. **One authority per actor.** A near embodied actor follows physics movement. The simulation gives it intent and receives its final position when it changes LOD or completes a movement step; it must not continually overwrite the physics body position while that body is moving.
2. **Collision and avoidance are different.** Physics shapes prevent bodies from passing through each other and the world. Navigation paths route around static geometry. Local avoidance steers moving agents before contact. None substitutes for the other.
3. **Only nearby actors need full physical behavior.** Keep far inhabitants in data and impostors. Enable detailed collision and active avoidance only for the local tier, with a small configurable cap and budget measurements.
4. **Use simple, intentional collision.** Do not use high-detail render meshes as the default physics shape. Use authored primitive/compound shapes for actors, buildings, and interactive props. Use concave trimesh collision only for static environment geometry where it is appropriate and profile it.
5. **Animation follows actual motion.** Feed measured horizontal velocity into locomotion. Use in-place locomotion while physics owns movement; consider root motion only for explicitly tested cinematic or attack moves.
6. **Make world actions readable.** NPCs should visibly approach a destination, slow down, orient, interact, and leave. Avoid instant target jumps, idle crowds sliding in place, and identical perfectly synchronized loops.
7. **Protect the mobile budget.** No blanket physics or avoidance on the entire simulated population. Measure low and high quality tiers in the settlement benchmark.

## Work plan

### Phase 0 — Lock a reproducible baseline

Before changing behavior, record a short repeatable route through the village and a representative fight. Capture the same camera view and settings after each phase. Record current frame-time percentiles and counts for full NPCs, sprites, colliders, and active navigation/avoidance agents.

Add temporary or opt-in debug views during implementation: physics collision shapes, navmesh, actor target/path, desired and actual velocity, animation state/blend value, and actor LOD. Keep diagnostics out of normal play and remove or disable them before the final delivery.

**Done when:** a reviewer can replay the same player route and crowd scene on LOW and HIGH, see the relevant collision/path data, and compare before/after captures and measurements.

### Phase 1 — Make geometry agree with what the player sees

Start with the [Meshy collision visual audit](COLLISION_VISUAL_AUDIT.html) and its [findings](COLLISION_VISUAL_AUDIT.md). The orange boxes reproduce the current simple collider approximation at fitted game scale and flag the openings/covered spaces that need a runtime walk-through.

Create a small asset collision profile keyed by the existing building/prop asset key. Keep render meshes and collision profiles separate. For each common asset, inspect its visible silhouette, intended entrances, eaves/awnings, porch, stairs, and pass-through openings. Prefer a few boxes/capsules in local asset space; use a C-shaped or segmented wall profile around an open doorway. Rotate the profile with the same lot yaw and align its base with the existing fitted model bounds.

Prioritize the inn, blacksmith, healer, adventurer guild, common houses, market stalls, gates, fences, carts, and door clutter. Large buildings should block walls and foundations, not the empty doorway. An entrance used by the player must have a clear approach wider than the player capsule plus a small side margin. An open building entrance can either be a real opening into a supported interior or be clearly closed; do not leave a solid invisible slab across a visible open door.

Add explicit collision categories for world solids, player, local NPCs, and interaction triggers. Give each physics object a deliberate layer and mask rather than relying on defaults. Keep camera collision queries on the intended world layer so an NPC does not pull the camera in unexpectedly.

Props need a simple data choice: `solid` (barrels, carts, walls), `trigger_only` (doors, service spots), or `visual_only` (small clutter/foliage). Avoid giving every decorative pebble an individual collider.

**Done when:** from both sides of the entrance, the player can use every intended door/arch; the player cannot cross a wall, stall counter, fence, or cart that is visibly solid; no collider blocks an empty opening; and collision debug shapes match the approved profiles.

### Phase 2 — Give the player and close crowd coherent contact

Keep the player on `CharacterBody3D`. Tune a capsule to the standing footprint and maintain consistent collision through age scaling and dodge. Ensure player layer/mask sees static world and local NPC bodies. During a dodge, preserve intentional movement and invulnerability rules without disabling world collision.

For the near NPC tier only, add a lightweight physical body with a capsule and a physics-step movement controller. Start with the current closest/near always tier, then profile before raising its cap. Give agents a soft personal-space radius for steering plus a smaller physical capsule; this prevents visual shoulders from needing full capsule-width gaps. Use controlled yielding: ordinary villagers step aside from the player, face the disturbance briefly, and resume; guards may hold their post; crowds near a stall form a loose queue rather than pushing into a single point.

Avoid deadlocks with a simple escalation ladder: slow down, wait briefly, sidestep to a nearby reachable point, then request a new route. Do not force actors through a collision or teleport them through a blocked wall to resolve a crowd jam. When two equal-priority agents meet head-on, deterministic small left/right preferences can prevent mirrored indecision.

Animals can follow the same pattern at a lower fidelity: simple body/collider and local steering for only nearby animals, while distant animals stay cheap or are not instantiated. Large animals need wider radii and should yield differently from chickens.

**Done when:** in repeated approaches, the player and visible people never pass through each other; actors do not jitter, pin the player, or remain frozen in a doorway; and pushing into a crowd does not create a physics pile-up.

### Phase 3 — Route agents through the streamed world

Use Godot's existing NavigationServer and `NavigationAgent3D` for nearby route-following actors rather than inventing a custom global pathfinder. First establish where navmesh data is authored/baked for the actual streamed settlement and Terrain3D chunks. Ensure navigation covers streets, paths, yards, and intended entrances, while excluding walls, roofs, inaccessible interiors, deep water, and out-of-bounds areas.

For each local actor, set a destination only when its intent changes; query the next path point and update movement from `_physics_process`. Feed wanted velocity through local avoidance where needed, then move the body using the returned safe velocity. Keep the capsule physics collision active regardless of avoidance. Repath only when a destination becomes unreachable, the actor is stuck, or streamed navigation changes. Snap/validate new goals onto reachable navmesh before committing them.

Treat streamed-region boundaries as joins, not gaps: adjacent nav regions need matching maps and compatible bake settings, and agents must wait or request a route when the next chunk is not ready. Keep a deterministic fallback (wait or choose a nearby reachable point) rather than reverting to straight-line movement through an obstruction.

Avoidance is not free. Enable it for actors currently close enough to meet, not all 20,000 population rows or all impostors. Use low-frequency intent/path updates and profile crowd caps. For crowd flow at larger scale, stagger target changes and use local avoidance sparingly.

**Done when:** a villager walks around a house to its front door, routes around a stall row, reaches a target on the other side of a wall only through a valid path, and handles a chunk boundary without snapping through geometry.

### Phase 4 — Calibrate animation and movement as one system

Start with the [locomotion speed review](LOCOMOTION_SPEED_REVIEW.html), the [player blend-space audit](PLAYER_BLENDSPACE_AUDIT.html), and the [prioritized findings](LOCOMOTION_SPEED_REVIEW.md). The current game-loader QA reports 54 failing speed cases out of 62; player blocking, villager catch-up, and wolf stalking are the most obvious examples. The player audit isolates a concrete mismatch: the tree blends 80% walk at the 4.2 m/s player walk speed because its walk point is derived from half of the 7 m/s run speed, despite the walk clip measuring about 0.98 m/s.

The [27-profile knockback retarget review](HIT_KNOCKBACK_RETARGET_REVIEW.html) is a concrete example of why a source-rig improvement cannot be accepted from one mannequin: the prototype reduces reference-rig floor penetration but still leaves severe failures across avatar profiles and worsens the worst planted-foot slip. The matching incoming GLB is marked as an experiment and must not replace the shared gameplay alias as-is.

Start from the existing `CharacterAnimator`, `AnimationTree`, UAL aliases, and QA harness. Build a per-rig locomotion calibration table for walk, jog/run, strafe, and backward movement. Compare clip ground speed and planted-foot slip to actual movement at the rig's in-game scale. Use the existing QA report as the baseline and target a game-speed/clip-speed ratio of **0.85–1.18** for ordinary locomotion, then review clips visually for contact quality. The current player walk, blocking walk, and villager walk are clear first targets.

Separate acceleration, braking, and turning response from animation blending. Use measured body velocity, not raw input, for the blend. Add or tune transitions for idle → start → walk → run, run → stop, pivots, strafing, backing up, block locomotion, hit reaction, attack recovery, and dodge recovery. Use turn-in-place or a controlled pivot when the requested direction differs sharply from facing. Crossfade state changes without restarting a clip every frame. Preserve the existing upper-body attack layering where the clip/rig supports it; validate bone filters per skeleton family.

Review the [player impulse response audit](PLAYER_IMPULSE_REVIEW.html) before changing attack lunge or hit recoil. The current player controller adds its decaying `_impulse` vector to horizontal velocity on every physics tick. Decide whether each use means a one-time velocity kick or a delta-scaled acceleration, keep melee lunge separate from received/block recoil, and compare the current 60 Hz response against collision and combat captures before tuning.

Use animation events or authored normalized hit windows for combat contact rather than allowing visual swing timing to drift from fixed damage timers. Keep hitbox activation, recovery, cancel windows, stamina cost, and movement lock visible in the move definition. Dodge displacement must agree with the dodge clip and still stop at walls. Camera shake and hit-stop should reinforce a confirmed impact and scale by hit strength, not fire on a miss.

Build a reusable clip acceptance matrix for player, villager rigs, guards, enemies, and animals: ground penetration, planted-foot slip, loop seam, pose pop, bone stretch, facing/heading, and playback-speed match. Repair bad retargets or select a better clip; do not hide broken gait by changing every actor to one unnatural speed.

Only after the base pose and weights are sound, evaluate secondary motion for rigs with verified single bone chains (hair, tails, or a small cloak chain). Godot 4.6's `SpringBoneSimulator3D` provides inertial wavering, stiffness/drag/gravity controls, and optional spring-bone collisions. This can add follow-through to close hero and selected near-NPC rigs; it cannot repair the documented stretched skirt/foot weights, and it should not run on every distant resident. Check state changes and LOD promotion/demotion; fade or reset the spring simulation after abrupt clip changes so it cannot kick into an unstable pose. Profile the near-actor cap on LOW and HIGH.

**Done when:** calibrated locomotion stays inside the target speed ratio, visible foot sliding is reduced in the recorded route, attacks land on their authored impact moment, and motion blends continuously across start/stop/turn/combat without fighting physics.

### Phase 5 — Make daily life read as intention, not random motion

Keep `WorldSim` responsible for schedules and target intent. Improve local travel and presentation without making all inhabitants expensive. Add small, deterministic variation to arrival time, path choice, facing, pauses, and animation phase so crowds do not march in lockstep. Make work, market, home, guard, and rest targets meaningful and reachable. A person marked indoors should disappear only after reaching a real entrance/service point; do not visually vanish while still standing outside.

Give local NPCs a compact state model such as `travel`, `arrive`, `work`, `socialize`, `wait`, `yield`, `react`, and `leave`. Each state owns its locomotion/idle choice and can be interrupted by higher-priority events (player collision, danger, dialogue). Add small actions where they strengthen existing world systems: look at a passerby, nod, step around the player, pause at a counter, carry a crate between a workplace and storage, tend a nearby field, sit at a bench, flee from danger, or regroup with a guard squad. Reuse the existing job, market, settlement, and animal data instead of creating parallel schedules.

Use interaction anchors around counters/doors/benches with approach points, facing direction, occupancy limits, and a graceful fallback if occupied. The actor should arrive, turn, blend into an activity, hold it for a plausible interval, then depart. Audio/footsteps should follow actual surface and speed; use restrained foley for steps, cloth, tools, market ambience, animals, and doors after the underlying timing is correct.

**Done when:** watching one market/work/home cycle for several in-game minutes shows understandable routine, spacing, interruptions and recovery, with no crowd orbiting a blocked goal or sliding through a building to simulate being indoors.

### Phase 6 — Tune the whole feel and protect performance

Run the same route in a quiet village, crowded market, building doorway, uneven terrain, shallow water, and combat encounter. Tune walk/run speeds, acceleration/braking, rotation rates, stopping distance, body radii, avoidance horizons, camera lag/collision, impact timing, and footstep volume together. Test keyboard, gamepad, and touch input; keep equivalent movement response across devices.

Compare LOW and HIGH tiers. Track physics time, frame-time p50/p95, full-body NPC count, active avoidance-agent count, collider count, and navmesh update time. Reduce agent activation radius or cap, stagger work, or simplify profiles before lowering the visual population that already works. Streamed settlement teardown must free local bodies, path agents, and callbacks cleanly.

**Done when:** the route and benchmark are at least as stable as baseline on supported targets, performance remains within the game's existing budget, and the improvements are visible on both desktop and mobile quality presets.

## Suggested implementation order for Claude

1. Add collision/path debug tooling and create a reproducible doorway + crowd test scene or QA route.
2. Fix building/prop collision profiles and verify the player's existing collider against them.
3. Add close NPC body collision and prove player/NPC contact without jitter or piles.
4. Make near agents follow valid navigation paths and yield around obstacles; then apply the same low-cost pattern to nearby animals.
5. Use QA measurements to calibrate player, villager, soldier, enemy, and animal locomotion.
6. Improve turn/start/stop and combat timing; retest all affected animation rigs.
7. Deepen daily-life behaviors and interaction anchors.
8. Profile LOW/HIGH and tune activation budgets after behavior is correct.

Do not land all phases as one large rewrite. Each phase should be a small reviewable change with its own before/after capture, measurements, and regression checks. Keep the simulation-data / embodiment boundary explicit so visual actors cannot fight the schedule simulation over position.

## Acceptance checklist

- [ ] Player cannot walk through a visibly solid Meshy or generated building, stall, cart, or fence.
- [ ] Intended doors, arches, and paths remain traversable; visible empty doorways are not covered by invisible boxes.
- [ ] Close villagers and animals do not pass through the player or through solid world collision.
- [ ] Agents route around buildings and blocked stalls; reachable destinations are not approached by a straight line through obstacles.
- [ ] NPCs yield, wait, sidestep, and resume without jitter, teleportation, or permanent deadlock.
- [ ] No simulation update overwrites a moving near physics actor's position every frame; handoffs preserve its real location.
- [ ] Player/villager/animal gait matches measured travel speed within the agreed band and passes visual review.
- [ ] Turns, starts, stops, blocks, attacks, hits, dodges, and recoveries blend without animation snapping or movement/clip mismatch.
- [ ] No close crowd pile-ups at doors, counters, or narrow streets; interaction spots have occupancy and fallback behavior.
- [ ] LOW/HIGH benchmarks record frame-time, physics time, body count, collider count, avoidance count, and nav update cost.
- [ ] Main route, crowd doorway, combat, slope/water, and streamed-boundary playtests pass on the supported quality tiers.

## Reference material

For open-world project patterns and source/art license distinctions, read the [open-world pattern study](OPEN_WORLD_PATTERN_STUDY.md).

Use these as technical references and pattern studies, not as a directive to import another game's code or art. Check the license and version before copying any implementation.

- [Godot 4.6 Navigation overview](https://docs.godotengine.org/en/4.6/tutorials/navigation/navigation_introduction_3d.html) — navigation maps/regions, agents, and the separation between navigation and custom actor movement.
- [Godot 4.6 NavigationAgent3D class reference](https://docs.godotengine.org/en/4.6/classes/class_navigationagent3d.html) — next path position and avoidance API. Avoidance adjusts requested velocity; the actor still has to move its body and retain physics collision.
- [Godot 4.6 Using NavigationObstacles](https://docs.godotengine.org/en/4.6/tutorials/navigation/navigation_using_navigationobstacles.html) — which obstacle modes affect mesh baking versus local avoidance, and the cost/limits to account for.
- [Godot 4.6 Using AnimationTree](https://docs.godotengine.org/en/4.6/tutorials/animation/animation_tree.html), [AnimationNodeBlendSpace1D](https://docs.godotengine.org/en/4.6/classes/class_animationnodeblendspace1d.html), and [AnimationNodeTimeScale](https://docs.godotengine.org/en/4.6/classes/class_animationnodetimescale.html) — measured-speed blend points, transitions, selective time scaling, and the root-motion API. Root motion still has to be consumed by the actor movement controller; it does not replace collision handling.
- [Godot 4.6 SpringBoneSimulator3D](https://docs.godotengine.org/en/4.6/classes/class_springbonesimulator3d.html) — inertial motion for configured bone chains and optional collisions. Use only after checking the rig's chain and skinning; its `reset()` API is relevant to discontinuous animation changes.
- [Godot Engine TPS demo](https://github.com/godotengine/tps-demo) — study its third-person control, animation layering, and interaction examples as a Godot-native reference. Its current project targets a newer engine branch; adapt concepts to this Godot 4.6 project rather than transplanting blindly.
- Project baselines: `kingdom/scripts/actors/player.gd`, `kingdom/scripts/actors/character_animator.gd`, `kingdom/scripts/population/villager.gd`, `kingdom/scripts/population/population_lod.gd`, `kingdom/autoload/world_sim.gd`, `kingdom/scripts/actors/critter.gd`, `kingdom/scripts/world/settlement_builder.gd`, `kingdom/scripts/world/assets.gd`, `docs/qa/anim_qa_report.md`, and `docs/RISING_ASHES_OPEN_WORLD.md`.
