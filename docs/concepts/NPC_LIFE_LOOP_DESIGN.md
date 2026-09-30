# NPC life-loop design for Rising Ashes

**Status:** living-world behavior design and acceptance contract for Claude. Movement/LOD/needs and a narrow water activity are now implemented on the Codex integration branch; this document is not evidence of runtime acceptance.

**Original source audit:** `claude/focused-curie-m09hbd` at `e3563fc4`. Current source findings are summarized above from Codex branch `gpt/living-world-integration`; recheck Claude local/unpushed work before changing shared files.

**Purpose:** turn the existing schedule and population system into visible, physical, interruptible lives without making the whole population expensive.

## Current implementation snapshot — 30 September 2026

- `WorldSim` remains the cheap schedule/data owner. It uses a bounded per-frame time budget, prioritizes residents near the player, and leaves embodied movement to the owning body. Distant rows still move directly toward coarse schedule targets; `DailyRhythm` supplies a deterministic two-game-hour per-person delay and `PopulationLOD` holds unembodied residents until their local schedule reaches a shared phase.
- `PopulationLOD` keeps full-model, sprite, physics and animation budgets separate. It writes embodied positions back under an instance token and preserves a body's resolved position during time skips. Promotion/demotion still reconstructs route intent rather than preserving a full route/velocity handoff record.
- `Villager` is a `CharacterBody3D`, routes near bodies through `StreetGraph`, uses acceleration/braking/facing and resolved speed for locomotion, and yields to the player. Within contact range it enables its capsule; the nearest eight selected bodies use `move_and_slide()`, and moving overflow uses one swept `move_and_collide()` query against world/player shapes. Actor-to-actor separation is steering-based. See [NPC_CONTACT_LOD_CONTRACT.md](NPC_CONTACT_LOD_CONTRACT.md) for collision limits and required runtime checks.
- `UtilityBrain` chooses needs and acts on staggered decision ticks. Sight requests are FIFO and budgeted at four casts per 500 ms; each observer rotates through up to four nearest hostile candidates, and unseen threats decay from anonymous last-known positions. A deterministic courage trait modestly changes existing FLEE/WATCH scores. Discrete sounds receive coarse damping behind settlement geometry. Conspicuous resolved combat techniques feed a 64-entry coalescing spectacle queue that can prompt nearby villagers to look. These cues do not identify a culprit or establish crime-witness evidence. Relationships retain bounded dialogue-topic memory, not witnessed crime, NPC biographies or propagated rumors.
- The first live physical activity is leased water fetching at two generated approaches or an abstract plaza break. Its need recovery and animation are gated on arrival, stop, facing and lease state. Offscreen catch-up approximates scheduled sleep, meals and hydration in constant time but does not debit an economy or recover social/faith needs. Other visible activities are not yet backed by generic approach/occupancy/work-order mechanics.
- Wolves, monsters and ambient critters remain separate behavior/movement implementations; do not assume the villager route/physics guarantees apply to wildlife.

This is source review only. Godot runtime, visual behavior, save/load, crowd contention and mobile frame cost remain unverified. Claude owns active rigs/scenes/colliders and should confirm the Meshy building collision before systems code is used to mask missing content.

## Historical baseline findings at e3563fc4

The [interactive daily-rhythm viewer](WORLD_DAILY_RHYTHM_REVIEW.html) exposes an additional source-level behavior risk: residents with the same job change phase on exact shared clock boundaries, and the simulation applies their new targets in a short update burst. The schedule table, real-time conversion, and a deterministic staggering design are in [WORLD_DAILY_RHYTHM_DESIGN.md](WORLD_DAILY_RHYTHM_DESIGN.md).

At that historical baseline, the system had a strong foundation: all residents exist cheaply as data in `WorldSim`; `PopulationLOD` promotes only a limited near set to full models; and work/home/market intent is already derived from the time of day. The gap is between that intent and what the player sees.

