# AAA mocap wiring + PC wall-contact / ground realism

Branch `claude/anim-aaa`. Brief: `docs/plans/ANIM_AAA_BRIEF.md`.

## What is where

| Piece | File |
|---|---|
| Decision manifest (all 108 staged clips, add / cmp / skip + reason) | `kingdom/data/anim/aaa_clips.json`, built by `kingdom/tools/anim/aaa/build_manifest.py` |
| Loader (copies only the wired clips into the shared per-skeleton library, optional trim) | `kingdom/scripts/actors/aaa_clips.gd`, called from `Assets._ual_for` |
| NPC combat rows / markers | `CombatMoves.BANDIT_ROWS / BRUTE_ROWS / DUEL / NPC_SWINGS`, markers via `tools/anim/aaa/build_markers.py`, soldier use in `scripts/army/soldier_aaa.gd` |
| LivingWorld sit clips | `animations/life/UAL_Life_AAA.glb` + `.life.json` (`tools/anim/aaa/make_life_aaa_sidecar.py`), `LifeLibrary.LIBS`, `data/living_world/smart_objects.json` |
| Wall contact (brace / glance / impact) | `scripts/actors/wall_contact.gd` (config `data/movement/traversal.json` `wall_contact`) |
| Slope lean + slide, edge balance, ledge stop | `scripts/actors/ground_realism.gd` (`slope_slide`, `slope_lean`, `balance`, `ledge_stop`) |
| Arm IK (hand brace) + torso yaw | `ProceduralRig.set_hand_brace`, `set_torso_yaw_offset` |
| Run-vault | `traversal.json` `vault.clip_run` (`Vault_Run`), `Traversal.plan_for` |

## Review sheets (frame sheets, 5 fps, 3 x 2 tiles, the clip played in place on the villager rig)

`review/pNN/sheet_*.png`, made with `kingdom/tools_qa/anim/aaa_review.tscn` (see the decision for each clip in the manifest `why`).
CMP pages put the AAA clip next to the game clip it would replace: p14 (Stagger_Back), p15 (ladder), p20 (march, limp), p21 (limp, drunk).

## Reviewing a clip

```
Godot --path kingdom --rendering-method mobile res://tools_qa/anim/aaa_review.tscn --write-movie out/f.png --fixed-fps 30 --quit-after 75 \
      -- --clips=Combat_Adv:Parry_High_Deflect,GAME:Stagger_Back,LIFE:Life_Walk_Limp [--view=q34|side|front]
tools/qa/video_to_sheets.sh out docs/anim/aaa_wiring/review/pXX 5 3 2 640
```
