# P2b: wolf turn clips, run turns and pack clips (Codex patch notes for `wolf.gd`)

**Status 2026-10-06: APPLIED by the local session (animation behaviour owner) and checked in the real game; sheets in `docs/anim/local_wiring/`, notes in `docs/STATUS_LOCAL.md`.**

Companion to `P2_quadruped_no_crab_walk.diff` (which bends the velocity toward the heading). This patch adds the clips that
make the feet match that motion. Assets are done: `wolf.glb` and `wolf_lod1.glb` (same clip names, same 51-bone skeleton,
30 fps, wolf scale 1.3 baked in, so `creature_models.gd` keeps `"scale": 1.0`). Numbers are in `docs/anim/creatures/wolf/TABLE.txt`,
sheets in `docs/anim/creatures/wolf/`. All clips are authored with planted feet measured in world space
(slip 0.001-0.009 m/s rms; details in TABLE.txt). New roles need no `clips` override: `wolf.gd::_play` already falls back to
the role name (`_clips.get(role, role)`).

Conventions: heading + = left turn = `+rotation.y` in Godot for a +Z-facing model. Times in seconds at playback rate 1.0.
"Root motion" below means the game moves/rotates the CharacterBody; the clip itself is in place (no root bone travel).

## Clips

| Clip | Length | Loop | Used by | Root motion (game side) | Blend in / out | Events |
|---|---|---|---|---|---|---|
| `turn_l90`, `turn_r90` | 0.967 s | no | ROAM / STALK / ATTACK when idle-ish and yaw error 60-135 deg | yaw only, table `TURN_90` (0 -> 90 deg over the clip); no translation | 0.12 / 0.15 (0.20 into walk/run) | none |
| `turn_l180`, `turn_r180` | 1.40 s | no | same, yaw error > 135 deg | yaw only, table `TURN_180` (0 -> 180 deg) | 0.12 / 0.15 | none |
| `run_turn_l`, `run_turn_r` | 0.567 s | yes (same length and phase as `run`) | any state running while the heading changes faster than 0.9 rad/s | none extra: keep P2 (`fwd.slerp(dir, 0.35)`); authored for 1.5 rad/s at 4.95 m/s | 0.15 / 0.15 (run <-> run_turn) | none |
| `stalk` | 1.20 s | yes | `State.STALK` (`stalk_speed` 1.0 -> rate 1.11) | forward 0.90 m/s (authored) | 0.25 / 0.25 | none |
| `circle_l`, `circle_r` | 0.60 s | yes | `State.ATTACK` while `_circling` and tangential speed <= 2.2 m/s | sideways 1.40 m/s and heading -/+0.28 rad/s (5 m orbit): the orbit code already does this | 0.15 / 0.15 | none |
| `lunge` | 1.267 s | no | `State.ATTACK` slot holder at 2.0-3.0 m (bite leap) | forward table `LUNGE_TRAVEL` (1.12 m total, 0.38-0.70 s) | 0.10 / 0.20 | `impact` 0.57, liftoff 0.40/0.44, land 0.62/0.70 |
| `howl` | 2.90 s | hold range 0.70-2.20 | first aggro of a pack, pack call | none | 0.20 / 0.25 | audio 0.55 |
| `flinch` | 0.40 s | no | `take_damage` light hit (amount < 25 % of max health, not heavy) instead of `hit` | none | 0.04 / 0.12 | peak 0.07 |
| `limp` | 1.00 s | yes | `State.FLEE` / `State.RETREAT` when health < `flee_below * 1.5`, speed <= 2.2 m/s (rate = speed / 1.1) | forward 1.10 m/s | 0.25 / 0.25 | none |
| `walk`, `run` | 1.067 / 0.567 s | yes | unchanged names; feet are now locked (walk slip 0.005 m/s, was 1.27; run 0.13, was 0.94) | walk 1.07 m/s, run 4.95 m/s (**run was 2.6 in the table: fix it**) | as now (0.28) | none |

Loops have identical first and last poses (checked, difference 0.00000). Old clips `idle attack hit death` are untouched
(`attack` impact stays 0.27, use 0.30 to land on full reach); `walk_orig` and `run_orig` are the pre-lock versions, unused.

## Rules

1. **Turn in place** when `_speed < 1.5` and `|yaw error| > 60 deg` (error = `angle_difference(rotation.y, atan2(dir.x, dir.z))`),
   not while `_winding > 0` or `_busy > 0`, and not within 0.4 s of the last turn. Pick `turn_l90/r90` for 60-135 deg, `turn_l180/r180` above.
   The clip is authored for an exact 90 / 180 deg: apply exactly that yaw along the table (leftover error, at most 45 deg, is
   handled by the normal `lerp_angle` afterwards) so the planted feet stay planted. Do not scale the rate by the error.
2. **Run turn**: while `locomotion == "run"` and `|yaw rate| > 0.9 rad/s` play `run_turn_l` (left) or `run_turn_r`; go back to `run`
   below 0.6 rad/s (hysteresis). Same playback rate as `run`. Keep the P2 `turn_pace` slow-down.
