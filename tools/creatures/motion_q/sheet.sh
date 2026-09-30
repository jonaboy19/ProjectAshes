#!/usr/bin/env bash
# usage: sheet.sh <frames_dir> <out_dir> <src_fps> [cols=5 rows=4 w=320] ; makes sheet_NNN.png + motion.png from frame*.png, then
# converts to <out_dir>/<name>_sheet_N.jpg if a NAME (env) is given, and deletes the source frames.
d=$1; o=$2; sf=$3; cols=${4:-5}; rows=${5:-4}; w=${6:-320}
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SRC_FPS=$sf bash "$ROOT/tools/qa/video_to_sheets.sh" "$d" "$o" "$sf" "$cols" "$rows" "$w"
