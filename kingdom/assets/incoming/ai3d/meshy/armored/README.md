# Armored humanoids (Meshy, rebound to the UAL skeleton)

Six armored characters generated with Meshy (image-to-3d, meshy-7, T-pose, textured), remeshed by
Meshy to about 12k triangles, then **re-rigged in Blender onto the game's Quaternius UAL skeleton**
(65 bones, with rest orientations bit-identical to UAL1 and the MakeHuman, G6 and CDmir characters). They do **not** use
Meshy's own rig. That means every UAL, UAL2, Mesh2Motion, Mocap and G6 clip plays on them through the existing
`Assets._ual_for()` path with no BoneMap.

**Licence:** Meshy paid-plan output. Commercial use is OK and no attribution is needed.

| file | character | height | LOD0 tris / tex | LOD1 tris / tex | `mh_character()` height arg* |
|---|---|---:|---|---|---:|
| `guard.glb`, `guard_lod1.glb` | town guard (kettle hat, gambeson, tabard) | 1.80 m | 11,888 / 1024 | 3,869 / 512 | 1.625 |
| `knight.glb`, `knight_lod1.glb` | knight (plate, visored helm, tabard, cape) | 1.85 m | 11,811 / 1024 | 3,873 / 512 | 1.729 |
| `mercenary.glb`, `mercenary_lod1.glb` | mercenary (nasal helm, mail, lamellar, sidearm) | 1.80 m | 11,886 / 1024 | 3,877 / 512 | 1.635 |
| `bandit.glb`, `bandit_lod1.glb` | bandit / archer (hood, mask, leather, cape, bow on back) | 1.75 m | 11,845 / 1024 | 3,875 / 512 | 1.597 |
| `noble.glb`, `noble_lod1.glb` | noble / lord (fur-trimmed long cloak, gilded cuirass, sheathed sword) | 1.78 m | 11,735 / 1024 | 3,880 / 512 | 1.740 |
| `orc_warchief.glb`, `orc_warchief_lod1.glb` | orc warchief (horned helm, skull pauldrons, spiked bracers) | 2.20 m | 11,965 / 1024 | 3,879 / 512 | 1.975 |

\* The GLBs are normalised like the other UAL characters (pelvis at the UAL height, 0.917 model units).
`Assets.mh_character()` scales so that `Head bone rest y * 1.1 == height`. For helmets, hoods and the orc, the
top of the mesh sits higher than that, so pass the value in the last column to get the head or helmet top at the
nominal height (or scale the root by `height / model_top` yourself). The lineup preview uses the nominal heights.

Other details: one material each (base colour only, JPEG in the GLB, metallic 0, roughness 0.75), no normal
or metal maps (for mobile), no Draco or meshopt, at most 4 weights per vertex, 16 deform bones on each side
(fingers are not weighted; the whole hand follows `hand_l/r`). Files are 0.45 to 1.4 MB. Each is one
draw call. Use the `_lod1` files beyond about 15 to 20 m (Godot `visibility_range`), then the impostors.

## Previews (look first)
- `../_previews/armored_lineup.png`: all six in rest (T) pose next to `generated/characters/villager_man_a.glb`, at nominal heights, with 0.5 m guides
- `../_previews/armored_<name>_anim.png`: Walk_Loop, Sword_Regular_A, Idle_Loop plus one extra clip (guard Sword_Block, knight Idle_Shield_Loop, mercenary Sword_Heavy_Combo, bandit Bow_Pull_Back, noble Idle_Talking_Loop, orc G6_cast_two_handed_melee)

## Verification
- Godot 4.6 headless (scratch project, same track-path rewrite as `_ual_for`, UAL1 + UAL2): every LOD0 and LOD1 file has
  65 bones, 85 clips, **0 unresolved tracks**, and a maximum bone distance of 1.16 to 1.18 model units while playing Walk, Sword, Idle, Death and Sprint
  (villager_man_a: 1.12). Head rest y is 1.569 to 1.578, the same as the villagers.
- Blender renders of 12 clips per character (walk, sprint, sword attacks, block, sit, crouch, roll, death, jump) were checked for
  exploding vertices and stretched plates.

