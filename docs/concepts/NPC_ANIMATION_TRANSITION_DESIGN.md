# Behavior and animation transitions for believable NPCs

**Audience:** Claude's implementation branch `claude/focused-curie-m09hbd`

**Purpose:** add explicit interrupt/cleanup/entry ownership to the existing NPC life-loop plan. Documentation only; no game systems are changed here.

## The naturalness gap

Rising Ashes already has a proposed NPC state priority list and several animation audits. The missing design detail is how an actor leaves one behavior and safely enters the next. An enum can switch from `work` to `combat`; a believable resident still needs to put down a tool, release a seat or service spot, stop walking, turn toward the threat, stand if seated, and then let combat own movement. When the interruption ends, the old schedule intent must be checked against the world before it resumes.

The latest checked Claude working copy remains on `e3563fc4`. It has uncommitted animation review, Blender/asset preview, and performance work in progress. That work already covers clip condition, retarget/skinning and speed calibration. This note stays on behavior handoffs, task cleanup, interruption policy, and the way animation phases represent those changes.

## Research pattern

Plch et al.'s AIIDE 2014 paper, written with Warhorse Studios and Charles University, describes an ambient and combat AI architecture for a planned high-budget open-world RPG. Its useful design ideas are:

- A priority hierarchy chooses which behavior component can own the actor.
- A higher-priority behavior does not simply erase the current action. Switch-out and switch-in phases coordinate the transition.
- A suspended task can retain internal state, then check/recover it when resumed. A halted task runs cleanup.
- Behaviors can share execution only where their outputs do not conflict; the paper gives an upper-body wave alongside walking as an example.
- Designers need debugging tools for state transitions and decision budgets; the paper treats this tooling as part of the AI system.
- Animation/world action needs accurate timing and placement. The paper's pub example calls out sitting alignment and synchronizing a hand with an item, as well as safe interruption by combat or dialogue.

The paper reports a historical design, not a plug-in, current engine recommendation, or guarantee of AAA quality in this game. Reproduce the useful boundaries in Rising Ashes' existing state/animation setup. Do not copy proprietary scripts, behavior graphs, art, or assets.

## A transition contract for Rising Ashes

Keep the existing behavior priorities. Add a small, explicit transition owner to coordinate their resources:

1. **Request:** danger, dialogue, player contact, path failure, or schedule change requests a higher-priority behavior. Keep the current task and goal identifiable while the request is pending.
2. **Switch out:** the current task enters an exit phase. It brakes its route, ends or completes a safe animation beat, stops speech if needed, releases anchor/item/attack reservations, and stops issuing movement. The exit may take more than one frame.
3. **Switch in:** the new behavior initializes the needed route, target, equipment, and animation context. Examples: turn and focus the player, stand from a bench, face the threat, ready a weapon, or move to a reachable safe point.
4. **Run:** one behavior owns lower-body movement. Compatible upper-body gestures may layer only through a verified skeleton filter. Animation state reflects the body movement and task state.
5. **Resume or replace:** when the interrupt ends, verify actor life/state, target, route, schedule phase, and anchor occupancy. Resume saved intent if still valid; otherwise choose a current reachable goal. Never resurrect stale velocity, stale target coordinates, or a released reservation.
6. **Cleanup on every exit:** death/despawn, scene/LOD removal, a second higher-priority interrupt, failed path, or timeout must release all owned resources. The actor may not keep moving or holding an interaction after its behavior stops.

| Interrupt | Coordinated exit | Incoming pose/action | Return rule |
|---|---|---|---|
| Threat while sitting/working | Stop task, release anchor/tool safely, stand and turn | Combat/flee takes route and lower-body ownership | Resume work only after threat resolves and anchor is still available |
| Player starts dialogue during travel | Brake, stop route, turn and settle attention | Dialogue controls interaction pose; no hidden path movement | Revalidate old destination and route after dialogue |
| Player approaches villager | Brake before capsule contact, orient, yield or hold role | Brief reaction/look/step-aside state | Continue old route after the crossing clears |
| Work route becomes blocked | Brake and cancel stale path, wait/look, then ask for a new approach | Recovery state makes the failure visible | Retry on nav/stream change; switch to a reachable alternate if policy allows |
| Death/despawn/LOD demotion | Stop updates and release occupancy/reservations | Current lifecycle handling | Store final position and intended coarse state before removing the body |

## Animation authoring and playback implications

- Create transition clips only where the rig has a suitable pose: sit-to-stand, stand-to-guard, tool put-down, start/stop, turn-to-attend, stumble/recover. An in-place crossfade cannot hide an incompatible change in hips or feet.
- Let animation notifies mark contact moments for actions that visibly touch something. At the notify, verify the world object/anchor is still valid; do not permanently change world state if the action was interrupted before contact.
- Preserve locomotion phase when a task changes but movement remains continuous. Use a controlled stop when movement must cease. Do not restart the same walk loop on every state poll.
- Keep the one movement/body owner rule during overlays. A wave may animate upper bones while walking if the filter is validated; two behavior components must not issue competing transforms or root motion.
- Test interruption on every rig family and current animation LOD used by the game. The same state transition can look fine on one skeleton and pop, clip, or stretch on another.

Use the [interactive handoff review](NPC_TRANSITION_HANDOFF_REVIEW.html) to reason about danger, dialogue, and blocked-route examples. Its durations are schematic, and it is not a runtime measurement.

## Instrumentation and acceptance

In the QA overlay/trace, record actor ID, state owner, pending interrupt, transition phase, entry/exit animation, lower/upper-body ownership, current goal/anchor ID, route status, held object/reservation, and resolved velocity. A reviewer should be able to see why the actor is waiting or turning without reading logs alone.

- Threat during sit, work, travel, dialogue, recovery, and a previous transition completes a readable switch-out and switch-in; no pose snaps or stale movement persists.
- Player dialogue/contact interrupts travel, visibly stops the NPC, and the NPC resumes a still-valid route after the interaction.
- A blocked route releases old movement, triggers a visible recovery, and resumes only after a new reachable path is available.
- Interrupted work releases the correct anchor/tool; a second interrupt and actor removal also run cleanup.
- Run identical captures across each rig family, at least two frame-rate caps, and the near-actor LOD boundaries; record animation state, resolved body velocity, and transition duration.
- Check for deadlocks in transition phases. Every transition has a timeout/failure route that gives control back without teleporting or silently discarding schedule intent.

## References

- Plch, Marko, Ondracek, Cerny, Gemrot, and Brom. [“An AI System for Large Open Virtual World,” AIIDE 2014](https://ojs.aaai.org/index.php/AIIDE/article/view/12705). The paper describes priority subbrains, coordinated switch transitions, suspend/resume, modular behavior trees, and profiling. It is a design source, not reusable game content.
- Godot 4.6 [AnimationTree documentation](https://docs.godotengine.org/en/4.6/tutorials/animation/animation_tree.html) for blend/state-machine transitions and AnimationNodeTimeScale.
- Current project references: [NPC life-loop design](NPC_LIFE_LOOP_DESIGN.md), [animation QA report from Claude's working checkout](CURRENT_RUN_VISUAL_REVIEW.md#relationship-to-ongoing-work), and [natural world feel plan](NATURAL_WORLD_FEEL_PLAN.md).
