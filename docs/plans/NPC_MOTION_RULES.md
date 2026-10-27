# NPC motion rules: one layer every NPC uses (design, 2026-10-27)

Owner request: "make a lot of systems that make things easier for animations: NPCs will avoid this, or do that, move like that, etc."
Goal: write each rule once, as data plus pure logic. Every body (villager, guard, bandit, follower, micro-event actor) gets it automatically, so Ashford looks alive without hand-authoring each scene.
Bar: `ashes-aaa-gate` (judged by eye against `docs/plans/ref_aaa/`), `ashes-best-tool-first`, `ashes-melee-combat`, `ashes-world-interaction`, `ashes-perception-ai`.
Status: this is a design only. No code changed.

---

## 1. Audit: what exists

| Piece | What it does | Solid | Missing for this layer |
|---|---|---|---|
| `living_world/smart_objects.gd` + `data/living_world/smart_objects.json` (33 types) | Pure-data spots. `find` / `claim` / `release` per slot. Each slot has an auto stand point (taken from the clip anchor). A `Session` state machine runs APPROACH → ALIGN → ENTER → LOOP/BETWEEN → EXIT, with interrupt, variant shuffle and seat offsets. | Claims are race-safe (tokens). Deterministic variants. A grid index. Search spots reuse it. | No IK targets (hand on bucket, handle or rung). Enter/exit is one clip per type, with no per-side or per-slot transitions. Only `well` has `queue`. No `approach_dir` or entry arc. No clearance or "occupied look" (people watching a busy anvil). Nothing maps needs to types beyond `acts`/`jobs`. |
| `living_world/life_actor.gd` | Reference body: walk, use spot, carry, chat, routine. | A clean worked example of every piece wired together. | It is a demo body. Villager and micro_actor wire the same pieces again by hand, which is the duplication this layer removes. |
| `living_world/life_ambience.gd` | Per-person traits from a hash: walk_speed, anim_rate, height, gesture, curiosity, restless, mood, walk style (happy, sad, brisk, elder, cane, kid skip). Also fidgets, glances at the player or a LivingEvent, and the rain hunch upper layer and pace. | Deterministic, allocation-free, and already gives personality. | Glances are not shared under a global budget and have no priority against other look sources. Weather covers rain only (no sun shading, cold or snow gait). Gesture amplitude is not applied to clips (only used to pick a clip). |
| `living_world/carry_errand.gd` | PICKUP → CARRY → SETDOWN with a composite carry upper layer. Drops the load when the NPC runs (`drop_to_ground`, kept 30 s). | Prop timing at the bottom of the bend. The load is dropped on urgent acts. | The carry gait is only an upper layer (no heavier stride, lean or slower pace). No load-aware yielding. No "flee and drop" clip (the load just detaches). |
| `living_world/contact_ik.gd` | A SkeletonModifier3D for pelvis and hand ground contact on kneel, dig and sit clips. Budget 4, range 15 m, requested and released per clip sidecar. | **The cost pattern to copy**: about 0.03 ms per NPC, created only when needed, a global budget. | Only reaches down to the ground. No hand-to-prop targets and no feet on slopes or stairs. |
| `living_world/crowd_anim_lod.gd` | NEAR (every frame, look-at, shadows), MID (stepped 1/2..1/8, phase-correct, no look-at), FAR (VAT twin at the same clip time), OUT (sprites). | Measured and seamless. Bucketed so there are no spikes. | Rules must degrade to it: at MID only clip and steer, at FAR only the base clip. No rule may assume a modifier exists beyond NEAR. |
| `living_world/life_library.gd` + `*.life.json` sidecars | About 285 life clips in 10 GLBs, with category, loop, layer, props, enter/exit, anchor and tags. `clips_tagged`, `composite(lower, upper)`. | Composite upper/lower layering with no AnimationTree (cheap). | **Tags are inconsistent**: Work, Mixamo5 and Meshy have no tags, and Mixamo_Farm only has `farm`. No verb/posture/prop/mood axes. No picker with no-repeat. Combat and AAA packs (`aaa/*.clips.json`, `data/anim/aaa_clips.json`) live in a different index. |
| `living_world/living_events.gd` | A 32-slot ring of world events (clang, cart, shout) with radius and ttl. `nearest()`. | O(1) emit, cheap scan. | No priority or kind class (loud, threat, social). There is a second bus in `NpcWorld.report` / `report_sound`, so events are split across two buses. |
| `population/villager.gd` (hot file, 2561 lines) | StreetGraph routing, hand-rolled `_neighbour_push` (0.9 m), player personal space (1.2 m, or 2.8 m while armed), `_check_yield` sidestep off the player's line, gait with speed-matched `speed_scale` and stride, head look via a priority if-chain, carry, sessions, ContactIK, face card, TalkPose. | Feet do not slide (clip speed matching). Yields to the player and to mounted riders. Steps aside for vehicles (`NpcWorld.mover_push`). Brakes and slows at corners. | **No reciprocal NPC↔NPC avoidance** (only a push, so head-on pairs dance). No pass-side convention, no shoulder turn, no lanes or road edges, no hazard avoidance (mud, puddles), no start/stop/turn clips, no lean. The head look is one if-chain with no budget. Foot IK was disabled (P6: −14..−22 fps on HIGH). |
| `population/utility_brain.gd` | 27 acts scored by response curves. Needs, personality, danger memory, THREAT_RAY_BUDGET, CHAT_GAP 1.3, chat assembly, QUEUE act. | Deterministic and tested (`test_utility_brain`). The single decision maker (per the perception skill, never add a second state machine). | Acts do not carry a motion style (hurry, cautious, tired). There is no "need → smart-object type" table, because the mapping is spread across villager.gd. |
| `population/reaction_adapter.gd` + `reaction_request.gd` | 16 reaction kinds (GLANCE, STEP_BACK, STEP_ASIDE, FLINCH, FLEE, KNEEL, HIDE, …) with layer HEAD/UPPER/LOCO/BODY, priority, duration and keeps_activity. `clip_hint` is free text. | The right abstraction: AI emits a kind, and the adapter maps it to the body. | `clip_hint` maps to no real clip (the stub is still a stub). No STARTLE, GATHER, CROWD_RIPPLE, DROP_LOAD_FLEE or WEATHER kinds. |
| `population/presence.gd`, `perception.gd`, `witness.gd`, `alert_net.gd`, `search.gd` | Staged notice → check → decide. Alert scalar, vision and hearing, search spots claimed through SmartObjects. | Budgeted and tested (`test_perception`, `test_search`). | Its output reaches the body only as reaction kinds plus `_react_look_until`. No shared attention budget. |
| `population/npc_world.gd` | Incident ring (fire, fight, crime, festival). Armed pressure, movers (`mover_push`), crop fields, bread queue (`queue_spot`, QUEUE_GAP 0.85), barks. | One stimulus bus for the near tier, with fixed storage. | Queues exist for the bread line only. No "fight ring" geometry for bystanders. |
| `population/micro_scene.gd` / `micro_actor.gd` | Scripted micro events (vehicle, walkers, chase, procession, carry …) on the same models and clips. | Reproducible and seeded. | Actors get none of the villager's steering or attention, so the same rules would have to be written a third time. |
| `population/talk_pose.gd` | Turns the body to the player during dialogue. Pure and tested. | — | Covers a 1:1 conversation with the player only. No circle, no turn-taking, no listener gestures. |
| `actors/procedural_rig.gd` | Player: TwoBoneIK3D foot IK with foot lock and heel phase, torso spring, prop springs, SpringBoneSimulator3D, hand brace/assist/carry IK, torso yaw offset. | AAA-grade player feet and props. | Too expensive for crowds (P6). Usable on NPCs only as a **budgeted NEAR-only request** like ContactIK. |
| `actors/follower_brain.gd` | Pure orders and formation slot offsets, follow / catch-up / teleport speeds, fighter leash, revive. | Tested (`test_follower_bodies`). | Fixed slot offsets with no personality, no side-by-side walk-and-talk, no shared avoidance with villagers. |
| `combat/*` (combat-motion worker) | `combat_motion` (root-motion warp), `combat_reactions` (direction × strength × state), `lean_aim` (lean into turns + aim twist modifier), `guard_legs`, `partial_ragdoll` (PhysicalBoneSimulator3D upper body), `knockdown_state`, `creature_attack_tokens`, `npc_fighter`. | The motion layers the AAA bar wants, already built and tested (`test_combat_reactions`). | Bystanders do not use them. Bandit groups have tokens but no group tactics (surround, flank, regroup or flee as a group). |
| Addon **LimboAI** 1.8.1 (GDExtension, Linux bins present) | BT + HSM. | — | **Unused**. Candidate for squad-level bandit tactics only (one BTPlayer per squad, not per NPC). |
| Addon **GodotGAS** | Abilities, attributes, tags. | — | Rejected for skills before (`sim/skills.gd:29`, too node/resource heavy). Not needed here: tags live in JSON. |
| Addon **godot_material_footsteps** | A per-step raycast material detector. | — | Not enabled and not used. Villagers already sample `Audio.surface_at` every 1.5 s, which is cheaper. Use the addon for the player only (out of scope). |
| Built-in **NavigationServer3D avoidance (RVO/ORCA)** + `NavigationObstacle3D` | Reciprocal velocity avoidance with per-agent radius, priority, layers and time horizon, server-side and multithreaded. Works without a navmesh query (agents on a map, routing stays on StreetGraph). | — | **Unused** (no NavigationAgent3D or agent RIDs anywhere). This is the fix for the head-on dance. |
| Built-in **LookAtModifier3D** | Used by villager, life_actor and player. Has angle limits, transition duration and ease. | Present on every embodied villager (NEAR only). | Villager lerps the target itself at 0.12 s instead of using `duration`/`transition_type`. No per-NPC limit tuning. |
| Built-in **TwoBoneIK3D / SkeletonModifier3D / PhysicalBoneSimulator3D / SpringBoneSimulator3D** | Used by the player, horses, ragdoll, combat. | — | NPCs only get ContactIK. Verify the 4.6.3 class list (`ClassDB.class_exists`) before using any IK3D class other than TwoBoneIK3D. |

