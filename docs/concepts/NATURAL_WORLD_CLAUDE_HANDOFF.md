# Rising Ashes: Natural World and Game Feel — Claude Handoff

**Purpose:** give the game-code owner a practical, staged route from the current systems to smoother movement, believable crowds, reliable collision, and a world that appears to have routines. Start with [`CLAUDE_GAME_FEEL_BRIEF.md`](CLAUDE_GAME_FEEL_BRIEF.md) for the prioritized task list and acceptance criteria. This is a design and implementation brief only. It does not change game scripts, scenes, or project settings.

**Branch context:** prepared on `gpt/ai3d-assets` after fetching `origin/claude/focused-curie-m09hbd` on 2026-09-27. Read `docs/LOCAL_SESSION_HANDOFF.md` before implementation and fetch/merge the latest Claude work first. The remote branch has a performance pass (`docs/qa/PERFORMANCE.md`) and location/time-aware audio director; coordinate around those live changes. Do not copy from the Codex checkout or force-push over either owner's branch.

## Codex branch progress (2026-09-27)

The latest Claude commits for performance and audio have been merged into `gpt/ai3d-assets`. The merge kept the calibrated humanoid gait speeds, near-player actor collision, and corrected terminal death clip while bringing in Claude's audio director and performance measurements. A focused animal pass now eases critter starts, stops and turns, then sets playback rate from actual eased movement speed. Blender QA also produced a derived fox gallop with the source `Tail1` vertical curve removed; measured tail stretch improved from 30.3% to 1.7% without changing the original CC0 GLB. See [`docs/qa/animal_fox_review.html`](../../qa/animal_fox_review.html) for the visual comparison and [`docs/qa/anim_qa_report_only_animal_fox.md`](../../qa/anim_qa_report_only_animal_fox.md) for the measured results.

The route graph, visible-impostor obstacle guidance, resident-to-resident physical spacing, precise door/collider profiles, and full live-gameplay feel route remain open. The animation sampler now checks animal gaits at 120 Hz: fox Run measures 1.87 m/s and rate-matches its 5 m/s flee speed at 2.5×, but still fails on paw slip, loop seam and leg pops; fox Walk still fails slip. See the refreshed full report and interactive motion-review page before taking the next animation task.

**New visual review finding (Codex QA snapshot):** the humanoid `Hit_A` clip is a short upper-body flinch; `Hit_B` is a full-body backward knockdown. Across 27 humanoid QA profiles, `Hit_A` passes its upper-body check, while `Hit_B` fails all 27 with floor penetration (about 5–34 cm) and a roughly 0.3 s all-feet-off-ground interval. The strip makes the difference easy to inspect in [`ANIMATION_MOTION_REVIEW.html`](../qa/ANIMATION_MOTION_REVIEW.html). Current gameplay calls `Hit_B` for strong soldier knockback and player guard break, so review those cases in play before changing clip selection; a QA floor failure does not by itself mean a knockdown should become a small flinch. The existing armored boot-weight repair was checked against six source models and found zero badly weighted foot-region vertices in each, so it is not a justified fix for these clip failures.

**Claude branch check (2026-09-27):** the latest observed source commit is `9bb0a44e` (LOW phone budget, region trees/impostors, Meshy LOD3 and VRAM texture limits). Claude's local checkout also has uncommitted work in `kingdom/scripts/world/settlement_builder.gd` and `docs/qa/anim_qa_report.md`, plus running/produced asset QA outputs. Keep this Codex review confined to the separate branch and avoid those files until Claude's work is committed and reviewed.

## The experience to build

The player should feel in control while the body has weight. A person should travel along a plausible route, slow down before a destination, make room in a crowd, and react briefly to nearby events before resuming their routine. Buildings and substantial props should stop the player and near characters, while doors, lanes, and plazas remain open. Distant people should keep the same broad schedule without paying the cost of a full physics character.

Keep the existing streamed world, art style, combat and schedule simulation. Improve the seams between them in small steps. Do not start over with a new controller, crowd framework, or world architecture unless profiling shows the current pieces cannot support the goal.

## What the current code says

These are observations from the fetched branch snapshot, not a claim that every issue has been reproduced in a live play session.

