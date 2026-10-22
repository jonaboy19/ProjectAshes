# Video study B2 (owner reference videos, batch 2)

Method: ashes-video-review (stop-motion contact sheets, 0.75-6 fps, plus a 4 fps crop of the key combat window). Sheets kept in `/tmp/claude-0/videostudy/b2/<videoid>_sheet*.png`. Priority: P0 now, P1 next, P2 later. Owner tags: CC = cloud code, LOCAL = local PC art/GPU, CODEX = animation. Mobile cost on Galaxy S22: cheap / moderate / expensive. Free CC0/MIT/OFL only; never Higgsfield.

## 1. 6342ce1d (1:36) - Blender stylized VFX shader tutorial (TikTok @goodgood3d)
**What:** Screen recording of a Blender tutorial building a "toon magic" VFX set: a hard-edged swirling shield sphere, expanding ground rings, slashes, orbs, all emissive with cel-shaded shadows on a test plane (first and last seconds show the finished showcase: cyan/white swirl shield, green spiral, blue energy burst, red crescent, orange ring).
**Steps shown (technique):**
1. Procedural noise (fBM, scale ~5) -> Greater Than threshold (0.4-0.75) gives a hard black/white mask (no soft gradients = stylized look). Threshold animates the mask growing/shrinking.
2. Swirl/stripe mask: Texture Coordinate (Generated) -> Separate XYZ -> Multiply the Z (height) by a factor, Combine XYZ into a Mapping rotation, so the noise rotates more with height; gradient texture -> noise vector. Offset by Scene Time (seconds) so it spins. Stripe density = the multiplier (2 -> 4.9).
3. Mask drives Emission (cyan, strength up) on a black Principled BSDF; Backfacing/Geometry node mixes a transparent shader for the inside. A Fresnel-like rim via Layer Weight.
4. Geometry Nodes for ring VFX: Map Range from Scene Time (0-25 frames) -> Float Curve (ease-out) -> Transform Geometry scale; Color Ramp makes the ring fade; ring thickness animated by the same curve.
**Why it feels premium:** everything is a short (about 1 s), fast ease-out burst with a bright core, hard-edged shapes with a few steps of colour, and cast shadows from emissive objects; shapes read at phone size.
**Licence:** Blender is GPL, our output (textures/meshes/shader code) is ours. Technique is generic (noise threshold, no asset reuse). OK.
**Takeaways for Rising Ashes**
| # | Takeaway | Owner | Mobile | P |
|---|---|---|---|---|
| a | Port to a Godot spatial/particle shader ("toon_mask.gdshader"): noise (small baked 128px tex) + `step(threshold, n)` + time-scrolled UV, emission. Use for technique shields, ward/runestone auras, soulbeast aura, spell shells (technique_caster.gd VFX). Matches storybook look better than soft particles. | CC | cheap (one baked noise tex, unlit) | P1 |
| b | Standard "burst" timing preset for VFX: 0.6-1.0 s, ease-out scale, colour-ramp fade, bright core at frame 1-3; one `VfxBurst` helper reused by hit sparks, rings on ground (shockwave on heavy hit, parry ring). | CC | cheap | P1 |
| c | Ground ring/slash meshes (flat quad with radial gradient) instead of GPU particles for most impacts: 1 draw call each. | CC + LOCAL (tex) | cheap | P1 |
| d | Warm-light style note: the showcase glows on a cool plane. In Style G keep emissive VFX warm/gold or one signature colour per power path so glow reads against sky-blue ambient. | LOCAL | cheap | P2 |