3. **Stalk / limp / circle** are loop locomotion roles chosen next to walk/run (below).
4. **Lunge** is an attack variant: when the slot holder is 2.0-3.0 m from the target, off cooldown, `randf() < 0.5`. Plays at rate 1.0
   (the travel table is tied to the clip). The bite is `_impact()` at 0.57 s; the body has travelled 0.75 m by then, so `reach` 2.3 is enough
   for a start distance of up to 3.0 m. Below 1.9 m use the normal `attack`.
5. **Howl** once when a pack member first enters ATTACK (per-wolf cooldown 20 s), optional extra loops of the hold range 0.70-2.20 s for a pack call.
6. **Flinch** for light hits, `hit` stays for bigger ones (as now) and knockdowns stay with the ragdoll.

## Tables (heading degrees / metres, sampled from the exported clips; linear interpolation between samples)

```
TURN_90  (every 0.1 s, t = 0 .. 0.9, then 90.0 at 0.967 s):
  0.0 2.3 12.0 23.3 35.2 46.8 58.5 70.4 81.3 89.3 | 90.0
TURN_180 (every 0.1 s, t = 0 .. 1.3, then 180.0 at 1.40 s):
  0.0 1.5 11.3 25.6 41.2 57.5 73.9 89.9 105.8 122.3 138.6 154.1 168.5 178.4 | 180.0
LUNGE_TRAVEL (metres forward, every 2 frames = 0.0667 s from t = 0):
  0.00 0.00 0.00 0.00 0.00 0.00 0.00 0.14 0.54 0.93 1.05 1.08 1.11 1.12 1.12 ... (1.12 to the end at 1.267 s)
```
(The full per-frame root motion of every clip, including the mirrored right turns, is in `docs/anim/creatures/wolf/root_motion_tables.txt`
and `tools/creatures/wolf` writes it to `wolf_rootmotion.json` next to the GLB when rebuilt.)

## GDScript sketch for `wolf.gd` (diff style, adapt names)