**Verdict.** The ingredients are good and mostly tested. What is missing is the **layer between "the brain decided" and "the body plays"**: one rule set with arbitration, a budget and LOD-degradation that every body type calls. Today villager.gd hard-codes about 15 of the rules below, and micro_actor, follower_body and soldier hard-code none of them.

---

## 2. Architecture (built-ins first, pure logic, one hook per body)

```
brain (utility_brain / npc_fighter / follower_brain / micro scene)      -> WHAT (act, target, spot)
perception + presence + NpcWorld + LivingEvents                          -> stimuli
        |                                                     
MotionRules.evaluate(ctx, persona, tier) -> MotionIntent    (pure, static, data/living_world/motion_rules.json)
        |  channels: BODY > LOCO > UPPER > HEAD, each with priority, min-hold and blend time
MotionApply (node side, ~150 lines, one per body type adapter)           -> AnimationPlayer / composite / LookAt / IK request / RVO velocity
```

- **`scripts/living_world/motion_rules.gd`** (pure, static, no nodes) takes a `ctx` dictionary (position, velocity, heading, act, tier, carrying, injured/tired/drunk, weather, hour, the nearest stimuli, corridor width, group slot) and returns a `MotionIntent`:
  - `steer`: a desired velocity offset and a speed multiplier, or stop.
  - `look`: target, priority and hold time.
  - `gait`: clip and rate.
  - `upper`: a composite clip.
  - `oneshot`: a clip and channel.
  - `lean`: radians, applied to the model root as a roll, so it costs no skeleton update.
  - `ik`: a list of `{limb, target, weight}` that is only honoured at NEAR within budget.
  - `reaction`: an `RR.Kind`.
- **Arbitration.** Each rule writes one or more channels with a priority. The highest priority wins per channel. Hysteresis uses `min_hold_s`. A BODY-channel winner (flee, kneel) suppresses LOCO and UPPER. This is the same layer model as `reaction_request.Layer`, which is reused rather than reinvented.
- **Data.** `data/living_world/motion_rules.json` has per-archetype parameters (`villager`, `child`, `elder`, `guard`, `bandit`, `follower`, `merchant`, `noble`): space radius, RVO radius and priority, yield rank, curiosity, gesture amplitude, gait set, and the head-turn limit in degrees. Every rule row has an `enabled` flag and its thresholds, so the rules are tunable without code.
- **Clip picker.** `scripts/living_world/clip_picker.gd` answers `pick(verb, {posture, prop, mood}, persona, last)` over one normalised tag index (`data/anim/motion_tags.json`, generated from every `*.life.json` + `aaa/*.clips.json` + `data/anim/aaa_clips.json`). It weights by personality, avoids a recent repeat with a per-NPC ring of 3, and seeds the choice from `hash([person, day, cycle])`.
- **Attention director.** `scripts/living_world/attention.gd` keeps one global table of look requests and allows at most `LOOK_SLOTS` NPCs with an active non-forward look (6 HIGH, 3 LOW). Priorities: threat 6 > the person addressing you 5 > loud event 4 > the player within 3 m 3 > a conversation partner 2 > an ambient point 1. Each NPC has a 4–9 s cooldown per source. It replaces the if-chain in `villager._update_head_look` and the glances in `LifeAmbience`.
- **Steering.** Every NEAR and MID body is a NavigationServer3D avoidance agent: an RID per body with `radius`, `avoidance_priority` and layers per archetype, `time_horizon_agents` 1.5 s and `max_neighbors` 6. Carts, horses and the mounted player are `NavigationObstacle3D` with a velocity. Routing stays on StreetGraph. RVO only bends the velocity, and the existing `_neighbour_push` stays as a fallback on LOW.
- **Write once.** villager.gd, micro_actor.gd, follower_body.gd and army/soldier.gd each get a hook of about 5 lines (build the ctx, call `MotionRules.evaluate`, call `MotionApply.apply`). life_actor.gd is the reference adapter.

