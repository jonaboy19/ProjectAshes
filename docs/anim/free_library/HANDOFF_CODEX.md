# HANDOFF for Codex: free clip libraries (`animations_free` + `animations_free2`)

Clips only; behaviour (state machine, blending, input) is yours. Nothing in `assets.gd` was changed. 207 clips on the UAL 65-bone skeleton, 30 fps, no name collides with the 270
clips already loaded through `Assets.UAL_FILES` (checked by script). Review verdicts and what was fixed / rejected: [review_results.md](review_results.md). Clip catalogue (source, licence): [clip_tables.md](clip_tables.md),
[../advanced/README.md](../advanced/README.md).

## 1. Exact `Assets.UAL_FILES` lines to add

In `kingdom/scripts/world/assets.gd` (next to `UAL_ANIM_DIR`), add two directory constants and append the GLBs to `UAL_FILES` (the current last entry is
`UAL_ANIM_DIR + "cmu_mocap/UAL_CMU_Mocap.glb"]`: put a comma after it and add these lines before the closing `]`):

```gdscript
const UAL_FREE_DIR := "res://assets/incoming/animations_free/"
const UAL_FREE2_DIR := "res://assets/incoming/animations_free2/"
# ... UAL_FILES := [ ...existing entries...,
	UAL_ANIM_DIR + "cmu_mocap/UAL_CMU_Mocap.glb",
	# Free clip library, round 3 (CMU mocap + KayKit CC0, docs/anim/free_library/HANDOFF_CODEX.md)
	UAL_FREE_DIR + "martial_arts_unarmed/UAL_Free_MartialArtsUnarmed.glb",
	UAL_FREE_DIR + "combos/UAL_Free_Combos.glb",
	UAL_FREE_DIR + "kicks/UAL_Free_Kicks.glb",
	UAL_FREE_DIR + "defense/UAL_Free_Defense.glb",
	UAL_FREE_DIR + "acrobatics/UAL_Free_Acrobatics.glb",
	UAL_FREE_DIR + "reactions/UAL_Free_Reactions.glb",
	UAL_FREE_DIR + "casting/UAL_Free_Casting.glb",
	UAL_FREE_DIR + "casting/UAL_Free_CastingKaykit.glb",
	UAL_FREE_DIR + "weapons/UAL_Free_Weapons.glb",
	UAL_FREE2_DIR + "kaykit_combat_reactions/UAL_Kay_combat_reactions.glb",
	UAL_FREE2_DIR + "kaykit_life_sim/UAL_Kay_life_sim.glb",
	UAL_FREE2_DIR + "kaykit_movement_ext/UAL_Kay_movement_ext.glb",
	UAL_FREE2_DIR + "kaykit_ranged/UAL_Kay_ranged.glb",
	UAL_FREE2_DIR + "kaykit_undead/UAL_Kay_undead.glb",
	UAL_FREE2_DIR + "traversal_authored/UAL_Authored_Traversal.glb"]
```

**Root-motion caveat (needs one more edit in `_ual_for`):** the line `var root_motion_lib := file.begins_with(UAL_ANIM_DIR)` only matches `res://assets/incoming/animations/`
(`animations_free/` does not start with `animations/`). For the new libraries the `root` position track would therefore stay ENABLED and every clip with travel (dodges 1 m, cartwheels 2 m,
jump kicks) would move the character on its own. Use

```gdscript
var root_motion_lib := file.begins_with(UAL_ANIM_DIR) or file.begins_with(UAL_FREE_DIR) or file.begins_with(UAL_FREE2_DIR)
```

which disables the track (in-place playback, the convention of the other libraries). For the clips marked **root motion: yes** below, duplicate the Animation, keep / re-enable
`<skeleton>:root` and set `AnimationPlayer.root_motion_track` to `<skeleton>:root` while it plays (recipe in `assets/incoming/animations/README.md`, "Root motion").

Names: Godot strips the `_Loop` suffix on import and sets the loop mode, so the tables use the in-game names (`Kay_Block_Hold`, not `Kay_Block_Hold_Loop`). Life-sim loops are called
`Kay_Work_*_Repeat` for that reason (the old `_Loop` names collided with the one-shots and were dropped by the importer; do not name a clip `*_Cycle_Loop`, Godot reads "cycle" as a second loop hint and the import fails to rename it; fixed in round 3). `Assets.character()` builds the library once per skeleton path
(`_ual_cache`); the new GLBs are about 8 MB on disk, so load the combat libraries at start and the rest lazily if start-up time matters.

## 2. Conventions used in the tables

* Frames are 30 fps frame numbers from the start of the clip, seconds = frame / 30. Events were **measured from the bone motion** (`tools/anim/measure_events.gd`, rebuild the tables with `tools/anim/build_handoff.py`):
  `hit` = frame of maximum reach of the fastest hand (or foot for kicks) within 6 frames after its speed peak = the frame the fist / blade / foot is fully extended = **contact / release / VFX spawn frame**.
  Multi-hit clips list every hit. Clips whose events column is `-` have no strike.
* Blend times: cross-fade in / out in seconds (`AnimationPlayer.play(name, custom_blend)` or the `AnimationTree` transition time). Attacks 0.05-0.10 in, 0.12-0.20 out; loops 0.15-0.25; reactions 0.03 in.
  Recommended cancel window for combos: from the last hit frame + 0.10 s.
* Hit-stop: freeze the attacker (`speed_scale = 0`) for 0.05-0.08 s at the hit frame for heavy hits (hooks, 2H, kicks), 0.03 s for light hits; see `docs/anim/advanced/tech/README.md`.
* VFX timing: the slash arc needs about 0.1 s to read, so spawn `ElementFX.slash(...)` 3 frames **before** the hit frame (the `@f` in the table already does this) and `ElementFX.hit_sparks(...)` / impact exactly on the hit frame.
  Positions: hand / foot / weapon bone via `BoneAttachment3D` or `Skeleton3D.get_bone_global_pose`, `dir` = target - attacker (world), `yaw` = attacker's `rotation.y`. `elem` is the weapon / spell element (`&"fire"`, `&"water"`, `&"earth"`, `&"wind"`,
  `&"lightning"`, `&"ice"`, `&"light"`, `&"dark"`; aliases in `ElementFX.canon()`); use `&"light"` for neutral / physical hits.
