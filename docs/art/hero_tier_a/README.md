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
