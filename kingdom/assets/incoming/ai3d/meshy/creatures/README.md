# Creatures (Meshy meshes, rigged and animated)

Mobile-ready monster and creature models. Each creature is one GLB with one skeleton and
named animation clips, plus a `_lod1` GLB with the same skeleton and clips. The files are
real-world scale in metres, origin at the feet, facing -Z in Godot (the glTF forward axis).
Clips are sampled at 30 fps. Textures are embedded JPEG. There is no Draco or meshopt compression.

Budget ("creature"): LOD0 ≤ 15k tris with a 1024 px texture. LOD1 ≤ 5k tris with a 512 px texture.

| Creature | Files | Size | LOD0 / LOD1 tris | Texture | Bones | Clips (seconds) | Rig source | Animation source | Licence |
|---|---|---|---|---|---|---|---|---|---|
| goblin | `goblin.glb`, `goblin_lod1.glb` | 1.1 m tall (T-pose) | 15,000 / 5,000 | 1024 / 512 | 24 | idle 4.0, walk 1.0, run 0.6, attack 1.5 (Right_Hand_Sword_Slash), hit 1.6, death 2.2 | Meshy auto-rig | Meshy (rig walk/run + animate 0, 219, 178, 189) | Meshy paid plan, no attribution |
| orc | `orc.glb`, `orc_lod1.glb` | 2.0 m | 15,000 / 5,000 | 1024 / 512 | 24 | idle 4.0, walk 1.0, run 0.6, attack 2.8 (Attack), attack_charged 7.7 (Charged_Axe_Chop, starts kneeling), hit 1.6, death 2.2 | Meshy auto-rig | Meshy (0, 4, 237, 178, 189) | Meshy paid plan |
| troll | `troll.glb`, `troll_lod1.glb` | 3.0 m | 14,999 / 5,000 | 1024 / 512 | 24 | idle 4.0, walk 1.0, run 0.6, attack 1.8 (Heavy_Hammer_Swing), slam 3.0 (Charged_Ground_Slam), hit 1.6, death 2.2 | Meshy auto-rig | Meshy (0, 128, 127, 178, 189) | Meshy paid plan |
| wolf | `wolf.glb`, `wolf_lod1.glb` | 0.85 m shoulder | 15,000 / 5,000 | 1024 / 512 | 51 (38 deform) | idle 3.3, walk 1.1, run 0.6 (Gallop), attack 1.3, hit 0.7, death 1.1 | Quaternius *Ultimate Animated Animals* `Wolf.gltf`, fitted to the mesh | same Quaternius Wolf clips | mesh: Meshy; rig and clips: CC0 (quaternius.com) |
| boar | `boar.glb`, `boar_lod1.glb` | 0.9 m shoulder | 14,999 / 5,000 | 1024 / 512 | 42 (29 deform) | idle 3.3, walk 1.2, run 0.6 (Gallop), attack 1.0 (Attack_Headbutt), hit 0.7, death 1.0 | Quaternius `Bull.gltf`, fitted | Quaternius Bull clips | Meshy + CC0 |
| bear | `bear.glb`, `bear_lod1.glb` | 1.3 m shoulder | 14,999 / 5,000 | 1024 / 512 | 51 (tail bones non-deforming) | idle 3.3, walk 1.1, run 0.6 (Gallop), attack 1.3, hit 0.7, death 1.1 | Quaternius `Wolf.gltf`, fitted | Quaternius Wolf clips | Meshy + CC0 |
| giant spider | `spider.glb`, `spider_lod1.glb` | 1.5 m leg span | 14,998 / 5,000 | 1024 / 512 | 36 (8 legs × 3 + body/ceph/abdomen, 8 IK-target bones) | idle 2.0, walk 0.8 (IK tetrapod gait), attack 1.1 (rear up and stab), hit 0.5, death 1.5 (legs curl) | procedural (Blender script) | procedural keys, IK baked to FK | Meshy mesh; own work |
| wyvern | `wyvern.glb`, `wyvern_lod1.glb` | 3.0 m tall | 14,999 / 5,000 | 1024 / 512 | 38 (spine, neck, head, 7 tail, legs, arms, 2 wing bones + 3 fingers per side) | idle 2.0, walk 1.1 (IK biped), flap 0.8, attack 1.2 (lunge bite), hit 0.5, death 1.7 | procedural (Blender script) | procedural keys, IK baked to FK | Meshy mesh; own work |
| stagborn elk | `stagborn_elk.glb`, `stagborn_elk_lod1.glb` | 1.25 m withers | 3,668 / 2,000 | 1024 + emissive / 512 | 26 | idle, idle_alt, graze, walk, run, run_charge, attack (antler gore, 1.83 s), attack_butt, hit, death | Quaternius UAA Stag (CC0), customised | Quaternius clips + authored attack and run_charge | CC0; details in `stagborn_README.md` |
| Antlered Warden | `stagborn_warden.glb`, `stagborn_warden_lod1.glb` | 2.0 m withers, 5.0 m with antlers | 5,728 / 4,600 | 1024 + emissive rune mask / 512 | 26 | as the elk plus kick and roar (2.37 s rear-up) | Quaternius UAA Stag (CC0), rebuilt antlers and mane | Quaternius clips (1.25x slower) + authored attack, run_charge, roar | CC0; details in `stagborn_README.md` |