### Perf tiers (every rule declares its lowest tier)
| Tier | Range (HIGH) | What rules may output | Budget |
|---|---|---|---|
| NEAR | CrowdAnimLOD near (about 15–20 m, nearest N) | Everything: look-at, budgeted IK (≤4 hand, ≤4 contact), oneshots, upper composites, lean, RVO | Rule evaluation ≤0.15 ms per frame for 24 bodies (staggered at 3.3 Hz think). No new rays: reuse perception's ray budget. |
| MID | to mid_dist | Steering (RVO), gait clip and rate, upper composite, oneshots. No look-at and no IK. | 0.02 ms per body |
| FAR (VAT) | to far_dist | Steering plus the base clip only. Every rule's clip must have a VAT-baked fallback (`vat_bake.json`), or it resolves to Walk/Idle. | ~0 |
| OUT | beyond | None (WorldSim intent only) | 0 |

---

## 3. The rule set

ID prefixes are S steering, A attention, R reactions, O smart objects, L locomotion, G groups, C clip selection, B combat.
Clip column: **have** = in the library today, **MISSING** = see §5.
Tests are gdUnit, headless (`tests/test_motion_*.gd`). Gates are Movie Maker shots from playtest_bot stages (`tools_qa/acceptance/`) on the Ashford slice, at 1280×720, 30 fps fixed, 11:00, HUD hidden.

### 3.1 Steering and personal space
| # | Rule | Trigger / perception | Behaviour | Motion layer (clip tag / additive / IK / look / procedural) | Built-in / addon | Extend | Tier | Test | Visual gate |
|---|---|---|---|---|---|---|---|---|---|
| S1 | RVO avoidance per type | always while moving | Reciprocal avoidance. Radius and priority per archetype: guard 0.9, noble 0.8, adult 0.5, child 0.3. A loaded carrier ranks higher (others give way). | procedural velocity, gait rate follows the resolved speed (exists) | NavigationServer3D agent RIDs, `avoidance_priority`, layers | villager `_neighbour_push` (keep for LOW), `motion_rules.json` | NEAR+MID (FAR keeps the push) | `test_motion_steer`: 2 agents head-on in a 2 m corridor pass within 3 s with no overlap under 0.45 m. Priority: the lower rank deviates more. | `npc_crossing`: 6 villagers cross the market. No dancing, no clipping. |
| S2 | Yield / give way | another agent with a higher yield rank on a collision course within 2.5 s, or the player (exists) | The lower rank slows to 0.4× and steps 0.6 m to its pass side, the higher rank barely deviates. Elders and loaded people get way. | gait rate down, STEP_ASIDE reaction | RVO priority | `villager._check_yield` (generalise from player-only to any agent), `reaction_request` | NEAR+MID | yield truth table (rank × load × age) | `npc_crossing` |
| S3 | Pass on the right + shoulder turn in narrow alleys | corridor width under 1.6 m (StreetGraph clearance) and an oncoming agent within 3 m | Both keep right. The NEAR body plays a 0.6 s shoulder-turn (torso yaw 30–40°) as they pass and looks at the other briefly. | upper composite `Life_Pass_Shoulder_Turn_Upper` (**MISSING**, generated in Blender) + look-at A1 | LookAtModifier3D | StreetGraph `clear_line`/`push_out` (new `corridor_width(p)`), clip_picker | NEAR (MID: side bias only) | side convention, trigger window, no turn when width is 2 m or more | `npc_alley_pass`: two villagers pass in the Ashford side street |
| S4 | Stop for carts and horses | `NpcWorld.mover_push` / mover lookahead 3 s inside 2.6 m | Stop at the kerb (or step aside if already on the lane), watch it pass, resume. Children are pulled back by an adult in the same group (G2). | stop clip (Loco_WalkStop, **share**), look at the mover | NavigationObstacle3D with velocity on vehicles | `npc_world.mover_push`, micro_scene vehicle | NEAR+MID | stop-before-collision for 50 seeded cart passes | `npc_cart_pass`: cart through the market, nobody clipped |
| S5 | Avoid mud, puddles, fire, dung | hazard points registered by type (puddle and mud decals, campfire, fire incident) | Path cost and a local steer around a radius of 0.8–2 m. Running NPCs splash through (no avoid). Fire uses `FIRE_DANGER_NEAR`. | procedural steer, and on a step over, the `Life_Step_Over` oneshot (**MISSING**, optional) | — | new `HazardField` (fixed array like NpcWorld), utility_brain `hazards()` | NEAR+MID | the steered path keeps out of the hazard; runners do not avoid | `npc_puddle`: walker skirts a puddle on the side street |
| S6 | Walk in pairs side by side | group of 2 (G2) travelling | Leader on the route, partner offset 0.7 m to the side, speed matched to the slower one. Walk-and-talk glances (A4). | gait rate sync, look-at partner, `talk` upper composite (have: Life_Social talker) | RVO (same avoidance layer, partner excluded via mask) | follower_brain `slot_offset` generalised, utility_brain chat pair | NEAR+MID | stays within 0.5 m of its slot through a 90° corner | `npc_pair_walk` |
| S7 | Queue at stalls and wells | smart object busy and `queue` declared | Join the queue slot with gap 0.85 m, face the object, shuffle forward when the front leaves, give up after the patience time (persona). | idle variants `wait` tag, small step-forward oneshot (have: Walk short) | — | `npc_world.queue_spot` generalised to any SmartObject `queue`, smart_objects.json | NEAR+MID | FIFO order, no two in one slot, patience give-up | `npc_well_queue`: 3 at the Ashford well |
| S8 | Follow road edges / lanes | travelling on a StreetGraph edge wider than 3 m | Lateral offset toward the right edge by hash, from 0.3 to 0.45 of the width, so streets do not run single-file down the centre line. Carts own the centre. | procedural | Road Generator lanes where present | StreetGraph edge width | NEAR+MID+FAR (offset is just route data) | the offset distribution is not centred | `npc_street_flow`: top-down 30 s of the market street |

