# Characters, rigs and animations (incoming)

Everything here is **free for commercial use** (CC0, or MIT for code) and builds on
the **master skeleton already used by the game: the Quaternius UAL skeleton**
(65 bones, UE-mannequin names, `Armature/Skeleton3D`), which the MakeHuman villagers
in `kingdom/assets/generated/characters/` also use with *bit-identical rest
orientations*. All new characters and clips below were converted to that exact
skeleton, so they drop into the existing `Assets._ual_for()` path with **no
BoneMap / retargeting at import**. Verified in Godot 4.6 (headless): every
character below loads with 65 bones, 204 clips, **0 unresolved tracks**, no
exploding bones (see "Verification").

Folders the game does not use yet carry a `.gdignore` (repo convention). Delete the
`.gdignore` of a folder when wiring it in. As of 2026-09-27, `g6-ual/` and `cdmir-ual/`
are wired in (no `.gdignore`); `_library/`, `mesh2motion/` and the `oga-*` sources are
still `.gdignore`d (see `docs/OPEN_SOURCE_AUDIT.md`).

## Previews (look at these first)

| file | what |
|---|---|
| `_previews/characters_sheet.png` | contact sheet of every candidate pack in the repo + new ones, 3/4 view, each scaled to ~1.75 m, tri counts; first two tiles are the accepted MakeHuman villagers (REF) |
| `_previews/scale_check_lineup.png` | new NPCs at real heights (1.55-1.78 m) in the UAL idle pose, next to the MakeHuman REF villagers and the Meshy blacksmith (scaled to its in-game 11 m) |
| `_previews/anim_poses_sheet.png` | 32 clips (UAL1, UAL2, Mesh2Motion, CMU mocap, G6) playing on a converted G6 villager |
| `_previews/anim_poses_monk.png`, `anim_poses_old_lady.png` | UAL clips on the re-rigged CDmir monk / old lady (robes, sitting, farming, death) |

## New in this folder

### Ready-to-use (already on the UAL skeleton)

| path | source | licence | tris | textures | notes |
|---|---|---|---:|---|---|
| `g6-ual/g6_m_villager_tunic.glb` | System G6 "Modular RPG Characters" | CC0 | 2,794 | 512-1024 px, 5 mats | villager / farmer / trader |
| `g6-ual/g6_m_blacksmith_apron.glb` | " | CC0 | 2,954 | " | blacksmith (leather apron, beard) |
| `g6-ual/g6_m_worker_apron.glb` | " | CC0 | 2,898 | " | innkeeper / worker (cloth apron, grey hair) |
| `g6-ual/g6_m_hunter_leather.glb` | " | CC0 | 3,268 | " | hunter / ranger / militia |
| `g6-ual/g6_f_villager_tunic.glb` | " | CC0 | 2,800 | " | villager woman |
| `g6-ual/g6_f_blacksmith_apron.glb` | " | CC0 | 3,076 | " | smith's wife / tanner |
| `g6-ual/g6_f_worker_apron.glb` | " | CC0 | 3,132 | " | innkeeper / maid / market woman |
| `g6-ual/g6_f_hunter_leather.glb` | " | CC0 | 3,516 | " | huntress |
| `g6-ual/g6_m_modular_all.glb`, `g6_f_modular_all.glb` | " | CC0 | 15,394 / 13,972 *(all parts; show 4-5 at a time = ~3k)* | " | **customisation kit**: 6 male heads, 6 male hairs (3+3 female), 4 tunics/aprons, boots, gloves, helmets, medium leather set; hide/show meshes by name (`human_male_head_3`, `human_male_hair_5`, `human_male_light_armor_2`, ...) |
| `cdmir-ual/cdmir_monk.glb` | CDmir "Monk" (Kelgar) | CC0 | 3,942 | 1024 px | monk / priest / healer; robe deforms well when sitting |
| `cdmir-ual/cdmir_old_lady.glb` | CDmir "Old Lady" (Kelgar) | CC0 | 3,994 | 2048 -> 1024 px | elder / herbalist / healer |

All are normalised like the MakeHuman GLBs: **hip height = UAL hip height
(0.932 model units)**, so scale by the head bone the way `Assets.humanoid()` /
`mh_character()` do. Natural heights to request: men 1.72-1.78 m, women
1.62-1.65 m, old lady 1.55 m, monk 1.72 m. Skin textures were warmed and the
white leg wraps recoloured brown (`tint_images` in the configs) so they sit next
to the MakeHuman villagers and the Meshy buildings (see the lineup).

