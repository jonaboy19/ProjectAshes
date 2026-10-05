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
