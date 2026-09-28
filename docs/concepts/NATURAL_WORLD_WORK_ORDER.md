# Rising Ashes: Natural World Work Order

**Audience:** Claude, who owns the live game implementation.
**Purpose:** a concrete, ordered plan for making movement, animation, collision, crowds, and daily life feel like one believable world. Build on the current Godot project; do not restart it.
**Scope of this Codex handoff:** documentation and review material only. No game scripts, scenes, project settings, or Claude working files were changed to prepare this plan.

## Read this first

This file is the current implementation work order. Use the deeper design and evidence in:

- [`CLAUDE_GAME_FEEL_BRIEF.md`](CLAUDE_GAME_FEEL_BRIEF.md) — priorities and acceptance criteria.
- [`NATURAL_WORLD_CLAUDE_HANDOFF.md`](NATURAL_WORLD_CLAUDE_HANDOFF.md) — existing systems, routing and crowd design, reference patterns.
- [`REAL_WORLD_GAME_FEEL_PLAN.md`](REAL_WORLD_GAME_FEEL_PLAN.md) — code observations, previous QA, and prior Codex-side work.
- [`OPEN_WORLD_PATTERN_STUDY.md`](OPEN_WORLD_PATTERN_STUDY.md) — architecture ideas and licence cautions.
- [`HIT_KNOCKBACK_RETARGET_REVIEW.html`](HIT_KNOCKBACK_RETARGET_REVIEW.html) — latest 27-profile game-loader evaluation of the shared knockdown clip; the current one-curve cleanup is not ready for integration.
- [`../LOCAL_SESSION_HANDOFF.md`](../LOCAL_SESSION_HANDOFF.md) — ownership, active work, asset status and merge coordination.
- [`../qa/PERFORMANCE.md`](../qa/PERFORMANCE.md) — actor and device budgets.

Before implementing a milestone, fetch and inspect the latest shared branch and the live working tree. This snapshot is dated 2026-09-27; the observed Claude head was `9bb0a44e` (`LOW phone budget: region trees + impostors, Meshy LOD3, VRAM textures, mobile texture caps`). Claude had uncommitted work in `kingdom/scripts/world/assets.gd`, `kingdom/scripts/world/settlement_builder.gd`, and `docs/qa/anim_qa_report.md`, plus Godot-generated imports and QA output. Those files may have moved since this observation. Do not overwrite in-progress changes; integrate only after reviewing their current contents.

## The target experience

The player can trust solid space: walls and substantial props block movement, openings stay open, and characters do not pass through buildings. Movement starts, turns, stops and attacks feel responsive while carrying believable weight. Nearby people notice the player, make room without forming a body wall, follow routes that make sense, and return to their routines after a brief reaction. Faraway life remains inexpensive and consistent with the same world state. Animation, movement, sound, camera and gameplay events share timing.

Keep the existing third-person controller, streamed world, `WorldSim`, `CityPlanner`, population LODs, actor classes, combat, audio and quality system. Improve their handoffs incrementally. Do not replace them with a new controller or crowd framework without profiling evidence that they cannot meet the target.

## What the code snapshot shows

These are source observations to verify against the latest branch, not claims of a current live-play reproduction:

- `Player` is a `CharacterBody3D`, calls `move_and_slide()`, and its mask includes layers 1, 2 and 4.
- Nearby `Villager` is on actor layer 2, uses a capsule and world-only mask 1, and moves toward the current `WorldSim` position. It writes its resolved position back to `WorldSim` after physics. This is a useful near-actor handoff, but its mask and `_separation_force()` behavior need to be checked against player collision and other actors in the actual engine.
- `Soldier`, `CampMonster` and `Wolf` use near-player collision toggles; their default masks are world-only and their player interaction is separately enabled. Friends, foes and squads still need distinct yielding behavior.
- A near villager steers toward `WorldSim.pos[person]`; distant simulated people and impostors are not physics bodies. The handoff brief notes that distant `WorldSim` movement currently uses direct goal movement and that `CityPlanner` provides streets, door paths, lots and gates suitable for route construction.
- Buildings and landmarks use generated collision proxies derived from model bounds in important placement paths. This is cheap, but a single bounds box can cover a doorway or awning, leave gaps around protrusions, or create an invisible wall. Inspect actual production proxies in [`../qa/collision_preview/index.html`](../qa/collision_preview/index.html) before changing them.
- Animation QA found `Hit_A` reads as a short flinch while `Hit_B` is a full-body knockdown. In the observed snapshot, `Hit_B` failed floor-contact checks across 27 humanoid profiles; gameplay timing for soldier and player recovery did not match the sampled clip duration. Review and reproduce in play before changing clip choice or gameplay balance.
- Animation QA also found that the fox Run clip has remaining paw slip, loop seam and leg-pop issues. Keep those findings distinct from fixes already measured in the fox tail curve.

