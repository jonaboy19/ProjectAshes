# P9 — Attack layering: full-body at a standstill, upper-body while moving, and no pop between combo hits

Owner: Codex (`kingdom/scripts/actors/character_animator.gd`, `player.gd`, `army/soldier.gd`).
Evidence: `docs/anim/COMBAT_AUDIT.md` issues C1, C3, C6.

## Why

1. **Every attack plays on the upper-body OneShot only.** The legs and the pelvis keep playing idle or locomotion.
   - The pelvis turn that drives every UAL sword swing is thrown away. The blade then swings to the side or behind the character instead of through the target.
     - Sword_Regular_C@2.2 never passes through a target 1.3 m in front.
     - Sword_Attack@1.4 never passes through it either.
     - Sword_Regular_B@1.7 only touches it on frame 0.
     - Sword_Regular_A@1.7 touches it on frames 7–8, 3 frames after the hit fires.
   - The 0.375 m capsule lunge slides planted idle feet. See `docs/anim/combat/game_before/c02_combo_on_orc_sheet_001.jpg` #1–#8.
2. **Re-firing the same `AnimationNodeOneShot` while it is active restarts it**, and its fade-in blends from the *base* input (block/locomotion), not from the pose on screen.
   - Each combo hand-over therefore snaps from the old swing to the base pose in one frame.
   - Telemetry: the blade tip jumps 40–47 m/s on the first frame of hits 2–4 (`combat_capture` swings 5, 8, 13, 16; `COMBAT_AUDIT.md` C6).

## What (the new clips already exist for this)

`res://assets/incoming/animations/combat/UAL_Combat.glb` (registered in `Assets.UAL_FILES`) holds each player hit twice:
- `Sword_Light_N` — the full body (hips lead, the lead foot steps in, root motion in `root`).
- `Sword_Light_N_Upper` — the hip yaw is folded into the spine, and the IK hand/blade targets are the same. The blade crosses the target on the same frame even when the pelvis comes from locomotion.

Frame numbers and step distances come from `combat_markers.json` (`CombatMarkers.get_clip()`).

## Diff: `character_animator.gd`

Two attack slots (A/B) replace the single `upper` OneShot. Each slot has an upper-body OneShot (filtered, `_Upper` clip) and a full-body OneShot (unfiltered, full clip). The slots alternate on every swing, so the new swing fades in over the swing still on screen.

`stand_mix` picks the full-body version by ground speed: 1 at ≤ 0.3 m/s, 0 at ≥ 1.5 m/s. This is the blend mask: lower body + pelvis from the attack when standing, from locomotion when moving.

```diff
@@ var _upper_anim: AnimationNodeAnimation
 var _upper_anim: AnimationNodeAnimation
+var _atk_up: Array[AnimationNodeAnimation] = []     # slot A/B upper-body clip (<clip>_Upper when it exists)
+var _atk_full: Array[AnimationNodeAnimation] = []   # slot A/B full-body clip
+var _atk_slot := 0
+var _stand := 0.0
@@ func _init(...)
-	_upper_anim = _anim("1H_Melee_Attack_Chop")
-	_root.add_node("upper_anim", _upper_anim, Vector2(250, 200))
-	var upper_speed := AnimationNodeTimeScale.new()
-	_root.add_node("upper_speed", upper_speed, Vector2(400, 200))
-	var upper := AnimationNodeOneShot.new()
-	upper.fadein_time = 0.08
-	upper.fadeout_time = 0.18
-	_filter_upper(upper)
-	_root.add_node("upper", upper, Vector2(550, 0))
+	# Upper OneShot kept for casts / block hits / reactions (play_upper), unchanged:
+	_upper_anim = _anim("Hit_Chest")
+	_root.add_node("upper_anim", _upper_anim, Vector2(250, 200))
+	_root.add_node("upper_speed", AnimationNodeTimeScale.new(), Vector2(400, 200))
+	var upper := AnimationNodeOneShot.new()
+	upper.fadein_time = 0.06
+	upper.fadeout_time = 0.15
+	_filter_upper(upper)
+	_root.add_node("upper", upper, Vector2(550, 0))
+	# Attack slots: atk_a -> atk_b (upper, filtered) -> stand_a -> stand_b (full body) ; stand_mix picks by speed.
+	for s in ["a", "b"]:
+		var up := _anim("Hit_Chest")
+		_atk_up.append(up)
+		_root.add_node("atk_%s_anim" % s, up, Vector2(700, 300))
+		_root.add_node("atk_%s_speed" % s, AnimationNodeTimeScale.new(), Vector2(800, 300))
+		var os := AnimationNodeOneShot.new()
+		os.fadein_time = 0.06     # fades in over the pose on screen (the other slot), not over idle
+		os.fadeout_time = 0.2     # the clip's own recovery is authored; this only covers an early cancel
+		_filter_upper(os)
+		_root.add_node("atk_" + s, os, Vector2(900, 0))
+		var fl := _anim("Hit_Chest")
+		_atk_full.append(fl)
+		_root.add_node("stand_%s_anim" % s, fl, Vector2(700, 500))
+		_root.add_node("stand_%s_speed" % s, AnimationNodeTimeScale.new(), Vector2(800, 500))
+		var fos := AnimationNodeOneShot.new()
+		fos.fadein_time = 0.06
+		fos.fadeout_time = 0.2
+		_root.add_node("stand_" + s, fos, Vector2(1000, 0))
+	_root.add_node("stand_mix", AnimationNodeBlend2.new(), Vector2(1100, 0))
@@ connections
-	_root.connect_node("full", 0, "upper")
+	_root.connect_node("atk_a_speed", 0, "atk_a_anim")
+	_root.connect_node("atk_b_speed", 0, "atk_b_anim")
+	_root.connect_node("stand_a_speed", 0, "stand_a_anim")
+	_root.connect_node("stand_b_speed", 0, "stand_b_anim")
+	_root.connect_node("atk_a", 0, "upper")
+	_root.connect_node("atk_a", 1, "atk_a_speed")
+	_root.connect_node("atk_b", 0, "atk_a")
+	_root.connect_node("atk_b", 1, "atk_b_speed")
+	_root.connect_node("stand_a", 0, "atk_b")
+	_root.connect_node("stand_a", 1, "stand_a_speed")
+	_root.connect_node("stand_b", 0, "stand_a")
+	_root.connect_node("stand_b", 1, "stand_b_speed")
+	_root.connect_node("stand_mix", 0, "atk_b")
+	_root.connect_node("stand_mix", 1, "stand_b")
+	_root.connect_node("full", 0, "stand_mix")
@@ func update(delta, speed, move_dir)
 	_block = move_toward(_block, _block_target, delta * 6.0)
 	tree["parameters/block/blend_amount"] = _block
+	# Standing attacks use the full-body clip (hips, step-in); moving ones keep the locomotion legs.
+	var want_stand := 1.0 - smoothstep(0.3, 1.5, _speed)
+	_stand = move_toward(_stand, want_stand, delta * 8.0)
+	tree["parameters/stand_mix/blend_amount"] = _stand
@@
+## Attack on alternating slots: the new swing fades in over the one on screen (no snap back to the base pose).
+## `clip` is the full-body name; the upper slot uses "<clip>_Upper" when the library has it.
+func play_attack(clip: String, time_scale := 1.0) -> void:
+	var old := "a" if _atk_slot == 0 else "b"
+	_atk_slot = 1 - _atk_slot
+	var s := "a" if _atk_slot == 0 else "b"
+	var full_name := _clip(clip)
+	var up_name := full_name + "_Upper" if player.has_animation(full_name + "_Upper") else full_name
+	_atk_up[_atk_slot].animation = up_name
+	_atk_full[_atk_slot].animation = full_name
+	tree["parameters/atk_%s_speed/scale" % s] = time_scale
+	tree["parameters/stand_%s_speed/scale" % s] = time_scale
+	tree["parameters/atk_%s/request" % s] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
+	tree["parameters/stand_%s/request" % s] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
+	# the old slot keeps playing underneath the new one's fade-in, then leaves
+	tree["parameters/atk_%s/request" % old] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT
+	tree["parameters/stand_%s/request" % old] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT
+
+func stop_attack() -> void:
+	for s in ["a", "b"]:
+		tree["parameters/atk_%s/request" % s] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT
+		tree["parameters/stand_%s/request" % s] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT
+
+func is_attack_busy() -> bool:
+	return tree["parameters/atk_a/active"] or tree["parameters/atk_b/active"]
```