- `WorldSim._current_phase()` selects only home, work, or market. `_on_phase_change()` replaces a person's target with a newly selected point. `_simulate_slice()` advances the position directly toward it at `WALK_SPEED`, in a straight line.
- `WorldSim._spot()` can choose a point by distance and angle, and shop/home targets stand near a lot. A target is not an authored entrance, counter, field row, patrol node, or occupied activity anchor.
- `is_indoors()` hides some people when their simulation position is within one metre of a target. There is no visible arrival sequence or proof that the target is a traversable door.
- `PopulationLOD` gives near residents a model and far residents a billboard. `Villager` is a `Node3D`, has no body collision, and chases `WorldSim.pos` directly in `_process()`. At a gap over four metres it temporarily follows at up to 4.8 m/s, despite the normal 1.6 m/s visual speed. It switches directly between `Walking_A` and `Idle`.
- The [follower/gait review](NPC_FOLLOWER_ANIMATION_REVIEW.html) and [source notes](NPC_FOLLOWER_ANIMATION_REVIEW.md) trace a new frame-rate/population interaction: `WorldSim` updates at most 1,500 rows per frame, while the embodied villager only selects `Walking_A` when its gap to the data position exceeds 0.15 m. This is a measured source-level hypothesis about why visible NPCs may glide or flicker between states; capture the actual gap, resolved velocity, clip, and playback rate before treating it as a proven runtime failure.
- `Critter` selects a random point within a radius and moves directly there while sampling terrain height. Its own comment explicitly says it has no physics or navigation. `Wolf` and `Monster` also advance their global position directly toward the target. The hostile state machines add intent, but the movement does not route around buildings or resolve body contact.

These are historical source observations, not current behavior claims. Re-run relevant checks against the latest Claude working copy before implementing any proposal below.

## Behavior model and remaining design

Keep schedule truth cheap and persistent. Make the close, visible actor a presentation and physical-execution tier for that truth.

```mermaid
flowchart LR
    S[Schedule and world intent] --> G[Stable goal ID and activity anchor]
    G --> R[Reachability check and local route]
    R --> M[Near actor movement and collision]
    M --> A[Arrival, facing, activity, pause]
    A --> S
    E[Player, danger, dialogue, blocked path] --> I[Interrupt and priority resolver]
    I --> R
    I --> M
    I --> A
```

### Authority and data

Keep `WorldSim` as owner of schedule, job, home, money, long-term goal, and low-detail position. Add stable goal identity and a compact coarse movement state only if needed for representation handoff. Avoid turning all 20,000 residents into physics nodes.

When a resident is promoted to the near tier, initialize the body at the stored world position and let its physics controller own motion while embodied. It reports its resolved position and arrival/goal status back at a controlled cadence. Do not have both the simulation and the body advance the same resident at once. On demotion, store the body’s final position and meaningful state before freeing it. Promotion/demotion must never snap an actor through a wall or back to an old simulation point.

The [contact and LOD contract](NPC_CONTACT_LOD_CONTRACT.md) makes this handoff concrete: contact actors keep a physical capsule; eight use multi-slide movement and overflow uses a single swept collision check. Model selection and three-spawns-per-refresh still do not guarantee instant promotion to a full body. Runtime-test contact density, spawn delay, overflow recovery and the separate route-only tier before changing either budget.

### State set and interrupt order

Use a small state set with explicit entry/exit behavior. It can be an enum plus data, an existing behavior-tree tool, or another fitting structure; preserve the existing project architecture unless evidence justifies a dependency.

| Priority | State | Entry | Visible behavior | Exit |
|---:|---|---|---|---|
| 0 | `dead_or_unavailable` | death, despawn, invalid actor | existing death/despawn handling | explicit respawn or lifecycle event |
| 1 | `combat_or_flee` | confirmed threat or damage | face threat, approach/retreat on a valid route, play attack/hit/recovery/flee animation | threat resolved, lost, or actor disabled |
| 2 | `dialogue_or_interaction` | player starts a supported interaction | stop at interaction range, turn toward player/anchor, use the interaction pose | interaction ends or higher priority danger occurs |
| 3 | `yield_or_react` | imminent player/crowd contact, startling event, blocked goal | brake, glance/turn, sidestep to a reachable point or wait, then resume | clear path plus brief recovery, or priority change |
| 4 | `travel` | schedule or local activity chooses a new goal | follow path with accel/braking and turn animation; do not walk through buildings | within anchor arrival radius, path fails, or interruption |
| 5 | `arrive` | actor reaches anchor approach point | decelerate, face anchor, settle into activity pose | anchor acquired, unavailable, or interruption |
| 6 | `work / socialize / wait / rest` | activity anchor granted | loop a suitable action with subtle idle variation; respect occupancy and plausible duration | schedule change, interruption, or activity timer |
| 7 | `leave` | activity ends or schedule goal changes | exit using its approach point, then travel to new goal | next anchor/goal reached or interrupted |

