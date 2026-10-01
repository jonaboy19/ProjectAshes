# Systems mining: perception, alertness, interaction, save-state

Status: research + design only (no game code written). Date: 2026-10-01.
Scope: what four shipped open-source engines teach us about NPC perception and
physical/contextual interaction, and how Rising Ashes (Godot 4.6, mobile, living-world RPG) should do it.

## 0. Licence record and rules

| Project | Code licence | Assets | What we did |
|---|---|---|---|
| The Dark Mod (stgatilov/darkmod_src, `game/`) | GPL-3.0 | CC BY-NC-SA 3.0 (maps, models, sound) | read only |
| Amnesia: The Dark Descent (FrictionalGames, `amnesia/src/game`) | GPL-3.0 | proprietary, not in repo | read only |
| Penumbra Overture (FrictionalGames) | GPL-3.0 | proprietary, not in repo | read only |
| Doom 3 BFG (id-Software, `neo/d3xp`, `neo/framework`) | GPL-3.0 plus id "additional terms" | not in repo | read only |

Rules followed: nothing was copied into this repo (no code, constants tables, def files, strings or assets).
File and function names below are pointers for a future reader, not content. Numbers quoted are
engine tuning facts we use as orders of magnitude only; RA values are our own and must be tuned in the lab.
Clones lived in `/tmp/claude-0/mining/` and were deleted afterwards. Any future borrowing that is
more than "idea" level needs a licence re-check (see skill `ashes-reference-mining`).

## 1. What Rising Ashes has today (read from code)

| Area | File | Current behaviour |
|---|---|---|
| Incident bus | `kingdom/scripts/population/npc_world.gd` | static SoA store (16 slots) of fire/fight/crime/festival/scream/funeral incidents with pos, radius, strength, expiry; villagers read them as brain inputs. `report_crime()` finds villagers within `CRIME_HEARING` (40 m), "saw" = within `CRIME_SIGHT` (26 m) and `StreetGraph.clear_line`; calls `witness()`; then Society `commit_crime`. |
| Threat sight | `utility_brain.gd` `sense_threats` | picks 2 nearest hazard samples within `WATCH_RANGE` (32 m), queues one ray request per observer, global budget `THREAT_RAY_BUDGET` 4 rays / 500 ms, mailbox of delayed results. Danger memory (`remember_danger`, 75 s) with avoid push. |
| Decisions | `utility_brain.gd` | utility AI (response curves, product of considerations), const action table, 0.3 s think tick, `DECIDE_PER_FRAME` 3. No suspicion/alert state: reaction is a direct input (`_crime_until`, danger, spectacle). |
| Body | `villager.gd` | 24 tier-0 bodies, contact LOD, `witness()` just latches `_crime_until` 25 s and re-decides. Head look exists. |
| Player noise | `actors/player.gd` `noise_radius()` | walk / run / crouch radii. Used by wolf.gd and monster.gd (scales aggro). Not used by villagers. |
| Smart objects | `living_world/smart_objects.gd` | data-driven spots with typed slots, `claim/release`, approach point, sessions. Pure data, no nodes. |
| Crime | `realm/society.gd` `commit_crime` | deterministic: per-witness see chance (0.9 day, 0.55 night, flat), recognition from disguise/fame/familiarity, willingness to report from honesty/fear/affection, evidence items, investigations, bounty, `bribe_witness`, `destroy_evidence`. Witnesses arrive as a list of mostly empty ids (NpcWorld passes `""`). |
| Props | `world/breakable.gd` | MultiMesh/node props, health, shards (cap), regen when player is away; smashing in town calls `report_theft` (pickpocket crime). |
| Doors | `interiors/interior_door.gd` | enter/exit scene swap; one interior at a time; no lock, no open/close state, no NPC use, no save. |
| Save | `sim/save_manager.gd` | atomic JSON slots (schema 2, checksum, migrate chain, backup); data comes from one `snapshot_fn` (`Life.snapshot`). No world-object state beyond what Life stores. |
| Micro events | `population/micro_events.gd` | deterministic, budgeted street scenes (2 active max). |

Not present: light-aware visibility, FOV cone for villagers, suspicion meter, hearing propagation with
occlusion, search behaviour, shared search work, guard calls for help, body/evidence discovery,
locks/keys/lockpicking, door state machine, physical carry/drag, trigger volumes with target chains,
persistent prop state.

## 2. Reference findings, per subsystem

### 2.1 Visual perception

**The Dark Mod.** Sight is probabilistic and gated, not a ray every frame. Order of cheap tests in
`idAI::PerformVisualScan`: acuity > 0, in player's potential-visible-set, FOV check against head
orientation (`CheckFOV`), then `GetVisibility` (a 0..1 factor from the player's light value and distance:
constant inside a "clamp" distance, linear falloff to zero at a "safe" distance, both scaled by light), then a
random draw against `timecheck / normtime * factor`, and only then an actual line trace (`CanSeeExt`). When it
passes, alert rises by a base amount plus a bonus proportional to the visibility factor. The player's light
value comes from `LightGem` (a render of the player into a small buffer) and for NPCs/objects from
`LightEstimateSystem` (analytic sampling of the lights around tracked entities, only for entities someone
cares about). Acuity is also scaled by the AI's own alert level (more alert = sees better).
Strengths: perception is a graded, tunable pipeline with early outs; light matters; stealth feels fair.
Weaknesses: the lightgem is a render pass (too heavy for phones); randomness in the loop makes tests
non-deterministic unless seeded.

