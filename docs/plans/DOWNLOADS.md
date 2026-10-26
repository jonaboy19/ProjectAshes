# Rising Ashes - free asset downloads (staging)

Downloaded 2026-10-26 with owner approval ("yes download all of them"). All from the official source pages, no accounts, no payments, free option only.
Local staging (NOT in the game repo or any worktree): `C:\Users\Jonna\Documents\ProjectAshes_art_staging\downloads\<pack>\` (zip + `extracted/`).
Rig names below were read from the GLB/glTF JSON (Python) or via Blender 5.2 headless (FBX). Total on disk about 440 MB (C: had 15 GB free afterwards).

## Summary / key findings
- **UAL2 Standard (free) contains 43 clips, not "130+"** (130+ is the paid Pro tier). Its skeleton is **identical to UAL1** (same 65 bones, same names; verified set-equal against `UAL_AAA_Combat_Adv.glb` in the repo), so no retarget is needed. Ships with and without root motion (`_RM`).
- **KayKit is NOT on the UAL rig.** It uses a 23-bone "Rig_Medium / Rig_Large" skeleton (`hips`, `spine`, `chest`, `upperarm.l`, `handslot.l` ...). It needs a bone-name retarget to UAL (Blender Expy Kit or Godot BoneMap); note hip scale 1.336 from the plan. 173 free clips.
- **Quaternius animals use a custom quadruped rig** (`Body/Back/Torso/FrontUpperLeg.L/BackLowerLeg.L/Tail*`, plus IK/pole-target helper bones in the skin). One rig family shared by all 12 animals, with real Walk + Gallop clips.
- **Gaps:** no sheep/pig/chicken gaits anywhere in the CC0 packs. The itch "Farm Animals" pack (Cow, Horse, Llama, Pig, Pug, Sheep, Zebra) has only `Idle` and `Jump` per animal (FBX/Blend/OBJ, no glTF). "Ultimate Animated Animals" has no sheep, pig or chicken (it has Alpaca, Bull, Cow, Deer, Donkey, Fox, Horse x2, Husky, Shiba Inu, Stag, Wolf). Sheep/pig gaits still need a Blender hand-fix or Meshy.
- **Kenney "Foley Sounds" does not exist** (kenney.nl/assets/foley-sounds returns an error page); skipped. Substitutes downloaded: Interface Sounds, Impact Sounds, RPG Audio, UI Audio.
- **CMU licence caveat:** CMU's site says the data is free for use and may be included in commercially-sold products, but **may not be resold directly, even in converted form**. Fine for baked game clips; do not commit raw BVH to a public repo or ship them as a standalone data pack. BVH files were kept out of the game repo.
- **CMU size:** the 7 requested subjects are 339 MB of raw BVH (120 Hz, long takes), over the 200 MB cap. Kept: a compressed zip of all 7 subjects (126 MB) plus extracted subjects 02, 127, 143 (about 35 MB). Subjects 13, 14, 79, 144 are only inside the zip (unzip on demand). Total about 161 MB.

## 1. Quaternius Universal Animation Library 2 (Standard)  -  `quaternius_ual2\`
- Official: https://quaternius.itch.io/universal-animation-library-2 (itch page updated 2026-09-28). Free "Standard" zip `UAL2_Standard.zip`, 17.9 MB (the plan said ~9.7 MB).
- Licence: CC0 1.0 (itch page "CC0 License"; `License.txt` inside: "CC0 1.0 Universal (CC0 1.0) Public Domain Dedication, https://creativecommons.org/publicdomain/zero/1.0/, Models by @Quaternius").
- Files: 3 .glb (UAL2_Standard.glb, UAL2_Standard_RM.glb, Female Mannequin/Mannequin_F.glb), 3 .fbx, 1 .blend, 3 .png (setup screenshots), 3 .txt. 88 MB on disk.
- Rig: **UAL / Quaternius universal humanoid, 65 bones, identical to UAL1**: `root pelvis spine_01 spine_02 spine_03 neck_01 Head clavicle_l/r upperarm_l/r lowerarm_l/r hand_l/r`, finger chains `index|middle|ring|pinky_01..03_(l|r)` + `*_04_leaf_*`, `thumb_01..03_(l|r)` + `thumb_04_leaf_*`, and `thigh_l/r calf_l/r foot_l/r ball_l/r ball_leaf_l/r`. Not Mixamo names.
- Clips (43): A_TPose, Chest_Open, ClimbUp_1m, Consume, Farm_Harvest, Farm_PlantSeed, Farm_Watering, Hit_Knockback, Idle_FoldArms_Loop, Idle_Lantern_Loop, Idle_No_Loop, Idle_Rail_Call, Idle_Rail_Loop, Idle_Shield_Break, Idle_Shield_Loop, Idle_TalkingPhone_Loop, LayToIdle, Melee_Hook(+_Rec), NinjaJump_Idle_Loop/Land/Start, OverhandThrow, Shield_Dash, Shield_OneShot, Slide_Exit/Loop/Start, Sword_Block, Sword_Dash, Sword_Heavy_Combo, Sword_Regular_A/B (+_Rec) /C, Sword_Regular_Combo, TreeChopping_Loop, Walk_Carry_Loop, Yes, Zombie_Idle_Loop, Zombie_Scratch, Zombie_Walk_Fwd_Loop.
- Use: extra clips directly on our UAL skeleton (combos, sword block/dash, shield, farming, tree chopping, carry-walk, slide / ninja-jump, hit knockback, chest open, lantern idle). Use `_RM` only if the runtime wants baked root motion. UAL1 is already in the repo. If the "130+ clips" target still matters, the Pro tier is paid and was NOT downloaded.

## 2. Quaternius animals
### 2a. Ultimate Animated Animals  -  `quaternius_ultimate_animated_animals\`
- Official: https://quaternius.com/packs/ultimateanimatedanimals.html, via its "Just give me the Download" link (Quaternius public Google Drive folder). Only `glTF/`, `License.txt` and `Preview.jpg` were fetched (FBX/OBJ/Blends skipped).
- Licence: CC0 1.0 (`License.txt`: "LowPoly Models by @Quaternius ... CC0 1.0 Universal (CC0 1.0) Public Domain Dedication").
- Files: 12 .gltf (self-contained, embedded buffers), 1 .jpg, 1 .txt; 36 MB.
- Animals: Alpaca, Bull, Cow, Deer, Donkey, Fox, Horse, Horse_White, Husky, ShibaInu, Stag, Wolf.
- Rig: custom Quaternius quadruped, 38-51 bones per animal. Fox: `Body Back Torso Torso2 Torso3 Neck1-3 Head Ear1-4.L/R FrontShoulder/FrontUpperLeg/FrontLowerLeg.L/R BackShoulder/BackLeg/BackUpperLeg/BackLowerLeg.L/R Tail1-8` plus IK helpers `PoleTarget*, IKBackLeg.*, IKFrontLeg.*, FF.*, FFB.*` (these are in the skin joint list; handle on import). Same naming across all 12 (ear/tail counts differ).
- Clips: 12-13 per animal: Idle, Idle_2, Idle_Headlow (Fox/Wolf: Idle_2_HeadLow), Idle_HitReact1/2, Walk, Gallop, Gallop_Jump, Jump_toIdle, Eating, Death, and Attack (Fox/Wolf/Husky/Shiba) or Attack_Headbutt + Attack_Kick (hoofed animals).
- Use: replacement creature gaits (horse/donkey Walk/Gallop, fox, wolf/husky/shiba dogs, deer/stag, cow/bull). Not usable for sheep, pig, chicken.

### 2b. Farm Animals Animated (itch "LowPoly Animated Animals")  -  `quaternius_farm_animals_itch\`
- Official: https://quaternius.itch.io/lowpoly-animated-animals (zip "Farm Animals Animated by Quaternius.zip", 6.6 MB). Licence CC0 (itch page "CC0 License", Creative Commons Zero v1.0). No separate LICENSE file in the zip.
- Files: 7 .fbx, 7 .blend, 7 .obj + 7 .mtl, 1 .gif; 23 MB. Animals: Cow, Horse, Llama, Pig, Pug, Sheep, Zebra.
- Rig: 35-bone Quaternius farm rig (`root Body Hips Torso Back Shoulders Neck Head FrontLeg/FrontUpLeg/FrontLowLeg/FrontFoot.L/R BackLeg/BackUpLeg/BackLowLeg/BackFoot.L/R` + `_end` leaves). Only 2 clips each: `Idle`, `Jump`. No Walk/Run, so it does not fix the sheep/pig gait problem (checked Sheep and Pig).

## 3. KayKit (Kay Lousberg)  -  CC0
Licence text (each `License.txt`): "Creative Commons Zero, CC0 ... free to use in personal, educational and commercial projects ... crediting 'Kay Lousberg, www.kaylousberg.com' is not mandatory".
- **Character Animations 1.1** (`kaykit_character_animations\`): https://kaylousberg.itch.io/kaykit-character-animations, "Free 1.1", 14.9 MB zip (created 2025-10-12). 16 .fbx, 16 .glb, 1 .png, 1 .txt, 3 .url; 56 MB. The 14 animation files are in `Animations/gltf|fbx/Rig_Medium` and `Rig_Large`. Rig: **KayKit 23-bone** `root hips spine chest head upperarm.l/r lowerarm.l/r wrist.l/r hand.l/r handslot.l/r upperleg.l/r lowerleg.l/r foot.l/r toes.l/r` (no fingers, no neck bone; not UAL, not Mixamo). Clips: Rig_Medium 139 (CombatMelee 22, CombatRanged 20, General 15, MovementAdvanced 13, MovementBasic 11, Simulation 14, Special 15, Tools 29) + Rig_Large 34 = 173. Examples: Melee_1H/2H/Dualwield/Unarmed attacks, Melee_Block/Block_Hit, Death_A/B, Hit_A/B, Interact, PickUp, Use_Item, Walking_A/B/C, Running_A/B, Jump_* set. Use: extra combat/interaction clips, after retarget to UAL.
- **Adventurers 2.0 FREE** (`kaykit_adventurers\`): https://kaylousberg.itch.io/kaykit-adventurers, "Free 2.0", 13 MB. 70 .fbx, 8 .glb, 31 .gltf + 31 .bin + 31 .obj/.mtl, 44 .png, 1 .txt; 35 MB. Characters: Barbarian, Knight, Mage, Ranger, Rogue, Rogue_Hooded (+ weapon/prop meshes). Same 23-bone rig (Knight: `root hips spine chest upperarm.l ... handslot.l ... head upperleg.r ...`), with copies of Rig_Medium General + MovementBasic. Use: reference characters/props for combat tests.
- **Skeletons 1.1 FREE** (`kaykit_skeletons\`): https://kaylousberg.itch.io/kaykit-skeletons, "Free 1.1", 7.7 MB (the "(Legacy)" skeleton page was not used). 32 .fbx, 6 .glb, 13 .gltf/.bin/.obj/.mtl, 12 .png, 1 .txt; 25 MB. Characters: Skeleton_Mage, Skeleton_Minion, Skeleton_Rogue, Skeleton_Warrior. Same 23-bone rig (bone order differs), so it shares the KayKit clips directly. Use: undead enemies.

## 4. Kenney (kenney.nl, all CC0)  -  `kenney_<slug>\`
Licence text (each `License.txt`): "Creative Commons Zero, CC0, http://creativecommons.org/publicdomain/zero/1.0/ - You may use these assets in personal and commercial projects. Credit (Kenney or www.kenney.nl) would be nice but is not mandatory."
Sources: https://kenney.nl/assets/<slug>.

| Pack | slug | Files | Disk |
|---|---|---|---|
| UI Pack (RPG Expansion) | ui-pack-rpg-expansion | 90 png, 1 svg | 1 MB |
| UI Pack | ui-pack | 870 png, 434 svg, 6 ogg, fonts | 6 MB |
| Game Icons | game-icons | 425 png, 2 svg | 6 MB |
| RPG Audio | rpg-audio | 52 ogg | 3 MB |
| Impact Sounds | impact-sounds | 130 ogg | 3 MB |
| Interface Sounds | interface-sounds | 100 ogg | 2 MB |
| UI Audio (bonus) | ui-audio | 52 ogg | 1 MB |

- Skipped: "Foley Sounds" (no such Kenney pack; the page returns an error).
- There are no .wav files; these packs ship .ogg, which Godot imports natively.
- Use: UI icons/panels (HUD, inventory) and UI/foley-style SFX (cloth/door/coins in RPG Audio, hits in Impact Sounds, clicks in Interface/UI Audio).

## 5. CMU Graphics Lab Motion Capture (BVH)  -  `cmu_mocap_bvh\`
- Official: http://mocap.cs.cmu.edu/ ("free for all uses"). CMU itself publishes ASF/AMC only; the BVH set is the **cgspeed.com "Motionbuilder-friendly BVH Conversion Release" (Bruce Hahne, 2010 re-release, v1.1, 2010-06-26)**, which the CMU site links from its home and Resources pages. Zips came from the MediaFire links on that cgspeed page: 01-09 (34 MB), 10-14 (67 MB), 76-80 (68 MB), 113-128 (99 MB), 141-144 (67 MB). Only subjects 02, 13, 14, 79, 127, 143, 144 were kept.
- Licence (CMU home page, saved in `CMU_LICENSE_from_site.txt`): "free for use in research projects. You may include this data in commercially-sold products, but you may not resell this data directly, even in converted form." FAQ: "may be copied, modified, or redistributed without permission." Requested acknowledgement: "The data used in this project was obtained from mocap.cs.cmu.edu. The database was created with funding from NSF EIA-0196217." The cgspeed README (`index_files/READMEFIRST.txt`) says free for any purpose.
- Files: 299 .bvh across the 7 subjects (02: 10, 13: 42, 14: 37, 79: 96, 127: 38, 143: 42, 144: 34), all inside `cmu_subjects_02_13_14_79_127_143_144_bvh.zip` (126 MB). Extracted copies kept only for 02, 127, 143. Index files in `index_files/` (READMEFIRST.txt, cmu-mocap-index-text.txt, cmu-mocap-index-spreadsheet.xls). Total 161 MB.
- Subject themes (CMU index): 13/14/79 everyday behaviours and locomotion, 127 action-adventure obstacles/running/jumping/ducking/rolling, 143 general capture, 144 punching.
- Rig: **CMU / MotionBuilder style** (not UAL): `Hips LHipJoint LeftUpLeg LeftLeg LeftFoot LeftToeBase RHipJoint RightUpLeg RightLeg RightFoot RightToeBase LowerBack Spine Spine1 Neck Neck1 Head LeftShoulder LeftArm LeftForeArm LeftHand LeftFingerBase LeftHandIndex1 LThumb` (+ Right*), 31 joints, 120 Hz (Frame Time 0.0083333), frame 1 is an added T-pose. Needs retargeting (Blender Expy Kit / BoneMap) to UAL.
- Use: retarget sources for missing locomotion/obstacle/combat motions.

## What each pack is for (from docs/plans/AAA_FINISH_PLAN.md)
UAL2 = extra clips on our skeleton; animals = replacement creature gaits (horse/donkey/fox/dog/wolf/deer/cow); KayKit = extra combat/interaction clips (needs retarget); Kenney = UI icons + UI/foley sounds; CMU = retarget sources.
