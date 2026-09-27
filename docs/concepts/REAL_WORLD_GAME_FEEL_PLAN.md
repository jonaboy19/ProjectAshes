# Rising Ashes / Kingdom — Natural Movement, World Feel, and Collision Plan

**Purpose:** improve the existing game in small, reviewable steps. Keep the current world, systems, assets, and art direction. This is an implementation plan, not a rewrite proposal.

## Implementation status

First collision pass is now implemented on `gpt/ai3d-assets`:

- The player collides with nearby embodied residents. Only the existing capped near-player villager LOD uses physics bodies; the distant population remains data and impostors.
- Villagers move through `CharacterBody3D` and a capsule, collide with solid world geometry, and write their resolved position back to `WorldSim` when a player or building blocks them.
- Village market stalls and solid plaza clutter now receive simple box colliders. Decorative plants remain non-colliding.
- House-lot and individual landmark collider footprints were tightened to cover more of their visible model.

The game has not yet been playtested after these changes. The next pass should check player/resident blocking, crowded doorways, market paths, and whether any collider feels like an invisible wall before expanding physics to combat units.

## What the current build already gives us

The Kingdom project already has a third-person player controller, multi-scale camera, stamina combat, buffered combo input, dodge, hit reactions, layered `AnimationTree` locomotion, head look, squads, a population simulation, animated nearby people, and sprite impostors for distant units. The world is streamed and settlements are procedurally placed. The best next step is to improve how the systems meet at close range and how movement is presented.

The inspected source explains the most visible collision problem:

- `Player` is a `CharacterBody3D` with a capsule and `move_and_slide()`.
- `Villager`, `Soldier`, and `CampMonster` are `Node3D`s that update their positions directly. They have no rigid or character body collision, so they can pass through the player and buildings.
- Settlements create some simple `StaticBody3D` building and wall colliders. These do not automatically guarantee that every imported or newly generated Meshy model has a correctly sized collision shape.
- Soldiers have a small squad-only separation force. This is steering, not solid collision, and does not cover villagers or other squads.
- `CharacterAnimator` already blends idle/walk/run and layers attacks and blocks. The player and soldier movement currently use fixed acceleration/turn values and do not tie their movement step to animation foot contact.
- `WorldSim` owns crowd position truth; close-range embodied characters need a deliberate handoff so physics corrections do not get overwritten by the next simulation update.

## Desired feel

1. **Solid, readable space:** the player cannot pass through building walls, large props, or nearby people. Doors and intentional passages remain traversable.
2. **Responsive movement with weight:** acceleration, stopping, turning, slopes, dodging, and attack recovery feel deliberate but never sticky.
3. **People with intent:** nearby residents appear to be going somewhere, make room, react to the player, and resume their routines. Far crowds remain inexpensive.
4. **Actions with clear cause and effect:** animation, contact, sound, camera response, and gameplay results happen on the same beat.
5. **One world, staged fidelity:** near actors use full physics and animation; mid-distance actors use lightweight steering; distant population stays simulation/impostor driven.

## Work plan

### Phase 0 — Lock the baseline and make a short feel checklist

Before tuning, keep a small, repeatable route: walk from the village square through the market, circle the inn, speak to a resident, walk into a crowded area, and fight one enemy. Record the Godot version, input device, frame rate, and short clips or notes for each issue. Use the same route after every phase.

Checklist: Can I walk through a wall? Can an NPC overlap me? Does a stop skid? Do feet slide while walking? Does the camera clip into a wall? Does a swing hit before/after the visible sword? Do residents block doors or each other? Do all of these remain smooth in the busiest village and battle?

### Phase 1 — Make collision dependable for every asset

**Model the world with collision proxies, not render-mesh collision.** Every placed building or solid prop should have explicit collision metadata or a placement profile: footprint, height, collision type, and optional entry gaps. Use a small set of boxes or convex shapes for ordinary buildings and props. Use hand-shaped compound boxes for irregular hero buildings. Keep render geometry independent so polygon changes cannot break movement.

For generated GLBs, add a companion manifest to the asset workflow describing its intended solid footprint and scale. At import/placement time, validate that a solid asset has a collider; make missing-collider assets visible in a debug report. Keep foliage, banners, fence decorations, signs, and other non-blocking details out of the body collision layer. Use trigger areas for doors, talk ranges, and interaction prompts.