### Extra animation libraries (UAL skeleton, retargeted)

Append any of these to `Assets.UAL_FILES` (they contain the UAL armature + the
UAL mannequin mesh, exactly like `UAL1_Standard.glb`, so Godot builds a
`Skeleton3D` and `_ual_for()` rewrites the track paths the same way). Clip names
ending in `_Loop` are imported as looping by Godot (the suffix is stripped).
No names collide with UAL1/UAL2.

| file | clips | source / licence | contents |
|---|---:|---|---|
| `_library/UAL_Extra_Mesh2Motion.glb` | 58 | Mesh2Motion, CC0 | **bow** (`Bow`, `Bow_Pull_Back`, `Bow_Pull_Hold`, `Bow_Release`), **climb** (`Climb_Ladder`, `Ladder_Idle`, `Climb_Wall`, `Ledge_Hang`, `Pipe_Climb`), **dodges** (`Dodge_back/left/right`), **deaths** (`Death_A/B/C`), `Defend`, `Fighting_Idle`, jabs, `Strafe_left/right`, `Walk_Backwards`, `Walk_Stealth`, `Run_Stealth`, `Crawl`, `Walk_Female`, `Run_Female`, `Walk_Large`, social (`Greeting`, `Head_Nod`, `Reject`, `Angry`, `Confused`, `Victory`, `Idle_Listening`, `Idle_Subtle`, `Idle_Hurt`, `Tired_Hunched`, `Kneeling_Tired`, `Shivering`, `Dizzy`), `Sleeping`, `Meditate`, `Consume_Item`, `Throw_Object`, `Jump_2`, `Run_Jump`, `Land_Three_Point`, `Backflip`, `Sword_Attack_Air_Vertical`, `Attack_Ground_Pound`, dances, `Pushup`, `Jumping_Jacks`, `Glide` |
| `_library/UAL_Extra_Mocap.glb` | 14 | Mesh2Motion (CMU mocap derived), CC0 | `Salute`, `Cheer_One_arm`, `Cheering_Two_Hands`, `Help_One_Arm/Two_Arms`, `Insult`, `Kick_Breach`, **fishing** (`Fishing_Cast/Reel/Catch`), **turn in place** (`Turn_Left/Right_90/180`) |
| `_library/UAL_Extra_G6_male.glb` | 47 | System G6, CC0 | prefix `G6_`: combat idles + attacks + channel loops for **two-handed melee (5 attacks)**, **dual wield (4)**, **main-hand melee (3)**, **off-hand shield bash**, **bow (2)**, **crossbow**, **staff**, **wand**, unarmed magic; `G6_death`, `G6_drink_potion`, `G6_gathering`, `G6_pray`, `G6_power_up`, `G6_jump`, `G6_run`. Stylised, short (10-20 frames at 24 fps) - good for NPC combat and quick player attacks |
| `_library/UAL_Extra_G6_female.glb` | 47 | System G6, CC0 | same clips from the female rig (same names; load only one of the two) |
| `_library/UAL_Extra_100STYLE.glb` | 14 | 100STYLE dataset (Mason/Starke/Komura, Univ. of Edinburgh), **CC BY 4.0** (retarget rig by Daniel Holden) | prefix `Style_`: **locomotion variety UAL doesn't have** — `Style_Neutral_Walk_Loop`, `Style_Neutral_Run_Loop`, `Style_Neutral_WalkBack_Loop` (backward), `Style_Neutral_Strafe_Loop` (sideways), `Style_Rushed_Sprint_Loop` (a faster gait than UAL's own Sprint), `Style_Walk_Start` / `Style_Walk_Stop` (non-looping accel/decel transitions), `Style_Turn_InPlace` (non-looping pivot), `Style_Guard_March_Loop` (stiff formal march, good for patrols), `Style_Old_Walk_Loop` (elderly NPCs), `Style_Wounded_Walk_Loop` (limping, low-health), `Style_Sneak_Walk_Loop` (crouched creep, complements `Walk_Stealth`), `Style_Shielded_Walk_Loop` (guarded stance, shield-carrying), `Style_Unarmed_Punch_Idle_Loop`. **CC BY 4.0: credit required, see `kingdom/CREDITS.md`.** Only BVH motion channels were used — the "Geno" mesh in the same source repo is marked non-commercial-research-only and was never downloaded. Each clip is a short window (~2-3 s at 60 fps source, resampled) hand-picked from the much longer raw takes (the full BVH set is 4.6 GB; only ~437 MB of relevant style/direction files were fetched via HTTP range requests against the archive's central directory, and only these 14 trimmed clips were kept — the rest was discarded, not committed). |

Total with the existing UAL1 + UAL2 Standard: **218 clips on one skeleton** (204 + 14 Style_ clips). Note: separately, `kingdom/assets/incoming/animations/` (souls_cat + cmu_mocap, see its own README) already adds combat blocks/parries/combos, knockdown get-ups, karate, swimming and chores — this 100STYLE set fills the different gap of **directional/styled locomotion** (turns, pivots, strafes, start/stop, character-specific gaits), which neither of those covers.

### Raw sources (kept for re-running the tools)

| path | what | licence URL |
|---|---|---|
| `mesh2motion/` | `human-base/addon/mocap-animations.glb`, `horse-animations.glb` (**horse mesh 3.4k tris + 14 clips**: Walk, Trot, Run, Idle, Eating, Rear, Kick, Death, Sleep, turns...), `rig-human.glb`, `rig-horse.glb`, `model-human.glb` | https://github.com/Mesh2Motion/mesh2motion-app (LICENSE-CC0.MD, LICENSE-MIT.MD copied) |
| `oga-system-g6-modular-rpg/` | male/female `.blend` (all parts, 45 clips each, textures) + IK rig | https://opengameart.org/content/modular-rpg-characters (CC0) |
| `oga-cdmir-kelgar/` | `MONK_1.blend`, `oldlady-v2.blend` (textures packed) | https://opengameart.org/content/monk , https://opengameart.org/content/old-lady (CC0) |

Credits (all optional, CC0): System G6 (Qoma); CDmir with TinyWorlds; Mesh2Motion
(Scott Petrovic); CMU Graphics Lab Motion Capture Database; Quaternius.
**No CC-BY items were added, so no mandatory credit lines.**

## Candidate ranking (style fit vs `docs/art_reference/village_target_1.png`)

Judged on the contact sheet and the lineup. Target = stylised, hand-painted,
natural-proportion medieval villagers.

1. **MakeHuman villagers** (`generated/characters/`, already in the game) - the
   base. Realistic-clean, shared atlas, 4.8-6.2k tris.
2. **G6 modular villagers (new, converted)** - painted tunics, leather/cloth
   aprons, laced boots; natural proportions that match MakeHuman; 2.8-3.5k tris.
   Best source for **blacksmith, innkeeper, farmer, trader, hunter** and for
   **player customisation** (heads/hairs/outfits). 
3. **CDmir monk and old lady (new, converted)** - painted, realistic; fill the
   **healer / priest / elder** roles; ~4k tris.
4. Styloo "The Company" (CC0, already in repo) - painted but heroic/chibi-leaning
   (big hands, long faces); OK for a wizard or dwarf NPC; not converted.
5. Quaternius Universal Base Characters + Fantasy outfits (used by the current
   `humanoid()` path) - PBR, fits, but heavy: body+outfit+hair = **29-42k tris**
   before the game's body trimming; keep only for the player if needed and
   decimate the outfits.
6. Quaternius Ultimate Modular Men/Women, RPG Characters - flat-colour low-poly;
   readable, but a different (untextured) look next to the painted buildings.
7. Reject for village NPCs (toy/chibi proportions): Ultimate Animated Character,
   KayKit Adventurers, Creatus Knight Pack, Kenney Mini Characters,
   Quaternius Animated Knight/Men/Women (modern clothes).

## Recommendation

* **Skeleton:** keep UAL as the only skeleton. Every body and clip here is
  already on it; no BoneMap needed. If a future pack must be retargeted at
  import instead, use Godot's import dialog: *Skeleton3D -> Retarget ->
  Bone Map* with `SkeletonProfileHumanoid`; UAL/UE names map 1:1 (`pelvis ->
  Hips`, `spine_01/02/03 -> Spine/Chest/UpperChest`, `neck_01 -> Neck`,
  `Head -> Head`, `clavicle_l -> LeftShoulder`, `upperarm_l -> LeftUpperArm`,
  `lowerarm_l -> LeftLowerArm`, `hand_l -> LeftHand`, `thigh_l -> LeftUpperLeg`,
  `calf_l -> LeftLowerLeg`, `foot_l -> LeftFoot`, `ball_l -> LeftToes`, fingers
  `index/middle/ring/pinky_01..03_l -> Left<Finger>Proximal/Intermediate/Distal`, `thumb_01..03_l -> LeftThumbMetacarpal/Proximal/Distal`, `root -> Root`),
  enable *Rest Fixer -> Overwrite Axis* and *Fix Silhouette*, and export the
  animations as a library. The Blender tool `_tools/retarget_to_ual.py` does
  the same offline and is what produced `_library/`.
* **Player:** `generated/characters/player_young.glb` (MakeHuman, 5.3k tris) as
  the body; for customisation use the G6 modular kit as the model (swap
  head/hair/outfit meshes on the same skeleton) or add MakeHuman outfit variants.
  Player budget 15k leaves room for armor from `incoming/armor/`.
* **NPCs:** MakeHuman villagers + the 8 G6 variants + monk + old lady = **22
  distinct NPC bodies**, all 2.8-6.2k tris, one skeleton, one clip library.
  Mix hair/head textures on the G6 modular kit for more variety.
* **Animation set to load:** `UAL1_Standard`, `UAL2_Standard`,
  `UAL_Extra_Mesh2Motion`, `UAL_Extra_Mocap`, `UAL_Extra_G6_male`.
  Suggested aliases: bow -> `Bow_Pull_Back`/`Bow_Release`; crossbow ->
  `G6_idle_combat_two_handed_crossbow`/`G6_cast_two_handed_crossbow`;
  two-handed -> `G6_idle_combat_two_handed_melee`, `G6_cast_two_handed_melee[_2.._5]`;
  dodge -> `Dodge_left/right/back`; deaths -> `Death01`, `Death_A/B/C`, `G6_death`;
  climb -> `Climb_Ladder`, `ClimbUp_1m`, `Ledge_Hang`; work -> `TreeChopping`,
  `Farm_Harvest/PlantSeed/Watering`, `Fixing_Kneeling` (kneeling repair work),
  `Walk_Carry`, `PickUp_Table`, `G6_gathering`, `Fishing_*`; social ->
  `Idle_Talking`, `Greeting`, `Head_Nod`, `Salute`, `Sitting_Talking`.
* **LOD:** G6/CDmir are already under NPC budget; Godot's auto-LOD
  (`meshes/generate_lods=true`) covers distance; hand over to the existing
  impostor sprites at 45 m. For crowds, a 40 % decimated LOD1 can be made
  the same way as the MakeHuman `_lod1` files.

## Verification

* **Rest orientation:** `_tools/compare_rest.py` UAL1 vs `g6_m_villager_tunic.glb`:
  0.00 deg on every bone (only joint positions differ, as intended).
* **Godot 4.6 headless** (scratch project, same track-path rewrite as
  `Assets._ual_for`, all 5 libraries):
  `villager_man_a / g6_m_villager_tunic / g6_f_worker_apron / cdmir_monk /
  cdmir_old_lady`: 65 bones, 204 clips (80 looping), 0 unresolved tracks,
  max bone distance from root 1.45-1.56 model units while playing Walk, Sit,
  Sword, Bow, Climb, Salute, G6 two-handed, Death (no explosions).
* **Visual:** `_previews/anim_poses_*.png` (Blender EEVEE).

## Tools (`_tools/`, Blender 5.2 headless)

| script | does |
|---|---|
| `inspect.py` | tris, bones, actions, textures, height of any GLB/FBX/blend -> `stats.jsonl` |
| `retarget_to_ual.py` + `cfg_*.json` | bake clips from any humanoid rig onto the exact UAL rest (direction-matched rest, world-space deltas, hip-height scaled pelvis, in place) and export a UAL library GLB |
| `rebind_to_ual.py` + `cfg_g6_rebind_*.json`, `cfg_cdmir_*.json` | re-rig any humanoid mesh onto the UAL skeleton: fit joints, reuse the source weights (`map`, with height-split of single spine/head groups) or Blender bone-heat weights (`auto`, hair forced rigid to `Head`), pose into the UAL T-pose, bake, translate-only bone fit (rest rotations stay UAL), recolour, textures <= 1024, one GLB per variant |
| `autotex.py` | rebuilds image materials for legacy (Blender 2.7x) .blend files |
| `render_tile.py`, `render_all_tiles.sh`, `contact_sheet.ps1` | contact sheet |
| `render_poses.py`, `pose_list.txt` | animation pose sheet on any UAL character |
| `render_lineup.py` | real-height lineup in front of a Meshy building |

## Looked at and rejected

| candidate | why |
|---|---|
| OGA "Adventurer-militia-peasant" (Danimal) | CC-BY-SA 3.0 |
| OGA "Monk animated" (hwoarangmy) | CC-BY-SA 3.0 (we used the CC0 original instead) |
| Mesh2Motion model variants Sophia / Jay / Sintel / Bunny | CC-SA / CC-BY; also not medieval |
| Mesh2Motion elbolilloduro humans, PSX pack | CC0 but modern (police, hazmat...) |
| catprisbrey/Godot4-OpenAnimationLibraries | no licence file; Mixamo bone map (likely Mixamo-derived) |
| kevdev "Human Basic Motions" free | licence not stated on the page |
| rancidmilk "Free Character Animations" (2000 CMU clips) | CMU terms (no resale of the data), rough/jittery; Mesh2Motion already gives cleaned CMU clips as CC0 |
| GDQuest godot-4-3D-Characters | robots/animals, Sophia is CC-BY-SA |
| KayKit Adventurers 2.0 (itch) | CC0, but chunky toy style; v1 already in `kaykit/characters` |
| Quaternius Modular Outfits Fantasy - full 12 outfits | only Peasant + Ranger are free; the rest is the paid Source tier (CC0 once bought, $20) - worth buying for more civilian outfits |
| UAL1/UAL2 "Source" (120+/130+ clips) | paid Patreon tier; the free Standard tiers (43 clips each) are what we have |
| Meshy/Mixamo/Hunyuan3D/Higgsfield/Unreal-only | rules |
| Quaternius "Ultimate Monsters" (50 animated monsters, CC0, quaternius.com/packs/ultimatemonsters.html) | style mismatch: chibi/toy-proportioned cartoon monsters (rounded heads, bright flat colours), clashes with the painterly Meshy creatures already in `ai3d/meshy/creatures/`. Same reason the other "Ultimate"/toy-style Quaternius packs were rejected above |
| GODOT-VFX-LIBRARY (github.com/haowg/GODOT-VFX-LIBRARY, MIT) | 2D `GPUParticles2D`/shader effects for a 2D action game; would need a full rewrite to `GPUParticles3D` to use in this 3D game, out of scope for sourcing |
| kevdev "Human Basic Motions FREE" (knockdown/get-up, stunned, crouch, strafe) | re-checked this session on both the paid and free itch.io pages: still **no licence text anywhere on either page** (confirms the 2026-09-27 finding) |
| Horse **rider** clips (mounted idle/walk/trot/gallop) | searched again this session (web search + itch.io tag browse): still nothing free/CC-licensed in 3D turned up; every free "horse rider" hit is either a 2D sprite pack or a paid FBX bundle. The CMU mocap database (mocap.cs.cmu.edu, confirmed "may be copied, modified, or redistributed without permission") likely has riding-adjacent poses, but it ships as ASF/AMC, which needs a converter this session didn't have time to build. Still recommend authoring `Ride_Idle` / `Ride_Trot` / `Ride_Gallop` by hand on the UAL rig as the practical fallback |

## Open problems

* G6 variants use 5 separate materials (body/head/hands/clothes/hair, 512-1024 px
  each) -> 5 draw calls per NPC; bake them into one atlas (like the MakeHuman
  `CharacterAtlas`) before shipping crowds.
* G6/CDmir heads have no facial bones (same as MakeHuman); eyes are painted.
* Horse riding: no CC0 rider clips were found. Use UAL `Sitting_Idle`/`Driving`
  as the mounted pose (legs need a wider stance) or author a short `Ride_Idle`
  / `Ride_Gallop` pair in Blender on the UAL rig; the Mesh2Motion horse
  (`mesh2motion/horse-animations.glb`, 3.4k tris, Walk/Trot/Run) and the
  Quaternius animated horse can carry the rider via a BoneAttachment3D.
* Swim/climb: UAL1 has `Swim_Fwd/Swim_Idle`; climbing comes from Mesh2Motion
  (`Climb_Ladder`, `Climb_Wall`, `Ledge_Hang`) and UAL2 (`ClimbUp_1m`); no
  ledge shimmy.
* G6 combat clips are short and snappy (10-20 frames at 24 fps); they read well
  at game distance but may need blending times of 0.1-0.15 s.
* The `modular_all` kits keep every part in one file (14-15k tris); only enable
  one head/hair/outfit at a time (or split into per-part GLBs if memory matters).
* Long robes/dresses (monk, old lady) use bone-heat weights: fine for
  walk/sit/work; in wide strides (Sprint, Dodge) the hem stretches between the legs.