Priorities are evaluated in that order, but persistent activities should not restart every frame. State changes should be event-driven or checked at a bounded rate. Add hysteresis to threat, distance, and path-failure thresholds so an actor does not chatter between states.

Use an explicit switch-out/switch-in contract when a higher-priority state interrupts a resident. Finish or safely cancel the current action, release its route, anchor, held-item, speech, or attack reservation, then initialize the new owner and its entry pose. Preserve the old goal as intent and revalidate it before resuming. Do not let two states drive the same body transform. The research-grounded details and three annotated interruption examples are in [behavior and animation transition design](NPC_ANIMATION_TRANSITION_DESIGN.md) and its [interactive handoff viewer](NPC_TRANSITION_HANDOFF_REVIEW.html).

## Goals and activity anchors

A position alone does not describe a believable destination. Represent a goal as a stable identity and a small anchor record:

- owning settlement/building/activity ID;
- approach position on a reachable path surface;
- facing direction or look target;
- interaction/activity type;
- acceptable arrival radius;
- occupancy capacity and current reservation;
- optional use duration and animation/action set;
- fallback anchors when occupied or unreachable.

Examples: an inn entrance approach, a blacksmith's work side of the counter, a market stall customer spot, a field work point, a guard's patrol node, a bench seat, a stable feeding point. Keep a door anchor outside the threshold and an interior point distinct; an actor should only be considered indoors after actually reaching a valid portal/arrival point.

On assignment, first validate that the approach point is reachable. If the primary anchor is occupied, choose another compatible anchor, wait in a queue position, or select a nearby meaningful activity. Never make every person target the same exact counter point. Release the reservation on interruption, timeout, actor removal, or schedule change.

## Motion and physical contact

For the near embodied tier:

1. Use a physics body/capsule for contact with approved solid world collision and other near actors.
2. Use navigation for the global path around static obstacles; use local avoidance or steering for moving agents and personal space; use physics for final body contact. These solve different parts of the problem.
3. Advance the body in the physics step. Rotate toward actual travel or interaction facing with bounded angular acceleration. Approach destinations with braking distance, not a constant-speed overshoot.
4. Detect stuck motion by comparing desired progress with actual progress over a short window. Escalate: slow/wait, try a reachable side-step, repath, then choose a safe fallback activity. Do not teleport through a blocker to hide failure.
5. Use different response profiles: a child, a laden worker, a guard at post, a horse, and a chicken should not share the same radius, turn rate, or yielding rule.

For distant data and sprite tiers, retain cheap simulation and schedule updates. Their approximated paths still must not jump through visible solid buildings when entering or leaving the represented region. Use a connected coarse route graph or a validated abstract travel transition; only promote an actor close enough for its collision and detailed animation to matter.

## Animation and sensory response

Animation follows resolved motion and state, not the requested target vector. Blend walk/run from measured horizontal speed after calibration against the QA clip speeds. Add start, brake, turn/pivot, wait, work, look, hit, and recovery transitions only where the rig has a suitable clip. Crossfade state changes and preserve current gait phase where appropriate; do not restart a loop each physics tick.

For noncombat reactions, use small readable signals: orient eyes/head or torso toward the player, pause a task briefly, make space, then return attention to the original activity. Keep this local and event-triggered. Don't run expensive gaze/avoidance logic on distant impostors. Use small deterministic variation in wait duration, gait phase, facing, and idle action so nearby actors do not repeat one identical loop in sync.

Footsteps and surface effects should be tied to actual locomotion and ground material after speed calibration. Work audio, doors, and tool sounds should fire from activity events. Audio timing must not mask a broken foot plant or an actor sliding across a stationary idle.

## Implementation sequence

