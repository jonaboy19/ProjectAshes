# Souls-like combat, magic and interaction clips (Cat Prisbrey, Unlicense)

`UAL_Souls_Cat.glb`: **43 clips, 53.6 s**, retargeted onto the Quaternius **UAL 65-bone
skeleton** (the rig of every humanoid in the game: player, soldiers, villagers). Registered
in `Assets.UAL_FILES`, so `CharacterAnimator.play_full("Magic_Cast_L")` / `play_upper(...)`
and `Assets.animation_player(model).play("Parry_Quick")` work on any UAL character.
The file holds a one-triangle skin stub instead of the mannequin (1.3 MB). Details of each
clip are in `UAL_Souls_Cat.glb.clips.json`.

| | |
|---|---|
| Source | https://github.com/catprisbrey/Cats-Godot4-Modular-Souls-like-Template, `MannyAnimations.zip` → `MannyAnimations.blend` (Manny rig, 30 fps) |
| Licence | **Unlicense** (public domain), `LICENSE` copied from the repo. Licence URL: https://github.com/catprisbrey/Cats-Godot4-Modular-Souls-like-Template/blob/main/LICENSE and https://unlicense.org |
| Credit | Not required. We credit "Cat Prisbrey" in CREDITS.md (the author asks nicely) |
| Mixamo check | The author's README says "Nothing from Mixamo". The rig uses Mixamo-style bone *names* (`mixamorig:Hips`, ...) with hand-made actions on an IK/FK control rig. No action is named `mixamo.com`, and none was taken from Mixamo |
| Not taken | the rest of the template (code, models, bow/crossbow/ladder/death clips we already have), `GuardingArm-loop` (arm-only layer) |

Loop clips were authored as loops (`*-loop` in the source) and are imported looping.
All clips are in place: the pelvis keeps its sway, and horizontal travel is on the
optional `root` position track (disabled by `Assets._ual_for`; see `../README.md`).

| clip | s | loop | source action |
|---|---:|---|---|
| `Souls_Light_Attack_1` | 0.67 |  | LiteAtk1 |
| `Souls_Light_Attack_2` | 0.60 |  | LiteATK2 |
| `Souls_Light_Special_1` | 1.50 |  | LiteSpecial2 |
| `Souls_Light_Special_2` | 1.67 |  | LiteSpecial3 |
| `Souls_Heavy_Attack_1` | 1.27 |  | HeavyATK1 |
| `Souls_Heavy_Attack_2` | 1.27 |  | HeavyATK2 |
| `Souls_Heavy_Stab` | 1.83 |  | HeavyStab |
| `Souls_Heavy_Special` | 1.90 |  | HeavySpecial |
| `Souls_Thrust_Attack_1` | 0.67 |  | ThrustATK1 |
| `Souls_Thrust_Attack_2` | 0.97 |  | ThrustATK2 |
| `Souls_Thrust_Special` | 1.33 |  | ThrustSpecial |
| `Souls_Fist_Attack` | 0.80 |  | FistATK1 |
| `Souls_Visceral_Attack` | 2.17 |  | ViseralATK (riposte / finisher) |
| `Magic_Attack_1` | 1.30 |  | MagicAtk1 |
| `Magic_Attack_2` | 1.67 |  | MagicATK2 |
| `Magic_Cast_L` | 1.40 |  | MagicCastL |
| `Magic_Cast_R` | 1.40 |  | MagicCastR |
| `Magic_Casting` | 1.00 | loop | MagicCasting-loop (channel) |
| `Magic_Idle_L` | 1.33 | loop | MagicLIdle-loop |
| `Shield_Bash` | 0.77 |  | ShieldBashBig |
| `Souls_Guard` | 1.87 | loop | Guarding-loop |
| `Souls_Guard_Hit` | 0.50 |  | GuardHit1 |
| `Souls_Guard_Hurt` | 0.70 |  | GuardHurt (guard broken) |
| `Parry_Quick` | 0.50 |  | ParryQuickL |
| `Souls_Roll` | 0.77 |  | Roll |
| `Souls_Fall_Attack_Start` | 0.57 |  | FallingATK |
| `Souls_Fall_Attack` | 0.73 | loop | FallingAtk-loop (plunging) |
| `Souls_Fall_Land` | 0.47 |  | FallLand |
| `Souls_Strafe_L` | 0.50 | loop | StrafeL-loop |
| `Souls_Strafe_R` | 0.50 | loop | StrafeR-loop |
| `Open_Door` | 2.50 |  | OpenDoor |
| `Open_Chest` | 1.30 |  | OpenChest |
| `Open_Gate` | 2.50 |  | OpenGate |
| `Door_Locked` | 1.70 |  | DoorLocked |
| `Lever_Pull_Floor` | 1.43 |  | PullLeverFloor |
| `Lever_Pull_Wall` | 1.33 |  | PullLeverWall |
| `Drink_Potion` | 1.63 |  | Potion |
| `Stand_From_Floor` | 2.00 |  | StandFromFloor |
| `Torch_Idle` | 1.30 | loop | TorchLIdle-loop |
| `Souls_Light_Idle` | 1.33 | loop | Lite-Idle-loop |
| `Souls_Heavy_Idle` | 1.33 | loop | HeavyIdle-loop |
| `Souls_Thrust_Idle` | 1.33 | loop | ThrustIdle-loop |
| `Souls_Shield_Idle` | 1.33 | loop | ShieldIdle-loop |

Rebuild: `tools/anim/cfg_souls_cat.json` (see `../README.md`).
