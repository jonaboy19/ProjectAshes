# AAA mocap clip packs: sources and licence

Files: `UAL_AAA_*.glb` (one animation library per theme) with a `.clips.json` sidecar each (clip name, length,
the source BVH file and time range, floor/foot fixes). The recipes are `kingdom/tools/anim/cfg_aaa_*.json`.

| Part | Source | Licence |
|---|---|---|
| Motion data | Carnegie Mellon University Graphics Lab Motion Capture Database (mocap.cs.cmu.edu), BVH conversion by Bruce Hahne (cgspeed.com). The `source` field of each clip in `.clips.json` is the BVH it was cut from (for example `002/02_08.bvh`). | Free for research and commercial use worldwide, no restrictions (see `../cmu_mocap/LICENSE` for the verbatim terms and citation request). |
| Rig / skeleton | Quaternius Universal Animation Library (`UAL1_Standard.glb`, Unreal-Godot rig). The CMU clips are retargeted onto this skeleton by `kingdom/tools/anim/retarget_bvh.py`. | CC0 |
| `UAL_AAA_Combat_Weapons` (part) | A few clips come from KayKit Character Animations (Rig_Medium CombatMelee), see `cfg_aaa_combat_weapons.json`. | CC0 |
| Retargeted clips (these GLBs) | Derived work of the two rows above, produced in-house. | Same terms: CMU data free for commercial use, rig CC0. No other third-party content. |

Status: staged, **not wired** into any animation table yet (nothing in `kingdom/scripts` references `animations/aaa`).
Retarget quality has not been checked in game. Some clip names are IP-flavoured (the review in
`PA_plans/ANTIGRAVITY_REVIEW.md`); rename before a public build. The Master / Mythic / Umbrella / bending packs were
deliberately not imported.
