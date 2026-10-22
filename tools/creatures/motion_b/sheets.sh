#!/usr/bin/env bash
# usage: sheets.sh <frames_root> <clip> <src_fps> <out_prefix> [sample_fps] [cols] [rows] [tilew]
# hstacks side+front frames, tiles them with tools/qa/video_to_sheets.sh, converts to jpg, deletes the PNGs.
R=$1; C=$2; SF=$3; OUT=$4; FPS=${5:-15}; COLS=${6:-3}; ROWS=${7:-4}; TW=${8:-380}
REPO=/c/Users/Jonna/Documents/PA_wt_creature
D=$R/$C; mkdir -p $D/both $D/sh
ffmpeg -v error -y -framerate 30 -i $D/side/frame%08d.png -framerate 30 -i $D/front/frame%08d.png -filter_complex hstack $D/both/frame%08d.png
SRC_FPS=$SF bash $REPO/tools/qa/video_to_sheets.sh $D/both $D/sh $FPS $COLS $ROWS $((TW*2)) >/dev/null
i=0; for f in $D/sh/sheet_*.png; do i=$((i+1)); ffmpeg -v error -y -i $f -q:v 4 ${OUT}_sheet_$i.jpg; done
[ -f $D/sh/motion.png ] && ffmpeg -v error -y -i $D/sh/motion.png -q:v 5 ${OUT}_motion.jpg
rm -rf $D
ls -la ${OUT}_*.jpg
