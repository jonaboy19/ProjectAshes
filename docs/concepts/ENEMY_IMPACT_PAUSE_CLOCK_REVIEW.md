# Enemy attack clock under local impact pause

5 October 2026. Source-derived risk; not a reproduced runtime failure.

Player's local ImpactPause receives struck actors' AnimationMixers. It sets AnimationPlayer speed to zero and later restores the saved rate. Monster and Wolf physics independently decrement `_winding` and `_busy`. Their two-phase strike sets `_anim.speed_scale = 1.0` at the snap threshold. Hyper-armour/poise can preserve `_winding` after a damaging hit, so an enemy attack can continue logically while its clip pauses; crossing the snap threshold can also overwrite the zero rate before pause restoration. Restoring a saved anticipation rate after a logical snap is another ordering risk.

The player's pause-aware action clock patch does not cover this enemy path. Interrupted attacks and poise-preserved attacks must be reviewed separately.

## Integration requirements

- Give local pause ownership a shared query/release contract accessible to each affected actor; a player-owned helper alone cannot safely arbitrate multiple independent pausers.
- Pause windup/contact/recovery together with the attack mixer, or explicitly define a different design that still preserves visible contact. Avoid a broad actor-physics freeze: knockback, collision and unrelated world motion need their existing owners.
- Speed changes during pause must update the intended resume rate without unfreezing playback early. Restoration must not reinstate a superseded clip's rate or reactivate a terminal/ragdoll owner.
- Reuse the existing attack tokens and impact range/visibility checks. Do not compensate by extending weapon reach, altering poise thresholds or moving damage earlier.
- Check weak poise hits immediately before snap/contact, repeated pauses, victim reaction replacement, death/yield, player teardown and multiple attackers. Record actual blade/contact frames and unchanged intended design windup.

No enemy or ImpactPause runtime code changed in this review. This crosses player and enemy animation ownership and requires a coordinated patch rather than only stopping one countdown.