**Amnesia.** A much simpler model in `LuxEnemy`: a sight range, a shorter "darkness sight range" used when the
player's light level is below a threshold and the player is nearly still, a crouch multiplier on range, a
lantern multiplier, then a line check. Hearing is a "hear volume" compared to the player's noise. Difficulty
scales these ranges. Strengths: four numbers, easy to explain to players, trivially cheap. Weakness: binary
(seen/not seen) so no gradual tension.

**Doom 3.** Monsters use `CanSee` with FOV and a PVS gate (`Pvs.cpp`): only simulate for what the player could
see. `SecurityCamera` shows a cone sweep with a fixed scan. Lesson is the gating, not the model.

**Applies to RA:** combine TDM's pipeline shape with Amnesia's cheapness. Light value for the single player
target can be computed analytically (no render): ambient by hour/weather/indoor + registered light sources +
player lantern, cached ~4 Hz. FOV cone, distance falloff and stance multipliers are free arithmetic. The one
expensive step (ray) is already budgeted by `sense_threats`; reuse that queue.

### 2.2 Hearing and sound propagation

**The Dark Mod.** `SndProp`/`SndPropLoader`: the map is preprocessed into acoustic areas joined by portals
(doors, windows, openings). A sound event has a source loudness in dB; propagation is a wavefront expansion
over the area graph (bounded node count, stops under the lowest listener threshold), subtracting distance loss
per area, a loss per portal, and a large loss when a door portal is closed. Only areas containing listeners
are evaluated. Each listener (`idAI::CheckHearing`, `HearSound`) compares loudness to its own threshold;
alert = (1 + (loudness - threshold) * factor), capped per sound type, so a dropped coin, a footstep and a
shattering bottle give different alert amounts. Apparent origin is fuzzed and, if the true origin is not reachable,
the apparent origin is the portal the sound came through. Special-cased noisemakers are heard once each.
Strengths: believable ("they heard it through the door but could not pin it down"), event types with different
alert. Weakness: needs offline area/portal baking; per-sound flood costs.

**Penumbra.** `TriggerHandler` keeps short-lived "game triggers" (bounding volume + type + timer) which enemies
poll if their type mask matches. A sound is simply a timed volume in the world. Strength: trivial, data-light.
RA already has this shape (`NpcWorld.report`).

**Applies to RA:** we have no baked portals, but we do have the structure: settlement plans (lots, streets,
`StreetGraph`), interiors as separate scenes, and doors as nodes. Use a *two-level* model: euclidean radius
for open air, and a per-event "occlusion class" multiplier when listener and source are in different cells
(inside vs outside a building; behind a closed door; different floor). Cells are building ids from the
plan, not a flood. Event types carry `loudness_m` and an `alert_gain`.

### 2.3 Alert and suspicion states

**The Dark Mod.** One scalar alert level with five thresholds mapped to discrete states: relaxed, observant
(bark only), suspicious (look, may stop and turn), searching (investigate), agitated searching, combat.
Each state is a class with enter/exit and handlers for visual/audio/other stimuli (`State::OnVisualAlert`,
`OnDeadPersonEncounter`, `OnVisualStimDoor` ...). A "grace period" lets the AI ignore repeated low alerts
from the same source briefly so a single noise does not spiral. Alert decays over time and each state has
its own decay and timeouts; the maximum recent alert is remembered. Combat entry from sight is allowed only
inside a cutoff distance, otherwise the alert is capped just below combat (they know something is there but
not where). Strengths: one number, human-readable escalation, designers can tune per NPC. Weakness: a lot of
state classes and a huge `State.cpp`; hard to keep consistent.

**Applies to RA:** adopt the scalar + thresholds + grace idea, but map it onto the existing utility brain as
*inputs* and a few new actions rather than a second state machine: `suspicion` (0..1 scalar), `alert_class`
(0 calm, 1 notice, 2 suspicious, 3 searching, 4 alarmed) and `alert_point` (Vector2). New acts: NOTICE
(turn head/body, bark, pause), INVESTIGATE (walk to point), SEARCH (visit spots), ALARM (run to guard/shout)
sit beside the existing FLEE/WATCH/SHELTER.

### 2.4 Investigation, search, memory

**The Dark Mod.** Search is a first-class shared object (`SearchManager`): one search per suspicious event
holding a set of hiding spots computed around the alert origin (`DarkmodAASHidingSpotFinder`, sorted so the
likeliest spots come first), the search radius, and assignments of AIs to spots. Cooperative mode caps active
searchers at two, swarm mode allows many; extra AIs get guard spots (places to stand and watch). Spots are
claimed so searchers do not duplicate. `Memory` holds per-AI last-seen position, evidence-of-intruders count,
alert origin, and a list of known/searched suspicious events by id so an NPC does not react twice to the same
corpse or noise, and so friends can "tell" them (`KnowsAboutSuspiciousEvent`, `HasSearchedEvent`).
`InvestigateSpotTask` handles walk, look, wait. Strengths: searching looks intelligent but is bounded work;
event ids prevent reaction loops. Weakness: hiding-spot computation uses the navmesh/AAS offline data.

