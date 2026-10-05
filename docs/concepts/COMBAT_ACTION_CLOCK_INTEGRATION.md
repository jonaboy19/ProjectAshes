# Combat action clock: integration design from current source

## Evidence and affected paths

Current Player decrements swing/recovery/combo timers at the beginning of `_physics_process`, consumes input buffers before movement, then updates animator parameters after collision movement. Damage contact is dispatched by a separate SceneTree timer. CombatFeedback's fallback slash is another timer. WeaponTrail advances a third clock in `_process`; its marker window and ribbon lifetime share that clock. ImpactPause freezes selected mixers until a wall-clock deadline and leaves all these timers running.

Consequently a mixer pause before contact can allow a pending hit or fallback slash to fire under a frozen pose; a pause after contact can consume recovery and standing-step travel. This is a source-confirmed clock separation, not a recorded visual diagnosis for a particular scene.

## Complete correction contract

1. Expose whether the actual player mixer is currently paused by ImpactPause. Use ownership of that mixer, not global `tree.active == false`, which also covers terminal and other disabled states. Restore/deadline handling must precede clock advancement consistently.
2. Advance one player action elapsed time by scaled physics delta only while its mixer may progress. Derive remaining commitment, contact threshold, active window, attack-cancel eligibility, combo grace during the action and authored step interval from that clock. Keep camera, world, health, stamina and ordinary physics clocks separate.
3. Replace only the player's timed damage contact with a pending action-owned receipt. Dispatch once on crossing contact time, rechecking swing identity, life, interruption and valid targets. Clear the receipt before damage callbacks to tolerate reentrancy. Never dispatch a previous action after dodge/death/replacement.
4. Move CombatFeedback fallback slash scheduling onto the same action clock, retaining its swing-ID check. First-person viewmodel tween also needs the pause policy reviewed; a source change to sword recovery does not approve that independent tween.
5. WeaponTrail's emission window must use the action clock. Separate emission/contact time from ribbon ageing: freezing emission must not prevent an already emitted ribbon from disappearing. Existing velocity gating and pooled buffers remain; do not duplicate its renderer or allocate ribbons per impact.
6. Marker travel integrates differences of the pause-aware elapsed time and divides displacement by the physical tick duration. Subtracting raw delta from a frozen action time would replay the last segment repeatedly. Cancelled travel has no catch-up debt.
7. Input may be buffered during the short freeze, but an action must not start on a frozen mixer. Decide explicitly whether cancellation interrupts a freeze or waits for release. Preserve mobile input grace and record any gameplay timing change.
8. Overlapping pauses and global finisher time scaling must not double-pause elapsed time or restore another owner's state. The same action policy must cover exhausted playback, where timings are already scaled to actual speed.

## Verification scope when requested

Use the existing production combat capture and telemetry, extending it with action elapsed time, mixer pause ownership, pending contact ID, dispatch count and marker travel. Cases: impact before contact, ordinary connecting hit, incoming hit during attack, two overlapping pauses, buffered chain/dodge during freeze, exhaustion, death/revive, first-person fallback slash, standing finisher, collision and no-hit swings. Record actual pose/contact beats, not just elapsed numbers. Preserve separate phone CPU/frame-time evidence.

## Status

No action-clock patch is applied by this document. The preceding standing footwork and exhaustion source commits remain local candidates pending this integration and visual/runtime review. Keep the current mixer-only pause behavior until the entire set of affected clocks is coordinated; a partial recovery-only fix would leave damage, trails or body motion inconsistent.

## 5 October source implementation checkpoint

The local working branch now implements the player combat subset of this contract. ImpactPause exposes actual mixer ownership until restoration. Swing elapsed/remaining time and combo grace advance with a pause-aware physics delta. Attack/dodge inputs wait or buffer during that local freeze. Pending damage contact dispatches once from the action threshold, with action identity/life checks and receipt removal before callbacks. This replaces the player's independent hit timer.

CombatFeedback uses the same elapsed clock for fallback slash thresholds and first-person viewmodel interpolation, replacing the independent timer/tween. WeaponTrail accepts an optional external emission clock for the player; other callers retain process-time emission. Ribbon ageing uses a separate process clock, including alpha interpolation, so emitted geometry still fades during a held action. Emission stops immediately when local hit pause starts and does not bridge across the held pose on release.

Standing step integration subtracts the actual advanced action delta, not raw physics delta, preventing repeated travel while the action is paused. Ordinary gait footstep cues are suppressed during the mixer freeze. Camera, world physics, ordinary movement, stamina and other actor clocks continue; global finisher/parry time scaling still supplies scaled delta as before.

**Not yet verified:** Godot parsing, in-game frame order, damage/pose contact alignment, overlapping impacts, buffers, death/revive, trail ageing, view switching, collision and phone costs. Existing dodge/landing/locomotion timer ownership is outside this combat-clock subset and must still be reviewed. No runtime pass is claimed. Earlier status above describes the pre-implementation checkpoint and is superseded only for these source changes.
