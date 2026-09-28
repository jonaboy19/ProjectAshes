# Adaptive music and environment sounds: sources and licences

Used by `scripts/audio/music_bank.gd` (score) and `scripts/audio/environment_audio.gd` (spots, thunder).
All files are OGG Vorbis. Music is loudness-matched to the existing set (about -18 LUFS integrated), stems and spots sit lower.

| File | What | Source | Licence |
|---|---|---|---|
| `mus_boss.ogg` | boss loop, 0 to 145.28 s; loops back to bar 7 (`loop_offset` 14.75 s) through a 0.35 s crossfade | "Five Armies", Kevin MacLeod (incompetech.com) | **CC BY 4.0** |
| `stinger_victory.ogg` | final cadence, 84.98 to 94.6 s, faded | "Heroic Age", Kevin MacLeod (incompetech.com) | **CC BY 4.0** |
| `mus_danger_stalk.ogg` | danger / stalk loop, 10 to 56 s, with the tail equal-power crossfaded into the head (seamless) | "Dark and Mysterious" from "Fantasy Music and Drum Loops Pack", North Fantasy Music (opengameart.org/content/fantasy-music-and-drum-loops-pack) | **CC BY 4.0** |
| `stinger_discovery.ogg` | opening swell, 1.9 to 10.5 s, faded | "New Dawn" from the same pack, North Fantasy Music | **CC BY 4.0** |
| `perc_explore.ogg`, `perc_explore_03.ogg`, `perc_night.ogg` | percussion stems, same length as `music/mus_explore`, `mus_explore_03` and `mus_night`, rendered on each track's beat grid (onset analysis: 109.32, 101.98 and 110.0 bpm) | synthesized for the game (frame drum, taiko, shaker, rim) | own work, CC0 |
| `perc_danger.ogg` | taiko / rim loop, 78.26 bpm, exactly the length of `mus_danger_stalk` | synthesized for the game | own work, CC0 |
| `env/bird_chirp_01..04.ogg` | bird spots cut from two recordings | "Evening birds" (s1859), "Awakening birds" (s0222), Joseph Sardin, BigSoundBank | CC0 |
| `env/cricket_01..03.ogg` | cricket spots | "Crickets ambient noise (loopable)", Wolfgang_ (OpenGameArt) | CC0 |
| `env/thunder_near_01..02.ogg`, `env/thunder_far_01..02.ogg` | close crack (full band) and distant roll (slowed, low-passed) | "Thunder" (s2718), Joseph Sardin, BigSoundBank | CC0 |

`mus_explore_02` has no stem: its beat grid was too loose to lock drums to.

Required credit lines:

- "Five Armies", "Heroic Age" Kevin MacLeod (incompetech.com), Licensed under Creative Commons: By Attribution 4.0 License, http://creativecommons.org/licenses/by/4.0/
- Music by North Fantasy Music ("Dark and Mysterious", "New Dawn"), CC BY 4.0, https://opengameart.org/content/fantasy-music-and-drum-loops-pack
