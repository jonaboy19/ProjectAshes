# P11 — Enemy attacks: hold-then-snap wind-up instead of a uniformly slowed clip

Owner: Codex (`monster.gd _strike/_impact`, `wolf.gd`, same pattern).
Evidence: `COMBAT_AUDIT.md` issue C7. Sheets:
- `docs/anim/combat/game_before/c07_orc_attacks_sheet_001.jpg`
- `c08_troll_attacks_sheet_001.jpg`
- `c06_goblin_attacks_sheet_001.jpg`

## Problem

`_strike()` plays the whole attack clip at `rate = _impact_time / windup`, so the clip's contact lands at `windup`.
- Orc: impact 1.11 s, wind-up 0.85 s, so the clip plays at 1.31x.
- Troll: 1.57 s over 1.1 s, so 1.43x.
- Goblin: 0.55 s over 0.5 s, so 1.1x.

One global rate scales the anticipation AND the strike together.
- In c07 the orc's arm-raise reads (#1–#10), but the slam is a single frame (#10 → #11).
- It then sits at the ground for 0.7 s (#11–#21) until `_busy` ends.
- The wind-up length is a fairness value set in design. It should not change the strike speed.

## Change (two-phase playback)

```diff
@@ func _strike(foe: Node3D) -> void:
-	_play("attack", true, clampf(_impact_time / windup, 0.3, 1.6))
+	# Anticipation stretched to the design wind-up, strike at the clip's own speed:
+	# the first (impact - STRIKE) s of the clip fill (windup - STRIKE) s, the last STRIKE s play at 1x.
+	var pre := maxf(_impact_time - STRIKE, 0.05)
+	var hold := maxf(windup - STRIKE, 0.05)
+	_play("attack", true, clampf(pre / hold, 0.25, 2.0))
+	_snap_at = windup - hold                  # new var: _winding value at which the strike runs at 1x
@@ where _winding counts down (_physics_process)
 	if _winding > 0.0:
 		_winding -= delta
+		if _winding <= windup_left_for_snap() and _anim and _anim.speed_scale != 1.0:
+			_anim.speed_scale = 1.0           # the snap: the strike at authored speed
+			VFX.flash(get_parent(), _weapon_point(), Color(1.0, 0.55, 0.2), 1.5, 0.08, 3.0)   # 2-frame telegraph
```

Use `const STRIKE := 0.2` and the helper `windup_left_for_snap() = STRIKE`. `_weapon_point()` is the hand bone's global position, or `global_position + UP * height * 0.8`.

The contact still lands exactly at `windup`, so gameplay timing and fairness are unchanged. The last 0.2 s before contact always has the clip's real snap, and the recovery plays at 1x instead of being stretched.
- The flash is the pre-strike cue for phones. The name-tag "!" is not read at 10 m.

## Enemy hit reactions

The Meshy creatures have one `hit` clip each.
- On the hit-stop frame, set `_anim.speed_scale = 0` for the attacker's hit-stop duration (0.045–0.10 s), then 1.
- The flinch then starts on the release, and the existing `_knock` slide runs in the push direction.
- This replaces the global `Engine.time_scale` freeze for light hits (FEEL_AUDIT F16, P12).