**Penumbra/Amnesia.** Enemies track last known player position and simply hunt there; no search pattern.

**Applies to RA:** the SmartObjects claim system already is the "assign unique spot" mechanism. Add a spot
kind `search` (doorways, alcoves, haystacks, barrels, behind stalls) generated with building spots; a
`Search` record per event: origin, radius, spot ids, claimed-by, expiry. Event ids with a tiny per-NPC
ring buffer prevent re-reaction.

### 2.5 Communication between guards

**The Dark Mod.** `CommunicationSubsystem` + `AIComm_Message`: typed messages (greeting, statement,
request for help, request for missile/melee help, request for light ...) with sender, recipient (entity or
radius), a position of interest and a priority; delivered after a delay with distance-limited reach; receivers
decide through their state. Also barks (`SingleBarkTask`, `RepeatedBarkTask`) are the audible feedback to the
player.
**Applies to RA:** a message is just an `NpcWorld.report` with a `kind` and an event id; add `Kind.CALL_FOR_HELP`,
`Kind.BODY_FOUND`, `Kind.SUSPICIOUS` with reach radii, and a bark line for every alert transition. Barks are
the best UX investment: players read NPC state from voice lines and speech bubbles (RA has bubbles, max 4).

### 2.6 Body and evidence discovery

**The Dark Mod.** `State::OnDeadPersonEncounter` / `OnUnconsciousPersonEncounter`: when an NPC first sees a
body it (1) marks the body as already seen by that NPC, (2) ignores bleeding markers and projectiles near
the body, (3) waits a random delay (0.5-1.5 s) so reactions are not simultaneous, (4) decides: unarmed or
civilian flees, otherwise raises evidence count and alert, and logs a suspicious event with the corpse as
source so friends can be told. "Did I see it happen" is a short time window after the fall. Similar stimulus
handlers exist for blood, missing items and doors found open that should be closed. This is built on a
stim/response layer (`StimResponse/*`): things emit typed stims with radius and timers, things with a matching
response react.
**Applies to RA:** exactly the gap we have: crimes with no witness leave no trace. Bodies, open doors, broken
props and missing owned items are *evidence entities* in an `Evidence` registry that perception scans (cheap:
only registry entries near each tier-0 NPC), and discovery later feeds Society (`add_evidence`, delayed
crime).

### 2.7 Doors, locks and usable objects

**The Dark Mod.** Everything usable is "frobbable" (`Entity` frob flags, highlight, distance, bias for which
object wins when several are in view). A door is `FrobDoor` over `BinaryFrobMover` (open/close/lock state,
swinging via rotation), a lock is a separate `FrobLock`/`PickableLock` object that can have handles
(`FrobLockHandle`) and targets, so one lock can lock several movers. Lockpicking is a pin-by-pin pattern with
click sounds and a hotspot window; failures counted, optional auto-pick. Doors have master/peer links
(double doors). NPC side: `HandleDoorTask` is a multi-step state machine (approach, safe position, wait,
open, move through, close behind, retry if interrupted), and `AreaManager` marks areas behind locked doors as
forbidden for specific NPCs in pathfinding (so a guard with the key may pass and a villager may not).
Strengths: lock separate from door, forbidden-area routing, NPC door etiquette. Weakness: a lot of
animation-coupled states.

**Amnesia/Penumbra.** `LuxProp_SwingDoor`: states closed/locked/broken, locked sound plays when interacted
while locked, auto-close when released, hint text shown once; interaction is a player state
(`InteractSwingDoor`) that drags the door by view motion against joint limits. Break damage meshes.
**Applies to RA:** door state machine (closed/open/locked/jammed/broken), lock as data (`lock_id`,
`key_id`, `level`), keys as items, NPC rules by ownership, lockpicking as a short timing mini-game with noise.
Use tweens, not physics joints.

### 2.8 Physical object interaction

**Amnesia/Penumbra.** One `PlayerState` per interaction mode: grab (`InteractGrab`), push (`InteractPush`),
slide (drawers, `InteractSlide`), rotate (lever, wheel, swing door, `InteractRotateBase`). Grab drives the
body toward a point in front of the camera with PID-controlled force and torque, clamped (max force,
max torque, max angular speed), scroll changes hold depth within min/max, the player is slowed according to
the mass held, speed is clamped when released, throw applies an impulse, and the hold breaks if the object
gets too far from the target. The held body's mass is temporarily scaled. The interaction state itself is
saved (prop id + body id + focus point) and restored in two phases (before enter / after enter).
Entity focus: raycast from camera to entities with a max focus distance, a callback on interact and on
look-at, and "interaction disabled" flag. Props are linked by named *connections* (`LuxInteractConnection`):
a lever or wheel drives a rope/door/slider, state-change events propagate with an "invert" flag and counter.
Strengths: modular states, constrained motion feels physical, connections make puzzles data-driven.
Weakness: assumes mouse-look and physics fidelity; on touch a free-drag grab is fiddly.
**Doom 3 `idGrabber`:** simple spring drag of a physics body with max trace distance, saved as an entity
pointer, damage-aware (drops if hit). Same lessons.
**Applies to RA:** touch-friendly "carry" (tap to pick up, object follows a hold point with a spring, tap to
drop, flick/throw button), mass slows movement, hold breaks on distance; only a handful of live rigid bodies;
drawers/levers/doors as constrained 1-DOF motion done with tweens and a state value (0..1), not joints.

