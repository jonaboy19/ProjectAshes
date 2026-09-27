#!/usr/bin/env bash
# Caption banners on copies of the store screenshots (Cinzel + IM Fell English, OFL).
# Reads store/screenshots/<size>/NN_*.png, writes store/screenshots/captioned/<size>/NN_*.png.
# Captions: tools/store/captions.txt ("NN|HEADLINE|sub line").
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SHOTS="$REPO/store/screenshots"
FONTS="$REPO/kingdom/assets/incoming/fonts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# drawtext needs simple relative font paths (no drive colons or brackets): work in $TMP.
cp "$FONTS/cinzel/Cinzel[wght].ttf" "$TMP/cinzel.ttf"
cp "$FONTS/imfellenglish/IMFeENit28P.ttf" "$TMP/fell_it.ttf"
cd "$TMP"
for dir in phone_1920x1080 iphone65_2688x1242; do
	mkdir -p "$SHOTS/captioned/$dir"
	for src in "$SHOTS/$dir"/[0-9][0-9]_*.png; do
		name="$(basename "$src")"
		nn="${name:0:2}"
		line="$(grep "^$nn|" "$HERE/captions.txt")"
		printf '%s' "$(echo "$line" | cut -d'|' -f2)" > head.txt
		printf '%s' "$(echo "$line" | cut -d'|' -f3)" > sub.txt
		IFS=, read -r W H < <(ffprobe -v error -show_entries stream=width,height -of csv=p=0 "$src")
		k=$(awk "BEGIN{print $H/1080}")
		hs=$(awk "BEGIN{printf \"%d\", 60*$k}")      # headline size
		ss=$(awk "BEGIN{printf \"%d\", 38*$k}")      # sub-line size
		band=$(awk "BEGIN{printf \"%d\", 320*$k}")   # gradient band height
		hy=$(awk "BEGIN{printf \"%d\", $H-150*$k}")  # headline baseline area
		sy=$(awk "BEGIN{printf \"%d\", $H-78*$k}")
		sh=$(awk "BEGIN{printf \"%d\", 3*$k}")
		ffmpeg -loglevel error -y -i "$src" -filter_complex "\
color=c=0x0e1019:s=${W}x${band},format=rgba,geq=r='14':g='16':b='25':a='255*pow(Y/H,1.1)*0.94'[g];\
[0][g]overlay=0:H-h[b];\
[b]drawtext=fontfile=cinzel.ttf:textfile=head.txt:fontsize=$hs:fontcolor=0xf5c35a:borderw=$sh:bordercolor=0x0e1019@0.7:x=(w-tw)/2:y=$hy-th/2:shadowcolor=0x000000@0.85:shadowx=$sh:shadowy=$sh,\
drawtext=fontfile=fell_it.ttf:textfile=sub.txt:fontsize=$ss:fontcolor=0xf2efe8:x=(w-tw)/2:y=$sy-th/2:shadowcolor=0x000000@0.85:shadowx=$sh:shadowy=$sh" \
			-frames:v 1 -pix_fmt rgb24 "$SHOTS/captioned/$dir/$name"
		echo "captioned $dir/$name"
	done
done
