# Region 1 audio (L17): area map, SFX events, loudness

Files live in `kingdom/assets/audio/region1/` (OGG Vorbis, **11.8 MB total**, 41 files). Sources and licences: `kingdom/assets/audio/region1/LICENSES.md`; credits: `kingdom/CREDITS.md`. Build scripts: `kingdom/tools/audio/r1_music.sh`, `r1_sfx.sh`, `r1_loopnorm.sh`, `r1_measure.sh`. Nothing here is wired yet: that is cloud work package **C12**.

Tone: warm, hopeful storybook medieval (lutes, fiddles, flutes, gentle strings). The rift-wilds theme is eerie but soft, never grimdark.

## 1. Area to music map (for C12)

All music tracks are seamless loops (4 s equal-power crossfade baked in; the seam step is within the normal sample-to-sample step for every track), so load them with `AudioStreamOggVorbis.loop = true` (as the director does for `amb_*`) rather than the play-once-then-pause playlist used for the older tracks. Suggested `MusicBank.CLIPS` names in the first column.

| Clip name | File (`res://assets/audio/region1/music/`) | Track | Play in (Region 1 sites) | Notes |
|---|---|---|---|---|
| `r1_village_day` | `mus_r1_village_day.ogg` | Folk Round (MacLeod) | Ashford village, Greenhollow, Crownstead crown farms, Old Mill, the farmland between them, daytime | Default "home" theme. Volume offset -3 dB like `town_day_a`. |
| `r1_guild_town` | `mus_r1_guild_town.ogg` | Minstrel Guild (MacLeod) | Silverford guild town (Masons and Runecarvers, Merchants' Hall, Adventurer Guild), Kingsreach markets, daytime | Busier, more festive than the village. |
| `r1_highwatch_keep` | `mus_r1_highwatch_keep.ogg` | Medieval Chateau (Nakarada) | Highwatch Keep, Greywatch Spear Hall, the Ember Lancers' yard, tournament grounds | Noble, steady. Use for keep interiors too, low-passed like the other interiors. |
| `r1_forest_glade` | `mus_r1_forest_glade.ogg` | Achaidh Cheide (MacLeod) | Stagborn Glade, NW woodland, forest roads, Veyl ranger camp | Celtic-flavoured, calm; the stagborn herd area. |
| `r1_rift_wilds` | `mus_r1_rift_wilds.ogg` | Lost Time (MacLeod) | Rift-touched wilds, the Ashen Scar, Rift's Edge Camp, high frontier threat in the west | Eerie, sparse. Pair with `amb_r1_scar_rift_loop`. |
| `r1_night` | `mus_r1_night.ogg` | Suonatore di Liuto (MacLeod) | Any outdoor Region 1 area after dusk (Sky3D time): quiet lute solo | Overrides the day theme; the existing `mus_night.ogg` can stay as a second night clip. |
| `r1_boss_warden` | `mus_r1_boss_warden.ogg` | Crusade (MacLeod) | Antlered Warden miniboss fight (Stagborn Glade). Also a fallback for the Scarbound Troll until a finale theme exists | Distinct from the existing `mus_boss` (Five Armies). |
| `r1_lament` | `mus_r1_lament.ogg` | Bittersweet (MacLeod), 90 s loop | Grief beats: Maren's last stand aftermath, losses in Acts II-III, quiet after-battle scenes | Cello, piano and choir at 73 bpm, tagged Calming/Somber; slow, sad but gentle, so it stays storybook. Replaces the `r1_night` fallback. |
| `r1_kindling` | `mus_r1_kindling.ogg` | Skye Cuillin (MacLeod), 100 s loop | Kindling Night lantern festival, tender family/hearth moments, Homecoming | Fiddle, whistle, harp and strings at 68 bpm, Celtic and Uplifting; warm and a little wistful. No hand-drum (none found under CC-BY). Replaces the `r1_village_day` fallback. |
| `r1_finale` | `mus_r1_finale.ogg` | Long Road Ahead (MacLeod), 146 s, play once (not a loop) | Finale after the Scarbound Troll and Rift seal; Homecoming card | Simple folk melody, "aftermath of a battle between good and evil", triumphant final third: triumphant but bittersweet. 4 s fade-out baked in. Set `loop = false`. Not the village_day melody rebuilt, but the folk tune fits the intent. Replaces the `r1_boss_warden` fallback. |

Suggested hook: a region + area -> clip table in `MusicBank.MOODS` (for example `&"r1_village_day": [&"r1_village_day"]`) and a crossfade of 2.5 s (`BED_FADE`) on area-border crossings, with about 8 s of hysteresis so walking along a border does not flip-flop. Combat still overrides area music (existing `combat` / `boss` moods); the Warden fight forces `r1_boss_warden`.

## 2. Loops and ambience

| Event / bed id | File (`res://assets/audio/region1/ambience/`) | Use | Level |
|---|---|---|---|
| `r1_rune_hum` | `sfx_r1_rune_hum_loop.ogg` (6 s, mono, exact-period loop) | 3D looping `AudioStreamPlayer3D` on each active runestone, max distance about 14 m; start at a random offset so neighbouring stones do not phase. Scale its volume with ward strength (decaying stones hum lower). | -26 LUFS-I, peak -16.9 dBFS: a quiet bed, use the player volume for +0 to +6 dB per stone |
| `r1_scar_rift_amb` | `amb_r1_scar_rift_loop.ogg` (24 s, stereo, crossfade loop) | Bed for the Ashen Scar and rift-touched wilds: register as `BEDS["scar_rift"]` and crossfade in with corruption level (the N2 mechanic) | -24 LUFS-I, same as the other `amb_*` beds |

## 3. One-shot SFX event names

Mono, peak-normalised to about -3 dBFS, so per-call volume works like the existing `sfx/` files. Suggested event name -> files (variants picked at random).

| Event | Files (`res://assets/audio/region1/sfx/`) | Trigger |
|---|---|---|
| `r1_ward_activate` | `sfx_r1_ward_activate.ogg` | A runestone is charged or a ward turns on |
| `r1_ward_break` | `sfx_r1_ward_break.ogg` | A ward fails or is broken (stone decays to 0, rift attack breaks the line) |
| `r1_glyph_carve` | `sfx_r1_glyph_carve_01.ogg`, `_02`, `_03` | One per stroke while the player carves a rune glyph; pick random, pitch +-4% |
| `r1_stagborn_bellow` | `sfx_r1_stagborn_bellow.ogg` | Stagborn elk herd call (every 20-60 s per herd, distance-culled at about 60 m), also the migration cue |
| `r1_stagborn_alert` | `sfx_r1_stagborn_alert_snort_01.ogg`, `_02` | A stagborn notices the player or a threat (before the antler charge) |
| `r1_stagborn_warden_roar` | `sfx_r1_stagborn_warden_roar.ogg` | Antlered Warden aggro / phase change (4.6 s; use the SFXFar bus for the long tail) |

## 4. Voice barks (`res://assets/audio/region1/voice/`, mono, `vo_r1_<m|f>_<kind>_<nn>.ogg`)

Non-verbal except where noted.

| Event | Male | Female |
|---|---|---|
| `r1_bark_effort` (swing, heavy attack, climb) | `m_effort_01`, `m_effort_02`, `m_effort_03` (03 is a big heavy-attack shout) | `f_effort_01`, `f_effort_02`, `f_effort_03` |
| `r1_bark_hurt` | `m_hurt_01`, `m_hurt_02` | `f_hurt_01`, `f_hurt_02`, `f_hurt_03` |
| `r1_bark_jump` | `m_jump_01` | `f_jump_01`, `f_jump_02` |
| `r1_bark_relief` (healed, safe, rest) | none | `f_relief_01`, `f_relief_02` |
| `r1_bark_greet` (short spoken hello) | `m_greet_01` | none in the CC0 pack |
| `r1_bark_yes` / `r1_bark_no` (spoken) | `m_yes_01` / `m_no_01` | none |
| `r1_bark_victory` (spoken cheer) | `m_victory_01` | none |

20 barks: 10 male, 10 female. Gap: female greeting, yes/no and victory lines (the only CC0 female pack found has none); logged in the backlog of `docs/STATUS_LOCAL.md`.

## 5. Loudness table

Measured with ffmpeg `ebur128` on the shipped OGG files (`kingdom/tools/audio/r1_measure.sh`, raw CSV `kingdom/assets/audio/region1/loudness_r1.csv`).

- Music target **-16 LUFS integrated, +-1**: all ten measure **-16.1 to -16.3** (the three story cues: lament -16.2, kindling -16.2, finale -16.3; peaks -3.7, -4.5, -1.7 dBFS).
- Loops match the existing ambience beds: rift bed -24.0, rune hum -26.0 LUFS-I.
- One-shots are peak-normalised to **-3 dBFS**; after Vorbis they measure -2.0 to -3.8 dBFS.
- Music was normalised with a pure gain (a lookahead limiter would put a fade-in at the loop seam) plus a mild sine soft-clip. `mus_r1_night` peaks at -0.8 dBFS because the lute source is very dynamic; lower its clip volume by 1 dB in `MusicBank` if a device clips.
- Clips shorter than 0.4 s are measured after padding to 1 s, so their LUFS-I reads lower than they sound; judge those by peak.

| File | s | KB | LUFS-I | peak dBFS (true/sample) |
|---|---:|---:|---:|---|
| `ambience/amb_r1_scar_rift_loop.ogg` | 24.00 | 208 | -24.0 | -14.4 / -14.4 |
| `ambience/sfx_r1_rune_hum_loop.ogg` | 6.00 | 23 | -26.0 | -16.9 / -16.9 |
| `music/mus_r1_boss_warden.ogg` | 110.00 | 1303 | -16.2 | -2.9 / -2.9 |
| `music/mus_r1_forest_glade.ogg` | 100.00 | 1084 | -16.2 | -1.4 / -1.4 |
| `music/mus_r1_guild_town.ogg` | 100.00 | 1227 | -16.1 | -2.0 / -2.6 |
| `music/mus_r1_highwatch_keep.ogg` | 100.00 | 1212 | -16.1 | -3.8 / -3.8 |
| `music/mus_r1_night.ogg` | 100.00 | 1119 | -16.2 | -0.8 / -0.8 |
| `music/mus_r1_rift_wilds.ogg` | 100.00 | 947 | -16.1 | -4.6 / -4.6 |
| `music/mus_r1_village_day.ogg` | 100.00 | 1130 | -16.2 | -1.4 / -1.4 |
| `sfx/sfx_r1_glyph_carve_01.ogg` | 0.42 | 7 | -17.4 | -3.6 / -3.6 |
| `sfx/sfx_r1_glyph_carve_02.ogg` | 0.55 | 8 | -16.0 | -3.1 / -3.1 |
| `sfx/sfx_r1_glyph_carve_03.ogg` | 0.36 | 7 | -16.5 | -3.4 / -3.8 |
| `sfx/sfx_r1_stagborn_alert_snort_01.ogg` | 0.72 | 9 | -18.5 | -3.7 / -3.7 |
| `sfx/sfx_r1_stagborn_alert_snort_02.ogg` | 0.86 | 9 | -18.9 | -3.3 / -3.3 |
| `sfx/sfx_r1_stagborn_bellow.ogg` | 3.42 | 26 | -13.7 | -3.1 / -3.1 |
| `sfx/sfx_r1_stagborn_warden_roar.ogg` | 4.63 | 37 | -16.1 | -3.2 / -3.2 |
| `sfx/sfx_r1_ward_activate.ogg` | 2.04 | 13 | -16.2 | -2.7 / -2.8 |
| `sfx/sfx_r1_ward_break.ogg` | 1.66 | 15 | -23.3 | -2.8 / -3.2 |
| `voice/vo_r1_f_effort_01.ogg` | 0.32 | 6 | -18.5 | -2.8 / -2.8 |
| `voice/vo_r1_f_effort_02.ogg` | 0.35 | 6 | -18.1 | -2.7 / -2.8 |
| `voice/vo_r1_f_effort_03.ogg` | 0.37 | 7 | -21.4 | -3.5 / -3.5 |
| `voice/vo_r1_f_hurt_01.ogg` | 0.29 | 6 | -20.6 | -3.5 / -3.6 |
| `voice/vo_r1_f_hurt_02.ogg` | 0.32 | 6 | -21.1 | -2.7 / -2.8 |
| `voice/vo_r1_f_hurt_03.ogg` | 0.35 | 6 | -19.8 | -3.4 / -3.4 |
| `voice/vo_r1_f_jump_01.ogg` | 0.20 | 5 | -22.5 | -2.6 / -2.7 |
| `voice/vo_r1_f_jump_02.ogg` | 0.21 | 5 | -19.3 | -3.0 / -3.1 |
| `voice/vo_r1_f_relief_01.ogg` | 0.45 | 7 | -17.7 | -2.9 / -2.9 |
| `voice/vo_r1_f_relief_02.ogg` | 0.61 | 9 | -16.7 | -3.0 / -3.1 |
| `voice/vo_r1_m_effort_01.ogg` | 0.28 | 6 | -21.0 | -2.4 / -2.4 |
| `voice/vo_r1_m_effort_02.ogg` | 0.44 | 7 | -21.3 | -3.5 / -3.5 |
| `voice/vo_r1_m_effort_03.ogg` | 0.62 | 8 | -17.7 | -2.0 / -2.1 |
| `voice/vo_r1_m_greet_01.ogg` | 0.39 | 7 | -21.5 | -2.7 / -2.8 |
| `voice/vo_r1_m_hurt_01.ogg` | 0.48 | 8 | -20.5 | -3.2 / -3.2 |
| `voice/vo_r1_m_hurt_02.ogg` | 0.61 | 9 | -19.4 | -2.8 / -2.8 |
| `voice/vo_r1_m_jump_01.ogg` | 0.24 | 5 | -24.2 | -3.3 / -3.3 |
| `voice/vo_r1_m_no_01.ogg` | 0.57 | 9 | -18.7 | -3.0 / -3.0 |
| `voice/vo_r1_m_victory_01.ogg` | 1.10 | 14 | -18.8 | -2.8 / -2.9 |
| `voice/vo_r1_m_yes_01.ogg` | 0.58 | 8 | -20.6 | -3.5 / -3.6 |

## 6. Loop-seam and format checks

- Seam step (absolute difference between the last and the first decoded sample) against the 99th percentile of normal sample-to-sample steps: all 9 loops pass. Largest music seam 0.022 (p99 0.034 to 0.062), rune hum 0.0002, rift bed 0.002.
- Formats: music stereo 44.1 kHz Vorbis q2 (about 90-105 kbps); loops and one-shots mono (rift bed stereo) 44.1 kHz q4. Total 8.3 MB.
- Not verified: listening in the engine (no Godot import on this machine, the disk is tight). Track mood was chosen from titles, descriptions and loudness/spectrum stats, not by ear. C12 should audition each track in its area and swap the file if it feels off.