### 2.9 Triggers, events, connections

**Doom 3.** Entities have `target` keys; `idTrigger_Multi` has `wait` (-1 one-shot), `delay`, `random_delay`;
activation calls `ActivateTargets` which posts events to targets (`PostEventMS` for delays). The event system
(`gamesys/Event.cpp`) is typed, delayed, and the saved queue survives load; post-restore fixes are done by
posting zero-delay events. **Penumbra:** timed trigger volumes handed to listeners by type mask (see 2.2).
**Amnesia:** area entities (script areas, sign, examine, sticky) call named script functions on enter/exit;
connections as above.
**Applies to RA:** data-defined trigger = {id, volume, on(enter|exit|use|state), wait, delay, once, targets[]},
targets are interactable ids + a verb. Delays use a deterministic scheduler with ints, never stored Callables.

### 2.10 Attack / damage handler and contextual interaction

**Penumbra `AttackHandler`.** A central service for line attacks (ray to nearest body, damage if player/enemy),
shape attacks (shape overlap, impulse scaled between min/max mass so heavy things barely move), "destroy body"
rays (breakables: only bodies with mass > 0 and user data), and splash damage with falloff
(`CalcSize` by distance) that is occluded by static geometry (`SplashDamageBlockCheck` only counts solid,
sound-blocking bodies). One place decides who can be hurt (target flags) so weapons do not each reimplement it.
**Applies to RA:** a single `Impact` service: `impact(kind, pos, radius, force, instigator)` that (a) damages
breakables/NPCs via a common `take_damage` contract (`breakable.gd` already has one), (b) emits a noise event,
(c) reports crimes if owned. Mass-scaled impulse for props, line-of-effect occlusion for blasts.

### 2.11 Entity/component layout and data declarations

**Amnesia:** `LuxEntity` base (id, name, active, callbacks, connections) -> `LuxProp` (physics bodies, mesh
entity, health, moving) -> specialised props (SwingDoor, Lever, Chest, Item, Lamp, NPC ...). Data from instance
vars on the placed object plus a type file. **Doom 3:** `idEntity` with `spawnArgs` (a string dictionary),
`entityDef` decls with inheritance, `thinkFlags` so only active entities enter the think list
(`activeEntities`). **TDM:** same plus `StimResponse` component.
**Applies:** JSON type tables with `extends` (we already do this for smart objects), instance = id + overrides;
only awake/near interactables process; component composition via small nodes/resources rather than deep
class hierarchies (Godot-native).

### 2.12 Save-state of interactive objects

**Doom 3** (`gamesys/SaveGame.cpp`): every entity implements `Save`/`Restore` of its own fields; objects are
indexed once in an object list, pointers are saved as indices; on load all objects are created first and only
then restored (no object may rely on others during restore; fixups are posted zero-delay events); header
has map name, version and enough to restart the level if the file is unreadable; version bump breaks
saves unless a class handles old versions by ignoring unused data and defaulting new fields.
**Amnesia** (`LuxSaved*`, `kSerializeVar` tables): per-entity save-data classes with a type id and a unique
entity id; each prop saves only its mutable state (locked, closed, broken, health, moving goals, callbacks,
connection states); the current interaction is saved by ids; maps saved per level, so returning to a level
restores it. **Penumbra:** global save of player/map/inventory/notebook/music. 
**Applies:** persistent *delta* store keyed by stable ids (we use MultiMesh clutter, so storing whole objects
is wasteful), two-phase restore, version tolerant, per-region chunks, bounded size. See section 4.6.

### 2.13 Profiling, resources, animation blending (Doom 3)

* `com_speeds` / `com_showFPS`: per-phase microsecond timers always compiled in, toggled by a cvar. RA
  equivalent: a `Prof` helper with named scopes and a lab overlay (`Performance.add_custom_monitor`).
* `DeclManager` `BeginLevelLoad`/`EndLevelLoad`: every decl "touched" during a level load is marked; untouched
  ones are purged. RA equivalent: when entering a region, record which meshes/clips/sounds were requested
  and free the rest; use `ResourceLoader.load_threaded_request` with a priority list.
* `idAnimBlend`: each animation channel has a weight with a blend time (`SetWeight(new, now, blendTime)`),
  frame commands fire events at frames (footsteps, hit frames). RA equivalent: `AnimationTree` transition
  xfade times per pair, and method-call tracks for footstep/hit events (we already have `_footstep`).
* Think lists: only entities with think flags tick. RA equivalent: our tier-0 / contact LOD.