### 3.2 Attention
| # | Rule | Trigger / perception | Behaviour | Motion layer | Built-in | Extend | Tier | Test | Gate |
|---|---|---|---|---|---|---|---|---|---|
| A1 | Head-turn budget | always | At most LOOK_SLOTS active non-forward looks (6 HIGH, 3 LOW). Priority queue with per-NPC per-source cooldown. Looks hold 1.2–3 s, then return. | look-at | LookAtModifier3D `duration`, `transition_type`, angle limits per archetype | villager `_update_head_look`, LifeAmbience glance → `attention.gd` | NEAR | slot cap, priority pre-emption, cooldown | all street shots: count heads turned at most N |
| A2 | Glance at the player when near | player within 3 m (or 6 m if notable: armed, famous, nobly dressed) | A short glance. A friend holds eye contact and nods. A guard follows with the eyes. Eye contact over 1.5 s (A3) triggers a nod or greeting. | look-at, a nod oneshot (have: Social greet; a nod additive is **MISSING**) | LookAtModifier3D | Presence GLANCE, villager `_maybe_greet` | NEAR | glance probability by curiosity, never 2 glances within cooldown | `npc_player_walkby`: player walks the market, 2–4 heads track |
| A3 | Eye contact | the player's camera faces the NPC (dot over 0.9) within 5 m for 1 s | The NPC looks back (eyes, then head). The reply depends on standing: nod, look away (LOOK_AWAY exists) or stare. | look-at + face card brows | — | presence.gd, face_state.gd | NEAR | reply table by standing | `npc_player_walkby` |
| A4 | Look at the speaker | conversation group (G1) | Listeners look at the current speaker. The speaker looks at listeners in turn, with a gaze shift every 2–4 s. | look-at | LookAtModifier3D | villager `_partner_node`, talk_pose | NEAR | gaze target follows the turn token | `npc_conversation` |
| A5 | Look at noises, fights, falling objects | LivingEvents / NpcWorld sound within radius, priority 4 | Turn the head. For a loud or threat event also turn the torso (body yaw of 30°, then the feet if it is still interesting after 1.5 s). | look-at → body turn (LOCO) | — | LivingEvents + `NpcWorld.best_sound` merged under `attention.gd` | NEAR (MID: body turn only) | the right source wins when two fire, reaction delay 0.15–0.4 s staggered | `npc_noise`: anvil clang + a dropped crate in the market |