- `WorldSim` is the position and schedule authority for a large population. It processes a rotating slice of up to 1,500 people each frame. `_spot()` chooses a destination; `_simulate_slice()` moves each data row directly toward it at `WALK_SPEED`. That direct line has no obstacle or street routing.
- `CityPlanner` already supplies a useful basis for routing: road segments (`streets`), door-to-street links (`paths`), building lots and gate angles. Reuse this settlement data instead of placing arbitrary waypoints or running a full 3D navigation agent for every resident.
- `PopulationLOD` turns only a capped set of nearby people into `Villager` physics characters. Distant visible impostors are not physical, so they need cheap route guidance too. Giving the entire simulated population collision bodies is not a viable fix.
- `Villager` is a `CharacterBody3D` and feeds its resolved position back to `WorldSim`, which prevents near residents from being pulled through an obstacle on the next simulation update. The current body mask collides with world geometry, not other villagers; soft separation is not a guarantee of non-overlap.
- Settlement and landmark collision proxies are derived from model AABBs. They can make a whole building shell solid quickly, but a box may cover an open doorway or empty awning space. Use the production proxy preview at `docs/qa/collision_preview/index.html` to review fit before changing proxy profiles.
- The player already uses `CharacterBody3D.move_and_slide()`, smoothed acceleration/facing, buffered combat input, a collision-aware camera arm and layered animation. The missing work is targeted feel review and synchronization: controls, stride, stopping, foot contact, attack contact, crowd yielding, obstacle routing and camera clearance must agree.
- The fetched Claude branch has a performance budget and an audio director. Check `docs/qa/PERFORMANCE.md`, `kingdom/scripts/core/quality.gd`, and the audio implementation before choosing active-agent counts, update rates, or adding sound behavior.

## Recommended implementation order

### 0. Establish a repeatable feel route

Before tuning values, choose one short route through a representative settlement: spawn, cross the plaza and stall lane, circle a Meshy house, approach a resident, enter and leave a doorway, and fight one nearby enemy. Record resolution, renderer, quality tier, frame rate, input device, and a short before clip or notes. Keep this route stable for later comparisons.

Record concrete failures: wall pass-through, doorway blocked by invisible geometry, visible residents crossing a building, crowd overlap, foot sliding, abrupt rotation, long braking glide, enemy collision snag, camera clipping, and attack effects occurring on the wrong beat. A headless pass can catch broken scripts and routing regressions; only in-game footage can establish whether the result feels natural.

### 1. Make the collision rules and building entrances explicit

Document the project physics layers and masks in one place. Verify player, resident, enemy, world shell, foliage, trigger, and interactable behavior against those rules. Keep near actors on the existing character-body path; a player and near resident should block one another without actors being accidentally blocked by triggers or decorative foliage.

Audit actual Meshy and Blender landmarks in the collision gallery. Where AABB boxes create false walls, add deliberate low-complexity collision profiles: solid wall or counter volumes, open door volumes, and separate collision shapes for large solid props. Do not use a building's entire visual AABB as the definition of its interior. Props that can be walked under (for example, a canopy) need a shape around their supports/counter, not an invisible box over the whole canopy. Keep decorative items non-blocking unless they have enough size and visual weight to justify it.

Treat doors as intentional transitions. Give each usable door an exterior approach point, a clear opening, an interaction/trigger volume and an interior destination. Ensure the resident destination stops outside the door and never places its target inside a solid wall. Test both player passage and NPC approaches from both sides.

**Acceptance:** walls and solid props stop the player and near actors; doors and intended lanes stay passable; every reviewed proxy visually matches the occupied volume; no common route requires the player to squeeze through a false collider.

### 2. Route simulated residents over the settlement layout

Build a lightweight 2D settlement route graph from the data already produced by `CityPlanner`: road-segment endpoints and junctions, gate links, and door-to-road paths. Snap meaningful destinations (home door, workshop, market, gate, field/forest edge) to the nearest accessible graph location. Use a deterministic shortest path, computed when a resident's schedule target changes or when a streamed settlement plan changes—not on every movement frame.

Keep each destination as a semantic goal and store a small route/progress cursor for the data row. Move along the current waypoint, advance when close, and ease speed down at the last waypoint. If a point cannot connect, choose a safe nearby road point or hold the resident at the last valid position; never silently fall back to a straight line through a building. Add a small deterministic side offset when multiple people share a route, while leaving enough clear width for opposing flows.

