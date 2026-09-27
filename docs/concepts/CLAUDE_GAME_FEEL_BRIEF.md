# Rising Ashes: Game Feel Implementation Brief

**For:** the Claude session working on the game code
**Purpose:** make movement, animation, collision, combat and daily life feel connected and believable while building on the current game. This is a design handoff only; it changes no game code, scenes, assets or project settings.

## Read first

Use this brief with [`NATURAL_WORLD_CLAUDE_HANDOFF.md`](NATURAL_WORLD_CLAUDE_HANDOFF.md) for the detailed staged plan and with [`REAL_WORLD_GAME_FEEL_PLAN.md`](REAL_WORLD_GAME_FEEL_PLAN.md) for the current Codex-side findings and QA. Fetch the latest shared branch and read `docs/LOCAL_SESSION_HANDOFF.md` before implementation. Inspect current files and uncommitted work first; this brief describes goals and acceptance criteria, not an assumption that a subsystem is missing or safe to replace.

The project already has a third-person controller, streamed settlements, scheduled population simulation, nearby physics actors, distant impostors, combat, animation blending, terrain-aware audio and collision preview tools. Keep those systems and improve their handoffs. Make focused changes in reviewable stages. Do not start over with a new controller, crowd framework or world architecture.

## Priority order

### 1. Make solid things solid and openings usable

First establish a repeatable in-game route through a settlement: cross the plaza and market lane, walk around a Meshy building, enter and exit a doorway, pass a resident, and engage one nearby enemy. Record the build/branch, quality tier, frame rate and reproduction steps for every collision failure.

Audit the actual production collision proxies using `docs/qa/collision_preview/`. Mesh appearance alone does not provide collision. Meshy houses, stalls and props need deliberate low-cost collision shapes or documented non-blocking behavior. Prefer simple wall/support/counter volumes over a whole-model AABB when it fills a doorway, canopy or empty interior. Keep trigger areas separate from solid collision. Confirm player, resident, enemy and world layer/mask behavior, including which actors block one another.

**Done when:** the player and near physical actors cannot pass through solid building walls or substantial props; doorways and intended under-canopy paths remain open; residents do not appear to route through buildings; no invisible collision blocks a normal route. Include screenshots or a short gameplay capture of the route and the collision gallery for any adjusted proxies.

### 2. Give every visible resident a safe route

Reuse `CityPlanner` settlement streets, door-to-street paths, gates and building lots to build a deterministic low-cost route graph. Keep `WorldSim` as the authority for schedules, destinations and persistent positions. Route distant simulation and visible impostors over this graph so they do not cut straight through buildings. Use full physics and local navigation only for a small, capped set of nearby actors. Check route legs against building footprints and ensure promotion/demotion between impostor and physical actor preserves position and heading.

For nearby actors, add gentle personal-space steering and yielding before hard collision. Separate player, villager, friendly and hostile behavior so a busy doorway does not turn into a wall of bodies. Resolve deadlocks with a short wait, a small sidestep or a nearby alternate waypoint; never push actors through geometry to clear them.

**Done when:** a route overlay/report shows paths around buildings; plaza, doorway and market pass-by cases stay navigable; distant people follow plausible lanes; switching between simulation LODs produces no visible teleport or geometry crossing; crowd additions stay within the budgets in `docs/qa/PERFORMANCE.md`.

### 3. Make movement and animation describe the same motion

Tune measured clip speed against actual actor speed, scale and stride. Blend walk/run from velocity with hysteresis, ease starts/stops/turns, and ensure playback-rate changes do not reset during activity clips. Keep input response immediate while giving the body believable acceleration and braking. Check planted-foot slip, foot height on slopes, turn-in-place, direction changes, recovery after blocking, and the transition between idle, work and travel.

For combat, make attack windup, active hit window, hit reaction, sound and visual effect share a clear timeline. Buffering and dodge responsiveness should remain readable. Do not adjust damage or combat balance as a side effect of animation polish without recording the separate gameplay decision.

**Done when:** the stable settlement route includes close start/stop/turn and obstacle interactions with no obvious foot skating or pose snapping; attack footage shows impact and hit feedback at the same beat; any unmeasurable clip or remaining slip is explicitly reported rather than marked passed from a headless run.

### 4. Make schedules and reactions readable

Use existing time, job and location data to give residents a few understandable states: travel, work, browse, converse and rest. Add short local reactions such as greeting, yielding, watching an event or fleeing danger, then resume the prior destination. Keep reactions interruptible and bounded by time/range. Keep interaction targets and doors available; do not let ambient behavior contradict quests or teleport a visible person.

Use the existing location/time-aware audio director and event sounds at authored moments. Avoid per-frame random behavior or crowd-wide sound spam. Continue to use distant simulation and impostors for population scale.

**Done when:** a short time-lapse shows people moving between appropriate places and times; nearby reactions return to routine; player interactions remain reliable; ambience follows place/time without uncontrolled stacking.

### 5. Recheck camera, terrain and performance

Repeat the route at close and zoomed-out camera distances, across a doorway, slope, bridge and streamed chunk edge. Check foliage separately from trunks so camera obstruction is handled without making all leaves solid. Measure crowded plaza and battle frame times, active physics actors, route updates and animation load at the supported quality tiers. Preserve `Quality` limits and record before/after measurements.

**Done when:** the camera stays clear of walls and terrain while keeping the player readable; movement does not snag on valid seams; no quality tier exceeds its existing actor/performance budget without an explicit decision.

## Architecture and reuse guardrails

- Extend the current `WorldSim`, `CityPlanner`, `PopulationLOD`, `Villager`, player and combat actor systems where they already own the relevant state. Keep one clear owner for schedule/destination data and feed resolved physical positions back to it.
- Do not put physics bodies on every simulated resident. Use street/door graph routing for distant actors, physics for nearby actors, and soft yielding for crowd comfort.
- Do not use render-mesh triangle collision as the default for buildings or props. Use reviewed primitive/convex shapes that preserve openings.
- Keep route generation deterministic and cache/reuse settlement data. Profile before adding per-agent navigation work.
- Study the source patterns linked in `NATURAL_WORLD_CLAUDE_HANDOFF.md` (Godot navigation, OpenMW path grids, 0 A.D. movement separation and Veloren scale boundaries). Adapt concepts to this Godot project's systems; do not transplant code or assets. Check upstream licences before any future reuse.
- Keep each milestone small enough to compare against the baseline and roll back independently. Update the detailed plan and `docs/LOCAL_SESSION_HANDOFF.md` with implementation, evidence, remaining failures and ownership.

## Suggested first pull request

Start with the settlement route and collision audit, then fix the highest-impact false wall or missing solid collider revealed by it. Include the route notes, before/after evidence and a focused collision regression check. Do not combine a broad controller rewrite, full crowd rewrite, animation overhaul and collision overhaul into one change. After the audit, take the routing foundation as the next isolated milestone.

