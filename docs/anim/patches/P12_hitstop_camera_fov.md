# P12 — Hit-stop tiers, FOV punch on heavy hits, sparks at the blade

Owner: Codex (`player.gd _resolve_hit/_hit_stop/_parry`, `camera_shake.gd` shared helper).
Evidence: `COMBAT_AUDIT.md` issue C8. Telemetry: hit-stop frames per swing (`combat_capture` c02/c10).

## Now

- Every connecting hit sets the global `Engine.time_scale = 0.05`: 0.05 s for light hits, 0.09 s for the finisher, 0.12 s for a parry.
- The shake is added in the same frame. `CameraShake.step()` uses scaled delta, so the shake plays after the stop (this part is fine).
- There is no FOV change anywhere, so the finisher and the parry have the same camera language as a light hit.
- Sparks spawn at `enemy + 0.8 m - 0.3 m toward the player`, not where the blade is.

## Change

1. **Tiers** (seconds): light 0.045, L3 0.06, L4 finisher 0.10, heavy release 0.12, parry 0.14, kill 0.14.
   - Light hits freeze only the attacker's and victim's mixers (`tools_qa/anim_tech/lib/hitstop.gd freeze_local`). The world, NPCs, VFX and camera keep moving.
   - Keep the global stop only for the finisher, parry and kills.
2. **FOV punch** (heavy, finisher, parry, kill). In `camera_shake.gd`:

```diff
+var fov_kick := 0.0             # degrees
+func punch(deg: float) -> void:
+	fov_kick = minf(fov_kick + deg, 8.0)
+## FOV offset (deg) for this frame: instant in, ~0.25 s exponential out.
+func fov_step(delta: float) -> float:
+	fov_kick = move_toward(fov_kick, 0.0, maxf(fov_kick, 1.0) * 6.0 * delta)
+	return -fov_kick                 # narrower = punch-in
```

   In `player._update_camera`, after `camera.rotation = _shake.step(delta)`:
   ```gdscript
   camera.fov = _base_fov + _shake.fov_step(delta)
   ```
   `_base_fov` is read once in `_ready()`. Punch on the contact frame: finisher `punch(3.0)`, parry `punch(4.0)`, heavy release `punch(5.0)`.
   The "reduce screen shake" option also zeroes the punch.
3. **Sparks at the blade.** In `_resolve_hit`, spawn `VFX.sparks` / `ElementFX.hit_sparks` at `_trail.tip_position()` (`WeaponTrail`) when the tip is within 0.6 m of the enemy. Otherwise use the current point. The spark direction is the tip velocity.
4. **Order on the contact frame** (one place, `_resolve_hit`):
   - damage
   - victim reaction frame 0 (P10)
   - sparks at the blade
   - hit-stop
   - on release: shake + FOV punch + the victim whip