## 3. Compare and strengths/weaknesses summary

| Topic | Best reference | RA now | Verdict |
|---|---|---|---|
| Vision pipeline | TDM gating + Amnesia ranges | rays only for hazards, no cone/light/stance | adopt; very cheap |
| Light awareness | TDM lightgem/estimate | none | analytic estimate, not render |
| Hearing | TDM propagation, Penumbra timed volumes | incident bus, flat radius | add occlusion class + event types |
| Alert states | TDM scalar + thresholds | direct brain inputs | add scalar, map to acts |
| Search | TDM SearchManager | none | add shared search over SmartObjects spots |
| Alert sharing | TDM comm + event ids | `report()` bus | add ids, help calls, barks |
| Bodies/evidence | TDM stim/response | none | add Evidence registry |
| Witness to crime | (TDM: AI alert) | immediate commit, flat see chance | add delayed reporting + light/FOV |
| Doors/locks | TDM lock/door split, HandleDoor, forbidden areas | enter/exit only | add state machine, lock data, forbidden routing |
| Props | Amnesia grab/slide/rotate states | breakables only | add carry + 1-DOF movers |
| Triggers | Doom 3 target chains, Penumbra timed volumes | micro events, incidents | add trigger def + scheduler |
| Damage | Penumbra AttackHandler | per-class take_damage | add Impact service |
| Save | Doom 3 two-phase, Amnesia per-entity ids | Life snapshot only | add WorldState delta store |

## 4. Rising Ashes designs

All new code goes in `kingdom/scripts/` following the repo's style (static/pure-data cores, nodes only at
the edge, deterministic RNG, JSON-safe state, gdUnit tests, budgets measured in tests).

### 4.1 Perception (`scripts/population/perception.gd`, static data + math)

Per tier-0 NPC (max 24) keep in fixed arrays (index = body slot, like `NpcWorld`): `alert[i]` float 0..30,
`alert_class[i]`, `alert_point[i]`, `alert_src[i]` (event id), `grace_until[i]`, `known[i]` (4-int ring of
event ids), `acuity[i]` (role: guard 1.2, villager 1.0, drunk 0.5, child 0.8), `facing[i]`.

Thresholds (own values, tune in lab): notice 1.5, suspicious 6, searching 10, alarmed 18; decay 0.8/s when
calm, 0.3/s while at search class; class never drops more than one step per 4 s (prevents flicker).

**Light level `light_at(pos) -> 0..1`** (cached at 4 Hz for the player; for NPC-as-target only on demand):
`ambient(hour, weather, indoor)` + sum over registered lights (`Perception.register_light(node, radius,
energy, flicker)`, kept in a flat array, only those within 25 m of the target, analytic falloff, no shadow
test, optional one ray for the nearest strong light) + player lantern/torch. Moonlit night ~0.15, torchlit
street ~0.5, noon 1.0. Interior scenes set their own ambient.

**Visibility factor** `vis = cone * dist_falloff * light_term * stance_term`:
* cone: 1 inside 70 degrees half-angle, linear to 0 at 110 (peripheral); head turn from `_update_head_look`.
* dist_falloff: 1 inside `near = 6 m * light_term`, linear to 0 at `far = 24 m * light_term` (guards x1.3).
* light_term: `clamp(0.15 + 0.85 * light, 0..1)`; Amnesia-style hard rule: still + dark (light < 0.3) shrinks
  `far` to 8 m.
* stance_term: crouch 0.5, walk 1.0, run 1.25, mounted 1.4, disguise reduces recognition not detection.
Gates in order: distance squared -> cone dot product -> `vis > 0.05` -> request a ray (existing queue,
`THREAT_RAY_BUDGET`). Result is `alert += (3 + 7*vis) * dt_scale` (TDM-like bonus by visibility), so a lit
player in the open fills the meter in ~1 s, a crouched player in shadow takes 5+ s or never.
Seeded determinism: no `randf()`; use `hash([npc_id, tick_index])` for any chance.

**Hearing** `Perception.emit_sound(kind, pos, loudness_m, maker)`. Kinds and default loudness (m):
footstep walk 8 / run 16 / crouch 3 (reuse `noise_radius`), door slam 14, lockpick 4, break wood 18,
break pottery 20, coin drop 9, combat clash 28, scream 40, thrown distraction 22. For each listener within
`loudness * occlusion`: `gain = clamp(1 + (loudness_eff - dist) * 0.15, 1, cap_by_kind)`. Occlusion classes:
same cell 1.0; open door between 0.7; closed door 0.35; different building, no door 0.2; interior scene vs
exterior (active interior only) uses door state. Origin fuzz: +-1.5 m scaled by distance/loudness; if
listener cannot path to source (behind locked door) the alert point is the door. Sounds are stored in the
same 16-slot ring as incidents (`NpcWorld`) so the cost is one scan per NPC think tick.

**Suspicion meter UI.** NPC head glyph: eye (notice), question mark (suspicious), searching sweep, exclamation
(alarmed); fill ring = alert fraction; shown for the 3 nearest attentive NPCs only (billboards, one shared
material). Player HUD: one edge indicator pointing to the most alert watcher (Thief-style) with haptic pulse on
class change. Barks on each upward transition (cooldown 6 s per NPC, existing bubble budget).