## Ordered implementation milestones

### 0. Establish the repeatable feel route and capture baseline

Use one representative route: leave spawn, cross the plaza and market lane, walk around a Meshy building, pass a resident, approach and enter/leave a usable doorway, cross a slope or streamed boundary, then fight one nearby enemy. Capture a short clip and log branch/commit, Godot version, device/renderer, quality tier, frame rate, and the exact reproduction point for each failure.

Record at minimum: wall/prop pass-through, false collider at door/awning, resident crossing a building, player/NPC overlap, doorway crowd jam, LOD snap, start/stop skid, turning pop, foot slip, combat event timing, camera clipping, and frame time/active actor counts.

**Accept when:** another developer can repeat the route and compare a before/after capture under the same conditions. Do not claim a visual or feel fix from a headless run alone.

### 1. Make collision match visible occupied space

First document the physics layer/mask table and verify collision behavior for player, villagers, enemies, friendlies, buildings, props, triggers, foliage and projectiles. Confirm mutual actor blocking in Godot; do not assume one body's mask is enough. Keep body collision, detection queries and interaction triggers separate.

Audit the real Meshy/generated models and their production proxy gallery. Replace overly broad building AABBs with simple compound boxes or convex shapes where needed. Model walls and occupied props, not the render mesh; preserve doors, archways, stalls, awnings and walk-under space. Give large props deliberate collision and leave decorative foliage/details non-blocking unless their trunk or solid body needs collision. Review stairs, interiors, terrain seams and streamed chunk edges too.

**Accept when:** the player and selected near actors stop at solid surfaces; doors and intended passages work from both sides; large props match their visible footprint; no reviewed route has an unexplained invisible wall. Include proxy screenshots and the repeatable in-game route.

### 2. Keep every visible resident on a plausible route

Preserve `WorldSim` as the authority for schedule, goal and persistent position. Build deterministic settlement routes from `CityPlanner` street endpoints/junctions, door links and gates; connect semantic goals (home, job, market, gate and settlement edge) to that graph. Cache paths when goals/layouts change rather than searching every frame. Check each route segment against actual building footprints and collision profiles.

For work destinations beyond town, link from a gate or street edge into a coarse terrain-aware route. If no safe connection exists, wait at a valid point or choose a nearby valid goal; do not silently fall back to a line through a building. Carry route cursor, heading and goal across near/mid/far LOD changes. When a body is promoted or demoted, transfer the final resolved position and intent before changing representation.

Use full physics only for the capped nearby tier. Mid-distance visible people need cheap steering that still respects roads and obstacles; distant schedule simulation can stay coarse. Add debug drawing for streets, doors, route legs, goals and blocked segments, plus a deterministic footprint-crossing audit.

**Accept when:** test settlements show no undeclared route crossing through buildings; distant visible people follow lanes; promotion/demotion has no pop or geometry crossing; the phone actor/update budgets remain within [`../qa/PERFORMANCE.md`](../qa/PERFORMANCE.md).

### 3. Add yielding without turning crowds into walls

Separate personal-space steering from hard collision. Nearby residents should ease, pause, or take a small side step before contact. Use deterministic tie-breaking so two agents do not mirror each other's sidestep forever. Add stuck detection: if progress stalls, wait briefly, pick a safe side step/alternate waypoint, then resume. Never clear a jam by teleporting a visible person through geometry.

Give actors role-specific priorities and behavior: residents yield to the player and keep door approaches clear; friendly followers keep formation offsets; enemies can intentionally body-block during combat; quest/interactable characters preserve access. Keep NPC-to-NPC physical collision limited to a justified local budget. Do not make the entire simulated crowd physical.

**Accept when:** a single resident, two-way lane pass, busy plaza, and doorway interaction all remain navigable, with no jitter, pinballing, long jams or repeated clipping. Record near-actor counts and crowded-scene frame times.