## 2. f021b83d (1:36) - Blender creature timelapse (TikTok @ivareio, "200$ commission")
**What:** Timelapse making a stylized-realistic wolf/dog from a 2D character sheet: blockout, sculpt (head, muscle groups, veins, eyes, claws), retopo, flat-colour texture paint matched to the 2D markings, paw detail, weight paint heat-maps, fur/hair (curve/particle strands, tail, mane, ruff), a Rigify-style rig with many controls, braided accessories (chain ring, feather braid), final turntable poses (stand, sit, walk).
**Premium cues:** silhouette-first (mane, tail plume, ruff break the outline), colour blocking that matches the 2D design exactly, layered fur (inner short fur, long guard hairs, feathered legs), asymmetric accessories (feather braid, ring collar) give character; eye shine and glossy nose; paws with separate claws.
**Takeaways**
| # | Takeaway | Owner | Mobile | P |
|---|---|---|---|---|
| a | Soulbeast/wolf quality bar: sculpt -> retopo to ~6-10k tris, colour map from design, fur as alpha **hair cards** (not strands), not particle hair. Cards for mane, tail, chest ruff, leg feathering: ~2-3k extra tris, one alpha-tested material. | LOCAL (Blender) | moderate | P1 |
| b | Accessory kit for beasts and NPCs (braid, collar ring, feather, bone charms): small separate meshes parented to bones, doubles as per-individual identity for micro-events (named wolf, guard dog). | LOCAL | cheap | P2 |
| c | Rig: Rigify (already in ashes-external-tools) with tail/ear/mane secondary chains; bake to GLB AnimationLibrary; Wiggle 2 or Bone Dynamics for mane/tail sway baked into clips for the phone (no runtime physics). | LOCAL + CODEX | cheap when baked | P1 |
| d | Eye detail (glossy cornea + highlight + warm iris) and wet nose are the cheapest "alive" cues; add to creature_models.gd materials. | CC | cheap | P1 |
| e | Weight-paint heatmap review step in our animation QA (ashes-video-review) to catch candy-wrapper joints before handing to Codex. | LOCAL | n/a | P2 |
Not a tool tutorial; no licence concern. Do not copy the owner's commission art or the 2D character itself.

## 3. 366ba72d (1:07) - Meme commentary, Avatar: The Last Airbender (TikTok @xe.ds)
**What:** Face-cam reaction over a tweet ("changing powers, who'd be the most ruthless?" Azula as a waterbender; Fire Nation/Water Tribe swap art) and a clip of Iroh/Aang from the cartoon, with burned-in word-by-word captions (bold white text, pink highlight). No gameplay, no engine.
**Useful bits only:** (1) power-path design discourse: players love *role inversions and cross-element power twists* (a "bloodbending"-style control technique reading as ruthless). (2) the caption style is a marketing format.
**Takeaways**
| # | Takeaway | Owner | Mobile | P |
|---|---|---|---|---|
| a | Power-path design (ashes-ability-system): include one "dark mastery" late-tier technique per path (control/drain), gated by reputation or crime, since that is what the audience finds memorable. Design doc only. | CC | n/a | P2 |
| b | Trailers/socials: word-by-word burned captions are the TikTok norm; later marketing task. | LOCAL | n/a | P2 |
Nothing visual to adopt. Copyrighted source; do not reuse clips.

