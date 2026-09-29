#!/usr/bin/env bash
# before/after attack comparison: compare.sh <creature> <orig.glb> <new.glb> <out.jpg> "<before frames>" "<after frames>" [view=side] [cols=10]
cr=$1; a=$2; b=$3; out=$4; fa=$5; fb=$6; view=${7:-side}; cols=${8:-10}
D=$(dirname "$0"); T=${WORK:-/c/Users/Jonna/mqw}
W=${W:-300} bash $D/strip.sh ${cr}_a "$a" $T/cmp_a.jpg attack "$fa" "$view" $cols
W=${W:-300} bash $D/strip.sh ${cr}_b "$b" $T/cmp_b.jpg attack "$fb" "$view" $cols
ffmpeg -v error -y -i $T/cmp_a.jpg -i $T/cmp_b.jpg -filter_complex "[0]drawtext=text='BEFORE':x=w-90:y=8:fontsize=22:fontcolor=yellow:fontfile='C\:/Windows/Fonts/arial.ttf'[a];[1]drawtext=text='AFTER':x=w-80:y=8:fontsize=22:fontcolor=lime:fontfile='C\:/Windows/Fonts/arial.ttf'[b];[a][b]vstack" -q:v 4 "$out"; rm -f $T/cmp_a.jpg $T/cmp_b.jpg
