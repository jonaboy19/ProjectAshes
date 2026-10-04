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