**Brain integration.** New inputs in `UtilityBrain.context`: `suspicion` (alert/18), `alert_class`, `heard`
(0/1), `evidence_near`. New acts: NOTICE, INVESTIGATE, SEARCH, ALARM. Considerations: villager with
`courage` low -> SHELTER/ALARM weighs more; guard -> INVESTIGATE/SEARCH weigh more; committed acts keep
the existing `committed` hysteresis. `plan_goal` gets new cases that use the street graph and the search spots.

### 4.2 Investigation and search

`Search` record in `NpcWorld` (max 4 live): `{id, origin, radius, spots[], claimed{npc:spot}, expiry, class}`.
Flow: alert class >= suspicious sets `alert_point`; INVESTIGATE walks to it (street graph, door paths), turns
head left/right 2 x 1.5 s, then if class >= searching spawns/joins the `Search` for that event id: ask
`SmartObjects.find(pos, {"act":"search"}, radius)` for the best unclaimed spot, `claim`, walk, play a short
look/peek clip, release, take next; cap 2 active searchers per search (others become "guard spots"
standing at street junctions facing the origin, TDM idea), expiry 60-90 s game-real time then decay; on
expiry the NPC writes `remember_danger` (existing avoidance memory) and returns to schedule. Evidence found
(open window, dropped item, body) adds to alert and extends expiry once. Spots generated per building lot:
doorway, alley mouth, behind stall, under cart, haystack, barrel cluster (reuse `building_spots` pipeline).

### 4.3 Alert propagation and town alert

* `Kind.CALL_FOR_HELP` (reach 40 m, guards only respond), `Kind.BODY_FOUND`, `Kind.SUSPICIOUS` (reach 15 m,
  friends only), each carries an event id; `known[i]` ring prevents re-reaction; a "tell" transfers the id,
  alert_point and a degraded alert (x0.6).
* Settlement `guard_alert` 0..3 (calm, watchful, hunting, lockdown) stored in `Society` per settlement, raised
  by alarmed class counts, decayed per game hour; it affects patrol density, gate closing (micro_events already
  closes gates), shop willingness and `treatment()`.
* Barks: one line per class transition and per message kind, picked deterministically (`NpcWorld.line`).

### 4.4 Crime witnessing -> Society (replace the flat check)

Today `report_crime` passes witness ids `""` and `commit_crime` rolls a flat 0.9/0.55 "see" chance.
Design:
1. Perception decides *seen*: `vis` of the culprit at the crime position for each candidate NPC (cone, light,
   distance, line) rather than a fixed probability. Heard-only gives `heard` (no identification).
2. Witnesses are real ids (notable ids from `Society.npcs` when the villager is a notable; otherwise
   `anon:<settlement>:<person>`), so familiarity/honour/fear in `commit_crime` actually apply. Pass
   `light`, `distance`, `disguise` into the recognition roll (`recog` falls with distance and darkness).
3. **Reporting is a task, not a roll.** Witness with `will_report` enters ALARM, runs to the nearest guard or
   shouts for help (CALL_FOR_HELP). The crime is *committed to Society only when the report is delivered* (guard
   within 6 m / call heard by a guard) or after a timeout of 25 s (town crier). If every witness is killed,
   knocked out, or loses the player and gives up, the crime stays `unreported` (rumour only, evidence on
   the ground). This gives the player counterplay (silence, outrun, bribe, disguise) and matches
   `bribe_witness`.
4. Body/evidence discovery (4.5) later creates `Society.add_evidence` and an investigation even with zero
   witnesses; solving needs `progress` as now.
5. Replace `commit_crime`'s flat see chances with parameters supplied by the caller (keep the old defaults
   when the caller gives none, so existing tests pass).

### 4.5 Evidence and body discovery (`scripts/population/evidence.gd`, static)

Registry (max 32) of `{id, kind(body|ko|blood|open_door|broken_prop|missing_item), pos, t, source, seen_mask}`.
Producers: NPC/animal death (`Villager` died), KO, `breakable` shatter inside a settlement (existing
`_report_theft`), door forced, owned chest emptied, bloody weapon use. Consumers: each tier-0 NPC think tick
checks entries within 12 m with cone + light + ray (budgeted), once per (npc, id) via `seen_mask`; random
reaction delay 0.5-1.5 s (deterministic hash); reaction by role: civilian -> FLEE + ALARM, guard -> INVESTIGATE
then SEARCH + CALL_FOR_HELP, drunk/child -> gawk. "Saw it happen" window 3 s after the event treats the
discovering NPC as a witness. Bodies are removed by `tick_day` (rot/cart away) and cleaning crews (guard job)
which also destroys evidence in Society terms. Persisted via the WorldState delta store.

### 4.6 Interaction framework

Goal: one small, uniform contract so doors, drawers, chests, levers, props and NPC use share prompts, state,
save and AI access.