Not every destination lies on a settlement street. Field, forest and roadside work destinations should use a route from the town gate or street edge toward the open-world goal. A coarse terrain-aware route or occasional collision-safe local waypoint is enough at distance; reserve dense 3D navigation for the player's nearby zone. Handle gates and streamed chunk boundaries explicitly so targets do not cross walls or point into unloaded terrain.

The near `Villager` should follow the same route intent as its `WorldSim` row. While physics resolves a close collision, its world position remains authoritative for that near actor; on LOD demotion, hand the corrected position back cleanly and continue the remaining route. On promotion, initialize the body from the data position and preserve the current target and route cursor. Avoid two systems pulling the same actor in different directions.

**Acceptance:** a route audit over deterministic settlements shows no waypoint leg crossing a building footprint or wall except a declared gate/door; arrivals and transitions are stable across LOD changes; route computation stays outside the per-frame inner crowd loop.

### 3. Add believable near-field yielding, without a crowd wall

Make collision and steering complementary. Physics provides final non-penetration for the player and nearby embodied characters; steering gives people room before they collide. Use short-horizon separation with a personal-space radius, a capped lateral sidestep, and a brief stop/yield option. Bias the sidestep toward nearby open street space, not into house lots, stalls or the player. Give the player right-of-way at conversational distance, but allow brief NPC-to-NPC yielding so two lines can pass.

Use a stable update budget. Prioritize actors inside the interaction radius, actors on screen, and actors involved in combat. Limit full physics/animation bodies using the quality tier already chosen by the project. Update low-priority steering less often and interpolate their displayed pose. Hysteresis around LOD distances prevents repeated spawn/despawn when the player hovers at a boundary.

When a route is blocked for a short time, let the person wait, try one side step, then replan from a safe point. Do not continually push into the same wall. Keep the state small and readable: `TRAVEL`, `YIELD`, `ARRIVE`, `IDLE`, `REACT`, `RETURN`. Reactions should expire and return to the person's scheduled goal.

**Acceptance:** close actors do not pass through the player or one another; passing creates a short readable yield instead of a traffic jam; people do not sidestep through solid geometry; far crowd performance remains within the branch's recorded budget.

### 4. Tune locomotion from movement, not from animation names

For each playable rig, measure the ground distance covered by a clean walk and run cycle. Calibrate blend thresholds and playback speed from those measurements. Update movement and facing with frame-rate-independent response; tune acceleration, braking and turn response separately. Start and stop tests matter as much as top speed. On slopes, preserve ground contact and avoid forced vertical snapping that causes foot jitter.

Use foot-contact markers or known cycle phase to schedule footsteps. Footsteps should reflect distance actually traveled and the ground surface, with a distance threshold as a fallback when a clip has no reliable events. Avoid a second cadence loop drifting independently from the animation. Add subtle body/upper-body response to starts, stops, turns and carried equipment only after the base feet align.

Interrupts need clear ownership: attacks, blocks, dodges, hits, death and interaction should blend in and out without fighting locomotion. Use a consistent priority rule and restore animation playback rate when a one-off activity ends. Keep root motion out unless a specific action needs it and the project can reconcile it with collision and player input.

**Acceptance:** at walk and run speed, feet do not visibly skate on level ground; direction changes and stops settle quickly without snapping; the same route feels responsive on keyboard and touch/controller; activity animations return to the right gait.

### 5. Synchronize combat and interaction feedback

For each attack, define startup, active contact and recovery using the animation timeline. Use an active-window overlap or swept arc, hit each target once per swing, and test line of contact against world geometry so a weapon does not damage through a wall. Lock or snapshot the attack direction at a clearly chosen point. Align damage, hit reaction, sound, VFX, camera response and hit-stop to that contact moment.

Preserve buffered inputs but specify when dodge/block can cancel an attack and how stamina is paid. Keep knockback subject to collision. Guard time scale and temporary effects when an actor is removed mid-hit so combat cannot leave global time stuck. For doors and dialogue, input feedback should confirm the chosen interaction before a transition begins; never let a nearby service NPC hide a usable door prompt.

