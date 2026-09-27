# Rising Ashes: game audio

Game-ready sound set, built by `tools/audio/build_audio.py` from licence-checked sources in `assets/incoming/` and played by `scripts/audio/audio_director.gd` (the `Audio` autoload). **205 files, 24.4 MB** (OGG Vorbis).

## Processing

| Kind | Format | Loudness | Other |
|---|---|---|---|
| Music (`music/`) | stereo 44.1 kHz, Vorbis q4 | integrated **-18 LUFS**, true peak <= -1 dBTP (limiter at -2.6 dBFS to absorb Vorbis overshoot) | RandomMind tracks are the authors' seamless loops; the combat stinger is the first 7 s of *Medieval Standoff* with a 2 s fade |
| Ambience beds (`ambience/amb_*`) | stereo 44.1 kHz, q4 | integrated **-24 LUFS**, gentle 3:1 bed compression, peak <= -3.4 dBFS | layered from 1-3 recordings, mono sources widened (right channel read 5-13 s later), **seamless loop**: the tail after the loop length is equal-power crossfaded into the head (3-4 s), so sample N-1 flows into sample 0 |
| One-shots (`sfx/`, `ui/`, `ambience/spots/`) | mono, 44.1 kHz (creatures and animals 32 kHz), q4 | matched on **max momentary loudness** per group (combat/creature -14, voice -16, animal -17, foley -18, UI -19, spot -20, footstep -21 LUFS) and capped at **-3 dBFS peak** (limiter at -3.4 dBFS) | leading/trailing silence trimmed (-45 dB rel.), 3 ms fade-in, 30-40 ms fade-out; multi-event takes auto-sliced into single events |

Very short transients (clicks, footsteps, metal hits) hit the -3 dBFS peak cap before the loudness target, so they measure quieter in LUFS than longer sounds; that's expected (perceived loudness of a 100 ms click is lower). The director applies a per-call volume on top.

`smithy` measures -27.5 LUFS because fire crackle peaks hit the limiter; the director plays it +3 dB.

## Loop points

Every `ambience/amb_*.ogg` loops over the whole file (loop start 0, loop end = file length, listed below). `AudioDirector` sets `AudioStreamOggVorbis.loop = true` at load, beds start at a random offset. Music: `mus_tavern` and `mus_combat` loop; other tracks play once, then a 20-90 s pause. Seam check (|first - last sample|) is within the normal sample-to-sample step for every bed.

## Sound list

Columns: duration (s), size (KB), integrated LUFS, max momentary LUFS, true peak (dBTP), source and licence.


### music/