**Components (Godot-native):**
* `Interactable` (node or metadata on a collider): `id` (stable: `"<site_or_settlement>/<kind>/<index or
  plan id>"`), `type` (JSON key), `verbs()` -> ordered list of `{id, label, enabled, reason}`,
  `use(verb, actor)`, `focus_changed(on)`, `max_focus_distance`, `owner` (household/faction/none). Types in
  `data/world/interactables.json` with `extends`.
* `WorldState` (autoload or `Life` module): `Dictionary id -> state dict` plus helpers `get_state(id,
  defaults)`, `set_state(id, patch)`, `dirty` list; serialisation is deltas only (anything equal to default
  is dropped). Pure data (RefCounted) so tests and the data-tier world can query without nodes.
* `InteractFocus` on the player: one ray / overlap at 10 Hz from the camera or tap point, picks best by
  distance + view angle + priority bias (TDM frob bias), shows prompt with primary verb; mobile: tap the prompt
  to do the primary verb, long-press for a radial of at most 3 more verbs.
* Verb priority: use/open > unlock (key) > pick up/carry > lockpick > examine > break. Contextual by state:
  locked + have key -> "Unlock"; locked + lockpick -> "Pick lock"; owned + seen -> label shows "(stealing)".

**Doors** (extend `interior_door.gd` into `Door` with the interior swap as one `use` result):
state `CLOSED, OPENING, OPEN, CLOSING, LOCKED, JAMMED, BROKEN`, `open_amount` 0..1 tweened 0.5 s (no joint),
auto-close when released/after 20 s if owner NPC-managed, `lock` sub-record `{key_id, level 0..5, picked
progress}`, noise events on slam/forced/lockpick, double-door peer link. Path integration: `StreetGraph`
door edges get `blocked_for(npc)` = locked and npc lacks key/ownership (TDM forbidden areas), households have
keys to their lot, guards have a master key for public buildings, shops lock by `work.gd` hours (closed at night).
NPC passing: approach point, 0.4 s pause, play open, pass, optional close (HandleDoor-lite, 3 states).
**Locks:** lock is data, not a node: `lock_id` shared by door + chest + gate so one key family works;
lockpicking = timing mini-game (sweet-spot sweep, 3 pins for level 3, pin sound per click, fail resets pin,
failure noise + tool wear), difficulty from skill; auto-pick option off by default. Breaking: damage from
`Impact`, health per door class, loud + crime if owned and witnessed.
**Drawers / chests / containers:** 1-DOF slider state 0..1 (tween), contents rolled once from ItemsDB with
seed `hash([WORLD_SEED, container_id])` and then stored as a taken/added delta; `searched` flag; owned
containers raise theft crime when an item is taken in view (`report_crime("burglary")`).
**Levers/buttons/wheels:** 1-DOF state with `targets` list; `Connection` data `{from, to, verb, invert}`
(Amnesia) resolved by id, evaluated by the trigger system.
**Physics props:** carry mode (tap to lift, hold point 1.2 m ahead, spring toward it with max force, mass
slows player, drop on distance > 3 m or hit, throw button impulse scaled by mass, noise on impact above a
speed). Only `RigidBody3D` for lifted/pushed items and the first 8 near the player; the rest static until
touched ("think flags"); settle -> freeze and write transform delta to WorldState if moved > 0.5 m.
**Triggers:** `TriggerDef {id, shape, on, wait, delay, once, targets[{id, verb, args}]}` in
`data/world/triggers.json` (+ site plan hooks). Evaluated by a 5 Hz `Triggers` service on registered Area3Ds or
cell tests (no per-frame scripts); delays through `Scheduler` (sorted array of `{t, id, verb}` ints and
strings only, saved in WorldState) so a save mid-delay resumes.
**Impact service** (Penumbra AttackHandler idea): `Impact.hit(kind, pos, radius, force, instigator)` ->
damage via `take_damage(amount, from, knockback)` (existing contract in `breakable.gd`), noise event,
ownership crime, splash falloff by distance, occlusion by one ray to solid static for explosions.

**Save-state (Doom 3 + Amnesia lessons):** `WorldState.snapshot()` -> `{"v":1,"objects":{id: {...deltas}},
"sched":[...],"evidence":[...],"searches":[]}` written under key `interactives` in the Life snapshot (so the
atomic writer, checksum and backup already protect it). Restore is two-phase: (1) `WorldState.restore(data)`
loads the dictionary only, (2) when a region/settlement/interior builds its nodes, each `Interactable.ready`
pulls its state by id and applies it silently (no sounds, no events); anything referring to ids not present
yet is kept until the region streams in. Never store node paths or Callables; ids only. Unknown ids and
unknown keys are ignored; new keys default (version tolerance). Data-tier owner for unloaded regions:
delta dictionaries per `region_id` so loading a settlement costs one dictionary read. Cap: 4000 object
deltas (~200 KB JSON), prune deltas back to default and regen (as `breakable` already does). Bump `SaveManager`
schema 2 -> 3 only if the envelope changes; adding a key inside `data` needs a default in restore, not a bump.

### 4.7 Mobile budgets (S22-class target, 60 fps = 16.6 ms)

