# Animation QA (`tools/qa/anim_qa`)

Objective check that character, creature and animal animations look natural: no foot
sliding, no floating or sinking, no stretched bones, no pops, clean loop seams, and clips
played at the speed the character actually moves in game.

## Run it

```bash
bash tools/qa/anim_qa/run.sh                # metrics + strips + contact sheets (GPU window, ~5-8 min)
bash tools/qa/anim_qa/run.sh --no-strips    # metrics + report only, headless (~2 min)
bash tools/qa/anim_qa/run.sh --only=guard   # a single character (substring of the id)
bash tools/qa/anim_qa/run.sh --import       # fresh checkout: import assets first
```

Set `GODOT=/path/to/godot` if Godot 4.6 is not at the default path of this PC.
The script calls `godot --path kingdom -s tools/qa/anim_qa/anim_qa.gd`, then reverts
any `.import` file that the Godot run rewrote (Godot 4.6 adds new default keys to
older `.import` files; those changes are noise for git). Nothing under `kingdom/` is
modified.

Debug one clip frame by frame (foot heights, contact vertex, hips):
`godot --headless --path kingdom -s <abs path>/anim_qa.gd -- --only=villager_man_a --dump=Walk`

## Outputs

| file | what |
|---|---|
| `docs/qa/anim_qa_report.md` | summary counts, ranked problems, speed table, thresholds, per character x clip tables. The block between `<!-- MANUAL START -->` and `<!-- MANUAL END -->` (visual judgement, recommendations for the cloud session) is preserved across runs. |
| `docs/qa/anim_qa_results.csv` | every row with all numbers |
| `docs/qa/anim_strips/<id>__<clip>.jpg` | 8 frames, side view, ground grid; locomotion strips move the model at the game speed so a sliding foot shows against the grid |
| `docs/qa/anim_sheet_<group>.jpg` | contact sheets: villagers, armored, creatures, animals (4 frames per clip) |

## What it tests (and how it stays honest)

* `catalog.gd` lists every character type the game spawns and the clips it plays,
  mirroring the game code: `Assets.MH_LOOKS` / `Assets.mh_character()` for all UAL
  humanoids (MakeHuman, G6, CDmir, Meshy armored), a copy of the `CampMonster`, `Wolf`
  and `Critter` setup (scale, loop flags) for goblins, the wolf and animals, and the
  Meshy creatures (ready but not yet wired). Humanoids are loaded through
  `Assets.mh_character()` itself, so the UAL library, track remapping and scaling are
  exactly what ships.
* Speeds come from `Player.WALK/RUN`, the `CharacterAnimator` blend points,
  `Soldier.WALK/RUN`, `Villager._process`, `CampMonster.SPECIES`, `Wolf` and
  `Critter.KINDS`. **When those constants change, update `speed_cases()` in
  `catalog.gd`.** When a new character or clip is added to the game, add it there too.
* Each clip is sampled at 30 fps (loop mode off while sampling, so the seam can be
  measured). Contact points are the lowest skinned vertices of each foot (feet are the
  UAL `foot/ball` bones, or clustered sole vertices for other rigs), so foot roll does
  not count as sliding. The clip's natural ground speed is the median backward speed of
  planted feet (for UAL rigs from the ball joints, independent of skin weights).
* Clips the game plays on the upper-body layer only (`CharacterAnimator.play_upper`:
  sword swings, block hit, Hit_A) are not graded on leg/ground metrics.

Thresholds and the reasoning are printed in the report ("Thresholds and why") and
defined at the top of `anim_qa.gd`.