## 4. d65f6591 (1:06, high bitrate) - Reaction to an Avatar-inspired elemental-combat game reveal (TikTok @rapidreacts)
**What:** Top third face-cam reaction, bottom two thirds a UE5-quality trailer/gameplay of a wuxia-style town ("NEW GAME REVEALED INSPIRED BY AVATAR"). Title not stated on screen (the Avatar logo card appears at 14 s); only the reaction channel is credited. Most valuable video in this batch because the footage is real elemental combat.
**What reads premium (frame evidence, see `d65f6591_combat.png`, 38.5-52 s at 4 fps):**
- **Camera:** third-person chase cam that swings *with* the action: pulls in tight on the player for a hit (40.75-41.5 s, ~1 s), cuts to a wide establishing shot, then low-angle/dutch tilts on launches (26 s aerial shot). Trailer-style rapid cuts every 1-2 s; in play, camera is close behind the shoulder with strong FOV push on special moves. Motion blur on bending (2.5-3 s, 31 s, 36 s) hides geometry.
- **Combat feel:** every strike has a *reaction*: enemies are launched, fall, and lie on the ground afterwards (42-45 s bodies stay; fire residue persists on the street). Heavy attacks throw dirt/rock debris (39.5 s boulder punched through) plus smoke puffs; the player lunges forward on each hit (root motion step-in), crouched stances between moves. Enemies burn: fire sits on their bodies and ignites ground patches that last several seconds.
- **VFX:** layered: core flash (white-orange), embers/sparks flying outward (23 s), smoke volume, ground decals (scorch, cracked cobbles, frost), refracted water splash, rising dust. Elements differ in *shape language*: earth = chunky slabs, fire = streaming tongues and embers, water = splashes and a frost disc on the floor (0-2 s), air = swirl and debris ring (29-31 s).
- **World and light:** dense dressing in the fight space (carts, lanterns, crates, tiled roofs, vines on walls, hanging signs); warm sun with cool shadow and volumetric haze; wet-looking cobbles with specular; destruction (the roof/water-tower toppling, a giant rolling wheel) used as set pieces.
- **Characters:** hero identity via a mask (red-white), cloth layers that trail, hair and cape secondary motion; enemies have coloured ember glow so faction/element reads instantly.
- **Implied audio:** low thump + whoosh on lunge, crackle bed on fire, rumbling crunch on earth, crisp water slap; rarely music-only.
**Takeaways**
| # | Takeaway | Owner | Mobile | P |
|---|---|---|---|---|
| 1 | **Hit reaction + knockdown + body stays** for every melee hit tier: light = flinch + 2-frame hit-stop, heavy = launch/stagger with ragdoll (ragdoll.gd) and a settled body for ~10 s. Extend combat_feedback.gd/impact_pause.gd tiers (light 40 ms, heavy 90 ms, kill 140 ms). | CC (feedback), CODEX (react clips) | cheap | P0 |
| 2 | **Hit-kick camera**: on heavy hit/special a 0.15-0.3 s FOV punch-in (-4 to -8 deg) + small shake on camera_shake.gd, eased back; plus lock-on framing keeps player + target in frame. | CC | cheap | P0 |
| 3 | **Ground decals/residue** (scorch, frost disc, cracked stone, blood-free dust ring) that last 3-8 s and fade, capped pool of ~12 decals. Matches ashes-world-lint budgets. | CC (system) + LOCAL (textures) | cheap | P1 |
| 4 | **Layered impact recipe**: flash sprite 2-3 frames + radial sparks/embers (CPUParticles3D, 12-20) + dust puff + ground ring. One reusable `ImpactLayers` scene with element variants (gold spark/steel, fire ember, frost, dust, ward-blue). | CC | cheap-moderate (CPUParticles, cap 3 active) | P0 |
| 5 | **Element shape language** for power paths: define silhouette/colour per path (fire streaming, earth slabs, water splash+frost disc, air swirl ring, ward = runestone gold) in the ability system docs before authoring VFX. | CC | cheap | P1 |
| 6 | **Burning status**: on-body ember particle + warm point-less emissive pulse on enemy material (no real lights), plus short ground fire patches as an alpha quad. | CC | cheap | P1 |
| 7 | **Lunge/root-motion step-in on attacks** and stance crouch between hits: needs per-clip root motion and attack magnetism toward target (player.gd combat, melee skill). | CODEX (clips) + CC (magnetism) | cheap | P0 |
| 8 | **Establishing dressing around fight spaces** (cart, crates, lanterns, vines) as cheap props with low LOD; fights in Thornfield market should feel alive, not an empty arena (matches VERTICAL_SLICE P1 props pass). | LOCAL + CC | moderate (draw-call budget) | P1 |
| 9 | **Radial/motion blur on specials only** (cheap fullscreen shader, 2-3 samples, 0.2 s) to hide the transition; skip on LOW tier. | CC | moderate (full-screen pass) | P2 |
| 10 | **Audio plan**: lunge whoosh + hit thump + debris crunch layered per tier (rFXGen/jsfxr, ashes-external-tools). | CC (hooks), LOCAL (SFX) | cheap | P1 |
Licence: game footage is reference only; do not copy assets or branding. Avatar IP is not ours; do not use Avatar names or logos.

