# Souls-like foley SFX (Cat Prisbrey, CC0 / Unlicense)

54 one-shots that fill gaps in `sfx/combat` and `sfx/world`: metal clang, wood clack, light
and heavy swings, blunt hits, cloth rustle, door and gate creaks, lever ratchets, and potion
cork and slosh. They are not registered with `AudioDirector` yet: add the groups below.

| | |
|---|---|
| Source | https://github.com/catprisbrey/Cats-Godot4-Modular-Souls-like-Template, `audio/SoundFX/` |
| Licence | CC0 per the author's README ("All CC0 content free to be used as you wish without attribution"); the repo is under the **Unlicense** (`LICENSE`). Licence URL: https://github.com/catprisbrey/Cats-Godot4-Modular-Souls-like-Template/blob/main/LICENSE |
| Credit | not required; credited in CREDITS.md |
| Format | converted by `tools/anim/convert_souls_sfx.py`: 48 kHz stereo WAV -> **mono 44.1 kHz Ogg Vorbis (~q4)**, silence trimmed at -45 dB rel., 3 ms fade-in / 35 ms fade-out, **peak -3 dBFS**. Not yet loudness-matched per group like `../README.md` (combat -14, foley -18 LUFS max momentary); run the audio pipeline or set `volume_db` per group |
| Not taken | `click`, `fire` loops, `hit_1-4`, `hit_metal` (we have `sfx/combat/hit_metal_*`), `hit_wet` (gory), `shuffle`, `step`, `voice_hurt`, `special/Spawn01` |

## Suggested AudioDirector groups

| group | files | use |
|---|---|---|
| `clang` | `clang_01..04` | metal-on-metal clash: parry (`Parry_Quick`), blocked sword hit, shield block |
| `clack` | `clack_01..05` | wood clack: staff/stick hits, wooden shield, training dummy, kata sparring |
| `swish` | `swish_01..06` | light weapon / fist / kick swing (light attacks, karate) |
| `swoosh` | `swoosh_01..05` | heavy swing, roll, cloak, spell release (`Magic_Cast_*`) |
| `hit_blunt` | `hit_blunt_01..06` | fist/club/kick impact, `Shield_Bash`, body fall (`Lie_Down`, knockdown) |
| `cloth` | `cloth_01..09` | armour/cloth rustle: dodge, guard up, equip, stand up, sit |
| `creak` | `creak_01..06` | door / gate / chest hinge (`Open_Door`, `Open_Gate`, `Open_Chest`) |
| `ratchet` | `ratchet_01..03` | lever pull, winch, portcullis (`Lever_Pull_*`) |
| `cork` | `cork_01..05` | potion uncork (`Drink_Potion` start) |
| `slosh` | `slosh_01..05` | potion drink / liquid (`Drink_Potion`) |

## Files (duration in seconds, source file in `audio/SoundFX/`)

| file | s | source |
|---|---:|---|
| `clang_01.ogg` | 0.36 | clang/clang_1.wav |
| `clang_02.ogg` | 0.43 | clang/clang_2.wav |
| `clang_03.ogg` | 0.33 | clang/clang_3.wav |
| `clang_04.ogg` | 0.32 | clang/clang_4.wav |
| `clack_01.ogg` | 0.52 | clack/clack_1.wav |
| `clack_02.ogg` | 0.54 | clack/clack_2.wav |
| `clack_03.ogg` | 0.83 | clack/clack_3.wav |
| `clack_04.ogg` | 0.66 | clack/clack_4.wav |
| `clack_05.ogg` | 0.82 | clack/clack_5.wav |
| `swish_01.ogg` | 0.46 | swish/swish_1.wav |
| `swish_02.ogg` | 0.42 | swish/swish_2.wav |
| `swish_03.ogg` | 0.37 | swish/swish_3.wav |
| `swish_04.ogg` | 0.39 | swish/swish_4.wav |
| `swish_05.ogg` | 0.41 | swish/swish_5.wav |
| `swish_06.ogg` | 0.49 | swish/swish_6.wav |
| `swoosh_01.ogg` | 0.68 | swoosh/swoosh_1.wav |
| `swoosh_02.ogg` | 0.56 | swoosh/swoosh_2.wav |
| `swoosh_03.ogg` | 0.43 | swoosh/swoosh_3.wav |
| `swoosh_04.ogg` | 0.45 | swoosh/swoosh_4.wav |
| `swoosh_05.ogg` | 0.52 | swoosh/swoosh_5.wav |
| `hit_blunt_01.ogg` | 0.30 | hit/hit_blunt_01.wav |
| `hit_blunt_02.ogg` | 0.35 | hit/hit_blunt_02.wav |
| `hit_blunt_03.ogg` | 0.37 | hit/hit_blunt_03.wav |
| `hit_blunt_04.ogg` | 0.38 | hit/hit_blunt_04.wav |
| `hit_blunt_05.ogg` | 0.34 | hit/hit_blunt_05.wav |
| `hit_blunt_06.ogg` | 0.29 | hit/hit_blunt_06.wav |
| `cloth_01.ogg` | 0.59 | cloth/cloth_01.wav |
| `cloth_02.ogg` | 0.41 | cloth/cloth_02.wav |
| `cloth_03.ogg` | 0.56 | cloth/cloth_03.wav |
| `cloth_04.ogg` | 0.64 | cloth/cloth_04.wav |
| `cloth_05.ogg` | 0.56 | cloth/cloth_05.wav |
| `cloth_06.ogg` | 0.58 | cloth/cloth_06.wav |
| `cloth_07.ogg` | 0.82 | cloth/cloth_07.wav |
| `cloth_08.ogg` | 0.61 | cloth/cloth_08.wav |
| `cloth_09.ogg` | 0.81 | cloth/cloth_09.wav |
| `creak_01.ogg` | 1.24 | creak/creak_1.wav |
| `creak_02.ogg` | 1.45 | creak/creak_2.wav |
| `creak_03.ogg` | 0.85 | creak/creak_3.wav |
| `creak_04.ogg` | 0.65 | creak/creak_4.wav |
| `creak_05.ogg` | 0.38 | creak/creak_5.wav |
| `creak_06.ogg` | 0.47 | creak/creak_6.wav |
| `ratchet_01.ogg` | 0.72 | ratchet/ratchet_1.wav |
| `ratchet_02.ogg` | 0.99 | ratchet/ratchet_2.wav |
| `ratchet_03.ogg` | 0.34 | ratchet/ratchet_3.wav |
| `cork_01.ogg` | 0.60 | cork/cork_01.wav |
| `cork_02.ogg` | 0.59 | cork/cork_02.wav |
| `cork_03.ogg` | 0.61 | cork/cork_03.wav |
| `cork_04.ogg` | 1.33 | cork/cork_04.wav |
| `cork_05.ogg` | 0.84 | cork/cork_05.wav |
| `slosh_01.ogg` | 0.77 | slosh/slosh_01.wav |
| `slosh_02.ogg` | 0.76 | slosh/slosh_2.wav |
| `slosh_03.ogg` | 0.81 | slosh/slosh_3.wav |
| `slosh_04.ogg` | 1.18 | slosh/slosh_4.wav |
| `slosh_05.ogg` | 1.05 | slosh/slosh_5.wav |
