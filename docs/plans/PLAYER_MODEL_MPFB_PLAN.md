# Player model from MPFB (MakeHuman) - plan (not started)

Status 2026-10-27: the player (hero_meshy3) reads low-detail next to ref 01 (KCD2): soft Meshy head, painted-on clothing folds, low-res hands.

## What is installed
- MPFB 2.0.17 in Blender 5.2 (`extensions/user_default/mpfb`). It has the base mesh (`data/3dobjs/base.obj`), targets (body/face shape), skin textures, poses, and rigs including **`rig.game_engine.json`**. That rig's bone names are Unreal-style (Root, pelvis, spine_01-03, clavicle_l, upperarm_l, lowerarm_l, hand_l, thigh_l, calf_l, foot_l, ball_l, finger chains). Those are the names the UAL libraries and ProceduralRig already use, so animation needs no retarget step, only a rest-pose (A/T) check.
- **Missing:** the MakeHuman asset packs (clothes, hair, eyebrows, eyes, skins beyond the default). They are CC0 ("system assets" and community packs from makehumancommunity.org) and have to be downloaded. Downloading needs your OK (filename, source, size).

## Plan
1. **Body/head (Blender, headless script `tools/blender/mpfb/build_player.py`):** a male adult (age 18-20 for the slice) with lean muscle and a weathered face, set from MPFB targets. Use the game_engine rig, feet on the ground, A-pose to match UAL rest. Use the MakeHuman skin material, baked to 2K albedo/normal/roughness, plus subsurface tint for Godot.
2. **Clothing (CC0 MakeHuman packs plus Blender tailoring):** linen shirt, wool tunic, belt, hose, and turn-shoe or short boots from the packs, with proxy-fitted weights. Gambeson/jerkin detail comes from cloth-sim baked folds (Blender cloth, 1 frame) baked to a normal map. Delete hidden body faces under the clothes, so there's no poke-through and fewer tris.
3. **Budget:** LOD0 about 25-30k tris with 2K textures, LOD1 about 8k, matching min-spec (integrated GPU). Eyes, brows, lashes and a hair-card helmet cut from the pack.
4. **Godot hookup:** add a `hero_mpfb` path in `Assets.mh_character` behind a flag. Same bone names, so CharacterAnimator, ProceduralRig sockets (hip/back/shield), HeroOutfit fitting and the props work unchanged. Check every socket offset against the new proportions.
5. **Gate:** equip_matrix sheets (idle/walk/run/ladder/sit/combat, sword + kite shield + pouch) and the slice route side by side with the current hero at gameplay distance, compared with ref 01, logged in AAA_GATE_LOG. Switch the default only on a PASS.

## Risks
- Pack licences: use CC0 items only, and record each one in a LICENSE.txt next to the GLB.
- Face realism: MakeHuman faces can read "uncanny-smooth". Plan a skin-detail normal pass (pores, stubble) and keep the camera distance in mind.
- Weights at the shoulders/hips under UAL's wide arm swings: check them with the run and ladder clips before the clothing work.
