# P10 — Directional, weighted hit reactions and stagger (player, soldiers/bandits)

Owner: Codex (`player.gd take_damage`, `army/soldier.gd take_damage`, `character_animator.gd PREFERRED_CLIPS`).
Evidence: `COMBAT_AUDIT.md` issue C5.
- Every hit plays `Hit_A` = UAL `Hit_Chest`: 0.33 s at 1.5x = 7 frames, on the upper body only, with 3 cm of chest travel.
- It is the same for a goblin poke, an orc slam from the side, and a troll club from behind.
- Guard break plays `Block_Hit` (remapped from `Hit_B`).
- Sheet: `docs/anim/combat/game_before/c07_orc_attacks_sheet_001.jpg` #11–#13 (orc slam → a barely visible flinch).

## New clips (`UAL_Combat.glb`, authored, `tools/anim/combat/combat_clips_reactions.py`)

| clip | frames | extreme | recovered | notes |
|---|---:|---:|---:|---|
| `Hit_Light_Front/Back/Left/Right` | 16 | f2 | f10 | 15° torso whip + head whip; pelvis 4.5 cm; overshoot back; feet planted |
| `Hit_Heavy_Front/Back/Left/Right` | 27 | f3 | f20 | 30° whip; pelvis 14 cm; knee dip; catch step with the foot on the push side |
| `Stagger_Back` / `Stagger_Forward` | 41 | f2 | f32 | 3 stumbling steps; 0.63 m root travel (root motion or capsule slide over 0.8 s) |

All clips start and end in the shared ready pose, and the contact is frame 0 (no anticipation on the victim).
Sheets: `docs/anim/combat/after/Hit_Heavy_Left/`, `docs/anim/combat/after/Stagger_Back/`.

## Diff: `player.gd`

```diff
@@ func take_damage(amount: int, from: Node = null, knockback := Vector3.ZERO) -> void:
-	elif not blocking:
-		_flinch = FLINCH_TIME
-		_animator.play_upper("Hit_A", 1.5)
+	elif not blocking:
+		_flinch = FLINCH_TIME
+		var heavy := amount >= max_health * 0.12 or knockback.length() >= 4.0
+		var clip := "Hit_%s_%s" % ["Heavy" if heavy else "Light", _hit_side(from)]
+		if heavy:
+			_animator.play_full(clip, 1.0)      # whole body: the catch step matches the capsule knockback
+		else:
+			_animator.play_upper(clip, 1.0)
@@
+## Which side the blow came from, in the body's frame: Front / Back / Left / Right.
+func _hit_side(from: Node) -> String:
+	if not (from is Node3D):
+		return "Front"
+	var to := (from as Node3D).global_position - global_position
+	var f := facing()
+	var fwd := f.dot(to)
+	var left := Vector3.UP.cross(f).dot(to)       # +: attacker on our left
+	if absf(fwd) >= absf(left):
+		return "Front" if fwd > 0.0 else "Back"
+	return "Left" if left > 0.0 else "Right"
@@ guard broken
-			_animator.play_full("Hit_B", 1.3)
+			_animator.play_full("Stagger_Back", 1.0)
+			_kick(-facing() * 2.2)                 # ~0.2 m burst; the clip's 3 steps carry the rest visually
```

## `soldier.gd`

Use the same `_hit_side()` helper, reading `global_transform.basis.z` as the facing.
- Light hits go to `play_upper`.
- `knockback > 4` goes to `play_full("Hit_Heavy_<side>")`.
- A parried swing goes to `play_full("Stagger_Back")` instead of the ragdoll knock-down.

## `character_animator.gd`

Once the soldier call sites are switched, `PREFERRED_CLIPS` `"Hit_B": "Block_Hit"` can go.

## Victim hit-stop

The reaction starts on the damage frame, which is also the hit-stop frame.
- Freeze the victim's mixer locally for the same duration (`tools_qa/anim_tech/lib/hitstop.gd freeze_local`).
- The reaction's frame 0 then holds through the stop and whips on release. The overshoot reads as the impact.