### 4. Match body motion, animation and audio

Measure the actual locomotion clips at the model's game scale and movement speeds. Drive gait blend and playback from resolved planar velocity, with hysteresis around walk/run thresholds. Tune acceleration, braking and facing separately so input stays responsive and starts/stops settle without skating. Inspect slopes, tight turns, backing/strafe (if clips exist), blocked movement, LOD transitions and animation interruption.

Give full-body actions explicit ownership and timing. For each attack/hit/dodge/knockdown, record windup, active/contact frame, recovery and movement lock. Align hit query, VFX, sound, impulse and hit-stop to contact. Make stun and movement recovery end in step with the chosen clip; verify sampled floor contact in game before changing a clip or balance. Use animation events or authored contact timing for footfalls where reliable; keep surface selection from terrain data. Add IK only after clip speed and controller motion agree.

**Accept when:** the baseline route has no obvious walk/run foot skating, turn snaps or recovery mismatch; measured movement and clip speed agree; a gameplay clip shows hit visuals, damage, sound and reaction on the same beat. Track remaining warnings rather than calling a mixed QA score “fixed.”

### 5. Make daily life legible and interruptible

Use the existing schedule, job and time/location data to show readable travel, work, browse, conversation and rest. Add a small set of nearby contextual reactions (notice/greet, yield, watch, flee) with range, cooldown and duration. Save and resume the prior schedule goal after a reaction. Keep door/interactable approaches clear and avoid reactions that contradict quests or teleport visible actors. Use the existing location/time-aware audio system for sparse authored ambience and event sounds; do not add crowd-wide per-frame randomness.

**Accept when:** a short time-lapse shows sensible place/time behavior; a nearby reaction returns to the prior routine; doors, dialogue and quests still work; ambience changes by place/time without stacking or spam.

### 6. Re-run the route on supported device tiers

Repeat the same route in the busiest settlement and combat area at each supported quality tier/device class. Track frame-time percentiles, active physical actors, route updates, visible population, draw/texture cost, camera clearance, and collision or animation regressions. Check low-end phone behavior before increasing nearby actor caps or navigation work. Follow existing `Quality` controls and [`../qa/PERFORMANCE.md`](../qa/PERFORMANCE.md); propose budget changes with measurements.

**Accept when:** each supported tier meets its documented budget or has a specific remaining failure/decision recorded. The same visual/gameplay acceptance route passes after all milestones.

## Suggested reviewable PR sequence

1. **Baseline + proxy correction:** capture route and fix one confirmed Meshy collider/opening mismatch; include proxy gallery evidence.
2. **Near collision contract:** verify player/resident/enemy mutual collision and correct only the required masks/toggles; capture a pass-by and doorway route.
3. **Distant route guidance:** settlement graph, route visualization and deterministic footprint-crossing audit; no general crowd rewrite.
4. **Crowd yielding:** near-tier behavior with measured actor budget and doorway/plaza playtest.
5. **Locomotion/action synchronization:** one actor/clip class per PR, backed by animation strip plus live route capture.
6. **Daily routine/reaction slice:** one resident role and one interrupt/resume reaction, then expand from evidence.
7. **Tier regression:** repeat baseline and record device/performance results.

Each PR should state: changed subsystem, files, baseline reproduction, evidence, performance delta, known failures, and a rollback boundary. Keep the plan and `docs/LOCAL_SESSION_HANDOFF.md` current when milestones land.

## Reuse boundaries

Learn from Godot navigation documentation, OpenMW path grids, Veloren's simulation/visual boundaries, and 0 A.D.'s separation of movement intent from movement execution as described in [`OPEN_WORLD_PATTERN_STUDY.md`](OPEN_WORLD_PATTERN_STUDY.md). Adapt the ideas to Rising Ashes' current Godot systems. Do not copy game code, models, textures, animations, maps or dialogue into the project. Check exact upstream licensing before any future reuse.

## Ownership and handoff

- Claude owns game implementation on its game branch and must inspect the latest working tree before editing.
- This Codex contribution is a new documentation file on `gpt/ai3d-assets`; it does not edit live game files or Claude's uncommitted work.
- Claude can choose the first milestone after reviewing current collision/route work. Keep existing quality/audio/streaming work and integrate around it.
- When each milestone is complete, append the commit, evidence link, performance result and remaining issue to `docs/LOCAL_SESSION_HANDOFF.md`.