Quaternius licence: CC0 1.0, https://creativecommons.org/publicdomain/zero/1.0/ (the licence file is in
`incoming/quaternius/ultimate-animated-animals/License.txt`). Meshy output is covered by the paid plan, so no attribution is needed.

## How they were made
Scripts are in `tools/meshy/creature_rig/`. Run them with Blender 5.2 headless (`-b --python`).
- **Bipeds** (`merge_biped.py`). Starts from the Meshy rigged GLB and imports every clip GLB onto the one skeleton.
  It drops the stray Hips *scale* keys that Meshy's Idle clip contains (×1.18, which inflated the whole body), scales the rig to the target height, and
  ground-fixes each clip. The fix shifts the Hips so the lower quartile of per-frame foot heights sits at 0. Death is ramped so the body ends lying on the ground.
  The script then decimates to 15k/5k and exports all actions.
- **Quadrupeds** (`fit_quadruped.py`). Imports the Quaternius armature and maps the rest pose onto the Meshy mesh using landmarks
  (feet clusters, shoulder height, body centre-line per slice, and the tail traced along the mesh's own tail).
  The armature object is scaled so that location keys scale with it. Weights come from bone heat on a voxel-remeshed proxy and are transferred to the real mesh (4 influences).
  The root `Body` bone and the IK and pole bones do not deform. Tail rotations are damped to 35%, because the Meshy tails hang down while the donor tails rest horizontally.
- **Spider and wyvern** (`rig_spider.py`, `rig_wyvern.py`). The bones are placed from landmarks, which were read off gridded ortho renders (`ortho_views.py`).
  Weights are nearest-bone-segment weights, with exclusive zones for the abdomen, the cephalothorax, the head and horns, and the wings. Clips are keyed procedurally with IK feet and baked to FK, and then the constraints are removed.
- Previews: `_previews/creatures_lineup.png` (to scale next to `villager_man_a`, 1.75 m) and `_previews/<name>_anim.png`
  (3 walk frames and 3 attack frames). Both are made with `render_sheet.py`.

## Known limitations
- Goblin, orc and troll carry no weapon. The Meshy meshes have empty hands, so the weapon clips swing empty hands. Attach a weapon to the `RightHand` bone in Godot.
- `orc.attack_charged` is long (7.7 s) and starts from a kneel. Use `attack` for the normal swing.
- The troll's `attack` and `slam` push the hands about 0.25–0.35 m below the ground at impact. This is by design of the Meshy clip.
- Quadruped walk and run clips are in place. Their feet were retargeted by proportion, not by IK, so some foot sliding and a few centimetres of ground penetration are possible, mostly in run.
- Spider and wyvern motion is simple procedural keying (readable but not hand-animated). The wyvern's death topples the rig as a whole, and its right wing is modelled folded tighter than the left.
- Meshy's troll texture looks faceted up close (a remesh artefact from Meshy).
- The rigged clip sources are in `../rigged/` (each GLB is about 7–8 MB and repeats the mesh). The Meshy task IDs are in `../tasks.tsv`.
