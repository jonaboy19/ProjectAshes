# Standing combat footwork: reuse checkpoint

## Current evidence

The inspected player starts every sword swing with `CharacterAnimator.play_upper(action.anim, rate)`, while collision-body movement applies the attack lunge separately. The standing legs therefore do not receive the authored attack step. Claude's `docs/anim/COMBAT_AUDIT.md` C3 identifies this same issue, and `docs/anim/patches/P9_attack_layering.md` supplies a previously tried, reverted integration recipe.

The P9 recipe is an existing project contribution to adapt, not a new controller to write. Its old diff targets dictionary-based combo data; the current player uses `CombatAction` resources and the exhausted-action clock correction. Preserve that architecture and the later jump/pivot graph when integrating.

## Reusable components

- Existing `Sword_Light_1..4` full-body clips and `_Upper` variants in `UAL_Combat.glb`.
- `combat_markers.json` authored step distances and frame windows.
- Existing CombatMarkers access, blade trail and combat capture/studio tools.
- P9 alternating upper/full attack slots for chaining without restarting from the base pose.

## Required integration constraints

1. Choose full or upper body on swing entry from physical movement speed, preserving moving attacks.
2. Preserve the current linear AnimationTree chain: outputs cannot feed two downstream inputs in the tried architecture.
3. Keep one movement authority: sample authored travel into collision-tested body movement; never enable a second visual root translation.
4. Respect action.root_motion, target standoff, interruption IDs and exhaustion playback speed when scheduling step markers.
5. Stop every attack slot on cancellation and death, and prevent old step callbacks from moving a new action.
6. Include the standing attack in the rig's full-body busy state so procedural foot correction does not fight the authored step.
7. Avoid adding full trees to distant NPCs. Start with the playable character; expand only within existing actor budgets.

## Evidence still required

The historical P9 trial is evidence of that older implementation, not a pass for the current branch. Review the current graph before applying it. Runtime/visual review should cover stationary and moving combos, exhaustion, cancellation, close targets and walls, and clips on the current outfit. The existing capture acceptance includes no first-frame blade spike above 30 m/s, contact at the intended blade beat, and lead foot planting where the body stops.

No new animation assets are required. No P9 gameplay change has been applied in this checkpoint.

## Implementation checkpoint

The working branch now adapts the existing P9 graph recipe: four serial alternating attack slots are created only on the playable `with_air` rig. Full-body dodge/hit layers retain priority. The player chooses the full-body variant when standing on the ground (excluding crouch and first-person), otherwise preserves upper-body motion. Normal reaction, dodge and cancellation entry points fade attack slots; full-body attack state also disables competing procedural foot correction through the existing busy-state contract.

Authored standing step distance is read from the existing markers, scaled with the player body and capped by target standoff. Its start is checked on the actor's physics action clock at the marker's frame divided by actual playback rate, including exhaustion. The pending step is guarded by swing identity, live action, grounding and body state. It travels through the existing collision-tested impulse path. No new asynchronous step timer is introduced.

This is a source implementation checkpoint, not runtime approval. The current constant impulse deceleration preserves the historical P9 limitation: body arrival may lag the foot plant. Marker-window travel alignment, visual review and collision cases remain pending. Do not claim planted-foot quality yet. The prior statement that P9 was not applied describes the earlier checkpoint only.

### Cancellation review

Attack cancellation writes fade requests even for slots not yet marked active, replacing a pending FIRE before the next graph evaluation. Terminal playback also clears attack requests, preventing retained attack state when the tree is reactivated after revival. The existing upper-busy query now includes attack slots, and full-busy includes standing attacks for rig ownership.

Claude's P15 integration-fix handoff and 1 October review were also read. The current lane probe already uses KinematicCollision3D; those old fixes should not be recreated. P15 explicitly leaves P9 attack layering deferred. Its historical pivot failure is superseded by this branch's later specific LOW captures, not by a blanket visual approval. P12 already specifies local mixer pauses for ordinary hits, explaining the current pause architecture; the recovery-clock synchronization issue remains a separate integration concern.

### Marker/duration inconsistency discovered after integration

The current JSON provides full-body step windows and distances:

| Clip | Distance at base size | Step frames at 30 fps | Step end at 1.2x |
| --- | --- | --- | --- |
| Sword_Light_1 | 0.22 m | 7–14 | 0.389 s |
| Sword_Light_2 | 0.24 m | 6–13 | 0.361 s |
| Sword_Light_3 | 0.26 m | 7–14 | 0.389 s |
| Sword_Light_4 | 0.40 m | 14–29 | 0.806 s |

The finisher action currently locks for 0.64 s, shorter than its authored step window. Exhaustion scales both but does not remove that inconsistency. The current step-start adapter intentionally does not extend the action lock or claim end-of-step alignment. This is an integration blocker for planted-foot approval, not evidence that the full-body patch is finished.

Next, review the existing full clip's recovery/contacts and the action's intended cancel policy together. Choose whether to retime the existing clip/markers or extend its commitment, recording any balance change. Then drive body travel through the complete marker interval with collision and interruption checks. Avoid fixing arrival by allowing an old action's motion to continue after a new action takes ownership.

### Marker-window travel implementation

Standing authored travel now uses the entire existing step interval instead of a delayed constant-deceleration kick. Each physics tick integrates a smoothstep distance curve over that tick's action-time interval and supplies its average velocity to the existing `move_and_slide` path. Intended distance is bounded by the marker distance and initial target standoff. Collision consumes elapsed time rather than storing blocked travel for a later catch-up. This is a generic bounded interpolation between authored markers, not extracted root trajectory or proof of exact foot locking.

Swing replacement, dodge, stun, jump, lost grounding, swimming, mount and death invalidate the remaining step. A replacement `_kick()` also clears authored travel, preserving knockback/guard movement priority. This supersedes the earlier constant-deceleration step-start adapter and its arrival-lag limitation in source; visual alignment still needs review.

**Recorded gameplay change:** only a standing authored finisher with a valid step interval extends its attack commitment to at least the step end. Sword_Light_4 therefore changes from 0.64 to about 0.806 s at 1.2x normal playback (about 1.152 s exhausted). Damage, contact time, stamina cost and moving attack commitment are unchanged. Finisher attack-cancel tail remains zero. This prevents normal attack chaining before the standing plant, but full end-pose recovery and dodge interruption still need review. It is not a runtime or balance acceptance claim.