**Acceptance:** visible contact matches gameplay contact; swings do not reach through walls; hits, blocks, misses, dodge and recovery each read clearly; chained inputs are forgiving but cannot bypass stated stamina or recovery rules.

### 6. Give people simple routines and readable reactions

Keep `WorldSim` the owner of schedule, destination and persistent state. Extend destinations with named stop types (home, work, market, gate, gathering place) and small deterministic variation. A near resident can play a context animation at the correct stop—work, browse, converse, rest—then resume travel when the schedule or a nearby event changes.

Add only a few short reactions at first: greet a known person, step aside for the player, watch a nearby event, flee danger, return to work. Give each a timeout, range and interrupt rule. Use time-of-day and location audio already being added on Claude's branch; select ambience and work sounds from actual place/time state, and keep one-shot sounds tied to an event to avoid crowd noise spam. Do not add random idle behaviors that contradict the schedule or make quests/interaction unreliable.

**Acceptance:** repeated visits show plausible work/rest/travel patterns; residents react briefly and return to their jobs; schedule transitions do not teleport visible people through geometry; ambience follows location/time without stacking uncontrollably.

### 7. Finish camera, terrain and performance checks

Review the camera on the same route at close, standard and zoomed-out scales. Keep the camera outside walls and terrain while preserving sight of the player. Check foliage separately from solid trunks so leaves do not hide combat unnecessarily. Test slopes, steps, bridges, doors, settlement gates, water edges and streamed chunk joins. Movement must not stick at a visual seam or fall off a valid path.

Measure the crowded plaza and a battle at the project's quality tiers on the target desktop and phone. Use `docs/qa/PERFORMANCE.md` as the baseline. Record frame-time percentiles and counts for physical actors, active animation trees, route updates and visible impostors. Reduce distant update frequency and visual detail before removing useful world activity. Recheck all tier caps after any collision or crowd change.

## Suggested milestones and review artifacts

1. **Baseline and collision audit:** one route, recorded before evidence, layer/mask map, proxy gallery annotations and door list.
2. **Navigation foundation:** deterministic route builder and a QA report drawing streets, door links, destinations and route legs over the settlement. Include a regression check for legs intersecting known building footprints and walls.
3. **Crowd handoff and yielding:** promotion/demotion checks, player/resident pass-by clip, crowded doorway and plaza review, perf numbers at each supported tier.
4. **Locomotion and action timing:** walk/run contact sheets plus in-game start/stop/turn footage; attack timeline and contact clip; footsteps on grass, dirt and stone.
5. **Daily-life pass:** a short time-lapse of one resident over a full schedule and a short reaction-to-return clip; verify dialogue and doors remain usable.
6. **Release route:** repeat baseline after changes at each target tier; list remaining rough edges with location, reproduction steps and owner.

Keep each milestone independently reviewable. Update this document's status or link its report/clip in `docs/LOCAL_SESSION_HANDOFF.md` when a milestone is ready for the other session. Do not mark an item done from a headless-only pass if its acceptance criteria include how movement looks or feels.

## Reference patterns to adapt

- Godot's [3D navigation overview](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_3d.html) and [NavigationAgent guide](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html) separate navigation maps, path following and avoidance. Avoidance does not replace collision shapes; use NavigationAgent3D selectively for the local region, not every simulated resident.
- OpenMW's [pathgrid documentation](https://openmw.readthedocs.io/en/stable/manuals/openmw-cs/tables-world.html#pathgrids) demonstrates authored connections for important routes. Rising Ashes already has generated streets and door paths, so adapt the authored-graph idea to those records.
- 0 A.D.'s [unit motion interface](https://github.com/0ad/0ad/blob/master/source/simulation2/components/ICmpUnitMotion.cpp) keeps movement requests separated from how movement executes. Use that separation as a design cue while retaining this project's own `WorldSim`, `CityPlanner`, `Villager`, `Player` and `Army` systems.
- Veloren's [architecture guide](https://book.veloren.net/contributors/developers/codebase-structure.html) is useful for thinking about world simulation and scale boundaries. Its voxel/Rust architecture is not a drop-in for this Godot game.

These are patterns to study, not code or art to import. Check each upstream licence before any future reuse; keep Rising Ashes assets, world and code in their existing ownership and style.