Also update `is_upper_busy()` callers that meant "attacking" to `is_attack_busy()`. The rig's `set_state` "full busy" should include `_stand > 0.5 and is_attack_busy()`, so foot IK eases off during the step-in.

## Diff: `player.gd`

This goes after the COMBO table switch that is already applied (`COMBAT_AUDIT.md` "Applied").

```diff
@@ func _start_swing() -> void:
-	_kick(facing() * lunge)
+	# Lunge = the clip's authored step (root travel), started on its step frame, and only when standing
+	# (the full-body clip then plants the lead foot exactly where the capsule arrives: no foot slide).
+	var mk := CombatMarkers.get_clip(step["anim"])
+	var step_m: float = float(mk.get("step_in_m", 0.0))
+	if target:
+		step_m = minf(step_m, maxf(gap, 0.0))        # never into the enemy (LUNGE_STANDOFF)
+	if _move_speed < 0.3 and step_m > 0.0:
+		var step_f: Array = mk.get("step_frames", [0, 0])
+		var v := sqrt(2.0 * IMPULSE_DECEL * step_m)  # travel under IMPULSE_DECEL = v^2 / 2a
+		get_tree().create_timer(float(step_f[0]) / 30.0 / float(step["speed"])).timeout.connect(
+			func() -> void: if id == _swing_id: _kick(facing() * v))
-	_animator.play_upper(step["anim"], step["speed"] * (0.7 if weak else 1.0))
+	_animator.play_attack(step["anim"], step["speed"] * (0.7 if weak else 1.0))
@@ func _start_dodge(is_ability: bool) -> void:
 	if _swing > 0.0:
 		_swing_id += 1
-		_animator.stop_upper()
+		_animator.stop_attack()
```

`soldier.gd` (bandits, guards): replace `_animator.play_upper([...][randi() % 3], 1.4)` with
`_animator.play_attack("Sword_Light_%d" % (1 + randi() % 3), 1.0)`. Replace the fixed 0.3 s damage timer with
`CombatMarkers.time_s(clip, "hit", 1.0)`.

## Cost

Four extra OneShots and one Blend2 per humanoid tree.
- Idle OneShots are near-free: the tree skips inactive branches (the flinch-tree bench measured +0.03 ms idle).
- While an attack plays, one extra clip is sampled: about +0.02 ms per character on PC, x5 on a phone.
- Soldiers beyond the full-tree budget can keep the current single-slot path (`play_upper`).

## How to check

Run `kingdom/tools_qa/combat_audit/combat_capture.tscn` scenarios c01, c02 and c10.
- `analyse_capture.py`: no tip-speed spike above 30 m/s on the first frame of a swing.
- Sheets: the lead foot plants where the capsule lunge ends, and the blade crosses the enemy on the hit-stop frame.
