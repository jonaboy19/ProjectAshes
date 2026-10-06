# Tier-A hero: checkpoint 1 (2026-10-06)

Recipe and commands are in the skill `ashes-hero-character`. Renders come from the PC Mobile renderer, using `tools_qa/hero/hero_shots.gd`. The S22 was not used because release QA owns adb.

## Ratings (honest, read from the images)

| Candidate | Face close-up | Dialogue | Shoulder cam | Clips | Tris / mats / tex |
|---|---|---|---|---|---|
| **Before:** G6 hero + HeroOutfit (`base_sheet.jpg`) | 2/10: 488-tri head, painted flat eyes, hair tufts float off the head, a tuft over the eye | 3 | 5 | ok | ~4.0k / 6 / 512-1024 |
| Built MH head on the G6 body (`a3_sheet.jpg`) | 4/10: real eyeballs (iris, catchlight), lashes, brows, blink/expression keys. Hair cards still spiky, neck clips the collar | 4 | 5 | not run | 10.8k / 9 |
| **Meshy villager_green_vest Tier-A** (`m3_sheet.jpg`, `m3_clips.jpg`) | 6/10: photoreal painted face and hair, smooth LOD0. No blink, a mouth texture blemish, eyes painted | 5: oversized cream shirt collar lump | 6: reads as a real person, but the back is dark green in back-light | 5: walk/run/sprint/attack/roll/idle all play; boot soles stretch into long "skis" | **14k / 1 / 2048** |

Lineup of all 7 Meshy UAL characters: `ml_sheet.jpg`. villager_green_vest is the hero pick. The others are Tier B companions and NPCs.

## Next steps (ranked)
1. Fix the foot weights (the ski soles). Use Blender weight clean-up or `armored_rig` overrides.
2. Shrink or reshape the shirt-collar lump.
3. Wire the hero into `player.gd` behind a flag, after items 1 and 2. It is not wired yet; the G6 hero is still the default.
4. Eyes and blink: transplant the built eyeballs and lid shape keys, or paint lids.
5. Add the hood and satchel with sway (the `hero_garment` pieces).
6. Measure on the S22.

## Pass 2 (2026-10-06): `m5_sheet.jpg`, `m5_clips.jpg`
New: `hero_fix.py` (foot and finger re-weights, collar pull-in, mouth patch, blink lid patches), `HeroTierA.dress_meshy_hero` (hood, satchel, strap, belt from HeroOutfit, plus the blink driver), and a painterly skin mip with a Style G warm grade and a brighter back.

Rating: still about 6/10 in close-up, so it is **not** made the default hero.
- Better: the fingers now curl on the sword grip, and the back is less dark.
- Not fixed:
  - Ski soles on run, sprint and attack.
  - The collar blob is barely changed.
  - The mouth smear remains.
  - The lid patches render as visible rectangles and need a soft alpha edge.
  - The hood ring reads as a flat tan band; it needs the real hood geometry.

## Pass 3 (2026-10-06): `m8_sheet.jpg`, `m8_clips.jpg`
- **Fixed:** ski soles. The boot is slid about 3.5 cm forward onto the ankle and the foot weights are made rigid. Walk, run, sprint, attack and roll are clean.
- **Better:**
  - Lids are softer (alpha border plus a lash line), but the blink still reads as smudged patches.
  - The mouth patch is gentler, but a small dark notch remains.
- **Not fixed:**
  - Collar/shoulder mass. It is the model's own shoulder volume, not a collar band, so it needs Blender sculpt or reshape work.
  - The fitted hood leaves orange shards at the chest, so it is switched off.
  - Grip: the Meshy hands are fused mitts. Finger re-weighting shredded them, so it is off (`--fingers`). The sword floats in an open hand.

Rating: about 6/10 in close-up and about 6 at the shoulder cam. **Not default.** It doesn't clearly beat the current hero, and there was no benchmark-street test: the sparse worktree has no town, and disk is too tight for a full worktree.

