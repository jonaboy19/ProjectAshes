---
name: ashes-hero-character
description: Tier-A character recipe for Rising Ashes (hero, companions, story NPCs) - pick a downloaded Meshy character, re-rig it to the UAL skeleton, smooth LOD0/LOD1/LOD2, the per-texel material-identity shader (skin SSS, hair anisotropy, linen/wool/leather/metal), optional built head (eyes, lashes, brows, hair cards, blink/expression shape keys) and the proof shots (turnaround, face, dialogue, shoulder cam, clip frame sheets). Use before touching the hero model, a companion or any close-up character.
---

# Tier-A hero / companion recipe

Owner rule (2026-10-06): **use the downloaded Meshy models first**; build from scratch only what they lack.
Status, ratings and images: `docs/art/hero_tier_a/README.md`. Owners: Codex = animation code + UAL bones (never change them);
AAA-feel agent = camera, HUD, lights. Characters only add meshes, materials and child nodes.

## 1. Pick the base (Meshy)
- Already on UAL: `kingdom/assets/incoming/meshy_dl3/characters_ual/` (7). Raw high-res sources (2048 px textures):
  `C:\Users\Jonna\Documents\ProjectAshes_art_staging\meshy_raw3\` (`*_biped.zip`; index `work3/index.txt`: 123 = villager_green_vest = `Medieval_Villager_T_P_biped`).
- Lineup: `godot --path kingdom --rendering-method mobile -s tools_qa/hero/hero_shots.gd -- --out=PREFIX --meshy_lineup` (body + face each).
- Hero = **villager_green_vest** (young brown-haired man, green vest, linen shirt: closest to target 03, best face of the set).
  Tier B companions/NPCs: peasant_hooded, merchant_cloaked, guardian_hooded, villager_hat, villager_white_shirt, knight_plate_a.

## 2. Re-rig + LODs (Windows, Blender 5.2 via `tools/external/blender.sh`)
1. Unzip the biped ZIP; `meshy3_rerig.PREP` bakes the rest mesh; `extract_texture` keeps the 2048 JPEG (see `C:/tmp/hero/rig/mk.py` pattern:
   cfg `lod0_tris` / `tex_lod0: 2048`). Run `tools/meshy/armored_rig/armored_rig.py -- cfg.json` (65 UAL bones, bone-heat weights).
2. `tools/blender/hero_tier_a/smooth_lods.py -- base.glb <prefix>`: weld seams, Catmull-Clark x1, decimate -> LOD0 14k, LOD1 = 4k source, LOD2 2k.
   Meshy biped sources are only ~4k tris, so LOD0 smoothness comes from the subdivision (weld first or the UV seams crack open).
3. Load like every character: `Assets.mh_character("res://assets/generated/characters/hero_tier_a/hero_meshy", 1.78[, keep, lod1])`.

## 3. Materials
- `HeroTierA.upgrade_meshy(model)` -> `shaders/hero/hero_character.gdshader`: one material per atlas; texels classified by HSV + height above
  the neck (`neck_y`): skin (wrapped red-shifted SSS in light(), pores, flush), hair (Kajiya-Kay band), linen weave, wool felt + sheen,
  leather grain + wear, metal. `debug_classes = 1` shows the class map. `ambient_lift` keeps the back-lit hero readable.
- Garments built in code (`hero_outfit.gd`, G6 hero) use `hero_garment.gdshader`: UV2.x = material id, UV2.y = sway weight, COLOR.a = stitched.

## 4. Built head (only if the base face is not good enough)
`tools/blender/hero_tier_a/build_head.py -- player_young.glb <out>` (MakeHuman face): welded skin, decimated CC, own 1024 face UV with baked
albedo x AO (`make_textures.py`), flush/cavity/lip vertex masks, shape keys Blink_L/R, Smile, Jaw_Open, Brow_Up, real eyeballs
(`hero_eye.gdshader`: iris, limbal ring, pupil, catchlight, lid shadow), lash + brow cards, MH hair cap + 3 layers of combed alpha cards
(`hero_hair.gdshader`, anisotropic, tip sway). `HeroTierA.upgrade(model)` retargets it onto ANY UAL skeleton at load
(v' = sum w * dst_rest * src_bind * v, blend shapes too) and adds `HeroFaceDriver` (blink, `set_expression`, `talk`, spring sway uniforms).

## 5. Prove it (always READ the images)
`tools_qa/hero/hero_shots.gd -- --out=P [--meshy=<path>] [--baseline] [--clips]`: turn_front/front34/side/back, face_front, face_34,
dialogue, shoulder_cam (3.9 m, FOV 54), clip strips (walk, Jog_Fwd, Sprint, Sword_Regular_A, Roll, Idle; side + back). Prints PERF tris.
Sparse worktree tip: Godot needs only characters, animations, animations_free2, quaternius/universal-animation-library*, fantasy-props-megakit,
armor, meshy_dl3, ai3d, generated/characters, generated/style_g (ground textures missing = harmless errors).

## Budgets (mobile)
LOD0 <= 15-20k tris, 1-3 materials, 1024 textures (2048 atlas for the hero face justified). Hero now: 14k / 1 material / 2048.

## Known gaps (next iteration)
Feet stretch into long "ski" soles on walk/run (armored_rig foot weights); oversized cream shirt collar lump (Meshy geometry); Meshy
eyes are painted (no blink/eye shader) - transplant the built eyes/lids or paint lids; no hood/satchel on the Meshy base; hands keep the
clip finger pose (no grip pose without bone changes); not yet wired as the default hero in `player.gd`; no S22 measurement.