## 5. 18a83567 (0:13, 1024x576) - Third-person fantasy life-sim/creature-collector gameplay with full HUD (TikTok @gula0234)
**What:** Night forest, player on a winged glider-mount that dashes and swoops through a purple-lit wood; quest text "Find clues in the Russet Highlands to restore the painting", NPC bubble "Pathfinder! Come take on the challenge!", enemy label "Lv.43 Sparki". The corner watermark is only partly legible and looks like "Fantasy Life i" (Level-5); I am not certain of the title.
**Premium cues:**
- **HUD discipline:** top-left circular minimap with a tiny sun/time icon and quest pin; quest tracker with a clear verb line ("Track the target") and a distance marker on world (962 m, small leaf icon); top-right icon row (menus); right edge a vertical party/companion stack with level badges; bottom control hints (Jump/Dash/ATK/Lock On) fading in the corner; bottom-center a segmented gauge ("Untwine") with pips; ability buttons bottom-right with cooldown numbers. Everything small, low-contrast, never covers the centre.
- **Atmosphere:** blue-teal night grade with purple fireflies/spirit orbs, volumetric mist between trunks, bright pinpoint lights for focal interest, heavy tall-grass foreground; enemies marked by red glow.
- **Locomotion VFX:** green speed-streak trails on dash/swoop, little wing flares, motion-feel via camera lag and low FOV changes.
- **World-to-UI:** in-world NPC speech bubble with name arrow; floating enemy name + level plate; far-away objective with metres.
**Takeaways**
| # | Takeaway | Owner | Mobile | P |
|---|---|---|---|---|
| 1 | **World-space objective marker with distance** (leaf/pin + "962 m") and a one-line quest verb; ties into our contextual interaction button task (P0 in VERTICAL_SLICE). | CC | cheap | P0 |
| 2 | **Floating name plate with level/threat tier** on enemies only when lock-on or near (shows "Lv" + faction glyph) plus red glow rim on hostile; helps readability at phone size. | CC | cheap | P1 |
| 3 | **Dismissable control hints** (Jump/Dash/ATK) in the bottom-left that fade after first use; on touch show icons next to our virtual buttons. | CC | cheap | P1 |
| 4 | **NPC speech bubble in world** (short rounded bubble with name + arrow) for micro_events barks (guard shout, merchant call) instead of full dialogue. | CC | cheap | P1 |
| 5 | **Night look target**: blue-teal grade + warm focal pinpoints + low-lying fog; spirit-orb fireflies as 10-20 additive sprites. Fits Style G night tier (cool shadows already in LUT; add fireflies in forest sites). | LOCAL (grade) + CC (fireflies) | cheap | P1 |
| 6 | **Dash streak** for the player dodge/sprint: a short ribbon trail (2-3 fading quads) instead of particles. | CC | cheap | P1 |
| 7 | **Segmented gauge** (pips) for stamina/focus: clearer than a smooth bar at phone size. | CC | cheap | P2 |
Reference only; do not copy the UI art or layout one-to-one (owner of that game's IP).

## Ranked top-10 takeaways (all videos)
1. (v4) Heavy-hit reaction chain: launch/stagger, ragdoll, body persists, tiered hit-stop. CC + CODEX, cheap, P0.
2. (v4) Hit-kick camera: FOV punch-in + short shake, lock-on framing. CC, cheap, P0.
3. (v4) Layered impact recipe (flash, sparks, dust, ground ring) as one reusable scene with per-element variants, capped. CC, cheap-moderate, P0.
4. (v4) Attack lunge/root-motion step-in and magnetism to target. CODEX + CC, cheap, P0.
5. (v5) World-space objective marker with distance plus contextual verb line; floating threat plate on hostile only. CC, cheap, P0.
6. (v1) Toon noise-threshold swirl shader and the 1-second ease-out burst preset for power-path VFX. CC, cheap, P1.
7. (v4) Ground decals/residue (scorch, frost, cracks, dust) with pooled cap. CC + LOCAL, cheap, P1.
8. (v2) Soulbeast quality bar: hair cards for mane/tail/ruff, baked secondary motion, eye detail, accessory kit. LOCAL + CODEX, moderate, P1.
9. (v5) Night grade and spirit-orb fireflies, speech-bubble barks for micro_events, dash streak ribbon. LOCAL + CC, cheap, P1.
10. (v4, v3) Per-element shape language plus audio layers (whoosh, thump, crunch); design a dark-mastery capstone per path. CC + LOCAL, cheap, P1/P2.