## Rig notes (`tools/meshy/armored_rig/`)
`armored_rig.py cfg_<name>.json [--debug]` does the following:
1. Finds landmarks: fingertips, the arm centre line (tracked from the tip inward), torso width, shoulder, ankles. Every UAL joint is
   placed from UAL proportions scaled by shoulder height. The elbow and wrist sit at UAL arc-length fractions along the tracked arm.
2. Applies Blender bone-heat weights on the fitted rig.
3. Cleans up the weights:
   - The **helmet or head** (everything above the Head joint) is 100 % `Head`.
   - **Pauldrons** (the shoulder sphere above the arm line) lose their spine weight to `upperarm`, with a small blend into `clavicle`.
   - **Limb bleed** is removed: arm and leg weights are dropped on vertices far from that bone's segment (capes, coats, torso).
   - **Skirts, long coats and capes** below the hips, away from the leg cores, blend `pelvis` into `thigh_l/r`. The blend depends on height and on x, so the hem
     follows both legs (60 % thigh at knee level) and sits between them when the legs split.
   - Hands hanging low in an A-pose are excluded from the skirt rule. After a light graph smoothing, weights are limited to 4 influences.
4. Poses the mesh into the exact UAL T-pose (arms straightened from Meshy's A-pose), bakes it, and scales it to the UAL pelvis height. The UAL armature is then fitted
   by **translation only**, so its rest rotations stay identical to UAL.
5. Builds LOD1 with Blender collapse decimation of the rigged LOD0. The weights are interpolated and the texture is reduced to 512 px.

Per-character overrides are in `cfg_*.json`:
- knight, bandit, noble: `shoulder_x 0.2`. Capes and fur collars hide the torso width.
- bandit: `rigid_lines`. The **bow on the back → `spine_03`**, as a diagonal band behind the back.
- orc: manual `arm_pts` (the spiked bracers confuse the arm tracker), a wider head-rigid zone (horns), and **skull pauldrons as
  uniform-weight boxes** (0.7 `upperarm` / 0.3 `clavicle`). Uniform weights keep each piece rigid instead of stretched.
- guard, mercenary: fully automatic.

`lineup.py` and `render_anim.py` produce the previews. `run_all.sh` rigs all six characters and renders a 12-clip stress sheet into `_work/`.
The Meshy remesh inputs (`_work/*_remesh_raw.glb`) are gitignored. `_work/` is ignored as a whole, including the debug joint and weight renders (`dbg_*`) and `stress_*.png`.

## Known issues
- **Capes and cloaks** (knight, bandit, noble) are skinned, not simulated. In a wide stride or a lunge (Sword_Regular_A) the legs push
  slightly through the cape or coat front, and in Roll or Death the cape stays a stiff sheet. Walk and idle are clean.
- **Orc pauldrons** are rigid to the upper arm. With the arms overhead (G6 two-handed casts) they fold over the helmet. The legs are short
  and stocky by design, so the knee sits lower than on the humans.
- **Noble sheath and mercenary sidearm** hang on the hip and use the skirt blend (pelvis plus thigh), so they swing slightly with the leg instead
  of staying perfectly rigid.
- **Bandit:** the bow top sits above the head, and the 1.75 m nominal height was applied by Meshy to the full bounding box, so the body is
  about 1.71 m. Use the height arg from the table.
- The shoulder bulk (gambeson, mail) makes the arms hang a little away from the body in idle poses.
- **LOD1** has some texture smearing where the decimation crosses UV seams (the guard's lion emblem, the noble's embroidery). It is fine at
  LOD1 distance.
- There are no finger bones in the weights (gloves and gauntlets are rigid fists), so grip poses do not curl the fingers. Attach weapons to `hand_r`
  as with the other characters.

## Meshy tasks and cost
Image-to-3d tasks were logged earlier in `../tasks.tsv` (36 cr each, including the concept image). This pass spent **30 credits**
(6 × `remesh` at 5 cr, 11.5k-tri target, resize to the nominal height, origin at the bottom). The remesh tasks are logged in `../tasks.tsv`.