1. **Observe:** record the same village market loop with a doorway, crowded route, work anchor, and player interruption. Capture normal view plus collision/path/state overlays. Use the existing current QA route if Claude's active work supplies one; don't duplicate it.
2. **Anchor proof:** add one meaningful set of entrance and stall approach anchors. Verify reachability, occupancy, reservation release, and “indoors after arrival” on these points.
3. **Near-body proof:** embody a small capped set of villagers and prove world collision, player contact, yielding, and exact LOD handoff. Measure body and avoidance counts on LOW/HIGH.
4. **Route proof:** route villagers around a building and blocked stall; test destination on the far side and a streamed boundary. Ensure there is no line-of-sight shortcut through walls.
5. **Life-loop proof:** complete one work-to-market-to-home cycle with arrival, action, interruption, and recovery. Add actors/anchors one job type at a time.
6. **Animation pass:** use Claude's game-loader QA and same camera captures to calibrate locomotion and inspect state transitions across each rig family.
7. **World extension:** reuse the actor contract for wolves, monsters, and near wildlife with role-specific pursuit/flee/social distance. Keep distant wildlife cheap.
8. **Scale and regression:** compare the same route on LOW/HIGH and a mobile target; record frame-time percentiles, active bodies/agents, route failures, crowd stalls, and a short visual capture.

## Acceptance matrix

| Scenario | Pass condition | Evidence to save |
|---|---|---|
| Resident changes home/work/market goal | One transition, valid goal identity, no repeated target reset | state/goal trace and capture |
| Goal behind Meshy wall | Route uses street and real entrance or selects a documented fallback; actor never cuts through the wall | path overlay, collision overlay, video |
| Two people meet in narrow lane | At least one yields or waits; both resume without shaking, capsule tunneling, or permanent deadlock | repeated approaches from both directions |
| Player walks into a villager | world/player/near-NPC bodies stop penetration; villager has a readable brief response and recovers | collision debug and repeated contact capture |
| Stall is crowded | actors reserve distinct spots or queue and leave cleanly when service ends | occupancy trace and market capture |
| Player starts dialogue during travel | path motion brakes; actor turns; it resumes or returns to its prior goal afterward | state trace and capture |
| Threat interrupts work | worker leaves activity through valid path; task/anchor reservation is released or safely restored | event trace and combat capture |
| LOD promote/demote during travel | no positional snap, wall crossing, stuck body, or lost schedule state | fixed route with overlay and position trace |
| LOW and HIGH tier | visible near behavior remains correct; active actor/agent counts and frame-time stay within the measured product budget | benchmark rows on same machine/settings |

## Technical and project references

- Godot 4.6 [NavigationAgent3D guidance](https://docs.godotengine.org/en/4.6/tutorials/navigation/navigation_using_navigationagents.html) and [NavigationObstacles guidance](https://docs.godotengine.org/en/4.6/tutorials/navigation/navigation_using_navigationobstacles.html): path following, avoidance, obstacle modes, update timing, and the need for the actor controller to consume safe velocity and move the body.
- Godot 4.6 [AnimationTree/root motion documentation](https://docs.godotengine.org/en/4.6/tutorials/animation/animation_tree.html): root motion is an input to body movement; it does not replace collision handling. Keep in-place clips for the regular physics-driven movement until a specific move is deliberately validated with root motion.
- [Skelerealms](https://github.com/SlashScreen/skelerealms): study composable actor packages, schedules, patrols, perception, and GOAP as ideas. Its project README calls it active and alpha; it has no terrain, chunk/LOD, dialogue, quests, or combat. Do not transplant its framework wholesale.
- [godotdetour](https://github.com/TheSHEEEP/godotdetour): historical crowd/nav reference only. Its README says maintenance mode, limited testing, and Godot 3/GDNative assumptions; Rising Ashes is Godot 4.6 and should start with its built-in navigation unless a measured limitation proves otherwise.
- [Open-world pattern study](OPEN_WORLD_PATTERN_STUDY.md): larger project comparison, license notes, and adaptation map. Use system ideas; do not take third-party models or game content and assume that recoloring or editing clears rights.

## Source map

- `kingdom/autoload/world_sim.gd`: `_current_phase`, `_simulate_slice`, `_on_phase_change`, `_spot`, `is_indoors`.
- `kingdom/scripts/population/population_lod.gd`: near/sprite/data representation tiers, caps, promotion and demotion.
- `kingdom/scripts/population/villager.gd`: current visible villager chase and two-state animation switch.
- `kingdom/scripts/actors/player.gd`: physics-driven player capsule/controller, collision and animation input.
- `kingdom/scripts/actors/critter.gd`, `wolf.gd`, `monster.gd`: direct-position animal/hostile movement patterns and existing behavior state.
- `kingdom/scripts/world/settlement_builder.gd`: fitted static building collision and settlement streaming.
