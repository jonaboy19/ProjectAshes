#!/usr/bin/env bash
# Google Play feature graphic (1024x500): real in-game key art (Ashford, Ultra, captured by
# store_shots.gd at 2048x1000) + the title logo. No small text.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
KEY="${1:-$REPO/store/_work/keyart_2048x1000.png}"
LOGO="$REPO/store/logo/rising_ashes_logo.png"
OUT="$REPO/store/feature_graphic/play_feature_graphic_1024x500.png"
ffmpeg -loglevel error -y -i "$KEY" -i "$LOGO" -filter_complex "\
[0]scale=1024:500:flags=lanczos,eq=saturation=1.08:contrast=1.04[bg];\
color=c=0x0e1019:s=1024x500,format=rgba,geq=r='14':g='16':b='25':a='255*(0.78*pow(max(0,1-Y/260),1.4)+0.35*pow(Y/H,3))'[shade];\
color=c=0xff7a1a:s=1024x500,format=rgba,geq=r='255':g='122':b='26':a='255*0.16*pow(max(0,1-hypot((X-512)/520,(Y-500)/260)),1.5)'[ember];\
[bg][shade]overlay[b1];[b1][ember]overlay[b2];\
[1]scale=720:-1:flags=lanczos[logo];[b2][logo]overlay=(W-w)/2:62" -frames:v 1 -pix_fmt rgb24 "$OUT"
echo "$OUT"