**Collision layers:** define named layers for world geometry, player, local NPCs, enemies, triggers, and projectiles. Set each body’s layer/mask explicitly. The player must collide with world geometry and near actors. A local NPC must collide with the world and player and use actor avoidance for other NPCs. Projectiles and interaction rays should query only their intended layers.

**Acceptance:** no walking through building shells or designated solid props; doors/gates work; no collision on decoration that should be walked through; colliders fit the visible footprint closely enough to avoid invisible walls.

### Phase 2 — Stop close characters passing through one another

Add a near-actor tier for characters that can affect the player. Convert only the small number near the camera/player into `CharacterBody3D` actors with capsule shapes and controlled `move_and_slide()` movement. Keep the far population as data, and mid-distance people on cheaper steering/impostor movement. Don’t make thousands of simulated residents into physics bodies.

Use `NavigationAgent3D` for destinations and local avoidance where navigation data exists; use collision bodies for actual physical blocking. Avoidance must be connected to its safe-velocity result and updated every physics frame. It is not a substitute for physics collision or static world geometry. For the player, nearby crowd actors should yield gently to avoid a hard “wall of people”; important quest NPCs can have a higher priority. For combat, use a distinct response: enemies can body-block, while friendly followers maintain formation spacing.

Introduce an explicit authority handoff: while an NPC is embodied nearby, physics controls its world position and writes the corrected position back to the population record at a safe cadence. On demotion to a lower LOD, copy the final physical position into `WorldSim` before freeing the body. This prevents snapping back to the old simulation coordinate.

Add a stuck-recovery rule for actors who fail to make progress: stop, re-query/replan, try a small sidestep, then choose a nearby valid position. Never teleport a visible person through a wall as the normal recovery path.

**Acceptance:** a resident cannot overlap the player; residents make room without pinballing; doorways stay usable; NPCs do not jitter in crowds; actors transition between near and far representation without snapping.

### Phase 3 — Smooth locomotion without losing input response

Tune acceleration, braking, and rotation as separate curves instead of increasing a single smoothing constant. Preserve immediate camera-relative input, but let the body accelerate into a run and decelerate in a short, controlled distance. Tune different response for walking, running, blocking, carrying, wading, and combat recovery. Give dodge and knockback their own movement authority so normal input smoothing does not erase them.

Drive animation from measured planar velocity and desired direction, not only a walk/run threshold. Expand the current idle/walk/run blend into a 2D directional blend if the imported animation set supports strafe/backpedal clips. Add short start/stop and turn-in-place transitions when available. Keep upper-body attacks layered over locomotion where the animation permits; full-body dodge/stagger/death actions temporarily own the whole body. Tune blend-in/out times and animation rates to speed so feet do not skate.

Add footstep events using animation call tracks (or foot-contact timing data), with surface tags from terrain/material. Add subtle footstep sound and dust/grass response. Consider foot placement IK only after the movement and animation timing is stable; do not make IK hide bad collision or animation speed.

**Acceptance:** clean start/stop, no long glide, no obvious foot skating at walk/run, body follows turns naturally, and controls still feel immediate on keyboard and touch.

### Phase 4 — Make combat contact and movement share one timeline

Keep the existing combo, stamina, dodge, block, hit-stop, and camera shake foundations. Replace distance-and-dot-only sword damage with a short active hit window driven by animation events and a swept arc or overlap query on the correct combat layer. Snapshot the attacker’s facing when the attack begins; only hit once per target per swing. Align impact VFX/audio, target reaction, knockback, and hit-stop to the contact frame.

Give attacks intentional startup, active, and recovery windows. Preserve input buffering during recovery, but add clear cancellation rules for dodge/block and make them consistent across player and AI. Use small hit reactions for light contact, larger stagger for heavy contact, and push impulses that respect solid collision. Clamp camera shake/hit-stop so repeated crowd hits cannot leave global time scale in the wrong state if an actor is removed mid-effect.

**Acceptance:** sword visuals land when damage lands; swings do not hit through walls; combo buffering is forgiving; a blocked hit, normal hit, and finisher read differently without locking movement longer than expected.

### Phase 5 — Give the village a daily rhythm

Retain the existing schedule/economy population simulation and improve its visible layer. Use authored points and nav regions for homes, workstations, market stalls, wells, gates, and gathering spots. Residents should travel between those meaningful destinations according to time of day, job, needs, and quest state. Add small idles at stops (look around, converse, inspect goods, sit, work) with deterministic variation by person so repeated visits feel coherent.

