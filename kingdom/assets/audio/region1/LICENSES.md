# Region 1 audio (L17): sources and licences

All licence pages were fetched on **2026-09-29** (or, where noted, recorded in the pack's `LICENSE` file in `assets/incoming/`). No account or login was needed for any download. Commercial use is allowed for every row; no NC, no ND, no SA.

Build scripts (reproducible, run from the repo root): `kingdom/tools/audio/r1_music.sh`, `kingdom/tools/audio/r1_sfx.sh`, `kingdom/tools/audio/r1_loopnorm.sh`; numbers: `kingdom/tools/audio/r1_measure.sh` -> `loudness_r1.csv`.

## Music (10 tracks, `music/`)

| File | Track | Author | Licence | Source / licence page |
|---|---|---|---|---|
| `mus_r1_village_day.ogg` | "Folk Round" | Kevin MacLeod | **CC BY 4.0** | https://incompetech.com/music/royalty-free/music.html · terms: https://incompetech.com/music/royalty-free/faq.html (CC BY 4.0, commercial use allowed) |
| `mus_r1_guild_town.ogg` | "Minstrel Guild" | Kevin MacLeod | **CC BY 4.0** | incompetech.com (same terms) |
| `mus_r1_highwatch_keep.ogg` | "Medieval Chateau" | Alexander Nakarada (CreatorChords) | **CC BY 4.0** | https://www.free-stock-music.com/alexander-nakarada-medieval-chateau.html (licence field "CC BY 4.0", commercial use allowed) |
| `mus_r1_forest_glade.ogg` | "Achaidh Cheide" | Kevin MacLeod | **CC BY 4.0** | incompetech.com |
| `mus_r1_rift_wilds.ogg` | "Lost Time" | Kevin MacLeod | **CC BY 4.0** | incompetech.com |
| `mus_r1_night.ogg` | "Suonatore di Liuto" | Kevin MacLeod | **CC BY 4.0** | incompetech.com |
| `mus_r1_boss_warden.ogg` | "Crusade" | Kevin MacLeod | **CC BY 4.0** | incompetech.com |
| `mus_r1_lament.ogg` | "Bittersweet" | Kevin MacLeod | **CC BY 4.0** | https://incompetech.com/music/royalty-free/faq.html (CC BY 4.0, commercial use allowed; verified 2026-09-29) |
| `mus_r1_kindling.ogg` | "Skye Cuillin" | Kevin MacLeod | **CC BY 4.0** | incompetech.com (same terms) |
| `mus_r1_finale.ogg` | "Long Road Ahead" | Kevin MacLeod | **CC BY 4.0** | incompetech.com (same terms) |

Originals are kept in `assets/incoming/incompetech/` (with `LICENSE.txt`) and `assets/incoming/music-cc-by/`. Credit lines are in `kingdom/CREDITS.md` (Region 1 audio section). Processing: 4 s equal-power crossfade loop of the first 100 s (110 s for the boss), gain-normalised to -16 LUFS, Vorbis q2 stereo.

## SFX, barks, ambience

| Files | Source | Author | Licence | Licence page |
|---|---|---|---|---|
| `voice/vo_r1_m_*` (10 male barks) | "Voice Clip Pack - Male Adventurer RPG" | wolfwoot (asks to be credited as Brandon Song) | **CC0** | https://opengameart.org/content/voice-clip-pack-male-adventurer-rpg (licence field CC0) |
| `voice/vo_r1_f_*` (10 female barks) | "Female RPG Voice Starter Pack" (Type 2 and 3) | cicifyre | **CC0** | https://opengameart.org/content/female-rpg-voice-starter-pack (licence field CC0) |
| `sfx/sfx_r1_stagborn_*` | BigSoundBank sounds s2384 (cow), s0546 (cow), s1881 and s1883 (big cat), s1543 (horse breath; via the shipped `sfx/animals/horse_snort.ogg`), pitched down and layered | Joseph Sardin | **CC0** | https://bigsoundbank.com/droit.html ("Use, including for commercial purposes. Without any restrictions", CC0 1.0) |
| `sfx/sfx_r1_ward_break.ogg` (glass layer) | "100 CC0 SFX", `glass_04` | rubberduck | **CC0** | https://opengameart.org/content/100-cc0-sfx |
| `sfx/sfx_r1_glyph_carve_*`, `sfx/sfx_r1_ward_activate.ogg`, `sfx/sfx_r1_ward_break.ogg` (synth layers), `ambience/sfx_r1_rune_hum_loop.ogg`, `ambience/amb_r1_scar_rift_loop.ogg` | Synthesised for the game with ffmpeg (`aevalsrc` sines, noise, filters), no third-party audio | Rising Ashes | own work, CC0 | n/a |

Female bark sources kept in `assets/incoming/opengameart/sfx/female-rpg-voice-starter-cicifyre/` (10 clips + LICENSE.txt); the male pack was already in `assets/incoming/opengameart/sfx/voice-clip-pack-male-adventurer-rpg/`.

Not used: "Female RPG Character Voice Pack" (RiddlesYouThis, CC BY 3.0, spoken lines, not needed). Pixabay, Sonniss GDC bundles and freesound were skipped (login or sign-up needed for downloads, or terms restricting redistribution while this repo is public; not re-checked this session because the sources above covered every need).