| File | s | KB | LUFS-I | LUFS-M max | dBTP | Source | Licence |
|---|---|---|---|---|---|---|---|
| `music/mus_combat.ogg` | 95.85 | 1460.6 | -18.0 | -14.9 | -8.0 | [cynicmusic_battleThemeA.mp3](https://opengameart.org/content/battle-theme-a) | CC0 |
| `music/mus_combat_stinger.ogg` | 7.00 | 77.1 | -18.2 | -11.6 | -2.0 | [medieval_standoff.ogg](https://opengameart.org/content/medieval-standoff) | CC0 |
| `music/mus_explore.ogg` | 57.73 | 728.1 | -18.1 | -13.9 | -6.1 | [randommind_The_Bards_Tale.ogg](https://opengameart.org/content/medieval-the-bards-tale) | CC0 |
| `music/mus_explore_02.ogg` | 80.75 | 1022.6 | -18.0 | -12.8 | -3.7 | [randommind_Kings_Feast_0.ogg](https://opengameart.org/content/medieval-kings-feast) | CC0 |
| `music/mus_explore_03.ogg` | 146.38 | 2161.7 | -18.5 | -14.0 | -1.2 | [medieval_theme_music.ogg](https://opengameart.org/content/medieval-theme) | CC0 |
| `music/mus_night.ogg` | 161.52 | 3396.1 | -18.1 | -16.0 | -5.3 | [Of Far Different Nature x John Dowland - If my Complaints Could Passions Move_0.mp3](https://opengameart.org/content/historic-renaissance-music-from-1597-if-my-complaints-could-passions-move-by-john-dowland) | CC0 |
| `music/mus_tavern.ogg` | 49.95 | 646.1 | -18.1 | -14.6 | -2.9 | [randommind_The_Old_Tower_Inn.ogg](https://opengameart.org/content/medieval-the-old-tower-inn) | CC0 |
| `music/mus_village_day.ogg` | 64.86 | 877.4 | -18.1 | -16.1 | -8.7 | [randommind_Market_Day.ogg](https://opengameart.org/content/medieval-market-day) | CC0 |
| `music/mus_village_day_02.ogg` | 56.31 | 704.2 | -18.0 | -15.1 | -6.0 | [randommind_Minstrel_Dance_0.ogg](https://opengameart.org/content/medieval-minstrel-dance) | CC0 |

### ambience/

| File | s | KB | LUFS-I | LUFS-M max | dBTP | Source | Licence |
|---|---|---|---|---|---|---|---|
| `ambience/amb_camp.ogg` | 45.00 | 737.1 | -24.2 | -22.7 | -2.2 | [strong_wind_and_trees_1_s1450.ogg](https://bigsoundbank.com/strong-wind-and-trees-1-s1450.html)<br>[fire_foley_s3322.ogg](https://bigsoundbank.com/fire-foley-s3322.html) | CC0 |
| `ambience/amb_creek.ogg` | 55.00 | 920.8 | -24.2 | -23.2 | -5.1 | [small_stream_s0823.ogg](https://bigsoundbank.com/small-stream-s0823.html)<br>[evening_birds_s1859.ogg](https://bigsoundbank.com/evening-birds-s1859.html) | CC0 |
| `ambience/amb_danger.ogg` | 55.00 | 754.4 | -24.1 | -22.3 | -12.2 | [strong_wind_and_trees_1_s1450.ogg](https://bigsoundbank.com/strong-wind-and-trees-1-s1450.html)<br>[whistling_of_the_wind_1_s0147.ogg](https://bigsoundbank.com/whistling-of-the-wind-1-s0147.html) | CC0 |
| `ambience/amb_forest_day.ogg` | 60.00 | 1026.1 | -24.3 | -19.9 | -3.1 | [forest_and_stream_1_s2713.ogg](https://bigsoundbank.com/forest-and-stream-1-s2713.html)<br>[forest_wind_in_the_trees_s0904.ogg](https://bigsoundbank.com/forest-wind-in-the-trees-s0904.html) | CC0 |
| `ambience/amb_forest_night.ogg` | 60.00 | 1022.3 | -24.3 | -23.6 | -11.9 | [wolfgang_crickets_loop.mp3](https://opengameart.org/content/crickets-ambient-noise-loopable)<br>[forest_wind_in_the_trees_s0904.ogg](https://bigsoundbank.com/forest-wind-in-the-trees-s0904.html)<br>[small_stream_s0823.ogg](https://bigsoundbank.com/small-stream-s0823.html) | CC0 |
| `ambience/amb_healer.ogg` | 45.00 | 699.1 | -24.1 | -17.7 | -4.1 | [fireplace_1_s0030.ogg](https://bigsoundbank.com/fireplace-1-s0030.html)<br>[whistling_of_the_wind_1_s0147.ogg](https://bigsoundbank.com/whistling-of-the-wind-1-s0147.html) | CC0 |
| `ambience/amb_meadow_day.ogg` | 55.00 | 819.3 | -24.2 | -19.9 | -10.0 | [awakening_birds_s0222.ogg](https://bigsoundbank.com/awakening-birds-s0222.html)<br>[wind_in_a_tree_s0659.ogg](https://bigsoundbank.com/wind-in-a-tree-s0659.html) | CC0 |
| `ambience/amb_rain.ogg` | 41.00 | 615.0 | -24.1 | -22.9 | -9.9 | [3.ogg](https://opengameart.org/content/rain-loopable) | CC0 |
| `ambience/amb_smithy.ogg` | 30.00 | 618.5 | -27.5 | -23.5 | -2.8 | [big_branching_fire_1_s0987.ogg](https://bigsoundbank.com/big-branching-fire-1-s0987.html)<br>[fireplace_1_s0030.ogg](https://bigsoundbank.com/fireplace-1-s0030.html) | CC0 |
| `ambience/amb_storm.ogg` | 36.00 | 520.2 | -24.0 | -17.3 | -5.0 | [storm_and_rain_3_s2717.ogg](https://bigsoundbank.com/storm-and-rain-3-s2717.html) | CC0 |
| `ambience/amb_tavern.ogg` | 50.00 | 821.2 | -24.1 | -17.2 | -4.4 | [small_restaurant_conversations_s3542.ogg](https://bigsoundbank.com/small-restaurant-conversations-s3542.html)<br>[fireplace_2_s0031.ogg](https://bigsoundbank.com/fireplace-2-s0031.html) | CC0 |
| `ambience/amb_village_day.ogg` | 60.00 | 885.7 | -24.3 | -20.3 | -9.3 | [awakening_birds_s0222.ogg](https://bigsoundbank.com/awakening-birds-s0222.html)<br>[crowd_of_50_60_people_1_s3515.ogg](https://bigsoundbank.com/crowd-of-50-60-people-1-s3515.html)<br>[wind_in_a_tree_s0659.ogg](https://bigsoundbank.com/wind-in-a-tree-s0659.html) | CC0 |
| `ambience/amb_village_night.ogg` | 60.00 | 1080.2 | -24.4 | -21.4 | -12.6 | [campaign_at_night_4_s1880.ogg](https://bigsoundbank.com/campaign-at-night-4-s1880.html)<br>[wind_in_a_tree_s0659.ogg](https://bigsoundbank.com/wind-in-a-tree-s0659.html) | CC0 |
| `ambience/amb_wind.ogg` | 55.00 | 818.6 | -24.2 | -20.4 | -4.6 | [strong_wind_in_a_village_s0625.ogg](https://bigsoundbank.com/strong-wind-in-a-village-s0625.html) | CC0 |

### ambience/spots/

| File | s | KB | LUFS-I | LUFS-M max | dBTP | Source | Licence |
|---|---|---|---|---|---|---|---|
| `ambience/spots/bellows.ogg` | 2.12 | 19.2 | -20.9 | -18.1 | -4.6 | noise | own work |
| `ambience/spots/bird_blackbird.ogg` | 2.11 | 17.7 | -23.0 | -20.1 | -13.1 | [common_blackbird_2_s3474.ogg](https://bigsoundbank.com/common-blackbird-2-s3474.html) | CC0 |
| `ambience/spots/church_bell.ogg` | 17.47 | 162.4 | -27.3 | -20.1 | -8.5 | [church_bell_s0135.ogg](https://bigsoundbank.com (sound 0135)) | CC0 |
| `ambience/spots/dog_distant_01.ogg` | 0.83 | 8.0 | -23.4 | -20.0 | -3.7 | [barking_dog_s0916.ogg](https://bigsoundbank.com/barking-dog-s0916.html) | CC0 |
| `ambience/spots/dog_distant_02.ogg` | 0.79 | 8.1 | -23.4 | -20.0 | -7.0 | [barking_dog_s0916.ogg](https://bigsoundbank.com/barking-dog-s0916.html) | CC0 |
| `ambience/spots/dog_distant_03.ogg` | 0.36 | 5.9 | -23.7 | -20.0 | -4.8 | [barking_dog_s0916.ogg](https://bigsoundbank.com/barking-dog-s0916.html) | CC0 |
| `ambience/spots/growl_distant.ogg` | 8.34 | 44.3 | -23.7 | -20.0 | -8.4 | [growling_cat_3_s1887.ogg](https://bigsoundbank.com/growling-cat-3-s1887.html) | CC0 |
| `ambience/spots/hammer_distant_01.ogg` | 1.05 | 9.8 | -23.8 | -20.0 | -10.2 | [anvil_blacksmith_1_s3589.ogg](https://bigsoundbank.com (sound 3589)) | CC0 |
| `ambience/spots/hammer_distant_02.ogg` | 1.07 | 10.9 | -23.9 | -20.0 | -5.9 | [anvil_blacksmith_1_s3589.ogg](https://bigsoundbank.com (sound 3589)) | CC0 |
| `ambience/spots/hammer_distant_03.ogg` | 0.95 | 9.7 | -25.1 | -20.1 | -4.7 | [anvil_blacksmith_1_s3589.ogg](https://bigsoundbank.com (sound 3589)) | CC0 |
| `ambience/spots/mug_knock_01.ogg` | 0.73 | 10.0 | -22.8 | -20.3 | -4.0 | [dishes_01.ogg](https://opengameart.org/content/100-cc0-sfx) | CC0 |
| `ambience/spots/mug_knock_02.ogg` | 0.64 | 9.6 | -23.3 | -20.5 | -5.1 | [dishes_03.ogg](https://opengameart.org/content/100-cc0-sfx) | CC0 |
| `ambience/spots/owl_01.ogg` | 6.30 | 37.9 | -23.7 | -20.0 | -12.2 | [tawny_owl_1_s1763.ogg](https://bigsoundbank.com/tawny-owl-1-s1763.html) | CC0 |
| `ambience/spots/owl_02.ogg` | 6.34 | 36.5 | -24.6 | -20.0 | -13.9 | [tawny_owl_2_s1764.ogg](https://bigsoundbank.com/tawny-owl-2-s1764.html) | CC0 |
| `ambience/spots/owl_03.ogg` | 8.97 | 76.1 | -25.4 | -20.1 | -10.7 | [owls_s0429.ogg](https://bigsoundbank.com/owls-s0429.html) | CC0 |
| `ambience/spots/page_turn_01.ogg` | 1.60 | 18.3 | -23.5 | -20.3 | -3.3 | [pages_that_turn_s0493.ogg](https://bigsoundbank.com/pages-that-turn-s0493.html) | CC0 |
| `ambience/spots/page_turn_02.ogg` | 1.18 | 14.8 | -26.8 | -23.4 | -3.3 | [pages_that_turn_s0493.ogg](https://bigsoundbank.com/pages-that-turn-s0493.html) | CC0 |
| `ambience/spots/page_turn_03.ogg` | 1.08 | 13.9 | -28.7 | -27.6 | -3.8 | [pages_that_turn_s0493.ogg](https://bigsoundbank.com/pages-that-turn-s0493.html) | CC0 |
| `ambience/spots/page_turn_04.ogg` | 0.45 | 7.1 | -30.5 | -28.9 | -3.9 | [turned_page_s0164.ogg](https://bigsoundbank.com/turned-page-s0164.html) | CC0 |
| `ambience/spots/rope_creak.ogg` | 3.50 | 48.6 | -30.2 | -26.3 | -4.1 | [rope_s3417.ogg](https://bigsoundbank.com/rope-s3417.html) | CC0 |
| `ambience/spots/thunder.ogg` | 20.84 | 138.9 | -21.6 | -17.0 | -3.2 | [thunder_s2718.ogg](https://bigsoundbank.com/thunder-s2718.html) | CC0 |
| `ambience/spots/well_bucket_01.ogg` | 1.06 | 12.6 | -29.2 | -22.7 | -3.4 | [metal_bucket_s0543.ogg](https://bigsoundbank.com/metal-bucket-s0543.html) | CC0 |
| `ambience/spots/well_bucket_02.ogg` | 0.92 | 11.2 | -29.2 | -22.6 | -3.3 | [metal_bucket_s0543.ogg](https://bigsoundbank.com/metal-bucket-s0543.html) | CC0 |
| `ambience/spots/well_bucket_03.ogg` | 0.89 | 11.2 | -25.4 | -21.6 | -3.8 | [metal_bucket_s0543.ogg](https://bigsoundbank.com/metal-bucket-s0543.html) | CC0 |
| `ambience/spots/wolf_howl_distant.ogg` | 2.41 | 17.3 | -22.4 | -19.9 | -10.3 | [dog_singing_1_s2450.ogg](https://bigsoundbank.com/dog-singing-1-s2450.html) | CC0 |

### sfx/footsteps/

| File | s | KB | LUFS-I | LUFS-M max | dBTP | Source | Licence |
|---|---|---|---|---|---|---|---|
| `sfx/footsteps/step_cobble_01.ogg` | 0.19 | 5.3 | -29.0 | -26.8 | -3.2 | [0.ogg](https://opengameart.org/content/footsteps-on-different-surfaces) | **CC-BY 3.0** |
| `sfx/footsteps/step_cobble_02.ogg` | 0.10 | 4.6 | -22.7 | -22.7 | -4.2 | [1.ogg](https://opengameart.org/content/footsteps-on-different-surfaces) | **CC-BY 3.0** |
| `sfx/footsteps/step_cobble_03.ogg` | 0.25 | 5.7 | -23.6 | -21.5 | -3.5 | [2.ogg](https://opengameart.org/content/footsteps-on-different-surfaces) | **CC-BY 3.0** |
| `sfx/footsteps/step_cobble_04.ogg` | 0.16 | 5.0 | -26.4 | -26.4 | -3.0 | [3.ogg](https://opengameart.org/content/footsteps-on-different-surfaces) | **CC-BY 3.0** |
| `sfx/footsteps/step_cobble_05.ogg` | 0.24 | 5.5 | -28.5 | -25.9 | -4.1 | [4.ogg](https://opengameart.org/content/footsteps-on-different-surfaces) | **CC-BY 3.0** |
| `sfx/footsteps/step_cobble_06.ogg` | 0.23 | 5.8 | -26.0 | -23.4 | -3.6 | [5.ogg](https://opengameart.org/content/footsteps-on-different-surfaces) | **CC-BY 3.0** |
| `sfx/footsteps/step_dirt_01.ogg` | 0.23 | 5.6 | -26.7 | -26.7 | -3.8 | [footstep00.ogg](https://kenney.nl/assets/rpg-audio) | CC0 |
| `sfx/footsteps/step_dirt_02.ogg` | 0.25 | 5.6 | -27.3 | -25.0 | -2.8 | [footstep01.ogg](https://kenney.nl/assets/rpg-audio) | CC0 |
| `sfx/footsteps/step_dirt_03.ogg` | 0.24 | 5.7 | -27.5 | -27.5 | -3.6 | [footstep02.ogg](https://kenney.nl/assets/rpg-audio) | CC0 |
| `sfx/footsteps/step_dirt_04.ogg` | 0.26 | 6.3 | -28.9 | -26.2 | -3.3 | [footstep03.ogg](https://kenney.nl/assets/rpg-audio) | CC0 |
| `sfx/footsteps/step_dirt_05.ogg` | 0.28 | 6.4 | -25.7 | -25.7 | -3.5 | [footstep04.ogg](https://kenney.nl/assets/rpg-audio) | CC0 |
| `sfx/footsteps/step_dirt_06.ogg` | 0.26 | 6.4 | -27.2 | -27.2 | -3.4 | [footstep05.ogg](https://kenney.nl/assets/rpg-audio) | CC0 |
| `sfx/footsteps/step_grass_01.ogg` | 0.16 | 5.1 | -27.5 | -27.5 | -3.4 | [footstep_grass_000.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/footsteps/step_grass_02.ogg` | 0.17 | 5.1 | -25.8 | -25.8 | -3.7 | [footstep_grass_001.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/footsteps/step_grass_03.ogg` | 0.17 | 5.3 | -26.1 | -26.1 | -3.6 | [footstep_grass_002.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/footsteps/step_grass_04.ogg` | 0.15 | 5.1 | -28.5 | -28.5 | -3.3 | [footstep_grass_003.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/footsteps/step_grass_05.ogg` | 0.14 | 5.0 | -28.0 | -28.0 | -3.2 | [footstep_grass_004.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/footsteps/step_leaves_01.ogg` | 0.35 | 7.5 | -24.0 | -22.9 | -4.1 | [feet_in_leaves_2_s2889.ogg](https://bigsoundbank.com/feet-in-leaves-2-s2889.html) | CC0 |
| `sfx/footsteps/step_leaves_02.ogg` | 0.35 | 7.2 | -22.2 | -21.1 | -5.0 | [feet_in_leaves_2_s2889.ogg](https://bigsoundbank.com/feet-in-leaves-2-s2889.html) | CC0 |
| `sfx/footsteps/step_leaves_03.ogg` | 0.35 | 7.2 | -22.9 | -21.3 | -4.0 | [feet_in_leaves_2_s2889.ogg](https://bigsoundbank.com/feet-in-leaves-2-s2889.html) | CC0 |
| `sfx/footsteps/step_leaves_04.ogg` | 0.35 | 7.0 | -22.8 | -21.2 | -5.7 | [feet_in_leaves_2_s2889.ogg](https://bigsoundbank.com/feet-in-leaves-2-s2889.html) | CC0 |
| `sfx/footsteps/step_leaves_05.ogg` | 0.35 | 7.0 | -22.3 | -21.2 | -4.7 | [feet_in_leaves_2_s2889.ogg](https://bigsoundbank.com/feet-in-leaves-2-s2889.html) | CC0 |
| `sfx/footsteps/step_stone_01.ogg` | 0.10 | 4.4 | -28.7 | -28.7 | -3.4 | [footstep_concrete_000.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/footsteps/step_stone_02.ogg` | 0.10 | 4.6 | -29.2 | -29.2 | -3.6 | [footstep_concrete_001.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/footsteps/step_stone_03.ogg` | 0.11 | 4.7 | -29.8 | -29.8 | -3.5 | [footstep_concrete_002.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/footsteps/step_stone_04.ogg` | 0.11 | 4.4 | -29.1 | -29.1 | -3.6 | [footstep_concrete_003.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/footsteps/step_stone_05.ogg` | 0.11 | 4.4 | -28.4 | -28.4 | -3.3 | [footstep_concrete_004.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/footsteps/step_wood_01.ogg` | 0.27 | 4.3 | -28.3 | -28.3 | -3.3 | [footstep_wood_000.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/footsteps/step_wood_02.ogg` | 0.25 | 4.3 | -27.6 | -27.6 | -3.4 | [footstep_wood_001.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/footsteps/step_wood_03.ogg` | 0.25 | 4.2 | -27.0 | -27.0 | -3.4 | [footstep_wood_002.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/footsteps/step_wood_04.ogg` | 0.25 | 4.4 | -28.6 | -28.6 | -3.5 | [footstep_wood_003.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/footsteps/step_wood_05.ogg` | 0.25 | 4.2 | -27.3 | -27.3 | -3.4 | [footstep_wood_004.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |

### sfx/combat/

| File | s | KB | LUFS-I | LUFS-M max | dBTP | Source | Licence |
|---|---|---|---|---|---|---|---|
| `sfx/combat/arrow_hit_01.ogg` | 0.13 | 4.1 | -28.1 | -28.1 | -3.6 | [impactWood_light_000.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/combat/arrow_hit_02.ogg` | 0.13 | 4.2 | -28.4 | -28.4 | -3.4 | [impactWood_light_002.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/combat/block_01.ogg` | 0.85 | 11.0 | -21.7 | -17.2 | -2.5 | [sword_clash.1.ogg](https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes) | CC0 |
| `sfx/combat/block_02.ogg` | 0.57 | 9.0 | -20.9 | -18.2 | -3.4 | [sword_clash.3.ogg](https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes) | CC0 |
| `sfx/combat/block_03.ogg` | 0.35 | 6.8 | -19.7 | -19.7 | -2.1 | [sword_clash.5.ogg](https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes) | CC0 |
| `sfx/combat/block_04.ogg` | 0.78 | 10.7 | -25.0 | -22.1 | -2.3 | [sword_clash.7.ogg](https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes) | CC0 |
| `sfx/combat/block_05.ogg` | 0.79 | 10.8 | -25.2 | -21.1 | -3.1 | [sword_clash.9.ogg](https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes) | CC0 |
| `sfx/combat/bow_shot_01.ogg` | 0.33 | 6.5 | -24.3 | -24.3 | -3.5 | [Bow.wav](https://opengameart.org/content/battle-sound-effects) | CC0 |
| `sfx/combat/bow_shot_02.ogg` | 0.30 | 6.4 | -25.1 | -25.1 | -3.3 | [Bow.wav](https://opengameart.org/content/battle-sound-effects) | CC0 |
| `sfx/combat/dodge_01.ogg` | 0.08 | 4.5 | -24.5 | -24.5 | -3.4 | [swish-2.wav](https://opengameart.org/content/swishes-sound-pack) | CC0 |
| `sfx/combat/dodge_02.ogg` | 0.12 | 4.7 | -23.0 | -23.0 | -3.3 | [swish-5.wav](https://opengameart.org/content/swishes-sound-pack) | CC0 |
| `sfx/combat/dodge_03.ogg` | 0.16 | 5.0 | -22.4 | -22.3 | -3.3 | [swish-9.wav](https://opengameart.org/content/swishes-sound-pack) | CC0 |
| `sfx/combat/hit_flesh_01.ogg` | 0.59 | 7.9 | -22.2 | -20.3 | -3.6 | [sword_cut_s0127.ogg](https://bigsoundbank.com (sound 0127)) | CC0 |
| `sfx/combat/hit_flesh_02.ogg` | 0.98 | 12.5 | -16.0 | -14.6 | -3.5 | [sword_s0129.ogg](https://bigsoundbank.com (sound 0129)) | CC0 |
| `sfx/combat/hit_flesh_03.ogg` | 0.47 | 7.0 | -23.3 | -20.7 | -3.4 | [impactPunch_heavy_000.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/combat/hit_flesh_04.ogg` | 0.35 | 5.8 | -23.3 | -20.5 | -3.3 | [impactPunch_heavy_002.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/combat/hit_flesh_05.ogg` | 0.61 | 8.6 | -23.7 | -22.9 | -3.4 | [melee sound.wav](https://opengameart.org/content/3-melee-sounds) | CC0 |
| `sfx/combat/hit_metal_01.ogg` | 0.16 | 4.4 | -29.5 | -29.5 | -3.4 | [impactMetal_heavy_000.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/combat/hit_metal_02.ogg` | 0.36 | 4.9 | -28.8 | -28.8 | -3.4 | [impactMetal_heavy_001.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/combat/hit_metal_03.ogg` | 0.11 | 4.2 | -28.7 | -28.7 | -3.1 | [impactMetal_heavy_002.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/combat/hit_wood_01.ogg` | 0.31 | 4.2 | -26.3 | -26.3 | -3.4 | [impactWood_heavy_000.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/combat/hit_wood_02.ogg` | 0.31 | 4.2 | -26.2 | -26.2 | -3.4 | [impactWood_heavy_001.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/combat/hit_wood_03.ogg` | 0.31 | 4.2 | -26.1 | -26.1 | -3.4 | [impactWood_heavy_002.ogg](https://kenney.nl/assets/impact-sounds) | CC0 |
| `sfx/combat/player_attack_grunt_01.ogg` | 0.30 | 6.3 | -19.5 | -19.5 | -3.5 | [attack0.wav](https://opengameart.org/content/voice-clip-pack-male-adventurer-rpg) | CC0 |
| `sfx/combat/player_attack_grunt_02.ogg` | 0.28 | 6.0 | -21.4 | -19.0 | -3.0 | [attack2.wav](https://opengameart.org/content/voice-clip-pack-male-adventurer-rpg) | CC0 |
| `sfx/combat/player_attack_grunt_03.ogg` | 0.43 | 7.5 | -21.6 | -20.3 | -3.6 | [attack5.wav](https://opengameart.org/content/voice-clip-pack-male-adventurer-rpg) | CC0 |
| `sfx/combat/player_death.ogg` | 2.33 | 24.0 | -21.2 | -16.0 | -5.0 | [death0.wav](https://opengameart.org/content/voice-clip-pack-male-adventurer-rpg) | CC0 |
| `sfx/combat/player_hurt_01.ogg` | 0.52 | 8.6 | -22.0 | -18.4 | -3.7 | [hurt0.wav](https://opengameart.org/content/voice-clip-pack-male-adventurer-rpg) | CC0 |
| `sfx/combat/player_hurt_02.ogg` | 0.32 | 6.5 | -22.4 | -20.2 | -3.3 | [hurt3.wav](https://opengameart.org/content/voice-clip-pack-male-adventurer-rpg) | CC0 |
| `sfx/combat/player_hurt_03.ogg` | 0.35 | 7.0 | -22.4 | -20.3 | -3.5 | [hurt6.wav](https://opengameart.org/content/voice-clip-pack-male-adventurer-rpg) | CC0 |
| `sfx/combat/swing_01.ogg` | 0.50 | 7.9 | -21.8 | -21.8 | -3.5 | [whoosh_1_s1795.ogg](https://bigsoundbank.com (sound 1795)) | CC0 |
| `sfx/combat/swing_02.ogg` | 0.24 | 5.7 | -22.6 | -22.6 | -3.5 | [whoosh_3_s1797.ogg](https://bigsoundbank.com (sound 1797)) | CC0 |
| `sfx/combat/swing_03.ogg` | 0.29 | 6.1 | -24.0 | -21.8 | -3.6 | [whoosh_5_s1799.ogg](https://bigsoundbank.com (sound 1799)) | CC0 |
| `sfx/combat/swing_04.ogg` | 0.46 | 7.5 | -22.3 | -20.8 | -3.2 | [whoosh_7_s1801.ogg](https://bigsoundbank.com (sound 1801)) | CC0 |
| `sfx/combat/swing_heavy_01.ogg` | 0.88 | 11.9 | -17.6 | -17.0 | -3.4 | [sword.1.ogg](https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes) | CC0 |
| `sfx/combat/swing_heavy_02.ogg` | 0.54 | 8.8 | -18.5 | -17.9 | -3.4 | [sword.4.ogg](https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes) | CC0 |
| `sfx/combat/swing_heavy_03.ogg` | 0.58 | 9.4 | -18.0 | -17.0 | -3.6 | [sword.7.ogg](https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes) | CC0 |
| `sfx/combat/sword_draw.ogg` | 0.32 | 6.9 | -21.1 | -20.0 | -2.5 | [sword-unsheathe2.wav](https://opengameart.org/content/rpg-sound-pack) | CC0 |

### sfx/creatures/

| File | s | KB | LUFS-I | LUFS-M max | dBTP | Source | Licence |
|---|---|---|---|---|---|---|---|
| `sfx/creatures/bear_growl.ogg` | 0.77 | 9.4 | -18.6 | -15.4 | -3.4 | [giant2.wav](https://opengameart.org/content/rpg-sound-pack) | CC0 |
| `sfx/creatures/bear_roar_01.ogg` | 2.33 | 19.6 | -17.3 | -15.1 | -3.6 | [cat_roar_1_s1881.ogg](https://bigsoundbank.com/cat-roar-1-s1881.html) | CC0 |
| `sfx/creatures/bear_roar_02.ogg` | 1.90 | 16.3 | -17.8 | -14.8 | -3.7 | [cat_roar_3_s1883.ogg](https://bigsoundbank.com/cat-roar-3-s1883.html) | CC0 |
| `sfx/creatures/boar_grunt.ogg` | 3.88 | 32.6 | -27.9 | -21.6 | -3.2 | [grumpy_pig_2_s1659.ogg](https://bigsoundbank.com/grumpy-pig-2-s1659.html) | CC0 |
| `sfx/creatures/boar_squeal_01.ogg` | 2.98 | 29.2 | -21.9 | -18.6 | -3.1 | [grumpy_pig_1_s1658.ogg](https://bigsoundbank.com/grumpy-pig-1-s1658.html) | CC0 |
| `sfx/creatures/boar_squeal_02.ogg` | 2.85 | 26.3 | -25.5 | -21.7 | -3.2 | [grumpy_pig_2_s1659.ogg](https://bigsoundbank.com/grumpy-pig-2-s1659.html) | CC0 |
| `sfx/creatures/goblin_chatter_01.ogg` | 3.08 | 31.0 | -19.6 | -16.3 | -3.7 | [Goblin_00.mp3](https://opengameart.org/content/fantasy-sound-effects-library) | **CC-BY 3.0** |
| `sfx/creatures/goblin_chatter_02.ogg` | 2.44 | 25.1 | -20.0 | -16.4 | -2.8 | [Goblin_02.mp3](https://opengameart.org/content/fantasy-sound-effects-library) | **CC-BY 3.0** |
| `sfx/creatures/goblin_chatter_03.ogg` | 1.61 | 17.2 | -20.0 | -16.2 | -3.0 | [Goblin_04.mp3](https://opengameart.org/content/fantasy-sound-effects-library) | **CC-BY 3.0** |
| `sfx/creatures/goblin_death.ogg` | 0.32 | 6.5 | -17.7 | -16.2 | -3.6 | [hurt_02.ogg](https://opengameart.org/content/80-cc0-creature-sfx) | CC0 |
| `sfx/creatures/goblin_hurt_01.ogg` | 0.69 | 9.6 | -19.1 | -17.3 | -3.1 | [Goblin_01.mp3](https://opengameart.org/content/fantasy-sound-effects-library) | **CC-BY 3.0** |
| `sfx/creatures/goblin_hurt_02.ogg` | 0.96 | 12.4 | -20.9 | -18.8 | -3.5 | [Goblin_03.mp3](https://opengameart.org/content/fantasy-sound-effects-library) | **CC-BY 3.0** |
| `sfx/creatures/monster_death.ogg` | 1.23 | 7.1 | -18.9 | -15.6 | -3.2 | [monster_04.ogg](https://opengameart.org/content/80-cc0-creature-sfx) | CC0 |
| `sfx/creatures/monster_hurt.ogg` | 0.42 | 6.1 | -22.6 | -19.3 | -3.4 | [monster_03.ogg](https://opengameart.org/content/80-cc0-creature-sfx) | CC0 |
| `sfx/creatures/orc_hurt_01.ogg` | 0.37 | 6.5 | -21.3 | -19.8 | -3.6 | [ogre1.wav](https://opengameart.org/content/rpg-sound-pack) | CC0 |
| `sfx/creatures/orc_hurt_02.ogg` | 0.30 | 6.1 | -24.8 | -22.6 | -3.3 | [ogre5.wav](https://opengameart.org/content/rpg-sound-pack) | CC0 |
| `sfx/creatures/orc_roar_01.ogg` | 0.58 | 8.3 | -19.8 | -18.7 | -3.6 | [ogre2.wav](https://opengameart.org/content/rpg-sound-pack) | CC0 |
| `sfx/creatures/orc_roar_02.ogg` | 0.56 | 8.1 | -19.4 | -16.3 | -3.4 | [ogre3.wav](https://opengameart.org/content/rpg-sound-pack) | CC0 |
| `sfx/creatures/orc_roar_03.ogg` | 0.59 | 8.3 | -19.4 | -16.7 | -3.5 | [ogre4.wav](https://opengameart.org/content/rpg-sound-pack) | CC0 |
| `sfx/creatures/spider_hiss_01.ogg` | 0.23 | 5.5 | -24.7 | -24.7 | -3.3 | [bug_01.ogg](https://opengameart.org/content/80-cc0-creature-sfx) | CC0 |
| `sfx/creatures/spider_hiss_02.ogg` | 0.47 | 8.1 | -29.2 | -25.3 | -3.9 | [bug_02.ogg](https://opengameart.org/content/80-cc0-creature-sfx) | CC0 |
| `sfx/creatures/spider_hiss_03.ogg` | 0.33 | 6.3 | -23.8 | -21.3 | -3.1 | [bug_04.ogg](https://opengameart.org/content/80-cc0-creature-sfx) | CC0 |
| `sfx/creatures/spider_hiss_04.ogg` | 0.68 | 9.2 | -21.1 | -18.1 | -6.2 | noise | own work |
| `sfx/creatures/wolf_bark_01.ogg` | 0.48 | 7.2 | -22.3 | -19.5 | -3.5 | [small_dogs_bark_growl_s1060.ogg](https://bigsoundbank.com/small-dogs-bark-growl-s1060.html) | CC0 |
| `sfx/creatures/wolf_bark_02.ogg` | 0.35 | 6.2 | -20.1 | -19.5 | -3.3 | [small_dogs_bark_growl_s1060.ogg](https://bigsoundbank.com/small-dogs-bark-growl-s1060.html) | CC0 |
| `sfx/creatures/wolf_death.ogg` | 0.54 | 7.4 | -18.4 | -16.5 | -3.5 | [hurt_05.ogg](https://opengameart.org/content/80-cc0-creature-sfx) | CC0 |
| `sfx/creatures/wolf_growl_01.ogg` | 2.79 | 23.4 | -17.3 | -14.0 | -7.3 | [growling_cat_1_s1885.ogg](https://bigsoundbank.com/growling-cat-1-s1885.html) | CC0 |
| `sfx/creatures/wolf_growl_02.ogg` | 7.41 | 58.4 | -18.1 | -14.7 | -3.3 | [growling_cat_3_s1887.ogg](https://bigsoundbank.com/growling-cat-3-s1887.html) | CC0 |
| `sfx/creatures/wolf_howl_01.ogg` | 2.08 | 20.2 | -18.1 | -16.0 | -6.2 | [dog_singing_1_s2450.ogg](https://bigsoundbank.com/dog-singing-1-s2450.html) | CC0 |
| `sfx/creatures/wolf_howl_02.ogg` | 0.73 | 9.0 | -18.8 | -15.9 | -4.8 | [howl.ogg](https://opengameart.org/content/80-cc0-creature-sfx) | CC0 |
| `sfx/creatures/wolf_hurt_01.ogg` | 0.45 | 7.1 | -23.2 | -20.7 | -3.7 | [hurt_01.ogg](https://opengameart.org/content/80-cc0-creature-sfx) | CC0 |
| `sfx/creatures/wolf_hurt_02.ogg` | 0.42 | 6.8 | -19.8 | -18.0 | -3.3 | [hurt_03.ogg](https://opengameart.org/content/80-cc0-creature-sfx) | CC0 |
| `sfx/creatures/wyvern_screech_01.ogg` | 3.30 | 30.4 | -20.6 | -16.9 | -3.2 | [Dragon_Growl_00.mp3](https://opengameart.org/content/fantasy-sound-effects-library) | **CC-BY 3.0** |
| `sfx/creatures/wyvern_screech_02.ogg` | 4.25 | 38.4 | -18.0 | -16.0 | -3.3 | [Dragon_Growl_01.mp3](https://opengameart.org/content/fantasy-sound-effects-library) | **CC-BY 3.0** |
| `sfx/creatures/wyvern_screech_03.ogg` | 1.63 | 17.0 | -16.0 | -14.3 | -3.7 | [cat_roar_1_s1881.ogg](https://bigsoundbank.com/cat-roar-1-s1881.html) | CC0 |

### sfx/animals/

| File | s | KB | LUFS-I | LUFS-M max | dBTP | Source | Licence |
|---|---|---|---|---|---|---|---|
| `sfx/animals/chicken_01.ogg` | 3.14 | 24.9 | -25.3 | -22.4 | -3.5 | [annoyed_hen_s0453.ogg](https://bigsoundbank.com/annoyed-hen-s0453.html) | CC0 |
| `sfx/animals/chicken_cluck_01.ogg` | 1.01 | 12.1 | -18.8 | -17.1 | -3.6 | [hen_lays_1_s0975.ogg](https://bigsoundbank.com/hen-lays-1-s0975.html) | CC0 |
| `sfx/animals/chicken_cluck_02.ogg` | 0.81 | 10.5 | -18.8 | -17.0 | -3.1 | [hen_lays_1_s0975.ogg](https://bigsoundbank.com/hen-lays-1-s0975.html) | CC0 |
| `sfx/animals/chicken_cluck_03.ogg` | 0.82 | 10.7 | -18.2 | -17.0 | -6.2 | [hen_lays_1_s0975.ogg](https://bigsoundbank.com/hen-lays-1-s0975.html) | CC0 |
| `sfx/animals/chicken_scared.ogg` | 5.87 | 48.9 | -23.9 | -17.2 | -6.7 | [hen_scared_s1040.ogg](https://bigsoundbank.com/hen-scared-s1040.html) | CC0 |
| `sfx/animals/cow_01.ogg` | 2.16 | 21.4 | -19.8 | -17.0 | -7.5 | [cow_moos_2_s2382.ogg](https://bigsoundbank.com/cow-moos-2-s2382.html) | CC0 |
| `sfx/animals/cow_02.ogg` | 2.28 | 21.2 | -19.7 | -17.0 | -8.5 | [cow_moos_4_s2384.ogg](https://bigsoundbank.com/cow-moos-4-s2384.html) | CC0 |
| `sfx/animals/cow_far_01.ogg` | 1.66 | 17.6 | -19.7 | -16.9 | -6.9 | [cow_moos_s0546.ogg](https://bigsoundbank.com/cow-moos-s0546.html) | CC0 |
| `sfx/animals/cow_far_02.ogg` | 1.84 | 17.8 | -19.3 | -16.9 | -8.7 | [cow_moos_s0546.ogg](https://bigsoundbank.com/cow-moos-s0546.html) | CC0 |
| `sfx/animals/dog_bark_01.ogg` | 0.31 | 5.8 | -20.7 | -19.4 | -3.4 | [barking_dog_2_s2954.ogg](https://bigsoundbank.com/barking-dog-2-s2954.html) | CC0 |
| `sfx/animals/dog_bark_02.ogg` | 0.31 | 5.8 | -22.1 | -20.0 | -3.4 | [barking_dog_2_s2954.ogg](https://bigsoundbank.com/barking-dog-2-s2954.html) | CC0 |
| `sfx/animals/dog_bark_03.ogg` | 0.31 | 5.9 | -21.7 | -19.9 | -3.4 | [barking_dog_2_s2954.ogg](https://bigsoundbank.com/barking-dog-2-s2954.html) | CC0 |
| `sfx/animals/donkey.ogg` | 6.38 | 52.9 | -23.7 | -17.1 | -4.9 | [donkey_braying_1_s1549.ogg](https://bigsoundbank.com/donkey-braying-1-s1549.html) | CC0 |
| `sfx/animals/goat.ogg` | 1.23 | 14.3 | -19.9 | -16.9 | -10.7 | [goat_1_s1380.ogg](https://bigsoundbank.com/goat-1-s1380.html) | CC0 |
| `sfx/animals/horse_neigh_01.ogg` | 1.64 | 17.2 | -19.8 | -17.1 | -5.3 | [horse_neigh_1_s0284.ogg](https://bigsoundbank.com (sound 0284)) | CC0 |
| `sfx/animals/horse_neigh_02.ogg` | 1.33 | 14.6 | -20.1 | -17.1 | -8.1 | [horse_neigh_4_s1542.ogg](https://bigsoundbank.com (sound 1542)) | CC0 |
| `sfx/animals/horse_snort.ogg` | 0.66 | 8.7 | -21.8 | -20.2 | -8.3 | [horse_breath_s1543.ogg](https://bigsoundbank.com (sound 1543)) | CC0 |
| `sfx/animals/pig_01.ogg` | 3.42 | 32.8 | -21.9 | -19.0 | -2.9 | [grumpy_pig_1_s1658.ogg](https://bigsoundbank.com/grumpy-pig-1-s1658.html) | CC0 |
| `sfx/animals/pig_02.ogg` | 3.14 | 28.2 | -25.4 | -21.3 | -3.3 | [grumpy_pig_2_s1659.ogg](https://bigsoundbank.com/grumpy-pig-2-s1659.html) | CC0 |
| `sfx/animals/rooster_01.ogg` | 6.01 | 49.7 | -18.7 | -17.1 | -7.5 | [rooster_s0104.ogg](https://bigsoundbank.com/rooster-s0104.html) | CC0 |
| `sfx/animals/rooster_02.ogg` | 2.32 | 21.0 | -19.9 | -17.0 | -8.3 | [song_of_rooster_s0283.ogg](https://bigsoundbank.com/song-of-rooster-s0283.html) | CC0 |
| `sfx/animals/sheep_01.ogg` | 0.76 | 9.6 | -19.2 | -17.1 | -4.8 | [sheep_1_s2343.ogg](https://bigsoundbank.com/sheep-1-s2343.html) | CC0 |
| `sfx/animals/sheep_02.ogg` | 0.81 | 10.0 | -19.1 | -17.0 | -5.5 | [sheep_3_s2345.ogg](https://bigsoundbank.com/sheep-3-s2345.html) | CC0 |
| `sfx/animals/sheep_03.ogg` | 0.83 | 10.4 | -19.0 | -17.1 | -6.4 | [sheep_5_s2347.ogg](https://bigsoundbank.com/sheep-5-s2347.html) | CC0 |

### sfx/world/

| File | s | KB | LUFS-I | LUFS-M max | dBTP | Source | Licence |
|---|---|---|---|---|---|---|---|
| `sfx/world/anvil_01.ogg` | 1.16 | 13.1 | -23.0 | -18.0 | -4.6 | [anvil_blacksmith_2_s3590.ogg](https://bigsoundbank.com (sound 3590)) | CC0 |
| `sfx/world/anvil_02.ogg` | 1.13 | 12.6 | -22.3 | -18.0 | -4.5 | [anvil_blacksmith_2_s3590.ogg](https://bigsoundbank.com (sound 3590)) | CC0 |
| `sfx/world/anvil_03.ogg` | 1.21 | 13.4 | -21.4 | -18.0 | -8.2 | [anvil_blacksmith_2_s3590.ogg](https://bigsoundbank.com (sound 3590)) | CC0 |
| `sfx/world/bell_tower.ogg` | 4.57 | 38.7 | -23.3 | -18.0 | -6.6 | [bell_tower_s3446.ogg](https://bigsoundbank.com (sound 3446)) | CC0 |
| `sfx/world/book_open.ogg` | 0.15 | 5.3 | -28.8 | -28.8 | -3.7 | [bookOpen.ogg](https://kenney.nl/assets/rpg-audio) | CC0 |
| `sfx/world/chop_wood.ogg` | 0.23 | 5.6 | -23.2 | -23.2 | -3.7 | [chop.ogg](https://kenney.nl/assets/rpg-audio) | CC0 |
| `sfx/world/cloth.ogg` | 0.37 | 6.7 | -26.1 | -23.3 | -3.5 | [cloth2.ogg](https://kenney.nl/assets/rpg-audio) | CC0 |
| `sfx/world/coins.ogg` | 0.73 | 11.7 | -28.2 | -26.6 | -2.8 | [handleCoins.ogg](https://kenney.nl/assets/rpg-audio) | CC0 |
| `sfx/world/coins_02.ogg` | 0.32 | 7.7 | -25.7 | -23.6 | -4.4 | [handleCoins2.ogg](https://kenney.nl/assets/rpg-audio) | CC0 |
| `sfx/world/door_close.ogg` | 0.57 | 9.5 | -21.5 | -18.2 | -3.6 | [doorClose_2.ogg](https://kenney.nl/assets/rpg-audio) | CC0 |
| `sfx/world/door_open.ogg` | 0.92 | 12.2 | -22.1 | -20.8 | -3.4 | [doorOpen_1.ogg](https://kenney.nl/assets/rpg-audio) | CC0 |
| `sfx/world/hammer_nail_01.ogg` | 0.10 | 4.5 | -30.2 | -30.2 | -2.9 | [nail_and_hammer_1_s0005.ogg](https://bigsoundbank.com/nail-and-hammer-1-s0005.html) | CC0 |
| `sfx/world/hammer_nail_02.ogg` | 0.09 | 4.4 | -30.2 | -30.2 | -3.4 | [nail_and_hammer_1_s0005.ogg](https://bigsoundbank.com/nail-and-hammer-1-s0005.html) | CC0 |
| `sfx/world/hammer_nail_03.ogg` | 0.09 | 4.4 | -30.3 | -30.3 | -2.7 | [nail_and_hammer_1_s0005.ogg](https://bigsoundbank.com/nail-and-hammer-1-s0005.html) | CC0 |

### ui/

| File | s | KB | LUFS-I | LUFS-M max | dBTP | Source | Licence |
|---|---|---|---|---|---|---|---|
| `ui/close.ogg` | 0.31 | 6.9 | -22.9 | -19.6 | -7.3 | [close_002.ogg](https://kenney.nl/assets/interface-sounds) | CC0 |
| `ui/coin.ogg` | 0.32 | 7.2 | -22.2 | -20.4 | -2.5 | [Pickup_Gold_00.mp3](https://opengameart.org/content/fantasy-sound-effects-library) | **CC-BY 3.0** |
| `ui/coin_02.ogg` | 0.27 | 6.5 | -24.1 | -24.1 | -3.6 | [Pickup_Gold_02.mp3](https://opengameart.org/content/fantasy-sound-effects-library) | **CC-BY 3.0** |
| `ui/confirm.ogg` | 0.54 | 6.7 | -21.3 | -19.0 | -8.2 | [confirmation_002.ogg](https://kenney.nl/assets/interface-sounds) | CC0 |
| `ui/defeat.ogg` | 5.97 | 47.7 | -20.6 | -16.0 | -4.1 | [Jingle_Lose_00.mp3](https://opengameart.org/content/fantasy-sound-effects-library) | **CC-BY 3.0** |
| `ui/error.ogg` | 0.10 | 4.8 | -23.5 | -23.5 | -3.3 | [error_004.ogg](https://kenney.nl/assets/interface-sounds) | CC0 |
| `ui/level_up.ogg` | 3.58 | 31.4 | -22.4 | -18.7 | -3.5 | [Jingle_Achievement_00.mp3](https://opengameart.org/content/fantasy-sound-effects-library) | **CC-BY 3.0** |
| `ui/menu_open.ogg` | 0.37 | 7.4 | -29.1 | -26.9 | -3.3 | [Inventory_Open_00.mp3](https://opengameart.org/content/fantasy-sound-effects-library) | **CC-BY 3.0** |
| `ui/open.ogg` | 0.31 | 6.9 | -20.2 | -19.5 | -7.8 | [open_002.ogg](https://kenney.nl/assets/interface-sounds) | CC0 |
| `ui/quest_accepted.ogg` | 0.95 | 11.1 | -18.0 | -16.0 | -6.6 | [jingles_PIZZI02.ogg](https://kenney.nl/assets/music-jingles) | CC0 |
| `ui/quest_complete.ogg` | 9.31 | 82.4 | -19.0 | -16.1 | -4.3 | [Jingle_Win_00.mp3](https://opengameart.org/content/fantasy-sound-effects-library) | **CC-BY 3.0** |
| `ui/select.ogg` | 0.04 | 4.1 | -28.3 | -28.3 | -3.4 | [select_002.ogg](https://kenney.nl/assets/interface-sounds) | CC0 |
| `ui/tap.ogg` | 0.08 | 4.5 | -35.2 | -35.2 | -4.6 | [click3.ogg](https://kenney.nl/assets/ui-audio) | CC0 |
| `ui/tap_02.ogg` | 0.01 | 3.8 | -28.2 | -28.2 | -3.2 | [click_002.ogg](https://kenney.nl/assets/interface-sounds) | CC0 |

## Sources and licences

| Source | Licence | Where | Verified |
|---|---|---|---|
| BigSoundBank (Joseph Sardin) | CC0 | https://bigsoundbank.com/droit.html | 2026-09-27, source page |
| rubberduck, 80 CC0 creature SFX | CC0 | https://opengameart.org/content/80-cc0-creature-sfx | 2026-09-27, source page |
| rubberduck, 100 CC0 SFX | CC0 | https://opengameart.org/content/100-cc0-sfx | 2026-09-27, source page |
| artisticdude, RPG Sound Pack | CC0 | https://opengameart.org/content/rpg-sound-pack | 2026-09-27, source page |
| Little Robot Sound Factory, Fantasy Sound Effects Library | **CC-BY 3.0** | https://opengameart.org/content/fantasy-sound-effects-library | 2026-09-27, source page |
| Kenney, Impact Sounds | CC0 | https://kenney.nl/assets/impact-sounds | 2026-09-27, source page |
| Kenney, RPG Audio | CC0 | https://kenney.nl/assets/rpg-audio | 2026-09-27, source page |
| Kenney, Interface Sounds | CC0 | https://kenney.nl/assets/interface-sounds | 2026-09-27, source page |
| Kenney, UI Audio | CC0 | https://kenney.nl/assets/ui-audio | 2026-09-27, source page |
| Kenney, Music Jingles | CC0 | https://kenney.nl/assets/music-jingles | 2026-09-27, source page |
| wolfwoot, Voice Clip Pack Male Adventurer | CC0 | https://opengameart.org/content/voice-clip-pack-male-adventurer-rpg | 2026-09-27, source page |
| congusbongus, Footsteps on different surfaces | **CC-BY 3.0** | https://opengameart.org/content/footsteps-on-different-surfaces | 2026-09-27, source page |
| StarNinjas, 20 Sword Sound Effects | CC0 | https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes | 2026-09-27, source page |
| artisticdude, Swishes Sound Pack | CC0 | https://opengameart.org/content/swishes-sound-pack | 2026-09-27, source page |
| Ogrebane, Battle Sound Effects (CC0 option) | CC0 | https://opengameart.org/content/battle-sound-effects | 2026-09-27, source page |
| remaxim, 3 Melee sounds | CC0 | https://opengameart.org/content/3-melee-sounds | 2026-09-27, source page |
| Ylmir, Rain (loopable) | CC0 | https://opengameart.org/content/rain-loopable | 2026-09-27, source page |
| Wolfgang_, Crickets Ambient Noise (loopable) | CC0 | https://opengameart.org/content/crickets-ambient-noise-loopable | 2026-09-27, source page |
| RandomMind, Medieval: Market Day | CC0 | https://opengameart.org/content/medieval-market-day | 2026-09-27, source page |
| RandomMind, Medieval: Minstrel Dance | CC0 | https://opengameart.org/content/medieval-minstrel-dance | 2026-09-27, source page |
| RandomMind, Medieval: The Old Tower Inn | CC0 | https://opengameart.org/content/medieval-the-old-tower-inn | 2026-09-27, source page |
| RandomMind, Medieval: The Bard's Tale | CC0 | https://opengameart.org/content/medieval-the-bards-tale | 2026-09-27, source page |
| RandomMind, Medieval: King's Feast | CC0 | https://opengameart.org/content/medieval-kings-feast | 2026-09-27, source page |
| Umplix, Medieval Theme | CC0 | https://opengameart.org/content/medieval-theme | 2026-09-27, source page |
| Umplix, Medieval Standoff (first 7 s) | CC0 | https://opengameart.org/content/medieval-standoff | 2026-09-27, source page |
| Of Far Different Nature, Dowland 1597 | CC0 | https://opengameart.org/content/historic-renaissance-music-from-1597-if-my-complaints-could-passions-move-by-john-dowland | 2026-09-27, source page |
| cynicmusic, Battle Theme A | CC0 | https://opengameart.org/content/battle-theme-a | 2026-09-27, source page |
| generated for the game (filtered noise) | own work | - | 2026-09-27, source page |

CC-BY credits are in `kingdom/CREDITS.md` (shown in the in-game Credits screen). New BigSoundBank downloads and their per-sound page URLs: `assets/incoming/audio/bigsoundbank/LICENSE.txt` (folder has a `.gdignore`; only the processed files here ship).

## Rebuild

```bash
py tools/audio/build_audio.py            # all (about 5 min), or a prefix: sfx/combat, ambience/amb_tavern
py tools/audio/write_readme.py            # this file
```
Needs ffmpeg/ffprobe and Python 3 + numpy. `loudness.csv` is rewritten by every build (ffmpeg `ebur128`, 0.6 s padding so short sounds get a reading).

## Naming for the director

`<name>_NN.ogg` variants are picked at random by `Audio.play_sfx("<name>", pos)`; `Audio.play_sfx("<name>_NN")` plays one exact file. Footsteps: `step_<surface>` with surface grass, dirt, cobble, stone, wood, leaves.

