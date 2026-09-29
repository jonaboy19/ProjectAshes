#!/usr/bin/env bash
# Latency-free loudness normalisation for seamless loops: measure integrated LUFS (ebur128), apply a pure gain
# (no loudnorm/alimiter, whose lookahead delay would break the loop seam), soft-clip stray peaks, encode OGG.
# usage: r1_loopnorm.sh in.wav out.ogg target_lufs quality [channels]
set -euo pipefail
in=$1; out=$2; tgt=$3; q=${4:-4}
cur=$(ffmpeg -nostdin -hide_banner -i "$in" -af ebur128 -f null - 2>&1 | sed -n '/Summary:/,$p' | awk '/^ *I:/{print $2}')
g=$(awk -v t="$tgt" -v c="$cur" 'BEGIN{printf "%.2f", t-c}')
ffmpeg -nostdin -v error -y -i "$in" -af "volume=${g}dB,asoftclip=type=sin:threshold=0.85" -c:a libvorbis -q:a "$q" "$out"
echo "$out: source ${cur} LUFS, gain ${g} dB"