* Root motion: **yes** when the root track travels 0.3 m or more (value = distance, direction in the character's forward / left axes of the retarget, the tables list the length only). For other clips the drift is under 0.3 m: play in place.
* Facing: every clip attacks / moves toward the front of the imported UAL model (+Z of the glTF, the same as all existing UAL clips). `_L_` clips are mirrors of the `_R_` clips (southpaw).

### `ElementFX` API used below (`kingdom/scripts/vfx/element_fx.gd`, all `static`)

```gdscript
ElementFX.play(element, type: StringName, pos: Vector3, dir := Vector3.ZERO, scale := 1.0, parent: Node = null) -> ElementEffect   # types: charge aura projectile beam impact aoe status
ElementFX.attach(element, type, node: Node3D, scale := 1.0, offset := Vector3.ZERO) -> ElementEffect                                # looping, follows the node (hand bone attachment)
ElementFX.stop(fx, fade := 0.25)
ElementFX.projectile(element, from: Vector3, to: Vector3, speed := 18.0, scale := 1.0, on_hit := Callable(), parent: Node = null) -> ElementEffect
ElementFX.beam(element, from, to, width := 1.0, seconds := 0.0, parent = null) -> ElementEffect        # ElementFX.aim_beam(fx, from, to, width) to re-aim
ElementFX.aoe(element, pos: Vector3, radius := 3.0, parent = null) -> ElementEffect
ElementFX.chain(element, points: Array, width := 1.0, hop_time := 0.07, parent = null)
ElementFX.slash(element, pos: Vector3, yaw := 0.0, tilt := 0.0, radius := 1.6, fist := false, parent = null) -> ElementEffect
ElementFX.hit_sparks(element, pos: Vector3, dir := Vector3.ZERO, scale := 1.0, parent = null) -> ElementEffect
ElementFX.dash(element, character: Node3D, dir := Vector3.ZERO, afterimages := 4, parent = null) -> ElementEffect
ElementFX.level_up(pos: Vector3, element = &"light", scale := 1.0, parent = null)
```

Typical wiring (attack clip, hit frame 24 at 30 fps):

```gdscript
var t := 24.0 / 30.0
get_tree().create_timer(t - 0.10).timeout.connect(func(): ElementFX.slash(&"fire", hand.global_position, rotation.y, 0.0, 1.2, true))
get_tree().create_timer(t).timeout.connect(func():
    ElementFX.hit_sparks(&"fire", target.global_position + Vector3.UP, (target.global_position - global_position).normalized())
    apply_damage(target))   # or connect to an AnimationPlayer method-call track on the duplicated Animation
```

Better: add a method-call track to the duplicated Animation at the frame time so the event follows `speed_scale` and blends.


## 3. Clip tables (in-game names; `Loop` = looping clip)

### martial_arts_unarmed  (`res://assets/incoming/animations_free/martial_arts_unarmed/UAL_Free_MartialArtsUnarmed.glb`)

| clip (in-game name) | s | gameplay state | blend in / out (s) | root motion | events (30 fps frame) | ElementFX (elem = element name, e.g. `&"fire"`) |
|---|---:|---|---|---|---|---|
| `MA_Kick_Front_R_Quick` | 1.60 | knee strike | 0.06 / 0.15 | no (0.12 m drift) | hit f16 (0.53 s) | `slash(elem, foot_pos, yaw, 0, 1.4, true)` @f13; `hit_sparks(elem, target_pos, dir)` @f16 |
| `MA_Punch_Cross_L_Head` | 1.60 | light attack 2 (cross) | 0.06 / 0.15 | no (0.10 m drift) | hit f24 (0.80 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f21; `hit_sparks(elem, target_pos, dir)` @f24 |
| `MA_Punch_Cross_R_Head_A` | 1.60 | light attack 2 (cross) | 0.06 / 0.15 | no (0.10 m drift) | hit f24 (0.80 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f21; `hit_sparks(elem, target_pos, dir)` @f24 |
| `MA_Punch_Cross_R_Head_B` | 1.00 | light attack 2 (cross) | 0.06 / 0.15 | no (0.09 m drift) | hit f12 (0.40 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f9; `hit_sparks(elem, target_pos, dir)` @f12 |
| `MA_Punch_Cross_R_Head_C` | 1.87 | light attack 2 (cross) | 0.06 / 0.15 | no | hit f27 (0.90 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f24; `hit_sparks(elem, target_pos, dir)` @f27 |
| `MA_Punch_Hook_L_A` | 1.60 | heavy attack (hook) | 0.08 / 0.18 | no (0.09 m drift) | hit f24 (0.80 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f21; `hit_sparks(elem, target_pos, dir)` @f24 |
| `MA_Punch_Hook_L_B` | 2.20 | heavy attack (hook) | 0.08 / 0.18 | no (0.07 m drift) | hit f40 (1.33 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f37; `hit_sparks(elem, target_pos, dir)` @f40 |
| `MA_Punch_Hook_L_C` | 1.97 | heavy attack (hook) | 0.08 / 0.18 | no | hit f30 (1.00 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f27; `hit_sparks(elem, target_pos, dir)` @f30 |
| `MA_Punch_Hook_L_D` | 1.67 | heavy attack (hook) | 0.08 / 0.18 | no | hit f21 (0.70 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f18; `hit_sparks(elem, target_pos, dir)` @f21 |
| `MA_Punch_Hook_R_A` | 1.60 | heavy attack (hook) | 0.08 / 0.18 | no (0.09 m drift) | hit f24 (0.80 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f21; `hit_sparks(elem, target_pos, dir)` @f24 |
| `MA_Punch_Hook_R_B` | 2.20 | heavy attack (hook) | 0.08 / 0.18 | no (0.07 m drift) | hit f40 (1.33 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f37; `hit_sparks(elem, target_pos, dir)` @f40 |
| `MA_Punch_Hook_R_Body` | 2.17 | heavy attack (hook) | 0.08 / 0.18 | no (0.19 m drift) | hit f30 (1.00 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f27; `hit_sparks(elem, target_pos, dir)` @f30 |
| `MA_Punch_Hook_R_C` | 1.63 | heavy attack (hook) | 0.08 / 0.18 | no | hit f25 (0.83 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f22; `hit_sparks(elem, target_pos, dir)` @f25 |
| `MA_Punch_Hook_R_D` | 1.97 | heavy attack (hook) | 0.08 / 0.18 | no | hit f30 (1.00 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f27; `hit_sparks(elem, target_pos, dir)` @f30 |
| `MA_Punch_Hook_R_E` | 1.67 | heavy attack (hook) | 0.08 / 0.18 | no | hit f21 (0.70 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f18; `hit_sparks(elem, target_pos, dir)` @f21 |
| `MA_Punch_Jab_L_Body` | 1.67 | light attack 1 (jab) | 0.05 / 0.12 | no | hit f27 (0.90 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f24; `hit_sparks(elem, target_pos, dir)` @f27 |
| `MA_Punch_Jab_L_Head_A` | 1.57 | light attack 1 (jab) | 0.05 / 0.12 | no (0.08 m drift) | hit f23 (0.77 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f20; `hit_sparks(elem, target_pos, dir)` @f23 |
| `MA_Punch_Jab_L_Head_B` | 1.90 | light attack 1 (jab) | 0.05 / 0.12 | no | hit f27 (0.90 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f24; `hit_sparks(elem, target_pos, dir)` @f27 |
| `MA_Punch_Jab_R_Head` | 1.57 | light attack 1 (jab) | 0.05 / 0.12 | no (0.08 m drift) | hit f23 (0.77 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f20; `hit_sparks(elem, target_pos, dir)` @f23 |

### combos  (`res://assets/incoming/animations_free/combos/UAL_Free_Combos.glb`)

| clip (in-game name) | s | gameplay state | blend in / out (s) | root motion | events (30 fps frame) | ElementFX (elem = element name, e.g. `&"fire"`) |
|---|---:|---|---|---|---|---|
| `MA_Combo_CrossCross` | 2.33 | combo chain (n hits, cancel window after each hit + 0.10 s) | 0.08 / 0.20 | no (0.15 m drift) | hit f15 (0.50 s), f24 (0.80 s), f55 (1.83 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f12/21/52; `hit_sparks(elem, target_pos, dir)` @f15/24/55 |
| `MA_Combo_HookHook` | 1.75 | combo chain (n hits, cancel window after each hit + 0.10 s) | 0.08 / 0.20 | no (0.07 m drift) | hit f28 (0.93 s), f42 (1.40 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f25/39; `hit_sparks(elem, target_pos, dir)` @f28/42 |
| `MA_Combo_HookJab` | 1.33 | combo chain (n hits, cancel window after each hit + 0.10 s) | 0.08 / 0.20 | no (0.08 m drift) | hit f16 (0.53 s), f31 (1.03 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f13/28; `hit_sparks(elem, target_pos, dir)` @f16/31 |
| `MA_Combo_HookStraight` | 1.60 | combo chain (n hits, cancel window after each hit + 0.10 s) | 0.08 / 0.20 | no (0.07 m drift) | hit f17 (0.57 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f14; `hit_sparks(elem, target_pos, dir)` @f17 |
| `MA_Combo_JabCross` | 1.45 | combo chain (n hits, cancel window after each hit + 0.10 s) | 0.08 / 0.20 | no (0.09 m drift) | hit f10 (0.33 s), f21 (0.70 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f7/18; `hit_sparks(elem, target_pos, dir)` @f10/21 |
| `MA_Combo_JabCross_Southpaw` | 1.45 | combo chain (n hits, cancel window after each hit + 0.10 s) | 0.08 / 0.20 | no (0.09 m drift) | hit f10 (0.33 s), f21 (0.70 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f7/18; `hit_sparks(elem, target_pos, dir)` @f10/21 |
| `MA_Combo_StraightStraight` | 1.40 | combo chain (n hits, cancel window after each hit + 0.10 s) | 0.08 / 0.20 | no (0.08 m drift) | hit f12 (0.40 s), f22 (0.73 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f9/19; `hit_sparks(elem, target_pos, dir)` @f12/22 |

### kicks  (`res://assets/incoming/animations_free/kicks/UAL_Free_Kicks.glb`)

| clip (in-game name) | s | gameplay state | blend in / out (s) | root motion | events (30 fps frame) | ElementFX (elem = element name, e.g. `&"fire"`) |
|---|---:|---|---|---|---|---|
| `MA_Kick_Front_L_High` | 2.20 | kick attack | 0.08 / 0.16 | no | hit f29 (0.97 s) | `slash(elem, foot_pos, yaw, 0, 1.4, true)` @f26; `hit_sparks(elem, target_pos, dir)` @f29 |
| `MA_Kick_Front_L_Low` | 2.07 | kick attack | 0.08 / 0.16 | no | hit f32 (1.07 s) | `slash(elem, foot_pos, yaw, 0, 1.4, true)` @f29; `hit_sparks(elem, target_pos, dir)` @f32 |
| `MA_Kick_Front_L_Mid` | 2.13 | kick attack | 0.08 / 0.16 | no | hit f27 (0.90 s) | `slash(elem, foot_pos, yaw, 0, 1.4, true)` @f24; `hit_sparks(elem, target_pos, dir)` @f27 |
| `MA_Kick_Front_R_High` | 2.17 | kick attack | 0.08 / 0.16 | no (0.07 m drift) | hit f27 (0.90 s) | `slash(elem, foot_pos, yaw, 0, 1.4, true)` @f24; `hit_sparks(elem, target_pos, dir)` @f27 |
| `MA_Kick_Front_R_Low` | 1.83 | kick attack | 0.08 / 0.16 | no (0.12 m drift) | hit f28 (0.93 s) | `slash(elem, foot_pos, yaw, 0, 1.4, true)` @f25; `hit_sparks(elem, target_pos, dir)` @f28 |
| `MA_Kick_Front_R_Mid` | 1.87 | kick attack | 0.08 / 0.16 | no (0.18 m drift) | hit f27 (0.90 s) | `slash(elem, foot_pos, yaw, 0, 1.4, true)` @f24; `hit_sparks(elem, target_pos, dir)` @f27 |
| `MA_Kick_JumpHigh_A` | 2.70 | leap / flying kick (root motion) | 0.10 / 0.20 | **yes**, 2.3 m | hit f43 (1.43 s) | `slash(elem, foot_pos, yaw, 0, 1.4, true)` @f40; `hit_sparks(elem, target_pos, dir)` @f43 |
| `MA_Kick_JumpHigh_B` | 2.60 | leap / flying kick (root motion) | 0.10 / 0.20 | **yes**, 2.1 m | hit f61 (2.03 s) | `slash(elem, foot_pos, yaw, 0, 1.4, true)` @f58; `hit_sparks(elem, target_pos, dir)` @f61 |
| `MA_Kick_Jump_L` | 1.23 | leap / flying kick (root motion) | 0.10 / 0.20 | **yes**, 1.2 m | hit f13 (0.43 s) | `slash(elem, foot_pos, yaw, 0, 1.4, true)` @f10; `hit_sparks(elem, target_pos, dir)` @f13 |
| `MA_Kick_Jump_R` | 1.23 | leap / flying kick (root motion) | 0.10 / 0.20 | **yes**, 1.2 m | hit f13 (0.43 s) | `slash(elem, foot_pos, yaw, 0, 1.4, true)` @f10; `hit_sparks(elem, target_pos, dir)` @f13 |
| `MA_Kick_Swing_R` | 2.17 | sweeping kick | 0.08 / 0.18 | **yes**, 0.6 m | hit f30 (1.00 s) | `slash(elem, foot_pos, yaw, 0, 1.4, true)` @f27; `hit_sparks(elem, target_pos, dir)` @f30 |

### defense  (`res://assets/incoming/animations_free/defense/UAL_Free_Defense.glb`)

| clip (in-game name) | s | gameplay state | blend in / out (s) | root motion | events (30 fps frame) | ElementFX (elem = element name, e.g. `&"fire"`) |
|---|---:|---|---|---|---|---|
| `MA_Block_L_A` | 1.17 | block / parry stance change | 0.05 / 0.15 | no (0.19 m drift) | - | `hit_sparks(elem, block_pos, dir, 0.7)` on a successful block |
| `MA_Block_L_B` | 0.80 | block / parry stance change | 0.05 / 0.15 | no (0.16 m drift) | - | `hit_sparks(elem, block_pos, dir, 0.7)` on a successful block |
| `MA_Block_L_C` | 1.03 | block / parry stance change | 0.05 / 0.15 | no (0.24 m drift) | - | `hit_sparks(elem, block_pos, dir, 0.7)` on a successful block |
| `MA_Block_R_A` | 1.13 | block / parry stance change | 0.05 / 0.15 | no (0.16 m drift) | - | `hit_sparks(elem, block_pos, dir, 0.7)` on a successful block |
| `MA_Block_R_B` | 1.53 | block / parry stance change | 0.05 / 0.15 | no | - | `hit_sparks(elem, block_pos, dir, 0.7)` on a successful block |
| `MA_Dodge_Duck` | 3.40 | dodge / duck under projectile | 0.08 / 0.20 | no (0.11 m drift) | - | - |
| `MA_Evade_AttackerCover` | 2.30 | evade / cover | 0.08 / 0.20 | **yes**, 0.5 m | - | `dash(elem, character, dir)` @f0 |
| `MA_Guard_Boxing` (loop) | 1.87 | combat idle (boxing guard) | 0.20 / 0.20 | no | - | - |

### acrobatics  (`res://assets/incoming/animations_free/acrobatics/UAL_Free_Acrobatics.glb`)

| clip (in-game name) | s | gameplay state | blend in / out (s) | root motion | events (30 fps frame) | ElementFX (elem = element name, e.g. `&"fire"`) |
|---|---:|---|---|---|---|---|
| `MA_Acro_BackflipBackOnHands` | 2.10 | back evade / acrobatic flourish (root motion) | 0.10 / 0.15 | **yes**, 1.4 m | - | `dash(elem, character, dir)` @f0 |
| `MA_Acro_Backflip_A` | 1.47 | back evade / acrobatic flourish (root motion) | 0.10 / 0.15 | **yes**, 0.5 m | - | `dash(elem, character, dir)` @f0 |
| `MA_Acro_Backflip_B` | 1.53 | back evade / acrobatic flourish (root motion) | 0.10 / 0.15 | **yes**, 1.6 m | - | `dash(elem, character, dir)` @f0 |
| `MA_Acro_Backflip_C` | 1.40 | back evade / acrobatic flourish (root motion) | 0.10 / 0.15 | **yes**, 1.3 m | - | `dash(elem, character, dir)` @f0 |
| `MA_Acro_Cartwheel_A` | 2.77 | sidestep evade (cartwheel), flourish emote (root motion) | 0.10 / 0.15 | **yes**, 2.3 m | - | `dash(elem, character, dir)` @f0 |
| `MA_Acro_Cartwheel_B` | 2.63 | sidestep evade (cartwheel), flourish emote (root motion) | 0.10 / 0.15 | **yes**, 2.4 m | - | `dash(elem, character, dir)` @f0 |
| `MA_Acro_Cartwheel_C` | 2.90 | sidestep evade (cartwheel), flourish emote (root motion) | 0.10 / 0.15 | **yes**, 2.5 m | - | `dash(elem, character, dir)` @f0 |
| `MA_Acro_Cartwheel_D` | 3.60 | sidestep evade (cartwheel), flourish emote (root motion) | 0.10 / 0.15 | **yes**, 2.6 m | - | `dash(elem, character, dir)` @f0 |
| `MA_Acro_FlipForward_Hands` | 1.70 | acrobatic flourish / traversal show-off (root motion) | 0.10 / 0.15 | no (0.19 m drift) | - | `dash(elem, character, dir)` @f0 |
| `MA_Acro_FrontHandFlip_B` | 3.00 | acrobatic flourish / traversal show-off (root motion) | 0.10 / 0.15 | **yes**, 1.7 m | - | `dash(elem, character, dir)` @f0 |
| `MA_Acro_HandSpinKick` | 3.80 | acrobatic flourish / traversal show-off (root motion) | 0.10 / 0.15 | **yes**, 2.3 m | - | `dash(elem, character, dir)` @f0 |
| `MA_Acro_Handspring` | 1.40 | acrobatic flourish / traversal show-off (root motion) | 0.10 / 0.15 | **yes**, 2.8 m | - | `dash(elem, character, dir)` @f0 |
| `MA_Acro_HandstandKicks` | 9.50 | acrobatic flourish / traversal show-off (root motion) | 0.10 / 0.15 | **yes**, 0.8 m | - | `dash(elem, character, dir)` @f0 |
| `MA_Acro_KickFlip` | 2.60 | acrobatic flourish / traversal show-off (root motion) | 0.10 / 0.15 | **yes**, 0.8 m | - | `dash(elem, character, dir)` @f0 |
| `MA_Acro_SideFlip` | 2.30 | acrobatic flourish / traversal show-off (root motion) | 0.10 / 0.15 | **yes**, 1.3 m | - | `dash(elem, character, dir)` @f0 |
| `MA_Acro_Somersault_Back` | 3.50 | back evade / acrobatic flourish (root motion) | 0.10 / 0.15 | **yes**, 1.9 m | - | `dash(elem, character, dir)` @f0 |

### reactions  (`res://assets/incoming/animations_free/reactions/UAL_Free_Reactions.glb`)

| clip (in-game name) | s | gameplay state | blend in / out (s) | root motion | events (30 fps frame) | ElementFX (elem = element name, e.g. `&"fire"`) |
|---|---:|---|---|---|---|---|
| `Fall_BackflipTwist` | 3.50 | knockdown (play GetUp_* afterwards) | 0.06 / 0.10 | **yes**, 0.6 m | hit f0; on ground from f88 (2.93 s) | `hit_sparks(elem, chest_pos, dir)` @f0 |
| `Fall_Forward_Knockdown` | 2.00 | knockdown (play GetUp_* afterwards) | 0.06 / 0.10 | no (0.16 m drift) | hit f0; on ground from f45 (1.50 s) | `hit_sparks(elem, chest_pos, dir)` @f0 |
| `Fall_RugPull_Back` | 2.00 | knockdown (play GetUp_* afterwards) | 0.06 / 0.10 | no | hit f0; on ground from f10 (0.33 s) | `hit_sparks(elem, chest_pos, dir)` @f0 |
| `Fall_Slip_Back` | 4.00 | knockdown (play GetUp_* afterwards) | 0.06 / 0.10 | **yes**, 1.7 m | hit f0; on ground from f75 (2.50 s) | `hit_sparks(elem, chest_pos, dir)` @f0 |
| `GetUp_Back_A` | 6.27 | get up after knockdown | 0.10 / 0.20 | **yes**, 0.7 m | hit f0 | - |
| `GetUp_Back_B` | 5.57 | get up after knockdown | 0.10 / 0.20 | **yes**, 0.7 m | hit f0 | - |
| `GetUp_FaceDown_A` | 5.00 | get up after knockdown | 0.10 / 0.20 | **yes**, 0.8 m | hit f0 | - |
| `GetUp_FaceDown_B` | 4.00 | get up after knockdown | 0.10 / 0.20 | **yes**, 0.6 m | hit f0 | - |
| `GetUp_Side` | 6.50 | get up after knockdown | 0.10 / 0.20 | **yes**, 0.5 m | hit f0 | - |

### casting  (`res://assets/incoming/animations_free/casting/UAL_Free_Casting.glb`)

| clip (in-game name) | s | gameplay state | blend in / out (s) | root motion | events (30 fps frame) | ElementFX (elem = element name, e.g. `&"fire"`) |
|---|---:|---|---|---|---|---|
| `Cast_Aura_Raise_Arms` | 4.20 | cast: buff / aura channel | 0.15 / 0.30 | no | arms overhead f62 (2.07 s) | `attach(&"light", &"aura", character)` @f62; `stop(fx)` at the end of the clip |
| `Cast_Aura_Raise_Arms_B` | 6.20 | cast: buff / aura channel | 0.15 / 0.30 | no | arms overhead f151 (5.03 s) | `attach(&"light", &"aura", character)` @f151; `stop(fx)` at the end of the clip |
| `Cast_Push_Palm_A` | 1.80 | cast: force push / wind blast | 0.10 / 0.20 | no | hit f17 (0.57 s) | `attach(&"wind", &"charge", hand_node)` @f0 .. hit; `play(&"wind", &"impact", palm_pos, forward)` or `projectile(&"wind", palm_pos, target, 22.0)` @f17 |
| `Cast_Push_Palm_B` | 1.60 | cast: force push / wind blast | 0.10 / 0.20 | no | hit f18 (0.60 s) | `attach(&"wind", &"charge", hand_node)` @f0 .. hit; `play(&"wind", &"impact", palm_pos, forward)` or `projectile(&"wind", palm_pos, target, 22.0)` @f18 |
| `Cast_Slam_Overhead` | 2.70 | cast: ground slam / earth AOE | 0.12 / 0.25 | no | hit f68 (2.27 s) | `attach(&"earth", &"charge", hand_node)` @f0 .. hit; `aoe(&"earth", ground_pos, 3.0)` @f68 |
| `Cast_Throw_1H` | 3.00 | cast: projectile throw (fireball) | 0.10 / 0.20 | no (0.21 m drift) | hit f62 (2.07 s) | `attach(&"fire", &"charge", hand_node)` @f0 .. release; `projectile(&"fire", hand_pos, target, 18.0)` @f62 |

### casting  (`res://assets/incoming/animations_free/casting/UAL_Free_CastingKaykit.glb`)

| clip (in-game name) | s | gameplay state | blend in / out (s) | root motion | events (30 fps frame) | ElementFX (elem = element name, e.g. `&"fire"`) |
|---|---:|---|---|---|---|---|
| `Cast_Raise_Charge` | 2.10 | cast: charge / channel start (lightning) | 0.12 / 0.20 | no | peak hand motion f8 (0.27 s) | `attach(&"lightning", &"charge", hand_node)` @f0; hold, then `chain(&"lightning", points)` @f8 |
| `Cast_Shoot_1H` | 0.93 | cast: one-hand projectile | 0.06 / 0.15 | no | hit f6 (0.20 s) | `projectile(elem, hand_pos, target, 20.0)` @f6 |
| `Cast_Spell_Long` | 2.53 | cast: long incantation (beam / big spell) | 0.10 / 0.25 | no | peak hand motion f5 (0.17 s) | `attach(elem, &"charge", hand_node)` @f0; `beam(elem, hand_pos, target, 1.0, 1.5)` @f5 |
| `Cast_Spell_Short` | 0.67 | cast: quick spell | 0.06 / 0.15 | no | peak hand motion f17 (0.57 s) | `play(elem, &"impact", target_pos)` @f17 |
| `Cast_Summon` | 4.30 | cast: summon / raise earth | 0.12 / 0.25 | no | hit f93 (3.10 s) | `aoe(&"earth", ground_pos, 3.0)` @f93 |
| `Cast_Throw_Orb` | 1.37 | cast: projectile throw (fireball) | 0.10 / 0.20 | no | hit f21 (0.70 s) | `attach(&"fire", &"charge", hand_node)` @f0 .. release; `projectile(&"fire", hand_pos, target, 18.0)` @f21 |

### weapons  (`res://assets/incoming/animations_free/weapons/UAL_Free_Weapons.glb`)

| clip (in-game name) | s | gameplay state | blend in / out (s) | root motion | events (30 fps frame) | ElementFX (elem = element name, e.g. `&"fire"`) |
|---|---:|---|---|---|---|---|
| `Hit_KK_A` | 0.67 | hit reaction (flinch) | 0.03 / 0.10 | no | recoil peak f3 (0.10 s) | `hit_sparks(elem, chest_pos, dir)` @f0 |
| `Hit_KK_B` | 0.87 | hit reaction (flinch) | 0.03 / 0.10 | no | recoil peak f7 (0.23 s) | `hit_sparks(elem, chest_pos, dir)` @f0 |
| `MA_KK_Idle_Loop` (loop) | 1.07 | unarmed combat idle | 0.20 / 0.20 | no | - | - |
| `MA_KK_Kick` | 0.93 | stylised kick | 0.06 / 0.15 | no | hit f13 (0.43 s) | `slash(elem, foot_pos, yaw, 0, 1.4, true)` @f10; `hit_sparks(elem, target_pos, dir)` @f13 |
| `MA_KK_Punch` | 1.17 | stylised punch | 0.05 / 0.12 | no (0.09 m drift) | hit f15 (0.50 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f12; `hit_sparks(elem, target_pos, dir)` @f15 |
| `Weapon_1H_Chop` | 1.07 | light attack 1H sword | 0.06 / 0.15 | no | hit f17 (0.57 s) | `slash(elem, weapon_pos, yaw, tilt, 1.6)` @f14; `hit_sparks(elem, target_pos, dir)` @f17 |
| `Weapon_1H_Chop_Jump` | 1.33 | plunge / jump attack 1H | 0.08 / 0.15 | no (0.11 m drift) | hit f22 (0.73 s) | `slash(elem, weapon_pos, yaw, tilt, 1.6)` @f19; `hit_sparks(elem, target_pos, dir)` @f22 |
| `Weapon_1H_Slice_Diagonal` | 1.00 | light attack 1H sword | 0.06 / 0.15 | no (0.09 m drift) | hit f14 (0.47 s) | `slash(elem, weapon_pos, yaw, tilt, 1.6)` @f11; `hit_sparks(elem, target_pos, dir)` @f14 |
| `Weapon_1H_Slice_Horizontal` | 1.37 | light attack 1H sword | 0.06 / 0.15 | no | hit f9 (0.30 s) | `slash(elem, weapon_pos, yaw, tilt, 1.6)` @f6; `hit_sparks(elem, target_pos, dir)` @f9 |
| `Weapon_1H_Stab` | 1.60 | light attack 1H sword | 0.06 / 0.15 | no | hit f13 (0.43 s) | `slash(elem, weapon_pos, yaw, tilt, 1.6)` @f10; `hit_sparks(elem, target_pos, dir)` @f13 |
| `Weapon_2H_Chop` | 1.63 | heavy attack 2H / staff / spear | 0.08 / 0.18 | no (0.09 m drift) | hit f25 (0.83 s) | `slash(elem, weapon_pos, yaw, tilt, 1.6)` @f22; `hit_sparks(elem, target_pos, dir)` @f25 |
| `Weapon_2H_Slice` | 1.10 | heavy attack 2H / staff / spear | 0.08 / 0.18 | no | hit f16 (0.53 s) | `slash(elem, weapon_pos, yaw, tilt, 1.6)` @f13; `hit_sparks(elem, target_pos, dir)` @f16 |
| `Weapon_2H_Spin` | 2.40 | spin attack 2H (area) | 0.10 / 0.20 | no | hit f23 (0.77 s), f38 (1.27 s) | `slash(elem, weapon_pos, yaw, tilt, 1.6)` @f20/35; `hit_sparks(elem, target_pos, dir)` @f23/38 |
| `Weapon_2H_Spinning` | 0.67 | spin attack 2H (area) | 0.10 / 0.20 | no (0.06 m drift) | hit f10 (0.33 s) | `slash(elem, weapon_pos, yaw, tilt, 1.6)` @f7; `hit_sparks(elem, target_pos, dir)` @f10 |
| `Weapon_2H_Stab` | 1.60 | heavy attack 2H / staff / spear | 0.08 / 0.18 | no (0.07 m drift) | hit f18 (0.60 s) | `slash(elem, weapon_pos, yaw, tilt, 1.6)` @f15; `hit_sparks(elem, target_pos, dir)` @f18 |
| `Weapon_Block` | 1.07 | block raise | 0.05 / 0.15 | no (0.09 m drift) | - | - |
| `Weapon_Block_Attack` | 1.07 | shield bash / counter after block | 0.05 / 0.15 | no | hit f13 (0.43 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f10; `hit_sparks(elem, target_pos, dir)` @f13 |
| `Weapon_Block_Hit` | 1.07 | block reaction (hit while blocking) | 0.03 / 0.12 | no | recoil peak f3 (0.10 s) | `hit_sparks(elem, block_pos, dir, 0.8)` @f3 |
| `Weapon_DW_Chop` | 1.27 | attack dual wield | 0.06 / 0.15 | no | hit f17 (0.57 s) | `slash(elem, weapon_pos, yaw, tilt, 1.6)` @f14; `hit_sparks(elem, target_pos, dir)` @f17 |
| `Weapon_DW_Slice` | 1.17 | attack dual wield | 0.06 / 0.15 | no (0.09 m drift) | hit f20 (0.67 s) | `slash(elem, weapon_pos, yaw, tilt, 1.6)` @f17; `hit_sparks(elem, target_pos, dir)` @f20 |
| `Weapon_DW_Stab` | 1.60 | attack dual wield | 0.06 / 0.15 | no (0.07 m drift) | hit f18 (0.60 s) | `slash(elem, weapon_pos, yaw, tilt, 1.6)` @f15; `hit_sparks(elem, target_pos, dir)` @f18 |

### kaykit_combat_reactions  (`res://assets/incoming/animations_free2/kaykit_combat_reactions/UAL_Kay_combat_reactions.glb`)

| clip (in-game name) | s | gameplay state | blend in / out (s) | root motion | events (30 fps frame) | ElementFX (elem = element name, e.g. `&"fire"`) |
|---|---:|---|---|---|---|---|
| `Kay_Attack_2H_Spin_Long` | 1.60 | spin attack 2H (area) | 0.10 / 0.20 | no (0.13 m drift) | hit f14 (0.47 s), f28 (0.93 s) | `slash(elem, weapon_pos, yaw, tilt, 1.6)` @f11/25; `hit_sparks(elem, target_pos, dir)` @f14/28 |
| `Kay_Block_Counter` | 1.07 | counter attack after block | 0.05 / 0.15 | no | hit f20 (0.67 s) | `slash(elem, hand_pos, yaw, 0, 1.2, true)` @f17; `hit_sparks(elem, target_pos, dir)` @f20 |
| `Kay_Block_Hold` (loop) | 1.07 | block hold | 0.10 / 0.12 | no | - | - |
| `Kay_Block_Impact` | 1.07 | block impact reaction | 0.03 / 0.10 | no (0.10 m drift) | recoil peak f9 (0.30 s) | `hit_sparks(elem, block_pos, dir, 0.8)` @f9 |
| `Kay_Block_Raise` | 1.07 | block start | 0.05 / 0.10 | no (0.21 m drift) | - | - |
| `Kay_Death_Fall_B` | 2.10 | death (fall, stay on last frame or hand over to ragdoll at the down frame) | 0.08 / 0.00 | **yes**, 0.8 m | hit f0; on ground from f49 (1.63 s) | `hit_sparks(elem, chest_pos, dir)` @f0; `play(&"dark", &"status", pos)` optional @down |
| `Kay_Dodge_Back` | 0.40 | dodge (0.4 s burst, blend out to idle over 0.15 s) | 0.02 / 0.15 | **yes**, 1.2 m | - | `dash(elem, character, dir)` @f0 |
| `Kay_Dodge_Fwd` | 0.40 | dodge (0.4 s burst, blend out to idle over 0.15 s) | 0.02 / 0.15 | **yes**, 0.5 m | - | `dash(elem, character, dir)` @f0 |
| `Kay_Dodge_L` | 0.40 | dodge (0.4 s burst, blend out to idle over 0.15 s) | 0.02 / 0.15 | **yes**, 1.0 m | - | `dash(elem, character, dir)` @f0 |
| `Kay_Dodge_R` | 0.40 | dodge (0.4 s burst, blend out to idle over 0.15 s) | 0.02 / 0.15 | **yes**, 1.0 m | - | `dash(elem, character, dir)` @f0 |
| `Kay_Hit_React_A` | 0.67 | hit reaction / stagger | 0.03 / 0.12 | no | recoil peak f3 (0.10 s) | `hit_sparks(elem, chest_pos, dir)` @f0 |
| `Kay_Hit_React_B` | 0.87 | hit reaction / stagger | 0.03 / 0.12 | no (0.11 m drift) | recoil peak f7 (0.23 s) | `hit_sparks(elem, chest_pos, dir)` @f0 |
| `Kay_Stance_2H_Idle` (loop) | 1.07 | combat idle (2H / fists) | 0.20 / 0.20 | no | - | - |
| `Kay_Stance_Fists_Idle` (loop) | 1.07 | combat idle (2H / fists) | 0.20 / 0.20 | no | - | - |

### kaykit_life_sim  (`res://assets/incoming/animations_free2/kaykit_life_sim/UAL_Kay_life_sim.glb`)

| clip (in-game name) | s | gameplay state | blend in / out (s) | root motion | events (30 fps frame) | ElementFX (elem = element name, e.g. `&"fire"`) |
|---|---:|---|---|---|---|---|
| `Kay_Emote_Cheer` (loop) | 1.67 | emote | 0.20 / 0.20 | no | - | - |
| `Kay_Emote_Wave` (loop) | 2.13 | emote | 0.20 / 0.20 | no | - | - |
| `Kay_Fishing_Bite` | 2.23 | fishing: bite | 0.05 / 0.10 | no (0.12 m drift) | - | `play(&"water", &"impact", bobber_pos, Vector3.UP, 0.5)` |
| `Kay_Fishing_Cast` | 1.93 | fishing: cast (release the bobber at the hit frame) | 0.10 / 0.15 | no | hit f35 (1.17 s) | `projectile(&"water", rod_tip, bobber_pos, 12.0, 0.5)` @f35 |
| `Kay_Fishing_Catch` | 3.23 | fishing: catch reveal | 0.10 / 0.20 | no | - | `level_up(pos, &"water", 0.6)` optional |
| `Kay_Fishing_Idle` (loop) | 2.33 | fishing: wait | 0.20 / 0.20 | no | - | - |
| `Kay_Fishing_Reel` (loop) | 1.60 | fishing: reel loop | 0.15 / 0.15 | no | - | - |
| `Kay_Fishing_Struggle` | 3.43 | fishing: fight the fish | 0.10 / 0.15 | no (0.09 m drift) | - | - |
| `Kay_Fishing_Tug` | 1.90 | fishing: tug | 0.08 / 0.10 | no | - | - |
| `Kay_Hold_Item_A` (loop) | 1.00 | hold item idle (upper body) | 0.15 / 0.15 | no | - | - |
| `Kay_Hold_Item_B` (loop) | 1.00 | hold item idle (upper body) | 0.15 / 0.15 | no | - | - |
| `Kay_Hold_Item_C` (loop) | 1.00 | hold item idle (upper body) | 0.15 / 0.15 | no | - | - |
| `Kay_Interact_Reach` | 1.30 | interaction (pick up / use item / reach) | 0.10 / 0.15 | no | - | - |
| `Kay_Lockpick` | 3.00 | interaction: lockpick | 0.15 / 0.20 | no | - | - |
| `Kay_Lockpick_Repeat` (loop) | 2.33 | interaction: lockpick | 0.15 / 0.20 | no | - | - |
| `Kay_Pick_Up_Ground` | 1.30 | interaction (pick up / use item / reach) | 0.10 / 0.15 | no | - | - |
| `Kay_Use_Item_Kay` | 1.60 | interaction (pick up / use item / reach) | 0.10 / 0.15 | no | - | - |
| `Kay_Work_Bench_A` | 2.53 | job: workbench / craft | 0.15 / 0.20 | no | - | - |
| `Kay_Work_Bench_A_Repeat` (loop) | 1.50 | job: workbench / craft | 0.15 / 0.20 | no | - | - |
| `Kay_Work_Bench_B` | 3.10 | job: workbench / craft | 0.15 / 0.20 | no | - | - |
| `Kay_Work_Bench_B_Repeat` (loop) | 2.53 | job: workbench / craft | 0.15 / 0.20 | no | - | - |
| `Kay_Work_Bench_C` | 3.67 | job: workbench / craft | 0.15 / 0.20 | no | - | - |
| `Kay_Work_Bench_C_Repeat` (loop) | 2.00 | job: workbench / craft | 0.15 / 0.20 | no | - | - |
| `Kay_Work_Chop_Tree` | 4.33 | job: chop tree | 0.15 / 0.20 | no | hit f19 (0.63 s), f59 (1.97 s), f99 (3.30 s) | `hit_sparks(&"earth", axe_tip, dir, 0.6)` on each hit frame |
| `Kay_Work_Chop_Tree_Repeat` (loop) | 1.33 | job: chop tree | 0.15 / 0.20 | no | hit f9 (0.30 s) | `hit_sparks(&"earth", axe_tip, dir, 0.6)` on each hit frame |
| `Kay_Work_Dig` | 4.67 | job: dig | 0.15 / 0.20 | no | hit f11 (0.37 s), f28 (0.93 s), f70 (2.33 s), f112 (3.73 s) | `hit_sparks(&"earth", spade_tip, dir, 0.6)` on each hit frame |
| `Kay_Work_Dig_Repeat` (loop) | 1.40 | job: dig | 0.15 / 0.20 | no | hit f18 (0.60 s) | `hit_sparks(&"earth", spade_tip, dir, 0.6)` on each hit frame |
| `Kay_Work_Hammer` | 4.33 | job: hammer / smith | 0.15 / 0.20 | no | - | `hit_sparks(&"fire", hammer_head, dir, 0.6)` on each hit frame |
| `Kay_Work_Hammer_Repeat` (loop) | 2.67 | job: hammer / smith | 0.15 / 0.20 | no | - | `hit_sparks(&"fire", hammer_head, dir, 0.6)` on each hit frame |
| `Kay_Work_Mine` | 6.03 | job: mine ore | 0.15 / 0.20 | no | hit f28 (0.93 s), f84 (2.80 s), f140 (4.67 s) | `hit_sparks(&"earth", pick_tip, dir, 0.7)` on each hit frame |
| `Kay_Work_Mine_Repeat` (loop) | 3.73 | job: mine ore | 0.15 / 0.20 | no | hit f8 (0.27 s), f64 (2.13 s) | `hit_sparks(&"earth", pick_tip, dir, 0.7)` on each hit frame |
| `Kay_Work_Saw` | 2.40 | job: saw | 0.15 / 0.20 | no | - | - |
| `Kay_Work_Saw_Repeat` (loop) | 0.67 | job: saw | 0.15 / 0.20 | no | - | - |

### kaykit_movement_ext  (`res://assets/incoming/animations_free2/kaykit_movement_ext/UAL_Kay_movement_ext.glb`)

| clip (in-game name) | s | gameplay state | blend in / out (s) | root motion | events (30 fps frame) | ElementFX (elem = element name, e.g. `&"fire"`) |
|---|---:|---|---|---|---|---|
| `Kay_Crouch_Idle` (loop) | 1.07 | crouch / sneak locomotion | 0.20 / 0.20 | no | - | - |
| `Kay_Idle_Kay_A` (loop) | 1.07 | idle variant | 0.25 / 0.25 | no | - | - |
| `Kay_Idle_Kay_B` (loop) | 2.13 | idle variant | 0.25 / 0.25 | no | - | - |
| `Kay_Jump_Air_Kay` (loop) | 1.07 | jump (start / air / land / short / long) | 0.06 / 0.10 | no | - | `dash(&"wind", character, dir, 0)` on land (dust) |
| `Kay_Jump_Land_Kay` | 0.67 | jump (start / air / land / short / long) | 0.06 / 0.10 | no | - | `dash(&"wind", character, dir, 0)` on land (dust) |
| `Kay_Jump_Long_Kay` | 2.33 | jump (start / air / land / short / long) | 0.06 / 0.10 | no | - | `dash(&"wind", character, dir, 0)` on land (dust) |
| `Kay_Jump_Short_Kay` | 1.17 | jump (start / air / land / short / long) | 0.06 / 0.10 | no | - | `dash(&"wind", character, dir, 0)` on land (dust) |
| `Kay_Jump_Start_Kay` | 0.60 | jump (start / air / land / short / long) | 0.06 / 0.10 | no | - | `dash(&"wind", character, dir, 0)` on land (dust) |
| `Kay_Run_Kay_A` (loop) | 0.80 | locomotion (alt walk / run set) | 0.20 / 0.20 | no | - | - |
| `Kay_Run_Kay_B` (loop) | 0.80 | locomotion (alt walk / run set) | 0.20 / 0.20 | no | - | - |
| `Kay_Run_Strafe_L` (loop) | 0.80 | strafe run (lock-on) | 0.15 / 0.15 | no | - | - |
| `Kay_Run_Strafe_R` (loop) | 0.80 | strafe run (lock-on) | 0.15 / 0.15 | no | - | - |
| `Kay_Sneak_Walk` (loop) | 2.13 | crouch / sneak locomotion | 0.20 / 0.20 | no | - | - |
| `Kay_Walk_Back` (loop) | 1.07 | walk backwards | 0.15 / 0.15 | no | - | - |
| `Kay_Walk_Kay_A` (loop) | 1.07 | locomotion (alt walk / run set) | 0.20 / 0.20 | no | - | - |
| `Kay_Walk_Kay_B` (loop) | 1.07 | locomotion (alt walk / run set) | 0.20 / 0.20 | no | - | - |
| `Kay_Walk_Kay_C_Casual` (loop) | 1.60 | locomotion (alt walk / run set) | 0.20 / 0.20 | no | - | - |

### kaykit_ranged  (`res://assets/incoming/animations_free2/kaykit_ranged/UAL_Kay_ranged.glb`)

| clip (in-game name) | s | gameplay state | blend in / out (s) | root motion | events (30 fps frame) | ElementFX (elem = element name, e.g. `&"fire"`) |
|---|---:|---|---|---|---|---|
| `Kay_Bow_Aim_Idle` (loop) | 1.83 | bow: idle / aim | 0.15 / 0.15 | no | - | - |
| `Kay_Bow_Draw` | 1.33 | bow: draw / release (release = arrow spawn frame) | 0.08 / 0.15 | no (0.18 m drift) | hit f10 (0.33 s) | `projectile(&"wind", nock_pos, target, 30.0, 0.6)` @f10 (release clips) |
| `Kay_Bow_Draw_Up` | 1.33 | bow: draw / release (release = arrow spawn frame) | 0.08 / 0.15 | no (0.15 m drift) | hit f8 (0.27 s) | `projectile(&"wind", nock_pos, target, 30.0, 0.6)` @f8 (release clips) |
| `Kay_Bow_Idle` (loop) | 1.57 | bow: idle / aim | 0.15 / 0.15 | no | - | - |
| `Kay_Bow_Release` | 1.33 | bow: draw / release (release = arrow spawn frame) | 0.08 / 0.15 | no | hit f2 (0.07 s) | `projectile(&"wind", nock_pos, target, 30.0, 0.6)` @f2 (release clips) |
| `Kay_Bow_Release_Up` | 1.37 | bow: draw / release (release = arrow spawn frame) | 0.08 / 0.15 | no (0.07 m drift) | hit f7 (0.23 s) | `projectile(&"wind", nock_pos, target, 30.0, 0.6)` @f7 (release clips) |
| `Kay_Pistol_Aim` (loop) | 1.07 | gun: aim | 0.12 / 0.12 | no (0.20 m drift) | - | - |
| `Kay_Pistol_Reload` | 1.17 | gun: reload | 0.10 / 0.15 | no | - | - |
| `Kay_Pistol_Shoot` | 1.07 | gun: shoot (muzzle flash at the recoil frame) | 0.03 / 0.10 | no | hit f8 (0.27 s) | `hit_sparks(&"fire", muzzle_pos, dir, 0.5)` @f8 |
| `Kay_Rifle_Aim` (loop) | 1.60 | gun: aim | 0.12 / 0.12 | no | - | - |
| `Kay_Rifle_Reload` | 1.60 | gun: reload | 0.10 / 0.15 | no | - | - |
| `Kay_Rifle_Shoot` | 1.07 | gun: shoot (muzzle flash at the recoil frame) | 0.03 / 0.10 | no | hit f10 (0.33 s) | `hit_sparks(&"fire", muzzle_pos, dir, 0.5)` @f10 |
| `Kay_Run_Holding_Bow` (loop) | 0.80 | run holding ranged weapon | 0.15 / 0.15 | no | - | - |
| `Kay_Run_Holding_Rifle` (loop) | 0.80 | run holding ranged weapon | 0.15 / 0.15 | no | - | - |

### kaykit_undead  (`res://assets/incoming/animations_free2/kaykit_undead/UAL_Kay_undead.glb`)

| clip (in-game name) | s | gameplay state | blend in / out (s) | root motion | events (30 fps frame) | ElementFX (elem = element name, e.g. `&"fire"`) |
|---|---:|---|---|---|---|---|
| `Kay_Undead_Awaken_Stand` | 1.00 | undead: awaken / resurrect (needs a ground clamp, big root travel) | 0.05 / 0.20 | **yes**, 1.4 m | - | `play(&"dark", &"aura", pos)` @f0 |
| `Kay_Undead_Collapse` | 2.00 | undead: collapse (death) | 0.08 / 0.00 | **yes**, 4.7 m | hit f0; on ground from f38 (1.27 s) | `play(&"dark", &"impact", pos)` @f0 |
| `Kay_Undead_Idle` (loop) | 4.27 | undead: idle | 0.25 / 0.25 | no | - | - |
| `Kay_Undead_Resurrect` | 2.70 | undead: awaken / resurrect (needs a ground clamp, big root travel) | 0.05 / 0.20 | **yes**, 5.7 m | - | `play(&"dark", &"aura", pos)` @f0 |
| `Kay_Undead_Taunt` | 1.03 | undead: taunt / aggro | 0.10 / 0.20 | no | - | - |
| `Kay_Undead_Taunt_Long` | 3.00 | undead: taunt / aggro | 0.10 / 0.20 | no | - | - |
| `Kay_Undead_Walk` (loop) | 1.60 | undead: walk | 0.20 / 0.20 | no | - | - |

### traversal_authored  (`res://assets/incoming/animations_free2/traversal_authored/UAL_Authored_Traversal.glb`)

| clip (in-game name) | s | gameplay state | blend in / out (s) | root motion | events (30 fps frame) | ElementFX (elem = element name, e.g. `&"fire"`) |
|---|---:|---|---|---|---|---|
| `Ladder_Climb_Down` (loop) | 1.20 | climb ladder (loop while the input is held) | 0.15 / 0.15 | **yes**, 0.6 m | - | - |
| `Ladder_Climb_Up` (loop) | 1.20 | climb ladder (loop while the input is held) | 0.15 / 0.15 | **yes**, 0.6 m | - | - |
| `Ledge_Hang_Idle` (loop) | 2.00 | hang from ledge | 0.10 / 0.15 | no | - | - |
| `Ledge_Shimmy_L` (loop) | 1.00 | shimmy along ledge (loop) | 0.10 / 0.10 | **yes**, 0.5 m | - | - |
| `Ledge_Shimmy_R` (loop) | 1.00 | shimmy along ledge (loop) | 0.10 / 0.10 | **yes**, 0.5 m | - | - |
| `Ride_Gallop` (loop) | 0.53 | riding: gait | 0.20 / 0.20 | no | - | - |
| `Ride_Idle` (loop) | 2.00 | riding: idle | 0.20 / 0.20 | no | - | - |
| `Ride_Lean_L` (loop) | 1.00 | riding: lean pose (additive-style hold, blend by steering) | 0.20 / 0.20 | no | - | - |
| `Ride_Lean_R` (loop) | 1.00 | riding: lean pose (additive-style hold, blend by steering) | 0.20 / 0.20 | no | - | - |
| `Ride_Trot` (loop) | 0.67 | riding: gait | 0.20 / 0.20 | no | - | - |
| `Ride_Walk` (loop) | 1.20 | riding: gait | 0.20 / 0.20 | no | - | - |
| `Vault_Low` | 1.40 | vault over a low obstacle (root motion) | 0.10 / 0.15 | **yes**, 2.7 m | - | `dash(&"wind", character, dir, 0)` on landing (dust) |
| `Wall_Climb_Up` (loop) | 1.40 | climb wall (loop) | 0.15 / 0.15 | **yes**, 0.5 m | - | - |

Total: 207 clips.

## 4. Renamed / removed clips (search your code for the old names)

| old name | now |
|---|---|
| `MA_Punch_Heavy_R_A/B/C/D/E/Body`, `MA_Punch_Heavy_L_A/B/C/D` | `MA_Punch_Hook_*` (same suffixes; they are hooks, not uppercuts) |
| `MA_Combo_HeavyJab`, `MA_Combo_HeavyHeavy`, `MA_Combo_HeavyStraight` | `MA_Combo_HookJab`, `MA_Combo_HookHook`, `MA_Combo_HookStraight` |
| `Kay_Work_Chop_Tree_Loop`, `Kay_Work_Dig_Loop`, `Kay_Work_Mine_Loop`, `Kay_Work_Hammer_Loop`, `Kay_Work_Saw_Loop`, `Kay_Lockpick_Loop`, `Kay_Work_Bench_A/B/C_Loop` | `Kay_Work_*_Repeat_Loop` (in game `Kay_Work_*_Repeat`); the plain `Kay_Work_*` one-shots are unchanged |
| removed: `MA_Punch_Cross_R_Body`, `MA_Combo_BodyHeadHead`, `MA_Combo_HeavyStraightHeavy`, `MA_Combo_StraightHeavy`, `MA_Combo_Flurry_5Hit`, `MA_Combo_Flurry_Long`, `MA_Combo_PunchKick`, `Kay_Death_Fall_A` | use `MA_Punch_Cross_R_Head_C`, `MA_Combo_JabCross`, `MA_Combo_HookHook`, `Kay_Death_Fall_B` (or the UAL `Death_*`) instead |
| trimmed (same name, shorter): `MA_Punch_Cross_R_Head_A/B`, `MA_Punch_Cross_L_Head`, `MA_Combo_JabCross(+_Southpaw)`, `MA_Combo_StraightStraight`, `MA_Combo_Hook*`, `Cast_Push_Palm_B`, `Kay_Death_Fall_B`, `Kay_Attack_2H_Spin_Long` | frame numbers in the tables are for the trimmed clips |

## 5. Cautions per clip family

* **Weapon clips (`Weapon_*`, KayKit)**: reviewed without a weapon in the hand. The hit frame is the hand's peak reach; the blade tip peaks about 1-2 frames later, so spawn the slash arc at the listed frame and keep the damage window 0.05 s either side.
  `Weapon_1H_Chop` and `Weapon_1H_Slice_*` have compressed arcs (the hand stays close to the chest), attach the sword and check before shipping.
* **Boxing takes (`MA_Punch_*`, `MA_Combo_*`)**: the torso yaws up to 90 degrees during the wind-up, so the visible hit frame comes right after a fast turn; rotate the character toward the target before the wind-up starts. Foot slide of a few cm in `MA_Combo_CrossCross`
  (0.67-0.73 s): pin the feet with foot IK if it shows.
* **Dodges (`Kay_Dodge_*`)**: 0.4 s bursts that end mid-motion (no recovery in the source); play them, then blend to idle over 0.15 s. The travel is on the `root` track only (1.0 m L/R, 1.2 m back, 0.5 m forward).
* **`Kay_Death_Fall_B`**: root travel 0.8 m, body on the ground from frame 49; hand over to a ragdoll or freeze on the last frame. `Kay_Undead_Collapse` (4.7 m of root travel), `Kay_Undead_Resurrect` (5.7 m) and `Kay_Undead_Awaken_*` need a ground clamp; do not use their root track.
* **Traversal (`Ladder_*`, `Wall_Climb_Up`, `Ledge_*`, `Vault_Low`, `Ride_*`)**: hand-authored placeholders. Ladder: rail plane 0.30 m in front of the root, rungs every 0.3 m (feet land on rungs 0.3 / 0.6 m, hands on 1.8 / 2.1 m at the start of a cycle, +0.6 m per cycle), so place the character with its root at a rung height that is a multiple of 0.6 m
  (the root track supplies the +0.6 m rise per 1.2 s loop). Ledge top 2.12 m above the root and 0.24 m in front; vault obstacle 0.92 m tall starting 0.9 m ahead; horse saddle top about 1.12 m.
* **Job loops (`Kay_Work_*_Repeat`)**: hit frames are only listed where a clear strike was measured (chop, dig, mine); for hammer / saw / bench clips spawn effects on a timer inside the loop.
* Kicks, defense, acrobatics, reactions and casting were not re-read in round 3, the events come from the measurements only; sample `docs/anim/free_library/frames/` for what was checked visually.

## 6. Tools

```
godot --path kingdom -s tools/anim/measure_events.gd -- --glb=res://assets/incoming/animations_free/weapons/UAL_Free_Weapons.glb --json=out.json [--limbs=feet|all] [--paths]
python kingdom/tools/anim/build_handoff.py <dir with the json files> tables.md          # regenerates the tables above
python kingdom/tools/anim/glb_edit_clips.py edit <glb> <edits.json>                       # trim / rename / delete clips (+ sidecar), pelvis_untravel
python kingdom/tools/anim/glb_edit_clips.py audit <glb...>                                # pelvis offsets and root travel per clip
```

## Polish pass 2026-09-29 (READ THIS: renames, deletions, new clips)
Full per-clip tables: [polish_review.md](polish_review.md) (kicks, defense, acrobatics, reactions, KayKit libraries, traversal) and [polish_casting.md](polish_casting.md) (16 new casting clips, ElementFX timings, UAL_FILES line).
- **Renamed:** `Kay_Crouch_Idle_Loop` -> `Kay_Crouch_Walk_Loop` (animations_free2/kaykit_movement_ext).
- **Deleted (rows above removed):** `MA_Acro_Cartwheel_E`, `MA_Acro_Flip_A`, `MA_Acro_FrontHandFlip_A`, `MA_Acro_MonkeyBackflip`, `Kay_Undead_Awaken_Floor`, `Kay_Undead_Rise_Ground`.
- **New:** `Cast_<Fire|Water|Earth|Wind|Lightning|Ice|Light|Dark>_Charge` / `_Release` in `animations_free/casting/UAL_Free_CastingElements.glb`; `Vault_Low_B` (mirrored vault) in the traversal library.
- **Casting v2 (2026-09-29, evening; replaces the v1 casting clips, READ THIS if you already wired the v1 release frames):** owner review said the v1 casts looked like punches. All 16 `Cast_<El>_Charge` / `_Release` clips were rebuilt (same names) with anticipation, hold, snap, overshoot, follow-through, a hip-led twist + step and per-element personality (fire two-hand thrust, water S-wave, earth stomp + lift, wind spin, lightning sky call + point, ice X guard + stop-push, light rising open-arm blessing, dark claw pull + burst). Two shared clips were added to the same GLB: `Cast_AoE_Slam` (leap + ground slam) and `Cast_Channel_Beam` (loop; braced lunge with strain vibration).
  **New release frames (30 fps):** fire 17, water 18, earth 18 (stomp; lift peak f36), wind 15, lightning 19 (sky call f9), ice 17, light 23, dark 27, `Cast_AoE_Slam` 27 (ground contact). The old values (9-17) are wrong now. Clip lengths: fire 1.60 s, water 1.87, earth 2.27, wind 1.73, lightning 1.60, ice 1.67, light 2.13, dark 1.93, AoE slam 2.20; charges 1.2-1.6 s. The release frame and every extra event are also stored per clip in `UAL_Free_CastingElements.glb.clips.json` (`release_frame`, `events`). Release frame 0 == Charge frame 0 (blend 0.05 s). The paste-ready state table, ElementFX calls, spawn positions and blend times are in [polish_casting.md](polish_casting.md); sheets in `frames/casting_elements_v2/`; source survey (why no free spellcast clip was used as a base) in the same file.
- **Rebuilt:** all 13 traversal clips (Vault_Low now has run-up, palm plants on the box, arc, landing; ladder hand rungs now at 1.5 / 1.8 m, ledge-hang pelvis at 1.125 m). Kicks / defense / acrobatics / reactions / KayKit libraries got floor, foot-pin and knee fixes (per-clip notes in polish_review.md).
- **Import hygiene:** `UAL_Free_Weapons.glb` and `UAL_Free_CastingKaykit.glb` had stale `valid=false` imports (they never loaded); fixed. `python kingdom/tools/anim/check_unique_clips.py` guards duplicate / `_loop`-suffix clip names.
- **Creatures:** Stagborn elk/Warden clips re-exported (walk hooves pinned: elk 1.21 m/s, Warden 1.24 m/s; see stagborn_README.md). Farm cows/chickens: graze reaches the ground, chicken wings have 4 bones each (11 -> 17 bones per chicken); clip names unchanged.


## Locomotion transitions + jump set 2026-09-29 (NEW LIBRARY, wire it: P5 + P7)
Library `kingdom/assets/incoming/animations_free2/loco_transitions/UAL_Loco_Transitions.glb` (20 clips, 30 fps) + `.contacts.json` sidecar (foot contact frames, root speeds, yaw curves, loop hand-off phases, events).
Contract with exact names, durations, blend times, rates: `docs/anim/patches/P5_locomotion_transitions.md`. Jump design (input, gravity, coyote, landing states, dust hooks, camera): `docs/anim/patches/P7_jump.md`.
Sheets: `docs/anim/free_library/frames/locomotion_v1/<clip>/`. Rebuild and method: `kingdom/tools/anim/loco/README.md`. Godot check: `tools/anim/loco/verify_loco.gd`.
**Register this library BEFORE UAL1 in `Assets.UAL_FILES`** (UAL1 has its own `Jump_Start`; `_ual_for` keeps the first clip of a name). Godot strips `_Loop`: in-game `Jump_Rise`, `Jump_Fall`.

| Clip | Len s | Root motion | Use | Blend in / out |
|---|---|---|---|---|
| `Loco_WalkStart_F` | 1.27 | 1.56 m fwd, 0.7 -> 1.5 m/s | idle -> walk | 0.06 / 0.15 |
| `Loco_RunStart_F` | 0.63 | 1.87 m, 2.1 -> 3.8 m/s | idle -> run | 0.05 / 0.12 |
| `Loco_RunStop_L` / `_R` | 0.87 / 0.80 | 1.45 / 1.74 m, 3.1 / 3.6 -> 0.5 / 0.9 | stop from run, pick by Jog phase (< 0.5 = L); rate = speed / entry speed -> 0.41 / 0.44 s at 6.5 m/s | 0.06 / 0.20 |
| `Loco_WalkStop` | 1.37 | 0.88 m, 1.1 -> 0.1 | stop from walk; plant frame 27 | 0.05 / 0.20 |
| `Loco_Sprint_Stop_Skid` | 0.90 | 2.65 m, 4.6 -> 1.2 | sprint / dash stop, dust frames 11-20 | 0.05 / 0.20 |
| `Loco_TurnInPlace_90_L/R`, `_180`, `_180_R` | 0.73 / 0.70 / 1.10 / 0.87 | heading on `root` rotation: +80 / -84 / +173 / -160 deg | idle turns (drive yaw from `yaw_curve_deg`) | 0.05 / 0.12-0.15 |
| `Loco_Pivot180_Run_L` / `_R` | 1.23 / 1.37 | backwards 1.13 / 0.64 m, yaw +189 / -182 | reversing out of a run above 3 m/s | 0.05 / 0.12 |
| `Jump_Start` | 0.33 | take-off frame 9 | standing jump anticipation (play at rate 2) | 0.05 / 0.0 |
| `Jump_Rise_Loop` / `Jump_Fall_Loop` | 0.80 (loops) | none | air states | 0.08 / 0.12 |
| `Jump_Land_Soft` / `_Hard` | 0.87 / 1.37 | touch-down frame 4 / 6 | knee absorb landings | 0.05 / 0.15 |
| `Jump_Land_Roll` | 1.67 | touch-down 4, roll from 12 | high fall with stick forward | 0.05 / 0.15 |
| `Jump_Running_Start` / `Jump_Land_Running` | 0.40 / 0.77 | take-off frame 12 / touch-down frame 2 | running jump | 0.04 / 0.10 |

Root motion: `root` position = horizontal travel, `root` rotation = heading (turn clips, pivot); this library is NOT in `animations/`, so `_ual_for` does not disable the root track. Decide per clip:
use it (drive the capsule from it) or disable the track and take the numbers from the sidecar. Never both. Foot planted windows per clip (frame ranges) are in `contacts` (`left` / `right`, `flat_*`, `airborne`);
`end_foot` tells which foot is planted last. Slide of planted feet <= 4.5 cm (Land_Hard 6.7). CMU mocap (credit already in CREDITS.md), UAL `Roll` (CC0) inside `Jump_Land_Roll`.


## Combat set 2026-09-30 (NEW LIBRARY `animations/combat/UAL_Combat.glb`, already in `Assets.UAL_FILES`)
Audit, evidence and the full clip table: [../COMBAT_AUDIT.md](../COMBAT_AUDIT.md). Patches: `docs/anim/patches/P9_attack_layering.md` (full-body standing attacks,
A/B attack slots against the OneShot re-fire pop, lunge = authored step), `P10_directional_hit_reactions.md`, `P11_enemy_attack_windup.md`, `P12_hitstop_camera_fov.md`.
- **Timing comes from the markers sidecar**, not from guessed numbers: `CombatMarkers.get_clip(name)` / `time_s(name, "hit", rate)` / `window_s(name, "combo_window", rate)`
  read `res://assets/incoming/animations/combat/combat_markers.json` (110 clips: every authored clip + 66 library attacks, measured by `tools_qa/combat_audit/combat_studio`).
  Keys: `windup_end, hit_start, hits, hit_end, trail_start, trail_end, combo_window, cancel_window, step_in_m, step_frames, contact_on_target` (30 fps frames at rate 1.0).
- **Already applied (local):** player COMBO uses `Sword_Light_1..4_Upper` at 1.2x; `WeaponTrail.attach(body)` + `_trail.swing(clip, rate)` per swing (third person).
- **Every attack also has `<clip>_Upper`** (hip yaw folded into the spine, same blade targets): use `<clip>` full-body when standing, `_Upper` on the upper layer while moving (P9).
- Root motion is in the `root` track (disabled on import like all of `animations/`): move the capsule by `step_in_m` over `step_frames`.
- Paired finishers: victim root 1.2 m in front of the attacker, facing it; both clips start on the same frame.
- Bow: `Bow_Draw` -> `Bow_Hold` (loop) -> `Bow_Loose` (arrow spawn f1); aim = Blend3(Hold, Bow_Aim_Down, Bow_Aim_Up) by camera pitch, upper-body filter.