```gdscript
@@ constants
+const TURN_90 := PackedFloat32Array([0.0, 2.3, 12.0, 23.3, 35.2, 46.8, 58.5, 70.4, 81.3, 89.3, 90.0])   # deg, 0.1 s steps, last sample at 0.967 s
+const TURN_180 := PackedFloat32Array([0.0, 1.5, 11.3, 25.6, 41.2, 57.5, 73.9, 89.9, 105.8, 122.3, 138.6, 154.1, 168.5, 178.4, 180.0])
+const TURN_DUR := {90: 0.9667, 180: 1.4}
+const LUNGE_TRAVEL := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.14, 0.54, 0.93, 1.05, 1.08, 1.11, 1.12])  # m, every 2/30 s, then 1.12
+const LUNGE_TIME := 1.267
+const LUNGE_IMPACT := 0.57
+const STALK_SPEED := 0.90      # authored ground speeds (m/s)
+const LIMP_SPEED := 1.10
+const CIRCLE_SPEED := 1.40
+const RUN_TURN_ON := 0.9       # rad/s
+const RUN_TURN_OFF := 0.6

@@ vars
+var _turn_deg := 0                 # 0 = not turning, else 90 or 180
+var _turn_sign := 1.0
+var _turn_t := 0.0
+var _turn_cool := 0.0
+var _lunge_t := -1.0               # >= 0 while a lunge plays
+var _yaw_prev := 0.0
+var _run_turning := false
+var _howl_cool := 0.0

+## Interpolates a table sampled every `step` seconds; the last entry is the value at `end`.
+func _table(tab: PackedFloat32Array, t: float, step: float, end: float) -> float:
+	if t >= end: return tab[tab.size() - 1]
+	var last := tab.size() - 1
+	var i := int(t / step)
+	if i >= last - 1:
+		return lerpf(tab[last - 1], tab[last], clampf((t - float(last - 1) * step) / (end - float(last - 1) * step), 0.0, 1.0))
+	return lerpf(tab[i], tab[i + 1], (t - float(i) * step) / step)

@@ _physics_process, before the movement block (after `_speed = lerpf(...)`)
+	_turn_cool -= delta
+	var dir_want := _target - global_position
+	dir_want.y = 0.0
+	var yaw_err := 0.0
+	if dir_want.length() > 0.3:
+		yaw_err = angle_difference(rotation.y, atan2(dir_want.x, dir_want.z))
+	if _turn_deg == 0 and _busy <= 0.0 and _winding <= 0.0 and _turn_cool <= 0.0 and _speed < 1.5 \
+			and absf(yaw_err) > deg_to_rad(60.0) and _lunge_t < 0.0 and not (face_player and state == State.ATTACK):
+		_turn_deg = 180 if absf(yaw_err) > deg_to_rad(135.0) else 90
+		_turn_sign = signf(yaw_err)
+		_turn_t = 0.0
+		_speed = 0.0
+		_play(("turn_l%d" if _turn_sign > 0.0 else "turn_r%d") % _turn_deg, true)     # blend 0.12 via _play
+	if _turn_deg != 0:
+		var tab := TURN_180 if _turn_deg == 180 else TURN_90
+		var dur: float = TURN_DUR[_turn_deg]
+		var before := _table(tab, _turn_t, 0.1, dur)
+		_turn_t += delta
+		rotation.y += _turn_sign * deg_to_rad(_table(tab, _turn_t, 0.1, dur) - before)
+		if _turn_t >= dur:
+			_turn_deg = 0
+			_turn_cool = 0.4
+		return                       # feet are planted by the clip: no translation while turning

@@ lunge (call from _attack_move instead of _begin_attack when the distance fits)
+	if d >= 2.0 and d <= 3.0 and _attack_cd <= 0.0 and randf() < 0.5:
+		_begin_lunge(player)
+func _begin_lunge(target: Node3D) -> void:
+	_attack_cd = randf_range(float(_sp["cooldown"][0]), float(_sp["cooldown"][1])) + 0.6
+	_winding = LUNGE_IMPACT                    # _impact() fires at 0.57 s exactly like the bite windup
+	_busy = LUNGE_TIME
+	_strike_target = target
+	_lunge_t = 0.0
+	_speed = 0.0
+	_play("lunge", true, 1.0)                  # rate 1.0: the travel table is tied to the clip
@@ _physics_process (root motion of the lunge)
+	if _lunge_t >= 0.0:
+		var a := _table(LUNGE_TRAVEL, _lunge_t, 2.0 / 30.0, LUNGE_TIME)
+		_lunge_t += delta
+		var b := _table(LUNGE_TRAVEL, _lunge_t, 2.0 / 30.0, LUNGE_TIME)
+		var fwd := Vector3(sin(rotation.y), 0.0, cos(rotation.y))
+		move_and_collide(fwd * (b - a))       # stops on the player capsule; keep global_position.y = WorldGen.height(...)
+		if _lunge_t >= LUNGE_TIME: _lunge_t = -1.0

@@ locomotion role selection (replaces the block at the end of _physics_process)
 	if _busy <= 0.0 and _winding <= 0.0:
-		var running := ...
-		var locomotion := "run" if running else ("walk" if _speed > 0.2 else "idle")
+		var yaw_rate := angle_difference(_yaw_prev, rotation.y) / maxf(delta, 0.001)
+		_yaw_prev = rotation.y
+		var running := _speed > _walk_clip_speed * 1.8 and _run_clip_speed > _walk_clip_speed * 1.2
+		_run_turning = absf(yaw_rate) > (RUN_TURN_OFF if _run_turning else RUN_TURN_ON)
+		var locomotion := "idle"
+		var authored := _walk_clip_speed
+		if running:
+			locomotion = ("run_turn_l" if yaw_rate > 0.0 else "run_turn_r") if _run_turning else "run"
+			authored = _run_clip_speed
+		elif _speed > 0.2:
+			locomotion = "walk"
+			if state == State.STALK: locomotion = "stalk"; authored = STALK_SPEED
+			elif (state == State.FLEE or state == State.RETREAT) and _speed <= 2.2 and health < int(_sp["flee_below"]) * 1.5:
+				locomotion = "limp"; authored = LIMP_SPEED
+			elif state == State.ATTACK and _circling and _speed <= 2.2:
+				locomotion = "circle_l" if _orbit_dir > 0.0 else "circle_r"; authored = CIRCLE_SPEED
+		var rate := 1.0 if locomotion == "idle" else clampf(_speed / authored, 0.6, 1.9)
 		_play(locomotion, false, rate)

@@ _play(): blend times (seconds)
-		var blend := 0.28 if _anim.current_animation in loco and anim_name in loco else 0.15
+		var blend := 0.28 if _anim.current_animation in loco and anim_name in loco else 0.15
+		match anim_name:
+			"flinch": blend = 0.04
+			"lunge": blend = 0.10
+			"howl", "stalk", "limp": blend = 0.20
+			"run_turn_l", "run_turn_r", "circle_l", "circle_r": blend = 0.15

@@ take_damage(): light hit -> flinch (heavy stays as is)
-	_busy = 0.3
-	_play("hit", true)
+	_busy = 0.3
+	_play("flinch" if amount < max_health / 4 else "hit", true)

@@ howl: first time a wolf enters ATTACK
+	if state == State.ATTACK and _howl_cool <= 0.0 and randf() < 0.35 and _busy <= 0.0:
+		_howl_cool = 20.0
+		_busy = 2.9
+		_play("howl", true)
+		get_tree().create_timer(0.55).timeout.connect(func(): Audio.play_sfx("wolf_howl", global_position + Vector3.UP * 1.0, -2.0, 0.05))
```

Notes for Codex
- The turn tables assume the game pivots the body around the model origin (the clips were solved for exactly that: no translation during a turn).
- `run_turn_*` and `circle_*` are meant to be entered from `run` / `walk` / `stalk` with the blend times above; poses differ by lean and spine bend only.
- If you scale a loop's playback rate the planted feet stay planted only if the ground speed scales with it (`rate = speed / authored`), which is what the role block does.
- Hit reactions during a turn or a lunge: cancel `_turn_deg` / `_lunge_t` in `take_damage` (set both back to 0 / -1) before playing `flinch` or `hit`.
