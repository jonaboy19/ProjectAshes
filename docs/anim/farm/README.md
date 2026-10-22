# Farm animals: graze + wing-flap polish

Rebuilt in place: `kingdom/assets/incoming/meshy_free/farm/rigged/{cow_spotted,cow_brown_a,cow_brown_b,chicken_hen,chicken_rooster}_rigged.glb` (+ `.json` for the chickens). Same file names, same clip names (`idle`, `walk`, `eat`, `flap`), same lengths (30 fps), no renamed clips. `.import` files untouched (import settings unchanged).

Scripts (Blender 5.2, reproducible): `kingdom/tools/anim/farm/`
- `build_all.sh [outdir]` rebuilds all five GLBs from `farm/*_lod0.glb`.
- `rig_cow.py`, `rig_chicken.py` (copies of `tools/meshy/animal_rig/` scripts with the fixes; they still import `rig_lib.py` from there).
- `measure.py` prints muzzle height / hoof height (cow) or wing spread (chicken) per frame.

## Cow graze (`eat`)
Problem: the old script solved the dip on the head bone tail (about 20 cm above the real muzzle) and its leg IK ignored the pelvis/chest pitch, so hooves sank up to 2 cm.
Fix: the dip (pelvis, chest, neck, head pitch, neck stretch, small root drop) is now bisected per cow on the SKINNED mesh until the muzzle (front 12 cm of head-weighted verts) is 4.5 cm above the ground at the bottom of the graze; leg IK now subtracts the parent pitch, so hooves stay planted while the body pitches.

| cow | muzzle min height, before | after | hoof min z before / after |
|---|---:|---:|---|
| spotted | 0.232 m | 0.029 m | -0.020 / -0.002 m |
| brown a | 0.280 m | 0.007 m | -0.009 / -0.008 m |
| brown b | 0.230 m | -0.005 m | -0.008 / -0.008 m |

(Muzzle touches the grass during the tearing bobs; brown b dips 5 mm, invisible under grass. Brown hoof z is identical before/after: the small negative is the hoof mesh, not sinking.) Bones: 21, unchanged.

## Chicken wings (`flap`)
Problem: one rigid bone per wing swung a flat flank patch out.
Fix: 4 bones per wing (upper arm `wing_L/R`, forearm `wingF_*`, secondaries `featIn_*`, primaries `featOut_*`). Bones: 11 -> 17 per chicken (skin weights of every non-wing bone are unchanged; wing weights follow distance to the wing chain, only in a band around the patch). Flap is now a 30-frame burst: 0-4 unfold from the folded rest pose, 3 flaps of 7 frames (downstroke 3 f, upstroke 4 f), 25-30 fold back; clip starts and ends folded (clean loop). Arm and forearm lengthen on unfold, forearm/feathers lag the shoulder (elbow bends on the upstroke), feathers fan out. idle/walk/eat leave the wing bones at rest.

| | max wing tip |x| before | after |
|---|---:|---:|
| hen | 0.194 m | 0.293 m |
| rooster | 0.224 m | 0.469 m |

Tris unchanged (hen 2,492, rooster 2,383; cows 5,994 / about 3,500).

## Review (sheets in `frames/<animal>_<clip>[_front]/`, JPEG, 480 px tiles, read one by one)
All pass: cows idle/walk/eat (spotted, brown a, brown b), chickens idle/walk/eat/flap side, flap front (hen and rooster). Sheets sampled at 15 fps (eat, flap 30 fps), idle 10 fps, walk 15 fps.
Known limits: the wing is still a textured flank patch, so it reads as a fanned, tapered wing, not individual feathers; the rooster wingspan is wide (0.94 m tip to tip), reduce `E_HI` / arm scale in `rig_chicken.py` if it looks too big in game; rooster orange tail spike still follows the tail bone (pre-existing); the cows' front legs look slightly wedge-like in deep graze.

## Handoff for Codex
No clip renamed. Chicken `flap` semantics changed slightly: it is now a folded -> open -> 3 flaps -> folded burst (30 f, still loop-safe); play once per flutter, or loop for repeated bursts. Cow `eat` reaches the ground (muzzle at ground level at about 0.5 s to 2.2 s of 5 s), so nothing else needed. Bone counts: cows 21, chickens 17 (was 11).