## Pass 4 (2026-10-06): `m11_sheet.jpg`, `m10_clips.jpg`
- **Hands:** the Meshy mitts are cut at the wrist and the G6 hands are retargeted on (15 real finger bones each). Clip fists and grips now curl, and all clips are clean. The skin tone is still too orange.
- **Blink:** the lids sample one plain cheek texel and get a soft border plus a lash line. The half-blink now reads as eyelids.
- **Hood:** a separate cloth shell grown from the collar and upper back (same weights, offset 1.6 cm plus 6 mm solidify, so it doesn't clip), with a folded bag on the back. At gameplay distance it reads as a brown hooded mantle and hides the shoulder bulk. In close-up its edges are flat and jagged.
- **Shoulders:** slimmed about 18 % in depth (geometric sculpt). Still broad.
- **Flag:** `player.gd` has `TIER_A_HERO` (false) and `--hero_tier_a`.

Rating: close-up about 6.5/10, shoulder cam about 6.5, clips 7.

Benchmark street: NOT run. The full worktree's Godot import segfaulted while disk free fell to 3.7 GB (other agents writing). The worktree was removed. The hero stays off by default.

## Pass 5 (2026-10-06): `m12_sheet.jpg` (shell visible), `m13_sheet.jpg` (shell hidden)
- **Hands:** they now use the same `hero_character` shader as the body. The tint is the measured ratio of the Meshy skin mean to the G6 hand texture mean (0.68, 0.69, 0.73), and they now match the face.
- **Sword:** `HeroTierA.regrip()` puts the handle centre between the curled middle finger and the thumb in the Sword_Idle pose. The sword now sits in the fist. The same bug exists on the current G6 hero (the handle lies across the wrist).
- **Mantle:** smoothed, thicker, with a darker wool tint, but the front shoulder slabs still read as shards in close-up. It is hidden (`SHOW_HOOD_SHELL = false`).

Rating: about 6.5/10. Still not default.

## Paid Meshy hero, first pass (2026-10-06): `n1_sheet.jpg`
- **Source:** `ProjectAshes_art_staging/hero_meshy/hero_rigged.glb` (35 credits, spent by the coordinator). Re-rigged to UAL with the same pipeline, LOD0 18k / LOD1 17.6k / LOD2 3k, saved as `assets/generated/characters/hero_tier_a/hero_meshy2*.glb`.
- **Result:** it loses (about 3/10).
  - The texture did not come through. `extract_texture` grabbed image 0, which is probably not the PBR base colour, so the model renders flat dark grey.
  - The body is a bulky cloak block with a dark face.
  - The boots stretch into skis again (the boot was shifted 9.7 cm).
- **Next:** pick the base-colour image by its material slot, then re-run `hero_fix` without `--keep_hands`.

## Paid Meshy hero, pass 2 (2026-10-06): `n2_sheet.jpg`, `n2_clips.jpg`
- **Texture:** the base colour is the material's baseColorTexture (image 2, not image 0). The Target 03 palette now reads: green tunic and cloak, leather vest and straps, hood.
- **Hands:** the hand swap works, and the sword sits in the fist.
- **Problems:**
  - Hulking proportions: very broad shoulders and arms.
  - The hood reads as shiny gold satin (the atlas classifier marks it leather/metal, so specular is too high).
  - The ski soles are back on run and attack (the 9.7 cm boot shift is too large for this model).
  - The face camera framing is too low for this head height.
  - Harsh painted brows.

Rating: about 5/10 (palette and silhouette at distance about 6, close-up 4). It loses to m13 (about 6.5), so it is not default. Benchmark street not run.

## Paid Meshy hero, pass 3 (2026-10-06): `n4_sheet.jpg`, `n4_clips.jpg`
- **Arms:** narrowed 18 % (`hero_fix.py --narrow=0.18`). Arms and shoulders only: the first try also caught the legs and made the hero float.
- **Hood:** forced to matte wool by a vertex mask (COLOR.r), not by colour heuristics.
- **Lips:** the lipstick red is muted in the shader.
- **Noise:** mip bias 0.6 and detail normals at 0.5 calm the close-up texture.
- **Face camera:** now aimed from the lid patch at the real eye height.
- **Boot shift:** capped at 3 cm (`--maxshift`).

Rating: about 5.5/10.
- Better: the outfit read at distance and the matte hood.
- Still wrong:
  - The hulking cloak silhouette from behind.
  - Run and attack soles still stretch backwards; this needs hand-painted foot weights.
  - The low-poly face planes up close.

It doesn't beat m13 (about 6.5), so it is not default. Benchmark street not run.

## Paid Meshy hero, pass 4 (2026-10-06): `n5_clips_coat_fail.jpg`, `n6_sheet.jpg`
I tried boot-only foot weights plus a shortened coat skirt (`hero_fix.py --coat`). It made things worse: the hero floats, the feet turn into stumps, and the hem is jagged. The flag stays off and the shipped asset is back to the pass 3 state (n6 = n4 plus stronger brow lightening).

The "skis" and the cloak bulk are baked into the Meshy geometry, a single fused shell for coat, legs and boots. Fixing them needs manual separation of the coat in Blender, not more scripted heuristics.

Verdict: m13 (about 6.5) stays the best candidate, the paid hero is about 5.5, and the current G6 hero stays the default. Benchmark street not run: neither candidate clearly wins in the sheets.

## Hero v2: part-separated Meshy hero, now the DEFAULT (2026-10-06): `v1_sheet.jpg`, `v1_clips.jpg`, `ig_compare.jpg`, `ig_hero_crop.jpg`
- **Source:** `ProjectAshes_art_staging/hero_meshy/hero_v2_parts_rigged.glb` (23 credits, smart topology, slim, separate boots, no cloak).
- **Pipeline:**
  1. armored_rig to UAL.
  2. `hero_fix.py --maxshift=0.03` (boot shift is only about 1 cm here, so no skis).
  3. G6 finger hands, blink lids, hood material mask.
  4. `smooth_lods.py` to LOD0 17k, LOD1 3.6k, LOD2 3k.
  5. In-game total: 19.5k tris, 4 materials, 2048 atlas.
- **Sheet:** clean walk, run, sprint, attack, roll and idle with no skis. The face is a stylised young hero that fits Style G better than the photoreal villager. The sword sits in the fist.
- **In-game** (full worktree, `tools_qa/aaa_camera/feel_views.tscn`, PC Mobile renderer, 2340x1080): street, village and benchmark street, current G6 hero vs v2. v2 clearly wins: real proportions, hooded leather vest over a green tunic, boots and bracers that read at the 3.9 m shoulder cam.
- **FPS:** noisy on the shared PC. Two runs each, benchmark views: G6 14-32 fps, v2 7-24 fps. There is no clear regression, but the S22 is not measured.
- **Rating:** about 7/10 (m13 about 6.5, the old G6 hero about 5 at the shoulder cam). `player.gd` now has `TIER_A_HERO = true`; set it to false to roll back. Custom appearance from character creation still uses G6.
- **Open:**
  - The hands are slightly paler than the face.
  - The brows are a little heavy.
  - The hood is down (no hood-up variant).
  - S22 fps and the LOD switch distances are not set.
