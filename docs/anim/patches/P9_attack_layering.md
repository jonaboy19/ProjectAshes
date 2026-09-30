# P9 — Attack layering: full-body at a standstill, upper-body while moving, and no pop between combo hits

Owner: Codex (`kingdom/scripts/actors/character_animator.gd`, `player.gd`; `army/soldier.gd` likewise).
Evidence: `docs/anim/COMBAT_AUDIT.md` issues C1, C3, C6.
**Status: tested in game (local trial, reverted, not committed).** The diff below is exactly what ran:
- in-game capture c01/c02/c03, zero AnimationTree errors;
- hit-stop on the blade's peak frame: L1 f+8, L3 f+8;
- running attacks keep the `_Upper` path.

Proof: `docs/anim/combat/compare/p9_trial_fullbody_vs_upper.jpg`.
- Top: what is applied today. The upper-body layer only, so the idle legs slide under the lunge (#1–#8).
- Bottom: this patch. A full-body coil, the lead foot steps in as the capsule lunges (#7–#8), and the feet stay planted at contact (#8–#12).

## Why

1. **Attacks play on the upper-body OneShot only.** The legs and pelvis keep the idle/locomotion pose.
   - The authored `Sword_Light_N` clips carry the hips leading, the step-in and a weight shift. On the upper layer all of that is lost.
   - The 0.375 m capsule lunge slides planted idle feet: `game_before/c02_combo_on_orc_30fps_sheet_001.jpg` #1–#8, still visible in `game_after/…` #1–#3.
2. **Re-firing the same `AnimationNodeOneShot` while it is active restarts it** from the base pose. Before the new clips, the tip jumped 40–47 m/s on the first frame of each hand-over.
   - The new clips mitigate this: each one starts in the previous follow-through pose.
   - Alternating A/B slots remove the cause.

## Engine constraint found while testing (read before changing the design)

In an `AnimationNodeBlendTree` **a node's output can feed only one input**. `connect_node` fails with `Condition "output == p_output_node"`, and the attack slots then never play.

So there is no live `stand_mix` Blend2 between an upper and a full-body branch fed from the same base. The choice between full-body and upper-body is made **when the swing starts**, by ground speed (standing < 0.3 m/s). The four slots sit in one chain:

`block → upper → atk_a → atk_b → stand_a → stand_b → full(dodge) → output`

- `atk_*`: upper-body filter, plays the `<clip>_Upper` variant.
- `stand_*`: unfiltered, plays the full-body `<clip>`.
- A new swing fades in (0.06 s) over the pose on screen, and the previous slot fades out underneath it.

## Tested diff

```diff
diff --git a/kingdom/scripts/actors/character_animator.gd b/kingdom/scripts/actors/character_animator.gd
index 1340aecb..2cbb8f5b 100644
--- a/kingdom/scripts/actors/character_animator.gd
+++ b/kingdom/scripts/actors/character_animator.gd
@@ -82,6 +82,10 @@ var stride_scale := 1.0
 var rig: Node
 var _root: AnimationNodeBlendTree
 var _upper_anim: AnimationNodeAnimation
+var _atk_up: Array[AnimationNodeAnimation] = []
+var _atk_full: Array[AnimationNodeAnimation] = []
+var _atk_slot := 0
+var _stand := 0.0
 var _full_anim: AnimationNodeAnimation
 var _block_target := 0.0
 var _block := 0.0
@@ -202,6 +206,24 @@ func _init(model: Node3D, run_speed: float, _walk_speed := -1.0, walk_anim := "W
 	upper.fadeout_time = 0.18
 	_filter_upper(upper)
 	_root.add_node("upper", upper, Vector2(550, 0))
+	for s in ["a", "b"]:
+		var up := _anim("1H_Melee_Attack_Chop")
+		_atk_up.append(up)
+		_root.add_node("atk_%s_anim" % s, up, Vector2(700, 300))
+		_root.add_node("atk_%s_speed" % s, AnimationNodeTimeScale.new(), Vector2(800, 300))
+		var os := AnimationNodeOneShot.new()
+		os.fadein_time = 0.06
+		os.fadeout_time = 0.2
+		_filter_upper(os)
+		_root.add_node("atk_" + s, os, Vector2(900, 0))
+		var fl := _anim("1H_Melee_Attack_Chop")
+		_atk_full.append(fl)
+		_root.add_node("stand_%s_anim" % s, fl, Vector2(700, 500))
+		_root.add_node("stand_%s_speed" % s, AnimationNodeTimeScale.new(), Vector2(800, 500))
+		var fos := AnimationNodeOneShot.new()
+		fos.fadein_time = 0.06
+		fos.fadeout_time = 0.2
+		_root.add_node("stand_" + s, fos, Vector2(1000, 0))
 
 	_full_anim = _anim("Dodge_Forward")
 	_root.add_node("full_anim", _full_anim, Vector2(550, 200))
@@ -218,7 +240,19 @@ func _init(model: Node3D, run_speed: float, _walk_speed := -1.0, walk_anim := "W
 	_root.connect_node("upper", 0, "block")
 	_root.connect_node("upper", 1, "upper_speed")
 	_root.connect_node("full_speed", 0, "full_anim")
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
+	_root.connect_node("full", 0, "stand_b")
 	_root.connect_node("full", 1, "full_speed")
 	_root.connect_node("output", 0, "full")
 
@@ -437,6 +471,38 @@ func stop_full() -> void:
 
 
 ## Cut an arms-only action short (e.g. a dodge cancelling a swing's recovery).
+## `standing`: full-body clip (hips, step-in; legs from the attack) on the stand slots; otherwise the
+## <clip>_Upper variant on the filtered slots over the running legs. Chosen when the swing starts.
+func play_attack(clip: String, time_scale := 1.0, standing := true) -> void:
+	var old := "a" if _atk_slot == 0 else "b"
+	_atk_slot = 1 - _atk_slot
+	var s := "a" if _atk_slot == 0 else "b"
+	var full_name := _clip(clip)
+	var up_name := full_name + "_Upper" if player.has_animation(full_name + "_Upper") else full_name
+	var kind := "stand" if standing else "atk"
+	if standing:
+		_atk_full[_atk_slot].animation = full_name
+	else:
+		_atk_up[_atk_slot].animation = up_name
+	_stand = 1.0 if standing else 0.0
+	tree["parameters/%s_%s_speed/scale" % [kind, s]] = time_scale
+	tree["parameters/%s_%s/request" % [kind, s]] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
+	# the previous swing (either kind) keeps playing underneath the new one's fade-in, then leaves
+	for k in ["atk", "stand"]:
+		tree["parameters/%s_%s/request" % [k, old]] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT
+	tree["parameters/%s_%s/request" % ["stand" if not standing else "atk", s]] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT
+
+
+func stop_attack() -> void:
+	for s in ["a", "b"]:
+		tree["parameters/atk_%s/request" % s] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT
+		tree["parameters/stand_%s/request" % s] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT
+
+
+func is_stand_attack() -> bool:
+	return _stand > 0.5 and (tree["parameters/stand_a/active"] or tree["parameters/stand_b/active"])
+
+
 func stop_upper() -> void:
 	if tree["parameters/upper/active"]:
 		tree["parameters/upper/request"] = AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT
diff --git a/kingdom/scripts/actors/player.gd b/kingdom/scripts/actors/player.gd
index 8c87d80e..ffac5cd6 100644
--- a/kingdom/scripts/actors/player.gd
+++ b/kingdom/scripts/actors/player.gd
@@ -504,7 +504,7 @@ func _physics_process(delta: float) -> void:
 	if _rig:
 		# Feet off the ground: airborne, swimming, rolling, dead. Big hits ease the IK off.
 		_rig.call("set_state", travel.length(), is_on_floor(), swimming or dead or _dodge > 0.0,
-				_animator.is_full_busy())
+				_animator.is_full_busy() or _animator.is_stand_attack())
 	_update_lean(delta)
 	_update_footsteps(delta, dir, grounded and not swimming)
 
@@ -1125,8 +1125,21 @@ func _start_swing() -> void:
 		# Travel under IMPULSE_DECEL is v²/(2a): pick v so the step ends at the standoff.
 		var gap := Vector2(target.global_position.x - global_position.x, target.global_position.z - global_position.z).length() - LUNGE_STANDOFF
 		lunge = clampf(sqrt(maxf(gap, 0.0) * 2.0 * IMPULSE_DECEL), 0.0, ATTACK_LUNGE)
-	_kick(facing() * lunge)
 	_swing_id += 1
+	var base_anim := String(step["anim"]).trim_suffix("_Upper")
+	var mk := CombatMarkers.get_clip(base_anim)
+	var step_m := float(mk.get("step_in_m", 0.0))
+	if _move_speed < 0.3 and step_m > 0.0:
+		# P9 trial: the lunge equals the clip's authored step, started on its step frame.
+		if target:
+			step_m = minf(step_m, maxf(Vector2(target.global_position.x - global_position.x, target.global_position.z - global_position.z).length() - LUNGE_STANDOFF, 0.0))
+		var v := sqrt(2.0 * IMPULSE_DECEL * step_m)
+		var sf: Array = mk.get("step_frames", [0, 0])
+		var sid := _swing_id
+		get_tree().create_timer(float(sf[0]) / 30.0 / float(step["speed"])).timeout.connect(func() -> void:
+			if sid == _swing_id: _kick(facing() * v))
+	else:
+		_kick(facing() * lunge)
 	_swing = step["lock"]
 	_swing_elapsed = 0.0
 	_swing_hit = hit_t
@@ -1135,7 +1148,7 @@ func _start_swing() -> void:
 	if _combo == COMBO.size() - 1:
 		_combo_window = 0.0     # finisher ends the chain
 		_swing_cancel = 0.0     # and commits to its full recovery
-	_animator.play_upper(step["anim"], step["speed"] * (0.7 if weak else 1.0))
+	_animator.play_attack(base_anim, step["speed"] * (0.7 if weak else 1.0), _move_speed < 0.3)
 	Audio.sfx("swing", null, -4.0)
 	if _viewmodel.visible:
 		var t := create_tween()
@@ -1210,7 +1223,7 @@ func _start_dodge(is_ability: bool) -> void:
 	_invulnerable = DASH_INVULNERABLE if is_ability else 0.35
 	if _swing > 0.0:
 		_swing_id += 1          # a pending hit frame no longer lands
-		_animator.stop_upper()
+		_animator.stop_attack()
 		if _trail:
 			_trail.stop()
 	_swing = 0.0
```

## Notes for the full integration

- `COMBO[...]["anim"]` can go back to plain `Sword_Light_N`; `play_attack` picks `_Upper` itself. The trial used `trim_suffix("_Upper")`.
- The **lunge = the authored step** (`CombatMarkers.get_clip(clip).step_in_m`, started at `step_frames[0] / 30 / speed`). It is capped at the gap to `LUNGE_STANDOFF`, and it only applies when standing; moving swings keep the current kick.
  - With `IMPULSE_DECEL` 12 the capsule arrives about 4 frames after the foot plants (f9 at 1.2x).
  - A per-swing decel of `v / step_duration` would make them land together. This is optional polish.
- `soldier.gd`:
  - `play_attack("Sword_Light_%d" % (1 + randi() % 3), 1.0, _velocity.length() < 0.3)`
  - damage at `CombatMarkers.time_s(clip, "hit", 1.0)` instead of the fixed 0.3 s.
- The rig: `set_state(..., is_full_busy() or is_stand_attack())` eases foot IK off during the authored step (included in the diff).

## Cost

Four OneShots per humanoid tree; only the firing slot samples a clip, so an idle attack costs almost nothing. Soldiers outside the full-tree budget can stay on `play_upper`.

## How to check

`combat_capture.tscn --only=c01,c02,c03` + `analyse_capture.py`:
- no tip spike above 30 m/s on a swing's first frame;
- the hit-stop frame equals the blade's peak frame;
- on the sheets, the lead foot plants where the capsule stops.
