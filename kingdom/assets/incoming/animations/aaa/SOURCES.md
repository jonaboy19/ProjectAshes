# AAA mocap clip packs: sources and licence

Files: `UAL_AAA_*.glb` (one animation library per theme) with a `.clips.json` sidecar each (clip name, length,
the source BVH file and time range, floor/foot fixes). The recipes are `kingdom/tools/anim/cfg_aaa_*.json`.

| Part | Source | Licence |
|---|---|---|
| Motion data | Carnegie Mellon University Graphics Lab Motion Capture Database (mocap.cs.cmu.edu), BVH conversion by Bruce Hahne (cgspeed.com). The `source` field of each clip in `.clips.json` is the BVH it was cut from (for example `002/02_08.bvh`). | Free for research and commercial use worldwide, no restrictions (see `../cmu_mocap/LICENSE` for the verbatim terms and citation request). |
| Rig / skeleton | Quaternius Universal Animation Library (`UAL1_Standard.glb`, Unreal-Godot rig). The CMU clips are retargeted onto this skeleton by `kingdom/tools/anim/retarget_bvh.py`. | CC0 |
| `UAL_AAA_Combat_Weapons` (part) | A few clips come from KayKit Character Animations (Rig_Medium CombatMelee), see `cfg_aaa_combat_weapons.json`. | CC0 |
| Retargeted clips (these GLBs) | Derived work of the two rows above, produced in-house. | Same terms: CMU data free for commercial use, rig CC0. No other third-party content. |

Status: **partly wired** (2026-10-23). `kingdom/data/anim/aaa_clips.json` decides every one of the 108 clips (add / cmp / skip with a
reason, from frame sheets in `docs/anim/aaa_wiring/review/`); only the wired ones are copied into the game's clip library by
`kingdom/scripts/actors/aaa_clips.gd`. The three reviewed sit clips of `UAL_AAA_LivingWorld.glb` also live in
`animations/life/UAL_Life_AAA.glb` (LivingWorld). Four clips whose names collided with existing game clips were renamed `*_Mocap`
(Bow_Draw, Jump_Land_Soft, Ledge_Shimmy_L/R). Licence terms above stay as they are: CMU data (free for commercial use) on the CC0 UAL rig,
a few CC0 KayKit clips in Combat_Weapons. Many pack names do not describe their content (see the manifest `why` fields); some names are
still IP-flavoured, rename before a public build. The Master / Mythic / Umbrella / bending packs were deliberately not imported.
