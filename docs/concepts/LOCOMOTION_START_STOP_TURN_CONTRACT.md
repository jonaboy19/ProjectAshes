# Locomotion starts, stops, and turns

Claude implementation handoff, based on gameplay source at `e3563fc4`. This is a design and capture contract; no controller or animation asset is changed. Apply it after the current per-rig speed and retarget corrections are accepted.

## Current source behavior

The player blends horizontal velocity toward its requested target with `12 * delta`, calls `move_and_slide()`, and passes the horizontal `velocity` magnitude to `CharacterAnimator`. That animator smooths speed again with a clamped `10 * delta` blend. It then drives a single Idle/Walk/Run blend space. These two filters can delay the visible start and stop; their actual combined effect must be measured alongside collisions and impulses.

Outside blocking and first person, the model turns toward input direction rather than measured travel direction. Blocking faces the camera heading, while its locomotion input remains a scalar speed. Forward, backward, and lateral travel therefore do not have distinct directional animation inputs in this graph. The source alone does not establish that a particular clip looks wrong in every case.

## Define the signals before tuning

Record requested direction/speed, controller `velocity`, `get_real_velocity()` after movement, body position delta, floor state, facing, filtered animation speed, and selected clip/blend. Godot distinguishes requested velocity from actual travel, especially on slopes. For grounded stride calibration, compare planar and floor-tangent travel; choose the signal matching the measured clip's ground-speed definition. Do not count falling speed as running.

Exclude teleports and ground-correction jumps from locomotion samples. If moving platforms are supported, distinguish standing transport from walking relative to the support; world displacement alone must not make a standing rider run. Use a trace to establish these cases before replacing the current animator input.

## Response contract

| Event | Body response | Visible response |
|---|---|---|
| Idle to travel | Accelerate using an authored response | Enter locomotion once; pose supports the first step before substantial translation |
| Release input | Brake to rest without overshoot | Blend to a stop/idle as actual speed falls; no stationary walk tail |
| Reverse or sharp turn | Decelerate/reorient within the intended handling profile | Pivot or suitable directional gait; avoid rotating a planted torso instantly |
| Block and strafe/backstep | Preserve responsive facing and collision | Use supported directional clips; a forward-only gait is not a universal solution |
| Push into a wall | Physics resolves the body | Do not keep a full-speed run solely because input requests it |
| Dodge or hit recovery | Existing action owns its movement interval | Resume the measured current gait without snapping or replaying a start every tick |

Separate body acceleration, braking, turning, and animation blend settings. Tune one at a time against the same capture. A longer crossfade can hide a pose pop while increasing response delay, so record both. Use enter/exit thresholds and a short state hold where needed for near-zero chatter; avoid delaying a real stop until after the player has visibly stood still.

For delta-aware exponential smoothing, define a response time in seconds and use `alpha = 1 - exp(-delta / tau)`. For bounded acceleration use a change in speed per second; for facing use a bounded angular rate or measured turn curve. These are alternative response models to compare, not instructions to stack all of them. Preserve player responsiveness and the existing combat layer contracts.

## Blender and game-loader capture

Review the accepted rig's first plant, last plant, hip trajectory, and turn pose in Blender. Identify available start/stop/pivot/strafe clips and their contact timing; do not assume the library contains suitable clips because their names sound appropriate. Record rig scale and clip source beside any proposed addition.

Then capture the real Godot loader/controller performing start, short tap, sustained walk, walk/run switch, release, 90-degree turn, reversal, block-forward/back/side travel, wall contact, and dodge recovery. Overlay facing and actual travel arrows, body speed and animator speed, state transitions, and foot contact. Keep a paired normal-camera clip so graphs do not substitute for judging natural motion.

Measure input-to-first movement, input-to-first readable step, time/distance to stop, turn duration, facing/travel disagreement, idle/walk state changes, and planted-foot drift. Compare LOW and HIGH at the same physics rate, then compare the player with one nearby villager and soldier. Adjust targets through play review rather than declaring arbitrary timings to be an AAA standard.

Acceptance requires a readable start/stop, coherent direction during supported gaits, reduced foot slip, stable state transitions, and continued world/body collision through actions. Speed calibration and phase/IK review remain separate dependencies: [speed review](LOCOMOTION_SPEED_REVIEW.md), [phase and foot contact](LOCOMOTION_PHASE_AND_FOOT_CONTACT_DESIGN.md), [impulse response](PLAYER_MECHANICS_RESPONSE_REVIEW.md), and [NPC movement ownership](NPC_CONTACT_LOD_CONTRACT.md).

Official source: [Godot 4.6 CharacterBody3D](https://docs.godotengine.org/en/4.6/classes/class_characterbody3d.html), particularly `get_real_velocity()`, `get_position_delta()`, floor state, and platform velocity. Project sources: `kingdom/scripts/actors/player.gd`, `character_animator.gd`, and `soldier.gd` (under `scripts/army`).