Use social groups and short-lived intentions rather than random wandering: pass someone, greet a known person, watch a nearby event, step aside for the player, flee a nearby battle, or return to work afterward. Make transitions interruptible, and avoid spawning extra AI frameworks until simple state-based behaviors are insufficient. Limit active decision updates by distance/importance; distant people continue as coarse schedule data.

World affordances must communicate rules: doors have a clear opening, market props do not block walking lanes, benches and stalls invite interaction, and NPCs do not choose destinations through walls. Add location-aware ambient sound, footsteps, work sounds, birds/wind, time-of-day lighting, and occasional village activity once movement is dependable.

**Acceptance:** residents have plausible destinations and routines, react briefly to the player/world, then return to their routine; paths avoid buildings; crowd density stays within frame-time targets.

### Phase 6 — Camera, terrain, and polish pass

Use a collision-aware camera arm/camera sweep in close views so the camera does not clip through buildings or terrain. Ease camera follow and view-scale transitions. Keep command view readable and do not let its large movement influence close-character physics.

Check walkable slopes, steps, ledges, bridges, water, and chunk boundaries. Make sure navigation regions join at streamed chunk seams and actors do not target unloaded positions. Use material/surface metadata to vary footstep audio and movement speed where appropriate. Add small, low-cost feedback such as foliage brushing, cloth/weapon motion, dust on dry ground, and ripples at water edges only after the core movement passes.

Profile busy scenes on the target PC and phone. Keep the existing actor LOD and impostor approach. Set budgets for active physics bodies, navigation agents, active animation trees, and shadows; reduce update rates and animation work with distance before reducing the number of simulated residents.

## Suggested implementation order and deliverables

1. **Collision audit:** scene/asset checklist, named physics layers, debug view/report, collider coverage for current buildings and solid props.
2. **Near-character collision:** player + nearby NPC capsule blocking, NPC-to-player collision, position handoff to/from `WorldSim`, doorway and crowd tuning.
3. **Movement and animation tuning:** acceleration/braking/turn curves, animation blend updates, footsteps and surface tags.
4. **Combat synchronization:** timed hit windows and wall checks, consistent attack recovery/cancel rules, impact synchronization.
5. **Village life:** nav-driven schedule stops, small contextual behaviors, distant update budgets.
6. **Camera/terrain/feel polish:** camera collision, slope/chunk tests, sound and lightweight environmental response, device profiling.

Each item should land as a small change with a short before/after clip and a manual route checklist. Keep every change inside the existing project architecture unless a measured limitation shows it cannot support the feature.

## Reuse references, adapt to Rising Ashes

- [Godot NavigationAgents guide](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html): path following and avoidance setup. Its key practical limit is that avoidance is a steering calculation; actual collisions and navigation geometry are separate systems.
- [Godot 3D navigation overview](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_3d.html): NavigationRegion3D, navmesh, layers, and obstacles.
- [Godot TPS demo](https://github.com/godotengine/tps-demo): already referenced by this project for camera shake and animation blend patterns.
- [GDQuest 3D third-person controller](https://github.com/gdquest-demos/godot-4-3d-third-person-controller): already referenced in the project’s source notes for camera-relative control and facing behavior.
- [Godot Navigation Agents Demo](https://github.com/viksl/Godot-Navigation-Agents-Demo): optional experiment for crowd-agent scaling; take performance ideas only after profiling this game's expected near-agent count.
- [Godot 4 third-person combat prototype](https://github.com/Snaiel/Godot4ThirdPersonCombatPrototype): inspect as a reference for controller/combat structure, not as a drop-in replacement.

Before copying any code or asset, re-check the exact repository licence and retain required notices. Prefer learning a narrowly scoped pattern (movement blend, path steering, hit window) and adapting it to the existing `CharacterAnimator`, `WorldSim`, `Player`, `Soldier`, and streamed settlement architecture. Do not import a full open-world starter project into this game.

## Scope guardrails

- Preserve the established world, lore, asset style, four camera scales, crowd LOD, combat loop, and open-world direction.
- Keep generated models as visual assets with separate, deliberate collision proxies.
- Physics bodies and detailed navigation apply only to actors near enough to matter; far population stays simulated cheaply.
- Prefer Godot built-ins first. Add a behavior-tree or state-machine plugin only when specific complexity or profiling justifies it.
- Treat manual play-feel review and target-device profiling as release gates; headless validation cannot judge whether controls feel natural.