### 3.3 Reactions
| # | Rule | Trigger | Behaviour | Motion layer | Built-in | Extend | Tier | Test | Gate |
|---|---|---|---|---|---|---|---|---|---|
| R1 | Flinch at loud sounds | sound loudness over 25 m within 8 m (thunder, crash, explosion, war horn) | Upper-body flinch, then look at the source (A5). A child runs to an adult (G2). | oneshot upper `startle` (**MISSING** civilian flinch; combat `Hit_Head_R/L` too violent) | — | `RR.Kind.FLINCH` → new `STARTLE` kind | NEAR+MID | one flinch per event id, delay staggered by distance | `npc_startle`: a thunder clap in the market |
| R2 | Step back from a drawn sword | `NpcWorld.armed_pressure` over 0.2 (exists, ARMED_SPACE 2.8) | Step back facing the blade, hands up when it is pointed at them. A guard instead squares up (B1). | STEP_BACK reaction, `hands_up` upper (**MISSING**), look at the weapon | — | villager armed space, `reaction_adapter` | NEAR+MID | distance kept ≥ ARMED_SPACE within 1 s | `npc_sword_drawn`: player draws in the crowd |
| R3 | Crowd ripple away from a fight | fight incident (NpcWorld FIGHT) | Inner ring (under 4 m) backs off fast, middle ring (4–10 m) backs off and turns to watch, outer ring stops. The wave propagates at 6 m/s from the centre, so the reaction delay grows with distance. | STEP_BACK / FLEE, then `watch` idle (have: Guard_Look_Around_Scan; arms-crossed watch **MISSING**) | RVO priority raised for retreaters | npc_world incident + new ring calc in `motion_rules` | NEAR+MID+FAR (FAR: steer only) | ring assignment, monotonic delay vs distance | `npc_fight_ripple` (with B1) |
| R4 | Curiosity gathering at events | festival, crier, brawl watchable, accident (micro events) | People with curiosity over 0.5 approach to a gather ring (radius by event, slots spaced 0.9 m, open side kept for the player's view), watch, point, comment, then disperse in a staggered way. | watch idles + `point` (have: NPC_Direct_Point_Wave, Life_Social_Point_Directions) + look-at | — | utility_brain WATCH / FESTIVE, SmartObjects dynamic "gather" type | NEAR+MID | ring slots unique, the gap toward the camera kept, dispersal staggered | `npc_gather`: town crier in the square |
| R5 | Flee with a dropped load | FLEE act while carrying | The load drops at the first step (exists, `drop_to_ground`), with a stumble-start oneshot, then a panic run. Arms are free (the carry composite is cleared). Pick the load up later (CarryErrand PICKUP) if it is still there. | `flee_start` oneshot (**MISSING**), panic run (**MISSING**, use Run_Natural meanwhile) | — | carry_errand `drop`, `RR.Kind.FLEE` | NEAR+MID | load dropped exactly once, re-pickup after calm | `npc_flee_drop`: a bandit appears in the market |
| R6 | Weather: hunch in rain, shade eyes in the sun | weather and hour (LifeAmbience) | Rain: hunch upper (have), pace ×1.15, prefer covered edges (S8 bias). Low sun in the facing direction: shade the eyes (have) as a 3 s oneshot, rare. | upper composite / oneshot | — | life_ambience weather | NEAR+MID (rain gait FAR) | weather → layer table | `npc_rain`: rain on the side street |
| R7 | Cold and snow | temperature or snow (biome, season) | A cold idle (have: Life_Mocap_Cold, Cold_Shiver_Campfire), gather at fires (smart object `campfire_warm`), a slower and wider snow gait. | idle variant, snow gait (**MISSING**) | — | life_ambience, smart_objects | NEAR+MID | selection table | (snow biome later, not in the slice) |

### 3.4 Smart objects (schema v2)
Every prop type declares the following. Old keys stay, new keys are optional with defaults, and a validator test checks them.
```json
"well": {
  "slots": [{"stand": "auto", "face": 180, "approach_dir": [0,0,1], "approach_arc": 70,
             "enter": {"front": "Life_Well_Enter", "side": "Life_Well_Enter_Side"}, "exit": "Life_Well_Exit",
             "ik": [{"limb": "hand_r", "target": "crank_handle", "weight": 1.0, "phase": [0.0, 1.0]},
                    {"limb": "hand_l", "target": "bucket_rim", "weight": 0.8, "phase": "loop"}]}],
  "ik_targets": {"crank_handle": [0.35, 0.95, 0.1], "bucket_rim": [-0.2, 0.8, 0.25]},
  "occupancy": {"max": 2, "watchers": 2, "watch_ring": 2.2},
  "queue": [[0,0,2.6],[0.6,0,3.4]],
  "needs": {"water": 1.0}, "clip_tags": {"loop": "verb:draw_water"}
}
```
| # | Rule | Trigger | Behaviour | Motion layer | Built-in | Extend | Tier | Test | Gate |
|---|---|---|---|---|---|---|---|---|---|
| O1 | Pick by need | utility_brain act + needs | `needs` weights × distance × occupancy × hours. This replaces the act→type mapping scattered across villager.gd. | — | — | utility_brain, smart_objects `find` filter | data tier too | need → type table, ties broken deterministically | — |
| O2 | Approach along the declared arc | Session APPROACH / ALIGN | Arrive inside `approach_arc` of `approach_dir`, slow down over the last 1.2 m, turn in place or arc in (L4). No sideways shuffle onto the stand point. | walk stop + turn clips (shared L4) | — | `Session._go` / `update` | NEAR+MID | arrival angle within the arc in 100 seeded approaches | `npc_smithy`, `npc_well_queue` |
| O3 | Side-aware entry/exit transitions | entering from front, side or back | Pick `enter[side]`, falling back to the type's single enter clip. | full clips (most side variants **MISSING**, use fallback) | — | Session ENTER/EXIT | NEAR+MID | side classification | `npc_bench_sit` (sit down from the side) |
| O4 | Hand IK on props | Session LOOP with an `ik` list and NEAR tier and budget | TwoBoneIK3D arm to the target (in the prop's frame) for the phase window, weight blended over 0.15 s. Released on EXIT or when out of budget. | IK | TwoBoneIK3D (budget 4, ContactIK request/release pattern) | **new `prop_ik.gd`** cloned from contact_ik.gd; procedural_rig `set_hand_carry` maths | NEAR only | target maths (prop frame → world), budget cap, release on tier change | `npc_well_ik`: hands on the crank (close-up), `npc_ladder_rung` |
| O5 | Occupancy and watchers | spot full | Up to `watchers` people stand at `watch_ring` and look (A1 priority 2), for example people watching the smith. Otherwise pick another spot. | idle watch + look-at | — | smart_objects `occupancy` | NEAR+MID | watcher slots unique | `npc_smithy` |

### 3.5 Locomotion adaptation
| # | Rule | Trigger | Behaviour | Motion layer | Built-in | Extend | Tier | Test | Gate |
|---|---|---|---|---|---|---|---|---|---|
| L1 | Slope and stairs feet | NEAR, ground slope over 8° or StreetGraph stair edge | Pelvis drop and foot plant on steps. NPCs **reuse ContactIK** extended with a standing-foot mode (two rays per 0.25 s refresh, not per frame). Stairs walk clips are used when available. | IK (pelvis + feet), stairs clips (**MISSING**) | TwoBoneIK3D under the ContactIK budget | contact_ik.gd (add `foot_plant` mode), procedural_rig foot-lock maths | NEAR only (budget 4 shared with O4 / ContactIK = 8 total HIGH, 2 LOW) | budget sharing, mode switch | `npc_stairs`: the inn stairs / Ashford steps |
| L2 | Lean into turns | yaw rate × speed | Model-root roll `-speed·yaw_rate·k` (k 0.02, ≤5°) plus forward pitch with speed (≤3°), through a critically damped spring. It rotates the visual root, not bones, so the skeleton costs nothing. | procedural (root transform) | — | `combat/lean_aim.gd` maths (copy the spring, not the modifier) | NEAR+MID | spring response, limits | `npc_street_flow` (look for leans at corners) |
| L3 | Speed-matched stride | always | Exists: `speed_scale = resolved / clip_speed`, clamped 0.3–1.8. Add the per-NPC persona `walk_speed` and pick the gait clip whose ground speed is nearest, so a clip is never scaled outside 0.75–1.3 (switch walk ↔ brisk ↔ jog instead). | gait clip + rate | — | villager gait, LifeAmbience walk_speed | NEAR+MID+FAR | rate stays in band for 0.6–4 m/s | `npc_street_flow` (feet do not slide) |
| L4 | Start, stop and turn transitions shared with the player | speed 0 ↔ walk, a heading change over 100° under 1 m/s | Walk start, walk stop, turn-in-place 90/180 L/R. These are the same clip names as the player (`Loco_WalkStart_F`, `Loco_WalkStop`, `Mx_Run_Turn_180`), installed on the NPC rig through LifeLibrary. Sit-to-stand already exists. | full oneshot, root travel ignored (in place) | AnimationPlayer blend 0.15–0.2 s | player clips + villager `_play` | NEAR (MID: start/stop only) | the decision table (when to play which) | `npc_start_stop`: villager leaves a stall, stops at the well |
| L5 | Carrying-load gait | CarryErrand CARRY | Heavier load: pace ×0.85, stride shortened (rate up 5%), lean back or forward by load type, and a sack on the shoulder makes the free arm counter-swing. | upper composite (have) + L2 lean bias + rate | — | carry_errand KINDS (add `mass`) | NEAR+MID | pace by mass | `npc_carry`: the sack errand on the slice street |
| L6 | Injured, tired and drunk gaits | health, need `rest` under 0.2, inn exit at night | Gait set swap: injured (have: `UAL_Mx_male_injured.glb` walk, idle and turns, not yet installed for villagers), limp (have: Life_Walk_Limp, Wounded_Limp_Walk), drunk (have: Life_Walk_Drunk, Tavern_Drunk_Stumble) with a weaving steer offset (sinusoidal, 0.4 m), tired (**MISSING**). | gait clip | — | LifeAmbience walk_style becomes a state-driven gait set | NEAR+MID+FAR (needs a VAT bake) | state → gait table, weaving amplitude bounded | `npc_inn_night`: a drunk leaves the tavern |

### 3.6 Groups
| # | Rule | Trigger | Behaviour | Motion layer | Built-in | Extend | Tier | Test | Gate |
|---|---|---|---|---|---|---|---|---|---|
| G1 | Conversation circles | 2–5 in a SOCIAL chat (utility_brain chat assembly) | Circle radius `0.55 + 0.25·n` m (2 people face each other at 1.3 m, CHAT_GAP), an open side toward the path or the player, and positions re-spaced when someone joins or leaves. Turn-taking: a speaker token passes every 3–7 s, the speaker plays talker clips (gesture amplitude from persona), listeners play listener clips and nod. | talker / listener tags (have: Life_Social 5/3, Mocap converse, Mixamo5 talk/argue/agree), look-at A4 | — | `smart_objects.conversation` (group) + new `group_motion.gd` | NEAR+MID | layout (no overlap, open side), token rotation fairness | `npc_conversation`: 3 in the square |
| G2 | Families walking together | household members travelling together (WorldSim household) | Parent leads. A child holds a slot at the parent's side (0.6 m), drifts ahead and runs back (bounded leash 3 m), and an adult reaches for the child at a cart (S4). | kid run clips (have: Life_Kid chase), hand-hold (**MISSING**, optional) | RVO masks | follower_brain slot maths, utility_brain | NEAR+MID | leash bound, reunite at corners | `npc_family` |
| G3 | Guards patrolling in step | ≥2 guards on PATROL | Pairs share a gait phase (same clip time, seek the follower to the leader's time). Side by side at 0.9 m, a synchronised stop and look at the end of each patrol leg. | March_Soldier_Loop (have) / walk with phase lock | AnimationPlayer `seek` (CrowdAnimLOD-safe: seek only) | utility_brain PATROL, villager patrol loop | NEAR+MID+FAR (VAT keeps the same time) | phase error under 0.05 s, never drifts | `npc_guard_patrol` |
| G4 | Children running around adults | children idle near adults (play act, market) | Orbit or chase paths around a moving anchor (adult or play spot), radius 2–5 m, with RVO priority low (children give way). | kid run/skip (have) | RVO | utility_brain PLAY, smart_objects play_area | NEAR+MID | orbit stays in radius, no adult collisions | `npc_kids_market` |

### 3.7 Animation selection
| # | Rule | Trigger | Behaviour | Motion layer | Built-in | Extend | Tier | Test | Gate |
|---|---|---|---|---|---|---|---|---|---|
| C1 | Tagged library | build step | `tools/anim/life/tag_clips.py` reads every sidecar and writes `data/anim/motion_tags.json` with axes **verb** (walk, talk, listen, hammer, draw_water, sit, watch, flinch …), **posture** (stand, sit, kneel, crouch, lie), **prop** (none, bucket, sack, hammer, mug …), **mood** (calm, happy, sad, angry, afraid), **layer** (full, upper), **intensity** 0–1 and **vat** (baked yes/no). Untagged clips are tagged from the category plus a hand table. | — | — | life_library `clips_tagged`, aaa_clips.json | build | every life clip has a verb and posture; no unknown names | — |
| C2 | Variety pick with no repeat | any clip choice | `clip_picker.pick(query, persona, history)` makes a weighted choice, excluding the last 3 per NPC and the last 2 among visible neighbours (crowd de-sync). The seed is `hash([person, day, cycle])`. | — | — | Session `_next_variant`, LifeAmbience fidget | NEAR+MID | no immediate repeats over 1000 picks, distribution within ±10% of weights, deterministic | `npc_street_flow`: no two neighbours on the same clip at the same phase |
| C3 | Personality offsets | per person | Speed ×0.88–1.12 and loop rate ×0.93–1.07 (exist), plus posture (spine pitch offset −3°..+4° as an extra model-root pitch while idle), gesture amplitude (pick high-intensity variants and play talk loops at ×1.0–1.15), and an idle start-time offset so nobody is in sync. | rate, root pitch, intensity filter | — | LifeAmbience traits (extend, do not fork) | NEAR+MID (rate FAR) | trait ranges, stability per id | contact sheet: 10 idle villagers, none in sync |

### 3.8 Combat bystanders and bandit groups (reuse the combat worker's layers)
| # | Rule | Trigger | Behaviour | Motion layer | Built-in / addon | Extend | Tier | Test | Gate |
|---|---|---|---|---|---|---|---|---|---|
| B1 | Bystander ring | fight incident | R3 ripple plus: guards square up (`guard_legs` stance, look-at the fighters) and move in when `guard_alert` ≥ 2. Civilians at 6–12 m watch, wince at heavy hits (an R1 flinch on `hit_confirmed` heavy), and children are pulled away. | combat `guard_legs`, `lean_aim` kick on wince (NEAR guards only), look-at | — | npc_world FIGHT incident, combat signals (`hit_confirmed`) | NEAR+MID | ring spacing, wince only on heavy hits, ≤1 per 2 s | `npc_fight_ripple`: player vs bandit in the market |
| B2 | Bandit squad tactics hooks | bandit group engaged | One engager per `creature_attack_tokens` slot. The others circle at the ring radius on the target's flanks, spaced by angle (no stacking), and rotate in when a token frees. Morale under the threshold makes the squad back off together and flee or surrender (WP-04). | npc_fighter states, `combat_motion` root travel, `combat_reactions` | **LimboAI** BTPlayer per squad (squad brain only: assign flank angles, call regroup or retreat). Individual fighters stay on `npc_fighter`. | creature_attack_tokens, npc_fighter, army/morale | NEAR+MID | flank angles spread ≥60°, token cap, squad retreat when morale is low | `bandit_camp_3v1` on the Kingsreach road |
| B3 | Bumped by a running player | the player runs into a NEAR villager under 0.5 m | A shoulder-shove reaction in the push direction plus an annoyed look and bark. Mounted means a big stagger. | `partial_ragdoll.hit_react` (influence 0.3, 0.4 s) or a stumble oneshot | PhysicalBoneSimulator3D (partial, NEAR only, budget 1) | combat partial_ragdoll, villager `_player_push` | NEAR | direction, cooldown | `npc_player_walkby` (sprint pass) |

---

## 4. Top 10 by visible impact (Ashford benchmark slice)

| Rank | Rule(s) | Why it is visible first |
|---|---|---|
| 1 | S1+S2 RVO + yield | Clipping and "dancing" people are the most obvious AI tell in every street shot |
| 2 | C2+C3 variety + personality | Synced idles and identical gaits read as "AI slop" (owner verdict) |
| 3 | A1+A2+A3 attention budget + glance + eye contact | Heads turning toward the player is the cheapest "alive" signal |
| 4 | L4 start/stop/turn shared with the player | NPCs snapping from idle to walk fail the AAA motion line |
| 5 | G1 conversation circles + turn-taking | The slice square has standing groups; today they are pairs only |
| 6 | O2+O4 approach arc + hand IK on props | Hands floating off the well crank or stall fail the props line |
| 7 | R3+B1 crowd ripple + bystander ring | Benchmark item 4 (fight in town) needs the crowd to react |
| 8 | S3+S8 pass side + shoulder turn + road lanes | Side-street shots, single-file centre-line walking |
| 9 | S7 queues at well and stalls | Market dressing with purpose |
| 10 | L5+L6 load, injured and drunk gaits | Variety in a street full of carriers |

---

## 5. Clips: have vs missing

| Need | Status | Source (in order of preference) |
|---|---|---|
| Walk start / stop / turn 90-180 in place (L4, O2) | **have for the player** (`Loco_WalkStart_F`, `Loco_WalkStop`, `Mx_Run_Turn_180`). Install them on the NPC library. | Already retargeted; also `ProjectAshes_art_staging/downloads/mixamo/packs/action_adventure/{left turn,right turn,run to stop}.fbx` → `tools/anim/mixamo_to_ual.py` |
| Injured walk, idle and turns (L6) | have (`mixamo_combat/UAL_Mx_male_injured.glb`), not installed for villagers | Add to LifeLibrary LIBS or composite |
| Tired walk (L6) | **MISSING** | Mixamo search "tired walk" (verify), or Meshy text-to-motion (swift, 3 credits) |
| Stairs up and down (L1) | **MISSING** | Mixamo search "ascending stairs" / "descending stairs" (verify names) |
| Civilian startle / flinch (R1) | **MISSING** | Mixamo search "startled", "reaction", "terrified" (verify), or a CMU search via `tools/anim/retarget_bvh.py` |
| Hands-up step back (R2) | **MISSING** | Mixamo search "surrender" / "step back" (verify) |
| Panic flee start + scared run (R5) | **MISSING** (Run_Natural as a stand-in) | Mixamo search "scared run" / "running scared" (verify) |
| Arms-crossed / onlooker watch idle (R3, R4, B1) | **MISSING** (Guard_Look_Around_Scan as a stand-in) | Mixamo search "standing arms crossed" / "looking" idles |
| Nod / listener acknowledge additive (A2, G1) | partial (listener clips) | Blender: bake a 0.8 s neck-pitch upper clip from Idle (`tools/blender`), no download needed |
| Shoulder-turn pass upper (S3) | **MISSING** | Blender: generate from Walk with spine_02/03 yaw 35° keyed in and out (an upper layer clip) |
| Snow gait (R7) | **MISSING** (not in the slice) | Mixamo search "walking in snow" (verify), or Meshy |
| Hand-hold child (G2) | **MISSING** (optional) | Mixamo pair clips are scarce, so use a hand IK target on the parent's hand (O4 machinery) |
| Side entries for bench / stool (O3) | **MISSING** | Mixamo "sit" variants in `owner_set*`; fallback to the front enter |
| Everything else in §3 | have | life sidecars, `aaa/UAL_AAA_LivingWorld.glb`, `Locomotion`, `Combat_Reactions` |
Every missing clip goes through the existing pipeline: the owner's Mixamo login in the browser pane (`ashes-mixamo-meshy`), then `mixamo_to_ual.py`, then a `.life.json` sidecar with tags, then a VAT bake entry. Log each one in `docs/plans/DOWNLOADS.md`. Keep Meshy at 200 credits or more.

---

## 6. Work split

### 6a. Cloud packages (headless logic + gdUnit). One routine each. Order is the dispatch order.
| Pkg | Scope (new files only, plus hooks described in the PR) | Rules | Depends | Lane |
|---|---|---|---|---|
| **M1 Core** | `scripts/living_world/motion_rules.gd`, `motion_intent.gd`, `data/living_world/motion_rules.json`, `tests/test_motion_rules.gd` | arbitration, tier degrade, archetype params | — | cloud |
| **M2 Clip tags + picker** | `tools/anim/life/tag_clips.py`, `data/anim/motion_tags.json`, `scripts/living_world/clip_picker.gd`, `tests/test_clip_picker.gd` | C1–C3 | — | cloud |
| **M3 Attention** | `scripts/living_world/attention.gd`, `tests/test_motion_attention.gd` | A1–A5 | M1 | cloud |
| **M4 Steering** | `scripts/living_world/steer_rules.gd`, `hazard_field.gd`, `street_graph` static `corridor_width`/`lane_offset` helpers in a new file, `tests/test_motion_steer.gd` (pure RVO params + a NavigationServer3D headless avoidance test) | S1–S8 | M1 | cloud |
| **M5 Groups** | `scripts/living_world/group_motion.gd`, `tests/test_group_motion.gd` | G1–G4, S6, S7 queue generalisation | M1 | cloud |
| **M6 Reactions** | extend `reaction_request.gd`/`reaction_adapter.gd` (new kinds appended, indices kept), `scripts/living_world/crowd_ripple.gd`, `tests/test_motion_reactions.gd` | R1–R7, B1 rings | M1, M2 | cloud |
| **M7 Smart objects v2** | schema keys + validator in `smart_objects.gd` (defaults only), migrate `smart_objects.json`, `needs` table, `tests/test_smart_objects_v2.gd` | O1–O3, O5 (+ the O4 data, not the IK) | — | cloud |
| **M8 Locomotion logic** | `scripts/living_world/gait_rules.gd` (gait set, start/stop/turn decision, lean spring, stride band), `tests/test_gait_rules.gd` | L2–L6 logic | M1, M2 | cloud |
| **M9 Bandit squad** | `scripts/combat/squad_tactics.gd` + a LimboAI BT resource `data/ai/bandit_squad.tres`, `tests/test_squad_tactics.gd` | B2 | combat worker's npc_fighter (read only) | cloud (coordinate with combat-motion worker) |

**COMMON block (paste at the top of every routine prompt).** Per `ashes-cloud-offload`: environment `env_011PGxABSirdeU5dXGSuDGYc`, model `claude-sonnet-5-5`, tools Bash/Read/Write/Edit/Glob/Grep, `run_once_at` now + 3 min.
> Repo `https://github.com/jonaboy19/ProjectAshes`. `git clone --depth 1 --single-branch -b aaa/finish https://github.com/jonaboy19/ProjectAshes.git && cd ProjectAshes && git checkout -b npc-motion/<PKG>`. Read `docs/plans/NPC_MOTION_RULES.md` (the whole design; your package is the row named below) and the skills `.claude/skills/ashes-best-tool-first`, `ashes-perception-ai`, `ashes-world-interaction`, `ashes-melee-combat`.
>
> Install Godot 4.6.3 headless Linux. Run `godot --headless --path kingdom --import`, then gdUnit: `godot --headless --path kingdom -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a tests/<file> --ignoreHeadlessMode`. Run one Godot at a time. Run the whole suite before and after; there must be no new failures.
>
> **Do not edit hot files:** `scripts/actors/player.gd` (CRLF), `actors/character_animator.gd`, `actors/procedural_rig.gd`, `population/villager.gd`, `army/soldier.gd`, `actors/monster.gd`, `actors/wolf.gd`, `actors/mount_controller.gd`, `world/*`, `core/main.gd`, animation `.glb` files. Where you need a hook there, add a static function in your own file and write the exact few-line call into the PR description for the local NPC worker.
>
> Rules:
> - Pure logic, no nodes where possible.
> - Deterministic: no `randf()`, use `hash([...])`.
> - No allocation in per-tick paths.
> - Respect the perf budgets in §2.
> - Every rule row gets a test.
>
> Add one line to `docs/plans/AAA_PROGRESS.md`. Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Push the branch and open a PR into `aaa/finish` whose description ends with "🤖 Generated with [Claude Code](https://claude.com/claude-code)". Finish with a summary: files, tests, budgets measured, the hook lines for the local worker, and what needs local GPU or visual verification.

**Package blocks (append one after the COMMON block):**
- **M1:** Implement `MotionRules.evaluate(ctx: Dictionary, persona: Dictionary, tier: int) -> Dictionary` (MotionIntent keys from §2), with channel arbitration BODY > LOCO > UPPER > HEAD, priority, `min_hold_s` hysteresis, and the tier degrade table from §2 (MID drops look and IK; FAR keeps steer and base clip only; a clip without `vat` resolves to Walk/Idle). Rules are registered from `data/living_world/motion_rules.json` (archetypes villager/child/elder/guard/bandit/follower/merchant/noble, with the numbers given in §3). Ship stub rule functions for every ID in §3 that return no-op, so later packages fill them. Tests: arbitration truth table, hysteresis, degrade per tier, and a cost test (24 contexts × 1000 evaluations under a loose limit).
- **M2:** Write `tools/anim/life/tag_clips.py` that reads every `kingdom/assets/incoming/animations/**/*.life.json`, `aaa/*.clips.json` and `kingdom/data/anim/aaa_clips.json` and emits `kingdom/data/anim/motion_tags.json` (axes verb/posture/prop/mood/layer/intensity/vat per §3.7 C1). Infer from category and name with a hand table for untagged libraries (Work, Mixamo5, Meshy, Mixamo_Farm). Then write `clip_picker.gd` with `pick(query, persona, history, neighbours)` per C2/C3. Tests: coverage (every life clip has verb and posture), no-repeat over 1000 picks, weight distribution ±10%, determinism, the neighbour de-sync rule.
- **M3:** Write `attention.gd`: a global fixed-size request table, LOOK_SLOTS 6/3 by `Quality.tier`, the priorities from §2, per-NPC per-source cooldown 4–9 s by hash, hold 1.2–3 s. Inputs come from `LivingEvents.nearest`, `NpcWorld.best_sound`, the presence GLANCE/LOOK_AWAY requests, the conversation speaker token and player distance/facing. Output is a look target per person, or null. Also write a static `apply_lookat_params(mod: LookAtModifier3D, archetype)` that sets `duration`, `transition_type` and the angle limits. Tests are the A1–A5 rows.
- **M4:** Write `steer_rules.gd`. It computes the desired velocity from the route velocity, plus the S2 yield (rank × load × age), the S3 pass-right + shoulder-turn trigger (corridor width under 1.6 m and oncoming within 3 m), the S4 mover stop, S5 hazard avoidance, S6 pair offset and S8 lane offset. Also write `hazard_field.gd` (fixed arrays, register/unregister/query) and an `rvo_params(archetype)` table with a helper that creates and configures a NavigationServer3D avoidance agent RID (`agent_create`, `agent_set_avoidance_enabled`, radius, `avoidance_priority`, layers, `time_horizon_agents` 1.5, `max_neighbors` 6), plus obstacle helpers for vehicles. Tests: the S1–S8 rows, including a headless NavigationServer3D test where 2 and 6 agents cross with no overlap under 0.45 m (step physics frames and wait for `velocity_computed`).
- **M5:** Write `group_motion.gd`. G1 circle layout (radius 0.55 + 0.25·n, open side toward a given direction, re-space on join or leave), the speaker token every 3–7 s by hash, and listener/speaker clip queries for clip_picker. G2 family slots and child leash 3 m. G3 guard phase lock (leader time → follower seek target). G4 child orbit paths. S7 generic queue (any SmartObject with `queue`, FIFO, patience give-up), reusing the `npc_world.queue_spot` maths without editing npc_world (add a new static). Tests per row.
- **M6:** Append the kinds STARTLE, GATHER, CROWD_RIPPLE, DROP_LOAD_FLEE, WEATHER_RAIN, WEATHER_SUN, COLD to `reaction_request.gd` without renumbering existing kinds. Fill `reaction_adapter.INFO` with clip_picker queries instead of free-text hints. Write `crowd_ripple.gd`: inner (under 4 m), middle (4–10 m) and outer rings, a 6 m/s propagation delay, gather ring slots spaced 0.9 m with the camera side kept open, and staggered dispersal. Also the B1 bystander ring (wince on heavy `hit_confirmed` at most once per 2 s). Tests per row. Keep `test_perception`, `test_search` and the presence tests green.
- **M7:** Extend the `smart_objects.json` schema with `approach_dir`, `approach_arc`, `enter` as a string or `{front, side, back}`, `ik` + `ik_targets`, `occupancy {max, watchers, watch_ring}`, `needs` and `clip_tags`, all optional with defaults in `smart_objects.gd` so old data behaves the same. Write a validator (`SmartObjects.validate(types) -> Array[String]`). Add `ik_targets` estimates and `needs` to all 33 types, marking the IK numbers `"_ik_unverified": true` for the local worker to tune. Implement O1 need-weighted `find` (a new filter key; the old filter is unchanged), O2 arrival arc in `Session`, O3 side pick, and O5 watcher slots. Tests: validator, defaults round-trip, the O1/O2/O3/O5 rows. Keep `test_smart_object_variants` green.
- **M8:** Write `gait_rules.gd`: the L6 state → gait-set table (with the clip names from §5, falling back to existing clips), the L4 start/stop/turn decision (inputs speed, desired speed, heading delta, tier → clip name or ""), the L2 lean spring (copy the maths idea of `combat/lean_aim.gd` for a model-root roll and pitch; do not use a modifier), the L3 stride band (switch gait when the rate leaves 0.75–1.3), L5 carry mass pace, and the L6 drunk weave offset. Tests per row.
- **M9:** Write `squad_tactics.gd` (pure): flank angle assignment (spread ≥60°), rotate-in when a `creature_attack_tokens` slot frees, regroup or retreat when the squad morale (`army/morale.gd`) is below the threshold, and the surrender hand-off to WP-04. Add a LimboAI behaviour tree `data/ai/bandit_squad.tres` that calls those pure functions from BTActions (LimboAI 1.8.1 is installed as a GDExtension; check it loads headless on Linux first, and if it does not, ship the pure logic plus a plain HSM fallback and say so). Do not edit `npc_fighter.gd`; read it and describe the hooks. Tests: angle spread, token cap, retreat trigger.

### 6b. Local NPC worker (GPU, visual tuning, Movie Maker gates)
| Step | Work | Gate shots (playtest_bot stages, Ashford slice) |
|---|---|---|
| L-1 | Hook M1 into `villager.gd` (it owns the hot file), then `micro_actor.gd`, `follower_body.gd`, `soldier.gd`. Write `MotionApply` per adapter, with `life_actor.gd` as the reference. | before/after `npc_street_flow` |
| L-2 | RVO agents on (M4), tune the per-archetype radius and priority by eye, check the LOW fallback, and run the perf bench on HIGH and LOW iGPU. | `npc_crossing`, `npc_alley_pass`, `npc_cart_pass` |
| L-3 | Attention (M3) wired to LookAtModifier3D, tuning angle limits and duration so there is no owl neck or snapping. | `npc_player_walkby`, `npc_noise`, `npc_conversation` |
| L-4 | Retarget and install the missing clips (§5) and the shared player locomotion transitions, then VAT-bake the new gaits. | `npc_start_stop`, `npc_stairs`, `npc_inn_night` |
| L-5 | `prop_ik.gd` (O4) cloned from contact_ik.gd, tuning `ik_targets` on the well, stall and bench in-engine, and the L1 foot-plant mode in ContactIK. | `npc_well_ik`, `npc_smithy`, `npc_bench_sit` |
| L-6 | Groups and reactions (M5, M6) by eye: circle spacing, ripple timing, gather framing. | `npc_conversation`, `npc_fight_ripple`, `npc_gather`, `npc_flee_drop`, `npc_guard_patrol`, `npc_family`, `npc_kids_market` |
| L-7 | Combat bystanders and the bandit squad with the combat-motion worker. | `npc_fight_ripple`, `bandit_camp_3v1` |
| Every step | Movie Maker on the same route before and after: contact sheet at 0.5 s, 3 worst stills, side-by-side with the `ref_aaa` street refs (05/06/12/17), PASS/FAIL into `docs/qa/AAA_GATE_LOG.md`, perf on HIGH and LOW. Nothing goes to the owner until it passes. | — |

The gate shot stages are new `tools_qa/acceptance/slice_npc_*.gd` stages, each a fixed camera plus scripted stimuli, built like `slice_move.gd` (`SLICEFRAME` cut marker). They can be written in the cloud as part of M1, but are recorded locally only.

**Dispatch order:**
- Wave 1: M1, M2 and M7 run in parallel (no shared files).
- Wave 2: M3, M4, M5 and M8 run in parallel once M1 is merged.
- Wave 3: M6 and M9.
- The local worker starts L-1 as soon as M1 lands, then L-2 to L-7 in the impact order of §4.
