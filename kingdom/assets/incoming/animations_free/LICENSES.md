# Licences of the free animation clip library

Every clip in `animations_free/` is retargeted onto the Quaternius UAL 65-bone skeleton by
`kingdom/tools/anim/retarget_bvh.py`. Only sources that allow commercial use in a closed,
paid mobile game are used. Raw source files are **not** committed (see `tools/anim/fetch_sources.sh`
and `tools/anim/fetch_free_sources.sh`); only the retargeted GLB libraries are.

## 1. CMU Graphics Lab Motion Capture Database (martial arts, boxing, kicks, acrobatics, falls, get-ups)

- Data: http://mocap.cs.cmu.edu/  (licence / FAQ: http://mocap.cs.cmu.edu/faqs.php)
- BVH conversion: Bruce Hahne ("cgspeed", 2010 Motionbuilder-friendly release),
  mirror used: https://github.com/una-dinosauria/cmu-mocap (`READMEFIRST.txt`)
- Subjects used: 02, 12, 13, 14, 15, 16, 17, 33, 49, 56, 74, 75, 76, 77, 78, 79, 80, 83, 85, 86,
  87, 88, 90, 91, 102, 139, 140, 141, 143, 144 (the exact take of every clip is in `README.md`
  and in each `*.clips.json`).
- Terms, verbatim from `READMEFIRST.txt` (quoting mocap.cs.cmu.edu):

  > CMU places no restrictions on the use of the original dataset, and I (Bruce) place no
  > additional restrictions on the use of this particular BVH conversion.
  >
  > "Use this data!  This data is free for use in research and commercial projects worldwide.
  > If you publish results obtained using this data, we would appreciate it if you would send
  > the citation to your published paper to jkh+mocap@cs.cmu.edu, and also would add this text
  > to your acknowledgments section: 'The data used in this project was obtained from
  > mocap.cs.cmu.edu.  The database was created with funding from NSF EIA-0196217.'"

- Credit line (kept in `kingdom/CREDITS.md`): "Motion capture data from the CMU Graphics Lab Motion
  Capture Database (mocap.cs.cmu.edu), created with funding from NSF EIA-0196217."
- Same terms as the already accepted `../animations/cmu_mocap/` library.

## 2. KayKit Character Animations 1.1 (casting, weapon swings, unarmed kick/punch, spawn, throw)

- Author: Kay Lousberg, https://kaylousberg.com  (in the repo: `assets/incoming/kaykit/character-animations/`)
- Licence: **CC0 1.0**, http://creativecommons.org/publicdomain/zero/1.0/  Verbatim from `License.txt`:
  "This content is free to use in personal, educational and commercial projects."
  Credit is optional ("Kay Lousberg, www.kaylousberg.com").
- Clips are prefixed `KK_` in the libraries.

## 3. Already in the game, referenced (not re-exported) by the casting map in `README.md`

| source | licence | where |
|---|---|---|
| Quaternius Universal Animation Library 1 and 2 (`Spell_Simple_*`, `Punch_*`, `Sword_*`, `Melee_Hook`, `Hit_*`) | CC0 1.0, https://creativecommons.org/publicdomain/zero/1.0/ | `assets/incoming/quaternius/universal-animation-library*/License.txt` |
| Cat Prisbrey Modular Souls-like Template (`Magic_*`, `Souls_*`) | Unlicense | `assets/incoming/animations/souls_cat/LICENSE` |
| Mesh2Motion CC0 clips (`Attack_Ground_Pound`, `Fighting_*`, `Dodge_*`, `Backflip`) | CC0 | `assets/incoming/characters/README.md` |
| G6 CC0 casts (`G6_cast_*`, `G6_channel_*_Loop`, `G6_power_up*`) | CC0 | `assets/incoming/characters/_library/` |
| 100STYLE (`Style_*`) | CC BY 4.0 (Ian Mason, Sebastian Starke, Taku Komura, Univ. of Edinburgh; retarget rig by Daniel Holden), https://creativecommons.org/licenses/by/4.0/ | `assets/incoming/characters/100style-retarget/LICENSE.txt` |

## Looked at and NOT used

| source | reason |
|---|---|
| Mixamo | Adobe terms forbid redistributing the raw animation files inside an asset pack; the clips would ship as raw retargets. Skipped. |
| LaFAN1 (Ubisoft) | CC BY-NC-ND 4.0: non-commercial, no derivatives. |
| Bandai-Namco Research Motion dataset | CC BY-NC 4.0: non-commercial. |
| ActorCore / Reallusion motion packs | Paid, proprietary licence, no redistribution of raw motion. |
| Rokoko free motion library packs | Downloads sit behind an account and per-pack terms that were not verified in this pass; skipped rather than guessed. |