| Item | Budget | How |
|---|---|---|
| Perception total, 24 NPCs | <= 0.25 ms/frame avg | think tick 3.3 Hz staggered (3 decisions/frame), cone/dist math only; <= 4 rays per 0.5 s globally (existing) |
| Light level | <= 0.03 ms | 4 Hz cache, <= 24 registered lights within 25 m |
| Sound events | <= 0.05 ms | ring of 16, one scan per NPC think |
| Evidence scan | <= 0.05 ms | 32 entries, spatial early out |
| Search spots | <= 0.05 ms per claim | SmartObjects grid cell lookup |
| Interact focus | <= 0.1 ms | 10 Hz physics ray |
| Door/drawer tweens | negligible | tween only while moving |
| Live rigid props | <= 8 near player, shards <= existing cap | freeze on settle |
| Trigger service | <= 0.05 ms | 5 Hz, only triggers in active region |
| WorldState snapshot | <= 5 ms, <= 200 KB | deltas only, run on autosave tick not in a frame spike (chunk by region) |
| Alert glyphs | 3 billboards, 1 material | no per-NPC UI nodes |

### 4.8 Lab tests (headless where possible)

* Perception: given player at distance d, light L, stance s, facing f, assert `vis` table and time-to-alert; a
  crouched player at 10 m under L 0.2 is never noticed in 20 s, a running player at 10 m under torchlight is
  noticed in < 1.5 s. Determinism: same seed -> same sequence.
* Hearing: sound at 12 m with closed door gives alert < sound with open door; outdoors distance monotonic.
* Search: 3 NPCs, 5 spots -> no duplicate claims, search expires, memory written.
* Crime: kill the only witness before report -> crime unreported; witness reaching guard -> committed once.
* Doors/locks: locked path blocked for villager, open for key owner; save/load round-trip equality of
  WorldState incl. mid-delay scheduler entry.
* Cost test with loose limit (CI is slow), as `ashes-realm-module` requires.

## 5. Gap list vs current code, with priorities

| P | Gap | Where | Effort | Notes |
|---|---|---|---|---|
| P0 | Alert scalar + classes + decay, new acts NOTICE/INVESTIGATE | new `perception.gd`, `utility_brain.gd`, `villager.gd` | M | foundation for everything below |
| P0 | Vision factor: cone, light, stance, distance | `perception.gd`, player stance | S | reuse ray queue |
| P0 | `WorldState` delta store + save integration | new, `save_manager.gd`/`Life` | M | blocks door/chest/prop persistence |
| P0 | Door state machine + lock data | `interior_door.gd` -> `door.gd` | M | after WorldState |
| P1 | Hearing events with occlusion class, loudness per kind | `npc_world.gd`, `player.gd`, `breakable.gd` | S | wolves/monsters can share it |
| P1 | Delayed crime reporting + real witness ids + light-aware see chance | `npc_world.report_crime`, `villager.witness`, `society.commit_crime` | M | keep default args for tests |
| P1 | Evidence/body registry and discovery | new `evidence.gd`, villager, society | M | closes the "no witness no crime" hole |
| P1 | Search object over SmartObjects spots | `npc_world.gd`, `smart_objects.gd`, `utility_brain.gd` | M | spot type `search` |
| P1 | Interactable contract + focus + verbs, mobile prompt | new + HUD | M | |
| P1 | Barks and alert glyphs | `npc_world.gd` lines, UI | S | big readability win |
| P2 | Keys, lockpick mini-game, forbidden-door pathing | items, `street_graph`, UI | M | |
| P2 | Alert sharing (ids, tell, call for help), settlement `guard_alert` | `npc_world.gd`, `society.gd` | M | |
| P2 | Containers/drawers with deterministic loot + theft | `home_chest.gd`, ItemsDB | S | `home_chest.gd` exists, extend |
| P2 | Trigger defs + Scheduler | new | M | |
| P2 | Impact service, noise from breakables, mass-scaled impulse | `breakable.gd` | S | |
| P3 | Carry/throw physics props | player | M | only if a puzzle/feature needs it |
| P3 | NPC door etiquette (open, pass, close, retry) | villager, door | S | |
| P3 | Prof scopes overlay, region resource touch-and-sweep | tools | S | Doom 3 lessons |
| P3 | Light registry for dressing (torches/lamps) | `micro_events` lamps, dressing | S | feeds light_at |

## 6. Top lessons (short)

1. Perception is a pipeline of cheap early-outs ending in one budgeted ray.
2. Light and stance are the stealth levers; four numbers (Amnesia) carry most of the feel.
3. One alert scalar with thresholds is easier to tune and test than many states.
4. Event ids make reactions idempotent and let alerts be "told" between NPCs.
5. Searching = shared spots with claims; we already own the claim primitive.
6. Evidence (bodies, open doors, missing items) is what turns unwitnessed crimes into gameplay.
7. Crime must be *reported*, not rolled; that gives counterplay.
8. Locks are data shared by doors/chests; routing must know who may pass.
9. Save only deltas keyed by stable ids; restore in two phases; ignore unknown, default new.
10. Mobile: tween 1-DOF motion instead of physics joints; touch needs tap-carry not drag-PID.
