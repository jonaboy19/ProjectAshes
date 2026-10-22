#!/usr/bin/env bash
# L17 Region 1 music: seamless crossfade loop + loudnorm -16 LUFS (two-pass linear) + OGG Vorbis q2.
# usage: r1_music.sh   (run from repo root; needs ffmpeg on PATH)
set -euo pipefail
IN=kingdom/assets/incoming
OUT=kingdom/assets/audio/region1/music
TMP=${TMPDIR:-/tmp}/r1m
mkdir -p "$OUT" "$TMP"
XF=4
# name | source | start s | loop length s
while IFS='|' read -r name src ss len; do
  wav="$TMP/$name.wav"; nrm="$TMP/${name}_n.wav"
  ffmpeg -nostdin -v error -y -ss "$ss" -i "$src" -filter_complex \
   "[0:a]aresample=44100,aformat=channel_layouts=stereo,asplit=3[a][b][c];
    [a]atrim=0:$XF,asetpts=PTS-STARTPTS[h];
    [b]atrim=$len:$(( len + XF )),asetpts=PTS-STARTPTS[t];
    [c]atrim=$XF:$len,asetpts=PTS-STARTPTS[bd];
    [t][h]acrossfade=d=$XF:c1=qsin:c2=qsin[m];[m][bd]concat=n=2:v=0:a=1[o]" -map "[o]" "$wav"
  bash kingdom/tools/audio/r1_loopnorm.sh "$wav" "$OUT/$name.ogg" -16 2
done <<LIST
mus_r1_village_day|$IN/incompetech/Folk Round.mp3|0|100
mus_r1_guild_town|$IN/incompetech/Minstrel Guild.mp3|0|100
mus_r1_highwatch_keep|$IN/music-cc-by/alexander-nakarada_medieval-chateau.mp3|0|100
mus_r1_forest_glade|$IN/incompetech/Achaidh Cheide.mp3|0|100
mus_r1_rift_wilds|$IN/incompetech/Lost Time.mp3|0|100
mus_r1_night|$IN/incompetech/Suonatore di Liuto.mp3|0|100
mus_r1_boss_warden|$IN/incompetech/Crusade.mp3|0|110
LIST
